// The display page (v0.167): the map of the screens over its rows, the keys and the pointer on it, a screen's own
// page, and the card of a change on trial.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, HintKey, Item, Mode, Provider, View, SETTINGS_DEST};
use spark_dialog::display::screens::Side;
use spark_dialog::draw::{Size, Step};
use spark_dialog::grid::{Buffer, Rect};
use spark_dialog::mcp::Incoming;
use spark_dialog::reply::Mark;
use spark_dialog::scene::{kind, Kind, Scene, Target};
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn uri(name: &str) -> String {
    format!("spark-shell://display/rows/screen/{name}")
}

/// Two screens that are on, one turned at the left of the other, and one that is off.
fn screens() -> Value {
    json!([
        {"name": "DP-3", "text": "MB16FC", "x": 0, "y": 0, "w": 1200, "h": 1920, "on": true, "main": false,
         "picture": "/srv/thumbs/a.png", "children": uri("DP-3")},
        {"name": "HDMI-A-1", "text": "T24i-30", "x": 1200, "y": 420, "w": 1920, "h": 1080, "on": true, "main": true,
         "picture": "/srv/thumbs/b.png", "children": uri("HDMI-A-1")},
        {"name": "DP-1", "text": "LG TV", "x": 0, "y": 0, "w": 0, "h": 0, "on": false, "main": false, "children": uri("DP-1")}
    ])
}

fn values(shown: &[&str]) -> Vec<Value> {
    shown.iter().map(|s| json!({"shown": s, "sent": s})).collect()
}

fn rows_of(screens: Value) -> Value {
    let levels: Vec<String> = (1..21).map(|n| (n * 5).to_string()).collect();
    let levels: Vec<Value> = levels.iter().map(|n| json!({"shown": format!("{n}%"), "sent": n})).collect();
    let step = |name: &str, values: Vec<Value>, words: [&str; 2]| json!({"values": values, "at": 1, "set": {"name": name, "arguments": {}}, "key": "to", "words": words});
    let one = |name: &str, text: &str, words: &str| json!({"id": format!("display:screen:{name}"), "text": text, "sign": "opens", "columns": [words], "children": uri(name), "group": "screens"});
    json!({"title": "display", "state": "3 screens", "rows": [
        {"id": "display:map", "text": "screens", "group": "screens", "screens": screens, "move": {"name": "display_position", "arguments": {}}},
        one("DP-3", "MB16FC", "1920x1200 \u{b7} turned"),
        one("HDMI-A-1", "T24i-30", "1920x1080 \u{b7} main"),
        one("DP-1", "LG TV", "off"),
        {"id": "display:level", "text": "level", "group": "brightness", "step": step("display_brightness", levels, ["dimmer", "brighter"])},
        {"id": "display:idle", "text": "idle screen", "group": "idle and lock", "step": step("display_idle", values(&["5 min", "10 min", "15 min", "never"]), ["sooner", "later"])},
        {"id": "display:saver", "text": "saver", "group": "idle and lock", "step": step("display_saver", values(&["clock", "art"]), ["back", "next"])},
        {"id": "display:lock", "text": "lock", "group": "idle and lock", "step": step("display_lock", values(&["5 min", "10 min", "never"]), ["sooner", "later"])}
    ], "short": []})
}

/// A screen's own page, and its resolutions.
fn page_of(at: &str) -> Value {
    let name = at.split("/screen/").nth(1).unwrap_or("").split('/').next().unwrap_or("");
    let a = json!({ "screen": name });
    if at.ends_with("/modes") {
        return json!({"title": "resolution", "state": "T24i-30", "rows": [
            {"id": "m:1", "sign": "check", "text": "1920x1080 60 Hz", "tool": null, "back": true},
            {"id": "m:2", "sign": "blank", "text": "1280x720 60 Hz", "tool": {"name": "display_mode", "arguments": {"screen": name, "mode": "1280x720@60Hz"}}, "back": true}
        ]});
    }
    json!({"title": "T24i-30", "state": "1920x1080 60 Hz", "rows": [
        {"id": "s:on", "text": "in use", "switch": {"on": true, "turn_on": {"name": "display_on", "arguments": a}, "turn_off": {"name": "display_off", "arguments": a}}},
        {"id": "s:main", "text": "main screen", "columns": ["this one"], "muted": true},
        {"id": "s:mode", "text": "resolution", "sign": "opens", "columns": ["1920x1080 60 Hz"], "children": format!("{}/modes", uri(name)), "choice": true},
        {"id": "s:scale", "text": "scale", "step": {"values": values(&["75%", "100%", "125%", "150%", "200%"]), "at": 1, "set": {"name": "display_scale", "arguments": a}, "key": "scale", "words": ["smaller", "larger"]}},
        {"id": "s:turn", "text": "orientation", "step": {"values": values(&["upright", "right", "upside down", "left"]), "at": 0, "set": {"name": "display_transform", "arguments": a}, "key": "transform", "words": ["back", "next"]}},
        {"id": "s:beside", "text": "beside MB16FC", "step": {"values": values(&["left", "right", "above", "below"]), "at": 1, "set": {"name": "display_place", "arguments": a}, "key": "side", "words": ["back", "next"]}}
    ]})
}

fn tools() -> Value {
    let text = json!({"type": "string"});
    let schema = json!({"type": "object", "properties": {"screen": text, "mode": text, "scale": text, "transform": text}});
    let tool = |name: &str, risky: bool| json!({"name": name, "title": name.replace('_', " "), "description": "d", "inputSchema": schema, "annotations": {"destructiveHint": risky}});
    json!([
        tool("display_position", false),
        tool("display_place", false),
        tool("display_brightness", false),
        tool("display_mode", false),
        tool("display_scale", false),
        tool("display_transform", false),
        tool("display_off", false),
        tool("display_on", false),
        tool("display_keep", false),
        tool("display_back", false),
        tool("display_wipe", true)
    ])
}

/// The page with nothing behind it, as a window of the dialog's own shows it.
fn display() -> App {
    let mut a = App::new(
        Config {
            band: false,
            ..Config::default()
        },
        &[],
    );
    (a.pixels, a.window_focused, a.pane_fits) = (true, true, true);
    let mut p = Provider::new("display");
    (p.ready, p.title) = (true, "3 screens".into());
    p.rows = spark_dialog::model::rows(&rows_of(screens()).to_string()).unwrap();
    p.tools = spark_dialog::model::tools(&json!({ "tools": tools() }));
    a.providers = vec![p];
    a.view = View::Section(0);
    a.came_from = vec![View::Home];
    (a.in_list, a.sel, a.list_keys) = (true, 0, true);
    a
}

type Answer = Box<dyn FnMut(&str, &Value) -> Value + Send>;

/// The page over a provider: every call it gets, and `answer` what each call's result carries.
fn served(mut answer: Answer) -> (App, Receiver<Incoming>, Arc<Mutex<Vec<Value>>>) {
    let (mut app, rx, tx) = app_with(&["display"]);
    (app.pixels, app.window_focused, app.pane_fits) = (true, true, true);
    let calls = Arc::new(Mutex::new(vec![]));
    let log = calls.clone();
    let script: Script = Box::new(move |v, send| {
        let at = v.pointer("/params/uri").and_then(Value::as_str).unwrap_or("");
        match v.get("method").and_then(Value::as_str) {
            Some("resources/read") if at.contains("/screen/") => {
                let text = page_of(at).to_string();
                send(result(
                    &v["id"],
                    json!({"contents": [{"uri": at, "mimeType": "application/json", "text": text}]}),
                ));
            }
            Some("tools/call") => {
                log.lock().unwrap().push(v["params"].clone());
                let sc = answer(v["params"]["name"].as_str().unwrap_or(""), &v["params"]["arguments"]);
                let said = sc.get("refused").and_then(Value::as_str).map(str::to_string);
                let text = said.clone().unwrap_or_else(|| "done".into());
                let mut r = json!({"content": [{"type": "text", "text": text}], "isError": said.is_some()});
                if said.is_none() {
                    r["structuredContent"] = sc;
                }
                send(result(&v["id"], r));
            }
            _ => {
                if let Some(r) = ordinary("display", v, &tools(), &rows_of(screens())) {
                    send(r);
                }
            }
        }
    });
    app.servers.push(stub(0, "display", script, tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.view = View::Section(0);
    app.came_from = vec![View::Home];
    (app.in_list, app.sel, app.list_keys) = (true, 0, true);
    (app, rx, calls)
}

/// The calls made, each its name and its arguments.
fn calls(log: &Arc<Mutex<Vec<Value>>>) -> Vec<Value> {
    let one = |v: &Value| json!({"name": v["name"], "arguments": v["arguments"]});
    log.lock().unwrap().iter().map(one).collect()
}

/// Where each screen of the map takes a click: its box.
fn places(s: &Scene) -> Vec<(String, (f64, f64, f64, f64))> {
    s.hits
        .iter()
        .filter_map(|h| match &h.target {
            Target::Screen(_, name) => Some((name.clone(), (h.x, h.y, h.w, h.h))),
            _ => None,
        })
        .collect()
}

fn place(s: &Scene, name: &str) -> (f64, f64, f64, f64) {
    places(s).into_iter().find(|p| p.0 == name).unwrap_or_else(|| panic!("no {name}")).1
}

/// The frame of a screen, two pixels wide, where one is in the accent.
fn framed(s: &Scene, b: (f64, f64, f64, f64)) -> bool {
    fills(s, ACCENT).contains(&(b.0, b.1, b.2, 2.0))
}

fn rect(a: &App, name: &str) -> (i32, i32) {
    let r = a.providers[0].rows.rows[0].map.as_ref().unwrap().named(name).unwrap().rect;
    (r.x, r.y)
}

// ---------------------------------------------------------------- the page

#[test]
fn the_page_starts_with_the_screens_to_scale_and_names_its_groups_small() {
    let mut a = display();
    assert_eq!(kind(&a), Kind::Page);
    let s = frame(&mut a, 600.0, 800.0);
    assert!(s.grid.is_none());
    // where you are: home, display, what it holds
    for w in ["home", "display", "3 screens"] {
        assert_eq!(word(&s, w).2, Size::Small);
    }
    // the groups, small and in the accent, in their order
    let heads = ["screens", "brightness", "idle and lock"].map(|h| word(&s, h));
    assert!(heads.iter().all(|h| h.2 == Size::Small && h.3 == ACCENT), "{heads:?}");
    assert!(heads[0].1 < heads[1].1 && heads[1].1 < heads[2].1);
    // each group has air over it: it stands nearer its own rows than the ones before it
    let (before, own) = (heads[1].1 - word(&s, "LG TV").1, word(&s, "level").1 - heads[1].1);
    assert!(before > own + 8.0, "{before} over it, {own} under it");
    // the map first, then a row each, then the settings
    let (dp, hdmi, off) = (place(&s, "DP-3"), place(&s, "HDMI-A-1"), place(&s, "DP-1"));
    assert!(heads[0].1 < dp.1 && dp.1 + dp.3 < word(&s, "1920x1200 \u{b7} turned").1);
    // to scale: 1200 by 1920 beside 1920 by 1080, a pixel of the ground between, its place 420 under the other's top
    let scale = s.map.unwrap().scale;
    assert!(
        (dp.3 - 1920.0 * scale).abs() <= 3.0 && (hdmi.2 - 1920.0 * scale).abs() <= 3.0,
        "{dp:?} {hdmi:?}"
    );
    assert!((hdmi.1 - dp.1 - 420.0 * scale).abs() <= 1.0);
    assert_eq!(hdmi.0 - (dp.0 + dp.2), 2.0);
    assert!((150.0..=220.0).contains(&dp.3), "about 200 at most in the regular window: {}", dp.3);
    // the one that is off stands past the rest, and nothing is wider than the window
    assert!(off.0 > hdmi.0 + hdmi.2 && off.0 + off.2 <= 600.0);
    let (left, right) = (dp.0, 600.0 - (off.0 + off.2));
    assert!((left - right).abs() <= 2.0, "in the middle: {left} {right}");
    // each with what it shows, a name at its foot, main said of the main one, off of the one that is off
    let covers: Vec<_> = s
        .steps
        .iter()
        .filter_map(|st| match st {
            Step::Cover { x, y, w, h, file } => Some((file.clone(), (*x, *y, *w, *h))),
            _ => None,
        })
        .collect();
    assert_eq!(covers, [("/srv/thumbs/a.png".to_string(), dp), ("/srv/thumbs/b.png".to_string(), hdmi)]);
    let inside = |text: &str, b: (f64, f64, f64, f64)| {
        let all = words(&s);
        all.iter()
            .any(|w| w.0 == text && w.3 == Size::Small && w.1 > b.0 && w.1 < b.0 + b.2 && w.2 > b.1 && w.2 < b.1 + b.3)
    };
    for (text, b) in [("MB16FC", dp), ("T24i-30", hdmi), ("main", hdmi), ("LG TV", off), ("off", off)] {
        assert!(inside(text, b), "{text} in its screen");
    }
    assert!(!inside("main", dp));
    // the one that is off is hollow: a line around it and nothing in it, and its row steps back as it does
    assert!(!s.steps.iter().any(|st| matches!(st, Step::Fill { x, y, w, h, .. } if (*x, *y, *w, *h) == off)));
    assert!(fills(&s, MUTED).contains(&(off.0, off.1, off.2, 1.0)));
    let row = words(&s).into_iter().find(|w| w.0 == "LG TV" && w.3 == Size::Main).unwrap();
    assert_eq!(row.4, MUTED);
    // the words of a screen's row stand on the options' column
    assert_eq!(word(&s, "1920x1080 \u{b7} main").0, word(&s, "dimmer").0);
}

#[test]
fn the_lit_screen_is_framed_and_nothing_moves_as_the_light_does() {
    let mut a = display();
    let first = frame(&mut a, 600.0, 800.0);
    let lit = |s: &Scene| places(s).into_iter().filter(|(_, b)| framed(s, *b)).map(|p| p.0).collect::<Vec<_>>();
    assert_eq!(lit(&first), ["HDMI-A-1"], "the main one, before one is chosen");
    // the row's bar touches both sides of the window
    assert!(
        fills(&first, LIT).iter().any(|f| f.0 == 0.0 && f.2 == 600.0 && f.3 > 180.0),
        "{:?}",
        fills(&first, LIT)
    );
    // a screen's own row lit: its screen is
    for (sel, name) in [(1, "DP-3"), (2, "HDMI-A-1"), (3, "DP-1")] {
        a.sel = sel;
        let s = frame(&mut a, 600.0, 800.0);
        assert_eq!(lit(&s), [name]);
        assert_eq!(places(&s), places(&first), "nothing moved");
    }
    a.sel = 4;
    assert!(lit(&frame(&mut a, 600.0, 800.0)).is_empty(), "a setting lit: no screen is");
    a.in_list = false;
    let s = frame(&mut a, 600.0, 800.0);
    assert!(lit(&s).is_empty());
    assert_eq!(places(&s), places(&first));
}

#[test]
fn the_page_holds_at_every_width() {
    for (w, h) in [(370.0, 420.0), (440.0, 800.0), (600.0, 800.0), (900.0, 1000.0), (1920.0, 1080.0)] {
        let mut a = display();
        let s = frame(&mut a, w, h);
        for (name, b) in places(&s) {
            assert!(b.0 >= 0.0 && b.0 + b.2 <= w && b.2 >= 1.0 && b.3 >= 1.0, "{w}: {name} {b:?}");
        }
        assert_eq!(places(&s).len(), 3, "{w} by {h}");
        for (text, x, _, size, _) in words(&s).into_iter().filter(|t| t.3 == Size::Small || t.3 == Size::Main) {
            let each = if size == Size::Small { M.sw } else { M.cw };
            assert!(x + text.chars().count() as f64 * each <= w + 1.0, "{w}: {text:?} from {x}");
        }
    }
}

#[test]
fn a_map_is_never_a_word_to_search_nor_a_row_of_the_grid() {
    let mut a = display();
    let map = |a: &App| {
        a.items()
            .iter()
            .any(|it| matches!(it, Item::Row(0, r) if a.providers[0].rows.rows[*r].map.is_some()))
    };
    assert!(map(&a));
    a.input = "screens".into();
    assert!(!map(&a));
    a.input.clear();
    a.pixels = false;
    assert!(!map(&a), "the terminal's list has the words of today: a row a screen, then the settings");
    let mut b = Buffer::empty(Rect::new(0, 0, 60, 40));
    a.size = (60, 40);
    spark_dialog::ui::draw(&a, &nord(), "", &mut b);
    let text: Vec<String> = (0..40).map(|y| (0..60).map(|x| b[(x, y)].symbol().to_string()).collect::<String>()).collect();
    for w in ["screens", "MB16FC", "1920x1200 \u{b7} turn", "T24i-30", "off", "level", "idle screen", "10 min"] {
        assert!(text.iter().any(|l| l.contains(w)), "{w}: {text:#?}");
    }
    let found = a.found("screens");
    assert!(!found
        .iter()
        .any(|(_, it)| matches!(it, Item::Row(0, r) if a.providers[0].rows.rows[*r].map.is_some())));
}

#[test]
fn settings_holds_display_under_appearance() {
    let mut a = display();
    for l in ["bar", "storage", "theme", "wallpaper"] {
        let mut p = Provider::new(l);
        p.ready = true;
        a.providers.push(p);
    }
    a.view = View::Dest(SETTINGS_DEST);
    let order: Vec<String> = a
        .items()
        .iter()
        .filter_map(|it| match it {
            Item::Heading(h) => Some(format!("[{h}]")),
            Item::Setting(i) => Some(spark_dialog::app::SETTINGS[*i].1.to_string()),
            _ => None,
        })
        .collect();
    assert_eq!(order[..7], ["[appearance]", "theme", "wallpaper", "display", "bar", "[devices]", "storage"]);
    // beside it in a wide window: the page as it is, its groups small
    a.sel = a
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Setting(i) if spark_dialog::app::SETTINGS[*i].0 == "display"))
        .unwrap();
    let s = frame(&mut a, 1920.0, 1080.0);
    assert_eq!(word(&s, "idle and lock").2, Size::Small);
    assert!(places(&s).is_empty(), "the whole of it opens display: nothing in it takes a click of its own");
    assert!(s.steps.iter().any(|st| matches!(st, Step::Cover { .. })), "the screens in it");
}

// ---------------------------------------------------------------- the keys

#[test]
fn left_and_right_choose_a_screen_and_enter_opens_it() {
    let mut a = display();
    let chosen = |a: &App| a.map_lit(a.providers[0].rows.rows[0].map.as_ref().unwrap()).unwrap();
    assert_eq!(chosen(&a), "HDMI-A-1");
    a.hint_key(HintKey::Left);
    assert_eq!(chosen(&a), "DP-3");
    a.hint_key(HintKey::Left);
    assert_eq!(
        (chosen(&a).as_str(), &a.view),
        ("DP-3", &View::Section(0)),
        "Left at the first stays: it never goes back"
    );
    for want in ["HDMI-A-1", "DP-1", "DP-1"] {
        a.hint_key(HintKey::Right);
        assert_eq!(chosen(&a), want);
    }
    a.hint_key(HintKey::Left);
    a.hint_key(HintKey::Enter);
    assert_eq!(a.view, View::Folder(0, uri("HDMI-A-1")));
    // the keys of the page, whatever row is lit
    let mut a = display();
    let keys = |a: &App| a.hint().iter().filter(|(_, k)| *k).map(|(t, _)| t.clone()).collect::<Vec<_>>();
    let all = keys(&a);
    assert_eq!(
        all,
        ["Esc", "Enter", "\u{2190} \u{2192}", "Ctrl+\u{2190} Ctrl+\u{2192} Ctrl+\u{2191} Ctrl+\u{2193}"]
    );
    a.sel = 5;
    assert_eq!(keys(&a), all);
    // on the bar they are one chip, the modifier said once
    let s = frame(&mut a, 600.0, 800.0);
    word(&s, "Ctrl+\u{2190} \u{2192} \u{2191} \u{2193}");
}

#[test]
fn control_and_an_arrow_move_the_lit_screen_beside_its_neighbor() {
    let (mut a, rx, log) = served(Box::new(
        |_, _| json!({"receipt": "done", "undo": {"name": "display_position", "arguments": {"screen": "HDMI-A-1", "x": 1200, "y": 420}}}),
    ));
    // the main one, right of the other: to its left, where the two still share the edge
    a.hint_key(HintKey::Place(Side::Left));
    assert_eq!(rect(&a, "HDMI-A-1"), (-1920, 420), "shown there at once");
    assert!(pump(&mut a, &rx, |_| !log.lock().unwrap().is_empty()));
    assert_eq!(
        calls(&log),
        [json!({"name": "display_position", "arguments": {"screen": "HDMI-A-1", "x": -1920, "y": 420}})],
        "whole numbers, as the tool takes them"
    );
    assert!(pump(&mut a, &rx, |a| a.undo.is_some()), "a move is taken back as any step is");
    assert!(a.reply.as_ref().is_some_and(|r| r.undo));
    // a screen's own row lit, the other rows none
    let mut a = display();
    a.sel = 1;
    a.hint_key(HintKey::Place(Side::Right));
    assert!(a.reply.as_ref().is_some_and(|r| r.mark == Mark::Refused && r.text.contains("stopped")));
    for (sel, why) in [(3, "that screen is off"), (4, "nothing to move here")] {
        let mut a = display();
        a.sel = sel;
        a.hint_key(HintKey::Place(Side::Right));
        assert_eq!(a.reply.as_ref().map(|r| (r.mark, r.text.as_str())), Some((Mark::Refused, why)));
    }
    // where it is already nothing is set and nothing said
    let mut a = display();
    a.hint_key(HintKey::Place(Side::Right));
    assert!(a.reply.is_none());
}

#[test]
fn one_screen_alone_is_drawn_and_moves_nowhere() {
    let mut a = display();
    let only = json!([screens()[0].clone()]);
    a.providers[0].rows = spark_dialog::model::rows(&rows_of(only).to_string()).unwrap();
    let s = frame(&mut a, 600.0, 800.0);
    assert_eq!(places(&s).len(), 1);
    a.hint_key(HintKey::Place(Side::Left));
    assert_eq!(a.reply.as_ref().map(|r| r.text.as_str()), Some("no other screen to move it beside"));
    let b = place(&s, "DP-3");
    a.map_press(0, "DP-3", (b.0 + 5.0, b.1 + 5.0), s.map.unwrap().scale);
    a.map_drag((b.0 + 200.0, b.1 + 5.0));
    assert!(!a.map_dragging());
    a.map_release(Instant::now());
    assert!(a.reply.as_ref().is_some_and(|r| r.mark == Mark::Refused), "nothing was set");
    assert!(!a.hint().iter().any(|(t, _)| t == "Move "), "no key for what cannot be done");
}

// ---------------------------------------------------------------- the pointer

#[test]
fn a_click_chooses_a_screen_and_a_second_one_opens_it() {
    let mut a = display();
    a.sel = 4;
    let s = frame(&mut a, 600.0, 800.0);
    let b = place(&s, "DP-3");
    let at = (b.0 + 20.0, b.1 + 20.0);
    let Some(Target::Screen(n, name)) = s.hit(at.0, at.1).cloned() else {
        panic!("{:?}", s.hit(at.0, at.1))
    };
    assert_eq!((n, name.as_str()), (0, "DP-3"), "the map is the first row that can be lit");
    let scale = s.map.unwrap().scale;
    let t0 = Instant::now();
    let click = |a: &mut App, t: Instant| {
        a.map_press(n, &name, at, scale);
        a.map_drag((at.0 + 3.0, at.1 + 2.0)); // a finger is never still
        a.map_release(t);
    };
    click(&mut a, t0);
    assert_eq!((a.sel, a.display.chosen.as_deref(), &a.view), (0, Some("DP-3"), &View::Section(0)));
    click(&mut a, t0 + Duration::from_secs(5));
    assert_eq!(a.view, View::Section(0), "too late to be a second click: a click of its own");
    click(&mut a, t0 + Duration::from_millis(5200));
    assert_eq!(a.view, View::Folder(0, uri("DP-3")));
    // the map's ground lights its row and opens nothing
    let mut a = display();
    a.sel = 4;
    a.clicked(0, Instant::now());
    assert_eq!((a.sel, &a.view), (0, &View::Section(0)));
}

#[test]
fn a_drag_shows_where_the_screen_lands_and_the_drop_sets_it() {
    let (mut a, rx, log) = served(Box::new(|_, _| json!({"receipt": "done"})));
    let s = frame(&mut a, 600.0, 800.0);
    let b = place(&s, "DP-3");
    let scale = s.map.unwrap().scale;
    let from = (b.0 + 30.0, b.1 + 30.0);
    a.map_press(0, "DP-3", from, scale);
    assert!(!a.map_drag((from.0 + 4.0, from.1)), "a few pixels are a click");
    // to the right of the other, about as high as it stands: its top lines up with the other's
    let to = (from.0 + 3140.0 * scale, from.1 + 400.0 * scale);
    assert!(a.map_drag(to));
    assert!(a.map_dragging());
    let held = frame(&mut a, 600.0, 800.0);
    assert_eq!(places(&held), places(&s), "the others stand still, and so does its own place");
    let land = (b.0 + 3120.0 * scale, b.1 + 420.0 * scale);
    assert!(
        fills(&held, ACCENT)
            .iter()
            .any(|f| (f.0 - land.0).abs() <= 2.0 && (f.1 - land.1).abs() <= 2.0 && f.3 == 2.0),
        "an outline where it lands: {:?}",
        fills(&held, ACCENT)
    );
    assert!(fills(&held, MUTED).contains(&(b.0, b.1, b.2, 1.0)), "its own place, hollow");
    a.map_release(Instant::now());
    assert_eq!(rect(&a, "DP-3"), (3120, 420), "shown there at once");
    assert!(pump(&mut a, &rx, |_| !log.lock().unwrap().is_empty()));
    assert_eq!(
        calls(&log),
        [json!({"name": "display_position", "arguments": {"screen": "DP-3", "x": 3120, "y": 420}})]
    );
}

#[test]
fn a_drag_cancelled_or_dropped_where_it_started_does_nothing() {
    let (mut a, rx, log) = served(Box::new(|_, _| json!({"receipt": "done"})));
    let s = frame(&mut a, 600.0, 800.0);
    let b = place(&s, "DP-3");
    let scale = s.map.unwrap().scale;
    let from = (b.0 + 30.0, b.1 + 30.0);
    let far = (from.0 + 300.0, from.1 + 40.0);
    // Esc while it is held: the page stands, and the release after it is nothing
    a.map_press(0, "DP-3", from, scale);
    a.map_drag(far);
    a.hint_key(HintKey::Escape);
    assert_eq!((&a.view, a.map_held()), (&View::Section(0), false));
    a.map_drag(far);
    a.map_release(Instant::now());
    // dropped a few pixels from where it stood, and back on it
    for to in [(from.0 + 9.0, from.1 + 2.0), (from.0 + 1.0, from.1)] {
        a.map_press(0, "DP-3", from, scale);
        a.map_drag(far);
        a.map_drag(to);
        a.map_release(Instant::now());
        assert_eq!(rect(&a, "DP-3"), (0, 0));
    }
    // one that is off is chosen by a press and never dragged
    let off = place(&s, "DP-1");
    a.map_press(0, "DP-1", (off.0 + 5.0, off.1 + 5.0), scale);
    a.map_drag((off.0 - 200.0, off.1));
    assert!(!a.map_dragging());
    a.map_release(Instant::now());
    // the rows came again without the screen while it was held
    a.map_press(0, "DP-3", from, scale);
    a.map_drag(far);
    let fewer = json!([screens()[1].clone(), screens()[2].clone()]);
    a.providers[0].rows = spark_dialog::model::rows(&rows_of(fewer).to_string()).unwrap();
    a.map_release(Instant::now());
    assert!(!pump_for(&mut a, &rx, Duration::from_millis(300), |_| !log.lock().unwrap().is_empty()));
    assert_eq!(calls(&log), Vec::<Value>::new());
}

#[test]
fn a_move_the_provider_refuses_goes_back_and_one_that_asks_is_asked() {
    let (mut a, rx, _) = served(Box::new(|_, _| json!({"refused": "no connected screen HDMI-A-1"})));
    a.hint_key(HintKey::Place(Side::Left));
    assert_eq!(rect(&a, "HDMI-A-1"), (-1920, 420));
    assert!(pump(&mut a, &rx, |a| a.reply.as_ref().is_some_and(|r| r.mark == Mark::Refused)));
    assert!(pump(&mut a, &rx, |a| rect(a, "HDMI-A-1") == (1200, 420)), "the provider's rows again");
    // a map whose step is a destructive one: the question, never set in place
    let mut a = display();
    let mut rows = rows_of(screens());
    rows["rows"][0]["move"] = json!({"name": "display_wipe", "arguments": {}});
    a.providers[0].rows = spark_dialog::model::rows(&rows.to_string()).unwrap();
    a.hint_key(HintKey::Place(Side::Left));
    assert!(matches!(a.mode, Mode::Confirm(_)));
    assert_eq!(rect(&a, "HDMI-A-1"), (1200, 420));
}

// ---------------------------------------------------------------- a screen's page

#[test]
fn a_screens_page_is_its_settings_on_one_column() {
    let mut a = display();
    a.view = View::Folder(0, uri("HDMI-A-1"));
    a.came_from = vec![View::Home, View::Section(0)];
    let page = page_of(&uri("HDMI-A-1")).to_string();
    a.folder = Some((0, uri("HDMI-A-1"), spark_dialog::model::rows(&page).unwrap()));
    (a.in_list, a.sel) = (true, 0);
    assert_eq!(kind(&a), Kind::Page);
    let s = frame(&mut a, 600.0, 800.0);
    let column = word(&s, "on").0;
    for w in ["this one", "1920x1080 60 Hz", "75%", "upright"] {
        assert_eq!(word(&s, w).0, column, "{w}");
    }
    let side = words(&s).into_iter().filter(|w| w.0 == "left").map(|w| w.1).fold(f64::MAX, f64::min);
    assert_eq!(side, column, "beside its left");
    // each setting on its own line in the regular window, the longest list too
    for (name, last) in [("scale", "200%"), ("orientation", "upside down"), ("beside MB16FC", "below")] {
        assert_eq!(word(&s, name).1, word(&s, last).1, "{name}");
    }
    // the resolution in use is the one in use, and its whole row opens the list behind it
    let mode = word(&s, "1920x1080 60 Hz");
    assert_eq!((mode.2, mode.3), (Size::Main, ACCENT));
    let n = a
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Folder(i) if a.folder.as_ref().unwrap().2.rows[*i].id == "s:mode"))
        .unwrap();
    assert_eq!(s.hit(mode.0 + 5.0, mode.1 + 5.0), Some(&Target::Pick(n)));
    a.sel = n;
    a.hint_key(HintKey::Enter);
    let modes = format!("{}/modes", uri("HDMI-A-1"));
    assert_eq!(a.view, View::Folder(0, modes.clone()));
    a.folder = Some((0, modes.clone(), spark_dialog::model::rows(&page_of(&modes).to_string()).unwrap()));
    let s = frame(&mut a, 600.0, 800.0);
    let names: Vec<String> = words(&s)
        .into_iter()
        .filter(|w| w.3 == Size::Small && w.2 == word(&s, "home").1 && w.0 != " / ")
        .map(|w| w.0)
        .collect();
    assert_eq!(names, ["home", "display", "T24i-30", "resolution"]);
    let at = word(&s, "display");
    assert_eq!(s.hit(at.0 + 3.0, at.1 + 5.0), Some(&Target::BackBy(2)));
}

// ---------------------------------------------------------------- the trial

fn trial(said: &str) -> Value {
    json!({"receipt": format!("HDMI-A-1 {said}"), "trial": {"said": said, "seconds": 15,
        "keep": {"name": "display_keep", "arguments": {"screen": "HDMI-A-1"}},
        "back": {"name": "display_back", "arguments": {"screen": "HDMI-A-1"}}}})
}

/// The resolution picked from its list, its trial on.
fn tried(answer: Answer) -> (App, Receiver<Incoming>, Arc<Mutex<Vec<Value>>>) {
    let (mut a, rx, log) = served(answer);
    let modes = format!("{}/modes", uri("HDMI-A-1"));
    a.view = View::Folder(0, modes.clone());
    a.came_from = vec![View::Home, View::Section(0), View::Folder(0, uri("HDMI-A-1"))];
    a.folder = Some((0, modes.clone(), spark_dialog::model::rows(&page_of(&modes).to_string()).unwrap()));
    let n = a
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Folder(i) if a.folder.as_ref().unwrap().2.rows[*i].id == "m:2"))
        .unwrap();
    (a.in_list, a.sel) = (true, n);
    a.hint_key(HintKey::Enter);
    assert_eq!(a.view, View::Folder(0, uri("HDMI-A-1")), "a pick goes back to the screen's page");
    (a, rx, log)
}

fn keep_or_back() -> Answer {
    Box::new(|name, _| match name {
        "display_mode" => trial("1280x720"),
        "display_keep" => {
            json!({"receipt": "HDMI-A-1 1280x720 kept", "undo": {"name": "display_mode", "arguments": {"screen": "HDMI-A-1", "mode": "1920x1080@60Hz"}}})
        }
        _ => json!({"receipt": "HDMI-A-1 is back as it was"}),
    })
}

#[test]
fn a_change_on_trial_is_a_card_that_counts_down_and_enter_keeps_it() {
    let (mut a, rx, log) = tried(keep_or_back());
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    let (said, left) = a.trial_card().unwrap();
    assert_eq!((said, (14..=15).contains(&left)), ("1280x720", true));
    assert!(a.reply.is_none() && a.undo.is_none(), "no receipt, and nothing to undo yet");
    // the card in the message's place: what changed, the seconds, two keys, each a place a click acts
    let s = frame(&mut a, 600.0, 800.0);
    let said = word(&s, "1280x720");
    assert_eq!(said.2, Size::Main);
    assert!(words(&s).iter().any(|w| w.0.starts_with("goes back in 1")), "{:?}", words(&s));
    let target = |s: &Scene, text: &str| {
        let at = words(s).into_iter().find(|w| w.0 == text && w.2 > 700.0).unwrap();
        s.hit(at.1 + 2.0, at.2 + 5.0).cloned()
    };
    assert_eq!(target(&s, "keep"), Some(Target::Trial(true)));
    let back = words(&s).into_iter().filter(|w| w.0 == "back" && w.2 > 700.0).collect::<Vec<_>>();
    assert!(back.iter().any(|w| s.hit(w.1 + 2.0, w.2 + 5.0) == Some(&Target::Trial(false))), "{back:?}");
    // the key bar's own Esc keeps its place and is dimmed: one key says one thing
    assert!(
        back.iter().any(|w| w.4 == LIT && s.hit(w.1 + 2.0, w.2 + 5.0).is_none()),
        "its own Esc is the card's for now: {back:?}"
    );
    // a tick: the seconds run down, and nothing moves as they do
    let t = Instant::now();
    a.tick(t + Duration::from_secs(7));
    assert!((7..=8).contains(&a.trial_card().unwrap().1));
    let later = frame(&mut a, 600.0, 800.0);
    assert!(
        words(&later).iter().any(|w| w.0.starts_with("goes back in  ")),
        "a figure keeps the room of two"
    );
    assert_eq!(target(&later, "keep"), Some(Target::Trial(true)));
    // every other key works as ever, and the card stays
    a.hint_key(HintKey::Down);
    a.hint_key(HintKey::Up);
    assert!(a.trial_card().is_some());
    // Enter is the card's
    a.hint_key(HintKey::Enter);
    assert!(a.trial_card().is_none());
    assert!(pump(&mut a, &rx, |a| a.reply.as_ref().is_some_and(|r| r.mark == Mark::Done)));
    let r = a.reply.clone().unwrap();
    assert_eq!(
        (r.text.as_str(), r.undo),
        ("HDMI-A-1 1280x720 kept", true),
        "its receipt, with the undo the change has now"
    );
    assert_eq!(calls(&log)[1], json!({"name": "display_keep", "arguments": {"screen": "HDMI-A-1"}}));
    // and the undo of it is a change on trial, as any is
    a.undo_now();
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
}

#[test]
fn esc_puts_a_change_on_trial_back_and_stays_on_the_page() {
    let (mut a, rx, log) = tried(keep_or_back());
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    a.hint_key(HintKey::Escape);
    assert_eq!((a.trial_card(), &a.view), (None, &View::Folder(0, uri("HDMI-A-1"))));
    assert!(pump(&mut a, &rx, |a| a.reply.as_ref().is_some_and(|r| r.mark == Mark::Done)));
    assert_eq!(calls(&log)[1]["name"], "display_back");
    a.hint_key(HintKey::Escape);
    assert_eq!(a.view, View::Section(0), "Esc is the page's again");
    // a click on a word is its key
    let (mut a, rx, log) = tried(keep_or_back());
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    a.trial_end(true);
    assert!(pump(&mut a, &rx, |_| log.lock().unwrap().len() == 2));
    assert_eq!(calls(&log)[1]["name"], "display_keep");
}

#[test]
fn a_trial_left_alone_goes_back_by_itself_and_its_rows_are_read_again() {
    let (mut a, rx, log) = tried(keep_or_back());
    let quiet = |a: &App| !a.providers[0].dirty && a.servers[0].pending.is_empty();
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some() && quiet(a)));
    let t = Instant::now();
    a.tick(t + Duration::from_secs(16));
    assert_eq!(a.trial_card(), None);
    let r = a.reply.clone().unwrap();
    assert_eq!((r.mark, r.text.as_str()), (Mark::Note, "1280x720 was not kept: the screen is as it was before"));
    assert!(a.providers[0].reading || a.providers[0].dirty, "its rows again");
    assert_eq!(calls(&log).len(), 1, "the desktop put it back: the dialog asks for nothing");
    // and once more a moment after, whichever clock ran first
    assert!(pump(&mut a, &rx, quiet));
    a.tick(t + Duration::from_secs(18));
    assert!(a.providers[0].reading || a.providers[0].dirty);
    // Enter and Esc are the page's again
    a.hint_key(HintKey::Escape);
    assert_eq!(a.view, View::Section(0));
}

#[test]
fn a_value_set_in_place_is_tried_too_and_a_second_change_keeps_the_first() {
    let (mut a, rx, log) = served(Box::new(|name, _| match name {
        "display_scale" => trial("scale 125%"),
        "display_transform" => trial("turned right"),
        _ => json!({"receipt": "done"}),
    }));
    a.view = View::Folder(0, uri("HDMI-A-1"));
    a.came_from = vec![View::Home, View::Section(0)];
    let open = |a: &mut App, id: &str| {
        a.folder = Some((0, uri("HDMI-A-1"), spark_dialog::model::rows(&page_of(&uri("HDMI-A-1")).to_string()).unwrap()));
        let n = a
            .picks()
            .iter()
            .position(|it| matches!(it, Item::Folder(i) if a.folder.as_ref().unwrap().2.rows[*i].id == id))
            .unwrap();
        (a.in_list, a.sel) = (true, n);
    };
    open(&mut a, "s:scale");
    a.hint_key(HintKey::Right);
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some_and(|c| c.0 == "scale 125%")));
    open(&mut a, "s:turn");
    a.hint_key(HintKey::Right);
    assert!(
        pump(&mut a, &rx, |a| a.trial_card().is_some_and(|c| c.0 == "turned right")),
        "its card in place of the first's"
    );
    // a setting that is no change of a screen leaves the card
    let n = calls(&log).len();
    a.view = View::Section(0);
    (a.in_list, a.sel) = (true, 4);
    a.hint_key(HintKey::Right);
    assert!(pump(&mut a, &rx, |_| log.lock().unwrap().len() > n));
    assert!(pump(&mut a, &rx, |a| !a.under_way()));
    assert!(a.trial_card().is_some());
    // a screen moved keeps what is on trial: its card goes with the result
    a.sel = 0;
    a.hint_key(HintKey::Place(Side::Left));
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_none()));
    assert!(a.reply.as_ref().is_none_or(|r| r.mark != Mark::Refused));
    a.came_from = vec![View::Home];
    a.hint_key(HintKey::Escape);
    assert_eq!(a.view, View::Home, "Esc is the page's");
}

#[test]
fn a_late_keep_is_said_plainly_and_is_no_alarm() {
    let (mut a, rx, _) = tried(Box::new(|name, _| match name {
        "display_mode" => trial("1280x720"),
        _ => json!({"refused": "nothing is being tried on HDMI-A-1: it was kept, or it went back"}),
    }));
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    a.hint_key(HintKey::Enter);
    assert!(pump(&mut a, &rx, |a| a.reply.is_some()));
    let r = a.reply.clone().unwrap();
    assert_eq!(
        (r.mark, r.text.as_str()),
        (Mark::Note, "nothing is being tried on HDMI-A-1: it was kept, or it went back")
    );
    assert_eq!(a.trial_card(), None);
}

#[test]
fn a_malformed_trial_is_an_ordinary_result_and_a_lost_provider_ends_one() {
    let (mut a, rx, log) = tried(Box::new(
        |_, _| json!({"receipt": "done", "trial": {"said": "1280x720", "seconds": 0}, "undo": {"name": "display_mode", "arguments": {"screen": "HDMI-A-1", "mode": "1920x1080@60Hz"}}}),
    ));
    assert!(pump(&mut a, &rx, |a| a.undo.is_some()));
    assert_eq!((a.trial_card(), calls(&log).len()), (None, 1));
    let (mut a, rx, _) = tried(keep_or_back());
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    a.incoming(Incoming::Gone(0, "it ended".into()));
    assert_eq!(a.trial_card(), None);
    // a question on screen has the keys: the card waits under it, and its seconds run
    let (mut a, rx, _) = tried(keep_or_back());
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    a.mode = Mode::Listening;
    a.hint_key(HintKey::Enter);
    a.trial_end(true);
    assert!(a.trial_card().is_some());
}

#[test]
fn the_grid_says_the_trial_on_its_status_row() {
    let (mut a, rx, _) = tried(keep_or_back());
    assert!(pump(&mut a, &rx, |a| a.trial_card().is_some()));
    a.pixels = false;
    for (w, h) in [(60u16, 40u16), (36, 20)] {
        a.size = (w, h);
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        let drawn = spark_dialog::ui::draw(&a, &nord(), "", &mut b);
        let y = spark_dialog::ui::status_y(h);
        let line: String = (0..w).map(|x| b[(x, y)].symbol().to_string()).collect();
        assert!(line.contains("1280x720") && line.contains("keep") && line.contains("back"), "{line:?}");
        assert_eq!(drawn.trial.len(), 2);
        for (x0, x1, row, keep) in &drawn.trial {
            let word: String = (*x0..*x1).map(|x| b[(x, *row)].symbol().to_string()).collect();
            assert_eq!((word.trim(), *row), (if *keep { "keep" } else { "back" }, y));
        }
        assert!(
            !drawn.keys.iter().any(|(_, _, _, k)| matches!(k, HintKey::Escape | HintKey::Enter)),
            "the card's, not the bar's"
        );
    }
}
