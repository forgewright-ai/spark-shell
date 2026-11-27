//! The status's arrangement, as the pointer and the keys change it: where a dragged module or its group would
//! land, the move that says it in the verb's own words, and the line's modules after it. Plain functions and no
//! screen. The shell makes the same move in src/arrange.sh, and one table of cases (test/move_cases.json) holds
//! the two to one answer.

use crate::bar::{Layout, Module, LOGO, PAD_ROOM, TIME};

/// A module as it stands on a bar: from its first part's left to its last part's right.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Span {
    pub name: String,
    pub group: String,
    pub x: i32,
    pub right: i32,
}

impl Span {
    fn middle(&self) -> i32 {
        (self.x + self.right) / 2
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Before,
    After,
}

impl Side {
    pub fn word(self) -> &'static str {
        match self {
            Side::Before => "before",
            Side::After => "after",
        }
    }
}

/// A move, in the verb's words: a module to a place inside its group, or a group to a place among the groups.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Move {
    /// The module that moves, or its group.
    pub what: String,
    pub side: Side,
    /// What it lands beside: a module of the same group, or another group.
    pub other: String,
    /// `what` and `other` are groups.
    pub group: bool,
}

impl Move {
    /// The move as the click's one word: what, the side and the other, a colon between.
    pub fn word(&self) -> String {
        format!("{}:{}:{}", self.what, self.side.word(), self.other)
    }
}

/// The modules a person can move, as a layout drew them, in the bar's order: each from its first part to its last.
/// The time's group, the mark and the pad's room are the bar's own and are not among them.
pub fn spans(layout: &Layout, modules: &[Module]) -> Vec<Span> {
    modules
        .iter()
        .filter(|m| m.group != TIME && m.name != LOGO && m.name != PAD_ROOM)
        .filter_map(|m| {
            let lead = format!("{}.", m.name);
            let parts = layout.targets.iter().filter(|t| t.id.starts_with(&lead)).map(|t| t.rect);
            let (x, right) = parts.fold((i32::MAX, i32::MIN), |(x, right), r| (x.min(r.x), right.max(r.right())));
            (x < right).then(|| Span {
                name: m.name.clone(),
                group: m.group.clone(),
                x,
                right,
            })
        })
        .collect()
}

/// The groups of some spans, in their order: each from its first module to its last.
fn groups(spans: &[Span]) -> Vec<Span> {
    let mut out: Vec<Span> = vec![];
    for s in spans {
        match out.iter_mut().find(|g| g.name == s.group) {
            Some(g) => (g.x, g.right) = (g.x.min(s.x), g.right.max(s.right)),
            None => out.push(Span {
                name: s.group.clone(),
                group: s.group.clone(),
                x: s.x,
                right: s.right,
            }),
        }
    }
    out
}

/// The place `me` takes among `row` when it is let go at `x`: before the first of the others whose middle is right
/// of `x`, else after the last. None where that is the place it has, or where it stands alone.
fn place(row: &[Span], me: &str, x: i32, group: bool) -> Option<Move> {
    let at = row.iter().position(|s| s.name == me)?;
    let others: Vec<&Span> = row.iter().filter(|s| s.name != me).collect();
    let k = others.iter().filter(|s| s.middle() < x).count();
    if k == at || others.is_empty() {
        return None;
    }
    let (side, other) = match others.get(k) {
        Some(s) => (Side::Before, *s),
        None => (Side::After, *others.last()?),
    };
    Some(Move {
        what: me.to_string(),
        side,
        other: other.name.clone(),
        group,
    })
}

/// Where a module dragged to `x` would land. Within its own group, and `reach` pixels at each side of it, it takes
/// a place among the group's modules. Past that the whole group moves, to a place among the groups: the modules
/// of a group stand together. None where everything would stand as it does.
pub fn landing(spans: &[Span], name: &str, x: i32, reach: i32) -> Option<Move> {
    let me = spans.iter().find(|s| s.name == name)?;
    let all = groups(spans);
    let mine = all.iter().find(|g| g.name == me.group)?;
    if x >= mine.x - reach && x < mine.right + reach {
        let row: Vec<Span> = spans.iter().filter(|s| s.group == me.group).cloned().collect();
        place(&row, name, x, false)
    } else {
        place(&all, &me.group, x, true)
    }
}

/// One step of a module to the left or the right, as a key asks it: past the module beside it in its group, and
/// from its group's end the whole group past the next one. None at the status's end.
pub fn step(spans: &[Span], name: &str, left: bool) -> Option<Move> {
    let me = spans.iter().find(|s| s.name == name)?;
    let beside = |row: &[Span], who: &str, group: bool| {
        let at = row.iter().position(|s| s.name == who)?;
        let other = if left { row.get(at.checked_sub(1)?)? } else { row.get(at + 1)? };
        Some(Move {
            what: who.to_string(),
            side: if left { Side::Before } else { Side::After },
            other: other.name.clone(),
            group,
        })
    };
    let row: Vec<Span> = spans.iter().filter(|s| s.group == me.group).cloned().collect();
    beside(&row, name, false).or_else(|| beside(&groups(spans), &me.group, true))
}

/// Where the line that shows a landing stands, its middle: `room` pixels off the edge of what the move lands
/// beside, the middle of the room between the two.
pub fn line(spans: &[Span], mv: &Move, room: i32) -> Option<i32> {
    let row = if mv.group { groups(spans) } else { spans.to_vec() };
    let other = row.iter().find(|s| s.name == mv.other)?;
    Some(match mv.side {
        Side::Before => other.x - room,
        Side::After => other.right + room,
    })
}

/// The line's modules after a move, every other one as it stood: what a bar draws from a drop until a line says it.
pub fn moved(modules: &[Module], mv: &Move) -> Vec<Module> {
    let takes = |m: &Module| if mv.group { m.group == mv.what } else { m.name == mv.what };
    let lands = |m: &Module| if mv.group { m.group == mv.other } else { m.name == mv.other };
    let block: Vec<Module> = modules.iter().filter(|m| takes(m)).cloned().collect();
    let mut rest: Vec<Module> = modules.iter().filter(|m| !takes(m)).cloned().collect();
    let at = match mv.side {
        Side::Before => rest.iter().position(lands),
        Side::After => rest.iter().rposition(lands).map(|i| i + 1),
    };
    match at {
        Some(at) if !block.is_empty() => {
            rest.splice(at..at, block);
            rest
        }
        _ => modules.to_vec(),
    }
}

/// The names of some modules, in their order.
pub fn names(modules: &[Module]) -> Vec<String> {
    modules.iter().map(|m| m.name.clone()).collect()
}

/// Whether a line's modules stand in the order a bar holds: the names both have come in the same order. A module
/// that came or went since says nothing against it.
pub fn agrees(held: &[String], line: &[String]) -> bool {
    let both = |from: &[String], with: &[String]| -> Vec<String> { from.iter().filter(|n| with.contains(n)).cloned().collect() };
    both(held, line) == both(line, held)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A status as a bar drew it: each module ten pixels wide, twenty between two of a group, forty between groups.
    fn status(said: &[(&str, &str)]) -> Vec<Span> {
        let mut x = 100;
        let mut out: Vec<Span> = vec![];
        for (name, group) in said {
            if let Some(last) = out.last() {
                x = last.right + if last.group == *group { 20 } else { 40 };
            }
            out.push(Span {
                name: name.to_string(),
                group: group.to_string(),
                x,
                right: x + 10,
            });
        }
        out
    }

    const BAR: [(&str, &str); 6] = [("lan", "network"), ("wifi", "network"), ("out", "sound"), ("mic", "sound"), ("light", "screen"), ("kb", "screen")];

    fn mv(what: &str, side: Side, other: &str, group: bool) -> Option<Move> {
        Some(Move {
            what: what.into(),
            side,
            other: other.into(),
            group,
        })
    }

    fn at(spans: &[Span], name: &str) -> i32 {
        spans.iter().find(|s| s.name == name).map(Span::middle).unwrap()
    }

    #[test]
    fn a_module_let_go_inside_its_group_takes_a_place_there() {
        let s = status(&BAR);
        // the microphone left of the volume's middle: before it; where it stands, and right of it: nothing moves
        assert_eq!(landing(&s, "mic", at(&s, "out") - 1, 20), mv("mic", Side::Before, "out", false));
        assert_eq!(landing(&s, "mic", at(&s, "mic"), 20), None);
        assert_eq!(landing(&s, "mic", at(&s, "mic") + 14, 20), None, "inside the reach past its group's end: still its own place");
        // the volume right of the microphone's middle: after it
        assert_eq!(landing(&s, "out", at(&s, "mic") + 1, 20), mv("out", Side::After, "mic", false));
        assert_eq!(landing(&s, "out", at(&s, "out"), 20), None);
    }

    #[test]
    fn a_module_let_go_past_its_group_moves_the_whole_group() {
        let s = status(&BAR);
        // brightness dragged left of sound: screen stands before sound; farther, before network
        assert_eq!(landing(&s, "light", at(&s, "out") - 30, 20), mv("screen", Side::Before, "sound", true));
        assert_eq!(landing(&s, "light", 0, 20), mv("screen", Side::Before, "network", true));
        // the wire dragged past everything: network after the last group
        assert_eq!(landing(&s, "lan", 10_000, 20), mv("network", Side::After, "screen", true));
        // sound dragged a little into the room at its side: nothing
        assert_eq!(landing(&s, "out", at(&s, "wifi") + 16, 20), None, "past its reach, yet not past the next group's middle");
        // a module that is not on the bar, and a status of one module
        assert_eq!(landing(&s, "bat", 0, 20), None);
        assert_eq!(landing(&status(&[("out", "sound")]), "out", 0, 20), None);
    }

    #[test]
    fn a_step_passes_the_module_beside_it_and_from_the_groups_end_the_next_group() {
        let s = status(&BAR);
        assert_eq!(step(&s, "mic", true), mv("mic", Side::Before, "out", false));
        assert_eq!(step(&s, "out", false), mv("out", Side::After, "mic", false));
        assert_eq!(step(&s, "out", true), mv("sound", Side::Before, "network", true), "first in its group: the group goes");
        assert_eq!(step(&s, "mic", false), mv("sound", Side::After, "screen", true));
        assert_eq!(step(&s, "lan", true), None, "the status's left end");
        assert_eq!(step(&s, "kb", false), None, "the status's right end");
        assert_eq!(step(&s, "bat", true), None);
    }

    #[test]
    fn the_landings_line_stands_in_the_room_beside_what_it_lands_by() {
        let s = status(&BAR);
        let before = mv("mic", Side::Before, "out", false).unwrap();
        assert_eq!(line(&s, &before, 10), Some(s[2].x - 10));
        let after = mv("network", Side::After, "screen", true).unwrap();
        assert_eq!(line(&s, &after, 20), Some(s[5].right + 20));
        let group = mv("screen", Side::Before, "sound", true).unwrap();
        assert_eq!(line(&s, &group, 20), Some(s[2].x - 20), "a group's edge is its first module's");
        assert_eq!(line(&s, &mv("mic", Side::Before, "bat", false).unwrap(), 10), None);
    }

    fn module(name: &str, group: &str) -> Module {
        Module {
            name: name.into(),
            group: group.into(),
            ..Module::default()
        }
    }

    fn line_of(said: &str, groups: &serde_json::Value) -> Vec<Module> {
        said.split_whitespace().map(|n| module(n, groups[n].as_str().unwrap_or("time"))).collect()
    }

    /// The table the shell's suite reads too: an order, a move in the verb's words, and the order after it. A move
    /// the verb refuses has no order after it: the bar never asks for one, and here it changes nothing.
    #[test]
    fn a_move_gives_the_order_the_shells_verb_gives() {
        let table: serde_json::Value = serde_json::from_str(include_str!("../../../test/move_cases.json")).unwrap();
        let groups = &table["groups"];
        let is_group = |w: &str| groups.as_object().unwrap().values().any(|g| g == w);
        let cases = table["cases"].as_array().unwrap();
        assert!(cases.len() >= 10, "the table is read: {} cases", cases.len());
        for case in cases {
            let said = |k: &str| case[k].as_str().unwrap_or_default().to_string();
            let words: Vec<String> = said("move").split_whitespace().map(String::from).collect();
            let [what, side, other] = words.as_slice() else { continue };   // first, last and a step are the shell's alone
            let side = match side.as_str() {
                "before" => Side::Before,
                "after" => Side::After,
                _ => continue,
            };
            let before = line_of(&said("order"), groups);
            let m = Move {
                what: what.clone(),
                side,
                other: if is_group(what) && !is_group(other) { groups[other.as_str()].as_str().unwrap_or_default().to_string() } else { other.clone() },
                group: is_group(what),
            };
            let after = names(&moved(&before, &m)).join(" ");
            let want = if case["to"].is_null() { said("order") } else { said("to") };
            if case["to"].is_null() && !is_group(what) && groups[what.as_str()] != groups[other.as_str()] {
                continue;   // a module asked past its group: refused by the verb, and never asked by the bar (landing)
            }
            assert_eq!(after, want, "{}: {}", said("order"), said("move"));
        }
    }

    #[test]
    fn a_move_leaves_the_bars_own_modules_where_they_stand() {
        let line: Vec<Module> = [("room", "pad"), ("lan", "network"), ("out", "sound"), ("mic", "sound"), ("clock", "time")]
            .iter()
            .map(|(n, g)| module(n, g))
            .collect();
        let m = mv("sound", Side::Before, "network", true).unwrap();
        assert_eq!(names(&moved(&line, &m)), ["room", "out", "mic", "lan", "clock"]);
        // a move that names what the line does not have changes nothing
        let m = mv("bat", Side::Before, "lan", false).unwrap();
        assert_eq!(moved(&line, &m), line);
        let m = mv("out", Side::After, "bat", false).unwrap();
        assert_eq!(moved(&line, &m), line);
    }

    #[test]
    fn a_line_agrees_with_a_held_order_by_the_names_both_have() {
        let n = |s: &str| -> Vec<String> { s.split_whitespace().map(String::from).collect() };
        assert!(agrees(&n("lan out mic"), &n("lan out mic")));
        assert!(agrees(&n("lan out mic"), &n("media lan out mic clock")), "a module that came says nothing against it");
        assert!(agrees(&n("lan out mic"), &n("lan mic")), "nor one that went");
        assert!(!agrees(&n("lan mic out"), &n("lan out mic")), "the order before the drop is another");
        assert!(agrees(&n(""), &n("lan")));
    }
}
