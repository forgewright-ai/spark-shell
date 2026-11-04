//! The prompt's drafts by view: the request the home, the conversation and the model list share, and a
//! filter of its own for a place that filters its list by what is typed.
use crate::app::{App, Mode, View};

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

    /// Only normal request text may be sent. A module filter is never a request.
    pub fn request_prompt(&self) -> bool {
        !matches!(self.view, View::Apps | View::Folder(..)) && self.mode == Mode::Normal
    }
}
