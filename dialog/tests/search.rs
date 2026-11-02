// The search from Home and the keys every row shares (#169): what is found, as one list (#196), what the
// providers find for the words, Space on any row with a page, Enter on a row that is only its steps.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{search_uri, App, Item, View};
use spark_dialog::mcp::Incoming;
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn tool(name: &str, title: &str) -> Value {
    json!({"name": name, "title": title, "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "minLength": 1}}, "required": ["name"], "additionalProperties": false}})
}

fn row(id: &str, text: &str, tool: &str, more: Value, page: Option<&str>) -> Value {
    let name = id.split_once(' ').map(|(_, n)| n).unwrap_or(text);
    let mut r = json!({"id": id, "sign": "blank", "text": text, "tool": {"name": tool, "arguments": {"name": name}}, "more": more, "columns": [], "children": null, "group": null});
    if let Some(p) = page {
        r["page"] = json!(p);
    }
    r
}

fn apps() -> (Value, Value) {
    let tools = json!([tool("apps_open", "apps open NAME")]);
    let rows = json!({"title": "apps", "rows": [
        row("apps:open firefox", "firefox", "apps_open", json!([]), Some("spark-shell://apps/page/ZmlyZWZveA")),
        row("apps:open micro", "micro", "apps_open", json!([]), Some("spark-shell://apps/page/bWljcm8")),
        row("apps:open mpv", "mpv", "apps_open", json!([]), Some("spark-shell://apps/page/bXB2"))
    ], "short": []});
    (tools, rows)
}

fn notes() -> (Value, Value) {
    let tools = json!([tool("notes_open", "notes open NAME"), tool("notes_trash", "notes trash NAME")]);
    let trash = |n: &str| json!([{"name": "notes_trash", "arguments": {"name": n}, "said": "trash"}]);
    let rows = json!({"title": "notes", "rows": [
        row("notes:open fish.md", "fish recipes", "notes_open", trash("fish.md"), None),
        row("notes:open trip.md", "field trip", "notes_open", trash("trip.md"), None),
        row("notes:open money.md", "finance", "notes_open", trash("money.md"), None),
        row("notes:open books.md", "fiction to read", "notes_open", trash("books.md"), None),
        row("notes:open veg.md", "vegetables", "notes_open", trash("veg.md"), None)
    ], "short": []});
    (tools, rows)
}

fn wifi() -> (Value, Value) {
    let tools = json!([tool("wifi_connect", "wifi connect NAME"), tool("wifi_forget", "wifi forget NAME")]);
    let rows = json!({"title": "wifi", "rows": [
        row("wifi:connect FiberNet", "FiberNet", "wifi_connect", json!([{"name": "wifi_forget", "arguments": {"name": "FiberNet"}, "said": "forget"}]), None),
        {"id": "wifi:saved Cafe", "sign": "blank", "text": "Cafe", "tool": null, "more": [{"name": "wifi_forget", "arguments": {"name": "Cafe"}, "said": "forget"}], "columns": ["saved, not around"], "children": null, "group": null}
    ], "short": []});
    (tools, rows)
}

fn files() -> (Value, Value) {
    let tools = json!([{"name": "files_open", "title": "files open PATH", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}]);
    let rows = json!({"title": "files", "rows": [{"id": "files:root:x", "sign": "opens", "text": "~", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows/eA", "group": null}], "short": []});
    (tools, rows)
}

/// A stub that answers the ordinary requests, a page for any page uri, and `extra` for the uris it names; it keeps
/// every uri it is asked to read.
fn stub_of(label: &'static str, tr: (Value, Value), extra: Vec<(String, Value)>, asked: Arc<Mutex<Vec<String>>>) -> Script {
    let (tools, rows) = tr;
    Box::new(move |v, send| {
        let uri = v.pointer("/params/uri").and_then(Value::as_str).unwrap_or("").to_string();
        if v.get("method").and_then(Value::as_str) == Some("resources/read") {
            asked.lock().unwrap().push(uri.clone());
            if uri.contains("/page/") {
                let page = json!({"title": "Firefox", "lines": ["Firefox", "Web Browser", "", "group      internet"], "bold": [0]});
                return send(result(
                    &v["id"],
                    json!({"contents": [{"uri": uri, "mimeType": "application/json", "text": page.to_string()}]}),
                ));
            }
            if let Some((_, r)) = extra.iter().find(|(u, _)| *u == uri) {
                return send(result(
                    &v["id"],
                    json!({"contents": [{"uri": uri, "mimeType": "application/json", "text": r.to_string()}]}),
                ));
            }
        }
        if let Some(r) = ordinary(label, v, &tools, &rows) {
            send(r);
        }
    })
}

fn file_hits() -> Value {
    let f = |id: &str, text: &str| json!({"id": id, "sign": "blank", "text": text, "tool": {"name": "files_open", "arguments": {"path": format!("/data/ada/{}", text)}}, "more": [], "columns": ["~"], "children": null, "group": null, "page": format!("spark-shell://files/preview/{}", id)});
    json!({"title": "match rep", "rows": [f("files:file:a", "report.pdf"), f("files:file:b", "old-report.txt")], "short": []})
}

struct Run {
    app: App,
    rx: Receiver<Incoming>,
    asked: Arc<Mutex<Vec<String>>>,
}

fn started() -> Run {
    let (mut app, rx, tx) = app_with(&["apps", "notes", "wifi", "files"]);
    let asked = Arc::new(Mutex::new(vec![]));
    let hits = vec![(search_uri("files", "match", "rep"), file_hits())];
    app.servers.push(stub(0, "apps", stub_of("apps", apps(), vec![], asked.clone()), tx.clone()));
    app.servers.push(stub(1, "notes", stub_of("notes", notes(), vec![], asked.clone()), tx.clone()));
    app.servers.push(stub(2, "wifi", stub_of("wifi", wifi(), vec![], asked.clone()), tx.clone()));
    app.servers.push(stub(3, "files", stub_of("files", files(), hits, asked.clone()), tx));
    app.start();
    assert!(
        pump(&mut app, &rx, |a| a.providers.iter().all(|p| p.ready && !p.tools.is_empty())),
        "the stubs never got ready"
    );
    Run { app, rx, asked }
}

fn typed(app: &mut App, words: &str) {
    for c in words.chars() {
        app.typed(c);
    }
}

/// The list as words: a heading as `# name`, a row by its text, a place and a setting by their names.
fn list(app: &App) -> Vec<String> {
    app.items()
        .iter()
        .filter_map(|it| match it {
            Item::Heading(h) => Some(format!("# {}", h)),
            Item::Row(p, r) => Some(app.providers[*p].rows.rows[*r].text.clone()),
            Item::Hit(i) => Some(app.hits[*i].1.text.clone()),
            Item::Dest(d) => Some(spark_dialog::app::DESTS[*d].name.to_string()),
            Item::Setting(i) => Some(spark_dialog::app::SETTINGS[*i].1.to_string()),
            _ => None,
        })
        .collect()
}

#[test]
fn a_search_from_home_is_one_list_the_best_first() {
    let mut r = started();
    typed(&mut r.app, "fi");
    let l = list(&r.app);
    let at = |s: &str| l.iter().position(|x| x == s).unwrap_or_else(|| panic!("{} not in {:?}", s, l));
    assert!(!l.iter().any(|x| x.starts_with("# ")), "no group headings: {:?}", l);
    assert!(!r.app.items().iter().any(|it| matches!(it, Item::Blank)), "no air between groups: {:?}", l);
    // every thing the words name, all four notes among them; a name's start first, the shorter name in a tie, then a
    // word's start (Wi-Fi)
    assert!(
        at("Files") < at("firefox") && at("firefox") < at("finance") && at("finance") < at("FiberNet"),
        "{:?}",
        l
    );
    assert!(
        at("FiberNet") < at("field trip") && at("field trip") < at("fish recipes") && at("fish recipes") < at("fiction to read"),
        "{:?}",
        l
    );
    assert!(at("fiction to read") < at("Wi-Fi"), "{:?}", l);
    assert!(!l.contains(&"vegetables".to_string()) && !l.contains(&"micro".to_string()));
    assert!(
        !l.contains(&"Cafe".to_string()) && !l.contains(&"~".to_string()),
        "two letters of a section's name hold none of its rows: {:?}",
        l
    );
    r.app.set_draft("");
    typed(&mut r.app, "wifi");
    assert!(
        list(&r.app).contains(&"Cafe".to_string()),
        "a section's name holds its rows: {:?}",
        list(&r.app)
    );
    assert!(
        r.app
            .items()
            .iter()
            .any(|it| matches!(it, Item::Setting(i) if spark_dialog::app::SETTINGS[*i].0 == "wifi")),
        "wifi finds the Wi-Fi setting, by its section's name"
    );
}

#[test]
fn a_letter_off_still_finds_and_never_lights_the_row() {
    let mut r = started();
    typed(&mut r.app, "firfox");
    let l = list(&r.app);
    assert!(l.contains(&"firefox".to_string()), "{:?}", l);
    assert!(!r.app.in_list, "a typo never lights a row Enter would run");
    r.app.typed('\u{8}');
}

#[test]
fn the_files_are_asked_once_typing_rests_and_an_answer_for_older_words_lands_nowhere() {
    let mut r = started();
    typed(&mut r.app, "rep");
    let before = list(&r.app);
    let uri = search_uri("files", "match", "rep");
    assert!(!r.asked.lock().unwrap().contains(&uri), "nothing is asked while the words are typed");
    r.app.tick(Instant::now() + Duration::from_millis(300));
    let app = &mut r.app;
    assert!(pump(app, &r.rx, |a| a.hits.len() == 2), "the files' names never came");
    assert!(r.asked.lock().unwrap().contains(&uri));
    // the notes are asked on the same rest; their request may still be on its way when the files' answer is in
    let notes = search_uri("notes", "find", "rep");
    let asked = r.asked.clone();
    assert!(
        pump(&mut r.app, &r.rx, |_| asked.lock().unwrap().contains(&notes)),
        "the notes are asked what they say"
    );
    // the files' names come after every row that was there: nothing above them moved (#196)
    let l = list(&r.app);
    assert_eq!(&l[l.len() - 2..], ["report.pdf", "old-report.txt"], "{:?}", l);
    assert_eq!(&l[..l.len() - 2], &before[..], "the rows before the names stay where they were");
    // a space after the words: the same words, the same names
    r.app.typed(' ');
    assert!(
        list(&r.app).contains(&"report.pdf".to_string()),
        "a space typed after the words keeps what was found"
    );
    // a word more: the names found for the older words are not shown for these
    r.app.typed('x');
    assert!(!list(&r.app).contains(&"report.pdf".to_string()));
}

#[test]
fn space_shows_any_row_that_has_a_page_and_the_keys_name_what_it_is() {
    let mut r = started();
    r.app.view = View::Section(0);
    r.app.came_from.push(View::Home);
    r.app.in_list = true;
    r.app.sel = 0;
    let keys = |a: &App| a.hint().into_iter().map(|(t, _)| t).collect::<String>();
    assert!(keys(&r.app).contains("Preview Space"), "{}", keys(&r.app));
    r.app.typed(' ');
    assert_eq!(r.app.view, View::Preview);
    let app = &mut r.app;
    assert!(
        pump(app, &r.rx, |a| a.preview.as_ref().is_some_and(|p| p.shown.is_some())),
        "the app's page never came"
    );
    assert!(r.asked.lock().unwrap().iter().any(|u| u == "spark-shell://apps/page/ZmlyZWZveA"));
    let k = keys(&r.app);
    assert!(
        k.contains("Back Esc") && k.contains("App \u{2191} \u{2193}") && k.contains("Open Enter"),
        "{}",
        k
    );
    r.app.down();
    assert_eq!(r.app.preview.as_ref().map(|p| p.row().text.clone()), Some("micro".into()), "down: the next app");
}

#[test]
fn a_row_that_is_only_its_steps_opens_them_on_enter() {
    let mut r = started();
    r.app.view = View::Section(2);
    r.app.came_from.push(View::Home);
    r.app.in_list = true;
    let at = r
        .app
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Row(2, 1)))
        .expect("the saved network is a pick");
    r.app.sel = at;
    r.app.enter();
    assert_eq!(r.app.view, View::Steps(2));
    assert_eq!(r.app.step_call_words(0).as_deref(), Some("forget"));
    // Esc comes back with the row lit, so Space and the right arrow go on from it
    r.app.escape();
    assert_eq!(r.app.view, View::Section(2));
    assert!(
        r.app.in_list && r.app.picks().get(r.app.sel) == Some(&Item::Row(2, 1)),
        "the row it came from is lit again"
    );
}

#[test]
fn the_same_words_typed_again_are_asked_again() {
    // the review's N: words cleared, then typed again, ask the providers again: a file made meanwhile is found
    let mut r = started();
    typed(&mut r.app, "rep");
    r.app.tick(Instant::now() + Duration::from_millis(300));
    let uri = search_uri("files", "match", "rep");
    let asked = r.asked.clone();
    assert!(pump(&mut r.app, &r.rx, |_| asked.lock().unwrap().contains(&uri)));
    for _ in 0..3 {
        r.app.backspace();
    }
    r.app.tick(Instant::now() + Duration::from_millis(300));
    let before = r.asked.lock().unwrap().iter().filter(|u| **u == uri).count();
    typed(&mut r.app, "rep");
    r.app.tick(Instant::now() + Duration::from_millis(600));
    let asked = r.asked.clone();
    assert!(
        pump(&mut r.app, &r.rx, |_| asked.lock().unwrap().iter().filter(|u| **u == uri).count() > before),
        "asked again"
    );
}
