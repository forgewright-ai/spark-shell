//! The wallpaper's domain: screens, loops and how a loop is scaled, which
//! loop plays on which screen, and when a screen's loop plays or pauses.
//! Pure: no I/O, no clock (time comes in as numbers), no unsafe.

mod assignment;
mod playback;
mod screen;
mod video;

pub use assignment::Assignment;
pub use playback::{Command, Event, Playback, QUIET_MS};
pub use screen::{Screen, Size};
pub use video::{Loop, Scaling};

use std::fmt;

/// What the player is asked to do: which loop plays where, and how it is scaled.
#[derive(Clone, Debug, PartialEq)]
pub struct Config {
    pub assignment: Assignment,
    pub scaling: Scaling,
}

/// A request the domain refuses, in the words a person reads on stderr.
#[derive(Clone, Debug, PartialEq)]
pub enum Error {
    /// A loop was given with no path.
    EmptyPath,
    /// A --screen value that is not NAME=FILE.
    ScreenSpec(String),
    /// The same screen was given two loops.
    TwoLoops(String),
    /// --all and --screen were both given.
    AllAndScreens,
    /// Neither --all nor --screen was given.
    NoLoop,
    /// A --scale value other than smooth or nearest.
    Scaling(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::EmptyPath => write!(f, "a loop needs a file"),
            Error::ScreenSpec(spec) => write!(f, "--screen takes NAME=FILE, not {spec:?}"),
            Error::TwoLoops(name) => write!(f, "the screen {name} was given two loops"),
            Error::AllAndScreens => write!(f, "--all and --screen do not go together"),
            Error::NoLoop => write!(f, "no loop: give --all FILE or --screen NAME=FILE"),
            Error::Scaling(value) => write!(f, "--scale takes smooth or nearest, not {value:?}"),
        }
    }
}

impl std::error::Error for Error {}
