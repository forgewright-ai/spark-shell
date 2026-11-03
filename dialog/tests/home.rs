mod common;
use ratatui::{buffer::Buffer, layout::Rect};
use serde_json::json;
use spark_dialog::app::{App, Config, Helper, HintKey, Item, Mode, Sign, View, DESTS, HELP_DEST};

fn app() -> App {
    App::new(Config::default(), &[])
}

#[test]
fn root_is_complete_quiet_and_restores_selection() {
    let mut app = app();
    assert_eq!(app.title(), "home");
    assert!(!app.in_list && app.input.is_empty());
    let names: Vec<_> = app
        .items()
        .iter()
        .filter_map(|i| if let Item::Dest(d) = i { Some(DESTS[*d].name) } else { None })
        .collect();
    assert_eq!(
        names,
        ["Apps", "Files", "Workspace", "Notes", "Calendar", "Tools", "Settings", "Help", "About", "Power"]
    );
    app.light(HELP_DEST);
    app.enter();
    assert_eq!(app.view, View::Help);
    app.escape();
    assert_eq!(app.view, View::Home);
    assert!(app.in_list && app.sel == HELP_DEST);
}

#[test]
fn conversation_switching_retains_native_view_state() {
    let mut app = app();
    app.view = View::Dest(spark_dialog::app::CALENDAR_DEST);
    app.month_offset = 3;
    app.conversation();
    app.conversation();
    assert_eq!(app.month_offset, 3);

    app.view = View::Steps(0);
    app.steps_row = Some(
        spark_dialog::model::rows(r#"{"rows":[{"id":"fixture","text":"native row"}]}"#)
            .unwrap()
            .rows
            .remove(0),
    );
    app.conversation();
    app.say(Sign::Says, "a retained answer");
    app.conversation();
    assert_eq!(app.view, View::Steps(0));
    assert_eq!(app.steps_row.as_ref().unwrap().id, "fixture");
    assert!(!app.exchange_up(), "hidden conversation history is not cleared by a native view's Back");
}

#[test]
fn unmatched_enter_and_unavailable_ask_preserve_work() {
    let mut app = app();
    app.set_draft("explain this please");
    app.attachment = Some("/data/explicit.md".into());
    app.enter();
    assert!(app.jobs.is_empty() && app.pending.is_none());
    app.ask();
    assert!(app.jobs.is_empty() && app.pending.is_none());
    assert_eq!(app.input, "explain this please");
    assert_eq!(app.attachment.as_deref(), Some("/data/explicit.md"));
    assert!(app.reply.as_ref().unwrap().text.contains("No model"));
}

#[test]
fn ask_never_sends_forms_and_duplicate_sends_do_not_replace_drafts() {
    let mut app = app();
    app.model_name = Some("fixture".into());
    for mode in [
        Mode::Listening,
        Mode::Apply("model".into()),
        Mode::Pair {
            prov: 0,
            id: json!(1),
            message: "Code".into(),
            kind: "pin".into(),
        },
        Mode::Elicit {
            prov: 0,
            id: json!(2),
            message: "Secret".into(),
            fields: vec![("secret".into(), "string".into())],
            answers: Default::default(),
            at: 0,
        },
    ] {
        app.mode = mode;
        app.set_draft("private form value");
        app.ask();
        assert!(app.jobs.is_empty());
        assert_eq!(app.input, "private form value");
    }
    app.mode = Mode::Normal;
    app.set_draft("first request");
    app.ask();
    assert_eq!(app.view, View::Conversation);
    assert_eq!(app.jobs.len(), 1);
    app.set_draft("next draft");
    app.ask();
    assert_eq!(app.jobs.len(), 1);
    assert_eq!(app.input, "next draft");
    app.conversation();
    assert_eq!(app.view, View::Home);
    assert!(app.pending.is_some());
    app.conversation();
    assert_eq!(app.input, "next draft");
}

#[test]
fn full_answers_keep_lines_and_long_tokens_across_resize_and_navigation() {
    let mut app = app();
    app.model_name = Some("fixture".into());
    app.set_draft("explain");
    app.ask();
    let answer = format!("First paragraph.\n\n{}\nLAST LINE", "abcdefghij".repeat(50));
    app.helper(
        Helper::Want(app.want_serial),
        Ok(json!({"answer": answer, "steps": [], "refused": []}).to_string()),
    );
    assert_eq!(app.exchange.last().unwrap().text, answer);
    app.set_draft("unfinished follow-up");
    for size in [(60, 40), (36, 20), (120, 50), (60, 40)] {
        app.size = size;
        let lines: Vec<_> = app
            .items()
            .into_iter()
            .filter_map(|i| if let Item::Said(Sign::Says, text, _) = i { Some(text) } else { None })
            .collect();
        assert!(lines.last().unwrap().contains("LAST LINE"));
        assert_eq!(lines.join("").replace(' ', ""), answer.replace(['\n', ' '], ""));
        app.page(1);
        app.conversation();
        app.conversation();
        assert_eq!(app.input, "unfinished follow-up");
        assert!(app.scroll > 0);
    }
}

#[test]
fn configured_ask_is_visible_clickable_and_uses_the_same_action() {
    let mut app = app();
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"ask":"F4"}"#).unwrap();
    app.model_name = Some("fixture".into());
    app.set_draft("question");
    for size in [(36, 20), (60, 40)] {
        app.size = size;
        let mut buffer = Buffer::empty(Rect::new(0, 0, size.0, size.1));
        let drawn = spark_dialog::ui::draw(&app, &common::palette("tokyonight-night"), "", &mut buffer);
        let key = drawn.keys.iter().find(|(_, _, _, key)| *key == HintKey::Ask).unwrap();
        assert_eq!(key.2, 4);
        assert!(key.1 <= size.0);
        let row: String = (0..size.0).map(|x| buffer[(x, 4)].symbol()).collect();
        assert!(row.contains("Ask") && row.contains("F4") && !row.contains("Ctrl+Enter"));
    }
    app.hint_key(HintKey::Ask);
    assert!(app.pending.is_some() && app.jobs.len() == 1);
    app.cfg.progress = true;
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"ask":"Ctrl+Alt+Shift+Enter"}"#).unwrap();
    for size in [(36, 20), (60, 40)] {
        app.size = size;
        let mut buffer = Buffer::empty(Rect::new(0, 0, size.0, size.1));
        let drawn = spark_dialog::ui::draw(&app, &common::palette("tokyonight-night"), "", &mut buffer);
        let key = drawn.keys.iter().find(|(_, _, _, key)| *key == HintKey::Ask).unwrap();
        assert!(key.1 <= size.0 - 2, "progress yields space to the configured Ask key");
    }
}

#[test]
fn shared_frame_prioritizes_navigation_and_ask_with_a_configured_footer() {
    let mut app = App::new(
        Config {
            plus: true,
            model: true,
            talk: true,
            ..Config::default()
        },
        &["files".into()],
    );
    app.providers[0].ready = true;
    app.model_name = Some("fixture-model".into());
    app.voice_on = true;
    let palette = common::palette("tokyonight-night");
    for view in [View::Home, View::Conversation] {
        app.view = view;
        for size in [(60, 40), (36, 24)] {
            app.size = size;
            let mut buffer = Buffer::empty(Rect::new(0, 0, size.0, size.1));
            let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
            let row = |y| (0..size.0).map(|x| buffer[(x, y)].symbol()).collect::<String>();
            let hint = row(spark_dialog::ui::HINT_Y);
            assert!(hint.find("Esc").unwrap() < hint.find("Ask").unwrap());
            assert!(!hint.contains("Chat") && !hint.contains("F2"));
            assert!(drawn
                .keys
                .iter()
                .all(|(start, end, y, _)| start < end && *end <= size.0 - 2 && *y == spark_dialog::ui::HINT_Y));
            for chip in [0, 1, 3] {
                assert!(drawn.chips.iter().any(|(_, _, y, id)| *id == chip && *y == size.1 - 2));
            }
            assert_eq!(row(size.1 - 3).matches('\u{25c7}').count(), 1);
            if size.0 == 60 {
                assert!(row(size.1 - 2).contains("fixture-model \u{b7} local"));
            }
        }
    }
    app.view = View::Home;
    app.size = (60, 40);
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    let positions: Vec<_> = drawn.picks.iter().map(|(y, _)| *y).collect();
    assert!(positions[..6].windows(2).all(|ys| ys[1] - ys[0] == 2));
    assert!(positions[6] - positions[5] > positions[9] - positions[8]);
    assert_eq!(buffer[(spark_dialog::ui::PURPOSE_X, positions[0])].fg, palette.fg);

    app.set_draft("unfinished request");
    app.size = (36, 24);
    let mut buffer = Buffer::empty(Rect::new(0, 0, 36, 24));
    let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    assert!(drawn.keys.iter().any(|(_, _, y, k)| *k == HintKey::Ask && *y == spark_dialog::ui::HINT_Y));
    assert!(drawn.keys.iter().any(|(_, _, y, k)| *k == HintKey::Enter && *y == spark_dialog::ui::HINT_Y + 1));
    assert!(drawn.keys.iter().all(|(_, end, _, _)| *end <= 34));
}
