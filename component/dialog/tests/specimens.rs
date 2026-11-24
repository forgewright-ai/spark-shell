// A setting's options drawn as what they are (v0.167): a typeface in its own face, a size as an A that large, a glyph
// family by its signs; one rhythm for the rows of a page, and the same words as ever where none can be drawn.
mod common;
use common::*;
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, HintKey, Provider, View};
use spark_dialog::draw::{Size, Step};
use spark_dialog::scene::{Scene, Target};

const URI: &str = "spark-shell://theme/rows/settings/type";
const FACES: [&str; 5] = ["neon", "argon", "xenon", "radon", "krypton"];

fn family(face: &str) -> String {
    format!("Monaspace {}{}", face[..1].to_uppercase(), &face[1..])
}

fn step(values: Vec<Value>, at: usize, words: [&str; 2]) -> Value {
    json!({"values": values, "at": at, "set": {"name": "theme_set", "arguments": {}}, "key": "to", "words": words})
}

/// The theme's Type and glyphs page, the face, the size and the family in use as asked.
fn page(face: usize, size: usize, family_at: usize) -> App {
    let mut a = App::new(Config::default(), &[]);
    (a.pixels, a.window_focused) = (true, true);
    let mut p = Provider::new("theme");
    p.ready = true;
    let tool = json!({"name": "theme_set", "title": "theme set NAME", "description": "d",
        "inputSchema": {"type": "object", "properties": {"to": {"type": "string"}}}, "annotations": {"destructiveHint": false}});
    p.tools = spark_dialog::model::tools(&json!({ "tools": [tool] }));
    a.providers = vec![p];
    let faces = FACES.iter().map(|f| json!({"shown": f, "sent": f, "face": family(f)})).collect();
    let sizes = (6..41).map(|n| json!({"shown": n.to_string(), "sent": n.to_string()})).collect();
    let signs = [
        ("stone", "\u{25b0}\u{25b1}\u{25b0}\u{25b1} \u{25b0}"),
        ("star", "\u{2501}\u{2500}\u{2501}\u{2500} \u{2726}"),
        ("banner", "\u{25ae}\u{25af}\u{25ae}\u{25af} \u{27a4}"),
    ];
    let families = signs.iter().map(|(n, s)| json!({"shown": n, "sent": n, "sample": s})).collect();
    let rows = json!({"title": "Type and glyphs", "rows": [
        {"id": "face", "text": "Typeface", "step": step(faces, face, ["back", "next"])},
        {"id": "size", "text": "Text size", "step": step(sizes, size - 6, ["smaller", "bigger"])},
        {"id": "family", "text": "Glyph family", "step": step(families, family_at, ["back", "next"])}
    ]});
    a.view = View::Folder(0, URI.into());
    a.came_from = vec![View::Home];
    a.folder = Some((0, URI.into(), spark_dialog::model::rows(&rows.to_string()).unwrap()));
    (a.in_list, a.sel) = (true, 0);
    for f in FACES {
        a.faces.insert(family(f), Some(41.0));
    }
    a
}

/// The typefaces drawn: each family with its left edge, its baseline, its color.
fn specimens(s: &Scene) -> Vec<(String, f64, f64, [u8; 3])> {
    s.steps
        .iter()
        .filter_map(|st| match st {
            Step::Specimen {
                x, base, face, color, text, ..
            } => {
                assert_eq!(text, spark_dialog::draw::LETTERS);
                Some((face.clone(), *x, *base, *color))
            }
            _ => None,
        })
        .collect()
}

/// The options' places: row, option, box.
type Place = (usize, usize, (f64, f64, f64, f64));

fn places(s: &Scene) -> Vec<Place> {
    s.hits
        .iter()
        .filter_map(|h| match h.target {
            Target::Option(n, k) => Some((n, k, (h.x, h.y, h.w, h.h))),
            _ => None,
        })
        .collect()
}

/// The three settings read as one: their options start at one column, stand the same distance apart on one baseline
/// with their name, each over its caption, in rows as tall; the one in use is in the accent with the line.
#[test]
fn the_three_settings_of_type_and_glyphs_are_one_pattern() {
    let mut a = page(3, 14, 0);
    let s = frame(&mut a, 600.0, 800.0);
    let faces = specimens(&s);
    assert_eq!(
        faces.iter().map(|f| f.0.clone()).collect::<Vec<_>>(),
        FACES.map(family),
        "each in its own face, in order"
    );
    let x0 = faces[0].1;
    let pitch = faces[1].1 - x0;
    for (k, (name, x, base, color)) in faces.iter().enumerate() {
        assert_eq!((*x, *base), (x0 + k as f64 * pitch, faces[0].2), "{name}");
        assert_eq!(*color == ACCENT, k == 3, "{name}: radon alone is in use");
        let caption = word(&s, FACES[k]);
        assert_eq!((caption.0, caption.2, caption.3 == ACCENT), (*x, Size::Small, k == 3));
        assert!(caption.1 > *base, "its name under it");
    }
    // the sizes: an A at each, over its number, on the same columns
    let sizes: Vec<_> = words(&s).into_iter().filter(|w| w.0 == "A").map(|w| (w.1, w.3)).collect();
    assert_eq!(
        sizes,
        [Size::Small, Size::Main, Size::Lead, Size::Head]
            .into_iter()
            .enumerate()
            .map(|(k, size)| (x0 + k as f64 * pitch, size))
            .collect::<Vec<_>>()
    );
    for (k, n) in ["10", "12", "14", "16"].iter().enumerate() {
        assert_eq!(word(&s, n).0, x0 + k as f64 * pitch);
    }
    // the families, each by its signs, on the same columns
    let stone = word(&s, "\u{25b0}\u{25b1}\u{25b0}\u{25b1} \u{25b0}");
    let star = word(&s, "\u{2501}\u{2500}\u{2501}\u{2500} \u{2726}");
    assert_eq!((stone.0, star.0, stone.3), (x0, x0 + pitch, ACCENT));
    assert_eq!(word(&s, "banner").0, x0 + 2.0 * pitch);
    // the lines under the three in use, from their left edges; a name on the specimens' baseline; rows as tall
    for x in [x0 + 3.0 * pitch, x0 + 2.0 * pitch, x0] {
        assert!(fills(&s, ACCENT).iter().any(|f| f.0 == x && f.3 == 2.0), "a line at {x}");
    }
    assert_eq!(word(&s, "Typeface").1 + M.up, faces[0].2);
    let top = |n: usize| places(&s).iter().find(|p| p.0 == n).unwrap().2 .1;
    assert_eq!(top(1) - top(0), top(2) - top(1), "rows as tall");
    // every option a target a finger hits, and inside the window
    assert_eq!(places(&s).len(), 5 + 4 + 3);
    for (n, k, (x, y, w, h)) in places(&s) {
        assert!(w >= 44.0 && h >= 44.0 && x >= 0.0 && x + w <= 600.0, "{n} {k}");
        assert_eq!(s.hit(x + 1.0, y + 1.0), Some(&Target::Option(n, k)));
    }
    // Left and Right change the lit row in place
    assert!(a.reply.is_none());
    a.hint_key(HintKey::Right);
    assert_eq!(a.keep_lit.as_deref(), Some("face"));
}

/// Whatever is in use, every option stands where it stood: the room of a size that is none of the usual four is kept.
#[test]
fn nothing_moves_as_what_is_in_use_changes() {
    for width in [420.0, 600.0, 1400.0] {
        let at = |face: usize, size: usize, fam: usize| {
            let s = frame(&mut page(face, size, fam), width, 900.0);
            let mut p = places(&s);
            p.retain(|(n, k, _)| *n != 1 || [4, 6, 8, 10].contains(k));
            (specimens(&s).iter().map(|f| (f.1, f.2)).collect::<Vec<_>>(), p)
        };
        let first = at(0, 12, 0);
        for (face, size, fam) in [(4, 12, 2), (2, 11, 1), (1, 40, 0), (0, 6, 2)] {
            assert_eq!(at(face, size, fam), first, "{width}: {face} {size} {fam}");
        }
    }
}

/// A size in use that is none of the four stands after them, its number under it, in the accent.
#[test]
fn a_size_of_its_own_stands_after_the_usual_four() {
    let s = frame(&mut page(0, 13, 0), 600.0, 800.0);
    let last = places(&s).into_iter().rfind(|p| p.0 == 1).unwrap();
    assert_eq!(last.1, 7, "13 is the eighth size");
    let caption = word(&s, "13");
    assert_eq!((caption.0, caption.3), (last.2 .0 + 8.0, ACCENT));
    assert_eq!(words(&s).iter().filter(|w| w.0 == "A").count(), 5);
}

/// A family no font here is of falls back to its word, and where none resolves the row is the words it always was.
#[test]
fn a_face_that_does_not_resolve_is_its_word() {
    let mut a = page(0, 12, 0);
    a.faces.insert(family("xenon"), None);
    a.faces.remove(&family("krypton"));
    let s = frame(&mut a, 600.0, 800.0);
    assert_eq!(
        specimens(&s).iter().map(|f| f.0.as_str()).collect::<Vec<_>>(),
        ["Monaspace Neon", "Monaspace Argon", "Monaspace Radon"]
    );
    for (name, others) in [("xenon", 1), ("krypton", 1)] {
        let all: Vec<_> = words(&s).into_iter().filter(|w| w.0 == name).collect();
        assert_eq!((all.len(), all[0].3), (others, Size::Main), "{name}: the word, said once");
    }
    // the families asked of the window: the ones not asked for yet, each once
    assert_eq!(a.faces_wanted(), [family("krypton")]);
    a.faces.clear();
    assert_eq!(a.faces_wanted().len(), 5);
    let s = frame(&mut a, 600.0, 800.0);
    assert!(specimens(&s).is_empty());
    for name in FACES {
        assert_eq!(word(&s, name).2, Size::Main);
    }
    // a page that names a thousand families asks for 64 at most
    let values: Vec<Value> = (0..60).map(|i| json!({"shown": "f", "sent": "f", "face": format!("Face {i}")})).collect();
    let rows = json!({"title": "t", "rows": [
        {"id": "a", "text": "a", "step": step(values.clone(), 0, ["back", "next"])},
        {"id": "b", "text": "b", "step": step(values.iter().map(|v| json!({"shown": "g", "sent": "g", "face": format!("Other {}", v["face"].as_str().unwrap())})).collect(), 0, ["back", "next"])}
    ]});
    a.folder = Some((0, URI.into(), spark_dialog::model::rows(&rows.to_string()).unwrap()));
    assert_eq!(a.faces_wanted().len(), 64);
}

/// A window too narrow for one line: the options stand under their name, in lines, none cut.
#[test]
fn a_narrow_window_wraps_the_specimens_and_cuts_none() {
    for width in [300.0, 360.0, 420.0] {
        let s = frame(&mut page(4, 13, 2), width, 1200.0);
        assert_eq!(specimens(&s).len(), 5);
        for (n, k, (x, _, w, _)) in places(&s) {
            assert!(x >= 0.0 && x + w <= width, "{width}: row {n} option {k} from {x}, {w} wide");
        }
        for (text, x, _, size, _) in words(&s) {
            let each = if size == Size::Small { M.sw } else { M.cw };
            if FACES.contains(&text.as_str()) {
                assert!(x + text.len() as f64 * each <= width, "{width}: {text} is cut");
            }
        }
    }
}

/// The words of a short list stand from the page's column, the first of every row on it; numbers of one unit say it
/// once.
#[test]
fn a_list_of_one_unit_says_it_once_and_every_row_starts_at_the_column() {
    let mut a = App::new(Config::default(), &[]);
    (a.pixels, a.window_focused) = (true, true);
    let mut p = Provider::new("display");
    p.ready = true;
    let minutes = |ns: &[&str]| -> Vec<Value> {
        ns.iter()
            .map(|n| json!({"shown": if *n == "0" { "never".to_string() } else { format!("{n} min") }, "sent": n}))
            .collect()
    };
    let savers = ["clock", "art", "spark", "starfield", "drift"].map(|s| json!({"shown": s, "sent": s}));
    p.rows = spark_dialog::model::rows(
        &json!({"title": "display", "rows": [
            {"id": "idle", "text": "idle screen", "group": "idle and lock", "step": step(minutes(&["5", "10", "15", "30", "60", "0"]), 1, ["sooner", "later"])},
            {"id": "saver", "text": "saver", "group": "idle and lock", "step": step(savers.to_vec(), 3, ["back", "next"])},
            {"id": "lock", "text": "lock", "group": "idle and lock", "step": step(minutes(&["5", "10", "15", "20", "30", "60", "0"]), 3, ["sooner", "later"])},
            {"id": "use", "text": "in use", "group": "idle and lock", "switch": {"on": true, "turn_on": {"name": "display_on"}, "turn_off": {"name": "display_off"}}}
        ]})
        .to_string(),
    )
    .unwrap();
    a.providers = vec![p];
    a.view = View::Section(0);
    a.came_from = vec![View::Home];
    (a.in_list, a.sel) = (true, 0);
    let s = frame(&mut a, 600.0, 800.0);
    assert_eq!(words(&s).iter().filter(|w| w.0 == "min").count(), 2, "once a list, after its last number");
    let (sixty, min) = (word(&s, "60"), word(&s, "min"));
    assert!(
        min.2 == Size::Small && min.0 > sixty.0 && min.1 > sixty.1,
        "small, after the 60, on its baseline"
    );
    let column = word(&s, "5").0;
    for first in ["clock", "on"] {
        assert_eq!(word(&s, first).0, column, "{first}");
    }
    // a line of its own only for the list that holds one more: it hangs under its options, never under the name
    let lock: Vec<_> = places(&s).into_iter().filter(|p| p.0 == 2).collect();
    assert_eq!(lock.len(), 7);
    assert!(lock.iter().all(|p| p.2 .0 >= column - 8.0 && p.2 .0 + p.2 .2 <= 600.0), "{lock:?}");
    let idle: Vec<_> = places(&s).into_iter().filter(|p| p.0 == 0).collect();
    assert!(idle.len() == 6 && idle.iter().all(|p| p.2 .1 == idle[0].2 .1), "on one line");
}
