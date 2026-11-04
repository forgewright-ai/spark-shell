//! Apps presentation on the shared home grid.
use super::*;
use crate::scrub::cut_words;

struct Lines {
    rows: Vec<Line>,
    width: u16,
    indent: u16,
}
impl Lines {
    fn new(width: u16) -> Self {
        Self {
            rows: vec![],
            width,
            indent: 4,
        }
    }
    fn blank(&mut self) {
        self.line("", "", None, false);
    }
    fn line(&mut self, label: &str, value: &str, action: Option<Action>, bold: bool) {
        let value_x = 24.min(self.width / 2 + 2);
        let underline = action.is_some() && value.is_empty() && !bold;
        self.rows.push(Line {
            label: cut_words(
                label,
                if value.is_empty() {
                    self.width.saturating_sub(self.indent + 2) as usize
                } else {
                    value_x.saturating_sub(self.indent + 2) as usize
                },
            ),
            value: cut_words(value, self.width.saturating_sub(value_x + 2) as usize),
            value_x,
            action,
            bold,
            indent: self.indent,
            underline,
            ..Line::default()
        });
    }
    fn heading(&mut self, label: &str) {
        self.indent = 2;
        self.line(&label.to_lowercase(), "", None, true);
        self.indent = 4;
        self.blank();
    }
    fn setting(&mut self, label: &str, value: &str, action: Action, menu: bool) {
        let first = self.rows.len();
        // A preference's value reflows just like technical metadata. Its label
        // remains the one logical keyboard/click target at every width.
        self.field(label, value);
        for line in self.rows.iter_mut().skip(first + 1) {
            line.continuation = true;
        }
        if let Some(line) = self.rows.get_mut(first) {
            line.action = Some(action);
            if menu {
                line.tail = "\u{2304}".into();
            }
        }
    }
    fn disclosure(&mut self, label: &str, expanded: bool, action: Action) {
        self.indent = 2;
        self.line(&label.to_lowercase(), "", Some(action), true);
        self.rows.last_mut().unwrap().tail = if expanded { "\u{2304}" } else { "\u{203a}" }.into();
        self.indent = 4;
        if expanded {
            self.blank();
        }
    }
    fn text(&mut self, text: &str) {
        for row in crate::ui::conversation_rows(&scrub(text), self.width.saturating_sub(self.indent + 2) as usize) {
            self.line(&row, "", None, false);
        }
    }
    fn field(&mut self, label: &str, value: &str) {
        let narrow = self.width < 50;
        let x = if narrow { 6 } else { 24 };
        let available = self.width.saturating_sub(x + 3) as usize;
        if narrow {
            self.line(&label.to_lowercase(), "", None, false);
        }
        for (i, row) in crate::ui::conversation_rows(&scrub(value), available).iter().enumerate() {
            self.rows.push(Line {
                label: if i == 0 && !narrow { label.to_lowercase() } else { String::new() },
                value: row.clone(),
                value_x: x,
                action: None,
                bold: false,
                indent: self.indent,
                ..Line::default()
            });
        }
    }

    fn visibility(&mut self, hidden: bool, action: Action) {
        self.setting("visibility", "hide / unhide", action, false);
        self.rows.last_mut().unwrap().toggle = Some(!hidden);
    }

    fn toolbar(&mut self, category: &str, show_hidden: bool) {
        let shared = self.width >= 54;
        let end = if shared { self.width - 31 } else { self.width };
        self.rows.push(Line {
            label: cut_words(category, end.saturating_sub(7) as usize),
            indent: 2,
            action: Some(Action::Filter),
            tail: "\u{2304}".into(),
            bounds: Some((0, end)),
            ..Line::default()
        });
        let start = if shared { self.width - 30 } else { 0 };
        self.rows.push(Line {
            label: "hidden apps:".into(),
            value: "hide / unhide".into(),
            indent: start + 2,
            value_x: start + 15,
            action: Some(Action::Hidden),
            bounds: Some((start, self.width)),
            inline: shared,
            toggle: Some(show_hidden),
            muted: true,
            ..Line::default()
        });
    }

    fn save_cancel(&mut self, save: Action, cancel: Action, dirty: bool) {
        self.blank();
        self.text(if dirty { "unsaved changes" } else { "" });
        for (label, action, start) in [("save", save, 2), ("cancel", cancel, 12)] {
            self.rows.push(Line {
                label: label.into(),
                indent: start + 2,
                action: Some(action),
                inline: start == 12,
                bounds: Some((start, start + 10)),
                underline: dirty,
                disabled: !dirty,
                ..Line::default()
            });
        }
    }
}

impl State {
    pub fn lines(&self, width: u16, query: &str, _frame: Option<u64>) -> Vec<Line> {
        let mut l = Lines::new(width);
        match &self.page {
            Page::List => {
                let category = if query.trim().is_empty() {
                    self.filter.as_deref().unwrap_or("all categories")
                } else {
                    "all categories"
                };
                l.toolbar(&category.to_lowercase(), self.show_hidden);
                if self.preference_error.is_some() {
                    l.text("Preferences could not be read. Saving is disabled; the original file is preserved.");
                }
                l.blank();
                let apps = self.visible(query);
                if apps.is_empty() && self.pending.is_none() {
                    l.text(if self.failed {
                        "Apps unavailable. Retry discovery below."
                    } else if !self.loaded {
                        "Apps have not been read yet."
                    } else if self.entries.is_empty() {
                        "No launchable applications are installed."
                    } else if !query.trim().is_empty() {
                        "No apps match this search."
                    } else {
                        "No visible apps in this category."
                    });
                }
                let mut category = String::new();
                for a in apps {
                    let group = self.prefs.category(&a.id, &a.categories);
                    if group != category {
                        if !category.is_empty() {
                            l.blank();
                        }
                        l.heading(&group);
                        category = group;
                    }
                    // Desktop-entry roles are concise and localized. Keep the
                    // full comment in Details and search, not every browse row.
                    l.line(&a.name, &a.generic_name, Some(Action::Launch(a.id.clone())), false);
                    let row = l.rows.last_mut().unwrap();
                    row.underline = false;
                    row.value_muted = true;
                    if self.preference(&a.id).hidden {
                        row.tail = "hidden".into();
                        row.value = cut_words(&a.generic_name, width.saturating_sub(row.value_x + 10) as usize);
                    }
                }
                l.blank();
                l.line("manage categories", "", Some(Action::Categories), false);
                l.line("refresh apps", "", Some(Action::Refresh), false);
            }
            Page::Details(id) => {
                let Some(app) = self.entry(id) else {
                    l.text("This application is no longer installed.");
                    return l.rows;
                };
                l.heading(&app.name);
                l.text(if app.description.is_empty() {
                    "No description supplied by the desktop entry."
                } else {
                    &app.description
                });
                l.blank();
                if let Some(details) = self.details.get(id) {
                    for (label, key) in [("Version", "version"), ("Installed via", "installed"), ("Source", "source")] {
                        l.field(label, details[key].as_str().unwrap_or("Unavailable"));
                    }
                } else if self.pending.is_none() {
                    l.line("retry details", "", Some(Action::RetryDetails(id.clone())), false);
                }
                l.blank();
                l.line("open application", "", Some(Action::Launch(id.clone())), false);
                l.blank();
                l.disclosure("technical details", self.expanded, Action::Technical);
                if self.expanded {
                    if let Some(fields) = self.details.get(id).and_then(|v| v["fields"].as_array()) {
                        for pair in fields {
                            if let (Some(label), Some(value)) = (pair[0].as_str(), pair[1].as_str()) {
                                l.field(label, value);
                            }
                        }
                    } else {
                        l.text("Technical metadata is unavailable.");
                    }
                    l.blank();
                    l.line("copy launcher path", "", Some(Action::Copy(app.launcher.clone())), false);
                }
                l.blank();
                l.heading("preferences");
                let pref = self.draft(id);
                let category = pref
                    .category
                    .clone()
                    .unwrap_or_else(|| format!("{} (mapped)", self.prefs.category("", &app.categories)));
                l.setting("category", &category.to_lowercase(), Action::ChooseCategory(id.clone()), true);
                l.visibility(pref.hidden, Action::Visibility(id.clone()));
                l.setting("launch", launch_name(pref.mode()), Action::ChooseLaunch(id.clone()), true);
                l.save_cancel(Action::Save(id.clone()), Action::Discard(id.clone()), self.dirty(id));
            }
            Page::Filter => {
                l.heading("choose a category");
                l.line("all categories", "", Some(Action::SetFilter(None)), false);
                for c in &self.prefs.categories {
                    l.line(&c.to_lowercase(), "", Some(Action::SetFilter(Some(c.clone()))), false);
                }
            }
            Page::CategoryPicker(id) => {
                l.heading("category preference");
                l.line("follow category mapping", "", Some(Action::SetCategory(id.clone(), None)), false);
                for c in &self.prefs.categories {
                    l.line(&c.to_lowercase(), "", Some(Action::SetCategory(id.clone(), Some(c.clone()))), false);
                }
            }
            Page::LaunchPicker(id) => {
                l.heading("launch preference");
                for mode in ["default", "focus", "new"] {
                    let supported = self
                        .entry(id)
                        .is_some_and(|a| mode == "default" || (mode == "focus" && a.focus) || (mode == "new" && a.new_window));
                    l.line(
                        launch_name(mode),
                        if supported { "" } else { "Unavailable" },
                        supported.then(|| Action::SetLaunch(id.clone(), mode.into())),
                        false,
                    );
                    if !supported {
                        l.text(if mode == "focus" {
                            "Needs Sway and a declared window identity."
                        } else {
                            "No New window action is declared by this app."
                        });
                    }
                }
            }
            Page::Categories => {
                l.heading("categories");
                for c in &self.prefs.categories {
                    l.line(&c.to_lowercase(), "", Some(Action::Category(c.clone())), false);
                    let row = l.rows.last_mut().unwrap();
                    row.tail = "\u{203a}".into();
                    row.underline = false;
                }
                l.blank();
                l.line("create category", "", Some(Action::AddCategory), false);
                l.line("default mappings", "", Some(Action::Mappings), false);
            }
            Page::Category(c) => {
                l.heading(c);
                if c != OTHER {
                    l.line("rename category", "", Some(Action::Rename(c.clone())), false);
                    l.line("delete category", "", Some(Action::Delete(c.clone())), false);
                } else {
                    l.text("Other is the fallback when no mapping or individual override applies.");
                }
                l.line("default mappings", "", Some(Action::Mappings), false);
            }
            Page::DeleteCategory(c) => {
                l.heading("delete category");
                l.text(&format!("Delete {c}? Its mappings and individual category overrides will be removed. Apps use remaining mappings or Other. Visibility and launch preferences stay."));
                l.blank();
                l.line("delete category", "", Some(Action::ConfirmDelete(c.clone())), false);
            }
            Page::Mappings => {
                l.heading("default category mappings");
                l.text("The first mapped category in a desktop entry wins; an individual override takes precedence.");
                l.blank();
                for (source, target) in &self.prefs.mappings {
                    let first = l.rows.len();
                    l.setting(source, &target.to_lowercase(), Action::Mapping(source.clone()), true);
                    // The desktop category identifier is data, not a UI label.
                    l.rows[first].label = cut_words(source, if width < 50 { width.saturating_sub(6) } else { 18 } as usize);
                }
                l.blank();
                l.line("add mapping", "", Some(Action::AddMapping), false);
            }
            Page::Mapping(source) => {
                l.heading("category mapping");
                l.text(&format!("Map desktop category {source} to:"));
                let target = self
                    .mapping_drafts
                    .get(source)
                    .cloned()
                    .unwrap_or_else(|| self.prefs.mappings.get(source).cloned());
                l.field("target", target.as_deref().unwrap_or("No mapping"));
                l.blank();
                for c in &self.prefs.categories {
                    l.line(&c.to_lowercase(), "", Some(Action::Map(source.clone(), Some(c.clone()))), false);
                }
                l.blank();
                l.line("remove mapping", "", Some(Action::Map(source.clone(), None)), false);
                l.save_cancel(
                    Action::SaveMapping(source.clone()),
                    Action::CancelMapping(source.clone()),
                    self.mapping_dirty(source),
                );
            }
            Page::Form(form) => {
                l.heading(match form {
                    Form::AddCategory => "create category",
                    Form::RenameCategory(_) => "rename category",
                    Form::AddMapping => "add mapping",
                });
                l.text(match form {
                    Form::AddCategory => "Type a new category name in the prompt.",
                    Form::RenameCategory(_) => "Type the new category name in the prompt.",
                    Form::AddMapping => "Type the system desktop category identifier, such as Network, in the prompt.",
                });
                if let Form::RenameCategory(from) = form {
                    l.field("current name", from);
                }
                l.blank();
                l.save_cancel(Action::Submit, Action::CancelForm, !query.is_empty());
            }
        }
        l.rows
    }
}
