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
        if self.apps.pending.is_some() {
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
                self.apps_activate(Action::Details(id.clone()));
                return true;
            }
        }
        false
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
}
