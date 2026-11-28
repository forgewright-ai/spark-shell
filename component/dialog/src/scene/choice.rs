//! A setting in one row (C3, v0.161): its name, then its options side by side, the one in use in the accent with the
//! line under it. An option is a word; or a specimen (v0.167), drawn as what it is (a typeface in its own face, a
//! size as an A that large, a glyph family by its signs) over its small caption. A page sets its rows of options to
//! one rhythm: they start at one column, and specimens stand the same distance apart in every row.

use super::{Area, Metrics, Pen, Target};
use crate::app::{App, Item, View};
use crate::draw::{Size, Step};
use crate::model::{self, Specimen};
use crate::scrub::cells;

/// An option: what is drawn for it, its size and, for a typeface, its family and its width there; the caption under
/// it, where it is no word of its own; the option App::option_at takes; whether it is the one in use, and whether it
/// is a word of the step (less, more) rather than a value.
#[derive(Clone, Debug, PartialEq)]
struct Opt {
    word: String,
    size: Size,
    face: Option<(String, f64)>,
    caption: String,
    /// What its number counts, small after it: said once in a list, after the last number.
    unit: String,
    k: usize,
    on: bool,
    verb: bool,
}

#[derive(Clone, Debug, PartialEq)]
struct Placed {
    opt: Opt,
    x: f64,
    y: f64,
    width: f64,
}

/// A row as it is laid: its name, its options each at its place from the row's words, and whether they are specimens.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Choice {
    name: String,
    opts: Vec<Placed>,
    specimens: bool,
    /// A list stands behind the one value shown: the whole row opens it, and its arrow says so.
    tail: bool,
    /// Where the name's baseline stands under the row's top.
    base: f64,
}

/// How a page sets its rows of options: where the options start, how far apart its specimens stand, and whether they
/// stand on their name's line; under it where the room is too narrow for that.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Rhythm {
    pub column: f64,
    pitch: f64,
    beside: bool,
}

/// A row's options before they are laid: specimens or words, and the two words around the value for a list of words
/// that does not fit its line.
struct Parts {
    name: String,
    opts: Vec<Opt>,
    specimens: bool,
    /// The columns its specimens take: a size keeps one for the size in use that is none of the usual four, so
    /// nothing moves when it is one.
    slots: usize,
    short: Option<Vec<Opt>>,
    tail: bool,
    /// Its page keeps its lists side by side.
    spread: bool,
}

/// In the sheets' pixels: the options' column, the air beside an option's word, a target a finger hits, a specimen's
/// row with its baseline and its caption's, the most its specimens stand apart, and the least between two.
const COLUMN: f64 = 200.0;
const NEAREST: f64 = 120.0;
const AIR: f64 = 8.0;
const TARGET: f64 = 44.0;
const TALL: f64 = 84.0;
const TALL_BASE: f64 = 45.0;
const TALL_CAPTION: f64 = 69.0;
const PITCH: f64 = 92.0;
const PART: f64 = 10.0;
/// How far under its name's line a row of specimens starts that does not stand on it.
const UNDER: f64 = 24.0;

/// The pages whose short lists always stand side by side, on a second line where the first is too short.
fn spread(app: &App) -> bool {
    matches!(&app.view, View::Folder(_, uri) if uri.starts_with("spark-shell://theme/rows/settings/")) || crate::appearance::display(app)
}

fn word(word: &str, k: usize, on: bool) -> Opt {
    Opt {
        word: word.to_string(),
        size: Size::Main,
        face: None,
        caption: String::new(),
        unit: String::new(),
        k,
        on,
        verb: false,
    }
}

/// A list's words: numbers of one unit ("5 min", "10 min") say it once, after the last of them.
fn listed(st: &model::Step) -> Vec<Opt> {
    let of = |v: &model::StepValue| {
        let (n, unit) = v.shown.split_once(' ')?;
        let plain = n.bytes().all(|b| b.is_ascii_digit()) && unit.bytes().all(|b| b.is_ascii_lowercase()) && !unit.is_empty();
        plain.then(|| (n.to_string(), unit.to_string()))
    };
    let numbers: Vec<Option<(String, String)>> = st.values.iter().map(of).collect();
    let unit = numbers.iter().flatten().map(|(_, u)| u).next();
    let one = numbers.iter().flatten().count() > 1 && numbers.iter().flatten().all(|(_, u)| Some(u) == unit);
    let last = numbers.iter().rposition(Option::is_some);
    let opt = |(k, v): (usize, &model::StepValue)| match &numbers[k] {
        Some((n, u)) if one => Opt {
            unit: if last == Some(k) { u.clone() } else { String::new() },
            ..word(n, k, k == st.at)
        },
        _ => word(&v.shown, k, k == st.at),
    };
    st.values.iter().enumerate().map(opt).collect()
}

/// The size an A stands for, beside the four the layout has: 10, 12, 14 and 16.
fn size_of(points: &str) -> Size {
    match points.parse::<u32>().unwrap_or(12) {
        0..=10 => Size::Small,
        11..=12 => Size::Main,
        13..=14 => Size::Lead,
        _ => Size::Head,
    }
}

/// A size's row: auto where it is one, then an A at each of four sizes, larger and larger, that stand still whatever
/// is in use: 10, 12, 14 and 16 where the list holds them, else its first four; after them the size in use, where it
/// is none of these.
fn sizes(st: &model::Step) -> Vec<Opt> {
    let auto = st.values.iter().position(|v| v.sent == "auto");
    let all: Vec<usize> = (0..st.values.len()).filter(|i| Some(*i) != auto).collect();
    let usual: Vec<usize> = ["10", "12", "14", "16"]
        .iter()
        .filter_map(|s| all.iter().copied().find(|i| st.values[*i].sent == *s))
        .collect();
    let shown: Vec<usize> = if usual.len() == 4 { usual } else { all.into_iter().take(4).collect() };
    let a = |i: usize, size: Size| Opt {
        size,
        caption: st.values[i].shown.clone(),
        ..word("A", i, i == st.at)
    };
    let mut opts: Vec<Opt> = auto
        .map(|i| Opt {
            caption: st.values[i].shown.trim_start_matches("auto").trim().to_string(),
            ..word("auto", i, i == st.at)
        })
        .into_iter()
        .collect();
    let steps = [Size::Small, Size::Main, Size::Lead, Size::Head];
    opts.extend(shown.iter().zip(steps).map(|(i, step)| a(*i, step)));
    if Some(st.at) != auto && !shown.contains(&st.at) {
        opts.push(a(st.at, size_of(&st.values[st.at].sent)));
    }
    opts
}

/// A value's specimen, where it has one that can be drawn: a family this window resolves, or its signs. Else its word.
fn specimen(app: &App, k: usize, v: &model::StepValue, on: bool) -> Opt {
    match &v.specimen {
        Some(Specimen::Face(f)) => match app.faces.get(f).copied().flatten() {
            Some(w) => Opt {
                size: Size::LETTERS,
                face: Some((f.clone(), w)),
                caption: v.shown.clone(),
                ..word(crate::draw::LETTERS, k, on)
            },
            None => word(&v.shown, k, on),
        },
        Some(Specimen::Signs(s)) => Opt {
            caption: v.shown.clone(),
            ..word(s, k, on)
        },
        None => word(&v.shown, k, on),
    }
}

/// The row of one setting an item is, where it is one: a group of picks (its name, its picks side by side), a switch
/// (on, off), a size, a value of a few short choices, else a value between its two words (less 35% more).
fn parts(app: &App, item: &Item) -> Option<Parts> {
    let row = app.row_ref(item)?;
    let words = |name: &str, opts: Vec<Opt>| Parts {
        name: name.to_string(),
        slots: opts.len(),
        opts,
        specimens: false,
        short: None,
        tail: false,
        spread: spread(app),
    };
    if let Item::Row(p, r) = item {
        if let Some(run) = app.choice_group(*p, *r) {
            let rows = &app.providers[*p].rows.rows;
            let opts = run.iter().enumerate().map(|(k, i)| word(&rows[*i].text, k, rows[*i].sign == "check")).collect();
            return Some(words(row.group.as_deref().unwrap_or_default(), opts));
        }
    }
    if let Some(sw) = &row.switch {
        return Some(words(&row.text, vec![word("on", 0, sw.on), word("off", 1, !sw.on)]));
    }
    // a choice with a list behind it: the one in use stands where the options do
    if row.choice && row.children.is_some() && crate::appearance::display(app) {
        if let Some(now) = row.columns.first().filter(|c| !c.is_empty()) {
            return Some(Parts {
                tail: true,
                ..words(&row.text, vec![word(now, 0, true)])
            });
        }
    }
    let st = row.step.as_ref()?;
    let n = st.values.len();
    let auto = st.values.iter().any(|v| v.sent == "auto");
    if (st.words.0.as_str(), st.words.1.as_str()) == ("smaller", "bigger") {
        return Some(Parts {
            specimens: true,
            slots: (n - usize::from(auto)).min(4) + 1 + usize::from(auto),
            ..words(&row.text, sizes(st))
        });
    }
    let values: Vec<Opt> = st.values.iter().enumerate().map(|(k, v)| specimen(app, k, v, k == st.at)).collect();
    if n <= 8 && values.iter().any(|o| !o.caption.is_empty()) {
        return Some(Parts {
            specimens: true,
            ..words(&row.text, values)
        });
    }
    let verb = |w: &str, k: usize| Opt {
        verb: true,
        ..word(w, k, false)
    };
    let short = vec![
        verb(&st.words.0, st.at.saturating_sub(1)),
        word(st.value(), st.at, true),
        verb(&st.words.1, (st.at + 1).min(n.saturating_sub(1))),
    ];
    // the one in use may stand past the six a list has: a page that keeps its lists side by side keeps it too
    let most = if spread(app) { 8 } else { 6 };
    if n > most || st.values.iter().any(|v| cells(&v.shown) > 14) {
        return Some(words(&row.text, short));
    }
    Some(Parts {
        short: Some(short),
        ..words(&row.text, listed(st))
    })
}

/// A setting's options as words, in the order its row draws them (v0.174, the actions beside a page): each one's
/// words, the option App::option_at takes, and whether it is the one in use. A size's A and a typeface's letters are
/// said by their captions.
pub(super) fn opts(app: &App, item: &Item) -> Vec<(String, usize, bool)> {
    let Some(p) = parts(app, item) else { return vec![] };
    p.opts
        .into_iter()
        .filter(|o| !(p.tail && o.on))
        .map(|o| {
            let words = if (o.face.is_some() || o.word == "A") && !o.caption.is_empty() {
                o.caption.clone()
            } else if o.unit.is_empty() {
                o.word.clone()
            } else {
                format!("{} {}", o.word, o.unit)
            };
            (words, o.k, o.on && !o.verb)
        })
        .collect()
}

impl Opt {
    /// The width drawn: a specimen's in its own face, as the window measured it.
    fn drawn(&self, m: &Metrics) -> f64 {
        match &self.face {
            Some((_, w)) => *w,
            None => cells(&self.word) as f64 * m.adv(self.size),
        }
    }
    /// What its unit takes, with the air before it.
    fn unit_w(&self, m: &Metrics) -> f64 {
        if self.unit.is_empty() {
            return 0.0;
        }
        m.px(AIR / 2.0) + cells(&self.unit) as f64 * m.sw
    }
    /// A word's place: its own width with air at both sides, a target a finger hits at least.
    fn width(&self, m: &Metrics, air: f64) -> f64 {
        (self.drawn(m) + self.unit_w(m) + 2.0 * air).max(m.px(TARGET))
    }
}

impl Parts {
    fn name_w(&self, m: &Metrics) -> f64 {
        cells(&self.name) as f64 * m.cw
    }
    /// What the options' words take on one line, the last one's air let go.
    fn need(&self, m: &Metrics, air: f64) -> f64 {
        self.opts.iter().map(|o| o.width(m, air) + m.px(AIR)).sum::<f64>() - 2.0 * m.px(AIR)
    }
    /// Where its words start: the page's column, or past a longer name.
    fn column(&self, m: &Metrics, column: f64) -> f64 {
        column.max(self.name_w(m) + m.px(24.0))
    }
    /// The air its words have at each side on its name's line: the usual one, or half of it where that brings them
    /// there and the page keeps its lists side by side; none where they do not fit.
    fn fits(&self, m: &Metrics, column: f64, room: f64) -> Option<f64> {
        let room = room - self.column(m, column);
        let airs: &[f64] = if self.spread { &[AIR, AIR / 2.0] } else { &[AIR] };
        airs.iter().map(|air| m.px(*air)).find(|air| self.need(m, *air) <= room)
    }
    /// The widest of its specimens, and of their captions.
    fn widest(&self, m: &Metrics) -> f64 {
        self.opts.iter().map(|o| o.drawn(m).max(cells(&o.caption) as f64 * m.sw)).fold(0.0, f64::max)
    }
}

/// The rhythm of a page's rows of options. The column is the one every page has; on a page whose short lists always
/// stand side by side it comes in to its longest name where that brings a list onto one line, for every row of the
/// page. The specimens' distance is the widest the room holds for the row with the most of them.
pub(super) fn rhythm(app: &App, m: &Metrics, items: &[Item], room: f64) -> Rhythm {
    let rows: Vec<Parts> = items.iter().filter_map(|it| parts(app, it)).collect();
    let (shown, lists): (Vec<&Parts>, Vec<&Parts>) = rows.iter().partition(|p| p.specimens);
    let slots = shown.iter().map(|p| p.slots).max().unwrap_or(1).max(1) as f64;
    let least = shown.iter().map(|p| p.widest(m) + m.px(PART)).fold(m.px(TARGET), f64::max);
    let at = |column: f64| {
        let from = shown.iter().map(|p| p.column(m, column)).fold(column, f64::max);
        let pitch = |room: f64| (room / slots).floor().min(m.px(PITCH));
        let beside = pitch(room - from) >= least;
        Rhythm {
            column: from,
            pitch: if beside { pitch(room - from) } else { pitch(room) },
            beside,
        }
    };
    // how many rows stand on their name's line with the options from there: with all their air, with some of it
    let fitting = |r: &Rhythm| {
        let specimens = if r.beside { shown.len() } else { 0 };
        let airs: Vec<f64> = lists.iter().filter_map(|p| p.fits(m, r.column, room)).collect();
        let whole = airs.iter().filter(|air| **air >= m.px(AIR)).count();
        (specimens + whole, airs.len())
    };
    let usual = at(m.px(COLUMN));
    if !spread(app) || fitting(&usual).0 == rows.len() {
        return usual;
    }
    // every row's name that has words beside it, the rows of no options too: they stand at the column as well
    let names = items
        .iter()
        .filter_map(|it| app.row_ref(it))
        .filter(|r| r.step.is_some() || r.switch.is_some() || !r.columns.is_empty())
        .map(|r| cells(&r.text) as f64 * m.cw)
        .fold(0.0, f64::max);
    let near = at((names + m.px(24.0)).clamp(m.px(NEAREST), m.px(COLUMN)));
    if fitting(&near) > fitting(&usual) {
        near
    } else {
        usual
    }
}

/// An item laid as a row of one setting, with its height; none for any other row.
pub(super) fn of(app: &App, m: &Metrics, item: &Item, room: f64, r: &Rhythm) -> Option<(f64, Choice)> {
    let mut p = parts(app, item)?;
    let column = p.column(m, r.column);
    let target = m.px(TARGET);
    if p.specimens {
        // on the name's own line, or in lines of their own under it, as many to a line as the room holds
        let (x0, y0, pitch, per) = if r.beside {
            (column, 0.0, r.pitch, p.opts.len().max(1))
        } else {
            let pitch = r.pitch.max(p.widest(m) + m.px(PART)).max(target);
            (0.0, m.px(UNDER), pitch, (room / pitch).floor().max(1.0) as usize)
        };
        let mut opts = vec![];
        let mut bottom = target;
        for (i, opt) in p.opts.into_iter().enumerate() {
            let (x, y) = (x0 + (i % per) as f64 * pitch, y0 + (i / per) as f64 * m.px(TALL));
            bottom = y + m.px(TALL);
            opts.push(Placed { opt, x, y, width: pitch });
        }
        let base = m.px(if r.beside { TALL_BASE } else { 28.0 });
        let choice = Choice {
            name: p.name,
            opts,
            specimens: true,
            tail: false,
            base,
        };
        return Some((bottom, choice));
    }
    if p.fits(m, r.column, room).is_none() && !p.spread {
        if let Some(short) = p.short.take() {
            p.opts = short;
        }
    }
    // every option stays visible in a narrow window, its target with it: under the options before it where half the
    // room is theirs, else under the name
    let gap = m.px(AIR);
    let fits = p.fits(m, r.column, room);
    let hangs = fits.is_some() || (p.spread && column <= room / 2.0);
    let (x0, mut y) = if hangs { (column, 0.0) } else { (0.0, target) };
    let mut x = x0;
    let mut opts = vec![];
    for opt in p.opts {
        let width = opt.width(m, fits.unwrap_or(gap));
        if x > x0 && x + width > room + 2.0 * gap {
            x = x0;
            y += target;
        }
        opts.push(Placed { opt, x, y, width });
        x += width + gap;
    }
    let choice = Choice {
        name: p.name,
        opts,
        specimens: false,
        tail: p.tail,
        base: m.px(28.0),
    };
    Some((y + target, choice))
}

/// Where a row of options is drawn: its words' left edge, its top, its list's box, its place among the picks, whether
/// it is lit and whether the list holds the keys.
pub(super) struct At {
    pub x: f64,
    pub top: f64,
    pub area: Area,
    pub pick: Option<usize>,
    pub on: bool,
    pub focus: bool,
}

pub(super) fn draw(pen: &mut Pen, c: &Choice, at: At) {
    let m = *pen.m;
    let base = at.top + c.base;
    let accent = pen.t.accent;
    let w = pen.text(at.x, base, &c.name, Size::Main, pen.t.ink, at.on);
    if at.on && at.focus {
        pen.fill(at.x, base + m.px(5.0), w, 2.0, accent);
    }
    for placed in &c.opts {
        let (x, y) = (at.x + placed.x, at.top + placed.y);
        let high = if c.specimens {
            specimen_at(pen, &placed.opt, x, y);
            m.px(TALL)
        } else {
            word_at(pen, &placed.opt, x, y + m.px(28.0));
            m.px(TARGET)
        };
        if let Some(n) = at.pick.filter(|_| !c.tail) {
            let (top, bottom) = (y.max(at.area.top), (y + high).min(at.area.bottom));
            pen.hit(x - m.px(AIR), top, placed.width, bottom - top, Target::Option(n, placed.opt.k));
        }
    }
    if c.tail {
        let end = (at.area.right - m.px(12.0)).min(at.area.left + m.px(super::ROW_MAX));
        pen.text_end(end, base, crate::ui::MORE, Size::Main, pen.t.muted, false);
    }
}

/// A word among words, from its place's left edge: the first of every row stands on the page's column.
fn word_at(pen: &mut Pen, o: &Opt, x: f64, base: f64) {
    let m = *pen.m;
    let used = o.on && !o.verb;
    let color = if used {
        pen.t.accent
    } else if o.verb {
        pen.t.ink
    } else {
        pen.t.muted
    };
    let w = pen.text(x, base, &o.word, o.size, color, false);
    if used {
        pen.fill(x.round(), base + m.px(5.0), w, 2.0, color);
    }
    pen.text(x + w + m.px(AIR / 2.0), base, &o.unit, Size::Small, pen.t.muted, false);
}

/// A specimen over its caption, both from its column's left edge; a value with no specimen of its own is its word.
fn specimen_at(pen: &mut Pen, o: &Opt, x: f64, top: f64) {
    let m = *pen.m;
    let base = (top + m.px(TALL_BASE)).round();
    let color = if o.on {
        pen.t.accent
    } else if o.caption.is_empty() {
        pen.t.muted
    } else {
        pen.t.ink
    };
    let w = match &o.face {
        Some((family, w)) => {
            pen.steps.push(Step::Specimen {
                x: x.round(),
                base,
                text: o.word.clone(),
                face: family.clone(),
                size: o.size,
                color,
            });
            *w
        }
        None => pen.text(x, base, &o.word, o.size, color, false),
    };
    if o.on {
        pen.fill(x.round(), base + m.px(7.0), w, 2.0, color);
    }
    let caption = if o.on { pen.t.accent } else { pen.t.muted };
    pen.text(x, top + m.px(TALL_CAPTION), &o.caption, Size::Small, caption, false);
}
