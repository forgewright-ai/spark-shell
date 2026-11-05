//! Apps' pages as lines, in the row shapes the dialog has everywhere: a group's heading at 2, muted; a row
//! under it with its sign at 4 and its words at 6; a value in one column; a choice's value before its arrow;
//! a switch's dot or ring and its word at the value column; a fact's label muted and its value in the text
//! color; a note muted. Every label is lowercase; a supplied name keeps its spelling.
use super::*;
use crate::scrub::{cells, cut_words};

/// The value column, two cells past the longest name a row keeps whole.
const VALUE_X: u16 = 26;

struct Lines {
    rows: Vec<Line>,
    width: u16,
}

impl Lines {
    fn new(width: u16) -> Self {
        Self { rows: vec![], width }
    }
    fn narrow(&self) -> bool {
        self.width < 50
    }
    fn blank(&mut self) {
        self.rows.push(Line::default());
    }
    fn heading(&mut self, label: &str) {
        self.rows.push(Line {
            label: label.to_lowercase(),
            indent: 2,
            heading: true,
            ..Line::default()
        });
    }
    /// The page's subject: a name as it is spelled, in the text color.
    fn title(&mut self, label: &str) {
        self.rows.push(Line {
            label: label.into(),
            indent: 2,
            title: true,
            ..Line::default()
        });
    }
    fn note(&mut self, text: &str) {
        for row in crate::ui::conversation_rows(&scrub(text), self.width.saturating_sub(8) as usize) {
            self.rows.push(Line {
                label: row,
                indent: 4,
                muted: true,
                ..Line::default()
            });
        }
    }
    /// An app's row (dialog/DESIGN.md): its name lowercase, and its role beside it, muted: the entry's GenericName,
    /// else its Comment with the period dropped (a comment that only repeats the name is dropped too), else nothing;
    /// cut with an ellipsis at the column's end, whole on the status row and in the details.
    fn app(&mut self, a: &Entry) {
        let role = if !a.generic_name.is_empty() {
            a.generic_name.clone()
        } else {
            let c = a.description.trim_end_matches('.');
            if c.eq_ignore_ascii_case(&a.name) {
                String::new()
            } else {
                c.to_string()
            }
        };
        let room = self.width.saturating_sub(VALUE_X + 2) as usize;
        let role = role.to_lowercase();
        let value = if cells(&role) > room {
            format!("{}\u{2026}", crate::scrub::cut(&role, room.saturating_sub(1)))
        } else {
            role
        };
        self.rows.push(Line {
            label: cut_words(&a.name.to_lowercase(), (VALUE_X - 8) as usize),
            value,
            value_x: VALUE_X,
            action: Some(Action::Launch(a.id.clone())),
            indent: 4,
            value_muted: true,
            ..Line::default()
        });
    }
    /// A row: its sign, its words, a value in the value column, an arrow where it opens a list.
    fn row(&mut self, sign: &'static str, label: &str, value: &str, action: Option<Action>) {
        let room = self.width.saturating_sub(VALUE_X + 2) as usize;
        self.rows.push(Line {
            sign,
            label: cut_words(label, (VALUE_X - 8) as usize),
            value: cut_words(value, room),
            value_x: VALUE_X,
            action,
            indent: 4,
            value_muted: true,
            ..Line::default()
        });
    }
    /// A choice among lists: its words, its value before the arrow, the arrow where the rows' arrows stand. Narrow,
    /// the value goes under its words, one target with them.
    fn choice(&mut self, label: &str, value: &str, action: Action) {
        let arrow = "\u{203a}".to_string();
        let end = self.width.saturating_sub(4);
        let value_x = end.saturating_sub(cells(value) as u16);
        if value.is_empty() || (!self.narrow() && value_x >= 6 + cells(label) as u16 + 2) {
            self.rows.push(Line {
                label: label.to_lowercase(),
                value: value.into(),
                value_x,
                tail: arrow,
                action: Some(action),
                indent: 4,
                value_muted: true,
                ..Line::default()
            });
            return;
        }
        self.rows.push(Line {
            label: label.to_lowercase(),
            tail: arrow,
            action: Some(action),
            indent: 4,
            ..Line::default()
        });
        for row in crate::ui::conversation_rows(value, self.width.saturating_sub(10) as usize) {
            self.rows.push(Line {
                value: row,
                value_x: 8,
                indent: 4,
                value_muted: true,
                continuation: true,
                ..Line::default()
            });
        }
    }
    /// A switch, as a setting's: its words, then the dot or the ring and on or off at the value column.
    fn switch(&mut self, label: &str, on: bool, action: Action) {
        self.rows.push(Line {
            sign: if on { "dot" } else { "ring" },
            label: label.to_lowercase(),
            value: if on { "on" } else { "off" }.into(),
            value_x: self.width.saturating_sub(7),
            action: Some(action),
            indent: 4,
            value_muted: !on,
            ..Line::default()
        });
    }
    /// One of a list to pick from: checked when it is the one in use.
    fn pick(&mut self, checked: bool, label: &str, action: Action) {
        self.rows.push(Line {
            sign: if checked { "check" } else { "blank" },
            label: label.to_lowercase(),
            action: Some(action),
            indent: 4,
            ..Line::default()
        });
    }
    /// A fact: its label muted, its value in the text color; a long value wraps under the value column, narrow under
    /// its label.
    fn fact(&mut self, label: &str, value: &str) {
        let (x, first) = if self.narrow() { (8, false) } else { (VALUE_X, true) };
        if !first {
            self.rows.push(Line {
                label: label.to_lowercase(),
                indent: 4,
                ..Line::default()
            });
        }
        for (i, row) in crate::ui::conversation_rows(&scrub(value), self.width.saturating_sub(x + 2) as usize)
            .iter()
            .enumerate()
        {
            self.rows.push(Line {
                label: if i == 0 && first { label.to_lowercase() } else { String::new() },
                value: row.clone(),
                value_x: x,
                indent: 4,
                value_muted: false,
                continuation: i > 0 || !first,
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
                if self.preference_error.is_some() {
                    l.note("the preferences could not be read: a change is refused, the file left as it is");
                    l.blank();
                }
                let apps = self.visible(query);
                if apps.is_empty() && self.pending.is_none() {
                    l.note(if self.failed {
                        "the apps could not be read: refresh apps, at the end of the list, reads them again"
                    } else if !self.loaded {
                        "the apps have not been read yet"
                    } else if self.entries.is_empty() {
                        "no app is installed"
                    } else if !query.trim().is_empty() {
                        "no app matches these words"
                    } else {
                        "no app in this category"
                    });
                }
                self.grouped(&mut l, apps);
                l.blank();
                // the category filter is the headings' (dialog/DESIGN.md, v0.124.4): a click on one shows that
                // category alone, Esc shows all; no filter row at the end of a list to scroll to
                // with nothing hidden the row is a fact, muted, and opens nothing
                let hidden = self.hidden().len();
                if hidden == 0 {
                    l.row("", "hidden apps", "none", None);
                } else {
                    l.choice("hidden apps", &hidden.to_string(), Action::Hidden);
                }
                l.choice("edit categories", "", Action::Categories);
                l.row("", "refresh apps", "", Some(Action::Refresh));
            }
            Page::Hidden => {
                // the hidden apps in the list's own shape, under their categories, searched by the words typed
                // (dialog/DESIGN.md, v0.124.4): hidden is a state of the same apps, not another kind of list
                let hidden = self.hidden_matching(query);
                if hidden.is_empty() {
                    l.note(if query.trim().is_empty() {
                        "no app is hidden"
                    } else {
                        "no hidden app matches these words"
                    });
                }
                self.grouped(&mut l, hidden);
            }
            Page::Details(id) => {
                let Some(app) = self.entry(id) else {
                    l.note("this application is no longer installed");
                    return l.rows;
                };
                // the name as a label: lowercase, as every name in a list is; the entry's own text is in the technical
                // details (dialog/DESIGN.md)
                l.title(&app.name.to_lowercase());
                l.note(&if app.description.is_empty() {
                    "no description in its desktop entry".to_string()
                } else {
                    app.description.trim_end_matches('.').to_lowercase()
                });
                l.blank();
                if let Some(details) = self.details.get(id) {
                    for (label, key) in [("version", "version"), ("installed via", "installed"), ("source", "source")] {
                        l.fact(label, details[key].as_str().unwrap_or("unavailable"));
                    }
                    l.blank();
                } else if self.pending.is_none() {
                    l.row("", "read the details again", "", Some(Action::RetryDetails(id.clone())));
                    l.blank();
                }
                l.row("", "open", "", Some(Action::Launch(id.clone())));
                l.choice("technical details", "", Action::Technical(id.clone()));
                l.blank();
                l.heading("preferences");
                let pref = self.preference(id);
                l.switch("hide this app", pref.hidden, Action::Visibility(id.clone()));
                let category = pref.category.clone().unwrap_or_else(|| self.category_of(app));
                l.choice("category", &category.to_lowercase(), Action::ChooseCategory(id.clone()));
                l.choice("launch", launch_name(pref.mode()), Action::ChooseLaunch(id.clone()));
            }
            Page::Technical(id) => {
                let Some(app) = self.entry(id) else {
                    l.note("this application is no longer installed");
                    return l.rows;
                };
                l.title(&app.name.to_lowercase());
                l.blank();
                match self.details.get(id).and_then(|v| v["fields"].as_array()) {
                    Some(fields) => {
                        for pair in fields {
                            if let (Some(label), Some(value)) = (pair[0].as_str(), pair[1].as_str()) {
                                l.fact(label, value);
                            }
                        }
                    }
                    None => l.note("the technical details are unavailable"),
                }
                l.blank();
                l.row("", "copy launcher path", "", Some(Action::Copy(app.launcher.clone())));
            }
            Page::CategoryPicker(id) => {
                l.heading("category");
                let pref = self.preference(id);
                let mapped = self.entry(id).map(|a| self.prefs.category("", &a.categories)).unwrap_or_else(|| OTHER.into());
                l.pick(
                    pref.category.is_none(),
                    &format!("as mapped: {}", mapped.to_lowercase()),
                    Action::SetCategory(id.clone(), None),
                );
                for c in &self.prefs.categories {
                    l.pick(
                        pref.category.as_deref() == Some(c.as_str()),
                        c,
                        Action::SetCategory(id.clone(), Some(c.clone())),
                    );
                }
            }
            Page::LaunchPicker(id) => {
                l.heading("launch");
                let pref = self.preference(id);
                for mode in ["default", "focus", "new"] {
                    let supported = self
                        .entry(id)
                        .is_some_and(|a| mode == "default" || (mode == "focus" && a.focus) || (mode == "new" && a.new_window));
                    if supported {
                        l.pick(pref.mode() == mode, launch_name(mode), Action::SetLaunch(id.clone(), mode.into()));
                    } else {
                        l.note(if mode == "focus" {
                            "focus existing needs sway and a window identity this app does not declare"
                        } else {
                            "new window: this app declares no such action"
                        });
                    }
                }
            }
            Page::Categories => {
                l.heading("categories");
                for c in &self.prefs.categories {
                    l.choice(c, "", Action::Category(c.clone()));
                }
                l.blank();
                l.row("", "new category", "", Some(Action::AddCategory));
                l.choice("mappings", "", Action::Mappings);
            }
            Page::Category(c) => {
                l.title(&c.to_lowercase());
                l.blank();
                if c != OTHER {
                    l.row("", "rename", "", Some(Action::Rename(c.clone())));
                    l.row("", "delete", "", Some(Action::Delete(c.clone())));
                } else {
                    l.note("other is where an app goes when no mapping and no choice places it");
                }
                let sources: Vec<&str> = self.prefs.mappings.iter().filter(|(_, t)| *t == c).map(|(s, _)| s.as_str()).collect();
                if !sources.is_empty() {
                    l.blank();
                    l.note(&format!("mapped from {}", sources.join(", ")));
                }
            }
            Page::Mappings => {
                l.heading("mappings");
                for (source, target) in &self.prefs.mappings {
                    // the desktop's own word, as it is spelled; ours lowercase
                    l.choice(source, &target.to_lowercase(), Action::Mapping(source.clone()));
                    if let Some(row) = l.rows.iter_mut().rev().find(|r| r.action == Some(Action::Mapping(source.clone()))) {
                        row.label = cut_words(source, 18);
                    }
                }
                l.blank();
                l.row("", "add mapping", "", Some(Action::AddMapping));
            }
            Page::Mapping(source) => {
                l.heading(&format!("{} maps to", source));
                if let Some(row) = l.rows.last_mut() {
                    row.label = format!("{} maps to", source); // the desktop's own word, as it is spelled
                }
                let current = self.prefs.mappings.get(source);
                for c in &self.prefs.categories {
                    l.pick(current == Some(c), c, Action::Map(source.clone(), Some(c.clone())));
                }
                l.blank();
                l.row("", "remove mapping", "", Some(Action::Map(source.clone(), None)));
                if current.is_none() {
                    l.rows.last_mut().unwrap().disabled = true;
                }
            }
            Page::Form(form) => {
                l.title(match form {
                    Form::AddCategory => "new category",
                    Form::RenameCategory(_) => "rename category",
                    Form::AddMapping => "add mapping",
                });
                l.blank();
                if *form == Form::AddMapping {
                    // the desktop categories the installed apps carry and no mapping places yet: picked, not
                    // recalled (dialog/DESIGN.md, v0.124.4); a word the catalog does not have is typed
                    let sources = self.unmapped_sources();
                    if !sources.is_empty() {
                        l.heading("seen in installed apps");
                        for s in &sources {
                            l.choice(s, "", Action::Mapping(s.clone()));
                            if let Some(row) = l.rows.last_mut() {
                                row.label = cut_words(s, 18); // the desktop's own word, as it is spelled
                            }
                        }
                        l.blank();
                    }
                }
                // the prompt's placeholder says what to type and the key bar says Enter saves: no note repeats them
                if *form == Form::AddMapping {
                    l.note("or type a desktop category in the prompt, such as Network, then Enter");
                }
                if let Form::RenameCategory(from) = form {
                    l.blank();
                    l.fact("now", from);
                }
            }
        }
        l.rows
    }

    /// Apps under their categories' headings, a row of air between groups: the list's shape, and the hidden
    /// page's (dialog/DESIGN.md, v0.124.4).
    fn grouped(&self, l: &mut Lines, apps: Vec<&Entry>) {
        let mut category = String::new();
        for a in apps {
            let group = self.category_of(a);
            if group != category {
                if !category.is_empty() {
                    l.blank();
                }
                l.heading(&group);
                category = group;
            }
            l.app(a);
        }
    }
}
