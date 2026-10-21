//! The dialog's state and what moves it: a key, a provider's message, a
//! helper's answer, the clock. Drawing is ui.rs; the terminal is main.rs.

use crate::gate;
use crate::mcp::{self, Incoming, Kind, Server};
use crate::model::{self, Call, Rows, Tool};
use crate::scrub::scrub;
use serde_json::{json, Map, Value};
use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// The size, a design token: 60 by 40 cells, 3:4 in a 9 by 18 pixel cell. The window may be smaller:
/// the drawing takes the terminal's own size, MIN_WIDTH by MIN_HEIGHT at least.
pub const WIDTH: u16 = 60;
pub const HEIGHT: u16 = 40;
pub const MIN_WIDTH: u16 = 36;
pub const MIN_HEIGHT: u16 = 20;
/// The newest lines of the exchange the content area shows, newest turn first.
pub const EXCHANGE_MAX: usize = 10;
/// The draft's length, in characters.
pub const INPUT_MAX: usize = 2000;
/// What the prompt says while it is empty.
pub const PLACEHOLDER: &str = "Type a request.";
/// Steps this machine counts as risky whatever their provider says (the hint is the provider's word,
/// the risk is decided here): a saved password gone, a window closed with its work, a layout written
/// over, a new device trusted.
pub const LOCAL_RISK: [&str; 4] = ["wifi_forget", "window_close", "layout_save", "bt_pair"];

/// The home's destinations: a name, what it is for, the sections it holds. Home rows are places;
/// commands are verbs; AI is what the prompt does, not a place.
pub struct Dest {
    pub name: &'static str,
    pub purpose: &'static str,
    pub sections: &'static [&'static str],
}
pub const DESTS: [Dest; 6] = [
    Dest {
        name: "Apps",
        purpose: "Open an application",
        sections: &["apps"],
    },
    Dest {
        name: "Files",
        purpose: "Browse your home",
        sections: &["files"],
    },
    Dest {
        name: "Workspace",
        purpose: "Windows and layouts",
        sections: &["window", "layout"],
    },
    Dest {
        name: "Notes",
        purpose: "Write and find",
        sections: &["notes"],
    },
    Dest {
        name: "Calendar",
        purpose: "Dates and reminders",
        sections: &["clock", "reminders"],
    },
    Dest {
        name: "Settings",
        purpose: "Devices and appearance",
        sections: &[],
    },
];
pub const SETTINGS_DEST: usize = 5;
pub const CALENDAR_DEST: usize = 4;
/// Settings: a section each, then Connections and About, in this order.
pub const SETTINGS: [(&str, &str, &str); 14] = [
    ("out", "Sound", "Output and volume"),
    ("mic", "Microphone", "Input and level"),
    ("wifi", "Wi-Fi", "Networks"),
    ("bt", "Bluetooth", "Devices nearby"),
    ("lan", "Network", "The wired connection"),
    ("display", "Display", "Screens, brightness, lock"),
    ("keyboard", "Keyboard", "Layouts"),
    ("theme", "Theme", "Palette and font"),
    ("wallpaper", "Wallpaper", "The desktop picture"),
    ("bar", "Bar", "The status bar"),
    ("bat", "Battery", "Charge"),
    ("talk", "Talk", "Click the mic, or off"),
    ("connections", "Connections", "Tools and the model"),
    ("about", "About", "Version and keys"),
];
/// Elicitation's caps: a provider asks at most this often (the review's M1).
pub const ASK_PER_CALL: usize = 3;
pub const ASK_PER_MINUTE: usize = 10;
/// One redraw of a provider's rows per this long, however often it says they changed.
pub const READ_GAP: Duration = Duration::from_millis(250);

/// HOME, the one root the dialog hands the files provider; an attachment must sit under it.
pub fn home() -> Option<String> {
    std::env::var("HOME").ok().filter(|h| h.starts_with('/') && h.len() > 1)
}

fn state_dir() -> Option<std::path::PathBuf> {
    let base = std::env::var("XDG_STATE_HOME")
        .ok()
        .filter(|s| s.starts_with('/'))
        .or_else(|| home().map(|h| h + "/.local/state"))?;
    Some(std::path::PathBuf::from(base).join("spark-shell").join("dialog"))
}

/// A section's name as a person reads it: Settings' names, and the places' own.
pub fn section_name(label: &str) -> String {
    if let Some((_, n, _)) = SETTINGS.iter().find(|(s, _, _)| *s == label) {
        return n.to_string();
    }
    match label {
        "window" => "Windows".into(),
        "layout" => "Layouts".into(),
        "clock" => "Calendar".into(),
        l => {
            let mut c = l.chars();
            c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
        }
    }
}

/// How talk works, as the person last chose it: click to talk unless they turned it off.
pub fn talk_kept() -> Talk {
    let said = state_dir().and_then(|d| std::fs::read_to_string(d.join("talk")).ok()).unwrap_or_default();
    if said.trim() == "off" {
        Talk::Off
    } else {
        Talk::Click
    }
}

fn talk_keep(t: Talk) {
    use std::os::unix::fs::DirBuilderExt;
    let Some(d) = state_dir() else { return };
    let _ = std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&d);
    let _ = std::fs::write(d.join("talk"), if t == Talk::Off { "off\n" } else { "click\n" });
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
    /// A destination of the home that holds more than one section, or none (Settings).
    Dest(usize),
    Section(usize),
    /// A folder (or any rows resource) under a provider: its uri.
    Folder(usize, String),
    About,
    Models,
    /// How talk works: click to talk, or off.
    Talk,
    /// Settings > Connections: the tools the dialog talks to, and where the model runs.
    Connections,
}

/// How the person talks to the prompt. Hold Space waits for a spark that can finish a recording on a
/// signal; until then it is shown, and not offered.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Talk {
    Click,
    Off,
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
    /// A model picked: Enter applies it, Esc keeps the one in use.
    Apply(String),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Helper {
    Want,
    Models,
    ModelSet,
    Listen,
    Voice,
    Client,
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
    /// A destination of the home.
    Dest(usize),
    /// A row of Settings: its index in SETTINGS.
    Setting(usize),
    /// A line of the exchange as drawn: its sign, the words, the first of its lines.
    Said(Sign, String, bool),
    /// A step the model proposed for a question: it runs only when picked.
    Proposal(usize),
    /// A way to talk.
    TalkOpt(Talk),
    /// A section's name over its rows, where a view holds more than one section.
    Title(String),
    /// A line that says something and opens nothing: (words, muted).
    Text(String, bool),
    /// A provider the dialog talks to, in Connections.
    Provider(usize),
    /// Connections' row that opens the models.
    OpenModels,
    /// Where the model runs: 0 the one in use (this computer, or the server spark is a client of);
    /// 1 the ones to come (another server, a cloud provider), shown and not offered.
    Conn(usize),
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
    /// The draft; a newline in it is Shift+Enter's, never a send.
    pub input: String,
    /// The cursor in the draft, in characters.
    pub cursor: usize,
    /// The draft kept while the prompt takes a yes, an argument or an answer for a provider.
    pub stash: Option<String>,
    /// The words and the file of the request in flight, given back if it fails.
    pub pending: Option<(String, Option<String>)>,
    /// Focus: the list (true) or the prompt (false); sel is the row in the list.
    pub in_list: bool,
    pub sel: usize,
    pub exchange: Vec<Line>,
    pub undo: Option<Step>,
    pub queue: VecDeque<Step>,
    /// Steps the model proposed for a question: run only when picked.
    pub proposals: Vec<Step>,
    pub running: Option<(usize, u64, Step, usize)>,
    pub busy_since: Option<Instant>,
    pub frame: u64,
    /// Every model spark lists: (name, serving | downloaded | -).
    pub models: Vec<(String, String)>,
    pub model_name: Option<String>,
    /// Where the model runs: None this computer, else the spark server's address (`spark client`).
    pub server: Option<String>,
    pub voice_on: bool,
    pub talk: Talk,
    /// Esc stopped the listening: what comes back is not said.
    pub listen_cancelled: bool,
    /// The window's size in cells, as the terminal says.
    pub size: (u16, u16),
    pub thinking: bool,
    pub jobs: Vec<Job>,
    pub quit: Option<i32>,
    pub opened: bool,
    asks_this_call: usize,
    asks: VecDeque<Instant>,
    pub chip_focus: Option<usize>,
    pub about_idx: Option<usize>,
    /// How far the content area is scrolled by Page Up and Page Down.
    pub scroll: usize,
    /// A theme step's palette, for main.rs to repaint the window with: the colors came in the
    /// environment at start, and a new palette must not wait for the dialog to be opened again.
    pub palette: Option<Map<String, Value>>,
}

impl App {
    pub fn new(cfg: Config, labels: &[String]) -> App {
        let providers: Vec<Provider> = labels.iter().map(|l| Provider::new(l)).collect();
        let about_idx = providers.iter().position(|p| p.label == "about");
        let view = match cfg.home.as_deref() {
            Some("about") => View::About,
            Some("clock") | Some("reminders") => View::Dest(CALENDAR_DEST), // the bar's clock opens the Calendar
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
            cursor: 0,
            stash: None,
            pending: None,
            in_list: false,
            sel: 0,
            exchange: vec![],
            undo: None,
            queue: VecDeque::new(),
            proposals: vec![],
            running: None,
            busy_since: None,
            frame: 0,
            models: vec![],
            model_name: None,
            server: None,
            voice_on: false,
            talk: talk_kept(),
            listen_cancelled: false,
            size: (WIDTH, HEIGHT),
            thinking: false,
            jobs: vec![],
            quit: None,
            opened: false,
            asks_this_call: 0,
            asks: VecDeque::new(),
            chip_focus: None,
            about_idx,
            scroll: 0,
            palette: None,
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
        if self.cfg.model {
            self.jobs.push(Job::Run(Helper::Client, vec![self.cfg.spark.clone(), "client".into()]));
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
                self.say(
                    Sign::Refused,
                    &format!("{}: {} stopped before it answered, so it may or may not have happened", step.line, label),
                );
                self.stop_queue("not run");
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
                    if self.view == View::Section(idx) {
                        if let Some(root) = self.files_root(idx) {
                            self.view = View::Folder(idx, root.clone());
                            self.read_folder(idx, &root);
                        }
                    }
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
                        // no answer is no proof either way: say so, and run nothing that depends on it
                        self.say(
                            Sign::Refused,
                            &format!(
                                "{}: no answer in {} s, so it may or may not have happened: look before you try again",
                                step.line,
                                mcp::T_CALL.as_secs()
                            ),
                        );
                        self.stop_queue("not run");
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

    /// The sections present that a destination holds; Settings holds those of SETTINGS that run here.
    pub fn dest_sections(&self, d: usize) -> Vec<usize> {
        DESTS[d]
            .sections
            .iter()
            .filter_map(|s| self.providers.iter().position(|p| &p.label == s && p.dead.is_none()))
            .collect()
    }

    /// The rows of Settings shown here: a section that runs, Connections always, About when it runs.
    pub fn settings(&self) -> Vec<usize> {
        SETTINGS
            .iter()
            .enumerate()
            .filter(|(_, (l, _, _))| *l == "connections" || (*l == "talk" && self.cfg.talk) || self.providers.iter().any(|p| &p.label == l && p.dead.is_none()))
            .map(|(i, _)| i)
            .collect()
    }

    /// The home's destinations shown here: one with a section that runs, Settings always.
    pub fn dests(&self) -> Vec<usize> {
        (0..DESTS.len()).filter(|d| *d == SETTINGS_DEST || !self.dest_sections(*d).is_empty()).collect()
    }

    /// The exchange as content lines: the newest turn first (a turn starts at what was asked), each in
    /// its own order; older turns while EXCHANGE_MAX lines hold them. Then the undo, then the proposals.
    fn said(&self, out: &mut Vec<Item>) {
        let w = self.size.0.saturating_sub(8).max(10) as usize; // the sign at 2, the words at 4, air at the right
        let mut turns: Vec<Vec<usize>> = vec![];
        for (i, l) in self.exchange.iter().enumerate() {
            if l.sign == Sign::You || turns.is_empty() {
                turns.push(vec![]);
            }
            if let Some(t) = turns.last_mut() {
                t.push(i);
            }
        }
        let mut lines = 0;
        for (k, t) in turns.iter().rev().enumerate() {
            let mut turn = vec![];
            for &i in t {
                let l = &self.exchange[i];
                for (j, part) in crate::ui::wrap(&l.text, w).into_iter().enumerate() {
                    turn.push(Item::Said(l.sign.clone(), part, j == 0));
                }
            }
            if k > 0 && lines + turn.len() > EXCHANGE_MAX {
                break;
            }
            lines += turn.len();
            out.extend(turn);
        }
        if self.undo.is_some() {
            out.push(Item::Undo);
        }
        if !self.proposals.is_empty() {
            // a question changed nothing: what the model would do, offered, run only when picked
            out.push(Item::Heading("proposed, not run".into()));
            for i in 0..self.proposals.len() {
                out.push(Item::Proposal(i));
            }
        }
    }

    /// A section's rows under their groups, as its own view shows them; under the section's name too
    /// where a view holds more than one section.
    fn section_rows(&self, p: usize, out: &mut Vec<Item>, heading: bool) {
        let mut rows = vec![];
        let mut group: Option<String> = None;
        for (i, r) in self.providers[p].rows.rows.iter().enumerate() {
            if r.children.as_deref() == Some(&format!("spark-shell://{}/rows", self.providers[p].label)) {
                continue;
            }
            if !self.input.is_empty() && !self.matches(p, r) {
                continue;
            }
            if r.group != group {
                if !rows.is_empty() {
                    rows.push(Item::Blank);
                }
                if let Some(g) = &r.group {
                    rows.push(Item::Heading(g.clone()));
                }
                group = r.group.clone();
            }
            rows.push(Item::Row(p, i));
        }
        if rows.is_empty() {
            return;
        }
        if heading {
            if !out.is_empty() {
                out.push(Item::Blank);
            }
            out.push(Item::Title(section_name(&self.providers[p].label)));
        }
        out.extend(rows);
    }

    /// The content area's items, in order: the exchange (the newest turn first), the undo and the
    /// proposals, then the view's list.
    pub fn items(&self) -> Vec<Item> {
        let mut out = vec![];
        if self.view != View::About {
            self.said(&mut out);
        }
        let mut list = vec![];
        match &self.view {
            View::Models => {
                list.push(Item::Heading("where it runs".into()));
                list.push(Item::Conn(0));
                list.push(Item::Conn(1));
                list.push(Item::Blank);
                list.push(Item::Heading("models".into()));
                for i in 0..self.models.len() {
                    list.push(Item::Model(i));
                }
                list.push(Item::Blank);
                let who = if self.server.is_some() {
                    "everyone who uses that server"
                } else {
                    "every client of this computer's spark"
                };
                self.text(&mut list, &format!("A change restarts the model for {}.", who), true);
            }
            View::Talk => {
                list.push(Item::TalkOpt(Talk::Click));
                list.push(Item::TalkOpt(Talk::Off));
                list.push(Item::Blank);
                self.text(&mut list, "Hold Space to talk needs a newer spark.", true);
                if !self.voice_on {
                    self.text(&mut list, "spark's voice is off: spark voice clear turns it on.", true);
                }
            }
            View::Connections => {
                list.push(Item::Heading("tools".into()));
                for (i, p) in self.providers.iter().enumerate() {
                    if p.dead.is_none() && Some(i) != self.about_idx {
                        list.push(Item::Provider(i));
                    }
                }
                list.push(Item::Blank);
                list.push(Item::Heading("model".into()));
                list.push(Item::OpenModels);
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
                        list.push(Item::Blank); // the summary at the end stands apart
                    }
                    list.push(Item::Folder(i));
                }
            }
            View::Section(p) => self.section_rows(*p, &mut list, false),
            View::Dest(d) if *d == SETTINGS_DEST => {
                for i in self.settings() {
                    if self.input.is_empty() || self.word_in(SETTINGS[i].1) {
                        list.push(Item::Setting(i));
                    }
                }
            }
            View::Dest(d) if *d == CALENDAR_DEST => {
                // the months are drawn above; the reminders, to add, mark done or snooze, below them
                if let Some(p) = self.providers.iter().position(|p| p.label == "reminders" && p.dead.is_none()) {
                    self.section_rows(p, &mut list, false);
                }
            }
            View::Dest(d) => {
                let secs = self.dest_sections(*d);
                let one = secs.len() == 1;
                for p in secs {
                    self.section_rows(p, &mut list, !one);
                }
            }
            View::Home => {
                if self.input.trim().is_empty() {
                    // the six places with air between them, as the approved home has them
                    for (k, d) in self.dests().into_iter().enumerate() {
                        if k > 0 {
                            list.push(Item::Blank);
                        }
                        list.push(Item::Dest(d));
                    }
                } else {
                    // what was typed, found: the places, then every step that says those words
                    for d in self.dests() {
                        if self.word_in(DESTS[d].name) {
                            list.push(Item::Dest(d));
                        }
                    }
                    for i in self.settings() {
                        if self.word_in(SETTINGS[i].1) {
                            list.push(Item::Setting(i));
                        }
                    }
                    for (p, prov) in self.providers.iter().enumerate() {
                        let rows: Vec<usize> = prov
                            .rows
                            .rows
                            .iter()
                            .enumerate()
                            .filter(|(_, r)| {
                                // the about's own row is found; its key sentences stay out of a search; a row that only opens
                                // its own section is left out, as the section's view leaves it (the setting opens it already)
                                Self::pickable(r)
                                    && self.matches(p, r)
                                    && (Some(p) != self.about_idx || r.tool.as_ref().is_some_and(|t| t.name == "about_open"))
                                    && r.children.as_deref() != Some(format!("spark-shell://{}/rows", prov.label).as_str())
                            })
                            .map(|(i, _)| i)
                            .collect();
                        if rows.is_empty() {
                            continue;
                        }
                        if !list.is_empty() {
                            list.push(Item::Blank);
                        }
                        list.push(Item::Heading(prov.label.clone()));
                        for i in rows {
                            list.push(Item::Row(p, i));
                        }
                    }
                }
            }
        }
        if !out.is_empty() && !list.is_empty() {
            out.push(Item::Blank);
        }
        out.extend(list);
        out
    }

    /// Words that open nothing, wrapped to the content's width.
    fn text(&self, out: &mut Vec<Item>, words: &str, muted: bool) {
        for l in crate::ui::wrap(words, self.size.0.saturating_sub(6).max(10) as usize) {
            out.push(Item::Text(l, muted));
        }
    }

    /// Every word typed is in these words.
    fn word_in(&self, words: &str) -> bool {
        let hay = words.to_lowercase();
        self.input.to_lowercase().split_whitespace().all(|w| hay.contains(w))
    }

    pub fn pickable_item(&self, i: &Item) -> bool {
        match i {
            Item::Row(p, r) => Self::pickable(&self.providers[*p].rows.rows[*r]),
            Item::Folder(i) => self
                .folder
                .as_ref()
                .and_then(|(_, _, rows)| rows.rows.get(*i))
                .map(Self::pickable)
                .unwrap_or(false),
            Item::Model(i) => self.models.get(*i).map(|(_, s)| s == "serving" || s == "downloaded").unwrap_or(false),
            Item::TalkOpt(_) => self.voice_on,
            Item::Undo | Item::Dest(_) | Item::Setting(_) | Item::Proposal(_) | Item::OpenModels => true,
            _ => false,
        }
    }

    pub fn picks(&self) -> Vec<Item> {
        self.items().into_iter().filter(|i| self.pickable_item(i)).collect()
    }

    // ---- keys

    /// The cursor as (line, column) in the draft's lines.
    fn at(&self) -> (usize, usize) {
        let before: String = self.input.chars().take(self.cursor).collect();
        let line = before.matches('\n').count();
        let col = before.rsplit('\n').next().map(|l| l.chars().count()).unwrap_or(0);
        (line, col)
    }

    /// The cursor put at (line, column), the column held to the line's length.
    fn put_at(&mut self, line: usize, col: usize) {
        let mut n = 0;
        for (i, l) in self.input.split('\n').enumerate() {
            let len = l.chars().count();
            if i == line {
                self.cursor = n + col.min(len);
                return;
            }
            n += len + 1;
        }
        self.cursor = self.input.chars().count();
    }

    fn lines(&self) -> usize {
        self.input.matches('\n').count() + 1
    }

    pub fn up(&mut self) {
        if self.in_list {
            if self.sel == 0 {
                self.in_list = false; // above the first row is the prompt
            } else {
                self.sel -= 1;
            }
        } else {
            let (l, c) = self.at();
            if l > 0 {
                self.put_at(l - 1, c);
            }
        }
    }

    pub fn down(&mut self) {
        if self.in_list {
            if self.sel + 1 < self.picks().len() {
                self.sel += 1;
            }
            return;
        }
        let (l, c) = self.at();
        if l + 1 < self.lines() {
            self.put_at(l + 1, c);
        } else if !self.picks().is_empty() && self.chip_focus.is_none() {
            self.in_list = true;
            self.sel = 0;
        }
    }

    /// A key that types: it goes to the prompt, wherever the focus was.
    pub fn typed(&mut self, c: char) {
        if c.is_control() {
            return;
        }
        self.insert(&c.to_string());
    }

    /// Shift+Enter: a new line in the draft; never in a yes, an argument or an answer, which are one line.
    pub fn newline(&mut self) {
        if self.mode == Mode::Normal {
            self.insert("\n");
        }
    }

    /// Pasted text goes into the draft as it is, its lines kept: a newline in it never sends. Where the
    /// prompt takes one line, the lines are joined by spaces.
    pub fn paste(&mut self, text: &str) {
        let one = self.mode != Mode::Normal;
        let t: String = text
            .replace("\r\n", "\n")
            .replace('\r', "\n")
            .chars()
            .map(|c| if c == '\t' || (one && c == '\n') { ' ' } else { c })
            .filter(|c| *c == '\n' || !c.is_control())
            .collect();
        self.insert(&t);
    }

    fn insert(&mut self, t: &str) {
        self.chip_focus = None;
        let room = INPUT_MAX.saturating_sub(self.input.chars().count());
        let t: String = t.chars().take(room).collect();
        if t.is_empty() {
            return;
        }
        let at = self.byte_at(self.cursor);
        self.input.insert_str(at, &t);
        self.cursor += t.chars().count();
        if matches!(self.mode, Mode::Normal) {
            self.in_list = false;
            self.sel = 0;
            self.scroll = 0;
        }
    }

    fn byte_at(&self, chars: usize) -> usize {
        self.input.char_indices().nth(chars).map(|(b, _)| b).unwrap_or(self.input.len())
    }

    /// The draft set whole, the cursor at its end.
    pub fn set_draft(&mut self, s: &str) {
        self.set_input(s.to_string());
    }

    fn set_input(&mut self, s: String) {
        self.cursor = s.chars().count();
        self.input = s;
    }

    pub fn backspace(&mut self) {
        if self.cursor == 0 {
            return;
        }
        let a = self.byte_at(self.cursor - 1);
        let b = self.byte_at(self.cursor);
        self.input.replace_range(a..b, "");
        self.cursor -= 1;
        if matches!(self.mode, Mode::Normal) {
            self.in_list = false;
            self.sel = 0;
        }
    }

    pub fn delete(&mut self) {
        if self.cursor >= self.input.chars().count() {
            return;
        }
        let a = self.byte_at(self.cursor);
        let b = self.byte_at(self.cursor + 1);
        self.input.replace_range(a..b, "");
    }

    /// Left and right: the cursor in the draft; in the Calendar with nothing typed, the months.
    pub fn left(&mut self) {
        if self.input.is_empty() && !self.in_list {
            return self.month(-1);
        }
        self.cursor = self.cursor.saturating_sub(1);
    }

    pub fn right(&mut self) {
        if self.input.is_empty() && !self.in_list {
            return self.month(1);
        }
        self.cursor = (self.cursor + 1).min(self.input.chars().count());
    }

    pub fn line_start(&mut self) {
        let (l, _) = self.at();
        self.put_at(l, 0);
    }

    pub fn line_end(&mut self) {
        let (l, _) = self.at();
        self.put_at(l, usize::MAX);
    }

    /// Page up and down: the content area, by most of its height.
    pub fn page(&mut self, d: i32) {
        let step = self.size.1.saturating_sub(14).max(4) as usize;
        self.scroll = if d < 0 { self.scroll.saturating_sub(step) } else { self.scroll + step };
    }

    /// The prompt takes a yes, an argument or an answer: the draft waits aside.
    fn stash_draft(&mut self) {
        if self.stash.is_none() {
            self.stash = Some(std::mem::take(&mut self.input));
        }
        self.cursor = 0;
    }

    /// The question answered or let go: the draft comes back as it was.
    fn unstash(&mut self) {
        if let Some(s) = self.stash.take() {
            if self.input.is_empty() {
                self.set_input(s);
            }
        }
    }

    /// Esc: a question waiting is answered no (the draft comes back); the focus on a control or the
    /// draft goes first; then back one view; from the first view the dialog closes.
    pub fn escape(&mut self) {
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            Mode::Confirm(step) => {
                self.say(Sign::Refused, &format!("{}: kept, not done", step.line));
                self.input.clear();
                self.unstash();
                self.stop_queue("the steps after it were not run");
            }
            Mode::Ask { step, .. } => {
                self.say(Sign::Refused, &format!("{}: not done", step.line));
                self.input.clear();
                self.unstash();
                self.stop_queue("the steps after it were not run");
            }
            Mode::Elicit { prov, id, .. } => {
                if let Some(s) = self.server(prov) {
                    s.answer(&id, json!({"action": "cancel"}));
                }
                self.input.clear();
                self.unstash();
            }
            Mode::Apply(name) => {
                self.say(Sign::Refused, &format!("model {}: kept {}", name, self.model_name.clone().unwrap_or_default()));
                self.input.clear();
                self.unstash();
            }
            Mode::Listening => {
                // the recording is dropped; the draft stays as it was
                self.listen_cancelled = true;
                self.mode = Mode::Listening;
                self.jobs.push(Job::StopListening);
            }
            Mode::Normal => {
                if self.chip_focus.is_some() {
                    self.chip_focus = None;
                } else if !self.input.is_empty() && !self.in_list {
                    self.set_input(String::new());
                    self.sel = 0;
                } else if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                } else {
                    self.quit = Some(0);
                }
            }
        }
    }

    fn go_back(&mut self, v: View) {
        self.view = v;
        self.sel = 0;
        self.in_list = false;
        self.scroll = 0;
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
    }

    fn go(&mut self, v: View) {
        // the files section is its home folder: its one row, ~, is no stop of its own
        if let View::Section(p) = v {
            if let Some(root) = self.files_root(p) {
                self.came_from.push(self.view.clone());
                self.view = View::Folder(p, root.clone());
                self.sel = 0;
                self.in_list = false;
                self.scroll = 0;
                return self.read_folder(p, &root);
            }
        }
        self.came_from.push(self.view.clone());
        self.view = v;
        self.sel = 0;
        self.in_list = false;
        self.scroll = 0;
        self.month_offset = 0;
    }

    /// A word typed alone that names a place: its view. "calendar" and "settings" are places, and
    /// so is a section's own name ("about" once opened aerc).
    fn place(&self, word: &str) -> Option<View> {
        let w = word.trim().to_lowercase();
        if let Some(d) = self.dests().into_iter().find(|d| DESTS[*d].name.to_lowercase() == w) {
            return Some(self.dest_view(d));
        }
        if w == "connections" {
            return Some(View::Connections);
        }
        if w == "talk" && self.cfg.talk {
            return Some(View::Talk);
        }
        if w == "about" && self.about_idx.is_some() {
            return Some(View::About);
        }
        let w = if w == "clock" { return Some(View::Dest(CALENDAR_DEST)) } else { w };
        if let Some(i) = SETTINGS.iter().position(|(_, n, _)| n.to_lowercase() == w) {
            if let Some(q) = self.providers.iter().position(|x| x.label == SETTINGS[i].0 && x.ready && x.dead.is_none()) {
                return Some(View::Section(q));
            }
        }
        self.providers.iter().position(|x| x.label == w && x.ready && x.dead.is_none()).map(|q| {
            if Some(q) == self.about_idx {
                View::About
            } else {
                View::Section(q)
            }
        })
    }

    /// A destination's view: one section is that section's own, files is its home folder.
    fn dest_view(&self, d: usize) -> View {
        if d == SETTINGS_DEST || d == CALENDAR_DEST {
            return View::Dest(d);
        }
        let secs = self.dest_sections(d);
        match secs.as_slice() {
            [p] => View::Section(*p),
            _ => View::Dest(d),
        }
    }

    pub fn enter(&mut self) {
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            Mode::Confirm(step) => {
                let typed = std::mem::take(&mut self.input);
                self.unstash();
                if typed.trim() == "yes" {
                    self.approved(step);
                } else {
                    self.say(Sign::Refused, &format!("{}: kept, not done (it takes yes)", step.line));
                    self.stop_queue("the steps after it were not run");
                }
                return;
            }
            Mode::Ask { mut step, field, .. } => {
                let typed = std::mem::take(&mut self.input);
                self.unstash();
                if typed.trim().is_empty() {
                    self.say(Sign::Refused, &format!("{}: not done, no {}", step.line, field));
                    self.stop_queue("the steps after it were not run");
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
                let typed = std::mem::take(&mut self.input);
                self.cursor = 0;
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
                } else {
                    self.unstash();
                    if let Some(s) = self.server(prov) {
                        s.answer(&id, json!({"action": "accept", "content": answers}));
                    }
                }
                return;
            }
            Mode::Apply(name) => {
                self.input.clear();
                self.unstash();
                self.say(Sign::Step, &format!("model {}", name));
                self.thinking = true;
                self.jobs.push(Job::Run(Helper::ModelSet, vec![self.cfg.spark.clone(), "model".into(), name]));
                return;
            }
            Mode::Listening => {
                self.mode = Mode::Listening;
                return;
            }
            Mode::Normal => {}
        }
        if let Some(c) = self.chip_focus {
            self.chip(c);
            return;
        }
        if !self.in_list {
            // the prompt: a place's name alone opens it; any other words are a request, never a row
            // that happens to match them (a question that names an app does not open it)
            let typed = self.input.trim().to_string();
            if typed.is_empty() {
                return;
            }
            if !typed.contains('\n') {
                if let Some(v) = self.place(&typed) {
                    self.set_input(String::new());
                    if self.view != v {
                        self.go(v);
                    }
                    return;
                }
            }
            self.set_input(String::new());
            return self.want(&typed);
        }
        let picks = self.picks();
        let sel = self.sel.min(picks.len().saturating_sub(1));
        let Some(item) = picks.get(sel).cloned() else { return };
        // a list filtered by the words typed: the words were a search, and go with the pick
        if matches!(self.view, View::Home | View::Section(_) | View::Dest(_) | View::Folder(..)) {
            self.set_input(String::new());
        }
        self.sel = 0;
        self.in_list = false;
        match item {
            Item::Undo => {
                if let Some(u) = self.undo.take() {
                    self.run(u);
                }
            }
            Item::Proposal(i) => {
                if i < self.proposals.len() {
                    let s = self.proposals.remove(i);
                    self.run(s);
                }
            }
            Item::Dest(d) => {
                let v = self.dest_view(d);
                self.go(v);
            }
            Item::Setting(i) => {
                let label = SETTINGS[i].0;
                if label == "connections" {
                    return self.go(View::Connections);
                }
                if label == "talk" {
                    return self.go(View::Talk);
                }
                if let Some(v) = self.place(label) {
                    self.go(v);
                }
            }
            Item::OpenModels => self.go(View::Models),
            Item::TalkOpt(t) => {
                self.talk = t;
                talk_keep(t);
                self.say(Sign::Done, if t == Talk::Off { "talk off" } else { "click the mic to talk" });
                if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                }
            }
            Item::Model(i) => {
                let (name, state) = self.models[i].clone();
                if state == "serving" {
                    self.say(Sign::Done, &format!("{} is in use", name));
                    return;
                }
                // browsing changed nothing; this is the review: what changes, and for whom
                let who = match &self.server {
                    Some(s) => format!("everyone who uses {}", s),
                    None => "every client of this computer's spark".to_string(),
                };
                self.say(
                    Sign::Says,
                    &format!(
                        "Use {} instead of {}? It restarts the model for {}.",
                        name,
                        self.model_name.clone().unwrap_or_default(),
                        who
                    ),
                );
                self.stash_draft();
                self.mode = Mode::Apply(name);
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
                        return self.go(View::About);
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
        if tail == "rows" {
            let v = if Some(q) == self.about_idx {
                View::About
            } else if label == "clock" || label == "reminders" {
                View::Dest(CALENDAR_DEST)
            } else {
                View::Section(q)
            };
            self.go(v);
        } else if tail.starts_with("rows/") {
            self.go(View::Folder(q, uri.to_string()));
            self.read_folder(q, uri);
        }
    }

    fn read_folder(&mut self, p: usize, uri: &str) {
        self.folder = None;
        if let Some(s) = self.server(p) {
            s.request("resources/read", json!({"uri": uri}), Kind::Folder, mcp::T_READ);
        }
    }

    /// The home folder's uri when provider p is the files section and its rows have come.
    fn files_root(&self, p: usize) -> Option<String> {
        let prov = self.providers.get(p)?;
        if prov.label != "files" {
            return None;
        }
        prov.rows.rows.iter().find_map(|r| r.children.clone())
    }

    /// The files provider, when one is running and handed a root.
    fn files(&self) -> Option<usize> {
        self.providers.iter().position(|p| p.label == "files" && p.dead.is_none())
    }

    /// The footer's controls and the attachment's Remove: 0 attach, 1 the model, 3 the mic, 4 remove
    /// the file attached. How talk works is a setting (Settings > Talk), not a control.
    pub fn chip(&mut self, c: usize) {
        self.chip_focus = None;
        match c {
            4 => {
                if let Some(a) = self.attachment.take() {
                    let name = a.rsplit('/').next().unwrap_or("").to_string();
                    self.say(Sign::Done, &format!("{} removed: the next question goes without it", name));
                }
            }
            0 if self.cfg.plus => {
                let Some(f) = self.files() else { return };
                let Some(root) = self.providers[f].rows.rows.iter().find_map(|r| r.children.clone()) else {
                    return self.say(Sign::Refused, "no folder to attach from");
                };
                self.attaching = Some((self.view.clone(), self.came_from.len()));
                self.open_children(f, &root);
            }
            1 if self.cfg.model => {
                if self.view != View::Models {
                    self.go(View::Models);
                }
            }
            3 if self.cfg.talk && self.voice_on && self.talk == Talk::Click => {
                if self.mode == Mode::Listening {
                    // a click on the mic again: stop, nothing kept (spark ends a recording at a pause)
                    self.listen_cancelled = true;
                    self.jobs.push(Job::StopListening);
                } else if self.mode == Mode::Normal && self.running.is_none() {
                    self.listen_cancelled = false;
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

    /// The controls Tab moves through, in their order on the screen.
    pub fn chips(&self) -> Vec<usize> {
        let mut v = vec![];
        if self.attachment.is_some() {
            v.push(4);
        }
        if self.cfg.plus && self.files().is_some() {
            v.push(0);
        }
        if self.cfg.model && self.model_name.is_some() {
            v.push(1);
        }
        if self.cfg.talk && self.voice_on && self.talk == Talk::Click {
            v.push(3);
        }
        v
    }

    /// Tab: the next control; after the last, the prompt again. Shift+Tab goes the other way.
    pub fn tab(&mut self, back: bool) {
        let c = self.chips();
        if c.is_empty() {
            return;
        }
        self.in_list = false;
        let at = self.chip_focus.and_then(|f| c.iter().position(|x| *x == f));
        self.chip_focus = match (at, back) {
            (None, false) => Some(c[0]),
            (None, true) => c.last().copied(),
            (Some(i), false) => c.get(i + 1).copied(),
            (Some(0), true) => None,
            (Some(i), true) => c.get(i - 1).copied(),
        };
    }

    /// Focus left the window (another window, the lock): a recording stops, nothing kept.
    pub fn focus_lost(&mut self) {
        if self.mode == Mode::Listening {
            self.listen_cancelled = true;
            self.jobs.push(Job::StopListening);
        }
    }

    // ---- the want and the steps

    fn want(&mut self, words: &str) {
        self.say(Sign::You, words);
        self.proposals.clear();
        if self.cfg.spark_shell.is_empty() {
            self.set_input(words.to_string());
            return self.say(Sign::Refused, "no spark-shell to read the words");
        }
        self.thinking = true;
        let mut argv = vec![self.cfg.spark_shell.clone(), "want".into(), "--json".into()];
        // the file goes with this request alone; it comes back if the request fails
        let file = self.attachment.take();
        if let Some(a) = &file {
            argv.push("--attach".into());
            argv.push(a.clone());
        }
        self.pending = Some((words.to_string(), file));
        argv.push("--".into());
        argv.push(words.to_string());
        self.jobs.push(Job::Run(Helper::Want, argv));
    }

    /// A request that did not get its answer: the words and the file come back, unless something new
    /// was typed or attached meanwhile.
    fn give_back(&mut self) {
        if let Some((words, file)) = self.pending.take() {
            if self.input.is_empty() && self.mode == Mode::Normal {
                self.set_input(words);
            }
            if self.attachment.is_none() {
                self.attachment = file;
            }
        }
    }

    /// The plan from `spark-shell want --json`: each step gated here too, then run in order. A question
    /// changes nothing: its steps are proposals, run only when picked.
    pub fn plan(&mut self, text: &str) {
        self.thinking = false;
        let Ok(v) = serde_json::from_str::<Value>(text) else {
            self.give_back();
            return self.say(Sign::Refused, "the answer was not a plan");
        };
        let question = v.get("question").and_then(Value::as_bool).unwrap_or(false);
        if let Some(a) = v.get("answer").and_then(Value::as_str) {
            if !a.trim().is_empty() {
                self.say(Sign::Says, a);
            }
        }
        let refused: Vec<String> = v
            .get("refused")
            .and_then(Value::as_array)
            .map(|r| {
                r.iter()
                    .filter_map(Value::as_str)
                    .map(|t| t.trim_start_matches('\u{2717}').trim().to_string())
                    .collect()
            })
            .unwrap_or_default();
        for t in &refused {
            self.say(Sign::Refused, t);
        }
        let steps = v.get("steps").and_then(Value::as_array).cloned().unwrap_or_default();
        if steps.is_empty() && v.get("answer").and_then(Value::as_str).unwrap_or("").trim().is_empty() && !refused.is_empty() {
            self.give_back(); // refused whole: the words come back to be said again
        } else {
            self.pending = None;
        }
        for s in steps {
            let Some(name) = s.get("name").and_then(Value::as_str) else { continue };
            let arguments = s.get("arguments").and_then(Value::as_object).cloned().unwrap_or_default();
            let line = scrub(s.get("line").and_then(Value::as_str).unwrap_or(name));
            // two steps are the dialog's own: undo is its undo row, about opens its about
            if name == "undo_all" {
                match self.undo.take() {
                    Some(u) if question => {
                        self.undo = Some(u);
                    }
                    Some(u) => self.queue.push_back(u),
                    None => self.say(Sign::Refused, "nothing to undo"),
                }
                continue;
            }
            if name == "about_open" {
                if self.about_idx.is_some() {
                    self.go(View::About);
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
                    Ok(()) => {
                        let step = Step {
                            prov: p,
                            call,
                            who: Who::Model,
                            line,
                        };
                        if question {
                            self.proposals.push(step);
                        } else {
                            self.queue.push_back(step);
                        }
                    }
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

    /// A step failed, was refused or kept: the steps planned after it depend on it, and are not run.
    fn stop_queue(&mut self, why: &str) {
        if self.queue.is_empty() {
            return;
        }
        let left: Vec<String> = self.queue.drain(..).map(|s| s.line).collect();
        self.say(Sign::Refused, &format!("{}: {}", why, left.join(", ")));
    }

    /// Whether a step waits for the typed yes: the provider's destructive hint, or this machine's own
    /// list. The hint alone never makes a step safe.
    pub fn risky(&self, tool: &Tool) -> bool {
        tool.destructive || LOCAL_RISK.contains(&tool.name.as_str())
    }

    /// A step: an argument asked when it lacks one, a typed yes when it is risky, then the call.
    pub fn run(&mut self, step: Step) {
        if let Some(field) = step.call.ask.first().cloned() {
            let masked = gate::secret(&field, self.tool_of(&step).and_then(|t| t.schema.pointer(&format!("/properties/{}", field))));
            self.stash_draft();
            self.mode = Mode::Ask { step, field, masked };
            return;
        }
        let Some(tool) = self.tool_of(&step).cloned() else {
            self.say(Sign::Refused, &format!("{}: not a step here now", step.line));
            return self.stop_queue("the steps after it were not run");
        };
        if let Err(e) = self.checked(&step) {
            self.say(Sign::Refused, &format!("{}: {}", step.line, e));
            return self.stop_queue("the steps after it were not run");
        }
        if step.who == Who::Model {
            self.say(Sign::Step, &step.line);
        }
        if self.risky(&tool) {
            self.stash_draft();
            self.mode = Mode::Confirm(step);
            return;
        }
        self.call(step);
    }

    /// What every step passes, now and again at its yes: its tool is still offered, no argument holds a
    /// control character (a pasted or spoken newline is never a step's), and a step the model or the
    /// undo planned names only what the rows list now.
    fn checked(&self, step: &Step) -> Result<(), String> {
        if self.tool_of(step).is_none() {
            return Err("not a step here now".into());
        }
        if step
            .call
            .arguments
            .values()
            .any(|v| v.as_str().is_some_and(|s| s.chars().any(char::is_control)))
        {
            return Err("an argument holds a control character".into());
        }
        if step.who != Who::Person {
            gate::step(&self.providers[step.prov].tools, &self.providers[step.prov].rows, &step.call)?;
        }
        Ok(())
    }

    /// The yes was typed for this step, these arguments: checked again against what is offered now,
    /// for the rows may have changed while the question waited.
    fn approved(&mut self, step: Step) {
        match self.checked(&step) {
            Ok(()) => self.call(step),
            Err(e) => {
                self.say(Sign::Refused, &format!("{}: not done, {}", step.line, e));
                self.stop_queue("the steps after it were not run");
            }
        }
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
                self.stop_queue("the steps after it were not run");
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
            self.stop_queue("not run, for the step before failed");
        } else if let Some(r) = result {
            let text = r.pointer("/content/0/text").and_then(Value::as_str).unwrap_or("");
            if refused {
                self.say(Sign::Refused, text);
                self.stop_queue("not run, for the step before failed");
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
                // the theme section's own palette, never another provider's
                if self.providers[idx].label == "theme" {
                    if let Some(p) = sc.get("palette").and_then(Value::as_object) {
                        self.palette = Some(p.clone());
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
            }
        }
        self.providers[idx].dirty = true;
        self.next_step();
    }

    /// A helper's answer: the plan, the model list, the model set, the words heard, the voice's state,
    /// where the model runs.
    pub fn helper(&mut self, h: Helper, out: Result<String, String>) {
        match h {
            Helper::Want => match out {
                Ok(t) => self.plan(&t),
                Err(e) => {
                    self.thinking = false;
                    match serde_json::from_str::<Value>(&e) {
                        Ok(_) => self.plan(&e),
                        Err(_) => {
                            self.give_back();
                            self.say(Sign::Refused, e.lines().next().unwrap_or("spark did not answer"))
                        }
                    }
                }
            },
            Helper::Models => {
                if let Ok(t) = out {
                    // every model spark knows: in use, installed, or not downloaded (shown, not offered)
                    self.models = t
                        .lines()
                        .filter_map(|l| {
                            let f: Vec<&str> = l.split('\t').collect();
                            let name = scrub(f.first()?);
                            let state = scrub(f.last()?);
                            (!name.is_empty()).then_some((
                                name,
                                if state == "serving" || state == "downloaded" {
                                    state
                                } else {
                                    "-".to_string()
                                },
                            ))
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
                let cancelled = std::mem::take(&mut self.listen_cancelled);
                match out {
                    Ok(t) if !cancelled => {
                        // what was heard goes into the draft at the cursor, to read and change; Enter sends
                        let heard = scrub(t.trim()).replace('\n', " ");
                        if !heard.is_empty() {
                            let before: String = self.input.chars().take(self.cursor).collect();
                            let pad = if before.is_empty() || before.ends_with(char::is_whitespace) {
                                ""
                            } else {
                                " "
                            };
                            self.insert(&format!("{}{}", pad, heard));
                        }
                    }
                    Ok(_) => {}
                    Err(_) if cancelled => self.say(Sign::Done, "stopped: nothing kept"),
                    Err(e) => self.say(Sign::Refused, e.lines().next().filter(|l| !l.trim().is_empty()).unwrap_or("nothing heard")),
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
            Helper::Client => {
                // "spark client -- of http://HOST:PORT, ..." when the model runs on another machine
                if let Ok(t) = out {
                    let first = t.lines().next().unwrap_or("");
                    self.server = first
                        .split_once(" of ")
                        .map(|(_, r)| scrub(r.split(|c: char| c == ',' || c.is_whitespace()).next().unwrap_or("")))
                        .filter(|u| u.starts_with("http"));
                }
            }
        }
    }

    // ---- what the window says

    /// The header's title: the view's name, in lower case as the home's.
    pub fn title(&self) -> String {
        if let Some(t) = &self.cfg.title {
            return scrub(t);
        }
        match &self.view {
            View::Home => "home".into(),
            View::Dest(d) => DESTS[*d].name.to_lowercase(),
            View::Section(p) | View::Folder(p, _) => section_name(&self.providers[*p].label).to_lowercase(),
            View::About => "about".into(),
            View::Models => "model".into(),
            View::Talk => "talk".into(),
            View::Connections => "connections".into(),
        }
    }

    pub fn subtitle(&self) -> String {
        match &self.view {
            View::Section(p) => self.providers[*p].title.clone(),
            View::Folder(..) => self.folder.as_ref().map(|(_, _, r)| r.title.clone()).unwrap_or_default(),
            _ => String::new(),
        }
    }

    /// The row under the prompt: what a key does now, a key named as a chip and nothing else as one.
    pub fn hint(&self) -> Vec<(String, bool)> {
        let key = |w: &str, k: &str| vec![(format!("{} ", w), false), (k.to_string(), true)];
        let gap = || ("   ".to_string(), false);
        let esc = |w: &str| vec![gap(), (format!("{} ", w), false), ("Esc".to_string(), true)];
        match &self.mode {
            Mode::Confirm(s) => {
                let mut v = vec![(format!("type yes to {}", s.line), false)];
                v.extend(esc("Keep"));
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
                v.extend(esc("Cancel"));
                return v;
            }
            Mode::Elicit { prov, message, fields, at, .. } => {
                let m = if message.is_empty() {
                    fields[*at].1.clone()
                } else {
                    format!("{}: {}", message, fields[*at].1)
                };
                let mut v = vec![(format!("{} asks: {}", self.providers[*prov].label, m), false)];
                v.extend(esc("Decline"));
                return v;
            }
            Mode::Listening => {
                let mut v = vec![("Listening, a pause ends it".to_string(), false)];
                v.extend(esc("Cancel"));
                return v;
            }
            Mode::Apply(_) => {
                let mut v = key("Apply", "Enter");
                v.extend(esc("Keep"));
                return v;
            }
            Mode::Normal => {}
        }
        if self.attaching.is_some() {
            let mut v = vec![(format!("Pick a file to attach ({})", self.cfg.attach.join(" ")), false)];
            v.extend(esc("Cancel"));
            return v;
        }
        if let Some(pk) = &self.picking {
            let mut v = vec![(format!("Pick a picture ({})", pk.types.join(" ")), false)];
            v.extend(esc("Cancel"));
            return v;
        }
        if self.chip_focus.is_some() {
            let mut v = key("Choose", "Enter");
            v.push(gap());
            v.extend(key("Next", "Tab"));
            return v;
        }
        if self.in_list {
            let word = match self.picks().get(self.sel) {
                Some(Item::Proposal(_)) | Some(Item::Undo) => "Run",
                Some(Item::Model(_)) | Some(Item::TalkOpt(_)) => "Choose",
                _ => "Open",
            };
            let mut v = key(word, "Enter");
            v.extend(esc(if self.came_from.is_empty() { "Close" } else { "Back" }));
            return v;
        }
        let mut v = key("Send", "Enter");
        v.push(gap());
        v.extend(key("New line", "Shift+Enter"));
        if self.input.is_empty() && self.is_calendar() {
            v.push(gap());
            v.extend(key("Month", "\u{2190} \u{2192}"));
        }
        v
    }

    /// The Calendar: its months, then the reminders.
    pub fn is_calendar(&self) -> bool {
        self.view == View::Dest(CALENDAR_DEST)
    }

    /// Left and right: the calendar's month back or on; nothing elsewhere.
    pub fn month(&mut self, d: i32) {
        if self.is_calendar() {
            self.month_offset += d;
        }
    }
}
