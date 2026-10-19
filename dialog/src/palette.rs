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
            dark: luma(surface) < 128,
        }
    }

    pub fn from_env() -> Palette {
        Palette::from(|k| std::env::var(k).ok())
    }
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
}
