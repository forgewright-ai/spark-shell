// The frame's rules, the same in every view (dialog/DESIGN.md): nothing is underlined, a key chip is a helper
// and no control, the selection bar is the list column with the same air at every size and the one signal,
// the key bar is the view's whatever row is lit or typed and the last thing in the frame, the prompt's tools
// stand under the prompt with the diamond's rule under them, the reply is the last row above the plain rule,
// and the frame has one width per view, in the middle of the window.
mod common;
use ratatui::{buffer::Buffer, layout::Rect, style::Modifier};
use serde_json::json;
use spark_dialog::app::{App, Config, HintKey, Item, Mode, Provider, Step, Target, View, Who, DESTS, SETTINGS_DEST};
use spark_dialog::model;
use spark_dialog::palette::Palette;
use spark_dialog::reply::{Mark, Reply};
use spark_dialog::ui::{self, keys_y, Drawn, CONTENT_Y, PROMPT_Y, TOOLS_Y, TOP_RULE_Y};

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

/// The cells a..b of a row, by cell and not by byte: a glyph outside ASCII is one cell.
fn span(buf: &Buffer, y: u16, a: u16, b: u16) -> String {
    (a..b).map(|x| buf[(x, y)].symbol()).collect()
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
    // Esc is a key: its chip is a label for it, never a Tab stop; a click on it still sends the key. Enter and
    // Ctrl+Enter have no chip: Enter opens what the bar is on, and asking is a row
    let mut app = home();
    assert!(!app.chips().contains(&5), "a key chip is no control: {:?}", app.chips());
    let mut seen = vec![];
    for _ in 0..6 {
        app.tab(false);
        seen.push(app.chip_focus);
    }
    assert!(!seen.contains(&Some(5)), "Tab never stops on a key chip: {:?}", seen);
    assert!(seen.contains(&None), "Tab comes back to the prompt after the prompt's tools: {:?}", seen);
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let esc = drawn.keys.iter().find(|(_, _, _, k)| *k == HintKey::Escape).expect("the Esc key takes a click");
    assert_eq!(esc.2, keys_y(40), "the key bar is the last thing in the frame");
    for x in esc.0..esc.1 {
        assert_ne!(buf[(x, esc.2)].bg, pal.accent, "a key chip is never lit as a control");
    }
    assert!(
        !drawn.keys.iter().any(|(_, _, _, k)| matches!(k, HintKey::Enter | HintKey::Ask)),
        "Enter and Ask have no chip: {:?}",
        drawn.keys
    );
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
    assert!(
        !idle.iter().any(|(t, k)| *k && t == "Enter"),
        "Enter has no chip in a view's key bar: {:?}",
        idle
    );

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
fn the_frame_is_one_shape_top_and_bottom_and_the_reply_is_the_last_row_above_the_rule() {
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
    assert!(
        !text(&buf, status + 1).contains('\u{25c7}') && !text(&buf, status + 1).contains('\u{25c6}'),
        "the bottom rule is plain: {:?}",
        text(&buf, status + 1)
    );
    assert!(text(&buf, status - 1).trim().is_empty(), "a row of air between the list and the status");
    assert!(text(&buf, status + 2).trim().is_empty(), "a row of air between the rule and the keys");
    assert_eq!(keys_y(40), status + 3, "the key bar is the last thing in the frame");
    assert!(
        text(&buf, keys_y(40)).contains("Esc"),
        "the view's keys at the bottom: {:?}",
        text(&buf, keys_y(40))
    );
    // the top has the same shape: the prompt, its tools, the rule with the diamond, a row of air, the list
    assert_eq!(
        CONTENT_Y,
        TOOLS_Y + 4,
        "the tools, a row of air, the rule, a row of air, then the list, at every width"
    );
    assert_eq!(TOP_RULE_Y, TOOLS_Y + 2);
    assert!(
        text(&buf, TOOLS_Y + 1).trim().is_empty(),
        "a row of air between the tools and the rule (v0.124.3)"
    );
    let tools = text(&buf, TOOLS_Y);
    assert!(tools.contains("gemma4") && tools.contains("talk"), "the prompt's tools under it: {:?}", tools);
    assert!(text(&buf, TOP_RULE_Y).contains("\u{2500}"), "the rule under the tools");
    assert!(
        text(&buf, TOP_RULE_Y).contains('\u{25c6}'),
        "the diamond full: a model answers: {:?}",
        text(&buf, TOP_RULE_Y)
    );
    assert!(text(&buf, TOP_RULE_Y + 1).trim().is_empty(), "a row of air under the rule");
    assert_eq!(drawn.picks[0].0, CONTENT_Y, "the list starts under the prompt's block");
    let (buf, drawn, _) = draw(&mut app, 36, 20);
    assert_eq!(drawn.picks[0].0, CONTENT_Y, "narrow, the list stays where it is");
    assert!(text(&buf, TOP_RULE_Y + 1).trim().is_empty(), "{:?}", text(&buf, TOP_RULE_Y + 1));
    assert!(text(&buf, keys_y(20)).contains("Esc"), "{:?}", text(&buf, keys_y(20)));
    app.model_name = None;
    let (buf, _, _) = draw(&mut app, 60, 40);
    assert!(
        text(&buf, TOP_RULE_Y).contains('\u{25c7}') && !text(&buf, TOP_RULE_Y).contains('\u{25c6}'),
        "the diamond hollow: no model answers: {:?}",
        text(&buf, TOP_RULE_Y)
    );

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
            // the prompt, the list and the status row share the column; the header, the rules and the key bar are
            // the window's (v0.124.4): the title centered, the key bar at the window's inset
            let title = app.title();
            if title.len() + 26 <= width as usize {
                assert!(text(&buf, 0).contains(&title), "{:?} at {}x{}: the title", view, w, h);
                // the name and its state are centered together: their middle is the window's, within a cell
                let (ta, _) = drawn.title.expect("the title's cells");
                let end = (ta..w - 4).rev().find(|&x| buf[(x, 0)].symbol() != " ").map_or(ta, |x| x + 1);
                assert!(
                    ((ta + end) as i32 / 2 - w as i32 / 2).abs() <= 1,
                    "{:?} at {}x{}: the title centered in the window ({}..{})",
                    view,
                    w,
                    h,
                    ta,
                    end
                );
            }
            assert_eq!(buf[(left + 2, PROMPT_Y)].symbol(), "\u{276f}", "{:?} at {}x{}: the prompt", view, w, h);
            assert_eq!(
                buf[(2, keys_y(h))].symbol().to_lowercase(),
                buf[(2, keys_y(h))].symbol(),
                "{:?} at {}x{}: the key bar",
                view,
                w,
                h
            );
            assert_ne!(
                buf[(2, keys_y(h))].symbol(),
                " ",
                "{:?} at {}x{}: the key bar starts at the window's inset",
                view,
                w,
                h
            );
            assert_eq!(buf[(left + 2, TOP_RULE_Y)].symbol(), "\u{2500}", "{:?} at {}x{}: the top rule", view, w, h);
            assert_eq!(
                buf[(left + width - 3, TOP_RULE_Y)].symbol(),
                "\u{2500}",
                "{:?} at {}x{}: the top rule ends with the column",
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
                buf[(left + width - 3, TOOLS_Y)].symbol(),
                "k",
                "{:?} at {}x{}: talk ends at the column's inset, on the tools row",
                view,
                w,
                h
            );
            assert_eq!(
                drawn.close,
                Some((w - 4, w - 1)),
                "{:?} at {}x{}: the x at the window's end, the header being the window's (v0.124.4)",
                view,
                w,
                h
            );
        }
    }
}

#[test]
fn asking_is_a_row_last_among_the_matches_and_alone_when_nothing_matches() {
    // the placeholder says what the box is for; Enter is the one key: it opens the match the bar is on, and the
    // ask row when nothing matches (dialog/DESIGN.md)
    assert_eq!(spark_dialog::app::PLACEHOLDER, "search or ask");
    let type_words = |app: &mut App, words: &str| {
        app.set_draft("");
        for c in words.chars() {
            app.typed(c);
        }
    };
    let mut app = home();
    assert!(!app.items().iter().any(|it| matches!(it, Item::Ask)), "the prompt empty: a menu, no ask row");
    type_words(&mut app, "workspace");
    let items = app.items();
    assert!(matches!(items.last(), Some(Item::Ask)), "the ask row last: {:?}", items);
    assert!(matches!(items[items.len() - 2], Item::Blank), "a row of air before it");
    assert!(
        app.in_list && matches!(app.picks()[app.sel], Item::Dest(2)),
        "the match is selected, not the ask row"
    );
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let (ask_y, _) = drawn.picks.iter().find(|(_, n)| matches!(app.picks()[*n], Item::Ask)).copied().unwrap();
    assert!(
        text(&buf, ask_y).contains("ask spark") && text(&buf, ask_y).contains("workspace"),
        "{:?}",
        text(&buf, ask_y)
    );
    assert_eq!(buf[(4, ask_y)].fg, pal.fg);
    assert_eq!(buf[(ui::PURPOSE_X, ask_y)].fg, pal.muted, "the words echoed muted");
    app.down();
    assert!(matches!(app.picks()[app.sel], Item::Ask), "Down reaches it");

    type_words(&mut app, "why is firefox slow today");
    let picks = app.picks();
    assert!(matches!(picks.as_slice(), [Item::Ask]), "nothing matches: the ask row alone: {:?}", picks);
    assert!(app.in_list && app.sel == 0, "and selected, so Enter asks");
    assert!(!app.items().iter().any(|it| matches!(it, Item::Blank)), "no air above a row that stands alone");
    app.enter();
    assert!(app.pending.is_some(), "Enter on the ask row asks");
    assert_eq!(app.jobs.len(), 1);

    // no model: no ask row, and typing searches alone
    let mut app = home();
    app.model_name = None;
    type_words(&mut app, "why is firefox slow today");
    assert!(app.picks().is_empty(), "{:?}", app.picks());
    assert!(!app.in_list);

    // words the dialog runs itself are never a question: undo with an undo at hand stays a command, at home and in Apps
    let mut app = home();
    app.undo = Some(Step { who: Who::Undo, ..a_step() });
    type_words(&mut app, "undo");
    assert!(
        !app.items().iter().any(|it| matches!(it, Item::Ask)),
        "undo at hand: no ask row: {:?}",
        app.picks()
    );
    assert!(!app.in_list, "the word stays at the prompt, where Enter runs it");
    app.enter();
    assert!(app.undo.is_none(), "Enter took the undo");
    let mut app = home();
    app.view = View::Apps;
    app.came_from.push(View::Home);
    app.apps.undo = Some(spark_dialog::apps::preferences::Preferences::default());
    type_words(&mut app, "undo");
    assert!(
        !app.items().iter().any(|it| matches!(it, Item::Ask)),
        "Apps' undo at hand: no ask row: {:?}",
        app.picks()
    );
    app.enter();
    assert!(app.apps.undo.is_none(), "Enter took Apps' undo");
    assert!(app.reply.as_ref().is_some_and(|r| r.text == "put back"), "{:?}", app.reply);

    // in Apps, whose prompt filters the list, the ask row stands too: Enter carries the words to the request
    let mut app = home();
    app.view = View::Apps;
    app.came_from.push(View::Home);
    type_words(&mut app, "is my disk full");
    // no app by these words: the managing rows stay, as they do in any search of the list, and the ask row stands
    // last and selected
    assert!(matches!(app.picks().last(), Some(Item::Ask)), "{:?}", app.picks());
    assert!(
        app.in_list && matches!(app.picks()[app.sel], Item::Ask),
        "the ask row selected: {:?}",
        app.picks().get(app.sel)
    );
    app.enter();
    assert_eq!(app.view, View::Conversation);
    assert!(app.pending.is_some(), "asked");
}

#[test]
fn an_objects_row_is_selected_by_a_click_and_acts_on_a_second_while_a_menus_row_acts_at_once() {
    use std::time::{Duration, Instant};
    let t0 = Instant::now();
    // home is a menu: one click opens the place
    let mut app = home();
    app.clicked(0, t0);
    assert_eq!(app.view, View::Apps, "one click on a place opens it");
    // a switch among a section's controls flips on one click
    let mut app = home();
    app.view = View::Section(1);
    app.came_from.push(View::Home);
    let tray = app
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Row(1, 1)))
        .expect("the tray's switch is a pick");
    app.clicked(tray, t0);
    assert!(app.providers[1].rows.rows[1].switch.as_ref().unwrap().on, "a control acts at once");
    // a window is an object: the first click selects it and the status row says what it is; a second click acts
    let mut app = home();
    app.view = View::Section(0);
    app.came_from.push(View::Home);
    let terminal = app.picks().iter().position(|it| matches!(it, Item::Row(0, 2))).expect("the window is a pick");
    app.clicked(terminal, t0);
    assert!(app.in_list && app.sel == terminal, "selected");
    assert!(app.reply.is_none() && app.running.is_none(), "nothing acted on the first click");
    let (buf, _, pal) = draw(&mut app, 60, 40);
    let status = text(&buf, ui::status_y(40));
    assert!(
        status.contains("terminal") && status.contains("~/projects"),
        "the selected object's line: {:?}",
        status
    );
    assert_eq!(buf[(4, ui::status_y(40))].fg, pal.muted, "muted");
    app.clicked(terminal, t0 + Duration::from_millis(200));
    // the step ran: here it is a risky one, so it waits for the typed yes, as it would from Enter
    assert!(
        app.reply.is_some() || app.running.is_some() || matches!(app.mode, Mode::Confirm(_)),
        "the second click acts on it: {:?}",
        app.mode
    );
    // two clicks too far apart are two selections
    let mut app = home();
    app.view = View::Section(0);
    app.came_from.push(View::Home);
    app.clicked(terminal, t0);
    app.clicked(terminal, t0 + Duration::from_secs(2));
    assert!(
        app.reply.is_none() && app.running.is_none() && app.mode == Mode::Normal,
        "a slow second click selects again"
    );
    assert!(app.object_pick(terminal), "a window is an object");
    assert!(!app.object_pick(0), "tabs is a menu's row among them: one click acts");
    app.view = View::Section(1);
    assert!(!app.object_pick(tray), "a control among a section's rows is a menu's row");
}

#[test]
fn a_places_second_column_is_its_state_from_what_the_dialog_already_holds() {
    let mut app = home();
    let state = |app: &App, name: &str| app.dest_state(DESTS.iter().position(|d| d.name == name).unwrap());
    // before anything is known: the purpose stands, muted, for every place but the two whose sections are here
    for name in ["apps", "files", "notes", "calendar", "settings", "about", "tools", "power"] {
        assert_eq!(state(&app, name), None, "{name}");
    }
    assert_eq!(
        state(&app, "workspace").as_deref(),
        Some("2 windows \u{b7} terminal, firefox"),
        "the windows by name, lowercase"
    );
    assert!(state(&app, "help").is_some_and(|s| s.ends_with(" shortcuts")), "the counts help has");
    // the catalog read: its counts
    app.apps.pending = Some((1, "catalog".into()));
    app.apps
        .receive(
            1,
            json!({"apps":[
                {"id":"a.desktop","name":"Alpha","generic_name":"Editor","categories":["Utility"]},
                {"id":"b.desktop","name":"Beta","categories":["Utility"]},
                {"id":"footclient.desktop","name":"Foot Client","categories":["System"]}
            ]}),
        )
        .unwrap();
    assert_eq!(state(&app, "apps").as_deref(), Some("2 installed \u{b7} 1 hidden"));
    // the files section's own summary, the newest note and its date, the look, the screens and the network
    app.providers.push(provider(
        "files",
        "~",
        json!({"title": "~", "rows": [
            {"id": "files:total", "sign": "blank", "text": "2 files \u{b7} 3 KB", "tool": null, "more": [], "columns": [], "children": null, "group": "this folder"}
        ], "short": []}),
        json!([]),
    ));
    let mut shopping = row("notes:1", "", "Shopping list", Some(("notes_open", json!({"path": "/n/1"}))), None);
    shopping["columns"] = json!(["4 Nov"]);
    let other = row("notes:2", "", "Ideas", Some(("notes_open", json!({"path": "/n/2"}))), None);
    app.providers.push(provider(
        "notes",
        "",
        json!({"title": "notes", "rows": [shopping, other], "short": []}),
        json!([{"name": "notes_open"}]),
    ));
    app.providers.push(provider(
        "theme",
        "tokyonight-night \u{b7} size 12",
        json!({"title": "theme", "rows": [], "short": []}),
        json!([]),
    ));
    app.providers.push(provider(
        "display",
        "2 screens",
        json!({"title": "display", "rows": [], "short": []}),
        json!([]),
    ));
    app.providers
        .push(provider("wifi", "home", json!({"title": "wifi", "rows": [], "short": []}), json!([])));
    let mut about = provider("about", "", json!({"title": "about", "rows": [], "short": []}), json!([]));
    about.version = "0.124".into();
    app.providers.push(about);
    app.about_idx = Some(app.providers.len() - 1);
    assert_eq!(state(&app, "files").as_deref(), Some("~ \u{b7} 2 files \u{b7} 3 KB"));
    assert_eq!(state(&app, "notes").as_deref(), Some("2 notes \u{b7} shopping list, 4 Nov"));
    assert_eq!(
        state(&app, "settings").as_deref(),
        Some("tokyonight-night \u{b7} 2 screens"),
        "the look and the screens, never the network"
    );
    assert_eq!(
        state(&app, "about").as_deref(),
        Some("spark-shell v0.124"),
        "the installed release, nothing else"
    );
    assert_eq!(state(&app, "tools"), None, "no state worth more than its purpose");
    assert_eq!(state(&app, "power"), None);
    // the about page opens on the versions
    app.view = View::About;
    let (buf, _, _) = draw(&mut app, 60, 40);
    assert!(text(&buf, CONTENT_Y).contains("spark-shell v0.124"), "{:?}", text(&buf, CONTENT_Y));
    assert!(text(&buf, CONTENT_Y + 2).contains("dialog "), "{:?}", text(&buf, CONTENT_Y + 2));
}

#[test]
fn the_home_is_ten_lowercase_places_in_three_groups_that_breathe_when_the_window_has_the_rows() {
    let mut app = home();
    let shape = |app: &App| -> Vec<String> {
        app.items()
            .iter()
            .map(|i| match i {
                Item::Dest(d) => DESTS[*d].name.to_string(),
                Item::Blank => "-".into(),
                other => format!("{:?}", other),
            })
            .collect()
    };
    // the dialog's own size: a row of air between the rows, two between the groups
    assert_eq!(
        shape(&app),
        [
            "apps",
            "-",
            "files",
            "-",
            "workspace",
            "-",
            "notes",
            "-",
            "calendar",
            "-",
            "tools",
            "-",
            "-",
            "settings",
            "-",
            "help",
            "-",
            "about",
            "-",
            "-",
            "power"
        ]
    );
    // the minimum window: single spaced, a row of air between the groups, and it scrolls
    app.size = (36, 20);
    assert_eq!(
        shape(&app),
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
        "every place is lowercase, as the key bar and the headings are"
    );
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let apps_y = drawn.picks[0].0;
    assert_eq!(buf[(4, apps_y)].symbol(), "a", "a place's name at the row column");
    assert_eq!(buf[(4, apps_y)].fg, pal.fg, "a place's name in the text color");
    assert_eq!(buf[(ui::PURPOSE_X, apps_y)].fg, pal.muted, "what a place is for, muted");
    assert!(!text(&buf, apps_y).contains('\u{203a}'), "no arrow at a place's end: every row here opens");
    let workspace_y = drawn.picks[2].0;
    assert!(text(&buf, workspace_y).contains("2 windows"));
    assert_eq!(
        buf[(ui::PURPOSE_X, workspace_y)].fg,
        pal.muted,
        "what a place holds now, muted too: one color for the column"
    );
    app.light(1);
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let files_y = drawn.picks[1].0;
    assert_eq!(
        buf[(4, files_y)].fg,
        pal.fg,
        "the selected row's name stays in the text color: the bar is the one signal"
    );
    assert_eq!(buf[(4, files_y)].bg, pal.lit, "the selection bar under it");
    assert_eq!(buf[(0, files_y)].symbol(), " ", "no cursor glyph before the bar");
    assert!(!buf[(4, files_y)].modifier.contains(Modifier::BOLD), "no bold on the selected row");
}

#[test]
fn back_has_more_doors_than_its_chip() {
    // dialog/DESIGN.md (v0.124.3): with nothing typed, Left and Backspace go back a level, and the header's place
    // name is a target for a click; none of them closes the dialog from home
    let t0 = std::time::Instant::now();
    let mut app = home();
    assert!(!app.can_go_back(), "home is the first level");
    app.left();
    app.backspace();
    assert_eq!(app.view, View::Home, "nothing closes the dialog but Esc");
    app.clicked(0, t0);
    assert_eq!(app.view, View::Apps);
    assert!(app.can_go_back());
    app.left();
    assert_eq!(app.view, View::Home, "Left goes back, as Right opens");
    app.clicked(0, t0);
    app.backspace();
    assert_eq!(app.view, View::Home, "Backspace on an empty prompt goes back");
    // words typed: Left moves the cursor and Backspace deletes, as before
    app.clicked(0, t0);
    for c in "fire".chars() {
        app.typed(c);
    }
    app.left();
    app.backspace();
    assert_eq!(app.view, View::Apps, "with words typed the keys edit them");
    let (buf, _, _) = draw(&mut app, 60, 40);
    assert!(text(&buf, PROMPT_Y).contains("fie"), "{:?}", text(&buf, PROMPT_Y));
    app.set_draft("");
    assert!(app.can_go_back());
    let (buf, drawn, _) = draw(&mut app, 60, 40);
    let (a, b) = drawn.title.expect("the header's place name has cells");
    assert_eq!(span(&buf, 0, a, b), "apps", "{:?}", text(&buf, 0));
}

#[test]
fn asking_off_turns_the_model_off_everywhere_and_is_the_model_pages_first_choice() {
    // dialog/DESIGN.md (v0.124.3): off, nothing is asked: no ask row, the diamond hollow, Ctrl+Enter refused with
    // the reason, the control reading model off; the choice is a row of the model page and applies at once
    let mut app = home();
    assert!(app.model_on, "on unless turned off");
    app.model_on = false;
    for c in "zebra".chars() {
        app.typed(c);
    }
    assert!(!app.items().iter().any(|it| matches!(it, Item::Ask)), "no ask row with the model off");
    let (buf, _, _) = draw(&mut app, 60, 40);
    assert!(
        text(&buf, TOP_RULE_Y).contains('\u{25c7}') && !text(&buf, TOP_RULE_Y).contains('\u{25c6}'),
        "the diamond hollow: {:?}",
        text(&buf, TOP_RULE_Y)
    );
    assert!(text(&buf, TOOLS_Y).contains("model off"), "{:?}", text(&buf, TOOLS_Y));
    app.ask();
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text.contains("the model is off")),
        "Ctrl+Enter refused with the reason: {:?}",
        app.reply
    );
    app.set_draft("");
    app.reply = None;
    app.chip(1);
    assert_eq!(app.view, View::Models);
    let items = app.items();
    assert!(matches!(&items[0], Item::Heading(h) if h == "asking"), "{:?}", items.first());
    assert!(matches!(items[1], Item::ModelOpt(true)) && matches!(items[2], Item::ModelOpt(false)));
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let row_of = |drawn: &Drawn, app: &App, on: bool| {
        drawn
            .picks
            .iter()
            .find(|(_, n)| matches!(app.picks()[*n], Item::ModelOpt(o) if o == on))
            .copied()
            .expect("the asking row")
    };
    let (off_y, _) = row_of(&drawn, &app, false);
    assert_eq!(buf[(4, off_y)].fg, pal.accent, "off is the choice in force, its dot in the accent");
    assert!(text(&buf, off_y).contains("off"));
    let (_, on_n) = row_of(&drawn, &app, true);
    app.light(on_n);
    app.enter();
    assert!(app.model_on, "the choice applies at once");
    assert_eq!(app.view, View::Home, "and the page gives way to where the control was clicked");
    let (buf, _, _) = draw(&mut app, 60, 40);
    let tools = text(&buf, TOOLS_Y);
    assert!(
        tools.contains(" gemma4-26b-a4b ") && !tools.contains("local") && !tools.contains('\u{2304}') && !tools.contains('\u{b7}'),
        "the model's name alone on the control: {:?}",
        tools
    );
    assert!(text(&buf, TOP_RULE_Y).contains('\u{25c6}'), "the diamond full again");
}

#[test]
fn the_header_is_back_the_centered_title_and_the_x_and_the_chrome_takes_a_wide_window() {
    // dialog/DESIGN.md (v0.124.4): no clock in the header; the place's name centered; back at the left where there
    // is a level above; the x at the right. Wider than the column, the header, the rules and the key bar take the
    // window's width and the column stays centered
    let t0 = std::time::Instant::now();
    let mut app = home();
    let (buf, drawn, _) = draw(&mut app, 60, 40);
    let head = text(&buf, 0);
    assert!(!head.contains("12:04") && !head.contains("Oct"), "no clock: {:?}", head);
    assert!(drawn.back.is_none(), "home is the first level");
    let (a, b) = drawn.title.unwrap();
    assert_eq!(span(&buf, 0, a, b), "home");
    assert!((a as i32 - 28).abs() <= 1, "centered in 60 cells: {}", a);
    assert_eq!(buf[(57, 0)].symbol(), "\u{d7}", "the x at the right");
    app.clicked(0, t0);
    let (buf, drawn, _) = draw(&mut app, 60, 40);
    let head = text(&buf, 0);
    let (ba, bb) = drawn.back.expect("back where there is a level above");
    assert_eq!((ba, span(&buf, 0, ba, bb)), (2, "\u{2039} back".to_string()));
    let (a, b) = drawn.title.unwrap();
    assert_eq!(span(&buf, 0, a, b), "apps", "{:?}", head);
    assert!(head.contains("installed apps"), "the state after the name: {:?}", head);
    assert!((a as i32 - 19).abs() <= 1, "the title and its state centered: {}", a);
    // a wide window: the chrome at its width, the column in the middle
    let (buf, drawn, pal) = draw(&mut app, 100, 40);
    let left = (100 - 60) / 2;
    assert_eq!(buf[(left + 2, PROMPT_Y)].symbol(), "\u{276f}", "the prompt sign at the column's edge");
    assert_eq!(buf[(2, TOP_RULE_Y)].symbol(), "\u{2500}", "the rule from the window's edge");
    assert_eq!(buf[(97, TOP_RULE_Y)].symbol(), "\u{2500}", "to the window's edge");
    assert_eq!(buf[(50, TOP_RULE_Y)].symbol(), "\u{25c6}", "the diamond in the middle");
    assert_eq!(buf[(2, 36)].symbol(), "\u{2500}", "the plain rule too");
    assert_eq!(buf[(97, 0)].symbol(), "\u{d7}", "the x at the window's right");
    assert_eq!(drawn.back.map(|(a, _)| a), Some(2), "back at the window's left");
    assert_eq!(drawn.keys.iter().map(|k| k.0).min(), Some(2), "the key bar at the window's left");
    assert_eq!(drawn.close, Some((96, 99)));
    let _ = pal;
}

#[test]
fn the_header_is_a_band_across_the_window_and_its_words_are_in_the_text_color() {
    // dialog/DESIGN.md (v0.124.5): row 0 is a band in the band slot, the accent at a quarter over the surface,
    // across the window at every width; its words are in the text color (muted did not read on the tint), the
    // title bold; the band is one row, and no other row wears it
    let t0 = std::time::Instant::now();
    let mut app = home();
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    assert!(pal.band != pal.lit && pal.band != pal.surface && pal.band != pal.accent, "a slot of its own");
    assert!((0..60).all(|x| buf[(x, 0)].bg == pal.band), "the band spans the window: {:?}", text(&buf, 0));
    assert!((0..60).all(|x| buf[(x, 1)].bg != pal.band), "the band is one row");
    assert!((0..60).all(|x| buf[(x, CONTENT_Y)].bg != pal.band), "a list row never wears it");
    let (a, _) = drawn.title.unwrap();
    assert_eq!(buf[(a, 0)].fg, pal.fg, "the title in the text color");
    assert!(buf[(a, 0)].modifier.contains(Modifier::BOLD), "and bold");
    assert_eq!(buf[(57, 0)].fg, pal.fg, "the x in the text color on the band");
    app.clicked(0, t0);
    let (buf, drawn, _) = draw(&mut app, 60, 40);
    let (ba, _) = drawn.back.expect("back where there is a level above");
    assert_eq!(buf[(ba, 0)].fg, pal.fg, "back in the text color on the band");
    let head = text(&buf, 0);
    let state = head.find("installed").expect("the place's state after its name") as u16;
    assert_eq!(buf[(state, 0)].fg, pal.fg, "the state in the text color too, plain: {:?}", head);
    assert!(!buf[(state, 0)].modifier.contains(Modifier::BOLD));
    // a wide window: the band is the window's, with the rest of the chrome
    let (buf, _, _) = draw(&mut app, 100, 40);
    assert!((0..100).all(|x| buf[(x, 0)].bg == pal.band), "the band across a wide window");
    assert!((0..100).all(|x| buf[(x, 1)].bg != pal.band));
}

#[test]
fn a_wrapped_key_bar_takes_the_air_above_it_and_leaves_the_last_row_empty() {
    // (v0.124.5) with no air of foot's own around the cells, the window's last row is its bottom edge. Narrow, the
    // keys wrap onto a second line: the two lines stand at h-3 and h-2, in the air above the key bar, so nothing is
    // drawn on the edge; wide, the one line stays at h-2 with the last row empty
    let root = json!({"title": "files", "rows": [{"id": "files:root:a", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/aG9tZQ", "group": null}], "short": ["files:root:a"]});
    let folder = json!({"title": "~", "rows": [
        {"id": "files:file:n", "sign": "blank", "text": "notes.md", "tool": {"name": "files_open", "arguments": {"path": "/x/notes.md"}},
         "more": [{"name": "files_show", "arguments": {"path": "/x/notes.md"}}], "columns": ["12 B", "today"], "children": null, "group": null,
         "page": "spark-shell://files/page/bm90ZXM"}
    ], "short": []});
    let tools = json!([
        {"name": "files_open", "title": "files open PATH", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}, "annotations": {"destructiveHint": false}},
        {"name": "files_show", "title": "files show PATH", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}, "annotations": {"readOnlyHint": true}}
    ]);
    let (mut app, rx, tx) = common::app_with(&["files"]);
    app.servers.push(common::stub(
        0,
        "files",
        Box::new(move |v, send| {
            if v.get("method").and_then(serde_json::Value::as_str) == Some("resources/read")
                && v.pointer("/params/uri") != Some(&json!("spark-shell://files/rows"))
            {
                return send(common::result(
                    &v["id"],
                    json!({"contents": [{"uri": v["params"]["uri"], "mimeType": "application/json", "text": folder.to_string()}]}),
                ));
            }
            if let Some(r) = common::ordinary("files", v, &tools, &root) {
                send(r);
            }
        }),
        tx,
    ));
    app.start();
    assert!(common::pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.in_list = true;
    app.sel = 1; // files, the second place of home
    app.enter();
    assert!(common::pump(&mut app, &rx, |a| a.folder.is_some()), "the folder opens: {:?}", app.view);
    assert!(matches!(app.view, View::Folder(0, _)), "{:?}", app.view);
    let (buf, drawn, _) = draw(&mut app, 60, 40);
    let keys = text(&buf, keys_y(40));
    assert!(keys.contains("Esc") && keys.contains("P"), "wide, one line of keys: {:?}", keys);
    assert!(text(&buf, 39).trim().is_empty(), "the last row is empty");
    assert!(drawn.keys.iter().all(|k| k.2 == keys_y(40)));
    let (buf, drawn, _) = draw(&mut app, 36, 20);
    assert!(text(&buf, 19).trim().is_empty(), "narrow, the last row is still empty: {:?}", text(&buf, 19));
    assert!(text(&buf, 17).contains("Esc"), "the first line of keys at h-3: {:?}", text(&buf, 17));
    assert!(text(&buf, 18).contains("P"), "the second at h-2: {:?}", text(&buf, 18));
    assert!(text(&buf, 16).contains("\u{2500}"), "the plain rule above them where it was");
    assert!(drawn.keys.iter().all(|k| k.2 == 17 || k.2 == 18), "{:?}", drawn.keys);
}

#[test]
fn the_wheel_moves_the_bar_a_row_at_a_time() {
    let mut app = home();
    assert!(!app.in_list);
    app.wheel(1);
    assert!(app.in_list && app.sel == 0, "a notch down enters the list");
    app.wheel(1);
    assert_eq!(app.sel, 1, "one row a notch");
    app.wheel(-1);
    assert_eq!(app.sel, 0);
    app.wheel(-1);
    assert!(!app.in_list, "above the first row is the prompt, as the arrow has it");
}

#[test]
fn undo_on_the_status_row_is_a_control_not_a_key_chip() {
    let mut app = home();
    app.undo = Some(a_step());
    let mut r = Reply::new(Mark::Done, "theme set");
    r.undo = true;
    app.reply = Some(r);
    let (buf, drawn, pal) = draw(&mut app, 60, 40);
    let y = ui::status_y(40);
    let (a, b, _) = drawn.reply_undo.expect("undo at the row's right");
    assert_eq!(span(&buf, y, a, b), " undo ", "lowercase, the controls' brush");
    assert_eq!(buf[(a + 1, y)].fg, pal.fg, "in the text color, not boxed as a key");
    assert_eq!(buf[(a + 1, y)].bg, buf[(4, y)].bg, "no chip background");
}
