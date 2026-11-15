//! spark-bar: the desktop's status bar on a sway desktop, a layer of its own on each output: spark's
//! mark, the workspaces' ten places, and the status spark-shell says, each module's facts drawn in the
//! bar's own look. Started with the desktop by spark-shell, for the session.

use std::process::ExitCode;

const USAGE: &str = "spark-bar -- the desktop's status bar: spark's mark, the workspaces, the status spark-shell says (run by spark-shell)

  spark-bar

  --version  the version

One bar on each output, along the top or the bottom, laid out in cells of
its font. From the left: spark's mark, then ten places for the workspaces 1
to 10, three cells each, in the glyph family's gauge pair: the full glyph
where a workspace is, on any output, the light one where none is, the full
one in the attention color where a window asks for you. The workspace the
output shows is the plate, in its own place: on the accent, its number in
two digits. No place moves when another workspace is shown. Any other
workspace gets a place after the tenth. A click on a place shows its
workspace.

From the right edge leftward: the status, module by module. A module's
parts are its sign, a cell a glyph, or its icon, drawn the text's size in
two cells; when it has a level and is pinned, a gauge of five cells and
its number; then its text in the cells kept for it, so a text that changes
moves nothing. One cell stands between a module's parts, three
between the modules of a group, five between groups, and a hairline before
the group time. Under the pointer a part stands on a chip of the lit tone
and keeps its own color, a dim part's raised halfway to the text's; a
place's chip is its three cells; the plate does not change.

When the width is short every pinned control gives up its number, then its
gauge; then whole modules go (BAR_OVERFLOW names the order; the modules it
does not name go before, from the left) and three dots stand for them: a
click on the dots opens home. The mark, the workspaces and the group time
stay.

While sway is in a binding mode other than default, the mode's name stands
five cells before the status, in the attention color, as plain text. It
takes the room the status leaves and no click.

The room after the workspaces is the pad's: spark-winpad stands there, on
a surface of its own, when its place is the bar (Apps). The bar draws
nothing in it, and says where it is in the state file.

The status is spark-shell's: the bar runs SPARK_SHELL bar status with
SPARK_BAR=1, in a process group of its own, and reads its stream as sway's
bar does, a line a refresh: a JSON array of objects that say facts, and no
markup. The object named look says the look, each value a string: fg,
accent, muted (the dim tone), ground, lit, attention, alert (red) and ink
(what is written on the accent: the plate's digits and the keys' line
there; without one, the ground's color) as rrggbb, alpha as 0 to 1, full
and light (the family's gauge pair, a glyph each), motion (yes or no).
Every other object with a name is a module, in the bar's order: name,
group, sign (its glyph or its word), icon (a drawing's name, lan or
out-muted: it stands for the sign where the bar has that drawing, in the
sign's tone), text and cells (the cells kept for the text), bold, state (ok, muted, off, missing, wrong, asks or records), level
(0 to 100, when it has one), set (the level can be set from the bar),
pinned (its gauge and number are on the bar), toggle (a click on its sign
or its text changes something in place and opens nothing) and label (its
name and state in words). The bar picks every tone by the state: the text's
color for what is well; muted dims its sign and its gauge, and its number
is not drawn; off and missing are dim, and missing draws no gauge and no
number; the sign is red for wrong and records, and the attention color for
asks; a module with no sign says its state on its text.

Clicks go to its stdin as sway's bar writes them (name, instance, button,
x, y, relative_x, relative_y, width, height; buttons 1 left, 2 middle, 3
right, 4 wheel up, 5 wheel down): name is the module and instance its part,
name (the sign), gauge, pct (the number) or text; the mark and the three
dots send logo. On a level that can be set, the wheel on any of its parts
(5 a step) and a click on its gauge (the place clicked, rounded to 5)
change the level drawn at once. The status's lines are the truth, all but
the old answers: in a burst the status answers each step in turn, and a
line that says the value of a step made in the last second, while a later
step is still unanswered, is not drawn. Once the last step is answered
every line is news again. A number on the bar that changes flows: only the
digits that change move, for 120 ms, and not at all with motion no. When
the status ends, its stream or the program itself, its group is told to end
and it is started again after 1 s, then 2, 4, up to 30; a line from a
status that has run 10 s starts the count anew.

SIGUSR1 puts the keyboard on the bar of the focused output, and a line in
the accent stands under the part the keys are on (in the ink on the
plate): Tab and Shift+Tab go round the targets, and Left and Right too;
Up and Down are the wheel on any part of a level that can be set, and Home
and End its ends on its gauge; Enter or Space is a click, and gives the
keyboard back, except on the sign or the text of a module that says toggle,
where the keys stay; Escape gives it back, and so does a button pressed off
the bar, or the pointer moved more than three cells there. SIGTERM or
SIGINT ends the bar, and its status with it.

An output rests while the workspace it shows has the rest name (BAR_REST),
or that name, a space and more: it has no bar, nothing drawn, no room
kept, no pointer and no keys, and a bar that had the keys gives them back
first. When it shows another workspace its bar is back. A workspace with
such a name has no place on any output's bar.

spark-shell sets the look and the place in the environment: BAR_POSITION
(top, the default, or bottom), BAR_FONT (a pango font, Monaspace Neon 12),
BAR_FG, BAR_ACCENT, BAR_MUTED, BAR_GROUND, BAR_LIT, BAR_ATTENTION,
BAR_ALERT and BAR_INK (rrggbb), BAR_ALPHA (0 to 1), BAR_GAUGE_FULL and
BAR_GAUGE_LIGHT (the gauge pair, a glyph each; the star family's without
them), BAR_MOTION (yes, the default, or no), BAR_OVERFLOW, BAR_REST (the
rest name; none: no output rests), BAR_TRAY_WIDTH (pixels kept clear at
the right end) on BAR_TRAY_OUTPUT (none: every output), and the files
BAR_LOCK (XDG_RUNTIME_DIR/spark-shell-bar.pid, held for the bar's life with
its pid in it: a second bar ends at once) and BAR_STATE
(XDG_RUNTIME_DIR/spark-shell-bar.state); SPARK_SHELL names spark-shell
itself, and the assets beside it give the mark, the dark one or the light
one by the ground. The environment's look is the look until a status line
says its own, and after it for each value the line leaves out or gets
wrong.

The state file is written whole after every change, its fields apart by
tabs:

  bar     1
  status  loading|ok|error
  mode    NAME
  level   MODULE LEVEL
  rest    OUTPUT
  output  NAME WIDTH HEIGHT top|bottom SCALE
  apps    OUTPUT X W
  target  OUTPUT ID X Y W H KIND STATE FLAGS NAME
  dropped OUTPUT ID

The mode line is there only in a binding mode other than default, with its
name; a level line for each module that has a level, as it is drawn; a rest
line for each output that rests, which has no output line and no target; an
apps line for each output that has a bar, the room after the workspaces it
keeps for the pad's windows, from X and W wide, in the bar's pixels. ID
is mark, workspace:N, MODULE.PART (name, gauge, pct or text) or more; X Y W
H is the part as wide as it is drawn, the bar's whole height; KIND is mark,
workspace, toggle (the sign or the text of a module that says toggle),
level (a gauge that can be set) or open; STATE is the module's (ok for the
mark, a workspace and more); FLAGS are focused, hover, selected, urgent,
visible (the plate), empty (a place with no workspace), joined by commas,
or -; NAME is the control's name. A dropped line names a number
(MODULE.pct), a gauge (MODULE.gauge) or a module left out for width.
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
            alert: color("BAR_ALERT", "e45649"),
            ink: env("BAR_INK").and_then(|v| Rgb::hex(&v)),
            alpha: env("BAR_ALPHA").and_then(|v| bar::alpha(&v)).unwrap_or(1.0),
            full: env("BAR_GAUGE_FULL").and_then(|v| bar::pair_glyph(&v)).unwrap_or_else(|| bar::PAIR.0.into()),
            light: env("BAR_GAUGE_LIGHT").and_then(|v| bar::pair_glyph(&v)).unwrap_or_else(|| bar::PAIR.1.into()),
            motion: env("BAR_MOTION").and_then(|v| bar::motion(&v)).unwrap_or(true),
        },
        font: env("BAR_FONT").unwrap_or_else(|| "Monaspace Neon 12".into()),
        edge: Edge::parse(env("BAR_POSITION").as_deref()),
        prefs: Prefs::new(
            &env("BAR_OVERFLOW").unwrap_or_default(),
            env("BAR_TRAY_WIDTH")
                .and_then(|v| v.trim().parse::<i32>().ok())
                .filter(|n| (0..=100_000).contains(n))
                .unwrap_or(0),
            &env("BAR_TRAY_OUTPUT").unwrap_or_default(),
        ),
        rest: env("BAR_REST").unwrap_or_default(),
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
    // sway's workspaces, then the outputs' names and scales, before the first surface: an output at rest gets none
    app.read_workspaces();
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
