// The golden renders: the dialog drawn from fixed state in the two
// palettes the records name. Both palettes give the same grid of slots
// (every color bound to a token), and the grid is the file in golden/.
// UPDATE_GOLDEN=1 writes the files after a change that was looked at.
mod common;
use common::palette;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use serde_json::json;
use spark_dialog::app::{App, Config, Line, Mode, Provider, Sign, Staged, Step, View, Who, CALENDAR_DEST, HEIGHT, SETTINGS_DEST, WIDTH};
use spark_dialog::model;

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
fn render_at(app: &App, name: &str, w: u16, h: u16) {
    let mut grids = vec![];
    for pal in ["tokyonight-night", "solarized-light"] {
        let p = palette(pal);
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        assert_eq!(app.size, (w, h), "{}: the app is told the size it is drawn at", name);
        spark_dialog::ui::draw(app, &p, CLOCK, &mut b);
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
fn a_section_with_its_groups_and_the_exchange() {
    let mut app = base();
    app.view = View::Section(0);
    app.came_from = vec![View::Home];
    app.exchange = vec![
        Line {
            sign: Sign::You,
            text: "window close aerc".into(),
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
fn a_turn_is_the_command_then_what_came_of_it() {
    // #53: a step's turn is its command as it ran and its result, Undo at the end of that result;
    // a question's turn is the words and the answer; the newest turn first
    let mut app = full();
    app.exchange = vec![
        Line {
            sign: Sign::You,
            text: "theme gruvbox-dark".into(),
            undo: false,
        },
        Line {
            sign: Sign::Done,
            text: "gruvbox-dark is on".into(),
            undo: true,
        },
        Line {
            sign: Sign::You,
            text: "is firefox open?".into(),
            undo: false,
        },
        Line {
            sign: Sign::Says,
            text: "No. Firefox is installed, and no window of it is open now.".into(),
            undo: false,
        },
    ];
    app.undo = Some(Step {
        prov: 1,
        call: model::Call {
            name: "theme_palette".into(),
            arguments: json!({"name": "everforest-dark"}).as_object().unwrap().clone(),
            ask: vec![],
        },
        who: Who::Undo,
        line: "undo theme gruvbox-dark".into(),
    });
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
fn about() {
    let mut app = base();
    app.view = View::About;
    app.came_from = vec![View::Home];
    app.exchange = vec![Line {
        sign: Sign::You,
        text: "show me about".into(),
        undo: false,
    }]; // the about is a page: the exchange is not drawn on it
    render(&app, "about");
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
        },
        who: Who::Person,
        line: "window close terminal".into(),
    });
    app.input = "ye".into();
    app.cursor = 2;
    render(&app, "confirm");
}

#[test]
fn an_answer_wraps_under_its_sign() {
    let mut app = full();
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
    app.came_from = vec![View::Home];
    app.folder = Some((f, "spark-shell://files/rows/RG93bmxvYWRz".into(), rows));
    app.in_list = true;
    app.sel = 3;
    app.attachment = Some("/data/me/notes.md".into());
    app.exchange = vec![Line {
        sign: Sign::You,
        text: "which of these are big".into(),
        undo: false,
    }];
    render(&app, "folder");
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
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    spark_dialog::ui::draw(app, &p, CLOCK, &mut b);
    let rows = (0..HEIGHT).map(|y| (0..WIDTH).map(|x| b[(x, y)].symbol().to_string()).collect()).collect();
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
    assert!(rows[7..12].iter().all(|r| r.contains(block)), "five rows of figures under the hint");
    assert!(!rows[6].contains(block) && !rows[12].contains(block), "a row of air above and below them");
    assert_eq!(b[(2, 7)].fg, p.accent, "in the accent");
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    spark_dialog::ui::draw(&app, &p, "Sun 18 Oct \u{b7} 9:05 PM", &mut b);
    let row = |y: u16| (0..WIDTH).map(|x| b[(x, y)].symbol().to_string()).collect::<String>();
    assert!(
        row(11).trim_end().ends_with("PM"),
        "a twelve-hour clock says PM beside the figures: {}",
        row(11)
    );
    assert_eq!((7..12).filter_map(|y| at(&row(y), block)).min(), Some(2), "a 9 starts at the months' left edge");
}

#[test]
fn the_calendar_draws_this_month_and_the_next_side_by_side() {
    let (_, _, rows) = drawn(&calendar_app(true));
    let y = rows.iter().position(|r| r.starts_with("  October 2026")).expect("this month");
    assert_eq!(y, 13, "under the prompt, the hint and the time's five rows of figures");
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
    let at_clock = at(&rows[0], CLOCK).expect("the date and the time");
    let before: String = rows[0].chars().skip(at_clock - 2).take(2).collect();
    assert_eq!(before, "  ", "two cells of air before the date: {}", rows[0]);
}
