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
/// The key bar of a files folder, in one pane and in two.
const BAR: &str = "Back Esc   Nav \u{2190} \u{2191} \u{2193} \u{2192}   Ren F2   View F3   Open F4   Copy F5   Move F6   New F7   Trash F8   Actions F9";

/// The files provider's tools, as the shell offers them: copy and move take `to`, and `name` and `there` besides.
fn tools() -> Value {
    let path = json!({"type": "string", "minLength": 2, "maxLength": 4096, "format": "path"});
    let name = json!({"type": "string", "minLength": 1, "maxLength": 255});
    let one = |n: &str, t: &str, props: Value, required: Vec<&str>, destructive: bool| json!({"name": n, "title": t, "inputSchema": {"type": "object", "properties": props, "required": required, "additionalProperties": false}, "annotations": {"destructiveHint": destructive}});
    json!([
        one("files_open", "files open PATH", json!({"path": path}), vec!["path"], false),
        one("files_browse", "files browse PATH", json!({"path": path}), vec!["path"], false),
        one("files_app", "files app PATH", json!({"path": path}), vec!["path"], false),
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
        {"name": "files_app", "said": "open in app"},
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
        {"name": "files_new_text", "arguments": {"path": path}, "ask": ["name"], "said": "new file"},
        {"name": "files_browse", "arguments": {"path": path}, "said": "open in the system file manager"}]})
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

/// The second pane open beside the first, the bar back in the first.
fn two_panes(app: &mut App) {
    app.right();
    app.left();
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
    assert!(app.cfg.keys.help().contains(&("select", "Space")), "a named action, in help: check Space");
    assert!(app.cfg.keys.help().contains(&("view", "F3")), "and preview F3");
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    app.typed(' ');
    assert!(app.files.checked("files:file:home:notes.md"), "checked by its id");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "the bar a row down");
    app.typed(' ');
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"));
    assert_eq!(
        app.selected_line().as_deref(),
        Some("2 selected \u{b7} 4.5 MB"),
        "the count and the size, in place of the lit row's line"
    );
    assert_eq!(app.files_checked_line().as_deref(), Some("2 selected \u{b7} 4.5 MB"));
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
    app.typed(' ');
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("only a file or a folder can be selected"));
    assert_eq!(lit(&app).as_deref(), Some("trash"), "the bar stays");
    light_row(&mut app, "STICK");
    app.typed(' ');
    assert!(!app.files.checked("files:drive:s"));
    // Insert on a checked row unchecks it
    light_row(&mut app, "notes.md");
    app.typed(' ');
    assert!(!app.files.checked("files:file:home:notes.md"));
    assert_eq!(app.selected_line().as_deref(), Some("1 selected \u{b7} 4.5 MB"));
    // a folder is checked too, and adds nothing to the size
    light_row(&mut app, "documents");
    app.typed(' ');
    assert_eq!(app.selected_line().as_deref(), Some("2 selected \u{b7} 4.5 MB"));
    // in the prompt, Insert says what to do
    app.in_list = false;
    app.typed(' ');
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("nothing is lit: an arrow or a click lights a row")
    );
}

#[test]
fn checks_keep_through_a_filter_and_go_with_esc_first_then_another_folder() {
    let mut app = files_app();
    app.typed(' ');
    light_row(&mut app, "todo.txt");
    app.typed(' ');
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
    assert_eq!(app.selected_line().as_deref(), Some("2 selected \u{b7} 3 KB"), "counted whole, filtered or not");
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
    app.typed(' ');
    light_row(&mut app, "documents");
    app.enter();
    assert!(matches!(&app.view, View::Folder(0, u) if u == DOCS));
    assert!(app.files.checks.is_empty(), "the pane's checks go when it opens another folder");
    // a preview and back leaves them
    let mut app = files_app();
    app.typed(' ');
    light_row(&mut app, "report.pdf");
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview);
    app.escape();
    assert!(app.files_checks_any(), "back from the preview, the checks as they were");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"));
}

#[test]
fn files_checked_golden() {
    let mut app = files_app();
    app.typed(' ');
    light_row(&mut app, "report.pdf");
    app.typed(' ');
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"));
    render(&app, "files-checked");
}

// ---- the actions page

#[test]
fn f9_opens_the_rows_actions_then_the_folders_and_every_door_goes_back_with_the_row_lit() {
    let mut app = files_app();
    assert_eq!(hint(&app), BAR);
    app.hint_key(HintKey::Actions);
    assert!(app.files_page_open() && matches!(app.files.page, Page::Actions(_)));
    assert_eq!(format!("{} \u{b7} {}", app.title(), app.subtitle()), "files \u{b7} notes.md");
    assert_eq!(
        labels(&app),
        [
            "open",
            "open in app",
            "view",
            "attach to the next request",
            "rename",
            "copy",
            "move",
            "copy path",
            "trash",
            "select",
            "",
            "new folder",
            "new file",
            "open in the system file manager"
        ],
        "one order whatever the provider's, a blank row, the folder's; close pane only while two stand"
    );
    let keys: Vec<(String, String)> = app
        .items()
        .iter()
        .filter_map(|it| match it {
            Item::Files(l) if l.action.is_some() => Some((l.label.clone(), l.key.clone())),
            _ => None,
        })
        .collect();
    let want = [
        ("open", "Enter"),
        ("open in app", "F4"),
        ("view", "F3"),
        ("attach to the next request", ""),
        ("rename", "F2"),
        ("copy", "F5"),
        ("move", "F6"),
        ("copy path", "Ctrl+C"),
        ("trash", "F8"),
        ("select", "Space"),
        ("new folder", "F7"),
        ("new file", ""),
        ("open in the system file manager", ""),
    ];
    assert_eq!(keys, want.map(|(a, b)| (a.to_string(), b.to_string())), "each row's key beside it");
    let check = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "select" => Some(l.key.clone()),
            _ => None,
        })
        .unwrap();
    assert_eq!(check, "Space", "the select binding's label");
    assert!(app.in_list && app.sel == 0, "the first row lit");
    assert_eq!(hint(&app), "Back Esc");
    assert!(app.can_go_back(), "the header's back stands");
    app.escape();
    for door in ["esc", "backspace", "f9"] {
        app.hint_key(HintKey::Actions);
        // the arrows stay put on a page: back in files is Esc, Backspace and the header's
        app.left();
        app.right();
        assert!(app.files_page_open() && app.files.other.is_none(), "{}: the arrows stayed put", door);
        match door {
            "esc" => app.escape(),
            "backspace" => app.backspace(),
            _ => app.hint_key(HintKey::Actions),
        }
        assert!(!app.files_page_open(), "{} goes back", door);
        assert_eq!(lit(&app).as_deref(), Some("notes.md"), "{}: the row lit again", door);
        assert!(app.in_list);
    }
    // the row's key is read from the keys: a rebinding is read on the page
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"select":"F11"}"#).unwrap();
    app.hint_key(HintKey::Actions);
    let check = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "select" => Some(l.key.clone()),
            _ => None,
        })
        .unwrap();
    assert_eq!(check, "F11");
    app.escape();
    // the page keeps the dialog's own width in a wide window
    app.size = (150, 46);
    app.hint_key(HintKey::Actions);
    assert_eq!(app.col_w(), 60, "a page of choices is 60 cells wide");
    app.escape();
    assert_eq!(app.col_w(), 120, "the list takes its 120 again");
}

#[test]
fn a_folders_page_the_summary_rows_and_the_checked_sets() {
    let mut app = files_app();
    light_row(&mut app, "documents");
    app.hint_key(HintKey::Actions);
    assert_eq!(
        labels(&app)[..8],
        ["open", "open in app", "rename", "copy", "move", "copy path", "trash", "select"],
        "a folder's row: no view, the rest as a file's"
    );
    page_row(&mut app, "open");
    app.enter();
    assert!(
        matches!(&app.view, View::Folder(0, u) if u == DOCS) && !app.files_page_open(),
        "open opens the folder: {:?}",
        app.view
    );
    // the summary row: Enter and F9 open the folder's actions alone, the header the folder's place
    let mut app = files_app();
    light_row(&mut app, "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB");
    app.enter();
    assert!(app.files_page_open());
    assert_eq!(app.subtitle(), "~");
    assert_eq!(labels(&app), ["new folder", "new file", "open in the system file manager"]);
    app.escape();
    app.hint_key(HintKey::Actions);
    assert_eq!(labels(&app)[0], "new folder");
    app.escape();
    // `..`: the folder's alone too; Enter on it opens the folder above
    at(&mut app, DOCS, docs_rows());
    light_row(&mut app, "..");
    app.hint_key(HintKey::Actions);
    assert_eq!(labels(&app)[0], "new folder");
    assert_eq!(app.subtitle(), "~/documents");
    app.escape();
    app.enter();
    assert!(matches!(&app.view, View::Folder(0, u) if u == HOME), "Enter on .. opens the folder above");
    // a drive: open, then the folder's
    let mut app = files_app();
    light_row(&mut app, "STICK");
    app.hint_key(HintKey::Actions);
    assert_eq!(labels(&app)[0], "open");
    app.escape();
    // the checked set: the header counts, the rows act on every checked file
    light_row(&mut app, "notes.md");
    app.typed(' ');
    app.typed(' ');
    light_row(&mut app, "documents");
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "2 selected", "whichever row is lit");
    assert_eq!(
        labels(&app),
        [
            "copy",
            "move",
            "copy path",
            "trash",
            "deselect all",
            "",
            "new folder",
            "new file",
            "open in the system file manager"
        ]
    );
    page_row(&mut app, "deselect all");
    app.enter();
    assert!(!app.files_checks_any() && !app.files_page_open());
    // a click on a menu's row acts at once; check from the page reads uncheck on a checked row
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    let t0 = Instant::now();
    let n = app.picks().iter().position(|it| matches!(it, Item::Files(l) if l.label == "select")).unwrap();
    app.clicked(n, t0);
    assert!(
        !app.files_page_open() && app.files.checked("files:file:home:notes.md"),
        "one click checks and goes back"
    );
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "and the bar moves down, as Insert does");
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Actions);
    assert_eq!(
        app.subtitle(),
        "1 selected",
        "a check standing, the page is the checked set's whichever row is lit"
    );
    // the wheel on the page: a row at a time
    app.sel = 0;
    app.wheel(1);
    assert_eq!(app.sel, 1);
    app.escape();
}

#[test]
fn preview_and_a_step_from_the_page_act_on_the_row_and_come_back_to_the_list() {
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "view");
    app.enter();
    assert_eq!(app.view, View::Preview, "preview opens the row's preview");
    assert_eq!(app.preview.as_ref().unwrap().row().text, "notes.md");
    app.escape();
    assert!(matches!(app.view, View::Folder(..)) && !app.files_page_open());
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    // copy to a folder in one pane: the picker, as today
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
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
    two_panes(&mut app);
    assert!(
        app.two_panes() && app.files.other.as_ref().is_some_and(|o| o.uri == HOME && o.rows.is_some()),
        "the same folder beside"
    );
    assert_eq!(app.files.other_side, Side::Right);
    assert_eq!(hint(&app), BAR);
    app.hint_key(HintKey::Actions);
    assert!(labels(&app).contains(&"close pane".to_string()), "the menu closes it while two stand");
    app.escape();
    // the other pane on the pictures: each pane keeps its words, its checks and its selection
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    app.typed(' ');
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
    app.typed(' ');
    assert_eq!(lit(&app).as_deref(), Some("photo-0412.jpg"));
    app.hint_key(HintKey::Pane);
    assert_eq!(app.input, "notes", "back in the first pane: its words");
    assert_eq!(app.subtitle(), "~");
    assert!(app.files.checked("files:file:home:notes.md") && !app.files.checked("files:file::holiday.jpg"));
    let other = app.files.other.clone().unwrap();
    assert_eq!(other.checks, vec!["files:file::holiday.jpg".to_string()], "the other pane's checks kept aside");
    assert_eq!(other.sel, 3, "its selection too");
    assert_eq!(app.prompts.restore(&View::Folder(0, PICS.into())), "", "and its own words, none");
    // close pane closes it
    app.set_draft("");
    app.files_activate(Action::ClosePane);
    assert!(app.files.other.is_none() && !app.two_panes());
    assert_eq!(hint(&app), BAR);
    // a narrow window refuses
    app.size = (50, 40);
    app.right();
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
    assert_eq!(drawn.columns, (0, 29), "the bar spans the active pane's half");
    assert_eq!(drawn.other_columns, (30, 60), "a cell for the line between them");
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
    app.hint_key(HintKey::View);
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
fn below_60_cells_the_active_pane_alone_is_drawn() {
    let mut app = files_app();
    at(&mut app, DOCS, docs_rows());
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    light_row(&mut app, "todo.txt");
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
    two_panes(&mut app);
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("the other pane shows this folder: open another there")
    );
    assert!(app.running.is_none() && app.files.batch.is_none(), "nothing ran");
    app.files.other = Some(pane(TRASH, Some(trash_rows())));
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "move");
    app.enter();
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("the other pane is not a folder"));
}

// ---- the batch, with a stub provider that answers as the shell does

type Calls = Arc<Mutex<Vec<Value>>>;

/// The names that have left your home: a read after one is pushed here no longer lists it.
type Gone = Arc<Mutex<Vec<String>>>;

/// A stub files provider: your home (less the names in `gone`), the documents, the pictures (with `also` in them) and
/// the trash; a call of a name in `refuse` is refused as the shell refuses a name already there; the rest answer with
/// a receipt and an undo.
fn files_stub(calls: Calls, also: Vec<&'static str>, refuse: Vec<&'static str>, gone: Gone) -> Script {
    let tools = tools();
    let root = root();
    Box::new(move |v, send| {
        if v.get("method").and_then(Value::as_str) == Some("resources/read") {
            let uri = v.pointer("/params/uri").and_then(Value::as_str).unwrap_or("").to_string();
            let rows = match uri.as_str() {
                HOME => {
                    let mut rows = home_rows();
                    let names = gone.lock().unwrap();
                    rows["rows"].as_array_mut().unwrap().retain(|r| !names.iter().any(|n| r["text"] == n.as_str()));
                    Some(rows)
                }
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
                "files_rename" => {
                    let new = v.pointer("/params/arguments/name").and_then(Value::as_str).unwrap_or("").to_string();
                    let dir = path.rsplit_once('/').map(|(d, _)| d.to_string()).unwrap_or_default();
                    json!({"receipt": format!("{} renamed", file), "undo": {"name": "files_rename", "arguments": {"path": format!("{}/{}", dir, new), "name": file}}})
                }
                _ => json!({"receipt": format!("{} {}", name, file)}),
            };
            send(result(
                &v["id"],
                json!({"content": [{"type": "text", "text": sc["receipt"].as_str().unwrap_or("").to_string()}], "structuredContent": sc, "isError": false}),
            ));
        }
    })
}

type Rx = std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>;
type Started = (App, Rx, Calls);

/// The files open at your home against the stub, notes.md lit.
fn started(also: Vec<&'static str>, refuse: Vec<&'static str>) -> Started {
    let (app, rx, calls, _) = started_gone(also, refuse);
    (app, rx, calls)
}

/// As started, with the names that have left your home to push to.
fn started_gone(also: Vec<&'static str>, refuse: Vec<&'static str>) -> (App, Rx, Calls, Gone) {
    let (mut app, rx, tx) = app_with(&["files"]);
    let calls = Arc::new(Mutex::new(vec![]));
    let gone: Gone = Arc::new(Mutex::new(vec![]));
    app.servers.push(stub(0, "files", files_stub(calls.clone(), also, refuse, gone.clone()), tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.in_list = true;
    app.sel = 1; // files
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.folder.is_some()), "files opens the home folder");
    app.in_list = true;
    app.sel = 3;
    (app, rx, calls, gone)
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
        app.typed(' '); // notes.md, report.pdf, todo.txt
    }
    assert_eq!(app.selected_line().as_deref(), Some("3 selected \u{b7} 4.5 MB"));
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "3 selected");
    page_row(&mut app, "copy");
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
    assert_eq!((r.mark, r.text.as_str(), r.undo), (Mark::Done, "3 files copied to ~/pictures", true));
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
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("3 undone"));
    assert!(app.files.undo_more.is_empty() || app.undo.is_some());
}

#[test]
fn typed_undo_takes_the_whole_batch_back_and_a_refusal_never_stops_it() {
    let (mut app, rx, calls) = started(vec![], vec!["report.pdf"]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "move");
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
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("2 undone"));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 5);
    assert!(c[3..].iter().all(|x| x["name"] == "files_move"));
}

#[test]
fn esc_stops_a_batch_after_the_file_under_way_wherever_you_are_and_so_does_the_x() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    for _ in 0..3 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "trash");
    app.enter();
    assert!(app.running.is_some() && app.files.batch.as_ref().is_some_and(|b| b.verb == Verb::Trash));
    // at the home meanwhile: the transfer goes on
    app.escape();
    assert_eq!(app.view, View::Folder(0, HOME.into()), "Esc stops the batch, and goes nowhere");
    assert!(app.files.batch.as_ref().is_some_and(|b| b.stopping && b.stopped == 2), "{:?}", app.files.batch);
    assert!(app.queue.is_empty(), "the files not yet under way are not run");
    // the march says so while the step under way lands; Esc and the x change nothing until it has
    app.files.batch.as_mut().unwrap().since = Instant::now() - Duration::from_millis(400);
    let status = screen(&app)[spark_dialog::ui::status_y(40) as usize].clone();
    assert!(status.contains("stopping after notes.md \u{b7} 1 of 3"), "{:?}", status);
    app.escape();
    app.close_window();
    assert!(
        app.quit.is_none() && app.view == View::Folder(0, HOME.into()) && app.files.batch.is_some(),
        "swallowed"
    );
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 1, "the file under way alone");
    let r = app.reply.clone().unwrap();
    assert_eq!((r.text.as_str(), r.undo), ("1 of 3 trashed, 2 not: stopped", true));
    assert!(app.quit.is_none());
    // the x: the batch stops and the dialog stays; the next x closes
    let (mut app, rx, _calls) = started(vec![], vec![]);
    for _ in 0..2 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
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
    app.typed(' '); // notes.md alone checked: one file, one step
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "1 selected");
    page_row(&mut app, "copy");
    app.enter();
    assert!(app.files.batch.is_none(), "one file: no batch");
    assert!(!app.files_checks_any(), "the checks clear when the step is sent");
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && a.undo.is_some()));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 1);
    assert_eq!(c[0]["arguments"]["to"], "/data/me/pictures");
    assert!(c[0]["arguments"].get("there").is_none(), "no conflict, no there");
    let r = app.reply.clone().expect("the receipt");
    assert_eq!(
        (r.mark, r.text.as_str(), r.undo),
        (Mark::Done, "notes.md copied to ~/pictures", true),
        "a files step from the actions page says its receipt, with undo"
    );
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
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(matches!(app.files.page, Page::Conflict(_)), "{:?}", app.files.page);
    assert_eq!(format!("{} \u{b7} {}", app.title(), app.subtitle()), "files \u{b7} notes.md already exists");
    assert_eq!(
        labels(&app),
        ["replace", "replace all", "skip", "skip all", "keep both"],
        "one list, no second column"
    );
    assert!(app.items().iter().all(|it| matches!(it, Item::Files(l) if l.value.is_empty())));
    assert_eq!(hint(&app), "Cancel Esc");
    assert!(app.in_list && app.sel == 0);
    assert!(app.running.is_none() && tool_calls(&calls).is_empty(), "nothing runs before the answers");
    // keep both for this one: the next conflict is asked, alone
    page_row(&mut app, "keep both");
    app.enter();
    assert_eq!(app.subtitle(), "todo.txt already exists");
    assert_eq!(labels(&app), ["replace", "skip", "keep both"], "the last conflict: no `all` rows");
    page_row(&mut app, "replace");
    app.enter();
    assert!(!app.files_page_open(), "the answers given, the batch runs");
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), 3);
    assert_eq!(c[0]["arguments"]["there"], "keep", "notes.md kept both");
    assert!(c[1]["arguments"].get("there").is_none(), "report.pdf had no conflict");
    assert_eq!(c[2]["arguments"]["there"], "replace");
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("3 files copied to ~/pictures"));
}

#[test]
fn skip_all_leaves_the_files_out_and_counts_them_and_esc_lets_the_whole_go() {
    let (mut app, rx, calls) = started(vec!["notes.md", "todo.txt"], vec![]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "move");
    app.enter();
    page_row(&mut app, "skip all");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 1, "report.pdf alone");
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("1 file moved to ~/pictures, 2 skipped"));
    // Esc on the page: the whole operation goes, nothing said
    let (mut app, rx, calls) = started(vec!["notes.md"], vec![]);
    with_pictures(&mut app, &rx);
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(matches!(app.files.page, Page::Conflict(_)), "one file too is asked about");
    app.escape();
    assert!(!app.files_page_open() && app.reply.is_none() && app.files.batch.is_none());
    assert_eq!(lit(&app).as_deref(), Some("notes.md"), "the list with the row lit");
    pump(&mut app, &rx, |_| false);
    assert!(tool_calls(&calls).is_empty(), "nothing ran");
    // a single file skipped: nothing copied, and the receipt says so
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    page_row(&mut app, "skip");
    app.enter();
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("nothing copied: 1 skipped"));
    assert!(tool_calls(&calls).is_empty());
}

#[test]
fn the_folder_picked_in_one_pane_is_read_for_conflicts_too() {
    let (mut app, rx, calls) = started(vec!["notes.md"], vec![]);
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
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
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
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
        value: None,
        children: None,
    };
    let steps = vec![
        (call("photo-0412.jpg"), "photo-0412.jpg".to_string()),
        (call("todo.txt"), "todo.txt".to_string()),
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
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "rename");
    app.enter();
    assert!(app.files_page_open() && app.files.form());
    assert_eq!(app.mode, Mode::Normal, "a form of files, not Mode::Ask");
    assert_eq!((app.input.as_str(), app.cursor), ("notes.md", 8), "the name as it is, the cursor at its end");
    assert_eq!(app.placeholder(), "new name");
    assert_eq!(hint(&app), "Cancel Esc   Save Enter");
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
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "rename");
    app.enter();
    app.set_draft("other");
    app.escape();
    assert!(!app.files_page_open() && app.input.is_empty() && app.running.is_none());
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    // new folder, from the summary row's actions: an empty prompt and its own placeholder
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "new folder");
    app.enter();
    assert!(app.files.form() && app.input.is_empty());
    assert_eq!(app.placeholder(), "folder name");
    assert_eq!(app.subtitle(), "new folder");
    app.enter();
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("type a name, or Esc cancels"),
        "Enter with no name says so"
    );
    assert!(app.files.form());
    app.escape();
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "new file");
    app.enter();
    assert_eq!(app.placeholder(), "file name");
    app.set_draft("ideas.txt");
    app.enter();
    assert!(!app.files.form());
    // another provider's ask keeps Mode::Ask
    let mut app = files_app();
    app.providers[0].label = "notes".into();
    app.view = View::Folder(0, HOME.into());
    app.hint_key(HintKey::Actions);
    assert!(matches!(app.view, View::Steps(0)), "another provider: the list of steps as today");
}

#[test]
fn files_form_golden() {
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
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
    app.hint_key(HintKey::Actions);
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
    assert_eq!(
        app.reply.as_ref().map(|r| (r.text.as_str(), r.undo)),
        Some(("notes.md renamed", true)),
        "the form's step says its receipt"
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
    two_panes(&mut app);
    app.typed(' '); // notes.md checked, report.pdf lit
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
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "trash");
    app.enter();
    assert!(app.running.is_some());
    // to another view while the batch runs: the transfer goes on, the receipt lands there
    app.conversation();
    assert_eq!(app.view, View::Conversation);
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(tool_calls(&calls).len(), 2);
    assert_eq!(app.view, View::Conversation);
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("2 files trashed"));
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

#[test]
fn every_size_draws_the_panes_the_checks_and_the_pages_whole() {
    // an odd half, the minimum window, a wide and a tall screen: the frame holds, nothing panics, and the bar is the
    // active pane's half alone while two panes are drawn
    for (w, h) in [(60u16, 40u16), (61, 40), (36, 20), (59, 30), (119, 40), (150, 46), (90, 80)] {
        let mut app = files_app();
        app.size = (w, h);
        app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
        app.typed(' ');
        let drawn = draw(&app);
        let cw = w.min(120);
        if cw >= 60 {
            let left = (w - cw) / 2;
            assert_eq!(drawn.columns, (left, left + (cw - 1) / 2), "{}x{}: the bar spans the active half", w, h);
            assert!(!drawn.other_picks.is_empty(), "{}x{}: the other pane's rows", w, h);
        } else {
            assert!(drawn.other_picks.is_empty(), "{}x{}: the other pane waits", w, h);
        }
        let rows = screen(&app);
        assert!(rows[0].contains("files"), "{}x{}: the header: {:?}", w, h, rows[0]);
        // a wrapped key bar takes the row of air above it (v0.124.5): at 60 cells the files' keys take two lines
        let ky = spark_dialog::ui::keys_y(h) as usize;
        assert!(rows[ky].contains("Esc") || rows[ky - 1].contains("Esc"), "{}x{}: the key bar", w, h);
        app.hint_key(HintKey::Actions);
        let _ = screen(&app);
        page_row(&mut app, "copy");
        app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md", "report.pdf"]))));
        app.escape();
        app.files_activate(Action::UncheckAll);
        app.hint_key(HintKey::Actions);
        page_row(&mut app, "copy");
        app.enter();
        // the other pane is the destination while it is on screen; below 60 cells the folder is picked
        if cw >= 60 {
            assert!(matches!(app.files.page, Page::Conflict(_)), "{}x{}: {:?}", w, h, app.files.page);
        } else {
            assert!(app.picking.is_some(), "{}x{}: {:?}", w, h, said(&app));
        }
        let _ = screen(&app);
        app.escape();
        app.hint_key(HintKey::Actions);
        page_row(&mut app, "rename");
        app.enter();
        assert!(app.files.form());
        let _ = screen(&app);
    }
}

/// Your home lists a recent file twice, under `home` and under `recent`, with one id (the provider's is the
/// path's): a check on either is one check on one file, counted once, drawn on both rows, and acted on once.
#[test]
fn a_file_listed_under_home_and_recent_is_one_check() {
    let mut app = files_app();
    let h = "/data/me";
    let twice = |group: &str, folder: Option<&str>| {
        let mut v = file(h, "notes.md", "2 KB", "18 Oct", group, folder);
        v["id"] = json!("files:file:bm90ZXM");
        v
    };
    at(
        &mut app,
        HOME,
        json!({"title": "~", "here": h, "kinds": kinds(), "rows": [
            dir(h, "documents", "12 items", "home", DOCS),
            twice("home", None),
            file(h, "todo.txt", "1 KB", "2025", "home", None),
            twice("recent", Some("~")),
            summary("this folder \u{b7} 1 folder \u{b7} 2 files \u{b7} 3 KB", h)
        ], "short": []}),
    );
    light_row(&mut app, "notes.md");
    app.typed(' ');
    assert_eq!(app.selected_line().as_deref(), Some("1 selected \u{b7} 2 KB"), "one file, once");
    let rows = screen(&app);
    assert_eq!(
        rows.iter().filter(|r| r.contains("\u{2713} notes.md")).count(),
        2,
        "the check on both rows of the one file"
    );
    app.hint_key(HintKey::Actions);
    let Page::Actions(a) = &app.files.page else { panic!("{:?}", app.files.page) };
    assert_eq!((a.title.as_str(), a.checked.len()), ("1 selected", 1), "the checked set holds it once");
}

/// Typing on the actions page narrows it to the rows the words name, as typing searches every list: the best
/// match is lit, Enter acts on it and the list's own words come back; a heading stays only with a row under
/// it, and words that name no row say so.
#[test]
fn typing_narrows_the_actions_page_and_enter_acts_on_the_row_the_words_name() {
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    assert!(matches!(app.files.page, Page::Actions(_)));
    for c in "new".chars() {
        app.typed(c);
    }
    assert_eq!(labels(&app), vec!["new folder", "new file"], "the rows the words name");
    assert_eq!(lit(&app).as_deref(), Some("new folder"), "lit by the words");
    for c in " fi".chars() {
        app.typed(c);
    }
    assert_eq!(lit(&app).as_deref(), Some("new file"));
    app.enter();
    assert!(app.files.form(), "Enter acted on the row");
    assert!(app.input.is_empty(), "the words were the page's, not the form's");
    app.escape();
    assert!(matches!(app.files.page, Page::List) && app.input.is_empty(), "nor the folder's");
    app.hint_key(HintKey::Actions);
    for c in "zzz".chars() {
        app.typed(c);
    }
    assert_eq!(labels(&app), vec!["no action by these words"]);
    assert!(!app.in_list, "nothing lit: Enter is the prompt's, which says why");
    app.escape();
    assert!(app.input.is_empty() && matches!(app.files.page, Page::Actions(_)), "Esc clears the words first");
}

// ---- the review round

#[test]
fn a_refused_first_step_never_takes_a_standing_undo_into_the_batch() {
    // a rename's undo stands; a batch of three whose first step is refused: its undo takes back the two done, and
    // nothing else
    let (mut app, rx, calls) = started(vec![], vec!["notes.md"]);
    with_pictures(&mut app, &rx);
    light_row(&mut app, "todo.txt");
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "rename");
    app.enter();
    app.set_draft("later.txt");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && a.undo.is_some()));
    assert_eq!(app.undo.as_ref().map(|u| u.call.name.as_str()), Some("files_rename"), "a rename's undo stands");
    light_row(&mut app, "notes.md");
    for _ in 0..3 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(app.files.batch.is_some() && app.undo.is_none(), "a batch starting lets the undo before it go");
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("2 of 3 copied to ~/pictures, 1 refused: notes.md is there already")
    );
    assert_eq!(app.files.undo_more.len(), 1, "two undos: the head and one more");
    let before = tool_calls(&calls).len();
    app.undo_now();
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    let c = tool_calls(&calls);
    assert_eq!(c.len(), before + 2, "exactly the two done are taken back");
    assert!(c[before..].iter().all(|x| x["name"] == "files_trash"), "{:?}", &c[before..]);
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("2 undone"));
}

#[test]
fn a_single_step_from_the_page_says_its_receipt() {
    let (mut app, rx, _calls) = started(vec![], vec![]);
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "trash");
    app.enter();
    assert!(app.files.batch.is_none());
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && a.reply.is_some()));
    assert_eq!(
        app.reply.as_ref().map(|r| (r.text.as_str(), r.undo)),
        Some(("notes.md is in the trash", true)),
        "the words carry what a row cannot"
    );
}

#[test]
fn insert_on_the_actions_page_checks_the_row_and_goes_back() {
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    app.typed(' ');
    assert!(!app.files_page_open(), "back to the list");
    assert!(app.files.checked("files:file:home:notes.md"), "the row checked, as the check row does");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "and the bar a row down");
    // the checked set's page, a conflict, a form: nothing to check there, and the key says so
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "1 selected");
    app.typed(' ');
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("nothing to select here: Esc goes back to the list")
    );
    assert!(app.files_page_open(), "and stays");
    app.escape();
    app.files_activate(Action::UncheckAll);
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(matches!(app.files.page, Page::Conflict(_)));
    app.typed(' ');
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("nothing to select here: Esc goes back to the list")
    );
    assert!(matches!(app.files.page, Page::Conflict(_)));
    app.escape();
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "rename");
    app.enter();
    assert!(app.files.form());
    app.typed(' ');
    assert_eq!(app.input, "notes.md ", "on a form Space is a space in the name (v0.125.1)");
    assert!(app.files.form());
}

#[test]
fn the_picker_says_what_the_folder_is_for() {
    let mut app = files_app();
    for _ in 0..2 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(app.picking.is_some());
    app.sel = 1; // a folder lit, not the row that lands it here
    assert!(hint(&app).starts_with("A folder for 2 files"), "{:?}", hint(&app));
    app.escape();
    assert!(app.picking.is_none() && app.files_checks_any(), "Esc cancels the pick first; the checks wait");
    app.files_activate(Action::UncheckAll);
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "move");
    app.enter();
    app.sel = 1;
    assert!(hint(&app).starts_with("A folder for notes.md"), "{:?}", hint(&app));
}

#[test]
fn a_provider_dying_mid_batch_counts_the_step_with_its_reason_and_stops_the_rest() {
    let (mut app, rx, _calls) = started(vec![], vec![]);
    with_pictures(&mut app, &rx);
    for _ in 0..3 {
        app.typed(' ');
    }
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(app.running.is_some());
    app.incoming(spark_dialog::mcp::Incoming::Gone(0, "it exited".into()));
    assert!(app.files.batch.is_none() && app.running.is_none(), "the batch ended");
    let r = app.reply.clone().expect("the receipt");
    assert_eq!(
        (r.text.as_str(), r.undo),
        (
            "0 of 3 copied to ~/pictures, 1 refused: stopped before it answered, so it may or may not have happened, 2 not: stopped",
            false
        ),
        "the broken step with its reason, the rest not run, no undo"
    );
    assert!(app.undo.is_none());
}

#[test]
fn a_name_under_recent_or_drives_is_no_conflict() {
    // copying ~/camera/photo-0412.jpg to ~, where the home lists photo-0412.jpg under recent: the folder's own
    // rows alone are its names
    let mut app = files_app();
    let camera = "/data/me/camera";
    at(
        &mut app,
        "spark-shell://files/rows/Y2FtZXJh",
        json!({"title": "~/camera", "here": camera, "kinds": kinds(), "rows": [
            up(HOME),
            file(camera, "photo-0412.jpg", "4.8 MB", "yesterday", "", None),
            file(camera, "STICK", "1 KB", "today", "", None),
            summary("this folder \u{b7} 2 files \u{b7} 4.8 MB", camera)
        ], "short": []}),
    );
    app.files.other = Some(pane(HOME, Some(home_rows())));
    light_row(&mut app, "photo-0412.jpg");
    app.typed(' ');
    app.typed(' '); // STICK, named as the drive is
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert!(
        !matches!(app.files.page, Page::Conflict(_)),
        "no conflict with a recent file or a drive: {:?}",
        app.files.page
    );
    // with no provider to answer, the batch of two ends at once: its receipt says the copy went ahead
    assert!(app.reply.as_ref().is_some_and(|r| r.text.starts_with("0 of 2 copied to ~")), "{:?}", app.reply);
}

#[test]
fn enter_with_words_that_name_no_row_on_a_page_says_so() {
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    for c in "zzz".chars() {
        app.typed(c);
    }
    assert!(!app.in_list);
    app.enter();
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("no action by these words: Esc clears them"));
    assert!(
        app.files_page_open() && app.pending.is_none() && app.view != View::Conversation,
        "nothing asked, the page stays"
    );
    assert_eq!(app.input, "zzz", "the words stay for Esc to clear");
}

#[test]
fn a_size_stands_at_the_panes_edge_with_two_cells_of_air() {
    let mut app = files_app();
    at(&mut app, DOCS, docs_rows());
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    let rows = screen(&app);
    let photo = rows.iter().find(|r| r.contains("0412.jpg")).expect("the picture's row");
    let cells: Vec<char> = photo.chars().collect();
    assert_eq!(cells[29], '\u{2502}', "the line between the panes: {:?}", photo);
    assert!(
        photo.ends_with("photo-0412.jpg    4.8 MB  "),
        "the name whole, the size at the edge: {:?}",
        photo
    );
    let todo = rows.iter().find(|r| r.contains("todo.txt")).unwrap();
    assert!(
        todo.starts_with("    todo.txt           1 KB  \u{2502}"),
        "two cells of air at the left pane's edge: {:?}",
        todo
    );
    assert!(!photo.contains("yesterday"), "no date at 30 cells");
    // at 120 cells the date stands after the size
    app.size = (120, 40);
    let rows = screen(&app);
    let photo = rows.iter().find(|r| r.contains("0412.jpg")).unwrap();
    assert!(photo.trim_end().ends_with("4.8 MB   yesterday"), "{:?}", photo);
    let cells: Vec<char> = photo.chars().collect();
    assert_eq!(cells[59], '\u{2502}', "59 and 60 cells");
}

#[test]
fn a_click_on_the_other_pane_declined_changes_nothing() {
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    app.mode = Mode::Listening;
    app.pane_clicked(2, Instant::now());
    assert_eq!(app.view, View::Folder(0, HOME.into()), "the pane did not switch");
    assert_eq!(app.sel, 3, "and the click fell on no row of the active pane");
}

#[test]
fn copy_to_a_pane_whose_rows_have_not_come_says_a_moment() {
    let mut app = files_app();
    app.files.other = Some(pane(PICS, None));
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "copy");
    app.enter();
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("the other pane's rows have not come yet: a moment")
    );
}

#[test]
fn a_trashed_row_is_not_checkable() {
    let mut app = files_app();
    at(&mut app, TRASH, trash_rows());
    app.came_from.push(View::Folder(0, HOME.into()));
    light_row(&mut app, "old.txt");
    app.typed(' ');
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("only a file or a folder can be selected"));
    assert!(!app.files_checks_any());
    app.hint_key(HintKey::Actions);
    assert!(!labels(&app).contains(&"check".to_string()), "{:?}", labels(&app));
}

// ---- v0.125.1: Space checks (#224); the rows' air (#223). F3 previews

#[test]
fn space_checks_the_lit_row_and_f3_previews_it_and_p_is_always_the_letter() {
    let mut app = files_app();
    app.typed(' ');
    assert!(app.files.checked("files:file:home:notes.md"), "Space checks the lit file");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "and the bar moves down");
    assert!(app.input.is_empty(), "no space typed");
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 previews the lit file");
    assert_eq!(app.preview.as_ref().unwrap().row().text, "report.pdf");
    app.typed(' ');
    assert!(
        matches!(app.view, View::Folder(..)),
        "in the preview Space with nothing typed goes back, as before"
    );
    assert_eq!(hint(&app), BAR, "the key bar reads the preview binding's label");
    // a folder lit: no preview, and F3 types nothing
    light_row(&mut app, "documents");
    app.hint_key(HintKey::View);
    assert!(matches!(app.view, View::Folder(..)), "no page: F3 does nothing");
    assert!(app.input.is_empty(), "and types nothing");
    // p is the letter, on any row: a search starts and nothing opens
    light_row(&mut app, "report.pdf");
    app.text_key('p');
    assert_eq!(app.input, "p", "p starts a search");
    assert!(matches!(app.view, View::Folder(..)), "and no preview comes up");
    // words typed, then Down hands the keys to the list (#163): F3 previews, Space checks
    app.set_draft("");
    for c in "report".chars() {
        app.typed(c);
    }
    app.typed(' ');
    assert_eq!(app.input, "report ", "Space while words are typed is a space");
    app.backspace();
    app.down();
    app.typed(' ');
    assert_eq!(app.input, "report", "Space with the list's keys types no space");
    assert!(app.files.checked("files:file:home:report.pdf"), "it checks");
    light_row(&mut app, "report.pdf");
    app.list_keys = true;
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 with the list's keys previews");
    app.escape();
    // a form takes a space in the name
    app.set_draft("");
    app.files_activate(Action::UncheckAll);
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "rename");
    app.enter();
    assert!(app.files.form());
    app.typed(' ');
    assert_eq!(app.input, "notes.md ", "a space in the form's name");
    app.escape();
    // the actions page: Space is the check row's key, as its chip says
    app.hint_key(HintKey::Actions);
    let chip = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "select" => Some(l.key.clone()),
            _ => None,
        })
        .unwrap();
    assert_eq!(chip, "Space");
    app.typed(' ');
    assert!(!app.files_page_open() && app.files.checked("files:file:home:notes.md"));
    // apps: Space is no key
    app.view = View::Apps;
    app.in_list = true;
    app.sel = 0;
    app.typed(' ');
    assert!(app.input.is_empty());
}

#[test]
fn check_rebound_to_insert_checks_in_files_and_nothing_elsewhere_and_space_is_plain() {
    let mut app = files_app();
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"check":"Insert"}"#).unwrap();
    app.hint_key(HintKey::Actions);
    let chip = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "select" => Some(l.key.clone()),
            _ => None,
        })
        .unwrap();
    assert_eq!(chip, "Insert", "the chip reads the binding");
    page_row(&mut app, "rename");
    app.enter();
    assert!(app.files.form());
    app.hint_key(HintKey::Select);
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("nothing to select here: Esc goes back to the list"),
        "another check key on a form has nothing to check"
    );
    app.escape();
    app.hint_key(HintKey::Select);
    assert!(app.files.checked("files:file:home:notes.md"), "Insert checks in files");
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"));
    // Space is no longer the check: a lit row with no words typed takes no space and no check
    app.files_activate(Action::UncheckAll);
    app.typed(' ');
    assert!(
        !app.files_checks_any() && app.input.is_empty(),
        "Space checks nothing now, and types nothing on a lit row"
    );
    assert!(app.cfg.keys.help().contains(&("select", "Insert")) && app.cfg.keys.help().contains(&("view", "F3")));
    // elsewhere Insert does nothing
    app.escape();
    assert_eq!(app.view, View::Home);
    app.in_list = true;
    app.sel = 0;
    app.hint_key(HintKey::Select);
    assert!(app.view == View::Home && app.input.is_empty(), "nothing at the home");
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("nothing to select here"));
}

/// #223: a row's words end two cells before the column's edge at every width; the selection bar still spans to it.
#[test]
fn a_rows_words_end_two_cells_before_the_edge() {
    let mut app = files_app();
    let h = "/data/me";
    let mut rows = home_rows();
    rows["rows"][7] = file(
        "/data/me/screenshots-and-captures",
        "invoice-0412.pdf",
        "120 KB",
        "today",
        "recent",
        Some("screenshots-and-captures"),
    );
    rows["rows"][11] = summary(
        "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB \u{b7} and words enough to reach the edge of the column",
        h,
    );
    at(&mut app, HOME, rows);
    light_row(&mut app, "invoice-0412.pdf");
    render(&app, "files-long-place");
    for (w, hh) in [(60u16, 40u16), (36, 40)] {
        app.size = (w, hh);
        let screen = screen(&app);
        let p = palette("tokyonight-night");
        let mut b = Buffer::empty(Rect::new(0, 0, w, hh));
        let d = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
        for y in spark_dialog::ui::CONTENT_Y..spark_dialog::ui::status_y(hh) {
            let row = &screen[y as usize];
            let tail: String = row.chars().skip(w as usize - 2).collect();
            assert_eq!(tail, "  ", "{}x{} row {}: the last two cells empty: {:?}", w, hh, y, row);
        }
        let (y, _) = d.picks.iter().find(|(_, n)| *n == app.sel).copied().unwrap();
        assert_eq!(b[(w - 1, y)].bg, p.lit, "{}x{}: the bar spans to the edge", w, hh);
        let row = &screen[y as usize];
        assert!(
            row.contains("screensh\u{2026}") || w < 60,
            "{}x{}: the ellipsis before the air: {:?}",
            w,
            hh,
            row
        );
    }
}

/// The Space key is the check only while the list holds the keys (#163 for the check as it was for the preview): with
/// words typed on the list or on a page, the key bound to check types a space, so `two panes` typed on the actions
/// page narrows it and Enter opens the panes; after Down the keys are the list's and Space checks with no space typed.
#[test]
fn the_check_key_is_a_space_while_words_are_typed() {
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    for c in "new".chars() {
        app.typed(c);
    }
    app.hint_key(HintKey::Select);
    assert_eq!(app.input, "new ", "a space typed, nothing selected");
    for c in "file".chars() {
        app.typed(c);
    }
    assert_eq!(lit(&app).as_deref(), Some("new file"));
    app.enter();
    assert!(app.files.form(), "Enter opened the form");
    app.escape();
    assert!(app.files.checks.is_empty(), "the space in the words selected nothing");
    // on the list: words typed, the key is a space; Down hands the keys to the list, then it checks
    for c in "no".chars() {
        app.typed(c);
    }
    app.hint_key(HintKey::Select);
    assert_eq!(app.input, "no ");
    app.backspace();
    app.down();
    app.hint_key(HintKey::Select);
    assert_eq!(app.input, "no", "no space typed");
    assert_eq!(app.files.checks.len(), 1, "the lit row checked");
}

// ---- two panes and the keys (the owner's decisions of 2026-11-05)

/// A row of the next page, as the provider writes it.
fn next_page() -> Value {
    json!({"id": "files:more", "sign": "opens", "text": "the next page", "columns": ["1,204 more"], "children": "spark-shell://files/rows/aG9tZQ?from=200", "group": "home"})
}

fn said(app: &App) -> Option<String> {
    app.reply.as_ref().map(|r| r.text.clone())
}

/// The key bar's rows as drawn, without their air.
fn bar(app: &App) -> Vec<String> {
    let (_, h) = app.size;
    let rows = screen(app);
    let y = spark_dialog::ui::keys_y(h) as usize;
    rows[y - 1..=y].iter().map(|r| r.trim().to_string()).filter(|r| !r.is_empty()).collect()
}

#[test]
fn the_key_bar_is_two_lines_at_60_cells_and_one_at_120_in_one_pane_and_in_two() {
    let line1 = "back  Esc   nav  \u{2190} \u{2191} \u{2193} \u{2192}   ren  F2   view  F3   open  F4";
    let line2 = "copy  F5   move  F6   new  F7   trash  F8   actions  F9";
    let mut app = files_app();
    assert_eq!(bar(&app), [line1, line2], "one pane, 60 cells");
    app.size = (120, 40);
    assert_eq!(bar(&app), [format!("{}   {}", line1, line2)], "one pane, 120 cells");
    app.size = (WIDTH, HEIGHT);
    two_panes(&mut app);
    assert_eq!(bar(&app), [line1, line2], "two panes, 60 cells");
    app.size = (120, 40);
    assert_eq!(bar(&app), [format!("{}   {}", line1, line2)], "two panes, 120 cells");
    app.size = (WIDTH, HEIGHT);
    // the menu, a form, a conflict
    app.hint_key(HintKey::Actions);
    assert_eq!(bar(&app), ["back  Esc"]);
    page_row(&mut app, "rename");
    app.enter();
    assert_eq!(bar(&app), ["cancel  Esc   save  Enter"]);
    app.escape();
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Copy);
    assert!(matches!(app.files.page, Page::Conflict(_)));
    assert_eq!(bar(&app), ["cancel  Esc"]);
}

#[test]
fn right_goes_to_the_right_pane_left_to_the_left_and_the_edges_stay_put() {
    let mut app = files_app();
    // one pane: Left does nothing, Right opens the second pane and goes to it
    app.left();
    assert!(app.files.other.is_none() && matches!(app.view, View::Folder(..)), "Left is no back in files");
    assert!(app.reply.is_none());
    app.right();
    assert_eq!(app.files.other_side, Side::Left, "the bar is in the right pane");
    assert!(app.files.other.as_ref().is_some_and(|o| o.uri == HOME), "on the same folder");
    assert_eq!(app.sel, 0, "its first row lit");
    // the edge: Right stays put
    let at = (app.view.clone(), app.sel);
    app.right();
    assert_eq!((app.view.clone(), app.sel, app.files.other_side), (at.0.clone(), at.1, Side::Left));
    // Left goes to the left pane, its row lit as it was
    app.left();
    assert_eq!(app.files.other_side, Side::Right);
    assert_eq!(lit(&app).as_deref(), Some("notes.md"));
    // and at the edge Left stays put
    app.left();
    assert_eq!(app.files.other_side, Side::Right);
    assert!(app.reply.is_none());
    // Right again, Ctrl+Tab both ways
    app.right();
    assert_eq!(app.files.other_side, Side::Left);
    app.hint_key(HintKey::Pane);
    assert_eq!(app.files.other_side, Side::Right);
    // with words typed the arrows are the cursor's
    app.typed('n');
    app.typed('o');
    app.left();
    assert_eq!((app.cursor, app.files.other_side), (1, Side::Right));
    app.right();
    assert_eq!((app.cursor, app.files.other_side), (2, Side::Right));
    app.escape();
    light_row(&mut app, "notes.md");
    // close pane closes the second pane, from either side
    app.right();
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "close pane");
    app.enter();
    assert!(app.files.other.is_none() && app.files.other_side == Side::Right);
    assert_eq!(lit(&app).as_deref(), Some("notes.md"), "the first pane, as it stood");
    // a row under the groups a pane leaves out keeps the bar when the pane closes
    light_row(&mut app, "STICK");
    app.right();
    app.left();
    assert_eq!(lit(&app).as_deref(), Some("STICK"));
    app.files_activate(Action::ClosePane);
    assert_eq!(lit(&app).as_deref(), Some("STICK"), "kept by its id: the recent rows came back above it");
    // Ctrl+Tab opens the second if there is none
    app.hint_key(HintKey::Pane);
    assert!(app.files.other.is_some() && app.files.other_side == Side::Left);
    app.left();
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "close pane");
    app.enter();
    assert!(app.files.other.is_none());
    // a pick holds the arrows
    let mut app = files_app();
    app.hint_key(HintKey::Copy);
    assert!(app.picking.is_some());
    app.right();
    assert!(app.files.other.is_none(), "a pick is no place for a pane");
    // below 60 cells one pane: Right says why, Left stays put
    let mut app = files_app();
    app.size = (50, 40);
    app.left();
    assert!(app.reply.is_none());
    app.right();
    assert_eq!(said(&app).as_deref(), Some("two panes need a window 60 cells wide"));
    assert!(app.files.other.is_none());
}

#[test]
fn back_in_files_is_esc_backspace_and_the_header_and_left_stays_back_outside() {
    let mut app = files_app();
    assert!(app.can_go_back());
    app.backspace();
    assert_eq!(app.view, View::Home, "Backspace goes back");
    let mut app = files_app();
    app.escape();
    assert_eq!(app.view, View::Home, "Esc goes back");
    // outside files Left stays back, and Right opens nothing
    let mut app = files_app();
    app.view = View::Help;
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.right();
    assert_eq!(app.view, View::Help);
    app.left();
    assert_eq!(app.view, View::Home, "Left is back outside files");
}

#[test]
fn every_key_on_every_kind_of_row_acts_or_says_why() {
    const ACT: &str = "nothing to act on: light a file or a folder, or select some";
    const NO_ROW: &str = "only a file or a folder can be selected";
    let lit_at = |text: &str, uri: &str, rows: Value| {
        let mut app = files_app();
        at(&mut app, uri, rows);
        light_row(&mut app, text);
        app
    };
    let mut home = home_rows();
    home["rows"].as_array_mut().unwrap().insert(6, next_page());
    let summary = "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB";
    // a row that is no file or folder: every key says why
    let kinds: Vec<(&str, &str, Value, &str)> = vec![
        ("..", DOCS, docs_rows(), "nothing to copy here"),
        ("the next page", HOME, home.clone(), "nothing to copy here"),
        ("STICK", HOME, home.clone(), "nothing to copy here"),
        ("old.txt", TRASH, trash_rows(), "nothing to copy here"),
    ];
    for (row, uri, rows, path) in kinds {
        for (key, words) in [
            (HintKey::Rename, "nothing to rename here"),
            (HintKey::View, "nothing to view here"),
            (HintKey::Open, "this cannot be opened here"),
            (HintKey::Copy, ACT),
            (HintKey::Move, ACT),
            (HintKey::Trash, ACT),
            (HintKey::CopyPath, path),
            (HintKey::Select, NO_ROW),
        ] {
            let mut app = lit_at(row, uri, rows.clone());
            app.hint_key(key);
            assert_eq!(said(&app).as_deref(), Some(words), "{:?} on {}", key, row);
            assert!(!app.files_page_open() && app.picking.is_none(), "{:?} on {} opened nothing", key, row);
        }
    }
    // the summary row: its path is the folder's, and nothing else is for it
    for (key, words) in [
        (HintKey::Rename, "nothing to rename here"),
        (HintKey::View, "nothing to view here"),
        (HintKey::Open, "this cannot be opened here"),
        (HintKey::Copy, ACT),
        (HintKey::Trash, ACT),
        (HintKey::Select, NO_ROW),
    ] {
        let mut app = lit_at(summary, HOME, home_rows());
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some(words), "{:?} on the summary", key);
    }
    // F7 opens the form on any row of a folder; the trash has no new folder
    for row in ["..", "drafts", "todo.txt"] {
        let mut app = lit_at(row, DOCS, docs_rows());
        app.hint_key(HintKey::New);
        assert!(app.files.form(), "F7 on {}", row);
        assert_eq!((app.placeholder(), app.subtitle().as_str()), ("folder name", "new folder"));
        assert!(app.input.is_empty());
    }
    let mut app = lit_at("old.txt", TRASH, trash_rows());
    app.hint_key(HintKey::New);
    assert_eq!(said(&app).as_deref(), Some("no new folder here"));
    // F9 on every kind: the row's actions, or the folder's
    for (row, uri, rows, first) in [
        ("..", DOCS, docs_rows(), "new folder"),
        ("drafts", DOCS, docs_rows(), "open"),
        ("todo.txt", DOCS, docs_rows(), "open"),
        (summary, HOME, home_rows(), "new folder"),
        ("the next page", HOME, home.clone(), "open"),
        ("STICK", HOME, home.clone(), "open"),
        ("invoice-0412.pdf", HOME, home.clone(), "open"),
        ("old.txt", TRASH, trash_rows(), "restore"),
    ] {
        let mut app = lit_at(row, uri, rows);
        app.hint_key(HintKey::Actions);
        assert!(app.files_page_open(), "F9 on {}: {:?}", row, said(&app));
        assert_eq!(labels(&app)[0], first, "F9 on {}", row);
    }
    // a file, a folder, a recent file: the keys act
    for row in ["notes.md", "documents", "invoice-0412.pdf"] {
        let mut app = lit_at(row, HOME, home_rows());
        app.hint_key(HintKey::Rename);
        assert!(app.files.form(), "F2 on {}", row);
        assert_eq!(app.input, row, "prefilled");
        let mut app = lit_at(row, HOME, home_rows());
        app.hint_key(HintKey::Copy);
        assert!(app.picking.is_some(), "F5 in one pane picks the folder");
        let mut app = lit_at(row, HOME, home_rows());
        app.hint_key(HintKey::Move);
        assert!(app.picking.is_some(), "F6 too");
    }
    // nothing lit: the keys that want a row say how to light one, F9 opens the folder's, F7 the form
    let mut app = files_app();
    app.in_list = false;
    for key in [HintKey::Rename, HintKey::View, HintKey::Open, HintKey::CopyPath, HintKey::Select] {
        app.reply = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some("nothing is lit: an arrow or a click lights a row"), "{:?}", key);
    }
    app.reply = None;
    app.hint_key(HintKey::Copy);
    assert_eq!(said(&app).as_deref(), Some(ACT));
    app.hint_key(HintKey::Actions);
    assert_eq!(labels(&app)[0], "new folder");
}

#[test]
fn the_keys_with_words_typed_in_a_form_on_a_page_and_in_the_view() {
    // words typed: the function keys act on the row the words lit, Space is a letter
    let mut app = files_app();
    app.in_list = false;
    app.sel = 0;
    for c in "todo".chars() {
        app.typed(c);
    }
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"));
    app.hint_key(HintKey::Rename);
    assert_eq!(app.input, "todo.txt", "F2 on the row the words lit");
    app.escape();
    assert_eq!(app.input, "todo", "the words come back with the list");
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "todo.txt", "F9 too");
    app.escape();
    assert_eq!(app.input, "todo", "and from the menu");
    // a form: every key says what holds it, Space and the letters are the name's
    let mut app = files_app();
    app.hint_key(HintKey::Rename);
    for key in [
        HintKey::Rename,
        HintKey::View,
        HintKey::Open,
        HintKey::Copy,
        HintKey::Move,
        HintKey::New,
        HintKey::Trash,
        HintKey::Actions,
        HintKey::CopyPath,
        HintKey::Pane,
    ] {
        app.reply = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some("finish this first: Enter saves, Esc cancels"), "{:?}", key);
    }
    assert!(app.files.form());
    app.reply = None;
    app.up();
    app.down();
    assert!(app.files.form() && !app.in_list, "the list behind a form takes no arrow");
    assert_eq!(app.input, "notes.md");
    // on the menu each key is its row's; a key with no row says why
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    app.hint_key(HintKey::Rename);
    assert!(app.files.form(), "F2 on the menu");
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 on the menu");
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    app.hint_key(HintKey::New);
    assert!(app.files.form(), "F7 on the menu");
    assert_eq!(app.subtitle(), "new folder");
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    app.hint_key(HintKey::Copy);
    assert!(app.picking.is_some() && !app.files_page_open(), "F5 on the menu");
    let mut app = files_app();
    light_row(&mut app, "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB");
    app.hint_key(HintKey::Actions);
    app.hint_key(HintKey::Rename);
    assert_eq!(said(&app).as_deref(), Some("nothing to rename here"));
    assert!(app.files_page_open());
    app.hint_key(HintKey::Pane);
    assert_eq!(said(&app).as_deref(), Some("Esc goes back to the list first"));
    // a conflict takes its rows
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
    app.hint_key(HintKey::Copy);
    assert!(matches!(app.files.page, Page::Conflict(_)));
    for key in [HintKey::Rename, HintKey::View, HintKey::Actions, HintKey::Trash, HintKey::CopyPath] {
        app.reply = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some("choose a row, or Esc cancels"), "{:?}", key);
    }
    // a pick: the keys wait for it
    let mut app = files_app();
    app.hint_key(HintKey::Copy);
    assert!(app.picking.is_some());
    for key in [HintKey::Rename, HintKey::Open, HintKey::Actions, HintKey::New, HintKey::Select, HintKey::Pane] {
        app.reply = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some("finish this first: Enter picks, Esc cancels"), "{:?}", key);
    }
    // the view: F3 goes back, F4 is the viewed file's, the rest are the list's and say so
    let mut app = files_app();
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview);
    assert_eq!(app.title(), "view", "the word is view: the header's too");
    assert_eq!(app.subtitle(), "~");
    for (key, words) in [
        (HintKey::Rename, "nothing to rename here"),
        (HintKey::Copy, "nothing to copy here"),
        (HintKey::Move, "nothing to move here"),
        (HintKey::New, "no new folder here"),
        (HintKey::Trash, "nothing to trash here"),
        (HintKey::Actions, "no actions here"),
        (HintKey::CopyPath, "nothing to copy here"),
        (HintKey::Pane, "no other pane here"),
    ] {
        app.reply = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some(words), "{:?}", key);
    }
    app.hint_key(HintKey::View);
    assert!(matches!(app.view, View::Folder(..)), "F3 again goes back, as in every viewer");
}

#[test]
fn the_folders_own_contents_in_two_panes_and_the_short_summary() {
    let mut app = files_app();
    let shown = |app: &App| -> Vec<String> {
        app.items()
            .iter()
            .filter_map(|it| match it {
                Item::Heading(h) => Some(format!("# {}", h)),
                Item::Folder(i) => Some(app.folder.as_ref().unwrap().2.rows[*i].text.clone()),
                _ => None,
            })
            .collect()
    };
    assert!(
        shown(&app).contains(&"# home".to_string()) && shown(&app).contains(&"# recent".to_string()),
        "one pane keeps them"
    );
    light_row(&mut app, "invoice-0412.pdf");
    two_panes(&mut app);
    let rows = shown(&app);
    assert!(!rows.contains(&"# home".to_string()) && !rows.contains(&"# recent".to_string()), "{:?}", rows);
    assert!(!rows.contains(&"invoice-0412.pdf".to_string()), "a pane shows the folder's own contents");
    assert!(rows.contains(&"# drives".to_string()) && rows.contains(&"trash".to_string()), "{:?}", rows);
    let drawn = screen(&app);
    assert!(drawn.iter().any(|r| r.contains("6 items \u{b7} 4.5 MB")), "the short summary under 40 cells");
    app.size = (120, 40);
    let drawn = screen(&app);
    assert!(
        drawn.iter().any(|r| r.contains("this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB")),
        "at 60 cells it stays"
    );
    // a lit row the panes leave out: the bar stays in the list
    let mut app = files_app();
    light_row(&mut app, "report.pdf");
    two_panes(&mut app);
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"), "the lit row kept by its id");
}

#[test]
fn f4_hands_the_row_to_the_system_by_the_tools_name() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    app.hint_key(HintKey::Open);
    assert!(pump(&mut app, &rx, |_| !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!(c[0]["name"], "files_app");
    assert_eq!(c[0]["arguments"]["path"], "/data/me/notes.md");
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    light_row(&mut app, "documents");
    app.hint_key(HintKey::Open);
    assert!(pump(&mut app, &rx, |_| tool_calls(&calls).len() == 2));
    assert_eq!(
        tool_calls(&calls)[1]["arguments"]["path"],
        "/data/me/documents",
        "a folder too: the system file manager"
    );
    // outside files there is nothing to open
    app.view = View::Help;
    app.hint_key(HintKey::Open);
    assert_eq!(said(&app).as_deref(), Some("nothing to open here"));
}

#[test]
fn f4_in_the_view_hands_the_viewed_file_to_its_app_and_says_why_where_no_path_stands() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview);
    app.preview.as_mut().unwrap().playing = Some(Instant::now());
    app.hint_key(HintKey::Open);
    assert!(pump(&mut app, &rx, |_| !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!(c[0]["name"], "files_app");
    assert_eq!(c[0]["arguments"]["path"], "/data/me/notes.md");
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert_eq!(app.view, View::Preview, "the view stands behind the app");
    assert!(app.preview.as_ref().unwrap().playing.is_none(), "a sound stops, as Enter stops it");
    // the file on screen, not the one the view opened on
    app.down();
    app.hint_key(HintKey::Open);
    assert!(pump(&mut app, &rx, |_| tool_calls(&calls).len() == 2));
    assert_eq!(tool_calls(&calls)[1]["arguments"]["path"], "/data/me/report.pdf");
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    // a row that names its path and offers no such step: the path is enough
    let pv = app.preview.as_mut().unwrap();
    let at = pv.at;
    pv.files[at].more.retain(|c| c.name != "files_app");
    app.hint_key(HintKey::Open);
    assert!(pump(&mut app, &rx, |_| tool_calls(&calls).len() == 3));
    let c = &tool_calls(&calls)[2];
    assert_eq!(c["name"], "files_app");
    assert_eq!(c["arguments"]["path"], "/data/me/report.pdf");
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    // a trashed row names no path of its own, a row with no steps none at all
    let pv = app.preview.as_mut().unwrap();
    let at = pv.at;
    let keep = pv.files[at].clone();
    pv.files[at].tool.as_mut().unwrap().name = "files_restore".into();
    app.hint_key(HintKey::Open);
    assert_eq!(said(&app).as_deref(), Some("nothing to open here"));
    let pv = app.preview.as_mut().unwrap();
    pv.files[at].tool = None;
    pv.files[at].more.clear();
    app.reply = None;
    app.hint_key(HintKey::Open);
    assert_eq!(said(&app).as_deref(), Some("nothing to open here"));
    // a provider with no such tool has nothing to hand it to
    app.preview.as_mut().unwrap().files[at] = keep;
    app.providers[0].tools.retain(|t| t.name != "files_app");
    app.reply = None;
    app.hint_key(HintKey::Open);
    assert_eq!(said(&app).as_deref(), Some("nothing to open here"));
    assert_eq!(tool_calls(&calls).len(), 3, "a refusal calls nothing");
}

#[test]
fn attach_on_the_menu_runs_the_rows_own_step() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "attach to the next request");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!(c[0]["name"], "files_attach");
    assert_eq!(c[0]["arguments"]["path"], "/data/me/notes.md");
}

#[test]
fn the_system_file_manager_stands_in_the_menu_where_the_provider_offers_it() {
    // the folder's door: it opens the folder on screen, after the folder's steps, before close pane
    let (mut app, rx, calls) = started(vec![], vec![]);
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "open in the system file manager");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!(c[0]["name"], "files_browse");
    assert_eq!(c[0]["arguments"]["path"], "/data/me");
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
    app.hint_key(HintKey::Actions);
    let rows = labels(&app);
    assert_eq!(
        rows[rows.len() - 4..],
        ["new folder", "new file", "open in the system\u{2026}", "close pane"],
        "the words cut to the pane, as every row's are"
    );
    // the provider's first: the menu keeps its place for it all the same
    let mut folder = home_rows();
    let last = folder["rows"].as_array().unwrap().len() - 1;
    folder["rows"][last]["more"].as_array_mut().unwrap().reverse();
    let mut app = files_app();
    at(&mut app, HOME, folder);
    light_row(&mut app, "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB");
    app.hint_key(HintKey::Actions);
    assert_eq!(labels(&app), ["new file", "new folder", "open in the system file manager"]);
    // a file's reveal: after attach, wherever the provider wrote it, its row running the file's step
    let mut folder = home_rows();
    let step = json!({"name": "files_reveal", "said": "reveal in the system file manager"});
    folder["kinds"]["file"]["more"].as_array_mut().unwrap().push(step);
    let mut app = files_app();
    at(&mut app, HOME, folder);
    app.hint_key(HintKey::Actions);
    assert_eq!(
        labels(&app)[..6],
        [
            "open",
            "open in app",
            "view",
            "attach to the next request",
            "reveal in the system file manager",
            "rename"
        ]
    );
    // none configured: the tool stands in the provider's list, the folder's steps and the row's hold none, so no row
    let mut folder = home_rows();
    let last = folder["rows"].as_array().unwrap().len() - 1;
    folder["rows"][last]["more"].as_array_mut().unwrap().retain(|c| c["name"] != "files_browse");
    let mut app = files_app();
    at(&mut app, HOME, folder);
    assert!(app.providers[0].tools.iter().any(|t| t.name == "files_browse"));
    app.hint_key(HintKey::Actions);
    let rows = labels(&app);
    assert!(
        !rows.iter().any(|l| l.contains("system file manager")) && rows.last().map(String::as_str) == Some("new file"),
        "{:?}",
        rows
    );
}

#[test]
fn ctrl_c_copies_the_path_and_says_how_many() {
    use spark_dialog::app::{Helper, Job};
    let sent = |app: &App| -> Value {
        match app.jobs.last() {
            Some(Job::RunInput(Helper::Apps(_), _, input)) => serde_json::from_str(input).unwrap(),
            other => panic!("no copy: {:?}", other),
        }
    };
    let mut app = files_app();
    app.hint_key(HintKey::CopyPath);
    assert_eq!(sent(&app), json!({"op": "copy", "text": "/data/me/notes.md"}));
    app.helper(Helper::Apps(app.apps.serial), Ok(json!({"copied": true}).to_string()));
    assert_eq!(said(&app).as_deref(), Some("path copied"));
    // several selected: one path a line
    app.typed(' ');
    app.typed(' ');
    app.hint_key(HintKey::CopyPath);
    assert_eq!(sent(&app), json!({"op": "copy", "text": "/data/me/notes.md\n/data/me/report.pdf"}));
    app.helper(Helper::Apps(app.apps.serial), Ok(json!({"copied": true}).to_string()));
    assert_eq!(said(&app).as_deref(), Some("2 paths copied"));
    assert!(app.files_checks_any(), "the selection stands: nothing moved");
    // a refusal says the adapter's words and leaves no receipt waiting
    app.hint_key(HintKey::CopyPath);
    app.helper(
        Helper::Apps(app.apps.serial),
        Ok(json!({"error": "Copy needs wl-copy in a Wayland session"}).to_string()),
    );
    assert_eq!(said(&app).as_deref(), Some("Copy needs wl-copy in a Wayland session"));
    assert!(app.apps.copy_said.is_none());
    // the menu's row, and elsewhere there is nothing to copy
    let mut app = files_app();
    app.hint_key(HintKey::Actions);
    app.hint_key(HintKey::CopyPath);
    assert_eq!(sent(&app)["text"], "/data/me/notes.md");
    assert!(!app.files_page_open());
    let mut app = files_app();
    app.view = View::Home;
    app.hint_key(HintKey::CopyPath);
    assert_eq!(said(&app).as_deref(), Some("nothing to copy here"));
    assert!(app.jobs.is_empty());
}

#[test]
fn f5_and_f6_act_at_once_with_undo_and_one_file_says_the_providers_words() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    with_pictures(&mut app, &rx);
    app.hint_key(HintKey::Copy);
    assert!(app.mode == Mode::Normal, "no confirmation: the prompt never confirms anything");
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && a.undo.is_some()));
    assert_eq!(said(&app).as_deref(), Some("notes.md copied to ~/pictures"));
    assert!(app.reply.as_ref().is_some_and(|r| r.undo));
    assert_eq!(tool_calls(&calls)[0]["arguments"]["to"], "/data/me/pictures");
    light_row(&mut app, "notes.md");
    app.typed(' ');
    app.typed(' ');
    app.hint_key(HintKey::Move);
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(said(&app).as_deref(), Some("2 files moved to ~/pictures"), "no size");
    app.undo_now();
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none() && a.running.is_none()));
    assert_eq!(said(&app).as_deref(), Some("2 undone"));
    // F8: the lit row, or the selected set
    light_row(&mut app, "report.pdf");
    app.hint_key(HintKey::Trash);
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && a.undo.is_some()));
    assert_eq!(said(&app).as_deref(), Some("report.pdf is in the trash"));
    // a step under way: no second one on top of it
    app.hint_key(HintKey::Copy);
    assert!(app.running.is_some());
    light_row(&mut app, "todo.txt");
    app.hint_key(HintKey::Copy);
    assert_eq!(said(&app).as_deref(), Some("wait for the current action's result"));
}

#[test]
fn keys_outside_files_say_there_is_nothing_for_them() {
    let mut app = files_app();
    for view in [View::Home, View::Help, View::Conversation, View::About, View::Models] {
        app.view = view.clone();
        app.folder = None;
        app.in_list = false;
        for (key, words) in [
            (HintKey::Rename, "nothing to rename here"),
            (HintKey::View, "nothing to view here"),
            (HintKey::Open, "nothing to open here"),
            (HintKey::Copy, "nothing to copy here"),
            (HintKey::Move, "nothing to move here"),
            (HintKey::New, "no new folder here"),
            (HintKey::Trash, "nothing to trash here"),
            (HintKey::Actions, "no actions here"),
            (HintKey::CopyPath, "nothing to copy here"),
            (HintKey::Pane, "no other pane here"),
        ] {
            app.reply = None;
            app.hint_key(key);
            assert_eq!(said(&app).as_deref(), Some(words), "{:?} in {:?}", key, view);
        }
    }
    // a question takes its rows, an answer being typed its prompt
    let step = Step {
        prov: 0,
        call: model::call(&json!({"name": "files_trash", "arguments": {"path": "/data/me/x"}})).unwrap(),
        who: Who::Person,
        line: "trash x".into(),
        typed: false,
    };
    app.view = View::Home;
    app.mode = Mode::Confirm(step.clone());
    app.hint_key(HintKey::Rename);
    assert_eq!(said(&app).as_deref(), Some("the question takes Enter on a row"));
    app.hint_key(HintKey::Conversation);
    assert_eq!(app.view, View::Home);
    app.mode = Mode::Ask {
        step,
        field: "name".into(),
        masked: false,
    };
    app.hint_key(HintKey::Actions);
    assert_eq!(said(&app).as_deref(), Some("finish this first: Enter or Esc"));
    app.hint_key(HintKey::Select);
    assert_eq!(app.input, " ", "Space is the answer's");
}

#[test]
fn an_unbound_action_draws_no_key_and_the_others_stand() {
    // `{"conversation": "F2"}`: rename lost its default key
    let mut app = files_app();
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"conversation": "F2"}"#).unwrap();
    let line = bar(&app).join("   ");
    assert!(!line.contains("ren"), "no key, no chip, no word: {:?}", line);
    assert!(
        line.contains("view  F3") && line.contains("actions  F9"),
        "the rest of the bar stands: {:?}",
        line
    );
    assert!(draw(&app).keys.iter().all(|k| k.3 != HintKey::Rename), "and nothing there to click");
    // the menu's row stands, with no key at its right; it still acts on Enter
    app.hint_key(HintKey::Actions);
    let row = app
        .items()
        .iter()
        .find_map(|it| match it {
            Item::Files(l) if l.label == "rename" => Some(l.key.clone()),
            _ => None,
        })
        .expect("the rename row stands");
    assert_eq!(row, "", "no key beside it");
    let drawn = screen(&app);
    let y = drawn.iter().find(|r| r.starts_with("    rename")).unwrap();
    assert_eq!(y.trim_end(), "    rename");
    page_row(&mut app, "rename");
    app.enter();
    assert!(app.files.form());
    app.escape();
    // help: the row stands, with no key
    app.view = View::Help;
    app.folder = None;
    let row = app.help_rows().into_iter().find(|(_, w, _)| w == "rename a row").unwrap();
    assert_eq!(row.2, "");
    assert!(screen(&app).iter().any(|r| r.trim_end() == "    rename a row"), "no chip on its row");
    // `{"check": "Insert"}`: the old name is select's
    let mut app = files_app();
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"check": "Insert"}"#).unwrap();
    app.hint_key(HintKey::Select);
    assert!(app.files.checked("files:file:home:notes.md"));
}

#[test]
fn f2_renames_a_note_a_layout_and_a_category_from_the_name_as_it_is() {
    let tools = model::tools(&json!({"tools": [
        {"name": "notes_open", "title": "notes open NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}},
        {"name": "notes_rename", "title": "notes rename NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}, "to": {"type": "string"}}}}
    ]}));
    let mut notes = Provider::new("notes");
    notes.tools = tools;
    notes.ready = true;
    notes.rows = model::rows(
        &json!({"title": "notes", "rows": [
            {"id": "notes:1", "sign": "blank", "text": "Shopping", "tool": {"name": "notes_open", "arguments": {"name": "shopping.md"}},
             "more": [{"name": "notes_rename", "arguments": {"name": "shopping.md"}, "ask": ["to"], "said": "rename"}]},
            {"id": "notes:new", "sign": "opens", "text": "new note", "tool": {"name": "notes_new", "arguments": {}}}
        ], "short": []})
        .to_string(),
    )
    .unwrap();
    let cfg = Config {
        model: false,
        talk: false,
        ..Config::default()
    };
    let mut app = App::new(cfg, &[]);
    app.providers = vec![notes];
    app.view = View::Section(0);
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = 0;
    let hint_row: String = app.hint().iter().map(|(t, _)| t.as_str()).collect();
    assert!(hint_row.contains("Actions F9"), "{}", hint_row);
    app.hint_key(HintKey::Rename);
    assert!(matches!(app.mode, Mode::Ask { .. }), "{:?}", app.mode);
    assert_eq!((app.input.as_str(), app.cursor), ("Shopping", 8), "prefilled, the cursor at its end");
    assert_eq!(hint(&app), "Cancel Esc   Save Enter");
    app.set_draft("");
    assert_eq!(app.placeholder(), "new name");
    app.escape();
    assert_eq!(app.mode, Mode::Normal);
    // from the row's page too, and a row with no rename step says so
    app.hint_key(HintKey::Actions);
    assert!(matches!(app.view, View::Steps(0)));
    app.hint_key(HintKey::Rename);
    assert!(matches!(app.mode, Mode::Ask { .. }));
    assert_eq!(app.input, "Shopping", "from the row's page too");
    app.escape();
    app.sel = 1;
    app.in_list = true;
    app.hint_key(HintKey::Rename);
    assert_eq!(said(&app).as_deref(), Some("nothing to rename here"));
    app.hint_key(HintKey::Actions);
    assert_eq!(said(&app).as_deref(), Some("no actions here"));
    // Right opens nothing outside files
    app.sel = 0;
    app.reply = None;
    app.right();
    assert_eq!(app.view, View::Section(0));
    // apps' categories
    let mut app = App::new(Config::default(), &[]);
    app.view = View::Apps;
    app.came_from.push(View::Home);
    app.apps.prefs = spark_dialog::apps::preferences::Preferences::default();
    app.apps.preference_error = None;
    app.hint_key(HintKey::Rename);
    assert_eq!(said(&app).as_deref(), Some("nothing to rename here"), "an app has no rename");
    app.hint_key(HintKey::Actions);
    assert_eq!(said(&app).as_deref(), Some("no details here"));
    app.apps_activate(spark_dialog::apps::Action::Categories);
    let n = app
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Apps(l) if l.action == Some(spark_dialog::apps::Action::Category("Web".into()))))
        .unwrap();
    app.light(n);
    app.hint_key(HintKey::Rename);
    assert!(app.apps.form());
    assert_eq!(app.input, "Web", "the name as it is");
    app.escape();
    app.apps_activate(spark_dialog::apps::Action::Category("Other".into()));
    app.hint_key(HintKey::Rename);
    assert_eq!(said(&app).as_deref(), Some("nothing to rename here"), "other stays other");
}

// ---- what the review found: every key on the row a person sees, and only there

const GONE: &str = "this file is gone: read the list again";

/// The provider says its rows changed and they land, these names gone from your home.
fn lands_without(app: &mut App, rx: &Rx, gone: &Gone, names: &[&str]) {
    gone.lock().unwrap().extend(names.iter().map(|n| n.to_string()));
    app.providers[0].dirty = true;
    let left = |rows: &model::Rows| rows.here.as_deref() == Some("/data/me") && !rows.rows.iter().any(|r| names.contains(&r.text.as_str()));
    let landed = |a: &App| a.folder.as_ref().is_some_and(|(_, _, r)| left(r)) || a.files.other.as_ref().and_then(|o| o.rows.as_ref()).is_some_and(left);
    assert!(pump(app, rx, landed), "the rows landed without {:?}", names);
}

#[test]
fn a_menu_acts_on_its_own_row_when_the_rows_land_under_it() {
    // F8 took notes.md, Down lit report.pdf, F9 opened its menu, and only then the read landed, a row shorter: the
    // index behind the page now names todo.txt
    let stale = || {
        let (mut app, rx, calls, gone) = started_gone(vec![], vec![]);
        light_row(&mut app, "report.pdf");
        app.hint_key(HintKey::Actions);
        lands_without(&mut app, &rx, &gone, &["notes.md"]);
        assert_eq!(app.subtitle(), "report.pdf");
        (app, rx, calls)
    };
    let (mut app, rx, calls) = stale();
    page_row(&mut app, "trash");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !tool_calls(&calls).is_empty()));
    let c = tool_calls(&calls);
    assert_eq!(c[0]["name"], "files_trash");
    assert_eq!(c[0]["arguments"]["path"], "/data/me/report.pdf", "never the row that came up into its place");
    for word in ["copy", "move"] {
        let (mut app, ..) = stale();
        page_row(&mut app, word);
        app.enter();
        let step = app.picking.as_ref().and_then(|pk| pk.step.clone()).expect("the pick");
        assert_eq!(step.call.arguments["path"], "/data/me/report.pdf", "{}", word);
    }
    let (mut app, ..) = stale();
    page_row(&mut app, "view");
    app.enter();
    assert_eq!(app.preview.as_ref().unwrap().row().text, "report.pdf");
    let (mut app, ..) = stale();
    app.apps.pending = None; // the catalog home asked for at the start
    page_row(&mut app, "copy path");
    app.enter();
    let copied = app.jobs.iter().rev().find_map(|j| match j {
        spark_dialog::app::Job::RunInput(spark_dialog::app::Helper::Apps(_), _, input) => Some(input.clone()),
        _ => None,
    });
    assert!(copied.is_some_and(|i| i.contains("/data/me/report.pdf")));
    // back from the page, the bar is on its row: the place behind a page keeps by id as the list does
    let (mut app, ..) = stale();
    app.escape();
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"));
    // and behind a form
    let (mut app, rx, _, gone) = started_gone(vec![], vec![]);
    light_row(&mut app, "report.pdf");
    app.hint_key(HintKey::Rename);
    lands_without(&mut app, &rx, &gone, &["notes.md"]);
    app.escape();
    assert_eq!(lit(&app).as_deref(), Some("report.pdf"));
}

#[test]
fn a_menu_whose_row_left_says_so_and_touches_nothing() {
    for word in [
        "open",
        "open in app",
        "view",
        "attach to the next request",
        "rename",
        "copy",
        "move",
        "copy path",
        "trash",
        "select",
    ] {
        let (mut app, rx, calls, gone) = started_gone(vec![], vec![]);
        light_row(&mut app, "report.pdf");
        app.hint_key(HintKey::Actions);
        lands_without(&mut app, &rx, &gone, &["report.pdf"]);
        app.apps.pending = None; // the catalog home asked for at the start
        app.jobs.clear();
        page_row(&mut app, word);
        app.enter();
        assert_eq!(said(&app).as_deref(), Some(GONE), "{}", word);
        assert!(tool_calls(&calls).is_empty() && app.running.is_none(), "{}: nothing ran", word);
        assert!(
            !app.files_page_open() && app.picking.is_none() && app.preview.is_none() && !app.files.form() && !app.files_checks_any() && app.jobs.is_empty(),
            "{}: nothing opened",
            word
        );
    }
    // the folder's own rows are no row's: they stand
    let (mut app, rx, _, gone) = started_gone(vec![], vec![]);
    light_row(&mut app, "report.pdf");
    app.hint_key(HintKey::Actions);
    lands_without(&mut app, &rx, &gone, &["report.pdf"]);
    page_row(&mut app, "new folder");
    app.enter();
    assert!(app.files.form(), "{:?}", said(&app));
    // the set's menu: one of it gone and the set is not what the page showed
    let (mut app, rx, calls, gone) = started_gone(vec![], vec![]);
    app.typed(' ');
    app.typed(' ');
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "2 selected");
    lands_without(&mut app, &rx, &gone, &["report.pdf"]);
    page_row(&mut app, "trash");
    app.enter();
    assert_eq!(said(&app).as_deref(), Some(GONE));
    assert!(tool_calls(&calls).is_empty() && app.files.batch.is_none());
    // the set whole, the rows moved under it: it acts on the set, as selected
    let (mut app, rx, calls, gone) = started_gone(vec![], vec![]);
    light_row(&mut app, "report.pdf");
    app.typed(' ');
    app.typed(' ');
    app.hint_key(HintKey::Actions);
    lands_without(&mut app, &rx, &gone, &["notes.md"]);
    page_row(&mut app, "trash");
    app.enter();
    assert!(pump(&mut app, &rx, |_| tool_calls(&calls).len() == 2));
    let paths: Vec<Value> = tool_calls(&calls).iter().map(|c| c["arguments"]["path"].clone()).collect();
    assert_eq!(paths, ["/data/me/report.pdf", "/data/me/todo.txt"]);
}

#[test]
fn below_sixty_cells_f5_and_f6_pick_the_folder_for_the_other_pane_is_not_on_screen() {
    for key in [HintKey::Copy, HintKey::Move] {
        let mut app = files_app();
        app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
        app.size = (50, HEIGHT);
        assert!(!app.panes_drawn());
        app.hint_key(key);
        assert!(app.picking.as_ref().is_some_and(|pk| pk.step.is_some()), "{:?}: {:?}", key, said(&app));
        assert!(!matches!(app.files.page, Page::Conflict(_)), "nothing asks about a folder nobody can see");
    }
    // the pane back on screen, the pane is the destination again
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
    app.size = (WIDTH, HEIGHT);
    app.hint_key(HintKey::Copy);
    assert!(app.picking.is_none() && matches!(app.files.page, Page::Conflict(_)));
}

#[test]
fn opening_the_second_pane_lets_go_of_the_recent_rows_it_stops_drawing() {
    let mut app = files_app();
    light_row(&mut app, "photo-0412.jpg");
    app.typed(' ');
    light_row(&mut app, "todo.txt");
    app.typed(' ');
    assert_eq!(app.files.checks.len(), 2);
    light_row(&mut app, "todo.txt");
    two_panes(&mut app);
    assert!(app.panes_drawn());
    assert_eq!(app.files.checks, ["files:file:home:todo.txt"], "what is off screen is off the selection");
    assert_eq!(app.selected_line().as_deref(), Some("1 selected \u{b7} 1 KB"));
    // the window grew back over a selection made below 60 cells: the set is what the list draws
    let mut app = files_app();
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    app.size = (50, HEIGHT);
    light_row(&mut app, "photo-0412.jpg");
    app.typed(' ');
    app.size = (WIDTH, HEIGHT);
    assert!(app.panes_drawn());
    assert_eq!(app.selected_line(), None);
}

#[test]
fn words_that_hide_selected_rows_stop_the_keys_with_the_count() {
    let selected = || {
        let mut app = files_app();
        light_row(&mut app, "report.pdf");
        app.typed(' ');
        light_row(&mut app, "todo.txt");
        app.typed(' ');
        app
    };
    let mut app = selected();
    for c in "note".chars() {
        app.typed(c);
    }
    for key in [HintKey::Copy, HintKey::Move, HintKey::Trash, HintKey::CopyPath] {
        app.reply = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some("2 selected rows are hidden: Esc clears the words"), "{:?}", key);
        assert!(app.picking.is_none() && app.files.batch.is_none() && app.jobs.is_empty(), "{:?}", key);
    }
    // from the menu too
    app.reply = None;
    app.hint_key(HintKey::Actions);
    page_row(&mut app, "trash");
    app.enter();
    assert_eq!(said(&app).as_deref(), Some("2 selected rows are hidden: Esc clears the words"));
    // one of them shows: the count is the hidden ones
    let mut app = selected();
    for c in "todo".chars() {
        app.typed(c);
    }
    app.hint_key(HintKey::Trash);
    assert_eq!(said(&app).as_deref(), Some("1 selected row is hidden: Esc clears the words"));
    // Esc clears the words, the selection stands, and the keys act on what is on screen
    app.escape();
    assert_eq!(app.input, "");
    assert!(app.files_checks_any(), "the words go first");
    app.reply = None;
    app.hint_key(HintKey::CopyPath);
    assert_eq!(said(&app), None);
    assert!(!app.jobs.is_empty(), "both rows on screen: the keys act");
}

#[test]
fn a_row_key_set_on_a_letter_or_delete_is_the_prompts_until_the_list_holds_the_keys() {
    let keys = |text: &str| spark_dialog::keys::Bindings::from_json(text).unwrap();
    let all = [
        ("rename", HintKey::Rename),
        ("open", HintKey::Open),
        ("copy", HintKey::Copy),
        ("move", HintKey::Move),
        ("new", HintKey::New),
        ("trash", HintKey::Trash),
        ("copy-path", HintKey::CopyPath),
        ("actions", HintKey::Actions),
        ("select", HintKey::Select),
        ("view", HintKey::View),
    ];
    for (name, key) in all {
        // words typed: the letter is one more of them, and nothing else happens
        let mut app = files_app();
        app.cfg.keys = keys(&format!(r#"{{"{}": "o"}}"#, name));
        app.typed('n');
        app.hint_key(key);
        assert_eq!(app.input, "no", "{}", name);
        assert!(
            said(&app).is_none() && !app.files_page_open() && app.picking.is_none() && app.files.batch.is_none() && app.view != View::Preview,
            "{}: {:?}",
            name,
            said(&app)
        );
        assert!(!app.files_checks_any() && app.jobs.is_empty(), "{}", name);
        // Down hands the keys to the list: the key is the key
        app.down();
        app.hint_key(key);
        assert_ne!(app.input, "noo", "{} acts once the list holds the keys", name);
        // Delete, the same way: it deletes the letter under the cursor
        let mut app = files_app();
        app.cfg.keys = keys(&format!(r#"{{"{}": "Delete"}}"#, name));
        app.set_draft("no");
        app.cursor = 0;
        app.hint_key(key);
        assert_eq!(app.input, "o", "{} on Delete", name);
        assert!(said(&app).is_none() && app.jobs.is_empty(), "{}", name);
        // a form's name takes it
        let mut app = files_app();
        app.cfg.keys = keys(&format!(r#"{{"{}": "o"}}"#, name));
        app.hint_key(HintKey::New);
        assert!(app.files.form() && app.input.is_empty(), "{}", name);
        app.hint_key(key);
        assert_eq!(app.input, "o", "{}: a name", name);
        // an answer being typed takes it
        let mut app = notes_app(&format!(r#"{{"{}": "o"}}"#, name));
        app.hint_key(HintKey::Rename);
        assert!(matches!(app.mode, Mode::Ask { .. }));
        app.set_draft("n");
        app.hint_key(key);
        assert_eq!(app.input, "no", "{}: an answer", name);
    }
    // the home with nothing lit: a letter starts the words, whatever it is bound to
    for (name, key) in all {
        let mut app = App::new(Config::default(), &[]);
        app.cfg.keys = keys(&format!(r#"{{"{}": "o"}}"#, name));
        app.hint_key(key);
        assert_eq!(app.input, "o", "{} at home", name);
        assert_eq!(app.view, View::Home);
    }
    // a key of the files' alone is a letter anywhere else, lit row or none
    let mut app = notes_app(r#"{"copy": "o"}"#);
    app.hint_key(HintKey::Copy);
    assert_eq!(app.input, "o");
    assert_eq!(said(&app), None);
    // a shifted letter is that letter, a key with Ctrl no letter at all
    let mut app = files_app();
    app.cfg.keys = keys(r#"{"trash": "Shift+o"}"#);
    app.typed('n');
    app.hint_key(HintKey::Trash);
    assert_eq!(app.input, "nO");
    let mut app = files_app();
    app.cfg.keys = keys(r#"{"copy-path": "Ctrl+o"}"#);
    app.typed('n');
    app.hint_key(HintKey::CopyPath);
    assert_eq!(app.input, "n");
    assert!(!app.jobs.is_empty(), "Ctrl types nothing: it acts as a function key does");
}

/// A note in Notes, lit, its row as the provider writes it: the file in the arguments, the title in the text.
fn notes_app(keys: &str) -> App {
    let mut notes = Provider::new("notes");
    notes.tools = model::tools(&json!({"tools": [
        {"name": "notes_open", "title": "notes open NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}},
        {"name": "notes_rename", "title": "notes rename NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}, "to": {"type": "string"}}}}
    ]}));
    notes.ready = true;
    notes.rows = model::rows(
        &json!({"title": "notes", "rows": [
            {"id": "notes:shopping.md", "sign": "blank", "text": "Shopping", "tool": {"name": "notes_open", "arguments": {"name": "shopping.md"}},
             "more": [{"name": "notes_rename", "arguments": {"name": "shopping.md"}, "ask": ["to"], "said": "rename"}]}
        ], "short": []})
        .to_string(),
    )
    .unwrap();
    let mut app = App::new(
        Config {
            model: false,
            talk: false,
            ..Config::default()
        },
        &[],
    );
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(keys).unwrap();
    app.providers = vec![notes];
    app.view = View::Section(0);
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = 0;
    app
}

#[test]
fn a_rename_left_empty_keeps_its_form_and_says_how_it_ends() {
    let mut app = notes_app("{}");
    app.hint_key(HintKey::Rename);
    app.set_draft("");
    app.enter();
    assert_eq!(said(&app).as_deref(), Some("type a name, or Esc cancels"));
    assert!(matches!(app.mode, Mode::Ask { .. }), "the form stands: {:?}", app.mode);
    app.escape();
    assert_eq!(app.mode, Mode::Normal);
}

#[test]
fn the_passive_panes_bar_keeps_its_row_by_id() {
    let aside = || {
        let (mut app, rx, _, gone) = started_gone(vec![], vec![]);
        light_row(&mut app, "todo.txt");
        app.right();
        light_row(&mut app, "documents");
        app.enter();
        assert!(pump(&mut app, &rx, |a| a.folder.as_ref().is_some_and(|(_, u, _)| u == DOCS)));
        (app, rx, gone)
    };
    let (mut app, rx, gone) = aside();
    lands_without(&mut app, &rx, &gone, &["notes.md"]);
    assert!(app.files_pane());
    assert_eq!(lit(&app).as_deref(), Some("todo.txt"), "the row, not its place");
    // the lit row itself left: the bar stands on a row that is there
    let (mut app, rx, gone) = aside();
    lands_without(
        &mut app,
        &rx,
        &gone,
        &["todo.txt", "trash", "STICK", "this folder \u{b7} 3 folders \u{b7} 3 files \u{b7} 4.5 MB"],
    );
    assert!(app.files_pane());
    assert!(app.sel < app.picks().len(), "{} of {}", app.sel, app.picks().len());
}

#[test]
fn only_esc_and_the_x_stop_a_batch_every_other_way_back_leaves_it_running() {
    let running = || {
        let (mut app, rx, calls) = started(vec![], vec![]);
        app.typed(' ');
        app.typed(' ');
        app.typed(' ');
        app.hint_key(HintKey::Trash);
        assert!(app.files.batch.is_some());
        (app, rx, calls)
    };
    let untouched = |app: &App, how: &str| {
        assert!(
            app.files.batch.as_ref().is_some_and(|b| !b.stopping && b.stopped == 0),
            "{}: {:?}",
            how,
            app.files.batch
        );
    };
    // F3 in the view, Space in the view
    let (mut app, ..) = running();
    light_row(&mut app, "todo.txt");
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview);
    app.hint_key(HintKey::View);
    assert!(matches!(app.view, View::Folder(..)), "{:?}", app.view);
    untouched(&app, "F3");
    light_row(&mut app, "todo.txt");
    app.hint_key(HintKey::View);
    app.typed(' ');
    assert!(matches!(app.view, View::Folder(..)), "{:?}", app.view);
    untouched(&app, "Space");
    // Backspace on an empty prompt, Left outside files
    let (mut app, ..) = running();
    app.backspace();
    assert_eq!(app.view, View::Home);
    untouched(&app, "Backspace");
    let (mut app, ..) = running();
    app.came_from.push(app.view.clone());
    app.view = View::Help;
    app.left();
    assert!(matches!(app.view, View::Folder(..)), "{:?}", app.view);
    untouched(&app, "Left");
    // the header's back
    let (mut app, ..) = running();
    app.back_key();
    assert_eq!(app.view, View::Home);
    untouched(&app, "the header's back");
    // Esc still stops it
    let (mut app, ..) = running();
    app.escape();
    assert!(app.files.batch.as_ref().is_some_and(|b| b.stopping));
}

#[test]
fn f2_starts_from_the_rows_words_never_its_file() {
    let mut app = notes_app("{}");
    app.hint_key(HintKey::Rename);
    assert_eq!(app.input, "Shopping", "the title, its first line");
    app.escape();
    // a layout's name is its row's words, as the provider writes it; a save-as from a recent one too
    let mut layouts = Provider::new("layout");
    layouts.tools = model::tools(&json!({"tools": [
        {"name": "layout_open", "title": "layout open NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}},
        {"name": "layout_rename", "title": "layout rename NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}, "to": {"type": "string"}}}}
    ]}));
    layouts.ready = true;
    layouts.rows = model::rows(
        &json!({"title": "layouts", "rows": [
            {"id": "layout:coding", "sign": "blank", "text": "coding", "tool": {"name": "layout_open", "arguments": {"name": "coding"}},
             "more": [{"name": "layout_rename", "arguments": {"name": "coding"}, "ask": ["to"], "said": "rename"}]}
        ], "short": []})
        .to_string(),
    )
    .unwrap();
    app.providers = vec![layouts];
    app.in_list = true;
    app.sel = 0;
    app.hint_key(HintKey::Rename);
    assert_eq!(app.input, "coding");
}

#[test]
fn a_batch_lets_go_of_the_sources_selection_when_it_starts_and_of_no_other() {
    let (mut app, rx, calls) = started(vec![], vec![]);
    light_row(&mut app, "report.pdf");
    app.right();
    light_row(&mut app, "report.pdf");
    app.typed(' ');
    app.left();
    app.typed(' ');
    app.typed(' ');
    assert_eq!(app.files.checks.len(), 2);
    app.hint_key(HintKey::Trash);
    assert!(app.files.batch.is_some());
    assert!(app.files.checks.is_empty(), "gone as the batch starts, as one file's is");
    // the other pane active while it runs, its own selection standing through the batch's end
    assert!(app.files_pane());
    assert!(app.files_checks_any());
    assert!(pump(&mut app, &rx, |a| a.files.batch.is_none()));
    assert_eq!(tool_calls(&calls).len(), 2);
    assert!(app.files_checks_any(), "the batch's end is no pane's business");
    assert_eq!(app.files.checks, ["files:file:home:report.pdf"]);
}

#[test]
fn the_keys_say_the_rows_have_not_come_while_the_folder_loads() {
    for key in [HintKey::Copy, HintKey::Move, HintKey::Trash, HintKey::Actions] {
        let mut app = files_app();
        app.folder = None;
        app.hint_key(key);
        assert_eq!(said(&app).as_deref(), Some("the rows have not come yet: a moment"), "{:?}", key);
    }
}

#[test]
fn f10_and_back_keeps_the_selection() {
    let (mut app, rx, _) = started(vec![], vec![]);
    app.typed(' ');
    assert!(app.files_checks_any());
    app.hint_key(HintKey::Conversation);
    assert_eq!(app.view, View::Conversation);
    app.hint_key(HintKey::Conversation);
    assert!(pump(&mut app, &rx, |a| a.folder.is_some()));
    assert!(app.files_checks_any(), "the conversation is no other folder");
}

#[test]
fn both_panes_take_one_date_decision_by_the_columns_width() {
    let mut app = files_app();
    at(&mut app, DOCS, docs_rows());
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    light_row(&mut app, "notes.md");
    let dated = |app: &App, name: &str, date: &str| screen(app).iter().any(|r| r.contains('\u{2502}') && r.contains(name) && r.contains(date));
    let (l, r) = spark_dialog::ui::pane_widths(80);
    assert_ne!(l, r, "80 cells split in two widths");
    app.size = (80, 40);
    assert!(dated(&app, "notes.md", "18 Oct"), "the left pane has its dates at 80");
    assert!(dated(&app, "holiday.jpg", "today"), "and the right");
    app.size = (79, 40);
    assert!(!dated(&app, "notes.md", "18 Oct") && !dated(&app, "holiday.jpg", "today"), "at 79 neither has");
}

#[test]
fn the_two_panes_frames_as_the_mock_has_them() {
    let docs = |app: &mut App| {
        at(app, DOCS, docs_rows());
        app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
        light_row(app, "notes.md");
    };
    let mut app = files_app();
    docs(&mut app);
    render(&app, "files-two-panes");
    app.size = (120, 40);
    render_at(&app, "full-files-two-panes", 120, 40);
    app.size = (WIDTH, HEIGHT);
    app.hint_key(HintKey::Rename);
    render(&app, "files-two-panes-rename");
    app.escape();
    app.hint_key(HintKey::New);
    render(&app, "files-two-panes-new");
    app.escape();
    app.hint_key(HintKey::Actions);
    render(&app, "files-two-panes-menu");
    app.escape();
    app.typed(' ');
    light_row(&mut app, "todo.txt");
    app.typed(' ');
    light_row(&mut app, "todo.txt");
    render(&app, "files-two-panes-selected");
    // the conflict, inside the active pane, the other pane staying
    let mut app = files_app();
    docs(&mut app);
    app.files.other = Some(pane(PICS, Some(pics_rows(&["notes.md"]))));
    app.hint_key(HintKey::Copy);
    render(&app, "files-two-panes-conflict");
    // your home, the folder alone
    let mut app = files_app();
    light_row(&mut app, "downloads");
    two_panes(&mut app);
    render(&app, "files-two-panes-home");
}

#[test]
fn the_menu_and_the_conflict_draw_in_the_pane_that_is_active() {
    let mut app = files_app();
    at(&mut app, DOCS, docs_rows());
    app.files.other = Some(pane(PICS, Some(pics_rows(&[]))));
    light_row(&mut app, "notes.md");
    app.right(); // the pictures, in the right pane
    light_row(&mut app, "holiday.jpg");
    app.hint_key(HintKey::Actions);
    let rows = screen(&app);
    let open = rows.iter().find(|r| r.contains("open in app")).expect("the menu");
    assert!(open.starts_with("    todo.txt") || open.contains("\u{2502}    open in app"), "{:?}", open);
    let cells: Vec<char> = open.chars().collect();
    assert_eq!(cells[29], '\u{2502}', "{:?}", open);
    assert!(open.ends_with("F4   "), "its key at the pane's right, three cells in: {:?}", open);
    assert!(rows.iter().any(|r| r.starts_with("    todo.txt")), "the other pane stays");
    let drawn = draw(&app);
    assert_eq!(drawn.columns, (30, 60), "the bar in the right pane");
    // a click on a row of the menu acts at once
    let n = app.picks().iter().position(|it| matches!(it, Item::Files(l) if l.label == "select")).unwrap();
    app.clicked(n, Instant::now());
    assert!(!app.files_page_open() && app.files.checks.len() == 1);
}

#[test]
fn enter_with_nothing_lit_and_nothing_typed_says_how_to_light_a_row() {
    let mut app = files_app();
    app.in_list = false;
    app.enter();
    assert_eq!(said(&app).as_deref(), Some("nothing is lit: an arrow or a click lights a row"));
    // a form takes no click: the list behind it stands, drawn and not a target
    light_row(&mut app, "notes.md");
    app.hint_key(HintKey::Rename);
    let drawn = draw(&app);
    assert!(drawn.picks.is_empty(), "{:?}", drawn.picks);
    assert!(app.picks().is_empty());
    assert_eq!(app.selected_line(), None, "the status row is the form's");
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    let y = (0..HEIGHT)
        .find(|y| (0..WIDTH).map(|x| b[(x, *y)].symbol()).collect::<String>().contains("18 Oct"))
        .unwrap();
    assert_eq!(b[(0, y)].bg, p.lit, "the row being renamed stays lit");
}
