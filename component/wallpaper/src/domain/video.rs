//! What plays: a loop (a video file played over and over) and how it is
//! scaled to fill a screen.

use super::Error;
use std::path::{Path, PathBuf};

/// A video file played over and over as a screen's wallpaper.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Loop {
    path: PathBuf,
}

impl Loop {
    pub fn new(path: &str) -> Result<Loop, Error> {
        if path.is_empty() {
            return Err(Error::EmptyPath);
        }
        Ok(Loop { path: PathBuf::from(path) })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

/// How a loop's pixels grow or shrink to the screen's.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Scaling {
    /// Filtered, for film and renders.
    #[default]
    Smooth,
    /// Each pixel a sharp block, for pixel art.
    Nearest,
}

impl Scaling {
    pub fn parse(value: &str) -> Result<Scaling, Error> {
        match value {
            "smooth" => Ok(Scaling::Smooth),
            "nearest" => Ok(Scaling::Nearest),
            _ => Err(Error::Scaling(value.to_owned())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_loop_keeps_its_path() {
        let l = Loop::new("/srv/cache/spark-shell/motion/sea.mp4").unwrap();
        assert_eq!(l.path(), Path::new("/srv/cache/spark-shell/motion/sea.mp4"));
    }

    #[test]
    fn a_loop_needs_a_path() {
        assert_eq!(Loop::new(""), Err(Error::EmptyPath));
    }

    #[test]
    fn scaling_reads_its_two_words() {
        assert_eq!(Scaling::parse("smooth"), Ok(Scaling::Smooth));
        assert_eq!(Scaling::parse("nearest"), Ok(Scaling::Nearest));
        assert_eq!(Scaling::default(), Scaling::Smooth);
    }

    #[test]
    fn scaling_refuses_any_other_word() {
        assert_eq!(Scaling::parse("bilinear"), Err(Error::Scaling("bilinear".into())));
        assert_eq!(Scaling::parse("Nearest"), Err(Error::Scaling("Nearest".into())));
    }
}
