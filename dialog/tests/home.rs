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
        ["apps", "files", "Workspace", "Notes", "Calendar", "Tools", "Settings", "Help", "About", "Power"]
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
        assert!(row.contains("ask") && row.contains("F4") && !row.contains("Ctrl+Enter"));
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
            assert!(hint.find("Esc").unwrap() < hint.find("ask").unwrap());
            assert!(!hint.contains("chat") && !hint.contains("F2"));
            assert!(drawn
                .keys
                .iter()
                .all(|(start, end, y, _)| start < end && *end <= size.0 - 2 && *y == spark_dialog::ui::HINT_Y));
            for chip in [0, 1, 3] {
                assert!(drawn.chips.iter().any(|(_, _, y, id)| *id == chip && *y == size.1 - 2));
            }
            assert_eq!(row(size.1 - 4).matches('\u{25c7}').count(), 1);
            assert!(row(size.1 - 3).trim().is_empty(), "one full blank row above the controls");
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

fn footer_app() -> App {
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
    app
}

#[test]
fn model_selector_centers_beneath_the_diamond_in_both_views() {
    let palette = common::palette("tokyonight-night");
    let mut app = footer_app();
    for view in [View::Home, View::Conversation] {
        app.view = view;
        for width in [60, 61, 120] {
            app.size = (width, 40);
            let mut buffer = Buffer::empty(Rect::new(0, 0, width, 40));
            let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
            let &(start, end, y, _) = drawn.chips.iter().find(|(_, _, _, id)| *id == 1).unwrap();
            assert!((start + end - 1).abs_diff(2 * (width / 2)) <= 1, "selector centered within one cell");
            assert_eq!(buffer[(width / 2, 36)].symbol(), "\u{25c7}");
            let label: String = (start..end).map(|x| buffer[(x, y)].symbol()).collect();
            assert_eq!(label, " fixture-model \u{b7} local \u{2304} ");
        }
    }
}

#[test]
fn narrow_footer_reserves_controls_and_keeps_hit_areas_on_their_labels() {
    let palette = common::palette("tokyonight-night");
    let mut app = footer_app();
    app.model_name = Some("a-model-name-too-long-to-fit-in-the-footer".into());
    let wide = "\u{754c}".repeat(30);
    for file in ["a-very-long-attachment-name.md", wide.as_str()] {
        app.attachment = Some(format!("/data/{}", file));
        for mode in [Mode::Normal, Mode::Listening] {
            app.mode = mode;
            for width in 36..=80 {
                app.size = (width, 40);
                let mut buffer = Buffer::empty(Rect::new(0, 0, width, 40));
                let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
                let mut chips = drawn.chips.clone();
                chips.sort_by_key(|c| c.0);
                assert_eq!(chips.iter().map(|c| c.3).collect::<Vec<_>>(), [0, 4, 1, 3]);
                assert!(chips.windows(2).all(|cs| cs[0].1 < cs[1].0), "one cell between hit areas at {width}");
                for &(start, end, y, id) in &chips {
                    assert!(start >= 1 && start < end && end < width && y == 38);
                    let label: String = (start..end).map(|x| buffer[(x, y)].symbol()).collect();
                    match id {
                        0 => assert!(!label.trim().is_empty(), "an attachment remains visible"),
                        4 => assert_eq!(label, " remove "),
                        1 if width == 36 => assert_eq!(label, " model \u{2304} "),
                        3 => assert_eq!(label, if app.mode == Mode::Listening { " cancel " } else { " talk " }),
                        _ => {}
                    }
                }
            }
        }
    }
}

#[test]
fn conversation_shows_the_answer_once_and_keeps_other_feedback() {
    use spark_dialog::app::{Step, Who};
    use spark_dialog::model::Call;
    use spark_dialog::reply::Mark;
    let mut app = footer_app();
    app.set_draft("question");
    app.ask();
    app.helper(
        Helper::Want(app.want_serial),
        Ok(json!({"answer": "One complete answer.", "steps": [], "refused": []}).to_string()),
    );
    let palette = common::palette("tokyonight-night");
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    let row = |b: &Buffer, y| (0..60).map(|x| b[(x, y)].symbol()).collect::<String>();
    assert!(row(&buffer, spark_dialog::ui::REPLY_Y).trim().is_empty());
    let screen: String = (0..40).map(|y| row(&buffer, y)).collect();
    assert_eq!(screen.matches("One complete answer.").count(), 1);
    // Other feedback still belongs to the reply row, even when its text happens
    // to match the answer. Visibility follows its kind, not a text comparison.
    for mark in [Mark::Refused, Mark::Done, Mark::Note] {
        app.reply(mark, "One complete answer.");
        let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
        spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
        assert!(row(&buffer, spark_dialog::ui::REPLY_Y).contains("One complete answer."));
    }
    app.reply(Mark::Done, "action completed");
    app.reply.as_mut().unwrap().undo = true;
    app.undo = Some(Step {
        prov: 0,
        call: Call {
            name: "fixture_undo".into(),
            arguments: Default::default(),
            ask: vec![],
            said: None,
            pick: None,
        },
        who: Who::Undo,
        line: "undo".into(),
        typed: false,
    });
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    assert!(drawn.reply_undo.is_some());
    assert!(row(&buffer, spark_dialog::ui::REPLY_Y).contains("action completed"));
}

#[test]
fn an_answer_arriving_in_another_view_is_discoverable_without_switching_views() {
    let mut app = footer_app();
    app.set_draft("question");
    app.ask();
    app.conversation();
    assert_eq!(app.view, View::Home);
    app.set_draft("next draft");
    app.helper(
        Helper::Want(app.want_serial),
        Ok(json!({"answer": "An answer has arrived.", "steps": [], "refused": []}).to_string()),
    );
    assert_eq!(app.view, View::Home);
    assert_eq!(app.input, "next draft");
    let palette = common::palette("tokyonight-night");
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    let row: String = (0..60).map(|x| buffer[(x, spark_dialog::ui::REPLY_Y)].symbol()).collect();
    assert!(row.contains("An answer has arrived."));
    app.hint_key(HintKey::Conversation);
    assert_eq!(app.view, View::Conversation);
    assert_eq!(app.input, "next draft");
    assert!(app
        .items()
        .iter()
        .any(|item| matches!(item, Item::Said(Sign::Says, text, _) if text == "An answer has arrived.")));
}

#[test]
fn modules_share_frame_anchors_while_apps_keeps_a_bounded_body() {
    use spark_dialog::ui::{CONTENT_Y, HINT_Y, PROMPT_Y};
    let mut app = footer_app();
    let palette = common::palette("tokyonight-night");
    for size in [(60, 40), (68, 49), (140, 50), (36, 24)] {
        app.size = size;
        let (w, h) = size;
        let frame = w.min(120);
        let frame_left = (w - frame) / 2;
        let mut anchors = None;
        for view in [View::Home, View::Apps, View::Folder(0, "spark-shell://files/rows/home".into())] {
            app.view = view;
            let width = app.col_w();
            let body_left = if app.view == View::Apps { frame_left } else { (w - width) / 2 };
            let mut buffer = Buffer::empty(Rect::new(0, 0, w, h));
            let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
            assert_eq!(drawn.columns, (body_left, body_left + width));
            assert_eq!(buffer[(frame_left + 2, PROMPT_Y)].symbol(), "\u{276f}");
            assert_eq!(buffer[(frame_left + 2, h - 2)].symbol(), "a");
            assert_eq!(buffer[(w / 2, h - 4)].symbol(), "\u{25c7}");
            assert!((0..w).all(|x| buffer[(x, h - 3)].symbol().trim().is_empty()));
            assert!(drawn.chips.iter().all(|(a, b, _, _)| *a >= frame_left && *b <= frame_left + frame));
            let actual = (drawn.close, drawn.cursor, drawn.chips.clone());
            if let Some(expected) = &anchors {
                assert_eq!(&actual, expected, "shared frame at {size:?}");
            } else {
                anchors = Some(actual);
            }
            if app.view == View::Home {
                assert_eq!(buffer[(body_left + 2, CONTENT_Y)].symbol(), "a");
                assert_eq!(buffer[(body_left + width - 3, CONTENT_Y)].symbol(), "\u{203a}");
                assert_eq!(buffer[(frame_left + 2, HINT_Y)].symbol(), "c");
            }
        }
    }
}

#[test]
fn footer_reservation_keeps_the_last_destination_visible_and_clickable_after_resize() {
    let mut app = footer_app();
    app.light(DESTS.len() - 1);
    let palette = common::palette("tokyonight-night");
    for size in [(60, 40), (140, 50), (68, 49), (36, 20), (60, 40)] {
        app.size = size;
        let mut buffer = Buffer::empty(Rect::new(0, 0, size.0, size.1));
        let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
        let &(y, _) = drawn.picks.iter().find(|(_, pick)| *pick == DESTS.len() - 1).expect("Power remains navigable");
        assert!(y < size.1 - spark_dialog::ui::BOTTOM);
        let row: String = (0..size.0).map(|x| buffer[(x, y)].symbol()).collect();
        assert!(row.contains("Power"));
        assert!(drawn.picks.iter().all(|(y, _)| *y < size.1 - spark_dialog::ui::BOTTOM));
        assert_eq!(app.sel, DESTS.len() - 1);
        assert_eq!(app.view, View::Home);
    }
}

/// A pairing code or a password is no draft: leaving for the model list and
/// coming back keeps nothing of it.
#[test]
fn an_answer_to_a_question_is_never_kept_as_a_draft() {
    let mut app = app();
    let here = View::Dest(spark_dialog::app::CALENDAR_DEST);
    app.view = here.clone();
    app.mode = Mode::Pair {
        prov: 0,
        id: json!(1),
        message: "the code".into(),
        kind: "pin".into(),
    };
    app.set_draft("123456");
    app.chip(1);
    assert_eq!(app.view, View::Models);
    app.escape();
    assert_eq!(app.mode, Mode::Normal);
    app.escape();
    assert_eq!(app.view, here);
    assert!(app.input.is_empty(), "the code came back as words: {}", app.input);
}

/// open_preview clears the prompt so the preview's keys work (#163): the
/// request draft stays the request's and never lands in a preview.
#[test]
fn a_preview_opens_clear_of_the_request_draft() {
    use spark_dialog::interaction::Prompts;
    let mut prompts = Prompts::default();
    prompts.save(&View::Home, "files");
    assert_eq!(prompts.restore(&View::Preview), "");
    prompts.save(&View::Preview, "");
    assert_eq!(prompts.restore(&View::Home), "files");
}

/// A motion draws and nothing more: Enter stays with the words typed.
#[test]
fn a_motion_outside_apps_leaves_enter_with_the_words() {
    let mut app = app();
    app.set_draft("open the notes");
    app.pointer_over(Some(2));
    assert!(!app.in_list, "a stray motion took Enter from the words");
    assert_eq!(app.sel, 0);
    app.view = View::Dest(spark_dialog::app::CALENDAR_DEST);
    app.scroll = 14;
    app.pointer_over(Some(3));
    assert_eq!(app.scroll, 14, "a motion moved the list");
}
