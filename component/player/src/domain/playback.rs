//! When a screen's loop plays. sway sends a surface no frame while it is
//! hidden (covered by windows, or a full screen window on its screen), so
//! a screen whose frame does not come is hidden: its loop pauses, and the
//! first frame after that is the screen shown again: its loop resumes.

/// How long a screen may wait for the compositor's frame before its loop
/// pauses, in milliseconds. A shown screen gets its frame within one
/// refresh (17 ms at 60 Hz, 42 ms at 24 Hz) and a busy compositor may miss
/// a few; 500 ms is far past both, so a shown screen never pauses, and a
/// covered one still stops decoding within a second.
pub const QUIET_MS: u64 = 500;

/// A screen's loop: playing, paused while the screen is hidden, or stopped
/// for good (its screen is gone).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Playback {
    #[default]
    Playing,
    Paused,
    Stopped,
}

/// What happened to the screen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Event {
    /// The compositor showed the frame the screen asked for.
    FrameShown,
    /// The frame asked for has not come for this many milliseconds.
    Quiet { ms: u64 },
    /// The screen is gone (unplugged, turned off, or the player stops).
    Gone,
}

/// What the renderer is told to do.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Command {
    Pause,
    Resume,
    Stop,
}

impl Playback {
    /// Moves on the event; returns the command it takes, if any.
    pub fn on(&mut self, event: Event) -> Option<Command> {
        let (next, command) = match (*self, event) {
            (Playback::Stopped, _) => (Playback::Stopped, None),
            (_, Event::Gone) => (Playback::Stopped, Some(Command::Stop)),
            (Playback::Playing, Event::Quiet { ms }) if ms >= QUIET_MS => (Playback::Paused, Some(Command::Pause)),
            (Playback::Paused, Event::FrameShown) => (Playback::Playing, Some(Command::Resume)),
            (state, _) => (state, None),
        };
        *self = next;
        command
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn after(start: Playback, event: Event) -> (Playback, Option<Command>) {
        let mut p = start;
        let c = p.on(event);
        (p, c)
    }

    #[test]
    fn a_loop_starts_playing() {
        assert_eq!(Playback::default(), Playback::Playing);
    }

    #[test]
    fn a_shown_frame_keeps_a_playing_loop_playing() {
        assert_eq!(after(Playback::Playing, Event::FrameShown), (Playback::Playing, None));
    }

    #[test]
    fn a_short_wait_is_not_quiet() {
        let ms = QUIET_MS - 1;
        assert_eq!(after(Playback::Playing, Event::Quiet { ms }), (Playback::Playing, None));
    }

    #[test]
    fn a_quiet_screen_pauses() {
        let ms = QUIET_MS;
        assert_eq!(after(Playback::Playing, Event::Quiet { ms }), (Playback::Paused, Some(Command::Pause)));
    }

    #[test]
    fn a_paused_loop_stays_paused_while_quiet() {
        let ms = QUIET_MS * 10;
        assert_eq!(after(Playback::Paused, Event::Quiet { ms }), (Playback::Paused, None));
    }

    #[test]
    fn the_first_frame_after_a_pause_resumes() {
        assert_eq!(after(Playback::Paused, Event::FrameShown), (Playback::Playing, Some(Command::Resume)));
    }

    #[test]
    fn a_gone_screen_stops_from_any_state() {
        assert_eq!(after(Playback::Playing, Event::Gone), (Playback::Stopped, Some(Command::Stop)));
        assert_eq!(after(Playback::Paused, Event::Gone), (Playback::Stopped, Some(Command::Stop)));
    }

    #[test]
    fn a_stopped_loop_takes_nothing_more() {
        for event in [Event::FrameShown, Event::Quiet { ms: QUIET_MS }, Event::Gone] {
            assert_eq!(after(Playback::Stopped, event), (Playback::Stopped, None), "{event:?}");
        }
    }

    #[test]
    fn a_hidden_then_shown_screen_pauses_once_and_resumes_once() {
        let mut p = Playback::Playing;
        let events = [
            Event::FrameShown,
            Event::Quiet { ms: 100 },
            Event::Quiet { ms: QUIET_MS + 1 },
            Event::Quiet { ms: QUIET_MS * 3 },
            Event::FrameShown,
            Event::FrameShown,
        ];
        let commands: Vec<Command> = events.into_iter().filter_map(|e| p.on(e)).collect();
        assert_eq!(commands, vec![Command::Pause, Command::Resume]);
        assert_eq!(p, Playback::Playing);
    }
}
