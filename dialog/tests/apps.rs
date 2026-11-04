// Apps, drawn with the dialog's own rows: an app a row under its category's heading, a switch to hide it, a
// choice row with its arrow for its category and its launch, a child list for its technical details, and
// every change applied at once with Undo on the status row. Nothing is a draft, nothing asks before it
// leaves, and no label changes under a moving pointer.
mod common;
use ratatui::{buffer::Buffer, layout::Rect, style::Modifier};
use serde_json::json;
use spark_dialog::app::{App, Config, Helper, HintKey, Item, View};
use spark_dialog::apps::{
    preferences::{Preference, Preferences},
    Action, Line, Navigation, Page,
};
use spark_dialog::reply::Mark;
use std::path::PathBuf;

static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
const ID: &str = "org.example.Editor.desktop";

fn app() -> App {
    let mut a = App::new(Config::default(), &[]);
    a.view = View::Apps;
    a.came_from.push(View::Home);
    a.apps.prefs = Preferences::default();
    a.apps.preference_error = None;
    a.apps.path = std::env::temp_dir()
        .join(format!(
            "apps-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ))
        .join("apps.json");
    a.apps.pending = Some((1, "catalog".into()));
    a.apps.receive(1, json!({"apps":[
        {"id":ID,"name":"Editor","generic_name":"Text Editor","description":"Write Documents","categories":["Development","Utility"],"focus":true,"new_window":"new-window","launcher":"/data/Applications/Editor.desktop"},
        {"id":"browser.desktop","name":"browser","description":"Read the web","categories":["Network"]},
        {"id":"firefox.desktop","name":"Firefox","display_name":"Mozilla Firefox","generic_name":"Web Browser","categories":["Network"]},
        {"id":"mystery.desktop","name":"Mystery","description":"","categories":["Unknown"]}
    ]})).unwrap();
    a
}
fn act(a: &mut App, action: Action) {
    a.apps_activate(action);
}
fn pick(a: &mut App, action: Action) {
    let n = a
        .picks()
        .iter()
        .position(|x| matches!(x, Item::Apps(l) if l.action.as_ref() == Some(&action)))
        .unwrap_or_else(|| panic!("no row for {:?}", action));
    a.light(n);
}
fn lines(a: &App) -> Vec<Line> {
    a.apps.lines(60, &a.input, None)
}
fn line<'a>(ls: &'a [Line], action: &Action) -> &'a Line {
    ls.iter()
        .find(|l| l.action.as_ref() == Some(action))
        .unwrap_or_else(|| panic!("no line for {:?}", action))
}
fn words(a: &App) -> String {
    a.hint().iter().map(|(t, _)| t.clone()).collect()
}
fn draw(a: &mut App, w: u16, h: u16) -> (Buffer, spark_dialog::ui::Drawn, spark_dialog::palette::Palette) {
    a.size = (w, h);
    let pal = common::palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, w, h));
    let d = spark_dialog::ui::draw(a, &pal, "", &mut b);
    (b, d, pal)
}
fn cleanup(a: &App) {
    let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
}

#[test]
fn the_list_is_the_apps_under_their_categories_then_the_managing_rows() {
    let a = app();
    let ls = lines(&a);
    let first = ls.iter().find(|l| !l.label.is_empty()).unwrap();
    assert!(
        first.heading && first.label == "development" && first.indent == 2,
        "a category is a heading, muted, lowercase: {:?}",
        first
    );
    let editor = line(&ls, &Action::Launch(ID.into()));
    assert_eq!(
        (editor.sign, editor.indent, editor.label.as_str()),
        ("opens", 4, "Editor"),
        "an app opens: its sign, under its heading"
    );
    assert_eq!(
        (editor.value.as_str(), editor.value_x, editor.value_muted),
        ("Text Editor", 26, true),
        "its role, muted, in one column"
    );
    let browser = line(&ls, &Action::Launch("browser.desktop".into()));
    assert!(browser.value.is_empty(), "no role, nothing invented");
    assert!(
        !ls.iter().any(|l| l.label.contains("hidden apps:") || l.label == "all categories"),
        "no toolbar above the list"
    );
    let tail: Vec<(&str, &str, &str)> = ls
        .iter()
        .skip_while(|l| l.action != Some(Action::Filter))
        .map(|l| (l.label.as_str(), l.value.as_str(), l.tail.as_str()))
        .collect();
    assert_eq!(
        tail,
        [
            ("category", "all", "\u{203a}"),
            ("hidden apps", "none", "\u{203a}"),
            ("categories", "", "\u{203a}"),
            ("refresh apps", "", "")
        ],
        "the managing rows at the end, each a row the dialog has: a choice with its arrow, a list behind an arrow, a step"
    );
    let at = ls.iter().position(|l| l.action == Some(Action::Filter)).unwrap();
    assert!(ls[at - 1].label.is_empty(), "a row of air before them");
    cleanup(&a);
}

#[test]
fn supplied_names_keep_their_spelling_and_search_reads_roles_and_comments() {
    let a = app();
    assert_eq!(a.apps.visible("mozilla")[0].name, "Firefox", "the name as the desktop entry writes it");
    assert_eq!(a.apps.visible("text")[0].id, ID, "the role is searchable");
    assert_eq!(a.apps.visible("write documents")[0].id, ID, "the full comment is searchable");
    assert_eq!(a.apps.visible("read the web")[0].id, "browser.desktop");
    let names: Vec<&str> = a.apps.visible("").iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        names,
        ["Editor", "browser", "Firefox", "Mystery"],
        "its category first, then the name whatever its case"
    );
    cleanup(&a);
}

#[test]
fn nothing_is_underlined_and_the_lit_row_wears_the_column_band() {
    for page in [Page::List, Page::Details(ID.into())] {
        for (w, h) in [(60u16, 40u16), (150, 40), (36, 20)] {
            let mut a = app();
            a.apps.page = page.clone();
            a.light(0);
            let (b, d, pal) = draw(&mut a, w, h);
            for y in 0..h {
                for x in 0..w {
                    assert!(
                        !b[(x, y)].modifier.contains(Modifier::UNDERLINED),
                        "{:?} at {}x{}: underlined at ({}, {})",
                        page,
                        w,
                        h,
                        x,
                        y
                    );
                }
            }
            let y = d.picks.iter().find(|(_, n)| *n == 0).unwrap().0;
            let band: Vec<u16> = (0..w).filter(|x| b[(*x, y)].bg == pal.lit).collect();
            assert_eq!(
                (band[0], *band.last().unwrap() + 1),
                d.columns,
                "{:?} at {}x{}: the band is the column",
                page,
                w,
                h
            );
            assert_eq!(b[(d.columns.0, y)].symbol(), "\u{203a}", "the cursor at the band's first cell");
            let label_x = (d.columns.0..d.columns.1)
                .find(|x| b[(*x, y)].symbol() != " " && b[(*x, y)].symbol() != "\u{203a}")
                .unwrap();
            let label_x = (label_x..d.columns.1).find(|x| b[(*x, y)].symbol().chars().all(char::is_alphabetic)).unwrap();
            assert_eq!(b[(label_x, y)].fg, pal.accent, "{:?} at {}x{}: the lit row's name in the accent", page, w, h);
            cleanup(&a);
        }
    }
}

#[test]
fn the_frame_is_the_dialogs_own_column_in_the_middle() {
    let mut a = app();
    pick(&mut a, Action::Launch(ID.into()));
    for (w, h) in [(60, 40), (150, 40), (80, 40), (36, 20)] {
        let (b, d, _) = draw(&mut a, w, h);
        let width = w.min(60);
        let left = (w - width) / 2;
        assert_eq!(d.columns, (left, left + width));
        assert_eq!(b[(left + 2, 0)].symbol(), "a", "the header at the column's inset at {}x{}", w, h);
        assert_eq!(b[(left + 2, spark_dialog::ui::PROMPT_Y)].symbol(), "\u{276f}");
        let y = d.picks.iter().find(|(_, n)| *n == a.sel).unwrap().0;
        assert_eq!(b[(left + 6, y)].symbol(), "E", "the lit app's name at the row's inset");
    }
    cleanup(&a);
}

#[test]
fn the_key_row_is_the_pages_whatever_is_lit_or_typed() {
    let mut a = app();
    let list = words(&a);
    assert_eq!(list, "Back Esc   Open Enter   Details \u{2192}");
    a.light(2);
    assert_eq!(words(&a), list, "a row lit");
    a.set_draft("fire");
    assert_eq!(words(&a), list, "words typed");
    a.set_draft("");
    pick(&mut a, Action::Filter);
    assert_eq!(words(&a), list, "the managing row lit");
    act(&mut a, Action::Details(ID.into()));
    let details = words(&a);
    assert_eq!(details, "Back Esc   Open Enter");
    pick(&mut a, Action::Visibility(ID.into()));
    assert_eq!(words(&a), details, "the switch lit");
    pick(&mut a, Action::ChooseCategory(ID.into()));
    assert_eq!(words(&a), details, "a choice lit");
    act(&mut a, Action::Categories);
    act(&mut a, Action::AddCategory);
    assert_eq!(words(&a), "Cancel Esc   Save Enter", "a form");
    a.set_draft("Writing");
    assert_eq!(words(&a), "Cancel Esc   Save Enter");
    cleanup(&a);
}

#[test]
fn hiding_an_app_is_a_switch_applied_at_once_with_undo() {
    let mut a = app();
    act(&mut a, Action::Details(ID.into()));
    let sw = line(&lines(&a), &Action::Visibility(ID.into())).clone();
    assert_eq!(
        (sw.sign, sw.label.as_str(), sw.value.as_str()),
        ("ring", "hide this app", "off"),
        "a switch, as a setting's: {:?}",
        sw
    );
    act(&mut a, Action::Visibility(ID.into()));
    assert!(a.apps.preference(ID).hidden, "hidden at once");
    assert!(Preferences::load(&a.apps.path).unwrap().apps[ID].hidden, "and saved at once");
    let r = a.reply.clone().expect("a receipt on the status row");
    assert_eq!((r.mark, r.text.as_str(), r.undo), (Mark::Done, "Editor hidden", true));
    let sw = line(&lines(&a), &Action::Visibility(ID.into())).clone();
    assert_eq!((sw.sign, sw.value.as_str()), ("dot", "on"));
    let (b, d, _) = draw(&mut a, 60, 40);
    assert!(d.reply_undo.is_some(), "Undo at the status row's right");
    let status: String = (0..60).map(|x| b[(x, 35)].symbol()).collect();
    assert!(status.contains("Editor hidden") && status.contains("Undo"), "{:?}", status);
    a.undo_now();
    assert!(!a.apps.preference(ID).hidden, "undo puts it back");
    assert!(!Preferences::load(&a.apps.path).unwrap().apps.get(ID).is_some_and(|p| p.hidden));
    assert!(a.reply.as_ref().is_none_or(|r| !r.undo), "an undo has no undo");
    cleanup(&a);
}

#[test]
fn category_and_launch_are_choice_rows_that_open_a_checked_list() {
    let mut a = app();
    act(&mut a, Action::Details(ID.into()));
    let ls = lines(&a);
    let cat = line(&ls, &Action::ChooseCategory(ID.into()));
    assert_eq!(
        (cat.label.as_str(), cat.value.as_str(), cat.tail.as_str()),
        ("category", "development", "\u{203a}")
    );
    let launch = line(&ls, &Action::ChooseLaunch(ID.into()));
    assert_eq!(
        (launch.label.as_str(), launch.value.as_str(), launch.tail.as_str()),
        ("launch", "application default", "\u{203a}")
    );
    assert!(
        !ls.iter().any(|l| l.label == "save" || l.label == "cancel" || l.label.contains("unsaved")),
        "nothing to save, nothing said about it"
    );

    act(&mut a, Action::ChooseCategory(ID.into()));
    assert_eq!(a.apps.page, Page::CategoryPicker(ID.into()));
    let ls = lines(&a);
    let mapped = line(&ls, &Action::SetCategory(ID.into(), None));
    assert_eq!(
        (mapped.sign, mapped.label.as_str()),
        ("check", "as mapped: development"),
        "the choice in use is checked"
    );
    let web = line(&ls, &Action::SetCategory(ID.into(), Some("Web".into())));
    assert_eq!((web.sign, web.label.as_str()), ("blank", "web"));
    act(&mut a, Action::SetCategory(ID.into(), Some("Web".into())));
    assert_eq!(a.apps.page, Page::Details(ID.into()), "the pick made, back to the details");
    assert_eq!(a.apps.preference(ID).category.as_deref(), Some("Web"));
    assert_eq!(
        Preferences::load(&a.apps.path).unwrap().apps[ID].category.as_deref(),
        Some("Web"),
        "saved at once"
    );
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("Editor in web", true)));
    act(&mut a, Action::ChooseCategory(ID.into()));
    assert_eq!(line(&lines(&a), &Action::SetCategory(ID.into(), Some("Web".into()))).sign, "check");
    a.escape();
    assert_eq!(a.apps.page, Page::Details(ID.into()), "Esc from the list is the details again, nothing asked");

    act(&mut a, Action::ChooseLaunch(ID.into()));
    let ls = lines(&a);
    assert_eq!(line(&ls, &Action::SetLaunch(ID.into(), "default".into())).sign, "check");
    assert!(
        ls.iter().any(|l| l.action == Some(Action::SetLaunch(ID.into(), "focus".into()))),
        "the editor declares a window"
    );
    assert!(
        ls.iter().any(|l| l.action == Some(Action::SetLaunch(ID.into(), "new".into()))),
        "and a new window"
    );
    act(&mut a, Action::SetLaunch(ID.into(), "focus".into()));
    assert_eq!(a.apps.preference(ID).mode(), "focus");
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("Editor: focus existing", true)));
    a.undo_now();
    assert_eq!(a.apps.preference(ID).mode(), "default");

    // an app with no window identity offers the default alone, and says why
    act(&mut a, Action::Details("browser.desktop".into()));
    act(&mut a, Action::ChooseLaunch("browser.desktop".into()));
    let ls = lines(&a);
    assert!(!ls.iter().any(|l| l.action == Some(Action::SetLaunch("browser.desktop".into(), "focus".into()))));
    assert!(ls.iter().any(|l| l.muted && l.label.contains("window identity")), "{:?}", ls);
    cleanup(&a);
}

#[test]
fn hidden_apps_are_a_list_of_their_own_and_never_leak_into_the_homes_search() {
    let mut a = app();
    a.apps.pending = Some((7, "catalog".into()));
    a.apps
        .receive(
            7,
            json!({"apps":[
                {"id":"foot.desktop","name":"foot","generic_name":"Terminal"},
                {"id":"footclient.desktop","name":"foot client","generic_name":"Terminal"},
                {"id":"foot-server.desktop","name":"foot server","generic_name":"Terminal"}
            ]}),
        )
        .unwrap();
    assert_eq!(
        a.apps.visible("foot").iter().map(|e| e.id.as_str()).collect::<Vec<_>>(),
        ["foot.desktop"],
        "the helpers start hidden"
    );
    let row = line(&lines(&a), &Action::Hidden).clone();
    assert_eq!(row.value, "2", "the list says how many");
    a.view = View::Home;
    a.set_draft("foot client");
    assert!(
        !a.picks().iter().any(|it| matches!(it, Item::Apps(_))),
        "a hidden app is not found from the home"
    );
    a.view = View::Apps;
    a.set_draft("");
    act(&mut a, Action::Hidden);
    assert_eq!(a.apps.page, Page::Hidden);
    let ls = lines(&a);
    let hidden: Vec<&str> = ls
        .iter()
        .filter(|l| matches!(l.action, Some(Action::Launch(_))))
        .map(|l| l.label.as_str())
        .collect();
    assert_eq!(hidden, ["foot client", "foot server"], "each a row that opens, as in the list");
    assert_eq!(words(&a), "Back Esc   Open Enter   Details \u{2192}", "the same keys as the list");
    pick(&mut a, Action::Launch("footclient.desktop".into()));
    assert!(a.apps_details(), "Right opens its details, where the switch is");
    act(&mut a, Action::Visibility("footclient.desktop".into()));
    assert!(!a.apps.preference("footclient.desktop").hidden);
    a.apps.prefs = Preferences::load(&a.apps.path).unwrap();
    assert_eq!(a.apps.visible("foot").len(), 2, "shown, and shown after a restart");
    a.escape();
    a.escape();
    assert_eq!(a.apps.page, Page::List);
    assert_eq!(line(&lines(&a), &Action::Hidden).value, "1");
    cleanup(&a);
}

#[test]
fn the_details_are_the_facts_then_the_steps_then_the_preferences() {
    let mut a = app();
    a.apps.details.insert(
        ID.into(),
        json!({"version":"1.2","installed":"XBPS / System","source":"XBPS","fields":[["Launcher","/data/Applications/Editor.desktop"]]}),
    );
    act(&mut a, Action::Details(ID.into()));
    let ls = lines(&a);
    let texts: Vec<String> = ls.iter().map(|l| format!("{}|{}|{}", l.label, l.value, l.tail)).collect();
    assert_eq!(texts[0], "Editor||", "the name first, as supplied");
    assert!(ls[0].title && !ls[0].heading, "the subject of the page, in the text color");
    assert!(ls.iter().any(|l| l.muted && l.label == "Write Documents"), "what it is, muted");
    let version = ls.iter().find(|l| l.label == "version").unwrap();
    assert_eq!(
        (version.value.as_str(), version.action.is_none(), version.value_x),
        ("1.2", true, 26),
        "a fact: a label and a value, no action"
    );
    let open = line(&ls, &Action::Launch(ID.into()));
    assert_eq!((open.sign, open.label.as_str()), ("opens", "open"));
    let tech = line(&ls, &Action::Technical(ID.into()));
    assert_eq!(
        (tech.label.as_str(), tech.tail.as_str()),
        ("technical details", "\u{203a}"),
        "a list behind its arrow, nothing unfolds in place"
    );
    let prefs = ls.iter().position(|l| l.heading && l.label == "preferences").unwrap();
    let after: Vec<&Action> = ls[prefs..].iter().filter_map(|l| l.action.as_ref()).collect();
    assert_eq!(
        after,
        [
            &Action::Visibility(ID.into()),
            &Action::ChooseCategory(ID.into()),
            &Action::ChooseLaunch(ID.into())
        ],
        "the switch, then the two choices, and nothing else"
    );
    act(&mut a, Action::Technical(ID.into()));
    assert_eq!(a.apps.page, Page::Technical(ID.into()));
    let ls = lines(&a);
    let at = ls.iter().position(|l| l.label == "launcher").expect("the launcher, its label lowercase");
    let whole: String = ls[at..]
        .iter()
        .take_while(|l| l.label == "launcher" || l.continuation)
        .map(|l| l.value.as_str())
        .collect();
    assert_eq!(
        whole, "/data/Applications/Editor.desktop",
        "a long value wraps under the value column, whole: {:?}",
        ls
    );
    assert!(ls.iter().any(|l| l.action == Some(Action::Copy("/data/Applications/Editor.desktop".into()))));
    a.escape();
    assert_eq!(a.apps.page, Page::Details(ID.into()));
    cleanup(&a);
}

#[test]
fn every_line_of_long_technical_metadata_is_reachable_by_paging() {
    let mut a = app();
    a.apps.details.insert(
        ID.into(),
        json!({"fields":[["Long value",(0..100).map(|n|format!("value-{n:03} ")).collect::<String>()]]}),
    );
    act(&mut a, Action::Details(ID.into()));
    act(&mut a, Action::Technical(ID.into()));
    a.in_list = false;
    let pal = common::palette("tokyonight-night");
    a.size = (36, 20);
    let mut observed = String::new();
    for _ in 0..80 {
        let mut b = Buffer::empty(Rect::new(0, 0, 36, 20));
        spark_dialog::ui::draw(&a, &pal, "", &mut b);
        for y in 7..14 {
            for x in 0..36 {
                observed.push_str(b[(x, y)].symbol());
            }
        }
        a.page(1);
    }
    for n in 0..100 {
        assert!(observed.contains(&format!("value-{n:03}")), "missing value {n}");
    }
    cleanup(&a);
}

#[test]
fn details_back_restores_the_search_the_selection_and_the_scroll() {
    let mut a = app();
    a.set_draft("editor");
    pick(&mut a, Action::Launch(ID.into()));
    a.scroll = 3;
    let sel = a.sel;
    assert!(a.apps_details());
    assert!(a.input.is_empty(), "the details have their own prompt");
    a.escape();
    assert_eq!(a.apps.page, Page::List);
    assert_eq!((a.input.as_str(), a.sel, a.scroll), ("editor", sel, 3));
    a.escape();
    assert!(a.input.is_empty(), "the first Esc clears the words");
    assert_eq!(a.view, View::Apps);
    a.escape();
    assert_eq!(a.view, View::Home, "the next goes back, nothing asked");
    cleanup(&a);
}

#[test]
fn launch_modes_share_enter_and_click_dispatch_and_preserve_context_on_failure() {
    let mut a = app();
    a.set_draft("editor");
    a.apps.prefs.apps.insert(
        ID.into(),
        Preference {
            launch: "focus".into(),
            ..Default::default()
        },
    );
    pick(&mut a, Action::Launch(ID.into()));
    a.enter();
    let serial = a.apps.serial;
    assert!(
        matches!(a.jobs.last(), Some(spark_dialog::app::Job::RunInput(_, _, s)) if serde_json::from_str::<serde_json::Value>(s).unwrap()["mode"] == "focus")
    );
    a.helper(Helper::Apps(serial), Ok(json!({"error":"Fixture launch refused"}).to_string()));
    assert_eq!(a.input, "editor");
    assert!(a.reply.as_ref().unwrap().text.contains("refused"));
    pick(&mut a, Action::Launch(ID.into()));
    a.enter();
    assert!(a.apps.pending.is_some());
    a.apps.pending = None;
    a.apps.prefs.apps.insert(
        "browser.desktop".into(),
        Preference {
            launch: "new".into(),
            ..Default::default()
        },
    );
    assert!(a.apps.activate(Action::Launch("browser.desktop".into()), Navigation::default()).is_err());
    cleanup(&a);
}

#[test]
fn categories_and_mappings_change_at_once_with_undo_and_a_form_types_in_the_prompt() {
    let mut a = app();
    act(&mut a, Action::Categories);
    let ls = lines(&a);
    assert_eq!(line(&ls, &Action::Category("Development".into())).tail, "\u{203a}");
    assert_eq!(line(&ls, &Action::Category("Development".into())).label, "development");
    assert!(ls.iter().any(|l| l.action == Some(Action::AddCategory) && l.label == "new category"));
    assert!(ls
        .iter()
        .any(|l| l.action == Some(Action::Mappings) && l.label == "mappings" && l.tail == "\u{203a}"));

    // rename: a form, typed in the prompt, Enter saves it at once
    act(&mut a, Action::Category("Development".into()));
    act(&mut a, Action::Rename("Development".into()));
    assert!(a.apps.form());
    a.set_draft("Work");
    a.enter();
    assert!(a.apps.prefs.categories.contains(&"Work".into()) && !a.apps.form());
    assert_eq!(Preferences::load(&a.apps.path).unwrap().mappings["Development"], "Work");
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("development renamed to work", true)));
    assert!(matches!(&a.apps.page, Page::Category(c) if c == "Work"), "{:?}", a.apps.page);

    // delete: at once, and Undo brings the category, its mappings and its apps' places back
    act(&mut a, Action::Delete("Work".into()));
    assert!(!a.apps.prefs.categories.contains(&"Work".into()));
    assert_eq!(a.apps.page, Page::Categories);
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("work deleted", true)));
    let system = a.apps.entry(ID).unwrap().categories.clone();
    assert_eq!(a.apps.prefs.category(ID, &system), "Utilities");
    a.undo_now();
    assert!(a.apps.prefs.categories.contains(&"Work".into()));
    assert_eq!(a.apps.prefs.category(ID, &system), "Work");
    assert_eq!(Preferences::load(&a.apps.path).unwrap().mappings["Development"], "Work");
    act(&mut a, Action::Delete("Other".into()));
    assert!(a.reply.as_ref().is_some_and(|r| r.mark == Mark::Refused), "Other is the fallback");

    // a mapping: its row names the source and the target, the list behind it is checked, a pick applies at once
    act(&mut a, Action::Mappings);
    let ls = lines(&a);
    let dev = line(&ls, &Action::Mapping("Development".into()));
    assert_eq!(
        (dev.label.as_str(), dev.value.as_str(), dev.tail.as_str()),
        ("Development", "work", "\u{203a}"),
        "the desktop's word, then ours"
    );
    act(&mut a, Action::Mapping("Development".into()));
    let ls = lines(&a);
    assert_eq!(line(&ls, &Action::Map("Development".into(), Some("Work".into()))).sign, "check");
    act(&mut a, Action::Map("Development".into(), Some("Office".into())));
    assert_eq!(a.apps.prefs.mappings["Development"], "Office");
    assert_eq!(a.apps.page, Page::Mappings, "the pick made, back to the mappings");
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("Development maps to office", true)));
    act(&mut a, Action::Mapping("Development".into()));
    act(&mut a, Action::Map("Development".into(), None));
    assert!(!a.apps.prefs.mappings.contains_key("Development"));
    a.undo_now();
    assert_eq!(a.apps.prefs.mappings["Development"], "Office");

    // a new mapping asks its desktop word in the prompt, then its category in the list
    act(&mut a, Action::AddMapping);
    a.set_draft("Foo");
    a.enter();
    assert!(matches!(&a.apps.page, Page::Mapping(s) if s == "Foo"));
    a.escape();
    assert_eq!(a.apps.page, Page::Mappings, "nothing kept, nothing asked");
    assert!(!a.apps.prefs.mappings.contains_key("Foo"));

    // a new category: the form, Esc lets it go without a word
    act(&mut a, Action::AddMapping);
    a.escape();
    assert_eq!(a.apps.page, Page::Mappings);
    a.escape();
    a.escape();
    act(&mut a, Action::AddCategory);
    a.set_draft("Writing");
    a.escape();
    assert!(!a.apps.form() && a.input.is_empty() && !a.apps.prefs.categories.contains(&"Writing".into()));
    cleanup(&a);
}

#[test]
fn a_renamed_category_keeps_its_filter() {
    let mut a = app();
    let name = a.apps.prefs.categories[0].clone();
    act(&mut a, Action::SetFilter(Some(name.clone())));
    assert_eq!(line(&lines(&a), &Action::Filter).value, "development", "the filter row says which");
    act(&mut a, Action::Categories);
    act(&mut a, Action::Category(name.clone()));
    act(&mut a, Action::Rename(name));
    a.set_draft("Renamed");
    act(&mut a, Action::Submit);
    assert_eq!(a.apps.filter.as_deref(), Some("Renamed"));
    cleanup(&a);
}

#[test]
fn the_filter_is_a_checked_list_and_the_query_crosses_categories() {
    let mut a = app();
    act(&mut a, Action::Filter);
    assert_eq!(a.apps.page, Page::Filter);
    let ls = lines(&a);
    assert_eq!(line(&ls, &Action::SetFilter(None)).sign, "check");
    assert_eq!(line(&ls, &Action::SetFilter(Some("Web".into()))).label, "web");
    act(&mut a, Action::SetFilter(Some("Web".into())));
    assert_eq!(a.apps.page, Page::List);
    assert_eq!(a.apps.visible("")[0].id, "browser.desktop");
    assert_eq!(a.apps.visible("write doc")[0].name, "Editor", "words search every category");
    act(&mut a, Action::Filter);
    assert_eq!(line(&lines(&a), &Action::SetFilter(Some("Web".into()))).sign, "check");
    cleanup(&a);
}

#[test]
fn preferences_survive_updates_and_restart() {
    let mut a = app();
    let system = a.apps.entry(ID).unwrap().categories.clone();
    assert_eq!(a.apps.prefs.category(ID, &system), "Development");
    assert_eq!(a.apps.prefs.category("unknown", &["X".into()]), "Other");
    a.apps.prefs.add("Writing").unwrap();
    a.apps.prefs.apps.insert(
        ID.into(),
        Preference {
            category: Some("Writing".into()),
            hidden: true,
            launch: "focus".into(),
        },
    );
    a.apps.prefs.save(&a.apps.path).unwrap();
    assert_eq!(Preferences::load(&a.apps.path).unwrap(), a.apps.prefs);
    a.apps.entries[0].name = "Editor updated".into();
    assert!(a.apps.visible("updated").is_empty(), "hidden, whatever its new name");
    act(&mut a, Action::Details(ID.into()));
    act(&mut a, Action::Visibility(ID.into()));
    assert!(!Preferences::load(&a.apps.path).unwrap().apps[ID].hidden);
    assert_eq!(a.apps.preference(ID).mode(), "focus", "the other preferences stand");
    cleanup(&a);
}

#[test]
fn unavailable_catalog_missing_metadata_and_invalid_preferences_are_explicit() {
    let mut a = app();
    a.apps.entries.clear();
    assert!(lines(&a).iter().any(|l| l.label.contains("No launchable")));
    a.apps.pending = Some((8, "catalog".into()));
    a.apps.receive(8, json!({"error":"GIO unavailable"})).unwrap_err();
    assert!(lines(&a).iter().any(|l| l.label.contains("Apps unavailable")));
    assert!(Preferences::parse("{}").is_err());
    a.apps.preference_error = Some("Invalid preferences".into());
    assert!(
        a.apps.activate(Action::Visibility(ID.into()), Navigation::default()).is_err(),
        "a change is refused, the file left as it is"
    );
    assert!(!PathBuf::from(&a.apps.path).exists());
    a.apps.failed = false;
    a.apps.pending = Some((9, "launch".into()));
    a.apps.receive(9, json!({"error":"launch failed"})).unwrap_err();
    assert!(!a.apps.failed, "a launch failure must not mislabel a valid catalog as unavailable");
    cleanup(&a);
}

#[test]
fn details_values_reflow_and_the_footer_keeps_its_room() {
    let mut a = app();
    a.apps.details.insert(
        ID.into(),
        json!({"version":"1.2","fields":[["Launcher","/data/Applications/A Very Long Folder/OriginalCase.desktop"]]}),
    );
    act(&mut a, Action::Details(ID.into()));
    a.attachment = Some("/data/An attached document.md".into());
    a.cfg.attach = vec!["files".into()];
    a.cfg.model = true;
    a.cfg.talk = true;
    a.model_name = Some("a-very-long-model-name-with-full-identity".into());
    for (w, h) in [(60, 40), (140, 50), (68, 49), (36, 20), (60, 40)] {
        let (_, d, _) = draw(&mut a, w, h);
        let footer = d.chips.iter().map(|c| c.2).min().unwrap();
        assert!(
            d.picks.iter().all(|&(y, _)| y < footer - 3),
            "the list ends above the status row and the footer"
        );
        for &(y, n) in &d.picks {
            assert!(matches!(&a.picks()[n], Item::Apps(l) if l.action.is_some()));
            assert!(y >= spark_dialog::ui::CONTENT_Y);
        }
    }
    let ls = a.apps.lines(36, "", None);
    let at = ls.iter().position(|l| l.label == "category").unwrap();
    assert!(
        ls[at].value.is_empty() && ls[at + 1].value == "development" && ls[at + 1].continuation,
        "narrow, the value under its label, one target"
    );
    cleanup(&a);
}

#[test]
fn configured_details_key_is_drawn_and_works() {
    let mut a = app();
    a.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"right":"F4"}"#).unwrap();
    pick(&mut a, Action::Launch(ID.into()));
    let (b, d, _) = draw(&mut a, 60, 40);
    let &(left, right, row, _) = d.keys.iter().find(|(_, _, _, k)| *k == HintKey::Right).expect("the Details key is drawn");
    assert!(left < right && row <= 5);
    let chip: String = (left..right).map(|x| b[(x, row)].symbol()).collect();
    assert!(chip.contains("F4"), "{:?}", chip);
    a.hint_key(HintKey::Right);
    assert_eq!(a.apps.page, Page::Details(ID.into()));
    cleanup(&a);
}

#[test]
fn reopening_details_refreshes_live_metadata_and_malformed_catalogs_stop_retrying() {
    let mut a = app();
    a.apps.details.insert(ID.into(), json!({"version":"old"}));
    let result = a.apps.activate(Action::Details(ID.into()), Navigation::default()).unwrap();
    assert_eq!(result.request.unwrap()["op"], "details");
    assert!(a.apps.details.contains_key(ID), "cached content remains readable while loading");
    a.apps.pending = Some((10, "catalog".into()));
    assert!(a.apps.receive(10, json!({"apps":null})).is_err());
    assert!(a.apps.failed);
    cleanup(&a);
}

#[test]
fn confirmed_launch_gives_the_app_the_screen_but_never_hides_a_newly_refocused_home() {
    let mut a = app();
    a.window_focused = false;
    a.apps.pending = Some((1, "launch".into()));
    a.helper(Helper::Apps(1), Ok(json!({"message":"Opened editor","confirmed":true}).to_string()));
    assert!(a.stow, "home steps aside for the app it opened");
    assert!(!a.hidden, "a clear window would stay over the app and take its clicks");
    a.stow = false;
    a.window_focused = true;
    a.apps.pending = Some((2, "launch".into()));
    a.helper(Helper::Apps(2), Ok(json!({"message":"Opened editor","confirmed":true}).to_string()));
    assert!(!a.stow, "a user's return to home wins over a delayed receipt");
    a.window_focused = false;
    a.apps.pending = Some((3, "launch".into()));
    a.helper(Helper::Apps(3), Ok(json!({"message":"Launch requested","confirmed":false}).to_string()));
    assert!(!a.stow, "an unconfirmed launch keeps its receipt visible");
    cleanup(&a);
}

#[test]
fn a_slow_app_moves_home_aside_when_its_window_takes_the_focus() {
    let mut a = app();
    a.window_focused = true;
    a.apps.pending = Some((7, "launch".into()));
    a.helper(Helper::Apps(7), Ok(json!({"message":"Launch requested","confirmed":false}).to_string()));
    assert!(!a.stow, "the receipt stays until a window comes");
    a.focus_lost();
    assert!(a.stow, "the slow app's window took the focus");
    a.stow = false;
    a.focus_lost();
    assert!(!a.stow, "one launch, one window");
    a.apps.pending = Some((8, "launch".into()));
    a.helper(Helper::Apps(8), Ok(json!({"message":"Launch requested","confirmed":false}).to_string()));
    a.launch_wait = Some(std::time::Instant::now() - std::time::Duration::from_secs(1));
    a.focus_lost();
    assert!(!a.stow, "long after the launch, the focus leaving is the person's");
    cleanup(&a);
}

#[test]
fn module_queries_request_drafts_and_attachments_have_separate_ownership() {
    let mut a = app();
    a.set_draft("editor");
    pick(&mut a, Action::Launch(ID.into()));
    let selected = a.sel;
    a.attachment = Some("/data/context.md".into());
    a.conversation();
    assert!(a.input.is_empty(), "a catalog filter must not become request text");
    a.set_draft("retain this request draft");
    a.conversation();
    assert_eq!(a.input, "editor");
    assert_eq!(a.sel, selected);
    a.conversation();
    assert_eq!(a.input, "retain this request draft");
    assert_eq!(a.attachment.as_deref(), Some("/data/context.md"));
    a.conversation();
    a.model_name = Some("fixture".into());
    a.ask();
    assert!(a.pending.is_none() && a.jobs.is_empty());
    assert_eq!(a.input, "retain this request draft");
    a.ask();
    assert_eq!(a.pending.as_ref().unwrap().0, "retain this request draft");
    a.conversation();
    assert_eq!(a.input, "editor");
    cleanup(&a);
}

#[test]
fn details_wait_for_the_work_under_way_and_open_from_the_list_alone() {
    let mut a = app();
    a.apps.pending = Some((9, "launch".into()));
    a.apps_activate(Action::Details(ID.into()));
    assert!(matches!(a.apps.page, Page::List), "a page with no request behind it");
    a.apps.pending = None;
    pick(&mut a, Action::Launch(ID.into()));
    assert!(a.apps_details());
    assert!(matches!(a.apps.page, Page::Details(_)));
    a.apps.pending = None;
    pick(&mut a, Action::Launch(ID.into()));
    assert!(!a.apps_details(), "details on details");
    a.escape();
    assert!(matches!(a.apps.page, Page::List), "one Esc is the list again");
    cleanup(&a);
}

#[test]
fn the_default_launch_chosen_again_changes_nothing() {
    let mut a = app();
    a.apps_activate(Action::SetLaunch(ID.into(), "default".into()));
    assert!(a.reply.is_none() && !a.apps.path.exists(), "nothing changed, nothing said, nothing written");
    cleanup(&a);
}

#[test]
fn space_is_no_key_in_apps_and_ctrl_c_leaves_at_once() {
    let mut a = app();
    pick(&mut a, Action::Launch(ID.into()));
    a.typed(' ');
    assert_eq!(a.apps.page, Page::List, "Space opens nothing here");
    act(&mut a, Action::Details(ID.into()));
    act(&mut a, Action::Visibility(ID.into()));
    a.hint_key(HintKey::Quit);
    assert_eq!(a.quit, Some(130), "nothing to save, nothing to ask");
    cleanup(&a);
}

#[test]
fn typed_undo_takes_the_last_change_of_apps_back_after_its_receipt_is_gone() {
    // Esc clears the receipt and its Undo, as it does everywhere; the word undo, typed in the list or at the home,
    // still takes the change back, as it does a provider's step
    let mut a = app();
    a.set_draft("editor");
    act(&mut a, Action::Details(ID.into()));
    act(&mut a, Action::Visibility(ID.into()));
    assert!(a.apps.preference(ID).hidden);
    a.escape();
    assert_eq!(a.apps.page, Page::List);
    assert!(a.reply.is_none(), "Esc clears the receipt");
    a.set_draft("undo");
    a.enter();
    assert!(!a.apps.preference(ID).hidden, "typed undo in the list");
    assert!(a.input.is_empty(), "the word is taken");
    act(&mut a, Action::Details(ID.into()));
    act(&mut a, Action::Visibility(ID.into()));
    a.escape();
    a.escape();
    a.escape();
    assert_eq!(a.view, View::Home);
    a.set_draft("undo");
    a.enter();
    assert!(!a.apps.preference(ID).hidden, "typed undo at the home");
    cleanup(&a);
}
