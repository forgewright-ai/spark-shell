//! spark-ear: spark-shell's ear. The microphone's sound to the words spoken, as they are spoken, on stdout:
//! `level N` ten times a second, `type TEXT` and `erase N` as the words come. The pure parts: level, words,
//! wav. At run time: the microphone (ALSA) and the engine (sherpa-onnx), both opened as libraries.

pub mod level;
pub mod wav;
pub mod words;

#[cfg(target_os = "linux")]
pub mod alsa;
#[cfg(target_os = "linux")]
pub mod engine;
