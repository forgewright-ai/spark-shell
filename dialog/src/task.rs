//! The desktop host of spark do's tool adapter. No model runs an OS action.
//! The continuation lives in this window, and results keep their MCP shape.

use crate::app::{section_name, App, Helper, Item, Job, Sign, Staged, Step, View, Who, DESTS, SETTINGS};
use crate::gate;
use crate::model::Call;
use crate::progress::Work;
use crate::scrub::scrub;
use serde_json::{json, Value};

#[derive(Clone, Debug, PartialEq)]
pub enum Phase {
    Thinking,
    Proposed,
    Question,
    Inspect(usize),
    Refresh(usize),
    Prepare(usize),
}

/// An explicit row selection, independent of the search results while typing.
#[derive(Clone, Debug)]
pub struct Target {
    pub view: View,
    pub provider: usize,
    pub id: String,
    pub text: String,
}

#[derive(Clone, Debug)]
pub struct Task {
    pub state: Value,
    pub goal: String,
    pub serial: u64,
    pub id: u64,
    pub phase: Phase,
    pub scope: Vec<usize>,
    pub offered: Vec<(usize, String)>,
    pub preparing: Option<Call>,
    pub observation: Option<Value>,
    pub attempted: Vec<(usize, Call)>,
}

/// Credentials stay in the native tool host, including schema-marked fields.
fn public_args(call: &Call, schema: &Value) -> Value {
    Value::Object(
        call.arguments
            .iter()
            .filter(|(k, _)| !gate::secret(k, schema.pointer(&format!("/properties/{}", k))))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect(),
    )
}

impl App {
    pub fn answering(&self) -> bool {
        self.task.as_ref().is_some_and(|t| t.phase == Phase::Question)
    }

    pub fn remember_target(&mut self) {
        if self.target.is_some() || self.task.is_some() || !self.input.is_empty() || !self.in_list {
            return;
        }
        if let Some(Item::Row(p, r)) = self.picks().get(self.sel) {
            let row = &self.providers[*p].rows.rows[*r];
            if self.providers[*p].label != "files" {
                self.target = Some(Target {
                    view: self.view.clone(),
                    provider: *p,
                    id: row.id.clone(),
                    text: row.text.clone(),
                });
            }
        }
    }

    pub fn target_row(&self) -> Option<(usize, &crate::model::Row)> {
        let t = self.target.as_ref()?;
        let p = self.providers.get(t.provider)?;
        if self.view != t.view || !p.ready || p.dead.is_some() {
            return None;
        }
        p.rows.rows.iter().find(|r| r.id == t.id).map(|r| (t.provider, r))
    }

    pub fn target_label(&self) -> Option<String> {
        self.target.as_ref().map(|t| match self.target_row() {
            Some((_, r)) => format!("For: {}", r.text),
            None => format!("No longer available: {}", t.text),
        })
    }

    pub fn task_cancel(&mut self) {
        if self.task.take().is_some() {
            self.target = None;
            self.task_serial += 1; // any late inference reply belongs to the old task
            self.wait = None;
            self.opened = false;
            self.staged = None;
            self.queue.clear();
            self.jobs.retain(|j| !matches!(j, Job::RunInput(Helper::Task(_), _, _)));
        }
    }

    pub fn task_start(&mut self, words: &str) {
        self.remember_target();
        let target = self.target.take();
        self.task_cancel();
        self.target = target;
        if self.target.is_some() && self.target_row().is_none() {
            self.target = None;
            self.set_input(words.to_string());
            return self.say(Sign::Refused, "the selected item is no longer available; select it again");
        }
        self.task = Some(Task {
            state: Value::Null,
            goal: words.into(),
            serial: 0,
            id: 0,
            phase: Phase::Thinking,
            scope: vec![],
            offered: vec![],
            preparing: None,
            observation: None,
            attempted: vec![],
        });
        self.task_advance(json!({}));
    }

    fn task_context(&self) -> Value {
        let providers: Vec<Value> = self
            .providers
            .iter()
            .enumerate()
            .filter(|(_, p)| p.ready && p.dead.is_none() && p.label != "files")
            .map(|(i, p)| {
                // Discovery needs the same meaning as the native navigation.
                // A provider's title/state can name a private device or item;
                // use only the host's static domain descriptions here.
                let description = SETTINGS
                    .iter()
                    .find(|(label, _, _)| *label == p.label)
                    .map(|(_, _, purpose)| *purpose)
                    .or_else(|| DESTS.iter().find(|d| d.sections.contains(&p.label.as_str())).map(|d| d.purpose));
                json!({"id": i, "name": p.label, "title": section_name(&p.label), "description": description})
            })
            .collect();
        // Only visible state is volunteered. More is read through an explicit
        // inspect decision; hidden notes, directories and networks stay out.
        let visible: Vec<Value> = self
            .shown()
            .iter()
            .filter(|i| self.providers[**i].label != "files")
            .map(|i| self.task_rows(*i))
            .collect();
        let selected = self.target_row().map(|(p, row)| {
            let mut value = self.task_row(p, row);
            value["provider"] = json!(p);
            value
        });
        json!({"view": self.title(), "selected": selected, "providers": providers, "visible": visible,
               "clock": clock_context()})
    }

    fn task_row(&self, idx: usize, row: &crate::model::Row) -> Value {
        let call = |c: &Call| {
            let schema = self.providers[idx]
                .tools
                .iter()
                .find(|t| t.name == c.name)
                .map(|t| &t.schema)
                .unwrap_or(&Value::Null);
            json!({"name": format!("p{}_{}", idx, c.name), "arguments": public_args(c, schema)})
        };
        let more: Vec<Value> = row.more.iter().map(&call).collect();
        let step = row
            .step
            .as_ref()
            .map(|s| json!({"value": s.value, "less": call(&s.less), "more": call(&s.more)}));
        json!({"id": row.id, "text": row.text, "state": row.sign, "date": row.date,
               "group": row.group, "columns": row.columns, "call": row.tool.as_ref().map(&call),
               "more": more, "step": step})
    }

    fn task_rows(&self, idx: usize) -> Value {
        let p = &self.providers[idx];
        let rows: Vec<Value> = p.rows.rows.iter().take(100).map(|r| self.task_row(idx, r)).collect();
        json!({"provider": idx, "state": p.rows.state, "rows": rows, "truncated": p.rows.rows.len() > 100,
               "age_ms": p.last_read.map(|t| t.elapsed().as_millis())})
    }

    pub fn task_advance(&mut self, extra: Value) {
        let Some(task) = &self.task else { return };
        let mut request = json!({"version": 1, "goal": task.goal, "context": self.task_context()});
        if !task.state.is_null() {
            request["state"] = task.state.clone();
        }
        let mut tools = vec![];
        let mut offered = vec![];
        let mut scope = self.shown();
        for i in &task.scope {
            if !scope.contains(i) {
                scope.push(*i);
            }
        }
        for (i, p) in self.providers.iter().enumerate().filter(|(_, p)| p.ready && p.dead.is_none()) {
            if !scope.contains(&i) {
                continue;
            }
            for t in &p.tools {
                // File operations retain the explicit picker/attachment path.
                if p.label == "files" {
                    continue;
                }
                tools.push(json!({"name": format!("p{}_{}", i, t.name), "title": t.title,
                    "description": t.description, "inputSchema": gate::task_schema(t, &p.rows)}));
                offered.push((i, t.name.clone()));
            }
        }
        request["tools"] = json!(tools);
        if let Some(fields) = extra.as_object() {
            for (k, v) in fields {
                request[k] = v.clone();
            }
        }
        let payload = request.to_string();
        if payload.len() > 262144 {
            self.task_cancel();
            return self.say(Sign::Refused, "this task has too much context to send");
        }
        self.task_serial += 1;
        if let Some(task) = &mut self.task {
            task.serial = self.task_serial;
            task.phase = Phase::Thinking;
            task.offered = offered;
        }
        self.wait = Some(Work::Think);
        self.jobs.push(Job::RunInput(
            Helper::Task(self.task_serial),
            vec![self.cfg.spark.clone(), "do".into(), "--tools".into()],
            payload,
        ));
    }

    pub fn task_reply(&mut self, serial: u64, output: Result<String, String>) {
        if !self.task.as_ref().is_some_and(|t| t.serial == serial && t.phase == Phase::Thinking) {
            return;
        }
        self.wait = None;
        let value: Value = match output.and_then(|s| serde_json::from_str::<Value>(&s).map_err(|_| "spark returned an invalid task reply".into())) {
            Ok(v) if v.get("version") == Some(&json!(1)) => v,
            Ok(_) => {
                self.task_cancel();
                return self.say(Sign::Refused, "spark does not support this task protocol");
            }
            Err(e) => {
                self.task_cancel();
                return self.say(Sign::Refused, &scrub(&e));
            }
        };
        let status = value["status"].as_str().unwrap_or("");
        if !["step", "ask", "inspect"].contains(&status) {
            let opened = self.opened;
            self.task_cancel();
            let message = scrub(value["summary"].as_str().unwrap_or("the task stopped without a result"));
            // A model's completion statement is prose. Native receipts alone
            // carry the Done mark, so a fluent claim cannot impersonate proof.
            self.say(if status == "done" || status == "answer" { Sign::Says } else { Sign::Refused }, &message);
            if status == "done" {
                self.opened = opened;
                self.next_step();
            } else {
                self.opened = false;
            }
            return;
        }
        if self.target.is_some() && self.target_row().is_none() {
            self.task_cancel();
            return self.say(Sign::Refused, "the selected item is no longer available; select it again");
        }
        let Some(id) = value["id"].as_u64() else {
            self.task_cancel();
            return;
        };
        let state = value["state"].clone();
        if !state.is_object() || state["pending"]["id"] != json!(id) {
            self.task_cancel();
            return self.say(Sign::Refused, "spark returned no matching task continuation");
        }
        if let Some(t) = &mut self.task {
            t.state = state;
            t.id = id;
        }
        match status {
            "ask" => {
                let question = scrub(value["question"].as_str().unwrap_or(""));
                if question.is_empty() {
                    self.task_cancel();
                    return;
                }
                if let Some(t) = &mut self.task {
                    t.phase = Phase::Question;
                }
                self.say(Sign::Says, &question);
            }
            "inspect" => {
                let idx = value["provider"].as_u64().map(|v| v as usize);
                if let Some(idx) = idx.filter(|i| self.providers.get(*i).is_some_and(|p| p.ready && p.dead.is_none() && p.label != "files")) {
                    if let Some(t) = &mut self.task {
                        t.phase = Phase::Inspect(idx);
                        if !t.scope.contains(&idx) {
                            t.scope.push(idx);
                        }
                    }
                    self.wait = Some(Work::Read);
                    self.read(idx);
                } else {
                    self.task_observe("error", json!({"isError": true, "message": "that provider cannot be inspected"}));
                }
            }
            "step" => {
                if value["step"] != value["state"]["pending"]["step"] {
                    self.task_cancel();
                    return self.say(Sign::Refused, "the proposal does not match its continuation");
                }
                let name = value["step"]["name"].as_str().unwrap_or("");
                let pair = name.strip_prefix('p').and_then(|s| s.split_once('_'));
                let resolved = pair.and_then(|(p, n)| p.parse::<usize>().ok().map(|i| (i, n.to_string())));
                let Some((prov, name)) = resolved.filter(|(i, _)| *i < self.providers.len()) else {
                    self.task_cancel();
                    return self.say(Sign::Refused, "spark proposed an unknown capability");
                };
                if !self.task.as_ref().is_some_and(|t| t.offered.contains(&(prov, name.clone()))) {
                    self.task_cancel();
                    return self.say(Sign::Refused, "spark proposed a capability that was not offered for this turn");
                }
                let Some(arguments) = value["step"]["arguments"].as_object().cloned() else {
                    self.task_cancel();
                    return;
                };
                let call = Call { name, arguments, ask: vec![] };
                let schema = self.providers[prov].tools.iter().find(|t| t.name == call.name).map(|t| &t.schema);
                if call
                    .arguments
                    .keys()
                    .any(|k| gate::secret(k, schema.and_then(|s| s.pointer(&format!("/properties/{}", k)))))
                {
                    self.task_cancel();
                    return self.say(Sign::Refused, "enter credentials through the native control");
                }
                if let Err(e) = gate::step(&self.providers[prov].tools, &self.providers[prov].rows, &call) {
                    self.say(Sign::Refused, &e);
                    return self.task_observe("error", json!({"isError": true, "message": e}));
                }
                if self.providers[prov].tools.iter().any(|t| t.name == call.name && t.prepare) {
                    let serial = self.task.as_ref().unwrap().serial;
                    let params = json!({"name": call.name, "arguments": call.arguments});
                    if let Some(t) = &mut self.task {
                        t.phase = Phase::Prepare(prov);
                        t.preparing = Some(call);
                    }
                    self.wait = Some(Work::Read);
                    let sent = self
                        .server(prov)
                        .and_then(|s| s.request("spark/prepare", params, crate::mcp::Kind::Prepare(serial), crate::mcp::T_READ))
                        .is_some();
                    if !sent {
                        self.task_prepared(prov, serial, None, Some("preparation could not start; nothing was executed".into()));
                    }
                } else {
                    self.task_stage(prov, call);
                }
            }
            _ => unreachable!(),
        }
    }

    pub fn task_prepared(&mut self, prov: usize, serial: u64, result: Option<Value>, error: Option<String>) {
        if !self.task.as_ref().is_some_and(|t| t.serial == serial && t.phase == Phase::Prepare(prov)) {
            return;
        }
        self.wait = None;
        let mut call = self.task.as_mut().and_then(|t| t.preparing.take()).unwrap();
        let fail = |app: &mut App, message: &str| {
            app.task_cancel();
            app.say(Sign::Refused, message);
        };
        if let Some(e) = error {
            return fail(self, &scrub(&e));
        }
        let Some(result) = result else {
            return fail(self, "preparation returned no result; nothing was executed");
        };
        match result["ready"].as_bool() {
            Some(false) => {
                let question = scrub(result["question"].as_str().unwrap_or(""));
                if question.is_empty() || question.chars().count() > 500 {
                    return fail(self, "preparation returned an invalid question; nothing was executed");
                }
                self.task_observe("needs_input", json!({"question": question}));
            }
            Some(true) => {
                let Some(args) = result["arguments"].as_object() else {
                    return fail(self, "preparation returned invalid arguments; nothing was executed");
                };
                let schema = self.providers[prov].tools.iter().find(|t| t.name == call.name).map(|t| &t.schema);
                if args
                    .keys()
                    .any(|k| gate::secret(k, schema.and_then(|s| s.pointer(&format!("/properties/{}", k)))))
                {
                    return fail(self, "preparation cannot supply credentials");
                }
                call.arguments = args.clone();
                if let Err(e) = gate::step(&self.providers[prov].tools, &self.providers[prov].rows, &call) {
                    return fail(self, &e);
                }
                if let Some(t) = &mut self.task {
                    t.state["pending"]["step"]["arguments"] = json!(call.arguments);
                }
                self.task_stage(prov, call);
            }
            None => fail(self, "preparation returned an invalid result; nothing was executed"),
        }
    }

    fn task_stage(&mut self, prov: usize, call: Call) {
        if self.task_repeat(prov, &call) {
            return;
        }
        if self.target.is_some() && self.target_row().is_none() {
            self.task_cancel();
            return self.say(Sign::Refused, "the selected item is no longer available; select it again");
        }
        let title = self.providers[prov]
            .tools
            .iter()
            .find(|t| t.name == call.name)
            .map(|t| t.title.as_str())
            .unwrap_or(&call.name);
        let placeholders = title.split_whitespace().filter(|w| w.bytes().all(|c| c.is_ascii_uppercase())).count();
        let simple = call.arguments.is_empty()
            || (call.arguments.len() == 1
                && placeholders == 1
                && call
                    .arguments
                    .values()
                    .all(|v| v.as_str().is_some_and(|s| !s.chars().any(char::is_control)) || v.is_number() || v.is_boolean()));
        let line = if simple {
            self.step_line(prov, &call, &call.name)
        } else {
            // A title may have fewer placeholders than the schema has
            // fields. Show every value the person would authorize.
            let label = title
                .split_whitespace()
                .filter(|w| !w.bytes().all(|c| c.is_ascii_uppercase()))
                .collect::<Vec<_>>()
                .join(" ");
            let args = call
                .arguments
                .iter()
                .map(|(k, v)| format!("{}: {}", k.replace('_', " "), v))
                .collect::<Vec<_>>()
                .join("\n");
            format!("{}\n{}", label, args)
        };
        if line.chars().count() > crate::app::INPUT_MAX {
            self.task_cancel();
            return self.say(Sign::Refused, "the proposed action is too large to review in this prompt");
        }
        let step = Step {
            prov,
            call,
            who: Who::Model,
            line: line.clone(),
        };
        let draft = std::mem::take(&mut self.input);
        self.set_input(line.clone());
        self.in_list = false;
        self.staged = Some(Staged {
            text: line,
            steps: vec![step],
            draft,
        });
        if let Some(t) = &mut self.task {
            t.phase = Phase::Proposed;
        }
    }

    pub fn task_observe(&mut self, status: &str, result: Value) {
        let Some(t) = &self.task else { return };
        self.task_advance(json!({"observation": {"id": t.id, "status": status, "result": result}}));
    }

    /// Native preparation can turn different words into the same operation.
    /// Compare what would actually run, including attempts that returned an
    /// error. Earlier receipts stay visible; a fresh task can try again.
    pub fn task_repeat(&mut self, prov: usize, call: &Call) -> bool {
        if !self.task.as_ref().is_some_and(|t| {
            t.attempted
                .iter()
                .any(|(p, c)| *p == prov && c.name == call.name && c.arguments == call.arguments)
        }) {
            return false;
        }
        self.task_cancel();
        self.say(Sign::Refused, "this task already tried that action; stopped without repeating it");
        true
    }

    /// Read after a successful action before offering row-bound capabilities
    /// again. The result is already shown; a read failure cannot undo it.
    pub fn task_refresh(&mut self, idx: usize, result: Value) {
        let Some(t) = &mut self.task else { return };
        let serial = t.serial;
        t.observation = Some(json!({"observation":{"id":t.id,"status":"ok","result":result}}));
        t.phase = Phase::Refresh(idx);
        self.wait = Some(Work::Read);
        let uri = format!("spark-shell://{}/rows", self.providers[idx].label);
        let sent = self
            .server(idx)
            .and_then(|s| s.request("resources/read", json!({"uri":uri}), crate::mcp::Kind::Refresh(serial), crate::mcp::T_READ));
        if let Some(id) = sent {
            let p = &mut self.providers[idx];
            p.read_id = Some(id);
            p.reading = true;
            p.dirty = false;
            p.last_read = Some(std::time::Instant::now());
        } else {
            self.task_refreshed(idx, serial, false);
        }
    }

    pub fn task_refreshed(&mut self, idx: usize, serial: u64, ok: bool) {
        if !self.task.as_ref().is_some_and(|t| t.serial == serial && t.phase == Phase::Refresh(idx)) {
            return;
        }
        self.wait = None;
        if !ok {
            self.task_cancel();
            return self.say(Sign::Refused, "the action completed, but its current state could not be read; task stopped");
        }
        if let Some(observation) = self.task.as_mut().and_then(|t| t.observation.take()) {
            self.task_advance(observation);
        }
    }

    pub fn task_read(&mut self, idx: usize, ok: bool) {
        if self.task.as_ref().is_some_and(|t| t.phase == Phase::Inspect(idx)) {
            let result = if ok {
                json!({"structuredContent": self.task_rows(idx), "isError": false})
            } else {
                json!({"isError": true, "message": "the current state could not be read"})
            };
            self.task_observe(if ok { "ok" } else { "error" }, result);
        }
    }
}

/// The OS supplies local civil time and its numeric UTC offset together.
fn clock_context() -> String {
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
        return Err("task input exceeds 256 kB".into());
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
    let mut stdin = child.stdin.take().ok_or("no task input pipe")?;
    let stdout = child.stdout.take().ok_or("no task output pipe")?;
    let stderr = child.stderr.take().ok_or("no task error pipe")?;
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
                return Err("task output exceeds 256 kB".into());
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
