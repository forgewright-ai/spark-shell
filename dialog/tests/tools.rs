// The tools place (dialog/DESIGN.md, v0.129): six utilities after Norton Utilities, a page each. The rows are as
// `spark-shell provide tools` writes them.
mod common;
use common::palette;
use ratatui::{buffer::Buffer, layout::Rect};
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, Item, Provider, View, DESTS};
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
    fix["line"] = json!(format!("fix {SEP} runs spark-shell on in a terminal"));
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
         "inputSchema": {"type": "object", "properties": {"command": {"type": "string"}}}}
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
    assert_eq!(app.selected_line().as_deref(), Some("fix \u{b7} runs spark-shell on in a terminal"));
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
