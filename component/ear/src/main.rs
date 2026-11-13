//! spark-ear: the microphone's sound to the words spoken, on stdout, until stdin closes (the leash), a
//! signal, the time cap, or the end of a wav file given in the microphone's place. Run by spark-shell.
//!
//! The lines: `level N` (0 to 7) ten times a second from the first sound, and as words come `type TEXT` and
//! `erase N`, so the reader keeps a line that reads as the words heard. Exit 0 when words came, 1 when none,
//! 2 when it cannot listen, the reason on stderr.
//!
//! With EAR_PUNCT the words wear capitals and marks while they are spoken, and with EAR_REWRITE the whole
//! utterance is read again when the speaking stops and the line is rewritten to what that model hears.

use std::process::ExitCode;

const USAGE: &str = "spark-ear -- the microphone's sound to the words spoken, as they are spoken (run by spark-shell)

  spark-ear [--from WAV] [--device NAME] [--max SECONDS]
  spark-ear --help | --version

  --from WAV      a wav file in the microphone's place, at its own pace
  --device NAME   the ALSA device (default)
  --max SECONDS   the most to listen (60)

The engine: EAR_LIB names libsherpa-onnx-c-api.so, EAR_MODEL its model's folder, EAR_THREADS its threads (1).
EAR_PUNCT names the punctuation model's folder, EAR_REWRITE the folder of the model that rewrites the line when
the speaking stops. Each is left out when unset.
";

struct Ask {
    from: Option<String>,
    device: String,
    max: u64,
}

fn parse(args: &[String]) -> Result<Option<Ask>, String> {
    let mut ask = Ask {
        from: None,
        device: "default".into(),
        max: 60,
    };
    let mut i = 0;
    while i < args.len() {
        let next = |i: usize| args.get(i + 1).cloned().ok_or_else(|| format!("{} takes a value", args[i]));
        match args[i].as_str() {
            "--help" | "-h" => {
                print!("{USAGE}");
                return Ok(None);
            }
            "--version" => {
                println!("spark-ear {}", env!("CARGO_PKG_VERSION"));
                return Ok(None);
            }
            "--from" => {
                ask.from = Some(next(i)?);
                i += 1;
            }
            "--device" => {
                ask.device = next(i)?;
                i += 1;
            }
            "--max" => {
                ask.max = next(i)?.parse().map_err(|_| "--max takes whole seconds".to_string())?;
                i += 1;
            }
            a => return Err(format!("unknown argument {a:?}")),
        }
        i += 1;
    }
    Ok(Some(ask))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match parse(&args) {
        Ok(None) => ExitCode::SUCCESS,
        Ok(Some(ask)) => match listen::run(ask) {
            Ok(true) => ExitCode::SUCCESS,
            Ok(false) => ExitCode::from(1),
            Err(e) => {
                eprintln!("spark-ear: {e}");
                ExitCode::from(2)
            }
        },
        Err(e) => {
            eprintln!("spark-ear: {e}\n\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

#[cfg(not(target_os = "linux"))]
mod listen {
    pub fn run(_: super::Ask) -> Result<bool, String> {
        Err("the ear listens on Linux only".into())
    }
}

#[cfg(target_os = "linux")]
mod listen {
    use super::Ask;
    use spark_ear::{alsa, engine::Engine, level::level, punct::Punct, rewrite::Rewrite, wav::Wav, words};
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::mpsc::{channel, RecvTimeoutError};
    use std::time::{Duration, Instant};

    static STOP: AtomicBool = AtomicBool::new(false);

    extern "C" fn stop(_: libc::c_int) {
        STOP.store(true, Ordering::SeqCst);
    }

    enum Source {
        Mic(alsa::Mic),
        File(Wav, Instant),
    }

    impl Source {
        fn rate(&self) -> u32 {
            match self {
                Source::Mic(_) => alsa::RATE,
                Source::File(w, _) => w.rate(),
            }
        }

        /// A tenth of a second of sound; None at the end. A file is read at its own pace.
        fn block(&mut self, n: usize, out: &mut Vec<i16>) -> Result<bool, String> {
            out.resize(n, 0);
            match self {
                Source::Mic(m) => {
                    let got = m.read(out)?;
                    out.truncate(got);
                    Ok(true)
                }
                Source::File(w, at) => {
                    let got = w.read(out);
                    out.truncate(got);
                    if got == 0 {
                        return Ok(false);
                    }
                    *at += Duration::from_millis(100);
                    if let Some(wait) = at.checked_duration_since(Instant::now()) {
                        std::thread::sleep(wait);
                    }
                    Ok(true)
                }
            }
        }
    }

    /// The words with their marks, where a punctuation model is loaded: the word still being spoken is left
    /// alone, since marking half a word only to take the mark back makes the line jump.
    fn marked(punct: &Option<Punct>, text: &str) -> String {
        let Some(p) = punct else { return text.to_string() };
        match text.rfind(' ') {
            Some(at) if at > 0 => format!("{}{}", p.add(&text[..at]), &text[at..]),
            _ => text.to_string(),
        }
    }

    pub fn run(ask: Ask) -> Result<bool, String> {
        let lib = std::env::var("EAR_LIB").map_err(|_| "EAR_LIB names no engine library".to_string())?;
        let model = std::env::var("EAR_MODEL").map_err(|_| "EAR_MODEL names no model folder".to_string())?;
        let threads: i32 = std::env::var("EAR_THREADS").ok().and_then(|t| t.parse().ok()).unwrap_or(1);
        let mut source = match &ask.from {
            Some(path) => Source::File(Wav::open(path)?, Instant::now()),
            None => Source::Mic(alsa::Mic::open(&ask.device).map_err(|e| format!("no microphone: {e}"))?),
        };
        let handler = stop as *const () as libc::sighandler_t;
        unsafe {
            libc::signal(libc::SIGTERM, handler);
            libc::signal(libc::SIGINT, handler);
            libc::signal(libc::SIGHUP, handler);
        }
        // the leash: stdin's end stops the ear
        std::thread::spawn(|| {
            let mut sink = [0u8; 256];
            while matches!(std::io::Read::read(&mut std::io::stdin(), &mut sink), Ok(n) if n > 0) {}
            STOP.store(true, Ordering::SeqCst);
        });
        // the sound is taken from the first moment, while the engine loads; its level said at once
        let rate = source.rate();
        let (tx, rx) = channel::<Vec<i16>>();
        let start = Instant::now();
        let max = Duration::from_secs(ask.max);
        std::thread::spawn(move || {
            let mut block = Vec::new();
            while !STOP.load(Ordering::SeqCst) && start.elapsed() < max {
                match source.block(rate as usize / 10, &mut block) {
                    Ok(true) => {
                        println!("level {}", level(&block));
                        if tx.send(block.clone()).is_err() {
                            break;
                        }
                    }
                    Ok(false) => break,
                    Err(e) => {
                        eprintln!("spark-ear: {e}");
                        break;
                    }
                }
            }
            drop(tx);
        });
        let engine = Engine::open(&lib, &model, threads).map_err(|e| format!("no engine: {e}"))?;
        // the marks while speaking, and the better read when it stops: each only where spark-shell named one
        let punct = match std::env::var("EAR_PUNCT") {
            Ok(dir) if !dir.is_empty() => Some(Punct::open(&lib, &dir, threads).map_err(|e| format!("no punctuation: {e}"))?),
            _ => None,
        };
        let rewrite = match std::env::var("EAR_REWRITE") {
            Ok(dir) if !dir.is_empty() => Some(Rewrite::open(&lib, &dir, threads).map_err(|e| format!("no rewrite: {e}"))?),
            _ => None,
        };
        let mut heard: Vec<f32> = vec![];
        let stream = engine.stream();
        let mut said = words::Text::default();
        let mut typed = String::new();
        let say = |now: &str, typed: &mut String| {
            for line in words::lines(typed, now) {
                println!("{line}");
            }
            *typed = now.to_string();
        };
        loop {
            match rx.recv_timeout(Duration::from_millis(200)) {
                Ok(block) => {
                    let samples: Vec<f32> = block.iter().map(|&s| f32::from(s) / 32768.0).collect();
                    stream.feed(rate, &samples);
                    if rewrite.is_some() {
                        heard.extend_from_slice(&samples);
                    }
                    let current = stream.text();
                    say(&marked(&punct, &said.now(&current)), &mut typed);
                    if stream.ended() {
                        said.end(&current);
                    }
                }
                Err(RecvTimeoutError::Timeout) => {
                    if STOP.load(Ordering::SeqCst) {
                        break;
                    }
                }
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
        stream.finish();
        say(&marked(&punct, &said.now(&stream.text())), &mut typed);
        // the line as the other model hears the whole of it; its own marks, so the punctuation model stands aside
        if let (Some(r), false) = (&rewrite, heard.is_empty()) {
            let again = r.text(rate, &heard);
            if !again.is_empty() {
                say(&again, &mut typed);
            }
        }
        Ok(!typed.trim().is_empty())
    }
}
