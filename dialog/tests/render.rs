// The golden renders: the dialog drawn from fixed state in the two
// palettes the records name. Both palettes give the same grid of slots
// (every colour bound to a token), and the grid is the file in golden/.
// UPDATE_GOLDEN=1 writes the files after a change that was looked at.
mod common;
use common::palette;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use serde_json::json;
use spark_dialog::app::{App, Config, Line, Mode, Provider, Sign, Step, View, Who, HEIGHT, WIDTH};
use spark_dialog::model;

const CLOCK: &str = "Sunday 18 October \u{b7} 12:04";

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
            row("window:focus terminal", "opens", "terminal", Some(("window_focus", json!({"name": "terminal"}))), Some("open now")),
            row("window:close terminal", "blank", "close terminal", Some(("window_close", json!({"name": "terminal"}))), Some("open now")),
            row("window:focus firefox", "opens", "firefox", Some(("window_focus", json!({"name": "firefox"}))), Some("open now")),
            row("window:close firefox", "blank", "close firefox", Some(("window_close", json!({"name": "firefox"}))), Some("open now")),
            row("window:show:side by side", "check", "side by side", None, Some("layout")),
            row("window:tabs", "ring", "tabs", Some(("window_tabs", json!({}))), Some("layout")),
            row("window:stacked", "ring", "stacked", Some(("window_stacked", json!({}))), Some("layout"))
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
    let mut about = provider("about", "a light desktop of sway and foot, for an AI box", about_rows, json!([]));
    about.version = "0.64".into();
    app.providers = vec![window, theme, bt, about];
    app.about_idx = Some(3);
    app.model_name = Some("gemma4-26b-a4b".into());
    app.voice_on = true;
    app
}

fn render(app: &App, name: &str) {
    let mut grids = vec![];
    for pal in ["tokyonight-night", "solarized-light"] {
        let p = palette(pal);
        let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
        spark_dialog::ui::draw(app, &p, CLOCK, &mut b);
        if let Ok(dir) = std::env::var("RENDER_HTML") {
            let page = format!("<!doctype html><meta charset=utf-8><body style=\"margin:0;padding:28px;background:#111;font:16px 'DejaVu Sans Mono',Menlo,monospace\">{}</body>", common::html_runs(&b, &p, &format!("{} \u{b7} {} \u{b7} 60x44", name, pal), "MARKBLOB"));
            std::fs::write(format!("{}/{}-{}.html", dir, name, pal), page).unwrap();
        }
        let s = spark_dialog::ui::snapshot(&b, &p);
        assert!(!s.contains('?'), "{} in {}: a colour that is no slot of the palette\n{}", name, pal, s);
        grids.push(s);
    }
    assert_eq!(grids[0], grids[1], "{}: the two palettes draw different grids", name);
    let path = format!("{}/tests/golden/{}.txt", env!("CARGO_MANIFEST_DIR"), name);
    if std::env::var("UPDATE_GOLDEN").is_ok() {
        std::fs::write(&path, &grids[0]).unwrap();
    }
    let want = std::fs::read_to_string(&path).unwrap_or_default();
    assert_eq!(grids[0], want, "{} differs from {} (UPDATE_GOLDEN=1 after looking at it)", name, path);
}

#[test]
fn home() {
    let app = base();
    render(&app, "home");
}

#[test]
fn a_section_with_its_groups_and_the_exchange() {
    let mut app = base();
    app.view = View::Section(0);
    app.exchange = vec![
        Line {
            sign: Sign::You,
            text: "close the mail window".into(),
            undo: false,
        },
        Line {
            sign: Sign::Done,
            text: "aerc closed".into(),
            undo: true,
        },
    ];
    app.undo = Some(Step {
        prov: 0,
        call: model::Call {
            name: "window_focus".into(),
            arguments: json!({"name": "aerc"}).as_object().unwrap().clone(),
            ask: vec![],
        },
        who: Who::Undo,
        line: "undo aerc".into(),
    });
    render(&app, "section");
}

#[test]
fn about() {
    let mut app = base();
    app.cfg.mark = true;
    app.view = View::About;
    render(&app, "about");
}

#[test]
fn a_destructive_step_waits_for_yes() {
    let mut app = base();
    app.view = View::Section(0);
    app.sel = 1;
    app.mode = Mode::Confirm(Step {
        prov: 0,
        call: model::Call {
            name: "window_close".into(),
            arguments: json!({"name": "terminal"}).as_object().unwrap().clone(),
            ask: vec![],
        },
        who: Who::Person,
        line: "window close terminal".into(),
    });
    app.input = "ye".into();
    render(&app, "confirm");
}

#[test]
fn an_answer_wraps_under_its_sign() {
    let mut app = base();
    app.exchange = vec![
        Line {
            sign: Sign::You,
            text: "what is my address".into(),
            undo: false,
        },
        Line {
            sign: Sign::Says,
            text: "192.0.2.10 on the wire and 192.0.2.20 on wifi; the gateway is 192.0.2.1, and the name server the same.".into(),
            undo: false,
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
    app.folder = Some((f, "spark-shell://files/rows/RG93bmxvYWRz".into(), rows));
    app.sel = 3;
    app.attachment = Some("/data/me/notes.md".into());
    app.exchange = vec![Line {
        sign: Sign::You,
        text: "which of these are big".into(),
        undo: false,
    }];
    render(&app, "folder");
}
