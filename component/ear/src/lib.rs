//! spark-ear: spark-shell's ear. The microphone's sound to the words spoken, as they are spoken, on stdout:
//! `level N` ten times a second, `type TEXT` and `erase N` as the words come. The pure parts: level, words,
//! wav. At run time: the microphone (ALSA) and three faces of sherpa-onnx, each opened as a library -- the
//! streaming engine, the punctuation the words wear while they are spoken, and the pass that rewrites the
//! line when the speaking stops.

pub mod level;
pub mod wav;
pub mod words;

#[cfg(target_os = "linux")]
pub mod alsa;
#[cfg(target_os = "linux")]
pub mod engine;
#[cfg(target_os = "linux")]
pub mod punct;
#[cfg(target_os = "linux")]
pub mod rewrite;
