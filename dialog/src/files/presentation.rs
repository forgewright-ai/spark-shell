//! Files' pages as lines, in the row shapes the dialog has everywhere: a row with its words at 4, its key at
//! the right, muted. Every label is lowercase; a file's name keeps its spelling.
use super::*;
use crate::app::HintKey;
use crate::keys::Bindings;
use crate::scrub::cut_words;

/// The steps the menu writes in its own places (dialog/DESIGN.md, F9); what else a row offers follows them.
const MENU_HOLDS: [&str; 9] = [
    "files_open",
    "files_app",
    "files_preview",
    "files_rename",
    "files_copy",
    "files_move",
    "files_trash",
    "files_attach",
    "files_reveal",
];

struct Lines {
    rows: Vec<Line>,
    width: u16,
}

impl Lines {
    /// A row of the menu: its words, the key that does the same where it has one.
    fn row(&mut self, label: &str, action: Action, key: &str) {
        self.rows.push(Line {
            label: cut_words(label, self.width.saturating_sub(6) as usize),
            action: Some(action),
            indent: 4,
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
/// of you): a row stays when its words hold every word typed, and with no row left the page says so, muted.
fn narrowed(rows: Vec<Line>, query: &str) -> Vec<Line> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() {
        return rows;
    }
    let mut out: Vec<Line> = rows
        .into_iter()
        .filter(|r| {
            let label = r.label.to_lowercase();
            r.action.is_some() && words.iter().all(|w| label.contains(w.as_str()))
        })
        .collect();
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
    /// The page as lines, narrowed to the words typed; `keys` names the key a row's shortcut is bound to. A form has
    /// none: the list stands behind it.
    pub fn lines(&self, width: u16, keys: &Bindings, query: &str) -> Vec<Line> {
        if self.form() {
            return vec![];
        }
        narrowed(self.page_lines(width, keys), query)
    }

    /// Whether an actions page would hold a row to act on.
    pub fn offers(&self, a: &Actions, keys: &Bindings) -> bool {
        let mut l = Lines { rows: vec![], width: 60 };
        self.actions(&mut l, a, keys);
        l.rows.iter().any(|r| r.action.is_some())
    }

    fn page_lines(&self, width: u16, keys: &Bindings) -> Vec<Line> {
        let mut l = Lines { rows: vec![], width };
        match &self.page {
            Page::List | Page::Form(_) => {}
            Page::Actions(a) => self.actions(&mut l, a, keys),
            Page::Conflict(c) => {
                // one list; the `all` rows only while more remain
                let more = c.remaining() > 1;
                l.row("replace", Action::Answer(Answer::Replace, false), "");
                if more {
                    l.row("replace all", Action::Answer(Answer::Replace, true), "");
                }
                l.row("skip", Action::Answer(Answer::Skip, false), "");
                if more {
                    l.row("skip all", Action::Answer(Answer::Skip, true), "");
                }
                l.row("keep both", Action::Answer(Answer::Keep, false), "");
            }
        }
        l.rows
    }

    /// The menu (dialog/DESIGN.md, F9): the row's actions in one order whatever the provider's, each with its key at
    /// the right; what the provider offers beyond them (a trashed file's restore, its delete for good) after them; a
    /// blank row; the folder's.
    fn actions(&self, l: &mut Lines, a: &Actions, keys: &Bindings) {
        let k = |h: HintKey| keys.label(h).to_string();
        if !a.checked.is_empty() {
            let holds = |verb: Verb| a.checked.iter().any(|r| r.tool.iter().chain(r.more.iter()).any(|c| c.name == verb.tool()));
            if holds(Verb::Copy) {
                l.row("copy", Action::Transfer(Verb::Copy), &k(HintKey::Copy));
            }
            if holds(Verb::Move) {
                l.row("move", Action::Transfer(Verb::Move), &k(HintKey::Move));
            }
            l.row("copy path", Action::CopyPath, &k(HintKey::CopyPath));
            if holds(Verb::Trash) {
                l.row("trash", Action::Transfer(Verb::Trash), &k(HintKey::Trash));
            }
            l.row("deselect all", Action::UncheckAll, "");
        } else if let Some(row) = &a.row {
            self.row_actions(l, row, keys);
        }
        let start = l.rows.len();
        // the folder's door to the system file manager closes its steps: the provider holds it to where one is
        // configured, so the step decides, never the tool's being listed
        let browse = |c: &&Call| c.name == "files_browse";
        for call in a.folder.iter().filter(|c| !browse(c)).chain(a.folder.iter().filter(browse)) {
            let (word, key) = match call.name.as_str() {
                "files_new_folder" => ("new folder".to_string(), k(HintKey::New)),
                "files_new_text" => ("new file".to_string(), String::new()),
                _ => (words_of(call), String::new()),
            };
            let action = if asks_name(call) {
                Action::Ask(call.clone(), word.clone())
            } else {
                Action::Step(call.clone())
            };
            l.row(&word, action, &key);
        }
        if self.other.is_some() {
            l.row("close pane", Action::ClosePane, "");
        }
        if start > 0 && l.rows.len() > start {
            l.rows.insert(start, Line::default());
        }
    }

    fn row_actions(&self, l: &mut Lines, row: &Row, keys: &Bindings) {
        let k = |h: HintKey| keys.label(h).to_string();
        let step = |name: &str| row.tool.iter().chain(row.more.iter()).find(|c| c.name == name);
        let enter = k(HintKey::Enter);
        if let Some(c) = &row.children {
            l.row("open", Action::Open(c.clone()), &enter);
        } else if let Some(t) = row.tool.as_ref() {
            let word = if t.name == "files_open" { "open".to_string() } else { words_of(t) };
            l.row(&word, Action::Step(t.clone()), &enter);
        }
        if let Some(c) = step("files_app") {
            l.row("open in app", Action::Step(c.clone()), &k(HintKey::Open));
        }
        if row.page.is_some() {
            l.row("view", Action::View, &k(HintKey::View));
        }
        for name in ["files_attach", "files_reveal"] {
            if let Some(c) = step(name) {
                l.row(&words_of(c), Action::Step(c.clone()), "");
            }
        }
        if let Some(c) = step("files_rename") {
            l.row("rename", Action::Ask(c.clone(), "rename".into()), &k(HintKey::Rename));
        }
        if step(Verb::Copy.tool()).is_some() {
            l.row("copy", Action::Transfer(Verb::Copy), &k(HintKey::Copy));
        }
        if step(Verb::Move.tool()).is_some() {
            l.row("move", Action::Transfer(Verb::Move), &k(HintKey::Move));
        }
        if path_of(row).is_some() {
            l.row("copy path", Action::CopyPath, &k(HintKey::CopyPath));
        }
        if step(Verb::Trash.tool()).is_some() {
            l.row("trash", Action::Transfer(Verb::Trash), &k(HintKey::Trash));
        }
        if checkable(row) {
            l.row("select", Action::Check(row.id.clone()), &k(HintKey::Select));
        }
        for call in row.more.iter().filter(|c| !MENU_HOLDS.contains(&c.name.as_str())) {
            if asks_name(call) {
                l.row(&words_of(call), Action::Ask(call.clone(), words_of(call)), "");
            } else {
                l.row(&words_of(call), Action::Step(call.clone()), "");
            }
        }
    }
}
