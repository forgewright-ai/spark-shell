//! sway's IPC: the tree, a command, the outputs, and the window events, over SWAYSOCK.

use serde_json::Value;
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

const MAGIC: &[u8; 6] = b"i3-ipc";
pub const RUN_COMMAND: u32 = 0;
pub const SUBSCRIBE: u32 = 2;
pub const GET_OUTPUTS: u32 = 3;
pub const GET_TREE: u32 = 4;
/// An event's type: the high bit and the event's number.
pub const EVENT_WORKSPACE: u32 = 0x8000_0000;
pub const EVENT_OUTPUT: u32 = 0x8000_0001;
pub const EVENT_WINDOW: u32 = 0x8000_0003;
pub const EVENT_TICK: u32 = 0x8000_0007;
/// The tick spark-shell sends for Super+Tab (desktop window back).
pub const BACK: &str = "spark-pad.back";
/// The tick spark-shell sends after a window command: the tree read now.
pub const LOOK: &str = "spark-pad.look";

fn socket() -> io::Result<UnixStream> {
    let path = std::env::var_os("SWAYSOCK").ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no sway here (SWAYSOCK)"))?;
    let s = UnixStream::connect(path)?;
    s.set_read_timeout(Some(Duration::from_secs(3)))?;
    s.set_write_timeout(Some(Duration::from_secs(3)))?;
    Ok(s)
}

/// A message on the wire: the magic, the payload's length and its type, then the payload.
pub fn frame(kind: u32, payload: &[u8]) -> Vec<u8> {
    let mut m = Vec::with_capacity(14 + payload.len());
    m.extend_from_slice(MAGIC);
    m.extend_from_slice(&(payload.len() as u32).to_ne_bytes());
    m.extend_from_slice(&kind.to_ne_bytes());
    m.extend_from_slice(payload);
    m
}

/// The whole messages at the front of `buf`, taken out of it; a partial one stays for the next read.
pub fn split(buf: &mut Vec<u8>) -> Vec<(u32, Vec<u8>)> {
    let mut out = vec![];
    loop {
        if buf.len() < 14 {
            break;
        }
        if &buf[..6] != MAGIC {
            buf.clear();
            break;
        }
        let len = u32::from_ne_bytes(buf[6..10].try_into().unwrap()) as usize;
        let kind = u32::from_ne_bytes(buf[10..14].try_into().unwrap());
        if buf.len() < 14 + len {
            break;
        }
        out.push((kind, buf[14..14 + len].to_vec()));
        buf.drain(..14 + len);
    }
    out
}

/// A connection for requests: one answer to each.
pub struct Ipc {
    s: UnixStream,
}

impl Ipc {
    pub fn connect() -> io::Result<Ipc> {
        Ok(Ipc { s: socket()? })
    }

    pub fn request(&mut self, kind: u32, payload: &str) -> io::Result<Value> {
        self.s.write_all(&frame(kind, payload.as_bytes()))?;
        let mut head = [0u8; 14];
        self.s.read_exact(&mut head)?;
        if &head[..6] != MAGIC {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "sway answered something else"));
        }
        let len = u32::from_ne_bytes(head[6..10].try_into().unwrap()) as usize;
        let mut body = vec![0u8; len];
        self.s.read_exact(&mut body)?;
        serde_json::from_slice(&body).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
    }

    pub fn tree(&mut self) -> io::Result<Value> {
        self.request(GET_TREE, "")
    }

    pub fn run(&mut self, command: &str) -> io::Result<Value> {
        self.request(RUN_COMMAND, command)
    }

    /// The output sway has the focus on, by name.
    pub fn focused_output(&mut self) -> Option<String> {
        let outs = self.request(GET_OUTPUTS, "").ok()?;
        outs.as_array()?.iter().find(|o| o["focused"] == true)?["name"].as_str().map(String::from)
    }
}

/// A connection that hears sway's events of those kinds: non-blocking, for the event loop.
pub fn subscribe(kinds: &[&str]) -> io::Result<UnixStream> {
    let mut s = socket()?;
    s.write_all(&frame(SUBSCRIBE, serde_json::to_string(kinds).unwrap_or_default().as_bytes()))?;
    let mut head = [0u8; 14];
    s.read_exact(&mut head)?;
    let len = u32::from_ne_bytes(head[6..10].try_into().unwrap()) as usize;
    let mut body = vec![0u8; len];
    s.read_exact(&mut body)?;
    let ok: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
    if ok["success"] != true {
        return Err(io::Error::other("sway refused the events"));
    }
    s.set_nonblocking(true)?;
    Ok(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_split_whole_and_keep_a_partial_one() {
        let mut buf = frame(EVENT_WINDOW, br#"{"change":"move"}"#);
        buf.extend(frame(EVENT_WINDOW, b"{}"));
        let tail = frame(EVENT_WINDOW, br#"{"change":"close"}"#);
        buf.extend(&tail[..10]);
        let got = split(&mut buf);
        assert_eq!(got.len(), 2);
        assert_eq!(got[0], (EVENT_WINDOW, br#"{"change":"move"}"#.to_vec()));
        assert_eq!(buf.len(), 10);
        buf.extend(&tail[10..]);
        assert_eq!(split(&mut buf), vec![(EVENT_WINDOW, br#"{"change":"close"}"#.to_vec())]);
        assert!(buf.is_empty());
    }
}
