//! Files' pages as lines, in the row shapes the dialog has everywhere: a heading muted at 2, a row with its
//! words at 4, a value in one muted column, a key chip beside a row. Every label is lowercase; a file's
//! name keeps its spelling.
use super::*;
use crate::scrub::cut_words;

/// The value column, as every page's.
const VALUE_X: u16 = 26;

struct Lines {
    rows: Vec<Line>,
    width: u16,
}

impl Lines {
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
    fn title(&mut self, label: &str) {
        self.rows.push(Line {
            label: label.into(),
            indent: 2,
            title: true,
            ..Line::default()
        });
    }
    /// A row of the menu: its words, a value in the value column where the choice needs saying, the key that
    /// does the same where it has one.
    fn row(&mut self, label: &str, value: &str, action: Action, key: &str) {
        let room = self.width.saturating_sub(VALUE_X + 2) as usize;
        self.rows.push(Line {
            label: cut_words(label, self.width.saturating_sub(6) as usize),
            value: cut_words(value, room),
            value_x: VALUE_X,
            action: Some(action),
            indent: 4,
            value_muted: true,
            key: key.into(),
            ..Line::default()
        });
    }
}

/// A step's words in a list of steps: the provider's own, else its verb.
fn words_of(call: &Call) -> String {
    call.said.clone().unwrap_or_else(|| crate::app::verb_of(&call.name).to_lowercase())
}

/// A step that asks for its name in the prompt: the form's.
fn asks_name(call: &Call) -> bool {
    call.ask.iter().any(|a| a == "name")
}

/// The page narrowed to the rows the typed words name (dialog/DESIGN.md: typing searches the list in front
/// of you): a row stays when its words hold every word typed, a heading only with a row under it, and with
/// no row left the page says so, muted. A form's page keeps its title: the prompt holds the name there.
fn narrowed(rows: Vec<Line>, query: &str) -> Vec<Line> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() || rows.iter().any(|r| r.title) {
        return rows;
    }
    let mut out: Vec<Line> = vec![];
    for r in rows {
        if r.action.is_some() {
            let label = r.label.to_lowercase();
            if words.iter().all(|w| label.contains(w.as_str())) {
                out.push(r);
            }
        } else if r.heading {
            if out.last().is_some_and(|l| l.action.is_some()) {
                out.push(Line::default());
            }
            out.push(r);
        }
    }
    // a heading with nothing under it goes, with the air before it
    while out.last().is_some_and(|l| l.heading || l.label.is_empty()) {
        out.pop();
    }
    if out.is_empty() {
        out.push(Line {
            label: "no action by these words".into(),
            indent: 4,
            muted: true,
            ..Line::default()
        });
    }
    out
}

impl State {
    /// The page as lines, narrowed to the words typed; `check_key` is the key that checks a row, as a chip
    /// beside check.
    pub fn lines(&self, width: u16, check_key: &str, query: &str) -> Vec<Line> {
        narrowed(self.page_lines(width, check_key), query)
    }

    fn page_lines(&self, width: u16, check_key: &str) -> Vec<Line> {
        let mut l = Lines { rows: vec![], width };
        match &self.page {
            Page::List => {}
            Page::Actions(a) => self.actions(&mut l, a, check_key),
            Page::Conflict(c) => {
                let (keep, replace) = match c.verb {
                    Verb::Move => (format!("moved as {}", c.kept_name()), "the one there goes to the trash"),
                    _ => (format!("the copy is named {}", c.kept_name()), "the one there goes to the trash"),
                };
                l.row("skip", "", Action::Answer(Answer::Skip, false), "");
                l.row("keep both", &keep, Action::Answer(Answer::Keep, false), "");
                l.row("replace", replace, Action::Answer(Answer::Replace, false), "");
                let others = c.remaining().saturating_sub(1);
                if others > 0 {
                    l.blank();
                    l.heading(&if others == 1 {
                        "the other too".to_string()
                    } else {
                        format!("the {} others too", others)
                    });
                    l.row("skip all", "", Action::Answer(Answer::Skip, true), "");
                    l.row("keep both for all", "", Action::Answer(Answer::Keep, true), "");
                    l.row("replace all", "", Action::Answer(Answer::Replace, true), "");
                }
            }
            Page::Form(f) => l.title(&f.words),
        }
        l.rows
    }

    fn actions(&self, l: &mut Lines, a: &Actions, check_key: &str) {
        // copy and move: to the other pane while two stand, else the folder is picked as today
        let transfer = |l: &mut Lines, call: &Call, verb: Verb| match &a.other {
            Some(place) => l.row(
                &format!("{} to {}", verb.tool().trim_start_matches("files_"), place),
                "",
                Action::Transfer(verb),
                "",
            ),
            None => l.row(&words_of(call), "", Action::Step(call.clone()), ""),
        };
        if !a.checked.is_empty() {
            // the checked set's: copy, move and trash act on every checked file in the list's order
            let step_of = |verb: Verb| {
                a.checked
                    .iter()
                    .find_map(|r| r.more.iter().chain(r.tool.iter()).find(|c| c.name == verb.tool()).cloned())
            };
            for verb in [Verb::Copy, Verb::Move] {
                match (step_of(verb), &a.other) {
                    (_, Some(place)) => l.row(
                        &format!("{} to {}", verb.tool().trim_start_matches("files_"), place),
                        "",
                        Action::Transfer(verb),
                        "",
                    ),
                    (Some(c), None) => l.row(&words_of(&c), "", Action::Transfer(verb), ""),
                    (None, None) => {}
                }
            }
            if let Some(c) = step_of(Verb::Trash) {
                l.row(&words_of(&c), "", Action::Transfer(Verb::Trash), "");
            }
            l.row("uncheck all", "", Action::UncheckAll, "");
        } else if let Some(row) = &a.row {
            if let Some(c) = &row.children {
                l.row("open", "", Action::Open(c.clone()), "");
            }
            for call in row.tool.iter().chain(row.more.iter()) {
                if call.name == "files_browse" && row.children.is_some() {
                    continue; // a folder's open is the dialog's own; the system file manager is the folder's row below
                }
                if call.name.ends_with("_preview") {
                    l.row(&words_of(call), "", Action::Step(call.clone()), "");
                } else if asks_name(call) {
                    l.row(&words_of(call), "", Action::Ask(call.clone(), words_of(call)), "");
                } else if call.name == Verb::Copy.tool() {
                    transfer(l, call, Verb::Copy);
                } else if call.name == Verb::Move.tool() {
                    transfer(l, call, Verb::Move);
                } else {
                    l.row(&words_of(call), "", Action::Step(call.clone()), "");
                }
            }
            if checkable(row) {
                let word = if self.checked(&row.id) { "uncheck" } else { "check" };
                l.row(word, "", Action::Check(row.id.clone()), check_key);
            }
        }
        if !l.rows.is_empty() {
            l.blank();
        }
        l.heading("this folder");
        for call in &a.folder {
            if call.name == "files_browse" {
                continue; // after two panes, as the mock has it
            }
            if asks_name(call) {
                l.row(&words_of(call), "", Action::Ask(call.clone(), words_of(call)), "");
            } else {
                l.row(&words_of(call), "", Action::Step(call.clone()), "");
            }
        }
        let two = a.other.is_some() || self.other.is_some();
        l.row(if two { "one pane" } else { "two panes" }, "", Action::Panes(!two), "");
        let browse = a.folder.iter().find(|c| c.name == "files_browse").cloned().or_else(|| {
            a.browse.as_ref().map(|path| {
                let mut arguments = serde_json::Map::new();
                arguments.insert("path".into(), serde_json::Value::String(path.clone()));
                Call {
                    name: "files_browse".into(),
                    arguments,
                    ask: vec![],
                    said: Some("open in the system file manager".into()),
                    pick: None,
                }
            })
        });
        if let Some(call) = browse {
            l.row(&words_of(&call), "", Action::Step(call), "");
        }
    }
}
