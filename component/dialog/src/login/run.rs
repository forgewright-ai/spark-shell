//! `spark-dialog login`: the login screen greetd shows on tty1, in a
//! window of its own that fills the screen, or in the terminal it runs
//! in. The face it is drawn on, the event loop and the machine's facts
//! (its name, its distro, the clock, spark's port); the state is
//! login/mod.rs, the drawing login/ui.rs, greetd greetd.rs.

use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind,
};
use ratatui::crossterm::execute;
use ratatui::crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::Terminal;
use spark_dialog::greetd::{self, Outcome};
use spark_dialog::login::ui as login_ui;
use spark_dialog::login::{self, Action, Key, Login, Power, Session};
use spark_dialog::palette::Palette;
use std::net::{Ipv4Addr, SocketAddr, TcpStream};
use std::sync::mpsc;
use std::time::Duration;

pub const USAGE: &str = "spark-dialog login -- the login screen greetd shows on tty1 (set up by spark-shell on login)

  spark-dialog login [--window] [--font \"FACE SIZE\"]
                     [--restart \"PATH WORDS\"] [--shutdown \"PATH WORDS\"]
                     [--spark-port N] [--desktop on|off]

--window draws it in a window of its own, else the terminal it runs in. It ends
with 0 after a login, 3 when no window opens, 4 when the window went before one.
";

/// What the program ends with when no window opens, and when the window went before a login: whoever started it
/// shows the login screen in a terminal then.
const NO_WINDOW: i32 = 3;
const WINDOW_GONE: i32 = 4;

struct Args {
    window: bool,
    font: String,
    restart: Option<Vec<String>>,
    shutdown: Option<Vec<String>>,
    port: Option<u16>,
    desktop: bool,
}

fn args() -> Result<Args, String> {
    let mut a = Args {
        window: false,
        font: "monospace 12".into(),
        restart: None,
        shutdown: None,
        port: None,
        desktop: true,
    };
    let mut it = std::env::args().skip(2);
    while let Some(w) = it.next() {
        let mut val = |name: &str| it.next().ok_or_else(|| format!("{} takes a value", name));
        match w.as_str() {
            "-h" | "--help" | "help" => return Err(String::new()),
            "--window" => a.window = true,
            "--font" => {
                a.font = val("--font")?;
                if a.font.trim().is_empty() || a.font.chars().any(char::is_control) {
                    return Err("the font is a face and a size, as \"Monaspace Neon 12\"".into());
                }
            }
            "--restart" => a.restart = Some(login::power_argv(&val("--restart")?)?),
            "--shutdown" => a.shutdown = Some(login::power_argv(&val("--shutdown")?)?),
            "--spark-port" => {
                let v = val("--spark-port")?;
                a.port = Some(v.parse::<u16>().ok().filter(|p| *p > 0).ok_or_else(|| format!("{}: a port is 1 to 65535", v))?);
            }
            "--desktop" => {
                a.desktop = match val("--desktop")?.as_str() {
                    "on" => true,
                    "off" => false,
                    v => return Err(format!("{} is on or off", v)),
                }
            }
            other => return Err(format!("no option {}", other)),
        }
    }
    Ok(a)
}

enum Ev {
    Term(Event),
    /// The window's size in pixels.
    Px(u32, u32),
    #[cfg(target_os = "linux")]
    Font(spark_dialog::draw::Cell),
    /// The window is gone: the compositor ended, or closed it.
    Gone,
    Tick,
    Spark(bool),
    Done(Outcome),
    PowerFailed(Power, String),
}

fn host() -> String {
    let mut b = [0u8; 256];
    let ok = unsafe { libc::gethostname(b.as_mut_ptr() as *mut libc::c_char, b.len()) } == 0;
    let n = b.iter().position(|x| *x == 0).unwrap_or(b.len());
    login::short_host(if ok { std::str::from_utf8(&b[..n]).unwrap_or("") } else { "" })
}

fn kernel() -> String {
    unsafe {
        let mut u: libc::utsname = std::mem::zeroed();
        if libc::uname(&mut u) != 0 {
            return String::new();
        }
        std::ffi::CStr::from_ptr(u.release.as_ptr()).to_string_lossy().into_owned()
    }
}

fn distro() -> String {
    let os = std::fs::read_to_string("/etc/os-release")
        .or_else(|_| std::fs::read_to_string("/usr/lib/os-release"))
        .unwrap_or_default();
    login::distro(&os, &kernel())
}

/// "Sunday, October 18 \u{b7} 14:32", by the machine's own clock and zone.
fn clock() -> String {
    unsafe {
        spark_dialog::preferences::refresh_zone();
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let f = |fmt: &[u8]| {
            let mut b = [0u8; 64];
            let n = libc::strftime(b.as_mut_ptr() as *mut libc::c_char, b.len(), fmt.as_ptr() as *const libc::c_char, &tm);
            String::from_utf8_lossy(&b[..n]).into_owned()
        };
        // the day's number with no leading zero: %-d is not every libc's
        format!(
            "{} {} \u{b7} {}",
            f(b"%A, %B\0"),
            tm.tm_mday,
            f(if spark_dialog::preferences::read().twelve {
                b"%I:%M %p\0"
            } else {
                b"%H:%M\0"
            })
        )
    }
}

/// The user's shell from the password database, else /bin/sh.
fn shell_of(user: &str) -> String {
    let Ok(name) = std::ffi::CString::new(user) else { return "/bin/sh".into() };
    unsafe {
        let pw = libc::getpwnam(name.as_ptr());
        if pw.is_null() || (*pw).pw_shell.is_null() {
            return "/bin/sh".into();
        }
        let s = std::ffi::CStr::from_ptr((*pw).pw_shell).to_string_lossy().into_owned();
        if s.starts_with('/') && !s.chars().any(|c| c.is_control()) {
            s
        } else {
            "/bin/sh".into()
        }
    }
}

/// This machine's IPv4 addresses, the loopback first.
fn addresses() -> Vec<Ipv4Addr> {
    let mut out = vec![Ipv4Addr::LOCALHOST];
    unsafe {
        let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
        if libc::getifaddrs(&mut head) != 0 {
            return out;
        }
        let mut p = head;
        while let Some(node) = p.as_ref() {
            if let Some(address) = node.ifa_addr.as_ref().filter(|a| a.sa_family as i32 == libc::AF_INET) {
                let sin = (address as *const libc::sockaddr).cast::<libc::sockaddr_in>();
                if let Some(sin) = sin.as_ref() {
                    let ip = Ipv4Addr::from(u32::from_be(sin.sin_addr.s_addr));
                    if !out.contains(&ip) {
                        out.push(ip);
                    }
                }
            }
            p = node.ifa_next;
        }
        libc::freeifaddrs(head);
    }
    out
}

/// Is anything listening on spark's port on this machine?
fn spark_ready(port: u16) -> bool {
    addresses()
        .into_iter()
        .any(|ip| TcpStream::connect_timeout(&SocketAddr::from((ip, port)), Duration::from_millis(300)).is_ok())
}

fn key_of(code: KeyCode, m: KeyModifiers) -> Option<Key> {
    if m.contains(KeyModifiers::CONTROL) {
        // Ctrl+C and the rest do nothing here: the login screen never exits on a key
        return (code == KeyCode::Char('u')).then_some(Key::Kill);
    }
    if m.contains(KeyModifiers::ALT) {
        return None;
    }
    Some(match code {
        KeyCode::Tab => Key::Tab,
        KeyCode::BackTab => Key::BackTab,
        KeyCode::Up => Key::Up,
        KeyCode::Down => Key::Down,
        KeyCode::Left => Key::Left,
        KeyCode::Right => Key::Right,
        KeyCode::Enter => Key::Enter,
        KeyCode::Esc => Key::Esc,
        KeyCode::Backspace => Key::Backspace,
        KeyCode::F(n) => Key::F(n),
        KeyCode::Char(c) => Key::Char(c),
        _ => return None,
    })
}

/// A key that types or acts now: pressed, or held and counted again, but a held Enter logs in once.
fn pressed(k: &KeyEvent) -> bool {
    match k.kind {
        KeyEventKind::Press => true,
        KeyEventKind::Repeat => k.code != KeyCode::Enter,
        KeyEventKind::Release => false,
    }
}

/// What the login screen is drawn on.
enum Face {
    /// A window of its own: clear but for the strip, as tall as its screen.
    #[cfg(target_os = "linux")]
    Own(own::Window),
    Term(Terminal<CrosstermBackend<std::io::Stdout>>),
}

impl Face {
    /// The face asked for; else the code to end with and why.
    fn open(a: &Args, tx: &mpsc::Sender<Ev>) -> Result<Face, (i32, String)> {
        #[cfg(target_os = "linux")]
        if a.window {
            return own::Window::open(&a.font, tx.clone()).map(Face::Own).map_err(|e| (NO_WINDOW, e));
        }
        #[cfg(not(target_os = "linux"))]
        if a.window {
            return Err((NO_WINDOW, "a window of its own opens only on Linux, under a Wayland compositor".into()));
        }
        let tx = tx.clone();
        std::thread::spawn(move || {
            while let Ok(e) = event::read() {
                if tx.send(Ev::Term(e)).is_err() {
                    return;
                }
            }
        });
        let _ = terminal::enable_raw_mode();
        let _ = execute!(std::io::stdout(), EnterAlternateScreen, EnableMouseCapture);
        let mut t = Terminal::new(CrosstermBackend::new(std::io::stdout())).map_err(|e| {
            let _ = terminal::disable_raw_mode();
            (1, e.to_string())
        })?;
        let _ = t.hide_cursor();
        Ok(Face::Term(t))
    }

    fn draw(&mut self, l: &Login, pal: &Palette, clock: &str) {
        match self {
            #[cfg(target_os = "linux")]
            Face::Own(w) => w.draw(l, pal, clock),
            Face::Term(t) => {
                let _ = t.draw(|f| {
                    // the login screen draws the dialog's own grid; the terminal is handed its cells
                    let area = f.area();
                    let mut b = spark_dialog::grid::Buffer::empty(spark_dialog::grid::Rect::new(0, 0, area.width, area.height));
                    login_ui::draw(l, pal, clock, &mut b);
                    spark_dialog::terminal::blit(&b, f.buffer_mut());
                });
            }
        }
    }

    /// The window's size in pixels, as the compositor says it.
    fn sized(&mut self, w: u32, h: u32) {
        match self {
            #[cfg(target_os = "linux")]
            Face::Own(own) => own.sized(w, h),
            Face::Term(_) => {
                let _ = (w, h);
            }
        }
    }

    /// A terminal's cells changed: what it showed is wiped.
    fn resized(&mut self) {
        if let Face::Term(t) = self {
            let _ = t.clear();
        }
    }

    /// A second went by: a window the compositor gave no other size is drawn at the one it has. True when that is news.
    fn settle(&mut self) -> bool {
        match self {
            #[cfg(target_os = "linux")]
            Face::Own(w) => w.settle(),
            Face::Term(_) => false,
        }
    }

    /// The face's size in cells, for a click.
    fn cells(&self) -> (u16, u16) {
        match self {
            #[cfg(target_os = "linux")]
            Face::Own(w) => w.cells(),
            Face::Term(t) => t.size().map(|s| (s.width, s.height)).unwrap_or_default(),
        }
    }

    fn close(&mut self) {
        if let Face::Term(t) = self {
            let _ = execute!(t.backend_mut(), DisableMouseCapture, LeaveAlternateScreen);
            let _ = terminal::disable_raw_mode();
            let _ = t.show_cursor();
        }
    }
}

#[cfg(target_os = "linux")]
mod own {
    use super::{login_ui, Ev, Login, Palette};
    use spark_dialog::window::{self, Handle, Out, Setup};
    use std::sync::mpsc;

    /// The login screen's own window. It maps clear, at the size it asked for, and the compositor then gives it its
    /// screen's: the strip is drawn for that size alone, so nothing of it ever moves.
    pub struct Window {
        pub(super) handle: Handle,
        px: (u32, u32),
        settled: bool,
    }

    impl Window {
        pub fn open(font: &str, tx: mpsc::Sender<Ev>) -> Result<Window, String> {
            let setup = Setup {
                font: font.to_string(),
                app_id: "spark-login".into(),
                title: "login".into(),
                cols: login_ui::STRIP,
                rows: 30,
            };
            let handle = window::open(setup, move |o| {
                let _ = tx.send(match o {
                    Out::Event(e) => Ev::Term(e),
                    Out::Pixels(w, h) => Ev::Px(w, h),
                    Out::Font(cell, ..) => Ev::Font(cell),
                    Out::Gone => Ev::Gone,
                    Out::At(..) | Out::Drawn => return,
                });
            })?;
            handle.frame_clear(vec![]);
            let px = handle.px;
            Ok(Window { handle, px, settled: false })
        }

        pub fn sized(&mut self, w: u32, h: u32) {
            self.settled |= (w, h) != self.handle.px;
            self.px = (w, h);
        }

        pub fn settle(&mut self) -> bool {
            !std::mem::replace(&mut self.settled, true)
        }

        pub fn cells(&self) -> (u16, u16) {
            let cell = self.handle.cell;
            (((self.px.0 as f64 / cell.w) as u16).max(1), login_ui::rows_in(self.px.1 as f64, cell))
        }

        pub fn draw(&self, l: &Login, pal: &Palette, clock: &str) {
            if self.settled {
                self.handle.frame_clear(login_ui::steps(l, pal, clock, self.handle.cell, self.px.1 as f64));
            }
        }
    }
}

pub fn main() {
    let a = match args() {
        Ok(a) => a,
        Err(e) => {
            if e.is_empty() {
                print!("{}", USAGE);
                std::process::exit(0);
            }
            println!("spark-dialog login -- {}; spark-dialog login -h lists the options", e);
            std::process::exit(2);
        }
    };
    let pal = Palette::from_env();
    let mut l = Login::new(&host(), &distro());
    l.desktop = a.desktop;
    l.can_restart = a.restart.is_some();
    l.can_shutdown = a.shutdown.is_some();
    let sock = std::env::var("GREETD_SOCK").ok().filter(|s| !s.is_empty());
    if sock.is_none() {
        l.note = Some(login::Note::Wrong("greetd is not running".into()));
    }
    let (tx, rx) = mpsc::channel::<Ev>();
    if let Some(port) = a.port {
        l.spark = Some(false);
        let tx = tx.clone();
        std::thread::spawn(move || loop {
            if tx.send(Ev::Spark(spark_ready(port))).is_err() {
                return;
            }
            std::thread::sleep(Duration::from_secs(5));
        });
    }
    {
        let tx = tx.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(1));
            if tx.send(Ev::Tick).is_err() {
                return;
            }
        });
    }
    let mut face = match Face::open(&a, &tx) {
        Ok(f) => f,
        Err((code, why)) => {
            eprintln!("spark-dialog login -- {}", why);
            std::process::exit(code);
        }
    };
    let mut code = None;
    let mut dirty = true;
    let mut last_clock = String::new();
    while code.is_none() {
        let now = clock();
        if now != last_clock {
            last_clock = now;
            dirty = true;
        }
        if dirty {
            face.draw(&l, &pal, &last_clock);
            dirty = false;
        }
        let Ok(ev) = rx.recv() else { break };
        match ev {
            Ev::Tick => dirty |= face.settle(),
            Ev::Px(w, h) => {
                face.sized(w, h);
                dirty = true;
            }
            #[cfg(target_os = "linux")]
            Ev::Font(cell) => {
                if let Face::Own(w) = &mut face {
                    w.handle.cell = cell;
                }
            }
            Ev::Gone => code = Some(WINDOW_GONE),
            Ev::Spark(r) => {
                dirty |= l.spark != Some(r);
                l.spark = Some(r);
            }
            Ev::Done(o) => {
                if l.outcome(o) {
                    code = Some(0);
                }
                dirty = true;
            }
            Ev::PowerFailed(p, why) => {
                l.power_failed(p, &why);
                dirty = true;
            }
            Ev::Term(Event::Resize(_, _)) => {
                face.resized();
                dirty = true;
            }
            Ev::Term(e @ (Event::Key(_) | Event::Mouse(_))) => {
                let act = match e {
                    Event::Key(k) if pressed(&k) => {
                        let Some(key) = key_of(k.code, k.modifiers) else { continue };
                        l.key(key)
                    }
                    Event::Mouse(m) if m.kind == MouseEventKind::Down(MouseButton::Left) => {
                        let (w, h) = face.cells();
                        let Some(s) = login_ui::spot(&l, w, h, m.column, m.row) else { continue };
                        l.click(s)
                    }
                    _ => continue,
                };
                dirty = true;
                match act {
                    None => {}
                    Some(Action::LogIn) => {
                        let pass = l.take_password();
                        let user = l.user.clone();
                        let cmd = vec![shell_of(&user), "-l".to_string()];
                        let env: Vec<String> = match l.session() {
                            Session::Desktop => vec![],
                            Session::Shell => vec!["SPARK_SHELL_SESSION=shell".into()],
                        };
                        let sock = sock.clone();
                        let tx = tx.clone();
                        std::thread::spawn(move || {
                            let o = match sock {
                                None => Outcome::Failed("greetd is not running".into()),
                                Some(path) => match std::os::unix::net::UnixStream::connect(&path) {
                                    Ok(mut s) => greetd::log_in(&mut s, &user, &pass, &cmd, &env),
                                    Err(e) => Outcome::Failed(format!("greetd: {}", e)),
                                },
                            };
                            drop(pass);
                            let _ = tx.send(Ev::Done(o));
                        });
                    }
                    Some(Action::Power(p)) => {
                        let argv = match p {
                            Power::Restart => a.restart.clone(),
                            Power::Shutdown => a.shutdown.clone(),
                        };
                        let tx = tx.clone();
                        std::thread::spawn(move || {
                            let Some((cmd, rest)) = argv.as_ref().and_then(|v| v.split_first()) else {
                                return;
                            };
                            let r = std::process::Command::new(cmd)
                                .args(rest)
                                .stdin(std::process::Stdio::null())
                                .stdout(std::process::Stdio::null())
                                .stderr(std::process::Stdio::null())
                                .status();
                            let why = match r {
                                Ok(s) if s.success() => return,
                                Ok(s) => match s.code() {
                                    Some(c) => format!("exit {}", c),
                                    None => "stopped by a signal".into(),
                                },
                                Err(e) => e.to_string(),
                            };
                            let _ = tx.send(Ev::PowerFailed(p, why));
                        });
                    }
                }
            }
            Ev::Term(Event::Paste(t)) => {
                for c in t.chars().filter(|c| !c.is_control()) {
                    l.key(Key::Char(c));
                }
                dirty = true;
            }
            _ => {}
        }
    }
    face.close();
    std::process::exit(code.unwrap_or(0));
}
