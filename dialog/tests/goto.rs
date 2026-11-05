//! The bar's click on a block while home is open: home goes to that block's section (lib/home.py writes
//! the request; the dialog takes it on its tick). A stale or unknown request moves nothing.
use spark_dialog::app::{App, Config, View, CALENDAR_DEST};
use spark_dialog::goto;
use std::time::{Duration, SystemTime};

fn app() -> App {
    App::new(Config::default(), &["notifications".into(), "bt".into(), "clock".into()])
}

#[test]
fn a_request_names_one_section_in_plain_lowercase() {
    assert_eq!(goto::parse("notifications\n").as_deref(), Some("notifications"));
    assert_eq!(goto::parse("  bt ").as_deref(), Some("bt"));
    for bad in ["", "\n", "Notifications", "../x", "bt wifi", "a;b", &"x".repeat(33)] {
        assert_eq!(goto::parse(bad), None, "{:?}", bad);
    }
}

#[test]
fn a_request_is_taken_once_and_a_stale_one_is_dropped() {
    let dir = std::env::temp_dir().join(format!("goto-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("spark-home.goto");
    std::fs::write(&file, "notifications\n").unwrap();
    let now = SystemTime::now();
    assert_eq!(goto::take_at(&file, now).as_deref(), Some("notifications"));
    assert!(!file.exists(), "taken: the file is gone");
    assert_eq!(goto::take_at(&file, now), None, "nothing waits: nothing is taken");
    std::fs::write(&file, "bt\n").unwrap();
    assert_eq!(
        goto::take_at(&file, now + Duration::from_secs(30)),
        None,
        "a request older than ten seconds is stale"
    );
    assert!(!file.exists(), "a stale request is removed too");
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn home_goes_to_the_section_and_esc_comes_back() {
    let mut app = app();
    assert_eq!(app.view, View::Home);
    assert!(app.go_to("notifications"));
    assert_eq!(app.view, View::Section(0));
    assert!(!app.go_to("notifications"), "there already: nothing moves");
    app.escape();
    assert_eq!(app.view, View::Home, "Esc gives back where home was");
}

#[test]
fn the_clock_goes_to_the_calendar_and_an_unknown_name_moves_nothing() {
    let mut app = app();
    assert!(app.go_to("clock"));
    assert_eq!(app.view, View::Dest(CALENDAR_DEST));
    assert!(app.go_to("bt"));
    assert_eq!(app.view, View::Section(1));
    assert!(!app.go_to("wifi"), "no wifi provider here");
    assert_eq!(app.view, View::Section(1));
}

#[test]
fn a_draft_waits_while_home_goes_to_the_section() {
    let mut app = app();
    app.input = "half a thought".into();
    app.cursor = app.input.len();
    assert!(app.go_to("notifications"));
    app.escape();
    assert_eq!(app.view, View::Home);
    assert_eq!(app.input, "half a thought", "the words typed at home are kept");
}
