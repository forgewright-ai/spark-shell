//! The two ports the use cases drive: the Display (the compositor's
//! screens and a background surface on each) and the Renderer (a loop
//! decoded and drawn into a surface). Screens are named by sway's names;
//! a surface is opaque here, handed from the Display to the Renderer.

use crate::domain::{Loop, Scaling, Screen};

/// What the Display and the Renderer tell the use cases, in the order it happened.
#[derive(Clone, Debug, PartialEq)]
pub enum Input<S> {
    /// The compositor has this screen (at the start, or plugged in).
    ScreenAdded(String),
    /// The screen is gone (unplugged or turned off), or its surface was closed.
    ScreenRemoved(String),
    /// The screen's surface has its size and scale, at first or changed.
    SurfaceReady { screen: Screen, surface: S },
    /// The compositor showed the frame the screen asked for.
    FrameShown(String),
    /// The renderer has news: a new frame may wait to be drawn.
    RendererWoke,
    /// Time passed: a screen may have waited too long for its frame.
    Tick,
}

/// The compositor: a background surface per screen, under the windows.
pub trait Display {
    /// What a renderer draws into, opaque to the use cases.
    type Surface;
    /// Puts a background surface on the screen; its size comes as SurfaceReady.
    fn add_surface(&mut self, screen: &str);
    /// Takes the screen's surface away.
    fn remove_surface(&mut self, screen: &str);
    /// Asks for FrameShown when the compositor shows the screen's next drawing.
    fn request_frame(&mut self, screen: &str);
}

/// The video: a loop decoded and drawn into a screen's surface.
pub trait Renderer<S> {
    /// Starts the loop on the screen's surface, playing.
    fn load(&mut self, screen: &Screen, surface: S, video: &Loop, scaling: Scaling) -> Result<(), String>;
    /// True when the screen's loop has a new frame to draw.
    fn frame_ready(&mut self, screen: &str) -> bool;
    /// Draws the screen's current frame at the screen's size and shows it.
    fn render(&mut self, screen: &Screen);
    fn pause(&mut self, screen: &str);
    fn resume(&mut self, screen: &str);
    /// Stops the screen's loop and lets its surface go.
    fn unload(&mut self, screen: &str);
}
