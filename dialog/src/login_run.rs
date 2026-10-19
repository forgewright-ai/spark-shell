//! `spark-dialog login`: the login screen greetd shows on tty1, in a
//! foot window that fills the screen. The terminal, the event loop and
//! the machine's facts (its name, its distro, the clock, spark's port);
//! the state is login.rs, the drawing login_ui.rs, greetd greetd.rs.

use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use ratatui::crossterm::execute;
use ratatui::crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::Terminal;
use spark_dialog::greetd::{self, Outcome};
use spark_dialog::login::{self, Action, Key, Login, Power, Session};
use spark_dialog::login_ui;
use spark_dialog::palette::Palette;
use std::net::{Ipv4Addr, SocketAddr, TcpStream};
use std::sync::mpsc;
use std::time::Duration;

pub const USAGE: &str = "spark-dialog login -- the login screen greetd shows on tty1 (set up by spark-shell on login)

  spark-dialog login [--restart \"PATH WORDS\"] [--shutdown \"PATH WORDS\"]
                     [--spark-port N] [--desktop on|off]
";

struct Args {
    restart: Option<Vec<String>>,
    shutdown: Option<Vec<String>>,
    port: Option<u16>,
    desktop: bool,
}

fn args() -> Result<Args, String> {
    let mut a = Args {
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
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let f = |fmt: &[u8]| {
            let mut b = [0u8; 64];
            let n = libc::strftime(b.as_mut_ptr() as *mut libc::c_char, b.len(), fmt.as_ptr() as *const libc::c_char, &tm);
            String::from_utf8_lossy(&b[..n]).into_owned()
        };
        // the day's number with no leading zero: %-d is not every libc's
        format!("{} {} \u{b7} {}", f(b"%A, %B\0"), tm.tm_mday, f(b"%H:%M\0"))
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
        while !p.is_null() {
            let a = (*p).ifa_addr;
            if !a.is_null() && (*a).sa_family as i32 == libc::AF_INET {
                let sin = a as *const libc::sockaddr_in;
                let ip = Ipv4Addr::from(u32::from_be((*sin).sin_addr.s_addr));
                if !out.contains(&ip) {
                    out.push(ip);
                }
            }
            p = (*p).ifa_next;
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

    let _ = terminal::enable_raw_mode();
    let _ = execute!(std::io::stdout(), EnterAlternateScreen);
    let mut term = match Terminal::new(CrosstermBackend::new(std::io::stdout())) {
        Ok(t) => t,
        Err(e) => {
            let _ = terminal::disable_raw_mode();
            println!("spark-dialog login -- {}", e);
            std::process::exit(1);
        }
    };
    let _ = term.hide_cursor();
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
            let _ = term.draw(|f| login_ui::draw(&l, &pal, &last_clock, f.buffer_mut()));
            dirty = false;
        }
        let Ok(ev) = rx.recv() else { break };
        match ev {
            Ev::Tick => {}
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
                let _ = term.clear();
                dirty = true;
            }
            Ev::Term(Event::Key(k)) if k.kind == KeyEventKind::Press => {
                dirty = true;
                let Some(key) = key_of(k.code, k.modifiers) else { continue };
                match l.key(key) {
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
    let _ = execute!(term.backend_mut(), LeaveAlternateScreen);
    let _ = terminal::disable_raw_mode();
    let _ = term.show_cursor();
    std::process::exit(code.unwrap_or(0));
}
