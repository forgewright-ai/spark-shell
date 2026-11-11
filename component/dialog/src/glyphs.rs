//! The glyph families (#248): a theme's signs, one set of three, every glyph Monaspace Neon's own and one
//! cell wide (test/glyph_check.py holds the build to that). Stone is today's look and the default; Star
//! is thin and clear, stars and fine lines; Banner is banners and the scribe's marks. A family styles the
//! model's sign on the top rule, a choice's on and off, a row that opens, the list bullet, and the header's
//! three animations: thinking (its sign moving on dots), a layout opening (its gauge pair filling) and a
//! model loading (its gauge pair growing from the middle). The bar draws the same family's gauge pair and
//! workspaces (spark-shell's family_set).
//!
//! Never in a family: the prompt's sign (spark's own), the controls (back, more, close, check, cross, the
//! arrows, the rules) and the password's mask. The family comes in the environment, GLYPH_FAMILY beside the
//! palette's HEX_* keys, and a theme step's palette carries it after a change.

/// One family's signs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Glyphs {
    /// Its name as the config and a saved theme write it.
    pub name: &'static str,
    /// The model's sign on the top rule: a model answers, or none does.
    pub model_on: &'static str,
    pub model_off: &'static str,
    /// A choice: the one in use, and the others.
    pub dot: &'static str,
    pub ring: &'static str,
    /// A row that opens a list of its own.
    pub opens: &'static str,
    /// A list's bullet. The dialog draws no list bullet yet: the family holds it for when one comes.
    pub bullet: &'static str,
    /// Thinking's sign, moving on the track's dots.
    pub think: &'static str,
    /// The gauge pair: a cell lit, a cell unlit. The bar's battery and its sound, mic and brightness
    /// gauges wear the same pair.
    pub gauge_on: &'static str,
    pub gauge_off: &'static str,
}

/// The dots thinking's sign moves on, the same in every family.
pub const TRACK: &str = "\u{b7}";

/// Today's signs: diamonds, circles, cut stone.
pub const STONE: Glyphs = Glyphs {
    name: "stone",
    model_on: "\u{25c6}",  // black diamond
    model_off: "\u{25c7}", // white diamond
    dot: "\u{25cf}",       // black circle
    ring: "\u{25cb}",      // white circle
    opens: "\u{25b8}",     // black right-pointing small triangle
    bullet: "\u{2022}",    // bullet
    think: "\u{25b0}",     // black parallelogram
    gauge_on: "\u{25b0}",  // black parallelogram
    gauge_off: "\u{25b1}", // white parallelogram
};

/// Thin and clear: stars and fine lines.
pub const STAR: Glyphs = Glyphs {
    name: "star",
    model_on: "\u{2605}",  // black star
    model_off: "\u{2606}", // white star
    dot: "\u{2726}",       // black four pointed star
    ring: "\u{2727}",      // white four pointed star
    opens: "\u{2937}",     // arrow pointing downwards then curving rightwards
    bullet: "\u{26ac}",    // medium small white circle
    think: "\u{2726}",     // black four pointed star
    gauge_on: "\u{2501}",  // box drawings heavy horizontal
    gauge_off: "\u{2500}", // box drawings light horizontal
};

/// The keep and the road: banners and the scribe's marks.
pub const BANNER: Glyphs = Glyphs {
    name: "banner",
    model_on: "\u{25bc}",  // black down-pointing triangle
    model_off: "\u{25bd}", // white down-pointing triangle
    dot: "\u{25a0}",       // black square
    ring: "\u{25a1}",      // white square
    opens: "\u{27a4}",     // black rightwards arrowhead
    bullet: "\u{25aa}",    // black small square
    think: "\u{27a4}",     // black rightwards arrowhead
    gauge_on: "\u{25ae}",  // black vertical rectangle
    gauge_off: "\u{25af}", // white vertical rectangle
};

/// The three, Stone first: the order Settings > theme steps through.
pub const FAMILIES: [Glyphs; 3] = [STONE, STAR, BANNER];

impl Glyphs {
    /// The family of that name; None for any other word.
    pub fn named(name: &str) -> Option<Glyphs> {
        FAMILIES.iter().copied().find(|g| g.name == name.trim())
    }

    /// The family spark-shell hands the dialog in GLYPH_FAMILY: Stone when it names none, or none of the three.
    pub fn from(get: impl Fn(&str) -> Option<String>) -> Glyphs {
        get("GLYPH_FAMILY").and_then(|v| Glyphs::named(&v)).unwrap_or(STONE)
    }

    pub fn from_env() -> Glyphs {
        Glyphs::from(|k| std::env::var(k).ok())
    }

    /// Every glyph of the family, each once, in the order the fields stand.
    pub fn all(&self) -> Vec<&'static str> {
        let mut v = vec![];
        for g in [
            self.model_on,
            self.model_off,
            self.dot,
            self.ring,
            self.opens,
            self.bullet,
            self.think,
            self.gauge_on,
            self.gauge_off,
        ] {
            if !v.contains(&g) {
                v.push(g);
            }
        }
        v
    }
}

impl Default for Glyphs {
    fn default() -> Glyphs {
        STONE
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_family_is_named_and_stone_is_the_default() {
        assert_eq!(Glyphs::named("star"), Some(STAR));
        assert_eq!(Glyphs::named("banner"), Some(BANNER));
        assert_eq!(Glyphs::named("Stone"), None);
        assert_eq!(Glyphs::from(|_| None), STONE);
        assert_eq!(Glyphs::from(|k| (k == "GLYPH_FAMILY").then(|| "banner".to_string())), BANNER);
        assert_eq!(Glyphs::from(|_| Some("runes".to_string())), STONE);
        assert_eq!(Glyphs::default(), STONE);
    }

    #[test]
    fn every_sign_is_one_character_and_the_families_differ() {
        for g in FAMILIES {
            for s in g.all() {
                assert_eq!(s.chars().count(), 1, "{}: {:?}", g.name, s);
                assert!(!s.is_ascii(), "{}: {:?} is ASCII", g.name, s);
            }
        }
        for (n, a) in FAMILIES.iter().enumerate() {
            for b in &FAMILIES[n + 1..] {
                assert_ne!(a.model_on, b.model_on);
                assert_ne!(a.dot, b.dot);
                assert_ne!(a.gauge_on, b.gauge_on);
                assert_ne!(a.think, b.think);
            }
        }
    }

    #[test]
    fn stone_is_todays_set() {
        // the signs the dialog drew before the families, and the bar's gauge pair (#248)
        assert_eq!((STONE.model_on, STONE.model_off), ("\u{25c6}", "\u{25c7}"));
        assert_eq!((STONE.dot, STONE.ring, STONE.opens), (crate::ui::DOT, crate::ui::RING, "\u{25b8}"));
        assert_eq!((STONE.gauge_on, STONE.gauge_off), ("\u{25b0}", "\u{25b1}"));
    }
}
