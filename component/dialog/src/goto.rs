//! A request for an open home to go to a section: a click on a bar block while home is already open
//! (lib/home.py writes it before it focuses the window). One short lowercase name in
//! $XDG_RUNTIME_DIR/spark-home.goto, taken once on the dialog's tick; one older than ten seconds is
//! stale (no home took it in time) and is dropped, so a later home never jumps on its own.
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

/// How long a request waits for the home it was written for.
pub const STALE: Duration = Duration::from_secs(10);

/// The request's file: the runtime folder home.py's launch lock sits in.
pub fn path() -> Option<PathBuf> {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
                .map(|c| c.join("spark-shell"))
        })
        .map(|d| d.join("spark-home.goto"))
}

/// The section a request names: one word of lowercase letters, 32 at most; anything else is none.
pub fn parse(text: &str) -> Option<String> {
    let w = text.trim();
    (!w.is_empty() && w.len() <= 32 && w.bytes().all(|b| b.is_ascii_lowercase())).then(|| w.to_string())
}

/// The request at FILE taken: read, removed, and its section when it is fresh at NOW.
pub fn take_at(file: &Path, now: SystemTime) -> Option<String> {
    let made = std::fs::metadata(file).and_then(|m| m.modified()).ok()?;
    let text = std::fs::read_to_string(file).ok();
    let _ = std::fs::remove_file(file);
    if now.duration_since(made).unwrap_or_default() > STALE {
        return None;
    }
    parse(&text?)
}

/// The request waiting now, taken.
pub fn take() -> Option<String> {
    take_at(&path()?, SystemTime::now())
}
