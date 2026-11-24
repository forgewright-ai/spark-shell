//! The card of a change on trial (v0.167), in the message's place over the keys: what changed, the seconds until it
//! goes back by itself, and the two keys that end it, each a place a click acts.

use super::{Geo, Metrics, Pen, Target};
use crate::app::App;
use crate::draw::Size;
use crate::scrub::cells;

const TALL: f64 = 64.0;

pub(super) fn height(m: &Metrics) -> f64 {
    m.px(TALL)
}

/// The words of the seconds left, as wide with one figure as with two: nothing moves as they run out.
pub(crate) fn seconds(left: u64) -> String {
    format!("goes back in {left:>2} s")
}

pub(super) fn draw(app: &App, pen: &mut Pen, g: &Geo) {
    let Some((said, left)) = app.trial_card() else { return };
    let m = *pen.m;
    let t = pen.t;
    let top = g.foot - height(&m);
    pen.fill(g.inset, top, g.w - 2.0 * g.inset, 1.0, t.accent);
    // from the card's end backward: keep, back, each its word and its key
    let (chip, base) = (m.px(8.0), top + m.px(38.0));
    let mut x = g.w - g.inset;
    for (word, key, keep) in [("back", "Esc", false), ("keep", "Enter", true)] {
        let kw = pen.width(key, Size::Small) + 2.0 * chip;
        pen.fill(x - kw, base - m.px(15.0), kw, m.px(21.0), t.lit);
        pen.text(x - kw + chip, base, key, Size::Small, t.ink, false);
        let ww = pen.width(word, Size::Small);
        pen.text(x - kw - chip - ww, base, word, Size::Small, t.accent, false);
        let w = kw + chip + ww;
        pen.hit(x - w - chip, top + m.px(8.0), w + chip, height(&m) - m.px(8.0), Target::Trial(keep));
        x -= w + m.px(24.0);
    }
    let from = m.px(super::TEXT);
    let said = pen.fit(said, Size::Main, x - from);
    pen.text(from, top + m.px(28.0), &said, Size::Main, t.ink, true);
    let words = seconds(left);
    let words = if cells(&words) as f64 * m.sw <= x - from {
        words
    } else {
        format!("{left:>2} s")
    };
    pen.text(from, top + m.px(50.0), &words, Size::Small, t.muted, false);
}
