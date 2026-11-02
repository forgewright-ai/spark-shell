//! The Display: the compositor's screens through smithay-client-toolkit,
//! and on each a surface on the wlr layer shell's background layer, under
//! the windows, anchored to every edge, over the bars' zones, taking no
//! keyboard. libwayland-client.so.0 is opened at run time.

use crate::app::{Display, Input};
use crate::domain::{Screen, Size};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, FrameCallbackData};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};
use wayland_client::globals::GlobalList;
use wayland_client::protocol::wl_output::{Transform, WlOutput};
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, QueueHandle};

/// The layer shell namespace: what sway's rules and tools call the surface.
const NAMESPACE: &str = "wallpaper";

/// A screen's background surface and what the compositor said of it.
struct Background {
    name: String,
    output: WlOutput,
    layer: LayerSurface,
    logical: Size,
    scale: u32,
}

impl Background {
    fn ready(&self) -> Input<WlSurface> {
        let screen = Screen::new(self.name.clone(), self.logical, self.scale);
        Input::SurfaceReady {
            screen,
            surface: self.layer.wl_surface().clone(),
        }
    }
}

/// The Wayland side of the player: the event loop's data. Its handlers
/// turn the compositor's events into inputs for the use cases.
pub struct Desktop {
    registry: RegistryState,
    outputs: OutputState,
    compositor: CompositorState,
    layer_shell: LayerShell,
    qh: QueueHandle<Desktop>,
    /// Every screen the compositor has, by sway's name.
    screens: Vec<(WlOutput, String)>,
    backgrounds: Vec<Background>,
    inbox: Vec<Input<WlSurface>>,
}

impl Desktop {
    pub fn new(globals: &GlobalList, qh: &QueueHandle<Desktop>) -> Result<Desktop, String> {
        let compositor = CompositorState::bind(globals, qh).map_err(|e| format!("the compositor has no wl_compositor: {e}"))?;
        let layer_shell = LayerShell::bind(globals, qh).map_err(|_| "the compositor has no layer shell (zwlr_layer_shell_v1)".to_string())?;
        Ok(Desktop {
            registry: RegistryState::new(globals),
            outputs: OutputState::new(globals, qh),
            compositor,
            layer_shell,
            qh: qh.clone(),
            screens: Vec::new(),
            backgrounds: Vec::new(),
            inbox: Vec::new(),
        })
    }

    /// An input from outside Wayland (the renderer, the clock), in turn with the rest.
    pub fn push(&mut self, input: Input<WlSurface>) {
        self.inbox.push(input);
    }

    /// The inputs since the last call, oldest first.
    pub fn take_inbox(&mut self) -> Vec<Input<WlSurface>> {
        std::mem::take(&mut self.inbox)
    }

    fn background(&mut self, surface: &WlSurface) -> Option<&mut Background> {
        self.backgrounds.iter_mut().find(|b| b.layer.wl_surface() == surface)
    }

    fn scale_of(&self, output: &WlOutput) -> u32 {
        self.outputs.info(output).map_or(1, |info| u32::try_from(info.scale_factor).unwrap_or(1))
    }
}

impl Display for Desktop {
    type Surface = WlSurface;

    fn add_surface(&mut self, screen: &str) {
        let Some((output, _)) = self.screens.iter().find(|(_, name)| name == screen) else {
            return;
        };
        let output = output.clone();
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self
            .layer_shell
            .create_layer_surface(&self.qh, surface, Layer::Background, Some(NAMESPACE), Some(&output));
        layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();
        let scale = self.scale_of(&output);
        self.backgrounds.push(Background {
            name: screen.to_owned(),
            output,
            layer,
            logical: Size::default(),
            scale,
        });
    }

    fn remove_surface(&mut self, screen: &str) {
        self.backgrounds.retain(|b| b.name != screen);
    }

    fn request_frame(&mut self, screen: &str) {
        if let Some(b) = self.backgrounds.iter().find(|b| b.name == screen) {
            let surface = b.layer.wl_surface();
            surface.frame(&self.qh, FrameCallbackData(surface.clone()));
        }
    }
}

impl LayerShellHandler for Desktop {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        if let Some(b) = self.backgrounds.iter().find(|b| &b.layer == layer) {
            self.inbox.push(Input::ScreenRemoved(b.name.clone()));
        }
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, configure: LayerSurfaceConfigure, _: u32) {
        let Some(i) = self.backgrounds.iter().position(|b| &b.layer == layer) else {
            return;
        };
        let scale = self.scale_of(&self.backgrounds[i].output);
        let b = &mut self.backgrounds[i];
        b.logical = Size::new(configure.new_size.0, configure.new_size.1);
        b.scale = scale;
        let ready = b.ready();
        self.inbox.push(ready);
    }
}

impl CompositorHandler for Desktop {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, factor: i32) {
        let scale = u32::try_from(factor).unwrap_or(1);
        let Some(b) = self.background(surface) else { return };
        if scale == b.scale || b.logical.is_empty() {
            return;
        }
        b.scale = scale;
        let ready = b.ready();
        self.inbox.push(ready);
    }

    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &WlSurface, _: u32) {
        if let Some(b) = self.background(surface) {
            let shown = Input::FrameShown(b.name.clone());
            self.inbox.push(shown);
        }
    }

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: Transform) {}

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlSurface, _: &WlOutput) {}
}

impl OutputHandler for Desktop {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        let Some(name) = self.outputs.info(&output).and_then(|info| info.name) else {
            return;
        };
        self.screens.push((output, name.clone()));
        self.inbox.push(Input::ScreenAdded(name));
    }

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlOutput) {}

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: WlOutput) {
        if let Some(i) = self.screens.iter().position(|(o, _)| o == &output) {
            let (_, name) = self.screens.remove(i);
            self.inbox.push(Input::ScreenRemoved(name));
        }
    }
}

impl ProvidesRegistryState for Desktop {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState];
}

delegate_registry!(Desktop);
delegate_dispatch2!(Desktop);
