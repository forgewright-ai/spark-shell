mod common;
use ratatui::{buffer::Buffer, layout::Rect};
use serde_json::json;
use spark_dialog::app::{App, Config, Helper, Item, View};
use spark_dialog::apps::{
    preferences::{Preference, Preferences},
    Action, Navigation, Page,
};
use std::path::PathBuf;

static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
fn app() -> App {
    let mut a = App::new(Config::default(), &[]);
    a.view = View::Apps;
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
        {"id":"org.example.Editor.desktop","name":"EDITOR","generic_name":"Text Editor","description":"Write Documents","categories":["Development","Utility"],"focus":true,"new_window":"new-window","launcher":"/data/Applications/Editor.desktop"},
        {"id":"browser.desktop","name":"Browser","description":"Read the web","categories":["Network"]},
        {"id":"mystery.desktop","name":"Mystery","description":"","categories":["Unknown"]}
    ]})).unwrap();
    a
}
const ID: &str = "org.example.Editor.desktop";
fn act(a: &mut App, action: Action) {
    a.apps_activate(action);
}
fn pick(a: &mut App, action: Action) {
    let n = a
        .picks()
        .iter()
        .position(|x| matches!(x, Item::Apps(l) if l.action.as_ref() == Some(&action)))
        .unwrap();
    a.light(n);
}
fn cleanup(a: &App) {
    let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
}

#[test]
fn browse_uses_short_roles_without_losing_description_search_or_details() {
    let mut a = app();
    let rows = a.apps.lines(60, "", None);
    let editor = rows.iter().find(|l| l.action == Some(Action::Launch(ID.into()))).unwrap();
    assert_eq!(editor.value, "Text Editor");
    assert_eq!(editor.indent, 4);
    assert_eq!(editor.value_x, 24);
    assert!(rows.iter().any(|l| l.label == "all categories"));
    assert!(!rows.iter().any(|l| l.label == "apps" || l.label == "category"));
    let browser = rows.iter().find(|l| l.action == Some(Action::Launch("browser.desktop".into()))).unwrap();
    assert!(browser.value.is_empty(), "missing roles do not fall back to verbose comments");
    assert_eq!(a.apps.visible("text")[0].id, ID, "the displayed role is searchable");
    assert_eq!(a.apps.visible("write documents")[0].id, ID, "full comments remain searchable");
    assert_eq!(a.apps.visible("read the web")[0].id, "browser.desktop");
    a.apps.page = Page::Details(ID.into());
    assert!(a.apps.lines(60, "", None).iter().any(|l| l.label == "Write Documents"));
    cleanup(&a);
}

#[test]
fn helper_defaults_can_be_restored_and_supplied_full_names_remain_searchable() {
    let mut a = app();
    a.apps.pending = Some((7, "catalog".into()));
    a.apps
        .receive(
            7,
            json!({"apps":[
                {"id":"foot.desktop","name":"foot"},
                {"id":"footclient.desktop","name":"foot client"},
                {"id":"foot-server.desktop","name":"foot server"},
                {"id":"firefox.desktop","name":"firefox","display_name":"Mozilla Firefox"}
            ]}),
        )
        .unwrap();
    assert_eq!(a.apps.visible("foot").iter().map(|e| e.id.as_str()).collect::<Vec<_>>(), ["foot.desktop"]);
    assert_eq!(a.apps.visible("mozilla")[0].name, "firefox");
    a.view = View::Home;
    a.set_draft("foot client");
    assert!(!a.picks().iter().any(|it| matches!(it, Item::Apps(_))));
    a.view = View::Apps;
    act(&mut a, Action::Hidden);
    assert_eq!(a.apps.visible("foot").len(), 3);
    act(&mut a, Action::Visibility("footclient.desktop".into()));
    assert!(a.apps.preference("footclient.desktop").hidden, "draft does not restore before save");
    act(&mut a, Action::Save("footclient.desktop".into()));
    a.apps.prefs = Preferences::load(&a.apps.path).unwrap();
    a.apps.show_hidden = false;
    assert_eq!(a.apps.visible("foot").len(), 2, "explicit restore wins over the helper default after restart");
    assert!(a.apps.preference("foot-server.desktop").hidden);
    cleanup(&a);
}

#[test]
fn inline_controls_have_distinct_targets_and_toggles_set_the_clicked_state_after_resize() {
    let mut a = app();
    let pal = common::palette("tokyonight-night");
    for (w, h) in [(60, 40), (140, 50), (36, 20), (68, 49)] {
        a.size = (w, h);
        a.apps.page = Page::List;
        a.in_list = false;
        a.scroll = 0;
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        let filter = d.pick_regions.iter().find(|(_, _, _, n)| *n == 0).unwrap();
        let hidden = d.pick_regions.iter().find(|(_, _, _, n)| *n == 1).unwrap();
        assert_eq!(filter.2 == hidden.2, w >= 54);
        assert_eq!(d.pick_at(filter.0 + 2, filter.2), Some(0));
        assert_eq!(d.pick_at(hidden.0 + 2, hidden.2), Some(1));
        for wanted in [false, true, true, false, false] {
            let &(x, _, y, n, state) = d.app_toggles.iter().find(|(_, _, _, _, state)| *state == wanted).unwrap();
            assert_eq!(d.pick_at(x, y), Some(n));
            a.apps_toggle(n, state);
            assert_eq!(a.apps.show_hidden, wanted);
        }
        a.apps.page = Page::Details(ID.into());
        act(&mut a, Action::Visibility(ID.into()));
        pick(&mut a, Action::Save(ID.into()));
        let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        let save = d
            .pick_regions
            .iter()
            .find(|(_, _, _, n)| matches!(&a.picks()[*n], Item::Apps(l) if l.action == Some(Action::Save(ID.into()))))
            .unwrap();
        let cancel = d
            .pick_regions
            .iter()
            .find(|(_, _, _, n)| matches!(&a.picks()[*n], Item::Apps(l) if l.action == Some(Action::Discard(ID.into()))))
            .unwrap();
        assert_eq!(save.2, cancel.2);
        assert!(save.1 <= cancel.0);
        let n = d.pick_at(cancel.0 + 2, cancel.2).unwrap();
        a.light(n);
        a.enter();
        assert!(!a.apps.dirty(ID));
        assert!(!a.apps.preference(ID).hidden);
    }
    cleanup(&a);
}

#[test]
fn section_spacing_and_colors_have_one_meaning_in_apps_and_details() {
    use ratatui::style::Modifier;
    let mut a = app();
    for page in [Page::List, Page::Details(ID.into()), Page::Categories] {
        a.apps.page = page;
        let lines = a.apps.lines(60, "", None);
        for (i, line) in lines.iter().enumerate().filter(|(_, l)| l.bold && l.action.is_none()) {
            assert_eq!(line.indent, 2);
            assert!(lines[i + 1].label.is_empty() && lines[i + 1].value.is_empty());
        }
    }
    a.apps.page = Page::List;
    for theme in ["tokyonight-night", "solarized-light"] {
        let pal = common::palette(theme);
        let mut b = Buffer::empty(Rect::new(0, 0, 60, 40));
        let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        let filter = d.pick_regions.iter().find(|(_, _, _, n)| *n == 0).unwrap();
        assert_eq!(b[(filter.0 + 2, filter.2)].fg, pal.fg);
        let hide = d.app_toggles.iter().find(|(_, _, _, _, state)| !*state).unwrap();
        assert!(b[(hide.0, hide.2)].modifier.contains(Modifier::UNDERLINED | Modifier::BOLD));
        pick(&mut a, Action::Launch(ID.into()));
        let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        let row = d.picks.iter().find(|(_, n)| *n == a.sel).unwrap().0;
        assert_eq!(b[(4, row)].fg, pal.accent);
        assert_eq!(b[(24, row)].fg, pal.muted);
        a.in_list = false;
    }
    cleanup(&a);
}

#[test]
fn apps_body_and_pointer_bounds_stay_on_the_shared_left_anchor_after_resize() {
    let mut a = app();
    pick(&mut a, Action::Launch(ID.into()));
    let pal = common::palette("tokyonight-night");
    for (w, h) in [(60, 40), (140, 50), (68, 49), (36, 20), (60, 40)] {
        a.size = (w, h);
        let frame_left = (w - w.min(120)) / 2;
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        assert_eq!(d.columns, (frame_left, frame_left + w.min(60)));
        let y = d.picks.iter().find(|(_, n)| *n == a.sel).unwrap().0;
        assert_eq!(b[(frame_left + 2, 0)].symbol(), "a", "apps header");
        assert_eq!(b[(frame_left + 4, y)].symbol(), "e", "selected editor name");
        assert_eq!(b[(frame_left, y)].symbol(), "\u{203a}");
        a.hover = Some((frame_left + 2, y));
        spark_dialog::ui::draw(&a, &pal, "", &mut b);
        assert_eq!(b[(frame_left + 2, y)].bg, pal.lit);
        if w > 60 {
            a.hover = Some((d.columns.1, y));
            spark_dialog::ui::draw(&a, &pal, "", &mut b);
            assert_ne!(b[(d.columns.1, y)].bg, pal.lit, "empty space outside the body is not a row target");
        }
        a.hover = None;
    }
    cleanup(&a);
}

#[test]
fn category_precedence_delete_and_preferences_survive_updates_and_restart() {
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
    a.apps.prefs.mappings.insert("Development".into(), "Writing".into());
    a.apps.prefs.rename("Writing", "Work").unwrap();
    assert_eq!(a.apps.prefs.category(ID, &system), "Work");
    a.apps.prefs.delete("Work").unwrap();
    assert_eq!(a.apps.prefs.category(ID, &system), "Utilities");
    assert!(a.apps.preference(ID).hidden);
    assert_eq!(a.apps.preference(ID).mode(), "focus");
    a.apps.prefs.save(&a.apps.path).unwrap();
    let restored = Preferences::load(&a.apps.path).unwrap();
    assert_eq!(restored, a.apps.prefs);
    a.apps.entries[0].name = "editor updated".into();
    assert!(a.apps.visible("updated").is_empty());
    act(&mut a, Action::Hidden);
    assert_eq!(a.apps.visible("updated").len(), 1);
    act(&mut a, Action::Visibility(ID.into()));
    act(&mut a, Action::Save(ID.into()));
    assert!(!Preferences::load(&a.apps.path).unwrap().apps[ID].hidden);
    assert_eq!(a.apps.preference(ID).mode(), "focus");
    cleanup(&a);
}

#[test]
fn query_crosses_categories_and_hidden_apps_never_leak_into_home_search() {
    let mut a = app();
    a.apps.filter = Some("Web".into());
    assert_eq!(a.apps.visible("")[0].id, "browser.desktop");
    assert_eq!(a.apps.visible("write doc")[0].name, "editor");
    a.apps.prefs.apps.insert(
        ID.into(),
        Preference {
            hidden: true,
            ..Default::default()
        },
    );
    assert!(a.apps.visible("editor").is_empty());
    a.view = View::Home;
    assert!(a.found("editor").is_empty());
    a.apps.show_hidden = true;
    assert!(a.found("editor").is_empty(), "Show hidden applies only to the management view");
    a.apps.prefs.apps.get_mut(ID).unwrap().hidden = false;
    assert!(matches!(&a.found("documents")[0].1, Item::Apps(_)));
    cleanup(&a);
}

#[test]
fn details_back_restores_search_selection_scroll_and_unsaved_preferences() {
    let mut a = app();
    a.set_draft("editor");
    pick(&mut a, Action::Launch(ID.into()));
    a.scroll = 3;
    let sel = a.sel;
    assert!(a.apps_details());
    assert!(a.input.is_empty());
    act(&mut a, Action::Visibility(ID.into()));
    act(&mut a, Action::Technical);
    for size in [(140, 50), (68, 49), (60, 40), (36, 20)] {
        a.size = size;
        let _ = a.items();
        assert!(a.apps.dirty(ID));
        assert!(a.apps.expanded);
    }
    a.escape();
    assert!(a.leave_decision.is_some());
    a.escape(); // dismissing the decision keeps the draft and the form
    assert!(a.apps.dirty(ID));
    assert_eq!(a.apps.page, Page::Details(ID.into()));
    a.escape();
    a.leave_choice(spark_dialog::interaction::Choice::Save);
    assert_eq!(a.apps.page, Page::List);
    assert_eq!((a.input.as_str(), a.sel, a.scroll), ("editor", sel, 3));
    assert!(a.apps.preference(ID).hidden && !a.apps.dirty(ID));
    a.escape();
    assert!(a.input.is_empty());
    assert_eq!(a.view, View::Apps);
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
    pick(&mut a, Action::Launch(ID.into())); // mouse uses this same light + enter pair
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
fn details_values_reflow_and_footer_and_pointer_bounds_follow_current_geometry() {
    let mut a = app();
    a.apps.page = Page::Details(ID.into());
    a.apps.expanded = true;
    a.apps.details.insert(
        ID.into(),
        json!({"version":"1.2","fields":[["Launcher","/data/Applications/A Very Long Folder/OriginalCase.desktop"]]}),
    );
    a.attachment = Some("/data/An attached document.md".into());
    a.cfg.attach = vec!["files".into()];
    a.cfg.model = true;
    a.cfg.talk = true;
    a.model_name = Some("a-very-long-model-name-with-full-identity".into());
    let palette = common::palette("tokyonight-night");
    for (w, h) in [(60, 40), (140, 50), (68, 49), (36, 20), (60, 40)] {
        a.size = (w, h);
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        let d = spark_dialog::ui::draw(&a, &palette, "Tue 3 Nov 12:00", &mut b);
        let frame_left = (w - w.min(120)) / 2;
        assert_eq!(d.columns, (frame_left, frame_left + w.min(60)));
        let footer = d.chips.iter().map(|c| c.2).min().unwrap();
        assert!(d.picks.iter().all(|&(y, _)| y < footer - 2));
        for &(x0, x1, y, _) in &d.chips {
            assert!(x0 < x1 && x0 >= frame_left && x1 <= frame_left + w.min(120) && y < h - 1);
        }
        for (i, &(x0, x1, y, _)) in d.chips.iter().enumerate() {
            assert!(d.chips[..i].iter().all(|&(a, b, r, _)| r != y || x1 <= a || x0 >= b));
        }
        for &(y, n) in &d.picks {
            assert!(matches!(&a.picks()[n], Item::Apps(l) if l.action.is_some()));
            assert!(y >= spark_dialog::ui::CONTENT_Y);
        }
    }
    let lines = a.apps.lines(36, "", None);
    let at = lines.iter().position(|l| l.label == "category").unwrap();
    assert!(lines[at].value.is_empty() && !lines[at + 1].value.is_empty());
    assert_eq!(a.apps.entry(ID).unwrap().launcher, "/data/Applications/Editor.desktop");
    cleanup(&a);
}

#[test]
fn unavailable_catalog_missing_metadata_and_invalid_preferences_are_explicit() {
    let mut a = app();
    a.apps.entries.clear();
    assert!(a.apps.lines(60, "", None).iter().any(|l| l.label.contains("No launchable")));
    a.apps.pending = Some((8, "catalog".into()));
    a.apps.receive(8, json!({"error":"GIO unavailable"})).unwrap_err();
    assert!(a.apps.lines(60, "", None).iter().any(|l| l.label.contains("Apps unavailable")));
    assert!(Preferences::parse("{}").is_err());
    a.apps.preference_error = Some("Invalid preferences".into());
    a.apps.drafts.insert(
        ID.into(),
        Preference {
            hidden: true,
            ..Default::default()
        },
    );
    assert!(a.apps.activate(Action::Save(ID.into()), Navigation::default()).is_err());
    assert!(!PathBuf::from(&a.apps.path).exists());
    cleanup(&a);
}

#[test]
fn configured_details_key_and_hover_use_current_drawn_controls() {
    let mut a = app();
    a.cfg.keys = spark_dialog::keys::Bindings::from_json(r#"{"right":"F4"}"#).unwrap();
    a.set_draft("editor");
    pick(&mut a, Action::Launch(ID.into()));
    let pal = common::palette("tokyonight-night");
    for (w, h) in [(60, 40), (140, 50), (68, 49), (60, 40)] {
        a.size = (w, h);
        let mut b = Buffer::empty(Rect::new(0, 0, w, h));
        let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        let &(left, right, row, _) = d
            .keys
            .iter()
            .find(|(_, _, _, k)| *k == spark_dialog::app::HintKey::Right)
            .expect("Details key remains visible and clickable");
        assert!(left < right && right < d.columns.1 && row <= 5);
        a.hover = Some((left, row));
        b = Buffer::empty(Rect::new(0, 0, w, h));
        let hovered = spark_dialog::ui::draw(&a, &pal, "", &mut b);
        assert_eq!(b[(left, row)].bg, pal.lit);
        assert!(hovered.keys.iter().any(|(_, _, _, key)| *key == spark_dialog::app::HintKey::Right));
        assert!(a.in_list, "hover keeps the app that the Details shortcut will inspect");
        let body_row = hovered.picks.iter().find(|(_, n)| *n == a.sel).unwrap().0;
        assert_ne!(b[(4 + (w - w.min(120)) / 2, body_row)].bg, pal.lit, "only the hovered shortcut is highlighted");
        a.hover = None;
    }
    a.hint_key(spark_dialog::app::HintKey::Right);
    assert_eq!(a.apps.page, Page::Details(ID.into()));
    cleanup(&a);
}

#[test]
fn wrapped_preference_values_stay_visible_and_share_the_labels_hit_target() {
    let mut a = app();
    a.apps.page = Page::Details(ID.into());
    a.size = (36, 20);
    act(&mut a, Action::Visibility(ID.into()));
    pick(&mut a, Action::Visibility(ID.into()));
    let pal = common::palette("tokyonight-night");
    let mut b = Buffer::empty(Rect::new(0, 0, 36, 20));
    let d = spark_dialog::ui::draw(&a, &pal, "", &mut b);
    let rows: Vec<_> = d.picks.iter().filter(|(_, n)| *n == a.sel).collect();
    assert_eq!(rows.len(), 2, "label and wrapped value activate the same preference");
    let value = (0..36).map(|x| b[(x, rows[1].0)].symbol()).collect::<String>();
    assert!(value.contains("hide / unhide"), "{value}");
    a.apps.pending = Some((9, "launch".into()));
    a.apps.receive(9, json!({"error":"launch failed"})).unwrap_err();
    assert!(!a.apps.failed, "a launch failure must not mislabel a valid catalog as unavailable");
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
fn every_line_of_long_technical_metadata_is_reachable_by_page_scrolling() {
    let mut a = app();
    a.apps.page = Page::Details(ID.into());
    a.apps.expanded = true;
    a.size = (36, 20);
    a.apps.details.insert(
        ID.into(),
        json!({"fields":[["Long value",(0..100).map(|n|format!("value-{n:03} ")).collect::<String>()]]}),
    );
    pick(&mut a, Action::Technical);
    let pal = common::palette("tokyonight-night");
    let mut observed = String::new();
    for _ in 0..60 {
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
    a.page(-1);
    assert!(!a.in_list, "scrolling metadata cannot accidentally launch a hidden selection");
    cleanup(&a);
}

#[test]
fn confirmed_launch_gives_the_app_the_screen_but_never_hides_a_newly_refocused_home() {
    let mut a = app();
    a.window_focused = false;
    a.apps.pending = Some((1, "launch".into()));
    a.helper(Helper::Apps(1), Ok(json!({"message":"Opened editor","confirmed":true}).to_string()));
    assert!(a.hidden);
    a.hidden = false;
    a.window_focused = true;
    a.apps.pending = Some((2, "launch".into()));
    a.helper(Helper::Apps(2), Ok(json!({"message":"Opened editor","confirmed":true}).to_string()));
    assert!(!a.hidden, "a user's return to home wins over a delayed receipt");
    a.window_focused = false;
    a.apps.pending = Some((3, "launch".into()));
    a.helper(Helper::Apps(3), Ok(json!({"message":"Launch requested","confirmed":false}).to_string()));
    assert!(!a.hidden, "an unconfirmed launch keeps its receipt visible");
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
    a.ask(); // compose the saved request, never silently submit a catalog filter
    assert!(a.pending.is_none() && a.jobs.is_empty());
    assert_eq!(a.input, "retain this request draft");
    a.ask();
    assert_eq!(a.pending.as_ref().unwrap().0, "retain this request draft");
    a.conversation();
    assert_eq!(a.input, "editor");
    cleanup(&a);
}

#[test]
fn dirty_close_and_navigation_require_a_decision_and_failed_save_keeps_edits() {
    use spark_dialog::interaction::Choice;
    let mut a = app();
    act(&mut a, Action::Details(ID.into()));
    act(&mut a, Action::Visibility(ID.into()));
    a.close_window();
    assert!(a.quit.is_none() && a.leave_decision.is_some());
    a.escape();
    assert!(a.leave_decision.is_none() && a.apps.dirty(ID));
    a.conversation();
    assert_eq!(a.view, View::Apps);
    assert!(a.leave_decision.is_some());
    a.leave_choice(Choice::Keep);
    std::fs::create_dir_all(a.apps.path.parent().unwrap()).unwrap();
    let blocker = a.apps.path.parent().unwrap().join("not-a-directory");
    std::fs::write(&blocker, "block").unwrap();
    a.apps.path = blocker.join("apps.json");
    a.close_window();
    a.leave_choice(Choice::Save);
    assert!(a.quit.is_none() && a.apps.dirty(ID));
    assert_eq!(a.apps.page, Page::Details(ID.into()));
    assert!(a.reply.as_ref().unwrap().text.contains("not saved"));
    a.close_window();
    a.leave_choice(Choice::Discard);
    assert!(a.quit.is_some() && !a.apps.dirty(ID));
    let _ = std::fs::remove_dir_all(blocker.parent().unwrap());
}

#[test]
fn category_form_decision_keeps_field_and_cancel_is_keyboard_accessible() {
    use spark_dialog::interaction::Choice;
    let mut a = app();
    act(&mut a, Action::Categories);
    act(&mut a, Action::AddCategory);
    a.set_draft("Writing");
    a.escape();
    assert!(a.leave_decision.is_some());
    a.text_key('x');
    a.paste("oops");
    a.backspace();
    a.escape();
    assert_eq!(a.input, "Writing");
    assert!(a.apps.form());
    a.conversation();
    assert!(a.leave_decision.is_some());
    a.leave_choice(Choice::Save);
    assert_eq!(a.view, View::Conversation);
    assert!(a.input.is_empty());
    assert!(Preferences::load(&a.apps.path).unwrap().categories.contains(&"Writing".into()));
    a.conversation();
    act(&mut a, Action::AddCategory);
    a.set_draft("Discard me");
    pick(&mut a, Action::CancelForm);
    a.enter();
    assert!(!a.apps.form() && a.input.is_empty());
    assert!(!a.apps.prefs.categories.contains(&"Discard me".into()));
    cleanup(&a);
}

#[test]
fn preference_save_cancel_and_open_slots_do_not_move_and_focus_has_a_marker() {
    let mut a = app();
    act(&mut a, Action::Details(ID.into()));
    let slots = |a: &App| {
        a.items()
            .iter()
            .enumerate()
            .filter_map(|(i, it)| match it {
                Item::Apps(line) if matches!(line.action, Some(Action::Save(_) | Action::Discard(_) | Action::Launch(_))) => Some(i),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    let before = slots(&a);
    act(&mut a, Action::Visibility(ID.into()));
    assert_eq!(slots(&a), before);
    pick(&mut a, Action::Visibility(ID.into()));
    let mut buffer = Buffer::empty(Rect::new(0, 0, 60, 40));
    let drawn = spark_dialog::ui::draw(&a, &common::palette("tokyonight-night"), "", &mut buffer);
    let y = drawn.picks.iter().find(|(_, n)| *n == a.sel).unwrap().0;
    assert_eq!(buffer[(drawn.columns.0, y)].symbol(), "\u{203a}");
    act(&mut a, Action::Discard(ID.into()));
    assert!(!a.apps.dirty(ID));
    assert_eq!(slots(&a), before);
    cleanup(&a);
}

#[test]
fn mapping_changes_wait_for_save_and_use_the_shared_dirty_exit() {
    use spark_dialog::interaction::Choice;
    let mut a = app();
    act(&mut a, Action::Mappings);
    act(&mut a, Action::Mapping("Development".into()));
    act(&mut a, Action::Map("Development".into(), Some("Office".into())));
    assert_ne!(a.apps.prefs.mappings.get("Development").map(String::as_str), Some("Office"));
    a.escape();
    assert!(a.leave_decision.is_some());
    a.leave_choice(Choice::Save);
    assert_eq!(a.apps.page, Page::Mappings);
    assert_eq!(Preferences::load(&a.apps.path).unwrap().mappings["Development"], "Office");
    act(&mut a, Action::Mapping("Development".into()));
    act(&mut a, Action::Map("Development".into(), None));
    a.escape();
    a.leave_choice(Choice::Discard);
    assert_eq!(a.apps.page, Page::Mappings);
    assert_eq!(a.apps.prefs.mappings["Development"], "Office");
    cleanup(&a);
}
