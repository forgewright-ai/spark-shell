//! The dialog's own window: a Wayland toplevel the compositor frames like any other, drawn with cairo and pango
//! (paint.rs) and typed into through the keyboard's own layout (xkb.rs), as spark-bar and spark-winpad are. It
//! lives on a thread of its own. The dialog's loop hands it frames (the grid as drawing steps), its title and
//! the pointer's shape; it hands back what a terminal would: keys, the pointer in cells, the size in cells,
//! the focus.

use crate::draw::{Cell, Rgb, Step};
use crate::input::{self, Wheel};
use crate::paint::{self, Font, Lib, Pixels};
use crate::xkb::{Composed, Keyboard};
use calloop::channel::{channel, Event as Msg, Sender};
use calloop::timer::{TimeoutAction, Timer};
use calloop::{EventLoop, LoopHandle, RegistrationToken};
use ratatui::crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent, MouseEventKind};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState};
use smithay_client_toolkit::dispatch2::Dispatch2;
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::seat::pointer::cursor_shape::CursorShapeManager;
use smithay_client_toolkit::seat::pointer::{PointerEvent, PointerEventKind, PointerHandler};
use smithay_client_toolkit::seat::{Capability, SeatHandler, SeatState};
use smithay_client_toolkit::shell::xdg::window::{Window, WindowConfigure, WindowDecorations, WindowHandler};
use smithay_client_toolkit::shell::xdg::XdgShell;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shm::slot::SlotPool;
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{mpsc, Arc};
use std::time::Duration;
use wayland_client::globals::registry_queue_init;
use wayland_client::protocol::wl_keyboard::{self, KeyState, WlKeyboard};
use wayland_client::protocol::wl_output::{Transform, WlOutput};
use wayland_client::protocol::wl_pointer::WlPointer;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::protocol::wl_shm;
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{ConnectError, Connection, QueueHandle, WEnum};

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;

/// What the window is opened with.
pub struct Setup {
    /// The text's face in pango's words ("Monaspace Neon 12").
    pub font: String,
    pub app_id: String,
    pub title: String,
    /// The size it asks for, in cells.
    pub cols: u16,
    pub rows: u16,
}

/// What the window hands the dialog's loop.
pub enum Out {
    /// A key, the pointer, the size in cells, the focus: as a terminal says them.
    Event(Event),
    /// The window is gone: closed, or the compositor left.
    Gone,
}

enum Cmd {
    Frame(Vec<Step>, Rgb),
    Title(String),
    Pointer(&'static str),
}

/// The window, held by the dialog's loop.
pub struct Handle {
    /// A cell's size in pixels, the font's.
    pub cell: Cell,
    /// The size asked for, in cells: the window's until it says another.
    pub size: (u16, u16),
    scale: Arc<AtomicI32>,
    tx: Sender<Cmd>,
}

impl Handle {
    /// How many of the screen's pixels stand on one of the window's: 1, or 2 and more on a screen of many pixels.
    /// A picture is made for the screen's pixels. A change is said as a size (Event::Resize), the cells the same.
    pub fn scale(&self) -> u32 {
        self.scale.load(Ordering::Relaxed).max(1) as u32
    }
    /// A frame to show: the grid's steps, and the ground for the pixels past the last whole cell.
    pub fn frame(&self, steps: Vec<Step>, ground: Rgb) {
        let _ = self.tx.send(Cmd::Frame(steps, ground));
    }
    /// The words on the window's band.
    pub fn title(&self, title: &str) {
        let _ = self.tx.send(Cmd::Title(title.to_string()));
    }
    /// The pointer's shape over the window, by its name: default, pointer, text, grab, grabbing.
    pub fn pointer(&self, shape: &'static str) {
        let _ = self.tx.send(Cmd::Pointer(shape));
    }
}

/// The window opened on a thread of its own. The error says what is missing: a library, the compositor, the font.
pub fn open(setup: Setup, send: impl Fn(Out) + Send + 'static) -> Result<Handle, String> {
    let (tx, rx) = channel::<Cmd>();
    let (ready_tx, ready_rx) = mpsc::channel::<Result<Cell, String>>();
    let size = (setup.cols, setup.rows);
    let scale = Arc::new(AtomicI32::new(1));
    let shared = scale.clone();
    std::thread::Builder::new()
        .name("window".into())
        .spawn(move || {
            let send: Box<dyn Fn(Out)> = Box::new(send);
            let (mut event_loop, mut state) = match State::new(setup, rx, send, shared) {
                Ok(s) => s,
                Err(e) => {
                    let _ = ready_tx.send(Err(e));
                    return;
                }
            };
            let _ = ready_tx.send(Ok(state.font.cell));
            let signal = event_loop.get_signal();
            let _ = event_loop.run(None, &mut state, |s| {
                if s.stop {
                    signal.stop();
                }
            });
            (state.send)(Out::Gone);
        })
        .map_err(|e| format!("the window's thread: {e}"))?;
    let cell = ready_rx.recv().map_err(|_| "the window's thread ended".to_string())??;
    Ok(Handle { cell, size, scale, tx })
}

struct Ptr {
    _wl: WlPointer,
    device: Option<WpCursorShapeDeviceV1>,
    serial: u32,
    /// Over the window now.
    over: bool,
    shape: Option<Shape>,
}

struct State {
    registry: RegistryState,
    outputs: OutputState,
    seats: SeatState,
    _compositor: CompositorState,
    _xdg: XdgShell,
    shm: Shm,
    pool: SlotPool,
    cursors: Option<CursorShapeManager>,
    handle: LoopHandle<'static, State>,
    window: Window,
    lib: Lib,
    font: Font,
    send: Box<dyn Fn(Out)>,
    /// The size asked for, in pixels: the window's where the compositor names none.
    want: (u32, u32),
    /// The surface's size in pixels, the grid's in cells, the output's scale.
    px: (u32, u32),
    grid: (u16, u16),
    scale: i32,
    /// The scale as the dialog's loop reads it.
    shared: Arc<AtomicI32>,
    configured: bool,
    /// The frame shown: drawn again when the size or the scale changes.
    frame: Option<(Vec<Step>, Rgb)>,
    kb: Keyboard,
    keyboard: Option<WlKeyboard>,
    /// A held key that repeats: its evdev code and its timer.
    repeat: Option<(u32, RegistrationToken)>,
    /// The compositor's repeat: keys a second, and the wait before the first.
    rate: (i32, i32),
    pointer: Option<Ptr>,
    shape: Shape,
    /// The cell the pointer was last said at, the left button held, the wheel's scroll not yet a step.
    at: Option<(u16, u16)>,
    left: bool,
    wheel: Wheel,
    stop: bool,
}

impl State {
    fn new(
        setup: Setup,
        cmds: calloop::channel::Channel<Cmd>,
        send: Box<dyn Fn(Out)>,
        shared: Arc<AtomicI32>,
    ) -> Result<(EventLoop<'static, State>, State), String> {
        if !wayland_sys::client::is_lib_available() {
            return Err("libwayland-client.so.0 is missing (Wayland's client library)".into());
        }
        let lib = Lib::open()?;
        let font = Font::new(&lib, &setup.font).ok_or_else(|| format!("no font for \"{}\"", setup.font))?;
        let kb = Keyboard::new()?;
        let conn = Connection::connect_to_env().map_err(|e| match e {
            ConnectError::NoWaylandLib => "libwayland-client.so.0 is missing (Wayland's client library)".to_string(),
            ConnectError::NoCompositor => "no Wayland compositor here (WAYLAND_DISPLAY)".to_string(),
            ConnectError::InvalidFd => "WAYLAND_SOCKET is not a socket".to_string(),
        })?;
        let (globals, mut queue) = registry_queue_init::<State>(&conn).map_err(|e| format!("the compositor's globals: {e}"))?;
        let qh = queue.handle();
        let event_loop: EventLoop<'static, State> = EventLoop::try_new().map_err(|e| format!("event loop: {e}"))?;
        let handle = event_loop.handle();
        let compositor = CompositorState::bind(&globals, &qh).map_err(|e| format!("the compositor has no wl_compositor: {e}"))?;
        let xdg = XdgShell::bind(&globals, &qh).map_err(|_| "the compositor has no xdg shell (xdg_wm_base)".to_string())?;
        let shm = Shm::bind(&globals, &qh).map_err(|e| format!("the compositor has no wl_shm: {e}"))?;
        let want = (
            (setup.cols as f64 * font.cell.w).ceil().max(1.0) as u32,
            (setup.rows as f64 * font.cell.h).ceil().max(1.0) as u32,
        );
        let pool = SlotPool::new((want.0 * want.1 * 4) as usize, &shm).map_err(|e| format!("shared memory: {e}"))?;
        // the compositor draws the frame and the band: the window is the dialog's content alone
        let window = xdg.create_window(compositor.create_surface(&qh), WindowDecorations::RequestServer, &qh);
        window.set_app_id(setup.app_id);
        window.set_title(setup.title);
        // a first commit with nothing on it: the compositor answers with the size, and the first frame maps the window
        window.commit();
        handle
            .insert_source(cmds, |msg, &mut (), s: &mut State| match msg {
                Msg::Msg(Cmd::Frame(steps, ground)) => {
                    s.frame = Some((steps, ground));
                    s.draw();
                }
                Msg::Msg(Cmd::Title(t)) => s.window.set_title(t),
                Msg::Msg(Cmd::Pointer(name)) => {
                    s.shape = match name {
                        "pointer" => Shape::Pointer,
                        "text" => Shape::Text,
                        "grab" => Shape::Grab,
                        "grabbing" => Shape::Grabbing,
                        _ => Shape::Default,
                    };
                    s.set_shape();
                }
                // the dialog's loop is gone
                Msg::Closed => s.stop = true,
            })
            .map_err(|e| format!("event loop: {}", e.error))?;
        let mut state = State {
            registry: RegistryState::new(&globals),
            outputs: OutputState::new(&globals, &qh),
            seats: SeatState::new(&globals, &qh),
            cursors: CursorShapeManager::bind(&globals, &qh).ok(),
            _compositor: compositor,
            _xdg: xdg,
            shm,
            pool,
            handle,
            window,
            lib,
            font,
            send,
            want,
            px: want,
            grid: (setup.cols, setup.rows),
            scale: 1,
            shared,
            configured: false,
            frame: None,
            kb,
            keyboard: None,
            repeat: None,
            rate: (25, 600),
            pointer: None,
            shape: Shape::Default,
            at: None,
            left: false,
            wheel: Wheel::default(),
            stop: false,
        };
        // the screens' scales before the first frame: a picture is made for the screen's pixels from the start. The
        // largest, where there are several; the compositor says the window's own once it is on a screen
        for _ in 0..2 {
            queue.roundtrip(&mut state).map_err(|e| format!("the compositor: {e}"))?;
        }
        let largest = state.outputs.outputs().filter_map(|o| state.outputs.info(&o)).map(|i| i.scale_factor).max();
        state.scale = largest.unwrap_or(1).max(1);
        state.shared.store(state.scale, Ordering::Relaxed);
        WaylandSource::new(conn, queue)
            .insert(state.handle.clone())
            .map_err(|e| format!("event loop: {}", e.error))?;
        Ok((event_loop, state))
    }

    fn say(&self, e: Event) {
        (self.send)(Out::Event(e));
    }

    /// The frame painted and shown, at the surface's size and the output's scale. Nothing before the compositor
    /// has answered the first commit, and nothing before the dialog's first frame: the window maps drawn.
    fn draw(&mut self) {
        if !self.configured {
            return;
        }
        let Some((steps, ground)) = &self.frame else { return };
        let scale = self.scale.max(1);
        let (bw, bh) = (self.px.0 as i32 * scale, self.px.1 as i32 * scale);
        let Ok((buffer, data)) = self.pool.create_buffer(bw, bh, bw * 4, wl_shm::Format::Argb8888) else {
            eprintln!("spark-dialog: no shared memory for a frame");
            return;
        };
        // the ground over the whole window first: the pixels past the last whole cell are the ground's too
        let whole = [Step::Fill {
            x: 0.0,
            y: 0.0,
            w: self.px.0 as f64,
            h: self.px.1 as f64,
            color: *ground,
        }];
        for part in [&whole[..], &steps[..]] {
            let px = Pixels {
                data: &mut *data,
                w: bw,
                h: bh,
                stride: bw * 4,
                scale: scale as f64,
            };
            if !paint::paint(&self.lib, &self.font, px, part) {
                return;
            }
        }
        let surface = self.window.wl_surface();
        surface.set_buffer_scale(scale);
        if buffer.attach_to(surface).is_ok() {
            surface.damage_buffer(0, 0, bw, bh);
            surface.commit();
        }
    }

    /// The pointer's shape asked of the compositor, while the pointer is over the window.
    fn set_shape(&mut self) {
        let want = self.shape;
        let Some(p) = self.pointer.as_mut().filter(|p| p.over && p.shape != Some(want)) else {
            return;
        };
        if let Some(d) = &p.device {
            d.set_shape(p.serial, want);
            p.shape = Some(want);
        }
    }

    fn stop_repeat(&mut self) {
        if let Some((_, token)) = self.repeat.take() {
            self.handle.remove(token);
        }
    }

    /// A key as it is now, with the modifiers held now: pressed, or held and counted again.
    fn key_event(&self, evdev: u32, kind: KeyEventKind) {
        let Some(sym) = self.kb.sym(evdev) else { return };
        if let Some(k) = input::key(sym, self.kb.text(sym), self.kb.mods(), kind) {
            self.say(Event::Key(k));
        }
    }

    fn key_down(&mut self, evdev: u32) {
        self.stop_repeat();
        let Some(sym) = self.kb.sym(evdev) else { return };
        match self.kb.compose(sym) {
            // a dead key waits for its letter: nothing typed yet
            Composed::Held => return,
            Composed::Text(text) => {
                for c in text.chars().filter(|c| !c.is_control()) {
                    let held = if c.is_uppercase() { KeyModifiers::SHIFT } else { KeyModifiers::NONE };
                    self.say(Event::Key(KeyEvent::new(KeyCode::Char(c), held)));
                }
                return;
            }
            Composed::Key => {}
        }
        self.key_event(evdev, KeyEventKind::Press);
        let (rate, delay) = self.rate;
        if rate <= 0 || !self.kb.repeats(evdev) {
            return;
        }
        let every = Duration::from_millis((1000 / rate as u64).max(1));
        let timer = Timer::from_duration(Duration::from_millis(delay.max(1) as u64));
        let token = self.handle.insert_source(timer, move |_, _, s: &mut State| match s.repeat {
            Some((held, _)) if held == evdev => {
                s.key_event(evdev, KeyEventKind::Repeat);
                TimeoutAction::ToDuration(every)
            }
            _ => TimeoutAction::Drop,
        });
        self.repeat = token.ok().map(|t| (evdev, t));
    }

    fn key_up(&mut self, evdev: u32) {
        if self.repeat.as_ref().is_some_and(|(held, _)| *held == evdev) {
            self.stop_repeat();
        }
    }

    fn mouse(&self, kind: MouseEventKind, (column, row): (u16, u16)) {
        self.say(Event::Mouse(MouseEvent {
            kind,
            column,
            row,
            modifiers: self.kb.mods().held(),
        }));
    }
}

impl WindowHandler for State {
    fn request_close(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &Window) {
        self.stop = true;
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &Window, configure: WindowConfigure, _: u32) {
        // a size the compositor names is the window's; where it names none (a floating window's first answer), the
        // one asked for
        let px = match configure.new_size {
            (Some(w), Some(h)) => (w.get(), h.get()),
            _ => self.want,
        };
        let cell = self.font.cell;
        let grid = (((px.0 as f64 / cell.w) as u16).max(1), ((px.1 as f64 / cell.h) as u16).max(1));
        let first = !self.configured;
        self.configured = true;
        if px == self.px && grid == self.grid && !first {
            return;
        }
        self.px = px;
        if grid != self.grid {
            self.grid = grid;
            self.say(Event::Resize(grid.0, grid.1));
        }
        self.draw();
    }
}

impl CompositorHandler for State {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, factor: i32) {
        if self.scale != factor.max(1) {
            self.scale = factor.max(1);
            self.shared.store(self.scale, Ordering::Relaxed);
            self.draw();
            // the dialog's loop draws again: its pictures are for the screen's pixels
            self.say(Event::Resize(self.grid.0, self.grid.1));
        }
    }

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: Transform) {}

    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: u32) {}

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}
}

impl OutputHandler for State {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {}

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {}

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {}
}

impl SeatHandler for State {
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
                    over: false,
                    shape: None,
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
                self.stop_repeat();
                if let Some(k) = self.keyboard.take() {
                    k.release();
                }
            }
            _ => {}
        }
    }

    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}
}

impl PointerHandler for State {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlPointer, events: &[PointerEvent]) {
        for ev in events {
            if &ev.surface != self.window.wl_surface() {
                continue;
            }
            let cell = self.font.cell;
            let at = input::cell(ev.position.0, ev.position.1, (cell.w, cell.h), self.grid);
            match ev.kind {
                PointerEventKind::Enter { serial } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.serial = serial;
                        p.over = true;
                        p.shape = None;
                    }
                    self.set_shape();
                    self.at = Some(at);
                    self.mouse(MouseEventKind::Moved, at);
                }
                PointerEventKind::Leave { .. } => {
                    if let Some(p) = self.pointer.as_mut() {
                        p.over = false;
                    }
                    self.at = None;
                }
                // a motion is said when it reaches another cell, as a terminal says it
                PointerEventKind::Motion { .. } if self.at != Some(at) => {
                    self.at = Some(at);
                    let kind = if self.left {
                        MouseEventKind::Drag(MouseButton::Left)
                    } else {
                        MouseEventKind::Moved
                    };
                    self.mouse(kind, at);
                }
                PointerEventKind::Press { button, .. } => {
                    if let Some(b) = button_of(button) {
                        self.left |= b == MouseButton::Left;
                        self.mouse(MouseEventKind::Down(b), at);
                    }
                }
                PointerEventKind::Release { button, .. } => {
                    if let Some(b) = button_of(button) {
                        self.left &= b != MouseButton::Left;
                        self.mouse(MouseEventKind::Up(b), at);
                    }
                }
                PointerEventKind::Axis { vertical, .. } => {
                    let steps = self.wheel.steps(vertical.absolute);
                    let kind = if steps < 0 { MouseEventKind::ScrollUp } else { MouseEventKind::ScrollDown };
                    for _ in 0..steps.unsigned_abs().min(8) {
                        self.mouse(kind, at);
                    }
                }
                _ => {}
            }
        }
    }
}

fn button_of(button: u32) -> Option<MouseButton> {
    match button {
        BTN_LEFT => Some(MouseButton::Left),
        BTN_RIGHT => Some(MouseButton::Right),
        BTN_MIDDLE => Some(MouseButton::Middle),
        _ => None,
    }
}

impl ShmHandler for State {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

/// The keyboard's events: evdev codes, read through the layout the compositor hands over.
struct KeyData;

impl Dispatch2<WlKeyboard, State> for KeyData {
    fn event(&self, s: &mut State, _: &WlKeyboard, event: wl_keyboard::Event, _: &Connection, _: &QueueHandle<State>) {
        match event {
            wl_keyboard::Event::Keymap { fd, size, .. } => s.kb.keymap(fd, size),
            wl_keyboard::Event::Enter { .. } => s.say(Event::FocusGained),
            wl_keyboard::Event::Leave { .. } => {
                s.stop_repeat();
                s.kb.compose_reset();
                s.say(Event::FocusLost);
            }
            wl_keyboard::Event::Modifiers {
                mods_depressed,
                mods_latched,
                mods_locked,
                group,
                ..
            } => s.kb.modifiers(mods_depressed, mods_latched, mods_locked, group),
            wl_keyboard::Event::RepeatInfo { rate, delay } => s.rate = (rate, delay),
            wl_keyboard::Event::Key {
                key,
                state: WEnum::Value(state),
                ..
            } => match state {
                KeyState::Pressed => s.key_down(key),
                KeyState::Released => s.key_up(key),
                _ => {}
            },
            _ => {}
        }
    }
}

impl ProvidesRegistryState for State {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}

delegate_registry!(State);
delegate_dispatch2!(State);
