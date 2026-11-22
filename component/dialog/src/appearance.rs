use crate::app::{App, Item, View};
use crate::model::{Row, Rows};

pub(crate) const GALLERY: &str = "spark-shell://theme/rows/gallery";
pub(crate) const PALETTES: &str = "spark-shell://theme/rows/palette/";
pub(crate) const EXPORTS: &str = "spark-shell://theme/rows/exports/";

pub(crate) fn gallery(view: &View) -> bool {
    matches!(view, View::Folder(_, uri) if uri == GALLERY || uri.strip_prefix(GALLERY).is_some_and(|tail| tail.starts_with('/')))
}

/// A work's compositions: each row a picture to look at, never applied.
pub(crate) fn compositions(uri: &str) -> bool {
    uri.strip_prefix(GALLERY)
        .is_some_and(|tail| tail.len() > "/art".len() && tail.ends_with("/art"))
}

/// A folder whose lit row is the poster: the gallery, a collection, a work's compositions.
fn browsing(uri: &str) -> bool {
    uri == GALLERY || uri.strip_prefix(GALLERY).is_some_and(|tail| tail.starts_with("/collection/")) || compositions(uri)
}

pub(crate) fn section(view: &View) -> bool {
    matches!(view, View::Folder(_, uri) if uri.starts_with("spark-shell://theme/rows/settings/") || uri.starts_with(PALETTES) || uri.starts_with(EXPORTS))
}

pub(crate) fn terminal_palette(app: &App) -> Option<(usize, String)> {
    let (p, row) = candidate(app)?;
    if row.id.starts_with("theme:room:") {
        return None; // a collection poster is not a single palette
    }
    let page = row.page.as_ref()?.strip_prefix("spark-shell://theme/preview/")?;
    let name = page.split('/').next().filter(|n| !n.is_empty())?; // a composition's page names its work first
    Some((p, format!("{PALETTES}{name}")))
}

pub(crate) fn candidate(app: &App) -> Option<(usize, &Row)> {
    match &app.view {
        View::Section(p) if app.providers[*p].label == "theme" && app.input.is_empty() => app.providers[*p]
            .rows
            .rows
            .iter()
            .find(|r| r.id == "theme:gallery:open" && r.page.is_some())
            .map(|r| (*p, r)),
        View::Folder(p, uri) if gallery(&app.view) => {
            let rows = &app.folder.as_ref().filter(|(_, u, _)| u == uri)?.2.rows;
            if browsing(uri) {
                let id = match app.picks().get(app.sel)? {
                    Item::Folder(i) => *i,
                    _ => return None,
                };
                rows.get(id).filter(|r| r.page.is_some()).map(|r| (*p, r))
            } else {
                rows.first().filter(|r| r.id.starts_with("theme:apply:") && r.page.is_some()).map(|r| (*p, r))
            }
        }
        _ => None,
    }
}

pub(crate) fn overview(p: usize, source: &Rows, out: &mut Vec<Item>) -> bool {
    let index = |id: &str| source.rows.iter().position(|row| row.id == id);
    let Some(browse) = index("theme:gallery:open") else { return false };
    out.push(Item::Row(p, browse));
    if source.rows.iter().any(|r| r.id.starts_with("theme:settings:")) {
        out.extend(
            source
                .rows
                .iter()
                .enumerate()
                .filter(|(_, r)| r.id.starts_with("theme:settings:"))
                .map(|(i, _)| Item::Row(p, i)),
        );
        return true;
    }
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
