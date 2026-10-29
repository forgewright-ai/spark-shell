//! The one model helper the dialog runs: spark steps, the tools on its stdin.

use crate::scrub::scrub;
use serde_json::Value;

/// The local civil time with its zone, for what the caller knows now.
pub fn clock() -> String {
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        let mut b = [0u8; 64];
        let n = libc::strftime(b.as_mut_ptr().cast(), b.len(), c"%Y-%m-%dT%H:%M:%S%z %Z".as_ptr(), &tm);
        String::from_utf8_lossy(&b[..n]).into_owned()
    }
}

/// A model helper receives JSON on stdin, never in argv or a temporary file.
/// Bound input, output and lifetime. Killing this helper cannot cancel an OS
/// write: it only proposes actions, which the host executes separately.
pub fn invoke(argv: &[String], input: String) -> Result<String, String> {
    use std::io::{Read, Write};
    use std::os::unix::process::CommandExt;
    use std::process::{Command, Stdio};
    use std::sync::mpsc;
    use std::time::{Duration, Instant};
    const MAX: u64 = 262144;
    if input.len() > MAX as usize {
        return Err("the request exceeds 256 kB".into());
    }
    let Some((cmd, args)) = argv.split_first() else {
        return Err("no spark executable".into());
    };
    let mut child = Command::new(cmd)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .map_err(|e| e.to_string())?;
    let pid = child.id();
    let mut stdin = child.stdin.take().ok_or("no input pipe")?;
    let stdout = child.stdout.take().ok_or("no output pipe")?;
    let stderr = child.stderr.take().ok_or("no error pipe")?;
    let (tx, rx) = mpsc::channel();
    let t = tx.clone();
    std::thread::spawn(move || {
        let _ = t.send((0, stdin.write_all(input.as_bytes()).map(|_| vec![])));
    });
    let t = tx.clone();
    std::thread::spawn(move || {
        let mut b = vec![];
        let r = stdout.take(MAX + 1).read_to_end(&mut b).map(|_| b);
        let _ = t.send((1, r));
    });
    std::thread::spawn(move || {
        let mut b = vec![];
        let r = stderr.take(MAX + 1).read_to_end(&mut b).map(|_| b);
        let _ = tx.send((2, r));
    });
    let deadline = Instant::now() + Duration::from_secs(75);
    let mut parts: [Option<Vec<u8>>; 3] = [None, None, None];
    let result = (|| loop {
        while let Ok((i, r)) = rx.try_recv() {
            let bytes = r.map_err(|e| e.to_string())?;
            if bytes.len() > MAX as usize {
                return Err("the answer exceeds 256 kB".into());
            }
            parts[i] = Some(bytes);
        }
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            if parts.iter().all(Option::is_some) {
                let out = String::from_utf8_lossy(parts[1].as_ref().unwrap()).into_owned();
                if status.success() || serde_json::from_str::<Value>(&out).is_ok() {
                    return Ok(out);
                }
                return Err(scrub(&String::from_utf8_lossy(parts[2].as_ref().unwrap())));
            }
        }
        if Instant::now() >= deadline {
            return Err("spark did not answer within 75 seconds".into());
        }
        std::thread::sleep(Duration::from_millis(10));
    })();
    unsafe {
        libc::kill(-(pid as libc::pid_t), libc::SIGKILL);
    }
    let _ = child.wait();
    result
}
