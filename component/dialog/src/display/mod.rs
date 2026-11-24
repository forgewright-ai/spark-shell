//! The display section's own state over its rows (v0.167): the screen chosen in the map, a drag of one, and a change
//! of a screen on trial.

pub mod screens;
mod surface;
pub mod trial;

use crate::model::Call;
use std::time::Instant;

#[derive(Default)]
pub struct State {
    /// The screen the keys act on in the map, once a key or a click chose one.
    pub chosen: Option<String>,
    /// A press on a screen of the map, not let go yet.
    pub drag: Option<Drag>,
    /// The screen last clicked, and when: a second click on it opens it.
    click: Option<(String, Instant)>,
    /// A change of a screen on trial, and the seconds its card shows.
    pub trial: Option<trial::Trial>,
    left: u64,
    /// The step that ends a trial, on its way: kept or put back already, its refusal is no alarm.
    ending: Option<Call>,
    /// The rows read once more after a trial ended by itself: the desktop's clock and this one are a moment apart.
    again: Option<(usize, Instant)>,
}

/// A screen of the map under a held button: the map's row among the picks, the screen, where the press was, how far
/// the pointer has come since, both in the window's pixels, and how many of those a layout pixel is.
#[derive(Clone, Debug, PartialEq)]
pub struct Drag {
    pub row: usize,
    pub name: String,
    from: (f64, f64),
    pub by: (f64, f64),
    scale: f64,
    /// Past a few pixels it is a drag, and the click it began as is gone.
    pub moved: bool,
    /// Where it lands let go now, in layout pixels: none for a screen that cannot be moved.
    pub landing: Option<(i32, i32)>,
}
