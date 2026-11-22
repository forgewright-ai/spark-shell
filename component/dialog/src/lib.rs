//! The spark dialog (spark-shell issue 1): an MCP host that draws one
//! window of 60 by 40 cells for every domain of the desktop.

pub mod animation;
pub mod app;
mod appearance;
pub mod apps;
pub mod audit;
pub mod calendar;
pub mod draw;
pub mod files;
pub mod gate;
pub mod glyphs;
pub mod goto;
pub mod greetd;
pub mod grid;
pub mod helper;
pub mod input;
pub mod interaction;
pub mod keys;
pub mod login;
pub mod mcp;
pub mod model;
pub mod page;
#[cfg(target_os = "linux")]
pub mod paint;
pub mod palette;
pub mod pieces;
pub mod preferences;
pub mod preview;
pub mod progress;
pub mod reply;
pub mod scene;
pub mod scrub;
pub mod search;
pub mod semantic;
pub mod sha256;
pub mod sixel;
pub mod terminal;
pub mod ui;
#[cfg(target_os = "linux")]
pub mod window;
#[cfg(target_os = "linux")]
pub mod xkb;
