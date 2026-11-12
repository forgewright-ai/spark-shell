//! The buttons on a window's title band, pure: where the bands are in sway's tree, the cells the pointer
//! takes, and the start of a title that draws them, by a window's focus and the pointer. sway draws them.

use crate::pad::Rect;
use crate::tree::{kids, num, rect_of};
use serde_json::Value;

/// A window's title band in sight, where sway draws the buttons and the pad takes the pointer: its rect in
/// its screen's own pixels, the window's whole rect for what lies over it, its app and whether it has the focus.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Band {
    pub id: i64,
    pub output: String,
    pub rect: Rect,
    pub whole: Rect,
    pub app: String,
    pub focused: bool,
}

/// The buttons at the left end of a band, in their order: close, minimize, fill the screen or put back.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Glyph {
    Close,
    Min,
    Fill,
}

/// The buttons' glyphs as pango character references, so every command and file stays ASCII: an X, a
/// triangle pointing down, a square. spark-shell's template writes the same three (BAND_GLYPHS).
pub const GLYPH_REFS: [&str; 3] = ["&#x2715;", "&#x25BD;", "&#x25A1;"];
/// The same three as sway draws them, a space at each side of each: nine characters, to measure one by.
pub const GLYPHS: &str = " \u{2715}  \u{25bd}  \u{25a1} ";
/// Where a title starts inside its band: the template's titlebar_padding.
pub const TITLE_PAD: i32 = 12;

/// The start of a title, sway's title_format: the three buttons, each three characters wide. On the focused
/// window they wear the title's own color, on the others each its control color. The one under the pointer
/// lights on any window: a chip in its control color, its glyph in the ground's. `colors` are close,
/// minimize and fill, as rrggbb.
pub fn buttons(focused: bool, hover: Option<Glyph>, colors: &[String; 3], ground: &str) -> String {
    let mut out = String::new();
    for (i, g) in [Glyph::Close, Glyph::Min, Glyph::Fill].into_iter().enumerate() {
        let (r, c) = (GLYPH_REFS[i], &colors[i]);
        out += &match (hover == Some(g), focused) {
            (true, _) => format!("<span background='#{c}' foreground='#{ground}'> {r} </span>"),
            (false, true) => format!(" {r} "),
            (false, false) => format!(" <span foreground='#{c}'>{r}</span> "),
        };
    }
    out
}

/// A band's three button cells for the pointer, `cell` the width of one character of the title: close,
/// minimize, fill, three characters each from the title's start, as tall as the band.
pub fn glyph_cells(band: Rect, cell: f64) -> [Rect; 3] {
    let at = |i: f64| {
        let x = band.x as f64 + TITLE_PAD as f64 + 3.0 * i * cell;
        Rect::new(x.round() as i32, band.y, (3.0 * cell).round() as i32, band.h)
    };
    [at(0.0), at(1.0), at(2.0)]
}

/// The button a point is on in a band.
pub fn glyph_at(band: Rect, cell: f64, x: f64, y: f64) -> Option<Glyph> {
    let [close, min, fill] = glyph_cells(band, cell);
    if close.has(x, y) {
        Some(Glyph::Close)
    } else if min.has(x, y) {
        Some(Glyph::Min)
    } else if fill.has(x, y) {
        Some(Glyph::Fill)
    } else {
        None
    }
}

fn meets(a: Rect, b: Rect) -> bool {
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

/// The title bands on each screen's current workspace, the tiled windows first and the floating ones in
/// their stacking order: each view with a title bar, its band placed by its parent's rect as sway gives
/// it, in the screen's own pixels. A workspace with a view in full screen has none, and a band whose
/// glyphs lie under a window above it is left out. `cell` is the width of one character of the title.
pub fn bands(tree: &Value, cell: f64) -> Vec<Band> {
    struct Seen {
        band: Rect,
        whole: Rect,
        id: i64,
        app: String,
        focused: bool,
        full: bool,
    }
    fn walk(n: &Value, at: Rect, out: &mut Vec<Seen>) {
        let r = rect_of(&n["rect"]);
        if kids(n).next().is_some() {
            for k in kids(n) {
                walk(k, r, out);
            }
            return;
        }
        if n["type"] != "con" && n["type"] != "floating_con" {
            return;
        }
        let d = rect_of(&n["deco_rect"]);
        let band = Rect::new(at.x + d.x, at.y + d.y, d.w, d.h);
        let (x0, y0) = (r.x.min(band.x), r.y.min(band.y));
        let whole = Rect::new(x0, y0, (r.x + r.w).max(band.x + band.w) - x0, (r.y + r.h).max(band.y + band.h) - y0);
        out.push(Seen {
            band,
            whole,
            id: n["id"].as_i64().unwrap_or(0),
            app: n["app_id"].as_str().unwrap_or("").to_string(),
            focused: n["focused"] == true,
            full: num(&n["fullscreen_mode"]) != 0,
        });
    }
    let mut out: Vec<Band> = vec![];
    for o in tree["nodes"].as_array().into_iter().flatten() {
        let name = o["name"].as_str().unwrap_or("");
        if o["type"] != "output" || name == "__i3" {
            continue;
        }
        let orect = rect_of(&o["rect"]);
        let current = &o["current_workspace"];
        let Some(ws) = o["nodes"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|w| w["type"] == "workspace" && &w["name"] == current)
        else {
            continue;
        };
        let mut seen = vec![];
        walk(ws, rect_of(&ws["rect"]), &mut seen);
        if seen.iter().any(|s| s.full) {
            continue;
        }
        let shift = |r: Rect| Rect::new(r.x - orect.x, r.y - orect.y, r.w, r.h);
        for s in seen.into_iter().filter(|s| s.band.h > 0 && s.band.w > 0) {
            out.push(Band {
                id: s.id,
                output: name.to_string(),
                rect: shift(s.band),
                whole: shift(s.whole),
                app: s.app,
                focused: s.focused,
            });
        }
    }
    let keep: Vec<bool> = (0..out.len())
        .map(|i| {
            let [a, _, b] = glyph_cells(out[i].rect, cell);
            let zone = Rect::new(a.x, a.y, b.x + b.w - a.x, a.h);
            !out[i + 1..].iter().any(|o| o.output == out[i].output && meets(zone, o.whole))
        })
        .collect();
    out.into_iter().zip(keep).filter_map(|(b, k)| k.then_some(b)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a_tree(over: bool) -> Value {
        // a screen of 1600 by 900 with the bar's 30 px, a tiled window with the focus and a floating one,
        // placed over the tiled one's glyphs when `over`
        let fx = if over { 20 } else { 400 };
        serde_json::json!({
            "type": "root", "focus": [2], "nodes": [
                {"type": "output", "name": "__i3", "id": 1, "nodes": [{"type": "workspace", "name": "__i3_scratch", "id": 9, "floating_nodes": [{"type": "floating_con", "id": 70, "pid": 7, "marks": ["_spark-shell.min.tiled.70"], "nodes": [], "floating_nodes": []}]}]},
                {"type": "output", "name": "DP-1", "id": 2, "current_workspace": "1", "rect": {"x": 0, "y": 0, "width": 1600, "height": 900}, "focus": [3],
                 "nodes": [{"type": "workspace", "name": "1", "id": 3, "rect": {"x": 0, "y": 30, "width": 1600, "height": 870}, "focus": [5, 6],
                            "nodes": [{"type": "con", "id": 5, "pid": 1, "focused": true, "fullscreen_mode": 0, "rect": {"x": 8, "y": 61, "width": 784, "height": 831}, "deco_rect": {"x": 8, "y": 8, "width": 784, "height": 23}, "nodes": [], "floating_nodes": []}],
                            "floating_nodes": [{"type": "floating_con", "id": 6, "pid": 2, "focused": false, "fullscreen_mode": 0, "rect": {"x": fx, "y": 50, "width": 400, "height": 300}, "deco_rect": {"x": fx, "y": -3, "width": 400, "height": 23}, "nodes": [], "floating_nodes": []}]}]}]
        })
    }

    #[test]
    fn the_bands_sit_where_sway_puts_the_titles() {
        let b = bands(&a_tree(false), 10.0);
        assert_eq!(b.len(), 2);
        assert_eq!(b[0].id, 5);
        assert!(b[0].focused && !b[1].focused);
        assert_eq!(b[0].rect, Rect::new(8, 38, 784, 23));
        assert_eq!(b[0].whole, Rect::new(8, 38, 784, 854));
        assert_eq!(b[1].rect, Rect::new(400, 27, 400, 23));
        // the title starts 12 px in: close, minimize, fill, three characters each
        let [close, min, fill] = glyph_cells(b[0].rect, 10.0);
        assert_eq!(close, Rect::new(20, 38, 30, 23));
        assert_eq!(min, Rect::new(50, 38, 30, 23));
        assert_eq!(fill, Rect::new(80, 38, 30, 23));
        assert_eq!(glyph_at(b[0].rect, 10.0, 35.0, 50.0), Some(Glyph::Close));
        assert_eq!(glyph_at(b[0].rect, 10.0, 65.0, 50.0), Some(Glyph::Min));
        assert_eq!(glyph_at(b[0].rect, 10.0, 95.0, 50.0), Some(Glyph::Fill));
        assert_eq!(glyph_at(b[0].rect, 10.0, 120.0, 50.0), None);
        assert_eq!(GLYPHS.chars().count(), 9);
    }

    #[test]
    fn the_buttons_wear_the_title_color_with_the_focus_and_their_own_without() {
        let c = ["bf616a".to_string(), "ebcb8b".to_string(), "a3be8c".to_string()];
        assert_eq!(buttons(true, None, &c, "2e3440"), " &#x2715;  &#x25BD;  &#x25A1; ");
        assert_eq!(
            buttons(true, Some(Glyph::Close), &c, "2e3440"),
            "<span background='#bf616a' foreground='#2e3440'> &#x2715; </span> &#x25BD;  &#x25A1; "
        );
        assert_eq!(
            buttons(false, None, &c, "2e3440"),
            " <span foreground='#bf616a'>&#x2715;</span>  <span foreground='#ebcb8b'>&#x25BD;</span>  <span foreground='#a3be8c'>&#x25A1;</span> "
        );
        assert_eq!(
            buttons(false, Some(Glyph::Min), &c, "2e3440"),
            " <span foreground='#bf616a'>&#x2715;</span> <span background='#ebcb8b' foreground='#2e3440'> &#x25BD; </span> <span foreground='#a3be8c'>&#x25A1;</span> "
        );
    }

    #[test]
    fn a_band_under_a_floating_window_has_no_glyphs() {
        // the floating window lies over the tiled band's left end, where its glyphs are
        let b = bands(&a_tree(true), 10.0);
        assert_eq!(b.iter().map(|b| b.id).collect::<Vec<_>>(), vec![6]);
    }
}
