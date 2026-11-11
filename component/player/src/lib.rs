//! spark-wallpaper's layers: the domain (pure), the application (the use
//! cases and their two ports) and, on Linux, the infrastructure (Wayland,
//! EGL and libmpv, each opened at run time).

pub mod app;
pub mod domain;
#[cfg(target_os = "linux")]
pub mod infra;
