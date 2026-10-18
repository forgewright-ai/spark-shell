//! The drawing: one 60 by 44 grid, every character a cell, every colour
//! a slot of the palette. No frame. The header's one row (the mark, the
//! title, the progress, close), the provider's rows, the exchange above
//! the hint (newest nearest the composer), the prompt, the chips.

use crate::app::{App, Item, Mode, Sign, View, HEIGHT, WIDTH};
use crate::palette::Palette;
use crate::scrub::{cells, cut};
use ratatui::buffer::{Buffer, CellDiffOption};
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};

pub const DOT: &str = "\u{25cf}";
pub const RING: &str = "\u{25cb}";
pub const CHECK: &str = "\u{2713}";
pub const CROSS: &str = "\u{2717}";
pub const OPENS: &str = "\u{25b8}";
pub const PROMPT: &str = "\u{276f}";
pub const CLOSE: &str = "\u{d7}";
pub const SEP: &str = " \u{b7} ";
/// The bottom: a row of air, the hint, air, the prompt, air, the chips.
pub const BOTTOM: u16 = 6;
/// The cells the mark takes in the header: it is one row tall and about 1.4 rows wide.
pub const MARK_CELLS: u16 = 3;
/// The about's sentence column, past the longest key chip.
pub const ABOUT_COL: u16 = 21;
/// The march, ten cells, while a step runs or a provider reads.
pub fn march(frame: u64) -> String {
    let i = (frame % 8) as usize;
    let mut cells = [' '; 8];
    cells[i] = '=';
    format!("[{}]", cells.iter().collect::<String>())
}

struct Pen<'a> {
    buf: &'a mut Buffer,
    pal: &'a Palette,
}

impl Pen<'_> {
    fn style(&self, fg: Color, bold: bool, lit: bool) -> Style {
        let mut s = Style::default().fg(fg);
        if bold {
            s = s.add_modifier(Modifier::BOLD);
        }
        if lit {
            s = s.bg(self.pal.lit);
        }
        s
    }
    /// Text at (x, y) in a colour; returns the column after it; nothing past the grid.
    fn put(&mut self, x: u16, y: u16, text: &str, fg: Color, bold: bool, lit: bool) -> u16 {
        if x >= WIDTH || y >= HEIGHT {
            return x;
        }
        let room = (WIDTH - x) as usize;
        let t = cut(text, room);
        let st = self.style(fg, bold, lit);
        self.buf.set_string(x, y, &t, st);
        x + cells(&t) as u16
    }
    fn chip(&mut self, x: u16, y: u16, text: &str, focus: bool) -> u16 {
        let st = if focus {
            Style::default().fg(self.pal.surface).bg(self.pal.accent)
        } else {
            Style::default().fg(self.pal.fg).bg(self.pal.lit)
        };
        let t = format!(" {} ", text);
        self.buf.set_string(x, y, &t, st);
        x + cells(&t) as u16
    }
    fn light(&mut self, y: u16) {
        for x in 0..WIDTH {
            let c = &mut self.buf[(x, y)];
            c.set_bg(self.pal.lit);
        }
    }
}

fn sign(pal: &Palette, s: &str) -> (&'static str, Color) {
    match s {
        "dot" => (DOT, pal.accent),
        "ring" => (RING, pal.fg),
        "check" => (CHECK, pal.accent),
        "cross" => (CROSS, pal.alarm),
        "opens" => (OPENS, pal.fg),
        _ => (" ", pal.fg),
    }
}

/// Words wrapped to `w` cells, a long word cut.
pub fn wrap(text: &str, w: usize) -> Vec<String> {
    let mut out = vec![];
    let mut line = String::new();
    for word in text.split_whitespace() {
        let word = cut(word, w);
        if !line.is_empty() && cells(&line) + 1 + cells(&word) > w {
            out.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(&word);
    }
    if !line.is_empty() {
        out.push(line);
    }
    out
}

/// The exchange as drawn rows: (indent, sign, its colour, text, text colour, the undo after it).
fn exchange_rows(app: &App, pal: &Palette) -> Vec<(u16, &'static str, Color, String, Color, bool)> {
    let mut out = vec![];
    let last_undo = app.undo.as_ref().map(|_| app.exchange.iter().rposition(|l| l.undo)).unwrap_or(None);
    for (i, l) in app.exchange.iter().enumerate() {
        let (ind, sg, sc, tc) = match l.sign {
            Sign::You => (2, PROMPT, pal.muted, pal.muted),
            Sign::Done => (4, CHECK, pal.accent, pal.fg),
            Sign::Refused => (4, CROSS, pal.alarm, pal.fg),
            Sign::Says => (4, "*", pal.accent, pal.fg),
            Sign::Step => (4, OPENS, pal.muted, pal.muted),
        };
        let undo = l.undo && Some(i) == last_undo;
        let room = (WIDTH - ind - 2) as usize - if undo { SEP.len() + 2 } else { 0 };
        for (k, part) in wrap(&l.text, room).into_iter().enumerate() {
            out.push((ind, if k == 0 { sg } else { " " }, sc, part, tc, false));
        }
        if undo {
            if let Some(r) = out.last_mut() {
                r.5 = true;
            }
        }
    }
    let n = out.len();
    if n > crate::app::EXCHANGE_MAX {
        out.drain(..n - crate::app::EXCHANGE_MAX);
    }
    out
}

/// The cells the mark takes in the header, for main.rs to draw the sixel into.
pub fn mark_at(app: &App) -> Option<(u16, u16)> {
    (app.cfg.mark && app.view == View::About).then_some((2, 0))
}

/// Where things landed, for a click: the cursor, each pickable row's line and its index, each chip's cells.
#[derive(Clone, Debug, Default)]
pub struct Drawn {
    pub cursor: (u16, u16),
    pub picks: Vec<(u16, usize)>,
    pub chips: Vec<(u16, u16, usize)>,
}

pub fn draw(app: &App, pal: &Palette, clock: &str, buf: &mut Buffer) -> Drawn {
    let mut drawn = Drawn::default();
    let area = Rect::new(0, 0, WIDTH, HEIGHT);
    buf.set_style(area, Style::default().fg(pal.fg));
    let mut pen = Pen { buf, pal };

    // the header
    let mut x = 2;
    if let Some((mx, my)) = mark_at(app) {
        for dx in 0..MARK_CELLS {
            pen.buf[(mx + dx, my)].set_diff_option(CellDiffOption::Skip);
        }
        x = mx + MARK_CELLS + 1;
    }
    x = pen.put(x, 0, &app.title(clock), pal.fg, true, false);
    let sub = app.subtitle();
    if !sub.is_empty() {
        let sep = if app.view == View::About { " " } else { SEP };
        let room = WIDTH.saturating_sub(x + 16) as usize;
        pen.put(x, 0, &cut(&format!("{}{}", sep, sub), room), pal.muted, false, false);
    }
    if app.cfg.close {
        pen.put(WIDTH - 1, 0, CLOSE, pal.muted, false, false);
    }
    if app.cfg.progress && app.busy() {
        pen.put(WIDTH - 13, 0, &march(app.frame), pal.muted, false, false);
    }

    // the exchange, then the content above it
    let ex = exchange_rows(app, pal);
    let bottom_top = HEIGHT - BOTTOM;
    let ex_top = if ex.is_empty() { bottom_top } else { bottom_top - 1 - ex.len() as u16 };
    for (k, (ind, sg, sc, text, tc, undo)) in ex.iter().enumerate() {
        let y = ex_top + k as u16;
        let x = pen.put(*ind, y, sg, *sc, false, false);
        let x = pen.put(x + 1, y, text, *tc, false, false);
        if *undo {
            pen.put(x, y, &format!("{}undo", SEP), pal.muted, false, false);
        }
    }
    let content_bottom = if ex.is_empty() { bottom_top } else { ex_top.saturating_sub(1) };
    if app.view == View::About {
        about(app, &mut pen, content_bottom);
    } else {
        drawn.picks = content(app, &mut pen, 2, content_bottom);
    }

    // the hint
    let hy = bottom_top + 1;
    let mut x = 2;
    for (t, key) in app.hint() {
        x = if key {
            pen.chip(x, hy, &t, false)
        } else {
            pen.put(x, hy, &t, pal.muted, false, false)
        };
    }

    // the prompt
    let py = bottom_top + 3;
    let x = pen.put(2, py, PROMPT, pal.accent, true, false) + 1;
    let masked = matches!(&app.mode, Mode::Ask { masked: true, .. });
    let shown: String = if masked {
        "\u{2022}".repeat(app.input.chars().count())
    } else {
        app.input.clone()
    };
    let room = (WIDTH - x - 2) as usize;
    let tail: String = {
        let w = cells(&shown);
        if w <= room {
            shown
        } else {
            let mut s: Vec<char> = shown.chars().collect();
            while cells(&s.iter().collect::<String>()) > room {
                s.remove(0);
            }
            s.into_iter().collect()
        }
    };
    let cursor_x = pen.put(x, py, &tail, pal.fg, false, false);

    // the chips: plus at the left, the model in the middle, talk at the right
    let cy = HEIGHT - 1;
    let chips = app.chips();
    if chips.contains(&0) {
        let e = pen.chip(2, cy, "+", app.chip_focus == Some(0));
        drawn.chips.push((2, e, 0));
    }
    if chips.contains(&1) {
        let name = app.model_name.clone().unwrap_or_default();
        let name = cut(&name, 30);
        let w = cells(&name) as u16 + 2;
        let e = pen.chip((WIDTH - w) / 2, cy, &name, app.chip_focus == Some(1));
        drawn.chips.push(((WIDTH - w) / 2, e, 1));
    }
    if chips.contains(&2) {
        let t = if app.mode == Mode::Listening { "listening" } else { "talk" };
        let w = cells(t) as u16 + 2;
        let e = pen.chip(WIDTH - 2 - w, cy, t, app.chip_focus == Some(2) || app.mode == Mode::Listening);
        drawn.chips.push((WIDTH - 2 - w, e, 2));
    }
    drawn.cursor = (cursor_x, py);
    drawn
}

fn content(app: &App, pen: &mut Pen, top: u16, bottom: u16) -> Vec<(u16, usize)> {
    let mut at = vec![];
    let items = app.items();
    let picks: Vec<usize> = items.iter().enumerate().filter(|(_, it)| app.picks().contains(it)).map(|(i, _)| i).collect();
    let selected = picks.get(app.sel).copied();
    let room = bottom.saturating_sub(top) as usize;
    // scroll so the selected row is in view, its heading too when it fits
    let mut first = 0usize;
    if let Some(s) = selected {
        if s >= room {
            first = s + 1 - room;
        }
    }
    let pal = pen.pal.clone();
    for (k, it) in items.iter().enumerate().skip(first).take(room) {
        let y = top + (k - first) as u16;
        let lit = Some(k) == selected;
        if let Some(n) = picks.iter().position(|i| *i == k) {
            at.push((y, n));
        }
        if lit {
            pen.light(y);
        }
        match it {
            Item::Heading(h) => {
                pen.put(2, y, h, pal.muted, false, false);
            }
            Item::Blank => {}
            Item::Undo => {
                let line = app.undo.as_ref().map(|u| u.line.trim_start_matches("undo ").to_string()).unwrap_or_default();
                pen.put(4, y, " ", pal.fg, false, lit);
                pen.put(6, y, &line, pal.fg, false, lit);
            }
            Item::Model(i) => {
                let (n, st) = &app.models[*i];
                let (g, c) = if st == "serving" { (DOT, pal.accent) } else { (RING, pal.fg) };
                pen.put(4, y, g, c, false, lit);
                let x = pen.put(6, y, n, pal.fg, false, lit);
                if st == "serving" {
                    pen.put(x, y, &format!("{}in use", SEP), pal.muted, false, lit);
                }
            }
            Item::Row(p, r) => {
                let row = &app.providers[*p].rows.rows[*r];
                let (g, c) = sign(&pal, &row.sign);
                pen.put(4, y, g, c, false, lit);
                let mut x = pen.put(6, y, &row.text, pal.fg, false, lit);
                for col in &row.columns {
                    x = pen.put(x + 3, y, col, pal.muted, false, lit);
                }
                if row.children.is_some() {
                    pen.put(x, y, " \u{203a}", pal.muted, false, lit);
                }
            }
        }
    }
    at
}

fn about(app: &App, pen: &mut Pen, bottom: u16) {
    let pal = pen.pal.clone();
    let Some(i) = app.about_idx else { return };
    let p = &app.providers[i];
    let mut y = 2;
    if !p.title.is_empty() {
        pen.put(2, y, &p.title, pal.muted, false, false);
        y += 2;
    }
    let mut group: Option<String> = None;
    for r in &p.rows.rows {
        if r.tool.is_some() || r.children.is_some() {
            continue;
        }
        if y >= bottom {
            break;
        }
        if r.group != group && group.is_some() {
            y += 1;
        }
        group = r.group.clone();
        if let Some(key) = r.columns.first() {
            pen.chip(2, y, key, false);
            for (k, part) in wrap(&r.text, (WIDTH - ABOUT_COL - 2) as usize).into_iter().enumerate() {
                if k > 0 {
                    y += 1;
                }
                if y >= bottom {
                    break;
                }
                pen.put(ABOUT_COL, y, &part, pal.fg, false, false);
            }
        } else if r.sign == "opens" {
            let x = pen.put(2, y, "MIT", pal.muted, false, false);
            let x = pen.put(x, y, SEP, pal.muted, false, false);
            pen.put(x, y, &r.text, pal.accent, false, false);
        } else {
            for (k, part) in wrap(&r.text, (WIDTH - 4) as usize).into_iter().enumerate() {
                if k > 0 {
                    y += 1;
                }
                pen.put(2, y, &part, pal.fg, false, false);
            }
        }
        y += 1;
    }
}

/// A rendered buffer as text and tokens: the 60 characters of each row,
/// then one line of two codes a cell -- the text's slot (f fg, m muted,
/// a accent, r alarm, s surface; upper case when bold) and the ground
/// (. the surface, l lit, a accent). A cell the mark takes is #.
pub fn snapshot(buf: &Buffer, pal: &Palette) -> String {
    let slot = |c: Color| -> char {
        if c == pal.fg || c == Color::Reset {
            'f'
        } else if c == pal.muted {
            'm'
        } else if c == pal.accent {
            'a'
        } else if c == pal.alarm {
            'r'
        } else if c == pal.surface {
            's'
        } else {
            '?'
        }
    };
    let mut text = String::new();
    let mut codes = String::new();
    for y in 0..HEIGHT {
        let mut skip_next = 0;
        for x in 0..WIDTH {
            let c = &buf[(x, y)];
            if skip_next > 0 {
                skip_next -= 1;
            } else if c.diff_option == CellDiffOption::Skip {
                text.push('#');
            } else {
                let sym = c.symbol();
                text.push_str(if sym.is_empty() { " " } else { sym });
                skip_next = cells(sym).saturating_sub(1);
            }
            let mut f = slot(c.fg);
            if c.modifier.contains(Modifier::BOLD) {
                f = f.to_ascii_uppercase();
            }
            let g = if c.bg == pal.lit {
                'l'
            } else if c.bg == pal.accent {
                'a'
            } else {
                '.'
            };
            codes.push(f);
            codes.push(g);
        }
        text.push('\n');
        codes.push('\n');
    }
    format!("{}\n{}", text, codes)
}

/// A rendered buffer as an HTML page in its real colours, for a person to
/// look at before a golden is kept (the tests write it under RENDER_HTML).
pub fn html(buf: &Buffer, pal: &Palette, caption: &str) -> String {
    let hex = |c: Color, d: Color| match if c == Color::Reset { d } else { c } {
        Color::Rgb(r, g, b) => format!("#{:02x}{:02x}{:02x}", r, g, b),
        _ => "inherit".into(),
    };
    let esc = |s: &str| s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    let mut out = format!(
        "<div><p style=\"color:{};font-size:13px;margin:0 0 8px\">{}</p><div style=\"background:{};padding:19px 2ch;white-space:pre;width:60ch;line-height:19px\">",
        hex(pal.muted, pal.muted),
        esc(caption),
        hex(pal.surface, pal.surface)
    );
    for y in 0..HEIGHT {
        let mut skip = 0;
        for x in 0..WIDTH {
            let c = &buf[(x, y)];
            if skip > 0 {
                skip -= 1;
                continue;
            }
            let sym = if c.diff_option == CellDiffOption::Skip { "\u{2593}" } else { c.symbol() };
            skip = cells(sym).saturating_sub(1);
            let bold = if c.modifier.contains(Modifier::BOLD) { "font-weight:700;" } else { "" };
            out.push_str(&format!(
                "<span style=\"color:{};background:{};{}display:inline-block;width:{}ch\">{}</span>",
                hex(c.fg, pal.fg),
                hex(c.bg, pal.surface),
                bold,
                cells(sym).max(1),
                esc(if sym.is_empty() { " " } else { sym })
            ));
        }
        out.push('\n');
    }
    out.push_str("</div></div>");
    out
}
