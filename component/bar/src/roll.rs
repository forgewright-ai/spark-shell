//! A text longer than its window, rolling through it like a billboard: the window keeps its cells whatever the
//! text, so nothing beside it moves when the text changes. Plain functions of the time; the clock is handed in.

use crate::bar::{Module, State, ELLIPSIS};

/// The cells of nothing between a text's end and its start coming round again.
pub const GAP: usize = 3;
/// How long the text stands a cell farther, in milliseconds: four cells a second.
pub const STEP_MS: u64 = 250;
/// How long it rests at its start each round, in milliseconds.
pub const REST_MS: u64 = 2000;
/// A text this many cells longer than its window, or fewer, is cut and does not roll: so short a way is a twitch.
pub const SLACK: usize = 2;

/// Whether a text of `len` cells rolls in a window of `cells`.
pub fn rolls(len: usize, cells: usize) -> bool {
    cells > 0 && len > cells + SLACK
}

/// A round's time: the rest at the start, then a step for each cell of the text and of the gap after it.
fn round(len: usize) -> u64 {
    REST_MS + (len + GAP) as u64 * STEP_MS
}

/// How many cells a text of `len` has gone to the left, `elapsed` milliseconds after it came: none while it rests
/// at its start, then one more each step, until its start is back where it began.
pub fn offset(len: usize, elapsed: u64) -> usize {
    let t = elapsed % round(len);
    if t < REST_MS {
        0
    } else {
        (((t - REST_MS) / STEP_MS + 1) as usize) % (len + GAP)
    }
}

/// The milliseconds from `elapsed` to the text's next step: when a frame is next worth drawing.
pub fn next(len: usize, elapsed: u64) -> u64 {
    let t = elapsed % round(len);
    if t < REST_MS {
        REST_MS - t
    } else {
        STEP_MS - (t - REST_MS) % STEP_MS
    }
}

/// What a window of `cells` shows of a text that has gone `offset` cells: the text, the gap after it and the text
/// again, round and round.
pub fn window(glyphs: &[String], cells: usize, offset: usize) -> Vec<String> {
    let round = glyphs.len() + GAP;
    (0..cells).map(|i| glyphs.get((offset + i) % round).cloned().unwrap_or_else(|| " ".into())).collect()
}

/// A text cut to a window of `cells`: its first cells, the last one an ellipsis. One that fits is itself.
pub fn cut(glyphs: &[String], cells: usize) -> Vec<String> {
    if glyphs.len() <= cells {
        return glyphs.to_vec();
    }
    let mut out: Vec<String> = glyphs.iter().take(cells).cloned().collect();
    if let Some(last) = out.last_mut() {
        *last = ELLIPSIS.into();
    }
    out
}

/// Since when each module's text stands, in a bar's own milliseconds: a roll counts from there. A line that says
/// the same text again changes nothing, so a volume step or a timed line never sends a title back to its start.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Rolls {
    since: Vec<(String, String, State, u64)>,
}

impl Rolls {
    pub const fn new() -> Rolls {
        Rolls { since: Vec::new() }
    }

    /// A line's modules at a time: a text that is new, or whose module's state changed (what plays was paused),
    /// stands from now; a module the line does not have is forgotten.
    pub fn said(&mut self, modules: &[Module], at: u64) {
        let was = std::mem::take(&mut self.since);
        self.since = modules
            .iter()
            .filter(|m| !m.text.is_empty())
            .map(|m| {
                let kept = was.iter().find(|(name, text, state, _)| *name == m.name && *text == m.text && *state == m.state);
                (m.name.clone(), m.text.clone(), m.state, kept.map_or(at, |k| k.3))
            })
            .collect();
    }

    /// Since when a module's text stands; none for a module no line has said.
    pub fn since(&self, module: &str) -> Option<u64> {
        self.since.iter().find(|(name, ..)| name == module).map(|k| k.3)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn glyphs(s: &str) -> Vec<String> {
        s.chars().map(String::from).collect()
    }

    #[test]
    fn a_text_rolls_only_when_it_is_more_than_two_cells_too_long() {
        assert!(!rolls(24, 24) && !rolls(25, 24) && !rolls(26, 24), "it fits, or is cut by a cell or two");
        assert!(rolls(27, 24));
        assert!(!rolls(27, 0), "no window, nothing rolls");
    }

    #[test]
    fn it_rests_at_its_start_then_goes_a_cell_a_step_and_comes_round() {
        let len = 30;   // a round: 2000 ms of rest and 33 steps
        assert_eq!((offset(len, 0), offset(len, 1999)), (0, 0));
        assert_eq!((offset(len, 2000), offset(len, 2249), offset(len, 2250)), (1, 1, 2));
        assert_eq!(offset(len, 2000 + 31 * 250), 32, "the last cell of the gap at the window's left");
        assert_eq!(offset(len, 2000 + 32 * 250), 0, "its start is back");
        let whole = 2000 + 33 * 250;
        assert_eq!((offset(len, whole), offset(len, whole + 2000), offset(len, 10 * whole + 2250)), (0, 1, 2), "round and round");
        // the next step: at the rest's end, then every quarter of a second
        assert_eq!((next(len, 0), next(len, 1500), next(len, 2000), next(len, 2100), next(len, 2249)), (2000, 500, 250, 150, 1));
        assert_eq!(next(len, whole - 1), 1);
    }

    #[test]
    fn the_window_shows_the_text_the_gap_and_the_text_again() {
        let t = glyphs("abcdef");
        assert_eq!(window(&t, 4, 0).concat(), "abcd");
        assert_eq!(window(&t, 4, 3).concat(), "def ");
        assert_eq!(window(&t, 4, 6).concat(), "   a", "the gap, then its start coming in at the right");
        assert_eq!(window(&t, 4, 8).concat(), " abc");
        assert_eq!(window(&t, 4, 9).concat(), "abcd", "a round is the text and the gap");
        assert_eq!(window(&t, 0, 2), Vec::<String>::new());
    }

    #[test]
    fn a_cut_text_ends_in_an_ellipsis_and_one_that_fits_is_itself() {
        assert_eq!(cut(&glyphs("abcdef"), 4).concat(), format!("abc{ELLIPSIS}"));
        assert_eq!(cut(&glyphs("abcd"), 4).concat(), "abcd");
        assert_eq!(cut(&glyphs("abcdef"), 0), Vec::<String>::new());
    }

    fn playing(text: &str, state: State) -> Module {
        Module {
            name: "media".into(),
            text: text.into(),
            state,
            ..Module::default()
        }
    }

    #[test]
    fn a_text_stands_from_the_line_that_first_said_it() {
        let mut r = Rolls::new();
        assert_eq!(r.since("media"), None);
        r.said(&[playing("A long title", State::Ok)], 100);
        assert_eq!(r.since("media"), Some(100));
        // the same text again, at a timed line or after a volume step: it goes on from where it was
        r.said(&[playing("A long title", State::Ok)], 5000);
        assert_eq!(r.since("media"), Some(100));
        // paused and played again: from its start; a new track too
        r.said(&[playing("A long title", State::Muted)], 6000);
        assert_eq!(r.since("media"), Some(6000));
        r.said(&[playing("A long title", State::Ok)], 7000);
        assert_eq!(r.since("media"), Some(7000));
        r.said(&[playing("Another", State::Ok)], 8000);
        assert_eq!(r.since("media"), Some(8000));
        // nothing plays: forgotten, and the next one starts fresh
        r.said(&[], 9000);
        assert_eq!(r.since("media"), None);
    }
}
