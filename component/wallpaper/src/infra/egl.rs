//! EGL: one display on the Wayland connection, and per screen an OpenGL
//! context with a window surface on the screen's wl_surface. libEGL.so.1
//! and libwayland-egl.so.1 are opened at run time.

use crate::domain::Screen;
use khronos_egl as egl;
use std::ffi::c_void;
use std::rc::Rc;
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, Proxy};
use wayland_egl::WlEglSurface;

/// libEGL's functions, opened at run time.
pub type Api = egl::DynamicInstance<egl::EGL1_4>;

/// Opens libwayland-egl.so.1 and libEGL.so.1; the error names the one missing.
pub fn open() -> Result<Api, String> {
    if !wayland_egl::is_available() {
        return Err("libwayland-egl.so.1 is missing (Wayland's EGL library)".into());
    }
    // SAFETY: libEGL.so.1 is the system's EGL library; khronos-egl finds
    // every EGL 1.4 function in it before it returns the instance.
    unsafe { Api::load_required() }.map_err(|_| "libEGL.so.1 is missing or older than EGL 1.4 (the GPU driver's EGL library)".to_string())
}

/// The EGL display of the Wayland connection, and the config every screen's surface uses.
pub struct Egl {
    api: Api,
    display: egl::Display,
    config: egl::Config,
    /// Kept so the C wl_display EGL and mpv use lives as long as this Egl.
    connection: Connection,
}

impl Egl {
    /// EGL on the connection's C wl_display, with desktop OpenGL bound.
    pub fn new(api: Api, connection: &Connection) -> Result<Egl, String> {
        let connection = connection.clone();
        let wl_display = connection.backend().display_ptr().cast();
        // SAFETY: wl_display is the live C wl_display of the connection,
        // which this Egl holds until after it terminates the EGL display.
        let display = unsafe { api.get_display(wl_display) }.ok_or("EGL has no display for this Wayland connection")?;
        api.initialize(display).map_err(|e| format!("EGL did not start: {e}"))?;
        match settle(&api, display) {
            Ok(config) => Ok(Egl {
                api,
                display,
                config,
                connection,
            }),
            Err(e) => {
                let _ = api.terminate(display);
                Err(e)
            }
        }
    }

    /// The C wl_display, alive as long as this Egl (for libmpv's hardware decoding).
    pub fn wl_display(&self) -> *mut c_void {
        self.connection.backend().display_ptr().cast()
    }

    /// An OpenGL function's address, for libmpv; null when there is none.
    pub fn proc_address(&self, name: &str) -> *mut c_void {
        self.api.get_proc_address(name).map_or(std::ptr::null_mut(), |f| f as *mut c_void)
    }
}

/// Binds desktop OpenGL and picks the first config with a window and 8 bits
/// a color (no alpha asked, so EGL sorts an opaque XRGB config first).
fn settle(api: &Api, display: egl::Display) -> Result<egl::Config, String> {
    api.bind_api(egl::OPENGL_API).map_err(|e| format!("EGL has no desktop OpenGL: {e}"))?;
    let wanted = [
        egl::SURFACE_TYPE,
        egl::WINDOW_BIT,
        egl::RENDERABLE_TYPE,
        egl::OPENGL_BIT,
        egl::RED_SIZE,
        8,
        egl::GREEN_SIZE,
        8,
        egl::BLUE_SIZE,
        8,
        egl::NONE,
    ];
    let config = api
        .choose_first_config(display, &wanted)
        .map_err(|e| format!("EGL could not list its configs: {e}"))?;
    config.ok_or_else(|| "EGL has no OpenGL config for a window".to_string())
}

impl Drop for Egl {
    fn drop(&mut self) {
        let _ = self.api.make_current(self.display, None, None, None);
        let _ = self.api.terminate(self.display);
    }
}

/// A screen's drawing target: its wl_surface, the wl_egl_window on it, an
/// EGL window surface and an OpenGL context of its own.
pub struct Target {
    egl: Rc<Egl>,
    context: egl::Context,
    surface: egl::Surface,
    window: WlEglSurface,
    wl_surface: WlSurface,
    width: i32,
    height: i32,
    scale: i32,
}

impl Target {
    /// The target at the screen's size, made current, its swaps never waiting.
    pub fn new(egl: Rc<Egl>, wl_surface: WlSurface, screen: &Screen) -> Result<Target, String> {
        let (width, height, scale) = pixels(screen)?;
        let window = WlEglSurface::new(wl_surface.id(), width, height).map_err(|e| format!("no EGL window: {e}"))?;
        let context = egl
            .api
            .create_context(egl.display, egl.config, None, &[egl::NONE])
            .map_err(|e| format!("no OpenGL context: {e}"))?;
        // SAFETY: window.ptr() is the wl_egl_window made above on a wl_surface
        // of the same connection as egl.display, and the Target keeps it
        // alive as long as the EGL surface (Drop destroys the surface first).
        let made = unsafe {
            egl.api
                .create_window_surface(egl.display, egl.config, window.ptr() as egl::NativeWindowType, None)
        };
        let surface = match made {
            Ok(surface) => surface,
            Err(e) => {
                let _ = egl.api.destroy_context(egl.display, context);
                return Err(format!("no EGL window surface: {e}"));
            }
        };
        wl_surface.set_buffer_scale(scale);
        let target = Target {
            egl,
            context,
            surface,
            window,
            wl_surface,
            width,
            height,
            scale,
        };
        target.make_current()?;
        // A swap must never wait for the compositor's frame: a hidden screen
        // gets none, and a wait would hold every screen's loop.
        target
            .egl
            .api
            .swap_interval(target.egl.display, 0)
            .map_err(|e| format!("EGL swap interval: {e}"))?;
        Ok(target)
    }

    /// Makes this screen's context and surface the ones OpenGL draws with.
    pub fn make_current(&self) -> Result<(), String> {
        let (egl, surface) = (&self.egl, Some(self.surface));
        egl.api
            .make_current(egl.display, surface, surface, Some(self.context))
            .map_err(|e| format!("EGL make current: {e}"))
    }

    /// Follows the screen's size and scale; both reach the compositor with the next swap.
    pub fn follow(&mut self, screen: &Screen) -> Result<(i32, i32), String> {
        let (width, height, scale) = pixels(screen)?;
        if (width, height) != (self.width, self.height) {
            self.window.resize(width, height, 0, 0);
            (self.width, self.height) = (width, height);
        }
        if scale != self.scale {
            self.wl_surface.set_buffer_scale(scale);
            self.scale = scale;
        }
        Ok((width, height))
    }

    /// Shows what was drawn: the commit carries the frame, its size and its scale.
    pub fn swap(&self) -> Result<(), String> {
        self.egl.api.swap_buffers(self.egl.display, self.surface).map_err(|e| format!("EGL swap: {e}"))
    }

    pub fn egl(&self) -> &Rc<Egl> {
        &self.egl
    }
}

impl Drop for Target {
    fn drop(&mut self) {
        let egl = &self.egl;
        let _ = egl.api.make_current(egl.display, None, None, None);
        let _ = egl.api.destroy_surface(egl.display, self.surface);
        let _ = egl.api.destroy_context(egl.display, self.context);
        // the wl_egl_window goes with the fields, after its EGL surface
    }
}

/// The screen's size in pixels and its scale, as Wayland's and EGL's ints.
fn pixels(screen: &Screen) -> Result<(i32, i32, i32), String> {
    let int = |n: u32| i32::try_from(n).map_err(|_| format!("{}: a size of {n} is too big", screen.name));
    Ok((int(screen.size.width)?, int(screen.size.height)?, int(screen.scale)?))
}
