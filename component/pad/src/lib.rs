//! spark-pad: the minimized windows of a sway desktop, on a surface of their own. The model is
//! pure and tested; the adapters are sway's IPC, cairo and pango and libxkbcommon (opened at run
//! time), and the Wayland side.

pub mod model;
pub mod sway;

#[cfg(target_os = "linux")]
pub mod app;
#[cfg(target_os = "linux")]
pub mod keys;
#[cfg(target_os = "linux")]
pub mod paint;
