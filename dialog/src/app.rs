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
/// The cells the Undo at the end of a result takes, with the air before it.
pub const UNDO_ROOM: usize = 7;
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
    ("theme", "Theme", "Palette, wallpaper and text"),
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
/// Rows older than this are read again when their place comes back on screen.
pub const STALE: Duration = Duration::from_secs(5);
/// The sections whose rows the home's places say (#36): read again when the home comes back.
pub const HOME_STATES: [&str; 7] = ["apps", "window", "layout", "notes", "reminders", "wifi", "theme"];

/// What Enter does to a row, in a word, from its tool's name: the hint says it (Use dracula, Connect a
/// network). A row that opens more is Open.
pub fn verb_of(tool: &str) -> &'static str {
    let last = tool.rsplit('_').next().unwrap_or("");
    match last {
        "open" | "terminal" | "focus" | "new" => "Open",
        "connect" | "pair" => "Connect",
        "disconnect" => "Disconnect",
        "forget" => "Forget",
        "close" => "Close",
        "mute" => "Mute",
        "unmute" => "Unmute",
        "save" => "Save",
        "delete" => "Delete",
        "done" => "Done",
        "snooze" => "Snooze",
        "capture" => "Capture",
        _ => "Use",
    }
}

/// HOME, the one root the dialog hands the files provider; an attachment must sit under it.
/// The one argument a command line gives a tool: its one required argument that is no secret, else
/// its one argument. None when it takes more, or none.
fn one_argument(schema: &Value) -> Option<String> {
    let props = schema.get("properties").and_then(Value::as_object)?;
    let open: Vec<&String> = props.keys().filter(|k| !gate::secret(k, props.get(*k))).collect();
    let required: Vec<&str> = schema
        .get("required")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).filter(|k| !gate::secret(k, props.get(*k))).collect())
        .unwrap_or_default();
    match (required.as_slice(), open.as_slice()) {
        ([k], _) => Some(k.to_string()),
        ([], [k]) => Some(k.to_string()),
        _ => None,
    }
}

/// A command line's value as the schema types it: a number for a number, a whole number for an integer
/// (a percent sign after it is the number's), the words for a string.
fn typed_value(schema: &Value, k: &str, value: &str) -> Option<Value> {
    let ty = schema.pointer(&format!("/properties/{}/type", k)).and_then(Value::as_str).unwrap_or("string");
    let bare = value.strip_suffix('%').filter(|n| !n.is_empty() && n.bytes().all(|c| c.is_ascii_digit()));
    match ty {
        "integer" => bare.unwrap_or(value).parse::<i64>().ok().map(Value::from),
        "number" => value.parse::<f64>().ok().and_then(|n| serde_json::Number::from_f64(n).map(Value::Number)),
        "boolean" => match value {
            "on" | "true" | "yes" => Some(Value::Bool(true)),
            "off" | "false" | "no" => Some(Value::Bool(false)),
            _ => None,
        },
        _ => Some(Value::String(bare.unwrap_or(value).to_string())),
    }
}

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

/// A line of the exchange: the command as it ran (or the words of a question), then what came of it.
#[derive(Clone, Debug, PartialEq)]
pub enum Sign {
    You,
    Done,
    Refused,
    Says,
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

/// The commands spark planned for words, in the input box where the words were typed, as spark's own
/// prompt puts a command in the line (#53): Enter runs them as they stand, a change makes them typed
/// words again, Esc drops them and gives back what was in the box.
#[derive(Clone, Debug, PartialEq)]
pub struct Staged {
    pub text: String,
    pub steps: Vec<Step>,
    pub draft: String,
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
    /// It checks its rows for changes: only while its rows are on screen (#37).
    pub subscribed: bool,
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
            subscribed: false,
        }
    }
}

/// What the command line chose (2.2 of the contract).
#[derive(Clone, Debug)]
pub struct Config {
    pub home: Option<String>,
    pub title: Option<String>,
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
    /// The words typed, as a request to spark: the first row while words are typed, lit when no name matches them.
    Ask,
    Heading(String),
    Blank,
    /// The last line of the result the undo at hand takes back, with Undo at its end: the line, as
    /// Said, and picking it runs the undo (#53).
    Undo(Sign, String, bool),
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
    /// The commands spark planned, waiting in the input box for Enter (#53).
    pub staged: Option<Staged>,
    /// The value row left or right last changed, and where its turn starts: the next change of the
    /// same value takes that turn's place, so a run of presses is one turn.
    pub value_turn: Option<(String, usize)>,
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
    /// The view the providers were last fitted to (follow_view).
    pub last_view: Option<View>,
    /// The row a value was just changed on: the light stays on it while the list around it changes
    /// (the receipt and the Undo row come in above it), until a key moves it.
    pub keep_lit: Option<String>,
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
            staged: None,
            value_turn: None,
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
            last_view: None,
            keep_lit: None,
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
            self.value_turn = self.value_turn.take().and_then(|(id, at)| at.checked_sub(n - 200).map(|a| (id, a)));
        }
    }

    /// The commands spark planned are in the box as they came: Enter runs them (#53).
    pub fn staged_now(&self) -> bool {
        self.staged.as_ref().is_some_and(|s| s.text == self.input)
    }

    /// What the list is searched by: the words typed, never the commands spark put in the box.
    fn query(&self) -> &str {
        if self.staged_now() {
            ""
        } else {
            &self.input
        }
    }

    /// Work you asked for: a step, a request, a recording, or the rows of the place you opened while
    /// they come. The providers' first rows at open come quietly (#37).
    pub fn busy(&self) -> bool {
        self.running.is_some()
            || self.thinking
            || matches!(self.mode, Mode::Listening)
            || self.shown().iter().any(|&p| self.providers[p].reading && !self.providers[p].ready)
    }

    /// The providers whose rows the view on screen shows: they check for changes while it does (#37).
    pub fn shown(&self) -> Vec<usize> {
        match &self.view {
            View::Section(p) | View::Folder(p, _) => vec![*p],
            View::Dest(d) if *d != SETTINGS_DEST => self.dest_sections(*d),
            _ => vec![],
        }
    }

    /// Subscribe what is on screen, unsubscribe what left it; the rows of a place just opened read
    /// again when they are older than a few seconds, and the home's states when it comes back (#37).
    fn follow_view(&mut self, now: Instant) {
        let shown = self.shown();
        for i in 0..self.providers.len() {
            let on = shown.contains(&i);
            let (ready, sub, dead) = (self.providers[i].ready, self.providers[i].subscribed, self.providers[i].dead.is_some());
            if dead || !ready || on == sub {
                continue;
            }
            let uri = format!("spark-shell://{}/rows", self.providers[i].label);
            let method = if on { "resources/subscribe" } else { "resources/unsubscribe" };
            if let Some(s) = self.server(i) {
                s.request(method, json!({"uri": uri}), Kind::Subscribe, mcp::T_LIST);
            }
            self.providers[i].subscribed = on;
            let old = self.providers[i].last_read.map(|t| now.duration_since(t) >= STALE).unwrap_or(true);
            if on && old && !self.providers[i].reading {
                self.read(i);
            }
        }
        if self.view == View::Home && self.last_view.as_ref() != Some(&View::Home) {
            for i in 0..self.providers.len() {
                let p = &self.providers[i];
                if HOME_STATES.contains(&p.label.as_str())
                    && p.ready
                    && !p.reading
                    && p.dead.is_none()
                    && p.last_read.map(|t| now.duration_since(t) >= STALE).unwrap_or(true)
                {
                    self.read(i);
                }
            }
        }
        self.last_view = Some(self.view.clone());
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
        if let Some((p, _, _, _)) = self.running.clone() {
            if p == idx {
                self.running = None;
                self.say(
                    Sign::Refused,
                    &format!("{} stopped before it answered, so it may or may not have happened", label),
                );
                self.stop_queue();
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
        self.follow_lit();
    }

    /// The light back on the row a value was changed on, wherever the list moved it.
    fn follow_lit(&mut self) {
        let Some(id) = self.keep_lit.clone() else { return };
        if !self.in_list {
            self.keep_lit = None;
            return;
        }
        if let Some(i) = self.picks().iter().position(|it| self.row_ref(it).is_some_and(|r| r.id == id)) {
            self.sel = i;
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
                    if let Some(s) = self.server(idx) {
                        s.notify("notifications/initialized", json!({}));
                        s.request("tools/list", json!({}), Kind::Tools, mcp::T_LIST);
                    }
                    self.read(idx); // its subscription is follow_view's, only while its rows are on screen (#37)
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

    /// The clock: rows read again when they changed, deadlines kept, the subscriptions fitted to the view.
    pub fn tick(&mut self, now: Instant) {
        if self.busy() {
            self.frame += 1;
        }
        self.follow_view(now);
        let mut late = vec![];
        for s in self.servers.iter_mut() {
            for (_, p) in s.expired(now) {
                late.push((s.idx, p.kind));
            }
        }
        for (idx, kind) in late {
            match kind {
                Kind::Call(_) => {
                    if self.running.take().is_some() {
                        // no answer is no proof either way: say so, and run nothing that depends on it
                        self.say(
                            Sign::Refused,
                            &format!(
                                "no answer in {} s, so it may or may not have happened: look before you try again",
                                mcp::T_CALL.as_secs()
                            ),
                        );
                        self.stop_queue();
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
                // the folder on screen is this provider's too (the wallpaper list, a files folder): read again, kept up meanwhile, so a check moves to the row chosen (#29)
                if let View::Folder(fp, uri) = self.view.clone() {
                    if fp == i {
                        self.refresh_folder(fp, &uri);
                    }
                }
            }
        }
    }

    // ---- the list

    fn matches(&self, prov: usize, row: &model::Row) -> bool {
        let hay = format!("{} {}", self.providers[prov].label, row.text).to_lowercase();
        self.query().to_lowercase().split_whitespace().all(|w| hay.contains(w))
    }

    fn pickable(row: &model::Row) -> bool {
        row.tool.is_some() || row.children.is_some() || row.step.is_some()
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

    /// The exchange as content lines: the newest turn first, a turn the command as it ran (or the words
    /// of a question) and what came of it; the undo at hand is Undo at the end of the result it takes
    /// back, never a row of its own (#53); a blank row between turns; older turns while EXCHANGE_MAX
    /// lines hold them.
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
        let undo_at = if self.undo.is_some() {
            self.exchange.iter().rposition(|l| l.undo)
        } else {
            None
        };
        let mut lines = 0;
        for (k, t) in turns.iter().rev().enumerate() {
            let mut turn = vec![];
            if k > 0 {
                turn.push(Item::Blank); // a turn is a group: a blank row parts it from the newer one
            }
            for &i in t {
                let l = &self.exchange[i];
                // the line Undo ends keeps its room: the words wrap short of the chip
                let room = if Some(i) == undo_at { w.saturating_sub(UNDO_ROOM).max(10) } else { w };
                let parts = crate::ui::wrap(&l.text, room);
                let last = parts.len().saturating_sub(1);
                for (j, part) in parts.into_iter().enumerate() {
                    if Some(i) == undo_at && j == last {
                        turn.push(Item::Undo(l.sign.clone(), part, j == 0));
                    } else {
                        turn.push(Item::Said(l.sign.clone(), part, j == 0));
                    }
                }
            }
            if k > 0 && lines + turn.len() > EXCHANGE_MAX {
                break;
            }
            lines += turn.len();
            out.extend(turn);
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
            if !self.query().is_empty() && !self.matches(p, r) {
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

    /// The content area's items, in order: the exchange (the newest turn first, the undo at the end of
    /// its result), then the view's list.
    pub fn items(&self) -> Vec<Item> {
        let mut out = vec![];
        if self.view != View::About {
            self.said(&mut out);
        }
        let mut list = vec![];
        if self.asks_spark() {
            list.push(Item::Ask);
        }
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
                    if !self.query().is_empty() && !self.matches(*p, r) {
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
                    // a group starts under its heading, with air above it, as in a section
                    let prev = rows.rows[..i]
                        .iter()
                        .rev()
                        .find(|q| self.query().is_empty() || self.matches(*p, q))
                        .map(|q| q.group.clone());
                    if r.group.is_some() && prev.as_ref() != Some(&r.group) {
                        if !list.is_empty() {
                            list.push(Item::Blank);
                        }
                        list.push(Item::Heading(r.group.clone().unwrap_or_default()));
                    }
                    list.push(Item::Folder(i));
                }
            }
            View::Section(p) => self.section_rows(*p, &mut list, false),
            View::Dest(d) if *d == SETTINGS_DEST => {
                for i in self.settings() {
                    if self.query().is_empty() || self.word_in(SETTINGS[i].1) {
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
                if self.query().trim().is_empty() {
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
        self.query().to_lowercase().split_whitespace().all(|w| hay.contains(w))
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
            Item::Ask | Item::Undo(..) | Item::Dest(_) | Item::Setting(_) | Item::OpenModels => true,
            _ => false,
        }
    }

    pub fn picks(&self) -> Vec<Item> {
        self.items().into_iter().filter(|i| self.pickable_item(i)).collect()
    }

    /// Words are typed where a list is shown, in no question: they can go to spark as a request.
    pub fn asks_spark(&self) -> bool {
        self.mode == Mode::Normal
            && !self.query().trim().is_empty()
            && self.attaching.is_none()
            && self.picking.is_none()
            && matches!(self.view, View::Home | View::Section(_) | View::Dest(_) | View::Folder(..))
    }

    /// The name a pick goes by, as typed words are matched against it.
    fn name_of(&self, it: &Item) -> Option<String> {
        match it {
            Item::Row(p, r) => Some(self.providers[*p].rows.rows[*r].text.clone()),
            Item::Folder(i) => self.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)).map(|r| r.text.clone()),
            Item::Dest(d) => Some(DESTS[*d].name.to_string()),
            Item::Setting(i) => Some(SETTINGS[*i].1.to_string()),
            _ => None,
        }
        .map(|n| n.to_lowercase())
    }

    /// How well the words typed name a pick: 3 the name itself, 2 the start of it, 1 the start of a
    /// word in it, 0 not by name (the words may still be found in it).
    fn name_score(&self, it: &Item) -> u8 {
        let typed = self.query().trim().to_lowercase();
        let Some(name) = self.name_of(it) else { return 0 };
        if typed.is_empty() || typed.contains('\n') {
            0
        } else if name == typed {
            3
        } else if name.starts_with(&typed) {
            2
        } else if !typed.contains(' ') && name.split_whitespace().any(|w| w.starts_with(&typed)) {
            1
        } else {
            0
        }
    }

    /// The pick lit as words are typed: the one they name best; the request when they name none (#28),
    /// wherever it sits: the exchange's undo comes before it and runs only when picked (#39).
    pub fn best(&self) -> usize {
        let picks = self.picks();
        let mut best: Option<(u8, usize)> = None;
        for (i, it) in picks.iter().enumerate() {
            let sc = self.name_score(it);
            if sc > 0 && best.is_none_or(|(b, _)| sc > b) {
                best = Some((sc, i));
            }
        }
        best.map(|(_, i)| i).or_else(|| picks.iter().position(|it| *it == Item::Ask)).unwrap_or(0)
    }

    /// The words changed: the lit row follows them; with no words, nothing is lit.
    fn follow_words(&mut self) {
        if self.mode != Mode::Normal {
            return;
        }
        self.scroll = 0;
        if self.asks_spark() || (!self.query().trim().is_empty() && !self.picks().is_empty()) {
            self.in_list = true;
            self.sel = self.best();
        } else {
            self.in_list = false;
            self.sel = 0;
        }
    }

    /// A place's state for the home, from what its sections say now; None keeps what it is for.
    pub fn dest_state(&self, d: usize) -> Option<String> {
        let prov = |l: &str| self.providers.iter().find(|p| p.label == l && p.dead.is_none() && p.ready);
        let tools = |l: &str, names: &[&str]| -> Vec<String> {
            prov(l)
                .map(|p| {
                    p.rows
                        .rows
                        .iter()
                        .filter(|r| r.tool.as_ref().is_some_and(|t| names.contains(&t.name.as_str())))
                        .map(|r| r.text.clone())
                        .collect()
                })
                .unwrap_or_default()
        };
        let count = |n: usize, one: &str, many: &str| if n == 1 { format!("1 {}", one) } else { format!("{} {}", n, many) };
        let said = match DESTS[d].name {
            "Apps" => {
                let apps = tools("apps", &["apps_open", "apps_terminal"]);
                match apps.len() {
                    0 => return None,
                    1..=3 => apps.join(", "),
                    n => format!("{} and {} more", apps[..3].join(", "), n - 3),
                }
            }
            "Workspace" => {
                let w = tools("window", &["window_focus"]).len();
                let l = tools("layout", &["layout_open"]).len();
                let wins = if w == 0 {
                    "no windows open".to_string()
                } else {
                    count(w, "window", "windows")
                };
                if l == 0 {
                    wins
                } else {
                    format!("{}{}{}", wins, crate::ui::SEP, count(l, "layout", "layouts"))
                }
            }
            "Notes" => {
                let notes = tools("notes", &["notes_open"]);
                match notes.first() {
                    None => "no notes yet".to_string(),
                    Some(n) => format!("{}{}{}", count(notes.len(), "note", "notes"), crate::ui::SEP, n),
                }
            }
            "Calendar" => {
                // the first reminder, due or ahead: its sign is a dot or a ring, its group says when
                let p = prov("reminders")?;
                let next = p.rows.rows.iter().find(|r| r.group.is_some() && (r.sign == "dot" || r.sign == "ring"));
                match next {
                    None => "no reminders ahead".to_string(),
                    Some(r) => {
                        let at = r.columns.first().cloned().unwrap_or_default();
                        match r.group.as_deref().unwrap_or("") {
                            "due" => format!("due now: {}", r.text),
                            g @ ("today" | "tomorrow") => format!("{} {} {}", g, at, r.text),
                            _ => format!("{} {}", at, r.text),
                        }
                    }
                }
            }
            "Files" => "your home folder".to_string(),
            "Settings" => {
                let parts: Vec<String> = ["wifi", "theme"]
                    .iter()
                    .filter_map(|l| prov(l).map(|p| p.title.split(crate::ui::SEP).next().unwrap_or("").trim().to_string()))
                    .filter(|t| !t.is_empty())
                    .collect();
                if parts.is_empty() {
                    return None;
                }
                parts.join(crate::ui::SEP)
            }
            _ => return None,
        };
        Some(said)
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
        self.keep_lit = None;
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
        self.keep_lit = None;
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
        self.keep_lit = None;
        if c.is_control() {
            return;
        }
        self.insert(&c.to_string());
        self.follow_words();
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
        self.follow_words();
    }

    pub fn delete(&mut self) {
        if self.cursor >= self.input.chars().count() {
            return;
        }
        let a = self.byte_at(self.cursor);
        let b = self.byte_at(self.cursor + 1);
        self.input.replace_range(a..b, "");
    }

    /// Left and right: a lit row's own value first; in the Calendar with nothing typed, the months,
    /// whether the focus is in the prompt or in the reminders under them (#59); else the cursor in
    /// the draft.
    pub fn left(&mut self) {
        if self.step_value(false) {
            return;
        }
        if self.input.is_empty() && (!self.in_list || self.is_calendar()) {
            return self.month(-1);
        }
        self.cursor = self.cursor.saturating_sub(1);
    }

    pub fn right(&mut self) {
        if self.step_value(true) {
            return;
        }
        if self.input.is_empty() && (!self.in_list || self.is_calendar()) {
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
        self.keep_lit = None;
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            Mode::Confirm(_) => {
                self.say(Sign::Refused, "not done");
                self.input.clear();
                self.unstash();
                self.stop_queue();
            }
            Mode::Ask { step, .. } => {
                self.say(Sign::You, &step.line);
                self.say(Sign::Refused, "not done");
                self.input.clear();
                self.unstash();
                self.stop_queue();
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
                } else if let Some(st) = self.staged.take() {
                    // the commands spark planned are dropped: what was in the box before them comes back
                    let back = if self.input == st.text { st.draft } else { String::new() };
                    self.set_input(back);
                    self.in_list = false;
                    self.sel = 0;
                } else if !self.input.is_empty() {
                    self.set_input(String::new());
                    self.in_list = false;
                    self.sel = 0;
                } else if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                } else if self.exchange_up() {
                    // at the home with an exchange showing, Esc clears it first; the next Esc closes (#25)
                    self.exchange.clear();
                    self.undo = None;
                    self.value_turn = None;
                    self.sel = 0;
                } else {
                    self.quit = Some(0);
                }
            }
        }
    }

    /// Whether the content area shows an exchange or an undo that Esc would clear.
    pub fn exchange_up(&self) -> bool {
        self.running.is_none() && (!self.exchange.is_empty() || self.undo.is_some())
    }

    fn go_back(&mut self, v: View) {
        self.keep_lit = None;
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
        self.keep_lit = None;
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
                    self.say(Sign::Refused, "not done: it takes the word yes");
                    self.stop_queue();
                }
                return;
            }
            Mode::Ask { mut step, field, .. } => {
                let typed = std::mem::take(&mut self.input);
                self.unstash();
                if typed.trim().is_empty() {
                    self.say(Sign::You, &step.line);
                    self.say(Sign::Refused, &format!("not done: no {}", field));
                    self.stop_queue();
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
                self.say(Sign::You, &format!("model {}", name));
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
        // the commands spark planned, as they stand in the box: Enter runs them, in order (#53)
        if self.staged_now() && !self.in_list {
            if let Some(st) = self.staged.take() {
                self.set_input(st.draft); // what was typed while spark planned comes back
                self.sel = 0;
                self.queue.extend(st.steps);
                return self.next_step();
            }
        }
        if !self.in_list {
            // the prompt: a place's name alone opens it, a command runs, any other words are a request,
            // never a row that happens to match them (a question that names an app does not open it)
            let typed = self.input.trim().to_string();
            if typed.is_empty() {
                return;
            }
            self.set_input(String::new());
            return self.request(&typed);
        }
        let picks = self.picks();
        let sel = self.sel.min(picks.len().saturating_sub(1));
        let Some(item) = picks.get(sel).cloned() else { return };
        let words = self.input.trim().to_string();
        // a list filtered by the words typed: the words were a search, and go with the pick
        if matches!(self.view, View::Home | View::Section(_) | View::Dest(_) | View::Folder(..)) {
            self.set_input(String::new());
        }
        self.sel = 0;
        self.in_list = false;
        match item {
            Item::Ask => {
                // words that name no row: a place's name alone opens it (Window, Settings, about), a command
                // runs, any other words are a request
                if words.is_empty() {
                    return;
                }
                self.request(&words);
            }
            Item::Undo(..) => {
                if let Some(u) = self.undo.take() {
                    self.run(u);
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
                    let line = self.step_line(p, &call, &row.text);
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
                    let line = self.step_line(p, &call, &row.text);
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
        self.refresh_folder(p, uri);
    }

    /// The folder read again while its rows stay on screen: the answer replaces them.
    fn refresh_folder(&mut self, p: usize, uri: &str) {
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

    /// Words from the prompt: a place's name alone opens it; commands in the dialog's own words run at
    /// once, with no model; any other words go to spark, and the commands it plans come back to the
    /// box (#53).
    fn request(&mut self, words: &str) {
        if !words.contains('\n') {
            if let Some(v) = self.place(words) {
                if self.view != v {
                    self.go(v);
                }
                return;
            }
        }
        if let Some(steps) = self.commands(words) {
            self.queue.extend(steps);
            return self.next_step();
        }
        self.want(words);
    }

    /// Lines in the dialog's own words, each a step: None when any line is not one.
    pub fn commands(&self, text: &str) -> Option<Vec<Step>> {
        let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
        if lines.is_empty() {
            return None;
        }
        lines.iter().map(|l| self.command(l)).collect()
    }

    /// A line in the dialog's own words, as a step: a tool's title with a value in place of its capital
    /// word at the end ("display brightness 30"), the title with the most words of its own winning
    /// ("theme text bigger" over "theme NAME"); "undo" is the undo at hand. The value is read as its
    /// schema types it, and must fit it.
    fn command(&self, line: &str) -> Option<Step> {
        let words: Vec<&str> = line.split_whitespace().collect();
        if words.is_empty() {
            return None;
        }
        if words.len() == 1 && words[0].eq_ignore_ascii_case("undo") {
            return self.undo.clone();
        }
        let capital = |w: &str| !w.is_empty() && w.bytes().all(|c| c.is_ascii_uppercase());
        let mut best: Option<(usize, Step)> = None;
        for (p, prov) in self.providers.iter().enumerate() {
            if !prov.ready || prov.dead.is_some() {
                continue;
            }
            for t in &prov.tools {
                if t.title.is_empty() || !model::title_ok(&t.title) || t.name == "about_open" || t.name == "undo_all" {
                    continue;
                }
                let tw: Vec<&str> = t.title.split(' ').collect();
                let caps = tw.iter().filter(|w| capital(w)).count();
                let own = tw.len() - caps;
                if best.as_ref().is_some_and(|(o, _)| own <= *o) {
                    continue;
                }
                let fits = |n: usize| tw[..n].iter().zip(&words).all(|(a, b)| a.eq_ignore_ascii_case(b));
                let mut arguments = Map::new();
                match caps {
                    0 if words.len() == tw.len() && fits(tw.len()) => {}
                    1 if capital(tw[tw.len() - 1]) && words.len() >= tw.len() && fits(tw.len() - 1) => {
                        let Some(k) = one_argument(&t.schema) else { continue };
                        let Some(v) = typed_value(&t.schema, &k, &words[tw.len() - 1..].join(" ")) else {
                            continue;
                        };
                        arguments.insert(k, v);
                    }
                    _ => continue,
                }
                if gate::schema_ok(&t.schema, &arguments).is_err() {
                    continue;
                }
                let call = Call {
                    name: t.name.clone(),
                    arguments,
                    ask: vec![],
                };
                best = Some((
                    own,
                    Step {
                        prov: p,
                        call,
                        who: Who::Person,
                        line: words.join(" "),
                    },
                ));
            }
        }
        best.map(|(_, s)| s)
    }

    fn want(&mut self, words: &str) {
        if self.cfg.spark_shell.is_empty() {
            self.set_input(words.to_string());
            self.say(Sign::You, words);
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

    /// The plan from `spark-shell want --json`: each step gated here too. The steps come back to the
    /// box as commands, one a line, to run with Enter, a question's alike (#52, #53): nothing spark
    /// plans runs before that. Words that were the commands already run at once. An answer, or a step
    /// refused, is said under the words that asked.
    pub fn plan(&mut self, text: &str) {
        self.thinking = false;
        let words = self.pending.as_ref().map(|(w, _)| w.clone()).unwrap_or_default();
        let Ok(v) = serde_json::from_str::<Value>(text) else {
            self.say(Sign::You, &words);
            self.give_back();
            return self.say(Sign::Refused, "spark answered with nothing to run");
        };
        let answer = v.get("answer").and_then(Value::as_str).unwrap_or("").trim().to_string();
        let mut no: Vec<String> = v
            .get("refused")
            .and_then(Value::as_array)
            .map(|r| {
                r.iter()
                    .filter_map(Value::as_str)
                    .map(|t| t.trim_start_matches('\u{2717}').trim().to_string())
                    .collect()
            })
            .unwrap_or_default();
        let mut steps: Vec<Step> = vec![];
        for s in v.get("steps").and_then(Value::as_array).cloned().unwrap_or_default() {
            let Some(name) = s.get("name").and_then(Value::as_str) else { continue };
            let arguments = s.get("arguments").and_then(Value::as_object).cloned().unwrap_or_default();
            let line = scrub(s.get("line").and_then(Value::as_str).unwrap_or(name));
            // two steps are the dialog's own: undo is the undo at hand, about opens its about
            if name == "undo_all" {
                match self.undo.clone() {
                    Some(u) => steps.push(Step { line: "undo".into(), ..u }),
                    None => no.push("nothing to undo".into()),
                }
                continue;
            }
            if name == "about_open" {
                if self.about_idx.is_some() {
                    self.go(View::About);
                } else {
                    no.push(format!("{} is not offered here now", line));
                }
                continue;
            }
            let call = Call {
                name: name.to_string(),
                arguments,
                ask: vec![],
            };
            match self.providers.iter().position(|p| p.tools.iter().any(|t| t.name == name)) {
                None => no.push(format!("{} is not offered here now", line)),
                Some(p) => match gate::step(&self.providers[p].tools, &self.providers[p].rows, &call) {
                    Ok(()) => steps.push(Step {
                        prov: p,
                        call,
                        who: Who::Model,
                        line,
                    }),
                    Err(e) => no.push(format!("{} did not run: {}", line, e)),
                },
            }
        }
        // the words asked something spark answered, or it refused a step: those lines stay, under the words
        if !answer.is_empty() || !no.is_empty() {
            self.say(Sign::You, &words);
            if !answer.is_empty() {
                self.say(Sign::Says, &answer);
            }
            for t in &no {
                self.say(Sign::Refused, t);
            }
        }
        if steps.is_empty() {
            if answer.is_empty() {
                if no.is_empty() {
                    self.say(Sign::You, &words);
                    self.say(Sign::Refused, "spark found nothing to do for that");
                }
                return self.give_back(); // the words come back to be said again
            }
            self.pending = None;
            return;
        }
        self.pending = None;
        let lines: Vec<String> = steps.iter().map(|s| s.line.clone()).collect();
        let said = |t: &str| {
            t.lines()
                .map(|l| l.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase())
                .filter(|l| !l.is_empty())
                .collect::<Vec<_>>()
        };
        if said(&words) == said(&lines.join("\n")) {
            // the words were the commands: they run, as typed ones do
            self.queue
                .extend(steps.into_iter().map(|s| if s.who == Who::Model { Step { who: Who::Person, ..s } } else { s }));
            if self.running.is_none() && self.mode == Mode::Normal {
                self.next_step();
            }
            return;
        }
        let draft = std::mem::take(&mut self.input);
        let text = lines.join("\n");
        self.set_input(text.clone());
        self.in_list = false;
        self.sel = 0;
        self.staged = Some(Staged { text, steps, draft });
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
    fn stop_queue(&mut self) {
        if self.queue.is_empty() {
            return;
        }
        let left: Vec<String> = self.queue.drain(..).map(|s| s.line).collect();
        self.say(Sign::Refused, &format!("so these did not run: {}", left.join(", ")));
    }

    /// Whether a step waits for the typed yes: the provider's destructive hint, or this machine's own
    /// list. The hint alone never makes a step safe.
    pub fn risky(&self, tool: &Tool) -> bool {
        tool.destructive || LOCAL_RISK.contains(&tool.name.as_str())
    }

    /// A step: an argument asked when it lacks one; then its turn starts, the command as it runs (#53);
    /// a typed yes when it is risky, then the call.
    pub fn run(&mut self, step: Step) {
        if let Some(field) = step.call.ask.first().cloned() {
            let masked = gate::secret(&field, self.tool_of(&step).and_then(|t| t.schema.pointer(&format!("/properties/{}", field))));
            self.stash_draft();
            self.mode = Mode::Ask { step, field, masked };
            return;
        }
        if step.who == Who::Undo {
            self.undo = None; // the undo at hand is taken, wherever it came from (its row, "undo", spark)
        }
        self.say(Sign::You, &step.line);
        let Some(tool) = self.tool_of(&step).cloned() else {
            self.say(Sign::Refused, "this is not offered here now");
            return self.stop_queue();
        };
        if let Err(e) = self.checked(&step) {
            self.say(Sign::Refused, &e);
            return self.stop_queue();
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
            return Err("this is not offered here now".into());
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
                self.say(Sign::Refused, &format!("not done: {}", e));
                self.stop_queue();
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
                self.say(Sign::Refused, "not done: the part of the desktop that does it stopped");
                self.stop_queue();
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
            self.say(Sign::Refused, &e);
            self.stop_queue();
        } else if let Some(r) = result {
            let text = r.pointer("/content/0/text").and_then(Value::as_str).unwrap_or("");
            if refused {
                self.say(Sign::Refused, text);
                self.stop_queue();
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
                            if let Some((w, _)) = &self.pending {
                                let w = w.clone();
                                self.say(Sign::You, &w);
                            }
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
        // the commands spark planned wait in the box: Enter runs them, Esc drops them (#53)
        if self.staged_now() && !self.in_list {
            let mut v = key("Run", "Enter");
            v.extend(esc("Discard"));
            return v;
        }
        // what Esc does now: the words typed go first, then back a view, then what was said, then the dialog
        let esc_word = if !self.input.is_empty() {
            "Clear"
        } else if !self.came_from.is_empty() {
            "Back"
        } else if self.exchange_up() {
            "Clear"
        } else {
            "Close"
        };
        if self.in_list {
            let lit = self.picks().get(self.sel).cloned();
            if let Some(st) = lit.as_ref().and_then(|it| self.row_ref(it)).and_then(|r| r.step.clone()) {
                if self.input.is_empty() {
                    // a value: left and right change it, in place
                    let cap = |w: &str| w[..1].to_uppercase() + &w[1..];
                    let mut v = key(&cap(&st.words.0), "\u{2190}");
                    v.push(gap());
                    v.extend(key(&cap(&st.words.1), "\u{2192}"));
                    v.extend(esc(esc_word));
                    return v;
                }
            }
            let word = match &lit {
                Some(Item::Ask) => "Ask",
                Some(Item::Undo(..)) => "Undo",
                Some(Item::Model(_)) | Some(Item::TalkOpt(_)) => "Choose",
                Some(it) => match self.row_ref(it) {
                    Some(r) if r.children.is_none() && r.pick.is_none() => r.tool.as_ref().map(|t| verb_of(&t.name)).unwrap_or("Open"),
                    _ => "Open",
                },
                None => "Open",
            };
            let mut v = key(word, "Enter");
            if lit == Some(Item::Ask) {
                v.push(gap());
                v.extend(key("New line", "Shift+Enter"));
            }
            v.extend(esc(esc_word));
            if self.is_calendar() && self.input.is_empty() {
                // the months move from the reminders too (#59)
                v.push(gap());
                v.extend(key("Month", "\u{2190} \u{2192}"));
            }
            return v;
        }
        if !self.input.trim().is_empty() {
            // words where no list is shown (the about, the models): they go to spark as they are
            let mut v = key("Send", "Enter");
            v.push(gap());
            v.extend(key("New line", "Shift+Enter"));
            v.extend(esc(esc_word));
            return v;
        }
        // nothing typed and nothing lit: Esc, and the down arrow into the list
        let mut v = vec![(format!("{} ", esc_word), false), ("Esc".to_string(), true)];
        if self.is_calendar() {
            v.push(gap());
            v.extend(key("Month", "\u{2190} \u{2192}"));
        }
        v
    }

    /// The provider row an item stands for (a section's row, or a folder's).
    fn row_ref(&self, it: &Item) -> Option<&model::Row> {
        match it {
            Item::Row(p, r) => self.providers[*p].rows.rows.get(*r),
            Item::Folder(i) => self.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)),
            _ => None,
        }
    }

    /// A step's line as people read it, the command as typed: its tool's title with the arguments in
    /// place of the capital words (theme wallpaper NAME gives theme wallpaper none, out level N gives
    /// out level 60), never a secret; else the section and the row (#32).
    fn step_line(&self, p: usize, call: &Call, row_text: &str) -> String {
        let tool = self.providers[p].tools.iter().find(|t| t.name == call.name);
        let title = tool.map(|t| t.title.clone()).unwrap_or_default();
        if !title.is_empty() && model::title_ok(&title) {
            let schema = tool.map(|t| t.schema.clone()).unwrap_or(Value::Null);
            let mut args = call
                .arguments
                .iter()
                .filter(|(k, _)| !gate::secret(k, schema.pointer(&format!("/properties/{}", k))))
                .filter_map(|(_, v)| match v {
                    Value::String(s) => Some(s.clone()),
                    Value::Number(n) => Some(n.to_string()),
                    Value::Bool(b) => Some(if *b { "on" } else { "off" }.to_string()),
                    _ => None,
                });
            let words: Vec<String> = title
                .split(' ')
                .map(|w| {
                    if w.bytes().all(|c| c.is_ascii_uppercase()) {
                        args.next().unwrap_or_else(|| row_text.to_string())
                    } else {
                        w.to_string()
                    }
                })
                .collect();
            return words.join(" ");
        }
        format!("{} {}", self.providers[p].label, row_text)
    }

    /// Left or right on a value row: its step down or up, run as a pick is.
    fn step_value(&mut self, up: bool) -> bool {
        if !self.in_list || !self.input.is_empty() || self.mode != Mode::Normal {
            return false;
        }
        let Some(it) = self.picks().get(self.sel).cloned() else { return false };
        let prov = match &it {
            Item::Row(p, _) => *p,
            Item::Folder(_) => match &self.folder {
                Some((p, _, _)) => *p,
                None => return false,
            },
            _ => return false,
        };
        let Some(row) = self.row_ref(&it).cloned() else { return false };
        let Some(st) = row.step else { return false };
        let call = if up { st.more } else { st.less };
        self.keep_lit = Some(row.id.clone());
        // a run of presses on one value is one turn: this change takes the place of the last one's
        if let Some((id, at)) = self.value_turn.clone() {
            if id == row.id && self.running.is_none() && at < self.exchange.len() && self.exchange[at + 1..].iter().all(|l| l.sign != Sign::You) {
                self.exchange.truncate(at);
            }
        }
        self.value_turn = Some((row.id.clone(), self.exchange.len()));
        let line = self.step_line(prov, &call, &row.text);
        self.run(Step {
            prov,
            call,
            who: Who::Person,
            line,
        });
        true
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
