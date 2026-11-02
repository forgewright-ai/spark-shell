//! spark-wallpaper: a looping video as the wallpaper, on the background
//! layer of each screen, under the windows; a screen's loop pauses while
//! the screen is hidden. Started and stopped by spark-shell.

use spark_wallpaper::domain::{Assignment, Config, Scaling};
use std::process::ExitCode;

const USAGE: &str = "spark-wallpaper -- a looping video as the wallpaper of each screen (run by spark-shell)

  spark-wallpaper [--scale smooth|nearest] [--verbose] --all FILE
  spark-wallpaper [--scale smooth|nearest] [--verbose] --screen NAME=FILE...

  --all FILE           play FILE on every screen
  --screen NAME=FILE   play FILE on the screen sway names NAME (DP-3, HDMI-A-1);
                       a screen with no --screen keeps the wallpaper under it
  --scale nearest      keep pixel art sharp (smooth by default)
  --verbose            say on stderr when a screen plays, pauses, resumes or stops

A screen's loop pauses while sway draws it no frame (covered by windows, or
a full screen window on it). SIGTERM or SIGINT ends it.
";

/// What the command line asks for.
#[derive(Debug, PartialEq)]
enum Ask {
    Help,
    Play { config: Config, verbose: bool },
}

fn parse(args: &[String]) -> Result<Ask, String> {
    let (mut all, mut screens, mut scaling, mut verbose) = (None, Vec::new(), Scaling::Smooth, false);
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Ask::Help),
            "-v" | "--verbose" => verbose = true,
            "--all" | "--screen" | "--scale" => {
                let value = args.next().ok_or_else(|| format!("{arg} needs a value"))?.as_str();
                match arg.as_str() {
                    "--all" if all.replace(value).is_some() => return Err("--all takes one file".into()),
                    "--all" => {}
                    "--screen" => screens.push(value),
                    _ => scaling = Scaling::parse(value).map_err(|e| e.to_string())?,
                }
            }
            _ => return Err(format!("unknown argument {arg:?}")),
        }
    }
    let assignment = Assignment::from_args(all, &screens).map_err(|e| e.to_string())?;
    Ok(Ask::Play {
        config: Config { assignment, scaling },
        verbose,
    })
}

fn main() -> ExitCode {
    let args: Result<Vec<String>, _> = std::env::args_os().skip(1).map(|a| a.into_string()).collect();
    let Ok(args) = args else {
        eprintln!("spark-wallpaper: an argument is not UTF-8");
        return ExitCode::from(2);
    };
    match parse(&args) {
        Ok(Ask::Help) => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Ok(Ask::Play { config, verbose }) => match play(config, verbose) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("spark-wallpaper: {e}");
                ExitCode::FAILURE
            }
        },
        Err(e) => {
            eprintln!("spark-wallpaper: {e}\n\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

#[cfg(not(target_os = "linux"))]
fn play(_: Config, _: bool) -> Result<(), String> {
    Err("plays only on Linux, under a Wayland compositor".into())
}

/// How often the player looks for a screen whose frame has not come (the
/// domain's QUIET_MS): often enough that a covered screen pauses soon after
/// the threshold, and too rare to cost anything.
#[cfg(target_os = "linux")]
const TICK: std::time::Duration = std::time::Duration::from_millis(100);

/// Plays until SIGTERM or SIGINT (Ok), or until the compositor goes (Err).
#[cfg(target_os = "linux")]
fn play(config: Config, verbose: bool) -> Result<(), String> {
    use calloop::signals::{Signal, Signals};
    use calloop::timer::{TimeoutAction, Timer};
    use calloop::{ping, EventLoop};
    use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
    use spark_wallpaper::app::{Input, Wallpaper};
    use spark_wallpaper::infra::egl::Egl;
    use spark_wallpaper::infra::mpv::MpvRenderer;
    use spark_wallpaper::infra::wayland::Desktop;
    use spark_wallpaper::infra::Libraries;
    use std::time::Instant;
    use wayland_client::globals::registry_queue_init;
    use wayland_client::{ConnectError, Connection};

    for video in config.assignment.loops() {
        if !video.path().is_file() {
            return Err(format!("no such file: {}", video.path().display()));
        }
    }
    let libraries = Libraries::open()?;
    // Before any thread starts: mpv's and the GPU driver's threads inherit
    // the blocked mask, so SIGTERM and SIGINT reach this loop and the
    // player lets mpv and EGL go before it exits.
    let signals = Signals::new(&[Signal::SIGTERM, Signal::SIGINT]).map_err(|e| format!("signals: {e}"))?;
    let conn = Connection::connect_to_env().map_err(|e| match e {
        ConnectError::NoWaylandLib => "libwayland-client.so.0 is missing (Wayland's client library)".to_string(),
        ConnectError::NoCompositor => "no Wayland compositor here (WAYLAND_DISPLAY)".to_string(),
        ConnectError::InvalidFd => "WAYLAND_SOCKET is not a socket".to_string(),
    })?;
    let (globals, queue) = registry_queue_init::<Desktop>(&conn).map_err(|e| format!("the compositor's globals: {e}"))?;
    let mut desktop = Desktop::new(&globals, &queue.handle())?;
    let egl = Egl::new(libraries.egl, &conn)?;

    let mut event_loop: EventLoop<Desktop> = EventLoop::try_new().map_err(|e| format!("event loop: {e}"))?;
    let handle = event_loop.handle();
    WaylandSource::new(conn.clone(), queue)
        .insert(handle.clone())
        .map_err(|e| format!("event loop: {}", e.error))?;
    // mpv says it has a frame (or a log line) from its own threads; the Ping
    // turns that into an input of this loop.
    let (ping, woke) = ping::make_ping().map_err(|e| format!("event loop: {e}"))?;
    handle
        .insert_source(woke, |(), &mut (), desktop| desktop.push(Input::RendererWoke))
        .map_err(|e| format!("event loop: {}", e.error))?;
    let ticks = handle.insert_source(Timer::from_duration(TICK), |_, &mut (), desktop| {
        desktop.push(Input::Tick);
        TimeoutAction::ToDuration(TICK)
    });
    ticks.map_err(|e| format!("event loop: {}", e.error))?;
    let stop = event_loop.get_signal();
    handle
        .insert_source(signals, move |_, &mut (), _| stop.stop())
        .map_err(|e| format!("event loop: {}", e.error))?;

    let mut renderer = MpvRenderer::new(libraries.mpv, egl, ping, verbose);
    let mut wallpaper = Wallpaper::new(config);
    let ran = event_loop.run(None, &mut desktop, |desktop| {
        for input in desktop.take_inbox() {
            if let Err(e) = wallpaper.handle(input, Instant::now(), desktop, &mut renderer) {
                eprintln!("spark-wallpaper: {e}");
            }
        }
    });
    wallpaper.stop(&mut desktop, &mut renderer);
    // mpv and EGL go before the Wayland connection they draw on
    drop(renderer);
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
    fn all_with_the_defaults() {
        let config = Config {
            assignment: Assignment::from_args(Some("/c/sea.mp4"), &[]).unwrap(),
            scaling: Scaling::Smooth,
        };
        assert_eq!(ask(&["--all", "/c/sea.mp4"]), Ok(Ask::Play { config, verbose: false }));
    }

    #[test]
    fn screens_nearest_and_verbose() {
        let assignment = Assignment::from_args(None, &["DP-3=/c/a.mp4", "HDMI-A-1=/c/b.mp4"]).unwrap();
        let config = Config {
            assignment,
            scaling: Scaling::Nearest,
        };
        let got = ask(&["--scale", "nearest", "--screen", "DP-3=/c/a.mp4", "-v", "--screen", "HDMI-A-1=/c/b.mp4"]);
        assert_eq!(got, Ok(Ask::Play { config, verbose: true }));
    }

    #[test]
    fn help_wins() {
        assert_eq!(ask(&["--all", "/c/sea.mp4", "--help"]), Ok(Ask::Help));
    }

    #[test]
    fn mistakes_are_named() {
        assert_eq!(ask(&["--all"]), Err("--all needs a value".into()));
        assert_eq!(ask(&["--all", "/a", "--all", "/b"]), Err("--all takes one file".into()));
        assert_eq!(
            ask(&["--scale", "big", "--all", "/a"]),
            Err("--scale takes smooth or nearest, not \"big\"".into())
        );
        assert_eq!(ask(&["--loop", "/a"]), Err("unknown argument \"--loop\"".into()));
        assert_eq!(ask(&[]), Err("no loop: give --all FILE or --screen NAME=FILE".into()));
        assert_eq!(
            ask(&["--all", "/a", "--screen", "DP-3=/b"]),
            Err("--all and --screen do not go together".into())
        );
    }
}
