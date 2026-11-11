//! The use cases: each screen that has a loop gets a background surface,
//! its loop is drawn when the renderer has a frame and the compositor
//! showed the last one, paused while the screen is hidden, and stopped
//! when the screen goes.

use super::ports::{Display, Input, Renderer};
use crate::domain::{Command, Config, Event, Loop, Playback, Screen};
use std::time::Instant;

/// A screen with a loop, from the moment the compositor has it.
struct Slot {
    name: String,
    video: Loop,
    playback: Playback,
    /// The screen once its surface has a size; its loop is loaded from then on.
    screen: Option<Screen>,
    /// When a frame was asked of the compositor, until it comes.
    asked: Option<Instant>,
    /// The renderer has a frame (or a new size) not drawn yet.
    pending: bool,
}

pub struct Wallpaper {
    config: Config,
    slots: Vec<Slot>,
}

impl Wallpaper {
    pub fn new(config: Config) -> Wallpaper {
        Wallpaper { config, slots: Vec::new() }
    }

    /// Takes one input. An error is a screen whose loop could not start:
    /// that screen is dropped, the others go on.
    pub fn handle<D, R>(&mut self, input: Input<D::Surface>, now: Instant, display: &mut D, renderer: &mut R) -> Result<(), String>
    where
        D: Display,
        R: Renderer<D::Surface>,
    {
        match input {
            Input::ScreenAdded(name) => self.add(name, display),
            Input::ScreenRemoved(name) => self.remove(&name, display, renderer),
            Input::SurfaceReady { screen, surface } => return self.ready(screen, surface, now, display, renderer),
            Input::FrameShown(name) => {
                if let Some(slot) = self.slots.iter_mut().find(|s| s.name == name) {
                    slot.asked = None;
                    let command = slot.playback.on(Event::FrameShown);
                    obey(command, slot, renderer);
                    draw_if_due(slot, now, display, renderer);
                }
            }
            Input::RendererWoke => {
                for slot in self.slots.iter_mut().filter(|s| s.screen.is_some()) {
                    if renderer.frame_ready(&slot.name) {
                        slot.pending = true;
                    }
                    draw_if_due(slot, now, display, renderer);
                }
            }
            Input::Tick => {
                for slot in &mut self.slots {
                    if let Some(asked) = slot.asked {
                        let ms = u64::try_from(now.saturating_duration_since(asked).as_millis()).unwrap_or(u64::MAX);
                        let command = slot.playback.on(Event::Quiet { ms });
                        obey(command, slot, renderer);
                    }
                }
            }
        }
        Ok(())
    }

    /// Every screen's loop stops and its surface goes (the player ends).
    pub fn stop<D, R>(&mut self, display: &mut D, renderer: &mut R)
    where
        D: Display,
        R: Renderer<D::Surface>,
    {
        let names: Vec<String> = self.slots.iter().map(|s| s.name.clone()).collect();
        for name in names {
            self.remove(&name, display, renderer);
        }
    }

    fn add<D: Display>(&mut self, name: String, display: &mut D) {
        if self.slots.iter().any(|s| s.name == name) {
            return;
        }
        let Some(video) = self.config.assignment.loop_for(&name) else { return };
        display.add_surface(&name);
        let slot = Slot {
            name,
            video: video.clone(),
            playback: Playback::Playing,
            screen: None,
            asked: None,
            pending: false,
        };
        self.slots.push(slot);
    }

    fn remove<D, R>(&mut self, name: &str, display: &mut D, renderer: &mut R)
    where
        D: Display,
        R: Renderer<D::Surface>,
    {
        let Some(i) = self.slots.iter().position(|s| s.name == name) else { return };
        let mut slot = self.slots.remove(i);
        let command = slot.playback.on(Event::Gone);
        obey(command, &slot, renderer);
        display.remove_surface(name);
    }

    fn ready<D, R>(&mut self, screen: Screen, surface: D::Surface, now: Instant, display: &mut D, renderer: &mut R) -> Result<(), String>
    where
        D: Display,
        R: Renderer<D::Surface>,
    {
        let Some(i) = self.slots.iter().position(|s| s.name == screen.name) else {
            return Ok(());
        };
        if screen.size.is_empty() {
            return Ok(());
        }
        let slot = &mut self.slots[i];
        if slot.screen.is_none() {
            if let Err(e) = renderer.load(&screen, surface, &slot.video, self.config.scaling) {
                let name = slot.name.clone();
                self.slots.remove(i);
                display.remove_surface(&name);
                return Err(format!("{name}: {e}"));
            }
        } else {
            slot.pending = true;
        }
        slot.screen = Some(screen);
        draw_if_due(slot, now, display, renderer);
        Ok(())
    }
}

/// Tells the renderer what the screen's playback decided.
fn obey<S, R: Renderer<S>>(command: Option<Command>, slot: &Slot, renderer: &mut R) {
    match command {
        Some(Command::Pause) => renderer.pause(&slot.name),
        Some(Command::Resume) => renderer.resume(&slot.name),
        Some(Command::Stop) if slot.screen.is_some() => renderer.unload(&slot.name),
        _ => {}
    }
}

/// Draws the screen when it has something new and the compositor showed
/// the last drawing: a hidden screen is never drawn twice.
fn draw_if_due<D, R>(slot: &mut Slot, now: Instant, display: &mut D, renderer: &mut R)
where
    D: Display,
    R: Renderer<D::Surface>,
{
    let Some(screen) = &slot.screen else { return };
    if !slot.pending || slot.asked.is_some() {
        return;
    }
    display.request_frame(&slot.name);
    renderer.render(screen);
    slot.asked = Some(now);
    slot.pending = false;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{Assignment, Scaling, Size, QUIET_MS};
    use std::cell::RefCell;
    use std::rc::Rc;
    use std::time::Duration;

    /// The display and the renderer in one log, so the order shows.
    #[derive(Clone, Default)]
    struct Fake {
        log: Rc<RefCell<Vec<String>>>,
        frames: Rc<RefCell<Vec<String>>>,
        refuse: bool,
    }

    impl Fake {
        fn say(&self, line: String) {
            self.log.borrow_mut().push(line);
        }
        fn take(&self) -> Vec<String> {
            std::mem::take(&mut *self.log.borrow_mut())
        }
        fn has_frame(&self, screen: &str) {
            self.frames.borrow_mut().push(screen.to_owned());
        }
    }

    impl Display for Fake {
        type Surface = u32;
        fn add_surface(&mut self, screen: &str) {
            self.say(format!("add {screen}"));
        }
        fn remove_surface(&mut self, screen: &str) {
            self.say(format!("remove {screen}"));
        }
        fn request_frame(&mut self, screen: &str) {
            self.say(format!("ask {screen}"));
        }
    }

    impl Renderer<u32> for Fake {
        fn load(&mut self, screen: &Screen, surface: u32, video: &Loop, scaling: Scaling) -> Result<(), String> {
            if self.refuse {
                return Err("no GPU".into());
            }
            let s = screen.size;
            self.say(format!(
                "load {} {}x{} on {surface} {} {scaling:?}",
                screen.name,
                s.width,
                s.height,
                video.path().display()
            ));
            Ok(())
        }
        fn frame_ready(&mut self, screen: &str) -> bool {
            let mut frames = self.frames.borrow_mut();
            let had = frames.iter().any(|f| f == screen);
            frames.retain(|f| f != screen);
            had
        }
        fn render(&mut self, screen: &Screen) {
            self.say(format!("render {} {}x{}", screen.name, screen.size.width, screen.size.height));
        }
        fn pause(&mut self, screen: &str) {
            self.say(format!("pause {screen}"));
        }
        fn resume(&mut self, screen: &str) {
            self.say(format!("resume {screen}"));
        }
        fn unload(&mut self, screen: &str) {
            self.say(format!("unload {screen}"));
        }
    }

    struct World {
        wallpaper: Wallpaper,
        display: Fake,
        renderer: Fake,
        t0: Instant,
    }

    impl World {
        fn new(assignment: Assignment) -> World {
            let display = Fake::default();
            let renderer = Fake {
                log: display.log.clone(),
                frames: display.frames.clone(),
                refuse: false,
            };
            let config = Config {
                assignment,
                scaling: Scaling::Smooth,
            };
            World {
                wallpaper: Wallpaper::new(config),
                display,
                renderer,
                t0: Instant::now(),
            }
        }

        fn all() -> World {
            World::new(Assignment::from_args(Some("/c/sea.mp4"), &[]).unwrap())
        }

        fn at(&mut self, ms: u64, input: Input<u32>) -> Result<(), String> {
            let now = self.t0 + Duration::from_millis(ms);
            self.wallpaper.handle(input, now, &mut self.display, &mut self.renderer)
        }

        fn send(&mut self, input: Input<u32>) {
            self.at(0, input).unwrap();
        }

        fn ready(name: &str, width: u32, height: u32) -> Input<u32> {
            Input::SurfaceReady {
                screen: Screen::new(name, Size::new(width, height), 1),
                surface: 7,
            }
        }

        /// DP-3 added, sized and loaded; the log emptied.
        fn playing() -> World {
            let mut w = World::all();
            w.send(Input::ScreenAdded("DP-3".into()));
            w.send(World::ready("DP-3", 1920, 1080));
            w.display.take();
            w
        }
    }

    #[test]
    fn only_a_screen_with_a_loop_gets_a_surface() {
        let assignment = Assignment::from_args(None, &["DP-3=/c/sea.mp4"]).unwrap();
        let mut w = World::new(assignment);
        w.send(Input::ScreenAdded("DP-3".into()));
        w.send(Input::ScreenAdded("HDMI-A-1".into()));
        w.send(Input::ScreenAdded("DP-3".into()));
        assert_eq!(w.display.take(), vec!["add DP-3"]);
    }

    #[test]
    fn a_ready_surface_loads_its_loop_once_and_a_new_size_redraws() {
        let mut w = World::all();
        w.send(Input::ScreenAdded("DP-3".into()));
        w.send(World::ready("DP-3", 1920, 1080));
        assert_eq!(w.display.take(), vec!["add DP-3", "load DP-3 1920x1080 on 7 /c/sea.mp4 Smooth"]);
        w.send(World::ready("DP-3", 2560, 1440));
        assert_eq!(w.display.take(), vec!["ask DP-3", "render DP-3 2560x1440"]);
    }

    #[test]
    fn an_empty_size_waits_for_a_real_one() {
        let mut w = World::all();
        w.send(Input::ScreenAdded("DP-3".into()));
        w.send(World::ready("DP-3", 0, 0));
        assert_eq!(w.display.take(), vec!["add DP-3"]);
    }

    #[test]
    fn a_frame_is_drawn_only_after_the_last_one_was_shown() {
        let mut w = World::playing();
        w.renderer.has_frame("DP-3");
        w.send(Input::RendererWoke);
        assert_eq!(w.display.take(), vec!["ask DP-3", "render DP-3 1920x1080"]);
        w.renderer.has_frame("DP-3");
        w.send(Input::RendererWoke);
        assert_eq!(w.display.take(), Vec::<String>::new(), "the compositor has not shown the last frame");
        w.send(Input::FrameShown("DP-3".into()));
        assert_eq!(w.display.take(), vec!["ask DP-3", "render DP-3 1920x1080"]);
        w.send(Input::FrameShown("DP-3".into()));
        assert_eq!(w.display.take(), Vec::<String>::new(), "nothing new to draw");
    }

    #[test]
    fn a_hidden_screen_pauses_and_its_first_frame_resumes_it() {
        let mut w = World::playing();
        w.renderer.has_frame("DP-3");
        w.send(Input::RendererWoke);
        w.display.take();
        w.at(QUIET_MS - 100, Input::Tick).unwrap();
        assert_eq!(w.display.take(), Vec::<String>::new());
        w.at(QUIET_MS, Input::Tick).unwrap();
        w.at(QUIET_MS + 400, Input::Tick).unwrap();
        assert_eq!(w.display.take(), vec!["pause DP-3"]);
        w.at(QUIET_MS * 9, Input::FrameShown("DP-3".into())).unwrap();
        assert_eq!(w.display.take(), vec!["resume DP-3"]);
    }

    #[test]
    fn a_quiet_screen_does_not_pause_the_others() {
        let mut w = World::playing();
        w.send(Input::ScreenAdded("HDMI-A-1".into()));
        w.send(World::ready("HDMI-A-1", 1920, 1080));
        w.renderer.has_frame("DP-3");
        w.renderer.has_frame("HDMI-A-1");
        w.send(Input::RendererWoke);
        w.at(100, Input::FrameShown("HDMI-A-1".into())).unwrap();
        w.display.take();
        w.at(QUIET_MS + 1, Input::Tick).unwrap();
        assert_eq!(w.display.take(), vec!["pause DP-3"]);
    }

    #[test]
    fn a_gone_screen_stops_and_loses_its_surface() {
        let mut w = World::playing();
        w.send(Input::ScreenRemoved("DP-3".into()));
        assert_eq!(w.display.take(), vec!["unload DP-3", "remove DP-3"]);
        w.renderer.has_frame("DP-3");
        w.send(Input::RendererWoke);
        w.send(Input::ScreenRemoved("DP-3".into()));
        assert_eq!(w.display.take(), Vec::<String>::new());
    }

    #[test]
    fn a_screen_gone_before_its_size_has_nothing_to_unload() {
        let mut w = World::all();
        w.send(Input::ScreenAdded("DP-3".into()));
        w.send(Input::ScreenRemoved("DP-3".into()));
        assert_eq!(w.display.take(), vec!["add DP-3", "remove DP-3"]);
    }

    #[test]
    fn a_refused_load_drops_that_screen_with_its_reason() {
        let mut w = World::all();
        w.renderer.refuse = true;
        w.send(Input::ScreenAdded("DP-3".into()));
        let ready = World::ready("DP-3", 1920, 1080);
        assert_eq!(w.at(0, ready), Err("DP-3: no GPU".into()));
        assert_eq!(w.display.take(), vec!["add DP-3", "remove DP-3"]);
        w.renderer.has_frame("DP-3");
        w.send(Input::RendererWoke);
        assert_eq!(w.display.take(), Vec::<String>::new());
    }

    #[test]
    fn stop_lets_every_screen_go() {
        let mut w = World::playing();
        w.send(Input::ScreenAdded("HDMI-A-1".into()));
        w.display.take();
        w.wallpaper.stop(&mut w.display, &mut w.renderer);
        assert_eq!(w.display.take(), vec!["unload DP-3", "remove DP-3", "remove HDMI-A-1"]);
    }
}
