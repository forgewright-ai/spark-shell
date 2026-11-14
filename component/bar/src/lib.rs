//! spark-bar: the desktop's status bar. Three domains, kept apart. The bar (bar) is pure and tested:
//! the modules, their cells, the pins, what fits, the targets, the keys and the clicks. The surface
//! (app, with paint, keys and mark) is the Wayland side: it draws what the bar laid out and hands the
//! pointer and the keys back to it. The values are spark-shell's (status): the bar holds no battery,
//! sound, network, clock or brightness logic, and takes its look from there too. sway (sway) lists the
//! workspaces, shows one and names its binding mode.

pub mod bar;
pub mod sway;

#[cfg(target_os = "linux")]
pub mod app;
#[cfg(target_os = "linux")]
pub mod keys;
#[cfg(target_os = "linux")]
pub mod mark;
#[cfg(target_os = "linux")]
pub mod paint;
#[cfg(target_os = "linux")]
pub mod status;
