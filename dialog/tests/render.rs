// The golden renders: the dialog drawn from fixed state in the two
// palettes the records name. Both palettes give the same grid of slots
// (every color bound to a token), and the grid is the file in golden/.
// UPDATE_GOLDEN=1 writes the files after a change that was looked at.
mod common;
use common::palette;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use serde_json::json;
use spark_dialog::app::{App, Config, Item, Line, Mode, Provider, Sign, Staged, Step, View, Who, CALENDAR_DEST, HEIGHT, SETTINGS_DEST, WIDTH};
use spark_dialog::model;
use spark_dialog::reply::{Mark, Reply};

const CLOCK: &str = "Sun 18 Oct \u{b7} 12:04";

fn provider(label: &str, title: &str, rows: serde_json::Value, tools: serde_json::Value) -> Provider {
    let mut p = Provider::new(label);
    p.title = title.into();
    p.version = "0.64".into();
    p.rows = model::rows(&rows.to_string()).unwrap();
    p.tools = model::tools(&json!({"tools": tools}));
    p.ready = true;
    p
}

fn row(id: &str, sign: &str, text: &str, tool: Option<(&str, serde_json::Value)>, group: Option<&str>) -> serde_json::Value {
    json!({"id": id, "sign": sign, "text": text, "tool": tool.map(|(n, a)| json!({"name": n, "arguments": a})), "more": [], "columns": [], "children": null, "group": group})
}

fn capture(what: &str, text: &str, key: &str) -> serde_json::Value {
    let mut r = row(
        &format!("window:capture {}", what),
        "opens",
        text,
        Some(("window_capture", json!({"what": what}))),
        None,
    );
    r["key"] = json!(key);
    r
}

fn open_window(name: &str, title: &str) -> serde_json::Value {
    let mut r = row(
        &format!("window:focus {}", name),
        "opens",
        name,
        Some(("window_focus", json!({"name": name}))),
        Some("open now"),
    );
    r["columns"] = json!([title]);
    r["more"] = json!([{"name": "window_close", "arguments": {"name": name}, "said": "close"}]);
    r
}

fn base() -> App {
    let cfg = Config {
        model: true,
        talk: true,
        close: true,
        ..Config::default()
    };
    let mut app = App::new(cfg, &[]);
    let window = provider(
        "window",
        "side by side",
        json!({"title": "window", "rows": [
            // as the provider writes them (#144): the layout, the captures with their keys, one row a window with its
            // title and close behind it
            row("window:show:side by side", "check", "side by side", None, Some("layout")),
            row("window:tabs", "ring", "tabs", Some(("window_tabs", json!({}))), Some("layout")),
            row("window:stacked", "ring", "stacked", Some(("window_stacked", json!({}))), Some("layout")),
            capture("screen", "capture the screen", "Print"),
            capture("area", "capture an area", "Shift+Print"),
            capture("window", "capture a window", "Super+Print"),
            open_window("terminal", "~/projects"),
            open_window("firefox", "Claude Code")
        ], "short": ["window:tabs", "window:stacked"]}),
        json!([{"name": "window_close", "title": "window close NAME", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}]),
    );
    let theme = provider(
        "theme",
        "tokyonight-night \u{b7} size 12",
        json!({"title": "theme", "rows": [
        {"id": "theme:more", "sign": "blank", "text": "tokyonight-night \u{b7} size 12 \u{b7} more", "tool": null, "more": [], "columns": [], "children": "spark-shell://theme/rows", "group": null}
    ], "short": ["theme:more"]}),
        json!([]),
    );
    let bt = provider(
        "bt",
        "MAJOR V",
        json!({"title": "bt", "rows": [
        row("bt:disconnect MAJOR V", "dot", "MAJOR V", Some(("bt_disconnect", json!({"name": "MAJOR V"}))), None),
        row("bt:connect Buds", "ring", "Buds", Some(("bt_connect", json!({"name": "Buds"}))), None)
    ], "short": ["bt:disconnect MAJOR V", "bt:connect Buds"]}),
        json!([]),
    );
    let about_rows: serde_json::Value = serde_json::from_str(include_str!("golden/about-rows.json")).unwrap();
    let mut about = provider("about", "", about_rows, json!([]));
    about.version = "0.90".into();
    app.providers = vec![window, theme, bt, about];
    app.about_idx = Some(3);
    app.model_name = Some("gemma4-26b-a4b".into());
    app.voice_on = true;
    app
}

fn render(app: &App, name: &str) {
    render_at(app, name, WIDTH, HEIGHT);
}

/// The app drawn at w by h in both palettes: the same grid of slots, the grid kept in golden/.
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

/// The base with a section for each place of the home: apps, files, notes and the clock too.
fn full() -> App {
    let mut app = base();
    for (l, t) in [("apps", "4 apps"), ("files", "your home"), ("notes", "2 notes"), ("clock", "")] {
        app.providers.push(provider(l, t, json!({"title": l, "rows": [], "short": []}), json!([])));
    }
    app
}

#[test]
fn home() {
    render(&full(), "home");
}

#[test]
fn home_in_a_small_window() {
    let mut app = full();
    app.size = (40, 26);
    render_at(&app, "home-small", 40, 26);
}

#[test]
fn a_window_too_small_says_so() {
    let mut app = full();
    app.size = (30, 14);
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, 30, 14));
    spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    let row: String = (0..30).map(|x| b[(x, 7)].symbol().to_string()).collect();
    assert_eq!(row.trim(), "Make this window larger");
}

#[test]
fn settings() {
    let mut app = full();
    app.view = View::Dest(SETTINGS_DEST);
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = 1;
    render(&app, "settings");
}

#[test]
fn the_model_picker_says_where_it_runs_and_for_whom() {
    let mut app = full();
    app.models = vec![
        ("gemma4-26b-a4b".into(), "serving".into()),
        ("qwen3-5-2b".into(), "downloaded".into()),
        ("qwen3-30b-a3b".into(), "-".into()),
    ];
    app.view = View::Models;
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = 1;
    app.input = "half a thought".into();
    app.cursor = 14;
    render(&app, "models");
}

#[test]
fn talk() {
    let mut app = full();
    app.view = View::Talk;
    app.came_from = vec![View::Home];
    render(&app, "talk");
}

#[test]
fn a_two_line_draft_and_a_file_for_the_next_question() {
    let mut app = full();
    app.cfg.plus = true;
    app.input = "summarize this\nand list what I should do first,\nthen what can wait".into();
    app.cursor = app.input.chars().count();
    app.attachment = Some("/data/me/notes.md".into());
    app.chip_focus = Some(4);
    render(&app, "draft");
}

#[test]
fn a_section_with_its_groups_and_a_click_left_an_undo() {
    // #196: a click says nothing; the step it ran left an undo, so the reply row under the keys holds Undo alone,
    // and the list starts where it always does
    let mut app = base();
    app.view = View::Section(0);
    app.came_from = vec![View::Home];
    app.reply = Some(Reply::undo_only());
    app.undo = Some(Step {
        prov: 0,
        call: model::Call {
            name: "window_focus".into(),
            arguments: json!({"name": "aerc"}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: None,
            value: None,
            children: None,
        },
        who: Who::Undo,
        line: "undo aerc".into(),
        typed: false,
    });
    render(&app, "section");
}

#[test]
fn a_question_is_its_turn_and_a_typed_step_its_reply() {
    // #53: a question's turn is the words and the answer; a typed step's receipt is the reply row, Undo at
    // its end, never a turn (#196)
    let mut app = full();
    app.view = View::Conversation;
    app.exchange = vec![
        Line {
            sign: Sign::You,
            text: "is firefox open?".into(),
        },
        Line {
            sign: Sign::Says,
            text: "No. Firefox is installed, and no window of it is open now.".into(),
        },
    ];
    app.undo = Some(Step {
        prov: 1,
        call: model::Call {
            name: "theme_palette".into(),
            arguments: json!({"name": "everforest-dark"}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: None,
            value: None,
            children: None,
        },
        who: Who::Undo,
        line: "undo theme gruvbox-dark".into(),
        typed: false,
    });
    let mut r = Reply::new(Mark::Done, "gruvbox-dark is on");
    r.undo = true;
    app.reply = Some(r);
    app.in_list = true;
    app.sel = 0;
    render(&app, "turn");
}

#[test]
fn commands_from_spark_wait_in_the_box_for_enter() {
    // #53: "movie time: connect the jabra, volume 60, dim the screen" came back as three commands,
    // one a line, in the box where the words were typed; Enter runs them, Esc drops them
    let mut app = full();
    let text = "bt connect jabra speak 410\nout level 60\ndisplay brightness 30".to_string();
    app.input = text.clone();
    app.cursor = text.chars().count();
    app.staged = Some(Staged {
        text,
        steps: vec![],
        draft: String::new(),
    });
    // the box is two rows: the reply row names every command in it (#196)
    app.reply = Some(Reply::new(Mark::Note, "run: bt connect jabra speak 410; out level 60; display brightness 30"));
    render(&app, "staged");
}

#[test]
fn a_long_list_says_how_many_rows_sit_below() {
    let mut app = base();
    let names = [
        "terminal",
        "aerc",
        "btop",
        "micro",
        "mpv",
        "pyradio",
        "firefox",
        "foot",
        "htop",
        "ncdu",
        "newsboat",
        "ranger",
        "vim",
        "w3m",
        "weechat",
        "alacritty",
        "cmus",
        "darktable",
        "evince",
        "fzf",
        "gimp",
        "helix",
        "imv",
        "inkscape",
        "kakoune",
        "lynx",
        "mutt",
        "nnn",
        "qutebrowser",
        "zathura",
    ];
    let rows: Vec<serde_json::Value> = names
        .iter()
        .map(|n| row(&format!("apps:open {}", n), "opens", n, Some(("apps_open", json!({"name": n}))), None))
        .collect();
    app.providers
        .insert(3, provider("apps", "30 apps", json!({"title": "apps", "rows": rows, "short": []}), json!([])));
    app.about_idx = Some(4);
    app.view = View::Section(3);
    app.came_from = vec![View::Home];
    render(&app, "long");
}

#[test]
fn a_list_of_a_thousand_pages_and_jumps_by_its_keys() {
    let mut app = base();
    let rows: Vec<serde_json::Value> = (0..1000)
        .map(|i| {
            row(
                &format!("apps:open {}", i),
                "opens",
                &format!("app {}", i),
                Some(("apps_open", json!({"name": i.to_string()}))),
                None,
            )
        })
        .collect();
    app.providers
        .insert(3, provider("apps", "1000 apps", json!({"title": "apps", "rows": rows, "short": []}), json!([])));
    app.about_idx = Some(4);
    app.view = View::Section(3);
    app.came_from = vec![View::Home];
    app.in_list = true;
    let step = app.size.1.saturating_sub(spark_dialog::ui::CONTENT_Y + spark_dialog::ui::BOTTOM + 1).max(4) as usize;
    app.page(1);
    assert_eq!(app.sel, step, "Page Down: the lit row a screen down");
    app.line_end();
    assert_eq!(app.sel, 999, "End: the last row");
    app.page(1);
    assert_eq!(app.sel, 999, "never past the last");
    app.page(-1);
    assert_eq!(app.sel, 999 - step);
    app.line_start();
    assert_eq!(app.sel, 0, "Home: the first row");
    app.in_list = false;
    (app.input, app.cursor) = ("words".into(), 5);
    app.line_start();
    assert_eq!((app.sel, app.cursor), (0, 0), "at the prompt, Home is the line's start");
}

#[test]
fn root_settings_says_the_look_and_the_screens_never_network_details() {
    // the settings row at home holds the look and the screens (dialog/DESIGN.md); a network's name or its state is
    // no business of the home's first screen
    let net = |wifi: &str, lan: &str| {
        let mut app = base();
        app.providers
            .insert(0, provider("wifi", wifi, json!({"title": "wifi", "rows": [], "short": []}), json!([])));
        app.providers
            .insert(1, provider("lan", lan, json!({"title": "lan", "rows": [], "short": []}), json!([])));
        app.about_idx = Some(app.providers.len() - 1);
        app.dest_state(spark_dialog::app::SETTINGS_DEST).unwrap_or_default()
    };
    for (wifi, lan) in [("not connected", "up"), ("private network", "up"), ("not connected", "no wire")] {
        let said = net(wifi, lan);
        assert!(!said.contains(wifi) && !said.contains(lan) && !said.contains("wi-fi"), "{:?}", said);
    }
}

#[test]
fn about() {
    let mut app = base();
    app.view = View::About;
    app.came_from = vec![View::Home];
    app.exchange = vec![Line {
        sign: Sign::You,
        text: "show me about".into(),
    }]; // the about is a page: the exchange is not drawn on it
    app.in_list = true;
    app.sel = 0;
    // the facts, then project, license, credits and help, then where it is installed (dialog/DESIGN.md, v0.127)
    let label = |app: &App, it: &Item| match it {
        Item::Row(p, r) => app.providers[*p].rows.rows[*r].text.clone(),
        Item::Dest(d) => spark_dialog::app::DESTS[*d].name.to_string(),
        _ => String::new(),
    };
    let names: Vec<String> = app.picks().iter().map(|it| label(&app, it)).collect();
    assert_eq!(names, vec!["project", "license", "credits", "help"]);
    assert_eq!(app.selected_line().as_deref(), Some("project \u{b7} opens in the browser"));
    render(&app, "about");
    // the license is a page: Enter reads it, as Space does; Esc comes back with the row lit
    app.sel = 1;
    app.enter();
    assert_eq!(app.view, View::Preview);
    assert_eq!(app.preview.as_ref().map(|pv| pv.row().id.clone()).as_deref(), Some("about:license"));
    app.escape();
    assert_eq!(app.view, View::About);
    assert_eq!(label(&app, &app.picks()[app.sel]), "license");
    // help is the dialog's own place
    app.sel = 3;
    app.enter();
    assert_eq!(app.view, View::Help);
}

#[test]
fn help_is_a_list_by_subject_with_key_chips() {
    let mut app = base();
    app.view = View::Help;
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = 2;
    // the dialog's keys first with sentences, then the desktop's by subject, then the words at the prompt
    let groups: Vec<String> = app
        .items()
        .iter()
        .filter_map(|it| match it {
            Item::Heading(h) => Some(h.clone()),
            _ => None,
        })
        .collect();
    assert_eq!(groups, vec!["general", "files", "view", "windows", "workspaces", "desktop", "prompt"]);
    assert_eq!(app.selected_line().as_deref(), Some("ask spark \u{b7} Ctrl+Enter"));
    assert_eq!(app.shortcuts(), 39, "21 of the dialog's and 18 of the desktop's");
    render(&app, "help");
    // words typed keep the rows they name, under their subjects, and the note goes
    app.input = "window".into();
    app.in_list = true;
    app.sel = 0;
    let rows: Vec<String> = app
        .items()
        .iter()
        .filter_map(|it| match it {
            Item::Key(w, _) => Some(w.clone()),
            _ => None,
        })
        .collect();
    assert!(
        rows.iter()
            .all(|w| w.contains("window") || w == "open a terminal" || w.ends_with("layout") || w == "move focus"),
        "{:?}",
        rows
    );
    assert!(
        rows.contains(&"close the window".to_string()) && rows.contains(&"move the window to a workspace".to_string()),
        "{:?}",
        rows
    );
    render(&app, "help-found");
}

#[test]
fn help_scrolls_past_its_last_row_to_the_note() {
    let mut app = base();
    app.view = View::Help;
    app.came_from = vec![View::Home];
    app.size = (60, 30);
    app.in_list = true;
    app.sel = app.picks().len() - 1;
    let (_, _, rows) = drawn(&app);
    let shown = |rows: &Vec<String>, s: &str| rows.iter().any(|r| r.contains(s));
    assert!(shown(&rows, "more") && !shown(&rows, "change keys"), "the note sits under the fold: {:?}", rows);
    // Down past the last row scrolls the list, so the note comes into view (dialog/DESIGN.md, v0.127.2)
    for _ in 0..3 {
        app.down();
    }
    let (_, _, rows) = drawn(&app);
    assert!(shown(&rows, "change keys") && !shown(&rows, "more"), "{:?}", rows);
    assert_eq!(app.sel, app.picks().len() - 1, "the bar stays on the last row");
}

#[test]
fn a_destructive_step_waits_for_yes() {
    let mut app = base();
    app.view = View::Section(0);
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = 1;
    app.mode = Mode::Confirm(Step {
        prov: 0,
        call: model::Call {
            name: "window_close".into(),
            arguments: json!({"name": "terminal"}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: None,
            value: None,
            children: None,
        },
        who: Who::Person,
        line: "window close terminal".into(),
        typed: false,
    });
    app.in_list = true;
    app.sel = 0;
    render(&app, "question");
}

#[test]
fn an_answer_wraps_under_its_sign() {
    let mut app = full();
    app.view = View::Conversation;
    app.exchange = vec![
        Line {
            sign: Sign::You,
            text: "what is my address".into(),
        },
        Line {
            sign: Sign::Says,
            text: "192.0.2.10 on the wire and 192.0.2.20 on wifi; the gateway is 192.0.2.1, and the name server the same.".into(),
        },
    ];
    render(&app, "answer");
}

#[test]
fn a_folder_with_its_columns_and_an_attachment() {
    let mut app = base();
    app.cfg.plus = true;
    let files = provider(
        "files",
        "the folders the host hands over",
        json!({"title": "files", "rows": [
        {"id": "files:root:a", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/aG9tZQ", "group": null}
    ], "short": ["files:root:a"]}),
        json!([]),
    );
    app.providers.push(files);
    let f = app.providers.len() - 1;
    let file = |id: &str, name: &str, size: &str, when: &str| json!({"id": id, "sign": "blank", "text": name, "tool": {"name": "files_open", "arguments": {"path": format!("/data/me/Downloads/{}", name)}}, "more": [], "columns": [size, when], "children": null, "group": null});
    let rows = model::rows(&json!({"title": "~/Downloads", "rows": [
        {"id": "files:up", "sign": "opens", "text": "..", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/aG9tZQ", "group": null},
        {"id": "files:dir:a", "sign": "opens", "text": "archive", "tool": null, "more": [], "columns": ["12 items"], "children": "spark-shell://files/rows/YQ", "group": null},
        file("files:file:1", "report.pdf", "2.1 MB", "yesterday"),
        file("files:file:2", "photo-0412.jpg", "4.8 MB", "today"),
        file("files:file:3", "notes.md", "2 KB", "today"),
        file("files:file:4", "setup.log", "14 KB", "today"),
        {"id": "files:total", "sign": "blank", "text": "4 files \u{b7} 6.9 MB", "tool": null, "more": [], "columns": [], "children": null, "group": null}
    ], "short": []}).to_string()).unwrap();
    app.view = View::Folder(f, "spark-shell://files/rows/RG93bmxvYWRz".into());
    app.came_from = vec![View::Home];
    app.folder = Some((f, "spark-shell://files/rows/RG93bmxvYWRz".into(), rows));
    app.in_list = true;
    app.sel = 3;
    app.attachment = Some("/data/me/notes.md".into());
    app.exchange = vec![Line {
        sign: Sign::You,
        text: "which of these are big".into(),
    }];
    render(&app, "folder");
}

/// The file manager (#112): the home folder as the provider lists it (the recent files, the folders and files, the folder's own steps).
fn manager_app() -> App {
    let mut app = base();
    app.cfg.plus = true;
    let files = provider(
        "files",
        "your home folder",
        json!({"title": "files", "rows": [
        {"id": "files:root:a", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/aG9tZQ", "group": null}
    ], "short": ["files:root:a"]}),
        json!([]),
    );
    app.providers.push(files);
    let f = app.providers.len() - 1;
    let steps = |p: &str| {
        json!([
            {"name": "files_reveal", "arguments": {"path": p}, "said": "reveal in the system file manager"},
            {"name": "files_rename", "arguments": {"path": p}, "ask": ["name"], "said": "rename"},
            {"name": "files_move", "arguments": {"path": p}, "pick": "to", "said": "move to a folder"},
            {"name": "files_copy", "arguments": {"path": p}, "pick": "to", "said": "copy to a folder"},
            {"name": "files_trash", "arguments": {"path": p}, "said": "trash"}
        ])
    };
    let file = |name: &str, size: &str, when: &str, group: &str, folder: Option<&str>| {
        let p = format!("/data/me/{}", name);
        let mut more = vec![
            json!({"name": "files_preview", "arguments": {"path": p}, "said": "preview"}),
            json!({"name": "files_attach", "arguments": {"path": p}, "said": "attach to the next request"}),
        ];
        more.extend(steps(&p).as_array().unwrap().iter().cloned());
        let mut columns = vec![size.to_string(), when.to_string()];
        if let Some(fo) = folder {
            columns.push(fo.to_string());
        }
        json!({"id": format!("files:file:{}:{}", group, name), "sign": "blank", "text": name, "tool": {"name": "files_open", "arguments": {"path": p}, "said": "open"}, "more": more, "columns": columns, "children": null, "group": group})
    };
    let dir = |name: &str, items: &str| {
        let p = format!("/data/me/{}", name);
        json!({"id": format!("files:dir:{}", name), "sign": "opens", "text": name, "tool": {"name": "files_browse", "arguments": {"path": p}, "said": "open in the system file manager"}, "more": steps(&p), "columns": [items], "children": format!("spark-shell://files/rows/{}", name), "group": "home"})
    };
    // the picture's row carries its small picture (drawn at the top right) and keeps its size, date and folder (#112)
    let mut photo = file("photo-0412.jpg", "4.8 MB", "yesterday", "recent", Some("camera"));
    photo["preview"] = json!("/data/me/.cache/thumbs/photo-0412.png");
    let rows = model::rows(&json!({"title": "~", "here": "/data/me", "rows": [
        file("invoice-0412.pdf", "120 KB", "today", "recent", Some("downloads")),
        photo,
        file("notes.md", "2 KB", "18 Oct", "recent", Some("~")),
        dir("documents", "12 items"),
        dir("downloads", "3 items"),
        dir("pictures", "40 items"),
        file("notes.md", "2 KB", "18 Oct", "home", None),
        file("todo.txt", "1 KB", "2025", "home", None),
        {"id": "files:total", "sign": "blank", "text": "2 files \u{b7} 3 KB", "tool": null, "more": [], "columns": [], "children": null, "group": "this folder"},
        {"id": "files:new-folder", "sign": "opens", "text": "new folder", "tool": {"name": "files_new_folder", "arguments": {"path": "/data/me"}, "ask": ["name"], "said": "new folder"}, "more": [], "columns": [], "children": null, "group": "this folder"},
        {"id": "files:new-text", "sign": "opens", "text": "new file", "tool": {"name": "files_new_text", "arguments": {"path": "/data/me"}, "ask": ["name"], "said": "new file"}, "more": [], "columns": [], "children": null, "group": "this folder"},
        {"id": "files:browse", "sign": "opens", "text": "open in the system file manager", "tool": {"name": "files_browse", "arguments": {"path": "/data/me"}, "said": "open in the system file manager"}, "more": [], "columns": [], "children": null, "group": "this folder"},
        {"id": "files:drive:s", "sign": "opens", "text": "STICK", "tool": null, "more": [], "columns": ["14.2 GB free"], "children": "spark-shell://files/rows/c3RpY2s", "group": "drives"}
    ], "short": []}).to_string()).unwrap();
    app.view = View::Folder(f, "spark-shell://files/rows/aG9tZQ".into());
    app.came_from = vec![View::Home];
    app.folder = Some((f, "spark-shell://files/rows/aG9tZQ".into(), rows));
    app.in_list = true;
    app.sel = 0;
    app
}

/// The picture's row lit: its small picture at the top right with no caption, the rows beside it ending
/// before it, and the row itself keeping its size, date and folder (#112).
#[test]
fn a_file_with_a_picture_lit_keeps_its_columns_and_nothing_is_drawn_beside_it() {
    // #196: the picture beside the list is cut; a row with one is a row as any other
    let mut app = manager_app();
    app.sel = 1;
    render(&app, "picture");
}

/// A column is whole or not drawn (#112); with no picture beside the rows (#196), every row keeps its size, its date
/// and its folder.
#[test]
fn rows_with_a_picture_keep_every_column() {
    let mut app = manager_app();
    let (f, uri, _) = app.folder.clone().unwrap();
    let file = |name: &str, size: &str, when: &str, group: &str, folder: Option<&str>| {
        let mut columns = vec![size.to_string(), when.to_string()];
        columns.extend(folder.map(str::to_string));
        json!({"id": format!("files:file:{}:{}", group, name), "sign": "blank", "text": name, "tool": {"name": "files_open", "arguments": {"path": format!("/data/me/{}", name)}, "said": "open"}, "more": [], "columns": columns, "children": null, "group": group})
    };
    let mut cat = file("cat.png", "4.8 MB", "yesterday", "recent", Some("camera"));
    cat["preview"] = json!("/data/me/.cache/thumbs/cat.png");
    let rows = model::rows(&json!({"title": "~", "here": "/data/me", "rows": [
        cat,
        file("memo.txt", "2 KB", "18 Oct", "recent", Some("~")),
        {"id": "files:dir:docs", "sign": "opens", "text": "docs", "tool": null, "more": [], "columns": ["12 items"], "children": "spark-shell://files/rows/ZG9jcw", "group": "home"},
        file("memo.txt", "2 KB", "18 Oct", "home", None),
        file("todo.txt", "1 KB", "2025", "home", None),
        {"id": "files:total", "sign": "blank", "text": "2 files \u{b7} 3 KB", "tool": null, "more": [], "columns": [], "children": null, "group": "this folder"}
    ], "short": []})
    .to_string())
    .unwrap();
    app.folder = Some((f, uri, rows));
    app.sel = 0;
    render(&app, "picture-short");
}

#[test]
fn the_home_folder_is_the_recent_files_the_folders_and_files_and_the_folders_own_steps() {
    let app = manager_app();
    render(&app, "manager");
}

/// Files as v0.113.1 lists your home, in the provider's own shape (the actions once a list, by kind; a row's kind and
/// path): home first with the trash last of it, the recent files below, the drives, then one row for the folder with
/// its actions behind it (#127, #130).
fn files_home() -> App {
    let mut app = base();
    app.cfg.plus = true;
    app.providers.push(provider(
        "files",
        "your home folder",
        json!({"title": "files", "rows": [
        {"id": "files:root:a", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/aG9tZQ", "group": null}
    ], "short": ["files:root:a"]}),
        json!([]),
    ));
    let f = app.providers.len() - 1;
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
    let kinds = json!({"file": {"tool": {"name": "files_open", "said": "open"}, "more": more}, "dir": {"more": steps}});
    let dir = |name: &str, items: &str| json!({"id": format!("files:dir:{}", name), "sign": "opens", "text": name, "columns": [items], "wide": ["folder", items, "", ""], "children": format!("spark-shell://files/rows/{}", name), "group": "home", "kind": "dir", "args": {"path": format!("/data/me/{}", name)}});
    // a wide list's columns as the provider writes them (#141): the kind, the size, the date with the time, the folder
    let file = |name: &str, cols: &[&str], group: &str| {
        let kind = match name.rsplit('.').next() {
            Some("md") => "Markdown",
            Some("txt") => "text",
            Some("pdf") => "PDF",
            Some("jpg") => "picture",
            _ => "file",
        };
        let stamp = if cols[1] == "2025" {
            "04 Mar 2025".to_string()
        } else {
            format!("{} 09:14", cols[1])
        };
        let mut wide = vec![kind.to_string(), cols[0].to_string(), stamp];
        wide.push(cols.get(2).copied().unwrap_or("").to_string());
        json!({"id": format!("files:file:{}:{}", group, name), "sign": "blank", "text": name, "columns": cols, "wide": wide, "group": group, "kind": "file", "args": {"path": format!("/data/me/{}", name)}, "page": format!("spark-shell://files/preview/{}", name)})
    };
    let rows = model::rows(
        &json!({"title": "~", "here": "/data/me", "kinds": kinds, "rows": [
        dir("documents", "12 items"),
        dir("downloads", "3 items"),
        dir("pictures", "40 items"),
        file("notes.md", &["2 KB", "18 Oct"], "home"),
        file("todo.txt", &["1 KB", "2025"], "home"),
        {"id": "files:trash", "sign": "opens", "text": "trash", "columns": ["2 items"], "wide": ["", "2 items", "", ""], "children": "spark-shell://files/rows/trash", "group": "home"},
        file("invoice-0412.pdf", &["120 KB", "today", "downloads"], "recent"),
        file("photo-0412.jpg", &["4.8 MB", "yesterday", "camera"], "recent"),
        file("notes.md", &["2 KB", "18 Oct", "~"], "recent"),
        {"id": "files:drive:s", "sign": "opens", "text": "STICK", "columns": ["14.2 GB free"], "wide": ["", "14.2 GB free", "", ""], "children": "spark-shell://files/rows/c3RpY2s", "group": "drives"},
        {"id": "files:here", "sign": "opens", "text": "this folder \u{b7} 3 folders \u{b7} 2 files \u{b7} 3 KB", "columns": [], "more": [
            {"name": "files_new_folder", "arguments": {"path": "/data/me"}, "ask": ["name"], "said": "new folder"},
            {"name": "files_new_text", "arguments": {"path": "/data/me"}, "ask": ["name"], "said": "new file"},
            {"name": "files_browse", "arguments": {"path": "/data/me"}, "said": "open in the system file manager"}]}
    ], "short": []})
        .to_string(),
    )
    .unwrap();
    app.view = View::Folder(f, "spark-shell://files/rows/aG9tZQ".into());
    app.came_from = vec![View::Home];
    app.folder = Some((f, "spark-shell://files/rows/aG9tZQ".into(), rows));
    app.in_list = true;
    app.sel = 3; // notes.md: a file with a page
    app
}

#[test]
fn files_your_home_starts_with_home_and_ends_with_its_own_row() {
    render(&files_home(), "files-home");
}

#[test]
fn files_a_files_actions_on_f9() {
    // the files' own page (dialog/DESIGN.md): the row's actions, check with its key, then the folder's
    let mut app = files_home();
    app.hint_key(spark_dialog::app::HintKey::Actions);
    assert!(matches!(app.view, View::Folder(..)) && app.files_page_open());
    render(&app, "files-actions");
}

/// The trash, a place (#130): what it holds, the newest first, each with the day and the folder it came from;
/// Enter restores, delete for good behind it; its own row last, empty the trash behind it.
#[test]
fn files_the_trash_is_a_place() {
    let mut app = files_home();
    let (f, _, _) = app.folder.clone().unwrap();
    let trashed = |name: &str, cols: &[&str], from: &str| json!({"id": format!("files:trashed:{}", name), "sign": "blank", "text": name, "columns": cols, "kind": "trashed", "args": {"path": format!("/data/me/{}/{}", from, name)}});
    let rows = model::rows(
        &json!({"title": "trash", "kinds": {"trashed": {"tool": {"name": "files_restore", "said": "restore"}, "more": [{"name": "files_purge", "said": "delete for good"}]}}, "rows": [
        trashed("old notes.txt", &["3 B", "today", "docs"], "docs"),
        trashed("draft-0410.md", &["14 KB", "yesterday", "~"], "."),
        trashed("scan-0402.pdf", &["2.1 MB", "02 Oct", "downloads"], "downloads"),
        {"id": "files:here", "sign": "opens", "text": "the trash \u{b7} 3 items \u{b7} 2.1 MB", "columns": [], "more": [{"name": "files_empty", "arguments": {}, "said": "empty the trash"}]}
    ], "short": []})
        .to_string(),
    )
    .unwrap();
    app.view = View::Folder(f, "spark-shell://files/rows/trash".into());
    app.came_from = vec![View::Home, View::Folder(f, "spark-shell://files/rows/aG9tZQ".into())];
    app.folder = Some((f, "spark-shell://files/rows/trash".into(), rows));
    app.sel = 0;
    render(&app, "files-trash");
}

/// A file with a page of its own lit: Open, Preview, Actions and Back keep to the content's width, the gaps
/// between the keys closing to two cells (#127).
#[test]
fn the_key_row_of_a_file_with_a_page_keeps_to_the_margin() {
    let mut app = manager_app();
    app.folder.as_mut().unwrap().2.rows[0].page = Some("spark-shell://files/preview/aW52b2ljZQ".into());
    render(&app, "manager-preview-key");
}

/// An empty trash in your home says empty, and the sizes of the files beside it keep to their right edge (#130).
#[test]
fn an_empty_trash_keeps_the_sizes_on_their_right_edge() {
    let mut app = manager_app();
    let trash = json!({"id": "files:trash", "sign": "opens", "text": "trash", "tool": null, "more": [], "columns": ["empty"], "children": "spark-shell://files/rows/trash", "group": "home"});
    let one = model::rows(&json!({"title": "~", "rows": [trash], "short": []}).to_string()).unwrap();
    app.folder.as_mut().unwrap().2.rows.insert(8, one.rows[0].clone());
    render(&app, "manager-empty-trash");
}

#[test]
fn right_on_a_file_lists_its_steps_in_the_providers_words() {
    // the provider's steps in its words on the files' actions page, a menu (dialog/DESIGN.md)
    let mut app = manager_app();
    app.hint_key(spark_dialog::app::HintKey::Actions);
    assert!(matches!(app.view, View::Folder(..)) && app.files_page_open());
    app.sel = 7; // trash
    render(&app, "steps");
}

#[test]
fn a_move_picks_its_folder_among_the_folders_with_the_row_that_lands_it_here() {
    let mut app = manager_app();
    app.hint_key(spark_dialog::app::HintKey::Actions);
    app.sel = 5; // move
    app.enter();
    assert!(app.picking.as_ref().is_some_and(|pk| pk.step.is_some()));
    render(&app, "pick");
}

/// The reminders a provider labelled "reminders" offers: a row with no day, then rows for days in groups.
fn reminders() -> Provider {
    let r = |date: &str, sign: &str, text: &str, when: &str, group: &str| json!({"id": format!("r:{}:{}", date, text.len()), "sign": sign, "text": text, "tool": {"name": "reminder_show", "arguments": {}}, "more": [], "columns": [when], "children": null, "group": group, "date": date});
    provider(
        "reminders",
        "2 today, 4 ahead",
        json!({"title": "reminders", "rows": [
            {"id": "r:new", "sign": "opens", "text": "new reminder", "tool": {"name": "reminder_new", "arguments": {}}, "more": [], "columns": [], "children": null, "group": null},
            r("2026-10-18", "dot", "call the dentist", "17:00", "today"),
            r("2026-10-18", "ring", "water the plants", "18:00", "today"),
            r("2026-10-19", "ring", "standup with the team", "09:00", "tomorrow"),
            r("2026-10-23", "ring", "dinner with friends", "Fri 20:00", "this week"),
            r("2026-11-03", "ring", "the vet", "Tue 3 Nov 16:30", "later")
        ], "short": []}),
        json!([]),
    )
}

/// The Calendar, with the reminders provider or without it.
fn calendar_app(with_reminders: bool) -> App {
    let mut app = base();
    if with_reminders {
        app.providers.push(reminders());
    }
    app.providers.push(provider(
        "clock",
        "Sunday 18 October 2026",
        json!({"title": "clock", "rows": [], "short": []}),
        json!([]),
    ));
    app.view = View::Dest(CALENDAR_DEST);
    app.came_from = vec![View::Home];
    app.today = Some((2026, 10, 18));
    app
}

#[test]
fn the_calendar_is_the_months_then_the_reminders() {
    render(&calendar_app(true), "calendar");
}

/// The app drawn in tokyonight-night: the buffer and each row's text.
fn drawn(app: &App) -> (Buffer, spark_dialog::palette::Palette, Vec<String>) {
    let p = palette("tokyonight-night");
    let (w, h) = app.size;
    let mut b = Buffer::empty(Rect::new(0, 0, w, h));
    spark_dialog::ui::draw(app, &p, CLOCK, &mut b);
    let rows = (0..h).map(|y| (0..w).map(|x| b[(x, y)].symbol().to_string()).collect()).collect();
    (b, p, rows)
}

/// The column (in chars) where `needle` starts on a row.
fn at(row: &str, needle: &str) -> Option<usize> {
    row.find(needle).map(|i| row[..i].chars().count())
}

#[test]
fn the_calendar_shows_the_time_in_large_figures() {
    // his word (#41): the calendar screen is missing the clock
    let app = calendar_app(true);
    let (b, p, rows) = drawn(&app);
    let block = "\u{2588}";
    assert!(rows[8..13].iter().all(|r| r.contains(block)), "five rows of figures under the hint");
    assert!(!rows[7].contains(block) && !rows[13].contains(block), "a row of air above and below them");
    assert_eq!(b[(2, 8)].fg, p.accent, "in the accent");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    spark_dialog::ui::draw(&app, &p, "Sun 18 Oct \u{b7} 9:05 PM", &mut b);
    let row = |y: u16| (0..WIDTH).map(|x| b[(x, y)].symbol().to_string()).collect::<String>();
    assert!(
        row(12).trim_end().ends_with("PM"),
        "a twelve-hour clock says PM beside the figures: {}",
        row(12)
    );
    assert_eq!((8..13).filter_map(|y| at(&row(y), block)).min(), Some(2), "a 9 starts at the months' left edge");
}

#[test]
fn the_calendar_draws_this_month_and_the_next_side_by_side() {
    let (_, _, rows) = drawn(&calendar_app(true));
    let y = rows.iter().position(|r| r.starts_with("  October 2026")).expect("this month");
    assert_eq!(y, 14, "under the prompt's block, the hint and the time's five rows of figures");
    assert_eq!(at(&rows[y], "November 2026"), Some(32), "the next month on the same row");
    assert_eq!(at(&rows[y + 1], "Su"), Some(2));
    assert_eq!(rows[y + 1].matches("Su").count(), 2, "a weekday line under each month");
    // November 2026 is five weeks, all of it inside the 60 columns
    assert!(rows[y + 2..y + 7].iter().any(|r| r.trim_end().ends_with("30") && r.chars().count() <= 60));
}

#[test]
fn a_day_with_a_reminder_is_in_the_accent_and_today_is_a_chip() {
    let (b, p, rows) = drawn(&calendar_app(true));
    let y = rows.iter().position(|r| r.starts_with("  October 2026")).unwrap() as u16;
    // October 2026: the 23rd is a Friday of the fourth week, column 2 + 5 * 4
    let (x, wk) = (22u16, y + 2 + 3);
    assert_eq!(format!("{}{}", b[(x, wk)].symbol(), b[(x + 1, wk)].symbol()), "23");
    assert_eq!(b[(x, wk)].fg, p.accent);
    assert!(b[(x, wk)].modifier.contains(ratatui::style::Modifier::BOLD));
    // the 18th, today, has a reminder too: the chip wins
    let wk = y + 2 + 3;
    assert_eq!(format!("{}{}", b[(2, wk)].symbol(), b[(3, wk)].symbol()), "18");
    assert_eq!(b[(2, wk)].bg, p.lit);
    // November's 3rd, the next month's reminder, is marked too: Tuesday, column 32 + 2 * 4
    let x = 32 + 8 + 1;
    assert_eq!(b[(x, y + 2)].symbol(), "3");
    assert_eq!(b[(x, y + 2)].fg, p.accent);
    // a day with none is plain
    assert_eq!(b[(10, wk)].fg, p.fg, "the 20th");
}

#[test]
fn the_reminders_under_the_months_are_rows_to_pick_in_their_groups() {
    let mut app = calendar_app(true);
    // Room for all groups, including the final reminder above the footer gap.
    app.size.1 = 43;
    let (b, p, rows) = drawn(&app);
    let head = |g: &str| {
        rows.iter()
            .position(|r| r.trim_end() == format!("  {}", g))
            .unwrap_or_else(|| panic!("a header {}", g))
    };
    let new = rows.iter().position(|r| r.contains("new reminder")).expect("new reminder, to add one here");
    let (today, tomorrow, week, later) = (head("today"), head("tomorrow"), head("this week"), head("later"));
    assert!(new < today && today < tomorrow && tomorrow < week && week < later, "in their order");
    assert_eq!(b[(2, today as u16)].fg, p.muted);
    assert_eq!(tomorrow, today + 4, "two rows, then a blank row between groups");
    let y = today + 1;
    assert_eq!(at(&rows[y], "call the dentist"), Some(6));
    assert_eq!(rows[y].chars().nth(4), Some('\u{25cf}'), "a dot");
    assert_eq!(b[(4, y as u16)].fg, p.accent);
    // the times line up on their right edge
    let end = |r: &str| r.trim_end().chars().count();
    assert_eq!(end(&rows[y]), end(&rows[later + 1]));
    // and the rows are picked as any list's
    app.in_list = true;
    assert!(app.picks().len() >= 6);
}

#[test]
fn the_calendar_with_no_reminders_is_the_two_months() {
    let (b, p, rows) = drawn(&calendar_app(false));
    let y = rows.iter().position(|r| r.starts_with("  October 2026")).unwrap();
    assert_eq!(at(&rows[y], "November 2026"), Some(32));
    let last = rows.iter().rposition(|r| r.contains("31")).unwrap();
    assert!(rows[last + 1..last + 6].iter().all(|r| r.trim().is_empty()));
    // no day in the accent
    for yy in y as u16..last as u16 + 1 {
        for x in 0..WIDTH {
            assert_ne!(b[(x, yy)].fg, p.accent, "({}, {})", x, yy);
        }
    }
}

#[test]
fn the_wallpaper_section_shows_each_color_as_a_sample() {
    let mut app = base();
    let color = |n: &str, hex: &str| json!({"id": format!("wallpaper:use {}", n), "sign": "blank", "text": n, "tool": {"name": "wallpaper_use", "arguments": {"name": n}}, "more": [], "columns": [], "children": null, "group": "colors", "swatch": hex});
    let shipped = |n: &str, pal: &str, hex: &str| json!({"id": format!("wallpaper:use {}", n), "sign": "blank", "text": n, "tool": {"name": "wallpaper_use", "arguments": {"name": n}}, "more": [], "columns": [pal], "children": null, "group": "wallpapers", "swatch": hex});
    app.providers.push(provider(
        "wallpaper",
        "teal",
        json!({"title": "wallpaper", "rows": [
            {"id": "wallpaper:use default", "sign": "blank", "text": "default", "tool": {"name": "wallpaper_use", "arguments": {"name": "default"}}, "more": [], "columns": [], "children": null, "group": null},
            shipped("fjord", "nord", "#88c0d0"), shipped("sunset", "gruvbox-dark", "#fe8019"), shipped("embers", "any dark palette", "#d24a2a"),
            color("black", "#000000"), color("navy", "#000080"),
            {"id": "wallpaper:show:teal", "sign": "check", "text": "teal", "tool": null, "more": [], "columns": [], "children": null, "group": "colors", "swatch": "#008080"},
            color("orange", "#ffa500"),
            {"id": "wallpaper:pick", "sign": "blank", "text": "a picture", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows", "group": null, "pick": {"tool": "wallpaper_picture", "types": ["jpg", "png"]}}
        ], "short": []}),
        json!([]),
    ));
    app.view = View::Section(app.providers.len() - 1);
    app.came_from = vec![View::Home];
    render(&app, "wallpaper");
}

#[test]
fn a_long_state_in_the_header_stops_short_of_the_date() {
    let mut app = base();
    app.providers[1].title = "catppuccin-latte \u{b7} DejaVu Sans Mono 12 \u{b7} more".into();
    app.view = View::Section(1);
    app.came_from = vec![View::Home];
    let (_, _, rows) = drawn(&app);
    // no clock in the header (v0.124.4): the state is cut at a word before the x, with air before it
    assert!(!rows[0].contains(CLOCK), "the clock is the bar's: {}", rows[0]);
    let at_x = at(&rows[0], "\u{d7}").expect("the x");
    let before: String = rows[0].chars().skip(at_x - 2).take(2).collect();
    assert_eq!(before, "  ", "two cells of air before the x: {}", rows[0]);
    assert!(rows[0].contains("catppuccin-latte"), "the state after the name: {}", rows[0]);
}

#[test]
fn calendar_arrow_chips_click_each_direction_without_changing_focus() {
    use spark_dialog::app::HintKey;
    let mut app = calendar_app(true);
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    let left = drawn.keys.iter().find(|k| k.3 == HintKey::Left).unwrap();
    let right = drawn.keys.iter().find(|k| k.3 == HintKey::Right).unwrap();
    assert_eq!(left.1, right.0);
    assert_eq!(left.2, right.2);
    assert!(left.0 < left.1 && right.0 < right.1);
    let focus = app.in_list;
    app.hint_key(right.3);
    assert_eq!(app.month_offset, 1);
    app.hint_key(left.3);
    assert_eq!(app.month_offset, 0);
    assert_eq!(app.in_list, focus);
}

#[test]
fn key_chips_preserve_the_typed_confirmation_for_destructive_actions() {
    use spark_dialog::app::HintKey;
    let mut app = base();
    app.mode = Mode::Confirm(Step {
        prov: 0,
        call: model::Call {
            name: "window_close".into(),
            arguments: json!({"name":"terminal"}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: None,
            value: None,
            children: None,
        },
        who: Who::Person,
        line: "close terminal".into(),
        typed: false,
    });
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    assert!(drawn.keys.iter().all(|k| k.3 == HintKey::Escape));
    // the question's page (dialog/DESIGN.md, v0.127): keep working, as Esc, keeps; only the verb's row is the yes
    app.in_list = true;
    app.sel = 1;
    app.hint_key(HintKey::Enter);
    assert!(matches!(app.mode, Mode::Normal));
    assert!(app.running.is_none() && app.queue.is_empty(), "keep working keeps the window");
    assert!(app.jobs.is_empty(), "keep never runs the step");
}

/// A preview (#120): `name` lit in a folder of three files, its page as its provider answers it.
fn preview_app(name: &str, place: &str, page: serde_json::Value, w: u16, h: u16) -> App {
    let mut app = manager_app();
    app.size = (w, h);
    let f = app.folder.as_ref().unwrap().0;
    let file = |n: &str| json!({"id": format!("files:file:{}", n), "sign": "blank", "text": n, "tool": {"name": "files_open", "arguments": {"path": format!("/data/me/{}", n)}, "said": "open"}, "more": [], "columns": [], "children": null, "group": "home", "page": format!("spark-shell://files/preview/{}", n)});
    let rows = model::rows(&json!({"title": place, "rows": [file("before.txt"), file(name), file("after.txt")]}).to_string()).unwrap();
    let mut pv = spark_dialog::preview::Preview::new(f, place, &rows.rows, &format!("files:file:{}", name)).unwrap();
    pv.shown = spark_dialog::preview::page(&pv.uri(), &page.to_string());
    assert!(pv.shown.is_some(), "the page is read");
    app.preview = Some(pv);
    app.came_from.push(app.view.clone());
    app.view = View::Preview;
    app.in_list = false;
    app
}

fn note() -> serde_json::Value {
    let text = "# Week of 2 November\n\nThe report goes out on Friday. Ada reviews the numbers on Thursday morning, and the charts follow the same afternoon.\n\n## To do\n\n- send the draft to Ada\n- book the room for Thursday\n- check the third quarter against last year\n\n## Notes\n\nThe new printer is on the second floor. Its queue is called office-2.";
    let lines: Vec<&str> = text.lines().collect();
    let bold: Vec<usize> = lines.iter().enumerate().filter(|(_, l)| l.starts_with('#')).map(|(i, _)| i).collect();
    let shown: Vec<String> = lines.iter().map(|l| l.trim_start_matches('#').trim_start().to_string()).collect();
    json!({"title": "plan.md", "facts": ["412 B", "today"], "lines": shown, "bold": bold, "attach": "/run/pages/1.txt"})
}

#[test]
fn a_preview_shows_a_text_read_only_its_headings_bold() {
    render(&preview_app("plan.md", "~/notes", note(), WIDTH, HEIGHT), "preview-text");
}

#[test]
fn a_preview_at_full_screen_pages_code_with_its_lines_numbered() {
    let code: Vec<String> = (1..=70)
        .map(|i| match i % 7 {
            1 => format!("fn step_{}(app: &mut App) -> bool {{", i),
            2 => "    let Some(pv) = app.preview.as_mut() else { return false };".to_string(),
            3 => "    // the page before or after; a picture's page is asked for, a text's is drawn".to_string(),
            4 => "    pv.step_page(1, app.preview_pages)".to_string(),
            5 => "}".to_string(),
            _ => String::new(),
        })
        .collect();
    let page = json!({"title": "preview.rs", "facts": ["6 KB", "today"], "lines": code, "numbered": true, "attach": "/run/pages/2.txt"});
    render_at(&preview_app("preview.rs", "~/projects/dialog/src", page, 120, 50), "preview-code-full", 120, 50);
}

#[test]
fn a_pdf_is_its_page_drawn_and_page_n_of_m() {
    let page = json!({"title": "invoice-0412.pdf", "facts": ["14 pages", "412 KB", "today"], "picture": "/run/pages/3-3.png", "page": 3, "pages": 14, "attach": "/run/pages/3-3.txt"});
    render(&preview_app("invoice-0412.pdf", "~/downloads", page, WIDTH, HEIGHT), "preview-pdf");
}

/// A sound's picture as mpv draws it: a waveform 16 rows tall (loud on the beat), then a spectrogram
/// of 32 rows (bright low, dark high), 64 columns.
fn sound_png() -> Vec<u8> {
    let (w, wave, spec) = (64u32, 16u32, 32u32);
    let mut px = vec![];
    for y in 0..wave + spec {
        for x in 0..w {
            let on = if y < wave {
                let reach = if x % 8 == 0 { 8 } else { 2 + (x % 8) / 3 };
                (y as i32 - 8).unsigned_abs() < reach
            } else {
                (y - wave) * 2 > spec - (x % 16) && (x / 4) % 2 == 0
            };
            let v = if on { 230 } else { 20 };
            px.extend([v, v, v, 255]);
        }
    }
    let mut raw = Vec::new();
    {
        let mut e = png::Encoder::new(&mut raw, w, wave + spec);
        e.set_color(png::ColorType::Rgba);
        e.set_depth(png::BitDepth::Eight);
        e.write_header().unwrap().write_image_data(&px).unwrap();
    }
    raw
}

fn sound_app(playing: bool) -> App {
    let page = json!({"title": "evening-sketch.flac", "facts": ["44.1 kHz", "16 bit", "stereo", "FLAC", "866 KB", "today"],
        "lines": ["Evening sketch", "Ada \u{b7} Proofs"], "bold": [0], "seconds": 20.0, "sound": {"picture": "/run/pages/7-sound.png", "wave": 16},
        "play": {"name": "files_play", "arguments": {"path": "/data/me/evening-sketch.flac"}, "said": "play"}, "stop": {"name": "files_stop", "arguments": {}, "said": "stop"}});
    let mut app = preview_app("evening-sketch.flac", "~/music", page, WIDTH, HEIGHT);
    let pv = app.preview.as_mut().unwrap();
    pv.heard = spark_dialog::preview::sound(&spark_dialog::sixel::decode(&sound_png()).unwrap(), 16);
    pv.played = 7.0;
    if playing {
        pv.playing = Some(std::time::Instant::now() + std::time::Duration::from_secs(3600));
    }
    app
}

/// Stopped at 0:07 of 0:20: the waveform played to there in the accent, the whole sound's spectrum,
/// the spectrogram's picture under them, what an audio engineer asks first in the facts.
#[test]
fn a_sound_is_its_waveform_its_spectrum_and_its_spectrogram() {
    render(&sound_app(false), "preview-sound");
}

/// A long sound whose waveform is still being drawn aside (#124): its facts, its tags, its length, the words
/// that say the picture comes; Play works meanwhile.
#[test]
fn a_long_sound_says_its_waveform_is_being_drawn() {
    let mut app = sound_app(false);
    app.preview.as_mut().unwrap().heard = None;
    render(&app, "preview-sound-drawing");
}

/// The wait plays while a page is slow to come, and ends when it did not come (#124): never under the words.
#[test]
fn a_page_that_did_not_come_ends_the_wait() {
    let mut app = sound_app(false);
    app.films = true;
    let pv = app.preview.as_mut().unwrap();
    pv.shown = None;
    pv.asked = std::time::Instant::now() - std::time::Duration::from_secs(2);
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    assert!(spark_dialog::ui::draw(&app, &p, CLOCK, &mut b).film.is_some(), "a slow page: the wait");
    app.preview.as_mut().unwrap().failed = true;
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    assert!(
        spark_dialog::ui::draw(&app, &p, CLOCK, &mut b).film.is_none(),
        "a page that did not come: no wait"
    );
}

/// A video plays over the frame where it was drawn (#125): Space sends the box with the play (#151).
#[test]
fn a_video_sends_the_box_of_its_frame_with_its_play() {
    let page = json!({"title": "clip.webm", "facts": ["0:05", "1280 \u{d7} 720"], "picture": "/run/pages/9-1600.png", "size": [1280, 720], "full": true, "seconds": 5.0,
        "play": {"name": "files_play", "arguments": {"path": "/data/me/clip.webm"}, "said": "play"}, "stop": {"name": "files_stop", "arguments": {}, "said": "stop"}});
    let mut app = preview_app("clip.webm", "~/videos", page, WIDTH, HEIGHT);
    app.preview.as_mut().unwrap().frame = Some((20, 200, 640, 360));
    app.typed(' ');
    let pv = app.preview.as_ref().unwrap();
    assert!(pv.playing.is_some(), "Space plays it, a player's key (#151)");
    app.right();
    let pv = app.preview.as_ref().unwrap();
    assert!(pv.playing.is_some() && pv.played >= 4.9, "Right goes 5 s ahead and plays on: {}", pv.played);
    app.stop_video();
    assert!(app.preview.as_ref().unwrap().playing.is_none(), "a click, a new size: the player stops");
}

#[test]
fn a_zoomed_picture_moves_with_the_arrows_and_fits_with_esc() {
    let page =
        json!({"title": "dunes.png", "facts": ["2400 \u{d7} 1350", "48 KB", "today"], "picture": "/run/pages/4-1600.png", "size": [2400, 1350], "full": false});
    let mut app = preview_app("dunes.png", "~/pictures", page, WIDTH, HEIGHT);
    let pv = app.preview.as_mut().unwrap();
    (pv.src, pv.px) = ((1600, 900), (616, 594));
    app.typed('>');
    app.typed('+');
    app.typed('+');
    let pv = app.preview.as_ref().unwrap();
    assert_eq!((pv.turn, pv.zoom, pv.full), (1, Some(50), false), "fitted at 25 %, two stops in");
    render(&app, "preview-zoom");
    app.escape();
    assert!(
        app.view == View::Preview && app.preview.as_ref().unwrap().zoom.is_none(),
        "Esc fits it, and the preview stays"
    );
}

#[test]
fn a_file_with_no_preview_says_why_in_the_middle() {
    let page = json!({"title": "backup.tar.zst", "facts": ["1.2 GB", "18 Oct"], "say": "this kind of file cannot be viewed: Enter opens it"});
    render(&preview_app("backup.tar.zst", "~", page, WIDTH, HEIGHT), "preview-none");
}

#[test]
fn a_conversation_preserves_the_preview_without_attaching_it() {
    let mut app = preview_app("plan.md", "~/notes", note(), WIDTH, HEIGHT);
    app.cfg.spark = "/bin/false".into();
    app.model_name = Some("fixture".into());
    app.set_draft("when is the report due?");
    app.ask();
    assert_eq!(app.view, View::Conversation);
    assert_eq!(app.pending.as_ref().unwrap().1, None, "preview is not an attachment");
    assert!(app.jobs.iter().any(|j| matches!(j, spark_dialog::app::Job::RunInput(..))));
    app.pending = None;
    app.wait = None;
    app.say(Sign::You, "when is the report due?");
    app.say(Sign::Says, "\"The report goes out on Friday.\"");
    render(&app, "preview-answer");
    app.conversation();
    assert_eq!(app.view, View::Preview);
    assert_eq!(app.preview.as_ref().unwrap().row().text, "plan.md");
}

#[test]
fn space_opens_the_lit_files_preview_and_esc_lights_it_again() {
    let mut app = manager_app();
    // notes.md, the third row, lit; Space with nothing typed opens its preview
    let (f, uri, mut rows) = app.folder.clone().unwrap();
    for r in rows.rows.iter_mut().filter(|r| r.tool.as_ref().is_some_and(|t| t.name == "files_open")) {
        r.page = Some(format!("spark-shell://files/preview/{}", r.id));
    }
    app.folder = Some((f, uri, rows));
    app.in_list = true;
    app.sel = 2;
    app.hint_key(spark_dialog::app::HintKey::View);
    assert_eq!(app.view, View::Preview);
    assert_eq!(app.preview.as_ref().unwrap().row().text, "notes.md");
    assert!(app.input.is_empty(), "F3 opened the preview and typed nothing");
    // up and down move through the list's files
    app.down();
    assert_eq!(
        app.preview.as_ref().unwrap().row().text,
        "notes.md",
        "the home folder's notes.md, after recent's"
    );
    app.up();
    app.up();
    assert_eq!(app.preview.as_ref().unwrap().row().text, "photo-0412.jpg");
    // Esc goes back with that file lit
    app.escape();
    assert!(matches!(app.view, View::Folder(..)) && app.preview.is_none() && app.in_list);
    assert_eq!(
        app.picks().get(app.sel).and_then(|it| match it {
            spark_dialog::app::Item::Folder(i) => app.folder.as_ref().map(|(_, _, r)| r.rows[*i].text.clone()),
            _ => None,
        }),
        Some("photo-0412.jpg".to_string())
    );
    // words typed: Space is a space
    app.typed('a');
    app.typed(' ');
    assert_eq!(app.input, "a ");
}

// ---- full screen (#141): one flow, the dialog's column as wide as a list wants (FULL_WIDTH at most) in the middle,
// nothing beside or under it

/// A wide screen (a 1920 by 1080 monitor at the dialog's text size) and a tall one (the same turned).
const WIDE: (u16, u16) = (150, 46);
const TALL: (u16, u16) = (90, 80);

fn sized(mut app: App, (w, h): (u16, u16)) -> App {
    app.size = (w, h);
    app
}

#[test]
fn full_screen_home_is_one_column_in_the_middle_its_words_whole() {
    let mut app = sized(full(), WIDE);
    app.in_list = true;
    app.sel = app.picks().iter().position(|i| matches!(i, spark_dialog::app::Item::Dest(2))).unwrap(); // Workspace
    let drawn = render_at(&app, "full-home", WIDE.0, WIDE.1);
    assert_eq!(drawn.columns, (45, 105), "home keeps its 60-cell measure in the middle");
}

#[test]
fn full_screen_settings_write_each_state_whole() {
    let mut app = sized(full(), WIDE);
    app.view = View::Dest(SETTINGS_DEST);
    app.came_from = vec![View::Home];
    app.in_list = true;
    app.sel = app
        .picks()
        .iter()
        .position(|i| matches!(i, spark_dialog::app::Item::Setting(k) if spark_dialog::app::SETTINGS[*k].0 == "bt"))
        .unwrap();
    render_at(&app, "full-settings", WIDE.0, WIDE.1);
}

#[test]
fn full_screen_files_list_whole_names_with_the_kind_the_size_and_the_time() {
    let mut app = sized(files_home(), WIDE);
    let long = model::rows(&json!({"title": "~", "rows": [{"id": "files:file:home:q", "sign": "blank", "text": "quarterly-report-for-the-board-final-v3.pdf", "columns": ["4.5 MB", "today"], "wide": ["PDF", "4.5 MB", "today 21:02", ""], "group": "home", "page": "spark-shell://files/preview/q"}], "short": []}).to_string()).unwrap();
    let rows = &mut app.folder.as_mut().unwrap().2.rows;
    let at = rows.iter().position(|r| r.text == "todo.txt").unwrap();
    rows.insert(at, long.rows[0].clone());
    render_at(&app, "full-files", WIDE.0, WIDE.1);
    let mut b = Buffer::empty(Rect::new(0, 0, WIDE.0, WIDE.1));
    spark_dialog::ui::draw(&app, &palette("tokyonight-night"), CLOCK, &mut b);
    let text: String = (0..WIDE.1)
        .flat_map(|y| (0..WIDE.0).map(move |x| (x, y)))
        .map(|(x, y)| b[(x, y)].symbol().to_string())
        .collect();
    assert!(text.contains("quarterly-report-for-the-board-final-v3.pdf"), "the name whole");
    assert!(
        text.contains("Markdown") && text.contains("18 Oct 09:14"),
        "the kind, and the date with the time"
    );
}

#[test]
fn full_screen_calendar_shows_more_months_across() {
    let app = sized(calendar_app(true), TALL);
    render_at(&app, "full-calendar-tall", TALL.0, TALL.1);
}

#[test]
fn full_screen_home_on_a_tall_screen_keeps_the_column_in_the_middle() {
    let mut app = sized(full(), TALL);
    app.in_list = true;
    app.sel = app.picks().iter().position(|i| matches!(i, spark_dialog::app::Item::Dest(2))).unwrap();
    render_at(&app, "full-home-tall", TALL.0, TALL.1);
}

// ---- v0.114.1

/// The opening plays alone (#142): nothing but its box is drawn, no cursor, the whole dialog after it.
#[test]
fn the_opening_plays_alone_then_the_whole_dialog() {
    let mut app = full();
    app.motion = Some((spark_dialog::transition::Reel::Open, std::time::Instant::now()));
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    assert!(drawn.alone && drawn.film.is_some(), "the opening alone");
    let text: String = (0..HEIGHT)
        .flat_map(|y| (0..WIDTH).map(move |x| (x, y)))
        .map(|(x, y)| b[(x, y)].symbol().to_string())
        .collect();
    assert!(text.trim().is_empty(), "nothing else drawn: {:?}", text.trim());
    app.motion = None;
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    assert!(!drawn.alone && drawn.film.is_none(), "after it, the dialog whole");
}

/// Back is the header's left where there is a level above (dialog/DESIGN.md, v0.124.4), the place's name
/// centered after it, and the key row still says Back with its key.
#[test]
fn back_is_in_the_header_and_in_the_key_row() {
    let app = manager_app();
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    let head: String = (0..WIDTH).map(|x| b[(x, 0)].symbol().to_string()).collect();
    assert!(head.starts_with("  \u{2039} back"), "the header starts with back: {:?}", head);
    assert_eq!(drawn.back.map(|(a, _)| a), Some(2));
    assert!(head.contains("files"), "then the place: {:?}", head);
    let hint: String = app.hint().iter().map(|(t, _)| t.as_str()).collect();
    assert!(hint.contains("Back Esc"), "the key row says Back: {:?}", hint);
}

/// A typed filter lights a file (#163): the key row says the down arrow leads to its preview; Down keeps the
/// file lit and hands the keys to the list, the row says Preview with Space, and Space shows it, the words gone.
/// Before Down, Space is a space: a second word, or a request to spark.
#[test]
fn a_filtered_file_shows_its_preview_after_the_down_arrow() {
    let filtered = || {
        let mut app = manager_app();
        app.folder.as_mut().unwrap().2.rows[0].page = Some("spark-shell://files/preview/aW52b2ljZQ".into());
        app.in_list = false;
        for c in "invo".chars() {
            app.typed(c);
        }
        app
    };
    let hint = |app: &App| app.hint().iter().map(|(t, _)| t.as_str()).collect::<String>();
    let mut app = filtered();
    assert!(
        hint(&app).contains("View F3"),
        "the way to the preview is said, the same words as always: {:?}",
        hint(&app)
    );
    app.typed(' ');
    assert_eq!(app.input, "invo ", "Space before Down is a space");
    let mut app = filtered();
    app.down();
    assert!(hint(&app).contains("View F3"), "Down: the keys are the list's: {:?}", hint(&app));
    app.hint_key(spark_dialog::app::HintKey::View);
    assert_eq!(app.view, View::Preview, "F3 shows the lit file");
    assert!(app.input.is_empty(), "the filter's words let go, so Space plays and Esc goes back");
    assert_eq!(app.preview.as_ref().unwrap().row().text, "invoice-0412.pdf");
}

/// A long sound whose waveform is still being drawn (#164): the animation that began while the page came plays
/// on under the title, no words over it, until the picture is there.
#[test]
fn a_long_sound_plays_the_wait_until_its_waveform_is_there() {
    let mut app = sound_app(false);
    app.films = true;
    app.preview.as_mut().unwrap().heard = None;
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    assert!(drawn.film.is_some(), "the wait plays");
    let all: String = (0..HEIGHT)
        .flat_map(|y| (0..WIDTH).map(move |x| (x, y)))
        .map(|c| b[c].symbol().to_string())
        .collect();
    assert!(!all.contains("drawing the waveform"), "no words over the animation");
    assert!(all.contains("Evening sketch"), "the title stays above it");
}

/// The preview's chip takes a click as the other chips do (#150): it sends P (v0.125.1).
#[test]
fn the_space_chip_is_a_key_a_click_takes() {
    let mut app = manager_app();
    // Secondary preview hints follow navigation, Ask and the row's primary
    // action; the wider column has room for the complete group.
    app.size = (120, 40);
    app.folder.as_mut().unwrap().2.rows[0].page = Some("spark-shell://files/preview/aW52b2ljZQ".into());
    let p = palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, 120, 40));
    let drawn = spark_dialog::ui::draw(&app, &p, CLOCK, &mut b);
    assert!(
        drawn.keys.iter().any(|(_, _, _, k)| *k == spark_dialog::app::HintKey::View),
        "the preview chip is clickable and sends F3: {:?}",
        drawn.keys
    );
}

/// A sound's keys are a player's (#151): Space plays and pauses, the arrows go 5 s back and ahead, Home to the start.
#[test]
fn a_sounds_keys_are_a_players() {
    let mut app = sound_app(false);
    app.typed(' ');
    assert!(app.preview.as_ref().unwrap().playing.is_some(), "Space plays");
    app.typed(' ');
    let pv = app.preview.as_ref().unwrap();
    assert!(
        pv.playing.is_none() && (pv.played - 7.0).abs() < 0.5,
        "Space pauses where it was: {}",
        pv.played
    );
    app.right();
    assert!((app.preview.as_ref().unwrap().played - 12.0).abs() < 0.5, "Right: 5 s ahead");
    app.left();
    app.left();
    assert!((app.preview.as_ref().unwrap().played - 2.0).abs() < 0.5, "Left twice: 10 s back");
    app.line_start();
    assert_eq!(app.preview.as_ref().unwrap().played, 0.0, "Home: the start");
    assert_eq!(app.view, View::Preview, "and Space never left the preview");
    let hint: Vec<String> = app.hint().into_iter().map(|(t, _)| t).collect();
    // the shared keys first, then the player's (#166); in a 60-cell window Seek is past the edge, its keys still work
    assert_eq!(hint[..3].concat(), "Back Esc   ", "{:?}", hint);
    assert!(hint.iter().any(|t| t.trim_end() == "Play"), "{:?}", hint);
}

/// Connections says once what is true of all its tools, by Settings' names; a tool that stopped has a row (#146).
#[test]
fn connections_say_the_tools_once() {
    let mut app = full();
    app.providers[2].dead = Some("its provider exited".into());
    app.view = View::Connections;
    app.came_from = vec![View::Home];
    let texts: Vec<String> = app
        .items()
        .into_iter()
        .filter_map(|i| match i {
            spark_dialog::app::Item::Text(t, _) => Some(t),
            _ => None,
        })
        .collect();
    let n: usize = app.providers.iter().filter(|p| p.dead.is_none()).map(|p| p.tools.len()).sum();
    assert_eq!(
        texts[0],
        format!("{} tools \u{b7} this computer, from spark-shell", n),
        "the tools counted, not the sections"
    );
    assert!(
        texts.iter().any(|t| t.contains("windows") && t.contains("theme")),
        "Settings' names: {:?}",
        texts
    );
    assert!(texts.iter().any(|t| t.ends_with("stopped: its provider exited")), "{:?}", texts);
}

/// A row's key is drawn as a chip beside it (#144); a key that is no key's shape is not read.
#[test]
fn a_rows_key_is_a_chip() {
    let rows = model::rows(&json!({"title": "window", "rows": [
        {"id": "window:capture screen", "sign": "opens", "text": "capture the screen", "tool": {"name": "window_capture", "arguments": {"what": "screen"}}, "more": [], "columns": [], "children": null, "key": "Print"},
        {"id": "window:capture area", "sign": "opens", "text": "capture an area", "tool": {"name": "window_capture", "arguments": {"what": "area"}}, "more": [], "columns": [], "children": null, "key": "Shift+Print; rm"}
    ], "short": []}).to_string()).unwrap();
    assert_eq!(rows.rows[0].key.as_deref(), Some("Print"));
    assert_eq!(rows.rows[1].key, None, "not a key's shape");
}

/// A click lights its row and the light kept from a preview lets go (#153).
#[test]
fn a_click_lights_its_row_and_the_kept_light_lets_go() {
    let mut app = manager_app();
    let id = app.folder.as_ref().unwrap().2.rows[1].id.clone();
    app.keep_lit = Some(id);
    app.sel = 1;
    app.light(0);
    assert!(app.keep_lit.is_none() && app.sel == 0 && app.in_list, "the click's row, the kept light gone");
}

/// A receipt has one place, the reply row (#154, #196): the home shows no Undo of its own; typed undo still works.
#[test]
fn the_home_has_no_second_undo() {
    let mut app = full();
    app.view = View::Home;
    app.undo = Some(Step {
        prov: 0,
        call: model::Call {
            name: "theme_set".into(),
            arguments: json!({"name": "dracula"}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: None,
            value: None,
            children: None,
        },
        who: Who::Undo,
        line: "undo the theme".into(),
        typed: false,
    });
    app.reply = None;
    let undo = app
        .items()
        .iter()
        .any(|i| matches!(i, spark_dialog::app::Item::Said(_, t, _) if t.contains("Undo")));
    assert!(!undo, "no Undo row on the home");
    assert!(app.undo.is_some(), "the undo is still at hand for typed undo");
}

/// The key row holds still (#166): Back, File and Open in the same places on a sound and on a picture, the
/// file's own keys after them; moving to the next file keeps the row as it was until that file's page is there.
#[test]
fn the_previews_keys_hold_their_places_between_files() {
    let row = |app: &App| app.hint().into_iter().map(|(t, _)| t).collect::<Vec<String>>();
    let sound = sound_app(false);
    let picture = json!({"title": "photo.jpg", "facts": ["4032 \u{d7} 3024", "951 KB"], "picture": "/run/pages/3-1600.png", "size": [4032, 3024]});
    let picture = preview_app("photo.jpg", "~/pictures", picture, WIDTH, HEIGHT);
    let (s, p) = (row(&sound), row(&picture));
    assert_eq!(s[..8], p[..8], "Back, File and Open the same on both: {:?} {:?}", s, p);
    assert_eq!(s[..8].concat(), "Back Esc   File \u{2191} \u{2193}   Open Enter");
    let mut app = sound_app(false);
    app.down();
    assert!(app.preview.as_ref().unwrap().shown.is_none(), "the next file's page is on its way");
    assert_eq!(row(&app), s, "the row as it was, no blink while it loads");
}

/// Apps with a catalog read: eight apps in five categories, two helpers hidden, Firefox's facts in.
fn apps_app() -> App {
    let mut app = base();
    app.view = View::Apps;
    app.came_from.push(View::Home);
    app.apps.prefs = spark_dialog::apps::preferences::Preferences::default();
    app.apps.preference_error = None;
    app.apps.path = std::env::temp_dir().join("spark-dialog-render-apps.json");
    app.apps.pending = Some((1, "catalog".into()));
    app.apps
        .receive(
            1,
            json!({"apps": [
                {"id": "btop.desktop", "name": "btop++", "generic_name": "System Monitor", "categories": ["System"]},
                {"id": "foot.desktop", "name": "foot", "generic_name": "Terminal", "categories": ["System"]},
                {"id": "footclient.desktop", "name": "foot client", "generic_name": "Terminal", "categories": ["System"]},
                {"id": "foot-server.desktop", "name": "foot server", "generic_name": "Terminal", "categories": ["System"]},
                {"id": "org.mozilla.firefox.desktop", "name": "Firefox", "generic_name": "Web Browser", "description": "Browse the World Wide Web", "categories": ["Network"], "focus": true, "launcher": "/usr/share/applications/org.mozilla.firefox.desktop"},
                {"id": "chromium.desktop", "name": "Chromium", "generic_name": "Web Browser", "categories": ["Network"]},
                {"id": "aerc.desktop", "name": "aerc", "generic_name": "Mail Client", "categories": ["Office"]},
                {"id": "mpv.desktop", "name": "mpv Media Player", "generic_name": "Multimedia player", "categories": ["AudioVideo"]},
                {"id": "micro.desktop", "name": "micro", "generic_name": "Text Editor", "categories": ["Utility"]}
            ]}),
        )
        .unwrap();
    app.apps.details.insert(
        "org.mozilla.firefox.desktop".into(),
        json!({"id": "org.mozilla.firefox.desktop", "version": "128.0", "installed": "XBPS / System", "source": "XBPS",
               "fields": [["Launcher", "/usr/share/applications/org.mozilla.firefox.desktop"]]}),
    );
    app
}

#[test]
fn apps_is_the_list_under_its_categories_then_the_managing_rows() {
    let mut app = apps_app();
    app.light(3); // Firefox
    render(&app, "apps");
}

#[test]
fn an_apps_details_are_its_facts_its_steps_and_its_preferences() {
    let mut app = apps_app();
    app.apps_activate(spark_dialog::apps::Action::Details("org.mozilla.firefox.desktop".into()));
    app.apps.pending = None; // the facts are in: nothing on its way
    app.light(2); // the switch
    render(&app, "apps-details");
}

/// The power place (dialog/DESIGN.md, v0.127): five verbs, one word each, what each does as its column, the
/// uptime a fact under them, the section's state the uptime.
#[test]
fn power_is_five_verbs_and_the_uptime() {
    let cfg = Config {
        model: true,
        talk: true,
        close: true,
        ..Config::default()
    };
    let mut app = App::new(cfg, &["power".into()]);
    let mut p = provider(
        "power",
        "up 3 days",
        json!({"title": "power", "rows": [
            {"id": "power:lock", "sign": "blank", "text": "lock", "tool": {"name": "power_lock", "arguments": {}}, "more": [], "columns": [], "wide": ["the screen \u{b7} Super+Escape"], "children": null, "group": null},
            {"id": "power:suspend", "sign": "blank", "text": "suspend", "tool": {"name": "power_suspend", "arguments": {}}, "more": [], "columns": [], "wide": ["the screen locks first"], "children": null, "group": null},
            {"id": "power:logout", "sign": "blank", "text": "logout", "tool": {"name": "power_logout", "arguments": {}}, "more": [], "columns": [], "wide": ["every window closes"], "children": null, "group": null},
            {"id": "power:restart", "sign": "blank", "text": "restart", "tool": {"name": "power_restart", "arguments": {}}, "more": [], "columns": [], "wide": ["asks first"], "children": null, "group": null},
            {"id": "power:shutdown", "sign": "blank", "text": "shutdown", "tool": {"name": "power_shutdown", "arguments": {}}, "more": [], "columns": [], "wide": ["asks first"], "children": null, "group": null},
            {"id": "power:up", "sign": "blank", "text": "up 3 days", "tool": null, "more": [], "columns": [], "children": null, "group": null}
        ], "short": []}),
        json!([
            {"name": "power_lock", "title": "power lock", "description": "Lock the screen.", "inputSchema": {"type": "object", "properties": {}}, "annotations": {"destructiveHint": false}},
            {"name": "power_suspend", "title": "power suspend", "description": "Lock the screen and suspend the machine.", "inputSchema": {"type": "object", "properties": {}}, "annotations": {"destructiveHint": false}},
            {"name": "power_logout", "title": "power logout", "description": "Log out. Every window closes and the session ends.", "inputSchema": {"type": "object", "properties": {}}},
            {"name": "power_restart", "title": "power restart", "description": "Restart the machine. Everything open closes and it starts again.", "inputSchema": {"type": "object", "properties": {}}},
            {"name": "power_shutdown", "title": "power shutdown", "description": "Shut the machine down. Everything open closes and the machine turns off.", "inputSchema": {"type": "object", "properties": {}}}
        ]),
    );
    p.version = "v0.126".into();
    app.providers = vec![p];
    app.model_name = Some("gemma4-26b-a4b".into());
    app.voice_on = true;
    app.came_from.push(View::Home);
    app.view = View::Section(0);
    app.in_list = true;
    app.sel = 0;
    // the row one word; what it does is the status row's line while it is lit; the uptime a fact apart
    assert_eq!(app.selected_line().as_deref(), Some("lock \u{b7} the screen \u{b7} Super+Escape"));
    render(&app, "power");
    app.sel = 1;
    assert_eq!(app.selected_line().as_deref(), Some("suspend \u{b7} the screen locks first"));
    // shutdown asks: the question's page, its note the description's last sentence
    app.sel = 4;
    app.enter();
    assert!(matches!(app.mode, Mode::Confirm(_)), "{:?}", app.mode);
    let items = app.items();
    let note = items.iter().find_map(|it| match it {
        Item::Text(t, _) => Some(t.trim().to_string()),
        _ => None,
    });
    assert_eq!(note.as_deref(), Some("(everything open closes and the machine turns off)"));
    render(&app, "power-question");
    // keep working: the bar back on shutdown, where it was asked from, not on the question's second row (v0.129)
    app.escape();
    assert!(matches!(app.mode, Mode::Normal), "{:?}", app.mode);
    assert_eq!((app.sel, app.in_list), (4, true), "back on shutdown");
}

#[test]
fn home_and_end_with_nothing_typed_take_the_list_on_a_page_just_opened() {
    // help opens with the prompt's line empty and nothing lit: End went to the end of that empty line, so it moved
    // nothing; with nothing typed, End is the list's last row and Home its first (v0.129.2)
    let mut app = base();
    app.view = View::Help;
    app.came_from = vec![View::Home];
    app.in_list = false;
    app.sel = 0;
    app.line_end();
    let last = app.picks().len() - 1;
    assert_eq!((app.in_list, app.sel), (true, last), "End: the last row");
    app.line_start();
    assert_eq!((app.in_list, app.sel), (true, 0), "Home: the first row");
    // words typed: Home and End are the line's, as before
    app.in_list = false;
    app.input = "window".into();
    app.cursor = 0;
    app.line_end();
    assert_eq!((app.in_list, app.cursor), (false, 6), "End with words: the line's end");
    app.line_start();
    assert_eq!((app.in_list, app.cursor), (false, 0), "Home with words: the line's start");
}
