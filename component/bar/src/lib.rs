//! spark-bar: the desktop's status bar. Three domains, kept apart. The bar (bar) is pure and tested:
//! the modules and their facts, the look of each by its state, the workspaces' places, what fits, the
//! targets, the keys and the clicks, the levels as they are drawn and the frames of a number's flow. Its
//! icons (icons) are drawings, written from component/bar/icons.py. The surface (app, with paint, keys
//! and mark) is the Wayland side: it draws the frame the bar says and hands the pointer and the keys back
//! to it. The values are spark-shell's (status): the bar holds no battery, sound, network, clock or
//! brightness logic, and takes its palette from there too. sway (sway) lists the workspaces, shows one
//! and names its binding mode. The notifications' stack (notifications) is the program's other job, a process
//! of its own: pure in the same way, with a surface of its own (notifications::ui).

pub mod bar;
pub mod icons;
pub mod notifications;
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
