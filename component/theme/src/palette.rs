//! Panel colors as RGB values or the live slots in a spark-shell terminal.

use crate::{dark_ground, mix, Rgb};

/// A color: the surface's own (Reset), one of the palette's slots by its number, or a red, green and blue.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum Color {
    #[default]
    Reset,
    Indexed(u8),
    Rgb(u8, u8, u8),
}

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

/// A launcher color in the form used by the native and terminal renderers.
pub fn hex(s: &str) -> Option<Color> {
    crate::hex(s).map(Color::from)
}

impl From<Rgb> for Color {
    fn from([r, g, b]: Rgb) -> Self {
        Self::Rgb(r, g, b)
    }
}

impl Palette {
    /// Resolve the launcher's keys independently, falling back for missing and malformed colors.
    pub fn from(get: impl Fn(&str) -> Option<String>) -> Palette {
        let read = |k: &str| get(k).and_then(|v| crate::hex(&v));
        let surface = read("PANEL_BG").unwrap_or([0x1f; 3]);
        let accent = read("HEX_ACCENT").unwrap_or([0x55, 0x55, 0xff]);
        let band = read("PANEL_BAND").unwrap_or_else(|| mix(surface, accent, 25));
        let [r, g, b] = surface;
        Palette {
            fg: read("HEX_FG").unwrap_or([0xaa; 3]).into(),
            accent: accent.into(),
            muted: read("PANEL_MUTED").unwrap_or([0x7f; 3]).into(),
            surface: surface.into(),
            lit: read("PANEL_HI").unwrap_or([0x33; 3]).into(),
            band: band.into(),
            alarm: read("HEX_ANSI_1").unwrap_or([0xaa, 0, 0]).into(),
            ok: read("HEX_ANSI_2").unwrap_or([0, 0xaa, 0]).into(),
            dark: dark_ground(r, g, b),
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

/// The window's foot.ini sets the extra slots: spark-shell says so in the environment.
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
}
