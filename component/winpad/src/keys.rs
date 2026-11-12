//! The keys as the keyboard's own layout names them: the keymap the compositor hands over, read
//! with libxkbcommon (libxkbcommon.so.0, which sway itself links), opened at run time. So any
//! keyboard drives the pad, a virtual one (wtype) or a Dvorak layout included. Without the library,
//! one line on stderr and the keys read as evdev positions on a US layout.

use crate::model::Key;
use libloading::Library;
use std::ffi::{c_char, c_int, c_void, CString};
use std::os::fd::{AsRawFd, OwnedFd};

const XKB_KEYMAP_FORMAT_TEXT_V1: c_int = 1;
const SONAME: &str = "libxkbcommon.so.0";

struct Lib {
    _lib: Library,
    context_new: unsafe extern "C" fn(c_int) -> *mut c_void,
    context_unref: unsafe extern "C" fn(*mut c_void),
    keymap_new_from_string: unsafe extern "C" fn(*mut c_void, *const c_char, c_int, c_int) -> *mut c_void,
    keymap_unref: unsafe extern "C" fn(*mut c_void),
    state_new: unsafe extern "C" fn(*mut c_void) -> *mut c_void,
    state_unref: unsafe extern "C" fn(*mut c_void),
    state_update_mask: unsafe extern "C" fn(*mut c_void, u32, u32, u32, u32, u32, u32) -> c_int,
    state_key_get_one_sym: unsafe extern "C" fn(*mut c_void, u32) -> u32,
}

fn get<T: Copy>(lib: &Library, name: &str) -> Option<T> {
    unsafe { lib.get::<T>(name.as_bytes()) }.ok().map(|s| *s)
}

impl Lib {
    fn open() -> Option<Lib> {
        let lib = unsafe { Library::new(SONAME) }.ok()?;
        Some(Lib {
            context_new: get(&lib, "xkb_context_new")?,
            context_unref: get(&lib, "xkb_context_unref")?,
            keymap_new_from_string: get(&lib, "xkb_keymap_new_from_string")?,
            keymap_unref: get(&lib, "xkb_keymap_unref")?,
            state_new: get(&lib, "xkb_state_new")?,
            state_unref: get(&lib, "xkb_state_unref")?,
            state_update_mask: get(&lib, "xkb_state_update_mask")?,
            state_key_get_one_sym: get(&lib, "xkb_state_key_get_one_sym")?,
            _lib: lib,
        })
    }
}

/// The keyboard: its keymap and state while there is one, else the evdev positions.
pub struct Keyboard {
    lib: Option<Lib>,
    ctx: *mut c_void,
    keymap: *mut c_void,
    state: *mut c_void,
}

impl Keyboard {
    pub fn new() -> Keyboard {
        let lib = Lib::open();
        if lib.is_none() {
            eprintln!("spark-winpad: {SONAME} is missing (the keyboard's layouts): the keys read as a US keyboard's");
        }
        let ctx = lib.as_ref().map_or(std::ptr::null_mut(), |l| unsafe { (l.context_new)(0) });
        Keyboard {
            lib,
            ctx,
            keymap: std::ptr::null_mut(),
            state: std::ptr::null_mut(),
        }
    }

    fn drop_keymap(&mut self) {
        if let Some(l) = &self.lib {
            unsafe {
                if !self.state.is_null() {
                    (l.state_unref)(self.state);
                }
                if !self.keymap.is_null() {
                    (l.keymap_unref)(self.keymap);
                }
            }
        }
        self.state = std::ptr::null_mut();
        self.keymap = std::ptr::null_mut();
    }

    /// The compositor's keymap (wl_keyboard.keymap): `size` bytes of XKB text in `fd`, read once.
    pub fn keymap(&mut self, fd: OwnedFd, size: u32) {
        self.drop_keymap();
        let Some(l) = &self.lib else { return };
        if self.ctx.is_null() || size == 0 {
            return;
        }
        let len = size as usize;
        let text = unsafe {
            let p = libc::mmap(std::ptr::null_mut(), len, libc::PROT_READ, libc::MAP_PRIVATE, fd.as_raw_fd(), 0);
            if p == libc::MAP_FAILED {
                return;
            }
            let bytes = std::slice::from_raw_parts(p as *const u8, len).to_vec();
            libc::munmap(p, len);
            bytes
        };
        let end = text.iter().position(|&b| b == 0).unwrap_or(text.len());
        let Ok(text) = CString::new(&text[..end]) else { return };
        unsafe {
            let keymap = (l.keymap_new_from_string)(self.ctx, text.as_ptr(), XKB_KEYMAP_FORMAT_TEXT_V1, 0);
            if keymap.is_null() {
                return;
            }
            let state = (l.state_new)(keymap);
            if state.is_null() {
                (l.keymap_unref)(keymap);
                return;
            }
            self.keymap = keymap;
            self.state = state;
        }
    }

    /// The modifiers and the layout group in use (wl_keyboard.modifiers).
    pub fn modifiers(&mut self, depressed: u32, latched: u32, locked: u32, group: u32) {
        if let (Some(l), false) = (&self.lib, self.state.is_null()) {
            unsafe {
                (l.state_update_mask)(self.state, depressed, latched, locked, 0, 0, group);
            }
        }
    }

    /// What a pressed key (its evdev code) is: by the layout's keysym, or by its US position when
    /// there is no keymap to read.
    pub fn key(&self, evdev: u32) -> Option<Key> {
        match (&self.lib, self.state.is_null()) {
            (Some(l), false) => Key::of_sym(unsafe { (l.state_key_get_one_sym)(self.state, evdev + 8) }),
            _ => Key::of_evdev(evdev),
        }
    }
}

impl Default for Keyboard {
    fn default() -> Keyboard {
        Keyboard::new()
    }
}

impl Drop for Keyboard {
    fn drop(&mut self) {
        self.drop_keymap();
        if let (Some(l), false) = (&self.lib, self.ctx.is_null()) {
            unsafe { (l.context_unref)(self.ctx) };
        }
    }
}
