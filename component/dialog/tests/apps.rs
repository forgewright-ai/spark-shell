// Apps, drawn with the dialog's own rows: an app a row under its category's heading, a switch to hide it, a
// choice row with its arrow for its category and its launch, a child list for its technical details, and
// every change applied at once with Undo on the status row. Nothing is a draft, nothing asks before it
// leaves, and no label changes under a moving pointer.
mod common;
use ratatui::{buffer::Buffer, layout::Rect, style::Modifier};
use serde_json::json;
use spark_dialog::app::{App, Config, Found, Helper, HintKey, Item, View};
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
        ("", 4, "editor"),
        "an app's row: no sign before it, its name lowercase, under its heading (the dialog design notes)"
    );
    assert_eq!(
        (editor.value.as_str(), editor.value_x, editor.value_muted),
        ("text editor", 26, true),
        "its role, lowercase, muted, in one column"
    );
    let browser = line(&ls, &Action::Launch("browser.desktop".into()));
    assert_eq!(browser.value, "read the web", "no GenericName: the Comment is the role");
    let mystery = line(&ls, &Action::Launch("mystery.desktop".into()));
    assert!(mystery.value.is_empty(), "neither: nothing invented");
    let narrow = a.apps.lines(36, "", None);
    let browser = line(&narrow, &Action::Launch("browser.desktop".into()));
    assert!(
        browser.value.ends_with('\u{2026}') && browser.value.len() < "read the web".len(),
        "cut with an ellipsis: {:?}",
        browser.value
    );
    assert!(
        !ls.iter().any(|l| l.label.contains("hidden apps:") || l.label == "all categories"),
        "no toolbar above the list"
    );
    let tail: Vec<(&str, &str, &str)> = ls
        .iter()
        .skip_while(|l| l.label != "hidden apps")
        .map(|l| (l.label.as_str(), l.value.as_str(), l.tail.as_str()))
        .collect();
    assert_eq!(
        tail,
        [("hidden apps", "none", ""), ("edit categories", "", "\u{203a}"), ("refresh apps", "", "")],
        "the managing rows at the end, a menu's rows: no filter row, the headings are the filter; nothing hidden, nothing to open (v0.124.4)"
    );
    let at = ls.iter().position(|l| l.label == "hidden apps").unwrap();
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
            assert_eq!(b[(d.columns.0, y)].symbol(), " ", "no cursor glyph: the selection bar is the one signal");
            let label_x = (d.columns.0..d.columns.1).find(|x| b[(*x, y)].symbol() != " ").unwrap();
            let label_x = (label_x..d.columns.1).find(|x| b[(*x, y)].symbol().chars().all(char::is_alphabetic)).unwrap();
            assert_eq!(
                b[(label_x, y)].fg,
                pal.fg,
                "{:?} at {}x{}: the selected row's name in the text color",
                page,
                w,
                h
            );
            assert!(
                !b[(label_x, y)].modifier.contains(Modifier::BOLD),
                "{:?} at {}x{}: no bold on the selected row",
                page,
                w,
                h
            );
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
        // the header is the window's (v0.124.4): back at its left, the title centered, the x at its right; the
        // prompt sign says where the column is
        let head: String = (0..w).map(|x| b[(x, 0)].symbol()).collect();
        assert!(
            head.trim_start().starts_with("\u{2039} back"),
            "back at the window's left at {}x{}: {:?}",
            w,
            h,
            head
        );
        let (ta, _) = d.title.expect("the title's cells");
        assert!(ta > left + 2 && head.contains("apps"), "the title centered at {}x{}: {:?}", w, h, head);
        assert_eq!(b[(w - 3, 0)].symbol(), "\u{d7}", "the x at the window's right at {}x{}", w, h);
        assert_eq!(
            b[(2, spark_dialog::ui::TOP_RULE_Y)].symbol(),
            "\u{2500}",
            "the rule from the window's edge at {}x{}",
            w,
            h
        );
        assert_eq!(b[(left + 2, spark_dialog::ui::PROMPT_Y)].symbol(), "\u{276f}");
        let y = d.picks.iter().find(|(_, n)| *n == a.sel).unwrap().0;
        assert_eq!(
            b[(left + 4, y)].symbol(),
            "e",
            "the lit app's name at the row column, lowercase, with no sign before it"
        );
    }
    cleanup(&a);
}

#[test]
fn the_key_row_is_the_pages_whatever_is_lit_or_typed() {
    let mut a = app();
    let list = words(&a);
    assert_eq!(list, "Back Esc   Details F9", "Esc and the list's own key; Enter has no chip");
    a.light(2);
    assert_eq!(words(&a), list, "a row lit");
    a.set_draft("fire");
    assert_eq!(words(&a), list, "words typed");
    a.set_draft("");
    pick(&mut a, Action::Categories);
    assert_eq!(words(&a), list, "the managing row lit");
    act(&mut a, Action::Details(ID.into()));
    let details = words(&a);
    assert_eq!(details, "Back Esc", "a details page: Esc alone, Enter needs no chip");
    pick(&mut a, Action::Visibility(ID.into()));
    assert_eq!(words(&a), details, "the switch lit");
    pick(&mut a, Action::ChooseCategory(ID.into()));
    assert_eq!(words(&a), details, "a choice lit");
    act(&mut a, Action::Categories);
    act(&mut a, Action::AddCategory);
    assert_eq!(
        words(&a),
        "Cancel Esc   Save Enter",
        "a form waits on Enter for the name typed, so Enter has its chip here"
    );
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
    assert_eq!(
        (r.mark, r.text.as_str(), r.undo),
        (Mark::Done, "editor hidden", true),
        "the receipt names the app as a label, lowercase"
    );
    let sw = line(&lines(&a), &Action::Visibility(ID.into())).clone();
    assert_eq!((sw.sign, sw.value.as_str()), ("dot", "on"));
    let (b, d, _) = draw(&mut a, 60, 40);
    assert!(d.reply_undo.is_some(), "Undo at the status row's right");
    let status: String = (0..60).map(|x| b[(x, 35)].symbol()).collect();
    assert!(
        status.contains("editor hidden") && status.contains(" undo "),
        "undo, a control at the right: {:?}",
        status
    );
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
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("editor in web", true)));
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
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("editor: focus existing", true)));
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
    assert_eq!(words(&a), "All apps Esc   Details F9", "the list's keys, Esc showing all apps again (v0.124.4)");
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
    assert_eq!(
        texts[0], "editor||",
        "the name first, lowercase as a label; the entry's text is in the technical details"
    );
    assert!(ls[0].title && !ls[0].heading, "the subject of the page, in the text color");
    assert!(ls.iter().any(|l| l.muted && l.label == "write documents"), "what it is, muted, lowercase");
    let version = ls.iter().find(|l| l.label == "version").unwrap();
    assert_eq!(
        (version.value.as_str(), version.action.is_none(), version.value_x),
        ("1.2", true, 26),
        "a fact: a label and a value, no action"
    );
    let open = line(&ls, &Action::Launch(ID.into()));
    assert_eq!((open.sign, open.label.as_str()), ("", "open"), "an action row, no sign before it");
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
        // the content's rows at 20 rows: from CONTENT_Y to the status row
        for y in 8..15 {
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
    // an action row stands at the row column like every row: no sign cell before its words (v0.124.3)
    assert!(ls
        .iter()
        .any(|l| l.action == Some(Action::AddCategory) && l.label == "new category" && l.sign.is_empty()));
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
    // the mappings page is its heading and its rows: no note above them, and add mapping at the row column
    let ls = lines(&a);
    assert!(!ls.iter().any(|l| l.muted && l.label.contains("wins")), "no note over the rows (v0.124.3)");
    assert!(ls.iter().any(|l| l.action == Some(Action::AddMapping) && l.sign.is_empty()));
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
fn a_category_moves_up_and_down_at_once_with_undo_and_the_list_follows_its_order() {
    // #233: a category's page has move up and move down; the list of apps shows its groups in that order
    let mut a = app();
    let groups = |a: &App| -> Vec<String> { lines(a).iter().filter(|l| l.heading).map(|l| l.label.clone()).collect() };
    assert_eq!(groups(&a), ["development", "web", "other"]);
    act(&mut a, Action::Categories);
    act(&mut a, Action::Category("Web".into()));
    let ls = lines(&a);
    let up = line(&ls, &Action::MoveCategory("Web".into(), true));
    let down = line(&ls, &Action::MoveCategory("Web".into(), false));
    assert_eq!((up.label.as_str(), up.disabled, up.sign), ("move up", false, ""));
    assert_eq!((down.label.as_str(), down.disabled), ("move down", false));

    // Enter on move up: applied at once, said with Undo, saved; the page and its lit row stay for another press
    assert_eq!(&a.apps.prefs.categories[..3], ["Development", "System", "Web"]);
    pick(&mut a, Action::MoveCategory("Web".into(), true));
    a.enter();
    assert_eq!(&a.apps.prefs.categories[..3], ["Development", "Web", "System"]);
    assert!(matches!(&a.apps.page, Page::Category(c) if c == "Web"), "the page stays: {:?}", a.apps.page);
    assert_eq!(a.reply.as_ref().map(|r| (r.text.as_str(), r.undo)), Some(("web moved up", true)));
    a.enter();
    assert_eq!(&a.apps.prefs.categories[..3], ["Web", "Development", "System"], "Enter again: another place up");
    assert_eq!(
        Preferences::load(&a.apps.path).unwrap().categories,
        a.apps.prefs.categories,
        "kept in apps.json"
    );

    // Undo takes the last move back
    a.undo_now();
    assert_eq!(&a.apps.prefs.categories[..3], ["Development", "Web", "System"]);

    // to the top: the first can go no higher, its move up muted and refused; the list follows the order
    while a.apps.prefs.categories[0] != "Web" {
        act(&mut a, Action::MoveCategory("Web".into(), true));
    }
    let ls = lines(&a);
    assert!(line(&ls, &Action::MoveCategory("Web".into(), true)).disabled);
    assert!(!line(&ls, &Action::MoveCategory("Web".into(), false)).disabled);
    act(&mut a, Action::MoveCategory("Web".into(), true));
    assert!(a.reply.as_ref().is_some_and(|r| r.mark == Mark::Refused), "first already");
    assert_eq!(a.apps.prefs.categories[0], "Web");
    // Other moves like any category, and the last cannot go lower
    act(&mut a, Action::Category("Other".into()));
    assert!(line(&lines(&a), &Action::MoveCategory("Other".into(), false)).disabled);
    a.escape();
    a.escape();
    a.escape();
    assert_eq!(a.apps.page, Page::List);
    assert_eq!(groups(&a), ["web", "development", "other"]);
    cleanup(&a);
}

#[test]
fn a_renamed_category_keeps_its_filter() {
    let mut a = app();
    let name = a.apps.prefs.categories[0].clone();
    act(&mut a, Action::SetFilter(Some(name.clone())));
    assert_eq!(a.subtitle(), "development", "the header says which category is shown");
    act(&mut a, Action::Categories);
    act(&mut a, Action::Category(name.clone()));
    act(&mut a, Action::Rename(name));
    a.set_draft("Renamed");
    act(&mut a, Action::Submit);
    assert_eq!(a.apps.filter.as_deref(), Some("Renamed"));
    cleanup(&a);
}

#[test]
fn a_categorys_rename_stands_lit_and_the_first_letter_replaces_it() {
    let mut a = app();
    let name = a.apps.prefs.categories[0].clone();
    act(&mut a, Action::Categories);
    act(&mut a, Action::Category(name.clone()));
    act(&mut a, Action::Rename(name.clone()));
    assert!(a.name_is_lit() && a.input == name, "the name offered, lit");
    a.typed('R');
    assert_eq!(a.input, "R", "the first letter replaces it whole");
    cleanup(&a);
}

#[test]
fn the_filter_is_the_headings_and_the_query_crosses_categories() {
    // the dialog design notes (v0.124.4): a heading narrows the list to its category; words typed search every category
    let mut a = app();
    a.apps_heading("web");
    assert_eq!(a.apps.page, Page::List, "the list itself narrows: no page opens");
    assert_eq!(a.apps.filter.as_deref(), Some("Web"));
    assert_eq!(a.apps.visible("")[0].id, "browser.desktop");
    assert!(lines(&a).iter().filter(|l| l.heading).count() == 1, "one heading, the category shown");
    assert_eq!(a.apps.visible("write doc")[0].name, "Editor", "words search every category");
    a.apps_heading("web");
    assert!(a.apps.filter.is_none(), "the same heading again shows all");
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
    assert!(lines(&a).iter().any(|l| l.label.contains("no app is installed")));
    a.apps.pending = Some((8, "catalog".into()));
    a.apps.receive(8, json!({"error":"GIO unavailable"})).unwrap_err();
    assert!(lines(&a).iter().any(|l| l.label.contains("could not be read")));
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
        assert!(
            d.chips.iter().all(|c| c.2 == spark_dialog::ui::TOOLS_Y),
            "the prompt's tools on their row: {:?}",
            d.chips
        );
        assert!(
            d.picks.iter().all(|&(y, _)| y < h - spark_dialog::ui::BOTTOM),
            "the list ends above the status row and the key bar"
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
    a.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"actions":"F11"}"#).unwrap();
    pick(&mut a, Action::Launch(ID.into()));
    let (b, d, _) = draw(&mut a, 60, 40);
    let &(left, right, row, _) = d.keys.iter().find(|(_, _, _, k)| *k == HintKey::Actions).expect("the Details key is drawn");
    assert!(left < right && row >= spark_dialog::ui::keys_y(40), "on the key bar at the bottom");
    let chip: String = (left..right).map(|x| b[(x, row)].symbol()).collect();
    assert!(chip.contains("F11"), "{:?}", chip);
    a.hint_key(HintKey::Actions);
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

#[test]
fn a_categorys_heading_is_the_filter_and_the_managing_rows_act_on_one_click() {
    // the dialog design notes (v0.124.4): a click on a heading shows that category alone, the header says which, Esc shows
    // all; the rows at the list's end are a menu's and act on one click; an app's row is selected first
    let mut a = app();
    let t0 = std::time::Instant::now();
    let c = {
        let shown = a.apps.visible("");
        a.apps.category_of(shown[0])
    };
    assert!(lines(&a).iter().filter(|l| l.heading).count() > 1, "more than one category to begin with");
    a.apps_heading(&c.to_lowercase());
    assert_eq!(a.apps.filter.as_deref(), Some(c.as_str()), "the heading's category alone");
    assert_eq!(a.subtitle(), c.to_lowercase(), "the header says which");
    assert_eq!(lines(&a).iter().filter(|l| l.heading).count(), 1);
    let hint: String = a.hint().iter().map(|(t, _)| t.as_str()).collect();
    assert!(hint.contains("All apps"), "Esc shows all, and its chip says so: {:?}", hint);
    a.apps_heading(&c.to_lowercase());
    assert!(a.apps.filter.is_none(), "the same heading again widens to all");
    a.apps_heading(&c.to_lowercase());
    a.escape();
    assert!(
        a.apps.filter.is_none() && a.view == spark_dialog::app::View::Apps,
        "Esc clears the filter, and stays"
    );
    // the managing rows act on one click; an app's row is selected by one
    act(&mut a, Action::Visibility("mystery.desktop".into()));
    let picks = a.picks();
    let hidden = picks
        .iter()
        .position(|it| matches!(it, spark_dialog::app::Item::Apps(l) if l.action == Some(Action::Hidden)))
        .expect("the hidden apps row");
    a.clicked(hidden, t0);
    assert_eq!(a.apps.page, Page::Hidden, "one click opens the hidden list");
    a.escape();
    assert_eq!(a.apps.page, Page::List);
    let picks = a.picks();
    let app_row = picks
        .iter()
        .position(|it| matches!(it, spark_dialog::app::Item::Apps(l) if matches!(l.action, Some(Action::Launch(_)))))
        .expect("an app's row");
    a.clicked(app_row, t0);
    assert!(
        a.in_list && a.sel == app_row && a.apps.page == Page::List && a.apps.pending.is_none(),
        "selected, not opened"
    );
    cleanup(&a);
}

#[test]
fn the_hidden_apps_are_the_lists_own_shape_under_their_categories_and_searched_by_typing() {
    let mut a = app();
    act(&mut a, Action::Visibility(ID.into()));
    act(&mut a, Action::Hidden);
    assert_eq!(a.subtitle(), "hidden", "the header says hidden");
    let ls = lines(&a);
    assert!(
        ls.iter().any(|l| l.heading && l.label == "development"),
        "under its category's heading: {:?}",
        ls.iter().map(|l| l.label.as_str()).collect::<Vec<_>>()
    );
    assert!(ls.iter().any(|l| l.label == "editor"));
    let hint: String = a.hint().iter().map(|(t, _)| t.as_str()).collect();
    assert!(hint.contains("All apps"), "{:?}", hint);
    a.set_draft("zzz");
    assert!(
        lines(&a).iter().any(|l| l.label.contains("no hidden app matches")),
        "typing searches the hidden list"
    );
    a.set_draft("edit");
    assert!(lines(&a).iter().any(|l| l.label == "editor"), "and finds by the words");
    cleanup(&a);
}

#[test]
fn f9_on_an_app_found_from_home_opens_its_details_and_esc_brings_the_words_back() {
    let mut a = app();
    a.view = View::Home;
    a.came_from.clear();
    for c in "editor".chars() {
        a.typed(c);
    }
    pick(&mut a, Action::Launch(ID.into()));
    a.hint_key(HintKey::Actions);
    assert_eq!(a.view, View::Apps);
    assert_eq!(a.apps.page, Page::Details(ID.into()), "F9 is the details, as in Apps");
    assert_eq!(a.input, "", "the words wait at home");
    a.apps.pending = None;
    a.escape();
    assert_eq!(a.apps.page, Page::List, "Esc goes back a page at a time");
    a.escape();
    assert_eq!(a.view, View::Home);
    assert_eq!(a.input, "editor", "the search as it was");
    // the apps at work: home stays, with the words, and says so
    pick(&mut a, Action::Launch(ID.into()));
    a.apps.pending = Some((9, "launch".into()));
    a.hint_key(HintKey::Actions);
    assert_eq!(a.view, View::Home);
    assert_eq!(a.input, "editor");
    assert_eq!(a.reply.as_ref().map(|r| r.text.as_str()), Some("the apps are busy: a moment"));
    a.apps.pending = None;
    // nothing lit: F9 has nothing to open
    a.in_list = false;
    a.hint_key(HintKey::Actions);
    assert_eq!(a.view, View::Home);
    assert_eq!(a.reply.as_ref().map(|r| r.text.as_str()), Some("no actions here"));
    // the rest of a kind, a list of its own: the same door, and back to it
    let found = View::Found(Found::Apps, "editor".into());
    a.set_draft("");
    a.view = found.clone();
    a.came_from.push(View::Home);
    pick(&mut a, Action::Launch(ID.into()));
    a.hint_key(HintKey::Actions);
    assert_eq!(a.apps.page, Page::Details(ID.into()));
    a.apps.pending = None;
    a.escape();
    a.escape();
    assert_eq!(a.view, found);
    cleanup(&a);
}

#[test]
fn right_opens_no_details_and_f9_does() {
    let mut a = app();
    pick(&mut a, Action::Launch(ID.into()));
    a.right();
    assert_eq!(a.apps.page, Page::List, "Right opens nothing outside files");
    a.hint_key(HintKey::Actions);
    assert_eq!(a.apps.page, Page::Details(ID.into()), "F9 is the details");
    a.left();
    assert_eq!(a.apps.page, Page::List, "Left stays back outside files");
    pick(&mut a, Action::Categories);
    a.hint_key(HintKey::Actions);
    assert_eq!(a.reply.as_ref().map(|r| r.text.as_str()), Some("no details here"));
    cleanup(&a);
}

/// The screen's text, a line a row.
fn screen_text(b: &Buffer) -> Vec<String> {
    (0..b.area.height)
        .map(|y| {
            (0..b.area.width)
                .map(|x| b[(x, y)].symbol().to_string())
                .collect::<String>()
                .trim_end()
                .to_string()
        })
        .collect()
}

#[test]
fn up_comes_back_to_the_top_of_the_list_its_first_heading_in_view() {
    // a list longer than the window, scrolled past its last row, then walked back up: the first heading comes back
    // into view on the first row, and the prompt shows the list from its top (v0.129.1)
    let mut a = app();
    let mut apps = vec![];
    for (i, cat) in ["Development", "Network", "Office", "AudioVideo", "Game", "Utility"].iter().enumerate() {
        for k in 0..3 {
            apps.push(json!({"id": format!("app{i}{k}.desktop"), "name": format!("app {i}{k}"), "description": "an app", "categories": [cat]}));
        }
    }
    a.apps.pending = Some((2, "catalog".into()));
    a.apps.receive(2, json!({ "apps": apps })).unwrap();
    let (b, _, _) = draw(&mut a, 60, 24);
    let top = screen_text(&b);
    assert!(top.iter().any(|l| l.trim() == "development"), "the first heading at the start: {top:?}");
    // down from the prompt to the last row, and past it
    a.in_list = false;
    for _ in 0..(a.picks().len() + 3) {
        a.down();
        draw(&mut a, 60, 24);
    }
    // back up to the first row
    while a.sel > 0 {
        a.up();
        draw(&mut a, 60, 24);
    }
    let (b, _, _) = draw(&mut a, 60, 24);
    let at_first = screen_text(&b);
    assert!(
        at_first.iter().any(|l| l.trim() == "development"),
        "on the first row, its heading above it: {at_first:?}"
    );
    // and up once more: the prompt, the list from its top
    a.up();
    assert!(!a.in_list);
    let (b, _, _) = draw(&mut a, 60, 24);
    let at_prompt = screen_text(&b);
    assert!(
        at_prompt.iter().any(|l| l.trim() == "development"),
        "at the prompt, the list from its top: {at_prompt:?}"
    );
    // PageDown at the prompt scrolls the list and lights nothing: the wheel up scrolls it back to its top
    a.page(1);
    let (b, _, _) = draw(&mut a, 60, 24);
    assert!(!screen_text(&b).iter().any(|l| l.trim() == "development"), "PageDown scrolled the heading away");
    for _ in 0..10 {
        a.wheel(-1);
        draw(&mut a, 60, 24);
    }
    assert!(!a.in_list, "the wheel scrolls; it lights nothing at the prompt");
    let (b, _, _) = draw(&mut a, 60, 24);
    let wheeled = screen_text(&b);
    assert!(
        wheeled.iter().any(|l| l.trim() == "development"),
        "the wheel up brings the top back: {wheeled:?}"
    );
    cleanup(&a);
}

/// The app list with icons on (#230): the editor's icon in the adapter's cache, the others with none.
fn app_with_icons() -> App {
    let mut a = app();
    let dir = spark_dialog::apps::icon_dir().expect("a state folder").join("18");
    let file = dir.join("0123abcd.png").to_string_lossy().into_owned();
    a.apps.icons = true;
    a.apps.icon_px = 18;
    a.apps.pending = Some((2, "catalog".into()));
    a.apps
        .receive(2, json!({"apps":[
            {"id":ID,"name":"Editor","generic_name":"Text Editor","categories":["Development"],"icon":file},
            {"id":"browser.desktop","name":"browser","categories":["Network"],"icon":"/etc/passwd"},
            {"id":"firefox.desktop","name":"Firefox","generic_name":"Web Browser","categories":["Network"],"icon":dir.join("../18/x.png").to_string_lossy()},
            {"id":"mystery.desktop","name":"9 Mystery","categories":["Unknown"]}
        ]}))
        .unwrap();
    a
}

#[test]
fn an_apps_icon_comes_from_the_adapters_cache_alone_and_an_app_without_one_wears_its_letter() {
    use spark_dialog::page::Icon;
    let a = app_with_icons();
    let ls = lines(&a);
    let icon = |id: &str| line(&ls, &Action::Launch(id.into())).icon.clone();
    let cached = spark_dialog::apps::icon_dir().unwrap().join("18/0123abcd.png").to_string_lossy().into_owned();
    assert_eq!(icon(ID), Some(Icon::Picture(cached)));
    // a path outside the cache is never read: /etc/passwd, or one that climbs out of it, is no icon
    assert_eq!(icon("browser.desktop"), Some(Icon::Letter('b')));
    assert_eq!(icon("firefox.desktop"), Some(Icon::Letter('f')));
    assert_eq!(icon("mystery.desktop"), Some(Icon::Letter('9')), "the first letter or digit of the name");
    // icons off: no icon, the list as it was
    let mut off = app();
    off.apps.icons = false;
    assert!(lines(&off).iter().all(|l| l.icon.is_none()));
    cleanup(&a);
}

#[test]
fn with_icons_the_apps_breathe_as_dialog_spacing_says_and_single_space_where_the_window_is_short() {
    // #232 and its patch: DIALOG_SPACING groups (the default) gives two rows over a heading and one under it; rows
    // gives a row of air between the apps too; none single spaces; a short window single spaces whatever it says
    use spark_dialog::preferences::Spacing;
    let mut a = app_with_icons();
    fn shape(a: &App, room: usize) -> String {
        a.apps
            .lines_in(60, "", None, room)
            .iter()
            .take_while(|l| l.label != "hidden apps")
            .map(|l| {
                if l.heading {
                    format!("#{}", l.label)
                } else if l.label.is_empty() {
                    "-".into()
                } else {
                    l.label.clone()
                }
            })
            .collect::<Vec<_>>()
            .join(" ")
    }
    assert_eq!(a.apps.spacing, Spacing::Groups, "groups when the config says nothing");
    assert_eq!(shape(&a, 26), "#development - editor - - #web - browser firefox - - #other - 9 mystery -");
    a.apps.spacing = Spacing::Rows;
    assert_eq!(shape(&a, 26), "#development - editor - - #web - browser - firefox - - #other - 9 mystery -");
    a.apps.spacing = Spacing::None;
    assert_eq!(shape(&a, 26), "#development editor - #web browser firefox - #other 9 mystery -");
    for spacing in [Spacing::Groups, Spacing::Rows] {
        a.apps.spacing = spacing;
        assert_eq!(
            shape(&a, spark_dialog::apps::AIRY_ROOM - 1),
            "#development editor - #web browser firefox - #other 9 mystery -",
            "{spacing:?} in a short window"
        );
    }
    cleanup(&a);
}

#[test]
fn an_apps_icon_is_drawn_in_its_rows_two_cells_which_the_buffer_skips_and_its_name_follows() {
    let mut a = app_with_icons();
    a.size = (60, 40);
    let (b, d, pal) = draw(&mut a, 60, 40);
    let text = screen_text(&b);
    let row = text.iter().position(|l| l.contains("editor")).expect("the editor's row");
    assert_eq!(text[row].find("editor"), Some(7), "the name three cells past the icon's: {:?}", text[row]);
    assert_eq!(d.icons.len(), 1, "one picture; the others wear their letter: {:?}", d.icons);
    let icon = &d.icons[0];
    assert_eq!((icon.x, icon.y, icon.lit), (4, row as u16, false));
    for x in 4..6 {
        assert_eq!(b[(x, row as u16)].diff_option, ratatui::buffer::CellDiffOption::Skip, "sixel's cell");
    }
    // a letter tile is text, on the band's color
    let tile = text.iter().position(|l| l.contains("browser")).unwrap() as u16;
    assert_eq!(b[(4, tile)].symbol(), "b");
    assert_eq!(b[(4, tile)].bg, pal.band);
    // the lit row's icon is drawn on the lit ground
    pick(&mut a, Action::Launch(ID.into()));
    let (_, d, _) = draw(&mut a, 60, 40);
    assert!(d.icons[0].lit);
    cleanup(&a);
}

#[test]
fn with_icons_a_catalog_read_asks_for_them_at_the_cells_size() {
    let mut a = app_with_icons();
    a.jobs.clear();
    a.apps_request(json!({"op":"catalog"}));
    let asked = a.jobs.iter().find_map(|j| match j {
        spark_dialog::app::Job::RunInput(Helper::Apps(_), _, input) => Some(input.clone()),
        _ => None,
    });
    let asked: serde_json::Value = serde_json::from_str(&asked.expect("the adapter asked")).unwrap();
    assert_eq!((asked["op"].as_str(), asked["icon_px"].as_u64()), (Some("catalog"), Some(18)));
    // icons off: no size asked
    a.apps.pending = None;
    a.apps.icons = false;
    a.jobs.clear();
    a.apps_request(json!({"op":"catalog"}));
    assert!(a
        .jobs
        .iter()
        .all(|j| !matches!(j, spark_dialog::app::Job::RunInput(_, _, input) if input.contains("icon_px"))));
    cleanup(&a);
}

#[test]
fn in_a_window_wider_than_the_column_an_icon_stands_in_the_column_beside_its_name() {
    // a full screen lays the column in the middle: the icon goes with it, never at the window's left edge
    let mut a = app_with_icons();
    let (b, d, _) = draw(&mut a, 150, 46);
    let text = screen_text(&b);
    let row = text.iter().position(|l| l.contains("editor")).expect("the editor's row");
    let name = text[row].find("editor").unwrap() as u16;
    assert_eq!(d.icons.len(), 1);
    assert_eq!((d.icons[0].x, d.icons[0].y), (name - 3, row as u16), "the icon three cells before the name");
    assert!(d.icons[0].x > 4, "in the column, not at the window's edge");
    for x in d.icons[0].x..d.icons[0].x + 2 {
        assert_eq!(b[(x, row as u16)].diff_option, ratatui::buffer::CellDiffOption::Skip);
    }
    cleanup(&a);
}

#[test]
fn an_app_found_from_home_wears_its_icon_and_the_apps_found_breathe() {
    // the patch after v0.130: a search's apps show their icons as the list of apps does, a row of air between them
    use spark_dialog::page::Icon;
    let mut a = app_with_icons();
    a.view = View::Home;
    a.size = (60, 40);
    a.apps.spacing = spark_dialog::preferences::Spacing::Rows;
    a.set_draft("e");
    let items = a.items();
    let found: Vec<&Line> = items
        .iter()
        .filter_map(|it| match it {
            Item::Apps(l) => Some(l),
            _ => None,
        })
        .collect();
    assert!(found.len() >= 2, "{items:?}");
    assert!(found.iter().all(|l| l.icon.is_some()), "every app found wears its icon");
    let editor = found.iter().find(|l| l.action == Some(Action::Launch(ID.into()))).expect("the editor found");
    assert!(matches!(&editor.icon, Some(Icon::Picture(f)) if f.ends_with("0123abcd.png")));
    assert_eq!(editor.value_x, 29, "the role's column moves as far as the icon takes");
    let first = items.iter().position(|it| matches!(it, Item::Apps(_))).unwrap();
    assert!(
        matches!(items[first + 1], Item::Blank) && matches!(items[first + 2], Item::Apps(_)),
        "a row of air between the apps found: {:?}",
        &items[first..first + 3]
    );
    let (b, d, _) = draw(&mut a, 60, 40);
    let text = screen_text(&b);
    let row = text.iter().position(|l| l.contains("Editor")).expect("the editor's row");
    assert!(
        d.icons
            .iter()
            .any(|i| i.file.ends_with("0123abcd.png") && i.y == row as u16 && i.x + 3 == text[row].find("Editor").unwrap() as u16),
        "its icon drawn three cells before its name: {:?}",
        d.icons
    );
    // groups (the default) or none: the apps found in single rows; a short window: no air; icons off: no icon, no air
    for spacing in [spark_dialog::preferences::Spacing::Groups, spark_dialog::preferences::Spacing::None] {
        a.apps.spacing = spacing;
        let items = a.items();
        let first = items.iter().position(|it| matches!(it, Item::Apps(_))).unwrap();
        assert!(matches!(items[first + 1], Item::Apps(_)), "{spacing:?}: no air");
    }
    a.apps.spacing = spark_dialog::preferences::Spacing::Rows;
    a.size = (60, 20);
    let items = a.items();
    let first = items.iter().position(|it| matches!(it, Item::Apps(_))).unwrap();
    assert!(matches!(items[first + 1], Item::Apps(_)));
    a.size = (60, 40);
    a.apps.icons = false;
    let items = a.items();
    let first = items.iter().position(|it| matches!(it, Item::Apps(_))).unwrap();
    assert!(matches!(&items[first], Item::Apps(l) if l.icon.is_none() && l.value_x == 26));
    assert!(matches!(items[first + 1], Item::Apps(_)));
    cleanup(&a);
}
