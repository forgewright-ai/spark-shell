//! The preview (#120): one file of a list, as large as the content area allows. Up and down go
//! through the list's files, left and right through the file's pages; Esc, or Space with nothing
//! typed, goes back to the list, and Enter opens the file. A picture is fitted to the area. The
//! provider reads the file and answers a page; the dialog draws two shapes, lines or a picture, and
//! never looks at a file's type.

use crate::model::Row;
use crate::scrub::scrub;
use serde_json::Value;

/// The lines one page brings, at most: a longer text says where its preview stops.
pub const LINES_MAX: usize = 20_000;
/// The facts a page shows at its foot, at most.
pub const FACTS_MAX: usize = 8;

/// What a provider answers for a file: its name, its facts, and lines or a picture.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Page {
    /// The uri this page answers: an answer for a file left meanwhile lands nowhere.
    pub uri: String,
    pub title: String,
    /// The file's facts, each a few words ("412 kB", "4032 by 3024", "3:45").
    pub facts: Vec<String>,
    pub lines: Vec<String>,
    /// The lines drawn bold, by index: a heading.
    pub bold: Vec<usize>,
    /// Lines numbered at the left, muted: source code.
    pub numbered: bool,
    /// A PNG of the page: absolute, a .png, no parent step (as a row's preview).
    pub picture: Option<String>,
    /// A picture's page and how many the file has (a PDF); text is paged here, by the area.
    pub page: usize,
    pub pages: usize,
    /// One line where there is no preview, and why.
    pub say: Option<String>,
    /// A text of the page spark can read, as a file the provider wrote: the attach path takes it.
    pub attach: Option<String>,
}

/// The preview's place: the provider, the list it came from (its files, in its order), the file
/// shown, its page, and the page as it came.
#[derive(Clone, Debug, PartialEq)]
pub struct Preview {
    pub prov: usize,
    /// The words of the list's place, for the header ("~/docs").
    pub place: String,
    pub files: Vec<Row>,
    pub at: usize,
    /// The page shown, from 1.
    pub page: usize,
    pub shown: Option<Page>,
    /// The keys of the page last shown: the key row keeps them while the next file's page is on its way (#166).
    pub keys: Option<Keys>,
}

/// What a page's own keys need (#166): a picture's, and how many pages.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Keys {
    pub picture: bool,
    pub pages: usize,
}

impl Keys {
    pub fn of(pg: &Page) -> Keys {
        Keys {
            picture: pg.picture.is_some(),
            pages: pg.pages,
        }
    }
}

impl Preview {
    /// The preview of `files[at]`, None when no row of the list has a page.
    pub fn new(prov: usize, place: &str, rows: &[Row], lit: &str) -> Option<Preview> {
        let files: Vec<Row> = rows.iter().filter(|r| r.page.is_some()).cloned().collect();
        let at = files.iter().position(|r| r.id == lit)?;
        Some(Preview {
            prov,
            place: place.to_string(),
            files,
            at,
            page: 1,
            shown: None,
            keys: None,
        })
    }

    pub fn row(&self) -> &Row {
        &self.files[self.at]
    }

    /// The uri of the page to read now: the row's own, with the page asked for past the first.
    pub fn uri(&self) -> String {
        let base = self.row().page.clone().unwrap_or_default();
        if self.page > 1 && self.shown.as_ref().is_some_and(|p| p.picture.is_some()) {
            format!("{}?page={}", base, self.page)
        } else {
            base
        }
    }

    /// Another file of the list, d away; false at either end.
    pub fn step_file(&mut self, d: i32) -> bool {
        let to = self.at as i64 + d as i64;
        if to < 0 || to >= self.files.len() as i64 {
            return false;
        }
        self.at = to as usize;
        self.page = 1;
        self.keys = self.shown.as_ref().map(Keys::of).or(self.keys);
        self.shown = None;
        true
    }

    /// Another page, d away, of `pages`; false at either end.
    pub fn step_page(&mut self, d: i32, pages: usize) -> bool {
        let to = self.page as i64 + d as i64;
        if to < 1 || to > pages as i64 {
            return false;
        }
        self.page = to as usize;
        true
    }
}

/// A picture's path is held to a preview's shape: absolute, a PNG, no parent step, no control.
fn png_path(v: Option<&Value>) -> Option<String> {
    let p = v?.as_str()?;
    (p.starts_with('/') && p.ends_with(".png") && !p.split('/').any(|c| c == "..") && !p.chars().any(char::is_control)).then(|| p.to_string())
}

/// A text for spark is a file the provider wrote, held to the same shape, a .txt.
fn attach(v: Option<&Value>) -> Option<String> {
    let p = v?.as_str()?;
    (p.starts_with('/') && p.ends_with(".txt") && !p.split('/').any(|c| c == "..") && !p.chars().any(char::is_control)).then(|| p.to_string())
}

/// A page from a resource read's text; None when it is not one. Every string scrubbed as it is read.
pub fn page(uri: &str, text: &str) -> Option<Page> {
    let v: Value = serde_json::from_str(text).ok()?;
    let str_of = |k: &str| v.get(k).and_then(Value::as_str).map(scrub).filter(|t| !t.is_empty());
    let lines: Vec<String> = v
        .get("lines")
        .and_then(Value::as_array)
        .map(|a| a.iter().take(LINES_MAX).map(|l| scrub(l.as_str().unwrap_or(""))).collect())
        .unwrap_or_default();
    let n = lines.len();
    let picture = png_path(v.get("picture"));
    let pages = v.get("pages").and_then(Value::as_u64).unwrap_or(1).clamp(1, 100_000) as usize;
    Some(Page {
        uri: uri.to_string(),
        title: str_of("title").unwrap_or_default(),
        facts: v
            .get("facts")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .map(scrub)
                    .filter(|f| !f.is_empty() && f.chars().count() <= 40)
                    .take(FACTS_MAX)
                    .collect()
            })
            .unwrap_or_default(),
        bold: v
            .get("bold")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(Value::as_u64).map(|i| i as usize).filter(|i| *i < n).collect())
            .unwrap_or_default(),
        numbered: v.get("numbered").and_then(Value::as_bool).unwrap_or(false),
        page: v.get("page").and_then(Value::as_u64).unwrap_or(1).clamp(1, pages as u64) as usize,
        pages: if picture.is_some() { pages } else { 1 },
        picture,
        lines,
        say: str_of("say"),
        attach: attach(v.get("attach")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model;

    fn row(id: &str, page: Option<&str>) -> Row {
        let mut r = model::rows(&format!(r#"{{"title":"t","rows":[{{"id":"{}","text":"{}"}}]}}"#, id, id))
            .unwrap()
            .rows
            .remove(0);
        r.page = page.map(str::to_string);
        r
    }

    #[test]
    fn a_page_is_read_and_held_to_its_shapes() {
        let p = page(
            "spark-shell://files/preview/x",
            r##"{"title":"notes\u001b[2J.md","facts":["2 kB","a fact far too long to be one, past forty cells","today"],
               "lines":["# one","two\u0007"],"bold":[0,9],"numbered":true,"picture":"/data/me/../etc/x.png",
               "attach":"/data/me/.cache/p.txt"}"##,
        )
        .unwrap();
        assert_eq!(p.title, "notes[2J.md");
        assert_eq!(p.facts, vec!["2 kB", "today"]);
        assert_eq!(p.lines, vec!["# one", "two"]);
        assert_eq!(p.bold, vec![0]);
        assert!(p.numbered && p.picture.is_none() && p.pages == 1);
        assert_eq!(p.attach.as_deref(), Some("/data/me/.cache/p.txt"));
        let q = page("u", r#"{"title":"r.pdf","picture":"/c/r-3.png","page":3,"pages":14,"attach":"/c/r.pdf"}"#).unwrap();
        assert_eq!((q.picture.as_deref(), q.page, q.pages, q.attach), (Some("/c/r-3.png"), 3, 14, None));
        assert!(page("u", "not json").is_none());
    }

    #[test]
    fn the_arrows_move_through_files_and_pages() {
        let rows = vec![row("a", Some("p://a")), row("dir", None), row("b", Some("p://b")), row("c", Some("p://c"))];
        let mut v = Preview::new(0, "~/docs", &rows, "b").unwrap();
        assert_eq!((v.files.len(), v.at), (3, 1));
        assert!(Preview::new(0, "~", &rows, "dir").is_none());
        assert!(v.step_file(1) && v.row().id == "c" && !v.step_file(1));
        assert!(v.step_file(-2) && v.row().id == "a" && !v.step_file(-1));
        assert_eq!(v.uri(), "p://a");
        v.shown = page("p://a", r#"{"picture":"/c/a.png","pages":3}"#);
        assert!(v.step_page(1, 3) && v.step_page(1, 3) && !v.step_page(1, 3));
        assert_eq!(v.uri(), "p://a?page=3");
        assert!(v.step_file(1) && v.page == 1 && v.shown.is_none());
    }
}
