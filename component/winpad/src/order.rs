//! The order the windows were focused in, pure: sway's own stacks to start from, each focus after, and
//! the walk Super+Tab takes through it.

use crate::tree::kids;
use serde_json::Value;
use std::time::{Duration, Instant};

/// The views in sight, in the order sway's focus stacks give them, the latest first; none from the pad.
pub fn in_sight(tree: &Value) -> Vec<i64> {
    fn walk(n: &Value, out: &mut Vec<i64>) {
        if n["type"] == "workspace" && n["name"] == "__i3_scratch" {
            return;
        }
        if kids(n).next().is_none() {
            if n["type"] == "con" || n["type"] == "floating_con" {
                if let Some(id) = n["id"].as_i64() {
                    out.push(id);
                }
            }
            return;
        }
        let order: Vec<i64> = n["focus"].as_array().into_iter().flatten().filter_map(Value::as_i64).collect();
        for &id in &order {
            if let Some(k) = kids(n).find(|k| k["id"].as_i64() == Some(id)) {
                walk(k, out);
            }
        }
        for k in kids(n).filter(|k| !k["id"].as_i64().is_some_and(|id| order.contains(&id))) {
            walk(k, out);
        }
    }
    let mut out = vec![];
    walk(tree, &mut out);
    out
}

/// The windows in the order they were focused in, the latest first, and a walk through it: Super+Tab goes
/// to the window before, and within a second again to the one before that; the walk ends a second after
/// the last press, with the window it stopped on at the front.
#[derive(Default)]
pub struct History {
    mru: Vec<i64>,
    walk: Option<Walk>,
}

struct Walk {
    order: Vec<i64>,
    at: usize,
    last: Instant,
}

/// How long a walk waits for the next press.
pub const WALK: Duration = Duration::from_secs(1);

impl History {
    /// A window took the focus; during a walk the focus is the walk's own.
    pub fn focused(&mut self, id: i64) {
        if self.walk.is_some() {
            return;
        }
        self.mru.retain(|&i| i != id);
        self.mru.insert(0, id);
    }

    /// A window closed; the walk ends when it was the window the walk stood on, sway's own choice of
    /// focus taken from then on.
    pub fn closed(&mut self, id: i64) {
        self.mru.retain(|&i| i != id);
        if self.walk.as_ref().is_some_and(|w| w.order.get(w.at) == Some(&id)) {
            self.walk = None;
            return;
        }
        self.drop_from_walk(|i| i == id);
    }

    /// The windows in sight as sway orders them: the ones not known yet join at the back, the ones gone leave.
    pub fn seed(&mut self, ids: &[i64]) {
        self.mru.retain(|i| ids.contains(i));
        for &id in ids {
            if !self.mru.contains(&id) {
                self.mru.push(id);
            }
        }
        self.drop_from_walk(|i| !ids.contains(&i));
    }

    fn drop_from_walk(&mut self, gone: impl Fn(i64) -> bool) {
        if let Some(w) = self.walk.as_mut() {
            w.order.retain(|&i| !gone(i));
            w.at = w.at.min(w.order.len().saturating_sub(1));
        }
        if self.walk.as_ref().is_some_and(|w| w.order.len() < 2) {
            self.walk = None;
        }
    }

    /// The window Super+Tab goes to now; none with fewer than two.
    pub fn back(&mut self, now: Instant) -> Option<i64> {
        if self.walk.as_ref().is_none_or(|w| now.duration_since(w.last) > WALK) {
            if self.mru.len() < 2 {
                self.walk = None;
                return None;
            }
            self.walk = Some(Walk {
                order: self.mru.clone(),
                at: 0,
                last: now,
            });
        }
        let w = self.walk.as_mut()?;
        w.at = (w.at + 1) % w.order.len();
        w.last = now;
        Some(w.order[w.at])
    }

    /// A walk a second past its last press ends: the window it stopped on comes to the front.
    pub fn settle(&mut self, now: Instant) {
        if let Some(id) = self.walk.as_ref().filter(|w| now.duration_since(w.last) > WALK).map(|w| w.order[w.at]) {
            self.walk = None;
            self.focused(id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_views_in_sight_follow_the_focus_stacks() {
        let tree = serde_json::json!({"type": "root", "focus": [2], "nodes": [
            {"type": "output", "name": "__i3", "id": 1, "nodes": [{"type": "workspace", "name": "__i3_scratch", "id": 9, "floating_nodes": [{"type": "floating_con", "id": 70, "nodes": [], "floating_nodes": []}]}]},
            {"type": "output", "name": "DP-1", "id": 2, "focus": [3], "nodes": [{"type": "workspace", "name": "1", "id": 3, "focus": [6, 5],
                "nodes": [{"type": "con", "id": 5, "nodes": [], "floating_nodes": []}],
                "floating_nodes": [{"type": "floating_con", "id": 6, "nodes": [], "floating_nodes": []}]}]}]});
        assert_eq!(in_sight(&tree), vec![6, 5]);
    }

    #[test]
    fn a_walk_goes_back_and_further_within_a_second() {
        let mut h = History::default();
        h.seed(&[5, 6, 7]);
        h.focused(7);
        let t = Instant::now();
        assert_eq!(h.back(t), Some(5));
        h.focused(5); // sway's event for the walk's own focus: not taken
        assert_eq!(h.back(t + Duration::from_millis(300)), Some(6));
        assert_eq!(h.back(t + Duration::from_millis(600)), Some(7));
        h.settle(t + Duration::from_millis(900));
        assert_eq!(h.back(t + Duration::from_millis(950)), Some(5));
        h.settle(t + Duration::from_secs(3));
        assert_eq!(h.back(t + Duration::from_secs(4)), Some(7));
        h.closed(7);
        h.settle(t + Duration::from_secs(6));
        assert_eq!(h.back(t + Duration::from_secs(7)), Some(6));
        h.seed(&[5]);
        h.settle(t + Duration::from_secs(9));
        assert_eq!(h.back(t + Duration::from_secs(10)), None);
    }
}
