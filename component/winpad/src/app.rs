//! The pad on the screens: a surface on the wlr layer shell's top layer on each screen, above every
//! window, drawn with cairo and pango; a docked pad keeps its strip with a second surface, empty, on
//! the background layer; a pad on the bar stands over the bar, which is on the bottom layer, and keeps none. The pointer, the keys while it has them, and sway's list.

use crate::buttons::{Band, Glyph, Mic};
use crate::keys::Keyboard;
use crate::order::History;
use crate::pad::{self, BarAt, Click, Edge, Gesture, Grab, Hit, Item, KeyAct, Layout, ListAct, Metrics, Place, Rect, Sides, View, Want, Win};
use crate::paint::{Align, Canvas, Fonts, Lib, Picture, Rgb};
use crate::sway::Ipc;
use calloop::timer::{TimeoutAction, Timer};
use calloop::LoopHandle;
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, Region};
use smithay_client_toolkit::dispatch2::Dispatch2;
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape as Cursor, WpCursorShapeDeviceV1};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::seat::pointer::cursor_shape::CursorShapeManager;
use smithay_client_toolkit::seat::pointer::{PointerEvent, PointerEventKind, PointerHandler};
use smithay_client_toolkit::seat::{Capability, SeatHandler, SeatState};
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shm::slot::SlotPool;
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use wayland_client::globals::GlobalList;
use wayland_client::protocol::wl_callback::{self, WlCallback};
use wayland_client::protocol::wl_keyboard::{self, KeyState, WlKeyboard};
use wayland_client::protocol::wl_output::{Transform, WlOutput};
use wayland_client::protocol::wl_pointer::WlPointer;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::protocol::wl_shm;
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, QueueHandle, WEnum};

mod buttons;
mod order;

/// The questions in a row sway may leave without an answer before the program ends and its keeper starts it again.
const MISSES: u32 = 10;

/// The layer shell namespace: what sway's rules and tools call the surface.
const NAMESPACE: &str = "spark-winpad";
const BTN_LEFT: u32 = 0x110;
/// How long the tree is read every tick after an event.
const BURST: Duration = Duration::from_secs(2);
/// The least width at a side spark-shell keeps (WINPAD_SIDE_WIDTH, 36 to 9999): a column's cell is narrower at a
/// small text size, and the layout makes the same column of it.
const SIDE_LEAST: i32 = 36;

/// The palette's slots and the text, as spark-shell hands them over.
pub struct Look {
    pub fg: Rgb,
    pub accent: Rgb,
    pub muted: Rgb,
    /// The dim tone, the bar's own: the grip's line, as the bar's hairline.
    pub dim: Rgb,
    /// The ground's color, the bar's: the pad's own body.
    pub ground: Rgb,
    /// What stands beside the pad: a label, a group's list.
    pub surface: Rgb,
    pub lit: Rgb,
    pub band: Rgb,
    pub alpha: f64,
    pub font: String,
}

/// What spark-shell says, read once at the start.
/// What the buttons on a title band need: what they wear, the terminal's app, and the title format that
/// follows the buttons, the terminal's and every other window's.
pub struct Titles {
    pub style: crate::buttons::Style,
    pub term: String,
    /// What an app of the menu opens its window under, as a start: spark-shell-tmux is a terminal too.
    pub term_also: String,
    pub title: String,
    pub term_title: String,
    /// The mic on a terminal's band (WINPAD_VOICE=yes), and spark-shell's voice state it follows.
    pub voice: bool,
    pub voice_state: Option<PathBuf>,
}

pub struct Config {
    pub look: Look,
    pub titles: Titles,
    pub place: Place,
    /// The icons alone (the default), or the titled slots (WINPAD_VIEW=titles).
    pub view: View,
    /// The most width at the top, the bottom or free (0: the room's), and at a side.
    pub width: i32,
    pub side_width: i32,
    /// The most height (0: as many rows as the windows need): WINPAD_HEIGHT.
    pub height: i32,
    /// The margin from an edge: WINPAD_GAP, the desktop's outer gap.
    pub gap: i32,
    /// The band with its words under the handle (WINPAD_BAND=on).
    pub band: bool,
    /// The rest workspace's name (WINPAD_REST): no pad on a screen that shows it; empty, never.
    pub rest: String,
    pub spark_shell: String,
    pub state_file: Option<PathBuf>,
    pub bar_pid: Option<PathBuf>,
    /// The state file of spark's bar (WINPAD_BAR_STATE): where each screen's bar stands and the room it keeps for
    /// the pad. None where no such bar draws: a pad whose place is the bar stands at the bottom's middle.
    pub bar_state: Option<PathBuf>,
}

/// The pad's form: on the bar one row with no hide, a column at a side, a row anywhere else.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Form {
    Bar,
    Row,
    Column,
}

impl Form {
    /// A pad docked at this edge, or free: a column at a side.
    fn at(edge: Option<Edge>) -> Form {
        if edge.is_some_and(Edge::side) {
            Form::Column
        } else {
            Form::Row
        }
    }
}

/// How a screen's surface is laid out: along an edge (the pad, the room for its label and its grips), at a
/// place of its own, or over the whole area while the pad is dragged or a group's list is open.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Shape {
    /// `over`: the thickness of the strip the pad keeps and stands over; 0 when it keeps none.
    Strip {
        edge: Edge,
        thick: i32,
        over: i32,
    },
    Free {
        x: i32,
        y: i32,
        w: i32,
        h: i32,
    },
    /// `back` and `bar`: an edge each and how far the surface reaches back over what stands there, so it covers
    /// that too: the strip kept through a drag; and the bar, which is not the windows' area, under a list open on
    /// a pad that stands on it and under a move, which shows the pad on the bar while the pointer is there.
    Full {
        back: Option<(Edge, i32)>,
        bar: Option<(Edge, i32)>,
    },
}

struct Surf {
    layer: LayerSurface,
    /// The layout last asked of the compositor; none before the first.
    shape: Option<Shape>,
    keys: Option<bool>,
    size: (i32, i32),
    configured: bool,
    /// Where the pad is drawn on the surface, its shape and its cells, and an open list's rectangle, for the
    /// pointer and the keys: what the screen shows.
    pad_at: (i32, i32),
    lay: Layout,
    items: Vec<Item>,
    list_at: Option<(Rect, usize)>,
}

/// The strip a docked pad keeps, the windows tiling beside it: an empty surface on the background
/// layer that takes no pointer and no key, its exclusive zone the pad's thickness. sway lays the zones
/// out layer by layer, overlay, top, bottom, background, so the strip on the background layer always
/// comes after swaybar's on the bottom layer: it lands inside the bar's zone and the bar stays where it
/// is. On the bottom layer beside the bar the order within the layer decided it, oldest first on sway
/// 1.10 and newer but newest first on 1.9 (Ubuntu 24.04), where the strip took the edge and pushed the
/// bar inward. The pad itself stands over the strip, on the top layer.
struct Kept {
    layer: LayerSurface,
    edge: Edge,
    thick: i32,
    /// Its buffer is on: sway holds its zone from then on.
    mapped: bool,
}

/// The glyph surface: the whole screen on the top layer, every zone ignored, so its pixels are the screen's
/// own; the minimize and close glyphs of each title band, and the pointer on them alone.
struct Deco {
    layer: LayerSurface,
    size: (i32, i32),
    configured: bool,
}

struct Out {
    output: WlOutput,
    name: String,
    scale: i32,
    /// The usable area: the screen without the bar, as the compositor last told it.
    area: (i32, i32),
    surf: Option<Surf>,
    strip: Option<Kept>,
    /// The surface that holds the keyboard while the pad has the keys.
    keyer: Option<LayerSurface>,
    deco: Option<Deco>,
}

struct Keys {
    out: String,
    /// The pad was hidden before the keys came: it goes again when they leave.
    temp: bool,
}

struct Ptr {
    _wl: WlPointer,
    device: Option<WpCursorShapeDeviceV1>,
    serial: u32,
    out: Option<usize>,
    pos: (f64, f64),
    cursor: Option<Cursor>,
}

struct Press {
    out: usize,
    gesture: Gesture,
    /// The pointer from the pad's corner.
    off: (f64, f64),
}

struct Drag {
    kind: Grab,
    out: usize,
    off: (f64, f64),
    /// The pointer at the press, in the frame of the surface it was pressed on.
    at: (f64, f64),
    /// The pad's form at the press, and whether it stood on the bar.
    was: Form,
    /// The drag holds the bar: the pointer is on it (pad::drag_bar).
    on_bar: bool,
    /// Set once the surface covers the whole area: the pad's corner there, and its rectangle at the start.
    pad: Option<(i32, i32)>,
    start: Rect,
    /// The edge the drag holds, from the pointer (pad::drag_edge).
    near: Option<Edge>,
    /// The surface's shape at the press. sway keeps a held pointer's coordinates in the frame the surface
    /// had at the press (seatop_down), so a drag's points are read from there.
    from: Option<Shape>,
    /// Where that surface stood in the area: known once the whole area's size is.
    origin: (i32, i32),
}

/// A group's list, open beside its icon.
struct List {
    out: usize,
    /// The group's app, by its name: the list closes when that group is gone.
    app: String,
    sel: usize,
    hover: Option<usize>,
    /// The list took the keyboard for Enter and Esc: it gives it back when it closes.
    took_keys: bool,
}

#[derive(Default)]
struct Tip {
    on: bool,
    quiet: bool,
    gone: Option<Instant>,
    gen: u64,
    quiet_gen: u64,
}

/// How long a pad whose place is the bar waits for the bar's state, in ticks of a tenth of a second: a bar that
/// starts again says where it stands well within it; with none after that, the pad stands at the bottom's middle.
const BAR_WAIT: u32 = 30;

pub struct App {
    registry: RegistryState,
    outputs: OutputState,
    compositor: CompositorState,
    layer_shell: LayerShell,
    seats: SeatState,
    shm: Shm,
    pool: SlotPool,
    cursors: Option<CursorShapeManager>,
    qh: QueueHandle<App>,
    handle: LoopHandle<'static, App>,
    lib: Lib,
    fonts: Fonts,
    m: Metrics,
    cfg: Config,
    ipc: Ipc,
    outs: Vec<Out>,
    wins: Vec<Win>,
    /// The screens at rest, as the tree last said.
    resting: Vec<String>,
    /// Each screen's bar, as its state file last said, the text it was read from, and the ticks since the file
    /// was last there.
    bars: Vec<(String, BarAt)>,
    bar_text: String,
    bar_gone: u32,
    /// The screens whose bar is on its way, and the ticks one that does not rest was waited for.
    coming: Vec<String>,
    late: u32,
    icon_paths: HashMap<String, String>,
    pictures: HashMap<String, Option<Picture>>,
    hidden: bool,
    keys: Option<Keys>,
    keys_wanted: bool,
    /// The cell the keys have picked.
    sel: usize,
    pointer: Option<Ptr>,
    keyboard: Option<WlKeyboard>,
    /// The keymap the compositor sent, read with libxkbcommon.
    kb: Keyboard,
    hover: Option<(usize, usize)>,
    press: Option<Press>,
    drag: Option<Drag>,
    list: Option<List>,
    tip: Tip,
    pub dirty: bool,
    pub list_dirty: bool,
    pub deco_dirty: bool,
    pub stop: bool,
    /// The looks at sway's tree in a row that got no answer, and why the pad ends when that many did.
    misses: u32,
    pub failed: Option<String>,
    /// The title bands in sight, and the glyph a press is on.
    bands: Vec<Band>,
    deco_press: Option<(i64, Glyph)>,
    /// The button under the pointer, and the title each window was last given.
    deco_hover: Option<(i64, Glyph)>,
    sent: HashMap<i64, String>,
    /// The mic as the voice state last said.
    voice: Mic,
    history: History,
    /// The width of one character of a title, in the title's font.
    cell: f64,
    /// Until when the tree is read every tick: two seconds after an event, since a move that follows sends none.
    burst_until: Option<Instant>,
    /// The screen changes counted: a refit runs for the last one only.
    screens_gen: u64,
    written: Option<(bool, usize)>,
    /// The strips kept when spark-shell last laid the placed windows out again (desktop window refit).
    refit_for: Vec<(String, Edge, i32)>,
    /// A strip went before it was mapped: sway 1.9 takes a strip's zone from its first commit, so the
    /// area may have changed and come back with no refit between.
    refit_owed: bool,
    /// The syncs sent for a refit that sway has not answered yet: the pad ending runs the refit itself.
    refit_waiting: u32,
    conn: Connection,
}

impl App {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        conn: &Connection,
        globals: &GlobalList,
        qh: &QueueHandle<App>,
        handle: LoopHandle<'static, App>,
        lib: Lib,
        cfg: Config,
        ipc: Ipc,
        keys: bool,
    ) -> Result<App, String> {
        let compositor = CompositorState::bind(globals, qh).map_err(|e| format!("the compositor has no wl_compositor: {e}"))?;
        let layer_shell = LayerShell::bind(globals, qh).map_err(|_| "the compositor has no layer shell (zwlr_layer_shell_v1)".to_string())?;
        let shm = Shm::bind(globals, qh).map_err(|e| format!("the compositor has no wl_shm: {e}"))?;
        let pool = SlotPool::new(1 << 20, &shm).map_err(|e| format!("shared memory: {e}"))?;
        let fonts = Fonts::new(&lib, &cfg.look.font);
        // one character of a title, from the buttons' nine in the title's own font
        let cell = {
            let mut probe = [0u8; 4 * 8 * 8];
            Canvas::new(&lib, &fonts, &mut probe, 8, 8, 32, 1.0).map_or(fonts.px * 0.6, |c| c.measure(crate::buttons::GLYPHS, false) / 9.0)
        };
        let m = Metrics {
            gap: cfg.gap,
            ..Metrics::for_text(fonts.px)
        };
        Ok(App {
            registry: RegistryState::new(globals),
            outputs: OutputState::new(globals, qh),
            seats: SeatState::new(globals, qh),
            cursors: CursorShapeManager::bind(globals, qh).ok(),
            compositor,
            layer_shell,
            shm,
            pool,
            qh: qh.clone(),
            handle,
            lib,
            fonts,
            m,
            cfg,
            ipc,
            outs: vec![],
            wins: vec![],
            resting: vec![],
            bars: vec![],
            bar_text: String::new(),
            bar_gone: 1,
            coming: vec![],
            late: 0,
            icon_paths: HashMap::new(),
            pictures: HashMap::new(),
            hidden: false,
            keys: None,
            keys_wanted: keys,
            sel: 0,
            pointer: None,
            keyboard: None,
            kb: Keyboard::new(),
            hover: None,
            press: None,
            drag: None,
            list: None,
            tip: Tip::default(),
            dirty: true,
            list_dirty: true,
            deco_dirty: true,
            stop: false,
            misses: 0,
            failed: None,
            bands: vec![],
            deco_press: None,
            deco_hover: None,
            sent: HashMap::new(),
            voice: Mic::default(),
            history: History::default(),
            cell,
            burst_until: None,
            screens_gen: 0,
            written: None,
            refit_for: vec![],
            refit_owed: false,
            refit_waiting: 0,
            conn: conn.clone(),
        })
    }

    /// The icon size to ask the apps adapter for: the largest scale among the screens.
    pub fn icon_px(&self) -> i32 {
        self.m.icon * self.outs.iter().map(|o| o.scale).max().unwrap_or(1).max(1)
    }

    pub fn set_icons(&mut self, paths: Vec<(String, String)>) {
        for (k, p) in paths {
            self.icon_paths.entry(k).or_insert(p);
        }
        for p in self.pictures.drain() {
            if let (_, Some(p)) = p {
                p.free(&self.lib);
            }
        }
        self.dirty = true;
    }

    fn visible(&self) -> bool {
        !self.wins.is_empty() && (!self.hidden || self.keys.is_some())
    }

    /// The pad on a screen: in sight, the screen not at rest, and a pad whose place is the bar not waiting for it.
    fn visible_on(&self, oi: usize) -> bool {
        self.visible() && self.outs.get(oi).is_some_and(|o| !self.awaits_bar(&o.name) && !self.resting.contains(&o.name))
    }

    /// A pad whose place is the bar, while the bar's state is not there: at its start, and while a bar that moves
    /// or takes another look starts again. The pad goes with the bar and comes back with it, for BAR_WAIT ticks
    /// at most: it never stands at the bar's old edge or at the bottom's middle for the moment between, nor on a
    /// screen that rested while its bar comes back. Not while it is dragged.
    fn awaits_bar(&self, name: &str) -> bool {
        let gone = self.bar_gone > 0 && self.bar_gone < BAR_WAIT;
        let waits = gone || self.coming.iter().any(|c| c == name);
        self.cfg.place == Place::Bar && self.cfg.bar_state.is_some() && self.drag.is_none() && waits
    }

    /// The windows' apps by name, oldest first: what a group folds by.
    fn names(&self) -> Vec<String> {
        self.wins.iter().map(|w| pad::app_name(&w.app)).collect()
    }

    /// The bar on a screen, where it has the room for the pad: its grip and one cell at least.
    fn bar_on(&self, oi: usize) -> Option<BarAt> {
        let name = &self.outs.get(oi)?.name;
        let bar = self.bars.iter().find(|b| b.0 == *name)?.1;
        (bar.w >= self.m.lead + self.m.tool).then_some(bar)
    }

    /// The pad's place on a screen: the config's; but a pad whose place is the bar stands at the bottom's middle,
    /// where it stood before the bar took it, on a screen whose bar has no room for it or that has no such bar.
    fn place_on(&self, oi: usize) -> Place {
        match self.cfg.place {
            Place::Bar if self.bar_on(oi).is_none() => Place::default(),
            place => place,
        }
    }

    /// The pad's form on a screen now: while it is moved, the one the drag holds (the bar's with the pointer on
    /// the bar, a column at a side, a row elsewhere); else its place's. A resize keeps its place's.
    fn form_on(&self, oi: usize) -> Form {
        match &self.drag {
            Some(d) if d.kind == Grab::Move && d.out == oi => {
                if d.on_bar {
                    Form::Bar
                } else {
                    Form::at(d.near)
                }
            }
            _ => match self.place_on(oi) {
                Place::Bar => Form::Bar,
                place => Form::at(place.edge()),
            },
        }
    }

    /// What the pad is asked to be in a form on a screen. A pad moved between a side and the rest is a column or a
    /// row again: the height it kept was the other shape's. On the bar it is icons in the room the bar keeps.
    fn want(&self, oi: usize, form: Form) -> Want {
        let side = form == Form::Column;
        match (form, self.bar_on(oi)) {
            (Form::Bar, Some(bar)) => Want {
                view: View::Icons,
                band: false,
                column: false,
                bar: true,
                w: bar.w,
                h: 0,
            },
            _ => Want {
                view: self.cfg.view,
                band: self.cfg.band,
                column: side,
                bar: false,
                w: if side { self.cfg.side_width.max(self.m.tool) } else { self.cfg.width },
                h: if side == self.place_on(oi).side() { self.cfg.height } else { 0 },
            },
        }
    }

    /// The room for the pad on a screen: the bar's own for a pad on it, else the usable area without the gap at
    /// each side.
    fn room(&self, oi: usize, form: Form) -> (i32, i32) {
        match (form, self.bar_on(oi)) {
            (Form::Bar, Some(bar)) => (bar.w, bar.height),
            _ => {
                let (aw, ah) = self.outs[oi].area;
                (aw - 2 * self.m.gap, ah - 2 * self.m.gap)
            }
        }
    }

    /// The pad's cells on a screen in a form: a window each while they fit, an app's windows folded into one when
    /// they do not, and on the bar, which has one row, the rest in its last cell; and its layout.
    fn items_on(&self, oi: usize, form: Form) -> (Vec<Item>, Layout) {
        let want = self.want(oi, form);
        let room = self.room(oi, form);
        let items = pad::group(&self.names(), pad::capacity(&want, room, &self.m), want.bar);
        let lay = pad::layout(items.len(), &want, room, &self.m);
        (items, lay)
    }

    fn layout_on(&self, oi: usize, form: Form) -> Layout {
        self.items_on(oi, form).1
    }

    /// The strip the pad keeps on a screen at its place: its edge and thickness. None on the bar.
    fn strip_for(&self, oi: usize) -> Option<(Edge, i32)> {
        let place = self.place_on(oi);
        let Place::Dock(edge, _) = place else { return None };
        let thick = pad::strip_thick(place, &self.layout_on(oi, Form::at(Some(edge))));
        (thick > 0).then_some((edge, thick))
    }

    fn shape_for(&self, oi: usize) -> Shape {
        let place = self.place_on(oi);
        if self.drag.as_ref().is_some_and(|d| d.out == oi) || self.list.as_ref().is_some_and(|l| l.out == oi) {
            // the surface reaches back over the bar under a list open on a pad that stands on the bar, where the pad
            // stays, and under a move from its start, never resized on the way: the pad is shown on the bar itself
            // while the pointer is there
            let over = match &self.drag {
                Some(d) => d.kind == Grab::Move,
                None => place == Place::Bar,
            };
            let bar = self.bar_on(oi).filter(|_| over).map(|b| (b.edge, b.height));
            let back = self.outs[oi].strip.as_ref().filter(|k| k.mapped).map(|k| (k.edge, k.thick + self.m.gap));
            return Shape::Full { back, bar };
        }
        let m = &self.m;
        let lay = self.layout_on(oi, self.form_on(oi));
        match place {
            // over the bar, which keeps the screen's edge: the margin goes its height back over it, as over a strip
            // the pad keeps itself; the label's room is on the windows' side
            Place::Bar => {
                let bar = self.bar_on(oi).unwrap_or(BarAt {
                    edge: Edge::Top,
                    height: lay.h,
                    x: 0,
                    w: 0,
                });
                Shape::Strip {
                    edge: bar.edge,
                    thick: bar.height + m.tip + pad::AIR,
                    over: bar.height,
                }
            }
            Place::Dock(edge, _) => {
                let over = pad::strip_thick(place, &lay);
                // the label's room beside the pad, away from its edge, where the grip on that side is too
                let thick = if edge.side() { lay.w + m.tip_room } else { lay.h + m.tip + pad::AIR };
                Shape::Strip { edge, thick, over }
            }
            Place::Free(..) => {
                // around the pad, inside the area: the room for its label on any side, and its grips
                let (aw, ah) = self.outs[oi].area;
                let (x, y) = pad::position(place, lay.w, lay.h, aw, ah, m);
                let (rx, ry) = (m.tip_room + pad::AIR, (m.tip + pad::AIR).max(m.grip));
                let (x0, y0) = ((x - rx).max(0), (y - ry).max(0));
                let (x1, y1) = ((x + lay.w + rx).min(aw).max(x + lay.w), (y + lay.h + ry).min(ah).max(y + lay.h));
                Shape::Free {
                    x: x0,
                    y: y0,
                    w: x1 - x0,
                    h: y1 - y0,
                }
            }
        }
    }

    /// Each screen's surfaces as the state wants them: made, laid out again, or taken away.
    pub fn apply(&mut self) {
        // a list whose group is gone, or under a drag or a pad that went, closes
        let gone = |l: &List| !self.visible_on(l.out) || self.drag.is_some() || self.list_group().is_none();
        if self.list.as_ref().is_some_and(gone) {
            self.drop_list();
        }
        // a press or a drag the pad went under is let go: its surface is gone, its release never comes
        if self.press.as_ref().is_some_and(|p| !self.visible_on(p.out)) {
            self.press = None;
        }
        if self.drag.as_ref().is_some_and(|d| !self.visible_on(d.out)) {
            self.drag = None;
        }
        if self.hover.is_some_and(|(oi, _)| !self.visible_on(oi)) {
            self.hover = None;
        }
        for oi in 0..self.outs.len() {
            self.apply_one(oi);
            self.apply_keyer(oi);
            self.apply_deco(oi);
        }
        self.dirty = true;
        self.refit();
    }

    /// A window event from sway: the focus order follows it, and the tree is read again.
    pub fn window_event(&mut self, change: &str, id: Option<i64>) {
        match (change, id) {
            ("focus", Some(id)) => self.history.focused(id),
            ("close", Some(id)) => {
                self.history.closed(id);
                self.sent.remove(&id);
            }
            _ => {}
        }
        self.look();
    }

    /// The tree read now, and every tick for the next two seconds: a command moved a window, or one may follow.
    pub fn look(&mut self) {
        self.burst_until = Some(Instant::now() + BURST);
        self.list_dirty = true;
    }

    /// A screen came, went or changed: spark-shell lays the placed windows out again (desktop window refit),
    /// half a second on and again a second later, as sway lays a screen out a moment after its event. Only
    /// the last event of a run counts.
    pub fn screens_changed(&mut self) {
        self.screens_gen += 1;
        let gen = self.screens_gen;
        for ms in [500, 1500] {
            let _ = self
                .handle
                .insert_source(Timer::from_duration(Duration::from_millis(ms)), move |_, _, app: &mut App| {
                    if app.screens_gen == gen {
                        spawn(&app.cfg.spark_shell, &["desktop", "window", "refit"]);
                    }
                    TimeoutAction::Drop
                });
        }
    }

    /// The voice state read, ten times a second: the mic and its bars follow it on every terminal's band.
    pub fn voice_tick(&mut self) {
        let t = &self.cfg.titles;
        if !t.voice {
            return;
        }
        let text = t.voice_state.as_ref().and_then(|p| std::fs::read_to_string(p).ok()).unwrap_or_default();
        let next = crate::buttons::mic_state(&text, &self.voice);
        if next != self.voice {
            self.voice = next;
            self.title_sync();
        }
    }

    /// The bar's state file read, ten times a second: where each screen's bar stands and the room it keeps. A
    /// file that is gone, or whose bar is, keeps what it last said for three seconds, a bar started again, and then
    /// says no bar.
    pub fn bar_tick(&mut self) {
        // a bar that does not come is waited for no longer than one that is gone
        let late = self.coming.iter().any(|c| !self.resting.contains(c));
        self.late = if late { self.late + 1 } else { 0 };
        if self.late == BAR_WAIT {
            self.coming.retain(|c| self.resting.contains(c));
            self.show_again();
        }
        let Some(file) = &self.cfg.bar_state else { return };
        // the text, and whether the pad is laid out again whatever it says: a bar back from being gone, or none come
        let (text, again) = match std::fs::read_to_string(file) {
            Ok(text) if text.starts_with("bar\t") && bar_runs(file) => {
                let back = self.bar_gone > 0;
                self.bar_gone = 0;
                if text == self.bar_text {
                    if back {
                        self.show_again(); // the same bar, back: the pad with it
                    }
                    return;
                }
                (text, back)
            }
            _ => {
                self.bar_gone = self.bar_gone.saturating_add(1);
                if self.bar_gone == 1 {
                    self.show_again(); // the bar went: the pad on it goes with it, and waits
                }
                if self.bar_gone != BAR_WAIT {
                    return;
                }
                (String::new(), true) // none came: the pad stands where it stood before the bar took it
            }
        };
        // the bar writes its state for more than where it stands (the pointer over it, a level it draws): the pad
        // is laid out again when a bar came, went or moved, not at every word of that. It was, ten times a second
        // while the pointer crossed the bar
        let bars = pad::bars(&text);
        let before: Vec<String> = self.bars.iter().map(|b| &b.0).chain(&self.coming).cloned().collect();
        let coming = pad::coming(&text, &before);
        self.bar_text = text;
        if again || bars != self.bars || coming != self.coming {
            (self.bars, self.coming) = (bars, coming);
            self.show_again();
        }
    }

    /// The pad laid out anew after the bar changed; a pad that is dragged is drawn again and laid out at its drop.
    fn show_again(&mut self) {
        if self.drag.is_none() {
            self.apply();
        } else {
            self.dirty = true;
        }
    }

    pub fn bursting(&self) -> bool {
        self.burst_until.is_some_and(|t| Instant::now() < t)
    }

    /// spark-shell lays the placed windows out again (desktop window refit) once each time a kept strip
    /// appears, goes, moves to another edge or changes its thickness: after a drag or a resize ends, never
    /// during one, and once sway holds the new strip. Not before sway has answered a sync sent behind the
    /// strip's commit: by then it has laid the windows' area out anew, so the refit reads the area as it
    /// is now (#273). Run aside, never waited on.
    fn refit(&mut self) {
        if self.drag.is_some() || self.outs.iter().any(|o| o.strip.as_ref().is_some_and(|k| !k.mapped)) {
            return;
        }
        let now: Vec<(String, Edge, i32)> = self
            .outs
            .iter()
            .filter_map(|o| o.strip.as_ref().map(|k| (o.name.clone(), k.edge, k.thick)))
            .collect();
        if now != self.refit_for || self.refit_owed {
            self.refit_for = now;
            self.refit_owed = false;
            self.refit_waiting += 1;
            self.conn.display().sync(&self.qh, Synced);
        }
    }

    /// The strip the pad keeps on a screen, made, moved or given back: kept as it is through a drag.
    fn apply_strip(&mut self, oi: usize) {
        let want = if self.visible_on(oi) { self.strip_for(oi) } else { None };
        if self.outs[oi].strip.as_ref().map(|k| (k.edge, k.thick)) == want {
            return;
        }
        let Some((edge, thick)) = want else {
            if let Some(k) = self.outs[oi].strip.take() {
                give_back(&k.layer);
                self.refit_owed |= !k.mapped;
            }
            return;
        };
        if self.outs[oi].strip.is_none() {
            let surface = self.compositor.create_surface(&self.qh);
            let layer = self
                .layer_shell
                .create_layer_surface(&self.qh, surface, Layer::Background, Some(NAMESPACE), Some(&self.outs[oi].output));
            layer.set_keyboard_interactivity(KeyboardInteractivity::None);
            if let Ok(region) = Region::new(&self.compositor) {
                layer.wl_surface().set_input_region(Some(region.wl_region()));
            }
            self.outs[oi].strip = Some(Kept {
                layer,
                edge,
                thick,
                mapped: false,
            });
        }
        let gap = self.m.gap;
        let k = self.outs[oi].strip.as_mut().unwrap();
        k.edge = edge;
        k.thick = thick;
        let (anchor, size, margin) = frame(edge, thick, gap);
        k.layer.set_anchor(anchor);
        k.layer.set_size(size.0, size.1);
        k.layer.set_margin(margin.0, margin.1, margin.2, margin.3);
        k.layer.set_exclusive_zone(thick);
        k.layer.commit();
    }

    /// The strip's surface shows nothing: one transparent pixel, so sway maps it and holds its zone.
    fn draw_strip(&mut self, oi: usize) {
        let Some(k) = self.outs[oi].strip.as_ref() else { return };
        let Ok((buffer, data)) = self.pool.create_buffer(1, 1, 4, wl_shm::Format::Argb8888) else {
            return;
        };
        data[..4].fill(0);
        let surface = k.layer.wl_surface().clone();
        if buffer.attach_to(&surface).is_ok() {
            surface.damage_buffer(0, 0, 1, 1);
            k.layer.commit();
            self.outs[oi].strip.as_mut().unwrap().mapped = true;
        }
    }

    /// While the pad has the keys, the screen it has them on holds a surface of one transparent pixel
    /// on the top layer that takes the keyboard; it takes no pointer and shows nothing.
    fn apply_keyer(&mut self, oi: usize) {
        let want = self.visible_on(oi) && self.keys.as_ref().is_some_and(|k| k.out == self.outs[oi].name);
        if !want {
            self.outs[oi].keyer = None;
            return;
        }
        if self.outs[oi].keyer.is_some() {
            return;
        }
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self
            .layer_shell
            .create_layer_surface(&self.qh, surface, Layer::Top, Some(NAMESPACE), Some(&self.outs[oi].output));
        layer.set_anchor(Anchor::TOP | Anchor::LEFT);
        layer.set_size(1, 1);
        layer.set_exclusive_zone(0);
        layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
        if let Ok(region) = Region::new(&self.compositor) {
            layer.wl_surface().set_input_region(Some(region.wl_region()));
        }
        layer.commit();
        self.outs[oi].keyer = Some(layer);
    }

    fn draw_keyer(&mut self, oi: usize) {
        let Some(l) = self.outs[oi].keyer.as_ref() else { return };
        let Ok((buffer, data)) = self.pool.create_buffer(1, 1, 4, wl_shm::Format::Argb8888) else {
            return;
        };
        data[..4].fill(0);
        let surface = l.wl_surface().clone();
        if buffer.attach_to(&surface).is_ok() {
            surface.damage_buffer(0, 0, 1, 1);
            l.commit();
        }
    }

    fn apply_one(&mut self, oi: usize) {
        if !self.visible_on(oi) {
            // the strip given back first, then the pad goes
            self.apply_strip(oi);
            self.outs[oi].surf = None;
            self.outs[oi].keyer = None;
            return;
        }
        if self.drag.is_none() {
            self.apply_strip(oi);
        }
        let shape = self.shape_for(oi);
        let keys = self.keys.as_ref().is_some_and(|k| k.out == self.outs[oi].name);
        if self.outs[oi].surf.is_none() {
            let surface = self.compositor.create_surface(&self.qh);
            let layer = self
                .layer_shell
                .create_layer_surface(&self.qh, surface, Layer::Top, Some(NAMESPACE), Some(&self.outs[oi].output));
            self.outs[oi].surf = Some(Surf {
                layer,
                shape: None,
                keys: None,
                size: (0, 0),
                configured: false,
                pad_at: (0, 0),
                lay: pad::layout(1, &self.want(oi, Form::Row), (1, 1), &self.m),
                items: vec![],
                list_at: None,
            });
        }
        let m = self.m;
        let s = self.outs[oi].surf.as_mut().unwrap();
        if s.shape == Some(shape) && s.keys == Some(keys) {
            return;
        }
        let l = &s.layer;
        // the pad is on the top layer always, above every window (full screen still covers it), and
        // reserves nothing: sway lays it out in the windows' area. Over a strip it keeps, that area ends
        // where the strip begins, so the margin goes the strip's thickness back over it: the pad stands
        // on the strip wherever sway put it, below a bar of any height at that edge, without being told.
        match shape {
            Shape::Strip { edge, thick, over } => {
                let (anchor, size, margin) = frame(edge, thick, if over > 0 { -over } else { m.gap });
                l.set_anchor(anchor);
                l.set_size(size.0, size.1);
                l.set_margin(margin.0, margin.1, margin.2, margin.3);
                l.set_exclusive_zone(0);
            }
            Shape::Free { x, y, w, h } => {
                l.set_anchor(Anchor::TOP | Anchor::LEFT);
                l.set_size(w as u32, h as u32);
                l.set_margin(y, 0, 0, x);
                l.set_exclusive_zone(0);
            }
            Shape::Full { back, bar } => {
                // the area as it is without the strip kept through it: the drag's frame; and with the bar, under a
                // list and under a move. A strip at the bar's edge stands inside the bar's zone: the two add up
                let mut far = (0, 0, 0, 0);
                for (edge, by) in back.into_iter().chain(bar) {
                    let add = frame(edge, 0, -by).2;
                    far = (far.0 + add.0, far.1 + add.1, far.2 + add.2, far.3 + add.3);
                }
                l.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
                l.set_size(0, 0);
                l.set_margin(far.0, far.1, far.2, far.3);
                l.set_exclusive_zone(0);
            }
        }
        // the keys go to a surface of their own (the keyer): sway gives the keyboard only to the top
        // layers, and the pad stays where it stands
        l.set_keyboard_interactivity(KeyboardInteractivity::None);
        s.shape = Some(shape);
        s.keys = Some(keys);
        // the surface keeps showing its last frame until the compositor's configure: then it is drawn again
        l.commit();
    }

    /// sway's tree read again: the title bands in sight, the focus order, the windows on the pad, oldest first,
    /// and the screens at rest.
    pub fn refresh_list(&mut self) {
        self.list_dirty = false;
        let tree = match self.ipc.tree() {
            Ok(t) => t,
            Err(e) => {
                // one answer missed: everything stays as it stands until the next look
                eprintln!("spark-winpad: sway did not answer: {e}");
                self.misses += 1;
                if self.misses >= MISSES {
                    self.failed = Some("sway does not answer".into());
                    self.stop = true;
                }
                return;
            }
        };
        self.misses = 0;
        let bands = crate::buttons::bands(&tree, self.cell);
        if bands != self.bands {
            self.bands = bands;
            self.deco_dirty = true;
        }
        self.title_sync();
        self.history.seed(&crate::order::in_sight(&tree));
        let wins = pad::minimized(&tree);
        let resting = pad::resting(&tree, &self.cfg.rest);
        if wins == self.wins && resting == self.resting {
            return;
        }
        let added = wins.len() > self.wins.len();
        self.wins = wins;
        self.resting = resting;
        if self.wins.is_empty() {
            self.keys = None;
        }
        // the keys go back when their screen starts to rest, as the bar's do: kept, the pad would take the
        // keyboard again when the idle screen ends
        if self.keys.as_ref().is_some_and(|k| self.resting.contains(&k.out)) {
            self.list = None;
            if self.keys.take().is_some_and(|k| k.temp) {
                self.hidden = true;
            }
        }
        let cells = self.cells_for_keys();
        if added && self.keys.is_some() {
            self.sel = cells.saturating_sub(1);
        }
        self.sel = self.sel.min(cells.saturating_sub(1));
        if self.keys_wanted && !self.wins.is_empty() {
            self.keys_wanted = false;
            self.keys_on();
        }
        self.apply();
        self.write_state();
    }

    /// The screen the keys are on.
    fn keys_out(&self) -> Option<usize> {
        let k = self.keys.as_ref()?;
        self.outs.iter().position(|o| o.name == k.out)
    }

    /// How many cells the pad has where the keys are, or on the first screen.
    fn cells_for_keys(&self) -> usize {
        match self.keys_out().or((!self.outs.is_empty()).then_some(0)) {
            Some(oi) => self.items_on(oi, self.form_on(oi)).0.len(),
            None => self.wins.len(),
        }
    }

    /// The hidden state and the count for the bar, and the bar told to draw again; once a change.
    pub fn write_state(&mut self) {
        let now = (self.hidden && self.keys.is_none(), self.wins.len());
        if self.written == Some(now) {
            return;
        }
        self.written = Some(now);
        if let Some(f) = &self.cfg.state_file {
            let tmp = f.with_extension("new");
            if std::fs::write(&tmp, format!("hidden {}\ncount {}\n", u8::from(now.0), now.1)).is_ok() {
                let _ = std::fs::rename(&tmp, f);
            }
        }
        if let Some(pid) = self
            .cfg
            .bar_pid
            .as_ref()
            .and_then(|f| std::fs::read_to_string(f).ok())
            .and_then(|s| s.trim().parse::<i32>().ok())
        {
            // the file outlives a crash and a restart of the machine: by then its pid is another program's, and the
            // signal's own action would end that program. Sent only to a process that is the status loop still
            let is_loop = std::fs::read(format!("/proc/{pid}/cmdline")).is_ok_and(|c| is_status_loop(&c));
            if pid > 1 && is_loop {
                unsafe {
                    libc::kill(pid, libc::SIGUSR1);
                }
            }
        }
    }

    pub fn toggle_hidden(&mut self) {
        self.hidden = !self.hidden;
        self.keys = None;
        self.list = None;
        self.press = None;
        self.drag = None;
        self.apply();
        self.write_state();
    }

    /// Super+minus: the pad in sight with the keyboard on it, on the screen sway has the focus on,
    /// the newest picked. Not on a screen at rest, and not kept for when it is back.
    pub fn keys_on(&mut self) {
        if self.wins.is_empty() {
            self.keys_wanted = true;
            return;
        }
        let out = self
            .ipc
            .focused_output()
            .or_else(|| self.outs.first().map(|o| o.name.clone()))
            .unwrap_or_default();
        if self.resting.contains(&out) {
            return;
        }
        let temp = self.keys.as_ref().map_or(self.hidden, |k| k.temp);
        self.keys = Some(Keys { out, temp });
        if let Some(l) = self.list.as_mut() {
            l.took_keys = false;
        }
        self.sel = self.cells_for_keys().saturating_sub(1);
        self.tip_wake();
        self.apply();
        self.write_state();
    }

    fn keys_off(&mut self) {
        self.list = None;
        if let Some(k) = self.keys.take() {
            if k.temp {
                self.hidden = true;
            }
        }
        self.apply();
        self.write_state();
    }

    /// A window back, by its place in the list.
    fn restore(&mut self, w: usize, oi: usize) {
        let Some(win) = self.wins.get(w) else { return };
        let id = win.id;
        if let Some(o) = self.outs.get(oi) {
            let _ = self.ipc.run(&format!("focus output \"{}\"", o.name.replace('"', "")));
        }
        spawn(&self.cfg.spark_shell, &["desktop", "window", "restore", &id.to_string()]);
        self.list = None;
        if self.keys.is_some() {
            self.keys_off();
        } else {
            self.apply();
        }
    }

    /// A cell chosen, by a click or Enter: its window back, or a group's list opened beside it.
    fn choose(&mut self, i: usize, oi: usize) {
        let Some(item) = self.outs.get(oi).and_then(|o| o.surf.as_ref()).and_then(|s| s.items.get(i)).cloned() else {
            return;
        };
        if item.group() {
            self.open_list(oi, i, &item);
        } else {
            self.restore(item.wins[0], oi);
        }
    }

    /// A group's list opened beside its icon, the newest picked. It takes the keyboard for Enter and Esc when the
    /// pad did not have it, and gives it back when it closes.
    fn open_list(&mut self, oi: usize, i: usize, item: &Item) {
        let names = self.names();
        let took_keys = self.keys.is_none();
        if took_keys {
            self.keys = Some(Keys {
                out: self.outs[oi].name.clone(),
                temp: self.hidden,
            });
        }
        self.sel = i;
        self.list = Some(List {
            out: oi,
            app: names[item.wins[0]].clone(),
            sel: item.wins.len() - 1,
            hover: None,
            took_keys,
        });
        self.press = None;
        self.hover = None;
        self.tip_hover();
        self.apply();
        self.write_state();
    }

    /// The open list's group as the pad shows it now: its cell and its windows; None when that group is gone.
    fn list_group(&self) -> Option<(usize, Vec<usize>)> {
        let l = self.list.as_ref()?;
        if l.out >= self.outs.len() {
            return None;
        }
        let names = self.names();
        let (items, _) = self.items_on(l.out, self.form_on(l.out));
        items
            .into_iter()
            .enumerate()
            .find(|(_, it)| it.group() && names[it.wins[0]] == l.app)
            .map(|(i, it)| (i, it.wins))
    }

    /// The list closed; the keyboard it took given back.
    fn drop_list(&mut self) {
        if let Some(l) = self.list.take() {
            if l.took_keys {
                if let Some(k) = self.keys.take() {
                    if k.temp {
                        self.hidden = true;
                    }
                }
            }
        }
    }

    /// Esc or a click outside: the list closes.
    fn close_list(&mut self) {
        self.drop_list();
        self.apply();
        self.write_state();
    }

    fn save_place(&self) {
        let words = self.cfg.place.words();
        spawn(
            &self.cfg.spark_shell,
            &[
                "desktop",
                "pad",
                "place",
                &words,
                &self.cfg.width.to_string(),
                &self.cfg.side_width.to_string(),
                &self.cfg.height.to_string(),
            ],
        );
    }

    fn picture(&mut self, app: &str) -> Option<&Picture> {
        let key = pad::icon_key(app);
        if !self.pictures.contains_key(&key) {
            let p = self.icon_paths.get(&key).and_then(|path| Picture::png(&self.lib, path));
            self.pictures.insert(key.clone(), p);
        }
        self.pictures.get(&key).and_then(Option::as_ref)
    }

    /// The cell lit on a screen: under the pointer, the one the keys picked, or the group whose list is open.
    fn lit_on(&self, oi: usize) -> Option<usize> {
        if let Some((o, i)) = self.hover {
            if o == oi {
                return Some(i);
            }
        }
        let keys_here = self.keys.as_ref().is_some_and(|k| self.outs.get(oi).is_some_and(|o| o.name == k.out));
        keys_here.then_some(self.sel)
    }

    /// A cell's words: a window's app and title, or a group's app and how many windows it holds.
    fn item_words(&self, it: &Item) -> (String, Option<String>) {
        let w = &self.wins[it.wins[0]];
        if it.wins.iter().any(|&i| pad::app_name(&self.wins[i].app) != pad::app_name(&w.app)) {
            ("more".into(), Some(format!("{} windows", it.wins.len())))
        } else if it.group() {
            pad::group_words(&w.app, it.wins.len())
        } else {
            pad::item_words(&w.app, &w.title)
        }
    }

    /// Every configured surface drawn again.
    pub fn draw_all(&mut self) {
        self.dirty = false;
        for oi in 0..self.outs.len() {
            self.draw(oi);
        }
    }

    fn draw(&mut self, oi: usize) {
        let Some(s) = self.outs[oi].surf.as_ref() else { return };
        if !s.configured || s.size.0 <= 0 || s.size.1 <= 0 || self.wins.is_empty() {
            return;
        }
        let (Some(shape), size) = (s.shape, s.size) else { return };
        let m = self.m;
        let scale = self.outs[oi].scale.max(1);
        let full = matches!(shape, Shape::Full { .. });
        let form = self.form_on(oi);
        let place = self.place_on(oi);
        let (items, lay) = self.items_on(oi, form);
        let (aw, ah) = self.outs[oi].area;
        let bar = self.bar_on(oi).filter(|_| form == Form::Bar);
        // where the windows' area begins on a surface that reaches over the bar: under a bar at the top; a bar at
        // the bottom comes after the area's rows
        let lift = match shape {
            Shape::Full {
                bar: Some((Edge::Top, far)), ..
            } => far,
            _ => 0,
        };
        // where the pad stands on this surface
        let pad_at = match (shape, bar) {
            // on the bar, the surface over it: in the bar's room, on the bar's own rows; a move that holds the bar
            // shows the pad there too, as it will stand
            (Shape::Full { bar: Some(_), .. } | Shape::Strip { .. }, Some(b)) => (b.x, if b.edge == Edge::Bottom { size.1 - lay.h } else { 0 }),
            // dragged: where the drag has it, in the windows' area; under a list: where it stands
            (Shape::Full { .. }, _) => {
                let at = self.drag.as_ref().and_then(|d| d.pad);
                let (x, y) = at.unwrap_or_else(|| pad::position(place, lay.w, lay.h, aw, ah, &m));
                (x, y + lift)
            }
            (Shape::Strip { edge: Edge::Bottom, .. }, None) => (pad::position(place, lay.w, lay.h, size.0, ah, &m).0, size.1 - lay.h),
            (Shape::Strip { edge: Edge::Top, .. }, None) => (pad::position(place, lay.w, lay.h, size.0, ah, &m).0, 0),
            (Shape::Strip { edge: Edge::Left, .. }, None) => (0, pad::position(place, lay.w, lay.h, aw, size.1, &m).1),
            (Shape::Strip { edge: Edge::Right, .. }, None) => (size.0 - lay.w, pad::position(place, lay.w, lay.h, aw, size.1, &m).1),
            // a free surface has the room around the pad
            (Shape::Free { x, y, .. }, _) => {
                let (px, py) = pad::position(place, lay.w, lay.h, aw, ah, &m);
                (px - x, py - y)
            }
        };
        let dock = bar.map(|b| b.edge).or(place.edge());
        let lit = self.lit_on(oi);
        let keys_here = self.keys.as_ref().is_some_and(|k| k.out == self.outs[oi].name);
        let apps: Vec<String> = items.iter().map(|it| self.wins[it.wins[0]].app.clone()).collect();
        for app in &apps {
            let _ = self.picture(app);
        }
        let words: Vec<(String, Option<String>)> = items.iter().map(|it| self.item_words(it)).collect();
        let lit_line = lit.and_then(|i| words.get(i)).map(|w| pad::line(w.clone()));
        let tip = pad::labeled(&lay, &m) && !full && lit_line.is_some() && (self.tip.on || keys_here) && !self.tip.quiet;
        let moved = full && self.drag.as_ref().is_some_and(|d| d.kind == Grab::Move);
        let near = self.drag.as_ref().and_then(|d| d.near).filter(|_| moved);
        let lands = bar.filter(|_| moved && self.drag.as_ref().is_some_and(|d| d.on_bar));
        // a group of several apps' windows, the rest the bar's one row has no cell for: three dots, no app's icon
        let mixed: Vec<bool> = items
            .iter()
            .map(|it| {
                it.wins
                    .iter()
                    .any(|&w| pad::app_name(&self.wins[w].app) != pad::app_name(&self.wins[it.wins[0]].app))
            })
            .collect();
        // the open list's rows: each window's words as a label says them, the newest last
        let list = self.list.as_ref().filter(|l| l.out == oi && full).and_then(|l| {
            let (gi, wins) = self.list_group()?;
            let lines: Vec<String> = wins.iter().map(|&w| pad::item_line(&self.wins[w].app, &self.wins[w].title)).collect();
            let picked = l.hover.or(keys_here.then_some(l.sel));
            Some((gi, lines, picked))
        });
        let (bw, bh) = (size.0 * scale, size.1 * scale);
        let Ok((buffer, data)) = self.pool.create_buffer(bw, bh, bw * 4, wl_shm::Format::Argb8888) else {
            eprintln!("spark-winpad: no shared memory for a frame");
            return;
        };
        let mut list_at = None;
        {
            let Some(c) = Canvas::new(&self.lib, &self.fonts, data, bw, bh, bw * 4, scale as f64) else {
                return;
            };
            let look = &self.cfg.look;
            let (ox, oy) = (pad_at.0 as f64, pad_at.1 as f64);
            let (w, h) = (lay.w as f64, lay.h as f64);
            let pad_r = Rect::new(pad_at.0, pad_at.1, lay.w, lay.h);
            // off the bar the pad is a piece of it: the bar's ground, and a fine edge (drawn last) so it reads on any
            // ground, the accent while the pad has the keys. On the bar it has neither: the bar's own ground shows
            if !lay.bar {
                c.fill(ox, oy, w, h, look.ground, look.alpha);
            }
            if lay.band {
                let br = lay.band_rect(&m);
                let (by, b) = (oy + br.y as f64, br.h as f64);
                c.fill(ox, by, w, b, look.band, look.alpha);
                let says = pad::band_words(lay.w, self.wins.len(), lit_line.as_deref(), &m);
                c.text(ox + 6.0, by, w - 12.0, b, &says, look.fg, true, Align::Center);
            }
            // the grip: a line in the middle of its room, half as long as the room is across, as the bar's hairline
            // is; on the bar, where the pad has no edge, it is the accent while the pad has the keys
            let lr = lay.lead_rect(&m);
            let grip = if keys_here && lay.bar { look.accent } else { look.dim };
            if lay.column {
                let len = (lr.w / 2) as f64;
                c.fill(ox + (lr.w as f64 - len) / 2.0, oy + (lr.y + lr.h / 2) as f64, len, 1.0, grip, 1.0);
            } else {
                let len = (lr.h / 2) as f64;
                c.fill(ox + (lr.x + lr.w / 2) as f64, oy + lr.y as f64 + (lr.h as f64 - len) / 2.0, 1.0, len, grip, 1.0);
            }
            // hide, muted, at the end of the cells; the bar's row has none
            if !lay.bar {
                let hr = pad::hide_rect(&lay, &m);
                c.text(
                    ox + hr.x as f64,
                    oy + hr.y as f64,
                    hr.w as f64,
                    hr.h as f64,
                    "\u{2212}",
                    look.muted,
                    false,
                    Align::Center,
                );
            }
            // a lit cell's chip on the bar is the bar's own: the plate's height, a ninth of the bar in from its ends
            let chip = if lay.bar { (lay.h as f64 / 9.0).round() } else { 0.0 };
            let inset = (m.icon as f64 / 3.0).round();
            let side_px = m.icon as f64;
            for (i, (it, (app, (name, rest)))) in items.iter().zip(apps.iter().zip(&words)).enumerate() {
                let r = pad::item_rect(&lay, i, &m);
                let (rx, ry) = (ox + r.x as f64, oy + r.y as f64);
                let lit_here = lit == Some(i) || list.as_ref().is_some_and(|(gi, ..)| *gi == i);
                if lit_here {
                    c.fill(
                        rx,
                        ry + chip,
                        r.w as f64,
                        r.h as f64 - 2.0 * chip,
                        look.lit,
                        if lay.bar { 1.0 } else { look.alpha },
                    );
                }
                let (ix, iy) = match lay.view {
                    View::Icons => (rx + (r.w as f64 - side_px) / 2.0, ry + (r.h as f64 - side_px) / 2.0),
                    View::Titles => (rx + inset, ry + (r.h as f64 - side_px) / 2.0),
                };
                match self.pictures.get(&pad::icon_key(app)).and_then(Option::as_ref).filter(|_| !mixed[i]) {
                    Some(p) => c.picture(p, ix, iy, side_px),
                    None => {
                        c.fill(ix, iy, side_px, side_px, look.lit, 1.0);
                        let letter: String = if mixed[i] {
                            "\u{2026}".into()
                        } else {
                            name.chars()
                                .find(|ch| ch.is_alphanumeric())
                                .map(|ch| ch.to_uppercase().collect())
                                .unwrap_or_default()
                        };
                        c.text(ix, iy, side_px, side_px, &letter, look.fg, true, Align::Center);
                    }
                }
                // a group's count, circled and filled, in the accent over the icon's top right corner
                if let Some(ch) = pad::badge(it.wins.len()) {
                    c.badge(ix + side_px - 2.0, iy + 2.0, &ch.to_string(), look.accent);
                }
                if lay.view == View::Titles {
                    // the app's name in the text color, then the title muted; a lit item both in the text color
                    let tx = ix + side_px + inset;
                    let room = r.w as f64 - (inset + side_px + inset + inset * 1.75);
                    let name_w = c.text(tx, ry, room, r.h as f64, name, look.fg, false, Align::Left);
                    if let Some(rest) = rest {
                        if let Some((at, tw)) = pad::title_room(room, name_w, c.measure("  ", false), self.fonts.px) {
                            c.text(
                                tx + at,
                                ry,
                                tw,
                                r.h as f64,
                                rest,
                                if lit_here { look.fg } else { look.muted },
                                false,
                                Align::Left,
                            );
                        }
                    }
                }
            }
            // the edge last, over a lit cell that reaches it: it runs all around, whatever is lit
            if !lay.bar {
                let edge = if keys_here { look.accent } else { look.lit };
                c.fill(ox, oy, w, 1.0, edge, 1.0);
                c.fill(ox, oy + h - 1.0, w, 1.0, edge, 1.0);
                c.fill(ox, oy + 1.0, 1.0, h - 2.0, edge, 1.0);
                c.fill(ox + w - 1.0, oy + 1.0, 1.0, h - 2.0, edge, 1.0);
            }
            if let (true, Some(line), Some(i)) = (tip, lit_line.as_deref(), lit) {
                // the lit cell's words beside the pad, away from the edge it sits on
                let r = pad::item_rect(&lay, i, &m);
                let cell = Rect::new(pad_at.0 + r.x, pad_at.1 + r.y, r.w, r.h);
                let pad_text = 10.0;
                let tw = (c.measure(line, false) + 2.0 * pad_text).min(m.tip_room as f64 - 8.0).ceil() as i32;
                let (tx, ty) = pad::beside(pad_r, cell, (tw, m.tip), dock, size);
                let (tx, ty, tw, th) = (tx as f64, ty as f64, tw as f64, m.tip as f64);
                c.fill(tx, ty, tw, th, look.surface, 0.95);
                c.text(tx + pad_text, ty, tw - 2.0 * pad_text, th, line, look.fg, false, Align::Left);
            }
            if let Some((gi, lines, picked)) = &list {
                // the group's list beside it, a row a window
                let r = pad::item_rect(&lay, *gi, &m);
                let cell = Rect::new(pad_at.0 + r.x, pad_at.1 + r.y, r.w, r.h);
                let pad_text = 10.0;
                let lw = lines.iter().map(|l| c.measure(l, false)).fold(0.0, f64::max) + 2.0 * pad_text;
                let lw = lw.clamp(m.tool as f64 * 3.0, m.tip_room as f64).ceil() as i32;
                let lr = pad::list_rect(pad_r, cell, lines.len(), lw, m.tip, dock, size);
                c.fill(lr.x as f64 - 1.0, lr.y as f64 - 1.0, lr.w as f64 + 2.0, lr.h as f64 + 2.0, look.lit, 1.0);
                c.fill(lr.x as f64, lr.y as f64, lr.w as f64, lr.h as f64, look.surface, look.alpha.max(0.95));
                for (j, line) in lines.iter().enumerate() {
                    let ry = (lr.y + j as i32 * m.tip) as f64;
                    if *picked == Some(j) {
                        c.fill(lr.x as f64, ry, lr.w as f64, m.tip as f64, look.lit, 1.0);
                    }
                    c.text(
                        lr.x as f64 + pad_text,
                        ry,
                        lr.w as f64 - 2.0 * pad_text,
                        m.tip as f64,
                        line,
                        look.fg,
                        false,
                        Align::Left,
                    );
                }
                list_at = Some((lr, lines.len()));
            }
            if let Some(e) = near {
                // the edge's line, counted in the windows' area as the pad's place along the edge is
                let in_area = Rect::new(pad_at.0, pad_at.1 - lift, lay.w, lay.h);
                let along = pad::snap_along(e, in_area, aw, ah, &m);
                let (dx, dy) = pad::position(Place::Dock(e, along), lay.w, lay.h, aw, ah, &m);
                let (lx, ly, lw, lh) = match e {
                    Edge::Bottom => (dx, ah - 3, lay.w, 3),
                    Edge::Top => (dx, 0, lay.w, 3),
                    Edge::Left => (0, dy, 3, lay.h),
                    Edge::Right => (aw - 3, dy, 3, lay.h),
                };
                c.fill(lx as f64, (ly + lift) as f64, lw as f64, lh as f64, look.accent, 1.0);
            }
            if let Some(b) = lands {
                // a drag that holds the bar: the pad is shown on the bar, where it lands, and the line marks it at
                // the screen's edge, as at any edge: the surface's own edge there, which reaches over the bar
                let ly = if b.edge == Edge::Bottom { size.1 - 3 } else { 0 };
                c.fill(pad_at.0 as f64, ly as f64, lay.w as f64, 3.0, look.accent, 1.0);
            }
        }
        let s = self.outs[oi].surf.as_mut().unwrap();
        s.pad_at = pad_at;
        s.lay = lay;
        s.items = items;
        s.list_at = list_at;
        let surface = s.layer.wl_surface().clone();
        if let Ok(region) = Region::new(&self.compositor) {
            if full {
                region.add(0, 0, size.0, size.1);
            } else {
                // the pad and its grips just outside it; a pad on the bar has none
                let g = if lay.bar { 0 } else { m.grip };
                region.add(pad_at.0 - g, pad_at.1 - g, lay.w + 2 * g, lay.h + 2 * g);
            }
            surface.set_input_region(Some(region.wl_region()));
        }
        surface.set_buffer_scale(scale);
        if buffer.attach_to(&surface).is_ok() {
            surface.damage_buffer(0, 0, bw, bh);
            s.layer.commit();
        }
    }

    fn out_of(&self, surface: &WlSurface) -> Option<usize> {
        self.outs.iter().position(|o| o.surf.as_ref().is_some_and(|s| s.layer.wl_surface() == surface))
    }

    /// What the pointer is on: a row of the open list, a cell, a button, the handle, a grip.
    fn hit_at(&self, oi: usize, pos: (f64, f64)) -> Hit {
        let Some(s) = self.outs.get(oi).and_then(|o| o.surf.as_ref()) else {
            return Hit::Nothing;
        };
        if let Some((r, rows)) = s.list_at.filter(|_| self.list.as_ref().is_some_and(|l| l.out == oi)) {
            if let Some(i) = pad::list_row(r, self.m.tip, rows, pos.0, pos.1) {
                return Hit::Row(i);
            }
        }
        let (x, y) = (pos.0 - s.pad_at.0 as f64, pos.1 - s.pad_at.1 as f64);
        pad::hit(&s.lay, s.items.len(), &self.m, x, y, self.place_on(oi).edge())
    }

    fn set_cursor(&mut self, want: Cursor) {
        let Some(p) = self.pointer.as_mut() else { return };
        if p.cursor == Some(want) {
            return;
        }
        if let Some(d) = &p.device {
            d.set_shape(p.serial, want);
            p.cursor = Some(want);
        }
    }

    fn motion(&mut self, oi: Option<usize>, pos: (f64, f64)) {
        if self.drag.is_some() {
            self.drag_motion(pos);
            return;
        }
        // a press anywhere on the pad becomes a drag 6 px on: a move, or a size from a grip
        if let Some(kind) = self.press.as_mut().and_then(|p| p.gesture.moved(pos)) {
            let p = self.press.take().unwrap();
            self.hover = None;
            self.tip_hover();
            let from = self.outs.get(p.out).and_then(|o| o.surf.as_ref()).and_then(|s| s.shape);
            let was = self.form_on(p.out);
            // an edge the pad is docked at is the edge the drag holds, until the pointer leaves it; and so is the bar
            self.drag = Some(Drag {
                kind,
                out: p.out,
                off: p.off,
                at: p.gesture.at,
                was,
                on_bar: was == Form::Bar && kind == Grab::Move,
                pad: None,
                start: Rect::default(),
                near: self.place_on(p.out).edge(),
                from,
                origin: (0, 0),
            });
            // through a move the pointer stays the holding hand it is over the grip, the one sway shows on a window
            // that is dragged (its name there is grab)
            self.set_cursor(match kind {
                Grab::Move => Cursor::Grab,
                Grab::Grip(s) => resize_cursor(s),
            });
            self.apply();
            return;
        }
        let Some(oi) = oi else { return };
        let what = self.hit_at(oi, pos);
        self.set_cursor(match what {
            Hit::Item(_) | Hit::Hide | Hit::Row(_) => Cursor::Pointer,
            Hit::Handle => Cursor::Grab,
            Hit::Grip(s) => resize_cursor(s),
            Hit::Nothing => Cursor::Default,
        });
        if let Some(l) = self.list.as_mut().filter(|l| l.out == oi) {
            let row = if let Hit::Row(i) = what { Some(i) } else { None };
            if row != l.hover {
                l.hover = row;
                if let Some(i) = row {
                    l.sel = i;
                }
                self.dirty = true;
            }
            return;
        }
        let item = if let Hit::Item(i) = what { Some((oi, i)) } else { None };
        if item != self.hover {
            self.hover = item;
            if let (Some((_, i)), true) = (item, self.keys.is_some()) {
                self.sel = i;
            }
            self.tip_hover();
            self.tip_wake();
            self.dirty = true;
        }
    }

    fn drag_motion(&mut self, pos: (f64, f64)) {
        let Some(d) = self.drag.as_ref() else { return };
        let Some(_) = d.pad else { return };
        let moved = (pos.0 - d.at.0, pos.1 - d.at.1);
        let pos = (pos.0 + d.origin.0 as f64, pos.1 + d.origin.1 as f64);
        let (oi, kind, off, start, was) = (d.out, d.kind, d.off, d.start, d.was);
        let (held, on_bar) = (d.near, d.on_bar);
        let (aw, ah) = self.outs[oi].area;
        let m = self.m;
        match kind {
            Grab::Move => {
                // the bar holds the pad while the pointer is on the bar itself, counted into the windows' area from
                // the bar's edge; else the edge from the pointer, never from the pad's outline, which the edge changes
                let bar = self.bar_on(oi);
                let into = |b: &BarAt| if b.edge == Edge::Bottom { ah as f64 - pos.1 } else { pos.1 };
                let on_bar = bar.is_some_and(|b| pad::drag_bar(on_bar, into(&b), b.height));
                let near = if on_bar { None } else { pad::drag_edge(held, pos, aw, ah, &m) };
                let form = if on_bar { Form::Bar } else { Form::at(near) };
                let d = self.drag.as_mut().unwrap();
                (d.near, d.on_bar) = (near, on_bar);
                let lay = self.layout_on(oi, form);
                let at = match bar.filter(|_| on_bar) {
                    // on the bar the pad is shown where it lands, in the bar's own room, by a surface that reaches over
                    // the bar; one that does not (the bar came after the drag began) shows it here, at the bar's edge
                    // of the windows' area
                    Some(b) => (b.x.min((aw - lay.w).max(0)), if b.edge == Edge::Bottom { (ah - lay.h).max(0) } else { 0 }),
                    None => {
                        // the pointer keeps its place on the pad; on a pad that took another form, the grip is under it
                        let lr = lay.lead_rect(&m);
                        let (gx, gy) = if form != was {
                            ((lr.x + lr.w / 2) as f64, (lr.y + lr.h / 2) as f64)
                        } else {
                            (off.0.min(lay.w as f64 - 12.0).max(0.0), off.1.min(lay.h as f64 - 4.0).max(0.0))
                        };
                        let x = ((pos.0 - gx).round() as i32).clamp(0, (aw - lay.w).max(0));
                        let y = ((pos.1 - gy).round() as i32).clamp(0, (ah - lay.h).max(0));
                        (x, y)
                    }
                };
                self.drag.as_mut().unwrap().pad = Some(at);
            }
            Grab::Grip(s) => {
                // the width sets the columns, the height the rows; a docked pad grows away from its edge
                let place = self.place_on(oi);
                let form = self.form_on(oi);
                let (w, h) = pad::grip_size(place, s, start, moved, self.room(oi, form), &m);
                if let Some(w) = w {
                    if place.side() {
                        self.cfg.side_width = w.max(SIDE_LEAST);
                    } else {
                        self.cfg.width = w;
                    }
                }
                if let Some(h) = h {
                    self.cfg.height = h;
                }
                let lay = self.layout_on(oi, form);
                self.cfg.place = pad::grip_place(self.cfg.place, s, start, lay.w, lay.h);
                let at = pad::position(self.place_on(oi), lay.w, lay.h, aw, ah, &m);
                self.drag.as_mut().unwrap().pad = Some(at);
            }
        }
        self.dirty = true;
    }

    fn press(&mut self, oi: Option<usize>, pos: (f64, f64)) {
        let Some(oi) = oi else { return };
        let what = self.hit_at(oi, pos);
        if self.list.is_some() && !matches!(what, Hit::Row(_)) {
            // a click outside the list closes it, and does nothing else
            self.close_list();
            return;
        }
        let pad_at = self.outs[oi].surf.as_ref().map_or((0, 0), |s| s.pad_at);
        self.press = Some(Press {
            out: oi,
            gesture: Gesture::press(what, pos),
            off: (pos.0 - pad_at.0 as f64, pos.1 - pad_at.1 as f64),
        });
    }

    fn release(&mut self, oi: Option<usize>, pos: (f64, f64)) {
        if let Some(d) = self.drag.take() {
            // the drop lands on the bar while the drag holds it, else docks at the edge the drag holds
            if let (Grab::Move, Some((x, y))) = (d.kind, d.pad) {
                let (aw, ah) = self.outs[d.out].area;
                let form = if d.on_bar { Form::Bar } else { Form::at(d.near) };
                let lay = self.layout_on(d.out, form);
                let r = Rect::new(x, y, lay.w, lay.h);
                if (form == Form::Column) != self.cfg.place.side() {
                    // a row turned a column or back: as many rows as it needs, until it is sized again
                    self.cfg.height = 0;
                }
                self.cfg.place = match d.near {
                    _ if d.on_bar => Place::Bar,
                    Some(e) => Place::Dock(e, pad::snap_along(e, r, aw, ah, &self.m)),
                    None => Place::Free(x, y),
                };
            }
            self.press = None;
            self.set_cursor(Cursor::Default);
            self.apply();
            self.save_place();
            return;
        }
        let Some(p) = self.press.take() else { return };
        let Some(oi) = oi.filter(|&o| o == p.out) else { return };
        match p.gesture.released(self.hit_at(oi, pos)) {
            Click::Choose(i) => self.choose(i, oi),
            Click::Row(i) => {
                if let Some((_, wins)) = self.list_group() {
                    if let Some(&w) = wins.get(i) {
                        self.restore(w, oi);
                    }
                }
            }
            Click::Hide => self.toggle_hidden(),
            Click::Nothing => {}
        }
    }

    fn key(&mut self, code: u32) {
        if self.keys.is_none() {
            return;
        }
        let Some(k) = self.kb.key(code) else { return };
        if let Some((l_out, l_sel)) = self.list.as_ref().map(|l| (l.out, l.sel)) {
            let wins = self.list_group().map(|(_, w)| w).unwrap_or_default();
            match pad::list_key(k, l_sel, wins.len()) {
                ListAct::Pick(i) => {
                    if let Some(l) = self.list.as_mut() {
                        l.sel = i;
                        l.hover = None;
                    }
                    self.dirty = true;
                }
                ListAct::Restore(i) => self.restore(wins[i], l_out),
                ListAct::Close => self.close_list(),
                ListAct::Nothing => {}
            }
            return;
        }
        let oi = self.keys_out().unwrap_or(0);
        let (cells, cols) = self
            .outs
            .get(oi)
            .and_then(|o| o.surf.as_ref())
            .map_or((self.wins.len(), 1), |s| (s.items.len(), s.lay.cols.max(1) as usize));
        match pad::key(k, self.sel, cells, cols) {
            KeyAct::Pick(i) => {
                self.sel = i;
                self.hover = None;
                self.tip_wake();
                self.dirty = true;
            }
            KeyAct::Choose(i) => self.choose(i, oi),
            KeyAct::Leave => self.keys_off(),
            KeyAct::Nothing => {}
        }
    }

    /// A label: 400 ms on the first cell, at once from cell to cell, gone a moment after the last.
    fn tip_hover(&mut self) {
        self.tip.gen += 1;
        if self.hover.is_none() {
            if self.tip.on {
                self.tip.on = false;
                self.tip.gone = Some(Instant::now());
            }
            return;
        }
        if self.tip.on || self.tip.gone.is_some_and(|t| t.elapsed() < Duration::from_millis(300)) {
            self.tip.on = true;
            return;
        }
        let gen = self.tip.gen;
        let _ = self
            .handle
            .insert_source(Timer::from_duration(Duration::from_millis(400)), move |_, _, app: &mut App| {
                if app.tip.gen == gen && app.hover.is_some() {
                    app.tip.on = true;
                    app.dirty = true;
                }
                TimeoutAction::Drop
            });
    }

    /// Like any tooltip, the label goes by itself 5 s after the last move or key.
    fn tip_wake(&mut self) {
        self.tip.quiet = false;
        self.tip.quiet_gen += 1;
        let gen = self.tip.quiet_gen;
        let _ = self
            .handle
            .insert_source(Timer::from_duration(Duration::from_secs(5)), move |_, _, app: &mut App| {
                if app.tip.quiet_gen == gen {
                    app.tip.quiet = true;
                    app.dirty = true;
                }
                TimeoutAction::Drop
            });
    }

    fn scale_of(&self, output: &WlOutput) -> i32 {
        self.outputs.info(output).map_or(1, |i| i.scale_factor.max(1))
    }

    fn logical_of(&self, output: &WlOutput) -> (i32, i32) {
        self.outputs.info(output).and_then(|i| i.logical_size).unwrap_or((1920, 1080))
    }

    pub fn free(&mut self) {
        // the strips given back first, then the pads go; once sway has them gone, spark-shell lays the
        // windows out again (#273)
        let mut owed = !self.refit_for.is_empty() || self.refit_owed || self.refit_waiting > 0;
        for o in &mut self.outs {
            if let Some(k) = o.strip.take() {
                give_back(&k.layer);
                owed = true;
            }
            o.surf = None;
            o.keyer = None;
            o.deco = None;
        }
        if owed {
            let _ = self.conn.roundtrip();
            spawn(&self.cfg.spark_shell, &["desktop", "window", "refit"]);
        }
        for (_, p) in self.pictures.drain() {
            if let Some(p) = p {
                p.free(&self.lib);
            }
        }
        self.fonts.free(&self.lib);
    }
}

/// The resize pointer for a grip: the side or the corner it moves.
fn resize_cursor(s: Sides) -> Cursor {
    match (s.x, s.y) {
        (-1, -1) => Cursor::NwResize,
        (1, -1) => Cursor::NeResize,
        (-1, 1) => Cursor::SwResize,
        (1, 1) => Cursor::SeResize,
        (-1, _) => Cursor::WResize,
        (1, _) => Cursor::EResize,
        (_, -1) => Cursor::NResize,
        _ => Cursor::SResize,
    }
}

/// A strip about to go is given back first: no zone, committed, so sway lays the screen out again
/// before the destroy that follows. sway 1.7 (Debian 12) kept a destroyed layer surface's zone until
/// something else arranged the screen, and the windows never took the strip back.
fn give_back(layer: &LayerSurface) {
    layer.set_exclusive_zone(0);
    layer.commit();
}

/// A surface along an edge `thick` across: anchored to the edge and both ends of it, `margin` off the edge.
fn frame(edge: Edge, thick: i32, margin: i32) -> (Anchor, (u32, u32), (i32, i32, i32, i32)) {
    let t = thick.max(0) as u32;
    match edge {
        Edge::Bottom => (Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT, (0, t), (0, 0, margin, 0)),
        Edge::Top => (Anchor::TOP | Anchor::LEFT | Anchor::RIGHT, (0, t), (margin, 0, 0, 0)),
        Edge::Left => (Anchor::LEFT | Anchor::TOP | Anchor::BOTTOM, (t, 0), (0, 0, 0, margin)),
        Edge::Right => (Anchor::RIGHT | Anchor::TOP | Anchor::BOTTOM, (t, 0), (0, margin, 0, 0)),
    }
}

/// A spark-shell step run aside, never waited on by the pad: its own thread reaps it.
fn spawn(program: &str, args: &[&str]) {
    match std::process::Command::new(program).args(args).stdin(std::process::Stdio::null()).spawn() {
        Ok(mut child) => {
            std::thread::spawn(move || {
                let _ = child.wait();
            });
        }
        Err(e) => eprintln!("spark-winpad: {program}: {e}"),
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        for o in &mut self.outs {
            if o.surf.as_ref().is_some_and(|s| &s.layer == layer) {
                o.surf = None;
            }
            if o.strip.as_ref().is_some_and(|k| &k.layer == layer) {
                o.strip = None;
            }
            if o.keyer.as_ref() == Some(layer) {
                o.keyer = None;
            }
            if o.deco.as_ref().is_some_and(|d| &d.layer == layer) {
                o.deco = None;
            }
        }
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, configure: LayerSurfaceConfigure, _: u32) {
        if let Some(oi) = self.outs.iter().position(|o| o.keyer.as_ref() == Some(layer)) {
            self.draw_keyer(oi);
            return;
        }
        if let Some(d) = self.outs.iter_mut().find_map(|o| o.deco.as_mut().filter(|d| &d.layer == layer)) {
            d.size = (configure.new_size.0 as i32, configure.new_size.1 as i32);
            d.configured = true;
            self.deco_dirty = true;
            return;
        }
        if let Some(oi) = self.outs.iter().position(|o| o.strip.as_ref().is_some_and(|k| &k.layer == layer)) {
            self.draw_strip(oi);
            self.refit();
            return;
        }
        let Some(oi) = self.outs.iter().position(|o| o.surf.as_ref().is_some_and(|s| &s.layer == layer)) else {
            return;
        };
        let (w, h) = (configure.new_size.0 as i32, configure.new_size.1 as i32);
        let Some(shape) = self.outs[oi].surf.as_ref().unwrap().shape else { return };
        let size = match shape {
            Shape::Strip { edge, thick, .. } => {
                if edge.side() {
                    self.outs[oi].area.1 = h;
                    (if w > 0 { w } else { thick }, h)
                } else {
                    self.outs[oi].area.0 = w;
                    (w, if h > 0 { h } else { thick })
                }
            }
            Shape::Free { w: fw, h: fh, .. } => (if w > 0 { w } else { fw }, if h > 0 { h } else { fh }),
            Shape::Full { bar, .. } => {
                // the bar under the surface is not the windows' area
                let far = bar.map_or(0, |(_, far)| far);
                self.outs[oi].area = (w, h - far);
                (w, h)
            }
        };
        let s = self.outs[oi].surf.as_mut().unwrap();
        s.size = size;
        s.configured = true;
        // the whole area under a drag: the pad's corner there, where it stood
        if matches!(shape, Shape::Full { .. }) && self.drag.as_ref().is_some_and(|d| d.out == oi && d.pad.is_none()) {
            // the drag's points are the windows' area's, whatever the surface covers beside it
            let (w, h) = self.outs[oi].area;
            let was = self.drag.as_ref().map_or(Form::Row, |d| d.was);
            let lay = self.layout_on(oi, was);
            let at = match self.bar_on(oi).filter(|_| was == Form::Bar) {
                // from the bar: the bar's edge of the windows' area; the pad itself is shown on the bar while the drag
                // holds it
                Some(b) => (b.x, if b.edge == Edge::Bottom { (h - lay.h).max(0) } else { 0 }),
                None => pad::position(self.place_on(oi), lay.w, lay.h, w, h, &self.m),
            };
            let gap = self.m.gap;
            let d = self.drag.as_mut().unwrap();
            d.pad = Some(at);
            d.start = Rect::new(at.0, at.1, lay.w, lay.h);
            d.origin = match d.from {
                // a surface over the bar began the bar's height before the windows' area
                Some(Shape::Strip {
                    edge: Edge::Bottom,
                    thick,
                    over,
                }) if was == Form::Bar => (0, h + over - thick),
                Some(Shape::Strip { edge: Edge::Top, over, .. }) if was == Form::Bar => (0, -over),
                Some(Shape::Strip { edge: Edge::Bottom, thick, .. }) => (0, h - gap - thick),
                Some(Shape::Strip { edge: Edge::Top, .. }) => (0, gap),
                Some(Shape::Strip { edge: Edge::Left, .. }) => (gap, 0),
                Some(Shape::Strip { edge: Edge::Right, thick, .. }) => (w - gap - thick, 0),
                Some(Shape::Free { x, y, .. }) => (x, y),
                Some(Shape::Full { .. }) | None => (0, 0),
            };
        }
        self.dirty = true;
    }
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, factor: i32) {
        if let Some(oi) = self.out_of(surface).or_else(|| self.deco_of(surface)) {
            if self.outs[oi].scale != factor.max(1) {
                self.outs[oi].scale = factor.max(1);
                self.dirty = true;
                self.deco_dirty = true;
            }
        }
    }

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: Transform) {}

    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: u32) {}

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        let name = self.outputs.info(&output).and_then(|i| i.name).unwrap_or_default();
        let scale = self.scale_of(&output);
        let area = self.logical_of(&output);
        self.outs.push(Out {
            output,
            name,
            scale,
            area,
            surf: None,
            strip: None,
            keyer: None,
            deco: None,
        });
        self.apply();
    }

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        let scale = self.scale_of(&output);
        let name = self.outputs.info(&output).and_then(|i| i.name).unwrap_or_default();
        if let Some(o) = self.outs.iter_mut().find(|o| o.output == output) {
            o.scale = scale;
            o.name = name;
        }
        self.dirty = true;
    }

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        self.outs.retain(|o| o.output != output);
        // the indexes moved: what the pointer held is let go
        self.hover = None;
        self.press = None;
        self.drag = None;
        self.list = None;
        // the keys were on the screen that went: given back, and a pad shown only for them goes again
        if self.keys.as_ref().is_some_and(|k| !self.outs.iter().any(|o| o.name == k.out)) {
            self.keys_off();
        }
        self.refit();
    }
}

impl SeatHandler for App {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seats
    }

    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}

    fn new_capability(&mut self, _: &Connection, qh: &QueueHandle<Self>, seat: WlSeat, capability: Capability) {
        if capability == Capability::Pointer && self.pointer.is_none() {
            if let Ok(wl) = self.seats.get_pointer(qh, &seat) {
                let device = self.cursors.as_ref().map(|c| c.get_shape_device(&wl, qh));
                self.pointer = Some(Ptr {
                    _wl: wl,
                    device,
                    serial: 0,
                    out: None,
                    pos: (0.0, 0.0),
                    cursor: None,
                });
            }
        }
        if capability == Capability::Keyboard && self.keyboard.is_none() {
            self.keyboard = Some(seat.get_keyboard(qh, KeyData));
        }
    }

    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat, capability: Capability) {
        match capability {
            Capability::Pointer => self.pointer = None,
            Capability::Keyboard => {
                if let Some(k) = self.keyboard.take() {
                    k.release();
                }
            }
            _ => {}
        }
    }

    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlPointer, events: &[PointerEvent]) {
        for ev in events {
            if let Some(oi) = self.deco_of(&ev.surface) {
                self.deco_pointer(oi, &ev.kind, ev.position);
                continue;
            }
            let oi = self.out_of(&ev.surface);
            match ev.kind {
                PointerEventKind::Enter { serial } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.serial = serial;
                        p.out = oi;
                        p.pos = ev.position;
                        p.cursor = None;
                    }
                    self.motion(oi, ev.position);
                }
                PointerEventKind::Leave { .. } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.out = None;
                    }
                    if self.drag.is_none() && self.hover.is_some() {
                        self.hover = None;
                        self.tip_hover();
                        self.dirty = true;
                    }
                }
                PointerEventKind::Motion { .. } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.pos = ev.position;
                    }
                    self.motion(oi, ev.position);
                }
                PointerEventKind::Press { button: BTN_LEFT, .. } => self.press(oi, ev.position),
                PointerEventKind::Release { button: BTN_LEFT, .. } => self.release(oi, ev.position),
                _ => {}
            }
        }
    }
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

/// sway's answer to the sync sent behind a strip's commit: the area is laid out anew, and spark-shell lays
/// the placed windows out on it (desktop window refit).
struct Synced;

impl Dispatch2<WlCallback, App> for Synced {
    fn event(&self, app: &mut App, _: &WlCallback, event: wl_callback::Event, _: &Connection, _: &QueueHandle<App>) {
        if let wl_callback::Event::Done { .. } = event {
            app.refit_waiting = app.refit_waiting.saturating_sub(1);
            spawn(&app.cfg.spark_shell, &["desktop", "window", "refit"]);
        }
    }
}

/// The keyboard's events while the pad has the keys: evdev codes, read as positions.
struct KeyData;

impl Dispatch2<WlKeyboard, App> for KeyData {
    fn event(&self, app: &mut App, _: &WlKeyboard, event: wl_keyboard::Event, _: &Connection, _: &QueueHandle<App>) {
        match event {
            wl_keyboard::Event::Keymap { fd, size, .. } => app.kb.keymap(fd, size),
            wl_keyboard::Event::Modifiers {
                mods_depressed,
                mods_latched,
                mods_locked,
                group,
                ..
            } => app.kb.modifiers(mods_depressed, mods_latched, mods_locked, group),
            wl_keyboard::Event::Key {
                key,
                state: WEnum::Value(KeyState::Pressed),
                ..
            } => app.key(key),
            _ => {}
        }
    }
}

impl ProvidesRegistryState for App {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}

delegate_registry!(App);
delegate_dispatch2!(App);
/// Whether a process's command line (as /proc gives it, its words ended by NUL) is the bar's status loop:
/// `spark-shell bar status`, under whatever sh runs it.
pub fn is_status_loop(cmdline: &[u8]) -> bool {
    let words: Vec<&[u8]> = cmdline.split(|b| *b == 0).collect();
    words.windows(2).any(|w| w[0] == b"bar" && w[1] == b"status")
}

/// Whether the bar of a state file runs: its lock, beside the file, names a process that is the bar still. One that
/// crashed leaves both; with no lock there is nothing to tell by, and the file's word is taken.
fn bar_runs(state: &Path) -> bool {
    let Ok(pid) = std::fs::read_to_string(state.with_extension("pid")) else {
        return true;
    };
    std::fs::read(format!("/proc/{}/cmdline", pid.trim())).is_ok_and(|c| c.windows(9).any(|w| w == b"spark-bar"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_state_file_outlives_its_bar_and_is_no_bar_then() {
        use std::io::Read;
        use std::process::{Command, Stdio};
        let state = std::env::temp_dir().join(format!("spark-winpad-bar.{}.state", std::process::id()));
        let lock = state.with_extension("pid");
        let names = |pid: &str| {
            std::fs::write(&lock, format!("{pid}\n")).unwrap();
            bar_runs(&state)
        };
        assert!(bar_runs(&state), "no lock beside it: the file's word is taken");
        // no process has the pid, it is another program's by now, or none is written
        assert!(!names(&i32::MAX.to_string()) && !names(&std::process::id().to_string()) && !names(""));
        // a process that is the bar, and the same once it has ended
        let mut run = Command::new("sh");
        run.args(["-c", "echo; read x", "spark-bar"]).stdin(Stdio::piped()).stdout(Stdio::piped());
        let mut bar = run.spawn().unwrap();
        let pid = bar.id().to_string();
        // it has spoken: the kernel has its words, which it has not the moment the spawn returns
        bar.stdout.as_mut().unwrap().read_exact(&mut [0]).unwrap();
        let ran = names(&pid);
        drop(bar.stdin.take());
        bar.wait().unwrap();
        let runs = names(&pid);
        std::fs::remove_file(&lock).unwrap();
        assert_eq!((ran, runs), (true, false));
    }

    #[test]
    fn only_the_status_loop_is_signalled() {
        assert!(is_status_loop(b"sh\0/home/ada/.spark-shell/spark-shell\0bar\0status\0"));
        assert!(is_status_loop(b"/bin/bash\0/opt/spark-shell/spark-shell\0bar\0status\0"));
        // the pid the file names is another program's by now: a terminal, a browser, the bar's own start
        assert!(!is_status_loop(b"foot\0--app-id\0spark-shell\0"));
        assert!(!is_status_loop(b"sh\0/home/ada/.spark-shell/spark-shell\0bar\0start\0"));
        assert!(!is_status_loop(b"vim\0bar status\0"));
        assert!(!is_status_loop(b""));
    }
}
