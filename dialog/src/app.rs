//! The dialog's state and what moves it: a key, a provider's message, a
//! helper's answer, the clock. Drawing is ui.rs; the terminal is main.rs.

use crate::gate;
use crate::mcp::{self, Incoming, Kind, Server};
use crate::model::{self, Call, Rows, Tool};
use crate::scrub::scrub;
use serde_json::{json, Map, Value};
use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// The size, a design token: 60 by 44 cells.
pub const WIDTH: u16 = 60;
pub const HEIGHT: u16 = 44;
/// The newest lines of the exchange the window keeps.
pub const EXCHANGE_MAX: usize = 12;
/// Elicitation's caps: a provider asks at most this often (the review's M1).
pub const ASK_PER_CALL: usize = 3;
pub const ASK_PER_MINUTE: usize = 10;
/// One redraw of a provider's rows per this long, however often it says they changed.
pub const READ_GAP: Duration = Duration::from_millis(250);

/// HOME, the one root the dialog hands the files provider; an attachment must sit under it.
pub fn home() -> Option<String> {
    std::env::var("HOME").ok().filter(|h| h.starts_with('/') && h.len() > 1)
}

#[derive(Clone, Debug, PartialEq)]
pub enum Sign {
    You,
    Done,
    Refused,
    Says,
    Step,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Line {
    pub sign: Sign,
    pub text: String,
    pub undo: bool,
}

/// A pick in progress: the view to go back to and how deep the stack was,
/// the provider and tool the file goes to, and the types offered.
#[derive(Clone, Debug, PartialEq)]
pub struct Picking {
    pub back: View,
    pub depth: usize,
    pub prov: usize,
    pub tool: String,
    pub types: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum View {
    Home,
    Section(usize),
    /// A folder (or any rows resource) under a provider: its uri.
    Folder(usize, String),
    About,
    Models,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Who {
    Person,
    Model,
    Undo,
}

impl Who {
    pub fn word(&self) -> &'static str {
        match self {
            Who::Person => "person",
            Who::Model => "model",
            Who::Undo => "undo",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Step {
    pub prov: usize,
    pub call: Call,
    pub who: Who,
    pub line: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Mode {
    Normal,
    /// A destructive step waits for the typed yes.
    Confirm(Step),
    /// An argument the row leaves to the person (a name; a password, masked).
    Ask {
        step: Step,
        field: String,
        masked: bool,
    },
    /// A provider's elicitation: one flat field at a time.
    Elicit {
        prov: usize,
        id: Value,
        message: String,
        fields: Vec<(String, String)>,
        answers: Map<String, Value>,
        at: usize,
    },
    Listening,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Helper {
    Want,
    Models,
    ModelSet,
    Listen,
    Voice,
}

/// What the app asks the outside world to do; main.rs runs each in a thread.
#[derive(Clone, Debug, PartialEq)]
pub enum Job {
    Run(Helper, Vec<String>),
    StopListening,
}

#[derive(Clone, Debug)]
pub struct Provider {
    pub label: String,
    pub title: String,
    pub version: String,
    pub tools: Vec<Tool>,
    pub rows: Rows,
    pub ready: bool,
    pub dead: Option<String>,
    pub dirty: bool,
    pub reading: bool,
    pub last_read: Option<Instant>,
}

impl Provider {
    pub fn new(label: &str) -> Provider {
        Provider {
            label: label.into(),
            title: String::new(),
            version: String::new(),
            tools: vec![],
            rows: Rows::default(),
            ready: false,
            dead: None,
            dirty: false,
            reading: false,
            last_read: None,
        }
    }
}

/// What the command line chose (2.2 of the contract).
#[derive(Clone, Debug)]
pub struct Config {
    pub home: Option<String>,
    pub title: Option<String>,
    pub mark: bool,
    pub close: bool,
    pub progress: bool,
    pub plus: bool,
    pub model: bool,
    pub talk: bool,
    pub attach: Vec<String>,
    pub spark_shell: String,
    pub spark: String,
}

impl Default for Config {
    fn default() -> Config {
        Config {
            home: None,
            title: None,
            mark: false,
            close: true,
            progress: true,
            plus: false,
            model: true,
            talk: true,
            attach: vec![],
            spark_shell: String::new(),
            spark: "spark".into(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Heading(String),
    Blank,
    Undo,
    Row(usize, usize),
    /// A row of the folder shown now.
    Folder(usize),
    Model(usize),
}

pub struct App {
    pub cfg: Config,
    pub providers: Vec<Provider>,
    pub servers: Vec<Server>,
    pub view: View,
    /// The views behind this one: Esc goes back through them.
    pub came_from: Vec<View>,
    /// The folder shown now: its provider, its uri, its rows once read.
    pub folder: Option<(usize, String, Rows)>,
    /// Plus is picking a file: the view to go back to and how deep the stack was.
    pub attaching: Option<(View, usize)>,
    /// The file the next want carries (`spark-shell want --attach`).
    pub attachment: Option<String>,
    /// A row's pick is choosing a file for a tool of its own provider (the wallpaper's picture).
    pub picking: Option<Picking>,
    /// Today, (year, month, day), the machine's own clock: the calendar's today.
    pub today: Option<(i32, u32, u32)>,
    /// The calendar's month, as months from this one.
    pub month_offset: i32,
    pub mode: Mode,
    pub input: String,
    pub sel: usize,
    pub exchange: Vec<Line>,
    pub undo: Option<Step>,
    pub queue: VecDeque<Step>,
    pub running: Option<(usize, u64, Step, usize)>,
    pub busy_since: Option<Instant>,
    pub frame: u64,
    pub recent: Vec<String>,
    pub models: Vec<(String, String)>,
    pub model_name: Option<String>,
    pub voice_on: bool,
    pub thinking: bool,
    pub jobs: Vec<Job>,
    pub quit: Option<i32>,
    pub opened: bool,
    asks_this_call: usize,
    asks: VecDeque<Instant>,
    pub chip_focus: Option<usize>,
    pub about_idx: Option<usize>,
}

impl App {
    pub fn new(cfg: Config, labels: &[String]) -> App {
        let providers: Vec<Provider> = labels.iter().map(|l| Provider::new(l)).collect();
        let about_idx = providers.iter().position(|p| p.label == "about");
        let view = match cfg.home.as_deref() {
            Some("about") => View::About,
            Some(h) => providers.iter().position(|p| p.label == h).map(View::Section).unwrap_or(View::Home),
            None => View::Home,
        };
        let came_from: Vec<View> = if view == View::About { vec![View::Home] } else { vec![] }; // opened on the about (the first desktop start): Esc gives the list back
        App {
            cfg,
            providers,
            servers: vec![],
            view,
            came_from,
            folder: None,
            attaching: None,
            attachment: None,
            picking: None,
            today: None,
            month_offset: 0,
            mode: Mode::Normal,
            input: String::new(),
            sel: 0,
            exchange: vec![],
            undo: None,
            queue: VecDeque::new(),
            running: None,
            busy_since: None,
            frame: 0,
            recent: vec![],
            models: vec![],
            model_name: None,
            voice_on: false,
            thinking: false,
            jobs: vec![],
            quit: None,
            opened: false,
            asks_this_call: 0,
            asks: VecDeque::new(),
            chip_focus: None,
            about_idx,
        }
    }

    pub fn say(&mut self, sign: Sign, text: &str) {
        let text = scrub(text);
        if text.is_empty() {
            return;
        }
        self.exchange.push(Line { sign, text, undo: false });
        let n = self.exchange.len();
        if n > 200 {
            self.exchange.drain(..n - 200);
        }
    }

    pub fn busy(&self) -> bool {
        self.running.is_some() || self.thinking || self.providers.iter().any(|p| p.reading && !p.ready) || matches!(self.mode, Mode::Listening)
    }

    // ---- the providers

    /// After each server is attached: initialize it.
    pub fn start(&mut self) {
        for s in self.servers.iter_mut() {
            s.request("initialize", mcp::init_params(), Kind::Init, mcp::T_INIT);
        }
        for i in 0..self.providers.len() {
            self.providers[i].reading = true;
        }
        if self.cfg.model {
            self.jobs.push(Job::Run(
                Helper::Models,
                vec![self.cfg.spark.clone(), "model".into(), "list".into(), "--porcelain".into()],
            ));
        }
        if self.cfg.talk {
            self.jobs.push(Job::Run(Helper::Voice, vec![self.cfg.spark.clone(), "voice".into()]));
        }
    }

    fn server(&mut self, idx: usize) -> Option<&mut Server> {
        self.servers.iter_mut().find(|s| s.idx == idx && s.alive)
    }

    fn read(&mut self, idx: usize) {
        let uri = format!("spark-shell://{}/rows", self.providers[idx].label);
        if let Some(s) = self.server(idx) {
            if s.request("resources/read", json!({"uri": uri}), Kind::Read, mcp::T_READ).is_some() {
                self.providers[idx].reading = true;
                self.providers[idx].dirty = false;
                self.providers[idx].last_read = Some(Instant::now());
            }
        }
    }

    fn lose(&mut self, idx: usize, why: &str) {
        if self.providers[idx].dead.is_some() {
            return;
        }
        let label = self.providers[idx].label.clone();
        self.providers[idx].dead = Some(why.to_string());
        self.providers[idx].rows = Rows::default();
        self.providers[idx].tools.clear();
        self.providers[idx].reading = false;
        if let Some(s) = self.servers.iter_mut().find(|s| s.idx == idx) {
            s.close_stdin();
        }
        if let Some((p, _, step, _)) = self.running.clone() {
            if p == idx {
                self.running = None;
                self.say(Sign::Refused, &format!("{}: not done, {} stopped", step.line, label));
                self.next_step();
            }
        }
        self.say(Sign::Refused, &format!("{} stopped: {}", label, why));
    }

    pub fn incoming(&mut self, m: Incoming) {
        match m {
            Incoming::Gone(idx, why) => self.lose(idx, &why),
            Incoming::Msg(idx, v) => self.message(idx, v),
        }
    }

    fn message(&mut self, idx: usize, v: Value) {
        if idx >= self.providers.len() {
            return;
        }
        let method = v.get("method").and_then(Value::as_str).map(String::from);
        let id = v.get("id").cloned();
        match (method, id) {
            (Some(m), Some(id)) => self.request_from(idx, &m, id, v.get("params").cloned().unwrap_or(Value::Null)),
            (Some(m), None) => self.notification(idx, &m, v.get("params").cloned().unwrap_or(Value::Null)),
            (None, Some(id)) => self.answer(idx, id, v),
            (None, None) => {}
        }
    }

    fn notification(&mut self, idx: usize, m: &str, p: Value) {
        match m {
            "notifications/resources/updated" => self.providers[idx].dirty = true,
            "notifications/tools/list_changed" => {
                if let Some(s) = self.server(idx) {
                    s.request("tools/list", json!({}), Kind::Tools, mcp::T_LIST);
                }
            }
            "notifications/progress" => {
                let tok = p.get("progressToken").and_then(Value::as_str).unwrap_or("");
                let active = self.servers.iter().any(|s| s.idx == idx && s.token_active(tok));
                if active {
                    self.frame += 1;
                }
            }
            _ => {}
        }
    }

    fn request_from(&mut self, idx: usize, m: &str, id: Value, p: Value) {
        match m {
            "ping" => {
                if let Some(s) = self.server(idx) {
                    s.answer(&id, json!({}));
                }
            }
            "elicitation/create" => self.elicit(idx, id, p),
            "roots/list" => {
                let roots: Vec<Value> = home().map(|h| json!({"uri": format!("file://{}", h), "name": "home"})).into_iter().collect();
                if let Some(s) = self.server(idx) {
                    s.answer(&id, json!({"roots": roots}));
                }
            }
            _ => {
                if let Some(s) = self.server(idx) {
                    s.refuse(&id, -32601, "the dialog does not answer that");
                }
            }
        }
    }

    fn elicit(&mut self, idx: usize, id: Value, p: Value) {
        let now = Instant::now();
        while self.asks.front().map(|t| now.duration_since(*t) > Duration::from_secs(60)).unwrap_or(false) {
            self.asks.pop_front();
        }
        let schema = p.get("requestedSchema").cloned().unwrap_or(Value::Null);
        let props = schema.get("properties").and_then(Value::as_object).cloned().unwrap_or_default();
        let credential = props
            .iter()
            .any(|(k, v)| gate::secret(k, Some(v)) || v.get("title").and_then(Value::as_str).map(|t| gate::secret(t, None)).unwrap_or(false));
        let busy = !matches!(self.mode, Mode::Normal);
        if credential || busy || self.asks_this_call >= ASK_PER_CALL || self.asks.len() >= ASK_PER_MINUTE || props.is_empty() {
            if credential {
                self.say(Sign::Refused, &format!("{} asked for a secret: declined", self.providers[idx].label));
            }
            if let Some(s) = self.server(idx) {
                s.answer(&id, json!({"action": "decline"}));
            }
            return;
        }
        self.asks_this_call += 1;
        self.asks.push_back(now);
        let fields: Vec<(String, String)> = props
            .iter()
            .map(|(k, v)| (k.clone(), scrub(v.get("title").and_then(Value::as_str).unwrap_or(k))))
            .collect();
        let message = scrub(p.get("message").and_then(Value::as_str).unwrap_or(""));
        self.input.clear();
        self.mode = Mode::Elicit {
            prov: idx,
            id,
            message,
            fields,
            answers: Map::new(),
            at: 0,
        };
    }

    fn answer(&mut self, idx: usize, id: Value, v: Value) {
        let Some(n) = id.as_u64() else { return };
        let Some(p) = self.servers.iter_mut().find(|s| s.idx == idx).and_then(|s| s.pending.remove(&n)) else {
            return;
        };
        let result = v.get("result").cloned();
        let error = v.get("error").and_then(|e| e.get("message")).and_then(Value::as_str).map(scrub);
        match p.kind {
            Kind::Init => match result {
                Some(r) => {
                    let ver = r.get("protocolVersion").and_then(Value::as_str).unwrap_or("");
                    let name = r.pointer("/serverInfo/name").and_then(Value::as_str).unwrap_or("");
                    let label = self.providers[idx].label.clone();
                    if ver != mcp::PROTOCOL {
                        return self.lose(idx, &format!("it speaks {}, not {}", scrub(ver), mcp::PROTOCOL));
                    }
                    if name != label {
                        return self.lose(idx, "it gave another name than the one it was started as");
                    }
                    self.providers[idx].title = scrub(r.pointer("/serverInfo/title").and_then(Value::as_str).unwrap_or(""));
                    self.providers[idx].version = scrub(r.pointer("/serverInfo/version").and_then(Value::as_str).unwrap_or(""));
                    let uri = format!("spark-shell://{}/rows", label);
                    if let Some(s) = self.server(idx) {
                        s.notify("notifications/initialized", json!({}));
                        s.request("tools/list", json!({}), Kind::Tools, mcp::T_LIST);
                        s.request("resources/subscribe", json!({"uri": uri}), Kind::Subscribe, mcp::T_LIST);
                    }
                    self.read(idx);
                }
                None => self.lose(idx, &error.unwrap_or_else(|| "it would not start".into())),
            },
            Kind::Tools => {
                if let Some(r) = result {
                    self.providers[idx].tools = model::tools(&r).into_iter().filter(|t| model::title_ok(&t.title)).collect();
                }
            }
            Kind::Subscribe => {}
            Kind::Read => {
                self.providers[idx].reading = false;
                let text = result
                    .as_ref()
                    .and_then(|r| r.pointer("/contents/0/text"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if text.len() > mcp::RESOURCE_MAX {
                    return self.lose(idx, "its rows are over 256 kB");
                }
                if let Some(rows) = model::rows(text) {
                    if let Some(st) = &rows.state {
                        self.providers[idx].title = st.clone(); // the subtitle follows the section's state, step by step
                    }
                    self.providers[idx].rows = rows;
                    self.providers[idx].ready = true;
                }
            }
            Kind::Folder => {
                let text = result
                    .as_ref()
                    .and_then(|r| r.pointer("/contents/0/text"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if text.len() > mcp::RESOURCE_MAX {
                    return self.say(Sign::Refused, "that folder holds too much to show");
                }
                if let View::Folder(p, uri) = self.view.clone() {
                    if p == idx {
                        match model::rows(text) {
                            Some(rows) => self.folder = Some((p, uri, rows)),
                            None => self.say(Sign::Refused, &error.unwrap_or_else(|| "that folder could not be read".into())),
                        }
                    }
                }
            }
            Kind::Call(_) => self.called(idx, n, result, error),
        }
    }

    /// The clock: rows read again when they changed, deadlines kept.
    pub fn tick(&mut self, now: Instant) {
        if self.busy() {
            self.frame += 1;
        }
        let mut late = vec![];
        for s in self.servers.iter_mut() {
            for (_, p) in s.expired(now) {
                late.push((s.idx, p.kind));
            }
        }
        for (idx, kind) in late {
            match kind {
                Kind::Call(_) => {
                    if let Some((_, _, step, _)) = self.running.take() {
                        self.say(Sign::Refused, &format!("{}: no answer in {} s", step.line, mcp::T_CALL.as_secs()));
                        self.next_step();
                    }
                }
                Kind::Read => self.providers[idx].reading = false,
                Kind::Init => self.lose(idx, "it did not answer"),
                _ => {}
            }
        }
        for i in 0..self.providers.len() {
            let p = &self.providers[i];
            if p.dirty && !p.reading && p.last_read.map(|t| now.duration_since(t) >= READ_GAP).unwrap_or(true) {
                self.read(i);
            }
        }
    }

    // ---- the list

    fn matches(&self, prov: usize, row: &model::Row) -> bool {
        let hay = format!("{} {}", self.providers[prov].label, row.text).to_lowercase();
        self.input.to_lowercase().split_whitespace().all(|w| hay.contains(w))
    }

    fn pickable(row: &model::Row) -> bool {
        row.tool.is_some() || row.children.is_some()
    }

    /// The content area's items, in order: the undo, the recent picks, then each provider's rows under its heading.
    pub fn items(&self) -> Vec<Item> {
        let mut out = vec![];
        match &self.view {
            View::Models => {
                out.push(Item::Heading("models".into()));
                for i in 0..self.models.len() {
                    out.push(Item::Model(i));
                }
            }
            View::About => {}
            View::Folder(..) => {
                let Some((p, _, rows)) = &self.folder else { return out };
                for (i, r) in rows.rows.iter().enumerate() {
                    if !self.input.is_empty() && !self.matches(*p, r) {
                        continue;
                    }
                    // attaching or picking, the files offered are of the types asked; the summary goes
                    let types = match (&self.picking, &self.attaching) {
                        (Some(pk), _) => Some(&pk.types),
                        (None, Some(_)) => Some(&self.cfg.attach),
                        _ => None,
                    };
                    if let Some(t) = types {
                        if r.children.is_none() && r.tool.is_some() {
                            let ext = r.text.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
                            if !t.contains(&ext) {
                                continue;
                            }
                        }
                        if r.tool.is_none() && r.children.is_none() {
                            continue;
                        }
                    }
                    if i + 1 == rows.rows.len() && i > 0 && r.tool.is_none() && r.children.is_none() {
                        out.push(Item::Blank); // the summary at the end stands apart
                    }
                    out.push(Item::Folder(i));
                }
            }
            View::Section(p) => {
                let mut group: Option<String> = None;
                for (i, r) in self.providers[*p].rows.rows.iter().enumerate() {
                    if r.children.as_deref() == Some(&format!("spark-shell://{}/rows", self.providers[*p].label)) {
                        continue;
                    }
                    if !self.input.is_empty() && !self.matches(*p, r) {
                        continue;
                    }
                    if r.group != group {
                        if group.is_some() || !out.is_empty() {
                            out.push(Item::Blank);
                        }
                        if let Some(g) = &r.group {
                            out.push(Item::Heading(g.clone()));
                        }
                        group = r.group.clone();
                    }
                    out.push(Item::Row(*p, i));
                }
            }
            View::Home => {
                let searching = !self.input.trim().is_empty();
                let mut shown: Vec<(usize, usize)> = vec![];
                if !searching {
                    if self.undo.is_some() {
                        out.push(Item::Heading("undo".into()));
                        out.push(Item::Undo);
                    }
                    let mut recent = vec![];
                    for id in &self.recent {
                        for (p, prov) in self.providers.iter().enumerate() {
                            if let Some(i) = prov.rows.rows.iter().position(|r| &r.id == id && Self::pickable(r)) {
                                recent.push((p, i));
                            }
                        }
                    }
                    if !recent.is_empty() {
                        if !out.is_empty() {
                            out.push(Item::Blank);
                        }
                        out.push(Item::Heading("recent".into()));
                        for (p, i) in recent {
                            out.push(Item::Row(p, i));
                            shown.push((p, i));
                        }
                    }
                }
                for (p, prov) in self.providers.iter().enumerate() {
                    let rows: Vec<usize> = prov
                        .rows
                        .rows
                        .iter()
                        .enumerate()
                        .filter(|(i, r)| {
                            Self::pickable(r)
                                && if searching {
                                    // the about's own row is found; its key sentences stay out of a search
                                    self.matches(p, r) && (Some(p) != self.about_idx || r.tool.as_ref().is_some_and(|t| t.name == "about_open"))
                                } else {
                                    prov.rows.short.contains(&r.id) && !shown.contains(&(p, *i))
                                }
                        })
                        .map(|(i, _)| i)
                        .collect();
                    if rows.is_empty() {
                        continue;
                    }
                    if !out.is_empty() {
                        out.push(Item::Blank);
                    }
                    out.push(Item::Heading(prov.label.clone()));
                    for i in rows {
                        out.push(Item::Row(p, i));
                    }
                }
            }
        }
        out
    }

    pub fn picks(&self) -> Vec<Item> {
        self.items()
            .into_iter()
            .filter(|i| match i {
                Item::Row(p, r) => Self::pickable(&self.providers[*p].rows.rows[*r]),
                Item::Folder(i) => self
                    .folder
                    .as_ref()
                    .and_then(|(_, _, rows)| rows.rows.get(*i))
                    .map(Self::pickable)
                    .unwrap_or(false),
                Item::Undo | Item::Model(_) => true,
                _ => false,
            })
            .collect()
    }

    // ---- keys

    pub fn up(&mut self) {
        self.sel = self.sel.saturating_sub(1);
    }

    pub fn down(&mut self) {
        let n = self.picks().len();
        if self.sel + 1 < n {
            self.sel += 1;
        }
    }

    pub fn typed(&mut self, c: char) {
        if c.is_control() {
            return;
        }
        self.chip_focus = None;
        if self.input.chars().count() < 400 {
            self.input.push(c);
        }
        if matches!(self.mode, Mode::Normal) {
            self.sel = 0;
        }
    }

    pub fn backspace(&mut self) {
        self.input.pop();
        if matches!(self.mode, Mode::Normal) {
            self.sel = 0;
        }
    }

    /// Esc: a question waiting is answered no; the about or the models go back; else the dialog closes.
    pub fn escape(&mut self) {
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            Mode::Confirm(step) => {
                self.say(Sign::Refused, &format!("{}: kept, not done", step.line));
                self.input.clear();
                self.next_step();
            }
            Mode::Ask { step, .. } => {
                self.say(Sign::Refused, &format!("{}: not done", step.line));
                self.input.clear();
                self.next_step();
            }
            Mode::Elicit { prov, id, .. } => {
                if let Some(s) = self.server(prov) {
                    s.answer(&id, json!({"action": "cancel"}));
                }
                self.input.clear();
            }
            Mode::Listening => {
                self.jobs.push(Job::StopListening);
            }
            Mode::Normal => {
                if self.chip_focus.is_some() {
                    self.chip_focus = None;
                } else if !self.input.is_empty() {
                    self.input.clear();
                    self.sel = 0;
                } else if let Some(v) = self.came_from.pop() {
                    self.view = v;
                    self.sel = 0;
                    if self.attaching.as_ref().map(|(_, d)| self.came_from.len() < *d + 1).unwrap_or(false) {
                        self.attaching = None;
                    }
                    if self.picking.as_ref().map(|pk| self.came_from.len() < pk.depth + 1).unwrap_or(false) {
                        self.picking = None;
                    }
                    if !matches!(self.view, View::Folder(..)) {
                        self.folder = None;
                    } else if let View::Folder(p, uri) = self.view.clone() {
                        self.read_folder(p, &uri);
                    }
                } else {
                    self.quit = Some(0);
                }
            }
        }
    }

    pub fn enter(&mut self) {
        let typed = std::mem::take(&mut self.input);
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            Mode::Confirm(step) => {
                if typed.trim() == "yes" {
                    self.call(step);
                } else {
                    self.say(Sign::Refused, &format!("{}: kept, not done (it takes yes)", step.line));
                    self.next_step();
                }
                return;
            }
            Mode::Ask { mut step, field, .. } => {
                if typed.is_empty() {
                    self.say(Sign::Refused, &format!("{}: not done, no {}", step.line, field));
                    self.next_step();
                    return;
                }
                step.call.arguments.insert(field.clone(), Value::String(typed));
                step.call.ask.retain(|a| a != &field);
                self.run(step);
                return;
            }
            Mode::Elicit {
                prov,
                id,
                message,
                fields,
                mut answers,
                at,
            } => {
                let (k, _) = &fields[at];
                answers.insert(k.clone(), Value::String(typed.clone()));
                self.say(Sign::You, &format!("{} {}", self.providers[prov].label, typed));
                if at + 1 < fields.len() {
                    self.mode = Mode::Elicit {
                        prov,
                        id,
                        message,
                        fields,
                        answers,
                        at: at + 1,
                    };
                } else if let Some(s) = self.server(prov) {
                    s.answer(&id, json!({"action": "accept", "content": answers}));
                }
                return;
            }
            Mode::Listening => {
                self.mode = Mode::Listening;
                self.input = typed;
                return;
            }
            Mode::Normal => {}
        }
        if let Some(c) = self.chip_focus {
            self.input = typed;
            self.chip(c);
            return;
        }
        if self.view == View::About && typed.trim().is_empty() {
            return;
        }
        // a section's own name typed alone opens that section, never the model ("about" once opened aerc)
        if matches!(self.view, View::Home | View::Section(_)) && self.sel == 0 {
            let word = typed.trim().to_lowercase();
            let word = if word == "calendar" { "clock".to_string() } else { word }; // the clock section is the Calendar
            if let Some(q) = self.providers.iter().position(|x| x.label == word && x.ready && x.dead.is_none()) {
                if self.view != View::Section(q) {
                    self.open_children(q, &format!("spark-shell://{}/rows", word));
                }
                return;
            }
        }
        self.input = typed.clone(); // the list the person saw, filtered by what they typed
        let picks = self.picks();
        self.input.clear();
        self.sel = self.sel.min(picks.len().saturating_sub(1));
        let sel = self.sel;
        self.sel = 0;
        if !typed.trim().is_empty() && (picks.is_empty() || self.view == View::About) {
            return self.want(typed.trim());
        }
        let Some(item) = picks.get(sel).cloned() else { return };
        match item {
            Item::Undo => {
                if let Some(u) = self.undo.take() {
                    self.run(u);
                }
            }
            Item::Model(i) => {
                let name = self.models[i].0.clone();
                self.say(Sign::Step, &format!("model {}", name));
                self.thinking = true;
                self.jobs.push(Job::Run(Helper::ModelSet, vec![self.cfg.spark.clone(), "model".into(), name]));
                self.view = self.came_from.pop().unwrap_or(View::Home);
                self.sel = 0;
            }
            Item::Row(p, r) => {
                let row = self.providers[p].rows.rows[r].clone();
                if let Some(pk) = &row.pick {
                    // a pick opens the files at the home folder, offering the types it takes
                    let Some(f) = self.files() else {
                        return self.say(Sign::Refused, "no files to pick from");
                    };
                    let Some(root) = self.providers[f].rows.rows.iter().find_map(|r| r.children.clone()) else {
                        return self.say(Sign::Refused, "no folder to pick from");
                    };
                    self.picking = Some(Picking {
                        back: self.view.clone(),
                        depth: self.came_from.len(),
                        prov: p,
                        tool: pk.tool.clone(),
                        types: pk.types.clone(),
                    });
                    self.open_children(f, &root);
                } else if let Some(c) = row.children {
                    self.open_children(p, &c);
                } else if let Some(call) = row.tool {
                    if call.name == "about_open" {
                        self.came_from.push(self.view.clone());
                        self.view = View::About;
                        self.sel = 0;
                        return;
                    }
                    let line = format!("{} {}", self.providers[p].label, row.text);
                    self.run(Step {
                        prov: p,
                        call,
                        who: Who::Person,
                        line,
                    });
                }
            }
            Item::Folder(i) => {
                let Some((p, _, rows)) = self.folder.clone() else { return };
                let Some(row) = rows.rows.get(i).cloned() else { return };
                if let Some(c) = row.children {
                    self.open_children(p, &c);
                    return;
                }
                if let Some(pk) = self.picking.clone() {
                    // the file picked goes to the tool the pick names, at its own provider; the shell checks the path
                    let Some(path) = row.tool.as_ref().and_then(|t| t.arguments.get("path")).and_then(Value::as_str) else {
                        return;
                    };
                    let mut arguments = serde_json::Map::new();
                    arguments.insert("path".into(), Value::String(path.to_string()));
                    self.picking = None;
                    self.came_from.truncate(pk.depth);
                    self.view = pk.back;
                    self.folder = None;
                    self.sel = 0;
                    let line = format!("{} {}", self.providers[pk.prov].label, row.text);
                    self.run(Step {
                        prov: pk.prov,
                        call: Call {
                            name: pk.tool,
                            arguments,
                            ask: vec![],
                        },
                        who: Who::Person,
                        line,
                    });
                    return;
                }
                let call = if self.attaching.is_some() {
                    row.more.iter().find(|m| m.name.ends_with("_attach")).cloned()
                } else {
                    row.tool.clone()
                };
                if let Some(call) = call {
                    let line = format!("{} {}", self.providers[p].label, row.text);
                    self.run(Step {
                        prov: p,
                        call,
                        who: Who::Person,
                        line,
                    });
                }
            }
            _ => {}
        }
    }

    /// A row's children: a provider's own rows (its section), or one of its folders.
    fn open_children(&mut self, from: usize, uri: &str) {
        let rest = uri.strip_prefix("spark-shell://").unwrap_or("");
        let (label, tail) = rest.split_once('/').unwrap_or((rest, ""));
        let Some(q) = self.providers.iter().position(|x| x.label == label) else {
            return;
        };
        let _ = from;
        self.came_from.push(self.view.clone());
        self.sel = 0;
        if tail == "rows" {
            self.view = if Some(q) == self.about_idx { View::About } else { View::Section(q) };
            self.month_offset = 0; // the calendar opens on this month
        } else if tail.starts_with("rows/") {
            self.view = View::Folder(q, uri.to_string());
            self.read_folder(q, uri);
        }
    }

    fn read_folder(&mut self, p: usize, uri: &str) {
        self.folder = None;
        if let Some(s) = self.server(p) {
            s.request("resources/read", json!({"uri": uri}), Kind::Folder, mcp::T_READ);
        }
    }

    /// The files provider, when one is running and handed a root.
    fn files(&self) -> Option<usize> {
        self.providers.iter().position(|p| p.label == "files" && p.dead.is_none())
    }

    /// The chips: 0 plus, 1 the model, 2 talk.
    pub fn chip(&mut self, c: usize) {
        self.chip_focus = None;
        match c {
            0 if self.cfg.plus => {
                if let Some(a) = self.attachment.take() {
                    let name = a.rsplit('/').next().unwrap_or("").to_string();
                    self.say(Sign::Done, &format!("{} no longer attached", name));
                    return;
                }
                let Some(f) = self.files() else { return };
                let Some(root) = self.providers[f].rows.rows.iter().find_map(|r| r.children.clone()) else {
                    return self.say(Sign::Refused, "no folder to attach from");
                };
                self.attaching = Some((self.view.clone(), self.came_from.len()));
                self.open_children(f, &root);
            }
            1 if self.cfg.model => {
                self.came_from.push(self.view.clone());
                self.view = View::Models;
                self.sel = self.models.iter().position(|(_, s)| s == "serving").unwrap_or(0);
            }
            2 if self.cfg.talk && self.voice_on => {
                if self.mode == Mode::Listening {
                    self.jobs.push(Job::StopListening);
                } else if self.mode == Mode::Normal {
                    self.mode = Mode::Listening;
                    self.jobs.push(Job::Run(
                        Helper::Listen,
                        vec![self.cfg.spark.clone(), "voice".into(), "listen".into(), "--buffer".into()],
                    ));
                }
            }
            _ => {}
        }
    }

    pub fn chips(&self) -> Vec<usize> {
        let mut v = vec![];
        if self.cfg.plus && self.files().is_some() {
            v.push(0);
        }
        if self.cfg.model && self.model_name.is_some() {
            v.push(1);
        }
        if self.cfg.talk && self.voice_on {
            v.push(2);
        }
        v
    }

    pub fn tab(&mut self) {
        let c = self.chips();
        if c.is_empty() {
            return;
        }
        self.chip_focus = match self.chip_focus {
            None => Some(c[0]),
            Some(f) => c.iter().position(|x| *x == f).and_then(|i| c.get(i + 1)).copied(),
        };
    }

    // ---- the want and the steps

    fn want(&mut self, words: &str) {
        self.say(Sign::You, words);
        if self.cfg.spark_shell.is_empty() {
            return self.say(Sign::Refused, "no spark-shell to read the words");
        }
        self.thinking = true;
        let mut argv = vec![self.cfg.spark_shell.clone(), "want".into(), "--json".into()];
        if let Some(a) = self.attachment.take() {
            argv.push("--attach".into());
            argv.push(a);
        }
        argv.push("--".into());
        argv.push(words.to_string());
        self.jobs.push(Job::Run(Helper::Want, argv));
    }

    /// The plan from `spark-shell want --json`: each step gated here too, then run in order.
    pub fn plan(&mut self, text: &str) {
        self.thinking = false;
        let Ok(v) = serde_json::from_str::<Value>(text) else {
            return self.say(Sign::Refused, "the answer was not a plan");
        };
        if let Some(a) = v.get("answer").and_then(Value::as_str) {
            if !a.trim().is_empty() {
                self.say(Sign::Says, a);
            }
        }
        for r in v.get("refused").and_then(Value::as_array).cloned().unwrap_or_default() {
            if let Some(t) = r.as_str() {
                self.say(Sign::Refused, t.trim_start_matches('\u{2717}').trim());
            }
        }
        for s in v.get("steps").and_then(Value::as_array).cloned().unwrap_or_default() {
            let Some(name) = s.get("name").and_then(Value::as_str) else { continue };
            let arguments = s.get("arguments").and_then(Value::as_object).cloned().unwrap_or_default();
            let line = scrub(s.get("line").and_then(Value::as_str).unwrap_or(name));
            // two steps are the dialog's own: undo is its undo row, about opens its about
            if name == "undo_all" {
                match self.undo.take() {
                    Some(u) => self.queue.push_back(u),
                    None => self.say(Sign::Refused, "nothing to undo"),
                }
                continue;
            }
            if name == "about_open" {
                if self.about_idx.is_some() {
                    self.came_from.push(self.view.clone());
                    self.view = View::About;
                    self.sel = 0;
                } else {
                    self.say(Sign::Refused, &format!("{}: not a step here now", line));
                }
                continue;
            }
            let call = Call {
                name: name.to_string(),
                arguments,
                ask: vec![],
            };
            match self.providers.iter().position(|p| p.tools.iter().any(|t| t.name == name)) {
                None => self.say(Sign::Refused, &format!("{}: not a step here now", line)),
                Some(p) => match gate::step(&self.providers[p].tools, &self.providers[p].rows, &call) {
                    Ok(()) => self.queue.push_back(Step {
                        prov: p,
                        call,
                        who: Who::Model,
                        line,
                    }),
                    Err(e) => self.say(Sign::Refused, &format!("{}: {}", line, e)),
                },
            }
        }
        if self.running.is_none() && self.mode == Mode::Normal {
            self.next_step();
        }
    }

    fn next_step(&mut self) {
        if self.running.is_some() || self.mode != Mode::Normal {
            return;
        }
        if let Some(s) = self.queue.pop_front() {
            self.run(s);
        } else if self.opened {
            self.quit = Some(3);
        }
    }

    /// A step: its line drawn, an argument asked when it lacks one, a typed yes when it is destructive, then the call.
    pub fn run(&mut self, step: Step) {
        if let Some(field) = step.call.ask.first().cloned() {
            let masked = gate::secret(&field, self.tool_of(&step).and_then(|t| t.schema.pointer(&format!("/properties/{}", field))));
            self.mode = Mode::Ask { step, field, masked };
            return;
        }
        let Some(tool) = self.tool_of(&step).cloned() else {
            self.say(Sign::Refused, &format!("{}: not a step here now", step.line));
            return self.next_step();
        };
        if step.who != Who::Person {
            if let Err(e) = gate::step(&self.providers[step.prov].tools, &self.providers[step.prov].rows, &step.call) {
                self.say(Sign::Refused, &format!("{}: {}", step.line, e));
                return self.next_step();
            }
        }
        if step.who == Who::Model {
            self.say(Sign::Step, &step.line);
        }
        if tool.destructive {
            self.mode = Mode::Confirm(step);
            return;
        }
        self.call(step);
    }

    fn tool_of(&self, step: &Step) -> Option<&Tool> {
        self.providers.get(step.prov)?.tools.iter().find(|t| t.name == step.call.name)
    }

    fn call(&mut self, step: Step) {
        let params = json!({"name": step.call.name, "arguments": Value::Object(step.call.arguments.clone())});
        let idx = step.prov;
        let n = self
            .servers
            .iter_mut()
            .find(|s| s.idx == idx && s.alive)
            .and_then(|s| s.request("tools/call", params, Kind::Call(0), mcp::T_CALL));
        match n {
            Some(id) => {
                self.asks_this_call = 0;
                self.running = Some((idx, id, step, self.exchange.len()));
            }
            None => {
                self.say(Sign::Refused, &format!("{}: not done, its provider is gone", step.line));
                self.next_step();
            }
        }
    }

    fn called(&mut self, idx: usize, n: u64, result: Option<Value>, error: Option<String>) {
        match &self.running {
            Some((p, id, _, _)) if *p == idx && *id == n => {}
            _ => return,
        }
        let Some((_, _, step, _)) = self.running.take() else { return };
        let schema = self.tool_of(&step).map(|t| t.schema.clone()).unwrap_or(Value::Null);
        let refused = error.is_some() || result.as_ref().and_then(|r| r.get("isError")).and_then(Value::as_bool).unwrap_or(false);
        crate::audit::record(
            step.who.word(),
            &self.providers[idx].label,
            &step.call.name,
            &schema,
            &step.call.arguments,
            refused,
        );
        if let Some(e) = error {
            self.say(Sign::Refused, &format!("{}: {}", step.line, e));
        } else if let Some(r) = result {
            let text = r.pointer("/content/0/text").and_then(Value::as_str).unwrap_or("");
            if refused {
                self.say(Sign::Refused, text);
            } else {
                let sc = r.get("structuredContent").cloned().unwrap_or(Value::Null);
                if let Some(path) = sc.get("attach").and_then(Value::as_str) {
                    let under = home().map(|h| path.starts_with(&format!("{}/", h))).unwrap_or(false);
                    if under && !path.split('/').any(|c| c == ".." || c.starts_with('.')) {
                        self.attachment = Some(path.to_string());
                        if let Some((v, depth)) = self.attaching.take() {
                            self.came_from.truncate(depth);
                            self.view = v;
                            self.folder = None;
                            self.sel = 0;
                            if let View::Folder(p, uri) = self.view.clone() {
                                self.read_folder(p, &uri);
                            }
                        }
                    } else {
                        self.say(Sign::Refused, "that file is not under your home: not attached");
                    }
                }
                if sc.get("opened").and_then(Value::as_bool) == Some(true) {
                    self.opened = true;
                } else {
                    let receipt = sc.get("receipt").and_then(Value::as_str).unwrap_or(text).to_string();
                    for (i, l) in receipt.lines().enumerate() {
                        if i == 0 {
                            self.say(Sign::Done, l);
                        } else {
                            self.say(Sign::Says, l);
                        }
                    }
                }
                self.undo = None;
                if let Some(u) = sc.get("undo") {
                    if let (Some(name), Some(args)) = (u.get("name").and_then(Value::as_str), u.get("arguments").and_then(Value::as_object)) {
                        let call = Call {
                            name: name.to_string(),
                            arguments: args.clone(),
                            ask: vec![],
                        };
                        let carries_secret = args.keys().any(|k| gate::secret(k, schema.pointer(&format!("/properties/{}", k))));
                        if !carries_secret {
                            let line = format!("undo {}", step.line);
                            self.undo = Some(Step {
                                prov: idx,
                                call,
                                who: Who::Undo,
                                line,
                            });
                            if let Some(l) = self.exchange.last_mut() {
                                l.undo = true;
                            }
                        }
                    }
                }
                if step.who == Who::Person {
                    let id = self.providers[idx]
                        .rows
                        .rows
                        .iter()
                        .find(|r| {
                            r.tool
                                .as_ref()
                                .map(|t| t.name == step.call.name && t.arguments == step.call.arguments)
                                .unwrap_or(false)
                        })
                        .map(|r| r.id.clone());
                    if let Some(id) = id {
                        self.recent.retain(|x| x != &id);
                        self.recent.insert(0, id);
                        self.recent.truncate(5);
                    }
                }
            }
        }
        self.providers[idx].dirty = true;
        self.next_step();
    }

    /// A helper's answer: the plan, the model list, the model set, the words heard, the voice's state.
    pub fn helper(&mut self, h: Helper, out: Result<String, String>) {
        match h {
            Helper::Want => match out {
                Ok(t) => self.plan(&t),
                Err(e) => {
                    self.thinking = false;
                    match serde_json::from_str::<Value>(&e) {
                        Ok(_) => self.plan(&e),
                        Err(_) => self.say(Sign::Refused, e.lines().next().unwrap_or("spark did not answer")),
                    }
                }
            },
            Helper::Models => {
                if let Ok(t) = out {
                    self.models = t
                        .lines()
                        .filter_map(|l| {
                            let f: Vec<&str> = l.split('\t').collect();
                            let name = scrub(f.first()?);
                            let state = scrub(f.last()?);
                            (state == "serving" || state == "downloaded").then_some((name, state))
                        })
                        .collect();
                    self.model_name = self.models.iter().find(|(_, s)| s == "serving").map(|(n, _)| n.clone());
                }
            }
            Helper::ModelSet => {
                self.thinking = false;
                match out {
                    Ok(_) => {
                        self.say(Sign::Done, "model changed");
                        self.jobs.push(Job::Run(
                            Helper::Models,
                            vec![self.cfg.spark.clone(), "model".into(), "list".into(), "--porcelain".into()],
                        ));
                    }
                    Err(e) => self.say(Sign::Refused, e.lines().last().unwrap_or("the model stays")),
                }
            }
            Helper::Listen => {
                if self.mode == Mode::Listening {
                    self.mode = Mode::Normal;
                }
                match out {
                    Ok(t) => {
                        let heard = scrub(t.trim());
                        if !heard.is_empty() {
                            self.input = heard;
                        }
                    }
                    Err(e) => self.say(Sign::Refused, e.lines().next().unwrap_or("nothing heard")),
                }
            }
            Helper::Voice => {
                if let Ok(t) = out {
                    self.voice_on = t
                        .lines()
                        .next()
                        .map(|l| !l.split_whitespace().nth(1).unwrap_or("off").starts_with("off"))
                        .unwrap_or(false);
                }
            }
        }
    }

    // ---- what the window says

    pub fn title(&self, clock: &str) -> String {
        if let Some(t) = &self.cfg.title {
            return scrub(t);
        }
        match &self.view {
            View::Home => clock.to_string(),
            View::Section(p) | View::Folder(p, _) => self.providers[*p].label.clone(),
            View::About => "spark-shell".into(),
            View::Models => "model".into(),
        }
    }

    pub fn subtitle(&self) -> String {
        match &self.view {
            View::Section(p) => self.providers[*p].title.clone(),
            View::Folder(..) => self.folder.as_ref().map(|(_, _, r)| r.title.clone()).unwrap_or_default(),
            View::About => self.about_idx.map(|i| self.providers[i].version.clone()).unwrap_or_default(),
            _ => String::new(),
        }
    }

    pub fn hint(&self) -> Vec<(String, bool)> {
        let esc = |w: &str| vec![(" \u{b7} ".to_string(), false), ("Esc".to_string(), true), (format!(" {}", w), false)];
        let mut v: Vec<(String, bool)> = match &self.mode {
            Mode::Confirm(s) => {
                let mut v = vec![(format!("type yes to {}", s.line), false)];
                v.extend(esc("keeps it"));
                return v;
            }
            Mode::Ask { step, field, masked } => {
                // the argument's own description when its tool gives one ("when and what: fri 9am call the vet")
                let said = self
                    .tool_of(step)
                    .and_then(|t| t.schema.pointer(&format!("/properties/{}/description", field)))
                    .and_then(Value::as_str)
                    .map(str::to_string);
                let what = if *masked {
                    format!("the {} for {}, not shown", field, step.line)
                } else if let Some(d) = said {
                    d
                } else {
                    format!("the {} for {}", field, step.line)
                };
                let mut v = vec![(what, false)];
                v.extend(esc("cancels"));
                return v;
            }
            Mode::Elicit { prov, message, fields, at, .. } => {
                let m = if message.is_empty() {
                    fields[*at].1.clone()
                } else {
                    format!("{}: {}", message, fields[*at].1)
                };
                let mut v = vec![(format!("{} asks: {}", self.providers[*prov].label, m), false)];
                v.extend(esc("declines"));
                return v;
            }
            Mode::Listening => {
                let mut v = vec![("listening, a pause ends it".to_string(), false)];
                v.extend(esc("stops"));
                return v;
            }
            Mode::Normal => vec![],
        };
        if self.attaching.is_some() {
            v.push((format!("pick a file to attach ({})", self.cfg.attach.join(" ")), false));
            v.extend(esc("cancels"));
            return v;
        }
        if let Some(pk) = &self.picking {
            v.push((format!("pick a picture ({})", pk.types.join(" ")), false));
            v.extend(esc("cancels"));
            return v;
        }
        // the keys, no words for them: the arrows where there is something to pick, the month's in the calendar
        if self.is_calendar() {
            v.push(("\u{2190}\u{2192}".into(), true));
            v.push((" month".into(), false));
        } else if self.view != View::About {
            v.push(("\u{2191}\u{2193}".into(), true));
        }
        // Esc goes back one view where there is one to go back to, and closes from the first
        let word = if self.came_from.is_empty() { "closes" } else { "goes back" };
        if v.is_empty() {
            v.push(("Esc".into(), true));
            v.push((format!(" {}", word), false));
        } else {
            v.extend(esc(word));
        }
        v
    }

    /// The clock section is the calendar.
    pub fn is_calendar(&self) -> bool {
        matches!(self.view, View::Section(p) if self.providers.get(p).map(|x| x.label == "clock").unwrap_or(false))
    }

    /// Left and right: the calendar's month back or on; nothing elsewhere.
    pub fn month(&mut self, d: i32) {
        if self.is_calendar() {
            self.month_offset += d;
        }
    }
}
