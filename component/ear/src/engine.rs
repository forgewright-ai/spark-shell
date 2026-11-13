//! sherpa-onnx's streaming recognizer through its C API (v2.0.1), opened at run time: spark-shell fetches
//! the library and the model, both pinned. The structs mirror c-api.h.

use libloading::{Library, Symbol};
use std::ffi::{c_char, c_float, c_int, c_void, CStr, CString};

#[repr(C)]
struct Transducer {
    encoder: *const c_char,
    decoder: *const c_char,
    joiner: *const c_char,
}
#[repr(C)]
struct Paraformer {
    encoder: *const c_char,
    decoder: *const c_char,
}
#[repr(C)]
struct OneModel {
    model: *const c_char,
}
#[repr(C)]
struct ModelConfig {
    transducer: Transducer,
    paraformer: Paraformer,
    zipformer2_ctc: OneModel,
    tokens: *const c_char,
    num_threads: c_int,
    provider: *const c_char,
    debug: c_int,
    model_type: *const c_char,
    modeling_unit: *const c_char,
    bpe_vocab: *const c_char,
    tokens_buf: *const c_char,
    tokens_buf_size: c_int,
    nemo_ctc: OneModel,
    t_one_ctc: OneModel,
}
#[repr(C)]
struct FeatureConfig {
    sample_rate: c_int,
    feature_dim: c_int,
}
#[repr(C)]
struct CtcFstDecoder {
    graph: *const c_char,
    max_active: c_int,
}
#[repr(C)]
struct Homophone {
    dict_dir: *const c_char,
    lexicon: *const c_char,
    rule_fsts: *const c_char,
}
#[repr(C)]
struct RecognizerConfig {
    feat_config: FeatureConfig,
    model_config: ModelConfig,
    decoding_method: *const c_char,
    max_active_paths: c_int,
    enable_endpoint: c_int,
    rule1_min_trailing_silence: c_float,
    rule2_min_trailing_silence: c_float,
    rule3_min_utterance_length: c_float,
    hotwords_file: *const c_char,
    hotwords_score: c_float,
    ctc_fst_decoder_config: CtcFstDecoder,
    rule_fsts: *const c_char,
    rule_fars: *const c_char,
    blank_penalty: c_float,
    hotwords_buf: *const c_char,
    hotwords_buf_size: c_int,
    hr: Homophone,
}
#[repr(C)]
struct RecognizerResult {
    text: *const c_char,
    tokens: *const c_char,
    tokens_arr: *const *const c_char,
    timestamps: *mut c_float,
    count: c_int,
    json: *const c_char,
}

type Create = unsafe extern "C" fn(*const RecognizerConfig) -> *const c_void;
type Destroy = unsafe extern "C" fn(*const c_void);
type NewStream = unsafe extern "C" fn(*const c_void) -> *const c_void;
type Accept = unsafe extern "C" fn(*const c_void, c_int, *const c_float, c_int);
type Ready = unsafe extern "C" fn(*const c_void, *const c_void) -> c_int;
type Decode = unsafe extern "C" fn(*const c_void, *const c_void);
type GetResult = unsafe extern "C" fn(*const c_void, *const c_void) -> *const RecognizerResult;
type FreeResult = unsafe extern "C" fn(*const RecognizerResult);
type IsEndpoint = unsafe extern "C" fn(*const c_void, *const c_void) -> c_int;
type Reset = unsafe extern "C" fn(*const c_void, *const c_void);
type Finished = unsafe extern "C" fn(*const c_void);

struct Api {
    _lib: Library,
    create: Create,
    destroy: Destroy,
    new_stream: NewStream,
    destroy_stream: Destroy,
    accept: Accept,
    ready: Ready,
    decode: Decode,
    result: GetResult,
    free_result: FreeResult,
    is_endpoint: IsEndpoint,
    reset: Reset,
    finished: Finished,
}

fn sym<T: Copy>(lib: &Library, name: &[u8]) -> Result<T, String> {
    let s: Symbol<T> = unsafe { lib.get(name) }.map_err(|_| format!("{} is missing from the engine's library", String::from_utf8_lossy(name)))?;
    Ok(*s)
}

/// The recognizer: the model loaded once, streams made from it.
pub struct Engine {
    api: Api,
    recognizer: *const c_void,
}

/// One stream of sound to the recognizer, the text it carries so far.
pub struct Stream<'a> {
    engine: &'a Engine,
    stream: *const c_void,
}

impl Engine {
    /// `lib` is libsherpa-onnx-c-api.so, `model` the folder with encoder.int8.onnx, decoder.int8.onnx,
    /// joiner.int8.onnx and tokens.txt.
    pub fn open(lib: &str, model: &str, threads: i32) -> Result<Engine, String> {
        let library = unsafe { Library::new(lib) }.map_err(|e| format!("{lib}: {e}"))?;
        let api = Api {
            create: sym(&library, b"SherpaOnnxCreateOnlineRecognizer")?,
            destroy: sym(&library, b"SherpaOnnxDestroyOnlineRecognizer")?,
            new_stream: sym(&library, b"SherpaOnnxCreateOnlineStream")?,
            destroy_stream: sym(&library, b"SherpaOnnxDestroyOnlineStream")?,
            accept: sym(&library, b"SherpaOnnxOnlineStreamAcceptWaveform")?,
            ready: sym(&library, b"SherpaOnnxIsOnlineStreamReady")?,
            decode: sym(&library, b"SherpaOnnxDecodeOnlineStream")?,
            result: sym(&library, b"SherpaOnnxGetOnlineStreamResult")?,
            free_result: sym(&library, b"SherpaOnnxDestroyOnlineRecognizerResult")?,
            is_endpoint: sym(&library, b"SherpaOnnxOnlineStreamIsEndpoint")?,
            reset: sym(&library, b"SherpaOnnxOnlineStreamReset")?,
            finished: sym(&library, b"SherpaOnnxOnlineStreamInputFinished")?,
            _lib: library,
        };
        for f in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"] {
            if !std::path::Path::new(model).join(f).is_file() {
                return Err(format!("{model}/{f} is missing"));
            }
        }
        let c = |s: String| CString::new(s).unwrap_or_default();
        let (encoder, decoder, joiner, tokens) = (
            c(format!("{model}/encoder.int8.onnx")),
            c(format!("{model}/decoder.int8.onnx")),
            c(format!("{model}/joiner.int8.onnx")),
            c(format!("{model}/tokens.txt")),
        );
        let (empty, cpu, greedy) = (c(String::new()), c("cpu".into()), c("greedy_search".into()));
        let one = OneModel { model: empty.as_ptr() };
        let config = RecognizerConfig {
            feat_config: FeatureConfig {
                sample_rate: 16000,
                feature_dim: 80,
            },
            model_config: ModelConfig {
                transducer: Transducer {
                    encoder: encoder.as_ptr(),
                    decoder: decoder.as_ptr(),
                    joiner: joiner.as_ptr(),
                },
                paraformer: Paraformer {
                    encoder: empty.as_ptr(),
                    decoder: empty.as_ptr(),
                },
                zipformer2_ctc: OneModel { model: empty.as_ptr() },
                tokens: tokens.as_ptr(),
                num_threads: threads,
                provider: cpu.as_ptr(),
                debug: 0,
                model_type: empty.as_ptr(),
                modeling_unit: empty.as_ptr(),
                bpe_vocab: empty.as_ptr(),
                tokens_buf: empty.as_ptr(),
                tokens_buf_size: 0,
                nemo_ctc: OneModel { model: empty.as_ptr() },
                t_one_ctc: one,
            },
            decoding_method: greedy.as_ptr(),
            max_active_paths: 4,
            enable_endpoint: 1,
            // a pause ends an utterance: 2.4 s of silence before any word, 1.2 s after words, or 20 s spoken
            rule1_min_trailing_silence: 2.4,
            rule2_min_trailing_silence: 1.2,
            rule3_min_utterance_length: 20.0,
            hotwords_file: empty.as_ptr(),
            hotwords_score: 0.0,
            ctc_fst_decoder_config: CtcFstDecoder {
                graph: empty.as_ptr(),
                max_active: 0,
            },
            rule_fsts: empty.as_ptr(),
            rule_fars: empty.as_ptr(),
            blank_penalty: 0.0,
            hotwords_buf: empty.as_ptr(),
            hotwords_buf_size: 0,
            hr: Homophone {
                dict_dir: empty.as_ptr(),
                lexicon: empty.as_ptr(),
                rule_fsts: empty.as_ptr(),
            },
        };
        let recognizer = unsafe { (api.create)(&config) };
        if recognizer.is_null() {
            return Err(format!("the model in {model} did not load"));
        }
        Ok(Engine { api, recognizer })
    }

    pub fn stream(&self) -> Stream<'_> {
        Stream {
            engine: self,
            stream: unsafe { (self.api.new_stream)(self.recognizer) },
        }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        unsafe { (self.api.destroy)(self.recognizer) }
    }
}

impl Stream<'_> {
    /// Sound in, at its rate (the engine resamples), decoded as far as it goes.
    pub fn feed(&self, rate: u32, samples: &[f32]) {
        let (api, r, s) = (&self.engine.api, self.engine.recognizer, self.stream);
        unsafe {
            (api.accept)(s, rate as c_int, samples.as_ptr(), samples.len() as c_int);
            while (api.ready)(r, s) != 0 {
                (api.decode)(r, s);
            }
        }
    }

    /// The text of the utterance so far.
    pub fn text(&self) -> String {
        let (api, r, s) = (&self.engine.api, self.engine.recognizer, self.stream);
        unsafe {
            let res = (api.result)(r, s);
            if res.is_null() {
                return String::new();
            }
            let text = CStr::from_ptr((*res).text).to_string_lossy().trim().to_string();
            (api.free_result)(res);
            text
        }
    }

    /// A pause ended the utterance: true once, and the stream starts over.
    pub fn ended(&self) -> bool {
        let (api, r, s) = (&self.engine.api, self.engine.recognizer, self.stream);
        unsafe {
            if (api.is_endpoint)(r, s) != 0 {
                (api.reset)(r, s);
                return true;
            }
        }
        false
    }

    /// No more sound comes: what is left decodes.
    pub fn finish(&self) {
        let (api, r, s) = (&self.engine.api, self.engine.recognizer, self.stream);
        unsafe {
            (api.finished)(s);
            while (api.ready)(r, s) != 0 {
                (api.decode)(r, s);
            }
        }
    }
}

impl Drop for Stream<'_> {
    fn drop(&mut self) {
        unsafe { (self.engine.api.destroy_stream)(self.stream) }
    }
}
