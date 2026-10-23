// Mock-ups for the v0.88 review: the dialog drawn by its own code from
// fixture rows shaped as the providers would send them. Run with
// MOCKUP_DIR=... cargo test --test mockup -- --nocapture; it writes one HTML
// page per state and palette. Not a golden: a picture to decide from.
mod common;
use ratatui::buffer::{Buffer, CellDiffOption};
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier};
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, Provider, View, CALENDAR_DEST, HEIGHT, SETTINGS_DEST, WIDTH};
use spark_dialog::model;
use spark_dialog::palette::Palette;
use spark_dialog::scrub::cells;
use std::collections::HashMap;

const CLOCK: &str = "Thu 22 Oct \u{b7} 23:30";
const DRAWINGS: [(&str, &str); 17] = [
    ("skyline", "tokyonight-night"),
    ("fjord", "nord"),
    ("forest", "everforest-dark"),
    ("sunset", "gruvbox-dark"),
    ("hills", "catppuccin-mocha"),
    ("dunes", "dracula"),
    ("ripples", "rose-pine"),
    ("contours", "selenized-dark"),
    ("morning", "solarized-light"),
    ("meadow", "catppuccin-latte"),
    ("kites", "tokyonight-day"),
    ("fields", "gruvbox-light"),
    ("grove", "everforest-light"),
    ("arches", "rose-pine-dawn"),
    ("shore", "selenized-light"),
    ("flight", "one-light"),
    ("embers", "any dark palette"),
];

fn themes() -> Vec<(String, HashMap<String, String>)> {
    let dir = format!("{}/../themes", env!("CARGO_MANIFEST_DIR"));
    let mut out: Vec<(String, HashMap<String, String>)> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|x| x == "env"))
        .map(|e| {
            let name = e.path().file_stem().unwrap().to_string_lossy().to_string();
            let kv = std::fs::read_to_string(e.path())
                .unwrap()
                .lines()
                .filter_map(|l| l.split_once('='))
                .map(|(k, v)| (k.to_string(), v.trim().to_string()))
                .collect();
            (name, kv)
        })
        .collect();
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

fn luma(hex: &str) -> u32 {
    let v = u32::from_str_radix(hex.trim_start_matches('#'), 16).unwrap_or(0);
    let (r, g, b) = ((v >> 16) & 255, (v >> 8) & 255, v & 255);
    (299 * r + 587 * g + 114 * b) / 1000
}

fn chip(kv: &HashMap<String, String>) -> Value {
    let k = |n: &str| kv.get(n).cloned().unwrap_or_else(|| "#808080".into());
    json!([
        k("THEME_BG"),
        k("THEME_FG"),
        k("THEME_ACCENT"),
        k("THEME_ANSI_1"),
        k("THEME_ANSI_2"),
        k("THEME_ANSI_3"),
        k("THEME_ANSI_4"),
        k("THEME_ANSI_5"),
        k("THEME_ANSI_6")
    ])
}

fn provider(label: &str, title: &str, rows: Value) -> Provider {
    let mut p = Provider::new(label);
    p.title = title.into();
    p.version = "0.88".into();
    p.rows = model::rows(&rows.to_string()).unwrap();
    p.ready = true;
    p
}

fn row(id: &str, sign: &str, text: &str, tool: Option<(&str, Value)>, group: Option<&str>) -> Value {
    json!({"id": id, "sign": sign, "text": text, "tool": tool.map(|(n, a)| json!({"name": n, "arguments": a})), "more": [], "columns": [], "children": null, "group": group})
}

fn theme_rows(cur: &str, drawing: &str, size: &str, transparency: &str) -> Value {
    let mut rows = vec![
        json!({"id": "theme:wallpaper", "sign": "blank", "text": "Wallpaper", "tool": null, "more": [], "columns": [drawing], "children": "spark-shell://theme/rows/wallpapers", "group": null}),
        json!({"id": "theme:text", "sign": "blank", "text": "Text size", "tool": null, "more": [], "columns": [], "children": null, "group": null,
               "step": {"value": size, "less": {"name": "theme_text", "arguments": {"size": "smaller"}}, "more": {"name": "theme_text", "arguments": {"size": "bigger"}}, "words": ["smaller", "bigger"]}}),
        json!({"id": "theme:transparency", "sign": "blank", "text": "Transparency", "tool": null, "more": [], "columns": [], "children": null, "group": null,
               "step": {"value": transparency, "less": {"name": "theme_transparency", "arguments": {"amount": "less"}}, "more": {"name": "theme_transparency", "arguments": {"amount": "more"}}, "words": ["less", "more"]}}),
    ];
    let all = themes();
    for (dark, group) in [(true, "dark"), (false, "light")] {
        for (name, kv) in all
            .iter()
            .filter(|(_, kv)| (luma(kv.get("THEME_BG").map(String::as_str).unwrap_or("#000")) < 128) == dark)
        {
            let own = DRAWINGS.iter().find(|(_, p)| p == name).map(|(d, _)| *d).unwrap_or("");
            let sign = if name == cur { "check" } else { "blank" };
            let tool = if name == cur {
                Value::Null
            } else {
                json!({"name": "theme_palette", "arguments": {"name": name}})
            };
            rows.push(json!({"id": format!("theme:{}", name), "sign": sign, "text": name, "tool": tool, "more": [], "columns": [own], "children": null, "group": group, "chip": chip(kv)}));
        }
    }
    rows.push(json!({"id": "theme:save", "sign": "blank", "text": "save this look as", "tool": {"name": "theme_save", "arguments": {}, "ask": ["name"]}, "more": [], "columns": [], "children": null, "group": "yours"}));
    rows.push(json!({"id": "theme:picture", "sign": "blank", "text": "a theme from a picture", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows", "group": "yours"}));
    rows.push(json!({"id": "theme:none", "sign": "blank", "text": "the terminal's own colors", "tool": {"name": "theme_palette", "arguments": {"name": "none"}}, "more": [], "columns": [], "children": null, "group": "yours"}));
    json!({"title": cur, "rows": rows, "short": []})
}

fn wallpaper_rows(cur: &str, thumbs: &str) -> Value {
    let mut rows = vec![];
    for (d, p) in DRAWINGS {
        let sign = if d == cur { "check" } else { "blank" };
        let tool = if d == cur {
            Value::Null
        } else {
            json!({"name": "theme_wallpaper", "arguments": {"name": d}})
        };
        let said = if p.starts_with("any") {
            "for any dark palette".to_string()
        } else {
            format!("for {}", p)
        };
        rows.push(json!({"id": format!("wall:{}", d), "sign": sign, "text": d, "tool": tool, "more": [], "columns": [said], "children": null, "group": "drawings", "preview": format!("{}/{}.png", thumbs, d)}));
    }
    rows.push(json!({"id": "wall:picture", "sign": "blank", "text": "a picture of yours", "tool": null, "more": [], "columns": [], "children": "spark-shell://files/rows", "group": "yours"}));
    rows.push(json!({"id": "wall:color", "sign": "blank", "text": "a color", "tool": {"name": "theme_wallpaper", "arguments": {}, "ask": ["name"]}, "more": [], "columns": ["a name or #rrggbb"], "children": null, "group": "yours"}));
    rows.push(json!({"id": "wall:ground", "sign": "blank", "text": "the ground", "tool": {"name": "theme_wallpaper", "arguments": {"name": "default"}}, "more": [], "columns": ["the palette's own, darker"], "children": null, "group": "yours", "chip": ["#13141c"]}));
    json!({"title": "wallpaper", "rows": rows, "short": []})
}

fn app(cur: &str, drawing: &str, thumbs: &str) -> App {
    let cfg = Config {
        plus: true,
        model: true,
        talk: true,
        close: true,
        ..Config::default()
    };
    let mut app = App::new(cfg, &[]);
    let apps = provider(
        "apps",
        "8 apps",
        json!({"title": "apps", "rows": [
            row("apps:terminal", "opens", "terminal", Some(("apps_terminal", json!({}))), None),
            row("apps:firefox", "opens", "firefox", Some(("apps_open", json!({"name": "firefox"}))), None),
            row("apps:btop", "opens", "btop", Some(("apps_open", json!({"name": "btop"}))), None),
            row("apps:aerc", "opens", "aerc", Some(("apps_open", json!({"name": "aerc"}))), None),
            row("apps:micro", "opens", "micro", Some(("apps_open", json!({"name": "micro"}))), None),
            row("apps:mpv", "opens", "mpv", Some(("apps_open", json!({"name": "mpv"}))), None),
            row("apps:pyradio", "opens", "pyradio", Some(("apps_open", json!({"name": "pyradio"}))), None),
            row("apps:tmux", "opens", "tmux", Some(("apps_open", json!({"name": "tmux"}))), None)
        ], "short": []}),
    );
    let window = provider(
        "window",
        "side by side",
        json!({"title": "window", "rows": [
            row("window:focus terminal", "opens", "terminal", Some(("window_focus", json!({"name": "terminal"}))), Some("open now")),
            row("window:focus firefox", "opens", "firefox", Some(("window_focus", json!({"name": "firefox"}))), Some("open now"))
        ], "short": []}),
    );
    let layout = provider(
        "layout",
        "3 saved",
        json!({"title": "layout", "rows": [
            row("layout:writing", "opens", "writing", Some(("layout_open", json!({"name": "writing"}))), None),
            row("layout:news", "opens", "news", Some(("layout_open", json!({"name": "news"}))), None),
            row("layout:music", "opens", "music", Some(("layout_open", json!({"name": "music"}))), None)
        ], "short": []}),
    );
    let notes = provider(
        "notes",
        "12 in ~/notes",
        json!({"title": "notes", "rows": [
            row("notes:new", "opens", "new note", Some(("notes_new", json!({}))), None),
            row("notes:groceries", "blank", "groceries", Some(("notes_open", json!({"name": "groceries"}))), None),
            row("notes:talk", "blank", "ideas for the talk", Some(("notes_open", json!({"name": "ideas for the talk"}))), None),
            row("notes:box", "blank", "box setup", Some(("notes_open", json!({"name": "box setup"}))), None)
        ], "short": []}),
    );
    let reminders = provider(
        "reminders",
        "1 ahead",
        json!({"title": "reminders", "rows": [
            row("reminders:new", "opens", "new reminder", Some(("reminders_new", json!({}))), None),
            json!({"id": "reminders:show:call the dentist", "sign": "ring", "text": "call the dentist", "tool": null, "more": [], "columns": ["9:00"], "children": null, "group": "tomorrow"})
        ], "short": []}),
    );
    let wifi = provider("wifi", "home-wifi", json!({"title": "wifi", "rows": [], "short": []}));
    let out = provider(
        "out",
        "jabra speak \u{b7} 62%",
        json!({"title": "out", "rows": [
            row("out:mute", "blank", "mute", Some(("out_mute", json!({}))), None)
        ], "short": []}),
    );
    let display = provider(
        "display",
        "brightness 60%",
        json!({"title": "display", "rows": [
            row("display:dimmer", "blank", "dimmer", Some(("display_brightness", json!({"level": "down"}))), None)
        ], "short": []}),
    );
    let theme = provider("theme", cur, theme_rows(cur, drawing, "11", "25%"));
    let files = provider("files", "your home", json!({"title": "files", "rows": [], "short": []}));
    let clock = provider("clock", "", json!({"title": "clock", "rows": [], "short": []}));
    let _ = thumbs;
    app.providers = vec![apps, files, window, layout, notes, reminders, clock, out, wifi, display, theme];
    app.model_name = Some("gemma4-26b-a4b".into());
    app.voice_on = true;
    app
}

fn hex(c: Color, d: Color) -> String {
    match if c == Color::Reset { d } else { c } {
        Color::Rgb(r, g, b) => format!("#{:02x}{:02x}{:02x}", r, g, b),
        _ => "inherit".into(),
    }
}

/// The buffer as one page: the box's font, a 19 px row, the window's own air, the picture where it lies.
fn page(buf: &Buffer, pal: &Palette, preview: &Option<(u16, u16, u16, u16, String)>) -> String {
    let esc = |s: &str| s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    let (w, h) = (buf.area.width, buf.area.height);
    let mut rows = String::new();
    for y in 0..h {
        let mut skip = 0;
        for x in 0..w {
            let c = &buf[(x, y)];
            if skip > 0 {
                skip -= 1;
                continue;
            }
            let sym = if c.diff_option == CellDiffOption::Skip { " " } else { c.symbol() };
            let sym = if sym.is_empty() { " " } else { sym };
            skip = cells(sym).saturating_sub(1);
            let bold = if c.modifier.contains(Modifier::BOLD) { "font-weight:700;" } else { "" };
            rows.push_str(&format!(
                "<span style=\"color:{};background:{};{}display:inline-block;width:{}ch;height:19px;text-align:center\">{}</span>",
                hex(c.fg, pal.fg),
                hex(c.bg, pal.surface),
                bold,
                cells(sym).max(1),
                esc(sym)
            ));
        }
        rows.push('\n');
    }
    let img = match preview {
        Some((x, y, pw, ph, file)) => format!(
            "<img src=\"file://{}\" style=\"position:absolute;left:calc(2ch + {}ch);top:calc(17px + {}px);width:{}ch;height:{}px;object-fit:cover;border-radius:3px\">",
            file,
            x,
            *y as u32 * 19,
            pw,
            *ph as u32 * 19
        ),
        None => String::new(),
    };
    let fonts = format!("{}/fonts", std::env::var("MOCKUP_DIR").unwrap());
    format!(
        "<!doctype html><meta charset=utf-8><style>@font-face{{font-family:DV;src:url(file://{f}/DejaVuSansMono.ttf)}}@font-face{{font-family:DV;font-weight:700;src:url(file://{f}/DejaVuSansMono-Bold.ttf)}}body{{margin:0;padding:0;background:{bg}}}</style><body><div style=\"position:relative;display:inline-block;background:{bg};padding:17px 2ch;font:15px/19px DV;white-space:pre;width:{w}ch\">{rows}{img}</div></body>",
        f = fonts,
        bg = hex(pal.surface, pal.surface),
        w = w,
        rows = rows,
        img = img
    )
}

fn shot(app: &App, pal: &Palette, name: &str, palname: &str) {
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    let drawn = spark_dialog::ui::draw(app, pal, CLOCK, &mut b);
    let dir = std::env::var("MOCKUP_DIR").unwrap();
    std::fs::write(format!("{}/{}-{}.html", dir, name, palname), page(&b, pal, &drawn.preview)).unwrap();
}

fn type_words(app: &mut App, words: &str) {
    for c in words.chars() {
        app.typed(c);
    }
}

fn lit(app: &mut App, text: &str) {
    let picks = app.picks();
    let i = picks
        .iter()
        .position(|it| match it {
            spark_dialog::app::Item::Row(p, r) => app.providers[*p].rows.rows[*r].text == text,
            spark_dialog::app::Item::Folder(i) => app.folder.as_ref().is_some_and(|(_, _, rows)| rows.rows[*i].text == text),
            _ => false,
        })
        .unwrap_or_else(|| panic!("no row {}", text));
    app.in_list = true;
    app.sel = i;
}

#[test]
fn mockups() {
    let Ok(dir) = std::env::var("MOCKUP_DIR") else { return };
    let thumbs = format!("{}/thumbs", dir);
    for (palname, drawing) in [("tokyonight-night", "skyline"), ("solarized-light", "morning")] {
        let pal = common::palette(palname);
        let base = app(palname, drawing, &thumbs);
        let th = base.providers.iter().position(|p| p.label == "theme").unwrap();

        let a = app(palname, drawing, &thumbs);
        shot(&a, &pal, "1-home", palname);

        let mut a = app(palname, drawing, &thumbs);
        type_words(&mut a, "nord");
        shot(&a, &pal, "2-home-nord", palname);

        let mut a = app(palname, drawing, &thumbs);
        type_words(&mut a, "mute everything and turn the screen down");
        shot(&a, &pal, "3-home-sentence", palname);

        let mut a = app(palname, drawing, &thumbs);
        a.view = View::Section(th);
        a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST)];
        shot(&a, &pal, "4-theme", palname);

        let mut a = app(palname, drawing, &thumbs);
        a.view = View::Section(th);
        a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST)];
        lit(&mut a, "Text size");
        shot(&a, &pal, "5-theme-text", palname);

        let mut a = app(palname, drawing, &thumbs);
        a.view = View::Section(th);
        a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST)];
        lit(&mut a, "nord");
        shot(&a, &pal, "6-theme-nord", palname);

        for (k, l) in [("7-wallpaper", None), ("8-wallpaper-fjord", Some("fjord"))] {
            let mut a = app(palname, drawing, &thumbs);
            let uri = "spark-shell://theme/rows/wallpapers".to_string();
            let rows = model::rows(&wallpaper_rows(drawing, &thumbs).to_string()).unwrap();
            a.folder = Some((th, uri.clone(), rows));
            a.view = View::Folder(th, uri);
            a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST), View::Section(th)];
            if let Some(l) = l {
                lit(&mut a, l);
            }
            shot(&a, &pal, k, palname);
        }
    }
}

/// A color as the design system's preview names it: a color of the dialog's palette is its token, so the card
/// follows the theme picker; a cell on a ground of its own (a palette's chip, a sample) keeps the data's hex.
fn ds_color(c: Color, d: Color, pal: &Palette, data: bool) -> String {
    let c = if c == Color::Reset { d } else { c };
    if !data {
        for (k, v) in [
            (pal.fg, "fg"),
            (pal.accent, "accent"),
            (pal.muted, "panel-muted"),
            (pal.surface, "panel-bg"),
            (pal.lit, "panel-hi"),
            (pal.alarm, "alarm"),
            (pal.ok, "ansi-2"),
        ] {
            if c == k {
                return format!("var(--{})", v);
            }
        }
    }
    hex(c, d)
}

/// One frame of the preview: a caption, then the window's cells as runs of one style a line, a glyph outside
/// ASCII held to one cell, the picture beside a list where the dialog draws it.
/// Where the dialog draws a picture (its cells and its file) and the picture's source in the page.
type Picture<'a> = Option<(&'a (u16, u16, u16, u16, String), &'a str)>;

fn ds_frame(buf: &Buffer, pal: &Palette, caption: &str, picture: Picture) -> String {
    let esc = |s: &str| s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    let (w, h) = (buf.area.width, buf.area.height);
    let mut out = String::new();
    for y in 0..h {
        let mut run: Option<(String, String)> = None; // (style, text)
        let mut skip = 0;
        for x in 0..w {
            if skip > 0 {
                skip -= 1;
                continue;
            }
            let c = &buf[(x, y)];
            let sym = if c.diff_option == CellDiffOption::Skip { " " } else { c.symbol() };
            let sym = if sym.is_empty() { " " } else { sym };
            skip = cells(sym).saturating_sub(1);
            let data = c.bg != Color::Reset && c.bg != pal.surface && c.bg != pal.lit;
            let style = format!(
                "color:{};background:{};{}",
                ds_color(c.fg, pal.fg, pal, data),
                ds_color(c.bg, pal.surface, pal, data),
                if c.modifier.contains(Modifier::BOLD) { "font-weight:700;" } else { "" }
            );
            let text = if sym.is_ascii() {
                esc(sym)
            } else {
                format!(
                    "<span style=\"display:inline-block;width:{}ch;text-align:center\">{}</span>",
                    cells(sym).max(1),
                    esc(sym)
                )
            };
            match run.as_mut() {
                Some((st, t)) if *st == style => t.push_str(&text),
                _ => {
                    if let Some((st, t)) = run.take() {
                        out.push_str(&format!("<span style=\"{}\">{}</span>", st, t));
                    }
                    run = Some((style, text));
                }
            }
        }
        if let Some((st, t)) = run.take() {
            out.push_str(&format!("<span style=\"{}\">{}</span>", st, t));
        }
        out.push('\n');
    }
    let img = match picture {
        Some(((x, y, pw, ph, _), src)) => format!(
            "<img alt=\"the lit drawing\" src=\"{}\" style=\"position:absolute;left:calc(2ch + {}ch);top:{}px;width:{}ch;height:{}px;object-fit:cover\">",
            src,
            x,
            19 + *y as u32 * 19,
            pw,
            *ph as u32 * 19
        ),
        None => String::new(),
    };
    format!(
        "<div><p style=\"color:var(--panel-muted);font-size:13px;margin:0 0 8px\">{}</p><div style=\"position:relative;background:var(--panel-bg);padding:19px 2ch;white-space:pre;width:{}ch;line-height:19px\">{}{}</div></div>",
        esc(caption),
        w,
        out,
        img
    )
}

/// The design system's Dialog preview, from this code's own render (DS_PREVIEW=FILE, DS_PICTURE=a PNG of skyline):
/// the home with each place's state, a palette named and Ask spark, the theme section, a value lit, the wallpaper list.
#[test]
fn design_system_preview() {
    let Ok(file) = std::env::var("DS_PREVIEW") else { return };
    let picture = std::env::var("DS_PICTURE").ok().map(|p| {
        let b = std::fs::read(p).unwrap();
        let mut s = String::from("data:image/png;base64,");
        const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for ch in b.chunks(3) {
            let n = (ch[0] as u32) << 16 | (*ch.get(1).unwrap_or(&0) as u32) << 8 | *ch.get(2).unwrap_or(&0) as u32;
            for k in 0..4 {
                if k <= ch.len() {
                    s.push(T[(n >> (18 - 6 * k) & 63) as usize] as char);
                } else {
                    s.push('=');
                }
            }
        }
        s
    });
    let pal = common::palette("tokyonight-night");
    let base = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    let th = base.providers.iter().position(|p| p.label == "theme").unwrap();
    let draw = |a: &App| -> (Buffer, spark_dialog::ui::Drawn) {
        let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
        let d = spark_dialog::ui::draw(a, &pal, CLOCK, &mut b);
        (b, d)
    };
    let mut frames = vec![];
    let a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    frames.push(ds_frame(&draw(&a).0, &pal, "home: what each place holds", None));
    let mut a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    type_words(&mut a, "nord");
    frames.push(ds_frame(&draw(&a).0, &pal, "home, nord typed: the palette lit, Enter uses it", None));
    let mut a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    type_words(&mut a, "mute everything and turn the screen down");
    frames.push(ds_frame(&draw(&a).0, &pal, "home, a request: no row has that name, Ask spark lit", None));
    let mut a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    a.view = View::Section(th);
    a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST)];
    frames.push(ds_frame(&draw(&a).0, &pal, "theme: the values, the palettes with their chips, yours", None));
    let mut a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    a.view = View::Section(th);
    a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST)];
    lit(&mut a, "Text size");
    frames.push(ds_frame(&draw(&a).0, &pal, "theme, text size lit: left and right change it", None));
    let mut a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    let uri = "spark-shell://theme/rows/wallpapers".to_string();
    a.folder = Some((th, uri.clone(), model::rows(&wallpaper_rows("fjord", "/srv/look/thumbs").to_string()).unwrap()));
    a.view = View::Folder(th, uri);
    a.came_from = vec![View::Home, View::Dest(SETTINGS_DEST), View::Section(th)];
    lit(&mut a, "skyline");
    let (b, d) = draw(&a);
    let pic = match (&d.preview, &picture) {
        (Some(p), Some(src)) => Some((p, src.as_str())),
        _ => None,
    };
    frames.push(ds_frame(&b, &pal, "the wallpaper list, skyline lit: its picture in the palette in use", pic));
    let head = "<!-- @dsCard group=\"Dialog\" height=2560 width=1420 subtitle=\"the dialog from v0.89's own render, bound to the tokens: the home with each place's state, a palette named and Ask spark, the theme section, a value lit, the wallpaper list with its picture\" -->\n<style>body{margin:0;background:var(--bg);color:var(--fg);font:16px/19px var(--font-mono);padding:12px}.d{display:flex;flex-wrap:wrap;gap:24px;align-items:flex-start}</style>\n";
    std::fs::write(file, format!("{}<div class=\"d\">{}</div>\n", head, frames.join(""))).unwrap();
}

/// The design system's Calendar preview, from this code's own render (DS_CALENDAR=FILE): the time in large
/// figures, the two months, the reminders in their groups (#41).
#[test]
fn design_system_calendar_preview() {
    let Ok(file) = std::env::var("DS_CALENDAR") else { return };
    let pal = common::palette("tokyonight-night");
    let mut a = app("tokyonight-night", "skyline", "/srv/look/thumbs");
    let r = |id: &str, sign: &str, text: &str, when: &str, group: &str, date: &str| json!({"id": id, "sign": sign, "text": text, "tool": null, "more": [], "columns": [when], "children": null, "group": group, "date": date});
    let rows = json!({"title": "reminders", "rows": [
        row("reminders:new", "opens", "new reminder", Some(("reminders_new", json!({}))), None),
        r("reminders:show:bread", "dot", "take the bread out", "18:30", "due", "2026-10-20"),
        r("reminders:show:gym", "ring", "gym", "19:00", "today", "2026-10-20"),
        r("reminders:show:dentist", "ring", "call the dentist", "09:00", "tomorrow", "2026-10-21"),
        r("reminders:show:dinner", "ring", "dinner with ada", "Fri 20:00", "this week", "2026-10-23"),
        r("reminders:show:vet", "ring", "the vet", "Tue 3 Nov 16:30", "later", "2026-11-03")
    ], "short": []});
    if let Some(p) = a.providers.iter_mut().find(|p| p.label == "reminders") {
        p.rows = model::rows(&rows.to_string()).unwrap();
    }
    a.view = View::Dest(CALENDAR_DEST);
    a.came_from = vec![View::Home];
    a.today = Some((2026, 10, 20));
    let mut b = Buffer::empty(Rect::new(0, 0, WIDTH, HEIGHT));
    spark_dialog::ui::draw(&a, &pal, "Tue 20 Oct \u{b7} 18:40", &mut b);
    let frame = ds_frame(&b, &pal, "calendar: the time in large figures, the months, the reminders", None);
    let head = "<!-- @dsCard group=\"Calendar\" height=860 width=720 subtitle=\"the Calendar from v0.90's own render: the time in large figures, the months, then the reminders as rows\" -->\n<style>body{margin:0;background:var(--bg);color:var(--fg);font:16px/19px var(--font-mono);padding:12px}.d{display:flex;flex-wrap:wrap;gap:24px;align-items:flex-start}</style>\n";
    std::fs::write(file, format!("{}<div class=\"d\">{}</div>\n<script></script>\n", head, frame)).unwrap();
}
