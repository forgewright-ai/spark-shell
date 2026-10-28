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
