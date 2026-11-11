//! The Renderer: a libmpv core per screen, drawing its loop with OpenGL
//! into the screen's EGL surface through libmpv's render API.
//! libmpv.so.2 (mpv's client API 2) is opened at run time, and only the
//! functions used are typed here, each under its name in mpv's headers
//! (client.h, render.h, render_gl.h).

use super::egl::{Egl, Target};
use crate::app::Renderer;
use crate::domain::{Loop, Scaling, Screen};
use calloop::ping::Ping;
use libloading::Library;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::os::unix::ffi::OsStrExt;
use std::ptr::null_mut;
use std::rc::Rc;
use wayland_client::protocol::wl_surface::WlSurface;

const SONAME: &str = "libmpv.so.2";

/// mpv_handle (client.h)
#[repr(C)]
struct Handle {
    _opaque: [u8; 0],
}

/// mpv_render_context (render.h)
#[repr(C)]
struct RenderContext {
    _opaque: [u8; 0],
}

/// mpv_render_param (render.h)
#[repr(C)]
struct RenderParam {
    kind: c_int,
    data: *mut c_void,
}

/// mpv_opengl_init_params (render_gl.h)
#[repr(C)]
struct OpenGlInitParams {
    get_proc_address: unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_void,
    get_proc_address_ctx: *mut c_void,
}

/// mpv_opengl_fbo (render_gl.h)
#[repr(C)]
struct OpenGlFbo {
    fbo: c_int,
    w: c_int,
    h: c_int,
    internal_format: c_int,
}

/// mpv_event (client.h)
#[repr(C)]
struct Event {
    event_id: c_int,
    _error: c_int,
    _reply_userdata: u64,
    data: *mut c_void,
}

/// mpv_event_log_message (client.h)
#[repr(C)]
struct LogMessage {
    prefix: *const c_char,
    _level: *const c_char,
    text: *const c_char,
    _log_level: c_int,
}

// mpv_render_param_type (render.h)
const MPV_RENDER_PARAM_INVALID: c_int = 0;
const MPV_RENDER_PARAM_API_TYPE: c_int = 1;
const MPV_RENDER_PARAM_OPENGL_INIT_PARAMS: c_int = 2;
const MPV_RENDER_PARAM_OPENGL_FBO: c_int = 3;
const MPV_RENDER_PARAM_FLIP_Y: c_int = 4;
const MPV_RENDER_PARAM_WL_DISPLAY: c_int = 9;
const MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME: c_int = 12;
// mpv_render_update_flag (render.h)
const MPV_RENDER_UPDATE_FRAME: u64 = 1;
// mpv_event_id (client.h)
const MPV_EVENT_NONE: c_int = 0;
const MPV_EVENT_LOG_MESSAGE: c_int = 2;

type Callback = unsafe extern "C" fn(*mut c_void);

/// The functions of libmpv.so.2 the player calls.
pub struct Libmpv {
    /// mpv_create
    create: unsafe extern "C" fn() -> *mut Handle,
    /// mpv_initialize
    initialize: unsafe extern "C" fn(*mut Handle) -> c_int,
    /// mpv_terminate_destroy
    terminate_destroy: unsafe extern "C" fn(*mut Handle),
    /// mpv_set_option_string
    set_option_string: unsafe extern "C" fn(*mut Handle, *const c_char, *const c_char) -> c_int,
    /// mpv_set_property_string
    set_property_string: unsafe extern "C" fn(*mut Handle, *const c_char, *const c_char) -> c_int,
    /// mpv_command
    command: unsafe extern "C" fn(*mut Handle, *mut *const c_char) -> c_int,
    /// mpv_error_string
    error_string: unsafe extern "C" fn(c_int) -> *const c_char,
    /// mpv_request_log_messages
    request_log_messages: unsafe extern "C" fn(*mut Handle, *const c_char) -> c_int,
    /// mpv_wait_event
    wait_event: unsafe extern "C" fn(*mut Handle, f64) -> *mut Event,
    /// mpv_set_wakeup_callback
    set_wakeup_callback: unsafe extern "C" fn(*mut Handle, Option<Callback>, *mut c_void),
    /// mpv_render_context_create
    render_context_create: unsafe extern "C" fn(*mut *mut RenderContext, *mut Handle, *mut RenderParam) -> c_int,
    /// mpv_render_context_set_update_callback
    render_context_set_update_callback: unsafe extern "C" fn(*mut RenderContext, Option<Callback>, *mut c_void),
    /// mpv_render_context_update
    render_context_update: unsafe extern "C" fn(*mut RenderContext) -> u64,
    /// mpv_render_context_render
    render_context_render: unsafe extern "C" fn(*mut RenderContext, *mut RenderParam) -> c_int,
    /// mpv_render_context_free
    render_context_free: unsafe extern "C" fn(*mut RenderContext),
    _library: Library,
}

impl Libmpv {
    /// Opens libmpv.so.2; the error says it is missing, or which function it lacks.
    pub fn open() -> Result<Libmpv, String> {
        // SAFETY: opening libmpv runs only its own initializers.
        let library = unsafe { Library::new(SONAME) }.map_err(|_| format!("{SONAME} is missing (mpv's library, libmpv)"))?;
        // SAFETY: each type is the function's declaration in mpv's headers
        // for client API 2, the API of libmpv.so.2, and the library stays
        // loaded in this struct as long as the pointers.
        unsafe {
            Ok(Libmpv {
                create: symbol(&library, "mpv_create")?,
                initialize: symbol(&library, "mpv_initialize")?,
                terminate_destroy: symbol(&library, "mpv_terminate_destroy")?,
                set_option_string: symbol(&library, "mpv_set_option_string")?,
                set_property_string: symbol(&library, "mpv_set_property_string")?,
                command: symbol(&library, "mpv_command")?,
                error_string: symbol(&library, "mpv_error_string")?,
                request_log_messages: symbol(&library, "mpv_request_log_messages")?,
                wait_event: symbol(&library, "mpv_wait_event")?,
                set_wakeup_callback: symbol(&library, "mpv_set_wakeup_callback")?,
                render_context_create: symbol(&library, "mpv_render_context_create")?,
                render_context_set_update_callback: symbol(&library, "mpv_render_context_set_update_callback")?,
                render_context_update: symbol(&library, "mpv_render_context_update")?,
                render_context_render: symbol(&library, "mpv_render_context_render")?,
                render_context_free: symbol(&library, "mpv_render_context_free")?,
                _library: library,
            })
        }
    }

    /// mpv's words for an error code.
    fn error(&self, code: c_int) -> String {
        // SAFETY: mpv_error_string returns a static string for any code.
        unsafe { CStr::from_ptr((self.error_string)(code)) }.to_string_lossy().into_owned()
    }
}

/// A function of the library, typed by the caller.
///
/// SAFETY: T must be the function's C declaration as a Rust fn pointer.
unsafe fn symbol<T: Copy>(library: &Library, name: &str) -> Result<T, String> {
    // SAFETY: the caller's T is the symbol's declaration.
    unsafe { library.get::<T>(name.as_bytes()) }
        .map(|s| *s)
        .map_err(|_| format!("{SONAME} has no {name} (too old an mpv)"))
}

/// mpv's wakeup and render update callbacks (mpv_set_wakeup_callback,
/// mpv_render_context_set_update_callback): run on mpv's threads, they
/// only wake the event loop, which does the work.
///
/// SAFETY: mpv passes back the pointer it was given: the renderer's Ping.
unsafe extern "C" fn wake(ping: *mut c_void) {
    // SAFETY: ping is the renderer's boxed Ping, which outlives every mpv
    // core (the renderer drops its videos before its Ping); Ping is Sync.
    unsafe { &*(ping as *const Ping) }.ping();
}

// The Ping is used from mpv's threads: it must be Sync.
const _: fn() = || {
    fn sync<T: Sync>() {}
    sync::<Ping>();
};

/// mpv_opengl_init_params.get_proc_address (render_gl.h): an OpenGL
/// function's address, from EGL.
///
/// SAFETY: mpv passes back the pointer it was given (the Egl) and a C string.
unsafe extern "C" fn get_proc_address(egl: *mut c_void, name: *const c_char) -> *mut c_void {
    // SAFETY: egl is the Egl the render context was made with, alive as
    // long as the context (a Video drops its core before its target); name
    // is a NUL-terminated string from mpv.
    let (egl, name) = unsafe { (&*(egl as *const Egl), CStr::from_ptr(name)) };
    name.to_str().map_or(null_mut(), |name| egl.proc_address(name))
}

/// The options of every core: the loop drawn through the render API, by
/// the GPU when it safely can, filling the screen, with no sound.
fn options(scaling: Scaling) -> Vec<(&'static str, &'static str)> {
    let mut options = vec![
        ("vo", "libmpv"),
        ("hwdec", "auto-safe"),
        ("loop-file", "inf"),
        ("aid", "no"),
        // fill the screen and crop the rest, like the still wallpaper's fill
        ("panscan", "1.0"),
        // a frame comes at its time, so drawing it at once is on time (render.h)
        ("video-timing-offset", "0"),
    ];
    if scaling == Scaling::Nearest {
        options.extend([("scale", "nearest"), ("dscale", "nearest")]);
    }
    options
}

/// One libmpv core and its render context, playing one loop.
struct Core {
    lib: Rc<Libmpv>,
    handle: *mut Handle,
    render: *mut RenderContext,
}

impl Core {
    /// Starts the loop. The screen's OpenGL context must be current.
    fn new(lib: &Rc<Libmpv>, egl: &Rc<Egl>, ping: *mut c_void, video: &Loop, scaling: Scaling, logs: &str) -> Result<Core, String> {
        // SAFETY: mpv_create has no preconditions; null means no memory.
        let handle = unsafe { (lib.create)() };
        if handle.is_null() {
            return Err("mpv did not start".into());
        }
        // From here Drop frees the handle on any error.
        let mut core = Core {
            lib: lib.clone(),
            handle,
            render: null_mut(),
        };
        for (name, value) in options(scaling) {
            let (n, v) = (cstring(name)?, cstring(value)?);
            // SAFETY: a live handle, before mpv_initialize; NUL-terminated strings.
            core.check(
                unsafe { (lib.set_option_string)(handle, n.as_ptr(), v.as_ptr()) },
                &format!("option {name}={value}"),
            )?;
        }
        // SAFETY: a live handle, initialized once.
        core.check(unsafe { (lib.initialize)(handle) }, "mpv_initialize")?;
        let level = cstring(logs)?;
        // SAFETY: a live handle; ping outlives the core (see wake).
        unsafe {
            (lib.request_log_messages)(handle, level.as_ptr());
            (lib.set_wakeup_callback)(handle, Some(wake), ping);
        }
        let mut init = OpenGlInitParams {
            get_proc_address,
            get_proc_address_ctx: Rc::as_ptr(egl) as *mut c_void,
        };
        let mut params = [
            RenderParam {
                kind: MPV_RENDER_PARAM_API_TYPE,
                data: c"opengl".as_ptr() as *mut c_void,
            },
            RenderParam {
                kind: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                data: (&raw mut init).cast(),
            },
            RenderParam {
                kind: MPV_RENDER_PARAM_WL_DISPLAY,
                data: egl.wl_display(),
            },
            RenderParam {
                kind: MPV_RENDER_PARAM_INVALID,
                data: null_mut(),
            },
        ];
        // SAFETY: the params are typed as render.h says and live through the
        // call; the screen's OpenGL context is current (the caller's promise).
        let made = unsafe { (lib.render_context_create)(&raw mut core.render, handle, params.as_mut_ptr()) };
        core.check(made, "mpv_render_context_create")?;
        // SAFETY: a live render context; ping outlives it (see wake).
        unsafe { (lib.render_context_set_update_callback)(core.render, Some(wake), ping) };
        core.load(video)?;
        Ok(core)
    }

    fn check(&self, code: c_int, what: &str) -> Result<(), String> {
        if code < 0 {
            return Err(format!("{what}: {}", self.lib.error(code)));
        }
        Ok(())
    }

    fn load(&self, video: &Loop) -> Result<(), String> {
        let path = CString::new(video.path().as_os_str().as_bytes()).map_err(|_| "a path with a NUL byte".to_string())?;
        let mut args = [c"loadfile".as_ptr(), path.as_ptr(), std::ptr::null()];
        // SAFETY: a live handle and a NULL-terminated list of C strings that live through the call.
        self.check(unsafe { (self.lib.command)(self.handle, args.as_mut_ptr()) }, "loadfile")
    }

    fn set_pause(&self, paused: bool) -> Result<(), String> {
        let value = if paused { c"yes" } else { c"no" };
        // SAFETY: a live handle and NUL-terminated strings.
        self.check(
            unsafe { (self.lib.set_property_string)(self.handle, c"pause".as_ptr(), value.as_ptr()) },
            "pause",
        )
    }

    /// True when a new frame waits; prints mpv's log lines on the way.
    fn frame_ready(&self, screen: &str) -> bool {
        self.print_logs(screen);
        // SAFETY: a live render context; this call needs no OpenGL context.
        let flags = unsafe { (self.lib.render_context_update)(self.render) };
        flags & MPV_RENDER_UPDATE_FRAME != 0
    }

    fn print_logs(&self, screen: &str) {
        loop {
            // SAFETY: a live handle; a zero timeout never blocks, and the
            // event (never null) stays valid until the next mpv_wait_event.
            let event = unsafe { &*(self.lib.wait_event)(self.handle, 0.0) };
            match event.event_id {
                MPV_EVENT_NONE => return,
                MPV_EVENT_LOG_MESSAGE if !event.data.is_null() => {
                    // SAFETY: a log message's data is an mpv_event_log_message
                    // whose strings are NUL-terminated.
                    let (prefix, text) = unsafe {
                        let m = &*(event.data as *const LogMessage);
                        (CStr::from_ptr(m.prefix), CStr::from_ptr(m.text))
                    };
                    eprintln!(
                        "spark-wallpaper: {screen}: mpv {}: {}",
                        prefix.to_string_lossy(),
                        text.to_string_lossy().trim_end()
                    );
                }
                _ => {}
            }
        }
    }

    /// Draws the current frame into the current context's window. The
    /// screen's OpenGL context must be current.
    fn draw(&self, width: c_int, height: c_int) -> Result<(), String> {
        let mut fbo = OpenGlFbo {
            fbo: 0,
            w: width,
            h: height,
            internal_format: 0,
        };
        let mut flip: c_int = 1;
        let mut block: c_int = 0;
        let mut params = [
            RenderParam {
                kind: MPV_RENDER_PARAM_OPENGL_FBO,
                data: (&raw mut fbo).cast(),
            },
            // the window's framebuffer has its rows bottom up
            RenderParam {
                kind: MPV_RENDER_PARAM_FLIP_Y,
                data: (&raw mut flip).cast(),
            },
            // never wait for the frame's time: the loop serves every screen
            RenderParam {
                kind: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME,
                data: (&raw mut block).cast(),
            },
            RenderParam {
                kind: MPV_RENDER_PARAM_INVALID,
                data: null_mut(),
            },
        ];
        // SAFETY: a live render context, params typed as render.h says that
        // live through the call, and the screen's context current.
        self.check(unsafe { (self.lib.render_context_render)(self.render, params.as_mut_ptr()) }, "render")
    }
}

impl Drop for Core {
    fn drop(&mut self) {
        // SAFETY: both pointers came from this library and are freed once,
        // the render context first as render.h asks, with the screen's
        // OpenGL context current (Video's Drop).
        unsafe {
            if !self.render.is_null() {
                (self.lib.render_context_free)(self.render);
            }
            (self.lib.terminate_destroy)(self.handle);
        }
    }
}

/// A screen's loop: its core, drawing into its target.
struct Video {
    name: String,
    // declared before the target: mpv lets go of its OpenGL objects while the context is alive
    core: Core,
    target: Target,
}

impl Drop for Video {
    fn drop(&mut self) {
        // mpv_render_context_free needs the screen's context current
        let _ = self.target.make_current();
    }
}

/// The Renderer: a video per screen, on EGL, woken through a calloop Ping.
pub struct MpvRenderer {
    // first: every core goes before the library, EGL and the Ping it uses
    videos: Vec<Video>,
    lib: Rc<Libmpv>,
    egl: Rc<Egl>,
    ping: Box<Ping>,
    verbose: bool,
}

impl MpvRenderer {
    pub fn new(lib: Libmpv, egl: Egl, ping: Ping, verbose: bool) -> MpvRenderer {
        MpvRenderer {
            videos: Vec::new(),
            lib: Rc::new(lib),
            egl: Rc::new(egl),
            ping: Box::new(ping),
            verbose,
        }
    }

    fn video(&self, screen: &str) -> Option<&Video> {
        self.videos.iter().find(|v| v.name == screen)
    }

    fn say(&self, screen: &str, what: &str) {
        if self.verbose {
            eprintln!("spark-wallpaper: {screen}: {what}");
        }
    }
}

impl Renderer<WlSurface> for MpvRenderer {
    fn load(&mut self, screen: &Screen, surface: WlSurface, video: &Loop, scaling: Scaling) -> Result<(), String> {
        let target = Target::new(self.egl.clone(), surface, screen)?;
        let ping = (&raw const *self.ping).cast_mut().cast();
        let logs = if self.verbose { "warn" } else { "error" };
        let core = Core::new(&self.lib, target.egl(), ping, video, scaling, logs)?;
        let (w, h) = (screen.size.width, screen.size.height);
        self.say(&screen.name, &format!("playing {} at {w}x{h}", video.path().display()));
        self.videos.push(Video {
            name: screen.name.clone(),
            core,
            target,
        });
        Ok(())
    }

    fn frame_ready(&mut self, screen: &str) -> bool {
        self.video(screen).is_some_and(|v| v.core.frame_ready(screen))
    }

    fn render(&mut self, screen: &Screen) {
        let Some(video) = self.videos.iter_mut().find(|v| v.name == screen.name) else {
            return;
        };
        let drawn = video
            .target
            .make_current()
            .and_then(|()| video.target.follow(screen))
            .and_then(|(w, h)| video.core.draw(w, h))
            .and_then(|()| video.target.swap());
        if let Err(e) = drawn {
            eprintln!("spark-wallpaper: {}: {e}", screen.name);
        }
    }

    fn pause(&mut self, screen: &str) {
        if let Some(video) = self.video(screen) {
            match video.core.set_pause(true) {
                Ok(()) => self.say(screen, "paused (hidden)"),
                Err(e) => eprintln!("spark-wallpaper: {screen}: {e}"),
            }
        }
    }

    fn resume(&mut self, screen: &str) {
        if let Some(video) = self.video(screen) {
            match video.core.set_pause(false) {
                Ok(()) => self.say(screen, "resumed (shown)"),
                Err(e) => eprintln!("spark-wallpaper: {screen}: {e}"),
            }
        }
    }

    fn unload(&mut self, screen: &str) {
        self.videos.retain(|v| v.name != screen);
        self.say(screen, "stopped");
    }
}

fn cstring(s: &str) -> Result<CString, String> {
    CString::new(s).map_err(|_| format!("{s:?} has a NUL byte"))
}
