// The frame's rules, the same in every view: nothing is underlined, a key chip is a helper and no
// control, the lit band is the list column with the same air at every size, the key row is the view's
// whatever row is lit or typed, the reply is the last row above the rule, and the frame has one width
// per view, in the middle of the window.
mod common;
use ratatui::{buffer::Buffer, layout::Rect, style::Modifier};
use serde_json::json;
use spark_dialog::app::{App, Config, Item, Provider, Step, Target, View, Who, DESTS, SETTINGS_DEST};
use spark_dialog::model;
use spark_dialog::palette::Palette;
use spark_dialog::reply::{Mark, Reply};
use spark_dialog::ui::{self, Drawn, CONTENT_Y, HINT_Y, PROMPT_Y};

fn provider(label: &str, title: &str, rows: serde_json::Value, tools: serde_json::Value) -> Provider {
    let mut p = Provider::new(label);
    p.title = title.into();
    p.rows = model::rows(&rows.to_string()).unwrap();
    p.tools = model::tools(&json!({"tools": tools}));
    p.ready = true;
    p
}

fn row(id: &str, sign: &str, text: &str, tool: Option<(&str, serde_json::Value)>, group: Option<&str>) -> serde_json::Value {
    json!({"id": id, "sign": sign, "text": text, "tool": tool.map(|(n, a)| json!({"name": n, "arguments": a})), "more": [], "columns": [], "children": null, "group": group})
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

/// The home with a window section (a layout, two windows with close behind them) and a bar section
/// (a switch and a value), the model and the mic in the footer.
fn home() -> App {
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
            row("window:show:side by side", "check", "side by side", None, Some("layout")),
            row("window:tabs", "ring", "tabs", Some(("window_tabs", json!({}))), Some("layout")),
            open_window("terminal", "~/projects"),
            open_window("firefox", "Claude Code")
        ], "short": []}),
        json!([{"name": "window_tabs"}, {"name": "window_focus"}, {"name": "window_close", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}}}]),
    );
    let bar = provider(
        "bar",
        "top",
        json!({"title": "bar", "rows": [
            row("bar:top", "check", "at the top", None, None),
            {"id": "bar:tray", "sign": "blank", "text": "the tray", "columns": [], "more": [],
             "switch": {"on": false, "turn_on": {"name": "bar_tray", "arguments": {"on": "yes"}}, "turn_off": {"name": "bar_tray", "arguments": {"on": "no"}}}},
            {"id": "bar:text", "sign": "blank", "text": "text size", "columns": [], "more": [],
             "step": {"values": [{"shown": "auto", "sent": "auto"}, {"shown": "12", "sent": "12"}], "at": 0, "set": {"name": "bar_text", "arguments": {}}, "key": "size"}}
        ], "short": []}),
        json!([{"name": "bar_tray"}, {"name": "bar_text"}]),
    );
    app.providers = vec![window, bar];
    app.model_name = Some("gemma4-26b-a4b".into());
    app.voice_on = true;
    app.size = (60, 40);
    app
}

fn draw(app: &mut App, w: u16, h: u16) -> (Buffer, Drawn, Palette) {
    app.size = (w, h);
    let pal = common::palette("tokyonight-night");
    let mut buf = Buffer::empty(Rect::new(0, 0, w, h));
    let drawn = ui::draw(app, &pal, "Sun 18 Oct \u{b7} 12:04", &mut buf);
    (buf, drawn, pal)
}

fn text(buf: &Buffer, y: u16) -> String {
    (0..buf.area.width).map(|x| buf[(x, y)].symbol()).collect()
}

fn a_step() -> Step {
    Step {
        prov: 0,
        call: model::call(&json!({"name": "window_tabs"})).unwrap(),
        who: Who::Person,
        line: "window tabs".into(),
        typed: true,
    }
}

type Case = (&'static str, Box<dyn Fn(&mut App)>);

#[test]
fn nothing_is_underlined() {
    let mut app = home();
    app.attachment = Some("/srv/notes.md".into());
    let cases: Vec<Case> = vec![
        ("the home", Box::new(|_| {})),
        ("attach in focus", Box::new(|a| a.chip_focus = Some(0))),
        ("the model in focus", Box::new(|a| a.chip_focus = Some(1))),
        ("settings", Box::new(|a| a.view = View::Dest(SETTINGS_DEST))),
        (
            "a section with a row lit",
            Box::new(|a| {
                a.view = View::Section(0);
                a.light(2);
            }),
        ),
        (
            "a reply with its undo",
            Box::new(|a| {
                a.reply = Some(Reply {
                    mark: Mark::Done,
                    text: "tabs".into(),
                    undo: true,
                });
                a.undo = Some(a_step());
            }),
        ),
    ];
    for (name, set) in cases {
        let mut app = home();
        app.attachment = Some("/srv/notes.md".into());
        set(&mut app);
        for (w, h) in [(60, 40), (150, 40)] {
            let (buf, _, _) = draw(&mut app, w, h);
            for y in 0..h {
                for x in 0..w {
                    assert!(
                        !buf[(x, y)].modifier.contains(Modifier::UNDERLINED),
                        "{} at {}x{}: an underline at ({}, {})",
                        name,
                        w,
                        h,
                        x,
                        y
                    );
                }
            }
        }
    }
}

#[test]
fn a_key_chip_is_a_helper_and_no_control() {
    // Ctrl+Enter is the key: its chip is a label for it, never a Tab stop; a click on it still sends the key
    let mut app = home();
    assert!(!app.chips().contains(&5), "the Ask chip is no control: {:?}", app.chips());
    let mut seen = vec![];
    for _ in 0..6 {
        app.tab(false);
        seen.push(app.chip_focus);
    }
    assert!(!seen.contains(&Some(5)), "Tab never stops on a key chip: {:?}", seen);
    assert!(seen.contains(&None), "Tab comes back to the prompt after the footer's controls: {:?}", seen);
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let ask = drawn
        .keys
        .iter()
        .find(|(_, _, _, k)| *k == spark_dialog::app::HintKey::Ask)
        .expect("the Ask key takes a click");
    for x in ask.0..ask.1 {
        assert_ne!(buf[(x, ask.2)].bg, pal.accent, "a key chip is never lit as a control");
    }
}

/// The band of the lit row: one run of the lit color, from the list column's first cell to the list's
/// end, the same whichever row is lit and whatever the window's size.
fn band(buf: &Buffer, pal: &Palette, y: u16) -> (u16, u16) {
    let w = buf.area.width;
    let start = (0..w).find(|x| buf[(*x, y)].bg == pal.lit).expect("a lit row has a band");
    let end = (start..w).find(|x| buf[(*x, y)].bg != pal.lit).unwrap_or(w);
    assert!((end..w).all(|x| buf[(x, y)].bg != pal.lit), "one band, not two, on row {}", y);
    (start, end)
}

fn last_glyph(buf: &Buffer, y: u16) -> u16 {
    (0..buf.area.width).rev().find(|x| !buf[(*x, y)].symbol().trim().is_empty()).unwrap()
}

#[test]
fn the_lit_band_is_the_list_column_with_the_same_air_at_every_size() {
    for (view, rows) in [(View::Home, [0usize, 9]), (View::Section(0), [0, 2]), (View::Dest(SETTINGS_DEST), [0, 1])] {
        for (w, h) in [(60u16, 40u16), (80, 40), (150, 40), (36, 20)] {
            let mut bands = vec![];
            for n in rows {
                let mut app = home();
                app.view = view.clone();
                app.light(n);
                let (buf, drawn, pal) = draw(&mut app, w, h);
                let (y, _) = drawn
                    .picks
                    .iter()
                    .find(|(_, k)| *k == n)
                    .copied()
                    .unwrap_or_else(|| panic!("{:?} at {}x{}: row {} lit is drawn: {:?}", view, w, h, n, drawn.picks));
                let (start, end) = band(&buf, &pal, y);
                assert_eq!(start, drawn.columns.0, "{:?} at {}x{}: the band starts at the column's first cell", view, w, h);
                assert!(
                    end >= last_glyph(&buf, y) + 3,
                    "{:?} at {}x{}: the row's glyphs and two cells of air lie in the band",
                    view,
                    w,
                    h
                );
                assert!(end <= drawn.columns.1, "{:?} at {}x{}: the band stays in the column", view, w, h);
                if drawn.columns.1 - drawn.columns.0 <= 60 {
                    assert_eq!(
                        end, drawn.columns.1,
                        "{:?} at {}x{}: in the dialog's own width the band is the whole column",
                        view, w, h
                    );
                }
                bands.push((start, end));
            }
            assert_eq!(bands[0], bands[1], "{:?} at {}x{}: the same band whichever row is lit", view, w, h);
        }
    }
}

#[test]
fn the_key_row_is_the_views_whatever_row_is_lit_or_typed() {
    let mut app = home();
    let idle = app.hint();
    app.light(2);
    assert_eq!(app.hint(), idle, "a row lit");
    app.set_draft("work");
    assert_eq!(app.hint(), idle, "words that light a row");
    app.set_draft("zzzq");
    assert_eq!(app.hint(), idle, "words that light no row");
    assert!(idle.iter().any(|(t, k)| !*k && t.trim() == "Close"), "Esc closes at the home: {:?}", idle);
    assert!(idle.iter().any(|(t, k)| !*k && t.trim() == "Open"), "Enter opens: {:?}", idle);

    // a section: a check row, a row with a tool, a row with steps behind it, a switch and a value
    for (view, lit) in [(View::Section(0), vec![0, 1, 3]), (View::Section(1), vec![0, 1, 2])] {
        let mut app = home();
        app.view = view.clone();
        app.came_from.push(View::Home);
        let idle = app.hint();
        assert!(idle.iter().any(|(t, k)| !*k && t.trim() == "Back"), "Esc goes back in a place: {:?}", idle);
        for n in lit {
            app.light(n);
            assert_eq!(app.hint(), idle, "{:?}: row {} lit", view, n);
        }
    }

    // spark at work: the march is the header's, never a label's
    let mut app = home();
    app.pending = Some(("what time is it".into(), None));
    let row: String = app.hint().into_iter().map(|(t, _)| t).collect();
    assert!(
        !row.chars().any(|c| ('\u{2800}'..='\u{28ff}').contains(&c)),
        "no spinner in the key row: {:?}",
        row
    );
}

#[test]
fn the_reply_is_the_last_row_above_the_rule_and_the_list_starts_under_the_keys() {
    let mut app = home();
    app.reply = Some(Reply {
        mark: Mark::Done,
        text: "window tabs".into(),
        undo: true,
    });
    app.undo = Some(a_step());
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let status = 40 - 5;
    assert!(
        text(&buf, status).contains("\u{2713} window tabs"),
        "the reply on the status row: {:?}",
        text(&buf, status)
    );
    assert_eq!(drawn.reply_undo.map(|(_, _, y)| y), Some(status), "Undo at the status row's right");
    assert!(text(&buf, status + 1).contains("\u{2500}"), "the rule under it");
    assert!(text(&buf, status - 1).trim().is_empty(), "a row of air between the list and the status");
    assert_eq!(drawn.picks[0].0, CONTENT_Y, "the list starts under the keys");
    assert_eq!(CONTENT_Y, HINT_Y + 3, "the keys' second row, a row of air, then the list, at every width");
    assert!(text(&buf, HINT_Y + 1).trim().is_empty());
    assert!(text(&buf, HINT_Y + 2).trim().is_empty());
    let (buf, drawn, _) = draw(&mut app, 36, 20);
    assert_eq!(drawn.picks[0].0, CONTENT_Y, "narrow, the keys wrap and the list stays where it is");
    assert!(text(&buf, HINT_Y + 2).trim().is_empty(), "{:?}", text(&buf, HINT_Y + 2));

    // the row the words are for is a note on the status row, never in the footer
    let mut app = home();
    app.view = View::Section(0);
    app.target = Some(Target {
        view: View::Section(0),
        provider: 0,
        id: "window:focus terminal".into(),
        text: "terminal".into(),
    });
    let (buf, _, _) = draw(&mut app, 60, 40);
    assert!(text(&buf, status).contains("For: terminal"), "{:?}", text(&buf, status));
    assert_eq!(buf[(4, status)].fg, pal.muted, "a note is muted");
    assert!(!text(&buf, 40 - 2).contains("For:"), "{:?}", text(&buf, 40 - 2));
}

#[test]
fn one_frame_width_per_view_in_the_middle_of_the_window() {
    for (w, h) in [(60u16, 40u16), (80, 40), (150, 40), (36, 20)] {
        for (view, width) in [
            (View::Home, 60u16),
            (View::Apps, 60),
            (View::Help, 60),
            (View::Conversation, 60),
            (View::Section(0), 120),
            (View::Dest(SETTINGS_DEST), 120),
        ] {
            let mut app = home();
            app.view = view.clone();
            let width = w.min(width);
            let left = (w - width) / 2;
            let (buf, drawn, _) = draw(&mut app, w, h);
            assert_eq!(drawn.columns, (left, left + width), "{:?} at {}x{}", view, w, h);
            // the header, the prompt, the keys, the rule and the footer share the column (a title the narrowest
            // window cannot hold beside the clock is cut at a word, as it was)
            let title = app.title();
            if title.len() + 26 <= width as usize {
                assert!(text(&buf, 0).contains(&title), "{:?} at {}x{}: the title", view, w, h);
                assert_eq!(
                    buf[(left + 2, 0)].symbol(),
                    &title[..1],
                    "{:?} at {}x{}: the title at the column's inset",
                    view,
                    w,
                    h
                );
            }
            assert_eq!(buf[(left + 2, PROMPT_Y)].symbol(), "\u{276f}", "{:?} at {}x{}: the prompt", view, w, h);
            assert_eq!(
                buf[(left + 2, HINT_Y)].symbol().to_lowercase(),
                buf[(left + 2, HINT_Y)].symbol(),
                "{:?} at {}x{}: the key row",
                view,
                w,
                h
            );
            assert_eq!(buf[(left + 2, h - 4)].symbol(), "\u{2500}", "{:?} at {}x{}: the rule", view, w, h);
            assert_eq!(
                buf[(left + width - 3, h - 4)].symbol(),
                "\u{2500}",
                "{:?} at {}x{}: the rule ends with the column",
                view,
                w,
                h
            );
            assert_eq!(
                buf[(left + width - 3, h - 2)].symbol(),
                "k",
                "{:?} at {}x{}: talk ends at the column's inset",
                view,
                w,
                h
            );
            assert_eq!(
                drawn.close,
                Some((left + width - 4, left + width - 1)),
                "{:?} at {}x{}: the x at the column's end",
                view,
                w,
                h
            );
        }
    }
}

#[test]
fn the_home_is_ten_lowercase_places_single_spaced_in_three_groups() {
    let mut app = home();
    let items = app.items();
    let shape: Vec<String> = items
        .iter()
        .map(|i| match i {
            Item::Dest(d) => DESTS[*d].name.to_string(),
            Item::Blank => "-".into(),
            other => format!("{:?}", other),
        })
        .collect();
    assert_eq!(
        shape,
        [
            "apps",
            "files",
            "workspace",
            "notes",
            "calendar",
            "tools",
            "-",
            "settings",
            "help",
            "about",
            "-",
            "power"
        ]
    );
    assert!(
        DESTS.iter().all(|d| d.name == d.name.to_lowercase()),
        "every place is lowercase, as the key row and the headings are"
    );
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let apps_y = drawn.picks[0].0;
    assert_eq!(buf[(2, apps_y)].fg, pal.fg, "a place's name in the text color");
    assert_eq!(buf[(ui::PURPOSE_X, apps_y)].fg, pal.muted, "what a place is for, muted");
    let workspace_y = drawn.picks[2].0;
    assert!(text(&buf, workspace_y).contains("2 windows"));
    assert_eq!(buf[(ui::PURPOSE_X, workspace_y)].fg, pal.fg, "what a place holds now, in the text color");
    app.light(1);
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let files_y = drawn.picks[1].0;
    assert_eq!(buf[(2, files_y)].fg, pal.accent, "the lit row's name in the accent");
}
