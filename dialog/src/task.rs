//! The desktop host of spark do's tool adapter. No model runs an OS action.
//! The continuation lives in this window, and results keep their MCP shape.

use crate::app::{App, Helper, Item, Job, Sign, Staged, Step, Who};
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
    Prepare(usize),
}

#[derive(Clone, Debug)]
pub struct Task {
    pub state: Value,
    pub goal: String,
    pub serial: u64,
    pub id: u64,
    pub phase: Phase,
    pub scope: Option<usize>,
    pub preparing: Option<Call>,
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
    pub fn task_cancel(&mut self) {
        if self.task.take().is_some() {
            self.task_serial += 1; // any late inference reply belongs to the old task
            self.wait = None;
            self.staged = None;
            self.queue.clear();
            self.jobs.retain(|j| !matches!(j, Job::RunInput(Helper::Task(_), _, _)));
        }
    }

    pub fn task_start(&mut self, words: &str) {
        self.task_cancel();
        self.task = Some(Task {
            state: Value::Null,
            goal: words.into(),
            serial: 0,
            id: 0,
            phase: Phase::Thinking,
            scope: None,
            preparing: None,
        });
        self.task_advance(json!({}));
    }

    fn task_context(&self) -> Value {
        let providers: Vec<Value> = self
            .providers
            .iter()
            .enumerate()
            .filter(|(_, p)| p.ready && p.dead.is_none() && p.label != "files")
            .map(|(i, p)| json!({"id": i, "name": p.label}))
            .collect();
        // Only visible state is volunteered. More is read through an explicit
        // inspect decision; hidden notes, directories and networks stay out.
        let visible: Vec<Value> = self.shown().iter().map(|i| self.task_rows(*i)).collect();
        let selected = self.picks().get(self.sel).filter(|_| self.in_list).and_then(|it| match it {
            Item::Row(p, r) => self.providers.get(*p).and_then(|pr| pr.rows.rows.get(*r)).map(|row| {
                let mut value = self.task_row(*p, row);
                value["provider"] = json!(p);
                value
            }),
            _ => None,
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
        let mut scope = self.shown();
        if let Some(i) = task.scope {
            if !scope.contains(&i) {
                scope.push(i);
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
            self.task_cancel();
            let message = scrub(value["summary"].as_str().unwrap_or("the task stopped without a result"));
            // A model's completion statement is prose. Native receipts alone
            // carry the Done mark, so a fluent claim cannot impersonate proof.
            return self.say(if status == "done" || status == "answer" { Sign::Says } else { Sign::Refused }, &message);
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
                        t.scope = Some(idx);
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
                let Some(arguments) = value["step"]["arguments"].as_object().cloned() else {
                    self.task_cancel();
                    return;
                };
                let call = Call { name, arguments, ask: vec![] };
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
        let title = self.providers[prov]
            .tools
            .iter()
            .find(|t| t.name == call.name)
            .map(|t| t.title.as_str())
            .unwrap_or(&call.name);
        let placeholders = title.split_whitespace().filter(|w| w.bytes().all(|c| c.is_ascii_uppercase())).count();
        let simple = call.arguments.is_empty()
            || (call.arguments.len() == 1 && placeholders == 1 && call.arguments.values().all(|v| v.is_string() || v.is_number() || v.is_boolean()));
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
            let args = call.arguments.iter().map(|(k, v)| format!("{}={}", k, v)).collect::<Vec<_>>().join(", ");
            format!("{}: {}", label, args)
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
