//! The application: the use cases of the wallpaper, and the two ports
//! they drive. No Wayland, EGL or mpv here.

mod ports;
mod wallpaper;

pub use ports::{Display, Input, Renderer};
pub use wallpaper::Wallpaper;
