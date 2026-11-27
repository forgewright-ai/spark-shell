//! The layout in pixels, for a window of the dialog's own: the line, where you are, the list and the keys placed
//! by the pixel in two sizes of text, where the grid (ui.rs) places every symbol in a cell. It draws the frame of
//! every place, and the body of the places redesigned so far: home, what home finds, apps and an app's details
//! beside its list, files in one pane and in two and a file's details beside its list. Any other place keeps its
//! grid rows, laid inside this frame. Pure: the app's state in, drawing
//! steps and the places a click acts out; a painter (paint.rs) draws them, a test reads them.

use crate::app::{App, FolderShape, HintKey, Item, Mode, Talk, View, DESTS, SETTINGS};
use crate::apps::{Action, Page};
use crate::draw::{Rgb, Size, Step};
use crate::files::{self, Side};
use crate::grid::Color;
use crate::page::Icon;
use crate::palette::Palette;
use crate::preferences::Spacing;
use crate::scrub::{cells, cut, cut_middle};

pub(crate) mod card;
mod choice;
mod screens;

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
    /// The large sizes (Size::BIG: a heading, the line under a name, a name at its three sizes): a letter's width,
    /// and the baseline under the line's top.
    pub big: [(f64, f64); 5],
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
        big: Metrics::big_of(10.0, 16.0),
    };
    /// The large sizes of a face whose own letter is `cw` wide with its baseline `up` under its line's top: each
    /// as many times those as the size is, on whole pixels. For a face nothing measured (a test's).
    pub const fn big_of(cw: f64, up: f64) -> [(f64, f64); 5] {
        const fn whole(v: f64) -> f64 {
            (v + 0.5) as i64 as f64
        }
        [
            (whole(cw * 1.75), whole(up * 1.75)),
            (whole(cw * 1.375), whole(up * 1.375)),
            (whole(cw * 4.5), whole(up * 4.5)),
            (whole(cw * 3.0), whole(up * 3.0)),
            (whole(cw * 2.0), whole(up * 2.0)),
        ]
    }
    /// A length of the sheets, at this text's size, on a whole pixel.
    pub fn px(&self, v: f64) -> f64 {
        (v * self.ch / 20.0).round()
    }
    fn adv(&self, size: Size) -> f64 {
        match size {
            Size::Main => self.cw,
            Size::Small => self.sw,
            big => self.big[big.big().unwrap_or(0)].0,
        }
    }
    fn rise(&self, size: Size) -> f64 {
        match size {
            Size::Main => self.up,
            Size::Small => self.sup,
            big => self.big[big.big().unwrap_or(0)].1,
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
    /// A place further up it: how many levels.
    BackBy(usize),
    /// An app in the list beside its details: its details come.
    ListApp(String),
    /// A row of the details shown beside the list while the list holds the keys.
    PaneRow(usize),
    /// A value's arrow: the row, and whether it steps the value up.
    Step(usize, bool),
    /// An option of a row of one setting (C3, v0.161): the row, and the option (App::option_at says which).
    Option(usize, usize),
    /// A screen of the display page's map (v0.167): the map's row, and the screen's name. A press on it is the map's:
    /// it may be a drag.
    Screen(usize, String),
    /// A change on trial: kept (true), or put back.
    Trial(bool),
    /// A folder's name on the location line: its uri.
    Crumb(String),
    /// A row of the other pane of files, by its place among that pane's rows.
    OtherRow(usize),
    /// The other pane of files, off its rows: it takes the keys.
    OtherPane,
    /// A row of the list of files while a file's details hold the keys: the list takes them, on that row.
    ListRow(usize),
    /// A folder's order on the location line: the next order (v0.169).
    Sort,
    /// A swatch of the color picker (v0.172): its strip, and its place on it.
    Swatch(crate::picker::Strip, usize),
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

/// What a file shows, where its details draw it: the box it is fitted in, its file, and for a sound's picture the
/// height of the waveform in it.
#[derive(Clone, Debug, PartialEq)]
pub struct PictureAt {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub file: String,
    pub wave: Option<u32>,
    /// It stands at the box's corner, not in its middle: a page in large type. A sound's is then its waveform.
    pub corner: bool,
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
    /// What a file shows in its details: kept inside the list's box, as an icon is.
    pub pictures: Vec<PictureAt>,
    /// How the display page's map is laid, where it is drawn: a drag on it is read by it.
    pub map: Option<crate::display::screens::Fit>,
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
    Files,
    /// Settings' list (v0.161): its groups named large, a setting two lines, its name over what it is set to.
    Settings,
    /// A section's page (v0.161): a setting one row, its options side by side.
    Page,
    /// A place of home in the new type (v0.162): workspaces, notes, system, help, power; a row of words two lines.
    Place,
    /// The Calendar (v0.162): the time large, the months side by side, then its rows.
    Calendar,
    /// The place's grid rows, inside the frame.
    Grid,
}

/// Which body the place shown gets: home and apps their rows in pixels, where every row is one the layout
/// knows; a question's page, a transition and every other place the grid's.
pub fn kind(app: &App) -> Kind {
    // a color being picked stands in place of the page, whichever place asked for it (v0.172)
    if app.picker.is_some() && app.motion.is_none() {
        return Kind::Page;
    }
    match app.view {
        View::Home | View::Apps => kind_of(app, &app.list_items()),
        View::Folder(..)
            if app.files_pane_view().is_some()
                || crate::appearance::gallery(&app.view)
                || crate::appearance::section(&app.view)
                || crate::appearance::screen(&app.view) =>
        {
            kind_of(app, &app.list_items())
        }
        View::Dest(d) if d == crate::app::SETTINGS_DEST => kind_of(app, &app.list_items()),
        View::Section(_) | View::Help => kind_of(app, &app.list_items()),
        View::Dest(d) if d == crate::app::WORKSPACE_DEST || d == crate::app::CALENDAR_DEST => kind_of(app, &app.list_items()),
        View::Steps(_) if theme_steps(app) => kind_of(app, &app.list_items()),
        _ => Kind::Grid,
    }
}

/// The steps of a theme's row (rename, duplicate, delete): a page as the theme's other lists are (v0.172; they stood
/// in the grid's tight lines under pages of rows).
fn theme_steps(app: &App) -> bool {
    matches!(app.view, View::Steps(p) if app.providers.get(p).is_some_and(|x| x.label == "theme"))
}

/// The sections a place of home shows in the new type (v0.162), apart from settings' pages.
const PLACES: [&str; 3] = ["notes", "system", "power"];

/// The same, of the items already read.
fn kind_of(app: &App, items: &[Item]) -> Kind {
    if app.motion.is_some() || matches!(app.mode, Mode::Confirm(_)) {
        return Kind::Grid;
    }
    if app.picker.is_some() {
        return Kind::Page;
    }
    match app.view {
        View::Home if items.iter().all(known) => Kind::Home,
        View::Apps if items.iter().all(known) => Kind::Apps,
        View::Folder(..) if app.files_pane_view().is_some() && items.iter().all(known) => Kind::Files,
        View::Dest(d) if d == crate::app::SETTINGS_DEST && items.iter().all(known) => Kind::Settings,
        View::Folder(..)
            if (crate::appearance::gallery(&app.view) || crate::appearance::section(&app.view) || crate::appearance::screen(&app.view))
                && items.iter().all(known) =>
        {
            Kind::Page
        }
        View::Section(p) if items.iter().all(known) && app.providers.get(p).is_some_and(|x| PLACES.contains(&x.label.as_str())) => Kind::Place,
        View::Section(_) if items.iter().all(known) => Kind::Page,
        View::Help if items.iter().all(known) => Kind::Place,
        View::Dest(d) if d == crate::app::WORKSPACE_DEST && items.iter().all(known) => Kind::Place,
        View::Dest(d) if d == crate::app::CALENDAR_DEST && items.iter().all(known) => Kind::Calendar,
        View::Steps(_) if theme_steps(app) && items.iter().all(known) => Kind::Page,
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
            | Item::Folder(_)
            | Item::Files(_)
            | Item::Here
            | Item::Key(..)
            | Item::StepOf(_)
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
/// A row's value, its control and its key stand this far from the list's edge at most: beside its name in a wide
/// window, never across it.
const ROW_MAX: f64 = 640.0;

/// Whether a window holds the frame at all: the line, a list and the keys. A smaller one is the grid's, which says
/// to make the window larger.
pub fn fits(m: &Metrics, w: f64, h: f64) -> bool {
    w >= crate::app::MIN_WIDTH as f64 * m.cw && h >= crate::app::MIN_HEIGHT as f64 * m.ch
}

/// Whether a window this wide holds an app's details beside the list.
pub fn splits(m: &Metrics, w: f64) -> bool {
    w >= m.px(SPLIT_MIN)
}

/// A window this wide shows the lit app or file beside the list at once, in large type (v0.160): the list keeps
/// a column at the left, WIDE_LIST wide, and the page starts WIDE_PAGE from the window's edge.
const WIDE_MIN: f64 = 1280.0;
const WIDE_LIST: f64 = 696.0;
const WIDE_PAGE: f64 = 780.0;

/// Whether a window is wide: the lit thing's page stands beside the list without being asked for.
pub fn wide(m: &Metrics, w: f64) -> bool {
    w >= m.px(WIDE_MIN)
}

/// Two panes of files keep the lit file's page beside them in a window this wide: three columns, the page the
/// last, PAGE3 wide.
const WIDE3_MIN: f64 = 1900.0;
const PAGE3: f64 = 640.0;

/// Whether a window holds two panes of files and the lit file's page.
pub fn wide3(m: &Metrics, w: f64) -> bool {
    w >= m.px(WIDE3_MIN)
}

/// The size in cells the app is told, so its own counts fit what is drawn: the columns the grid rows have, and a
/// list of as many rows as the body shows, under the grid's head and over its foot.
pub fn size(app: &App, m: &Metrics, w: f64, h: f64) -> (u16, u16) {
    let k = kind(app);
    let g = Geo::new(app, m, w, h, k);
    let rows = match k {
        Kind::Grid => g.grid_rows(m),
        Kind::Home | Kind::Files => ((g.bottom - g.top) / m.px(44.0)) as u16,
        Kind::Apps => ((g.bottom - g.top) / app_row(m, app.apps.spacing)) as u16,
        Kind::Settings => ((g.bottom - g.top) / m.px(52.0)) as u16,
        Kind::Page | Kind::Place => ((g.bottom - g.top) / m.px(44.0)) as u16,
        Kind::Calendar => ((g.bottom - calendar_top(app, m, &g)) / m.px(44.0)) as u16,
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
        let trial = app.trial_card().is_some();
        let status = k == Kind::Grid || trial || message(app, k).is_some();
        let top = if path { m.px(PATH_RULE) + 1.0 } else { m.px(HEAD) };
        let room = match (trial, status) {
            (true, _) => card::height(m),
            (false, true) => m.px(STATUS),
            (false, false) => 0.0,
        };
        let bottom = (foot - room).max(top);
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
    pictures: Vec<PictureAt>,
    /// Where the next list's second words stand, from its left edge, where its page says: the column its options have.
    column: Option<f64>,
    /// What a list draws over all of its rows: a screen that is dragged.
    over: Vec<Step>,
    map: Option<crate::display::screens::Fit>,
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
        pictures: vec![],
        column: None,
        over: vec![],
        map: None,
    };
    line(app, &mut pen, &g);
    if g.path {
        path(app, &mut pen, &g, &items, k);
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
        Kind::Files => files_body(app, &mut pen, &g, &items),
        Kind::Settings => settings(app, &mut pen, &g, &items),
        Kind::Page => page(app, &mut pen, &g, &items),
        Kind::Place => place(app, &mut pen, &g, &items),
        Kind::Calendar => calendar(app, &mut pen, &g, &items),
    }
    if app.trial_card().is_some() {
        card::draw(app, &mut pen, &g);
    } else if g.status {
        status(app, &mut pen, &g, k);
    }
    g.keys.draw(&mut pen, &g);
    scene.steps = pen.steps;
    scene.hits = pen.hits;
    scene.icons = pen.icons;
    scene.lists = pen.lists;
    scene.pictures = pen.pictures;
    scene.map = pen.map;
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
        let cw = m.cw * symbol_at(&row, cc).map_or(1, |s| cells(&s)) as f64;
        let m = Metrics { cw, ..m }; // the cursor is as wide as the character it stands on
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
fn path(app: &App, pen: &mut Pen, g: &Geo, items: &[Item], k: Kind) {
    let m = *pen.m;
    let t = pen.t;
    let base = m.px(PATH_BASE);
    let crumbs = if k == Kind::Files { crumbs(app) } else { None };
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
        (View::Folder(_, uri), _)
            if app.input.is_empty()
                && (uri == crate::appearance::GALLERY || uri.starts_with(crate::appearance::PALETTES) || uri.starts_with(crate::appearance::EXPORTS)) =>
        {
            app.folder.as_ref().and_then(|(_, _, rows)| rows.state.clone()).unwrap_or_default()
        }
        // a folder of files: how much it holds, which its summary row said in the grid. A page alone over the
        // list says what it is of, and no count
        _ if k == Kind::Files && !(app.files_page_open() && !app.files.form() && !app.files_details_beside()) => {
            // its count, then its order (v0.169): a click on them takes the next order
            let rows = app.folder.as_ref().map(|(_, _, rows)| rows);
            let count = rows
                .and_then(|rows| rows.rows.iter().find(|r| files::is_summary(r)))
                .and_then(|r| files::short_summary(&r.text))
                .unwrap_or_default();
            let order = rows
                .and_then(|rows| rows.state.clone())
                .filter(|_| app.files_pane_view().is_some())
                .unwrap_or_default();
            [count, order].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join(crate::ui::SEP)
        }
        (View::Help, _) => format!("{} shortcuts", app.shortcuts()),
        _ => String::new(),
    };
    // what a place holds now is no level under it: it stands at the line's end, where a list's count does (v0.169)
    let holds = app.mode == Mode::Normal && (matches!(app.view, View::Section(_)) || matches!(app.view, View::Dest(_)) && app.ws_filter.is_none());
    let (place, mut sub) = (app.title(), if beside { String::new() } else { app.subtitle() });
    let count = if holds && count.is_empty() { std::mem::take(&mut sub) } else { count };
    let right = g.w - g.inset;
    let count = pen.fit(&count, Size::Small, ((right - g.inset) / 2.0).floor()); // a long state leaves the place its names
    let said = pen.text_end(right, base, &count, Size::Small, t.muted, false);
    if k == Kind::Files && app.files_pane_view().is_some() && app.folder.as_ref().is_some_and(|(_, _, rows)| rows.state.is_some()) {
        pen.hit(
            right - said - m.px(4.0),
            base - m.sup - m.px(6.0),
            said + m.px(8.0),
            m.sh + m.px(10.0),
            Target::Sort,
        );
    }
    let end = right - said - if count.is_empty() { 0.0 } else { m.px(16.0) };
    let mut names = vec![("home".to_string(), Some(Target::Home))];
    // the view of a file: its folder, then the file's own name, which is where you are
    let viewed = (app.view == View::Preview)
        .then(|| app.preview.as_ref().map(|pv| pv.row().text.clone()))
        .flatten()
        .filter(|n| !n.trim().is_empty());
    if let Some(file) = &viewed {
        names.push((place, Some(Target::Back)));
        if !sub.trim().is_empty() {
            names.push((sub, Some(Target::Back)));
        }
        names.push((file.clone(), None));
    } else if let Some(folders) = crumbs {
        names.extend(folders);
        // a path too long for the line loses its middle: the place and the folders nearest stay
        let width =
            |names: &[(String, Option<Target>)]| names.iter().map(|(n, _)| pen.width(n, Size::Small)).sum::<f64>() + (names.len() - 1) as f64 * 3.0 * m.sw;
        let mut cut = false;
        while names.len() > 4 && g.inset + width(&names) > end {
            if cut {
                names.remove(3);
            } else {
                names[2] = ("\u{2026}".to_string(), None);
                cut = true;
            }
        }
    } else if let Some(screen) = crate::appearance::modes_of(app) {
        names.push((place, Some(Target::BackBy(2))));
        names.push((screen, Some(Target::Back)));
        names.push((sub, None));
    } else if sub.trim().is_empty() {
        names.push((place, None));
    } else {
        names.push((place, (!holds).then_some(Target::Back)));
        names.push((sub, None));
    }
    let mut x = g.inset;
    let last = names.len() - 1;
    for (k, (name, target)) in names.into_iter().enumerate() {
        // the last name is cut where the count starts; an earlier one is short. A file's name is cut in its
        // middle: its type stays
        let name = if k == last && viewed.is_some() {
            cut_middle(&name, (((end - x) / m.sw).floor().max(4.0)) as usize)
        } else {
            pen.fit(&name, Size::Small, (end - x).max(0.0))
        };
        // a folder's name goes to that folder whatever the way back holds
        let live = matches!(target, Some(Target::Crumb(_))) || (target.is_some() && app.can_go_back());
        let color = if live {
            t.accent
        } else if k < last && name == "\u{2026}" {
            t.muted
        } else {
            t.ink
        };
        let w = pen.text(x, base, &name, Size::Small, color, false);
        if let Some(target) = target.filter(|_| live) {
            pen.hit(x - m.px(4.0), base - m.sup - m.px(6.0), w + m.px(8.0), m.sh + m.px(10.0), target);
        }
        x += w;
        if k < last {
            x += pen.text(x, base, " / ", Size::Small, t.muted, false);
        }
    }
    pen.fill(g.inset, m.px(PATH_RULE), g.w - 2.0 * g.inset, 1.0, t.lit);
}

/// A folder of files as the location line names it: the place, then each folder from your home down, each a
/// target but the last, which is where you are. None where the place is no folder under your home (a drive, the
/// trash, what a search found) or a page stands alone over the list: the place and its words say that.
fn crumbs(app: &App) -> Option<Vec<(String, Option<Target>)>> {
    use crate::search::b64;
    app.files_pane_view()?;
    let page = app.files_page_open() && !app.files_details_beside();
    let (_, _, rows) = app.folder.as_ref().filter(|_| !page)?;
    let here = rows.here.as_deref()?;
    let under = if rows.title == "~" { "" } else { rows.title.strip_prefix("~/")? };
    let home = if under.is_empty() {
        here
    } else {
        here.strip_suffix(under)?.strip_suffix('/')?
    };
    let uri = |path: &str| format!("spark-shell://files/rows/{}", b64(path));
    let parts: Vec<&str> = under.split('/').filter(|s| !s.is_empty()).collect();
    let mut names = vec![(app.title(), (!parts.is_empty()).then(|| Target::Crumb(uri(home))))];
    let mut at = home.to_string();
    for (k, part) in parts.iter().enumerate() {
        at = format!("{}/{}", at, part);
        names.push((part.to_string(), (k + 1 < parts.len()).then(|| Target::Crumb(uri(&at)))));
    }
    Some(names)
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
    if let Some(words) = app.view_wait() {
        return Some(Message::march(words));
    }
    let Some(r) = &app.reply else {
        // a list of files says the lit file in its row and in its details: the line says the selection alone
        let note = app.target_label().or_else(|| match k {
            Kind::Apps => None,
            Kind::Files => app.files_checked_line(),
            _ if crate::appearance::poster_lit(app) => None,
            _ => app.selected_line(),
        })?;
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

/// The key bar: each group its words and its key in a chip, Esc's first; a second line where one is too short. A key
/// that is another's for now (Enter and Esc, a trial's) keeps its place, dimmed.
struct Keys {
    groups: Vec<(f64, crate::ui::KeyGroup)>,
    taken: bool,
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
        Keys {
            groups,
            taken: app.trial_keys(),
            lines,
            room,
        }
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
            let dim = self.taken && crate::ui::trials(parts);
            let ink = if dim { t.lit } else { t.ink };
            for (text, key, actions) in parts {
                let from = x;
                if *key {
                    let w = pen.width(text, Size::Small) + m.px(16.0);
                    if !dim {
                        pen.fill(x, base - m.px(15.0), w, m.px(21.0), t.lit);
                    }
                    pen.text(x + m.px(8.0), base, text, Size::Small, ink, false);
                    x += w;
                } else {
                    let words = text.trim_end().to_lowercase();
                    x += pen.text(x, base, &words, Size::Small, ink, false) + m.px(8.0);
                }
                if dim {
                    continue;
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
    Palette(String, Vec<Rgb>),
    Color(String, String, Rgb),
    /// A group's name, small and in the accent (v0.169: one size in every list); the category a click on it
    /// shows alone.
    Head(String, Option<String>),
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
    /// What a page in a wide window is about, in large type: its name as large as its length allows, and one line
    /// of what it is under it.
    Name {
        icon: Option<Icon>,
        name: String,
        what: String,
    },
    /// Facts side by side: each one's word in the smaller face, its value under it.
    Facts(Vec<(String, String)>),
    /// A setting in one row (C3, v0.161): its name, then its options side by side.
    Choice(choice::Choice),
    /// The screens to scale (v0.167).
    Map(Box<crate::display::screens::Map>),
    /// A file or a folder in a list of files, one line as every list's row (v0.169): its name leads, then its size
    /// (a folder's count) and, where the row carries one, its own folder in the list's column, and its day at the end.
    File {
        name: String,
        /// A folder: its name ends in a slash.
        dir: bool,
        what: String,
        when: String,
        check: bool,
        muted: bool,
    },
    /// What a file shows, in a box over its details: its picture, a sound's picture with the waveform's height in
    /// it, its first lines, or the words that say why nothing is shown.
    Shown {
        picture: Option<(String, Option<u32>)>,
        lines: Vec<String>,
        say: String,
        /// A page in large type (v0.160): no box, the picture at the corner and never larger than its own pixels,
        /// a sound's waveform as a strip, the lines in the text's own size.
        large: bool,
    },
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
    /// A row's key stands in the smaller text with no box around it: a page in large type.
    bare: bool,
    /// A setting is one row, its options side by side (C3, v0.161): a page of settings.
    c3: bool,
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
    if r.id.starts_with("theme:color:") {
        if let (Some(color), Some(hex)) = (r.swatch, r.columns.first()) {
            return K::Color(r.text.clone(), hex.clone(), color);
        }
    }
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
    } else if r.end && !r.columns.is_empty() {
        End::Words(r.columns.join(crate::ui::SEP))
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
        } else if r.id.starts_with("theme:apply:") && r.sign == "check" {
            "in use".into()
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

/// A provider's row of a list of files as the row its list draws.
fn file_row(r: &crate::model::Row, check: bool) -> K {
    // the row's own columns: its size (a folder's count), its day, its folder
    let col = |k: usize| r.columns.get(k).map(String::as_str).unwrap_or("");
    let what: Vec<&str> = [col(0), col(2)].into_iter().filter(|w| !w.is_empty()).collect();
    K::File {
        name: r.text.clone(),
        dir: r.id.starts_with("files:dir:"),
        what: what.join(crate::ui::SEP),
        when: col(1).to_string(),
        check,
        muted: r.muted,
    }
}

/// A line of a page of files as a row: an action with its key, air, or words.
fn files_line(m: &Metrics, l: &files::Line) -> Option<(f64, K)> {
    if l.label.is_empty() && l.value.is_empty() && l.action.is_none() {
        return None;
    }
    if l.action.is_none() {
        return Some((m.px(22.0), K::Words(l.label.clone(), Size::Small, true, false)));
    }
    Some((
        m.px(36.0),
        K::One {
            icon: None,
            sign: "",
            swatch: vec![],
            name: l.label.clone(),
            muted: l.disabled,
            words: String::new(),
            end: End::None,
            tail: false,
            key: l.key.clone(),
        },
    ))
}

/// The rows of a list of items: each item the row its kind has, the picks counted as the app counts them.
fn rows_of(app: &App, pen: &Pen, items: &[Item], shape: Shape, room: f64) -> Vec<Row> {
    let m = pen.m;
    let picks: Vec<usize> = items.iter().enumerate().filter(|(_, it)| app.pickable_item(it)).map(|(i, _)| i).collect();
    let pick = |k: usize| picks.iter().position(|p| *p == k);
    let one = m.px(shape.one);
    let rhythm = shape.c3.then(|| choice::rhythm(app, m, items, room));
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
            Item::Heading(h) => Some((m.px(36.0), K::Head(h.clone(), None))),
            Item::Dest(d) => {
                let words = app.dest_state(*d).unwrap_or_else(|| DESTS[*d].purpose.to_string());
                Some((m.px(44.0), K::Dest(DESTS[*d].name.to_string(), words)))
            }
            Item::Setting(i) => {
                let (label, name, purpose) = SETTINGS[*i];
                let words = crate::ui::setting_words(app, label, purpose);
                // settings' own list (v0.161): two lines, as an app's row, its state under its name
                if shape.two {
                    Some((m.px(52.0), K::App(name.to_string(), words, None, String::new())))
                } else {
                    Some((one, plain(name, words, false)))
                }
            }
            Item::Step(p, name) => app
                .providers
                .get(*p)
                .and_then(|x| x.tools.iter().find(|t| &t.name == name))
                .map(|t| (one, plain(&crate::app::step_title(&t.title), t.description.clone(), false))),
            Item::More(_, n) => Some((one, plain(&format!("{} more", n), String::new(), true))),
            Item::StepOf(n) => app
                .steps_row
                .as_ref()
                .and_then(|r| r.tool.iter().chain(r.more.iter()).nth(*n))
                .map(|c| (one, plain(&app.step_words(c), String::new(), c.children.is_some()))),
            Item::Ask => {
                let words: String = app.input.split_whitespace().collect::<Vec<_>>().join(" ");
                Some((one, plain("ask spark", words, false)))
            }
            Item::Row(..) | Item::Folder(_) if shape.c3 => app.row_ref(it).map(|row| {
                if let Some(map) = &row.map {
                    (screens::height(m, 0.0), K::Map(Box::new(map.clone())))
                } else if let Some((h, c)) = rhythm.as_ref().and_then(|r| choice::of(app, m, it, room, r)) {
                    (h, K::Choice(c))
                } else if row.id.starts_with("theme:detail:") {
                    (one, K::Fact(row.text.clone(), row.columns.join(crate::ui::SEP)))
                } else if shape.two {
                    row_two(m, row, one)
                } else if app.screen_off(row) {
                    (one, of_row(&crate::model::Row { muted: true, ..row.clone() }))
                } else {
                    let mut k = of_row(row);
                    // a row that makes a new thing shows the words typed as what it will make (v0.169)
                    if let (Some(typed), K::One { words, .. }) = (app.takes_words(row), &mut k) {
                        *words = typed;
                    }
                    (one, k)
                }
            }),
            // a key of help (v0.162): what you do, the key at the row's end in the smaller text
            Item::Key(words, key) => Some((
                one,
                K::One {
                    icon: None,
                    sign: "",
                    swatch: vec![],
                    name: words.clone(),
                    muted: false,
                    words: String::new(),
                    end: End::None,
                    tail: false,
                    key: key.clone(),
                },
            )),
            Item::Hit(_) | Item::Row(..) => app.row_ref(it).map(|r| (one, of_row(r))),
            Item::Folder(_) => app.row_ref(it).map(|r| (one, file_row(r, app.files_checks_any() && app.files.checked(&r.id)))),
            Item::Files(l) => {
                let made = files_line(m, l);
                if made.is_none() {
                    gap(&mut out, m.px(12.0));
                }
                made
            }
            // the row that lands a step in the folder shown
            Item::Here => app.picking.as_ref().map(|pk| (one, plain(&pk.what, String::new(), false))),
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
                    Some((m.px(36.0), K::Head(l.label.clone(), click)))
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
    out
}

/// The rows of a page about one app, as its details are drawn: who it is first, what you do with it, a rule,
/// its facts, a rule, then its preferences. The rows keep the order the app counts its picks in.
fn about_app(app: &App, pen: &Pen, id: &str, rows: Vec<Row>, room: f64, wide: bool) -> Vec<Row> {
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
    // a wide window (v0.160): the name in large type and what it is on one line, what you do with it, its facts
    // side by side, its preferences. No rule and no box: the sizes say what leads
    if wide {
        let air = |h: f64| Row {
            h: m.px(h),
            pick: None,
            k: K::Gap(m.px(h)),
        };
        let mut out = vec![Row {
            h: m.px(220.0),
            pick: None,
            k: K::Name {
                icon: app.apps.icon_of(a),
                name: a.name.to_lowercase(),
                what,
            },
        }];
        if !matches!(app.apps.page, Page::Details(_) | Page::List | Page::Hidden) {
            out.extend(body);
            return out;
        }
        let head = body.iter().position(|r| matches!(r.k, K::Head(..))).unwrap_or(body.len());
        let (first, rest) = body.split_at(head);
        out.extend(first.iter().filter(|r| matches!(r.k, K::One { .. })).cloned());
        let pairs: Vec<(String, String)> = first
            .iter()
            .filter_map(|r| match &r.k {
                K::Fact(label, value) => Some((label.clone(), value.clone())),
                _ => None,
            })
            .collect();
        if !pairs.is_empty() {
            out.push(air(12.0));
            out.push(Row {
                h: m.px(72.0),
                pick: None,
                k: K::Facts(pairs),
            });
        }
        out.extend(first.iter().filter(|r| matches!(r.k, K::Words(..))).cloned());
        if !rest.is_empty() {
            out.push(air(8.0));
            out.extend(rest.iter().cloned());
        }
        return out;
    }
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
    let said = pen.column.take();
    // a list with a row checked (a pick list) keeps the check's room on every row, so its names stand in one line
    // and stay there as the check moves from group to group
    let checked = rows.iter().any(|r| matches!(&r.k, K::One { sign: "check", .. }));
    let mut y = area.top - off;
    for (at, row) in rows.iter().enumerate() {
        if matches!(row.k, K::Head(..)) || at == 0 {
            let group = || {
                rows[at..]
                    .iter()
                    .skip(usize::from(matches!(row.k, K::Head(..))))
                    .take_while(|r| !matches!(r.k, K::Head(..)))
            };
            let names = group()
                .filter_map(|r| match &r.k {
                    K::One { name, icon, sign, .. } => Some(
                        cells(name) as f64 * m.cw + if icon.is_some() { m.px(36.0) } else { 0.0 } + if !sign.is_empty() || checked { 2.0 * m.cw } else { 0.0 },
                    ),
                    K::Dest(name, _) => Some(cells(name) as f64 * m.cw),
                    K::File { name, dir, .. } => Some((cells(name) + usize::from(*dir)).min(30) as f64 * m.cw),
                    _ => None,
                })
                .fold(0.0, f64::max);
            column = said.unwrap_or_else(|| (m.px(24.0) + names + m.px(24.0)).clamp(m.px(176.0), ((right - area.left) * 0.55).round().max(m.px(176.0))));
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
        // a click reaches no further than the list's box
        let inside = |y: f64| y.max(area.top).min(area.bottom);
        // a column of names keeps its room for the names; in a wide window what ends a row stays beside its name
        let end = (right - m.px(if shape.two && shape.narrow { 4.0 } else { 12.0 })).min(area.left + m.px(ROW_MAX));
        // on a whole pixel: a row of an odd height would set its words half a pixel down, blurred
        let mid = (top + h / 2.0).floor();
        match &row.k {
            K::Gap(_) => {}
            K::Rule => pen.fill(area.left, top + m.px(8.0), right - area.left, 1.0, t.lit),
            K::Color(name, hex, color) => {
                let chip = m.px(22.0);
                pen.fill(x, mid - chip / 2.0, chip, chip, *color);
                let label = x + chip + m.px(10.0);
                let bound = right - m.px(8.0);
                let word = pen.fit(name, Size::Main, bound - label - m.sw * 8.0);
                pen.text(label, mid + m.up / 2.0, &word, Size::Main, t.ink, false);
                pen.text_end(bound, mid + m.sup / 2.0, hex, Size::Small, t.muted, false);
            }
            K::Palette(name, colors) => {
                let w = (right - x).max(0.0);
                pen.fill(x, top, w, h - m.px(12.0), colors[0]);
                let pad = m.px(12.0);
                let prompt = pen.text(x + pad, mid, ">", Size::Lead, colors[2], true);
                let sample = pen.fit(name, Size::Lead, w - prompt - 3.0 * pad);
                pen.text(x + prompt + 2.0 * pad, mid, &sample, Size::Lead, colors[1], false);
                let hues = &colors[2..];
                for (i, c) in hues.iter().enumerate() {
                    let edge = |n: usize| (w * n as f64 / hues.len() as f64).round();
                    pen.fill(x + edge(i), top + h - m.px(20.0), edge(i + 1) - edge(i), m.px(8.0), *c);
                }
            }
            K::Head(text, click) => {
                // a group's name, small and in the accent, as every list has it (v0.169); what follows a workspace's
                // name (this one, its screen) stands after it, muted, both cut to the room. One the list's edge
                // would cut is left out: its rows say where they are
                let w = if top + m.px(8.0) >= area.top && top + m.px(30.0) <= area.bottom {
                    let words = heading_words(text);
                    let (name, rest) = heading_parts(&words);
                    let base = top + m.px(24.0);
                    let name = pen.fit(name, Size::Small, end - x);
                    let w = pen.text(x, base, &name, Size::Small, t.accent, true);
                    let rx = x + w + m.px(12.0);
                    let rest = pen.fit(rest, Size::Small, end - rx);
                    if cells(&rest) > 1 {
                        w + m.px(12.0) + pen.text(rx, base, &rest, Size::Small, t.muted, false)
                    } else {
                        w
                    }
                } else {
                    0.0
                };
                if let Some(label) = click {
                    let (a, b) = (inside(top + m.px(6.0)), inside(top + h - m.px(2.0)));
                    pen.hit(x - m.px(6.0), a, w + m.px(12.0), b - a, Target::Head(label.clone()));
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
                } else if checked {
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
                if !key.is_empty() && shape.bare {
                    e -= pen.text_end(e, base, key, Size::Small, t.muted, false) + m.px(8.0);
                } else if !key.is_empty() {
                    let w = pen.width(key, Size::Small) + m.px(16.0);
                    pen.fill(e - w, base - m.px(15.0), w, m.px(21.0), if on { t.ground } else { t.lit });
                    pen.text(e - w + m.px(8.0), base, key, Size::Small, t.ink, false);
                    e -= w + m.px(8.0);
                }
                match at_end {
                    End::None => {}
                    End::Words(v) => {
                        // the value keeps its room while the name keeps twelve letters: a day stands whole, a long title is cut
                        let v = pen.fit(
                            v,
                            Size::Small,
                            (e - nx - pen.width(name, Size::Main).min(12.0 * m.cw) - m.px(16.0)).max(4.0 * m.sw),
                        );
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
                            let (a, b) = (inside(top), inside(top + h));
                            pen.hit(lx - aw, a, 3.0 * aw, b - a, Target::Step(n, false));
                            pen.hit(mx - aw, a, 3.0 * aw, b - a, Target::Step(n, true));
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
                let w = pen.text(x, base, label, Size::Small, t.muted, false);
                // a value longer than its room is cut in its middle: both its ends are kept
                let n = ((end - x - w - m.px(16.0)) / m.sw).floor().max(4.0) as usize;
                pen.text_end(end, base, &cut_middle(value, n), Size::Small, t.ink, false);
            }
            K::Choice(c) => choice::draw(
                pen,
                c,
                choice::At {
                    x,
                    top,
                    area,
                    pick: row.pick,
                    on,
                    focus,
                },
            ),
            K::Map(map) => screens::draw(
                app,
                pen,
                map,
                screens::At {
                    top,
                    h,
                    area,
                    pick: row.pick,
                    on,
                },
            ),
            K::Name { icon, name, what } => {
                let mut nx = x;
                if let Some(icon) = icon {
                    let side = m.px(64.0);
                    pen.icon(icon, nx, top + m.px(58.0), side);
                    nx += side + m.px(20.0);
                }
                // 72 pixels, then 48, then 32, each on the same line; a name too long for the last is cut in its middle
                let room = right - nx;
                let size = [Size::Title, Size::Title2, Size::Title3]
                    .into_iter()
                    .find(|s| pen.width(name, *s) <= room)
                    .unwrap_or(Size::Title3);
                let n = (room / m.adv(size)).floor().max(4.0) as usize;
                pen.text(nx, top + m.px(115.0), &cut_middle(name, n), size, t.ink, false);
                let what = pen.fit(what, Size::Lead, room);
                pen.text(nx, top + m.px(165.0), &what, Size::Lead, t.muted, false);
            }
            K::Facts(pairs) => {
                let mut fx = x;
                for (label, value) in pairs {
                    if right - fx < 6.0 * m.cw {
                        break;
                    }
                    pen.text(fx, top + m.px(28.0), label, Size::Small, t.muted, false);
                    let value = pen.fit(value, Size::Main, right - fx);
                    let w = pen.text(fx, top + m.px(54.0), &value, Size::Main, t.ink, false);
                    fx += w.max(pen.width(label, Size::Small)).max(m.px(96.0)) + m.px(56.0);
                }
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
            K::File {
                name,
                dir,
                what,
                when,
                check,
                muted,
            } => {
                let base = mid + m.px(6.0);
                if *check {
                    pen.text(x - 2.0 * m.cw, base, crate::ui::CHECK, Size::Main, t.accent, false);
                }
                // from the end backward: its day; then the name, cut in its middle so its type stays, a folder's slash
                // after it, muted; then what it holds in the list's column
                let e = if when.is_empty() {
                    end
                } else {
                    end - pen.text_end(end, base, when, Size::Small, t.muted, false) - m.px(16.0)
                };
                let slash = if *dir { m.cw } else { 0.0 };
                let wx = (area.left + column).max(x + 6.0 * m.cw);
                let room = if what.is_empty() { e - x } else { wx - m.px(16.0) - x };
                let cells_wide = ((room - slash) / m.cw).floor().max(4.0) as usize;
                let w = pen.text(x, base, &cut_middle(name, cells_wide), Size::Main, if *muted { t.muted } else { t.ink }, on);
                if *dir {
                    pen.text(x + w, base, "/", Size::Main, t.muted, false);
                }
                if !what.is_empty() {
                    let what = pen.fit(what, Size::Small, e - wx);
                    pen.text(wx, base, &what, Size::Small, t.muted, false);
                }
                if on && focus {
                    pen.fill(x, base + m.px(5.0), w, 2.0, t.accent);
                }
            }
            K::Shown {
                picture,
                lines,
                say,
                large: true,
            } => {
                let (bw, bh) = (right - x, (top + h).min(area.bottom) - top);
                if let Some((file, wave)) = picture {
                    pen.pictures.push(PictureAt {
                        x,
                        y: top,
                        w: bw,
                        h: if wave.is_some() { bh.min(m.px(140.0)) } else { bh },
                        file: file.clone(),
                        wave: *wave,
                        corner: true,
                    });
                } else if !lines.is_empty() {
                    let pitch = m.px(26.0);
                    for (i, l) in lines.iter().take((bh / pitch).floor().max(0.0) as usize).enumerate() {
                        let l = pen.fit(l, Size::Main, bw);
                        pen.text(x, top + m.up + i as f64 * pitch, &l, Size::Main, t.ink, false);
                    }
                } else if !say.is_empty() {
                    let say = pen.fit(say, Size::Main, bw);
                    pen.text(x, top + m.up, &say, Size::Main, t.muted, false);
                }
            }
            K::Shown { picture, lines, say, .. } => {
                let (bx, by, bw, bh) = (area.left, top + m.px(16.0), right - area.left, h - m.px(16.0));
                pen.fill(bx, by, bw, bh, t.lit);
                if let Some((file, wave)) = picture {
                    pen.pictures.push(PictureAt {
                        x: bx,
                        y: by,
                        w: bw,
                        h: bh,
                        file: file.clone(),
                        wave: *wave,
                        corner: false,
                    });
                } else if !lines.is_empty() {
                    let n = ((bh - m.px(16.0)) / m.sh).floor().max(0.0) as usize;
                    for (i, l) in lines.iter().take(n).enumerate() {
                        let l = pen.fit(l, Size::Small, bw - m.px(24.0));
                        pen.text(bx + m.px(12.0), by + m.px(8.0) + m.sup + i as f64 * m.sh, &l, Size::Small, t.ink, false);
                    }
                } else if !say.is_empty() {
                    let said = crate::ui::wrap(say, ((bw - m.px(24.0)) / m.sw).floor().max(8.0) as usize);
                    let first = by + ((bh - said.len() as f64 * m.sh) / 2.0).round().max(m.px(8.0)) + m.sup;
                    for (i, l) in said.iter().enumerate() {
                        pen.text(bx + m.px(12.0), first + i as f64 * m.sh, l, Size::Small, t.muted, false);
                    }
                }
            }
        }
    }
    let over = std::mem::take(&mut pen.over);
    pen.steps.extend(over);
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
/// Nor while a step asks for a value: the prompt holds the keys then, and the row that asked stays lit under it.
fn list_focus(app: &App) -> bool {
    app.in_list && app.chip_focus.is_none() && !app.prompt_form() && (app.list_keys || (app.input.is_empty() && app.view != View::Home))
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
        bare: false,
        c3: false,
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
        bare: false,
        c3: false,
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
    // a wide window: the list keeps its column, the lit app has the rest, in large type, and no line stands between
    let wide = wide(&m, g.w);
    let pane_w = ((g.w - 2.0 * g.inset) * 0.5).round().clamp(m.px(280.0), m.px(440.0));
    let divide = if wide { m.px(WIDE_LIST) } else { whole.right - pane_w - m.px(16.0) };
    // beside each other, a bar ends at the line between them
    let left = Area {
        right: divide - m.px(if wide { 24.0 } else { 16.0 }),
        to: divide,
        ..whole
    };
    let right = Area {
        left: if wide { m.px(WIDE_PAGE) } else { divide + m.px(16.0) },
        from: if wide { m.px(WIDE_PAGE) - m.px(12.0) } else { divide + 1.0 },
        ..whole
    };
    let between = |pen: &mut Pen| {
        if !wide {
            pen.fill(divide, whole.top + m.px(8.0), 1.0, whole.bottom - whole.top - m.px(16.0), pen.t.lit);
        }
    };
    let narrow = Shape {
        two: true,
        one: 44.0,
        narrow: true,
        still: false,
        pad: 24.0,
        bare: false,
        c3: false,
    };
    let page = Shape {
        two: false,
        one: 36.0,
        narrow: true,
        still: false,
        pad: 12.0,
        bare: false,
        c3: false,
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
            between(pen);
            let about = Page::Details(id.clone());
            let lines: Vec<Item> = app.apps.lines_of(&about, 60, "", 0).into_iter().map(Item::Apps).collect();
            let still = Shape { still: true, ..page };
            let rows = about_app(app, pen, &id, rows_of(app, pen, &lines, still, room(right)), room(right), wide);
            let off = list(app, pen, &rows, right, None, false, still, 0, named(&about, ""));
            pane_targets(pen, &rows, right, off);
        }
        // a wide window with no app lit (the line holds the keys, or a row that is no app): the list keeps its
        // column, so nothing moves when an app is lit
        (true, true, _) if wide => {
            let rows = rows_of(app, pen, items, narrow, room(left));
            list(app, pen, &rows, left, lit(app), list_focus(app), narrow, app.scroll, own);
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
            between(pen);
            let rows = about_app(app, pen, &id, rows_of(app, pen, items, page, room(right)), room(right), wide);
            list(app, pen, &rows, right, lit(app), list_focus(app), page, app.scroll, own);
        }
        // a page about an app, alone: who it is first
        (_, false, Some(id)) => {
            let rows = about_app(app, pen, &id, rows_of(app, pen, items, full, room(whole)), room(whole), false);
            list(app, pen, &rows, whole, lit(app), list_focus(app), full, app.scroll, own);
        }
        _ => {
            let rows = rows_of(app, pen, items, full, room(whole));
            list(app, pen, &rows, whole, lit(app), list_focus(app), full, app.scroll, own);
        }
    }
}

/// Keep the poster in view while the list scrolls. A wide frame gives each its own column.
fn theme_poster(app: &App, pen: &mut Pen, whole: Area, row: &crate::model::Row) -> Area {
    let m = *pen.m;
    let width = whole.right - whole.left;
    let height = whole.bottom - whole.top;
    let side = width >= m.px(760.0);
    if height < m.px(180.0) && !side {
        return whole;
    }
    let (left, right, top, list_area) = if side {
        let divide = whole.left + (width * 0.40).round();
        (
            divide + m.px(24.0),
            whole.right,
            whole.top + m.px(14.0),
            Area {
                right: divide - m.px(12.0),
                to: divide,
                ..whole
            },
        )
    } else {
        (whole.left, whole.right, whole.top + m.px(4.0), whole)
    };
    let w = right - left;
    let cap = if side {
        height - m.px(110.0)
    } else {
        (height * 0.50 - m.px(10.0)).max(m.px(52.0))
    };
    let h = (w * 9.0 / 16.0).min(cap).max(m.px(32.0)).round();
    let pw = w.min((h * 16.0 / 9.0).round());
    let x = left + ((w - pw) / 2.0).round();
    let page = app
        .files
        .peek
        .as_ref()
        .filter(|peek| Some(&peek.uri) == row.page.as_ref())
        .and_then(|peek| peek.page.as_ref());
    pen.fill(left, top, w, h, row.chip.first().copied().unwrap_or(pen.t.band));
    if let Some(file) = page.and_then(|p| p.picture.as_ref()) {
        pen.pictures.push(PictureAt {
            x,
            y: top,
            w: pw,
            h,
            file: file.clone(),
            wave: None,
            corner: false,
        });
    } else {
        let word = page.and_then(|p| p.say.as_deref()).unwrap_or(if page.is_some() {
            "Wallpaper preview unavailable"
        } else {
            "Loading wallpaper"
        });
        let label = pen.fit(word, Size::Small, w - m.px(24.0));
        let ink = row.chip.get(1).copied().unwrap_or(pen.t.ink);
        pen.text(left + m.px(12.0), top + h / 2.0 + m.sup / 2.0, &label, Size::Small, ink, false);
    }
    // A collection has a featured poster, not an applied palette of its own.
    if !row.id.starts_with("theme:room:") {
        let hues = row.chip.get(2..).unwrap_or_default();
        for (i, color) in hues.iter().enumerate() {
            let edge = |n: usize| (w * n as f64 / hues.len() as f64).round();
            pen.fill(left + edge(i), top + h, edge(i + 1) - edge(i), m.px(4.0), *color);
        }
    }
    let name = if row.id == "theme:gallery:open" {
        row.columns.first().map(String::as_str).unwrap_or(&row.text)
    } else if row.id.starts_with("theme:apply:") {
        app.folder.as_ref().map(|f| f.2.title.as_str()).unwrap_or(&row.text)
    } else {
        &row.text
    };
    let room = row.id.starts_with("theme:room:");
    let caption = if room {
        row.columns.first().map(String::as_str).unwrap_or("")
    } else {
        page.and_then(|pg| pg.facts.first()).map(String::as_str).unwrap_or("")
    };
    let base = top + h + m.px(32.0);
    let label = pen.fit(name, Size::Lead, w * 0.62);
    pen.text(left, base, &label, Size::Lead, pen.t.ink, true);
    let caption = pen.fit(caption, Size::Small, w * 0.34);
    pen.text_end(right, base, &caption, Size::Small, pen.t.muted, false);
    let mut bottom = base;
    // a work's own page says its kind under its name where its row has the words (v0.172), as the list before it did
    if !row.id.starts_with("theme:apply:") || row.line.as_ref().is_some_and(|l| !l.is_empty()) {
        bottom += m.px(23.0);
        // a collection's description, a work's kind (pixel scene, dark): the lit row's line is the poster's;
        // the theme in use, with none, says its palette
        // a palette whose reference is its own title says it once, in the name over this line (v0.172)
        let line = row.line.clone().filter(|l| !l.is_empty()).or_else(|| {
            (!room)
                .then(|| page.and_then(|pg| pg.facts.get(1)))
                .flatten()
                .filter(|reference| reference.as_str() != name)
                .map(|reference| format!("Palette  {reference}"))
        });
        if let Some(line) = line {
            let label = pen.fit(&line, Size::Small, w);
            pen.text(left, bottom, &label, Size::Small, pen.t.muted, false);
        }
    }
    let palette = row.id.starts_with("theme:entry:") || row.id.starts_with("theme:apply:");
    let strip = if palette { m.px(8.0) } else { 0.0 };
    pen.hit(left, top, w, h - strip, Target::Key(HintKey::View));
    if palette {
        pen.hit(left, top + h - strip, w, bottom + m.px(12.0) - (top + h - strip), Target::Key(HintKey::Open));
    }
    if side {
        list_area
    } else {
        Area {
            top: bottom + m.px(16.0),
            ..list_area
        }
    }
}

/// The wallpaper list's picture (v0.172): the wallpaper of the row lit, or the one in use, over the list, its name
/// under it. The list named its wallpapers and showed none of them. The box keeps its place and size as the row
/// lit changes; the list has what is under it.
fn wall_poster(pen: &mut Pen, whole: Area, row: &crate::model::Row) -> Area {
    let m = *pen.m;
    let (w, height) = (whole.right - whole.left, whole.bottom - whole.top);
    if height < m.px(360.0) {
        return whole;
    }
    let top = whole.top + m.px(4.0);
    let h = (w * 9.0 / 16.0).min(height * 0.45).max(m.px(32.0)).round();
    let pw = w.min((h * 16.0 / 9.0).round());
    pen.fill(whole.left, top, w, h, row.chip.first().copied().unwrap_or(pen.t.band));
    if let Some(file) = row.preview.as_ref().filter(|f| std::path::Path::new(f).is_file()) {
        pen.pictures.push(PictureAt {
            x: whole.left + ((w - pw) / 2.0).round(),
            y: top,
            w: pw,
            h,
            file: file.clone(),
            wave: None,
            corner: false,
        });
    }
    let base = top + h + m.px(32.0);
    let label = pen.fit(&row.text, Size::Lead, w * 0.62);
    pen.text(whole.left, base, &label, Size::Lead, pen.t.ink, true);
    let caption = pen.fit(row.columns.first().map(String::as_str).unwrap_or(""), Size::Small, w * 0.34);
    pen.text_end(whole.right, base, &caption, Size::Small, pen.t.muted, false);
    Area {
        top: base + m.px(16.0),
        ..whole
    }
}

/// A section's page (v0.161): a setting one row, its options side by side, the one in use in the accent; the
/// groups named large, as settings' are.
fn page(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let m = *pen.m;
    let whole = Area {
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
        bare: true,
        c3: true,
    };
    if let Some(p) = &app.picker {
        return picker(app, pen, whole, p);
    }
    if matches!(&app.view, View::Folder(_, uri) if uri.starts_with(crate::appearance::PALETTES) || uri == crate::appearance::COLORS)
        && app.query().is_empty()
        && whole.right - whole.left >= m.px(460.0)
        && whole.bottom - whole.top >= m.px(580.0)
    {
        return terminal_colors(app, pen, whole, shape);
    }
    let candidate = crate::appearance::candidate(app).map(|(_, row)| row);
    let area = match (candidate, crate::appearance::wallpaper(app)) {
        (Some(r), _) => theme_poster(app, pen, whole, r),
        (None, Some(r)) => wall_poster(pen, whole, r),
        (None, None) => whole,
    };
    // a work's page shows the rows its provider gives, each one (v0.172). It once left out what a theme keeps as
    // it is, and with those every row that had no second words: Duplicate was no longer drawn and still took the
    // keys, so the row lit was not the row Enter ran, and a click on Export duplicated the theme
    let mut rows = rows_of(app, pen, items, shape, area.right - area.left - m.px(36.0));
    for r in rows.iter_mut().filter(|r| matches!(r.k, K::Map(_))) {
        r.h = screens::height(&m, area.bottom - area.top);
    }
    if crate::appearance::display(app) {
        // the words of a row with no options stand at the options' column, where half the room is left for them
        let room = area.right - area.left - m.px(36.0);
        let column = choice::rhythm(app, &m, items, room).column;
        pen.column = (column <= room / 2.0).then_some(m.px(24.0) + column);
    }
    if candidate.is_none() && crate::appearance::gallery(&app.view) && app.input.is_empty() {
        if let Some((_, _, folder)) = &app.folder {
            if let Some(r) = folder.rows.first().filter(|r| r.id.starts_with("theme:apply:") && r.chip.len() >= 3) {
                rows.insert(
                    0,
                    Row {
                        h: m.px(84.0),
                        pick: None,
                        k: K::Palette(folder.title.clone(), r.chip.clone()),
                    },
                );
            }
        }
    }
    let key = format!("page\u{1f}{:?}\u{1f}{}", app.view, app.input);
    list(app, pen, &rows, area, lit(app), list_focus(app), shape, app.scroll, key);
}

/// A color being picked (v0.172), in place of the page that asked: a sample of it, what it was beside what it is
/// and how that reads, then a strip of swatches each for its hue, its shade and its strength, and the list's other
/// colors to take as they are. The strip the arrows are on is lit as a row is, and the swatch in use wears the line
/// a chosen value wears. The prompt above holds the color's value, to type one.
fn picker(app: &App, pen: &mut Pen, whole: Area, p: &crate::picker::Picker) {
    use crate::picker::Strip;
    let (m, t) = (*pen.m, pen.t);
    let row = app.asking_row();
    let now = p.value();
    let name = row.map_or("color", |r| r.text.as_str()).to_string();
    let key = row.and_then(|r| r.id.strip_prefix("theme:color:")).map(str::to_string);
    let wide = whole.right - whole.left;
    let mut top = whole.top;
    // the sample: a theme's color in the words a terminal shows in it, the color picked in its own place; a color
    // those words do not wear is its own name, written in it
    let of = |k: &str| {
        if key.as_deref() == Some(k) {
            return Some(now);
        }
        let id = format!("theme:color:{}", k);
        app.folder.as_ref()?.2.rows.iter().find(|r| r.id == id)?.swatch
    };
    let block = m.px(66.0);
    if let (Some(k), Some(bg), Some(fg), Some(accent), Some(blue), Some(green)) = (key.as_deref(), of("BG"), of("FG"), of("ACCENT"), of("ANSI_4"), of("ANSI_2"))
    {
        let x = whole.left + m.px(14.0);
        pen.fill(whole.left, top, wide, block, bg);
        let prompt = pen.text(x, top + m.px(24.0), "spark>", Size::Main, accent, true);
        pen.text(x + prompt + m.cw, top + m.px(24.0), "ls", Size::Main, fg, false);
        let y = top + m.px(50.0);
        let src = pen.text(x, y, "src/", Size::Main, blue, false);
        let readme = pen.text(x + src + 2.0 * m.cw, y, "README.md", Size::Main, fg, false);
        pen.text(x + src + readme + 4.0 * m.cw, y, "build", Size::Main, green, false);
        if !matches!(k, "BG" | "FG" | "ACCENT" | "ANSI_4" | "ANSI_2") {
            let word = name.split_whitespace().last().unwrap_or("color");
            pen.text_end(whole.right - m.px(14.0), top + m.px(24.0), word, Size::Main, now, false);
        }
    } else {
        pen.fill(whole.left, top, wide, block, now);
    }
    top += m.px(74.0);
    // what it was, touching what it is; its name; how it reads on the color it stands against
    let one = m.px(44.0);
    let x = whole.left + m.px(8.0);
    let chip = m.px(22.0);
    let mid = (top + one / 2.0).floor();
    pen.fill(x, mid - chip / 2.0, chip, chip, p.was);
    pen.fill(x + chip, mid - chip / 2.0, chip, chip, now);
    let label = x + 2.0 * chip + m.px(10.0);
    let said = p.contrast().map(|c| {
        let ratio = format!("{}.{}:1", c / 100, (c % 100) / 10);
        if c < 450 {
            (format!("contrast {}, hard to read", ratio), t.alarm)
        } else {
            (format!("contrast {}", ratio), t.muted)
        }
    });
    let end = whole.right - m.px(8.0);
    let taken = said
        .as_ref()
        .map_or(0.0, |(s, color)| pen.text_end(end, mid + m.sup / 2.0, s, Size::Small, *color, false));
    let word = pen.fit(&name, Size::Main, end - taken - label - m.cw);
    pen.text(label, mid + m.up / 2.0, &word, Size::Main, t.ink, false);
    top += one;
    // the strips: a name, then its swatches from one column, each as wide as the room allows
    let column = x + 12.0 * m.cw;
    for strip in p.strips() {
        let words = match strip {
            Strip::Hue => "hue",
            Strip::Shade => "shade",
            Strip::Strength => "strength",
            Strip::Theirs => "this theme",
        };
        let (swatches, at, on) = (p.swatches(strip), p.at(strip), p.strip == strip);
        let mid = (top + one / 2.0).floor();
        if on {
            pen.fill(whole.from, top, whole.to - whole.from, one, t.lit);
        }
        let w = pen.text(x, mid + m.up / 2.0, words, Size::Main, t.ink, on);
        if on {
            pen.fill(x, mid + m.px(12.0), w, 2.0, t.accent);
        }
        let n = swatches.len().max(1);
        let pitch = ((end - column) / n as f64).floor().min(m.px(30.0)).max(4.0);
        let (side, tall) = ((pitch - m.px(4.0)).max(2.0), m.px(20.0));
        for (i, c) in swatches.iter().enumerate() {
            let cx = column + i as f64 * pitch;
            // a swatch the ground would hide stands on a hairline of its own
            if (0..3).all(|k| (i32::from(c[k]) - i32::from(if on { t.lit[k] } else { t.ground[k] })).abs() < 14) {
                pen.fill(cx - 1.0, mid - tall / 2.0 - 1.0, side + 2.0, tall + 2.0, t.muted);
            }
            pen.fill(cx, mid - tall / 2.0, side, tall, *c);
            // the swatch of the color as it is: the line a chosen value wears; the theme's own only while it is that color
            if i == at && (strip != Strip::Theirs || *c == now) {
                pen.fill(cx, mid + tall / 2.0 + m.px(3.0), side, 2.0, t.accent);
            }
            pen.hit(cx, top, pitch, one, Target::Swatch(strip, i));
        }
        top += one;
    }
}

/// Pair normal and bright terminal colors so the same ANSI hue lines up across columns.
fn terminal_colors(app: &App, pen: &mut Pen, whole: Area, shape: Shape) {
    let m = *pen.m;
    let shape = Shape { one: 44.0, pad: 8.0, ..shape };
    let mid = ((whole.left + whole.right) / 2.0).round();
    let head = |s: &str| Row {
        h: m.px(32.0),
        pick: None,
        k: K::Head(s.into(), None),
    };
    let mut columns = [vec![head("Base colors")], vec![head("Accents")]];
    let mut export = Vec::new();
    // the theme's other variant: beside another theme's colors, in the second column (v0.172)
    let mut beside = Vec::new();
    for (i, it) in app.picks().iter().enumerate() {
        let Some(r) = app.row_ref(it) else { continue };
        let row = Row {
            h: m.px(shape.one),
            pick: Some(i),
            k: of_row(r),
        };
        match r.id.as_str() {
            "theme:palette:export" | "theme:colors:from" => export.push(row),
            "theme:colors:pair" => beside.push(Row {
                k: of_row(&crate::model::Row { columns: vec![], ..r.clone() }),
                ..row
            }),
            "theme:color:BG" | "theme:color:FG" => columns[0].push(row),
            "theme:color:ACCENT" | "theme:color:MUTED" => columns[1].push(row),
            id => {
                let Some(n) = id.strip_prefix("theme:color:ANSI_").and_then(|s| s.parse::<usize>().ok()).filter(|n| *n < 16) else {
                    continue;
                };
                let column = &mut columns[n / 8];
                if n % 8 == 0 {
                    column.push(head(if n == 0 { "ANSI regular" } else { "ANSI bright" }));
                }
                column.push(row);
            }
        }
    }
    let mut controls = whole;
    if whole.bottom - whole.top >= m.px(654.0) {
        let color = |id: &str| app.folder.as_ref()?.2.rows.iter().find(|r| r.id == id)?.swatch;
        if let (Some(bg), Some(fg), Some(accent), Some(blue), Some(green)) = (
            color("theme:color:BG"),
            color("theme:color:FG"),
            color("theme:color:ACCENT"),
            color("theme:color:ANSI_4"),
            color("theme:color:ANSI_2"),
        ) {
            let x = whole.left + m.px(14.0);
            pen.fill(whole.left, whole.top, whole.right - whole.left, m.px(66.0), bg);
            let prompt = pen.text(x, whole.top + m.px(24.0), "spark>", Size::Main, accent, true);
            pen.text(x + prompt + m.cw, whole.top + m.px(24.0), "ls", Size::Main, fg, false);
            let y = whole.top + m.px(50.0);
            let src = pen.text(x, y, "src/", Size::Main, blue, false);
            let readme = pen.text(x + src + 2.0 * m.cw, y, "README.md", Size::Main, fg, false);
            pen.text(x + src + readme + 4.0 * m.cw, y, "build", Size::Main, green, false);
            controls.top += m.px(74.0);
        }
    }
    if let Some(reference) = app
        .folder
        .as_ref()
        .and_then(|f| f.2.rows.iter().find(|r| r.id == "theme:palette:reference"))
        .and_then(|r| r.columns.first())
    {
        let x = whole.left + m.px(8.0);
        let y = controls.top + m.px(21.0);
        let label = pen.text(x, y, "Palette reference", Size::Small, pen.t.muted, false);
        let start = x + label + m.cw;
        let value = pen.fit(reference, Size::Small, whole.right - start);
        pen.text(start, y, &value, Size::Small, pen.t.ink, true);
        controls.top += m.px(32.0);
    }
    let top = controls.top + m.px(shape.one);
    let first = if beside.is_empty() {
        Area { bottom: top, ..controls }
    } else {
        Area {
            bottom: top,
            right: mid - m.px(8.0),
            to: mid,
            ..controls
        }
    };
    list(app, pen, &export, first, lit(app), list_focus(app), shape, 0, "palette/export".into());
    if !beside.is_empty() {
        let second = Area {
            bottom: top,
            left: mid + m.px(8.0),
            from: mid,
            ..controls
        };
        list(app, pen, &beside, second, lit(app), list_focus(app), shape, 0, "palette/beside".into());
    }
    for (i, rows) in columns.iter().enumerate() {
        let area = if i == 0 {
            Area {
                top,
                right: mid - m.px(8.0),
                to: mid,
                ..whole
            }
        } else {
            Area {
                top,
                left: mid + m.px(8.0),
                from: mid,
                ..whole
            }
        };
        list(app, pen, rows, area, lit(app), list_focus(app), shape, 0, format!("palette/{i}"));
    }
}

/// A provider's row as a place's page has it (v0.162): a row of words that is no control is two lines, its name over
/// its words, as an app's row is; any other row is the row of_row draws.
fn row_two(m: &Metrics, r: &crate::model::Row, one: f64) -> (f64, K) {
    let plain = r.step.is_none()
        && r.switch.is_none()
        && !r.choice
        && r.key.is_none()
        && r.swatch.is_none()
        && r.chip.is_empty()
        && matches!(r.sign.as_str(), "" | "blank" | "-" | "opens")
        && r.columns.iter().any(|c| !c.is_empty());
    if plain {
        let words = r.columns.iter().filter(|c| !c.is_empty()).cloned().collect::<Vec<_>>().join(crate::ui::SEP);
        (m.px(52.0), K::App(r.text.clone(), words, None, String::new()))
    } else {
        (one, of_row(r))
    }
}

/// The shape of a place's rows (v0.169, as home's): a row one line, its name and what it holds now in a column, a
/// setting one row, a key at the row's end in the smaller text with no box.
const PLACE_SHAPE: Shape = Shape {
    two: false,
    one: 44.0,
    narrow: false,
    still: false,
    pad: 24.0,
    bare: true,
    c3: true,
};

/// A place of home in the new type (v0.162): workspaces, notes, system, help and power.
fn place(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let m = *pen.m;
    let whole = Area {
        left: g.inset,
        right: g.w - g.inset,
        top: g.top,
        bottom: g.bottom,
        from: 0.0,
        to: g.w,
    };
    let key = format!("place\u{1f}{:?}\u{1f}{}", app.view, app.input);
    // help in a wide window is a sheet of its keys: its groups in columns, a column a group or more, as even as they go
    let cols = ((whole.right - whole.left) / m.px(600.0)).floor() as usize;
    if app.view == View::Help && wide(&m, g.w) && cols >= 2 {
        let col_w = ((whole.right - whole.left) / cols as f64).floor();
        let rows = place_rows(app, pen, items, col_w - m.px(48.0));
        let mut groups: Vec<Vec<Row>> = vec![];
        for r in rows {
            if matches!(r.k, K::Head(..)) || groups.is_empty() {
                groups.push(vec![]);
            }
            if let Some(gr) = groups.last_mut() {
                gr.push(r);
            }
        }
        let total: f64 = groups.iter().flatten().map(|r| r.h).sum();
        let per = total / cols as f64;
        let mut columns: Vec<Vec<Row>> = vec![vec![]];
        for gr in groups {
            let h: f64 = columns.last().map(|c| c.iter().map(|r| r.h).sum()).unwrap_or(0.0);
            if h > 0.0 && h + gr.iter().map(|r| r.h).sum::<f64>() / 2.0 > per && columns.len() < cols {
                columns.push(vec![]);
            }
            if let Some(c) = columns.last_mut() {
                c.extend(gr);
            }
        }
        for (k, c) in columns.iter().enumerate() {
            let from = whole.left + k as f64 * col_w;
            let area = Area {
                left: from,
                right: from + col_w - m.px(24.0),
                from: if k == 0 { 0.0 } else { from },
                to: if k + 1 == columns.len() { g.w } else { from + col_w },
                ..whole
            };
            list(app, pen, c, area, lit(app), list_focus(app), PLACE_SHAPE, 0, format!("{key}\u{1f}{k}"));
        }
        return;
    }
    let rows = place_rows(app, pen, items, whole.right - whole.left - m.px(36.0));
    list(app, pen, &rows, whole, lit(app), list_focus(app), PLACE_SHAPE, app.scroll, key);
}

/// A place's rows (v0.169), as home's places are: no arrow on a row that opens a page, since every row of a place
/// opens or does something; a choice keeps the arrow after what it holds.
fn place_rows(app: &App, pen: &Pen, items: &[Item], room: f64) -> Vec<Row> {
    let mut rows = rows_of(app, pen, items, PLACE_SHAPE, room);
    for r in rows.iter_mut() {
        if let K::One { tail, end: End::None, .. } = &mut r.k {
            *tail = false;
        }
    }
    rows
}

/// A group's name, its number said once: a workspace's name carries its number framed as the bar draws
/// it ("workspace 1 {1}"), which large type repeats for nothing.
fn heading_words(text: &str) -> String {
    let words: Vec<&str> = text.split(' ').collect();
    let mut out: Vec<&str> = vec![];
    for (i, w) in words.iter().enumerate() {
        let inner: String = w.chars().filter(|c| c.is_alphanumeric()).collect();
        let framed = !inner.is_empty() && inner.len() < w.len() && i > 0 && words[i - 1] == inner;
        if !framed {
            out.push(w);
        }
    }
    out.join(" ")
}

/// A group's name and what follows it, split at the first middle dot the provider joins them with:
/// "workspace 1", then its label, "this one" and its screen (v0.162.1).
fn heading_parts(words: &str) -> (&str, &str) {
    words.split_once(" \u{b7} ").unwrap_or((words, ""))
}

/// A month's block in the Calendar (v0.162): its name, the days' initials, six weeks' room.
const MONTH_W: f64 = 280.0;
const MONTH_H: f64 = 44.0 + 24.0 + 6.0 * 34.0;
const MONTH_AIR: f64 = 48.0;

/// Where the Calendar's rows start: under the time and the day, and under the months.
fn calendar_top(app: &App, m: &Metrics, g: &Geo) -> f64 {
    g.top + if app.today.is_some() { m.px(DAY_H) } else { 0.0 } + m.px(MONTH_H) + m.px(20.0)
}

/// Today's block over the months (v0.169): its weekday small in the accent, its date in large type.
const DAY_H: f64 = 84.0;

/// The Calendar (v0.169): today leads, its weekday small in the accent over its date in large type (the bar says
/// the time); then as many months side by side as the window holds, each named as a group is, today in the accent
/// and underlined, a day with a reminder in the accent; then its rows (the reminders, a new reminder, the time).
/// Left and Right move the months.
fn calendar(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    use crate::calendar::{shift, weekday, weeks_from, ymd, DAYS, MONTHS};
    const WEEKDAYS: [&str; 7] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    let m = *pen.m;
    let t = pen.t;
    let x0 = g.inset + m.px(24.0);
    let mut y = g.top;
    if let Some((ty, tm, td)) = app.today {
        pen.text(x0, y + m.px(24.0), WEEKDAYS[weekday(ty, tm, td) as usize % 7], Size::Small, t.accent, true);
        let day = format!("{} {} {}", td, MONTHS[(tm - 1) as usize], ty);
        let day = pen.fit(&day, Size::Title3, g.w - g.inset - x0);
        pen.text(x0, y + m.px(64.0), &day, Size::Title3, t.ink, false);
        y += m.px(DAY_H);
    }
    let dated: Vec<(i32, u32, u32)> = app
        .providers
        .iter()
        .find(|p| p.label == "reminders")
        .map(|p| p.rows.rows.iter().filter_map(|r| ymd(r.date.as_deref()?)).collect())
        .unwrap_or_default();
    if let Some((ty, tm, td)) = app.today {
        let step = m.px(MONTH_W + MONTH_AIR);
        let across = ((g.w - 2.0 * g.inset - m.px(24.0) + m.px(MONTH_AIR)) / step).floor().max(1.0) as i32;
        let cw = m.px(MONTH_W) / 7.0;
        for k in 0..across {
            let mx = x0 + k as f64 * step;
            let (yr, mo) = shift(ty, tm, app.month_offset + k);
            pen.text(
                mx,
                y + m.px(24.0),
                &format!("{} {}", MONTHS[(mo - 1) as usize], yr),
                Size::Small,
                t.accent,
                true,
            );
            for i in 0..7 {
                let d = DAYS[(i + usize::from(app.monday_first)) % 7];
                pen.text_end(mx + (i + 1) as f64 * cw - m.px(10.0), y + m.px(62.0), d, Size::Small, t.muted, false);
            }
            for (w, wk) in weeks_from(yr, mo, app.monday_first).iter().enumerate() {
                let base = y + m.px(68.0) + (w + 1) as f64 * m.px(34.0) - m.px(10.0);
                for (i, d) in wk.iter().enumerate() {
                    let Some(d) = d else { continue };
                    let today = (yr, mo, *d) == (ty, tm, td);
                    let marked = dated.contains(&(yr, mo, *d));
                    let n = d.to_string();
                    let right = mx + (i + 1) as f64 * cw - m.px(10.0);
                    let color = if today || marked { t.accent } else { t.ink };
                    let wd = pen.text_end(right, base, &n, Size::Main, color, today);
                    if today {
                        pen.fill(right - wd, base + m.px(5.0), wd, 2.0, t.accent);
                    }
                }
            }
        }
    }
    let whole = Area {
        left: g.inset,
        right: g.w - g.inset,
        top: calendar_top(app, &m, g),
        bottom: g.bottom,
        from: 0.0,
        to: g.w,
    };
    let rows = place_rows(app, pen, items, whole.right - whole.left - m.px(36.0));
    let key = format!("calendar\u{1f}{}", app.input);
    list(app, pen, &rows, whole, lit(app), list_focus(app), PLACE_SHAPE, app.scroll, key);
}

/// Settings (v0.169, as home): its groups named small, a setting one line, its name and what it is set to now in a
/// column. What was typed finds settings with no headings, in the same rows.
fn settings(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let m = *pen.m;
    let whole = Area {
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
        bare: false,
        c3: false,
    };
    // a wide window (v0.161): the list keeps its column, the lit setting's page stands beside it in large type, as an
    // app's and a file's do; a click on it opens the setting
    let lit_setting = match app.picks().get(app.sel).filter(|_| app.in_list && app.input.is_empty()) {
        Some(Item::Setting(i)) => Some(*i),
        _ => None,
    };
    let key = format!("settings\u{1f}{}", app.input);
    let Some(i) = lit_setting.filter(|_| wide(&m, g.w)) else {
        let rows = rows_of(app, pen, items, shape, whole.right - whole.left - m.px(36.0));
        list(app, pen, &rows, whole, lit(app), list_focus(app), shape, app.scroll, key);
        return;
    };
    let divide = m.px(WIDE_LIST);
    let left = Area {
        right: divide - m.px(24.0),
        to: divide,
        ..whole
    };
    let rows = rows_of(app, pen, items, shape, left.right - left.left - m.px(36.0));
    list(app, pen, &rows, left, lit(app), list_focus(app), shape, app.scroll, key);
    let page = Area {
        left: m.px(WIDE_PAGE),
        from: m.px(WIDE_PAGE) - m.px(12.0),
        right: (m.px(WIDE_PAGE) + m.px(640.0)).min(whole.right),
        ..whole
    };
    let (label, name, purpose) = SETTINGS[i];
    let mut out = vec![Row {
        h: m.px(220.0),
        pick: None,
        k: K::Name {
            icon: None,
            name: name.to_string(),
            what: crate::ui::setting_words(app, label, purpose),
        },
    }];
    let still = Shape {
        two: false,
        one: 44.0,
        narrow: false,
        still: true,
        pad: 12.0,
        bare: true,
        c3: true,
    };
    if let Some(p) = app.providers.iter().position(|p| p.label == label && p.dead.is_none()) {
        out.extend(rows_of(app, pen, &app.section_items(p), still, page.right - page.left));
    }
    let mark = pen.hits.len();
    list(app, pen, &out, page, None, false, still, 0, format!("settings\u{1f}page\u{1f}{label}"));
    // the page is no list of its own: its options take no click here, the whole of it opens the setting
    pen.hits.truncate(mark);
    if let Some(n) = lit(app) {
        pen.hit(page.from, page.top, g.w - page.from, page.bottom - page.top, Target::Pick(n));
    }
}

/// The other pane's rows: its own folder under its own words, the picks counted as its bar walks them.
fn pane_rows(app: &App, m: &Metrics, pane: &files::Pane) -> Vec<Row> {
    let (Some(rows), Some(p)) = (&pane.rows, app.files()) else {
        return vec![];
    };
    let words = app.prompts.restore(&View::Folder(p, pane.uri.clone()));
    let shape = FolderShape {
        own: true,
        ..FolderShape::default()
    };
    let mut out: Vec<Row> = vec![];
    let mut n = 0;
    for it in app.folder_items(p, rows, &words, &shape) {
        let gap = matches!(out.last(), Some(Row { k: K::Gap(_), .. }));
        match it {
            Item::Blank if !out.is_empty() && !gap => out.push(Row {
                h: m.px(16.0),
                pick: None,
                k: K::Gap(m.px(16.0)),
            }),
            Item::Heading(h) => {
                if gap {
                    out.pop();
                }
                out.push(Row {
                    h: m.px(36.0),
                    pick: None,
                    k: K::Head(h, None),
                });
            }
            Item::Folder(i) => {
                if let Some(r) = rows.rows.get(i) {
                    let pick = App::pickable(r).then(|| {
                        n += 1;
                        n - 1
                    });
                    out.push(Row {
                        h: m.px(44.0),
                        pick,
                        k: file_row(r, pane.checks.contains(&r.id)),
                    });
                }
            }
            _ => {}
        }
    }
    out
}

/// The rows of a file's details: what it shows, its name, its facts, a rule, then what you do with it (`body`,
/// the actions' rows). The folder alone and a selected set have their name and what they hold.
fn about_file(app: &App, pen: &Pen, a: &files::Actions, body: Vec<Row>, room: f64, tall: f64, shows: bool) -> Vec<Row> {
    let m = pen.m;
    let sep = crate::ui::SEP;
    let mut out: Vec<Row> = vec![];
    let mut facts: Vec<(&str, String)> = vec![];
    if !a.checked.is_empty() {
        let size: u64 = a.checked.iter().map(files::row_size).sum();
        if size > 0 {
            facts.push(("size", files::size_words(size)));
        }
    } else if let Some(r) = &a.row {
        let page = app
            .files
            .peek
            .as_ref()
            .filter(|pk| Some(&pk.uri) == r.page.as_ref())
            .and_then(|pk| pk.page.as_ref());
        if shows && r.page.is_some() {
            let none = || K::Shown {
                picture: None,
                lines: vec![],
                say: String::new(),
                large: false,
            };
            let k = match page {
                Some(pg) if pg.picture.is_some() => K::Shown {
                    picture: pg.picture.clone().map(|f| (f, None)),
                    lines: vec![],
                    say: String::new(),
                    large: false,
                },
                Some(pg) if pg.sound.is_some() => K::Shown {
                    picture: pg.sound.clone().map(|(f, wave)| (f, Some(wave))),
                    lines: vec![],
                    say: String::new(),
                    large: false,
                },
                Some(pg) if !pg.lines.is_empty() => K::Shown {
                    picture: None,
                    lines: pg.lines.clone(),
                    say: String::new(),
                    large: false,
                },
                // a page that came with nothing on it says so; one on its way leaves the box empty
                Some(pg) => K::Shown {
                    picture: None,
                    lines: vec![],
                    say: pg.say.clone().unwrap_or_else(|| "nothing to show".to_string()),
                    large: false,
                },
                None => none(),
            };
            // one height whatever the file shows, so the rows under it stand still from one file to the next
            let h = (room * 0.625).round().min((tall * 0.4).round()).max(m.px(60.0));
            out.push(Row {
                h: h + m.px(16.0),
                pick: None,
                k,
            });
        }
        let wide = r.wide.clone().unwrap_or_default();
        let or = |w: usize, c: usize| {
            wide.get(w)
                .filter(|s| !s.is_empty())
                .or_else(|| r.columns.get(c).filter(|s| !s.is_empty()))
                .cloned()
                .unwrap_or_default()
        };
        let (kind, size, when) = (wide.first().cloned().unwrap_or_default(), or(1, 0), or(2, 1));
        // what its page says of it and its row does not: a picture's size, how many pages, a sound's length. A
        // path is where it is, which the list says
        let said = |f: &String| f.contains('/') || [&kind, &size, &when].into_iter().chain(r.columns.iter()).any(|v| v.eq_ignore_ascii_case(f));
        let mut more: Vec<String> = page.map(|pg| pg.facts.iter().filter(|f| !said(f)).cloned().collect()).unwrap_or_default();
        if let Some(pg) = page {
            if pg.pages > 1 {
                more.push(format!("{} pages", pg.pages));
            }
            if pg.seconds >= 1.0 {
                let s = pg.seconds.round() as u64;
                more.push(format!("{}:{:02}", s / 60, s % 60));
            }
        }
        // as many on the kind's row as it holds, the rest on rows under it
        let fits = ((room - m.px(24.0) - 4.0 * m.sw - m.px(16.0)) / m.sw).floor().max(12.0) as usize;
        let mut line = String::new();
        let mut first = true;
        for part in [kind.clone()].into_iter().filter(|k| !k.is_empty()).chain(more) {
            if !line.is_empty() && cells(&line) + cells(sep) + cells(&part) > fits {
                facts.push((if first { "kind" } else { "" }, std::mem::take(&mut line)));
                first = false;
            }
            line = if line.is_empty() { part } else { format!("{}{}{}", line, sep, part) };
        }
        if !line.is_empty() {
            facts.push((if first { "kind" } else { "" }, line));
        }
        if !size.is_empty() {
            facts.push((if r.children.is_some() { "holds" } else { "size" }, size));
        }
        if !when.is_empty() {
            facts.push(("changed", when));
        }
        if let Some(place) = files::place_of(r) {
            facts.push(("in", place));
        }
    } else if let Some(r) = app.folder.as_ref().and_then(|(_, _, rows)| rows.rows.iter().find(|r| files::is_summary(r))) {
        // the folder itself: what its summary counts, and its size
        let (sizes, counts): (Vec<&str>, Vec<&str>) = r.text.split(sep).skip(1).partition(|part| files::bytes(part).is_some());
        if !counts.is_empty() {
            facts.push(("holds", counts.join(sep)));
        }
        if let Some(size) = sizes.first() {
            facts.push(("size", size.to_string()));
        }
    }
    if out.is_empty() {
        out.push(Row {
            h: m.px(8.0),
            pick: None,
            k: K::Gap(m.px(8.0)),
        });
    }
    let cells_wide = ((room - m.px(24.0)) / m.cw).floor().max(8.0) as usize;
    out.push(Row {
        h: m.px(44.0),
        pick: None,
        k: K::Words(cut_middle(&a.title, cells_wide), Size::Main, false, true),
    });
    out.extend(facts.into_iter().map(|(label, value)| Row {
        h: m.px(28.0),
        pick: None,
        k: K::Fact(label.to_string(), value),
    }));
    if !body.is_empty() {
        out.push(Row {
            h: m.px(17.0),
            pick: None,
            k: K::Rule,
        });
        out.extend(body);
    }
    out
}

/// A pane's folder over its rows, where two stand: bright over the pane that holds the keys, muted over the other.
fn pane_head(pen: &mut Pen, a: Area, top: f64, title: &str, active: bool) {
    let m = *pen.m;
    let x = a.left + m.px(24.0);
    let n = ((a.right - x) / m.sw).floor().max(4.0) as usize;
    let color = if active { pen.t.ink } else { pen.t.muted };
    pen.text(x, top + m.px(24.0), &cut_middle(title, n), Size::Small, color, active);
}

/// The clicks of the list drawn since `mark` given another meaning: a row of the other pane, or of the list
/// beside the details that hold the keys.
fn retarget(pen: &mut Pen, mark: usize, to: fn(usize) -> Target) {
    for h in pen.hits[mark..].iter_mut() {
        if let Target::Pick(n) = h.target {
            h.target = to(n);
        }
    }
}

/// The lit file's page in large type (v0.160), in a wide window: its name as large as its length allows, one line of
/// what it is, its facts side by side, then what it holds in the form that suits it (a folder's names, a text's
/// first lines, a picture, a sound's waveform, or the words that say there is nothing to show) with what you do
/// with it beside that, always in one place; under each other where the page is too narrow for the two. No line
/// and no box. `area` is the page; the details hold the keys while their own page is open.
fn file_page(app: &App, pen: &mut Pen, g: &Geo, area: Area, items: &[Item]) {
    let m = *pen.m;
    let Some(about) = app.files_about() else { return };
    let details = matches!(app.files.page, files::Page::Actions(_));
    let shape = Shape {
        two: false,
        one: 36.0,
        narrow: true,
        still: !details,
        pad: 12.0,
        bare: true,
        c3: false,
    };
    let lines: Vec<Item> = if details {
        items.to_vec()
    } else {
        app.files_about_lines(&about).into_iter().map(Item::Files).collect()
    };
    let body = rows_of(app, pen, &lines, shape, area.right - area.left);
    // the details' own rows, told apart: what it shows, its name, the kind's line, its facts, what you do with it
    let (mut name, mut what, mut pairs, mut content, mut steps) = (about.title.clone(), vec![], vec![], None, vec![]);
    let mut acts = false;
    for r in about_file(app, pen, &about, body, 1e6, 0.0, true) {
        match r.k {
            K::Rule => acts = true,
            _ if acts => steps.push(r),
            K::Shown { picture, lines, say, .. } => {
                content = Some(K::Shown {
                    picture,
                    lines,
                    say,
                    large: true,
                })
            }
            K::Words(title, Size::Main, _, true) => name = title,
            K::Fact(label, value) if label == "kind" || label.is_empty() => what.push(value),
            K::Fact(label, value) => pairs.push((label, value)),
            _ => {}
        }
    }
    let page = about
        .row
        .as_ref()
        .and_then(|r| app.files.peek.as_ref().filter(|pk| Some(&pk.uri) == r.page.as_ref()))
        .and_then(|pk| pk.page.as_ref());
    match page {
        // a sound that says its title is named by it, its file among the facts; who it is by follows
        Some(pg) if pg.sound.is_some() && pg.bold.contains(&0) && !pg.lines.is_empty() => {
            pairs.insert(0, ("file".to_string(), std::mem::replace(&mut name, pg.lines[0].clone())));
            if let Some(by) = pg.lines.get(1).filter(|l| !l.is_empty()) {
                pairs.push(("by".to_string(), by.clone()));
            }
        }
        // a folder: its name is said once, so its page's own first line goes
        Some(pg) if about.row.as_ref().is_some_and(|r| r.children.is_some()) && pg.lines.first() == Some(&name) => {
            if let Some(K::Shown { lines, .. }) = content.as_mut() {
                lines.remove(0);
            }
        }
        _ => {}
    }
    // a set of files selected: their names are what it holds
    if !about.checked.is_empty() {
        content = Some(K::Shown {
            picture: None,
            lines: about.checked.iter().map(|r| r.text.clone()).collect(),
            say: String::new(),
            large: true,
        });
    }
    let fixed = |h: f64, k: K| Row { h: m.px(h), pick: None, k };
    let mut rows = vec![fixed(
        193.0,
        K::Name {
            icon: None,
            name,
            what: what.join(crate::ui::SEP),
        },
    )];
    if !pairs.is_empty() {
        rows.push(fixed(72.0, K::Facts(pairs)));
    }
    rows.push(fixed(30.0, K::Gap(m.px(30.0))));
    let head: f64 = rows.iter().map(|r| r.h).sum();
    let key = format!("files\u{1f}about\u{1f}{}", about.title);
    // what it holds and what you do with it side by side, where the page has the room for the two
    let beside = area.right - area.left >= m.px(1000.0);
    if beside {
        let cut = area.left + m.px(736.0);
        let still = Shape { still: true, ..shape };
        // the name has the page's whole width; what the file holds stands under it, at the left
        let over = Area {
            bottom: area.top + head,
            ..area
        };
        list(app, pen, &rows, over, None, false, still, 0, format!("{key}\u{1f}head"));
        if let Some(k) = content {
            let left = Area {
                right: cut - m.px(24.0),
                to: cut,
                top: area.top + head,
                ..area
            };
            let holds = [Row {
                h: (area.bottom - area.top - head).max(m.px(160.0)),
                pick: None,
                k,
            }];
            list(app, pen, &holds, left, None, false, still, 0, format!("{key}\u{1f}holds"));
        }
        let right = Area {
            left: cut,
            right: (cut + m.px(344.0)).min(area.right),
            top: area.top + head - m.px(6.0),
            from: cut,
            to: g.w,
            ..area
        };
        if details {
            list(app, pen, &steps, right, lit(app), list_focus(app), shape, app.scroll, key);
        } else {
            let off = list(app, pen, &steps, right, None, false, shape, 0, key);
            pane_targets(pen, &steps, right, off);
        }
        return;
    }
    let acts_h: f64 = steps.iter().map(|r| r.h).sum();
    rows.extend(steps);
    if let Some(k) = content {
        rows.push(fixed(16.0, K::Gap(m.px(16.0))));
        rows.push(Row {
            h: (area.bottom - area.top - head - acts_h - m.px(16.0)).max(m.px(200.0)),
            pick: None,
            k,
        });
    }
    if details {
        list(app, pen, &rows, area, lit(app), list_focus(app), shape, app.scroll, key);
    } else {
        let off = list(app, pen, &rows, area, None, false, shape, 0, key);
        pane_targets(pen, &rows, area, off);
    }
}

/// Files: a folder's list, two panes each its own folder, a file's details beside the list where the window
/// holds both, or a page of files alone.
fn files_body(app: &App, pen: &mut Pen, g: &Geo, items: &[Item]) {
    let m = *pen.m;
    let Some((_, uri)) = app.files_pane_view() else { return };
    let whole = Area {
        left: g.inset,
        right: g.w - g.inset,
        top: g.top,
        bottom: g.bottom,
        from: 0.0,
        to: g.w,
    };
    let rows_shape = Shape {
        two: false,
        one: 44.0,
        narrow: false,
        still: false,
        pad: 24.0,
        bare: false,
        c3: false,
    };
    let room = |a: Area, s: Shape| a.right - a.left - m.px(s.pad) - m.px(12.0);
    // a page over the list (the actions, a conflict): the items are its lines, and the list stands as it stood
    // when the page opened. A form keeps the list as the items
    let over = app.files_page_open() && !app.files.form();
    let nav = app.files.list_nav();
    let panes = app.panes_drawn();
    let list_items: Vec<Item> = match (&app.folder, nav) {
        (Some((p, _, rows)), Some(nav)) if over => app.folder_items(
            *p,
            rows,
            &nav.query,
            &FolderShape {
                own: panes,
                ..FolderShape::default()
            },
        ),
        _ if over => vec![],
        _ => items.to_vec(),
    };
    let (list_lit, list_scroll, list_words) = match nav {
        Some(n) => (n.in_list.then_some(n.selected), n.scroll, n.query.clone()),
        None => (lit(app), app.scroll, app.input.clone()),
    };
    let focus = nav.is_none() && list_focus(app);
    // a pane keeps its place by its side: both may show one folder
    let active_left = app.files.other.is_none() || app.files.other_side == Side::Right;
    let named = |left: bool, uri: &str, words: &str| format!("files\u{1f}{}\u{1f}{}\u{1f}{}", if left { "left" } else { "right" }, uri, words);
    let own = named(active_left, &uri, &list_words);
    let page_rows = |pen: &Pen, shape: Shape, a: Area| match &app.files.page {
        files::Page::Actions(act) => about_file(
            app,
            pen,
            act,
            rows_of(app, pen, items, shape, room(a, shape)),
            a.right - a.left,
            a.bottom - a.top,
            false,
        ),
        _ => rows_of(app, pen, items, shape, room(a, shape)),
    };
    if let (true, Some(other)) = (panes, app.files.other.as_ref()) {
        // P2 (v0.160): a window that holds them keeps the lit file's page beside the two panes, a third column
        let paged = app.files_details_beside() && wide3(&m, g.w);
        let end = if paged { g.w - m.px(PAGE3) } else { g.w };
        let divide = (end / 2.0).round();
        let head = m.px(40.0);
        let left = Area {
            right: divide - m.px(12.0),
            top: g.top + head,
            to: divide,
            ..whole
        };
        let right = Area {
            left: divide,
            right: if paged { end - m.px(12.0) } else { whole.right },
            top: g.top + head,
            from: divide + 1.0,
            to: end,
            ..whole
        };
        if paged {
            let page = Area {
                left: end + m.px(12.0),
                from: end,
                ..whole
            };
            file_page(app, pen, g, page, items);
        }
        let over = over && !paged;
        let (act, oth) = if active_left { (left, right) } else { (right, left) };
        let title = app.folder.as_ref().map(|(_, _, r)| r.title.clone()).unwrap_or_default();
        // anywhere on the other pane takes the keys there; its rows, drawn after, take their own click
        pen.hit(oth.from, g.top, oth.to - oth.from, g.bottom - g.top, Target::OtherPane);
        pane_head(pen, act, g.top, &title, true);
        pane_head(pen, oth, g.top, &other.title(), false);
        if over {
            let shape = Shape {
                two: false,
                one: 36.0,
                narrow: true,
                still: false,
                pad: 24.0,
                bare: false,
                c3: false,
            };
            let rows = page_rows(pen, shape, act);
            list(
                app,
                pen,
                &rows,
                act,
                lit(app),
                list_focus(app),
                shape,
                app.scroll,
                "files\u{1f}page".to_string(),
            );
        } else {
            let rows = rows_of(app, pen, &list_items, rows_shape, room(act, rows_shape));
            list(app, pen, &rows, act, list_lit, focus, rows_shape, list_scroll, own);
        }
        let rows = pane_rows(app, &m, other);
        let words = app
            .files()
            .map(|p| app.prompts.restore(&View::Folder(p, other.uri.clone())))
            .unwrap_or_default();
        let mark = pen.hits.len();
        list(
            app,
            pen,
            &rows,
            oth,
            None,
            false,
            rows_shape,
            other.scroll,
            named(!active_left, &other.uri, &words),
        );
        // no line between the panes (v0.160): the lit row's bar and the space say where a pane ends
        retarget(pen, mark, Target::OtherRow);
        return;
    }
    if app.files_details_beside() && wide(&m, g.w) {
        // a wide window (v0.160): the list keeps its column, the lit file has the rest, in large type
        let divide = m.px(WIDE_LIST);
        let left = Area {
            right: divide - m.px(24.0),
            to: divide,
            ..whole
        };
        let narrow = Shape { narrow: true, ..rows_shape };
        let details = matches!(app.files.page, files::Page::Actions(_));
        let rows = rows_of(app, pen, &list_items, narrow, room(left, narrow));
        let mark = pen.hits.len();
        list(app, pen, &rows, left, list_lit, focus, narrow, list_scroll, own);
        if details {
            retarget(pen, mark, Target::ListRow);
        }
        let page = Area {
            left: m.px(WIDE_PAGE),
            from: m.px(WIDE_PAGE) - m.px(12.0),
            ..whole
        };
        file_page(app, pen, g, page, items);
        return;
    }
    if app.files_details_beside() {
        // the details take a third of the window: the list a column of names until the window is wide
        let pane_w = (g.w / 3.0).round().clamp(m.px(280.0), m.px(640.0));
        let divide = whole.right - pane_w - m.px(16.0);
        let left = Area {
            right: divide - m.px(12.0),
            to: divide,
            ..whole
        };
        let right = Area {
            left: divide + m.px(16.0),
            from: divide + 1.0,
            ..whole
        };
        let narrow = Shape { narrow: true, ..rows_shape };
        // the details hold the keys while their page is open; else the list does, and they follow its lit file
        let details = matches!(app.files.page, files::Page::Actions(_));
        let rows = rows_of(app, pen, &list_items, narrow, room(left, narrow));
        let mark = pen.hits.len();
        list(app, pen, &rows, left, list_lit, focus, narrow, list_scroll, own);
        if details {
            retarget(pen, mark, Target::ListRow);
        }
        pen.fill(divide, whole.top + m.px(8.0), 1.0, whole.bottom - whole.top - m.px(16.0), pen.t.lit);
        let Some(about) = app.files_about() else { return };
        let shape = Shape {
            two: false,
            one: 36.0,
            narrow: true,
            still: !details,
            pad: 12.0,
            bare: false,
            c3: false,
        };
        let lines: Vec<Item> = if details {
            items.to_vec()
        } else {
            app.files_about_lines(&about).into_iter().map(Item::Files).collect()
        };
        let body = rows_of(app, pen, &lines, shape, room(right, shape));
        let rows = about_file(app, pen, &about, body, right.right - right.left, right.bottom - right.top, true);
        let key = format!("files\u{1f}about\u{1f}{}", about.title);
        if details {
            list(app, pen, &rows, right, lit(app), list_focus(app), shape, app.scroll, key);
        } else {
            let off = list(app, pen, &rows, right, None, false, shape, 0, key);
            pane_targets(pen, &rows, right, off);
        }
        return;
    }
    if over {
        let shape = Shape {
            two: false,
            one: 36.0,
            narrow: false,
            still: false,
            pad: 24.0,
            bare: false,
            c3: false,
        };
        let rows = page_rows(pen, shape, whole);
        list(
            app,
            pen,
            &rows,
            whole,
            lit(app),
            list_focus(app),
            shape,
            app.scroll,
            "files\u{1f}page".to_string(),
        );
        return;
    }
    let mut rows = rows_of(app, pen, &list_items, rows_shape, room(whole, rows_shape));
    if rows.is_empty() && app.folder.is_some() && list_words.is_empty() {
        rows.push(Row {
            h: m.px(44.0),
            pick: None,
            k: K::Words("empty".to_string(), Size::Small, true, false),
        });
    }
    list(app, pen, &rows, whole, list_lit, focus, rows_shape, list_scroll, own);
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
