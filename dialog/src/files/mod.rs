//! Files: the manager's own state inside the folder list (dialog/DESIGN.md, "Files"): the selection on
//! several rows (`checks` here), the actions page of a row or of the selected set, the second pane beside
//! the first, the batch that copies, moves or trashes the selected files one after another, the list of
//! choices a conflict opens, and the form rename and new folder type in the prompt. The folder list itself
//! stays the dialog's View::Folder: this module adds to it and draws nothing new.
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
            Verb::PutBack => "undoing",
        }
    }
    pub fn done(self) -> &'static str {
        match self {
            Verb::Copy => "copied",
            Verb::Move => "moved",
            Verb::Trash => "trashed",
            Verb::PutBack => "undone",
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
}

/// The actions page: of one row, of the folder alone (`..`, the summary row), or of the checked set.
#[derive(Clone, Debug, PartialEq)]
pub struct Actions {
    pub row: Option<Row>,
    pub checked: Vec<Row>,
    /// The folder's own actions: the summary row's steps, and the rows of the "this folder" group.
    pub folder: Vec<Call>,
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
    /// The lit row in the view.
    View,
    Check(String),
    UncheckAll,
    /// The lit row's path, or the selected rows', one a line.
    CopyPath,
    /// The second pane closes.
    ClosePane,
    /// Copy, move or trash: the lit row to the other pane, or the selected set.
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
    /// The calls still to run or running: the call and the file's name.
    pub steps: Vec<(Call, String)>,
    pub done: Vec<(String, Result<(), String>)>,
    pub skipped: usize,
    pub stopped: usize,
    pub stopping: bool,
    /// When the step under way began: the march shows once the wait is felt.
    pub since: Instant,
    pub current: Option<String>,
    pub undos: Vec<Step>,
}

impl Batch {
    pub fn new(verb: Verb, dest_title: Option<String>, steps: Vec<(Call, String)>, skipped: usize) -> Batch {
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
            undos: vec![],
        }
    }
    /// Whether a step is one of this batch's.
    pub fn owns(&self, call: &Call) -> bool {
        self.steps.iter().any(|(c, _)| c == call)
    }
    pub fn ok(&self) -> usize {
        self.done.iter().filter(|(_, r)| r.is_ok()).count()
    }
    /// The step under way, counted: "copying photo-0412.jpg . 2 of 5"; "stopping after photo-0412.jpg . 2 of 5"
    /// once Esc or the x asked the batch to stop.
    pub fn march(&self) -> String {
        let name = self.current.clone().unwrap_or_default();
        let doing = if self.stopping {
            "stopping after".to_string()
        } else {
            self.verb.doing().to_string()
        };
        format!("{} {}{}{} of {}", doing, name, crate::ui::SEP, self.done.len() + 1, self.total)
    }
    /// The one receipt for the whole, with the real counts.
    pub fn receipt(&self) -> String {
        let ok = self.ok();
        if self.total == 0 {
            // nothing was tried: every file skipped
            return format!("nothing {}: {} skipped", self.verb.done(), self.skipped);
        }
        let dest = match (&self.dest_title, self.verb) {
            (Some(t), Verb::Copy | Verb::Move) => format!(" to {}", t),
            _ => String::new(),
        };
        let mut s = if ok < self.total {
            format!("{} of {} {}{}", ok, self.total, self.verb.done(), dest)
        } else if self.verb == Verb::PutBack {
            format!("{} {}", ok, self.verb.done())
        } else {
            format!("{} file{} {}{}", ok, if ok == 1 { "" } else { "s" }, self.verb.done(), dest)
        };
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
    /// Where the list stood when a form opened: the form keeps it on screen as it was.
    pub fn form_nav(&self) -> Option<&Navigation> {
        self.stack.last().filter(|_| self.form()).map(|(_, nav)| nav)
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

/// A row a check can stand on: a file (a page of its own, or the open step) or a folder (children and steps);
/// not `..`, the summary row, a drive, a next-page row, a trashed file.
pub fn checkable(row: &Row) -> bool {
    let file = row.page.is_some() || row.tool.as_ref().is_some_and(|t| t.name == "files_open");
    let folder = row.children.is_some() && !row.more.is_empty();
    !is_up(row) && !is_summary(row) && (file || folder)
}

/// The path a row names: a file's or a folder's, the folder's own on its summary row; `..`, a drive and a trashed file
/// name none.
pub fn path_of(row: &Row) -> Option<String> {
    if is_up(row) || row.tool.as_ref().is_some_and(|t| t.name == "files_restore") {
        return None;
    }
    row.tool
        .iter()
        .chain(row.more.iter())
        .find_map(|c| c.arguments.get("path").and_then(serde_json::Value::as_str))
        .map(str::to_string)
}

/// The folder's summary as a pane under 40 cells writes it: `this folder . 1 folder . 3 files . 4.5 MB` reads
/// `4 items . 4.5 MB`, the provider's own counts added up, its size kept. None for words that hold no count.
pub fn short_summary(text: &str) -> Option<String> {
    let sep = crate::ui::SEP;
    let (mut items, mut size, mut counted) = (0u64, None, false);
    for part in text.split(sep).skip(1) {
        if part == "empty" {
            counted = true;
        } else if bytes(part).is_some() {
            size = Some(part);
        } else {
            let n: String = part.split_whitespace().next()?.chars().filter(|c| *c != ',').collect();
            items += n.parse::<u64>().ok()?;
            counted = true;
        }
    }
    if !counted {
        return None;
    }
    let count = format!("{} item{}", items, if items == 1 { "" } else { "s" });
    Some(size.map_or(count.clone(), |z| format!("{}{}{}", count, sep, z)))
}

/// A row of the folder's own: a file or a folder in it, never a recent file, a drive, the trash, `..`, the
/// next page or the summary. The names a copy or a move may run into are these rows' alone.
pub fn in_folder(row: &Row) -> bool {
    !matches!(row.group.as_deref(), Some("recent") | Some("drives"))
        && !matches!(row.id.as_str(), "files:trash" | "files:up" | "files:more" | "files:here" | "files:total")
        && !is_up(row)
        && (row.tool.is_some() || row.children.is_some())
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
    fn a_short_summary_adds_the_counts_up_and_keeps_the_size() {
        let dot = crate::ui::SEP;
        let said = |parts: &[&str]| short_summary(&parts.join(dot));
        assert_eq!(
            said(&["this folder", "1 folder", "3 files", "4.5 MB"]).as_deref(),
            Some("4 items \u{b7} 4.5 MB")
        );
        assert_eq!(said(&["this folder", "1 file", "12 B"]).as_deref(), Some("1 item \u{b7} 12 B"));
        assert_eq!(said(&["this folder", "2 folders"]).as_deref(), Some("2 items"));
        assert_eq!(said(&["this folder", "1,204 files", "2.1 GB"]).as_deref(), Some("1204 items \u{b7} 2.1 GB"));
        assert_eq!(said(&["this folder", "empty"]).as_deref(), Some("0 items"));
        assert_eq!(said(&["the trash", "3 items", "2.1 MB"]).as_deref(), Some("3 items \u{b7} 2.1 MB"));
        assert_eq!(short_summary("find notes"), None, "words with no count stay as they are");
    }
}
