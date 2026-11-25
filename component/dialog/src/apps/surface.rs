//! Connect the Apps workflow to home's existing prompt, selection, status row and job queue.
use super::{Action, Navigation, Outcome, Page};
use crate::app::{App, Helper, Item, Job, Mode, View};
use crate::reply::Mark;
use serde_json::{json, Value};

impl App {
    pub fn apps_navigation(&self) -> Navigation {
        Navigation {
            query: self.input.clone(),
            selected: self.sel,
            in_list: self.in_list,
            scroll: self.scroll,
        }
    }

    pub fn apps_restore(&mut self, nav: Navigation) {
        self.set_input(nav.query);
        self.sel = nav.selected;
        self.in_list = nav.in_list;
        self.scroll = nav.scroll;
        self.chip_focus = None;
    }

    pub fn apps_request(&mut self, mut request: Value) {
        // an app, and the details of one, open over details still being read
        let over = matches!(request["op"].as_str(), Some("launch" | "details")) && self.apps.pending.as_ref().is_some_and(|(_, op)| op == "details");
        if over {
            self.apps.asked = None;
        } else if self.apps.pending.is_some() {
            return self.refuse("the apps are busy: a moment");
        }
        // with icons shown, a catalog read asks for each app's icon drawn at the cell's size (#230)
        if request["op"] == "catalog" && self.apps.icons && self.apps.icon_px > 0 {
            request["icon_px"] = json!(self.apps.icon_px);
        }
        self.apps.serial += 1;
        let serial = self.apps.serial;
        let op = request["op"].as_str().unwrap_or("").to_string();
        self.apps.pending_name = if op == "launch" {
            request["id"]
                .as_str()
                .and_then(|id| self.apps.entry(id))
                .map(|a| a.name.to_lowercase())
                .unwrap_or_default()
        } else {
            String::new()
        };
        self.apps.pending_since = Some(std::time::Instant::now());
        self.apps.pending = Some((serial, op));
        let shell = std::fs::canonicalize(&self.cfg.spark_shell).unwrap_or_else(|_| self.cfg.spark_shell.clone().into());
        let adapter = shell.parent().unwrap_or(std::path::Path::new(".")).join("lib/apps.py");
        self.jobs.push(Job::RunInput(
            Helper::Apps(serial),
            vec!["python3".into(), adapter.to_string_lossy().into_owned()],
            request.to_string(),
        ));
    }

    /// An action of Apps: a page opened, a change applied at once and said on the status row with Undo, a
    /// request to the native adapter, or a refusal.
    pub fn apps_activate(&mut self, action: Action) {
        let nav = self.apps_navigation();
        // a rename starts from the name as it is, so a letter can be changed (the dialog design notes)
        let prefill = if let Action::Rename(name) = &action { Some(name.clone()) } else { None };
        match self.apps.activate(action, nav) {
            Ok(Outcome {
                navigation,
                request,
                notice,
                undo,
                copy,
            }) => {
                self.reply = None;
                if let Some(nav) = navigation {
                    self.apps_restore(nav);
                }
                if let Some(name) = prefill {
                    self.offer_name(name);
                }
                if let Some(request) = request {
                    self.apps_request(request);
                }
                if let Some(text) = copy {
                    self.apps_request(json!({"op":"copy","text":text}));
                }
                if let Some(text) = notice {
                    self.reply(Mark::Done, &text);
                    if let Some(r) = self.reply.as_mut() {
                        r.undo = undo;
                    }
                }
            }
            Err(error) => self.refuse(&error),
        }
    }

    /// Undo on the status row, for a change of Apps: the preferences as they were.
    pub fn apps_undo(&mut self) {
        if let Some(prefs) = self.apps.undo.take() {
            self.apps_activate(Action::Undo(Box::new(prefs)));
        }
    }

    /// F2 in apps: a category's rename, on its page or on its row among the categories; an app has no rename.
    pub(crate) fn apps_rename(&mut self) {
        let name = match &self.apps.page {
            Page::Category(c) => Some(c.clone()),
            Page::Categories => match self.picks().get(self.sel).filter(|_| self.in_list) {
                Some(Item::Apps(line)) => match &line.action {
                    Some(Action::Category(c)) => Some(c.clone()),
                    _ => None,
                },
                _ => None,
            },
            _ => None,
        };
        match name.filter(|c| c != super::preferences::OTHER) {
            Some(c) => self.apps_activate(Action::Rename(c)),
            None => self.refuse("nothing to rename here"),
        }
    }

    /// F9 on an app in the list, or among the hidden: its details.
    pub fn apps_details(&mut self) -> bool {
        if self.view != View::Apps || !matches!(self.apps.page, Page::List | Page::Hidden) || !self.in_list || self.mode != Mode::Normal {
            return false;
        }
        if let Some(Item::Apps(line)) = self.picks().get(self.sel) {
            if let Some(Action::Launch(id)) = &line.action {
                let id = id.clone();
                // the layout in pixels shows them beside the list where the window holds both, the keys on their
                // first row
                self.apps.pane = self.pixels && self.pane_fits;
                if self.apps.pane && self.apps.details.contains_key(&id) && self.apps.asked.as_deref() == Some(id.as_str()) {
                    // read a moment ago, while the list held the keys beside them
                    let nav = self.apps_navigation();
                    let nav = self.apps.show_details(&id, nav);
                    self.apps_restore(nav);
                } else {
                    self.apps_activate(Action::Details(id.clone()));
                }
                if self.pixels && self.apps.page == Page::Details(id) {
                    (self.in_list, self.sel, self.list_keys) = (true, 0, true);
                }
                return true;
            }
        }
        false
    }

    /// The layout in pixels: the details beside the list kept true to the place shown, and the lit app's facts
    /// asked for, once an app, while the list holds the keys beside them. main.rs calls it every turn of its loop.
    pub fn apps_follow(&mut self) {
        // a wide window shows the lit app beside the list at once (v0.160): the details open by themselves, and
        // close by themselves when the window is no longer wide
        if self.pixels && self.view == View::Apps && matches!(self.apps.page, Page::List | Page::Hidden) {
            if self.wide && self.pane_fits {
                (self.apps.pane, self.pane_wide) = (true, true);
            } else if self.pane_wide {
                (self.apps.pane, self.pane_wide) = (false, false);
            }
        }
        if !self.pixels || !self.apps.pane {
            return;
        }
        let listing = matches!(self.apps.page, Page::List | Page::Hidden);
        let about = self.apps.subject().is_some() && self.apps.root_lists();
        if self.view != View::Apps || !self.pane_fits || !(listing || about) {
            self.apps.pane = false;
            return;
        }
        if !listing || !self.in_list || self.apps.pending.is_some() || self.mode != Mode::Normal {
            return;
        }
        if let Some(Item::Apps(line)) = self.picks().get(self.sel) {
            if let Some(Action::Launch(id)) = &line.action {
                if self.apps.asked.as_deref() != Some(id.as_str()) {
                    self.apps.asked = Some(id.clone());
                    self.apps_request(json!({"op":"details","id":id}));
                }
            }
        }
    }

    /// Tab while an app's details stand beside the list: from the details to the list, from the list to the
    /// line's controls, from the last of them to the details again; Shift+Tab the other way. False where the
    /// details do not stand beside a list: Tab is the controls' alone.
    pub(crate) fn apps_pane_tab(&mut self, back: bool) -> bool {
        if !self.pixels || self.view != View::Apps || !self.apps.pane || self.mode != Mode::Normal {
            return false;
        }
        let listing = matches!(self.apps.page, Page::List | Page::Hidden);
        let details = matches!(self.apps.page, Page::Details(_)) && self.apps.root_lists();
        if !listing && !details {
            return false;
        }
        let c = self.chips();
        let at = self.chip_focus.and_then(|f| c.iter().position(|x| *x == f));
        match (details, at, back) {
            // the details: the list, either way
            (true, _, _) => self.apps_pane_leave(),
            // the list: Tab is the details beside it; Shift+Tab the line's last control, the details where there is none
            (false, None, true) if !c.is_empty() => self.chip_focus = c.last().copied(),
            (false, None, _) => {
                self.apps_details();
            }
            // a control: the next one, and past the last the list; back, the one before, and before the first the list
            (false, Some(i), false) => {
                self.chip_focus = c.get(i + 1).copied();
                if self.chip_focus.is_none() {
                    (self.in_list, self.list_keys) = (true, true);
                }
            }
            (false, Some(0), true) => {
                self.chip_focus = None;
                (self.in_list, self.list_keys) = (true, true);
            }
            (false, Some(i), true) => self.chip_focus = c.get(i - 1).copied(),
        }
        true
    }

    /// From an app's details to the list beside them, the details left open: the list holds the keys, its app lit.
    fn apps_pane_leave(&mut self) {
        if let Some(nav) = self.apps.back() {
            self.apps_restore(nav);
            (self.in_list, self.list_keys) = (true, true);
            self.reply = None;
        }
    }

    /// A click on an app in the list beside the details: that app's details.
    pub fn apps_show(&mut self, id: &str) {
        while self.apps.subject().is_some() {
            let Some(nav) = self.apps.back() else { break };
            self.apps_restore(nav);
        }
        let at = self
            .picks()
            .iter()
            .position(|it| matches!(it, Item::Apps(l) if l.action == Some(Action::Launch(id.to_string()))));
        if let Some(n) = at {
            self.light(n);
            self.apps_details();
        }
    }

    /// A click on a row of the details shown beside the list while the list holds the keys: the keys go to the
    /// details, and the row acts as a click on it does: by what it does, since a read that starts takes a row away.
    pub fn apps_pane_row(&mut self, n: usize, now: std::time::Instant) {
        let Some(Item::Apps(lit)) = self.picks().get(self.sel).cloned() else { return };
        let Some(Action::Launch(id)) = lit.action else { return };
        let row = self.apps.lines_of(&Page::Details(id), 60, "", 0).into_iter().filter_map(|l| l.action).nth(n);
        // refused while the apps are at work: the click is no row of the list's
        if self.apps_details() && matches!(self.apps.page, Page::Details(_)) {
            let same = |it: &Item| matches!(it, Item::Apps(l) if row.is_some() && l.action == row);
            if let Some(n) = self.picks().iter().position(same) {
                self.clicked(n, now);
            }
        }
    }

    pub fn apps_enter(&mut self) {
        if self.apps.form() && !self.in_list {
            return self.apps_activate(Action::Submit);
        }
        // the word undo, typed: the last change of Apps taken back, as a provider's step is at the home, after Esc
        // cleared the receipt that carried its Undo
        if !self.in_list && self.input.trim().eq_ignore_ascii_case("undo") && self.apps.undo.is_some() {
            self.set_input(String::new());
            return self.apps_undo();
        }
        match self.picks().get(self.sel).filter(|_| self.in_list) {
            Some(Item::Apps(line)) => {
                if let Some(action) = &line.action {
                    self.apps_activate(action.clone());
                }
            }
            // Enter is never silent (the dialog design notes)
            _ if self.input.trim().is_empty() => self.refuse("nothing is lit: an arrow or a click lights a row"),
            _ => self.refuse("no app by these words: Esc clears them"),
        }
    }

    /// The key bar is the page's, whatever row is lit or typed: a label stands still under a moving pointer. Enter
    /// has no chip: it opens the app the bar is on, saves a form, as it does everywhere.
    pub fn apps_hint(&self) -> Vec<(String, bool)> {
        let pair = |w: &str, k: &str| vec![(format!("{w} "), false), (k.to_string(), true)];
        if self.pixels && !self.apps.form() {
            return self.apps_hint_pixels();
        }
        // what Esc does here: a form let go, the category filter cleared, else back
        let mut keys = if self.apps.form() {
            // a form waits on Enter for the name typed, so Enter has its chip here (the dialog design notes)
            let mut k = pair("Cancel", "Esc");
            k.push(("   ".into(), false));
            k.extend(pair("Save", "Enter"));
            k
        } else if (self.apps.page == Page::List && self.apps.filter.is_some()) || self.apps.page == Page::Hidden {
            pair("All apps", "Esc")
        } else {
            pair("Back", "Esc")
        };
        if matches!(self.apps.page, Page::List | Page::Hidden) {
            keys.push(("   ".into(), false));
            keys.extend(pair("Details", "F9"));
        }
        keys
    }

    /// The key bar of the layout in pixels: the keys of the part that holds them. Esc's step by its name; Enter
    /// where the lit row opens an app; the details key on a list; Tab between the details and the list while
    /// both stand.
    fn apps_hint_pixels(&self) -> Vec<(String, bool)> {
        let pair = |w: &str, k: &str| vec![(format!("{w} "), false), (k.to_string(), true)];
        let gap = || ("   ".to_string(), false);
        let listing = matches!(self.apps.page, Page::List | Page::Hidden);
        let beside = self.apps.pane && self.pane_fits;
        let mut keys = if listing && beside && !self.wide {
            pair("Close details", "Esc")
        } else if (self.apps.page == Page::List && self.apps.filter.is_some()) || self.apps.page == Page::Hidden {
            pair("All apps", "Esc")
        } else if beside && matches!(self.apps.page, Page::Details(_)) {
            pair("Back to list", "Esc")
        } else {
            pair("Back", "Esc")
        };
        let opens = self.in_list && matches!(self.picks().get(self.sel), Some(Item::Apps(l)) if matches!(l.action, Some(Action::Launch(_))));
        if opens {
            keys.push(gap());
            keys.extend(pair("Open", "Enter"));
        }
        if listing {
            keys.push(gap());
            keys.extend(pair("Details", if beside { "Tab" } else { "F9" }));
        } else if beside && matches!(self.apps.page, Page::Details(_)) {
            keys.push(gap());
            keys.extend(pair("List", "Tab"));
        }
        keys
    }
}
