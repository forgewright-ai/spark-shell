//! The layout in pixels, for a window of the dialog's own: the line, where you are, the list and the keys placed
//! by the pixel in two sizes of text, where the grid (ui.rs) places every symbol in a cell. It draws the frame of
//! every place, and the body of the places redesigned so far: home, what home finds, apps and an app's details
//! beside its list. Any other place keeps its grid rows, laid inside this frame. Pure: the app's state in, drawing
//! steps and the places a click acts out; a painter (paint.rs) draws them, a test reads them.

use crate::app::{App, HintKey, Item, Mode, Talk, View, DESTS, SETTINGS};
use crate::apps::{Action, Page};
use crate::draw::{Rgb, Size, Step};
use crate::grid::Color;
use crate::page::Icon;
use crate::palette::Palette;
use crate::preferences::Spacing;
use crate::scrub::{cells, cut, cut_middle};

/// The text's measures: the cell of the text's own face and where its baseline stands under its line's top,
/// then the same of the smaller face. Every length of the layout is said for a line 20 pixels tall and grows
/// with the line.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Metrics {
    pub cw: f64,
    pub ch: f64,
    pub up: f64,
    pub sw: f64,
    pub sh: f64,
    pub sup: f64,
}

impl Metrics {
    /// The measures the sheets were drawn with: Monaspace at 12 points.
    pub const SHEET: Metrics = Metrics {
        cw: 10.0,
        ch: 20.0,
        up: 16.0,
        sw: 7.0,
        sh: 15.0,
        sup: 12.0,
    };
    /// A length of the sheets, at this text's size, on a whole pixel.
    pub fn px(&self, v: f64) -> f64 {
        (v * self.ch / 20.0).round()
    }
    fn adv(&self, size: Size) -> f64 {
        match size {
            Size::Main => self.cw,
            Size::Small => self.sw,
        }
    }
    fn rise(&self, size: Size) -> f64 {
        match size {
            Size::Main => self.up,
            Size::Small => self.sup,
        }
    }
}

/// What a click does where it lands.
#[derive(Clone, Debug, PartialEq)]
pub enum Target {
    /// A row of the list, by its place among the rows that can be lit.
    Pick(usize),
    /// A key of the key bar.
    Key(HintKey),
    /// A control at the line's end: attach, remove, talk.
    Chip(usize),
    /// The line itself.
    Prompt,
    /// Undo, on the message's line.
    Undo,
    /// A category's heading in the list of apps.
    Head(String),
    /// Home, on the location line.
    Home,
    /// The place above this one, on the location line.
    Back,
    /// An app in the list beside its details: its details come.
    ListApp(String),
    /// A row of the details shown beside the list while the list holds the keys.
    PaneRow(usize),
    /// A value's arrow: the row, and whether it steps the value up.
    Step(usize, bool),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub target: Target,
}

/// An app's picture where it is drawn: its corner, its side, its file.
#[derive(Clone, Debug, PartialEq)]
pub struct IconAt {
    pub x: f64,
    pub y: f64,
    pub side: f64,
    pub file: String,
}

/// The grid rows of a place the layout has not drawn yet: where they are laid, how many cells they are, and the
/// box they are kept inside.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GridBody {
    pub x: f64,
    pub y: f64,
    pub cols: u16,
    pub rows: u16,
    pub clip: (f64, f64, f64, f64),
}

/// How a list was last scrolled: which list it is, how far in pixels, and what that came of: the app's own count
/// of lines, the row lit, the box's height. A list keeps its place from frame to frame by it, so a drag moves the
/// list freely and the lit row is brought into view only when it changes.
#[derive(Clone, Debug, PartialEq)]
pub struct Scrolled {
    pub key: String,
    pub off: f64,
    pub lines: usize,
    pub lit: Option<usize>,
    pub view: f64,
}

/// A list where it is drawn: its box, how far it is scrolled and how far it can be.
#[derive(Clone, Debug, PartialEq)]
pub struct ListBox {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    /// The most it scrolls: nothing where every row is in view.
    pub most: f64,
    pub at: Scrolled,
}

impl ListBox {
    pub fn holds(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Scene {
    pub steps: Vec<Step>,
    pub hits: Vec<Hit>,
    pub icons: Vec<IconAt>,
    /// The list's box: an icon is kept inside it.
    pub icon_clip: (f64, f64, f64, f64),
    pub grid: Option<GridBody>,
    /// The lists drawn in pixels: a drag scrolls the one it starts on.
    pub lists: Vec<ListBox>,
}

impl Scene {
    /// What a click at a point does: the last thing drawn there.
    pub fn hit(&self, x: f64, y: f64) -> Option<&Target> {
        self.hits
            .iter()
            .rev()
            .find(|h| x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)
            .map(|h| &h.target)
    }
}

/// The body the layout draws for the place shown.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Home,
    Apps,
    /// The place's grid rows, inside the frame.
    Grid,
}

/// Which body the place shown gets: home and apps their rows in pixels, where every row is one the layout
/// knows; a question's page, a transition and every other place the grid's.
pub fn kind(app: &App) -> Kind {
    match app.view {
        View::Home | View::Apps => kind_of(app, &app.list_items()),
        _ => Kind::Grid,
    }
}

/// The same, of the items already read.
fn kind_of(app: &App, items: &[Item]) -> Kind {
    if app.motion.is_some() || matches!(app.mode, Mode::Confirm(_)) {
        return Kind::Grid;
    }
    match app.view {
        View::Home if items.iter().all(known) => Kind::Home,
        View::Apps if items.iter().all(known) => Kind::Apps,
        _ => Kind::Grid,
    }
}

fn known(it: &Item) -> bool {
    matches!(
        it,
        Item::Dest(_)
            | Item::Heading(_)
            | Item::Blank
            | Item::Apps(_)
            | Item::Hit(_)
            | Item::Row(..)
            | Item::More(..)
            | Item::Ask
            | Item::Setting(_)
            | Item::Step(..)
            | Item::Title(_)
            | Item::Text(..)
            | Item::Note(_)
    )
}

/// The frame's lengths, as the sheets have them.
const INSET: f64 = 24.0;
const TEXT: f64 = 48.0;
const LINE_TOP: f64 = 24.0;
const UNDER: f64 = 55.0;
const HEAD: f64 = 72.0;
const PATH_BASE: f64 = 82.0;
const PATH_RULE: f64 = 96.0;
const FOOT: f64 = 48.0;
const FOOT_LINE: f64 = 26.0;
const STATUS: f64 = 28.0;
/// A window narrower than this shows an app's details as a page, not beside the list.
const SPLIT_MIN: f64 = 600.0;

/// Whether a window holds the frame at all: the line, a list and the keys. A smaller one is the grid's, which says
/// to make the window larger.
pub fn fits(m: &Metrics, w: f64, h: f64) -> bool {
    w >= crate::app::MIN_WIDTH as f64 * m.cw && h >= crate::app::MIN_HEIGHT as f64 * m.ch
}

/// Whether a window this wide holds an app's details beside the list.
pub fn splits(m: &Metrics, w: f64) -> bool {
    w >= m.px(SPLIT_MIN)
}

/// The size in cells the app is told, so its own counts fit what is drawn: the columns the grid rows have, and a
/// list of as many rows as the body shows, under the grid's head and over its foot.
pub fn size(app: &App, m: &Metrics, w: f64, h: f64) -> (u16, u16) {
    let k = kind(app);
    let g = Geo::new(app, m, w, h, k);
    let rows = match k {
        Kind::Grid => g.grid_rows(m),
        Kind::Home => ((g.bottom - g.top) / m.px(44.0)) as u16,
        Kind::Apps => ((g.bottom - g.top) / app_row(m, app.apps.spacing)) as u16,
    };
    (g.grid_cols(m), rows.max(1) + crate::ui::head(app).content + crate::ui::BOTTOM)
}

/// An app's row: its height by the app spacing setting, the sheets' with rows.
fn app_row(m: &Metrics, s: Spacing) -> f64 {
    m.px(match s {
        Spacing::None => 40.0,
        Spacing::Groups => 46.0,
        Spacing::Rows => 52.0,
    })
}

/// Where the frame's parts stand.
struct Geo {
    w: f64,
    inset: f64,
    top: f64,
    bottom: f64,
    foot: f64,
    path: bool,
    status: bool,
    keys: Keys,
}

impl Geo {
    fn new(app: &App, m: &Metrics, w: f64, h: f64, k: Kind) -> Geo {
        let inset = m.px(INSET);
        let keys = Keys::new(app, m, w - 2.0 * inset);
        let foot = h - m.px(FOOT) - if keys.lines > 1 { m.px(FOOT_LINE) } else { 0.0 };
        let path = app.view != View::Home;
        // the grid's rows always keep the message's line, as the grid kept its status row: a list of files says
        // the lit file there. The rows in pixels give it room only while there is something to say
        let status = k == Kind::Grid || message(app, k).is_some();
        let top = if path { m.px(PATH_RULE) + 1.0 } else { m.px(HEAD) };
        let bottom = (foot - if status { m.px(STATUS) } else { 0.0 }).max(top);
        Geo {
            w,
            inset,
            top,
            bottom,
            foot,
            path,
            status,
            keys,
        }
    }
    /// The grid rows start two cells left of the frame's edge, so their first text column stands on it.
    fn grid_x(&self, m: &Metrics) -> f64 {
        self.inset - 2.0 * m.cw
    }
    /// Every column that starts inside the window: 60 at the window's start size, as the grid had there, which
    /// two panes of files need. The last one may hang past the window's edge: it is the rows' own air.
    fn grid_cols(&self, m: &Metrics) -> u16 {
        ((self.w - self.grid_x(m)) / m.cw).ceil().max(1.0) as u16
    }
    fn grid_top(&self, m: &Metrics) -> f64 {
        self.top + m.px(4.0)
    }
    fn grid_rows(&self, m: &Metrics) -> u16 {
        ((self.bottom - self.grid_top(m)) / m.ch).floor().max(1.0) as u16
    }
}

/// The colors as the painter takes them.
#[derive(Clone, Copy)]
struct Tones {
    ground: Rgb,
    ink: Rgb,
    muted: Rgb,
    accent: Rgb,
    lit: Rgb,
    band: Rgb,
    alarm: Rgb,
}

fn rgb(c: Color, or: Rgb) -> Rgb {
    match c {
        Color::Rgb(r, g, b) => [r, g, b],
        _ => or,
    }
}

struct Pen<'a> {
    m: &'a Metrics,
    t: Tones,
    steps: Vec<Step>,
    hits: Vec<Hit>,
    icons: Vec<IconAt>,
    /// How the lists were scrolled in the frame before, and the lists of this one.
    was: &'a [Scrolled],
    lists: Vec<ListBox>,
}

impl Pen<'_> {
    fn fill(&mut self, x: f64, y: f64, w: f64, h: f64, color: Rgb) {
        if w > 0.0 && h > 0.0 {
            self.steps.push(Step::Fill { x, y, w, h, color });
        }
    }
    fn width(&self, s: &str, size: Size) -> f64 {
        cells(s) as f64 * self.m.adv(size)
    }
    /// Words with their baseline at `base`; their width.
    fn text(&mut self, x: f64, base: f64, s: &str, size: Size, color: Rgb, bold: bool) -> f64 {
        if s.is_empty() {
            return 0.0;
        }
        self.steps.push(Step::Text {
            x: x.round(),
            y: (base - self.m.rise(size)).round(),
            text: s.to_string(),
            size,
            color,
            bold,
        });
        self.width(s, size)
    }
    /// Words that end at `right`; their width.
    fn text_end(&mut self, right: f64, base: f64, s: &str, size: Size, color: Rgb, bold: bool) -> f64 {
        let w = self.width(s, size);
        self.text(right - w, base, s, size, color, bold);
        w
    }
    /// Words cut to a room in pixels, an ellipsis where they are cut.
    fn fit(&self, s: &str, size: Size, room: f64) -> String {
        let n = (room / self.m.adv(size)).floor().max(0.0) as usize;
        if cells(s) > n {
            format!("{}\u{2026}", cut(s, n.saturating_sub(1)))
        } else {
            s.to_string()
        }
    }
    fn hit(&mut self, x: f64, y: f64, w: f64, h: f64, target: Target) {
        self.hits.push(Hit { x, y, w, h, target });
    }
    /// An app's picture in a box of `side`, or its letter on a tile.
    fn icon(&mut self, icon: &Icon, x: f64, y: f64, side: f64) {
        match icon {
            Icon::Picture(file) => self.icons.push(IconAt {
                x,
                y,
                side,
                file: file.clone(),
            }),
            Icon::Letter(c) => {
                self.fill(x, y, side, side, self.t.band);
                let (m, ink) = (*self.m, self.t.ink);
                self.steps.push(Step::Text {
                    x: (x + (side - m.cw) / 2.0).round(),
                    y: (y + (side - m.ch) / 2.0).round(),
                    text: c.to_string(),
                    size: Size::Main,
                    color: ink,
                    bold: false,
                });
            }
        }
    }
}

/// The frame and the body of the place shown, for a window of `w` by `h` pixels. `was` is how the lists of the
/// frame before were scrolled (Scene::lists, each one's `at`): nothing for a first frame.
pub fn build(app: &App, pal: &Palette, m: &Metrics, w: f64, h: f64, was: &[Scrolled]) -> Scene {
    // the items read once: a search behind them is run once a frame
    let items = app.list_items();
    let k = kind_of(app, &items);
    let g = Geo::new(app, m, w, h, k);
    let ink = rgb(pal.fg, [0xaa; 3]);
    let mut pen = Pen {
        m,
        t: Tones {
            ground: rgb(pal.surface, [0x1f; 3]),
            ink,
            muted: rgb(pal.muted, ink),
            accent: rgb(pal.accent, ink),
            lit: rgb(pal.lit, [0x44; 3]),
            band: rgb(pal.band, [0x44; 3]),
            alarm: rgb(pal.alarm, ink),
        },
        steps: vec![],
        hits: vec![],
        icons: vec![],
        was,
        lists: vec![],
    };
    line(app, &mut pen, &g);
    if g.path {
        path(app, &mut pen, &g, &items);
    }
    let mut scene = Scene {
        icon_clip: (g.inset, g.top, w - 2.0 * g.inset, g.bottom - g.top),
        ..Scene::default()
    };
    match k {
        Kind::Grid => {
            scene.grid = Some(GridBody {
                x: g.grid_x(m),
                y: g.grid_top(m),
                cols: g.grid_cols(m),
                rows: g.grid_rows(m),
                clip: (0.0, g.top, w, g.bottom - g.top),
            });
        }
        Kind::Home => home(app, &mut pen, &g, &items),
        Kind::Apps => apps(app, &mut pen, &g, &items),
    }
    if g.status {
        status(app, &mut pen, &g, k);
    }
    g.keys.draw(&mut pen, &g);
    scene.steps = pen.steps;
    scene.hits = pen.hits;
    scene.icons = pen.icons;
    scene.lists = pen.lists;
    scene
}

// ---------------------------------------------------------------- the line

/// The symbol standing at a count of cells in a row of the draft.
fn symbol_at(row: &str, at: usize) -> Option<String> {
    use unicode_segmentation::UnicodeSegmentation;
    let mut x = 0;
    for g in row.graphemes(true) {
        let w = cells(g);
        if w > 0 && x == at {
            return Some(g.to_string());
        }
        x += w;
    }
    None
}

/// The line: the sign, the draft or what the empty line takes, the controls at its end, the cursor, and the rule
/// under it, in the accent while the line holds the keys. The march stands over its end while spark thinks.
fn line(app: &App, pen: &mut Pen, g: &Geo) {
    let m = *pen.m;
    let t = pen.t;
    let (top, base) = (m.px(LINE_TOP), m.px(LINE_TOP) + m.up);
    let tx = m.px(TEXT);
    let right = g.w - g.inset;
    pen.text(g.inset, base, crate::ui::PROMPT, Size::Main, t.accent, false);
    // the controls, from the line's end backward: talk, remove, attach or the attached file's name
    let chips = app.chips();
    let mut x = right;
    let control = |pen: &mut Pen, x: &mut f64, words: &str, id: usize, on: bool, quiet: bool, live: bool| {
        let w = pen.width(words, Size::Small);
        let (pad, x0) = (m.px(6.0), *x - w);
        let focus = app.chip_focus == Some(id);
        if focus {
            pen.fill(x0 - pad, top, w + 2.0 * pad, m.ch, t.lit);
        }
        let color = if quiet && !on { t.muted } else { t.accent };
        pen.text(x0, base, words, Size::Small, color, focus || on);
        if live {
            pen.hit(x0 - pad, top - m.px(6.0), w + 2.0 * pad, m.ch + m.px(12.0), Target::Chip(id));
        }
        *x = x0 - m.px(20.0);
    };
    if app.cfg.talk && app.talk == Talk::Click {
        let listening = app.mode == Mode::Listening;
        let live = chips.contains(&3);
        control(pen, &mut x, if listening { "cancel" } else { "talk" }, 3, listening, !live, live);
    }
    if chips.contains(&4) {
        control(pen, &mut x, "remove", 4, false, false, true);
    }
    if chips.contains(&0) {
        let name = app.attachment.as_deref().map(|a| cut_middle(a.rsplit('/').next().unwrap_or(""), 16));
        control(pen, &mut x, name.as_deref().unwrap_or("attach"), 0, name.is_some(), false, true);
    }
    // the draft: the row the cursor is on, each symbol in its cell so the cursor stands on it
    let room = ((x - tx) / m.cw).floor().max(crate::ui::DRAFT_MIN as f64) as usize;
    let masked = matches!(&app.mode, Mode::Ask { masked: true, .. }) || matches!(&app.mode, Mode::Pair { kind, .. } if kind == "pin" || kind == "passkey");
    let shown: String = if masked {
        "\u{2022}".repeat(app.input.chars().count())
    } else {
        app.input.clone()
    };
    let (rows, (cr, cc)) = crate::ui::draft_rows(&shown, app.cursor, room.saturating_sub(1));
    let empty = app.input.is_empty() && (app.mode == Mode::Normal || app.prompt_form());
    let row = if empty {
        app.placeholder().to_string()
    } else {
        rows.get(cr).cloned().unwrap_or_default()
    };
    if !empty && app.name_is_lit() {
        pen.fill(tx, top, pen.width(&row, Size::Main), m.ch, t.lit);
    }
    symbols(pen, tx, top, &row, if empty { t.muted } else { t.ink });
    if !empty {
        // more of the draft above or under the row shown
        let mark = match (cr > 0, cr + 1 < rows.len()) {
            (true, _) => crate::ui::ABOVE,
            (false, true) => crate::ui::BELOW,
            _ => "",
        };
        pen.text(tx + room as f64 * m.cw, base, mark, Size::Main, t.muted, false);
    }
    let typing = !list_focus(app) && app.chip_focus.is_none();
    if typing {
        let cx = tx + cc as f64 * m.cw;
        if app.window_focused {
            pen.fill(cx, top, m.cw, m.ch, if empty { t.muted } else { t.ink });
            if let Some(s) = symbol_at(&row, cc) {
                symbols(pen, cx, top, &s, t.ground);
            }
        } else {
            let c = t.ink;
            pen.fill(cx, top, m.cw, 1.0, c);
            pen.fill(cx, top + m.ch - 1.0, m.cw, 1.0, c);
            pen.fill(cx, top, 1.0, m.ch, c);
            pen.fill(cx + m.cw - 1.0, top, 1.0, m.ch, c);
        }
    }
    let under = m.px(UNDER);
    if typing {
        pen.fill(g.inset, under, g.w - 2.0 * g.inset, 2.0, t.accent);
    } else {
        pen.fill(g.inset, under + 1.0, g.w - 2.0 * g.inset, 1.0, t.lit);
    }
    if app.cfg.progress && app.thinking() {
        let bar = crate::progress::bar(app.work(), &app.glyphs, app.frame);
        pen.text_end(right, m.px(4.0) + m.sup, &bar, Size::Small, t.accent, false);
    }
    // the line's own place, under its controls': the pointer is a text's there
    pen.hits.insert(
        0,
        Hit {
            x: g.inset,
            y: m.px(12.0),
            w: (x - g.inset).max(0.0),
            h: under - m.px(12.0),
            target: Target::Prompt,
        },
    );
}

/// Words drawn a symbol a cell, as the grid draws them: a text that is typed into keeps its cells.
fn symbols(pen: &mut Pen, x: f64, y: f64, text: &str, color: Rgb) {
    use unicode_segmentation::UnicodeSegmentation;
    let mut k = 0;
    for g in text.graphemes(true) {
        let w = cells(g);
        if w == 0 {
            continue;
        }
        if !g.trim().is_empty() {
            pen.steps.push(Step::Symbol {
                x: x + k as f64 * pen.m.cw,
                y,
                cells: w as u16,
                text: g.to_string(),
                color,
                bold: false,
            });
        }
        k += w;
    }
}

/// Where you are, under the line: home, the place, and what the place shows now. Home and the place above are
/// targets; the last name is where you are. The count of the list stands at the line's end.
fn path(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let m = *pen.m;
    let t = pen.t;
    let base = m.px(PATH_BASE);
    let apps = |n: usize| format!("{} {}", n, if n == 1 { "app" } else { "apps" });
    let launches = |l: &crate::apps::Line| matches!(l.action, Some(Action::Launch(_)));
    // an app's details beside the list: the list is the place still, and its count stands
    let beside = app.view == View::Apps && app.apps.pane && splits(&m, g.w) && app.apps.subject().is_some() && app.apps.root_lists();
    let count = match (&app.view, &app.apps.page) {
        (View::Apps, Page::List | Page::Hidden) => apps(items.iter().filter(|it| matches!(it, Item::Apps(l) if launches(l))).count()),
        (View::Apps, _) if beside => {
            let (root, query) = app
                .apps
                .root()
                .map(|(p, n)| (p.clone(), n.query.clone()))
                .unwrap_or((Page::List, String::new()));
            apps(app.apps.lines_of(&root, 60, &query, 0).iter().filter(|l| launches(l)).count())
        }
        _ => String::new(),
    };
    let right = g.w - g.inset;
    let end = right - pen.text_end(right, base, &count, Size::Small, t.muted, false) - if count.is_empty() { 0.0 } else { m.px(16.0) };
    let (place, sub) = (app.title(), if beside { String::new() } else { app.subtitle() });
    let mut names = vec![("home".to_string(), Some(Target::Home))];
    if sub.trim().is_empty() {
        names.push((place, None));
    } else {
        names.push((place, Some(Target::Back)));
        names.push((sub, None));
    }
    let mut x = g.inset;
    let last = names.len() - 1;
    for (k, (name, target)) in names.into_iter().enumerate() {
        // the last name is cut where the count starts; an earlier one is short
        let name = pen.fit(&name, Size::Small, (end - x).max(0.0));
        let color = if target.is_some() && app.can_go_back() { t.accent } else { t.ink };
        let w = pen.text(x, base, &name, Size::Small, color, false);
        if let Some(target) = target.filter(|_| app.can_go_back()) {
            pen.hit(x - m.px(4.0), base - m.sup - m.px(6.0), w + m.px(8.0), m.sh + m.px(10.0), target);
        }
        x += w;
        if k < last {
            x += pen.text(x, base, " / ", Size::Small, t.muted, false);
        }
    }
    pen.fill(g.inset, m.px(PATH_RULE), g.w - 2.0 * g.inset, 1.0, t.lit);
}

// ---------------------------------------------------------------- the message and the keys

/// What the message's line says now, as the grid's status row decides it: an app opening or files under way,
/// the reply, else a note. The line of the lit object is said for home's finds and for a place's grid rows;
/// a list of apps says it in the row itself.
fn message(app: &App, k: Kind) -> Option<Message> {
    use crate::reply::Mark;
    if let (Some((_, op)), Some(since)) = (&app.apps.pending, app.apps.pending_since) {
        if op == "launch" && since.elapsed() >= crate::ui::LAUNCH_FELT && !app.apps.pending_name.is_empty() {
            return Some(Message::march(format!("opening {}", app.apps.pending_name)));
        }
    }
    if let Some(b) = &app.files.batch {
        if app.running.is_some() && b.current.is_some() && b.since.elapsed() >= crate::ui::LAUNCH_FELT {
            return Some(Message::march(b.march()));
        }
    }
    let Some(r) = &app.reply else {
        let note = app.target_label().or_else(|| if k == Kind::Apps { None } else { app.selected_line() })?;
        return Some(Message {
            sign: Sign::None,
            text: note,
            muted: true,
            undo: false,
        });
    };
    if (r.mark == Mark::Answer && app.view == View::Conversation) || r.text.is_empty() {
        return None;
    }
    Some(Message {
        sign: match r.mark {
            Mark::Done => Sign::Done,
            Mark::Refused => Sign::Refused,
            _ => Sign::None,
        },
        text: r.text.clone(),
        muted: matches!(r.mark, Mark::Note | Mark::Answer),
        undo: r.undo && (app.undo.is_some() || app.apps.undo.is_some()),
    })
}

enum Sign {
    None,
    Done,
    Refused,
    March,
}

struct Message {
    sign: Sign,
    text: String,
    muted: bool,
    undo: bool,
}

impl Message {
    fn march(text: String) -> Message {
        Message {
            sign: Sign::March,
            text,
            muted: true,
            undo: false,
        }
    }
}

/// The message's line, over the keys' rule: its sign at the frame's edge, its words at the text's, Undo at its end.
fn status(app: &App, pen: &mut Pen, g: &Geo, k: Kind) {
    let Some(msg) = message(app, k) else { return };
    let m = *pen.m;
    let t = pen.t;
    let base = g.foot - m.px(10.0);
    let mut right = g.w - g.inset;
    if msg.undo {
        let w = pen.text_end(right, base, "undo", Size::Small, t.accent, false);
        pen.hit(right - w - m.px(6.0), g.foot - m.px(STATUS), w + m.px(12.0), m.px(STATUS), Target::Undo);
        right -= w + m.px(16.0);
    }
    let mut x = m.px(TEXT);
    match msg.sign {
        Sign::Done => {
            pen.text(g.inset, base, crate::ui::CHECK, Size::Small, t.accent, false);
        }
        Sign::Refused => {
            pen.text(g.inset, base, crate::ui::CROSS, Size::Small, t.alarm, false);
        }
        Sign::March => {
            let bar = crate::progress::bar(crate::progress::Work::March, &app.glyphs, app.frame);
            x = g.inset + pen.text(g.inset, base, &bar, Size::Small, t.muted, false) + m.sw;
        }
        Sign::None => {}
    }
    let words = pen.fit(&msg.text, Size::Small, right - x);
    pen.text(x, base, &words, Size::Small, if msg.muted { t.muted } else { t.ink }, false);
}

/// The key bar: each group its words and its key in a chip, Esc's first; a second line where one is too short.
struct Keys {
    groups: Vec<(f64, crate::ui::KeyGroup)>,
    lines: usize,
    room: f64,
}

impl Keys {
    fn new(app: &App, m: &Metrics, room: f64) -> Keys {
        let groups: Vec<(f64, crate::ui::KeyGroup)> = crate::ui::key_groups(app, app.preview_pages.max(1))
            .into_iter()
            .map(|parts| (Keys::span(m, &parts), parts))
            .collect();
        let mut x = 0.0;
        let mut lines = 1;
        for (w, _) in &groups {
            if x + w > room {
                if *w <= room {
                    lines = 2;
                }
                break;
            }
            x += w + m.px(20.0);
        }
        Keys { groups, lines, room }
    }
    /// A group's width: words, then a chip of the key's words with its air.
    fn span(m: &Metrics, parts: &crate::ui::KeyGroup) -> f64 {
        parts
            .iter()
            .map(|(t, key, _)| {
                if *key {
                    cells(t) as f64 * m.sw + m.px(16.0)
                } else {
                    cells(t.trim_end()) as f64 * m.sw + m.px(8.0)
                }
            })
            .sum()
    }
    fn draw(&self, pen: &mut Pen, g: &Geo) {
        let m = *pen.m;
        let t = pen.t;
        pen.fill(g.inset, g.foot, g.w - 2.0 * g.inset, 1.0, t.lit);
        let (left, right) = (g.inset, g.inset + self.room);
        let last = g.foot + m.px(29.0) + if self.lines > 1 { m.px(FOOT_LINE) } else { 0.0 };
        let (mut x, mut base) = (left, g.foot + m.px(29.0));
        for (width, parts) in &self.groups {
            if x + width > right && base < last && *width <= self.room {
                x = left;
                base = last;
            }
            if x + width > right {
                // words that explain can end at a word; an action is shown whole or left to help
                if parts.iter().all(|(_, key, _)| !key) {
                    let text: String = parts.iter().map(|(t, ..)| t.as_str()).collect();
                    let text = pen.fit(text.trim_end(), Size::Small, right - x);
                    pen.text(x, base, &text, Size::Small, t.ink, false);
                }
                continue;
            }
            let start = x;
            for (text, key, actions) in parts {
                let from = x;
                if *key {
                    let w = pen.width(text, Size::Small) + m.px(16.0);
                    pen.fill(x, base - m.px(15.0), w, m.px(21.0), t.lit);
                    pen.text(x + m.px(8.0), base, text, Size::Small, t.ink, false);
                    x += w;
                } else {
                    let words = text.trim_end().to_lowercase();
                    x += pen.text(x, base, &words, Size::Small, t.ink, false) + m.px(8.0);
                }
                let n = actions.len() as f64;
                for (i, action) in actions.iter().enumerate() {
                    let a = if actions.len() == 1 { start } else { from + (x - from) * i as f64 / n };
                    let b = from + (x - from) * (i + 1) as f64 / n;
                    pen.hit(a, base - m.px(21.0), b - a, m.px(33.0), Target::Key(*action));
                }
            }
            x += m.px(20.0);
        }
    }
}

// ---------------------------------------------------------------- the rows

/// What stands at a row's end.
#[derive(Clone, Debug, PartialEq)]
enum End {
    None,
    Words(String),
    /// A switch: on, or off.
    Switch(bool),
    /// A value between its arrows: the value, whether there is a lesser and a greater one, the room of its widest.
    Stepper(String, bool, bool, usize),
}

#[derive(Clone, Debug, PartialEq)]
enum K {
    Gap(f64),
    Rule,
    /// A group's heading; its count; the category a click on it shows alone.
    Head(String, Option<String>, Option<String>),
    /// A place of home: its name, and what it holds now.
    Dest(String, String),
    /// An app in the list of apps: its name over what it is.
    App(String, String, Option<Icon>, String),
    /// A row of one line: a picture, a sign, a sample, its name, the words beside it, what stands at its end, an
    /// arrow, a key.
    One {
        icon: Option<Icon>,
        sign: &'static str,
        swatch: Vec<Rgb>,
        name: String,
        muted: bool,
        words: String,
        end: End,
        tail: bool,
        key: String,
    },
    /// Words that open nothing: their size, whether they are muted, bold.
    Words(String, Size, bool, bool),
    /// A fact: its label and its value on one line.
    Fact(String, String),
    /// The app a page is about: its picture, its name, what it is.
    Identity(Option<Icon>, String, Vec<String>),
}

#[derive(Clone, Debug, PartialEq)]
struct Row {
    h: f64,
    /// Its place among the rows that can be lit.
    pick: Option<usize>,
    k: K,
}

/// How a list's rows are made and drawn.
#[derive(Clone, Copy)]
struct Shape {
    /// An app's row in two lines, as the list of apps has it; in one, as home's finds do.
    two: bool,
    /// A one-line row's height, in the sheets' pixels.
    one: f64,
    /// No count beside a heading, and no target on it: the list beside the details.
    narrow: bool,
    /// The rows take no click of their own (the list beside the details): a click on an app shows its details.
    still: bool,
    /// A row's words start this far inside its fill, in the sheets' pixels: 24 in a list, 12 in the details
    /// beside one.
    pad: f64,
}

/// What an app is, beside or under its name: the entry's own word for its kind, else its comment.
fn role(a: &crate::apps::Entry) -> String {
    let r = if !a.generic_name.is_empty() {
        a.generic_name.clone()
    } else {
        let c = a.description.trim_end_matches('.');
        if c.eq_ignore_ascii_case(&a.name) {
            String::new()
        } else {
            c.to_string()
        }
    };
    r.to_lowercase()
}

/// A provider's row as a row of one line.
fn of_row(r: &crate::model::Row) -> K {
    let sign: &'static str = match r.sign.as_str() {
        "dot" => "dot",
        "ring" => "ring",
        "check" => "check",
        "cross" => "cross",
        _ => "",
    };
    let end = if let Some(st) = &r.step {
        End::Stepper(st.value().to_string(), st.at > 0, st.at + 1 < st.values.len(), st.width())
    } else if let Some(sw) = &r.switch {
        End::Switch(sw.on)
    } else if r.choice && r.children.is_some() && !r.columns.is_empty() {
        End::Words(r.columns[0].clone())
    } else {
        End::None
    };
    let words = if matches!(end, End::None) {
        r.columns.join(crate::ui::SEP)
    } else {
        String::new()
    };
    K::One {
        icon: None,
        sign,
        swatch: r.swatch.map(|c| vec![c]).unwrap_or_else(|| r.chip.clone()),
        name: if r.id.starts_with("files:") {
            cut_middle(&r.text, 28)
        } else {
            r.text.clone()
        },
        muted: r.muted,
        words,
        end,
        tail: r.children.is_some() && r.text != ".." && !r.id.starts_with("files:"),
        key: r.key.clone().unwrap_or_default(),
    }
}

/// The rows of a list of items: each item the row its kind has, the picks counted as the app counts them.
fn rows_of(app: &App, pen: &Pen, items: &[Item], shape: Shape, room: f64) -> Vec<Row> {
    let m = pen.m;
    let picks: Vec<usize> = items.iter().enumerate().filter(|(_, it)| app.pickable_item(it)).map(|(i, _)| i).collect();
    let pick = |k: usize| picks.iter().position(|p| *p == k);
    let one = m.px(shape.one);
    let mut out: Vec<Row> = vec![];
    let gap = |out: &mut Vec<Row>, h: f64| {
        if !out.is_empty() && !matches!(out.last(), Some(Row { k: K::Gap(_), .. })) {
            out.push(Row { h, pick: None, k: K::Gap(h) });
        }
    };
    let plain = |name: &str, words: String, tail: bool| K::One {
        icon: None,
        sign: "",
        swatch: vec![],
        name: name.to_string(),
        muted: false,
        words,
        end: End::None,
        tail,
        key: String::new(),
    };
    let mut k = 0;
    while k < items.len() {
        let it = &items[k];
        let at = k;
        k += 1;
        let made: Option<(f64, K)> = match it {
            Item::Blank => {
                gap(&mut out, m.px(16.0));
                None
            }
            Item::Heading(h) => Some((m.px(36.0), K::Head(h.clone(), None, None))),
            Item::Dest(d) => {
                let words = app.dest_state(*d).unwrap_or_else(|| DESTS[*d].purpose.to_string());
                Some((m.px(44.0), K::Dest(DESTS[*d].name.to_string(), words)))
            }
            Item::Setting(i) => {
                let (label, name, purpose) = SETTINGS[*i];
                Some((one, plain(name, crate::ui::setting_words(app, label, purpose), false)))
            }
            Item::Step(p, name) => app
                .providers
                .get(*p)
                .and_then(|x| x.tools.iter().find(|t| &t.name == name))
                .map(|t| (one, plain(&crate::app::step_title(&t.title), t.description.clone(), false))),
            Item::More(_, n) => Some((one, plain(&format!("{} more", n), String::new(), true))),
            Item::Ask => {
                let words: String = app.input.split_whitespace().collect::<Vec<_>>().join(" ");
                Some((one, plain("ask spark", words, false)))
            }
            Item::Hit(_) | Item::Row(..) => app.row_ref(it).map(|r| (one, of_row(r))),
            Item::Title(t) => Some((m.px(28.0), K::Words(t.clone(), Size::Main, false, false))),
            Item::Text(t, muted) => Some((m.px(22.0), K::Words(t.clone(), Size::Small, *muted, false))),
            Item::Note(t) => Some((m.px(22.0), K::Words(t.clone(), Size::Small, true, false))),
            Item::Apps(l) => {
                let blank = l.label.is_empty() && l.value.is_empty() && l.action.is_none();
                // an app's row where apps are listed: a list of apps, home's finds. On a page about one app the
                // same action is the page's own row (open)
                let launch = match &l.action {
                    Some(Action::Launch(id)) if shape.two || app.view != View::Apps => app.apps.entry(id),
                    _ => None,
                };
                if blank {
                    gap(&mut out, m.px(12.0));
                    None
                } else if l.heading {
                    let click = (!shape.narrow && app.view == View::Apps && app.apps.page == Page::List).then(|| l.label.clone());
                    Some((m.px(36.0), K::Head(l.label.clone(), None, click)))
                } else if let Some(a) = launch {
                    let name = a.name.to_lowercase();
                    if shape.two {
                        Some((app_row(m, app.apps.spacing), K::App(name, role(a), l.icon.clone(), a.id.clone())))
                    } else {
                        Some((
                            one,
                            K::One {
                                icon: l.icon.clone(),
                                sign: "",
                                swatch: vec![],
                                name,
                                muted: false,
                                words: role(a),
                                end: End::None,
                                tail: false,
                                key: String::new(),
                            },
                        ))
                    }
                } else if l.title {
                    Some((m.px(28.0), K::Words(l.label.clone(), Size::Main, false, true)))
                } else if l.muted {
                    // a note's lines were wrapped for the grid: joined, and wrapped again for this room
                    let mut text = l.label.clone();
                    while let Some(Item::Apps(n)) = items.get(k).filter(|it| matches!(it, Item::Apps(n) if n.muted && !n.heading)) {
                        text = format!("{} {}", text, n.label);
                        k += 1;
                    }
                    let n = (room / m.sw).floor().max(8.0) as usize;
                    for row in crate::ui::wrap(&text, n) {
                        out.push(Row {
                            h: m.px(20.0),
                            pick: None,
                            k: K::Words(row, Size::Small, true, false),
                        });
                    }
                    None
                } else if l.action.is_some() {
                    let switch = matches!(l.sign, "dot" | "ring") && !l.value.is_empty();
                    let sign = if matches!(l.sign, "check" | "blank") { l.sign } else { "" };
                    // a value the grid put under its words is the row's own again
                    let mut value = l.value.clone();
                    while let Some(Item::Apps(n)) = items.get(k).filter(|it| matches!(it, Item::Apps(n) if n.continuation && n.action.is_none())) {
                        value = format!("{} {}", value, n.value).trim().to_string();
                        k += 1;
                    }
                    Some((
                        m.px(36.0),
                        K::One {
                            icon: None,
                            sign,
                            swatch: vec![],
                            name: l.label.clone(),
                            muted: l.disabled,
                            words: String::new(),
                            end: if switch {
                                End::Switch(l.sign == "dot")
                            } else if value.is_empty() {
                                End::None
                            } else {
                                End::Words(value)
                            },
                            tail: !l.tail.is_empty(),
                            key: l.key.clone(),
                        },
                    ))
                } else {
                    // a fact: its value's lines joined, then on its label's line where both fit, else under it
                    let mut value = l.value.clone();
                    while let Some(Item::Apps(n)) = items.get(k).filter(|it| matches!(it, Item::Apps(n) if n.continuation && n.action.is_none())) {
                        value = format!("{} {}", value, n.value).trim().to_string();
                        k += 1;
                    }
                    if (cells(&l.label) + cells(&value) + 2) as f64 * m.sw <= room {
                        Some((m.px(28.0), K::Fact(l.label.clone(), value)))
                    } else {
                        if !l.label.is_empty() {
                            out.push(Row {
                                h: m.px(24.0),
                                pick: None,
                                k: K::Words(l.label.clone(), Size::Small, true, false),
                            });
                        }
                        for row in crate::ui::wrap(&value, (room / m.sw).floor().max(8.0) as usize) {
                            out.push(Row {
                                h: m.px(20.0),
                                pick: None,
                                k: K::Words(row, Size::Small, false, false),
                            });
                        }
                        None
                    }
                }
            }
            _ => None,
        };
        if let Some((h, kind)) = made {
            // a heading brings its own air over it
            if matches!(kind, K::Head(..)) && matches!(out.last(), Some(Row { k: K::Gap(_), .. })) {
                out.pop();
            }
            out.push(Row {
                h,
                pick: if shape.still { None } else { pick(at) },
                k: kind,
            });
        }
    }
    while matches!(out.last(), Some(Row { k: K::Gap(_), .. })) {
        out.pop();
    }
    // a category says how many apps stand under it
    if shape.two && !shape.narrow {
        for at in 0..out.len() {
            if matches!(out[at].k, K::Head(..)) {
                let n = out[at + 1..]
                    .iter()
                    .take_while(|r| !matches!(r.k, K::Head(..)))
                    .filter(|r| matches!(r.k, K::App(..)))
                    .count();
                if let (K::Head(_, count, _), true) = (&mut out[at].k, n > 0) {
                    *count = Some(n.to_string());
                }
            }
        }
    }
    out
}

/// The rows of a page about one app, as its details are drawn: who it is first, what you do with it, a rule,
/// its facts, a rule, then its preferences. The rows keep the order the app counts its picks in.
fn about_app(app: &App, pen: &Pen, id: &str, rows: Vec<Row>, room: f64) -> Vec<Row> {
    let m = pen.m;
    let Some(a) = app.apps.entry(id) else { return rows };
    // the page's own title and its note stand in the identity: the rows up to the first air go
    let titled = matches!(
        rows.first(),
        Some(Row {
            k: K::Words(_, Size::Main, _, true),
            ..
        })
    );
    let skip = rows
        .iter()
        .position(|r| matches!(r.k, K::Gap(_)))
        .filter(|_| titled)
        .map_or(usize::from(titled), |k| k + 1);
    let body: Vec<Row> = rows.into_iter().skip(skip).collect();
    let what = if a.description.is_empty() {
        "no description in its desktop entry".to_string()
    } else {
        a.description.trim_end_matches('.').to_lowercase()
    };
    let side = m.px(48.0);
    // three lines at most, the third cut: the identity keeps one height, so the rows under it stand still from
    // one app to the next
    let cells_wide = ((room - side - m.px(12.0)) / m.sw).floor().max(8.0) as usize;
    let mut lines = crate::ui::wrap(&what, cells_wide);
    if lines.len() > 3 {
        let rest = lines[2..].join(" ");
        lines.truncate(2);
        lines.push(format!("{}\u{2026}", cut(&rest, cells_wide.saturating_sub(1)).trim_end()));
    }
    let h = m.px(108.0);
    let mut out = vec![Row {
        h,
        pick: None,
        k: K::Identity(app.apps.icon_of(a), a.name.to_lowercase(), lines),
    }];
    let rule = || Row {
        h: m.px(17.0),
        pick: None,
        k: K::Rule,
    };
    if !matches!(app.apps.page, Page::Details(_) | Page::List | Page::Hidden) {
        out.extend(body);
        return out;
    }
    let head = body.iter().position(|r| matches!(r.k, K::Head(..))).unwrap_or(body.len());
    let (first, rest) = body.split_at(head);
    let acts: Vec<Row> = first.iter().filter(|r| matches!(r.k, K::One { .. })).cloned().collect();
    let facts: Vec<Row> = first.iter().filter(|r| matches!(r.k, K::Fact(..) | K::Words(..))).cloned().collect();
    out.extend(acts);
    if !facts.is_empty() {
        out.push(rule());
        out.extend(facts);
    }
    if !rest.is_empty() {
        out.push(rule());
        out.extend(rest.iter().cloned());
    }
    out
}

/// A box of a list: the edges its words keep to, its top and bottom, and the ends of the lit row's bar. The
/// bar fills the line from the window's edge to its other edge, or to the line between two lists: wider than the
/// words' own edges, which stand inside the frame.
#[derive(Clone, Copy)]
struct Area {
    left: f64,
    right: f64,
    top: f64,
    bottom: f64,
    from: f64,
    to: f64,
}

/// How far a list is scrolled. It keeps the place it had in the frame before (a drag moves it there), moved by
/// what the app's own count of lines changed. When the lit row changes, or the box's height, the lit row is brought
/// into view: with the heading over it where both fit, and with a part of the next row under it, which says
/// the list goes on. A list drawn for the first time starts from the app's count of lines.
fn scrolled(m: &Metrics, rows: &[Row], lit: Option<usize>, view: f64, lines: usize, was: Option<&Scrolled>) -> f64 {
    let total: f64 = rows.iter().map(|r| r.h).sum();
    let most = (total - view).max(0.0);
    let (mut off, seek) = match was {
        Some(w) => (w.off + (lines as f64 - w.lines as f64) * m.ch, w.lit != lit || w.view != view),
        None => (lines as f64 * m.ch, true),
    };
    off = off.clamp(0.0, most);
    let Some(at) = lit.and_then(|n| rows.iter().position(|r| r.pick == Some(n))).filter(|_| seek) else {
        return off;
    };
    let top: f64 = rows[..at].iter().map(|r| r.h).sum();
    let bottom = top + rows[at].h;
    // a part of the row before and of the row after stays in view: the list is seen to go on
    let peek = m.px(24.0);
    // what frames the row from above comes into view with it
    let framed = (0..at).rev().take_while(|k| matches!(rows[*k].k, K::Head(..) | K::Gap(_))).last().unwrap_or(at);
    let head: f64 = rows[..framed].iter().map(|r| r.h).sum();
    let above = if framed < at && bottom - head <= view { head } else { (top - peek).max(0.0) };
    off = off.min(above);
    let under = if at + 1 < rows.len() { peek } else { 0.0 };
    if bottom + under > off + view {
        off = (bottom + under - view).min(top);
    }
    off.clamp(0.0, most)
}

/// A list drawn in its box: the rows in view, the lit one filled (its name underlined while the list holds the
/// keys). A list longer than its box is cut at the box's edge, a part of the next row in view: no bar says it. `key`
/// names the list, so it keeps its place from frame to frame; how far it is scrolled is given back.
#[allow(clippy::too_many_arguments)]
fn list(app: &App, pen: &mut Pen, rows: &[Row], area: Area, lit: Option<usize>, focus: bool, shape: Shape, lines: usize, key: String) -> f64 {
    let m = *pen.m;
    let t = pen.t;
    let view = area.bottom - area.top;
    let total: f64 = rows.iter().map(|r| r.h).sum();
    let off = scrolled(&m, rows, lit, view, lines, pen.was.iter().find(|w| w.key == key));
    pen.lists.push(ListBox {
        x: area.from,
        y: area.top,
        w: area.to - area.from,
        h: view,
        most: (total - view).max(0.0),
        at: Scrolled { key, off, lines, lit, view },
    });
    let right = area.right;
    pen.steps.push(Step::Clip {
        x: area.from,
        y: area.top,
        w: area.to - area.from,
        h: view,
    });
    // each group lines its second words up: past its longest name
    let mut column = m.px(176.0);
    let mut y = area.top - off;
    for (at, row) in rows.iter().enumerate() {
        if matches!(row.k, K::Head(..)) || at == 0 {
            let names = rows[at..]
                .iter()
                .skip(usize::from(matches!(row.k, K::Head(..))))
                .take_while(|r| !matches!(r.k, K::Head(..)))
                .filter_map(|r| match &r.k {
                    K::One { name, icon, .. } => Some(cells(name) as f64 * m.cw + if icon.is_some() { m.px(36.0) } else { 0.0 }),
                    K::Dest(name, _) => Some(cells(name) as f64 * m.cw),
                    _ => None,
                })
                .fold(0.0, f64::max);
            column = (m.px(24.0) + names + m.px(24.0)).clamp(m.px(176.0), ((right - area.left) * 0.55).round().max(m.px(176.0)));
        }
        let (top, h) = (y, row.h);
        y += h;
        if top + h <= area.top || top >= area.bottom {
            continue;
        }
        let on = row.pick.is_some() && row.pick == lit;
        // the lit row's bar fills the line end to end, and the whole of it takes the click
        if on {
            pen.fill(area.from, top, area.to - area.from, h, t.lit);
        }
        if let Some(n) = row.pick {
            pen.hit(
                area.from,
                top.max(area.top),
                area.to - area.from,
                (top + h).min(area.bottom) - top.max(area.top),
                Target::Pick(n),
            );
        }
        let x = area.left + m.px(shape.pad);
        // a column of names keeps its room for the names
        let end = right - m.px(if shape.two && shape.narrow { 4.0 } else { 12.0 });
        // on a whole pixel: a row of an odd height would set its words half a pixel down, blurred
        let mid = (top + h / 2.0).floor();
        match &row.k {
            K::Gap(_) => {}
            K::Rule => pen.fill(area.left, top + m.px(8.0), right - area.left, 1.0, t.lit),
            K::Head(text, count, click) => {
                let base = top + m.px(24.0);
                let w = pen.text(x, base, text, Size::Small, t.accent, true);
                if let Some(c) = count.as_ref().filter(|_| !shape.narrow) {
                    pen.text_end(end, base, c, Size::Small, t.muted, false);
                }
                if let Some(label) = click {
                    pen.hit(x - m.px(6.0), top + m.px(6.0), w + m.px(12.0), h - m.px(8.0), Target::Head(label.clone()));
                }
            }
            K::Dest(name, words) => {
                let base = mid + m.px(6.0);
                let w = pen.text(x, base, name, Size::Main, t.ink, on);
                let wx = area.left + column;
                let words = pen.fit(words, Size::Small, end - wx);
                pen.text(wx, base, &words, Size::Small, t.muted, false);
                if on && focus {
                    pen.fill(x, base + m.px(5.0), w, 2.0, t.accent);
                }
            }
            K::App(name, role, icon, id) => {
                let side = m.px(32.0);
                let mut nx = x;
                if let Some(icon) = icon {
                    pen.icon(icon, x, (mid - side / 2.0).round(), side);
                    nx += side + m.px(16.0);
                }
                let (nb, rb) = if role.is_empty() {
                    (mid + m.px(6.0), 0.0)
                } else {
                    (mid - m.px(5.0), mid + m.px(16.0))
                };
                let name = pen.fit(name, Size::Main, end - nx);
                let w = pen.text(nx, nb, &name, Size::Main, t.ink, on);
                if !role.is_empty() {
                    let role = pen.fit(role, Size::Small, end - nx);
                    pen.text(nx, rb, &role, Size::Small, t.muted, false);
                }
                if on && focus {
                    pen.fill(nx, nb + m.px(4.0), w, 2.0, t.accent);
                }
                if shape.still {
                    pen.hit(
                        area.from,
                        top.max(area.top),
                        area.to - area.from,
                        (top + h).min(area.bottom) - top.max(area.top),
                        Target::ListApp(id.clone()),
                    );
                }
            }
            K::One {
                icon,
                sign,
                swatch,
                name,
                muted,
                words,
                end: at_end,
                tail,
                key,
            } => {
                let base = mid + m.px(6.0);
                let mut nx = x;
                if let Some(icon) = icon {
                    let side = m.px(24.0);
                    pen.icon(icon, x, (mid - side / 2.0).round(), side);
                    nx += side + m.px(12.0);
                }
                if !sign.is_empty() {
                    let (glyph, color) = match *sign {
                        "dot" => (app.glyphs.dot, t.accent),
                        "ring" => (app.glyphs.ring, t.ink),
                        "check" => (crate::ui::CHECK, t.accent),
                        "cross" => (crate::ui::CROSS, t.alarm),
                        _ => (" ", t.ink),
                    };
                    pen.text(nx, base, glyph, Size::Main, color, false);
                    nx += 2.0 * m.cw;
                }
                if !swatch.is_empty() {
                    let s = m.px(12.0);
                    for (i, c) in swatch.iter().take(6).enumerate() {
                        pen.fill(nx + i as f64 * s, (mid - s / 2.0).round(), s, s, *c);
                    }
                    nx += swatch.len().min(6) as f64 * s + m.px(10.0);
                }
                // from the row's end backward: the arrow, the key, then the value or the control
                let mut e = end;
                if *tail {
                    e -= pen.text_end(e, base, crate::ui::MORE, Size::Main, t.muted, false) + m.px(8.0);
                }
                if !key.is_empty() {
                    let w = pen.width(key, Size::Small) + m.px(16.0);
                    pen.fill(e - w, base - m.px(15.0), w, m.px(21.0), if on { t.ground } else { t.lit });
                    pen.text(e - w + m.px(8.0), base, key, Size::Small, t.ink, false);
                    e -= w + m.px(8.0);
                }
                match at_end {
                    End::None => {}
                    End::Words(v) => {
                        let v = pen.fit(v, Size::Small, (e - nx - pen.width(name, Size::Main) - m.px(16.0)).max(4.0 * m.sw));
                        e -= pen.text_end(e, base, &v, Size::Small, t.muted, false) + m.px(8.0);
                    }
                    End::Switch(is_on) => {
                        let (glyph, gc, word, wc) = if *is_on {
                            (app.glyphs.dot, t.accent, "on", t.ink)
                        } else {
                            (app.glyphs.ring, t.muted, "off", t.muted)
                        };
                        e -= pen.text_end(e, base, word, Size::Small, wc, false) + m.sw;
                        e -= pen.text_end(e, base, glyph, Size::Small, gc, false) + m.px(8.0);
                    }
                    End::Stepper(v, less, more, widest) => {
                        // the room of the widest value, so the arrows stand still as it changes
                        let (dim, live) = (if on { t.ground } else { t.lit }, if on { t.accent } else { t.muted });
                        let aw = m.cw;
                        let mx = e - aw;
                        pen.text(mx, base, crate::ui::MORE, Size::Main, if *more { live } else { dim }, false);
                        let vx = mx - m.sw - *widest as f64 * m.sw;
                        pen.text_end(mx - m.sw, base, v, Size::Small, t.ink, false);
                        let lx = vx - m.sw - aw;
                        pen.text(lx, base, crate::ui::LESS, Size::Main, if *less { live } else { dim }, false);
                        if let Some(n) = row.pick {
                            pen.hit(lx - aw, top, 3.0 * aw, h, Target::Step(n, false));
                            pen.hit(mx - aw, top, 3.0 * aw, h, Target::Step(n, true));
                        }
                        e = lx - m.px(8.0);
                    }
                }
                let wx = (area.left + column).max(nx);
                let room = if words.is_empty() { e - nx } else { (wx - m.px(16.0) - nx).max(6.0 * m.cw) };
                let name = pen.fit(name, Size::Main, room);
                let w = pen.text(nx, base, &name, Size::Main, if *muted { t.muted } else { t.ink }, on);
                if !words.is_empty() {
                    let wx = wx.max(nx + w + m.px(16.0));
                    let words = pen.fit(words, Size::Small, e - wx);
                    pen.text(wx, base, &words, Size::Small, t.muted, false);
                }
                if on && focus {
                    pen.fill(nx, base + m.px(5.0), w, 2.0, t.accent);
                }
            }
            K::Words(text, size, muted, bold) => {
                let base = mid + if *size == Size::Main { m.px(6.0) } else { m.px(5.0) };
                let text = pen.fit(text, *size, end - x);
                pen.text(x, base, &text, *size, if *muted { t.muted } else { t.ink }, *bold);
            }
            K::Fact(label, value) => {
                let base = mid + m.px(5.0);
                pen.text(x, base, label, Size::Small, t.muted, false);
                pen.text_end(end, base, value, Size::Small, t.ink, false);
            }
            K::Identity(icon, name, lines) => {
                let side = m.px(48.0);
                let mut nx = area.left;
                if let Some(icon) = icon {
                    pen.icon(icon, nx, top + m.px(16.0), side);
                    nx += side + m.px(12.0);
                }
                let name = pen.fit(name, Size::Main, end - nx);
                pen.text(nx, top + m.px(36.0), &name, Size::Main, t.ink, true);
                for (i, l) in lines.iter().enumerate() {
                    pen.text(nx, top + m.px(56.0) + i as f64 * m.px(17.0), l, Size::Small, t.muted, false);
                }
            }
        }
    }
    pen.steps.push(Step::Unclip);
    off
}

/// The row lit now: by the app's count, while a row is lit.
fn lit(app: &App) -> Option<usize> {
    app.in_list.then_some(app.sel)
}

/// Whether the list holds the keys: a lit row then wears the line under its name, and the line shows no cursor.
/// A row lit by a key, or lit with nothing typed in a place; never the row home keeps lit at its empty line, nor
/// the one the words typed light, where the line still holds them.
fn list_focus(app: &App) -> bool {
    app.in_list && app.chip_focus.is_none() && (app.list_keys || (app.input.is_empty() && app.view != View::Home))
}

// ---------------------------------------------------------------- the bodies

/// Home: its places, or what the words typed found, a row of one line each.
fn home(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let area = Area {
        left: g.inset,
        right: g.w - g.inset,
        top: g.top,
        bottom: g.bottom,
        from: 0.0,
        to: g.w,
    };
    let shape = Shape {
        two: false,
        one: 44.0,
        narrow: false,
        still: false,
        pad: 24.0,
    };
    let rows = rows_of(app, pen, items, shape, area.right - area.left - pen.m.px(48.0));
    list(
        app,
        pen,
        &rows,
        area,
        lit(app),
        list_focus(app),
        shape,
        app.scroll,
        format!("home\u{1f}{}", app.input),
    );
}

/// Apps: the list, a page of its own, or an app's details beside the list where the window holds both.
fn apps(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let m = *pen.m;
    let whole = Area {
        left: g.inset,
        right: g.w - g.inset,
        top: g.top,
        bottom: g.bottom,
        from: 0.0,
        to: g.w,
    };
    let listing = matches!(app.apps.page, Page::List | Page::Hidden);
    let full = Shape {
        two: listing,
        one: if listing { 44.0 } else { 36.0 },
        narrow: false,
        still: false,
        pad: 24.0,
    };
    // the details beside the list: the list a narrow column of names, the details the rest
    let beside = app.apps.pane && splits(&m, g.w);
    let subject = app.apps.subject().map(str::to_string);
    let lit_app = || match app.picks().get(app.sel).filter(|_| app.in_list) {
        Some(Item::Apps(l)) => match &l.action {
            Some(Action::Launch(id)) => Some(id.clone()),
            _ => None,
        },
        _ => None,
    };
    let pane_w = ((g.w - 2.0 * g.inset) * 0.5).round().clamp(m.px(280.0), m.px(440.0));
    let divide = whole.right - pane_w - m.px(16.0);
    // beside each other, a bar ends at the line between them
    let left = Area {
        right: divide - m.px(16.0),
        to: divide,
        ..whole
    };
    let right = Area {
        left: divide + m.px(16.0),
        from: divide + 1.0,
        ..whole
    };
    let narrow = Shape {
        two: true,
        one: 44.0,
        narrow: true,
        still: false,
        pad: 24.0,
    };
    let page = Shape {
        two: false,
        one: 36.0,
        narrow: true,
        still: false,
        pad: 12.0,
    };
    let room = |a: Area| a.right - a.left - m.px(36.0);
    // a list by its name: the page, the words that search it, the category shown alone. The list beside the
    // details has the name it had alone, so it keeps its place when the keys go to the details and back
    let named = |page: &Page, query: &str| format!("apps\u{1f}{:?}\u{1f}{}\u{1f}{:?}", page, query, app.apps.filter);
    let own = named(&app.apps.page, &app.input);
    match (beside, listing, subject) {
        // the list holds the keys, the lit app's details stand beside it
        (true, true, _) if lit_app().is_some() => {
            let id = lit_app().unwrap_or_default();
            let rows = rows_of(app, pen, items, narrow, room(left));
            list(app, pen, &rows, left, lit(app), list_focus(app), narrow, app.scroll, own);
            pen.fill(divide, whole.top + m.px(8.0), 1.0, whole.bottom - whole.top - m.px(16.0), pen.t.lit);
            let about = Page::Details(id.clone());
            let lines: Vec<Item> = app.apps.lines_of(&about, 60, "", 0).into_iter().map(Item::Apps).collect();
            let still = Shape { still: true, ..page };
            let rows = about_app(app, pen, &id, rows_of(app, pen, &lines, still, room(right)), room(right));
            let off = list(app, pen, &rows, right, None, false, still, 0, named(&about, ""));
            pane_targets(pen, &rows, right, off);
        }
        // the details hold the keys, the list stands beside them with their app lit
        (true, false, Some(id)) if app.apps.root_lists() => {
            let (root, query) = app
                .apps
                .root()
                .map(|(p, n)| (p.clone(), n.query.clone()))
                .unwrap_or((Page::List, String::new()));
            let lines: Vec<Item> = app.apps.lines_of(&root, 60, &query, 0).into_iter().map(Item::Apps).collect();
            let still = Shape { still: true, ..narrow };
            let mut rows = rows_of(app, pen, &lines, still, room(left));
            // the app the details are of is the lit one, by a pick no row of the app's has
            for r in rows.iter_mut() {
                if matches!(&r.k, K::App(_, _, _, a) if *a == id) {
                    r.pick = Some(usize::MAX);
                }
            }
            list(app, pen, &rows, left, Some(usize::MAX), false, still, 0, named(&root, &query));
            pen.hits.retain(|h| h.target != Target::Pick(usize::MAX));
            pen.fill(divide, whole.top + m.px(8.0), 1.0, whole.bottom - whole.top - m.px(16.0), pen.t.lit);
            let rows = about_app(app, pen, &id, rows_of(app, pen, items, page, room(right)), room(right));
            list(app, pen, &rows, right, lit(app), list_focus(app), page, app.scroll, own);
        }
        // a page about an app, alone: who it is first
        (_, false, Some(id)) => {
            let rows = about_app(app, pen, &id, rows_of(app, pen, items, full, room(whole)), room(whole));
            list(app, pen, &rows, whole, lit(app), list_focus(app), full, app.scroll, own);
        }
        _ => {
            let rows = rows_of(app, pen, items, full, room(whole));
            list(app, pen, &rows, whole, lit(app), list_focus(app), full, app.scroll, own);
        }
    }
}

/// The details beside a list that holds the keys: a click on one of their rows takes the keys there, on that row.
fn pane_targets(pen: &mut Pen, rows: &[Row], area: Area, off: f64) {
    let mut y = area.top - off;
    let mut n = 0;
    for r in rows {
        let (top, h) = (y, r.h);
        y += h;
        if !matches!(r.k, K::One { .. }) {
            continue;
        }
        let at = n;
        n += 1;
        let (a, b) = (top.max(area.top), (top + h).min(area.bottom));
        if b > a {
            pen.hit(area.from, a, area.to - area.from, b - a, Target::PaneRow(at));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_length_of_the_sheets_grows_with_the_text() {
        assert_eq!(Metrics::SHEET.px(44.0), 44.0);
        let big = Metrics { ch: 30.0, ..Metrics::SHEET };
        assert_eq!(big.px(44.0), 66.0);
        assert_eq!(app_row(&Metrics::SHEET, Spacing::Rows), 52.0);
        assert_eq!(app_row(&Metrics::SHEET, Spacing::None), 40.0);
    }

    #[test]
    fn the_last_thing_drawn_at_a_point_takes_the_click() {
        let hit = |x: f64, target| Hit {
            x,
            y: 0.0,
            w: 10.0,
            h: 10.0,
            target,
        };
        let s = Scene {
            hits: vec![hit(0.0, Target::Prompt), hit(5.0, Target::Undo)],
            ..Scene::default()
        };
        assert_eq!(s.hit(2.0, 2.0), Some(&Target::Prompt));
        assert_eq!(s.hit(7.0, 2.0), Some(&Target::Undo), "the later of two over a point");
        assert_eq!(s.hit(15.0, 2.0), None, "its right edge is outside");
        assert_eq!(s.hit(2.0, 10.0), None);
    }
}
