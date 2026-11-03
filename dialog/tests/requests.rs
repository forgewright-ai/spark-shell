//! Explicit Ask makes one request to spark: these words, this tool list, which
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
    app.model_name = Some("test-model".into());
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
fn a_request_carries_tools_without_implicit_selected_context() {
    let (mut app, _, _) = started(false);
    app.down();
    assert!(app.in_list);
    type_words(&mut app, "make this quieter");
    app.ask();
    let (_, about, tools) = request(&app);
    assert!(!about.contains("The view: sound"), "{}", about);
    assert!(!about.contains("volume 70"), "{}", about);
    assert!(about.contains("explicit draft and attachment"), "{}", about);
    assert!(!about.contains("hidden note title"), "a row of another place is not volunteered: {}", about);
    let names: Vec<&str> = tools["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["out_level"]);
    assert_eq!(tools["tools"][0]["inputSchema"]["required"][0], "level");
}

#[test]
fn a_dead_or_unready_provider_is_not_offered_and_the_files_are() {
    let (mut app, _, _) = app_with(&["out", "files", "wifi"]);
    app.cfg.spark = "/bin/sh".into();
    app.model_name = Some("test-model".into());
    for p in &mut app.providers {
        p.ready = true;
        p.tools = vec![spark_dialog::model::Tool {
            description: "d".into(),
            output_schema: None,
            name: format!("{}_x", p.label),
            title: format!("{} x", p.label),
            schema: json!({"type": "object", "properties": {}}),
            read_only: true,
            destructive: false,
            opens: false,
        }];
    }
    app.providers[2].dead = Some("gone".into());
    app.view = View::Home;
    type_words(&mut app, "do something");
    app.ask();
    let (_, _, tools) = request(&app);
    let names: Vec<&str> = tools["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["out_x", "files_x"], "the files' tools go too since #112");
}

#[test]
fn typing_a_request_in_models_sends_it_instead_of_picking_a_model() {
    let (mut app, _, _) = started(false);
    app.view = View::Models;
    app.models = vec![("local-model".into(), "downloaded".into())];
    type_words(&mut app, "Increase the volume a little bit please.");
    app.ask();
    let (_, about, _) = request(&app);
    assert!(!about.contains("The view: model"), "{}", about);
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
    app.ask();
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
    app.ask();
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
fn an_explicit_ask_for_an_exact_command_still_requires_review() {
    let (mut app, rx, calls) = started(false);
    app.set_draft("out level 30");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    assert!(app.staged_now());
    assert!(calls.lock().unwrap().is_empty(), "the request's words do not authorize its proposal");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert_eq!(calls.lock().unwrap().len(), 1);
}

#[test]
fn a_reply_for_a_request_esc_dropped_lands_nowhere() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.ask();
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
    app.ask();
    let (serial, _, _) = request(&app);
    assert!(app.pending.is_some());
    app.conversation();
    app.down();
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()), "the row runs at once");
    assert!(app.pending.is_none(), "the request is dropped");
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    assert!(app.staged.is_none(), "its late reply proposes nothing");
    assert_eq!(calls.lock().unwrap().len(), 1);
}

#[test]
fn a_duplicate_request_is_suppressed_and_a_new_draft_is_preserved() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.ask();
    let (first, _, _) = request(&app);
    app.jobs.clear();
    type_words(&mut app, "make it much quieter");
    app.ask();
    assert!(app.jobs.is_empty());
    assert_eq!(app.want_serial, first);
    assert_eq!(app.input, "make it much quieter");
    propose(&mut app, first, json!([{"name": "out_level", "arguments": {"level": 20}}]));
    assert!(app.staged_now() && app.input == "out level 20");
    assert_eq!(app.staged.as_ref().unwrap().draft, "make it much quieter");
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn the_words_come_back_when_spark_does_not_answer() {
    let (mut app, _, _) = started(false);
    type_words(&mut app, "make it quieter");
    app.ask();
    let (serial, _, _) = request(&app);
    app.helper(Helper::Want(serial), Err("spark did not answer within 75 seconds".into()));
    assert_eq!(app.input, "make it quieter");
    assert!(app.pending.is_none());
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text.contains("did not answer")),
        "the refusal is the reply row's"
    );
}

#[test]
fn an_answer_is_said_in_place_and_nothing_to_do_is_one_line() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "is the sound on");
    app.ask();
    let (serial, _, _) = request(&app);
    app.helper(
        Helper::Want(serial),
        Ok(json!({"answer": "The output is at 70 percent.", "steps": [], "refused": []}).to_string()),
    );
    // a one-line answer is the reply row's, nothing above the list (#196)
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("The output is at 70 percent."));
    assert!(app.exchange.iter().any(|line| line.text.contains("70 percent")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
    type_words(&mut app, "fly me to the moon");
    app.ask();
    let (serial, _, _) = request(&app);
    app.helper(Helper::Want(serial), Ok(json!({"answer": "", "steps": [], "refused": []}).to_string()));
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("nothing to do")), "{:?}", app.reply);
    assert_eq!(app.input, "fly me to the moon", "the words come back to be said again");
}

#[test]
fn a_step_that_is_not_offered_or_fails_the_gate_is_refused_in_one_line() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "display_brightness", "arguments": {"level": 10}}]));
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("not offered here now")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
    type_words(&mut app, "make it quieter");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 300}}]));
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("did not run")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
}

#[test]
fn a_proposal_with_several_fields_shows_each_before_enter() {
    let (mut app, _, calls) = started(false);
    app.providers[0].tools[0].schema["properties"]["balance"] = json!({"type":"integer"});
    type_words(&mut app, "set the volume and balance");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30, "balance": 70}}]));
    let display = &app.staged.as_ref().unwrap().text;
    assert!(display.contains("level: 30") && display.contains("balance: 70"), "{}", display);
    assert!(calls.lock().unwrap().is_empty());
    // the reply row reads a text of several lines on one line, parted by spaces: never "levelbalance" (#112's proof)
    let said = spark_dialog::reply::Reply::new(spark_dialog::reply::Mark::Done, display).text;
    assert!(said.contains(" level: 30") && said.contains(" balance: 70"), "{}", said);
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
        app.ask();
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

/// A theme provider beside the sound one: palettes by their exact names, and a layout provider
/// whose rows name layouts, for the names a request from another view carries.
fn with_names() -> (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>) {
    let (mut app, rx, tx) = app_with(&["out", "theme", "layout"]);
    app.cfg.spark = "/bin/sh".into();
    app.model_name = Some("test-model".into());
    let out_tools = json!([{"name": "out_level", "title": "out level N", "description": "Set output volume.",
        "inputSchema": {"type": "object", "properties": {"level": {"type": "integer", "minimum": 0, "maximum": 100}}, "required": ["level"]},
        "annotations": {"destructiveHint": false}}]);
    let out_rows = json!({"title": "Sound", "state": "volume 70", "rows": [{"id": "volume", "sign": "check", "text": "volume 70",
        "tool": {"name": "out_level", "arguments": {"level": 70}}}]});
    let theme_tools = json!([{"name": "theme_palette", "title": "theme NAME", "description": "Use a palette everywhere.",
        "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "minLength": 1, "maxLength": 256}}, "required": ["name"]},
        "annotations": {"destructiveHint": false, "idempotentHint": true}}]);
    let theme_rows = json!({"title": "theme", "state": "everforest-dark", "rows": [
        {"id": "theme:selenized-dark", "sign": "check", "text": "selenized-dark", "tool": null},
        {"id": "theme:everforest-dark", "sign": "blank", "text": "everforest-dark", "tool": {"name": "theme_palette", "arguments": {"name": "everforest-dark"}}},
        {"id": "theme:everforest-light", "sign": "blank", "text": "everforest-light", "tool": {"name": "theme_palette", "arguments": {"name": "everforest-light"}}},
        {"id": "theme:gruvbox-light", "sign": "blank", "text": "gruvbox-light", "tool": {"name": "theme_palette", "arguments": {"name": "gruvbox-light"}}},
        {"id": "theme:nord", "sign": "blank", "text": "nord", "tool": {"name": "theme_palette", "arguments": {"name": "nord"}}}]});
    let layout_tools = json!([{"name": "layout_open", "title": "layout open NAME", "description": "Open a saved layout.",
        "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "minLength": 1, "maxLength": 256}}, "required": ["name"]},
        "annotations": {"destructiveHint": false}}]);
    let layout_rows = json!({"title": "layout", "state": "", "rows": [
        {"id": "layout:webdev", "sign": "blank", "text": "webdev", "tool": {"name": "layout_open", "arguments": {"name": "webdev"}}},
        {"id": "layout:zen", "sign": "blank", "text": "zen, micro and a terminal", "tool": {"name": "layout_open", "arguments": {"name": "zen-micro-and-a-terminal"}}}]});
    let out: Script = Box::new(move |v, send| {
        if let Some(r) = ordinary("out", v, &out_tools, &out_rows) {
            send(r);
        }
    });
    let theme: Script = Box::new(move |v, send| {
        if let Some(r) = ordinary("theme", v, &theme_tools, &theme_rows) {
            send(r);
        }
    });
    let layout: Script = Box::new(move |v, send| {
        if let Some(r) = ordinary("layout", v, &layout_tools, &layout_rows) {
            send(r);
        }
    });
    app.servers.push(stub(0, "out", out, tx.clone()));
    app.servers.push(stub(1, "theme", theme, tx.clone()));
    app.servers.push(stub(2, "layout", layout, tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a
        .providers
        .iter()
        .all(|p| p.ready && !p.tools.is_empty() && !p.rows.rows.is_empty())));
    app.view = View::Section(0);
    app.jobs.clear();
    (app, rx)
}

#[test]
fn a_step_that_names_a_row_by_a_near_miss_takes_the_rows_own_name() {
    let (mut app, _) = with_names();
    type_words(&mut app, "change theme to everforest light");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": "everforest light"}}]));
    assert!(
        app.staged_now() && app.input == "theme everforest-light",
        "the proposal names the row: {:?} {:?}",
        app.input,
        app.exchange
    );
    // a unique start of a name, and a unique name holding every word, fit the same way
    for (said, want) in [("gruvbox", "theme gruvbox-light"), ("light everforest", "theme everforest-light")] {
        app.escape();
        app.input.clear();
        type_words(&mut app, "use the other one");
        app.ask();
        let (serial, _, _) = request(&app);
        propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": said}}]));
        assert!(app.staged_now() && app.input == want, "{}: {:?} {:?}", said, app.input, app.exchange);
    }
}

#[test]
fn a_step_that_names_no_row_is_refused_in_the_steps_own_words() {
    let (mut app, _) = with_names();
    type_words(&mut app, "change theme to rainbow");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": "rainbow"}}]));
    assert!(!app.staged_now(), "{:?}", app.input);
    let last = app.reply.as_ref().map(|r| r.text.clone()).unwrap_or_default();
    assert_eq!(last, "theme rainbow did not run: rainbow is not in the list now");
    // two names start with the word: no guess, the gate decides
    app.input.clear();
    type_words(&mut app, "everforest please");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": "everforest"}}]));
    assert!(!app.staged_now(), "{:?}", app.input);
}

#[test]
fn a_request_does_not_volunteer_names_from_other_providers() {
    let (mut app, _) = with_names();
    type_words(&mut app, "open the web layout");
    app.ask();
    let (_, about, _) = request(&app);
    assert!(
        !about.contains("everforest") && !about.contains("webdev"),
        "unattached names stay local: {}",
        about
    );
}

/// The files as a file manager (#112): a folder on screen, its rows' paths the names a step takes.
fn in_a_folder() -> (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>) {
    let (mut app, rx, tx) = app_with(&["files"]);
    app.cfg.spark = "/bin/sh".into();
    app.model_name = Some("test-model".into());
    let path_prop = json!({"type": "string", "minLength": 2, "maxLength": 4096, "format": "path"});
    let tools = json!([
        {"name": "files_trash", "title": "files trash PATH", "description": "Trash.", "inputSchema": {"type": "object", "properties": {"path": path_prop}, "required": ["path"]}, "annotations": {"destructiveHint": false}},
        {"name": "files_move", "title": "files move PATH", "description": "Move.", "inputSchema": {"type": "object", "properties": {"path": path_prop, "to": path_prop}, "required": ["path", "to"]}, "annotations": {"destructiveHint": false}}
    ]);
    let root = json!({"title": "files", "rows": [{"id": "files:root:a", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/aG9tZQ", "group": null}], "short": ["files:root:a"]});
    let folder = json!({"title": "~", "here": "/data/me", "rows": [
        {"id": "files:dir:d", "sign": "opens", "text": "documents", "tool": {"name": "files_browse", "arguments": {"path": "/data/me/documents"}}, "more": [{"name": "files_trash", "arguments": {"path": "/data/me/documents"}}], "columns": [], "children": "spark-shell://files/rows/ZG9jcw", "group": null},
        {"id": "files:file:i", "sign": "blank", "text": "invoice.pdf", "tool": {"name": "files_open", "arguments": {"path": "/data/me/invoice.pdf"}}, "more": [{"name": "files_move", "arguments": {"path": "/data/me/invoice.pdf"}, "pick": "to"}, {"name": "files_trash", "arguments": {"path": "/data/me/invoice.pdf"}}], "columns": ["2 MB", "today"], "children": null, "group": null}
    ], "short": []});
    let script: Script = Box::new(move |v, send| {
        if v.get("method").and_then(Value::as_str) == Some("resources/read") && v.pointer("/params/uri") != Some(&json!("spark-shell://files/rows")) {
            return send(result(
                &v["id"],
                json!({"contents": [{"uri": v["params"]["uri"], "mimeType": "application/json", "text": folder.to_string()}]}),
            ));
        }
        if let Some(r) = ordinary("files", v, &tools, &root) {
            send(r);
        }
    });
    app.servers.push(stub(0, "files", script, tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.came_from.push(View::Home);
    app.view = View::Section(0);
    app.down();
    app.up();
    let root_uri = "spark-shell://files/rows/aG9tZQ".to_string();
    app.view = View::Folder(0, root_uri);
    app.folder = None;
    app.tick(std::time::Instant::now());
    // the folder's rows, read as the view opens
    app.providers[0].dirty = true;
    assert!(pump(&mut app, &rx, |a| a.folder.is_some()), "the folder's rows come");
    app.jobs.clear();
    (app, rx)
}

#[test]
fn a_request_from_a_folder_carries_tools_without_browsed_paths() {
    let (mut app, _) = in_a_folder();
    type_words(&mut app, "move the invoice to documents");
    app.ask();
    let (_, about, tools) = request(&app);
    assert!(
        !about.contains("/data/me/") && !about.contains("invoice.pdf"),
        "browsed paths stay local: {}",
        about
    );
    let names: Vec<&str> = tools["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["files_trash", "files_move"]);
}

#[test]
fn a_step_with_a_path_no_row_holds_is_refused_and_a_rows_own_path_passes() {
    let (mut app, _) = in_a_folder();
    type_words(&mut app, "trash the password file");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(&mut app, serial, json!([{"name": "files_trash", "arguments": {"path": "/etc/passwd"}}]));
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text.contains("passwd is not in the list now")),
        "{:?}",
        app.reply
    );
    assert!(app.staged.is_none());
    type_words(&mut app, "move the invoice to documents");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(
        &mut app,
        serial,
        json!([{"name": "files_move", "arguments": {"path": "/data/me/invoice.pdf", "to": "/data/me/documents"}}]),
    );
    assert!(app.staged.is_some(), "a move between two rows' paths waits in the box: {:?}", app.exchange);
    // a near miss on the name resolves to the row's own path, and a folder named by its path alone passes the gate
    type_words(&mut app, "move invoice.pdf to documents");
    app.ask();
    let (serial, _, _) = request(&app);
    propose(
        &mut app,
        serial,
        json!([{"name": "files_move", "arguments": {"path": "invoice.pdf", "to": "/data/me/documents"}}]),
    );
    assert!(
        app.staged
            .as_ref()
            .is_some_and(|st| st.steps[0].call.arguments["path"] == "/data/me/invoice.pdf"),
        "{:?} {:?}",
        app.staged,
        app.exchange
    );
}

#[test]
fn a_plan_that_comes_while_the_prompt_asks_waits_for_the_question() {
    // the review's G: commands spark planned never take the box where a yes was being typed
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "make it quieter");
    app.ask();
    let (serial, _, _) = request(&app);
    app.mode = Mode::Confirm(app.commands("out level 20").unwrap().remove(0));
    app.stash = Some(String::new());
    type_words(&mut app, "ye");
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 10}}]));
    assert_eq!(app.input, "ye", "the yes being typed stays");
    assert!(matches!(app.mode, Mode::Confirm(_)));
    app.escape();
    assert!(app.staged_now(), "the question let go, the commands are in the box: {:?}", app.input);
    assert!(calls.lock().unwrap().is_empty(), "and nothing ran");
}

#[test]
fn a_raw_error_of_the_system_is_said_in_plain_words() {
    // the review: with no spark installed, "No such file or directory (os error 2)" was said as the answer
    let (mut app, _, _) = started(false);
    type_words(&mut app, "make it quieter");
    app.ask();
    let (serial, _, _) = request(&app);
    app.helper(Helper::Want(serial), Err("No such file or directory (os error 2)".into()));
    assert_eq!(app.reply.as_ref().unwrap().text, "spark did not answer: spark is not installed here");
    assert_eq!(app.input, "make it quieter", "the words come back");
}
