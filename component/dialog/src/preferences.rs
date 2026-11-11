//! Literal presentation preferences shared with spark-shell's config.

/// The room around the apps where they wear their icons (#232): none, around the categories' headings, or
/// between the apps' rows too. DIALOG_SPACING in the config; groups when the line is absent.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Spacing {
    None,
    #[default]
    Groups,
    Rows,
}

#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub struct Preferences {
    pub twelve: bool,
    pub monday: bool,
    /// DIALOG_ICONS=off: the apps listed without their icons (#230). On when the line is absent.
    pub icons_off: bool,
    pub spacing: Spacing,
}

impl Preferences {
    pub fn parse(text: &str) -> Self {
        let mut p = Self::default();
        for line in text.lines() {
            match line.trim() {
                "CLOCK_FORMAT=12" => p.twelve = true,
                "CLOCK_FORMAT=24" => p.twelve = false,
                "WEEK_START=monday" => p.monday = true,
                "WEEK_START=sunday" => p.monday = false,
                "DIALOG_ICONS=off" => p.icons_off = true,
                "DIALOG_ICONS=on" => p.icons_off = false,
                "DIALOG_SPACING=none" => p.spacing = Spacing::None,
                "DIALOG_SPACING=groups" => p.spacing = Spacing::Groups,
                "DIALOG_SPACING=rows" => p.spacing = Spacing::Rows,
                _ => {}
            }
        }
        p
    }
}

pub fn read() -> Preferences {
    let dir = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")));
    dir.and_then(|d| std::fs::read_to_string(d.join("spark-shell/config")).ok())
        .map(|s| Preferences::parse(&s))
        .unwrap_or_default()
}

/// localtime_r may cache the native zone until tzset is called.
pub fn refresh_zone() {
    unsafe extern "C" {
        fn tzset();
    }
    unsafe {
        tzset();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_literal_preferences_are_read_and_the_last_one_wins() {
        let p = Preferences::parse("CLOCK_FORMAT=12\nWEEK_START=monday\nCLOCK_FORMAT=24\nUNKNOWN=yes\n");
        assert!(!p.twelve);
        assert!(p.monday);
        assert!(!Preferences::parse("CLOCK_FORMAT=$(echo 12)\nWEEK_START=other").twelve);
        // icons are on unless the config says off (#230)
        assert!(!Preferences::parse("").icons_off);
        assert!(Preferences::parse("DIALOG_ICONS=off\n").icons_off);
        assert!(!Preferences::parse("DIALOG_ICONS=off\nDIALOG_ICONS=on\n").icons_off);
        assert!(!Preferences::parse("DIALOG_ICONS=no\n").icons_off);
        // the room around the apps: groups unless the config says none or rows
        assert_eq!(Preferences::parse("").spacing, Spacing::Groups);
        assert_eq!(Preferences::parse("DIALOG_SPACING=rows\n").spacing, Spacing::Rows);
        assert_eq!(Preferences::parse("DIALOG_SPACING=none\n").spacing, Spacing::None);
        assert_eq!(Preferences::parse("DIALOG_SPACING=lots\n").spacing, Spacing::Groups);
    }
}
