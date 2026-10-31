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
use spark_dialog::app::{App, Config, Helper, Job, View};
use spark_dialog::mcp::{Incoming, Server};
use spark_dialog::palette::{slots_here, Palette};
use spark_dialog::sixel::Image;
use spark_dialog::transition::{self, Reel};
use spark_dialog::{preview, sixel, ui};
use std::io::Write;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

mod login_run;

const USAGE: &str = "spark-dialog -- the spark dialog, one window for every domain (run by spark-shell dialog)

  spark-dialog [--provider \"PATH WORDS\"]... [--home SECTION] [--title TEXT]
               [--close on|off] [--progress on|off]
               [--composer plus,model,talk] [--attach \"txt md\"]
               [--spark-shell PATH] [--spark PATH] [--transitions DIR]
  spark-dialog login ...   the login screen on tty1 (spark-dialog login -h)
";

enum Ev {
    Term(Event),
    /// The terminal is gone (its window closed): the dialog goes with it, and its providers.
    Gone,
    Mcp(Incoming),
    Tick,
    Helper(Helper, Result<String, String>),
    /// The transitions' piece, decoded (#122): None when it could not be.
    Films(Option<transition::Films>),
    /// A piece lit in the animation list, decoded (#132): its folder, and None when it could not be.
    Side(String, Option<transition::Films>),
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
            "--transitions" => {
                let dir = val("--transitions")?;
                if !dir.starts_with('/') || dir.split('/').any(|c| c == "..") || dir.chars().any(char::is_control) {
                    return Err(format!("{}: the transitions are a whole path", dir));
                }
                cfg.transitions = Some(dir);
            }
            other => return Err(format!("no option {}", other)),
        }
    }
    Ok(Args { cfg, providers })
}

/// The date and the time, the header's right: the machine's own clock and zone, in the person's
/// locale for the day and month, with the saved 12 or 24 hour preference, as "Tue 20 Oct, 11:18" with a middle dot.
fn clock(twelve: bool) -> String {
    unsafe {
        spark_dialog::preferences::refresh_zone();
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
        spark_dialog::preferences::refresh_zone();
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        (tm.tm_year + 1900, (tm.tm_mon + 1) as u32, tm.tm_mday as u32)
    }
}

fn run_job(job: Job, tx: mpsc::Sender<Ev>, listening: Arc<Mutex<Option<u32>>>) {
    match job {
        Job::RunInput(h, argv, input) => {
            std::thread::spawn(move || {
                let result = spark_dialog::helper::invoke(&argv, input);
                let _ = tx.send(Ev::Helper(h, result));
            });
        }
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

/// The picture a row brings, or a preview's page, as sixel for a box of `bw` by `bh` pixels, with its
/// size in pixels: a regular PNG of 8 MB at most, made once for its file, its time and the box (the
/// cache), None while it is not there yet.
/// A picture's file decoded once for its file and its time: a regular PNG of 8 MB at most, None while
/// it is not there yet. The preview zooms, moves and turns the one kept (#120).
fn image<'a>(file: &str, cache: &'a mut Option<(String, std::time::SystemTime, Image)>) -> Option<&'a Image> {
    let meta = std::fs::metadata(file).ok().filter(|m| m.is_file() && m.len() <= 8 << 20)?;
    let when = meta.modified().ok()?;
    if !cache.as_ref().is_some_and(|(f, t, _)| f == file && *t == when) {
        *cache = Some((file.to_string(), when, sixel::decode(&std::fs::read(file).ok()?)?));
    }
    cache.as_ref().map(|(_, _, i)| i)
}

/// A transition drawn: its box, which one, its frame.
type ShownFilm = ((u16, u16, u16, u16), Reel, usize);
/// A piece beside a list drawn (#132): its box, its folder, the wait or the open, its frame.
type ShownSide = ((u16, u16, u16, u16), String, bool, usize);
/// A sound's spectrogram in the palette: its file, the palette's ramp, its box, the picture.
type Tinted = (String, [[u8; 3]; 4], (u32, u32), Image);

/// A piece's three films from its folder; @2x where a cell is twice the usual height. None where one is
/// missing or no GIF.
fn decode_films(dir: &str) -> Option<transition::Films> {
    let double = cell_px().is_some_and(|(_, ch)| ch >= 30);
    let one = |reel: &str| {
        let f = format!("{}/{}{}.gif", dir, reel, if double { "@2x" } else { "" });
        let bytes = std::fs::read(&f).ok().filter(|b| b.len() <= 4 << 20)?;
        transition::film(&bytes)
    };
    Some(transition::Films {
        open: one("open")?,
        wait: one("wait")?,
        close: one("close")?,
    })
}

/// The transitions' piece (#122), decoded aside so the window draws at once. Again when a theme step
/// changes the look (#126).
fn spawn_films(dir: String, tx: mpsc::Sender<Ev>) {
    std::thread::spawn(move || {
        let _ = tx.send(Ev::Films(decode_films(&dir)));
    });
}

/// Two clicks on a row this close together are a double-click, the desktop's usual (#140).
const DOUBLE_CLICK: Duration = Duration::from_millis(400);

/// A drag's pictures, this far apart at least (#129), and as far apart as the last one took to draw (#148).
const DRAG_GAP: Duration = Duration::from_millis(40);
/// A drag's pictures in fewer colors, so each is a small write the terminal draws at once; the whole one when the
/// pointer lets go (#148).
const DRAG_COLORS: usize = 48;

/// The pointer foot draws over the window (OSC 22, its cursor theme's names): a hand where a click acts,
/// the closed hand over a picture that moves and while it moves, the text cursor on the prompt (#129).
fn pointer_at(app: &App, drawn: &ui::Drawn, col: u16, row: u16, dragging: bool) -> &'static str {
    let on = |(x, y, w, h): (u16, u16, u16, u16)| row >= y && row < y + h && col >= x && col < x + w;
    let span = |a: u16, b: u16, y: u16| row == y && col >= a && col < b;
    // where a click acts: the x, a chip, a key, the waveform (it seeks), a row of the list
    let clicks = (row == 0 && drawn.close.is_some_and(|(a, b)| span(a, b, 0)))
        || (row == 0 && drawn.back.is_some_and(|(a, b)| span(a, b, 0)))
        || drawn.chips.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.keys.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.wave.is_some_and(on)
        || [drawn.toast_undo, drawn.toast_close].iter().flatten().any(|(a, b, y)| span(*a, *b, *y));
    if dragging {
        "grabbing"
    } else if clicks {
        "pointer"
    } else if drawn.preview.as_ref().is_some_and(|p| app.zoomed() && on((p.x, p.y, p.w, p.h))) {
        "grab"
    } else if row >= drawn.prompt.0 && row <= drawn.prompt.1 {
        "text"
    } else if drawn.picks.iter().any(|(y, _)| *y == row) && col >= drawn.columns.0 && col < drawn.columns.1 {
        "pointer"
    } else {
        "default"
    }
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
    // the palette as colors, slots or not: a picture tinted in it needs them (a spectrogram, #156)
    let mut colors = Palette::from(|k| std::env::var(k).ok());
    let labels: Vec<String> = a.providers.iter().map(|(l, _)| l.clone()).collect();
    let mut app = App::new(a.cfg, &labels);
    unsafe {
        libc::setlocale(libc::LC_TIME, c"".as_ptr());
    }
    let (tx, rx) = mpsc::channel::<Ev>();
    let films_tx = tx.clone();
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
    if let Some(dir) = app.cfg.transitions.clone() {
        spawn_films(dir, tx.clone());
        // the opening is pending from the first frame: the home's rows wait for it, never a flash of them before it (#138)
        if app.cfg.home.is_none() && app.view == View::Home {
            app.motion = Some((Reel::Open, Instant::now()));
        }
    }
    let started = Instant::now();
    let (mut drag_drawn, mut drag_owed) = (Instant::now(), false);
    // how long the last picture of a drag took to make and write: the next waits as long (#148)
    let mut drag_cost = Duration::ZERO;
    // the last click on a row of Files: where, which, when (#140)
    let mut last_click: Option<(u16, usize, Instant)> = None;
    let mut pointer = "";
    let mut films: Option<transition::Films> = None;
    // the transition drawn now: its box, which one, its frame
    let mut shown_film: Option<ShownFilm> = None;
    let mut film_due: Option<Duration> = None;
    // an animation beside a list (#132): the piece lit, decoded aside, and since when it plays; the one being decoded;
    // the frame drawn now (its box, its folder, the wait or the open, the frame)
    let mut side: Option<(String, Option<transition::Films>, Instant)> = None;
    let mut side_loading: Option<String> = None;
    let mut shown_side: Option<ShownSide> = None;
    let mut side_due: Option<Duration> = None;
    let side_tx = tx.clone();

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
    let mut shown_preview: Option<ui::Picture> = None;
    let mut preview_tried = Instant::now();
    let mut images = None;
    // a sound's spectrogram in the palette's colors, filling its box: made once a sound, a palette and a box
    let mut tinted: Option<Tinted> = None;
    // a drag on a picture: where the pointer was
    let mut drag: Option<(u16, u16)> = None;
    let mut drawn = ui::Drawn::default();
    let mut dirty = true;
    let mut last_clock = String::new();
    loop {
        for j in std::mem::take(&mut app.jobs) {
            run_job(j, tx.clone(), listening.clone());
        }
        // in slots, the switch recolored this window with every other one, its slots and its ground (#33, #34);
        // elsewhere a theme step brings the new palette, and the window's ground with it
        if let Some(m) = app.palette.take() {
            colors = Palette::from(|k| m.get(k).and_then(serde_json::Value::as_str).map(String::from));
            if !slots {
                pal = colors.clone();
                if let ratatui::style::Color::Rgb(r, g, b) = pal.surface {
                    let _ = write!(out, "\x1b]11;#{:02x}{:02x}{:02x}\x1b\\", r, g, b);
                    let _ = out.flush();
                }
                let _ = term.clear();
            }
            shown_preview = None;
            dirty = true;
        }
        let prefs = spark_dialog::preferences::read();
        if app.monday_first != prefs.monday {
            app.monday_first = prefs.monday;
            dirty = true;
        }
        let now_clock = clock(prefs.twelve);
        if now_clock != last_clock {
            last_clock = now_clock;
            app.today = Some(today());
            dirty = true;
        }
        if let Some(f) = &films {
            app.follow_motion(Instant::now(), f.open.length(), f.close.length());
            dirty |= app.motion.is_some() || shown_film.is_some();
        }
        if dirty {
            if let Ok(sz) = term.size() {
                app.size = (sz.width, sz.height);
            }
            // a sound's picture read once: its waveform and its spectrum, before it is drawn
            if let Some(pv) = app.preview.as_mut().filter(|pv| pv.heard.is_none()) {
                if let Some((file, wave)) = pv.shown.as_ref().and_then(|pg| pg.sound.clone()) {
                    pv.heard = image(&file, &mut images).and_then(|i| preview::sound(i, wave));
                }
            }
            let _ = out.write_all(b"\x1b[?2026h");
            let _ = out.flush();
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
                // the opening alone has no cursor: nothing is there to type into yet (#142)
                if !drawn.alone {
                    f.set_cursor_position(drawn.cursor);
                }
            });
            let _ = out.write_all(b"\x1b[?2026l");
            let _ = out.flush();
            app.preview_pages = drawn.pages.max(1);
            // the picture beside a list: drawn when it changed, its cells blanked first (the buffer skips them);
            // a picture gone is the buffer's again, which writes its cells over it
            let want = drawn.preview.clone();
            let mut again = false;
            if want != shown_preview {
                shown_preview = None;
                if let (Some(p), Some((cw, chh)), true) = (&want, cell_px(), sixel_ok) {
                    let drawing = Instant::now();
                    // one synchronized update: the old picture stays on screen until the new one is whole (#129)
                    let _ = out.write_all(b"\x1b[?2026h");
                    blank(&mut out, (p.x, p.y, p.w, p.h), term_color(pal.surface));
                    let (bw, bh) = (p.w as u32 * cw, p.h as u32 * chh);
                    let img = if p.spectrogram {
                        let ramp = colors.ramp().unwrap_or([[0x1f; 3], [0x7f; 3], [0x55, 0x55, 0xff], [0xaa; 3]]);
                        let heard = app.preview.as_ref().and_then(|pv| pv.heard.as_ref());
                        if let Some(h) = heard.filter(|_| !tinted.as_ref().is_some_and(|(f, r, b, _)| *f == p.file && *r == ramp && *b == (bw, bh))) {
                            tinted = Some((p.file.clone(), ramp, (bw, bh), h.spectrogram.tinted(&ramp).resized(bw, bh)));
                        }
                        tinted.as_ref().filter(|(f, _, _, _)| *f == p.file).map(|(_, _, _, i)| i)
                    } else {
                        image(&p.file, &mut images)
                    };
                    if let Some(img) = img {
                        // the preview's picture: its box and its pixels, for the zoom and the move (#120)
                        if let Some(pv) = app.preview.as_mut().filter(|_| app.view == View::Preview && !p.spectrogram) {
                            if pv.px != (bw, bh) || pv.src != (img.w, img.h) {
                                (pv.px, pv.src) = ((bw, bh), (img.w, img.h));
                                again = true;
                            }
                        }
                        // while a drag moves the picture, a lighter frame keeps up with the pointer; the whole one when it stops (#148)
                        let colors = if drag.is_some() { DRAG_COLORS } else { 255 };
                        if let Some((s, pw, ph)) = sixel::show_with(img, bw, bh, &p.view, colors) {
                            // in the middle of its box by whole cells
                            let (dx, dy) = ((bw.saturating_sub(pw) / 2 / cw) as u16, (bh.saturating_sub(ph) / 2 / chh) as u16);
                            // where it is, in pixels: a video plays over it (#125)
                            if let Some(pv) = app.preview.as_mut().filter(|_| app.view == View::Preview && !p.spectrogram) {
                                pv.frame = Some(((p.x + dx) as u32 * cw, (p.y + dy) as u32 * chh, pw, ph));
                            }
                            let _ = queue!(
                                out,
                                ratatui::crossterm::cursor::SavePosition,
                                ratatui::crossterm::cursor::MoveTo(p.x + dx, p.y + dy)
                            );
                            let _ = out.write_all(s.as_bytes());
                            let _ = queue!(out, ratatui::crossterm::cursor::RestorePosition);
                            shown_preview = want.clone();
                        }
                    }
                    let _ = out.write_all(b"\x1b[?2026l");
                    let _ = out.flush();
                    if drag.is_some() {
                        drag_cost = drawing.elapsed();
                    }
                }
                preview_tried = Instant::now();
            }
            // a transition: its frame now, at the top left of its box, where the rows land and give way to it (#132), at
            // the GIF's own pace (#122)
            film_due = None;
            match (drawn.film, &films, cell_px()) {
                (Some((x, y, w, h, reel, since)), Some(f), Some((cw, chh))) if sixel_ok => {
                    // a page being read plays the open from its start, then the wait looped while it is still on its way (#142)
                    let ms = Instant::now().saturating_duration_since(since).as_millis();
                    let (film, k, left, shown) = if reel == Reel::Load && ms >= f.open.length() {
                        let (k, left) = f.wait.at(ms - f.open.length(), true);
                        (&f.wait, k, left, k + f.open.frames.len())
                    } else {
                        let film = f.of(reel);
                        let (k, left) = film.at(ms, reel == Reel::Wait);
                        (film, k, left, k)
                    };
                    let at = ((x, y, w, h), reel, shown);
                    if shown_film != Some(at) {
                        // its cells cleared and the frame drawn in one synchronized update: the ground is
                        // the window's own, and no frame shows half drawn
                        let (dx, dy) = (
                            ((w as u32 * cw).saturating_sub(film.w) / 2 / cw) as u16,
                            ((h as u32 * chh).saturating_sub(film.h) / 2 / chh) as u16,
                        );
                        let (fw, fh) = ((film.w.div_ceil(cw) as u16).min(w - dx), (film.h.div_ceil(chh) as u16).min(h - dy));
                        let _ = out.write_all(b"\x1b[?2026h");
                        if shown_film.is_none_or(|(b, _, _)| b != (x, y, w, h)) {
                            blank(&mut out, (x, y, w, h), term_color(pal.surface));
                        } else {
                            blank(&mut out, (x + dx, y + dy, fw, fh), term_color(pal.surface));
                        }
                        let _ = queue!(
                            out,
                            ratatui::crossterm::cursor::SavePosition,
                            ratatui::crossterm::cursor::MoveTo(x + dx, y + dy)
                        );
                        let _ = out.write_all(film.frames[k].0.as_bytes());
                        let _ = queue!(out, ratatui::crossterm::cursor::RestorePosition);
                        let _ = out.write_all(b"\x1b[?2026l");
                        let _ = out.flush();
                        shown_film = Some(at);
                    }
                    film_due = Some(Duration::from_millis(left.clamp(1, 1000) as u64));
                }
                _ => shown_film = None,
            }
            // an animation beside a list (#132): the lit piece's open, then its wait looped, from when it was lit, in the
            // middle of the box a wallpaper's picture takes
            side_due = None;
            match (&drawn.side_film, cell_px()) {
                (Some((x, y, w, h, dir)), Some((cw, chh))) if sixel_ok => {
                    let bx = (*x, *y, *w, *h);
                    if side.as_ref().is_none_or(|(d, _, _)| d != dir) && side_loading.as_deref() != Some(dir.as_str()) {
                        side_loading = Some(dir.clone());
                        let (tx, dir) = (side_tx.clone(), dir.clone());
                        std::thread::spawn(move || {
                            let f = decode_films(&dir);
                            let _ = tx.send(Ev::Side(dir, f));
                        });
                    }
                    if shown_side.as_ref().is_some_and(|(b, d, _, _)| *b != bx || d != dir) {
                        // another piece lit: the box is cleared while it comes
                        let _ = out.write_all(b"\x1b[?2026h");
                        blank(&mut out, bx, term_color(pal.surface));
                        let _ = out.write_all(b"\x1b[?2026l");
                        let _ = out.flush();
                        shown_side = None;
                    }
                    if let Some((_, Some(f), since)) = side.as_ref().filter(|(d, _, _)| d == dir) {
                        let ms = since.elapsed().as_millis();
                        let opened = f.open.length();
                        let (film, waiting, t) = if ms < opened { (&f.open, false, ms) } else { (&f.wait, true, ms - opened) };
                        let (k, left) = film.at(t, waiting);
                        let at = (bx, dir.clone(), waiting, k);
                        if shown_side.as_ref() != Some(&at) {
                            let (dx, dy) = (
                                ((*w as u32 * cw).saturating_sub(film.w) / 2 / cw) as u16,
                                ((*h as u32 * chh).saturating_sub(film.h) / 2 / chh) as u16,
                            );
                            let _ = out.write_all(b"\x1b[?2026h");
                            blank(&mut out, bx, term_color(pal.surface));
                            let _ = queue!(
                                out,
                                ratatui::crossterm::cursor::SavePosition,
                                ratatui::crossterm::cursor::MoveTo(x + dx, y + dy)
                            );
                            let _ = out.write_all(film.frames[k].0.as_bytes());
                            let _ = queue!(out, ratatui::crossterm::cursor::RestorePosition);
                            let _ = out.write_all(b"\x1b[?2026l");
                            let _ = out.flush();
                            shown_side = Some(at);
                        }
                        side_due = Some(Duration::from_millis(left.clamp(1, 1000) as u64));
                    }
                }
                _ => shown_side = None,
            }
            dirty = again;
        }
        if app.quit.is_some() {
            break;
        }
        // a transition playing wakes for its next frame, a drag for its next picture; else the next event
        // a sound playing: its waveform and its spectrum drawn about thirty times a second, a steady motion (#152)
        let play_due = (app.view == View::Preview && app.preview.as_ref().is_some_and(|pv| pv.playing.is_some())).then(|| Duration::from_millis(33));
        let due = [
            film_due,
            side_due,
            play_due,
            drag_owed.then(|| DRAG_GAP.max(drag_cost).saturating_sub(drag_drawn.elapsed()).max(Duration::from_millis(1))),
        ]
        .into_iter()
        .flatten()
        .min();
        let ev = match due {
            Some(d) => match rx.recv_timeout(d) {
                Ok(ev) => ev,
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if drag_owed && drag_drawn.elapsed() >= DRAG_GAP.max(drag_cost) {
                        drag_owed = false;
                        drag_drawn = Instant::now();
                    }
                    dirty = true;
                    continue;
                }
                Err(_) => break,
            },
            None => match rx.recv() {
                Ok(ev) => ev,
                Err(_) => break,
            },
        };
        match ev {
            Ev::Gone => app.quit = Some(129),
            Ev::Side(dir, f) => {
                if side_loading.as_deref() == Some(dir.as_str()) {
                    side_loading = None;
                    side = Some((dir, f, Instant::now()));
                    dirty = true;
                }
            }
            Ev::Films(f) => {
                // the open plays from its start when it is still pending: the dialog opened on its home a moment ago and no
                // key cut it (a letter typed lands at the prompt and cuts nothing, #138); else the rows show
                app.films = f.is_some();
                if matches!(app.motion, Some((Reel::Open, _))) {
                    let on_time = f.is_some() && app.view == View::Home && started.elapsed() < Duration::from_millis(800);
                    app.motion = on_time.then(|| (Reel::Open, Instant::now()));
                }
                films = f;
                dirty = true;
            }
            Ev::Tick => {
                let was = app.busy();
                app.tick(Instant::now());
                dirty |= was || app.busy();
                // an opening whose animation never came: the rows show (#138)
                if films.is_none() && matches!(app.motion, Some((Reel::Open, _))) && started.elapsed() >= Duration::from_millis(1500) {
                    app.motion = None;
                    dirty = true;
                }
                // a toast whose time is out, or whose view was left, goes (#133)
                dirty |= app.toast_tick();
                // a picture not drawn yet (its small picture is still being made): tried again now and then
                dirty |= drawn.preview.is_some() && shown_preview.is_none() && preview_tried.elapsed() >= Duration::from_millis(400);
                // a sound playing: its waveform and its spectrum move
                dirty |= app.preview.as_ref().is_some_and(|pv| pv.playing.is_some());
                // a long sound's waveform drawn aside: read the moment it is there (#124)
                dirty |= app
                    .preview
                    .as_ref()
                    .is_some_and(|pv| pv.heard.is_none() && pv.shown.as_ref().is_some_and(|pg| pg.sound.is_some()));
            }
            Ev::Mcp(m) => {
                app.incoming(m);
                // a theme step changed the animation: the new piece read aside, none at once (#126)
                match app.films_want.take() {
                    Some(Some(dir)) => spawn_films(dir, films_tx.clone()),
                    Some(None) => {
                        films = None;
                        app.films = false;
                        app.motion = None;
                    }
                    None => {}
                }
                dirty = true;
            }
            Ev::Helper(h, r) => {
                app.helper(h, r);
                dirty = true;
            }
            Ev::Term(Event::Resize(_, _)) => {
                app.stop_video(); // the frame moves: the player would stand where it was (#125)
                shown_preview = None;
                let _ = term.clear();
                dirty = true;
            }
            Ev::Term(Event::Key(k)) if k.kind == KeyEventKind::Press => {
                dirty = true;
                // a letter typed while the opening plays lands at the prompt and the opening plays on; Enter, Esc, an
                // arrow or a click cut it (#138)
                if !matches!(k.code, KeyCode::Char(_) | KeyCode::Backspace)
                    || k.modifiers.contains(KeyModifiers::CONTROL)
                    || k.modifiers.contains(KeyModifiers::ALT)
                {
                    app.cut_motion();
                }
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
                // the pointer says what a click does where it is (#129)
                let dragging = drag.is_some() && matches!(m.kind, MouseEventKind::Drag(_));
                let want = pointer_at(&app, &drawn, m.column, m.row, dragging);
                if want != pointer {
                    pointer = want;
                    let _ = write!(out, "\x1b]22;{}\x1b\\", want);
                    let _ = out.flush();
                }
                if matches!(m.kind, MouseEventKind::Moved) {
                    dirty = false;
                }
                match m.kind {
                    MouseEventKind::Down(MouseButton::Left) => {
                        app.cut_motion();
                        // a click raises the dialog over a video's player: it stops, unless the click is the key that pauses it (#125)
                        if !drawn.keys.iter().any(|(a, b, y, _)| m.row == *y && m.column >= *a && m.column < *b) {
                            app.stop_video();
                        }
                        if m.row == 0 && drawn.back.is_some_and(|(a, b)| m.column >= a && m.column < b) {
                            app.back(); // the header's back arrow, as a browser's (#147)
                        } else if m.row == 0 && drawn.close.is_some_and(|(a, b)| m.column >= a && m.column < b) {
                            if matches!(app.motion, Some((Reel::Close, _))) {
                                app.quit = Some(0);
                            } else {
                                app.close_window();
                            }
                        } else if drawn.toast_close.is_some_and(|(a, b, y)| m.row == y && m.column >= a && m.column < b) {
                            app.toast = None; // the toast's x (#133)
                        } else if drawn.toast_undo.is_some_and(|(a, b, y)| m.row == y && m.column >= a && m.column < b) {
                            app.undo_now();
                        } else if let Some((_, _, _, c)) = drawn.chips.iter().find(|(a, b, y, _)| m.row == *y && m.column >= *a && m.column < *b) {
                            app.chip(*c);
                        } else if let Some((_, _, _, key)) = drawn.keys.iter().find(|(a, b, y, _)| m.row == *y && m.column >= *a && m.column < *b) {
                            app.hint_key(*key);
                        } else if let Some((x, _, w, _)) = drawn
                            .wave
                            .filter(|(x, y, w, h)| m.row >= *y && m.row < y + h && m.column >= *x && m.column < x + w)
                        {
                            app.preview_seek((m.column - x) as f64 / w as f64);
                        } else if drawn
                            .preview
                            .as_ref()
                            .is_some_and(|p| app.zoomed() && m.row >= p.y && m.row < p.y + p.h && m.column >= p.x && m.column < p.x + p.w)
                        {
                            drag = Some((m.column, m.row));
                        } else if m.row >= drawn.prompt.0 && m.row <= drawn.prompt.1 {
                            app.focus_prompt();
                        } else if let Some((_, n)) = drawn
                            .picks
                            .iter()
                            .find(|(y, _)| *y == m.row && m.column >= drawn.columns.0 && m.column < drawn.columns.1)
                        {
                            // a file or a folder in Files: a click lights it, a second one on it opens it, as a file manager's
                            // do; any other row, a place or an action, is done on one click (#140)
                            let again = last_click.is_some_and(|(r, k, t)| r == m.row && k == *n && t.elapsed() < DOUBLE_CLICK);
                            app.light(*n);
                            if !app.lights_on_click(*n) || again {
                                last_click = None;
                                app.enter();
                            } else {
                                last_click = Some((m.row, *n, Instant::now()));
                            }
                        }
                    }
                    MouseEventKind::Drag(MouseButton::Left) => {
                        if let (Some((c0, r0)), Some((cw, chh))) = (drag, cell_px()) {
                            app.preview_drag((m.column as f64 - c0 as f64) * cw as f64, (m.row as f64 - r0 as f64) * chh as f64);
                            drag = Some((m.column, m.row));
                            // the picture follows at most every DRAG_GAP, and no sooner than the last took to draw, at the
                            // latest place: never a picture a motion (#129, #148)
                            if drag_drawn.elapsed() < DRAG_GAP.max(drag_cost) {
                                drag_owed = true;
                                dirty = false;
                            } else {
                                drag_drawn = Instant::now();
                            }
                        }
                    }
                    MouseEventKind::Up(_) => {
                        // the pointer let go: the picture drawn whole again, in all its colors (#148)
                        if drag.take().is_some() {
                            shown_preview = None;
                            drag_cost = Duration::ZERO;
                        }
                        drag_owed = false;
                    }
                    MouseEventKind::ScrollUp if app.view == View::Preview => app.preview_wheel(-1, m.modifiers.contains(KeyModifiers::CONTROL)),
                    MouseEventKind::ScrollDown if app.view == View::Preview => app.preview_wheel(1, m.modifiers.contains(KeyModifiers::CONTROL)),
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
    // the providers: each one's input closed, none waited for. Each ends the request it is answering,
    // reads the end of its input and leaves through its own EXIT trap; its process group of its own keeps
    // the window's closing from cutting one short. Waiting here held the window open as a bare terminal,
    // the cursor blinking and keys echoed, for as long as the slowest took: 1.5 s once on the box (#60)
    for s in app.servers.iter_mut() {
        s.close_stdin();
    }
    std::process::exit(code);
}
