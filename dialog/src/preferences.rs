//! Literal presentation preferences shared with spark-shell's config.

#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub struct Preferences {
    pub twelve: bool,
    pub monday: bool,
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
    }
}
