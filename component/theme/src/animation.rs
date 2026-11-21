//! RGB colors for artwork, from the launched panel or a gallery palette.

use crate::{hex, mix, Rgb};

// The terminal defaults used by spark-shell and the gallery artwork.
const ANSI: [Rgb; 16] = [
    [0x24, 0x24, 0x24],
    [0xf6, 0x2b, 0x5a],
    [0x47, 0xb4, 0x13],
    [0xe3, 0xc4, 0x01],
    [0x24, 0xac, 0xd4],
    [0xf2, 0xaf, 0xfd],
    [0x13, 0xc2, 0x99],
    [0xe6, 0xe6, 0xe6],
    [0x61, 0x61, 0x61],
    [0xff, 0x4d, 0x51],
    [0x35, 0xd4, 0x50],
    [0xe9, 0xe8, 0x36],
    [0x5d, 0xc5, 0xf8],
    [0xfe, 0xab, 0xf2],
    [0x24, 0xdf, 0xc4],
    [0xff, 0xff, 0xff],
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Colors {
    pub surface: Rgb,
    pub fg: Rgb,
    pub muted: Rgb,
    pub accent: Rgb,
    pub ansi: [Rgb; 16],
}

impl Colors {
    /// The launcher supplies the first four colors. Missing ANSI entries use the terminal defaults.
    pub fn from_panel(get: impl Fn(&str) -> Option<String>) -> Option<Self> {
        let read = |k: &str| get(k).and_then(|v| hex(&v));
        Some(Self {
            surface: read("PANEL_BG")?,
            fg: read("HEX_FG")?,
            muted: read("PANEL_MUTED")?,
            accent: read("HEX_ACCENT")?,
            ansi: std::array::from_fn(|i| read(&format!("HEX_ANSI_{i}")).unwrap_or(ANSI[i])),
        })
    }

    /// Resolve artwork from THEME_* values, including older quoted values and missing slots.
    pub fn from_theme(get: impl Fn(&str) -> Option<String>) -> Self {
        let read = |k: &str| get(k).and_then(|v| hex(v.trim_matches(['"', '\''])));
        let ansi = std::array::from_fn(|i| read(&format!("THEME_ANSI_{i}")).unwrap_or(ANSI[i]));
        let bg = read("THEME_BG").unwrap_or([0x24; 3]);
        let fg = read("THEME_FG").unwrap_or([0xff; 3]);
        let surface = mix(bg, fg, 9);
        let muted = read("THEME_MUTED").unwrap_or(ansi[8]);
        // panel_load starts at 35% and raises the quiet text in steps of five to 4.5:1 or the foreground.
        let mut percent = 35;
        let mut quiet = mix(muted, fg, percent);
        while percent < 100 && contrast(quiet, surface) < 450 {
            percent += 5;
            quiet = mix(muted, fg, percent);
        }
        Self {
            surface,
            fg,
            muted: quiet,
            accent: read("THEME_ACCENT").unwrap_or(ansi[4]),
            ansi,
        }
    }
}

/// The shell's hex_contrast, as a ratio times 100.
fn contrast(a: Rgb, b: Rgb) -> u32 {
    let luminance = |color: Rgb| {
        let [r, g, b] = color.map(|v| {
            let v = f64::from(v) / 255.0;
            if v <= 0.03928 {
                v / 12.92
            } else {
                ((v + 0.055) / 1.055).powf(2.4)
            }
        });
        0.2126 * r + 0.7152 * g + 0.0722 * b
    };
    let (x, y) = (luminance(a), luminance(b));
    ((x.max(y) + 0.05) / (x.min(y) + 0.05) * 100.0) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artwork_uses_the_selected_ansi_slots_for_missing_source_roles() {
        let colors = Colors::from_theme(|key| match key {
            "THEME_ANSI_4" => Some("\"#AAbbCC\"".into()),
            "THEME_ANSI_8" => Some("'#f0f0f0'".into()),
            "THEME_MUTED" => Some("broken".into()),
            _ => None,
        });
        assert_eq!(colors.accent, [0xaa, 0xbb, 0xcc]);
        assert_eq!(colors.surface, [0x37; 3]);
        assert_eq!(colors.muted, [0xf5; 3]);
        assert_eq!(colors.ansi[0], ANSI[0]);
        assert!(Colors::from_panel(|_| None).is_none());
    }
}
