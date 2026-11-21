//! The MCP client: one provider is one child on stdio, JSON-RPC a line
//! (MCP 2025-06-18). No shell starts it, its environment is a named
//! list, every line it writes is capped, and every request it is sent
//! has a deadline. Its lines are queued and written by a thread of its
//! own, so a provider that stops reading never blocks the dialog.

use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::mpsc::SyncSender;
use std::sync::{Arc, Condvar, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

pub const PROTOCOL: &str = "2025-06-18";
/// A line longer than this from a provider closes it; the dialog never writes a longer one. Twice
/// RESOURCE_MAX: a resource's text comes inside one line, its quotes escaped (a preview's page, #120).
pub const LINE_MAX: usize = 1048576;
/// A resource's text longer than this is not drawn, and the provider is closed: a folder's page of a
/// thousand rows fits (#123).
pub const RESOURCE_MAX: usize = 524288;
/// The most bytes queued for a provider, the line being written included: the longest line and as much again
/// behind it. A provider with more than this unread has stopped reading, and is closed (#28).
pub const QUEUE_MAX: usize = 2 * LINE_MAX;
/// A line is written in pieces this long, and a close is seen between two, so it cuts a long line short.
const PIECE: usize = libc::PIPE_BUF;
/// Why a provider is gone when its queue is full or a write to it fails.
const DEAF: &str = "it stopped reading";
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
    /// A preview's page (#120).
    Page,
    /// The page of the file lit in a list of files, for its details beside the list: what the file shows.
    Peek,
    /// The rows a provider found for the words typed at Home: files by name, notes by what they say (#169).
    Hits,
    /// A sound's play or stop in a preview: a key, not a turn (#120).
    Quiet,
    /// A value set in place (#183): no turn, a refusal puts the value back.
    Set,
    Subscribe,
    Call(u64),
}

/// A tool result has its own envelope even when its tool declares no output
/// schema. A malformed reply is an unknown outcome, never evidence of success.
pub fn tool_result_ok(value: &Value) -> bool {
    let string = |v: &Value, k: &str| v.get(k).is_some_and(Value::is_string);
    value.is_object()
        && value.get("isError").is_none_or(Value::is_boolean)
        && value.get("structuredContent").is_none_or(Value::is_object)
        && value.get("content").and_then(Value::as_array).is_some_and(|items| {
            items.iter().all(|item| match item.get("type").and_then(Value::as_str) {
                Some("text") => string(item, "text"),
                Some("image" | "audio") => string(item, "data") && string(item, "mimeType"),
                Some("resource_link") => string(item, "uri") && string(item, "name"),
                Some("resource") => item
                    .get("resource")
                    .is_some_and(|r| string(r, "uri") && (string(r, "text") || string(r, "blob"))),
                _ => false,
            })
        })
}

#[derive(Debug)]
pub struct Pending {
    pub kind: Kind,
    pub deadline: Instant,
    pub token: Option<String>,
}

/// The lines queued for one provider. The dialog's thread only queues a line and never waits. The provider's
/// writer thread writes them, so a provider that stops reading blocks that thread, not the dialog (#28).
#[derive(Default)]
struct Outbox {
    state: Mutex<Waiting>,
    more: Condvar,
}

#[derive(Default)]
struct Waiting {
    /// The lines not started yet, each with the id of the request it carries.
    lines: VecDeque<(Option<u64>, Vec<u8>)>,
    /// The bytes of `lines` plus the line being written.
    bytes: usize,
    closed: bool,
}

/// Why a line was not queued.
enum Refused {
    Closed,
    Full,
}

impl Outbox {
    fn state(&self) -> MutexGuard<'_, Waiting> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn put(&self, id: Option<u64>, line: Vec<u8>) -> Result<(), Refused> {
        let mut q = self.state();
        if q.closed {
            return Err(Refused::Closed);
        }
        if q.bytes + line.len() > QUEUE_MAX {
            return Err(Refused::Full);
        }
        q.bytes += line.len();
        q.lines.push_back((id, line));
        drop(q);
        self.more.notify_one();
        Ok(())
    }

    /// Removes a request that is still queued, so it is never sent. False when its line was already started.
    fn withdraw(&self, id: u64) -> bool {
        let mut q = self.state();
        let Some(at) = q.lines.iter().position(|(i, _)| *i == Some(id)) else {
            return false;
        };
        if let Some((_, line)) = q.lines.remove(at) {
            q.bytes -= line.len();
        }
        true
    }

    /// Stops sending: the queued lines are dropped, the line being written stops at its next piece, and the
    /// writer thread closes the provider's input. True when the queue was open.
    fn close(&self) -> bool {
        let mut q = self.state();
        let open = !q.closed;
        q.closed = true;
        let dropped: usize = q.lines.drain(..).map(|(_, line)| line.len()).sum();
        q.bytes -= dropped;
        drop(q);
        self.more.notify_one();
        open
    }
}

pub struct Server {
    pub argv: Vec<String>,
    pub idx: usize,
    pub label: String,
    outbox: Arc<Outbox>,
    tx: SyncSender<Incoming>,
    next: u64,
    pub pending: HashMap<u64, Pending>,
    pub alive: bool,
}

/// Dropping a server closes its provider's input, as `close_stdin` does: the writer thread holds the pipe.
impl Drop for Server {
    fn drop(&mut self) {
        self.outbox.close();
    }
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
            .stderr(Stdio::null())
            // a process group of its own: the window closing (a hangup to the terminal's group) never
            // reaches a provider in the middle of a step; it ends when its input does (#60)
            .process_group(0);
        for (k, v) in std::env::vars() {
            if env_kept(&k) {
                cmd.env(k, v);
            }
        }
        if let Ok(h) = std::env::var("HOME") {
            cmd.current_dir(h);
        }
        // the child's pipes are kept, the handle itself is not: nothing waits for a provider (#60)
        let mut child = cmd.spawn().map_err(|e| format!("{}: {}", label, e))?;
        let out = child.stdout.take().ok_or("no stdout")?;
        let to = child.stdin.take().ok_or("no stdin")?;
        let mut server = Server::on_pipes(idx, label, out, to, tx);
        server.argv = argv.to_vec();
        Ok(server)
    }

    /// A provider on a pair of pipes already open (the tests' stub servers).
    pub fn on_pipes(idx: usize, label: &str, from: impl Read + Send + 'static, to: impl Write + Send + 'static, tx: SyncSender<Incoming>) -> Server {
        let outbox = Arc::new(Outbox::default());
        std::thread::spawn({
            let tx = tx.clone();
            move || read_lines(idx, from, tx)
        });
        std::thread::spawn({
            let (outbox, tx) = (outbox.clone(), tx.clone());
            move || write_lines(idx, to, outbox, tx)
        });
        Server {
            argv: vec![],
            idx,
            label: label.to_string(),
            outbox,
            tx,
            next: 1,
            pending: HashMap::new(),
            alive: true,
        }
    }

    /// Queues a line for the provider and never waits. False when the line is not queued: it is over LINE_MAX,
    /// the provider is closed, or the queue is full. A full queue closes the provider and reports it gone.
    fn write(&mut self, id: Option<u64>, v: &Value) -> bool {
        let mut line = v.to_string();
        if line.len() > LINE_MAX {
            return false;
        }
        line.push('\n');
        match self.outbox.put(id, line.into_bytes()) {
            Ok(()) => true,
            Err(Refused::Closed) => false,
            Err(Refused::Full) => {
                self.outbox.close();
                // reported from a thread of its own: the channel is bounded, and the dialog's thread never waits on it
                let (tx, idx) = (self.tx.clone(), self.idx);
                std::thread::spawn(move || tx.send(Incoming::Gone(idx, DEAF.into())));
                false
            }
        }
    }

    /// A request with its deadline; the id, or None when the provider is gone. The deadline covers the time in
    /// the queue and the write (#28). A request queued and only partly sent keeps its id: it ends at its deadline
    /// or with its provider, and its outcome is unknown.
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
        let deadline = Instant::now() + timeout;
        let ok = self.write(Some(id), &json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}));
        if !ok {
            self.alive = false;
            return None;
        }
        self.pending.insert(id, Pending { kind, deadline, token });
        Some(id)
    }

    pub fn notify(&mut self, method: &str, params: Value) {
        let _ = self.write(None, &json!({"jsonrpc": "2.0", "method": method, "params": params}));
    }

    pub fn answer(&mut self, id: &Value, result: Value) {
        let _ = self.write(None, &json!({"jsonrpc": "2.0", "id": id, "result": result}));
    }

    pub fn refuse(&mut self, id: &Value, code: i64, message: &str) {
        let _ = self.write(None, &json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}));
    }

    /// The requests whose deadline passed: each is dead. One still queued is never sent; one sent, or partly
    /// sent, gets a cancellation.
    pub fn expired(&mut self, now: Instant) -> Vec<(u64, Pending)> {
        let late: Vec<u64> = self.pending.iter().filter(|(_, p)| p.deadline <= now).map(|(k, _)| *k).collect();
        let mut out = Vec::new();
        for id in late {
            if let Some(p) = self.pending.remove(&id) {
                if !self.outbox.withdraw(id) {
                    self.notify("notifications/cancelled", json!({"requestId": id, "reason": "the dialog stopped waiting"}));
                }
                out.push((id, p));
            }
        }
        out
    }

    /// The token of a request still waiting, so progress is taken only for it.
    pub fn token_active(&self, token: &str) -> bool {
        self.pending.values().any(|p| p.token.as_deref() == Some(token))
    }

    /// Its input closed: the provider ends the request it is answering, reads the end of its input
    /// and leaves through its own EXIT trap, its temporary folder with it. Nothing waits for it (#60).
    /// What is still queued is never sent. A provider that had stopped reading sees the end of its input
    /// when it reads again (#28).
    pub fn close_stdin(&mut self) {
        self.outbox.close();
        self.alive = false;
    }
}

/// A provider's writer thread: it writes the queued lines in order, a piece at a time. It ends when the queue
/// closes or a write fails, and the provider's input closes with it. A failed write reports the provider gone.
fn write_lines(idx: usize, mut to: impl Write, outbox: Arc<Outbox>, tx: SyncSender<Incoming>) {
    loop {
        let line = {
            let mut q = outbox.state();
            loop {
                if q.closed {
                    return;
                }
                if let Some((_, line)) = q.lines.pop_front() {
                    break line;
                }
                q = outbox.more.wait(q).unwrap_or_else(PoisonError::into_inner);
            }
        };
        let mut sent = Ok(());
        for piece in line.chunks(PIECE) {
            if outbox.state().closed {
                return;
            }
            sent = to.write_all(piece);
            if sent.is_err() {
                break;
            }
        }
        outbox.state().bytes -= line.len();
        if sent.and_then(|_| to.flush()).is_err() {
            if outbox.close() {
                let _ = tx.send(Incoming::Gone(idx, DEAF.into()));
            }
            return;
        }
    }
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
            let _ = tx.send(Incoming::Gone(idx, "a line over 1 MB".into()));
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
        "capabilities": {"elicitation": {}, "roots": {"listChanged": false}, "experimental": {"spark-shell/pairing": true}},
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

    /// A guard, so a call that blocks on a provider's pipe fails the test and does not hang it. It is not a
    /// guess at how long a call takes.
    const GUARD: Duration = Duration::from_secs(10);

    /// Runs `run` on a thread of its own, as the dialog's thread would: a call that blocks fails here.
    fn in_time<T: Send + 'static>(run: impl FnOnce() -> T + Send + 'static) -> T {
        let (done, back) = std::sync::mpsc::channel();
        std::thread::spawn(move || done.send(run()));
        back.recv_timeout(GUARD).expect("the call blocked on a provider that does not read")
    }

    /// A provider that does not read: the reader of its input is held open and not read, its output is silent.
    fn deaf() -> (Server, std::io::PipeReader, std::io::PipeWriter, std::sync::mpsc::Receiver<Incoming>) {
        let (input, to) = std::io::pipe().unwrap();
        let (from, output) = std::io::pipe().unwrap();
        let (tx, said) = std::sync::mpsc::sync_channel(8);
        (Server::on_pipes(0, "deaf", from, to, tx), input, output, said)
    }

    /// Params that make a line of half LINE_MAX: more than a pipe holds.
    fn long() -> Value {
        json!({"uri": "a".repeat(LINE_MAX / 2)})
    }

    #[test]
    fn a_provider_that_never_reads_blocks_no_request_deadline_or_close() {
        // #28: the write blocked the dialog's thread on the full pipe, and the deadline started after the write
        let (mut s, mut input, _output, _said) = deaf();
        let soon = Duration::from_millis(25);
        let before = Instant::now();
        let (mut s, first) = in_time(move || {
            let id = s.request("resources/read", long(), Kind::Read, soon);
            (s, id)
        });
        let first = first.expect("the request is queued");
        // the writer thread takes the first line and blocks on the pipe; the second request stays queued
        let end = Instant::now() + GUARD;
        while !s.outbox.state().lines.is_empty() && Instant::now() < end {
            std::thread::sleep(Duration::from_millis(1));
        }
        assert!(s.outbox.state().lines.is_empty(), "the writer thread took the first line");
        let second = s.request("tools/list", json!({}), Kind::Tools, soon).expect("the second is queued");
        assert!(s.expired(before).is_empty(), "nothing expires early");
        // both expire on time: the deadline covers the time in the queue and the write
        let last = s.pending.values().map(|p| p.deadline).max().unwrap();
        std::thread::sleep(last.saturating_duration_since(Instant::now()));
        let (mut s, late) = in_time(move || {
            let late = s.expired(Instant::now());
            (s, late)
        });
        let mut ids: Vec<u64> = late.iter().map(|(id, _)| *id).collect();
        ids.sort();
        assert_eq!(ids, vec![first, second]);
        // the queued request is never sent; the partly sent one gets a cancellation
        let queued: Vec<Value> = s.outbox.state().lines.iter().map(|(_, line)| serde_json::from_slice(line).unwrap()).collect();
        assert_eq!(queued.len(), 1, "{:?}", queued);
        assert_eq!(queued[0]["method"], "notifications/cancelled");
        assert_eq!(queued[0]["params"]["requestId"], first);
        // a close does not block, and the input does close: a provider that reads now gets the start of the
        // first line, then the end of its input, and nothing that was queued
        let mut s = in_time(move || {
            s.close_stdin();
            s
        });
        assert!(!s.alive && s.request("tools/list", json!({}), Kind::Tools, soon).is_none());
        let read = in_time(move || {
            let mut read = Vec::new();
            input.read_to_end(&mut read).map(|_| read)
        })
        .unwrap();
        let line = json!({"jsonrpc": "2.0", "id": first, "method": "resources/read", "params": long()}).to_string();
        assert!(read.len() < line.len() && line.as_bytes().starts_with(&read), "{} bytes", read.len());
    }

    #[test]
    fn a_full_queue_closes_the_provider_and_reports_it_gone() {
        let (mut s, _input, _output, said) = deaf();
        // three lines of half LINE_MAX fit under QUEUE_MAX; the fourth is refused and closes the provider
        let (mut s, queued) = in_time(move || {
            let queued: Vec<Option<u64>> = (0..5).map(|_| s.request("resources/read", long(), Kind::Read, T_READ)).collect();
            (s, queued)
        });
        assert_eq!(queued, vec![Some(1), Some(2), Some(3), None, None]);
        assert!(!s.alive && s.request("tools/list", json!({}), Kind::Tools, T_LIST).is_none());
        assert!(s.outbox.state().lines.is_empty(), "a closed queue holds nothing");
        match said.recv_timeout(GUARD) {
            Ok(Incoming::Gone(0, why)) => assert_eq!(why, "it stopped reading"),
            other => panic!("{:?}", other),
        }
        // the three queued are still pending: the app ends them with the provider, their outcome unknown
        assert!(queued.iter().flatten().all(|id| s.pending.contains_key(id)));
    }

    #[test]
    fn a_failed_write_reports_the_provider_gone_and_keeps_the_request_pending() {
        // the provider reads the start of a call, then closes its input: the call is partly sent
        let (mut s, mut input, _output, said) = deaf();
        let id = s.request("tools/call", long(), Kind::Call(0), T_CALL).expect("the call is queued");
        let input = in_time(move || {
            input.read_exact(&mut [0; 64]).unwrap();
            input
        });
        drop(input);
        match said.recv_timeout(GUARD) {
            Ok(Incoming::Gone(0, why)) => assert_eq!(why, "it stopped reading"),
            other => panic!("{:?}", other),
        }
        // the call is still pending, not refused: the app ends it as one that may or may not have happened
        assert!(s.pending.contains_key(&id));
        assert!(s.request("tools/list", json!({}), Kind::Tools, T_LIST).is_none() && !s.alive);
    }
}
