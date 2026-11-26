//! The scrubber: every string another program hands a component passes it before the screen. The twin of
//! spark-shell's SCRUB_JQ. Each class is a named line, so it can be argued with. The dialog scrubs what a
//! provider says; the notifications' drawer what an app sent.

/// The characters that can redraw, retitle or reorder a screen.
pub const DROP: &[(char, char, &str)] = &[
    ('\u{0000}', '\u{0008}', "C0 before the tab"),
    ('\u{000a}', '\u{001f}', "C0 after the tab: a row is one line"),
    ('\u{007f}', '\u{009f}', "DEL and C1"),
    ('\u{200e}', '\u{200f}', "the bidi marks"),
    ('\u{202a}', '\u{202e}', "the bidi embeddings and overrides"),
    ('\u{2066}', '\u{2069}', "the bidi isolates"),
    ('\u{200b}', '\u{200d}', "the zero-width space and joiners"),
    ('\u{2060}', '\u{2065}', "the word joiner and the invisible operators"),
    ('\u{feff}', '\u{feff}', "the zero-width no-break space"),
    ('\u{2028}', '\u{2029}', "the line and paragraph separators"),
    ('\u{00ad}', '\u{00ad}', "the soft hyphen"),
    ('\u{061c}', '\u{061c}', "the Arabic letter mark"),
    ('\u{115f}', '\u{1160}', "the Hangul fillers"),
    ('\u{180e}', '\u{180e}', "the Mongolian vowel separator"),
    ('\u{3164}', '\u{3164}', "the Hangul filler"),
    ('\u{ffa0}', '\u{ffa0}', "the halfwidth Hangul filler"),
    ('\u{fff9}', '\u{fffb}', "the annotation marks"),
    ('\u{e0000}', '\u{e007f}', "the tag block"),
];

/// The text with every DROP class gone and a tab as a space.
pub fn scrub(s: &str) -> String {
    s.chars()
        .map(|c| if c == '\t' { ' ' } else { c })
        .filter(|c| !DROP.iter().any(|(a, b, _)| c >= a && c <= b))
        .collect()
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
    fn a_character_no_screen_shows_goes_and_an_emoji_stays() {
        let unseen =
            "\u{ad}\u{61c}\u{115f}\u{1160}\u{180e}\u{2061}\u{2062}\u{2063}\u{2064}\u{3164}\u{ffa0}\u{fff9}\u{fffa}\u{fffb}\u{e0001}\u{e0020}\u{e0041}\u{e007f}";
        for c in unseen.chars() {
            assert_eq!(scrub(&format!("pay{}pal", c)), "paypal", "{:?} stayed", c);
        }
        // the variation selector keeps an emoji in color; the joiner between two goes, as ever
        assert_eq!(scrub("\u{2764}\u{fe0f}"), "\u{2764}\u{fe0f}");
        assert_eq!(scrub("\u{1f468}\u{200d}\u{1f469}"), "\u{1f468}\u{1f469}");
    }

    #[test]
    fn plain_text_stays() {
        assert_eq!(scrub("caf\u{e9} \u{25cf} 5 GHz"), "caf\u{e9} \u{25cf} 5 GHz");
        assert_eq!(scrub("a\tb"), "a b");
        assert_eq!(scrub("\u{1b}[2Jev\u{202e}il"), "[2Jevil");
    }
}
