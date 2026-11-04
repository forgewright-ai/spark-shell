//! Shared draft ownership and guarded navigation. Features supply persistence;
//! home owns the decision and resumes the requested navigation only on success.
use crate::app::{App, Item, Mode, View};
use crate::apps::{Action, Navigation, Page};

#[derive(Default)]
pub struct Prompts {
    request: String,
    queries: Vec<(View, String)>,
}

impl Prompts {
    fn request_view(view: &View) -> bool {
        matches!(view, View::Home | View::Conversation | View::Models)
    }
    pub fn save(&mut self, view: &View, text: &str) {
        if Self::request_view(view) {
            self.request = text.into();
        } else {
            self.queries.retain(|(v, _)| v != view);
            self.queries.push((view.clone(), text.into()));
        }
    }
    pub fn restore(&self, view: &View) -> String {
        if Self::request_view(view) {
            self.request.clone()
        } else {
            self.queries.iter().find(|(v, _)| v == view).map(|(_, s)| s.clone()).unwrap_or_default()
        }
    }
}

#[derive(Clone, Debug)]
pub enum LeaveIntent {
    Back,
    Close,
    Conversation,
    Go(View),
    Attach,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Choice {
    Save,
    Discard,
    Keep,
}
impl Choice {
    pub fn label(&self) -> &str {
        match self {
            Self::Save => "Save",
            Self::Discard => "Discard",
            Self::Keep => "Keep editing",
        }
    }
}

#[derive(Clone)]
enum EditOwner {
    App(String),
    CategoryForm,
    Mapping(String),
}

pub struct LeaveDecision {
    intent: LeaveIntent,
    owner: EditOwner,
    navigation: Navigation,
}

impl App {
    /// Only what was typed at rest is a draft. An answer to a question, a
    /// password or a pairing code among them, is never kept, and a draft never
    /// takes the place of an answer being typed.
    pub(crate) fn prompt_depart(&mut self) {
        if self.mode == Mode::Normal {
            self.prompts.save(&self.view, &self.input);
        }
    }
    pub(crate) fn prompt_arrive(&mut self) {
        if self.mode == Mode::Normal {
            self.set_input(self.prompts.restore(&self.view));
        }
    }

    /// The pointer moved, over row `pick` or over none. Everywhere else a
    /// motion only draws: Enter stays with the keyboard's row or the words
    /// typed. Apps follows it, so its shortcuts act on the row under the
    /// pointer; a decision waiting keeps its safe choice.
    pub fn pointer_over(&mut self, pick: Option<usize>) {
        if self.view != View::Apps || self.leave_decision.is_some() {
            return;
        }
        // Pointer movement must not move the visible target by dropping the
        // keyboard selection's scroll position.
        self.scroll = crate::ui::body_scroll(self);
        if let Some(n) = pick {
            self.chip_focus = None;
            self.light(n);
        }
    }

    /// Only normal request text may be sent. A module filter is never a request.
    pub fn request_prompt(&self) -> bool {
        !matches!(self.view, View::Apps | View::Folder(..)) && self.mode == Mode::Normal && self.leave_decision.is_none()
    }

    pub(crate) fn guard_leave(&mut self, intent: LeaveIntent) -> bool {
        if self.leave_decision.is_some() {
            return true;
        }
        if self.view != View::Apps || self.mode != Mode::Normal {
            return false;
        }
        let owner = match &self.apps.page {
            Page::Form(_) if !self.input.is_empty() => Some(EditOwner::CategoryForm),
            Page::Mapping(source) if self.apps.mapping_dirty(source) => Some(EditOwner::Mapping(source.clone())),
            Page::Details(id) | Page::CategoryPicker(id) | Page::LaunchPicker(id) if self.apps.dirty(id) => Some(EditOwner::App(id.clone())),
            _ => None,
        };
        let Some(owner) = owner else { return false };
        self.leave_decision = Some(LeaveDecision {
            intent,
            owner,
            navigation: self.apps_navigation(),
        });
        self.reply = None;
        self.in_list = true;
        self.sel = 2; // Keep editing is the safe initial choice.
        self.scroll = 0;
        self.chip_focus = None;
        true
    }

    pub fn leave_choice(&mut self, choice: Choice) {
        let Some(decision) = self.leave_decision.take() else { return };
        self.apps_restore(decision.navigation.clone());
        if choice == Choice::Keep {
            return;
        }
        let result = match (&decision.owner, &choice) {
            (EditOwner::Mapping(source), Choice::Save) => self.apps.activate(Action::SaveMapping(source.clone()), self.apps_navigation()),
            (EditOwner::Mapping(source), Choice::Discard) => self.apps.activate(Action::CancelMapping(source.clone()), self.apps_navigation()),
            (EditOwner::App(id), Choice::Save) => self.apps.activate(Action::Save(id.clone()), self.apps_navigation()),
            (EditOwner::App(id), Choice::Discard) => self.apps.activate(Action::Discard(id.clone()), self.apps_navigation()),
            (EditOwner::CategoryForm, Choice::Save) => self.apps.activate(Action::Submit, self.apps_navigation()),
            (EditOwner::CategoryForm, Choice::Discard) => {
                self.set_input(String::new());
                Ok(Default::default())
            }
            _ => unreachable!(),
        };
        let mut returned = false;
        match result {
            Err(error) => {
                // The form, focus and field are intact; retry or cancel locally.
                self.refuse(&error);
                return;
            }
            Ok(out) => {
                if let Some(nav) = out.navigation {
                    returned = true;
                    self.apps_restore(nav);
                }
            }
        }
        // A mapping added here still wants its category: nothing is saved yet,
        // so stay for it rather than leave with the choice lost.
        if matches!(decision.owner, EditOwner::CategoryForm) && matches!(self.apps.page, Page::Mapping(_)) {
            return;
        }
        match decision.intent {
            LeaveIntent::Back if returned => {} // The feature already returned.
            LeaveIntent::Back => self.escape(),
            LeaveIntent::Close => self.close_window(),
            LeaveIntent::Conversation => self.conversation(),
            LeaveIntent::Go(view) => self.go(view),
            LeaveIntent::Attach => self.chip(0),
        }
    }

    pub(crate) fn decision_items(&self) -> Vec<Item> {
        vec![
            Item::Heading("Unsaved changes".into()),
            Item::Text("Save before leaving?".into(), false),
            Item::Blank,
            Item::Leave(Choice::Save),
            Item::Leave(Choice::Discard),
            Item::Leave(Choice::Keep),
        ]
    }
}
