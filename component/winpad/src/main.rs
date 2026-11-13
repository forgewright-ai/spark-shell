//! spark-winpad: spark-shell's windows on a sway desktop, three jobs. The pad: the minimized windows on a
//! surface of their own on each screen, each with its app's icon and its title; a click or a key brings
//! one back. The buttons: close, minimize and fill on every title band, drawn by sway, told and clicked
//! here. The order: the windows as they were focused, for Super+Tab. Started with the desktop by
//! spark-shell, for the session.

use std::process::ExitCode;

const USAGE: &str =
    "spark-winpad -- the windows of a sway desktop: the pad for the minimized ones, the buttons on every title band, the focus order (run by spark-shell)

  spark-winpad [--keys]

  --keys     the keyboard on the pad as soon as it shows, as Super+minus
  --version  the version

The windows are the ones spark-shell put in sway's scratchpad with its mark,
an icon each. A click on one, or Enter, brings it back through spark-shell
desktop window restore. When the pad is too small for them, the windows of
one app fold into one icon, the app with the most first; a click on it, or
Enter, opens its list. SIGUSR1 puts the keyboard on the pad, SIGUSR2 hides
or shows it, SIGTERM or SIGINT ends it. The close, minimize and fill buttons at the
start of every title are sway's own text: the pad tells sway how each
window's are drawn, by its focus and the pointer, and takes their clicks.
It keeps the
order the windows were focused in, and the tick spark-winpad.back (spark-shell
desktop window back, Super+Tab) focuses the window before.

spark-shell sets the look and the place in the environment: WINPAD_FG,
WINPAD_ACCENT, WINPAD_MUTED, WINPAD_SURFACE, WINPAD_LIT, WINPAD_BAND_HEX (rrggbb),
WINPAD_CLOSE, WINPAD_MIN, WINPAD_FILL and WINPAD_GROUND (the buttons' colors and the
ground's), WINPAD_TERM (the terminal's app), WINPAD_TITLE and WINPAD_TERM_TITLE
(the title format after the buttons),
WINPAD_ALPHA, WINPAD_FONT, WINPAD_VIEW (icons, the default, or titles: a slot a
window with its title), WINPAD_BAND (on: the band under the handle; off, the
default), WINPAD_GAP (the pixels off an edge, 8), WINPAD_PLACE, WINPAD_WIDTH,
WINPAD_SIDE_WIDTH, WINPAD_HEIGHT (the most height, 0: as many rows as needed),
and the files WINPAD_LOCK, WINPAD_STATE and WINPAD_BAR_PID; SPARK_SHELL names
spark-shell itself, and the assets beside it give the dialog spark's S,
the dark one or the light one by WINPAD_SURFACE. After a drag or a resize it
runs spark-shell desktop pad place PLACE WIDTH SIDE_WIDTH HEIGHT, and each
time the strip it keeps appears, goes, moves to another edge or changes
its thickness, spark-shell desktop window refit.
";

#[derive(Debug, PartialEq)]
enum Ask {
    Help,
    Version,
    Run { keys: bool },
}

fn parse(args: &[String]) -> Result<Ask, String> {
    let mut keys = false;
    for a in args {
        match a.as_str() {
            "-h" | "--help" => return Ok(Ask::Help),
            "--version" => return Ok(Ask::Version),
            "--keys" => keys = true,
            _ => return Err(format!("unknown argument {a:?}")),
        }
    }
    Ok(Ask::Run { keys })
}

fn main() -> ExitCode {
    let args: Result<Vec<String>, _> = std::env::args_os().skip(1).map(|a| a.into_string()).collect();
    let Ok(args) = args else {
        eprintln!("spark-winpad: an argument is not UTF-8");
        return ExitCode::from(2);
    };
    match parse(&args) {
        Ok(Ask::Help) => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Ok(Ask::Version) => {
            println!("spark-winpad {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Ok(Ask::Run { keys }) => match run(keys) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("spark-winpad: {e}");
                ExitCode::FAILURE
            }
        },
        Err(e) => {
            eprintln!("spark-winpad: {e}\n\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

#[cfg(not(target_os = "linux"))]
fn run(_: bool) -> Result<(), String> {
    Err("runs only on Linux, under sway".into())
}

#[cfg(target_os = "linux")]
fn config() -> spark_winpad::app::Config {
    use spark_winpad::app::{Config, Look, Titles};
    use spark_winpad::pad::{Place, View};
    use spark_winpad::paint::Rgb;
    let env = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());
    let color = |k: &str, d: &str| env(k).and_then(|v| Rgb::hex(&v)).unwrap_or_else(|| Rgb::hex(d).unwrap());
    // a color kept as its six digits, for sway's markup
    let hex = |k: &str, d: &str| {
        env(k)
            .map(|v| v.trim_start_matches('#').to_lowercase())
            .filter(|v| Rgb::hex(v).is_some())
            .unwrap_or_else(|| d.into())
    };
    let num = |k: &str, d: i32| {
        env(k)
            .and_then(|v| v.trim().parse::<i32>().ok())
            .filter(|n| (0..=100_000).contains(n))
            .unwrap_or(d)
    };
    Config {
        look: Look {
            fg: color("WINPAD_FG", "383a42"),
            accent: color("WINPAD_ACCENT", "4078f2"),
            muted: color("WINPAD_MUTED", "696c77"),
            surface: color("WINPAD_SURFACE", "ebebec"),
            lit: color("WINPAD_LIT", "dcdcdd"),
            band: color("WINPAD_BAND_HEX", "c3d0ee"),
            alpha: env("WINPAD_ALPHA")
                .and_then(|v| v.trim().parse::<f64>().ok())
                .filter(|a| a.is_finite())
                .map_or(1.0, |a| a.clamp(0.0, 1.0)),
            font: env("WINPAD_FONT").unwrap_or_else(|| "Monaspace Neon 12".into()),
        },
        titles: Titles {
            colors: [hex("WINPAD_CLOSE", "e45649"), hex("WINPAD_MIN", "c18401"), hex("WINPAD_FILL", "50a14f")],
            ground: hex("WINPAD_GROUND", "fafafa"),
            term: env("WINPAD_TERM").unwrap_or_default(),
            title: env("WINPAD_TITLE").unwrap_or_else(|| "%title".into()),
            term_title: env("WINPAD_TERM_TITLE").unwrap_or_else(|| "%title".into()),
        },
        place: env("WINPAD_PLACE").and_then(|p| Place::parse(&p)).unwrap_or_default(),
        view: View::parse(env("WINPAD_VIEW").as_deref()),
        width: num("WINPAD_WIDTH", 0),
        side_width: num("WINPAD_SIDE_WIDTH", 36),
        height: num("WINPAD_HEIGHT", 0),
        gap: gap(env("WINPAD_GAP").as_deref()),
        band: env("WINPAD_BAND").is_some_and(|v| v.trim().eq_ignore_ascii_case("on")),
        spark_shell: env("SPARK_SHELL").unwrap_or_else(|| "spark-shell".into()),
        state_file: env("WINPAD_STATE").map(Into::into),
        bar_pid: env("WINPAD_BAR_PID").map(Into::into),
    }
}

/// The margin off an edge: WINPAD_GAP's whole pixels, 0 to 200; the desktop's outer gap when it says none.
fn gap(v: Option<&str>) -> i32 {
    v.and_then(|v| v.trim().parse::<i32>().ok())
        .filter(|n| (0..=200).contains(n))
        .unwrap_or(spark_winpad::pad::GAP)
}

/// The one pad: WINPAD_LOCK held for the pad's life, its pid in it. None when another pad holds it.
#[cfg(target_os = "linux")]
fn lock() -> Result<Option<std::fs::File>, String> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    use std::os::unix::io::AsRawFd;
    let path = std::env::var_os("WINPAD_LOCK").map(std::path::PathBuf::from).unwrap_or_else(|| {
        let dir = std::env::var_os("XDG_RUNTIME_DIR").map_or_else(std::env::temp_dir, Into::into);
        dir.join("spark-shell-app.pid")
    });
    let mut f = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(&path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Ok(None);
    }
    let _ = f.set_len(0);
    let _ = writeln!(f, "{}", std::process::id());
    Ok(Some(f))
}

/// The apps adapter's catalog with icons at `px`, read aside: each app's id and class to its icon.
#[cfg(target_os = "linux")]
fn icons(spark_shell: &str, px: i32) -> Vec<(String, String)> {
    use std::io::{Read, Write};
    use std::process::{Command, Stdio};
    let Some(adapter) = std::path::Path::new(spark_shell)
        .parent()
        .map(|d| d.join("lib/apps.py"))
        .filter(|p| p.is_file())
    else {
        return vec![];
    };
    let Ok(mut child) = Command::new("python3")
        .arg(&adapter)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return vec![];
    };
    if let Some(mut i) = child.stdin.take() {
        let _ = i.write_all(format!("{{\"op\":\"catalog\",\"icon_px\":{}}}", px.clamp(8, 256)).as_bytes());
    }
    let mut out = String::new();
    if let Some(mut o) = child.stdout.take() {
        let _ = o.read_to_string(&mut out);
    }
    let _ = child.wait();
    serde_json::from_str(&out).map(|v| spark_winpad::pad::icon_paths(&v)).unwrap_or_default()
}

/// Spark's mark for the dialog's icon at `px`, from the assets next to spark-shell, the dark ground's or the light
/// one's: the PNG nearest the size at or above it; past the largest, the SVG drawn at the size by rsvg-convert
/// into a cache under XDG_RUNTIME_DIR, else the largest PNG, scaled. None when the assets are not there.
#[cfg(target_os = "linux")]
fn mark(spark_shell: &str, dark: bool, px: i32) -> Option<String> {
    use spark_winpad::pad;
    let dir = std::path::Path::new(spark_shell).parent().filter(|d| !d.as_os_str().is_empty())?.join("asset");
    let file = dir.join(pad::mark_file(dark, px));
    let largest = dir.join(pad::mark_file(dark, pad::MARK_PNGS[pad::MARK_PNGS.len() - 1]));
    let drawn = if file.extension().is_some_and(|e| e == "svg") {
        svg_at(&file, px)
    } else {
        Some(file).filter(|f| f.is_file())
    };
    drawn
        .or_else(|| Some(largest).filter(|f| f.is_file()))
        .map(|f| f.to_string_lossy().into_owned())
}

/// An SVG drawn at `px` square by rsvg-convert, kept under XDG_RUNTIME_DIR and drawn again only when the SVG is
/// newer than what is kept. None without rsvg-convert, the runtime folder or a PNG out of it.
#[cfg(target_os = "linux")]
fn svg_at(svg: &std::path::Path, px: i32) -> Option<std::path::PathBuf> {
    use std::os::unix::fs::DirBuilderExt;
    use std::process::{Command, Stdio};
    let run = std::env::var_os("XDG_RUNTIME_DIR").filter(|d| !d.is_empty())?;
    let made = std::fs::metadata(svg).and_then(|m| m.modified()).ok()?;
    let dir = std::path::PathBuf::from(run).join("spark-shell-app.icons");
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir).ok()?;
    let name = format!("{}-{px}.png", svg.file_stem()?.to_string_lossy());
    let out = dir.join(&name);
    if std::fs::metadata(&out).and_then(|m| m.modified()).is_ok_and(|kept| kept >= made) {
        return Some(out);
    }
    let size = px.clamp(8, 512).to_string();
    let got = Command::new("rsvg-convert")
        .args(["-w", &size, "-h", &size])
        .arg(svg)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !got.status.success() || !got.stdout.starts_with(b"\x89PNG\r\n\x1a\n") {
        return None;
    }
    let part = dir.join(format!(".{name}.{}", std::process::id()));
    std::fs::write(&part, &got.stdout).ok()?;
    std::fs::rename(&part, &out).ok()?;
    Some(out)
}

/// Shows the pad until SIGTERM or SIGINT (Ok), or until the compositor or sway goes (Err).
#[cfg(target_os = "linux")]
fn run(keys: bool) -> Result<(), String> {
    use calloop::channel::{channel, Event as Msg};
    use calloop::generic::Generic;
    use calloop::signals::{Signal, Signals};
    use calloop::timer::{TimeoutAction, Timer};
    use calloop::{EventLoop, Interest, Mode, PostAction};
    use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
    use spark_winpad::app::App;
    use spark_winpad::sway::{self, Ipc};
    use std::io::Read;
    use std::time::Duration;
    use wayland_client::globals::registry_queue_init;
    use wayland_client::{ConnectError, Connection};

    let cfg = config();
    let Some(_lock) = lock()? else { return Ok(()) };
    // the ground spark's mark stands on: the dark S on a dark surface, the light one on a light one
    let byte = |v: f64| (v * 255.0).round().clamp(0.0, 255.0) as u8;
    let s = cfg.look.surface;
    let dark = spark_winpad::pad::dark_ground(byte(s.0), byte(s.1), byte(s.2));
    if !wayland_sys::client::is_lib_available() {
        return Err("libwayland-client.so.0 is missing (Wayland's client library)".into());
    }
    let lib = spark_winpad::paint::Lib::open()?;
    // before any thread starts: the threads inherit the blocked mask, so the signals reach this loop
    let signals = Signals::new(&[Signal::SIGUSR1, Signal::SIGUSR2, Signal::SIGTERM, Signal::SIGINT]).map_err(|e| format!("signals: {e}"))?;
    let conn = Connection::connect_to_env().map_err(|e| match e {
        ConnectError::NoWaylandLib => "libwayland-client.so.0 is missing (Wayland's client library)".to_string(),
        ConnectError::NoCompositor => "no Wayland compositor here (WAYLAND_DISPLAY)".to_string(),
        ConnectError::InvalidFd => "WAYLAND_SOCKET is not a socket".to_string(),
    })?;
    let ipc = Ipc::connect().map_err(|e| format!("sway: {e}"))?;
    let events = sway::subscribe(&["window", "workspace", "output", "tick"]).map_err(|e| format!("sway: {e}"))?;
    let (globals, mut queue) = registry_queue_init::<App>(&conn).map_err(|e| format!("the compositor's globals: {e}"))?;
    let mut event_loop: EventLoop<'static, App> = EventLoop::try_new().map_err(|e| format!("event loop: {e}"))?;
    let handle = event_loop.handle();
    let spark_shell = cfg.spark_shell.clone();
    let mut app = App::new(&conn, &globals, &queue.handle(), handle.clone(), lib, cfg, ipc, keys)?;
    // the screens' names and scales before the first surface
    queue.roundtrip(&mut app).map_err(|e| format!("the compositor: {e}"))?;
    WaylandSource::new(conn.clone(), queue)
        .insert(handle.clone())
        .map_err(|e| format!("event loop: {}", e.error))?;
    let stop = event_loop.get_signal();
    handle
        .insert_source(signals, |ev, &mut (), app: &mut App| match ev.signal() {
            Signal::SIGUSR1 => app.keys_on(),
            Signal::SIGUSR2 => app.toggle_hidden(),
            _ => app.stop = true,
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    let mut buf = Vec::new();
    handle
        .insert_source(Generic::new(events, Interest::READ, Mode::Level), move |_, s, app: &mut App| {
            let mut chunk = [0u8; 8192];
            let mut stream: &std::os::unix::net::UnixStream = s;
            loop {
                match stream.read(&mut chunk) {
                    Ok(0) => {
                        eprintln!("spark-winpad: sway is gone");
                        app.stop = true;
                        return Ok(PostAction::Remove);
                    }
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(e) => return Err(e),
                }
            }
            for (kind, payload) in sway::split(&mut buf) {
                match kind {
                    sway::EVENT_WINDOW => {
                        let v: serde_json::Value = serde_json::from_slice(&payload).unwrap_or_default();
                        app.window_event(v["change"].as_str().unwrap_or(""), v["container"]["id"].as_i64());
                    }
                    sway::EVENT_WORKSPACE => app.look(),
                    sway::EVENT_OUTPUT => {
                        app.look();
                        app.screens_changed();
                    }
                    sway::EVENT_TICK => {
                        let v: serde_json::Value = serde_json::from_slice(&payload).unwrap_or_default();
                        if v["payload"] == sway::BACK {
                            app.back();
                        } else if v["payload"] == sway::LOOK {
                            app.look();
                        }
                    }
                    _ => {}
                }
            }
            Ok(PostAction::Continue)
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    // the icons, aside: the adapter draws what it has not yet within its own time, so a second read
    // a few seconds on finds the rest
    let (tx, rx) = channel::<Vec<(String, String)>>();
    handle
        .insert_source(rx, |ev, &mut (), app: &mut App| {
            if let Msg::Msg(paths) = ev {
                app.set_icons(paths);
            }
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    let px = app.icon_px();
    std::thread::spawn(move || {
        // the dialog's mark first, spark's own: a file at hand, where the catalog takes its time
        if let Some(path) = mark(&spark_shell, dark, px) {
            let key = spark_winpad::pad::icon_key(spark_winpad::pad::DIALOG);
            if tx.send(vec![(key, path)]).is_err() {
                return;
            }
        }
        if tx.send(icons(&spark_shell, px)).is_ok() {
            std::thread::sleep(Duration::from_secs(5));
            let _ = tx.send(icons(&spark_shell, px));
        }
    });
    let tick = Duration::from_millis(100);
    let mut ticks = 0u32;
    handle
        .insert_source(Timer::from_duration(tick), move |_, _, app: &mut App| {
            app.settle();
            // the tree read again every tick for two seconds after an event, else every half second: a
            // resize or a drag sends no event
            ticks = ticks.wrapping_add(1);
            if app.bursting() || ticks.is_multiple_of(5) {
                app.list_dirty = true;
            }
            TimeoutAction::ToDuration(tick)
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    app.refresh_list();
    let ran = event_loop.run(None, &mut app, |app| {
        if app.list_dirty {
            app.refresh_list();
        }
        if app.dirty {
            app.draw_all();
        }
        if app.deco_dirty {
            app.draw_decos();
        }
        if app.stop {
            stop.stop();
        }
    });
    app.free();
    let _ = conn.flush();
    ran.map_err(|e| format!("the compositor is gone: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(args: &[&str]) -> Result<Ask, String> {
        parse(&args.iter().map(|a| (*a).to_owned()).collect::<Vec<_>>())
    }

    #[test]
    fn arguments() {
        assert_eq!(ask(&[]), Ok(Ask::Run { keys: false }));
        assert_eq!(ask(&["--keys"]), Ok(Ask::Run { keys: true }));
        assert_eq!(ask(&["--keys", "--help"]), Ok(Ask::Help));
        assert_eq!(ask(&["--version"]), Ok(Ask::Version));
        assert_eq!(ask(&["--all"]), Err("unknown argument \"--all\"".into()));
    }

    #[test]
    fn the_gap_is_whole_pixels() {
        assert_eq!(gap(None), 8);
        assert_eq!(gap(Some("16")), 16);
        assert_eq!(gap(Some(" 0 ")), 0);
        assert_eq!(gap(Some("8.5")), 8);
        assert_eq!(gap(Some("-4")), 8);
        assert_eq!(gap(Some("9000")), 8);
    }
}
