//! Connect the Apps workflow to home's existing prompt, selection and job queue.
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
            return self.refuse("Wait for the current Apps operation");
        }
        self.apps.serial += 1;
        let serial = self.apps.serial;
        let op = request["op"].as_str().unwrap_or("").to_string();
        self.apps.pending = Some((serial, op));
        let shell = std::fs::canonicalize(&self.cfg.spark_shell).unwrap_or_else(|_| self.cfg.spark_shell.clone().into());
        let adapter = shell.parent().unwrap_or(std::path::Path::new(".")).join("lib/apps.py");
        self.jobs.push(Job::RunInput(
            Helper::Apps(serial),
            vec!["python3".into(), adapter.to_string_lossy().into_owned()],
            request.to_string(),
        ));
    }

    pub fn apps_activate(&mut self, action: Action) {
        if self.leave_decision.is_some() {
            return;
        }
        let nav = self.apps_navigation();
        match self.apps.activate(action, nav) {
            Ok(Outcome {
                navigation,
                request,
                notice,
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
                }
            }
            Err(error) => self.refuse(&error),
        }
    }

    pub fn apps_details(&mut self) -> bool {
        if self.view != View::Apps || !self.in_list || self.mode != Mode::Normal {
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
        if let Some(Item::Apps(line)) = self.picks().get(self.sel).filter(|_| self.in_list) {
            if let Some(action) = &line.action {
                self.apps_activate(action.clone());
            }
        }
    }

    pub fn apps_hint(&self) -> Vec<(String, bool)> {
        let back = if self.apps.form() {
            "Cancel"
        } else if !self.input.is_empty() {
            "Clear"
        } else {
            "Back"
        };
        let mut keys = vec![(format!("{back} "), false), ("Esc".into(), true)];
        let action = self.picks().get(self.sel).and_then(|it| match it {
            Item::Apps(line) => line.action.clone(),
            _ => None,
        });
        if self.apps.form() || self.in_list {
            let label = if self.apps.form() && !self.in_list {
                "Save"
            } else {
                action.as_ref().map(Action::verb).unwrap_or("Choose")
            };
            keys.extend([("   ".into(), false), (format!("{label} "), false), ("Enter".into(), true)]);
        }
        if matches!(self.apps.page, Page::List) && matches!(action, Some(Action::Launch(_))) && self.in_list {
            keys.extend([("   ".into(), false), ("Details ".into(), false), ("\u{2192}".into(), true)]);
        }
        keys
    }
}
