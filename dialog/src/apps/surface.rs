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

    pub fn apps_request(&mut self, request: Value) {
        if self.apps.pending.is_some() {
            return self.refuse("wait for the current Apps operation");
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

    /// Right on an app in the list, or among the hidden: its details.
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
        if let Some(Item::Apps(line)) = self.picks().get(self.sel).filter(|_| self.in_list) {
            if let Some(action) = &line.action {
                self.apps_activate(action.clone());
            }
        }
    }

    /// The key bar is the page's, whatever row is lit or typed: a label stands still under a moving pointer. Enter
    /// has no chip: it opens the app the bar is on, saves a form, as it does everywhere.
    pub fn apps_hint(&self) -> Vec<(String, bool)> {
        let pair = |w: &str, k: &str| vec![(format!("{w} "), false), (k.to_string(), true)];
        let mut keys = if self.apps.form() { pair("Cancel", "Esc") } else { pair("Back", "Esc") };
        if matches!(self.apps.page, Page::List | Page::Hidden) {
            keys.push(("   ".into(), false));
            keys.extend(pair("Details", "\u{2192}"));
        }
        keys
    }
}
