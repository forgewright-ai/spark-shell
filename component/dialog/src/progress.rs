//! What the dialog shows while it works: eight cells drawn from the theme's glyph family (#248), each
//! kind of wait its own motion. Thinking is the family's sign moving on dots, across the eight cells and
//! back; a model loading is the gauge pair growing from the middle and back; a step under way, a layout or
//! an app opening, a copy, is the gauge pair filling one cell at a time. spark-shell's pulse_frame draws the
//! same frames in a terminal, from the same family.

use crate::glyphs::{Glyphs, TRACK};

/// The kind of work the dialog is waiting on. Each kind has its own motion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Work {
    /// spark is thinking, or the dialog listens: the family's sign bouncing on dots.
    Think,
    /// The rows of a place are being read: the gauge pair filling.
    Read,
    /// A step runs and more wait behind it: the gauge pair filling.
    Steps,
    /// A model loads, with no estimate of how long: the gauge pair growing from the middle and back.
    Swell,
    /// One step runs, an app opens, files are copied: the gauge pair filling.
    March,
}

/// The cells a bar has.
pub const CELLS: usize = 8;

/// A model loading: how many cells are lit, from the middle, at each tick.
const SWELL: [usize; 6] = [2, 4, 6, 8, 6, 4];

/// The cells of a kind at tick `i`, in the family `g`: always CELLS cells.
pub fn frame_cells(work: Work, g: &Glyphs, i: u64) -> String {
    match work {
        Work::Think => {
            // across the eight cells and back: 0 to 7, then 6 down to 1, fourteen ticks a round
            let span = 2 * CELLS as u64 - 2;
            let pos = i % span;
            let pos = if pos < CELLS as u64 { pos } else { span - pos } as usize;
            (0..CELLS).map(|c| if c == pos { g.think } else { TRACK }).collect()
        }
        Work::Swell => {
            let w = SWELL[(i % SWELL.len() as u64) as usize];
            let side = (CELLS - w) / 2;
            [g.gauge_off.repeat(side), g.gauge_on.repeat(w), g.gauge_off.repeat(side)].concat()
        }
        Work::Read | Work::Steps | Work::March => {
            // one cell lit, then two, to all eight, and again
            let k = (i % CELLS as u64) as usize + 1;
            [g.gauge_on.repeat(k), g.gauge_off.repeat(CELLS - k)].concat()
        }
    }
}

/// The bar the header and the status row draw: the cells alone, the unlit ones the track.
pub fn bar(work: Work, g: &Glyphs, i: u64) -> String {
    frame_cells(work, g, i)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::glyphs::{BANNER, FAMILIES, STAR, STONE};

    /// Every frame of the three, as the approved set draws them (glyph-families-14: bounce, fill and swell).
    fn bounce(lit: &str) -> Vec<String> {
        let at: Vec<usize> = (0..8).chain((1..7).rev()).collect();
        at.iter().map(|&i| [TRACK.repeat(i), lit.to_string(), TRACK.repeat(7 - i)].concat()).collect()
    }
    fn fill(on: &str, off: &str) -> Vec<String> {
        (1..=8).map(|k| [on.repeat(k), off.repeat(8 - k)].concat()).collect()
    }
    fn swell(on: &str, off: &str) -> Vec<String> {
        [2, 4, 6, 8, 6, 4]
            .iter()
            .map(|&w| [off.repeat((8 - w) / 2), on.repeat(w), off.repeat((8 - w) / 2)].concat())
            .collect()
    }

    #[test]
    fn every_family_draws_the_agreed_frames() {
        for (g, lit, on, off) in [
            (STONE, "\u{25b0}", "\u{25b0}", "\u{25b1}"),
            (STAR, "\u{2726}", "\u{2501}", "\u{2500}"),
            (BANNER, "\u{27a4}", "\u{25ae}", "\u{25af}"),
        ] {
            for (work, want) in [(Work::Think, bounce(lit)), (Work::Steps, fill(on, off)), (Work::Swell, swell(on, off))] {
                for round in 0..2u64 {
                    for (i, w) in want.iter().enumerate() {
                        let t = round * want.len() as u64 + i as u64;
                        assert_eq!(&frame_cells(work, &g, t), w, "{} {:?} at tick {}", g.name, work, t);
                    }
                }
            }
            // stone's thinking at tick 0: the sign first, seven dots
            assert_eq!(frame_cells(Work::Think, &g, 0), format!("{}{}", lit, "\u{b7}".repeat(7)));
        }
    }

    #[test]
    fn a_step_an_app_opening_and_a_read_fill_as_a_layout_opens() {
        for g in FAMILIES {
            for i in 0..20 {
                assert_eq!(frame_cells(Work::March, &g, i), frame_cells(Work::Steps, &g, i));
                assert_eq!(frame_cells(Work::Read, &g, i), frame_cells(Work::Steps, &g, i));
            }
        }
    }

    #[test]
    fn a_bar_is_eight_cells_whatever_the_tick() {
        for g in FAMILIES {
            for work in [Work::Think, Work::Read, Work::Steps, Work::Swell, Work::March] {
                for i in [0u64, 1, 7, 8, 13, 14, 99, 1_000_003, u64::MAX] {
                    let b = bar(work, &g, i);
                    assert_eq!(crate::scrub::cells(&b), CELLS, "{} {:?} at {}: {:?}", g.name, work, i, b);
                    assert_eq!(b.chars().count(), CELLS, "{:?}", b);
                }
            }
        }
    }

    #[test]
    fn the_three_motions_look_different_from_each_other() {
        for g in FAMILIES {
            let kinds = [Work::Think, Work::Steps, Work::Swell];
            for (n, a) in kinds.iter().enumerate() {
                for b in &kinds[n + 1..] {
                    let ra: Vec<String> = (0..16).map(|i| frame_cells(*a, &g, i)).collect();
                    let rb: Vec<String> = (0..16).map(|i| frame_cells(*b, &g, i)).collect();
                    assert_ne!(ra, rb, "{}: {:?} and {:?} would read the same", g.name, a, b);
                }
            }
        }
    }
}
