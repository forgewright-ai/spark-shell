//! The microphone through ALSA's library, opened at run time (libasound.so.2): one channel, 16-bit, 16 kHz,
//! the device `default` unless told another.

use libloading::{Library, Symbol};
use std::ffi::{c_char, c_int, c_long, c_uint, c_ulong, c_void, CStr, CString};

const CAPTURE: c_int = 1;
const S16_LE: c_int = 2;
const RW_INTERLEAVED: c_int = 3;
pub const RATE: u32 = 16000;

type Open = unsafe extern "C" fn(*mut *mut c_void, *const c_char, c_int, c_int) -> c_int;
type SetParams = unsafe extern "C" fn(*mut c_void, c_int, c_int, c_uint, c_uint, c_int, c_uint) -> c_int;
type ReadI = unsafe extern "C" fn(*mut c_void, *mut c_void, c_ulong) -> c_long;
type Recover = unsafe extern "C" fn(*mut c_void, c_int, c_int) -> c_int;
type Close = unsafe extern "C" fn(*mut c_void) -> c_int;
type StrError = unsafe extern "C" fn(c_int) -> *const c_char;

pub struct Mic {
    _lib: Library,
    pcm: *mut c_void,
    readi: ReadI,
    recover: Recover,
    close: Close,
    strerror: StrError,
}

fn sym<T: Copy>(lib: &Library, name: &[u8]) -> Result<T, String> {
    let s: Symbol<T> = unsafe { lib.get(name) }.map_err(|_| format!("{} is missing from libasound", String::from_utf8_lossy(name)))?;
    Ok(*s)
}

impl Mic {
    pub fn open(device: &str) -> Result<Mic, String> {
        let lib = unsafe { Library::new("libasound.so.2") }.map_err(|_| "libasound.so.2 is missing (ALSA's library)".to_string())?;
        let open: Open = sym(&lib, b"snd_pcm_open")?;
        let set_params: SetParams = sym(&lib, b"snd_pcm_set_params")?;
        let readi: ReadI = sym(&lib, b"snd_pcm_readi")?;
        let recover: Recover = sym(&lib, b"snd_pcm_recover")?;
        let close: Close = sym(&lib, b"snd_pcm_close")?;
        let strerror: StrError = sym(&lib, b"snd_strerror")?;
        let name = CString::new(device).map_err(|_| "a device name holds no NUL".to_string())?;
        let mut pcm: *mut c_void = std::ptr::null_mut();
        let say = |err: c_int| unsafe { CStr::from_ptr(strerror(err)).to_string_lossy().into_owned() };
        let err = unsafe { open(&mut pcm, name.as_ptr(), CAPTURE, 0) };
        if err < 0 {
            return Err(format!("{device}: {}", say(err)));
        }
        let err = unsafe { set_params(pcm, S16_LE, RW_INTERLEAVED, 1, RATE, 1, 200_000) };
        if err < 0 {
            unsafe { close(pcm) };
            return Err(format!("{device}: {}", say(err)));
        }
        Ok(Mic {
            _lib: lib,
            pcm,
            readi,
            recover,
            close,
            strerror,
        })
    }

    /// Frames into `out`: how many came; an overrun is recovered from.
    pub fn read(&mut self, out: &mut [i16]) -> Result<usize, String> {
        loop {
            let n = unsafe { (self.readi)(self.pcm, out.as_mut_ptr().cast(), out.len() as c_ulong) };
            if n >= 0 {
                return Ok(n as usize);
            }
            if unsafe { (self.recover)(self.pcm, n as c_int, 1) } < 0 {
                let why = unsafe { CStr::from_ptr((self.strerror)(n as c_int)).to_string_lossy().into_owned() };
                return Err(format!("the microphone stopped: {why}"));
            }
        }
    }
}

// one thread reads the handle at a time
unsafe impl Send for Mic {}

impl Drop for Mic {
    fn drop(&mut self) {
        unsafe { (self.close)(self.pcm) };
    }
}
