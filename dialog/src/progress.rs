//! What the header's bar shows while the dialog works: spark's own progress animations, five of them,
//! each saying what is going on. They are spark's (`look.PROGRESS` and `look._cells` in lib/spark/look.py):
//! eight cells of ASCII. The dialog borrows them so a wait reads the same here as at spark's prompt.

/// The kind of work the dialog is waiting on. Each kind has its own motion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Work {
    /// spark is thinking, or the dialog listens: a light bouncing.
    Think,
    /// The rows of a place are being read: an arrow crossing.
    Read,
    /// A step runs and more wait behind it: one step after another.
    Steps,
    /// A model loads, with no estimate of how long: a bar growing and shrinking.
    Swell,
    /// One step runs: marks moving right.
    March,
}

/// The cells a bar has.
pub const CELLS: usize = 8;

const STEPS: [&str; 4] = ["# . . . ", ". # . . ", ". . # . ", ". . . # "];
const SWELL: [&str; 6] = ["   ==   ", "  ====  ", " ====== ", "========", " ====== ", "  ====  "];
const MARCH: [&str; 4] = [">   >   ", " >   >  ", "  >   > ", "   >   >"];

/// The cells of a kind at tick `i`, bare: exactly what spark draws for that tick.
pub fn frame_cells(work: Work, i: u64) -> String {
    match work {
        Work::Read => {
            // the arrow's head walks ten places, two of them past the last cell
            let head = (i % (CELLS as u64 + 2)) as i64;
            (0..CELLS as i64)
                .map(|c| {
                    if head - 2 <= c && c <= head {
                        b"-->"[(c - head + 2) as usize] as char
                    } else {
                        ' '
                    }
                })
                .collect()
        }
        Work::Steps => STEPS[((i / 2) % STEPS.len() as u64) as usize].to_string(),
        Work::Swell => SWELL[(i % SWELL.len() as u64) as usize].to_string(),
        Work::March => MARCH[(i % MARCH.len() as u64) as usize].to_string(),
        Work::Think => {
            let span = 2 * CELLS as u64 - 2;
            let pos = i % span;
            let pos = if pos < CELLS as u64 { pos } else { span - pos } as usize;
            (0..CELLS).map(|c| if c == pos { '=' } else { ' ' }).collect()
        }
    }
}

/// The bar the header draws: the cells in brackets.
pub fn bar(work: Work, i: u64) -> String {
    format!("[{}]", frame_cells(work, i))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Sixteen ticks of each kind, as spark's look._cells draws them.
    const SPARK: [(Work, [&str; 16]); 5] = [
        (
            Work::Think,
            [
                "=       ", " =      ", "  =     ", "   =    ", "    =   ", "     =  ", "      = ", "       =", "      = ", "     =  ", "    =   ", "   =    ",
                "  =     ", " =      ", "=       ", " =      ",
            ],
        ),
        (
            Work::Read,
            [
                ">       ", "->      ", "-->     ", " -->    ", "  -->   ", "   -->  ", "    --> ", "     -->", "      --", "       -", ">       ", "->      ",
                "-->     ", " -->    ", "  -->   ", "   -->  ",
            ],
        ),
        (
            Work::Steps,
            [
                "# . . . ", "# . . . ", ". # . . ", ". # . . ", ". . # . ", ". . # . ", ". . . # ", ". . . # ", "# . . . ", "# . . . ", ". # . . ", ". # . . ",
                ". . # . ", ". . # . ", ". . . # ", ". . . # ",
            ],
        ),
        (
            Work::Swell,
            [
                "   ==   ", "  ====  ", " ====== ", "========", " ====== ", "  ====  ", "   ==   ", "  ====  ", " ====== ", "========", " ====== ", "  ====  ",
                "   ==   ", "  ====  ", " ====== ", "========",
            ],
        ),
        (
            Work::March,
            [
                ">   >   ", " >   >  ", "  >   > ", "   >   >", ">   >   ", " >   >  ", "  >   > ", "   >   >", ">   >   ", " >   >  ", "  >   > ", "   >   >",
                ">   >   ", " >   >  ", "  >   > ", "   >   >",
            ],
        ),
    ];

    #[test]
    fn every_kind_draws_what_spark_draws() {
        for (work, frames) in SPARK {
            for (i, want) in frames.iter().enumerate() {
                assert_eq!(&frame_cells(work, i as u64), want, "{:?} at tick {}", work, i);
            }
        }
    }

    #[test]
    fn a_bar_is_ten_columns_of_ascii_whatever_the_tick() {
        for work in [Work::Think, Work::Read, Work::Steps, Work::Swell, Work::March] {
            for i in [0u64, 1, 7, 8, 13, 14, 99, 1_000_003, u64::MAX] {
                let b = bar(work, i);
                assert_eq!(b.chars().count(), CELLS + 2, "{:?} at {}: {:?}", work, i, b);
                assert!(b.starts_with('[') && b.ends_with(']') && b.is_ascii(), "{:?}", b);
            }
        }
    }

    #[test]
    fn the_kinds_look_different_from_each_other() {
        let kinds = [Work::Think, Work::Read, Work::Steps, Work::Swell, Work::March];
        for (n, a) in kinds.iter().enumerate() {
            for b in &kinds[n + 1..] {
                let ra: Vec<String> = (0..16).map(|i| frame_cells(*a, i)).collect();
                let rb: Vec<String> = (0..16).map(|i| frame_cells(*b, i)).collect();
                assert_ne!(ra, rb, "{:?} and {:?} would read the same", a, b);
            }
        }
    }
}
