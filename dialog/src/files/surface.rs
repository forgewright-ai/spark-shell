//! Connect files' pages, checks, panes and batches to home's prompt, selection, status row and job
//! queue. The folder list stays View::Folder with all its machinery; this is what the files section adds.
use super::*;
use crate::app::{App, HintKey, Item, Mode, Who, WIDTH};
use crate::mcp::{self, Kind};
use crate::reply::Mark;
use serde_json::{json, Value};

impl App {
    /// The files provider and its folder on screen: the active pane, when the view is one.
    pub fn files_pane_view(&self) -> Option<(usize, String)> {
        match &self.view {
            View::Folder(p, uri) if self.providers.get(*p).is_some_and(|x| x.label == "files") => Some((*p, uri.clone())),
            _ => None,
        }
    }

    /// A page of files stands over the list: the actions, a conflict, a form.
    pub fn files_page_open(&self) -> bool {
        self.files_pane_view().is_some() && self.files.page != Page::List
    }

    /// Two panes stand and are the list's shape now: the view is a files folder and no pick or attach is on. A page
    /// of files draws inside the active pane, and a form keeps both. Below a column of 60 cells ui.rs draws the active
    /// pane alone, and nothing is said.
    pub fn two_panes(&self) -> bool {
        self.files_pane_view().is_some() && self.files.other.is_some() && self.picking.is_none() && self.attaching.is_none()
    }

    /// The width a page of files is drawn at: the active pane's while two stand, else the frame's.
    pub(crate) fn files_page_width(&self) -> u16 {
        let w = self.col_w();
        if !self.panes_drawn() {
            return w;
        }
        let (left, right) = crate::ui::pane_widths(w);
        if self.files.other_side == Side::Right {
            left
        } else {
            right
        }
    }

    /// The two panes are what the list draws: two stand, and the column has the 60 cells for them.
    pub fn panes_drawn(&self) -> bool {
        self.two_panes() && self.col_w() >= WIDTH
    }

    /// Where the list stands behind a form of files: the form keeps it on screen, lit as it was.
    pub fn files_form_nav(&self) -> Option<&Navigation> {
        self.files_pane_view()?;
        self.files.form_nav()
    }

    /// The active pane's checks stand on rows of the folder on screen.
    pub fn files_checks_any(&self) -> bool {
        self.files_pane_view().is_some_and(|(_, uri)| uri == self.files.checks_uri) && !self.files.checks.is_empty()
    }

    fn files_navigation(&self) -> Navigation {
        Navigation {
            query: self.input.clone(),
            selected: self.sel,
            in_list: self.in_list,
            scroll: self.scroll,
        }
    }

    fn files_restore(&mut self, nav: Navigation) {
        self.set_input(nav.query);
        self.sel = nav.selected;
        self.in_list = nav.in_list;
        self.scroll = nav.scroll;
        self.chip_focus = None;
        self.keep_lit = None;
        self.last_click = None;
    }

    /// A page opened: the list's place kept, the page's first row lit.
    fn files_open(&mut self, page: Page) {
        let nav = self.files_navigation();
        self.files.navigate(page, nav);
        self.files_restore(Navigation {
            in_list: true,
            ..Default::default()
        });
        self.reply = None;
        self.want_cancel();
        self.target = None;
    }

    /// Back from a page: the list with the row lit again.
    pub(crate) fn files_back(&mut self) {
        if let Some(nav) = self.files.back() {
            self.files_restore(nav);
        }
        self.reply = None;
    }

    fn files_to_list(&mut self) {
        if let Some(nav) = self.files.back_to_list() {
            self.files_restore(nav);
        }
    }

    /// F9 on a row of the active pane, Enter on the summary row: the actions page, of the selected set while a
    /// selection stands, else of the row (the folder's alone on `..`, the summary row, and with nothing lit). False
    /// outside a files folder; a page with nothing to offer says so.
    pub(crate) fn files_actions(&mut self, row: Option<Row>) -> bool {
        if self.files_pane_view().is_none() || self.mode != Mode::Normal || self.picking.is_some() || self.attaching.is_some() || self.files.page != Page::List
        {
            return false;
        }
        let Some((_, _, rows)) = self.folder.clone() else { return false };
        let checked: Vec<Row> = if self.files_checks_any() { self.files_checked_rows(&rows) } else { vec![] };
        let folder = folder_actions(&rows);
        let row = row.filter(|r| !is_summary(r) && !is_up(r));
        let title = if !checked.is_empty() {
            format!("{} selected", checked.len())
        } else if let Some(r) = &row {
            r.text.clone()
        } else {
            rows.title.clone()
        };
        let actions = Actions {
            row: if checked.is_empty() { row } else { None },
            checked,
            folder,
            title,
        };
        if !self.files.offers(&actions, &self.cfg.keys) {
            self.refuse("no actions here");
            return true;
        }
        self.files_open(Page::Actions(Box::new(actions)));
        true
    }

    /// Left and Right in a files folder (dialog/DESIGN.md): Right goes to the right pane and in one pane opens it,
    /// Left goes to the left pane; at the edge, on a page, in a pick both stay put. False where the arrow is the
    /// cursor's: with words typed, while the prompt takes an answer, outside files.
    pub(crate) fn files_arrow(&mut self, side: Side) -> bool {
        if self.files_pane_view().is_none() || self.mode != Mode::Normal || !self.input.is_empty() {
            return false;
        }
        if self.files.page != Page::List || self.picking.is_some() || self.attaching.is_some() || self.chip_focus.is_some() {
            return true;
        }
        match (self.files.other.is_some(), side) {
            (false, Side::Left) => {}
            (false, Side::Right) => self.files_second_pane(),
            (true, _) if self.col_w() < WIDTH => {
                if side == Side::Right {
                    self.refuse("two panes need a window 60 cells wide");
                }
            }
            (true, _) if self.files.other_side == side => {
                self.files_pane();
            }
            (true, _) => {}
        }
        true
    }

    /// Ctrl+Tab: the other pane, opening the second if there is none.
    pub(crate) fn files_pane_key(&mut self) {
        if self.files_pane_view().is_none() {
            return self.refuse("no other pane here");
        }
        if self.files.page != Page::List {
            return self.refuse("Esc goes back to the list first");
        }
        if self.files.other.is_none() {
            return self.files_second_pane();
        }
        if self.col_w() < WIDTH {
            return self.refuse("two panes need a window 60 cells wide");
        }
        self.files_pane();
    }

    pub fn files_activate(&mut self, action: Action) {
        let Some(p) = self.files() else { return };
        match action {
            Action::Open(uri) => {
                self.files_to_list();
                self.open_children(p, &uri);
            }
            Action::Step(call) => {
                self.files_to_list();
                if call.name.ends_with("_preview") {
                    self.open_preview();
                    return;
                }
                // a files step from the actions page says its receipt on the status row with undo, as apps' changes do:
                // the words carry what a row cannot (as notes 2.md, the one there is in the trash)
                let text = call.arguments.get("path").and_then(Value::as_str).map(name_of).unwrap_or_default();
                let line = self.step_line(p, &call, &text);
                self.run(Step {
                    prov: p,
                    call,
                    who: Who::Person,
                    line,
                    typed: true,
                });
            }
            Action::View => {
                self.files_to_list();
                if !self.open_preview() {
                    self.refuse("nothing to view here");
                }
            }
            Action::Ask(call, words) => {
                let line = self.step_line(p, &call, "");
                let step = Step {
                    prov: p,
                    call,
                    who: Who::Person,
                    line,
                    typed: false,
                };
                if !self.files_form(step) {
                    self.files_to_list();
                    self.refuse(&format!("{} is not offered here now", words));
                }
            }
            Action::Check(id) => {
                self.files_to_list();
                self.files_toggle(&id);
                if self.sel + 1 < self.picks().len() {
                    self.sel += 1;
                }
            }
            Action::UncheckAll => {
                self.files_to_list();
                self.files.clear_checks();
            }
            Action::CopyPath => {
                self.files_to_list();
                self.files_copy_path();
            }
            Action::ClosePane => {
                self.files_to_list();
                self.files_close_pane();
            }
            Action::Transfer(verb) => {
                self.files_to_list();
                self.files_transfer_now(verb);
            }
            Action::Answer(answer, all) => self.files_conflict_answer(answer, all),
        }
    }

    // ---- the checks

    /// Space: the lit file or folder selected or let go, and the bar a row down, as Norton Commander's Insert did. On
    /// a row's actions page it is the select row's key; any other page has nothing to select, and says so.
    pub fn files_check(&mut self) {
        if self.files_pane_view().is_none() || self.mode != Mode::Normal {
            return;
        }
        if self.picking.is_some() || self.attaching.is_some() {
            return self.refuse("finish this first: Enter picks, Esc cancels");
        }
        match &self.files.page {
            Page::List => {}
            Page::Actions(a) if a.row.as_ref().is_some_and(checkable) => {
                let id = a.row.as_ref().map(|r| r.id.clone()).unwrap_or_default();
                return self.files_activate(Action::Check(id));
            }
            _ => return self.refuse("nothing to select here: Esc goes back to the list"),
        }
        if !self.in_list {
            return self.refuse("nothing is lit: an arrow or a click lights a row");
        }
        let row = match self.picks().get(self.sel) {
            Some(Item::Folder(i)) => self.folder.as_ref().and_then(|(_, _, r)| r.rows.get(*i)).cloned(),
            _ => None,
        };
        let Some(row) = row.filter(checkable) else {
            return self.refuse("only a file or a folder can be selected");
        };
        self.reply = None;
        self.files_toggle(&row.id);
        self.keep_lit = None;
        self.list_keys = true;
        if self.sel + 1 < self.picks().len() {
            self.sel += 1;
        }
    }

    fn files_toggle(&mut self, id: &str) {
        let Some((_, uri)) = self.files_pane_view() else { return };
        if self.files.checks_uri != uri {
            self.files.checks.clear();
            self.files.checks_uri = uri;
        }
        match self.files.checks.iter().position(|c| c == id) {
            Some(i) => {
                self.files.checks.remove(i);
            }
            None => self.files.checks.push(id.to_string()),
        }
    }

    /// Esc with nothing typed: the checks go first; true when there were any. A pick or an attach on is Esc's
    /// to cancel first: the checked set waits for its folder through it.
    pub(crate) fn files_checks_clear(&mut self) -> bool {
        if !self.files_checks_any() || self.files.page != Page::List || self.picking.is_some() || self.attaching.is_some() {
            return false;
        }
        self.files.clear_checks();
        true
    }

    /// The checked rows of the folder on screen, each file once: your home lists a recent file under `recent`
    /// and under `home` with one id, and a check on either is one check on one file.
    pub(crate) fn files_checked_rows(&self, rows: &Rows) -> Vec<Row> {
        let mut seen: Vec<&str> = vec![];
        rows.rows
            .iter()
            .filter(|r| {
                self.files.checked(&r.id) && checkable(r) && !seen.contains(&r.id.as_str()) && {
                    seen.push(r.id.as_str());
                    true
                }
            })
            .cloned()
            .collect()
    }

    /// The status row while a selection stands: `2 selected . 4.5 MB`, the selected files' sizes summed.
    pub fn files_checked_line(&self) -> Option<String> {
        if !self.files_checks_any() || self.files.page != Page::List || self.mode != Mode::Normal {
            return None;
        }
        let rows = &self.folder.as_ref()?.2;
        let checked = self.files_checked_rows(rows);
        if checked.is_empty() {
            return None;
        }
        let size: u64 = checked.iter().map(row_size).sum();
        let mut s = format!("{} selected", checked.len());
        if size > 0 {
            s.push_str(&format!("{}{}", crate::ui::SEP, size_words(size)));
        }
        Some(s)
    }

    /// The status row's place for a files row: its own folder where it carries one, else the folder on screen.
    pub(crate) fn files_place(&self, it: &Item, row: &Row) -> Option<String> {
        place_of(row).or_else(|| match it {
            Item::Folder(_) => self.folder.as_ref().map(|(_, _, r)| r.title.clone()).filter(|t| !t.is_empty()),
            _ => None,
        })
    }

    /// The checks keep to the folder they were made in: another folder opened takes them away; a preview and
    /// back leaves them.
    pub(crate) fn files_on_view(&mut self) {
        match &self.view {
            View::Folder(_, uri) if *uri == self.files.checks_uri => {}
            View::Preview => {}
            _ => self.files.clear_checks(),
        }
    }

    // ---- two panes

    /// Right in one pane, Ctrl+Tab: the second pane opens at the right on the same folder, and the bar goes to it. The
    /// first pane drops what is not its folder's own (your home's recent files), its lit row kept by its id.
    fn files_second_pane(&mut self) {
        let Some((p, uri)) = self.files_pane_view() else { return };
        if self.col_w() < WIDTH {
            return self.refuse("two panes need a window 60 cells wide");
        }
        let lit = self.lit_row().filter(|_| self.in_list).map(|(_, r)| r.id);
        let rows = self.folder.as_ref().map(|(_, _, r)| r.clone());
        self.files.other = Some(Pane {
            uri,
            rows,
            sel: 0,
            scroll: 0,
            in_list: false,
            checks: vec![],
            came_from: self.came_from.clone(),
        });
        self.files.other_side = Side::Right;
        self.files_relight(lit);
        self.files_refresh_other(p);
        self.reply = None;
        self.files_pane();
    }

    /// The list changed its shape under the bar, a pane opened or closed: the lit row kept by its id.
    fn files_relight(&mut self, lit: Option<String>) {
        if let Some(id) = lit {
            let picks = self.picks();
            let at = picks.iter().position(|it| self.row_ref(it).is_some_and(|r| r.id == id));
            self.sel = at.unwrap_or(self.sel.min(picks.len().saturating_sub(1)));
        }
    }

    /// `close pane`: the second pane closes, the one at the right; the bar stands in the first.
    fn files_close_pane(&mut self) {
        if self.files.other_side == Side::Left {
            self.files_pane();
        }
        let lit = self.lit_row().filter(|_| self.in_list).map(|(_, r)| r.id);
        self.files.other = None;
        self.files.other_side = Side::Right;
        self.files_relight(lit);
    }

    /// Ctrl+Tab, a click on the other pane: the other pane becomes active, the active one waits aside. False when
    /// nothing switched: no other pane, a page open, a pick or a question on.
    pub fn files_pane(&mut self) -> bool {
        let Some((p, uri)) = self.files_pane_view() else { return false };
        if self.mode != Mode::Normal || self.files.page != Page::List || self.picking.is_some() || self.attaching.is_some() {
            return false;
        }
        let Some(other) = self.files.other.take() else { return false };
        self.prompt_depart();
        let active = Pane {
            uri,
            rows: self.folder.take().map(|(_, _, r)| r),
            sel: self.sel,
            scroll: self.scroll,
            in_list: self.in_list,
            checks: std::mem::take(&mut self.files.checks),
            came_from: std::mem::take(&mut self.came_from),
        };
        self.files.other = Some(active);
        self.files.other_side = match self.files.other_side {
            Side::Right => Side::Left,
            Side::Left => Side::Right,
        };
        self.view = View::Folder(p, other.uri.clone());
        self.came_from = other.came_from;
        self.files.checks = other.checks;
        self.files.checks_uri = other.uri.clone();
        self.sel = other.sel;
        self.scroll = other.scroll;
        self.keep_lit = None;
        self.target = None;
        self.reply = None;
        self.last_click = None;
        match other.rows {
            Some(r) => {
                self.folder = Some((p, other.uri.clone(), r));
                self.refresh_folder(p, &other.uri);
            }
            None => self.read_folder(p, &other.uri),
        }
        self.prompt_arrive();
        self.in_list = true;
        self.list_keys = true;
        true
    }

    /// A click on a row of the other pane: it becomes active and that row is selected; a second click opens it.
    /// A click the switch declines falls on nothing.
    pub fn pane_clicked(&mut self, n: usize, now: std::time::Instant) {
        if !self.files_pane() {
            return;
        }
        self.last_click = None;
        self.clicked(n, now);
    }

    /// The other pane's rows read again: its own read of its own folder.
    pub(crate) fn files_refresh_other(&mut self, p: usize) {
        let Some(uri) = self.files.other.as_ref().map(|o| o.uri.clone()) else {
            return;
        };
        if let Some(id) = self
            .server(p)
            .and_then(|s| s.request("resources/read", json!({"uri": uri}), Kind::Folder, mcp::T_READ))
        {
            self.files.folder_reads.push((p, id, Landing::Other(uri)));
        }
    }

    /// A folder's rows came for request `n` of provider `idx`: into the pane they are for. The lit row keeps by its
    /// id and the checks by theirs; an answer for a folder neither pane shows lands nowhere.
    pub(crate) fn files_land(&mut self, idx: usize, n: u64, of: Option<String>, rows: Option<Rows>, error: Option<String>) {
        let landing = self
            .files
            .folder_reads
            .iter()
            .position(|(p, id, _)| *p == idx && *id == n)
            .map(|k| self.files.folder_reads.remove(k).2);
        let view_uri = match &self.view {
            View::Folder(p, uri) if *p == idx => Some(uri.clone()),
            _ => None,
        };
        let other_uri = self
            .files
            .other
            .as_ref()
            .map(|o| o.uri.clone())
            .filter(|_| self.files().is_some_and(|f| f == idx));
        let uri = match &landing {
            Some(Landing::Active(u)) | Some(Landing::Other(u)) => Some(u.clone()),
            None => of.or_else(|| view_uri.clone()),
        };
        let to_other = match (&landing, &uri) {
            (Some(Landing::Other(_)), Some(u)) if other_uri.as_deref() == Some(u.as_str()) => true,
            (_, Some(u)) if view_uri.as_deref() == Some(u.as_str()) => false,
            (_, Some(u)) if other_uri.as_deref() == Some(u.as_str()) => true,
            _ => return,
        };
        let Some(uri) = uri else { return };
        let Some(rows) = rows else {
            if !to_other {
                self.refuse(&error.unwrap_or_else(|| "that folder could not be read".into()));
            }
            return;
        };
        let ids: Vec<&str> = rows.rows.iter().map(|r| r.id.as_str()).collect();
        if to_other {
            let keep: Vec<String> = ids.iter().map(|s| s.to_string()).collect();
            if let Some(o) = self.files.other.as_mut() {
                o.checks.retain(|c| keep.contains(c));
                o.rows = Some(rows);
            }
            return;
        }
        let lit = self
            .in_list
            .then(|| self.picks().get(self.sel).and_then(|it| self.row_ref(it)).map(|r| r.id.clone()))
            .flatten();
        if self.files.checks_uri == uri {
            let keep: Vec<String> = ids.iter().map(|s| s.to_string()).collect();
            self.files.checks.retain(|c| keep.contains(c));
        }
        self.folder = Some((idx, uri, rows));
        self.hold_rows(idx);
        if let Some(id) = lit {
            let picks = self.picks();
            if let Some(i) = picks.iter().position(|it| self.row_ref(it).is_some_and(|r| r.id == id)) {
                self.sel = i;
            } else {
                self.sel = self.sel.min(picks.len().saturating_sub(1));
            }
        }
    }

    /// The panes of this provider read again: the folder on screen, and the other pane's.
    pub(crate) fn refresh_panes(&mut self, p: usize) {
        if let View::Folder(fp, uri) = self.view.clone() {
            if fp == p {
                self.refresh_folder(fp, &uri);
            }
        }
        if self.files() == Some(p) {
            self.files_refresh_other(p);
        }
    }

    // ---- the form

    /// A files step that asks for a name: the form, typed in the prompt (dialog/DESIGN.md); the row's name
    /// prefilled for a rename. False for any other ask, which keeps Mode::Ask.
    pub(crate) fn files_form(&mut self, step: Step) -> bool {
        if self.providers.get(step.prov).is_none_or(|p| p.label != "files") || !step.call.ask.iter().any(|a| a == "name") || self.files_pane_view().is_none() {
            return false;
        }
        // the header's words: the dialog's own for what it names, else the provider's
        let words = match step.call.name.as_str() {
            "files_rename" => "rename".to_string(),
            "files_new_folder" => "new folder".to_string(),
            "files_new_text" => "new file".to_string(),
            _ => step.call.said.clone().unwrap_or_else(|| crate::app::verb_of(&step.call.name).to_lowercase()),
        };
        let current = if step.call.name == "files_rename" {
            step.call.arguments.get("path").and_then(Value::as_str).map(name_of).unwrap_or_default()
        } else {
            String::new()
        };
        // from the actions page: that page gives way, so Esc lets the form go and the list is back with its row lit
        let nav = match self.files.page {
            Page::List => self.files_navigation(),
            _ => self.files.back().unwrap_or_else(|| self.files_navigation()),
        };
        self.files.navigate(
            Page::Form(Box::new(Form {
                step,
                field: "name".into(),
                words,
            })),
            nav,
        );
        self.set_input(current);
        self.in_list = false;
        self.sel = 0;
        self.scroll = 0;
        self.chip_focus = None;
        self.reply = None;
        true
    }

    /// Enter on the form: the step runs with the name typed.
    pub(crate) fn files_submit(&mut self) {
        let Page::Form(f) = self.files.page.clone() else { return };
        let f = *f;
        let typed = self.input.trim().to_string();
        if typed.is_empty() {
            return self.refuse("type a name, or Esc cancels");
        }
        let mut step = f.step;
        step.call.arguments.insert(f.field.clone(), Value::String(typed));
        step.call.ask.retain(|a| a != &f.field);
        step.typed = true; // the receipt says what was made or renamed
        self.files_to_list();
        self.run(step);
    }

    /// What the form's empty prompt takes.
    pub fn files_placeholder(&self) -> Option<&'static str> {
        let Page::Form(f) = &self.files.page else { return None };
        self.files_pane_view()?;
        Some(match f.step.call.name.as_str() {
            "files_rename" => "new name",
            "files_new_folder" => "folder name",
            "files_new_text" => "file name",
            _ => "a name",
        })
    }

    /// The key bar of a page of files; None on the list, whose keys are the folder's.
    pub fn files_hint(&self) -> Option<Vec<(String, bool)>> {
        self.files_pane_view()?;
        let pair = |w: &str, k: &str| vec![(format!("{w} "), false), (k.to_string(), true)];
        match &self.files.page {
            Page::List => None,
            Page::Form(_) => {
                let mut k = pair("Cancel", "Esc");
                k.push(("   ".into(), false));
                k.extend(pair("Save", "Enter"));
                Some(k)
            }
            Page::Actions(_) => Some(pair("Back", "Esc")),
            Page::Conflict(_) => Some(pair("Cancel", "Esc")),
        }
    }

    // ---- the keys

    /// The key's refusal where it has nothing to act on.
    fn files_key_words(key: HintKey) -> &'static str {
        match key {
            HintKey::Rename => "nothing to rename here",
            HintKey::View => "nothing to view here",
            HintKey::Open => "this cannot be opened here",
            HintKey::Copy | HintKey::CopyPath => "nothing to copy here",
            HintKey::Move => "nothing to move here",
            HintKey::New => "no new folder here",
            HintKey::Trash => "nothing to trash here",
            _ => "no actions here",
        }
    }

    /// The key on a page of files: on the menu the row that carries it acts, as a click does; a conflict takes its rows.
    /// True when the page answered the key.
    pub(crate) fn files_page_key(&mut self, key: HintKey) -> bool {
        match self.files.page {
            Page::List | Page::Form(_) => false,
            Page::Conflict(_) => {
                self.refuse("choose a row, or Esc cancels");
                true
            }
            Page::Actions(_) => {
                let label = self.cfg.keys.label(key).to_string();
                let lines = self.files.lines(self.files_page_width(), &self.cfg.keys, "");
                match lines.into_iter().find(|l| !label.is_empty() && l.key == label).and_then(|l| l.action) {
                    Some(action) => self.files_activate(action),
                    None => self.refuse(Self::files_key_words(key)),
                }
                true
            }
        }
    }

    /// A key that wants a row, with none lit, says how to light one; else its own words.
    pub(crate) fn files_nothing(&mut self, key: HintKey) {
        if self.files_pane_view().is_some() && self.files.page == Page::List && !self.in_list {
            return self.refuse("nothing is lit: an arrow or a click lights a row");
        }
        self.refuse(Self::files_key_words(key));
    }

    /// F4 to F8 and Ctrl+C in a files folder: outside one each says there is nothing for it.
    pub(crate) fn files_key(&mut self, key: HintKey) {
        let Some((p, _)) = self.files_pane_view() else {
            return self.refuse(if key == HintKey::Open {
                "nothing to open here"
            } else {
                Self::files_key_words(key)
            });
        };
        if self.files_page_key(key) {
            return;
        }
        match key {
            HintKey::Open => {
                let lit = self.lit_row().filter(|_| self.in_list).map(|(_, r)| r);
                let Some(row) = lit else { return self.files_nothing(key) };
                match row.tool.iter().chain(row.more.iter()).find(|c| c.name == "files_app") {
                    Some(call) => self.files_activate(Action::Step(call.clone())),
                    None => self.refuse(Self::files_key_words(key)),
                }
            }
            HintKey::Copy => self.files_transfer_now(Verb::Copy),
            HintKey::Move => self.files_transfer_now(Verb::Move),
            HintKey::Trash => self.files_transfer_now(Verb::Trash),
            HintKey::CopyPath => self.files_copy_path(),
            HintKey::New => {
                let rows = self.folder.as_ref().map(|(_, _, r)| folder_actions(r)).unwrap_or_default();
                match rows.into_iter().find(|c| c.name == "files_new_folder") {
                    Some(call) => {
                        let line = self.step_line(p, &call, "");
                        let step = Step {
                            prov: p,
                            call,
                            who: Who::Person,
                            line,
                            typed: false,
                        };
                        self.files_form(step);
                    }
                    None => self.refuse(Self::files_key_words(key)),
                }
            }
            _ => {}
        }
    }

    /// Ctrl+C: the lit row's path, or the selected rows', one a line, to the clipboard through the apps adapter.
    fn files_copy_path(&mut self) {
        let Some((_, _, rows)) = self.folder.clone() else {
            return self.files_nothing(HintKey::CopyPath);
        };
        let chosen: Vec<Row> = if self.files_checks_any() {
            self.files_checked_rows(&rows)
        } else {
            self.lit_row().filter(|_| self.in_list).map(|(_, r)| r).into_iter().collect()
        };
        let paths: Vec<String> = chosen.iter().filter_map(path_of).collect();
        if paths.is_empty() {
            return self.files_nothing(HintKey::CopyPath);
        }
        if self.apps.pending.is_some() {
            return self.refuse("the apps are busy: a moment");
        }
        let n = paths.len();
        self.apps.copy_said = Some(if n == 1 { "path copied".into() } else { format!("{} paths copied", n) });
        self.apps_request(json!({"op": "copy", "text": paths.join("\n")}));
    }

    // ---- the operation

    /// Copy, move or trash: the checked set, else the lit row; to the other pane's folder while two stand, else
    /// the folder is picked as today.
    fn files_transfer_now(&mut self, verb: Verb) {
        let Some((p, _)) = self.files_pane_view() else { return };
        let Some((_, _, rows)) = self.folder.clone() else { return };
        if self.running.is_some() || self.files.batch.is_some() {
            return self.reply(Mark::Note, "wait for the current action's result");
        }
        let mut chosen: Vec<Row> = if self.files_checks_any() { self.files_checked_rows(&rows) } else { vec![] };
        if chosen.is_empty() {
            if let Some(Item::Folder(i)) = self.picks().get(self.sel).filter(|_| self.in_list) {
                if let Some(r) = rows.rows.get(*i).filter(|r| checkable(r)) {
                    chosen.push(r.clone());
                }
            }
        }
        if chosen.is_empty() {
            return self.refuse("nothing to act on: light a file or a folder, or select some");
        }
        if verb == Verb::Trash {
            let transfers = self.files_steps(p, verb, &chosen, None);
            return self.files_start(verb, None, transfers);
        }
        let Some(other) = self.files.other.clone() else {
            return self.files_pick_folder(p, verb, chosen);
        };
        if other.rows.is_none() {
            return self.refuse("the other pane's rows have not come yet: a moment");
        }
        let Some(here) = other.here() else {
            return self.refuse("the other pane is not a folder");
        };
        if Some(here.as_str()) == rows.here.as_deref() {
            return self.refuse("the other pane shows this folder: open another there");
        }
        let transfers = self.files_steps(p, verb, &chosen, Some(&here));
        let dest = other.rows.clone().unwrap_or_default();
        self.files_transfer(verb, transfers, Some((other.title(), dest)));
    }

    /// Each chosen row's step for the verb, its destination filled; a row with no such step is refused by name.
    fn files_steps(&self, p: usize, verb: Verb, rows: &[Row], to: Option<&str>) -> Vec<Transfer> {
        rows.iter()
            .map(|r| {
                let name = r.text.clone();
                let Some(mut call) = r.tool.iter().chain(r.more.iter()).find(|c| c.name == verb.tool()).cloned() else {
                    return Transfer {
                        step: None,
                        name: name.clone(),
                        conflict: false,
                        answer: None,
                        refused: Some(format!("{}: not offered", name)),
                    };
                };
                if let Some(t) = to {
                    call.arguments.insert("to".into(), Value::String(t.into()));
                }
                call.pick = None;
                let name = call.arguments.get("path").and_then(Value::as_str).map(name_of).unwrap_or(name);
                let line = self.step_line(p, &call, &r.text);
                Transfer {
                    step: Some(Step {
                        prov: p,
                        call,
                        who: Who::Person,
                        line,
                        typed: false,
                    }),
                    name,
                    conflict: false,
                    answer: None,
                    refused: None,
                }
            })
            .collect()
    }

    /// One pane: the folder is picked as today, with the first file's step; every chosen file goes where the
    /// pick lands.
    fn files_pick_folder(&mut self, p: usize, verb: Verb, chosen: Vec<Row>) {
        let transfers = self.files_steps(p, verb, &chosen, None);
        let Some(first) = transfers.iter().find_map(|t| t.step.clone()) else {
            return self.refuse(&format!("{} is not offered for these", verb.tool().trim_start_matches("files_")));
        };
        let n = transfers.len();
        let mut step = first;
        step.call.pick = Some("to".into());
        self.run(step);
        // the pick is on: the files wait for its folder; refused (a step under way), nothing waits
        if !self.picking.as_ref().is_some_and(|pk| pk.step.is_some()) {
            return;
        }
        self.files.pending = Some((verb, transfers));
        if n > 1 {
            if let Some(pk) = self.picking.as_mut() {
                pk.what = format!("{} {} files here", verb.tool().trim_start_matches("files_"), n);
            }
        }
    }

    /// The folder picked (Enter on the row that lands the step here): the step, or the batch waiting, goes there,
    /// the names already in it asked about first. False for a step that is no files copy or move.
    pub(crate) fn files_picked(&mut self, step: Step, here: &str) -> bool {
        let is_files = self.providers.get(step.prov).is_some_and(|p| p.label == "files");
        let verb = match step.call.name.as_str() {
            "files_copy" => Verb::Copy,
            "files_move" => Verb::Move,
            _ => {
                self.files.pending = None;
                return false;
            }
        };
        if !is_files {
            self.files.pending = None;
            return false;
        }
        let Some((_, _, rows)) = self.folder.clone() else { return false };
        let dest = (rows.title.clone(), rows);
        let transfers = match self.files.pending.take() {
            Some((v, mut ts)) if v == verb => {
                for t in ts.iter_mut() {
                    if let Some(s) = t.step.as_mut() {
                        s.call.arguments.insert("to".into(), Value::String(here.into()));
                    }
                }
                ts
            }
            _ => {
                let name = step.call.arguments.get("path").and_then(Value::as_str).map(name_of).unwrap_or_default();
                vec![Transfer {
                    step: Some(step),
                    name,
                    conflict: false,
                    answer: None,
                    refused: None,
                }]
            }
        };
        self.files_transfer(verb, transfers, Some(dest));
        true
    }

    /// A copy or a move: the names already in the destination asked about first, each a page of choices; then
    /// the operation.
    fn files_transfer(&mut self, verb: Verb, mut transfers: Vec<Transfer>, dest: Option<(String, Rows)>) {
        if let Some((title, rows)) = &dest {
            // the folder's own rows alone: a recent file, a drive, the trash, `..` are no names in it
            let taken: Vec<String> = rows.rows.iter().filter(|r| in_folder(r)).map(|r| r.text.clone()).collect();
            // a file in its own folder already is no conflict: the provider says so, as today
            let here = rows.here.clone().unwrap_or_default();
            for t in transfers.iter_mut() {
                let own = t
                    .step
                    .as_ref()
                    .and_then(|s| s.call.arguments.get("path").and_then(Value::as_str))
                    .and_then(|p| p.rsplit_once('/').map(|(d, _)| d.to_string()))
                    .is_some_and(|d| d == here);
                t.conflict = t.step.is_some() && !own && taken.contains(&t.name);
            }
            if let Some(at) = transfers.iter().position(|t| t.conflict) {
                self.files_open(Page::Conflict(Box::new(Conflicts {
                    verb,
                    dest_title: title.clone(),
                    items: transfers,
                    at,
                })));
                return;
            }
        }
        self.files_start(verb, dest.map(|(t, _)| t), transfers);
    }

    /// A choice on the conflict page, for this file or for all that remain; the last answer starts the operation.
    fn files_conflict_answer(&mut self, answer: Answer, all: bool) {
        let Page::Conflict(c) = self.files.page.clone() else { return };
        let mut c = *c;
        for (i, t) in c.items.iter_mut().enumerate() {
            if t.conflict && t.answer.is_none() && (all || i == c.at) {
                t.answer = Some(answer);
            }
        }
        match c.items.iter().position(|t| t.conflict && t.answer.is_none()) {
            Some(next) => {
                c.at = next;
                self.files.page = Page::Conflict(Box::new(c));
                self.sel = 0;
                self.scroll = 0;
            }
            None => {
                self.files_to_list();
                self.files_start(c.verb, Some(c.dest_title), c.items);
            }
        }
    }

    /// The operation: one file through the provider's step as today; several as a batch, one step a file through
    /// the queue, a skipped file left out and counted, a kept or replaced one saying so to the provider.
    fn files_start(&mut self, verb: Verb, dest_title: Option<String>, transfers: Vec<Transfer>) {
        let skipped = transfers.iter().filter(|t| t.answer == Some(Answer::Skip)).count();
        let mut steps: Vec<(Step, String)> = vec![];
        let mut seeded: Vec<(String, Result<(), String>)> = vec![];
        for t in transfers {
            if t.answer == Some(Answer::Skip) {
                continue;
            }
            match (t.step, t.refused) {
                (Some(mut step), None) => {
                    match t.answer {
                        Some(Answer::Keep) => {
                            step.call.arguments.insert("there".into(), Value::String("keep".into()));
                        }
                        Some(Answer::Replace) => {
                            step.call.arguments.insert("there".into(), Value::String("replace".into()));
                        }
                        _ => {}
                    }
                    steps.push((step, t.name));
                }
                (_, Some(why)) => seeded.push((t.name, Err(why))),
                _ => {}
            }
        }
        if steps.len() == 1 && seeded.is_empty() && skipped == 0 {
            // one file: the provider's step, its receipt on the status row; the checks go once it is sent
            let (mut step, _) = steps.remove(0);
            step.typed = true;
            self.run(step);
            if self.running.is_some() || matches!(self.mode, Mode::Confirm(_)) {
                self.files.clear_checks();
            }
            return;
        }
        // the batch's undo is its own: the undo standing before it goes, so a refused step can never take it
        self.undo = None;
        self.files.undo_more.clear();
        let calls: Vec<(Call, String)> = steps.iter().map(|(s, n)| (s.call.clone(), n.clone())).collect();
        let mut batch = Batch::new(verb, dest_title, calls, skipped);
        batch.total += seeded.len();
        batch.done = seeded;
        self.files.batch = Some(batch);
        if steps.is_empty() {
            return self.files_finish_batch();
        }
        self.queue.extend(steps.into_iter().map(|(s, _)| s));
        self.next_step();
    }

    /// A batch's step was sent: the march counts it from now.
    pub(crate) fn files_step_sent(&mut self, call: &Call) {
        if let Some(b) = self.files.batch.as_mut() {
            if let Some((_, name)) = b.steps.iter().find(|(c, _)| c == call) {
                b.current = Some(name.clone());
                b.since = std::time::Instant::now();
            }
        }
    }

    /// Whether a step is the batch's: its receipt and its refusal are the batch's to count, never the queue's to stop.
    pub(crate) fn files_batch_owns(&self, call: &Call) -> bool {
        self.files.batch.as_ref().is_some_and(|b| b.owns(call))
    }

    /// A batch's step landed: counted, its undo kept, nothing said; the last one ends the batch with its receipt.
    pub(crate) fn files_step_done(&mut self, step: &Step, outcome: Result<(), String>) {
        // a step done leaves its undo; a refused one leaves none, and takes none that stood before
        let undo = if outcome.is_ok() { self.undo.take() } else { None };
        let Some(b) = self.files.batch.as_mut() else { return };
        let Some(k) = b.steps.iter().position(|(c, _)| *c == step.call) else {
            return;
        };
        let (_, name) = b.steps.remove(k);
        b.done.push((name, outcome));
        b.current = None;
        b.undos.extend(undo);
        self.reply = None;
        if b.steps.is_empty() {
            self.files_finish_batch();
        }
    }

    /// The batch ended: one receipt for the whole, undo for the whole newest first, the checks gone, both panes
    /// read again.
    fn files_finish_batch(&mut self) {
        let Some(b) = self.files.batch.take() else { return };
        let text = b.receipt();
        self.reply(Mark::Done, &text);
        let mut undos = b.undos;
        undos.reverse();
        self.undo = undos.first().cloned();
        self.files.undo_more = undos.into_iter().skip(1).collect();
        if let Some(r) = self.reply.as_mut() {
            r.undo = self.undo.is_some();
        }
        self.files.clear_checks();
        if let Some(p) = self.files() {
            self.providers[p].dirty = true;
        }
    }

    /// Esc or the x while a batch runs, wherever you are: it stops after the file under way, and the receipt says
    /// what was done. True while a batch is being stopped.
    pub(crate) fn files_stop_batch(&mut self) -> bool {
        let running: Option<Call> = self.running.as_ref().map(|(_, _, s)| s.call.clone());
        let Some(b) = self.files.batch.as_mut() else { return false };
        let keep = running.filter(|c| b.owns(c));
        let owned: Vec<Call> = b.steps.iter().map(|(c, _)| c.clone()).collect();
        let before = b.steps.len();
        b.steps.retain(|(c, _)| keep.as_ref() == Some(c));
        b.stopped += before - b.steps.len();
        b.stopping = true;
        let done = b.steps.is_empty();
        self.queue.retain(|s| !owned.contains(&s.call));
        if matches!(&self.mode, Mode::Confirm(s) if owned.contains(&s.call)) {
            self.mode = Mode::Normal;
            self.input.clear();
            self.unstash();
        }
        if done {
            self.files_finish_batch();
        }
        true
    }

    /// A batch's step that got no answer (the provider stopped, or kept silent): counted as refused with its reason,
    /// then the rest not run, and the receipt says so. False for a step of no batch.
    pub(crate) fn files_batch_broken(&mut self, step: &Step, why: &str) -> bool {
        if !self.files_batch_owns(&step.call) {
            return false;
        }
        self.running = None;
        self.files_step_done(step, Err(why.to_string()));
        self.files_stop_batch();
        true
    }

    /// The batch's undo, from the status row or typed: every step back, newest first, as a batch of its own; the
    /// receipt says how many were undone. False when the undo at hand is one step, run as today.
    pub(crate) fn files_undo_batch(&mut self) -> bool {
        if self.files.undo_more.is_empty() {
            return false;
        }
        if self.running.is_some() {
            self.reply(Mark::Note, "wait for the current action's result");
            return true;
        }
        let Some(head) = self.undo.take() else {
            self.files.undo_more.clear();
            return false;
        };
        let mut steps = vec![head];
        steps.append(&mut self.files.undo_more);
        let calls: Vec<(Call, String)> = steps
            .iter()
            .map(|s| {
                (
                    s.call.clone(),
                    s.call.arguments.get("path").and_then(Value::as_str).map(name_of).unwrap_or_default(),
                )
            })
            .collect();
        self.reply = None;
        self.files.batch = Some(Batch::new(Verb::PutBack, None, calls, 0));
        self.queue.extend(steps);
        self.next_step();
        true
    }
}
