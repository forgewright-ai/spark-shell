// Files v0 (dialog/DESIGN.md, "Files"): the status row's place, the checks, the actions page, two panes, the
// batch and its receipts and undo, the conflict page, the forms typed in the prompt, Esc's order, and the rows
// that land after a pane switch or in another view.
mod common;
use common::{app_with, ordinary, palette, pump, result, stub, Script};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, HintKey, Item, Mode, Provider, Step, View, Who, HEIGHT, WIDTH};
use spark_dialog::files::{Action, Batch, Page, Pane, Side, Verb};
use spark_dialog::model;
use spark_dialog::reply::Mark;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const CLOCK: &str = "Sun 18 Oct \u{b7} 12:04";
const HOME: &str = "spark-shell://files/rows/aG9tZQ";
const DOCS: &str = "spark-shell://files/rows/ZG9jcw";
const PICS: &str = "spark-shell://files/rows/cGljcw";
const TRASH: &str = "spark-shell://files/rows/trash";

/// The files provider's tools, as the shell offers them: copy and move take `to`, and `name` and `there` besides.
fn tools() -> Value {
    let path = json!({"type": "string", "minLength": 2, "maxLength": 4096, "format": "path"});
    let name = json!({"type": "string", "minLength": 1, "maxLength": 255});
    let one = |n: &str, t: &str, props: Value, required: Vec<&str>, destructive: bool| json!({"name": n, "title": t, "inputSchema": {"type": "object", "properties": props, "required": required, "additionalProperties": false}, "annotations": {"destructiveHint": destructive}});
    json!([
        one("files_open", "files open PATH", json!({"path": path}), vec!["path"], false),
        one("files_browse", "files browse PATH", json!({"path": path}), vec!["path"], false),
        one("files_attach", "files attach PATH", json!({"path": path}), vec!["path"], false),
        one(
            "files_rename",
            "files rename PATH",
            json!({"path": path, "name": name}),
            vec!["path", "name"],
            false
        ),
        one(
            "files_move",
            "files move PATH",
            json!({"path": path, "to": path, "name": name, "there": {"type": "string", "enum": ["keep", "replace"]}}),
            vec!["path", "to"],
            false
        ),
        one(
            "files_copy",
            "files copy PATH",
            json!({"path": path, "to": path, "name": name, "there": {"type": "string", "enum": ["keep", "replace"]}}),
            vec!["path", "to"],
            false
        ),
        one("files_trash", "files trash PATH", json!({"path": path}), vec!["path"], false),
        one("files_restore", "files restore PATH", json!({"path": path}), vec!["path"], false),
        one(
            "files_new_folder",
            "files new-folder PATH",
            json!({"path": path, "name": name}),
            vec!["path", "name"],
            false
        ),
        one(
            "files_new_text",
            "files new-text PATH",
            json!({"path": path, "name": name}),
            vec!["path", "name"],
            false
        )
    ])
}

/// The steps once a list, by kind, as the provider writes them (#123).
fn kinds() -> Value {
    let steps = json!([
        {"name": "files_rename", "ask": ["name"], "said": "rename"},
        {"name": "files_move", "pick": "to", "said": "move to a folder"},
        {"name": "files_copy", "pick": "to", "said": "copy to a folder"},
        {"name": "files_trash", "said": "trash"}
    ]);
    let mut more = vec![
        json!({"name": "files_preview", "said": "preview"}),
        json!({"name": "files_attach", "said": "attach to the next request"}),
    ];
    more.extend(steps.as_array().unwrap().iter().cloned());
    json!({"file": {"tool": {"name": "files_open", "said": "open"}, "more": more}, "dir": {"more": steps}})
}

fn file(dir: &str, name: &str, size: &str, when: &str, group: &str, folder: Option<&str>) -> Value {
    let kind = match name.rsplit('.').next() {
        Some("md") => "Markdown",
        Some("txt") => "text",
        Some("pdf") => "PDF",
        Some("jpg") => "picture",
        _ => "file",
    };
    let stamp = if when == "2025" {
        "04 Mar 2025".to_string()
    } else {
        format!("{} 09:14", when)
    };
    let mut columns = vec![size.to_string(), when.to_string()];
    columns.extend(folder.map(str::to_string));
    let wide = vec![kind.to_string(), size.to_string(), stamp, folder.unwrap_or("").to_string()];
    json!({"id": format!("files:file:{}:{}", group, name), "sign": "blank", "text": name, "columns": columns, "wide": wide, "group": group, "kind": "file", "args": {"path": format!("{}/{}", dir, name)}, "page": format!("spark-shell://files/preview/{}", name)})
}

fn dir(parent: &str, name: &str, items: &str, group: &str, uri: &str) -> Value {
    json!({"id": format!("files:dir:{}", name), "sign": "opens", "text": name, "columns": [items], "wide": ["folder", items, "", ""], "children": uri, "group": group, "kind": "dir", "args": {"path": format!("{}/{}", parent, name)}})
}

fn summary(text: &str, path: &str) -> Value {
    json!({"id": "files:here", "sign": "opens", "text": text, "columns": [], "more": [
        {"name": "files_new_folder", "arguments": {"path": path}, "ask": ["name"], "said": "new folder"},
        {"name": "files_new_text", "arguments": {"path": path}, "ask": ["name"], "said": "new text file"}]})
}

fn up(uri: &str) -> Value {
    json!({"id": "files:up", "sign": "opens", "text": "..", "columns": [], "children": uri})
}

/// Your home, as files_home() in render.rs has it, with report.pdf among the files.
fn home_rows() -> Value {
    let h = "/data/me";
    json!({"title": "~", "here": h, "kinds": kinds(), "rows": [
        dir(h, "documents", "12 items", "home", DOCS),
        dir(h, "downloads", "3 items", "home", "spark-shell://files/rows/ZG93bg"),
        dir(h, "pictures", "40 items", "home", PICS),
        file(h, "notes.md", "2 KB", "18 Oct", "home", None),
        file(h, "report.pdf", "4.5 MB", "today", "home", None),
        file(h, "todo.txt", "1 KB", "2025", "home", None),
        {"id": "files:trash", "sign": "opens", "text": "trash", "columns": ["2 items"], "wide": ["", "2 items", "", ""], "children": TRASH, "group": "home"},
        file("/data/me/downloads", "invoice-0412.pdf", "120 KB", "today", "recent", Some("downloads")),
        file("/data/me/camera", "photo-0412.jpg", "4.8 MB", "yesterday", "recent", Some("camera")),
        file(h, "notes.md", "2 KB", "18 Oct", "recent", Some("~")),
        {"id": "files:drive:s", "sign": "opens", "text": "STICK", "columns": ["14.2 GB free"], "wide": ["", "14.2 GB free", "", ""], "children": "spark-shell://files/rows/c3RpY2s", "group": "drives"},
        summary("this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB", h)
    ], "short": []})
}

fn docs_rows() -> Value {
    let d = "/data/me/documents";
    json!({"title": "~/documents", "here": d, "kinds": kinds(), "rows": [
        up(HOME),
        dir(d, "drafts", "3 items", "", "spark-shell://files/rows/ZHJhZnRz"),
        file(d, "notes.md", "2 KB", "18 Oct", "", None),
        file(d, "todo.txt", "1 KB", "2025", "", None),
        summary("this folder \u{b7} 1 folder \u{b7} 2 files \u{b7} 3 KB", d)
    ], "short": []})
}

/// The pictures, with the names of `also` in them too (a conflict for a copy of each).
fn pics_rows(also: &[&str]) -> Value {
    let p = "/data/me/pictures";
    let mut rows = vec![
        up(HOME),
        dir(p, "2024", "120 items", "", "spark-shell://files/rows/MjAyNA"),
        file(p, "holiday.jpg", "4.8 MB", "today", "", None),
        file(p, "photo-0412.jpg", "4.8 MB", "yesterday", "", None),
    ];
    for name in also {
        rows.push(file(p, name, "1 KB", "today", "", None));
    }
    rows.push(summary("this folder \u{b7} 1 folder \u{b7} 2 files \u{b7} 9.6 MB", p));
    json!({"title": "~/pictures", "here": p, "kinds": kinds(), "rows": rows, "short": []})
}

fn trash_rows() -> Value {
    json!({"title": "trash", "kinds": {"trashed": {"tool": {"name": "files_restore", "said": "restore"}}}, "rows": [
        {"id": "files:trashed:old.txt", "sign": "blank", "text": "old.txt", "columns": ["3 B", "today", "docs"], "kind": "trashed", "args": {"path": "/data/me/docs/old.txt"}},
        {"id": "files:here", "sign": "opens", "text": "the trash \u{b7} 1 item \u{b7} 3 B", "columns": [], "more": [{"name": "files_empty", "arguments": {}, "said": "empty the trash"}]}
    ], "short": []})
}

fn root() -> Value {
    json!({"title": "files", "rows": [{"id": "files:root:a", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": HOME, "group": null}], "short": ["files:root:a"]})
}

fn provider() -> Provider {
    let mut p = Provider::new("files");
    p.title = "your home folder".into();
    p.rows = model::rows(&root().to_string()).unwrap();
    p.tools = model::tools(&json!({"tools": tools()}));
    p.ready = true;
    p
}

/// Files at your home, notes.md lit, drawn as the goldens are: the files provider alone, a model and talk.
fn files_app() -> App {
    let cfg = Config {
        model: true,
        talk: true,
        close: true,
        plus: true,
        ..Config::default()
    };
    let mut app = App::new(cfg, &[]);
    app.providers = vec![provider()];
    app.model_name = Some("gemma4-26b-a4b".into());
    app.voice_on = true;
    app.view = View::Folder(0, HOME.into());
    app.came_from = vec![View::Home];
    app.folder = Some((0, HOME.into(), model::rows(&home_rows().to_string()).unwrap()));
    app.in_list = true;
    app.sel = 3;
    app
}

/// The active pane on `uri` with these rows.
fn at(app: &mut App, uri: &str, rows: Value) {
    app.view = View::Folder(0, uri.into());
    app.folder = Some((0, uri.into(), model::rows(&rows.to_string()).unwrap()));
}

fn pane(uri: &str, rows: Option<Value>) -> Pane {
    Pane {
        uri: uri.into(),
        rows: rows.map(|r| model::rows(&r.to_string()).unwrap()),
        came_from: vec![View::Home],
        ..Pane::default()
    }
}

fn render(app: &App, name: &str) -> spark_dialog::ui::Drawn {
    render_at(app, name, WIDTH, HEIGHT)
}

/// The app drawn at w by h in both palettes: the same grid of slots, the grid kept in golden/ (as render.rs keeps it).
fn render_at(app: &App, name: &str, w: u16, h: u16) -> spark_dialog::ui::Drawn {
    let mut grids = vec![];
    let mut drawn = spark_dialog::ui::Drawn::default();
    for pal in ["tokyonight-night", "solarized-light"] {
        let p = palette(pal);
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        assert_eq!(app.size, (w, h), "{}: the app is told the size it is drawn at", name);
        drawn = spark_dialog::ui::draw(app, &p, CLOCK, &mut b);
        if let Ok(dir) = std::env::var("RENDER_HTML") {
            let page = format!("<!doctype html><meta charset=utf-8><body style=\"margin:0;padding:28px;background:#111;font:16px 'DejaVu Sans Mono',Menlo,monospace\">{}</body>", common::html_runs(&b, &p, &format!("{} \u{b7} {} \u{b7} {}x{}", name, pal, w, h), "PICTURE"));
            std::fs::write(format!("{}/{}-{}.html", dir, name, pal), page).unwrap();
        }
        let s = spark_dialog::ui::snapshot(&b, &p);
        let codes = s.split_once("\n\n").map(|(_, c)| c).unwrap_or("");
        assert!(!codes.contains('?'), "{} in {}: a color that is no slot of the palette\n{}", name, pal, s);
        grids.push(s);
    }
    assert_eq!(grids[0], grids[1], "{}: the two palettes draw different grids", name);
    let path = format!("{}/tests/golden/{}.txt", env!("CARGO_MANIFEST_DIR"), name);
    if std::env::var("UPDATE_GOLDEN").is_ok() {
        std::fs::write(&path, &grids[0]).unwrap();
    }
    let want = std::fs::read_to_string(&path).unwrap_or_default();
    assert_eq!(grids[0], want, "{} differs from {} (UPDATE_GOLDEN=1 after looking at it)", name, path);
    drawn
}

/// The app drawn in tokyonight-night: where things landed.
fn draw(app: &App) -> spark_dialog::ui::Drawn {
    let p = palette("tokyonight-night");
    let (w, h) = app.size;
    let mut b = Buffer::empty(Rect::new(0, 0, w, h));
    spark_dialog::ui::draw(app, &p, CLOCK, &mut b)
}

/// The rows of the screen as text, in tokyonight-night.
fn screen(app: &App) -> Vec<String> {
    let p = palette("tokyonight-night");
    let (w, h) = app.size;
    let mut b = Buffer::empty(Rect::new(0, 0, w, h));
    spark_dialog::ui::draw(app, &p, CLOCK, &mut b);
    (0..h).map(|y| (0..w).map(|x| b[(x, y)].symbol().to_string()).collect()).collect()
}

fn hint(app: &App) -> String {
    app.hint().iter().map(|(t, _)| t.as_str()).collect()
}

/// The labels of a page of files, in order; a blank line as an empty label.
fn labels(app: &App) -> Vec<String> {
    app.items()
        .iter()
        .filter_map(|it| match it {
            Item::Files(l) => Some(l.label.clone()),
            _ => None,
        })
        .collect()
}

fn lit(app: &App) -> Option<String> {
    app.picks().get(app.sel).and_then(|it| match it {
        Item::Folder(i) => app.folder.as_ref().map(|(_, _, r)| r.rows[*i].text.clone()),
        Item::Files(l) => Some(l.label.clone()),
        _ => None,
    })
}

/// The pick index of the row named, in the list's order.
fn row(app: &App, name: &str) -> usize {
    app.picks()
        .iter()
        .position(|it| matches!(it, Item::Folder(i) if app.folder.as_ref().unwrap().2.rows[*i].text == name))
        .unwrap_or_else(|| panic!("no row {}", name))
}

fn light_row(app: &mut App, name: &str) {
    let n = row(app, name);
    app.light(n);
}

fn page_row(app: &mut App, label: &str) {
    let n = app
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Files(l) if l.label == label))
        .unwrap_or_else(|| panic!("no page row {}: {:?}", label, labels(app)));
    app.light(n);
}

// ---- the status row

#[test]
fn the_status_row_says_the_place_the_rows_own_folder_else_the_folder_on_screen() {
    let mut app = files_app();
    assert_eq!(
        app.selected_line().as_deref(),
        Some("notes.md \u{b7} Markdown \u{b7} 2 KB \u{b7} 18 Oct 09:14 \u{b7} ~"),
        "name, kind, size, the date with its time, the place"
    );
    light_row(&mut app, "invoice-0412.pdf");
    assert_eq!(
        app.selected_line().as_deref(),
        Some("invoice-0412.pdf \u{b7} PDF \u{b7} 120 KB \u{b7} today 09:14 \u{b7} downloads"),
        "a recent file: its own folder"
    );
    light_row(&mut app, "documents");
    assert_eq!(
        app.selected_line().as_deref(),
        Some("documents \u{b7} folder \u{b7} 12 items \u{b7} ~"),
        "a folder: name, folder, count, place"
    );
    at(&mut app, DOCS, docs_rows());
    light_row(&mut app, "todo.txt");
    assert_eq!(
        app.selected_line().as_deref(),
        Some("todo.txt \u{b7} text \u{b7} 1 KB \u{b7} 04 Mar 2025 \u{b7} ~/documents")
    );
    assert_eq!(
        app.title() + " \u{b7} " + &app.subtitle(),
        "files \u{b7} ~/documents",
        "the header writes the place the same way"
    );
}

// ---- the checks

#[test]
fn insert_checks_the_lit_row_moves_the_bar_down_and_the_status_row_counts() {
    let mut app = files_app();
    assert!(app.cfg.keys.help().contains(&("check", "Insert")), "a named action, in help");
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    app.hint_key(HintKey::Check);
    assert!(app.files.checked("files:file:home:notes.md"), "checked by its id");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "the bar a row down");
    app.hint_key(HintKey::Check);
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"));
    assert_eq!(
        app.selected_line().as_deref(),
        Some("2 checked \u{b7} 4.5 MB"),
        "the count and the size, in place of the lit row's line"
    );
    assert_eq!(app.files_checked_line().as_deref(), Some("2 checked \u{b7} 4.5 MB"));
    // the sign and the words' column: as a checked list draws its picks
    let rows = screen(&app);
    let notes = rows.iter().find(|r| r.contains("notes.md") && r.contains("18 Oct")).unwrap();
    assert!(
        notes.starts_with("    \u{2713} notes.md"),
        "a check before the name, the words at 6: {:?}",
        notes
    );
    let docs = rows.iter().find(|r| r.contains("documents")).unwrap();
    assert!(
        docs.starts_with("      documents"),
        "every row's words move to 6 while any is checked: {:?}",
        docs
    );
    // not on the trash, the summary row, a drive or ..
    light_row(&mut app, "trash");
    app.hint_key(HintKey::Check);
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("only a file or a folder can be checked"));
    assert_eq!(lit(&app).as_deref(), Some("trash"), "the bar stays");
    light_row(&mut app, "STICK");
    app.hint_key(HintKey::Check);
    assert!(!app.files.checked("files:drive:s"));
    // Insert on a checked row unchecks it
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Check);
    assert!(!app.files.checked("files:file:home:notes.md"));
    assert_eq!(app.selected_line().as_deref(), Some("1 checked \u{b7} 4.5 MB"));
    // a folder is checked too, and adds nothing to the size
    light_row(&mut app, "documents");
    app.hint_key(HintKey::Check);
    assert_eq!(app.selected_line().as_deref(), Some("2 checked \u{b7} 4.5 MB"));
    // in the prompt, Insert says what to do
    app.in_list = false;
    app.hint_key(HintKey::Check);
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("nothing is lit: an arrow or a click lights a row")
    );
}

#[test]
fn checks_keep_through_a_filter_and_go_with_esc_first_then_another_folder() {
    let mut app = files_app();
    app.hint_key(HintKey::Check);
    light_row(&mut app, "todo.txt");
    app.hint_key(HintKey::Check);
    for c in "notes".chars() {
        app.typed(c);
    }
    assert_eq!(
        app.picks().iter().filter(|it| matches!(it, Item::Folder(_))).count(),
        2,
        "the two notes.md: {:?}",
        app.picks()
    );
    assert!(
        app.files.checked("files:file:home:notes.md") && app.files.checked("files:file:home:todo.txt"),
        "kept through the filter"
    );
    assert_eq!(app.selected_line().as_deref(), Some("2 checked \u{b7} 3 KB"), "counted whole, filtered or not");
    app.escape();
    assert!(app.input.is_empty(), "the first Esc clears the words");
    assert!(app.files_checks_any(), "the checks stand");
    app.escape();
    assert!(
        !app.files_checks_any() && matches!(app.view, View::Folder(..)),
        "the next Esc clears the checks, and stays"
    );
    app.escape();
    assert_eq!(app.view, View::Home, "the next goes back");
    // another folder opened: the checks go with the one left
    let mut app = files_app();
    app.hint_key(HintKey::Check);
    light_row(&mut app, "documents");
    app.enter();
    assert!(matches!(&app.view, View::Folder(0, u) if u == DOCS));
    assert!(app.files.checks.is_empty(), "the pane's checks go when it opens another folder");
    // a preview and back leaves them
    let mut app = files_app();
    app.hint_key(HintKey::Check);
    light_row(&mut app, "report.pdf");
    app.typed(' ');
    assert_eq!(app.view, View::Preview);
    app.escape();
    assert!(app.files_checks_any(), "back from the preview, the checks as they were");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"));
}

#[test]
fn files_checked_golden() {
    let mut app = files_app();
    app.hint_key(HintKey::Check);
    light_row(&mut app, "report.pdf");
    app.hint_key(HintKey::Check);
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"));
    render(&app, "files-checked");
}

// ---- the actions page

#[test]
fn right_opens_the_rows_actions_then_the_folders_and_every_door_goes_back_with_the_row_lit() {
    let mut app = files_app();
    assert_eq!(hint(&app), "Back Esc   Actions \u{2192}   Preview Space");
    app.right();
    assert!(app.files_page_open() && matches!(app.files.page, Page::Actions(_)));
    assert_eq!(format!("{} \u{b7} {}", app.title(), app.subtitle()), "files \u{b7} notes.md");
    assert_eq!(
        labels(&app),
        [
            "open",
            "preview",
            "attach to the next request",
            "rename",
            "move to a folder",
            "copy to a folder",
            "trash",
            "check",
            "",
            "this folder",
            "new folder",
            "new text file",
            "two panes",
            "open in the system file manager"
        ],
        "the row's actions in the provider's order, check, then the folder's under a heading"
    );
    let check = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "check" => Some(l.key.clone()),
            _ => None,
        })
        .unwrap();
    assert_eq!(check, "Insert", "its key as a chip beside it");
    assert!(app.in_list && app.sel == 0, "the first row lit");
    assert_eq!(hint(&app), "Back Esc");
    assert!(app.can_go_back(), "the header's back stands");
    for door in ["esc", "left", "backspace"] {
        app.right();
        match door {
            "esc" => app.escape(),
            "left" => app.left(),
            _ => app.backspace(),
        }
        assert!(!app.files_page_open(), "{} goes back", door);
        assert_eq!(lit(&app).as_deref(), Some("notes.md"), "{}: the row lit again", door);
        assert!(app.in_list);
    }
    // the chip reads Insert from the keys: a rebinding is read on the page
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"check":"F6"}"#).unwrap();
    app.right();
    let check = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "check" => Some(l.key.clone()),
            _ => None,
        })
        .unwrap();
    assert_eq!(check, "F6");
    app.escape();
    // the page keeps the dialog's own width in a wide window
    app.size = (150, 46);
    app.right();
    assert_eq!(app.col_w(), 60, "a page of choices is 60 cells wide");
    app.escape();
    assert_eq!(app.col_w(), 120, "the list takes its 120 again");
}

#[test]
fn a_folders_page_the_summary_rows_and_the_checked_sets() {
    let mut app = files_app();
    light_row(&mut app, "documents");
    app.right();
    assert_eq!(
        labels(&app)[..6],
        ["open", "rename", "move to a folder", "copy to a folder", "trash", "check"],
        "a folder's row: open, then its steps, then check"
    );
    page_row(&mut app, "open");
    app.enter();
    assert!(
        matches!(&app.view, View::Folder(0, u) if u == DOCS) && !app.files_page_open(),
        "open opens the folder: {:?}",
        app.view
    );
    // the summary row: Enter and Right open the folder's actions alone, the header the folder's place
    let mut app = files_app();
    light_row(&mut app, "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB");
    app.enter();
    assert!(app.files_page_open());
    assert_eq!(app.subtitle(), "~");
    assert_eq!(
        labels(&app),
        ["this folder", "new folder", "new text file", "two panes", "open in the system file manager"]
    );
    app.escape();
    app.right();
    assert_eq!(labels(&app)[0], "this folder");
    app.escape();
    // `..`: the folder's alone too; Enter on it opens the folder above
    at(&mut app, DOCS, docs_rows());
    light_row(&mut app, "..");
    app.right();
    assert_eq!(labels(&app)[0], "this folder");
    assert_eq!(app.subtitle(), "~/documents");
    app.escape();
    app.enter();
    assert!(matches!(&app.view, View::Folder(0, u) if u == HOME), "Enter on .. opens the folder above");
    // a drive: open, then the folder's
    let mut app = files_app();
    light_row(&mut app, "STICK");
    app.right();
    assert_eq!(labels(&app)[0], "open");
    app.escape();
    // the checked set: the header counts, the rows act on every checked file
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Check);
    app.hint_key(HintKey::Check);
    light_row(&mut app, "documents");
    app.right();
    assert_eq!(app.subtitle(), "2 checked", "whichever row is lit");
    assert_eq!(
        labels(&app),
        [
            "copy to a folder",
            "move to a folder",
            "trash",
            "uncheck all",
            "",
            "this folder",
            "new folder",
            "new text file",
            "two panes",
            "open in the system file manager"
        ]
    );
    page_row(&mut app, "uncheck all");
    app.enter();
    assert!(!app.files_checks_any() && !app.files_page_open());
    // a click on a menu's row acts at once; check from the page reads uncheck on a checked row
    let mut app = files_app();
    app.right();
    let t0 = Instant::now();
    let n = app.picks().iter().position(|it| matches!(it, Item::Files(l) if l.label == "check")).unwrap();
    app.clicked(n, t0);
    assert!(
        !app.files_page_open() && app.files.checked("files:file:home:notes.md"),
        "one click checks and goes back"
    );
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "and the bar moves down, as Insert does");
    light_row(&mut app, "notes.md");
    app.right();
    assert_eq!(
        app.subtitle(),
        "1 checked",
        "a check standing, the page is the checked set's whichever row is lit"
    );
    // the wheel on the page: a row at a time
    app.sel = 0;
    app.wheel(1);
    assert_eq!(app.sel, 1);
    app.escape();
    // no system file manager offered: no row for it
    app.providers[0].tools.retain(|t| t.name != "files_browse");
    app.right();
    assert!(!labels(&app).contains(&"open in the system file manager".to_string()));
}

#[test]
fn preview_and_a_step_from_the_page_act_on_the_row_and_come_back_to_the_list() {
    let mut app = files_app();
    app.right();
    page_row(&mut app, "preview");
    app.enter();
    assert_eq!(app.view, View::Preview, "preview opens the row's preview");
    assert_eq!(app.preview.as_ref().unwrap().row().text, "notes.md");
    app.escape();
    assert!(matches!(app.view, View::Folder(..)) && !app.files_page_open());
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    // copy to a folder in one pane: the picker, as today
    app.right();
    page_row(&mut app, "copy to a folder");
    app.enter();
    assert!(
        app.picking.as_ref().is_some_and(|pk| pk.step.is_some() && pk.field == "to"),
        "the folder is picked: {:?}",
        app.picking
    );
    assert!(!app.files_page_open());
    app.escape();
    assert!(app.picking.is_none());
}

// ---- two panes

#[test]
fn two_panes_open_beside_the_first_switch_with_ctrl_tab_and_keep_each_panes_state() {
    let mut app = files_app();
    assert!(app.cfg.keys.help().contains(&("pane", "Ctrl+Tab")), "a named action, in help");
    app.files_activate(Action::Panes(true));
    assert!(
        app.two_panes() && app.files.other.as_ref().is_some_and(|o| o.uri == HOME && o.rows.is_some()),
        "the same folder beside"
    );
    assert_eq!(app.files.other_side, Side::Right);
    assert_eq!(hint(&app), "Back Esc   Actions \u{2192}   Preview Space   Pane Ctrl+Tab");
    app.right();
    assert!(
        labels(&app).contains(&"one pane".to_string()),
        "the folder's action reads one pane while two stand"
    );
    app.escape();
    // the other pane on the pictures: each pane keeps its words, its checks and its selection
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    app.hint_key(HintKey::Check);
    for c in "notes".chars() {
        app.typed(c);
    }
    app.hint_key(HintKey::Pane);
    assert_eq!(app.files.other_side, Side::Left, "the panes swapped sides: the active is the right one now");
    assert_eq!(app.subtitle(), "~/pictures", "the header names the active pane's place");
    assert!(app.input.is_empty(), "the other pane's own words: none");
    assert!(!app.files_checks_any(), "and no checks");
    assert!(app.in_list, "the bar is the active pane's");
    assert_eq!(app.sel, 0);
    light_row(&mut app, "holiday.jpg");
    app.hint_key(HintKey::Check);
    assert_eq!(lit(&app).as_deref(), Some("photo-0412.jpg"));
    app.hint_key(HintKey::Pane);
    assert_eq!(app.input, "notes", "back in the first pane: its words");
    assert_eq!(app.subtitle(), "~");
    assert!(app.files.checked("files:file:home:notes.md") && !app.files.checked("files:file::holiday.jpg"));
    let other = app.files.other.clone().unwrap();
    assert_eq!(other.checks, vec!["files:file::holiday.jpg".to_string()], "the other pane's checks kept aside");
    assert_eq!(other.sel, 3, "its selection too");
    assert_eq!(app.prompts.restore(&View::Folder(0, PICS.into())), "", "and its own words, none");
    // one pane closes it
    app.set_draft("");
    app.files_activate(Action::Panes(false));
    assert!(app.files.other.is_none() && !app.two_panes());
    assert_eq!(hint(&app), "Back Esc   Actions \u{2192}   Preview Space");
    // a narrow window refuses
    app.size = (50, 40);
    app.files_activate(Action::Panes(true));
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("two panes need a window 60 cells wide"));
    assert!(app.files.other.is_none());
}

#[test]
fn a_click_on_the_other_pane_makes_it_active_and_selects_its_row_a_second_opens_it() {
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    assert!(app.two_panes());
    let t0 = Instant::now();
    let drawn = draw(&app);
    assert!(!drawn.other_picks.is_empty(), "the other pane's rows take a click: {:?}", drawn.other_picks);
    assert!(drawn.other_path.is_some(), "and its path line");
    assert_eq!(drawn.columns, (0, 30), "the bar spans the active pane's half");
    assert_eq!(drawn.other_columns, (30, 60));
    let n = drawn.other_picks.iter().find(|(_, n)| *n == 1).map(|(_, n)| *n).unwrap(); // 2024
    app.pane_clicked(n, t0);
    assert!(matches!(&app.view, View::Folder(0, u) if u == PICS), "the other pane is active");
    assert_eq!(app.subtitle(), "~/pictures", "the header names its place");
    assert_eq!(lit(&app).as_deref(), Some("2024"), "and that row is selected");
    assert_eq!(app.files.other.as_ref().unwrap().uri, HOME, "the first pane waits aside");
    app.pane_clicked(0, t0 + Duration::from_millis(100));
    assert!(
        matches!(&app.view, View::Folder(0, u) if u == HOME),
        "a click on the first pane makes it active again"
    );
    app.pane_clicked(1, t0 + Duration::from_millis(200));
    app.clicked(1, t0 + Duration::from_millis(300));
    assert!(
        matches!(&app.view, View::Folder(0, u) if u.ends_with("MjAyNA")),
        "a second click opens the folder: {:?}",
        app.view
    );
    // the status row is the active pane's; Space previews the active pane's file in the whole window, Esc comes back
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    assert_eq!(
        app.selected_line().as_deref(),
        Some("notes.md \u{b7} Markdown \u{b7} 2 KB \u{b7} 18 Oct 09:14 \u{b7} ~")
    );
    app.typed(' ');
    assert_eq!(app.view, View::Preview);
    assert_eq!(app.col_w(), 60, "the whole window");
    app.escape();
    assert!(app.two_panes() && lit(&app).as_deref() == Some("notes.md"), "the panes as they were");
    // Esc goes back in the active pane alone: the other stays
    app.escape();
    assert_eq!(app.view, View::Home);
    assert!(app.files.other.is_some(), "kept while the dialog lives, so files reopens in two panes");
}

#[test]
fn files_two_panes_goldens() {
    let mut app = files_app();
    at(&mut app, DOCS, docs_rows());
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    light_row(&mut app, "todo.txt");
    render(&app, "files-two-panes");
    app.size = (120, 40);
    render_at(&app, "full-files-two-panes", 120, 40);
    // below 60 cells the active pane alone is drawn, nothing said
    app.size = (50, 40);
    let rows = screen(&app);
    assert!(!rows.iter().any(|r| r.contains("~/pictures")), "the other pane waits");
    assert!(rows.iter().any(|r| r.contains("todo.txt")));
    assert!(app.reply.is_none());
}

#[test]
fn copy_to_the_other_pane_refuses_the_same_folder_and_what_is_no_folder() {
    let mut app = files_app();
    app.files_activate(Action::Panes(true));
    app.right();
    assert!(
        labels(&app).contains(&"copy to ~".to_string()) && labels(&app).contains(&"move to ~".to_string()),
        "{:?}",
        labels(&app)
    );
    page_row(&mut app, "copy to ~");
    app.enter();
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("the other pane shows this folder: open another there")
    );
    assert!(app.running.is_none() && app.files.batch.is_none(), "nothing ran");
    app.files.other = Some(pane(TRASH, Some(trash_rows())));
    app.right();
    assert!(labels(&app).contains(&"copy to the other pane".to_string()), "{:?}", labels(&app));
    page_row(&mut app, "move to the other pane");
    app.enter();
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("the other pane is not a folder"));
}

// ---- the batch, with a stub provider that answers as the shell does

type Calls = Arc<Mutex<Vec<Value>>>;

/// A stub files provider: your home, the documents, the pictures (with `also` in them) and the trash; a call of a
/// name in `refuse` is refused as the shell refuses a name already there; the rest answer with a receipt and an undo.
fn files_stub(calls: Calls, also: Vec<&'static str>, refuse: Vec<&'static str>) -> Script {
    let tools = tools();
    let root = root();
    Box::new(move |v, send| {
        if v.get("method").and_then(Value::as_str) == Some("resources/read") {
            let uri = v.pointer("/params/uri").and_then(Value::as_str).unwrap_or("").to_string();
            let rows = match uri.as_str() {
                HOME => Some(home_rows()),
                DOCS => Some(docs_rows()),
                PICS => Some(pics_rows(&also)),
                TRASH => Some(trash_rows()),
                _ => None,
            };
            if let Some(rows) = rows {
                calls.lock().unwrap().push(json!({"read": uri}));
                return send(result(
                    &v["id"],
                    json!({"contents": [{"uri": uri, "mimeType": "application/json", "text": rows.to_string()}]}),
                ));
            }
        }
        if let Some(r) = ordinary("files", v, &tools, &root) {
            return send(r);
        }
        if v.get("method").and_then(Value::as_str) == Some("tools/call") {
            calls.lock().unwrap().push(v["params"].clone());
            let name = v.pointer("/params/name").and_then(Value::as_str).unwrap_or("").to_string();
            let path = v.pointer("/params/arguments/path").and_then(Value::as_str).unwrap_or("").to_string();
            let file = path.rsplit('/').next().unwrap_or("").to_string();
            if refuse.contains(&file.as_str()) {
                return send(result(
                    &v["id"],
                    json!({"content": [{"type": "text", "text": format!("files: {} is there already", file)}], "isError": true}),
                ));
            }
            let to = v.pointer("/params/arguments/to").and_then(Value::as_str).unwrap_or("").to_string();
            let sc = match name.as_str() {
                "files_copy" => {
                    json!({"receipt": format!("{} copied to ~/pictures", file), "undo": {"name": "files_trash", "arguments": {"path": format!("{}/{}", to, file)}}})
                }
                "files_move" => {
                    let from = path.rsplit_once('/').map(|(d, _)| d.to_string()).unwrap_or_default();
                    json!({"receipt": format!("{} moved to ~/pictures", file), "undo": {"name": "files_move", "arguments": {"path": format!("{}/{}", to, file), "to": from}}})
                }
                "files_trash" => json!({"receipt": format!("{} is in the trash", file), "undo": {"name": "files_restore", "arguments": {"path": path}}}),
                _ => json!({"receipt": format!("{} {}", name, file)}),
            };
            send(result(
                &v["id"],
                json!({"content": [{"type": "text", "text": sc["receipt"].as_str().unwrap_or("").to_string()}], "structuredContent": sc, "isError": false}),
            ));
        }
    })
}

type Started = (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>, Calls);

/// The files open at your home against the stub, notes.md lit.
fn started(also: Vec<&'static str>, refuse: Vec<&'static str>) -> Started {
    let (mut app, rx, tx) = app_with(&["files"]);
    let calls = Arc::new(Mutex::new(vec![]));
    app.servers.push(stub(0, "files", files_stub(calls.clone(), also, refuse), tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.in_list = true;
    app.sel = 1; // files
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.folder.is_some()), "files opens the home folder");
    app.in_list = true;
    app.sel = 3;
    (app, rx, calls)
}

fn tool_calls(calls: &Calls) -> Vec<Value> {
    calls.lock().unwrap().iter().filter(|c| c.get("name").is_some()).cloned().collect()
}

/// The other pane on the pictures, read from the stub, and the home pane active again.
fn with_pictures(app: &mut App, rx: &std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>) {
    app.files.other = Some(pane(PICS, None));
    app.files_pane();
    assert!(
        pump(app, rx, |a| a.folder.as_ref().is_some_and(|(_, u, _)| u == PICS)),
        "the pictures read for the pane"
    );
    app.files_pane();
    assert!(pump(app, rx, |a| a.folder.as_ref().is_some_and(|(_, u, _)| u == HOME)));
    app.in_list = true;
    app.sel = 3;
}

#[test]
fn several_checked_files_copy_one_after_another_with_one_receipt_and_one_undo() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.hint_key(HintKey::Check); // notes.md, report.pdf, todo.txt
    }
    assert_eq!(app.selected_line().as_deref(), Some("3 checked \u{b7} 4.5 MB"));
    app.right();
    assert_eq!(app.subtitle(), "3 checked");
    page_row(&mut app, "copy to ~/pictures");
    app.enter();
    assert!(
        app.files.batch.as_ref().is_some_and(|b| b.verb == Verb::Copy && b.total == 3),
        "a batch of three: {:?}",
        app.files.batch
    );
    assert!(app.running.is_some(), "the first step is on its way");
    // the march once the step is felt: the file and the count, on the status row
    app.files.batch.as_mut().unwrap().since = Instant::now() - Duration::from_millis(400);
    let rows = screen(&app);
    let status = &rows[spark_dialog::ui::status_y(40) as usize];
    assert!(status.contains("copying notes.md \u{b7} 1 of 3"), "{:?}", status);
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()), "the batch ends");
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 3);
    assert_eq!(
        c.iter()
            .map(|x| x["arguments"]["path"].as_str().unwrap().rsplit('/').next().unwrap().to_string())
            .collect::<Vec<_>>(),
        ["notes.md", "report.pdf", "todo.txt"],
        "in the list's order"
    );
    assert!(c.iter().all(|x| x["name"] == "files_copy" && x["arguments"]["to"] == "/data/me/pictures"));
    let r = app.reply.clone().expect("one receipt");
    assert_eq!((r.mark, r.text.as_str(), r.undo), (Mark::Done, "3 copied to ~/pictures \u{b7} 4.5 MB", true));
    assert!(!app.files_checks_any(), "the checks clear when the operation ends");
    assert_eq!(
        app.undo.as_ref().map(|u| u.call.arguments["path"].as_str().unwrap().to_string()),
        Some("/data/me/pictures/todo.txt".into()),
        "the newest first"
    );
    assert_eq!(app.files.undo_more.len(), 2);
    // undo takes the whole back, newest first, as one; the receipt counts them
    app.undo_now();
    assert!(app.files.batch.as_ref().is_some_and(|b| b.verb == Verb::PutBack && b.total == 3));
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 6);
    assert_eq!(
        c[3..]
            .iter()
            .map(|x| x["arguments"]["path"].as_str().unwrap().rsplit('/').next().unwrap().to_string())
            .collect::<Vec<_>>(),
        ["todo.txt", "report.pdf", "notes.md"]
    );
    assert!(c[3..].iter().all(|x| x["name"] == "files_trash"));
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("3 put back"));
    assert!(app.files.undo_more.is_empty() || app.undo.is_some());
}

#[test]
fn typed_undo_takes_the_whole_batch_back_and_a_refusal_never_stops_it() {
    let (mut app, rx, calls) = started(vec![], vec!["report.pdf"]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "move to ~/pictures");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 3, "the refused one stopped nothing");
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("2 of 3 moved to ~/pictures, 1 refused: report.pdf is there already"),
        "the real counts, the reason without the provider's label"
    );
    assert!(app.reply.as_ref().is_some_and(|r| r.undo));
    app.escape();
    assert!(app.reply.is_none(), "Esc clears the receipt");
    assert!(app.undo.is_some() && app.files.undo_more.len() == 1, "the undo still at hand");
    app.in_list = false;
    for c in "undo".chars() {
        app.typed(c);
    }
    assert!(!app.items().iter().any(|it| matches!(it, Item::Ask)), "undo at hand is never a question");
    app.enter();
    assert!(
        app.files.batch.as_ref().is_some_and(|b| b.verb == Verb::PutBack && b.total == 2),
        "{:?}",
        app.files.batch
    );
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("2 put back"));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 5);
    assert!(c[3..].iter().all(|x| x["name"] == "files_move"));
}

#[test]
fn esc_stops_a_batch_after_the_file_under_way_wherever_you_are_and_so_does_the_x() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    for _ in 0..3 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "trash");
    app.enter();
    assert!(app.running.is_some() && app.files.batch.as_ref().is_some_and(|b| b.verb == Verb::Trash));
    // at the home meanwhile: the transfer goes on
    app.escape();
    assert_eq!(app.view, View::Folder(0, HOME.into()), "Esc stops the batch, and goes nowhere");
    assert!(app.files.batch.as_ref().is_some_and(|b| b.stopping && b.stopped == 2), "{:?}", app.files.batch);
    assert!(app.queue.is_empty(), "the files not yet under way are not run");
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 1, "the file under way alone");
    let r = app.reply.clone().unwrap();
    assert_eq!((r.text.as_str(), r.undo), ("1 of 3 trashed, 2 not: stopped", true));
    assert!(app.quit.is_none());
    // the x: the batch stops and the dialog stays; the next x closes
    let (mut app, rx, _calls) = started(vec![], vec![]);
    for _ in 0..2 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "trash");
    app.enter();
    app.conversation();
    assert_eq!(app.view, View::Conversation, "elsewhere meanwhile");
    app.close_window();
    assert!(
        app.quit.is_none() && app.files.batch.as_ref().is_some_and(|b| b.stopping),
        "the x stops the batch, the dialog stays"
    );
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none()));
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text == "1 of 2 trashed, 1 not: stopped"),
        "{:?}",
        app.reply
    );
    app.close_window();
    assert_eq!(app.quit, Some(0), "the next x closes");
}

#[test]
fn a_single_file_goes_through_the_providers_step_as_today() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    with_pictures(&mut app, &rx);
    app.right();
    page_row(&mut app, "copy to ~/pictures");
    app.enter();
    assert!(app.files.batch.is_none(), "one file: no batch");
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && a.undo.is_some()));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 1);
    assert_eq!(c[0]["arguments"]["to"], "/data/me/pictures");
    assert!(c[0]["arguments"].get("there").is_none(), "no conflict, no there");
    assert_eq!(app.reply, Some(spark_dialog::reply::Reply::undo_only()), "a click's receipt: undo alone");
    assert!(
        pump(&mut app, &rx, |_| calls.lock().unwrap().iter().filter(|c| c["read"] == PICS).count() >= 2),
        "the other pane reads its folder again"
    );
}

// ---- conflicts

#[test]
fn a_name_already_in_the_destination_is_a_page_of_choices() {
    let (mut app, rx, calls) = started(vec!["notes.md", "todo.txt"], vec![]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "copy to ~/pictures");
    app.enter();
    assert!(matches!(app.files.page, Page::Conflict(_)), "{:?}", app.files.page);
    assert_eq!(
        format!("{} \u{b7} {}", app.title(), app.subtitle()),
        "files \u{b7} notes.md is in ~/pictures already"
    );
    let lines: Vec<(String, String)> = app
        .items()
        .iter()
        .filter_map(|it| match it {
            Item::Files(l) => Some((l.label.clone(), l.value.clone())),
            _ => None,
        })
        .collect();
    assert_eq!(
        lines,
        [
            ("skip".into(), "".into()),
            ("keep both".into(), "the copy is named notes 2.md".into()),
            ("replace".into(), "the one there goes to the trash".into()),
            ("".into(), "".into()),
            ("the other too".into(), "".into()),
            ("skip all".into(), "".into()),
            ("keep both for all".into(), "".into()),
            ("replace all".into(), "".into())
        ]
    );
    assert_eq!(hint(&app), "Back Esc");
    assert!(app.in_list && app.sel == 0);
    assert!(app.running.is_none() && tool_calls(&calls).is_empty(), "nothing runs before the answers");
    // keep both for this one: the next conflict is asked, alone
    page_row(&mut app, "keep both");
    app.enter();
    assert_eq!(app.subtitle(), "todo.txt is in ~/pictures already");
    assert_eq!(labels(&app), ["skip", "keep both", "replace"], "the last conflict: no others");
    page_row(&mut app, "replace");
    app.enter();
    assert!(!app.files_page_open(), "the answers given, the batch runs");
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 3);
    assert_eq!(c[0]["arguments"]["there"], "keep", "notes.md kept both");
    assert!(c[1]["arguments"].get("there").is_none(), "report.pdf had no conflict");
    assert_eq!(c[2]["arguments"]["there"], "replace");
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("3 copied to ~/pictures \u{b7} 4.5 MB"));
}

#[test]
fn skip_all_leaves_the_files_out_and_counts_them_and_esc_lets_the_whole_go() {
    let (mut app, rx, calls) = started(vec!["notes.md", "todo.txt"], vec![]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "move to ~/pictures");
    app.enter();
    assert_eq!(
        app.items().iter().find_map(|it| match it {
            Item::Files(l) if l.label == "keep both" => Some(l.value.clone()),
            _ => None,
        }),
        Some("moved as notes 2.md".into()),
        "a move's kept copy"
    );
    page_row(&mut app, "skip all");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 1, "report.pdf alone");
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("1 moved to ~/pictures \u{b7} 4.5 MB, 2 skipped")
    );
    // Esc on the page: the whole operation goes, nothing said
    let (mut app, rx, calls) = started(vec!["notes.md"], vec![]);
    with_pictures(&mut app, &rx);
    app.right();
    page_row(&mut app, "copy to ~/pictures");
    app.enter();
    assert!(matches!(app.files.page, Page::Conflict(_)), "one file too is asked about");
    app.escape();
    assert!(!app.files_page_open() && app.reply.is_none() && app.files.batch.is_none());
    assert_eq!(lit(&app).as_deref(), Some("notes.md"), "the list with the row lit");
    pump(&mut app, &rx, |_| false);
    assert!(tool_calls(&calls).is_empty(), "nothing ran");
    // a single file skipped: nothing copied, and the receipt says so
    app.right();
    page_row(&mut app, "copy to ~/pictures");
    app.enter();
    page_row(&mut app, "skip");
    app.enter();
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("0 copied to ~/pictures, 1 skipped"));
    assert!(tool_calls(&calls).is_empty());
}

#[test]
fn the_folder_picked_in_one_pane_is_read_for_conflicts_too() {
    let (mut app, rx, calls) = started(vec!["notes.md"], vec![]);
    app.right();
    page_row(&mut app, "copy to a folder");
    app.enter();
    assert!(app.picking.is_some());
    light_row(&mut app, "pictures");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.folder.as_ref().is_some_and(|(_, u, _)| u == PICS)), "pictures opened");
    app.in_list = true;
    app.sel = 0;
    assert_eq!(app.picks()[0], Item::Here);
    app.enter();
    assert!(
        matches!(app.files.page, Page::Conflict(_)),
        "the picked folder's rows hold the name: {:?}",
        app.files.page
    );
    assert!(app.picking.is_none());
    page_row(&mut app, "keep both");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!((c[0]["name"].as_str(), c[0]["arguments"]["there"].as_str()), (Some("files_copy"), Some("keep")));
    assert_eq!(c[0]["arguments"]["to"], "/data/me/pictures");
}

#[test]
fn files_conflict_golden() {
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md", "report.pdf", "todo.txt"]))));
    for _ in 0..3 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "copy to ~/pictures");
    app.enter();
    assert!(matches!(app.files.page, Page::Conflict(_)));
    render(&app, "files-conflict");
}

#[test]
fn files_batch_golden() {
    // the march, a third of a second in: the file and the count on the status row
    let mut app = files_app();
    let call = |name: &str| model::Call {
        name: "files_copy".into(),
        arguments: json!({"path": format!("/data/me/{}", name), "to": "/data/me/pictures"})
            .as_object()
            .unwrap()
            .clone(),
        ask: vec![],
        said: None,
        pick: None,
    };
    let steps = vec![
        (call("photo-0412.jpg"), "photo-0412.jpg".to_string(), 0u64),
        (call("todo.txt"), "todo.txt".to_string(), 0),
    ];
    let mut b = Batch::new(Verb::Copy, Some("~/pictures".into()), steps, 0);
    b.total = 5;
    b.done = vec![("notes.md".into(), Ok(()))];
    b.current = Some("photo-0412.jpg".into());
    b.since = Instant::now() - Duration::from_secs(1);
    app.files.batch = Some(b);
    app.running = Some((
        0,
        7,
        Step {
            prov: 0,
            call: call("photo-0412.jpg"),
            who: Who::Person,
            line: "files copy photo-0412.jpg".into(),
            typed: false,
        },
    ));
    render(&app, "files-batch");
}

// ---- the forms

#[test]
fn rename_new_folder_and_new_text_file_type_in_the_prompt() {
    let mut app = files_app();
    app.right();
    page_row(&mut app, "rename");
    app.enter();
    assert!(app.files_page_open() && app.files.form());
    assert_eq!(app.mode, Mode::Normal, "a form of files, not Mode::Ask");
    assert_eq!((app.input.as_str(), app.cursor), ("notes.md", 8), "the name as it is, the cursor at its end");
    assert_eq!(app.placeholder(), "the new name");
    assert_eq!(hint(&app), "Let go Esc   Save Enter");
    assert_eq!(format!("{} \u{b7} {}", app.title(), app.subtitle()), "files \u{b7} rename");
    assert!(!app.can_go_back(), "a form has no back: Esc lets it go");
    app.backspace();
    app.backspace();
    app.typed('t');
    app.typed('x');
    app.typed('t');
    app.enter();
    assert!(!app.files_page_open(), "saved: the list again");
    assert!(app.running.is_some() || app.reply.is_some(), "the step ran");
    assert_eq!(lit(&app).as_deref(), Some("notes.md"), "the row lit");
    // Esc lets a form go, words typed or none; the list is back with the row lit
    let mut app = files_app();
    app.right();
    page_row(&mut app, "rename");
    app.enter();
    app.set_draft("other");
    app.escape();
    assert!(!app.files_page_open() && app.input.is_empty() && app.running.is_none());
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    // new folder, from the summary row's actions: an empty prompt and its own placeholder
    app.right();
    page_row(&mut app, "new folder");
    app.enter();
    assert!(app.files.form() && app.input.is_empty());
    assert_eq!(app.placeholder(), "a name for the folder");
    assert_eq!(app.subtitle(), "new folder");
    app.enter();
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("type a name, or Esc lets it go"),
        "Enter with no name says so"
    );
    assert!(app.files.form());
    app.escape();
    app.right();
    page_row(&mut app, "new text file");
    app.enter();
    assert_eq!(app.placeholder(), "a name for the text file");
    app.set_draft("ideas.txt");
    app.enter();
    assert!(!app.files.form());
    // another provider's ask keeps Mode::Ask
    let mut app = files_app();
    app.providers[0].label = "notes".into();
    app.view = View::Folder(0, HOME.into());
    app.right();
    assert!(matches!(app.view, View::Steps(0)), "another provider: the list of steps as today");
}

#[test]
fn files_form_golden() {
    let mut app = files_app();
    app.right();
    page_row(&mut app, "rename");
    app.enter();
    assert_eq!(app.input, "notes.md");
    render(&app, "files-form");
}

#[test]
fn the_form_runs_the_step_with_the_name_and_both_panes_read_again() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    with_pictures(&mut app, &rx);
    let reads = |c: &Calls, uri: &str| c.lock().unwrap().iter().filter(|v| v["read"] == uri).count();
    let (home_before, pics_before) = (reads(&calls, HOME), reads(&calls, PICS));
    app.right();
    page_row(&mut app, "rename");
    app.enter();
    app.set_draft("notes2.md");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!(
        (c[0]["name"].as_str(), c[0]["arguments"]["name"].as_str()),
        (Some("files_rename"), Some("notes2.md"))
    );
    assert!(
        pump(&mut app, &rx, |_| reads(&calls, HOME) > home_before && reads(&calls, PICS) > pics_before),
        "both panes read their folders again"
    );
}

// ---- the landings

#[test]
fn rows_that_land_after_a_pane_switch_keep_the_lit_row_by_id_and_the_checks() {
    let (mut app, rx, _calls) = started(vec![], vec![]);
    app.files_activate(Action::Panes(true));
    app.hint_key(HintKey::Check); // notes.md checked, report.pdf lit
    app.hint_key(HintKey::Pane); // the other pane active: its read is on its way
    app.hint_key(HintKey::Pane); // and back, before it landed: a read of this pane is on its way too
    light_row(&mut app, "todo.txt");
    assert!(!app.files.folder_reads.is_empty(), "reads on their way: {:?}", app.files.folder_reads);
    assert!(pump(&mut app, &rx, |a| a.files.folder_reads.is_empty()), "every read landed");
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"), "the lit row by its id after the rows landed");
    assert!(app.files.checked("files:file:home:notes.md"), "the checks by theirs");
    assert!(app.files.other.as_ref().is_some_and(|o| o.rows.is_some()), "the other pane got its rows");
}

#[test]
fn a_steps_result_lands_while_another_view_shows() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    for _ in 0..2 {
        app.hint_key(HintKey::Check);
    }
    app.right();
    page_row(&mut app, "trash");
    app.enter();
    assert!(app.running.is_some());
    // to another view while the batch runs: the transfer goes on, the receipt lands there
    app.conversation();
    assert_eq!(app.view, View::Conversation);
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 2);
    assert_eq!(app.view, View::Conversation);
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("2 trashed \u{b7} 4.5 MB"));
    assert!(app.undo.is_some() && app.files.undo_more.len() == 1);
}

#[test]
fn enter_is_never_silent_in_a_files_folder() {
    let mut app = files_app();
    light_row(&mut app, "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB");
    app.enter();
    assert!(app.files_page_open(), "the summary row opens the folder's actions");
    app.escape();
    light_row(&mut app, "STICK");
    app.enter();
    assert!(matches!(&app.view, View::Folder(0, u) if u.ends_with("c3RpY2s")), "a drive opens");
}
