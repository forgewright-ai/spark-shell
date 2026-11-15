//! The buttons on a window's title band, pure: where the bands are in sway's tree, the cells the pointer
//! takes, and the start of a title that draws them, by a window's focus and the pointer. sway draws them.

use crate::pad::Rect;
use crate::tree::{kids, num, rect_of};
use serde_json::Value;

/// A window's title band in sight, where sway draws the buttons and the pad takes the pointer: its rect in
/// its screen's own pixels, the window's whole rect for what lies over it, its app, the name the window
/// gives itself, whether it has the focus and whether sway marks it urgent.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Band {
    pub id: i64,
    pub output: String,
    pub rect: Rect,
    pub whole: Rect,
    pub app: String,
    pub name: String,
    pub focused: bool,
    pub urgent: bool,
}

/// The colors sway paints a band in, which say what its buttons wear: an urgent window's come before the
/// focus's, as sway picks them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Focus,
    Urgent,
    Plain,
}

impl Band {
    pub fn kind(&self) -> Kind {
        if self.urgent {
            Kind::Urgent
        } else if self.focused {
            Kind::Focus
        } else {
            Kind::Plain
        }
    }
}

/// The buttons at the left end of a band, in their order: close, minimize, fill the screen or put back,
/// and on a terminal the mic.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Glyph {
    Close,
    Min,
    Fill,
    Mic,
}

/// The buttons' glyphs as pango character references, so every command and file stays ASCII: an X, a
/// triangle pointing down, a square. spark-shell's template writes the same three (BAND_GLYPHS).
pub const GLYPH_REFS: [&str; 3] = ["&#x2715;", "&#x25BD;", "&#x25A1;"];
/// The same three as sway draws them, a space at each side of each: nine characters, to measure one by.
pub const GLYPHS: &str = " \u{2715}  \u{25bd}  \u{25a1} ";
/// Where a title starts inside its band: the template's titlebar_padding.
pub const TITLE_PAD: i32 = 12;
/// The mic at rest, a ring, and listening, a dot; the bars, eight heights.
pub const MIC_REFS: [&str; 2] = ["&#x25CB;", "&#x25CF;"];
pub const BAR_REFS: [&str; 8] = ["&#x2581;", "&#x2582;", "&#x2583;", "&#x2584;", "&#x2585;", "&#x2586;", "&#x2587;", "&#x2588;"];
/// The cells the meter keeps at the right end of every band, whatever the window's name is.
pub const METER: usize = 8;
/// The blank kept between a name and the meter, so a name cut short never touches it.
pub const APART: usize = 1;
/// Where a name was cut.
pub const ELLIPSIS: &str = "&#x2026;";
/// The mic on a band: listening or at rest, and the last levels, the newest last, one for each meter cell.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Mic {
    pub listening: bool,
    pub bars: [u8; METER],
}

/// The mic from spark-shell's voice state (`listening 0|1`, `level N`) and the mic before: the bars slide.
pub fn mic_state(text: &str, before: &Mic) -> Mic {
    let (mut listening, mut level) = (false, 0u8);
    for line in text.lines() {
        if let Some(v) = line.strip_prefix("listening ") {
            listening = v.trim() == "1";
        }
        if let Some(v) = line.strip_prefix("level ") {
            level = v.trim().parse().unwrap_or(0);
        }
    }
    let mut bars = [0u8; METER];
    if listening {
        bars[..METER - 1].copy_from_slice(&before.bars[1..]);
        bars[METER - 1] = level.min(7);
    }
    Mic { listening, bars }
}

/// What the buttons wear, as spark-shell hands it: close, minimize and fill's colors, the glyph's on close's
/// chip, the chip's tone on the focused window's band, on an urgent one's and on the others, all rrggbb, and
/// pango's size for the half space at a glyph's sides (none: whole spaces).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Style {
    pub colors: [String; 3],
    pub close_ink: String,
    pub band_lit: String,
    pub urgent_lit: String,
    pub lit: String,
    pub half: Option<String>,
}

impl Style {
    /// The style from spark-shell's environment, `get` a variable's value: WINPAD_CLOSE_INK falls back to
    /// WINPAD_GROUND, WINPAD_BAND_LIT and WINPAD_URGENT_LIT to WINPAD_LIT.
    pub fn read(get: impl Fn(&str) -> Option<String>) -> Style {
        let color = |k: &str, d: &str| hex(get(k).as_deref()).unwrap_or_else(|| d.into());
        let lit = color("WINPAD_LIT", "dcdcdd");
        let ground = color("WINPAD_GROUND", "fafafa");
        Style {
            colors: [color("WINPAD_CLOSE", "e45649"), color("WINPAD_MIN", "c18401"), color("WINPAD_FILL", "50a14f")],
            close_ink: color("WINPAD_CLOSE_INK", &ground),
            band_lit: color("WINPAD_BAND_LIT", &lit),
            urgent_lit: color("WINPAD_URGENT_LIT", &lit),
            lit,
            half: half_size(get("WINPAD_HALF").as_deref()),
        }
    }
}

/// A color as pango's markup takes one, its six digits in lower case. Anything else stays out of the
/// title, as a half space's size does.
fn hex(v: Option<&str>) -> Option<String> {
    let v = v?.trim().trim_start_matches('#');
    (v.len() == 6 && v.bytes().all(|b| b.is_ascii_hexdigit())).then(|| v.to_lowercase())
}

/// A size for the half space as pango's markup takes one, in 1024ths of a point: digits alone, more than
/// none. Anything else stays out of the title: sway shows markup pango refuses as text.
pub fn half_size(v: Option<&str>) -> Option<String> {
    let v = v?.trim();
    let whole = !v.is_empty() && v.len() <= 7 && v.bytes().all(|b| b.is_ascii_digit()) && v.bytes().any(|b| b != b'0');
    whole.then(|| v.to_string())
}

/// The start of a title, sway's title_format: the three buttons and, where something can hear, the mic, a
/// space at each side of each. On the focused window's band and on an urgent one's they wear the title's
/// own color; on the others close, minimize and fill wear each its control color, and the mic the title's.
/// The one under the pointer gets a chip: close's in its control color with the glyph in close's ink, the
/// others' in the band's lit tone with the glyph as it was. An urgent band is close's own color, so every
/// chip there, close's too, is the urgent lit tone and its glyph keeps the title's color. With a half space
/// the chip is the glyph and half a cell at each side, the other halves outside it; a button is as wide at
/// rest and under the pointer, three cells: sway places a title's glyphs unrounded, so two half spaces are
/// one cell at any size.
pub fn buttons(kind: Kind, hover: Option<Glyph>, style: &Style, mic: Option<&Mic>) -> String {
    let half = style.half.as_ref().map(|n| format!("<span size='{n}'> </span>"));
    let (outer, inner) = half.as_deref().map_or(("", " "), |h| (h, h));
    let plain = kind == Kind::Plain;
    let mut all: Vec<(Glyph, &str, Option<&str>)> = [Glyph::Close, Glyph::Min, Glyph::Fill]
        .into_iter()
        .enumerate()
        .map(|(i, g)| (g, GLYPH_REFS[i], plain.then_some(style.colors[i].as_str())))
        .collect();
    if let Some(m) = mic {
        all.push((Glyph::Mic, MIC_REFS[usize::from(m.listening)], None));
    }
    let ink = |c: Option<&str>| c.map(|c| format!(" foreground='#{c}'")).unwrap_or_default();
    all.into_iter()
        .map(|(g, r, own)| {
            if hover == Some(g) {
                let (chip, on) = match (kind, g) {
                    (Kind::Urgent, _) => (&style.urgent_lit, None),
                    (_, Glyph::Close) => (&style.colors[0], Some(style.close_ink.as_str())),
                    (Kind::Focus, _) => (&style.band_lit, own),
                    (Kind::Plain, _) => (&style.lit, own),
                };
                format!("{outer}<span background='#{chip}'{}>{inner}{r}{inner}</span>{outer}", ink(on))
            } else if let Some(c) = own {
                format!("{outer}{inner}<span foreground='#{c}'>{r}</span>{inner}{outer}")
            } else {
                format!("{outer}{inner}{r}{inner}{outer}")
            }
        })
        .collect()
}

/// The meter at the right end of a band: the levels as blocks, the newest last, in the band's own text
/// color. It is empty at rest, and its cells are kept for it either way, so nothing moves when it starts.
pub fn meter(mic: Option<&Mic>) -> String {
    match mic {
        Some(m) if m.listening => m.bars.iter().map(|&l| BAR_REFS[usize::from(l.min(7))]).collect(),
        _ => String::new(),
    }
}

/// The cells a title takes on screen: a tag takes none, a character reference or an escaped character one,
/// and a character in a span with a size of its own half of one: the half spaces at a button's sides.
pub fn cells(s: &str) -> usize {
    let (mut halves, mut small, mut it) = (0usize, false, s.chars());
    while let Some(c) = it.next() {
        match c {
            '<' => {
                let tag: String = it.by_ref().take_while(|&d| d != '>').collect();
                small = tag.starts_with("span size=");
                continue;
            }
            '&' => {
                it.by_ref().find(|&d| d == ';');
            }
            '\\' => {
                it.next();
            }
            _ => {}
        }
        halves += if small { 1 } else { 2 };
    }
    halves.div_ceil(2)
}

/// A name as it is safe to hand sway: the control characters out, the markup's characters as references,
/// and the backslash doubled for sway's own parser, so no window's name can carry a command.
fn safe(name: &str) -> String {
    name.chars()
        .filter(|c| !c.is_control())
        .map(|c| match c {
            '&' => "&amp;".to_string(),
            '<' => "&lt;".to_string(),
            '>' => "&gt;".to_string(),
            '"' => "&quot;".to_string(),
            '\\' => "\\\\".to_string(),
            c => c.to_string(),
        })
        .collect()
}

/// A name cut to the cells it has, the cut marked with an ellipsis.
fn clip(name: &str, room: usize) -> String {
    let kept: String = name.chars().filter(|c| !c.is_control()).collect();
    if kept.chars().count() <= room {
        return safe(&kept);
    }
    if room == 0 {
        return String::new();
    }
    let cut: String = kept.chars().take(room - 1).collect();
    format!("{}{ELLIPSIS}", safe(cut.trim_end()))
}

/// The cells a band has for its title: its width less the padding at each side, in characters.
pub fn room(band: Rect, cell: f64) -> usize {
    (f64::from(band.w - 2 * TITLE_PAD) / cell).max(0.0) as usize
}

/// The whole word to sway for one band, sway's title_format: the buttons, what the look puts around the
/// window's name, the name cut to the cells left over, and the meter's cells at the right end. The name is
/// padded out to its own room, so the meter keeps the same cells and nothing on the band moves. `room` is
/// the cells the band holds.
pub fn title(room: usize, buttons: &str, around: &str, name: &str, meter: &str) -> String {
    let (head, tail) = around.split_once("%title").unwrap_or((around, ""));
    let taken = cells(buttons) + cells(head) + cells(tail) + METER + APART;
    let line = format!("{buttons}{head}{}{tail}", clip(name, room.saturating_sub(taken)));
    let pad = room.saturating_sub(METER).saturating_sub(cells(&line));
    format!("{line}{:pad$}{meter}", "")
}

/// A band's button cells for the pointer, `cell` the width of one character of the title: close,
/// minimize, fill and the mic, three characters each from the title's start, as tall as the band.
pub fn glyph_cells(band: Rect, cell: f64) -> [Rect; 4] {
    let at = |i: f64| {
        let x = band.x as f64 + TITLE_PAD as f64 + 3.0 * i * cell;
        Rect::new(x.round() as i32, band.y, (3.0 * cell).round() as i32, band.h)
    };
    [at(0.0), at(1.0), at(2.0), at(3.0)]
}

/// The button a point is on in a band; the mic's cell counts on a terminal's band alone.
pub fn glyph_at(band: Rect, cell: f64, x: f64, y: f64, with_mic: bool) -> Option<Glyph> {
    let [close, min, fill, mic] = glyph_cells(band, cell);
    if close.has(x, y) {
        Some(Glyph::Close)
    } else if min.has(x, y) {
        Some(Glyph::Min)
    } else if fill.has(x, y) {
        Some(Glyph::Fill)
    } else if with_mic && mic.has(x, y) {
        Some(Glyph::Mic)
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
        name: String,
        focused: bool,
        urgent: bool,
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
            name: n["name"].as_str().unwrap_or("").to_string(),
            focused: n["focused"] == true,
            urgent: n["urgent"] == true,
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
                name: s.name,
                focused: s.focused,
                urgent: s.urgent,
            });
        }
    }
    let keep: Vec<bool> = (0..out.len())
        .map(|i| {
            let [a, _, b, _] = glyph_cells(out[i].rect, cell);
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
                            "nodes": [{"type": "con", "id": 5, "pid": 1, "name": "a terminal", "focused": true, "fullscreen_mode": 0, "rect": {"x": 8, "y": 61, "width": 784, "height": 831}, "deco_rect": {"x": 8, "y": 8, "width": 784, "height": 23}, "nodes": [], "floating_nodes": []}],
                            "floating_nodes": [{"type": "floating_con", "id": 6, "pid": 2, "focused": false, "fullscreen_mode": 0, "rect": {"x": fx, "y": 50, "width": 400, "height": 300}, "deco_rect": {"x": fx, "y": -3, "width": 400, "height": 23}, "nodes": [], "floating_nodes": []}]}]}]
        })
    }

    #[test]
    fn the_bands_sit_where_sway_puts_the_titles() {
        let b = bands(&a_tree(false), 10.0);
        assert_eq!(b.len(), 2);
        assert_eq!(b[0].id, 5);
        assert_eq!(b[0].name, "a terminal");
        assert!(b[0].focused && !b[1].focused);
        assert_eq!(b[0].rect, Rect::new(8, 38, 784, 23));
        assert_eq!(b[0].whole, Rect::new(8, 38, 784, 854));
        assert_eq!(b[1].rect, Rect::new(400, 27, 400, 23));
        // the title starts 12 px in: close, minimize, fill, three characters each
        let [close, min, fill, mic] = glyph_cells(b[0].rect, 10.0);
        assert_eq!(close, Rect::new(20, 38, 30, 23));
        assert_eq!(min, Rect::new(50, 38, 30, 23));
        assert_eq!(fill, Rect::new(80, 38, 30, 23));
        assert_eq!(mic, Rect::new(110, 38, 30, 23));
        assert_eq!(glyph_at(b[0].rect, 10.0, 35.0, 50.0, false), Some(Glyph::Close));
        assert_eq!(glyph_at(b[0].rect, 10.0, 65.0, 50.0, false), Some(Glyph::Min));
        assert_eq!(glyph_at(b[0].rect, 10.0, 95.0, 50.0, false), Some(Glyph::Fill));
        assert_eq!(glyph_at(b[0].rect, 10.0, 120.0, 50.0, false), None);
        assert_eq!(glyph_at(b[0].rect, 10.0, 120.0, 50.0, true), Some(Glyph::Mic));
        assert_eq!(glyph_at(b[0].rect, 10.0, 150.0, 50.0, true), None);
        assert_eq!(GLYPHS.chars().count(), 9);
    }

    fn a_style(half: Option<&str>) -> Style {
        Style {
            colors: ["bf616a".into(), "ebcb8b".into(), "a3be8c".into()],
            close_ink: "eceff4".into(),
            band_lit: "9db0cc".into(),
            urgent_lit: "d08770".into(),
            lit: "4c566a".into(),
            half: half.map(Into::into),
        }
    }

    #[test]
    fn the_buttons_wear_the_title_color_with_the_focus_and_their_own_without() {
        let s = a_style(None);
        assert_eq!(buttons(Kind::Focus, None, &s, None), " &#x2715;  &#x25BD;  &#x25A1; ");
        assert_eq!(
            buttons(Kind::Plain, None, &s, None),
            " <span foreground='#bf616a'>&#x2715;</span>  <span foreground='#ebcb8b'>&#x25BD;</span>  <span foreground='#a3be8c'>&#x25A1;</span> "
        );
    }

    #[test]
    fn under_the_pointer_close_is_a_chip_of_its_own_color_and_the_others_of_the_lit_tone() {
        let s = a_style(None);
        // close: its control color, the glyph in close's ink, with the focus and without
        assert_eq!(
            buttons(Kind::Focus, Some(Glyph::Close), &s, None),
            "<span background='#bf616a' foreground='#eceff4'> &#x2715; </span> &#x25BD;  &#x25A1; "
        );
        assert!(buttons(Kind::Plain, Some(Glyph::Close), &s, None)
            .starts_with("<span background='#bf616a' foreground='#eceff4'> &#x2715; </span> <span foreground='#ebcb8b'>"));
        // the others keep their color at rest: the title's on the focused band's lit tone, their own on the others'
        assert_eq!(
            buttons(Kind::Focus, Some(Glyph::Min), &s, None),
            " &#x2715; <span background='#9db0cc'> &#x25BD; </span> &#x25A1; "
        );
        assert_eq!(
            buttons(Kind::Focus, Some(Glyph::Fill), &s, None),
            " &#x2715;  &#x25BD; <span background='#9db0cc'> &#x25A1; </span>"
        );
        assert_eq!(
            buttons(Kind::Plain, Some(Glyph::Min), &s, None),
            " <span foreground='#bf616a'>&#x2715;</span> <span background='#4c566a' foreground='#ebcb8b'> &#x25BD; </span> <span foreground='#a3be8c'>&#x25A1;</span> "
        );
    }

    #[test]
    fn on_an_urgent_band_the_buttons_wear_the_title_color_and_every_chip_the_urgent_tone() {
        let s = a_style(None);
        let rest = Mic::default();
        // at rest as on the band with the focus: close's own color is the urgent band's
        assert_eq!(buttons(Kind::Urgent, None, &s, None), " &#x2715;  &#x25BD;  &#x25A1; ");
        assert_eq!(buttons(Kind::Urgent, None, &s, Some(&rest)), buttons(Kind::Focus, None, &s, Some(&rest)));
        // under the pointer the chip is the urgent tone, close's too, and the glyph keeps the title's color
        assert_eq!(
            buttons(Kind::Urgent, Some(Glyph::Close), &s, None),
            "<span background='#d08770'> &#x2715; </span> &#x25BD;  &#x25A1; "
        );
        assert_eq!(
            buttons(Kind::Urgent, Some(Glyph::Min), &s, None),
            " &#x2715; <span background='#d08770'> &#x25BD; </span> &#x25A1; "
        );
        assert_eq!(
            buttons(Kind::Urgent, Some(Glyph::Fill), &s, None),
            " &#x2715;  &#x25BD; <span background='#d08770'> &#x25A1; </span>"
        );
        assert_eq!(
            buttons(Kind::Urgent, Some(Glyph::Mic), &s, Some(&rest)),
            " &#x2715;  &#x25BD;  &#x25A1; <span background='#d08770'> &#x25CB; </span>"
        );
        for hover in [None, Some(Glyph::Close), Some(Glyph::Min), Some(Glyph::Fill), Some(Glyph::Mic)] {
            let m = buttons(Kind::Urgent, hover, &s, Some(&rest));
            assert!(!m.contains("foreground") && !m.contains("bf616a"), "{m}");
            assert_eq!(cells(&m), 12);
        }
    }

    #[test]
    fn a_band_is_urgent_before_it_is_the_focus() {
        // the tiled window has the focus, the floating one neither; sway marks each urgent in turn
        let mut tree = a_tree(false);
        let kinds = |t: &Value| bands(t, 10.0).iter().map(Band::kind).collect::<Vec<_>>();
        assert_eq!(kinds(&tree), [Kind::Focus, Kind::Plain]);
        tree["nodes"][1]["nodes"][0]["floating_nodes"][0]["urgent"] = true.into();
        assert_eq!(kinds(&tree), [Kind::Focus, Kind::Urgent]);
        // sway paints a window with the focus in the urgent colors until its urgency ends
        tree["nodes"][1]["nodes"][0]["nodes"][0]["urgent"] = true.into();
        assert_eq!(kinds(&tree), [Kind::Urgent, Kind::Urgent]);
    }

    #[test]
    fn the_style_is_read_with_a_fallback_for_each_color() {
        fn read(vars: &[(&str, &str)]) -> Style {
            Style::read(|k| vars.iter().find(|v| v.0 == k).map(|v| v.1.to_string()))
        }
        // none handed: the ground on close's chip, the lit tone on an urgent band and on the focused one
        let s = read(&[("WINPAD_CLOSE", "#BF616A"), ("WINPAD_GROUND", "2e3440"), ("WINPAD_LIT", " 4c566a ")]);
        assert_eq!(s.colors[0], "bf616a");
        assert_eq!([&s.close_ink, &s.band_lit, &s.urgent_lit, &s.lit], ["2e3440", "4c566a", "4c566a", "4c566a"]);
        let s = read(&[
            ("WINPAD_GROUND", "2e3440"),
            ("WINPAD_LIT", "4c566a"),
            ("WINPAD_CLOSE_INK", "eceff4"),
            ("WINPAD_BAND_LIT", "9db0cc"),
            ("WINPAD_URGENT_LIT", "d08770"),
        ]);
        assert_eq!([&s.close_ink, &s.band_lit, &s.urgent_lit, &s.lit], ["eceff4", "9db0cc", "d08770", "4c566a"]);
        // what is no color stays out of the title, and its fallback stands
        let s = read(&[
            ("WINPAD_GROUND", "2e3440"),
            ("WINPAD_CLOSE_INK", "fff' size='99"),
            ("WINPAD_URGENT_LIT", "d0877"),
        ]);
        assert_eq!([&s.close_ink, &s.urgent_lit], ["2e3440", "dcdcdd"]);
        assert_eq!(read(&[]).colors, ["e45649", "c18401", "50a14f"]);
        assert_eq!(read(&[("WINPAD_HALF", "6144")]).half, Some("6144".into()));
    }

    #[test]
    fn the_mic_wears_the_title_color_and_takes_the_same_cells_at_rest_and_listening() {
        let s = a_style(None);
        let rest = Mic::default();
        assert_eq!(buttons(Kind::Focus, None, &s, Some(&rest)), " &#x2715;  &#x25BD;  &#x25A1;  &#x25CB; ");
        assert!(buttons(Kind::Plain, None, &s, Some(&rest)).ends_with(" <span foreground='#a3be8c'>&#x25A1;</span>  &#x25CB; "));
        let live = Mic {
            listening: true,
            bars: [0, 2, 5, 7, 3, 1, 0, 6],
        };
        assert_eq!(buttons(Kind::Focus, None, &s, Some(&live)), " &#x2715;  &#x25BD;  &#x25A1;  &#x25CF; ");
        // under the pointer: the band's lit tone, never close's red
        assert_eq!(
            buttons(Kind::Focus, Some(Glyph::Mic), &s, Some(&live)),
            " &#x2715;  &#x25BD;  &#x25A1; <span background='#9db0cc'> &#x25CF; </span>"
        );
        assert!(buttons(Kind::Plain, Some(Glyph::Mic), &s, Some(&rest)).ends_with("<span background='#4c566a'> &#x25CB; </span>"));
        assert_eq!(cells(&buttons(Kind::Focus, None, &s, Some(&rest))), 12);
        assert_eq!(cells(&buttons(Kind::Focus, Some(Glyph::Mic), &s, Some(&live))), 12);
        assert_eq!(cells(&buttons(Kind::Plain, None, &s, None)), 9);
        // the meter is the band's own color, nothing at rest, one cell a level
        assert_eq!(meter(None), "");
        assert_eq!(meter(Some(&rest)), "");
        assert_eq!(cells(&meter(Some(&live))), METER);
        assert!(meter(Some(&live)).starts_with("&#x2581;&#x2583;"));
    }

    #[test]
    fn with_a_half_space_the_chip_is_the_glyph_and_half_a_cell_each_side() {
        let s = a_style(Some("6144"));
        let h = "<span size='6144'> </span>";
        let rest = Mic::default();
        assert_eq!(
            buttons(Kind::Focus, None, &s, Some(&rest)),
            format!("{h}{h}&#x2715;{h}{h}{h}{h}&#x25BD;{h}{h}{h}{h}&#x25A1;{h}{h}{h}{h}&#x25CB;{h}{h}")
        );
        assert_eq!(
            buttons(Kind::Plain, None, &s, Some(&rest)),
            format!(
                "{h}{h}<span foreground='#bf616a'>&#x2715;</span>{h}{h}{h}{h}<span foreground='#ebcb8b'>&#x25BD;</span>{h}{h}{h}{h}<span foreground='#a3be8c'>&#x25A1;</span>{h}{h}{h}{h}&#x25CB;{h}{h}"
            )
        );
        // the chip takes the inner half at each side, the outer ones stay outside it
        assert_eq!(
            buttons(Kind::Focus, Some(Glyph::Close), &s, None),
            format!("{h}<span background='#bf616a' foreground='#eceff4'>{h}&#x2715;{h}</span>{h}{h}{h}&#x25BD;{h}{h}{h}{h}&#x25A1;{h}{h}")
        );
        assert_eq!(
            buttons(Kind::Focus, Some(Glyph::Min), &s, None),
            format!("{h}{h}&#x2715;{h}{h}{h}<span background='#9db0cc'>{h}&#x25BD;{h}</span>{h}{h}{h}&#x25A1;{h}{h}")
        );
        assert!(buttons(Kind::Plain, Some(Glyph::Fill), &s, None)
            .ends_with(&format!("{h}<span background='#4c566a' foreground='#a3be8c'>{h}&#x25A1;{h}</span>{h}")));
        assert!(buttons(Kind::Plain, Some(Glyph::Mic), &s, Some(&rest)).ends_with(&format!("{h}<span background='#4c566a'>{h}&#x25CB;{h}</span>{h}")));
        // a button is as wide at rest and under the pointer: four halves and its glyph, three cells
        for kind in [Kind::Focus, Kind::Urgent, Kind::Plain] {
            for hover in [None, Some(Glyph::Close), Some(Glyph::Min), Some(Glyph::Fill), Some(Glyph::Mic)] {
                let m = buttons(kind, hover, &s, Some(&rest));
                assert_eq!((m.matches(h).count(), cells(&m)), (16, 12), "{m}");
            }
        }
        assert_eq!(cells(&buttons(Kind::Focus, None, &s, None)), 9);
        assert_eq!(cells(h), 1);
        assert_eq!(cells(&format!("{h}{h}x")), 2);
    }

    #[test]
    fn a_half_space_is_a_size_safe_in_a_title() {
        assert_eq!(half_size(Some("6144")), Some("6144".into()));
        assert_eq!(half_size(Some(" 5632 ")), Some("5632".into()));
        for bad in [
            "",
            "  ",
            "0",
            "8px",
            "6.5pt",
            "50%",
            "-6144",
            "6144' background='#ff0000",
            "6\" ; exec x",
            "12345678",
        ] {
            assert_eq!(half_size(Some(bad)), None, "{bad}");
        }
        assert_eq!(half_size(None), None);
    }

    #[test]
    fn the_mic_follows_the_voice_state_and_its_bars_slide() {
        let rest = Mic::default();
        assert_eq!(mic_state("", &rest), rest);
        let a = mic_state("listening 1\nlevel 4\n", &rest);
        assert_eq!(a.bars, [0, 0, 0, 0, 0, 0, 0, 4]);
        let b = mic_state("listening 1\nlevel 9\n", &a);
        assert_eq!(b.bars, [0, 0, 0, 0, 0, 0, 4, 7]);
        assert_eq!(mic_state("listening 0\nlevel 3\n", &b), rest);
    }

    #[test]
    fn the_name_is_cut_to_its_room_and_the_meter_keeps_the_right_end() {
        let btn = " &#x2715;  &#x25BD;  &#x25A1; ";
        let short = title(40, btn, "  %title", "notes", "");
        assert_eq!(cells(&short), 40 - METER);
        assert!(short.starts_with(&format!("{btn}  notes ")));
        // a name longer than its room is cut with an ellipsis, a blank short of the meter, and the line stays as wide
        let long = title(40, btn, "  %title", "a window with a name far longer than its band", "");
        assert_eq!(cells(&long), 40 - METER);
        assert!(long.contains(&format!("a window with a nam{ELLIPSIS} ")), "{long}");
        // the meter takes the cells kept for it, wherever the name ends
        let live = Mic {
            listening: true,
            bars: [1; METER],
        };
        let m = meter(Some(&live));
        assert_eq!(cells(&title(40, btn, "  %title", "notes", &m)), 40);
        assert_eq!(cells(&title(40, btn, "  terminal   %title", "notes", &m)), 40);
        assert!(title(40, btn, "  %title", "notes", &m).ends_with(&m));
        // a band too narrow for a name keeps the buttons and the meter's room
        assert_eq!(title(14, btn, "  %title", "notes", &m), format!("{btn}  {m}"));
        // no window's name can carry markup or a command out of sway's quotes
        let shady = title(40, "", "%title", "a \"b\" <i>c</i> & d\\", "");
        assert!(shady.starts_with("a &quot;b&quot; &lt;i&gt;c&lt;/i&gt; &amp; d\\\\"), "{shady}");
        assert_eq!(cells(&shady), 32);
    }

    #[test]
    fn a_band_has_the_cells_its_width_holds() {
        assert_eq!(room(Rect::new(0, 0, 784, 23), 10.0), 76);
        assert_eq!(room(Rect::new(0, 0, 20, 23), 10.0), 0);
    }

    #[test]
    fn a_band_under_a_floating_window_has_no_glyphs() {
        // the floating window lies over the tiled band's left end, where its glyphs are
        let b = bands(&a_tree(true), 10.0);
        assert_eq!(b.iter().map(|b| b.id).collect::<Vec<_>>(), vec![6]);
    }
}
