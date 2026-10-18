//! The MCP client: one provider is one child on stdio, JSON-RPC a line
//! (MCP 2025-06-18). No shell starts it, its environment is a named
//! list, every line it writes is capped, and every request it is sent
//! has a deadline.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::SyncSender;
use std::time::{Duration, Instant};

pub const PROTOCOL: &str = "2025-06-18";
/// A line longer than this from a provider closes it; the dialog never writes a longer one.
pub const LINE_MAX: usize = 65536;
/// A resource's text longer than this is not drawn, and the provider is closed.
pub const RESOURCE_MAX: usize = 262144;
pub const T_INIT: Duration = Duration::from_secs(5);
pub const T_LIST: Duration = Duration::from_secs(5);
pub const T_READ: Duration = Duration::from_secs(10);
/// A step's ceiling, whatever its progress says: spark do's STEP_TIMEOUT.
pub const T_CALL: Duration = Duration::from_secs(120);

/// The environment a provider gets, a named line each; nothing else is passed.
pub const ENV_KEEP: &[(&str, &str)] = &[
    ("HOME", "where its config and state live"),
    ("PATH", "the tools it runs"),
    ("LANG", "the language of its words"),
    ("LC_ALL", "the same"),
    ("LC_CTYPE", "the same"),
    ("TERM", "what a tool it runs may ask of the terminal"),
    ("XDG_CONFIG_HOME", "its config"),
    ("XDG_STATE_HOME", "its state"),
    ("XDG_DATA_HOME", "its data"),
    ("XDG_CACHE_HOME", "its cache"),
    ("XDG_RUNTIME_DIR", "the session's sockets"),
    ("WAYLAND_DISPLAY", "the desktop"),
    ("SWAYSOCK", "sway's own socket, for the windows"),
    ("DBUS_SESSION_BUS_ADDRESS", "the session bus"),
];
/// Prefixes passed whole: the palette spark-shell hands down, and the seams its tests set.
pub const ENV_KEEP_PREFIX: &[(&str, &str)] = &[
    ("HEX_", "the palette"),
    ("PANEL_", "the surface's shades"),
    ("SPARK_SHELL_", "the seams spark-shell's tests set (a fixture /sys, a throwaway root)"),
    ("SPARK_OS_RELEASE", "the distro fixture of the same tests"),
];

pub fn env_kept(name: &str) -> bool {
    ENV_KEEP.iter().any(|(k, _)| *k == name) || ENV_KEEP_PREFIX.iter().any(|(p, _)| name.starts_with(p))
}

/// What a provider says, as the reader thread hands it on.
#[derive(Debug)]
pub enum Incoming {
    Msg(usize, Value),
    Gone(usize, String),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Kind {
    Init,
    Tools,
    Read,
    Folder,
    Subscribe,
    Call(u64),
}

#[derive(Debug)]
pub struct Pending {
    pub kind: Kind,
    pub deadline: Instant,
    pub token: Option<String>,
}

pub struct Server {
    pub idx: usize,
    pub label: String,
    child: Option<Child>,
    stdin: Option<Box<dyn Write + Send>>,
    next: u64,
    pub pending: HashMap<u64, Pending>,
    pub alive: bool,
}

/// argv words, the first an absolute path: never a shell string.
pub fn argv_ok(argv: &[String]) -> Result<(), String> {
    match argv.first() {
        None => Err("a provider needs a command".into()),
        Some(p) if !p.starts_with('/') => Err(format!("{}: a provider is an absolute path", p)),
        Some(p) if p.chars().any(|c| c.is_control()) => Err("a provider's path holds a control character".into()),
        _ => Ok(()),
    }
}

impl Server {
    pub fn spawn(idx: usize, label: &str, argv: &[String], tx: SyncSender<Incoming>) -> Result<Server, String> {
        argv_ok(argv)?;
        let mut cmd = Command::new(&argv[0]);
        cmd.args(&argv[1..])
            .env_clear()
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        for (k, v) in std::env::vars() {
            if env_kept(&k) {
                cmd.env(k, v);
            }
        }
        if let Ok(h) = std::env::var("HOME") {
            cmd.current_dir(h);
        }
        let mut child = cmd.spawn().map_err(|e| format!("{}: {}", label, e))?;
        let out = child.stdout.take().ok_or("no stdout")?;
        let stdin: Option<Box<dyn Write + Send>> = child.stdin.take().map(|w: ChildStdin| Box::new(w) as Box<dyn Write + Send>);
        std::thread::spawn(move || read_lines(idx, out, tx));
        Ok(Server {
            idx,
            label: label.to_string(),
            child: Some(child),
            stdin,
            next: 1,
            pending: HashMap::new(),
            alive: true,
        })
    }

    /// A provider on a pair of pipes already open (the tests' stub servers).
    pub fn on_pipes(idx: usize, label: &str, from: impl Read + Send + 'static, to: impl Write + Send + 'static, tx: SyncSender<Incoming>) -> Server {
        std::thread::spawn(move || read_lines(idx, from, tx));
        Server {
            idx,
            label: label.to_string(),
            child: None,
            stdin: Some(Box::new(to)),
            next: 1,
            pending: HashMap::new(),
            alive: true,
        }
    }

    fn write(&mut self, v: &Value) -> bool {
        let mut line = v.to_string();
        if line.len() > LINE_MAX {
            return false;
        }
        line.push('\n');
        match self.stdin.as_mut() {
            Some(w) => w.write_all(line.as_bytes()).and_then(|_| w.flush()).is_ok(),
            None => false,
        }
    }

    /// A request with its deadline; the id, or None when the provider is gone.
    pub fn request(&mut self, method: &str, params: Value, kind: Kind, timeout: Duration) -> Option<u64> {
        if !self.alive {
            return None;
        }
        let id = self.next;
        self.next += 1;
        let mut params = params;
        let mut token = None;
        if let Kind::Call(_) = kind {
            let t = format!("{}-{}", self.label, id);
            if let Some(o) = params.as_object_mut() {
                o.insert("_meta".into(), json!({"progressToken": t}));
            }
            token = Some(t);
        }
        let ok = self.write(&json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}));
        if !ok {
            self.alive = false;
            return None;
        }
        self.pending.insert(
            id,
            Pending {
                kind,
                deadline: Instant::now() + timeout,
                token,
            },
        );
        Some(id)
    }

    pub fn notify(&mut self, method: &str, params: Value) {
        let _ = self.write(&json!({"jsonrpc": "2.0", "method": method, "params": params}));
    }

    pub fn answer(&mut self, id: &Value, result: Value) {
        let _ = self.write(&json!({"jsonrpc": "2.0", "id": id, "result": result}));
    }

    pub fn refuse(&mut self, id: &Value, code: i64, message: &str) {
        let _ = self.write(&json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}));
    }

    /// The requests whose deadline passed: each gets a cancellation, and is dead.
    pub fn expired(&mut self, now: Instant) -> Vec<(u64, Pending)> {
        let late: Vec<u64> = self.pending.iter().filter(|(_, p)| p.deadline <= now).map(|(k, _)| *k).collect();
        let mut out = Vec::new();
        for id in late {
            if let Some(p) = self.pending.remove(&id) {
                self.notify("notifications/cancelled", json!({"requestId": id, "reason": "the dialog stopped waiting"}));
                out.push((id, p));
            }
        }
        out
    }

    /// The token of a request still waiting, so progress is taken only for it.
    pub fn token_active(&self, token: &str) -> bool {
        self.pending.values().any(|p| p.token.as_deref() == Some(token))
    }

    /// Close stdin, 2 s; SIGTERM, 2 s; SIGKILL.
    pub fn close_stdin(&mut self) {
        self.stdin = None;
        self.alive = false;
    }

    pub fn shutdown(&mut self) {
        self.close_stdin();
        let Some(child) = self.child.as_mut() else { return };
        if wait_for(child, Duration::from_secs(2)) {
            return;
        }
        unsafe {
            libc::kill(child.id() as libc::pid_t, libc::SIGTERM);
        }
        if wait_for(child, Duration::from_secs(2)) {
            return;
        }
        let _ = child.kill();
        let _ = child.wait();
    }
}

fn wait_for(child: &mut Child, d: Duration) -> bool {
    let end = Instant::now() + d;
    while Instant::now() < end {
        if let Ok(Some(_)) = child.try_wait() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    false
}

fn read_lines(idx: usize, out: impl Read, tx: SyncSender<Incoming>) {
    let mut r = BufReader::new(out);
    loop {
        let mut buf = Vec::new();
        let n = match (&mut r).take(LINE_MAX as u64 + 1).read_until(b'\n', &mut buf) {
            Ok(n) => n,
            Err(e) => {
                let _ = tx.send(Incoming::Gone(idx, e.to_string()));
                return;
            }
        };
        if n == 0 {
            let _ = tx.send(Incoming::Gone(idx, "it ended".into()));
            return;
        }
        if buf.last() != Some(&b'\n') && buf.len() > LINE_MAX {
            let _ = tx.send(Incoming::Gone(idx, "a line over 64 kB".into()));
            return;
        }
        if buf.iter().all(|b| b.is_ascii_whitespace()) {
            continue;
        }
        match serde_json::from_slice::<Value>(&buf) {
            Ok(v) if v.get("jsonrpc") == Some(&json!("2.0")) => {
                if tx.send(Incoming::Msg(idx, v)).is_err() {
                    return;
                }
            }
            _ => {
                let _ = tx.send(Incoming::Gone(idx, "a line that is not MCP".into()));
                return;
            }
        }
    }
}

/// The initialize request's params: the host's own capabilities.
pub fn init_params() -> Value {
    json!({
        "protocolVersion": PROTOCOL,
        "capabilities": {"elicitation": {}, "roots": {"listChanged": false}},
        "clientInfo": {"name": "spark-dialog", "title": "the spark dialog", "version": env!("CARGO_PKG_VERSION")}
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn argv_is_an_absolute_path_and_words() {
        assert!(argv_ok(&["/usr/bin/x".into(), "provide".into()]).is_ok());
        assert!(argv_ok(&["x".into()]).is_err());
        assert!(argv_ok(&[]).is_err());
        assert!(argv_ok(&["/x\u{1b}".into()]).is_err());
    }

    #[test]
    fn the_environment_is_a_named_list() {
        for k in ["HOME", "PATH", "SWAYSOCK", "HEX_ACCENT", "PANEL_BG", "XDG_STATE_HOME"] {
            assert!(env_kept(k), "{}", k);
        }
        for k in ["SSH_AUTH_SOCK", "SPARK_API_KEY_FILE", "GITHUB_TOKEN", "LD_PRELOAD", "AWS_SECRET_ACCESS_KEY"] {
            assert!(!env_kept(k), "{}", k);
        }
    }
}
