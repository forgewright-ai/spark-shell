//! The notifications on the screen: one layer surface in the corner by the bar, on the screen with the
//! keyboard. It draws the frames the stack says (`super`), hands it the pointer and the keys, and speaks
//! with the server over its own stdin and stdout, a JSON line each way: the server says the look, what to
//! show and what to close; this says what the person did. It ends when the server's side of the pipe does.

use super::{Draw, Event, Key, Metrics, Note, Stack, Tone};
use crate::keys::Keyboard;
use crate::paint::{Canvas, Font, Lib, Rgb, Ruler};
use calloop::timer::{TimeoutAction, Timer};
use calloop::{LoopHandle, RegistrationToken};
use serde_json::Value;
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, FrameCallbackData, Region};
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
use std::io::Write;
use std::time::{Duration, Instant};
use wayland_client::globals::GlobalList;
use wayland_client::protocol::wl_keyboard::{self, KeyState, WlKeyboard};
use wayland_client::protocol::wl_output::{Transform, WlOutput};
use wayland_client::protocol::wl_pointer::WlPointer;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::protocol::wl_shm;
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, QueueHandle, WEnum};

const NAMESPACE: &str = "spark-notifications";
/// The room between the stack and the screen's edges: with sway's gaps, the windows' own edge.
const MARGIN: i32 = 12;
/// What a bar takes of a screen's height, at most: the stack's room is the rest, less its margins.
const BAR_ROOM: i32 = 64;
const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;

/// The look, as the server hands spark-shell's over: the colors, the face, the card's width and air, the
/// edge the stack hangs from and whether it moves.
#[derive(Clone, Debug, PartialEq)]
pub struct Look {
    pub fg: Rgb,
    pub accent: Rgb,
    pub muted: Rgb,
    pub ground: Rgb,
    pub lit: Rgb,
    pub alert: Rgb,
    pub font: String,
    pub width: f64,
    pub pad_x: f64,
    pub pad_y: f64,
    pub top: bool,
    pub motion: bool,
}

impl Default for Look {
    fn default() -> Look {
        let hex = |s: &str| Rgb::hex(s).unwrap_or(Rgb(0.5, 0.5, 0.5));
        Look {
            fg: hex("383a42"),
            accent: hex("4078f2"),
            muted: hex("696c77"),
            ground: hex("ebebec"),
            lit: hex("dcdcdd"),
            alert: hex("e45649"),
            font: "Monaspace Neon 12".into(),
            width: 360.0,
            pad_x: 18.0,
            pad_y: 12.0,
            top: true,
            motion: true,
        }
    }
}

impl Look {
    /// This look with what a line of the server's says over it: a key it leaves out, or gets wrong, stays.
    pub fn with(&self, said: &Value) -> Look {
        let word = |k: &str| said.get(k).and_then(Value::as_str).filter(|s| !s.is_empty());
        let color = |k: &str, own: Rgb| word(k).and_then(Rgb::hex).unwrap_or(own);
        let size = |k: &str, own: f64, most: f64| word(k).and_then(|s| s.parse::<f64>().ok()).filter(|n| *n >= 0.0 && *n <= most).unwrap_or(own);
        Look {
            fg: color("fg", self.fg),
            accent: color("accent", self.accent),
            muted: color("muted", self.muted),
            ground: color("ground", self.ground),
            lit: color("lit", self.lit),
            alert: color("alert", self.alert),
            font: word("font").map_or_else(|| self.font.clone(), |s| s.chars().filter(|c| !c.is_control()).take(120).collect()),
            width: size("width", self.width, 2000.0),
            pad_x: size("pad_x", self.pad_x, 200.0),
            pad_y: size("pad_y", self.pad_y, 200.0),
            top: word("anchor").map_or(self.top, |s| s != "bottom"),
            motion: word("motion").map_or(self.motion, |s| s != "no"),
        }
    }

    fn color(&self, tone: Tone) -> Rgb {
        match tone {
            Tone::Ground => self.ground,
            // a shade toward the text for each place behind: lighter on a dark ground, darker on a light one
            Tone::Behind(i) => self.ground.toward(self.fg, 0.07 * i as f64),
            Tone::Lit => self.lit,
            Tone::Text => self.fg,
            Tone::Dim => self.muted,
            Tone::Accent => self.accent,
            Tone::Alert => self.alert,
        }
    }
}

struct Ptr {
    _wl: WlPointer,
    device: Option<WpCursorShapeDeviceV1>,
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
    qh: QueueHandle<App>,
    handle: LoopHandle<'static, App>,
    lib: Lib,
    font: Font,
    ruler: Ruler,
    look: Look,
    stack: Stack,
    started: Instant,
    /// The surface, while there is something to show.
    layer: Option<LayerSurface>,
    /// Its size as the compositor last told it; none before its first answer.
    size: Option<(i32, i32)>,
    /// The size, the layer and the hold on the keyboard last asked of the compositor.
    asked: (i32, i32),
    over: bool,
    keyed: bool,
    scale: i32,
    /// The compositor has not shown the last frame yet, and one more is to be drawn when it has.
    waiting: bool,
    due: bool,
    pointer: Option<Ptr>,
    keyboard: Option<WlKeyboard>,
    kb: Keyboard,
    /// The timer for the next card whose time is up, and that time.
    timer: Option<(RegistrationToken, u64)>,
    pub dirty: bool,
    pub stop: bool,
}

impl App {
    pub fn new(globals: &GlobalList, qh: &QueueHandle<App>, handle: LoopHandle<'static, App>, lib: Lib) -> Result<App, String> {
        let compositor = CompositorState::bind(globals, qh).map_err(|e| format!("the compositor has no wl_compositor: {e}"))?;
        let layer_shell = LayerShell::bind(globals, qh).map_err(|_| "the compositor has no layer shell (zwlr_layer_shell_v1)".to_string())?;
        let shm = Shm::bind(globals, qh).map_err(|e| format!("the compositor has no wl_shm: {e}"))?;
        let pool = SlotPool::new(1 << 20, &shm).map_err(|e| format!("shared memory: {e}"))?;
        let look = Look::default();
        let font = Font::new(&lib, &look.font);
        let ruler = Ruler::new(&lib);
        let stack = Stack::new(metrics(&lib, &font, &ruler, &look), look.top, look.motion);
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
            font,
            ruler,
            look,
            stack,
            started: Instant::now(),
            layer: None,
            size: None,
            asked: (0, 0),
            over: false,
            keyed: false,
            scale: 1,
            waiting: false,
            due: false,
            pointer: None,
            keyboard: None,
            kb: Keyboard::new(),
            timer: None,
            dirty: false,
            stop: false,
        })
    }

    fn now(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }

    /// What the person did, a line each for the server. A server that is gone ends this.
    fn say(&mut self, events: Vec<Event>) {
        if events.is_empty() {
            return;
        }
        let mut out = std::io::stdout().lock();
        for e in &events {
            if writeln!(out, "{}", e.json()).is_err() {
                self.stop = true;
            }
        }
        if out.flush().is_err() {
            self.stop = true;
        }
        self.dirty = true;
    }

    /// A line of the server's: the look, a notification to show or to close, the keys.
    pub fn heard(&mut self, line: &str) {
        let Ok(said) = serde_json::from_str::<Value>(line) else { return };
        let now = self.now();
        if let Some(look) = said.get("look") {
            let look = self.look.with(look);
            if look.font != self.look.font {
                self.font.free(&self.lib);
                self.font = Font::new(&self.lib, &look.font);
            }
            let anchored = look.top != self.look.top;
            self.look = look;
            self.stack
                .look(metrics(&self.lib, &self.font, &self.ruler, &self.look), self.look.top, self.look.motion, now);
            if anchored {
                // the other edge: a surface of its own there
                self.drop_layer();
            }
        }
        if let Some(note) = said.get("show").and_then(Note::of) {
            self.stack.show(note, now);
        }
        if let Some(id) = said.get("close").and_then(Value::as_u64).and_then(|i| u32::try_from(i).ok()) {
            self.stack.close(id, now);
        }
        if said.get("open").and_then(Value::as_bool) == Some(true) {
            let events = self.stack.open_keys(now);
            self.say(events);
        }
        self.dirty = true;
    }

    /// The cards whose time is up.
    fn tick(&mut self) {
        let events = self.stack.tick(self.now());
        self.say(events);
        self.dirty = true;
    }

    fn drop_layer(&mut self) {
        (self.layer, self.size, self.asked, self.waiting, self.due) = (None, None, (0, 0), false, false);
        (self.over, self.keyed, self.scale) = (false, false, 1);
        // the pointer went with the surface: no leave comes for one that is gone
        self.stack.leave_pointer(self.now());
    }

    /// The surface as the stack needs it now: there while something shows, of the stack's size, over a
    /// full-screen window while a critical one is in sight or the keys are the stack's (keys held by a stack
    /// nobody sees would lock the person out), holding the keyboard while the keys are the stack's.
    fn fit(&mut self) {
        let now = self.now();
        let (w, h) = self.stack.size(now);
        let (w, h) = (w as i32, h as i32);
        if self.stack.is_empty() && !self.stack.moving(now) || w <= 0 || h <= 0 {
            if self.layer.is_some() {
                self.drop_layer();
            }
            return;
        }
        let keyed = self.stack.wants_keys();
        let over = keyed || self.stack.critical();
        if self.layer.is_none() {
            // no screen, no surface: a compositor with none closes it at once, and the next turn would make another
            if self.outputs.outputs().next().is_none() {
                return;
            }
            let surface = self.compositor.create_surface(&self.qh);
            // no output named: the compositor puts it on the screen with the keyboard
            let layer = self
                .layer_shell
                .create_layer_surface(&self.qh, surface, if over { Layer::Overlay } else { Layer::Top }, Some(NAMESPACE), None);
            layer.set_anchor(if self.look.top { Anchor::TOP } else { Anchor::BOTTOM } | Anchor::RIGHT);
            layer.set_margin(MARGIN, MARGIN, MARGIN, MARGIN);
            layer.set_exclusive_zone(0);
            layer.set_size(w as u32, h as u32);
            layer.set_keyboard_interactivity(if keyed {
                KeyboardInteractivity::Exclusive
            } else {
                KeyboardInteractivity::None
            });
            layer.commit();
            (self.layer, self.size, self.asked, self.over, self.keyed) = (Some(layer), None, (w, h), over, keyed);
            return;
        }
        let Some(layer) = self.layer.as_ref() else { return };
        let mut changed = false;
        if (w, h) != self.asked {
            layer.set_size(w as u32, h as u32);
            (self.asked, changed) = ((w, h), true);
        }
        if over != self.over {
            layer.set_layer(if over { Layer::Overlay } else { Layer::Top });
            (self.over, changed) = (over, true);
        }
        if keyed != self.keyed {
            layer.set_keyboard_interactivity(if keyed {
                KeyboardInteractivity::Exclusive
            } else {
                KeyboardInteractivity::None
            });
            (self.keyed, changed) = (keyed, true);
        }
        if changed {
            layer.commit();
        }
    }

    /// The next card's time, kept as one timer.
    fn arm(&mut self) {
        let want = self.stack.deadline();
        if self.timer.as_ref().map(|(_, at)| *at) == want {
            return;
        }
        if let Some((token, _)) = self.timer.take() {
            self.handle.remove(token);
        }
        let Some(at) = want else { return };
        let wait = Duration::from_millis(at.saturating_sub(self.now()));
        if let Ok(token) = self.handle.insert_source(Timer::from_duration(wait), |_, _, app: &mut App| {
            app.timer = None;
            app.tick();
            TimeoutAction::Drop
        }) {
            self.timer = Some((token, at));
        }
    }

    /// The loop's turn: the surface fitted, the frame drawn, the next time armed.
    pub fn turn(&mut self) {
        if !self.dirty {
            return;
        }
        self.dirty = false;
        self.fit();
        self.draw();
        self.arm();
    }

    /// The frame the stack says for now, on the surface as the compositor sized it. Each frame asks to be
    /// told when it is shown, and the next is drawn no sooner: a fast pointer draws a frame a refresh, not one
    /// an event.
    fn draw(&mut self) {
        let (Some(layer), Some((w, h))) = (self.layer.as_ref(), self.size) else {
            return;
        };
        if w <= 0 || h <= 0 {
            return;
        }
        if self.waiting {
            self.due = true;
            return;
        }
        let now = self.now();
        let scale = self.scale.max(1);
        let (bw, bh) = (w * scale, h * scale);
        let Ok((buffer, data)) = self.pool.create_buffer(bw, bh, bw * 4, wl_shm::Format::Argb8888) else {
            eprintln!("spark-bar notifications: no shared memory for a frame");
            return;
        };
        {
            let Some(c) = Canvas::new(&self.lib, &self.font, data, bw, bh, bw * 4, scale as f64) else {
                return;
            };
            for d in self.stack.frame(now, h as f64) {
                match d {
                    Draw::Fill { x, y, w, h, tone, alpha } => c.fill(x, y, w, h, self.look.color(tone), alpha),
                    Draw::Text {
                        x,
                        y,
                        w,
                        h,
                        text,
                        tone,
                        bold,
                        alpha,
                    } => c.text(x, y, w, h, &text, self.look.color(tone), bold, alpha),
                }
            }
        }
        let surface = layer.wl_surface();
        // the pointer is the stack's on its cards alone: beside them it falls through to the windows
        if let Ok(region) = Region::new(&self.compositor) {
            for r in self.stack.regions(now, h as f64) {
                region.add(r.x.floor() as i32, r.y.floor() as i32, r.w.ceil() as i32, r.h.ceil() as i32);
            }
            surface.set_input_region(Some(region.wl_region()));
        }
        surface.set_buffer_scale(scale);
        if buffer.attach_to(surface).is_ok() {
            surface.damage_buffer(0, 0, bw, bh);
            surface.frame(&self.qh, FrameCallbackData(surface.clone()));
            layer.commit();
            self.waiting = true;
        }
    }

    fn shape(&mut self, serial: u32) {
        if let Some(d) = self.pointer.as_ref().and_then(|p| p.device.as_ref()) {
            d.set_shape(serial, Cursor::Default);
        }
    }

    fn key(&mut self, code: u32) {
        let key = match self.kb.sym(code) {
            Some(sym) => Key::of_sym(sym),
            None => Key::of_evdev(code),
        };
        if let Some(key) = key {
            let events = self.stack.key(key, self.now());
            self.say(events);
            self.dirty = true;
        }
    }

    /// The stack's room: the shortest screen's height, less a bar's and the margins. It may open on any of them.
    fn measure(&mut self) {
        let short = self
            .outputs
            .outputs()
            .filter_map(|o| self.outputs.info(&o))
            .filter_map(|i| i.logical_size)
            .map(|(_, h)| h)
            .min();
        if let Some(h) = short.filter(|h| *h > 0) {
            let now = self.now();
            self.stack.room((h - BAR_ROOM - 2 * MARGIN).max(0) as f64, now);
            self.dirty = true;
        }
    }

    /// The end: what cairo and pango hold given back.
    pub fn free(&mut self) {
        self.drop_layer();
        self.ruler.free(&self.lib);
        self.font.free(&self.lib);
    }
}

/// The stack's sizes for a look: a cell is the width of "0" in its face.
fn metrics(lib: &Lib, font: &Font, ruler: &Ruler, look: &Look) -> Metrics {
    Metrics::new(font.px, ruler.width(lib, font, "0").max(1.0), look.width, look.pad_x, look.pad_y)
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        // its screen went: the next turn makes one on the screen that has the keyboard now
        if self.layer.as_ref() == Some(layer) {
            self.drop_layer();
            self.dirty = true;
        }
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, configure: LayerSurfaceConfigure, _: u32) {
        if self.layer.as_ref() != Some(layer) {
            return;
        }
        let (w, h) = (configure.new_size.0 as i32, configure.new_size.1 as i32);
        self.size = Some(if w > 0 && h > 0 { (w, h) } else { self.asked });
        self.dirty = true;
    }
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, factor: i32) {
        if self.layer.as_ref().is_some_and(|l| l.wl_surface() == surface) && self.scale != factor.max(1) {
            self.scale = factor.max(1);
            self.dirty = true;
        }
    }

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: Transform) {}

    /// The last frame is shown: the next is drawn when one is due, or a card is on its way.
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, _: u32) {
        if self.layer.as_ref().is_some_and(|l| l.wl_surface() == surface) {
            self.waiting = false;
            if std::mem::take(&mut self.due) || self.stack.moving(self.now()) {
                self.dirty = true;
            }
        }
    }

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {
        self.measure();
        self.dirty = true; // a screen again: what waited for one shows
    }

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {
        self.measure();
    }

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {
        self.measure();
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
                self.pointer = Some(Ptr { _wl: wl, device });
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
                self.stack.leave_pointer(self.now());
                self.dirty = true;
            }
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
        let Some(height) = self.size.map(|(_, h)| h as f64) else { return };
        for ev in events {
            if !self.layer.as_ref().is_some_and(|l| *l.wl_surface() == ev.surface) {
                continue;
            }
            let now = self.now();
            let (x, y) = ev.position;
            let events = match ev.kind {
                PointerEventKind::Enter { serial } => {
                    self.shape(serial);
                    self.stack.point(x, y, now, height)
                }
                PointerEventKind::Motion { .. } => self.stack.point(x, y, now, height),
                PointerEventKind::Leave { .. } => {
                    self.stack.leave_pointer(now);
                    vec![]
                }
                PointerEventKind::Press { button, .. } => {
                    let button = match button {
                        BTN_LEFT => 1,
                        BTN_MIDDLE => 2,
                        BTN_RIGHT => 3,
                        _ => continue,
                    };
                    self.stack.press(x, y, button, now, height)
                }
                PointerEventKind::Release { button: BTN_LEFT, .. } => self.stack.release(now),
                _ => vec![],
            };
            self.say(events);
            self.dirty = true;
        }
    }
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

/// The keyboard's events while the stack has the keys: evdev codes, read as the layout names them.
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

/// The drawer runs until its stdin ends (the server is gone) or a signal says to: Ok. Err when the
/// compositor goes or was never there.
pub fn run() -> Result<(), String> {
    use calloop::generic::Generic;
    use calloop::signals::{Signal, Signals};
    use calloop::{EventLoop, Interest, Mode, PostAction};
    use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
    use std::io::Read;
    use std::os::fd::AsRawFd;
    use wayland_client::globals::registry_queue_init;
    use wayland_client::ConnectError;

    // its own name in the process list: a second spark-bar there reads as two bars, to a person and to what counts them
    unsafe { libc::prctl(libc::PR_SET_NAME, c"spark-notify".as_ptr()) };
    let signals = Signals::new(&[Signal::SIGTERM, Signal::SIGINT]).map_err(|e| format!("signals: {e}"))?;
    if !wayland_sys::client::is_lib_available() {
        return Err("libwayland-client.so.0 is missing (Wayland's client library)".into());
    }
    let lib = Lib::open()?;
    let conn = Connection::connect_to_env().map_err(|e| match e {
        ConnectError::NoWaylandLib => "libwayland-client.so.0 is missing (Wayland's client library)".to_string(),
        ConnectError::NoCompositor => "no Wayland compositor here (WAYLAND_DISPLAY)".to_string(),
        ConnectError::InvalidFd => "WAYLAND_SOCKET is not a socket".to_string(),
    })?;
    let (globals, mut queue) = registry_queue_init::<App>(&conn).map_err(|e| format!("the compositor's globals: {e}"))?;
    let mut event_loop: EventLoop<'static, App> = EventLoop::try_new().map_err(|e| format!("event loop: {e}"))?;
    let handle = event_loop.handle();
    let mut app = App::new(&globals, &queue.handle(), handle.clone(), lib)?;
    queue.roundtrip(&mut app).map_err(|e| format!("the compositor: {e}"))?;
    WaylandSource::new(conn.clone(), queue)
        .insert(handle.clone())
        .map_err(|e| format!("event loop: {}", e.error))?;
    let stop = event_loop.get_signal();
    handle
        .insert_source(signals, |_, &mut (), app: &mut App| app.stop = true)
        .map_err(|e| format!("event loop: {}", e.error))?;
    // the server's lines: stdin read as it comes, never waited for
    let stdin = std::io::stdin();
    unsafe {
        let flags = libc::fcntl(stdin.as_raw_fd(), libc::F_GETFL);
        libc::fcntl(stdin.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK);
    }
    let mut buf: Vec<u8> = Vec::new();
    handle
        .insert_source(Generic::new(stdin, Interest::READ, Mode::Level), move |_, s, app: &mut App| {
            let mut chunk = [0u8; 8192];
            loop {
                match s.lock().read(&mut chunk) {
                    Ok(0) => {
                        app.stop = true;
                        return Ok(PostAction::Remove);
                    }
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(e) => return Err(e),
                }
            }
            while let Some(end) = buf.iter().position(|b| *b == b'\n') {
                let line: Vec<u8> = buf.drain(..=end).collect();
                app.heard(String::from_utf8_lossy(&line).trim_end());
            }
            if buf.len() > (1 << 20) {
                buf.clear();
            }
            Ok(PostAction::Continue)
        })
        .map_err(|e| format!("event loop: {}", e.error))?;
    let ran = event_loop.run(None, &mut app, |app| {
        app.turn();
        if app.stop {
            stop.stop();
        }
    });
    app.free();
    let _ = conn.flush();
    ran.map_err(|e| format!("the compositor is gone: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_look_takes_what_the_server_says_and_keeps_the_rest() {
        let own = Look::default();
        let said = own.with(
            &json!({"fg": "ffffff", "ground": "101010", "font": "DejaVu Sans Mono 12", "width": "420", "pad_x": "18", "anchor": "bottom", "motion": "no"}),
        );
        assert_eq!((said.fg, said.ground), (Rgb::hex("ffffff").unwrap(), Rgb::hex("101010").unwrap()));
        assert_eq!(
            (said.font.as_str(), said.width, said.pad_x, said.top, said.motion),
            ("DejaVu Sans Mono 12", 420.0, 18.0, false, false)
        );
        assert_eq!((said.accent, said.pad_y), (own.accent, own.pad_y), "a key left out stays");
        // a key it gets wrong stays too: no color, a size below nothing or beyond a screen, a word that is no number
        let wrong = said.with(&json!({"fg": "no color", "width": "-4", "pad_x": "900", "pad_y": "wide", "font": "", "anchor": 3}));
        assert_eq!(wrong, said);
        // a face's name is a line of plain text
        let face = own.with(&json!({"font": "Mono\u{7}\n 12"}));
        assert_eq!(face.font, "Mono 12");
    }
}
