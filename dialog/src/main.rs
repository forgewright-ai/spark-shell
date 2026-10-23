//! spark-dialog: the terminal, the event loop, the helpers. Run by
//! `spark-shell dialog` in a foot window of 60 by 40 cells.

use ratatui::backend::CrosstermBackend;
use ratatui::buffer::Buffer;
use ratatui::crossterm::event::{
    self, DisableBracketedPaste, DisableFocusChange, DisableMouseCapture, EnableBracketedPaste, EnableFocusChange, EnableMouseCapture, Event, KeyCode,
    KeyEventKind, KeyModifiers, KeyboardEnhancementFlags, MouseButton, MouseEventKind, PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use ratatui::crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::crossterm::{execute, queue};
use ratatui::layout::Rect;
use ratatui::Terminal;
use spark_dialog::app::{App, Config, Helper, Job};
use spark_dialog::mcp::{Incoming, Server};
use spark_dialog::palette::{slots_here, Palette};
use spark_dialog::{sixel, ui};
use std::io::Write;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

mod login_run;

const USAGE: &str = "spark-dialog -- the spark dialog, one window for every domain (run by spark-shell dialog)

  spark-dialog [--provider \"PATH WORDS\"]... [--home SECTION] [--title TEXT]
               [--close on|off] [--progress on|off]
               [--composer plus,model,talk] [--attach \"txt md\"]
               [--spark-shell PATH] [--spark PATH]
  spark-dialog login ...   the login screen on tty1 (spark-dialog login -h)
";

enum Ev {
    Term(Event),
    /// The terminal is gone (its window closed): the dialog goes with it, and its providers.
    Gone,
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

/// How the person's locale writes the time: twelve hours when its own format says so, else 24.
fn twelve_hours() -> bool {
    unsafe {
        let p = libc::nl_langinfo(libc::T_FMT);
        if p.is_null() {
            return false;
        }
        let f = std::ffi::CStr::from_ptr(p).to_string_lossy();
        f.contains("%I") || f.contains("%r") || f.contains("%p") || f.contains("%l")
    }
}

/// The date and the time, the header's right: the machine's own clock and zone, in the person's
/// locale (the day and the month in its words, 12 or 24 hours as it says), as "Tue 20 Oct, 11:18" with a middle dot.
fn clock(twelve: bool) -> String {
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let mut b = [0u8; 96];
        let f: &[u8] = if twelve {
            b"%a %d %b \xc2\xb7 %I:%M %p\0"
        } else {
            b"%a %d %b \xc2\xb7 %H:%M\0"
        };
        let n = libc::strftime(b.as_mut_ptr() as *mut libc::c_char, b.len(), f.as_ptr() as *const libc::c_char, &tm);
        let s = String::from_utf8_lossy(&b[..n]).into_owned();
        // no leading zero on the day or a twelve-hour hour: "Tue 5 Oct", "9:05 AM"
        let s = s.replacen(" 0", " ", 1);
        if twelve {
            s.replace("\u{b7} 0", "\u{b7} ")
        } else {
            s
        }
    }
}

/// Today, (year, month, day), by the machine's own clock and zone.
fn today() -> (i32, u32, u32) {
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        (tm.tm_year + 1900, (tm.tm_mon + 1) as u32, tm.tm_mday as u32)
    }
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

/// A color of the palette as crossterm writes it: a slot stays a slot (#34).
fn term_color(c: ratatui::style::Color) -> ratatui::crossterm::style::Color {
    match c {
        ratatui::style::Color::Rgb(r, g, b) => ratatui::crossterm::style::Color::Rgb { r, g, b },
        ratatui::style::Color::Indexed(n) => ratatui::crossterm::style::Color::AnsiValue(n),
        _ => ratatui::crossterm::style::Color::Reset,
    }
}

/// Cells (x, y, w, h) made blank on the window's ground: a picture's old place, before the next.
fn blank(out: &mut std::io::Stdout, (x, y, w, h): (u16, u16, u16, u16), ground: ratatui::crossterm::style::Color) {
    let _ = queue!(
        out,
        ratatui::crossterm::cursor::SavePosition,
        ratatui::crossterm::style::SetBackgroundColor(ground)
    );
    for dy in 0..h {
        let _ = queue!(
            out,
            ratatui::crossterm::cursor::MoveTo(x, y + dy),
            ratatui::crossterm::style::Print(" ".repeat(w as usize))
        );
    }
    let _ = queue!(out, ratatui::crossterm::style::ResetColor, ratatui::crossterm::cursor::RestorePosition);
}

/// A cell's size in pixels, as the terminal says; None where it does not.
fn cell_px() -> Option<(u32, u32)> {
    terminal::window_size()
        .ok()
        .filter(|w| w.columns > 0 && w.rows > 0 && w.width > 0 && w.height > 0)
        .map(|w| ((w.width / w.columns) as u32, (w.height / w.rows) as u32))
}

/// The picture a row brings, as sixel for a box of `bw` by `bh` pixels: a regular PNG of 4 MB at most,
/// made once for its file, its time and the box (the cache), None while it is not there yet.
fn picture(file: &str, bw: u32, bh: u32, cache: &mut Option<(String, u32, u32, std::time::SystemTime, String)>) -> Option<String> {
    let meta = std::fs::metadata(file).ok().filter(|m| m.is_file() && m.len() <= 4 << 20)?;
    let when = meta.modified().ok()?;
    if let Some((f, w, h, t, s)) = cache.as_ref() {
        if f == file && *w == bw && *h == bh && *t == when {
            return Some(s.clone());
        }
    }
    let s = sixel::picture(&std::fs::read(file).ok()?, bw, bh)?;
    *cache = Some((file.to_string(), bw, bh, when, s.clone()));
    Some(s)
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("login") {
        login_run::main();
    }
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
    let mut pal = Palette::from_env();
    let slots = slots_here();
    let labels: Vec<String> = a.providers.iter().map(|(l, _)| l.clone()).collect();
    let mut app = App::new(a.cfg, &labels);
    unsafe {
        libc::setlocale(libc::LC_TIME, c"".as_ptr());
    }
    let twelve = twelve_hours();
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
    let mut out = std::io::stdout();
    let _ = terminal::enable_raw_mode();
    let _ = execute!(out, EnterAlternateScreen, EnableMouseCapture, EnableBracketedPaste, EnableFocusChange);
    // the kitty keyboard protocol (foot speaks it): Shift+Enter is a key of its own, a new line, not
    // Enter. Asked before the keys' thread starts: that thread would hold the terminal's answer.
    let kitty = terminal::supports_keyboard_enhancement().unwrap_or(false);
    if kitty {
        let _ = execute!(out, PushKeyboardEnhancementFlags(KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES));
    }
    {
        let tx = tx.clone();
        std::thread::spawn(move || {
            let mut errors = 0;
            loop {
                match event::read() {
                    Ok(e) => {
                        errors = 0;
                        if tx.send(Ev::Term(e)).is_err() {
                            return;
                        }
                    }
                    // a terminal that hung up answers every read with an error at once; one that did
                    // not may fail a read now and then: twenty in a row is a window gone (#37)
                    Err(_) => {
                        errors += 1;
                        if errors >= 20 {
                            let _ = tx.send(Ev::Gone);
                            return;
                        }
                        std::thread::sleep(Duration::from_millis(10));
                    }
                }
            }
        });
    }
    app.start();

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
    // the picture beside a list (a wallpaper's): where it is drawn now, when one was last tried, the last one made
    let mut shown_preview: Option<(u16, u16, u16, u16, String)> = None;
    let mut preview_tried = Instant::now();
    let mut preview_cache = None;
    let mut drawn = ui::Drawn::default();
    let mut dirty = true;
    let mut last_clock = String::new();
    loop {
        for j in std::mem::take(&mut app.jobs) {
            run_job(j, tx.clone(), listening.clone());
        }
        // in slots, the switch recolored this window with every other one, its slots and its ground (#33, #34);
        // elsewhere a theme step brings the new palette, and the window's ground with it
        if let Some(m) = app.palette.take().filter(|_| !slots) {
            pal = Palette::from(|k| m.get(k).and_then(serde_json::Value::as_str).map(String::from));
            if let ratatui::style::Color::Rgb(r, g, b) = pal.surface {
                let _ = write!(out, "\x1b]11;#{:02x}{:02x}{:02x}\x1b\\", r, g, b);
                let _ = out.flush();
            }
            shown_preview = None;
            let _ = term.clear();
            dirty = true;
        }
        let now_clock = clock(twelve);
        if now_clock != last_clock {
            last_clock = now_clock;
            app.today = Some(today());
            dirty = true;
        }
        if dirty {
            if let Ok(sz) = term.size() {
                app.size = (sz.width, sz.height);
            }
            let _ = term.draw(|f| {
                let area = f.area();
                let mut b = Buffer::empty(Rect::new(0, 0, area.width, area.height));
                drawn = ui::draw(&app, &pal, &last_clock, &mut b);
                let fb = f.buffer_mut();
                for y in 0..area.height {
                    for x in 0..area.width {
                        fb[(x, y)] = b[(x, y)].clone();
                    }
                }
                f.set_cursor_position(drawn.cursor);
            });
            // the picture beside a list: drawn when it changed, its cells blanked first (the buffer skips them);
            // a picture gone is the buffer's again, which writes its cells over it
            let want = drawn.preview.clone();
            if want != shown_preview {
                shown_preview = None;
                if let (Some((x, y, w, h, file)), true) = (&want, sixel_ok) {
                    blank(&mut out, (*x, *y, *w, *h), term_color(pal.surface));
                    if let Some(s) = cell_px().and_then(|(cw, chh)| picture(file, *w as u32 * cw, *h as u32 * chh, &mut preview_cache)) {
                        let _ = queue!(out, ratatui::crossterm::cursor::SavePosition, ratatui::crossterm::cursor::MoveTo(*x, *y));
                        let _ = out.write_all(s.as_bytes());
                        let _ = queue!(out, ratatui::crossterm::cursor::RestorePosition);
                        shown_preview = want.clone();
                    }
                    let _ = out.flush();
                }
                preview_tried = Instant::now();
            }
            dirty = false;
        }
        if app.quit.is_some() {
            break;
        }
        let Ok(ev) = rx.recv() else { break };
        match ev {
            Ev::Gone => app.quit = Some(129),
            Ev::Tick => {
                let was = app.busy();
                app.tick(Instant::now());
                dirty |= was || app.busy();
                // a picture not drawn yet (its small picture is still being made): tried again now and then
                dirty |= drawn.preview.is_some() && shown_preview.is_none() && preview_tried.elapsed() >= Duration::from_millis(400);
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
                shown_preview = None;
                let _ = term.clear();
                dirty = true;
            }
            Ev::Term(Event::Key(k)) if k.kind == KeyEventKind::Press => {
                dirty = true;
                match (k.code, k.modifiers) {
                    (KeyCode::Char('c'), m) if m.contains(KeyModifiers::CONTROL) => app.quit = Some(130),
                    (KeyCode::Esc, _) => app.escape(),
                    // Shift+Enter, or Alt+Enter where the terminal cannot tell Shift+Enter from Enter
                    (KeyCode::Enter, m) if m.contains(KeyModifiers::SHIFT) || m.contains(KeyModifiers::ALT) => app.newline(),
                    (KeyCode::Char('j'), m) if m.contains(KeyModifiers::CONTROL) => app.newline(),
                    (KeyCode::Enter, _) => app.enter(),
                    (KeyCode::Up, _) => app.up(),
                    (KeyCode::Down, _) => app.down(),
                    (KeyCode::Left, _) => app.left(),
                    (KeyCode::Right, _) => app.right(),
                    (KeyCode::Home, _) => app.line_start(),
                    (KeyCode::End, _) => app.line_end(),
                    (KeyCode::PageUp, _) => app.page(-1),
                    (KeyCode::PageDown, _) => app.page(1),
                    (KeyCode::Tab, m) => app.tab(m.contains(KeyModifiers::SHIFT)),
                    (KeyCode::BackTab, _) => app.tab(true),
                    (KeyCode::Backspace, _) => app.backspace(),
                    (KeyCode::Delete, _) => app.delete(),
                    (KeyCode::Char(c), m) if !m.contains(KeyModifiers::CONTROL) && !m.contains(KeyModifiers::ALT) => app.typed(c),
                    _ => {}
                }
            }
            Ev::Term(Event::Paste(p)) => {
                app.paste(&p);
                dirty = true;
            }
            Ev::Term(Event::FocusLost) => {
                app.focus_lost();
                dirty = true;
            }
            Ev::Term(Event::Mouse(m)) => {
                dirty = true;
                match m.kind {
                    MouseEventKind::Down(MouseButton::Left) => {
                        if m.row == 0 && drawn.close.is_some_and(|(a, b)| m.column >= a && m.column < b) {
                            app.quit = Some(0);
                        } else if let Some((_, _, _, c)) = drawn.chips.iter().find(|(a, b, y, _)| m.row == *y && m.column >= *a && m.column < *b) {
                            app.chip(*c);
                        } else if m.row >= drawn.prompt.0 && m.row <= drawn.prompt.1 {
                            app.in_list = false;
                            app.chip_focus = None;
                        } else if let Some((_, n)) = drawn.picks.iter().find(|(y, _)| *y == m.row) {
                            app.in_list = true;
                            app.sel = *n;
                            app.enter();
                        }
                    }
                    MouseEventKind::ScrollUp => app.page(-1),
                    MouseEventKind::ScrollDown => app.page(1),
                    _ => {}
                }
            }
            _ => {}
        }
    }
    let code = app.quit.unwrap_or(0);
    // a recording does not outlive the window
    run_job(Job::StopListening, tx.clone(), listening.clone());
    if kitty {
        let _ = execute!(term.backend_mut(), PopKeyboardEnhancementFlags);
    }
    let _ = execute!(
        term.backend_mut(),
        DisableFocusChange,
        DisableBracketedPaste,
        DisableMouseCapture,
        LeaveAlternateScreen
    );
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
