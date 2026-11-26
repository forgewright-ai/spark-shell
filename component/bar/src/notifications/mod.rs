//! The notifications' stack: which cards show, where each stands and how it moves there, what a pointer or a
//! key does to them, and when one's time is up. Pure and tested: no surface, no bus, no clock but the one it
//! is handed (milliseconds). The server (lib/notifications.py) owns the list; this is what is on the screen
//! now. `ui` draws the frames it says and hands the pointer and the keys back to it.
//!
//! The newest card stands in front at the screen's edge. Closed, two older ones show behind it, each a
//! sliver, narrower and a shade off; open (the pointer over the stack, or the keys on it) they stand apart, a
//! list. A card dragged aside 45 pixels, or flicked, is dismissed. A card's time runs only while it is in
//! sight and the stack is closed. What waits out of sight (do not disturb, the idle screen) is the server's.

use serde_json::Value;
use spark_theme::scrub::scrub;
use unicode_width::UnicodeWidthChar;

#[cfg(target_os = "linux")]
pub mod ui;

/// The cards in sight while the stack is closed.
pub const SHOWN: usize = 3;
/// The cards listed while it is open, where the screen has the room; the rest are counted in one line.
pub const OPEN_MOST: usize = 8;
/// The body's lines on a card of a closed stack, and of an open one.
pub const BODY_CLOSED: usize = 3;
pub const BODY_OPEN: usize = 8;
/// A card dragged this far aside is dismissed when let go.
pub const SWIPE: f64 = 45.0;
/// Or let go while moving this fast, pixels a millisecond, having gone a little way.
pub const FLICK: f64 = 0.5;
pub const FLICK_WAY: f64 = 12.0;
/// A press that moved less than this is a click.
pub const CLICK: f64 = 4.0;
/// How long a card takes to its place, and to leave.
pub const MOVE_MS: u64 = 200;
pub const LEAVE_MS: u64 = 150;
/// The actions a card shows as buttons.
pub const CHIPS: usize = 2;
const TEXT_MOST: usize = 1000;
/// The longest a card's time may be, an hour: the server says far less.
const TIME_MOST: u64 = 3_600_000;
const CHIP_CELLS: usize = 14;

pub const ANGLE: &str = "\u{276f}";
pub const CLOSE: &str = "\u{00d7}";
pub const OPENS: &str = "\u{25b8}";
const ELLIPSIS: char = '\u{2026}';

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Urgency {
    Low,
    Normal,
    Critical,
}

/// A notification as the server hands it over, every text scrubbed.
#[derive(Clone, Debug, PartialEq)]
pub struct Note {
    pub id: u32,
    pub app: String,
    pub summary: String,
    /// The body's own lines.
    pub body: Vec<String>,
    pub urgency: Urgency,
    pub category: String,
    /// The actions an app offers: its key and its words.
    pub actions: Vec<(String, String)>,
    /// How long it stays in sight; none stays until it is dismissed.
    pub ms: Option<u64>,
}

fn text(v: &Value, key: &str) -> String {
    let s = v.get(key).and_then(Value::as_str).unwrap_or("");
    scrub(&s.chars().take(TEXT_MOST).collect::<String>()).trim().to_string()
}

impl Note {
    /// The server's record; none when it has no id.
    pub fn of(v: &Value) -> Option<Note> {
        let id = u32::try_from(v.get("id")?.as_u64()?).ok().filter(|i| *i > 0)?;
        let body = v.get("body").and_then(Value::as_str).unwrap_or("");
        let body: String = body.chars().take(TEXT_MOST).collect();
        let actions = v
            .get("actions")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|p| Some((p.get(0)?.as_str()?.to_string(), scrub(p.get(1)?.as_str()?).trim().to_string())))
                    .take(8)
                    .collect()
            })
            .unwrap_or_default();
        Some(Note {
            id,
            app: text(v, "app"),
            summary: text(v, "summary"),
            body: body.lines().map(|l| scrub(l).trim_end().to_string()).filter(|l| !l.trim().is_empty()).collect(),
            urgency: match v.get("urgency").and_then(Value::as_u64) {
                Some(0) => Urgency::Low,
                Some(2) => Urgency::Critical,
                _ => Urgency::Normal,
            },
            category: text(v, "category"),
            actions,
            ms: v.get("ms").and_then(Value::as_u64).filter(|ms| *ms > 0).map(|ms| ms.min(TIME_MOST)),
        })
    }

    /// The sign before the summary: the kind where the app names one, a warning on a critical one.
    pub fn sign(&self) -> &'static str {
        if self.urgency == Urgency::Critical {
            return "\u{26a0}";
        }
        match self.category.as_str() {
            "email" | "email.arrived" => "\u{2261}",
            "transfer.complete" => "\u{2713}",
            "transfer.error" => "\u{2717}",
            "device.added" => "\u{25ad}",
            "x-spark-shell.reminder" => "\u{29d7}",
            _ => "\u{25cf}",
        }
    }

    /// What a click on the card does, in the app's words; none when it offers no default action.
    fn default_words(&self) -> Option<&str> {
        self.actions.iter().find(|(k, _)| k == "default").map(|(_, w)| w.as_str())
    }
}

/// The sizes a card is laid out by, in logical pixels: a cell and a line of the face, the air inside a card,
/// its width, the room between two cards of an open stack, the sliver a card behind shows and how much
/// narrower each one behind is at each side.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Metrics {
    pub cell: f64,
    pub line: f64,
    pub pad_x: f64,
    pub pad_y: f64,
    pub width: f64,
    pub gap: f64,
    pub peek: f64,
    pub inset: f64,
}

impl Metrics {
    /// For a face of `px` pixels whose cell is `cell` wide, a card `width` wide with `pad_x` and `pad_y` of air.
    pub fn new(px: f64, cell: f64, width: f64, pad_x: f64, pad_y: f64) -> Metrics {
        let width = width.max(cell * 16.0 + 2.0 * pad_x);
        Metrics {
            cell,
            line: (px * 1.5).round(),
            pad_x,
            pad_y,
            width,
            gap: 8.0,
            peek: (px * 0.625).round(),
            inset: (width * 0.035).round(),
        }
    }

    /// The cells of text a card's line holds.
    pub fn cells(&self) -> usize {
        (((self.width - 2.0 * self.pad_x) / self.cell).floor() as usize).max(8)
    }
}

/// The cells a character takes in the face: two for a wide one (Chinese, Japanese, Korean, most emoji), none
/// for one that joins the one before.
fn wide(c: char) -> usize {
    UnicodeWidthChar::width(c).unwrap_or(0)
}

/// The cells a text takes.
pub fn cells_of(s: &str) -> usize {
    s.chars().map(wide).sum()
}

/// A text cut to `cells` cells, an ellipsis its last when it was longer.
pub fn cut(s: &str, cells: usize) -> String {
    if cells_of(s) <= cells {
        return s.to_string();
    }
    let (mut out, mut n) = (String::new(), 0);
    for c in s.chars() {
        if n + wide(c) + 1 > cells {
            break;
        }
        out.push(c);
        n += wide(c);
    }
    out.truncate(out.trim_end().len());
    out.push(ELLIPSIS);
    out
}

/// A text's lines of `cells` cells at most, broken at blanks; a word longer than a line is broken in it.
pub fn wrap(s: &str, cells: usize) -> Vec<String> {
    let mut lines = vec![];
    let mut line = String::new();
    let mut n = 0;
    for mut word in s.split_whitespace() {
        loop {
            let room = if n == 0 { cells } else { cells.saturating_sub(n + 1) };
            let w = cells_of(word);
            if w <= room {
                if n > 0 {
                    line.push(' ');
                    n += 1;
                }
                line.push_str(word);
                n += w;
                break;
            }
            if n > 0 {
                lines.push(std::mem::take(&mut line));
                n = 0;
                continue;
            }
            // longer than a line: as much of it as a line holds, one character at least
            let (mut took, mut end) = (0, 0);
            for (i, c) in word.char_indices() {
                if end > 0 && took + wide(c) > cells {
                    break;
                }
                took += wide(c);
                end = i + c.len_utf8();
            }
            lines.push(word[..end].to_string());
            word = &word[end..];
        }
    }
    if n > 0 {
        lines.push(line);
    }
    lines
}

/// Where a card stands: its distance from the screen's edge, how far it is aside, its size, how solid it is
/// and how solid its text.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pose {
    pub d: f64,
    pub x: f64,
    pub w: f64,
    pub h: f64,
    pub alpha: f64,
    pub text: f64,
}

impl Pose {
    fn toward(self, to: Pose, part: f64) -> Pose {
        let mix = |a: f64, b: f64| a + (b - a) * part;
        Pose {
            d: mix(self.d, to.d),
            x: mix(self.x, to.x),
            w: mix(self.w, to.w),
            h: mix(self.h, to.h),
            alpha: mix(self.alpha, to.alpha),
            text: mix(self.text, to.text),
        }
    }
}

/// How far a move is at `t` of its time: eased out, as the bar's numbers flow.
fn ease(t: f64) -> f64 {
    crate::bar::ease(t)
}

/// A card: a notification laid out for the face, its time, and the move it is making.
#[derive(Clone, Debug)]
struct Card {
    note: Note,
    /// The app's line, the summary's and the body's, each cut to the card.
    head: String,
    title: String,
    body: Vec<String>,
    /// The actions shown as buttons: key and words.
    chips: Vec<(String, String)>,
    /// The time it still has; none stays. `since` is when that time last began to run.
    left: Option<u64>,
    since: Option<u64>,
    /// Where it was when its move began, and when that was.
    from: Pose,
    t0: u64,
}

impl Card {
    fn new(note: Note, m: &Metrics) -> Card {
        let cells = m.cells();
        let head = match note.default_words().filter(|w| !w.is_empty() && !w.eq_ignore_ascii_case("default")) {
            Some(words) => format!("{} {OPENS} {words}", note.app),
            None => note.app.clone(),
        };
        let body = note.body.iter().flat_map(|l| wrap(l, cells)).collect();
        let chips = note
            .actions
            .iter()
            .filter(|(k, w)| k != "default" && !w.is_empty())
            .take(CHIPS)
            .map(|(k, w)| (k.clone(), cut(w, CHIP_CELLS)))
            .collect();
        Card {
            head: cut(&head, cells.saturating_sub(4)),
            title: cut(&note.summary, cells.saturating_sub(2)),
            body,
            chips,
            left: note.ms,
            since: None,
            from: Pose {
                d: 0.0,
                x: 0.0,
                w: m.width,
                h: 0.0,
                alpha: 0.0,
                text: 0.0,
            },
            t0: 0,
            note,
        }
    }

    /// The body's lines it shows: the first few, the last one ending in an ellipsis when there are more.
    fn lines(&self, open: bool) -> Vec<String> {
        let most = if open { BODY_OPEN } else { BODY_CLOSED };
        let mut lines: Vec<String> = self.body.iter().take(most).cloned().collect();
        if self.body.len() > most {
            if let Some(last) = lines.last_mut() {
                // the ellipsis takes the place of the line's end: a cell at least
                while let Some(c) = last.pop() {
                    if wide(c) > 0 {
                        break;
                    }
                }
                last.push(ELLIPSIS);
            }
        }
        lines
    }

    fn height(&self, m: &Metrics, open: bool) -> f64 {
        let lines = 2 + self.body.len().min(if open { BODY_OPEN } else { BODY_CLOSED });
        let chips = if self.chips.is_empty() { 0.0 } else { m.line + (m.pad_y / 2.0).round() };
        2.0 * m.pad_y + m.line * lines as f64 + chips
    }
}

/// A card on its way out: drawn until it has faded.
#[derive(Clone, Debug)]
struct Gone {
    card: Card,
    from: Pose,
    to: Pose,
    t0: u64,
    /// The place it had in the stack, for its shade.
    place: usize,
}

/// A press held on a card.
#[derive(Clone, Copy, Debug)]
struct Drag {
    id: u32,
    at: (f64, f64),
    part: Part,
    dx: f64,
    moved: bool,
    /// The pointer's last two places in time, for the speed it is let go at.
    last: (f64, u64),
    before: (f64, u64),
}

/// The part of a card a pointer is on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part {
    Card,
    Close,
    Chip(usize),
}

/// What the person did, for the server.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    Expired(u32),
    Dismissed(u32),
    Action(u32, String),
    /// The ones on the screen were looked at: the stack was opened.
    Seen,
}

impl Event {
    /// The line the server reads.
    pub fn json(&self) -> String {
        match self {
            Event::Expired(id) => serde_json::json!({"event": "expired", "id": id}),
            Event::Dismissed(id) => serde_json::json!({"event": "dismissed", "id": id}),
            Event::Action(id, key) => serde_json::json!({"event": "action", "id": id, "key": key}),
            Event::Seen => serde_json::json!({"event": "seen"}),
        }
        .to_string()
    }
}

/// A key the open stack takes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Up,
    Down,
    Activate,
    Delete,
    Escape,
}

impl Key {
    /// A keysym (X11's keysymdef.h), as the layout names the key.
    pub fn of_sym(sym: u32) -> Option<Key> {
        match sym {
            0xff52 | 0xff97 => Some(Key::Up),
            0xff54 | 0xff99 => Some(Key::Down),
            0xff0d | 0xff8d | 0x20 => Some(Key::Activate),
            0xffff | 0xff08 | 0xff9f => Some(Key::Delete),
            0xff1b => Some(Key::Escape),
            _ => None,
        }
    }

    /// An evdev code, by its place on a US keyboard: where no keymap can be read.
    pub fn of_evdev(code: u32) -> Option<Key> {
        match code {
            103 => Some(Key::Up),
            108 => Some(Key::Down),
            28 | 96 | 57 => Some(Key::Activate),
            111 | 14 => Some(Key::Delete),
            1 => Some(Key::Escape),
            _ => None,
        }
    }
}

/// The tone a thing is drawn in; `ui` has the look's color for each.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Tone {
    Ground,
    /// The ground of a card behind the front one, by its place: a shade off for each.
    Behind(usize),
    /// The card the pointer or the keys are on, and a button.
    Lit,
    Text,
    Dim,
    Accent,
    Alert,
}

/// One thing of a frame, in logical pixels from the surface's top left.
#[derive(Clone, Debug, PartialEq)]
pub enum Draw {
    Fill {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        tone: Tone,
        alpha: f64,
    },
    /// A line of text in a box: set at its left, in the middle of its height, cut at its width.
    Text {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        text: String,
        tone: Tone,
        bold: bool,
        alpha: f64,
    },
}

/// A place on the surface.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl Rect {
    fn holds(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
}

pub struct Stack {
    m: Metrics,
    /// The stack hangs from the screen's top edge; else it stands on the bottom one.
    top: bool,
    motion: bool,
    /// Newest first.
    cards: Vec<Card>,
    gone: Vec<Gone>,
    /// The pointer is over the stack.
    inside: bool,
    /// The keys are on it (Super+N).
    keys: bool,
    hover: Option<usize>,
    sel: usize,
    drag: Option<Drag>,
    /// The surface's size before the last change, held until the move from it is over.
    held: (f64, f64),
    held_until: u64,
    /// The height the screen has for the stack.
    room: f64,
}

impl Stack {
    pub fn new(m: Metrics, top: bool, motion: bool) -> Stack {
        Stack {
            m,
            top,
            motion,
            cards: vec![],
            gone: vec![],
            inside: false,
            keys: false,
            hover: None,
            sel: 0,
            drag: None,
            held: (0.0, 0.0),
            held_until: 0,
            room: f64::INFINITY,
        }
    }

    /// The height the screen has for the stack: an open one lists no more cards than it holds.
    pub fn room(&mut self, room: f64, now: u64) {
        if room != self.room {
            self.settle(now);
            self.room = room;
            self.after(now);
        }
    }

    /// The cards an open stack lists: the newest ones, as many as the room holds with the line that counts the
    /// rest, one at least and OPEN_MOST at most.
    fn listed(&self) -> usize {
        let m = &self.m;
        let (mut h, mut n) = (0.0, 0);
        for c in self.cards.iter().take(OPEN_MOST) {
            let next = h + c.height(m, true) + if n > 0 { m.gap } else { 0.0 };
            let more = if n + 1 < self.cards.len() { m.gap + m.line } else { 0.0 };
            if n > 0 && next + more > self.room {
                break;
            }
            (h, n) = (next, n + 1);
        }
        n
    }

    /// A new look: the cards laid out again for it, where they are.
    pub fn look(&mut self, m: Metrics, top: bool, motion: bool, now: u64) {
        self.settle(now);
        (self.m, self.top, self.motion) = (m, top, motion);
        for c in &mut self.cards {
            let (left, since) = (c.left, c.since);
            let mut laid = Card::new(c.note.clone(), &m);
            (laid.left, laid.since, laid.from, laid.t0) = (left, since, c.from, c.t0);
            *c = laid;
        }
        self.after(now);
    }

    pub fn is_empty(&self) -> bool {
        self.cards.is_empty()
    }

    /// Open: the cards stand apart, each whole.
    pub fn open(&self) -> bool {
        !self.cards.is_empty() && (self.inside || self.keys)
    }

    /// The keys are the stack's.
    pub fn wants_keys(&self) -> bool {
        self.keys && !self.cards.is_empty()
    }

    /// A critical one is in sight: it shows over a full-screen window too.
    pub fn critical(&self) -> bool {
        self.cards.iter().take(SHOWN).any(|c| c.note.urgency == Urgency::Critical)
    }

    // --- the moves
    fn span(&self) -> u64 {
        if self.motion {
            MOVE_MS
        } else {
            0
        }
    }

    /// Where each card is to stand, in the stack's order.
    fn targets(&self) -> Vec<Pose> {
        let m = &self.m;
        let mut out = Vec::with_capacity(self.cards.len());
        if self.open() {
            let (mut d, listed) = (0.0, self.listed());
            for (i, c) in self.cards.iter().enumerate() {
                if i < listed {
                    let h = c.height(m, true);
                    out.push(Pose {
                        d,
                        x: 0.0,
                        w: m.width,
                        h,
                        alpha: 1.0,
                        text: 1.0,
                    });
                    d += h + m.gap;
                } else {
                    out.push(Pose {
                        d: (d - m.gap).max(0.0),
                        x: 0.0,
                        w: m.width,
                        h: 0.0,
                        alpha: 0.0,
                        text: 0.0,
                    });
                }
            }
        } else {
            let h0 = self.cards.first().map_or(0.0, |c| c.height(m, false));
            for i in 0..self.cards.len() {
                let k = i.min(SHOWN - 1) as f64;
                out.push(Pose {
                    d: m.peek * k,
                    x: m.inset * k,
                    w: m.width - 2.0 * m.inset * k,
                    h: h0,
                    alpha: if i < SHOWN { 1.0 } else { 0.0 },
                    text: if i == 0 { 1.0 } else { 0.0 },
                });
            }
        }
        out
    }

    fn at(from: Pose, to: Pose, t0: u64, span: u64, now: u64) -> Pose {
        if span == 0 || now >= t0 + span {
            to
        } else {
            from.toward(to, ease(now.saturating_sub(t0) as f64 / span as f64))
        }
    }

    /// Where each card is now, on its way.
    fn poses(&self, now: u64) -> Vec<Pose> {
        let span = self.span();
        self.targets()
            .into_iter()
            .zip(&self.cards)
            .map(|(to, c)| Stack::at(c.from, to, c.t0, span, now))
            .collect()
    }

    /// Before a change: each card's move starts again from where it is now, and the surface keeps its size
    /// until the move is over.
    fn settle(&mut self, now: u64) {
        let size = self.size(now);
        let poses = self.poses(now);
        for (c, p) in self.cards.iter_mut().zip(poses) {
            (c.from, c.t0) = (p, now);
        }
        self.held = size;
        self.held_until = now + if self.motion { MOVE_MS.max(LEAVE_MS) } else { 0 };
    }

    /// The cards in sight: the ones an open stack lists, the front ones of a closed one.
    fn most(&self) -> usize {
        if self.open() {
            self.listed()
        } else {
            SHOWN
        }
    }

    /// After a change: the keys and the pointer's card kept within the cards there are, the times running or held.
    /// With no card left the surface goes, and the pointer and the keys with it: the next card starts closed.
    fn after(&mut self, now: u64) {
        if self.cards.is_empty() {
            (self.keys, self.inside, self.hover, self.drag, self.sel) = (false, false, None, None, 0);
        }
        self.sel = self.sel.min(self.listed().saturating_sub(1));
        if self.hover.is_some_and(|h| h >= self.cards.len()) {
            self.hover = None;
        }
        let run = !self.open() && self.drag.is_none();
        for (i, c) in self.cards.iter_mut().enumerate() {
            let runs = run && i < SHOWN && c.left.is_some();
            match (runs, c.since) {
                (true, None) => c.since = Some(now),
                (false, Some(since)) => {
                    c.left = c.left.map(|l| l.saturating_sub(now.saturating_sub(since)).max(1));
                    c.since = None;
                }
                _ => {}
            }
        }
        self.gone.retain(|g| now < g.t0 + LEAVE_MS);
    }

    /// The surface's size: what the stack takes, and while a move goes on what it took before as well.
    pub fn size(&self, now: u64) -> (f64, f64) {
        let m = &self.m;
        let (mut w, mut h) = (0.0, 0.0);
        let targets = self.targets();
        let most = self.most();
        if let Some(last) = targets.len().min(most).checked_sub(1).map(|i| targets[i]) {
            (w, h) = (m.width, last.d + last.h);
            if self.open() && self.cards.len() > most {
                h += m.gap + m.line;
            }
        }
        if now < self.held_until {
            (w, h) = (w.max(self.held.0), h.max(self.held.1));
        }
        (w.ceil(), h.ceil())
    }

    /// Whether anything is on its way: the next frame is wanted.
    pub fn moving(&self, now: u64) -> bool {
        let span = self.span();
        self.gone.iter().any(|g| now < g.t0 + LEAVE_MS) || self.cards.iter().any(|c| now < c.t0 + span) || now < self.held_until
    }

    /// When the next card's time is up, if one's runs.
    pub fn deadline(&self) -> Option<u64> {
        self.cards.iter().filter_map(|c| Some(c.since?.saturating_add(c.left?))).min()
    }

    fn leave(&mut self, i: usize, now: u64, aside: bool) {
        let from = self.poses(now)[i];
        let card = self.cards.remove(i);
        let dx = self.drag.filter(|d| d.id == card.note.id).map_or(0.0, |d| d.dx);
        let from = Pose { x: from.x + dx, ..from };
        let to = if aside {
            Pose {
                x: from.x + self.m.width * 0.6,
                alpha: 0.0,
                ..from
            }
        } else {
            Pose { alpha: 0.0, ..from }
        };
        if self.motion {
            self.gone.push(Gone {
                card,
                from,
                to,
                t0: now,
                place: i,
            });
        }
        if self.drag.is_some_and(|d| !self.cards.iter().any(|c| c.note.id == d.id)) {
            self.drag = None;
        }
    }

    // --- what the server says
    /// A notification to show: a new one comes in at the front; one that is there already is changed in place.
    pub fn show(&mut self, note: Note, now: u64) {
        self.settle(now);
        let mut card = Card::new(note, &self.m);
        if let Some(i) = self.cards.iter().position(|c| c.note.id == card.note.id) {
            (card.from, card.t0) = (self.cards[i].from, self.cards[i].t0);
            self.cards[i] = card;
        } else {
            self.cards.insert(0, card);
            let to = self.targets()[0];
            // it comes in from beyond the edge, fading in
            (self.cards[0].from, self.cards[0].t0) = (
                Pose {
                    d: to.d - self.m.line,
                    alpha: 0.0,
                    text: 1.0,
                    ..to
                },
                now,
            );
            if let Some(h) = self.hover.as_mut() {
                *h += 1;
            }
            if self.keys {
                self.sel += 1;
            }
        }
        self.after(now);
    }

    /// The server closed one: it fades where it is.
    pub fn close(&mut self, id: u32, now: u64) {
        let Some(i) = self.cards.iter().position(|c| c.note.id == id) else { return };
        self.settle(now);
        self.leave(i, now, false);
        self.after(now);
    }

    /// Super+N: the stack opens and takes the keys, the newest card chosen.
    pub fn open_keys(&mut self, now: u64) -> Vec<Event> {
        if self.cards.is_empty() || self.keys {
            return vec![];
        }
        let was = self.open();
        self.settle(now);
        (self.keys, self.sel) = (true, 0);
        self.after(now);
        if was {
            vec![]
        } else {
            vec![Event::Seen]
        }
    }

    // --- the clock
    /// The cards whose time is up leave.
    pub fn tick(&mut self, now: u64) -> Vec<Event> {
        let due: Vec<u32> = self
            .cards
            .iter()
            .filter(|c| matches!((c.since, c.left), (Some(s), Some(l)) if now >= s.saturating_add(l)))
            .map(|c| c.note.id)
            .collect();
        if due.is_empty() {
            self.gone.retain(|g| now < g.t0 + LEAVE_MS);
            return vec![];
        }
        self.settle(now);
        for id in &due {
            if let Some(i) = self.cards.iter().position(|c| c.note.id == *id) {
                self.leave(i, now, false);
            }
        }
        self.after(now);
        due.into_iter().map(Event::Expired).collect()
    }

    // --- the pointer
    /// A card's place on a surface `height` tall.
    fn rect(&self, p: &Pose, height: f64) -> Rect {
        let y = if self.top { p.d } else { height - p.d - p.h };
        Rect { x: p.x, y, w: p.w, h: p.h }
    }

    /// The card and its part under a place: the front ones first.
    pub fn hit(&self, x: f64, y: f64, now: u64, height: f64) -> Option<(usize, Part)> {
        let poses = self.poses(now);
        let most = self.most();
        for (i, p) in poses.iter().enumerate().take(most) {
            let r = self.rect(p, height);
            if p.alpha < 0.5 || !r.holds(x, y) {
                continue;
            }
            if self.open() || i == 0 {
                if self.close_rect(&r).holds(x, y) && self.open() {
                    return Some((i, Part::Close));
                }
                for (k, chip) in self.chip_rects(&self.cards[i], &r).iter().enumerate() {
                    if chip.holds(x, y) {
                        return Some((i, Part::Chip(k)));
                    }
                }
            }
            return Some((i, Part::Card));
        }
        None
    }

    fn close_rect(&self, r: &Rect) -> Rect {
        let m = &self.m;
        Rect {
            x: r.x + r.w - m.pad_x - 2.0 * m.cell,
            y: r.y + m.pad_y,
            w: 2.0 * m.cell + m.pad_x,
            h: m.line,
        }
    }

    fn chip_rects(&self, card: &Card, r: &Rect) -> Vec<Rect> {
        let m = &self.m;
        let mut x = r.x + m.pad_x;
        let y = r.y + r.h - m.pad_y - m.line;
        card.chips
            .iter()
            .map(|(_, words)| {
                let w = (cells_of(words) + 2) as f64 * m.cell;
                let rect = Rect { x, y, w, h: m.line };
                x += w + m.cell;
                rect
            })
            .collect()
    }

    /// The pointer came over the stack, or moved on it.
    pub fn point(&mut self, x: f64, y: f64, now: u64, height: f64) -> Vec<Event> {
        if let Some(d) = self.drag.as_mut() {
            d.dx = (x - d.at.0).max(0.0);
            d.moved |= (x - d.at.0).hypot(y - d.at.1) >= CLICK;
            if now > d.last.1 {
                (d.before, d.last) = (d.last, (x, now));
            }
            return vec![];
        }
        let was = self.open();
        if !self.inside {
            self.settle(now);
            self.inside = true;
        }
        self.hover = self.hit(x, y, now, height).map(|(i, _)| i);
        self.after(now);
        if was || self.cards.is_empty() {
            vec![]
        } else {
            vec![Event::Seen]
        }
    }

    /// The pointer left the stack: it closes, unless the keys hold it open. A card held aside goes back.
    pub fn leave_pointer(&mut self, now: u64) {
        if !self.inside && self.drag.is_none() {
            return;
        }
        self.settle(now);
        self.back(now);
        (self.inside, self.hover) = (false, None);
        self.after(now);
    }

    /// A card held aside goes back to its place.
    fn back(&mut self, now: u64) {
        if let Some(d) = self.drag.take() {
            if let Some(c) = self.cards.iter_mut().find(|c| c.note.id == d.id) {
                (c.from.x, c.t0) = (c.from.x + d.dx, now);
            }
        }
    }

    /// A button pressed: 1 holds the card for a click or a swipe, 2 dismisses every one, 3 the one under it.
    pub fn press(&mut self, x: f64, y: f64, button: u32, now: u64, height: f64) -> Vec<Event> {
        let Some((i, part)) = self.hit(x, y, now, height) else { return vec![] };
        match button {
            1 => {
                self.settle(now);
                self.drag = Some(Drag {
                    id: self.cards[i].note.id,
                    at: (x, y),
                    part,
                    dx: 0.0,
                    moved: false,
                    last: (x, now),
                    before: (x, now),
                });
                self.after(now);
                vec![]
            }
            2 => self.dismiss_all(now),
            3 => self.dismiss(i, now, false),
            _ => vec![],
        }
    }

    /// The button let go: a click does what the part it was on does; a card let go aside leaves or goes back.
    pub fn release(&mut self, now: u64) -> Vec<Event> {
        let Some(d) = self.drag else { return vec![] };
        let Some(i) = self.cards.iter().position(|c| c.note.id == d.id) else {
            self.drag = None;
            return vec![];
        };
        if !d.moved {
            self.drag = None;
            return match d.part {
                Part::Close => self.dismiss(i, now, false),
                Part::Chip(k) => match self.cards[i].chips.get(k).map(|(key, _)| key.clone()) {
                    Some(key) => self.act(i, key, now),
                    None => vec![],
                },
                Part::Card => self.act_default(i, now),
            };
        }
        let took = now.saturating_sub(d.before.1).max(1) as f64;
        let speed = (d.last.0 - d.before.0) / took;
        if d.dx >= SWIPE || (d.dx >= FLICK_WAY && speed >= FLICK) {
            return self.dismiss(i, now, true);
        }
        self.settle(now);
        self.back(now);
        self.after(now);
        vec![]
    }

    fn dismiss(&mut self, i: usize, now: u64, aside: bool) -> Vec<Event> {
        let id = self.cards[i].note.id;
        self.settle(now);
        self.leave(i, now, aside);
        self.drag = None;
        self.after(now);
        vec![Event::Dismissed(id)]
    }

    fn dismiss_all(&mut self, now: u64) -> Vec<Event> {
        let ids: Vec<u32> = self.cards.iter().map(|c| c.note.id).collect();
        self.settle(now);
        while !self.cards.is_empty() {
            self.leave(0, now, false);
        }
        self.after(now);
        ids.into_iter().map(Event::Dismissed).collect()
    }

    fn act(&mut self, i: usize, key: String, now: u64) -> Vec<Event> {
        let id = self.cards[i].note.id;
        self.settle(now);
        self.leave(i, now, false);
        self.after(now);
        vec![Event::Action(id, key)]
    }

    /// A click on a card, or Enter on it: what its app offers, when it offers something.
    fn act_default(&mut self, i: usize, now: u64) -> Vec<Event> {
        if self.cards[i].note.default_words().is_some() {
            self.act(i, "default".into(), now)
        } else {
            vec![]
        }
    }

    // --- the keys
    pub fn key(&mut self, key: Key, now: u64) -> Vec<Event> {
        if !self.wants_keys() {
            return vec![];
        }
        let last = self.listed().max(1) - 1;
        // up is toward the screen's top: the front card hangs there, or stands at the bottom
        let (up, down) = if self.top {
            (self.sel.saturating_sub(1), (self.sel + 1).min(last))
        } else {
            ((self.sel + 1).min(last), self.sel.saturating_sub(1))
        };
        match key {
            Key::Up => self.sel = up,
            Key::Down => self.sel = down,
            Key::Activate => return self.act_default(self.sel, now),
            Key::Delete => return self.dismiss(self.sel, now, false),
            Key::Escape => {
                self.settle(now);
                self.keys = false;
                self.after(now);
            }
        }
        vec![]
    }

    // --- the frame
    /// The places that take the pointer on a surface `height` tall: the cards in sight, and the room between
    /// them while the stack is open, so the pointer never falls through on its way from one to the next.
    pub fn regions(&self, now: u64, height: f64) -> Vec<Rect> {
        let poses = self.poses(now);
        let most = self.most();
        let mut rects: Vec<Rect> = poses
            .iter()
            .take(most)
            .filter(|p| p.alpha > 0.0 && p.h > 0.0)
            .map(|p| self.rect(p, height))
            .collect();
        if self.open() {
            if let (Some(first), Some(last)) = (poses.first(), poses.len().min(most).checked_sub(1).map(|i| &poses[i])) {
                let whole = Pose {
                    d: first.d,
                    h: last.d + last.h - first.d,
                    ..*first
                };
                rects = vec![self.rect(&whole, height)];
            }
        }
        rects
    }

    /// What to draw now on a surface `height` tall: the cards from the back to the front, then the ones leaving.
    pub fn frame(&self, now: u64, height: f64) -> Vec<Draw> {
        let mut out = vec![];
        let open = self.open();
        let poses = self.poses(now);
        let lit = if self.keys { Some(self.sel) } else { self.hover.filter(|_| open) };
        for (i, (c, p)) in self.cards.iter().zip(&poses).enumerate().rev() {
            if p.alpha <= 0.0 || p.h <= 0.0 {
                continue;
            }
            let dx = self.drag.filter(|d| d.id == c.note.id).map_or(0.0, |d| d.dx);
            let p = Pose {
                x: p.x + dx,
                alpha: p.alpha * (1.0 - (dx / (self.m.width * 0.8)).clamp(0.0, 0.7)),
                ..*p
            };
            let ground = if lit == Some(i) {
                Tone::Lit
            } else if open || i == 0 {
                Tone::Ground
            } else {
                Tone::Behind(i.min(SHOWN - 1))
            };
            self.card(&mut out, c, &p, ground, open, lit == Some(i), height);
        }
        let listed = self.listed();
        if open && self.cards.len() > listed {
            if let Some(last) = listed.checked_sub(1).and_then(|i| poses.get(i)) {
                let r = self.rect(
                    &Pose {
                        d: last.d + last.h + self.m.gap,
                        h: self.m.line,
                        ..*last
                    },
                    height,
                );
                let text = format!("{OPENS} and {} more", self.cards.len() - listed);
                out.push(Draw::Text {
                    x: r.x + self.m.pad_x,
                    y: r.y,
                    w: r.w - 2.0 * self.m.pad_x,
                    h: r.h,
                    text,
                    tone: Tone::Dim,
                    bold: false,
                    alpha: last.alpha,
                });
            }
        }
        for g in &self.gone {
            let p = Stack::at(g.from, g.to, g.t0, LEAVE_MS, now);
            if p.alpha > 0.0 {
                let ground = if open || g.place == 0 {
                    Tone::Ground
                } else {
                    Tone::Behind(g.place.min(SHOWN - 1))
                };
                self.card(&mut out, &g.card, &p, ground, open, false, height);
            }
        }
        out
    }

    #[allow(clippy::too_many_arguments)]
    fn card(&self, out: &mut Vec<Draw>, c: &Card, p: &Pose, ground: Tone, open: bool, lit: bool, height: f64) {
        let m = &self.m;
        let r = self.rect(p, height);
        out.push(Draw::Fill {
            x: r.x,
            y: r.y,
            w: r.w,
            h: r.h,
            tone: ground,
            alpha: p.alpha,
        });
        let alpha = p.alpha * p.text;
        if alpha <= 0.01 {
            return;
        }
        let low = c.note.urgency == Urgency::Low;
        let ink = if low { Tone::Dim } else { Tone::Text };
        let (x, w) = (r.x + m.pad_x, r.w - 2.0 * m.pad_x);
        let mut y = r.y + m.pad_y;
        let line = |out: &mut Vec<Draw>, x: f64, y: f64, w: f64, text: &str, tone: Tone, bold: bool| {
            out.push(Draw::Text {
                x,
                y,
                w,
                h: m.line,
                text: text.to_string(),
                tone,
                bold,
                alpha,
            });
        };
        line(out, x, y, 2.0 * m.cell, ANGLE, if low { Tone::Dim } else { Tone::Accent }, false);
        line(out, x + 2.0 * m.cell, y, w - 4.0 * m.cell, &c.head, Tone::Dim, false);
        if lit {
            line(out, r.x + r.w - m.pad_x - m.cell, y, m.cell, CLOSE, Tone::Dim, false);
        }
        y += m.line;
        let sign = if c.note.urgency == Urgency::Critical { Tone::Alert } else { ink };
        line(out, x, y, 2.0 * m.cell, c.note.sign(), sign, false);
        line(out, x + 2.0 * m.cell, y, w - 2.0 * m.cell, &c.title, ink, true);
        for text in c.lines(open) {
            y += m.line;
            if y + m.line > r.y + r.h {
                break;
            }
            line(out, x, y, w, &text, ink, false);
        }
        for ((_, words), chip) in c.chips.iter().zip(self.chip_rects(c, &r)) {
            out.push(Draw::Fill {
                x: chip.x,
                y: chip.y,
                w: chip.w,
                h: chip.h,
                // a button stands out from its card: the card's own ground under it on the lit one
                tone: if ground == Tone::Lit { Tone::Ground } else { Tone::Lit },
                alpha,
            });
            line(out, chip.x + m.cell, chip.y, chip.w - m.cell, words, ink, false);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn m() -> Metrics {
        Metrics::new(16.0, 10.0, 360.0, 24.0, 16.0)
    }

    fn note(id: u32, summary: &str) -> Note {
        Note::of(&json!({"id": id, "app": "mail", "summary": summary, "body": "one line", "urgency": 1, "category": "", "actions": [], "ms": 6000})).unwrap()
    }

    fn stack(n: u32) -> Stack {
        let mut s = Stack::new(m(), true, true);
        for id in 1..=n {
            s.show(note(id, "hello"), 0);
        }
        s
    }

    fn fills(s: &Stack, now: u64, h: f64) -> Vec<(f64, f64, f64, f64, Tone)> {
        s.frame(now, h)
            .into_iter()
            .filter_map(|d| match d {
                Draw::Fill { x, y, w, h, tone, .. } if tone != Tone::Lit => Some((x, y, w, h, tone)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn a_note_is_read_and_scrubbed() {
        let n = Note::of(
            &json!({"id": 7, "app": "fire\u{202e}fox", "summary": "Down\u{0007}load", "body": "a\nb\n\n\u{200b}", "urgency": 2,
            "category": "transfer.complete", "actions": [["default", "Open"], ["x", "Sh\u{200b}ow"]], "ms": 0}),
        )
        .unwrap();
        assert_eq!((n.app.as_str(), n.summary.as_str()), ("firefox", "Download"));
        assert_eq!(n.body, ["a", "b"]);
        assert_eq!((n.urgency, n.ms), (Urgency::Critical, None));
        assert_eq!(n.actions, [("default".to_string(), "Open".to_string()), ("x".to_string(), "Show".to_string())]);
        assert_eq!(n.sign(), "\u{26a0}", "a critical one wears the warning, whatever its kind");
        assert!(Note::of(&json!({"id": 0, "summary": "x"})).is_none() && Note::of(&json!({"summary": "x"})).is_none());
        assert_eq!(note(1, "x").sign(), "\u{25cf}");
    }

    #[test]
    fn text_is_cut_and_wrapped_by_cells() {
        assert_eq!(cut("hello", 5), "hello");
        assert_eq!(cut("hello world", 8), "hello w\u{2026}");
        assert_eq!(cut("hello world", 7), "hello\u{2026}", "no blank before the ellipsis");
        assert_eq!(wrap("the quick brown fox", 9), ["the quick", "brown fox"]);
        assert_eq!(wrap("abcdefghijkl mn", 5), ["abcde", "fghij", "kl mn"]);
        assert!(wrap("   ", 5).is_empty());
    }

    #[test]
    fn closed_the_newest_is_in_front_and_two_show_behind_it() {
        let s = stack(5);
        let f = fills(&s, 1000, 200.0);
        // back to front: the third, the second, the first; the fourth and the fifth are not drawn
        assert_eq!(f.len(), 3);
        let (m, h0) = (m(), 2.0 * 16.0 + 24.0 * 3.0);
        assert_eq!(f[2], (0.0, 0.0, 360.0, h0, Tone::Ground));
        assert_eq!(f[1], (m.inset, m.peek, 360.0 - 2.0 * m.inset, h0, Tone::Behind(1)));
        assert_eq!(f[0], (2.0 * m.inset, 2.0 * m.peek, 360.0 - 4.0 * m.inset, h0, Tone::Behind(2)));
        assert_eq!(s.size(1000), (360.0, h0 + 2.0 * m.peek));
        // only the front one's words are drawn
        let words = s.frame(1000, 200.0).iter().filter(|d| matches!(d, Draw::Text { .. })).count();
        assert_eq!(words, 5, "the angle, the app, the sign, the summary and one line of body");
    }

    #[test]
    fn it_stands_on_the_bottom_edge_too() {
        let mut s = Stack::new(m(), false, false);
        s.show(note(1, "a"), 0);
        s.show(note(2, "b"), 0);
        let (w, h) = s.size(0);
        let f = fills(&s, 0, h);
        assert_eq!((f[1].0, f[1].1 + f[1].3), (0.0, h), "the front card's foot is on the edge");
        assert!(f[0].1 < f[1].1, "the one behind shows above it");
        assert_eq!(w, 360.0);
    }

    #[test]
    fn the_pointer_over_it_opens_it_and_leaving_closes_it() {
        let mut s = stack(3);
        assert_eq!(s.point(10.0, 10.0, 1000, 200.0), [Event::Seen]);
        assert!(s.open());
        assert_eq!(s.point(12.0, 10.0, 1010, 200.0), [], "looked at once");
        let h = s.size(2000).1;
        let f = fills(&s, 2000, h);
        let each = 2.0 * 16.0 + 24.0 * 3.0;
        assert_eq!(h, 3.0 * each + 2.0 * 8.0);
        assert!(f.iter().all(|r| r.0 == 0.0 && r.2 == 360.0 && r.3 == each), "each whole and as wide: {f:?}");
        s.leave_pointer(3000);
        assert!(!s.open());
        assert_eq!(s.size(4000).1, each + 2.0 * m().peek);
    }

    #[test]
    fn a_new_one_comes_in_from_the_edge_and_the_surface_keeps_room_meanwhile() {
        let mut s = stack(1);
        s.show(note(2, "new"), 1000);
        let at = |now| fills(&s, now, 300.0).last().copied().unwrap();
        assert_eq!(fills(&s, 1000, 300.0).len(), 1, "not drawn before it has faded in at all");
        assert!(at(1020).1 < 0.0, "it starts beyond the edge");
        assert!(at(1100).1 > at(1020).1 && at(1100).1 < 0.0);
        assert_eq!(at(1200).1, 0.0);
        assert!(s.moving(1100) && !s.moving(1201));
        // no motion: in its place at once
        let mut q = Stack::new(m(), true, false);
        q.show(note(1, "a"), 0);
        assert_eq!(fills(&q, 0, 300.0)[0].1, 0.0);
        assert!(!q.moving(0));
    }

    #[test]
    fn one_shown_again_is_changed_in_place() {
        let mut s = stack(2);
        s.show(note(1, "saved"), 5000);
        let titles: Vec<String> = s.cards.iter().map(|c| c.title.clone()).collect();
        assert_eq!(titles, ["hello", "saved"], "its place kept, no new entrance");
        assert_eq!(s.cards.len(), 2);
    }

    #[test]
    fn a_card_s_time_runs_in_sight_and_waits_while_the_stack_is_open() {
        let mut s = stack(4);
        assert_eq!(s.deadline(), Some(6000), "the three in sight run; the fourth waits its turn");
        assert_eq!(s.cards.iter().filter(|c| c.since.is_some()).count(), 3);
        assert_eq!(s.tick(5999), []);
        s.point(10.0, 10.0, 2000, 200.0);
        assert_eq!((s.deadline(), s.tick(9000)), (None, vec![]), "open: no time runs");
        s.leave_pointer(9000);
        assert_eq!(s.deadline(), Some(13000), "four seconds were left");
        let mut gone = s.tick(13000);
        gone.sort_by_key(|e| format!("{e:?}"));
        assert_eq!(gone, [Event::Expired(2), Event::Expired(3), Event::Expired(4)]);
        assert_eq!(s.cards.len(), 1);
        assert_eq!(s.deadline(), Some(19000), "the one that waited has its whole time");
    }

    #[test]
    fn a_critical_one_stays() {
        let mut s = Stack::new(m(), true, true);
        s.show(Note::of(&json!({"id": 1, "summary": "Battery", "urgency": 2, "ms": 0})).unwrap(), 0);
        assert_eq!((s.deadline(), s.tick(1_000_000)), (None, vec![]));
        assert!(s.critical());
    }

    #[test]
    fn a_swipe_past_the_mark_dismisses_and_a_short_one_goes_back() {
        let mut s = stack(2);
        s.point(10.0, 10.0, 0, 200.0);
        assert_eq!(s.press(100.0, 20.0, 1, 100, 200.0), []);
        s.point(130.0, 20.0, 400, 200.0);
        assert_eq!(s.release(900), [], "30 pixels, slowly: back to its place");
        assert_eq!(s.cards.len(), 2);
        s.press(100.0, 20.0, 1, 1000, 200.0);
        s.point(150.0, 22.0, 1400, 200.0);
        assert_eq!(s.release(1900), [Event::Dismissed(2)], "50 pixels: gone");
        assert_eq!(s.cards.len(), 1);
        // a flick: a short way, fast
        s.press(100.0, 20.0, 1, 3000, 200.0);
        s.point(104.0, 20.0, 3010, 200.0);
        s.point(120.0, 20.0, 3020, 200.0);
        assert_eq!(s.release(3021), [Event::Dismissed(1)]);
        assert!(s.is_empty() && !s.open());
    }

    #[test]
    fn a_click_does_what_the_app_offers_and_the_other_buttons_dismiss() {
        let mut s = Stack::new(m(), true, false);
        let with = |id: u32| {
            Note::of(&json!({"id": id, "app": "spark-shell", "summary": "call the vet", "actions": [["default", "a click opens Reminders"], ["snooze", "Snooze"]], "ms": 6000})).unwrap()
        };
        s.show(with(1), 0);
        s.show(note(2, "plain"), 0);
        s.show(with(3), 0);
        s.point(10.0, 10.0, 0, 400.0);
        // a click on a card with nothing offered does nothing
        let y2 = s.cards[0].height(&m(), true) + 8.0 + 10.0;
        s.press(50.0, y2, 1, 10, 400.0);
        assert_eq!(s.release(20), []);
        // on the front one: its default action, and it leaves
        s.press(50.0, 40.0, 1, 30, 400.0);
        assert_eq!(s.release(40), [Event::Action(3, "default".into())]);
        // the right button dismisses the one under it, the middle one every one
        assert_eq!(s.press(50.0, 10.0, 3, 50, 400.0), [Event::Dismissed(2)]);
        s.show(note(4, "more"), 60);
        let mut all = s.press(50.0, 10.0, 2, 70, 400.0);
        all.sort_by_key(|e| format!("{e:?}"));
        assert_eq!(all, [Event::Dismissed(1), Event::Dismissed(4)]);
        assert!(s.is_empty());
    }

    #[test]
    fn a_button_on_the_card_is_its_action_and_the_cross_dismisses() {
        let mut s = Stack::new(m(), true, false);
        s.show(Note::of(&json!({"id": 9, "app": "chat", "summary": "Ada", "body": "hi", "actions": [["default", "Open"], ["reply", "Reply"], ["mute", "Mute"], ["x", "Third"]], "ms": 0})).unwrap(), 0);
        s.point(10.0, 10.0, 0, 400.0);
        let h = s.size(0).1;
        assert_eq!(s.cards[0].chips.len(), 2, "two buttons, the default is the card's own click");
        assert_eq!(s.cards[0].head, "chat \u{25b8} Open");
        let chip_y = h - 16.0 - 12.0;
        assert_eq!(s.hit(24.0 + 5.0, chip_y, 0, h), Some((0, Part::Chip(0))));
        assert_eq!(s.hit(24.0 + 7.0 * 10.0 + 10.0 + 5.0, chip_y, 0, h), Some((0, Part::Chip(1))));
        assert_eq!(s.hit(360.0 - 24.0 - 5.0, 16.0 + 5.0, 0, h), Some((0, Part::Close)));
        s.press(24.0 + 7.0 * 10.0 + 10.0 + 5.0, chip_y, 1, 10, h);
        assert_eq!(s.release(20), [Event::Action(9, "mute".into())]);
    }

    #[test]
    fn the_keys_open_it_and_move_act_dismiss_and_close() {
        let mut s = stack(3);
        assert_eq!(s.open_keys(100), [Event::Seen]);
        assert!(s.wants_keys() && s.open() && s.deadline().is_none());
        assert_eq!(s.key(Key::Down, 110), []);
        assert_eq!(s.sel, 1);
        assert_eq!(s.key(Key::Activate, 120), [], "nothing offered: nothing done");
        assert_eq!(s.key(Key::Delete, 130), [Event::Dismissed(2)]);
        assert_eq!(s.sel, 1, "the next one takes its place");
        s.key(Key::Down, 140);
        s.key(Key::Down, 150);
        assert_eq!(s.sel, 1, "no further than the last");
        s.key(Key::Up, 160);
        s.key(Key::Up, 170);
        assert_eq!(s.sel, 0);
        s.key(Key::Escape, 180);
        assert!(!s.wants_keys() && !s.open());
        assert_eq!(s.key(Key::Delete, 190), [], "closed: the keys are not its own");
        assert_eq!(Key::of_sym(0xffff), Some(Key::Delete));
        assert_eq!(Key::of_evdev(1), Some(Key::Escape));
        assert_eq!((Key::of_sym(0x61), Key::of_evdev(30)), (None, None));
        // standing on the bottom edge, up is toward the older ones
        let mut b = Stack::new(m(), false, false);
        b.show(note(1, "a"), 0);
        b.show(note(2, "b"), 0);
        b.open_keys(0);
        b.key(Key::Up, 1);
        assert_eq!(b.sel, 1);
    }

    #[test]
    fn the_server_closes_one_and_an_empty_stack_takes_nothing() {
        let mut s = stack(2);
        s.open_keys(0);
        s.close(1, 100);
        s.close(2, 100);
        s.close(7, 100);
        assert!(s.is_empty() && !s.wants_keys());
        assert!(
            s.moving(150) && !s.moving(100 + MOVE_MS),
            "the ones leaving fade, and the surface is theirs meanwhile"
        );
        assert_eq!(s.size(1000), (0.0, 0.0));
        assert_eq!(s.open_keys(1000), []);
        assert_eq!(s.point(1.0, 1.0, 1000, 0.0), []);
        assert!(s.regions(1000, 0.0).is_empty());
    }

    #[test]
    fn more_than_it_lists_are_counted_in_a_line() {
        let mut s = stack(11);
        s.open_keys(0);
        let h = s.size(1000).1;
        let said: Vec<String> = s
            .frame(1000, h)
            .into_iter()
            .filter_map(|d| match d {
                Draw::Text { text, .. } if text.contains("more") => Some(text),
                _ => None,
            })
            .collect();
        assert_eq!(said, ["\u{25b8} and 3 more"]);
        assert_eq!(fills(&s, 1000, h).len(), OPEN_MOST - 1, "the one the keys are on is lit");
        let lit = s
            .frame(1000, h)
            .iter()
            .filter(|d| matches!(d, Draw::Fill { tone: Tone::Lit, w, .. } if *w == 360.0))
            .count();
        assert_eq!(lit, 1);
        assert_eq!(s.regions(1000, h).len(), 1, "open: one place from the first card to the last");
    }

    #[test]
    fn the_last_card_dismissed_under_the_pointer_leaves_the_next_one_closed_with_its_time() {
        let mut s = stack(1);
        s.point(10.0, 10.0, 500, 400.0);
        assert!(s.open() && s.deadline().is_none());
        assert_eq!(s.press(10.0, 10.0, 3, 600, 400.0), [Event::Dismissed(1)]);
        // its surface goes with it, and no leave comes for a surface that is gone
        s.show(note(2, "next"), 2000);
        assert!(!s.open(), "the pointer is not on a stack that was not there");
        assert_eq!(s.deadline(), Some(8000));
        // a leave that comes late changes nothing
        s.leave_pointer(2100);
        assert_eq!(s.deadline(), Some(8000));
    }

    #[test]
    fn the_keys_stay_on_their_card_when_a_new_one_comes() {
        let mut s = stack(3);
        s.open_keys(0);
        s.key(Key::Down, 1);
        let chosen = s.cards[s.sel].note.id;
        s.show(note(4, "new"), 2);
        assert_eq!(s.cards[s.sel].note.id, chosen);
        // where the list has no room for its card any more, the keys are on the last one listed
        let each = 2.0 * 16.0 + 24.0 * 3.0;
        s.room(2.0 * each + 8.0 + 8.0 + 24.0, 3);
        assert_eq!(s.sel, 1);
        s.show(note(5, "newer"), 4);
        assert_eq!((s.sel, s.cards[s.sel].note.id), (1, 4));
    }

    #[test]
    fn wide_text_is_measured_in_cells() {
        // each of these takes two cells
        let wide = "\u{65e5}\u{672c}\u{8a9e}\u{306e}\u{30c6}\u{30ad}\u{30b9}\u{30c8}";
        assert_eq!(cells_of(wide), 16);
        assert_eq!(cut(wide, 16), wide);
        let short = cut(wide, 9);
        assert!(short.ends_with('\u{2026}') && cells_of(&short) <= 9, "{short}");
        let lines = wrap(&format!("{wide}{wide} ok"), 10);
        assert!(lines.len() >= 4 && lines.iter().all(|l| cells_of(l) <= 10), "{lines:?}");
        assert_eq!(lines.concat().replace(' ', ""), format!("{wide}{wide}ok"));
        // a joiner takes no cell, and a line never ends without taking a character
        assert_eq!(wrap("e\u{301}e\u{301}e\u{301}", 2), ["e\u{301}e\u{301}", "e\u{301}"]);
        assert_eq!(wrap(wide, 1).len(), 8);
        // a time longer than an hour is an hour
        let long = Note::of(&json!({"id": 1, "summary": "s", "ms": u64::MAX})).unwrap();
        assert_eq!(long.ms, Some(3_600_000));
    }

    #[test]
    fn an_open_stack_lists_what_the_screen_holds() {
        let mut s = stack(6);
        let each = 2.0 * 16.0 + 24.0 * 3.0;
        // room for three cards and the line that counts the rest, and not for a fourth
        s.room(3.0 * each + 2.0 * 8.0 + 8.0 + 24.0, 0);
        s.open_keys(0);
        let h = s.size(1000).1;
        assert_eq!(h, 3.0 * each + 2.0 * 8.0 + 8.0 + 24.0);
        assert!(s
            .frame(1000, h)
            .iter()
            .any(|d| matches!(d, Draw::Text { text, .. } if text.ends_with("and 3 more"))));
        s.key(Key::Down, 1);
        s.key(Key::Down, 2);
        s.key(Key::Down, 3);
        assert_eq!(s.sel, 2, "the keys stay on the cards listed");
        assert_eq!(s.hit(10.0, 3.0 * each + 2.0 * 8.0 + 12.0, 1000, h), None, "the line that counts is no card");
        // no room at all: one card still
        s.room(10.0, 2000);
        assert_eq!(s.size(3000).1, each + 8.0 + 24.0);
    }

    #[test]
    fn a_long_body_is_cut_closed_and_shown_open() {
        let mut s = Stack::new(m(), true, false);
        let body = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three";
        s.show(Note::of(&json!({"id": 1, "summary": "long", "body": body, "ms": 0})).unwrap(), 0);
        let closed = s.cards[0].lines(false);
        assert_eq!(closed.len(), BODY_CLOSED);
        assert!(closed[2].ends_with('\u{2026}'));
        assert!(s.cards[0].lines(true).len() > BODY_CLOSED);
        assert!(s.cards[0].height(&m(), true) > s.cards[0].height(&m(), false));
    }

    #[test]
    fn an_event_is_a_line_for_the_server() {
        assert_eq!(Event::Expired(4).json(), r#"{"event":"expired","id":4}"#);
        assert_eq!(Event::Action(4, "default".into()).json(), r#"{"event":"action","id":4,"key":"default"}"#);
        assert_eq!(Event::Seen.json(), r#"{"event":"seen"}"#);
    }
}
