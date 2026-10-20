//! The drawing: one grid the terminal's size (60 by 40 cells as made), every character a cell, every
//! color a slot of the palette. No frame. The header's one row (the title, the progress, the date and
//! the time, close); the prompt of two rows; what a key does now; the content (the exchange, the newest
//! turn first, then the view's list), scrolled as it needs; a rule; the footer's controls (Attach, the
//! model, the mic).

use crate::app::{App, Item, Mode, Sign, Talk, View, DESTS, MIN_HEIGHT, MIN_WIDTH, PLACEHOLDER, SETTINGS};
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
pub const BELOW: &str = "\u{2193}";
pub const ABOVE: &str = "\u{2191}";
pub const MORE: &str = "\u{203a}";
pub const MENU: &str = "\u{2304}";
pub const RULE: &str = "\u{2500}";
/// A color's sample: two full blocks, about a square in a terminal cell's shape.
pub const SAMPLE: &str = "\u{2588}\u{2588}";
pub const SEP: &str = " \u{b7} ";
/// The rows: the prompt's two, the attachment's (air above and below it), what a key does, where the
/// content starts (the last two two rows lower while a file is attached).
pub const PROMPT_Y: u16 = 2;
pub const ATTACH_Y: u16 = 5;
pub const HINT_Y: u16 = 5;
pub const CONTENT_Y: u16 = 7;
/// The bottom: air, the rule, the footer, air.
pub const BOTTOM: u16 = 4;
/// Where a destination's purpose starts, past the longest name (Connections).
pub const PURPOSE_X: u16 = 16;
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
    w: u16,
    h: u16,
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
    /// Text at (x, y) in a color; returns the column after it; nothing past the grid.
    fn put(&mut self, x: u16, y: u16, text: &str, fg: Color, bold: bool, lit: bool) -> u16 {
        if x >= self.w || y >= self.h {
            return x;
        }
        let room = (self.w - x) as usize;
        let t = cut(text, room);
        let st = self.style(fg, bold, lit);
        self.buf.set_string(x, y, &t, st);
        x + cells(&t) as u16
    }
    /// A key, as a chip: the only thing drawn as one.
    fn chip(&mut self, x: u16, y: u16, text: &str, focus: bool) -> u16 {
        if x >= self.w || y >= self.h {
            return x;
        }
        let st = if focus {
            Style::default().fg(self.pal.surface).bg(self.pal.accent)
        } else {
            Style::default().fg(self.pal.fg).bg(self.pal.lit)
        };
        let t = cut(&format!(" {} ", text), (self.w - x) as usize);
        self.buf.set_string(x, y, &t, st);
        x + cells(&t) as u16
    }
    /// A control (Attach, the model, Talk, the mic, Remove): plain text, for it is no key. The one Tab
    /// focuses is lit; one that is on (a file attached, listening) is in the accent. A cell of air each
    /// side, lit with it, so the place a click takes is the place drawn.
    fn control(&mut self, x: u16, y: u16, text: &str, focus: bool, on: bool, quiet: bool) -> u16 {
        if x >= self.w || y >= self.h {
            return x;
        }
        let fg = if on {
            self.pal.accent
        } else if quiet {
            self.pal.muted
        } else {
            self.pal.fg
        };
        let mut st = Style::default().fg(fg);
        if focus {
            st = st.bg(self.pal.lit);
        }
        let t = cut(&format!(" {} ", text), (self.w - x) as usize);
        self.buf.set_string(x, y, &t, st);
        x + cells(&t) as u16
    }
    fn light(&mut self, y: u16) {
        for x in 0..self.w {
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

/// The cells the mark takes in the header, for main.rs to draw the sixel into.
pub fn mark_at(app: &App) -> Option<(u16, u16)> {
    (app.cfg.mark && app.view == View::About).then_some((2, 0))
}

/// Where things landed, for a click: the cursor, each pickable row's line and its index, each
/// control's cells and row, close, the prompt's rows.
#[derive(Clone, Debug, Default)]
pub struct Drawn {
    pub cursor: (u16, u16),
    pub picks: Vec<(u16, usize)>,
    pub chips: Vec<(u16, u16, u16, usize)>,
    pub close: Option<(u16, u16)>,
    pub prompt: (u16, u16),
}

/// The draft as the prompt shows it: its lines, each wrapped to `w` cells, and where the cursor is in
/// them (row, cells from the row's start).
pub fn draft_rows(text: &str, cursor: usize, w: usize) -> (Vec<String>, (usize, usize)) {
    let w = w.max(1);
    let mut rows: Vec<String> = vec![];
    let mut at = (0, 0);
    let mut n = 0; // characters before the row being built
    for line in text.split('\n') {
        let mut row = String::new();
        let mut row_start = n;
        for c in line.chars() {
            let cw = cells(&c.to_string());
            if cells(&row) + cw > w {
                rows.push(std::mem::take(&mut row));
                row_start = n;
            }
            if n == cursor {
                at = (rows.len(), cells(&row));
            }
            row.push(c);
            n += 1;
        }
        if n == cursor {
            at = (rows.len(), cells(&row));
            if cells(&row) >= w {
                // the cursor after a full row sits at the start of the next
                rows.push(std::mem::take(&mut row));
                at = (rows.len(), 0);
            }
        }
        let _ = row_start;
        rows.push(row);
        n += 1; // the newline
    }
    (rows, at)
}

/// The local date and time as the person's locale writes them; main.rs makes it, this draws it.
pub fn draw(app: &App, pal: &Palette, clock: &str, buf: &mut Buffer) -> Drawn {
    let mut drawn = Drawn::default();
    let (w, h) = (buf.area.width, buf.area.height);
    let area = Rect::new(0, 0, w, h);
    buf.set_style(area, Style::default().fg(pal.fg));
    let mut pen = Pen { buf, pal, w, h };
    if w < MIN_WIDTH || h < MIN_HEIGHT {
        // too small to hold the prompt, a list and the footer without cutting one: say so, plainly
        let t = "Make this window larger";
        pen.put(w.saturating_sub(cells(t) as u16) / 2, h / 2, t, pal.muted, false, false);
        return drawn;
    }

    // the header: the title, its state; then the march, the date and the time, close
    let mut x = 2;
    if let Some((mx, my)) = mark_at(app) {
        for dx in 0..MARK_CELLS {
            pen.buf[(mx + dx, my)].set_diff_option(CellDiffOption::Skip);
        }
        x = mx + MARK_CELLS + 1;
    }
    let right = if app.cfg.close { w - 3 } else { w - 1 };
    if app.cfg.close {
        pen.put(w - 3, 0, CLOSE, pal.muted, false, false);
        drawn.close = Some((w - 4, w - 1));
    }
    // the march sits before the date while something runs; where the window is too narrow for both,
    // it takes the date's place, which comes back when the work is done
    let clock_x = right.saturating_sub(2 + cells(clock) as u16);
    let busy = app.cfg.progress && app.busy();
    let title = app.title();
    let narrow = clock_x.saturating_sub(12) < x + cells(&title) as u16 + 1;
    let (end, march_x) = match (busy, narrow) {
        (false, _) => (clock_x, None),
        (true, false) => (clock_x - 12, Some(clock_x - 12)),
        (true, true) => (right.saturating_sub(12), Some(right.saturating_sub(12))),
    };
    x = pen.put(x, 0, &cut(&title, end.saturating_sub(x + 1) as usize), pal.fg, true, false);
    let sub = app.subtitle();
    if !sub.is_empty() && end > x + 5 {
        // two cells of air before the date: a long state is cut, never run into it
        let sep = if app.view == View::About { " " } else { SEP };
        pen.put(x, 0, &cut(&format!("{}{}", sep, sub), (end - x - 2) as usize), pal.muted, false, false);
    }
    match march_x {
        Some(mx) => {
            pen.put(mx, 0, &march(app.frame), pal.muted, false, false);
            if !narrow {
                pen.put(clock_x, 0, clock, pal.muted, false, false);
            }
        }
        None => {
            pen.put(clock_x, 0, clock, pal.muted, false, false);
        }
    }

    // the prompt: two rows; a longer draft scrolls inside them
    let tx = 4;
    let tw = (w - tx - 3) as usize;
    pen.put(2, PROMPT_Y, PROMPT, pal.accent, true, false);
    let masked = matches!(&app.mode, Mode::Ask { masked: true, .. });
    let shown: String = if masked {
        "\u{2022}".repeat(app.input.chars().count())
    } else {
        app.input.clone()
    };
    let (rows, (cr, cc)) = draft_rows(&shown, app.cursor, tw);
    let top = cr.saturating_sub(1).min(rows.len().saturating_sub(2));
    drawn.prompt = (PROMPT_Y, PROMPT_Y + 1);
    if app.input.is_empty() && app.mode == Mode::Normal {
        pen.put(tx, PROMPT_Y, PLACEHOLDER, pal.muted, false, false);
    } else {
        for (k, r) in rows.iter().skip(top).take(2).enumerate() {
            pen.put(tx, PROMPT_Y + k as u16, r, pal.fg, false, false);
        }
        if top > 0 {
            pen.put(w - 2, PROMPT_Y, ABOVE, pal.muted, false, false);
        }
        if top + 2 < rows.len() {
            pen.put(w - 2, PROMPT_Y + 1, BELOW, pal.muted, false, false);
        }
    }
    drawn.cursor = (tx + cc as u16, PROMPT_Y + (cr - top) as u16);

    // the file attached, for the next question alone, and its Remove
    if let Some(a) = &app.attachment {
        let name = cut(a.rsplit('/').next().unwrap_or(""), (w / 3) as usize);
        let x = pen.put(tx, ATTACH_Y, &name, pal.fg, false, false);
        let x0 = x + 2;
        let e = pen.control(x0, ATTACH_Y, "Remove", app.chip_focus == Some(4), false, false);
        drawn.chips.push((x0, e, ATTACH_Y, 4));
        let said = "Text or Markdown, next question only";
        let said = if e + 3 + cells(said) as u16 <= w - 2 { said } else { "next question only" };
        if e + 3 + cells(said) as u16 <= w - 2 {
            pen.put(w - 2 - cells(said) as u16, ATTACH_Y, said, pal.muted, false, false);
        }
    }

    // what a key does now; a row lower when a file is attached, so air stays between them
    let shift = if app.attachment.is_some() { 2 } else { 0 };
    let hint_y = HINT_Y + shift;
    let mut x = 2;
    for (t, key) in app.hint() {
        x = if key {
            pen.chip(x, hint_y, &t, false)
        } else {
            pen.put(x, hint_y, &t, pal.muted, false, false)
        };
    }

    // the content
    let bottom = h - BOTTOM;
    let content_y = CONTENT_Y + shift;
    if app.view == View::About {
        about(app, &mut pen, content_y, bottom);
    } else {
        let mut top = content_y;
        if app.is_calendar() {
            top = calendar(app, &mut pen, content_y, bottom) + 1;
        }
        drawn.picks = content(app, &mut pen, top, bottom);
    }

    // the rule, then the footer: Attach, the model, Talk at the left; the mic at the right
    for x in 2..w - 2 {
        pen.put(x, h - 3, RULE, pal.lit, false, false);
    }
    footer(app, &mut pen, h - 2, &mut drawn);
    drawn
}

fn footer(app: &App, pen: &mut Pen, y: u16, drawn: &mut Drawn) {
    let w = pen.w;
    let chips = app.chips();
    let mic = if app.mode == Mode::Listening { "Listening" } else { "Mic off" };
    // the mic while talk is click to talk; how talk works is a setting
    let mic_on = app.cfg.talk && app.talk == Talk::Click;
    let mic_w = if mic_on { cells(mic) as u16 + 2 } else { 0 };
    let mut x = 1;
    if chips.contains(&0) {
        let e = pen.control(x, y, "Attach", app.chip_focus == Some(0), app.attachment.is_some(), false);
        drawn.chips.push((x, e, y, 0));
        x = e + 1;
    }
    if app.cfg.model && app.model_name.is_some() {
        let room = (w.saturating_sub(x + mic_w + 6)) as usize;
        let full = app.model_name.clone().unwrap_or_default();
        // the model's whole name, or the word for it where the name does not fit whole
        let name = format!("{} {}", if cells(&full) + 2 <= room { full.as_str() } else { "Model" }, MENU);
        let e = pen.control(x, y, &name, app.chip_focus == Some(1), false, false);
        drawn.chips.push((x, e, y, 1));
    }
    if mic_on {
        let mx = w - 1 - mic_w;
        let live = chips.contains(&3);
        let e = pen.control(mx, y, mic, app.chip_focus == Some(3), app.mode == Mode::Listening, true);
        if live {
            drawn.chips.push((mx, e, y, 3));
        }
    }
}

/// One content row: what it shows, lit when it is the row picked.
/// A list's columns: their widths, which line up on their right edge, whether rows carry a sample.
type Cols<'a> = (&'a [usize], &'a [bool], bool);

fn item_line(app: &App, pen: &mut Pen, it: &Item, y: u16, lit: bool, cols: Cols) {
    let (widths, right, samples) = cols;
    let pal = pen.pal.clone();
    let w = pen.w;
    match it {
        Item::Heading(h) => {
            pen.put(2, y, h, pal.muted, false, false);
        }
        Item::Blank => {}
        Item::Said(s, text, first) => {
            let (ind, sg, sc, tc) = match s {
                Sign::You => (2, PROMPT, pal.muted, pal.muted),
                Sign::Done => (4, CHECK, pal.accent, pal.fg),
                Sign::Refused => (4, CROSS, pal.alarm, pal.fg),
                Sign::Says => (4, "*", pal.accent, pal.fg),
                Sign::Step => (4, OPENS, pal.muted, pal.muted),
            };
            if *first {
                pen.put(ind, y, sg, sc, false, false);
            }
            pen.put(ind + 2, y, text, tc, false, false);
        }
        Item::Undo => {
            let line = app.undo.as_ref().map(|u| u.line.trim_start_matches("undo ").to_string()).unwrap_or_default();
            let x = pen.put(6, y, "Undo", pal.fg, false, lit);
            pen.put(x, y, &format!("  {}", line), pal.muted, false, lit);
        }
        Item::Proposal(i) => {
            if let Some(s) = app.proposals.get(*i) {
                pen.put(4, y, OPENS, pal.accent, false, lit);
                pen.put(6, y, &s.line, pal.fg, false, lit);
            }
        }
        Item::Dest(d) => {
            pen.put(2, y, DESTS[*d].name, pal.fg, false, lit);
            pen.put(PURPOSE_X, y, &cut(DESTS[*d].purpose, (w - PURPOSE_X - 4) as usize), pal.muted, false, lit);
            pen.put(w - 3, y, MORE, pal.muted, false, lit);
        }
        Item::Setting(i) => {
            let (label, name, purpose) = SETTINGS[*i];
            pen.put(2, y, name, pal.fg, false, lit);
            // a section's own state reads better than its purpose where it has one (on, a level, a name)
            let state = if label == "talk" {
                Some(if app.talk == Talk::Off { "Off" } else { "Click the mic" }.to_string())
            } else {
                app.providers
                    .iter()
                    .find(|p| p.label == label)
                    .map(|p| p.title.clone())
                    .filter(|t| !t.is_empty() && label != "about")
            };
            let words = state.unwrap_or_else(|| purpose.to_string());
            pen.put(PURPOSE_X, y, &cut(&words, (w - PURPOSE_X - 4) as usize), pal.muted, false, lit);
            pen.put(w - 3, y, MORE, pal.muted, false, lit);
        }
        Item::Title(t) => {
            pen.put(2, y, t, pal.fg, false, false);
        }
        Item::Text(t, muted) => {
            pen.put(2, y, t, if *muted { pal.muted } else { pal.fg }, false, false);
        }
        Item::Model(i) => {
            let (n, st) = &app.models[*i];
            let (g, c, said) = match st.as_str() {
                "serving" => (DOT, pal.accent, "in use"),
                "downloaded" => (RING, pal.fg, "installed"),
                _ => (" ", pal.muted, "not downloaded"),
            };
            pen.put(4, y, g, c, false, lit);
            let x = pen.put(6, y, n, if st == "-" { pal.muted } else { pal.fg }, false, lit);
            pen.put(x, y, &format!("{}{}", SEP, said), pal.muted, false, lit);
        }
        Item::TalkOpt(t) => {
            let on = app.talk == *t;
            let (g, c) = if on { (DOT, pal.accent) } else { (RING, pal.fg) };
            pen.put(4, y, g, c, false, lit);
            let words = if *t == Talk::Click { "Click the mic to talk" } else { "Off" };
            pen.put(6, y, words, if app.voice_on { pal.fg } else { pal.muted }, false, lit);
        }
        Item::Conn(k) => {
            if *k == 0 {
                pen.put(4, y, DOT, pal.accent, false, false);
                let at = match &app.server {
                    Some(s) => format!("your spark server, {}", s),
                    None => "this computer".to_string(),
                };
                let x = pen.put(6, y, &cut(&at, (w - 18) as usize), pal.fg, false, false);
                pen.put(x, y, &format!("{}in use", SEP), pal.muted, false, false);
            } else {
                let x = pen.put(6, y, "another server, a cloud provider", pal.muted, false, false);
                pen.put(
                    x,
                    y,
                    &cut(&format!("{}not yet", SEP), (w.saturating_sub(x + 2)) as usize),
                    pal.muted,
                    false,
                    false,
                );
            }
        }
        Item::Provider(i) => {
            let p = &app.providers[*i];
            pen.put(4, y, &p.label, pal.fg, false, false);
            pen.put(PURPOSE_X, y, "this computer, spark-shell", pal.muted, false, false);
        }
        Item::OpenModels => {
            let name = app.model_name.clone().unwrap_or_else(|| "spark".into());
            let x = pen.put(4, y, &name, pal.fg, false, lit);
            let at = match &app.server {
                Some(s) => s.clone(),
                None => "this computer".to_string(),
            };
            pen.put(x, y, &cut(&format!("{}{}", SEP, at), (w.saturating_sub(x + 4)) as usize), pal.muted, false, lit);
            pen.put(w - 3, y, MORE, pal.muted, false, lit);
        }
        Item::Row(p, r) => row_line(pen, &app.providers[*p].rows.rows[*r], y, lit, widths, right, samples),
        Item::Folder(i) => {
            if let Some(row) = app.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)) {
                row_line(pen, row, y, lit, widths, right, samples);
            }
        }
    }
}

fn content(app: &App, pen: &mut Pen, top: u16, bottom: u16) -> Vec<(u16, usize)> {
    let mut at = vec![];
    let items = app.items();
    let picks: Vec<usize> = items.iter().enumerate().filter(|(_, it)| app.pickable_item(it)).map(|(i, _)| i).collect();
    let selected = if app.in_list { picks.get(app.sel).copied() } else { None };
    let all = bottom.saturating_sub(top) as usize;
    // a list longer than the area keeps its last line to say how many rows sit below
    let room = if items.len() > all { all.saturating_sub(1) } else { all };
    // the picked row in view; else where Page Up and Page Down left it
    let mut first = app.scroll.min(items.len().saturating_sub(room));
    if let Some(s) = selected {
        first = first.min(s);
        if s >= first + room {
            first = s + 1 - room;
        }
    }
    let pal = pen.pal.clone();
    let below = items
        .iter()
        .skip(first + room)
        .filter(|it| !matches!(it, Item::Heading(_) | Item::Blank))
        .count();
    if below > 0 {
        let y = top + room as u16;
        pen.put(4, y, BELOW, pal.muted, false, false);
        pen.put(6, y, &format!("{} more", below), pal.muted, false, false);
    }
    let (widths, right) = widths(app, &items);
    let samples = items
        .iter()
        .any(|it| matches!(it, Item::Row(p, r) if app.providers[*p].rows.rows[*r].swatch.is_some()));
    for (k, it) in items.iter().enumerate().skip(first).take(room) {
        let y = top + (k - first) as u16;
        let lit = Some(k) == selected;
        if let Some(n) = picks.iter().position(|i| *i == k) {
            at.push((y, n));
        }
        if lit {
            pen.light(y);
        }
        item_line(app, pen, it, y, lit, (&widths, &right, samples));
    }
    at
}

/// A cell that starts or ends with a figure: a size, a count, a time.
fn figure(col: &str) -> bool {
    col.chars().next().is_some_and(|c| c.is_ascii_digit()) || col.chars().last().is_some_and(|c| c.is_ascii_digit())
}

/// The widths of a list's columns: the name, then each column, so they line up (the name 26 cells at most);
/// and per column whether every cell in it is a figure, so the column lines up on its right edge.
fn widths(app: &App, items: &[Item]) -> (Vec<usize>, Vec<bool>) {
    let mut w: Vec<usize> = vec![];
    let mut right: Vec<bool> = vec![];
    for it in items {
        let row = match it {
            Item::Row(p, r) => &app.providers[*p].rows.rows[*r],
            Item::Folder(i) => match app.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)) {
                Some(r) => r,
                None => continue,
            },
            _ => continue,
        };
        if row.columns.is_empty() {
            continue;
        }
        let cols = std::iter::once(cells(&row.text).min(26)).chain(row.columns.iter().map(|c| cells(c)));
        for (k, c) in cols.enumerate() {
            if w.len() <= k {
                w.push(0);
            }
            w[k] = w[k].max(c);
        }
        for (k, col) in row.columns.iter().enumerate() {
            if right.len() <= k {
                right.push(true);
            }
            right[k] = right[k] && figure(col);
        }
    }
    (w, right)
}

/// One row: its sign at 4, its text at 6, its columns lined up (the first right-aligned, a size; the rest left), its arrow when it opens more.
/// A row: its sign at 4, its text at 6, or at 9 in a list where rows carry a color's sample, the sample at 6.
fn row_line(pen: &mut Pen, row: &crate::model::Row, y: u16, lit: bool, widths: &[usize], right: &[bool], samples: bool) {
    let pal = pen.pal.clone();
    let (g, c) = sign(&pal, &row.sign);
    pen.put(4, y, g, c, false, lit);
    let tx = if samples { 9 } else { 6 };
    if let Some([r, gr, b]) = row.swatch {
        pen.put(6, y, SAMPLE, Color::Rgb(r, gr, b), false, lit);
    }
    let name = if row.columns.is_empty() { row.text.clone() } else { cut(&row.text, 26) };
    let mut x = pen.put(tx, y, &name, pal.fg, false, lit);
    if !row.columns.is_empty() && !widths.is_empty() {
        x = tx + widths[0] as u16;
        for (k, col) in row.columns.iter().enumerate() {
            let w = widths.get(k + 1).copied().unwrap_or(0) as u16;
            let cw = cells(col) as u16;
            // a size, a count or a time lines up on its right edge; words (a palette's name) on their left
            let numeric = right.get(k).copied().unwrap_or(false); // a column of sizes, counts or times: its right edge
            let at = if k == 0 && numeric {
                x + 2 + w.saturating_sub(cw)
            } else if k == 0 {
                x + 2
            } else {
                x + 3
            };
            pen.put(at, y, col, pal.muted, false, lit);
            x = if k == 0 { x + 2 + w } else { x + 3 + w };
        }
    }
    if row.children.is_some() && row.text != ".." {
        pen.put(x, y, " \u{203a}", pal.muted, false, lit);
    }
}

/// Where the Calendar's two months start.
const MONTH_X: [u16; 2] = [2, 32];

/// The Calendar's months: this month and the next side by side, today a chip and a day with a
/// reminder in the accent; left and right move both. The time is the header's. The reminders, to add,
/// mark done or snooze, are the content's rows below. Returns the row after the months.
fn calendar(app: &App, pen: &mut Pen, top: u16, bottom: u16) -> u16 {
    use crate::calendar::{shift, weeks, ymd, DAYS, MONTHS};
    let pal = pen.pal.clone();
    // the reminders provider's rows that are for a day
    let dated: Vec<(i32, u32, u32)> = app
        .providers
        .iter()
        .find(|p| p.label == "reminders")
        .map(|p| p.rows.rows.iter().filter_map(|r| ymd(r.date.as_deref()?)).collect())
        .unwrap_or_default();
    let Some((ty, tm, td)) = app.today else { return top };
    // two months side by side where they fit, else this month alone
    let two = pen.w >= MONTH_X[1] + 28;
    let mut low = top;
    for (k, x0) in MONTH_X.iter().enumerate().take(if two { 2 } else { 1 }) {
        let (yr, mo) = shift(ty, tm, app.month_offset + k as i32);
        let mut y = top;
        pen.put(*x0, y, &format!("{} {}", MONTHS[(mo - 1) as usize], yr), pal.muted, false, false);
        y += 1;
        for (i, d) in DAYS.iter().enumerate() {
            pen.put(x0 + i as u16 * 4, y, d, pal.muted, false, false);
        }
        y += 1;
        for wk in weeks(yr, mo) {
            if y >= bottom {
                break;
            }
            for (i, d) in wk.iter().enumerate() {
                let Some(d) = d else { continue };
                let x = x0 + i as u16 * 4;
                let n = format!("{:>2}", d);
                if (yr, mo, *d) == (ty, tm, td) {
                    pen.chip(x - 1, y, &n, false); // today, a cell of air each side
                } else if dated.contains(&(yr, mo, *d)) {
                    pen.put(x, y, &n, pal.accent, true, false);
                } else {
                    pen.put(x, y, &n, pal.fg, false, false);
                }
            }
            y += 1;
        }
        low = low.max(y);
    }
    low
}

/// The about: the keys, each a chip and its sentence, in their groups; under them the version with
/// its licence, and the address. A sentence with no key (the media keys, typing exit) stays in
/// `spark-shell desktop keys` and the README, not here.
fn about(app: &App, pen: &mut Pen, top: u16, bottom: u16) {
    let pal = pen.pal.clone();
    let w = pen.w;
    let Some(i) = app.about_idx else { return };
    let p = &app.providers[i];
    let keys_end = bottom.saturating_sub(3); // a blank row, the version, the address
    let mut y = top;
    let mut group: Option<String> = None;
    for r in &p.rows.rows {
        let Some(key) = r.columns.first() else { continue };
        if r.tool.is_some() || r.children.is_some() || y >= keys_end {
            continue;
        }
        if r.group != group && group.is_some() {
            y += 1;
        }
        group = r.group.clone();
        pen.chip(2, y, key, false);
        for (k, part) in wrap(&r.text, (w - ABOUT_COL - 2) as usize).into_iter().enumerate() {
            if k > 0 {
                y += 1;
            }
            if y >= keys_end {
                break;
            }
            pen.put(ABOUT_COL, y, &part, pal.fg, false, false);
        }
        y += 1;
    }
    let y = (y + 1).min(keys_end + 1);
    let x = pen.put(2, y, &format!("spark-shell {}", p.version), pal.fg, false, false);
    pen.put(x, y, &format!("{}MIT", SEP), pal.muted, false, false);
    if let Some(addr) = p.rows.rows.iter().find(|r| r.id == "about:address") {
        pen.put(2, y + 1, &addr.text, pal.accent, false, false);
    }
}

/// A rendered buffer as text and tokens: the 60 characters of each row,
/// then one line of two codes a cell -- the text's slot (f fg, m muted,
/// a accent, r alarm, s surface, l lit: the rule; upper case when bold) and the ground
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
        } else if c == pal.lit {
            'l'
        } else {
            '?'
        }
    };
    let mut text = String::new();
    let mut codes = String::new();
    for y in 0..buf.area.height {
        let mut skip_next = 0;
        for x in 0..buf.area.width {
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
            // a color's sample is the data's color, not a palette slot: w
            let mut f = if c.symbol() == "\u{2588}" && slot(c.fg) == '?' { 'w' } else { slot(c.fg) };
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

/// A rendered buffer as an HTML page in its real colors, for a person to
/// look at before a golden is kept (the tests write it under RENDER_HTML).
pub fn html(buf: &Buffer, pal: &Palette, caption: &str) -> String {
    let hex = |c: Color, d: Color| match if c == Color::Reset { d } else { c } {
        Color::Rgb(r, g, b) => format!("#{:02x}{:02x}{:02x}", r, g, b),
        _ => "inherit".into(),
    };
    let esc = |s: &str| s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    let mut out = format!(
        "<div><p style=\"color:{};font-size:13px;margin:0 0 8px\">{}</p><div style=\"background:{};padding:19px 2ch;white-space:pre;width:{}ch;line-height:19px\">",
        hex(pal.muted, pal.muted),
        esc(caption),
        hex(pal.surface, pal.surface),
        buf.area.width
    );
    for y in 0..buf.area.height {
        let mut skip = 0;
        for x in 0..buf.area.width {
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
