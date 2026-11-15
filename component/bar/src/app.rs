//! The bar on the screens: a surface on the wlr layer shell's bottom layer on each output, where swaybar
//! docks, drawn with cairo and pango. It draws the frame the pure half says and hands the pointer and
//! the keys back to it: no value, no place and no tone is decided here. One thing moves by itself: a
//! level's number flows to its new digits. While one does, the bar draws on the surface's frame
//! callbacks; at rest it asks for none and does not wake. While a bar has the keys, a transparent surface
//! over the rest of each output takes the pointer there: what it does off the bar gives the keys back.

use crate::bar::{self, Act, Astray, Draw, Edge, KeyAct, Layout, Levels, Metrics, Module, Off, Prefs, Press, Scene, Shown, Status, Tone, View, Workspace};
use crate::keys::Keyboard;
use crate::paint::{Canvas, Font, Lib, Picture, Rgb, Ruler};
use crate::status::{Feed, Said};
use crate::sway::Ipc;
use calloop::channel::Sender;
use calloop::timer::{TimeoutAction, Timer};
use calloop::LoopHandle;
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, FrameCallbackData, Region};
use smithay_client_toolkit::dispatch2::Dispatch2;
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape as Cursor, WpCursorShapeDeviceV1};
use smithay_client_toolkit::reexports::protocols::wp::viewporter::client::wp_viewport::{self, WpViewport};
use smithay_client_toolkit::reexports::protocols::wp::viewporter::client::wp_viewporter::{self, WpViewporter};
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
use std::path::PathBuf;
use std::time::{Duration, Instant};
use wayland_client::globals::GlobalList;
use wayland_client::protocol::wl_keyboard::{self, KeyState, WlKeyboard};
use wayland_client::protocol::wl_output::{Transform, WlOutput};
use wayland_client::protocol::wl_pointer::WlPointer;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::protocol::wl_shm;
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, QueueHandle, WEnum};

/// The layer shell namespace: what sway's rules and tools call the surface.
const NAMESPACE: &str = "spark-bar";
const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;
/// The pixels of scroll that make one wheel step: a notch of a wheel.
const WHEEL_STEP: f64 = 15.0;

/// The look, as spark-shell hands it over: in the environment at the start, then in each status line.
/// The palette's slots, the ground's alpha, the glyph family's gauge pair and whether the digits flow.
#[derive(Clone, PartialEq)]
pub struct Look {
    pub fg: Rgb,
    pub accent: Rgb,
    /// The dim tone.
    pub muted: Rgb,
    pub ground: Rgb,
    pub lit: Rgb,
    pub attention: Rgb,
    /// Red.
    pub alert: Rgb,
    pub alpha: f64,
    pub full: String,
    pub light: String,
    pub motion: bool,
}

impl Look {
    /// This look with the slots a status line says over it: what the line leaves out or gets wrong stays.
    fn with(&self, said: &bar::Look) -> Look {
        let color = |said: Option<bar::Color>, own: Rgb| said.map_or(own, Rgb::of);
        Look {
            fg: color(said.fg, self.fg),
            accent: color(said.accent, self.accent),
            muted: color(said.muted, self.muted),
            ground: color(said.ground, self.ground),
            lit: color(said.lit, self.lit),
            attention: color(said.attention, self.attention),
            alert: color(said.alert, self.alert),
            alpha: said.alpha.unwrap_or(self.alpha),
            full: said.full.clone().unwrap_or_else(|| self.full.clone()),
            light: said.light.clone().unwrap_or_else(|| self.light.clone()),
            motion: said.motion.unwrap_or(self.motion),
        }
    }

    /// The color a tone is drawn in.
    fn color(&self, tone: Tone) -> Rgb {
        match tone {
            Tone::Text => self.fg,
            Tone::Dim => self.muted,
            Tone::Alert => self.alert,
            Tone::Attention => self.attention,
            Tone::Accent => self.accent,
            Tone::Ground => self.ground,
            Tone::Lit => self.lit,
            Tone::Raised => self.muted.toward(self.fg, bar::RAISE),
        }
    }

    /// Whether its ground is dark: which of spark's marks stands on it.
    fn dark(&self) -> bool {
        let byte = |v: f64| (v * 255.0).round().clamp(0.0, 255.0) as u8;
        let g = self.ground;
        bar::dark_ground(byte(g.0), byte(g.1), byte(g.2))
    }
}

/// What spark-shell says, read once at the start. Its look is the environment's: the bar's until a
/// status line says its own, and after it for every slot a line does not say.
pub struct Config {
    pub look: Look,
    /// BAR_FONT: a pango font.
    pub font: String,
    pub edge: Edge,
    pub prefs: Prefs,
    pub spark_shell: String,
    pub state_file: PathBuf,
}

/// The surface over an output, all but its bar, while a bar has the keys: transparent, on the top layer,
/// with no keyboard. One pixel, stretched over the output by its viewport.
struct Catcher {
    layer: LayerSurface,
    viewport: WpViewport,
    /// It was handed its size and is on the screen.
    shown: bool,
}

impl Drop for Catcher {
    fn drop(&mut self) {
        self.viewport.destroy();
    }
}

/// An output and its bar.
struct Out {
    output: WlOutput,
    name: String,
    scale: i32,
    layer: Option<LayerSurface>,
    /// The surface that holds the keyboard while this bar has the keys.
    keyer: Option<LayerSurface>,
    /// The surface that takes the pointer off the bar while a bar has the keys.
    catcher: Option<Catcher>,
    /// The bar's width as the compositor last told it; 0 before.
    width: i32,
    /// What the screen shows, for the pointer and the keys.
    layout: Layout,
    /// The target the keys are on, by its id: it stays through a new line.
    focus: Option<String>,
    hover: Option<usize>,
    /// A frame callback was asked of the bar's surface and has not come: the next frame of a number's flow.
    waiting: bool,
}

struct Ptr {
    _wl: WlPointer,
    device: Option<WpCursorShapeDeviceV1>,
    out: Option<usize>,
    pos: (f64, f64),
    /// The scroll not yet a whole wheel step.
    wheel: f64,
}

pub struct App {
    registry: RegistryState,
    outputs: OutputState,
    compositor: CompositorState,
    layer_shell: LayerShell,
    seats: SeatState,
    shm: Shm,
    pool: SlotPool,
    cursors: Option<CursorShapeManager>,
    /// The compositor's viewporter; without one there is no catcher, and Escape alone gives the keys back.
    viewporter: Option<WpViewporter>,
    qh: QueueHandle<App>,
    handle: LoopHandle<'static, App>,
    lib: Lib,
    font: Font,
    ruler: Ruler,
    m: Metrics,
    cfg: Config,
    /// The look in use: the environment's with the last line's over it.
    look: Look,
    ipc: Ipc,
    outs: Vec<Out>,
    /// The status as spark-shell last said it, and every output's workspaces as sway last listed them.
    status: Status,
    modules: Vec<Module>,
    /// The levels as they are drawn: the line's, or the hand's since.
    levels: Levels,
    /// When the bar started: the time the numbers flow by is counted from it.
    started: Instant,
    workspaces: Vec<Workspace>,
    /// sway's binding mode; none in the default one.
    mode: Option<String>,
    /// The status child, the count of children started, and how many ended in a row.
    feed: Option<Feed>,
    tx: Sender<Said>,
    gen: u64,
    failures: u32,
    /// The output whose bar has the keyboard.
    keys: Option<String>,
    /// The pointer off the bar since then.
    astray: Astray,
    pointer: Option<Ptr>,
    keyboard: Option<WlKeyboard>,
    /// The keymap the compositor sent, read with libxkbcommon.
    kb: Keyboard,
    /// Spark's mark at each scale in use; None where the assets have none.
    marks: HashMap<i32, Option<Picture>>,
    /// The state file as last written.
    written: String,
    pub dirty: bool,
    pub stop: bool,
    /// Why the bar ends when sway is gone: it ends with an error, and its keeper starts it again.
    pub failed: Option<String>,
}

impl App {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        globals: &GlobalList,
        qh: &QueueHandle<App>,
        handle: LoopHandle<'static, App>,
        lib: Lib,
        cfg: Config,
        ipc: Ipc,
        tx: Sender<Said>,
    ) -> Result<App, String> {
        let compositor = CompositorState::bind(globals, qh).map_err(|e| format!("the compositor has no wl_compositor: {e}"))?;
        let layer_shell = LayerShell::bind(globals, qh).map_err(|_| "the compositor has no layer shell (zwlr_layer_shell_v1)".to_string())?;
        let shm = Shm::bind(globals, qh).map_err(|e| format!("the compositor has no wl_shm: {e}"))?;
        let pool = SlotPool::new(1 << 20, &shm).map_err(|e| format!("shared memory: {e}"))?;
        let font = Font::new(&lib, &cfg.font);
        let ruler = Ruler::new(&lib);
        // one cell: the width of "0" in the bar's font
        let m = Metrics::for_text(font.px, ruler.width(&lib, &font, "0"));
        Ok(App {
            registry: RegistryState::new(globals),
            outputs: OutputState::new(globals, qh),
            seats: SeatState::new(globals, qh),
            cursors: CursorShapeManager::bind(globals, qh).ok(),
            viewporter: globals.bind(qh, 1..=1, Viewed).ok(),
            compositor,
            layer_shell,
            shm,
            pool,
            qh: qh.clone(),
            handle,
            lib,
            font,
            ruler,
            m,
            look: cfg.look.clone(),
            cfg,
            ipc,
            outs: vec![],
            status: Status::Loading,
            modules: vec![],
            levels: Levels::default(),
            started: Instant::now(),
            workspaces: vec![],
            mode: None,
            feed: None,
            tx,
            gen: 0,
            failures: 0,
            keys: None,
            astray: Astray::default(),
            pointer: None,
            keyboard: None,
            kb: Keyboard::new(),
            marks: HashMap::new(),
            written: String::new(),
            dirty: true,
            stop: false,
            failed: None,
        })
    }

    /// `spark-shell bar status` started; when it cannot be, the status is broken and it is tried again later.
    pub fn start_status(&mut self) {
        self.gen += 1;
        match Feed::start(&self.cfg.spark_shell, self.gen, self.tx.clone()) {
            Ok(feed) => self.feed = Some(feed),
            Err(e) => {
                eprintln!("spark-bar: {}: {e}", self.cfg.spark_shell);
                self.status_broke();
            }
        }
    }

    /// The time, in milliseconds since the bar started.
    fn now(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }

    /// What the status child said: a line replaces the last one; its end breaks the status. Only the
    /// running child is heard: one that ended may say its end twice (its exit and its stream's), and a
    /// line of its may still come after. A line's levels are the truth: one the hand set since is drawn
    /// as the line says, though the line itself is the same as the last.
    pub fn said(&mut self, said: Said) {
        let Some(lived) = self.feed.as_ref().map(Feed::lived) else { return };
        match said {
            Said::Line(gen, line) if gen == self.gen => {
                let Some((modules, look)) = bar::parse_refresh(&line) else { return };
                if bar::steady(lived.as_secs()) {
                    self.failures = 0;
                }
                self.set_look(self.cfg.look.with(&look));
                let moved = self.levels.said(&modules, self.now());
                if self.status != Status::Ok || modules != self.modules || moved {
                    self.status = Status::Ok;
                    self.modules = modules;
                    self.relayout();
                }
            }
            Said::End(gen) if gen == self.gen => self.status_broke(),
            _ => {}
        }
    }

    /// A new look: every bar is drawn again in it. The mark is the dark ground's or the light one's, so
    /// a ground that changed sides takes the other, loaded at the next draw.
    fn set_look(&mut self, look: Look) {
        if look == self.look {
            return;
        }
        if look.dark() != self.look.dark() {
            self.drop_marks();
        }
        self.look = look;
        self.dirty = true;
    }

    fn drop_marks(&mut self) {
        for (_, p) in self.marks.drain() {
            if let Some(p) = p {
                p.free(&self.lib);
            }
        }
    }

    /// The status child ended or never started: its group is told to end, the frame stays, a warning
    /// stands for the status, and the child is started again after 1 s, then 2, 4, up to 30.
    fn status_broke(&mut self) {
        if let Some(feed) = self.feed.take() {
            feed.end();
        }
        self.status = Status::Error;
        self.failures += 1;
        self.relayout();
        let wait = Duration::from_secs(bar::backoff(self.failures));
        let _ = self.handle.insert_source(Timer::from_duration(wait), |_, _, app: &mut App| {
            if app.feed.is_none() && !app.stop {
                app.start_status();
            }
            TimeoutAction::Drop
        });
    }

    /// sway's workspaces read again: at the start and after each workspace or output event.
    pub fn read_workspaces(&mut self) {
        let Ok(v) = self.ipc.workspaces() else {
            self.failed = Some("sway did not answer".into());
            self.stop = true;
            return;
        };
        let workspaces = bar::workspaces(&v);
        if workspaces != self.workspaces {
            self.workspaces = workspaces;
            self.relayout();
        }
    }

    /// sway's binding mode read again: at the start and after each mode event.
    pub fn read_mode(&mut self) {
        let Ok(v) = self.ipc.binding_state() else {
            self.failed = Some("sway did not answer".into());
            self.stop = true;
            return;
        };
        let mode = bar::mode(&v);
        if mode != self.mode {
            self.mode = mode;
            self.relayout();
        }
    }

    /// Every bar laid out again by the pure half, and the state file with them.
    fn relayout(&mut self) {
        for (oi, o) in self.outs.iter_mut().enumerate() {
            if o.width <= 0 {
                continue;
            }
            let scene = Scene {
                output: &o.name,
                width: o.width,
                edge: self.cfg.edge,
                status: self.status,
                modules: &self.modules,
                levels: &self.levels,
                workspaces: &self.workspaces,
                mode: self.mode.as_deref(),
            };
            o.layout = bar::layout(&scene, &self.cfg.prefs, &self.m);
            // the pointer stays where it is: what is under it now
            o.hover = self.pointer.as_ref().filter(|p| p.out == Some(oi)).and_then(|p| o.layout.hit(p.pos.0, p.pos.1));
            // the keys stay on their target; when it is gone, on the first
            if self.keys.as_deref() == Some(o.name.as_str()) && o.focus.as_deref().and_then(|id| o.layout.find(id)).is_none() {
                o.focus = o.layout.targets.first().map(|t| t.id.clone());
            }
        }
        self.dirty = true;
        self.write_state();
    }

    /// The target the keys are on, on an output's bar.
    fn focus_on(&self, oi: usize) -> Option<usize> {
        let o = &self.outs[oi];
        if self.keys.as_deref() != Some(o.name.as_str()) {
            return None;
        }
        o.focus.as_deref().and_then(|id| o.layout.find(id))
    }

    /// The state file, written whole beside itself and moved into place; once a change.
    fn write_state(&mut self) {
        let bars: Vec<Shown> = (0..self.outs.len())
            .filter(|&oi| self.outs[oi].width > 0)
            .map(|oi| Shown {
                output: &self.outs[oi].name,
                scale: self.outs[oi].scale,
                layout: &self.outs[oi].layout,
                focus: self.focus_on(oi),
                hover: self.outs[oi].hover,
            })
            .collect();
        let text = bar::state_text(self.status, self.mode.as_deref(), &self.levels, &bars);
        if text == self.written {
            return;
        }
        let tmp = self.cfg.state_file.with_extension("new");
        if std::fs::write(&tmp, &text).is_ok() && std::fs::rename(&tmp, &self.cfg.state_file).is_ok() {
            self.written = text;
        }
    }

    /// An output's bar: on the bottom layer as swaybar's, along the edge from side to side, the windows
    /// kept off its height.
    fn add_bar(&mut self, oi: usize) {
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self
            .layer_shell
            .create_layer_surface(&self.qh, surface, Layer::Bottom, Some(NAMESPACE), Some(&self.outs[oi].output));
        let edge = match self.cfg.edge {
            Edge::Top => Anchor::TOP,
            Edge::Bottom => Anchor::BOTTOM,
        };
        layer.set_anchor(edge | Anchor::LEFT | Anchor::RIGHT);
        layer.set_size(0, self.m.height as u32);
        layer.set_exclusive_zone(self.m.height);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();
        self.outs[oi].layer = Some(layer);
    }

    /// While a bar has the keys, its output holds a surface of one transparent pixel on the top layer
    /// that takes the keyboard: sway gives the keyboard only to the top layers, and the bar stays on the
    /// bottom one. It takes no pointer and shows nothing. It comes once every catcher is on the screen:
    /// sway hands the pointer to a surface that just came only when the pointer next moves, or when
    /// another layer comes after it, and so a button with no move before it reaches the catcher too.
    fn apply_keyers(&mut self) {
        if self.keys.is_some() && self.outs.iter().any(|o| o.catcher.as_ref().is_some_and(|c| !c.shown)) {
            return;
        }
        for oi in 0..self.outs.len() {
            let want = self.keys.as_deref() == Some(self.outs[oi].name.as_str());
            if !want {
                self.outs[oi].keyer = None;
                continue;
            }
            if self.outs[oi].keyer.is_some() {
                continue;
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

    /// While a bar has the keys, every output holds a catcher: a button on it, or the pointer's travel over
    /// it, gives the keys back as Escape does. It takes no pointer until its size is known.
    fn apply_catchers(&mut self) {
        let Some(viewporter) = self.viewporter.clone() else { return };
        for oi in 0..self.outs.len() {
            if self.keys.is_none() {
                self.outs[oi].catcher = None;
                continue;
            }
            if self.outs[oi].catcher.is_some() {
                continue;
            }
            let surface = self.compositor.create_surface(&self.qh);
            let viewport = viewporter.get_viewport(&surface, &self.qh, Viewed);
            let layer = self
                .layer_shell
                .create_layer_surface(&self.qh, surface, Layer::Top, Some(NAMESPACE), Some(&self.outs[oi].output));
            layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
            layer.set_size(0, 0);
            layer.set_exclusive_zone(-1);
            layer.set_keyboard_interactivity(KeyboardInteractivity::None);
            if let Ok(region) = Region::new(&self.compositor) {
                layer.wl_surface().set_input_region(Some(region.wl_region()));
            }
            layer.commit();
            self.outs[oi].catcher = Some(Catcher { layer, viewport, shown: false });
        }
    }

    /// A catcher handed its size, the output's: shown, and the keyboard taken once every one is. One that
    /// cannot be shown is none, and the keys do not wait for it.
    fn draw_catcher(&mut self, oi: usize, (w, h): (u32, u32)) {
        if !self.show_catcher(oi, w as i32, h as i32) {
            self.outs[oi].catcher = None;
        }
        self.apply_keyers();
    }

    /// A catcher on the screen at a size: it takes the pointer everywhere but on the bar, so a click on the
    /// bar still reaches the bar. False when it could not be shown.
    fn show_catcher(&mut self, oi: usize, w: i32, h: i32) -> bool {
        let Some(c) = self.outs[oi].catcher.as_mut() else { return true };
        if w <= 0 || h <= 0 {
            return false;
        }
        let Ok((buffer, data)) = self.pool.create_buffer(1, 1, 4, wl_shm::Format::Argb8888) else {
            return false;
        };
        data[..4].fill(0);
        let surface = c.layer.wl_surface();
        c.viewport.set_destination(w, h);
        if let Ok(region) = Region::new(&self.compositor) {
            let bar = match self.cfg.edge {
                Edge::Top => 0,
                Edge::Bottom => h - self.m.height,
            };
            region.add(0, 0, w, h);
            region.subtract(0, bar, w, self.m.height);
            surface.set_input_region(Some(region.wl_region()));
        }
        if buffer.attach_to(surface).is_err() {
            return false;
        }
        surface.damage_buffer(0, 0, 1, 1);
        c.layer.commit();
        c.shown = true;
        true
    }

    /// The pointer on a catcher: off the bar while a bar has the keys.
    fn off_bar(&mut self, ev: &PointerEvent) {
        let (x, y) = ev.position;
        let what = match ev.kind {
            PointerEventKind::Enter { serial } => {
                if let Some(d) = self.pointer.as_ref().and_then(|p| p.device.as_ref()) {
                    d.set_shape(serial, Cursor::Default);
                }
                Off::Came(x, y)
            }
            PointerEventKind::Motion { .. } => Off::Moved(x, y),
            // the wheel too: a scroll this surface spent would look like a frozen window
            PointerEventKind::Press { .. } | PointerEventKind::Axis { .. } => Off::Pressed,
            PointerEventKind::Leave { .. } => Off::Left,
            _ => return,
        };
        if self.astray.back(what, self.m.cell) {
            self.keys_off();
        }
    }

    /// SIGUSR1: the keyboard on the bar of the output sway has the focus on, the first target picked.
    pub fn keys_on(&mut self) {
        let Some(name) = self
            .ipc
            .focused_output()
            .filter(|n| self.outs.iter().any(|o| o.name == *n))
            .or_else(|| self.outs.first().map(|o| o.name.clone()))
        else {
            return;
        };
        for o in &mut self.outs {
            o.focus = (o.name == name).then(|| o.layout.targets.first().map(|t| t.id.clone())).flatten();
        }
        self.keys = Some(name);
        self.astray = Astray::default();
        self.apply_catchers();
        self.apply_keyers();
        self.dirty = true;
        self.write_state();
    }

    /// Escape, a button or the pointer's travel off the bar, or the keyboard taken away: the keys go back
    /// and no target is picked.
    fn keys_off(&mut self) {
        if self.keys.take().is_none() {
            return;
        }
        for o in &mut self.outs {
            o.focus = None;
        }
        self.apply_keyers();
        self.apply_catchers();
        self.dirty = true;
        self.write_state();
    }

    /// What a click or a key asked for: a click for spark-shell, or a command for sway; and the level it
    /// changes, drawn at once.
    fn act(&mut self, press: Press) {
        match press.act {
            Act::Send(click) => {
                if let Some(feed) = self.feed.as_mut() {
                    feed.click(&click);
                }
            }
            Act::Sway(command) => {
                if self.ipc.run(&command).is_err() {
                    self.failed = Some("sway did not answer".into());
                    self.stop = true;
                }
            }
            Act::Nothing => {}
        }
        if let Some((module, level)) = press.set {
            if self.levels.set(&module, level, self.now()) {
                self.relayout();
            }
        }
    }

    fn key(&mut self, code: u32) {
        let Some(oi) = self.keys.as_ref().and_then(|k| self.outs.iter().position(|o| o.name == *k)) else {
            return;
        };
        let Some(k) = self.kb.key(code) else { return };
        match self.outs[oi].layout.key(self.focus_on(oi).unwrap_or(0), k, &self.levels) {
            KeyAct::Focus(i) => {
                let o = &mut self.outs[oi];
                o.focus = o.layout.targets.get(i).map(|t| t.id.clone());
                self.dirty = true;
                self.write_state();
            }
            KeyAct::Do { press, leave } => {
                self.act(press);
                if leave {
                    self.keys_off();
                }
            }
            KeyAct::Leave => self.keys_off(),
            KeyAct::Nothing => {}
        }
    }

    /// The pointer at a point of an output's bar, or off every bar: the target under it is lit.
    fn hover(&mut self, at: Option<(usize, (f64, f64))>) {
        let mut changed = false;
        for (oi, o) in self.outs.iter_mut().enumerate() {
            let now = at.filter(|(on, _)| *on == oi).and_then(|(_, pos)| o.layout.hit(pos.0, pos.1));
            changed |= now != o.hover;
            o.hover = now;
        }
        if changed {
            self.dirty = true;
            self.write_state();
        }
    }

    /// A button (1 left, 2 middle, 3 right, 4 wheel up, 5 wheel down) on an output's bar.
    fn press(&mut self, oi: usize, pos: (f64, f64), button: u32) {
        let press = self.outs[oi].layout.press(pos.0, pos.1, button, &self.levels);
        self.act(press);
    }

    /// Spark's mark at a scale, loaded once: the mark's side in that scale's pixels.
    fn load_mark(&mut self, scale: i32) {
        if self.marks.contains_key(&scale) {
            return;
        }
        let picture = crate::mark::file(&self.cfg.spark_shell, self.look.dark(), self.m.mark * scale).and_then(|path| Picture::png(&self.lib, &path));
        self.marks.insert(scale, picture);
    }

    /// Every configured bar drawn again.
    pub fn draw_all(&mut self) {
        self.dirty = false;
        for oi in 0..self.outs.len() {
            self.draw(oi);
        }
    }

    /// One bar drawn: the frame the pure half says for now, each thing in its tone's color. While a number
    /// on this bar is on its way the next frame is asked of the surface, once; a bar at rest asks for none,
    /// and neither does one whose change shows no number.
    fn draw(&mut self, oi: usize) {
        if self.outs[oi].layer.is_none() || self.outs[oi].width <= 0 {
            return;
        }
        let scale = self.outs[oi].scale.max(1);
        self.load_mark(scale);
        let focus = self.focus_on(oi);
        let now = self.now();
        let o = &self.outs[oi];
        let (lay, look) = (&o.layout, &self.look);
        let (w, h) = (o.width, self.m.height);
        let (bw, bh) = (w * scale, h * scale);
        let Ok((buffer, data)) = self.pool.create_buffer(bw, bh, bw * 4, wl_shm::Format::Argb8888) else {
            eprintln!("spark-bar: no shared memory for a frame");
            return;
        };
        let view = View {
            hover: o.hover,
            focus,
            full: &look.full,
            light: &look.light,
            levels: &self.levels,
            motion: look.motion,
            at: now,
        };
        {
            let Some(c) = Canvas::new(&self.lib, &self.font, data, bw, bh, bw * 4, scale as f64) else {
                return;
            };
            c.fill(0.0, 0.0, w as f64, h as f64, look.ground, look.alpha);
            for draw in lay.frame(&view) {
                match draw {
                    Draw::Fill { rect: r, tone } => c.fill(r.x as f64, r.y as f64, r.w as f64, r.h as f64, look.color(tone), 1.0),
                    Draw::Mark { rect: r } => {
                        if let Some(p) = self.marks.get(&scale).and_then(Option::as_ref) {
                            c.picture(p, r.x as f64, r.y as f64, r.w as f64);
                        }
                    }
                    Draw::Glyph {
                        rect: r,
                        text,
                        tone,
                        bold,
                        fit,
                        shift,
                    } => c.glyph(r.x as f64, r.y as f64, r.w as f64, r.h as f64, &text, look.color(tone), bold, fit, shift),
                }
            }
        }
        // the next frame, only while a number on this bar is on its way
        let ask = lay.moving(&view) && !o.waiting;
        let Some(layer) = o.layer.as_ref() else { return };
        let surface = layer.wl_surface();
        surface.set_buffer_scale(scale);
        if buffer.attach_to(surface).is_ok() {
            surface.damage_buffer(0, 0, bw, bh);
            if ask {
                surface.frame(&self.qh, FrameCallbackData(surface.clone()));
            }
            layer.commit();
            self.outs[oi].waiting |= ask;
        }
    }

    fn out_of(&self, surface: &WlSurface) -> Option<usize> {
        self.outs.iter().position(|o| o.layer.as_ref().is_some_and(|l| l.wl_surface() == surface))
    }

    /// Whether a surface is a catcher.
    fn catches(&self, surface: &WlSurface) -> bool {
        self.outs.iter().any(|o| o.catcher.as_ref().is_some_and(|c| c.layer.wl_surface() == surface))
    }

    fn scale_of(&self, output: &WlOutput) -> i32 {
        self.outputs.info(output).map_or(1, |i| i.scale_factor.max(1))
    }

    /// The bar ends: the status child's group told to, the surfaces and what cairo and pango hold given back.
    pub fn free(&mut self) {
        if let Some(feed) = self.feed.take() {
            feed.end();
        }
        for o in &mut self.outs {
            o.layer = None;
            o.keyer = None;
            o.catcher = None;
        }
        self.drop_marks();
        self.ruler.free(&self.lib);
        self.font.free(&self.lib);
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        for o in &mut self.outs {
            if o.layer.as_ref() == Some(layer) {
                o.layer = None;
                o.width = 0;
                o.waiting = false;
            }
            if o.keyer.as_ref() == Some(layer) {
                o.keyer = None;
            }
            if o.catcher.as_ref().is_some_and(|c| c.layer == *layer) {
                o.catcher = None;
            }
        }
        self.apply_keyers();
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, configure: LayerSurfaceConfigure, _: u32) {
        if let Some(oi) = self.outs.iter().position(|o| o.keyer.as_ref() == Some(layer)) {
            self.draw_keyer(oi);
            return;
        }
        if let Some(oi) = self.outs.iter().position(|o| o.catcher.as_ref().is_some_and(|c| c.layer == *layer)) {
            self.draw_catcher(oi, configure.new_size);
            return;
        }
        let Some(o) = self.outs.iter_mut().find(|o| o.layer.as_ref() == Some(layer)) else {
            return;
        };
        o.width = configure.new_size.0 as i32;
        self.relayout();
    }
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, factor: i32) {
        if let Some(oi) = self.out_of(surface) {
            if self.outs[oi].scale != factor.max(1) {
                self.outs[oi].scale = factor.max(1);
                self.dirty = true;
                self.write_state();
            }
        }
    }

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: Transform) {}

    /// The frame a draw asked for while a number was on its way: that bar drawn again, as far as the
    /// number is now; the draw asks for the next one until the number rests.
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, _: u32) {
        if let Some(oi) = self.out_of(surface) {
            self.outs[oi].waiting = false;
            self.draw(oi);
        }
    }

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
        self.outs.push(Out {
            output,
            name,
            scale,
            layer: None,
            keyer: None,
            catcher: None,
            width: 0,
            layout: Layout::default(),
            focus: None,
            hover: None,
            waiting: false,
        });
        self.add_bar(self.outs.len() - 1);
        self.apply_catchers();
    }

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        let scale = self.scale_of(&output);
        let name = self.outputs.info(&output).and_then(|i| i.name).unwrap_or_default();
        if let Some(o) = self.outs.iter_mut().find(|o| o.output == output) {
            o.scale = scale;
            o.name = name;
        }
        self.relayout();
    }

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        self.outs.retain(|o| o.output != output);
        // the indexes moved: the pointer is on no bar until it moves again
        if let Some(p) = self.pointer.as_mut() {
            p.out = None;
        }
        if self.keys.as_ref().is_some_and(|k| !self.outs.iter().any(|o| o.name == *k)) {
            self.keys_off();
        }
        self.apply_keyers();
        self.relayout();
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
                    out: None,
                    pos: (0.0, 0.0),
                    wheel: 0.0,
                });
            }
        }
        if capability == Capability::Keyboard && self.keyboard.is_none() {
            self.keyboard = Some(seat.get_keyboard(qh, KeyData));
        }
    }

    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat, capability: Capability) {
        match capability {
            Capability::Pointer => {
                self.pointer = None;
                self.hover(None);
            }
            Capability::Keyboard => {
                if let Some(k) = self.keyboard.take() {
                    k.release();
                }
                self.keys_off();
            }
            _ => {}
        }
    }

    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlPointer, events: &[PointerEvent]) {
        for ev in events {
            if self.catches(&ev.surface) {
                self.off_bar(ev);
                continue;
            }
            let Some(oi) = self.out_of(&ev.surface) else { continue };
            match ev.kind {
                PointerEventKind::Enter { serial } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.out = Some(oi);
                        p.pos = ev.position;
                        p.wheel = 0.0;
                        if let Some(d) = &p.device {
                            d.set_shape(serial, Cursor::Default);
                        }
                    }
                    self.hover(Some((oi, ev.position)));
                }
                PointerEventKind::Leave { .. } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.out = None;
                    }
                    self.hover(None);
                }
                PointerEventKind::Motion { .. } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.out = Some(oi);
                        p.pos = ev.position;
                    }
                    self.hover(Some((oi, ev.position)));
                }
                PointerEventKind::Press { button, .. } => {
                    let button = match button {
                        BTN_LEFT => 1,
                        BTN_MIDDLE => 2,
                        BTN_RIGHT => 3,
                        _ => continue,
                    };
                    self.press(oi, ev.position, button);
                }
                PointerEventKind::Axis { vertical, .. } => {
                    // a wheel step each 15 px of scroll: up is 4, down is 5
                    let Some(p) = self.pointer.as_mut() else { continue };
                    p.wheel += vertical.absolute;
                    let steps = (p.wheel / WHEEL_STEP).trunc();
                    p.wheel -= steps * WHEEL_STEP;
                    for _ in 0..(steps.abs() as u32).min(8) {
                        self.press(oi, ev.position, if steps < 0.0 { 4 } else { 5 });
                    }
                }
                PointerEventKind::Release { .. } => {}
            }
        }
    }
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

/// The viewporter and a catcher's viewport: neither says anything.
struct Viewed;

impl Dispatch2<WpViewporter, App> for Viewed {
    fn event(&self, _: &mut App, _: &WpViewporter, _: wp_viewporter::Event, _: &Connection, _: &QueueHandle<App>) {}
}

impl Dispatch2<WpViewport, App> for Viewed {
    fn event(&self, _: &mut App, _: &WpViewport, _: wp_viewport::Event, _: &Connection, _: &QueueHandle<App>) {}
}

/// The keyboard's events while a bar has the keys: evdev codes, read as the layout names them.
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
            // a leave is not the end of the keys, as on the pad: sway leaves and enters the same surface again
            // when a keyboard is configured (one plugged in, a layout changed), and Escape gives them back
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
