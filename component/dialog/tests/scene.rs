// The layout in pixels (scene.rs): home, apps and an app's details beside its list, placed as the sheets of
// 2026-11-20 have them (R1, A1, N1, P1); files in one pane and in two and a file's details beside its list (L1,
// K1, D1); and the places a click acts. The steps are read as they are; where cairo and pango are, they are
// painted too (NATIVE_PNG=DIR keeps the pictures).
mod common;
use serde_json::json;
use spark_dialog::app::{App, Config, HintKey, Provider, View};
use spark_dialog::apps::{preferences::Preferences, Page};
use spark_dialog::draw::{Size, Step};
use spark_dialog::files::{Pane, Peek, Side};
use spark_dialog::palette::Palette;
use spark_dialog::scene::{build, kind, size, Kind, Metrics, PictureAt, Scene, Target};

static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
const M: Metrics = Metrics::SHEET;
const LIT: [u8; 3] = [0x4c, 0x52, 0x5e];
const ACCENT: [u8; 3] = [0x88, 0xc0, 0xd0];

/// Nord as the dialog wears it: the sheets' colors.
fn nord() -> Palette {
    let t = [
        ("HEX_FG", "d8dee9"),
        ("HEX_ACCENT", "88c0d0"),
        ("PANEL_MUTED", "aeb5c2"),
        ("PANEL_BG", "3d434f"),
        ("PANEL_HI", "4c525e"),
        ("HEX_ANSI_1", "bf616a"),
        ("HEX_ANSI_2", "a3be8c"),
    ];
    Palette::from(|k| t.iter().find(|(a, _)| *a == k).map(|(_, v)| v.to_string()))
}

fn home() -> App {
    // as a window of the dialog's own has it: the band is the window's
    let mut a = App::new(
        Config {
            band: false,
            ..Config::default()
        },
        &[],
    );
    a.pixels = true;
    a.pane_fits = true;
    a.window_focused = true;
    a.rest_light();
    a
}

/// Apps with the ten of the sheet, under five categories.
fn apps() -> App {
    let mut a = home();
    a.view = View::Apps;
    a.came_from.push(View::Home);
    (a.in_list, a.sel) = (false, 0);
    a.apps.prefs = Preferences::default();
    a.apps.preference_error = None;
    a.apps.icons = true;
    a.apps.spacing = spark_dialog::preferences::Spacing::Rows;
    a.apps.path = std::env::temp_dir()
        .join(format!(
            "scene-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ))
        .join("apps.json");
    a.apps.pending = Some((1, "catalog".into()));
    let app = |id: &str, name: &str, what: &str, cat: &str| json!({"id": format!("{id}.desktop"), "name": name, "generic_name": what, "description": what, "categories": [cat]});
    a.apps
        .receive(
            1,
            json!({"apps": [
                app("btop", "btop++", "System Monitor", "System"),
                app("foot", "Foot", "Terminal", "System"),
                app("cups", "Manage Printing", "CUPS Web Interface", "System"),
                app("tmux", "tmux", "A shell with panes, sessions and windows", "System"),
                app("chromium", "Chromium", "Web Browser", "Network"),
                app("pyradio", "PyRadio", "Terminal Radio Player", "Network"),
                app("steam", "Steam", "Application for managing and playing games on Steam", "Network"),
                app("aerc", "aerc", "Mail Client", "Office"),
                app("mpv", "mpv Media Player", "Multimedia player", "AudioVideo"),
                app("micro", "Micro", "Text Editor", "Utility"),
            ]}),
        )
        .unwrap();
    a
}

/// The folder the files of these tests are in, and a folder's uri as the files provider writes it.
const HERE: &str = "/data/me/documents/research";

fn folder_uri(path: &str) -> String {
    format!("spark-shell://files/rows/{}", spark_dialog::search::b64(path))
}

/// A folder's rows as the files provider writes them: the folder above, a folder, three files, its summary.
fn research() -> serde_json::Value {
    let steps = json!([
        {"name": "files_app", "said": "open in app"},
        {"name": "files_rename", "ask": ["name"], "said": "rename"},
        {"name": "files_move", "pick": "to", "said": "move to a folder"},
        {"name": "files_copy", "pick": "to", "said": "copy to a folder"},
        {"name": "files_trash", "said": "trash"}
    ]);
    let mut more = vec![
        json!({"name": "files_preview", "said": "view"}),
        json!({"name": "files_attach", "said": "attach"}),
    ];
    more.extend(steps.as_array().unwrap().iter().cloned());
    let kinds = json!({"file": {"tool": {"name": "files_open", "said": "open"}, "more": more}, "dir": {"more": steps}});
    let file = |name: &str, kind: &str, size: &str| json!({"id": format!("files:file:{name}"), "sign": "blank", "text": name, "columns": [size, "today"], "wide": [kind, size, "today 20:44", ""], "kind": "file", "args": {"path": format!("{HERE}/{name}")}, "page": format!("spark-shell://files/preview/{name}")});
    json!({"title": "~/documents/research", "here": HERE, "kinds": kinds, "rows": [
        {"id": "files:up", "sign": "opens", "text": "..", "columns": [], "children": folder_uri("/data/me/documents")},
        {"id": "files:dir:figures", "sign": "opens", "text": "figures", "columns": ["2 items"], "wide": ["folder", "2 items", "", ""], "children": folder_uri("/data/me/documents/research/figures"), "kind": "dir", "args": {"path": format!("{HERE}/figures")}},
        file("a-very-long-file-name-for-the-quarterly-research-summary-2026.txt", "text", "8 B"),
        file("diagram.png", "picture", "1 KB"),
        file("field-notes.pdf", "PDF", "11 KB"),
        {"id": "files:here", "sign": "opens", "text": "this folder \u{b7} 1 folder \u{b7} 3 files \u{b7} 12 KB", "columns": [], "more": [{"name": "files_new_folder", "arguments": {"path": HERE}, "ask": ["name"], "said": "new folder"}]}
    ], "short": []})
}

/// The folder above it, as the other pane shows it.
fn documents() -> serde_json::Value {
    json!({"title": "~/documents", "here": "/data/me/documents", "rows": [
        {"id": "files:up", "sign": "opens", "text": "..", "columns": [], "children": folder_uri("/data/me")},
        {"id": "files:dir:letters", "sign": "opens", "text": "letters", "columns": ["0 items"], "children": folder_uri("/data/me/documents/letters")},
        {"id": "files:dir:research", "sign": "opens", "text": "research", "columns": ["4 items"], "children": folder_uri(HERE)},
        {"id": "files:here", "sign": "opens", "text": "this folder \u{b7} 2 folders", "columns": [], "more": []}
    ], "short": []})
}

/// Files in a folder two under your home, come to from home, nothing lit yet.
fn files() -> App {
    let mut a = home();
    let mut p = Provider::new("files");
    p.title = "your home folder".into();
    p.ready = true;
    a.providers = vec![p];
    a.view = View::Folder(0, folder_uri(HERE));
    a.came_from = vec![View::Home];
    a.folder = Some((0, folder_uri(HERE), spark_dialog::model::rows(&research().to_string()).unwrap()));
    (a.in_list, a.sel) = (false, 0);
    a
}

/// The keys of the key bar, in their order.
fn keys(s: &Scene) -> Vec<HintKey> {
    s.hits
        .iter()
        .filter_map(|h| match &h.target {
            Target::Key(k) => Some(*k),
            _ => None,
        })
        .collect()
}

fn scene(a: &mut App, w: f64, h: f64) -> Scene {
    a.size = size(a, &M, w, h);
    build(a, &nord(), &M, w, h, &[])
}

/// The words drawn, each with its corner, its size and whether it is bold.
fn words(s: &Scene) -> Vec<(String, f64, f64, Size, bool)> {
    s.steps
        .iter()
        .filter_map(|st| match st {
            Step::Text { x, y, text, size, bold, .. } => Some((text.clone(), *x, *y, *size, *bold)),
            _ => None,
        })
        .collect()
}

fn word(s: &Scene, text: &str) -> (f64, f64, Size, bool) {
    words(s)
        .into_iter()
        .find(|(t, ..)| t == text)
        .map(|(_, x, y, size, bold)| (x, y, size, bold))
        .unwrap_or_else(|| panic!("no words {text:?} among {:?}", words(s).iter().map(|w| &w.0).collect::<Vec<_>>()))
}

fn fills(s: &Scene, color: [u8; 3]) -> Vec<(f64, f64, f64, f64)> {
    s.steps
        .iter()
        .filter_map(|st| match st {
            Step::Fill { x, y, w, h, color: c } if *c == color => Some((*x, *y, *w, *h)),
            _ => None,
        })
        .collect()
}

#[test]
fn home_is_nine_rows_of_44_pixels_with_the_first_lit_at_the_empty_line() {
    let mut a = home();
    assert_eq!(kind(&a), Kind::Home);
    let s = scene(&mut a, 600.0, 800.0);
    assert!(s.grid.is_none(), "home is drawn in pixels");
    // R1: a row is 44 pixels, the name at the text's edge with its baseline 28 under the row's top, the state
    // beside it in the smaller text on the same baseline
    assert_eq!(word(&s, "apps"), (48.0, 72.0 + 28.0 - M.up, Size::Main, true), "the lit row's name is bold");
    assert_eq!(word(&s, "files"), (48.0, 116.0 + 28.0 - M.up, Size::Main, false));
    assert_eq!(word(&s, "browse your home"), (200.0, 116.0 + 28.0 - M.sup, Size::Small, false));
    // the second group stands 16 pixels under the first
    assert_eq!(word(&s, "settings").1, 72.0 + 5.0 * 44.0 + 16.0 + 28.0 - M.up);
    assert_eq!(word(&s, "power").1, 72.0 + 8.0 * 44.0 + 16.0 + 28.0 - M.up);
    // the lit row's bar fills the line from the window's edge to its other edge; the line holds the keys, so its
    // rule is the accent's and no line stands under the row's name
    assert!(fills(&s, LIT).contains(&(0.0, 72.0, 600.0, 44.0)), "the bar: {:?}", fills(&s, LIT));
    assert!(fills(&s, ACCENT).contains(&(24.0, 55.0, 552.0, 2.0)), "the line's rule in the accent");
    assert_eq!(fills(&s, ACCENT).len(), 1, "nothing else in the accent is a box: {:?}", fills(&s, ACCENT));
    // the keys: close, open, and the list's
    let keys: Vec<&HintKey> = s
        .hits
        .iter()
        .filter_map(|h| match &h.target {
            Target::Key(k) => Some(k),
            _ => None,
        })
        .collect();
    assert_eq!(keys, [&HintKey::Escape, &HintKey::Enter, &HintKey::Down]);
    assert_eq!(word(&s, "close").2, Size::Small);
    assert!(fills(&s, LIT).contains(&(24.0, 752.0, 552.0, 1.0)), "the keys' rule");
    // a click: the line, a row by the pixel, a key
    assert_eq!(s.hit(100.0, 40.0), Some(&Target::Prompt));
    assert_eq!(s.hit(300.0, 72.0), Some(&Target::Pick(0)));
    assert_eq!(s.hit(300.0, 115.9), Some(&Target::Pick(0)), "the row's last pixel");
    assert_eq!(s.hit(300.0, 116.0), Some(&Target::Pick(1)), "the next row's first");
    assert_eq!(s.hit(300.0, 72.0 + 5.0 * 44.0 + 8.0), None, "the air between the groups takes no click");
    assert_eq!(s.hit(30.0, 781.0), Some(&Target::Key(HintKey::Escape)));
}

#[test]
fn down_hands_the_list_the_keys_and_up_at_the_empty_line_is_the_lines() {
    let mut a = home();
    assert!(a.in_list && !a.list_keys && a.sel == 0, "a row lit, the line holding the keys");
    a.down();
    assert!(a.in_list && a.list_keys && a.sel == 1, "Down: the list's keys, the next row");
    let s = scene(&mut a, 600.0, 800.0);
    // the name of the lit row wears the line, and the line's rule is quiet
    let (x, y, ..) = word(&s, "files");
    assert!(
        fills(&s, ACCENT).contains(&(x, y + M.up + 5.0, 50.0, 2.0)),
        "under the name: {:?}",
        fills(&s, ACCENT)
    );
    assert!(!fills(&s, ACCENT).contains(&(24.0, 55.0, 552.0, 2.0)));
    a.up();
    a.up();
    a.rest_light();
    assert!(
        a.in_list && !a.list_keys && a.sel == 0,
        "above the first row is the line, a row lit at rest again"
    );
    // a letter typed at rest is a letter, and the row follows the words
    a.text_key('z');
    assert_eq!(a.input, "z");
}

#[test]
fn what_home_finds_wears_homes_rows_an_app_with_its_picture() {
    let mut a = apps();
    a.view = View::Home;
    a.came_from.clear();
    a.set_draft("foot");
    assert_eq!(kind(&a), Kind::Home);
    let s = scene(&mut a, 600.0, 800.0);
    assert!(s.grid.is_none(), "the finds are drawn in pixels");
    // the kind's heading, then the app: a row of one line, its picture before its name, what it is beside it
    let (hx, hy, size, bold) = word(&s, "apps");
    assert_eq!((hx, hy, size, bold), (48.0, 72.0 + 24.0 - M.sup, Size::Small, true));
    let (x, y, size, _) = word(&s, "foot");
    assert_eq!((x, y, size), (48.0 + 24.0 + 12.0, 72.0 + 36.0 + 28.0 - M.up, Size::Main));
    assert_eq!(word(&s, "terminal").1, 72.0 + 36.0 + 28.0 - M.sup, "on the name's baseline");
    assert_eq!(s.hit(300.0, 72.0 + 36.0 + 10.0), Some(&Target::Pick(0)));
    let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
}

#[test]
fn the_grid_keeps_its_rows_inside_the_frame_for_a_place_not_drawn_yet() {
    let mut a = home();
    a.view = View::Help;
    a.came_from.push(View::Home);
    (a.in_list, a.sel) = (false, 0);
    assert_eq!(kind(&a), Kind::Grid);
    let s = scene(&mut a, 600.0, 800.0);
    let g = s.grid.expect("help keeps its grid rows");
    // the rows' first text column stands on the frame's edge; the rows are kept inside the body's height, and
    // their lit row's bar has the window's width
    assert_eq!(g.x + 2.0 * M.cw, 24.0);
    // at the window's start size the rows have the 60 columns the grid had there: two panes of files need them
    assert_eq!(g.cols, 60);
    assert!(a.col_w() >= spark_dialog::app::WIDTH, "two panes fit: {}", a.col_w());
    let narrow = scene(&mut a, 420.0, 800.0).grid.unwrap();
    assert_eq!(narrow.cols, 42, "every column that starts inside the window");
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!((g.clip.0, g.clip.2), (0.0, 600.0));
    assert_eq!(
        a.size,
        (g.cols, g.rows + 9),
        "the app counts the rows the body holds, under three of head and over six of foot"
    );
    assert_eq!(a.list_room(), g.rows);
    // where you are: home is a target, the place is where you are
    assert_eq!(word(&s, "home").2, Size::Small);
    assert_eq!(s.hit(30.0, 78.0), Some(&Target::Home));
    assert_eq!(word(&s, "help").0, 24.0 + 7.0 * M.sw, "after home and its bar");
}

#[test]
fn apps_are_rows_of_two_lines_under_their_categories_with_a_count() {
    let mut a = apps();
    assert_eq!(kind(&a), Kind::Apps);
    let s = scene(&mut a, 600.0, 800.0);
    // N1: where you are heads the list, the count at its end
    assert_eq!(word(&s, "home").0, 24.0);
    let (x, _, size, _) = word(&s, "10 apps");
    assert_eq!((x + 7.0 * M.sw, size), (576.0, Size::Small));
    assert!(fills(&s, LIT).contains(&(24.0, 96.0, 552.0, 1.0)), "the rule under it");
    // A1: a category is 36 pixels, an app 52: its name over what it is
    assert_eq!(word(&s, "system"), (48.0, 97.0 + 24.0 - M.sup, Size::Small, true));
    assert_eq!(word(&s, "btop++"), (96.0, 97.0 + 36.0 + 21.0 - M.up, Size::Main, false));
    assert_eq!(word(&s, "system monitor"), (96.0, 97.0 + 36.0 + 42.0 - M.sup, Size::Small, false));
    assert_eq!(word(&s, "foot").1, 97.0 + 36.0 + 52.0 + 21.0 - M.up);
    assert_eq!(word(&s, "web").1, 97.0 + 36.0 + 4.0 * 52.0 + 24.0 - M.sup);
    // a description has the row's width: never cut by a column
    word(&s, "application for managing and playing games on steam");
    // the list runs past its box, and no bar says so: nothing is drawn at its edge, and the fills reach it
    assert!(!fills(&s, LIT).iter().any(|f| f.2 == 3.0), "no scrollbar: {:?}", fills(&s, LIT));
    assert_eq!((s.lists.len(), s.lists[0].at.off), (1, 0.0));
    assert!(s.lists[0].most > 0.0, "it scrolls");
    // a click on a heading shows the category alone; on a row, the row
    assert_eq!(s.hit(60.0, 115.0), Some(&Target::Head("system".into())));
    assert_eq!(s.hit(300.0, 140.0), Some(&Target::Pick(0)));
    // the keys of a list with nothing lit: back and details
    let keys: Vec<&Target> = s.hits.iter().map(|h| &h.target).filter(|t| matches!(t, Target::Key(_))).collect();
    assert_eq!(keys, [&Target::Key(HintKey::Escape), &Target::Key(HintKey::Actions)]);
}

#[test]
fn a_list_keeps_its_place_a_drag_moves_it_and_the_lit_row_comes_into_view_when_it_changes() {
    let mut a = apps();
    let (w, h) = (600.0, 800.0);
    a.size = size(&a, &M, w, h);
    let first = build(&a, &nord(), &M, w, h, &[]);
    let (most, view) = (first.lists[0].most, first.lists[0].h);
    let was = |s: &Scene| vec![s.lists[0].at.clone()];
    // a drag: the list is where the drag left it, clamped by the caller to what it scrolls, and nothing lit
    // pulls it back
    let mut dragged = was(&first);
    dragged[0].off = 100.0;
    let s = build(&a, &nord(), &M, w, h, &dragged);
    assert_eq!(s.lists[0].at.off, 100.0);
    assert_eq!(word(&s, "chromium").1, word(&first, "chromium").1 - 100.0, "every row moved with it");
    // past what it scrolls it stops
    dragged[0].off = most + 500.0;
    assert_eq!(build(&a, &nord(), &M, w, h, &dragged).lists[0].at.off, most);
    // the lit row changes: it comes into view, a part of the next row under it, which says the list goes on
    for _ in 0..10 {
        a.down();
    }
    let s = build(&a, &nord(), &M, w, h, &was(&first));
    let (_, y, ..) = word(&s, "micro");
    let bottom = y + M.up - 21.0 + 52.0;
    assert_eq!(bottom + 24.0, 97.0 + view, "the lit row's foot stands 24 pixels over the box's: {y}");
    assert!(s.lists[0].at.off > 0.0);
    // the row lit moves up inside what is in view: the list stands still
    let kept = s.lists[0].at.off;
    a.up();
    let s2 = build(&a, &nord(), &M, w, h, &was(&s));
    assert_eq!(s2.lists[0].at.off, kept, "no jump while the lit row is in view");
    // the last row has nothing after it: it stands at the box's foot, the list at its end
    for _ in 0..12 {
        a.down();
    }
    let s3 = build(&a, &nord(), &M, w, h, &was(&s2));
    assert_eq!(s3.lists[0].at.off, most);
    // another list (words typed) starts from its top
    a.set_draft("mpv");
    let s4 = build(&a, &nord(), &M, w, h, &was(&s3));
    assert_eq!(s4.lists[0].at.off, 0.0);
    let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
}

#[test]
fn right_goes_in_a_level_and_left_goes_back_one() {
    // home's row lit at the empty line: Right opens the place, Left comes back
    let mut a = home();
    a.right();
    assert_eq!(a.view, View::Apps, "Right on a place opens it");
    a.left();
    assert_eq!(a.view, View::Home, "Left goes back a level");
    // an app lit in the list: Right shows its details, never opens the app; Left is the list again
    let mut a = apps();
    a.down();
    a.down();
    a.right();
    assert_eq!(a.apps.page, Page::Details("foot.desktop".into()), "the details are the level under an app");
    let (serial, op) = a.apps.pending.clone().expect("its facts are asked for");
    assert_eq!(op, "details", "the app is not opened");
    a.apps
        .receive(
            serial,
            json!({"id": "foot.desktop", "version": "1.28.0_1", "installed": "XBPS / System", "source": "XBPS", "fields": []}),
        )
        .unwrap();
    // on the details, open acts: Right leaves it alone; a row with an arrow opens its page
    a.right();
    assert_eq!(a.apps.page, Page::Details("foot.desktop".into()), "Right on a row that acts does nothing");
    a.down();
    a.right();
    assert_eq!(a.apps.page, Page::Technical("foot.desktop".into()), "technical details has an arrow: a level");
    a.left();
    a.left();
    assert!(a.apps.page == Page::List && !a.apps.pane, "two levels back: the list");
    // words typed: the arrows are the line's
    a.set_draft("fo");
    a.right();
    assert!(a.apps.page == Page::List && a.view == View::Apps);
    let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
}

#[test]
fn the_app_spacing_setting_sets_an_apps_row() {
    use spark_dialog::preferences::Spacing;
    let mut a = apps();
    for (spacing, h) in [(Spacing::None, 40.0), (Spacing::Groups, 46.0), (Spacing::Rows, 52.0)] {
        a.apps.spacing = spacing;
        let s = scene(&mut a, 600.0, 800.0);
        assert_eq!(word(&s, "foot").1 - word(&s, "btop++").1, h, "{spacing:?}");
    }
}

#[test]
fn an_apps_details_stand_beside_the_list_and_tab_goes_between_them() {
    let mut a = apps();
    a.down();
    a.down();
    assert!(a.in_list && a.sel == 1, "foot is lit");
    assert!(a.apps_details(), "the details key");
    let (serial, _) = a.apps.pending.clone().expect("its facts are asked for");
    a.apps
        .receive(
            serial,
            json!({"id": "foot.desktop", "version": "1.28.0_1", "installed": "XBPS / System", "source": "XBPS", "fields": []}),
        )
        .unwrap();
    assert!(a.apps.pane && a.apps.page == Page::Details("foot.desktop".into()));
    assert!(a.in_list && a.list_keys && a.sel == 0, "the keys on the details' first row");
    let s = scene(&mut a, 600.0, 800.0);
    // P1: the list a column of names with foot lit, its bar from the window's edge to the line between; the details
    // at the right
    assert!(
        fills(&s, LIT).contains(&(0.0, 97.0 + 36.0 + 52.0, 280.0, 52.0)),
        "foot lit in the list: {:?}",
        fills(&s, LIT)
    );
    assert!(fills(&s, LIT).iter().any(|f| f.0 == 280.0 && f.2 == 1.0), "the line between them");
    // where you are is the list still, with its count
    assert_eq!(word(&s, "apps").2, Size::Small);
    word(&s, "10 apps");
    let foots: Vec<_> = words(&s).into_iter().filter(|w| w.0 == "foot").collect();
    assert!(
        foots.iter().any(|w| w.1 == 96.0) && foots.iter().any(|w| w.1 > 296.0 && w.4),
        "its name in the list and, bold, over its details"
    );
    let (x, y, _, bold) = word(&s, "open");
    assert!(x > 296.0 && bold, "open is the lit row of the details");
    assert!(
        fills(&s, ACCENT).contains(&(x, y + M.up + 5.0, 40.0, 2.0)),
        "and wears the line: the details hold the keys"
    );
    // a click on another app in the list shows that app's details; on a details row, the row
    assert_eq!(s.hit(100.0, 97.0 + 36.0 + 10.0), Some(&Target::ListApp("btop.desktop".into())));
    assert_eq!(s.hit(400.0, y + 8.0), Some(&Target::Pick(0)));
    let keys: Vec<&Target> = s.hits.iter().map(|h| &h.target).filter(|t| matches!(t, Target::Key(_))).collect();
    assert_eq!(
        keys,
        [&Target::Key(HintKey::Escape), &Target::Key(HintKey::Enter), &Target::Key(HintKey::Tab)],
        "back to list, open, list"
    );
    // a list come back to with its row lit holds the keys though no key lit it: the row wears the line
    let mut back = apps();
    (back.in_list, back.sel, back.list_keys) = (true, 1, false);
    let s2 = scene(&mut back, 600.0, 800.0);
    let (fx, fy, ..) = word(&s2, "foot");
    assert!(
        fills(&s2, ACCENT).contains(&(fx, fy + M.up + 4.0, 40.0, 2.0)),
        "under foot: {:?}",
        fills(&s2, ACCENT)
    );
    assert!(!fills(&s2, ACCENT).contains(&(24.0, 55.0, 552.0, 2.0)), "and the line's rule is quiet");
    let _ = std::fs::remove_dir_all(back.apps.path.parent().unwrap());
    // Tab: the list holds the keys, the details stay and follow the lit app
    a.tab(false);
    assert!(a.apps.pane && a.apps.page == Page::List && a.in_list && a.sel == 1 && a.list_keys);
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!(s.hit(100.0, 97.0 + 36.0 + 10.0), Some(&Target::Pick(0)), "the list's rows are picks again");
    assert!(
        matches!(s.hit(400.0, y + 8.0), Some(Target::PaneRow(0))),
        "a click on a details row takes the keys there"
    );
    a.up();
    a.apps_follow();
    assert_eq!(a.apps.asked.as_deref(), Some("btop.desktop"), "the lit app's details are asked for, once");
    a.apps.pending = None;
    // Tab again: the details, with the keys
    a.tab(false);
    assert_eq!(a.apps.page, Page::Details("btop.desktop".into()));
    a.apps.pending = None;
    // Esc: back to the list, the details closed
    a.escape();
    assert!(a.apps.page == Page::List && !a.apps.pane);
    // a window too narrow for both shows the details as a page
    a.down();
    a.pane_fits = false;
    assert!(a.apps_details() && !a.apps.pane);
    let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
}

#[test]
fn a_larger_text_grows_every_length() {
    let mut a = home();
    let big = Metrics {
        cw: 15.0,
        ch: 30.0,
        up: 24.0,
        sw: 12.0,
        sh: 24.0,
        sup: 19.0,
    };
    a.size = size(&a, &big, 900.0, 1200.0);
    let s = build(&a, &nord(), &big, 900.0, 1200.0, &[]);
    assert_eq!(word(&s, "apps"), (72.0, 108.0 + 42.0 - 24.0, Size::Main, true));
    assert!(fills(&s, LIT).contains(&(0.0, 108.0, 900.0, 66.0)));
}

/// The scenes painted, where cairo and pango are: nothing asserted of the pixels but that the painter takes the
/// steps; NATIVE_PNG=DIR keeps the pictures for a look.
#[cfg(target_os = "linux")]
#[test]
fn files_are_rows_of_44_pixels_the_name_leading_its_size_and_its_date_beside_it() {
    let mut a = files();
    assert_eq!(kind(&a), Kind::Files);
    let s = scene(&mut a, 600.0, 800.0);
    assert!(s.grid.is_none(), "files are drawn in pixels");
    // L1: a row is 44 pixels, the name at the text's edge; a folder's name ends in a slash
    assert_eq!(word(&s, ".."), (48.0, 97.0 + 28.0 - M.up, Size::Main, false));
    let (x, y, size, _) = word(&s, "figures");
    assert_eq!((x, y, size), (48.0, 97.0 + 44.0 + 28.0 - M.up, Size::Main));
    assert!(
        words(&s).iter().any(|w| w.0 == "/" && (w.1, w.2, w.3) == (48.0 + 7.0 * M.cw, y, Size::Main)),
        "the slash after the folder's name"
    );
    // the size and the date in the smaller text, each on its right edge: the date at the frame's, the size
    // 86 pixels before it, the names the rest
    let small = 97.0 + 44.0 + 28.0 - M.sup;
    assert_eq!(word(&s, "2 items"), (490.0 - 7.0 * M.sw, small, Size::Small, false));
    assert_eq!(word(&s, "1 KB"), (490.0 - 4.0 * M.sw, small + 2.0 * 44.0, Size::Small, false));
    let dates: Vec<_> = words(&s).into_iter().filter(|w| w.0 == "today").collect();
    assert_eq!(dates.len(), 3, "a date beside each file, none beside a folder");
    assert!(dates.iter().all(|w| w.1 == 576.0 - 5.0 * M.sw && w.3 == Size::Small));
    // a name longer than its column is cut in its middle: its type stays
    let long = words(&s).into_iter().find(|w| w.0.starts_with("a-very-long")).expect("the long name");
    assert!(long.0.contains('\u{2026}') && long.0.ends_with("2026.txt"), "{}", long.0);
    assert_eq!(long.0.chars().count(), 36, "the 378 pixels of the names, less their air");
    // the folder's summary is no row: what it counts stands where you are, at the line's end
    assert!(!words(&s).iter().any(|w| w.0.starts_with("this folder")));
    assert_eq!(word(&s, "4 items \u{b7} 12 KB"), (576.0 - 15.0 * M.sw, 82.0 - M.sup, Size::Small, false));
    // where you are: home, the place, each folder from your home down; all but the last go there
    assert_eq!(s.hit(30.0, 78.0), Some(&Target::Home));
    assert_eq!(s.hit(80.0, 78.0), Some(&Target::Crumb(folder_uri("/data/me"))), "files: your home");
    assert_eq!(s.hit(150.0, 78.0), Some(&Target::Crumb(folder_uri("/data/me/documents"))));
    assert_eq!(s.hit(230.0, 78.0), None, "research is where you are");
    // K1: back, view and details; open once a row is lit
    assert_eq!(keys(&s), [HintKey::Escape, HintKey::View, HintKey::Actions]);
    assert_eq!(s.hit(300.0, 97.0 + 44.0 + 10.0), Some(&Target::Pick(1)));
    a.down();
    a.down();
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!(keys(&s), [HintKey::Escape, HintKey::Enter, HintKey::View, HintKey::Actions]);
    // the lit row's bar from the window's edge to its other edge, its name bold with the line under it
    assert!(fills(&s, LIT).contains(&(0.0, 97.0 + 44.0, 600.0, 44.0)), "{:?}", fills(&s, LIT));
    assert!(word(&s, "figures").3, "the lit name is bold");
    assert!(fills(&s, ACCENT).contains(&(48.0, y + M.up + 5.0, 70.0, 2.0)), "{:?}", fills(&s, ACCENT));
    // the lit file's line is no message: its row says it
    assert!(!words(&s).iter().any(|w| w.0.starts_with("figures \u{b7}")));
    // the app counts the rows the body holds
    assert_eq!(a.list_room(), ((752.0 - 97.0) / 44.0) as u16);
}

#[test]
fn a_wide_window_keeps_a_files_size_and_date_beside_its_name() {
    let mut a = files();
    let s = scene(&mut a, 1920.0, 1080.0);
    // the names take 420 pixels at most: the size and the date stand after them, never across the window
    assert_eq!(word(&s, "2 items").0, 48.0 + 420.0 + 64.0 - 7.0 * M.sw);
    assert!(words(&s).iter().filter(|w| w.0 == "today").all(|w| w.1 == 48.0 + 420.0 + 150.0 - 5.0 * M.sw));
    let long = words(&s).into_iter().find(|w| w.0.starts_with("a-very-long")).expect("the long name");
    assert_eq!(long.0.chars().count(), 40, "cut to its column still");
}

#[test]
fn two_panes_of_files_stand_side_by_side_each_under_its_folder() {
    let mut a = files();
    a.files.other = Some(Pane {
        uri: folder_uri("/data/me/documents"),
        rows: spark_dialog::model::rows(&documents().to_string()),
        came_from: vec![View::Home],
        ..Pane::default()
    });
    a.files.other_side = Side::Right;
    (a.in_list, a.sel, a.list_keys) = (true, 1, true);
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!(kind(&a), Kind::Files);
    assert!(a.panes_drawn() && s.grid.is_none());
    // each pane under its folder: bright over the one that holds the keys, muted over the other
    assert_eq!(word(&s, "~/documents/research"), (48.0, 97.0 + 24.0 - M.sup, Size::Small, true));
    assert_eq!(word(&s, "~/documents"), (324.0, 97.0 + 24.0 - M.sup, Size::Small, false));
    // the rows 40 pixels under the frame's rule; a pane has the room for the size alone
    let dots: Vec<_> = words(&s).into_iter().filter(|w| w.0 == "..").collect();
    assert_eq!(dots.len(), 2);
    assert!(dots.iter().all(|w| w.2 == 137.0 + 28.0 - M.up) && dots[0].1 == 48.0 && dots[1].1 == 324.0);
    assert_eq!(
        word(&s, "2 items").0,
        288.0 - 7.0 * M.sw,
        "the left pane's sizes end 12 pixels before the line between"
    );
    assert_eq!(word(&s, "4 items").0, 576.0 - 7.0 * M.sw, "the right pane's at the frame's edge");
    assert!(!words(&s).iter().any(|w| w.0 == "today"), "no date in a pane this narrow");
    // the lit row's bar ends at the line between the panes; the other pane has none
    assert!(fills(&s, LIT).contains(&(0.0, 137.0 + 44.0, 300.0, 44.0)), "{:?}", fills(&s, LIT));
    assert!(fills(&s, LIT).iter().any(|f| f.0 == 300.0 && f.2 == 1.0), "the line between them");
    assert_eq!(fills(&s, LIT).iter().filter(|f| f.3 == 44.0).count(), 1);
    // a click: a row of this pane, a row of the other, the other pane off its rows
    assert_eq!(s.hit(150.0, 137.0 + 10.0), Some(&Target::Pick(0)));
    assert_eq!(s.hit(450.0, 137.0 + 44.0 + 10.0), Some(&Target::OtherRow(1)));
    assert_eq!(s.hit(450.0, 600.0), Some(&Target::OtherPane));
    assert_eq!(s.hit(450.0, 110.0), Some(&Target::OtherPane), "its folder's name too");
    // the keys say Tab is the other pane
    assert_eq!(keys(&s), [HintKey::Escape, HintKey::Enter, HintKey::View, HintKey::Actions, HintKey::Tab]);
    a.tab(false);
    assert_eq!(a.files.other_side, Side::Left, "Tab: the right pane holds the keys");
    let s = scene(&mut a, 600.0, 800.0);
    assert!(word(&s, "~/documents").3 && !word(&s, "~/documents/research").3);
    assert_eq!(s.hit(150.0, 137.0 + 10.0), Some(&Target::OtherRow(0)), "the left pane is the other one now");
}

#[test]
fn a_files_details_stand_beside_the_list_follow_the_lit_file_and_tab_goes_between_them() {
    let mut a = files();
    (a.in_list, a.sel, a.list_keys) = (true, 3, true); // diagram.png
    a.hint_key(HintKey::Actions);
    assert!(a.files.pane && a.files_page_open(), "F9: the details, beside the list, with the keys");
    assert!(a.in_list && a.sel == 0, "on their first row");
    // what the file shows is asked of its provider; with none to ask the details say so
    a.files_follow();
    assert_eq!(a.files.peek.as_ref().map(|p| p.uri.as_str()), Some("spark-shell://files/preview/diagram.png"));
    let s = scene(&mut a, 600.0, 800.0);
    word(&s, "nothing to show");
    assert!(s.pictures.is_empty());
    // its page came: a picture, and what the row does not say of it
    a.files.peek = Some(Peek {
        uri: "spark-shell://files/preview/diagram.png".into(),
        page: Some(spark_dialog::preview::Page {
            picture: Some("/run/pages/diagram.png".into()),
            facts: vec!["1 KB".into(), "today".into(), "640 \u{d7} 400".into()],
            ..Default::default()
        }),
    });
    let s = scene(&mut a, 600.0, 800.0);
    // D1: the list a column of names with the file lit, its bar to the line between; the details a third of the
    // window, 280 pixels at least
    assert!(fills(&s, LIT).contains(&(0.0, 97.0 + 3.0 * 44.0, 280.0, 44.0)), "{:?}", fills(&s, LIT));
    assert!(fills(&s, LIT).iter().any(|f| f.0 == 280.0 && f.2 == 1.0), "the line between them");
    assert!(!words(&s).iter().any(|w| w.0 == "today" || w.0 == "2 items"), "names alone in the list");
    // what it shows, in a box of one height whatever the file; then its name, its facts, what you do with it
    let shown = PictureAt {
        x: 296.0,
        y: 97.0 + 16.0,
        w: 280.0,
        h: 175.0,
        file: "/run/pages/diagram.png".into(),
        wave: None,
    };
    assert_eq!(s.pictures, [shown]);
    assert!(fills(&s, LIT).contains(&(296.0, 113.0, 280.0, 175.0)), "the box's ground");
    let names: Vec<_> = words(&s).into_iter().filter(|w| w.0 == "diagram.png").collect();
    assert!(
        names.iter().any(|w| w.1 == 48.0) && names.iter().any(|w| w.1 == 308.0 && w.4),
        "in the list and, bold, over its details"
    );
    assert_eq!(word(&s, "kind").2, Size::Small);
    let (kx, ..) = word(&s, "picture \u{b7} 640 \u{d7} 400");
    assert_eq!(kx, 564.0 - 19.0 * M.sw, "what the page adds to the row's kind, at the row's end");
    word(&s, "today 20:44");
    assert!(!words(&s).iter().any(|w| w.0.contains("1 KB \u{b7}")), "what the row says already is said once");
    let (x, y, _, bold) = word(&s, "open");
    assert!(x == 308.0 && bold, "open is the lit row of the details");
    assert!(fills(&s, ACCENT).contains(&(x, y + M.up + 5.0, 40.0, 2.0)), "and wears the line");
    word(&s, "rename");
    // the folder's own rows end the list, the second pane's with its key: a taller window shows them
    let tall = scene(&mut a, 600.0, 1100.0);
    word(&tall, "new folder");
    word(&tall, "second pane");
    word(&tall, "Ctrl+Tab");
    // a click on a row of the details is that row; on a row of the list, the list's, which takes the keys
    assert_eq!(s.hit(400.0, y + 8.0), Some(&Target::Pick(0)));
    assert_eq!(s.hit(100.0, 97.0 + 44.0 + 10.0), Some(&Target::ListRow(1)));
    assert_eq!(keys(&s), [HintKey::Escape, HintKey::Enter, HintKey::Tab], "back to list, open, list");
    // where you are is the folder still, with what it holds
    word(&s, "4 items \u{b7} 12 KB");
    assert_eq!(s.hit(150.0, 78.0), Some(&Target::Crumb(folder_uri("/data/me/documents"))));
    // a folder's name there goes to that folder from the details too: they give the keys back first
    let mut gone = files();
    (gone.in_list, gone.sel, gone.list_keys) = (true, 3, true);
    gone.hint_key(HintKey::Actions);
    gone.files_go_to(&folder_uri("/data/me/documents"));
    assert!(
        matches!(&gone.view, View::Folder(_, u) if *u == folder_uri("/data/me/documents")),
        "{:?}",
        gone.view
    );
    assert!(!gone.files_page_open() && gone.files.pane, "the details stay open for the folder come to");
    // and back through the folders you came by, where the folder is one of them
    let mut back = files();
    back.came_from = vec![View::Home, View::Folder(0, folder_uri("/data/me/documents"))];
    (back.in_list, back.sel, back.list_keys) = (true, 3, true);
    back.hint_key(HintKey::Actions);
    back.files_go_to(&folder_uri("/data/me/documents"));
    assert!(
        matches!(&back.view, View::Folder(_, u) if *u == folder_uri("/data/me/documents")),
        "{:?}",
        back.view
    );
    assert_eq!(back.came_from, [View::Home], "back, not deeper: Esc goes home from there");
    assert!(back.files.pane, "the details open still");
    // Tab: the list holds the keys, the details stay and follow the lit file
    a.tab(false);
    assert!(a.files.pane && !a.files_page_open() && a.in_list && a.sel == 3 && a.list_keys);
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!(s.hit(100.0, 97.0 + 44.0 + 10.0), Some(&Target::Pick(1)), "the list's rows are picks again");
    assert!(
        matches!(s.hit(400.0, y + 8.0), Some(Target::PaneRow(0))),
        "a click on a details row takes the keys there"
    );
    assert_eq!(
        keys(&s),
        [HintKey::Escape, HintKey::Enter, HintKey::View, HintKey::Tab],
        "close details, open, view, details"
    );
    a.down();
    a.files_follow();
    assert_eq!(
        a.files.peek.as_ref().map(|p| p.uri.as_str()),
        Some("spark-shell://files/preview/field-notes.pdf")
    );
    let s = scene(&mut a, 600.0, 800.0);
    assert!(
        words(&s).iter().any(|w| w.0 == "field-notes.pdf" && w.1 == 308.0 && w.4),
        "the details are the lit file's"
    );
    // a text shows its first lines, a sound its picture with the waveform's height in it
    a.files.peek = Some(Peek {
        uri: "spark-shell://files/preview/field-notes.pdf".into(),
        page: Some(spark_dialog::preview::Page {
            lines: vec!["FIELD NOTES".into(), "research / 01".into()],
            ..Default::default()
        }),
    });
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!(word(&s, "FIELD NOTES"), (308.0, 113.0 + 8.0, Size::Small, false));
    a.files.peek = Some(Peek {
        uri: "spark-shell://files/preview/field-notes.pdf".into(),
        page: Some(spark_dialog::preview::Page {
            sound: Some(("/run/pages/a-sound.png".into(), 160)),
            seconds: 63.0,
            ..Default::default()
        }),
    });
    let s = scene(&mut a, 600.0, 800.0);
    assert_eq!(
        s.pictures.first().map(|p| (p.file.as_str(), p.wave)),
        Some(("/run/pages/a-sound.png", Some(160)))
    );
    word(&s, "PDF \u{b7} 1:03");
    // Tab again: the details, with the keys; Esc: back to the list, the details closed
    a.tab(false);
    assert!(a.files_page_open() && a.subtitle() == "field-notes.pdf");
    a.escape();
    assert!(!a.files_page_open() && !a.files.pane && a.in_list && a.sel == 4);
    // Right on a file is its details too, and Left goes back
    a.right();
    assert!(a.files_page_open() && a.files.pane);
    a.left();
    assert!(!a.files_page_open() && !a.files.pane);
    // a window too narrow for both shows the details as a page of their own
    a.pane_fits = false;
    a.hint_key(HintKey::Actions);
    assert!(a.files_page_open() && !a.files.pane);
    let s = scene(&mut a, 480.0, 800.0);
    assert_eq!(kind(&a), Kind::Files);
    assert!(
        words(&s).iter().any(|w| w.0 == "field-notes.pdf" && w.1 == 48.0 && w.4),
        "the file's name over its page"
    );
    assert!(!words(&s).iter().any(|w| w.0 == "diagram.png"), "the list gave way");
    assert_eq!(keys(&s), [HintKey::Escape], "back");
}

#[test]
fn the_wheel_moves_the_lit_row_a_row_a_notch_and_the_list_follows() {
    // a list of files: a notch down lights the first row, the next ones move the bar, a notch up moves it back
    let mut a = files();
    a.wheel(1);
    assert!(a.in_list && a.sel == 0, "a notch down lights the first row");
    a.wheel(1);
    a.wheel(1);
    assert_eq!(a.sel, 2);
    a.wheel(-1);
    assert_eq!(a.sel, 1);
    let s = scene(&mut a, 600.0, 800.0);
    assert!(
        fills(&s, LIT).contains(&(0.0, 97.0 + 44.0, 600.0, 44.0)),
        "the bar is on the row the wheel chose"
    );
    // a list longer than the window: the wheel walks to its last app, and the list has followed the bar there
    let mut long = apps();
    for _ in 0..40 {
        long.wheel(1);
    }
    let s = scene(&mut long, 600.0, 500.0);
    let list = &s.lists[0];
    assert!(list.at.off > 0.0, "the list scrolled with its lit row: {:?}", list.at);
    let lit: Vec<_> = fills(&s, LIT).into_iter().filter(|f| f.0 == 0.0 && f.2 == 600.0 && f.3 > 30.0).collect();
    assert_eq!(lit.len(), 1, "one lit row: {lit:?}");
    assert!(
        lit[0].1 >= list.y && lit[0].1 + lit[0].3 <= list.y + list.h,
        "and it is in view: {lit:?} in {list:?}"
    );
    let _ = std::fs::remove_dir_all(long.apps.path.parent().unwrap());
    // an app's details are rows in the layout in pixels: the wheel moves their lit row too, and keeps one lit
    let mut d = apps();
    d.down();
    d.down();
    assert!(d.apps_details());
    let (serial, _) = d.apps.pending.clone().expect("its facts are asked for");
    d.apps
        .receive(
            serial,
            json!({"id": "foot.desktop", "version": "1.28.0_1", "installed": "XBPS / System", "source": "XBPS", "fields": []}),
        )
        .unwrap();
    assert!(d.in_list && d.sel == 0);
    d.wheel(1);
    assert!(d.in_list && d.sel == 1, "the next row of the details: lit {} in_list {}", d.sel, d.in_list);
    d.wheel(-1);
    assert!(d.in_list && d.sel == 0);
    let _ = std::fs::remove_dir_all(d.apps.path.parent().unwrap());
}

#[test]
fn the_view_of_a_file_names_it_where_you_are() {
    let mut a = files();
    (a.in_list, a.sel, a.list_keys) = (true, 3, true); // diagram.png
    let rows = a.folder.as_ref().unwrap().2.clone();
    a.preview = spark_dialog::preview::Preview::new(0, &rows.title, &rows.rows, "files:file:diagram.png");
    assert!(a.preview.is_some());
    a.came_from.push(a.view.clone());
    a.view = View::Preview;
    assert_eq!(kind(&a), Kind::Grid, "the view keeps its grid rows");
    let s = scene(&mut a, 600.0, 800.0);
    // home, the view, the file's folder, then the file's own name: the last is where you are
    let (x, y, size, _) = word(&s, "diagram.png");
    assert_eq!((y, size), (82.0 - M.sup, Size::Small));
    let (fx, ..) = word(&s, "~/documents/research");
    assert!(fx < x, "the folder stands before its file");
    assert_eq!(s.hit(fx + 4.0, 78.0), Some(&Target::Back), "the folder goes back to its list");
    assert_eq!(s.hit(x + 4.0, 78.0), None, "the file is where you are");
    // while its page is on its way the line over the keys says so beside the moving bar, as an app opening has it
    a.preview.as_mut().unwrap().asked = std::time::Instant::now() - std::time::Duration::from_secs(2);
    assert_eq!(a.view_wait().as_deref(), Some("loading diagram.png"));
    let s = scene(&mut a, 600.0, 800.0);
    let (lx, ly, size, _) = word(&s, "loading diagram.png");
    assert_eq!((ly, size), (752.0 - 10.0 - M.sup, Size::Small), "on the message's line");
    let bar = words(&s).into_iter().find(|w| w.1 == 24.0 && w.2 == ly).expect("the bar at the frame's edge");
    assert!(lx > bar.1 + M.sw * bar.0.chars().count() as f64, "the words after the bar: {bar:?}");
    // a name too long for the line is cut in its middle: its type stays
    a.preview = spark_dialog::preview::Preview::new(
        0,
        &rows.title,
        &rows.rows,
        "files:file:a-very-long-file-name-for-the-quarterly-research-summary-2026.txt",
    );
    let s = scene(&mut a, 600.0, 800.0);
    let long = words(&s).into_iter().find(|w| w.0.starts_with("a-very-long")).expect("the long name");
    assert!(long.0.contains('\u{2026}') && long.0.ends_with("2026.txt"), "{}", long.0);
    assert!(long.1 + long.0.chars().count() as f64 * M.sw <= 576.0, "inside the frame");
}

#[test]
fn the_scenes_are_painted_with_cairo_and_pango() {
    use spark_dialog::paint::{png, Font, Lib};
    let Ok(lib) = Lib::open() else {
        eprintln!("  NOTICE: cairo or pango is not here -- the painter is not exercised");
        return;
    };
    let face = std::env::var("DIALOG_FONT").unwrap_or_else(|_| "monospace 12".into());
    let Some(font) = Font::new(&lib, &face) else {
        eprintln!("  NOTICE: no font {face:?} here -- the painter is not exercised");
        return;
    };
    let m = Metrics {
        cw: font.cell.w,
        ch: font.cell.h,
        up: font.ascent.0,
        sw: font.small_cell.w,
        sh: font.small_cell.h,
        sup: font.ascent.1,
    };
    assert!(m.sw < m.cw && m.sup < m.up, "the smaller face is smaller: {m:?}");
    let dir = std::env::var("NATIVE_PNG").unwrap_or_else(|_| std::env::temp_dir().to_string_lossy().into_owned());
    let (w, h) = (60.0 * m.cw, 40.0 * m.ch);
    let mut shots: Vec<(&str, App)> = vec![("scene-home", home()), ("scene-apps", apps())];
    let mut lit = apps();
    lit.down();
    lit.down();
    shots.push(("scene-apps-lit", lit));
    let mut split = apps();
    split.down();
    split.down();
    split.apps_details();
    let (serial, _) = split.apps.pending.clone().unwrap();
    split
        .apps
        .receive(
            serial,
            json!({"id": "foot.desktop", "version": "1.28.0_1", "installed": "XBPS / System", "source": "XBPS", "fields": []}),
        )
        .unwrap();
    shots.push(("scene-apps-details", split));
    let mut help = home();
    help.view = View::Help;
    help.came_from.push(View::Home);
    (help.in_list, help.sel) = (false, 0);
    shots.push(("scene-help", help));
    // files: the list with a row lit, a file's details beside it with its first lines, two panes
    let mut list = files();
    (list.in_list, list.sel, list.list_keys) = (true, 3, true);
    shots.push(("scene-files", list));
    let mut details = files();
    (details.in_list, details.sel, details.list_keys) = (true, 4, true);
    details.hint_key(HintKey::Actions);
    details.files.peek = Some(Peek {
        uri: "spark-shell://files/preview/field-notes.pdf".into(),
        page: Some(spark_dialog::preview::Page {
            lines: vec!["FIELD NOTES".into(), "research / 01".into()],
            ..Default::default()
        }),
    });
    shots.push(("scene-files-details", details));
    let mut panes = files();
    panes.files.other = Some(Pane {
        uri: folder_uri("/data/me/documents"),
        rows: spark_dialog::model::rows(&documents().to_string()),
        came_from: vec![View::Home],
        ..Pane::default()
    });
    (panes.in_list, panes.sel, panes.list_keys) = (true, 2, true);
    shots.push(("scene-files-panes", panes));
    for (name, mut a) in shots {
        a.size = size(&a, &m, w, h);
        let s = build(&a, &nord(), &m, w, h, &[]);
        let mut steps = vec![Step::Fill {
            x: 0.0,
            y: 0.0,
            w,
            h,
            color: [0x3d, 0x43, 0x4f],
        }];
        steps.extend(s.steps);
        let path = format!("{dir}/{name}.png");
        assert!(png(&lib, &font, w as i32, h as i32, &steps, &path), "{path} written");
        if std::env::var("NATIVE_PNG").is_err() {
            let _ = std::fs::remove_file(&path);
        }
        if a.view == View::Apps {
            let _ = std::fs::remove_dir_all(a.apps.path.parent().unwrap());
        }
    }
    font.free(&lib);
}
