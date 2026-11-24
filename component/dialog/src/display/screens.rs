//! The screens as the display page draws them (v0.167): read from a row of its provider, laid to scale in a box, and
//! where one lands that is dragged, or moved to a side of its neighbor by a key. Pure: places in, places out.

use crate::model::{self, Call};
use crate::scrub::{cells, scrub};
use serde_json::Value;

/// The most screens a map holds.
pub const MOST: usize = 16;
/// How far a screen may stand from the layout's origin, and the largest one, in layout pixels.
const REACH: i64 = 65_535;
const LARGEST: i64 = 32_767;

/// A screen's place, in layout pixels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
    pub fn right(&self) -> i32 {
        self.x + self.w
    }
    pub fn bottom(&self) -> i32 {
        self.y + self.h
    }
    fn at(&self, (x, y): (i32, i32)) -> Rect {
        Rect { x, y, ..*self }
    }
    pub fn over(&self, o: &Rect) -> bool {
        self.x < o.right() && o.x < self.right() && self.y < o.bottom() && o.y < self.bottom()
    }
    /// How long the edge is that two screens side by side share: the pointer crosses there.
    fn shared(&self, o: &Rect) -> i32 {
        let down = self.bottom().min(o.bottom()) - self.y.max(o.y);
        let across = self.right().min(o.right()) - self.x.max(o.x);
        if self.right() == o.x || o.right() == self.x {
            down.max(0)
        } else if self.bottom() == o.y || o.bottom() == self.y {
            across.max(0)
        } else {
            0
        }
    }
    fn middle(&self) -> (f64, f64) {
        (self.x as f64 + self.w as f64 / 2.0, self.y as f64 + self.h as f64 / 2.0)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Screen {
    /// The port, which names the screen to the tools, and the words it is called by.
    pub name: String,
    pub text: String,
    /// Its place; for one that is off, its shape alone.
    pub rect: Rect,
    pub on: bool,
    pub main: bool,
    /// A small picture of what it shows, in its own shape.
    pub picture: Option<String>,
    /// The list that is the screen's own page.
    pub children: Option<String>,
}

/// A row that is a map of the screens, and the step that moves one; none where nothing moves them.
#[derive(Clone, Debug, PartialEq)]
pub struct Map {
    pub screens: Vec<Screen>,
    pub step: Option<Call>,
}

/// The shape of a screen that is off and says none.
const PLAIN: Rect = Rect::new(0, 0, 1920, 1080);

fn screen(v: &Value) -> Option<Screen> {
    let name = v.get("name")?.as_str()?;
    if name.is_empty() || name.len() > 80 || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b"_.:-".contains(&b)) {
        return None;
    }
    let on = v.get("on")?.as_bool()?;
    let n = |k: &str, least: i64, most: i64| {
        let n = v.get(k)?.as_i64()?;
        (least..=most).contains(&n).then_some(n as i32)
    };
    let rect = || {
        Some(Rect::new(
            n("x", -REACH, REACH)?,
            n("y", -REACH, REACH)?,
            n("w", 1, LARGEST)?,
            n("h", 1, LARGEST)?,
        ))
    };
    let rect = if on {
        rect()?
    } else {
        match (n("w", 1, LARGEST), n("h", 1, LARGEST)) {
            (Some(w), Some(h)) => Rect::new(0, 0, w, h),
            _ => PLAIN,
        }
    };
    let text = v
        .get("text")
        .and_then(Value::as_str)
        .map(scrub)
        .filter(|t| !t.trim().is_empty() && cells(t) <= 40);
    Some(Screen {
        name: name.to_string(),
        text: text.unwrap_or_else(|| name.to_string()),
        rect,
        on,
        main: on && v.get("main").and_then(Value::as_bool).unwrap_or(false),
        picture: model::preview(v.get("picture")).filter(|_| on),
        children: v
            .get("children")
            .and_then(Value::as_str)
            .filter(|u| u.starts_with("spark-shell://") && u.len() <= 400 && !u.chars().any(char::is_control))
            .map(str::to_string),
    })
}

/// A row's map: its screens, MOST at most, each name once; one that is malformed is left out. None where none is left.
pub fn read(row: &Value) -> Option<Map> {
    let mut screens: Vec<Screen> = vec![];
    for s in row.get("screens")?.as_array()?.iter().filter_map(screen) {
        if screens.len() < MOST && !screens.iter().any(|k| k.name == s.name) {
            screens.push(s);
        }
    }
    (!screens.is_empty()).then(|| Map {
        screens,
        step: row.get("move").and_then(model::call),
    })
}

impl Map {
    pub fn named(&self, name: &str) -> Option<&Screen> {
        self.screens.iter().find(|s| s.name == name)
    }
    /// The screens that are on, but for the one named.
    pub fn others(&self, name: &str) -> Vec<Rect> {
        self.screens.iter().filter(|s| s.on && s.name != name).map(|s| s.rect).collect()
    }
    /// The screen chosen before a key or a click chooses one: the main one, else the first that is on.
    pub fn first(&self) -> Option<&Screen> {
        let on = || self.screens.iter().filter(|s| s.on);
        on().find(|s| s.main).or_else(|| on().next()).or(self.screens.first())
    }
    /// The screens in the order a key walks them: from the left, from the top, the ones that are off last.
    pub fn order(&self) -> Vec<&Screen> {
        let mut v: Vec<&Screen> = self.screens.iter().collect();
        v.sort_by_key(|s| (!s.on, s.rect.x, s.rect.y));
        v
    }
    /// Whether the screen can be moved: it is on, another is, and there is a step for it.
    pub fn moves(&self, name: &str) -> bool {
        self.step.is_some() && self.named(name).is_some_and(|s| s.on) && !self.others(name).is_empty()
    }
    /// Where each screen is drawn, in layout pixels, in the map's own order: its place, and for the ones that are off a
    /// place of their own past the right of the rest, at their foot.
    pub fn places(&self) -> Vec<Rect> {
        let on: Vec<Rect> = self.screens.iter().filter(|s| s.on).map(|s| s.rect).collect();
        let (right, foot) = match bounds(&on) {
            Some(b) => (b.right(), b.bottom()),
            None => (0, PLAIN.h),
        };
        let tall = on.iter().map(|r| r.h).max().unwrap_or(PLAIN.h);
        let air = tall / 8;
        let mut x = right + if on.is_empty() { 0 } else { air };
        self.screens
            .iter()
            .map(|s| {
                if s.on {
                    return s.rect;
                }
                // never taller than the rest: what is off takes no more room than what is on
                let k = (tall as f64 / s.rect.h as f64).min(1.0);
                let (w, h) = (((s.rect.w as f64 * k) as i32).max(1), ((s.rect.h as f64 * k) as i32).max(1));
                let r = Rect::new(x, foot - h, w, h);
                x += w + air;
                r
            })
            .collect()
    }
}

/// The box around places.
pub fn bounds(places: &[Rect]) -> Option<Rect> {
    let x = places.iter().map(|r| r.x).min()?;
    let y = places.iter().map(|r| r.y).min()?;
    let right = places.iter().map(Rect::right).max()?;
    let bottom = places.iter().map(Rect::bottom).max()?;
    Some(Rect::new(x, y, right - x, bottom - y))
}

/// How places are laid in a box of the window: how many of its pixels a layout pixel is, and where the layout's origin
/// stands in it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Fit {
    pub scale: f64,
    pub x: f64,
    pub y: f64,
}

impl Fit {
    /// Places in the middle of a box, as large as the box holds them.
    pub fn new(places: &[Rect], (x, y, w, h): (f64, f64, f64, f64)) -> Option<Fit> {
        let b = bounds(places)?;
        let scale = (w / b.w as f64).min(h / b.h as f64);
        if !scale.is_finite() || scale <= 0.0 {
            return None;
        }
        Some(Fit {
            scale,
            x: x + (w - b.w as f64 * scale) / 2.0 - b.x as f64 * scale,
            y: y + (h - b.h as f64 * scale) / 2.0 - b.y as f64 * scale,
        })
    }
    /// A place in the window's pixels, on whole ones: two that touch there touch here.
    pub fn place(&self, r: &Rect) -> (f64, f64, f64, f64) {
        let (x0, y0) = ((self.x + r.x as f64 * self.scale).round(), (self.y + r.y as f64 * self.scale).round());
        let (x1, y1) = (
            (self.x + r.right() as f64 * self.scale).round(),
            (self.y + r.bottom() as f64 * self.scale).round(),
        );
        (x0, y0, (x1 - x0).max(1.0), (y1 - y0).max(1.0))
    }
}

/// Where a place may stand along one axis, lined up with another: their starts, their ends, their middles, or past it.
fn lines(len: i32, start: i32, size: i32) -> [i32; 5] {
    [start, start + size - len, start + (size - len) / 2, start + size, start - len]
}

/// Where a screen dragged to `want` (its corner, in layout pixels) lands: against the edge of another, over none of
/// them, with enough of the edge shared for the pointer to cross. `near` is how far it is pulled to line up with
/// another's edge or middle. None where there is no other.
pub fn landing(moving: Rect, want: (f64, f64), others: &[Rect], near: f64) -> Option<(i32, i32)> {
    let mut best: Option<(f64, (i32, i32))> = None;
    let mut offer = |at: (i32, i32), beside: &Rect, aligned: bool| {
        let r = moving.at(at);
        let least = (moving.w.min(moving.h).min(beside.w).min(beside.h) / 8).max(1);
        let within = |v: i32| (v as i64).abs() <= REACH;
        if !within(r.x) || !within(r.y) || r.shared(beside) < least || others.iter().any(|o| r.over(o)) {
            return;
        }
        let d = (r.x as f64 - want.0).hypot(r.y as f64 - want.1);
        let cost = d + if aligned { 0.0 } else { near };
        if best.is_none_or(|(c, _)| cost < c) {
            best = Some((cost, at));
        }
    };
    let whole = |v: f64| v.round().clamp(-(REACH as f64), REACH as f64) as i32;
    let (wx, wy) = (whole(want.0), whole(want.1));
    for o in others {
        // where it stood is a line of its own: a small move lets go there again
        offer((moving.x, moving.y), o, true);
        for x in [o.x - moving.w, o.right()] {
            offer((x, wy), o, false);
            for y in others.iter().flat_map(|p| lines(moving.h, p.y, p.h)) {
                offer((x, y), o, true);
            }
            // as far along the edge as it may go
            for y in [o.y - moving.h + o.h.min(moving.h) / 4, o.bottom() - o.h.min(moving.h) / 4] {
                offer((x, y), o, false);
            }
        }
        for y in [o.y - moving.h, o.bottom()] {
            offer((wx, y), o, false);
            for x in others.iter().flat_map(|p| lines(moving.w, p.x, p.w)) {
                offer((x, y), o, true);
            }
            for x in [o.x - moving.w + o.w.min(moving.w) / 4, o.right() - o.w.min(moving.w) / 4] {
                offer((x, y), o, false);
            }
        }
    }
    best.map(|(_, at)| at)
}

/// The side of its neighbor a key moves a screen to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
    Above,
    Below,
}

/// Where a screen goes that a key moves to a side of its neighbor, the screen nearest it: against that edge, where it
/// stood along it if they still share it, else lined up with its start; past any other screen that stands there. None
/// where it is there already, or there is no other.
pub fn beside(moving: Rect, others: &[Rect], side: Side) -> Option<(i32, i32)> {
    let (mx, my) = moving.middle();
    let far = |o: &Rect| {
        // the gap between the two, then their middles
        let gap = |a0: i32, a1: i32, b0: i32, b1: i32| (b0 - a1).max(a0 - b1).max(0) as f64;
        let d = gap(moving.x, moving.right(), o.x, o.right()).hypot(gap(moving.y, moving.bottom(), o.y, o.bottom()));
        let (ox, oy) = o.middle();
        (d, (ox - mx).hypot(oy - my))
    };
    let near = others.iter().min_by(|a, b| far(a).partial_cmp(&far(b)).unwrap_or(std::cmp::Ordering::Equal))?;
    // along the edge: where it stood, where the two still share a part of it
    let along = |at: i32, len: i32, start: i32, size: i32| {
        if at < start + size && start < at + len {
            at
        } else {
            start
        }
    };
    let beyond = |o: &Rect| match side {
        Side::Left => (o.x - moving.w, along(moving.y, moving.h, near.y, near.h)),
        Side::Right => (o.right(), along(moving.y, moving.h, near.y, near.h)),
        Side::Above => (along(moving.x, moving.w, near.x, near.w), o.y - moving.h),
        Side::Below => (along(moving.x, moving.w, near.x, near.w), o.bottom()),
    };
    let mut at = beyond(near);
    for _ in 0..MOST {
        let Some(o) = others.iter().find(|o| moving.at(at).over(o)) else { break };
        at = beyond(o);
    }
    let free = !others.iter().any(|o| moving.at(at).over(o));
    let within = |v: i32| (v as i64).abs() <= REACH;
    (free && at != (moving.x, moving.y) && within(at.0) && within(at.1)).then_some(at)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const A: Rect = Rect::new(0, 0, 1200, 1920);
    const B: Rect = Rect::new(1200, 420, 2560, 1440);

    fn one(extra: Value) -> Value {
        let mut v = json!({"name": "DP-3", "text": "MB16FC", "x": 0, "y": 0, "w": 1200, "h": 1920, "on": true});
        v.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
        v
    }

    #[test]
    fn a_map_is_read_only_in_its_shape() {
        let m = read(&json!({"move": {"name": "display_position", "arguments": {}}, "screens": [
            one(json!({"main": true, "picture": "/srv/thumbs/a.png", "children": "spark-shell://display/rows/screen/DP-3"})),
            {"name": "eDP-1", "text": "built-in", "x": 0, "y": 0, "w": 0, "h": 0, "on": false, "main": true, "picture": "/srv/thumbs/b.png"}
        ]}))
        .unwrap();
        let (a, b) = (&m.screens[0], &m.screens[1]);
        assert_eq!((a.rect, a.main, a.picture.as_deref()), (A, true, Some("/srv/thumbs/a.png")));
        assert_eq!(a.children.as_deref(), Some("spark-shell://display/rows/screen/DP-3"));
        assert_eq!(
            (b.on, b.main, b.picture.is_none(), b.rect),
            (false, false, true, PLAIN),
            "one that is off has no place and no picture"
        );
        assert_eq!(m.step.as_ref().map(|c| c.name.as_str()), Some("display_position"));
        // each of these screens is left out: a number out of its range, a name no port has, a place that is missing
        for bad in [
            one(json!({"w": 0})),
            one(json!({"h": 32768})),
            one(json!({"x": 65536})),
            one(json!({"y": -65536})),
            one(json!({"x": 0.5})),
            one(json!({"x": "0"})),
            one(json!({"w": 9_223_372_036_854_775_807i64})),
            one(json!({"name": ""})),
            one(json!({"name": "DP 3"})),
            one(json!({"name": "DP-3\u{1b}"})),
            one(json!({"name": "x".repeat(81)})),
            one(json!({"on": "yes"})),
            json!({"name": "DP-3", "on": true}),
            json!(null),
            json!([]),
        ] {
            assert_eq!(read(&json!({"screens": [bad]})), None, "{bad}");
        }
        for none in [json!({}), json!({"screens": 3}), json!({"screens": []}), json!({"screens": {}}), json!(7)] {
            assert_eq!(read(&none), None, "{none}");
        }
        // words: scrubbed, and the port's name where they say nothing
        let text = |t: Value| read(&json!({"screens": [one(json!({ "text": t }))]})).unwrap().screens[0].text.clone();
        assert_eq!(text(json!("MB\u{1b}[2J16")), "MB[2J16");
        for plain in [json!(" "), json!("x".repeat(41)), json!(4)] {
            assert_eq!(text(plain), "DP-3");
        }
        // a picture only as a preview is: a whole path to a PNG, no step up; a step only as one is
        for p in ["thumbs/a.png", "/srv/../etc/a.png", "/srv/a.svg", "/srv/a\n.png"] {
            assert!(
                read(&json!({"screens": [one(json!({ "picture": p }))]})).unwrap().screens[0].picture.is_none(),
                "{p}"
            );
        }
        assert!(read(&json!({"screens": [one(json!({}))], "move": {"name": "Display Position"}}))
            .unwrap()
            .step
            .is_none());
        assert!(read(&json!({"screens": [one(json!({"children": "file:///etc"}))]})).unwrap().screens[0]
            .children
            .is_none());
        // sixteen at most, each name once
        let many: Vec<Value> = (0..40).map(|i| one(json!({"name": format!("DP-{}", i / 2)}))).collect();
        let m = read(&json!({ "screens": many })).unwrap();
        assert_eq!(m.screens.len(), MOST);
        assert_eq!(m.screens[15].name, "DP-15");
    }

    #[test]
    fn places_fit_their_box_to_scale_in_the_middle_and_touch_where_they_touch() {
        let f = Fit::new(&[A, B], (10.0, 20.0, 600.0, 160.0)).unwrap();
        // 3760 by 1920 in 600 by 160: the height rules
        assert!((f.scale - 160.0 / 1920.0).abs() < 1e-9);
        let (a, b) = (f.place(&A), f.place(&B));
        assert_eq!((a.1, a.3), (20.0, 160.0), "the whole height");
        assert_eq!(a.0 + a.2, b.0, "the edge they share is one edge");
        let left = a.0 - 10.0;
        let right = 610.0 - (b.0 + b.2);
        assert!((left - right).abs() <= 1.0, "in the middle: {left} {right}");
        assert_eq!((b.1, b.3), (55.0, 120.0));
        assert_eq!(Fit::new(&[], (0.0, 0.0, 10.0, 10.0)), None);
        assert_eq!(Fit::new(&[A], (0.0, 0.0, 0.0, 10.0)), None, "a box with no room");
        // the farthest a hostile map may say still fits
        let far = [Rect::new(-65535, -65535, 1, 1), Rect::new(65535, 65535, 32767, 32767)];
        let f = Fit::new(&far, (0.0, 0.0, 100.0, 100.0)).unwrap();
        assert!(f.place(&far[0]).2 >= 1.0 && f.place(&far[1]).0.is_finite());
    }

    #[test]
    fn a_screen_that_is_off_stands_past_the_rest_and_no_taller() {
        let m = read(&json!({"screens": [
            one(json!({})),
            {"name": "eDP-1", "on": false, "w": 3840, "h": 2160},
            {"name": "DP-9", "on": false}
        ]}))
        .unwrap();
        let p = m.places();
        assert_eq!(p[0], A);
        assert!(p[1].x > A.right() && p[1].bottom() == A.bottom() && p[1].h <= A.h, "{p:?}");
        assert!(p[2].x > p[1].right());
        assert!(!p[1].over(&p[2]));
        // the order of the keys: those that are on first; moving needs two that are on and a step
        assert_eq!(m.order().iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["DP-3", "eDP-1", "DP-9"]);
        assert!(!m.moves("DP-3"));
        // nothing on at all: they are drawn all the same
        let m = read(&json!({"screens": [{"name": "eDP-1", "on": false}]})).unwrap();
        assert_eq!(m.places(), [Rect::new(0, 0, 1920, 1080)]);
        assert_eq!(m.first().map(|s| s.name.as_str()), Some("eDP-1"));
    }

    #[test]
    fn a_small_move_lets_a_screen_go_where_it_stood() {
        let at = |want: (f64, f64)| landing(A, want, &[B], 100.0).unwrap();
        assert_eq!(at((20.0, 10.0)), (0, 0), "where it stood");
        assert_eq!(at((-10.0, -70.0)), (0, -60), "its foot lined up with the other's");
        assert_eq!(at((0.0, 190.0)), (0, 180), "its middle with the other's");
        assert_eq!(at((3700.0, 400.0)), (3760, 420), "its top, on the other side");
    }

    #[test]
    fn the_pull_of_a_line_is_as_far_as_asked() {
        let (m, o) = (Rect::new(0, 0, 1000, 1000), Rect::new(1000, 0, 1000, 1000));
        // dropped 60 low beside it: lined up with its top where the pull reaches, where it was let go where it does not
        assert_eq!(landing(m, (5.0, 60.0), &[o], 100.0), Some((0, 0)));
        assert_eq!(landing(m, (5.0, 160.0), &[o], 100.0), Some((0, 160)));
        // a corner: above it, the two left edges lined up
        assert_eq!(landing(m, (1040.0, -980.0), &[o], 100.0), Some((1000, -1000)));
        // dropped right on it: the nearest edge, never over it
        let at = landing(m, (1300.0, 40.0), &[o], 100.0).unwrap();
        assert!(!m.at(at).over(&o) && m.at(at).shared(&o) > 0, "{at:?}");
        // a corner alone is no edge: the pointer could not cross
        let at = landing(m, (0.0, -1000.0), &[o], 10.0).unwrap();
        assert!(m.at(at).shared(&o) >= 125, "{at:?}");
        assert_eq!(landing(m, (0.0, 0.0), &[], 100.0), None, "no other to land against");
        // a place far out of the layout's reach is never offered
        let edge = Rect::new(65535, 0, 100, 100);
        let at = landing(m, (90000.0, 0.0), &[edge], 10.0).unwrap();
        assert!(at.0 <= 65535, "{at:?}");
    }

    #[test]
    fn a_landing_among_several_is_over_none_of_them() {
        let m = Rect::new(0, 0, 800, 600);
        let others = [
            Rect::new(800, 0, 1920, 1080),
            Rect::new(2720, 0, 1080, 1920),
            Rect::new(800, 1080, 1920, 1080),
            Rect::new(-1280, 600, 1280, 720),
        ];
        for x in (-3000..5000).step_by(331) {
            for y in (-3000..4000).step_by(293) {
                let at = landing(m, (x as f64, y as f64), &others, 120.0).unwrap();
                let r = m.at(at);
                assert!(!others.iter().any(|o| r.over(o)), "({x}, {y}) lands at {at:?}, over another");
                assert!(others.iter().any(|o| r.shared(o) >= 75), "({x}, {y}) lands at {at:?}, beside none");
            }
        }
    }

    #[test]
    fn a_key_moves_a_screen_to_that_side_of_its_neighbor() {
        // it stood left of it: to its right it keeps its height, where the two still share the edge
        assert_eq!(beside(A, &[B], Side::Right), Some((3760, 0)));
        assert_eq!(beside(A, &[B], Side::Left), None, "it is there");
        // above it, where they shared nothing across: lined up with its start
        assert_eq!(beside(A, &[B], Side::Above), Some((1200, 420 - 1920)));
        assert_eq!(beside(A, &[B], Side::Below), Some((1200, 1860)));
        assert_eq!(beside(A, &[], Side::Left), None);
        // three in a row, the last one left: past the one that stands there, and on to the next free edge
        let (a, b, c) = (Rect::new(0, 0, 100, 100), Rect::new(100, 0, 100, 100), Rect::new(200, 0, 100, 100));
        assert_eq!(beside(c, &[a, b], Side::Left), Some((-100, 0)));
        assert_eq!(beside(a, &[b, c], Side::Right), Some((300, 0)));
        assert_eq!(beside(b, &[a, c], Side::Below), Some((0, 100)), "of the nearest, the first of two as near");
    }
}
