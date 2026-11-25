//! The dialog's own window: a Wayland toplevel the compositor frames like any other, drawn with cairo and pango
//! (paint.rs) and typed into through the keyboard's own layout (xkb.rs), as spark-bar and spark-winpad are. It
//! lives on a thread of its own. The dialog's loop hands it frames (the grid as drawing steps), its title and
//! the pointer's shape; it hands back what a terminal would: keys, the pointer in cells, the size in cells,
//! the focus.

use crate::draw::{Cell, Rgb, Step};
use crate::input::{self, Held, Wheel};
use crate::paint::{self, Font, Lib, Pixels};
use crate::xkb::{Composed, Keyboard};
use calloop::channel::{channel, Event as Msg, Sender};
use calloop::timer::{TimeoutAction, Timer};
use calloop::{EventLoop, LoopHandle, RegistrationToken};
use ratatui::crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent, MouseEventKind};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState};
use smithay_client_toolkit::data_device_manager::data_device::{DataDevice, DataDeviceHandler};
use smithay_client_toolkit::data_device_manager::data_offer::{DataOfferHandler, DragOffer};
use smithay_client_toolkit::data_device_manager::DataDeviceManagerState;
use smithay_client_toolkit::dispatch2::Dispatch2;
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::primary_selection::device::{PrimarySelectionDevice, PrimarySelectionDeviceHandler};
use smithay_client_toolkit::primary_selection::PrimarySelectionManagerState;
use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1};
use smithay_client_toolkit::reexports::protocols::wp::primary_selection::zv1::client::zwp_primary_selection_device_v1::ZwpPrimarySelectionDeviceV1;
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
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};
use wayland_client::globals::registry_queue_init;
use wayland_client::protocol::wl_callback::{self, WlCallback};
use wayland_client::protocol::wl_data_device::WlDataDevice;
use wayland_client::protocol::wl_data_device_manager::DndAction;
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
    /// The window's size in pixels, said before its size in cells: the layout in pixels places by them.
    Pixels(u32, u32),
    /// The face measured at another scale (Handle's cell, small, ascent and big), said before the size it makes.
    Font(Cell, Cell, (f64, f64), [(f64, f64); 5]),
    /// Where the pointer is, in pixels, said before the pointer's event it belongs to.
    At(f64, f64),
    /// The frames handed over before `when_drawn` are with the compositor: the window is mapped with them on it.
    Drawn,
    /// The window is gone: closed, or the compositor left.
    Gone,
}

enum Cmd {
    Frame(Vec<Step>, Option<Rgb>),
    Title(String),
    Pointer(&'static str),
    Paste(bool),
    Drawn,
    /// A family asked about, and who waits for the word on it.
    Face(String, mpsc::Sender<Option<f64>>),
}

/// How long a family is waited for: pango finds one in a few milliseconds, behind a frame being painted at most.
const FACE_WAIT: Duration = Duration::from_secs(1);

/// The most a paste brings: a megabyte of text.
const PASTE_MOST: u64 = 1 << 20;
/// How long a paste waits for the program that holds the text.
const PASTE_WAIT: Duration = Duration::from_secs(5);
/// The kinds of text a paste takes, the best first.
const TEXT_KINDS: [&str; 5] = ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING"];

fn text_kind(kinds: &[String]) -> Option<String> {
    TEXT_KINDS.iter().find(|k| kinds.iter().any(|have| have == *k)).map(|k| k.to_string())
}

/// The window, held by the dialog's loop.
pub struct Handle {
    /// A cell's size in pixels, the font's.
    pub cell: Cell,
    /// The smaller face's cell, and where each face's baseline stands under its line's top (the text's own, the
    /// smaller one): the layout in pixels places its words by them.
    pub small: Cell,
    pub ascent: (f64, f64),
    /// The large sizes' measures (draw::Size::BIG): a letter's width, and the baseline under the line's top.
    pub big: [(f64, f64); 5],
    /// The size asked for, in cells: the window's until it says another.
    pub size: (u16, u16),
    /// The size asked for, in pixels.
    pub px: (u32, u32),
    scale: Arc<AtomicI32>,
    tx: Sender<Cmd>,
}

impl Handle {
    /// How many of the screen's pixels stand on one of the window's: 1, or 2 and more on a screen of many pixels.
    /// A picture is made for the screen's pixels. A change is said as a size (Event::Resize), after Out::Font.
    pub fn scale(&self) -> u32 {
        self.scale.load(Ordering::Relaxed).max(1) as u32
    }
    /// A frame to show: the grid's steps, and the ground for the pixels past the last whole cell.
    pub fn frame(&self, steps: Vec<Step>, ground: Rgb) {
        let _ = self.tx.send(Cmd::Frame(steps, Some(ground)));
    }
    /// A frame with no ground under its steps: what they leave is clear, and what is behind the window shows there.
    pub fn frame_clear(&self, steps: Vec<Step>) {
        let _ = self.tx.send(Cmd::Frame(steps, None));
    }
    /// The words on the window's band.
    pub fn title(&self, title: &str) {
        let _ = self.tx.send(Cmd::Title(title.to_string()));
    }
    /// The pointer's shape over the window, by its name: default, pointer, text, grab, grabbing.
    pub fn pointer(&self, shape: &'static str) {
        let _ = self.tx.send(Cmd::Pointer(shape));
    }
    /// The clipboard's text asked for, or the text last selected with the pointer (`primary`): it comes as a paste
    /// (Event::Paste), when there is text to take.
    pub fn paste(&self, primary: bool) {
        let _ = self.tx.send(Cmd::Paste(primary));
    }
    /// The width of a typeface's specimen in this family (Font::letters), where a font here is the family's own: asked
    /// once a family, before the frame that first shows it.
    pub fn face(&self, family: &str) -> Option<f64> {
        let (tx, rx) = mpsc::channel();
        self.tx.send(Cmd::Face(family.to_string(), tx)).ok()?;
        rx.recv_timeout(FACE_WAIT).ok().flatten()
    }
    /// Asks the window to say (Out::Drawn) when the frames handed over so far are with the compositor. A window
    /// mapped unseen is shown on that word, never on a guess of how long a frame takes to paint.
    pub fn when_drawn(&self) {
        let _ = self.tx.send(Cmd::Drawn);
    }
}

/// The window opened on a thread of its own. The error says what is missing: a library, the compositor, the font.
pub fn open(setup: Setup, send: impl Fn(Out) + Send + Sync + 'static) -> Result<Handle, String> {
    let (tx, rx) = channel::<Cmd>();
    let (ready_tx, ready_rx) = mpsc::channel::<Result<(Cell, Cell, (f64, f64), [(f64, f64); 5], (u32, u32)), String>>();
    let size = (setup.cols, setup.rows);
    let scale = Arc::new(AtomicI32::new(1));
    let shared = scale.clone();
    std::thread::Builder::new()
        .name("window".into())
        .spawn(move || {
            let send: Say = Arc::new(send);
            let (mut event_loop, mut state) = match State::new(setup, rx, send, shared) {
                Ok(s) => s,
                Err(e) => {
                    let _ = ready_tx.send(Err(e));
                    return;
                }
            };
            let _ = ready_tx.send(Ok((
                state.font.cell,
                state.font.small_cell,
                state.font.ascent,
                state.font.big_cells,
                state.want,
            )));
            let signal = event_loop.get_signal();
            let _ = event_loop.run(None, &mut state, |s| {
                // the frames that came in one turn are one paint: the last of them
                if s.stale {
                    s.draw();
                }
                if s.ask_drawn && s.committed {
                    s.ask_drawn = false;
                    // the compositor answers once it has taken everything sent before, that frame's commit with it
                    s.conn.display().sync(&s.qh, Synced);
                }
                if s.stop {
                    signal.stop();
                }
            });
            (state.send)(Out::Gone);
        })
        .map_err(|e| format!("the window's thread: {e}"))?;
    let (cell, small, ascent, big, px) = ready_rx.recv().map_err(|_| "the window's thread ended".to_string())??;
    Ok(Handle {
        cell,
        small,
        ascent,
        big,
        size,
        px,
        scale,
        tx,
    })
}

/// How the window says something to the dialog's loop, from its own thread or from one that reads a paste.
type Say = Arc<dyn Fn(Out) + Send + Sync>;

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
    /// The clipboard and the pointer's selection, where the compositor has them: read for a paste, never written.
    clipboard: Option<DataDeviceManagerState>,
    clipboard_device: Option<DataDevice>,
    primary: Option<PrimarySelectionManagerState>,
    primary_device: Option<PrimarySelectionDevice>,
    handle: LoopHandle<'static, State>,
    conn: Connection,
    qh: QueueHandle<State>,
    window: Window,
    lib: Lib,
    font: Font,
    face: String,
    send: Say,
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
    frame: Option<(Vec<Step>, Option<Rgb>)>,
    /// A frame came and is not painted yet; a frame is on the surface; the dialog's loop asked to hear of it.
    stale: bool,
    committed: bool,
    ask_drawn: bool,
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
    /// The pixel the pointer was last said at.
    at_px: (f64, f64),
    held: Held,
    wheel: Wheel,
    /// A paste is being read: one at a time, so a held Ctrl+V starts no second reader.
    pasting: Arc<AtomicBool>,
    stop: bool,
}

impl State {
    fn new(setup: Setup, cmds: calloop::channel::Channel<Cmd>, send: Say, shared: Arc<AtomicI32>) -> Result<(EventLoop<'static, State>, State), String> {
        if !wayland_sys::client::is_lib_available() {
            return Err("libwayland-client.so.0 is missing (Wayland's client library)".into());
        }
        let lib = Lib::open()?;
        let font = Font::new(&lib, &setup.font, 1.0).ok_or_else(|| format!("no font for \"{}\"", setup.font))?;
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
                    s.stale = true;
                }
                Msg::Msg(Cmd::Drawn) => s.ask_drawn = true,
                Msg::Msg(Cmd::Face(family, answer)) => {
                    let _ = answer.send(s.font.letters(&s.lib, &family));
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
                Msg::Msg(Cmd::Paste(primary)) => s.paste(primary),
                // the dialog's loop is gone
                Msg::Closed => s.stop = true,
            })
            .map_err(|e| format!("event loop: {}", e.error))?;
        let mut state = State {
            registry: RegistryState::new(&globals),
            outputs: OutputState::new(&globals, &qh),
            seats: SeatState::new(&globals, &qh),
            cursors: CursorShapeManager::bind(&globals, &qh).ok(),
            clipboard: DataDeviceManagerState::bind(&globals, &qh).ok(),
            clipboard_device: None,
            primary: PrimarySelectionManagerState::bind(&globals, &qh).ok(),
            primary_device: None,
            _compositor: compositor,
            _xdg: xdg,
            shm,
            pool,
            handle,
            conn: conn.clone(),
            qh: qh.clone(),
            window,
            lib,
            font,
            face: setup.font,
            send,
            want,
            px: want,
            grid: (setup.cols, setup.rows),
            scale: 1,
            shared,
            configured: false,
            frame: None,
            stale: false,
            committed: false,
            ask_drawn: false,
            kb,
            keyboard: None,
            repeat: None,
            rate: (25, 600),
            pointer: None,
            shape: Shape::Default,
            at: None,
            at_px: (-1.0, -1.0),
            held: Held::default(),
            wheel: Wheel::default(),
            pasting: Arc::new(AtomicBool::new(false)),
            stop: false,
        };
        // the screens' scale before the first frame: a picture is made for the screen's pixels from the start, where
        // every screen has the same. The compositor says the window's own once it is on a screen
        for _ in 0..2 {
            queue.roundtrip(&mut state).map_err(|e| format!("the compositor: {e}"))?;
        }
        let scale = input::first_scale(state.outputs.outputs().filter_map(|o| state.outputs.info(&o)).map(|i| i.scale_factor));
        state.rescale(scale);
        state.want.0 = want.0.max((setup.cols as f64 * state.font.cell.w).ceil() as u32);
        WaylandSource::new(conn, queue)
            .insert(state.handle.clone())
            .map_err(|e| format!("event loop: {}", e.error))?;
        Ok((event_loop, state))
    }

    /// Another scale, and the face measured at it: a letter is as wide as it is drawn there.
    fn rescale(&mut self, scale: i32) {
        self.scale = scale;
        self.shared.store(scale, Ordering::Relaxed);
        let Some(font) = Font::new(&self.lib, &self.face, scale as f64) else { return };
        std::mem::replace(&mut self.font, font).free(&self.lib);
    }

    fn say(&self, e: Event) {
        (self.send)(Out::Event(e));
    }

    /// The frame painted and shown, at the surface's size and the output's scale. Nothing before the compositor
    /// has answered the first commit, and nothing before the dialog's first frame: the window maps drawn.
    fn draw(&mut self) {
        self.stale = false;
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
        // the ground over the whole window first: the pixels past the last whole cell are the ground's too. With none,
        // a buffer used before is wiped, so nothing of the last frame stays where this one draws nothing
        let whole: Vec<Step> = ground
            .map(|color| Step::Fill {
                x: 0.0,
                y: 0.0,
                w: self.px.0 as f64,
                h: self.px.1 as f64,
                color,
            })
            .into_iter()
            .collect();
        if whole.is_empty() {
            data.fill(0);
        }
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
            self.committed = true;
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

    /// The clipboard's text, or the pointer's selection, read aside and said as a paste: the program that holds it
    /// writes it in its own time, and the window never waits for it.
    fn paste(&mut self, primary: bool) {
        let pipe = if primary {
            let Some(offer) = self.primary_device.as_ref().and_then(|d| d.data().selection_offer()) else {
                return;
            };
            let Some(kind) = offer.with_mime_types(text_kind) else { return };
            offer.receive(kind).ok()
        } else {
            let Some(offer) = self.clipboard_device.as_ref().and_then(|d| d.data().selection_offer()) else {
                return;
            };
            let Some(kind) = offer.with_mime_types(text_kind) else { return };
            offer.receive(kind).ok()
        };
        let Some(pipe) = pipe else { return };
        // one reader at a time: a paste asked for while one is read (the key held, a program slow to write) is not
        // a second one, and its pipe closes here
        if self.pasting.swap(true, Ordering::SeqCst) {
            return;
        }
        let (send, pasting) = (self.send.clone(), self.pasting.clone());
        std::thread::spawn(move || {
            let text = read_text(pipe, PASTE_MOST, PASTE_WAIT);
            pasting.store(false, Ordering::SeqCst);
            if let Some(bytes) = text.filter(|b| !b.is_empty()) {
                send(Out::Event(Event::Paste(String::from_utf8_lossy(&bytes).into_owned())));
            }
        });
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
        if px != self.px || first {
            (self.send)(Out::Pixels(px.0, px.1));
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
            self.rescale(factor.max(1));
            let cell = self.font.cell;
            self.grid = (((self.px.0 as f64 / cell.w) as u16).max(1), ((self.px.1 as f64 / cell.h) as u16).max(1));
            self.draw();
            (self.send)(Out::Font(self.font.cell, self.font.small_cell, self.font.ascent, self.font.big_cells));
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
        if self.clipboard_device.is_none() {
            self.clipboard_device = self.clipboard.as_ref().map(|m| m.get_data_device(qh, &seat));
        }
        if self.primary_device.is_none() {
            self.primary_device = self.primary.as_ref().map(|m| m.get_selection_device(qh, &seat));
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
            // the pixel first, then the event it belongs to
            let px = (ev.position.0, ev.position.1);
            let moved = (px.0 - self.at_px.0).abs() >= 1.0 || (px.1 - self.at_px.1).abs() >= 1.0;
            if !matches!(ev.kind, PointerEventKind::Leave { .. } | PointerEventKind::Motion { .. }) || moved {
                self.at_px = px;
                (self.send)(Out::At(px.0, px.1));
            }
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
                    self.held.leave();
                }
                // a motion is said when it reaches another pixel: the layout in pixels has places smaller than a cell
                PointerEventKind::Motion { .. } if moved || self.at != Some(at) => {
                    self.at = Some(at);
                    let kind = if self.held.dragging() {
                        MouseEventKind::Drag(MouseButton::Left)
                    } else {
                        MouseEventKind::Moved
                    };
                    self.mouse(kind, at);
                }
                PointerEventKind::Press { button, .. } => {
                    if let Some(b) = button_of(button) {
                        self.held.press(b == MouseButton::Left);
                        self.mouse(MouseEventKind::Down(b), at);
                        // the middle button pastes what the pointer last selected, as in a terminal
                        if b == MouseButton::Middle {
                            self.paste(true);
                        }
                    }
                }
                PointerEventKind::Release { button, .. } => {
                    if let Some(b) = button_of(button) {
                        self.held.release(b == MouseButton::Left);
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

// the clipboard is read when a paste is asked for: what it offers, and a drag over the window, change nothing here
impl DataDeviceHandler for State {
    fn enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlDataDevice, _: f64, _: f64, _: &WlSurface) {}
    fn leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlDataDevice) {}
    fn motion(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlDataDevice, _: f64, _: f64) {}
    fn selection(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlDataDevice) {}
    fn drop_performed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlDataDevice) {}
}

impl DataOfferHandler for State {
    fn source_actions(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &mut DragOffer, _: DndAction) {}
    fn selected_action(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &mut DragOffer, _: DndAction) {}
}

impl PrimarySelectionDeviceHandler for State {
    fn selection(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &ZwpPrimarySelectionDeviceV1) {}
}

impl ShmHandler for State {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

/// The compositor's answer to a sync: it has taken every request sent before it.
struct Synced;

impl Dispatch2<WlCallback, State> for Synced {
    fn event(&self, s: &mut State, _: &WlCallback, event: wl_callback::Event, _: &Connection, _: &QueueHandle<State>) {
        if let wl_callback::Event::Done { .. } = event {
            (s.send)(Out::Drawn);
        }
    }
}

/// The text a program writes into a pipe, read until it closes its end: `most` bytes at most. None when it has
/// not closed within `wait`: a program that hangs holds no thread of the dialog's for good, and half a text is
/// not pasted.
fn read_text(mut pipe: impl std::io::Read + std::os::fd::AsFd, most: u64, wait: Duration) -> Option<Vec<u8>> {
    use std::os::fd::AsRawFd;
    let until = Instant::now() + wait;
    let most = usize::try_from(most).unwrap_or(usize::MAX);
    let mut bytes = Vec::new();
    let mut part = [0u8; 16384];
    loop {
        if bytes.len() >= most {
            return Some(bytes);
        }
        let left = until.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return None;
        }
        let mut fds = [libc::pollfd {
            fd: pipe.as_fd().as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        }];
        // SAFETY: one pollfd, alive for the call, of a descriptor this function holds
        let ready = unsafe { libc::poll(fds.as_mut_ptr(), 1, left.as_millis().min(i32::MAX as u128) as i32) };
        if ready == 0 {
            return None;
        }
        if ready < 0 {
            if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return None;
        }
        match pipe.read(&mut part) {
            Ok(0) => return Some(bytes),
            Ok(n) => bytes.extend_from_slice(&part[..n.min(most - bytes.len())]),
            Err(e) if matches!(e.kind(), std::io::ErrorKind::Interrupted | std::io::ErrorKind::WouldBlock) => continue,
            Err(_) => return None,
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_paste_takes_text_and_the_best_kind_of_it() {
        let kinds = |k: &[&str]| k.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(
            text_kind(&kinds(&["text/html", "text/plain", "text/plain;charset=utf-8"])).as_deref(),
            Some("text/plain;charset=utf-8"),
            "UTF-8 text before plain text, whatever their order"
        );
        assert_eq!(text_kind(&kinds(&["STRING", "UTF8_STRING"])).as_deref(), Some("UTF8_STRING"));
        assert_eq!(text_kind(&kinds(&["image/png", "text/html"])), None, "a picture or a page is no text to type");
        assert_eq!(text_kind(&[]), None);
    }

    #[test]
    fn a_paste_is_read_to_its_end_and_never_waited_for_for_good() {
        use std::io::Write;
        // the program writes its text and closes: all of it
        let (r, mut w) = std::io::pipe().unwrap();
        w.write_all(b"two words").unwrap();
        drop(w);
        assert_eq!(read_text(r, 1 << 20, Duration::from_secs(5)).as_deref(), Some(&b"two words"[..]));
        // more than the most a paste brings: the most, at once, the program's end still open
        let (r, mut w) = std::io::pipe().unwrap();
        w.write_all(&[b'x'; 300]).unwrap();
        assert_eq!(read_text(r, 100, Duration::from_secs(5)).map(|b| b.len()), Some(100));
        drop(w);
        // a program that wrote half and hangs: nothing, within the wait, and the reader is free again
        let (r, mut w) = std::io::pipe().unwrap();
        w.write_all(b"half").unwrap();
        let before = Instant::now();
        assert_eq!(read_text(r, 1 << 20, Duration::from_millis(150)), None);
        assert!(before.elapsed() < Duration::from_secs(2), "the wait is the wait asked for");
        drop(w);
        // nothing to paste is an empty text, not a failure
        let (r, w) = std::io::pipe().unwrap();
        drop(w);
        assert_eq!(read_text(r, 1 << 20, Duration::from_secs(5)).as_deref(), Some(&b""[..]));
    }
}
