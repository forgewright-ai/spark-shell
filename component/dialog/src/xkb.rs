//! The keyboard as its own layout names the keys: the keymap the compositor hands over, read with libxkbcommon
//! (libxkbcommon.so.0, which sway itself links), opened at run time as spark-winpad opens it. A key's keysym,
//! the character it types, the modifiers held, whether a held key repeats, and the compose sequences of the
//! person's locale (a dead key, then a letter).

use crate::input::Mods;
use libloading::Library;
use std::ffi::{c_char, c_int, c_void, CString};
use std::os::fd::{AsRawFd, OwnedFd};

const XKB_KEYMAP_FORMAT_TEXT_V1: c_int = 1;
const XKB_STATE_MODS_EFFECTIVE: c_int = 1 << 3;
const XKB_COMPOSE_COMPOSING: c_int = 1;
const XKB_COMPOSE_COMPOSED: c_int = 2;
const XKB_COMPOSE_CANCELLED: c_int = 3;
const SONAME: &str = "libxkbcommon.so.0";

struct Lib {
    _lib: Library,
    context_new: unsafe extern "C" fn(c_int) -> *mut c_void,
    context_unref: unsafe extern "C" fn(*mut c_void),
    keymap_new_from_string: unsafe extern "C" fn(*mut c_void, *const c_char, c_int, c_int) -> *mut c_void,
    keymap_unref: unsafe extern "C" fn(*mut c_void),
    keymap_key_repeats: unsafe extern "C" fn(*mut c_void, u32) -> c_int,
    state_new: unsafe extern "C" fn(*mut c_void) -> *mut c_void,
    state_unref: unsafe extern "C" fn(*mut c_void),
    state_update_mask: unsafe extern "C" fn(*mut c_void, u32, u32, u32, u32, u32, u32) -> c_int,
    state_key_get_one_sym: unsafe extern "C" fn(*mut c_void, u32) -> u32,
    state_mod_name_is_active: unsafe extern "C" fn(*mut c_void, *const c_char, c_int) -> c_int,
    keysym_to_utf32: unsafe extern "C" fn(u32) -> u32,
    compose: Option<ComposeLib>,
}

/// The compose half of the library: there since 0.5, and the keyboard types without it.
struct ComposeLib {
    table_new_from_locale: unsafe extern "C" fn(*mut c_void, *const c_char, c_int) -> *mut c_void,
    table_unref: unsafe extern "C" fn(*mut c_void),
    state_new: unsafe extern "C" fn(*mut c_void, c_int) -> *mut c_void,
    state_unref: unsafe extern "C" fn(*mut c_void),
    state_feed: unsafe extern "C" fn(*mut c_void, u32) -> c_int,
    state_get_status: unsafe extern "C" fn(*mut c_void) -> c_int,
    state_get_utf8: unsafe extern "C" fn(*mut c_void, *mut c_char, usize) -> c_int,
    state_reset: unsafe extern "C" fn(*mut c_void),
}

fn get<T: Copy>(lib: &Library, name: &str) -> Option<T> {
    unsafe { lib.get::<T>(name.as_bytes()) }.ok().map(|s| *s)
}

impl Lib {
    fn open() -> Option<Lib> {
        let lib = unsafe { Library::new(SONAME) }.ok()?;
        let compose = (|| {
            Some(ComposeLib {
                table_new_from_locale: get(&lib, "xkb_compose_table_new_from_locale")?,
                table_unref: get(&lib, "xkb_compose_table_unref")?,
                state_new: get(&lib, "xkb_compose_state_new")?,
                state_unref: get(&lib, "xkb_compose_state_unref")?,
                state_feed: get(&lib, "xkb_compose_state_feed")?,
                state_get_status: get(&lib, "xkb_compose_state_get_status")?,
                state_get_utf8: get(&lib, "xkb_compose_state_get_utf8")?,
                state_reset: get(&lib, "xkb_compose_state_reset")?,
            })
        })();
        Some(Lib {
            context_new: get(&lib, "xkb_context_new")?,
            context_unref: get(&lib, "xkb_context_unref")?,
            keymap_new_from_string: get(&lib, "xkb_keymap_new_from_string")?,
            keymap_unref: get(&lib, "xkb_keymap_unref")?,
            keymap_key_repeats: get(&lib, "xkb_keymap_key_repeats")?,
            state_new: get(&lib, "xkb_state_new")?,
            state_unref: get(&lib, "xkb_state_unref")?,
            state_update_mask: get(&lib, "xkb_state_update_mask")?,
            state_key_get_one_sym: get(&lib, "xkb_state_key_get_one_sym")?,
            state_mod_name_is_active: get(&lib, "xkb_state_mod_name_is_active")?,
            keysym_to_utf32: get(&lib, "xkb_keysym_to_utf32")?,
            compose,
            _lib: lib,
        })
    }
}

/// What a pressed key is once the compose sequences have seen it.
#[derive(Debug, PartialEq, Eq)]
pub enum Composed {
    /// No sequence holds it: the key is itself.
    Key,
    /// In the middle of a sequence (a dead key waiting for its letter), or a sequence let go: nothing is typed.
    Held,
    /// A sequence ended: what it types.
    Text(String),
}

/// The keyboard: its keymap and state once the compositor has handed one over.
pub struct Keyboard {
    lib: Lib,
    ctx: *mut c_void,
    keymap: *mut c_void,
    state: *mut c_void,
    compose_table: *mut c_void,
    compose_state: *mut c_void,
}

/// The locale the compose sequences are read for: the environment's, as libc reads it.
fn locale() -> String {
    ["LC_ALL", "LC_CTYPE", "LANG"]
        .iter()
        .find_map(|k| std::env::var(k).ok().filter(|v| !v.is_empty()))
        .unwrap_or_else(|| "C".into())
}

impl Keyboard {
    /// The library opened; the error names it when it is missing.
    pub fn new() -> Result<Keyboard, String> {
        let lib = Lib::open().ok_or_else(|| format!("{SONAME} is missing (the keyboard's layouts)"))?;
        let ctx = unsafe { (lib.context_new)(0) };
        if ctx.is_null() {
            return Err(format!("{SONAME} gave no context"));
        }
        let (mut compose_table, mut compose_state) = (std::ptr::null_mut(), std::ptr::null_mut());
        if let (Some(c), Ok(loc)) = (&lib.compose, CString::new(locale())) {
            unsafe {
                compose_table = (c.table_new_from_locale)(ctx, loc.as_ptr(), 0);
                if !compose_table.is_null() {
                    compose_state = (c.state_new)(compose_table, 0);
                }
            }
        }
        Ok(Keyboard {
            lib,
            ctx,
            keymap: std::ptr::null_mut(),
            state: std::ptr::null_mut(),
            compose_table,
            compose_state,
        })
    }

    fn drop_keymap(&mut self) {
        unsafe {
            if !self.state.is_null() {
                (self.lib.state_unref)(self.state);
            }
            if !self.keymap.is_null() {
                (self.lib.keymap_unref)(self.keymap);
            }
        }
        self.state = std::ptr::null_mut();
        self.keymap = std::ptr::null_mut();
    }

    /// The compositor's keymap (wl_keyboard.keymap): `size` bytes of XKB text in `fd`, read once.
    pub fn keymap(&mut self, fd: OwnedFd, size: u32) {
        self.drop_keymap();
        if size == 0 {
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
            let keymap = (self.lib.keymap_new_from_string)(self.ctx, text.as_ptr(), XKB_KEYMAP_FORMAT_TEXT_V1, 0);
            if keymap.is_null() {
                return;
            }
            let state = (self.lib.state_new)(keymap);
            if state.is_null() {
                (self.lib.keymap_unref)(keymap);
                return;
            }
            self.keymap = keymap;
            self.state = state;
        }
    }

    /// The modifiers and the layout group in use (wl_keyboard.modifiers).
    pub fn modifiers(&mut self, depressed: u32, latched: u32, locked: u32, group: u32) {
        if !self.state.is_null() {
            unsafe {
                (self.lib.state_update_mask)(self.state, depressed, latched, locked, 0, 0, group);
            }
        }
    }

    /// The modifiers held now.
    pub fn mods(&self) -> Mods {
        if self.state.is_null() {
            return Mods::default();
        }
        let on = |name: &std::ffi::CStr| unsafe { (self.lib.state_mod_name_is_active)(self.state, name.as_ptr(), XKB_STATE_MODS_EFFECTIVE) > 0 };
        Mods {
            shift: on(c"Shift"),
            ctrl: on(c"Control"),
            alt: on(c"Mod1"),
            logo: on(c"Mod4"),
        }
    }

    /// The keysym of a key (its evdev code) in the layout and with the modifiers in use; None before a keymap.
    pub fn sym(&self, evdev: u32) -> Option<u32> {
        if self.state.is_null() {
            return None;
        }
        Some(unsafe { (self.lib.state_key_get_one_sym)(self.state, evdev + 8) }).filter(|s| *s != 0)
    }

    /// The character a keysym types; none for a key that types nothing.
    pub fn text(&self, sym: u32) -> Option<char> {
        char::from_u32(unsafe { (self.lib.keysym_to_utf32)(sym) }).filter(|c| *c != '\0')
    }

    /// Whether a held key repeats in this keymap: a letter does, Shift does not.
    pub fn repeats(&self, evdev: u32) -> bool {
        !self.keymap.is_null() && unsafe { (self.lib.keymap_key_repeats)(self.keymap, evdev + 8) } > 0
    }

    /// A pressed key shown to the compose sequences.
    pub fn compose(&mut self, sym: u32) -> Composed {
        let (Some(c), false) = (&self.lib.compose, self.compose_state.is_null()) else {
            return Composed::Key;
        };
        unsafe {
            // a key the sequences ignore (a modifier) changes nothing
            if (c.state_feed)(self.compose_state, sym) == 0 {
                return Composed::Key;
            }
            match (c.state_get_status)(self.compose_state) {
                XKB_COMPOSE_COMPOSING => Composed::Held,
                XKB_COMPOSE_CANCELLED => {
                    (c.state_reset)(self.compose_state);
                    Composed::Held
                }
                XKB_COMPOSE_COMPOSED => {
                    let mut buf = [0u8; 64];
                    let n = (c.state_get_utf8)(self.compose_state, buf.as_mut_ptr() as *mut c_char, buf.len());
                    (c.state_reset)(self.compose_state);
                    let n = (n.max(0) as usize).min(buf.len() - 1);
                    Composed::Text(String::from_utf8_lossy(&buf[..n]).into_owned())
                }
                _ => Composed::Key,
            }
        }
    }

    /// A sequence under way let go: the keyboard left the window.
    pub fn compose_reset(&mut self) {
        if let (Some(c), false) = (&self.lib.compose, self.compose_state.is_null()) {
            unsafe { (c.state_reset)(self.compose_state) };
        }
    }
}

impl Drop for Keyboard {
    fn drop(&mut self) {
        self.drop_keymap();
        unsafe {
            if let Some(c) = &self.lib.compose {
                if !self.compose_state.is_null() {
                    (c.state_unref)(self.compose_state);
                }
                if !self.compose_table.is_null() {
                    (c.table_unref)(self.compose_table);
                }
            }
            (self.lib.context_unref)(self.ctx);
        }
    }
}
