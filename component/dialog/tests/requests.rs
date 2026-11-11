//! Two requests go to spark (v0.130). Asking sends the words alone: spark's answer in words is said in the
//! conversation, no tool goes with it, and nothing runs. Enter on a step found by what the words mean sends the words
//! with that one tool: the values spark reads from them come back as a proposal in the box, each step run on Enter;
//! nothing runs before that, and a reply for a request that was dropped lands nowhere.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{App, Helper, Item, Job, Mode, Sign, View};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn started(risky: bool) -> (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>, Arc<Mutex<Vec<Value>>>) {
    let (mut app, rx, tx) = app_with(&["out", "notes"]);
    app.cfg.spark = "/bin/sh".into();
    app.model_name = Some("test-model".into());
    app.model_on = true;
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

/// The step `tool` found by what `words` mean, lit and entered at Home: the semantic search ranks it first, and Enter
/// asks spark for its values. The request spark was asked: its serial, the about and the one tool on stdin.
fn fill_request(app: &mut App, words: &str, tool: &str) -> (u64, String, Value) {
    app.cfg.semantic = Some("/run/test/semantic.sock".into());
    // the ask row stands under the matches, so the light is in the list when the meaning lands
    app.cfg.model = true;
    app.model_on = true;
    app.view = View::Home;
    app.in_list = false;
    app.set_draft("");
    app.search_sent.clear(); // the same words typed again are ranked again, as after clearing them
    type_words(app, words);
    app.tick(Instant::now() + Duration::from_millis(300));
    let serial = app
        .jobs
        .iter()
        .rev()
        .find_map(|j| match j {
            Job::Rank(Helper::Rank(s), _, w, _) if *s != 0 && w == words.trim() => Some(*s),
            _ => None,
        })
        .expect("a semantic search for the words");
    let (_, _, items) = app.rank_sent.clone().expect("the rows sent to be ranked");
    let scores: Vec<f32> = items
        .iter()
        .map(|it| if matches!(it, Item::Step(_, n) if n == tool) { 0.9 } else { 0.1 })
        .collect();
    app.helper(Helper::Rank(serial), Ok(json!(scores).to_string()));
    assert!(
        app.in_list && matches!(app.picks().get(app.sel), Some(Item::Step(_, n)) if n == tool),
        "the step is lit: {:?}",
        app.picks().get(app.sel)
    );
    app.enter();
    app.jobs
        .iter()
        .rev()
        .find_map(|j| match j {
            Job::RunInput(Helper::Fill(id), argv, data) => {
                assert_eq!(argv[0], app.cfg.spark);
                assert_eq!(argv[1], "steps");
                assert_eq!(argv[2], "--about");
                assert_eq!(argv[4], "--");
                assert_eq!(argv[5], words.trim());
                assert_eq!(argv.len(), 6);
                Some((*id, argv[3].clone(), serde_json::from_str(data).unwrap()))
            }
            _ => None,
        })
        .expect("a request to spark steps")
}

fn propose(app: &mut App, serial: u64, steps: Value) {
    app.helper(Helper::Fill(serial), Ok(json!({"answer": "", "steps": steps, "refused": []}).to_string()));
}

/// The words asked of spark: the request's serial, the command line and what went on stdin.
fn chat_request(app: &App) -> (u64, Vec<String>, String) {
    app.jobs
        .iter()
        .rev()
        .find_map(|j| match j {
            Job::RunInput(Helper::Chat(id), argv, data) => Some((*id, argv.clone(), data.clone())),
            _ => None,
        })
        .expect("a question to spark")
}

fn tool_names(payload: &Value) -> Vec<&str> {
    payload["tools"].as_array().unwrap().iter().filter_map(|t| t["name"].as_str()).collect()
}

fn type_words(app: &mut App, words: &str) {
    for c in words.chars() {
        app.typed(c);
    }
}

#[test]
fn an_ask_carries_the_words_alone() {
    let (mut app, _, _) = started(false);
    app.down();
    assert!(app.in_list);
    type_words(&mut app, "make this quieter");
    app.ask();
    let (_, argv, stdin) = chat_request(&app);
    assert_eq!(argv, ["/bin/sh", "make this quieter"], "the words as one argument, never a command of spark's");
    assert_eq!(stdin, "", "no tool, no row, no view goes with them");
    assert!(
        !app.jobs.iter().any(|j| matches!(j, Job::RunInput(Helper::Want(_) | Helper::Fill(_), ..))),
        "{:?}",
        app.jobs
    );
}

#[test]
fn one_word_asked_ends_with_a_question_mark_and_a_leading_at_goes() {
    let (mut app, _, _) = started(false);
    for (typed, sent) in [
        ("volume", "volume?"),
        ("@notes.md what is in it", "notes.md what is in it"),
        ("update my notes", "update my notes"),
    ] {
        app.set_draft(typed);
        app.ask();
        let (serial, argv, _) = chat_request(&app);
        assert_eq!(argv, ["/bin/sh", sent], "{}", typed);
        app.helper(Helper::Chat(serial), Ok("ok".into()));
    }
}

#[test]
fn an_answer_is_said_in_the_conversation_and_nothing_runs() {
    let (mut app, _, calls) = started(false);
    type_words(&mut app, "is the sound on");
    app.ask();
    let (serial, _, _) = chat_request(&app);
    app.helper(Helper::Chat(serial), Ok("* The output is at 70 percent.\n".into()));
    // a one-line answer is the reply row's, the exchange keeps the words and the answer (#196)
    assert_eq!(app.reply.as_ref().map(|r| r.text.as_str()), Some("The output is at 70 percent."));
    assert!(app.exchange.iter().any(|l| l.sign == Sign::You && l.text == "is the sound on"));
    assert!(app.exchange.iter().any(|l| l.sign == Sign::Says && l.text == "The output is at 70 percent."));
    assert!(app.staged.is_none() && app.pending.is_none() && calls.lock().unwrap().is_empty());
    // no answer: the words come back to be said again
    type_words(&mut app, "fly me to the moon");
    app.ask();
    let (serial, _, _) = chat_request(&app);
    app.helper(Helper::Chat(serial), Ok("\n".into()));
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("answered nothing")), "{:?}", app.reply);
    assert_eq!(app.input, "fly me to the moon");
}

#[test]
fn an_ask_in_the_words_of_a_command_asks_and_runs_nothing() {
    let (mut app, _, calls) = started(false);
    app.set_draft("out level 30");
    app.ask();
    let (serial, argv, _) = chat_request(&app);
    assert_eq!(argv, ["/bin/sh", "out level 30"]);
    app.helper(Helper::Chat(serial), Ok("That sets the output to 30 percent.".into()));
    assert!(app.staged.is_none(), "an answer proposes nothing");
    assert!(calls.lock().unwrap().is_empty(), "the words asked do not run what they name");
}

#[test]
fn a_fill_carries_one_tool_without_implicit_selected_context() {
    let (mut app, _, _) = started(false);
    app.down();
    assert!(app.in_list);
    let (_, about, tools) = fill_request(&mut app, "make this quieter", "out_level");
    assert!(!about.contains("The view: sound"), "{}", about);
    assert!(!about.contains("volume 70"), "{}", about);
    assert!(about.contains("explicit draft and attachment"), "{}", about);
    assert!(!about.contains("hidden note title"), "a row of another place is not volunteered: {}", about);
    assert_eq!(tool_names(&tools), ["out_level"], "the one step found, nothing else");
    assert_eq!(tools["tools"][0]["inputSchema"]["required"][0], "level");
    assert!(!tools.to_string().contains("volume 70") && !tools.to_string().contains("hidden note title"));
}

#[test]
fn a_step_of_a_dead_or_unready_provider_a_persons_step_and_a_path_step_are_never_found_by_meaning() {
    let (mut app, _, _) = app_with(&["out", "files", "wifi", "bt", "tools"]);
    let tool = |name: &str, schema: Value, person: bool| spark_dialog::model::Tool {
        description: "d".into(),
        output_schema: None,
        name: name.into(),
        title: name.replace('_', " "),
        schema,
        read_only: true,
        destructive: false,
        opens: person,
        person,
    };
    for p in &mut app.providers {
        p.ready = true;
        p.tools = vec![tool(&format!("{}_x", p.label), json!({"type": "object", "properties": {}}), false)];
    }
    let path = json!({"type": "object", "properties": {"path": {"type": "string", "format": "path"}}, "required": ["path"]});
    app.providers[1].tools.push(tool("files_trash", path, false));
    app.providers[2].dead = Some("gone".into());
    app.providers[3].ready = false;
    app.providers[4]
        .tools
        .push(tool("tools_update", json!({"type": "object", "properties": {}}), true));
    let steps: Vec<(String, String)> = app
        .candidates()
        .into_iter()
        .filter_map(|(it, text)| match it {
            Item::Step(_, n) => Some((n, text)),
            _ => None,
        })
        .collect();
    let names: Vec<&str> = steps.iter().map(|(n, _)| n.as_str()).collect();
    assert_eq!(names, ["out_x", "files_x", "tools_x"], "the files' other steps are found too");
    assert_eq!(
        steps[0].1, "sound x: d",
        "a step is known by its section's name, its verb and what it does (v0.130.1)"
    );
}

#[test]
fn asking_from_the_models_sends_the_words_and_picks_no_model() {
    let (mut app, _, _) = started(false);
    app.view = View::Models;
    app.models = vec![("local-model".into(), "downloaded".into())];
    type_words(&mut app, "Increase the volume a little bit please.");
    app.ask();
    let (_, argv, _) = chat_request(&app);
    assert_eq!(argv[1], "Increase the volume a little bit please.");
    assert_eq!(app.mode, Mode::Normal);
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::Run(Helper::ModelSet, _))));
}

#[test]
fn keyboard_model_selection_still_requires_explicit_choice_and_confirmation() {
    let (mut app, _, _) = started(false);
    app.view = View::Models;
    app.models = vec![("local-model".into(), "downloaded".into())];
    // the asking rows come first on the page (v0.124.3): Down until the model's own row
    app.down();
    while !matches!(app.picks().get(app.sel), Some(spark_dialog::app::Item::Model(_))) {
        app.down();
    }
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
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
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
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 30}}]));
    app.enter();
    assert!(matches!(app.mode, Mode::Confirm(_)));
    assert!(calls.lock().unwrap().is_empty());
    // the question's page: keep working runs nothing
    app.sel = 1;
    app.enter();
    assert!(matches!(app.mode, Mode::Normal));
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn a_reply_for_a_request_esc_dropped_lands_nowhere() {
    let (mut app, _, calls) = started(false);
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
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
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    assert!(app.pending.is_some());
    // back in the section, its row picked
    app.view = View::Section(0);
    app.in_list = false;
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
    let (first, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    app.jobs.clear();
    type_words(&mut app, "make it much quieter");
    app.ask();
    assert!(app.jobs.is_empty(), "{:?}", app.jobs);
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
    type_words(&mut app, "is the sound on");
    app.ask();
    let (serial, _, _) = chat_request(&app);
    app.helper(Helper::Chat(serial), Err("spark did not answer within 75 seconds".into()));
    assert_eq!(app.input, "is the sound on");
    assert!(app.pending.is_none());
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text.contains("did not answer")),
        "the refusal is the reply row's"
    );
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    app.helper(Helper::Fill(serial), Err("spark did not answer within 75 seconds".into()));
    assert_eq!(app.input, "make it quieter");
    assert!(app.pending.is_none() && app.filling.is_none());
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("did not answer")), "{:?}", app.reply);
}

#[test]
fn a_step_that_is_not_offered_or_fails_the_gate_is_refused_in_one_line() {
    let (mut app, _, calls) = started(false);
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    propose(&mut app, serial, json!([{"name": "display_brightness", "arguments": {"level": 10}}]));
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("not offered here now")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 300}}]));
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("did not run")));
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty());
}

#[test]
fn a_proposal_with_several_fields_shows_each_before_enter() {
    let (mut app, _, calls) = started(false);
    app.providers[0].tools[0].schema["properties"]["balance"] = json!({"type":"integer"});
    let (serial, _, _) = fill_request(&mut app, "set the volume and balance", "out_level");
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
        let (serial, _, _) = fill_request(&mut app, "append literal text", "notes_append");
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
/// whose rows name layouts, for the names a fill must not carry.
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
    let (serial, _, _) = fill_request(&mut app, "change theme to everforest light", "theme_palette");
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
        let (serial, _, _) = fill_request(&mut app, "use the other one", "theme_palette");
        propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": said}}]));
        assert!(app.staged_now() && app.input == want, "{}: {:?} {:?}", said, app.input, app.exchange);
    }
}

#[test]
fn a_step_that_names_no_row_is_refused_in_the_steps_own_words() {
    let (mut app, _) = with_names();
    let (serial, _, _) = fill_request(&mut app, "change theme to rainbow", "theme_palette");
    propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": "rainbow"}}]));
    assert!(!app.staged_now(), "{:?}", app.input);
    let last = app.reply.as_ref().map(|r| r.text.clone()).unwrap_or_default();
    assert_eq!(last, "theme rainbow did not run: rainbow is not in the list now");
    // two names start with the word: no guess, the gate decides
    let (serial, _, _) = fill_request(&mut app, "everforest please", "theme_palette");
    propose(&mut app, serial, json!([{"name": "theme_palette", "arguments": {"name": "everforest"}}]));
    assert!(!app.staged_now(), "{:?}", app.input);
}

#[test]
fn a_fill_does_not_volunteer_names_from_other_providers() {
    let (mut app, _) = with_names();
    let (_, about, tools) = fill_request(&mut app, "open the web layout", "layout_open");
    // the names the one step takes, its own provider's rows, go with it so a value is one of them (v0.130); another
    // provider's names never do
    assert!(!about.contains("everforest"), "another provider's names stay local: {}", about);
    assert!(about.contains("(one of: webdev"), "the step's own names go: {}", about);
    assert_eq!(tool_names(&tools), ["layout_open"]);
    let sent = tools.to_string();
    assert!(!sent.contains("webdev") && !sent.contains("everforest"), "the rows' names stay local: {}", sent);
}

/// The files as a file manager (#112): a folder on screen, its rows' paths the names a step takes. A path is picked in
/// the files, never said, so a step that takes one is never found by meaning: files find is.
fn in_a_folder() -> (App, std::sync::mpsc::Receiver<spark_dialog::mcp::Incoming>) {
    let (mut app, rx, tx) = app_with(&["files"]);
    app.cfg.spark = "/bin/sh".into();
    app.model_name = Some("test-model".into());
    let path_prop = json!({"type": "string", "minLength": 2, "maxLength": 4096, "format": "path"});
    let tools = json!([
        {"name": "files_trash", "title": "files trash PATH", "description": "Trash.", "inputSchema": {"type": "object", "properties": {"path": path_prop}, "required": ["path"]}, "annotations": {"destructiveHint": false}},
        {"name": "files_move", "title": "files move PATH", "description": "Move.", "inputSchema": {"type": "object", "properties": {"path": path_prop, "to": path_prop}, "required": ["path", "to"]}, "annotations": {"destructiveHint": false}},
        {"name": "files_find", "title": "files find WORDS", "description": "Find files by name.", "inputSchema": {"type": "object", "properties": {"words": {"type": "string", "minLength": 1, "maxLength": 256}}, "required": ["words"]}, "annotations": {"readOnlyHint": true}}
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
fn a_fill_carries_no_browsed_path_and_a_step_that_takes_a_path_is_never_found_by_meaning() {
    let (mut app, _) = in_a_folder();
    let steps: Vec<String> = app
        .candidates()
        .into_iter()
        .filter_map(|(it, _)| match it {
            Item::Step(_, n) => Some(n),
            _ => None,
        })
        .collect();
    assert_eq!(steps, ["files_find"], "a path is picked in the files, never said");
    let (_, about, tools) = fill_request(&mut app, "move the invoice to documents", "files_find");
    assert!(
        !about.contains("/data/me/") && !about.contains("invoice.pdf"),
        "browsed paths stay local: {}",
        about
    );
    assert_eq!(tool_names(&tools), ["files_find"]);
    assert!(!tools.to_string().contains("/data/me/"), "{}", tools);
}

#[test]
fn a_step_with_a_path_no_row_holds_is_refused_and_a_rows_own_path_passes() {
    let (mut app, _) = in_a_folder();
    let (serial, _, _) = fill_request(&mut app, "trash the password file", "files_find");
    propose(&mut app, serial, json!([{"name": "files_trash", "arguments": {"path": "/etc/passwd"}}]));
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text.contains("passwd is not in the list now")),
        "{:?}",
        app.reply
    );
    assert!(app.staged.is_none());
    let (serial, _, _) = fill_request(&mut app, "move the invoice to documents", "files_find");
    propose(
        &mut app,
        serial,
        json!([{"name": "files_move", "arguments": {"path": "/data/me/invoice.pdf", "to": "/data/me/documents"}}]),
    );
    assert!(app.staged.is_some(), "a move between two rows' paths waits in the box: {:?}", app.exchange);
    // a near miss on the name resolves to the row's own path, and a folder named by its path alone passes the gate
    let (serial, _, _) = fill_request(&mut app, "move invoice.pdf to documents", "files_find");
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
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    app.mode = Mode::Confirm(app.commands("out level 20").unwrap().remove(0));
    app.stash = Some(String::new());
    propose(&mut app, serial, json!([{"name": "out_level", "arguments": {"level": 10}}]));
    assert!(matches!(app.mode, Mode::Confirm(_)), "the question stands while the plan waits");
    app.escape();
    assert!(app.staged_now(), "the question let go, the commands are in the box: {:?}", app.input);
    assert!(calls.lock().unwrap().is_empty(), "and nothing ran");
}

#[test]
fn a_raw_error_of_the_system_is_said_in_plain_words() {
    // the review: with no spark installed, "No such file or directory (os error 2)" was said as the answer
    let (mut app, _, _) = started(false);
    type_words(&mut app, "is the sound on");
    app.ask();
    let (serial, _, _) = chat_request(&app);
    app.helper(Helper::Chat(serial), Err("No such file or directory (os error 2)".into()));
    assert_eq!(app.reply.as_ref().unwrap().text, "spark did not answer: spark is not installed here");
    assert_eq!(app.input, "is the sound on", "the words come back");
    let (serial, _, _) = fill_request(&mut app, "make it quieter", "out_level");
    app.helper(Helper::Fill(serial), Err("No such file or directory (os error 2)".into()));
    assert_eq!(app.reply.as_ref().unwrap().text, "spark did not answer: spark is not installed here");
    assert_eq!(app.input, "make it quieter", "the words come back");
}

#[test]
fn a_persons_step_is_never_found_by_meaning_and_a_plan_that_names_one_is_refused() {
    // tools' terminal steps (a fix, an update, the package cache's clean) carry _meta spark-shell/person: they run from
    // their row alone (the dialog design notes, Tools, v0.129.2)
    let (mut app, rx, tx) = app_with(&["tools"]);
    app.cfg.spark = "/bin/sh".into();
    app.model_name = Some("test-model".into());
    let calls = Arc::new(Mutex::new(vec![]));
    let captured = calls.clone();
    let tools = json!([
        {"name": "tools_check", "title": "tools check", "description": "Run the setup's tests.", "inputSchema": {"type": "object", "properties": {}},
         "annotations": {"readOnlyHint": true, "destructiveHint": false}},
        {"name": "tools_find", "title": "tools find NAME", "description": "Find a running program by its name.",
         "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "minLength": 1}}, "required": ["name"]},
         "annotations": {"readOnlyHint": true, "destructiveHint": false}},
        {"name": "tools_update", "title": "tools update", "description": "Run spark-shell update in a terminal window.", "inputSchema": {"type": "object", "properties": {}},
         "annotations": {"readOnlyHint": false, "destructiveHint": false}, "_meta": {"spark-shell/opens": true, "spark-shell/person": true}}
    ]);
    let rows = json!({"title": "tools", "state": "", "rows": [
        {"id": "tools:check", "sign": "blank", "text": "check", "tool": null, "more": [], "columns": ["no problems"], "children": "spark-shell://tools/rows/check", "group": null}
    ], "short": []});
    let script: Script = Box::new(move |v, send| {
        if let Some(r) = ordinary("tools", v, &tools, &rows) {
            return send(r);
        }
        if v["method"] == "tools/call" {
            captured.lock().unwrap().push(v["params"].clone());
            send(result(
                &v["id"],
                json!({"isError": false, "content": [{"type": "text", "text": "done"}], "structuredContent": {"receipt": "done"}}),
            ));
        }
    });
    app.servers.push(stub(0, "tools", script, tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && a.providers[0].tools.len() == 3));
    assert!(app.providers[0].tools.iter().any(|t| t.name == "tools_update" && t.person));
    app.view = View::Section(0);
    app.jobs.clear();
    assert!(
        !app.candidates().iter().any(|(it, _)| matches!(it, Item::Step(_, n) if n == "tools_update")),
        "a person's step is never found by what the words mean"
    );
    let (serial, _, offered) = fill_request(&mut app, "update everything", "tools_find");
    assert_eq!(tool_names(&offered), ["tools_find"], "the fill carries the one step found");
    propose(&mut app, serial, json!([{"name": "tools_update", "arguments": {}}]));
    assert!(
        app.reply.as_ref().is_some_and(|r| r.text.contains("never from a plan")),
        "{:?}",
        app.reply.as_ref().map(|r| r.text.clone())
    );
    assert!(app.staged.is_none() && calls.lock().unwrap().is_empty(), "nothing staged, nothing called");
}
