pub use spark_theme::glyphs::*;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stone_is_todays_set() {
        // the signs the dialog drew before the families, and the bar's gauge pair (#248)
        assert_eq!((STONE.model_on, STONE.model_off), ("\u{25c6}", "\u{25c7}"));
        assert_eq!((STONE.dot, STONE.ring, STONE.opens), (crate::ui::DOT, crate::ui::RING, "\u{25b8}"));
        assert_eq!((STONE.gauge_on, STONE.gauge_off), ("\u{25b0}", "\u{25b1}"));
    }
}
