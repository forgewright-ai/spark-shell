//! The dialog accepts live palette updates from its provider.

pub use spark_theme::palette::{hex, slots_here, Palette};

/// A palette a theme's step hands the dialog (#183): plain colors, rrggbb or empty, and the glyph family by its
/// name (#248). Anything else and the dialog wears none of it.
pub fn step_palette_ok(p: &serde_json::Map<String, serde_json::Value>) -> bool {
    p.iter().all(|(k, v)| {
        v.as_str()
            .is_some_and(|s| s.is_empty() || spark_theme::hex_digits(s).is_some() || (k == "GLYPH_FAMILY" && crate::glyphs::Glyphs::named(s).is_some()))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_steps_palette_is_colors_and_a_family_by_its_name() {
        let m = |pairs: &[(&str, &str)]| pairs.iter().map(|(k, v)| (k.to_string(), serde_json::json!(v))).collect();
        assert!(step_palette_ok(&m(&[("HEX_FG", "d8dee9"), ("HEX_ANSI_1", "")])));
        assert!(step_palette_ok(&m(&[("HEX_FG", "d8dee9"), ("GLYPH_FAMILY", "banner")])));
        assert!(
            !step_palette_ok(&m(&[("HEX_FG", "d8dee9"), ("GLYPH_FAMILY", "runes")])),
            "a family it does not know"
        );
        assert!(!step_palette_ok(&m(&[("HEX_FG", "star")])), "a family's name is no color");
        assert!(!step_palette_ok(&m(&[("HEX_FG", "#d8dee9")])));
    }
}
