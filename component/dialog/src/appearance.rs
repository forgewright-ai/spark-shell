use crate::app::{Item, View};
use crate::model::Rows;

const GALLERY: &str = "spark-shell://theme/rows/gallery";

pub(crate) fn gallery(view: &View) -> bool {
    matches!(view, View::Folder(_, uri) if uri == GALLERY || uri.strip_prefix(GALLERY).is_some_and(|tail| tail.starts_with('/')))
}

pub(crate) fn overview(p: usize, source: &Rows, out: &mut Vec<Item>) -> bool {
    let index = |id: &str| source.rows.iter().position(|row| row.id == id);
    let Some(browse) = index("theme:gallery:open") else { return false };
    out.push(Item::Row(p, browse));
    let groups: &[(&str, &[&str])] = &[
        (
            "wallpaper and motion",
            &["theme:wallpaper", "theme:show:Moving wallpaper", "theme:show:Animation"],
        ),
        ("type and glyphs", &["theme:show:Text face", "theme:show:Text size", "theme:show:Glyph family"]),
        (
            "interface",
            &[
                "theme:show:Transparency",
                "theme:show:Words on the bar",
                "theme:show:App icons",
                "theme:show:App spacing",
            ],
        ),
        ("manage themes", &["theme:save", "theme:picture", "theme:none"]),
    ];
    for (group, ids) in groups {
        let mut rows = ids.iter().filter_map(|id| index(id)).peekable();
        if rows.peek().is_some() {
            out.push(Item::Blank);
            out.push(Item::Heading((*group).into()));
            out.extend(rows.map(|i| Item::Row(p, i)));
        }
    }
    true
}
