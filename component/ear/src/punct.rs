//! The punctuation the words wear while they are spoken: sherpa-onnx's online punctuation model through its
//! C API, opened at run time beside the engine. It reads text and gives text back, so it costs no audio work.

use libloading::{Library, Symbol};
use std::ffi::{c_char, c_int, c_void, CStr, CString};

#[repr(C)]
struct ModelConfig {
    cnn_bilstm: *const c_char,
    bpe_vocab: *const c_char,
    num_threads: c_int,
    debug: c_int,
    provider: *const c_char,
}
#[repr(C)]
struct Config {
    model: ModelConfig,
}

type Create = unsafe extern "C" fn(*const Config) -> *const c_void;
type Destroy = unsafe extern "C" fn(*const c_void);
type AddPunct = unsafe extern "C" fn(*const c_void, *const c_char) -> *const c_char;
type FreeText = unsafe extern "C" fn(*const c_char);

/// The model, loaded once.
pub struct Punct {
    _lib: Library,
    punct: *const c_void,
    add: AddPunct,
    free: FreeText,
    destroy: Destroy,
}

fn sym<T: Copy>(lib: &Library, name: &[u8]) -> Result<T, String> {
    let s: Symbol<T> = unsafe { lib.get(name) }.map_err(|_| format!("{} is missing from the engine's library", String::from_utf8_lossy(name)))?;
    Ok(*s)
}

impl Punct {
    /// `lib` is libsherpa-onnx-c-api.so, `model` the folder with model.onnx and bpe.vocab.
    pub fn open(lib: &str, model: &str, threads: i32) -> Result<Punct, String> {
        for f in ["model.onnx", "bpe.vocab"] {
            if !std::path::Path::new(model).join(f).is_file() {
                return Err(format!("{model}/{f} is missing"));
            }
        }
        let library = unsafe { Library::new(lib) }.map_err(|e| format!("{lib}: {e}"))?;
        let create: Create = sym(&library, b"SherpaOnnxCreateOnlinePunctuation")?;
        let add: AddPunct = sym(&library, b"SherpaOnnxOnlinePunctuationAddPunct")?;
        let free: FreeText = sym(&library, b"SherpaOnnxOnlinePunctuationFreeText")?;
        let destroy: Destroy = sym(&library, b"SherpaOnnxDestroyOnlinePunctuation")?;
        let c = |s: String| CString::new(s).unwrap_or_default();
        let (model_file, vocab, cpu) = (c(format!("{model}/model.onnx")), c(format!("{model}/bpe.vocab")), c("cpu".into()));
        let config = Config {
            model: ModelConfig {
                cnn_bilstm: model_file.as_ptr(),
                bpe_vocab: vocab.as_ptr(),
                num_threads: threads,
                debug: 0,
                provider: cpu.as_ptr(),
            },
        };
        let punct = unsafe { create(&config) };
        if punct.is_null() {
            return Err(format!("the punctuation model in {model} did not load"));
        }
        Ok(Punct {
            _lib: library,
            punct,
            add,
            free,
            destroy,
        })
    }

    /// The same words with capitals and marks; the text itself when the model cannot read it.
    pub fn add(&self, text: &str) -> String {
        let Ok(input) = CString::new(text) else { return text.to_string() };
        unsafe {
            let out = (self.add)(self.punct, input.as_ptr());
            if out.is_null() {
                return text.to_string();
            }
            let said = CStr::from_ptr(out).to_string_lossy().into_owned();
            (self.free)(out);
            said
        }
    }
}

impl Drop for Punct {
    fn drop(&mut self) {
        unsafe { (self.destroy)(self.punct) }
    }
}
