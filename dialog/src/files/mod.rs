//! Files: the manager's own state inside the folder list (dialog/DESIGN.md, "Files"): the checks on
//! several rows, the actions page of a row or of the checked set, the second pane beside the first, the
//! batch that copies, moves or trashes the checked files one after another, the page of choices a
//! conflict opens, and the form rename and new folder type in the prompt. The folder list itself stays
//! the dialog's View::Folder: this module adds to it and draws nothing new.
mod presentation;
mod surface;

use crate::app::{Step, View};
use crate::model::{Call, Row, Rows};
use std::time::Instant;

pub use crate::page::Navigation;

pub type Line = crate::page::Line<Action>;

/// What a batch does to each file, and the words of it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Verb {
    Copy,
    Move,
    Trash,
    /// The batch's undo: every step taken back, newest first.
    PutBack,
}

impl Verb {
    pub fn doing(self) -> &'static str {
        match self {
            Verb::Copy => "copying",
            Verb::Move => "moving",
            Verb::Trash => "trashing",
            Verb::PutBack => "putting back",
        }
    }
    pub fn done(self) -> &'static str {
        match self {
            Verb::Copy => "copied",
            Verb::Move => "moved",
            Verb::Trash => "trashed",
            Verb::PutBack => "put back",
        }
    }
    /// The provider's tool a row's steps hold for it.
    pub fn tool(self) -> &'static str {
        match self {
            Verb::Copy => "files_copy",
            Verb::Move => "files_move",
            Verb::Trash => "files_trash",
            Verb::PutBack => "",
        }
    }
}

/// A choice on the conflict page.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Answer {
    Skip,
    Keep,
    Replace,
}

/// One file of a copy or a move: its step, its name and size, and the answer where its name is in the
/// destination already.
#[derive(Clone, Debug, PartialEq)]
pub struct Transfer {
    /// None for a row that has no step for the verb: refused by name, never run.
    pub step: Option<Step>,
    pub name: String,
    pub size: u64,
    pub conflict: bool,
    pub answer: Option<Answer>,
    pub refused: Option<String>,
}

/// The conflicts of a copy or a move, asked one by one before it starts.
#[derive(Clone, Debug, PartialEq)]
pub struct Conflicts {
    pub verb: Verb,
    pub dest_title: String,
    pub items: Vec<Transfer>,
    /// The names already in the destination: a kept copy takes the next free number among them.
    pub taken: Vec<String>,
    /// The conflict being asked: an index into items.
    pub at: usize,
}

impl Conflicts {
    /// The conflicts not answered yet, the one asked included.
    pub fn remaining(&self) -> usize {
        self.items.iter().filter(|t| t.conflict && t.answer.is_none()).count()
    }
    pub fn current(&self) -> Option<&Transfer> {
        self.items.get(self.at)
    }
    /// The name a kept copy of the current file takes.
    pub fn kept_name(&self) -> String {
        self.current().map(|t| numbered(&t.name, &self.taken)).unwrap_or_default()
    }
}

/// The actions page: of one row, of the folder alone (`..`, the summary row), or of the checked set.
#[derive(Clone, Debug, PartialEq)]
pub struct Actions {
    pub row: Option<Row>,
    pub checked: Vec<Row>,
    /// The folder's own actions: the summary row's steps, and the rows of the "this folder" group.
    pub folder: Vec<Call>,
    /// The folder's path where the provider offers files_browse and no folder action holds it already.
    pub browse: Option<String>,
    /// The other pane's place while two panes stand: copy and move go there.
    pub other: Option<String>,
    pub title: String,
}

/// A form typed in the prompt: the step waiting for its name.
#[derive(Clone, Debug, PartialEq)]
pub struct Form {
    pub step: Step,
    pub field: String,
    /// The action's words: the header and the title.
    pub words: String,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub enum Page {
    #[default]
    List,
    Actions(Box<Actions>),
    Conflict(Box<Conflicts>),
    Form(Box<Form>),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    /// A folder's children: opened in the active pane.
    Open(String),
    /// A provider's step of the row, run as a pick: a preview step opens the preview.
    Step(Call),
    /// A step that asks for a name: the form.
    Ask(Call, String),
    Check(String),
    UncheckAll,
    Panes(bool),
    /// Copy, move or trash: the lit row to the other pane, or the checked set.
    Transfer(Verb),
    /// The conflict page's choice, for this file or for all.
    Answer(Answer, bool),
}

/// The passive pane while two stand: what the active pane would be, kept aside.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Pane {
    pub uri: String,
    pub rows: Option<Rows>,
    pub sel: usize,
    pub scroll: usize,
    pub in_list: bool,
    pub checks: Vec<String>,
    pub came_from: Vec<View>,
}

impl Pane {
    pub fn title(&self) -> String {
        self.rows.as_ref().map(|r| r.title.clone()).unwrap_or_default()
    }
    /// Its folder's path: None for the trash, a search, or rows not read yet.
    pub fn here(&self) -> Option<String> {
        self.rows.as_ref().and_then(|r| r.here.clone())
    }
}

/// Which side the other pane stands on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
}

/// A batch under way: one step a file through the queue, tracked here for the march and the receipt.
#[derive(Clone, Debug, PartialEq)]
pub struct Batch {
    pub verb: Verb,
    pub dest_title: Option<String>,
    pub total: usize,
    /// The calls still to run or running: (the call, the file's name, its size).
    pub steps: Vec<(Call, String, u64)>,
    pub done: Vec<(String, Result<(), String>)>,
    pub skipped: usize,
    pub stopped: usize,
    pub stopping: bool,
    /// When the step under way began: the march shows once the wait is felt.
    pub since: Instant,
    pub current: Option<String>,
    pub size: u64,
    pub undos: Vec<Step>,
}

impl Batch {
    pub fn new(verb: Verb, dest_title: Option<String>, steps: Vec<(Call, String, u64)>, skipped: usize) -> Batch {
        Batch {
            verb,
            dest_title,
            total: steps.len(),
            steps,
            done: vec![],
            skipped,
            stopped: 0,
            stopping: false,
            since: Instant::now(),
            current: None,
            size: 0,
            undos: vec![],
        }
    }
    /// Whether a step is one of this batch's.
    pub fn owns(&self, call: &Call) -> bool {
        self.steps.iter().any(|(c, _, _)| c == call)
    }
    pub fn ok(&self) -> usize {
        self.done.iter().filter(|(_, r)| r.is_ok()).count()
    }
    /// The step under way, counted: "copying photo-0412.jpg . 2 of 5".
    pub fn march(&self) -> String {
        let name = self.current.clone().unwrap_or_default();
        format!("{} {}{}{} of {}", self.verb.doing(), name, crate::ui::SEP, self.done.len() + 1, self.total)
    }
    /// The one receipt for the whole, with the real counts.
    pub fn receipt(&self) -> String {
        let ok = self.ok();
        let dest = match (&self.dest_title, self.verb) {
            (Some(t), Verb::Copy | Verb::Move) => format!(" to {}", t),
            _ => String::new(),
        };
        let mut s = if ok == self.total {
            format!("{} {}{}", ok, self.verb.done(), dest)
        } else {
            format!("{} of {} {}{}", ok, self.total, self.verb.done(), dest)
        };
        if ok == self.total && self.size > 0 && self.verb != Verb::PutBack {
            s.push_str(&format!("{}{}", crate::ui::SEP, size_words(self.size)));
        }
        if self.skipped > 0 {
            s.push_str(&format!(", {} skipped", self.skipped));
        }
        // the first reason or two, the provider's label dropped: "notes.md is there already"
        let refused: Vec<&str> = self
            .done
            .iter()
            .filter_map(|(_, r)| r.as_ref().err().map(|e| e.strip_prefix("files: ").unwrap_or(e)))
            .collect();
        if !refused.is_empty() {
            let why: Vec<&str> = refused.iter().take(2).copied().collect();
            s.push_str(&format!(", {} refused: {}", refused.len(), why.join("; ")));
        }
        if self.stopped > 0 {
            s.push_str(&format!(", {} not: stopped", self.stopped));
        }
        s
    }
}

/// Where a folder read lands: the active pane's rows, or the other pane's.
#[derive(Clone, Debug, PartialEq)]
pub enum Landing {
    Active(String),
    Other(String),
}

pub struct State {
    pub page: Page,
    stack: Vec<(Page, Navigation)>,
    /// The active pane's checks: the rows' ids, for the folder at checks_uri.
    pub checks: Vec<String>,
    pub checks_uri: String,
    /// The other pane while two stand, and the side it is on.
    pub other: Option<Pane>,
    pub other_side: Side,
    pub batch: Option<Batch>,
    /// A batch's undo past the first step (App::undo): newest first.
    pub undo_more: Vec<Step>,
    /// The folder reads on their way: the provider, the request, and where the rows land.
    pub folder_reads: Vec<(usize, u64, Landing)>,
    /// A copy or a move of several files waiting for the folder the picker lands in (one pane).
    pub pending: Option<(Verb, Vec<Transfer>)>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            page: Page::List,
            stack: vec![],
            checks: vec![],
            checks_uri: String::new(),
            other: None,
            other_side: Side::Right,
            batch: None,
            undo_more: vec![],
            folder_reads: vec![],
            pending: None,
        }
    }
}

impl State {
    pub fn form(&self) -> bool {
        matches!(self.page, Page::Form(_))
    }
    pub fn has_back(&self) -> bool {
        !self.stack.is_empty()
    }
    pub fn navigate(&mut self, page: Page, nav: Navigation) {
        self.stack.push((self.page.clone(), nav));
        self.page = page;
    }
    pub fn back(&mut self) -> Option<Navigation> {
        self.stack.pop().map(|(page, nav)| {
            self.page = page;
            nav
        })
    }
    /// Back to the list, whatever pages stand: the list's own navigation.
    pub fn back_to_list(&mut self) -> Option<Navigation> {
        let mut last = None;
        while let Some(nav) = self.back() {
            last = Some(nav);
        }
        last
    }
    pub fn checked(&self, id: &str) -> bool {
        self.checks.iter().any(|c| c == id)
    }
    /// The checks go: another folder opened, an operation ended, Esc.
    pub fn clear_checks(&mut self) {
        self.checks.clear();
    }
}

/// The row that is the folder's own: its summary, which opens the folder's actions.
pub fn is_summary(row: &Row) -> bool {
    row.tool.is_none() && row.children.is_none() && (row.id == "files:here" || row.id == "files:total")
}

/// The row that opens the folder above.
pub fn is_up(row: &Row) -> bool {
    row.id == "files:up" || row.text == ".."
}

/// A row a check can stand on: a file or a folder; not `..`, the summary row, a drive, a next-page row.
pub fn checkable(row: &Row) -> bool {
    !is_up(row) && !is_summary(row) && (row.tool.is_some() || !row.more.is_empty())
}

/// A row's size in bytes, from its size column; a folder's count is no size.
pub fn row_size(row: &Row) -> u64 {
    let col = match &row.wide {
        Some(w) if w.len() >= 2 => w.get(1),
        _ => row.columns.first(),
    };
    col.and_then(|c| bytes(c)).unwrap_or(0)
}

/// The row's own folder, where it carries one (a recent file, a file found).
pub fn place_of(row: &Row) -> Option<String> {
    let col = match &row.wide {
        Some(w) if w.len() >= 4 => w.get(3),
        _ => row.columns.get(2),
    };
    col.filter(|c| !c.is_empty()).cloned()
}

/// The folder's own actions: the summary row's steps, then the tools of the rows under "this folder".
pub fn folder_actions(rows: &Rows) -> Vec<Call> {
    let mut v: Vec<Call> = vec![];
    for r in &rows.rows {
        if is_summary(r) {
            v.extend(r.more.iter().cloned());
        }
    }
    for r in rows.rows.iter().filter(|r| r.group.as_deref() == Some("this folder")) {
        if let Some(t) = &r.tool {
            if !v.iter().any(|c| c.name == t.name) {
                v.push(t.clone());
            }
        }
    }
    v
}

/// A size column as bytes: "2 KB", "4.8 MB", "3 B", "14.2 GB free"; a count is none.
pub fn bytes(col: &str) -> Option<u64> {
    let mut it = col.split_whitespace();
    let n: f64 = it.next()?.parse().ok()?;
    let unit = match it.next()? {
        "B" => 1.0,
        "KB" => 1024.0,
        "MB" => 1024.0 * 1024.0,
        "GB" => 1024.0 * 1024.0 * 1024.0,
        _ => return None,
    };
    Some((n * unit).round() as u64)
}

/// Bytes in the provider's own words: 14 KB, 2.1 MB.
pub fn size_words(n: u64) -> String {
    let n = n as f64;
    if n < 1024.0 {
        format!("{} B", n as u64)
    } else if n < 1024.0 * 1024.0 {
        format!("{} KB", (n / 1024.0) as u64)
    } else if n < 1024.0 * 1024.0 * 1024.0 {
        format!("{:.1} MB", n / 1024.0 / 1024.0)
    } else {
        format!("{:.1} GB", n / 1024.0 / 1024.0 / 1024.0)
    }
}

/// The name a kept copy takes beside the one there: `notes 2.md`, then `notes 3.md`.
pub fn numbered(name: &str, taken: &[String]) -> String {
    let (stem, ext) = match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name, ""),
    };
    let mut n = 2;
    loop {
        let candidate = format!("{} {}{}", stem, n, ext);
        if !taken.contains(&candidate) {
            return candidate;
        }
        n += 1;
    }
}

/// A path's last part: the file's name.
pub fn name_of(path: &str) -> String {
    path.trim_end_matches('/').rsplit('/').next().unwrap_or(path).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_read_and_write_in_the_providers_words() {
        assert_eq!(bytes("2 KB"), Some(2048));
        assert_eq!(bytes("3 B"), Some(3));
        assert_eq!(bytes("12 items"), None);
        assert_eq!(bytes("14.2 GB free"), Some((14.2 * 1024.0 * 1024.0 * 1024.0_f64).round() as u64));
        assert_eq!(size_words(3), "3 B");
        assert_eq!(size_words(2048), "2 KB");
        assert_eq!(size_words(bytes("4.8 MB").unwrap() + bytes("120 KB").unwrap()), "4.9 MB");
    }

    #[test]
    fn a_kept_copy_takes_the_next_free_number() {
        assert_eq!(numbered("notes.md", &[]), "notes 2.md");
        assert_eq!(numbered("notes.md", &["notes 2.md".into()]), "notes 3.md");
        assert_eq!(numbered("drafts", &[]), "drafts 2");
        assert_eq!(numbered(".hidden", &[]), ".hidden 2");
    }
}
