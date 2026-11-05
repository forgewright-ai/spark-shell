//! The dialog's state and what moves it: a key, a provider's message, a
//! helper's answer, the clock. Drawing is ui.rs; the terminal is main.rs.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HintKey {
    Enter,
    Ask,
    Conversation,
    PreviousControl,
    Start,
    End,
    PageUp,
    PageDown,
    Backspace,
    Delete,
    Quit,
    Escape,
    Newline,
    Tab,
    Left,
    Right,
    Up,
    Down,
    /// A character a key chip stands for (a preview's + - < >), typed as the key is.
    Char(char),
    /// The lit row's preview (F3); files: its check (Space), and the other pane made active (Ctrl+Tab).
    Check,
    Preview,
    Pane,
}

use crate::gate;
use crate::mcp::{self, Incoming, Kind, Server};
use crate::model::{self, Call, Rows, Tool};
use crate::preview::{self, Preview};
use crate::progress::Work;
use crate::reply::{Mark, Reply};
use crate::scrub::{cells, scrub};
use crate::search;
use crate::transition::Reel;
use serde_json::{json, Map, Value};
use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// The size, a design token: 60 by 40 cells, 3:4 in a 9 by 18 pixel cell. The window may be smaller:
/// the drawing takes the terminal's own size, MIN_WIDTH by MIN_HEIGHT at least.
pub const WIDTH: u16 = 60;
pub const HEIGHT: u16 = 40;
pub const MIN_WIDTH: u16 = 36;
pub const MIN_HEIGHT: u16 = 20;
/// The draft's length, in characters.
pub const INPUT_MAX: usize = 2000;
/// What the prompt says while it is empty.
/// What the prompt is for, in the two words the market settled on for a box that both filters a list and takes a
/// question (dialog/DESIGN.md): typing searches at once, and asking is a row among the results.
pub const PLACEHOLDER: &str = "search or ask";

impl App {
    /// What the empty prompt says it takes: a form of apps names the one thing to type (dialog/DESIGN.md).
    /// A layout's name being typed in the prompt: a form, as a category's name is in apps.
    pub fn layout_form(&self) -> bool {
        matches!(&self.mode, Mode::Ask { step, .. } if matches!(step.call.name.as_str(), "layout_save" | "layout_rename"))
    }

    pub fn placeholder(&self) -> &'static str {
        if let Mode::Ask { step, .. } = &self.mode {
            match step.call.name.as_str() {
                "layout_save" => return "a name for this layout",
                "layout_rename" => return "the new name",
                _ => {}
            }
        }
        if self.view == View::Apps {
            if let crate::apps::Page::Form(form) = &self.apps.page {
                return match form {
                    crate::apps::Form::AddCategory => "a name for the category",
                    crate::apps::Form::RenameCategory(_) => "the new name",
                    crate::apps::Form::AddMapping => "a desktop category, such as Network",
                };
            }
        }
        if let Some(p) = self.files_placeholder() {
            return p;
        }
        PLACEHOLDER
    }
}
/// Steps this machine counts as risky whatever their provider says (the hint is the provider's word,
/// the risk is decided here): a saved password gone, a window closed with its work, a layout written
/// over, a new device trusted.
pub const LOCAL_RISK: [&str; 3] = ["wifi_forget", "window_close", "bt_pair"];

/// The home's destinations: a name, what it is for, the sections it holds. Home rows are places;
/// commands are verbs; AI is what the prompt does, not a place.
pub struct Dest {
    pub name: &'static str,
    pub purpose: &'static str,
    pub sections: &'static [&'static str],
}
pub const DESTS: [Dest; 10] = [
    Dest {
        name: "apps",
        purpose: "open an application",
        sections: &["apps"],
    },
    Dest {
        name: "files",
        purpose: "browse your home",
        sections: &["files"],
    },
    Dest {
        name: "workspace",
        purpose: "windows and layouts",
        sections: &["window", "layout"],
    },
    Dest {
        name: "notes",
        purpose: "write and find",
        sections: &["notes"],
    },
    Dest {
        name: "calendar",
        purpose: "dates and reminders",
        sections: &["clock", "reminders"],
    },
    Dest {
        name: "tools",
        purpose: "utilities and diagnostics",
        sections: &[],
    },
    Dest {
        name: "settings",
        purpose: "devices and appearance",
        sections: &[],
    },
    Dest {
        name: "help",
        purpose: "commands and shortcuts",
        sections: &[],
    },
    Dest {
        name: "about",
        purpose: "project, license and credits",
        sections: &["about"],
    },
    Dest {
        name: "power",
        purpose: "lock, logout, restart, shutdown",
        sections: &["power"],
    },
];
pub const SETTINGS_DEST: usize = 6;
pub const HELP_DEST: usize = 7;
pub const TOOLS_DEST: usize = 5;
pub const CALENDAR_DEST: usize = 4;
pub const WORKSPACE_DEST: usize = 2;
/// The steps of the workspace place whose receipt stands on the status row, as a change of Apps does (dialog/DESIGN.md).
const WORKSPACE_SAYS: [&str; 13] = [
    "window_split",
    "window_tabs",
    "window_stacked",
    "window_restore",
    "window_move",
    "window_place",
    "window_close",
    "window_capture",
    "layout_save",
    "layout_rename",
    "layout_delete",
    "layout_restore",
    "layout_add",
];
/// Settings: a section each, then Talk and Connections, in this order, under their groups (#137); About is a
/// place of the home since v0.114 (#136).
pub const SETTINGS: [(&str, &str, &str); 17] = [
    ("out", "sound", "output and volume"),
    ("mic", "microphone", "input and level"),
    ("wifi", "Wi-Fi", "networks"),
    ("bt", "Bluetooth", "devices nearby"),
    ("lan", "network", "the wired connection"),
    ("storage", "storage", "drives and free space"),
    ("display", "display", "screens, brightness, lock"),
    ("keyboard", "keyboard", "layouts and key repeat"),
    ("pointer", "pointer", "mouse and touchpad"),
    ("theme", "theme", "palette, wallpaper and text"),
    ("wallpaper", "wallpaper", "the desktop picture"),
    ("bar", "bar", "the status bar"),
    ("notifications", "notifications", "do not disturb, the last few"),
    ("power", "power", "lock, suspend, restart"),
    ("bat", "battery", "charge"),
    ("talk", "talk", "click the mic, or off"),
    ("connections", "connections", "tools and the model"),
];

/// The group a row of Settings sits under, its heading (#137).
pub fn setting_group(label: &str) -> &'static str {
    match label {
        "out" | "mic" => "sound",
        "wifi" | "bt" | "lan" => "network",
        "storage" | "display" | "keyboard" | "pointer" => "devices",
        "theme" | "wallpaper" | "bar" | "notifications" => "look",
        _ => "system",
    }
}
/// What a search from Home finds, in the order its groups stand (#169): a heading each, the best few
/// of each, and a row that opens the rest of that kind.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Found {
    Places,
    Apps,
    Files,
    Notes,
    Reminders,
    Windows,
    Layouts,
    Settings,
}
pub const FOUND: [Found; 8] = [
    Found::Places,
    Found::Apps,
    Found::Files,
    Found::Notes,
    Found::Reminders,
    Found::Windows,
    Found::Layouts,
    Found::Settings,
];
/// The things of one kind a search from Home shows before the row that opens the rest (#169).
pub const FOUND_SHOWN: usize = 3;
/// How long typing rests before the providers are asked what they find for the words (#169).
pub const SEARCH_PAUSE: Duration = Duration::from_millis(250);

impl Found {
    /// The kind's heading, as the list writes it.
    pub fn name(self) -> &'static str {
        match self {
            Found::Places => "places",
            Found::Apps => "apps",
            Found::Files => "files",
            Found::Notes => "notes",
            Found::Reminders => "reminders",
            Found::Windows => "windows",
            Found::Layouts => "layouts",
            Found::Settings => "settings",
        }
    }

    /// The kind of a section's rows: a place's own, else a setting.
    pub fn of(label: &str) -> Found {
        match label {
            "apps" => Found::Apps,
            "files" => Found::Files,
            "notes" => Found::Notes,
            "reminders" => Found::Reminders,
            "window" => Found::Windows,
            "layout" => Found::Layouts,
            _ => Found::Settings,
        }
    }
}

/// What the up and down arrows move between in a preview: the thing a section's rows are (#169).
pub fn thing_of(label: &str) -> &'static str {
    match label {
        "apps" => "App",
        "notes" => "Note",
        "reminders" => "Reminder",
        "window" => "Window",
        "layout" => "Layout",
        "wifi" => "Network",
        "bt" => "Device",
        "storage" => "Drive",
        _ => "File",
    }
}

/// Elicitation's caps: a provider asks at most this often (the review's M1).
pub const ASK_PER_CALL: usize = 3;
pub const ASK_PER_MINUTE: usize = 10;
/// One redraw of a provider's rows per this long, however often it says they changed.
pub const READ_GAP: Duration = Duration::from_millis(250);
/// Rows older than this are read again when their place comes back on screen.
pub const STALE: Duration = Duration::from_secs(5);
/// The sections whose rows the home's places say (#36): read again when the home comes back.
/// How long a launch no window confirmed may still bring its window (the desktop's own wait for a slow app).
const LAUNCH_WAIT: Duration = Duration::from_secs(30);
/// Two clicks on one object's row within this act on it (dialog/DESIGN.md).
pub const DOUBLE_CLICK: Duration = Duration::from_millis(400);

pub const HOME_STATES: [&str; 6] = ["window", "layout", "notes", "reminders", "wifi", "theme"];

/// What Enter does to a row, in a word, from its tool's name: the hint says it (Use dracula, Connect a
/// network). A row that opens more is Open.
pub fn verb_of(tool: &str) -> &'static str {
    // a trashed file comes back (#130); a notification restored is shown again
    if tool == "files_restore" {
        return "Restore";
    }
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
        "mount" => "Mount",
        "unmount" => "Unmount",
        "eject" => "Eject",
        "dismiss" => "Dismiss",
        "restore" => "Show",
        "reveal" => "Reveal",
        "rename" => "Rename",
        "move" => "Move",
        "copy" => "Copy",
        "trash" => "Trash",
        "purge" => "Delete",
        "empty" => "Empty",
        "show" => "Show",
        "attach" => "Attach",
        "find" | "say" => "Find",
        "browse" => "Open",
        "folder" | "text" => "Make",
        "lock" => "Lock",
        "suspend" => "Suspend",
        "logout" => "Log out",
        "restart" => "Restart",
        "shutdown" => "Shut down",
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

/// The rows a provider finds for the words (#169): the files' names that hold them, the notes that say them.
pub fn search_uri(label: &str, kind: &str, words: &str) -> String {
    format!("spark-shell://{}/rows/{}/{}", label, kind, search::b64(words))
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
    // every label the dialog writes is lowercase; a section's name is its label said whole
    match label {
        "window" => "windows".into(),
        "layout" => "layouts".into(),
        "clock" => "calendar".into(),
        l => l.to_string(),
    }
}

/// A helper's error line as the reply row says it: its own words, but a raw error of the system (a program not
/// found, a pipe broken) is said plainly (#196).
fn plain_words(line: Option<&str>, fallback: &str) -> String {
    match line.map(str::trim).filter(|l| !l.is_empty()) {
        Some(l) if l.contains("No such file or directory") || l.contains("os error 2)") => {
            format!("{}: spark is not installed here", fallback)
        }
        Some(l) if l.contains("(os error") => format!("{}: the system refused to run it", fallback),
        Some(l) => l.to_string(),
        None => fallback.to_string(),
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

/// Whether a model answers, as the person last chose it on the model page: on unless they turned it off.
pub fn model_kept() -> bool {
    let said = state_dir().and_then(|d| std::fs::read_to_string(d.join("ask")).ok()).unwrap_or_default();
    said.trim() != "off"
}

fn model_keep(on: bool) {
    use std::os::unix::fs::DirBuilderExt;
    let Some(d) = state_dir() else { return };
    let _ = std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&d);
    let _ = std::fs::write(d.join("ask"), if on { "on\n" } else { "off\n" });
}

/// A line of the exchange: the words asked of spark, then what it said.
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
}

/// How far Left and Right move a sound or a video in the preview (#151).
pub const SEEK_SECONDS: f64 = 5.0;

/// A pick in progress: the view to go back to and how deep the stack was,
/// the provider and tool the file goes to, and the types offered. A folder
/// pick (#112) carries the step waiting for it, the argument it fills and
/// the words of the row that ends it ("move photo.png here").
#[derive(Clone, Debug, PartialEq)]
pub struct Picking {
    pub back: View,
    pub depth: usize,
    pub prov: usize,
    pub tool: String,
    pub types: Vec<String>,
    pub step: Option<Step>,
    pub field: String,
    pub what: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum View {
    Home,
    Apps,
    Help,
    Conversation,
    /// A destination of the home that holds more than one section, or none (Settings).
    Dest(usize),
    Section(usize),
    /// A folder (or any rows resource) under a provider: its uri.
    Folder(usize, String),
    /// The steps of one row of a provider (its tool and its more), as a list: Right on the row opens it (#112).
    Steps(usize),
    About,
    Models,
    /// How talk works: click to talk, or off.
    Talk,
    /// Settings > Connections: the tools the dialog talks to, and where the model runs.
    Connections,
    /// One file of a list, as large as the area allows (#120): the state is App::preview.
    Preview,
    /// Every thing of one kind a search from Home found for these words (#169).
    Found(Found, String),
}

/// How the person talks to the prompt. Holding a key waits for a spark that can finish a recording on
/// a signal; until then it is said, and not offered.
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

/// A value shown before the provider says it (#183): a step's place in its list, a switch's state, a
/// setting kept (a palette: its row checked, the others not).
#[derive(Clone, Debug, PartialEq)]
pub enum Held {
    At(usize),
    On(bool),
    Checked,
}

/// How long a value set in place is held over the rows read after its call came back.
const HOLD: Duration = Duration::from_millis(1500);

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
    /// The step in words ("theme nord"): what a list of steps not run names. Never drawn as a line.
    pub line: String,
    /// Typed words made it, not a click: its receipt is said in the reply row (#196).
    pub typed: bool,
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
    /// A code for the native pairing already started by the person.
    Pair {
        prov: usize,
        id: Value,
        message: String,
        kind: String,
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
    Apps(u64),
    /// spark's answer to a request, with the request's serial: an older one is dropped.
    Want(u64),
    Models,
    ModelSet,
    Listen,
    Voice,
    Client,
}

/// What the app asks the outside world to do; main.rs runs each in a thread.
#[derive(Clone, Debug, PartialEq)]
pub enum Job {
    RunInput(Helper, Vec<String>, String),
    Run(Helper, Vec<String>),
    StopListening,
}

/// An explicit row selection, independent of the search results while typing.
#[derive(Clone, Debug)]
pub struct Target {
    pub view: View,
    pub provider: usize,
    pub id: String,
    pub text: String,
}

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
    pub read_id: Option<u64>,
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
            read_id: None,
            subscribed: false,
        }
    }
}

/// What the command line chose (2.2 of the contract).
#[derive(Clone, Debug)]
pub struct Config {
    pub keys: crate::keys::Bindings,
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
    /// The folder of the transitions' piece in the palette in use (#122): open, wait and close.
    pub transitions: Option<String>,
}

impl Default for Config {
    fn default() -> Config {
        Config {
            keys: crate::keys::Bindings::default(),
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
            transitions: None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Apps(crate::apps::Line),
    /// A line of a page of files: the actions, a conflict's choices, a form.
    Files(crate::files::Line),
    Heading(String),
    Blank,
    Row(usize, usize),
    /// A row of the folder shown now.
    Folder(usize),
    /// A row a provider found for the words typed at Home (a file by its name, a note by what it says): App::hits (#169).
    Hit(usize),
    /// The row that opens the rest of one kind a search from Home found, and how many more there are (#169).
    More(Found, usize),
    /// A step of the row whose steps are shown: its index among the row's tool and its more.
    StepOf(usize),
    /// The row that ends a folder pick: the step lands in the folder shown (#112).
    Here,
    /// The row that asks spark the words typed (dialog/DESIGN.md): last among the matches, alone when nothing
    /// matches, so Enter asks; only while a model answers.
    Ask,
    /// A question's two rows (dialog/DESIGN.md, v0.127): the verb, which acts, and keep working, which lets the
    /// step go. The page stands in for the typed yes wherever a step is risky.
    Question(bool),
    /// A row of help (dialog/DESIGN.md, v0.127): what you do, and the key that does it, drawn as a chip.
    Key(String, String),
    Model(usize),
    /// A muted line under a page's title.
    Note(String),
    /// A destination of the home.
    Dest(usize),
    /// A row of Settings: its index in SETTINGS.
    Setting(usize),
    /// A line of the exchange as drawn: its sign, the words, the first of its lines.
    Said(Sign, String, bool),
    /// A way to talk.
    TalkOpt(Talk),
    /// Asking: a model answers (true), or off.
    ModelOpt(bool),
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
    pub prompts: crate::interaction::Prompts,
    pub apps: crate::apps::State,
    /// Files' own state over the folder list: checks, pages, the other pane, a batch (crate::files).
    pub files: crate::files::State,
    pub window_focused: bool,
    /// The request spark is answering now; an older reply is dropped.
    pub want_serial: u64,
    pub target: Option<Target>,
    pub cfg: Config,
    pub providers: Vec<Provider>,
    pub servers: Vec<Server>,
    pub view: View,
    /// The views behind this one: Esc goes back through them.
    pub came_from: Vec<View>,
    navigation: Vec<(View, usize, bool, usize, i32)>,
    /// The folder shown now: its provider, its uri, its rows once read.
    pub folder: Option<(usize, String, Rows)>,
    /// The row whose steps are shown (View::Steps), as it was when Right opened them.
    pub steps_row: Option<model::Row>,
    /// The heading shown alone in the workspace place (dialog/DESIGN.md).
    pub ws_filter: Option<String>,
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
    pub monday_first: bool,
    pub mode: Mode,
    /// The draft; a newline in it is Shift+Enter's, never a send.
    pub input: String,
    /// The cursor in the draft, in characters.
    pub cursor: usize,
    /// Requests from this window only. Forms and confirmations never enter here.
    prompt_history: VecDeque<String>,
    history_at: Option<usize>,
    history_draft: Option<(String, usize, Option<Target>)>,
    /// The draft kept while the prompt takes a yes, an argument or an answer for a provider.
    pub stash: Option<String>,
    /// The words and the file of the request in flight, given back if it fails.
    pub pending: Option<(String, Option<String>)>,
    /// Focus: the list (true) or the prompt (false); sel is the row in the list.
    pub in_list: bool,
    pub sel: usize,
    pub exchange: Vec<Line>,
    /// The reply row under the key row: the last receipt, refusal or note (#196).
    pub reply: Option<Reply>,
    pub undo: Option<Step>,
    pub queue: VecDeque<Step>,
    /// The commands spark planned, waiting in the input box for Enter (#53).
    pub staged: Option<Staged>,
    pub running: Option<(usize, u64, Step)>,
    /// The dialog stepped aside for a step that puts a window in front: main.rs makes the window clear
    /// while this holds, and solid again when it ends (#196).
    pub hidden: bool,
    /// The app home opened is in front: main.rs puts home away, once.
    pub stow: bool,
    /// A launch no window has confirmed, and until when the focus leaving home is taken for that app's window.
    pub launch_wait: Option<Instant>,
    /// The last click on an object's row, and when: a second within DOUBLE_CLICK acts on it (dialog/DESIGN.md).
    pub last_click: Option<(usize, Instant)>,
    pub busy_since: Option<Instant>,
    pub frame: u64,
    /// Every model spark lists: (name, serving | downloaded | -).
    pub models: Vec<(String, String)>,
    pub model_name: Option<String>,
    /// Where the model runs: None this computer, else the spark server's address (`spark client`).
    pub server: Option<String>,
    pub voice_on: bool,
    pub talk: Talk,
    /// Whether a model answers: the model page's choice, kept across runs (dialog/DESIGN.md).
    pub model_on: bool,
    /// Esc stopped the listening: what comes back is not said.
    pub listen_cancelled: bool,
    /// The window's size in cells, as the terminal says.
    pub size: (u16, u16),
    /// What spark or the machine is asked for and has not answered: the words (think), a model switch (swell).
    pub wait: Option<Work>,
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
    /// Words typed, then the down arrow or a click: the keys are the list's, so Space checks the lit file (#163).
    pub list_keys: bool,
    /// The preview shown (View::Preview): the list it came from, the file, its page (#120).
    pub preview: Option<Preview>,
    /// A sound's play or stop on its way: its request and its call, audited when it answers.
    quiet: Vec<(u64, usize, Call)>,
    /// A value being set in place (#183): the request, its provider, its row and the call.
    setting: Option<(u64, usize, String, Call)>,
    /// The values wanted while one was being set, the last one for each row only.
    set_next: Vec<(usize, String, Call)>,
    /// Values shown before the provider's rows say them: kept over every rows read until a moment after
    /// the last one was set, so a read that left before it never shows the old value again.
    held: Vec<(usize, String, Held, Option<Instant>)>,
    /// The transition playing, and since when (#122); main.rs moves it on and draws it.
    pub motion: Option<(Reel, Instant)>,
    /// The transitions are loaded: Esc that closes the dialog plays the close first.
    pub films: bool,
    /// The transitions to read again, a theme step having changed them (#126): a folder, or None for none.
    pub films_want: Option<Option<String>>,
    /// A text page's count as last drawn: how far right goes (the area decides it, so ui.rs does).
    pub preview_pages: usize,
    /// The rows the providers found for the words in hits_for: the files by name, the notes by what they say (#169).
    pub hits: Vec<(usize, model::Row)>,
    pub hits_for: String,
    /// When the words typed at Home last changed, until the providers are asked about them, and the words asked.
    pub search_at: Option<Instant>,
    pub search_sent: String,
    /// The list's column widths and its right edge as last drawn, and the view they are for: held while the view
    /// stays, so a longer name or state moves no column back and forth (#196). ui.rs keeps it as it draws.
    cols_held: std::cell::RefCell<Option<(View, Vec<usize>, u16)>>,
}

/// The view a name opens: home's own places, the bar's clock (the Calendar), else the section of that
/// provider; none for a name nothing here answers to. The start's --home and a bar click share it.
fn view_named(providers: &[Provider], name: &str) -> Option<View> {
    match name {
        "apps" => Some(View::Apps),
        "about" => Some(View::About),
        "chat" => Some(View::Conversation),
        "help" => Some(View::Help),
        "clock" | "reminders" => Some(View::Dest(CALENDAR_DEST)), // the bar's clock opens the Calendar
        "window" | "layout" => Some(View::Dest(WORKSPACE_DEST)),
        h => providers.iter().position(|p| p.label == h).map(View::Section),
    }
}

/// A window's name and title are labels, lowercase (dialog/DESIGN.md); here rather than at the provider, which has
/// no lowercase past ASCII.
fn lower_titles(rows: &mut [model::Row]) {
    for r in rows.iter_mut().filter(|r| r.tool.as_ref().is_some_and(|t| t.name == "window_focus")) {
        r.text = r.text.to_lowercase();
        r.columns.iter_mut().for_each(|c| *c = c.to_lowercase());
        if let Some(w) = r.wide.as_mut() {
            w.iter_mut().for_each(|c| *c = c.to_lowercase());
        }
        r.line = r.line.as_ref().map(|l| l.to_lowercase());
    }
}

impl App {
    pub fn new(cfg: Config, labels: &[String]) -> App {
        let providers: Vec<Provider> = labels.iter().map(|l| Provider::new(l)).collect();
        let about_idx = providers.iter().position(|p| p.label == "about");
        let view = cfg.home.as_deref().and_then(|h| view_named(&providers, h)).unwrap_or(View::Home);
        let came_from: Vec<View> = if matches!(view, View::About | View::Conversation | View::Help) {
            vec![View::Home]
        } else {
            vec![]
        }; // opened on the about (the first desktop start): Esc gives the list back
        App {
            prompts: Default::default(),
            apps: crate::apps::State::default(),
            files: crate::files::State::default(),
            window_focused: true,
            want_serial: 0,
            target: None,
            cfg,
            providers,
            servers: vec![],
            view,
            came_from,
            navigation: vec![],
            folder: None,
            attaching: None,
            attachment: None,
            picking: None,
            today: None,
            month_offset: 0,
            monday_first: false,
            mode: Mode::Normal,
            input: String::new(),
            cursor: 0,
            prompt_history: VecDeque::new(),
            history_at: None,
            history_draft: None,
            stash: None,
            pending: None,
            in_list: false,
            sel: 0,
            exchange: vec![],
            reply: None,
            undo: None,
            queue: VecDeque::new(),
            staged: None,
            running: None,
            hidden: false,
            stow: false,
            launch_wait: None,
            last_click: None,
            busy_since: None,
            frame: 0,
            models: vec![],
            model_name: None,
            server: None,
            voice_on: false,
            talk: talk_kept(),
            model_on: model_kept(),
            listen_cancelled: false,
            size: (WIDTH, HEIGHT),
            wait: None,
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
            list_keys: false,
            preview: None,
            quiet: vec![],
            setting: None,
            set_next: vec![],
            held: vec![],
            motion: None,
            films: false,
            films_want: None,
            preview_pages: 1,
            steps_row: None,
            ws_filter: None,
            hits: vec![],
            hits_for: String::new(),
            search_at: None,
            search_sent: String::new(),
            cols_held: std::cell::RefCell::new(None),
        }
    }

    /// A list's column widths and right edge, never narrower than they were drawn in this view: they grow once for a
    /// longer value and then stand still (#196).
    pub fn held_columns(&self, widths: Vec<usize>, right: u16) -> (Vec<usize>, u16) {
        let mut held = self.cols_held.borrow_mut();
        let (w, r) = match held.as_ref().filter(|(v, _, _)| *v == self.view) {
            Some((_, old, r0)) => {
                let n = widths.len().max(old.len());
                let w = (0..n)
                    .map(|k| widths.get(k).copied().unwrap_or(0).max(old.get(k).copied().unwrap_or(0)))
                    .collect();
                (w, right.max(*r0))
            }
            None => (widths, right),
        };
        *held = Some((self.view.clone(), w.clone(), r));
        (w, r)
    }

    pub fn say(&mut self, sign: Sign, text: &str) {
        let text = text.lines().map(scrub).collect::<Vec<_>>().join("\n");
        if text.is_empty() {
            return;
        }
        self.exchange.push(Line { sign, text });
        let n = self.exchange.len();
        if n > 200 {
            self.exchange.drain(..n - 200);
        }
    }

    /// The reply row says this, in place of what it said before (#196).
    pub fn reply(&mut self, mark: Mark, text: &str) {
        self.reply = Some(Reply::new(mark, text));
    }

    /// A refusal, in the reply row.
    pub fn refuse(&mut self, text: &str) {
        self.reply(Mark::Refused, text);
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
        (self.view == View::Apps && self.apps.pending.is_some())
            || self.running.is_some()
            || self.wait.is_some()
            || matches!(self.mode, Mode::Listening)
            || self.shown().iter().any(|&p| self.providers[p].reading && !self.providers[p].ready)
            || self.servers.iter().any(|s| s.pending.values().any(|p| p.kind == Kind::Page))
    }

    /// spark works on words: the header's march says so and nothing else does (#139). A step, a page, a place's
    /// rows show none: a page slow to come has its wait (#122), a step its row (#196).
    pub fn thinking(&self) -> bool {
        self.wait.is_some()
    }

    /// What spark's work is, for the march: its reply is think, its model loading is swell.
    pub fn work(&self) -> Work {
        self.wait.unwrap_or(Work::Think)
    }

    /// The providers whose rows the view on screen shows: they check for changes while it does (#37).
    pub fn shown(&self) -> Vec<usize> {
        match &self.view {
            View::Section(p) | View::Folder(p, _) | View::Steps(p) => vec![*p],
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

    pub(crate) fn server(&mut self, idx: usize) -> Option<&mut Server> {
        self.servers.iter_mut().find(|s| s.idx == idx && s.alive)
    }

    pub(crate) fn read(&mut self, idx: usize) {
        let uri = format!("spark-shell://{}/rows", self.providers[idx].label);
        let sent = self
            .server(idx)
            .and_then(|s| s.request("resources/read", json!({"uri": uri}), Kind::Read, mcp::T_READ));
        if let Some(id) = sent {
            self.providers[idx].reading = true;
            self.providers[idx].read_id = Some(id);
            self.providers[idx].dirty = false;
            self.providers[idx].last_read = Some(Instant::now());
        } else {
            self.providers[idx].reading = false;
        }
    }

    fn clear_pair(&mut self, idx: usize) {
        if matches!(&self.mode, Mode::Pair { prov, .. } if *prov == idx) {
            self.mode = Mode::Normal;
            self.input.clear();
            self.cursor = 0;
            self.unstash();
        }
    }

    fn lose(&mut self, idx: usize, why: &str) {
        self.clear_pair(idx);
        if self.providers[idx].dead.is_some() {
            return;
        }
        let label = self.providers[idx].label.clone();
        let was_shown = self.shown().contains(&idx);
        self.providers[idx].dead = Some(why.to_string());
        self.providers[idx].rows = Rows::default();
        self.providers[idx].tools.clear();
        self.providers[idx].reading = false;
        if self.target.as_ref().is_some_and(|t| t.provider == idx) || was_shown {
            self.want_cancel();
        }
        if let Some(s) = self.servers.iter_mut().find(|s| s.idx == idx) {
            s.close_stdin();
        }
        if self.running.as_ref().is_some_and(|(p, _, _)| *p == idx) {
            let step = self.running.take().map(|(_, _, s)| s);
            self.want_cancel();
            self.opened = false;
            self.hidden = false;
            let why = format!("{} stopped before it answered, so it may or may not have happened", label);
            if step.is_some_and(|s| self.files_batch_broken(&s, "stopped before it answered, so it may or may not have happened")) {
                return;
            }
            self.refuse(&why);
            self.stop_queue();
            return self.next_step();
        }
        self.refuse(&format!("{} stopped: {}", label, why));
    }

    /// A provider's message. True when it may change what is drawn: a notice that the rows changed only marks
    /// them to be read again, and a progress note only moves a march the header may not show, so neither asks for
    /// a frame (#196).
    pub fn incoming(&mut self, m: Incoming) -> bool {
        let shows = match &m {
            Incoming::Msg(_, v) => v.get("id").is_some() || v.get("method").and_then(Value::as_str) == Some("notifications/tools/list_changed"),
            Incoming::Gone(..) => true,
        };
        match m {
            Incoming::Gone(idx, why) => self.lose(idx, &why),
            Incoming::Msg(idx, v) => self.message(idx, v),
        }
        self.follow_lit();
        shows
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
            "spark-shell/pairing" => self.pair_question(idx, id, p),
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

    fn pair_question(&mut self, idx: usize, id: Value, p: Value) {
        let active = self
            .running
            .as_ref()
            .is_some_and(|(provider, _, step)| *provider == idx && step.call.name == "bt_pair");
        let native = !self.cfg.spark_shell.is_empty()
            && self
                .servers
                .iter()
                .any(|s| s.idx == idx && s.argv == [self.cfg.spark_shell.clone(), "provide".into(), "bt".into()]);
        let kind = p.get("kind").and_then(Value::as_str).unwrap_or("");
        if active && native && kind == "dismiss" {
            if matches!(&self.mode, Mode::Pair { prov, kind, .. } if *prov == idx && kind == "display") {
                self.clear_pair(idx);
            }
            if let Some(s) = self.server(idx) {
                s.answer(&id, json!({"action": "accept"}));
            }
            return;
        }
        if !active || !native || self.mode != Mode::Normal || self.asks_this_call >= ASK_PER_CALL || !matches!(kind, "pin" | "passkey" | "confirm" | "display")
        {
            if let Some(s) = self.server(idx) {
                s.answer(&id, json!({"action": "decline"}));
            }
            return;
        }
        self.asks_this_call += 1;
        self.input.clear();
        self.cursor = 0;
        self.mode = Mode::Pair {
            prov: idx,
            id,
            message: scrub(p.get("message").and_then(Value::as_str).unwrap_or("pairing")),
            kind: kind.to_string(),
        };
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
        let busy = !matches!(self.mode, Mode::Normal) || !self.running.as_ref().is_some_and(|(provider, _, _)| *provider == idx);
        if credential || busy || self.asks_this_call >= ASK_PER_CALL || self.asks.len() >= ASK_PER_MINUTE || props.is_empty() {
            if credential {
                self.refuse(&format!("{} asked for a secret: declined", self.providers[idx].label));
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
        let has_result = v.get("result").is_some();
        let has_error = v.get("error").is_some();
        let valid = v["jsonrpc"] == "2.0" && has_result != has_error && (!has_error || (v["error"]["code"].is_i64() && v["error"]["message"].is_string()));
        let result = if valid { v.get("result").cloned() } else { None };
        let error = if valid {
            v.get("error").and_then(|e| e.get("message")).and_then(Value::as_str).map(scrub)
        } else {
            Some("the provider returned an invalid protocol reply".into())
        };
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
                if self.providers[idx].read_id != Some(n) {
                    return;
                }
                self.providers[idx].reading = false;
                let text = result
                    .as_ref()
                    .and_then(|r| r.pointer("/contents/0/text"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if text.len() > mcp::RESOURCE_MAX {
                    return self.lose(idx, "its rows are over 512 kB");
                }
                if let Some(mut rows) = model::rows(text) {
                    if let Some(st) = &rows.state {
                        self.providers[idx].title = st.clone(); // the subtitle follows the section's state, step by step
                    }
                    if self.providers[idx].label == "window" {
                        lower_titles(&mut rows.rows); // a window's title is a label (dialog/DESIGN.md)
                    }
                    self.providers[idx].rows = rows;
                    self.hold_rows(idx);
                    self.providers[idx].ready = true;
                    self.workspace_follow(idx);
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
                    return self.refuse("that folder holds too much to show");
                }
                // the rows of the folder on screen, or of the other pane: an answer for a folder neither shows lands
                // nowhere (#112); a pick kept in a list (a wallpaper) stays checked over the read (#191)
                let of = result.as_ref().and_then(|r| r.pointer("/contents/0/uri")).and_then(Value::as_str).map(scrub);
                self.files_land(idx, n, of, model::rows(text), error);
            }
            Kind::Hits => {
                // what a provider found for the words: kept for the words typed now, an answer for older words lands nowhere
                let of = result.as_ref().and_then(|r| r.pointer("/contents/0/uri")).and_then(Value::as_str).map(scrub);
                let words = self.query().trim().to_string();
                let label = self.providers[idx].label.clone();
                let kind = if label == "files" { "match" } else { "find" };
                if words.is_empty() || of.as_deref() != Some(search_uri(&label, kind, &words).as_str()) {
                    return;
                }
                let text = result
                    .as_ref()
                    .and_then(|r| r.pointer("/contents/0/text"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let Some(rows) = model::rows(text).filter(|_| text.len() <= mcp::RESOURCE_MAX) else {
                    return;
                };
                let before = self.picks().get(self.sel).cloned().map(|it| {
                    let key = self.prov_of(&it).zip(self.row_ref(&it).map(|r| r.id.clone()));
                    (it, key)
                });
                if self.hits_for != words {
                    self.hits.clear();
                    self.hits_for = words;
                }
                self.hits.retain(|(p, _)| *p != idx);
                self.hits.extend(rows.rows.into_iter().map(|r| (idx, r)));
                self.relight(before);
            }
            Kind::Page => {
                let text = result
                    .as_ref()
                    .and_then(|r| r.pointer("/contents/0/text"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                // the page of the file and the page on screen alone: one asked for before a key moved on lands nowhere
                let of = result.as_ref().and_then(|r| r.pointer("/contents/0/uri")).and_then(Value::as_str).map(scrub);
                let Some(pv) = self.preview.as_mut().filter(|pv| pv.prov == idx) else {
                    return;
                };
                let want = pv.uri();
                if of.as_deref().is_some_and(|u| u != want) {
                    return;
                }
                match preview::page(&want, text).filter(|_| text.len() <= mcp::RESOURCE_MAX) {
                    Some(pg) => pv.shown = Some(pg),
                    None => {
                        pv.failed = true;
                        let name = pv.row().text.clone();
                        self.refuse(&error.unwrap_or_else(|| format!("{} could not be shown", name)));
                    }
                }
            }
            Kind::Quiet => {
                // a play and a stop may both be on their way: each answer finds its own, and both are audited (the review's H)
                let Some(k) = self.quiet.iter().position(|(q, p, _)| *q == n && *p == idx) else {
                    return;
                };
                let (_, p, call) = self.quiet.remove(k);
                let refused = error.is_some() || result.as_ref().and_then(|r| r.get("isError")).and_then(Value::as_bool).unwrap_or(false);
                let schema = self.providers[p]
                    .tools
                    .iter()
                    .find(|t| t.name == call.name)
                    .map(|t| t.schema.clone())
                    .unwrap_or(Value::Null);
                crate::audit::record(Who::Person.word(), &self.providers[p].label, &call.name, &schema, &call.arguments, refused);
                if refused {
                    if let Some(pv) = self.preview.as_mut() {
                        pv.playing = None;
                    }
                    let said = result
                        .as_ref()
                        .and_then(|r| r.pointer("/content/0/text"))
                        .and_then(Value::as_str)
                        .map(scrub)
                        .filter(|t| !t.is_empty())
                        .or(error)
                        .unwrap_or_else(|| "not played".into());
                    self.refuse(&said);
                }
            }
            Kind::Call(_) => {
                self.clear_pair(idx);
                self.called(idx, n, result, error)
            }
            Kind::Set => {
                let refused = error.is_some() || result.as_ref().and_then(|r| r.get("isError")).and_then(Value::as_bool).unwrap_or(false);
                let said = result
                    .as_ref()
                    .and_then(|r| r.pointer("/content/0/text"))
                    .and_then(Value::as_str)
                    .map(scrub)
                    .filter(|t| !t.is_empty())
                    .or(error)
                    .unwrap_or_else(|| "not changed".into());
                let mut fresh = false;
                if !refused {
                    if let Some(sc) = result.as_ref().and_then(|r| r.get("structuredContent")) {
                        self.wear_theme(idx, sc);
                        fresh = self.setting.as_ref().is_some_and(|(q, p, _, _)| *q == n && *p == idx) && self.take_rows(idx, sc);
                    }
                }
                self.set_done(idx, n, refused, &said, fresh);
            }
        }
    }

    /// The clock: rows read again when they changed, deadlines kept, the subscriptions fitted to the view.
    pub fn tick(&mut self, now: Instant) {
        if matches!(self.view, View::Apps | View::Home | View::Found(..)) && !self.apps.loaded && !self.apps.failed && self.apps.pending.is_none() {
            self.apps_request(json!({"op":"catalog"}));
        }
        if self.busy() {
            self.frame += 1;
        }
        // a sound that has played to its end: the key row says Play again
        if let Some(pv) = self.preview.as_mut() {
            if pv.playing.is_some() && !pv.plays(now) {
                pv.playing = None;
            }
        }
        self.follow_view(now);
        self.search_now(now);
        let mut late = vec![];
        for s in self.servers.iter_mut() {
            for (id, p) in s.expired(now) {
                late.push((s.idx, id, p.kind));
            }
        }
        for (idx, id, kind) in late {
            match kind {
                Kind::Call(_) => {
                    self.clear_pair(idx);
                    if self.running.as_ref().is_some_and(|(p, n, _)| *p == idx && *n == id) {
                        let step = self.running.take().map(|(_, _, s)| s);
                        self.want_cancel();
                        self.opened = false;
                        self.hidden = false;
                        // no answer is no proof either way: say so, and run nothing that depends on it
                        let why = format!(
                            "no answer in {} s, so it may or may not have happened: look before you try again",
                            mcp::T_CALL.as_secs()
                        );
                        if step.is_some_and(|s| self.files_batch_broken(&s, &why)) {
                            continue;
                        }
                        self.refuse(&why);
                        self.stop_queue();
                        self.next_step();
                    }
                }
                Kind::Read => {
                    if self.providers[idx].read_id == Some(id) {
                        self.providers[idx].reading = false;
                    }
                }
                Kind::Folder => {
                    self.files.folder_reads.retain(|(p, i, _)| !(*p == idx && *i == id));
                    self.refuse("the list did not come in time: Esc goes back")
                }
                Kind::Page => {
                    if let Some(pv) = self.preview.as_mut() {
                        pv.failed = true; // the wait ends with the words (#124)
                    }
                    self.refuse("the preview did not come in time: Enter opens the file")
                }
                Kind::Set => self.set_done(idx, id, true, "it did not answer in time", false),
                Kind::Quiet => {
                    self.quiet.retain(|(q, p, _)| !(*q == id && *p == idx));
                    if let Some(pv) = self.preview.as_mut() {
                        pv.playing = None;
                    }
                    self.refuse("the sound did not answer in time");
                }
                Kind::Init => self.lose(idx, "it did not answer"),
                _ => {}
            }
        }
        for i in 0..self.providers.len() {
            let p = &self.providers[i];
            if p.dirty && !p.reading && p.last_read.map(|t| now.duration_since(t) >= READ_GAP).unwrap_or(true) {
                self.read(i);
                // the folder on screen is this provider's too (the wallpaper list, a files folder): read again, kept up meanwhile, so a check moves to the row chosen (#29); the other pane with it
                self.refresh_panes(i);
            }
        }
    }

    // ---- the list

    fn matches(&self, prov: usize, row: &model::Row) -> bool {
        self.row_matches(prov, row, self.query())
    }

    /// Every word typed is in the row's words, its line, or its section's name.
    fn row_matches(&self, prov: usize, row: &model::Row, words: &str) -> bool {
        let hay = format!("{} {} {}", self.providers[prov].label, row.text, row.line.as_deref().unwrap_or("")).to_lowercase();
        words.to_lowercase().split_whitespace().all(|w| hay.contains(w))
    }

    pub fn pickable(row: &model::Row) -> bool {
        row.tool.is_some() || row.children.is_some() || row.step.is_some() || row.switch.is_some() || !row.more.is_empty() || row.back || row.page.is_some()
    }

    /// The sections present that a destination holds; Settings holds those of SETTINGS that run here.
    pub fn dest_sections(&self, d: usize) -> Vec<usize> {
        DESTS[d]
            .sections
            .iter()
            .filter_map(|s| self.providers.iter().position(|p| &p.label == s && p.dead.is_none()))
            .collect()
    }

    /// The rows of Settings shown here: a section that runs, Talk where talk is offered, Connections always.
    pub fn settings(&self) -> Vec<usize> {
        SETTINGS
            .iter()
            .enumerate()
            .filter(|(_, (l, _, _))| *l == "connections" || (*l == "talk" && self.cfg.talk) || self.providers.iter().any(|p| &p.label == l && p.dead.is_none()))
            .map(|(i, _)| i)
            .collect()
    }

    /// Every root destination remains discoverable, including unavailable ones.
    pub fn dests(&self) -> Vec<usize> {
        (0..DESTS.len()).collect()
    }

    /// The exchange as content lines: the newest turn first, a turn the command as it ran (or the words
    /// of a question) and what came of it; the undo at hand is Undo at the end of the result it takes
    /// back, never a row of its own (#53); a blank row between turns. All retained
    /// answers are readable by scrolling, without a rendered-line limit.
    fn said(&self, out: &mut Vec<Item>) {
        let w = self.col_w().saturating_sub(8).max(10) as usize; // the sign at 2, the words at 4, air at the right
        let mut turns: Vec<Vec<usize>> = vec![];
        for (i, l) in self.exchange.iter().enumerate() {
            if l.sign == Sign::You || turns.is_empty() {
                turns.push(vec![]);
            }
            if let Some(t) = turns.last_mut() {
                t.push(i);
            }
        }
        for (k, t) in turns.iter().rev().enumerate() {
            let mut turn = vec![];
            if k > 0 {
                turn.push(Item::Blank); // a turn is a group: a blank row parts it from the newer one
            }
            for &i in t {
                let l = &self.exchange[i];
                for (j, part) in crate::ui::conversation_rows(&l.text, w).into_iter().enumerate() {
                    turn.push(Item::Said(l.sign.clone(), part, j == 0));
                }
            }

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
        // the facts at a menu's end stand apart from its rows (power's uptime: dialog/DESIGN.md, v0.127)
        if let Some(last) = rows
            .iter()
            .rposition(|it| matches!(it, Item::Row(_, r) if Self::pickable(&self.providers[p].rows.rows[*r])))
        {
            if matches!(rows.get(last + 1), Some(Item::Row(..))) {
                rows.insert(last + 1, Item::Blank);
            }
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

    /// Whether a row of the workspace place stands: as a model answers or not, and by the words typed.
    fn workspace_keeps(&self, p: usize, r: &model::Row) -> bool {
        let model = self.cfg.model && self.model_on && self.model_name.is_some();
        r.when_model.is_none_or(|m| m == model) && (self.query().is_empty() || self.matches(p, r))
    }

    /// The workspace place (dialog/DESIGN.md): the windows under their workspaces, then the layouts, then a menu's
    /// rows. A heading shown alone keeps its rows alone.
    fn workspace_rows(&self, out: &mut Vec<Item>) {
        let secs = self.dest_sections(WORKSPACE_DEST);
        let mut heading: Option<&str> = None;
        for &p in &secs {
            for (i, r) in self.providers[p].rows.rows.iter().enumerate() {
                let Some(g) = r.group.as_deref() else { continue };
                if !self.workspace_keeps(p, r) || self.ws_filter.as_deref().is_some_and(|f| f != g) {
                    continue;
                }
                if heading != Some(g) {
                    if !out.is_empty() {
                        out.push(Item::Blank);
                    }
                    out.push(Item::Heading(g.to_string()));
                    heading = Some(g);
                }
                out.push(Item::Row(p, i));
            }
        }
        if self.ws_filter.is_some() {
            return;
        }
        let mut first = true;
        for &p in &secs {
            for (i, r) in self.providers[p].rows.rows.iter().enumerate() {
                if r.group.is_some() || !self.workspace_keeps(p, r) {
                    continue;
                }
                if first && !out.is_empty() {
                    out.push(Item::Blank);
                }
                first = false;
                out.push(Item::Row(p, i));
            }
        }
    }

    /// Help's rows (dialog/DESIGN.md, v0.127): a subject, what you do, the key that does it. The dialog's own keys
    /// first, as they are bound now; then the desktop's, as the about provider sends them, in their subjects; then
    /// the words typed at the prompt. Arrows, Home, End, Backspace and Delete need no help.
    pub fn help_rows(&self) -> Vec<(String, String, String)> {
        let k = |a: HintKey| self.cfg.keys.label(a).to_string();
        let mut rows: Vec<(String, String, String)> = vec![
            ("in home", "open what the bar is on", k(HintKey::Enter)),
            ("in home", "back a level; at home, close", k(HintKey::Escape)),
            ("in home", "ask spark the words", k(HintKey::Ask)),
            ("in home", "a new line in the prompt", k(HintKey::Newline)),
            ("in home", "the conversation, and back", k(HintKey::Conversation)),
            ("in home", "the prompt's tools, one to the next", k(HintKey::Tab)),
            ("in home", "a row's preview", k(HintKey::Preview)),
            ("in home", "a row's actions or details", k(HintKey::Right)),
            ("in home", "check a file, and the next", k(HintKey::Check)),
            ("in home", "the other pane", k(HintKey::Pane)),
            ("in home", "a page up, a page down", format!("{}  {}", k(HintKey::PageUp), k(HintKey::PageDown))),
            (
                "in a preview",
                "bigger, smaller, as it fits",
                format!("{}  {}  {}", k(HintKey::Char('+')), k(HintKey::Char('-')), k(HintKey::Char('0'))),
            ),
            (
                "in a preview",
                "the page before, the page after",
                format!("{}  {}", k(HintKey::Char('<')), k(HintKey::Char('>'))),
            ),
        ]
        .into_iter()
        .map(|(g, w, key)| (g.to_string(), w.to_string(), key))
        .collect();
        if let Some(p) = self.about_idx {
            for r in &self.providers[p].rows.rows {
                if let (true, Some(key), Some(g)) = (r.id.starts_with("about:key:"), &r.key, &r.group) {
                    rows.push((g.clone(), r.text.clone(), key.clone()));
                }
            }
        }
        for (w, key) in [
            ("search the list in front of you", "type"),
            ("take the last thing back", "undo"),
            ("a tool's words with its value", "display brightness 30"),
        ] {
            rows.push(("at the prompt".into(), w.into(), key.into()));
        }
        rows
    }

    /// How many keys help lists: the home's column.
    pub fn shortcuts(&self) -> usize {
        self.help_rows().iter().filter(|(g, _, _)| g != "at the prompt").count()
    }

    /// Help as a list (dialog/DESIGN.md, v0.127): the rows under their subjects, the ones the words typed name when
    /// there are words; then the note that the keys are yours to change.
    fn help_items(&self, list: &mut Vec<Item>) {
        let filtering = !self.query().trim().is_empty();
        let mut group: Option<String> = None;
        for (g, words, key) in self.help_rows() {
            if filtering && !self.word_in(&format!("{} {} {}", g, words, key)) {
                continue;
            }
            if group.as_deref() != Some(g.as_str()) {
                if group.is_some() {
                    list.push(Item::Blank);
                }
                list.push(Item::Heading(g.clone()));
                group = Some(g);
            }
            list.push(Item::Key(words, key));
        }
        if !filtering {
            list.push(Item::Blank);
            for l in crate::ui::wrap(
                "the keys are yours to change: home-keys.json for home, sway's config.d for the desktop",
                self.col_w().saturating_sub(8).max(10) as usize,
            ) {
                list.push(Item::Text(format!("  {}", l), true));
            }
        }
    }

    /// The workspace place's rows came again: a row's page follows its row, and a heading shown alone that has gone
    /// shows all.
    fn workspace_follow(&mut self, idx: usize) {
        if !matches!(self.providers[idx].label.as_str(), "window" | "layout") {
            return;
        }
        if let Some(id) = self.steps_row.as_ref().map(|r| r.id.clone()).filter(|_| self.step_prov() == Some(idx)) {
            match self.providers[idx].rows.rows.iter().find(|r| r.id == id).cloned() {
                Some(row) => self.steps_row = Some(row),
                None if matches!(self.view, View::Steps(_)) => {
                    self.steps_row = None;
                    if let Some(v) = self.came_from.pop() {
                        self.go_back(v);
                    }
                }
                None => {}
            }
        }
        if let Some(f) = self.ws_filter.clone() {
            let held = self
                .dest_sections(WORKSPACE_DEST)
                .iter()
                .any(|&p| self.providers[p].rows.rows.iter().any(|r| r.group.as_deref() == Some(f.as_str())));
            if !held && self.dest_sections(WORKSPACE_DEST).iter().all(|&p| self.providers[p].ready) {
                self.ws_filter = None;
            }
        }
    }

    /// The provider of the row whose steps are held: the view's, or the picker's opened from them.
    fn step_prov(&self) -> Option<usize> {
        match &self.view {
            View::Steps(p) | View::Folder(p, _) => Some(*p),
            _ => None,
        }
    }

    /// Arriving at the workspace place: the bar stands on the window that was in front, so Right acts on it.
    fn workspace_arrive(&mut self) {
        if self.view != View::Dest(WORKSPACE_DEST) {
            return;
        }
        let front = self
            .dest_sections(WORKSPACE_DEST)
            .iter()
            .find_map(|&p| self.providers[p].rows.rows.iter().find(|r| r.front).map(|r| r.id.clone()));
        if let Some(id) = front {
            self.in_list = true;
            self.keep_lit = Some(id);
            self.follow_lit();
        }
    }

    /// A click on a heading of the workspace place: that heading alone, or all again on the one shown alone.
    fn workspace_heading(&mut self, label: &str) {
        self.ws_filter = if self.ws_filter.as_deref() == Some(label) {
            None
        } else {
            Some(label.to_string())
        };
        self.reply = None;
        self.keep_lit = None;
        self.sel = 0;
        self.scroll = 0;
    }

    /// The header's words for the heading shown alone: `2 <symbol>` of a workspace, a heading's own words else.
    fn workspace_filter_words(&self) -> Option<String> {
        let f = self.ws_filter.as_deref()?;
        let head = f.split(crate::ui::SEP).next().unwrap_or(f);
        Some(head.strip_prefix("workspace ").unwrap_or(head).to_string())
    }

    /// The about (dialog/DESIGN.md, v0.127): the facts, the installed release with its date and the dialog's own
    /// under it, the purpose line; then the rows that open, project, license, credits and help; then where it is
    /// installed. The provider's key rows are help's, not listed here.
    fn about_items(&self, list: &mut Vec<Item>) {
        let Some(p) = self.about_idx else { return };
        let rows = &self.providers[p].rows.rows;
        let fact = |id: &str| rows.iter().find(|r| r.id == id).map(|r| r.text.clone());
        let w = self.col_w().saturating_sub(8) as usize; // the row column to two cells before the band's close
        let version = self.providers[p].version.trim_start_matches('v').to_string();
        let mut first = format!(
            "{:<13}{}",
            "spark-shell",
            if version.is_empty() {
                "release unknown here".to_string()
            } else {
                format!("v{}", version)
            }
        );
        if let Some(released) = fact("about:released") {
            let pad = w.saturating_sub(cells(&first) + cells(&released));
            if pad >= 2 {
                first = format!("{}{}{}", first, " ".repeat(pad), released);
            }
        }
        list.push(Item::Text(format!("  {}", first), false));
        list.push(Item::Text(format!("  {:<13}v{}", "spark-dialog", env!("CARGO_PKG_VERSION")), false));
        list.push(Item::Blank);
        list.push(Item::Text("  a lightweight sway shell".into(), true));
        list.push(Item::Blank);
        for (i, r) in rows.iter().enumerate() {
            if matches!(r.id.as_str(), "about:project" | "about:license" | "about:credits") {
                list.push(Item::Row(p, i));
            }
        }
        list.push(Item::Dest(HELP_DEST));
        if let Some(i) = rows.iter().position(|r| r.id == "about:installed") {
            list.push(Item::Blank);
            list.push(Item::Row(p, i));
        }
    }

    /// The content area's items: conversation turns or the current native view.
    /// Whether the ask row stands in the list: words typed in a view that searches by them, a model that answers,
    /// and nothing else waiting on the prompt (dialog/DESIGN.md).
    pub fn ask_row(&self) -> bool {
        let searching_view = match &self.view {
            View::Home | View::Dest(_) | View::Section(_) | View::Found(..) | View::Help => true,
            View::Folder(..) => !self.files_page_open(),
            View::Apps => matches!(self.apps.page, crate::apps::Page::List | crate::apps::Page::Hidden),
            _ => false,
        };
        let words = self.query().trim().to_string();
        // words the dialog runs itself are never a question: undo with an undo at hand, and a command in the dialog's
        // own words (theme dracula, display brightness 30) run on Enter with no model, as they always did. A place's
        // name selects its row, and the ask row stands under it as under any match
        let runs_here = (words.eq_ignore_ascii_case("undo") && (self.undo.is_some() || self.apps.undo.is_some())) || self.commands(&words).is_some();
        searching_view
            && self.mode == Mode::Normal
            && self.cfg.model
            && self.model_on
            && self.model_name.is_some()
            && !words.is_empty()
            && !runs_here
            && !self.staged_now()
            && self.attaching.is_none()
            && self.picking.is_none()
            && self.pending.is_none()
    }

    pub fn items(&self) -> Vec<Item> {
        // a question is a page of choices (dialog/DESIGN.md, v0.127): the step's line as the heading, one note,
        // the verb's row and keep working; it takes the whole list, whatever the view
        if let Mode::Confirm(step) = &self.mode {
            return self.question_items(step);
        }
        if self.view == View::Apps {
            let mut list: Vec<Item> = self
                .apps
                .lines(self.col_w(), &self.input, self.cfg.progress.then_some(self.frame))
                .into_iter()
                .map(Item::Apps)
                .collect();
            if self.ask_row() {
                if list.iter().any(|it| matches!(it, Item::Apps(l) if l.action.is_some())) {
                    list.push(Item::Blank);
                }
                list.push(Item::Ask);
            }
            return list;
        }
        if self.files_page_open() {
            // a page of files: its lines, a menu; no ask row over it
            let key = self.cfg.keys.label(HintKey::Check).to_string();
            return self.files.lines(self.col_w(), &key, &self.input).into_iter().map(Item::Files).collect();
        }
        let mut out = vec![];
        if self.view == View::Conversation {
            if let Some((words, _)) = &self.pending {
                for (i, line) in crate::ui::draft_rows(words, 0, self.col_w().saturating_sub(8) as usize)
                    .0
                    .into_iter()
                    .enumerate()
                {
                    out.push(Item::Said(Sign::You, line, i == 0));
                }
                out.push(Item::Blank);
            }
            self.said(&mut out);
        }
        let mut list = vec![];
        match &self.view {
            View::Apps => {}
            View::Models => {
                // asking comes first: a model answers, or off and nothing is asked (dialog/DESIGN.md)
                list.push(Item::Heading("asking".into()));
                list.push(Item::ModelOpt(true));
                list.push(Item::ModelOpt(false));
                list.push(Item::Blank);
                if let Some(name) = &self.model_name {
                    if cells(name) > self.col_w().saturating_sub(12) as usize {
                        list.push(Item::Heading("current model".into()));
                        self.text(&mut list, name, true);
                        list.push(Item::Blank);
                    }
                }
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
                self.text(&mut list, "Holding a key to talk needs a newer spark.", true);
                if !self.voice_on {
                    self.text(&mut list, "spark's voice is off: spark voice clear turns it on.", true);
                }
            }
            View::Connections => {
                // what is true of them all, said once; their names as Settings writes them; a row only for one that
                // stopped, with why (#146)
                list.push(Item::Heading("tools".into()));
                let tools: Vec<&Provider> = self
                    .providers
                    .iter()
                    .enumerate()
                    .filter(|(i, _)| Some(*i) != self.about_idx)
                    .map(|(_, p)| p)
                    .collect();
                let running: Vec<String> = tools.iter().filter(|p| p.dead.is_none()).map(|p| section_name(&p.label)).collect();
                let n: usize = tools.iter().filter(|p| p.dead.is_none()).map(|p| p.tools.len()).sum();
                list.push(Item::Text(format!("{} tools \u{b7} this computer, from spark-shell", n), false));
                self.text(&mut list, &running.join(", "), true);
                for p in tools.iter().filter(|p| p.dead.is_some()) {
                    list.push(Item::Text(
                        format!("{} stopped: {}", section_name(&p.label), p.dead.clone().unwrap_or_default()),
                        false,
                    ));
                }
                list.push(Item::Blank);
                list.push(Item::Heading("model".into()));
                list.push(Item::OpenModels);
            }
            View::Conversation | View::Preview => {}
            View::About => self.about_items(&mut list),
            View::Help => self.help_items(&mut list),
            View::Steps(p) => {
                // a window's page, a layout's: what it is above its steps, as an app's details have it
                if matches!(self.providers[*p].label.as_str(), "window" | "layout") {
                    if let Some(r) = &self.steps_row {
                        list.push(Item::Title(r.text.clone()));
                        if let Some(c) = r.columns.first().filter(|c| !c.is_empty()) {
                            list.push(Item::Note(c.clone()));
                        }
                        list.push(Item::Blank);
                    }
                }
                let n = self.steps_row.as_ref().map(|r| r.tool.iter().count() + r.more.len()).unwrap_or(0);
                for k in 0..n {
                    list.push(Item::StepOf(k));
                }
            }
            View::Folder(..) => {
                let Some((p, _, rows)) = &self.folder else { return out };
                // a folder being picked for a step: the row that lands it here first, then the folders alone
                let folder_pick = self.picking.as_ref().is_some_and(|pk| pk.step.is_some());
                if folder_pick && rows.here.is_some() {
                    list.push(Item::Here);
                }
                // attaching or picking, the files offered are of the types asked; the summary goes
                let types = match (&self.picking, &self.attaching) {
                    (Some(pk), _) => Some(pk.types.as_slice()),
                    (None, Some(_)) => Some(self.cfg.attach.as_slice()),
                    _ => None,
                };
                let lead = !list.is_empty();
                list.extend(self.folder_items(*p, rows, self.query(), folder_pick, types, lead));
            }
            View::Section(p) => self.section_rows(*p, &mut list, false),
            View::Dest(d) if *d == SETTINGS_DEST => {
                if self.query().is_empty() {
                    self.settings_items(&mut list);
                } else {
                    // what was typed, found, with no headings
                    for i in self.settings() {
                        if self.word_in(SETTINGS[i].1) {
                            list.push(Item::Setting(i));
                        }
                    }
                }
            }
            View::Dest(d) if *d == CALENDAR_DEST => {
                // the months are drawn above; clock preferences and reminders below them
                if let Some(p) = self.providers.iter().position(|p| p.label == "clock" && p.dead.is_none()) {
                    self.section_rows(p, &mut list, false);
                }
                if let Some(p) = self.providers.iter().position(|p| p.label == "reminders" && p.dead.is_none()) {
                    self.section_rows(p, &mut list, false);
                }
            }
            View::Dest(d) if *d == WORKSPACE_DEST => self.workspace_rows(&mut list),
            View::Dest(d) => {
                let secs = self.dest_sections(*d);
                let one = secs.len() == 1;
                if secs.is_empty() {
                    self.text(
                        &mut list,
                        if *d == TOOLS_DEST {
                            "No utilities are registered here yet. Native diagnostics: spark-shell status."
                        } else {
                            "This capability is unavailable in this session."
                        },
                        true,
                    );
                }
                for p in secs {
                    self.section_rows(p, &mut list, !one);
                }
            }
            View::Found(k, words) => {
                let all = self.found(words);
                let q = search::words(self.query());
                for it in all.into_iter().filter(|(f, _)| f == k).map(|(_, it)| it) {
                    if q.is_empty() || self.name_of(&it).is_some_and(|n| search::score(&q, &n).is_some()) {
                        list.push(it);
                    }
                }
            }
            View::Home => {
                if self.query().trim().is_empty() {
                    // the places in three groups: the everyday places, the system's, and power alone at the end. A
                    // menu breathes: a row of air between its rows when the window has the rows for it, two between
                    // its groups; the minimum window single spaces, a row of air between the groups, and scrolls
                    let dests = self.dests();
                    let room = self.size.1.saturating_sub(crate::ui::CONTENT_Y + crate::ui::BOTTOM) as usize;
                    let airy = room > dests.len() * 2;
                    for (k, d) in dests.iter().enumerate() {
                        let group = *d == SETTINGS_DEST || *d == DESTS.len() - 1;
                        if k > 0 && (airy || group) {
                            list.push(Item::Blank);
                        }
                        if airy && group {
                            list.push(Item::Blank);
                        }
                        list.push(Item::Dest(*d));
                    }
                } else {
                    // what was typed, found, in groups of a kind each (#169): the best few of each, then a row that opens the rest
                    let all = self.found(self.query());
                    for k in FOUND {
                        let of: Vec<Item> = all.iter().filter(|(f, _)| *f == k).map(|(_, it)| it.clone()).collect();
                        if of.is_empty() {
                            continue;
                        }
                        if !list.is_empty() {
                            list.push(Item::Blank);
                        }
                        list.push(Item::Heading(k.name().into()));
                        let n = of.len();
                        list.extend(of.into_iter().take(FOUND_SHOWN));
                        if n > FOUND_SHOWN {
                            list.push(Item::More(k, n - FOUND_SHOWN));
                        }
                    }
                }
            }
        }
        // asking is a row: last among the matches, with a row of air before it; alone when nothing matches
        if self.ask_row() {
            if list.iter().any(|it| self.pickable_item(it)) {
                list.push(Item::Blank);
            }
            list.push(Item::Ask);
        }
        if !out.is_empty() && !list.is_empty() {
            out.push(Item::Blank);
        }
        out.extend(list);
        out
    }

    /// A folder's rows as items, filtered by the words: a group under its heading with air above it (and above the
    /// first where a row leads the list), the summary row apart at the end; the folders alone during a folder pick,
    /// the types asked during a file pick.
    pub(crate) fn folder_items(&self, p: usize, rows: &Rows, words: &str, folder_pick: bool, types: Option<&[String]>, lead: bool) -> Vec<Item> {
        let mut list = vec![];
        for (i, r) in rows.rows.iter().enumerate() {
            if !words.is_empty() && !self.row_matches(p, r, words) {
                continue;
            }
            if folder_pick && r.children.is_none() {
                continue;
            }
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
                .find(|q| words.is_empty() || self.row_matches(p, q, words))
                .map(|q| q.group.clone());
            if r.group.is_some() && prev.as_ref() != Some(&r.group) {
                if !list.is_empty() || lead {
                    list.push(Item::Blank);
                }
                list.push(Item::Heading(r.group.clone().unwrap_or_default()));
            }
            list.push(Item::Folder(i));
        }
        list
    }

    /// Everything the words name, by kind, the best first in each (#169): the places and the settings by their names, every
    /// row of every section by its words (or its section's name), and what the providers found for these words (files
    /// by name, notes by what they say). A score ties to the shorter name, then to the order the rows came in.
    pub fn found(&self, typed: &str) -> Vec<(Found, Item)> {
        let words = search::words(typed);
        if words.is_empty() {
            return vec![];
        }
        let mut all: Vec<(Found, u32, usize, usize, Item)> = vec![];
        let add = |k: Found, sc: u32, name: &str, it: Item, all: &mut Vec<(Found, u32, usize, usize, Item)>| {
            let at = all.len();
            all.push((k, sc, cells(name), at, it));
        };
        // a place and a setting by their names, a setting by its section's too (wifi is Wi-Fi), and by what they are for,
        // a little ("volume" finds Sound)
        let named = |name: &str, also: &str, purpose: &str| {
            search::score(&words, name)
                .or_else(|| search::score(&words, also))
                .or_else(|| search::score(&words, purpose).map(|_| search::NEAR))
        };
        for d in self.dests() {
            if let Some(sc) = named(DESTS[d].name, "", DESTS[d].purpose) {
                add(Found::Places, sc, DESTS[d].name, Item::Dest(d), &mut all);
            }
        }
        for i in self.settings() {
            let (label, name, purpose) = SETTINGS[i];
            if let Some(sc) = named(name, label, purpose) {
                add(Found::Settings, sc, name, Item::Setting(i), &mut all);
            }
        }
        for a in &self.apps.entries {
            if self.apps.preference(&a.id).hidden {
                continue;
            }
            if let Some(sc) = named(&a.name, &a.display_name, &format!("{} {}", a.generic_name, a.description)) {
                let line = crate::apps::Line {
                    sign: "opens",
                    label: crate::scrub::cut_words(&a.name, 18),
                    value: crate::scrub::cut_words(&a.generic_name, self.col_w().saturating_sub(28) as usize),
                    value_x: 26,
                    action: Some(crate::apps::Action::Launch(a.id.clone())),
                    indent: 4,
                    value_muted: true,
                    ..crate::apps::Line::default()
                };
                add(Found::Apps, sc, &a.name, Item::Apps(line), &mut all);
            }
        }
        let mut seen: Vec<String> = vec![];
        for (p, prov) in self.providers.iter().enumerate() {
            if prov.dead.is_some() || prov.label == "apps" {
                continue;
            }
            // a section's name, three letters of it at least, holds its rows a little: "wifi" finds the networks, "wifi home"
            // the one; the files' rows are their roots, found by the place
            let (label, name) = (prov.label.clone(), section_name(&prov.label).to_lowercase());
            let names = |w: &String| prov.label != "files" && w.chars().count() >= 3 && (label.starts_with(w.as_str()) || name.starts_with(w.as_str()));
            for (i, r) in prov.rows.rows.iter().enumerate() {
                // the about's own row is found, its key sentences stay out; a row that only opens its own section is left
                // out, as the section's view leaves it (the setting opens it already)
                if !Self::pickable(r)
                    || (Some(p) == self.about_idx && !r.tool.as_ref().is_some_and(|t| t.name == "about_open"))
                    || r.children.as_deref() == Some(format!("spark-shell://{}/rows", prov.label).as_str())
                {
                    continue;
                }
                let sc = search::score(&words, &r.text).or_else(|| {
                    // every word in the row's words or the section's name, and one at least in the row's
                    let own: Vec<String> = words.iter().filter(|w| !names(w)).cloned().collect();
                    (own.len() < words.len())
                        .then(|| if own.is_empty() { Some(search::NEAR) } else { search::score(&own, &r.text) })
                        .flatten()
                });
                if let Some(sc) = sc {
                    seen.push(format!("{}\u{1f}{}", p, r.id));
                    add(Found::of(&prov.label), sc, &r.text, Item::Row(p, i), &mut all);
                }
            }
        }
        if self.hits_for == typed.trim() {
            for (i, (p, r)) in self.hits.iter().enumerate() {
                if self.providers[*p].label == "apps" || seen.contains(&format!("{}\u{1f}{}", p, r.id)) || !Self::pickable(r) {
                    continue;
                }
                // the provider found it: by its name (a file), or by what it says (a note, whose name may hold none of the words)
                let sc = search::score(&words, &r.text).unwrap_or(search::NEAR);
                add(Found::of(&self.providers[*p].label), sc, &r.text, Item::Hit(i), &mut all);
            }
        }
        all.sort_by(|a, b| b.1.cmp(&a.1).then(a.2.cmp(&b.2)).then(a.3.cmp(&b.3)));
        all.into_iter().map(|(k, _, _, _, it)| (k, it)).collect()
    }

    /// The list changed under the light, a provider's finds having come in (#169): where the words chose the lit row, it
    /// is the one they name best now; where a key chose it, it stays on that row, wherever it moved.
    fn relight(&mut self, before: Option<(Item, Option<(usize, String)>)>) {
        if !self.in_list {
            return;
        }
        if !self.list_keys {
            // the words still light the row they name best, else the ask row, as follow_words lights it: a search
            // answer landing after typing rested must not drop the ask row's selection (v0.124.4)
            match self.best().or_else(|| self.ask_pick()) {
                Some(i) => self.sel = i,
                None => (self.in_list, self.sel) = (false, 0),
            }
            return;
        }
        let Some((it, key)) = before else { return };
        let picks = self.picks();
        let at = picks.iter().position(|x| match &key {
            Some((p, id)) => self.prov_of(x) == Some(*p) && self.row_ref(x).is_some_and(|r| &r.id == id),
            None => *x == it,
        });
        if let Some(i) = at {
            self.sel = i;
        }
    }

    /// The list is what a search from Home found: the groups, or the rest of one kind (#169).
    pub fn searching(&self) -> bool {
        matches!(self.view, View::Found(..)) || (self.view == View::Home && !self.query().trim().is_empty())
    }

    /// The words typed at Home changed: the providers are asked what they find for them once typing rests (#169).
    fn search_later(&mut self) {
        if self.view == View::Home && !self.query().trim().is_empty() {
            self.search_at = Some(Instant::now());
        } else {
            self.search_at = None;
            if self.query().trim().is_empty() {
                self.search_sent.clear(); // the same words typed again are asked again (the review's N)
            }
        }
    }

    /// Typing rested: the files are asked for the names that hold the words, the notes for the ones that say them (#169).
    fn search_now(&mut self, now: Instant) {
        let Some(at) = self.search_at else { return };
        if now.duration_since(at) < SEARCH_PAUSE {
            return;
        }
        self.search_at = None;
        let words = self.query().trim().to_string();
        if self.view != View::Home || words.is_empty() || words == self.search_sent {
            return;
        }
        self.search_sent = words.clone();
        for (label, kind) in [("files", "match"), ("notes", "find")] {
            let Some(p) = self.providers.iter().position(|x| x.label == label && x.ready && x.dead.is_none()) else {
                continue;
            };
            let uri = search_uri(label, kind, &words);
            if let Some(s) = self.server(p) {
                s.request("resources/read", json!({"uri": uri}), Kind::Hits, mcp::T_READ);
            }
        }
    }

    /// Settings under their groups' headings, as Files parts its rows (#137).
    fn settings_items(&self, list: &mut Vec<Item>) {
        let mut group = "";
        for i in self.settings() {
            let g = setting_group(SETTINGS[i].0);
            if g != group {
                if !group.is_empty() {
                    list.push(Item::Blank);
                }
                list.push(Item::Heading(g.into()));
                group = g;
            }
            list.push(Item::Setting(i));
        }
    }

    /// Words that open nothing, wrapped to the content's width.
    /// The question's page for a risky step: its line as the heading, what it does in parentheses under it, a row
    /// of air, then the verb's row and keep working.
    fn question_items(&self, step: &Step) -> Vec<Item> {
        let mut list = vec![Item::Heading(self.question_line(step))];
        if let Some(note) = self.question_note(step) {
            for l in crate::ui::wrap(&format!("({})", note), self.col_w().saturating_sub(8).max(10) as usize) {
                list.push(Item::Text(format!("  {}", l), true));
            }
        }
        list.push(Item::Blank);
        list.push(Item::Question(true));
        list.push(Item::Question(false));
        list
    }

    /// What the step does, in one line: the last sentence of its tool's description, lowercase, its period dropped.
    fn question_note(&self, step: &Step) -> Option<String> {
        let d = self.tool_of(step)?.description.trim().trim_end_matches('.').to_string();
        let last = d.rsplit(". ").next().unwrap_or(&d).trim().to_lowercase();
        (!last.is_empty()).then_some(last)
    }

    /// The question's words: the row's own text where the step is a row's (`shutdown`), else the step's line
    /// (`close the window firefox`, as spark planned it), lowercase.
    fn question_line(&self, step: &Step) -> String {
        self.providers
            .get(step.prov)
            .and_then(|p| p.rows.rows.iter().find(|r| r.tool.as_ref() == Some(&step.call)))
            .map(|r| r.text.to_lowercase())
            .unwrap_or_else(|| step.line.to_lowercase())
    }

    /// The verb's row of the question.
    pub fn question_verb(&self) -> String {
        match &self.mode {
            Mode::Confirm(s) => self.question_line(s),
            _ => String::new(),
        }
    }

    fn text(&self, out: &mut Vec<Item>, words: &str, muted: bool) {
        for l in crate::ui::wrap(words, self.col_w().saturating_sub(6).max(10) as usize) {
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
            Item::Apps(line) => line.action.is_some(),
            Item::Files(line) => line.action.is_some(),
            Item::Row(p, r) => Self::pickable(&self.providers[*p].rows.rows[*r]),
            Item::Folder(i) => self
                .folder
                .as_ref()
                .and_then(|(_, _, rows)| rows.rows.get(*i))
                .map(Self::pickable)
                .unwrap_or(false),
            Item::Model(i) => self.models.get(*i).map(|(_, s)| s == "serving" || s == "downloaded").unwrap_or(false),
            Item::TalkOpt(_) => self.voice_on,
            Item::ModelOpt(_) | Item::Question(_) | Item::Key(..) => true,
            Item::Hit(i) => self.hits.get(*i).is_some_and(|(_, r)| Self::pickable(r)),
            Item::Dest(_) | Item::Setting(_) | Item::OpenModels | Item::StepOf(_) | Item::Here | Item::More(..) | Item::Ask => true,
            _ => false,
        }
    }

    /// Where the ask row stands among the picks, when it does.
    fn ask_pick(&self) -> Option<usize> {
        self.picks().iter().position(|it| matches!(it, Item::Ask))
    }

    pub fn picks(&self) -> Vec<Item> {
        self.items().into_iter().filter(|i| self.pickable_item(i)).collect()
    }

    /// The name a pick goes by, as typed words are matched against it.
    fn name_of(&self, it: &Item) -> Option<String> {
        match it {
            Item::Apps(line) if matches!(line.action, Some(crate::apps::Action::Launch(_))) => Some(line.label.clone()),
            // a page of files is a menu typed words narrow: the row they name best is lit, so Enter acts on it
            Item::Files(line) if line.action.is_some() => Some(line.label.clone()),
            Item::Row(p, r) => Some(self.providers[*p].rows.rows[*r].text.clone()),
            Item::Folder(i) => self.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)).map(|r| r.text.clone()),
            Item::Hit(i) => self.hits.get(*i).map(|(_, r)| r.text.clone()),
            Item::StepOf(k) => self.step_call(*k).map(|c| self.step_words(&c)),
            Item::Here => self.picking.as_ref().map(|pk| pk.what.clone()),
            Item::Dest(d) => Some(DESTS[*d].name.to_string()),
            Item::Setting(i) => Some(SETTINGS[*i].1.to_string()),
            Item::Key(words, _) => Some(words.clone()),
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
    pub fn best(&self) -> Option<usize> {
        let mut best: Option<(u8, usize)> = None;
        for (i, it) in self.picks().iter().enumerate() {
            let sc = self.name_score(it);
            if sc > 0 && best.is_none_or(|(b, _)| sc > b) {
                best = Some((sc, i));
            }
        }
        best.map(|(_, i)| i)
    }

    /// The words changed: the lit row follows them; with no words, nothing is lit.
    fn follow_words(&mut self) {
        self.list_keys = false;
        self.search_later();
        if self.mode != Mode::Normal {
            return;
        }
        self.scroll = 0;
        if self.view == View::Apps {
            if matches!(self.apps.page, crate::apps::Page::List | crate::apps::Page::Hidden) && !self.input.trim().is_empty() {
                let found = self
                    .picks()
                    .iter()
                    .position(|it| matches!(it, Item::Apps(line) if matches!(line.action, Some(crate::apps::Action::Launch(_)))))
                    .or_else(|| self.ask_pick()); // no app by these words: the ask row, so Enter asks
                self.in_list = found.is_some();
                self.sel = found.unwrap_or(0);
            } else {
                self.in_list = false;
                self.sel = 0;
            }
            return;
        }
        // Only searchable rows follow typing: the row the words name best is lit; words that name no row light the
        // ask row when a model answers, so Enter asks, and stay at the prompt otherwise. Model/connection/voice
        // controls keep their explicit keyboard selection; a request must not pick one.
        match self.best().filter(|_| !self.query().trim().is_empty()).or_else(|| self.ask_pick()) {
            Some(i) => {
                self.in_list = true;
                self.sel = i;
            }
            None => {
                self.in_list = false;
                self.sel = 0;
            }
        }
    }

    /// Enter on the ask row: the words go to spark as a request. From a place whose prompt is a filter (Apps, a
    /// folder) they move to the request first, in the conversation, so the filter stays what it was.
    fn ask_from_row(&mut self) {
        if self.request_prompt() {
            return self.ask();
        }
        let words = self.input.trim().to_string();
        self.set_input(String::new());
        self.go(View::Conversation);
        self.set_input(words);
        self.ask();
    }

    /// A place's state for the home (dialog/DESIGN.md): what it holds now, from what the dialog already has, cheaply;
    /// None keeps what it is for. Tools and power have no state worth more than their purpose.
    pub fn dest_state(&self, d: usize) -> Option<String> {
        let sep = crate::ui::SEP;
        let prov = |l: &str| self.providers.iter().find(|p| p.label == l && p.dead.is_none() && p.ready);
        match DESTS[d].name {
            "apps" => {
                // the catalog's counts, once it has been read (tick asks for it at the home)
                if !self.apps.loaded {
                    return None;
                }
                if self.apps.entries.is_empty() {
                    return Some("none installed".into());
                }
                let hidden = self.apps.hidden().len();
                let mut s = format!("{} installed", self.apps.visible("").len());
                if hidden > 0 {
                    s.push_str(&format!("{}{} hidden", sep, hidden));
                }
                return Some(s);
            }
            "files" => {
                // the folder's own summary, as the files section writes it
                let total = prov("files")?.rows.rows.iter().find(|r| r.id == "files:total")?.text.clone();
                return Some(format!("~{}{}", sep, total));
            }
            "settings" => {
                // the look and the screens, from what their sections say, whichever are known; never the network: a
                // network's name is no business of the home's first screen
                let mut parts = vec![];
                if let Some(t) = prov("theme")
                    .map(|p| p.title.split(sep).next().unwrap_or("").trim().to_string())
                    .filter(|t| !t.is_empty())
                {
                    parts.push(t.to_lowercase());
                }
                if let Some(t) = prov("display").map(|p| p.title.clone()).filter(|t| !t.is_empty()) {
                    parts.push(t.to_lowercase());
                }
                return (!parts.is_empty()).then(|| parts.join(sep));
            }
            "help" => return Some(format!("{} shortcuts", self.shortcuts())),
            "about" => {
                let v = self
                    .about_idx
                    .map(|i| self.providers[i].version.trim_start_matches('v').to_string())
                    .filter(|v| !v.is_empty())?;
                return Some(format!("spark-shell v{}", v));
            }
            "notes" | "calendar" => {}
            "workspace" => {
                // the windows open and their apps, each named once; the layouts where no window is. With no desktop
                // the window section says so, and the layouts are what the place holds
                if self.providers.iter().any(|p| p.label == "window" && p.dead.is_none() && !p.ready) {
                    return None;
                }
                let names = |l: &str, tool: &str| -> Vec<String> {
                    prov(l)
                        .map(|p| {
                            p.rows
                                .rows
                                .iter()
                                .filter(|r| r.tool.as_ref().is_some_and(|t| t.name == tool) && (l != "layout" || r.group.as_deref() == Some("layouts")))
                                .map(|r| r.text.to_lowercase())
                                .collect()
                        })
                        .unwrap_or_default()
                };
                let count = |n: usize, one: &str, many: &str| if n == 1 { format!("1 {}", one) } else { format!("{} {}", n, many) };
                let windows = names("window", "window_focus");
                let layouts = names("layout", "layout_open");
                let desktop = prov("window").is_some_and(|p| p.title != "no desktop");
                return if !windows.is_empty() {
                    let mut apps: Vec<&str> = vec![];
                    for w in &windows {
                        if !apps.contains(&w.as_str()) {
                            apps.push(w);
                        }
                    }
                    Some(format!("{}{}{}", count(windows.len(), "window", "windows"), sep, apps.join(", ")))
                } else if desktop {
                    Some(if layouts.is_empty() {
                        "no windows open".to_string()
                    } else {
                        format!("no windows open{}{}", sep, count(layouts.len(), "layout", "layouts"))
                    })
                } else if layouts.is_empty() {
                    None
                } else {
                    Some(format!("{}{}{}", count(layouts.len(), "layout", "layouts"), sep, layouts.join(", ")))
                };
            }
            _ => return None,
        }
        let count = |n: usize, one: &str, many: &str| if n == 1 { format!("1 {}", one) } else { format!("{} {}", n, many) };
        let said = match DESTS[d].name {
            "notes" => {
                // the count, the newest note's title and its date
                let p = prov("notes")?;
                let notes: Vec<&model::Row> = p.rows.rows.iter().filter(|r| r.tool.as_ref().is_some_and(|t| t.name == "notes_open")).collect();
                match notes.first() {
                    None => "no notes yet".to_string(),
                    Some(n) => {
                        let mut s = format!("{}{}{}", count(notes.len(), "note", "notes"), sep, n.text.to_lowercase());
                        if let Some(when) = n.columns.first().filter(|c| !c.is_empty()) {
                            s.push_str(&format!(", {}", when));
                        }
                        s
                    }
                }
            }
            "calendar" => {
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
        if self.preview_key() {
            return if self.zoomed() { self.preview_pan(0.0, -1.0) } else { self.preview_file(-1) };
        }
        self.keep_lit = None;
        if self.in_list {
            if self.sel == 0 {
                self.in_list = false; // above the first row is the prompt
                self.list_keys = false;
            } else {
                self.sel -= 1;
            }
        } else {
            let (l, c) = self.at();
            if l > 0 {
                self.put_at(l - 1, c);
            } else {
                self.recall_prompt(true);
            }
        }
    }

    pub fn down(&mut self) {
        if self.preview_key() {
            return if self.zoomed() { self.preview_pan(0.0, 1.0) } else { self.preview_file(1) };
        }
        self.keep_lit = None;
        if self.in_list {
            // words typed lit a file: the first Down hands the keys to the list and keeps it lit, so Space
            // checks it (#163)
            if !self.input.is_empty() && !self.list_keys {
                self.list_keys = true;
                if self.lit_has_page() {
                    return;
                }
            }
            if self.sel + 1 < self.picks().len() {
                self.sel += 1;
            }
            return;
        }
        let (l, c) = self.at();
        if l + 1 < self.lines() {
            self.put_at(l + 1, c);
        } else if self.history_at.is_some() && self.recall_prompt(false) {
            // Down restores the unfinished draft before it can enter the list.
        } else if !self.picks().is_empty() && self.chip_focus.is_none() {
            self.in_list = true;
            self.list_keys = true;
            self.sel = 0;
        }
    }

    /// The lit row is a file with a page of its own: Space can show it (#120).
    fn lit_has_page(&self) -> bool {
        self.in_list && self.picks().get(self.sel).and_then(|it| self.row_ref(it)).is_some_and(|r| r.page.is_some())
    }

    fn recall_prompt(&mut self, older: bool) -> bool {
        if self.mode != Mode::Normal
            || self.pending.is_some()
            || self.running.is_some()
            || self.staged.is_some()
            || self.chip_focus.is_some()
            || self.prompt_history.is_empty()
        {
            return false;
        }
        let next = match (self.history_at, older) {
            (None, true) => {
                self.history_draft = Some((self.input.clone(), self.cursor, self.target.clone()));
                Some(self.prompt_history.len() - 1)
            }
            (Some(i), true) => Some(i.saturating_sub(1)),
            (Some(i), false) if i + 1 < self.prompt_history.len() => Some(i + 1),
            (_, false) => None,
        };
        if let Some(i) = next {
            self.input = self.prompt_history[i].clone();
            self.cursor = self.input.chars().count();
            self.target = None;
        } else if let Some((draft, cursor, target)) = self.history_draft.take() {
            self.input = draft;
            self.cursor = cursor;
            self.target = target;
        }
        self.history_at = next;
        self.in_list = false;
        self.sel = 0;
        true
    }

    fn leave_history(&mut self) {
        self.history_at = None;
        self.history_draft = None;
    }

    fn remember_prompt(&mut self, words: &str) {
        self.leave_history();
        if words.is_empty() || words.chars().count() > INPUT_MAX {
            return;
        }
        if self.prompt_history.back().is_none_or(|last| last != words) {
            if self.prompt_history.len() == 50 {
                self.prompt_history.pop_front();
            }
            self.prompt_history.push_back(words.to_string());
        }
    }

    /// A key that types: it goes to the prompt, wherever the focus was.
    pub fn typed(&mut self, c: char) {
        if self.preview_picture_key(c) {
            return;
        }
        // Space with nothing typed, or with the keys on the list: back from a preview, a switch, a check (#120, #163)
        if c == ' ' && (self.input.is_empty() || self.list_keys) && self.mode == Mode::Normal && self.chip_focus.is_none() && self.pending.is_none() {
            if self.view == View::Preview {
                // a sound or a video: Space plays and pauses, as a player's does (#151); else back to the list
                if self.preview_plays() {
                    return self.preview_play_pause();
                }
                return self.escape();
            }
            if let Some(it) = self
                .picks()
                .get(self.sel)
                .cloned()
                .filter(|it| self.in_list && self.row_ref(it).is_some_and(|r| r.switch.is_some()))
            {
                self.flip_or_keep(&it); // a switch: Space flips it, as Enter and a click do (#183)
                return;
            }
            // in a files folder Space checks the lit row while it is the check key (v0.125.1, #224); a form's name takes the space
            if self.files_pane_view().is_some() && !self.files.form() && self.space_checks() {
                return self.files_check();
            }
            if self.in_list && self.input.is_empty() {
                return; // a lit row: Space is no letter of a search not begun (#196)
            }
        }
        self.text_key(c);
    }

    /// Whether Space is the check key (the default): then it checks in files, and keeps its other meanings elsewhere;
    /// rebound (Insert), Space is a plain key.
    fn space_checks(&self) -> bool {
        use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
        self.cfg.keys.action(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE)) == Some(HintKey::Check)
    }

    /// The check key: in a files folder, or on a files page, the check (Space by default); elsewhere the key does
    /// what Space does (a switch flips, a space is typed) while it is Space, and nothing
    /// once it is rebound.
    fn check_key(&mut self) {
        if self.files_pane_view().is_some() {
            // the check while the list holds the keys: nothing typed, or the keys handed to the list by Down or a
            // click; with words typed Space is a letter of the search (#163), and a form's name takes a space
            let list_keys = self.input.is_empty() || self.list_keys;
            if !self.files.form() && list_keys {
                return self.files_check();
            }
            if !self.space_checks() {
                return self.refuse("nothing to check here: Esc goes back to the list");
            }
        } else if !self.space_checks() {
            return;
        }
        self.typed(' ');
    }

    /// The preview key, F3: the lit row's preview, in any list with one, words typed or not: no word typed reaches a
    /// function key. Bound to a letter in a person's own keys, it previews while the list holds the keys, and is that
    /// letter everywhere else.
    fn preview_key_pressed(&mut self) {
        let bound = self.cfg.keys.label(HintKey::Preview);
        let letter = bound.chars().next().filter(|_| bound.chars().count() == 1).map(|c| c.to_ascii_lowercase());
        let typing = letter.is_some() && !self.input.is_empty() && !self.list_keys;
        let files_page = self.files_pane_view().is_some() && self.files.page != crate::files::Page::List;
        if !typing
            && !files_page
            && self.mode == Mode::Normal
            && self.chip_focus.is_none()
            && self.pending.is_none()
            && self.lit_has_page()
            && self.open_preview()
        {
            return;
        }
        if let Some(c) = letter {
            self.text_key(c);
        }
    }

    /// A printable key not bound to an action. Remapping removes its old shortcut.
    pub fn text_key(&mut self, c: char) {
        self.keep_lit = None;
        if c.is_control() {
            return;
        }
        // the question takes no words: its rows answer it
        if matches!(self.mode, Mode::Confirm(_)) {
            self.refuse("the question takes Enter on a row");
            return;
        }
        // typing is the prompt's: a control's focus (Tab) lets go, so Enter goes with the words, not the control
        self.chip_focus = None;
        // typing over the commands spark planned starts clean: the plan is dropped, as Esc drops it
        if self.staged_now() {
            self.staged = None;
            self.set_input(String::new());
        }
        self.insert(&c.to_string());
        self.follow_words();
    }

    fn plain_text_input(&self) -> bool {
        match &self.mode {
            Mode::Ask { step, field, masked: false } => self
                .tool_of(step)
                .and_then(|t| t.schema.get("properties"))
                .and_then(|p| p.get(field))
                .is_some_and(gate::plain_text),
            _ => false,
        }
    }

    /// Shift+Enter: a new line in a draft or an explicitly literal text field.
    pub fn newline(&mut self) {
        if self.mode == Mode::Normal || self.plain_text_input() {
            self.insert("\n");
        }
    }

    /// Pasted text goes into the draft as it is, its lines kept: a newline in it never sends. Where the
    /// prompt takes one line, the lines are joined by spaces.
    pub fn paste(&mut self, text: &str) {
        let plain = self.plain_text_input();
        let one = self.mode != Mode::Normal && !plain;
        let t: String = text
            .replace("\r\n", "\n")
            .replace('\r', "\n")
            .chars()
            .map(|c| if (c == '\t' && !plain) || (one && c == '\n') { ' ' } else { c })
            .filter(|c| *c == '\n' || (plain && *c == '\t') || !c.is_control())
            .collect();
        self.insert(&t);
    }

    fn insert(&mut self, t: &str) {
        self.leave_history();
        let room = INPUT_MAX.saturating_sub(self.input.chars().count());
        if self.plain_text_input() && t.chars().count() > room {
            return self.refuse(&format!("this prompt holds at most {} characters; the text was not added", INPUT_MAX));
        }
        if self.mode == Mode::Normal {
            self.remember_target();
        }
        self.chip_focus = None;
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

    pub(crate) fn set_input(&mut self, s: String) {
        self.leave_history();
        self.list_keys = false;
        self.cursor = s.chars().count();
        self.input = s;
    }

    pub fn backspace(&mut self) {
        if self.cursor == 0 {
            // an empty prompt: Backspace goes back a level, as a launcher's does (dialog/DESIGN.md)
            if self.can_go_back() {
                self.escape();
            }
            return;
        }
        self.leave_history();
        let a = self.byte_at(self.cursor - 1);
        let b = self.byte_at(self.cursor);
        self.input.replace_range(a..b, "");
        self.cursor -= 1;
        if self.input.is_empty() {
            self.target = None;
        }
        self.follow_words();
    }

    pub fn delete(&mut self) {
        if self.cursor >= self.input.chars().count() {
            return;
        }
        self.leave_history();
        let a = self.byte_at(self.cursor);
        let b = self.byte_at(self.cursor + 1);
        self.input.replace_range(a..b, "");
        if self.input.is_empty() {
            self.target = None;
        }
        self.follow_words();
    }

    /// A click in the prompt keeps an explicit row as the request's target.
    pub fn focus_prompt(&mut self) {
        self.remember_target();
        self.in_list = false;
        self.chip_focus = None;
    }

    /// Left and right: a lit row's own value first; in the Calendar with nothing typed, the months,
    /// whether the focus is in the prompt or in the reminders under them (#59); else the cursor in
    /// the draft.
    pub fn left(&mut self) {
        if self.preview_key() {
            if self.zoomed() {
                return self.preview_pan(-1.0, 0.0);
            }
            if self.preview_plays() {
                return self.preview_seek_by(-SEEK_SECONDS); // 5 s back (#151)
            }
            return self.preview_page(-1);
        }
        if self.step_value(false) {
            return;
        }
        // nothing typed, outside the Calendar: Left goes back a level, as Right opens one (dialog/DESIGN.md)
        if !self.is_calendar() && self.can_go_back() {
            return self.escape();
        }
        if self.input.is_empty() && (!self.in_list || self.is_calendar()) {
            return self.month(-1);
        }
        self.cursor = self.cursor.saturating_sub(1);
    }

    /// Whether there is a level above this one to go back to, with nothing in the way: a page of Apps under its
    /// list or the view this one came from; no words typed, no question open, no request pending, no commands
    /// staged, no form of Apps being filled (dialog/DESIGN.md).
    pub fn can_go_back(&self) -> bool {
        // a question's page keeps on every back door, the header's among them (dialog/DESIGN.md, v0.127)
        self.input.is_empty()
            && matches!(self.mode, Mode::Normal | Mode::Confirm(_))
            && self.chip_focus.is_none()
            && self.staged.is_none()
            && self.pending.is_none()
            && !(self.view == View::Apps && self.apps.form())
            && !(self.files_page_open() && self.files.form())
            && ((self.view == View::Apps && self.apps.has_back()) || (self.files_pane_view().is_some() && self.files.has_back()) || !self.came_from.is_empty())
    }

    pub fn right(&mut self) {
        if self.apps_details() {
            return;
        }
        if self.mode == Mode::Normal && self.chip_focus.is_none() && self.files_right() {
            return;
        }
        if self.preview_key() {
            return if self.zoomed() {
                self.preview_pan(1.0, 0.0)
            } else if self.preview_plays() {
                self.preview_seek_by(SEEK_SECONDS) // 5 s ahead (#151)
            } else {
                self.preview_page(1)
            };
        }
        if self.step_value(true) {
            return;
        }
        if self.open_steps() {
            return;
        }
        if self.input.is_empty() && (!self.in_list || self.is_calendar()) {
            return self.month(1);
        }
        self.cursor = (self.cursor + 1).min(self.input.chars().count());
    }

    /// Home and End: in a list, its first and its last row (a folder of a thousand, #123); else the
    /// line's start and end.
    pub fn line_start(&mut self) {
        if self.preview_key() && self.preview_plays() {
            return self.preview_seek(0.0); // Home: a sound or a video from its start (#151)
        }
        if self.in_list && !self.preview_key() {
            self.keep_lit = None;
            self.sel = 0;
            return;
        }
        let (l, _) = self.at();
        self.put_at(l, 0);
    }

    pub fn line_end(&mut self) {
        if self.in_list && !self.preview_key() {
            self.keep_lit = None;
            self.sel = self.picks().len().saturating_sub(1);
            return;
        }
        let (l, _) = self.at();
        self.put_at(l, usize::MAX);
    }

    /// Page up and down: in a list, the lit row by a screen of rows; else the content area, by most of
    /// its height.
    pub fn page(&mut self, d: i32) {
        // a page is the content's rows less one, so a line is shared between pages
        let step = self.size.1.saturating_sub(crate::ui::CONTENT_Y + crate::ui::BOTTOM + 1).max(4) as usize;
        if self.view == View::Apps && matches!(self.apps.page, crate::apps::Page::Details(_) | crate::apps::Page::Technical(_)) {
            self.scroll = crate::ui::body_scroll(self);
            self.in_list = false;
            self.list_keys = false;
            self.scroll = if d < 0 { self.scroll.saturating_sub(step) } else { self.scroll + step };
            return;
        }
        if self.in_list && !self.preview_key() {
            self.keep_lit = None;
            let last = self.picks().len().saturating_sub(1);
            self.sel = if d < 0 { self.sel.saturating_sub(step) } else { (self.sel + step).min(last) };
            return;
        }
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
    pub(crate) fn unstash(&mut self) {
        if let Some(s) = self.stash.take() {
            if self.input.is_empty() {
                self.set_input(s);
            }
        }
    }

    /// Esc: a question waiting is answered no (the draft comes back); the focus on a control or the
    /// draft goes first; then back one view; from the first view the dialog closes.
    pub fn escape(&mut self) {
        // files being copied, moved or trashed: Esc stops after the file under way, wherever you are (dialog/DESIGN.md)
        if self.mode == Mode::Normal && self.files_stop_batch() {
            return;
        }
        // a page of files: the actions or a conflict go back, a form is let go (dialog/DESIGN.md); the words first
        if self.files_page_open() && self.mode == Mode::Normal && self.chip_focus.is_none() && (self.input.is_empty() || self.files.form()) {
            return self.files_back();
        }
        // a heading shown alone in the workspace place: Esc shows all first, as apps' filter does (dialog/DESIGN.md)
        if self.view == View::Dest(WORKSPACE_DEST)
            && self.ws_filter.is_some()
            && self.mode == Mode::Normal
            && self.chip_focus.is_none()
            && self.input.is_empty()
        {
            self.ws_filter = None;
            self.reply = None;
            return;
        }
        // a form of Apps: Esc lets it go, words typed or none, and asks nothing; a page: back, once the words are cleared
        if self.view == View::Apps && self.mode == Mode::Normal && self.chip_focus.is_none() && (self.input.is_empty() || self.apps.form()) {
            // a category filter on the list: Esc shows all apps first (dialog/DESIGN.md, v0.124.4)
            if self.apps.page == crate::apps::Page::List && self.apps.filter.is_some() && self.input.is_empty() {
                self.reply = None;
                return self.apps_activate(crate::apps::Action::SetFilter(None));
            }
            if let Some(nav) = self.apps.back() {
                self.apps_restore(nav);
                self.reply = None;
                return;
            }
        }
        if matches!(self.motion, Some((Reel::Close, _))) {
            self.quit = Some(0);
            return;
        }
        self.target = None;
        // Esc clears the reply row, whatever else it does (#196)
        self.reply = None;
        // a request spark is still reading: Esc drops it, and the words come back
        if self.pending.is_some() && self.mode == Mode::Normal && !self.staged_now() {
            let words = self.pending.as_ref().map(|(w, _)| w.clone()).unwrap_or_default();
            self.want_cancel();
            if self.input.is_empty() {
                self.set_input(words);
            }
            return;
        }
        self.keep_lit = None;
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            // a question let go is a step not run: nothing is said, Esc said it (#196)
            Mode::Confirm(_) | Mode::Ask { .. } => {
                self.hidden = false;
                self.input.clear();
                self.unstash();
                // a batch's step let go stops the batch with it: the receipt says what was done
                if self.files.batch.is_some() {
                    self.files_stop_batch();
                }
                self.queue.clear();
            }
            Mode::Pair { prov, id, .. } | Mode::Elicit { prov, id, .. } => {
                if let Some(s) = self.server(prov) {
                    s.answer(&id, json!({"action": "cancel"}));
                }
                self.input.clear();
                self.unstash();
            }
            Mode::Apply(_) => {
                self.input.clear();
                self.unstash();
            }
            Mode::Listening => {
                // the recording is dropped, the prompt is yours at once; what comes back is not said (the review's D)
                self.listen_cancelled = true;
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
                } else if self.files_checks_clear() {
                    // the checks go first; the next Esc goes back (dialog/DESIGN.md)
                } else if self.zoomed() {
                    if let Some(pv) = self.preview.as_mut() {
                        pv.fit();
                    }
                } else if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                } else if self.exchange_up() {
                    // at the home with an exchange showing, Esc clears it first; the next Esc closes (#25);
                    // the undo at hand stays, typed undo takes it
                    self.exchange.clear();
                    self.sel = 0;
                } else {
                    self.close_window();
                }
            }
        }
    }

    /// Whether the content area shows an exchange that Esc would clear.
    pub fn exchange_up(&self) -> bool {
        self.view == View::Conversation && self.running.is_none() && !self.exchange.is_empty()
    }

    fn go_back(&mut self, v: View) {
        self.leave_plan();
        self.prompt_depart();
        self.navigation.retain(|(view, ..)| *view != self.view);
        self.navigation
            .push((self.view.clone(), self.sel, self.in_list, self.scroll, self.month_offset));
        // back from the rest of a kind to the home: the words come back, the search as it was (#169)
        let words = match (&self.view, &v) {
            (View::Found(_, w), View::Home) => Some(w.clone()),
            _ => None,
        };
        // back from a preview or from a row's steps: that row lit again, so F3 and the right arrow go on from it (#169)
        let lit = if self.view == View::Preview {
            self.stop_sound();
            self.preview.take().map(|pv| pv.row().id.clone())
        } else if matches!(self.view, View::Steps(_)) {
            self.steps_row.as_ref().map(|r| r.id.clone())
        } else {
            None
        };
        self.target = None;
        self.keep_lit = None;
        self.reply = None; // a reply is the view's it was said in: it never follows to another (#196)
        self.view = v;
        if self.view == View::Home {
            self.ws_filter = None;
        }
        self.prompt_arrive();
        self.sel = 0;
        self.in_list = false;
        self.scroll = 0;
        if self.attaching.as_ref().map(|(_, d)| self.came_from.len() < *d + 1).unwrap_or(false) {
            self.attaching = None;
        }
        if self.picking.as_ref().map(|pk| self.came_from.len() < pk.depth + 1).unwrap_or(false) {
            self.picking = None;
            self.files.pending = None;
        }
        self.files_on_view();
        if !matches!(self.view, View::Steps(_)) {
            self.steps_row = None;
        }
        if !matches!(self.view, View::Folder(..)) {
            self.folder = None;
        } else if let View::Folder(p, uri) = self.view.clone() {
            // the same folder's rows stay on screen while fresh ones come (back from a row's steps); another folder's go first
            if self.folder.as_ref().is_some_and(|(fp, fu, _)| *fp == p && *fu == uri) {
                self.refresh_folder(p, &uri);
            } else {
                self.read_folder(p, &uri);
            }
        }
        let restore_position = lit.is_none();
        if let Some(id) = lit {
            self.in_list = true;
            self.keep_lit = Some(id);
            self.follow_lit();
        }
        if let Some((_, sel, in_list, scroll, month)) = self.navigation.iter().find(|(view, ..)| restore_position && *view == self.view) {
            self.sel = *sel;
            self.in_list = *in_list;
            self.scroll = *scroll;
            self.month_offset = *month;
        }
        if let Some(w) = words {
            self.set_input(w);
            self.follow_words();
        }
    }

    /// Leaving a view while the box holds the commands spark planned: the plan is the conversation's and goes on
    /// the way out, as Esc drops it; what was typed before them comes back (v0.124.4).
    fn leave_plan(&mut self) {
        if self.staged_now() {
            if let Some(st) = self.staged.take() {
                self.set_input(st.draft);
            }
        }
    }

    /// A bar block clicked while home is open (lib/home.py's request, crate::goto): home goes to that
    /// block's section as a click on its row would, the draft and the way back kept; true when it moved.
    pub fn go_to(&mut self, name: &str) -> bool {
        match view_named(&self.providers, name) {
            Some(v) if v != self.view => {
                self.go(v);
                true
            }
            _ => false,
        }
    }

    pub(crate) fn go(&mut self, v: View) {
        let v = match v {
            View::Section(p) if matches!(self.providers[p].label.as_str(), "window" | "layout") => View::Dest(WORKSPACE_DEST),
            View::Section(p) => self.files_root(p).map(|root| View::Folder(p, root)).unwrap_or(View::Section(p)),
            other => other,
        };
        self.leave_plan();
        self.prompt_depart();
        self.navigation.retain(|(view, ..)| *view != self.view);
        self.navigation
            .push((self.view.clone(), self.sel, self.in_list, self.scroll, self.month_offset));
        self.target = None;
        self.keep_lit = None;
        self.reply = None;
        // a picker opened from a row's steps keeps them: the pick comes back to that page
        if v != View::Conversation && !(matches!(self.view, View::Steps(_)) && matches!(v, View::Folder(..))) {
            self.steps_row = None;
        }
        self.came_from.push(self.view.clone());
        self.view = v;
        self.files_on_view();
        self.prompt_arrive();
        self.sel = 0;
        self.in_list = false;
        self.scroll = 0;
        self.month_offset = 0;
        if let Some((_, sel, in_list, scroll, month)) = self.navigation.iter().find(|(view, ..)| *view == self.view) {
            self.sel = *sel;
            self.in_list = *in_list;
            self.scroll = *scroll;
            self.month_offset = *month;
        }
        if let View::Folder(p, uri) = self.view.clone() {
            self.read_folder(p, &uri);
        }
        self.workspace_arrive();
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
        if d == 0 {
            return View::Apps;
        }
        if d == HELP_DEST {
            return View::Help;
        }
        if d == SETTINGS_DEST || d == CALENDAR_DEST || d == WORKSPACE_DEST {
            return View::Dest(d);
        }
        if DESTS[d].sections == ["about"] {
            return View::About;
        }
        let secs = self.dest_sections(d);
        match secs.as_slice() {
            [p] => View::Section(*p),
            _ => View::Dest(d),
        }
    }

    pub fn enter(&mut self) {
        // the preview's Enter, nothing typed: the file opens in its app, as Files opens it
        if self.preview_key() {
            let Some(pv) = &self.preview else { return };
            let (p, row) = (pv.prov, pv.row().clone());
            self.stop_sound();
            if let Some(call) = row.tool {
                self.pick_step(p, call, &row.text);
            }
            return;
        }
        // the question's page (dialog/DESIGN.md, v0.127): Enter on the verb's row is the yes; on keep working, or
        // anywhere else, it keeps
        if matches!(self.mode, Mode::Confirm(_)) {
            let verb = self.in_list && matches!(self.picks().get(self.sel), Some(Item::Question(true)));
            if !verb {
                return self.escape();
            }
            if let Mode::Confirm(step) = std::mem::replace(&mut self.mode, Mode::Normal) {
                self.input.clear();
                self.unstash();
                self.hidden = false;
                self.approved(step);
            }
            return;
        }
        match std::mem::replace(&mut self.mode, Mode::Normal) {
            Mode::Confirm(_) => return,
            Mode::Ask { mut step, field, .. } => {
                let typed = std::mem::take(&mut self.input);
                self.unstash();
                let plain = self
                    .tool_of(&step)
                    .and_then(|t| t.schema.get("properties"))
                    .and_then(|p| p.get(&field))
                    .is_some_and(gate::plain_text);
                if if plain { typed.is_empty() } else { typed.trim().is_empty() } {
                    self.refuse(&format!("not done: no {}", field.replace('_', " ")));
                    self.stop_queue();
                    return;
                }
                step.call.arguments.insert(field.clone(), Value::String(typed));
                step.call.ask.retain(|a| a != &field);
                self.run(step);
                return;
            }
            Mode::Pair { prov, id, message, kind } => {
                if kind == "display" {
                    self.input.clear();
                    self.cursor = 0;
                    self.mode = Mode::Pair { prov, id, message, kind };
                    return;
                }
                let typed = std::mem::take(&mut self.input);
                self.cursor = 0;
                let answer = match kind.as_str() {
                    "confirm" | "display" => match typed.trim() {
                        "yes" => Some(Value::Bool(true)),
                        "no" => Some(Value::Bool(false)),
                        _ => None,
                    },
                    "passkey" if !typed.is_empty() && typed.len() <= 6 && typed.bytes().all(|c| c.is_ascii_digit()) => Some(Value::String(typed)),
                    "pin" if !typed.is_empty() && typed.len() <= 16 && typed.bytes().all(|c| (32..=126).contains(&c)) => Some(Value::String(typed)),
                    _ => None,
                };
                if let Some(answer) = answer {
                    if let Some(s) = self.server(prov) {
                        s.answer(&id, json!({"action": "accept", "content": {"answer": answer}}));
                    }
                    self.unstash();
                } else {
                    self.refuse(if kind == "confirm" || kind == "display" {
                        "type yes or no"
                    } else {
                        "enter the device code in the requested form"
                    });
                    self.mode = Mode::Pair { prov, id, message, kind };
                }
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
                answers.insert(k.clone(), Value::String(typed));
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
                self.wait = Some(Work::Swell); // spark's server restarts and loads the model: no estimate of how long
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
        // the ask row, lit by the words or by the arrows: Enter asks, in any list that has it
        if self.in_list && matches!(self.picks().get(self.sel), Some(Item::Ask)) {
            return self.ask_from_row();
        }
        if self.view == View::Apps {
            return self.apps_enter();
        }
        // a form of files: Enter saves the name typed
        if self.files_page_open() && self.files.form() && !self.in_list {
            return self.files_submit();
        }
        // a page of files is a menu: words that name no row of it ask nothing, and the status row says so
        if self.files_page_open() && !self.in_list && !self.input.trim().is_empty() {
            return self.refuse("no action by these words: Esc clears them");
        }
        // the commands spark planned, as they stand in the box: Enter runs them, in order (#53)
        if self.staged_now() && !self.in_list {
            if let Some(st) = self.staged.take() {
                self.set_input(st.draft); // what was typed while spark planned comes back
                self.sel = 0;
                self.queue.extend(st.steps.into_iter().map(|s| Step { typed: true, ..s }));
                return self.next_step();
            }
        }
        if !self.in_list && (self.attaching.is_some() || self.picking.is_some()) {
            // picking a file or a folder, the words typed find one: Enter picks the best, it never leaves the pick
            if self.input.trim().is_empty() || self.picks().is_empty() {
                return;
            }
            self.in_list = true;
            self.sel = self.best().unwrap_or(0);
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
        if let Item::Apps(line) = &item {
            if let Some(action) = &line.action {
                self.apps_activate(action.clone());
            }
            return;
        }
        if let Item::Files(line) = &item {
            if let Some(action) = &line.action {
                self.files_activate(action.clone());
            }
            return;
        }
        let words = self.input.trim().to_string();
        // a list filtered by the words typed: the words were a search, and go with the pick; commands spark
        // put in the box go too, so Space and the history are the list's again
        if matches!(self.view, View::Home | View::Section(_) | View::Dest(_) | View::Folder(..) | View::Found(..)) {
            self.staged = None;
            if !words.is_empty() && !matches!(item, Item::Dest(_) | Item::Setting(_) | Item::OpenModels | Item::More(..)) {
                self.set_input(String::new());
            }
        }
        // a switch flips and a value kept is set, found by words or not; a value row found by words stays lit
        if self.flip_or_keep(&item) {
            return self.follow_lit();
        }
        if !words.is_empty() && self.row_ref(&item).is_some_and(|r| r.step.is_some()) {
            self.keep_lit = self.row_ref(&item).map(|r| r.id.clone());
            return self.follow_lit();
        }
        match item {
            Item::StepOf(k) => {
                // one of the lit row's steps: back to its list, then the step as a pick of its own
                let (Some(row), View::Steps(p)) = (self.steps_row.clone(), self.view.clone()) else {
                    return;
                };
                let Some(call) = self.step_call(k) else { return };
                if let Some(uri) = call.children.clone() {
                    return self.open_children(p, &uri); // a choice: its list, and the pick comes back here
                }
                if call.name.ends_with("_preview") {
                    self.view = self.came_from.pop().unwrap_or(View::Home);
                    self.in_list = true;
                    self.keep_lit = Some(row.id.clone());
                    self.follow_lit();
                    self.open_preview();
                    return;
                }
                self.steps_row = None; // a step run from the list: the light is not put back on a row it may have taken away
                if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                }
                self.pick_step(p, call, &row.text);
            }
            Item::Here => {
                // the folder shown is the one picked: the step waiting for it runs with it, and the list stays here
                let Some(pk) = self.picking.take() else { return };
                let Some(mut step) = pk.step else { return };
                let Some(here) = self.folder.as_ref().and_then(|(_, _, r)| r.here.clone()) else {
                    return;
                };
                step.call.arguments.insert(pk.field.clone(), Value::String(here.clone()));
                step.call.pick = None;
                self.came_from.truncate(pk.depth);
                // landed in the folder the pick began in: the copy pushed so Esc could cancel goes (the review's B)
                if self.came_from.last() == Some(&self.view) {
                    self.came_from.pop();
                }
                self.sel = 0;
                // a files copy or move: the names already here are asked about first, and several files go as one
                if self.files_picked(step.clone(), &here) {
                    return;
                }
                self.run(step);
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
                if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                }
            }
            Item::ModelOpt(on) => {
                // the choice applies at once and is kept; back to where the model control was clicked
                self.model_on = on;
                model_keep(on);
                self.reply = None;
                if let Some(v) = self.came_from.pop() {
                    self.go_back(v);
                }
            }
            Item::Model(i) => {
                let (name, state) = self.models[i].clone();
                if state == "serving" {
                    return; // the one in use: nothing to change
                }
                // browsing changed nothing; this is the review: what changes, and for whom
                let who = match &self.server {
                    Some(s) => format!("everyone who uses {}", s),
                    None => "every client of this computer's spark".to_string(),
                };
                self.reply(
                    Mark::Note,
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
            Item::More(k, _) => self.go(View::Found(k, words)),
            Item::Hit(i) => {
                let Some((p, row)) = self.hits.get(i).cloned() else { return };
                if let Some(c) = row.children {
                    self.open_children(p, &c);
                } else if let Some(call) = row.tool {
                    self.pick_step(p, call, &row.text);
                } else if !row.more.is_empty() {
                    self.steps_of(p, row);
                }
            }
            Item::Row(p, r) => {
                let row = self.providers[p].rows.rows[r].clone();
                if let Some(pk) = &row.pick {
                    // a pick opens the files at the home folder, offering the types it takes
                    let Some(f) = self.files() else {
                        return self.refuse("no files to pick from");
                    };
                    let Some(root) = self.providers[f].rows.rows.iter().find_map(|r| r.children.clone()) else {
                        return self.refuse("no folder to pick from");
                    };
                    self.picking = Some(Picking {
                        back: self.view.clone(),
                        depth: self.came_from.len(),
                        prov: p,
                        tool: pk.tool.clone(),
                        types: pk.types.clone(),
                        step: None,
                        field: String::new(),
                        what: String::new(),
                    });
                    self.open_children(f, &root);
                } else if let Some(c) = row.children {
                    self.open_children(p, &c);
                } else if let Some(call) = row.tool {
                    if call.name == "about_open" {
                        return self.go(View::About);
                    }
                    self.pick_step(p, call, &row.text);
                } else if !row.more.is_empty() {
                    // a row that is only its steps (a saved network not around, #169): Enter opens them, as Right does
                    self.steps_of(p, row);
                } else if row.page.is_some() {
                    // a row that is only its page (the license, the credits): Enter reads it, as P does
                    self.open_preview();
                }
            }
            Item::Folder(i) => {
                let Some((p, _, rows)) = self.folder.clone() else { return };
                let Some(row) = rows.rows.get(i).cloned() else { return };
                if row.back {
                    // a pick among choices: back where the list was opened, and the change is said there
                    if let Some(v) = self.came_from.pop() {
                        self.go_back(v);
                    }
                    if let Some(call) = row.tool {
                        self.pick_step(p, call, &row.text);
                    }
                    return;
                }
                if let Some(c) = row.children {
                    self.open_children(p, &c);
                    return;
                }
                // the folder's own row: its actions (dialog/DESIGN.md), Enter never silent
                if self.providers[p].label == "files" && crate::files::is_summary(&row) && self.files_actions(Some(row.clone())) {
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
                    self.prompt_arrive();
                    self.folder = None;
                    self.sel = 0;
                    let call = Call {
                        name: pk.tool,
                        arguments,
                        ask: vec![],
                        said: None,
                        pick: None,
                        value: None,
                        children: None,
                    };
                    self.pick_step(pk.prov, call, &row.text);
                    return;
                }
                let call = if self.attaching.is_some() {
                    row.more.iter().find(|m| m.name.ends_with("_attach")).cloned()
                } else {
                    row.tool.clone()
                };
                if let Some(call) = call {
                    self.pick_step(p, call, &row.text);
                } else if !row.more.is_empty() {
                    // a row that is only its actions (this folder, #127): Enter opens them, as Right does
                    if !self.files_actions(Some(row.clone())) {
                        self.steps_of(p, row);
                    }
                }
            }
            _ => {}
        }
    }

    /// A row's children: a provider's own rows (its section), or one of its folders.
    pub(crate) fn open_children(&mut self, from: usize, uri: &str) {
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
        }
    }

    pub(crate) fn read_folder(&mut self, p: usize, uri: &str) {
        self.folder = None;
        self.refresh_folder(p, uri);
    }

    /// The folder read again while its rows stay on screen: the answer replaces them, landing in the active pane.
    pub(crate) fn refresh_folder(&mut self, p: usize, uri: &str) {
        if let Some(id) = self
            .server(p)
            .and_then(|s| s.request("resources/read", json!({"uri": uri}), Kind::Folder, mcp::T_READ))
        {
            self.files.folder_reads.push((p, id, crate::files::Landing::Active(uri.to_string())));
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
    pub(crate) fn files(&self) -> Option<usize> {
        self.providers.iter().position(|p| p.label == "files" && p.dead.is_none())
    }

    /// The footer's controls and the attachment's Remove: 0 attach, 1 the model, 3 the mic, 4 remove
    /// the file attached. How talk works is a setting (Settings > Talk), not a control.
    pub fn chip(&mut self, c: usize) {
        self.chip_focus = None;
        match c {
            5 => self.ask(),
            6 => self.conversation(),
            4 => {
                self.attachment = None;
            }
            0 if self.cfg.plus => {
                self.reply = None; // a new action: what the status row said about the last one is gone
                let Some(f) = self.files() else {
                    return self.refuse("nothing to attach from: the files section is not here");
                };
                let Some(root) = self.providers[f].rows.rows.iter().find_map(|r| r.children.clone()) else {
                    return self.refuse("no folder to attach from");
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
                    // a new try clears the last one's refusal (nothing heard) from the status row
                    self.reply = None;
                    self.listen_cancelled = false;
                    self.mode = Mode::Listening;
                    self.jobs.push(Job::Run(
                        Helper::Listen,
                        vec![self.cfg.spark.clone(), "voice".into(), "listen".into(), "--buffer".into()],
                    ));
                }
            }
            // a control that cannot act says why, on the status row: Enter or a click is never silent (v0.124.4)
            3 if self.cfg.talk => self.refuse(if self.voice_on {
                "talk is off: the talk page turns it on"
            } else {
                "spark's voice is off: spark voice clear turns it on"
            }),
            _ => {}
        }
    }

    /// The wheel: a row at a time in a list, as the arrows move the bar; three lines in text, and in a page of
    /// Apps that scrolls (dialog/DESIGN.md).
    pub fn wheel(&mut self, d: i32) {
        let step = |s: usize| if d < 0 { s.saturating_sub(3) } else { s + 3 };
        if self.view == View::Apps && matches!(self.apps.page, crate::apps::Page::Details(_) | crate::apps::Page::Technical(_)) {
            self.scroll = step(crate::ui::body_scroll(self));
            self.in_list = false;
            self.list_keys = false;
            return;
        }
        if self.picks().is_empty() || self.preview_key() {
            self.scroll = step(self.scroll);
            return;
        }
        if d < 0 {
            self.up();
        } else {
            self.down();
        }
    }

    /// The controls Tab moves through, in their order on the screen: the footer's, which have no key. A key
    /// chip is a helper, never a stop.
    pub fn chips(&self) -> Vec<usize> {
        let mut v = vec![];
        if self.cfg.plus && self.files().is_some() {
            v.push(0);
        }
        if self.attachment.is_some() {
            v.push(4);
        }
        if self.cfg.model {
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
        if self.launch_wait.take().is_some_and(|until| Instant::now() < until) {
            self.stow = true;
        }
        if self.mode == Mode::Listening {
            self.listen_cancelled = true;
            self.jobs.push(Job::StopListening);
        }
    }

    // ---- the want and the steps

    /// Enter resolves places and native commands locally. An unmatched draft stays
    /// available for editing or an explicit Ask.
    fn request(&mut self, words: &str) {
        if self.running.is_some() {
            self.set_input(words.into());
            return self.reply(Mark::Note, "wait for the current action's result");
        }
        let visible = self.shown();
        let first = words.split_whitespace().next().unwrap_or("");
        let loading = self.providers.iter().enumerate().any(|(idx, provider)| {
            provider.dead.is_none()
                && (visible.contains(&idx) || provider.label.eq_ignore_ascii_case(first))
                && ((!provider.ready && provider.reading) || self.servers.iter().any(|s| s.idx == idx && s.pending.values().any(|p| p.kind == Kind::Tools)))
        });
        if loading {
            self.set_input(words.into());
            return self.reply(Mark::Note, "the controls are still loading; press Enter when they appear");
        }
        self.remember_prompt(words);
        // undo of a batch of files: every step back, as one (dialog/DESIGN.md)
        if words.trim().eq_ignore_ascii_case("undo") && self.files_undo_batch() {
            self.set_input(String::new());
            return;
        }
        // undo with no provider step at hand: the last change of Apps, whose receipt Esc may have cleared
        if words.trim().eq_ignore_ascii_case("undo") && self.undo.is_none() && self.apps.undo.is_some() {
            self.set_input(String::new());
            return self.apps_undo();
        }
        if !words.contains('\n') {
            if let Some(v) = self.place(words) {
                if self.view != v {
                    self.go(v);
                }
                return;
            }
        }
        if let Some(steps) = self.commands(words) {
            self.queue.extend(steps.into_iter().map(|s| Step { typed: true, ..s }));
            return self.next_step();
        }
        self.set_input(words.to_string());
        // no row, no place, no command by these words: they are a request, and Enter asks (dialog/DESIGN.md), or
        // the status row says why it cannot
        if self.cfg.model && self.model_on && self.model_name.is_some() {
            return self.ask();
        }
        if self.cfg.model && !self.model_on {
            return self.reply(Mark::Note, "no row by these words, and the model is off: the model control turns it on");
        }
        self.reply(Mark::Note, "no row by these words, and no model to ask");
    }

    /// Explicit model request. Forms, confirmation text and previews grant no context authority.
    pub fn ask(&mut self) {
        if self.view == View::Apps && self.apps.form() {
            return self.refuse("finish the category edit first: Enter saves it, Esc lets it go");
        }
        if self.mode != Mode::Normal {
            return;
        }
        if self.staged_now() {
            // the box holds the commands spark planned: Enter runs them, Esc drops them; asking waits for that
            return self.reply(Mark::Note, "Enter runs the planned commands, Esc drops them");
        }
        if !self.request_prompt() {
            self.conversation();
            return self.reply(Mark::Note, "write a request here: the words typed in the list stay");
        }
        if self.pending.is_some() || self.running.is_some() || self.wait.is_some() {
            return self.reply(Mark::Note, "wait for the current request");
        }
        let words = self.input.trim().to_string();
        if words.is_empty() {
            return;
        }
        if self.model_name.is_none() {
            return self.refuse("no model is available: the draft stays, and the rows still work");
        }
        if !self.model_on {
            return self.refuse("the model is off: the model control turns it on");
        }
        self.reply = None;
        self.remember_prompt(&words);
        self.set_input(String::new());
        self.in_list = false;
        self.want(&words);
        if self.pending.is_some() && self.view != View::Conversation {
            self.go(View::Conversation);
        }
        self.scroll = 0;
    }

    pub fn conversation(&mut self) {
        if self.mode != Mode::Normal {
            return;
        }
        if self.view == View::Conversation {
            if let Some(v) = self.came_from.pop() {
                self.go_back(v);
            } else {
                self.view = View::Home;
            }
        } else {
            self.go(View::Conversation);
        }
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
                    said: None,
                    pick: None,
                    value: None,
                    children: None,
                };
                best = Some((
                    own,
                    Step {
                        prov: p,
                        call,
                        who: Who::Person,
                        line: words.join(" "),
                        typed: true,
                    },
                ));
            }
        }
        best.map(|(_, s)| s)
    }

    fn want(&mut self, words: &str) {
        if self.cfg.spark.is_empty() && self.cfg.spark_shell.is_empty() {
            self.set_input(words.to_string());
            return self.refuse("no spark to read the words");
        }
        self.want_cancel();
        self.wait = Some(Work::Think);
        // Only an explicit attachment is sent. Inspecting a file stays local.
        let file = self.attachment.take();
        self.pending = Some((words.to_string(), file.clone()));
        let serial = self.want_serial;
        if file.is_some() || self.cfg.spark.is_empty() {
            // a file goes the terminal's way: spark-shell want reads it with the words
            let mut argv = vec![self.cfg.spark_shell.clone(), "want".into(), "--json".into()];
            if let Some(a) = &file {
                argv.push("--attach".into());
                argv.push(a.clone());
            }
            argv.push("--".into());
            argv.push(words.to_string());
            self.jobs.push(Job::Run(Helper::Want(serial), argv));
            return;
        }
        // the one bounded call: these words, this tool list, which steps. The
        // list is every ready provider's tools, in provider order, the same
        // bytes from one request to the next, so spark's served prompt keeps
        // it cached and a request pays its own words.
        let tools: Vec<Value> = self
            .providers
            .iter()
            .filter(|p| p.ready && p.dead.is_none())
            .flat_map(|p| {
                p.tools
                    .iter()
                    .map(|t| json!({"name": t.name, "title": t.title, "description": t.description, "inputSchema": t.schema}))
            })
            .collect();
        let payload = json!({"tools": tools}).to_string();
        let argv = vec![
            self.cfg.spark.clone(),
            "steps".into(),
            "--about".into(),
            self.want_about(),
            "--".into(),
            words.to_string(),
        ];
        self.jobs.push(Job::RunInput(Helper::Want(serial), argv, payload));
    }

    /// Browsing state is not implicit model context.
    fn want_about(&self) -> String {
        "Home: optional assistance. Only the explicit draft and attachment are authorized context. Propose steps for review; do not execute them.".into()
    }

    /// A step from spark that names a row by a near miss ("everforest light" for everforest-light,
    /// "hail mary" for a note's whole title) takes the row's own value when one row alone fits: the
    /// same letters and digits, else the one name that starts with the words, else the one name that
    /// holds every word. An exact name, an enum, or no one fit changes nothing: the gate decides then,
    /// and the proposal still waits for Enter (#95).
    fn nearest_name(&self, p: usize, call: &mut Call) {
        let Some(tool) = self.providers[p].tools.iter().find(|t| t.name == call.name) else {
            return;
        };
        let rows = self.rows_for_gate(p);
        for k in gate::name_keys(&tool.schema) {
            let Some(typed) = call.arguments.get(&k).and_then(Value::as_str).map(str::to_string) else {
                continue;
            };
            let mut names: Vec<String> = vec![];
            for r in &rows.rows {
                for c in r.calls() {
                    if c.name == call.name {
                        if let Some(v) = c.arguments.get(&k).and_then(Value::as_str) {
                            if !names.iter().any(|n| n == v) {
                                names.push(v.to_string());
                            }
                        }
                    }
                }
            }
            let names: Vec<&str> = names.iter().map(String::as_str).collect();
            if names.contains(&typed.as_str()) {
                continue;
            }
            let slug = |s: &str| {
                s.to_lowercase()
                    .chars()
                    .map(|c| if c.is_alphanumeric() { c } else { ' ' })
                    .collect::<String>()
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
            };
            let t = slug(&typed);
            if t.is_empty() {
                continue;
            }
            let same: Vec<&str> = names.iter().copied().filter(|n| slug(n) == t).collect();
            let starts: Vec<&str> = names.iter().copied().filter(|n| slug(n).starts_with(&t)).collect();
            let holds: Vec<&str> = names
                .iter()
                .copied()
                .filter(|n| {
                    let s = slug(n);
                    t.split(' ').all(|w| s.split(' ').any(|x| x == w))
                })
                .collect();
            let pick = match (same.as_slice(), starts.as_slice(), holds.as_slice()) {
                ([one], _, _) => Some(*one),
                ([], [one], _) => Some(*one),
                ([], [], [one]) => Some(*one),
                _ => None,
            };
            if let Some(n) = pick {
                call.arguments.insert(k.clone(), Value::String(n.to_string()));
            }
        }
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

    /// Model proposals are gated and staged for review, even when their text
    /// matches the original request. Full answers remain in the conversation.
    pub fn plan(&mut self, text: &str) {
        self.wait = None;
        let words = self.pending.as_ref().map(|(w, _)| w.clone()).unwrap_or_default();
        let Ok(v) = serde_json::from_str::<Value>(text) else {
            self.give_back();
            return self.refuse("spark answered with nothing to run");
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
            let said = s.get("line").and_then(Value::as_str).map(scrub);
            let line = said.clone().unwrap_or_else(|| name.to_string());
            // two steps are the dialog's own: undo is the undo at hand, about opens its about
            if name == "undo_all" {
                match self.undo.clone() {
                    Some(u) => steps.push(Step { line: "undo".into(), ..u }),
                    None => no.push("nothing to undo".into()),
                }
                continue;
            }
            if name == "about_open" {
                // the about waits in the box as the word about, as every step does: nothing opens before Enter (the review's F)
                match self.about_idx {
                    Some(p) => steps.push(Step {
                        prov: p,
                        call: Call {
                            name: name.to_string(),
                            arguments: Map::new(),
                            ask: vec![],
                            said: None,
                            pick: None,
                            value: None,
                            children: None,
                        },
                        who: Who::Model,
                        line: "about".into(),
                        typed: true,
                    }),
                    None => no.push(format!("{} is not offered here now", line)),
                }
                continue;
            }
            let mut call = Call {
                name: name.to_string(),
                arguments,
                ask: vec![],
                said: None,
                pick: None,
                value: None,
                children: None,
            };
            let at = self.providers.iter().position(|p| p.tools.iter().any(|t| t.name == name));
            if let Some(p) = at {
                self.nearest_name(p, &mut call);
            }
            match at {
                None => no.push(format!("{} is not offered here now", line)),
                Some(p) => match gate::step(&self.providers[p].tools, self.rows_for_gate(p), &call) {
                    Ok(()) => {
                        // spark steps sends no line: the step reads as the tool's title with the
                        // values in its capitals' places, or every field when it has more
                        let line = said.unwrap_or_else(|| self.proposal_line(p, &call));
                        steps.push(Step {
                            prov: p,
                            call,
                            who: Who::Model,
                            line,
                            typed: true,
                        })
                    }
                    Err(e) => no.push(format!("{} did not run: {}", said.unwrap_or_else(|| self.proposal_line(p, &call)), e)),
                },
            }
        }
        // The answer's summary makes its arrival visible in another view.
        // Conversation shows the complete text, preserving its paragraphs.
        if !no.is_empty() {
            self.refuse(&no.join("; "));
        } else if !answer.is_empty() {
            self.reply(Mark::Answer, &answer);
        }
        if !words.is_empty() {
            self.say(Sign::You, &words);
        }
        if !answer.is_empty() {
            self.say(Sign::Says, &answer);
        }
        if !no.is_empty() {
            self.say(Sign::Refused, &no.join("\n"));
        }
        if !steps.is_empty() {
            self.say(
                Sign::Says,
                &format!(
                    "Proposed steps (review before running):\n{}",
                    steps.iter().map(|s| s.line.as_str()).collect::<Vec<_>>().join("\n")
                ),
            );
        }
        if steps.is_empty() {
            if answer.is_empty() {
                if no.is_empty() {
                    self.refuse("spark found nothing to do for that");
                }
                return self.give_back(); // the words come back to be said again
            }
            self.pending = None;
            return;
        }
        self.pending = None;
        let lines: Vec<String> = steps.iter().map(|s| s.line.clone()).collect();
        let text = lines.join("\n");
        if self.mode != Mode::Normal {
            // the prompt is asking (a yes, a name, a code): the commands wait where the draft waits, and come
            // to the box when the question is answered or let go (#196)
            let draft = self.stash.replace(text.clone()).unwrap_or_default();
            self.staged = Some(Staged { text, steps, draft });
            return;
        }
        let draft = std::mem::take(&mut self.input);
        self.set_input(text.clone());
        self.in_list = false;
        self.sel = 0;
        // the box is two rows: the reply row names every command waiting in it, unless it says what was refused
        if self.reply.as_ref().is_none_or(|r| r.mark != Mark::Refused) {
            self.reply(Mark::Note, &format!("run: {}", lines.join("; ")));
        }
        self.staged = Some(Staged { text, steps, draft });
    }

    pub(crate) fn next_step(&mut self) {
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
        let why = self
            .reply
            .as_ref()
            .filter(|r| r.mark == Mark::Refused)
            .map(|r| format!("{}; ", r.text))
            .unwrap_or_default();
        self.refuse(&format!("{}so these did not run: {}", why, left.join(", ")));
    }

    /// A row picked (a click, Enter, a preview's Enter, a step from a row's list): its step, run as every
    /// step is and silent unless refused (#196).
    pub(crate) fn pick_step(&mut self, prov: usize, call: Call, row_text: &str) {
        let line = self.step_line(prov, &call, row_text);
        self.run(Step {
            prov,
            call,
            who: Who::Person,
            line,
            typed: false,
        });
    }

    /// Whether a step waits for the typed yes: the provider's destructive hint, or this machine's own
    /// list. The hint alone never makes a step safe.
    pub fn risky(&self, tool: &Tool) -> bool {
        tool.destructive || LOCAL_RISK.contains(&tool.name.as_str())
    }

    /// A step: an argument asked when it lacks one; a typed yes when it is risky, then the call. Nothing is
    /// drawn for it: a refusal lands in the reply row, a typed step's receipt too (#196).
    pub fn run(&mut self, step: Step) {
        if self.running.is_some() {
            return self.reply(Mark::Note, "wait for the current action's result");
        }
        self.reply = None;
        if step.who != Who::Model {
            self.want_cancel();
            self.target = None;
        }
        if let Some(field) = step.call.ask.first().cloned() {
            // files' rename, new folder and new text file: a form typed in the prompt (dialog/DESIGN.md)
            if self.files_form(step.clone()) {
                return;
            }
            let masked = gate::secret(&field, self.tool_of(&step).and_then(|t| t.schema.pointer(&format!("/properties/{}", field))));
            self.stash_draft();
            self.mode = Mode::Ask { step, field, masked };
            return;
        }
        if let Some(field) = step.call.pick.clone().filter(|f| !step.call.arguments.contains_key(f)) {
            // a folder picked in the files for the step's argument (a move's to): the list stays where it
            // is with a row that lands the step here, and only folders open; Esc cancels (#112)
            let Some(f) = self.files() else {
                return self.refuse("no files to pick a folder from");
            };
            let name = step
                .call
                .arguments
                .get("path")
                .and_then(Value::as_str)
                .and_then(|p| p.rsplit('/').next())
                .unwrap_or("it")
                .to_string();
            let what = format!("{} {} here", verb_of(&step.call.name).to_lowercase(), name);
            if !matches!(&self.view, View::Folder(p, _) if *p == f) {
                let Some(root) = self.files_root(f) else {
                    return self.refuse("no folder to pick from");
                };
                self.go(View::Folder(f, root.clone()));
            } else {
                self.came_from.push(self.view.clone());
            }
            self.picking = Some(Picking {
                back: self.view.clone(),
                depth: self.came_from.len(),
                prov: step.prov,
                tool: step.call.name.clone(),
                types: vec![],
                step: Some(step),
                field,
                what,
            });
            self.in_list = true;
            self.sel = 0;
            return;
        }
        if step.call.name == "about_open" {
            return self.go(View::About); // the about is the dialog's own page, no provider's step
        }
        if step.who == Who::Undo {
            self.undo = None; // the undo at hand is taken, wherever it came from (its row, "undo", spark)
        }
        let Some(tool) = self.tool_of(&step).cloned() else {
            return self.step_refused_early(&step, "this is not offered here now");
        };
        if let Err(e) = self.checked(&step) {
            return self.step_refused_early(&step, &e);
        }
        if self.risky(&tool) {
            self.stash_draft();
            self.mode = Mode::Confirm(step);
            // the question's page, the verb's row lit: Enter again is the yes
            self.in_list = true;
            self.sel = 0;
            self.reply = None;
            return;
        }
        self.call(step);
    }

    /// What every step passes, now and again at its yes: its tool is still offered, only explicit
    /// text/plain fields can hold text whitespace, and a step the model or the
    /// undo planned names only what the rows list now.
    fn checked(&self, step: &Step) -> Result<(), String> {
        if step.who == Who::Model && self.target.is_some() && self.target_row().is_none() {
            return Err("the selected item is no longer available; select it again".into());
        }
        let Some(tool) = self.tool_of(step) else {
            return Err("this is not offered here now".into());
        };
        if step.call.arguments.iter().any(|(key, v)| {
            let prop = tool.schema.get("properties").and_then(|p| p.get(key)).unwrap_or(&Value::Null);
            v.as_str().is_some_and(|text| !gate::text_controls_ok(prop, text))
        }) {
            return Err("an argument holds a control character".into());
        }
        match step.who {
            Who::Model => gate::step(&self.providers[step.prov].tools, self.rows_for_gate(step.prov), &step.call)?,
            // an undo names what its own result gave back (a file moved into another folder, a palette
            // not on the list): the schema holds, and the provider's own lines hold again when it runs
            Who::Undo => gate::schema_ok(&tool.schema, &step.call.arguments)?,
            Who::Person => {}
        }
        Ok(())
    }

    /// The yes was typed for this step, these arguments: checked again against what is offered now,
    /// for the rows may have changed while the question waited.
    fn approved(&mut self, step: Step) {
        match self.checked(&step) {
            Ok(()) => self.call(step),
            Err(e) => {
                self.refuse(&format!("not done: {}", e));
                self.stop_queue();
            }
        }
    }

    fn tool_of(&self, step: &Step) -> Option<&Tool> {
        self.providers.get(step.prov)?.tools.iter().find(|t| t.name == step.call.name)
    }

    fn call(&mut self, step: Step) {
        if self.running.is_some() {
            return self.reply(Mark::Note, "wait for the current action's result");
        }
        // a step that puts a window in front: the dialog steps aside at once, and closes when it is done (#196)
        let opens = self.tool_of(&step).is_some_and(|t| t.opens);
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
                self.files_step_sent(&step.call);
                self.running = Some((idx, id, step));
                self.hidden = opens;
            }
            None => self.step_refused_early(&step, "not done: the part of the desktop that does it stopped"),
        }
    }

    /// A step refused before it was sent: said, and the steps after it not run; a batch's step is counted as
    /// refused and the batch goes on.
    fn step_refused_early(&mut self, step: &Step, why: &str) {
        if self.files_batch_owns(&step.call) {
            self.files_step_done(step, Err(why.to_string()));
            return self.next_step();
        }
        self.refuse(why);
        self.stop_queue();
    }

    fn called(&mut self, idx: usize, n: u64, result: Option<Value>, error: Option<String>) {
        match &self.running {
            Some((p, id, _)) if *p == idx && *id == n => {}
            _ => return,
        }
        let Some((_, _, step)) = self.running.take() else { return };
        let task_result = result
            .clone()
            .unwrap_or_else(|| json!({"isError": true, "message": error.clone().unwrap_or_else(|| "no result".into())}));
        let mut output_error = if error.is_some() {
            Some("the provider could not report the result; the action may have happened".to_string())
        } else if !result.as_ref().is_some_and(mcp::tool_result_ok) {
            Some("the provider returned an invalid tool result; the action may have happened".to_string())
        } else {
            None
        };
        let privacy = result
            .as_ref()
            .filter(|_| output_error.is_none())
            .map(|r| {
                let mut privacy = gate::result_privacy(None, r);
                if let Some(schema) = self.tool_of(&step).and_then(|t| t.output_schema.as_ref()) {
                    privacy.extend(gate::result_privacy(Some(schema), &r["structuredContent"]));
                }
                if let Some(undo) = r.pointer("/structuredContent/undo") {
                    if let Some(tool) = self.providers[idx].tools.iter().find(|t| Some(t.name.as_str()) == undo["name"].as_str()) {
                        privacy.extend(gate::result_privacy(Some(&tool.schema), &undo["arguments"]));
                    }
                }
                privacy
            })
            .unwrap_or_default();
        if output_error.is_none() && result.as_ref().is_some_and(|r| r.get("isError") != Some(&Value::Bool(true))) {
            if let Some(output) = self.tool_of(&step).and_then(|t| t.output_schema.as_ref()) {
                output_error = gate::result_ok(output, &task_result["structuredContent"]).err();
            }
        }
        let schema = self.tool_of(&step).map(|t| t.schema.clone()).unwrap_or(Value::Null);
        let refused = output_error.is_some() || error.is_some() || result.as_ref().and_then(|r| r.get("isError")).and_then(Value::as_bool).unwrap_or(false);
        crate::audit::record(
            step.who.word(),
            &self.providers[idx].label,
            &step.call.name,
            &schema,
            &step.call.arguments,
            refused,
        );
        // a batch's step: its refusal is counted, never the queue's to stop; its receipt is the batch's one (dialog/DESIGN.md)
        let batch_step = self.files_batch_owns(&step.call);
        let mut outcome: Result<(), String> = Ok(());
        let mut fresh = false;
        if let Some(e) = output_error {
            self.opened = false;
            self.hidden = false;
            outcome = Err(e);
        } else if let Some(r) = result {
            let text = r.pointer("/content/0/text").and_then(Value::as_str).unwrap_or("");
            if refused {
                self.hidden = false;
                outcome = Err(if text.is_empty() || !privacy.text_safe(text) {
                    "the action did not complete".to_string()
                } else {
                    text.to_string()
                });
            } else {
                let sc = r.get("structuredContent").cloned().unwrap_or(Value::Null);
                fresh = self.take_rows(idx, &sc);
                if let Some(path) = sc.get("attach").and_then(Value::as_str) {
                    let under = home().map(|h| path.starts_with(&format!("{}/", h))).unwrap_or(false);
                    if privacy.text_safe(path) && under && !path.split('/').any(|c| c == ".." || c.starts_with('.')) {
                        self.attachment = Some(path.to_string());
                        if let Some((v, depth)) = self.attaching.take() {
                            self.came_from.truncate(depth);
                            self.view = v;
                            self.prompt_arrive();
                            self.folder = None;
                            self.sel = 0;
                            if let View::Folder(p, uri) = self.view.clone() {
                                self.read_folder(p, &uri);
                            }
                        }
                    } else {
                        self.refuse("that file is not under your home: not attached");
                    }
                }
                // a list of the provider's own to open (a search's rows): opened as a row's children are
                if let Some(u) = sc.get("open").and_then(Value::as_str) {
                    if u.starts_with(&format!("spark-shell://{}/rows/", self.providers[idx].label)) && privacy.text_safe(u) && !u.chars().any(char::is_control)
                    {
                        self.open_children(idx, u);
                    }
                }
                // the theme section's own palette, never another provider's
                if self.providers[idx].label == "theme" {
                    if let Some(p) = sc.get("palette").and_then(Value::as_object) {
                        if p.values().all(|v| v.as_str().is_some_and(|s| privacy.text_safe(s))) {
                            self.palette = Some(p.clone());
                        }
                    }
                    // and its animation now: read again at once, so the next wait and the close are the new look's (#126)
                    if let Some(t) = sc.get("transitions").and_then(Value::as_str) {
                        let whole = t.starts_with('/') && !t.split('/').any(|c| c == "..") && !t.chars().any(char::is_control);
                        if t.is_empty() || whole {
                            let want = (!t.is_empty()).then(|| t.to_string());
                            if want != self.cfg.transitions {
                                self.cfg.transitions = want.clone();
                                self.films_want = Some(want);
                            }
                        }
                    }
                }
                // a window put in front closes the dialog when the steps are done; anything else shows it again
                if sc.get("opened").and_then(Value::as_bool) == Some(true) {
                    self.opened = true;
                } else {
                    self.hidden = false;
                }
                // the receipt, every line of it, for typed words alone: a click's row shows what it did (#196)
                // the workspace place says each change on the status row, as apps does (dialog/DESIGN.md)
                let says = step.typed || WORKSPACE_SAYS.contains(&step.call.name.as_str());
                if says && !self.opened {
                    let receipt = sc.get("receipt").and_then(Value::as_str).unwrap_or(text).to_string();
                    if privacy.text_safe(&receipt) {
                        self.reply(Mark::Done, &receipt);
                    } else {
                        self.reply(Mark::Done, "the action completed; private details withheld");
                    }
                }
                self.undo = None;
                self.files.undo_more.clear(); // a batch's undo past this step goes with the undo it followed
                if let Some(u) = sc.get("undo") {
                    if let (Some(name), Some(args)) = (u.get("name").and_then(Value::as_str), u.get("arguments").and_then(Value::as_object)) {
                        let call = Call {
                            name: name.to_string(),
                            arguments: args.clone(),
                            ask: vec![],
                            said: None,
                            pick: None,
                            value: None,
                            children: None,
                        };
                        let undo_schema = self.providers[idx].tools.iter().find(|t| t.name == name).map(|t| &t.schema);
                        let carries_secret = args.iter().any(|(k, v)| {
                            gate::secret(k, undo_schema.and_then(|s| s.get("properties")).and_then(|p| p.get(k)))
                                || !privacy.text_safe(v.as_str().unwrap_or(&v.to_string()))
                        });
                        if !carries_secret {
                            let line = format!("undo {}", step.line);
                            self.undo = Some(Step {
                                prov: idx,
                                call,
                                who: Who::Undo,
                                line,
                                typed: false,
                            });
                            // Undo at the end of the reply row: after the receipt, or alone for a click
                            match self.reply.as_mut() {
                                Some(r) if r.mark == Mark::Done => r.undo = true,
                                _ => self.reply = Some(Reply::undo_only()),
                            }
                        }
                    }
                }
            }
        }
        if let Err(e) = &outcome {
            if !batch_step {
                self.refuse(e);
                self.stop_queue();
            }
        }
        if !fresh {
            self.providers[idx].dirty = true;
        }
        if batch_step {
            self.files_step_done(&step, outcome);
        }
        self.next_step();
    }

    /// The rows a call's answer carries, as the step left them (#196): taken as a read's are, and nothing is read
    /// again. False when the answer carries none.
    fn take_rows(&mut self, idx: usize, sc: &Value) -> bool {
        let Some(text) = sc.get("rows").filter(|r| r.is_object()).map(Value::to_string) else {
            return false;
        };
        let Some(rows) = model::rows(&text).filter(|_| text.len() <= mcp::RESOURCE_MAX) else {
            return false;
        };
        if let Some(st) = &rows.state {
            self.providers[idx].title = st.clone();
        }
        self.providers[idx].rows = rows;
        self.providers[idx].dirty = false;
        self.providers[idx].last_read = Some(Instant::now());
        self.hold_rows(idx);
        // a list of the provider's own on screen (the wallpapers) is read again: the answer is the section's rows
        self.refresh_panes(idx);
        true
    }

    /// Home keeps its reading measure; wider views can use more of the grid.
    pub fn col_w(&self) -> u16 {
        crate::ui::frame_width(self.size.0, self)
    }

    /// A click lights row `n`: a choice, as a key's is, so the light kept from a preview lets go (#153).
    pub fn light(&mut self, n: usize) {
        self.in_list = true;
        self.sel = n;
        self.keep_lit = None;
        self.list_keys = true;
    }

    /// A click on row `n` (dialog/DESIGN.md): a menu's row acts at once; an object's row is selected by the first
    /// click and acts on a second within DOUBLE_CLICK, as a file does on every desktop.
    pub fn clicked(&mut self, n: usize, now: Instant) {
        let again = self
            .last_click
            .is_some_and(|(k, at)| k == n && now.saturating_duration_since(at) < DOUBLE_CLICK);
        self.light(n);
        if again || !self.object_pick(n) {
            self.last_click = None;
            self.enter();
        } else {
            self.last_click = Some((n, now));
        }
    }

    /// A click on a category's heading in the list of apps (dialog/DESIGN.md, v0.124.4): the list narrows to that
    /// category; on the heading of the category shown alone, it widens to all. `label` is the heading as drawn.
    pub fn apps_heading(&mut self, label: &str) {
        if self.view == View::Dest(WORKSPACE_DEST) {
            return self.workspace_heading(label);
        }
        if self.view != View::Apps || self.apps.page != crate::apps::Page::List || self.mode != Mode::Normal {
            return;
        }
        let Some(c) = self.apps.prefs.categories.iter().find(|c| c.to_lowercase() == label).cloned() else {
            return;
        };
        let next = if self.apps.filter.as_deref() == Some(c.as_str()) { None } else { Some(c) };
        self.reply = None;
        self.apps_activate(crate::apps::Action::SetFilter(next));
    }

    /// Whether pick `n` is an object, selected before it is acted on: an app in the list, a file, a folder, a
    /// note, a window, a layout. A place, a setting, a choice, an action of a details page is a menu's row.
    pub fn object_pick(&self, n: usize) -> bool {
        let Some(it) = self.picks().get(n).cloned() else { return false };
        match &it {
            // an app's own row is the object; the managing rows at the list's end are a menu's and act on one
            // click (dialog/DESIGN.md, v0.124.4)
            Item::Apps(line) => {
                matches!(self.apps.page, crate::apps::Page::List | crate::apps::Page::Hidden) && matches!(line.action, Some(crate::apps::Action::Launch(_)))
            }
            // a window's row and a layout's are the objects of the workspace place; capture, arrange and save are a
            // menu's and act on one click (dialog/DESIGN.md)
            Item::Folder(_) | Item::Row(..) | Item::Hit(_) => self.prov_of(&it).is_some_and(|p| match self.providers[p].label.as_str() {
                "files" | "notes" => true,
                "window" | "layout" => self
                    .row_ref(&it)
                    .and_then(|r| r.tool.as_ref())
                    .is_some_and(|t| matches!(t.name.as_str(), "window_focus" | "layout_open")),
                _ => false,
            }),
            _ => false,
        }
    }

    /// The selected object's line for the status row (dialog/DESIGN.md): what the narrow columns cut, while
    /// nothing is said there. An app: its name, what it is, its category, its launch choice. A file or a row: its
    /// name and its wide columns.
    pub fn selected_line(&self) -> Option<String> {
        // checks standing: their count and size, in place of the lit row's line (dialog/DESIGN.md)
        if let Some(line) = self.files_checked_line() {
            return Some(line);
        }
        if !self.in_list || self.mode != Mode::Normal {
            return None;
        }
        let it = self.picks().get(self.sel)?.clone();
        match &it {
            Item::Apps(line) => {
                let Some(crate::apps::Action::Launch(id)) = &line.action else { return None };
                let a = self.apps.entry(id)?;
                let about = if a.description.is_empty() { &a.generic_name } else { &a.description };
                let mut parts = vec![a.name.to_lowercase()];
                if !about.is_empty() {
                    parts.push(about.trim_end_matches('.').to_lowercase());
                }
                parts.push(self.apps.category_of(a).to_lowercase());
                // the launch choice only where it is one: the default says nothing
                let mode = self.apps.preference(id).mode().to_string();
                if mode != "default" {
                    parts.push(crate::apps::launch_name(&mode).to_string());
                }
                Some(parts.join(crate::ui::SEP))
            }
            Item::Folder(_) | Item::Row(..) | Item::Hit(_) if self.object_pick(self.sel) => {
                let r = self.row_ref(&it)?;
                if let Some(line) = &r.line {
                    return Some(line.clone());
                }
                let cols = r.wide.as_ref().unwrap_or(&r.columns);
                let mut parts = vec![r.text.clone()];
                if r.id.starts_with("files:") {
                    // a file: name, kind, size, the date with its time, then the place: the row's own folder where it
                    // carries one (a recent file, a file found), else the folder on screen (dialog/DESIGN.md)
                    let before_place = if r.wide.is_some() { 3 } else { 2 };
                    parts.extend(cols.iter().take(before_place).filter(|c| !c.is_empty()).cloned());
                    parts.extend(self.files_place(&it, r));
                } else {
                    parts.extend(cols.iter().filter(|c| !c.is_empty()).cloned());
                }
                Some(parts.join(crate::ui::SEP))
            }
            // help's row: what you do and its key, whole, where the row cut the words (dialog/DESIGN.md, v0.127)
            Item::Key(words, key) => Some(format!("{}{}{}", words, crate::ui::SEP, key)),
            // a menu's row with a wide column (power: what the step does): the row stays one word, its line
            // here while it is lit (dialog/DESIGN.md, v0.127)
            Item::Row(..) => {
                let r = self.row_ref(&it)?;
                let wide = r.wide.as_ref()?;
                let mut parts = vec![r.text.clone()];
                parts.extend(wide.iter().filter(|c| !c.is_empty()).cloned());
                Some(parts.join(crate::ui::SEP))
            }
            _ => None,
        }
    }

    /// The undo at hand runs now (the status row's Undo): a provider's step, or Apps' preferences as they were.
    pub fn undo_now(&mut self) {
        self.reply = None;
        if self.files_undo_batch() {
            return;
        }
        if let Some(u) = self.undo.take() {
            self.run(u);
        } else if self.apps.undo.is_some() {
            self.apps_undo();
        }
    }

    /// A helper's answer: the plan, the model list, the model set, the words heard, the voice's state,
    /// where the model runs.
    pub fn helper(&mut self, h: Helper, out: Result<String, String>) {
        if let Helper::Apps(serial) = h {
            let value = out
                .and_then(|text| serde_json::from_str::<Value>(&text).map_err(|_| "Invalid native Apps response".into()))
                .unwrap_or_else(|error| json!({"error":error}));
            let launching = self.apps.pending.as_ref().is_some_and(|(s, op)| *s == serial && op == "launch");
            let opened = launching && value["confirmed"].as_bool() == Some(true);
            match self.apps.receive(serial, value) {
                Ok(Some(message)) => {
                    self.reply(Mark::Done, &message);
                    // The launched app has focus. Let it be seen and used, while
                    // home keeps its workflow and returns on the next Super+Space.
                    if opened && !self.window_focused {
                        self.stow = true;
                    } else if launching && !opened {
                        // a slow app, or one whose window has another name: its window takes the focus when it maps
                        self.launch_wait = Some(Instant::now() + LAUNCH_WAIT);
                    }
                }
                Err(error) => self.refuse(&error),
                Ok(None) => {}
            }
            if self.view == View::Apps && !self.in_list {
                self.follow_words();
            }
            return;
        }
        match h {
            Helper::Apps(_) => unreachable!(),
            Helper::Want(serial) if serial != self.want_serial => {} // an older request's reply: the newer one still thinks (the review's I)
            Helper::Want(_) => match out {
                Ok(t) => self.plan(&t),
                Err(e) => {
                    self.wait = None;
                    match serde_json::from_str::<Value>(&e) {
                        Ok(_) => self.plan(&e),
                        Err(_) => {
                            self.give_back();
                            self.refuse(&plain_words(e.lines().next(), "spark did not answer"))
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
                self.wait = None;
                match out {
                    Ok(_) => {
                        self.reply(Mark::Done, "model changed");
                        self.jobs.push(Job::Run(
                            Helper::Models,
                            vec![self.cfg.spark.clone(), "model".into(), "list".into(), "--porcelain".into()],
                        ));
                    }
                    Err(e) => self.refuse(&plain_words(e.lines().last(), "the model stays")),
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
                    Err(_) if cancelled => {}
                    Err(e) => self.refuse(&plain_words(e.lines().next(), "nothing heard")),
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
            View::Apps => "apps".into(),
            View::Home => "home".into(),
            View::Help => "help".into(),
            View::Conversation => "conversation".into(),
            View::Dest(d) => DESTS[*d].name.to_lowercase(),
            View::Section(p) | View::Folder(p, _) | View::Steps(p) if matches!(self.providers[*p].label.as_str(), "window" | "layout") => "workspace".into(),
            View::Section(p) | View::Folder(p, _) | View::Steps(p) => section_name(&self.providers[*p].label).to_lowercase(),
            View::About => "about".into(),
            View::Models => "model".into(),
            View::Talk => "talk".into(),
            View::Connections => "connections".into(),
            View::Preview => "preview".into(),
            View::Found(k, _) => k.name().into(),
        }
    }

    pub fn subtitle(&self) -> String {
        // the question's page says its verb in the header: `power . shutdown`
        if let Mode::Confirm(s) = &self.mode {
            return self.question_line(s);
        }
        match &self.view {
            View::Apps => {
                // the header says which page of apps this is (dialog/DESIGN.md, v0.124.4)
                use crate::apps::{Form, Page};
                match &self.apps.page {
                    // the list of every app says nothing after the name (dialog/DESIGN.md, v0.127); a category filter says which
                    Page::List => self.apps.filter.as_ref().map(|c| c.to_lowercase()).unwrap_or_default(),
                    Page::Hidden => "hidden".into(),
                    Page::Details(id) | Page::Technical(id) | Page::CategoryPicker(id) | Page::LaunchPicker(id) => {
                        self.apps.entry(id).map(|a| a.name.to_lowercase()).unwrap_or_default()
                    }
                    Page::Categories => "categories".into(),
                    Page::Category(c) => c.to_lowercase(),
                    Page::Mappings => "mappings".into(),
                    Page::Mapping(s) => s.clone(), // the desktop's own word, as it is spelled
                    Page::Form(Form::AddCategory) => "new category".into(),
                    Page::Form(Form::RenameCategory(_)) => "rename category".into(),
                    Page::Form(Form::AddMapping) => "add mapping".into(),
                }
            }
            View::Dest(d) if *d == WORKSPACE_DEST => {
                // a form says what it is for, a heading shown alone says which, else what the place holds now
                if let Mode::Ask { step, .. } = &self.mode {
                    match step.call.name.as_str() {
                        "layout_save" => return "save layout".into(),
                        "layout_rename" => return "rename layout".into(),
                        _ => {}
                    }
                }
                self.workspace_filter_words().unwrap_or_else(|| {
                    self.providers
                        .iter()
                        .find(|p| p.label == "window" && p.dead.is_none())
                        .map(|p| p.title.clone())
                        .unwrap_or_else(|| "no desktop".into())
                })
            }
            View::Section(p) => self.providers[*p].title.clone(),
            View::Folder(..) => {
                use crate::files::Page;
                match &self.files.page {
                    Page::Actions(a) if self.files_page_open() => a.title.clone(),
                    Page::Conflict(c) if self.files_page_open() => {
                        format!("{} is in {} already", c.current().map(|t| t.name.clone()).unwrap_or_default(), c.dest_title)
                    }
                    Page::Form(f) if self.files_page_open() => f.words.clone(),
                    _ => self.folder.as_ref().map(|(_, _, r)| r.title.clone()).unwrap_or_default(),
                }
            }
            View::Steps(_) => self.steps_row.as_ref().map(|r| r.text.clone()).unwrap_or_default(),
            View::Preview => self.preview.as_ref().map(|pv| pv.place.clone()).unwrap_or_default(),
            View::Found(_, words) => words.clone(),
            _ => String::new(),
        }
    }

    /// The row under the prompt: what a key does now, a key named as a chip and nothing else as one.
    /// A visible key chip follows the same action as that key on the keyboard.
    pub fn hint_key(&mut self, key: HintKey) {
        match key {
            HintKey::Enter => self.enter(),
            HintKey::Ask => self.ask(),
            HintKey::Conversation => self.conversation(),
            HintKey::PreviousControl => self.tab(true),
            HintKey::Start => self.line_start(),
            HintKey::End => self.line_end(),
            HintKey::PageUp => self.page(-1),
            HintKey::PageDown => self.page(1),
            HintKey::Backspace => self.backspace(),
            HintKey::Delete => self.delete(),
            // the way out, with a signal's 130 for the caller
            HintKey::Quit => self.quit = Some(130),
            HintKey::Escape => self.escape(),
            HintKey::Newline => self.newline(),
            HintKey::Tab => self.tab(false),
            HintKey::Left => self.left(),
            HintKey::Right => self.right(),
            HintKey::Up => self.up(),
            HintKey::Down => self.down(),
            HintKey::Char(c) => self.typed(c),
            HintKey::Check => self.check_key(),
            HintKey::Preview => self.preview_key_pressed(),
            HintKey::Pane => {
                self.files_pane();
            }
        }
    }

    pub fn hint(&self) -> Vec<(String, bool)> {
        self.hint_with(self.preview_pages)
    }

    /// The key row, a preview's text taking `pages` at the size it is drawn now (ui.rs draws the
    /// content first, so the row offers the pages of this frame, not the last one's).
    pub fn hint_with(&self, pages: usize) -> Vec<(String, bool)> {
        let mut v = self.hint_keys(pages);
        // one rule for every row of keys (#166): what Esc does comes first, in the same place on every view,
        // then Enter's, then what only some rows have; a row that starts with a sentence keeps its order
        if self.mode == Mode::Normal && !self.preview_key() && v.get(1).is_some_and(|(_, k)| *k) {
            if let Some(i) = v.iter().position(|(t, k)| *k && t == "Esc").filter(|i| *i >= 3) {
                let pair: Vec<(String, bool)> = v.drain(i - 2..=i).skip(1).collect();
                v.insert(0, ("   ".to_string(), false));
                for (n, p) in pair.into_iter().enumerate() {
                    v.insert(n, p);
                }
            }
        }
        v
    }

    fn hint_keys(&self, pages: usize) -> Vec<(String, bool)> {
        if self.view == View::Apps && self.mode == Mode::Normal && self.chip_focus.is_none() {
            return self.apps_hint();
        }
        if self.mode == Mode::Normal && self.chip_focus.is_none() && self.picking.is_none() && self.attaching.is_none() {
            if let Some(h) = self.files_hint() {
                return h;
            }
        }
        let key = |w: &str, k: &str| vec![(format!("{} ", w), false), (k.to_string(), true)];
        let gap = || ("   ".to_string(), false);
        let esc = |w: &str| vec![gap(), (format!("{} ", w), false), ("Esc".to_string(), true)];
        match &self.mode {
            // the question's page: Esc keeps; Enter has no chip, it acts on the lit row
            Mode::Confirm(_) => return vec![("keep ".to_string(), false), ("Esc".to_string(), true)],
            Mode::Ask { .. } if self.layout_form() => {
                // a form says what to type in the prompt's placeholder, and Enter saves (dialog/DESIGN.md)
                let mut v = key("Cancel", "Esc");
                v.push(gap());
                v.extend(key("Save", "Enter"));
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
            Mode::Pair { message, kind, .. } => {
                let suffix = if kind == "display" {
                    "waiting for the device"
                } else if kind == "confirm" {
                    "type yes or no"
                } else {
                    "code hidden"
                };
                let mut v = vec![(format!("{} ({})", message, suffix), false)];
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
        if self.pending.is_some() && !self.staged_now() {
            let mut v = vec![("Thinking".to_string(), false)];
            v.extend(esc("Discard"));
            return v;
        }
        if self.attaching.is_some() {
            let mut v = vec![(format!("Pick a file to attach ({})", self.cfg.attach.join(" ")), false)];
            v.extend(esc("Cancel"));
            return v;
        }
        if let Some(pk) = &self.picking {
            let mut v = if pk.step.is_some() {
                // a folder for a step: open folders, Enter on the first row lands it here
                let lit = self.in_list.then(|| self.picks().get(self.sel).cloned()).flatten();
                if lit == Some(Item::Here) {
                    key("Here", "Enter")
                } else {
                    // what the folder is for, from the row's words without their verb and their "here": notes.md, 2 files
                    let what = pk.what.strip_suffix(" here").unwrap_or(&pk.what);
                    let what = what.split_once(' ').map(|(_, w)| w).unwrap_or("it");
                    vec![(format!("A folder for {}", what), false)]
                }
            } else {
                vec![(format!("Pick a picture ({})", pk.types.join(" ")), false)]
            };
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
        if self.preview_key() {
            return self.preview_hint(pages);
        }
        // the key bar is the view's: what Esc does, then the keys any row of the view takes. Enter has no chip:
        // it opens what the bar is on, everywhere. The bar never changes for the row lit or the words typed, so
        // a label stands still under a moving pointer
        let back = if self.view == View::Dest(WORKSPACE_DEST) && self.ws_filter.is_some() {
            "All windows"
        } else if self.came_from.is_empty() {
            "Close"
        } else {
            "Back"
        };
        let mut v = vec![(format!("{} ", back), false), ("Esc".to_string(), true)];
        let add = |v: &mut Vec<(String, bool)>, w: &str, k: &str| {
            v.push(gap());
            v.extend(key(w, k));
        };
        match &self.view {
            View::Conversation => add(&mut v, "History", "\u{2191}"),
            View::Models | View::Talk | View::Steps(_) | View::Help | View::About | View::Preview | View::Apps | View::Home | View::Connections => {}
            View::Dest(_) | View::Section(_) | View::Folder(..) | View::Found(..) => {
                let rows = self.view_rows();
                // in a files folder every row opens its actions page (dialog/DESIGN.md)
                if rows.iter().any(|r| !r.more.is_empty()) || self.files_pane_view().is_some() {
                    add(&mut v, "Actions", "\u{2192}");
                }
                if rows.iter().any(|r| r.page.is_some()) {
                    add(&mut v, "Preview", "F3");
                }
                if self.two_panes() {
                    add(&mut v, "Pane", "Ctrl+Tab");
                }
                if rows.iter().any(|r| r.step.is_some()) {
                    add(&mut v, "Change", "\u{2190} \u{2192}");
                }
                if self.is_calendar() {
                    add(&mut v, "Month", "\u{2190} \u{2192}");
                }
            }
        }
        v
    }

    /// Every row the view holds, the words typed notwithstanding: what its key row offers is read from them all,
    /// so a filter that leaves no row with a page takes no label away.
    fn view_rows(&self) -> Vec<&model::Row> {
        match &self.view {
            View::Folder(..) => self.folder.as_ref().map(|(_, _, rows)| rows.rows.iter().collect()).unwrap_or_default(),
            View::Section(p) => self.providers[*p].rows.rows.iter().collect(),
            View::Dest(d) => self.dest_sections(*d).into_iter().flat_map(|p| self.providers[p].rows.rows.iter()).collect(),
            View::Found(k, words) => {
                let found = self.found(words);
                found
                    .iter()
                    .filter(|(f, _)| f == k)
                    .filter_map(|(_, it)| match it {
                        Item::Row(p, r) => self.providers[*p].rows.rows.get(*r),
                        Item::Hit(i) => self.hits.get(*i).map(|(_, r)| r),
                        _ => None,
                    })
                    .collect()
            }
            _ => vec![],
        }
    }

    /// The provider row an item stands for (a section's row, or a folder's).
    pub(crate) fn row_ref(&self, it: &Item) -> Option<&model::Row> {
        match it {
            Item::Row(p, r) => self.providers[*p].rows.rows.get(*r),
            Item::Folder(i) => self.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)),
            Item::Hit(i) => self.hits.get(*i).map(|(_, r)| r),
            _ => None,
        }
    }

    /// The provider an item's row is of: a section's, the folder's, the one that found it.
    fn prov_of(&self, it: &Item) -> Option<usize> {
        match it {
            Item::Row(p, _) => Some(*p),
            Item::Folder(_) => self.folder.as_ref().map(|(p, _, _)| *p),
            Item::Hit(i) => self.hits.get(*i).map(|(p, _)| *p),
            _ => None,
        }
    }

    /// The lit row and its provider, where the lit pick is a row.
    pub(crate) fn lit_row(&self) -> Option<(usize, model::Row)> {
        let it = self.picks().get(self.sel).cloned()?;
        Some((self.prov_of(&it)?, self.row_ref(&it)?.clone()))
    }

    /// A step's line as people read it, the command as typed: its tool's title with the arguments in
    /// place of the capital words (theme wallpaper NAME gives theme wallpaper none, out level N gives
    /// out level 60), never a secret; else the section and the row (#32).
    pub(crate) fn step_line(&self, p: usize, call: &Call, row_text: &str) -> String {
        let tool = self.providers[p].tools.iter().find(|t| t.name == call.name);
        let title = tool.map(|t| t.title.clone()).unwrap_or_default();
        if !title.is_empty() && model::title_ok(&title) {
            let schema = tool.map(|t| t.schema.clone()).unwrap_or(Value::Null);
            let mut args = call
                .arguments
                .iter()
                .filter(|(k, _)| !gate::secret(k, schema.pointer(&format!("/properties/{}", k))))
                .filter_map(|(k, v)| match v {
                    // a path reads by its last part: files rename photo.png, never the whole path (#112)
                    Value::String(s) if gate::is_path(&schema, k) => Some(s.rsplit('/').next().unwrap_or(s).to_string()),
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

    /// A step spark proposed, as a person reads it before Enter: the tool's title with the
    /// value in its capital's place when the step has one simple value; every field on its
    /// own line (`level: 30`) when it has more, so each value is seen before it runs.
    pub(crate) fn proposal_line(&self, p: usize, call: &Call) -> String {
        let title = self.providers[p]
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
        if simple {
            return self.step_line(p, call, &call.name);
        }
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
    }

    /// A click on a value row's arrow (#175): the row lit, and its step down or up, as left and right are.
    pub fn step_at(&mut self, n: usize, up: bool) {
        self.light(n);
        self.step_lit(up);
    }

    /// Left or right on a value row: its step down or up, run as a pick is.
    fn step_value(&mut self, up: bool) -> bool {
        if !self.in_list || !self.input.is_empty() {
            return false;
        }
        self.step_lit(up)
    }

    /// The lit value row's step down or up.
    fn step_lit(&mut self, up: bool) -> bool {
        if self.mode != Mode::Normal {
            return false;
        }
        let Some((prov, row)) = self.lit_row() else { return false };
        let Some(st) = row.step else { return false };
        self.keep_lit = Some(row.id.clone());
        // the next value in the list, on the screen now and set behind it; an end of the list does nothing,
        // its arrow dimmed (#183)
        let next = if up {
            Some(st.at + 1).filter(|i| *i < st.values.len())
        } else {
            st.at.checked_sub(1)
        };
        if let Some((i, call)) = next.and_then(|i| st.call_at(i).map(|c| (i, c))) {
            self.set_value(prov, &row.id, Held::At(i), call);
        }
        true
    }

    /// A switch flips, a setting changed in place is kept (a palette): the light stays on its row, and
    /// nothing is said unless it is refused (#183). False for any other row.
    fn flip_or_keep(&mut self, item: &Item) -> bool {
        let Some(row) = self.row_ref(item).cloned() else { return false };
        let Some(p) = self.prov_of(item) else { return false };
        if let Some(sw) = &row.switch {
            self.keep_lit = Some(row.id.clone());
            self.set_value(p, &row.id, Held::On(!sw.on), sw.flip());
            return true;
        }
        if let (true, Some(call)) = (row.quiet, row.tool.clone()) {
            self.keep_lit = Some(row.id.clone());
            if row.sign == "check" {
                return true; // the one in use already: nothing to set, nothing said (#191)
            }
            self.set_value(p, &row.id, Held::Checked, call);
            return true;
        }
        false
    }

    /// A value set in place (#183): held to its tool as every step is, shown on its row at once, then
    /// set; while one is being set, the newest wanted for each row waits, and only it is sent.
    fn set_value(&mut self, p: usize, id: &str, held: Held, call: Call) {
        let step = Step {
            prov: p,
            call: call.clone(),
            who: Who::Person,
            line: String::new(),
            typed: false,
        };
        if self.tool_of(&step).is_none() {
            return self.refuse("this is not offered here now");
        }
        if let Err(e) = self.checked(&step) {
            return self.refuse(&e);
        }
        self.reply = None;
        self.held.retain(|(hp, hid, _, _)| !(*hp == p && hid == id));
        self.held.push((p, id.to_string(), held, None));
        self.hold_rows(p);
        if self.setting.is_some() {
            self.set_next.retain(|(np, nid, _)| !(*np == p && nid == id));
            self.set_next.push((p, id.to_string(), call));
            return;
        }
        self.send_set(p, id, call);
    }

    fn send_set(&mut self, p: usize, id: &str, call: Call) {
        let params = json!({"name": call.name, "arguments": Value::Object(call.arguments.clone())});
        match self.server(p).and_then(|s| s.request("tools/call", params, Kind::Set, mcp::T_CALL)) {
            Some(n) => self.setting = Some((n, p, id.to_string(), call)),
            None => {
                self.held.retain(|(hp, hid, _, _)| !(*hp == p && hid == id));
                self.refuse("not changed: the part of the desktop that does it stopped");
            }
        }
    }

    /// A palette kept (#183): the dialog wears the colors its result carries, and a palette kept brings
    /// its animation; the theme section's own result only, plain colors only.
    fn wear_theme(&mut self, idx: usize, sc: &Value) {
        if self.providers[idx].label != "theme" {
            return;
        }
        if let Some(p) = sc.get("palette").and_then(Value::as_object) {
            if p.values().all(|v| {
                v.as_str()
                    .is_some_and(|s| s.is_empty() || (s.len() == 6 && s.bytes().all(|b| b.is_ascii_hexdigit())))
            }) {
                self.palette = Some(p.clone());
            }
        }
        if let Some(t) = sc.get("transitions").and_then(Value::as_str) {
            let whole = t.starts_with('/') && !t.split('/').any(|c| c == "..") && !t.chars().any(char::is_control);
            if t.is_empty() || whole {
                let want = (!t.is_empty()).then(|| t.to_string());
                if want != self.cfg.transitions {
                    self.cfg.transitions = want.clone();
                    self.films_want = Some(want);
                }
            }
        }
    }

    /// A value's set came back: audited as every step is; a refusal said and its value given back to the
    /// provider's rows; then the next one waiting, if any.
    fn set_done(&mut self, idx: usize, n: u64, refused: bool, said: &str, fresh: bool) {
        let Some((_, p, id, call)) = self.setting.take().filter(|(q, p, _, _)| *q == n && *p == idx) else {
            return;
        };
        let schema = self.providers[p]
            .tools
            .iter()
            .find(|t| t.name == call.name)
            .map(|t| t.schema.clone())
            .unwrap_or(Value::Null);
        crate::audit::record(Who::Person.word(), &self.providers[p].label, &call.name, &schema, &call.arguments, refused);
        let waiting = self.set_next.iter().any(|(np, nid, _)| *np == p && *nid == id);
        if refused && !waiting {
            self.held.retain(|(hp, hid, _, _)| !(*hp == p && *hid == id));
            self.refuse(said);
        } else if !waiting {
            let until = Instant::now() + HOLD;
            for h in self.held.iter_mut().filter(|(hp, hid, _, _)| *hp == p && *hid == id) {
                h.3 = Some(until);
            }
        }
        if !fresh {
            self.providers[p].dirty = true; // the rows read again: the provider's word on the value
        }
        if !self.set_next.is_empty() {
            let (np, nid, ncall) = self.set_next.remove(0);
            self.send_set(np, &nid, ncall);
        }
    }

    /// The values held for a provider's rows, over the rows as they came: a step's place, a switch's
    /// state, the setting kept checked, in the section or in the list shown of it (a wallpaper, an
    /// animation: one checked, #191). A hold that ran out goes.
    pub(crate) fn hold_rows(&mut self, p: usize) {
        let now = Instant::now();
        self.held.retain(|(_, _, _, until)| until.is_none_or(|u| u > now));
        let held: Vec<(String, Held)> = self.held.iter().filter(|h| h.0 == p).map(|h| (h.1.clone(), h.2.clone())).collect();
        for (id, h) in held {
            let rows = &mut self.providers[p].rows.rows;
            match h {
                Held::At(i) => {
                    if let Some(st) = rows.iter_mut().find(|r| r.id == id).and_then(|r| r.step.as_mut()) {
                        st.at = i.min(st.values.len().saturating_sub(1));
                    }
                }
                Held::On(on) => {
                    if let Some(sw) = rows.iter_mut().find(|r| r.id == id).and_then(|r| r.switch.as_mut()) {
                        sw.on = on;
                    }
                }
                Held::Checked => {
                    if rows.iter().any(|r| r.id == id) {
                        for r in rows.iter_mut().filter(|r| r.quiet) {
                            r.sign = if r.id == id { "check" } else { "blank" }.to_string();
                        }
                    }
                    // a list is one pick: the row kept is checked, the one checked before (a picture, a color) is not
                    if let Some((_, _, fr)) = self.folder.as_mut().filter(|(fp, _, fr)| *fp == p && fr.rows.iter().any(|r| r.id == id)) {
                        for r in fr.rows.iter_mut().filter(|r| r.id == id || r.sign == "check") {
                            r.sign = if r.id == id { "check" } else { "blank" }.to_string();
                        }
                    }
                }
            }
        }
    }

    /// Something the person asked for is under way: a step, a value being set, a request to spark. The pointer
    /// does not change for it (#196): the row shows the step, and spark's march its thinking.
    pub fn under_way(&self) -> bool {
        self.running.is_some() || self.setting.is_some() || self.wait.is_some()
    }

    /// The lit row's steps, when it has steps of its own (its more): Right opens them as a list of
    /// their own, Enter runs one, Esc comes back (#112). The row is kept as it was, so the list stands
    /// while its folder is read again.
    fn open_steps(&mut self) -> bool {
        if !self.in_list || !self.input.is_empty() || self.mode != Mode::Normal || self.picking.is_some() || self.attaching.is_some() {
            return false;
        }
        let Some((prov, row)) = self.lit_row() else { return false };
        if self.providers[prov].label == "files" && self.files_actions(Some(row.clone())) {
            return true; // the files' own page, in place of the list of steps (dialog/DESIGN.md)
        }
        if row.more.is_empty() {
            return false;
        }
        self.steps_of(prov, row);
        true
    }

    /// A row's steps as a list of their own (#112): Enter runs one, Esc comes back.
    fn steps_of(&mut self, prov: usize, row: model::Row) {
        self.want_cancel();
        self.target = None;
        self.keep_lit = None;
        self.steps_row = Some(row);
        self.came_from.push(self.view.clone());
        self.view = View::Steps(prov);
        self.sel = 0;
        self.in_list = true;
        self.scroll = 0;
    }

    /// The k-th step of the row whose steps are shown: its tool first, then its more.
    fn step_call(&self, k: usize) -> Option<Call> {
        let row = self.steps_row.as_ref()?;
        row.tool.iter().chain(row.more.iter()).nth(k).cloned()
    }

    /// A step's words in a list of steps: the provider's own ("move to a folder"), else its verb.
    pub fn step_words(&self, call: &Call) -> String {
        call.said.clone().unwrap_or_else(|| verb_of(&call.name).to_lowercase())
    }

    /// The words of the k-th step shown (the tests read them).
    pub fn step_call_words(&self, k: usize) -> Option<String> {
        self.step_call(k).map(|c| self.step_words(&c))
    }

    /// The rows a step from the model or an undo is held to: the folder on screen when it is the
    /// provider's (the files: a path a row holds), else the provider's own rows.
    fn rows_for_gate(&self, p: usize) -> &Rows {
        match &self.folder {
            Some((fp, _, rows)) if *fp == p => rows,
            _ => &self.providers[p].rows,
        }
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

impl App {
    pub fn remember_target(&mut self) {
        if self.target.is_some() || !self.input.is_empty() || !self.in_list {
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

    /// The pending request's reply, when it comes, belongs to nobody: a newer
    /// request, a row picked or Esc moved on.
    pub fn want_cancel(&mut self) {
        self.want_serial += 1;
        self.pending = None;
        if self.wait == Some(Work::Think) {
            self.wait = None;
        }
        self.jobs.retain(|j| !matches!(j, Job::RunInput(Helper::Want(_), _, _)));
    }
}

/// The preview (#120): opened by F3 on a lit row, or by the preview step of its list of steps.
impl App {
    /// A key that moves the preview: in it, nothing typed, nothing asked, no control in focus.
    fn preview_key(&self) -> bool {
        self.view == View::Preview && self.input.is_empty() && self.mode == Mode::Normal && self.chip_focus.is_none() && self.staged.is_none()
    }

    /// The lit row's page, where it has one (#120; every kind of row since #169): the list it is in goes with it, so
    /// up and down go to the next of its kind; false where it has none.
    pub(crate) fn open_preview(&mut self) -> bool {
        if !self.in_list || self.picking.is_some() || self.attaching.is_some() {
            return false;
        }
        let Some(it) = self.picks().get(self.sel).cloned() else { return false };
        let Some((p, row)) = self.lit_row() else { return false };
        let (place, rows): (String, Vec<model::Row>) = match it {
            Item::Folder(_) => match &self.folder {
                Some((_, _, rows)) => (rows.title.clone(), rows.rows.clone()),
                None => return false,
            },
            Item::Hit(_) => (
                section_name(&self.providers[p].label).to_lowercase(),
                self.hits.iter().filter(|(q, _)| *q == p).map(|(_, r)| r.clone()).collect(),
            ),
            _ => (section_name(&self.providers[p].label).to_lowercase(), self.providers[p].rows.rows.clone()),
        };
        let Some(pv) = Preview::new(p, &place, &rows, &row.id) else {
            return false;
        };
        // the words that filtered the folder go: in the preview Space plays and Esc goes back (#163)
        self.set_input(String::new());
        self.preview = Some(pv);
        self.preview_pages = 1;
        self.go(View::Preview);
        self.read_page();
        true
    }

    /// The page on screen asked of its provider; the answer replaces what is shown.
    fn read_page(&mut self) {
        let Some(pv) = self.preview.as_mut() else { return };
        pv.asked = Instant::now();
        pv.failed = false;
        let (p, uri) = (pv.prov, pv.uri());
        if let Some(s) = self.server(p) {
            s.request("resources/read", json!({"uri": uri}), Kind::Page, mcp::T_READ);
        }
    }

    /// Up and down: the list's previous or next file.
    fn preview_file(&mut self, d: i32) {
        self.stop_sound();
        if self.preview.as_mut().is_some_and(|pv| pv.step_file(d)) {
            self.preview_pages = 1;
            self.read_page();
        }
    }

    /// The pages the file has: a picture's from its provider, a text's as drawn.
    fn pages(&self) -> usize {
        match self.preview.as_ref().and_then(|pv| pv.shown.as_ref()) {
            Some(pg) if pg.picture.is_some() => pg.pages,
            Some(_) => self.preview_pages.max(1),
            None => 1,
        }
    }

    /// Left and right: the page before or after; a picture's page is asked for, a text's is drawn.
    fn preview_page(&mut self, d: i32) {
        let pages = self.pages();
        let Some(pv) = self.preview.as_mut() else { return };
        pv.page = pv.page.min(pages);
        if pv.step_page(d, pages) && pv.shown.as_ref().is_some_and(|pg| pg.picture.is_some()) {
            self.read_page();
        }
    }

    /// A picture shown, the preview's zoom and turn apply to it.
    fn has_picture(&self) -> bool {
        self.preview.as_ref().and_then(|pv| pv.shown.as_ref()).is_some_and(|pg| pg.picture.is_some())
    }

    /// Zoomed: the arrows move the picture, and Esc fits it.
    pub fn zoomed(&self) -> bool {
        self.has_picture() && self.preview.as_ref().is_some_and(|pv| pv.zoom.is_some())
    }

    /// A key of the picture's, nothing typed: + (or =) and - zoom, 0 fits, < and > turn a quarter.
    /// False for any other key, or with no picture shown: the key is typed.
    fn preview_picture_key(&mut self, c: char) -> bool {
        if !self.preview_key() || !self.has_picture() {
            return false;
        }
        let Some(pv) = self.preview.as_mut() else { return false };
        match c {
            '+' | '=' => {
                pv.zoom_step(1);
            }
            '-' => {
                pv.zoom_step(-1);
            }
            '0' => pv.fit(),
            '<' => pv.rotate(-1),
            '>' => pv.rotate(1),
            _ => return false,
        }
        if pv.needs_full() {
            pv.full = true;
            self.read_page();
        }
        true
    }

    /// Ctrl and the wheel, or a key: a zoom stop in or out.
    pub fn preview_zoom(&mut self, d: i32) {
        self.preview_picture_key(if d > 0 { '+' } else { '-' });
    }

    /// A drag or the wheel on a zoomed picture: it moves, by box pixels.
    pub fn preview_drag(&mut self, dx: f64, dy: f64) {
        if let Some(pv) = self.preview.as_mut().filter(|pv| pv.zoom.is_some() && pv.px.0 > 0) {
            pv.pan(-dx / pv.px.0 as f64, -dy / pv.px.1 as f64);
        }
    }

    /// The wheel in a preview: with Ctrl a zoom stop; on a zoomed picture it moves it; else a page.
    pub fn preview_wheel(&mut self, d: i32, ctrl: bool) {
        if ctrl {
            self.preview_zoom(-d);
        } else if self.zoomed() {
            self.preview_pan(0.0, d as f64);
        } else if !self.preview.as_ref().and_then(|pv| pv.shown.as_ref()).is_some_and(|pg| pg.sound.is_some()) {
            self.preview_page(d);
        }
    }

    /// The arrows on a zoomed picture: it moves a quarter of what is shown.
    fn preview_pan(&mut self, dx: f64, dy: f64) {
        if let Some(pv) = self.preview.as_mut() {
            pv.pan(dx * preview::PAN, dy * preview::PAN);
        }
    }

    /// The page shown plays: a sound, or a video (#151).
    pub fn preview_plays(&self) -> bool {
        self.preview.as_ref().and_then(|pv| pv.shown.as_ref()).is_some_and(|pg| pg.play.is_some())
    }

    /// A sound or a video `d` seconds back or ahead of where it is, playing on where it played (#151).
    fn preview_seek_by(&mut self, d: f64) {
        let Some(pv) = &self.preview else { return };
        let Some(pg) = pv.shown.as_ref() else { return };
        let (Some(play), len) = (pg.play.clone(), pg.seconds) else { return };
        let at = (pv.position(Instant::now()) + d).clamp(0.0, len.max(0.0));
        if pv.playing.is_some() {
            self.play_from(play, at);
        } else if let Some(pv) = self.preview.as_mut() {
            pv.played = at;
        }
    }

    /// A sound or a video: Space plays it from where it is, or pauses it there; a video with no player here plays in
    /// its app (#151).
    fn preview_play_pause(&mut self) {
        let Some(pv) = &self.preview else { return };
        let Some(play) = pv.shown.as_ref().and_then(|pg| pg.play.clone()) else {
            return;
        };
        if pv.playing.is_some() {
            return self.stop_sound();
        }
        let len = pv.shown.as_ref().map(|pg| pg.seconds).unwrap_or(0.0);
        let at = if len > 0.0 && pv.played >= len { 0.0 } else { pv.played };
        self.play_from(play, at);
    }

    /// A sound from a share of its length: a click on its waveform, Home back to the start.
    pub fn preview_seek(&mut self, share: f64) {
        let Some(pv) = &self.preview else { return };
        let Some(pg) = pv.shown.as_ref().filter(|pg| pg.sound.is_some()) else {
            return;
        };
        let (Some(play), len) = (pg.play.clone(), pg.seconds) else { return };
        let at = (share.clamp(0.0, 1.0) * len).max(0.0);
        if pv.playing.is_some() {
            self.play_from(play, at);
        } else if let Some(pv) = self.preview.as_mut() {
            pv.played = at;
        }
    }

    fn play_from(&mut self, mut play: Call, at: f64) {
        let Some(pv) = self.preview.as_mut() else { return };
        let (p, text) = (pv.prov, pv.row().text.clone());
        if pv.shown.as_ref().is_none_or(|pg| pg.stop.is_none()) {
            // a video plays in its app: a step like any, its window the receipt
            return self.pick_step(p, play, &text);
        }
        play.arguments.insert("at".into(), json!((at * 10.0).round() / 10.0));
        // a video: the box its frame was drawn in, where the player is laid (#125)
        if pv.shown.as_ref().is_some_and(|pg| pg.sound.is_none()) {
            if let Some((x, y, w, h)) = pv.frame {
                for (k, v) in [("x", x), ("y", y), ("w", w), ("h", h)] {
                    play.arguments.insert(k.into(), json!(v));
                }
            }
        }
        pv.played = at;
        pv.playing = Some(Instant::now());
        self.transport(p, play);
    }

    /// A sound's play or stop: a key of the preview's, as the Calendar's arrows are, so it says no turn
    /// in the exchange; held to its tool's schema, audited as every step is, and a refusal said.
    fn transport(&mut self, p: usize, call: Call) {
        let step = Step {
            prov: p,
            call: call.clone(),
            who: Who::Person,
            line: String::new(),
            typed: false,
        };
        if self.tool_of(&step).is_none() {
            return self.refuse("this is not offered here now");
        }
        if let Err(e) = self.checked(&step) {
            return self.refuse(&e);
        }
        let params = json!({"name": call.name, "arguments": Value::Object(call.arguments.clone())});
        if let Some(n) = self.server(p).and_then(|s| s.request("tools/call", params, Kind::Quiet, mcp::T_CALL)) {
            self.quiet.push((n, p, call));
        }
    }

    /// A video playing over its frame stops where it is: a click raises the dialog over the player, a new
    /// size moves the frame (#125).
    pub fn stop_video(&mut self) {
        if self
            .preview
            .as_ref()
            .is_some_and(|pv| pv.playing.is_some() && pv.shown.as_ref().is_some_and(|pg| pg.sound.is_none()))
        {
            self.stop_sound();
        }
    }

    /// A sound playing here stops where it is: leaving its file, leaving the preview, Right again.
    fn stop_sound(&mut self) {
        let now = Instant::now();
        let Some(pv) = self.preview.as_mut() else { return };
        if pv.playing.is_none() {
            return;
        }
        pv.played = pv.position(now);
        pv.playing = None;
        let Some(stop) = pv.shown.as_ref().and_then(|pg| pg.stop.clone()) else {
            return;
        };
        let p = pv.prov;
        self.transport(p, stop);
    }

    /// The preview's key row, nothing typed, each key whole where the row has room, in this order:
    /// open, back (fit, zoomed), the files (move, zoomed), the pages or play, zoom, turn. The about
    /// lists them all.
    fn preview_hint(&self, pages: usize) -> Vec<(String, bool)> {
        let pv = self.preview.as_ref();
        let shown = pv.and_then(|pv| pv.shown.as_ref());
        // the shared keys first, in the same places on every file and in every state (loading, zoomed); the
        // file's own after them, so a click never lands on another key when the file or the state changes
        // (#166). A word that changes keeps its width: Fit is Back's, Play is Pause's.
        let zoomed = self.zoomed();
        // the page's own keys, or the last page's while the next file's is on its way: the row never
        // blinks between files (#166)
        let own = shown.map(crate::preview::Keys::of).or_else(|| pv.and_then(|pv| pv.keys));
        let mut keys: Vec<(&str, &str)> = vec![(if zoomed { "Fit " } else { "Back" }, "Esc")];
        if zoomed {
            keys.push(("Move", "\u{2190} \u{2191} \u{2193} \u{2192}"));
        } else if pv.is_some_and(|pv| pv.files.len() > 1) {
            keys.push((pv.map(|pv| thing_of(&self.providers[pv.prov].label)).unwrap_or("File"), "\u{2191} \u{2193}"));
        }
        // what Enter does to the thing shown, in its tool's word (Open an app, Connect a network); nothing where it has no tool
        if let Some(t) = pv.and_then(|pv| pv.row().tool.as_ref()) {
            keys.push((verb_of(&t.name), "Enter"));
        }
        if !zoomed && own.is_some_and(|k| k.play) {
            // a player's keys: Space plays and pauses, the arrows seek (#151)
            keys.push((if pv.is_some_and(|pv| pv.playing.is_some()) { "Pause" } else { "Play " }, "Space"));
            keys.push(("Seek", "\u{2190} \u{2192}"));
        }
        if !zoomed && own.is_some_and(|k| if k.picture { k.pages > 1 } else { pages > 1 }) {
            keys.push(("Page", "\u{2190} \u{2192}"));
        }
        if own.is_some_and(|k| k.picture) {
            keys.push(("Zoom", "+ -"));
            keys.push(("Turn", "< >"));
        }
        let room = self.col_w().saturating_sub(4) as usize;
        let mut v: Vec<(String, bool)> = vec![];
        let mut used = 0;
        for (w, k) in keys {
            let need = if v.is_empty() { 0 } else { 3 } + cells(w) + 1 + cells(k) + 2;
            if used + need > room {
                break;
            }
            if !v.is_empty() {
                v.push(("   ".to_string(), false));
            }
            v.push((format!("{} ", w), false));
            v.push((k.to_string(), true));
            used += need;
        }
        v
    }
}

/// The transitions (#122): the dialog opens with one, waits with one, and closes with one.
impl App {
    /// The window closes: with the close playing first where the transitions are loaded (Esc, the x).
    pub fn close_window(&mut self) {
        // files being copied, moved or trashed: the x stops the batch and the dialog stays; the next x closes
        if self.files_stop_batch() {
            return;
        }
        if self.films {
            self.motion = Some((Reel::Close, Instant::now()));
            self.in_list = false;
        } else {
            self.quit = Some(0);
        }
    }

    /// A key or a click: the open or the wait stops where it is, and the key does what it does.
    pub fn cut_motion(&mut self) {
        if matches!(self.motion, Some((Reel::Open | Reel::Wait, _))) {
            self.motion = None;
        }
    }

    /// The home has its rows: every provider has answered, or stopped.
    pub fn home_ready(&self) -> bool {
        self.providers.iter().all(|p| p.ready || p.dead.is_some())
    }

    /// The transition moved on: the open ends in the wait while the home loads, the wait when it has,
    /// the close in the window going. `open` and `close` are how long they play.
    pub fn follow_motion(&mut self, now: Instant, open: u128, close: u128) {
        let Some((reel, since)) = self.motion else { return };
        let ms = now.duration_since(since).as_millis();
        match reel {
            Reel::Open if ms >= open => self.motion = (!self.home_ready()).then_some((Reel::Wait, now)),
            Reel::Wait if self.home_ready() || ms >= crate::transition::WAIT_MAX_MS => self.motion = None,
            Reel::Close if ms >= close => self.quit = Some(0),
            _ => {}
        }
    }
}
