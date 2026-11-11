//! The adapters: Wayland (the Display), and EGL with libmpv (the
//! Renderer). Every native library is opened at run time, so the binary
//! builds with no -devel package and runs on each family's own libraries;
//! a missing one is a line on stderr, never a panic.

pub mod egl;
pub mod mpv;
pub mod wayland;

/// The libraries opened before anything starts.
pub struct Libraries {
    pub egl: egl::Api,
    pub mpv: mpv::Libmpv,
}

impl Libraries {
    /// Opens each one; the error names the first one missing.
    pub fn open() -> Result<Libraries, String> {
        if !wayland_sys::client::is_lib_available() {
            return Err("libwayland-client.so.0 is missing (Wayland's client library)".into());
        }
        Ok(Libraries {
            egl: egl::open()?,
            mpv: mpv::Libmpv::open()?,
        })
    }
}
