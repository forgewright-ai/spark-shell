//! spark-bar: the desktop's status bar on a sway desktop, a layer of its own on each output: spark's
//! mark, the output's workspaces, and the status spark-shell says, each block in the cells kept for it.
//! Started with the desktop by spark-shell, for the session.

use std::process::ExitCode;

const USAGE: &str = "spark-bar -- the desktop's status bar: spark's mark, the workspaces, the status spark-shell says (run by spark-shell)

  spark-bar

  --version  the version

One bar on each output, along the top or the bottom. From the left: spark's
mark, then the output's workspaces; a click on one shows it. From the right
edge leftward: the status, each block in the cells kept for it, so a number
that changes moves nothing. When the width is short the optional blocks go
first, then whole modules (BAR_OVERFLOW names the order; the modules it does
not name go before, from the left), then the workspaces farthest from the
one shown; an ellipsis stands for the modules left out. The mark stays.

While sway is in a binding mode other than default, the mode's name stands
after the workspaces, in the accent, as plain text. It takes the room the
status leaves and no click: workspaces go for it, a module never.

The status is spark-shell's: the bar runs SPARK_SHELL bar status with
SPARK_BAR=1, in a process group of its own, and reads the i3bar protocol as
sway's bar does, a line a refresh. A block's name is its module, full_text is
pango markup, and the bar reads its own fields too: cells (the character
cells kept), optional (a label, dropped first), label (the control's name
and state), control (toggle, level or open), state (ok, unavailable or
error). The module logo is the mark. The block named look is no module: it
says the look, each value a string (fg, accent, muted, ground, lit and
attention as rrggbb, alpha as 0 to 1), and every bar is drawn again in a
look that changed. Clicks go to its stdin as sway's bar writes them (name,
instance, button, x, y, relative_x, relative_y, width, height; buttons
1 left, 2 middle, 3 right, 4 wheel up, 5 wheel down). When the status ends,
its stream or the program itself, its group is told to end and it is started
again after 1 s, then 2, 4, up to 30; a line from a status that has run 10 s
starts the count anew.

SIGUSR1 puts the keyboard on the bar of the focused output: Tab and
Shift+Tab go round the targets, Left and Right too; on a level they are the
wheel, and Home and End its ends; Enter or Space is a click; Escape gives
the keyboard back. SIGTERM or SIGINT ends the bar, and its status with it.

spark-shell sets the look and the place in the environment: BAR_POSITION
(top, the default, or bottom), BAR_FONT (a pango font, Monaspace Neon 12),
BAR_FG, BAR_ACCENT, BAR_MUTED, BAR_GROUND, BAR_LIT, BAR_ATTENTION (rrggbb),
BAR_ALPHA (0 to 1), BAR_PINS (the modules shown, apart by blanks; none: all;
workspaces is one), BAR_OVERFLOW, BAR_TRAY_WIDTH (pixels kept clear at the
right end) on BAR_TRAY_OUTPUT (none: every output), and the files BAR_LOCK
(XDG_RUNTIME_DIR/spark-shell-bar.pid, held for the bar's life with its pid
in it: a second bar ends at once) and BAR_STATE
(XDG_RUNTIME_DIR/spark-shell-bar.state); SPARK_SHELL names spark-shell
itself, and the assets beside it give the mark, the dark one or the light
one by the ground. The colors and the alpha are the look until a status line
says its own, and after it for each one the line leaves out or gets wrong.

The state file is written whole after every change, its fields apart by
tabs:

  bar     1
  status  loading|ok|error
  mode    NAME
  output  NAME WIDTH HEIGHT top|bottom SCALE
  target  OUTPUT ID X Y W H KIND STATE FLAGS NAME
  dropped OUTPUT ID

The mode line is there only in a binding mode other than default, with its
name. ID is mark, workspace:N, MODULE.INSTANCE (MODULE alone without an
instance) or more; KIND is mark, workspace, toggle, level or open; STATE is
ok, unavailable or error; FLAGS are focused, hover, selected, urgent,
visible, joined by commas, or -; NAME is the control's name. A dropped line
names a block, a module or a workspace left out for width.
";

#[derive(Debug, PartialEq)]
enum Ask {
    Help,
    Version,
    Run,
}

fn parse(args: &[String]) -> Result<Ask, String> {
    match args.first().map(String::as_str) {
        None => Ok(Ask::Run),
        Some("-h" | "--help") => Ok(Ask::Help),
        Some("--version") => Ok(Ask::Version),
        Some(a) => Err(format!("unknown argument {a:?}")),
    }
}

fn main() -> ExitCode {
    let args: Result<Vec<String>, _> = std::env::args_os().skip(1).map(|a| a.into_string()).collect();
    let Ok(args) = args else {
        eprintln!("spark-bar: an argument is not UTF-8");
        return ExitCode::from(2);
    };
    match parse(&args) {
        Ok(Ask::Help) => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Ok(Ask::Version) => {
            println!("spark-bar {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Ok(Ask::Run) => match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("spark-bar: {e}");
                ExitCode::FAILURE
            }
        },
        Err(e) => {
            eprintln!("spark-bar: {e}\n\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

#[cfg(not(target_os = "linux"))]
fn run() -> Result<(), String> {
    Err("runs only on Linux, under sway".into())
}

/// A file of the bar's under XDG_RUNTIME_DIR, or where the environment names it.
#[cfg(target_os = "linux")]
fn runtime_file(var: &str, name: &str) -> std::path::PathBuf {
    std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            let dir = std::env::var_os("XDG_RUNTIME_DIR").map_or_else(std::env::temp_dir, Into::into);
            dir.join(name)
        })
}

#[cfg(target_os = "linux")]
fn config() -> spark_bar::app::Config {
    use spark_bar::app::{Config, Look};
    use spark_bar::bar::{self, Edge, Prefs};
    use spark_bar::paint::Rgb;
    let env = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());
    let color = |k: &str, d: &str| env(k).and_then(|v| Rgb::hex(&v)).unwrap_or_else(|| Rgb::hex(d).unwrap());
    Config {
        look: Look {
            fg: color("BAR_FG", "383a42"),
            accent: color("BAR_ACCENT", "4078f2"),
            muted: color("BAR_MUTED", "696c77"),
            ground: color("BAR_GROUND", "ebebec"),
            lit: color("BAR_LIT", "dcdcdd"),
            attention: color("BAR_ATTENTION", "e45649"),
            alpha: env("BAR_ALPHA").and_then(|v| bar::alpha(&v)).unwrap_or(1.0),
        },
        font: env("BAR_FONT").unwrap_or_else(|| "Monaspace Neon 12".into()),
        edge: Edge::parse(env("BAR_POSITION").as_deref()),
        prefs: Prefs::new(
            &env("BAR_PINS").unwrap_or_default(),
            &env("BAR_OVERFLOW").unwrap_or_default(),
            env("BAR_TRAY_WIDTH")
                .and_then(|v| v.trim().parse::<i32>().ok())
                .filter(|n| (0..=100_000).contains(n))
                .unwrap_or(0),
            &env("BAR_TRAY_OUTPUT").unwrap_or_default(),
        ),
        spark_shell: env("SPARK_SHELL").unwrap_or_else(|| "spark-shell".into()),
        state_file: runtime_file("BAR_STATE", "spark-shell-bar.state"),
    }
}

/// The one bar: BAR_LOCK held for the bar's life, its pid in it. None when another bar holds it.
#[cfg(target_os = "linux")]
fn lock() -> Result<Option<std::fs::File>, String> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    use std::os::unix::io::AsRawFd;
    let path = runtime_file("BAR_LOCK", "spark-shell-bar.pid");
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

/// Shows the bar until SIGTERM or SIGINT (Ok), or until the compositor or sway goes (Err).
#[cfg(target_os = "linux")]
fn run() -> Result<(), String> {
    use calloop::channel::{channel, Event as Msg};
    use calloop::generic::Generic;
    use calloop::signals::{Signal, Signals};
    use calloop::{EventLoop, Interest, Mode, PostAction};
    use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
    use spark_bar::app::App;
    use spark_bar::status::Said;
    use spark_bar::sway::{self, Ipc};
    use std::io::Read;
    use wayland_client::globals::registry_queue_init;
    use wayland_client::{ConnectError, Connection};

    let cfg = config();
    // before the lock: a bar that holds it ends by its loop alone, never by a signal's own action, which
    // its keeper takes for a crash. And before any thread starts: the threads inherit the blocked mask,
    // so the signals reach this loop
    let signals = Signals::new(&[Signal::SIGUSR1, Signal::SIGTERM, Signal::SIGINT]).map_err(|e| format!("signals: {e}"))?;
    let Some(_lock) = lock()? else { return Ok(()) };
    if !wayland_sys::client::is_lib_available() {
        return Err("libwayland-client.so.0 is missing (Wayland's client library)".into());
    }
    let lib = spark_bar::paint::Lib::open()?;
    let conn = Connection::connect_to_env().map_err(|e| match e {
        ConnectError::NoWaylandLib => "libwayland-client.so.0 is missing (Wayland's client library)".to_string(),
        ConnectError::NoCompositor => "no Wayland compositor here (WAYLAND_DISPLAY)".to_string(),
        ConnectError::InvalidFd => "WAYLAND_SOCKET is not a socket".to_string(),
    })?;
    let ipc = Ipc::connect().map_err(|e| format!("sway: {e}"))?;
    let events = sway::subscribe(&["workspace", "output", "mode"]).map_err(|e| format!("sway: {e}"))?;
    let (globals, mut queue) = registry_queue_init::<App>(&conn).map_err(|e| format!("the compositor's globals: {e}"))?;
    let mut event_loop: EventLoop<'static, App> = EventLoop::try_new().map_err(|e| format!("event loop: {e}"))?;
    let handle = event_loop.handle();
    let (tx, rx) = channel::<Said>();
    let mut app = App::new(&globals, &queue.handle(), handle.clone(), lib, cfg, ipc, tx)?;
    // the outputs' names and scales before the first surface
    queue.roundtrip(&mut app).map_err(|e| format!("the compositor: {e}"))?;
    WaylandSource::new(conn.clone(), queue)
        .insert(handle.clone())
        .map_err(|e| format!("event loop: {}", e.error))?;
    let stop = event_loop.get_signal();
    handle
        .insert_source(signals, |ev, &mut (), app: &mut App| match ev.signal() {
            Signal::SIGUSR1 => app.keys_on(),
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
                        app.failed = Some("sway is gone".into());
                        app.stop = true;
                        return Ok(PostAction::Remove);
                    }
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(e) => return Err(e),
                }
            }
            // a workspace or an output changed: the workspaces are read again, once. The mode is read after any
            // event: a reload puts it back to default and says so with a workspace event alone
            let events = sway::split(&mut buf);
            if events.iter().any(|(kind, _)| *kind != sway::EVENT_MODE) {
                app.read_workspaces();
            }
            if !events.is_empty() && !app.stop {
                app.read_mode();
            }
            Ok(PostAction::Continue)
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    handle
        .insert_source(rx, |ev, &mut (), app: &mut App| {
            if let Msg::Msg(said) = ev {
                app.said(said);
            }
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    app.read_workspaces();
    app.read_mode();
    app.start_status();
    let ran = event_loop.run(None, &mut app, |app| {
        if app.dirty {
            app.draw_all();
        }
        if app.stop {
            stop.stop();
        }
    });
    app.free();
    let _ = conn.flush();
    ran.map_err(|e| format!("the compositor is gone: {e}"))?;
    app.failed.take().map_or(Ok(()), Err)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(args: &[&str]) -> Result<Ask, String> {
        parse(&args.iter().map(|a| (*a).to_owned()).collect::<Vec<_>>())
    }

    #[test]
    fn arguments() {
        assert_eq!(ask(&[]), Ok(Ask::Run));
        assert_eq!(ask(&["--help"]), Ok(Ask::Help));
        assert_eq!(ask(&["-h"]), Ok(Ask::Help));
        assert_eq!(ask(&["--version"]), Ok(Ask::Version));
        assert_eq!(ask(&["--all"]), Err("unknown argument \"--all\"".into()));
    }

    #[test]
    fn the_usage_is_plain_ascii() {
        assert!(USAGE.is_ascii());
    }
}
