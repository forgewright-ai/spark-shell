//! The display page's map (v0.167): the screens to scale in the middle of a row as tall as a few of the list's, each
//! with what it shows, a hairline around it and its name at its foot; the lit one framed in the accent, one that is
//! off an outline past the rest. A screen that is dragged follows the pointer, and an outline says where it lands.

use super::{Area, Metrics, Pen, Target, Tones};
use crate::app::App;
use crate::display::screens::{Fit, Map, Screen};
use crate::draw::{Rgb, Size, Step};
use crate::scrub::{cells, cut};

/// The map's row, in the sheets' pixels: a share of the list's height, between these two.
const SHARE: f64 = 0.32;
const LEAST: f64 = 184.0;
const MOST: f64 = 360.0;
/// The air around the screens in it: room at the sides and over them for one that is dragged there.
const SIDE: f64 = 64.0;
const AIR: f64 = 26.0;
/// The name's place at a screen's foot: from its left edge, from its bottom, and how tall the shade behind it is.
const IN: f64 = 10.0;
const FOOT: f64 = 10.0;
const SHADE: f64 = 44.0;
/// How near the place it lands a dragged screen stands there.
const NEAR: f64 = 14.0;

/// The height of the map's row in a list this tall.
pub(super) fn height(m: &Metrics, list: f64) -> f64 {
    (list * SHARE).clamp(m.px(LEAST), m.px(MOST)).round()
}

/// Where the map's row is drawn: its top, its height, its list's box, its place among the picks, whether it is lit.
pub(super) struct At {
    pub top: f64,
    pub h: f64,
    pub area: Area,
    pub pick: Option<usize>,
    pub on: bool,
}

type Boxed = (f64, f64, f64, f64);

/// A frame of lines as wide as `w`, inside a box.
fn frame(out: &mut Vec<Step>, (x, y, bw, bh): Boxed, w: f64, color: Rgb) {
    for (fx, fy, fw, fh) in [
        (x, y, bw, w),
        (x, y + bh - w, bw, w),
        (x, y + w, w, bh - 2.0 * w),
        (x + bw - w, y + w, w, bh - 2.0 * w),
    ] {
        if fw > 0.0 && fh > 0.0 {
            out.push(Step::Fill {
                x: fx,
                y: fy,
                w: fw,
                h: fh,
                color,
            });
        }
    }
}

/// The colors of a screen where it is drawn: the ground its name is read on, a plain surface, its frame.
struct Ink {
    ground: Rgb,
    surface: Rgb,
    line: Rgb,
    name: Rgb,
    word: Rgb,
}

/// A screen in its box: what it shows or a plain surface, its name and whether it is the main one, its frame.
fn screen(m: &Metrics, t: &Tones, s: &Screen, b: Boxed, lit: bool, ink: &Ink) -> Vec<Step> {
    let mut out = vec![];
    let (x, y, w, h) = b;
    let word = match (s.on, s.main) {
        (false, _) => "off",
        (true, true) => "main",
        _ => "",
    };
    // the name, and the word after it where both fit; else the word under the name, where two lines do
    let room = ((w - 2.0 * m.px(IN)) / m.sw).floor().max(0.0) as usize;
    let name = if cells(&s.text) <= room {
        s.text.clone()
    } else if room > 3 {
        format!("{}\u{2026}", cut(&s.text, room - 1))
    } else {
        String::new()
    };
    let one = cells(&name) + 2 + cells(word) <= room;
    let two = !word.is_empty() && !one && cells(word) <= room && h > 3.0 * m.sh;
    if s.on {
        out.push(Step::Fill {
            x,
            y,
            w,
            h,
            color: ink.surface,
        });
        if let Some(file) = &s.picture {
            out.push(Step::Cover {
                x,
                y,
                w,
                h,
                file: file.clone(),
            });
            let shade = (m.px(SHADE) + if two { m.sh } else { 0.0 }).min(h).round();
            out.push(Step::Shade {
                x,
                y: y + h - shade,
                w,
                h: shade,
                color: ink.ground,
            });
        }
    }
    let mut base = y + h - m.px(FOOT);
    let mut text = |x: f64, base: f64, words: &str, color: Rgb| {
        out.push(Step::Text {
            x: x.round(),
            y: (base - m.sup).round(),
            text: words.to_string(),
            size: Size::Small,
            color,
            bold: false,
        });
    };
    let left = x + m.px(IN);
    if two {
        text(left, base, word, ink.word);
        base -= m.sh;
    }
    if !name.is_empty() && h > m.sh + m.px(4.0) {
        text(left, base, &name, ink.name);
        if one && !word.is_empty() {
            text(left + (cells(&name) + 2) as f64 * m.sw, base, word, ink.word);
        }
    }
    if lit {
        frame(&mut out, b, 2.0, t.accent);
    } else {
        frame(&mut out, b, 1.0, ink.line);
    }
    out
}

pub(super) fn draw(app: &App, pen: &mut Pen, map: &Map, at: At) {
    let m = *pen.m;
    let t = pen.t;
    let a = at.area;
    let (side, air) = (m.px(SIDE).min((a.right - a.left) / 6.0), m.px(AIR));
    let room = (
        a.left + side,
        at.top + air,
        (a.right - a.left - 2.0 * side).max(1.0),
        (at.h - 2.0 * air).max(1.0),
    );
    let places = map.places();
    let Some(fit) = Fit::new(&places, room) else { return };
    let boxed = |r| {
        // a pixel of the row's ground between two that touch
        let (x, y, w, h) = fit.place(&r);
        (x + 1.0, y + 1.0, (w - 2.0).max(1.0), (h - 2.0).max(1.0))
    };
    let under = if at.on { t.lit } else { t.ground };
    let ink = |on: bool| Ink {
        ground: t.ground,
        surface: if at.on { t.ground } else { t.lit },
        line: t.muted,
        name: if on { t.ink } else { t.muted },
        word: t.muted,
    };
    let lit = app.map_lit(map);
    let drag = app.display.drag.as_ref().filter(|d| d.moved && d.landing.is_some() && at.pick == Some(d.row));
    for (s, r) in map.screens.iter().zip(&places) {
        let b = boxed(*r);
        if let Some(n) = at.pick {
            let (top, bottom) = (b.1.max(a.top), (b.1 + b.3).min(a.bottom));
            if bottom > top {
                pen.hit(b.0, top, b.2, bottom - top, Target::Screen(n, s.name.clone()));
            }
        }
        let is_lit = lit.as_deref() == Some(s.name.as_str());
        let Some(d) = drag.filter(|d| d.name == s.name) else {
            let steps = screen(&m, &t, s, b, is_lit, &ink(s.on));
            pen.steps.extend(steps);
            continue;
        };
        // the one held: where it stood, an outline; where it lands, one in the accent; itself under the pointer, all
        // of it over the rows around the map
        let mut held = vec![];
        frame(&mut pen.steps, b, 1.0, t.muted);
        let Some((lx, ly)) = d.landing else { continue };
        let land = boxed(crate::display::screens::Rect { x: lx, y: ly, ..s.rect });
        let free = (b.0 + d.by.0.round(), b.1 + d.by.1.round(), b.2, b.3);
        // near where it lands it stands there: let go now, nothing moves
        if (free.0 - land.0).hypot(free.1 - land.1) <= m.px(NEAR) {
            held.extend(screen(&m, &t, s, land, true, &ink(true)));
        } else {
            held.push(Step::Fill {
                x: land.0,
                y: land.1,
                w: land.2,
                h: land.3,
                color: under,
            });
            frame(&mut held, land, 2.0, t.accent);
            held.extend(screen(&m, &t, s, free, false, &ink(true)));
        }
        pen.over.extend(held);
    }
    pen.map = Some(fit);
}
