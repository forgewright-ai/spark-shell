//! The pad's shape, place and list, pure: what the mock-up drew, in numbers. Every length is in
//! logical pixels of the screen's usable area (the part sway gives the windows: the bar left out),
//! its origin at that area's top left corner.

use serde_json::Value;
use std::time::{Duration, Instant};

/// The lengths the pad is drawn with, at a text size: the mock-up's at 16 px (Monaspace Neon 12),
/// in proportion at any other. The air off an edge (PAD_GAP), the snapping distances and the grips stay as they are.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Metrics {
    /// A titled slot at its widest: the icon and 18 cells of title.
    pub slot_max: i32,
    /// A titled slot at its narrowest: the icon and 8 cells of title.
    pub slot_min: i32,
    /// An icon's square cell.
    pub tool: i32,
    /// A titled row's height.
    pub cell: i32,
    /// The band's height, under the handle (PAD_BAND=on).
    pub band: i32,
    /// The handle across the pad's top.
    pub handle: i32,
    /// Hide's room at the end of the cells.
    pub ctl: i32,
    /// An icon's side.
    pub icon: i32,
    /// The air between the pad and an edge: the windows' outer gap, PAD_GAP.
    pub gap: i32,
    /// How near an edge or a snapping point a drop snaps to it, and how near the pointer takes an edge in a drag.
    pub snap: i32,
    /// How far the pointer goes from an edge a drag has taken before it lets the edge go.
    pub unsnap: i32,
    /// A grip's width along each side and corner of the pad, outside it.
    pub grip: i32,
    /// The room beside the pad for a label.
    pub tip_room: i32,
    /// A label's height, and a row's in a group's list.
    pub tip: i32,
}

/// The pad's margin from an edge when PAD_GAP says none: the desktop's outer gap.
pub const GAP: i32 = 8;

impl Metrics {
    /// The lengths for text of `px` pixels: the mock-up's at 16.
    pub fn for_text(px: f64) -> Metrics {
        let k = if px.is_finite() && px > 0.0 { (px / 16.0).clamp(0.5, 3.0) } else { 1.0 };
        let s = |v: f64| (v * k).round() as i32;
        Metrics {
            slot_max: s(228.0),
            slot_min: s(132.0),
            tool: s(36.0),
            cell: s(40.0),
            band: s(24.0),
            handle: s(6.0).max(4),
            ctl: s(24.0),
            icon: s(24.0),
            gap: GAP,
            snap: 48,
            unsnap: 96,
            grip: 8,
            tip_room: s(360.0),
            tip: s(24.0),
        }
    }
}

/// What a cell shows: an icon alone (the default), or a titled slot (PAD_VIEW=titles).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum View {
    #[default]
    Icons,
    Titles,
}

impl View {
    /// PAD_VIEW: titles is the titled slots; unset or anything else, the icons.
    pub fn parse(v: Option<&str>) -> View {
        match v {
            Some(v) if v.trim().eq_ignore_ascii_case("titles") => View::Titles,
            _ => View::Icons,
        }
    }
}

/// What the pad is asked to be: its view, the band, a column at a side (hide under the cells) or a row elsewhere
/// (hide at the first row's end), and the most width and height it takes; 0 for the width is as wide as the room
/// allows, 0 for the height as many rows as the windows need.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Want {
    pub view: View,
    pub band: bool,
    pub column: bool,
    pub w: i32,
    pub h: i32,
}

/// The pad's shape: the handle across its top, the band under it when it is on, a grid of cells, and hide at the end.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Layout {
    pub view: View,
    pub band: bool,
    /// Hide under the cells, a column's end; else at the end of the first row.
    pub column: bool,
    pub cols: i32,
    pub rows: i32,
    /// A cell's width and height: the icon's square, or a titled slot.
    pub cw: i32,
    pub ch: i32,
    pub w: i32,
    pub h: i32,
}

impl Layout {
    /// Where the cells begin: under the handle, and under the band when it is on.
    pub fn top(&self, m: &Metrics) -> i32 {
        m.handle + if self.band { m.band } else { 0 }
    }
}

/// The cells' and hide's lengths: a cell's least width and its height, the room at the top, hide's width and height.
fn parts(want: &Want, m: &Metrics) -> (i32, i32, i32, i32, i32) {
    let (cw, ch) = match want.view {
        View::Icons => (m.tool, m.tool),
        View::Titles => (m.slot_min, m.cell),
    };
    let top = m.handle + if want.band { m.band } else { 0 };
    let (end_w, end_h) = if want.column { (0, 1 + m.ctl) } else { (1 + m.ctl, 0) };
    (cw, ch, top, end_w, end_h)
}

/// How many columns and rows the asked width and height hold in the room, at least one each, and the width the
/// cells may take.
fn fit(want: &Want, room: (i32, i32), m: &Metrics) -> (i32, i32, i32) {
    let (cw, ch, top, end_w, end_h) = parts(want, m);
    let rw = room.0.max(cw + end_w);
    let rh = room.1.max(top + ch + end_h);
    let w = if want.w <= 0 { rw } else { want.w.min(rw) };
    let h = if want.h <= 0 { rh } else { want.h.min(rh) };
    (((w - end_w) / cw).max(1), ((h - top - end_h) / ch).max(1), w - end_w)
}

/// How many cells a pad asked `want` holds in the room: past it, an app's windows fold into one (`group`).
pub fn capacity(want: &Want, room: (i32, i32), m: &Metrics) -> usize {
    let (cols, rows, _) = fit(want, room, m);
    (cols * rows) as usize
}

/// The shape of a pad of `k` cells: the width sets the columns, the height the rows. Without a height, as many
/// columns as the width holds and the rows the cells need; with one, as many rows as it holds and the columns the
/// cells need, so a pad made two rows high is two rows. Never wider or taller than its whole cells; past them
/// (when grouping cannot fold enough), rows are added. A titled slot takes 18 cells of title at most, shrunk
/// evenly down to 8.
pub fn layout(k: usize, want: &Want, room: (i32, i32), m: &Metrics) -> Layout {
    let k = k.max(1) as i32;
    let (fit_cols, fit_rows, inner) = fit(want, room, m);
    let cols = if want.h > 0 {
        let rows = k.min(fit_rows);
        ((k + rows - 1) / rows).min(fit_cols)
    } else {
        k.min(fit_cols)
    };
    let rows = (k + cols - 1) / cols;
    let (_, ch, top, end_w, end_h) = parts(want, m);
    let cw = match want.view {
        View::Icons => m.tool,
        View::Titles => (inner / cols).clamp(m.slot_min, m.slot_max),
    };
    Layout {
        view: want.view,
        band: want.band,
        column: want.column,
        cols,
        rows,
        cw,
        ch,
        w: cols * cw + end_w,
        h: top + rows * ch + end_h,
    }
}

/// One cell's worth: a window, or the windows of one app folded into one icon (a group). Their places in the
/// window list, oldest first.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Item {
    pub wins: Vec<usize>,
}

impl Item {
    pub fn group(&self) -> bool {
        self.wins.len() > 1
    }
}

/// The cells for windows of these apps (each window's app's name, oldest first) when `cap` cells hold them: each
/// window its own while they fit; else the app with the most windows folds into one icon, then the next, until they
/// fit (on a tie, the app whose window came first). A group stands where its oldest window would. Made big enough
/// again, each window has its own once more.
pub fn group(names: &[String], cap: usize) -> Vec<Item> {
    let cap = cap.max(1);
    let mut folded: Vec<&str> = vec![];
    let mut count = names.len();
    while count > cap {
        let mut best: Option<(&str, usize)> = None;
        for (i, name) in names.iter().enumerate() {
            if folded.contains(&name.as_str()) || names[..i].contains(name) {
                continue;
            }
            let n = names.iter().filter(|x| *x == name).count();
            if n >= 2 && best.is_none_or(|(_, b)| n > b) {
                best = Some((name, n));
            }
        }
        let Some((name, n)) = best else { break };
        folded.push(name);
        count -= n - 1;
    }
    let mut out: Vec<Item> = vec![];
    for (i, name) in names.iter().enumerate() {
        if folded.contains(&name.as_str()) {
            if let Some(it) = out.iter_mut().find(|it| names[it.wins[0]] == *name) {
                it.wins.push(i);
                continue;
            }
        }
        out.push(Item { wins: vec![i] });
    }
    out
}

/// The filled circled number a group's icon wears at its top right: the font's own, U+2777 for two windows to
/// U+277F for ten, ten for more; none for one.
pub fn badge(n: usize) -> Option<char> {
    match n {
        0 | 1 => None,
        2..=10 => char::from_u32(0x2775 + n as u32),
        _ => Some('\u{277f}'),
    }
}

/// An edge of the usable area.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Edge {
    Top,
    Bottom,
    Left,
    Right,
}

impl Edge {
    pub fn side(self) -> bool {
        matches!(self, Edge::Left | Edge::Right)
    }

    fn word(self) -> &'static str {
        match self {
            Edge::Top => "top",
            Edge::Bottom => "bottom",
            Edge::Left => "left",
            Edge::Right => "right",
        }
    }
}

/// Where along its edge a docked pad stands.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Along {
    Center,
    /// At the left end, or the top of a side.
    Start,
    /// At the right end, or the bottom of a side.
    End,
    /// Its middle at this many pixels along the edge.
    At(i32),
}

/// The pad's place: docked at an edge, or free at a corner position.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Place {
    Dock(Edge, Along),
    Free(i32, i32),
}

impl Default for Place {
    fn default() -> Place {
        Place::Dock(Edge::Bottom, Along::Center)
    }
}

impl Place {
    /// "bottom center", "left start", "top 640", "free 120 300"; None for anything else.
    pub fn parse(s: &str) -> Option<Place> {
        let w: Vec<&str> = s.split_whitespace().collect();
        let num = |v: &str| v.parse::<i32>().ok().filter(|n| (-100_000..=100_000).contains(n));
        match w.as_slice() {
            ["free", x, y] => Some(Place::Free(num(x)?, num(y)?)),
            [edge, along] => {
                let edge = match *edge {
                    "top" => Edge::Top,
                    "bottom" => Edge::Bottom,
                    "left" => Edge::Left,
                    "right" => Edge::Right,
                    _ => return None,
                };
                let along = match *along {
                    "center" => Along::Center,
                    "start" => Along::Start,
                    "end" => Along::End,
                    v => Along::At(num(v)?),
                };
                Some(Place::Dock(edge, along))
            }
            _ => None,
        }
    }

    /// The words parse reads back.
    pub fn words(&self) -> String {
        match self {
            Place::Free(x, y) => format!("free {x} {y}"),
            Place::Dock(e, a) => {
                let a = match a {
                    Along::Center => "center".to_string(),
                    Along::Start => "start".to_string(),
                    Along::End => "end".to_string(),
                    Along::At(n) => n.to_string(),
                };
                format!("{} {a}", e.word())
            }
        }
    }

    pub fn side(&self) -> bool {
        matches!(self, Place::Dock(e, _) if e.side())
    }

    /// The edge it is docked at.
    pub fn edge(&self) -> Option<Edge> {
        match self {
            Place::Dock(e, _) => Some(*e),
            Place::Free(..) => None,
        }
    }
}

/// A rectangle: x, y, width, height.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub fn new(x: i32, y: i32, w: i32, h: i32) -> Rect {
        Rect { x, y, w, h }
    }

    pub fn has(&self, x: f64, y: f64) -> bool {
        x >= self.x as f64 && y >= self.y as f64 && x < (self.x + self.w) as f64 && y < (self.y + self.h) as f64
    }
}

fn clamp(v: i32, lo: i32, hi: i32) -> i32 {
    v.max(lo).min(hi.max(lo))
}

fn along_at(along: Along, len: i32, span: i32, gap: i32) -> i32 {
    match along {
        Along::Center => (span - len) / 2,
        Along::Start => gap,
        Along::End => span - gap - len,
        Along::At(c) => clamp(c - len / 2, gap, span - gap - len),
    }
}

/// Where a pad of `w` by `h` stands in a usable area of `aw` by `ah`: its top left corner.
pub fn position(place: Place, w: i32, h: i32, aw: i32, ah: i32, m: &Metrics) -> (i32, i32) {
    match place {
        Place::Dock(Edge::Bottom, a) => (along_at(a, w, aw, m.gap), ah - m.gap - h),
        Place::Dock(Edge::Top, a) => (along_at(a, w, aw, m.gap), m.gap),
        Place::Dock(Edge::Left, a) => (m.gap, along_at(a, h, ah, m.gap)),
        Place::Dock(Edge::Right, a) => (aw - m.gap - w, along_at(a, h, ah, m.gap)),
        Place::Free(x, y) => (clamp(x, 0, aw - w), clamp(y, 0, ah - h)),
    }
}

/// The edge a dragged pad holds, from the pointer at `at` in the usable area (the bar's edge counted from the
/// bar), never from the pad's own outline, which the edge changes: the nearest edge within the snapping distance;
/// an edge held stays until the pointer is `unsnap` from it, so a pointer trembling at the line never flips the
/// pad's shape. The drop docks at the edge the drag holds.
pub fn drag_edge(held: Option<Edge>, at: (f64, f64), aw: i32, ah: i32, m: &Metrics) -> Option<Edge> {
    let off = |e: Edge| match e {
        Edge::Left => at.0,
        Edge::Right => aw as f64 - at.0,
        Edge::Top => at.1,
        Edge::Bottom => ah as f64 - at.1,
    };
    if let Some(e) = held.filter(|&e| off(e) < m.unsnap as f64) {
        return Some(e);
    }
    [Edge::Left, Edge::Right, Edge::Top, Edge::Bottom]
        .into_iter()
        .map(|e| (e, off(e)))
        .filter(|&(_, d)| d <= m.snap as f64)
        .min_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(e, _)| e)
}

/// Along an edge: the center within the snapping distance, or either end within it of its corner,
/// else where the pad was let go.
pub fn snap_along(edge: Edge, r: Rect, aw: i32, ah: i32, m: &Metrics) -> Along {
    let (pos, len, span) = if edge.side() { (r.y, r.h, ah) } else { (r.x, r.w, aw) };
    let c = pos + len / 2;
    if (c - span / 2).abs() <= m.snap {
        Along::Center
    } else if pos - m.gap <= m.snap {
        Along::Start
    } else if span - m.gap - (pos + len) <= m.snap {
        Along::End
    } else {
        Along::At(c)
    }
}

/// The strip a docked pad keeps, the windows tiling beside it, as thick as the pad is: its height at the top or
/// the bottom, its width at a side; 0 for a free pad, which floats over the windows.
pub fn strip_thick(place: Place, l: &Layout) -> i32 {
    match place {
        Place::Dock(e, _) if e.side() => l.w,
        Place::Dock(..) => l.h,
        Place::Free(..) => 0,
    }
}

/// The sides a grip moves: x -1 the left, 1 the right; y -1 the top, 1 the bottom; 0 neither. A corner moves two.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sides {
    pub x: i8,
    pub y: i8,
}

/// What a point of the pad (its own coordinates) is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Hit {
    Item(usize),
    Hide,
    /// The handle, and the band under it.
    Handle,
    /// The grips just outside a side or a corner.
    Grip(Sides),
    /// A row of a group's list.
    Row(usize),
    Nothing,
}

/// A cell's rectangle in the pad's coordinates.
pub fn item_rect(l: &Layout, i: usize, m: &Metrics) -> Rect {
    let (col, row) = (i as i32 % l.cols, i as i32 / l.cols);
    Rect::new(col * l.cw, l.top(m) + row * l.ch, l.cw, l.ch)
}

/// The hide button's rectangle: past a hairline at the end of the first row, or under a column's cells.
pub fn hide_rect(l: &Layout, m: &Metrics) -> Rect {
    let top = l.top(m);
    if l.column {
        Rect::new(0, top + l.rows * l.ch + 1, l.w, m.ctl)
    } else {
        Rect::new(l.cols * l.cw + 1, top, m.ctl, l.ch)
    }
}

/// What the point x, y is on a pad of `k` cells docked at `dock`: a cell, hide, the handle or the band, or one of
/// the grips, `m.grip` wide just outside each side and corner, a corner's reaching `m.grip` along each side. A
/// docked pad has none at its edge: it grows away from it.
pub fn hit(l: &Layout, k: usize, m: &Metrics, x: f64, y: f64, dock: Option<Edge>) -> Hit {
    let (w, h, g) = (l.w as f64, l.h as f64, m.grip as f64);
    if !Rect::new(0, 0, l.w, l.h).has(x, y) {
        if x < -g || y < -g || x >= w + g || y >= h + g {
            return Hit::Nothing;
        }
        let mut sx = if x < g { -1 } else { i8::from(x >= w - g) };
        let mut sy = if y < g { -1 } else { i8::from(y >= h - g) };
        match dock {
            Some(Edge::Left) if sx < 0 => sx = 0,
            Some(Edge::Right) if sx > 0 => sx = 0,
            Some(Edge::Top) if sy < 0 => sy = 0,
            Some(Edge::Bottom) if sy > 0 => sy = 0,
            _ => {}
        }
        return if sx == 0 && sy == 0 {
            Hit::Nothing
        } else {
            Hit::Grip(Sides { x: sx, y: sy })
        };
    }
    if hide_rect(l, m).has(x, y) {
        return Hit::Hide;
    }
    if y < l.top(m) as f64 {
        return Hit::Handle;
    }
    (0..k).find(|&i| item_rect(l, i, m).has(x, y)).map_or(Hit::Nothing, Hit::Item)
}

/// The band's words: pad and how many windows wait, or the lit window's words (`item_line`); pad alone
/// when there is no room.
pub fn band_words(w: i32, n: usize, lit: Option<&str>, m: &Metrics) -> String {
    if !band_says(w, m) {
        return "pad".into();
    }
    match lit {
        Some(t) => format!("pad \u{b7} {t}"),
        None if n == 1 => "pad \u{b7} 1 window".into(),
        None => format!("pad \u{b7} {n} windows"),
    }
}

/// Whether a band `w` wide has the room to say the count or the lit window's words.
fn band_says(w: i32, m: &Metrics) -> bool {
    w >= m.slot_max * 160 / 228
}

/// Whether the lit window's words show in a label beside the pad: always, but where the band says them.
pub fn labeled(l: &Layout, m: &Metrics) -> bool {
    !l.band || !band_says(l.w, m)
}

/// An app's name as spark-shell's win_label makes it, as the dialog names a window: the last dot-separated word
/// of its app id or X11 class, lowercase (org.mozilla.firefox is firefox); footclient is foot, and the dialog,
/// spark-dialog, is spark.
pub fn app_name(app: &str) -> String {
    let name = app.trim().rsplit('.').next().unwrap_or_default().to_lowercase();
    match name.as_str() {
        "footclient" => "foot".into(),
        DIALOG => "spark".into(),
        _ => name,
    }
}

/// The dialog's app id: on the pad it wears spark's own mark, the block-letter S, never an icon theme's.
pub const DIALOG: &str = "spark-dialog";

/// The heights spark's mark comes in as a PNG next to spark-shell (asset/favicon-N.png and its -light twin).
pub const MARK_PNGS: [i32; 4] = [16, 19, 22, 26];

/// Whether a ground is dark, spark-shell's rule (theme_is_dark): its luminance under half, in whole numbers.
pub fn dark_ground(r: u8, g: u8, b: u8) -> bool {
    (r as u32 * 299 + g as u32 * 587 + b as u32 * 114) / 1000 < 128
}

/// Spark's mark for an icon of `px` pixels on a ground: its file in the assets, favicon for a dark ground and
/// favicon-light for a light one, never recolored. The PNG nearest the size at or above it; above the largest,
/// the SVG, drawn at the size.
pub fn mark_file(dark: bool, px: i32) -> String {
    let stem = if dark { "favicon" } else { "favicon-light" };
    match MARK_PNGS.iter().find(|&&n| n >= px) {
        Some(n) => format!("{stem}-{n}.png"),
        None => format!("{stem}.svg"),
    }
}

/// An item's words, the dialog's rule: the app's name, then the window's title when it is not the name, both
/// lowercase. The painter draws the name in the text color and the title muted, and cuts them to the slot.
pub fn item_words(app: &str, title: &str) -> (String, Option<String>) {
    let name = app_name(app);
    let title: String = title
        .trim()
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect::<String>()
        .to_lowercase();
    if name.is_empty() {
        (title, None)
    } else if title.is_empty() || title == name {
        (name, None)
    } else {
        (name, Some(title))
    }
}

/// A group's words: its app's name, then how many windows it holds.
pub fn group_words(app: &str, n: usize) -> (String, Option<String>) {
    let name = app_name(app);
    let count = format!("{n} windows");
    if name.is_empty() {
        (count, None)
    } else {
        (name, Some(count))
    }
}

/// Words on one line, as the band and a label say the lit item: the name, two spaces, the rest.
pub fn line((name, rest): (String, Option<String>)) -> String {
    match rest {
        Some(rest) => format!("{name}  {rest}"),
        None => name,
    }
}

/// A window's words on one line, as the band, a label and a group's list say it.
pub fn item_line(app: &str, title: &str) -> String {
    line(item_words(app, title))
}

/// Where the title goes in a slot's text box `room` wide, once the name took `name_w` of it: past the name and
/// `space`, in what is left (the painter cuts it with an ellipsis); none when less than `least` is left.
pub fn title_room(room: f64, name_w: f64, space: f64, least: f64) -> Option<(f64, f64)> {
    let x = name_w + space;
    (room - x >= least).then_some((x, room - x))
}

/// The air between the pad and what stands beside it.
pub const AIR: i32 = 6;

/// Where a label or a group's list `size` stands beside the pad, away from the edge it sits on, by the item at
/// `cell` (the pad and the cell in the coordinates of `bounds`): over a pad at the bottom, under one at the top,
/// right of one at the left and left of one at the right; a free pad's over it, or under it with no room over it,
/// and beside a pad taller than wide. Kept inside the bounds.
pub fn beside(pad: Rect, cell: Rect, size: (i32, i32), edge: Option<Edge>, bounds: (i32, i32)) -> (i32, i32) {
    let (w, h) = size;
    let mid = cell.y + (cell.h - h) / 2;
    let above = pad.y - AIR - h;
    let below = pad.y + pad.h + AIR;
    let right = pad.x + pad.w + AIR;
    let left = pad.x - AIR - w;
    let (x, y) = match edge {
        Some(Edge::Bottom) => (cell.x, above),
        Some(Edge::Top) => (cell.x, below),
        Some(Edge::Left) => (right, mid),
        Some(Edge::Right) => (left, mid),
        None if pad.h > pad.w => (if right + w <= bounds.0 || left < 0 { right } else { left }, mid),
        None => (cell.x, if above >= 0 { above } else { below }),
    };
    (x.min(bounds.0 - w).max(0), y.min(bounds.1 - h).max(0))
}

/// A group's list: one row a window, `row` high and `w` wide, beside the group's cell.
pub fn list_rect(pad: Rect, cell: Rect, rows: usize, w: i32, row: i32, edge: Option<Edge>, bounds: (i32, i32)) -> Rect {
    let h = rows as i32 * row;
    let (x, y) = beside(pad, cell, (w, h), edge, bounds);
    Rect::new(x, y, w, h)
}

/// The row of a list at `r` the point x, y is on.
pub fn list_row(r: Rect, row: i32, rows: usize, x: f64, y: f64) -> Option<usize> {
    if !r.has(x, y) || row <= 0 {
        return None;
    }
    let i = ((y - r.y as f64) / row as f64) as usize;
    (i < rows).then_some(i)
}

/// The size a grip's drag asks, from the pad's rectangle at the press and how far the pointer `moved` since: the
/// grip's side follows the pointer and the other side stays, so the size grows by the distance outward; a docked
/// pad grows away from its edge, and along it from both ends when it stands at the middle. Each between one icon's
/// cell and the room; None for a length the grip leaves alone.
pub fn grip_size(place: Place, s: Sides, start: Rect, moved: (f64, f64), room: (i32, i32), m: &Metrics) -> (Option<i32>, Option<i32>) {
    let both = |a: Along| if matches!(a, Along::Center | Along::At(_)) { 2 } else { 1 };
    let (kw, kh) = match place {
        Place::Free(..) => (1, 1),
        Place::Dock(e, a) if e.side() => (1, both(a)),
        Place::Dock(_, a) => (both(a), 1),
    };
    let out = |d: f64, sign: i8| (d * sign as f64).round() as i32;
    let w = (s.x != 0).then(|| (start.w + kw * out(moved.0, s.x)).clamp(m.tool, room.0.max(m.tool)));
    let h = (s.y != 0).then(|| (start.h + kh * out(moved.1, s.y)).clamp(m.tool, room.1.max(m.tool)));
    (w, h)
}

/// A free pad resized from its left or its top keeps its other side where it was: its corner, once it is `w` by `h`.
/// A docked pad stays where it is docked.
pub fn grip_place(place: Place, s: Sides, start: Rect, w: i32, h: i32) -> Place {
    match place {
        Place::Free(..) => Place::Free(
            if s.x < 0 { (start.x + start.w - w).max(0) } else { start.x },
            if s.y < 0 { (start.y + start.h - h).max(0) } else { start.y },
        ),
        p => p,
    }
}

/// The pointer goes this far with the button held before a press is a drag.
pub const DRAG_START: f64 = 6.0;

/// What a drag does: moves the pad, or sizes it from a grip.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Grab {
    Move,
    Grip(Sides),
}

/// What a press does when it is let go before it becomes a drag.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Click {
    /// A cell: its window back, or a group's list opened.
    Choose(usize),
    /// A row of a group's list: its window back.
    Row(usize),
    Hide,
    Nothing,
}

/// A press on the pad until its release: a drag once the pointer has gone `DRAG_START` with the button held, from
/// anywhere on the pad (a cell, the band, the handle; a grip sizes it), else a click. So a click never moves the
/// pad, and a drag never brings a window back. A group's list never moves the pad.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Gesture {
    pub what: Hit,
    pub at: (f64, f64),
    pub grab: Option<Grab>,
}

impl Gesture {
    pub fn press(what: Hit, at: (f64, f64)) -> Gesture {
        Gesture { what, at, grab: None }
    }

    /// The pointer at `to` with the button held: the drag the press becomes, once, when it is far enough.
    pub fn moved(&mut self, to: (f64, f64)) -> Option<Grab> {
        if self.grab.is_some() || matches!(self.what, Hit::Row(_)) || (to.0 - self.at.0).hypot(to.1 - self.at.1) < DRAG_START {
            return None;
        }
        let grab = match self.what {
            Hit::Grip(s) => Grab::Grip(s),
            _ => Grab::Move,
        };
        self.grab = Some(grab);
        Some(grab)
    }

    /// Let go on `what`: a click on what it pressed when it never became a drag.
    pub fn released(&self, what: Hit) -> Click {
        if self.grab.is_some() || what != self.what {
            return Click::Nothing;
        }
        match what {
            Hit::Item(i) => Click::Choose(i),
            Hit::Row(i) => Click::Row(i),
            Hit::Hide => Click::Hide,
            _ => Click::Nothing,
        }
    }
}

/// A key the pad reads, by what the layout names it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    Enter,
    Escape,
    Tab,
    /// 1 to 9: the item at that place, counted from 1.
    Digit(usize),
}

impl Key {
    /// A keysym (X11's keysymdef.h, as libxkbcommon gives it): the arrows and Home, End, Return,
    /// KP_Enter, space, Escape and Tab; 1 to 9; and h j k l as the arrows.
    pub fn of_sym(sym: u32) -> Option<Key> {
        Some(match sym {
            0xff51 | 0x68 => Key::Left,
            0xff53 | 0x6c => Key::Right,
            0xff52 | 0x6b => Key::Up,
            0xff54 | 0x6a => Key::Down,
            0xff50 => Key::Home,
            0xff57 => Key::End,
            0xff0d | 0xff8d | 0x20 => Key::Enter,
            0xff1b => Key::Escape,
            0xff09 => Key::Tab,
            0x31..=0x39 => Key::Digit((sym - 0x30) as usize),
            _ => return None,
        })
    }

    /// An evdev code read as its place on a US keyboard: when no keymap can be read.
    pub fn of_evdev(code: u32) -> Option<Key> {
        Some(match code {
            105 | 35 => Key::Left,
            106 | 38 => Key::Right,
            103 | 37 => Key::Up,
            108 | 36 => Key::Down,
            102 => Key::Home,
            107 => Key::End,
            28 | 96 | 57 => Key::Enter,
            1 => Key::Escape,
            15 => Key::Tab,
            2..=10 => Key::Digit((code - 1) as usize),
            _ => return None,
        })
    }
}

/// What a key does on a pad that has the keyboard.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyAct {
    Pick(usize),
    /// A cell's window back, or a group's list opened.
    Choose(usize),
    Leave,
    Nothing,
}

/// A key on a grid of `n` cells, `cols` a row: Left and Right go through them in order, Up and Down a row (into a
/// shorter last row, to its last cell; at the first or the last row, nowhere), Home and End to the first and the
/// last, 1 to 9 choose by place, Enter chooses the one picked, Esc leaves.
pub fn key(k: Key, sel: usize, n: usize, cols: usize) -> KeyAct {
    if n == 0 {
        return if k == Key::Escape { KeyAct::Leave } else { KeyAct::Nothing };
    }
    let last = n - 1;
    let sel = sel.min(last);
    let cols = cols.max(1);
    match k {
        Key::Left => KeyAct::Pick(sel.saturating_sub(1)),
        Key::Right | Key::Tab => KeyAct::Pick((sel + 1).min(last)),
        Key::Up => KeyAct::Pick(if sel >= cols { sel - cols } else { sel }),
        Key::Down => KeyAct::Pick(if sel + cols <= last {
            sel + cols
        } else if sel / cols < last / cols {
            last
        } else {
            sel
        }),
        Key::Home => KeyAct::Pick(0),
        Key::End => KeyAct::Pick(last),
        Key::Enter => KeyAct::Choose(sel),
        Key::Escape => KeyAct::Leave,
        Key::Digit(d) if (1..=n).contains(&d) => KeyAct::Choose(d - 1),
        Key::Digit(_) => KeyAct::Nothing,
    }
}

/// What a key does while a group's list is open.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ListAct {
    Pick(usize),
    Restore(usize),
    Close,
    Nothing,
}

/// A key on a group's list of `n` rows: Up and Down (Left and Right too) move a row, Home and End to the first and
/// the last, 1 to 9 bring back the window at that row, Enter the one picked, Esc closes the list.
pub fn list_key(k: Key, sel: usize, n: usize) -> ListAct {
    if n == 0 {
        return ListAct::Close;
    }
    let last = n - 1;
    let sel = sel.min(last);
    match k {
        Key::Up | Key::Left => ListAct::Pick(sel.saturating_sub(1)),
        Key::Down | Key::Right | Key::Tab => ListAct::Pick((sel + 1).min(last)),
        Key::Home => ListAct::Pick(0),
        Key::End => ListAct::Pick(last),
        Key::Enter => ListAct::Restore(sel),
        Key::Escape => ListAct::Close,
        Key::Digit(d) if (1..=n).contains(&d) => ListAct::Restore(d - 1),
        Key::Digit(_) => ListAct::Nothing,
    }
}

/// A window on the pad.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Win {
    pub id: i64,
    pub app: String,
    pub title: String,
}

/// The mark spark-shell gives a window it minimizes.
pub const MARK: &str = "_spark-shell.min.";

/// The windows spark-shell minimized: in sway's scratchpad, with its mark, oldest first.
pub fn minimized(tree: &Value) -> Vec<Win> {
    fn scratch(v: &Value) -> Option<&Value> {
        if v["type"] == "workspace" && v["name"] == "__i3_scratch" {
            return Some(v);
        }
        v["nodes"].as_array()?.iter().find_map(scratch)
    }
    let Some(ws) = scratch(tree) else { return vec![] };
    let text = |v: &Value| v.as_str().unwrap_or("").to_string();
    ws["floating_nodes"]
        .as_array()
        .map(|nodes| {
            nodes
                .iter()
                .filter(|c| {
                    c["marks"]
                        .as_array()
                        .is_some_and(|ms| ms.iter().any(|m| m.as_str().is_some_and(|m| m.starts_with(MARK))))
                })
                .filter_map(|c| {
                    let app = Some(text(&c["app_id"]))
                        .filter(|a| !a.is_empty())
                        .unwrap_or_else(|| text(&c["window_properties"]["class"]));
                    Some(Win {
                        id: c["id"].as_i64()?,
                        app,
                        title: text(&c["name"]),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// A window's title band in sight, where the pad draws the minimize and close glyphs: its rect in its
/// screen's own pixels, the window's whole rect for what lies over it, and whether it has the focus.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Band {
    pub id: i64,
    pub output: String,
    pub rect: Rect,
    pub whole: Rect,
    pub focused: bool,
}

/// The pixels between a band's right end and its glyphs.
pub const GLYPH_INSET: i32 = 8;

/// The glyphs at the right end of a band: minimize, fill the screen or put back, close.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Glyph {
    Min,
    Fill,
    Close,
}

/// A band's three glyph cells, each as tall as the band and as wide: minimize, fill, close.
pub fn glyph_cells(band: Rect) -> [Rect; 3] {
    let cell = band.h.max(1);
    let x1 = band.x + band.w - GLYPH_INSET;
    [
        Rect::new(x1 - 3 * cell, band.y, cell, band.h),
        Rect::new(x1 - 2 * cell, band.y, cell, band.h),
        Rect::new(x1 - cell, band.y, cell, band.h),
    ]
}

/// The glyph a point is on in a band.
pub fn glyph_at(band: Rect, x: f64, y: f64) -> Option<Glyph> {
    let [min, fill, close] = glyph_cells(band);
    if close.has(x, y) {
        Some(Glyph::Close)
    } else if fill.has(x, y) {
        Some(Glyph::Fill)
    } else if min.has(x, y) {
        Some(Glyph::Min)
    } else {
        None
    }
}

fn meets(a: Rect, b: Rect) -> bool {
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

fn num(v: &Value) -> i32 {
    v.as_i64().unwrap_or(0) as i32
}

fn rect_of(v: &Value) -> Rect {
    Rect::new(num(&v["x"]), num(&v["y"]), num(&v["width"]), num(&v["height"]))
}

fn kids(n: &Value) -> impl Iterator<Item = &Value> {
    n["nodes"]
        .as_array()
        .into_iter()
        .flatten()
        .chain(n["floating_nodes"].as_array().into_iter().flatten())
}

/// The title bands on each screen's current workspace, the tiled windows first and the floating ones in
/// their stacking order: each view with a title bar, its band placed by its parent's rect as sway gives
/// it, in the screen's own pixels. A workspace with a view in full screen has none, and a band whose
/// glyphs lie under a window above it is left out.
pub fn bands(tree: &Value) -> Vec<Band> {
    struct Seen {
        band: Rect,
        whole: Rect,
        id: i64,
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
                focused: s.focused,
            });
        }
    }
    let keep: Vec<bool> = (0..out.len())
        .map(|i| {
            let [a, _, b] = glyph_cells(out[i].rect);
            let zone = Rect::new(a.x, a.y, b.x + b.w - a.x, a.h);
            !out[i + 1..].iter().any(|o| o.output == out[i].output && meets(zone, o.whole))
        })
        .collect();
    out.into_iter().zip(keep).filter_map(|(b, k)| k.then_some(b)).collect()
}

/// The views in sight, in the order sway's focus stacks give them, the latest first; none from the pad.
pub fn in_sight(tree: &Value) -> Vec<i64> {
    fn walk(n: &Value, out: &mut Vec<i64>) {
        if n["type"] == "workspace" && n["name"] == "__i3_scratch" {
            return;
        }
        if kids(n).next().is_none() {
            if n["type"] == "con" || n["type"] == "floating_con" {
                if let Some(id) = n["id"].as_i64() {
                    out.push(id);
                }
            }
            return;
        }
        let order: Vec<i64> = n["focus"].as_array().into_iter().flatten().filter_map(Value::as_i64).collect();
        for &id in &order {
            if let Some(k) = kids(n).find(|k| k["id"].as_i64() == Some(id)) {
                walk(k, out);
            }
        }
        for k in kids(n).filter(|k| !k["id"].as_i64().is_some_and(|id| order.contains(&id))) {
            walk(k, out);
        }
    }
    let mut out = vec![];
    walk(tree, &mut out);
    out
}

/// The windows in the order they were focused in, the latest first, and a walk through it: Super+Tab goes
/// to the window before, and within a second again to the one before that; the walk ends a second after
/// the last press, with the window it stopped on at the front.
#[derive(Default)]
pub struct History {
    mru: Vec<i64>,
    walk: Option<Walk>,
}

struct Walk {
    order: Vec<i64>,
    at: usize,
    last: Instant,
}

/// How long a walk waits for the next press.
pub const WALK: Duration = Duration::from_secs(1);

impl History {
    /// A window took the focus; during a walk the focus is the walk's own.
    pub fn focused(&mut self, id: i64) {
        if self.walk.is_some() {
            return;
        }
        self.mru.retain(|&i| i != id);
        self.mru.insert(0, id);
    }

    /// A window closed; the walk ends when it was the window the walk stood on, sway's own choice of
    /// focus taken from then on.
    pub fn closed(&mut self, id: i64) {
        self.mru.retain(|&i| i != id);
        if self.walk.as_ref().is_some_and(|w| w.order.get(w.at) == Some(&id)) {
            self.walk = None;
            return;
        }
        self.drop_from_walk(|i| i == id);
    }

    /// The windows in sight as sway orders them: the ones not known yet join at the back, the ones gone leave.
    pub fn seed(&mut self, ids: &[i64]) {
        self.mru.retain(|i| ids.contains(i));
        for &id in ids {
            if !self.mru.contains(&id) {
                self.mru.push(id);
            }
        }
        self.drop_from_walk(|i| !ids.contains(&i));
    }

    fn drop_from_walk(&mut self, gone: impl Fn(i64) -> bool) {
        if let Some(w) = self.walk.as_mut() {
            w.order.retain(|&i| !gone(i));
            w.at = w.at.min(w.order.len().saturating_sub(1));
        }
        if self.walk.as_ref().is_some_and(|w| w.order.len() < 2) {
            self.walk = None;
        }
    }

    /// The window Super+Tab goes to now; none with fewer than two.
    pub fn back(&mut self, now: Instant) -> Option<i64> {
        if self.walk.as_ref().is_none_or(|w| now.duration_since(w.last) > WALK) {
            if self.mru.len() < 2 {
                self.walk = None;
                return None;
            }
            self.walk = Some(Walk {
                order: self.mru.clone(),
                at: 0,
                last: now,
            });
        }
        let w = self.walk.as_mut()?;
        w.at = (w.at + 1) % w.order.len();
        w.last = now;
        Some(w.order[w.at])
    }

    /// A walk a second past its last press ends: the window it stopped on comes to the front.
    pub fn settle(&mut self, now: Instant) {
        if let Some(id) = self.walk.as_ref().filter(|w| now.duration_since(w.last) > WALK).map(|w| w.order[w.at]) {
            self.walk = None;
            self.focused(id);
        }
    }
}

/// The app an icon is looked up by: a desktop entry's id without .desktop, or its window class.
pub fn icon_key(app: &str) -> String {
    app.trim().to_lowercase()
}

/// The apps adapter's catalog (lib/apps.py): each app's id and window class to its icon's file.
pub fn icon_paths(catalog: &Value) -> Vec<(String, String)> {
    let apps = catalog.as_array().or_else(|| catalog["apps"].as_array());
    let mut out = vec![];
    for a in apps.into_iter().flatten() {
        let Some(icon) = a["icon"].as_str().filter(|p| p.starts_with('/') && p.ends_with(".png")) else {
            continue;
        };
        if let Some(id) = a["id"].as_str() {
            out.push((icon_key(id.trim_end_matches(".desktop")), icon.to_string()));
        }
        if let Some(c) = a["wm_class"].as_str().filter(|c| !c.is_empty()) {
            out.push((icon_key(c), icon.to_string()));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a_tree(over: bool) -> Value {
        // a screen of 1600 by 900 with the bar's 30 px, a tiled window with the focus and a floating one,
        // placed over the tiled one's glyphs when `over`
        let fx = if over { 700 } else { 100 };
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
        let b = bands(&a_tree(false));
        assert_eq!(b.len(), 2);
        assert_eq!(b[0].id, 5);
        assert!(b[0].focused);
        assert_eq!(b[0].rect, Rect::new(8, 38, 784, 23));
        assert_eq!(b[0].whole, Rect::new(8, 38, 784, 854));
        assert_eq!(b[1].rect, Rect::new(100, 27, 400, 23));
        let [min, fill, close] = glyph_cells(b[0].rect);
        assert_eq!(min, Rect::new(792 - 8 - 69, 38, 23, 23));
        assert_eq!(fill, Rect::new(792 - 8 - 46, 38, 23, 23));
        assert_eq!(close, Rect::new(792 - 8 - 23, 38, 23, 23));
        assert_eq!(glyph_at(b[0].rect, 775.0, 50.0), Some(Glyph::Close));
        assert_eq!(glyph_at(b[0].rect, 750.0, 50.0), Some(Glyph::Fill));
        assert_eq!(glyph_at(b[0].rect, 720.0, 50.0), Some(Glyph::Min));
        assert_eq!(glyph_at(b[0].rect, 700.0, 50.0), None);
    }

    #[test]
    fn a_band_under_a_floating_window_has_no_glyphs() {
        let b = bands(&a_tree(true));
        assert_eq!(b.iter().map(|b| b.id).collect::<Vec<_>>(), vec![6]);
    }

    #[test]
    fn the_views_in_sight_follow_the_focus_stacks() {
        assert_eq!(in_sight(&a_tree(false)), vec![5, 6]);
    }

    #[test]
    fn a_walk_goes_back_and_further_within_a_second() {
        let mut h = History::default();
        h.seed(&[5, 6, 7]);
        h.focused(7);
        let t = Instant::now();
        assert_eq!(h.back(t), Some(5));
        h.focused(5); // sway's event for the walk's own focus: not taken
        assert_eq!(h.back(t + Duration::from_millis(300)), Some(6));
        assert_eq!(h.back(t + Duration::from_millis(600)), Some(7));
        h.settle(t + Duration::from_millis(900));
        assert_eq!(h.back(t + Duration::from_millis(950)), Some(5));
        h.settle(t + Duration::from_secs(3));
        assert_eq!(h.back(t + Duration::from_secs(4)), Some(7));
        h.closed(7);
        h.settle(t + Duration::from_secs(6));
        assert_eq!(h.back(t + Duration::from_secs(7)), Some(6));
        h.seed(&[5]);
        h.settle(t + Duration::from_secs(9));
        assert_eq!(h.back(t + Duration::from_secs(10)), None);
    }

    fn m() -> Metrics {
        Metrics::for_text(16.0)
    }

    /// The room on a 1920 by 1054 area, the gap off each side.
    const ROOM: (i32, i32) = (1904, 1038);

    fn want(view: View, column: bool, w: i32, h: i32) -> Want {
        Want {
            view,
            band: false,
            column,
            w,
            h,
        }
    }

    fn names(apps: &[&str]) -> Vec<String> {
        apps.iter().map(|a| a.to_string()).collect()
    }

    fn wins(items: &[Item]) -> Vec<Vec<usize>> {
        items.iter().map(|it| it.wins.clone()).collect()
    }

    #[test]
    fn icons_at_the_bottom_are_a_row_and_at_a_side_a_column() {
        let m = m();
        // three windows at the bottom: three cells of 36 under the 6 px handle, a hairline and hide at the row's end
        assert_eq!(
            layout(3, &want(View::Icons, false, 0, 0), ROOM, &m),
            Layout {
                view: View::Icons,
                band: false,
                column: false,
                cols: 3,
                rows: 1,
                cw: 36,
                ch: 36,
                w: 3 * 36 + 1 + 24,
                h: 6 + 36
            }
        );
        // at a side, its 36 px: a column, hide under it past a hairline
        assert_eq!(
            layout(3, &want(View::Icons, true, 36, 0), ROOM, &m),
            Layout {
                view: View::Icons,
                band: false,
                column: true,
                cols: 1,
                rows: 3,
                cw: 36,
                ch: 36,
                w: 36,
                h: 6 + 3 * 36 + 1 + 24
            }
        );
        // the width no longer switches the view: a wide pad is icons, a narrow titled one titled
        assert_eq!(layout(3, &want(View::Icons, false, 1500, 0), ROOM, &m).cw, 36);
        assert_eq!(layout(3, &want(View::Titles, true, 36, 0), ROOM, &m).cw, 132);
        // with no height asked the rows come as the width needs them: seven in a width of three
        let l = layout(7, &want(View::Icons, false, 3 * 36 + 25, 0), ROOM, &m);
        assert_eq!((l.cols, l.rows, l.w, l.h), (3, 3, 133, 6 + 108));
        // never wider than its cells, nor than the room
        assert_eq!(layout(2, &want(View::Icons, false, 900, 0), ROOM, &m).w, 2 * 36 + 25);
        assert_eq!(capacity(&want(View::Icons, false, 0, 0), ROOM, &m), 52 * 28);
    }

    #[test]
    fn the_width_sets_the_columns_and_the_height_the_rows() {
        let m = m();
        // a row of four made two rows high from a corner, its width as it was: two of two
        let l = layout(4, &want(View::Icons, false, 4 * 36 + 25, 6 + 72 + 4), ROOM, &m);
        assert_eq!((l.cols, l.rows, l.w, l.h), (2, 2, 2 * 36 + 25, 6 + 72));
        // three in two rows: two columns, the last row short
        let l = layout(3, &want(View::Icons, false, 0, 6 + 72), ROOM, &m);
        assert_eq!((l.cols, l.rows), (2, 2));
        // one window in a pad two rows high is one cell: never taller than its cells
        assert_eq!(layout(1, &want(View::Icons, false, 0, 6 + 72), ROOM, &m).rows, 1);
        // a square: three by three holds nine
        let square = want(View::Icons, false, 3 * 36 + 25, 6 + 3 * 36);
        assert_eq!(capacity(&square, ROOM, &m), 9);
        let l = layout(9, &square, ROOM, &m);
        assert_eq!((l.cols, l.rows), (3, 3));
        // a column at a side made two columns wide and four rows high
        let side = want(View::Icons, true, 72, 6 + 4 * 36 + 25);
        assert_eq!(capacity(&side, ROOM, &m), 8);
        let l = layout(8, &side, ROOM, &m);
        assert_eq!((l.cols, l.rows, l.w, l.h), (2, 4, 72, 6 + 144 + 25));
        // a width or a height under one cell is still one
        assert_eq!(capacity(&want(View::Icons, false, 10, 10), ROOM, &m), 1);
        // a height past the room is the room
        assert_eq!(capacity(&want(View::Icons, true, 36, 5000), ROOM, &m), 27);
        // more cells than the asked size holds (grouping could not fold enough): rows are added
        let l = layout(5, &want(View::Icons, false, 61, 78), ROOM, &m);
        assert_eq!((l.cols, l.rows), (1, 5));
    }

    #[test]
    fn titled_slots_grow_shrink_then_wrap() {
        let m = m();
        // three windows on a wide screen: three slots at their widest, hide past a hairline, the handle on top
        assert_eq!(
            layout(3, &want(View::Titles, false, 0, 0), ROOM, &m),
            Layout {
                view: View::Titles,
                band: false,
                column: false,
                cols: 3,
                rows: 1,
                cw: 228,
                ch: 40,
                w: 684 + 1 + 24,
                h: 6 + 40
            }
        );
        // the room for hide comes out of the width: five within 785 keep one row of 152
        let l = layout(5, &want(View::Titles, false, 785, 0), ROOM, &m);
        assert_eq!((l.cols, l.rows, l.cw, l.w, l.h), (5, 1, 152, 785, 46));
        // five within 445: three slots a row of 140, two rows
        let l = layout(5, &want(View::Titles, false, 445, 0), ROOM, &m);
        assert_eq!((l.cols, l.rows, l.cw, l.w, l.h), (3, 2, 140, 445, 6 + 80));
        // the band on: under the handle, over the slots
        let band = Want {
            band: true,
            ..want(View::Titles, false, 0, 0)
        };
        assert_eq!(layout(3, &band, ROOM, &m).h, 6 + 24 + 40);
        assert_eq!(layout(3, &band, ROOM, &m).top(&m), 30);
        // titled at a side: one slot at its narrowest, never under it
        let l = layout(3, &want(View::Titles, true, 36, 0), ROOM, &m);
        assert_eq!((l.cols, l.rows, l.w, l.h), (1, 3, 132, 6 + 120 + 25));
        // two rows asked of a titled pad
        let l = layout(5, &want(View::Titles, false, 0, 6 + 80), ROOM, &m);
        assert_eq!((l.cols, l.rows, l.cw), (3, 2, 228));
    }

    #[test]
    fn an_app_folds_only_when_the_cells_run_out_the_most_windows_first() {
        let apps = names(&["foot", "foot", "firefox", "foot", "xterm", "firefox"]);
        // room for every window: each its own, oldest first
        assert_eq!(wins(&group(&apps, 6)), vec![vec![0], vec![1], vec![2], vec![3], vec![4], vec![5]]);
        assert_eq!(wins(&group(&apps, 40)).len(), 6);
        // one cell short: foot, with the most, folds where its oldest stands
        assert_eq!(wins(&group(&apps, 5)), vec![vec![0, 1, 3], vec![2], vec![4], vec![5]]);
        assert_eq!(wins(&group(&apps, 4)), vec![vec![0, 1, 3], vec![2], vec![4], vec![5]]);
        // then firefox
        assert_eq!(wins(&group(&apps, 3)), vec![vec![0, 1, 3], vec![2, 5], vec![4]]);
        // nothing more to fold: every app one icon, whatever the room
        assert_eq!(wins(&group(&apps, 2)), vec![vec![0, 1, 3], vec![2, 5], vec![4]]);
        assert_eq!(wins(&group(&apps, 0)), vec![vec![0, 1, 3], vec![2, 5], vec![4]]);
        // a tie: the app whose window came first
        let tie = names(&["b", "a", "a", "b"]);
        assert_eq!(wins(&group(&tie, 3)), vec![vec![0, 3], vec![1], vec![2]]);
        // made big enough again, the group opens back into its icons
        assert_eq!(wins(&group(&tie, 4)), vec![vec![0], vec![1], vec![2], vec![3]]);
        assert!(group(&tie, 3)[0].group() && !group(&tie, 3)[1].group());
        assert_eq!(group(&[], 3), vec![]);
    }

    #[test]
    fn a_group_wears_its_count_circled() {
        assert_eq!(badge(0), None);
        assert_eq!(badge(1), None);
        assert_eq!(badge(2), Some('\u{2777}'));
        assert_eq!(badge(3), Some('\u{2778}'));
        assert_eq!(badge(9), Some('\u{277e}'));
        assert_eq!(badge(10), Some('\u{277f}'));
        assert_eq!(badge(11), Some('\u{277f}'));
        assert_eq!(badge(400), Some('\u{277f}'));
        assert_eq!(group_words("footclient", 3), ("foot".into(), Some("3 windows".into())));
        assert_eq!(line(group_words("org.mozilla.firefox", 2)), "firefox  2 windows");
        assert_eq!(line(group_words("", 2)), "2 windows");
    }

    #[test]
    fn places_read_and_write() {
        for s in ["bottom center", "top start", "left end", "right 400", "free 120 300", "free -4 0"] {
            assert_eq!(Place::parse(s).unwrap().words(), s);
        }
        assert_eq!(Place::parse("middle center"), None);
        assert_eq!(Place::parse("free 1"), None);
        assert_eq!(Place::parse("bottom here"), None);
        assert_eq!(Place::parse(""), None);
        assert_eq!(Place::default().words(), "bottom center");
        assert_eq!(Place::default().edge(), Some(Edge::Bottom));
        assert_eq!(Place::Free(1, 2).edge(), None);
    }

    #[test]
    fn views_read() {
        assert_eq!(View::parse(None), View::Icons);
        assert_eq!(View::parse(Some("titles")), View::Titles);
        assert_eq!(View::parse(Some(" Titles ")), View::Titles);
        assert_eq!(View::parse(Some("icons")), View::Icons);
        assert_eq!(View::parse(Some("slots")), View::Icons);
        assert_eq!(View::parse(Some("")), View::Icons);
    }

    #[test]
    fn positions_on_each_edge() {
        let m = m();
        let (aw, ah) = (1920, 1054);
        assert_eq!(position(Place::default(), 684, 64, aw, ah, &m), (618, 1054 - 8 - 64));
        assert_eq!(position(Place::Dock(Edge::Top, Along::Start), 684, 64, aw, ah, &m), (8, 8));
        assert_eq!(
            position(Place::Dock(Edge::Right, Along::End), 36, 211, aw, ah, &m),
            (1920 - 8 - 36, 1054 - 8 - 211)
        );
        assert_eq!(position(Place::Dock(Edge::Left, Along::At(100)), 36, 211, aw, ah, &m), (8, 8));
        assert_eq!(position(Place::Free(5000, -20), 200, 64, aw, ah, &m), (1720, 0));
        // PAD_GAP's margin
        let wide = Metrics { gap: 16, ..m };
        assert_eq!(position(Place::default(), 684, 64, aw, ah, &wide), (618, 1054 - 16 - 64));
    }

    #[test]
    fn snapping() {
        let m = m();
        let (aw, ah) = (1920, 1054);
        assert_eq!(drag_edge(None, (30.0, 400.0), aw, ah, &m), Some(Edge::Left));
        assert_eq!(drag_edge(None, (900.0, 1020.0), aw, ah, &m), Some(Edge::Bottom));
        assert_eq!(drag_edge(None, (1900.0, 1040.0), aw, ah, &m), Some(Edge::Bottom));
        assert_eq!(drag_edge(None, (900.0, 400.0), aw, ah, &m), None);
        // the edge held stays until 96 px, even with another edge nearer meanwhile
        assert_eq!(drag_edge(Some(Edge::Left), (90.0, 20.0), aw, ah, &m), Some(Edge::Left));
        assert_eq!(drag_edge(Some(Edge::Left), (96.0, 20.0), aw, ah, &m), Some(Edge::Top));
        assert_eq!(snap_along(Edge::Bottom, Rect::new(640, 0, 684, 64), aw, ah, &m), Along::Center);
        assert_eq!(snap_along(Edge::Bottom, Rect::new(40, 0, 684, 64), aw, ah, &m), Along::Start);
        assert_eq!(snap_along(Edge::Bottom, Rect::new(1200, 0, 684, 64), aw, ah, &m), Along::End);
        assert_eq!(snap_along(Edge::Bottom, Rect::new(300, 0, 400, 64), aw, ah, &m), Along::At(500));
        assert_eq!(snap_along(Edge::Left, Rect::new(16, 30, 36, 211), aw, ah, &m), Along::Start);
    }

    #[test]
    fn a_docked_pad_keeps_a_strip_as_thick_as_it_is() {
        let m = m();
        let row = layout(3, &want(View::Icons, false, 0, 0), ROOM, &m);
        let two = layout(4, &want(View::Icons, false, 0, 6 + 72), ROOM, &m);
        let column = layout(3, &want(View::Icons, true, 36, 0), ROOM, &m);
        assert_eq!(strip_thick(Place::default(), &row), 42);
        assert_eq!(strip_thick(Place::Dock(Edge::Top, Along::Start), &row), 42);
        // two rows: a strip of both
        assert_eq!(strip_thick(Place::default(), &two), 78);
        assert_eq!(strip_thick(Place::Dock(Edge::Left, Along::Center), &column), 36);
        assert_eq!(
            strip_thick(
                Place::Dock(Edge::Right, Along::End),
                &layout(8, &want(View::Icons, true, 72, 6 + 4 * 36 + 25), ROOM, &m)
            ),
            72
        );
        // free: none, it floats over the windows
        assert_eq!(strip_thick(Place::Free(0, 0), &row), 0);
        // the titled row's 46
        assert_eq!(strip_thick(Place::default(), &layout(3, &want(View::Titles, false, 0, 0), ROOM, &m)), 46);
    }

    #[test]
    fn hits_on_a_row_of_icons() {
        let m = m();
        let l = layout(3, &want(View::Icons, false, 0, 0), ROOM, &m);
        assert_eq!((l.w, l.h), (133, 42));
        // the handle across the top, the cells under it, hide past the hairline
        assert_eq!(hit(&l, 3, &m, 50.0, 3.0, None), Hit::Handle);
        assert_eq!(hit(&l, 3, &m, 18.0, 20.0, None), Hit::Item(0));
        assert_eq!(hit(&l, 3, &m, 90.0, 20.0, None), Hit::Item(2));
        assert_eq!(hit(&l, 3, &m, 108.5, 20.0, None), Hit::Nothing);
        assert_eq!(hit(&l, 3, &m, 120.0, 20.0, None), Hit::Hide);
        assert_eq!(item_rect(&l, 2, &m), Rect::new(72, 6, 36, 36));
        assert_eq!(hide_rect(&l, &m), Rect::new(109, 6, 24, 36));
        // the grips, 8 px outside each side, a corner's reaching 8 px along each side
        let g = |x: i8, y: i8| Hit::Grip(Sides { x, y });
        assert_eq!(hit(&l, 3, &m, -3.0, 20.0, None), g(-1, 0));
        assert_eq!(hit(&l, 3, &m, -3.0, -3.0, None), g(-1, -1));
        assert_eq!(hit(&l, 3, &m, 4.0, -3.0, None), g(-1, -1));
        assert_eq!(hit(&l, 3, &m, 50.0, -5.0, None), g(0, -1));
        assert_eq!(hit(&l, 3, &m, 136.0, 20.0, None), g(1, 0));
        assert_eq!(hit(&l, 3, &m, 136.0, 44.0, None), g(1, 1));
        assert_eq!(hit(&l, 3, &m, 50.0, 45.0, None), g(0, 1));
        assert_eq!(hit(&l, 3, &m, -9.0, 20.0, None), Hit::Nothing);
        assert_eq!(hit(&l, 3, &m, 50.0, 51.0, None), Hit::Nothing);
        // docked at the bottom: no grip at the edge, the corners by it are the sides'
        let b = Some(Edge::Bottom);
        assert_eq!(hit(&l, 3, &m, 50.0, 45.0, b), Hit::Nothing);
        assert_eq!(hit(&l, 3, &m, -3.0, 45.0, b), g(-1, 0));
        assert_eq!(hit(&l, 3, &m, -3.0, -3.0, b), g(-1, -1));
        assert_eq!(hit(&l, 3, &m, 50.0, -5.0, b), g(0, -1));
        // docked at the left: none at the left
        assert_eq!(hit(&l, 3, &m, -3.0, 20.0, Some(Edge::Left)), Hit::Nothing);
        assert_eq!(hit(&l, 3, &m, -3.0, -3.0, Some(Edge::Left)), g(0, -1));
        assert_eq!(hit(&l, 3, &m, 136.0, 20.0, Some(Edge::Right)), Hit::Nothing);
        assert_eq!(hit(&l, 3, &m, 50.0, -5.0, Some(Edge::Top)), Hit::Nothing);
    }

    #[test]
    fn hits_on_a_column_and_on_titled_slots() {
        let m = m();
        let c = layout(3, &want(View::Icons, true, 36, 0), ROOM, &m);
        assert_eq!(hit(&c, 3, &m, 18.0, 3.0, Some(Edge::Left)), Hit::Handle);
        assert_eq!(hit(&c, 3, &m, 18.0, 6.0 + 36.0 + 5.0, Some(Edge::Left)), Hit::Item(1));
        assert_eq!(hide_rect(&c, &m), Rect::new(0, 6 + 108 + 1, 36, 24));
        assert_eq!(hit(&c, 3, &m, 18.0, 6.0 + 108.0 + 0.5, Some(Edge::Left)), Hit::Nothing);
        assert_eq!(hit(&c, 3, &m, 18.0, 6.0 + 108.0 + 1.0 + 5.0, Some(Edge::Left)), Hit::Hide);
        // a grid's last row: an empty cell is nothing
        let g = layout(5, &want(View::Titles, false, 445, 0), ROOM, &m);
        assert_eq!(hit(&g, 5, &m, 350.0, 6.0 + 40.0 + 10.0, None), Hit::Nothing);
        assert_eq!(hit(&g, 5, &m, 150.0, 6.0 + 40.0 + 10.0, None), Hit::Item(4));
        // titled with the band: the band is the handle's, hide stands at the first row's end
        let band = layout(
            3,
            &Want {
                band: true,
                ..want(View::Titles, false, 0, 0)
            },
            ROOM,
            &m,
        );
        assert_eq!(hit(&band, 3, &m, 300.0, 20.0, None), Hit::Handle);
        assert_eq!(hit(&band, 3, &m, 300.0, 40.0, None), Hit::Item(1));
        assert_eq!(hit(&band, 3, &m, 690.0, 40.0, None), Hit::Hide);
        assert_eq!(item_rect(&band, 2, &m), Rect::new(456, 30, 228, 40));
    }

    #[test]
    fn the_band_says_the_count_or_the_lit_window_and_a_label_says_it_elsewhere() {
        let m = m();
        assert_eq!(band_words(684, 3, None, &m), "pad \u{b7} 3 windows");
        assert_eq!(band_words(228, 1, None, &m), "pad \u{b7} 1 window");
        let lit = item_line("org.mozilla.firefox", "Mozilla Firefox");
        assert_eq!(band_words(684, 3, Some(&lit), &m), "pad \u{b7} firefox  mozilla firefox");
        assert_eq!(band_words(140, 3, None, &m), "pad");
        let row = layout(3, &want(View::Icons, false, 0, 0), ROOM, &m);
        assert!(labeled(&row, &m));
        let band = |view, n| {
            layout(
                n,
                &Want {
                    band: true,
                    ..want(view, false, 0, 0)
                },
                ROOM,
                &m,
            )
        };
        // a band too narrow for the words leaves them to the label
        assert!(labeled(&band(View::Icons, 3), &m));
        assert!(!labeled(&band(View::Icons, 6), &m));
        assert!(!labeled(&band(View::Titles, 1), &m));
    }

    #[test]
    fn items_are_named_as_the_dialog_names_a_window() {
        // the app's name: the last word of its id, lowercase; then its title, lowercase
        assert_eq!(
            item_words("org.mozilla.firefox", "Mozilla Firefox"),
            ("firefox".into(), Some("mozilla firefox".into()))
        );
        assert_eq!(item_line("org.mozilla.firefox", "Mozilla Firefox"), "firefox  mozilla firefox");
        // footclient is foot, and foot's title says what foot does not
        assert_eq!(item_words("footclient", "terminal"), ("foot".into(), Some("terminal".into())));
        assert_eq!(item_line("foot", "~/projects/spark"), "foot  ~/projects/spark");
        // an X11 class, as sway gives an Xwayland window's
        assert_eq!(item_words("XTerm", "Build Log"), ("xterm".into(), Some("build log".into())));
        assert_eq!(item_words("Steam", "Friends List"), ("steam".into(), Some("friends list".into())));
        // a title that is the app's name says it once
        assert_eq!(item_words("Steam", "Steam"), ("steam".into(), None));
        assert_eq!(item_line("pavucontrol", "  Pavucontrol "), "pavucontrol");
        assert_eq!(item_words("org.gnome.Nautilus", ""), ("nautilus".into(), None));
        // the dialog is spark, then its window's title
        assert_eq!(item_words("spark-dialog", "Home"), ("spark".into(), Some("home".into())));
        assert_eq!(item_line("spark-dialog", "spark"), "spark");
        assert_eq!(group_words("spark-dialog", 2), ("spark".into(), Some("2 windows".into())));
        // a long title whole and lowercase: the painter cuts it to the slot with an ellipsis
        let long = "PyRadio - Title: A Song With A Title Far Longer Than Any Slot Holds";
        assert_eq!(
            item_words("pyradio", long),
            (
                "pyradio".into(),
                Some("pyradio - title: a song with a title far longer than any slot holds".into())
            )
        );
        assert_eq!(title_room(150.0, 60.0, 19.0, 16.0), Some((79.0, 71.0)));
        assert_eq!(title_room(150.0, 130.0, 19.0, 16.0), None);
        // no app id: the title alone
        assert_eq!(item_words("", "Untitled\tWindow"), ("untitled window".into(), None));
    }

    #[test]
    fn a_label_and_a_list_stand_beside_the_pad_away_from_its_edge() {
        let bounds = (1920, 1054);
        let pad = Rect::new(900, 976, 61, 78);
        let cell = Rect::new(900, 982, 36, 36);
        // at the bottom: over the pad, from the cell's left
        assert_eq!(beside(pad, cell, (200, 24), Some(Edge::Bottom), bounds), (900, 976 - 6 - 24));
        // at the top: under it
        let top = Rect::new(900, 8, 61, 78);
        assert_eq!(beside(top, Rect::new(900, 14, 36, 36), (200, 24), Some(Edge::Top), bounds), (900, 8 + 78 + 6));
        // at the left: right of it, by the cell; at the right: left of it
        let left = Rect::new(8, 400, 36, 139);
        let c = Rect::new(8, 442, 36, 36);
        assert_eq!(beside(left, c, (200, 24), Some(Edge::Left), bounds), (8 + 36 + 6, 442 + 6));
        assert_eq!(
            beside(
                Rect::new(1876, 400, 36, 139),
                Rect::new(1876, 442, 36, 36),
                (200, 24),
                Some(Edge::Right),
                bounds
            ),
            (1876 - 6 - 200, 448)
        );
        // free: over it, or under it at the area's top; beside a tall one
        assert_eq!(
            beside(Rect::new(500, 300, 133, 42), Rect::new(500, 306, 36, 36), (200, 24), None, bounds),
            (500, 270)
        );
        assert_eq!(
            beside(Rect::new(500, 10, 133, 42), Rect::new(500, 16, 36, 36), (200, 24), None, bounds),
            (500, 58)
        );
        assert_eq!(
            beside(Rect::new(500, 300, 36, 139), Rect::new(500, 306, 36, 36), (200, 24), None, bounds),
            (542, 312)
        );
        assert_eq!(
            beside(Rect::new(1800, 300, 36, 139), Rect::new(1800, 306, 36, 36), (200, 24), None, bounds),
            (1594, 312)
        );
        // kept inside: a cell near the right end
        assert_eq!(beside(pad, Rect::new(1850, 982, 36, 36), (200, 24), Some(Edge::Bottom), bounds), (1720, 946));
        // a list too tall to stand over a low pad stays inside
        assert_eq!(
            beside(Rect::new(900, 20, 61, 42), Rect::new(900, 26, 36, 36), (200, 72), None, (1920, 100)),
            (900, 28)
        );
    }

    #[test]
    fn a_group_list_picks_its_row() {
        let pad = Rect::new(900, 976, 61, 78);
        let cell = Rect::new(900, 982, 36, 36);
        let r = list_rect(pad, cell, 3, 200, 24, Some(Edge::Bottom), (1920, 1054));
        assert_eq!(r, Rect::new(900, 976 - 6 - 72, 200, 72));
        assert_eq!(list_row(r, 24, 3, 950.0, 898.0), Some(0));
        assert_eq!(list_row(r, 24, 3, 950.0, 922.0), Some(1));
        assert_eq!(list_row(r, 24, 3, 950.0, 969.9), Some(2));
        assert_eq!(list_row(r, 24, 3, 950.0, 970.0), None);
        assert_eq!(list_row(r, 24, 3, 899.0, 920.0), None);
        assert_eq!(list_row(r, 0, 3, 950.0, 920.0), None);
        // its keys: a row up and down, the ends, a row by its place, Enter the one picked, Esc closes
        assert_eq!(list_key(Key::Up, 2, 3), ListAct::Pick(1));
        assert_eq!(list_key(Key::Up, 0, 3), ListAct::Pick(0));
        assert_eq!(list_key(Key::Down, 1, 3), ListAct::Pick(2));
        assert_eq!(list_key(Key::Down, 2, 3), ListAct::Pick(2));
        assert_eq!(list_key(Key::Left, 1, 3), ListAct::Pick(0));
        assert_eq!(list_key(Key::Right, 1, 3), ListAct::Pick(2));
        assert_eq!(list_key(Key::Home, 2, 3), ListAct::Pick(0));
        assert_eq!(list_key(Key::End, 0, 3), ListAct::Pick(2));
        assert_eq!(list_key(Key::Enter, 1, 3), ListAct::Restore(1));
        assert_eq!(list_key(Key::Enter, 9, 3), ListAct::Restore(2));
        assert_eq!(list_key(Key::Digit(3), 0, 3), ListAct::Restore(2));
        assert_eq!(list_key(Key::Digit(4), 0, 3), ListAct::Nothing);
        assert_eq!(list_key(Key::Escape, 0, 3), ListAct::Close);
        assert_eq!(list_key(Key::Enter, 0, 0), ListAct::Close);
    }

    #[test]
    fn a_grip_sizes_the_pad_away_from_its_edge() {
        let m = m();
        let row = Rect::new(893, 1004, 133, 42);
        let n = Sides { x: 0, y: -1 };
        let nw = Sides { x: -1, y: -1 };
        let w = Sides { x: -1, y: 0 };
        let e = Sides { x: 1, y: 0 };
        let s = Sides { x: 0, y: 1 };
        // at the bottom's middle: the top grip 40 px up makes it 40 taller, the width left alone
        assert_eq!(grip_size(Place::default(), n, row, (3.0, -40.0), ROOM, &m), (None, Some(82)));
        // a corner: along the edge both ends move, so the width grows twice the pointer's way
        assert_eq!(grip_size(Place::default(), nw, row, (-10.0, -40.0), ROOM, &m), (Some(153), Some(82)));
        // the left side in: narrower on both ends, never under one cell
        assert_eq!(grip_size(Place::default(), w, row, (30.0, 0.0), ROOM, &m), (Some(73), None));
        assert_eq!(grip_size(Place::default(), w, row, (300.0, 0.0), ROOM, &m), (Some(36), None));
        assert_eq!(grip_size(Place::default(), n, row, (0.0, 30.0), ROOM, &m), (None, Some(36)));
        // never past the room
        assert_eq!(grip_size(Place::default(), e, row, (5000.0, 0.0), ROOM, &m), (Some(1904), None));
        // at the bottom's left end: one end moves
        assert_eq!(
            grip_size(Place::Dock(Edge::Bottom, Along::Start), e, row, (20.0, 0.0), ROOM, &m),
            (Some(153), None)
        );
        // at the left side's middle: wider to the right, taller from both ends
        let col = Rect::new(8, 400, 36, 139);
        let side = Place::Dock(Edge::Left, Along::Center);
        assert_eq!(grip_size(side, e, col, (40.0, 0.0), ROOM, &m), (Some(76), None));
        assert_eq!(grip_size(side, s, col, (0.0, 30.0), ROOM, &m), (None, Some(199)));
        // free: the side follows the pointer, and from the left or the top the other side stays
        let free = Place::Free(500, 300);
        let r = Rect::new(500, 300, 133, 42);
        assert_eq!(grip_size(free, nw, r, (-20.0, -36.0), ROOM, &m), (Some(153), Some(78)));
        assert_eq!(grip_place(free, nw, r, 169, 78), Place::Free(464, 264));
        assert_eq!(grip_place(free, e, r, 169, 42), Place::Free(500, 300));
        assert_eq!(grip_place(free, w, Rect::new(10, 0, 50, 42), 133, 42), Place::Free(0, 0));
        assert_eq!(grip_place(Place::default(), nw, row, 169, 78), Place::default());
    }

    #[test]
    fn the_edge_comes_from_the_pointer_and_stays_until_96_px() {
        let m = m();
        let (aw, ah) = (1920, 1054);
        // the shape a drag lays the pad out in: a column while it holds a side
        let column = |held: Option<Edge>| held.is_some_and(Edge::side);
        let mut held = None;
        let mut changes = vec![];
        let path: Vec<i32> = (0..=300).rev().chain(1..=300).collect();
        for x in path {
            let was = column(held);
            held = drag_edge(held, (x as f64, 500.0), aw, ah, &m);
            if column(held) != was {
                changes.push((x, column(held)));
            }
        }
        // in at 48 px from the left edge, out at 96, once each way
        assert_eq!(changes, vec![(48, true), (96, false)]);
        // trembling at the line never flips it
        let mut held = drag_edge(None, (48.0, 500.0), aw, ah, &m);
        for x in [49.0, 47.0, 50.0, 46.0, 60.0, 95.5] {
            held = drag_edge(held, (x, 500.0), aw, ah, &m);
            assert_eq!(held, Some(Edge::Left), "{x}");
        }
        // the bar's edge counted from the bar: the area's own top
        assert_eq!(drag_edge(None, (900.0, 30.0), aw, ah, &m), Some(Edge::Top));
    }

    #[test]
    fn a_press_moved_6_px_is_a_drag_and_before_it_a_click() {
        // from a cell: 5 px is still a click, and the click chooses it
        let mut g = Gesture::press(Hit::Item(1), (300.0, 20.0));
        assert_eq!(g.moved((303.0, 24.0)), None);
        assert_eq!(g.released(Hit::Item(1)), Click::Choose(1));
        // past 6 px it is a drag of the pad, once, and its release brings nothing back
        let mut g = Gesture::press(Hit::Item(1), (300.0, 20.0));
        assert_eq!(g.moved((304.0, 24.5)), Some(Grab::Move));
        assert_eq!(g.moved((280.0, 10.0)), None);
        assert_eq!(g.released(Hit::Item(1)), Click::Nothing);
        // the band, the handle, hide and an icon move the pad too; a grip sizes it
        for what in [Hit::Handle, Hit::Hide, Hit::Item(0), Hit::Nothing] {
            assert_eq!(Gesture::press(what, (0.0, 0.0)).moved((6.0, 0.0)), Some(Grab::Move), "{what:?}");
        }
        let nw = Sides { x: -1, y: -1 };
        assert_eq!(Gesture::press(Hit::Grip(nw), (0.0, 0.0)).moved((0.0, -7.0)), Some(Grab::Grip(nw)));
        // a list's row never moves the pad; let go on it, its window comes back
        let mut g = Gesture::press(Hit::Row(2), (0.0, 0.0));
        assert_eq!(g.moved((30.0, 0.0)), None);
        assert_eq!(g.released(Hit::Row(2)), Click::Row(2));
        assert_eq!(g.released(Hit::Row(1)), Click::Nothing);
        // hide's click hides; a press let go elsewhere is nothing
        assert_eq!(Gesture::press(Hit::Hide, (0.0, 0.0)).released(Hit::Hide), Click::Hide);
        assert_eq!(Gesture::press(Hit::Item(0), (0.0, 0.0)).released(Hit::Item(1)), Click::Nothing);
        assert_eq!(Gesture::press(Hit::Handle, (0.0, 0.0)).released(Hit::Handle), Click::Nothing);
    }

    #[test]
    fn keys_move_through_the_grid() {
        // five cells, three a row: 0 1 2 / 3 4
        assert_eq!(key(Key::Left, 2, 5, 3), KeyAct::Pick(1));
        assert_eq!(key(Key::Left, 0, 5, 3), KeyAct::Pick(0));
        assert_eq!(key(Key::Left, 3, 5, 3), KeyAct::Pick(2));
        assert_eq!(key(Key::Right, 2, 5, 3), KeyAct::Pick(3));
        assert_eq!(key(Key::Right, 4, 5, 3), KeyAct::Pick(4));
        assert_eq!(key(Key::Tab, 0, 5, 3), KeyAct::Pick(1));
        assert_eq!(key(Key::Down, 0, 5, 3), KeyAct::Pick(3));
        assert_eq!(key(Key::Down, 1, 5, 3), KeyAct::Pick(4));
        // into a shorter last row: its last cell
        assert_eq!(key(Key::Down, 2, 5, 3), KeyAct::Pick(4));
        // the last row and the first stay where they are
        assert_eq!(key(Key::Down, 3, 5, 3), KeyAct::Pick(3));
        assert_eq!(key(Key::Down, 4, 5, 3), KeyAct::Pick(4));
        assert_eq!(key(Key::Up, 4, 5, 3), KeyAct::Pick(1));
        assert_eq!(key(Key::Up, 3, 5, 3), KeyAct::Pick(0));
        assert_eq!(key(Key::Up, 2, 5, 3), KeyAct::Pick(2));
        // a row: Up and Down stay; a column: they move one
        assert_eq!(key(Key::Down, 1, 3, 3), KeyAct::Pick(1));
        assert_eq!(key(Key::Down, 1, 3, 1), KeyAct::Pick(2));
        assert_eq!(key(Key::Up, 1, 3, 1), KeyAct::Pick(0));
        assert_eq!(key(Key::Home, 4, 5, 3), KeyAct::Pick(0));
        assert_eq!(key(Key::End, 0, 5, 3), KeyAct::Pick(4));
        // Enter chooses: the window back, or a group's list
        assert_eq!(key(Key::Enter, 1, 5, 3), KeyAct::Choose(1));
        assert_eq!(key(Key::Enter, 9, 5, 3), KeyAct::Choose(4));
        assert_eq!(key(Key::Digit(2), 0, 5, 3), KeyAct::Choose(1));
        assert_eq!(key(Key::Digit(8), 0, 5, 3), KeyAct::Nothing);
        assert_eq!(key(Key::Escape, 0, 5, 3), KeyAct::Leave);
        assert_eq!(key(Key::Escape, 0, 0, 3), KeyAct::Leave);
        assert_eq!(key(Key::Enter, 0, 0, 3), KeyAct::Nothing);
    }

    #[test]
    fn keysyms_name_the_keys_whatever_the_layout() {
        // Left, Return, KP_Enter, space, Escape, Tab, 2, h, l, k, j
        assert_eq!(Key::of_sym(0xff51), Some(Key::Left));
        assert_eq!(Key::of_sym(0xff0d), Some(Key::Enter));
        assert_eq!(Key::of_sym(0xff8d), Some(Key::Enter));
        assert_eq!(Key::of_sym(0x20), Some(Key::Enter));
        assert_eq!(Key::of_sym(0xff1b), Some(Key::Escape));
        assert_eq!(Key::of_sym(0xff09), Some(Key::Tab));
        assert_eq!(Key::of_sym(0x32), Some(Key::Digit(2)));
        assert_eq!(Key::of_sym(0x30), None);
        assert_eq!(Key::of_sym(0x68), Some(Key::Left));
        assert_eq!(Key::of_sym(0x6c), Some(Key::Right));
        assert_eq!(Key::of_sym(0x6b), Some(Key::Up));
        assert_eq!(Key::of_sym(0x6a), Some(Key::Down));
        assert_eq!(Key::of_sym(0xff50), Some(Key::Home));
        assert_eq!(Key::of_sym(0xff57), Some(Key::End));
        assert_eq!(Key::of_sym(0x61), None);
        // without a keymap: evdev positions on a US keyboard
        assert_eq!(Key::of_evdev(105), Some(Key::Left));
        assert_eq!(Key::of_evdev(28), Some(Key::Enter));
        assert_eq!(Key::of_evdev(3), Some(Key::Digit(2)));
        assert_eq!(Key::of_evdev(10), Some(Key::Digit(9)));
        assert_eq!(Key::of_evdev(102), Some(Key::Home));
        assert_eq!(Key::of_evdev(11), None);
    }

    #[test]
    fn the_tree_gives_the_minimized_windows_oldest_first() {
        let tree: Value = serde_json::from_str(
            r#"{"type":"root","nodes":[
              {"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","nodes":[],"floating_nodes":[
                {"type":"floating_con","id":10,"app_id":"foot","name":"~/projects/spark","marks":["_spark-shell.min.FB.10"]},
                {"type":"floating_con","id":12,"app_id":"spark-dialog","name":"spark","marks":[]},
                {"type":"floating_con","id":14,"app_id":null,"window_properties":{"class":"Steam"},"name":"Steam","marks":["x","_spark-shell.min.tiled.14"]}
              ]}]},
              {"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","name":"1","nodes":[],"floating_nodes":[]}]}
            ]}"#,
        )
        .unwrap();
        assert_eq!(
            minimized(&tree),
            vec![
                Win {
                    id: 10,
                    app: "foot".into(),
                    title: "~/projects/spark".into()
                },
                Win {
                    id: 14,
                    app: "Steam".into(),
                    title: "Steam".into()
                },
            ]
        );
        assert_eq!(minimized(&serde_json::json!({"type":"root","nodes":[]})), vec![]);
    }

    #[test]
    fn the_catalog_gives_icons_by_id_and_class() {
        let cat = serde_json::json!([
            {"id":"foot.desktop","wm_class":"","icon":"/s/icons/24/a.png"},
            {"id":"org.mozilla.firefox.desktop","wm_class":"firefox","icon":"/s/icons/24/b.png"},
            {"id":"x.desktop","wm_class":"X","icon":""}
        ]);
        assert_eq!(
            icon_paths(&cat),
            vec![
                ("foot".into(), "/s/icons/24/a.png".into()),
                ("org.mozilla.firefox".into(), "/s/icons/24/b.png".into()),
                ("firefox".into(), "/s/icons/24/b.png".into()),
            ]
        );
    }

    #[test]
    fn the_dialog_wears_sparks_mark_by_its_ground_at_the_size_or_above() {
        // spark-shell's theme_is_dark: luminance under half
        assert!(dark_ground(0x28, 0x2a, 0x38), "tokyonight-night's surface");
        assert!(!dark_ground(0xf0, 0xeb, 0xdb), "solarized-light's");
        assert!(!dark_ground(0xeb, 0xeb, 0xec), "the pad's own default");
        assert!(dark_ground(127, 127, 127) && !dark_ground(128, 128, 128), "the line at half");
        // the PNG nearest the icon at or above it; past the largest, the SVG at the size
        assert_eq!(mark_file(true, Metrics::for_text(16.0).icon), "favicon-26.png");
        assert_eq!(mark_file(false, 24), "favicon-light-26.png");
        assert_eq!(mark_file(true, 18), "favicon-19.png");
        assert_eq!(mark_file(true, 16), "favicon-16.png");
        assert_eq!(mark_file(false, 12), "favicon-light-16.png");
        assert_eq!(mark_file(true, 26), "favicon-26.png");
        assert_eq!(mark_file(true, 27), "favicon.svg");
        assert_eq!(mark_file(false, 48), "favicon-light.svg");
        assert_eq!(icon_key(DIALOG), "spark-dialog");
    }

    #[test]
    fn metrics_scale_with_the_text() {
        assert_eq!(Metrics::for_text(16.0).slot_max, 228);
        assert_eq!(Metrics::for_text(24.0).tool, 54);
        assert_eq!(Metrics::for_text(24.0).handle, 9);
        assert_eq!(Metrics::for_text(f64::NAN), Metrics::for_text(16.0));
        // the air, the snapping and the grips stay as they are at any text size
        let big = Metrics::for_text(24.0);
        assert_eq!((big.gap, big.snap, big.unsnap, big.grip), (8, 48, 96, 8));
    }
}
