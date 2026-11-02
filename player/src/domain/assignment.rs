//! Which loop plays on which screen: one loop on every screen (--all), or
//! a loop per named screen (--screen NAME=FILE). A screen with no loop
//! gets no surface.

use super::{Error, Loop};

#[derive(Clone, Debug, PartialEq)]
pub enum Assignment {
    /// The same loop on every screen, the ones plugged in later too.
    All(Loop),
    /// A loop per screen, by sway's name for it.
    Screens(Vec<(String, Loop)>),
}

impl Assignment {
    /// The assignment from the command line's --all FILE or its
    /// --screen NAME=FILE values; one of the two, never both.
    pub fn from_args(all: Option<&str>, screens: &[&str]) -> Result<Assignment, Error> {
        match (all, screens.is_empty()) {
            (Some(_), false) => Err(Error::AllAndScreens),
            (Some(path), true) => Ok(Assignment::All(Loop::new(path)?)),
            (None, true) => Err(Error::NoLoop),
            (None, false) => {
                let mut pairs: Vec<(String, Loop)> = Vec::with_capacity(screens.len());
                for spec in screens {
                    let (name, path) = spec.split_once('=').ok_or_else(|| Error::ScreenSpec((*spec).to_owned()))?;
                    if name.is_empty() || path.is_empty() {
                        return Err(Error::ScreenSpec((*spec).to_owned()));
                    }
                    if pairs.iter().any(|(n, _)| n == name) {
                        return Err(Error::TwoLoops(name.to_owned()));
                    }
                    pairs.push((name.to_owned(), Loop::new(path)?));
                }
                Ok(Assignment::Screens(pairs))
            }
        }
    }

    /// The loop the screen plays, if it has one.
    pub fn loop_for(&self, screen: &str) -> Option<&Loop> {
        match self {
            Assignment::All(l) => Some(l),
            Assignment::Screens(pairs) => pairs.iter().find(|(name, _)| name == screen).map(|(_, l)| l),
        }
    }

    /// Every loop asked for (to check its file is there before playing).
    pub fn loops(&self) -> Vec<&Loop> {
        match self {
            Assignment::All(l) => vec![l],
            Assignment::Screens(pairs) => pairs.iter().map(|(_, l)| l).collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn all_plays_one_loop_on_every_screen() {
        let a = Assignment::from_args(Some("/c/sea.mp4"), &[]).unwrap();
        assert_eq!(a.loop_for("DP-3").unwrap().path(), Path::new("/c/sea.mp4"));
        assert_eq!(a.loop_for("HDMI-A-1").unwrap().path(), Path::new("/c/sea.mp4"));
        assert_eq!(a.loops().len(), 1);
    }

    #[test]
    fn screens_play_their_own_loops_and_others_get_none() {
        let a = Assignment::from_args(None, &["DP-3=/c/sea.mp4", "HDMI-A-1=/c/rain.mp4"]).unwrap();
        assert_eq!(a.loop_for("DP-3").unwrap().path(), Path::new("/c/sea.mp4"));
        assert_eq!(a.loop_for("HDMI-A-1").unwrap().path(), Path::new("/c/rain.mp4"));
        assert_eq!(a.loop_for("eDP-1"), None);
        assert_eq!(a.loops().len(), 2);
    }

    #[test]
    fn a_file_may_hold_an_equals_sign() {
        let a = Assignment::from_args(None, &["DP-3=/c/a=b.mp4"]).unwrap();
        assert_eq!(a.loop_for("DP-3").unwrap().path(), Path::new("/c/a=b.mp4"));
    }

    #[test]
    fn a_screen_value_needs_a_name_and_a_file() {
        for spec in ["DP-3", "=/c/sea.mp4", "DP-3="] {
            assert_eq!(Assignment::from_args(None, &[spec]), Err(Error::ScreenSpec(spec.into())), "{spec}");
        }
    }

    #[test]
    fn a_screen_takes_one_loop() {
        let e = Assignment::from_args(None, &["DP-3=/c/a.mp4", "DP-3=/c/b.mp4"]);
        assert_eq!(e, Err(Error::TwoLoops("DP-3".into())));
    }

    #[test]
    fn all_and_screens_do_not_mix() {
        assert_eq!(Assignment::from_args(Some("/c/a.mp4"), &["DP-3=/c/b.mp4"]), Err(Error::AllAndScreens));
    }

    #[test]
    fn some_loop_is_needed() {
        assert_eq!(Assignment::from_args(None, &[]), Err(Error::NoLoop));
        assert_eq!(Assignment::from_args(Some(""), &[]), Err(Error::EmptyPath));
    }
}
