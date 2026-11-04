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
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")));
    if let Some(config) = config {
        cfg.keys = spark_dialog::keys::Bindings::load(&config.join("spark-shell/home-keys.json"))?;
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
                let result = if matches!(h, spark_dialog::app::Helper::Apps(_)) {
                    spark_dialog::helper::invoke_apps(&argv, input)
                } else {
                    spark_dialog::helper::invoke(&argv, input)
                };
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

/// A drag's pictures, this far apart at least (#129), and as far apart as the last one took to draw (#148).
const DRAG_GAP: Duration = Duration::from_millis(40);
/// A drag's pictures in fewer colors, so each is a small write the terminal draws at once; the whole one when the
/// pointer lets go (#148).
const DRAG_COLORS: usize = 48;

/// A tick wants a frame while spark's march shows, and when work starts or ends; work nothing shows draws
/// nothing (#196). `was` and `now` say whether work was under way.
fn frame_for_tick(was: bool, now: bool, march: bool) -> bool {
    march || was != now
}

/// A mouse event wants a frame when it can change what is drawn: a press, a drag, the wheel, or the end of a drag;
/// a motion or a release that ends nothing draws none, so a click is one frame (#196).
fn frame_for_mouse(kind: MouseEventKind, dragging: bool) -> bool {
    match kind {
        MouseEventKind::Moved => false,
        MouseEventKind::Up(_) => dragging,
        _ => true,
    }
}

/// The dialog's window shown (#167): it mapped unseen, and its first frame is drawn now. A RUN_COMMAND on sway's
/// own socket, no process started; a moment's wait first, so foot has put the frame on the window before it shows.
fn reveal() {
    opacity(1, Duration::from_millis(25));
}

/// The dialog's window made clear (0) or solid (1) on sway's own socket: clear while a step puts a window in
/// front, so the click shows that window coming at once, solid again when the step comes back refused (#196).
fn opacity(level: u8, after: Duration) {
    sway_command(format!("[app_id=\"spark-dialog\"] opacity {}", level), after);
}

/// Home put away while the app it opened is in front. It stays as it is and Super+Space brings it back; a clear
/// window would stay over that app and take its clicks, and the pointer crossing it would bring home back.
fn stow() {
    sway_command("[app_id=\"spark-dialog\"] move scratchpad".into(), Duration::ZERO);
}

/// One command on sway's own socket; away from sway, nothing.
fn sway_command(cmd: String, after: Duration) {
    let Some(sock) = std::env::var_os("SWAYSOCK") else { return };
    std::thread::spawn(move || {
        std::thread::sleep(after);
        let cmd = cmd.as_bytes();
        if let Ok(mut s) = std::os::unix::net::UnixStream::connect(sock) {
            let mut msg = b"i3-ipc".to_vec();
            msg.extend((cmd.len() as u32).to_ne_bytes());
            msg.extend(0u32.to_ne_bytes());
            msg.extend(cmd);
            let _ = s.write_all(&msg);
            let mut answer = [0u8; 512];
            let _ = std::io::Read::read(&mut s, &mut answer);
        }
    });
}

/// The pointer foot draws over the window (OSC 22, its cursor theme's names): a hand where a click acts,
/// the closed hand over a picture that moves and while it moves, the text cursor on the prompt (#129).
fn pointer_at(app: &App, drawn: &ui::Drawn, col: u16, row: u16, dragging: bool) -> &'static str {
    let on = |(x, y, w, h): (u16, u16, u16, u16)| row >= y && row < y + h && col >= x && col < x + w;
    let span = |a: u16, b: u16, y: u16| row == y && col >= a && col < b;
    // where a click acts: the x, a chip, a key, the waveform (it seeks), a row of the list
    let clicks = (row == 0 && drawn.close.is_some_and(|(a, b)| span(a, b, 0)))
        || drawn.chips.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.keys.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.wave.is_some_and(on)
        || drawn.reply_undo.is_some_and(|(a, b, y)| span(a, b, y));
    if dragging {
        "grabbing"
    } else if clicks {
        "pointer"
    } else if drawn.preview.as_ref().is_some_and(|p| app.zoomed() && on((p.x, p.y, p.w, p.h))) {
        "grab"
    } else if row >= drawn.prompt.0 && row <= drawn.prompt.1 {
        "text"
    } else if drawn.pick_at(col, row).is_some() {
        "pointer"
    } else {
        "default"
    }
}

/// Force a full repaint without querying the cursor. Terminal::clear asks the
/// input reader for a cursor report; with event::read on another thread that
/// can block resize until the next key. A fullscreen resize only writes output.
fn invalidate_frame(term: &mut Terminal<CrosstermBackend<std::io::Stdout>>) {
    if let Ok(size) = term.size() {
        let _ = term.resize(Rect::new(0, 0, size.width, size.height));
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
    let _ = execute!(
        out,
        EnterAlternateScreen,
        EnableMouseCapture,
        EnableBracketedPaste,
        EnableFocusChange,
        ratatui::crossterm::cursor::SetCursorStyle::BlinkingBlock
    );
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
    // the window maps unseen (the sway rule's opacity 0) and is shown once the opening's first frame is on it:
    // nothing comes before the animation, no cursor and no empty surface (#167)
    // under sway, always: a dialog run elsewhere finds no window of that app id unseen, and nothing changes
    let mut unseen = std::env::var_os("SWAYSOCK").is_some();
    let (mut drag_drawn, mut drag_owed) = (Instant::now(), false);
    // how long the last picture of a drag took to make and write: the next waits as long (#148)
    let mut drag_cost = Duration::ZERO;
    // the window made clear for a step that puts a window in front (#196)
    let mut cleared = false;
    let mut pointer = "";
    // where the mouse was last over the window: the pointer's shape is asked again there as the work starts and ends (#183)
    let mut mouse_at: Option<(u16, u16)> = None;
    let mut films: Option<transition::Films> = None;
    // the transition drawn now: its box, which one, its frame
    let mut shown_film: Option<ShownFilm> = None;
    let mut film_due: Option<Duration> = None;

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
    let mut prefs_at: Option<Instant> = None;
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
                invalidate_frame(&mut term);
            }
            shown_preview = None;
            dirty = true;
        }
        // the preferences read and the clock written once a second at most, never per event or pointer motion (#196)
        if prefs_at.is_none_or(|t| t.elapsed() >= Duration::from_secs(1)) {
            prefs_at = Some(Instant::now());
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
        }
        // a step that closes the dialog closes it before another frame is drawn (#196)
        if app.quit.is_some() {
            break;
        }
        if let Some(f) = &films {
            app.follow_motion(Instant::now(), f.open.length(), f.close.length());
            dirty |= app.motion.is_some() || shown_film.is_some();
        }
        if dirty {
            // a sound's picture read once: its waveform and its spectrum, before it is drawn
            if let Some(pv) = app.preview.as_mut().filter(|pv| pv.heard.is_none()) {
                if let Some((file, wave)) = pv.shown.as_ref().and_then(|pg| pg.sound.clone()) {
                    pv.heard = image(&file, &mut images).and_then(|i| preview::sound(i, wave));
                }
            }
            let _ = out.write_all(b"\x1b[?2026h");
            let _ = out.flush();
            let frame_drawn = term.draw(|f| {
                let area = f.area();
                // Use the frame actually being drawn, not an earlier size
                // query that can race the compositor's next configure event.
                app.size = (area.width, area.height);
                let mut b = Buffer::empty(Rect::new(0, 0, area.width, area.height));
                drawn = ui::draw(&app, &pal, &last_clock, &mut b);
                let fb = f.buffer_mut();
                for y in 0..area.height {
                    for x in 0..area.width {
                        fb[(x, y)] = b[(x, y)].clone();
                    }
                }
                // the opening alone has no cursor: nothing is there to type into yet (#142)
                if !drawn.alone && !app.list_keys && app.chip_focus.is_none() {
                    f.set_cursor_position(drawn.cursor);
                }
            });
            let frame_drawn = frame_drawn.is_ok();
            if !frame_drawn {
                // SIGWINCH can interrupt an output write. Invalidate the diff
                // and retry on the next event even when the size is unchanged.
                invalidate_frame(&mut term);
            }
            let _ = out.write_all(b"\x1b[?2026l");
            // the mouse still and the frame new: the pointer's shape asked again where it rests
            if let Some((c, r)) = mouse_at {
                let want = pointer_at(&app, &drawn, c, r, false);
                if want != pointer && drag.is_none() {
                    pointer = want;
                    let _ = write!(out, "\x1b]22;{}\x1b\\", want);
                }
            }
            let _ = out.flush();
            // with no opening to wait for (none chosen, or it never came), the first whole frame shows the window
            if unseen && !matches!(app.motion, Some((Reel::Open, _))) {
                reveal();
                unseen = false;
            }
            if app.hidden != cleared && !unseen {
                cleared = app.hidden;
                opacity(if cleared { 0 } else { 1 }, Duration::ZERO);
            }
            if std::mem::take(&mut app.stow) {
                stow();
            }
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
                        if unseen {
                            reveal();
                            unseen = false;
                        }
                    }
                    film_due = Some(Duration::from_millis(left.clamp(1, 1000) as u64));
                }
                _ => shown_film = None,
            }
            dirty = again || !frame_drawn;
        }
        if app.quit.is_some() {
            break;
        }
        // a transition playing wakes for its next frame, a drag for its next picture; else the next event
        // a sound playing: its waveform and its spectrum drawn about thirty times a second, a steady motion (#152)
        let play_due = (app.view == View::Preview && app.preview.as_ref().is_some_and(|pv| pv.playing.is_some())).then(|| Duration::from_millis(33));
        let due = [
            film_due,
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
                // Some launchers do not deliver SIGWINCH to the UI process.
                // Size is cheap to query; a resize must redraw without a keypress.
                if terminal::size().is_ok_and(|size| size != app.size) {
                    app.hover = None;
                    mouse_at = None;
                    app.stop_video();
                    shown_preview = None;
                    invalidate_frame(&mut term);
                    dirty = true;
                }
                let was = app.busy();
                app.tick(Instant::now());
                // a frame for the march while it shows, and when the work starts or ends; none for work nothing shows (#196)
                dirty |= frame_for_tick(
                    was,
                    app.busy(),
                    app.cfg.progress && (app.thinking() || app.view == View::Apps && app.apps.pending.is_some()),
                );
                // a window still unseen after a moment is shown whatever is drawn: never a dialog that cannot be seen
                if unseen && started.elapsed() >= Duration::from_millis(1500) {
                    reveal();
                    unseen = false;
                }
                // an opening whose animation never came: the rows show (#138)
                if films.is_none() && matches!(app.motion, Some((Reel::Open, _))) && started.elapsed() >= Duration::from_millis(1500) {
                    app.motion = None;
                    dirty = true;
                }
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
                let shows = app.incoming(m);
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
                dirty |= shows;
            }
            Ev::Helper(h, r) => {
                app.helper(h, r);
                dirty = true;
            }
            Ev::Term(Event::Resize(_, _)) => {
                app.hover = None;
                mouse_at = None;
                app.stop_video(); // the frame moves: the player would stand where it was (#125)
                shown_preview = None;
                invalidate_frame(&mut term);
                dirty = true;
            }
            Ev::Term(Event::Key(k)) if k.kind == KeyEventKind::Press => {
                app.hover = None;
                dirty = true;
                // a letter typed while the opening plays lands at the prompt and the opening plays on; Enter, Esc, an
                // arrow or a click cut it (#138)
                if !matches!(k.code, KeyCode::Char(_) | KeyCode::Backspace)
                    || k.modifiers.contains(KeyModifiers::CONTROL)
                    || k.modifiers.contains(KeyModifiers::ALT)
                {
                    app.cut_motion();
                }
                if let Some(action) = app.cfg.keys.action(k) {
                    app.hint_key(action);
                } else if let KeyCode::Char(c) = k.code {
                    if !k.modifiers.intersects(KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SUPER) {
                        app.text_key(c);
                    }
                }
            }
            Ev::Term(Event::Paste(p)) => {
                app.paste(&p);
                dirty = true;
            }
            Ev::Term(Event::FocusGained) => {
                app.window_focused = true;
                app.hidden = false;
                dirty = true;
            }
            Ev::Term(Event::FocusLost) => {
                app.window_focused = false;
                app.focus_lost();
                dirty = true;
            }
            Ev::Term(Event::Mouse(m)) => {
                dirty |= frame_for_mouse(m.kind, drag.is_some());
                // the pointer says what a click does where it is (#129)
                let dragging = drag.is_some() && matches!(m.kind, MouseEventKind::Drag(_));
                if m.kind == MouseEventKind::Moved && mouse_at.is_some_and(|old| old != (m.column, m.row)) {
                    let was = app.hover;
                    let lit = (app.sel, app.in_list, app.scroll);
                    app.hover = Some((m.column, m.row));
                    app.pointer_over(drawn.pick_at(m.column, m.row));
                    dirty |= drawn.hover_differs(was, app.hover) || lit != (app.sel, app.in_list, app.scroll);
                }
                mouse_at = Some((m.column, m.row));
                let want = pointer_at(&app, &drawn, m.column, m.row, dragging);
                if want != pointer {
                    pointer = want;
                    let _ = write!(out, "\x1b]22;{}\x1b\\", want);
                    let _ = out.flush();
                }
                match m.kind {
                    MouseEventKind::Down(MouseButton::Left) => {
                        app.cut_motion();
                        // a click raises the dialog over a video's player: it stops, unless the click is the key that pauses it (#125)
                        if !drawn.keys.iter().any(|(a, b, y, _)| m.row == *y && m.column >= *a && m.column < *b) {
                            app.stop_video();
                        }
                        if m.row == 0 && drawn.close.is_some_and(|(a, b)| m.column >= a && m.column < b) {
                            if matches!(app.motion, Some((Reel::Close, _))) {
                                app.quit = Some(0);
                            } else {
                                app.close_window();
                            }
                        } else if drawn.reply_undo.is_some_and(|(a, b, y)| m.row == y && m.column >= a && m.column < b) {
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
                        } else if let Some((_, _, _, n, up)) = drawn.steps.iter().find(|(a, b, y, _, _)| m.row == *y && m.column >= *a && m.column < *b) {
                            app.step_at(*n, *up); // a value's arrow steps it, as left and right do (#175)
                        } else if m.row >= drawn.prompt.0 && m.row <= drawn.prompt.1 {
                            app.focus_prompt();
                        } else if let Some((_, _, _, n, unhide)) =
                            drawn.app_toggles.iter().find(|(a, b, y, _, _)| m.row == *y && m.column >= *a && m.column < *b)
                        {
                            app.apps_toggle(*n, *unhide);
                        } else if let Some(n) = drawn.pick_at(m.column, m.row) {
                            // one click runs a row, everywhere, a folder's and a file's too (#196)
                            app.light(n);
                            app.enter();
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
    let _ = execute!(out, ratatui::crossterm::cursor::SetCursorStyle::DefaultUserShape);
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

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::crossterm::event::{MouseButton, MouseEventKind};

    #[test]
    fn a_click_is_one_frame_and_a_motion_none() {
        // the press draws; the release after it draws nothing unless it ends a drag (#196)
        let frames = [MouseEventKind::Down(MouseButton::Left), MouseEventKind::Up(MouseButton::Left)]
            .into_iter()
            .filter(|k| frame_for_mouse(*k, false))
            .count();
        assert_eq!(frames, 1, "a click");
        assert!(!frame_for_mouse(MouseEventKind::Moved, false), "a motion");
        assert!(
            frame_for_mouse(MouseEventKind::Up(MouseButton::Left), true),
            "a drag let go draws the picture whole"
        );
        assert!(frame_for_mouse(MouseEventKind::ScrollDown, false), "the wheel");
    }

    #[test]
    fn a_tick_draws_only_for_the_march_or_a_change_of_work() {
        assert!(!frame_for_tick(true, true, false), "work nothing shows: no frame");
        assert!(frame_for_tick(false, true, false), "the work starts");
        assert!(frame_for_tick(true, false, false), "the work ends");
        assert!(frame_for_tick(false, false, true), "the march moves");
        assert!(!frame_for_tick(false, false, false), "nothing at all: no frame");
    }
}
