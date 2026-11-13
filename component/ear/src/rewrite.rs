//! The pass that rewrites the line when you stop speaking: sherpa-onnx's offline recognizer over the whole
//! utterance, which hears names and whole sentences better than a streaming model can and writes its own
//! punctuation. The structs mirror c-api.h of the pinned release.

use libloading::{Library, Symbol};
use std::ffi::{c_char, c_float, c_int, c_void, CStr, CString};

#[repr(C)]
struct Transducer {
    encoder: *const c_char,
    decoder: *const c_char,
    joiner: *const c_char,
}
#[repr(C)]
struct OneFile {
    model: *const c_char,
}
#[repr(C)]
struct Paraformer {
    model: *const c_char,
}
#[repr(C)]
struct Whisper {
    encoder: *const c_char,
    decoder: *const c_char,
    language: *const c_char,
    task: *const c_char,
    tail_paddings: c_int,
    enable_token_timestamps: c_int,
    enable_segment_timestamps: c_int,
}
#[repr(C)]
struct SenseVoice {
    model: *const c_char,
    language: *const c_char,
    use_itn: c_int,
}
#[repr(C)]
struct Moonshine {
    preprocessor: *const c_char,
    encoder: *const c_char,
    uncached_decoder: *const c_char,
    cached_decoder: *const c_char,
    merged_decoder: *const c_char,
}
#[repr(C)]
struct TwoFiles {
    encoder: *const c_char,
    decoder: *const c_char,
}
#[repr(C)]
struct Canary {
    encoder: *const c_char,
    decoder: *const c_char,
    src_lang: *const c_char,
    tgt_lang: *const c_char,
    use_pnc: c_int,
}
#[repr(C)]
struct FunAsrNano {
    encoder_adaptor: *const c_char,
    llm: *const c_char,
    embedding: *const c_char,
    tokenizer: *const c_char,
    system_prompt: *const c_char,
    user_prompt: *const c_char,
    max_new_tokens: c_int,
    temperature: c_float,
    top_p: c_float,
    seed: c_int,
    language: *const c_char,
    itn: c_int,
    hotwords: *const c_char,
}
#[repr(C)]
struct Qwen3Asr {
    conv_frontend: *const c_char,
    encoder: *const c_char,
    decoder: *const c_char,
    tokenizer: *const c_char,
    max_total_len: c_int,
    max_new_tokens: c_int,
    temperature: c_float,
    top_p: c_float,
    seed: c_int,
    hotwords: *const c_char,
}
#[repr(C)]
struct CohereTranscribe {
    encoder: *const c_char,
    decoder: *const c_char,
    language: *const c_char,
    use_punct: c_int,
    use_itn: c_int,
}
#[repr(C)]
struct ModelConfig {
    transducer: Transducer,
    paraformer: Paraformer,
    nemo_ctc: OneFile,
    whisper: Whisper,
    tdnn: OneFile,
    tokens: *const c_char,
    num_threads: c_int,
    debug: c_int,
    provider: *const c_char,
    model_type: *const c_char,
    modeling_unit: *const c_char,
    bpe_vocab: *const c_char,
    telespeech_ctc: *const c_char,
    sense_voice: SenseVoice,
    moonshine: Moonshine,
    fire_red_asr: TwoFiles,
    dolphin: OneFile,
    zipformer_ctc: OneFile,
    canary: Canary,
    wenet_ctc: OneFile,
    omnilingual: OneFile,
    medasr: OneFile,
    funasr_nano: FunAsrNano,
    fire_red_asr_ctc: OneFile,
    qwen3_asr: Qwen3Asr,
    cohere_transcribe: CohereTranscribe,
}
#[repr(C)]
struct FeatureConfig {
    sample_rate: c_int,
    feature_dim: c_int,
}
#[repr(C)]
struct LmConfig {
    model: *const c_char,
    scale: c_float,
}
#[repr(C)]
struct Homophone {
    dict_dir: *const c_char,
    lexicon: *const c_char,
    rule_fsts: *const c_char,
}
#[repr(C)]
struct CtcFstDecoder {
    graph: *const c_char,
    max_active: c_int,
}
#[repr(C)]
struct RecognizerConfig {
    feat_config: FeatureConfig,
    model_config: ModelConfig,
    lm_config: LmConfig,
    decoding_method: *const c_char,
    max_active_paths: c_int,
    hotwords_file: *const c_char,
    hotwords_score: c_float,
    rule_fsts: *const c_char,
    rule_fars: *const c_char,
    blank_penalty: c_float,
    hr: Homophone,
    ctc_fst_decoder_config: CtcFstDecoder,
}
#[repr(C)]
struct Result_ {
    text: *const c_char,
    timestamps: *mut c_float,
    count: c_int,
    tokens: *const c_char,
    tokens_arr: *const *const c_char,
    json: *const c_char,
}

type Create = unsafe extern "C" fn(*const RecognizerConfig) -> *const c_void;
type Destroy = unsafe extern "C" fn(*const c_void);
type NewStream = unsafe extern "C" fn(*const c_void) -> *const c_void;
type Accept = unsafe extern "C" fn(*const c_void, c_int, *const c_float, c_int);
type Decode = unsafe extern "C" fn(*const c_void, *const c_void);
type GetResult = unsafe extern "C" fn(*const c_void) -> *const Result_;
type FreeResult = unsafe extern "C" fn(*const Result_);

/// The model, loaded once; a pass runs when the person stops speaking.
pub struct Rewrite {
    _lib: Library,
    recognizer: *const c_void,
    new_stream: NewStream,
    destroy_stream: Destroy,
    accept: Accept,
    decode: Decode,
    result: GetResult,
    free_result: FreeResult,
    destroy: Destroy,
}

fn sym<T: Copy>(lib: &Library, name: &[u8]) -> Result<T, String> {
    let s: Symbol<T> = unsafe { lib.get(name) }.map_err(|_| format!("{} is missing from the engine's library", String::from_utf8_lossy(name)))?;
    Ok(*s)
}

impl Rewrite {
    /// `lib` is libsherpa-onnx-c-api.so, `model` the folder with the three int8 files and tokens.txt.
    pub fn open(lib: &str, model: &str, threads: i32) -> Result<Rewrite, String> {
        for f in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"] {
            if !std::path::Path::new(model).join(f).is_file() {
                return Err(format!("{model}/{f} is missing"));
            }
        }
        let library = unsafe { Library::new(lib) }.map_err(|e| format!("{lib}: {e}"))?;
        let create: Create = sym(&library, b"SherpaOnnxCreateOfflineRecognizer")?;
        let new_stream: NewStream = sym(&library, b"SherpaOnnxCreateOfflineStream")?;
        let destroy_stream: Destroy = sym(&library, b"SherpaOnnxDestroyOfflineStream")?;
        let accept: Accept = sym(&library, b"SherpaOnnxAcceptWaveformOffline")?;
        let decode: Decode = sym(&library, b"SherpaOnnxDecodeOfflineStream")?;
        let result: GetResult = sym(&library, b"SherpaOnnxGetOfflineStreamResult")?;
        let free_result: FreeResult = sym(&library, b"SherpaOnnxDestroyOfflineRecognizerResult")?;
        let destroy: Destroy = sym(&library, b"SherpaOnnxDestroyOfflineRecognizer")?;
        let c = |s: String| CString::new(s).unwrap_or_default();
        let (encoder, decoder, joiner, tokens) = (
            c(format!("{model}/encoder.int8.onnx")),
            c(format!("{model}/decoder.int8.onnx")),
            c(format!("{model}/joiner.int8.onnx")),
            c(format!("{model}/tokens.txt")),
        );
        let (empty, cpu, greedy, kind) = (c(String::new()), c("cpu".into()), c("greedy_search".into()), c("nemo_transducer".into()));
        let e = empty.as_ptr();
        let one = || OneFile { model: e };
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
                paraformer: Paraformer { model: e },
                nemo_ctc: one(),
                whisper: Whisper {
                    encoder: e,
                    decoder: e,
                    language: e,
                    task: e,
                    tail_paddings: 0,
                    enable_token_timestamps: 0,
                    enable_segment_timestamps: 0,
                },
                tdnn: one(),
                tokens: tokens.as_ptr(),
                num_threads: threads,
                debug: 0,
                provider: cpu.as_ptr(),
                model_type: kind.as_ptr(),
                modeling_unit: e,
                bpe_vocab: e,
                telespeech_ctc: e,
                sense_voice: SenseVoice {
                    model: e,
                    language: e,
                    use_itn: 0,
                },
                moonshine: Moonshine {
                    preprocessor: e,
                    encoder: e,
                    uncached_decoder: e,
                    cached_decoder: e,
                    merged_decoder: e,
                },
                fire_red_asr: TwoFiles { encoder: e, decoder: e },
                dolphin: one(),
                zipformer_ctc: one(),
                canary: Canary {
                    encoder: e,
                    decoder: e,
                    src_lang: e,
                    tgt_lang: e,
                    use_pnc: 0,
                },
                wenet_ctc: one(),
                omnilingual: one(),
                medasr: one(),
                funasr_nano: FunAsrNano {
                    encoder_adaptor: e,
                    llm: e,
                    embedding: e,
                    tokenizer: e,
                    system_prompt: e,
                    user_prompt: e,
                    max_new_tokens: 0,
                    temperature: 0.0,
                    top_p: 0.0,
                    seed: 0,
                    language: e,
                    itn: 0,
                    hotwords: e,
                },
                fire_red_asr_ctc: one(),
                qwen3_asr: Qwen3Asr {
                    conv_frontend: e,
                    encoder: e,
                    decoder: e,
                    tokenizer: e,
                    max_total_len: 0,
                    max_new_tokens: 0,
                    temperature: 0.0,
                    top_p: 0.0,
                    seed: 0,
                    hotwords: e,
                },
                cohere_transcribe: CohereTranscribe {
                    encoder: e,
                    decoder: e,
                    language: e,
                    use_punct: 0,
                    use_itn: 0,
                },
            },
            lm_config: LmConfig { model: e, scale: 0.0 },
            decoding_method: greedy.as_ptr(),
            max_active_paths: 4,
            hotwords_file: e,
            hotwords_score: 0.0,
            rule_fsts: e,
            rule_fars: e,
            blank_penalty: 0.0,
            hr: Homophone {
                dict_dir: e,
                lexicon: e,
                rule_fsts: e,
            },
            ctc_fst_decoder_config: CtcFstDecoder { graph: e, max_active: 0 },
        };
        let recognizer = unsafe { create(&config) };
        if recognizer.is_null() {
            return Err(format!("the model in {model} did not load"));
        }
        Ok(Rewrite {
            _lib: library,
            recognizer,
            new_stream,
            destroy_stream,
            accept,
            decode,
            result,
            free_result,
            destroy,
        })
    }

    /// The whole utterance read again: the text as this model hears it, with its own punctuation.
    pub fn text(&self, rate: u32, samples: &[f32]) -> String {
        unsafe {
            let stream = (self.new_stream)(self.recognizer);
            if stream.is_null() {
                return String::new();
            }
            (self.accept)(stream, rate as c_int, samples.as_ptr(), samples.len() as c_int);
            (self.decode)(self.recognizer, stream);
            let res = (self.result)(stream);
            let said = if res.is_null() {
                String::new()
            } else {
                let text = CStr::from_ptr((*res).text).to_string_lossy().trim().to_string();
                (self.free_result)(res);
                text
            };
            (self.destroy_stream)(stream);
            said
        }
    }
}

impl Drop for Rewrite {
    fn drop(&mut self) {
        unsafe { (self.destroy)(self.recognizer) }
    }
}
