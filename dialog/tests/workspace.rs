// The workspace place (dialog/DESIGN.md): the windows under their workspaces, the layouts, the menu's rows, a window's
// page and a layout's, the pickers, the form, the empty states and every door. The rows are as `spark-shell provide
// window` and `provide layout` write them.
mod common;
use common::palette;
use ratatui::{buffer::Buffer, layout::Rect};
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, HintKey, Item, Mode, Provider, View, DESTS, WORKSPACE_DEST};
use spark_dialog::model;
use spark_dialog::ui;
use std::time::{Duration, Instant};

const CLOCK: &str = "Sun 18 Oct \u{b7} 12:04";
const ONE: &str = "workspace 1 \u{235f} \u{b7} HDMI-A-1";
const TWO: &str = "workspace 2 \u{232c} \u{b7} this one \u{b7} eDP-1";

fn provider(label: &str, title: &str, rows: Value, tools: Value) -> Provider {
    let mut p = Provider::new(label);
    p.title = title.into();
    p.rows = model::rows(&rows.to_string()).unwrap();
    p.tools = model::tools(&json!({"tools": tools}));
    p.ready = true;
    p
}

fn window(id: &str, app: &str, title: &str, group: &str, ws: u32, placed: &str, front: bool) -> Value {
    json!({"id": format!("window:focus {id}"), "sign": "opens", "text": app, "group": group, "columns": [title], "children": null,
    "wide": [title, placed], "line": format!("{app} \u{b7} {title} \u{b7} workspace {ws} \u{b7} {placed}"), "front": front,
    "page": format!("spark-shell://window/page/{id}"),
    "tool": {"name": "window_focus", "arguments": {"name": id}, "said": "put in front"},
    "more": [
        {"name": "window_move", "arguments": {"name": id}, "said": "move to workspace", "value": ws.to_string(), "children": format!("spark-shell://window/rows/move/{id}")},
        {"name": "window_place", "arguments": {"name": id}, "said": "placement", "value": placed, "children": format!("spark-shell://window/rows/place/{id}")},
        {"name": "window_capture", "arguments": {"what": "window", "name": id}, "said": "capture this window"},
        {"name": "window_close", "arguments": {"name": id}, "said": "close"}
    ]})
}

fn capture(what: &str, text: &str, key: &str) -> Value {
    json!({"id": format!("window:capture {what}"), "sign": "opens", "text": text, "key": key, "columns": [], "more": [], "children": null, "group": null,
        "tool": {"name": "window_capture", "arguments": {"what": what}}})
}

fn arrange(value: &str) -> Value {
    json!({"id": "window:arrange", "sign": "opens", "text": "arrange windows", "tool": null, "more": [], "choice": true, "columns": [value],
        "children": "spark-shell://window/rows/arrange", "group": null})
}

fn layout(name: &str, apps: &str, why: &str) -> Value {
    json!({"id": format!("layout:open {name}"), "sign": "opens", "text": name, "group": "layouts", "columns": [apps], "wide": [apps, why], "children": null,
        "line": format!("{name} \u{b7} {apps} \u{b7} {why}"), "tool": {"name": "layout_open", "arguments": {"name": name}, "said": "open"},
        "page": format!("spark-shell://layout/page/{name}"),
        "more": [{"name": "layout_rename", "arguments": {"name": name}, "ask": ["to"], "said": "rename"},
                 {"name": "layout_delete", "arguments": {"name": name}, "said": "delete"}]})
}

fn save_row() -> Value {
    json!({"id": "layout:save", "sign": "opens", "text": "save this workspace", "columns": [], "more": [], "children": null, "group": null,
        "tool": {"name": "layout_save", "arguments": {}, "ask": ["name"]}})
}

fn tools() -> (Value, Value) {
    (
        json!([{"name": "window_focus"}, {"name": "window_close"}, {"name": "window_capture"}, {"name": "window_move"}, {"name": "window_place"}, {"name": "window_tabs"}]),
        json!([{"name": "layout_open"}, {"name": "layout_add"}, {"name": "layout_rename"}, {"name": "layout_delete"},
               {"name": "layout_save", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}}]),
    )
}

fn app_with(window_state: &str, window_rows: Value, layout_rows: Value) -> App {
    let cfg = Config {
        model: true,
        talk: true,
        close: true,
        ..Config::default()
    };
    let mut app = App::new(cfg, &[]);
    let (wt, lt) = tools();
    app.providers = vec![
        provider(
            "window",
            window_state,
            json!({"title": "window", "state": window_state, "rows": window_rows, "short": []}),
            wt,
        ),
        provider("layout", "", json!({"title": "layout", "rows": layout_rows, "short": []}), lt),
    ];
    app.model_name = Some("gemma4-26b-a4b".into());
    app.size = (60, 40);
    app
}

/// Four windows on two workspaces and two screens, two layouts, a recent one and an offer.
fn busy() -> App {
    app_with(
        "4 windows",
        json!([
            window("11", "firefox", "claude code", ONE, 1, "tiled", false),
            window("12", "foot", "~/projects", ONE, 1, "tiled", false),
            window("21", "foot", "btop", TWO, 2, "floating", true),
            window("22", "chromium", "invoice-0412.pdf", TWO, 2, "tiled", false),
            capture("screen", "capture the screen", "Print"),
            capture("area", "capture an area", "Shift+Print"),
            arrange("side by side")
        ]),
        json!([
            {"id": "layout:add btop", "sign": "opens", "text": "btop", "group": "also open", "columns": ["suggested for writing"], "more": [], "children": null,
             "tool": {"name": "layout_add", "arguments": {"name": "btop"}}},
            layout("writing", "foot, firefox", "saved 4 Nov 2026"),
            layout("news", "newsboat, firefox, mpv", "saved 2 Nov 2026"),
            save_row()
        ]),
    )
}

fn at_workspace(app: &mut App) {
    assert!(app.go_to("window"), "a bar click on the windows opens the place");
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

fn screen(app: &mut App) -> String {
    let (w, h) = app.size;
    snapshot(app, w, h)
}

fn pick_of(app: &App, text: &str) -> usize {
    app.picks()
        .iter()
        .position(|it| match it {
            Item::Row(p, r) => app.providers[*p].rows.rows[*r].text == text,
            _ => false,
        })
        .unwrap_or_else(|| panic!("no pick {text}"))
}

fn lit_text(app: &App) -> String {
    match &app.picks()[app.sel] {
        Item::Row(p, r) => app.providers[*p].rows.rows[*r].text.clone(),
        other => format!("{other:?}"),
    }
}

#[test]
fn the_list_stands_in_order_with_the_bar_on_the_window_in_front() {
    let mut app = busy();
    at_workspace(&mut app);
    assert_eq!(app.title(), "workspace");
    assert_eq!(app.subtitle(), "4 windows");
    assert_eq!(lit_text(&app), "foot", "the bar is on the window that was in front");
    assert_eq!(app.selected_line().unwrap(), "foot \u{b7} btop \u{b7} workspace 2 \u{b7} floating");
    golden(&mut app, "workspace-list", 60, 40);
    golden(&mut app, "workspace-wide", 130, 40);
    let order: Vec<String> = app
        .items()
        .iter()
        .filter_map(|it| match it {
            Item::Heading(h) => Some(h.clone()),
            Item::Row(p, r) if app.providers[*p].rows.rows[*r].group.is_none() => Some(app.providers[*p].rows.rows[*r].text.clone()),
            _ => None,
        })
        .collect();
    assert_eq!(
        order,
        [
            ONE,
            TWO,
            "also open",
            "layouts",
            "capture the screen",
            "capture an area",
            "arrange windows",
            "save this workspace"
        ],
        "windows, then layouts, then a menu's rows"
    );
}

#[test]
fn a_window_and_a_layout_are_objects_and_the_rest_a_menus_rows() {
    let mut app = busy();
    at_workspace(&mut app);
    for name in ["firefox", "writing"] {
        assert!(app.object_pick(pick_of(&app, name)), "{name}");
    }
    for name in ["capture the screen", "arrange windows", "save this workspace", "btop"] {
        assert!(!app.object_pick(pick_of(&app, name)), "{name}");
    }
    let t0 = Instant::now();
    let firefox = pick_of(&app, "firefox");
    app.clicked(firefox, t0);
    assert_eq!(app.mode, Mode::Normal);
    assert_eq!(
        app.selected_line().unwrap(),
        "firefox \u{b7} claude code \u{b7} workspace 1 \u{b7} tiled",
        "one click selects"
    );
    assert!(app.running.is_none(), "nothing acted on the first click");
    // a menu's row acts on the first click: arrange opens its list, here with no provider to read it from
    let t1 = t0 + Duration::from_secs(5);
    let arrange = pick_of(&app, "arrange windows");
    app.clicked(arrange, t1);
    assert!(matches!(app.view, View::Folder(0, _)), "{:?}", app.view);
}

#[test]
fn a_heading_is_the_filter_and_esc_shows_all() {
    let mut app = busy();
    at_workspace(&mut app);
    app.apps_heading(TWO);
    assert_eq!(app.subtitle(), "2 \u{232c}", "the header carries the heading's words");
    let shown = screen(&mut app);
    assert!(shown.contains("all windows") && shown.contains("Esc"), "Esc's chip says what it does: {shown}");
    assert!(!shown.contains("firefox") && !shown.contains("capture the screen"), "that heading alone");
    golden(&mut app, "workspace-filtered", 60, 40);
    app.escape();
    assert_eq!(app.subtitle(), "4 windows");
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST), "Esc showed all and stayed");
    app.apps_heading("layouts");
    assert_eq!(app.subtitle(), "layouts");
    app.apps_heading("layouts");
    assert_eq!(app.subtitle(), "4 windows", "a click on the heading shown alone widens it");
    app.apps_heading(TWO);
    app.left();
    assert_eq!(app.subtitle(), "4 windows", "Left is a door of the same step");
    app.escape();
    assert_eq!(app.view, View::Home, "then back");
}

#[test]
fn f9_on_a_window_opens_its_page_and_a_choice_its_list_and_the_pick_comes_back() {
    let mut app = busy();
    at_workspace(&mut app);
    let lit = app.sel;
    app.right();
    assert_eq!(
        (app.view.clone(), app.sel),
        (View::Dest(WORKSPACE_DEST), lit),
        "Right opens nothing outside files"
    );
    app.hint_key(HintKey::Actions);
    assert!(matches!(app.view, View::Steps(0)), "{:?}", app.view);
    assert_eq!((app.title().as_str(), app.subtitle().as_str()), ("workspace", "foot"));
    golden(&mut app, "workspace-window", 60, 40);
    // the second step is move to workspace: a choice, so its list opens and the page is kept
    app.sel = 1;
    app.enter();
    assert!(matches!(app.view, View::Folder(0, _)), "{:?}", app.view);
    let uri = "spark-shell://window/rows/move/21".to_string();
    let rows = json!({"title": "foot", "rows": [
        {"id": "window:move:1", "sign": "blank", "text": "1 \u{235f}", "columns": ["firefox, foot"], "more": [], "children": null, "group": "move to workspace", "back": true,
         "tool": {"name": "window_move", "arguments": {"name": "21", "to": "1"}}},
        {"id": "window:move:2", "sign": "check", "text": "2 \u{232c}", "columns": ["chromium, foot"], "more": [], "children": null, "group": "move to workspace", "back": true, "tool": null},
        {"id": "window:move:3", "sign": "blank", "text": "3 \u{2206}", "columns": ["empty"], "more": [], "children": null, "group": "move to workspace", "back": true,
         "tool": {"name": "window_move", "arguments": {"name": "21", "to": "3"}}}
    ]});
    app.folder = Some((0, uri, model::rows(&rows.to_string()).unwrap()));
    assert_eq!(app.subtitle(), "foot");
    golden(&mut app, "workspace-move", 60, 40);
    app.in_list = true;
    app.sel = 1;
    app.enter();
    assert!(
        matches!(app.view, View::Steps(0)),
        "the row in use goes back with nothing to do: {:?}",
        app.view
    );
    assert_eq!(app.steps_row.as_ref().map(|r| r.text.as_str()), Some("foot"), "the page is still the window's");
    app.escape();
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST));
    assert_eq!(lit_text(&app), "foot", "back on its row");
}

#[test]
fn f9_on_a_layout_opens_its_page() {
    let mut app = busy();
    at_workspace(&mut app);
    app.sel = pick_of(&app, "writing");
    app.in_list = true;
    app.hint_key(HintKey::Actions);
    assert_eq!(app.subtitle(), "writing");
    golden(&mut app, "workspace-layout", 60, 40);
}

#[test]
fn f2_renames_a_layout_from_its_name_and_a_window_has_none() {
    let mut app = busy();
    at_workspace(&mut app);
    app.hint_key(HintKey::Rename);
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("nothing to rename here"), "a window");
    app.sel = pick_of(&app, "writing");
    app.in_list = true;
    app.hint_key(HintKey::Rename);
    assert!(matches!(app.mode, Mode::Ask { .. }), "{:?}", app.mode);
    assert_eq!(app.input, "writing", "the name as it is");
    assert_eq!(app.subtitle(), "rename layout");
    app.set_draft("");
    assert_eq!(app.placeholder(), "new name");
    app.escape();
    assert_eq!(app.mode, Mode::Normal);
}

#[test]
fn saving_is_a_form_in_the_prompt() {
    let mut app = busy();
    at_workspace(&mut app);
    app.sel = pick_of(&app, "save this workspace");
    app.in_list = true;
    app.enter();
    assert!(matches!(app.mode, Mode::Ask { .. }), "{:?}", app.mode);
    assert_eq!(app.subtitle(), "save layout");
    assert_eq!(app.placeholder(), "a name for this layout");
    golden(&mut app, "workspace-save", 60, 40);
    app.escape();
    assert_eq!(app.mode, Mode::Normal);
    assert_eq!(app.subtitle(), "4 windows", "Esc lets it go");
}

#[test]
fn f3_previews_a_window_or_a_layout_and_no_letter_or_space_does() {
    let mut app = busy();
    at_workspace(&mut app);
    assert!(app.in_list, "the bar stands on the window in front on arrival");
    let hint: String = app.hint().iter().map(|(t, _)| t.as_str()).collect();
    assert!(hint.contains("View F3"), "the key bar reads the view binding's label: {hint}");
    assert!(!hint.contains("Space"), "{hint}");

    // Space: no preview, no letter of a search not begun
    let lit = lit_text(&app);
    app.typed(' ');
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST), "Space shows no preview");
    assert!(app.preview.is_none());
    assert_eq!(app.input, "", "and types nothing");
    assert_eq!(lit_text(&app), lit, "and leaves the bar where it was");

    // p is the letter, with the bar on a window: a search starts and nothing opens
    app.text_key('p');
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST), "p opens no preview");
    assert!(app.preview.is_none());
    assert_eq!(app.input, "p", "p starts a search");
    app.set_draft("");

    // F3 on a window, and Esc comes back
    app.sel = pick_of(&app, &lit);
    app.in_list = true;
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 previews the lit window");
    assert_eq!(app.preview.as_ref().unwrap().row().text, lit);
    app.escape();
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST), "Esc comes back to the list");
    assert_eq!(app.input, "", "nothing typed");

    // F3 on a layout
    app.sel = pick_of(&app, "writing");
    app.in_list = true;
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 previews the lit layout");
    assert_eq!(app.preview.as_ref().unwrap().row().text, "writing");
    app.escape();

    // words typed: F3 is no letter, so it previews the row the bar is on
    for c in "writing".chars() {
        app.typed(c);
    }
    assert_eq!(lit_text(&app), "writing", "the bar on the best match");
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 with words typed previews the best match");
    app.escape();

    // a menu's row has no page: F3 does nothing and types nothing
    app.set_draft("");
    app.sel = pick_of(&app, "save this workspace");
    app.in_list = true;
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST));
    assert_eq!(app.input, "", "no page: F3 does nothing");

    // a form is the prompt's: F3 opens nothing over it
    app.enter();
    assert!(matches!(app.mode, Mode::Ask { .. }), "{:?}", app.mode);
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST), "no preview over a form");
    assert_eq!(app.input, "", "and F3 types nothing in the name");
}

#[test]
fn preview_bound_to_a_letter_stays_that_letter_in_the_words() {
    let dir = std::env::temp_dir().join(format!("ws-keys-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("home-keys.json");
    std::fs::write(&file, r#"{"preview": "P"}"#).unwrap();
    let keys = spark_dialog::keys::Bindings::load(&file).unwrap();
    std::fs::remove_dir_all(&dir).unwrap();

    let mut app = busy();
    app.cfg.keys = keys;
    at_workspace(&mut app);
    let drawn = screen(&mut app);
    assert!(drawn.contains("view  P"), "the key bar draws the person's own key: {drawn}");
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Preview, "nothing typed: their key previews");
    app.escape();
    app.typed('a');
    app.hint_key(HintKey::View);
    assert_eq!(app.view, View::Dest(WORKSPACE_DEST), "with words typed it opens nothing");
    assert_eq!(app.input, "ap", "it is the letter of the search");
    app.set_draft("");
    app.sel = pick_of(&app, "save this workspace");
    app.in_list = true;
    app.hint_key(HintKey::View);
    assert_eq!(app.input, "p", "on a row with no page it is the letter too");
}

fn none_saved() -> Value {
    json!([
        {"id": "layout:show:none saved", "sign": "blank", "text": "none saved: ask at the prompt or save this workspace", "tool": null, "more": [], "columns": [],
         "children": null, "group": "layouts", "muted": true, "when_model": true},
        {"id": "layout:show:none", "sign": "blank", "text": "none saved: save this workspace to keep one", "tool": null, "more": [], "columns": [],
         "children": null, "group": "layouts", "muted": true, "when_model": false},
        {"id": "layout:save", "sign": "opens", "text": "save this workspace", "tool": null, "more": [], "columns": [], "children": null, "group": null, "muted": true}
    ])
}

fn empty() -> App {
    app_with(
        "no windows",
        json!([
            {"id": "window:none", "sign": "blank", "text": "no windows here", "tool": null, "more": [], "columns": [], "children": null,
             "group": "workspace 1 \u{235f} \u{b7} this one", "muted": true},
            capture("screen", "capture the screen", "Print"),
            capture("area", "capture an area", "Shift+Print"),
            arrange("side by side")
        ]),
        none_saved(),
    )
}

#[test]
fn nothing_open_and_nothing_saved() {
    let mut app = empty();
    at_workspace(&mut app);
    assert_eq!(app.subtitle(), "no windows");
    golden(&mut app, "workspace-empty", 60, 40);
    assert!(screen(&mut app).contains("none saved: ask at the prompt"));
    app.model_on = false;
    let shown = screen(&mut app);
    assert!(
        shown.contains("none saved: save this workspace to keep one") && !shown.contains("ask at the prompt"),
        "no model, no asking: {shown}"
    );
}

#[test]
fn a_terminal_session_has_the_layouts_alone() {
    let mut app = app_with(
        "no desktop",
        json!([]),
        json!([{"id": "layout:open writing", "sign": "opens", "text": "writing", "group": "layouts", "columns": ["foot, firefox"], "more": [], "children": null,
            "line": "writing \u{b7} foot, firefox \u{b7} opens in tmux", "tool": {"name": "layout_open", "arguments": {"name": "writing"}}}]),
    );
    at_workspace(&mut app);
    assert_eq!(app.subtitle(), "no desktop");
    app.in_list = true;
    assert_eq!(app.selected_line().unwrap(), "writing \u{b7} foot, firefox \u{b7} opens in tmux");
    golden(&mut app, "workspace-no-desktop", 60, 40);
}

#[test]
fn homes_column_says_what_the_place_holds() {
    let d = DESTS.iter().position(|d| d.name == "workspace").unwrap();
    let mut app = busy();
    assert_eq!(app.dest_state(d).unwrap(), "4 windows \u{b7} firefox, foot, chromium", "an app named once");
    assert_eq!(empty().dest_state(d).unwrap(), "no windows open");
    app.providers[0] = provider("window", "no windows", json!({"title": "window", "rows": [], "short": []}), json!([]));
    assert_eq!(app.dest_state(d).unwrap(), "no windows open \u{b7} 2 layouts");
    app.providers[0] = provider("window", "no desktop", json!({"title": "window", "rows": [], "short": []}), json!([]));
    assert_eq!(app.dest_state(d).unwrap(), "2 layouts \u{b7} writing, news");
    let mut bare = empty();
    bare.providers[0] = provider("window", "no desktop", json!({"title": "window", "rows": [], "short": []}), json!([]));
    assert_eq!(bare.dest_state(d), None, "no desktop and nothing saved: the place's purpose stands");
}

#[test]
fn words_search_the_titles_and_the_apps_of_a_layout() {
    let mut app = busy();
    at_workspace(&mut app);
    for c in "invoice".chars() {
        app.typed(c);
    }
    assert!(app.items().iter().any(|it| matches!(it, Item::Row(0, 3))), "a title is searched");
    app.set_draft("");
    for c in "newsboat".chars() {
        app.typed(c);
    }
    assert!(app.picks().iter().any(|it| matches!(it, Item::Row(1, 2))), "a layout's apps are searched");
}
