//! Words that name no row are one request to spark: these words, this tool list, which
//! steps. The steps come back as proposals in the box, each run on Enter; nothing runs
//! before that, and a reply for a request that was dropped lands nowhere.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{App, Helper, Job, Mode, View};
use std::sync::{Arc, Mutex};

fn started(risky: bool) -> (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>, Arc<Mutex<Vec<Value>>>) {
    let (mut app, rx, tx) = app_with(&["out", "notes"]);
    app.cfg.spark = "/bin/sh".into();
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
        if v["method"] == "tools/call" {
            captured.lock().unwrap().push(v["params"].clone());
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

/// The request spark was asked: its serial, the about and the tool list on stdin.
fn request(app: &App) -> (u64, String, Value) {
    app.jobs
        .iter()
        .rev()
        .find_map(|j| match j {
            Job::RunInput(Helper::Want(id), argv, data) => {
                assert_eq!(argv[1], "steps");
                assert_eq!(argv[2], "--about");
                assert_eq!(argv[4], "--");
                Some((*id, argv[3].clone(), serde_json::from_str(data).unwrap()))
            }
            _ => None,
        })
        .expect("a request to spark steps")
}

fn propose(app: &mut App, serial: u64, steps: Value) {
    app.helper(Helper::Want(serial), Ok(json!({"answer": "", "steps": steps, "refused": []}).to_string()));
}

fn type_words(app: &mut App, words: &str) {
    for c in words.chars() {
        app.typed(c);
    }
}

#[test]
fn a_request_carries_the_view_the_selected_row_and_every_ready_tool_but_the_files() {
    let (mut app, _, _) = started(false);
    app.down();
    assert!(app.in_list);
    type_words(&mut app, "make this quieter");
    app.enter();
    let (_, about, tools) = request(&app);
    assert!(about.contains("The view: sound"), "{}", about);
    assert!(about.contains("The selected row: volume 70"), "{}", about);
    assert!(about.contains("The local time: "), "{}", about);
    assert!(!about.contains("hidden note title"), "a row of another place is not volunteered: {}", about);
    let names: Vec<&str> = tools["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["out_level"]);
    assert_eq!(tools["tools"][0]["inputSchema"]["required"][0], "level");
}

#[test]
fn a_dead_or_unready_provider_and_the_files_are_not_offered() {
    let (mut app, _, _) = app_with(&["out", "files", "wifi"]);
    app.cfg.spark = "/bin/sh".into();
    for p in &mut app.providers {
        p.ready = true;
        p.tools = vec![spark_dialog::model::Tool {
            prepare: false,
            description: "d".into(),
            output_schema: None,
            name: format!("{}_x", p.label),
            title: format!("{} x", p.label),
            schema: json!({"type": "object", "properties": {}}),
            read_only: true,
            destructive: false,
        }];
    }
    app.providers[2].dead = Some("gone".into());
    app.view = View::Home;
    type_words(&mut app, "do something");
    app.enter();
    let (_, _, tools) = request(&app);
    let names: Vec<&str> = tools["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["out_x"]);
}

#[test]
fn typing_a_request_in_models_sends_it_instead_of_picking_a_model() {
    let (mut app, _, _) = started(false);
    app.view = View::Models;
    app.models = vec![("local-model".into(), "downloaded".into())];
    type_words(&mut app, "Increase the volume a little bit please.");
    app.enter();
    let (_, about, _) = request(&app);
    assert!(about.contains("The view: model"), "{}", about);
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
}

#[test]
fn typed_command_needs_no_inference() {
    let (mut app, rx, calls) = started(false);
    app.input = "out level 30".into();
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert!(app.jobs.is_empty());
    assert!(app.pending.is_none());
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
    assert!(app.pending.is_none() && app.jobs.is_empty() && calls.lock().unwrap().is_empty());
    app.providers[0].tools = tools;
    app.providers[0].ready = true;
    app.providers[0].reading = false;
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert!(app.pending.is_none() && app.jobs.is_empty());
}

#[test]
fn a_proposal_waits_for_enter_and_runs_as_proposed() {
    let (mut app, rx, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    assert!(app.staged_now() && app.input == "out level 30", "{:?}", app.input);
    assert!(calls.lock().unwrap().is_empty(), "nothing runs before Enter");
    assert!(app.pending.is_none(), "the request is answered");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert_eq!(calls.lock().unwrap()[0]["arguments"]["level"], 30);
    assert!(app.input.is_empty() && app.staged.is_none());
}

#[test]
fn a_proposal_cannot_bypass_destructive_confirmation() {
    let (mut app, _, calls) = started(true);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    app.enter();
    assert!(matches!(app.mode, Mode::Confirm(_)));
    assert!(calls.lock().unwrap().is_empty());
    app.input = "no".into();
    app.enter();
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn a_reply_for_a_request_esc_dropped_lands_nowhere() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    assert!(app.pending.is_some());
    app.escape();
    assert!(app.pending.is_none(), "Esc drops the request");
    assert_eq!(app.input, "make it quieter", "the words come back");
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    assert!(app.staged.is_none(), "a late reply proposes nothing");
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn a_row_picked_while_spark_thinks_runs_and_drops_the_request() {
    let (mut app, rx, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    assert!(app.pending.is_some());
    app.down();
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()), "the row runs at once");
    assert!(app.pending.is_none(), "the request is dropped");
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    assert!(app.staged.is_none(), "its late reply proposes nothing");
    assert_eq!(calls.lock().unwrap().len(), 1);
}

#[test]
fn a_newer_request_supersedes_the_older_one() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (first, _, _) = request(&app);
    app.jobs.clear();
    type_words(&mut app, "make it much quieter");
    app.enter();
    let (second, _, _) = request(&app);
    assert_ne!(first, second);
    propose(&mut app, first, json!([{"name": "out_level", "arguments": {"level": 60}}]));
    assert!(app.staged.is_none(), "the older reply proposes nothing");
    propose(&mut app, second, json!([{"name": "out_level", "arguments": {"level": 20}}]));
    assert!(app.staged_now() && app.input == "out level 20");
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn the_words_come_back_when_spark_does_not_answer() {
    let (mut app, _, _) = started(false);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    app.helper(Helper::Want(serial), Err("spark did not answer within 75 seconds".into()));
    assert_eq!(app.input, "make it quieter");
    assert!(app.pending.is_none());
    assert!(app.exchange.iter().any(|l| l.text.contains("did not answer")));
}

#[test]
fn an_answer_is_said_in_place_and_nothing_to_do_is_one_line() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "is the sound on");
    app.enter();
    let (serial, _, _) = request(&app);
    app.helper(
        Helper::Want(serial),
        Ok(json!({"answer": "The output is at 70 percent.", "steps": [], "refused": []}).to_string()),
    );
    assert_eq!(app.exchange.last().map(|l| l.text.as_str()), Some("The output is at 70 percent."));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
    type_words(&mut app, "fly me to the moon");
    app.enter();
    let (serial, _, _) = request(&app);
    app.helper(Helper::Want(serial), Ok(json!({"answer": "", "steps": [], "refused": []}).to_string()));
    assert!(
        app.exchange.last().is_some_and(|l| l.text.contains("nothing to do")),
        "{:?}",
        app.exchange.last().map(|l| l.text.clone())
    );
    assert_eq!(app.input, "fly me to the moon", "the words come back to be said again");
}

#[test]
fn a_step_that_is_not_offered_or_fails_the_gate_is_refused_in_one_line() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "display_brightness", "arguments": {"level": 10}}]));
    assert!(app.exchange.last().is_some_and(|l| l.text.contains("not offered here now")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
    type_words(&mut app, "make it quieter");
    app.enter();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 300}}]));
    assert!(app.exchange.last().is_some_and(|l| l.text.contains("did not run")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
}

#[test]
fn a_proposal_with_several_fields_shows_each_before_enter() {
    let (mut app, _, calls) = started(false);
    app.providers[0].tools[0].schema["properties"]["balance"] = json!({"type":"integer"});
    type_words(&mut app, "set the volume and balance");
    app.enter();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30, "balance": 70}}]));
    let display = &app.staged.as_ref().unwrap().text;
    assert!(display.contains("level: 30") && display.contains("balance: 70"), "{}", display);
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
        type_words(&mut app, "append literal text");
        app.enter();
        let (serial, _, _) = request(&app);
        propose(&mut app, serial, json!([{"name": "notes_append", "arguments": arguments}]));
        let staged = app.staged.as_ref().unwrap();
        assert!(staged.text.contains("text: \"first\\nsecond\\tlast\\r\""), "{}", staged.text);
        assert!(!staged.text.contains(['\t', '\r']));
        assert_eq!(staged.steps[0].call.arguments["text"], text);
        assert!(calls.lock().unwrap().is_empty());
        app.enter();
        assert!(pump(&mut app, &rx, |a| a.running.is_none() && !calls.lock().unwrap().is_empty()));
        assert_eq!(calls.lock().unwrap()[0]["arguments"], arguments);
    }
}

#[test]
fn the_helper_feeds_stdin_keeps_json_on_a_nonzero_exit_and_bounds_its_input() {
    let output = spark_dialog::helper::invoke(
        &["/bin/sh".into(), "-c".into(), "cat; exit 2".into()],
        json!({"answer": "", "steps": [], "refused": ["x"]}).to_string(),
    )
    .unwrap();
    assert_eq!(serde_json::from_str::<Value>(&output).unwrap()["refused"][0], "x");
    assert!(spark_dialog::helper::invoke(&["/bin/cat".into()], "x".repeat(262145)).is_err());
}
