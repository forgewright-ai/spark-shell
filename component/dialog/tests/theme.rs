// The theme's pages after the review of v0.172, against a stub theme provider: a value asked for in the prompt,
// the color picker, what Enter does on a work's page, the row lit and the row run, a pick let go by a jump, the
// steps of a row as a page, the words of the keys' line, and a look changed outside home.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{App, HintKey, Item, Mode, Picking, View};
use spark_dialog::mcp::Incoming;
use spark_dialog::picker::{hex_of, Strip};
use spark_dialog::scene::{self, Kind, Target};
use std::sync::{Arc, Mutex};

const ROOT: &str = "spark-shell://theme/rows";
const COLORS: &str = "spark-shell://theme/rows/colors";
const YOURS: &str = "spark-shell://theme/rows/yours";
const WORK: &str = "spark-shell://theme/rows/gallery/mars-conquest";
const MINE: &str = "spark-shell://theme/rows/gallery/my-night";
const WALLS: &str = "spark-shell://theme/rows/wallpapers";

fn tools() -> Value {
    let ann = json!({"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false});
    let name = json!({"type": "string", "minLength": 1, "maxLength": 256});
    let new = json!({"type": "string", "minLength": 1, "maxLength": 40, "description": "the new name"});
    let of = |props: Value, required: &[&str]| json!({"type": "object", "properties": props, "required": required, "additionalProperties": false});
    json!([
        {"name": "theme_color", "title": "theme color WORD COLOR", "annotations": ann, "inputSchema": of(json!({
            "word": {"type": "string", "enum": ["background", "text", "accent", "red"]},
            "color": {"type": "string", "format": "color", "minLength": 1, "maxLength": 40, "description": "#rrggbb or a color's name"}}), &["word", "color"])},
        {"name": "theme_save", "title": "theme save NAME", "annotations": ann,
         "inputSchema": of(json!({"name": {"type": "string", "minLength": 1, "maxLength": 256, "description": "a name for this theme"}}), &["name"])},
        {"name": "theme_rename", "title": "theme rename NAME NEW", "annotations": ann, "inputSchema": of(json!({"name": name, "to": new}), &["name", "to"])},
        {"name": "theme_duplicate", "title": "theme duplicate NAME NEW", "annotations": ann, "inputSchema": of(json!({"name": name, "to": new}), &["name", "to"])},
        {"name": "theme_export", "title": "theme export NAME", "annotations": ann, "inputSchema": of(json!({"name": name}), &["name"])},
        {"name": "theme_palette", "title": "theme NAME", "annotations": ann, "inputSchema": of(json!({"name": name}), &["name"])},
        {"name": "theme_wallpaper", "title": "theme wallpaper NAME", "annotations": ann, "inputSchema": of(json!({"name": name}), &["name"])}
    ])
}

fn page(uri: &str) -> Value {
    let color = |key: &str, text: &str, word: &str, hex: &str, against: Option<&str>| {
        let mut row = json!({"id": format!("theme:color:{key}"), "group": "theme colors", "text": text, "swatch": hex, "columns": [hex],
            "tool": {"name": "theme_color", "arguments": {"word": word}, "ask": ["color"]}});
        if let Some(a) = against {
            row["against"] = json!(a);
        }
        row
    };
    match uri {
        COLORS => json!({"title": "Colors", "state": "Catppuccin Mocha", "short": [], "rows": [
            {"id": "theme:colors:from", "text": "another theme's colors", "sign": "opens", "children": "spark-shell://theme/rows/colors/from"},
            {"id": "theme:colors:pair", "text": "other variant", "sign": "opens", "columns": ["Catppuccin Latte"], "children": "spark-shell://theme/rows/colors/pair"},
            color("BG", "Background", "background", "#1e1e2e", Some("#cdd6f4")),
            color("FG", "Text", "text", "#cdd6f4", Some("#1e1e2e")),
            color("ACCENT", "Accent", "accent", "#cba6f7", Some("#1e1e2e")),
            color("ANSI_1", "1  red", "red", "#f38ba8", Some("#1e1e2e")),
            color("ANSI_2", "2  green", "green", "#a6e3a1", Some("#1e1e2e")),
            color("ANSI_4", "4  blue", "blue", "#89b4fa", Some("#1e1e2e"))]}),
        YOURS => json!({"title": "Your themes", "state": "1 theme", "short": [], "rows": [
            {"id": "theme:new:look", "group": "new theme", "text": "from the look in use", "tool": {"name": "theme_save", "arguments": {}, "ask": ["name"]}},
            {"id": "theme:entry:my-night", "group": "yours", "text": "my-night", "sign": "check", "children": MINE, "chip": ["#1e1e2e", "#cdd6f4", "#cba6f7"],
             "more": [{"name": "theme_rename", "arguments": {"name": "my-night"}, "ask": ["to"], "said": "rename"},
                      {"name": "theme_duplicate", "arguments": {"name": "my-night"}, "ask": ["to"], "said": "duplicate"}]}]}),
        WORK | MINE => {
            let name = uri.rsplit('/').next().unwrap();
            let manage = if uri == MINE {
                json!([{"id": "theme:manage:rename", "group": "manage", "text": "Rename", "tool": {"name": "theme_rename", "arguments": {"name": name}, "ask": ["to"]}}])
            } else {
                json!([{"id": "theme:manage:duplicate", "group": "manage", "text": "Duplicate as yours", "tool": {"name": "theme_duplicate", "arguments": {"name": name}, "ask": ["to"]}}])
            };
            let mut rows = vec![
                json!({"id": format!("theme:apply:{name}"), "text": "apply theme", "sign": "blank", "chip": ["#2a1f1b", "#e8d9c5", "#e6a878"], "quiet": true,
                       "line": "cinematic illustration \u{b7} dark", "page": format!("spark-shell://theme/preview/{name}"), "tool": {"name": "theme_palette", "arguments": {"name": name}}}),
                json!({"id": "theme:terminal-palette", "text": "Terminal palette", "sign": "opens", "columns": ["handpicked"], "children": format!("spark-shell://theme/rows/palette/{name}")}),
                json!({"id": "theme:detail:wall", "group": "it brings", "text": "wallpaper", "columns": ["Landscape 1, moving"]}),
                json!({"id": "theme:detail:type", "group": "it brings", "text": "type", "columns": ["Krypton"]}),
            ];
            rows.extend(manage.as_array().unwrap().iter().cloned());
            rows.push(json!({"id": "theme:manage:export", "group": "manage", "text": "Export", "columns": ["a theme file in Downloads"], "tool": {"name": "theme_export", "arguments": {"name": name}}}));
            json!({"title": "Mars Conquest", "short": [], "rows": rows})
        }
        WALLS => json!({"title": "Wallpaper", "state": "", "short": [], "rows": [
            {"id": "theme:wallpaper hills", "text": "hills", "sign": "check", "group": "drawings", "columns": ["for catppuccin-mocha"], "quiet": true, "tool": {"name": "theme_wallpaper", "arguments": {"name": "hills"}}},
            {"id": "theme:wallpaper fjord", "text": "fjord", "sign": "blank", "group": "drawings", "columns": ["for nord"], "quiet": true, "tool": {"name": "theme_wallpaper", "arguments": {"name": "fjord"}}}]}),
        _ => json!({"title": "theme", "state": "catppuccin-mocha", "short": [], "rows": [
            {"id": "theme:gallery:open", "text": "The Gallery", "sign": "opens", "children": "spark-shell://theme/rows/gallery"},
            {"id": "theme:mars-conquest", "text": "Mars Conquest", "sign": "blank", "group": "themes", "tool": {"name": "theme_palette", "arguments": {"name": "mars-conquest"}}},
            {"id": "theme:show:Text size", "text": "Text size", "sign": "blank", "group": "text and bar",
             "step": {"values": [{"shown": "11", "sent": "11"}, {"shown": "12", "sent": "12"}], "at": 1, "set": {"name": "theme_palette", "arguments": {}}, "key": "name", "words": ["smaller", "bigger"]}}]}),
    }
}

type Calls = Arc<Mutex<Vec<Value>>>;

/// A theme provider that answers each page by its uri and logs every step.
fn theme() -> (App, std::sync::mpsc::Receiver<Incoming>, Calls) {
    let (mut app, rx, tx) = app_with(&["theme"]);
    let calls: Calls = Arc::new(Mutex::new(vec![]));
    let c2 = calls.clone();
    let script: Script = Box::new(move |v, send| {
        match v.get("method").and_then(Value::as_str) {
            Some("resources/read") => {
                let uri = v.pointer("/params/uri").and_then(Value::as_str).unwrap_or(ROOT).to_string();
                return send(result(
                    &v["id"],
                    json!({"contents": [{"uri": uri, "mimeType": "application/json", "text": page(&uri).to_string()}]}),
                ));
            }
            Some("tools/call") => {
                c2.lock().unwrap().push(v["params"].clone());
                return send(result(
                    &v["id"],
                    json!({"content": [{"type": "text", "text": "done"}], "structuredContent": {"receipt": "done"}, "isError": false}),
                ));
            }
            _ => {}
        }
        if let Some(r) = ordinary("theme", v, &tools(), &page(ROOT)) {
            send(r);
        }
    });
    app.servers.push(stub(0, "theme", script, tx));
    app.start();
    assert!(pump(&mut app, &rx, |a| a.providers[0].ready && !a.providers[0].tools.is_empty()));
    app.pixels = true;
    (app, rx, calls)
}

/// A page of the theme's opened, nothing lit.
fn open(app: &mut App, uri: &str) {
    app.came_from.push(app.view.clone());
    app.view = View::Folder(0, uri.into());
    app.folder = Some((0, uri.into(), spark_dialog::model::rows(&page(uri).to_string()).unwrap()));
    (app.in_list, app.sel, app.scroll) = (false, 0, 0);
}

/// The row with this id lit by the keys.
fn light(app: &mut App, id: &str) {
    let n = app
        .picks()
        .iter()
        .position(|it| matches!(it, Item::Folder(i) if app.folder.as_ref().unwrap().2.rows[*i].id == id))
        .unwrap_or_else(|| panic!("no row {id} to light"));
    (app.in_list, app.sel) = (true, n);
}

fn keys(app: &App) -> String {
    app.hint().iter().map(|(t, _)| t.as_str()).collect::<String>()
}

fn type_in(app: &mut App, text: &str) {
    for c in text.chars() {
        app.typed(c);
    }
}

/// A value a step asks for is typed in a prompt that says what it takes and holds the keys; the page stands as it
/// stood, the row that asked lit. The prompt stood blank with no cursor, its words in the keys' line, and the
/// first letter emptied the page as a search does.
#[test]
fn a_value_asked_for_keeps_the_page_and_the_prompt_holds_the_keys() {
    let (mut app, rx, calls) = theme();
    open(&mut app, YOURS);
    light(&mut app, "theme:new:look");
    let rows = app.picks().len();
    app.enter();
    assert!(matches!(app.mode, Mode::Ask { .. }), "{:?}", app.mode);
    assert_eq!(app.placeholder(), "a name for this theme");
    let said = frame(&mut app, 600.0, 800.0);
    // the prompt holds the keys: its line is the accent's, two pixels, as while a search is typed
    assert!(
        fills(&said, ACCENT).iter().any(|f| f.3 == 2.0 && f.2 > 400.0),
        "the prompt's line in the accent"
    );
    assert!(
        keys(&app).contains("Cancel") && keys(&app).contains("Save") && keys(&app).contains("Enter"),
        "{}",
        keys(&app)
    );
    assert!(app.in_list && app.sel == 0, "the row that asked stays lit");
    app.down();
    app.up();
    assert!(app.in_list && app.sel == 0, "the arrows are the prompt's: the list stands still");
    type_in(&mut app, "zz top");
    assert_eq!(app.picks().len(), rows, "the words typed are a name, not a search: every row stands");
    assert!(words(&frame(&mut app, 600.0, 800.0)).iter().any(|w| w.0 == "my-night"));
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 1));
    assert_eq!(calls.lock().unwrap()[0]["arguments"], json!({"name": "zz top"}));
    // Esc lets the question go: the page as it was, the row lit, the prompt its own again
    light(&mut app, "theme:new:look");
    app.enter();
    type_in(&mut app, "x");
    app.escape();
    assert_eq!(app.mode, Mode::Normal);
    assert!(app.input.is_empty() && app.in_list);
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert_eq!(calls.lock().unwrap().len(), 1, "nothing ran");
}

/// A rename starts from the theme's name wherever it is asked: among a row's steps, and on the theme's own page,
/// whose row says Rename (it offered the word Rename as the name).
#[test]
fn a_rename_offers_the_themes_name_wherever_it_is_asked() {
    let (mut app, _rx, _calls) = theme();
    open(&mut app, MINE);
    light(&mut app, "theme:manage:rename");
    app.enter();
    assert!(matches!(app.mode, Mode::Ask { .. }));
    assert_eq!(app.input, "my-night");
    assert!(app.name_is_lit(), "lit whole: the first letter typed replaces it");
    app.escape();
    // from the list, by the row's steps
    open(&mut app, YOURS);
    light(&mut app, "theme:entry:my-night");
    app.hint_key(HintKey::Actions);
    assert!(matches!(app.view, View::Steps(0)), "{:?}", app.view);
    assert_eq!(scene::kind(&app), Kind::Page, "a row's steps are a page, as the theme's lists are");
    let steps = frame(&mut app, 600.0, 800.0);
    assert!(words(&steps).iter().any(|w| w.0 == "rename") && words(&steps).iter().any(|w| w.0 == "duplicate"));
    assert_eq!(
        fills(&steps, LIT).iter().filter(|f| f.3 >= 40.0).count(),
        1,
        "the step lit wears the bar a row wears"
    );
    app.enter();
    assert!(matches!(app.mode, Mode::Ask { .. }), "{:?}", app.mode);
    assert_eq!(app.input, "my-night");
    assert_eq!(app.placeholder(), "the new name");
}

/// A color is picked on strips of swatches, with its value in the prompt to type one whole. It was a blank prompt.
#[test]
fn a_color_is_picked_on_strips_and_typed_whole() {
    let (mut app, rx, calls) = theme();
    open(&mut app, COLORS);
    light(&mut app, "theme:color:FG");
    assert!(keys(&app).contains("Change"), "{}", keys(&app));
    app.enter();
    let p = app.picker.clone().expect("a step that asks for a color opens the picker");
    assert_eq!((p.was, p.against), ([0xcd, 0xd6, 0xf4], Some([0x1e, 0x1e, 0x2e])));
    assert!(
        p.theirs.iter().any(|(n, _)| n == "Background") && !p.theirs.iter().any(|(n, _)| n == "Text"),
        "the list's other colors: {:?}",
        p.theirs
    );
    assert_eq!(app.input, "#cdd6f4");
    assert!(app.name_is_lit());
    assert_eq!(scene::kind(&app), Kind::Page);
    let page = frame(&mut app, 600.0, 800.0);
    for w in ["hue", "shade", "strength", "this theme", "Text"] {
        assert!(words(&page).iter().any(|x| x.0 == w), "{w}");
    }
    assert!(!words(&page).iter().any(|x| x.0 == "Background"), "the strips stand in place of the page");
    assert!(words(&page).iter().any(|x| x.0.starts_with("contrast ")), "how it reads on the ground");
    assert!(keys(&app).contains("Use") && keys(&app).contains("Cancel"), "{}", keys(&app));
    // the arrows: right along the strip lit, down to the next strip; the prompt says the color they make
    app.right();
    let hue = app.picker.as_ref().unwrap().value();
    assert_ne!(hue, [0xcd, 0xd6, 0xf4]);
    assert_eq!(app.input, hex_of(hue));
    app.down();
    assert_eq!(app.picker.as_ref().unwrap().strip, Strip::Shade);
    assert_eq!(app.input, hex_of(hue), "another strip, the same color");
    // a swatch clicked
    let page = frame(&mut app, 600.0, 800.0);
    let first = page
        .hits
        .iter()
        .find(|h| h.target == Target::Swatch(Strip::Theirs, 0))
        .expect("each swatch takes a click");
    assert_eq!(page.hit(first.x + 2.0, first.y + 2.0), Some(&Target::Swatch(Strip::Theirs, 0)));
    app.picker_click(Strip::Theirs, 0);
    assert_eq!(app.picker.as_ref().unwrap().value(), [0x1e, 0x1e, 0x2e], "the background's color, as it is");
    // a value typed whole: the strips follow it, and Enter uses it
    type_in(&mut app, "#ff8800");
    assert_eq!(app.picker.as_ref().unwrap().value(), [0xff, 0x88, 0x00]);
    // in cells too: the swatches drawn, each to click
    let mut b = spark_dialog::grid::Buffer::empty(spark_dialog::grid::Rect::new(0, 0, 60, 40));
    app.size = (60, 40);
    let drawn = spark_dialog::ui::draw(&app, &palette("nord"), "", &mut b);
    assert!(
        drawn.swatches.iter().any(|s| s.3 == Strip::Hue) && drawn.swatches.iter().any(|s| s.3 == Strip::Theirs),
        "{:?}",
        drawn.swatches.len()
    );
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 1));
    assert_eq!(calls.lock().unwrap()[0]["arguments"], json!({"word": "text", "color": "#ff8800"}));
    assert!(app.picker.is_none() && app.mode == Mode::Normal);
    // a color's name goes as typed: the provider knows the names
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    open(&mut app, COLORS);
    light(&mut app, "theme:color:ACCENT");
    app.enter();
    type_in(&mut app, "teal");
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 2));
    assert_eq!(calls.lock().unwrap()[1]["arguments"], json!({"word": "accent", "color": "teal"}));
    // and Esc picks nothing
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    open(&mut app, COLORS);
    light(&mut app, "theme:color:BG");
    app.enter();
    app.right();
    app.escape();
    assert!(app.picker.is_none() && app.input.is_empty());
    assert_eq!(calls.lock().unwrap().len(), 2);
}

/// On a work's page the keys' line says Enter applies, and with no row lit it does. It answered that nothing was lit.
#[test]
fn enter_does_what_the_keys_line_says_with_no_row_lit() {
    let (mut app, rx, calls) = theme();
    open(&mut app, WORK);
    assert!(!app.in_list);
    assert!(keys(&app).contains("Apply"), "{}", keys(&app));
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 1), "{:?}", app.reply);
    assert_eq!(calls.lock().unwrap()[0]["name"], "theme_palette");
    assert_eq!(calls.lock().unwrap()[0]["arguments"], json!({"name": "mars-conquest"}));
    // a list with no picture of a row says no word for Enter until a row is lit, and Enter then says why it did nothing
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    open(&mut app, WALLS);
    assert!(!keys(&app).contains("Enter"), "{}", keys(&app));
    app.enter();
    assert_eq!(
        app.reply.as_ref().map(|r| r.text.as_str()),
        Some("nothing is lit: an arrow or a click lights a row")
    );
    light(&mut app, "theme:wallpaper fjord");
    assert!(keys(&app).contains("Use") && keys(&app).contains("Enter"), "a wallpaper lit: {}", keys(&app));
    open(&mut app, COLORS);
    assert!(!keys(&app).contains("Enter"), "{}", keys(&app));
    light(&mut app, "theme:colors:from");
    assert!(keys(&app).contains("Open"), "{}", keys(&app));
}

/// A work's page draws every row its provider gives, so the row lit is the row Enter runs and a click lands on the
/// row under it. Rows with no second words were left out of the drawing and kept by the keys: a click on Export
/// duplicated the theme.
#[test]
fn the_row_lit_on_a_works_page_is_the_row_enter_runs() {
    let (mut app, rx, calls) = theme();
    open(&mut app, WORK);
    let page = frame(&mut app, 600.0, 1400.0);
    for w in [
        "apply theme",
        "Terminal palette",
        "wallpaper",
        "Duplicate as yours",
        "Export",
        "it brings",
        "manage",
    ] {
        assert!(words(&page).iter().any(|x| x.0 == w), "{w} is drawn");
    }
    for id in ["theme:manage:duplicate", "theme:manage:export"] {
        let text = app.folder.as_ref().unwrap().2.rows.iter().find(|r| r.id == id).unwrap().text.clone();
        let at = word(&page, &text);
        let n = match page.hit(at.0 + 2.0, at.1 + 4.0) {
            Some(Target::Pick(n)) => *n,
            other => panic!("{text}: a click there is {:?}", other),
        };
        let row = app.picks().get(n).and_then(|it| match it {
            Item::Folder(i) => Some(app.folder.as_ref().unwrap().2.rows[*i].id.clone()),
            _ => None,
        });
        assert_eq!(row.as_deref(), Some(id), "a click on {text} is that row's");
    }
    light(&mut app, "theme:manage:export");
    assert!(
        keys(&app).contains("Export") && !keys(&app).contains("Apply"),
        "the row lit says its own word: {}",
        keys(&app)
    );
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 1));
    assert_eq!(calls.lock().unwrap()[0]["name"], "theme_export");
}

/// A file being picked is let go when home is sent to another place from outside (a block of the bar, a key). The
/// pick went with it: every page after was cut to the files it takes, its keys' line still asking for one.
#[test]
fn a_jump_from_outside_lets_a_file_pick_go() {
    let (mut app, _rx, _calls) = theme();
    open(&mut app, YOURS);
    let (back, depth) = (app.view.clone(), app.came_from.len());
    app.picking = Some(Picking {
        back: back.clone(),
        depth,
        prov: 0,
        tool: "theme_install".into(),
        types: vec!["spark-theme".into()],
        arguments: serde_json::Map::new(),
        step: None,
        field: String::new(),
        what: String::new(),
    });
    app.came_from.push(app.view.clone());
    app.view = View::Folder(0, "spark-shell://theme/rows/elsewhere".into());
    assert!(keys(&app).to_lowercase().contains("pick a file"), "{}", keys(&app));
    assert!(app.go_to("theme"), "home goes where it is sent");
    assert!(app.picking.is_none());
    assert_eq!(app.view, View::Section(0));
    assert!(!keys(&app).to_lowercase().contains("pick a file"), "{}", keys(&app));
    assert_eq!(app.came_from.last(), Some(&back), "back goes to the page the pick was asked on");
}

/// Back from a pick of a file, the page it began on stands as it was while its rows are read again. It stood blank
/// the second its provider took to read a slow page (the wallpaper's screens).
#[test]
fn back_from_a_pick_the_page_stands_while_it_is_read_again() {
    let (mut app, _rx, _calls) = theme();
    let mut files = spark_dialog::app::Provider::new("files");
    files.ready = true;
    files.rows = spark_dialog::model::rows(
        &json!({"title": "files", "rows": [{"id": "files:root", "text": "~", "children": "spark-shell://files/rows/aG9tZQ"}]}).to_string(),
    )
    .unwrap();
    app.providers.push(files);
    let mut rows = page(YOURS);
    rows["rows"].as_array_mut().unwrap().push(
        json!({"id": "theme:new:picture", "group": "new theme", "text": "from a picture", "sign": "opens",
        "children": "spark-shell://files/rows", "pick": {"tool": "theme_picture", "types": ["png"]}}),
    );
    app.came_from.push(app.view.clone());
    app.view = View::Folder(0, YOURS.into());
    app.folder = Some((0, YOURS.into(), spark_dialog::model::rows(&rows.to_string()).unwrap()));
    light(&mut app, "theme:new:picture");
    app.enter();
    assert!(app.picking.is_some(), "the pick opened");
    assert!(matches!(&app.view, View::Folder(1, _)), "{:?}", app.view);
    app.escape();
    assert_eq!(app.view, View::Folder(0, YOURS.into()));
    assert!(
        app.folder
            .as_ref()
            .is_some_and(|(_, u, r)| u == YOURS && r.rows.iter().any(|x| x.id == "theme:new:picture")),
        "the page's rows stand at once"
    );
    assert!(!words(&frame(&mut app, 600.0, 800.0)).iter().all(|w| w.0 != "from a picture"), "and are drawn");
}

/// A value being asked for is let go too when home is sent elsewhere: the question stood unseen over the place home
/// went to, and the next Enter there answered it.
#[test]
fn a_jump_from_outside_lets_a_question_go() {
    let (mut app, rx, calls) = theme();
    open(&mut app, COLORS);
    light(&mut app, "theme:color:FG");
    app.enter();
    app.right();
    assert!(app.picker.is_some());
    assert!(app.go_to("theme"));
    assert_eq!(app.mode, Mode::Normal);
    assert!(app.picker.is_none() && app.input.is_empty());
    assert_eq!(app.view, View::Section(0));
    app.enter();
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    assert!(
        calls.lock().unwrap().iter().all(|c| c["name"] != "theme_color"),
        "no color was set: {:?}",
        calls.lock().unwrap()
    );
}

/// What the theme's words find says what Enter does to it, and a theme shown by its title is found by its name too.
#[test]
fn a_theme_found_by_its_name_says_enter_applies_it() {
    let (mut app, _rx, _calls) = theme();
    app.came_from.push(app.view.clone());
    app.view = View::Section(0);
    type_in(&mut app, "mars-conquest");
    assert!(app.in_list, "the words light the theme they name");
    let lit = app.picks().get(app.sel).cloned();
    assert!(
        matches!(lit, Some(Item::Row(0, r)) if app.providers[0].rows.rows[r].id == "theme:mars-conquest"),
        "{:?}",
        lit
    );
    assert!(keys(&app).contains("Apply") && keys(&app).contains("Enter"), "{}", keys(&app));
    assert!(!keys(&app).contains("Change"), "the arrows change no value of a theme: {}", keys(&app));
}

/// A look changed outside home (the prompt, a key, another home) is worn, and every place reads its rows again.
#[test]
fn a_look_changed_outside_is_worn_and_every_place_reads_again() {
    let (mut app, rx, _calls) = theme();
    assert!(pump(&mut app, &rx, |a| !a.providers[0].dirty && !a.providers[0].rows.rows.is_empty()));
    let look = spark_dialog::look::parse("HEX_FG=e8d9c5\nHEX_ACCENT=e6a878\nPANEL_BG=2a1f1b\nGLYPH_FAMILY=banner\nFONT=Monaspace Krypton 12\n").unwrap();
    app.wear_look(&look);
    assert_eq!(app.palette.as_ref().and_then(|p| p.get("HEX_ACCENT")).and_then(Value::as_str), Some("e6a878"));
    assert_eq!(app.glyphs, spark_dialog::glyphs::BANNER);
    // its opening and closing too: the piece the look names is the one home closes with
    let moved = spark_dialog::look::parse("PANEL_BG=2a1f1b\nTRANSITIONS=draw:moon\n").unwrap();
    app.wear_look(&moved);
    assert_eq!(app.cfg.transitions.as_deref(), Some("draw:moon"));
    assert!(
        app.providers.iter().all(|p| p.dirty || p.last_read.is_none()),
        "each place is read again: one in view now, any other when it is next opened"
    );
    // a place not in view waits until it is watched: what its provider makes apart for the new look is said only then
    app.providers[0].subscribed = None;
    app.providers[0].dirty = false;
    app.providers[0].last_read = Some(std::time::Instant::now());
    app.view = View::Section(0);
    app.wear_look(&look);
    assert!(!app.providers[0].dirty && app.providers[0].last_read.is_none());
    app.providers[0].subscribed = Some(ROOT.into());
    app.wear_look(&look);
    assert!(app.providers[0].dirty, "a place in view reads now");
}

/// What a fresh review of the picker and the forms found, each held here.
#[test]
fn a_color_pasted_is_the_color_used_and_a_name_typed_survives_the_arrows() {
    let (mut app, rx, calls) = theme();
    open(&mut app, COLORS);
    light(&mut app, "theme:color:FG");
    app.enter();
    // a paste replaces the value lit, the strips follow it, and Enter uses it: it used the color before the paste
    app.paste("#ff8800");
    assert_eq!(app.input, "#ff8800");
    assert_eq!(app.picker.as_ref().unwrap().value(), [0xff, 0x88, 0x00]);
    app.enter();
    assert!(pump(&mut app, &rx, |_| calls.lock().unwrap().len() == 1));
    assert_eq!(calls.lock().unwrap()[0]["arguments"]["color"], "#ff8800");
    assert!(pump(&mut app, &rx, |a| a.running.is_none()));
    // a name typed stays while Up and Down change the strip: they change no color
    open(&mut app, COLORS);
    light(&mut app, "theme:color:ACCENT");
    app.enter();
    type_in(&mut app, "teal");
    app.down();
    app.up();
    assert_eq!(app.input, "teal");
    // on the list's own colors the first step takes the first of them
    let p = app.picker.as_mut().unwrap();
    p.strip = Strip::Theirs;
    let first = p.theirs[0].1;
    app.right();
    assert_eq!(app.picker.as_ref().unwrap().value(), first, "the first of the theme's colors, not the second");
    app.right();
    assert_eq!(app.picker.as_ref().unwrap().value(), app.picker.as_ref().unwrap().theirs[1].1);
}

#[test]
fn while_a_value_is_asked_for_the_page_behind_takes_no_key_and_no_click() {
    let (mut app, _rx, calls) = theme();
    open(&mut app, YOURS);
    light(&mut app, "theme:new:look");
    let at = app.sel;
    app.enter();
    type_in(&mut app, "my theme");
    // Home and End are the prompt's: the cursor moves, the row that asked stays lit
    app.line_start();
    assert_eq!((app.cursor, app.sel, app.in_list), (0, at, true));
    app.line_end();
    assert_eq!(app.cursor, "my theme".chars().count());
    app.page(1);
    assert_eq!(app.sel, at);
    // a click on another row is not that row's, and not an Enter
    app.clicked(1, std::time::Instant::now());
    assert!(matches!(app.mode, Mode::Ask { .. }) && app.sel == at, "the question stands");
    assert_eq!(app.input, "my theme");
    assert!(calls.lock().unwrap().is_empty());
    // attach waits too: no file pick opens over the question
    app.chip(0);
    assert!(app.attaching.is_none() && matches!(app.mode, Mode::Ask { .. }));
}

#[test]
fn a_pick_let_go_leaves_no_words_behind_and_a_question_let_go_is_said() {
    let (mut app, _rx, _calls) = theme();
    open(&mut app, YOURS);
    let (back, depth) = (app.view.clone(), app.came_from.len());
    app.picking = Some(Picking {
        back: back.clone(),
        depth,
        prov: 0,
        tool: "theme_install".into(),
        types: vec!["spark-theme".into()],
        arguments: serde_json::Map::new(),
        step: None,
        field: String::new(),
        what: String::new(),
    });
    app.came_from.push(app.view.clone());
    app.view = View::Folder(0, "spark-shell://theme/rows/elsewhere".into());
    type_in(&mut app, "beach");
    assert!(app.go_to("theme"));
    assert!(app.input.is_empty(), "the words typed to find a file went with the pick: {:?}", app.input);
    app.escape();
    assert_eq!(app.view, back);
    assert!(app.input.is_empty(), "and the page the pick began on is not searched for them: {:?}", app.input);
    // a question let go by a jump to the place already shown is a change to draw: go_to says so
    app.came_from.push(app.view.clone());
    app.view = View::Section(0);
    open(&mut app, COLORS);
    light(&mut app, "theme:color:FG");
    app.enter();
    app.view = View::Section(0);
    assert!(app.go_to("theme"), "the place is the one shown, and the question went: a frame is owed");
    assert_eq!(app.mode, Mode::Normal);
}

/// A color asked for from a place that is no page of the theme's (home, by what its words found) is picked on the
/// same strips: they stood nowhere in pixels, and the arrows changed a color nobody saw.
#[test]
fn a_color_asked_for_anywhere_is_picked_on_the_strips() {
    let (mut app, _rx, _calls) = theme();
    assert_eq!(app.view, View::Home);
    let call = spark_dialog::model::rows(&page(COLORS).to_string()).unwrap().rows[3].tool.clone().unwrap();
    app.run(spark_dialog::app::Step {
        prov: 0,
        call,
        who: spark_dialog::app::Who::Person,
        line: "theme color text".into(),
        typed: false,
    });
    assert!(app.picker.is_some());
    assert_eq!(scene::kind(&app), Kind::Page);
    let drawn = frame(&mut app, 600.0, 800.0);
    assert!(words(&drawn).iter().any(|w| w.0 == "hue") && words(&drawn).iter().any(|w| w.0 == "strength"));
}

/// A code typed for a pairing, or an answer to a provider's question, is no search either.
#[test]
fn an_answer_typed_to_a_provider_is_not_searched_for() {
    let (mut app, _rx, _calls) = theme();
    assert_eq!(app.view, View::Home);
    app.mode = Mode::Pair {
        prov: 0,
        id: json!("p1"),
        message: "the code on the speaker".into(),
        kind: "pin".into(),
    };
    type_in(&mut app, "4711");
    assert!(app.search_at.is_none(), "a pairing code is not searched for");
    app.mode = Mode::Elicit {
        prov: 0,
        id: json!("e1"),
        message: "which name".into(),
        fields: vec![("name".into(), "a name".into())],
        answers: serde_json::Map::new(),
        at: 0,
    };
    type_in(&mut app, "x");
    assert!(app.search_at.is_none(), "nor an answer to a provider's question");
}
