//! The Calendar of the clock section: a month as weeks, Sunday first, and
//! the time in blocks, five rows tall (the figures the panel drew).

pub const MONTHS: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];
pub const DAYS: [&str; 7] = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

pub fn leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

pub fn days_in(y: i32, m: u32) -> u32 {
    match m {
        2 if leap(y) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// The weekday of a date, 0 Sunday (Sakamoto's).
pub fn weekday(y: i32, m: u32, d: u32) -> u32 {
    const T: [i32; 12] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
    let y = if m < 3 { y - 1 } else { y };
    ((y + y / 4 - y / 100 + y / 400 + T[(m - 1) as usize] + d as i32).rem_euclid(7)) as u32
}

/// The month `offset` months from (y, m).
pub fn shift(y: i32, m: u32, offset: i32) -> (i32, u32) {
    let n = y * 12 + (m as i32 - 1) + offset;
    (n.div_euclid(12), (n.rem_euclid(12) + 1) as u32)
}

/// "YYYY-MM-DD" as (year, month, day), a real day of a real month; None for any other shape.
pub fn ymd(s: &str) -> Option<(i32, u32, u32)> {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' || !b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit()) {
        return None;
    }
    let (y, m, d) = (s[0..4].parse().ok()?, s[5..7].parse().ok()?, s[8..10].parse().ok()?);
    ((1..=12).contains(&m) && d >= 1 && d <= days_in(y, m)).then_some((y, m, d))
}

/// The month as weeks of seven, a day or none.
pub fn weeks(y: i32, m: u32) -> Vec<[Option<u32>; 7]> {
    let mut out = vec![];
    let mut wk = [None; 7];
    let mut col = weekday(y, m, 1) as usize;
    for d in 1..=days_in(y, m) {
        wk[col] = Some(d);
        col += 1;
        if col == 7 {
            out.push(wk);
            wk = [None; 7];
            col = 0;
        }
    }
    if col > 0 {
        out.push(wk);
    }
    out
}

const FIGURES: [[&str; 5]; 11] = [
    ["###", "# #", "# #", "# #", "###"],
    ["  #", " ##", "  #", "  #", "  #"],
    ["###", "  #", "###", "#  ", "###"],
    ["###", "  #", "###", "  #", "###"],
    ["# #", "# #", "###", "  #", "  #"],
    ["###", "#  ", "###", "  #", "###"],
    ["###", "#  ", "###", "# #", "###"],
    ["###", "  #", "  #", "  #", "  #"],
    ["###", "# #", "###", "# #", "###"],
    ["###", "# #", "###", "  #", "###"],
    [" ", "#", " ", "#", " "],
];

/// "HH:MM" as five rows of full blocks, every stroke two cells wide, the figures two cells apart.
pub fn strokes(hhmm: &str) -> Vec<String> {
    (0..5)
        .map(|r| {
            hhmm.chars()
                .filter_map(|c| match c {
                    '0'..='9' => Some(FIGURES[c as usize - '0' as usize][r]),
                    ':' => Some(FIGURES[10][r]),
                    _ => None,
                })
                .map(|f| f.replace(' ', "  ").replace('#', "\u{2588}\u{2588}"))
                .collect::<Vec<_>>()
                .join("  ")
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn october_2026_starts_on_a_thursday_and_has_five_weeks() {
        assert_eq!(weekday(2026, 10, 1), 4);
        let w = weeks(2026, 10);
        assert_eq!(w.len(), 5);
        assert_eq!(w[0][4], Some(1));
        assert_eq!(w[4][6], Some(31));
    }

    #[test]
    fn months_shift_across_the_year_and_february_knows_a_leap_year() {
        assert_eq!(shift(2026, 12, 1), (2027, 1));
        assert_eq!(shift(2026, 1, -1), (2025, 12));
        assert_eq!(days_in(2028, 2), 29);
        assert_eq!(days_in(2100, 2), 28);
    }

    #[test]
    fn a_date_reads_only_as_a_real_day() {
        assert_eq!(ymd("2026-10-19"), Some((2026, 10, 19)));
        assert_eq!(ymd("2028-02-29"), Some((2028, 2, 29)));
        assert_eq!(ymd("2026-02-29"), None);
        assert_eq!(ymd("2026-1-19"), None);
        assert_eq!(ymd("2026-00-10"), None);
        assert_eq!(ymd("+026-10-19"), None);
    }

    #[test]
    fn the_time_is_five_rows_of_blocks() {
        let s = strokes("19:25");
        assert_eq!(s.len(), 5);
        assert!(s.iter().all(|l| l.chars().count() == s[0].chars().count()));
        assert!(s[0].contains('\u{2588}'));
    }
}
