//! The bar, pure: the modules a status line says, each with its facts, and the look it says; the levels as
//! they are drawn, the hand's change at once and the number's flow; where everything stands, the
//! workspaces' ten places and their plate among them; what a bar short of width gives up; what the pointer
//! and the keys reach and what they send back, and when the pointer off the bar gives the keys back; what
//! a frame shows, each thing in its tone; and the text of the state file. No Wayland, no sway, no file, no
//! environment, no clock: the time is handed in.

use serde_json::Value;

/// The name a click on spark's mark, or on the three dots, is sent under: it opens home.
pub const LOGO: &str = "logo";
/// The object that is the look, by its name: never a module or a target.
pub const LOOK: &str = "look";
/// The group of the time and the notifications' sign: a hairline stands before it, and it stays on a bar
/// short of width.
pub const TIME: &str = "time";
/// The id of the cell that stands for the modules left out.
pub const MORE: &str = "more";
/// What the cell for the modules left out shows, and the cell before the first line: three dots.
pub const ELLIPSIS: &str = "\u{2026}";
/// What stands where the status would be while spark-shell's status is broken: a warning sign, as text.
pub const WARNING: &str = "\u{26a0}\u{fe0e}";
/// The cells a note (the dots before the first line, the warning) keeps.
const NOTE_CELLS: i32 = 2;
/// The most cells one text may keep, and the most characters read of one.
const CELLS_MOST: usize = 400;
/// The places the workspaces always have: one for each of 1 to 10.
pub const PLACES: i32 = 10;
/// A place's cells, the plate's too: its two digits stand in the middle two.
const PLACE_CELLS: i32 = 3;
/// A gauge's cells.
pub const GAUGE_CELLS: i32 = 5;
/// A number's digit cells; the percent sign's cell follows them.
pub const DIGIT_CELLS: i32 = 3;
/// The cells between a module's parts, between the modules of a group, and between groups.
const PART_GAP: i32 = 1;
const MODULE_GAP: i32 = 3;
const GROUP_GAP: i32 = 5;
/// The cells of room at the bar's right edge.
const EDGE_CELLS: i32 = 2;
/// What a wheel step, or Up or Down, changes a level by, and what a click on a gauge is rounded to.
pub const STEP: i32 = 5;
/// How far the pointer may travel off the bar, in cells, before a bar that has the keys gives them back.
pub const TRAVEL_CELLS: i32 = 3;
/// How far a dim part on a chip is raised from the dim color toward the text's: halfway.
pub const RAISE: f64 = 0.5;
/// How long a digit takes to flow, in milliseconds.
pub const FLOW_MS: u64 = 120;
/// How long a step of the hand waits for the status's answer, in milliseconds: within that time a line
/// that says its value, while a later step waits too, is an old answer.
pub const HAND_MS: u64 = 1000;
/// The star family's gauge pair, full and light: the bar's until the environment or a line says one.
pub const PAIR: (&str, &str) = ("\u{2501}", "\u{2500}");

/// A rectangle in the surface's logical pixels.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub const fn new(x: i32, y: i32, w: i32, h: i32) -> Rect {
        Rect { x, y, w, h }
    }

    /// Whether a point is inside: the left and top edges are, the right and bottom ones are not.
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x as f64 && x < (self.x + self.w) as f64 && y >= self.y as f64 && y < (self.y + self.h) as f64
    }

    pub fn right(&self) -> i32 {
        self.x + self.w
    }
}

/// The screen edge the bar stands at.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Edge {
    #[default]
    Top,
    Bottom,
}

impl Edge {
    /// BAR_POSITION: bottom, or the top for anything else.
    pub fn parse(s: Option<&str>) -> Edge {
        match s.map(str::trim) {
            Some("bottom") => Edge::Bottom,
            _ => Edge::Top,
        }
    }

    pub fn word(self) -> &'static str {
        match self {
            Edge::Top => "top",
            Edge::Bottom => "bottom",
        }
    }
}

/// How a module is, as spark-shell says it: the bar picks each part's tone by it.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum State {
    #[default]
    Ok,
    Muted,
    Off,
    Missing,
    Wrong,
    Asks,
    Records,
}

impl State {
    fn of(word: Option<&str>) -> State {
        match word {
            Some("muted") => State::Muted,
            Some("off") => State::Off,
            Some("missing") => State::Missing,
            Some("wrong") => State::Wrong,
            Some("asks") => State::Asks,
            Some("records") => State::Records,
            _ => State::Ok,
        }
    }

    pub fn word(self) -> &'static str {
        match self {
            State::Ok => "ok",
            State::Muted => "muted",
            State::Off => "off",
            State::Missing => "missing",
            State::Wrong => "wrong",
            State::Asks => "asks",
            State::Records => "records",
        }
    }

    /// The sign's tone: the text's color while all is well; dim when muted, as its gauge is, off or missing;
    /// red for what is wrong or records; the attention color for what asks.
    pub fn sign(self) -> Tone {
        match self {
            State::Ok => Tone::Text,
            State::Muted | State::Off | State::Missing => Tone::Dim,
            State::Wrong | State::Records => Tone::Alert,
            State::Asks => Tone::Attention,
        }
    }

    /// The tone of a module's number, and of its text beside a sign: dim when off or missing. A module with
    /// no sign has its text in the sign's tone.
    pub fn text(self) -> Tone {
        match self {
            State::Off | State::Missing => Tone::Dim,
            _ => Tone::Text,
        }
    }

    /// The tone of a gauge's full cells: dim when muted or off, so every cell is. Its light cells are always dim.
    pub fn gauge(self) -> Tone {
        match self {
            State::Muted | State::Off | State::Missing => Tone::Dim,
            _ => Tone::Text,
        }
    }

    /// Whether a gauge's cells are drawn: with no device they stay empty.
    pub fn gauged(self) -> bool {
        self != State::Missing
    }

    /// Whether the number is drawn: muted or with no device its cells stay empty.
    pub fn numbered(self) -> bool {
        !matches!(self, State::Muted | State::Missing)
    }
}

/// The status as a whole: before the first line, lines coming, or the stream broken.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    Loading,
    Ok,
    Error,
}

impl Status {
    pub fn word(self) -> &'static str {
        match self {
            Status::Loading => "loading",
            Status::Ok => "ok",
            Status::Error => "error",
        }
    }
}

/// A text's glyphs, a cell each: a character with the marks that join it (a variation selector, a
/// combining mark, a joiner).
pub fn glyphs(s: &str) -> Vec<String> {
    let mut out: Vec<String> = vec![];
    for c in s.chars() {
        let joins = matches!(c as u32, 0x0300..=0x036f | 0x200d | 0x20d0..=0x20ff | 0xfe00..=0xfe0f);
        match out.last_mut() {
            Some(last) if joins => last.push(c),
            _ => out.push(c.to_string()),
        }
    }
    out
}

/// A string as the bar keeps it: no control character, and no more characters than a text may keep cells.
fn plain(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).take(CELLS_MOST).collect()
}

/// One module of a status line: facts, and no word on how they look.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Module {
    pub name: String,
    /// The group it stands in: modules of one group stand closer.
    pub group: String,
    /// Its glyph, or its word; empty when it has none.
    pub sign: String,
    /// The plain text after the sign; empty when none.
    pub text: String,
    /// The cells kept for the text, its widest: a text that changes moves nothing.
    pub cells: i32,
    pub bold: bool,
    pub state: State,
    /// 0 to 100 when the module has a level.
    pub level: Option<i32>,
    /// The level can be set from the bar.
    pub set: bool,
    /// Its control is on the bar: the gauge and the number.
    pub pinned: bool,
    /// A click on its sign or its text changes something in place and opens nothing: the keys stay on it.
    pub toggle: bool,
    /// Its name and state in words.
    pub label: Option<String>,
}

impl Module {
    /// An object with a name; anything else is no module.
    fn of(v: &Value) -> Option<Module> {
        let o = v.as_object()?;
        let said = |k: &str| o.get(k).and_then(Value::as_str).map(plain).unwrap_or_default();
        let flag = |k: &str| o.get(k).and_then(Value::as_bool).unwrap_or(false);
        let name = said("name");
        if name.is_empty() {
            return None;
        }
        let text = said("text");
        let cells = o.get("cells").and_then(Value::as_i64).filter(|n| *n >= 0);
        Some(Module {
            name,
            group: said("group"),
            sign: said("sign"),
            cells: cells.map_or(glyphs(&text).len(), |n| (n as usize).min(CELLS_MOST)) as i32,
            text,
            bold: flag("bold"),
            state: State::of(o.get("state").and_then(Value::as_str)),
            level: o.get("level").and_then(Value::as_i64).map(|n| n.clamp(0, 100) as i32),
            set: flag("set"),
            pinned: flag("pinned"),
            toggle: flag("toggle"),
            label: Some(said("label").trim().to_string()).filter(|s| !s.is_empty()),
        })
    }

    /// The module's name and state in words: its label, else its name; never empty.
    pub fn title(&self) -> String {
        self.label.clone().unwrap_or_else(|| self.name.clone())
    }
}

/// A color as spark-shell says it: red, green and blue, a byte each.
pub type Color = [u8; 3];

/// A color said as rrggbb (or #rrggbb), the blanks around it dropped; None for anything else. The
/// environment's colors (BAR_FG and the rest) and a status line's look are both read by this.
pub fn hex(s: &str) -> Option<Color> {
    let s = s.trim().trim_start_matches('#');
    if s.len() != 6 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let v = u32::from_str_radix(s, 16).ok()?;
    Some([(v >> 16) as u8, (v >> 8) as u8, v as u8])
}

/// The ground's alpha said as a number, kept within 0 to 1; None for anything else. BAR_ALPHA and a
/// status line's look are both read by this.
pub fn alpha(s: &str) -> Option<f64> {
    s.trim().parse::<f64>().ok().filter(|a| a.is_finite()).map(|a| a.clamp(0.0, 1.0))
}

/// One glyph of the family's gauge pair, the blanks around it dropped; None for anything that is not one
/// glyph. BAR_GAUGE_FULL, BAR_GAUGE_LIGHT and a status line's look are read by this.
pub fn pair_glyph(s: &str) -> Option<String> {
    let s = s.trim();
    let one = glyphs(s);
    (one.len() == 1 && !s.chars().any(char::is_control)).then(|| s.to_string())
}

/// Whether the digits flow, said as yes or no; None for anything else. BAR_MOTION and a status line's look
/// are read by this.
pub fn motion(s: &str) -> Option<bool> {
    match s.trim() {
        "yes" => Some(true),
        "no" => Some(false),
        _ => None,
    }
}

/// The look a status line says, in its object named look: the palette's slots, a color each, the ground's
/// alpha, the family's gauge pair and whether the digits flow, each a string in the form the environment
/// has it. A slot the line leaves out or gets wrong is None: the environment's stands for it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Look {
    pub fg: Option<Color>,
    pub accent: Option<Color>,
    /// The dim tone.
    pub muted: Option<Color>,
    pub ground: Option<Color>,
    pub lit: Option<Color>,
    pub attention: Option<Color>,
    /// Red: what is wrong, what records.
    pub alert: Option<Color>,
    /// What is written on the accent: the plate's digits, and the keys' line on it.
    pub ink: Option<Color>,
    pub alpha: Option<f64>,
    /// The pair's full glyph and its light one: the gauges' cells and the workspaces' places.
    pub full: Option<String>,
    pub light: Option<String>,
    pub motion: Option<bool>,
}

impl Look {
    fn of(v: &Value) -> Look {
        let color = |k: &str| v[k].as_str().and_then(hex);
        Look {
            fg: color("fg"),
            accent: color("accent"),
            muted: color("muted"),
            ground: color("ground"),
            lit: color("lit"),
            attention: color("attention"),
            alert: color("alert"),
            ink: color("ink"),
            alpha: v["alpha"].as_str().and_then(alpha),
            full: v["full"].as_str().and_then(pair_glyph),
            light: v["light"].as_str().and_then(pair_glyph),
            motion: v["motion"].as_str().and_then(motion),
        }
    }
}

/// One line of the status stream: the modules of a refresh, in the line's order, and the look it says, or
/// None for the header, the opening bracket and anything that is not an array. A comma before or after the
/// array is the stream's own. The object named look is the look and no module; of several, the last. An
/// object without a name is no module, and of two modules under one name the first stands.
pub fn parse_refresh(line: &str) -> Option<(Vec<Module>, Look)> {
    let line = line.trim();
    let line = line.strip_prefix(',').unwrap_or(line);
    let line = line.strip_suffix(',').unwrap_or(line).trim();
    let v: Value = serde_json::from_str(line).ok()?;
    let (mut modules, mut look): (Vec<Module>, Look) = (vec![], Look::default());
    for v in v.as_array()? {
        if v["name"] == LOOK {
            look = Look::of(v);
        } else if let Some(m) = Module::of(v) {
            if !modules.iter().any(|have| have.name == m.name) {
                modules.push(m);
            }
        }
    }
    Some((modules, look))
}

/// A line's modules alone.
pub fn parse_line(line: &str) -> Option<Vec<Module>> {
    parse_refresh(line).map(|(modules, _)| modules)
}

/// A level as the bar draws it: what the last line said, or what the hand set since, and the level
/// before it while the number flows from one to the other.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Drawn {
    name: String,
    level: i32,
    from: i32,
    /// When the level changed, in milliseconds; none for a level that never did.
    since: Option<u64>,
    /// The steps of the hand the status has not answered yet: the values it set within the last HAND_MS,
    /// each with its time, in the order they were set.
    hand: Vec<(i32, u64)>,
}

impl Drawn {
    /// The steps the hand made longer ago than HAND_MS are forgotten: no answer to them is waited for.
    fn forget(&mut self, at: u64) {
        self.hand.retain(|(_, set)| at.saturating_sub(*set) < HAND_MS);
    }

    /// A line's level taken as the status's answer to the hand's steps, which it answers in turn: the
    /// earliest step that set this value is answered by it, and every step before that one with it. True
    /// when a later step is still unanswered: the line is an old answer and is not drawn. The answer to the
    /// last step leaves none: the burst is answered, and every line after it is news. A value no step set
    /// is news too, and answers none.
    fn answers(&mut self, level: i32) -> bool {
        match self.hand.iter().position(|set| set.0 == level) {
            Some(step) => {
                self.hand.drain(..=step);
                !self.hand.is_empty()
            }
            None => false,
        }
    }

    /// The level drawn from a time on, the number flowing to it from the one before.
    fn draw(&mut self, level: i32, at: u64) {
        (self.from, self.level, self.since) = (self.level, level, Some(at));
    }
}

/// A number on its way: from the level before to the level drawn, and how far, 0 to 1, eased out.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Flow {
    pub from: i32,
    pub to: i32,
    pub part: f64,
}

/// The levels the bar draws, by module. A wheel step, an arrow or a click on a gauge changes one at once;
/// the status's lines are the truth, and replace it, all but the old answers: in a burst of steps the
/// status answers each in turn, and a line that says the value of a step the hand made in the last
/// second, while a later step is still unanswered, is the answer to the earlier one and is not drawn. Once
/// the last step is answered the burst is over, and every line is news again. A level that changes,
/// either way, has its number flow for FLOW_MS from then.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Levels {
    all: Vec<Drawn>,
}

impl Levels {
    /// A line's levels, at a time in milliseconds. Each replaces the one drawn, the number flowing from one
    /// to the other, unless it is an old answer: the value of a step the hand made within the last second,
    /// with a later step still unanswered. The line that says the hand's last step confirms it, and with it
    /// the burst is answered: what a line says after that is news, a value the hand passed through too. A
    /// value no unanswered step set is the truth, as a change that failed is. A module the line does not
    /// name, or names without a level, has none. True when a drawn level changed, or a level came or went.
    pub fn said(&mut self, modules: &[Module], at: u64) -> bool {
        let mut all: Vec<Drawn> = vec![];
        let mut changed = false;
        for m in modules {
            let Some(level) = m.level else { continue };
            let mut d = self.all.iter().find(|d| d.name == m.name).cloned().unwrap_or_else(|| {
                changed = true;
                Drawn {
                    name: m.name.clone(),
                    level,
                    from: level,
                    since: None,
                    hand: vec![],
                }
            });
            d.forget(at);
            let old = d.answers(level);
            if d.level != level && !old {
                d.draw(level, at);
                changed = true;
            }
            all.push(d);
        }
        changed |= all.len() != self.all.len();
        self.all = all;
        changed
    }

    /// The hand's change, at once: a module's level drawn as `level` from now, kept within 0 to 100, and
    /// remembered for HAND_MS as a step the status has yet to answer. True when the level drawn changed; a
    /// module with no level has none to set.
    pub fn set(&mut self, name: &str, level: i32, at: u64) -> bool {
        let level = level.clamp(0, 100);
        let Some(d) = self.all.iter_mut().find(|d| d.name == name) else {
            return false;
        };
        d.forget(at);
        d.hand.push((level, at));
        if d.level == level {
            return false;
        }
        d.draw(level, at);
        true
    }

    /// A module's level as it is drawn.
    pub fn level(&self, name: &str) -> Option<i32> {
        self.all.iter().find(|d| d.name == name).map(|d| d.level)
    }

    /// Every level drawn, in the line's order.
    pub fn each(&self) -> impl Iterator<Item = (&str, i32)> {
        self.all.iter().map(|d| (d.name.as_str(), d.level))
    }

    /// A module's number on its way at a time; none once FLOW_MS have passed, and for a level that never changed.
    pub fn flow(&self, name: &str, at: u64) -> Option<Flow> {
        let d = self.all.iter().find(|d| d.name == name)?;
        let passed = at.saturating_sub(d.since?);
        (passed < FLOW_MS).then(|| Flow {
            from: d.from,
            to: d.level,
            part: ease(passed as f64 / FLOW_MS as f64),
        })
    }
}

/// How far a move is at `t` of its time, 0 to 1: eased out, fast at first and slow into place.
pub fn ease(t: f64) -> f64 {
    let t = if t.is_finite() { t.clamp(0.0, 1.0) } else { 1.0 };
    1.0 - (1.0 - t).powi(3)
}

/// A number's three digit cells, the digits at the right: 5 is two blanks and a 5, 100 fills them.
pub fn digits(level: i32) -> [Option<char>; DIGIT_CELLS as usize] {
    let mut out = [None; DIGIT_CELLS as usize];
    for (i, c) in level.clamp(0, 999).to_string().chars().rev().enumerate() {
        out[DIGIT_CELLS as usize - 1 - i] = Some(c);
    }
    out
}

/// The cells a gauge of five draws full for a level: level x 5 / 100, rounded, and at least one above zero.
pub fn full_cells(level: i32) -> i32 {
    match level.clamp(0, 100) {
        0 => 0,
        l => ((l * GAUGE_CELLS + 50) / 100).max(1),
    }
}

/// The level a click on a gauge asks for: the place clicked along its width, to the nearest STEP, in the
/// whole numbers spark-shell reckons it in: (x * 100 / width + 2) / 5 * 5, each division dropping its
/// remainder, kept within 0 to 100. So the level drawn at once is the one the status sets. None for a
/// gauge of no width: spark-shell sets nothing from one.
pub fn level_at(x: i32, width: i32) -> Option<i32> {
    (width > 0).then(|| ((x.saturating_mul(100) / width + STEP / 2) / STEP * STEP).clamp(0, 100))
}

/// A digit in its cell: where it stands below its place, in cell heights; above it when negative.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Roll {
    pub digit: char,
    pub shift: f64,
}

/// What a number's three digit cells show `part` of the way (0 to 1) from one level to another. A cell
/// whose digit does not change shows it, still. In a cell whose digit changes, the old one leaves, upward
/// when the level rose and downward when it fell, and the new one follows it in from the other side, a
/// cell's height behind.
pub fn rolls(from: i32, to: i32, part: f64) -> [Vec<Roll>; DIGIT_CELLS as usize] {
    let (old, new) = (digits(from), digits(to));
    let part = if part.is_finite() { part.clamp(0.0, 1.0) } else { 1.0 };
    let way = if to > from { -1.0 } else { 1.0 };
    std::array::from_fn(|i| {
        if old[i] == new[i] || part >= 1.0 {
            return new[i].map(|digit| Roll { digit, shift: 0.0 }).into_iter().collect();
        }
        let leaves = old[i].map(|digit| Roll { digit, shift: way * part });
        let comes = new[i].map(|digit| Roll {
            digit,
            shift: way * (part - 1.0),
        });
        leaves.into_iter().chain(comes).collect()
    })
}

/// A workspace as sway lists it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Workspace {
    /// Its number; none when its name has none.
    pub num: Option<i32>,
    pub name: String,
    pub output: String,
    /// Shown on its output now.
    pub visible: bool,
    /// The one workspace sway has the focus on.
    pub focused: bool,
    pub urgent: bool,
}

/// sway's answer to get_workspaces, in number order; the ones without a number after, as sway has them.
pub fn workspaces(v: &Value) -> Vec<Workspace> {
    let mut all: Vec<Workspace> = v
        .as_array()
        .map(|a| {
            a.iter()
                .map(|w| Workspace {
                    num: w["num"].as_i64().filter(|n| (0..=i32::MAX as i64).contains(n)).map(|n| n as i32),
                    name: w["name"].as_str().unwrap_or("").to_string(),
                    output: w["output"].as_str().unwrap_or("").to_string(),
                    visible: w["visible"] == true,
                    focused: w["focused"] == true,
                    urgent: w["urgent"] == true,
                })
                .collect()
        })
        .unwrap_or_default();
    all.sort_by_key(|w| w.num.map_or((1, 0), |n| (0, n)));
    all
}

/// Whether a workspace's name is a rest name: the rest name itself, or the rest name, a space and more
/// (idle, idle DP-1). With no rest name, none is.
pub fn rests(rest: &str, name: &str) -> bool {
    !rest.is_empty() && name.strip_prefix(rest).is_some_and(|more| more.is_empty() || more.starts_with(' '))
}

/// Whether an output rests: the workspace it shows now has a rest name. Such an output has no bar.
pub fn resting(rest: &str, workspaces: &[Workspace], output: &str) -> bool {
    workspaces.iter().any(|w| w.output == output && w.visible && rests(rest, &w.name))
}

/// sway's binding mode, from its answer to get_binding_state: its name, or None in the default mode.
pub fn mode(v: &Value) -> Option<String> {
    v["name"].as_str().filter(|n| !n.is_empty() && *n != "default").map(String::from)
}

impl Workspace {
    /// workspace:N, or workspace:NAME without a number.
    pub fn id(&self) -> String {
        match self.num {
            Some(n) => format!("workspace:{n}"),
            None => format!("workspace:{}", self.name),
        }
    }

    /// Its name as a control: "workspace 2".
    pub fn title(&self) -> String {
        match self.num {
            Some(n) => format!("workspace {n}"),
            None => format!("workspace {}", self.name).trim().to_string(),
        }
    }

    /// The sway command that shows it.
    pub fn command(&self) -> String {
        match self.num {
            Some(n) => format!("workspace number {n}"),
            None => format!("workspace \"{}\"", self.name.replace(['"', '\\'], "")),
        }
    }

    /// What its plate says, in two cells: its number's last two digits (02, 10, 23), or without a number
    /// its name's first two characters.
    pub fn plate(&self) -> String {
        match self.num {
            Some(n) => format!("{:02}", n % 100),
            None => glyphs(&plain(&self.name)).into_iter().take(2).collect(),
        }
    }
}

/// Whether a workspace has one of the ten places that always stand.
fn placed(w: &Workspace) -> bool {
    w.num.is_some_and(|n| (1..=PLACES).contains(&n))
}

/// A place in the workspaces' run, on one output's bar.
struct Place {
    id: String,
    name: String,
    command: String,
    label: String,
    /// A workspace exists there, on any output.
    full: bool,
    urgent: bool,
    /// This output shows it: it is the plate.
    plate: bool,
    focused: bool,
}

impl Place {
    fn of(id: String, name: String, command: String, label: String, there: &[&Workspace], output: &str) -> Place {
        let here = |w: &&&Workspace| w.output == output && w.visible;
        Place {
            id,
            name,
            command,
            label,
            full: !there.is_empty(),
            urgent: there.iter().any(|w| w.urgent),
            plate: there.iter().any(|w| here(&w)),
            focused: there.iter().filter(here).any(|w| w.focused),
        }
    }
}

/// The run's places on an output's bar: one for each of 1 to 10, whether a workspace is there or not, then
/// one for every other workspace (a higher number, a name), in the order sway's list was put in. A
/// workspace with a rest name is left out, on every output's bar.
fn places(workspaces: &[Workspace], output: &str, rest: &str) -> Vec<Place> {
    let workspaces: Vec<&Workspace> = workspaces.iter().filter(|w| !rests(rest, &w.name)).collect();
    let mut out = vec![];
    for n in 1..=PLACES {
        let there: Vec<&Workspace> = workspaces.iter().copied().filter(|w| w.num == Some(n)).collect();
        out.push(Place::of(
            format!("workspace:{n}"),
            format!("workspace {n}"),
            format!("workspace number {n}"),
            format!("{n:02}"),
            &there,
            output,
        ));
    }
    for w in workspaces.iter().copied().filter(|w| !placed(w)) {
        out.push(Place::of(w.id(), w.title(), w.command(), w.plate(), &[w], output));
    }
    out
}

/// What the owner chose for the bar itself: the order modules leave in when the width is short, and the
/// room kept clear at the right end for another program's tray. What is on the bar, and which controls are
/// pinned, the status line says.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Prefs {
    pub overflow: Vec<String>,
    pub tray_width: i32,
    pub tray_output: String,
}

impl Prefs {
    /// BAR_OVERFLOW (names apart by blanks), BAR_TRAY_WIDTH and BAR_TRAY_OUTPUT.
    pub fn new(overflow: &str, tray_width: i32, tray_output: &str) -> Prefs {
        Prefs {
            overflow: overflow.split_whitespace().map(String::from).collect(),
            tray_width: tray_width.max(0),
            tray_output: tray_output.trim().to_string(),
        }
    }

    /// The pixels kept clear at the right end of an output's bar.
    pub fn tray_on(&self, output: &str) -> i32 {
        if self.tray_output.is_empty() || self.tray_output == output {
            self.tray_width
        } else {
            0
        }
    }
}

/// The bar's sizes, from its text's: one character cell, the bar's height and the mark's side.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Metrics {
    pub cell: i32,
    pub height: i32,
    pub mark: i32,
}

impl Metrics {
    /// From the text's size in pixels and the width of "0" in the font: at 16 px, 36 high with a mark of 24.
    pub fn for_text(px: f64, zero: f64) -> Metrics {
        let px = if px.is_finite() && px >= 1.0 { px.min(256.0) } else { 16.0 };
        let zero = if zero.is_finite() && zero >= 1.0 { zero.min(256.0) } else { px * 0.6 };
        Metrics {
            cell: zero.ceil() as i32,
            height: (px * 2.25).round() as i32,
            mark: (px * 1.5).round() as i32,
        }
    }

    /// How far the plate's box stands in from the bar's top and bottom: a ninth of the height, 4 px of 36.
    pub fn inset(&self) -> i32 {
        (self.height as f64 / 9.0).round() as i32
    }
}

/// What a target is, in the state file's words.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Mark,
    Workspace,
    /// The sign or the text of a module that says toggle: a click changes something in place, and the keys stay.
    Toggle,
    /// The gauge of a level that can be set: a click sets it to the place clicked, Home and End to its ends.
    Level,
    Open,
}

impl Kind {
    pub fn word(self) -> &'static str {
        match self {
            Kind::Mark => "mark",
            Kind::Workspace => "workspace",
            Kind::Toggle => "toggle",
            Kind::Level => "level",
            Kind::Open => "open",
        }
    }
}

/// A color of the look, by what it is for: the surface has the color itself.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tone {
    /// The text's color: all that is well.
    Text,
    /// The dim color: what is off or missing, a place with no workspace, a gauge's light cells, the hairline.
    Dim,
    /// Red: what is wrong, what records.
    Alert,
    /// What asks for you: a module that asks, a workspace with an urgent window, the binding mode.
    Attention,
    /// The plate and the keys' line, and nothing else.
    Accent,
    /// The ground's color: the plate's digits, and the keys' line on it, when the look says no ink.
    Ground,
    /// The look's ink: the plate's digits, and the keys' line on it.
    Ink,
    /// The chip under the pointer.
    Lit,
    /// A dim part on a chip: the dim color raised toward the text's by RAISE, so the pointer never lowers
    /// its contrast.
    Raised,
}

/// Where a target's click goes: to spark-shell as a click on a part, or to sway as a command.
#[derive(Clone, Debug, PartialEq, Eq)]
enum To {
    Shell { name: String, instance: String },
    Sway(String),
}

/// What a target shows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum What {
    /// Spark's mark, in its square.
    Mark(Rect),
    /// A workspace's place: three cells of the pair's full glyph where a workspace exists, of its light one
    /// where none does.
    Place { full: bool },
    /// The workspace this output shows: its place as the plate, and its two characters.
    Plate(String),
    /// A sign, a text or the three dots: glyphs, a cell each.
    Text { glyphs: Vec<String>, bold: bool },
    /// A gauge: so many of its five cells full.
    Gauge { full: i32 },
    /// A level's number: its module, the level, and where the four cells kept for it begin.
    Number { module: String, level: i32, x: i32 },
}

/// Something the pointer and the keys reach: a part as it is drawn, what it is, how it is and its name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
    pub id: String,
    /// The part as wide as it is drawn, the bar's whole height: what the pointer hits.
    pub rect: Rect,
    pub kind: Kind,
    pub state: State,
    /// The control's name, never empty.
    pub name: String,
    /// A workspace: the one this output shows, with the focus.
    pub selected: bool,
    pub urgent: bool,
    /// A workspace: the one this output shows, the plate.
    pub visible: bool,
    /// A workspace's place with no workspace.
    pub empty: bool,
    /// The part's own tone: what it is drawn in, at rest and on its chip.
    pub tone: Tone,
    pub what: What,
    to: To,
    /// The module whose level a wheel step here changes at once; none where no level can be set.
    sets: Option<String>,
}

impl Target {
    fn new(id: String, rect: Rect, kind: Kind, name: String, tone: Tone, what: What, to: To) -> Target {
        Target {
            id,
            rect,
            kind,
            state: State::Ok,
            name,
            selected: false,
            urgent: false,
            visible: false,
            empty: false,
            tone,
            what,
            to,
            sets: None,
        }
    }
}

/// One thing a frame draws.
#[derive(Clone, Debug, PartialEq)]
pub enum Draw {
    /// A box filled: the plate, a chip, the keys' line, the hairline.
    Fill { rect: Rect, tone: Tone },
    /// Spark's mark, in its square.
    Mark { rect: Rect },
    /// A glyph (or a plate's two) in the middle of its box. `fit`: one of the family's pair, drawn as wide
    /// as its cell and cut at it, so a run of them joins and ends with its cells. `shift`: a digit on its
    /// way, so far below its place in box heights (above when negative), and cut at its box.
    Glyph {
        rect: Rect,
        text: String,
        tone: Tone,
        bold: bool,
        fit: bool,
        shift: f64,
    },
}

/// What a bar shows: an output's width and workspaces, and the status every output repeats.
pub struct Scene<'a> {
    pub output: &'a str,
    pub width: i32,
    pub edge: Edge,
    pub status: Status,
    pub modules: &'a [Module],
    /// The levels as they are drawn; a module it does not have is drawn at the level the line said.
    pub levels: &'a Levels,
    /// Every output's workspaces.
    pub workspaces: &'a [Workspace],
    /// sway's binding mode, on every output; none in the default one.
    pub mode: Option<&'a str>,
    /// The rest name: a workspace named so has no place; empty for none.
    pub rest: &'a str,
}

/// A bar laid out: its targets in the keys' order (left to right), what stands whatever the pointer and
/// the keys do (the binding mode, the hairline, a note), and what was left out for width, in the order it went.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Layout {
    pub width: i32,
    pub height: i32,
    pub edge: Edge,
    cell: i32,
    inset: i32,
    pub targets: Vec<Target>,
    pub fixed: Vec<Draw>,
    pub dropped: Vec<String>,
}

/// A module on the bar, with the parts it still has: on a bar short of width a pinned control gives up
/// its number, then its gauge.
struct Piece<'a> {
    m: &'a Module,
    sign: Vec<String>,
    level: i32,
    gauge: bool,
    number: bool,
}

impl Piece<'_> {
    /// The cells its parts take, each part's own and one between two.
    fn cells(&self) -> i32 {
        let parts = [
            self.sign.len() as i32,
            if self.gauge { GAUGE_CELLS } else { 0 },
            if self.number { DIGIT_CELLS + 1 } else { 0 },
            self.m.cells,
        ];
        let n = parts.iter().filter(|p| **p > 0).count() as i32;
        parts.iter().sum::<i32>() + (n - 1).max(0) * PART_GAP
    }
}

/// The cells between two modules next to each other: three inside a group, five between groups.
fn gap(a: &Module, b: &Module) -> i32 {
    if a.group == b.group {
        MODULE_GAP
    } else {
        GROUP_GAP
    }
}

/// The cells the status takes: its modules and their gaps, and the cell for the modules left out a
/// group's gap before them.
fn status_cells(pieces: &[Piece], more: bool) -> i32 {
    let mut n: i32 = pieces.iter().map(Piece::cells).sum();
    n += pieces.windows(2).map(|p| gap(p[0].m, p[1].m)).sum::<i32>();
    if more {
        n += 1 + if pieces.is_empty() { 0 } else { GROUP_GAP };
    }
    n
}

/// The order modules leave in when the width is short: the ones BAR_OVERFLOW does not name first, from the
/// left of the line, then the named ones in BAR_OVERFLOW's order. The time's group never leaves.
fn drop_order(pieces: &[Piece], overflow: &[String]) -> Vec<String> {
    let named = |p: &&Piece| overflow.iter().position(|o| *o == p.m.name);
    let may: Vec<&Piece> = pieces.iter().filter(|p| p.m.group != TIME).collect();
    let mut order: Vec<&Piece> = may.iter().copied().filter(|p| named(p).is_none()).collect();
    let mut rest: Vec<&Piece> = may.iter().copied().filter(|p| named(p).is_some()).collect();
    rest.sort_by_key(|p| named(p));
    order.extend(rest);
    order.iter().map(|p| p.m.name.clone()).collect()
}

/// The bar laid out, in cells of the bar's font.
///
/// From the left: one cell, the mark, one cell, then the workspaces' run: a place of three cells for each
/// of 1 to 10 and for every other workspace after them, none between, so the run of ten is thirty cells.
/// The place this output shows is the plate, in its own three cells: no place moves when another
/// workspace is shown.
///
/// From the right: two cells of room (after the tray's), then the status in the line's order: one cell
/// between a module's parts, three between the modules of a group, five between groups. A module's parts
/// are its sign; pinned and with a level, its gauge of five cells and its number in four (three digits
/// at the right and the percent sign); then the cells kept for its text. A hairline stands in the middle
/// of the gap before the time's group, when something stands left of it.
///
/// Short of width, with five cells kept between the run and the status: every number goes, then every
/// gauge, then whole modules in the overflow order, three dots standing for them at the status's left
/// end. The run and the time's group stay; a bar with no room even for those shows no status.
///
/// sway's binding mode stands one cell after the run, in the room the status leaves: the status is fitted
/// as if there were no mode, so a mode moves no module and drops none. It is cut five cells before the
/// status, and is no target.
pub fn layout(scene: &Scene, prefs: &Prefs, m: &Metrics) -> Layout {
    let (cell, h) = (m.cell.max(1), m.height);
    let mut lay = Layout {
        width: scene.width,
        height: h,
        edge: scene.edge,
        cell,
        inset: m.inset(),
        ..Layout::default()
    };
    let home = || To::Shell {
        name: LOGO.into(),
        instance: String::new(),
    };
    let square = Rect::new(cell, (h - m.mark) / 2, m.mark, m.mark);
    lay.targets.push(Target::new(
        "mark".into(),
        Rect::new(cell, 0, m.mark, h),
        Kind::Mark,
        "spark".into(),
        Tone::Lit,
        What::Mark(square),
        home(),
    ));

    // the workspaces' run
    let mut x = cell + m.mark + cell;
    for p in places(scene.workspaces, scene.output, scene.rest) {
        let rect = Rect::new(x, 0, PLACE_CELLS * cell, h);
        x += PLACE_CELLS * cell;
        if rect.right() > scene.width {
            continue;
        }
        let (tone, what) = match (p.plate, p.urgent, p.full) {
            (true, ..) => (Tone::Accent, What::Plate(p.label)),
            (_, true, _) => (Tone::Attention, What::Place { full: true }),
            (_, _, full) => (if full { Tone::Text } else { Tone::Dim }, What::Place { full }),
        };
        lay.targets.push(Target {
            selected: p.plate && p.focused,
            urgent: p.urgent,
            visible: p.plate,
            empty: !p.full,
            ..Target::new(p.id, rect, Kind::Workspace, p.name, tone, what, To::Sway(p.command))
        });
    }
    let run_end = x;

    // the status: what the line says is on the bar, then what the width lets stay
    let right = (scene.width - prefs.tray_on(scene.output)).max(0) - EDGE_CELLS * cell;
    let mut pieces: Vec<Piece> = vec![];
    if scene.status == Status::Ok {
        for module in scene.modules.iter().filter(|module| module.name != LOGO) {
            let level = scene.levels.level(&module.name).or(module.level);
            let control = module.pinned && level.is_some();
            let piece = Piece {
                m: module,
                sign: glyphs(&module.sign),
                level: level.unwrap_or(0),
                gauge: control,
                number: control,
            };
            if piece.cells() > 0 {
                pieces.push(piece);
            }
        }
    }
    let fits = |cells: i32| cells == 0 || run_end + (GROUP_GAP + cells) * cell <= right;
    let mut dropped: Vec<String> = vec![];
    let mut more = false;
    if !fits(status_cells(&pieces, more)) {
        for p in pieces.iter_mut().filter(|p| p.number) {
            p.number = false;
            dropped.push(format!("{}.pct", p.m.name));
        }
    }
    if !fits(status_cells(&pieces, more)) {
        for p in pieces.iter_mut().filter(|p| p.gauge) {
            p.gauge = false;
            dropped.push(format!("{}.gauge", p.m.name));
        }
    }
    for name in drop_order(&pieces, &prefs.overflow) {
        if fits(status_cells(&pieces, more)) {
            break;
        }
        pieces.retain(|p| p.m.name != name);
        dropped.push(name);
        more = true;
    }
    let note = match scene.status {
        Status::Loading => Some(ELLIPSIS),
        Status::Error => Some(WARNING),
        Status::Ok => None,
    };
    let mut cells = if note.is_some() { NOTE_CELLS } else { status_cells(&pieces, more) };
    if !fits(cells) {
        pieces.clear();
        (more, cells) = (false, 0);
    }
    let start = right - cells * cell;

    // the binding mode, in the room between the run and the status
    if let Some(name) = scene.mode {
        let limit = if cells > 0 { start - GROUP_GAP * cell } else { right };
        for (i, glyph) in glyphs(&plain(name)).into_iter().enumerate() {
            let rect = Rect::new(run_end + cell + i as i32 * cell, 0, cell, h);
            if rect.right() > limit {
                break;
            }
            lay.fixed.push(Draw::Glyph {
                rect,
                text: glyph,
                tone: Tone::Attention,
                bold: false,
                fit: false,
                shift: 0.0,
            });
        }
    }

    let mut x = start;
    if let (Some(sign), true) = (note, cells > 0) {
        lay.fixed.push(Draw::Glyph {
            rect: Rect::new(x, 0, NOTE_CELLS * cell, h),
            text: sign.into(),
            tone: Tone::Dim,
            bold: false,
            fit: false,
            shift: 0.0,
        });
    }
    if more {
        let dots = What::Text {
            glyphs: vec![ELLIPSIS.into()],
            bold: false,
        };
        lay.targets.push(Target::new(
            MORE.into(),
            Rect::new(x, 0, cell, h),
            Kind::Open,
            MORE.into(),
            Tone::Dim,
            dots,
            home(),
        ));
        x += (1 + GROUP_GAP) * cell;
    }
    let mut before: Option<&Module> = None;
    for p in &pieces {
        if let Some(b) = before {
            x += gap(b, p.m) * cell;
        }
        // the hairline: in the middle of the five cells before the time's group, a tenth of a cell wide, a quarter
        // of the bar's height from its top and as far from its bottom
        if p.m.group == TIME && before.map_or(more, |b| b.group != TIME) {
            let (room, wide, top) = (GROUP_GAP * cell, ((cell + 5) / 10).max(1), (h + 2) / 4);
            lay.fixed.push(Draw::Fill {
                rect: Rect::new(x - room + (room - wide + 1) / 2, top, wide, h - 2 * top),
                tone: Tone::Dim,
            });
        }
        before = Some(p.m);
        let state = p.m.state;
        let sets = (p.m.set && scene.levels.level(&p.m.name).is_some()).then(|| p.m.name.clone());
        let part = |word: &str, rect: Rect, kind: Kind, tone: Tone, what: What| Target {
            state,
            sets: sets.clone(),
            ..Target::new(
                format!("{}.{word}", p.m.name),
                rect,
                kind,
                p.m.title(),
                tone,
                what,
                To::Shell {
                    name: p.m.name.clone(),
                    instance: word.into(),
                },
            )
        };
        let end = x + p.cells() * cell;
        // the sign and the text of a module that says toggle switch something in place; any other open something
        let switch = if p.m.toggle { Kind::Toggle } else { Kind::Open };
        // a module with no sign says its state on its text: red for what is wrong, the attention color for what asks
        let worded = if p.sign.is_empty() { state.sign() } else { state.text() };
        if !p.sign.is_empty() {
            let w = p.sign.len() as i32 * cell;
            let sign = What::Text {
                glyphs: p.sign.clone(),
                bold: false,
            };
            lay.targets.push(part("name", Rect::new(x, 0, w, h), switch, state.sign(), sign));
            x += w + PART_GAP * cell;
        }
        if p.gauge {
            if state.gauged() {
                let kind = if p.m.set { Kind::Level } else { Kind::Open };
                let gauge = What::Gauge { full: full_cells(p.level) };
                lay.targets
                    .push(part("gauge", Rect::new(x, 0, GAUGE_CELLS * cell, h), kind, state.gauge(), gauge));
            }
            x += (GAUGE_CELLS + PART_GAP) * cell;
        }
        if p.number {
            if state.numbered() {
                // as wide as it is drawn: its digits and the percent sign
                let blank = digits(p.level).iter().filter(|d| d.is_none()).count() as i32;
                let number = What::Number {
                    module: p.m.name.clone(),
                    level: p.level,
                    x,
                };
                let rect = Rect::new(x + blank * cell, 0, (DIGIT_CELLS + 1 - blank) * cell, h);
                lay.targets.push(part("pct", rect, Kind::Open, state.text(), number));
            }
            x += (DIGIT_CELLS + 1 + PART_GAP) * cell;
        }
        let text: Vec<String> = glyphs(&p.m.text).into_iter().take(p.m.cells.max(0) as usize).collect();
        if !text.is_empty() && !p.m.text.trim().is_empty() {
            let rect = Rect::new(x, 0, text.len() as i32 * cell, h);
            let text = What::Text { glyphs: text, bold: p.m.bold };
            lay.targets.push(part("text", rect, switch, worded, text));
        }
        x = end;
    }
    lay.dropped = dropped;
    lay
}

/// A click as swaybar writes it to the status program: the module and its part, the button, and where, in
/// pixels of the bar and of the part.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Click {
    pub name: String,
    pub instance: String,
    pub button: u32,
    pub x: i32,
    pub y: i32,
    pub relative_x: i32,
    pub relative_y: i32,
    pub width: i32,
    pub height: i32,
}

impl Click {
    /// The click as one JSON object, its keys in swaybar's order.
    pub fn json(&self) -> String {
        let text = |s: &str| serde_json::to_string(s).unwrap_or_else(|_| "\"\"".into());
        format!(
            "{{\"name\":{},\"instance\":{},\"button\":{},\"x\":{},\"y\":{},\"relative_x\":{},\"relative_y\":{},\"width\":{},\"height\":{}}}",
            text(&self.name),
            text(&self.instance),
            self.button,
            self.x,
            self.y,
            self.relative_x,
            self.relative_y,
            self.width,
            self.height
        )
    }
}

/// The line a click is on the status program's stdin: the opening bracket before the first, a comma
/// before every other.
pub fn click_line(click: &Click, first: bool) -> String {
    format!("{}{}\n", if first { "[\n" } else { "," }, click.json())
}

/// What a click or a key asks the surface to do.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum Act {
    /// A click for spark-shell.
    Send(Click),
    /// A command for sway.
    Sway(String),
    #[default]
    Nothing,
}

/// What a button on the bar does: what is sent, and the level it changes at once, by module.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Press {
    pub act: Act,
    pub set: Option<(String, i32)>,
}

/// A key the bar reads while it has the keyboard.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Tab,
    /// Shift+Tab.
    BackTab,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    /// Enter or Space.
    Activate,
    Escape,
}

impl Key {
    /// A keysym (X11's keysymdef.h, as libxkbcommon gives it), with Shift held or not.
    pub fn of_sym(sym: u32, shift: bool) -> Option<Key> {
        Some(match sym {
            0xff51 => Key::Left,
            0xff53 => Key::Right,
            0xff52 => Key::Up,
            0xff54 => Key::Down,
            0xff50 => Key::Home,
            0xff57 => Key::End,
            0xff0d | 0xff8d | 0x20 => Key::Activate,
            0xff1b => Key::Escape,
            0xfe20 => Key::BackTab,
            0xff09 if shift => Key::BackTab,
            0xff09 => Key::Tab,
            _ => return None,
        })
    }

    /// An evdev code read as its place on a US keyboard: when no keymap can be read.
    pub fn of_evdev(code: u32, shift: bool) -> Option<Key> {
        Some(match code {
            105 => Key::Left,
            106 => Key::Right,
            103 => Key::Up,
            108 => Key::Down,
            102 => Key::Home,
            107 => Key::End,
            28 | 96 | 57 => Key::Activate,
            1 => Key::Escape,
            15 if shift => Key::BackTab,
            15 => Key::Tab,
            _ => return None,
        })
    }
}

/// What a key does on a bar that has the keyboard.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum KeyAct {
    /// The focus moves to that target.
    Focus(usize),
    /// The target acts; `leave`: the keyboard goes back after it (what opens something takes the keys
    /// itself); a toggle keeps it.
    Do {
        press: Press,
        leave: bool,
    },
    /// The keyboard goes back.
    Leave,
    Nothing,
}

/// What a frame is drawn with: where the pointer and the keys are, the family's pair, and the numbers on
/// their way at a time in milliseconds.
pub struct View<'a> {
    pub hover: Option<usize>,
    pub focus: Option<usize>,
    /// The pair's full glyph and its light one.
    pub full: &'a str,
    pub light: &'a str,
    pub levels: &'a Levels,
    /// Whether the digits flow; when not, a number changes in place.
    pub motion: bool,
    /// Whether the look says an ink.
    pub ink: bool,
    pub at: u64,
}

impl View<'_> {
    /// The tone of what is written on the accent: the look's ink, or the ground's color when it says none.
    fn written(&self) -> Tone {
        if self.ink {
            Tone::Ink
        } else {
            Tone::Ground
        }
    }
}

impl Layout {
    /// The target under a point; none in a gap, at an edge or outside.
    pub fn hit(&self, x: f64, y: f64) -> Option<usize> {
        self.targets.iter().position(|t| t.rect.contains(x, y))
    }

    /// The target with that id.
    pub fn find(&self, id: &str) -> Option<usize> {
        self.targets.iter().position(|t| t.id == id)
    }

    /// The plate's box over a slot: as wide, and in from the bar's top and bottom by a ninth of its height.
    pub fn boxed(&self, slot: Rect) -> Rect {
        Rect::new(slot.x, self.inset, slot.w, self.height - 2 * self.inset)
    }

    /// The chip under a part the pointer is on, the plate's height: a place's own three cells, and no wider;
    /// any other part's width and half a cell at each side.
    pub fn chip(&self, t: &Target) -> Rect {
        let half = if matches!(t.what, What::Place { .. }) { 0 } else { self.cell / 2 };
        self.boxed(Rect::new(t.rect.x - half, 0, t.rect.w + 2 * half, self.height))
    }

    /// How thick the keys' line is: a fifth of a cell, 2 px of 10.
    fn stroke(&self) -> i32 {
        ((self.cell + 2) / 5).max(1)
    }

    /// The line under the part the keys are on: the last pixels inside the plate's box, as wide as the chip.
    pub fn line(&self, t: &Target) -> Rect {
        let (chip, stroke) = (self.chip(t), self.stroke());
        Rect::new(chip.x, chip.y + chip.h - stroke, chip.w, stroke)
    }

    /// The keys' line on the plate: as wide as the plate, and raised from its foot by its own thickness. It is
    /// drawn in the plate's digits' tone there, the accent on the accent could not be seen, and the strip of
    /// accent left under it makes it a line and not a shorter plate.
    pub fn plate_line(&self, plate: Rect) -> Rect {
        let (plate, stroke) = (self.boxed(plate), self.stroke());
        Rect::new(plate.x, plate.y + plate.h - 2 * stroke, plate.w, stroke)
    }

    /// A button on a target, the pointer `rx`, `ry` inside it. On a module whose level can be set, the
    /// wheel changes the level drawn by a step, on any of its parts, and the left button on its gauge sets
    /// it to the place clicked: at once, whatever the status says later.
    fn act(&self, target: usize, button: u32, rx: i32, ry: i32, levels: &Levels) -> Press {
        let Some(t) = self.targets.get(target) else { return Press::default() };
        let act = match &t.to {
            To::Sway(command) if button == 1 => Act::Sway(command.clone()),
            To::Sway(_) => Act::Nothing,
            To::Shell { name, instance } => Act::Send(Click {
                name: name.clone(),
                instance: instance.clone(),
                button,
                x: t.rect.x + rx,
                y: t.rect.y + ry,
                relative_x: rx,
                relative_y: ry,
                width: t.rect.w,
                height: t.rect.h,
            }),
        };
        let set = t.sets.as_ref().and_then(|module| {
            let now = levels.level(module)?;
            let level = match button {
                4 => now + STEP,
                5 => now - STEP,
                1 if matches!(t.what, What::Gauge { .. }) => level_at(rx, t.rect.w)?,
                _ => return None,
            };
            Some((module.clone(), level.clamp(0, 100)))
        });
        Press { act, set }
    }

    /// A pointer button (1 left, 2 middle, 3 right, 4 wheel up, 5 wheel down) at a point: a click for
    /// spark-shell on a module's part, the mark or the three dots; a workspace shown on the left button.
    pub fn press(&self, x: f64, y: f64, button: u32, levels: &Levels) -> Press {
        let Some(i) = self.hit(x, y) else { return Press::default() };
        let r = self.targets[i].rect;
        self.act(i, button, x.floor() as i32 - r.x, y.floor() as i32 - r.y, levels)
    }

    /// A key with the focus on a target. Tab and Shift+Tab go round the targets, left to right, and Left
    /// and Right do too, on every part. Up and Down are the wheel's step up and down on any part of a
    /// module whose level can be set, and the keys stay; elsewhere they do nothing. Home and End set a
    /// level to its ends on its gauge; Enter or Space is the left button at the part's center, and nothing
    /// on such a gauge. After it the keyboard goes back, except on a toggle, to be switched again.
    pub fn key(&self, focus: usize, k: Key, levels: &Levels) -> KeyAct {
        let n = self.targets.len();
        if n == 0 {
            return if k == Key::Escape { KeyAct::Leave } else { KeyAct::Nothing };
        }
        let focus = focus.min(n - 1);
        let t = &self.targets[focus];
        let level = t.kind == Kind::Level;
        let (cx, cy) = (t.rect.w / 2, t.rect.h / 2);
        let stay = |press| KeyAct::Do { press, leave: false };
        match k {
            Key::Escape => KeyAct::Leave,
            Key::Tab | Key::Right => KeyAct::Focus((focus + 1) % n),
            Key::BackTab | Key::Left => KeyAct::Focus((focus + n - 1) % n),
            Key::Up if t.sets.is_some() => stay(self.act(focus, 4, cx, cy, levels)),
            Key::Down if t.sets.is_some() => stay(self.act(focus, 5, cx, cy, levels)),
            Key::Up | Key::Down => KeyAct::Nothing,
            Key::Home if level => stay(self.act(focus, 1, 0, cy, levels)),
            Key::End if level => stay(self.act(focus, 1, t.rect.w, cy, levels)),
            Key::Home | Key::End => KeyAct::Nothing,
            Key::Activate if level => KeyAct::Nothing,
            Key::Activate => KeyAct::Do {
                press: self.act(focus, 1, cx, cy, levels),
                leave: t.kind != Kind::Toggle,
            },
        }
    }

    /// What a target shows, in its own tone, on its chip too; but a dim part on its chip is raised
    /// halfway to the text's color. A gauge's cells keep their tones there.
    fn show(&self, t: &Target, chip: bool, v: &View, out: &mut Vec<Draw>) {
        let (cell, h) = (self.cell, self.height);
        let tone = if chip && t.tone == Tone::Dim { Tone::Raised } else { t.tone };
        let glyph = |rect: Rect, text: &str, tone: Tone, bold: bool, fit: bool, shift: f64| Draw::Glyph {
            rect,
            text: text.to_string(),
            tone,
            bold,
            fit,
            shift,
        };
        let slot = |i: i32| Rect::new(t.rect.x + i * cell, 0, cell, h);
        match &t.what {
            What::Mark(square) => out.push(Draw::Mark { rect: *square }),
            What::Place { full } => {
                for i in 0..PLACE_CELLS {
                    out.push(glyph(slot(i), if *full { v.full } else { v.light }, tone, false, true, 0.0));
                }
            }
            What::Plate(label) => {
                out.push(Draw::Fill {
                    rect: self.boxed(t.rect),
                    tone: Tone::Accent,
                });
                out.push(glyph(t.rect, label, v.written(), true, false, 0.0));
            }
            What::Text { glyphs, bold } => {
                for (i, g) in glyphs.iter().enumerate() {
                    out.push(glyph(slot(i as i32), g, tone, *bold, false, 0.0));
                }
            }
            What::Gauge { full } => {
                for i in 0..GAUGE_CELLS {
                    let (pair, tone) = if i < *full { (v.full, t.tone) } else { (v.light, Tone::Dim) };
                    out.push(glyph(slot(i), pair, tone, false, true, 0.0));
                }
            }
            What::Number { module, level, x } => {
                // a digit's cell is as tall as the plate: one on its way is cut there, on a chip too
                let digit = |i: i32| self.boxed(Rect::new(x + i * cell, 0, cell, h));
                let flow = v.levels.flow(module, v.at).filter(|f| v.motion && f.to == *level);
                let cells = flow.map_or_else(|| rolls(*level, *level, 1.0), |f| rolls(f.from, f.to, f.part));
                for (i, rolling) in cells.iter().enumerate() {
                    for roll in rolling {
                        out.push(glyph(digit(i as i32), &roll.digit.to_string(), tone, false, false, roll.shift));
                    }
                }
                out.push(glyph(digit(DIGIT_CELLS), "%", tone, false, false, 0.0));
            }
        }
    }

    /// A frame: everything the bar draws over its ground, in order. What stands whatever happens, then
    /// each target in its tone; the part under the pointer last, on a chip of the lit tone (the plate does
    /// not change); and over all, the line under the part the keys are on, in the accent, or on the plate
    /// in the plate's digits' tone and its own thickness higher.
    pub fn frame(&self, v: &View) -> Vec<Draw> {
        let mut out = self.fixed.clone();
        let hover = v.hover.filter(|i| self.targets.get(*i).is_some_and(|t| !matches!(t.what, What::Plate(_))));
        for (i, t) in self.targets.iter().enumerate() {
            if hover != Some(i) {
                self.show(t, false, v, &mut out);
            }
        }
        if let Some(t) = hover.map(|i| &self.targets[i]) {
            out.push(Draw::Fill {
                rect: self.chip(t),
                tone: Tone::Lit,
            });
            self.show(t, true, v, &mut out);
        }
        if let Some(t) = v.focus.and_then(|i| self.targets.get(i)) {
            out.push(match t.what {
                What::Plate(_) => Draw::Fill {
                    rect: self.plate_line(t.rect),
                    tone: v.written(),
                },
                _ => Draw::Fill {
                    rect: self.line(t),
                    tone: Tone::Accent,
                },
            });
        }
        out
    }

    /// Whether a frame drawn with this view shows a number on its way: the surface asks for the next frame
    /// while one does, and for none after. Only a number that is on this bar moves: a level that is not
    /// pinned, or whose number was given up for width or is not drawn muted or missing, changes without a
    /// frame of its own, and so does every number when the look says motion no.
    pub fn moving(&self, v: &View) -> bool {
        v.motion
            && self.targets.iter().any(|t| match &t.what {
                What::Number { module, level, .. } => v.levels.flow(module, v.at).is_some_and(|f| f.to == *level),
                _ => false,
            })
    }
}

/// What the pointer does off the bar while a bar has the keys.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Off {
    /// It came off the bar at a point, or the keys were taken with it there.
    Came(f64, f64),
    /// It moved to a point.
    Moved(f64, f64),
    /// A button went down.
    Pressed,
    /// It left: onto the bar, or onto another screen.
    Left,
}

/// The pointer off the bar while a bar has the keys: where its travel is counted from.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Astray {
    from: Option<(f64, f64)>,
}

impl Astray {
    /// Whether the keys go back, as on Escape: at a button, or once the pointer is more than TRAVEL_CELLS
    /// cells from where it came off the bar. A hand that rests on the mouse moves it less, and keeps them.
    pub fn back(&mut self, what: Off, cell: i32) -> bool {
        match what {
            Off::Pressed => true,
            Off::Came(x, y) => {
                self.from = Some((x, y));
                false
            }
            Off::Left => {
                self.from = None;
                false
            }
            Off::Moved(x, y) => {
                let (fx, fy) = *self.from.get_or_insert((x, y));
                (x - fx).hypot(y - fy) > (TRAVEL_CELLS * cell.max(1)) as f64
            }
        }
    }
}

/// One output's bar as it stands, for the state file: its layout, its scale, and the targets the keys
/// and the pointer are on.
pub struct Shown<'a> {
    pub output: &'a str,
    pub scale: i32,
    pub layout: &'a Layout,
    pub focus: Option<usize>,
    pub hover: Option<usize>,
}

/// A field of the state file: no tab and no line end inside.
fn field(s: &str) -> String {
    s.replace(['\t', '\n', '\r'], " ")
}

/// The state file's text: the status, sway's binding mode while one is on, each level as it is drawn,
/// each output that rests, then each output that has a bar with its targets and what it left out.
pub fn state_text(status: Status, mode: Option<&str>, levels: &Levels, resting: &[&str], bars: &[Shown]) -> String {
    let mut out = format!("bar\t1\nstatus\t{}\n", status.word());
    if let Some(name) = mode {
        out += &format!("mode\t{}\n", field(name));
    }
    for (module, level) in levels.each() {
        out += &format!("level\t{}\t{level}\n", field(module));
    }
    for output in resting {
        out += &format!("rest\t{}\n", field(output));
    }
    for b in bars {
        let (l, name) = (b.layout, field(b.output));
        out += &format!("output\t{name}\t{}\t{}\t{}\t{}\n", l.width, l.height, l.edge.word(), b.scale);
        for (i, t) in l.targets.iter().enumerate() {
            let flags: Vec<&str> = [
                (b.focus == Some(i), "focused"),
                (b.hover == Some(i), "hover"),
                (t.selected, "selected"),
                (t.urgent, "urgent"),
                (t.visible, "visible"),
                (t.empty, "empty"),
            ]
            .iter()
            .filter(|f| f.0)
            .map(|f| f.1)
            .collect();
            out += &format!(
                "target\t{name}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                field(&t.id),
                t.rect.x,
                t.rect.y,
                t.rect.w,
                t.rect.h,
                t.kind.word(),
                t.state.word(),
                if flags.is_empty() { "-".to_string() } else { flags.join(",") },
                field(&t.name)
            );
        }
        for d in &l.dropped {
            out += &format!("dropped\t{name}\t{}\n", field(d));
        }
    }
    out
}

/// The seconds before spark-shell's status is started again after it ended `failures` times in a row:
/// 1, 2, 4 and so on, 30 at most.
pub fn backoff(failures: u32) -> u64 {
    (1u64 << failures.saturating_sub(1).min(5)).min(30)
}

/// Whether a status child that has lived `seconds` is a steady one: a line of its clears the count of
/// failures. One that says a line and ends sooner is started again later each time, not every second.
pub fn steady(seconds: u64) -> bool {
    seconds >= 10
}

/// The sizes spark's mark comes drawn at, as PNGs in the assets.
pub const MARK_PNGS: [i32; 4] = [16, 19, 22, 26];

/// Whether a ground is dark, spark-shell's rule (theme_is_dark): its luminance under half, in whole numbers.
pub fn dark_ground(r: u8, g: u8, b: u8) -> bool {
    (r as u32 * 299 + g as u32 * 587 + b as u32 * 114) / 1000 < 128
}

/// Spark's mark at `px` pixels on a ground: its file in the assets, favicon for a dark ground and
/// favicon-light for a light one, never recolored. The PNG nearest the size at or above it; above the
/// largest, the SVG, drawn at the size.
pub fn mark_file(dark: bool, px: i32) -> String {
    let stem = if dark { "favicon" } else { "favicon-light" };
    match MARK_PNGS.iter().find(|&&n| n >= px) {
        Some(n) => format!("{stem}-{n}.png"),
        None => format!("{stem}.svg"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The sizes at 16 px text with a cell of 10: 36 high, a mark of 24.
    const M: Metrics = Metrics {
        cell: 10,
        height: 36,
        mark: 24,
    };

    /// The star family's pair.
    const FULL: &str = "\u{2501}";
    const LIGHT: &str = "\u{2500}";

    /// The sheet's line: the wire, bluetooth and wifi; the speaker pinned at 55 and the microphone; the
    /// brightness and the keyboard's layout; the time, bold, and the flag. 57 cells.
    const SHEET: &str = r#"[{"name":"look","fg":"ebdbb2","accent":"fe8019","muted":"928374","ground":"282828","lit":"3c3836","attention":"fabd2f","alert":"fb4934","alpha":"0.95","full":"\u2501","light":"\u2500","motion":"yes"},
        {"name":"lan","group":"connections","sign":"\u21c5","text":"","cells":0,"bold":false,"state":"ok","set":false,"pinned":false,"label":"wired network"},
        {"name":"bt","group":"connections","sign":"\u2726","text":"","cells":0,"bold":false,"state":"ok","set":false,"pinned":false,"label":"bluetooth on"},
        {"name":"wifi","group":"connections","sign":"\u25e0","text":"","cells":0,"bold":false,"state":"ok","level":70,"set":false,"pinned":false,"label":"wifi home 70%"},
        {"name":"out","group":"sound","sign":"\u25c0","text":"","cells":0,"bold":false,"state":"ok","level":55,"set":true,"pinned":true,"label":"output 55%"},
        {"name":"mic","group":"sound","sign":"\u25c9","text":"","cells":0,"bold":false,"state":"ok","level":40,"set":true,"pinned":false,"label":"microphone 40%"},
        {"name":"light","group":"seat","sign":"\u263c","text":"","cells":0,"bold":false,"state":"ok","level":80,"set":true,"pinned":false,"label":"brightness 80%"},
        {"name":"kb","group":"seat","sign":"\u2317","text":"us","cells":2,"bold":false,"state":"ok","set":false,"pinned":false,"label":"keyboard us"},
        {"name":"clock","group":"time","sign":"","text":"13:29","cells":5,"bold":true,"state":"ok","set":false,"pinned":false,"label":"13:29"},
        {"name":"notifications","group":"time","sign":"\u2691","text":"","cells":0,"bold":false,"state":"ok","set":false,"pinned":false,"label":"no notifications"}],"#;

    /// The speaker pinned at 55, the time and the flag: 26 cells.
    const SHORT: &str = r#"[{"name":"out","group":"sound","sign":"\u25c0","state":"ok","level":55,"set":true,"pinned":true,"label":"output 55%"},
        {"name":"clock","group":"time","text":"13:29","cells":5,"bold":true,"label":"13:29"},
        {"name":"notifications","group":"time","sign":"\u2691","state":"asks","label":"2 notifications"}]"#;

    fn mods(line: &str) -> Vec<Module> {
        parse_line(line).expect("a line")
    }

    /// The levels a line says, as the first line's are: none on its way.
    fn levels_of(modules: &[Module]) -> Levels {
        let mut levels = Levels::default();
        levels.said(modules, 0);
        levels
    }

    fn ws(num: i32, name: &str, output: &str, visible: bool, focused: bool, urgent: bool) -> Workspace {
        Workspace {
            num: (num >= 0).then_some(num),
            name: name.into(),
            output: output.into(),
            visible,
            focused,
            urgent,
        }
    }

    /// The sheet's workspaces: 1, 2, 3, 4 and 7 exist; A shows 2, with the focus, and B shows 4.
    fn five() -> Vec<Workspace> {
        vec![
            ws(1, "1", "A", false, false, false),
            ws(2, "2", "A", true, true, false),
            ws(3, "3", "A", false, false, false),
            ws(4, "4", "B", true, false, false),
            ws(7, "7", "A", false, false, false),
        ]
    }

    #[allow(clippy::too_many_arguments)]
    fn lay_on(
        output: &str,
        width: i32,
        edge: Edge,
        status: Status,
        modules: &[Module],
        levels: &Levels,
        workspaces: &[Workspace],
        mode: Option<&str>,
        prefs: &Prefs,
    ) -> Layout {
        let scene = Scene {
            output,
            width,
            edge,
            status,
            modules,
            levels,
            workspaces,
            mode,
            rest: "",
        };
        layout(&scene, prefs, &M)
    }

    fn lay_with(width: i32, status: Status, modules: &[Module], workspaces: &[Workspace], prefs: &Prefs) -> Layout {
        lay_on("A", width, Edge::Top, status, modules, &levels_of(modules), workspaces, None, prefs)
    }

    fn lay(width: i32, modules: &[Module], workspaces: &[Workspace]) -> Layout {
        lay_with(width, Status::Ok, modules, workspaces, &Prefs::default())
    }

    fn sheet(width: i32) -> Layout {
        lay(width, &mods(SHEET), &five())
    }

    /// The 1200 bar on A laid out with the levels as they are drawn now, as the surface lays it out after a change.
    fn laid(modules: &[Module], levels: &Levels) -> Layout {
        lay_on("A", 1200, Edge::Top, Status::Ok, modules, levels, &five(), None, &Prefs::default())
    }

    /// Whether a frame of a bar at a time is followed by another: a number on it is on its way.
    fn moves(l: &Layout, levels: &Levels, at: u64) -> bool {
        l.moving(&View { at, ..view(levels) })
    }

    /// The sheet's bar on A at another size of text.
    fn sized(m: &Metrics, width: i32, workspaces: &[Workspace], mode: Option<&str>) -> Layout {
        let modules = mods(SHEET);
        let scene = Scene {
            output: "A",
            width,
            edge: Edge::Top,
            status: Status::Ok,
            modules: &modules,
            levels: &levels_of(&modules),
            workspaces,
            mode,
            rest: "",
        };
        layout(&scene, &Prefs::default(), m)
    }

    fn target<'a>(l: &'a Layout, id: &str) -> &'a Target {
        &l.targets[l.find(id).unwrap_or_else(|| panic!("no target {id}"))]
    }

    fn rect_of(l: &Layout, id: &str) -> Rect {
        target(l, id).rect
    }

    fn ids(l: &Layout) -> Vec<&str> {
        l.targets.iter().map(|t| t.id.as_str()).collect()
    }

    /// The ids of the status's targets: every one after the mark and the workspaces.
    fn status_ids(l: &Layout) -> Vec<&str> {
        l.targets
            .iter()
            .filter(|t| !matches!(t.kind, Kind::Mark | Kind::Workspace))
            .map(|t| t.id.as_str())
            .collect()
    }

    fn send(act: Act) -> Click {
        match act {
            Act::Send(c) => c,
            other => panic!("not a click: {other:?}"),
        }
    }

    /// A frame at rest: no pointer, no keys, the star pair, the digits free to flow, no ink.
    fn view(levels: &Levels) -> View<'_> {
        View {
            hover: None,
            focus: None,
            full: FULL,
            light: LIGHT,
            levels,
            motion: true,
            ink: false,
            at: 0,
        }
    }

    /// What one target draws at rest, or on its chip.
    fn shows(l: &Layout, id: &str, chip: bool, v: &View) -> Vec<Draw> {
        let mut out = vec![];
        l.show(target(l, id), chip, v, &mut out);
        out
    }

    fn glyph(rect: Rect, text: &str, tone: Tone) -> Draw {
        Draw::Glyph {
            rect,
            text: text.into(),
            tone,
            bold: false,
            fit: false,
            shift: 0.0,
        }
    }

    /// One of the pair, as wide as its cell.
    fn pair(rect: Rect, text: &str, tone: Tone) -> Draw {
        Draw::Glyph {
            rect,
            text: text.into(),
            tone,
            bold: false,
            fit: true,
            shift: 0.0,
        }
    }

    fn fill(rect: Rect, tone: Tone) -> Draw {
        Draw::Fill { rect, tone }
    }

    /// The tones of what a target draws, in order.
    fn tones(draws: &[Draw]) -> Vec<Tone> {
        draws
            .iter()
            .filter_map(|d| match d {
                Draw::Glyph { tone, .. } | Draw::Fill { tone, .. } => Some(*tone),
                Draw::Mark { .. } => None,
            })
            .collect()
    }

    #[test]
    fn a_line_is_read_as_modules_with_their_facts() {
        let m = mods(SHEET);
        let names: Vec<&str> = m.iter().map(|m| m.name.as_str()).collect();
        assert_eq!(names, ["lan", "bt", "wifi", "out", "mic", "light", "kb", "clock", "notifications"]);
        let out = &m[3];
        assert_eq!(
            (out.group.as_str(), out.sign.as_str(), out.text.as_str(), out.cells),
            ("sound", "\u{25c0}", "", 0)
        );
        assert_eq!((out.state, out.level, out.set, out.pinned, out.bold), (State::Ok, Some(55), true, true, false));
        assert_eq!(out.label.as_deref(), Some("output 55%"));
        // a reading: a level that cannot be set; a module with no level
        assert_eq!((m[2].level, m[2].set, m[2].pinned), (Some(70), false, false));
        assert_eq!((m[6].level, m[6].text.as_str(), m[6].cells), (None, "us", 2));
        assert!(m[7].bold && m[7].sign.is_empty() && m[7].group == TIME);
        // every state by its word, and ok for any other
        for (word, state) in [
            ("ok", State::Ok),
            ("muted", State::Muted),
            ("off", State::Off),
            ("missing", State::Missing),
            ("wrong", State::Wrong),
            ("asks", State::Asks),
            ("records", State::Records),
            ("odd", State::Ok),
        ] {
            let m = mods(&format!(r#"[{{"name":"a","sign":"x","state":"{word}"}}]"#));
            assert_eq!(m[0].state, state, "{word}");
            assert!(state.word() == word || word == "odd");
        }
    }

    #[test]
    fn what_a_module_leaves_out_falls_to_its_default() {
        let m = &mods(r#"[{"name":"a"}]"#)[0];
        assert_eq!(
            *m,
            Module {
                name: "a".into(),
                ..Module::default()
            }
        );
        assert_eq!((m.state, m.level, m.cells, m.title().as_str()), (State::Ok, None, 0, "a"));
        // a text with no cells said keeps as many as it has glyphs
        assert_eq!(mods(r#"[{"name":"a","text":"13:29"}]"#)[0].cells, 5);
        assert_eq!(mods(r#"[{"name":"a","text":"13:29","cells":8}]"#)[0].cells, 8);
    }

    #[test]
    fn the_header_the_bracket_and_bad_lines_are_no_refresh() {
        assert_eq!(parse_line(r#"{"version":1,"click_events":true}"#), None);
        assert_eq!(parse_line("["), None);
        assert_eq!(parse_line(""), None);
        assert_eq!(parse_line("[{\"name\":"), None);
        assert_eq!(parse_line("not json"), None);
        // an empty refresh is one; a comma before the array is the stream's too
        assert_eq!(parse_line("[],"), Some(vec![]));
        assert_eq!(parse_line(r#",[{"name":"a","sign":"x"}]"#).unwrap().len(), 1);
    }

    #[test]
    fn bad_fields_fall_to_their_defaults_and_what_is_no_module_is_none() {
        let line = r##"[{"name":7,"sign":"x"}, 5, "text", null, [], {"sign":"x"}, {"name":"","sign":"x"},
            {"name":"a","group":3,"sign":["x"],"text":null,"cells":-3,"bold":"yes","state":7,"level":"55","set":1,"pinned":"no","label":"  ",
             "full_text":"old","instance":"old","markup":"pango","color":"#ff0000"},
            {"name":"big","text":"x","cells":100000,"level":250},
            {"name":"low","level":-4},
            {"name":"a","sign":"again"},
            {"name":"ctl\tname","sign":"a\u0000b","text":"one\ntwo","label":" said \r\n"}]"##;
        let m = mods(line);
        let names: Vec<&str> = m.iter().map(|m| m.name.as_str()).collect();
        assert_eq!(names, ["a", "big", "low", "ctlname"], "no name, no module; of two under one name, the first");
        assert_eq!(
            m[0],
            Module {
                name: "a".into(),
                ..Module::default()
            }
        );
        // the most cells a text keeps, and a level kept within 0 to 100
        assert_eq!((m[1].cells, m[1].level, m[2].level), (400, Some(100), Some(0)));
        // no control character stays in a name, a sign, a text or a label
        assert_eq!((m[3].sign.as_str(), m[3].text.as_str(), m[3].label.as_deref()), ("ab", "onetwo", Some("said")));
        let long = "x".repeat(5000);
        let m = mods(&format!(r#"[{{"name":"a","sign":"{long}","text":"{long}"}}]"#));
        assert_eq!((m[0].sign.len(), m[0].text.len(), m[0].cells), (400, 400, 400));
    }

    #[test]
    fn a_glyph_is_a_character_with_the_marks_that_join_it() {
        assert_eq!(glyphs("13:29"), ["1", "3", ":", "2", "9"]);
        assert_eq!(glyphs(WARNING).len(), 1, "the sign and its text selector");
        assert_eq!(glyphs("e\u{301}a"), ["e\u{301}", "a"]);
        assert_eq!(glyphs(""), Vec::<String>::new());
        assert_eq!(glyphs("\u{fe0e}x").len(), 2, "a mark with nothing before it stands alone");
    }

    #[test]
    fn the_sizes_follow_the_text() {
        assert_eq!(Metrics::for_text(16.0, 9.6), M);
        assert_eq!(M.inset(), 4, "a ninth of 36");
        let big = Metrics::for_text(24.0, 14.4);
        assert_eq!(
            big,
            Metrics {
                cell: 15,
                height: 54,
                mark: 36
            }
        );
        assert_eq!(big.inset(), 6);
        assert_eq!(Metrics::for_text(f64::NAN, 0.0), Metrics::for_text(16.0, 9.6));
    }

    #[test]
    fn the_left_end_is_a_cell_the_mark_a_cell_and_the_run_from_44() {
        let l = sheet(1200);
        let mark = &l.targets[0];
        assert_eq!(
            (mark.id.as_str(), mark.rect, mark.kind, mark.name.as_str()),
            ("mark", Rect::new(10, 0, 24, 36), Kind::Mark, "spark")
        );
        assert_eq!(mark.what, What::Mark(Rect::new(10, 6, 24, 24)));
        assert_eq!(rect_of(&l, "workspace:1"), Rect::new(44, 0, 30, 36));
        // the mark is never dropped and never made smaller
        for width in [0, 1, 30, 60, 200, 513, 4000] {
            assert_eq!(sheet(width).targets[0], *mark, "at {width}");
        }
    }

    #[test]
    fn the_run_is_ten_places_three_cells_each_whether_a_workspace_is_there_or_not() {
        let l = sheet(1200);
        let run: Vec<&Target> = l.targets.iter().filter(|t| t.kind == Kind::Workspace).collect();
        let want: Vec<String> = (1..=10).map(|n| format!("workspace:{n}")).collect();
        assert_eq!(run.iter().map(|t| t.id.clone()).collect::<Vec<_>>(), want);
        // three cells each from 44, none between, the plate (2) as wide as any: the run ends at 344
        let xs: Vec<(i32, i32)> = run.iter().map(|t| (t.rect.x, t.rect.w)).collect();
        let want: Vec<(i32, i32)> = (0..10).map(|i| (44 + i * 30, 30)).collect();
        assert_eq!(xs, want);
        assert!(run.iter().all(|t| (t.rect.y, t.rect.h) == (0, 36)));
        assert_eq!(run.last().unwrap().rect.right() - run[0].rect.x, 300, "thirty cells");
        // full where a workspace exists, on any output (4 is on B); light and dim where none does
        let full: Vec<bool> = run.iter().map(|t| !t.empty).collect();
        assert_eq!(full, [true, true, true, true, false, false, true, false, false, false]);
        for t in &run {
            match &t.what {
                What::Plate(label) => assert_eq!((t.id.as_str(), label.as_str(), t.tone), ("workspace:2", "02", Tone::Accent)),
                What::Place { full } => assert_eq!((*full, t.tone), (!t.empty, if t.empty { Tone::Dim } else { Tone::Text }), "{}", t.id),
                other => panic!("{other:?}"),
            }
            assert_eq!(t.name, t.id.replace(':', " "));
        }
        // with no workspace at all, and no output of that name, the ten places stand, light
        let none = lay(1200, &mods(SHEET), &[]);
        let run: Vec<&Target> = none.targets.iter().filter(|t| t.kind == Kind::Workspace).collect();
        assert_eq!(run.len(), 10);
        assert!(run.iter().all(|t| t.empty && t.what == What::Place { full: false } && t.rect.w == 30));
    }

    #[test]
    fn the_plate_is_its_place_30_by_28_and_no_place_moves_with_the_workspace_shown() {
        let places: Vec<Rect> = (0..10).map(|i| Rect::new(44 + i * 30, 0, 30, 36)).collect();
        for n in 1..=10 {
            let here = [ws(n, &n.to_string(), "A", true, true, false)];
            let l = lay_on("A", 1200, Edge::Top, Status::Ok, &[], &Levels::default(), &here, Some("r"), &Prefs::default());
            let run: Vec<&Target> = l.targets.iter().filter(|t| t.kind == Kind::Workspace).collect();
            assert_eq!(run.len(), 10);
            let plate = run[n as usize - 1];
            assert_eq!(plate.what, What::Plate(format!("{n:02}")), "two digits");
            assert_eq!(l.boxed(plate.rect), Rect::new(plate.rect.x, 4, 30, 28), "{n}");
            assert!(plate.visible && plate.selected && !plate.empty);
            // every place where it always is, the plate's too, and no room beside it
            assert_eq!(run.iter().map(|t| t.rect).collect::<Vec<_>>(), places, "{n}");
            // the run ends at 344 wherever the plate is: the mode stands one cell after it
            let Draw::Glyph { rect, .. } = &l.fixed[0] else { panic!() };
            assert_eq!(rect.x, 354, "{n}");
        }
        // nor with which workspaces exist, or ask
        let mut all = five();
        all[4].urgent = true;
        for workspaces in [vec![], five(), all] {
            let l = lay(1200, &[], &workspaces);
            let run: Vec<Rect> = l.targets.iter().filter(|t| t.kind == Kind::Workspace).map(|t| t.rect).collect();
            assert_eq!(run, places);
        }
    }

    #[test]
    fn each_output_has_its_own_plate_and_the_same_places() {
        let all = five();
        let on = |output: &str| lay_on(output, 1200, Edge::Top, Status::Ok, &[], &Levels::default(), &all, None, &Prefs::default());
        let (a, b) = (on("A"), on("B"));
        assert_eq!(ids(&a), ids(&b));
        // A shows 2 and sway's focus is there; B shows 4 without it
        let two = target(&a, "workspace:2");
        assert_eq!((two.what.clone(), two.visible, two.selected), (What::Plate("02".into()), true, true));
        let four = target(&b, "workspace:4");
        assert_eq!(
            (four.rect, four.what.clone(), four.visible, four.selected),
            (Rect::new(134, 0, 30, 36), What::Plate("04".into()), true, false)
        );
        // the other output's plate is a full place here, and no plate
        let there = target(&b, "workspace:2");
        assert_eq!(
            (there.rect, there.what.clone(), there.visible, there.selected),
            (Rect::new(74, 0, 30, 36), What::Place { full: true }, false, false)
        );
        assert_eq!(target(&a, "workspace:4").what, What::Place { full: true });
        // every place stands in the same cells on both
        for (here, there) in a.targets.iter().zip(&b.targets) {
            assert_eq!(here.rect, there.rect, "{}", here.id);
        }
    }

    #[test]
    fn an_urgent_workspace_is_its_full_glyph_in_the_attention_color() {
        let mut all = five();
        all[4].urgent = true;
        let l = lay(1200, &[], &all);
        let seven = target(&l, "workspace:7");
        assert_eq!(
            (seven.tone, seven.what.clone(), seven.urgent, seven.empty),
            (Tone::Attention, What::Place { full: true }, true, false)
        );
        let levels = Levels::default();
        assert_eq!(
            shows(&l, "workspace:7", false, &view(&levels)),
            [
                pair(Rect::new(224, 0, 10, 36), FULL, Tone::Attention),
                pair(Rect::new(234, 0, 10, 36), FULL, Tone::Attention),
                pair(Rect::new(244, 0, 10, 36), FULL, Tone::Attention)
            ]
        );
        // the plate stays the plate when the workspace shown is urgent
        all[1].urgent = true;
        let l = lay(1200, &[], &all);
        assert_eq!((target(&l, "workspace:2").tone, target(&l, "workspace:2").urgent), (Tone::Accent, true));
    }

    #[test]
    fn the_run_is_drawn_in_the_familys_pair_and_the_plate_bold_on_the_accent() {
        let l = sheet(1200);
        let levels = Levels::default();
        let v = view(&levels);
        // a place is three cells of the pair, each as wide as its cell, so the line is unbroken from place to place
        let three = |x: i32, text: &str, tone: Tone| [0, 1, 2].map(|i| pair(Rect::new(x + i * 10, 0, 10, 36), text, tone));
        assert_eq!(shows(&l, "workspace:1", false, &v), three(44, FULL, Tone::Text));
        assert_eq!(shows(&l, "workspace:5", false, &v), three(164, LIGHT, Tone::Dim));
        // the plate is its place: the accent's box, and its two bold digits in the middle of the three cells
        assert_eq!(
            shows(&l, "workspace:2", false, &v),
            [
                fill(Rect::new(74, 4, 30, 28), Tone::Accent),
                Draw::Glyph {
                    rect: Rect::new(74, 0, 30, 36),
                    text: "02".into(),
                    tone: Tone::Ground,
                    bold: true,
                    fit: false,
                    shift: 0.0
                }
            ]
        );
        // another family's pair is the look's to say
        let stone = View {
            full: "\u{25b0}",
            light: "\u{25b1}",
            ..view(&levels)
        };
        assert_eq!(shows(&l, "workspace:5", false, &stone), three(164, "\u{25b1}", Tone::Dim));
    }

    #[test]
    fn a_workspace_outside_1_to_10_gets_a_place_after_the_tenth() {
        let all = vec![
            ws(2, "2", "A", true, true, false),
            ws(11, "11", "A", false, false, false),
            ws(123, "123:web", "B", true, false, false),
            ws(-1, "mail", "A", false, false, true),
            ws(-1, "x", "A", false, false, false),
        ];
        let a = lay(1200, &[], &all);
        assert_eq!(ids(&a)[11..], ["workspace:11", "workspace:123", "workspace:mail", "workspace:x"]);
        // three cells each from 344, full, none between
        assert_eq!(rect_of(&a, "workspace:11"), Rect::new(344, 0, 30, 36));
        assert_eq!(rect_of(&a, "workspace:x"), Rect::new(434, 0, 30, 36));
        assert_eq!(
            (target(&a, "workspace:11").what.clone(), target(&a, "workspace:mail").tone),
            (What::Place { full: true }, Tone::Attention)
        );
        // on a plate: the number's last two digits, or the name's first two characters; in the same place
        let b = lay_on("B", 1200, Edge::Top, Status::Ok, &[], &Levels::default(), &all, None, &Prefs::default());
        assert_eq!(
            (rect_of(&b, "workspace:11").x, rect_of(&b, "workspace:123"), rect_of(&b, "workspace:mail").x),
            (344, Rect::new(374, 0, 30, 36), 404)
        );
        assert_eq!(rect_of(&a, "workspace:123"), rect_of(&b, "workspace:123"));
        assert_eq!(target(&b, "workspace:123").what, What::Plate("23".into()));
        assert_eq!(
            (ws(-1, "mail", "A", true, true, false).plate(), ws(-1, "x", "A", true, true, false).plate()),
            ("ma".into(), "x".into())
        );
        assert_eq!(
            (
                ws(5, "5", "A", true, true, false).plate(),
                ws(10, "10", "A", true, true, false).plate(),
                ws(0, "0", "A", true, true, false).plate()
            ),
            ("05".into(), "10".into(), "00".into())
        );
        assert_eq!(ws(3, "3:web", "A", true, true, false).plate(), "03");
    }

    #[test]
    fn a_click_on_a_place_goes_to_its_workspace_even_where_none_exists() {
        let mut all = five();
        all.push(ws(11, "11", "A", false, false, false));
        all.push(ws(-1, "mail \"box\"", "A", false, false, false));
        let l = lay(1200, &mods(SHEET), &all);
        let levels = Levels::default();
        let press = |x: f64, button: u32| l.press(x, 10.0, button, &levels);
        assert_eq!(press(50.0, 1).act, Act::Sway("workspace number 1".into()));
        assert_eq!(press(170.0, 1).act, Act::Sway("workspace number 5".into()), "no workspace 5 yet: as Super+5");
        assert_eq!(press(80.0, 1).act, Act::Sway("workspace number 2".into()), "the plate");
        assert_eq!(press(350.0, 1).act, Act::Sway("workspace number 11".into()));
        assert_eq!(press(380.0, 1).act, Act::Sway("workspace \"mail box\"".into()));
        // the left button alone, and no level is set by it
        for button in [2, 3, 4, 5] {
            assert_eq!(press(50.0, button), Press::default());
        }
        assert_eq!(press(50.0, 1).set, None);
        // no room beside the plate: the pixel before it is the first place's, and the one after it the third's
        assert_eq!((l.hit(73.9, 10.0), l.hit(74.0, 10.0), l.hit(104.0, 10.0)), (Some(1), Some(2), Some(3)));
        assert_eq!(target(&l, "workspace:mail \"box\"").name, "workspace mail \"box\"");
    }

    #[test]
    fn the_status_stands_two_cells_from_the_right_edge_in_gaps_of_1_3_and_5_cells() {
        let l = sheet(1200);
        assert_eq!(
            status_ids(&l),
            [
                "lan.name",
                "bt.name",
                "wifi.name",
                "out.name",
                "out.gauge",
                "out.pct",
                "mic.name",
                "light.name",
                "kb.name",
                "kb.text",
                "clock.text",
                "notifications.name"
            ]
        );
        let at = |id: &str| (rect_of(&l, id).x, rect_of(&l, id).right());
        // the sheet's 1200 bar: the flag two cells from the edge, the time three cells before it
        assert_eq!(at("notifications.name"), (1170, 1180));
        assert_eq!(at("clock.text"), (1090, 1140));
        // five cells between groups; one cell between the keyboard's sign and its text
        assert_eq!((at("kb.name"), at("kb.text")), ((1000, 1010), (1020, 1040)));
        // three cells between the modules of a group
        assert_eq!(at("light.name"), (960, 970));
        assert_eq!(at("mic.name"), (900, 910));
        // the speaker: its sign, a cell, five cells of gauge, a cell, and four cells of number, the 55% at their right
        assert_eq!((at("out.name"), at("out.gauge"), at("out.pct")), ((750, 760), (770, 820), (840, 870)));
        assert_eq!(
            target(&l, "out.pct").what,
            What::Number {
                module: "out".into(),
                level: 55,
                x: 830
            }
        );
        assert_eq!((at("lan.name"), at("bt.name"), at("wifi.name")), ((610, 620), (650, 660), (690, 700)));
        assert!(l.targets.iter().all(|t| (t.rect.y, t.rect.h) == (0, 36)));
        assert!(l.dropped.is_empty());
        // the wide bar keeps the same places from its own right edge
        let wide = sheet(1920);
        assert_eq!(
            (
                rect_of(&wide, "notifications.name").x,
                rect_of(&wide, "clock.text").x,
                rect_of(&wide, "lan.name").x
            ),
            (1890, 1810, 1330)
        );
    }

    #[test]
    fn a_level_has_its_gauge_and_number_only_when_it_is_pinned() {
        let l = sheet(1200);
        // the microphone, the brightness and wifi have levels and are not pinned: the sign alone
        for name in ["mic", "light", "wifi"] {
            assert_eq!((l.find(&format!("{name}.gauge")), l.find(&format!("{name}.pct"))), (None, None), "{name}");
        }
        // pinned without a level: nothing to draw a gauge from
        let m = mods(r#"[{"name":"kb","group":"seat","sign":"\u2317","text":"us","cells":2,"pinned":true}]"#);
        assert_eq!(status_ids(&lay(1200, &m, &[])), ["kb.name", "kb.text"]);
        // a reading pinned: its gauge is no level to set
        let m = mods(r#"[{"name":"wifi","group":"connections","sign":"\u25e0","level":70,"set":false,"pinned":true}]"#);
        let l = lay(1200, &m, &[]);
        assert_eq!(status_ids(&l), ["wifi.name", "wifi.gauge", "wifi.pct"]);
        assert_eq!(
            (target(&l, "wifi.gauge").kind, target(&l, "wifi.gauge").what.clone()),
            (Kind::Open, What::Gauge { full: 4 })
        );
        assert_eq!(target(&sheet(1200), "out.gauge").kind, Kind::Level);
    }

    #[test]
    fn a_gauge_is_the_level_in_five_cells_rounded_and_never_empty_above_zero() {
        let cells: Vec<i32> = [0, 1, 9, 10, 29, 30, 49, 50, 55, 69, 70, 89, 90, 100].iter().map(|l| full_cells(*l)).collect();
        assert_eq!(cells, [0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5]);
        assert_eq!((full_cells(-5), full_cells(400)), (0, 5));
        // drawn in the pair: the full cells in the text's color, the light ones dim, each as wide as its cell
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let cell = |i: i32| Rect::new(770 + i * 10, 0, 10, 36);
        assert_eq!(
            shows(&l, "out.gauge", false, &view(&levels)),
            [
                pair(cell(0), FULL, Tone::Text),
                pair(cell(1), FULL, Tone::Text),
                pair(cell(2), FULL, Tone::Text),
                pair(cell(3), LIGHT, Tone::Dim),
                pair(cell(4), LIGHT, Tone::Dim)
            ]
        );
    }

    #[test]
    fn a_number_is_three_digit_cells_at_the_right_and_a_percent_sign() {
        assert_eq!(digits(5), [None, None, Some('5')]);
        assert_eq!(digits(55), [None, Some('5'), Some('5')]);
        assert_eq!(digits(100), [Some('1'), Some('0'), Some('0')]);
        assert_eq!(digits(0), [None, None, Some('0')]);
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        // each digit in its own cell, as tall as the plate; the four cells start at 830
        let cell = |i: i32| Rect::new(830 + i * 10, 4, 10, 28);
        assert_eq!(
            shows(&l, "out.pct", false, &view(&levels)),
            [
                glyph(cell(1), "5", Tone::Text),
                glyph(cell(2), "5", Tone::Text),
                glyph(cell(3), "%", Tone::Text)
            ]
        );
        // the target is as wide as what is drawn: 100% takes the four cells, 5% two
        for (level, rect) in [
            (100, Rect::new(830, 0, 40, 36)),
            (55, Rect::new(840, 0, 30, 36)),
            (5, Rect::new(850, 0, 20, 36)),
            (0, Rect::new(850, 0, 20, 36)),
        ] {
            let m = mods(&SHEET.replace(r#""level":55"#, &format!(r#""level":{level}"#)));
            let l = lay(1200, &m, &five());
            assert_eq!(rect_of(&l, "out.pct"), rect, "{level}");
            // and nothing else moves with it
            for t in sheet(1200).targets.iter().filter(|t| t.id != "out.pct") {
                assert_eq!(rect_of(&l, &t.id), t.rect, "{} at {level}", t.id);
            }
        }
    }

    #[test]
    fn a_text_is_drawn_a_glyph_a_cell_and_the_time_alone_is_bold() {
        let l = sheet(1200);
        let levels = Levels::default();
        let v = view(&levels);
        assert_eq!(
            shows(&l, "kb.text", false, &v),
            [
                glyph(Rect::new(1020, 0, 10, 36), "u", Tone::Text),
                glyph(Rect::new(1030, 0, 10, 36), "s", Tone::Text)
            ]
        );
        assert_eq!(shows(&l, "kb.name", false, &v), [glyph(Rect::new(1000, 0, 10, 36), "\u{2317}", Tone::Text)]);
        let time = shows(&l, "clock.text", false, &v);
        assert_eq!(time.len(), 5);
        for (i, d) in time.iter().enumerate() {
            let Draw::Glyph { rect, text, bold, tone, .. } = d else { panic!() };
            assert_eq!(
                (*rect, text.as_str(), *bold, *tone),
                (Rect::new(1090 + i as i32 * 10, 0, 10, 36), &"13:29"[i..=i], true, Tone::Text)
            );
        }
        // nothing else on the bar is bold but the plate's number
        let bold = l.frame(&v).iter().filter(|d| matches!(d, Draw::Glyph { bold: true, .. })).count();
        assert_eq!(bold, 6);
        // a sign that is a word keeps a cell a letter
        let m = mods(r#"[{"name":"out","group":"sound","sign":"vol","level":55,"set":true,"pinned":true}]"#);
        let l = lay(1200, &m, &[]);
        assert_eq!((rect_of(&l, "out.name"), rect_of(&l, "out.gauge").x), (Rect::new(1040, 0, 30, 36), 1080));
    }

    #[test]
    fn a_text_keeps_its_cells_whatever_it_says() {
        let line = |text: &str| mods(&SHEET.replace(r#""text":"13:29""#, &format!(r#""text":"{text}""#)));
        let before = sheet(1200);
        // a shorter text is drawn from the left of its cells, and moves nothing else
        let after = lay(1200, &line("9:05"), &five());
        assert_eq!(rect_of(&after, "clock.text"), Rect::new(1090, 0, 40, 36));
        for t in before.targets.iter().filter(|t| t.id != "clock.text") {
            assert_eq!(rect_of(&after, &t.id), t.rect, "{}", t.id);
        }
        // a longer one is cut at its cells
        let long = lay(1200, &line("13:29:59"), &five());
        assert_eq!(
            (rect_of(&long, "clock.text"), rect_of(&long, "notifications.name")),
            (Rect::new(1090, 0, 50, 36), Rect::new(1170, 0, 10, 36))
        );
        // no text, or blanks: its cells stay and nothing is there to reach
        for text in ["", "     "] {
            let none = lay(1200, &line(text), &five());
            assert_eq!(none.find("clock.text"), None, "{text:?}");
            assert_eq!(rect_of(&none, "kb.text"), rect_of(&before, "kb.text"));
        }
        // the notifications' count: two cells kept beside the flag, empty until something waits
        let m = mods(r#"[{"name":"notifications","group":"time","sign":"\u2691","text":"","cells":2}]"#);
        let l = lay(1200, &m, &[]);
        assert_eq!(
            (status_ids(&l), rect_of(&l, "notifications.name")),
            (vec!["notifications.name"], Rect::new(1140, 0, 10, 36))
        );
        let m = mods(r#"[{"name":"notifications","group":"time","sign":"\u2691","text":"9+","cells":2}]"#);
        let l = lay(1200, &m, &[]);
        assert_eq!(
            (rect_of(&l, "notifications.name"), rect_of(&l, "notifications.text")),
            (Rect::new(1140, 0, 10, 36), Rect::new(1160, 0, 20, 36))
        );
    }

    #[test]
    fn a_module_with_nothing_to_show_takes_no_room_and_logo_is_none() {
        let line = SHEET.replacen(
            r#"{"name":"lan""#,
            r#"{"name":"none","group":"connections","sign":"","text":"","cells":0},{"name":"logo","group":"windows","sign":"S"},{"name":"lan""#,
            1,
        );
        let (with, without) = (lay(1200, &mods(&line), &five()), sheet(1200));
        assert_eq!(with, without);
        // a module appearing at the left moves nothing at its right
        let line = SHEET.replacen(r#"{"name":"lan""#, r#"{"name":"pad","group":"windows","sign":"\u229f"},{"name":"lan""#, 1);
        let with = lay(1200, &mods(&line), &five());
        assert_eq!(rect_of(&with, "pad.name"), Rect::new(550, 0, 10, 36), "five cells before the connections");
        for t in &without.targets {
            assert_eq!(rect_of(&with, &t.id), t.rect, "{}", t.id);
        }
    }

    #[test]
    fn a_hairline_stands_in_the_middle_of_the_five_cells_before_the_time() {
        // the sheet: the keyboard's text ends at 1040, the time starts at 1090, the line at 1065 from 9 to 27
        let l = sheet(1200);
        assert_eq!(l.fixed, [fill(Rect::new(1065, 9, 1, 18), Tone::Dim)]);
        // it follows the time, not the width
        assert_eq!(sheet(1920).fixed, [fill(Rect::new(1785, 9, 1, 18), Tone::Dim)]);
        // with nothing left of the time there is no line; with the three dots there is
        let alone = mods(r#"[{"name":"clock","group":"time","text":"13:29","cells":5,"bold":true},{"name":"notifications","group":"time","sign":"\u2691"}]"#);
        assert_eq!(lay(1200, &alone, &five()).fixed, []);
        let l = sheet(570);
        assert_eq!(status_ids(&l), ["more", "clock.text", "notifications.name"]);
        assert_eq!((rect_of(&l, MORE), rect_of(&l, "clock.text").x), (Rect::new(400, 0, 10, 36), 460));
        assert_eq!(l.fixed, [fill(Rect::new(435, 9, 1, 18), Tone::Dim)]);
        // a group named time anywhere on the line has its line before its first module, once
        let m = mods(
            r#"[{"name":"a","group":"g","sign":"a"},{"name":"t","group":"time","sign":"t"},{"name":"u","group":"time","sign":"u"},{"name":"b","group":"h","sign":"b"}]"#,
        );
        let l = lay(1200, &m, &[]);
        assert_eq!(l.fixed, [fill(Rect::new(rect_of(&l, "t.name").x - 25, 9, 1, 18), Tone::Dim)]);
    }

    /// The speaker pinned at 55 with a text, in a state.
    fn in_state(state: &str) -> (Layout, Levels) {
        let m = mods(&format!(
            r#"[{{"name":"out","group":"sound","sign":"\u25c0","text":"hd","cells":2,"state":"{state}","level":55,"set":true,"pinned":true}}]"#
        ));
        (lay(1200, &m, &[]), levels_of(&m))
    }

    #[test]
    fn each_part_takes_its_tone_from_the_modules_state() {
        use Tone::{Alert, Attention, Dim, Text};
        // the sign, a gauge's full cells (its light ones are always dim), the number, the text
        let want = [
            ("ok", Text, Some(Text), Some(Text), Text),
            ("muted", Dim, Some(Dim), None, Text),
            ("off", Dim, Some(Dim), Some(Dim), Dim),
            ("missing", Dim, None, None, Dim),
            ("wrong", Alert, Some(Text), Some(Text), Text),
            ("records", Alert, Some(Text), Some(Text), Text),
            ("asks", Attention, Some(Text), Some(Text), Text),
        ];
        for (state, sign, gauge, number, text) in want {
            let (l, levels) = in_state(state);
            let v = view(&levels);
            assert_eq!(tones(&shows(&l, "out.name", false, &v)), [sign], "{state}: the sign");
            assert_eq!(tones(&shows(&l, "out.text", false, &v)), [text, text], "{state}: the text");
            match gauge {
                // the level stays in a muted gauge: three cells are still the full glyph
                Some(full) => {
                    let cells = shows(&l, "out.gauge", false, &v);
                    assert_eq!(tones(&cells), [full, full, full, Dim, Dim], "{state}: the gauge");
                    let said: Vec<&str> = cells
                        .iter()
                        .map(|d| if let Draw::Glyph { text, .. } = d { text.as_str() } else { "" })
                        .collect();
                    assert_eq!(said, [FULL, FULL, FULL, LIGHT, LIGHT], "{state}");
                }
                None => assert_eq!(l.find("out.gauge"), None, "{state}: the gauge's cells stay empty"),
            }
            match number {
                Some(tone) => assert_eq!(tones(&shows(&l, "out.pct", false, &v)), [tone, tone, tone], "{state}: the number"),
                None => assert_eq!(l.find("out.pct"), None, "{state}: the number is not drawn"),
            }
            // its cells stay whatever is drawn in them: nothing moves between states
            assert_eq!(
                (rect_of(&l, "out.name"), rect_of(&l, "out.text")),
                (Rect::new(1030, 0, 10, 36), Rect::new(1160, 0, 20, 36)),
                "{state}"
            );
            // every part says the module's state
            assert!(
                l.targets.iter().filter(|t| t.id.starts_with("out.")).all(|t| t.state.word() == state),
                "{state}"
            );
        }
        // the accent is the plate's and the keys' line's alone: no part of a module ever takes it
        for (state, ..) in want {
            let (l, levels) = in_state(state);
            assert!(!tones(&l.frame(&view(&levels))).contains(&Tone::Accent), "{state}");
        }
    }

    #[test]
    fn a_module_with_no_sign_says_its_state_on_its_text() {
        use Tone::{Alert, Attention, Dim, Text};
        // the battery is its number as text and no sign: low, it must not read as well
        for (state, tone) in [
            ("ok", Text),
            ("muted", Dim),
            ("off", Dim),
            ("missing", Dim),
            ("wrong", Alert),
            ("records", Alert),
            ("asks", Attention),
        ] {
            let m = mods(&format!(
                r#"[{{"name":"bat","group":"seat","sign":"","text":"9%","cells":4,"state":"{state}"}}]"#
            ));
            let l = lay(1200, &m, &[]);
            let levels = Levels::default();
            assert_eq!(status_ids(&l), ["bat.text"], "{state}");
            assert_eq!(target(&l, "bat.text").tone, tone, "{state}");
            assert_eq!(
                shows(&l, "bat.text", false, &view(&levels)),
                [glyph(Rect::new(1140, 0, 10, 36), "9", tone), glyph(Rect::new(1150, 0, 10, 36), "%", tone)],
                "{state}"
            );
            // and on its chip under the pointer it keeps that tone, the dim one raised
            let v = View {
                hover: l.find("bat.text"),
                ..view(&levels)
            };
            let on_chip = if tone == Dim { Tone::Raised } else { tone };
            let f = l.frame(&v);
            assert_eq!(
                f[f.len() - 3..],
                [
                    fill(Rect::new(1135, 4, 30, 28), Tone::Lit),
                    glyph(Rect::new(1140, 0, 10, 36), "9", on_chip),
                    glyph(Rect::new(1150, 0, 10, 36), "%", on_chip)
                ],
                "{state}"
            );
        }
        // beside a sign the text keeps the text's color: the sign says the state
        for (state, sign) in [("wrong", Alert), ("asks", Attention), ("records", Alert)] {
            let m = mods(&format!(
                r#"[{{"name":"bat","group":"seat","sign":"\u25ae","text":"9%","cells":4,"state":"{state}"}}]"#
            ));
            let l = lay(1200, &m, &[]);
            assert_eq!((target(&l, "bat.name").tone, target(&l, "bat.text").tone), (sign, Text), "{state}");
        }
        // a number is no text: with no sign and a pinned level it keeps the number's tone
        let m = mods(r#"[{"name":"x","group":"g","sign":"","text":"t","cells":1,"state":"wrong","level":50,"pinned":true}]"#);
        let l = lay(1200, &m, &[]);
        assert_eq!(
            (target(&l, "x.pct").tone, target(&l, "x.gauge").tone, target(&l, "x.text").tone),
            (Text, Text, Alert)
        );
        // the time has no sign and is well: the text's color, as it was
        assert_eq!(target(&sheet(1200), "clock.text").tone, Text);
    }

    /// 12 px text with a cell of 8: 27 high, a mark of 18.
    const M8: Metrics = Metrics { cell: 8, height: 27, mark: 18 };

    /// 24 px text with a cell of 15, an odd number of pixels: 54 high, a mark of 36.
    const M15: Metrics = Metrics {
        cell: 15,
        height: 54,
        mark: 36,
    };

    /// The plate's rect on a bar.
    fn plate_of(l: &Layout) -> Rect {
        l.targets.iter().find(|t| matches!(t.what, What::Plate(_))).expect("a plate").rect
    }

    #[test]
    fn at_12_px_text_everything_stands_in_cells_of_8_on_a_bar_of_27() {
        assert_eq!((Metrics::for_text(12.0, 7.2), M8.inset()), (M8, 3));
        let l = sized(&M8, 1000, &five(), Some("resize"));
        assert_eq!((l.height, l.targets.iter().all(|t| (t.rect.y, t.rect.h) == (0, 27))), (27, true));
        // a cell, the mark in the bar's middle, a cell
        assert_eq!(
            (l.targets[0].rect, l.targets[0].what.clone()),
            (Rect::new(8, 0, 18, 27), What::Mark(Rect::new(8, 4, 18, 18)))
        );
        // the run from 34: places of 24, the plate one of them, thirty cells in all
        assert_eq!(
            (rect_of(&l, "workspace:1"), plate_of(&l), rect_of(&l, "workspace:3")),
            (Rect::new(34, 0, 24, 27), Rect::new(58, 0, 24, 27), Rect::new(82, 0, 24, 27))
        );
        assert_eq!((rect_of(&l, "workspace:10").right(), rect_of(&l, "workspace:10").right() - 34), (274, 30 * 8));
        // the plate's box: a ninth of the height in from the top and the bottom
        assert_eq!(l.boxed(plate_of(&l)), Rect::new(58, 3, 24, 21));
        // the status two cells from the edge, in gaps of 1, 3 and 5 cells
        let at = |id: &str| rect_of(&l, id);
        assert_eq!(
            (at("notifications.name"), at("clock.text")),
            (Rect::new(976, 0, 8, 27), Rect::new(912, 0, 40, 27))
        );
        assert_eq!(
            (at("kb.text"), at("kb.name"), at("light.name").x, at("mic.name").x),
            (Rect::new(856, 0, 16, 27), Rect::new(840, 0, 8, 27), 808, 760)
        );
        assert_eq!(
            (at("out.pct"), at("out.gauge"), at("out.name")),
            (Rect::new(712, 0, 24, 27), Rect::new(656, 0, 40, 27), Rect::new(640, 0, 8, 27))
        );
        assert_eq!((at("wifi.name").x, at("bt.name").x, at("lan.name").x), (592, 560, 528));
        // the hairline: 20 px into the 40 before the time, one pixel wide, as far from the top as from the bottom
        let hairline = fill(Rect::new(892, 7, 1, 13), Tone::Dim);
        assert_eq!(l.fixed.last(), Some(&hairline));
        assert_eq!((7, 27 - 7 - 13), (7, 7));
        // the mode one cell after the run, a glyph a cell
        assert_eq!(l.fixed[0], glyph(Rect::new(282, 0, 8, 27), "r", Tone::Attention));
        // a chip: half a cell at each side, the plate's height; the keys' line the last two pixels inside it
        let bt = target(&l, "bt.name");
        assert_eq!((l.chip(bt), l.line(bt)), (Rect::new(556, 3, 16, 21), Rect::new(556, 22, 16, 2)));
        assert_eq!(
            (l.chip(target(&l, "out.gauge")), l.chip(target(&l, "mark"))),
            (Rect::new(652, 3, 48, 21), Rect::new(4, 3, 26, 21))
        );
        // a place's chip is its own three cells, and its line as wide
        let three = target(&l, "workspace:3");
        assert_eq!((l.chip(three), l.line(three)), (Rect::new(82, 3, 24, 21), Rect::new(82, 22, 24, 2)));
        assert_eq!(l.plate_line(plate_of(&l)), Rect::new(58, 20, 24, 2), "two pixels of the accent under it");
        // a digit's cell is as tall as the plate
        let levels = levels_of(&mods(SHEET));
        assert_eq!(shows(&l, "out.pct", false, &view(&levels))[0], glyph(Rect::new(712, 3, 8, 21), "5", Tone::Text));
        // the run 274, five cells, the status's 57 and the edge's two: 786 fits whole, and 785 gives up the number
        assert!(sized(&M8, 786, &five(), None).dropped.is_empty());
        assert_eq!(sized(&M8, 785, &five(), None).dropped, ["out.pct"]);
    }

    #[test]
    fn at_a_cell_of_an_odd_number_of_pixels_the_places_are_whole_cells_too() {
        assert_eq!((Metrics::for_text(24.0, 14.4), M15.inset()), (M15, 6));
        let l = sized(&M15, 2000, &five(), None);
        // places of 45, the plate one of them
        assert_eq!(
            (rect_of(&l, "workspace:1"), plate_of(&l), rect_of(&l, "workspace:3")),
            (Rect::new(66, 0, 45, 54), Rect::new(111, 0, 45, 54), Rect::new(156, 0, 45, 54))
        );
        assert_eq!(l.boxed(plate_of(&l)), Rect::new(111, 6, 45, 42));
        // the run is thirty cells, to the pixel, wherever the plate is
        for n in 1..=10 {
            let here = [ws(n, &n.to_string(), "A", true, true, false)];
            let l = sized(&M15, 2000, &here, Some("r"));
            let run: Vec<Rect> = l.targets.iter().filter(|t| t.kind == Kind::Workspace).map(|t| t.rect).collect();
            let want: Vec<Rect> = (0..10).map(|i| Rect::new(66 + i * 45, 0, 45, 54)).collect();
            assert_eq!(run, want, "{n}");
            let Draw::Glyph { rect, .. } = &l.fixed[0] else { panic!() };
            assert_eq!(rect.x, 66 + 30 * 15 + 15, "{n}: the mode one cell after the run");
        }
        // the status: whole cells from two cells before the edge
        let at = |id: &str| rect_of(&l, id);
        assert_eq!(
            (at("notifications.name"), at("clock.text"), at("lan.name").x),
            (Rect::new(1955, 0, 15, 54), Rect::new(1835, 0, 75, 54), 1115)
        );
        // the hairline: a tenth of a cell wide, in the middle of the 75 before the time, 14 from the top and from the bottom
        assert_eq!(l.fixed, [fill(Rect::new(1797, 14, 2, 26), Tone::Dim)]);
        assert_eq!((1797 - (1835 - 75), 1835 - 1799), (37, 36));
        // a chip: 7 at each side, where half a cell is 7 and a pixel is left over; the keys' line a fifth of a
        // cell thick, the last pixels inside the plate's box
        let flag = target(&l, "notifications.name");
        assert_eq!((l.chip(flag), l.line(flag)), (Rect::new(1948, 6, 29, 42), Rect::new(1948, 45, 29, 3)));
        assert_eq!(l.plate_line(plate_of(&l)), Rect::new(111, 42, 45, 3), "three pixels of the accent under it");
        // the chips of two parts a cell apart do not meet, at any size, and a place's chip ends with its cells
        for (m, width) in [(&M8, 1000), (&M, 1200), (&M15, 2000)] {
            let l = sized(m, width, &five(), None);
            let (sign, gauge) = (l.chip(target(&l, "out.name")), l.chip(target(&l, "out.gauge")));
            assert!(sign.right() <= gauge.x, "{sign:?} {gauge:?}");
            let place = target(&l, "workspace:3");
            assert_eq!(l.chip(place), l.boxed(place.rect));
        }
    }

    #[test]
    fn at_any_size_and_width_nothing_lies_over_another_and_the_look_keeps_its_shape() {
        let sizes = [
            (8.0, 4.8),
            (9.0, 5.4),
            (10.0, 6.0),
            (11.0, 6.6),
            (12.0, 7.2),
            (13.0, 7.8),
            (14.67, 8.8),
            (16.0, 9.6),
            (17.33, 10.4),
            (18.67, 11.2),
            (24.0, 14.4),
            (32.0, 19.2),
            (40.0, 24.0),
        ];
        for (px, zero) in sizes {
            let m = Metrics::for_text(px, zero);
            let (cell, h, half) = (m.cell, m.height, m.cell / 2);
            for width in (0..=3200).step_by(37).chain([cell * 80, cell * 120]) {
                let l = sized(&m, width, &five(), Some("resize"));
                let mut rects: Vec<Rect> = l.targets.iter().map(|t| t.rect).collect();
                rects.extend(l.fixed.iter().map(|d| match d {
                    Draw::Fill { rect, .. } | Draw::Mark { rect } | Draw::Glyph { rect, .. } => *rect,
                }));
                rects.sort_by_key(|r| r.x);
                for r in &rects {
                    assert!(r.w > 0 && r.h > 0 && r.x >= 0 && r.y >= 0 && r.y + r.h <= h, "{r:?} at {px} px, {width}");
                }
                for pair in rects.windows(2) {
                    assert!(!over(&pair[0], &pair[1]), "{:?} over {:?} at {px} px, {width}", pair[0], pair[1]);
                }
            }
            // on a bar wide enough for all of it: the plate in its place, its box, the hairline and the line, by the same rules
            let l = sized(&m, cell * 120, &five(), None);
            assert!(l.dropped.is_empty(), "{px} px");
            let plate = plate_of(&l);
            assert_eq!(
                (
                    plate.x - rect_of(&l, "workspace:1").right(),
                    rect_of(&l, "workspace:3").x - plate.right(),
                    plate.w
                ),
                (0, 0, 3 * cell),
                "{px} px"
            );
            assert_eq!(rect_of(&l, "workspace:10").right() - rect_of(&l, "workspace:1").x, 30 * cell, "{px} px");
            let boxed = l.boxed(plate);
            assert_eq!(
                (boxed.y, boxed.y + boxed.h),
                (m.inset(), h - m.inset()),
                "{px} px: as far from the top as from the bottom"
            );
            assert!((boxed.y * 9 - h).abs() <= 4, "{px} px: a ninth of the height");
            let [Draw::Fill { rect: line, .. }] = &l.fixed[..] else {
                panic!("{px} px: {:?}", l.fixed)
            };
            let (before, after) = (line.x - rect_of(&l, "kb.text").right(), rect_of(&l, "clock.text").x - line.right());
            assert!(
                before + line.w + after == 5 * cell && (before - after).abs() <= 1,
                "{px} px: {before} {} {after}",
                line.w
            );
            assert_eq!(line.y, h - line.y - line.h, "{px} px: the hairline as far from the top as from the bottom");
            assert!(
                (line.y * 4 - h).abs() <= 2 && line.w >= 1 && (line.w * 10 - cell).abs() <= 5,
                "{px} px: {line:?}"
            );
            let part = target(&l, "bt.name");
            let (chip, under) = (l.chip(part), l.line(part));
            assert_eq!(
                (chip.x, chip.right(), chip.y, chip.h),
                (part.rect.x - half, part.rect.right() + half, boxed.y, boxed.h),
                "{px} px"
            );
            assert_eq!((under.x, under.w, under.y + under.h), (chip.x, chip.w, chip.y + chip.h), "{px} px");
            assert!(under.h >= 1 && (under.h * 5 - cell).abs() <= 2 && under.h < chip.h, "{px} px: {under:?}");
            let on_plate = l.plate_line(plate);
            assert_eq!(
                (on_plate.x, on_plate.w, on_plate.h, on_plate.y + 2 * on_plate.h),
                (boxed.x, boxed.w, under.h, boxed.y + boxed.h),
                "{px} px"
            );
            assert!(on_plate.y > boxed.y, "{px} px: inside the plate");
        }
    }

    #[test]
    fn under_the_pointer_a_part_stands_on_a_lit_chip_in_its_own_tone() {
        use Tone::{Alert, Attention, Dim, Lit, Raised, Text};
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let rest = l.frame(&view(&levels));
        let over = |id: &str| {
            let v = View {
                hover: l.find(id),
                ..view(&levels)
            };
            l.frame(&v)
        };
        // the chip: the part's width and half a cell at each side, the plate's height
        assert_eq!(l.chip(target(&l, "bt.name")), Rect::new(645, 4, 20, 28));
        // a sign: the chip in the lit tone and the glyph in its own, as at rest; drawn last, over what is beside it
        let f = over("bt.name");
        assert_eq!(
            f[f.len() - 2..],
            [fill(Rect::new(645, 4, 20, 28), Lit), glyph(Rect::new(650, 0, 10, 36), "\u{2726}", Text)]
        );
        assert_eq!(f.len(), rest.len() + 1, "one chip, and each part lights alone");
        // a gauge: its cells keep their tones, the full ones the text's and the light ones dim
        let f = over("out.gauge");
        assert_eq!(f[f.len() - 6], fill(Rect::new(765, 4, 60, 28), Lit));
        assert_eq!(f[f.len() - 5..], shows(&l, "out.gauge", false, &view(&levels))[..]);
        assert_eq!(tones(&f[f.len() - 5..]), [Text, Text, Text, Dim, Dim]);
        // a number: as wide as the digits drawn and the percent sign
        let f = over("out.pct");
        assert_eq!(f[f.len() - 4], fill(Rect::new(835, 4, 40, 28), Lit));
        assert_eq!(tones(&f[f.len() - 3..]), [Text; 3]);
        // a text: the time stays bold on its chip
        let f = over("clock.text");
        assert_eq!(f[f.len() - 6], fill(Rect::new(1085, 4, 60, 28), Lit));
        assert!(f[f.len() - 5..].iter().all(|d| matches!(d, Draw::Glyph { tone: Text, bold: true, .. })));
        // a place: its chip is its own three cells in the plate's box, and no wider; a workspace's glyphs as at rest
        let f = over("workspace:7");
        assert_eq!(f[f.len() - 4], fill(Rect::new(224, 4, 30, 28), Lit));
        assert_eq!(f[f.len() - 3..], shows(&l, "workspace:7", false, &view(&levels))[..]);
        assert_eq!(tones(&f[f.len() - 3..]), [Text; 3]);
        // an empty place is dim: on its chip the dim tone is raised halfway to the text's
        let f = over("workspace:5");
        assert_eq!(f[f.len() - 4], fill(Rect::new(164, 4, 30, 28), Lit));
        assert_eq!(f[f.len() - 3..], [0, 1, 2].map(|i| pair(Rect::new(164 + i * 10, 0, 10, 36), LIGHT, Raised)));
        // the chips of the places beside the plate end where its box begins and begin where it ends
        assert_eq!((l.chip(target(&l, "workspace:1")).right(), l.chip(target(&l, "workspace:3")).x), (74, 104));
        // the plate does not change
        assert_eq!(over("workspace:2"), rest);
        // the mark is a picture: a chip in the lit tone behind it
        let f = over("mark");
        assert_eq!(
            f[f.len() - 2..],
            [
                fill(Rect::new(5, 4, 34, 28), Lit),
                Draw::Mark {
                    rect: Rect::new(10, 6, 24, 24)
                }
            ]
        );
        // a sign keeps its tone on its chip whatever it is: red for what is wrong, the attention color for what asks;
        // a dim one, muted, off or missing, is raised
        for (state, tone) in [
            ("ok", Text),
            ("wrong", Alert),
            ("records", Alert),
            ("asks", Attention),
            ("muted", Raised),
            ("off", Raised),
            ("missing", Raised),
        ] {
            let (l, levels) = in_state(state);
            let v = View {
                hover: l.find("out.name"),
                ..view(&levels)
            };
            let f = l.frame(&v);
            assert_eq!(
                f[f.len() - 2..],
                [fill(Rect::new(1025, 4, 20, 28), Lit), glyph(Rect::new(1030, 0, 10, 36), "\u{25c0}", tone)],
                "{state}"
            );
        }
        // off: the number and the text are dim, and raised on their chips; the gauge's cells keep the dim tone
        let (off, off_levels) = in_state("off");
        let on = |id: &str| {
            let v = View {
                hover: off.find(id),
                ..view(&off_levels)
            };
            tones(&off.frame(&v))
        };
        assert_eq!(on("out.pct")[on("out.pct").len() - 4..], [Lit, Raised, Raised, Raised]);
        assert_eq!(on("out.text")[on("out.text").len() - 3..], [Lit, Raised, Raised]);
        assert_eq!(on("out.gauge")[on("out.gauge").len() - 6..], [Lit, Dim, Dim, Dim, Dim, Dim]);
        // an urgent workspace keeps the attention color on its chip, and the three dots, dim, are raised
        let mut all = five();
        all[4].urgent = true;
        let l = lay(1200, &[], &all);
        let v = View {
            hover: l.find("workspace:7"),
            ..view(&levels)
        };
        let f = l.frame(&v);
        assert_eq!(tones(&f[f.len() - 4..]), [Lit, Attention, Attention, Attention]);
        let l = sheet(570);
        let v = View {
            hover: l.find(MORE),
            ..view(&levels)
        };
        let f = l.frame(&v);
        assert_eq!(
            f[f.len() - 2..],
            [fill(Rect::new(395, 4, 20, 28), Lit), glyph(Rect::new(400, 0, 10, 36), ELLIPSIS, Raised)]
        );
        // nothing is drawn in the ground's color on a chip, and the lit and the raised tones are a chip's alone
        let l = sheet(1200);
        assert!(!tones(&rest).iter().any(|t| matches!(t, Lit | Raised)));
        for i in 0..l.targets.len() {
            let v = View {
                hover: Some(i),
                ..view(&levels)
            };
            let f = l.frame(&v);
            let plate = matches!(l.targets[i].what, What::Plate(_));
            assert_eq!(tones(&f).iter().filter(|t| **t == Lit).count(), usize::from(!plate), "{}", l.targets[i].id);
            assert_eq!(tones(&f).iter().filter(|t| **t == Tone::Ground).count(), 1, "the plate's digits alone");
        }
        // no pointer, or one past the last target: no chip
        let v = View {
            hover: Some(999),
            ..view(&levels)
        };
        assert_eq!(sheet(1200).frame(&v), rest);
    }

    #[test]
    fn the_keys_line_is_two_pixels_of_accent_at_the_plates_foot() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        // the last two pixels inside the plate's box, as wide as the chip: the part and half a cell at each side,
        // a place's own three cells
        assert_eq!(l.line(target(&l, "bt.name")), Rect::new(645, 30, 20, 2));
        let rest = l.frame(&view(&levels));
        for (id, line) in [
            ("bt.name", Rect::new(645, 30, 20, 2)),
            ("out.name", Rect::new(745, 30, 20, 2)),
            ("out.gauge", Rect::new(765, 30, 60, 2)),
            ("out.pct", Rect::new(835, 30, 40, 2)),
            ("clock.text", Rect::new(1085, 30, 60, 2)),
            ("workspace:7", Rect::new(224, 30, 30, 2)),
            ("workspace:5", Rect::new(164, 30, 30, 2)),
            ("mark", Rect::new(5, 30, 34, 2)),
        ] {
            let v = View {
                focus: l.find(id),
                ..view(&levels)
            };
            let f = l.frame(&v);
            // over everything, and nothing else changes
            assert_eq!((f.last(), &f[..f.len() - 1]), (Some(&fill(line, Tone::Accent)), &rest[..]), "{id}");
        }
        // the keys on the gauge, the pointer on its number: the chip, then the line
        let v = View {
            focus: l.find("out.gauge"),
            hover: l.find("out.pct"),
            ..view(&levels)
        };
        let f = l.frame(&v);
        assert_eq!(f.last(), Some(&fill(Rect::new(765, 30, 60, 2), Tone::Accent)));
        assert!(f.contains(&fill(Rect::new(835, 4, 40, 28), Tone::Lit)));
        // the accent is on the plate and the line and nowhere else
        let accents: Vec<&Draw> = f.iter().filter(|d| tones(std::slice::from_ref(d)) == [Tone::Accent]).collect();
        assert_eq!(
            accents,
            [&fill(Rect::new(74, 4, 30, 28), Tone::Accent), &fill(Rect::new(765, 30, 60, 2), Tone::Accent)]
        );
    }

    #[test]
    fn on_the_plate_the_keys_line_is_the_grounds_color() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let rest = l.frame(&view(&levels));
        // the accent on the accent could not be seen: two pixels as wide as the plate, in the ground's color, raised
        // by their own thickness so that two pixels of the accent show under them
        let line = l.plate_line(Rect::new(74, 0, 30, 36));
        assert_eq!(line, Rect::new(74, 28, 30, 2));
        assert_eq!(
            (line.y + line.h, l.boxed(Rect::new(74, 0, 30, 36)).y + 28),
            (30, 32),
            "the plate's foot is two pixels lower"
        );
        // every other part's line stays at the plate's foot, two pixels lower
        assert_eq!(l.line(target(&l, "workspace:3")).y, 30);
        let v = View {
            focus: l.find("workspace:2"),
            ..view(&levels)
        };
        let f = l.frame(&v);
        assert_eq!((f.last(), &f[..f.len() - 1]), (Some(&fill(Rect::new(74, 28, 30, 2), Tone::Ground)), &rest[..]));
        // it lies inside the plate's fill, which is drawn before it, and the plate's own accent is the only one
        let plate = fill(Rect::new(74, 4, 30, 28), Tone::Accent);
        assert!(f.iter().position(|d| *d == plate).unwrap() < f.len() - 1);
        assert_eq!(f.iter().filter(|d| tones(std::slice::from_ref(*d)) == [Tone::Accent]).count(), 1);
        // the plate wherever it is, and on a workspace past the tenth
        let all = [ws(123, "123", "A", true, true, false)];
        let l = lay(1200, &[], &all);
        let v = View {
            focus: l.find("workspace:123"),
            ..view(&levels)
        };
        assert_eq!(l.frame(&v).last(), Some(&fill(Rect::new(344, 28, 30, 2), Tone::Ground)));
        // every other target keeps the accent: no other line is the ground's color
        let l = sheet(1200);
        for i in (0..l.targets.len()).filter(|i| l.targets[*i].id != "workspace:2") {
            let v = View {
                focus: Some(i),
                ..view(&levels)
            };
            assert!(matches!(l.frame(&v).last(), Some(Draw::Fill { tone: Tone::Accent, .. })), "{}", l.targets[i].id);
        }
    }

    #[test]
    fn with_an_ink_the_plates_digits_and_its_keys_line_are_the_ink() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let inked = View { ink: true, ..view(&levels) };
        // the digits on the plate: the ink when the look says one, the ground's color when it says none
        let digits = |tone: Tone| Draw::Glyph {
            rect: Rect::new(74, 0, 30, 36),
            text: "02".into(),
            tone,
            bold: true,
            fit: false,
            shift: 0.0,
        };
        let plate = fill(Rect::new(74, 4, 30, 28), Tone::Accent);
        assert_eq!(shows(&l, "workspace:2", false, &inked), [plate.clone(), digits(Tone::Ink)]);
        assert_eq!(shows(&l, "workspace:2", false, &view(&levels)), [plate, digits(Tone::Ground)]);
        // the keys' line on the plate too, where it was
        let keyed = |ink: bool| {
            l.frame(&View {
                focus: l.find("workspace:2"),
                ink,
                ..view(&levels)
            })
        };
        assert_eq!(keyed(true).last(), Some(&fill(Rect::new(74, 28, 30, 2), Tone::Ink)));
        assert_eq!(keyed(false).last(), Some(&fill(Rect::new(74, 28, 30, 2), Tone::Ground)));
        // those two alone: with an ink nothing is drawn in the ground's color, without one nothing in the ink,
        // and no other tone changes
        let (with, without) = (tones(&keyed(true)), tones(&keyed(false)));
        assert_eq!(with.iter().filter(|t| **t == Tone::Ink).count(), 2);
        assert!(!with.contains(&Tone::Ground) && !without.contains(&Tone::Ink));
        let grounded: Vec<Tone> = with.iter().map(|t| if *t == Tone::Ink { Tone::Ground } else { *t }).collect();
        assert_eq!(grounded, without);
        // any other part's line is the accent, with an ink too
        let v = View {
            focus: l.find("workspace:3"),
            ..inked
        };
        assert_eq!(l.frame(&v).last(), Some(&fill(Rect::new(104, 30, 30, 2), Tone::Accent)));
    }

    #[test]
    fn short_of_width_the_numbers_go_then_the_gauges_then_whole_modules() {
        // the run ends at 344, five cells of room, the status's 570 and the edge's 20: 984 fits whole
        assert!(sheet(984).dropped.is_empty());
        // one pixel less: every pinned control gives up its number, and nothing else
        let l = sheet(983);
        assert_eq!(l.dropped, ["out.pct"]);
        assert_eq!((l.find("out.pct"), l.find(MORE)), (None, None));
        assert_eq!(
            (rect_of(&l, "out.gauge").right(), rect_of(&l, "mic.name").x),
            (653, 683),
            "three cells to the next module"
        );
        assert_eq!(sheet(934).dropped, ["out.pct"]);
        // then its gauge: the sign alone stays
        let l = sheet(933);
        assert_eq!(l.dropped, ["out.pct", "out.gauge"]);
        assert_eq!(
            (l.find("out.gauge"), rect_of(&l, "out.name").right(), rect_of(&l, "mic.name").x),
            (None, 603, 633)
        );
        assert_eq!(sheet(874).dropped, ["out.pct", "out.gauge"]);
        // then modules, from the left: the dots' cell and its gap take the room of the first, so the second goes with it
        let l = sheet(873);
        assert_eq!(l.dropped, ["out.pct", "out.gauge", "lan", "bt"]);
        assert_eq!(status_ids(&l)[..2], ["more", "wifi.name"]);
        assert_eq!(sheet(854).dropped.len(), 4);
        assert_eq!(sheet(853).dropped[4..], ["wifi"]);
        assert_eq!(sheet(793).dropped[4..], ["wifi", "out"]);
        assert_eq!(sheet(753).dropped[4..], ["wifi", "out", "mic"]);
        assert_eq!(sheet(693).dropped[4..], ["wifi", "out", "mic", "light"]);
        // the time's group stays, and the run: nothing of either is ever named
        let l = sheet(653);
        assert_eq!(l.dropped, ["out.pct", "out.gauge", "lan", "bt", "wifi", "out", "mic", "light", "kb"]);
        assert_eq!(status_ids(&l), ["more", "clock.text", "notifications.name"]);
        assert_eq!(sheet(564).targets, {
            let mut same = l.targets.clone();
            for t in same.iter_mut().filter(|t| t.kind == Kind::Open) {
                t.rect.x -= 653 - 564;
            }
            same
        });
        // a bar with no room even for the time shows the mark and the run alone
        let l = sheet(563);
        assert_eq!(status_ids(&l), Vec::<&str>::new());
        assert_eq!(l.targets.len(), 11);
        assert!(l.fixed.is_empty());
        // every pinned control gives up its number at once, in the line's order, and then every gauge
        let two = mods(&SHEET.replace(r#""level":40,"set":true,"pinned":false"#, r#""level":40,"set":true,"pinned":true"#));
        // the microphone's gauge and number are 11 cells more: 1094 fits whole
        assert!(lay(1094, &two, &five()).dropped.is_empty());
        assert_eq!(lay(1093, &two, &five()).dropped, ["out.pct", "mic.pct"]);
        assert_eq!(lay(993, &two, &five()).dropped, ["out.pct", "mic.pct", "out.gauge", "mic.gauge"]);
    }

    #[test]
    fn three_dots_stand_for_the_modules_left_out_and_open_home() {
        let l = sheet(873);
        // the status is 44 cells from 413: the dots' cell, five cells, then wifi
        let more = target(&l, MORE);
        assert_eq!(
            (more.rect, more.kind, more.name.as_str(), more.tone),
            (Rect::new(413, 0, 10, 36), Kind::Open, "more", Tone::Dim)
        );
        assert_eq!(rect_of(&l, "wifi.name").x, 473);
        let levels = Levels::default();
        assert_eq!(shows(&l, MORE, false, &view(&levels)), [glyph(Rect::new(413, 0, 10, 36), ELLIPSIS, Tone::Dim)]);
        // a click on them is a click on logo, as one on the mark is
        let c = send(l.press(415.0, 5.0, 1, &levels).act);
        assert_eq!((c.name.as_str(), c.instance.as_str(), c.relative_x, c.width), ("logo", "", 2, 10));
        let c = send(l.press(20.0, 10.0, 1, &levels).act);
        assert_eq!((c.name.as_str(), c.instance.as_str(), c.button, c.relative_x, c.width), ("logo", "", 1, 10, 24));
        // a number or a gauge given up is no module left out: no dots
        assert_eq!(sheet(933).find(MORE), None);
    }

    #[test]
    fn the_overflow_order_names_what_leaves_last_and_the_rest_leave_first() {
        let prefs = Prefs::new("kb  out clock", 0, "");
        let at = |width: i32| lay_with(width, Status::Ok, &mods(SHEET), &five(), &prefs).dropped;
        // lan, bt, wifi, mic and light are not named: they leave first, from the left
        assert_eq!(at(793)[2..], ["lan", "bt", "wifi", "mic"]);
        assert_eq!(at(753)[2..], ["lan", "bt", "wifi", "mic", "light"]);
        // then the named ones in BAR_OVERFLOW's order; the time's group stays though it is named
        assert_eq!(at(713)[2..], ["lan", "bt", "wifi", "mic", "light", "kb"]);
        assert_eq!(at(623)[2..], ["lan", "bt", "wifi", "mic", "light", "kb", "out"]);
        assert_eq!(at(564).len(), 9);
        let l = lay_with(564, Status::Ok, &mods(SHEET), &five(), &prefs);
        assert_eq!(status_ids(&l), ["more", "clock.text", "notifications.name"]);
        assert_eq!(Prefs::new("", 0, "").overflow, Vec::<String>::new());
    }

    #[test]
    fn the_trays_room_is_kept_clear_at_the_right_end() {
        let prefs = Prefs::new("", 96, "");
        let l = lay_with(1200, Status::Ok, &mods(SHEET), &five(), &prefs);
        assert_eq!(rect_of(&l, "notifications.name").right(), 1084);
        assert_eq!(rect_of(&l, "mark").x, 10);
        // on the named output alone
        assert_eq!((Prefs::new("", 96, "A").tray_on("A"), Prefs::new("", 96, "B").tray_on("A")), (96, 0));
        let other = lay_with(1200, Status::Ok, &mods(SHEET), &five(), &Prefs::new("", 96, "B"));
        assert_eq!(rect_of(&other, "notifications.name").right(), 1180);
        // the room counts against the width: what fits at 984 does not with 96 px less
        assert_eq!(lay_with(984, Status::Ok, &mods(SHEET), &five(), &prefs).dropped, ["out.pct", "out.gauge"]);
        assert_eq!(Prefs::new("", -5, "").tray_width, 0);
        // a tray wider than the bar leaves the mark and the run
        let l = lay_with(400, Status::Ok, &mods(SHEET), &five(), &Prefs::new("", 5000, ""));
        assert_eq!(l.targets.len(), 11);
    }

    #[test]
    fn the_top_and_the_bottom_lay_out_the_same() {
        let on = |edge: Edge| {
            lay_on(
                "A",
                900,
                edge,
                Status::Ok,
                &mods(SHEET),
                &levels_of(&mods(SHEET)),
                &five(),
                Some("resize"),
                &Prefs::default(),
            )
        };
        let (top, bottom) = (on(Edge::Top), on(Edge::Bottom));
        assert_eq!((top.edge, bottom.edge), (Edge::Top, Edge::Bottom));
        assert_eq!((&top.targets, &top.fixed, &top.dropped), (&bottom.targets, &bottom.fixed, &bottom.dropped));
        // the chip and the keys' line stand in the plate's box at either edge
        let part = target(&top, "clock.text");
        assert_eq!((top.chip(part), top.line(part)), (bottom.chip(part), bottom.line(part)));
        assert_eq!(Edge::parse(Some("bottom")), Edge::Bottom);
        assert_eq!(Edge::parse(Some(" top ")), Edge::Top);
        assert_eq!(Edge::parse(Some("left")), Edge::Top);
        assert_eq!(Edge::parse(None), Edge::Top);
    }

    #[test]
    fn the_pointer_hits_parts_and_misses_gaps_and_edges() {
        let l = sheet(1200);
        let id = |x: f64, y: f64| l.hit(x, y).map(|i| l.targets[i].id.as_str());
        assert_eq!(id(9.9, 10.0), None, "the left edge");
        assert_eq!(id(10.0, 0.0), Some("mark"));
        assert_eq!(id(33.9, 35.9), Some("mark"));
        assert_eq!(id(34.0, 10.0), None, "the cell after the mark");
        assert_eq!(id(44.0, 10.0), Some("workspace:1"));
        assert_eq!(id(104.0, 0.0), Some("workspace:3"), "the bar's first row of pixels");
        assert_eq!((id(133.9, 10.0), id(134.0, 10.0)), (Some("workspace:3"), Some("workspace:4")), "places touch");
        assert_eq!(id(344.0, 10.0), None, "the free room");
        assert_eq!(id(760.0, 10.0), None, "the cell between a module's parts");
        assert_eq!(id(770.0, 10.0), Some("out.gauge"));
        assert_eq!(id(830.0, 10.0), None, "the number's empty hundreds cell");
        assert_eq!(id(840.0, 10.0), Some("out.pct"));
        assert_eq!(id(870.0, 10.0), None, "the cells between modules");
        assert_eq!(id(1179.9, 10.0), Some("notifications.name"));
        assert_eq!(id(1180.0, 10.0), None, "the right edge");
        assert_eq!(id(800.0, 36.0), None, "under the bar");
        assert_eq!(id(800.0, -0.1), None, "over the bar");
    }

    #[test]
    fn a_click_is_sent_as_swaybar_writes_it_with_the_module_and_the_part() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let c = send(l.press(792.6, 9.2, 1, &levels).act);
        assert_eq!(
            c.json(),
            r#"{"name":"out","instance":"gauge","button":1,"x":792,"y":9,"relative_x":22,"relative_y":9,"width":50,"height":36}"#
        );
        // each part under its word: the sign is name, then gauge, pct and text
        let part = |x: f64| {
            let c = send(l.press(x, 20.0, 1, &levels).act);
            (c.name, c.instance, c.relative_x, c.width)
        };
        assert_eq!(part(755.0), ("out".into(), "name".into(), 5, 10));
        assert_eq!(part(845.0), ("out".into(), "pct".into(), 5, 30));
        assert_eq!(part(1025.0), ("kb".into(), "text".into(), 5, 20));
        assert_eq!(part(1005.0), ("kb".into(), "name".into(), 5, 10));
        assert_eq!(part(1100.0), ("clock".into(), "text".into(), 10, 50));
        assert_eq!(part(1175.0), ("notifications".into(), "name".into(), 5, 10));
        // every button goes to spark-shell, the wheel too
        for button in [2, 3, 4, 5] {
            assert_eq!(send(l.press(1100.0, 20.0, button, &levels).act).button, button);
        }
        assert_eq!(l.press(880.0, 20.0, 1, &levels), Press::default(), "a gap");
        // the stream: the bracket before the first click, a comma before the others
        assert_eq!(click_line(&c, true), format!("[\n{}\n", c.json()));
        assert_eq!(click_line(&c, false), format!(",{}\n", c.json()));
        // a name is written as JSON writes it
        let odd = Click { name: "a\"b".into(), ..c };
        assert!(odd.json().starts_with(r#"{"name":"a\"b","instance":"gauge""#));
    }

    #[test]
    fn the_wheel_on_any_part_of_a_level_that_can_be_set_changes_it_at_once() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let wheel = |x: f64, button: u32| l.press(x, 20.0, button, &levels);
        // the speaker at 55: five a step on its sign, its gauge and its number, and the click still goes out
        for (x, part) in [(755.0, "name"), (790.0, "gauge"), (850.0, "pct")] {
            let up = wheel(x, 4);
            assert_eq!(up.set, Some(("out".into(), 60)), "{part}");
            let c = send(up.act);
            assert_eq!((c.name.as_str(), c.instance.as_str(), c.button), ("out", part, 4));
            assert_eq!(wheel(x, 5).set, Some(("out".into(), 50)), "{part}");
        }
        // a level that is not pinned is set by its sign: the microphone at 40
        assert_eq!(wheel(905.0, 4).set, Some(("mic".into(), 45)));
        assert_eq!(wheel(965.0, 5).set, Some(("light".into(), 75)));
        // a reading (wifi) and a module with no level are sent the wheel and nothing is set
        for x in [695.0, 1005.0, 1100.0, 20.0] {
            assert_eq!((wheel(x, 4).set, wheel(x, 5).set), (None, None), "at {x}");
            assert_eq!(send(wheel(x, 4).act).button, 4);
        }
        // no other button sets a level from a sign or a number
        for button in [1, 2, 3] {
            assert_eq!((wheel(755.0, button).set, wheel(850.0, button).set), (None, None));
        }
        // the ends hold
        let mut full = levels.clone();
        full.set("out", 100, 0);
        assert_eq!(l.press(755.0, 20.0, 4, &full).set, Some(("out".into(), 100)));
        full.set("out", 2, 0);
        assert_eq!(l.press(755.0, 20.0, 5, &full).set, Some(("out".into(), 0)));
        // the step is from the level drawn, not the one the line said
        full.set("out", 70, 0);
        assert_eq!(l.press(755.0, 20.0, 4, &full).set, Some(("out".into(), 75)));
    }

    #[test]
    fn a_click_on_a_gauge_sets_the_level_the_shell_sets_for_that_place() {
        // spark-shell's own reckoning (src/bar.sh, bar_click): whole numbers, each division dropping its remainder
        let shell = |x: i32, w: i32| {
            let hundredths = x * 100 / w;
            let fives = (hundredths + 2) / 5;
            (fives * 5).clamp(0, 100)
        };
        // a gauge of five cells at cells of 7, 8, 9, 10, 16 and 20 px: every place along each
        for w in [35, 40, 45, 50, 80, 100] {
            let all: Vec<i32> = (0..=w).map(|x| level_at(x, w).unwrap()).collect();
            for (x, level) in all.iter().enumerate() {
                assert_eq!(*level, shell(x as i32, w), "{x} of {w}");
                assert!(level % 5 == 0 && (0..=100).contains(level), "{x} of {w}: {level}");
            }
            assert_eq!((all[0], all[w as usize]), (0, 100), "the ends of {w}");
            assert!(
                all.windows(2).all(|p| p[0] <= p[1] && p[1] - p[0] <= 5),
                "{w}: never back, never past a step: {all:?}"
            );
        }
        // worked by hand, at each width
        let at = |w: i32, xs: &[i32]| xs.iter().map(|x| level_at(*x, w).unwrap()).collect::<Vec<_>>();
        assert_eq!(at(35, &[1, 2, 17, 18, 19, 34]), [0, 5, 50, 50, 55, 95]);
        assert_eq!(at(40, &[1, 2, 20, 39]), [0, 5, 50, 95]);
        assert_eq!(at(45, &[1, 2, 22, 23, 24, 44]), [0, 5, 50, 50, 55, 95]);
        assert_eq!(
            at(50, &[0, 1, 2, 3, 11, 12, 13, 25, 37, 38, 47, 48, 49, 50]),
            [0, 0, 5, 5, 20, 25, 25, 50, 75, 75, 95, 95, 100, 100]
        );
        assert_eq!(at(80, &[1, 2, 3, 40, 78, 79]), [0, 0, 5, 50, 95, 100]);
        assert_eq!(at(100, &[2, 3, 50, 97, 98]), [0, 5, 50, 95, 100]);
        // past its ends it is kept within them; a gauge of no width sets nothing, as the shell sets nothing from one
        assert_eq!((level_at(-9, 50), level_at(900, 50), level_at(i32::MAX, 50)), (Some(0), Some(100), Some(100)));
        assert_eq!((level_at(3, 0), level_at(3, -5)), (None, None));
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        // the gauge stands from 770 to 820
        let p = l.press(795.5, 20.0, 1, &levels);
        assert_eq!(p.set, Some(("out".into(), 50)));
        let c = send(p.act);
        assert_eq!((c.instance.as_str(), c.button, c.relative_x, c.width), ("gauge", 1, 25, 50));
        assert_eq!(l.press(770.0, 20.0, 1, &levels).set, Some(("out".into(), 0)));
        assert_eq!(l.press(819.0, 20.0, 1, &levels).set, Some(("out".into(), 100)));
        // the other buttons on it set nothing but the wheel's step
        assert_eq!((l.press(795.0, 20.0, 2, &levels).set, l.press(795.0, 20.0, 3, &levels).set), (None, None));
        // a reading's gauge is sent the click and sets nothing
        let m = mods(r#"[{"name":"wifi","group":"connections","sign":"\u25e0","level":70,"set":false,"pinned":true}]"#);
        let l = lay(1200, &m, &[]);
        let p = l.press(rect_of(&l, "wifi.gauge").x as f64 + 10.0, 20.0, 1, &levels_of(&m));
        assert_eq!((send(p.act).instance.as_str(), p.set), ("gauge", None));
    }

    #[test]
    fn the_hands_change_is_drawn_at_once_and_the_next_line_is_the_truth() {
        let m = mods(SHEET);
        let mut levels = levels_of(&m);
        let l = lay_on("A", 1200, Edge::Top, Status::Ok, &m, &levels, &five(), None, &Prefs::default());
        assert_eq!((levels.level("out"), levels.level("mic"), levels.level("kb")), (Some(55), Some(40), None));
        // a wheel step: the level drawn changes before the status says a word
        let (name, level) = l.press(790.0, 20.0, 4, &levels).set.unwrap();
        assert!(levels.set(&name, level, 1000));
        assert_eq!(levels.level("out"), Some(60));
        let l = lay_on("A", 1200, Edge::Top, Status::Ok, &m, &levels, &five(), None, &Prefs::default());
        assert_eq!(
            target(&l, "out.pct").what,
            What::Number {
                module: "out".into(),
                level: 60,
                x: 830
            },
            "the line still says 55"
        );
        assert_eq!(levels.flow("out", 1000), Some(Flow { from: 55, to: 60, part: 0.0 }));
        // a click at the gauge's end: 100 at once, the gauge full and the number four cells wide
        assert!(levels.set("out", 100, 2000));
        let l = lay_on("A", 1200, Edge::Top, Status::Ok, &m, &levels, &five(), None, &Prefs::default());
        assert_eq!(
            (target(&l, "out.gauge").what.clone(), rect_of(&l, "out.pct")),
            (What::Gauge { full: 5 }, Rect::new(830, 0, 40, 36))
        );
        // the same level again changes nothing and starts no flow; past its ends it is kept within them
        assert!(!levels.set("out", 100, 3000));
        assert!(!levels.set("out", 250, 3000));
        assert_eq!(levels.flow("out", 3000), None);
        assert!(levels.set("out", -20, 3000));
        assert_eq!(levels.level("out"), Some(0));
        // a module with no level has none to set
        assert!(!levels.set("kb", 50, 3000) && !levels.set("nothing", 50, 3000));
        assert_eq!(levels.level("kb"), None);

        // the line that agrees with the hand changes nothing: no second flow
        let mut levels = levels_of(&m);
        levels.set("out", 60, 1000);
        let agrees = mods(&SHEET.replace(r#""level":55"#, r#""level":60"#));
        assert!(!levels.said(&agrees, 1050));
        assert_eq!(
            levels.flow("out", 1050),
            Some(Flow {
                from: 55,
                to: 60,
                part: ease(50.0 / 120.0)
            })
        );
        // the line that differs is the truth: the level is the line's, and the number flows to it from what was drawn
        let mut levels = levels_of(&m);
        levels.set("out", 60, 1000);
        assert!(levels.said(&m, 5000), "the same line as before, and the drawn level changed");
        assert_eq!(levels.level("out"), Some(55));
        assert_eq!(levels.flow("out", 5000), Some(Flow { from: 60, to: 55, part: 0.0 }));
        let other = mods(&SHEET.replace(r#""level":55"#, r#""level":35"#));
        assert!(levels.said(&other, 9000));
        assert_eq!(
            (levels.level("out"), levels.flow("out", 9000)),
            (Some(35), Some(Flow { from: 55, to: 35, part: 0.0 }))
        );
        // a module that leaves the line takes its level with it; one that comes has no flow
        assert!(levels.said(&mods(SHORT), 9500));
        assert_eq!(levels.each().collect::<Vec<_>>(), [("out", 55)]);
        assert!(levels.said(&m, 9600));
        assert_eq!((levels.level("mic"), levels.flow("mic", 9600)), (Some(40), None));
        assert_eq!(levels.each().map(|l| l.0).collect::<Vec<_>>(), ["wifi", "out", "mic", "light"]);
    }

    #[test]
    fn only_the_digits_that_change_move_up_when_the_level_rose_and_down_when_it_fell() {
        let roll = |digit: char, shift: f64| Roll { digit, shift };
        // 55 to 60, a quarter of the way: both digits leave upward, the new ones a cell's height behind them
        assert_eq!(
            rolls(55, 60, 0.25),
            [vec![], vec![roll('5', -0.25), roll('6', 0.75)], vec![roll('5', -0.25), roll('0', 0.75)]]
        );
        // 60 to 55: downward, the new ones coming from above
        assert_eq!(
            rolls(60, 55, 0.25),
            [vec![], vec![roll('6', 0.25), roll('5', -0.75)], vec![roll('0', 0.25), roll('5', -0.75)]]
        );
        // a digit that stays is still: 55 to 65 moves the tens alone
        assert_eq!(rolls(55, 65, 0.5), [vec![], vec![roll('5', -0.5), roll('6', 0.5)], vec![roll('5', 0.0)]]);
        // a cell that fills or empties moves too: 95 to 100, and back
        assert_eq!(
            rolls(95, 100, 0.5),
            [
                vec![roll('1', 0.5)],
                vec![roll('9', -0.5), roll('0', 0.5)],
                vec![roll('5', -0.5), roll('0', 0.5)]
            ]
        );
        assert_eq!(rolls(100, 95, 0.5)[0], [roll('1', 0.5)]);
        // at the start the old digits stand in place, at the end the new ones do, alone
        assert_eq!(rolls(55, 60, 0.0)[1], [roll('5', 0.0), roll('6', 1.0)]);
        for part in [1.0, 7.0, f64::NAN] {
            assert_eq!(rolls(55, 60, part), [vec![], vec![roll('6', 0.0)], vec![roll('0', 0.0)]], "{part}");
        }
        assert_eq!(rolls(55, 55, 0.3), rolls(55, 55, 1.0));
        assert_eq!(rolls(55, 60, -3.0), rolls(55, 60, 0.0));
    }

    #[test]
    fn a_number_flows_for_120_ms_eased_out_and_then_rests() {
        assert_eq!(FLOW_MS, 120);
        // eased out: fast at first, slow into place
        assert_eq!((ease(0.0), ease(0.5), ease(1.0)), (0.0, 0.875, 1.0));
        assert_eq!((ease(-1.0), ease(9.0), ease(f64::NAN)), (0.0, 1.0, 1.0));
        let steps: Vec<f64> = (0..=10).map(|i| ease(i as f64 / 10.0)).collect();
        assert!(steps.windows(2).all(|p| p[0] < p[1]), "{steps:?}");
        assert!(steps[1] - steps[0] > steps[10] - steps[9]);

        let m = mods(SHEET);
        let mut levels = levels_of(&m);
        // the first line's levels do not flow: nothing was drawn before them
        assert!(levels.flow("out", 0).is_none() && !moves(&laid(&m, &levels), &levels, 0));
        assert!(levels.set("out", 60, 1000));
        assert_eq!(levels.flow("out", 1000), Some(Flow { from: 55, to: 60, part: 0.0 }));
        assert_eq!(levels.flow("out", 1060), Some(Flow { from: 55, to: 60, part: 0.875 }));
        assert!(levels.flow("out", 1119).is_some_and(|f| f.part > 0.99 && f.part < 1.0));
        assert_eq!(levels.flow("out", 1120), None);
        // the surface draws frames while a number moves, and none after: an idle bar does not wake
        let l = laid(&m, &levels);
        assert!(moves(&l, &levels, 1000) && moves(&l, &levels, 1119));
        assert!(!moves(&l, &levels, 1120) && !moves(&l, &levels, 999_999));
        // and at rest a frame is the same frame whatever the time: nothing on the bar moves by itself
        let at = |at: u64| l.frame(&View { at, ..view(&levels) });
        assert_eq!((at(1120), at(4120)), (at(999_999), at(999_999)));
        assert_ne!(at(1060), at(1120));
        assert_eq!(levels.flow("mic", 1060), None, "the other levels stand still");
        // a clock that went back does not break it
        assert_eq!(levels.flow("out", 900), Some(Flow { from: 55, to: 60, part: 0.0 }));
        // a change before the last one came to rest flows from the level drawn
        assert!(levels.set("out", 65, 1050));
        assert_eq!(levels.flow("out", 1050), Some(Flow { from: 60, to: 65, part: 0.0 }));
        let l = laid(&m, &levels);
        assert!(moves(&l, &levels, 1169) && !moves(&l, &levels, 1170));
    }

    #[test]
    fn only_a_number_that_is_on_the_bar_moves_and_asks_for_frames() {
        let m = mods(SHEET);
        let shifted = |l: &Layout, levels: &Levels, at: u64| {
            let v = View { at, ..view(levels) };
            l.frame(&v).iter().filter(|d| matches!(d, Draw::Glyph { shift, .. } if *shift != 0.0)).count()
        };
        // the microphone has a level and is not pinned: its change is drawn once, and nothing moves for it
        let mut levels = levels_of(&m);
        assert!(levels.set("mic", 45, 1000));
        let l = laid(&m, &levels);
        assert!(levels.flow("mic", 1010).is_some(), "the level itself changed 10 ms ago");
        for at in [1000, 1010, 1060, 1119, 1120] {
            assert!(!moves(&l, &levels, at), "at {at}");
            assert_eq!(shifted(&l, &levels, at), 0, "at {at}");
        }
        // nor for the brightness, nor for a reading the status changed
        assert!(levels.set("light", 85, 2000));
        let other = mods(&SHEET.replace(r#""level":70"#, r#""level":40"#));
        assert!(levels.said(&other, 2000));
        let l = laid(&other, &levels);
        assert!(!moves(&l, &levels, 2010) && shifted(&l, &levels, 2010) == 0);
        // the speaker's number is on the bar: it moves, and the frames show it
        let mut levels = levels_of(&m);
        assert!(levels.set("out", 60, 1000));
        let l = laid(&m, &levels);
        assert!(moves(&l, &levels, 1010) && shifted(&l, &levels, 1010) == 4);
        // on a bar that gave up the number for width the same change moves nothing: each output by what it shows
        let narrow = lay_on("A", 983, Edge::Top, Status::Ok, &m, &levels, &five(), None, &Prefs::default());
        assert_eq!((narrow.find("out.pct"), narrow.find("out.gauge").is_some()), (None, true));
        assert!(!moves(&narrow, &levels, 1010) && shifted(&narrow, &levels, 1010) == 0);
        // nor where the number is not drawn: muted, or with no device; off draws it, dim, and it moves
        for (state, moving) in [("muted", false), ("missing", false), ("off", true), ("wrong", true)] {
            let m = mods(&SHEET.replace(r#""state":"ok","level":55"#, &format!(r#""state":"{state}","level":55"#)));
            let mut levels = levels_of(&m);
            assert!(levels.set("out", 60, 1000));
            let l = laid(&m, &levels);
            assert_eq!((moves(&l, &levels, 1010), l.find("out.pct").is_some()), (moving, moving), "{state}");
        }
        // nor when the look says motion no
        let still = View {
            at: 1010,
            motion: false,
            ..view(&levels)
        };
        assert!(!l.moving(&still));
        // a bar with no status at all, and one with no level
        assert!(!moves(&Layout::default(), &levels, 1010));
        assert!(!moves(&lay(1200, &mods(SHORT), &five()), &Levels::default(), 1010));
    }

    #[test]
    fn a_frame_shows_the_digits_on_their_way_and_none_without_motion() {
        let m = mods(SHEET);
        let mut levels = levels_of(&m);
        levels.set("out", 60, 1000);
        let l = lay_on("A", 1200, Edge::Top, Status::Ok, &m, &levels, &five(), None, &Prefs::default());
        let cell = |i: i32| Rect::new(830 + i * 10, 4, 10, 28);
        let moving = |rect: Rect, text: &str, shift: f64| Draw::Glyph {
            rect,
            text: text.into(),
            tone: Tone::Text,
            bold: false,
            fit: false,
            shift,
        };
        // halfway through its time the flow is seven eighths done: the 5s nearly out at the top, 6 and 0 nearly in
        let at = |at: u64, motion: bool| View { at, motion, ..view(&levels) };
        assert_eq!(
            shows(&l, "out.pct", false, &at(1060, true)),
            [
                moving(cell(1), "5", -0.875),
                moving(cell(1), "6", 0.125),
                moving(cell(2), "5", -0.875),
                moving(cell(2), "0", 0.125),
                moving(cell(3), "%", 0.0)
            ]
        );
        // the percent sign, the gauge and every other part stand still through it
        let still = [moving(cell(1), "6", 0.0), moving(cell(2), "0", 0.0), moving(cell(3), "%", 0.0)];
        assert_eq!(shows(&l, "out.pct", false, &at(1120, true)), still, "at rest after 120 ms");
        assert_eq!(shows(&l, "out.pct", false, &at(1060, false)), still, "the look says motion no");
        let shifted = |f: &[Draw]| f.iter().filter(|d| matches!(d, Draw::Glyph { shift, .. } if *shift != 0.0)).count();
        assert_eq!(
            (
                shifted(&l.frame(&at(1060, true))),
                shifted(&l.frame(&at(1060, false))),
                shifted(&l.frame(&at(1120, true)))
            ),
            (4, 0, 0)
        );
        // on its chip the digits flow as they do at rest, in their own tone, cut at the same cells
        let v = View {
            hover: l.find("out.pct"),
            ..at(1060, true)
        };
        let f = l.frame(&v);
        assert_eq!(f[f.len() - 6], fill(Rect::new(835, 4, 40, 28), Tone::Lit));
        assert_eq!(f[f.len() - 5..], shows(&l, "out.pct", false, &at(1060, true))[..]);
        // a fall goes the other way
        levels.set("out", 55, 2000);
        let l = lay_on("A", 1200, Edge::Top, Status::Ok, &m, &levels, &five(), None, &Prefs::default());
        let v = View { at: 2060, ..view(&levels) };
        assert_eq!(
            shows(&l, "out.pct", false, &v)[..2],
            [moving(cell(1), "6", 0.875), moving(cell(1), "5", -0.125)]
        );
    }

    #[test]
    fn the_keys_go_round_the_targets_left_to_right() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let key = |focus: usize, k: Key| l.key(focus, k, &levels);
        let last = l.targets.len() - 1;
        assert_eq!(last, 22, "the mark, ten places and twelve parts");
        assert_eq!(key(0, Key::Tab), KeyAct::Focus(1));
        assert_eq!(key(last, Key::Tab), KeyAct::Focus(0), "past the last, the first");
        assert_eq!(key(0, Key::BackTab), KeyAct::Focus(last), "before the first, the last");
        assert_eq!(key(3, Key::BackTab), KeyAct::Focus(2));
        assert_eq!(key(1, Key::Right), KeyAct::Focus(2));
        assert_eq!(key(1, Key::Left), KeyAct::Focus(0));
        assert_eq!(key(last, Key::Right), KeyAct::Focus(0));
        assert_eq!(key(0, Key::Escape), KeyAct::Leave);
        // the order is the one on the screen
        let xs: Vec<i32> = l.targets.iter().map(|t| t.rect.x).collect();
        assert!(xs.windows(2).all(|p| p[0] < p[1]), "{xs:?}");
        // Left and Right always move, on the gauge of a level that can be set too: every target is the same to them
        for focus in 0..=last {
            assert_eq!(key(focus, Key::Right), key(focus, Key::Tab), "{}", l.targets[focus].id);
            assert_eq!(key(focus, Key::Left), key(focus, Key::BackTab), "{}", l.targets[focus].id);
        }
        let gauge = l.find("out.gauge").unwrap();
        assert_eq!(
            (key(gauge, Key::Right), key(gauge, Key::Left)),
            (KeyAct::Focus(gauge + 1), KeyAct::Focus(gauge - 1))
        );
        // a focus past the last target is the last; a bar with no target at all
        assert_eq!(key(999, Key::Tab), KeyAct::Focus(0));
        let none = Layout::default();
        assert_eq!(
            (none.key(0, Key::Tab, &levels), none.key(0, Key::Escape, &levels)),
            (KeyAct::Nothing, KeyAct::Leave)
        );
    }

    #[test]
    fn up_and_down_are_the_wheel_on_any_part_of_a_level_that_can_be_set_and_the_keys_stay() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let does = |id: &str, k: Key| match l.key(l.find(id).unwrap(), k, &levels) {
            KeyAct::Do { press, leave: false } => (send(press.act), press.set),
            other => panic!("{id}: {other:?}"),
        };
        // the speaker at 55, on its sign, its gauge and its number: Up is the wheel up and Down the wheel down, at
        // the part's center, five a step, at once
        for (part, x, width) in [("name", 755, 10), ("gauge", 795, 50), ("pct", 855, 30)] {
            let id = format!("out.{part}");
            let (c, set) = does(&id, Key::Up);
            assert_eq!((c.name.as_str(), c.instance.as_str(), c.button, c.x, c.width), ("out", part, 4, x, width));
            assert_eq!(set, Some(("out".into(), 60)), "{part}");
            let (c, set) = does(&id, Key::Down);
            assert_eq!((c.instance.as_str(), c.button, set), (part, 5, Some(("out".into(), 50))), "{part}");
            // and it is the wheel's own step there
            let wheel = l.press(x as f64, 18.0, 4, &levels);
            assert_eq!((send(wheel.act), wheel.set), does(&id, Key::Up), "{part}");
        }
        // a level that is not pinned is set on its sign: the microphone at 40, the brightness at 80
        assert_eq!(does("mic.name", Key::Up).1, Some(("mic".into(), 45)));
        assert_eq!(does("light.name", Key::Down).1, Some(("light".into(), 75)));
        // the step is from the level drawn, and the ends hold
        let mut drawn = levels.clone();
        drawn.set("out", 100, 0);
        let gauge = l.find("out.gauge").unwrap();
        assert!(matches!(
            l.key(gauge, Key::Up, &drawn),
            KeyAct::Do {
                press: Press { set: Some((_, 100)), .. },
                leave: false
            }
        ));
        assert!(matches!(
            l.key(gauge, Key::Down, &drawn),
            KeyAct::Do {
                press: Press { set: Some((_, 95)), .. },
                leave: false
            }
        ));
        // elsewhere they do nothing: the mark, a place, the plate, a reading (wifi), a module with no level
        for id in [
            "mark",
            "workspace:1",
            "workspace:2",
            "lan.name",
            "wifi.name",
            "kb.name",
            "kb.text",
            "clock.text",
            "notifications.name",
        ] {
            let focus = l.find(id).unwrap();
            assert_eq!(
                (l.key(focus, Key::Up, &levels), l.key(focus, Key::Down, &levels)),
                (KeyAct::Nothing, KeyAct::Nothing),
                "{id}"
            );
        }
        // a reading's gauge is no level to set, pinned or not
        let m = mods(r#"[{"name":"wifi","group":"connections","sign":"\u25e0","level":70,"set":false,"pinned":true}]"#);
        let reading = lay(1200, &m, &[]);
        let gauge = reading.find("wifi.gauge").unwrap();
        assert_eq!(reading.key(gauge, Key::Up, &levels_of(&m)), KeyAct::Nothing);
        assert_eq!(reading.key(gauge, Key::Right, &levels_of(&m)), KeyAct::Focus(gauge + 1));
        // and on a bar with no target at all
        assert_eq!(Layout::default().key(0, Key::Up, &levels), KeyAct::Nothing);
    }

    #[test]
    fn on_a_gauge_home_and_end_set_the_level_to_its_ends() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let gauge = l.find("out.gauge").unwrap();
        let does = |k: Key| match l.key(gauge, k, &levels) {
            KeyAct::Do { press, leave: false } => (send(press.act), press.set),
            other => panic!("{other:?}"),
        };
        // Home: the left button at the gauge's start, 0; End: at its width, 100
        let (c, set) = does(Key::Home);
        assert_eq!((c.button, c.relative_x, c.x, c.relative_y, set), (1, 0, 770, 18, Some(("out".into(), 0))));
        let (c, set) = does(Key::End);
        assert_eq!((c.button, c.relative_x, c.x, c.width, set), (1, 50, 820, 50, Some(("out".into(), 100))));
        assert_eq!(l.key(gauge, Key::Activate, &levels), KeyAct::Nothing);
        // Home and End are a level's gauge's alone
        assert_eq!(l.key(l.find("out.name").unwrap(), Key::Home, &levels), KeyAct::Nothing);
        assert_eq!(l.key(0, Key::End, &levels), KeyAct::Nothing);
    }

    #[test]
    fn enter_and_space_are_the_left_button_at_the_parts_center_and_give_the_keys_back() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let does = |id: &str| match l.key(l.find(id).unwrap(), Key::Activate, &levels) {
            KeyAct::Do { press, leave } => (press, leave),
            other => panic!("{other:?}"),
        };
        let (press, leave) = does("out.name");
        let c = send(press.act);
        assert_eq!(
            (
                c.name.as_str(),
                c.instance.as_str(),
                c.button,
                c.x,
                c.y,
                c.relative_x,
                c.relative_y,
                c.width,
                c.height
            ),
            ("out", "name", 1, 755, 18, 5, 18, 10, 36)
        );
        assert_eq!((press.set, leave), (None, true));
        let (press, leave) = does("clock.text");
        assert_eq!((send(press.act).relative_x, leave), (25, true));
        let (press, leave) = does("mark");
        let c = send(press.act);
        assert_eq!((c.name.as_str(), c.instance.as_str(), c.button, c.relative_x, leave), ("logo", "", 1, 12, true));
        assert_eq!(
            does("workspace:2"),
            (
                Press {
                    act: Act::Sway("workspace number 2".into()),
                    set: None
                },
                true
            )
        );
        assert_eq!(does("workspace:9").0.act, Act::Sway("workspace number 9".into()));
    }

    #[test]
    fn on_a_toggle_enter_and_space_click_and_the_keys_stay() {
        // the speaker's sign mutes and the keyboard's sign and text take the next layout: a click changes them in place
        let line = SHEET
            .replace(r#""label":"output 55%""#, r#""toggle":true,"label":"output 55%""#)
            .replace(r#""label":"keyboard us""#, r#""toggle":true,"label":"keyboard us""#);
        let m = mods(&line);
        assert!(
            m[3].toggle && m[6].toggle && !m[4].toggle && !mods(SHEET)[3].toggle,
            "false unless the line says true"
        );
        for wrong in [r#""yes""#, "1", "null", r#"["true"]"#] {
            assert!(!mods(&format!(r#"[{{"name":"a","sign":"x","toggle":{wrong}}}]"#))[0].toggle, "{wrong}");
        }
        let l = lay(1200, &m, &five());
        let levels = levels_of(&m);
        let does = |id: &str| match l.key(l.find(id).unwrap(), Key::Activate, &levels) {
            KeyAct::Do { press, leave } => (send(press.act), press.set, leave),
            other => panic!("{id}: {other:?}"),
        };
        // the click goes out as on any part, and the keyboard stays, to switch it again
        for id in ["out.name", "kb.name", "kb.text"] {
            let (c, set, leave) = does(id);
            assert_eq!((c.button, set, leave, target(&l, id).kind), (1, None, false, Kind::Toggle), "{id}");
        }
        let (c, ..) = does("kb.text");
        assert_eq!((c.name.as_str(), c.instance.as_str(), c.relative_x, c.width), ("kb", "text", 10, 20));
        // only the sign and the text: the speaker's number opens something, and its gauge is the level, where Enter does nothing
        assert_eq!((does("out.pct").2, target(&l, "out.pct").kind), (true, Kind::Open));
        let gauge = l.find("out.gauge").unwrap();
        assert_eq!((l.key(gauge, Key::Activate, &levels), l.targets[gauge].kind), (KeyAct::Nothing, Kind::Level));
        // a module that does not say toggle gives the keys back, as the mark and a workspace do
        for id in ["lan.name", "mic.name", "clock.text", "notifications.name", "mark"] {
            assert_eq!((does(id).2, target(&l, id).kind == Kind::Toggle), (true, false), "{id}");
        }
        assert!(matches!(l.key(2, Key::Activate, &levels), KeyAct::Do { leave: true, .. }));
        // the arrows and Tab pass a toggle as any part, and Home and End are a level's alone
        let sign = l.find("out.name").unwrap();
        assert_eq!(
            (l.key(sign, Key::Right, &levels), l.key(sign, Key::Tab, &levels)),
            (KeyAct::Focus(sign + 1), KeyAct::Focus(sign + 1))
        );
        assert_eq!(l.key(sign, Key::Home, &levels), KeyAct::Nothing);
        // nothing stands or looks otherwise for it, and the pointer's click is the same click
        let plain = sheet(1200);
        for (t, was) in l.targets.iter().zip(&plain.targets) {
            assert_eq!((&t.id, t.rect, t.tone, &t.what, t.state), (&was.id, was.rect, was.tone, &was.what, was.state));
        }
        assert_eq!(l.press(755.0, 20.0, 1, &levels), plain.press(755.0, 20.0, 1, &levels));
        // the state file says which targets are toggles
        let bars = [Shown {
            output: "A",
            scale: 1,
            layout: &l,
            focus: None,
            hover: None,
        }];
        let text = state_text(Status::Ok, None, &levels, &[], &bars);
        assert!(text.contains("target\tA\tout.name\t750\t0\t10\t36\ttoggle\tok\t-\toutput 55%\n"), "{text}");
        assert!(text.contains("target\tA\tkb.text\t1020\t0\t20\t36\ttoggle\tok\t-\tkeyboard us\n"));
        assert_eq!(text.matches("\ttoggle\t").count(), 3);
    }

    /// The sheet's line with the speaker at a level.
    fn speaker_at(level: i32) -> Vec<Module> {
        mods(&SHEET.replace(r#""level":55"#, &format!(r#""level":{level}"#)))
    }

    #[test]
    fn a_burst_of_steps_is_not_pulled_back_by_the_answers_to_its_earlier_steps() {
        assert_eq!(HAND_MS, 1000);
        // the speaker at 40 and three wheel steps up, 30 ms apart: 45, 50 and 55 are drawn at once
        let mut levels = levels_of(&speaker_at(40));
        for (level, at) in [(45, 1000), (50, 1030), (55, 1060)] {
            assert!(levels.set("out", level, at));
        }
        assert_eq!(levels.level("out"), Some(55));
        // the status answers each step in turn, late: 45 and 50 are old answers and are not drawn
        assert!(!levels.said(&speaker_at(45), 1200));
        assert_eq!((levels.level("out"), levels.flow("out", 1200)), (Some(55), None), "no jump back, and no flow");
        assert!(!levels.said(&speaker_at(50), 1300));
        assert_eq!(levels.level("out"), Some(55));
        // 55 is the latest the hand set: the line confirms it, and nothing moves
        assert!(!levels.said(&speaker_at(55), 1400));
        assert_eq!((levels.level("out"), levels.flow("out", 1400)), (Some(55), None));
        // the bar laid out through it shows 55 all along, though the line it is laid out from says 45
        let old = speaker_at(45);
        let l = lay_on("A", 1200, Edge::Top, Status::Ok, &old, &levels, &five(), None, &Prefs::default());
        assert_eq!(
            target(&l, "out.pct").what,
            What::Number {
                module: "out".into(),
                level: 55,
                x: 830
            }
        );
        // the burst is answered: a value it passed through, said after that and within the second, is news
        assert!(levels.said(&speaker_at(45), 1500));
        assert_eq!(
            (levels.level("out"), levels.flow("out", 1500)),
            (Some(45), Some(Flow { from: 55, to: 45, part: 0.0 }))
        );
        // a step waits a second for its answer and no longer: a burst the status never answered ignores 45 at
        // 999 ms after it was set, and takes it for the truth at 1000
        let burst = || {
            let mut levels = levels_of(&speaker_at(40));
            for (level, at) in [(45, 1000), (50, 1500), (55, 1900)] {
                levels.set("out", level, at);
            }
            levels
        };
        let mut levels = burst();
        assert!(!levels.said(&speaker_at(45), 1999));
        assert_eq!(levels.level("out"), Some(55));
        let mut levels = burst();
        assert!(levels.said(&speaker_at(45), 2000), "45 was set a second ago: no answer is waited for any more");
        assert_eq!(levels.level("out"), Some(45));
        // each step by its own time: 50, set at 1500, is still waited for, and 55 is still the hand's last
        assert!(!levels.said(&speaker_at(50), 2001), "an old answer: not drawn");
        assert_eq!(levels.level("out"), Some(45));
        assert!(levels.said(&speaker_at(55), 2002), "the answer to the last step: drawn");
        assert_eq!(levels.level("out"), Some(55));
    }

    #[test]
    fn once_the_last_step_is_answered_a_line_is_news_again() {
        // the wheel from 40 to 45 and 50, and the line says 50: the burst is answered
        let mut levels = levels_of(&speaker_at(40));
        assert!(levels.set("out", 45, 1000) && levels.set("out", 50, 1030));
        assert!(!levels.said(&speaker_at(50), 1200));
        assert_eq!(levels.level("out"), Some(50));
        // then a line says 45, a value the hand passed through within the second: the device was set from
        // outside, and 45 is drawn at once
        assert!(levels.said(&speaker_at(45), 1300));
        assert_eq!(
            (levels.level("out"), levels.flow("out", 1300)),
            (Some(45), Some(Flow { from: 50, to: 45, part: 0.0 }))
        );
        // the same when the status answered each step in turn: 45 (an old answer), 50, and then 45 is news
        let mut levels = levels_of(&speaker_at(40));
        levels.set("out", 45, 1000);
        levels.set("out", 50, 1030);
        assert!(!levels.said(&speaker_at(45), 1100) && !levels.said(&speaker_at(50), 1200));
        assert_eq!(levels.level("out"), Some(50));
        assert!(levels.said(&speaker_at(45), 1300));
        assert_eq!(levels.level("out"), Some(45));

        // the wheel to 45 and the line says 45; then a step to 50 that fails: the line says 45 again
        let mut levels = levels_of(&speaker_at(40));
        assert!(levels.set("out", 45, 1000));
        assert!(!levels.said(&speaker_at(45), 1100));
        assert!(levels.set("out", 50, 1200));
        assert_eq!(levels.level("out"), Some(50));
        // 45 answered its own step long since: it is no old answer now but the truth, drawn at once
        assert!(levels.said(&speaker_at(45), 1300));
        assert_eq!(
            (levels.level("out"), levels.flow("out", 1300)),
            (Some(45), Some(Flow { from: 50, to: 45, part: 0.0 }))
        );
        // and a step that goes through after it is answered as any step is
        assert!(levels.set("out", 50, 1400));
        assert!(!levels.said(&speaker_at(50), 1500));
        assert_eq!(levels.level("out"), Some(50));

        // an unanswered burst still ignores its old answers: 45 and 50 while 55 is waited for
        let mut levels = levels_of(&speaker_at(40));
        for (level, at) in [(45, 1000), (50, 1030), (55, 1060)] {
            levels.set("out", level, at);
        }
        assert!(!levels.said(&speaker_at(45), 1100) && !levels.said(&speaker_at(50), 1150));
        assert_eq!(levels.level("out"), Some(55));
        // a status that answers the last step alone has answered the burst: the steps before it are not waited for
        let mut levels = levels_of(&speaker_at(40));
        for (level, at) in [(45, 1000), (50, 1030), (55, 1060)] {
            levels.set("out", level, at);
        }
        assert!(!levels.said(&speaker_at(55), 1200));
        assert!(levels.said(&speaker_at(50), 1300), "news: no step is waiting");
        assert_eq!(levels.level("out"), Some(50));
    }

    #[test]
    fn a_change_that_failed_shows_when_the_line_says_what_the_hand_never_set() {
        let mut levels = levels_of(&speaker_at(40));
        assert!(levels.set("out", 45, 1000));
        // the status could not change it: its line says 40, a value the hand did not set, and the number flows back
        assert!(levels.said(&speaker_at(40), 1100));
        assert_eq!(
            (levels.level("out"), levels.flow("out", 1100)),
            (Some(40), Some(Flow { from: 45, to: 40, part: 0.0 }))
        );
        // the same line again changes nothing
        assert!(!levels.said(&speaker_at(40), 1150));
        // when the change goes through after all, the line that says the hand's latest is drawn
        assert!(levels.said(&speaker_at(45), 1200));
        assert_eq!(
            (levels.level("out"), levels.flow("out", 1200)),
            (Some(45), Some(Flow { from: 40, to: 45, part: 0.0 }))
        );
        // another program's change in the middle of a burst is the truth too
        let mut levels = levels_of(&speaker_at(40));
        levels.set("out", 45, 1000);
        levels.set("out", 50, 1030);
        assert!(levels.said(&speaker_at(80), 1100));
        assert_eq!(levels.level("out"), Some(80));
        // and of the burst's own answers after it, 45 is old and 50, the latest, is drawn
        assert!(!levels.said(&speaker_at(45), 1150));
        assert_eq!(levels.level("out"), Some(80));
        assert!(levels.said(&speaker_at(50), 1200));
        assert_eq!(levels.level("out"), Some(50));
        // with nothing set by the hand every line is the truth, as it always was
        let mut levels = levels_of(&speaker_at(40));
        assert!(levels.said(&speaker_at(45), 10) && levels.said(&speaker_at(40), 20) && levels.said(&speaker_at(45), 30));
        assert_eq!(levels.level("out"), Some(45));
    }

    #[test]
    fn a_burst_up_and_down_again_holds_through_its_answers() {
        // the speaker at 40: up to 45, up to 50, down to 45
        let mut levels = levels_of(&speaker_at(40));
        for (level, at) in [(45, 1000), (50, 1030), (45, 1060)] {
            assert!(levels.set("out", level, at));
        }
        // the answers in turn: 45 (the first step's, and the hand's latest too), 50 (an old answer), 45
        for (said, at) in [(45, 1200), (50, 1250), (45, 1300)] {
            assert!(!levels.said(&speaker_at(said), at), "{said} at {at}");
            assert_eq!((levels.level("out"), levels.flow("out", at)), (Some(45), None), "{said} at {at}");
        }
        // down and up again, back to where it began: 40 is the hand's latest and 35 its old answer
        let mut levels = levels_of(&speaker_at(40));
        levels.set("out", 35, 1000);
        levels.set("out", 40, 1030);
        for (said, at) in [(35, 1200), (40, 1250)] {
            assert!(!levels.said(&speaker_at(said), at), "{said} at {at}");
            assert_eq!(levels.level("out"), Some(40));
        }
        // a step at the gauge's end sets the same value again: it is the hand's latest still
        let mut levels = levels_of(&speaker_at(90));
        assert!(levels.set("out", 95, 1000) && levels.set("out", 100, 1030));
        assert!(!levels.set("out", 100, 1060), "nothing to draw anew");
        for (said, at) in [(95, 1200), (100, 1250), (100, 1300)] {
            assert!(!levels.said(&speaker_at(said), at), "{said} at {at}");
            assert_eq!(levels.level("out"), Some(100));
        }
        // each level has its own hand: the speaker's burst makes no old answer of the microphone's line
        let mut levels = levels_of(&speaker_at(40));
        levels.set("out", 45, 1000);
        levels.set("out", 50, 1030);
        let line = mods(&SHEET.replace(r#""level":55"#, r#""level":45"#).replace(r#""level":40"#, r#""level":45"#));
        assert!(levels.said(&line, 1100), "the microphone went from 40 to 45");
        assert_eq!((levels.level("out"), levels.level("mic")), (Some(50), Some(45)));
        // a clock that went back forgets nothing early and breaks nothing
        let mut levels = levels_of(&speaker_at(40));
        levels.set("out", 45, 5000);
        levels.set("out", 50, 5030);
        assert!(!levels.said(&speaker_at(45), 10));
        assert_eq!(levels.level("out"), Some(50));
    }

    #[test]
    fn keysyms_and_positions_name_the_same_keys() {
        assert_eq!(Key::of_sym(0xff09, false), Some(Key::Tab));
        assert_eq!(Key::of_sym(0xff09, true), Some(Key::BackTab));
        assert_eq!(Key::of_sym(0xfe20, true), Some(Key::BackTab), "ISO_Left_Tab");
        assert_eq!(Key::of_sym(0x20, false), Some(Key::Activate));
        assert_eq!(Key::of_sym(0xff0d, false), Some(Key::Activate));
        assert_eq!(Key::of_sym(0xff1b, false), Some(Key::Escape));
        assert_eq!(Key::of_sym(0x61, false), None);
        assert_eq!((Key::of_evdev(15, false), Key::of_evdev(15, true)), (Some(Key::Tab), Some(Key::BackTab)));
        assert_eq!((Key::of_sym(0xff51, false), Key::of_sym(0xff53, false)), (Some(Key::Left), Some(Key::Right)));
        assert_eq!((Key::of_sym(0xff52, false), Key::of_sym(0xff54, true)), (Some(Key::Up), Some(Key::Down)));
        assert_eq!((Key::of_evdev(105, false), Key::of_evdev(106, false)), (Some(Key::Left), Some(Key::Right)));
        assert_eq!((Key::of_evdev(103, false), Key::of_evdev(108, false)), (Some(Key::Up), Some(Key::Down)));
        assert_eq!((Key::of_evdev(102, false), Key::of_evdev(107, false)), (Some(Key::Home), Some(Key::End)));
        assert_eq!((Key::of_evdev(57, false), Key::of_evdev(1, false)), (Some(Key::Activate), Some(Key::Escape)));
    }

    #[test]
    fn a_button_off_the_bar_gives_the_keys_back_and_so_does_travel_past_three_cells() {
        assert_eq!(TRAVEL_CELLS, 3);
        // a button anywhere off the bar, wherever the pointer was seen or not seen before
        assert!(Astray::default().back(Off::Pressed, 10));
        let mut seen = Astray::default();
        assert!(!seen.back(Off::Came(400.0, 300.0), 10));
        assert!(seen.back(Off::Pressed, 10));
        // travel is counted from where the pointer came off the bar, as the crow flies: three cells of 10 px keep
        // the keys, a little more gives them back, in any direction
        for (dx, dy, back) in [
            (0.0, 0.0, false),
            (30.0, 0.0, false),
            (30.5, 0.0, true),
            (-30.0, 0.0, false),
            (-31.0, 0.0, true),
            (0.0, 30.0, false),
            (0.0, -30.01, true),
            (18.0, 24.0, false),
            (18.0, 24.1, true),
            (21.3, 21.3, true),
            (-21.0, 21.0, false),
            (900.0, 500.0, true),
        ] {
            let mut p = Astray::default();
            assert!(!p.back(Off::Came(400.0, 300.0), 10), "coming off the bar is no travel");
            assert_eq!(p.back(Off::Moved(400.0 + dx, 300.0 + dy), 10), back, "{dx} {dy}");
        }
        // a hand resting on the mouse: many small moves around one place never add up
        let mut p = Astray::default();
        p.back(Off::Came(400.0, 300.0), 10);
        for i in 0..1000 {
            let (dx, dy) = ([0.0, 9.0, -9.0, 4.0][i % 4], [5.0, -7.0, 0.0, 8.0][i % 4]);
            assert!(!p.back(Off::Moved(400.0 + dx, 300.0 + dy), 10), "{i}");
        }
        // and a slow move away does, once it is far enough from where it began
        let far: Vec<bool> = (1..=8).map(|i| p.back(Off::Moved(400.0 + 5.0 * i as f64, 300.0), 10)).collect();
        assert_eq!(far, [false, false, false, false, false, false, true, true]);
        // three cells of the bar's own text: at a cell of 8, 24 px; of 15, 45
        for (cell, keeps, gives) in [(8, 24.0, 24.5), (15, 45.0, 45.5), (1, 3.0, 3.5)] {
            let mut p = Astray::default();
            p.back(Off::Came(0.0, 0.0), cell);
            assert!(!p.back(Off::Moved(keeps, 0.0), cell) && p.back(Off::Moved(gives, 0.0), cell), "{cell}");
        }
        // back on the bar and off it again, travel is counted anew from where it came off
        let mut p = Astray::default();
        p.back(Off::Came(400.0, 300.0), 10);
        assert!(!p.back(Off::Moved(425.0, 300.0), 10));
        assert!(!p.back(Off::Left, 10));
        assert!(!p.back(Off::Came(425.0, 40.0), 10));
        assert!(!p.back(Off::Moved(440.0, 60.0), 10), "25 px from where it came off this time");
        assert!(p.back(Off::Moved(425.0, 71.0), 10));
        // a move with no coming before it starts the count where it is
        let mut p = Astray::default();
        assert!(!p.back(Off::Moved(900.0, 900.0), 10));
        assert!(!p.back(Off::Moved(930.0, 900.0), 10) && p.back(Off::Moved(931.0, 900.0), 10));
        // a cell of no size is a cell of one pixel, and nothing here panics
        let mut p = Astray::default();
        p.back(Off::Came(0.0, 0.0), 0);
        assert!(!p.back(Off::Moved(3.0, 0.0), 0) && p.back(Off::Moved(3.1, 0.0), -7));
        assert!(!p.back(Off::Moved(f64::NAN, 0.0), 10));
    }

    #[test]
    fn every_target_has_a_name_and_a_module_says_its_own_on_every_part() {
        let l = sheet(1200);
        let names: Vec<&str> = l.targets[11..].iter().map(|t| t.name.as_str()).collect();
        assert_eq!(
            names,
            [
                "wired network",
                "bluetooth on",
                "wifi home 70%",
                "output 55%",
                "output 55%",
                "output 55%",
                "microphone 40%",
                "brightness 80%",
                "keyboard us",
                "keyboard us",
                "13:29",
                "no notifications"
            ]
        );
        // without a label, the module's name
        let nameless = r#"[{"name":"a","sign":"x","label":""},{"name":"b","sign":"y","text":"z","level":5,"pinned":true}]"#;
        let mut all = five();
        all.push(ws(-1, "", "A", false, false, false));
        for width in [120, 300, 473, 1000] {
            for line in [SHEET, nameless] {
                let l = lay(width, &mods(line), &all);
                for t in &l.targets {
                    assert!(!t.name.trim().is_empty(), "{} at {width}", t.id);
                    assert!(!t.id.is_empty());
                }
            }
        }
        assert_eq!(target(&lay(1000, &mods(nameless), &[]), "b.gauge").name, "b");
    }

    #[test]
    fn workspaces_are_read_from_sway_in_number_order() {
        let v: Value = serde_json::from_str(
            r#"[{"num":3,"name":"3:<3> mail","output":"A","visible":false,"focused":false,"urgent":true},
                {"num":-1,"name":"notes","output":"A","visible":false,"focused":false,"urgent":false},
                {"num":1,"name":"1","output":"B","visible":true,"focused":true,"urgent":false},
                {"num":2,"name":"2:","output":"A","visible":true,"focused":false,"urgent":false}]"#,
        )
        .unwrap();
        let all = workspaces(&v);
        let seen: Vec<(Option<i32>, &str, &str)> = all.iter().map(|w| (w.num, w.name.as_str(), w.output.as_str())).collect();
        assert_eq!(
            seen,
            [(Some(1), "1", "B"), (Some(2), "2:", "A"), (Some(3), "3:<3> mail", "A"), (None, "notes", "A")]
        );
        assert!(all[2].urgent && all[0].focused && all[1].visible);
        assert_eq!(workspaces(&Value::Null), vec![]);
        // two workspaces under one number share its place: full, urgent or the plate when either is
        let twice = vec![ws(3, "3:a", "B", false, false, true), ws(3, "3:b", "A", true, true, false)];
        let l = lay(1200, &[], &twice);
        let three = target(&l, "workspace:3");
        assert_eq!((three.what.clone(), three.urgent, three.selected), (What::Plate("03".into()), true, true));
        assert_eq!(l.targets.len(), 11);
    }

    #[test]
    fn an_output_rests_while_it_shows_a_workspace_with_the_rest_name() {
        // the rest name itself, or the rest name, a space and more
        for name in ["idle", "idle DP-1", "idle ", "idle two words"] {
            assert!(rests("idle", name), "{name:?}");
        }
        for name in ["idler", "", "Idle", " idle", "idle\tDP-1", "idle-DP-1", "1:idle", "1", "id"] {
            assert!(!rests("idle", name), "{name:?}");
        }
        // BAR_REST unset or empty: no name rests, the empty one neither
        for name in ["", " ", "idle", " idle", "1"] {
            assert!(!rests("", name), "{name:?}");
        }
        // an output rests by the workspace it shows now, each output by its own
        let mut all = vec![
            ws(1, "1", "A", false, false, false),
            ws(-1, "idle", "A", true, true, false),
            ws(2, "2", "B", true, false, false),
            ws(-1, "idle B", "B", false, false, false),
        ];
        assert!(resting("idle", &all, "A"));
        assert!(!resting("idle", &all, "B"), "its rest workspace is there and not shown");
        assert!(!resting("idle", &all, "C") && !resting("", &all, "A") && !resting("idler", &all, "A"));
        (all[2].visible, all[3].visible) = (false, true);
        assert!(resting("idle", &all, "A") && resting("idle", &all, "B"));
        (all[0].visible, all[1].visible) = (true, false);
        assert!(!resting("idle", &all, "A") && resting("idle", &all, "B"));
        assert!(!resting("idle", &five(), "A") && !resting("idle", &[], "A"));
    }

    #[test]
    fn a_rest_workspace_has_no_place_on_any_bar() {
        let two = vec![ws(1, "1", "A", true, true, false), ws(2, "2", "A", false, false, false)];
        let mut three = two.clone();
        three.push(ws(-1, "idle DP-1", "DP-1", true, false, true));
        let on = |output: &str, rest: &str, workspaces: &[Workspace]| {
            let scene = Scene {
                output,
                width: 1200,
                edge: Edge::Top,
                status: Status::Ok,
                modules: &[],
                levels: &Levels::default(),
                workspaces,
                mode: None,
                rest,
            };
            layout(&scene, &Prefs::default(), &M)
        };
        // with it the run is the run of 1 and 2 alone, on the bar of the screen that shows it too
        for output in ["A", "DP-1"] {
            assert_eq!(on(output, "idle", &three), on(output, "idle", &two), "{output}");
            assert_eq!(on(output, "idle", &three).targets.len(), 11);
        }
        // BAR_REST unset: a place after the tenth as any workspace with a name has, the plate on its own screen
        let (a, own) = (on("A", "", &three), on("DP-1", "", &three));
        let place = target(&a, "workspace:idle DP-1");
        assert_eq!(
            (a.targets.len(), place.rect, place.what.clone(), place.urgent),
            (12, Rect::new(344, 0, 30, 36), What::Place { full: true }, true)
        );
        assert_eq!(target(&own, "workspace:idle DP-1").what, What::Plate("id".into()));
        // a name that only begins with the rest name keeps its place
        three[2].name = "idler".into();
        assert_eq!(on("A", "idle", &three).targets.len(), 12);
        // one of the ten places stands when its workspace has the rest name, with no workspace in it
        let nine = [ws(9, "9", "A", true, true, false)];
        let l = on("A", "9", &nine);
        assert_eq!((l.targets.len(), target(&l, "workspace:9").what.clone()), (11, What::Place { full: false }));
    }

    #[test]
    fn before_the_first_line_and_after_a_break_a_dim_sign_stands_for_the_status() {
        for (status, sign) in [(Status::Loading, ELLIPSIS), (Status::Error, WARNING)] {
            // the last line's modules are not shown: the mark and the run are
            let l = lay_with(1200, status, &mods(SHEET), &five(), &Prefs::default());
            assert_eq!(l.targets.len(), 11);
            assert_eq!(l.targets, sheet(1200).targets[..11]);
            assert_eq!(
                l.fixed,
                [glyph(Rect::new(1160, 0, 20, 36), sign, Tone::Dim)],
                "two cells, two cells from the edge"
            );
            assert!(l.dropped.is_empty());
            // no room for it after the run: none
            assert_eq!(lay_with(434, status, &mods(SHEET), &five(), &Prefs::default()).fixed.len(), 1);
            assert_eq!(lay_with(433, status, &mods(SHEET), &five(), &Prefs::default()).fixed, []);
        }
        assert!(ELLIPSIS == "\u{2026}" && WARNING.starts_with('\u{26a0}'));
    }

    #[test]
    fn the_state_file_names_every_output_target_level_and_drop() {
        let m = mods(SHORT);
        let mut all = five();
        all[4].urgent = true;
        let levels = levels_of(&m);
        let l = lay_on("A", 770, Edge::Top, Status::Ok, &m, &levels, &all, None, &Prefs::default());
        let bars = [Shown {
            output: "A",
            scale: 2,
            layout: &l,
            focus: l.find("workspace:2"),
            hover: l.find("out.gauge"),
        }];
        let want = "bar\t1\n\
            status\tok\n\
            level\tout\t55\n\
            output\tA\t770\t36\ttop\t2\n\
            target\tA\tmark\t10\t0\t24\t36\tmark\tok\t-\tspark\n\
            target\tA\tworkspace:1\t44\t0\t30\t36\tworkspace\tok\t-\tworkspace 1\n\
            target\tA\tworkspace:2\t74\t0\t30\t36\tworkspace\tok\tfocused,selected,visible\tworkspace 2\n\
            target\tA\tworkspace:3\t104\t0\t30\t36\tworkspace\tok\t-\tworkspace 3\n\
            target\tA\tworkspace:4\t134\t0\t30\t36\tworkspace\tok\t-\tworkspace 4\n\
            target\tA\tworkspace:5\t164\t0\t30\t36\tworkspace\tok\tempty\tworkspace 5\n\
            target\tA\tworkspace:6\t194\t0\t30\t36\tworkspace\tok\tempty\tworkspace 6\n\
            target\tA\tworkspace:7\t224\t0\t30\t36\tworkspace\tok\turgent\tworkspace 7\n\
            target\tA\tworkspace:8\t254\t0\t30\t36\tworkspace\tok\tempty\tworkspace 8\n\
            target\tA\tworkspace:9\t284\t0\t30\t36\tworkspace\tok\tempty\tworkspace 9\n\
            target\tA\tworkspace:10\t314\t0\t30\t36\tworkspace\tok\tempty\tworkspace 10\n\
            target\tA\tout.name\t490\t0\t10\t36\topen\tok\t-\toutput 55%\n\
            target\tA\tout.gauge\t510\t0\t50\t36\tlevel\tok\thover\toutput 55%\n\
            target\tA\tout.pct\t580\t0\t30\t36\topen\tok\t-\toutput 55%\n\
            target\tA\tclock.text\t660\t0\t50\t36\topen\tok\t-\t13:29\n\
            target\tA\tnotifications.name\t740\t0\t10\t36\topen\tasks\t-\t2 notifications\n";
        assert_eq!(state_text(Status::Ok, None, &levels, &[], &bars), want);
        // what a bar short of width gave up, in the order it went
        let l = lay_on("A", 673, Edge::Bottom, Status::Ok, &m, &levels, &all, None, &Prefs::default());
        let bars = [Shown {
            output: "A",
            scale: 1,
            layout: &l,
            focus: None,
            hover: None,
        }];
        let text = state_text(Status::Ok, None, &levels, &[], &bars);
        assert!(
            text.contains("output\tA\t673\t36\tbottom\t1\n") && text.ends_with("\t2 notifications\ndropped\tA\tout.pct\n"),
            "{text}"
        );
        assert!(!text.contains("out.pct\t"));
        let l = sheet(653);
        let bars = [Shown {
            output: "A",
            scale: 1,
            layout: &l,
            focus: None,
            hover: None,
        }];
        let text = state_text(Status::Ok, None, &levels_of(&mods(SHEET)), &[], &bars);
        assert!(text.contains("target\tA\tmore\t483\t0\t10\t36\topen\tok\t-\tmore\n"), "{text}");
        assert!(text.ends_with("dropped\tA\tout.pct\ndropped\tA\tout.gauge\ndropped\tA\tlan\ndropped\tA\tbt\ndropped\tA\twifi\ndropped\tA\tout\ndropped\tA\tmic\ndropped\tA\tlight\ndropped\tA\tkb\n"));
        // every level drawn, pinned or not, in the line's order; the hand's change at once
        let mut levels = levels_of(&mods(SHEET));
        levels.set("out", 60, 10);
        assert!(state_text(Status::Ok, None, &levels, &[], &bars)
            .starts_with("bar\t1\nstatus\tok\nlevel\twifi\t70\nlevel\tout\t60\nlevel\tmic\t40\nlevel\tlight\t80\noutput\tA\t"));
        // no output yet, and a broken status
        assert_eq!(state_text(Status::Loading, None, &Levels::default(), &[], &[]), "bar\t1\nstatus\tloading\n");
        assert!(state_text(Status::Error, None, &Levels::default(), &[], &bars).starts_with("bar\t1\nstatus\terror\noutput\tA\t"));
        // every state by its own word
        for state in ["ok", "muted", "off", "missing", "wrong", "asks", "records"] {
            let (l, levels) = in_state(state);
            let bars = [Shown {
                output: "A",
                scale: 1,
                layout: &l,
                focus: None,
                hover: None,
            }];
            assert!(
                state_text(Status::Ok, None, &levels, &[], &bars).contains(&format!("target\tA\tout.name\t1030\t0\t10\t36\topen\t{state}\t-\tout\n")),
                "{state}"
            );
        }
    }

    #[test]
    fn the_state_file_names_an_output_that_rests_and_gives_it_no_bar() {
        let l = sheet(1200);
        let levels = levels_of(&mods(SHEET));
        let bars = [Shown {
            output: "A",
            scale: 1,
            layout: &l,
            focus: None,
            hover: None,
        }];
        let (both, one) = (
            state_text(Status::Ok, None, &levels, &["B"], &bars),
            state_text(Status::Ok, None, &levels, &[], &bars),
        );
        // one line after the levels, before the outputs that have a bar, and nothing else differs
        assert!(both.contains("level\tlight\t80\nrest\tB\noutput\tA\t1200\t36\ttop\t1\n"), "{both}");
        assert_eq!(both.replacen("rest\tB\n", "", 1), one);
        assert!(!one.contains("rest\t") && !both.contains("output\tB") && !both.contains("target\tB"));
        // every output at rest, and a name that would break the file
        assert_eq!(
            state_text(Status::Ok, Some("m"), &Levels::default(), &["A", "B\tC"], &[]),
            "bar\t1\nstatus\tok\nmode\tm\nrest\tA\nrest\tB C\n"
        );
    }

    #[test]
    fn a_tab_or_a_line_end_in_a_name_cannot_break_the_state_file() {
        let m = mods(r#"[{"name":"a\tb","group":"g","sign":"x","text":"c\nd","level":5,"pinned":true,"label":"one\ttwo\r\nthree"}]"#);
        let levels = levels_of(&m);
        let l = lay_on(
            "A\tB",
            1000,
            Edge::Bottom,
            Status::Ok,
            &m,
            &levels,
            &[ws(-1, "tab\there", "A\tB", true, true, false), ws(-1, "line\nend", "A\tB", false, false, false)],
            None,
            &Prefs::default(),
        );
        let text = state_text(
            Status::Ok,
            None,
            &levels,
            &[],
            &[Shown {
                output: "A\tB",
                scale: 1,
                layout: &l,
                focus: None,
                hover: None,
            }],
        );
        for line in text.lines().skip(2) {
            let want = match line.split('\t').next() {
                Some("output") => 6,
                Some("level") => 3,
                _ => 11,
            };
            assert_eq!(line.split('\t').count(), want, "{line:?}");
        }
        assert_eq!(text.lines().count(), 2 + 1 + 1 + 1 + 12 + 4);
        assert!(text.contains("\tbottom\t1\n") && text.contains("\tworkspace tab here\n") && text.contains("\tworkspace:line end\t"));
    }

    /// Whether two boxes share a pixel.
    fn over(a: &Rect, b: &Rect) -> bool {
        a.x < b.right() && b.x < a.right() && a.y < b.y + b.h && b.y < a.y + a.h
    }

    #[test]
    fn no_width_panics_or_lays_one_thing_over_another() {
        let odd = r#"[{"name":"a","sign":"a long sign with no group","text":"and a long text","pinned":true,"level":100,"set":true},{"name":"x","group":"time","text":"bold","bold":true,"state":"off"}]"#;
        let mut many = five();
        many.push(ws(17, "17:writing a long name", "A", false, false, true));
        many.push(ws(-1, "notes", "B", false, false, false));
        let prefs = [Prefs::default(), Prefs::new("clock lan", 120, ""), Prefs::new("out", 0, "A")];
        for width in 0..=2400 {
            for (line, status) in [(SHEET, Status::Ok), (odd, Status::Ok), (SHEET, Status::Loading), ("[]", Status::Error)] {
                for p in &prefs {
                    for mode in [None, Some("resize"), Some("a mode with a long name to stand in the bar")] {
                        let m = mods(line);
                        let levels = levels_of(&m);
                        let l = lay_on("A", width, Edge::Top, status, &m, &levels, &many, mode, p);
                        let mut rects: Vec<Rect> = l.targets.iter().map(|t| t.rect).collect();
                        rects.extend(l.fixed.iter().map(|d| match d {
                            Draw::Fill { rect, .. } | Draw::Mark { rect } | Draw::Glyph { rect, .. } => *rect,
                        }));
                        rects.sort_by_key(|r| r.x);
                        for r in &rects {
                            assert!(r.w > 0 && r.h > 0 && r.x >= 0 && r.y >= 0 && r.y + r.h <= 36, "{r:?} at {width}");
                        }
                        for pair in rects.windows(2) {
                            assert!(!over(&pair[0], &pair[1]), "{:?} over {:?} at {width}", pair[0], pair[1]);
                        }
                        // all but the mark stands inside the bar, and the status clear of the tray's room and the edge
                        for t in l.targets.iter().filter(|t| t.kind != Kind::Mark) {
                            assert!(t.rect.right() <= width, "{} past {width}", t.id);
                        }
                        for t in l.targets.iter().filter(|t| !matches!(t.kind, Kind::Mark | Kind::Workspace)) {
                            assert!(t.rect.right() <= width - p.tray_on("A") - 20, "{} at {width}", t.id);
                        }
                        // a frame draws at any width, the pointer and the keys on any target
                        let v = View {
                            hover: Some(width as usize % (l.targets.len() + 1)),
                            focus: Some(width as usize % 7),
                            at: 50,
                            ..view(&levels)
                        };
                        assert!(!l.frame(&v).is_empty());
                    }
                }
            }
        }
    }

    #[test]
    fn malformed_lines_never_panic() {
        let many = five();
        // a line read, laid out, drawn, pressed and keyed, whatever it says
        let run = |line: &str| {
            let Some((modules, _)) = parse_refresh(line) else { return };
            let mut levels = Levels::default();
            levels.said(&modules, 0);
            levels.said(&modules, 60);
            for width in [0, 90, 400, 800, 1920] {
                let l = lay_on(
                    "A",
                    width,
                    Edge::Top,
                    Status::Ok,
                    &modules,
                    &levels,
                    &many,
                    Some("m"),
                    &Prefs::new("a b", 30, ""),
                );
                for i in 0..=l.targets.len() {
                    let v = View {
                        hover: Some(i),
                        focus: Some(i),
                        at: 100,
                        ..view(&levels)
                    };
                    let _ = l.frame(&v);
                    for k in [
                        Key::Tab,
                        Key::BackTab,
                        Key::Left,
                        Key::Right,
                        Key::Up,
                        Key::Down,
                        Key::Home,
                        Key::End,
                        Key::Activate,
                        Key::Escape,
                    ] {
                        let _ = l.key(i, k, &levels);
                    }
                }
                for t in &l.targets {
                    for button in 0..=6 {
                        let p = l.press(t.rect.x as f64 + 0.5, 1.0, button, &levels);
                        if let Some((name, level)) = p.set {
                            assert!((0..=100).contains(&level), "{name} {level}");
                        }
                    }
                }
                let bars = [Shown {
                    output: "A",
                    scale: 1,
                    layout: &l,
                    focus: Some(3),
                    hover: Some(900),
                }];
                assert!(state_text(Status::Ok, Some("m"), &levels, &[], &bars).starts_with("bar\t1\n"));
            }
        };
        let odd = [
            "",
            "[",
            "]",
            "[[]]",
            "[[[[[[[[[[",
            "{}",
            "null",
            "0",
            "\"[]\"",
            "[null,true,1,\"x\",[],{}]",
            r#"[{"name":null}]"#,
            r#"[{"name":"look"}]"#,
            r#"[{"name":"look","fg":7,"alpha":[],"full":{},"light":null,"motion":1}]"#,
            r#"[{"name":"a","sign":"","text":"","cells":0,"level":50,"pinned":true}]"#,
            r#"[{"name":"a","sign":"x","level":1e400,"cells":1e400}]"#,
            r#"[{"name":"a","sign":"x","level":-99999999999999999999,"cells":99999999999999999999,"pinned":true,"set":true}]"#,
            r#"[{"name":"a","sign":"x","level":55.5,"cells":2.5,"pinned":true,"set":true}]"#,
            r#"[{"name":"a","sign":"x","level":9223372036854775807,"cells":9223372036854775807,"pinned":true,"set":true}]"#,
            r#"[{"name":"a","sign":"\ud83d\ude00\u200d\ufe0f\u0301","text":"\u0301\u0301","cells":3,"group":"time","bold":true}]"#,
            r#"[{"name":"a","group":"time","sign":"x"},{"name":"b","group":"time","sign":"y"},{"name":"c","group":"time","sign":"z"}]"#,
            r#"[{"name":"more","sign":"x"},{"name":"mark","sign":"y"},{"name":"workspace:1","sign":"z"},{"name":"logo","sign":"l"}]"#,
            r#"[{"name":"a.b.c","sign":"x","text":"\t\n","cells":400,"level":100,"pinned":true,"set":true,"state":"missing"}]"#,
            r#",[{"name":"a","sign":"x"}],"#,
            r#",,[{"name":"a","sign":"x"}],,"#,
        ];
        for line in odd {
            run(line);
        }
        // every start of the sheet's line, and the line with any one character taken out or made another
        let cuts: Vec<usize> = SHEET.char_indices().map(|(i, _)| i).collect();
        for &i in &cuts {
            run(&SHEET[..i]);
        }
        for pair in cuts.windows(2).step_by(3) {
            let (before, after) = (&SHEET[..pair[0]], &SHEET[pair[1]..]);
            run(&format!("{before}{after}"));
            for other in ["\"", "{", "[", "9", "x", ",", ":", "\u{2501}"] {
                run(&format!("{before}{other}{after}"));
            }
        }
        // the look alone is read from any of them without a panic too
        for &i in cuts.iter().step_by(7) {
            let _ = parse_refresh(&SHEET[i..]);
        }
    }

    #[test]
    fn the_status_is_started_again_later_each_time() {
        let waits: Vec<u64> = (1..=8).map(backoff).collect();
        assert_eq!(waits, [1, 2, 4, 8, 16, 30, 30, 30]);
        assert_eq!(backoff(0), 1);
        assert_eq!(backoff(u32::MAX), 30);
    }

    #[test]
    fn sparks_mark_is_picked_by_the_ground_and_the_size() {
        assert!(dark_ground(0x28, 0x2a, 0x38) && !dark_ground(0xeb, 0xeb, 0xec));
        assert!(dark_ground(127, 127, 127) && !dark_ground(128, 128, 128), "the line at half");
        // the PNG nearest the size at or above it; past the largest, the SVG at the size
        assert_eq!(mark_file(true, M.mark), "favicon-26.png");
        assert_eq!(mark_file(false, 24), "favicon-light-26.png");
        assert_eq!(mark_file(true, 16), "favicon-16.png");
        assert_eq!(mark_file(true, 27), "favicon.svg");
        assert_eq!(mark_file(false, 48), "favicon-light.svg");
    }

    #[test]
    fn a_child_is_steady_once_it_has_lived_ten_seconds() {
        assert!(!steady(0) && !steady(9));
        assert!(steady(10) && steady(u64::MAX));
    }

    fn look_of(line: &str) -> Look {
        parse_refresh(line).expect("a line").1
    }

    #[test]
    fn colors_the_alpha_the_pair_and_the_motion_are_read_as_the_environment_has_them() {
        assert_eq!(hex("ff0080"), Some([255, 0, 128]));
        assert_eq!(hex("#000000"), Some([0, 0, 0]));
        assert_eq!(hex(" ABCdef\n"), Some([0xab, 0xcd, 0xef]));
        for bad in ["", "fff", "ff00800", "gg0000", "+f0080", "ff 080", "#"] {
            assert_eq!(hex(bad), None, "{bad:?}");
        }
        assert_eq!((alpha("0.95"), alpha(" 1 "), alpha("0")), (Some(0.95), Some(1.0), Some(0.0)));
        // past its ends it is kept within them
        assert_eq!((alpha("2"), alpha("-0.5")), (Some(1.0), Some(0.0)));
        for bad in ["", "half", "nan", "inf", "0,5", "50%"] {
            assert_eq!(alpha(bad), None, "{bad:?}");
        }
        // one glyph of the pair, the blanks around it dropped
        assert_eq!(
            (pair_glyph("\u{2501}"), pair_glyph(" \u{25b0}\n"), pair_glyph("#")),
            (Some("\u{2501}".into()), Some("\u{25b0}".into()), Some("#".into()))
        );
        for bad in ["", " ", "\u{2501}\u{2501}", "ab", "a\tb", "\u{7}"] {
            assert_eq!(pair_glyph(bad), None, "{bad:?}");
        }
        assert_eq!((motion("yes"), motion(" no "), motion("")), (Some(true), Some(false), None));
        for bad in ["Yes", "1", "true", "off", "maybe"] {
            assert_eq!(motion(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn a_line_says_the_whole_look_first_and_it_is_no_module() {
        let (modules, look) = parse_refresh(SHEET).unwrap();
        assert_eq!(
            look,
            Look {
                fg: Some([0xeb, 0xdb, 0xb2]),
                accent: Some([0xfe, 0x80, 0x19]),
                muted: Some([0x92, 0x83, 0x74]),
                ground: Some([0x28, 0x28, 0x28]),
                lit: Some([0x3c, 0x38, 0x36]),
                attention: Some([0xfa, 0xbd, 0x2f]),
                alert: Some([0xfb, 0x49, 0x34]),
                ink: None,
                alpha: Some(0.95),
                full: Some("\u{2501}".into()),
                light: Some("\u{2500}".into()),
                motion: Some(true),
            }
        );
        assert!(!modules.iter().any(|m| m.name == LOOK));
        // no target, no drop and no level under its name, at any width, though it says a sign and a level as a module would
        let line = SHEET.replacen(
            r#"{"name":"look","#,
            r#"{"name":"look","sign":"L","text":"look","cells":9,"level":50,"pinned":true,"group":"time","#,
            1,
        );
        assert_eq!(mods(&line), mods(SHEET));
        for width in [0, 564, 873, 984, 1200] {
            let l = lay(width, &mods(&line), &five());
            assert_eq!(l, sheet(width), "at {width}");
            assert!(!l.targets.iter().any(|t| t.id.starts_with(LOOK)) && !l.dropped.iter().any(|d| d.starts_with(LOOK)));
        }
        assert_eq!(levels_of(&mods(&line)).level(LOOK), None);
        // alone on its line: a refresh with no module
        assert_eq!(mods(r#"[{"name":"look","fg":"abb2bf"}]"#), vec![]);
    }

    #[test]
    fn a_look_names_the_slots_it_says_and_no_other() {
        let look = look_of(r#"[{"name":"look","ground":"282c34","alpha":"0.5","motion":"no"}]"#);
        assert_eq!(
            look,
            Look {
                ground: Some([0x28, 0x2c, 0x34]),
                alpha: Some(0.5),
                motion: Some(false),
                ..Look::default()
            }
        );
        // a look with nothing in it, a line without one, and of two looks the last, whole
        assert_eq!(look_of(r#"[{"name":"look"}]"#), Look::default());
        assert_eq!(look_of(SHORT), Look::default());
        assert_eq!(look_of("[]"), Look::default());
        let two = look_of(r#"[{"name":"look","fg":"abb2bf","alpha":"0.5"},{"name":"a","sign":"x"},{"name":"look","alert":"e06c75","full":"\u25ae"}]"#);
        assert_eq!(
            two,
            Look {
                alert: Some([0xe0, 0x6c, 0x75]),
                full: Some("\u{25ae}".into()),
                ..Look::default()
            }
        );
        // an object is the look by its name alone, and what is no refresh says no look either
        assert_eq!(
            look_of(r#"[{"name":"Look","fg":"abb2bf"},{"group":"look","fg":"abb2bf"},"look"]"#),
            Look::default()
        );
        assert_eq!(parse_refresh(r#"{"version":1,"click_events":true}"#), None);
        assert_eq!(parse_refresh("["), None);
    }

    #[test]
    fn a_slot_a_look_gets_wrong_is_left_and_the_others_are_taken() {
        // too short, not hex, a number, null: left; with a # or blanks around it, as the environment takes it
        let look = look_of(
            r##"[{"name":"look","fg":"abb2b","accent":"gggggg","muted":7,"ground":null,"lit":"#3E4451","attention":" e06c75 ","alert":"red","alpha":"half",
                "full":"\u2501\u2501","light":"","motion":"maybe"}]"##,
        );
        assert_eq!(
            look,
            Look {
                lit: Some([0x3e, 0x44, 0x51]),
                attention: Some([0xe0, 0x6c, 0x75]),
                ..Look::default()
            }
        );
        // every value is a string, as the environment's are: a number or a boolean is none
        let said = |key: &str, value: &str| look_of(&format!(r#"[{{"name":"look","{key}":{value}}}]"#));
        assert_eq!(
            (
                said("alpha", r#""1.5""#).alpha,
                said("alpha", r#""-1""#).alpha,
                said("alpha", r#"" 0.25 ""#).alpha
            ),
            (Some(1.0), Some(0.0), Some(0.25))
        );
        for bad in [r#""nan""#, r#""inf""#, r#""""#, "0.5", "true", "null", r#"["0.5"]"#] {
            assert_eq!(said("alpha", bad).alpha, None, "{bad}");
        }
        assert_eq!(
            (said("motion", r#""no""#).motion, said("motion", "false").motion, said("motion", "0").motion),
            (Some(false), None, None)
        );
        assert_eq!(
            (said("full", r#""\u25b0""#).full, said("full", "7").full, said("light", r#"" \u25b1 ""#).light),
            (Some("\u{25b0}".into()), None, Some("\u{25b1}".into()))
        );
        assert_eq!(
            (said("alert", r#""fb4934""#).alert, said("alert", "16468276").alert),
            (Some([0xfb, 0x49, 0x34]), None)
        );
        // the ink is a color as the others are; left out, empty or wrong it is none, and the ground stands for it
        assert_eq!(said("ink", r#""1F2430""#).ink, Some([0x1f, 0x24, 0x30]));
        assert_eq!(look_of(SHEET).ink, None);
        for bad in [r#""""#, r#""1f243""#, r#""ground""#, "2041904", "null"] {
            assert_eq!(said("ink", bad).ink, None, "{bad}");
        }
    }

    #[test]
    fn the_binding_mode_is_sways_and_default_is_none() {
        let of = |s: &str| mode(&serde_json::from_str(s).unwrap());
        assert_eq!(of(r#"{"name":"resize"}"#), Some("resize".into()));
        assert_eq!(of(r#"{"name":"default"}"#), None);
        // a name is taken as it is, markup too
        assert_eq!(of(r#"{"name":"<b>move</b> it"}"#), Some("<b>move</b> it".into()));
        for none in [r#"{"name":""}"#, r#"{"name":7}"#, r#"{"success":false}"#, "null", "[]"] {
            assert_eq!(of(none), None, "{none}");
        }
    }

    /// The sheet's bar on A in a binding mode.
    fn in_mode(width: i32, status: Status, mode: &str, workspaces: &[Workspace]) -> Layout {
        let m = mods(SHEET);
        lay_on("A", width, Edge::Top, status, &m, &levels_of(&m), workspaces, Some(mode), &Prefs::default())
    }

    /// The mode's name as it stands: where its first glyph is, and the glyphs drawn.
    fn mode_said(l: &Layout) -> Option<(i32, String)> {
        let said: Vec<(i32, &str)> = l
            .fixed
            .iter()
            .filter_map(|d| match d {
                Draw::Glyph {
                    rect,
                    text,
                    tone: Tone::Attention,
                    ..
                } => Some((rect.x, text.as_str())),
                _ => None,
            })
            .collect();
        said.first().map(|first| (first.0, said.iter().map(|s| s.1).collect()))
    }

    #[test]
    fn a_binding_mode_stands_one_cell_after_the_run_in_the_attention_color_and_is_no_target() {
        let (with, without) = (in_mode(1200, Status::Ok, "resize", &five()), sheet(1200));
        // the run ends at 344: plain text from 354, a glyph a cell, no fill behind it
        assert_eq!(mode_said(&with), Some((354, "resize".into())));
        assert_eq!(with.fixed[0], glyph(Rect::new(354, 0, 10, 36), "r", Tone::Attention));
        assert_eq!(with.fixed.len(), 7, "six glyphs and the hairline");
        assert_eq!(mode_said(&without), None);
        // no target: every target is where it was, the pointer reaches nothing there and the keys pass it by
        assert_eq!((&with.targets, &with.dropped), (&without.targets, &without.dropped));
        let levels = Levels::default();
        assert_eq!((with.hit(370.0, 10.0), with.press(370.0, 10.0, 1, &levels)), (None, Press::default()));
        assert_eq!(with.key(10, Key::Tab, &levels), KeyAct::Focus(11));
        assert_eq!(with.targets[11].id, "lan.name");
        // a name with markup in it is plain text
        assert_eq!(mode_said(&in_mode(1200, Status::Ok, "<b>r</b>", &five())), Some((354, "<b>r</b>".into())));
        // before the first line and after a break it stands too
        for status in [Status::Loading, Status::Error] {
            assert_eq!(mode_said(&in_mode(1200, status, "resize", &five())), Some((354, "resize".into())));
        }
        // after the last place when a workspace stands past the tenth
        let mut all = five();
        all.push(ws(11, "11", "A", false, false, false));
        assert_eq!(mode_said(&in_mode(1200, Status::Ok, "resize", &all)), Some((384, "resize".into())));
    }

    #[test]
    fn a_mode_is_cut_five_cells_before_the_status_and_takes_nothing_from_it() {
        // the status starts at 610 on the 1200 bar: a long name is cut at 560, whole glyphs only
        let long = "a mode with a long name to stand in the bar here";
        let l = in_mode(1200, Status::Ok, long, &five());
        let (x, said) = mode_said(&l).unwrap();
        assert_eq!((x, said.as_str()), (354, &long[..20]));
        assert_eq!(l.targets, sheet(1200).targets);
        // the status is fitted as if there were no mode: at 984 it fits whole and leaves the mode no room
        let l = in_mode(984, Status::Ok, "resize", &five());
        assert_eq!((mode_said(&l), l.dropped.len()), (None, 0));
        // seven more cells of room and the mode stands whole; one pixel less and its last glyph is cut
        assert_eq!(mode_said(&in_mode(1054, Status::Ok, "resize", &five())), Some((354, "resize".into())));
        assert_eq!(mode_said(&in_mode(1053, Status::Ok, "resize", &five())), Some((354, "resiz".into())));
        // at any width the status with a mode is the status without one
        for width in 0..=1300 {
            for status in [Status::Ok, Status::Loading, Status::Error] {
                let with = in_mode(width, status, long, &five());
                let without = lay_with(width, status, &mods(SHEET), &five(), &Prefs::default());
                assert_eq!((&with.targets, &with.dropped), (&without.targets, &without.dropped), "at {width}");
                let rest: Vec<&Draw> = with.fixed.iter().filter(|d| !matches!(d, Draw::Glyph { tone: Tone::Attention, .. })).collect();
                assert_eq!(rest, without.fixed.iter().collect::<Vec<_>>(), "at {width}");
            }
        }
    }

    #[test]
    fn the_state_file_says_the_mode_while_one_is_on() {
        let l = in_mode(1200, Status::Ok, "resize", &five());
        let bars = [Shown {
            output: "A",
            scale: 1,
            layout: &l,
            focus: None,
            hover: None,
        }];
        let levels = Levels::default();
        let (on, off) = (
            state_text(Status::Ok, Some("resize"), &levels, &[], &bars),
            state_text(Status::Ok, None, &levels, &[], &bars),
        );
        // one line after the status, and nothing else differs: the mode is no target
        assert!(on.starts_with("bar\t1\nstatus\tok\nmode\tresize\noutput\tA\t1200\t36\ttop\t1\n"));
        assert_eq!(on.replacen("mode\tresize\n", "", 1), off);
        assert!(!off.contains("mode"));
        // with no output yet, and a name that would break the file
        assert_eq!(
            state_text(Status::Loading, Some("resize"), &levels, &[], &[]),
            "bar\t1\nstatus\tloading\nmode\tresize\n"
        );
        assert_eq!(
            state_text(Status::Error, Some("re\tsize\r\nnow"), &levels, &[], &[]),
            "bar\t1\nstatus\terror\nmode\tre size  now\n"
        );
    }
}
