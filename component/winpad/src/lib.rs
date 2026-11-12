//! spark-winpad: spark-shell's windows on a sway desktop. The pad, where the minimized ones wait; the
//! buttons on every title band; the order the windows were focused in. Each has a pure, tested model
//! (pad, buttons, order); the adapters are sway's IPC, cairo and pango and libxkbcommon (opened at run
//! time), and the Wayland side (app).

pub mod buttons;
pub mod order;
pub mod pad;
pub mod sway;
mod tree;

#[cfg(target_os = "linux")]
pub mod app;
#[cfg(target_os = "linux")]
pub mod keys;
#[cfg(target_os = "linux")]
pub mod paint;
