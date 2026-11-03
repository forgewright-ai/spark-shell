//! Apps owns browsing, Details and local preferences inside home's shared frame.
pub mod preferences;
mod surface;

use crate::scrub::{cut_words, scrub};
use preferences::{Preference, Preferences, OTHER};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub description: String,
    pub generic_name: String,
    pub categories: Vec<String>,
    pub launcher: String,
    pub focus: bool,
    pub new_window: bool,
}

impl Entry {
    fn read(v: &Value) -> Option<Self> {
        let id = v["id"].as_str()?;
        if !id.ends_with(".desktop") || id.contains('/') || id.chars().any(char::is_control) {
            return None;
        }
        Some(Self {
            id: id.into(),
            name: scrub(v["name"].as_str()?).to_lowercase(),
            description: scrub(v["description"].as_str().unwrap_or("")),
            generic_name: scrub(v["generic_name"].as_str().unwrap_or("")),
            categories: v["categories"]
                .as_array()
                .map(|a| a.iter().filter_map(Value::as_str).map(scrub).collect())
                .unwrap_or_default(),
            launcher: v["launcher"].as_str().unwrap_or("").into(),
            focus: v["focus"].as_bool().unwrap_or(false),
            new_window: v["new_window"].as_str().is_some_and(|x| !x.is_empty()),
        })
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Form {
    AddCategory,
    RenameCategory(String),
    AddMapping,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub enum Page {
    #[default]
    List,
    Details(String),
    Filter,
    CategoryPicker(String),
    LaunchPicker(String),
    Categories,
    Category(String),
    DeleteCategory(String),
    Mappings,
    Mapping(String),
    Form(Form),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    Launch(String),
    Details(String),
    Filter,
    SetFilter(Option<String>),
    Hidden,
    Categories,
    Category(String),
    Rename(String),
    Delete(String),
    ConfirmDelete(String),
    AddCategory,
    Mappings,
    Mapping(String),
    Map(String, Option<String>),
    SaveMapping(String),
    CancelMapping(String),
    AddMapping,
    Submit,
    Technical,
    ChooseCategory(String),
    SetCategory(String, Option<String>),
    Visibility(String),
    ChooseLaunch(String),
    SetLaunch(String, String),
    Save(String),
    Discard(String),
    CancelForm,
    Refresh,
    Copy(String),
    RetryDetails(String),
}

impl Action {
    pub fn verb(&self) -> &str {
        match self {
            Self::Launch(_) => "Open",
            Self::Save(_) | Self::SaveMapping(_) | Self::Submit => "Save",
            Self::Copy(_) => "Copy",
            Self::ConfirmDelete(_) => "Delete",
            Self::Hidden | Self::Visibility(_) | Self::Technical => "Change",
            Self::SetCategory(..) | Self::SetLaunch(..) | Self::SetFilter(_) | Self::Map(..) => "Set",
            Self::Discard(_) | Self::CancelForm | Self::CancelMapping(_) => "Cancel",
            Self::Refresh | Self::RetryDetails(_) => "Retry",
            _ => "Choose",
        }
    }
}

/// A composed content line. Only its action makes it selectable. Wrapped values
/// retain their original data in the model, independent of drawing and copying.
#[derive(Clone, Debug, PartialEq)]
pub struct Line {
    pub label: String,
    pub value: String,
    pub value_x: u16,
    pub action: Option<Action>,
    pub bold: bool,
    pub indent: u16,
    pub tail: String,
    pub continuation: bool,
}

#[derive(Clone, Debug, Default)]
pub struct Navigation {
    pub query: String,
    pub selected: usize,
    pub in_list: bool,
    pub scroll: usize,
}

#[derive(Default)]
pub struct Outcome {
    pub navigation: Option<Navigation>,
    pub request: Option<Value>,
    pub notice: Option<String>,
    pub copy: Option<String>,
}

pub struct State {
    pub entries: Vec<Entry>,
    pub prefs: Preferences,
    pub path: PathBuf,
    pub preference_error: Option<String>,
    pub page: Page,
    pub filter: Option<String>,
    pub show_hidden: bool,
    pub expanded: bool,
    pub drafts: BTreeMap<String, Preference>,
    pub mapping_drafts: BTreeMap<String, Option<String>>,
    pub details: BTreeMap<String, Value>,
    pub loaded: bool,
    pub failed: bool,
    pub pending: Option<(u64, String)>,
    pub serial: u64,
    stack: Vec<(Page, Navigation)>,
}

impl Default for State {
    fn default() -> Self {
        let path = Preferences::path();
        let loaded = Preferences::load(&path);
        let preference_error = loaded.as_ref().err().cloned();
        Self {
            entries: vec![],
            prefs: loaded.unwrap_or_default(),
            path,
            preference_error,
            page: Page::List,
            filter: None,
            show_hidden: false,
            expanded: false,
            drafts: BTreeMap::new(),
            mapping_drafts: BTreeMap::new(),
            details: BTreeMap::new(),
            loaded: false,
            failed: false,
            pending: None,
            serial: 0,
            stack: vec![],
        }
    }
}

impl State {
    pub fn form(&self) -> bool {
        matches!(self.page, Page::Form(_))
    }
    pub fn preference(&self, id: &str) -> Preference {
        self.prefs.apps.get(id).cloned().unwrap_or_default()
    }
    pub fn draft(&self, id: &str) -> Preference {
        self.drafts.get(id).cloned().unwrap_or_else(|| self.preference(id))
    }
    pub fn dirty(&self, id: &str) -> bool {
        self.draft(id) != self.preference(id)
    }
    pub fn mapping_dirty(&self, source: &str) -> bool {
        self.mapping_drafts
            .get(source)
            .is_some_and(|target| target.as_ref() != self.prefs.mappings.get(source))
    }
    pub fn entry(&self, id: &str) -> Option<&Entry> {
        self.entries.iter().find(|a| a.id == id)
    }

    pub fn visible(&self, query: &str) -> Vec<&Entry> {
        let words = query.to_lowercase();
        let mut apps: Vec<_> = self
            .entries
            .iter()
            .filter(|a| {
                if self.preference(&a.id).hidden && !self.show_hidden {
                    return false;
                }
                if words.trim().is_empty() {
                    self.filter.as_ref().is_none_or(|c| *c == self.prefs.category(&a.id, &a.categories))
                } else {
                    let text = format!("{} {} {}", a.name, a.generic_name, a.description).to_lowercase();
                    words.split_whitespace().all(|w| text.contains(w))
                }
            })
            .collect();
        apps.sort_by_key(|a| {
            (
                self.prefs
                    .categories
                    .iter()
                    .position(|c| *c == self.prefs.category(&a.id, &a.categories))
                    .unwrap_or(usize::MAX),
                &a.name,
                &a.id,
            )
        });
        apps
    }

    fn navigate(&mut self, page: Page, nav: Navigation) -> Navigation {
        self.stack.push((self.page.clone(), nav));
        self.page = page;
        Navigation::default()
    }

    pub fn back(&mut self) -> Option<Navigation> {
        self.stack.pop().map(|(page, nav)| {
            self.page = page;
            nav
        })
    }

    fn save(&mut self, prefs: Preferences) -> Result<(), String> {
        if let Some(error) = &self.preference_error {
            return Err(error.clone());
        }
        prefs.save(&self.path)?;
        self.prefs = prefs;
        if self.filter.as_ref().is_some_and(|c| !self.prefs.categories.contains(c)) {
            self.filter = None;
        }
        Ok(())
    }

    pub fn activate(&mut self, action: Action, nav: Navigation) -> Result<Outcome, String> {
        let mut out = Outcome::default();
        match action {
            Action::Launch(id) => {
                if self.pending.is_some() {
                    return Err("Wait for the current Apps operation".into());
                }
                let app = self.entry(&id).ok_or("This application is no longer available")?;
                let pref = self.preference(&id);
                if pref.mode() == "focus" && !app.focus {
                    return Err("Focus existing is unavailable here; choose Application default in Details".into());
                }
                if pref.mode() == "new" && !app.new_window {
                    return Err("New window is no longer supported; choose Application default in Details".into());
                }
                out.request = Some(json!({"op":"launch","id":id,"mode":pref.mode()}));
            }
            Action::Details(id) => {
                self.entry(&id).ok_or("This application is no longer available")?;
                out.navigation = Some(self.navigate(Page::Details(id.clone()), nav));
                // Keep cached content readable while refreshing on entry:
                // packages and running windows may have changed since last time.
                out.request = Some(json!({"op":"details","id":id}));
            }
            Action::Filter => out.navigation = Some(self.navigate(Page::Filter, nav)),
            Action::SetFilter(category) => {
                self.filter = category;
                out.navigation = self.back();
                if let Some(n) = &mut out.navigation {
                    n.selected = 0;
                    n.in_list = false;
                    n.scroll = 0;
                }
            }
            Action::Hidden => {
                self.show_hidden = !self.show_hidden;
                out.navigation = Some(Navigation {
                    query: nav.query,
                    ..Navigation::default()
                });
            }
            Action::Categories => out.navigation = Some(self.navigate(Page::Categories, nav)),
            Action::Category(name) => out.navigation = Some(self.navigate(Page::Category(name), nav)),
            Action::Rename(name) => out.navigation = Some(self.navigate(Page::Form(Form::RenameCategory(name)), nav)),
            Action::AddCategory => out.navigation = Some(self.navigate(Page::Form(Form::AddCategory), nav)),
            Action::AddMapping => out.navigation = Some(self.navigate(Page::Form(Form::AddMapping), nav)),
            Action::Mappings => out.navigation = Some(self.navigate(Page::Mappings, nav)),
            Action::Mapping(name) => out.navigation = Some(self.navigate(Page::Mapping(name), nav)),
            Action::Map(source, target) => {
                self.mapping_drafts.insert(source, target);
            }
            Action::SaveMapping(source) => {
                let mut prefs = self.prefs.clone();
                let target = self
                    .mapping_drafts
                    .get(&source)
                    .cloned()
                    .unwrap_or_else(|| self.prefs.mappings.get(&source).cloned());
                if let Some(target) = target {
                    prefs.mappings.insert(source.clone(), target);
                } else {
                    prefs.mappings.remove(&source);
                }
                self.save(prefs)?;
                self.mapping_drafts.remove(&source);
                out.navigation = self.back();
            }
            Action::CancelMapping(source) => {
                self.mapping_drafts.remove(&source);
                out.navigation = self.back();
            }
            Action::Submit => {
                let mut prefs = self.prefs.clone();
                match self.page.clone() {
                    Page::Form(Form::AddCategory) => prefs.add(&nav.query)?,
                    Page::Form(Form::RenameCategory(from)) => {
                        prefs.rename(&from, &nav.query)?;
                        self.save(prefs)?;
                        for draft in self.drafts.values_mut() {
                            if draft.category.as_deref() == Some(&from) {
                                draft.category = Some(nav.query.trim().into());
                            }
                        }
                        self.back();
                        self.page = Page::Category(nav.query.trim().into());
                        out.navigation = Some(Navigation::default());
                        return Ok(out);
                    }
                    Page::Form(Form::AddMapping) => {
                        let source = nav.query.trim();
                        if source.is_empty() || source.len() > 80 || !source.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
                            return Err("Use a desktop category identifier, such as Network".into());
                        }
                        self.back();
                        self.page = Page::Mapping(source.into());
                        out.navigation = Some(Navigation::default());
                        return Ok(out);
                    }
                    _ => return Ok(out),
                }
                self.save(prefs)?;
                out.navigation = self.back();
            }
            Action::Delete(name) => out.navigation = Some(self.navigate(Page::DeleteCategory(name), nav)),
            Action::ConfirmDelete(name) => {
                let mut prefs = self.prefs.clone();
                prefs.delete(&name)?;
                self.save(prefs)?;
                for draft in self.drafts.values_mut() {
                    if draft.category.as_deref() == Some(&name) {
                        draft.category = None;
                    }
                }
                self.back();
                out.navigation = self.back();
            }
            Action::Technical => self.expanded = !self.expanded,
            Action::ChooseCategory(id) => out.navigation = Some(self.navigate(Page::CategoryPicker(id), nav)),
            Action::ChooseLaunch(id) => out.navigation = Some(self.navigate(Page::LaunchPicker(id), nav)),
            Action::SetCategory(id, category) => {
                let mut draft = self.draft(&id);
                draft.category = category;
                self.drafts.insert(id, draft);
                out.navigation = self.back();
            }
            Action::SetLaunch(id, launch) => {
                let mut draft = self.draft(&id);
                draft.launch = launch;
                self.drafts.insert(id, draft);
                out.navigation = self.back();
            }
            Action::Visibility(id) => {
                let mut draft = self.draft(&id);
                draft.hidden = !draft.hidden;
                self.drafts.insert(id, draft);
            }
            Action::Save(id) => {
                let mut prefs = self.prefs.clone();
                prefs.apps.insert(id.clone(), self.draft(&id));
                self.save(prefs)?;
                self.drafts.remove(&id);
                out.notice = Some("Apps preferences saved".into());
            }
            Action::Discard(id) => {
                self.drafts.remove(&id);
                out.notice = Some("Unsaved preferences discarded".into());
            }
            Action::CancelForm => out.navigation = self.back(),
            Action::Refresh => out.request = Some(json!({"op":"catalog"})),
            Action::RetryDetails(id) => out.request = Some(json!({"op":"details","id":id})),
            Action::Copy(value) => out.copy = Some(value),
        }
        Ok(out)
    }

    pub fn receive(&mut self, serial: u64, value: Value) -> Result<Option<String>, String> {
        if self.pending.as_ref().is_none_or(|(s, _)| *s != serial) {
            return Ok(None);
        }
        let (_, op) = self.pending.take().unwrap();
        if let Some(error) = value["error"].as_str() {
            if op == "catalog" {
                self.failed = true;
            }
            return Err(scrub(error));
        }
        match op.as_str() {
            "catalog" => {
                self.failed = true;
                self.entries = value["apps"]
                    .as_array()
                    .ok_or("Invalid native Apps catalog")?
                    .iter()
                    .filter_map(Entry::read)
                    .collect();
                self.loaded = true;
                self.failed = false;
                self.details.clear();
            }
            "details" => {
                let id = value["id"].as_str().ok_or("Invalid application details")?.to_string();
                self.details.insert(id, value);
            }
            "launch" => return Ok(Some(scrub(value["message"].as_str().unwrap_or("Launch outcome is unavailable")))),
            "copy" => return Ok(Some("Copied".into())),
            _ => return Err("Unknown Apps operation result".into()),
        }
        Ok(None)
    }
}

pub fn launch_name(mode: &str) -> &str {
    match mode {
        "focus" => "Focus existing",
        "new" => "New window",
        _ => "Application default",
    }
}

struct Lines {
    rows: Vec<Line>,
    width: u16,
}
impl Lines {
    fn new(width: u16) -> Self {
        Self {
            rows: vec![],
            width: width.saturating_sub(4),
        }
    }
    fn blank(&mut self) {
        self.line("", "", None, false);
    }
    fn line(&mut self, label: &str, value: &str, action: Option<Action>, bold: bool) {
        let value_x = if value.is_empty() { 2 } else { 20.min(self.width / 2 + 2) };
        self.rows.push(Line {
            label: cut_words(
                label,
                if value.is_empty() {
                    self.width as usize
                } else {
                    value_x.saturating_sub(4) as usize
                },
            ),
            value: cut_words(value, self.width.saturating_sub(value_x - 2) as usize),
            value_x,
            action,
            bold,
            indent: 2,
            tail: String::new(),
            continuation: false,
        });
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
        self.line(label, "", Some(action), true);
        self.rows.last_mut().unwrap().tail = if expanded { "\u{2304}" } else { "\u{203a}" }.into();
    }
    fn text(&mut self, text: &str) {
        for row in crate::ui::wrap(&scrub(text), self.width as usize) {
            self.line(&row, "", None, false);
        }
    }
    fn field(&mut self, label: &str, value: &str) {
        let narrow = self.width < 46;
        let x = if narrow { 4 } else { 20 };
        let available = self.width.saturating_sub(x) as usize;
        if narrow {
            self.line(label, "", None, false);
        }
        for (i, row) in crate::ui::wrap(&scrub(value), available).iter().enumerate() {
            self.rows.push(Line {
                label: if i == 0 && !narrow { label.into() } else { String::new() },
                value: row.clone(),
                value_x: x,
                action: None,
                bold: false,
                indent: 2,
                tail: String::new(),
                continuation: false,
            });
        }
    }
}

impl State {
    pub fn lines(&self, width: u16, query: &str, frame: Option<u64>) -> Vec<Line> {
        let mut l = Lines::new(width);
        let heading = match &self.page {
            Page::Details(id) => format!("apps / {}", self.entry(id).map(|a| a.name.as_str()).unwrap_or("unavailable")),
            _ => "apps".into(),
        };
        l.line(&heading, "", None, true);
        if let Some((_, op)) = &self.pending {
            let label = match op.as_str() {
                "catalog" => "Finding apps",
                "details" => "Reading details",
                "launch" => "Opening app",
                _ => "Copying",
            };
            l.line(
                &frame
                    .map(|f| format!("{} {}", label, crate::progress::bar(crate::progress::Work::Swell, f)))
                    .unwrap_or_else(|| label.into()),
                "",
                None,
                false,
            );
        } else {
            l.blank();
        }
        match &self.page {
            Page::List => {
                l.setting(
                    "Category",
                    if query.trim().is_empty() {
                        self.filter.as_deref().unwrap_or("All apps")
                    } else {
                        "All apps search"
                    },
                    Action::Filter,
                    true,
                );
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
                        l.line(&group, "", None, true);
                        category = group;
                    }
                    let name = if self.preference(&a.id).hidden {
                        format!("hidden: {}", a.name)
                    } else {
                        a.name.clone()
                    };
                    // Desktop-entry roles are concise and localized. Keep the
                    // full comment in Details and search, not every browse row.
                    l.line(&name, &a.generic_name, Some(Action::Launch(a.id.clone())), false);
                }
                l.blank();
                l.line("Manage categories", "", Some(Action::Categories), false);
                l.line(
                    if self.show_hidden { "Hide hidden apps" } else { "Show hidden apps" },
                    "",
                    Some(Action::Hidden),
                    false,
                );
                l.line("Refresh apps", "", Some(Action::Refresh), false);
            }
            Page::Details(id) => {
                let Some(app) = self.entry(id) else {
                    l.text("This application is no longer installed.");
                    return l.rows;
                };
                l.text(if app.description.is_empty() {
                    "No description supplied by the desktop entry."
                } else {
                    &app.description
                });
                if let Some(details) = self.details.get(id) {
                    for (label, key) in [("Version", "version"), ("Installed via", "installed"), ("Source", "source")] {
                        l.field(label, details[key].as_str().unwrap_or("Unavailable"));
                    }
                } else if self.pending.is_none() {
                    l.line("Retry details", "", Some(Action::RetryDetails(id.clone())), false);
                }
                l.blank();
                l.disclosure("Technical details", self.expanded, Action::Technical);
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
                    l.line("Copy launcher path", "", Some(Action::Copy(app.launcher.clone())), false);
                }
                l.blank();
                l.line("Preferences", "", None, true);
                let pref = self.draft(id);
                let category = pref
                    .category
                    .clone()
                    .unwrap_or_else(|| format!("{} (mapped)", self.prefs.category("", &app.categories)));
                l.setting("Category", &category, Action::ChooseCategory(id.clone()), true);
                l.setting(
                    "Visibility",
                    if pref.hidden { "Hidden from Apps" } else { "Shown in Apps" },
                    Action::Visibility(id.clone()),
                    false,
                );
                l.setting("Launch", launch_name(pref.mode()), Action::ChooseLaunch(id.clone()), true);
                l.text(if self.dirty(id) { "Unsaved preferences" } else { "Preferences saved" });
                l.line("Save", "", Some(Action::Save(id.clone())), false);
                l.line("Cancel", "", Some(Action::Discard(id.clone())), false);
                l.blank();
                l.line("Open application", "", Some(Action::Launch(id.clone())), false);
            }
            Page::Filter => {
                l.line("Choose a category", "", None, true);
                l.line("All apps", "", Some(Action::SetFilter(None)), false);
                for c in &self.prefs.categories {
                    l.line(c, "", Some(Action::SetFilter(Some(c.clone()))), false);
                }
            }
            Page::CategoryPicker(id) => {
                l.line("Category preference", "", None, true);
                l.line("Follow category mapping", "", Some(Action::SetCategory(id.clone(), None)), false);
                for c in &self.prefs.categories {
                    l.line(c, "", Some(Action::SetCategory(id.clone(), Some(c.clone()))), false);
                }
            }
            Page::LaunchPicker(id) => {
                l.line("Launch preference", "", None, true);
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
                l.line("Categories", "", None, true);
                for c in &self.prefs.categories {
                    l.disclosure(c, false, Action::Category(c.clone()));
                }
                l.blank();
                l.line("Create category", "", Some(Action::AddCategory), false);
                l.line("Default mappings", "", Some(Action::Mappings), false);
            }
            Page::Category(c) => {
                l.line(c, "", None, true);
                if c != OTHER {
                    l.line("Rename category", "", Some(Action::Rename(c.clone())), false);
                    l.line("Delete category", "", Some(Action::Delete(c.clone())), false);
                } else {
                    l.text("Other is the fallback when no mapping or individual override applies.");
                }
                l.line("Default mappings", "", Some(Action::Mappings), false);
            }
            Page::DeleteCategory(c) => {
                l.text(&format!("Delete {c}? Its mappings and individual category overrides will be removed. Apps use remaining mappings or Other. Visibility and launch preferences stay."));
                l.blank();
                l.line("Delete category", "", Some(Action::ConfirmDelete(c.clone())), false);
            }
            Page::Mappings => {
                l.line("Default category mappings", "", None, true);
                l.text("The first mapped category in a desktop entry wins; an individual override takes precedence.");
                l.blank();
                for (source, target) in &self.prefs.mappings {
                    l.setting(source, target, Action::Mapping(source.clone()), true);
                }
                l.blank();
                l.line("Add mapping", "", Some(Action::AddMapping), false);
            }
            Page::Mapping(source) => {
                l.text(&format!("Map desktop category {source} to:"));
                let target = self
                    .mapping_drafts
                    .get(source)
                    .cloned()
                    .unwrap_or_else(|| self.prefs.mappings.get(source).cloned());
                l.field("Target", target.as_deref().unwrap_or("No mapping"));
                l.blank();
                for c in &self.prefs.categories {
                    l.line(c, "", Some(Action::Map(source.clone(), Some(c.clone()))), false);
                }
                l.blank();
                l.line("Remove mapping", "", Some(Action::Map(source.clone(), None)), false);
                l.text(if self.mapping_dirty(source) { "Unsaved mapping" } else { "Mapping saved" });
                l.line("Save", "", Some(Action::SaveMapping(source.clone())), false);
                l.line("Cancel", "", Some(Action::CancelMapping(source.clone())), false);
            }
            Page::Form(form) => {
                l.text(match form {
                    Form::AddCategory => "Type a new category name in the prompt.",
                    Form::RenameCategory(_) => "Type the new category name in the prompt.",
                    Form::AddMapping => "Type the system desktop category identifier, such as Network, in the prompt.",
                });
                if let Form::RenameCategory(from) = form {
                    l.field("Current name", from);
                }
                l.blank();
                l.line("Save", "", Some(Action::Submit), false);
                l.line("Cancel", "", Some(Action::CancelForm), false);
            }
        }
        l.rows
    }
}
