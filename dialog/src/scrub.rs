//! The scrubber: every string a provider hands the dialog passes it
//! before the screen, the brief or a record. The twin of spark-shell's
//! SCRUB_JQ. Each class is a named line, so it can be argued with.

/// The characters that can redraw, retitle or reorder a screen.
pub const DROP: &[(char, char, &str)] = &[
    ('\u{0000}', '\u{0008}', "C0 before the tab"),
    ('\u{000a}', '\u{001f}', "C0 after the tab: a row is one line"),
    ('\u{007f}', '\u{009f}', "DEL and C1"),
    ('\u{200e}', '\u{200f}', "the bidi marks"),
    ('\u{202a}', '\u{202e}', "the bidi embeddings and overrides"),
    ('\u{2066}', '\u{2069}', "the bidi isolates"),
    ('\u{200b}', '\u{200d}', "the zero-width space and joiners"),
    ('\u{2060}', '\u{2060}', "the word joiner"),
    ('\u{feff}', '\u{feff}', "the zero-width no-break space"),
    ('\u{2028}', '\u{2029}', "the line and paragraph separators"),
];

/// The text with every DROP class gone and a tab as a space.
pub fn scrub(s: &str) -> String {
    s.chars()
        .map(|c| if c == '\t' { ' ' } else { c })
        .filter(|c| !DROP.iter().any(|(a, b, _)| c >= a && c <= b))
        .collect()
}

/// The text cut to `cells` terminal cells, a wide character never split.
pub fn cut(s: &str, cells: usize) -> String {
    let mut out = String::new();
    let mut w = 0;
    for c in s.chars() {
        let cw = unicode_width::UnicodeWidthChar::width(c).unwrap_or(0);
        if w + cw > cells {
            break;
        }
        w += cw;
        out.push(c);
    }
    out
}

/// How many cells the text takes.
pub fn cells(s: &str) -> usize {
    unicode_width::UnicodeWidthStr::width(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_class_goes() {
        for (a, b, why) in DROP {
            for c in [*a, *b] {
                let s = format!("x{}y", c);
                assert_eq!(scrub(&s), "xy", "{} ({:?}) stayed", why, c);
            }
        }
    }

    #[test]
    fn plain_text_stays() {
        assert_eq!(scrub("caf\u{e9} \u{25cf} 5 GHz"), "caf\u{e9} \u{25cf} 5 GHz");
        assert_eq!(scrub("a\tb"), "a b");
        assert_eq!(scrub("\u{1b}[2Jev\u{202e}il"), "[2Jevil");
    }

    #[test]
    fn a_cut_never_splits_a_wide_character() {
        assert_eq!(cut("\u{4e2d}\u{6587}x", 3), "\u{4e2d}");
        assert_eq!(cut("abcdef", 4), "abcd");
        assert_eq!(cells("\u{4e2d}a"), 3);
    }
}
