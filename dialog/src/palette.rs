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

impl Palette {
    /// From a lookup (the environment, or a test's table); a key that is
    /// missing or not a color takes the dark default.
    pub fn from(get: impl Fn(&str) -> Option<String>) -> Palette {
        let c = |k: &str, d: &str| get(k).and_then(|v| hex(&v)).unwrap_or_else(|| hex(d).unwrap());
        let surface = c("PANEL_BG", "1f1f1f");
        Palette {
            fg: c("HEX_FG", "aaaaaa"),
            accent: c("HEX_ACCENT", "5555ff"),
            muted: c("PANEL_MUTED", "7f7f7f"),
            surface,
            lit: c("PANEL_HI", "333333"),
            alarm: c("HEX_ANSI_1", "aa0000"),
            ok: c("HEX_ANSI_2", "00aa00"),
            dark: luma(surface) < 128,
        }
    }

    /// The same palette drawn in the terminal's own slots (#34): spark-shell's foot.ini gives 16 to 20
    /// the accent, the muted color, the surface, the lit row and the quiet text, and a new look sends
    /// them to the open windows, so a cell drawn in a slot changes color in place, with no redraw.
    pub fn slots(self) -> Palette {
        Palette {
            fg: Color::Reset,
            accent: Color::Indexed(16),
            muted: Color::Indexed(20),
            surface: Color::Indexed(18),
            lit: Color::Indexed(19),
            alarm: Color::Indexed(1),
            ok: Color::Indexed(2),
            dark: self.dark,
        }
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

/// The window's foot.ini sets the five slots: spark-shell says so in the environment.
pub fn slots_here() -> bool {
    std::env::var("SPARK_DIALOG_SLOTS").as_deref() == Ok("1")
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn in_slots_every_color_is_a_slot_and_dark_stays_the_palettes() {
        let p = Palette::from(|k| (k == "PANEL_BG").then(|| "fdf6e3".into())).slots();
        assert_eq!(
            (p.accent, p.muted, p.surface, p.lit),
            (Color::Indexed(16), Color::Indexed(20), Color::Indexed(18), Color::Indexed(19))
        );
        assert_eq!((p.fg, p.alarm, p.ok), (Color::Reset, Color::Indexed(1), Color::Indexed(2)));
        assert!(!p.dark, "a light surface is still light");
    }
}
