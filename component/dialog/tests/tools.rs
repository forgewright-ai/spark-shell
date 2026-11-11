// The tools place (the dialog design notes, v0.129): six utilities after Norton Utilities, a page each. The rows are as
// `spark-shell provide tools` writes them.
mod common;
use common::palette;
use ratatui::{buffer::Buffer, layout::Rect};
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, HintKey, Item, Mode, Provider, View, DESTS};
use spark_dialog::model;
use spark_dialog::ui;

const CLOCK: &str = "Sun 18 Oct \u{b7} 12:04";
const SEP: &str = "\u{b7}";

fn provider(label: &str, rows: Value, tools: Value) -> Provider {
    let mut p = Provider::new(label);
    p.rows = model::rows(&rows.to_string()).unwrap();
    p.tools = model::tools(&json!({"tools": tools}));
    p.ready = true;
    p
}

fn menu_row(name: &str, state: &str, line: &str) -> Value {
    json!({"id": format!("tools:{name}"), "sign": "blank", "text": name, "tool": null, "more": [], "columns": [state],
        "children": format!("spark-shell://tools/rows/{name}"), "group": null, "line": format!("{name} {SEP} {line}")})
}

fn menu() -> Value {
    json!({"title": "tools", "state": "", "rows": [
        menu_row("check", "2 problems", "test the setup and fix problems"),
        menu_row("space", "120.3 GB free", "see what uses the disk"),
        menu_row("running", "412 processes", "see what uses the cpu and memory"),
        menu_row("system", "Void Linux, 16 GB", "hardware and software details"),
        menu_row("updates", "spark-shell v0.128", "update spark-shell and the system"),
        menu_row("software", "837 packages", "installed packages and their licenses")
    ], "short": []})
}

fn row(id: &str, text: &str) -> Value {
    json!({"id": id, "sign": "blank", "text": text, "tool": null, "more": [], "columns": [], "children": null, "group": null})
}

fn gap(n: &str) -> Value {
    let mut g = row(&format!("tools:gap:{n}"), "");
    g["muted"] = json!(true);
    g
}

/// The check's page, as `spark-shell provide tools` writes it for two problems one fix covers.
fn check_page() -> Value {
    let problem = |name: &str, label: &str, detail: &str| {
        let mut r = row(&format!("tools:problem:{name}"), label);
        r["group"] = json!("problems");
        r["columns"] = json!([detail]);
        r
    };
    let mut fix = row("tools:fix:spark-shell on", "fix");
    fix["columns"] = json!(["spark-shell on"]);
    fix["tool"] = json!({"name": "tools_fix", "arguments": {"command": "spark-shell on"}});
    fix["line"] = json!(format!("fix {SEP} in a terminal: spark-shell on"));
    let mut passed = row("tools:passed", "14 passed");
    passed["children"] = json!("spark-shell://tools/rows/check/passed");
    passed["line"] = json!(format!("14 passed {SEP} the checks with no problem"));
    let mut na = row("tools:na", "7 not applicable");
    na["muted"] = json!(true);
    let mut again = row("tools:check-again", "check again");
    again["columns"] = json!(["checked at 09:12"]);
    again["tool"] = json!({"name": "tools_check", "arguments": {}});
    again["line"] = json!(format!("check again {SEP} runs every test again"));
    json!({"title": "check", "state": "2 problems", "rows": [
        problem("tools", "programs", "missing: fzf zoxide"),
        problem("look", "config files", "out of date: .tmux.conf"),
        gap("1"), fix, gap("2"), passed, na, gap("3"), again
    ], "short": []})
}

fn tools_list() -> Value {
    json!([
        {"name": "tools_check", "annotations": {"readOnlyHint": true, "destructiveHint": false}},
        {"name": "tools_fix", "annotations": {"readOnlyHint": false, "destructiveHint": false}, "_meta": {"spark-shell/opens": true},
         "inputSchema": {"type": "object", "properties": {"command": {"type": "string"}}}},
        {"name": "tools_front", "title": "tools front NAME", "description": "Put a running program's newest window in front.",
         "annotations": {"readOnlyHint": false, "destructiveHint": false}, "_meta": {"spark-shell/opens": true},
         "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}},
        {"name": "tools_end", "title": "end NAME", "description": "End a program and all its processes. Unsaved work is lost.",
         "annotations": {"readOnlyHint": false, "destructiveHint": true},
         "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}}
    ])
}

fn app() -> App {
    let cfg = Config {
        model: true,
        talk: true,
        close: true,
        ..Config::default()
    };
    let mut app = App::new(cfg, &[]);
    app.providers = vec![provider("tools", menu(), tools_list())];
    app.model_name = Some("gemma4-26b-a4b".into());
    app.size = (60, 40);
    app
}

fn at_tools(app: &mut App) {
    let d = DESTS.iter().position(|d| d.name == "tools").unwrap();
    app.came_from = vec![View::Home];
    app.view = View::Section(0);
    assert_eq!(app.dest_sections(d), vec![0], "tools holds the tools section");
}

fn at_page(app: &mut App, name: &str, page: Value) {
    at_tools(app);
    let uri = format!("spark-shell://tools/rows/{name}");
    app.came_from.push(View::Section(0));
    app.view = View::Folder(0, uri.clone());
    app.folder = Some((0, uri, model::rows(&page.to_string()).unwrap()));
    app.in_list = true;
    app.sel = 0;
}

fn snapshot(app: &App, w: u16, h: u16) -> String {
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, w, h));
    ui::draw(app, &p, CLOCK, &mut b);
    ui::snapshot(&b, &p)
}

fn golden(app: &mut App, name: &str, w: u16, h: u16) {
    app.size = (w, h);
    let got = snapshot(app, w, h);
    let path = format!("{}/tests/golden/{}.txt", env!("CARGO_MANIFEST_DIR"), name);
    if std::env::var("UPDATE_GOLDEN").is_ok() {
        std::fs::write(&path, &got).unwrap();
    }
    assert_eq!(
        got,
        std::fs::read_to_string(&path).unwrap_or_default(),
        "{name} differs (UPDATE_GOLDEN=1 after looking at it)"
    );
}

fn label(app: &App, it: &Item) -> String {
    match it {
        Item::Row(p, r) => app.providers[*p].rows.rows[*r].text.clone(),
        Item::Folder(i) => app.folder.as_ref().map(|(_, _, rows)| rows.rows[*i].text.clone()).unwrap_or_default(),
        _ => String::new(),
    }
}

#[test]
fn tools_is_six_utilities_each_with_its_state_and_its_line() {
    let mut app = app();
    at_tools(&mut app);
    app.in_list = true;
    app.sel = 0;
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["check", "space", "running", "system", "updates", "software"]);
    assert_eq!(app.selected_line().as_deref(), Some("check \u{b7} test the setup and fix problems"));
    app.sel = 2;
    assert_eq!(app.selected_line().as_deref(), Some("running \u{b7} see what uses the cpu and memory"));
    // a menu: one click opens, as Enter does
    app.sel = 0;
    assert!(!app.object_pick(0), "the six are a menu's rows");
    app.sel = 0;
    golden(&mut app, "tools", 60, 40);
}

#[test]
fn home_says_the_last_check_and_tools_before_its_rows_says_what_it_holds() {
    let mut app = app();
    let d = DESTS.iter().position(|d| d.name == "tools").unwrap();
    assert_eq!(app.dest_state(d).as_deref(), Some("2 problems"));
    app.providers[0].ready = false;
    assert_eq!(app.dest_state(d), None);
    assert_eq!(DESTS[d].purpose, "check, space, running");
}

#[test]
fn check_is_the_problems_then_one_fix_for_both_then_what_passed() {
    let mut app = app();
    at_page(&mut app, "check", check_page());
    // the problems are facts: the bar lands on the fix, the passed list and check again alone
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["fix", "14 passed", "check again"]);
    assert_eq!(app.selected_line().as_deref(), Some("fix \u{b7} in a terminal: spark-shell on"));
    assert_eq!(app.subtitle(), "check");
    golden(&mut app, "tools-check", 60, 40);
    // Enter on the fix runs its tool with the command, as the row says
    // Enter on the fix sends its tool at once: no question, it only opens a terminal (with no provider running here,
    // the send is refused, which proves it was sent)
    app.enter();
    assert!(matches!(app.mode, spark_dialog::app::Mode::Normal), "{:?}", app.mode);
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("not done: the part of the desktop that does it stopped")
    );
}

#[test]
fn check_with_no_problems_says_so_and_offers_no_fix() {
    let mut app = app();
    let page = json!({"title": "check", "state": "no problems", "rows": [
        {"id": "tools:passed", "sign": "blank", "text": "16 passed", "tool": null, "more": [], "columns": [], "children": "spark-shell://tools/rows/check/passed", "group": null},
        {"id": "tools:na", "sign": "blank", "text": "7 not applicable", "tool": null, "more": [], "columns": [], "children": null, "group": null, "muted": true},
        gap("3"),
        {"id": "tools:check-again", "sign": "blank", "text": "check again", "tool": {"name": "tools_check", "arguments": {}}, "more": [], "columns": ["checked at 09:12"], "children": null, "group": null}
    ], "short": []});
    at_page(&mut app, "check", page);
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["16 passed", "check again"]);
    golden(&mut app, "tools-check-ok", 60, 40);
}

fn fact(group: &str, label: &str, value: &str) -> Value {
    json!({"id": format!("tools:fact:{label}"), "sign": "blank", "text": label, "tool": null, "more": [], "columns": [value], "children": null, "group": group})
}

#[test]
fn system_is_three_groups_of_facts_and_copy_details() {
    let mut app = app();
    let mut copy = row("tools:copy-details", "copy details");
    copy["tool"] = json!({"name": "tools_copy_details", "arguments": {}});
    copy["line"] = json!(format!("copy details {SEP} to the clipboard, for bug reports"));
    let page = json!({"title": "system", "state": "", "rows": [
        fact("hardware", "model", "ThinkPad T14 Gen 3"),
        fact("hardware", "processor", "AMD Ryzen 7 PRO 6850U, 8 cores"),
        fact("hardware", "memory", "16 GB, 5.2 GB used"),
        fact("hardware", "disk", "476.9 GB, 120.3 GB free"),
        fact("hardware", "graphics", "amdgpu"),
        fact("hardware", "battery", "82%, health 91%"),
        fact("operating system", "system", "Void Linux"),
        fact("operating system", "kernel", "6.12.8_1"),
        fact("operating system", "init", "runit"),
        fact("operating system", "packages", "xbps"),
        fact("operating system", "uptime", "3 days"),
        fact("desktop", "sway", "1.10"),
        fact("desktop", "screens", "eDP-1 1920x1200, HDMI-A-1 2560x1440"),
        fact("desktop", "spark-shell", "v0.128"),
        fact("desktop", "spark-dialog", "v0.128.0"),
        fact("desktop", "spark", "1.113.1"),
        gap("1"), copy
    ], "short": []});
    at_page(&mut app, "system", page);
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["copy details"], "the facts are facts; copy details is the one row");
    assert_eq!(app.selected_line().as_deref(), Some("copy details \u{b7} to the clipboard, for bug reports"));
    golden(&mut app, "tools-system", 60, 40);
}

#[test]
fn updates_is_the_two_versions_and_the_two_updates() {
    let mut app = app();
    let mut up = row("tools:update", "update spark-shell");
    up["tool"] = json!({"name": "tools_update", "arguments": {}});
    up["line"] = json!(format!("update spark-shell {SEP} in a terminal: spark-shell update"));
    let mut sys = row("tools:update-system", "update system");
    sys["tool"] = json!({"name": "tools_update_system", "arguments": {}});
    sys["line"] = json!(format!("update system {SEP} in a terminal: sudo xbps-install -Su"));
    let page = json!({"title": "updates", "state": "", "rows": [
        fact("", "spark-shell", "v0.128, released 6 Nov 2026"), fact("", "spark-dialog", "v0.128.0"), up,
        gap("1"), fact("", "system", "Void Linux, xbps"), sys
    ], "short": []});
    let page: Value = serde_json::from_str(&page.to_string().replace("\"group\":\"\"", "\"group\":null")).unwrap();
    at_page(&mut app, "updates", page);
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["update spark-shell", "update system"]);
    assert_eq!(
        app.selected_line().as_deref(),
        Some("update spark-shell \u{b7} in a terminal: spark-shell update")
    );
    golden(&mut app, "tools-updates", 60, 40);
}

#[test]
fn software_counts_open_their_lists_and_a_package_is_an_object_with_its_view() {
    let mut app = app();
    let kind = |k: &str, n: &str, what: &str| {
        let mut r = row(&format!("tools:software:{k}"), k);
        r["columns"] = json!([n]);
        r["children"] = json!(format!("spark-shell://tools/rows/software/{k}"));
        r["line"] = json!(format!("{k} {SEP} {what}"));
        r
    };
    let mut export = row("tools:export", "export");
    export["columns"] = json!(["CycloneDX 1.5"]);
    export["tool"] = json!({"name": "tools_export", "arguments": {}});
    export["line"] = json!(format!("export {SEP} save the list as a CycloneDX file"));
    let page = json!({"title": "software", "state": "", "rows": [
        kind("apps", "4", "packages with a desktop entry"), kind("tools", "161", "packages with commands"),
        kind("parts", "672", "libraries and data"), gap("1"), export
    ], "short": []});
    at_page(&mut app, "software", page);
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["apps", "tools", "parts", "export"]);
    golden(&mut app, "tools-software", 60, 40);
    // a package's list: a package is an object, its line on the status row, Enter its view
    let package = |n: &str, v: &str, l: &str| {
        let mut r = row(&format!("tools:package:app:{n}"), n);
        r["columns"] = json!([v]);
        r["line"] = json!(format!("{n} {SEP} {v} {SEP} {l}"));
        r["page"] = json!(format!("spark-shell://tools/page/{n}"));
        r
    };
    let list = json!({"title": "apps", "state": "", "rows": [
        package("firefox", "133.0_1", "MPL-2.0"), package("foot", "1.20.2_1", "MIT"), package("mpv", "0.39.0_1", "GPL-2.0-or-later"), package("thunar", "4.20.0_1", "GPL-2.0-or-later")
    ], "short": []});
    at_page(&mut app, "software/apps", list);
    assert!(app.object_pick(0), "a package is an object: a click selects it");
    assert_eq!(app.selected_line().as_deref(), Some("firefox \u{b7} 133.0_1 \u{b7} MPL-2.0"));
    assert_eq!(app.subtitle(), "apps");
    golden(&mut app, "tools-software-apps", 60, 40);
    app.enter();
    assert_eq!(app.view, View::Preview, "Enter views a package, as F3 does");
}

/// A program of the running list, as `spark-shell provide tools` writes it: an object, its view, put in front when it
/// has a window, end when it is the person's.
fn program(name: &str, cpu: &str, mem: &str, n: u32, window: bool, mine: bool) -> Value {
    let procs = if n == 1 { "1 process".to_string() } else { format!("{n} processes") };
    let front = json!({"name": "tools_front", "arguments": {"name": name}, "said": "put in front"});
    let mut more = vec![];
    if mine {
        more.push(json!({"name": "tools_end", "arguments": {"name": name}, "said": "end"}));
    }
    let mut line = format!("{name} {SEP} {cpu} cpu {SEP} {mem} {SEP} {procs}");
    if !mine {
        line.push_str(&format!(" {SEP} user root"));
    }
    json!({"id": format!("tools:program:{name}"), "sign": "blank", "text": name, "more": more, "children": null, "group": null,
        "columns": [cpu, mem], "wide": [format!("{cpu} cpu"), mem, procs], "line": line,
        "page": format!("spark-shell://tools/page/{name}"), "tool": if window { front } else { Value::Null }})
}

fn running() -> Value {
    json!({"title": "running", "state": "412 processes", "rows": [
        program("firefox", "9%", "1.6 GB", 14, true, true),
        program("llama-server", "4%", "5.1 GB", 1, false, true),
        program("foot", "1%", "84 MB", 3, true, true),
        program("pipewire", "1%", "32 MB", 2, false, true),
        program("udevd", "0%", "4.0 MB", 1, false, false)
    ], "short": []})
}

#[test]
fn running_is_every_program_its_cpu_and_its_memory_and_a_program_is_an_object() {
    let mut app = app();
    at_page(&mut app, "running", running());
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["firefox", "llama-server", "foot", "pipewire", "udevd"]);
    assert!(app.object_pick(0), "a program is an object: a click selects it");
    assert!(app.object_pick(4), "every program");
    assert_eq!(app.selected_line().as_deref(), Some("firefox \u{b7} 9% cpu \u{b7} 1.6 GB \u{b7} 14 processes"));
    assert_eq!(app.subtitle(), "running");
    golden(&mut app, "tools-running", 60, 40);
    // another user's program says whose it is
    app.sel = 4;
    assert_eq!(
        app.selected_line().as_deref(),
        Some("udevd \u{b7} 0% cpu \u{b7} 4.0 MB \u{b7} 1 process \u{b7} user root")
    );
    // and has no actions here: it is not the person's, and it has no window
    app.hint_key(HintKey::Actions);
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("no actions here"));
    // a program with no window: Enter is its view, as F3
    app.reply = None;
    app.sel = 1;
    app.enter();
    assert_eq!(app.view, View::Preview, "Enter views a program with no window");
}

#[test]
fn f9_on_a_program_is_put_in_front_and_end_and_end_asks_first() {
    let mut app = app();
    at_page(&mut app, "running", running());
    app.hint_key(HintKey::Actions);
    assert!(matches!(app.view, View::Steps(0)), "{:?}", app.view);
    assert_eq!(app.subtitle(), "firefox");
    let words: Vec<String> = (0..2).filter_map(|k| app.step_call_words(k)).collect();
    assert_eq!(words, vec!["put in front", "end"]);
    assert!(app.step_call_words(2).is_none(), "two steps, each once");
    golden(&mut app, "tools-running-actions", 60, 40);
    // end: the question, its line and what it costs, keep working lit first
    app.in_list = true;
    app.sel = 1;
    app.enter();
    assert!(matches!(app.mode, Mode::Confirm(_)), "end asks first: {:?}", app.mode);
    assert_eq!(app.question_verb(), "end firefox");
    golden(&mut app, "tools-end", 60, 40);
    let screen = snapshot(&app, 60, 40);
    assert!(screen.contains("(unsaved work is lost)"), "{screen}");
    app.escape();
    assert!(matches!(app.mode, Mode::Normal), "Esc keeps working: {:?}", app.mode);
}

/// Space's page, as `spark-shell provide tools` writes it: the system disk, cleanup, home's largest folders.
fn space() -> Value {
    let clean = |id: &str, text: &str, size: &str, line: &str| {
        let mut r = row(id, text);
        r["group"] = json!("cleanup");
        r["columns"] = json!([size]);
        r["line"] = json!(format!("{text} {SEP} {line}"));
        r
    };
    let mut trash = clean("tools:trash", "trash", "2.1 GB", "open in files to restore or empty");
    trash["children"] = json!("spark-shell://files/rows/trash");
    let mut pkg = clean("tools:clean-packages", "package cache", "3.2 GB", "clean: sudo xbps-remove -O");
    pkg["tool"] = json!({"name": "tools_clean_packages", "arguments": {}});
    let mut caches = clean("tools:caches", "app caches", "1.4 GB", "~/.cache by folder");
    caches["page"] = json!("spark-shell://tools/page/caches");
    let folder = |name: &str, size: &str| {
        let hidden = name.starts_with('.');
        let mut r = row(&format!("tools:folder:{name}"), name);
        r["group"] = json!("home");
        r["columns"] = json!([size]);
        r["line"] = json!(format!("{name} {SEP} {size} {SEP} {}", if hidden { "hidden folder" } else { "folder" }));
        r["page"] = json!(format!("spark-shell://tools/page/{name}"));
        if !hidden {
            r["children"] = json!(format!("spark-shell://files/rows/{name}"));
        }
        r
    };
    let mut loose = folder("~", "2.4 GB");
    loose["text"] = json!("files in home");
    loose["line"] = json!(format!("files in home {SEP} 2.4 GB {SEP} files directly in ~"));
    loose["page"] = Value::Null;
    let mut more = row("tools:space:more", "9 more folders");
    more["group"] = json!("home");
    more["columns"] = json!(["0.4 GB"]);
    let mut again = row("tools:measure", "measure again");
    again["columns"] = json!(["measured at 09:12"]);
    again["tool"] = json!({"name": "tools_measure", "arguments": {}});
    again["line"] = json!(format!("measure again {SEP} what uses the disk now"));
    json!({"title": "space", "state": "120.3 GB free", "rows": [
        fact("", "system disk", "476.9 GB, 120.3 GB free"),
        trash, pkg, caches,
        folder("downloads", "18.2 GB"), folder("pictures", "12.0 GB"), folder("projects", "4.8 GB"), folder(".local", "4.2 GB"),
        loose, more, gap("1"), again
    ], "short": []})
}

#[test]
fn space_is_the_disk_then_cleanup_then_homes_folders_as_objects() {
    let mut app = app();
    at_page(&mut app, "space", space_page());
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(
        names,
        vec![
            "trash",
            "package cache",
            "app caches",
            "downloads",
            "pictures",
            "projects",
            ".local",
            "files in home",
            "measure again"
        ],
        "the disk and the rest of home are facts"
    );
    assert!(!app.object_pick(0), "cleanup is a menu: a click opens");
    assert_eq!(app.selected_line().as_deref(), Some("trash \u{b7} open in files to restore or empty"));
    golden(&mut app, "tools-space", 60, 40);
    app.sel = 3;
    assert!(app.object_pick(3), "a home folder is an object: a click selects it");
    assert!(app.object_pick(7), "and the files in home");
    assert!(!app.object_pick(8), "measure again is a menu's row");
    assert_eq!(app.selected_line().as_deref(), Some("downloads \u{b7} 18.2 GB \u{b7} folder"));
    app.sel = 6;
    assert_eq!(app.selected_line().as_deref(), Some(".local \u{b7} 4.2 GB \u{b7} hidden folder"));
    // files hides a hidden folder: Enter views it instead
    app.enter();
    assert_eq!(app.view, View::Preview, "Enter views a hidden folder");
    // app caches is a view: Enter opens it, as a click does
    at_page(&mut app, "space", space_page());
    app.sel = 2;
    app.enter();
    assert_eq!(app.view, View::Preview, "app caches opens its view");
}

fn space_page() -> Value {
    serde_json::from_str(&space().to_string().replace("\"group\":\"\"", "\"group\":null")).unwrap()
}

#[test]
fn keep_working_comes_back_to_the_program_the_words_found_and_enter_views_that_one() {
    let mut app = app();
    at_page(&mut app, "running", running());
    for c in "pipe".chars() {
        app.typed(c);
    }
    assert_eq!(app.selected_line().as_deref(), Some("pipewire \u{b7} 1% cpu \u{b7} 32 MB \u{b7} 2 processes"));
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "pipewire", "F9 with words typed: the program they found");
    app.in_list = true;
    app.sel = 0;
    app.enter();
    assert!(matches!(app.mode, Mode::Confirm(_)), "{:?}", app.mode);
    assert_eq!(app.question_verb(), "end pipewire");
    app.escape();
    // keep working: back on the list, the words as they were, the bar on the program it was asked for
    assert_eq!(app.view, View::Folder(0, "spark-shell://tools/rows/running".into()));
    assert_eq!(app.input, "pipe");
    assert_eq!(app.selected_line().as_deref(), Some("pipewire \u{b7} 1% cpu \u{b7} 32 MB \u{b7} 2 processes"));
    // Enter views the row the bar is on, though the words go first
    app.enter();
    assert_eq!(app.view, View::Preview);
    assert_eq!(app.preview.as_ref().map(|p| p.row().id.as_str()), Some("tools:program:pipewire"));
}

#[test]
fn enter_with_words_typed_views_the_package_they_found() {
    let mut app = app();
    let package = |n: &str| {
        let mut r = row(&format!("tools:package:app:{n}"), n);
        r["page"] = json!(format!("spark-shell://tools/page/{n}"));
        r
    };
    let list = json!({"title": "apps", "state": "", "rows": [package("firefox"), package("foot"), package("mpv"), package("thunar")], "short": []});
    at_page(&mut app, "software/apps", list);
    for c in "thun".chars() {
        app.typed(c);
    }
    app.enter();
    assert_eq!(
        app.preview.as_ref().map(|p| p.row().id.as_str()),
        Some("tools:package:app:thunar"),
        "not the first of the list"
    );
}
