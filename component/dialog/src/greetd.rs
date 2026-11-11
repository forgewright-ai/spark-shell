//! greetd's IPC, as the login screen speaks it: each message is a u32
//! length in the machine's byte order, then that many bytes of JSON, on
//! the socket greetd names in GREETD_SOCK. The password only ever lives
//! in a Secret, and the one message that carries it is zeroed after it
//! is written.

use serde_json::{json, Value};
use std::io::{Read, Write};

/// The most a message from greetd may be: an answer is a few hundred bytes.
const MOST: u32 = 64 * 1024;
/// The most a password may be, in bytes: room is kept for it up front, so it is never moved.
pub const SECRET_MOST: usize = 255;

/// A password: its bytes are overwritten with zeros when it is cleared,
/// when a character is taken off and when it is dropped. It has no Debug
/// and no Display, so it cannot reach a log or an error by accident.
pub struct Secret {
    bytes: Vec<u8>,
    chars: usize,
}

impl Default for Secret {
    fn default() -> Self {
        Secret::new()
    }
}

impl Secret {
    pub fn new() -> Secret {
        Secret {
            bytes: Vec::with_capacity(SECRET_MOST + 4),
            chars: 0,
        }
    }
    /// A character on the end; false (nothing added) when it would pass SECRET_MOST.
    pub fn push(&mut self, c: char) -> bool {
        let mut b = [0u8; 4];
        let s = c.encode_utf8(&mut b);
        if self.bytes.len() + s.len() > SECRET_MOST {
            wipe(&mut b);
            return false;
        }
        self.bytes.extend_from_slice(s.as_bytes());
        wipe(&mut b);
        self.chars += 1;
        true
    }
    /// The last character off, its bytes zeroed.
    pub fn pop(&mut self) {
        let mut n = self.bytes.len();
        while n > 0 {
            n -= 1;
            if self.bytes[n] & 0xc0 != 0x80 {
                break;
            }
        }
        if self.bytes.len() > n {
            wipe(&mut self.bytes[n..]);
            self.bytes.truncate(n);
            self.chars -= 1;
        }
    }
    pub fn clear(&mut self) {
        wipe(&mut self.bytes);
        self.bytes.clear();
        self.chars = 0;
    }
    /// How many characters: the dots drawn.
    pub fn len(&self) -> usize {
        self.chars
    }
    pub fn is_empty(&self) -> bool {
        self.chars == 0
    }
    /// The bytes themselves, for the one message that carries them (and the tests).
    pub fn expose(&self) -> &[u8] {
        &self.bytes
    }
}

impl Drop for Secret {
    fn drop(&mut self) {
        self.clear();
    }
}

/// Zeros over the bytes, written so the compiler keeps them.
pub fn wipe(b: &mut [u8]) {
    for x in b.iter_mut() {
        unsafe { std::ptr::write_volatile(x, 0) };
    }
    std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
}

/// One message on the stream: its length, then its bytes.
pub fn send(s: &mut impl Write, msg: &[u8]) -> std::io::Result<()> {
    let n = u32::try_from(msg.len()).map_err(|_| std::io::Error::other("a message too long"))?;
    s.write_all(&n.to_ne_bytes())?;
    s.write_all(msg)?;
    s.flush()
}

/// One message off the stream, as JSON.
pub fn recv(s: &mut impl Read) -> std::io::Result<Value> {
    let mut n = [0u8; 4];
    s.read_exact(&mut n)?;
    let n = u32::from_ne_bytes(n);
    if n > MOST {
        return Err(std::io::Error::other("greetd sent a message too long"));
    }
    let mut b = vec![0u8; n as usize];
    s.read_exact(&mut b)?;
    serde_json::from_slice(&b).map_err(|_| std::io::Error::other("greetd sent something that is not JSON"))
}

fn send_json(s: &mut impl Write, v: Value) -> std::io::Result<()> {
    send(s, v.to_string().as_bytes())
}

/// The answer to a secret prompt, the password written into the JSON by
/// hand so no copy of it is left behind: the buffer is zeroed after it
/// is sent, sent or not.
fn send_secret(s: &mut impl Write, pass: &Secret) -> std::io::Result<()> {
    let mut b: Vec<u8> = Vec::with_capacity(64 + pass.expose().len() * 6);
    b.extend_from_slice(b"{\"type\":\"post_auth_message_response\",\"response\":\"");
    for &x in pass.expose() {
        match x {
            b'"' => b.extend_from_slice(b"\\\""),
            b'\\' => b.extend_from_slice(b"\\\\"),
            0..=0x1f => {
                let hexd = b"0123456789abcdef";
                b.extend_from_slice(b"\\u00");
                b.push(hexd[(x >> 4) as usize]);
                b.push(hexd[(x & 15) as usize]);
            }
            _ => b.push(x),
        }
    }
    b.extend_from_slice(b"\"}");
    let r = send(s, &b);
    wipe(&mut b);
    r
}

/// How a login ended.
#[derive(Debug, PartialEq)]
pub enum Outcome {
    /// greetd starts the session once the login screen exits.
    Started,
    /// The user name or the password is wrong (greetd does not say which).
    Wrong,
    /// The account asks for more than one password (a code, a second factor).
    More,
    /// Anything else, greetd's words.
    Failed(String),
}

fn kind(v: &Value) -> &str {
    v.get("type").and_then(Value::as_str).unwrap_or("")
}

fn words(v: &Value, key: &str) -> String {
    let t = v.get(key).and_then(Value::as_str).unwrap_or("").trim();
    if t.is_empty() {
        "greetd gave no reason".into()
    } else {
        crate::scrub::scrub(t)
    }
}

/// The session is cancelled after any refusal, its answer read and dropped.
fn cancel(s: &mut (impl Read + Write)) {
    if send_json(s, json!({"type": "cancel_session"})).is_ok() {
        let _ = recv(s);
    }
}

/// The whole login on one connection: create the session, answer the one
/// password prompt, start `cmd` with `env`.
pub fn log_in(s: &mut (impl Read + Write), user: &str, pass: &Secret, cmd: &[String], env: &[String]) -> Outcome {
    let io = |e: std::io::Error| Outcome::Failed(format!("greetd: {}", e));
    if let Err(e) = send_json(s, json!({"type": "create_session", "username": user})) {
        return io(e);
    }
    let mut answered = false;
    loop {
        let v = match recv(s) {
            Ok(v) => v,
            Err(e) => return io(e),
        };
        match kind(&v) {
            "success" => break,
            "auth_message" => match v.get("auth_message_type").and_then(Value::as_str).unwrap_or("") {
                "secret" if !answered => {
                    answered = true;
                    if let Err(e) = send_secret(s, pass) {
                        return io(e);
                    }
                }
                "info" | "error" => {
                    if let Err(e) = send_json(s, json!({"type": "post_auth_message_response", "response": null})) {
                        return io(e);
                    }
                }
                _ => {
                    cancel(s);
                    return Outcome::More;
                }
            },
            "error" => {
                cancel(s);
                if v.get("error_type").and_then(Value::as_str) == Some("auth_error") {
                    return Outcome::Wrong;
                }
                return Outcome::Failed(words(&v, "description"));
            }
            _ => {
                cancel(s);
                return Outcome::Failed("greetd sent an answer this login does not know".into());
            }
        }
    }
    if let Err(e) = send_json(s, json!({"type": "start_session", "cmd": cmd, "env": env})) {
        return io(e);
    }
    match recv(s) {
        Ok(v) if kind(&v) == "success" => Outcome::Started,
        Ok(v) => {
            cancel(s);
            Outcome::Failed(words(&v, "description"))
        }
        Err(e) => io(e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_message_goes_and_comes_back_whole() {
        let mut b = vec![];
        send(&mut b, br#"{"type":"success"}"#).unwrap();
        assert_eq!(&b[..4], &18u32.to_ne_bytes());
        let v = recv(&mut &b[..]).unwrap();
        assert_eq!(v["type"], "success");
    }

    #[test]
    fn a_message_too_long_is_refused() {
        let mut b = (MOST + 1).to_ne_bytes().to_vec();
        b.extend_from_slice(b"{}");
        assert!(recv(&mut &b[..]).is_err());
    }

    #[test]
    fn the_secret_takes_characters_off_and_zeroes() {
        let mut p = Secret::new();
        for c in "p\u{e4}\"ss".chars() {
            assert!(p.push(c));
        }
        assert_eq!(p.len(), 5);
        p.pop();
        assert_eq!(p.expose(), "p\u{e4}\"s".as_bytes());
        p.pop();
        p.pop();
        assert_eq!(p.expose(), "p\u{e4}".as_bytes());
        let ptr = p.bytes.as_ptr();
        let cap = p.bytes.capacity();
        p.clear();
        assert!(p.is_empty());
        // the bytes that held the password are zeros now (the buffer was never moved)
        let raw = unsafe { std::slice::from_raw_parts(ptr, 3) };
        assert_eq!(raw, &[0, 0, 0]);
        assert_eq!(p.bytes.capacity(), cap);
    }

    #[test]
    fn the_secret_stops_at_its_size() {
        let mut p = Secret::new();
        for _ in 0..SECRET_MOST {
            assert!(p.push('a'));
        }
        assert!(!p.push('a'));
        assert_eq!(p.len(), SECRET_MOST);
    }

    #[test]
    fn the_answer_is_json_with_the_password_escaped() {
        let mut p = Secret::new();
        for c in "a\"b\\c\u{1}".chars() {
            p.push(c);
        }
        let mut b = vec![];
        send_secret(&mut b, &p).unwrap();
        let v = recv(&mut &b[..]).unwrap();
        assert_eq!(v["type"], "post_auth_message_response");
        assert_eq!(v["response"], "a\"b\\c\u{1}");
    }
}
