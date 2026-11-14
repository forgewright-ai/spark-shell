//! The bar, pure: the modules and their blocks read from a status line, and the look it says, the cells
//! each keeps, the pins, what goes first when the width is short, where everything stands, sway's binding
//! mode among them, what the pointer and the keys reach and what they send back, and the text of the
//! state file. No Wayland, no sway, no file, no environment.

use serde_json::Value;

/// The module that is spark's mark: the bar draws the mark itself and never the module's text.
pub const LOGO: &str = "logo";
/// The block that is the look, by its name: never a module, a cell or a target.
pub const LOOK: &str = "look";
/// The workspaces' name among the pins.
pub const WORKSPACES: &str = "workspaces";
/// The id of the cell that stands for the modules left out.
pub const MORE: &str = "more";
/// What the cell for the modules left out shows, and the cell before the first line: an ellipsis.
pub const ELLIPSIS: &str = "\u{2026}";
/// What stands where the status would be while spark-shell's status is broken: a warning sign, as text.
pub const WARNING: &str = "\u{26a0}\u{fe0e}";
/// The cells a note (the ellipsis before the first line, the warning) keeps.
const NOTE_CELLS: i32 = 2;
/// The most cells one block may keep.
const CELLS_MOST: i64 = 400;
/// The line under a focused target and beside an urgent workspace, in pixels.
pub const LINE: i32 = 2;

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

/// What a block is to the hand: switched, set along its width, or opened.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Control {
    Toggle,
    Level,
    #[default]
    Open,
}

/// Whether what a block stands for can be used.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum State {
    #[default]
    Ok,
    Unavailable,
    Error,
}

impl State {
    pub fn word(self) -> &'static str {
        match self {
            State::Ok => "ok",
            State::Unavailable => "unavailable",
            State::Error => "error",
        }
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

/// One block of a status line: the i3bar fields the bar reads, and the bar's own.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Block {
    pub name: String,
    pub instance: String,
    /// full_text: pango markup.
    pub text: String,
    /// The character cells kept for it; none: as many as its text takes.
    pub cells: Option<i32>,
    /// A label, dropped first when the width is short.
    pub optional: bool,
    pub label: Option<String>,
    pub control: Control,
    pub state: State,
}

impl Block {
    fn of(v: &Value) -> Option<Block> {
        let o = v.as_object()?;
        let text = |k: &str| o.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        Some(Block {
            name: text("name"),
            instance: text("instance"),
            text: text("full_text"),
            cells: o.get("cells").and_then(Value::as_i64).filter(|n| *n >= 0).map(|n| n.min(CELLS_MOST) as i32),
            optional: o.get("optional").and_then(Value::as_bool).unwrap_or(false),
            label: o
                .get("label")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(String::from),
            control: match o.get("control").and_then(Value::as_str) {
                Some("toggle") => Control::Toggle,
                Some("level") => Control::Level,
                _ => Control::Open,
            },
            state: match o.get("state").and_then(Value::as_str) {
                Some("unavailable") => State::Unavailable,
                Some("error") => State::Error,
                _ => State::Ok,
            },
        })
    }

    /// The block's id in the state file: MODULE.INSTANCE, or MODULE alone when it has no instance.
    pub fn id(&self) -> String {
        let name = if self.name.is_empty() { "block" } else { &self.name };
        if self.instance.is_empty() {
            name.to_string()
        } else {
            format!("{name}.{}", self.instance)
        }
    }

    /// The control's name and state in words: its label, else its name and instance; never empty.
    pub fn title(&self) -> String {
        if let Some(l) = &self.label {
            return l.clone();
        }
        let said = format!("{} {}", self.name, self.instance);
        let said = said.trim();
        if said.is_empty() {
            "status".to_string()
        } else {
            said.to_string()
        }
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

/// The look a status line says, in its block named look: the palette's slots, a color each, and the
/// ground's alpha, each a string in the form the environment has it. A slot the line leaves out or gets
/// wrong is None: the environment's stands for it.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Look {
    pub fg: Option<Color>,
    pub accent: Option<Color>,
    pub muted: Option<Color>,
    pub ground: Option<Color>,
    pub lit: Option<Color>,
    pub attention: Option<Color>,
    pub alpha: Option<f64>,
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
            alpha: v["alpha"].as_str().and_then(alpha),
        }
    }
}

/// One line of the status stream: the blocks of a refresh and the look it says, or None for the header,
/// the opening bracket and anything that is not an array. A comma before or after the array is the
/// stream's own. The block named look is the look and no block; of several, the last.
pub fn parse_refresh(line: &str) -> Option<(Vec<Block>, Look)> {
    let line = line.trim();
    let line = line.strip_prefix(',').unwrap_or(line);
    let line = line.strip_suffix(',').unwrap_or(line).trim();
    let v: Value = serde_json::from_str(line).ok()?;
    let (mut blocks, mut look) = (vec![], Look::default());
    for v in v.as_array()? {
        if v["name"] == LOOK {
            look = Look::of(v);
        } else if let Some(block) = Block::of(v) {
            blocks.push(block);
        }
    }
    Some((blocks, look))
}

/// A line's blocks alone.
pub fn parse_line(line: &str) -> Option<Vec<Block>> {
    parse_refresh(line).map(|(blocks, _)| blocks)
}

/// A module: the blocks next to each other on the line under one name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Module {
    pub name: String,
    pub blocks: Vec<Block>,
}

/// The line's blocks as modules, in the line's order.
pub fn modules(blocks: Vec<Block>) -> Vec<Module> {
    let mut out: Vec<Module> = vec![];
    for b in blocks {
        match out.last_mut() {
            Some(m) if m.name == b.name => m.blocks.push(b),
            _ => out.push(Module {
                name: b.name.clone(),
                blocks: vec![b],
            }),
        }
    }
    out
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

    /// What the bar shows: the name without its leading "N:"; a name with no number before a colon, whole.
    pub fn label(&self) -> &str {
        match self.name.split_once(':') {
            Some((n, rest)) if !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()) && !rest.trim().is_empty() => rest,
            _ => &self.name,
        }
    }

    /// Its name as a control: "workspace 2".
    pub fn title(&self) -> String {
        match self.num {
            Some(n) => format!("workspace {n}"),
            None => format!("workspace {}", self.name),
        }
    }

    /// The sway command that shows it.
    pub fn command(&self) -> String {
        match self.num {
            Some(n) => format!("workspace number {n}"),
            None => format!("workspace \"{}\"", self.name.replace(['"', '\\'], "")),
        }
    }
}

/// What the owner chose: the modules shown, the order they go in when the width is short, and the room
/// kept clear at the right end for another program's tray.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Prefs {
    pub pins: Vec<String>,
    pub overflow: Vec<String>,
    pub tray_width: i32,
    pub tray_output: String,
}

impl Prefs {
    /// BAR_PINS and BAR_OVERFLOW (names apart by blanks), BAR_TRAY_WIDTH and BAR_TRAY_OUTPUT.
    pub fn new(pins: &str, overflow: &str, tray_width: i32, tray_output: &str) -> Prefs {
        let words = |s: &str| s.split_whitespace().map(String::from).collect();
        Prefs {
            pins: words(pins),
            overflow: words(overflow),
            tray_width: tray_width.max(0),
            tray_output: tray_output.trim().to_string(),
        }
    }

    /// Whether a module is shown: every one without pins, the pinned ones with them.
    pub fn shows(&self, module: &str) -> bool {
        self.pins.is_empty() || self.pins.iter().any(|p| p == module)
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
}

/// What a target is, in the state file's words.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Mark,
    Workspace,
    Toggle,
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

/// Where a target's click goes: to spark-shell as a click on a block, or to sway as a command.
#[derive(Clone, Debug, PartialEq, Eq)]
enum To {
    Block { name: String, instance: String },
    Sway(String),
}

/// Something the pointer and the keys reach: its slot, what it is and its name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
    pub id: String,
    pub rect: Rect,
    pub kind: Kind,
    pub state: State,
    /// The control's name, never empty.
    pub name: String,
    /// A workspace: the one this output shows, with the focus.
    pub selected: bool,
    pub urgent: bool,
    /// A workspace: shown on its output.
    pub visible: bool,
    to: To,
}

/// How a workspace's label is drawn.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tone {
    /// Shown here with the focus: the accent behind it, the label in the ground's color.
    Focused,
    /// Shown here while another output has the focus: the label in the text's color.
    Visible,
    /// Not shown: muted.
    Other,
    /// Asks for attention: the label and a line in the attention color, never the accent.
    Urgent,
}

/// What a cell shows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Paint {
    /// Spark's mark, in the cell's square.
    Mark,
    /// A workspace's label, centered.
    Workspace { label: String, tone: Tone },
    /// sway's binding mode: its name as plain text, centered, in the colors of the workspace shown with
    /// the focus.
    Mode(String),
    /// A block's text, pango markup, from the cell's left edge and cut at its right one.
    Markup(String),
    /// A muted sign, centered: the ellipsis or the warning.
    Note(&'static str),
}

/// One thing drawn: where, what, and the target it belongs to.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cell {
    pub rect: Rect,
    pub paint: Paint,
    pub target: Option<usize>,
}

/// What a bar shows: an output's width and workspaces, and the status every output repeats.
pub struct Scene<'a> {
    pub output: &'a str,
    pub width: i32,
    pub edge: Edge,
    pub status: Status,
    pub modules: &'a [Module],
    /// Every output's workspaces: the bar takes its own.
    pub workspaces: &'a [Workspace],
    /// sway's binding mode, on every output; none in the default one.
    pub mode: Option<&'a str>,
}

/// A bar laid out: its cells, its targets in the keys' order (left to right), and what was left out
/// for width, in the order it went.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Layout {
    pub width: i32,
    pub height: i32,
    pub edge: Edge,
    pub cells: Vec<Cell>,
    pub targets: Vec<Target>,
    pub dropped: Vec<String>,
}

/// A status block with the width of its slot.
struct Slot<'a> {
    module: usize,
    block: &'a Block,
    w: i32,
}

/// The gap before the next slot: one cell inside a module, two between modules.
fn gap(a: &Slot, b: &Slot, cell: i32) -> i32 {
    if a.module == b.module {
        cell
    } else {
        2 * cell
    }
}

/// The width the status takes: its slots and their gaps, and the cell for the modules left out before them.
fn status_width(slots: &[Slot], more: bool, cell: i32) -> i32 {
    let mut w: i32 = slots.iter().map(|s| s.w).sum();
    w += slots.windows(2).map(|p| gap(&p[0], &p[1], cell)).sum::<i32>();
    if more {
        w += cell + if slots.is_empty() { 0 } else { 2 * cell };
    }
    w
}

/// The order modules go in when the width is short: the ones BAR_OVERFLOW does not name first, from the
/// left of the line, then the named ones in BAR_OVERFLOW's order.
fn drop_order(modules: &[Module], overflow: &[String]) -> Vec<usize> {
    let named = |m: &Module| overflow.iter().position(|o| *o == m.name);
    let mut order: Vec<usize> = (0..modules.len()).filter(|&i| named(&modules[i]).is_none()).collect();
    let mut rest: Vec<usize> = (0..modules.len()).filter(|&i| named(&modules[i]).is_some()).collect();
    rest.sort_by_key(|&i| named(&modules[i]));
    order.extend(rest);
    order
}

/// The workspace that goes next when even the workspaces are too wide: the one farthest from the one
/// shown here, the later one of two as far; an urgent one only when `urgent` allows it.
fn farthest(shown: &[(&Workspace, i32)], urgent: bool) -> Option<usize> {
    let here = shown.iter().position(|(w, _)| w.visible).unwrap_or(0);
    (0..shown.len())
        .filter(|&i| !shown[i].0.visible && (urgent || !shown[i].0.urgent))
        .max_by_key(|&i| (i.abs_diff(here), i))
}

/// The bar laid out. `measure` gives a text's width in pixels in the bar's font: pango markup when its
/// second argument is true, plain text otherwise.
///
/// From the left: an edge of one cell, the mark, a gap, this output's workspaces. From the right: an
/// edge of one cell (after the tray's room), then the status, each block in the slot kept for it, so a
/// text that changes moves nothing. When the width is short, optional blocks go first, then whole
/// modules, then workspaces; the mark never goes and is never made smaller.
///
/// sway's binding mode stands one cell after the workspaces, in the room the status leaves: the status
/// is fitted as if there were no mode, so a mode moves no module and drops none. Workspaces go for it,
/// the farthest first; with none left to go it is cut where the status begins, or not drawn. It is no
/// target.
pub fn layout(scene: &Scene, prefs: &Prefs, m: &Metrics, measure: &dyn Fn(&str, bool) -> i32) -> Layout {
    let (cell, h) = (m.cell.max(1), m.height);
    let left = cell + m.mark + cell;
    let right = (scene.width - prefs.tray_on(scene.output)).max(0) - cell;

    let mut slots: Vec<Slot> = vec![];
    if scene.status == Status::Ok {
        for (mi, module) in scene.modules.iter().enumerate() {
            if module.name == LOGO || !prefs.shows(&module.name) {
                continue;
            }
            for block in &module.blocks {
                let w = match block.cells {
                    Some(n) => n * cell,
                    None => (measure(&block.text, true).max(0) + cell - 1) / cell * cell,
                };
                if w > 0 {
                    slots.push(Slot { module: mi, block, w });
                }
            }
        }
    }
    let mut note = match scene.status {
        Status::Loading => Some(ELLIPSIS),
        Status::Error => Some(WARNING),
        Status::Ok => None,
    };
    let mut shown: Vec<(&Workspace, i32)> = scene
        .workspaces
        .iter()
        .filter(|w| w.output == scene.output && prefs.shows(WORKSPACES))
        .map(|w| (w, measure(w.label(), false).max(0) + cell))
        .collect();
    // the mode's name with half a cell at each side, as a workspace's label
    let mode_w = scene.mode.map_or(0, |name| measure(name, false).max(0) + cell);
    let mut dropped: Vec<String> = vec![];
    let mut more = false;

    let status_w = |slots: &[Slot], more: bool, note: bool| if note { NOTE_CELLS * cell } else { status_width(slots, more, cell) };
    // `mode`: the width of the mode's cell after the workspaces, or 0 to fit without it
    let fits = |slots: &[Slot], more: bool, note: bool, shown: &[(&Workspace, i32)], mode: i32| {
        let (sw, ww) = (status_w(slots, more, note), shown.iter().map(|s| s.1).sum::<i32>());
        let frame = ww + if ww > 0 && mode > 0 { cell } else { 0 } + mode;
        let between = if sw > 0 && frame > 0 { 2 * cell } else { 0 };
        left + frame + between + sw <= right
    };

    // the optional blocks first, one at a time, then whole modules: fitted without the mode
    let order = drop_order(scene.modules, &prefs.overflow);
    'optional: for &mi in &order {
        loop {
            if fits(&slots, more, false, &shown, 0) {
                break 'optional;
            }
            let Some(i) = slots.iter().position(|s| s.module == mi && s.block.optional) else {
                break;
            };
            dropped.push(slots.remove(i).block.id());
        }
    }
    for &mi in &order {
        if fits(&slots, more, false, &shown, 0) {
            break;
        }
        if slots.iter().any(|s| s.module == mi) {
            slots.retain(|s| s.module != mi);
            dropped.push(scene.modules[mi].name.clone());
            more = true;
        }
    }
    // then the workspaces not shown here, the urgent ones last: for the status and for the mode
    while !fits(&slots, more, note.is_some(), &shown, mode_w) {
        let Some(i) = farthest(&shown, false).or_else(|| farthest(&shown, true)) else {
            break;
        };
        dropped.push(shown.remove(i).0.id());
    }
    // a bar too narrow even for what is left of the status shows the mark and the workspaces alone
    if right - status_w(&slots, more, note.is_some()) < left {
        slots.clear();
        more = false;
        note = None;
    }

    let mut lay = Layout {
        width: scene.width,
        height: h,
        edge: scene.edge,
        ..Layout::default()
    };
    lay.add(
        Rect::new(cell, (h - m.mark) / 2, m.mark, m.mark),
        Paint::Mark,
        Some(Target {
            id: "mark".into(),
            rect: Rect::new(cell, 0, m.mark, h),
            kind: Kind::Mark,
            state: State::Ok,
            name: "spark".into(),
            selected: false,
            urgent: false,
            visible: false,
            to: To::Block {
                name: LOGO.into(),
                instance: String::new(),
            },
        }),
    );

    let sw = status_w(&slots, more, note.is_some());
    let start = right - sw;
    // the workspaces end where the status begins: one that does not fit whole is cut there, or goes
    let limit = if sw > 0 { start - 2 * cell } else { right };
    let mut x = left;
    for (ws, w) in shown {
        let w = w.min(limit - x);
        if w <= 0 {
            dropped.push(ws.id());
            continue;
        }
        let rect = Rect::new(x, 0, w, h);
        let tone = match (ws.urgent, ws.visible, ws.focused) {
            (true, ..) => Tone::Urgent,
            (_, true, true) => Tone::Focused,
            (_, true, false) => Tone::Visible,
            _ => Tone::Other,
        };
        lay.add(
            rect,
            Paint::Workspace {
                label: ws.label().to_string(),
                tone,
            },
            Some(Target {
                id: ws.id(),
                rect,
                kind: Kind::Workspace,
                state: State::Ok,
                name: ws.title(),
                selected: ws.visible && ws.focused,
                urgent: ws.urgent,
                visible: ws.visible,
                to: To::Sway(ws.command()),
            }),
        );
        x += w;
    }
    if let Some(name) = scene.mode {
        let x = if x > left { x + cell } else { x };
        let w = mode_w.min(limit - x);
        if w > 0 {
            lay.add(Rect::new(x, 0, w, h), Paint::Mode(name.to_string()), None);
        }
    }

    let mut x = start;
    if let Some(sign) = note {
        lay.add(Rect::new(x, 0, NOTE_CELLS * cell, h), Paint::Note(sign), None);
    }
    if more {
        let rect = Rect::new(x, 0, cell, h);
        lay.add(
            rect,
            Paint::Note(ELLIPSIS),
            Some(Target {
                id: MORE.into(),
                rect,
                kind: Kind::Open,
                state: State::Ok,
                name: MORE.into(),
                selected: false,
                urgent: false,
                visible: false,
                to: To::Block {
                    name: LOGO.into(),
                    instance: String::new(),
                },
            }),
        );
        x += cell + 2 * cell;
    }
    for (i, s) in slots.iter().enumerate() {
        let rect = Rect::new(x, 0, s.w, h);
        lay.add(
            rect,
            Paint::Markup(s.block.text.clone()),
            Some(Target {
                id: s.block.id(),
                rect,
                kind: match s.block.control {
                    Control::Toggle => Kind::Toggle,
                    Control::Level => Kind::Level,
                    Control::Open => Kind::Open,
                },
                state: s.block.state,
                name: s.block.title(),
                selected: false,
                urgent: false,
                visible: false,
                to: To::Block {
                    name: s.block.name.clone(),
                    instance: s.block.instance.clone(),
                },
            }),
        );
        x += s.w + slots.get(i + 1).map_or(0, |next| gap(s, next, cell));
    }
    lay.dropped = dropped;
    lay
}

/// A click as swaybar writes it to the status program: the block, the button, and where, in pixels of
/// the bar and of the block's slot.
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
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Act {
    /// A click for spark-shell.
    Send(Click),
    /// A command for sway.
    Sway(String),
    Nothing,
}

/// A key the bar reads while it has the keyboard.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Tab,
    /// Shift+Tab.
    BackTab,
    Left,
    Right,
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
    /// The target acts; `leave`: the keyboard goes back after it (what opens something takes the keys itself).
    Do {
        act: Act,
        leave: bool,
    },
    /// The keyboard goes back.
    Leave,
    Nothing,
}

impl Layout {
    fn add(&mut self, rect: Rect, paint: Paint, target: Option<Target>) {
        let target = target.map(|t| {
            self.targets.push(t);
            self.targets.len() - 1
        });
        self.cells.push(Cell { rect, paint, target });
    }

    /// The target under a point; none in a gap, at an edge or outside.
    pub fn hit(&self, x: f64, y: f64) -> Option<usize> {
        self.targets.iter().position(|t| t.rect.contains(x, y))
    }

    /// The target with that id.
    pub fn find(&self, id: &str) -> Option<usize> {
        self.targets.iter().position(|t| t.id == id)
    }

    /// A button on a target, the pointer `rx`, `ry` inside its slot.
    fn act(&self, target: usize, button: u32, rx: i32, ry: i32) -> Act {
        let Some(t) = self.targets.get(target) else { return Act::Nothing };
        match &t.to {
            To::Sway(command) if button == 1 => Act::Sway(command.clone()),
            To::Sway(_) => Act::Nothing,
            To::Block { name, instance } => Act::Send(Click {
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
        }
    }

    /// A pointer button (1 left, 2 middle, 3 right, 4 wheel up, 5 wheel down) at a point: a click for
    /// spark-shell on a block, the mark or the cell for the rest; a workspace shown on the left button.
    pub fn press(&self, x: f64, y: f64, button: u32) -> Act {
        let Some(i) = self.hit(x, y) else { return Act::Nothing };
        let r = self.targets[i].rect;
        self.act(i, button, x.floor() as i32 - r.x, y.floor() as i32 - r.y)
    }

    /// A key with the focus on a target. Tab and Shift+Tab go round the targets, left to right; Left and
    /// Right do too, except on a level, which they turn down and up as the wheel does; Home and End set a
    /// level to its ends; Enter or Space is the left button at the slot's center, and nothing on a level.
    pub fn key(&self, focus: usize, k: Key) -> KeyAct {
        let n = self.targets.len();
        if n == 0 {
            return if k == Key::Escape { KeyAct::Leave } else { KeyAct::Nothing };
        }
        let focus = focus.min(n - 1);
        let t = &self.targets[focus];
        let level = t.kind == Kind::Level;
        let (cx, cy) = (t.rect.w / 2, t.rect.h / 2);
        let stay = |act| KeyAct::Do { act, leave: false };
        match k {
            Key::Escape => KeyAct::Leave,
            Key::Tab => KeyAct::Focus((focus + 1) % n),
            Key::BackTab => KeyAct::Focus((focus + n - 1) % n),
            Key::Right if !level => KeyAct::Focus((focus + 1) % n),
            Key::Left if !level => KeyAct::Focus((focus + n - 1) % n),
            Key::Right => stay(self.act(focus, 4, cx, cy)),
            Key::Left => stay(self.act(focus, 5, cx, cy)),
            Key::Home if level => stay(self.act(focus, 1, 0, cy)),
            Key::End if level => stay(self.act(focus, 1, t.rect.w, cy)),
            Key::Home | Key::End => KeyAct::Nothing,
            Key::Activate if level => KeyAct::Nothing,
            Key::Activate => KeyAct::Do {
                act: self.act(focus, 1, cx, cy),
                leave: t.kind != Kind::Toggle,
            },
        }
    }

    /// The line along the bottom of a slot: under the target the keys are on.
    pub fn underline(&self, slot: Rect) -> Rect {
        Rect::new(slot.x, self.height - LINE, slot.w, LINE)
    }

    /// The line along the bar's inner edge, the one toward the windows: beside an urgent workspace.
    pub fn inner_line(&self, slot: Rect) -> Rect {
        match self.edge {
            Edge::Top => Rect::new(slot.x, self.height - LINE, slot.w, LINE),
            Edge::Bottom => Rect::new(slot.x, 0, slot.w, LINE),
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

/// The state file's text: the status, sway's binding mode while one is on, then each output with its
/// targets and what it left out.
pub fn state_text(status: Status, mode: Option<&str>, bars: &[Shown]) -> String {
    let mut out = format!("bar\t1\nstatus\t{}\n", status.word());
    if let Some(name) = mode {
        out += &format!("mode\t{}\n", field(name));
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

    /// Ten pixels a character; a markup's tags take none.
    fn measure(s: &str, markup: bool) -> i32 {
        let mut n = 0;
        let mut tag = false;
        for c in s.chars() {
            match c {
                '<' if markup => tag = true,
                '>' if markup => tag = false,
                _ if !tag => n += 1,
                _ => {}
            }
        }
        n * 10
    }

    /// net (6) | out: an optional label (3) and a level (8) | mic, a toggle (3) | clock (5): 320 px.
    const LINE5: &str = r#"[{"name":"net","instance":"","full_text":"wifi","cells":6},
        {"name":"out","instance":"label","full_text":"vol","cells":3,"optional":true,"label":"output"},
        {"name":"out","instance":"gauge","full_text":"60%","cells":8,"control":"level","level":60,"label":"output 60%"},
        {"name":"mic","instance":"","full_text":"mic","cells":3,"control":"toggle","state":"unavailable"},
        {"name":"clock","instance":"","full_text":"12:00","cells":5}],"#;

    fn mods(line: &str) -> Vec<Module> {
        modules(parse_line(line).expect("a line"))
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

    /// Three on A (2 shown with the focus), one on B (shown).
    fn four() -> Vec<Workspace> {
        vec![
            ws(1, "1:<1>", "A", false, false, false),
            ws(2, "2:<2>", "A", true, true, false),
            ws(3, "3:<3>", "A", false, false, false),
            ws(4, "4:<4>", "B", true, false, false),
        ]
    }

    fn lay_with(width: i32, edge: Edge, status: Status, modules: &[Module], workspaces: &[Workspace], prefs: &Prefs) -> Layout {
        let scene = Scene {
            output: "A",
            width,
            edge,
            status,
            modules,
            workspaces,
            mode: None,
        };
        layout(&scene, prefs, &M, &measure)
    }

    fn lay(width: i32, modules: &[Module], workspaces: &[Workspace]) -> Layout {
        lay_with(width, Edge::Top, Status::Ok, modules, workspaces, &Prefs::default())
    }

    fn rect_of(l: &Layout, id: &str) -> Rect {
        l.targets[l.find(id).unwrap_or_else(|| panic!("no target {id}"))].rect
    }

    fn ids(l: &Layout) -> Vec<&str> {
        l.targets.iter().map(|t| t.id.as_str()).collect()
    }

    fn send(act: Act) -> Click {
        match act {
            Act::Send(c) => c,
            other => panic!("not a click: {other:?}"),
        }
    }

    #[test]
    fn a_line_is_read_with_the_bars_own_fields() {
        let blocks = parse_line(LINE5).unwrap();
        assert_eq!(blocks.len(), 5);
        let gauge = &blocks[2];
        assert_eq!((gauge.name.as_str(), gauge.instance.as_str(), gauge.text.as_str()), ("out", "gauge", "60%"));
        assert_eq!((gauge.cells, gauge.control), (Some(8), Control::Level));
        assert_eq!(gauge.label.as_deref(), Some("output 60%"));
        assert!(blocks[1].optional && !gauge.optional);
        assert_eq!((blocks[3].control, blocks[3].state), (Control::Toggle, State::Unavailable));
        // the defaults: no cells, not optional, opened, ok
        let clock = &parse_line(r#"[{"name":"clock","full_text":"12:00"}]"#).unwrap()[0];
        assert_eq!(
            (clock.cells, clock.optional, clock.control, clock.state),
            (None, false, Control::Open, State::Ok)
        );
        assert_eq!(clock.instance, "");
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
        assert_eq!(parse_line(r#",[{"name":"a","full_text":"x"}]"#).unwrap().len(), 1);
    }

    #[test]
    fn bad_fields_fall_to_their_defaults_and_unknown_keys_are_ignored() {
        let line = r##"[{"name":7,"full_text":"x","cells":-3,"optional":"yes","control":"spin","state":"odd","level":250,
            "separator":false,"separator_block_width":9,"markup":"pango","color":"#ff0000"}, 5, "text", null,
            {"name":"big","full_text":"x","cells":100000,"level":-4,"label":"  "}]"##;
        let blocks = parse_line(line).unwrap();
        assert_eq!(blocks.len(), 2, "what is not an object is no block");
        let b = &blocks[0];
        assert_eq!(
            (b.name.as_str(), b.cells, b.optional, b.control, b.state),
            ("", None, false, Control::Open, State::Ok)
        );
        assert_eq!((blocks[1].cells, blocks[1].label.clone()), (Some(400), None));
    }

    #[test]
    fn blocks_next_to_each_other_under_one_name_are_one_module() {
        let m = mods(LINE5);
        let names: Vec<(&str, usize)> = m.iter().map(|m| (m.name.as_str(), m.blocks.len())).collect();
        assert_eq!(names, [("net", 1), ("out", 2), ("mic", 1), ("clock", 1)]);
        // the same name again after another module is a module of its own
        let m = mods(r#"[{"name":"a","full_text":"1"},{"name":"b","full_text":"2"},{"name":"a","full_text":"3"}]"#);
        assert_eq!(m.len(), 3);
    }

    #[test]
    fn a_block_has_an_id_and_a_name_whatever_it_says() {
        let b = &parse_line(
            r#"[{"name":"out","instance":"gauge","full_text":"x","label":"output 60%"},
            {"name":"out","instance":"gauge","full_text":"x"},{"name":"clock","full_text":"x"},{"full_text":"x"}]"#,
        )
        .unwrap();
        assert_eq!((b[0].id().as_str(), b[0].title().as_str()), ("out.gauge", "output 60%"));
        assert_eq!(b[1].title(), "out gauge");
        assert_eq!((b[2].id().as_str(), b[2].title().as_str()), ("clock", "clock"));
        assert_eq!((b[3].id().as_str(), b[3].title().as_str()), ("block", "status"));
    }

    #[test]
    fn the_sizes_follow_the_text() {
        assert_eq!(Metrics::for_text(16.0, 9.6), M);
        assert_eq!(
            Metrics::for_text(24.0, 14.4),
            Metrics {
                cell: 15,
                height: 54,
                mark: 36
            }
        );
        assert_eq!(Metrics::for_text(f64::NAN, 0.0), Metrics::for_text(16.0, 9.6));
    }

    #[test]
    fn the_status_stands_at_the_right_edge_in_the_lines_order() {
        let l = lay(1000, &mods(LINE5), &four());
        assert_eq!(
            ids(&l),
            [
                "mark",
                "workspace:1",
                "workspace:2",
                "workspace:3",
                "net",
                "out.label",
                "out.gauge",
                "mic",
                "clock"
            ]
        );
        // one cell at the right edge, one between a module's blocks, two between modules
        assert_eq!(rect_of(&l, "clock"), Rect::new(940, 0, 50, 36));
        assert_eq!(rect_of(&l, "mic"), Rect::new(890, 0, 30, 36));
        assert_eq!(rect_of(&l, "out.gauge"), Rect::new(790, 0, 80, 36));
        assert_eq!(rect_of(&l, "out.label"), Rect::new(750, 0, 30, 36));
        assert_eq!(rect_of(&l, "net"), Rect::new(670, 0, 60, 36));
        assert!(l.dropped.is_empty());
    }

    #[test]
    fn the_left_end_is_an_edge_the_mark_a_gap_and_this_outputs_workspaces() {
        let l = lay(1000, &mods(LINE5), &four());
        assert_eq!(rect_of(&l, "mark"), Rect::new(10, 0, 24, 36));
        assert_eq!(
            l.cells[0],
            Cell {
                rect: Rect::new(10, 6, 24, 24),
                paint: Paint::Mark,
                target: Some(0)
            }
        );
        // a label of three characters and half a cell at each side; output B's workspace is not here
        assert_eq!(rect_of(&l, "workspace:1"), Rect::new(44, 0, 40, 36));
        assert_eq!(rect_of(&l, "workspace:2"), Rect::new(84, 0, 40, 36));
        assert_eq!(rect_of(&l, "workspace:3"), Rect::new(124, 0, 40, 36));
        assert_eq!(l.find("workspace:4"), None);
    }

    #[test]
    fn a_text_that_changes_moves_nothing() {
        let before = lay(1000, &mods(LINE5), &four());
        let after = lay(1000, &mods(&LINE5.replace("60%", "100% <b>loud</b>").replace("12:00", "9:05")), &four());
        let rects = |l: &Layout| l.targets.iter().map(|t| (t.id.clone(), t.rect)).collect::<Vec<_>>();
        assert_eq!(rects(&before), rects(&after));
        // the text itself is what changed
        assert_ne!(before.cells, after.cells);
    }

    #[test]
    fn a_block_without_cells_keeps_whole_cells_for_its_text() {
        let m = mods(r#"[{"name":"a","full_text":"<b>abc</b>"},{"name":"b","full_text":"x","cells":0},{"name":"c","full_text":""}]"#);
        let l = lay(1000, &m, &[]);
        // three characters measured, the tags none; a block of no width is not laid out
        assert_eq!(ids(&l), ["mark", "a"]);
        assert_eq!(rect_of(&l, "a"), Rect::new(960, 0, 30, 36));
        let odd = |s: &str, _: bool| s.len() as i32 * 7 + 1;
        let scene = Scene {
            output: "A",
            width: 1000,
            edge: Edge::Top,
            status: Status::Ok,
            modules: &m,
            workspaces: &[],
            mode: None,
        };
        assert_eq!(layout(&scene, &Prefs::default(), &M, &odd).targets[1].rect.w, 80, "71 px up to whole cells");
    }

    #[test]
    fn a_module_appearing_at_the_left_moves_nothing_at_its_right() {
        let without = lay(1000, &mods(LINE5), &four());
        let with = lay(
            1000,
            &mods(&LINE5.replacen('[', r#"[{"name":"vpn","instance":"","full_text":"vpn","cells":4},"#, 1)),
            &four(),
        );
        assert_eq!(rect_of(&with, "vpn"), Rect::new(610, 0, 40, 36));
        for t in &without.targets {
            assert_eq!(rect_of(&with, &t.id), t.rect, "{}", t.id);
        }
    }

    #[test]
    fn without_pins_every_module_is_shown() {
        for prefs in [Prefs::default(), Prefs::new("", "", 0, ""), Prefs::new("   ", "", 0, "")] {
            let l = lay_with(1000, Edge::Top, Status::Ok, &mods(LINE5), &four(), &prefs);
            assert_eq!(l.targets.len(), 9);
        }
    }

    #[test]
    fn with_pins_only_those_are_shown_in_the_lines_order() {
        let prefs = Prefs::new("clock  workspaces net nothing-by-that-name", "", 0, "");
        let l = lay_with(1000, Edge::Top, Status::Ok, &mods(LINE5), &four(), &prefs);
        assert_eq!(ids(&l), ["mark", "workspace:1", "workspace:2", "workspace:3", "net", "clock"]);
        assert_eq!(rect_of(&l, "clock"), Rect::new(940, 0, 50, 36));
        assert_eq!(rect_of(&l, "net"), Rect::new(860, 0, 60, 36));
        // what is not pinned is not left out for width: nothing is named, no cell stands for it
        assert!(l.dropped.is_empty());
        assert_eq!(l.find(MORE), None);
    }

    #[test]
    fn workspaces_not_pinned_are_not_drawn_and_the_mark_always_is() {
        let prefs = Prefs::new("clock", "", 0, "");
        let l = lay_with(1000, Edge::Top, Status::Ok, &mods(LINE5), &four(), &prefs);
        assert_eq!(ids(&l), ["mark", "clock"]);
    }

    #[test]
    fn the_logo_module_is_the_mark_and_its_text_is_never_drawn() {
        let m = mods(r#"[{"name":"logo","instance":"","full_text":"S","cells":2},{"name":"clock","full_text":"12:00","cells":5}]"#);
        let l = lay(1000, &m, &[]);
        assert_eq!(ids(&l), ["mark", "clock"]);
        assert!(!l.cells.iter().any(|c| c.paint == Paint::Markup("S".into())));
        let c = send(l.press(20.0, 10.0, 1));
        assert_eq!((c.name.as_str(), c.instance.as_str()), ("logo", ""));
    }

    #[test]
    fn short_of_width_the_optional_blocks_go_first() {
        // the left takes 44 + 120, the gap 20, the status 320 and the edge 10: 514 fits whole
        assert!(lay(514, &mods(LINE5), &four()).dropped.is_empty());
        let l = lay(513, &mods(LINE5), &four());
        assert_eq!(l.dropped, ["out.label"]);
        assert_eq!(l.find("out.label"), None);
        // an optional block is no module: no cell stands for it, and the rest keeps to the right edge
        assert_eq!(l.find(MORE), None);
        assert_eq!(rect_of(&l, "clock").right(), 503);
        assert_eq!(rect_of(&l, "out.gauge"), Rect::new(303, 0, 80, 36));
    }

    #[test]
    fn then_whole_modules_go_the_unnamed_ones_first_from_the_left() {
        // without the label the status takes 280: 474 fits, 473 does not
        assert_eq!(lay(474, &mods(LINE5), &four()).dropped, ["out.label"]);
        let l = lay(473, &mods(LINE5), &four());
        assert_eq!(l.dropped, ["out.label", "net"]);
        let l = lay(400, &mods(LINE5), &four());
        assert_eq!(l.dropped, ["out.label", "net", "out"]);
        assert_eq!(ids(&l), ["mark", "workspace:1", "workspace:2", "workspace:3", "more", "mic", "clock"]);
    }

    #[test]
    fn the_overflow_order_names_what_goes_first_among_the_named() {
        let prefs = Prefs::new("", "clock out", 0, "");
        // two optional blocks: the unnamed module's goes before the named one's
        let line = LINE5.replace(r#""full_text":"mic","cells":3"#, r#""full_text":"mic","cells":3,"optional":true"#);
        let l = lay_with(513, Edge::Top, Status::Ok, &mods(&line), &four(), &prefs);
        assert_eq!(l.dropped, ["mic"]);
        // modules: net and mic are not named and go first, from the left; then clock, then out
        let l = lay_with(304, Edge::Top, Status::Ok, &mods(LINE5), &four(), &prefs);
        assert_eq!(l.dropped, ["out.label", "net", "mic", "clock"]);
        assert_eq!(ids(&l), ["mark", "workspace:1", "workspace:2", "workspace:3", "more", "out.gauge"]);
    }

    #[test]
    fn a_cell_stands_for_the_modules_left_out_at_the_left_of_the_status() {
        let l = lay(473, &mods(LINE5), &four());
        // out 80, mic 30, clock 50 and two gaps of 20 from 463 leftward; the cell two cells before them
        assert_eq!(rect_of(&l, "out.gauge").x, 263);
        assert_eq!(rect_of(&l, MORE), Rect::new(233, 0, 10, 36));
        let more = &l.targets[l.find(MORE).unwrap()];
        assert_eq!((more.kind, more.name.as_str()), (Kind::Open, "more"));
        assert!(l.cells.iter().any(|c| c.paint == Paint::Note(ELLIPSIS) && c.target == l.find(MORE)));
        // a click on it is a click on the mark's block
        let c = send(l.press(235.0, 5.0, 1));
        assert_eq!((c.name.as_str(), c.instance.as_str(), c.relative_x, c.width), ("logo", "", 2, 10));
    }

    #[test]
    fn the_cells_room_is_kept_as_soon_as_a_module_goes() {
        // 473: dropping net alone would free 80, but the cell and its gap take 30 of them
        let m = mods(r#"[{"name":"a","full_text":"a","cells":2},{"name":"b","full_text":"b","cells":30}]"#);
        // the left 44, the status 20 + 20 + 300, the edge 10: 394 fits; at 393 a goes, at 363 (b alone and the cell) b too
        assert!(lay(394, &m, &[]).dropped.is_empty());
        assert_eq!(lay(393, &m, &[]).dropped, ["a"]);
        assert_eq!(lay(384, &m, &[]).dropped, ["a"]);
        assert_eq!(lay(383, &m, &[]).dropped, ["a", "b"]);
        assert_eq!(ids(&lay(383, &m, &[])), ["mark", "more"]);
    }

    #[test]
    fn the_mark_is_never_dropped_and_never_made_smaller() {
        for width in [0, 1, 30, 60, 200, 513, 4000] {
            let l = lay(width, &mods(LINE5), &four());
            assert_eq!(rect_of(&l, "mark"), Rect::new(10, 0, 24, 36), "at {width}");
            assert_eq!(l.cells[0].rect, Rect::new(10, 6, 24, 24), "at {width}");
        }
    }

    #[test]
    fn workspaces_go_last_the_farthest_from_the_one_shown_first() {
        let many = vec![
            ws(1, "1:<1>", "A", false, false, false),
            ws(2, "2:<2>", "A", false, false, true),
            ws(3, "3:<3>", "A", true, true, false),
            ws(4, "4:<4>", "A", false, false, false),
            ws(5, "5:<5>", "A", false, false, false),
            ws(6, "6:<6>", "A", false, false, false),
        ];
        // every module gone first: the cell (10) is all the status; 44 + 240 + 20 + 10 + 10 = 324 fits the six
        let l = lay(324, &mods(LINE5), &many);
        assert_eq!(l.dropped, ["out.label", "net", "out", "mic", "clock"]);
        // 6 is three away from 3; then 1 and 5 are two away, the later first; the urgent 2 stays past 4
        let l = lay(323, &mods(LINE5), &many);
        assert_eq!(l.dropped[5..], ["workspace:6"]);
        let l = lay(204, &mods(LINE5), &many);
        assert_eq!(l.dropped[5..], ["workspace:6", "workspace:5", "workspace:1"]);
        let l = lay(203, &mods(LINE5), &many);
        assert_eq!(l.dropped[5..], ["workspace:6", "workspace:5", "workspace:1", "workspace:4"]);
        assert_eq!(ids(&l), ["mark", "workspace:2", "workspace:3", "more"]);
        // narrower still, the urgent one goes; the one shown here is the last and is cut, not dropped
        let l = lay(163, &mods(LINE5), &many);
        assert_eq!(ids(&l), ["mark", "workspace:3", "more"]);
        let l = lay(110, &mods(LINE5), &many);
        assert_eq!(rect_of(&l, "workspace:3"), Rect::new(44, 0, 26, 36));
        assert_eq!(rect_of(&l, MORE), Rect::new(90, 0, 10, 36));
    }

    #[test]
    fn the_top_and_the_bottom_lay_out_the_same() {
        let top = lay_with(700, Edge::Top, Status::Ok, &mods(LINE5), &four(), &Prefs::default());
        let bottom = lay_with(700, Edge::Bottom, Status::Ok, &mods(LINE5), &four(), &Prefs::default());
        assert_eq!((top.edge, bottom.edge), (Edge::Top, Edge::Bottom));
        assert_eq!((&top.cells, &top.targets, &top.dropped), (&bottom.cells, &bottom.targets, &bottom.dropped));
        // only the line toward the windows differs: under the bar at the top, over it at the bottom
        let slot = Rect::new(84, 0, 40, 36);
        assert_eq!(top.inner_line(slot), Rect::new(84, 34, 40, 2));
        assert_eq!(bottom.inner_line(slot), Rect::new(84, 0, 40, 2));
        assert_eq!(top.underline(slot), bottom.underline(slot));
        assert_eq!(Edge::parse(Some("bottom")), Edge::Bottom);
        assert_eq!(Edge::parse(Some(" top ")), Edge::Top);
        assert_eq!(Edge::parse(Some("left")), Edge::Top);
        assert_eq!(Edge::parse(None), Edge::Top);
    }

    #[test]
    fn the_pointer_hits_slots_and_misses_gaps_and_edges() {
        let l = lay(1000, &mods(LINE5), &four());
        let id = |x: f64, y: f64| l.hit(x, y).map(|i| l.targets[i].id.as_str());
        assert_eq!(id(9.9, 10.0), None, "the left edge");
        assert_eq!(id(10.0, 0.0), Some("mark"));
        assert_eq!(id(33.9, 35.9), Some("mark"));
        assert_eq!(id(34.0, 10.0), None, "the gap after the mark");
        assert_eq!(id(44.0, 10.0), Some("workspace:1"));
        assert_eq!(id(84.0, 10.0), Some("workspace:2"), "workspaces touch");
        assert_eq!(id(164.0, 10.0), None, "the free space");
        assert_eq!(id(780.0, 10.0), None, "the gap inside a module");
        assert_eq!(id(790.0, 10.0), Some("out.gauge"));
        assert_eq!(id(870.0, 10.0), None, "the gap between modules");
        assert_eq!(id(989.9, 10.0), Some("clock"));
        assert_eq!(id(990.0, 10.0), None, "the right edge");
        assert_eq!(id(800.0, 36.0), None, "under the bar");
        assert_eq!(id(800.0, -0.1), None, "over the bar");
    }

    #[test]
    fn the_keys_go_round_the_targets_left_to_right() {
        let l = lay(1000, &mods(LINE5), &four());
        let last = l.targets.len() - 1;
        assert_eq!(l.key(0, Key::Tab), KeyAct::Focus(1));
        assert_eq!(l.key(last, Key::Tab), KeyAct::Focus(0), "past the last, the first");
        assert_eq!(l.key(0, Key::BackTab), KeyAct::Focus(last), "before the first, the last");
        assert_eq!(l.key(3, Key::BackTab), KeyAct::Focus(2));
        assert_eq!(l.key(1, Key::Right), KeyAct::Focus(2));
        assert_eq!(l.key(1, Key::Left), KeyAct::Focus(0));
        assert_eq!(l.key(last, Key::Right), KeyAct::Focus(0));
        assert_eq!(l.key(0, Key::Escape), KeyAct::Leave);
        // the order is the one on the screen
        let xs: Vec<i32> = l.targets.iter().map(|t| t.rect.x).collect();
        assert!(xs.windows(2).all(|p| p[0] < p[1]), "{xs:?}");
        // Tab leaves a level too, where the arrows do not
        let gauge = l.find("out.gauge").unwrap();
        assert_eq!(l.key(gauge, Key::Tab), KeyAct::Focus(gauge + 1));
        assert_eq!(l.key(gauge, Key::BackTab), KeyAct::Focus(gauge - 1));
        // a bar with no target at all
        let none = Layout::default();
        assert_eq!((none.key(0, Key::Tab), none.key(0, Key::Escape)), (KeyAct::Nothing, KeyAct::Leave));
    }

    #[test]
    fn a_pointer_click_is_sent_as_swaybar_writes_it() {
        let l = lay(1000, &mods(LINE5), &four());
        let c = send(l.press(812.6, 9.2, 1));
        assert_eq!(
            c.json(),
            r#"{"name":"out","instance":"gauge","button":1,"x":812,"y":9,"relative_x":22,"relative_y":9,"width":80,"height":36}"#
        );
        // every button goes to spark-shell, the wheel too
        for button in [2, 3, 4, 5] {
            assert_eq!(send(l.press(950.0, 20.0, button)).button, button);
        }
        assert_eq!(send(l.press(950.0, 20.0, 3)).name, "clock");
        assert_eq!(l.press(880.0, 20.0, 1), Act::Nothing, "a gap");
        // the stream: the bracket before the first click, a comma before the others
        assert_eq!(click_line(&c, true), format!("[\n{}\n", c.json()));
        assert_eq!(click_line(&c, false), format!(",{}\n", c.json()));
        // a name is written as JSON writes it
        let odd = Click { name: "a\"b".into(), ..c };
        assert!(odd.json().starts_with(r#"{"name":"a\"b","instance":"gauge""#));
    }

    #[test]
    fn a_workspace_is_shown_by_the_left_button_alone() {
        let mut all = four();
        all.push(ws(-1, "mail \"box\"", "A", false, false, false));
        let l = lay(1000, &mods(LINE5), &all);
        assert_eq!(l.press(50.0, 10.0, 1), Act::Sway("workspace number 1".into()));
        for button in [2, 3, 4, 5] {
            assert_eq!(l.press(50.0, 10.0, button), Act::Nothing);
        }
        // one without a number, by its name, after the numbered ones
        let named = l.find("workspace:mail \"box\"").unwrap();
        assert_eq!(named, 4);
        assert_eq!(l.targets[named].name, "workspace mail \"box\"");
        assert_eq!(
            l.key(named, Key::Activate),
            KeyAct::Do {
                act: Act::Sway("workspace \"mail box\"".into()),
                leave: true
            }
        );
    }

    #[test]
    fn enter_and_space_are_the_left_button_at_the_slots_center() {
        let l = lay(1000, &mods(LINE5), &four());
        // a toggle keeps the keyboard, to be switched again
        let KeyAct::Do { act, leave } = l.key(l.find("mic").unwrap(), Key::Activate) else {
            panic!()
        };
        let c = send(act);
        assert_eq!(
            (c.name.as_str(), c.button, c.x, c.y, c.relative_x, c.relative_y, c.width, c.height),
            ("mic", 1, 905, 18, 15, 18, 30, 36)
        );
        assert!(!leave);
        // what opens something gives the keyboard back: the mark, a block, a workspace
        let KeyAct::Do { act, leave } = l.key(l.find("clock").unwrap(), Key::Activate) else {
            panic!()
        };
        assert_eq!((send(act).relative_x, leave), (25, true));
        let KeyAct::Do { act, leave } = l.key(0, Key::Activate) else { panic!() };
        let c = send(act);
        assert_eq!((c.name.as_str(), c.instance.as_str(), c.button, c.relative_x, leave), ("logo", "", 1, 12, true));
        assert_eq!(
            l.key(2, Key::Activate),
            KeyAct::Do {
                act: Act::Sway("workspace number 2".into()),
                leave: true
            }
        );
        // Home and End are a level's
        assert_eq!(l.key(l.find("mic").unwrap(), Key::Home), KeyAct::Nothing);
        assert_eq!(l.key(0, Key::End), KeyAct::Nothing);
    }

    #[test]
    fn on_a_level_the_arrows_turn_it_and_home_and_end_set_its_ends() {
        let l = lay(1000, &mods(LINE5), &four());
        let gauge = l.find("out.gauge").unwrap();
        let click = |k: Key| match l.key(gauge, k) {
            KeyAct::Do { act, leave: false } => send(act),
            other => panic!("{other:?}"),
        };
        // Left is the wheel down, Right the wheel up, at the center
        let c = click(Key::Left);
        assert_eq!((c.button, c.relative_x, c.x, c.width), (5, 40, 830, 80));
        assert_eq!(click(Key::Right).button, 4);
        // Home: the left button at the slot's start; End: at its width
        let c = click(Key::Home);
        assert_eq!((c.instance.as_str(), c.button, c.relative_x, c.x, c.relative_y), ("gauge", 1, 0, 790, 18));
        let c = click(Key::End);
        assert_eq!((c.button, c.relative_x, c.x, c.width), (1, 80, 870, 80));
        assert_eq!(l.key(gauge, Key::Activate), KeyAct::Nothing);
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
        assert_eq!((Key::of_evdev(105, false), Key::of_evdev(106, false)), (Some(Key::Left), Some(Key::Right)));
        assert_eq!((Key::of_evdev(102, false), Key::of_evdev(107, false)), (Some(Key::Home), Some(Key::End)));
        assert_eq!((Key::of_evdev(57, false), Key::of_evdev(1, false)), (Some(Key::Activate), Some(Key::Escape)));
    }

    #[test]
    fn every_target_has_a_name() {
        let nameless = r#"[{"full_text":"x"},{"name":"","instance":"","full_text":"y","label":""},{"name":"a","instance":"b","full_text":"z"}]"#;
        let mut all = four();
        all.push(ws(-1, "", "A", false, false, false));
        for width in [120, 300, 473, 1000] {
            for line in [LINE5, nameless] {
                let l = lay(width, &mods(line), &all);
                for t in &l.targets {
                    assert!(!t.name.trim().is_empty(), "{} at {width}", t.id);
                    assert!(!t.id.is_empty());
                }
            }
        }
        let l = lay(1000, &mods(LINE5), &four());
        let names: Vec<&str> = l.targets.iter().map(|t| t.name.as_str()).collect();
        assert_eq!(
            names,
            [
                "spark",
                "workspace 1",
                "workspace 2",
                "workspace 3",
                "net",
                "output",
                "output 60%",
                "mic",
                "clock"
            ]
        );
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
        let seen: Vec<(Option<i32>, &str, &str)> = all.iter().map(|w| (w.num, w.label(), w.output.as_str())).collect();
        // "N:" goes from the label; a name with nothing after it, or no colon, is shown whole
        assert_eq!(
            seen,
            [(Some(1), "1", "B"), (Some(2), "2:", "A"), (Some(3), "<3> mail", "A"), (None, "notes", "A")]
        );
        assert!(all[2].urgent && all[0].focused && all[1].visible);
        assert_eq!(ws(-1, "web:dev", "A", false, false, false).label(), "web:dev");
        assert_eq!(workspaces(&Value::Null), vec![]);
    }

    #[test]
    fn a_workspace_is_toned_by_where_it_is_shown_and_urgency_is_never_the_accent() {
        let all = vec![
            ws(1, "1:<1>", "A", false, false, false),
            ws(2, "2:<2>", "A", true, true, false),
            ws(3, "3:<3>", "A", false, false, true),
            ws(4, "4:<4>", "B", true, false, false),
            ws(5, "5:<5>", "B", false, false, false),
        ];
        let tones = |output: &str, all: &[Workspace]| {
            let scene = Scene {
                output,
                width: 1000,
                edge: Edge::Top,
                status: Status::Ok,
                modules: &[],
                workspaces: all,
                mode: None,
            };
            layout(&scene, &Prefs::default(), &M, &measure)
                .cells
                .iter()
                .filter_map(|c| match &c.paint {
                    Paint::Workspace { label, tone } => Some((label.clone(), *tone)),
                    _ => None,
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(
            tones("A", &all),
            [("<1>".into(), Tone::Other), ("<2>".into(), Tone::Focused), ("<3>".into(), Tone::Urgent)]
        );
        // the other output shows its own, without the focus
        assert_eq!(tones("B", &all), [("<4>".into(), Tone::Visible), ("<5>".into(), Tone::Other)]);
        // urgent on the focused one is still the attention mark
        let mut urgent = all.clone();
        urgent[1].urgent = true;
        assert_eq!(tones("A", &urgent)[1].1, Tone::Urgent);
        let l = lay(1000, &[], &all);
        let flags: Vec<(bool, bool, bool)> = l.targets[1..].iter().map(|t| (t.selected, t.urgent, t.visible)).collect();
        assert_eq!(flags, [(false, false, false), (true, false, true), (false, true, false)]);
    }

    #[test]
    fn before_the_first_line_and_after_a_break_a_muted_sign_stands_for_the_status() {
        for (status, sign) in [(Status::Loading, ELLIPSIS), (Status::Error, WARNING)] {
            // the last line's modules are not shown: the frame is, the mark and the workspaces
            let l = lay_with(1000, Edge::Top, status, &mods(LINE5), &four(), &Prefs::default());
            assert_eq!(ids(&l), ["mark", "workspace:1", "workspace:2", "workspace:3"]);
            let note = l.cells.last().unwrap();
            assert_eq!((note.rect, &note.paint, note.target), (Rect::new(970, 0, 20, 36), &Paint::Note(sign), None));
            assert!(l.dropped.is_empty());
        }
        assert!(ELLIPSIS == "\u{2026}" && WARNING.starts_with('\u{26a0}'));
    }

    #[test]
    fn the_trays_room_is_kept_clear_at_the_right_end() {
        let prefs = Prefs::new("", "", 96, "");
        let l = lay_with(1000, Edge::Top, Status::Ok, &mods(LINE5), &four(), &prefs);
        assert_eq!(rect_of(&l, "clock").right(), 894);
        assert_eq!(rect_of(&l, "mark").x, 10);
        // on the named output alone
        assert_eq!((Prefs::new("", "", 96, "A").tray_on("A"), Prefs::new("", "", 96, "B").tray_on("A")), (96, 0));
        let other = lay_with(1000, Edge::Top, Status::Ok, &mods(LINE5), &four(), &Prefs::new("", "", 96, "B"));
        assert_eq!(rect_of(&other, "clock").right(), 990);
        // the room counts against the width: what fits at 514 does not with 96 px less
        assert_eq!(
            lay_with(514, Edge::Top, Status::Ok, &mods(LINE5), &four(), &prefs).dropped,
            ["out.label", "net", "out"]
        );
        assert_eq!(Prefs::new("", "", -5, "").tray_width, 0);
        // a tray wider than the bar leaves the mark
        let l = lay_with(300, Edge::Top, Status::Ok, &mods(LINE5), &four(), &Prefs::new("", "", 5000, ""));
        assert_eq!(ids(&l), ["mark"]);
    }

    #[test]
    fn the_state_file_names_every_output_target_and_drop() {
        let l = lay(473, &mods(LINE5), &four());
        let bars = [Shown {
            output: "A",
            scale: 2,
            layout: &l,
            focus: l.find("workspace:2"),
            hover: l.find("mic"),
        }];
        let want = "bar\t1\n\
            status\tok\n\
            output\tA\t473\t36\ttop\t2\n\
            target\tA\tmark\t10\t0\t24\t36\tmark\tok\t-\tspark\n\
            target\tA\tworkspace:1\t44\t0\t40\t36\tworkspace\tok\t-\tworkspace 1\n\
            target\tA\tworkspace:2\t84\t0\t40\t36\tworkspace\tok\tfocused,selected,visible\tworkspace 2\n\
            target\tA\tworkspace:3\t124\t0\t40\t36\tworkspace\tok\t-\tworkspace 3\n\
            target\tA\tmore\t233\t0\t10\t36\topen\tok\t-\tmore\n\
            target\tA\tout.gauge\t263\t0\t80\t36\tlevel\tok\t-\toutput 60%\n\
            target\tA\tmic\t363\t0\t30\t36\ttoggle\tunavailable\thover\tmic\n\
            target\tA\tclock\t413\t0\t50\t36\topen\tok\t-\tclock\n\
            dropped\tA\tout.label\n\
            dropped\tA\tnet\n";
        assert_eq!(state_text(Status::Ok, None, &bars), want);
        // no output yet, and a broken status
        assert_eq!(state_text(Status::Loading, None, &[]), "bar\t1\nstatus\tloading\n");
        assert!(state_text(Status::Error, None, &bars).starts_with("bar\t1\nstatus\terror\noutput\tA\t"));
    }

    #[test]
    fn a_tab_or_a_line_end_in_a_name_cannot_break_the_state_file() {
        let m = mods(r#"[{"name":"a\tb","instance":"c\nd","full_text":"x","label":"one\ttwo\r\nthree"}]"#);
        let l = lay_with(
            1000,
            Edge::Bottom,
            Status::Ok,
            &m,
            &[ws(-1, "tab\there", "A\tB", true, true, false)],
            &Prefs::default(),
        );
        let text = state_text(
            Status::Ok,
            None,
            &[Shown {
                output: "A\tB",
                scale: 1,
                layout: &l,
                focus: None,
                hover: None,
            }],
        );
        for line in text.lines().skip(2) {
            let want = if line.starts_with("output") { 6 } else { 11 };
            assert_eq!(line.split('\t').count(), want, "{line:?}");
        }
        assert!(text.contains("\tbottom\t1\n") && text.contains("\tone two  three\n"));
    }

    #[test]
    fn no_width_panics_or_lays_one_rect_over_another() {
        let nameless = r#"[{"full_text":"a long text with no cells at all"},{"name":"x","full_text":"<b>bold</b>","optional":true}]"#;
        let mut many = four();
        many.push(ws(7, "7:<7> writing a long name", "A", false, false, true));
        many.push(ws(-1, "notes", "A", false, false, false));
        let prefs = [
            Prefs::default(),
            Prefs::new("", "clock net", 120, ""),
            Prefs::new("clock out workspaces", "out", 0, "A"),
        ];
        for width in (0..=3840).step_by(1) {
            for (line, status) in [(LINE5, Status::Ok), (nameless, Status::Ok), (LINE5, Status::Loading), ("[]", Status::Error)] {
                for p in &prefs {
                    let l = lay_with(width, Edge::Top, status, &mods(line), &many, p);
                    let mut rects: Vec<Rect> = l.cells.iter().map(|c| c.rect).collect();
                    rects.sort_by_key(|r| r.x);
                    for r in &rects {
                        assert!(r.w > 0 && r.h > 0, "{r:?} at {width}");
                    }
                    for p in rects.windows(2) {
                        assert!(p[0].right() <= p[1].x, "{:?} over {:?} at {width}", p[0], p[1]);
                    }
                    for t in &l.targets {
                        assert!(l.cells.iter().any(|c| c.target.is_some_and(|i| l.targets[i].id == t.id)));
                    }
                    if width >= 200 {
                        let last = rects.last().unwrap();
                        assert!(last.right() <= width - p.tray_on("A").min(width) || rects.len() == 1, "{last:?} past {width}");
                    }
                }
            }
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

    /// The whole look, after a block.
    const LOOKED: &str = r#"[{"name":"clock","full_text":"12:00","cells":5},
        {"name":"look","fg":"abb2bf","accent":"61afef","muted":"5c6370","ground":"282c34","lit":"3e4451","attention":"e06c75","alpha":"0.95"}],"#;

    fn look_of(line: &str) -> Look {
        parse_refresh(line).expect("a line").1
    }

    #[test]
    fn colors_and_the_alpha_are_read_as_the_environment_has_them() {
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
    }

    #[test]
    fn a_line_says_the_whole_look_in_its_block() {
        let (blocks, look) = parse_refresh(LOOKED).unwrap();
        assert_eq!(
            look,
            Look {
                fg: Some([0xab, 0xb2, 0xbf]),
                accent: Some([0x61, 0xaf, 0xef]),
                muted: Some([0x5c, 0x63, 0x70]),
                ground: Some([0x28, 0x2c, 0x34]),
                lit: Some([0x3e, 0x44, 0x51]),
                attention: Some([0xe0, 0x6c, 0x75]),
                alpha: Some(0.95),
            }
        );
        // the look is no block of the line
        assert_eq!(blocks.iter().map(Block::id).collect::<Vec<_>>(), ["clock"]);
    }

    #[test]
    fn a_look_names_the_slots_it_says_and_no_other() {
        let look = look_of(r#"[{"name":"look","ground":"282c34","alpha":"0.5"}]"#);
        assert_eq!(
            look,
            Look {
                ground: Some([0x28, 0x2c, 0x34]),
                alpha: Some(0.5),
                ..Look::default()
            }
        );
        // a look with nothing in it, and of two looks the last, whole
        assert_eq!(look_of(r#"[{"name":"look"}]"#), Look::default());
        let two = look_of(r#"[{"name":"look","fg":"abb2bf","alpha":"0.5"},{"name":"a","full_text":"x"},{"name":"look","accent":"61afef"}]"#);
        assert_eq!(
            two,
            Look {
                accent: Some([0x61, 0xaf, 0xef]),
                ..Look::default()
            }
        );
    }

    #[test]
    fn a_slot_a_look_gets_wrong_is_left_and_the_others_are_taken() {
        // too short, not hex, a number, null: left; with a # or blanks around it, as the environment takes it
        let look =
            look_of(r##"[{"name":"look","fg":"abb2b","accent":"gggggg","muted":7,"ground":null,"lit":"#3E4451","attention":" e06c75 ","alpha":"half"}]"##);
        assert_eq!(
            look,
            Look {
                lit: Some([0x3e, 0x44, 0x51]),
                attention: Some([0xe0, 0x6c, 0x75]),
                ..Look::default()
            }
        );
        // the alpha is a string, as BAR_ALPHA is: kept within 0 to 1, and nothing else is one
        let alpha_of = |said: &str| look_of(&format!(r#"[{{"name":"look","alpha":{said}}}]"#)).alpha;
        assert_eq!(
            (alpha_of(r#""1.5""#), alpha_of(r#""-1""#), alpha_of(r#"" 0.25 ""#)),
            (Some(1.0), Some(0.0), Some(0.25))
        );
        for bad in [r#""nan""#, r#""inf""#, r#""""#, "0.5", "true", "null", r#"["0.5"]"#] {
            assert_eq!(alpha_of(bad), None, "{bad}");
        }
    }

    #[test]
    fn a_line_without_a_look_says_none() {
        assert_eq!(look_of(LINE5), Look::default());
        assert_eq!(look_of("[]"), Look::default());
        // a block is the look by its name alone, and what is no refresh says no look either
        assert_eq!(
            look_of(r#"[{"name":"Look","fg":"abb2bf"},{"instance":"look","fg":"abb2bf"},"look"]"#),
            Look::default()
        );
        assert_eq!(parse_refresh(r#"{"version":1,"click_events":true}"#), None);
        assert_eq!(parse_refresh("["), None);
    }

    #[test]
    fn the_look_is_no_module_no_cell_and_no_target_and_takes_no_width() {
        // a look that says a text and cells as a block would, between a module's two blocks
        let look = r#"{"name":"look","instance":"x","full_text":"look","cells":9,"optional":true,"fg":"abb2bf","alpha":"0.5"},"#;
        let line = LINE5.replacen(r#"{"name":"out","instance":"gauge""#, &format!(r#"{look}{{"name":"out","instance":"gauge""#), 1);
        assert_ne!(look_of(&line), Look::default());
        assert_eq!(parse_line(&line), parse_line(LINE5));
        // the module it stands in is still one
        assert_eq!(mods(&line), mods(LINE5));
        assert!(!mods(&line).iter().any(|m| m.name == LOOK));
        for width in [0, 120, 304, 473, 513, 514, 1000] {
            let l = lay(width, &mods(&line), &four());
            assert_eq!(l, lay(width, &mods(LINE5), &four()), "at {width}");
            assert!(!l.dropped.iter().any(|d| d.starts_with(LOOK)) && l.find(LOOK).is_none() && l.find("look.x").is_none());
        }
        // pinned or named in the overflow, it is still none
        let prefs = Prefs::new("look clock", "look", 0, "");
        let l = lay_with(1000, Edge::Top, Status::Ok, &mods(&line), &four(), &prefs);
        assert_eq!(ids(&l), ["mark", "clock"]);
        // alone on its line: a refresh with no module
        assert_eq!(mods(r#"[{"name":"look","fg":"abb2bf"}]"#), vec![]);
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

    /// The bar on A in a binding mode.
    fn lay_mode(width: i32, status: Status, mode: &str, modules: &[Module], workspaces: &[Workspace], prefs: &Prefs) -> Layout {
        let scene = Scene {
            output: "A",
            width,
            edge: Edge::Top,
            status,
            modules,
            workspaces,
            mode: Some(mode),
        };
        layout(&scene, prefs, &M, &measure)
    }

    fn resize(width: i32, workspaces: &[Workspace]) -> Layout {
        lay_mode(width, Status::Ok, "resize", &mods(LINE5), workspaces, &Prefs::default())
    }

    /// The mode's cell: where it stands and the name it shows.
    fn mode_cell(l: &Layout) -> Option<(Rect, &str)> {
        l.cells.iter().find_map(|c| match &c.paint {
            Paint::Mode(name) => Some((c.rect, name.as_str())),
            _ => None,
        })
    }

    #[test]
    fn a_binding_mode_stands_one_cell_after_the_workspaces_and_is_no_target() {
        let (with, without) = (resize(1000, &four()), lay(1000, &mods(LINE5), &four()));
        // the workspaces end at 164; the name's six characters and half a cell at each side
        assert_eq!(mode_cell(&with), Some((Rect::new(174, 0, 70, 36), "resize")));
        assert_eq!(mode_cell(&without), None);
        // no target: every target is where it was, the pointer reaches nothing there and the keys pass it by
        assert_eq!((&with.targets, &with.dropped), (&without.targets, &without.dropped));
        assert!(with.cells.iter().all(|c| !matches!(c.paint, Paint::Mode(_)) || c.target.is_none()));
        assert_eq!((with.hit(200.0, 10.0), with.press(200.0, 10.0, 1)), (None, Act::Nothing));
        assert_eq!(with.key(3, Key::Tab), KeyAct::Focus(4));
        assert_eq!(with.targets[4].id, "net");
        // on an output with no workspace it stands where they would; a name with markup in it is plain text
        assert_eq!(mode_cell(&resize(1000, &[])), Some((Rect::new(44, 0, 70, 36), "resize")));
        let l = lay_mode(1000, Status::Ok, "<b>r</b>", &mods(LINE5), &four(), &Prefs::default());
        assert_eq!(mode_cell(&l), Some((Rect::new(174, 0, 90, 36), "<b>r</b>")));
        // before the first line and after a break it stands too
        for status in [Status::Loading, Status::Error] {
            let l = lay_mode(1000, status, "resize", &mods(LINE5), &four(), &Prefs::default());
            assert_eq!(mode_cell(&l), Some((Rect::new(174, 0, 70, 36), "resize")));
        }
    }

    #[test]
    fn workspaces_go_for_the_mode_the_farthest_first_and_the_status_never() {
        // 44 + 120 for the workspaces, 10 + 70 for the mode, 20, the status 320 and the edge 10: 594 fits whole
        assert!(resize(594, &four()).dropped.is_empty());
        // one pixel less: 3 and 1 are as far from 2, the later goes; the mode follows the workspaces left
        let l = resize(593, &four());
        assert_eq!(l.dropped, ["workspace:3"]);
        assert_eq!(mode_cell(&l), Some((Rect::new(134, 0, 70, 36), "resize")));
        // 514 only just holds the status and the three workspaces: the mode takes two of them and no block
        let l = resize(514, &four());
        assert_eq!(l.dropped, ["workspace:3", "workspace:1"]);
        assert_eq!(ids(&l), ["mark", "workspace:2", "net", "out.label", "out.gauge", "mic", "clock"]);
        assert_eq!(mode_cell(&l), Some((Rect::new(94, 0, 70, 36), "resize")));
        // at 513 the label goes as it does without a mode, and nothing more of the status
        let l = resize(513, &four());
        assert_eq!(l.dropped, ["out.label", "workspace:3", "workspace:1"]);
        assert_eq!(rect_of(&l, "out.gauge"), rect_of(&lay(513, &mods(LINE5), &four()), "out.gauge"));
        // an urgent workspace goes after the others, the one shown here never
        let urgent = vec![
            ws(1, "1:<1>", "A", false, false, false),
            ws(2, "2:<2>", "A", true, true, false),
            ws(3, "3:<3>", "A", false, false, true),
        ];
        assert_eq!(resize(593, &urgent).dropped, ["workspace:1"]);
        assert_eq!(resize(514, &urgent).dropped, ["workspace:1", "workspace:3"]);
        // no workspace left to go: the mode is cut where the status begins, then not drawn
        let l = resize(200, &four());
        assert_eq!(ids(&l), ["mark", "workspace:2", "more"]);
        assert_eq!(mode_cell(&l), Some((Rect::new(94, 0, 66, 36), "resize")));
        assert_eq!(rect_of(&l, MORE), Rect::new(180, 0, 10, 36));
        assert_eq!(mode_cell(&resize(135, &four())), Some((Rect::new(94, 0, 1, 36), "resize")));
        let l = resize(134, &four());
        assert_eq!(mode_cell(&l), None);
        assert_eq!(ids(&l), ["mark", "workspace:2", "more"]);
    }

    #[test]
    fn a_mode_moves_no_module_drops_none_and_lays_nothing_over_another() {
        let nameless = r#"[{"full_text":"a long text with no cells at all"},{"name":"x","full_text":"<b>bold</b>","optional":true}]"#;
        let mut many = four();
        many.push(ws(7, "7:<7> writing a long name", "A", false, false, true));
        many.push(ws(-1, "notes", "A", false, false, false));
        let prefs = [
            Prefs::default(),
            Prefs::new("", "clock net", 120, ""),
            Prefs::new("clock out workspaces", "out", 0, "A"),
            Prefs::new("clock out", "", 0, ""),
        ];
        // the status: every target that is no workspace, every cell that is none either, and what was left out of it
        let status_of = |l: &Layout| {
            let targets: Vec<Target> = l.targets.iter().filter(|t| t.kind != Kind::Workspace).cloned().collect();
            let cells: Vec<(Rect, Paint)> = l
                .cells
                .iter()
                .filter(|c| !matches!(c.paint, Paint::Workspace { .. } | Paint::Mode(_)))
                .map(|c| (c.rect, c.paint.clone()))
                .collect();
            let dropped: Vec<String> = l.dropped.iter().filter(|d| !d.starts_with("workspace:")).cloned().collect();
            (targets, cells, dropped)
        };
        let shown = |l: &Layout| -> Vec<String> { l.targets.iter().filter(|t| t.kind == Kind::Workspace).map(|t| t.id.clone()).collect() };
        for width in 0..=1400 {
            for (line, status) in [(LINE5, Status::Ok), (nameless, Status::Ok), (LINE5, Status::Loading), ("[]", Status::Error)] {
                for p in &prefs {
                    for name in ["resize", "a mode with a long name to stand in the bar"] {
                        let with = lay_mode(width, status, name, &mods(line), &many, p);
                        let without = lay_with(width, Edge::Top, status, &mods(line), &many, p);
                        assert_eq!(status_of(&with), status_of(&without), "{name:?} at {width}");
                        // the workspaces left are among those shown without it, in their order
                        let (kept, all) = (shown(&with), shown(&without));
                        assert!(all.iter().filter(|id| kept.contains(id)).eq(kept.iter()), "{kept:?} of {all:?} at {width}");
                        let mut rects: Vec<Rect> = with.cells.iter().map(|c| c.rect).collect();
                        rects.sort_by_key(|r| r.x);
                        for r in &rects {
                            assert!(r.w > 0 && r.h > 0, "{r:?} at {width}");
                        }
                        for pair in rects.windows(2) {
                            assert!(pair[0].right() <= pair[1].x, "{:?} over {:?} at {width}", pair[0], pair[1]);
                        }
                        // one cell at most: a cell after the workspaces, two cells before the status
                        assert!(with.cells.iter().filter(|c| matches!(c.paint, Paint::Mode(_))).count() <= 1);
                        if let Some((r, said)) = mode_cell(&with) {
                            assert_eq!(said, name);
                            let after = with.targets.iter().filter(|t| t.kind == Kind::Workspace).map(|t| t.rect.right()).max();
                            assert!(after.map_or(r.x == 44, |end| r.x == end + 10), "{r:?} after {after:?} at {width}");
                            let status_at = with.cells.iter().filter(|c| c.rect.x > r.x).map(|c| c.rect.x).min();
                            assert!(status_at.is_none_or(|x| r.right() + 20 <= x), "{r:?} before {status_at:?} at {width}");
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn the_state_file_says_the_mode_while_one_is_on() {
        let l = resize(1000, &four());
        let bars = [Shown {
            output: "A",
            scale: 1,
            layout: &l,
            focus: None,
            hover: None,
        }];
        let (on, off) = (state_text(Status::Ok, Some("resize"), &bars), state_text(Status::Ok, None, &bars));
        // one line after the status, and nothing else differs: the mode is no target
        assert!(on.starts_with("bar\t1\nstatus\tok\nmode\tresize\noutput\tA\t1000\t36\ttop\t1\n"));
        assert_eq!(on.replacen("mode\tresize\n", "", 1), off);
        assert!(!off.contains("mode"));
        // with no output yet, and a name that would break the file
        assert_eq!(state_text(Status::Loading, Some("resize"), &[]), "bar\t1\nstatus\tloading\nmode\tresize\n");
        assert_eq!(
            state_text(Status::Error, Some("re\tsize\r\nnow"), &[]),
            "bar\t1\nstatus\terror\nmode\tre size  now\n"
        );
    }
}
