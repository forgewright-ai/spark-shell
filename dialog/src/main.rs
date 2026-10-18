//! spark-dialog: the terminal, the event loop, the helpers. Run by
//! `spark-shell dialog` in a foot window of 60 by 44 cells.

use ratatui::backend::CrosstermBackend;
use ratatui::buffer::Buffer;
use ratatui::crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind};
use ratatui::crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::crossterm::{execute, queue};
use ratatui::layout::Rect;
use ratatui::Terminal;
use spark_dialog::app::{App, Config, Helper, Job, HEIGHT, WIDTH};
use spark_dialog::mcp::{Incoming, Server};
use spark_dialog::palette::Palette;
use spark_dialog::{sixel, ui};
use std::io::Write;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const USAGE: &str = "spark-dialog -- the spark dialog, one window for every domain (run by spark-shell dialog)

  spark-dialog [--provider \"PATH WORDS\"]... [--home SECTION] [--title TEXT]
               [--mark on|off] [--close on|off] [--progress on|off]
               [--composer plus,model,talk] [--attach \"txt md\"]
               [--spark-shell PATH] [--spark PATH]
";

enum Ev {
    Term(Event),
    Mcp(Incoming),
    Tick,
    Helper(Helper, Result<String, String>),
}

struct Args {
    cfg: Config,
    providers: Vec<(String, Vec<String>)>,
}

fn onoff(v: &str) -> Result<bool, String> {
    match v {
        "on" => Ok(true),
        "off" => Ok(false),
        _ => Err(format!("{} is on or off", v)),
    }
}

fn args() -> Result<Args, String> {
    let mut cfg = Config::default();
    let mut providers = vec![];
    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        let mut val = |name: &str| it.next().ok_or_else(|| format!("{} takes a value", name));
        match a.as_str() {
            "-h" | "--help" | "help" => return Err(String::new()),
            "--provider" => {
                let words: Vec<String> = val("--provider")?.split_whitespace().map(String::from).collect();
                spark_dialog::mcp::argv_ok(&words)?;
                let label = words.last().cloned().unwrap_or_default();
                providers.push((label, words));
            }
            "--home" => cfg.home = Some(val("--home")?),
            "--title" => cfg.title = Some(val("--title")?),
            "--mark" => cfg.mark = onoff(&val("--mark")?)?,
            "--close" => cfg.close = onoff(&val("--close")?)?,
            "--progress" => cfg.progress = onoff(&val("--progress")?)?,
            "--composer" => {
                let v = val("--composer")?;
                let w: Vec<&str> = v.split(',').map(str::trim).filter(|s| !s.is_empty()).collect();
                if let Some(bad) = w.iter().find(|x| !["plus", "model", "talk"].contains(x)) {
                    return Err(format!("{}: the composer takes plus, model and talk", bad));
                }
                cfg.plus = w.contains(&"plus");
                cfg.model = w.contains(&"model");
                cfg.talk = w.contains(&"talk");
            }
            "--attach" => cfg.attach = val("--attach")?.split_whitespace().map(String::from).collect(),
            "--spark-shell" => cfg.spark_shell = val("--spark-shell")?,
            "--spark" => cfg.spark = val("--spark")?,
            other => return Err(format!("no option {}", other)),
        }
    }
    Ok(Args { cfg, providers })
}

/// The date and the time, the home dialog's title: the machine's own clock and zone.
fn clock() -> String {
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let mut b = [0u8; 64];
        let f = b"%A %d %B \xc2\xb7 %H:%M\0";
        let n = libc::strftime(b.as_mut_ptr() as *mut libc::c_char, b.len(), f.as_ptr() as *const libc::c_char, &tm);
        String::from_utf8_lossy(&b[..n]).into_owned()
    }
}

/// The ids of the panel's recent picks (SECTION<tab>ACTION ARG), newest first.
fn recent() -> Vec<String> {
    let base = std::env::var("XDG_STATE_HOME")
        .ok()
        .filter(|s| s.starts_with('/'))
        .or_else(|| std::env::var("HOME").ok().map(|h| h + "/.local/state"));
    let Some(b) = base else { return vec![] };
    std::fs::read_to_string(format!("{}/spark-shell/panel/recent", b))
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.split_once('\t').map(|(s, a)| format!("{}:{}", s, a)))
        .take(5)
        .collect()
}

fn run_job(job: Job, tx: mpsc::Sender<Ev>, listening: Arc<Mutex<Option<u32>>>) {
    match job {
        Job::StopListening => {
            if let Some(pid) = *listening.lock().unwrap() {
                unsafe {
                    libc::kill(pid as libc::pid_t, libc::SIGINT);
                }
            }
        }
        Job::Run(h, argv) => {
            std::thread::spawn(move || {
                let Some((cmd, rest)) = argv.split_first() else { return };
                let child = std::process::Command::new(cmd)
                    .args(rest)
                    .stdin(std::process::Stdio::null())
                    .stdout(std::process::Stdio::piped())
                    .stderr(std::process::Stdio::piped())
                    .spawn();
                let out = match child {
                    Err(e) => Err(format!("{}: {}", cmd, e)),
                    Ok(c) => {
                        if h == Helper::Listen {
                            *listening.lock().unwrap() = Some(c.id());
                        }
                        let o = c.wait_with_output();
                        if h == Helper::Listen {
                            *listening.lock().unwrap() = None;
                        }
                        match o {
                            Ok(o) if o.status.success() => Ok(String::from_utf8_lossy(&o.stdout).into_owned()),
                            Ok(o) => {
                                let so = String::from_utf8_lossy(&o.stdout).into_owned();
                                Err(if so.trim().is_empty() {
                                    String::from_utf8_lossy(&o.stderr).into_owned()
                                } else {
                                    so
                                })
                            }
                            Err(e) => Err(e.to_string()),
                        }
                    }
                };
                let _ = tx.send(Ev::Helper(h, out));
            });
        }
    }
}

fn main() {
    let a = match args() {
        Ok(a) => a,
        Err(e) => {
            if e.is_empty() {
                print!("{}", USAGE);
                std::process::exit(0);
            }
            println!("spark-dialog -- {}; spark-dialog -h lists the options", e);
            std::process::exit(2);
        }
    };
    let pal = Palette::from_env();
    let labels: Vec<String> = a.providers.iter().map(|(l, _)| l.clone()).collect();
    let mut app = App::new(a.cfg, &labels);
    app.recent = recent();
    let (tx, rx) = mpsc::channel::<Ev>();
    let (mtx, mrx) = mpsc::sync_channel::<Incoming>(256);
    for (i, (label, argv)) in a.providers.iter().enumerate() {
        match Server::spawn(i, label, argv, mtx.clone()) {
            Ok(s) => app.servers.push(s),
            Err(e) => app.providers[i].dead = Some(e),
        }
    }
    {
        let tx = tx.clone();
        std::thread::spawn(move || {
            while let Ok(m) = mrx.recv() {
                if tx.send(Ev::Mcp(m)).is_err() {
                    return;
                }
            }
        });
    }
    {
        let tx = tx.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_millis(120));
            if tx.send(Ev::Tick).is_err() {
                return;
            }
        });
    }
    {
        let tx = tx.clone();
        std::thread::spawn(move || loop {
            match event::read() {
                Ok(e) => {
                    if tx.send(Ev::Term(e)).is_err() {
                        return;
                    }
                }
                Err(_) => return,
            }
        });
    }
    app.start();

    let mut out = std::io::stdout();
    let _ = terminal::enable_raw_mode();
    let _ = execute!(out, EnterAlternateScreen, EnableMouseCapture);
    let mut term = match Terminal::new(CrosstermBackend::new(std::io::stdout())) {
        Ok(t) => t,
        Err(e) => {
            let _ = terminal::disable_raw_mode();
            println!("spark-dialog -- {}", e);
            std::process::exit(1);
        }
    };
    let listening = Arc::new(Mutex::new(None));
    let sixel_ok = sixel::terminal_draws_it(&std::env::var("TERM").unwrap_or_default());
    let mut mark_drawn = false;
    let mut drawn = ui::Drawn::default();
    let mut dirty = true;
    let mut last_clock = String::new();
    loop {
        for j in std::mem::take(&mut app.jobs) {
            run_job(j, tx.clone(), listening.clone());
        }
        let now_clock = clock();
        if now_clock != last_clock {
            last_clock = now_clock;
            dirty = true;
        }
        if dirty {
            let _ = term.draw(|f| {
                let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
                drawn = ui::draw(&app, &pal, &last_clock, &mut b);
                let area = f.area();
                let fb = f.buffer_mut();
                for y in 0..HEIGHT.min(area.height) {
                    for x in 0..WIDTH.min(area.width) {
                        fb[(x, y)] = b[(x, y)].clone();
                    }
                }
                f.set_cursor_position(drawn.cursor);
            });
            match ui::mark_at(&app) {
                Some((mx, my)) if sixel_ok && !mark_drawn => {
                    let cell_h = terminal::window_size()
                        .ok()
                        .filter(|w| w.rows > 0 && w.height > 0)
                        .map(|w| (w.height / w.rows) as u32)
                        .unwrap_or(0);
                    if let Some(s) = sixel::mark(cell_h, pal.dark) {
                        let _ = queue!(out, ratatui::crossterm::cursor::SavePosition, ratatui::crossterm::cursor::MoveTo(mx, my));
                        let _ = out.write_all(s.as_bytes());
                        let _ = queue!(out, ratatui::crossterm::cursor::RestorePosition);
                        let _ = out.flush();
                    }
                    mark_drawn = true;
                }
                Some(_) => {}
                None => mark_drawn = false,
            }
            dirty = false;
        }
        if app.quit.is_some() {
            break;
        }
        let Ok(ev) = rx.recv() else { break };
        match ev {
            Ev::Tick => {
                let was = app.busy();
                app.tick(Instant::now());
                dirty |= was || app.busy();
            }
            Ev::Mcp(m) => {
                app.incoming(m);
                dirty = true;
            }
            Ev::Helper(h, r) => {
                app.helper(h, r);
                dirty = true;
            }
            Ev::Term(Event::Resize(_, _)) => {
                mark_drawn = false;
                let _ = term.clear();
                dirty = true;
            }
            Ev::Term(Event::Key(k)) if k.kind == KeyEventKind::Press => {
                dirty = true;
                match (k.code, k.modifiers) {
                    (KeyCode::Char('c'), m) if m.contains(KeyModifiers::CONTROL) => app.quit = Some(130),
                    (KeyCode::Esc, _) => app.escape(),
                    (KeyCode::Enter, _) => app.enter(),
                    (KeyCode::Up, _) => app.up(),
                    (KeyCode::Down, _) => app.down(),
                    (KeyCode::Tab, _) => app.tab(),
                    (KeyCode::Backspace, _) => app.backspace(),
                    (KeyCode::Char(c), m) if !m.contains(KeyModifiers::CONTROL) && !m.contains(KeyModifiers::ALT) => app.typed(c),
                    _ => {}
                }
            }
            Ev::Term(Event::Paste(p)) => {
                for c in p.chars().filter(|c| !c.is_control()) {
                    app.typed(c);
                }
                dirty = true;
            }
            Ev::Term(Event::Mouse(m)) => {
                dirty = true;
                match m.kind {
                    MouseEventKind::Down(MouseButton::Left) => {
                        if m.row == 0 && m.column + 2 >= WIDTH && app.cfg.close {
                            app.quit = Some(0);
                        } else if let Some((_, _, c)) = drawn.chips.iter().find(|(a, b, _)| m.row == HEIGHT - 1 && m.column >= *a && m.column < *b) {
                            app.chip(*c);
                        } else if let Some((_, n)) = drawn.picks.iter().find(|(y, _)| *y == m.row) {
                            app.sel = *n;
                            app.enter();
                        }
                    }
                    MouseEventKind::ScrollUp => app.up(),
                    MouseEventKind::ScrollDown => app.down(),
                    _ => {}
                }
            }
            _ => {}
        }
    }
    let code = app.quit.unwrap_or(0);
    let _ = execute!(term.backend_mut(), DisableMouseCapture, LeaveAlternateScreen);
    let _ = terminal::disable_raw_mode();
    let _ = term.show_cursor();
    for s in app.servers.iter_mut() {
        s.close_stdin();
    }
    let handles: Vec<_> = std::mem::take(&mut app.servers)
        .into_iter()
        .map(|mut s| std::thread::spawn(move || s.shutdown()))
        .collect();
    for h in handles {
        let _ = h.join();
    }
    std::process::exit(code);
}
