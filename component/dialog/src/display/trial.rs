//! A change of a screen on trial (v0.167): a resolution, a scale or a turn the desktop wears now and puts back by
//! itself unless it is kept. The desktop's own clock puts it back, whatever happens to this dialog; the card here says
//! what changed, counts the same seconds down and offers the two steps. The clock is handed in: nothing here waits.

use crate::model::{self, Call};
use crate::scrub::{cells, scrub};
use serde_json::Value;
use std::time::{Duration, Instant};

/// The longest a trial runs, in seconds: a longer one is no trial.
const LONGEST: u64 = 120;

#[derive(Clone, Debug, PartialEq)]
pub struct Trial {
    /// The provider whose change it is: its own steps alone end it.
    pub prov: usize,
    /// What changed, in a few words ("1280x720").
    pub said: String,
    pub keep: Call,
    pub back: Call,
    until: Instant,
}

impl Trial {
    /// The trial a step's result carries, from `now`; none where any part of it is not in its shape.
    pub fn read(result: &Value, prov: usize, now: Instant) -> Option<Trial> {
        let v = result.get("trial")?;
        let said = scrub(v.get("said")?.as_str()?);
        let seconds = v.get("seconds")?.as_u64()?;
        if said.trim().is_empty() || cells(&said) > 40 || said.len() > 160 || seconds == 0 || seconds > LONGEST {
            return None;
        }
        Some(Trial {
            prov,
            said,
            keep: model::call(v.get("keep")?)?,
            back: model::call(v.get("back")?)?,
            until: now + Duration::from_secs(seconds),
        })
    }

    /// The seconds left, the one under way counted: nothing once it has ended.
    pub fn left(&self, now: Instant) -> u64 {
        let left = self.until.saturating_duration_since(now);
        left.as_secs() + u64::from(left.subsec_nanos() > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn result() -> Value {
        json!({"trial": {"said": "1280x720", "seconds": 15,
            "keep": {"name": "display_keep", "arguments": {"screen": "DP-3"}},
            "back": {"name": "display_back", "arguments": {"screen": "DP-3"}}}})
    }

    #[test]
    fn the_seconds_count_down_by_the_clock_handed_in() {
        let t0 = Instant::now();
        let t = Trial::read(&result(), 3, t0).unwrap();
        assert_eq!(
            (t.prov, t.said.as_str(), t.keep.name.as_str(), t.back.name.as_str()),
            (3, "1280x720", "display_keep", "display_back")
        );
        assert_eq!(t.keep.arguments["screen"], json!("DP-3"));
        let at = |ms: u64| t.left(t0 + Duration::from_millis(ms));
        assert_eq!(
            [at(0), at(1), at(1000), at(13_999), at(14_000), at(14_999), at(15_000), at(99_000)],
            [15, 15, 14, 2, 1, 1, 0, 0]
        );
    }

    #[test]
    fn a_trial_in_any_other_shape_is_none() {
        let t0 = Instant::now();
        let with = |k: &str, v: Value| {
            let mut r = result();
            r["trial"][k] = v;
            Trial::read(&r, 0, t0)
        };
        for (k, v) in [
            ("said", json!("")),
            ("said", json!("  ")),
            ("said", json!(7)),
            ("said", json!("x".repeat(41))),
            ("said", json!(format!("a{}", "\u{301}".repeat(200)))),
            ("seconds", json!(0)),
            ("seconds", json!(121)),
            ("seconds", json!(-1)),
            ("seconds", json!(15.5)),
            ("seconds", json!("15")),
            ("seconds", json!(u64::MAX)),
            ("keep", json!(null)),
            ("keep", json!({"name": "Display Keep"})),
            ("back", json!("display_back")),
            ("back", json!({})),
        ] {
            assert_eq!(with(k, v.clone()), None, "{k}: {v}");
        }
        for v in [json!({}), json!({"trial": null}), json!({"trial": []}), json!({"trial": "15"}), json!(null)] {
            assert_eq!(Trial::read(&v, 0, t0), None, "{v}");
        }
        assert_eq!(with("said", json!("1280\u{1b}[2Jx720")).unwrap().said, "1280[2Jx720", "scrubbed");
    }
}
