//! What a key or the pointer does on the display page (v0.167): the map's screens chosen, opened, dragged and moved by
//! a key, and the card of a change on trial, kept or put back.

use super::screens::{beside, landing, Map, Rect, Screen, Side};
use super::trial::Trial;
use super::Drag;
use crate::app::{App, Held, Item, Mode, Step, View, Who, DOUBLE_CLICK};
use crate::gate::ResultPrivacy;
use crate::model::{Call, Row};
use crate::reply::Mark;
use serde_json::Value;
use std::time::{Duration, Instant};

/// How far a press on a screen may move and still be a click, in pixels: a finger is never still.
const SLOP: f64 = 8.0;
/// How near a line of another screen pulls a dragged one, in the window's pixels.
const PULL: f64 = 12.0;
/// The steps that change a screen with no trial of their own, and so keep the one under way.
const KEEPS: [&str; 4] = ["display_position", "display_place", "display_on", "display_off"];
/// The rows read once more this long after a trial ended by itself.
const AGAIN: Duration = Duration::from_millis(1500);

impl App {
    // ---- the map

    /// The map of the section on screen: its provider, its row.
    fn map_row(&self) -> Option<(usize, &Row, &Map)> {
        let View::Section(p) = &self.view else { return None };
        let row = self.providers.get(*p)?.rows.rows.iter().find(|r| r.map.is_some())?;
        Some((*p, row, row.map.as_ref()?))
    }

    /// The screen of a map the keys act on: the one chosen, else the one it starts on.
    pub fn map_chosen<'a>(&self, map: &'a Map) -> Option<&'a Screen> {
        self.display.chosen.as_deref().and_then(|n| map.named(n)).or_else(|| map.first())
    }

    /// The screen the light is on: the one chosen while the map's row is lit, or the one whose own row is.
    pub fn map_lit(&self, map: &Map) -> Option<String> {
        if !self.in_list {
            return None;
        }
        let row = self.row_ref(self.picks().get(self.sel)?)?;
        if row.map.is_some() {
            return self.map_chosen(map).map(|s| s.name.clone());
        }
        let own = row.children.as_deref()?;
        map.screens.iter().find(|s| s.children.as_deref() == Some(own)).map(|s| s.name.clone())
    }

    /// Whether a row of the section is a screen's that is off: its name steps back, as it does in the map.
    pub(crate) fn screen_off(&self, row: &Row) -> bool {
        let Some(own) = row.children.as_deref() else { return false };
        let maps = self.providers.iter().flat_map(|p| &p.rows.rows).filter_map(|r| r.map.as_ref());
        maps.flat_map(|m| &m.screens).any(|s| !s.on && s.children.as_deref() == Some(own))
    }

    /// The map whose row is lit, with nothing typed and nothing asked: its provider and itself.
    fn map_keys(&self) -> Option<(usize, Map)> {
        if !self.in_list || !self.input.is_empty() || self.mode != Mode::Normal {
            return None;
        }
        let item = self.picks().get(self.sel).cloned()?;
        let map = self.row_ref(&item)?.map.clone()?;
        Some((self.prov_of(&item)?, map))
    }

    /// Left and right on the map's row: the screen beside the one chosen. The keys stay the map's at its ends.
    pub(crate) fn map_walk(&mut self, up: bool) -> bool {
        let Some((_, map)) = self.map_keys() else { return false };
        let order = map.order();
        let at = self.map_chosen(&map).and_then(|s| order.iter().position(|o| o.name == s.name)).unwrap_or(0);
        let next = if up { at + 1 } else { at.wrapping_sub(1) };
        if let Some(s) = order.get(next) {
            self.display.chosen = Some(s.name.clone());
        }
        true
    }

    /// The page the map's row opens: the chosen screen's own.
    pub(crate) fn map_opens(&self, item: &Item) -> Option<(usize, String)> {
        let map = self.row_ref(item)?.map.as_ref()?;
        Some((self.prov_of(item)?, self.map_chosen(map)?.children.clone()?))
    }

    /// The button down on a screen of the map, its row `n` among the picks: it is chosen, and may be dragged.
    pub fn map_press(&mut self, n: usize, name: &str, at: (f64, f64), scale: f64) {
        self.light(n);
        self.display.chosen = Some(name.to_string());
        self.display.drag = Some(Drag {
            row: n,
            name: name.to_string(),
            from: at,
            by: (0.0, 0.0),
            scale,
            moved: false,
            landing: None,
        });
    }

    /// The pointer moved with the button down on a screen: true where a frame should show it.
    pub fn map_drag(&mut self, at: (f64, f64)) -> bool {
        let Some(mut d) = self.display.drag.take() else { return false };
        d.by = (at.0 - d.from.0, at.1 - d.from.1);
        let was = d.moved;
        d.moved |= d.by.0.hypot(d.by.1) > SLOP;
        let free = self.map_row().filter(|(_, _, m)| m.moves(&d.name));
        d.landing = free.filter(|_| d.moved).and_then(|(_, _, map)| {
            let r = map.named(&d.name)?.rect;
            let want = (r.x as f64 + d.by.0 / d.scale, r.y as f64 + d.by.1 / d.scale);
            landing(r, want, &map.others(&d.name), PULL / d.scale)
        });
        let shows = d.moved || was;
        self.display.drag = Some(d);
        shows
    }

    /// Whether the pointer holds a screen of the map.
    pub fn map_held(&self) -> bool {
        self.display.drag.is_some()
    }

    /// Whether a screen of the map is being dragged.
    pub fn map_dragging(&self) -> bool {
        self.display.drag.as_ref().is_some_and(|d| d.moved && d.landing.is_some())
    }

    /// The button let go: a drag drops its screen where it lands, a click chose its screen and a second one opens it.
    pub fn map_release(&mut self, now: Instant) {
        let Some(d) = self.display.drag.take() else { return };
        if d.moved {
            self.display.click = None;
            if let Some(at) = d.landing {
                self.map_put(&d.name, at);
            }
            return;
        }
        let again = self
            .display
            .click
            .take()
            .is_some_and(|(n, at)| n == d.name && now.saturating_duration_since(at) < DOUBLE_CLICK);
        if again {
            let item = self.picks().get(d.row).cloned();
            if let Some((p, uri)) = item.and_then(|it| self.map_opens(&it)) {
                self.open_children(p, &uri);
            }
        } else {
            self.display.click = Some((d.name, now));
        }
    }

    /// A drag let go without a drop: Esc, or the window not the one typed into any more.
    pub fn map_cancel(&mut self) -> bool {
        self.display.drag.take().is_some()
    }

    /// A key that moves the lit screen to a side of its neighbor.
    pub(crate) fn map_place(&mut self, side: Side) {
        if self.mode != Mode::Normal {
            self.key_held();
            return;
        }
        let lit = self.map_row().and_then(|(_, _, map)| {
            let s = map.named(&self.map_lit(map)?)?.clone();
            Some((map.moves(&s.name), beside(s.rect, &map.others(&s.name), side), s))
        });
        match lit {
            None => self.refuse("nothing to move here"),
            Some((false, _, s)) if !s.on => self.refuse("that screen is off"),
            Some((false, ..)) => self.refuse("no other screen to move it beside"),
            Some((true, at, s)) => {
                if let Some(at) = at {
                    self.map_put(&s.name, at);
                }
            }
        }
    }

    /// A screen put at a place, in layout pixels: shown there at once and set behind it. Where it stands already,
    /// nothing is set.
    fn map_put(&mut self, name: &str, at: (i32, i32)) {
        let Some((p, row, map)) = self.map_row() else { return };
        let (Some(s), Some(step)) = (map.named(name), &map.step) else { return };
        if (s.rect.x, s.rect.y) == at || !map.moves(name) {
            return;
        }
        let (id, mut call) = (row.id.clone(), step.clone());
        call.arguments.insert("screen".into(), Value::String(name.to_string()));
        call.arguments.insert("x".into(), Value::from(at.0));
        call.arguments.insert("y".into(), Value::from(at.1));
        self.display.chosen = Some(name.to_string());
        self.reply = None;
        // a step that asks goes the way of every step, with its question: nothing is set in place unasked
        if self.providers[p].tools.iter().any(|t| t.name == call.name && self.risky(t)) {
            let line = self.step_line(p, &call, name);
            let who = Who::Person;
            return self.run(Step {
                prov: p,
                call,
                who,
                line,
                typed: false,
            });
        }
        self.set_value(p, &id, Held::Placed(name.to_string(), at), call);
    }

    /// The place of a screen held in a map while it is being set.
    pub(crate) fn map_hold(row: &mut Row, name: &str, (x, y): (i32, i32)) {
        if let Some(s) = row.map.as_mut().and_then(|m| m.screens.iter_mut().find(|s| s.name == name)) {
            s.rect = Rect { x, y, ..s.rect };
        }
    }

    // ---- the trial

    /// What a step that was done says of a trial: its own, whose card stands until it is kept, put back, or goes back
    /// by itself, its words held to what may be said as a receipt's are; or the end of the one shown, since any other
    /// change of the screens keeps it.
    pub(crate) fn trial_take(&mut self, prov: usize, tool: &str, result: &Value, privacy: &ResultPrivacy, now: Instant) {
        if let Some(t) = Trial::read(result, prov, now).filter(|t| privacy.text_safe(&t.said)) {
            self.display.left = t.left(now);
            self.display.trial = Some(t);
            self.reply = None;
        } else if KEEPS.contains(&tool) {
            self.display.trial.take_if(|t| t.prov == prov);
        }
    }

    /// The step that ends a trial refused: it was kept or it went back before, which is said and is no alarm. False
    /// for any other step.
    pub(crate) fn trial_told(&mut self, call: &Call, why: &str) -> bool {
        if self.display.ending.take_if(|c| c == call).is_none() {
            return false;
        }
        self.reply(Mark::Note, why);
        true
    }

    /// The card shown: what is on trial, and the seconds left.
    pub fn trial_card(&self) -> Option<(&str, u64)> {
        self.display.trial.as_ref().map(|t| (t.said.as_str(), self.display.left))
    }

    /// Whether Enter and Esc are the card's: a trial runs, and nothing is asked that takes them.
    pub fn trial_keys(&self) -> bool {
        self.display.trial.is_some() && self.mode == Mode::Normal
    }

    /// The change on trial kept, or put back now: its own provider's step, said as a typed one is, with its undo.
    pub fn trial_end(&mut self, keep: bool) {
        if !self.trial_keys() {
            return;
        }
        let Some(t) = self.display.trial.take() else { return };
        self.held.retain(|(p, ..)| *p != t.prov); // the rows say what stands now
        let call = if keep { t.keep } else { t.back };
        let line = self.step_line(t.prov, &call, &t.said);
        self.display.ending = Some(call.clone());
        self.queue.push_front(Step {
            prov: t.prov,
            call,
            who: Who::Person,
            line,
            typed: true,
        });
        self.next_step(); // after the one running, if any
    }

    /// The provider is gone, and its trial with it: the desktop puts the change back on its own.
    pub(crate) fn trial_lost(&mut self, prov: usize) {
        if self.display.trial.as_ref().is_some_and(|t| t.prov == prov) {
            self.display.trial = None;
        }
    }

    /// The clock: the card's seconds, and at their end the change gone back by itself, its rows read again.
    pub(crate) fn display_tick(&mut self, now: Instant) {
        if let Some((p, _)) = self.display.again.take_if(|(_, at)| now >= *at) {
            self.providers[p].dirty = true;
        }
        let Some(t) = &self.display.trial else { return };
        self.display.left = t.left(now);
        if self.display.left > 0 {
            return;
        }
        let Some(t) = self.display.trial.take() else { return };
        self.held.retain(|(p, ..)| *p != t.prov);
        self.providers[t.prov].dirty = true;
        self.display.again = Some((t.prov, now + AGAIN));
        self.reply(Mark::Note, &format!("{} was not kept: the screen is as it was before", t.said));
    }
}
