//! Apps: the applications installed, browsed, searched and opened inside home, drawn with the dialog's own
//! rows. A change to a preference applies at once and Undo on the status row takes it back; nothing is a
//! draft, and nothing asks before you leave.
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
    /// The name as the desktop entry writes it: supplied, and kept in its spelling.
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
            name: scrub(v["name"].as_str()?),
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

/// The pages: the list, the hidden apps, an app's details and its technical details, the lists a choice
/// opens, the categories and their mappings, and a form that types in the prompt.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum Page {
    #[default]
    List,
    Hidden,
    Details(String),
    Technical(String),
    Filter,
    CategoryPicker(String),
    LaunchPicker(String),
    Categories,
    Category(String),
    Mappings,
    Mapping(String),
    Form(Form),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    Launch(String),
    Details(String),
    Technical(String),
    Filter,
    SetFilter(Option<String>),
    Hidden,
    Categories,
    Category(String),
    Rename(String),
    Delete(String),
    AddCategory,
    Mappings,
    Mapping(String),
    Map(String, Option<String>),
    AddMapping,
    Submit,
    ChooseCategory(String),
    SetCategory(String, Option<String>),
    Visibility(String),
    ChooseLaunch(String),
    SetLaunch(String, String),
    Refresh,
    Copy(String),
    RetryDetails(String),
    /// The preferences as they were before the last change: Undo on the status row.
    Undo(Box<Preferences>),
}

/// One line of a page, in the row shapes the dialog has: a group's heading, the page's subject, a note,
/// a fact (a label and a value, no action), or a row with a sign, a label, a value and an arrow. A switch
/// is a row whose sign is a dot or a ring and whose value is on or off, drawn at the value column as a
/// setting's is.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Line {
    pub sign: &'static str,
    pub label: String,
    pub value: String,
    pub value_x: u16,
    pub tail: String,
    pub action: Option<Action>,
    pub indent: u16,
    pub heading: bool,
    pub title: bool,
    pub muted: bool,
    pub value_muted: bool,
    /// A wrapped value's next line: one target with the line it continues.
    pub continuation: bool,
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
    /// The notice's change can be taken back: Undo stands at its end.
    pub undo: bool,
    pub copy: Option<String>,
}

pub struct State {
    pub entries: Vec<Entry>,
    pub prefs: Preferences,
    pub path: PathBuf,
    pub preference_error: Option<String>,
    pub page: Page,
    pub filter: Option<String>,
    pub details: BTreeMap<String, Value>,
    pub loaded: bool,
    pub failed: bool,
    pub pending: Option<(u64, String)>,
    /// When the pending operation began, and the app a launch is of, lowercase: the status row says "opening NAME"
    /// with the march once the wait is felt (dialog/DESIGN.md).
    pub pending_since: Option<std::time::Instant>,
    pub pending_name: String,
    pub serial: u64,
    /// The preferences before the last change, while Undo stands on the status row.
    pub undo: Option<Preferences>,
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
            details: BTreeMap::new(),
            loaded: false,
            failed: false,
            pending: None,
            pending_since: None,
            pending_name: String::new(),
            serial: 0,
            undo: None,
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
    pub fn entry(&self, id: &str) -> Option<&Entry> {
        self.entries.iter().find(|a| a.id == id)
    }
    /// An app's category: its own choice, else the first of its desktop categories that is mapped, else Other.
    pub fn category_of(&self, a: &Entry) -> String {
        self.prefs.category(&a.id, &a.categories)
    }

    fn sorted<'a>(&self, apps: impl Iterator<Item = &'a Entry>) -> Vec<&'a Entry> {
        let mut apps: Vec<&Entry> = apps.collect();
        apps.sort_by_key(|a| {
            (
                self.prefs.categories.iter().position(|c| *c == self.category_of(a)).unwrap_or(usize::MAX),
                a.name.to_lowercase(),
                a.id.clone(),
            )
        });
        apps
    }

    /// The apps shown: never a hidden one; the category filtered while nothing is typed, every category for words.
    pub fn visible(&self, query: &str) -> Vec<&Entry> {
        let words = query.to_lowercase();
        self.sorted(self.entries.iter().filter(|a| {
            if self.preference(&a.id).hidden {
                return false;
            }
            if words.trim().is_empty() {
                self.filter.as_ref().is_none_or(|c| *c == self.category_of(a))
            } else {
                let text = format!("{} {} {} {}", a.name, a.display_name, a.generic_name, a.description).to_lowercase();
                words.split_whitespace().all(|w| text.contains(w))
            }
        }))
    }

    /// The apps hidden, a list of their own.
    pub fn hidden(&self) -> Vec<&Entry> {
        self.sorted(self.entries.iter().filter(|a| self.preference(&a.id).hidden))
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

    /// Whether a page stands under this one to go back to.
    pub fn has_back(&self) -> bool {
        !self.stack.is_empty()
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

    /// A change applied at once: saved, said in a few words, and Undo stands for it.
    fn change(&mut self, prefs: Preferences, words: String, out: &mut Outcome) -> Result<(), String> {
        let before = self.prefs.clone();
        self.save(prefs)?;
        self.undo = Some(before);
        out.notice = Some(words);
        out.undo = true;
        Ok(())
    }

    fn pref_mut<'a>(prefs: &'a mut Preferences, id: &str, current: Preference) -> &'a mut Preference {
        prefs.apps.entry(id.to_string()).or_insert(current);
        prefs.apps.get_mut(id).unwrap()
    }

    pub fn activate(&mut self, action: Action, nav: Navigation) -> Result<Outcome, String> {
        let mut out = Outcome::default();
        // a receipt names the app as a label, lowercase (dialog/DESIGN.md)
        let name = |s: &Self, id: &str| s.entry(id).map(|a| a.name.to_lowercase()).unwrap_or_else(|| id.to_string());
        match action {
            Action::Launch(id) => {
                if self.pending.is_some() {
                    return Err("wait for the current Apps operation".into());
                }
                let app = self.entry(&id).ok_or("this application is no longer available")?;
                let pref = self.preference(&id);
                if pref.mode() == "focus" && !app.focus {
                    return Err("focus existing is unavailable here; choose application default in its details".into());
                }
                if pref.mode() == "new" && !app.new_window {
                    return Err("new window is no longer declared; choose application default in its details".into());
                }
                out.request = Some(json!({"op":"launch","id":id,"mode":pref.mode()}));
            }
            Action::Details(id) => {
                if self.pending.is_some() {
                    return Err("wait for the current Apps operation".into());
                }
                self.entry(&id).ok_or("this application is no longer available")?;
                out.navigation = Some(self.navigate(Page::Details(id.clone()), nav));
                // the cached facts stay readable while fresh ones come: packages and windows change
                out.request = Some(json!({"op":"details","id":id}));
            }
            Action::Technical(id) => out.navigation = Some(self.navigate(Page::Technical(id), nav)),
            Action::Filter => out.navigation = Some(self.navigate(Page::Filter, nav)),
            Action::SetFilter(category) => {
                self.filter = category;
                out.navigation = self.back().map(|n| Navigation {
                    selected: 0,
                    in_list: false,
                    scroll: 0,
                    ..n
                });
            }
            Action::Hidden => out.navigation = Some(self.navigate(Page::Hidden, nav)),
            Action::Categories => out.navigation = Some(self.navigate(Page::Categories, nav)),
            Action::Category(name) => out.navigation = Some(self.navigate(Page::Category(name), nav)),
            Action::Rename(name) => out.navigation = Some(self.navigate(Page::Form(Form::RenameCategory(name)), nav)),
            Action::AddCategory => out.navigation = Some(self.navigate(Page::Form(Form::AddCategory), nav)),
            Action::AddMapping => out.navigation = Some(self.navigate(Page::Form(Form::AddMapping), nav)),
            Action::Mappings => out.navigation = Some(self.navigate(Page::Mappings, nav)),
            Action::Mapping(name) => out.navigate_to(self, Page::Mapping(name), nav),
            Action::Map(source, target) => {
                let mut prefs = self.prefs.clone();
                let words = match &target {
                    Some(t) => {
                        prefs.mappings.insert(source.clone(), t.clone());
                        format!("{} maps to {}", source, t.to_lowercase())
                    }
                    None => {
                        prefs.mappings.remove(&source);
                        format!("{} unmapped", source)
                    }
                };
                self.change(prefs, words, &mut out)?;
                out.navigation = self.back();
            }
            Action::Submit => {
                let typed = nav.query.trim().to_string();
                match self.page.clone() {
                    Page::Form(Form::AddCategory) => {
                        let mut prefs = self.prefs.clone();
                        prefs.add(&typed)?;
                        self.change(prefs, format!("{} added", typed.to_lowercase()), &mut out)?;
                        out.navigation = self.back();
                    }
                    Page::Form(Form::RenameCategory(from)) => {
                        let mut prefs = self.prefs.clone();
                        prefs.rename(&from, &typed)?;
                        let filtered = self.filter.as_deref() == Some(from.as_str());
                        self.change(prefs, format!("{} renamed to {}", from.to_lowercase(), typed.to_lowercase()), &mut out)?;
                        if filtered {
                            self.filter = Some(typed.clone());
                        }
                        // back to the category's own page, under its new name
                        self.back();
                        self.page = Page::Category(typed);
                        out.navigation = Some(Navigation::default());
                    }
                    Page::Form(Form::AddMapping) => {
                        if typed.is_empty() || typed.len() > 80 || !typed.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
                            return Err("use a desktop category identifier, such as Network".into());
                        }
                        self.page = Page::Mapping(typed);
                        out.navigation = Some(Navigation::default());
                    }
                    _ => {}
                }
            }
            Action::Delete(name) => {
                let mut prefs = self.prefs.clone();
                prefs.delete(&name)?;
                self.change(prefs, format!("{} deleted", name.to_lowercase()), &mut out)?;
                if matches!(&self.page, Page::Category(c) if *c == name) {
                    out.navigation = self.back();
                }
            }
            Action::ChooseCategory(id) => out.navigation = Some(self.navigate(Page::CategoryPicker(id), nav)),
            Action::ChooseLaunch(id) => out.navigation = Some(self.navigate(Page::LaunchPicker(id), nav)),
            Action::SetCategory(id, category) => {
                let current = self.preference(&id);
                if current.category != category {
                    let mut prefs = self.prefs.clone();
                    Self::pref_mut(&mut prefs, &id, current).category = category.clone();
                    let words = match &category {
                        Some(c) => format!("{} in {}", name(self, &id), c.to_lowercase()),
                        None => format!("{} as mapped", name(self, &id)),
                    };
                    self.change(prefs, words, &mut out)?;
                }
                out.navigation = self.back();
            }
            Action::SetLaunch(id, launch) => {
                let current = self.preference(&id);
                if current.mode() != launch {
                    let mut prefs = self.prefs.clone();
                    Self::pref_mut(&mut prefs, &id, current).launch = launch.clone();
                    let words = format!("{}: {}", name(self, &id), launch_name(&launch));
                    self.change(prefs, words, &mut out)?;
                }
                out.navigation = self.back();
            }
            Action::Visibility(id) => {
                let current = self.preference(&id);
                let hidden = !current.hidden;
                let mut prefs = self.prefs.clone();
                Self::pref_mut(&mut prefs, &id, current).hidden = hidden;
                let words = format!("{} {}", name(self, &id), if hidden { "hidden" } else { "shown" });
                self.change(prefs, words, &mut out)?;
            }
            Action::Undo(prefs) => {
                self.save(*prefs)?;
                self.undo = None;
                out.notice = Some("put back".into());
            }
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
                    .ok_or("invalid native Apps catalog")?
                    .iter()
                    .filter_map(Entry::read)
                    .collect();
                self.loaded = true;
                self.failed = false;
                self.details.clear();
            }
            "details" => {
                let id = value["id"].as_str().ok_or("invalid application details")?.to_string();
                self.details.insert(id, value);
            }
            "launch" => return Ok(Some(scrub(value["message"].as_str().unwrap_or("launch outcome is unavailable")))),
            "copy" => return Ok(Some("copied".into())),
            _ => return Err("unknown Apps operation result".into()),
        }
        Ok(None)
    }
}

impl Outcome {
    fn navigate_to(&mut self, state: &mut State, page: Page, nav: Navigation) {
        self.navigation = Some(state.navigate(page, nav));
    }
}

pub fn launch_name(mode: &str) -> &str {
    match mode {
        "focus" => "focus existing",
        "new" => "new window",
        _ => "application default",
    }
}
