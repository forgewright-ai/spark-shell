//! The frame of a window as wide as a screen (v0.174): every place in the three areas files has had since v0.160, the
//! list at the left, the page of the row lit in the middle, what you do with it at the right. The list and the
//! actions stand each on the panel's ground, a step from the window's; the page stands on the window's own, its name
//! in large type over one line of what it is, its facts side by side, then what it holds.

use super::{list, Area, End, Geo, Metrics, Pen, Row, Shape, Target, K};
use crate::app::{App, HintKey, Item};
use crate::draw::{Rgb, Size};
use crate::model;
use crate::page::Icon;
use crate::preview::Page;
use crate::scrub::cells;

/// The actions' column at its widest, as the sheet of files has it: its words 36 pixels in, its keys ending 60 short
/// of the window's edge.
const ACTS: f64 = 440.0;

/// The rows of a page and of its actions: no click of their own, a key in the smaller text with no box.
pub(super) const STILL: Shape = Shape {
    two: false,
    one: 36.0,
    narrow: true,
    still: true,
    pad: 12.0,
    bare: true,
    c3: false,
};

/// Where the three areas stand.
#[derive(Clone, Copy)]
pub(super) struct Frame {
    pub list: Area,
    pub page: Area,
    pub acts: Area,
}

impl Frame {
    /// The three areas of a wide window, the list's and the actions' grounds painted: each from the location line's
    /// rule to the keys', edge to edge.
    pub(super) fn new(pen: &mut Pen, g: &Geo) -> Frame {
        let m = *pen.m;
        let l = m.px(super::WIDE_LIST).min((g.w * 0.3625).round());
        let a = g.w - m.px(ACTS).min((g.w * 0.23).round());
        let (top, bottom) = (g.top, g.bottom);
        let panel = pen.t.panel;
        pen.fill(0.0, top, l, g.foot - top, panel);
        pen.fill(a, top, g.w - a, g.foot - top, panel);
        Frame {
            list: Area {
                left: g.inset,
                right: l - m.px(24.0),
                top,
                bottom,
                from: 0.0,
                to: l,
            },
            page: Area {
                left: l + m.px(84.0),
                right: a - m.px(48.0),
                top,
                bottom,
                from: l,
                to: a,
            },
            acts: Area {
                left: a + m.px(36.0),
                right: g.w - m.px(60.0),
                top,
                bottom,
                from: a,
                to: g.w,
            },
        }
    }
}

/// What you do with the row lit, a row each in the actions' column: its words and its key, what it is set to, whether
/// it is the one in use, and what a click on it does; or a group's name, a muted line, air.
pub(super) enum Act {
    Do {
        words: String,
        key: String,
        value: String,
        on: bool,
        target: Option<Target>,
    },
    Head(String),
    Note(String),
    Gap,
}

impl Act {
    pub(super) fn key(words: &str, key: &str, target: Target) -> Act {
        Act::Do {
            words: words.to_string(),
            key: key.to_string(),
            value: String::new(),
            on: false,
            target: Some(target),
        }
    }
}

/// The page of the row lit: its picture, its name and one line of what it is, its facts side by side, what it holds,
/// and the actions beside it.
#[derive(Default)]
pub(super) struct Look {
    pub icon: Option<Icon>,
    pub name: String,
    pub what: String,
    pub facts: Vec<(String, String)>,
    pub body: Vec<Row>,
    pub acts: Vec<Act>,
}

/// The height the name and the facts take over what the page holds.
pub(super) fn head_h(m: &Metrics, look: &Look) -> f64 {
    let mut h = 0.0;
    if !look.name.is_empty() {
        h += m.px(193.0);
    }
    if !look.facts.is_empty() {
        h += m.px(72.0);
    }
    h + m.px(30.0)
}

/// The page and its actions drawn: the name and the facts over what it holds, the actions from their column's top.
/// `key` names the lists, so each keeps its place from frame to frame.
pub(super) fn draw(app: &App, pen: &mut Pen, f: &Frame, mut look: Look, key: &str) {
    let m = *pen.m;
    // what the key bar names that the row's own actions do not say: change, move, month (v0.174)
    let said: Vec<(String, Option<Target>)> = look
        .acts
        .iter()
        .filter_map(|a| match a {
            Act::Do { key, target, .. } => Some((key.clone(), target.clone())),
            _ => None,
        })
        .collect();
    let more: Vec<Act> = bar_acts(app)
        .into_iter()
        .filter(|a| matches!(a, Act::Do { key, target, .. } if !said.iter().any(|(k, t)| (!k.is_empty() && k == key) || (t.is_some() && t == target))))
        .collect();
    if !more.is_empty() {
        if !look.acts.is_empty() {
            look.acts.push(Act::Gap);
        }
        look.acts.extend(more);
    }
    let fixed = |h: f64, k: K| Row { h: m.px(h), pick: None, k };
    let mut head = vec![];
    let hh = head_h(&m, &look);
    if !look.name.is_empty() {
        head.push(fixed(
            193.0,
            K::Name {
                icon: look.icon.clone(),
                name: look.name.clone(),
                what: look.what.clone(),
            },
        ));
    }
    if !look.facts.is_empty() {
        head.push(fixed(72.0, K::Facts(look.facts.clone())));
    }
    if !head.is_empty() {
        let over = Area {
            bottom: (f.page.top + hh).min(f.page.bottom),
            ..f.page
        };
        list(app, pen, &head, over, None, false, STILL, 0, format!("{key}\u{1f}head"));
    }
    if !look.body.is_empty() {
        let under = Area {
            top: (f.page.top + hh).min(f.page.bottom),
            ..f.page
        };
        list(app, pen, &look.body, under, None, false, STILL, 0, format!("{key}\u{1f}body"));
    }
    acts(app, pen, f, look.acts, key);
}

/// The actions in their column, from its top: each one's words and key, what it is set to, the one in use checked;
/// a click on one does it.
pub(super) fn acts(app: &App, pen: &mut Pen, f: &Frame, acts: Vec<Act>, key: &str) {
    let m = *pen.m;
    let checks = acts.iter().any(|a| matches!(a, Act::Do { on: true, .. }));
    let mut rows = vec![];
    let mut targets = vec![];
    for a in acts {
        let (row, target) = match a {
            Act::Do { words, key, value, on, target } => (
                Row {
                    h: m.px(36.0),
                    pick: None,
                    k: K::One {
                        icon: None,
                        sign: if on {
                            "check"
                        } else if checks {
                            "blank"
                        } else {
                            ""
                        },
                        swatch: vec![],
                        name: words,
                        muted: target.is_none(),
                        words: String::new(),
                        end: if value.is_empty() { End::None } else { End::Words(value) },
                        tail: false,
                        key,
                    },
                },
                target,
            ),
            Act::Head(h) => (
                Row {
                    h: m.px(36.0),
                    pick: None,
                    k: K::Head(h, None),
                },
                None,
            ),
            Act::Note(n) => (
                Row {
                    h: m.px(22.0),
                    pick: None,
                    k: K::Words(n, Size::Small, true, false),
                },
                None,
            ),
            Act::Gap => (
                Row {
                    h: m.px(12.0),
                    pick: None,
                    k: K::Gap(m.px(12.0)),
                },
                None,
            ),
        };
        rows.push(row);
        targets.push(target);
    }
    if rows.is_empty() {
        return;
    }
    let area = Area {
        top: f.acts.top + m.px(4.0),
        ..f.acts
    };
    let off = list(app, pen, &rows, area, None, false, STILL, 0, format!("{key}\u{1f}acts"));
    let mut y = area.top - off;
    for (r, t) in rows.iter().zip(targets) {
        let (top, h) = (y, r.h);
        y += h;
        let (a, b) = (top.max(area.top), (top + h).min(area.bottom));
        if let Some(t) = t.filter(|_| b > a) {
            pen.hit(area.from, a, area.to - area.from, b - a, t);
        }
    }
}

// ---------------------------------------------------------------- what a page holds

/// Air of a height, in the sheets' pixels.
pub(super) fn air(m: &Metrics, h: f64) -> Row {
    Row {
        h: m.px(h),
        pick: None,
        k: K::Gap(m.px(h)),
    }
}

/// A group's name, small in the accent, as every list has it.
pub(super) fn head(m: &Metrics, text: &str) -> Row {
    Row {
        h: m.px(36.0),
        pick: None,
        k: K::Head(text.to_string(), None),
    }
}

/// Words in the text's own size, wrapped to the room: what a step does, a note's lines.
pub(super) fn prose(m: &Metrics, text: &str, room: f64, muted: bool) -> Vec<Row> {
    let n = ((room - m.px(24.0)) / m.cw).floor().max(8.0) as usize;
    crate::ui::wrap(text, n)
        .into_iter()
        .map(|l| Row {
            h: m.px(26.0),
            pick: None,
            k: K::Words(l, Size::Main, muted, false),
        })
        .collect()
}

/// A label and its value, the value at a column: a fact of a list of them.
pub(super) fn pair(m: &Metrics, label: &str, value: &str) -> Row {
    Row {
        h: m.px(30.0),
        pick: None,
        k: K::Pair(label.to_string(), value.to_string()),
    }
}

/// A thing named, its words in the smaller text at the list's column: a window and its title.
pub(super) fn named(m: &Metrics, name: &str, words: &str) -> Row {
    Row {
        h: m.px(36.0),
        pick: None,
        k: K::One {
            icon: None,
            sign: "",
            swatch: vec![],
            name: name.to_string(),
            muted: false,
            words: words.to_string(),
            end: End::None,
            tail: false,
            key: String::new(),
        },
    }
}

/// A page's lines as rows: a line in bold a group's name, an empty one air, the rest in the text's own size. As many
/// as `most`.
pub(super) fn lines(m: &Metrics, pg: &Page, skip: usize, most: usize) -> Vec<Row> {
    let mut out: Vec<Row> = vec![];
    for (i, l) in pg.lines.iter().enumerate().skip(skip).take(most) {
        if l.trim().is_empty() {
            if !out.is_empty() && !matches!(out.last(), Some(Row { k: K::Gap(_), .. })) {
                out.push(air(m, 13.0));
            }
        } else if pg.bold.contains(&i) {
            out.push(head(m, l.trim()));
        } else {
            out.push(Row {
                h: m.px(26.0),
                pick: None,
                k: K::Words(l.clone(), Size::Main, false, false),
            });
        }
    }
    while matches!(out.last(), Some(Row { k: K::Gap(_), .. })) {
        out.pop();
    }
    out
}

/// The page a provider sent for a row, where it has come.
pub(super) fn peeked<'a>(app: &'a App, r: &model::Row) -> Option<&'a Page> {
    app.files
        .peek
        .as_ref()
        .filter(|pk| Some(&pk.uri) == r.page.as_ref())
        .and_then(|pk| pk.page.as_ref())
}

/// A part of a page made of facts (the providers' page_of and page_blocks): a fact as label and value, a group's name,
/// a line of words, air.
pub(super) enum Block {
    Pair(String, String),
    Head(String),
    Text(String),
    Gap,
}

/// A page made of a title, a line of what it is and its facts as label and value (the providers' page_of), its facts
/// in groups each under a bold line (page_blocks, v0.174): the line, and its parts in order. None for a page of any
/// other shape.
pub(super) fn facts_of(pg: &Page) -> Option<(String, Vec<Block>)> {
    if pg.bold.first() != Some(&0) || pg.lines.first() != Some(&pg.title) {
        return None;
    }
    let (what, from) = match pg.lines.get(1) {
        Some(l) if !l.is_empty() => (l.clone(), 3),
        _ => (String::new(), 2),
    };
    let blocks = pg
        .lines
        .iter()
        .enumerate()
        .skip(from)
        .map(|(i, l)| {
            if pg.bold.contains(&i) {
                return Block::Head(l.trim().to_string());
            }
            if l.trim().is_empty() {
                return Block::Gap;
            }
            match l.find("   ") {
                Some(at) if !l[..at].trim().is_empty() && !l[at..].trim().is_empty() => Block::Pair(l[..at].trim().to_string(), l[at..].trim().to_string()),
                _ => Block::Text(l.trim().to_string()),
            }
        })
        .collect();
    Some((what, blocks))
}

/// A page's parts as rows: a fact its label and its value, a long value on lines under it; a group's name small in the
/// accent with air over it; words wrapped to the room. `first`: nothing stands over them yet, so no air leads.
pub(super) fn rows_of_blocks(m: &Metrics, blocks: Vec<Block>, room: f64, first: bool) -> Vec<Row> {
    let mut out: Vec<Row> = vec![];
    for b in blocks {
        match b {
            Block::Pair(l, v) => {
                let n = ((room - m.px(192.0)) / m.cw).floor().max(8.0) as usize;
                for (i, line) in crate::ui::wrap(&v, n).into_iter().enumerate() {
                    out.push(Row {
                        h: m.px(if i == 0 { 30.0 } else { 24.0 }),
                        pick: None,
                        k: K::Pair(if i == 0 { l.clone() } else { String::new() }, line),
                    });
                }
            }
            Block::Head(h) => {
                if !out.is_empty() || !first {
                    out.push(air(m, 8.0));
                }
                out.push(head(m, &h));
            }
            Block::Text(t) => out.extend(prose(m, &t, room, false)),
            Block::Gap => out.push(air(m, 10.0)),
        }
    }
    out
}

/// The facts a page leads with, before its first group or words: side by side under the name where they are few.
pub(super) fn leading(blocks: &[Block]) -> Vec<(String, String)> {
    blocks
        .iter()
        .map_while(|b| match b {
            Block::Pair(l, v) => Some((l.clone(), v.clone())),
            _ => None,
        })
        .collect()
}

/// Facts that stand side by side under the name: a few, each short; more, or longer, stand under it a row each.
pub(super) fn side_by_side(pairs: &[(String, String)]) -> bool {
    !pairs.is_empty() && pairs.len() <= 4 && pairs.iter().all(|(l, v)| cells(l).max(cells(v)) <= 22)
}

/// What a row's tool does, in its provider's words: the line a page says under the name where nothing says more.
pub(super) fn does(app: &App, p: usize, r: &model::Row) -> String {
    // a row that picks a file says what its tool does with the file (v0.174.1): its page was its name alone
    let named = r
        .tool
        .as_ref()
        .or(r.step.as_ref().map(|s| &s.set))
        .or(r.switch.as_ref().map(|s| &s.turn_on))
        .map(|c| c.name.as_str());
    named
        .or(r.pick.as_ref().map(|pk| pk.tool.as_str()))
        .and_then(|n| app.providers.get(p)?.tools.iter().find(|t| t.name == n))
        .map(|t| t.description.trim().to_string())
        .unwrap_or_default()
}

/// What a row's own steps are, in the actions' column: its tool on Enter, its page on F3, then its other steps, each
/// a click away. A step that opens a list has an arrow's words.
pub(super) fn row_acts(app: &App, r: &model::Row) -> Vec<Act> {
    let keys = &app.cfg.keys;
    let mut out = vec![];
    let enter = keys.label(HintKey::Enter).to_string();
    if let Some(t) = &r.tool {
        out.push(Act::key(&app.step_words(t), &enter, Target::Key(HintKey::Enter)));
    } else if let Some(sw) = &r.switch {
        out.push(Act::key(if sw.on { "turn off" } else { "turn on" }, &enter, Target::Key(HintKey::Enter)));
    } else if r.pick.is_some() {
        out.push(Act::key("choose", &enter, Target::Key(HintKey::Enter))); // as the key bar says it
    } else if r.children.is_some() {
        out.push(Act::key("open", &enter, Target::Key(HintKey::Enter)));
    }
    if r.page.is_some() {
        out.push(Act::key("view", keys.label(HintKey::View), Target::Key(HintKey::View)));
    }
    let first = usize::from(r.tool.is_some());
    for (k, c) in r.more.iter().enumerate() {
        let key = if c.name.ends_with("_rename") {
            keys.label(HintKey::Rename).to_string()
        } else {
            String::new()
        };
        out.push(Act::Do {
            words: app.step_words(c),
            key,
            value: c.value.clone().unwrap_or_default(),
            on: false,
            target: Some(Target::Act(first + k)),
        });
    }
    out
}

/// The look of a provider's row: its name, what it is (its words, else what its step does), the facts and the lines
/// its page says, else what its step does in full; its own steps beside it.
pub(super) fn row(app: &App, pen: &Pen, p: usize, r: &model::Row, room: f64) -> Look {
    let m = *pen.m;
    let words: Vec<String> = r
        .wide
        .clone()
        .unwrap_or_else(|| r.columns.clone())
        .into_iter()
        .filter(|c| !c.trim().is_empty())
        .collect();
    let mut look = Look {
        name: r.text.clone(),
        what: words.join(crate::ui::SEP),
        acts: row_acts(app, r),
        ..Look::default()
    };
    let does = does(app, p, r);
    match peeked(app, r) {
        Some(pg) => {
            if let Some((what, blocks)) = facts_of(pg) {
                if !what.is_empty() && look.what.is_empty() {
                    look.what = what;
                } else if !what.is_empty() && what != look.what {
                    look.body.extend(prose(&m, &what, room, true));
                }
                let lead = leading(&blocks);
                let skip = if side_by_side(&lead) {
                    look.facts = lead.clone();
                    lead.len()
                } else {
                    0
                };
                let first = look.body.is_empty();
                look.body.extend(rows_of_blocks(&m, blocks.into_iter().skip(skip).collect(), room, first));
            } else {
                // a file's page: its facts are its kind, its size and its day, the last two always there
                let n = pg.facts.len();
                for (i, fact) in pg.facts.iter().enumerate() {
                    let label = match n - i {
                        1 => "changed",
                        2 => "size",
                        _ => "kind",
                    };
                    look.facts.push((label.to_string(), fact.clone()));
                }
                if let Some(file) = &pg.picture {
                    look.body.push(Row {
                        h: m.px(420.0),
                        pick: None,
                        k: K::Shown {
                            picture: Some((file.clone(), None)),
                            lines: vec![],
                            say: String::new(),
                            large: true,
                        },
                    });
                } else if !pg.lines.is_empty() {
                    let skip = usize::from(pg.lines.first().is_some_and(|l| l.trim() == r.text.trim()));
                    look.body.extend(lines(&m, pg, skip, 60));
                } else if let Some(say) = &pg.say {
                    look.body.extend(prose(&m, say, room, true));
                }
            }
            if look.body.is_empty() && !does.is_empty() {
                look.body.extend(prose(&m, &does, room, false));
            }
        }
        None => {
            if look.what.is_empty() {
                if let Some(line) = r.line.as_ref().filter(|l| !l.contains(&r.text) || l.len() > r.text.len() + 4) {
                    look.what = line.clone();
                }
            }
            if !does.is_empty() && does != look.what {
                look.body.extend(prose(&m, &does, room, false));
            }
            // a row with a picture of its own (the picture or video in use, v0.174.1) shows it under its words, with
            // the air a file's page has between its facts and its picture
            if let Some(file) = &r.preview {
                if !look.body.is_empty() {
                    look.body.push(Row {
                        h: m.px(30.0),
                        pick: None,
                        k: K::Gap(m.px(30.0)),
                    });
                }
                look.body.push(Row {
                    h: m.px(420.0),
                    pick: None,
                    k: K::Shown {
                        picture: Some((file.clone(), None)),
                        lines: vec![],
                        say: String::new(),
                        large: true,
                    },
                });
            }
        }
    }
    look
}

/// The options of a setting's row, as actions: each one a click away, the one in use checked; for a value between two
/// words, those words and the value.
pub(super) fn options(app: &App, item: &Item, n: usize) -> Vec<Act> {
    super::choice::opts(app, item)
        .into_iter()
        .map(|(words, k, on)| Act::Do {
            words,
            key: String::new(),
            value: String::new(),
            on,
            target: Some(Target::Option(n, k)),
        })
        .collect()
}

/// A shade between two colors: `share` of the way from `a` to `b`.
pub(super) fn blend(a: Rgb, b: Rgb, share: f64) -> Rgb {
    std::array::from_fn(|i| (f64::from(a[i]) + (f64::from(b[i]) - f64::from(a[i])) * share).round() as u8)
}

/// The actions the key bar names for the row lit, as rows (a theme's page: details, wallpaper, palette): each group's
/// words and its key; back, help and the arrows stay the bar's.
pub(super) fn bar_acts(app: &App) -> Vec<Act> {
    let mut out = vec![];
    for group in crate::ui::key_groups(app, app.preview_pages.max(1)) {
        let words: String = group.iter().filter(|(_, k, _)| !*k).map(|(t, ..)| t.trim()).collect::<Vec<_>>().join(" ");
        let key: Vec<&str> = group.iter().filter(|(_, k, _)| *k).map(|(t, ..)| t.as_str()).collect();
        let Some(action) = group.iter().find_map(|(_, _, a)| a.first().copied()) else {
            continue;
        };
        if words.is_empty() || matches!(action, HintKey::Escape | HintKey::Help | HintKey::Up | HintKey::Down | HintKey::Actions) {
            continue;
        }
        out.push(Act::key(&words.to_lowercase(), &key.join(" "), Target::Key(action)));
    }
    out
}

/// The item lit, or where nothing is lit the first one a page can say something of: a place shows its first row's
/// page until a row is lit, never an empty middle.
pub(super) fn shown(app: &App, items: &[Item]) -> Option<(usize, Item)> {
    let _ = items;
    let n = app.shown_pick()?;
    app.picks().get(n).cloned().map(|it| (n, it))
}

/// The page of a place's row lit (notes, system, power, workspaces, help): by what the row is.
pub(super) fn place(app: &App, pen: &Pen, f: &Frame, items: &[Item]) -> Look {
    let room = f.page.right - f.page.left;
    let Some((n, it)) = shown(app, items) else { return Look::default() };
    if let Item::Key(words, key) = &it {
        return help(app, pen, items, n, words, key);
    }
    let (Some(p), Some(r)) = (app.prov_of(&it), app.row_ref(&it)) else {
        return Look::default();
    };
    match app.providers[p].label.as_str() {
        "power" => power(app, pen, p, r, room),
        "window" | "layout" => workspace(app, pen, p, r, room),
        _ => {
            let mut look = row(app, pen, p, r, room);
            if app.providers[p].label == "notes" && r.page.is_some() {
                look.what = std::iter::once("a note".to_string())
                    .chain(r.columns.iter().filter(|c| !c.is_empty()).cloned())
                    .collect::<Vec<_>>()
                    .join(crate::ui::SEP);
            }
            look
        }
    }
}

/// Power's page of a step: what it does in its provider's words, and what becomes of the windows open, each named.
fn power(app: &App, pen: &Pen, p: usize, r: &model::Row, room: f64) -> Look {
    let m = *pen.m;
    let mut look = row(app, pen, p, r, room);
    look.body.clear();
    let said = does(app, p, r);
    let (first, rest) = match said.find(". ") {
        Some(at) => (said[..=at].to_string(), said[at + 2..].trim().to_string()),
        None => (said.clone(), String::new()),
    };
    look.what = first.trim_end_matches('.').to_lowercase();
    if !rest.is_empty() {
        look.body.extend(prose(&m, &rest, room, false));
        look.body.push(air(&m, 12.0));
    }
    let windows = windows(app);
    let keeps = r.group.as_deref().is_some_and(|g| g.starts_with("keeps"));
    look.facts = vec![
        (
            "windows".to_string(),
            match (windows.len(), keeps) {
                (0, _) => "none open".to_string(),
                (n, true) => format!("{n} kept"),
                (n, false) => format!("{n} closed"),
            },
        ),
        ("this session".to_string(), app.providers[p].title.trim().to_string()),
    ];
    look.facts.retain(|(_, v)| !v.is_empty());
    if !windows.is_empty() && r.tool.is_some() {
        look.body.push(head(&m, if keeps { "stays open" } else { "closes" }));
        for (name, title, _) in windows {
            look.body.push(named(&m, &name, &title));
        }
    }
    if let Some(k) = &r.key {
        look.acts.push(Act::Gap);
        look.acts.push(Act::Note(format!("anywhere on the desktop: {k}")));
    }
    look
}

/// The windows open, as the workspaces place lists them: each one's app, its title, its workspace's heading.
fn windows(app: &App) -> Vec<(String, String, String)> {
    let Some(p) = app.providers.iter().find(|p| p.label == "window" && p.dead.is_none()) else {
        return vec![];
    };
    p.rows
        .rows
        .iter()
        .filter(|r| r.tool.as_ref().is_some_and(|t| t.name == "window_focus"))
        .map(|r| (r.text.to_lowercase(), r.columns.join(crate::ui::SEP), r.group.clone().unwrap_or_default()))
        .collect()
}

/// A workspace of the map: its name, whether it is the one in use, its windows (each its app, its title, whether it
/// is the row lit).
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Space {
    pub name: String,
    pub this: bool,
    pub windows: Vec<(String, String, bool)>,
}

/// The screens with their workspaces, as the map of the workspaces place draws them (v0.174): each screen its name,
/// its shape, its workspaces.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Desk {
    pub screens: Vec<(String, f64, Vec<Space>)>,
}

/// The map's measures, in the sheets' pixels: a workspace's height, the air between two, a screen's name over them,
/// a workspace's name under it.
const SPACE_H: f64 = 118.0;
const SPACE_AIR: f64 = 20.0;
const SCREEN_HEAD: f64 = 30.0;
const SPACE_FOOT: f64 = 30.0;

impl Desk {
    /// The map of the window section's rows; the row whose id is `lit` is the window lit.
    fn of(app: &App, lit: Option<&str>) -> Desk {
        let mut screens: Vec<(String, f64, Vec<Space>)> = vec![];
        let Some(p) = app.providers.iter().find(|p| p.label == "window" && p.dead.is_none()) else {
            return Desk { screens };
        };
        let shape = |name: &str| {
            app.providers
                .iter()
                .filter(|p| p.label == "display")
                .flat_map(|p| p.rows.rows.iter())
                .filter_map(|r| r.map.as_ref())
                .find_map(|m| m.named(name))
                .map(|s| s.rect.w as f64 / s.rect.h.max(1) as f64)
                .unwrap_or(16.0 / 9.0)
        };
        for r in &p.rows.rows {
            let Some(g) = r.group.as_deref().filter(|g| g.starts_with("workspace")) else {
                continue;
            };
            let words = super::heading_words(g);
            let (name, rest) = super::heading_parts(&words);
            let screen = rest.rsplit(" \u{b7} ").next().unwrap_or("").trim().to_string();
            let this = rest.split(" \u{b7} ").any(|w| w.trim() == "this one");
            if !screens.iter().any(|s| s.0 == screen) {
                screens.push((screen.clone(), shape(&screen), vec![]));
            }
            let Some(at) = screens.iter_mut().find(|s| s.0 == screen) else { continue };
            if !at.2.iter().any(|s| s.name == name) {
                at.2.push(Space {
                    name: name.to_string(),
                    this,
                    windows: vec![],
                });
            }
            if let (Some(space), true) = (
                at.2.iter_mut().find(|s| s.name == name),
                r.tool.as_ref().is_some_and(|t| t.name == "window_focus"),
            ) {
                space
                    .windows
                    .push((r.text.to_lowercase(), r.columns.join(crate::ui::SEP), lit == Some(r.id.as_str())));
            }
        }
        Desk { screens }
    }

    /// Its height in a page this wide: each screen's name, then its workspaces in rows as many as the width holds.
    fn height(&self, m: &Metrics, w: f64) -> f64 {
        self.screens
            .iter()
            .map(|(_, shape, spaces)| {
                let sw = (m.px(SPACE_H) * shape).round();
                let across = ((w + m.px(SPACE_AIR)) / (sw + m.px(SPACE_AIR))).floor().max(1.0) as usize;
                let lines = spaces.len().div_ceil(across).max(1) as f64;
                m.px(SCREEN_HEAD) + lines * (m.px(SPACE_H) + m.px(SPACE_FOOT)) + m.px(12.0)
            })
            .sum()
    }
}

/// The map drawn: each screen's name small in the accent, then its workspaces, each a picture of the screen's shape
/// with its windows side by side in it, the window lit in the accent, the workspace in use framed; its name under it.
pub(super) fn draw_desk(pen: &mut Pen, d: &Desk, x: f64, top: f64, w: f64, bottom: f64) {
    let m = *pen.m;
    let t = pen.t;
    let mut y = top;
    for (screen, shape, spaces) in &d.screens {
        if y + m.px(SCREEN_HEAD) + m.px(SPACE_H) + m.px(SPACE_FOOT) > bottom {
            break;
        }
        let name = pen.fit(screen, Size::Small, w);
        pen.text(x, y + m.px(20.0), &name, Size::Small, t.accent, true);
        y += m.px(SCREEN_HEAD);
        let (sh, sw) = (m.px(SPACE_H), (m.px(SPACE_H) * shape).round().min(w));
        let mut sx = x;
        for s in spaces {
            if sx > x && sx + sw > x + w {
                sx = x;
                y += sh + m.px(SPACE_FOOT);
            }
            // what the page's foot would cut is left out: the list says every workspace
            if y + sh + m.px(SPACE_FOOT) > bottom {
                break;
            }
            pen.fill(sx, y, sw, sh, t.panel);
            let edge = if s.this { t.accent } else { t.lit };
            for (fx, fy, fw, fh) in [(sx, y, sw, 1.0), (sx, y + sh - 1.0, sw, 1.0), (sx, y, 1.0, sh), (sx + sw - 1.0, y, 1.0, sh)] {
                pen.fill(fx, fy, fw, fh, edge);
            }
            let n = s.windows.len();
            let pad = m.px(6.0);
            if n == 0 {
                let say = pen.fit("empty", Size::Small, sw - 2.0 * pad);
                pen.text(sx + pad + m.px(4.0), y + sh / 2.0 + m.sup / 2.0, &say, Size::Small, t.muted, false);
            }
            for (i, (app_name, title, lit)) in s.windows.iter().enumerate() {
                let edge = |k: usize| ((sw - 2.0 * pad) * k as f64 / n as f64).round();
                let (tx, tw) = (sx + pad + edge(i), edge(i + 1) - edge(i) - if i + 1 < n { pad } else { 0.0 });
                let (ty, th) = (y + pad, sh - 2.0 * pad);
                pen.fill(tx, ty, tw, th, if *lit { blend(t.lit, t.accent, 0.35) } else { t.lit });
                if *lit {
                    for (fx, fy, fw, fh) in [(tx, ty, tw, 2.0), (tx, ty + th - 2.0, tw, 2.0), (tx, ty, 2.0, th), (tx + tw - 2.0, ty, 2.0, th)] {
                        pen.fill(fx, fy, fw, fh, t.accent);
                    }
                }
                let room = tw - m.px(12.0);
                if room > 3.0 * m.sw {
                    let a = pen.fit(app_name, Size::Small, room);
                    pen.text(tx + m.px(6.0), ty + m.px(6.0) + m.sup, &a, Size::Small, t.ink, *lit);
                    let tt = pen.fit(title, Size::Small, room);
                    pen.text(tx + m.px(6.0), ty + m.px(6.0) + m.sup + m.sh, &tt, Size::Small, t.muted, false);
                }
            }
            let label = if s.this {
                format!("{}{}this one", s.name, crate::ui::SEP)
            } else {
                s.name.clone()
            };
            let label = pen.fit(&label, Size::Small, sw.max(m.px(140.0)));
            pen.text(sx, y + sh + m.px(20.0), &label, Size::Small, if s.this { t.ink } else { t.muted }, false);
            sx += sw + m.px(SPACE_AIR);
        }
        y += sh + m.px(SPACE_FOOT) + m.px(12.0);
    }
}

/// The workspaces place's page of a row: a window's name, its title, its facts, then the map of the screens with their
/// windows, the one lit in the accent; any other row its own page over the map.
fn workspace(app: &App, pen: &Pen, p: usize, r: &model::Row, room: f64) -> Look {
    let m = *pen.m;
    let mut look = row(app, pen, p, r, room);
    let window = r.tool.as_ref().is_some_and(|t| t.name == "window_focus");
    if window {
        look.name = r.text.to_lowercase();
        look.body.clear();
        // the workspace's number is said once
        for (_, v) in look.facts.iter_mut() {
            *v = super::heading_words(v);
        }
    }
    let desk = Desk::of(app, window.then_some(r.id.as_str()));
    if !desk.screens.is_empty() {
        if !look.body.is_empty() {
            look.body.push(air(&m, 16.0));
        }
        look.body.push(head(&m, "your screens"));
        look.body.push(Row {
            h: desk.height(&m, room - m.px(24.0)),
            pick: None,
            k: K::Desk(Box::new(desk)),
        });
    }
    look
}

/// Help's page of a key: the key in large type, what it does under it, then the keys of its group, the lit one marked;
/// beside it the groups, a click away.
fn help(app: &App, pen: &Pen, items: &[Item], n: usize, words: &str, key: &str) -> Look {
    let m = *pen.m;
    let mut group = String::new();
    let mut groups: Vec<(String, Option<usize>)> = vec![];
    let mut mine: Vec<(String, String, bool)> = vec![];
    let mut pick = 0;
    let mut current = String::new();
    for it in items {
        match it {
            Item::Heading(h) => {
                current = h.clone();
                groups.push((h.clone(), None));
            }
            Item::Key(w, k) => {
                if let Some(g) = groups.last_mut().filter(|g| g.1.is_none()) {
                    g.1 = Some(pick);
                }
                let lit = pick == n;
                if lit {
                    group = current.clone();
                }
                mine.push((current.clone(), format!("{w}\u{1f}{k}"), lit));
            }
            _ => {}
        }
        if app.pickable_item(it) {
            pick += 1;
        }
    }
    let mut look = Look {
        name: if key.is_empty() { words.to_string() } else { key.to_string() },
        what: if key.is_empty() { String::new() } else { words.to_string() },
        ..Look::default()
    };
    if !group.is_empty() {
        look.body.push(head(&m, &group));
        for (g, wk, lit) in mine.into_iter().filter(|(g, ..)| *g == group) {
            let _ = g;
            let (w, k) = wk.split_once('\u{1f}').unwrap_or((&wk, ""));
            look.body.push(Row {
                h: m.px(36.0),
                pick: None,
                k: K::One {
                    icon: None,
                    sign: if lit { "dot" } else { "blank" },
                    swatch: vec![],
                    name: w.to_string(),
                    muted: !lit,
                    words: String::new(),
                    end: End::None,
                    tail: false,
                    key: k.to_string(),
                },
            });
        }
    }
    look.acts.push(Act::Head("groups".to_string()));
    for (g, first) in groups {
        if let Some(first) = first {
            look.acts.push(Act::Do {
                words: g.clone(),
                key: String::new(),
                value: String::new(),
                on: g == group,
                target: Some(Target::Pick(first)),
            });
        }
    }
    look
}

/// A month of the Calendar's page (v0.174): its year and month, the day lit, today where it is in it, and each day's
/// reminders.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Month {
    pub year: i32,
    pub month: u32,
    pub lit: Option<u32>,
    pub today: Option<u32>,
    pub monday: bool,
    pub days: Vec<(u32, String)>,
}

/// A week's height in the month, and the row of the days' initials over the weeks, in the sheets' pixels.
const WEEK_H: f64 = 66.0;
const DAYS_H: f64 = 34.0;

impl Month {
    pub(super) fn height(&self, m: &Metrics) -> f64 {
        let weeks = crate::calendar::weeks_from(self.year, self.month, self.monday).len().max(1) as f64;
        m.px(DAYS_H) + weeks * m.px(WEEK_H)
    }
}

/// The month drawn as a page has it: the days' initials, then a week a line, each day its number at its corner, today
/// in the accent and underlined, the day lit on the lit row's ground, a day's first reminder under its number.
pub(super) fn draw_month(pen: &mut Pen, mo: &Month, x: f64, top: f64, w: f64, bottom: f64) {
    use crate::calendar::{weeks_from, DAYS};
    let m = *pen.m;
    let t = pen.t;
    let cw = (w / 7.0).floor();
    if top + m.px(DAYS_H) > bottom {
        return;
    }
    for i in 0..7 {
        let d = DAYS[(i + usize::from(mo.monday)) % 7];
        pen.text(x + i as f64 * cw + m.px(10.0), top + m.px(20.0), d, Size::Small, t.muted, false);
    }
    pen.fill(x, top + m.px(DAYS_H) - 1.0, cw * 7.0, 1.0, t.lit);
    for (k, wk) in weeks_from(mo.year, mo.month, mo.monday).iter().enumerate() {
        let wy = top + m.px(DAYS_H) + k as f64 * m.px(WEEK_H);
        if wy + m.px(WEEK_H) > bottom {
            break;
        }
        for (i, d) in wk.iter().enumerate() {
            let Some(d) = d else { continue };
            let cx = x + i as f64 * cw;
            let (today, lit) = (mo.today == Some(*d), mo.lit == Some(*d));
            if lit {
                pen.fill(cx + 2.0, wy + 2.0, cw - 4.0, m.px(WEEK_H) - 4.0, t.lit);
            }
            let said: Vec<&String> = mo.days.iter().filter(|(day, _)| day == d).map(|(_, s)| s).collect();
            let color = if today { t.accent } else { t.ink };
            let base = wy + m.px(26.0);
            let nw = pen.text(cx + m.px(10.0), base, &d.to_string(), Size::Main, color, today || lit);
            if today {
                pen.fill(cx + m.px(10.0), base + m.px(5.0), nw, 2.0, t.accent);
            }
            if let Some(first) = said.first() {
                pen.fill(cx + m.px(10.0), base + m.px(15.0), m.px(6.0), m.px(6.0), t.accent);
                let room = cw - m.px(30.0);
                let more = if said.len() > 1 { format!(" +{}", said.len() - 1) } else { String::new() };
                let words = pen.fit(&format!("{first}{more}"), Size::Small, room);
                pen.text(
                    cx + m.px(22.0),
                    base + m.px(22.0),
                    &words,
                    Size::Small,
                    if lit { t.ink } else { t.muted },
                    false,
                );
            }
        }
    }
}

/// The Calendar's page: the month of the reminder lit, else the month shown, large, each day's reminders in it; over it
/// the day lit or today; beside it a new reminder, the months before and after, and the lit reminder's own steps.
pub(super) fn calendar(app: &App, pen: &Pen, f: &Frame, items: &[Item]) -> Look {
    use crate::calendar::{shift, weekday, ymd, MONTHS};
    const WEEKDAYS: [&str; 7] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    let m = *pen.m;
    let room = f.page.right - f.page.left;
    let Some((ty, tm, td)) = app.today else { return Look::default() };
    let lit = super::lit(app).and_then(|n| app.picks().get(n).cloned());
    let lit_row = lit.as_ref().and_then(|it| Some((app.prov_of(it)?, app.row_ref(it)?)));
    let lit_day = lit_row.and_then(|(_, r)| ymd(r.date.as_deref()?));
    let (year, month) = match lit_day {
        Some((y, mo, _)) if app.month_offset == 0 => (y, mo),
        _ => shift(ty, tm, app.month_offset),
    };
    let reminders: Vec<(i32, u32, u32, String, String)> = app
        .providers
        .iter()
        .filter(|p| p.label == "reminders")
        .flat_map(|p| p.rows.rows.iter())
        .filter_map(|r| {
            let (y, mo, d) = ymd(r.date.as_deref()?)?;
            Some((y, mo, d, r.text.clone(), r.columns.first().cloned().unwrap_or_default()))
        })
        .collect();
    let mine: Vec<&(i32, u32, u32, String, String)> = reminders.iter().filter(|r| (r.0, r.1) == (year, month)).collect();
    let day = lit_day
        .or(((year, month) == (ty, tm)).then_some((ty, tm, td)))
        .filter(|d| (d.0, d.1) == (year, month))
        .map(|d| d.2);
    let mo = Month {
        year,
        month,
        lit: day,
        today: ((year, month) == (ty, tm)).then_some(td),
        monday: app.monday_first,
        days: mine.iter().map(|r| (r.2, r.3.clone())).collect(),
    };
    let (dy, dm, dd) = lit_day.unwrap_or((ty, tm, td));
    let _ = lit_row;
    let named = format!("{} {} {}", WEEKDAYS[weekday(dy, dm, dd) as usize % 7], dd, MONTHS[(dm - 1) as usize]);
    let what = if (dy, dm, dd) == (ty, tm, td) { format!("today, {named}") } else { named };
    let count = |n: usize| if n == 1 { "1 reminder".to_string() } else { format!("{n} reminders") };
    let ahead = reminders.iter().filter(|r| (r.0, r.1, r.2) >= (ty, tm, td)).count();
    let mut look = Look {
        name: format!("{} {}", MONTHS[(month - 1) as usize], year),
        what,
        facts: vec![("this month".to_string(), count(mine.len())), ("ahead".to_string(), count(ahead))],
        ..Look::default()
    };
    if let Some(zone) = app
        .providers
        .iter()
        .filter(|p| p.label == "clock")
        .flat_map(|p| p.rows.rows.iter())
        .find_map(|r| r.columns.first().filter(|c| c.contains('/')).cloned())
    {
        look.facts
            .push(("time".to_string(), zone.split(',').next().unwrap_or(&zone).trim().to_string()));
    }
    look.body.push(Row {
        h: mo.height(&m),
        pick: None,
        k: K::Month(Box::new(mo)),
    });
    // the day lit: its reminders, each at its hour
    if let Some(d) = day {
        let on: Vec<&&(i32, u32, u32, String, String)> = mine.iter().filter(|r| r.2 == d).collect();
        if !on.is_empty() {
            look.body.push(air(&m, 12.0));
            for r in on {
                look.body.push(pair(&m, &r.4, &r.3));
            }
        }
    }
    let _ = (room, items);
    let keys = &app.cfg.keys;
    look.acts.push(Act::key("new reminder", keys.label(HintKey::New), Target::Key(HintKey::New)));
    look.acts.push(Act::key("month before", "\u{2190}", Target::Key(HintKey::Left)));
    look.acts.push(Act::key("month after", "\u{2192}", Target::Key(HintKey::Right)));
    if let Some((_, r)) = lit_row.filter(|_| lit_day.is_some()) {
        look.acts.push(Act::Gap);
        look.acts.extend(row_acts(app, r));
    }
    look
}

/// Home's page of a place (v0.174): its name, what it holds now, and a glimpse of it, the first of its rows as its
/// own page lists them; open beside it.
pub(super) fn dest(app: &App, pen: &Pen, d: usize, room: f64) -> Look {
    use crate::app::{DESTS, SETTINGS};
    let m = *pen.m;
    let dest = &DESTS[d];
    let mut look = Look {
        name: dest.name.to_string(),
        what: app.dest_state(d).unwrap_or_else(|| dest.purpose.to_string()),
        acts: vec![Act::key("open", app.cfg.keys.label(HintKey::Enter), Target::Key(HintKey::Enter))],
        ..Look::default()
    };
    if look.what != dest.purpose {
        look.body.extend(prose(&m, dest.purpose, room, true));
        look.body.push(air(&m, 12.0));
    }
    let shape = Shape {
        still: true,
        ..super::PLACE_SHAPE
    };
    let mut glimpse: Vec<Row> = match dest.name {
        "settings" => {
            let items: Vec<Item> = (0..SETTINGS.len()).map(Item::Setting).collect();
            super::rows_of(app, pen, &items, shape, room)
        }
        "apps" => {
            let items: Vec<Item> = app
                .apps
                .lines_of(&crate::apps::Page::List, 60, "", 0)
                .into_iter()
                .filter(|l| l.heading || matches!(l.action, Some(crate::apps::Action::Launch(_))))
                .map(Item::Apps)
                .collect();
            super::rows_of(app, pen, &items, Shape { pad: 12.0, ..shape }, room)
        }
        "help" => app
            .help_rows()
            .into_iter()
            .filter(|(g, ..)| g == "general")
            .map(|(_, w, k)| Row {
                h: m.px(36.0),
                pick: None,
                k: K::One {
                    icon: None,
                    sign: "",
                    swatch: vec![],
                    name: w,
                    muted: false,
                    words: String::new(),
                    end: End::None,
                    tail: false,
                    key: k,
                },
            })
            .collect(),
        // your home folder's own page: what it holds by kind, its newest and largest files
        "files" => app
            .home_page(d)
            .and_then(|(uri, _)| app.files.peek.as_ref().filter(|pk| pk.uri == uri))
            .and_then(|pk| pk.page.as_ref())
            .and_then(facts_of)
            .map(|(_, blocks)| rows_of_blocks(&m, blocks, room, false))
            .unwrap_or_default(),
        "workspaces" => {
            let desk = Desk::of(app, None);
            if desk.screens.is_empty() {
                vec![]
            } else {
                vec![
                    head(&m, "your screens"),
                    Row {
                        h: desk.height(&m, room - m.px(24.0)),
                        pick: None,
                        k: K::Desk(Box::new(desk)),
                    },
                ]
            }
        }
        _ => {
            let mut rows = vec![];
            for s in dest.sections {
                if let Some(p) = app.providers.iter().position(|p| p.label == *s && p.dead.is_none()) {
                    let items: Vec<Item> = app
                        .section_items(p)
                        .into_iter()
                        .filter(|it| app.row_ref(it).is_none_or(|r| r.when_model.is_none_or(|w| w == app.answers())))
                        .collect();
                    rows.extend(super::place_rows(app, pen, &items, room));
                }
            }
            rows
        }
    };
    for r in glimpse.iter_mut() {
        r.pick = None;
        if let K::One { key, .. } = &mut r.k {
            if dest.name != "help" {
                key.clear();
            }
        }
    }
    look.body.extend(glimpse);
    look
}
