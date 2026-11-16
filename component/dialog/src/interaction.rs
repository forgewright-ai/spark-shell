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

#[cfg(test)]
mod tests {
    use crate::app::{App, Config, Mode, View, CALENDAR_DEST};

    fn pairing() -> Mode {
        Mode::Pair {
            prov: 0,
            id: serde_json::json!(1),
            message: "the code".into(),
            kind: "pin".into(),
        }
    }

    /// The guard itself, whatever doors the frame has: what is typed as an answer is not saved when the view is
    /// left, so it cannot come back as words; and a draft kept for a view does not land on an answer being typed.
    #[test]
    fn an_answer_is_never_saved_as_a_draft_and_a_draft_never_replaces_an_answer() {
        let place = View::Dest(CALENDAR_DEST);
        // at rest a draft is kept for its view and comes back: without this the two checks below prove nothing
        let mut app = App::new(Config::default(), &[]);
        app.view = place.clone();
        app.set_draft("dentist");
        app.prompt_depart();
        app.set_draft("");
        app.prompt_arrive();
        assert_eq!(app.input, "dentist", "a draft typed at rest is kept for its view");

        // a pairing code typed as an answer: leaving the view saves nothing of it
        let mut app = App::new(Config::default(), &[]);
        app.view = place.clone();
        app.mode = pairing();
        app.set_draft("123456");
        app.prompt_depart();
        app.mode = Mode::Normal;
        app.set_draft("");
        app.prompt_arrive();
        assert!(app.input.is_empty(), "the code came back as words: {}", app.input);

        // a draft kept for the view never takes the place of an answer being typed there
        let mut app = App::new(Config::default(), &[]);
        app.view = place;
        app.set_draft("dentist");
        app.prompt_depart();
        app.mode = pairing();
        app.set_draft("12");
        app.prompt_arrive();
        assert_eq!(app.input, "12", "the answer being typed is left alone");
    }
}
