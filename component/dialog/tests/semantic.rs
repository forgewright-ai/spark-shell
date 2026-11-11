//! Semantic search (v0.130): typing at Home rests, and the semantic search is asked how close each place, setting,
//! row and step is to what the words mean. The close ones join the list, the best lit when no row is named by the
//! words. Enter on a place or a list found by meaning opens it; anything found by meaning that does something waits
//! in the box for Enter, and a step that needs values has them read by spark, or asked for.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{chat_words, step_text, step_title, App, Helper, Item, Job, Mode, View, CALENDAR_DEST};
use std::sync::mpsc::{Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const SOCK: &str = "/run/test/semantic.sock";

/// A sound provider (the volume's steps, a list of devices) and a theme provider (two palettes), each call kept.
fn serve(app: &mut App, tx: SyncSender<spark_dialog::mcp::Incoming>) -> Arc<Mutex<Vec<Value>>> {
    let calls = Arc::new(Mutex::new(vec![]));
    let out_tools = json!([
        {"name": "out_level", "title": "out level N", "description": "Set the output volume from 0 to 100.",
         "inputSchema": {"type": "object", "properties": {"level": {"type": "integer", "minimum": 0, "maximum": 100}}, "required": ["level"]},
         "annotations": {"destructiveHint": false}},
        {"name": "out_adjust", "title": "out adjust DELTA", "description": "Turn the output volume up or down by DELTA.",
         "inputSchema": {"type": "object", "properties": {"delta": {"type": "integer", "minimum": -100, "maximum": 100}}, "required": ["delta"]},
         "annotations": {"destructiveHint": false}},
        {"name": "out_mute", "title": "out mute", "description": "Mute the output.",
         "inputSchema": {"type": "object", "properties": {}}, "annotations": {"destructiveHint": false}}
    ]);
    let out_rows = json!({"title": "Sound", "state": "volume 70", "rows": [
        {"id": "volume", "sign": "blank", "text": "volume 70", "tool": {"name": "out_level", "arguments": {"level": 70}}},
        {"id": "devices", "sign": "opens", "text": "devices", "tool": null, "children": "spark-shell://out/rows/devices"}
    ]});
    let theme_tools = json!([{"name": "theme_palette", "title": "theme NAME", "description": "Use a palette everywhere.",
        "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "minLength": 1}}, "required": ["name"]},
        "annotations": {"destructiveHint": false}}]);
    let theme_rows = json!({"title": "theme", "state": "everforest-dark", "rows": [
        {"id": "theme:nord", "sign": "blank", "text": "nord", "tool": {"name": "theme_palette", "arguments": {"name": "nord"}}},
        {"id": "theme:everforest-dark", "sign": "check", "text": "everforest-dark", "tool": null}
    ]});
    let script = |label: &'static str, tools: Value, rows: Value, calls: Arc<Mutex<Vec<Value>>>| -> Script {
        Box::new(move |v, send| {
            if let Some(r) = ordinary(label, v, &tools, &rows) {
                return send(r);
            }
            if v["method"] == "tools/call" {
                calls.lock().unwrap().push(v["params"].clone());
                send(result(
                    &v["id"],
                    json!({"isError": false, "content": [{"type": "text", "text": "done"}], "structuredContent": {"receipt": "done"}}),
                ));
            }
        })
    };
    app.servers.push(stub(0, "out", script("out", out_tools, out_rows, calls.clone()), tx.clone()));
    app.servers.push(stub(1, "theme", script("theme", theme_tools, theme_rows, calls.clone()), tx));
    calls
}

/// The home with the semantic search served and a model that answers: the ask row stands under the matches.
fn started() -> (App, Receiver<spark_dialog::mcp::Incoming>, Arc<Mutex<Vec<Value>>>) {
    let (mut app, rx, tx) = app_with(&["out", "theme"]);
    app.cfg.spark = "/bin/sh".into();
    app.cfg.model = true;
    app.model_on = true;
    app.model_name = Some("test-model".into());
    app.cfg.semantic = Some(SOCK.into());
    let calls = serve(&mut app, tx);
    app.start();
    assert!(pump(&mut app, &rx, |a| a
        .providers
        .iter()
        .all(|p| p.ready && !p.tools.is_empty() && !p.rows.rows.is_empty())));
    app.view = View::Home;
    app.jobs.clear();
    (app, rx, calls)
}

fn type_words(app: &mut App, words: &str) {
    for c in words.chars() {
        app.typed(c);
    }
}

/// Typing rests: the semantic search asked about the words in the prompt, its serial and the things sent, in the order
/// the scores come back.
fn rest(app: &mut App, typed: &str) -> (u64, Vec<Item>) {
    type_words(app, typed);
    app.tick(Instant::now() + Duration::from_millis(300));
    let words = app.input.trim().to_string();
    let serial = app
        .jobs
        .iter()
        .rev()
        .find_map(|j| match j {
            Job::Rank(Helper::Rank(s), sock, w, texts) if *s != 0 => {
                assert_eq!((sock.as_str(), w.as_str()), (SOCK, words.as_str()));
                assert!(!texts.is_empty());
                Some(*s)
            }
            _ => None,
        })
        .expect("a semantic search for the words");
    let (s, w, items) = app.rank_sent.clone().expect("the things sent to be ranked");
    assert_eq!((s, w), (serial, words));
    (serial, items)
}

/// The semantic search answers: each thing's closeness to the words, by `score`.
fn answer(app: &mut App, serial: u64, items: &[Item], score: impl Fn(&Item) -> f32) {
    let scores: Vec<f32> = items.iter().map(score).collect();
    app.helper(Helper::Rank(serial), Ok(json!(scores).to_string()));
}

/// One thing close, everything else far.
fn only(app: &mut App, serial: u64, items: &[Item], close: &Item, score: f32) {
    answer(app, serial, items, |it| if it == close { score } else { 0.1 });
}

fn step(name: &str) -> Item {
    Item::Step(0, name.into())
}

fn row(app: &App, text: &str) -> Item {
    for (p, prov) in app.providers.iter().enumerate() {
        if let Some(i) = prov.rows.rows.iter().position(|r| r.text == text) {
            return Item::Row(p, i);
        }
    }
    panic!("no row {}", text)
}

fn lit(app: &App) -> Option<Item> {
    app.in_list.then(|| app.picks().get(app.sel).cloned()).flatten()
}

/// Whether spark was asked anything: a question, a fill, a plan.
fn model_called(app: &App) -> bool {
    app.jobs
        .iter()
        .any(|j| matches!(j, Job::RunInput(Helper::Chat(_) | Helper::Fill(_) | Helper::Want(_), ..)))
}

#[test]
fn no_semantic_search_is_asked_without_its_socket() {
    let (mut app, _, _) = started();
    app.cfg.semantic = None;
    type_words(&mut app, "make it a bit louder");
    app.tick(Instant::now() + Duration::from_millis(300));
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::Rank(..))), "{:?}", app.jobs);
    assert!(app.rank_sent.is_none());
}

#[test]
fn the_rows_are_turned_into_vectors_once_when_every_provider_is_ready() {
    let (mut app, rx, tx) = app_with(&["out", "theme"]);
    app.cfg.semantic = Some(SOCK.into());
    serve(&mut app, tx);
    app.start();
    app.tick(Instant::now());
    assert!(
        !app.jobs.iter().any(|j| matches!(j, Job::Rank(..))),
        "nothing is sent before the providers have their rows"
    );
    assert!(pump(&mut app, &rx, |a| a.providers.iter().all(|p| p.ready)));
    for _ in 0..3 {
        app.tick(Instant::now());
    }
    let warm: Vec<(&str, &str, &Vec<String>)> = app
        .jobs
        .iter()
        .filter_map(|j| match j {
            Job::Rank(Helper::Rank(0), sock, words, texts) => Some((sock.as_str(), words.as_str(), texts)),
            _ => None,
        })
        .collect();
    assert_eq!(warm.len(), 1, "once: {:?}", app.jobs);
    assert_eq!((warm[0].0, warm[0].1), (SOCK, ""), "no words: the vectors only");
    let nord = row(&app, "nord");
    let (_, text) = app.candidates().into_iter().find(|(it, _)| *it == nord).expect("nord is a candidate");
    assert!(warm[0].2.contains(&text), "the rows go: {:?}", warm[0].2);
    assert!(
        app.jobs.iter().all(|j| !matches!(j, Job::Rank(Helper::Rank(s), ..) if *s != 0)),
        "no search before words"
    );
}

#[test]
fn a_ranking_for_older_words_is_ignored() {
    let (mut app, _, _) = started();
    let (old, old_items) = rest(&mut app, "make it louder");
    let (new, items) = rest(&mut app, " please");
    assert!(new > old);
    let searches = app.jobs.iter().filter(|j| matches!(j, Job::Rank(Helper::Rank(s), ..) if *s != 0)).count();
    assert_eq!(searches, 1, "the older search is not sent");
    only(&mut app, old, &old_items, &step("out_adjust"), 0.9);
    assert!(app.meaning.is_none(), "the scores for the older words land nowhere");
    assert!(!app.items().contains(&step("out_adjust")));
    only(&mut app, new, &items, &step("out_adjust"), 0.9);
    assert_eq!(app.meaning.as_ref().map(|(w, f)| (w.as_str(), f.len())), Some(("make it louder please", 1)));
    assert!(app.items().contains(&step("out_adjust")));
    // a word more: what the older words meant is not shown for these
    type_words(&mut app, " now");
    assert!(!app.items().contains(&step("out_adjust")));
}

#[test]
fn a_meaning_match_is_lit_only_when_close_enough() {
    let (mut app, _, _) = started();
    let (serial, items) = rest(&mut app, "make it a bit louder");
    only(&mut app, serial, &items, &step("out_adjust"), 0.71);
    assert!(app.items().contains(&step("out_adjust")), "shown at 0.71");
    assert_eq!(lit(&app), Some(Item::Ask), "not lit under 0.72: Enter asks");
    let (mut app, _, _) = started();
    let (serial, items) = rest(&mut app, "make it a bit louder");
    only(&mut app, serial, &items, &step("out_adjust"), 0.72);
    assert_eq!(lit(&app), Some(step("out_adjust")), "lit at 0.72");
}

#[test]
fn a_row_named_by_the_words_keeps_the_light() {
    let (mut app, _, _) = started();
    let (serial, items) = rest(&mut app, "nord");
    let nord = row(&app, "nord");
    assert_eq!(lit(&app), Some(nord.clone()), "the name lights its row");
    only(&mut app, serial, &items, &step("out_mute"), 0.95);
    assert_eq!(lit(&app), Some(nord), "a closer meaning does not take the light from a name");
    assert!(app.items().contains(&step("out_mute")), "the meaning match is shown under it");
}

#[test]
fn matches_under_the_shown_closeness_are_not_shown_and_five_at_most() {
    let (mut app, _, _) = started();
    let (serial, items) = rest(&mut app, "something about the desktop");
    let mute = step("out_mute");
    // every thing close, a little less each time down the list, and the mute just under 0.65
    let score = |it: &Item| {
        let at = items.iter().position(|x| x == it).unwrap() as f32;
        if *it == mute {
            0.649
        } else {
            0.9 - at * 0.005
        }
    };
    answer(&mut app, serial, &items, score);
    let (_, found) = app.meaning.clone().unwrap();
    assert_eq!(found.len(), 5, "{:?}", found);
    assert!(found.windows(2).all(|w| w[0].0 >= w[1].0), "the closest first: {:?}", found);
    assert!(found.iter().all(|(s, _)| *s >= 0.65));
    assert!(!found.iter().any(|(_, it)| *it == mute) && !app.items().contains(&mute));
    // the mute alone just under the line: still not shown
    let (mut app, _, _) = started();
    let (serial, items) = rest(&mut app, "something about the desktop");
    only(&mut app, serial, &items, &mute, 0.649);
    assert!(!app.items().contains(&mute));
    assert_eq!(app.meaning.as_ref().map(|(_, f)| f.len()), Some(0));
}

#[test]
fn each_thing_is_found_once() {
    let (mut app, _, _) = started();
    let candidates = app.candidates();
    for (it, _) in &candidates {
        assert_eq!(candidates.iter().filter(|(x, _)| x == it).count(), 1, "{:?} sent twice", it);
    }
    // a row found by its name is not repeated by its meaning
    let (serial, items) = rest(&mut app, "nord");
    let nord = row(&app, "nord");
    only(&mut app, serial, &items, &nord, 0.9);
    assert_eq!(app.items().iter().filter(|it| **it == nord).count(), 1);
}

#[test]
fn enter_on_a_place_a_setting_or_a_list_found_by_meaning_opens_it_at_once() {
    // the sound's devices row is its second
    let cases = [
        ("when is my dentist appointment", Item::Dest(CALENDAR_DEST), View::Dest(CALENDAR_DEST)),
        ("the speakers are too loud", Item::Setting(0), View::Section(0)),
        (
            "which speakers do I have",
            Item::Row(0, 1),
            View::Folder(0, "spark-shell://out/rows/devices".into()),
        ),
    ];
    for (words, it, opens) in cases {
        let (mut app, _, calls) = started();
        assert_eq!(row(&app, "devices"), Item::Row(0, 1));
        let (serial, items) = rest(&mut app, words);
        only(&mut app, serial, &items, &it, 0.9);
        assert_eq!(lit(&app), Some(it), "{}", words);
        app.enter();
        assert_eq!(app.view, opens, "{}", words);
        assert!(app.staged.is_none() && !model_called(&app) && calls.lock().unwrap().is_empty(), "{}", words);
    }
}

#[test]
fn a_row_found_by_meaning_that_acts_waits_in_the_box_and_by_its_name_runs_at_once() {
    let (mut app, rx, calls) = started();
    let (serial, items) = rest(&mut app, "make everything darker");
    let nord = row(&app, "nord");
    only(&mut app, serial, &items, &nord, 0.9);
    assert_eq!(lit(&app), Some(nord.clone()));
    app.enter();
    assert!(app.staged_now() && app.input.contains("nord"), "the step waits in the box: {:?}", app.input);
    assert!(calls.lock().unwrap().is_empty() && !model_called(&app), "nothing runs before Enter");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    let sent = calls.lock().unwrap()[0].clone();
    assert_eq!((&sent["name"], &sent["arguments"]), (&json!("theme_palette"), &json!({"name": "nord"})));
    // the same row named by the words: Enter runs it, as it always did
    let (mut app, rx, calls) = started();
    let (serial, items) = rest(&mut app, "nord");
    only(&mut app, serial, &items, &nord, 0.9);
    app.enter();
    assert!(app.staged.is_none());
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()), "the named row runs at once");
    assert_eq!(calls.lock().unwrap()[0]["arguments"]["name"], "nord");
}

#[test]
fn a_meaning_match_follows_its_row_when_the_rows_change_and_a_row_gone_is_no_match() {
    let (mut app, _rx, calls) = started();
    let (serial, items) = rest(&mut app, "make everything darker");
    let nord = row(&app, "nord");
    only(&mut app, serial, &items, &nord, 0.9);
    // a row comes in before it: the match is nord still, by its id, never the row now at its old place
    let dracula = spark_dialog::model::rows(
        r#"{"title":"theme","rows":[{"id":"theme:dracula","text":"dracula","tool":{"name":"theme_palette","arguments":{"name":"dracula"}}}]}"#,
    )
    .unwrap()
    .rows
    .remove(0);
    app.providers[1].rows.rows.insert(0, dracula);
    assert_eq!(lit(&app), Some(row(&app, "nord")), "the light is on nord where it stands now");
    app.enter();
    assert!(
        app.staged_now() && app.input.contains("nord") && !app.input.contains("dracula"),
        "{:?}",
        app.input
    );
    assert!(calls.lock().unwrap().is_empty());
    // the rows gone: the match goes with them, and nothing reads past the end of the list
    let (mut app, _rx, _calls) = started();
    let (serial, items) = rest(&mut app, "make everything darker");
    let nord = row(&app, "nord");
    only(&mut app, serial, &items, &nord, 0.9);
    app.providers[1].rows.rows.clear();
    assert!(!app.picks().iter().any(|it| matches!(it, Item::Row(1, _))), "{:?}", app.picks());
}

#[test]
fn in_the_rest_of_one_kind_a_row_found_by_meaning_that_acts_still_waits_for_enter() {
    let (mut app, _rx, calls) = started();
    let words = "make everything darker";
    let (serial, items) = rest(&mut app, words);
    let nord = row(&app, "nord");
    only(&mut app, serial, &items, &nord, 0.9);
    // the rest of the kind, as its More row opens it: the prompt there starts empty, the words are the view's
    app.set_draft("");
    app.view = View::Found(spark_dialog::app::Found::of("theme"), words.into());
    let at = app.picks().iter().position(|it| *it == nord).expect("nord among the rest of its kind");
    (app.in_list, app.sel) = (true, at);
    app.enter();
    assert!(app.staged_now() && app.input.contains("nord"), "the step waits in the box: {:?}", app.input);
    assert!(calls.lock().unwrap().is_empty(), "nothing runs before Enter");
}

#[test]
fn a_fill_with_a_value_left_asks_it_then_the_whole_step_waits_and_spark_s_value_meets_the_gate() {
    let (mut app, rx, calls) = started();
    // a palette and where it goes: spark reads the name, the scope is asked
    app.providers[1].tools[0].schema = json!({"type": "object", "properties": {
        "name": {"type": "string", "minLength": 1}, "scope": {"type": "string", "minLength": 1}}, "required": ["name", "scope"]});
    // its rows name the palettes with both values, so the gate holds a step to them
    let nord = app.providers[1].rows.rows.iter_mut().find(|r| r.text == "nord").unwrap();
    nord.tool.as_mut().unwrap().arguments.insert("scope".into(), json!("all"));
    let (serial, items) = rest(&mut app, "use the bogus palette");
    only(&mut app, serial, &items, &Item::Step(1, "theme_palette".into()), 0.9);
    app.enter();
    let fill = app
        .jobs
        .iter()
        .find_map(|j| match j {
            Job::RunInput(Helper::Fill(s), _, _) => Some(*s),
            _ => None,
        })
        .expect("spark is asked for the step's values");
    app.helper(
        Helper::Fill(fill),
        Ok(json!({"answer": "", "steps": [{"name": "theme_palette", "arguments": {"name": "bogus"}}], "refused": []}).to_string()),
    );
    assert!(matches!(&app.mode, Mode::Ask { field, .. } if field == "scope"), "{:?}", app.mode);
    type_words(&mut app, "all");
    app.enter();
    assert!(
        app.staged_now() && app.input.contains("bogus") && app.input.contains("all"),
        "every value seen: {:?}",
        app.input
    );
    assert!(calls.lock().unwrap().is_empty(), "nothing runs before Enter");
    app.enter();
    assert!(
        !pump_for(&mut app, &rx, QUIET, |_| !calls.lock().unwrap().is_empty()),
        "a name no row holds never runs"
    );
    assert!(app.reply.as_ref().is_some_and(|r| r.text.contains("bogus")), "{:?}", app.reply);
}

#[test]
fn a_fill_that_comes_back_empty_for_a_step_whose_values_are_all_optional_waits_for_enter() {
    let (mut app, _rx, calls) = started();
    app.providers[0].tools[1].schema = json!({"type": "object", "properties": {"delta": {"type": "integer"}}});
    let (serial, items) = rest(&mut app, "turn it up");
    only(&mut app, serial, &items, &step("out_adjust"), 0.9);
    app.enter();
    let fill = app
        .jobs
        .iter()
        .find_map(|j| match j {
            Job::RunInput(Helper::Fill(s), _, _) => Some(*s),
            _ => None,
        })
        .expect("spark is asked for the step's values");
    app.helper(Helper::Fill(fill), Ok(json!({"answer": "", "steps": [], "refused": []}).to_string()));
    assert!(app.staged_now(), "the step waits in the box: {:?} {:?}", app.input, app.mode);
    assert!(calls.lock().unwrap().is_empty(), "nothing runs before Enter");
}

#[test]
fn a_step_that_takes_nothing_found_by_meaning_waits_in_the_box_and_a_second_enter_runs_it() {
    let (mut app, rx, calls) = started();
    let (serial, items) = rest(&mut app, "silence the speakers");
    only(&mut app, serial, &items, &step("out_mute"), 0.9);
    assert_eq!(lit(&app), Some(step("out_mute")));
    app.enter();
    assert!(app.staged_now() && app.input == "out mute", "{:?}", app.input);
    assert!(!model_called(&app), "a step that takes nothing has nothing for spark to read");
    assert!(calls.lock().unwrap().is_empty());
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert_eq!(calls.lock().unwrap()[0]["name"], "out_mute");
}

#[test]
fn a_step_whose_fill_comes_back_empty_asks_its_value_and_a_number_typed_goes_as_a_number() {
    let (mut app, rx, calls) = started();
    let (serial, items) = rest(&mut app, "make it a bit louder");
    only(&mut app, serial, &items, &step("out_adjust"), 0.9);
    app.enter();
    let fill = app
        .jobs
        .iter()
        .find_map(|j| match j {
            Job::RunInput(Helper::Fill(s), _, _) => Some(*s),
            _ => None,
        })
        .expect("spark is asked for the step's values");
    app.helper(Helper::Fill(fill), Ok(json!({"answer": "", "steps": [], "refused": []}).to_string()));
    assert!(matches!(&app.mode, Mode::Ask { field, .. } if field == "delta"), "{:?}", app.mode);
    type_words(&mut app, "5");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    let sent = calls.lock().unwrap()[0].clone();
    assert_eq!(sent["name"], "out_adjust");
    assert_eq!(sent["arguments"], json!({"delta": 5}), "5 is a number, not the text 5");
}

#[test]
fn a_value_that_is_sparks_own_placeholder_is_asked_for_and_a_whole_fill_waits_for_enter() {
    let (mut app, _rx, calls) = started();
    let fill = |app: &mut App, reply: Value| {
        app.search_sent.clear(); // the same words, searched again
        let (serial, items) = rest(app, "make it a bit louder");
        only(app, serial, &items, &step("out_adjust"), 0.9);
        app.enter();
        let s = app
            .jobs
            .iter()
            .find_map(|j| match j {
                Job::RunInput(Helper::Fill(s), _, _) => Some(*s),
                _ => None,
            })
            .expect("spark is asked for the step's values");
        app.jobs.clear();
        app.helper(Helper::Fill(s), Ok(reply.to_string()));
    };
    // a model with nothing to write writes the brief's placeholder: no value, so the form asks for it
    fill(
        &mut app,
        json!({"answer": "", "steps": [{"name": "out_adjust", "arguments": {"delta": "TEXT"}}], "refused": []}),
    );
    assert!(matches!(&app.mode, Mode::Ask { field, .. } if field == "delta"), "{:?}", app.mode);
    assert!(!app.staged_now(), "nothing is proposed with a placeholder in it");
    app.escape();
    app.set_draft("");
    // every value read: the step waits in the box, and nothing runs before Enter
    fill(
        &mut app,
        json!({"answer": "", "steps": [{"name": "out_adjust", "arguments": {"delta": 5}}], "refused": []}),
    );
    assert!(app.staged_now() && app.input == "out adjust 5", "{:?}", app.input);
    assert!(calls.lock().unwrap().is_empty());
}

#[test]
fn with_no_model_a_step_found_by_meaning_asks_its_value_and_calls_no_model() {
    let (mut app, rx, calls) = started();
    app.model_on = false;
    let (serial, items) = rest(&mut app, "make it a bit louder");
    only(&mut app, serial, &items, &step("out_adjust"), 0.9);
    // no ask row to hold the light: Down goes to the step
    app.down();
    assert_eq!(lit(&app), Some(step("out_adjust")));
    app.enter();
    assert!(!model_called(&app));
    assert!(matches!(&app.mode, Mode::Ask { field, .. } if field == "delta"), "{:?}", app.mode);
    type_words(&mut app, "-5");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert_eq!(calls.lock().unwrap()[0]["arguments"]["delta"], -5);
}

#[test]
fn a_step_is_known_by_its_title_without_its_capital_words() {
    assert_eq!(step_title("out adjust DELTA"), "out adjust");
    assert_eq!(step_title("files rename PATH NAME"), "files rename");
    assert_eq!(step_title("out mute"), "out mute");
}

#[test]
fn a_step_is_ranked_by_its_sections_name_its_verb_and_the_first_sentence_of_what_it_does() {
    let adjust = "Change the volume by delta percentage points from its fresh native level. Native readback must match.";
    assert_eq!(
        step_text("out", "out adjust DELTA", adjust),
        "sound adjust: Change the volume by delta percentage points from its fresh native level."
    );
    // a title that does not start with the label keeps its words; a description of one sentence is whole
    assert_eq!(
        step_text("display", "screen scale", "Set the scale on one screen"),
        "display screen scale: Set the scale on one screen"
    );
}

#[test]
fn the_words_asked_are_one_question_for_spark() {
    assert_eq!(chat_words("is the sound on"), "is the sound on");
    assert_eq!(chat_words("  update my notes  "), "update my notes", "never one of spark's commands");
    assert_eq!(chat_words("volume"), "volume?", "a single word is a question too");
    assert_eq!(chat_words("volume?"), "volume?");
    assert_eq!(
        chat_words("@notes.md what is in it"),
        "notes.md what is in it",
        "only the file attached is sent"
    );
    assert_eq!(chat_words("@@notes.md"), "notes.md?");
}

/// The theme's setting, as Home and every list name it.
fn theme_setting() -> Item {
    Item::Setting(spark_dialog::app::SETTINGS.iter().position(|s| s.0 == "theme").unwrap())
}

/// The list of apps, opened from Home, with two apps read: words typed there search the apps by name (#250).
fn in_apps(app: &mut App) {
    app.view = View::Apps;
    app.came_from.push(View::Home);
    app.apps.prefs = spark_dialog::apps::preferences::Preferences::default();
    app.apps.preference_error = None;
    app.apps.path = std::env::temp_dir().join(format!("semantic-apps-{}", std::process::id())).join("apps.json");
    app.apps.pending = Some((1, "catalog".into()));
    app.apps
        .receive(
            1,
            json!({"apps": [
                {"id": "firefox.desktop", "name": "Firefox", "generic_name": "Web Browser", "categories": ["Network"]},
                {"id": "editor.desktop", "name": "Editor", "generic_name": "Text Editor", "categories": ["Utility"]}
            ]}),
        )
        .unwrap();
}

fn an_app(app: &App) -> bool {
    app.items()
        .iter()
        .any(|it| matches!(it, Item::Apps(l) if matches!(l.action, Some(spark_dialog::apps::Action::Launch(_)))))
}

#[test]
fn in_the_list_of_apps_words_that_name_no_app_find_by_meaning_and_enter_opens_the_setting() {
    // the owner's case: `change theme` typed in the list of apps went to spark, which answered with its own look
    let (mut app, _, calls) = started();
    in_apps(&mut app);
    let (serial, items) = rest(&mut app, "change theme");
    assert!(!an_app(&app), "no app by these words");
    assert_eq!(lit(&app), Some(Item::Ask), "before the scores come: the ask row, as before");
    only(&mut app, serial, &items, &theme_setting(), 0.821);
    let list = app.items();
    let at = |x: &Item| list.iter().position(|it| it == x);
    let heading = at(&Item::Heading("settings".into())).expect("what the words mean, under its kind");
    let theme = at(&theme_setting()).expect("the theme's setting is shown");
    let ask = at(&Item::Ask).expect("the ask row stays");
    assert!(
        heading < theme && theme < ask,
        "the meaning under the list's own rows, the ask row last: {:?}",
        list
    );
    assert_eq!(lit(&app), Some(theme_setting()), "close enough: lit, so Enter opens it");
    app.enter();
    assert_eq!(app.view, View::Section(1), "Enter opened the theme");
    assert!(app.staged.is_none() && !model_called(&app) && calls.lock().unwrap().is_empty());
    app.back_key();
    assert_eq!(app.view, View::Apps, "Esc goes back to the list of apps");
}

#[test]
fn in_the_list_of_apps_a_meaning_under_the_lit_closeness_is_shown_and_the_ask_row_keeps_the_light() {
    let (mut app, _, _) = started();
    in_apps(&mut app);
    let (serial, items) = rest(&mut app, "change theme");
    only(&mut app, serial, &items, &theme_setting(), 0.70);
    assert!(app.items().contains(&theme_setting()), "shown at 0.70");
    assert_eq!(lit(&app), Some(Item::Ask), "not lit under 0.72: Enter asks");
}

#[test]
fn in_the_list_of_apps_an_app_named_by_the_words_keeps_the_light_and_nothing_else_is_shown() {
    let (mut app, _, _) = started();
    in_apps(&mut app);
    let (serial, items) = rest(&mut app, "firefox");
    only(&mut app, serial, &items, &theme_setting(), 0.95);
    assert!(an_app(&app));
    assert!(matches!(lit(&app), Some(Item::Apps(_))), "the app keeps the light: {:?}", lit(&app));
    assert!(!app.items().contains(&theme_setting()), "words that name an app search the apps alone");
}

#[test]
fn in_the_list_of_apps_a_step_found_by_meaning_waits_in_the_box_and_a_second_enter_runs_it() {
    let (mut app, rx, calls) = started();
    in_apps(&mut app);
    let (serial, items) = rest(&mut app, "silence the speakers");
    only(&mut app, serial, &items, &step("out_mute"), 0.9);
    assert_eq!(lit(&app), Some(step("out_mute")));
    app.enter();
    assert!(app.staged_now() && app.input == "out mute", "{:?}", app.input);
    assert_eq!(app.view, View::Apps);
    assert!(an_app(&app), "the step in the box searches no app: the list is whole under it");
    let keys: String = app.hint().iter().map(|(t, _)| t.clone()).collect();
    assert!(keys.contains("Run") && keys.contains("Discard"), "the keys are the step's: {:?}", keys);
    assert!(calls.lock().unwrap().is_empty() && !model_called(&app), "nothing runs before Enter");
    app.enter();
    assert!(pump(&mut app, &rx, |_| !calls.lock().unwrap().is_empty()));
    assert_eq!(calls.lock().unwrap()[0]["name"], "out_mute");
}

#[test]
fn in_a_section_words_that_name_none_of_its_rows_find_by_meaning_and_a_row_named_keeps_the_light() {
    // the theme's section: `make it louder` names none of its rows, and the volume's step is found elsewhere
    let (mut app, _, _) = started();
    app.view = View::Section(1);
    app.came_from.push(View::Home);
    let (serial, items) = rest(&mut app, "make it louder");
    only(&mut app, serial, &items, &step("out_adjust"), 0.9);
    let list = app.items();
    assert_eq!(list.first(), Some(&Item::Heading("settings".into())), "no row of air over it: {:?}", list);
    assert_eq!(lit(&app), Some(step("out_adjust")));
    assert_eq!(list.last(), Some(&Item::Ask), "the ask row last");
    // a row of the section named by the words: it keeps the light, and the section is searched alone
    let (mut app, _, _) = started();
    app.view = View::Section(1);
    app.came_from.push(View::Home);
    let (serial, items) = rest(&mut app, "nord");
    only(&mut app, serial, &items, &step("out_mute"), 0.95);
    assert_eq!(lit(&app), Some(row(&app, "nord")));
    assert!(!app.items().contains(&step("out_mute")));
}

#[test]
fn a_near_tie_within_a_section_lights_the_sections_own_setting() {
    // the box's case: `change theme` put the moving wallpaper's row 0.007 above the theme itself
    let scores = |row_score: f32, setting: Item, setting_score: f32| {
        let (mut app, _, _) = started();
        in_apps(&mut app);
        let (serial, items) = rest(&mut app, "change theme");
        let nord = row(&app, "nord");
        answer(&mut app, serial, &items, |it| {
            if *it == nord {
                row_score
            } else if *it == setting {
                setting_score
            } else {
                0.1
            }
        });
        (lit(&app), nord)
    };
    let (lit_now, _) = scores(0.828, theme_setting(), 0.821);
    assert_eq!(
        lit_now,
        Some(theme_setting()),
        "within 0.02 of its own row: the theme is lit, and Enter opens it"
    );
    let (lit_now, nord) = scores(0.85, theme_setting(), 0.821);
    assert_eq!(lit_now, Some(nord), "further than the tie: the row keeps the light");
    let (lit_now, nord) = scores(0.828, Item::Setting(0), 0.825);
    assert_eq!(lit_now, Some(nord), "another section's setting never takes it");
}

#[test]
fn without_its_socket_no_view_asks_the_semantic_search() {
    let (mut app, _, _) = started();
    app.cfg.semantic = None;
    in_apps(&mut app);
    type_words(&mut app, "change theme");
    app.tick(Instant::now() + Duration::from_millis(300));
    assert!(!app.jobs.iter().any(|j| matches!(j, Job::Rank(..))), "{:?}", app.jobs);
    assert_eq!(lit(&app), Some(Item::Ask), "the ask row, as before");
}
