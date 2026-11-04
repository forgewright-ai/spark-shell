//! Apps owns browsing, Details and local preferences inside home's shared frame.
pub mod preferences;
mod presentation;
mod surface;

use crate::scrub::scrub;
use preferences::{Preference, Preferences, OTHER};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub display_name: String,
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
            display_name: scrub(v["display_name"].as_str().unwrap_or("")),
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
            Self::Launch(_) => "open",
            Self::Save(_) | Self::SaveMapping(_) | Self::Submit => "save",
            Self::Copy(_) => "copy",
            Self::ConfirmDelete(_) => "delete",
            Self::Hidden | Self::Visibility(_) | Self::Technical => "change",
            Self::SetCategory(..) | Self::SetLaunch(..) | Self::SetFilter(_) | Self::Map(..) => "set",
            Self::Discard(_) | Self::CancelForm | Self::CancelMapping(_) => "cancel",
            Self::Refresh | Self::RetryDetails(_) => "retry",
            _ => "choose",
        }
    }
}

/// A composed content line. Only its action makes it selectable. Wrapped values
/// retain their original data in the model, independent of drawing and copying.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Line {
    pub label: String,
    pub value: String,
    pub value_x: u16,
    pub action: Option<Action>,
    pub bold: bool,
    pub indent: u16,
    pub tail: String,
    pub continuation: bool,
    /// A second independently focusable control sharing the previous row.
    pub inline: bool,
    pub bounds: Option<(u16, u16)>,
    pub toggle: Option<bool>,
    pub underline: bool,
    pub muted: bool,
    pub value_muted: bool,
    pub disabled: bool,
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
        self.prefs.apps.get(id).cloned().unwrap_or_else(|| Preference {
            hidden: matches!(id, "footclient.desktop" | "foot-server.desktop"),
            ..Preference::default()
        })
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
                    let text = format!("{} {} {} {}", a.name, a.display_name, a.generic_name, a.description).to_lowercase();
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
                out.navigation = Some(Navigation { scroll: 0, ..nav });
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
                if !self.dirty(&id) {
                    return Ok(out);
                }
                let mut prefs = self.prefs.clone();
                prefs.apps.insert(id.clone(), self.draft(&id));
                self.save(prefs)?;
                self.drafts.remove(&id);
                out.notice = Some("Apps preferences saved".into());
            }
            Action::Discard(id) => {
                if !self.dirty(&id) {
                    return Ok(out);
                }
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
        "focus" => "focus existing",
        "new" => "new window",
        _ => "application default",
    }
}
