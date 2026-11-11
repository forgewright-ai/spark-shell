//! The palette spark-shell hands the dialog in the environment: every
//! color a slot of the palette, never one of the dialog's own.

use ratatui::style::Color;

#[derive(Clone, Debug, PartialEq)]
pub struct Palette {
    pub fg: Color,
    pub accent: Color,
    pub muted: Color,
    pub surface: Color,
    pub lit: Color,
    /// The header's band (the dialog design notes, v0.124.5): the accent at a quarter over the surface.
    pub band: Color,
    pub alarm: Color,
    /// A good state: the login's ready dot.
    pub ok: Color,
    pub dark: bool,
}

/// rrggbb (or #rrggbb) as a color; None for anything else.
pub fn hex(s: &str) -> Option<Color> {
    let s = s.trim().trim_start_matches('#');
    if s.len() != 6 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let v = u32::from_str_radix(s, 16).ok()?;
    Some(Color::Rgb((v >> 16) as u8, (v >> 8) as u8, v as u8))
}

fn luma(c: Color) -> u32 {
    match c {
        Color::Rgb(r, g, b) => (299 * r as u32 + 587 * g as u32 + 114 * b as u32) / 1000,
        _ => 0,
    }
}

/// `a` moved `pct` of the way to `b`, channel by channel, as spark-shell's hex_mix does it (whole
/// numbers, the remainder dropped), so the dialog and the launcher derive the same shade; a color
/// that is no RGB stays `a`.
fn mix(a: Color, b: Color, pct: i32) -> Color {
    match (a, b) {
        (Color::Rgb(r1, g1, b1), Color::Rgb(r2, g2, b2)) => {
            let m = |x: u8, y: u8| (x as i32 + (y as i32 - x as i32) * pct / 100) as u8;
            Color::Rgb(m(r1, r2), m(g1, g2), m(b1, b2))
        }
        _ => a,
    }
}

impl Palette {
    /// From a lookup (the environment, or a test's table); a key that is
    /// missing or not a color takes the dark default.
    pub fn from(get: impl Fn(&str) -> Option<String>) -> Palette {
        let c = |k: &str, d: &str| get(k).and_then(|v| hex(&v)).unwrap_or_else(|| hex(d).unwrap());
        let surface = c("PANEL_BG", "1f1f1f");
        let accent = c("HEX_ACCENT", "5555ff");
        // the band is spark-shell's PANEL_BAND; a launcher without it (or a test's table) gets the same derivation
        let band = get("PANEL_BAND").and_then(|v| hex(&v)).unwrap_or_else(|| mix(surface, accent, 25));
        Palette {
            fg: c("HEX_FG", "aaaaaa"),
            accent,
            muted: c("PANEL_MUTED", "7f7f7f"),
            surface,
            lit: c("PANEL_HI", "333333"),
            band,
            alarm: c("HEX_ANSI_1", "aa0000"),
            ok: c("HEX_ANSI_2", "00aa00"),
            dark: luma(surface) < 128,
        }
    }

    /// The same palette drawn in the terminal's own slots (#34): spark-shell's foot.ini gives 16 to 21
    /// the accent, the muted color, the surface, the lit row, the quiet text and the header's band, and
    /// a new look sends them to the open windows, so a cell drawn in a slot changes color in place, with
    /// no redraw.
    pub fn slots(self) -> Palette {
        Palette {
            fg: Color::Reset,
            accent: Color::Indexed(16),
            muted: Color::Indexed(20),
            surface: Color::Indexed(18),
            lit: Color::Indexed(19),
            band: Color::Indexed(21),
            alarm: Color::Indexed(1),
            ok: Color::Indexed(2),
            dark: self.dark,
        }
    }

    /// A picture's ramp in this palette (#156): the ground, the muted color, the accent, the text color, as colors. A
    /// palette drawn in slots has none (a slot is no color a picture can hold): keep the palette as it came for this.
    pub fn ramp(&self) -> Option<[[u8; 3]; 4]> {
        let rgb = |c: Color| match c {
            Color::Rgb(r, g, b) => Some([r, g, b]),
            _ => None,
        };
        Some([rgb(self.surface)?, rgb(self.muted)?, rgb(self.accent)?, rgb(self.fg)?])
    }

    /// The environment's palette; in slots where spark-shell says the window has them (SPARK_DIALOG_SLOTS=1).
    pub fn from_env() -> Palette {
        let p = Palette::from(|k| std::env::var(k).ok());
        if slots_here() {
            p.slots()
        } else {
            p
        }
    }
}

/// A palette a theme's step hands the dialog (#183): plain colors, rrggbb or empty, and the glyph family by its
/// name (#248). Anything else and the dialog wears none of it.
pub fn step_palette_ok(p: &serde_json::Map<String, serde_json::Value>) -> bool {
    p.iter().all(|(k, v)| {
        v.as_str().is_some_and(|s| {
            s.is_empty() || (s.len() == 6 && s.bytes().all(|b| b.is_ascii_hexdigit())) || (k == "GLYPH_FAMILY" && crate::glyphs::Glyphs::named(s).is_some())
        })
    })
}

/// The window's foot.ini sets the five slots: spark-shell says so in the environment.
pub fn slots_here() -> bool {
    std::env::var("SPARK_DIALOG_SLOTS").as_deref() == Ok("1")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pictures_ramp_is_colors_never_slots() {
        // #156: on the desktop the dialog draws in slots, and a slot is no color: a ramp of slots was four grays, the
        // spectrogram one flat block; the ramp comes from the palette as colors, and a slots palette has none
        let p = Palette::from(|k| match k {
            "PANEL_BG" => Some("184956".into()),
            "PANEL_MUTED" => Some("72898f".into()),
            "HEX_ACCENT" => Some("4695f7".into()),
            "HEX_FG" => Some("adbcbc".into()),
            _ => None,
        });
        assert_eq!(p.ramp(), Some([[0x18, 0x49, 0x56], [0x72, 0x89, 0x8f], [0x46, 0x95, 0xf7], [0xad, 0xbc, 0xbc]]));
        assert_eq!(p.clone().slots().ramp(), None);
    }

    #[test]
    fn colors_come_from_the_keys() {
        let p = Palette::from(|k| match k {
            "PANEL_BG" => Some("fdf6e3".into()),
            "HEX_ACCENT" => Some("#268bd2".into()),
            "HEX_FG" => Some("nonsense".into()),
            _ => None,
        });
        assert_eq!(p.surface, Color::Rgb(0xfd, 0xf6, 0xe3));
        assert_eq!(p.accent, Color::Rgb(0x26, 0x8b, 0xd2));
        assert_eq!(p.fg, Color::Rgb(0xaa, 0xaa, 0xaa));
        assert!(!p.dark);
    }

    #[test]
    fn the_band_is_the_accent_at_a_quarter_over_the_surface_unless_the_key_says_otherwise() {
        // the dialog design notes (v0.124.5): the header's band is PANEL_BAND, which spark-shell derives as the accent at a
        // quarter over the surface (hex_mix PANEL_BG HEX_ACCENT 25, integer arithmetic); without the key the dialog
        // derives the same, so a test's palette and an old launcher draw the same band; in slots it is the 22nd
        let p = Palette::from(|k| match k {
            "PANEL_BG" => Some("393834".into()),
            "HEX_ACCENT" => Some("fe8019".into()),
            _ => None,
        });
        assert_eq!(p.band, Color::Rgb(0x6a, 0x4a, 0x2e));
        let q = Palette::from(|k| (k == "PANEL_BAND").then(|| "112233".into()));
        assert_eq!(q.band, Color::Rgb(0x11, 0x22, 0x33));
        assert_eq!(p.slots().band, Color::Indexed(21));
    }

    #[test]
    fn in_slots_every_color_is_a_slot_and_dark_stays_the_palettes() {
        let p = Palette::from(|k| (k == "PANEL_BG").then(|| "fdf6e3".into())).slots();
        assert_eq!(
            (p.accent, p.muted, p.surface, p.lit),
            (Color::Indexed(16), Color::Indexed(20), Color::Indexed(18), Color::Indexed(19))
        );
        assert_eq!((p.fg, p.alarm, p.ok), (Color::Reset, Color::Indexed(1), Color::Indexed(2)));
        assert!(!p.dark, "a light surface is still light");
    }

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
