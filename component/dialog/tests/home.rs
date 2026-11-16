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
        ["apps", "files", "workspace", "notes", "calendar", "tools", "settings", "help", "about", "power"]
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
    assert!(app.reply.as_ref().unwrap().text.contains("no model"));
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
fn a_configured_ask_key_asks_and_has_no_chip() {
    // asking is a row, not a key (the dialog design notes): the configured key still asks, and no chip names it
    let mut app = app();
    app.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"ask":"F4"}"#).unwrap();
    app.model_name = Some("fixture".into());
    app.set_draft("question");
    for size in [(36, 20), (60, 40)] {
        app.size = size;
        let mut buffer = Buffer::empty(Rect::new(0, 0, size.0, size.1));
        let drawn = spark_dialog::ui::draw(&app, &common::palette("tokyonight-night"), "", &mut buffer);
        assert!(drawn.keys.iter().all(|(_, _, _, key)| *key != HintKey::Ask), "no Ask chip: {:?}", drawn.keys);
        let bar: String = (0..size.0).map(|x| buffer[(x, spark_dialog::ui::keys_y(size.1))].symbol()).collect();
        assert!(!bar.contains("F4") && !bar.contains("Ctrl+Enter"), "{:?}", bar);
    }
    app.hint_key(HintKey::Ask);
    assert!(app.pending.is_some() && app.jobs.len() == 1);
}

#[test]
fn the_frame_is_one_shape_at_the_top_and_the_bottom_in_both_views() {
    use spark_dialog::ui::{head, keys_y};
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
            // the key bar at the bottom: the view's keys alone, Esc first, no Enter and no Ask among them
            let bar = row(keys_y(size.1));
            assert!(bar.contains("Esc"), "{:?}", bar);
            assert!(
                !bar.contains("ask") && !bar.contains("Enter") && !bar.contains("chat") && !bar.contains("F2"),
                "{:?}",
                bar
            );
            assert!(drawn
                .keys
                .iter()
                .all(|(start, end, y, _)| start < end && *end <= size.0 - 2 && (*y == keys_y(size.1) || *y == size.1 - 1)));
            // what else the line takes stands on the line: attach and talk, and no control for the model
            let line = head(&app).prompt;
            for chip in [0, 3] {
                assert!(drawn.chips.iter().any(|(_, _, y, id)| *id == chip && *y == line), "control {chip} on the line");
            }
            assert!(drawn.chips.iter().all(|(_, _, _, id)| *id != 1), "the model has no control in the head");
            assert!(row(line).contains(" attach ") && row(line).contains(" talk "), "{:?}", row(line));
            assert!(!row(line).contains("fixture-model"), "the model is named where it answers: {:?}", row(line));
            // the line is the whole head: air under it, then the list, and no rule with a sign above the list
            assert!(row(line + 1).trim().is_empty(), "a row of air between the line and the list");
            assert_eq!(head(&app).content, line + 2);
            for y in 0..head(&app).content {
                assert_eq!(
                    row(y).matches(['\u{2500}', '\u{25c7}', '\u{25c6}']).count(),
                    0,
                    "no rule above the list: {:?}",
                    row(y)
                );
            }
            assert_eq!(row(size.1 - 4).matches(['\u{25c7}', '\u{25c6}']).count(), 0, "the bottom rule is plain");
            assert!(row(size.1 - 3).trim().is_empty(), "one full blank row above the keys");
        }
    }
    app.view = View::Home;
    app.size = (60, 40);
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    let positions: Vec<_> = drawn.picks.iter().map(|(y, _)| *y).collect();
    assert!(
        positions[..6].windows(2).all(|ys| ys[1] - ys[0] == 2),
        "a row of air between the rows: {:?}",
        positions
    );
    assert_eq!(positions[6] - positions[5], 3, "two rows of air before settings: {:?}", positions);
    assert_eq!(positions[9] - positions[8], 3, "and before power: {:?}", positions);
    assert_eq!(buffer[(spark_dialog::ui::PURPOSE_X, positions[0])].fg, palette.muted, "a purpose is muted");

    app.set_draft("unfinished request");
    app.size = (36, 24);
    let mut buffer = Buffer::empty(Rect::new(0, 0, 36, 24));
    let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
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
fn a_new_try_at_talk_clears_the_last_refusal() {
    // the dialog design notes (v0.124.3): nothing heard stood on the status row through the next try with the mic connected
    let mut app = footer_app();
    app.refuse("nothing heard");
    assert!(app.reply.is_some());
    app.chip(3);
    assert_eq!(app.mode, Mode::Listening);
    assert!(app.reply.is_none(), "the status row is clear for the new try");
}

#[test]
fn the_model_has_no_control_in_the_head_in_both_views() {
    // the model is named where it answers (the ask row, the conversation's band), so the head offers attach and
    // talk alone at every width; the model's own place is reached from settings
    let palette = common::palette("tokyonight-night");
    let mut app = footer_app();
    for view in [View::Home, View::Conversation] {
        app.view = view;
        for width in [36, 60, 61, 120] {
            app.size = (width, 40);
            let mut buffer = Buffer::empty(Rect::new(0, 0, width, 40));
            let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
            let line = spark_dialog::ui::head(&app).prompt;
            assert_eq!(drawn.chips.iter().map(|c| c.3).collect::<Vec<_>>(), [0, 3], "attach, then talk, at {width}");
            assert!(drawn.chips.iter().all(|c| c.2 == line), "both on the line at {width}");
            let words: String = (0..width).map(|x| buffer[(x, line)].symbol()).collect();
            assert!(!words.contains("fixture-model") && !words.contains("model"), "{:?}", words);
        }
    }
    assert_eq!(app.chips(), [0, 3], "Tab moves through attach and talk");
}

#[test]
fn the_line_keeps_its_controls_whole_and_the_draft_its_room_at_every_width() {
    use spark_dialog::ui::{head, DRAFT_MIN};
    let palette = common::palette("tokyonight-night");
    let mut app = footer_app();
    let wide = "\u{754c}".repeat(30);
    for file in ["a-very-long-attachment-name.md", wide.as_str()] {
        app.attachment = Some(format!("/data/{}", file));
        for mode in [Mode::Normal, Mode::Listening] {
            app.mode = mode;
            for width in 36..=80 {
                app.size = (width, 40);
                let mut buffer = Buffer::empty(Rect::new(0, 0, width, 40));
                let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
                let line = head(&app).prompt;
                let mut chips = drawn.chips.clone();
                chips.sort_by_key(|c| c.0);
                assert_eq!(chips.iter().map(|c| c.3).collect::<Vec<_>>(), [0, 4, 3], "the file, remove, talk at {width}");
                // each control's pad is its own, so two may touch: a click lands on one and one only
                assert!(chips.windows(2).all(|cs| cs[0].1 <= cs[1].0), "no hit area over another at {width}");
                // a long name never takes the draft's room: the prompt's words start at column 4
                assert!(chips[0].0 >= 4 + 1 + DRAFT_MIN, "the draft keeps {DRAFT_MIN} cells at {width}: {:?}", chips);
                for &(start, end, y, id) in &chips {
                    assert!(start < end && end < width && y == line, "{:?} at {width}", (start, end, y, id));
                    let label: String = (start..end).map(|x| buffer[(x, y)].symbol()).collect();
                    match id {
                        0 => assert!(!label.trim().is_empty(), "an attachment remains visible at {width}"),
                        4 => assert_eq!(label, " remove "),
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
    assert!(row(&buffer, spark_dialog::ui::status_y(40)).trim().is_empty());
    let screen: String = (0..40).map(|y| row(&buffer, y)).collect();
    assert_eq!(screen.matches("One complete answer.").count(), 1);
    // Other feedback still belongs to the reply row, even when its text happens
    // to match the answer. Visibility follows its kind, not a text comparison.
    for mark in [Mark::Refused, Mark::Done, Mark::Note] {
        app.reply(mark, "One complete answer.");
        let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
        spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
        assert!(row(&buffer, spark_dialog::ui::status_y(40)).contains("One complete answer."));
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
            value: None,
            children: None,
        },
        who: Who::Undo,
        line: "undo".into(),
        typed: false,
    });
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    let drawn = spark_dialog::ui::draw(&app, &palette, "", &mut buffer);
    assert!(drawn.reply_undo.is_some());
    assert!(row(&buffer, spark_dialog::ui::status_y(40)).contains("action completed"));
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
    let row: String = (0..60).map(|x| buffer[(x, spark_dialog::ui::status_y(40))].symbol()).collect();
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
        assert!(row.contains("power"), "{:?}", row);
        assert!(drawn.picks.iter().all(|(y, _)| *y < size.1 - spark_dialog::ui::BOTTOM));
        assert_eq!(app.sel, DESTS.len() - 1);
        assert_eq!(app.view, View::Home);
    }
}

/// A pairing code or a password is no draft: leaving for the model list and
/// coming back keeps nothing of it.
#[test]
fn an_answer_to_a_question_is_never_kept_as_a_draft() {
    // while a code is being typed nothing in the frame leaves the page: the line's controls and the conversation
    // key wait for the answer, so the code stays in the open question alone, and Esc leaves the prompt empty.
    // (The guard on saved drafts is pinned in interaction.rs, whatever doors the frame has.)
    type Door = (&'static str, fn(&mut App));
    let doors: [Door; 5] = [
        ("attach", |a| a.chip(0)),
        ("the model's old control", |a| a.chip(1)),
        ("talk", |a| a.chip(3)),
        ("the conversation key", |a| a.hint_key(HintKey::Conversation)),
        ("the actions key", |a| a.hint_key(HintKey::Actions)),
    ];
    for (name, door) in doors {
        let mut app = footer_app();
        let here = View::Dest(spark_dialog::app::CALENDAR_DEST);
        app.view = here.clone();
        app.mode = Mode::Pair {
            prov: 0,
            id: json!(1),
            message: "the code".into(),
            kind: "pin".into(),
        };
        app.set_draft("123456");
        door(&mut app);
        assert_eq!(app.view, here, "{name} leaves the page while a code is being typed");
        assert!(matches!(app.mode, Mode::Pair { .. }), "{name} ended the question");
        assert_eq!(app.input, "123456", "{name} took the answer being typed");
        app.escape();
        assert_eq!((app.mode.clone(), app.view.clone()), (Mode::Normal, here), "Esc ends the question, on its page");
        assert!(app.input.is_empty(), "the code came back as words after {name}: {}", app.input);
    }
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

/// Ctrl+C ends the dialog at once, and says so to the caller as a signal would.
#[test]
fn ctrl_c_is_the_way_out_with_a_signals_code() {
    let mut app = app();
    app.hint_key(HintKey::Quit);
    assert_eq!(app.quit, Some(130));
}
