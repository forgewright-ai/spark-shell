mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{App, Helper, Job, Mode, View};
use spark_dialog::task::Phase;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn started(risky: bool) -> (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>, Arc<Mutex<Vec<Value>>>) {
    let (mut app, rx, tx) = app_with(&["out", "notes"]);
    let calls = Arc::new(Mutex::new(vec![]));
    let captured = calls.clone();
    let tools = json!([{"name": "out_level", "title": "out level N", "description": "Set output volume from 0 to 100.",
        "inputSchema": {"type": "object", "properties": {"level": {"type": "integer", "minimum": 0, "maximum": 100}}, "required": ["level"]},
        "annotations": {"destructiveHint": risky}}]);
    let rows = json!({"title": "Sound", "state": "volume 70", "rows": [{"id": "volume", "sign": "check", "text": "volume 70",
        "tool": {"name": "out_level", "arguments": {"level": 70}},
        "step": {"value":70,"less":{"name":"out_level","arguments":{"level":60}},"more":{"name":"out_level","arguments":{"level":80}}}}]});
    let script: Script = Box::new(move |v, send| {
        if let Some(r) = ordinary("out", v, &tools, &rows) {
            return send(r);
        }
        if v["method"] == "spark/prepare" {
            return send(result(&v["id"], json!({"ready":true, "arguments":{"level":25}})));
        }
        if v["method"] == "tools/call" {
            captured.lock().unwrap().push(v["params"].clone());
            if v["params"]["arguments"]["level"] == 40 {
                return send(result(
                    &v["id"],
                    json!({"isError":true,"content":[{"type":"text","text":"output unavailable"}]}),
                ));
            }
            send(result(
                &v["id"],
                json!({"isError": false, "content": [{"type": "text", "text": "volume 30"}],
                "structuredContent": {"receipt": "volume 30", "actual_level": 30,
                "undo":{"name":"out_level","arguments":{"level":70}}}}),
            ));
        }
    });
    app.servers.push(stub(0, "out", script, tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.view = View::Section(0);
    app.providers[1].ready = true;
    app.providers[1].rows = spark_dialog::model::rows(r#"{"title":"Notes","rows":[{"id":"private","text":"hidden note title"}]}"#).unwrap();
    app.jobs.clear();
    (app, rx, calls)
}

fn request(app: &App) -> (u64, Value) {
    app.jobs
        .iter()
        .rev()
        .find_map(|j| match j {
            Job::RunInput(Helper::Task(id), argv, data) => {
                assert_eq!(&argv[1..], &["do", "--tools"]);
                Some((*id, serde_json::from_str(data).unwrap()))
            }
            _ => None,
        })
        .expect("a task request")
}

fn propose(app: &mut App) {
    let (serial, _) = request(app);
    let step = json!({"name": "p0_out_level", "arguments": {"level": 30}});
    let pending = json!({"id": 1, "kind": "step", "step": step});
    let state = json!({"version": 1, "goal": "make it quieter", "turn": 1, "history": [], "pending": pending, "closed": false});
    app.task_reply(
        serial,
        Ok(json!({"version": 1, "id": 1, "status": "step", "step": step, "state": state}).to_string()),
    );
}

fn type_words(app: &mut App, words: &str) {
    for c in words.chars() {
        app.typed(c);
    }
}

fn ask_output(app: &mut App) {
    let (id, _) = request(app);
    app.task_reply(
        id,
        Ok(json!({"version": 1, "status": "ask", "id": 1,
        "question": "Which output?", "state": {"version": 1, "goal": "make it quieter",
        "pending": {"id": 1, "kind": "ask", "question": "Which output?"}}})
        .to_string()),
    );
}

#[test]
fn keyboard_request_keeps_the_explicit_target() {
    let (mut app, _, _) = started(false);
    app.down();
    assert!(app.in_list);
    type_words(&mut app, "make this quieter");
    app.enter();
    assert_eq!(request(&app).1["context"]["selected"]["id"], "volume");
}

#[test]
fn editing_a_proposal_keeps_the_target_for_the_replacement_request() {
    let (mut app, _, calls) = started(false);
    app.down();
    type_words(&mut app, "make this quieter");
    app.enter();
    propose(&mut app);
    while !app.input.is_empty() {
        app.backspace();
    }
    type_words(&mut app, "make that a little quieter instead");
    app.enter();
    assert_eq!(request(&app).1["context"]["selected"]["id"], "volume");
    assert!(app.staged.is_none());
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn keyboard_answer_cannot_run_a_matching_row() {
    let (mut app, rx, calls) = started(false);
    app.task_start("make it quieter");
    ask_output(&mut app);
    app.jobs.clear();
    type_words(&mut app, "volume 70");
    app.enter();
    assert!(pump(&mut app, &rx, |a| !a.jobs.is_empty() || !calls.lock().unwrap().is_empty()));
    assert!(calls.lock().unwrap().is_empty(), "an answer must not run the matching row");
    assert_eq!(request(&app).1["answer"], "volume 70");
}

#[test]
fn task_hints_describe_answering_and_stopping() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    assert!(app.hint().iter().any(|(s, _)| s.trim() == "Stop"));
    ask_output(&mut app);
    assert!(app.hint().iter().any(|(s, _)| s.trim() == "Answer"));
    assert!(app.hint().iter().any(|(s, _)| s.trim() == "Stop"));
}

#[test]
fn pasted_answer_and_pointer_pick_belong_to_the_question() {
    for pointer in [false, true] {
        let (mut app, _, calls) = started(false);
        app.task_start("make it quieter");
        ask_output(&mut app);
        app.jobs.clear();
        if pointer {
            app.down();
            assert!(app.in_list);
            app.left();
            app.right();
        } else {
            app.paste("volume 70");
            assert!(app.jobs.is_empty());
        }
        app.hint_key(spark_dialog::app::HintKey::Enter);
        assert_eq!(request(&app).1["answer"], "volume 70");
        assert!(calls.lock().unwrap().is_empty());
    }
}

#[test]
fn target_survives_reordering_but_not_removal_or_navigation() {
    let (mut app, _, _) = started(false);
    app.down();
    app.focus_prompt();
    app.paste("make this quieter");
    let mut other = app.providers[0].rows.rows[0].clone();
    other.id = "other".into();
    app.providers[0].rows.rows.insert(0, other);
    app.enter();
    assert_eq!(request(&app).1["context"]["selected"]["id"], "volume");
    app.providers[0].rows.rows.retain(|r| r.id != "volume");
    propose(&mut app);
    assert!(app.task.is_none());
    assert!(app.staged.is_none());
    assert!(app.exchange.last().unwrap().text.contains("no longer available"));
    let (mut app, _, _) = started(false);
    app.down();
    type_words(&mut app, "notes");
    app.enter();
    assert_eq!(app.view, View::Section(1));
    assert!(app.target.is_none());
}

#[test]
fn disappearing_target_is_checked_again_on_enter() {
    let (mut app, _, calls) = started(false);
    app.down();
    type_words(&mut app, "make this quieter");
    app.enter();
    propose(&mut app);
    app.providers[0].rows.rows.clear();
    app.enter();
    assert!(calls.lock().unwrap().is_empty());
    assert!(app.task.is_none());
}

#[test]
fn disappearing_target_is_checked_again_after_yes() {
    let (mut app, _, calls) = started(true);
    app.down();
    type_words(&mut app, "make this quieter");
    app.enter();
    propose(&mut app);
    app.enter();
    app.providers[0].rows.rows.clear();
    type_words(&mut app, "yes");
    app.enter();
    assert!(calls.lock().unwrap().is_empty());
    assert!(app.task.is_none());
}

#[test]
fn navigation_stops_the_task_and_ignores_its_late_proposal() {
    for confirming in [false, true] {
        let (mut app, _, calls) = started(confirming);
        app.cfg.model = true;
        app.down();
        type_words(&mut app, "make this quieter");
        app.enter();
        let (serial, _) = request(&app);
        if confirming {
            propose(&mut app);
            app.enter();
            assert!(matches!(app.mode, Mode::Confirm(_)));
        }
        app.chip(1);
        assert_eq!(app.view, View::Models);
        assert!(app.task.is_none());
        assert_eq!(app.mode, Mode::Normal);
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"ask","id":1,"question":"late","state":{"pending":{"id":1}}}).to_string()),
        );
        assert!(app.task.is_none());
        assert!(calls.lock().unwrap().is_empty());
    }
}

#[test]
fn stopping_during_an_action_keeps_its_receipt_without_continuing() {
    let (mut app, rx, calls) = started(false);
    app.task_start("make it quieter");
    propose(&mut app);
    app.enter();
    app.escape();
    assert!(app.exchange.last().unwrap().text.contains("may still finish"));
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert_eq!(calls.lock().unwrap().len(), 1);
    assert!(app.task.is_none());
    assert!(app.exchange.iter().any(|l| l.sign == spark_dialog::app::Sign::Done && l.text == "volume 30"));
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::RunInput(..))));
}

#[test]
fn an_opened_window_closes_the_dialog_when_the_task_finishes() {
    let (mut app, _, _) = started(false);
    app.task_start("open the app");
    app.opened = true;
    let (id, _) = request(&app);
    app.task_reply(id, Ok(json!({"version":1,"status":"done","summary":"opened"}).to_string()));
    assert_eq!(app.quit, Some(3));
}

#[test]
fn a_partial_failure_stays_visible_after_an_earlier_open() {
    let (mut app, _, _) = started(false);
    app.task_start("open the app then finish the task");
    app.opened = true;
    let (id, _) = request(&app);
    app.task_reply(
        id,
        Ok(json!({"version":1,"status":"blocked","summary":"the next action is unavailable"}).to_string()),
    );
    assert_eq!(app.quit, None);
    assert!(!app.opened);
    assert_eq!(app.exchange.last().unwrap().sign, spark_dialog::app::Sign::Refused);
}

#[test]
fn partial_completion_keeps_the_first_receipt_and_its_undo() {
    let (mut app, rx, calls) = started(false);
    app.task_start("change the output in two steps");
    propose(&mut app);
    app.jobs.clear();
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && !a.jobs.is_empty()));
    assert_eq!(app.undo.as_ref().unwrap().call.arguments["level"], 70);
    let (serial, _) = request(&app);
    let step = json!({"name":"p0_out_level","arguments":{"level":40}});
    app.task_reply(
        serial,
        Ok(json!({"version":1,"status":"step","id":2,"step":step,
        "state":{"pending":{"id":2,"kind":"step","step":step}}})
        .to_string()),
    );
    assert_eq!(calls.lock().unwrap().len(), 1);
    app.jobs.clear();
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none() && !a.jobs.is_empty()));
    assert_eq!(request(&app).1["observation"]["status"], "error");
    let (serial, _) = request(&app);
    app.task_reply(serial, Ok(json!({"version":1,"status":"blocked","summary":"output unavailable"}).to_string()));
    assert!(app.exchange.iter().any(|l| l.sign == spark_dialog::app::Sign::Done && l.text == "volume 30"));
    assert_eq!(app.undo.as_ref().unwrap().call.arguments["level"], 70);
    app.paste("undo");
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 3));
    assert_eq!(calls.lock().unwrap()[2]["arguments"]["level"], 70);
}

#[test]
fn a_lost_target_provider_cancels_thinking_without_another_request() {
    let (mut app, _, _) = started(false);
    app.down();
    type_words(&mut app, "make this quieter");
    app.enter();
    let (serial, _) = request(&app);
    app.incoming(spark_dialog::mcp::Incoming::Gone(0, "closed".into()));
    app.task_reply(
        serial,
        Ok(json!({"version":1,"status":"ask","id":1,"question":"late","state":{"pending":{"id":1}}}).to_string()),
    );
    assert!(app.task.is_none());
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::RunInput(..))));
}

#[test]
fn a_lost_unselected_provider_cancels_a_calendar_task() {
    let (mut app, _, _) = started(false);
    app.providers[0].label = "clock".into();
    app.view = View::Dest(spark_dialog::app::CALENDAR_DEST);
    app.task_start("what is next");
    assert!(app.target.is_none());
    app.incoming(spark_dialog::mcp::Incoming::Gone(0, "closed".into()));
    assert!(app.task.is_none());
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::RunInput(..))));
}

fn render_task(app: &App, name: &str) {
    let Ok(dir) = std::env::var("TASK_RENDER_DIR") else { return };
    for look in ["tokyonight-night", "solarized-light"] {
        let pal = palette(look);
        let mut b = ratatui::buffer::Buffer::empty(ratatui::layout::Rect::new(0, 0, app.size.0, app.size.1));
        spark_dialog::ui::draw(app, &pal, "Wed 28 Oct  10:00", &mut b);
        let html = format!(
            "<!doctype html><meta charset=\"utf-8\"><style>body{{margin:20px;background:#808080;font:16px Menlo,monospace}}</style>{}",
            html_runs(&b, &pal, name, "")
        );
        std::fs::write(format!("{dir}/{name}-{look}.html"), html).unwrap();
    }
}

#[test]
fn task_interaction_renders() {
    if std::env::var("TASK_RENDER_DIR").is_err() {
        return;
    }
    let (mut app, _, _) = started(false);
    app.down();
    type_words(&mut app, "make this quieter");
    render_task(&app, "target");
    app.enter();
    render_task(&app, "thinking");
    ask_output(&mut app);
    type_words(&mut app, "volume 70");
    render_task(&app, "question");
    app.size = (36, 20);
    render_task(&app, "question-small");
    app.size = (60, 40);
    app.escape();
    app.task_start("make it quieter");
    propose(&mut app);
    render_task(&app, "proposal");
    app.escape();
    render_task(&app, "stopped");
}

#[test]
fn contextual_request_preserves_semantics_and_does_not_volunteer_hidden_data() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    let (_, req) = request(&app);
    assert!(req["context"]["clock"].as_str().unwrap().contains('T'));
    assert_eq!(req["context"]["visible"][0]["provider"], 0);
    assert!(req["tools"][0]["description"].as_str().unwrap().contains("0 to 100"));
    assert!(!req.to_string().contains("hidden note title"));
}

#[test]
fn discovery_describes_domains_from_home_models_and_unrelated_views() {
    for view in [View::Home, View::Models, View::Dest(spark_dialog::app::SETTINGS_DEST), View::Section(1)] {
        let (mut app, _, calls) = started(false);
        app.view = view;
        // Dynamic provider titles and rows can contain private native state.
        app.providers[0].title = "private output device".into();
        app.providers[0].rows.state = Some("private volume state".into());
        app.task_start("Increase the volume a little bit please.");
        let (_, req) = request(&app);
        let sound = &req["context"]["providers"][0];
        assert_eq!(sound["name"], "out");
        assert_eq!(sound["title"], "Sound");
        assert_eq!(sound["description"], "Output and volume");
        assert!(!req.to_string().contains("private output device"));
        assert!(!req.to_string().contains("private volume state"));
        assert!(req["tools"].as_array().unwrap().is_empty(), "discovery grants no native tool");
        assert!(calls.lock().unwrap().is_empty());
    }
}

#[test]
fn typing_a_request_in_models_sends_it_instead_of_picking_a_model() {
    let (mut app, _, _) = started(false);
    app.view = View::Models;
    app.models = vec![("local-model".into(), "downloaded".into())];
    type_words(&mut app, "Increase the volume a little bit please.");
    app.enter();
    assert_eq!(request(&app).1["context"]["view"], "model");
    assert_eq!(app.mode, Mode::Normal);
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::Run(Helper::ModelSet, _))));
}

#[test]
fn keyboard_model_selection_still_requires_explicit_choice_and_confirmation() {
    let (mut app, _, _) = started(false);
    app.view = View::Models;
    app.models = vec![("local-model".into(), "downloaded".into())];
    app.down();
    app.enter();
    assert!(matches!(app.mode, Mode::Apply(_)));
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::Run(Helper::ModelSet, _))));
    app.enter();
    assert!(app
        .jobs
        .iter()
        .any(|j| matches!(j, Job::Run(Helper::ModelSet, argv) if argv.last().is_some_and(|v| v == "local-model"))));
    assert!(app.task.is_none());
}

#[test]
fn discovery_distinguishes_sound_microphone_and_display_and_omits_unavailable_domains() {
    let (mut app, _, _) = app_with(&["out", "mic", "display", "files", "wifi", "bt", "custom"]);
    for p in &mut app.providers {
        p.ready = true;
    }
    app.providers[4].ready = false;
    app.providers[5].dead = Some("gone".into());
    app.providers[6].title = "private custom state".into();
    app.view = View::Models;
    app.task_start("Increase the volume a little bit please.");
    let (_, req) = request(&app);
    let providers = req["context"]["providers"].as_array().unwrap();
    assert_eq!(providers.len(), 4);
    assert_eq!(providers[0]["title"], "Sound");
    assert_eq!(providers[1]["title"], "Microphone");
    assert_eq!(providers[2]["description"], "Screens, brightness, lock");
    assert_eq!(providers[3]["title"], "Custom");
    assert!(providers[3]["description"].is_null());
    assert!(!req.to_string().contains("private custom state"));
    assert!(req["context"]["visible"].as_array().unwrap().is_empty());
}

#[test]
fn action_waits_for_enter_and_actual_structured_result_drives_next_turn() {
    let (mut app, rx, calls) = started(false);
    app.task_start("make it quieter");
    propose(&mut app);
    assert!(calls.lock().unwrap().is_empty());
    assert!(app.staged.is_some());
    app.jobs.clear();
    app.enter();
    assert!(pump(&mut app, &rx, |a| !a.jobs.is_empty()));
    assert_eq!(calls.lock().unwrap().len(), 1);
    let (_, req) = request(&app);
    assert_eq!(req["observation"]["result"]["structuredContent"]["actual_level"], 30);
    assert_eq!(req["observation"]["id"], 1);
    assert_eq!(req["state"]["goal"], "make it quieter");
}

#[test]
fn typed_command_needs_no_inference() {
    let (mut app, rx, calls) = started(false);
    app.input = "out level 30".into();
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert!(app.jobs.is_empty());
    assert!(app.task.is_none());
}

#[test]
fn an_early_direct_command_waits_for_its_provider_instead_of_using_ai() {
    let (mut app, rx, calls) = started(false);
    app.view = View::Home;
    let tools = std::mem::take(&mut app.providers[0].tools);
    app.providers[0].ready = false;
    app.providers[0].reading = true;
    type_words(&mut app, "out level 30");
    app.enter();
    assert_eq!(app.input, "out level 30");
    assert!(app.task.is_none() && app.jobs.is_empty() && calls.lock().unwrap().is_empty());
    app.providers[0].tools = tools;
    app.providers[0].ready = true;
    app.providers[0].reading = false;
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert!(app.task.is_none() && app.jobs.is_empty());
}

#[test]
fn model_cannot_bypass_destructive_confirmation() {
    let (mut app, _, calls) = started(true);
    app.task_start("make it quieter");
    propose(&mut app);
    app.enter();
    assert!(matches!(app.mode, Mode::Confirm(_)));
    assert!(calls.lock().unwrap().is_empty());
    app.input = "no".into();
    app.enter();
    assert!(calls.lock().unwrap().is_empty());
    assert!(app.task.is_none());
}

#[test]
fn cancellation_invalidates_late_model_reply() {
    let (mut app, _, calls) = started(false);
    app.task_start("make it quieter");
    let (id, _) = request(&app);
    app.escape();
    app.task_reply(
        id,
        Ok(json!({"version": 1, "status": "ask", "id": 1, "question": "Which output?", "state": {"pending": {"id": 1}}}).to_string()),
    );
    assert!(app.task.is_none());
    assert!(app.staged.is_none());
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn question_answer_keeps_original_goal() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    let (id, _) = request(&app);
    app.task_reply(
        id,
        Ok(json!({"version": 1, "status": "ask", "id": 1, "question": "Which output?",
        "state": {"version": 1, "goal": "make it quieter", "pending": {"id": 1, "kind": "ask", "question": "Which output?"}}})
        .to_string()),
    );
    app.input = "speakers".into();
    app.enter();
    let (_, req) = request(&app);
    assert_eq!(req["answer"], "speakers");
    assert_eq!(req["state"]["goal"], "make it quieter");
}

#[test]
fn inspection_reads_provider_state_without_mutation() {
    let (mut app, rx, calls) = started(false);
    app.view = View::Home;
    app.task_start("what is the volume");
    let (id, first) = request(&app);
    assert!(first["tools"].as_array().unwrap().is_empty(), "home offers domain discovery");
    app.jobs.clear();
    app.task_reply(
        id,
        Ok(json!({"version": 1, "status": "inspect", "id": 1, "provider": 0,
        "state": {"pending": {"id": 1, "kind": "inspect", "provider": 0}}})
        .to_string()),
    );
    assert!(pump(&mut app, &rx, |a| !a.jobs.is_empty()));
    let (_, req) = request(&app);
    assert_eq!(req["observation"]["result"]["structuredContent"]["state"], "volume 70");
    assert!(!req["tools"].as_array().unwrap().is_empty());
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn timeout_ends_task_without_retrying() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    propose(&mut app);
    app.enter();
    app.jobs.clear();
    app.tick(Instant::now() + Duration::from_secs(130));
    assert!(app.task.is_none());
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::RunInput(..))));
}

#[test]
fn completion_prose_does_not_get_a_native_success_mark() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    let (id, _) = request(&app);
    app.task_reply(
        id,
        Ok(json!({"version": 1, "status": "done", "summary": "completed", "evidence": [1]}).to_string()),
    );
    assert_eq!(app.exchange.last().unwrap().sign, spark_dialog::app::Sign::Says);
    assert!(app.task.is_none());
}

#[test]
fn helper_uses_stdin_and_preserves_json_on_a_nonzero_exit() {
    let output = spark_dialog::task::invoke(
        &["/bin/sh".into(), "-c".into(), "cat; exit 2".into()],
        json!({"version": 1, "status": "blocked", "summary": "unavailable"}).to_string(),
    )
    .unwrap();
    assert_eq!(serde_json::from_str::<Value>(&output).unwrap()["status"], "blocked");
    assert!(spark_dialog::task::invoke(&["/bin/cat".into()], "x".repeat(262145)).is_err());
}

#[test]
fn ordinary_action_supersedes_a_pending_model_request() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    assert_eq!(app.task.as_ref().unwrap().phase, Phase::Thinking);
    app.input = "out level 20".into();
    app.enter();
    assert!(app.task.is_none());
}

#[test]
fn declared_output_schema_rejects_a_false_receipt_after_execution() {
    let (mut app, rx, calls) = started(false);
    app.providers[0].tools[0].output_schema = Some(json!({"type":"object", "properties":{"actual_level":{"type":"string"}}, "required":["actual_level"]}));
    app.task_start("make it quieter");
    propose(&mut app);
    app.jobs.clear();
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert_eq!(calls.lock().unwrap().len(), 1);
    assert!(app.task.is_none());
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::RunInput(..))));
    assert!(app.exchange.iter().any(|l| l.text.contains("may have happened")));
}

#[test]
fn output_validation_accepts_nested_receipts_and_checks_types() {
    let schema = json!({"type":"object", "properties":{"receipt":{"type":"string"},
        "undo":{"type":"object", "properties":{"name":{"type":"string"},"arguments":{"type":"object"}}, "required":["name","arguments"]}},
        "required":["receipt"], "additionalProperties":false});
    assert!(spark_dialog::gate::result_ok(
        &schema,
        &json!({"receipt":"first line\nsecond line", "undo":{"name":"restore","arguments":{"level":70}}})
    )
    .is_ok());
    assert!(spark_dialog::gate::result_ok(&schema, &json!({"receipt":true})).is_err());
    assert!(spark_dialog::gate::result_ok(&schema, &json!({"receipt":"done","extra":1})).is_err());
    assert!(spark_dialog::gate::result_ok(&json!({"type":"string","pattern":"x"}), &json!("x")).is_err());
}

#[test]
fn context_does_not_invent_a_selection_when_focus_is_in_the_prompt() {
    let (mut app, _, _) = started(false);
    app.in_list = false;
    app.task_start("change that");
    assert!(request(&app).1["context"]["selected"].is_null());
    app.task_cancel();
    app.in_list = true;
    app.sel = app.picks().iter().position(|i| matches!(i, spark_dialog::app::Item::Row(0, 0))).unwrap();
    app.providers[0].rows.rows[0].columns = vec!["10:00".into()];
    app.providers[0].rows.rows[0].date = Some("2026-10-26".into());
    app.task_start("change that");
    assert_eq!(request(&app).1["context"]["selected"]["id"], "volume");
    assert_eq!(request(&app).1["context"]["selected"]["call"]["arguments"]["level"], 70);
    assert_eq!(request(&app).1["context"]["visible"][0]["rows"][0]["date"], "2026-10-26");
    assert_eq!(request(&app).1["context"]["visible"][0]["rows"][0]["columns"][0], "10:00");
}

#[test]
fn task_capabilities_bind_existing_items_to_row_arguments_not_display_names() {
    let (mut app, _, _) = started(false);
    app.providers[0].tools[0].name = "out_use".into();
    app.providers[0].tools[0].schema = json!({"type":"object", "properties":{"name":{"type":"string"}}, "required":["name"]});
    app.providers[0].rows.rows[0].text = "Desk speakers".into();
    let call = app.providers[0].rows.rows[0].tool.as_mut().unwrap();
    call.name = "out_use".into();
    call.arguments = json!({"name":"device-47"}).as_object().unwrap().clone();
    app.task_start("use those speakers");
    assert_eq!(request(&app).1["tools"][0]["inputSchema"]["properties"]["name"]["enum"], json!(["device-47"]));
    // A row that asks for a new value supplies no existing-item restriction.
    app.task_cancel();
    app.providers[0].rows.rows[0].tool.as_mut().unwrap().ask = vec!["name".into()];
    app.task_start("name a new item");
    assert!(request(&app).1["tools"][0]["inputSchema"]["properties"]["name"].get("enum").is_none());
}

#[test]
fn native_preparation_finishes_before_review_and_execution() {
    let (mut app, rx, calls) = started(false);
    app.providers[0].tools[0].prepare = true;
    app.task_start("make it quieter");
    propose(&mut app);
    assert_eq!(app.task.as_ref().unwrap().phase, Phase::Prepare(0));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
    assert!(pump(&mut app, &rx, |a| a.staged.is_some()));
    assert_eq!(app.staged.as_ref().unwrap().steps[0].call.arguments["level"], 25);
    assert_eq!(app.task.as_ref().unwrap().state["pending"]["step"]["arguments"]["level"], 25);
    assert!(calls.lock().unwrap().is_empty(), "preparation never executes the operation");
}

#[test]
fn canonical_preparation_stops_repeated_attempts_and_allows_distinct_actions() {
    for (repeat, native_error) in [(true, false), (true, true), (false, false)] {
        let (mut app, rx, tx) = app_with(&["reminders"]);
        let calls = Arc::new(Mutex::new(Vec::<Value>::new()));
        let captured = calls.clone();
        let tools = json!([{"name":"reminder_add","title":"remind WHEN TITLE",
            "inputSchema":{"type":"object","properties":{"when":{"type":"string"},"title":{"type":"string"}},"required":["when","title"]},
            "annotations":{"destructiveHint":false},"_meta":{"spark-shell/prepare":true}}]);
        let rows = json!({"title":"reminders","rows":[]});
        let script: Script = Box::new(move |v, send| {
            if let Some(answer) = ordinary("reminders", v, &tools, &rows) {
                return send(answer);
            }
            if v["method"] == "spark/prepare" {
                let mut args = v["params"]["arguments"].clone();
                args["when"] = json!(if args["when"] == "the following day at nine" {
                    "2026-10-30 09:00"
                } else {
                    "2026-10-29 09:00"
                });
                return send(result(&v["id"], json!({"ready":true,"arguments":args})));
            }
            if v["method"] == "tools/call" {
                captured.lock().unwrap().push(v["params"].clone());
                send(result(
                    &v["id"],
                    json!({"isError":native_error,"content":[{"type":"text",
                    "text":if native_error {"reminder unavailable"} else {"reminder saved"}}]}),
                ));
            }
        });
        app.servers.push(stub(0, "reminders", script, tx));
        app.start();
        assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
        app.view = View::Section(0);
        app.task_start("remind me to water the garden");
        let propose = |app: &mut App, when: &str, id: u64| {
            let (serial, _) = request(app);
            let step = json!({"name":"p0_reminder_add","arguments":{"when":when,"title":"water garden"}});
            app.task_reply(
                serial,
                Ok(json!({"version":1,"status":"step","id":id,"step":step,
                "state":{"pending":{"id":id,"kind":"step","step":step}}})
                .to_string()),
            );
        };
        propose(&mut app, "tomorrow at nine", 1);
        assert!(pump(&mut app, &rx, |a| a.staged.is_some()));
        assert!(app.task.as_ref().unwrap().attempted.is_empty(), "review is not an attempted action");
        app.enter();
        assert!(pump(&mut app, &rx, |a| a.running.is_none()
            && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
        assert_eq!(app.task.as_ref().unwrap().attempted.len(), 1);
        let prior_receipt = app.exchange.last().unwrap().clone();
        propose(&mut app, if repeat { "tomorrow morning 9" } else { "the following day at nine" }, 2);
        if repeat {
            assert!(pump(&mut app, &rx, |a| a.task.is_none()));
            assert!(app.staged.is_none() && app.running.is_none() && app.jobs.is_empty());
            assert_eq!(calls.lock().unwrap().len(), 1);
            assert!(app
                .exchange
                .iter()
                .any(|line| line.text == prior_receipt.text && line.sign == prior_receipt.sign));
            assert!(app.exchange.last().unwrap().text.contains("without repeating it"));
            if !native_error {
                app.task_start("create another reminder for the same time");
                propose(&mut app, "tomorrow at nine", 1);
                assert!(pump(&mut app, &rx, |a| a.staged.is_some()));
                app.enter();
                assert!(pump(&mut app, &rx, |a| a.running.is_none()
                    && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
                assert_eq!(calls.lock().unwrap().len(), 2, "a fresh user task has its own attempt history");
            }
        } else {
            assert!(pump(&mut app, &rx, |a| a.staged.is_some()));
            assert_eq!(calls.lock().unwrap().len(), 1, "a distinct action still waits for Enter");
            app.enter();
            assert!(pump(&mut app, &rx, |a| a.running.is_none()
                && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
            let calls = calls.lock().unwrap();
            assert_eq!(calls.len(), 2);
            assert_ne!(calls[0]["arguments"], calls[1]["arguments"]);
        }
    }
}

#[test]
fn native_preparation_can_request_input_and_late_replies_are_ignored() {
    let (mut app, rx, calls) = started(false);
    app.providers[0].tools[0].prepare = true;
    app.task_start("make it quieter");
    propose(&mut app);
    let serial = app.task.as_ref().unwrap().serial;
    app.task_prepared(0, serial, Some(json!({"ready":false,"question":"Which output should I use?"})), None);
    assert_eq!(request(&app).1["observation"]["status"], "needs_input");
    assert!(app.staged.is_none());
    app.task_cancel();
    pump(&mut app, &rx, |_| false);
    assert!(app.task.is_none() && app.staged.is_none() && calls.lock().unwrap().is_empty());
}

#[test]
fn preparation_timeout_never_stages_or_executes_an_operation() {
    let (mut app, _, calls) = started(false);
    app.providers[0].tools[0].prepare = true;
    app.task_start("make it quieter");
    propose(&mut app);
    app.tick(Instant::now() + spark_dialog::mcp::T_READ + Duration::from_secs(1));
    assert!(app.task.is_none() && app.staged.is_none() && calls.lock().unwrap().is_empty());
}

#[test]
fn confirmation_shows_every_argument_even_when_the_title_has_one_placeholder() {
    let (mut app, _, calls) = started(false);
    app.providers[0].tools[0].schema["properties"]["balance"] = json!({"type":"integer"});
    app.task_start("set the volume and balance");
    let (id, _) = request(&app);
    let step = json!({"name":"p0_out_level", "arguments":{"level":30,"balance":70}});
    app.task_reply(
        id,
        Ok(json!({"version":1, "status":"step", "id":1, "step":step,
        "state":{"pending":{"id":1,"kind":"step","step":step}}})
        .to_string()),
    );
    let display = &app.staged.as_ref().unwrap().text;
    assert!(display.contains("level: 30") && display.contains("balance: 70"));
    assert!(calls.lock().unwrap().is_empty());
    render_task(&app, "proposal-fields");
}

#[test]
fn confirmation_shows_a_value_even_when_the_title_has_no_placeholder() {
    let (mut app, _, calls) = started(false);
    app.providers[0].tools[0].title = "out level".into();
    app.task_start("set the volume to 30");
    let (id, _) = request(&app);
    let step = json!({"name":"p0_out_level", "arguments":{"level":30}});
    app.task_reply(
        id,
        Ok(json!({"version":1, "status":"step", "id":1, "step":step,
        "state":{"pending":{"id":1,"kind":"step","step":step}}})
        .to_string()),
    );
    assert!(app.staged.as_ref().unwrap().text.contains("level: 30"));
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn literal_text_proposals_show_escaped_fields_and_send_exact_arguments() {
    for single in [false, true] {
        let (mut app, rx, calls) = started(false);
        let text = "first\nsecond\tlast\r";
        let tool = &mut app.providers[0].tools[0];
        tool.name = "notes_append".into();
        tool.title = if single { "notes append TEXT" } else { "notes append NAME TEXT" }.into();
        tool.schema = json!({"type":"object","properties":{
            "text":{"type":"string","contentMediaType":"text/plain","maxLength":16384}},"required":["text"]});
        let mut arguments = json!({"text":text});
        if !single {
            tool.schema["properties"]["name"] = json!({"type":"string","maxLength":255});
            tool.schema["required"].as_array_mut().unwrap().push(json!("name"));
            arguments["name"] = json!("fixture.md");
        }
        app.task_start("append literal text");
        let (serial, _) = request(&app);
        let step = json!({"name":"p0_notes_append","arguments":arguments});
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"step","id":1,"step":step,
            "state":{"pending":{"id":1,"kind":"step","step":step}}})
            .to_string()),
        );
        let staged = app.staged.as_ref().unwrap();
        assert!(staged.text.contains("text: \"first\\nsecond\\tlast\\r\""));
        assert!(!staged.text.contains(['\t', '\r']));
        assert_eq!(staged.steps[0].call.arguments["text"], text);
        assert!(calls.lock().unwrap().is_empty());
        app.enter();
        assert!(pump(&mut app, &rx, |a| a.running.is_none()
            && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
        assert_eq!(calls.lock().unwrap().len(), 1);
        assert_eq!(calls.lock().unwrap()[0]["arguments"], arguments);
    }
}

#[test]
fn malformed_and_protocol_results_stop_without_losing_prior_receipts() {
    let replies = [
        json!({"result":null}),
        json!({"result":[]}),
        json!({"result":{}}),
        json!({"result":{"content":[],"isError":"true","structuredContent":{"receipt":"not evidence"}}}),
        json!({"result":{"content":"not a list"}}),
        json!({"result":{"content":[{"type":"text","text":12}]}}),
        json!({"result":{"content":[],"structuredContent":[]}}),
        json!({"error":{"code":-32603,"message":"provider failed"}}),
        // Protocol diagnostics can repeat private values: spark:allow-secret.
        json!({"error":{"code":-32603,"message":"fixture private value","data":{"password":"fixture private value"}}}),
        json!({"error":{"code":"wrong","message":"provider failed"}}),
        json!({"result":{"content":[]},"error":{"code":-32603,"message":"both"}}),
    ];
    for reply in replies {
        let (mut app, rx, _) = started(false);
        app.task_start("change the output in two steps");
        propose(&mut app);
        app.enter();
        assert!(pump(&mut app, &rx, |a| a.running.is_none()
            && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
        let undo = app.undo.clone();
        let (serial, _) = request(&app);
        let step = json!({"name":"p0_out_level","arguments":{"level":40}});
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"step","id":2,"step":step,
            "state":{"pending":{"id":2,"kind":"step","step":step}}})
            .to_string()),
        );
        app.enter();
        app.jobs.clear();
        app.opened = true;
        let (provider, id, _, _) = app.running.clone().unwrap();
        let mut response = reply;
        response["jsonrpc"] = json!("2.0");
        response["id"] = json!(id);
        app.incoming(spark_dialog::mcp::Incoming::Msg(provider, response));
        assert!(app.task.is_none() && app.running.is_none());
        assert!(app.jobs.is_empty(), "unknown outcomes do not ask for a retry");
        assert_eq!(app.undo, undo);
        assert!(!app.opened && app.quit.is_none());
        assert!(app
            .exchange
            .iter()
            .any(|line| line.sign == spark_dialog::app::Sign::Done && line.text == "volume 30"));
        assert!(app.exchange.last().unwrap().text.contains("may have happened"));
        assert!(!app.exchange.iter().any(|line| line.text.contains("fixture private value")));
    }
}

#[test]
fn a_row_click_and_value_key_cannot_replace_a_running_action() {
    let (mut app, rx, calls) = started(false);
    app.task_start("make it quieter");
    propose(&mut app);
    app.enter();
    let running = app.running.clone();
    let task_serial = app.task.as_ref().unwrap().serial;
    app.in_list = true;
    app.sel = 0;
    app.enter();
    assert_eq!(app.running, running);
    assert_eq!(app.task.as_ref().unwrap().serial, task_serial);
    app.in_list = true;
    app.sel = 0;
    app.right();
    assert_eq!(app.running, running);
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert_eq!(calls.lock().unwrap().len(), 1);
    assert!(app.exchange.iter().any(|line| line.text == "volume 30"));
}

#[test]
fn an_old_timeout_cannot_cancel_a_different_running_call() {
    let (mut app, rx, calls) = started(false);
    app.task_start("make it quieter");
    propose(&mut app);
    app.enter();
    let running = app.running.clone();
    app.servers[0].pending.insert(
        9999,
        spark_dialog::mcp::Pending {
            kind: spark_dialog::mcp::Kind::Call(0),
            deadline: Instant::now(),
            token: None,
        },
    );
    app.tick(Instant::now() + Duration::from_secs(1));
    assert_eq!(app.running, running);
    assert!(app.task.is_some());
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert_eq!(calls.lock().unwrap().len(), 1);
}

#[test]
fn timeout_and_provider_loss_keep_a_partial_task_visible() {
    for lost in [false, true] {
        let (mut app, _, _) = started(false);
        app.task_start("open something then change the output");
        propose(&mut app);
        app.enter();
        app.opened = true;
        if lost {
            app.incoming(spark_dialog::mcp::Incoming::Gone(0, "closed".into()));
        } else {
            app.tick(Instant::now() + spark_dialog::mcp::T_CALL + Duration::from_secs(1));
        }
        assert!(app.task.is_none() && app.quit.is_none() && !app.opened);
    }
}

#[test]
fn an_unrelated_provider_cannot_take_over_a_native_question() {
    let (mut app, _, _) = started(false);
    app.task_start("make it quieter");
    propose(&mut app);
    app.enter();
    app.incoming(spark_dialog::mcp::Incoming::Msg(
        1,
        json!({"jsonrpc":"2.0","id":"other",
        "method":"elicitation/create","params":{"message":"unrelated", "requestedSchema":{
        "type":"object","properties":{"choice":{"type":"string"}}}}}),
    ));
    assert_eq!(app.mode, Mode::Normal);
    assert!(app.running.is_some());
}

#[test]
fn a_proposal_cannot_reach_an_unoffered_provider_or_supply_credentials() {
    for credentials in [false, true] {
        let (mut app, _, calls) = started(false);
        app.providers[0].tools[0].schema["properties"]["password"] = json!({"type":"string","format":"password"});
        if !credentials {
            app.view = View::Home;
        }
        app.task_start("make it quieter");
        let (serial, _) = request(&app);
        let args = if credentials {
            json!({"level":30,"password":"fixture value"})
        } else {
            json!({"level":30})
        };
        let step = json!({"name":"p0_out_level","arguments":args});
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"step","id":1,"step":step,
            "state":{"pending":{"id":1,"kind":"step","step":step}}})
            .to_string()),
        );
        assert!(app.task.is_none() && app.staged.is_none());
        assert!(calls.lock().unwrap().is_empty());
        assert!(!app.exchange.iter().any(|line| line.text.contains("fixture value")));
    }
}

#[test]
fn a_multi_provider_task_uses_native_results_and_keeps_discovered_capabilities() {
    let (mut app, rx, tx) = app_with(&["notes", "reminders", "wifi"]);
    let calls = Arc::new(Mutex::new(Vec::<Value>::new()));
    let notes = json!([
        {"name":"notes_create","title":"notes create","inputSchema":{"type":"object","properties":{},"required":[]},"annotations":{"destructiveHint":false}},
        {"name":"notes_open","title":"notes open NAME","inputSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]},"annotations":{"destructiveHint":false}},
        {"name":"notes_link","title":"notes link NOTE REMINDER","inputSchema":{"type":"object","properties":{"note":{"type":"string"},"reminder":{"type":"string"}},"required":["note","reminder"]},"annotations":{"destructiveHint":false}}
    ]);
    let reminders = json!([
        {"name":"reminders_create","title":"reminders create SOURCE","inputSchema":{"type":"object","properties":{"source":{"type":"string"}},"required":["source"]},"annotations":{"destructiveHint":false}}
    ]);
    for (provider, label, tools) in [(0, "notes", notes), (1, "reminders", reminders)] {
        let captured = calls.clone();
        let mut rows = if provider == 0 {
            json!({"title":label,"rows":[{"id":"existing","text":"Existing note",
                "tool":{"name":"notes_open","arguments":{"name":"existing"}}}]})
        } else {
            json!({"title":label,"rows":[]})
        };
        let script: Script = Box::new(move |v, send| {
            if let Some(r) = ordinary(label, v, &tools, &rows) {
                return send(r);
            }
            if v["method"] == "tools/call" {
                let mut calls = captured.lock().unwrap();
                calls.push(v["params"].clone());
                // This identity exists only after execution, and differs for each write.
                let identity = format!("{}-{}", label, calls.len());
                if v["params"]["name"] == "notes_create" {
                    rows["rows"].as_array_mut().unwrap().push(json!({"id":identity,"text":"Created note",
                        "tool":{"name":"notes_open","arguments":{"name":identity}}}));
                }
                send(result(
                    &v["id"],
                    json!({"isError":false,"content":[{"type":"text","text":"saved"}],
                    "structuredContent":{"receipt":format!("saved {}", identity),"id":identity}}),
                ));
            }
        });
        app.servers.push(stub(provider, label, script, tx.clone()));
    }
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[..2].iter().all(|p| p.ready && !p.tools.is_empty())));
    app.providers[2].ready = true;
    app.providers[2].rows = spark_dialog::model::rows(r#"{"title":"wifi","rows":[{"id":"private","text":"private unrelated network"}]}"#).unwrap();
    app.jobs.clear();
    app.task_start("create a note and a reminder, then link the saved items");
    assert!(request(&app).1["tools"].as_array().unwrap().is_empty());
    let inspect = |app: &mut App, provider: usize, id: u64| {
        let (serial, _) = request(app);
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"inspect","id":id,"provider":provider,
            "state":{"pending":{"id":id,"kind":"inspect","provider":provider}}})
            .to_string()),
        );
    };
    let step = |app: &mut App, name: &str, arguments: Value, id: u64| {
        let (serial, _) = request(app);
        let call = json!({"name":name,"arguments":arguments});
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"step","id":id,"step":call,
            "state":{"pending":{"id":id,"kind":"step","step":call}}})
            .to_string()),
        );
    };
    inspect(&mut app, 0, 1);
    assert!(pump(&mut app, &rx, |a| a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
    step(&mut app, "p0_notes_create", json!({}), 2);
    assert!(calls.lock().unwrap().is_empty());
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none()
        && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
    let note_id = request(&app).1["observation"]["result"]["structuredContent"]["id"].clone();
    assert!(note_id.is_string());
    let open_schema = request(&app).1["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["name"] == "p0_notes_open")
        .unwrap()["inputSchema"]
        .clone();
    assert!(
        open_schema["properties"]["name"]["enum"].as_array().unwrap().contains(&note_id),
        "the next turn sees the new identity without another model inspection"
    );
    step(&mut app, "p0_notes_open", json!({"name":note_id}), 3);
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none()
        && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
    inspect(&mut app, 1, 4);
    assert!(pump(&mut app, &rx, |a| a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
    let tools = request(&app).1["tools"].as_array().unwrap().clone();
    assert!(tools.iter().any(|t| t["name"] == "p0_notes_link"));
    assert!(tools.iter().any(|t| t["name"] == "p1_reminders_create"));
    step(&mut app, "p1_reminders_create", json!({"source":note_id}), 5);
    assert_eq!(calls.lock().unwrap().len(), 2, "the second provider also waits for review");
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none()
        && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
    let reminder_id = request(&app).1["observation"]["result"]["structuredContent"]["id"].clone();
    assert!(reminder_id.is_string() && reminder_id != note_id);
    step(&mut app, "p0_notes_link", json!({"note":note_id,"reminder":reminder_id}), 6);
    assert_eq!(calls.lock().unwrap().len(), 3);
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none()
        && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
    let recorded = calls.lock().unwrap();
    assert_eq!(recorded.len(), 4);
    assert_eq!(recorded[1]["arguments"]["name"], note_id);
    assert_eq!(recorded[2]["arguments"]["source"], note_id);
    assert_eq!(recorded[3]["arguments"], json!({"note":note_id,"reminder":reminder_id}));
    for job in &app.jobs {
        if let Job::RunInput(Helper::Task(_), _, body) = job {
            assert!(!body.contains("private unrelated network"));
        }
    }
    drop(recorded);
    let (serial, _) = request(&app);
    app.task_reply(serial, Ok(json!({"version":1,"status":"done","summary":"saved and linked"}).to_string()));
    assert!(app.task.is_none());
    assert_eq!(app.exchange.iter().filter(|l| l.sign == spark_dialog::app::Sign::Done).count(), 4);
}

#[test]
fn a_failed_refresh_preserves_the_completed_action_and_stops_continuation() {
    for timeout in [false, true] {
        let (mut app, rx, calls) = started(false);
        app.task_start("make it quieter then continue");
        propose(&mut app);
        app.enter();
        app.jobs.clear();
        assert!(pump(&mut app, &rx, |a| a.task.as_ref().is_some_and(|t| t.phase == Phase::Refresh(0))));
        let undo = app.undo.clone();
        assert!(undo.is_some());
        app.opened = true;
        if timeout {
            app.tick(Instant::now() + spark_dialog::mcp::T_READ + Duration::from_secs(1));
        } else {
            let id = app.providers[0].read_id.unwrap();
            app.incoming(spark_dialog::mcp::Incoming::Msg(0, result(&json!(id), json!({"contents":[]}))));
        }
        assert!(app.task.is_none() && app.jobs.is_empty() && app.quit.is_none());
        assert_eq!(app.undo, undo);
        assert_eq!(calls.lock().unwrap().len(), 1);
        assert!(app.exchange.iter().any(|l| l.sign == spark_dialog::app::Sign::Done && l.text == "volume 30"));
        assert!(app.exchange.last().unwrap().text.contains("current state could not be read"));
    }
}

#[test]
fn private_native_results_keep_safe_receipts_but_never_continue_the_model() {
    // Synthetic credential fields only: spark:allow-secret.
    let private = "fixture private value";
    let cases = [
        (
            json!({"content":[],"structuredContent":{"receipt":"saved safely",
                "undo":{"name":"out_level","arguments":{"password":private}}}}),
            None,
            false,
        ),
        (
            json!({"content":[],"structuredContent":{"receipt":"saved safely",
                "details":[{"value":private}]}}),
            Some(json!({"type":"object","properties":{"details":{"type":"array","items":{
                "type":"object","properties":{"value":{"type":"string","format":"password"}}}}}})),
            false,
        ),
        (
            json!({"content":[],"structuredContent":{"receipt":private}}),
            Some(json!({"type":"object","properties":{"receipt":{"type":"string","format":"password"}}})),
            false,
        ),
        (
            json!({"content":[{"type":"text","text":json!({"token":private}).to_string()}],
                "structuredContent":{"receipt":"saved safely"}}),
            None,
            false,
        ),
        (
            json!({"isError":true,"content":[{"type":"text","text":private}],
                "structuredContent":{"password":private}}),
            None,
            false,
        ),
        (
            json!({"content":[],"structuredContent":{"receipt":"saved safely",
                "undo":{"name":"out_restore","arguments":{"value":private}}}}),
            None,
            true,
        ),
    ];
    for (response, output_schema, inverse) in cases {
        let (mut app, rx, _) = started(false);
        app.task_start("change the output in two steps");
        propose(&mut app);
        app.enter();
        assert!(pump(&mut app, &rx, |a| a.running.is_none()
            && a.task.as_ref().is_some_and(|t| t.phase == Phase::Thinking)));
        app.providers[0].tools[0].output_schema = output_schema;
        if inverse {
            let mut tool = app.providers[0].tools[0].clone();
            tool.name = "out_restore".into();
            tool.schema = json!({"type":"object","properties":{"value":{"type":"string","format":"password"}},"required":["value"]});
            app.providers[0].tools.push(tool);
        }
        let (serial, _) = request(&app);
        let step = json!({"name":"p0_out_level","arguments":{"level":40}});
        app.task_reply(
            serial,
            Ok(json!({"version":1,"status":"step","id":2,"step":step,
                "state":{"pending":{"id":2,"kind":"step","step":step}}})
            .to_string()),
        );
        app.enter();
        app.jobs.clear();
        let (provider, id, _, _) = app.running.clone().unwrap();
        let safe_receipt = response.pointer("/structuredContent/receipt").and_then(Value::as_str) == Some("saved safely");
        let refused = response["isError"] == true;
        app.incoming(spark_dialog::mcp::Incoming::Msg(provider, result(&json!(id), response)));
        assert!(app.task.is_none() && app.running.is_none() && app.jobs.is_empty());
        assert!(app.quit.is_none() && !app.opened);
        assert!(app.exchange.iter().any(|line| line.text == "volume 30"), "prior native receipts survive");
        assert!(!app.exchange.iter().any(|line| line.text.contains(private)));
        assert!(app.exchange.last().unwrap().text.contains("without sending it to spark"));
        if safe_receipt {
            assert!(app
                .exchange
                .iter()
                .any(|line| line.sign == spark_dialog::app::Sign::Done && line.text == "saved safely"));
        }
        if !refused {
            assert!(app.undo.is_none(), "a private inverse is never retained");
        }
    }
}

#[test]
fn private_result_scanning_has_a_bound_and_keeps_ordinary_native_data() {
    use spark_dialog::gate::result_privacy;
    let ordinary = json!({"content":[{"type":"text","text":"saved"}],"structuredContent":{
        "receipt":"saved note","name":"garden.md","uid":"runtime-id","due":"2026-10-29T09:00",
        "undo":{"name":"notes_delete","arguments":{"name":"garden.md"}}}});
    assert!(!result_privacy(None, &ordinary).private);
    let mut deep = json!("ordinary");
    for _ in 0..14 {
        deep = json!({"nested":deep});
    }
    let bounded = result_privacy(None, &deep);
    assert!(bounded.private && !bounded.text_safe("a receipt"));
    let wide = Value::Array(vec![json!(0); 4097]);
    assert!(result_privacy(None, &wide).private);
}
