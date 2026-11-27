//! The look as spark-shell last set it, for a home that stands open while it changes (v0.172). spark-shell writes
//! the colors, the glyph family and the text's font to $XDG_RUNTIME_DIR/spark-shell-dialog.look, whole, at each
//! change of the look; the dialog reads the file when its time changes. A theme picked in home came with its
//! step's answer, colors only; one set at the prompt, by a key or from another home reached no open home, which
//! kept the old colors and the old typeface until it was closed and opened.
use serde_json::{Map, Value};
use std::path::PathBuf;
use std::time::SystemTime;

/// The most the file may hold, and the most lines read of it: twenty colors, a family and a font fit many times.
const MOST: u64 = 64 * 1024;
const LINES: usize = 64;

/// The file: the runtime folder, else spark-shell's state folder, as spark-shell picks it.
pub fn path() -> Option<PathBuf> {
    std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("XDG_STATE_HOME")
                .filter(|d| !d.is_empty())
                .map(PathBuf::from)
                .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))
                .map(|s| s.join("spark-shell"))
        })
        .map(|d| d.join("spark-shell-dialog.look"))
}

/// A look read from the file: the colors and the family as a theme step's answer has them, and the font's words.
#[derive(Clone, Debug, PartialEq)]
pub struct Look {
    pub palette: Map<String, Value>,
    pub font: Option<String>,
    /// The dialog's opening and closing, as a theme step's answer names them: a folder, `draw:` and a piece, or
    /// nothing for none. None where the file has no such line.
    pub transitions: Option<String>,
}

/// The lines of a look: KEY=VALUE, a color six hex digits (a leading # let go), the family a word, the font plain
/// words. A line that is none of these is left out; a file with no color is no look.
pub fn parse(text: &str) -> Option<Look> {
    let mut palette = Map::new();
    let (mut font, mut transitions) = (None, None);
    for line in text.lines().take(LINES) {
        let Some((key, value)) = line.split_once('=') else { continue };
        let value = value.trim();
        let color = matches!(key, "HEX_FG" | "HEX_ACCENT" | "PANEL_MUTED" | "PANEL_BG" | "PANEL_HI" | "PANEL_BAND")
            || key
                .strip_prefix("HEX_ANSI_")
                .is_some_and(|n| n.bytes().all(|b| b.is_ascii_digit()) && (n == "0" || !n.starts_with('0')) && n.parse::<u8>().is_ok_and(|v| v < 16));
        if color {
            let digits = value.trim_start_matches('#');
            if spark_theme::hex_digits(digits).is_some() {
                palette.insert(key.to_string(), Value::String(digits.to_ascii_lowercase()));
            }
        } else if key == "GLYPH_FAMILY" {
            if crate::glyphs::Glyphs::named(value).is_some() {
                palette.insert(key.to_string(), Value::String(value.to_string()));
            }
        } else if key == "TRANSITIONS" {
            if value.is_empty() || crate::app::transitions_ok(value) {
                transitions = Some(value.to_string());
            }
        } else if key == "FONT" && !value.is_empty() && value.len() <= 120 && value.chars().all(|c| c.is_ascii_alphanumeric() || " -_.,".contains(c)) {
            font = Some(value.to_string());
        }
    }
    let colors = palette.keys().any(|k| k != "GLYPH_FAMILY");
    (colors && crate::palette::step_palette_ok(&palette)).then_some(Look { palette, font, transitions })
}

/// The file watched by its time: nothing is read while it stands as it stood.
#[derive(Debug, Default)]
pub struct Watch {
    file: Option<PathBuf>,
    seen: Option<SystemTime>,
}

impl Watch {
    /// The file as it stands when the dialog starts is the look it started in: only a later one is new.
    pub fn new(file: Option<PathBuf>) -> Watch {
        let seen = file.as_ref().and_then(|f| std::fs::metadata(f).and_then(|m| m.modified()).ok());
        Watch { file, seen }
    }

    /// The look, when the file changed since it was last seen and holds one.
    pub fn changed(&mut self) -> Option<Look> {
        let file = self.file.as_ref()?;
        let meta = std::fs::metadata(file).ok()?;
        let made = meta.modified().ok();
        if made == self.seen {
            return None;
        }
        self.seen = made;
        if !meta.is_file() || meta.len() > MOST {
            return None;
        }
        parse(&std::fs::read_to_string(file).ok()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_look_is_colors_a_family_and_a_font_and_nothing_else() {
        let look = parse("HEX_FG=d8dee9\nHEX_ACCENT=#88C0D0\nPANEL_BG=2e3440\nHEX_ANSI_4=81a1c1\nGLYPH_FAMILY=star\nFONT=Monaspace Krypton 12\nHOME=/x\nHEX_ANSI_16=ffffff\nHEX_ANSI_+1=ffffff\n").unwrap();
        assert_eq!(look.palette.get("HEX_FG").and_then(Value::as_str), Some("d8dee9"));
        assert_eq!(
            look.palette.get("HEX_ACCENT").and_then(Value::as_str),
            Some("88c0d0"),
            "a # is let go, as the launcher's colors have none"
        );
        assert_eq!(look.palette.get("GLYPH_FAMILY").and_then(Value::as_str), Some("star"));
        assert_eq!(look.font.as_deref(), Some("Monaspace Krypton 12"));
        assert_eq!(look.transitions, None, "no line: the dialog keeps the one it has");
        let moved = parse("PANEL_BG=101010\nTRANSITIONS=draw:moon\n").unwrap();
        assert_eq!(moved.transitions.as_deref(), Some("draw:moon"));
        assert_eq!(parse("PANEL_BG=101010\nTRANSITIONS=\n").unwrap().transitions.as_deref(), Some(""), "none");
        assert_eq!(
            parse("PANEL_BG=101010\nTRANSITIONS=../x\n").unwrap().transitions,
            None,
            "no path that is not whole"
        );
        assert!(!look.palette.contains_key("HOME") && !look.palette.contains_key("HEX_ANSI_16") && !look.palette.contains_key("HEX_ANSI_+1"));
        assert!(crate::palette::step_palette_ok(&look.palette), "what a theme step's answer may carry");
        // a color that is none, a family nobody drew and a font with an escape are left out, the rest kept
        let look = parse("HEX_FG=red\nPANEL_BG=101010\nGLYPH_FAMILY=runes\nFONT=Mono\u{1b}[31m 12\n").unwrap();
        assert_eq!(look.palette.len(), 1);
        assert_eq!(look.font, None);
        assert_eq!(parse("GLYPH_FAMILY=star\nFONT=Mono 12\n"), None, "no color: no look");
        assert_eq!(parse(""), None);
    }

    #[test]
    fn the_file_is_read_when_its_time_changes_and_only_then() {
        let dir = std::env::temp_dir().join(format!("spark-dialog-look-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("spark-shell-dialog.look");
        std::fs::write(&file, "HEX_FG=111111\n").unwrap();
        let mut w = Watch::new(Some(file.clone()));
        assert_eq!(w.changed(), None, "the look the dialog started in is not a new one");
        let later = SystemTime::now() + std::time::Duration::from_secs(5);
        std::fs::write(&file, "HEX_FG=222222\nFONT=Mono 14\n").unwrap();
        std::fs::File::options().write(true).open(&file).unwrap().set_modified(later).unwrap();
        let look = w.changed().expect("a later file is a new look");
        assert_eq!(look.palette.get("HEX_FG").and_then(Value::as_str), Some("222222"));
        assert_eq!(look.font.as_deref(), Some("Mono 14"));
        assert_eq!(w.changed(), None, "read once");
        let mut none = Watch::new(Some(dir.join("absent")));
        assert_eq!(none.changed(), None);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
