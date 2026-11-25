//! spark-dialog: the event loop, the helpers, and what shows the dialog: a window of its own (--window, 60 by
//! 40 cells of its font), or the terminal it runs in. Run by `spark-shell dialog`.

use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::event::{
    self, DisableBracketedPaste, DisableFocusChange, DisableMouseCapture, EnableBracketedPaste, EnableFocusChange, EnableMouseCapture, Event, KeyCode,
    KeyModifiers, KeyboardEnhancementFlags, MouseButton, MouseEventKind, PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use ratatui::crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::crossterm::{execute, queue};
use ratatui::Terminal;
use spark_dialog::animation::{self, Reel};
use spark_dialog::app::{App, Config, Helper, Job, View};
use spark_dialog::draw::{Pic, Step};
use spark_dialog::grid::{Buffer, Color, Modifier, Rect};
use spark_dialog::mcp::{Incoming, Server};
use spark_dialog::palette::{slots_here, Palette};
use spark_dialog::sixel::Image;
use spark_dialog::{preview, scene, sixel, ui};
use std::io::Write;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const USAGE: &str = "spark-dialog -- the spark dialog, one window for every domain (run by spark-shell dialog)

  spark-dialog [--provider \"PATH WORDS\"]... [--home SECTION] [--title TEXT]
               [--window] [--font \"FACE SIZE\"]
               [--band on|off] [--close on|off] [--progress on|off]
               [--composer plus,model,talk] [--attach \"txt md\"]
               [--spark-shell PATH] [--spark PATH] [--transitions DIR]
               [--semantic SOCKET]
  spark-dialog login ...   the login screen on tty1 (spark-dialog login -h)
";

#[cfg_attr(not(target_os = "linux"), allow(dead_code))] // Drawn, Px and At come from the window, Linux's alone
enum Ev {
    Term(Event),
    /// The terminal is gone (its window closed): the dialog goes with it, and its providers.
    Gone,
    /// The dialog's own window has its frames with the compositor: it is mapped, and can be shown.
    Drawn,
    /// The dialog's own window says its size in pixels, and where the pointer is, before the event it belongs to.
    Px(u32, u32),
    At(f64, f64),
    Font(spark_dialog::draw::Cell, spark_dialog::draw::Cell, (f64, f64), [(f64, f64); 5]),
    Mcp(Incoming),
    Tick,
    Helper(Helper, Result<String, String>),
    /// The transitions' piece, decoded (#122): None when it could not be.
    Films(Option<animation::Films>),
}

struct Args {
    cfg: Config,
    providers: Vec<(String, Vec<String>)>,
    /// A window of the dialog's own, not the terminal it runs in; its text's face in pango's words.
    window: bool,
    font: String,
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
    let (mut window, mut font) = (false, String::from("monospace 12"));
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
            // a window of its own: the compositor frames it, so the dialog draws no band row
            "--window" => {
                window = true;
                cfg.band = false;
            }
            "--font" => {
                font = val("--font")?;
                if font.trim().is_empty() || font.chars().any(char::is_control) {
                    return Err("the font is a face and a size, as \"Monaspace Neon 12\"".into());
                }
            }
            "--home" => cfg.home = Some(val("--home")?),
            "--title" => cfg.title = Some(val("--title")?),
            // off where the window wears the band: no band row, and the title goes to the terminal
            "--band" => cfg.band = onoff(&val("--band")?)?,
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
                if !spark_dialog::app::transitions_ok(&dir) {
                    return Err(format!("{}: the transitions are a whole path, or draw: and a piece's name", dir));
                }
                cfg.transitions = Some(dir);
            }
            "--semantic" => {
                // the socket of spark-shell semantic start: the rows ranked by meaning (v0.130)
                let sock = val("--semantic")?;
                if !sock.starts_with('/') || sock.chars().any(char::is_control) {
                    return Err(format!("{}: the semantic search socket is a whole path", sock));
                }
                cfg.semantic = Some(sock);
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
    Ok(Args { cfg, providers, window, font })
}

/// The dialog's own window (window.rs), where there is one to open.
#[cfg(target_os = "linux")]
type Window = spark_dialog::window::Handle;

#[cfg(target_os = "linux")]
fn open_window(font: &str, title: &str, tx: mpsc::Sender<Ev>) -> Result<Window, String> {
    use spark_dialog::window::{open, Out, Setup};
    let setup = Setup {
        font: font.to_string(),
        app_id: "spark-dialog".into(),
        title: title.to_string(),
        cols: 60,
        rows: 40,
    };
    open(setup, move |o| {
        let _ = tx.send(match o {
            Out::Event(e) => Ev::Term(e),
            Out::Pixels(w, h) => Ev::Px(w, h),
            Out::Font(cell, small, ascent, big) => Ev::Font(cell, small, ascent, big),
            Out::At(x, y) => Ev::At(x, y),
            Out::Drawn => Ev::Drawn,
            Out::Gone => Ev::Gone,
        });
    })
}

/// Away from Linux there is no window to open: the dialog runs in a terminal there.
#[cfg(not(target_os = "linux"))]
struct Window {
    cell: spark_dialog::draw::Cell,
    small: spark_dialog::draw::Cell,
    ascent: (f64, f64),
    big: [(f64, f64); 5],
    size: (u16, u16),
    px: (u32, u32),
}

#[cfg(not(target_os = "linux"))]
impl Window {
    fn frame(&self, _: Vec<spark_dialog::draw::Step>, _: spark_dialog::draw::Rgb) {}
    fn title(&self, _: &str) {}
    fn pointer(&self, _: &'static str) {}
    fn scale(&self) -> u32 {
        1
    }
    fn paste(&self, _: bool) {}
    fn when_drawn(&self) {}
    fn face(&self, _: &str) -> Option<f64> {
        None
    }
}

#[cfg(not(target_os = "linux"))]
fn open_window(_: &str, _: &str, _: mpsc::Sender<Ev>) -> Result<Window, String> {
    Err("a window of its own opens only on Linux, under a Wayland compositor".into())
}

/// The pointer's shape where a click acts (#129): asked of the compositor for a window of the dialog's own, of
/// the terminal (OSC 22, its cursor theme's names) otherwise.
fn point(window: &Option<Window>, out: &mut std::io::Stdout, shape: &'static str) {
    match window {
        Some(w) => w.pointer(shape),
        None => {
            let _ = write!(out, "\x1b]22;{}\x1b\\", shape);
            let _ = out.flush();
        }
    }
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
        Job::Rank(h, sock, query, texts) => {
            std::thread::spawn(move || {
                let r = spark_dialog::semantic::rank(&sock, &query, &texts).map(|s| serde_json::Value::from(s).to_string());
                let _ = tx.send(Ev::Helper(h, r));
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
fn term_color(c: Color) -> ratatui::crossterm::style::Color {
    match c {
        Color::Rgb(r, g, b) => ratatui::crossterm::style::Color::Rgb { r, g, b },
        Color::Indexed(n) => ratatui::crossterm::style::Color::AnsiValue(n),
        Color::Reset => ratatui::crossterm::style::Color::Reset,
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

/// An icon's sixel, made once: its file, its row's ground, its box in pixels (#230).
type IconKey = (String, Option<[u8; 3]>, u32, u32);

/// A color's red, green and blue, where it is one; a slot's index has none (the icon is then drawn unblended).
fn rgb_of(c: Color) -> Option<[u8; 3]> {
    match c {
        Color::Rgb(r, g, b) => Some([r, g, b]),
        _ => None,
    }
}

/// An app's icon decoded once for its file and its time (#230): a regular PNG of 1 MB at most from the apps
/// adapter's cache, None while it is not there. The adapter draws it at the cell's size, so it is small.
fn icon_image<'a>(file: &str, cache: &'a mut std::collections::HashMap<String, Option<(std::time::SystemTime, Image)>>) -> Option<&'a Image> {
    let meta = std::fs::symlink_metadata(file).ok().filter(|m| m.is_file() && m.len() <= 1 << 20)?;
    let when = meta.modified().ok()?;
    let fresh = cache.get(file).is_some_and(|c| c.as_ref().is_some_and(|(t, _)| *t == when));
    if !fresh {
        let img = std::fs::read(file).ok().and_then(|b| sixel::decode(&b)).map(|i| (when, i));
        cache.insert(file.to_string(), img);
    }
    cache.get(file).and_then(|c| c.as_ref()).map(|(_, i)| i)
}

/// Cells as the frame has them, written again (#230): a place an icon left, which the buffer's diff may think
/// unchanged, so the terminal would keep the icon's pixels there.
fn repaint(out: &mut std::io::Stdout, buf: &Buffer, x: u16, y: u16, w: u16) {
    use ratatui::crossterm::style::{Attribute, Print, ResetColor, SetAttribute, SetBackgroundColor, SetForegroundColor};
    let _ = queue!(out, ratatui::crossterm::cursor::SavePosition);
    for cx in x..x.saturating_add(w) {
        if cx >= buf.area.width || y >= buf.area.height {
            break;
        }
        let c = &buf[(cx, y)];
        let bold = if c.modifier.contains(Modifier::BOLD) {
            Attribute::Bold
        } else {
            Attribute::NormalIntensity
        };
        let _ = queue!(
            out,
            ratatui::crossterm::cursor::MoveTo(cx, y),
            SetAttribute(bold),
            SetForegroundColor(term_color(c.fg)),
            SetBackgroundColor(term_color(c.bg)),
            Print(c.symbol())
        );
    }
    let _ = queue!(out, ResetColor, SetAttribute(Attribute::Reset), ratatui::crossterm::cursor::RestorePosition);
}

/// A cell's size in pixels, as the terminal says; None where it does not.
fn cell_px() -> Option<(u32, u32)> {
    terminal::window_size()
        .ok()
        .filter(|w| w.columns > 0 && w.rows > 0 && w.width > 0 && w.height > 0)
        .map(|w| ((w.width / w.columns) as u32, (w.height / w.rows) as u32))
}

/// The most a picture's file may weigh: what 4096 by 4096 pixels, the most the dialog decodes, take with no
/// compression at all. A photo's full picture, asked for by a zoom past the page's pixels, is a PNG of 25 MB and
/// more: a cap under that left the view empty at the zoom step that asked for it.
const PICTURE_MOST: u64 = 64 << 20;

/// A picture's file decoded once for its file and its time: a regular PNG of PICTURE_MOST at most, None while
/// it is not there yet. The preview zooms, moves and turns the one kept (#120).
fn image<'a>(file: &str, cache: &'a mut Option<(String, std::time::SystemTime, Image)>) -> Option<&'a Image> {
    let meta = std::fs::metadata(file).ok().filter(|m| m.is_file() && m.len() <= PICTURE_MOST)?;
    let when = meta.modified().ok()?;
    if !cache.as_ref().is_some_and(|(f, t, _)| f == file && *t == when) {
        *cache = Some((file.to_string(), when, sixel::decode(&std::fs::read(file).ok()?)?));
    }
    cache.as_ref().map(|(_, _, i)| i)
}

/// The window's preview picture as pixels, kept until its place, its file, its view or the screen's scale changes.
struct WinPreview {
    of: ui::Picture,
    scale: u32,
    pic: Arc<Pic>,
    /// The size drawn, and the source's own, in pixels.
    size: (u32, u32),
    source: (u32, u32),
}

/// What a file shows in its details, made: its file, its box in the screen's pixels, a sound's waveform height.
type PeekKey = (String, u32, u32, Option<u32>, bool);

/// A transition drawn: its box, which one, its frame.
type ShownFilm = ((u16, u16, u16, u16), Reel, usize);
/// A piece beside a list drawn (#132): its box, its folder, the wait or the open, its frame.
/// A sound's spectrogram in the palette: its file, the palette's ramp, its box, the picture.
type Tinted = (String, [[u8; 3]; 4], (u32, u32), Image);

/// A piece's three films from its folder; @2x where a cell is twice the usual height. None where one is
/// missing or no GIF. `draw:PIECE` draws the piece in the palette the window wears (pieces.rs): a palette
/// with no GIFs of its own, a theme from a picture or from words.
fn decode_films(dir: &str, palette: &std::collections::HashMap<String, String>, kind: FilmKind) -> Option<animation::Films> {
    let FilmKind { double, pixels } = kind;
    if let Some(name) = dir.strip_prefix("draw:") {
        let roles = spark_dialog::pieces::Roles::from(|k| palette.get(k).cloned())?;
        let scale = if double { 2 } else { 1 };
        return if pixels {
            spark_dialog::pieces::films_pixels(name, &roles, scale)
        } else {
            spark_dialog::pieces::films(name, &roles, scale)
        };
    }
    let one = |reel: &str| {
        // a painted piece: its own WebP, in its own colors, read as it plays; in a folder of its own (DIR/open.webp) or
        // beside its theme's pictures (THEME-dialog, its reels THEME-dialog-open.webp)
        for f in [format!("{}/{}.webp", dir, reel), format!("{}-{}.webp", dir, reel)] {
            if let Some(bytes) = std::fs::read(&f).ok().filter(|b| b.len() <= 16 << 20) {
                return animation::film_webp(bytes, pixels);
            }
        }
        let f = format!("{}/{}{}.gif", dir, reel, if double { "@2x" } else { "" });
        let bytes = std::fs::read(&f).ok().filter(|b| b.len() <= 4 << 20)?;
        if pixels {
            animation::film_pixels(&bytes)
        } else {
            animation::film(&bytes)
        }
    };
    Some(animation::Films {
        open: one("open")?,
        close: one("close")?,
    })
}

/// The transitions' piece (#122), decoded aside so the window draws at once. Again when a theme step
/// changes the look (#126).
fn spawn_films(dir: String, palette: std::collections::HashMap<String, String>, kind: FilmKind, tx: mpsc::Sender<Ev>) {
    std::thread::spawn(move || {
        let _ = tx.send(Ev::Films(decode_films(&dir, &palette, kind)));
    });
}

/// How a piece's films are read: at twice the size where a cell is twice the usual height, and as pixels for a
/// window that paints them itself, as sixel for a terminal.
#[derive(Clone, Copy, PartialEq)]
struct FilmKind {
    double: bool,
    pixels: bool,
}

/// The palette's colors a drawn piece takes (pieces::Roles), as the environment gave them at the start.
fn piece_colors() -> std::collections::HashMap<String, String> {
    let keys = ["PANEL_BG", "HEX_FG", "PANEL_MUTED", "HEX_ACCENT"]
        .into_iter()
        .map(String::from)
        .chain((0..16).map(|i| format!("HEX_ANSI_{}", i)));
    keys.filter_map(|k| std::env::var(&k).ok().map(|v| (k, v))).collect()
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

/// The pointer in a window of the dialog's own: where it is, where it was, the screen's scale.
type Moved = ((f64, f64), (f64, f64), f64);

/// How far a drag moved a zoomed picture, in the screen's pixels. A window of the dialog's own says the pointer
/// by the pixel (`at`, where it was before, the screen's scale): the picture follows it by the pixel. A terminal
/// says cells: the cells moved, at a cell's size.
fn drag_by(window: Option<Moved>, cells: (f64, f64), cell: (u32, u32)) -> (f64, f64) {
    match window {
        Some((at, was, scale)) => ((at.0 - was.0) * scale, (at.1 - was.1) * scale),
        None => (cells.0 * cell.0 as f64, cells.1 * cell.1 as f64),
    }
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

/// The same for either window. foot's is mapped before the dialog runs, so a moment's wait is enough. The
/// dialog's own maps with its first frame, and how long that frame takes to paint is not known: the window says
/// when the frame is with the compositor (Ev::Drawn), and it is shown then. Shown sooner, the command finds no
/// window, and the one that maps after it stays unseen. `asked` holds when the window was asked.
fn show(window: &Option<Window>, asked: &mut Option<Instant>) {
    match window {
        Some(w) => {
            w.when_drawn();
            *asked = Some(Instant::now());
        }
        None => reveal(),
    }
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
    // where a click acts: the x, minimize, a chip, a key, the waveform (it seeks), a row of the list
    let clicks = (row == 0 && drawn.close.is_some_and(|(a, b)| span(a, b, 0)))
        || (row == 0 && drawn.minimize.is_some_and(|(a, b)| span(a, b, 0)))
        || (row == 0 && app.can_go_back() && (drawn.back.is_some_and(|(a, b)| span(a, b, 0)) || drawn.title.is_some_and(|(a, b)| span(a, b, 0))))
        || drawn.heads.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.chips.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.keys.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.wave.is_some_and(on)
        || drawn.reply_undo.is_some_and(|(a, b, y)| span(a, b, y))
        || drawn.trial.iter().any(|(a, b, y, _)| span(*a, *b, *y))
        || drawn.other_path.is_some_and(|(a, b, y)| span(a, b, y))
        || drawn.other_pick_at(col, row).is_some();
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

/// A box in the screen's pixels in the window's own, which sway counts by: a video's player is laid by them.
fn logical(scale: u32, (x, y, w, h): (u32, u32, u32, u32)) -> (u32, u32, u32, u32) {
    (x / scale, y / scale, w / scale, h / scale)
}

/// The text's measures the layout in pixels places by: the window's font says them.
fn metrics(w: &Window) -> scene::Metrics {
    scene::Metrics {
        cw: w.cell.w,
        ch: w.cell.h,
        up: w.ascent.0,
        sw: w.small.w,
        sh: w.small.h,
        sup: w.ascent.1,
        big: w.big,
    }
}

/// The cell of the grid's rows the pointer is over, where a frame of the layout in pixels holds a place's grid
/// rows: the rows' own columns and rows, as the grid counted them.
fn grid_cell(at: Option<(scene::GridBody, u16)>, (x, y): (f64, f64), cell: spark_dialog::draw::Cell) -> Option<(u16, u16)> {
    let (g, first) = at?;
    let inside = x >= g.clip.0.max(g.x) && x < g.clip.0 + g.clip.2 && y >= g.clip.1.max(g.y) && y < g.clip.1 + g.clip.3;
    inside.then(|| (((x - g.x) / cell.w) as u16, ((y - g.y) / cell.h) as u16 + first))
}

/// A press on a list of the layout in pixels, not let go yet: the list, where the press began and how far the list
/// was scrolled then, what a click there does, and whether the pointer has since moved far enough to be a drag.
struct Press {
    key: String,
    y0: f64,
    off0: f64,
    most: f64,
    target: Option<scene::Target>,
    moved: bool,
}

/// How far a press may move and still be a click, in pixels: a finger is never still.
const DRAG_SLOP: f64 = 8.0;

/// What a click on a place of the layout in pixels does.
fn act(app: &mut App, target: scene::Target) {
    match target {
        scene::Target::Pick(n) => app.clicked(n, Instant::now()),
        scene::Target::Key(key) => app.hint_key(key),
        scene::Target::Chip(c) => app.chip(c),
        scene::Target::Prompt => app.focus_prompt(),
        scene::Target::Undo => app.undo_now(),
        scene::Target::Head(label) => app.apps_heading(&label),
        scene::Target::Home => app.go_home(),
        scene::Target::Back => app.back_key(),
        scene::Target::BackBy(levels) => {
            for _ in 0..levels.min(8) {
                if app.can_go_back() {
                    app.back_key();
                }
            }
        }
        scene::Target::ListApp(id) => app.apps_show(&id),
        scene::Target::PaneRow(n) if app.view == View::Apps => app.apps_pane_row(n, Instant::now()),
        scene::Target::PaneRow(n) => app.files_pane_row(n, Instant::now()),
        scene::Target::Step(n, up) => app.step_at(n, up),
        scene::Target::Option(n, k) => app.option_at(n, k),
        scene::Target::Screen(..) => {} // the press is the map's own: it may be a drag
        scene::Target::Trial(keep) => app.trial_end(keep),
        scene::Target::Crumb(uri) => app.files_go_to(&uri),
        scene::Target::OtherRow(n) => app.pane_clicked(n, Instant::now()),
        scene::Target::OtherPane => {
            app.files_pane();
        }
        scene::Target::ListRow(n) => app.files_list_row(n, Instant::now()),
    }
}

/// The pointer's shape over a frame of the layout in pixels: the text's on the line, a hand where a click acts,
/// and over a place's grid rows what the grid says of the cell.
fn pointer_in(app: &App, sc: &scene::Scene, drawn: &ui::Drawn, at: (f64, f64), cell: Option<(u16, u16)>, dragging: bool) -> &'static str {
    if dragging {
        return "grabbing";
    }
    match (sc.hit(at.0, at.1), cell) {
        (Some(scene::Target::Prompt), _) => "text",
        (Some(_), _) => "pointer",
        (None, Some((c, r))) => pointer_at(app, drawn, c, r, false),
        (None, None) => "default",
    }
}

/// Force a full repaint without querying the cursor. Terminal::clear asks the
/// input reader for a cursor report; with event::read on another thread that
/// can block resize until the next key. A fullscreen resize only writes output.
fn invalidate_frame(term: &mut Option<Terminal<CrosstermBackend<std::io::Stdout>>>) {
    let Some(term) = term else { return };
    if let Ok(size) = term.size() {
        let _ = term.resize(ratatui::layout::Rect::new(0, 0, size.width, size.height));
    }
}

#[path = "login/run.rs"]
mod login_run;

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
    // what the dialog starts (its providers, a video's player) is told the window is the dialog's own: a place in
    // it is counted from its corner, with no terminal's padding. Said before any thread starts
    if a.window {
        std::env::set_var("SPARK_DIALOG_OWN_WINDOW", "1");
    }
    // a terminal's slots recolor with the terminal; a window of the dialog's own has none, and wears the colors
    let slots = slots_here() && !a.window;
    // the palette as colors, slots or not: a picture tinted in it needs them (a spectrogram, #156)
    let mut colors = Palette::from(|k| std::env::var(k).ok());
    let mut pal = if a.window { colors.clone() } else { Palette::from_env() };
    let labels: Vec<String> = a.providers.iter().map(|(l, _)| l.clone()).collect();
    let mut app = App::new(a.cfg, &labels);
    app.glyphs = spark_dialog::glyphs::Glyphs::from_env();
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
    // what shows the dialog: a window of its own, which hands the loop its keys, its pointer and its size, or
    // the terminal it runs in
    let mut window: Option<Window> = a.window.then(|| match open_window(&a.font, &app.window_title(), tx.clone()) {
        Ok(w) => w,
        Err(e) => {
            println!("spark-dialog -- {}", e);
            std::process::exit(1);
        }
    });
    // the window's size in cells: the one asked for until the window says another
    let mut window_size = window.as_ref().map_or((0, 0), |w| w.size);
    // and in pixels, where the pointer is in them, the frame of the layout in pixels last drawn, and where a
    // place's grid rows stand in it with the first of them
    let mut window_px = window.as_ref().map_or((0.0, 0.0), |w| (w.px.0 as f64, w.px.1 as f64));
    let mut at_px = (-1.0, -1.0);
    let mut shown: Option<scene::Scene> = None;
    let mut grid_at: Option<(scene::GridBody, u16)> = None;
    // how the lists of the last frame were scrolled: a list keeps its place by it, and a drag moves it there; and
    // a press on a list that is not let go yet
    let mut scrolls: Vec<scene::Scrolled> = vec![];
    let mut press: Option<Press> = None;
    app.pixels = window.is_some();
    let mut kitty = false;
    if window.is_none() {
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
        kitty = terminal::supports_keyboard_enhancement().unwrap_or(false);
        if kitty {
            // and a key held says so, so copy, move and trash can count it once (keys.rs)
            let _ = execute!(
                out,
                PushKeyboardEnhancementFlags(KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES | KeyboardEnhancementFlags::REPORT_EVENT_TYPES)
            );
        }
    }
    if window.is_none() {
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
    // a cell's size in the screen's pixels: the window's font and its screen's scale say it, or the terminal
    let cell_size = |window: &Option<Window>| match window {
        Some(w) => Some(((w.cell.w * w.scale() as f64) as u32, (w.cell.h * w.scale() as f64) as u32)),
        None => cell_px(),
    };
    let film_kind = |window: &Option<Window>| FilmKind {
        double: cell_size(window).is_some_and(|(_, ch)| ch >= 30),
        pixels: window.is_some(),
    };
    // the films as they were last asked for: asked again when the window's screen has another scale
    let mut films_as = film_kind(&window);
    // the colors a drawn piece takes: the environment's, then each theme step's palette over them
    let mut piece_pal = piece_colors();
    if let Some(dir) = app.cfg.transitions.clone() {
        spawn_films(dir, piece_pal.clone(), films_as, tx.clone());
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
    // the dialog's own window asked to say when its frame is drawn, and not yet heard from
    let mut drawn_asked: Option<Instant> = None;
    // the title last written to the terminal, where the window wears the band
    let mut window_title = String::new();
    let (mut drag_drawn, mut drag_owed) = (Instant::now(), false);
    // how long the last picture of a drag took to make and write: the next waits as long (#148)
    let mut drag_cost = Duration::ZERO;
    // the window made clear for a step that puts a window in front (#196)
    let mut cleared = false;
    let mut pointer = "";
    // where the mouse was last over the window: the pointer's shape is asked again there as the work starts and ends (#183)
    let mut mouse_at: Option<(u16, u16)> = None;
    let mut films: Option<animation::Films> = None;
    // the transition drawn now: its box, which one, its frame
    let mut shown_film: Option<ShownFilm> = None;
    let mut film_due: Option<Duration> = None;

    let mut term = match &window {
        Some(_) => None,
        None => match Terminal::new(CrosstermBackend::new(std::io::stdout())) {
            Ok(t) => Some(t),
            Err(e) => {
                let _ = terminal::disable_raw_mode();
                println!("spark-dialog -- {}", e);
                std::process::exit(1);
            }
        },
    };
    let listening = Arc::new(Mutex::new(None));
    // a terminal's pictures are sixel; a window of the dialog's own paints its pictures itself
    let sixel_ok = window.is_none() && sixel::terminal_draws_it(&std::env::var("TERM").unwrap_or_default());
    let pictures = sixel_ok || window.is_some();
    // the window's pictures as pixels, each made once: the preview's for its place and view (with its size and its
    // source's), an icon's for its file and box
    let mut win_preview: Option<WinPreview> = None;
    let mut win_icons: std::collections::HashMap<(String, u32, u32), Arc<Pic>> = Default::default();
    // the picture beside a list (a wallpaper's): where it is drawn now, when one was last tried, the last one made
    let mut shown_preview: Option<ui::Picture> = None;
    let mut preview_tried = Instant::now();
    let mut images = None;
    // a sound's spectrogram in the palette's colors, filling its box: made once a sound, a palette and a box
    let mut tinted: Option<Tinted> = None;
    // what a file shows in its details beside the list (the layout in pixels): its picture's file read once, and
    // the picture made once for its file, its box and the screen's scale
    let mut peek_images = None;
    let mut win_peek: Option<(PeekKey, Arc<Pic>, (u32, u32))> = None;
    let mut peek_tried = Instant::now();
    // the pictures of the screens in the display page's map
    let mut thumbs = spark_dialog::thumbs::Thumbs::default();
    // a drag on a picture: where the pointer was, in the event's cells and, for a window of the dialog's own, in
    // its pixels
    let mut drag: Option<(u16, u16)> = None;
    let mut drag_px = (0.0, 0.0);
    let mut drawn = ui::Drawn::default();
    // the apps' icons (#230): the ones on screen now, each file decoded once for its time, each sixel made once for
    // its file, ground and box; the frame as last drawn, for the cells an icon leaves
    let mut shown_icons: Vec<ui::IconAt> = vec![];
    let mut icon_images: std::collections::HashMap<String, Option<(std::time::SystemTime, Image)>> = Default::default();
    let mut icon_sixels: std::collections::HashMap<IconKey, Option<String>> = Default::default();
    let mut frame_buf = Buffer::empty(Rect::new(0, 0, 0, 0));
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
            piece_pal.extend(m.iter().filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string()))));
            if !slots {
                pal = colors.clone();
                if let (Color::Rgb(r, g, b), None) = (pal.surface, &window) {
                    let _ = write!(out, "\x1b]11;#{:02x}{:02x}{:02x}\x1b\\", r, g, b);
                    let _ = out.flush();
                }
                invalidate_frame(&mut term);
                shown_icons.clear();
            }
            shown_preview = None;
            win_preview = None; // a sound's picture wears the palette's tones: made again in the new ones
            dirty = true;
        }
        // the preferences read and the clock written once a second at most, never per event or pointer motion (#196)
        if prefs_at.is_none_or(|t| t.elapsed() >= Duration::from_secs(1)) {
            prefs_at = Some(Instant::now());
            let prefs = spark_dialog::preferences::read();
            // icons before the apps' names (#230): DIALOG_ICONS on, in a terminal that draws sixel, drawn at the cell's
            // size; turned on, or the cell's size changed, the catalog is read again for icons drawn at it
            // a window of the dialog's own draws them larger, and the one of an app's details larger still: asked for
            // at that size, in the screen's pixels, and drawn smaller in a row
            let px = match &window {
                Some(w) => ((metrics(w).px(48.0) * w.scale() as f64) as u32).min(256),
                None => cell_size(&window)
                    .map(|(cw, chh)| chh.min(cw * spark_dialog::page::ICON_CELLS as u32))
                    .unwrap_or(0),
            };
            let icons = !prefs.icons_off && pictures && px >= 8;
            if prefs.spacing != app.apps.spacing {
                app.apps.spacing = prefs.spacing;
                dirty = true;
            }
            if icons != app.apps.icons || (icons && px != app.apps.icon_px) {
                let again = icons && (!app.apps.icons || px != app.apps.icon_px);
                app.apps.icons = icons;
                app.apps.icon_px = px;
                if again && app.apps.loaded && app.apps.pending.is_none() {
                    app.apps_request(serde_json::json!({"op":"catalog"}));
                }
                dirty = true;
            }
            if app.monday_first != prefs.monday {
                app.monday_first = prefs.monday;
                dirty = true;
            }
            let now_clock = clock(prefs.twelve);
            if now_clock != last_clock {
                last_clock = now_clock;
                app.clock = last_clock.clone();
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
        // the layout in pixels: home's row lit at the empty line, an app's details beside the list
        let was = (app.in_list, app.apps.pane, app.apps.pending.is_some());
        app.rest_light();
        app.apps_follow();
        // what the file lit shows, for its details beside the list: asked for here, drawn when it comes
        app.files_follow();
        dirty |= was != (app.in_list, app.apps.pane, app.apps.pending.is_some());
        if dirty {
            // the window's frame set a picture's size the layout reads: drawn once more
            let mut window_again = false;
            // a sound's picture read once: its waveform and its spectrum, before it is drawn
            if let Some(pv) = app.preview.as_mut().filter(|pv| pv.heard.is_none()) {
                if let Some((file, wave)) = pv.shown.as_ref().and_then(|pg| pg.sound.clone()) {
                    pv.heard = image(&file, &mut images).and_then(|i| preview::sound(i, wave));
                }
            }
            let frame_drawn = if let Some(w) = &window {
                let tones = spark_dialog::draw::tones(&pal);
                let m = metrics(w);
                // the opening plays alone on the whole window, as the grid has it (#142). Every other frame is the
                // layout in pixels: its own steps, and inside it the grid's rows of a place it has not drawn yet,
                // laid at the body's corner and kept inside the body's box
                // a window too small for the frame is the grid's too: it says to make the window larger
                let alone = matches!(app.motion, Some((Reel::Open, _))) || !scene::fits(&m, window_px.0, window_px.1);
                let mut steps;
                let (mut ox, mut oy) = (0.0, 0.0);
                let mut boxed = false;
                grid_at = None;
                if alone {
                    app.size = window_size;
                    let mut b = Buffer::empty(Rect::new(0, 0, window_size.0, window_size.1));
                    drawn = ui::draw(&app, &pal, &last_clock, &mut b);
                    steps = spark_dialog::draw::steps(&b, w.cell, &tones);
                    frame_buf = b;
                    shown = None;
                } else {
                    app.pane_fits = scene::splits(&m, window_px.0);
                    app.wide = scene::wide(&m, window_px.0);
                    app.wide3 = scene::wide3(&m, window_px.0);
                    // a typeface's specimen: its family asked of the window once, before the frame that draws it
                    for family in app.faces_wanted() {
                        let width = w.face(&family);
                        app.faces.insert(family, width);
                    }
                    app.size = scene::size(&app, &m, window_px.0, window_px.1);
                    let sc = scene::build(&app, &pal, &m, window_px.0, window_px.1, &scrolls);
                    scrolls = sc.lists.iter().map(|l| l.at.clone()).collect();
                    steps = thumbs.put(sc.steps.clone(), w.scale());
                    drawn = ui::Drawn::default();
                    if let Some(g) = sc.grid {
                        let mut b = Buffer::empty(Rect::new(0, 0, app.size.0, app.size.1));
                        drawn = ui::draw(&app, &pal, &last_clock, &mut b);
                        let first = ui::head(&app).content;
                        (ox, oy) = (g.x, g.y - first as f64 * w.cell.h);
                        steps.push(Step::Clip {
                            x: g.clip.0,
                            y: g.clip.1,
                            w: g.clip.2,
                            h: g.clip.3,
                        });
                        let rows = spark_dialog::draw::rows_steps(&b, w.cell, &tones, first, first + g.rows);
                        // a bar that starts at the grid's first column is a lit row's, of the list or of the left of two
                        // panes: it starts at the window's edge, as a row of the layout in pixels does. Its other end is
                        // the grid's, which reaches the window's other edge
                        let rows = rows
                            .into_iter()
                            .map(|st| match st {
                                Step::Fill { x, y, w: fw, h, color } if x <= 0.0 => Step::Fill {
                                    x: -g.x,
                                    y,
                                    w: fw + g.x,
                                    h,
                                    color,
                                },
                                st => st,
                            })
                            .collect();
                        steps.extend(spark_dialog::draw::moved(rows, g.x, g.y));
                        boxed = true;
                        frame_buf = b;
                        grid_at = Some((g, first));
                    }
                    shown = Some(sc);
                }
                // the pictures, each a step over the cells the grid left for it. A frame is drawn whole, so a picture
                // that is gone is simply not drawn; each is made for the screen's pixels
                let scale = w.scale();
                let (cw, chh) = (((w.cell.w * scale as f64) as u32).max(1), ((w.cell.h * scale as f64) as u32).max(1));
                let place = |x: u16, y: u16, pic: &Arc<Pic>| Step::Picture {
                    x: ox + x as f64 * w.cell.w,
                    y: oy + y as f64 * w.cell.h,
                    scale: scale as f64,
                    pic: pic.clone(),
                };
                // the grid's corner in the screen's pixels: a video plays over the picture, placed by them
                let (dox, doy) = ((ox * scale as f64) as u32, (oy * scale as f64) as u32);
                // the picture beside a list, or the preview's: made again when its place, its file or its view changed
                match drawn.preview.clone() {
                    Some(p) => {
                        let (bw, bh) = (p.w as u32 * cw, p.h as u32 * chh);
                        if win_preview.as_ref().is_none_or(|kept| kept.of != p || kept.scale != scale) {
                            win_preview = None;
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
                            if let Some((img, fitted)) = img.and_then(|img| sixel::fit(img, bw, bh, &p.view).map(|f| (img, f))) {
                                win_preview = Some(WinPreview {
                                    of: p.clone(),
                                    scale,
                                    pic: Arc::new(Pic::of(&fitted)),
                                    size: (fitted.w, fitted.h),
                                    source: (img.w, img.h),
                                });
                            }
                            preview_tried = Instant::now();
                        }
                        if let Some(kept) = &win_preview {
                            let (pw, ph) = kept.size;
                            // in the middle of its box by whole cells
                            let (dx, dy) = ((bw.saturating_sub(pw) / 2 / cw) as u16, (bh.saturating_sub(ph) / 2 / chh) as u16);
                            // the preview's picture: its box and its pixels, for the zoom and the move (#120), and where it
                            // is, in pixels: a video plays over it (#125)
                            if let Some(pv) = app.preview.as_mut().filter(|_| app.view == View::Preview && !p.spectrogram) {
                                if pv.px != (bw, bh) || pv.src != kept.source {
                                    (pv.px, pv.src) = ((bw, bh), kept.source);
                                    window_again = true;
                                }
                                let at = (dox + (p.x + dx) as u32 * cw, doy + (p.y + dy) as u32 * chh, pw, ph);
                                pv.frame = Some(logical(scale, at));
                            }
                            steps.push(place(p.x + dx, p.y + dy, &kept.pic));
                        }
                        shown_preview = win_preview.as_ref().map(|_| p);
                    }
                    None => {
                        win_preview = None;
                        shown_preview = None;
                    }
                }
                // the apps' icons (#230): a lit row's ground under its icon first, since the grid leaves an icon's cells
                // on the window's ground
                for icon in &drawn.icons {
                    let cells = spark_dialog::page::ICON_CELLS;
                    let (bw, bh) = (cells as u32 * cw, chh);
                    let key = (icon.file.clone(), bw, bh);
                    if !win_icons.contains_key(&key) {
                        let made = icon_image(&icon.file, &mut icon_images).and_then(|img| sixel::icon_box(img, bw, bh, None));
                        if let Some(made) = made {
                            win_icons.insert(key.clone(), Arc::new(Pic::of(&made)));
                        }
                    }
                    if let Some(pic) = win_icons.get(&key) {
                        if let (true, Some(lit)) = (icon.lit, rgb_of(pal.lit)) {
                            steps.push(Step::Fill {
                                x: ox + icon.x as f64 * w.cell.w,
                                y: oy + icon.y as f64 * w.cell.h,
                                w: cells as f64 * w.cell.w,
                                h: w.cell.h,
                                color: lit,
                            });
                        }
                        steps.push(place(icon.x, icon.y, pic));
                    }
                }
                // a transition: its frame now, in the middle of its box by whole cells, at the GIF's own pace (#122)
                film_due = None;
                match (drawn.film, &films) {
                    (Some((x, y, fw, fh, reel, since)), Some(f)) => {
                        let ms = Instant::now().saturating_duration_since(since).as_millis();
                        let film = f.of(reel);
                        let (k, left) = film.at(ms, false);
                        let shown = k;
                        let (dx, dy) = (
                            ((fw as u32 * cw).saturating_sub(film.w) / 2 / cw) as u16,
                            ((fh as u32 * chh).saturating_sub(film.h) / 2 / chh) as u16,
                        );
                        if let Some(pic) = film.pic(k) {
                            steps.push(place(x + dx, y + dy, &pic));
                        }
                        shown_film = Some(((x, y, fw, fh), reel, shown));
                        // the opening's first frame is on the window: it is shown (#167)
                        if unseen {
                            show(&window, &mut drawn_asked);
                            unseen = false;
                        }
                        film_due = Some(Duration::from_millis(left.clamp(1, 1000) as u64));
                    }
                    _ => shown_film = None,
                }
                if boxed {
                    steps.push(Step::Unclip);
                }
                // the apps' pictures of the layout in pixels, each made once for its file and its box, kept inside
                // the list they stand in
                if let Some(sc) = shown.as_ref().filter(|sc| !sc.icons.is_empty()) {
                    let (x, y, bw, bh) = sc.icon_clip;
                    steps.push(Step::Clip { x, y, w: bw, h: bh });
                    for icon in &sc.icons {
                        let side = ((icon.side * scale as f64) as u32).max(1);
                        let key = (icon.file.clone(), side, side);
                        if !win_icons.contains_key(&key) {
                            let made = icon_image(&icon.file, &mut icon_images).and_then(|img| sixel::icon_box(img, side, side, None));
                            if let Some(made) = made {
                                win_icons.insert(key.clone(), Arc::new(Pic::of(&made)));
                            }
                        }
                        if let Some(pic) = win_icons.get(&key) {
                            steps.push(Step::Picture {
                                x: icon.x,
                                y: icon.y,
                                scale: scale as f64,
                                pic: pic.clone(),
                            });
                        }
                    }
                    steps.push(Step::Unclip);
                }
                // what a file shows in its details: fitted in its box with its shape kept, a sound's picture in the
                // palette's tones over the whole of it; in the middle of the box, kept inside the list
                if let Some(sc) = shown.as_ref().filter(|sc| !sc.pictures.is_empty()) {
                    let (x, y, bw, bh) = sc.icon_clip;
                    steps.push(Step::Clip { x, y, w: bw, h: bh });
                    for p in &sc.pictures {
                        let (pw, ph) = ((p.w * scale as f64) as u32, (p.h * scale as f64) as u32);
                        let key: PeekKey = (p.file.clone(), pw, ph, p.wave, p.corner);
                        if win_peek.as_ref().is_none_or(|(k, ..)| *k != key) {
                            let made = image(&p.file, &mut peek_images).and_then(|img| match p.wave {
                                Some(wave) => {
                                    let ramp = colors.ramp().unwrap_or([[0x1f; 3], [0x7f; 3], [0x55, 0x55, 0xff], [0xaa; 3]]);
                                    // a page in large type shows a sound's waveform, a strip; the details its spectrogram
                                    if p.corner {
                                        (wave > 0 && wave < img.h).then(|| img.rows(0, wave).tinted(&ramp).resized(pw.max(8), ph.max(8)))
                                    } else {
                                        preview::sound(img, wave).map(|s| s.spectrogram.tinted(&ramp).resized(pw.max(8), ph.max(8)))
                                    }
                                }
                                None => sixel::fit(img, pw, ph, &sixel::Viewport::FIT),
                            });
                            win_peek = made.map(|img| (key, Arc::new(Pic::of(&img)), (img.w, img.h)));
                            peek_tried = Instant::now();
                        }
                        if let Some((_, pic, (iw, ih))) = &win_peek {
                            steps.push(Step::Picture {
                                x: if p.corner {
                                    p.x
                                } else {
                                    (p.x + (p.w - *iw as f64 / scale as f64) / 2.0).round()
                                },
                                y: if p.corner {
                                    p.y
                                } else {
                                    (p.y + (p.h - *ih as f64 / scale as f64) / 2.0).round()
                                },
                                scale: scale as f64,
                                pic: pic.clone(),
                            });
                        }
                    }
                    steps.push(Step::Unclip);
                } else {
                    win_peek = None;
                }
                w.frame(steps, tones.ground);
                true
            } else if let Some(term) = term.as_mut() {
                let _ = out.write_all(b"\x1b[?2026h");
                let _ = out.flush();
                let frame_drawn = term.draw(|f| {
                    let area = f.area();
                    // Use the frame actually being drawn, not an earlier size
                    // query that can race the compositor's next configure event.
                    app.size = (area.width, area.height);
                    let mut b = Buffer::empty(Rect::new(0, 0, area.width, area.height));
                    drawn = ui::draw(&app, &pal, &last_clock, &mut b);
                    frame_buf = b.clone();
                    // the grid is the dialog's own; the terminal is handed its cells
                    spark_dialog::terminal::blit(&b, f.buffer_mut());
                    // the opening alone has no cursor: nothing is there to type into yet (#142)
                    if !drawn.alone && !app.list_keys && app.chip_focus.is_none() {
                        f.set_cursor_position(drawn.cursor);
                    }
                });
                let _ = out.write_all(b"\x1b[?2026l");
                frame_drawn.is_ok()
            } else {
                false
            };
            if !frame_drawn {
                // SIGWINCH can interrupt an output write. Invalidate the diff
                // and retry on the next event even when the size is unchanged.
                invalidate_frame(&mut term);
                shown_icons.clear();
            }
            // the mouse still and the frame new: the pointer's shape asked again where it rests
            if let Some((c, r)) = mouse_at {
                let want = match (&shown, &window) {
                    (Some(sc), Some(w)) => pointer_in(&app, sc, &drawn, at_px, grid_cell(grid_at, at_px, w.cell), false),
                    _ => pointer_at(&app, &drawn, c, r, false),
                };
                // not while a picture is moved or a list dragged: the holding hand stays for the whole of the drag
                if want != pointer && drag.is_none() && !press.as_ref().is_some_and(|p| p.moved) && !app.map_dragging() {
                    pointer = want;
                    point(&window, &mut out, want);
                }
            }
            // the window wears the band: its words are the window's title, said again when they change, and
            // before the window is shown
            if !app.cfg.band {
                let want = app.window_title();
                if want != window_title {
                    match &window {
                        Some(w) => w.title(&want),
                        None => {
                            let _ = write!(out, "\x1b]2;{}\x1b\\", want);
                        }
                    }
                    window_title = want;
                }
            }
            let _ = out.flush();
            // with no opening to wait for (none chosen, or it never came), the first whole frame shows the window
            if unseen && !matches!(app.motion, Some((Reel::Open, _))) {
                show(&window, &mut drawn_asked);
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
            let mut again = window_again;
            if window.is_none() && want != shown_preview {
                shown_preview = None;
                if let (Some(p), Some((cw, chh)), true) = (&want, cell_size(&window), sixel_ok) {
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
            // the apps' icons (#230): drawn when the set changed, in one synchronized update. A place an icon left is
            // written again as the frame has it, since the buffer's diff may think those cells unchanged; a new icon,
            // or one whose row was lit or let go, has its cells blanked on its row's ground and its sixel drawn there
            let want_icons = if sixel_ok { drawn.icons.clone() } else { vec![] };
            if want_icons != shown_icons {
                if let Some((cw, chh)) = cell_size(&window) {
                    let cells = spark_dialog::page::ICON_CELLS;
                    let _ = out.write_all(b"\x1b[?2026h");
                    for old in shown_icons.iter().filter(|o| !want_icons.iter().any(|n| n.x == o.x && n.y == o.y)) {
                        repaint(&mut out, &frame_buf, old.x, old.y, cells);
                    }
                    for icon in want_icons.iter().filter(|n| !shown_icons.contains(n)) {
                        let ground = if icon.lit { colors.lit } else { colors.surface };
                        blank(&mut out, (icon.x, icon.y, cells, 1), term_color(if icon.lit { pal.lit } else { pal.surface }));
                        let key = (icon.file.clone(), rgb_of(ground), cells as u32 * cw, chh);
                        let s = icon_sixels.entry(key).or_insert_with_key(|(file, ground, bw, bh)| {
                            icon_image(file, &mut icon_images).and_then(|img| sixel::icon(img, *bw, *bh, *ground))
                        });
                        if let Some(s) = s {
                            let _ = queue!(
                                out,
                                ratatui::crossterm::cursor::SavePosition,
                                ratatui::crossterm::cursor::MoveTo(icon.x, icon.y)
                            );
                            let _ = out.write_all(s.as_bytes());
                            let _ = queue!(out, ratatui::crossterm::cursor::RestorePosition);
                        }
                    }
                    let _ = out.write_all(b"\x1b[?2026l");
                    let _ = out.flush();
                    shown_icons = want_icons;
                }
            }
            // a transition: its frame now, at the top left of its box, where the rows land and give way to it (#132), at
            // the GIF's own pace (#122)
            if window.is_none() {
                film_due = None;
            }
            match (drawn.film, &films, cell_size(&window)) {
                (Some((x, y, w, h, reel, since)), Some(f), Some((cw, chh))) if sixel_ok => {
                    let ms = Instant::now().saturating_duration_since(since).as_millis();
                    let film = f.of(reel);
                    let (k, left) = film.at(ms, false);
                    let shown = k;
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
                        let _ = out.write_all(film.sixel(k).unwrap_or_default().as_bytes());
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
                _ if window.is_none() => shown_film = None,
                _ => {}
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
            Ev::Drawn => {
                // the window is mapped with its frame on it: shown, unless a step has cleared it since
                drawn_asked = None;
                if !cleared {
                    opacity(1, Duration::ZERO);
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
                // a bar block clicked while home is open: its section (lib/home.py's request)
                if let Some(name) = spark_dialog::goto::take() {
                    dirty |= app.go_to(&name);
                }
                // Some launchers do not deliver SIGWINCH to the UI process.
                // Size is cheap to query; a resize must redraw without a keypress.
                if term.is_some() && terminal::size().is_ok_and(|size| size != app.size) {
                    mouse_at = None;
                    app.stop_video();
                    shown_preview = None;
                    invalidate_frame(&mut term);
                    shown_icons.clear();
                    dirty = true;
                }
                let (was, said, card) = (app.busy(), app.reply.is_some(), app.trial_card().map(|(_, left)| left));
                app.tick(Instant::now());
                // the card of a change on trial: a frame a second, and one when it ends
                dirty |= card != app.trial_card().map(|(_, left)| left);
                // a receipt left the message's row: a frame without it
                dirty |= said != app.reply.is_some();
                // a frame for the march while it shows, and when the work starts or ends; none for work nothing shows (#196).
                // The view's wait shows it on the message's row from the moment the wait is felt
                let march = app.cfg.progress && (app.thinking() || app.view == View::Apps && app.apps.pending.is_some() || app.files.batch.is_some());
                dirty |= frame_for_tick(was, app.busy(), march || app.view_wait().is_some());
                // a window still unseen after a moment is shown whatever is drawn: never a dialog that cannot be seen
                if unseen && started.elapsed() >= Duration::from_millis(1500) {
                    reveal();
                    unseen = false;
                }
                // and one that never said its frame was drawn is shown as well
                if drawn_asked.is_some_and(|t| t.elapsed() >= Duration::from_millis(1500)) {
                    drawn_asked = None;
                    if !cleared {
                        opacity(1, Duration::ZERO);
                    }
                }
                // an opening whose animation never came: the rows show (#138)
                if films.is_none() && matches!(app.motion, Some((Reel::Open, _))) && started.elapsed() >= Duration::from_millis(1500) {
                    app.motion = None;
                    dirty = true;
                }
                // a picture not drawn yet (its small picture is still being made): tried again now and then
                dirty |= drawn.preview.is_some() && shown_preview.is_none() && preview_tried.elapsed() >= Duration::from_millis(400);
                // what a file shows in its details, the same: a sound's picture is drawn aside and comes a moment later
                dirty |= shown.as_ref().is_some_and(|sc| !sc.pictures.is_empty()) && win_peek.is_none() && peek_tried.elapsed() >= Duration::from_millis(400);
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
                    Some(Some(dir)) => {
                        // a drawn piece in the step's own palette, not yet worn: it comes in the same result
                        let mut pal = piece_pal.clone();
                        if let Some(m) = &app.palette {
                            pal.extend(m.iter().filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string()))));
                        }
                        spawn_films(dir, pal, films_as, films_tx.clone())
                    }
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
            Ev::At(x, y) => at_px = (x, y),
            Ev::Font(cell, small, ascent, big) => {
                if let Some(w) = &mut window {
                    (w.cell, w.small, w.ascent, w.big) = (cell, small, ascent, big);
                }
                app.faces.clear(); // the specimens are measured again too
            }
            Ev::Px(w, h) => {
                // the layout in pixels places by them: a frame at the new size, the pictures made again for it
                window_px = (w as f64, h as f64);
                mouse_at = None;
                app.stop_video();
                shown_preview = None;
                dirty = true;
            }
            Ev::Term(Event::Resize(cols, rows)) => {
                // the window says its size in cells; a terminal's is read as the frame is drawn
                if window.is_some() {
                    window_size = (cols, rows);
                    // the window's screen has another scale: the films again, at the size a cell has there
                    if film_kind(&window) != films_as {
                        films_as = film_kind(&window);
                        if let Some(dir) = app.cfg.transitions.clone() {
                            spawn_films(dir, piece_pal.clone(), films_as, films_tx.clone());
                        }
                    }
                }
                mouse_at = None;
                app.stop_video(); // the frame moves: the player would stand where it was (#125)
                shown_preview = None;
                invalidate_frame(&mut term);
                shown_icons.clear();
                dirty = true;
            }
            Ev::Term(Event::Key(k)) if app.cfg.keys.takes(&k) => {
                // in a window of its own the dialog asks for the clipboard itself, where a terminal pasted for it:
                // Ctrl+V or Ctrl+Shift+V the clipboard, Shift+Insert what the pointer last selected; a key a person
                // bound to an action stays that action's
                if let (Some(w), None) = (&window, app.cfg.keys.action(k)) {
                    let ctrl = k.modifiers.contains(KeyModifiers::CONTROL) && !k.modifiers.intersects(KeyModifiers::ALT | KeyModifiers::SUPER);
                    if ctrl && matches!(k.code, KeyCode::Char('v' | 'V')) {
                        w.paste(false);
                        continue;
                    }
                    if k.code == KeyCode::Insert && k.modifiers == KeyModifiers::SHIFT {
                        w.paste(true);
                        continue;
                    }
                }
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
                        // Space rebound from select keeps what else it does: the player's play, a switch's flip
                        if c == ' ' {
                            app.typed(c);
                        } else {
                            app.text_key(c);
                        }
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
                app.map_cancel();
                app.focus_lost();
                dirty = true;
            }
            Ev::Term(Event::Mouse(m)) => {
                // a drag of nothing draws nothing: the window says the pointer a pixel at a time
                dirty |= frame_for_mouse(m.kind, drag.is_some()) && !(drag.is_none() && matches!(m.kind, MouseEventKind::Drag(_)));
                // the pointer says what a click does where it is (#129)
                // a picture being moved, or a list being dragged: the holding hand
                let dragging = (drag.is_some() && matches!(m.kind, MouseEventKind::Drag(_))) || press.as_ref().is_some_and(|p| p.moved) || app.map_dragging();
                mouse_at = Some((m.column, m.row));
                // in a frame of the layout in pixels the grid's cell is the one of the place's rows under the pointer,
                // and no cell at all outside them
                let (col, row) = match (&shown, &window) {
                    (Some(_), Some(w)) => grid_cell(grid_at, at_px, w.cell).unwrap_or((u16::MAX, u16::MAX)),
                    _ => (m.column, m.row),
                };
                let want = match &shown {
                    Some(sc) => pointer_in(&app, sc, &drawn, at_px, (col != u16::MAX).then_some((col, row)), dragging),
                    None => pointer_at(&app, &drawn, col, row, dragging),
                };
                if want != pointer {
                    pointer = want;
                    point(&window, &mut out, want);
                }
                match m.kind {
                    MouseEventKind::Down(MouseButton::Left) => {
                        app.cut_motion();
                        // the layout's own places: the line, the keys, a row, a name on the location line
                        let target = shown.as_ref().and_then(|sc| sc.hit(at_px.0, at_px.1)).cloned();
                        // a click raises the dialog over a video's player: it stops, unless the click is the key that pauses it (#125)
                        if !matches!(target, Some(scene::Target::Key(_))) && !drawn.keys.iter().any(|(a, b, y, _)| row == *y && col >= *a && col < *b) {
                            app.stop_video();
                        }
                        // a press on a screen of the map is the map's, not the list's: let go where it began it chooses the
                        // screen, dragged it moves it
                        if let (Some(scene::Target::Screen(n, name)), Some(fit)) = (&target, shown.as_ref().and_then(|sc| sc.map)) {
                            press = None;
                            app.map_press(*n, name, at_px, fit.scale);
                            continue;
                        }
                        // a press on a list waits: let go where it began it is the click, dragged it scrolls the list,
                        // with the pointer or with a finger
                        let on = shown.as_ref().and_then(|sc| sc.lists.iter().find(|l| l.holds(at_px.0, at_px.1)));
                        if let Some(l) = on {
                            press = Some(Press {
                                key: l.at.key.clone(),
                                y0: at_px.1,
                                off0: l.at.off,
                                most: l.most,
                                target,
                                moved: false,
                            });
                        } else if let Some(target) = target {
                            press = None;
                            act(&mut app, target);
                        } else if row == 0 && drawn.close.is_some_and(|(a, b)| col >= a && col < b) {
                            if matches!(app.motion, Some((Reel::Close, _))) {
                                app.quit = Some(0);
                            } else {
                                app.close_window();
                            }
                        } else if row == 0 && drawn.minimize.is_some_and(|(a, b)| col >= a && col < b) {
                            app.minimize(); // the header's minimize: the dialog to the pad, as it is (v0.134.3)
                        } else if row == 0
                            && app.can_go_back()
                            && (drawn.back.is_some_and(|(a, b)| col >= a && col < b) || drawn.title.is_some_and(|(a, b)| col >= a && col < b))
                        {
                            app.back_key(); // the header's back, or its place name: back a level (the dialog design notes)
                        } else if let Some((_, _, _, label)) = drawn.heads.iter().find(|(a, b, y, _)| row == *y && col >= *a && col < *b) {
                            app.apps_heading(&label.clone()); // a category's heading: the list narrowed to it, or widened
                        } else if let Some((_, _, _, keep)) = drawn.trial.iter().find(|(a, b, y, _)| row == *y && col >= *a && col < *b) {
                            app.trial_end(*keep);
                        } else if drawn.reply_undo.is_some_and(|(a, b, y)| row == y && col >= a && col < b) {
                            app.undo_now();
                        } else if let Some((_, _, _, c)) = drawn.chips.iter().find(|(a, b, y, _)| row == *y && col >= *a && col < *b) {
                            app.chip(*c);
                        } else if let Some((_, _, _, key)) = drawn.keys.iter().find(|(a, b, y, _)| row == *y && col >= *a && col < *b) {
                            app.hint_key(*key);
                        } else if let Some((x, _, w, _)) = drawn.wave.filter(|(x, y, w, h)| row >= *y && row < y + h && col >= *x && col < x + w) {
                            app.preview_seek((col - x) as f64 / w as f64);
                        } else if drawn
                            .preview
                            .as_ref()
                            .is_some_and(|p| app.zoomed() && row >= p.y && row < p.y + p.h && col >= p.x && col < p.x + p.w)
                        {
                            // kept as the motion says it: the event's own cells, never the place's rows'
                            drag = Some((m.column, m.row));
                            drag_px = at_px;
                        } else if let Some((_, _, _, n, up)) = drawn.steps.iter().find(|(a, b, y, _, _)| row == *y && col >= *a && col < *b) {
                            app.step_at(*n, *up); // a value's arrow steps it, as left and right do (#175)
                        } else if row >= drawn.prompt.0 && row <= drawn.prompt.1 {
                            app.focus_prompt();
                        } else if let Some(n) = drawn.pick_at(col, row) {
                            // a menu's row acts on one click; an object's row is selected first and acts on a second
                            // click, as a file does on every desktop (the dialog design notes)
                            app.clicked(n, Instant::now());
                        } else if let Some(n) = drawn.other_pick_at(col, row) {
                            // a row of the other pane: that pane becomes active and the row is selected (the dialog design notes)
                            app.pane_clicked(n, Instant::now());
                        } else if drawn.other_path.is_some_and(|(a, b, y)| row == y && col >= a && col < b) {
                            app.files_pane(); // its path: the pane becomes active
                        }
                    }
                    MouseEventKind::Drag(MouseButton::Left) if app.map_held() => {
                        if app.map_drag(at_px) {
                            dirty = true;
                        }
                        if app.map_dragging() && pointer != "grabbing" {
                            pointer = "grabbing";
                            point(&window, &mut out, pointer);
                        }
                    }
                    MouseEventKind::Drag(MouseButton::Left) => {
                        if let Some(p) = press.as_mut() {
                            // past a few pixels it is a drag: the list follows the pointer, as far as it scrolls
                            let dy = at_px.1 - p.y0;
                            if p.moved || dy.abs() > DRAG_SLOP {
                                p.moved = true;
                                // the holding hand from the drag's first pixel
                                if pointer != "grabbing" {
                                    pointer = "grabbing";
                                    point(&window, &mut out, pointer);
                                }
                                let off = (p.off0 - dy).clamp(0.0, p.most);
                                if let Some(sc) = scrolls.iter_mut().find(|sc| sc.key == p.key).filter(|sc| sc.off != off) {
                                    sc.off = off;
                                    dirty = true;
                                }
                            }
                        } else if let (Some((c0, r0)), Some(cell)) = (drag, cell_size(&window)) {
                            let own = window.as_ref().map(|w| (at_px, drag_px, w.scale() as f64));
                            let (dx, dy) = drag_by(own, (m.column as f64 - c0 as f64, m.row as f64 - r0 as f64), cell);
                            app.preview_drag(dx, dy);
                            drag = Some((m.column, m.row));
                            drag_px = at_px;
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
                    MouseEventKind::Up(MouseButton::Left) if app.map_held() => {
                        app.map_release(Instant::now());
                        dirty = true;
                    }
                    // the button was let go elsewhere
                    MouseEventKind::Moved if app.map_cancel() => dirty = true,
                    MouseEventKind::Up(button) => {
                        // a press on a list let go: where it began, it is the click
                        if let Some(p) = press.take().filter(|_| button == MouseButton::Left) {
                            if let Some(target) = p.target.filter(|_| !p.moved) {
                                act(&mut app, target);
                            }
                            dirty = true;
                        }
                        // the pointer let go: the picture drawn whole again, in all its colors (#148)
                        if drag.take().is_some() {
                            shown_preview = None;
                            drag_cost = Duration::ZERO;
                        }
                        drag_owed = false;
                    }
                    MouseEventKind::ScrollUp if app.view == View::Preview => app.preview_wheel(-1, m.modifiers.contains(KeyModifiers::CONTROL)),
                    MouseEventKind::ScrollDown if app.view == View::Preview => app.preview_wheel(1, m.modifiers.contains(KeyModifiers::CONTROL)),
                    // the wheel moves the bar a row in a list, as the arrows do; three lines in text (the dialog design
                    // notes). In the layout in pixels too: the list follows its lit row, and a drag scrolls it freely
                    MouseEventKind::ScrollUp => app.wheel(-1),
                    MouseEventKind::ScrollDown => app.wheel(1),
                    _ => {}
                }
            }
            _ => {}
        }
    }
    let code = app.quit.unwrap_or(0);
    // a recording does not outlive the window
    run_job(Job::StopListening, tx.clone(), listening.clone());
    if let Some(term) = term.as_mut() {
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
    }
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
    fn a_photos_full_picture_is_read_though_its_file_is_large() {
        // a zoom past the page's pixels asks for the picture at 4096 pixels a side: of a photo, a PNG of 25 MB and
        // more. Noise stands in for a photo: 2048 by 2048 of it will not compress under 8 MB, the old cap
        let (w, h) = (2048u32, 2048u32);
        let mut seed = 0x2545_f491u32;
        let raw: Vec<u8> = (0..w * h * 3)
            .map(|_| {
                seed ^= seed << 13;
                seed ^= seed >> 17;
                seed ^= seed << 5;
                seed as u8
            })
            .collect();
        let mut bytes = Vec::new();
        {
            let mut e = png::Encoder::new(&mut bytes, w, h);
            e.set_color(png::ColorType::Rgb);
            e.set_depth(png::BitDepth::Eight);
            e.write_header().unwrap().write_image_data(&raw).unwrap();
        }
        assert!(bytes.len() > 8 << 20, "the test's picture is over the old cap: {} bytes", bytes.len());
        assert!((bytes.len() as u64) < PICTURE_MOST);
        let file = std::env::temp_dir().join(format!("spark-dialog-photo-{}.png", std::process::id()));
        std::fs::write(&file, &bytes).unwrap();
        let mut cache = None;
        let read = image(file.to_str().unwrap(), &mut cache).map(|i| (i.w, i.h));
        let _ = std::fs::remove_file(&file);
        assert_eq!(read, Some((w, h)), "the view draws it");
    }

    #[test]
    fn a_drag_moves_a_picture_by_the_pixel_in_the_dialogs_window_and_by_the_cell_in_a_terminal() {
        // a window of the dialog's own: the pointer's pixels, at the screen's scale; the cells of the event say nothing
        assert_eq!(drag_by(Some(((310.0, 452.0), (300.0, 450.0), 1.0)), (9.0, 9.0), (10, 20)), (10.0, 2.0));
        assert_eq!(drag_by(Some(((310.0, 452.0), (300.0, 450.0), 2.0)), (0.0, 0.0), (20, 40)), (20.0, 4.0));
        assert_eq!(
            drag_by(Some(((300.0, 450.0), (300.0, 450.0), 1.0)), (0.0, 2.0), (10, 20)),
            (0.0, 0.0),
            "the press moves nothing"
        );
        // a terminal: the cells moved, at a cell's size
        assert_eq!(drag_by(None, (-2.0, 1.0), (9, 18)), (-18.0, 18.0));
    }

    #[test]
    fn a_videos_box_is_in_the_windows_own_pixels_at_any_scale() {
        assert_eq!(logical(1, (24, 101, 640, 360)), (24, 101, 640, 360));
        assert_eq!(
            logical(2, (48, 202, 1281, 720)),
            (24, 101, 640, 360),
            "a screen of 1.5 or 2: drawn at 2, placed by one"
        );
    }

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
    fn the_pointer_over_a_places_grid_rows_is_on_their_own_cell() {
        // the rows laid at (4, 101), kept between the frame's edges, the first of them the grid's row 3
        let g = scene::GridBody {
            x: 4.0,
            y: 101.0,
            cols: 59,
            rows: 31,
            clip: (24.0, 97.0, 552.0, 627.0),
        };
        let cell = spark_dialog::draw::Cell { w: 10.0, h: 20.0 };
        let at = |x: f64, y: f64| grid_cell(Some((g, 3)), (x, y), cell);
        assert_eq!(at(24.0, 101.0), Some((2, 3)), "the first text column of the first row");
        assert_eq!(at(33.9, 120.9), Some((2, 3)), "to that cell's last pixel");
        assert_eq!(at(34.0, 121.0), Some((3, 4)));
        assert_eq!(at(23.0, 110.0), None, "left of the frame's edge");
        assert_eq!(at(100.0, 99.0), None, "the air over the first row is no row");
        assert_eq!(at(576.0, 110.0), None, "the frame's right edge is outside");
        assert_eq!(at(100.0, 724.0), None, "under the body");
        assert_eq!(grid_cell(None, (100.0, 200.0), cell), None, "a body in pixels has no cells");
    }

    #[test]
    fn a_drag_shows_the_holding_hand_whatever_is_under_the_pointer() {
        let app = App::new(Config::default(), &[]);
        let (sc, drawn) = (scene::Scene::default(), ui::Drawn::default());
        assert_eq!(pointer_in(&app, &sc, &drawn, (10.0, 10.0), None, true), "grabbing");
        assert_eq!(pointer_in(&app, &sc, &drawn, (10.0, 10.0), None, false), "default");
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
