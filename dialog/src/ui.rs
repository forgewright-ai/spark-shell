//! The drawing: one grid the terminal's size (60 by 40 cells as made), every character a cell, every
//! color a slot of the palette. No frame. The header's one row (the title, the progress, the date and
//! the time, close); the prompt of two rows; what a key does now; the content (the exchange, the newest
//! turn first, then the view's list), scrolled as it needs; a rule; the footer's controls (Attach, the
//! model, the mic).

use crate::app::{App, HintKey, Item, Mode, Sign, Talk, View, DESTS, MIN_HEIGHT, MIN_WIDTH, PLACEHOLDER, SETTINGS, SETTINGS_DEST, WIDTH};
use crate::palette::Palette;
use crate::progress;
use crate::scrub::{cells, cut, cut_words};
use crate::sixel::Viewport;
use crate::transition::Reel;
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
/// The rows the prompt grows to for a longer draft: commands spark planned are all in sight before
/// Enter runs them (#53); past this the draft scrolls inside them.
pub const PROMPT_MAX: usize = 5;
pub const ATTACH_Y: u16 = 5;
pub const HINT_Y: u16 = 5;
pub const CONTENT_Y: u16 = 7;
/// The bottom: air, the rule, the footer, air.
pub const BOTTOM: u16 = 4;
/// Where a destination's purpose starts: past the longest name (Notifications) and two cells of air.
pub const PURPOSE_X: u16 = 17;
/// A palette's chip: a small terminal in the palette's own colors, this many cells wide.
pub const CHIP: u16 = 9;
/// A picture beside a list (a wallpaper's), in cells: about 16 by 9 in a 9 by 18 pixel cell.
pub const PREVIEW_W: u16 = 24;
pub const PREVIEW_H: u16 = 7;
pub const LESS: &str = "\u{2039}";
struct Pen<'a> {
    buf: &'a mut Buffer,
    pal: &'a Palette,
    w: u16,
    h: u16,
    /// Rows y0..y1 end at x: a picture sits right of them.
    stop: Option<(u16, u16, u16)>,
    /// A wide list's right edge (#141): its band, its arrows and the toast's Undo end where its words end, never at the
    /// screen's edge.
    right: u16,
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
    fn end(&self, y: u16) -> u16 {
        match self.stop {
            Some((y0, y1, x)) if y >= y0 && y < y1 => x.min(self.right),
            _ => self.w.min(self.right),
        }
    }
    fn put(&mut self, x: u16, y: u16, text: &str, fg: Color, bold: bool, lit: bool) -> u16 {
        if x >= self.end(y) || y >= self.h {
            return x;
        }
        let room = (self.end(y) - x) as usize;
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
        for x in 0..self.end(y).min(self.w) {
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

/// Where things landed, for a click: the cursor, each pickable row's line and its index, each
/// control's cells and row, close, the prompt's rows.
#[derive(Clone, Debug, Default)]
pub struct Drawn {
    pub cursor: (u16, u16),
    pub picks: Vec<(u16, usize)>,
    pub chips: Vec<(u16, u16, u16, usize)>,
    pub keys: Vec<(u16, u16, u16, HintKey)>,
    pub close: Option<(u16, u16)>,
    pub prompt: (u16, u16),
    /// A picture to draw beside the list, or a preview's page.
    pub preview: Option<Picture>,
    /// A preview's text, the pages it takes at this size (#120).
    pub pages: usize,
    /// A sound's waveform, its cells (x, y, w, h): a click there plays from that point.
    pub wave: Option<(u16, u16, u16, u16)>,
    /// A transition playing (#122): its cells (x, y, w, h), which one, and since when.
    pub film: Option<(u16, u16, u16, u16, Reel, std::time::Instant)>,
    /// An animation beside a list (#132): its box (x, y, w, h in cells) and the piece's folder, main.rs plays it.
    pub side_film: Option<(u16, u16, u16, u16, String)>,
    /// The toast's Undo and its x (#133): their cells (x0, x1, y), for a click.
    pub toast_undo: Option<(u16, u16, u16)>,
    pub toast_close: Option<(u16, u16, u16)>,
    /// The dialog's own column, its first cell and the cell after its last (#131): a click's row is its list's only there.
    pub columns: (u16, u16),
    /// The opening plays alone (#142): nothing else drawn, no cursor.
    pub alone: bool,
    /// The back arrow's cells (x0, x1) on the header's row, for a click (#147).
    pub back: Option<(u16, u16)>,
}

/// A picture main.rs draws in sixel over cells the buffer skips: where (x, y, w, h in cells), its file,
/// how it is shown, and whether it is a sound's spectrogram (the lower part of its file, in the palette).
#[derive(Clone, Debug, PartialEq)]
pub struct Picture {
    pub x: u16,
    pub y: u16,
    pub w: u16,
    pub h: u16,
    pub file: String,
    pub view: Viewport,
    pub spectrogram: bool,
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
            // Literal text fields retain tabs and may carry CR from a native
            // value. Draw their escapes, never terminal control characters.
            let shown = match c {
                '\t' => "\\t".to_string(),
                '\r' => "\\r".to_string(),
                _ => c.to_string(),
            };
            let cw = cells(&shown);
            if cells(&row) + cw > w {
                rows.push(std::mem::take(&mut row));
                row_start = n;
            }
            if n == cursor {
                at = (rows.len(), cells(&row));
            }
            row.push_str(&shown);
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

/// Full screen (#141): one flow, the dialog's own column as wide as a list's columns want, this many cells at most, in
/// the middle of the screen; nothing beside or under it, nothing stretched to the screen's edge.
pub const FULL_WIDTH: u16 = 120;

/// The width the dialog's own column has at this size: its words wrap to it.
pub fn column_width(w: u16, _h: u16) -> u16 {
    w.min(FULL_WIDTH)
}

/// A column wider than the dialog's own size: a list there shows its rows' wide columns and whole names (#141).
pub fn wide(w: u16) -> bool {
    w > WIDTH
}

impl Drawn {
    /// Every place moved right by `dx` cells: the column drawn apart, then laid at its place on the screen.
    fn shift(&mut self, dx: u16) {
        self.cursor.0 += dx;
        for c in &mut self.chips {
            c.0 += dx;
            c.1 += dx;
        }
        for k in &mut self.keys {
            k.0 += dx;
            k.1 += dx;
        }
        self.close = self.close.map(|(a, b)| (a + dx, b + dx));
        self.back = self.back.map(|(a, b)| (a + dx, b + dx));
        if let Some(p) = self.preview.as_mut() {
            p.x += dx;
        }
        self.wave = self.wave.map(|(x, y, w, h)| (x + dx, y, w, h));
        self.film = self.film.map(|(x, y, w, h, r, t)| (x + dx, y, w, h, r, t));
        if let Some(s) = self.side_film.as_mut() {
            s.0 += dx;
        }
        self.toast_undo = self.toast_undo.map(|(a, b, y)| (a + dx, b + dx, y));
        self.toast_close = self.toast_close.map(|(a, b, y)| (a + dx, b + dx, y));
        self.columns = (self.columns.0 + dx, self.columns.1 + dx);
    }
}

/// `part`'s cells laid on `buf` with its corner at (x, y), each as it is, the cells a picture keeps included.
fn blit(buf: &mut Buffer, part: &Buffer, x: u16, y: u16) {
    for yy in 0..part.area.height {
        for xx in 0..part.area.width {
            if x + xx < buf.area.width && y + yy < buf.area.height {
                buf[(x + xx, y + yy)] = part[(xx, yy)].clone();
            }
        }
    }
}

/// The local date and time as the person's locale writes them; main.rs makes it, this draws it.
pub fn draw(app: &App, pal: &Palette, clock: &str, buf: &mut Buffer) -> Drawn {
    let (w, h) = (buf.area.width, buf.area.height);
    buf.set_style(Rect::new(0, 0, w, h), Style::default().fg(pal.fg));
    // the opening, and the wait after it while the home loads, play alone in the middle of the window: nothing
    // else is drawn until they end, then the whole dialog at once (#142)
    if let Some((reel @ (Reel::Open | Reel::Wait), since)) = app.motion {
        let mut drawn = Drawn {
            alone: true,
            ..Drawn::default()
        };
        let (x, y, bw, bh) = (2, 2, w.saturating_sub(4), h.saturating_sub(4));
        for yy in y..(y + bh).min(h) {
            for xx in x..(x + bw).min(w) {
                buf[(xx, yy)].set_diff_option(CellDiffOption::Skip);
            }
        }
        drawn.film = Some((x, y, bw, bh, reel, since));
        return drawn;
    }
    // a preview opened on Space keeps the whole screen: its zoom and its drag want the room (#120); elsewhere the column
    // in the middle (#141)
    let cw = if app.view == View::Preview { w } else { column_width(w, h) };
    if cw == w {
        let mut d = draw_column(app, pal, clock, buf);
        d.columns = (0, w);
        return d;
    }
    let x = (w - cw) / 2;
    let mut col = Buffer::empty(Rect::new(0, 0, cw, h));
    let mut drawn = draw_column(app, pal, clock, &mut col);
    blit(buf, &col, x, 0);
    drawn.shift(x);
    drawn.columns = (x, x + cw);
    drawn
}

/// The dialog's own column.
fn draw_column(app: &App, pal: &Palette, clock: &str, buf: &mut Buffer) -> Drawn {
    let mut drawn = Drawn::default();
    let (w, h) = (buf.area.width, buf.area.height);
    let area = Rect::new(0, 0, w, h);
    buf.set_style(area, Style::default().fg(pal.fg));
    let mut pen = Pen {
        buf,
        pal,
        w,
        h,
        stop: None,
        right: w,
    };
    if w < MIN_WIDTH || h < MIN_HEIGHT {
        // too small to hold the prompt, a list and the footer without cutting one: say so, plainly
        let t = "Make this window larger";
        pen.put(w.saturating_sub(cells(t) as u16) / 2, h / 2, t, pal.muted, false, false);
        return drawn;
    }

    // the header: the back arrow where there is somewhere to go back to (#147), the title, its state; then the march,
    // the date and the time, close
    let mut x = 2;
    if app.goes_back() {
        pen.put(2, 0, LESS, pal.muted, false, false);
        drawn.back = Some((1, 4));
        x = 4;
    }
    let right = if app.cfg.close { w - 3 } else { w - 1 };
    if app.cfg.close {
        pen.put(w - 3, 0, CLOSE, pal.muted, false, false);
        drawn.close = Some((w - 4, w - 1));
    }
    // the march sits before the date while something runs; where the window is too narrow for both,
    // it takes the date's place, which comes back when the work is done
    let clock_x = right.saturating_sub(2 + cells(clock) as u16);
    let busy = app.cfg.progress && app.thinking();
    let title = app.title();
    let narrow = clock_x.saturating_sub(12) < x + cells(&title) as u16 + 1;
    let (end, march_x) = match (busy, narrow) {
        (false, _) => (clock_x, None),
        (true, false) => (clock_x - 12, Some(clock_x - 12)),
        (true, true) => (right.saturating_sub(12), Some(right.saturating_sub(12))),
    };
    x = pen.put(x, 0, &cut_words(&title, end.saturating_sub(x + 1) as usize), pal.fg, true, false);
    let sub = app.subtitle();
    if !sub.is_empty() && end > x + 5 {
        // two cells of air before the date: a long state is cut, never run into it
        pen.put(x, 0, &cut_words(&format!("{}{}", SEP, sub), (end - x - 2) as usize), pal.muted, false, false);
    }
    match march_x {
        Some(mx) => {
            pen.put(mx, 0, &progress::bar(app.work(), app.frame), pal.muted, false, false);
            if !narrow {
                pen.put(clock_x, 0, clock, pal.muted, false, false);
            }
        }
        None => {
            pen.put(clock_x, 0, clock, pal.muted, false, false);
        }
    }

    // the prompt: two rows, up to PROMPT_MAX for a longer draft; past that it scrolls inside them
    let tx = 4;
    let tw = (w - tx - 3) as usize;
    pen.put(2, PROMPT_Y, PROMPT, pal.accent, true, false);
    let masked = matches!(&app.mode, Mode::Ask { masked: true, .. }) || matches!(&app.mode, Mode::Pair { kind, .. } if kind == "pin" || kind == "passkey");
    let shown: String = if masked {
        "\u{2022}".repeat(app.input.chars().count())
    } else {
        app.input.clone()
    };
    let (rows, (cr, cc)) = draft_rows(&shown, app.cursor, tw);
    let n = rows.len().clamp(2, PROMPT_MAX);
    let grow = (n - 2) as u16;
    let top = cr.saturating_sub(n - 1).min(rows.len().saturating_sub(n));
    drawn.prompt = (PROMPT_Y, PROMPT_Y + n as u16 - 1);
    if app.input.is_empty() && app.mode == Mode::Normal {
        pen.put(tx, PROMPT_Y, PLACEHOLDER, pal.muted, false, false);
    } else {
        for (k, r) in rows.iter().skip(top).take(n).enumerate() {
            pen.put(tx, PROMPT_Y + k as u16, r, pal.fg, false, false);
        }
        if top > 0 {
            pen.put(w - 2, PROMPT_Y, ABOVE, pal.muted, false, false);
        }
        if top + n < rows.len() {
            pen.put(w - 2, PROMPT_Y + n as u16 - 1, BELOW, pal.muted, false, false);
        }
    }
    drawn.cursor = (tx + cc as u16, PROMPT_Y + (cr - top) as u16);

    // the file attached, for the next question alone, and its Remove
    if let Some(a) = &app.attachment {
        let name = cut(a.rsplit('/').next().unwrap_or(""), (w / 3) as usize);
        let ay = ATTACH_Y + grow;
        let x = pen.put(tx, ay, &name, pal.fg, false, false);
        let x0 = x + 2;
        let e = pen.control(x0, ay, "Remove", app.chip_focus == Some(4), false, false);
        drawn.chips.push((x0, e, ay, 4));
        let said = "Text or Markdown, next question only";
        let said = if e + 3 + cells(said) as u16 <= w - 2 { said } else { "next question only" };
        if e + 3 + cells(said) as u16 <= w - 2 {
            pen.put(w - 2 - cells(said) as u16, ay, said, pal.muted, false, false);
        }
    }

    // what a key does now; a row lower when a file is attached, so air stays between them
    let shift = (if app.attachment.is_some() { 2 } else { 0 }) + grow;
    let hint_y = HINT_Y + shift;
    let target = app.target_label();
    if let Some(t) = &target {
        pen.put(2, hint_y + 2, &cut_words(t, (w - 4) as usize), pal.muted, false, false);
    }
    let shift = shift + if target.is_some() { 2 } else { 0 };

    // the content first: a preview's text decides the pages its key row offers
    let bottom = h - BOTTOM;
    let content_y = CONTENT_Y + shift;
    if let Some((reel, since)) = app.motion {
        // a transition: the content area is its, in its middle (main.rs draws it)
        let (x, y, w, h) = (2, content_y, pen.w.saturating_sub(4), bottom.saturating_sub(content_y));
        skip(
            &mut pen,
            Picture {
                x,
                y,
                w,
                h,
                file: String::new(),
                view: Viewport::FIT,
                spectrogram: false,
            },
        );
        drawn.film = Some((x, y, w, h, reel, since));
    } else if app.view == View::About {
        about(app, &mut pen, content_y, bottom);
    } else if app.view == View::Preview {
        let (picks, picture, pages) = preview(app, &mut pen, content_y, bottom, &mut drawn);
        drawn.picks = picks;
        drawn.preview = picture;
        drawn.pages = pages;
    } else {
        let mut top = content_y;
        if app.is_calendar() {
            top = calendar(app, &mut pen, clock, content_y, bottom) + 1;
        }
        let (picks, preview) = content(app, &mut pen, top, bottom, &mut drawn);
        drawn.picks = picks;
        drawn.preview = preview;
    }

    // the key row keeps to the content's width: where it would pass the margin (Open, Preview,
    // Actions and Back on a file, #127) the gaps between its keys close to two cells
    let mut hint = app.hint_with(drawn.pages.max(1));
    let span = |v: &[(String, bool)]| v.iter().map(|(t, k)| cells(t) + if *k { 2 } else { 0 }).sum::<usize>();
    while span(&hint) > w.saturating_sub(4) as usize {
        let mut closed = false;
        for (t, k) in hint.iter_mut() {
            if !*k && t.len() > 2 && t.chars().all(|c| c == ' ') {
                t.pop();
                closed = true;
            }
        }
        if !closed {
            break;
        }
    }
    let mut x = 2;
    for (t, key) in hint {
        let start = x;
        x = if key {
            pen.chip(x, hint_y, &t, false)
        } else {
            pen.put(x, hint_y, &t, pal.muted, false, false)
        };
        if key && start < x && x <= w && hint_y < h {
            // a chip of one key, or of a few (the arrows, + -, < >): each key its share of the chip
            let parts: Vec<HintKey> = t.split(' ').filter_map(key_of).collect();
            if parts.len() == t.split(' ').count() {
                let n = parts.len() as u16;
                for (k, a) in parts.into_iter().enumerate() {
                    let k = k as u16;
                    drawn.keys.push((start + (x - start) * k / n, start + (x - start) * (k + 1) / n, hint_y, a));
                }
            }
        }
    }

    // the rule, then the footer: Attach, the model, Talk at the left; the mic at the right
    for x in 2..w - 2 {
        pen.put(x, h - 3, RULE, pal.lit, false, false);
    }
    footer(app, &mut pen, h - 2, &mut drawn);
    drawn
}

/// The action of a key named on a chip.
fn key_of(k: &str) -> Option<HintKey> {
    Some(match k {
        "Enter" => HintKey::Enter,
        "Esc" => HintKey::Escape,
        "Shift+Enter" => HintKey::Newline,
        "Tab" => HintKey::Tab,
        "\u{2190}" => HintKey::Left,
        "\u{2192}" => HintKey::Right,
        "\u{2191}" => HintKey::Up,
        "\u{2193}" => HintKey::Down,
        "+" | "-" | "<" | ">" => HintKey::Char(k.chars().next()?),
        // Space previews the lit file, its chip as clickable as the others (#150)
        "Space" => HintKey::Char(' '),
        _ => return None,
    })
}

fn footer(app: &App, pen: &mut Pen, y: u16, drawn: &mut Drawn) {
    let w = pen.w;
    let chips = app.chips();
    let mic = if app.mode == Mode::Listening { "Listening" } else { "Mic" };
    // the mic while talk is click to talk; how talk works is a setting
    let mic_on = app.cfg.talk && app.talk == Talk::Click;
    let mic_w = if mic_on { cells(mic) as u16 + 2 } else { 0 };
    let mut x = 1;
    if let Some(pv) = app.preview.as_ref().filter(|_| app.view == View::Preview) {
        // the file shown goes with the words: Attach names it, in the accent where spark can read it (#120)
        let reads = pv.shown.as_ref().is_some_and(|pg| pg.attach.is_some());
        let name = cut(&pv.row().text, (w / 2) as usize);
        x = pen.control(x, y, &name, false, reads, !reads) + 1;
    } else if chips.contains(&0) {
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

/// A line of the exchange: the command as it ran at the left, in muted after its prompt sign; what came
/// of it under it, after its sign (#53).
fn said_line(pen: &mut Pen, s: &Sign, text: &str, first: bool, y: u16, lit: bool) {
    let pal = pen.pal.clone();
    let (ind, sg, sc, tc) = match s {
        Sign::You => (2, PROMPT, pal.muted, pal.muted),
        Sign::Done => (4, CHECK, pal.accent, pal.fg),
        Sign::Refused => (4, CROSS, pal.alarm, pal.fg),
        Sign::Says => (4, "*", pal.accent, pal.fg),
    };
    if first {
        pen.put(ind, y, sg, sc, false, lit);
    }
    pen.put(ind + 2, y, text, tc, false, lit);
}

/// One content row: what it shows, lit when it is the row picked.
/// A list's columns: their widths, which line up on their right edge, whether rows carry a sample.
type Cols<'a> = (&'a [usize], &'a [bool], bool, bool);

fn item_line(app: &App, pen: &mut Pen, it: &Item, y: u16, lit: bool, cols: Cols) {
    let (widths, right, samples, chips) = cols;
    let pal = pen.pal.clone();
    let w = pen.w;
    match it {
        Item::Ask => {
            let x = pen.put(2, y, "Ask spark", pal.fg, false, lit);
            let words = app.input.trim().replace('\n', " ");
            pen.put(x + 2, y, &cut_words(&words, w.saturating_sub(x + 5) as usize), pal.muted, false, lit);
        }
        Item::Heading(h) => {
            pen.put(2, y, h, pal.muted, false, false);
        }
        Item::Blank | Item::Toast => {}
        Item::Said(s, text, first) => said_line(pen, s, text, *first, y, false),
        Item::Undo(s, text, first) => {
            // the result the undo at hand takes back, with Undo at its end where the rows' signs end (#53)
            said_line(pen, s, text, *first, y, lit);
            pen.put(w.saturating_sub(6), y, "Undo", if lit { pal.fg } else { pal.muted }, false, lit);
        }
        Item::Dest(d) => {
            pen.put(2, y, DESTS[*d].name, pal.fg, false, lit);
            // what the place holds now, else what it is for
            let words = app.dest_state(*d).unwrap_or_else(|| DESTS[*d].purpose.to_string());
            let e = pen.end(y);
            pen.put(
                PURPOSE_X,
                y,
                &cut_words(&words, e.saturating_sub(PURPOSE_X + 4) as usize),
                pal.muted,
                false,
                lit,
            );
            pen.put(e - 3, y, MORE, pal.muted, false, lit);
        }
        Item::Setting(i) => {
            let (label, name, purpose) = SETTINGS[*i];
            // in Settings the rows sit under their groups' headings, as a folder's do (#137); found from the home, beside the places
            let ind = if app.view == View::Dest(SETTINGS_DEST) { 2 } else { 0 };
            pen.put(2 + ind, y, name, pal.fg, false, lit);
            let words = setting_words(app, label, purpose);
            pen.put(
                PURPOSE_X + ind,
                y,
                &cut_words(&words, pen.end(y).saturating_sub(PURPOSE_X + ind + 4) as usize),
                pal.muted,
                false,
                lit,
            );
            let e = pen.end(y);
            pen.put(e - 3, y, MORE, pal.muted, false, lit);
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
        Item::Row(p, r) => row_line(pen, &app.providers[*p].rows.rows[*r], y, lit, widths, right, samples, chips),
        Item::Folder(i) => {
            if let Some(row) = app.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)) {
                row_line(pen, row, y, lit, widths, right, samples, chips);
            }
        }
        Item::StepOf(k) => {
            // one of a row's steps, in the provider's words: a row of its own, no sign
            if let Some(c) = app.steps_row.as_ref().and_then(|r| r.tool.iter().chain(r.more.iter()).nth(*k)) {
                pen.put(6, y, &app.step_words(c), pal.fg, false, lit);
            }
        }
        Item::Here => {
            // the row that lands a step in the folder shown (#112): it opens nothing, it does
            let (g, c) = sign(&pal, "opens");
            pen.put(4, y, g, c, false, lit);
            let what = app.picking.as_ref().map(|pk| pk.what.clone()).unwrap_or_default();
            pen.put(6, y, &what, pal.fg, false, lit);
        }
    }
}

fn pal_muted(pen: &Pen) -> Color {
    pen.pal.muted
}

/// The row an item stands for, where it is a provider's row or a folder's.
fn row_of<'a>(app: &'a App, it: &Item) -> Option<&'a crate::model::Row> {
    match it {
        Item::Row(p, r) => app.providers[*p].rows.rows.get(*r),
        Item::Folder(i) => app.folder.as_ref().and_then(|(_, _, rows)| rows.rows.get(*i)),
        _ => None,
    }
}

type Preview = Option<Picture>;

/// A line folded to `w` cells for a preview: every character kept, an indent too, broken after the
/// last space that fits past the indent, else where it must be.
pub fn fold(text: &str, w: usize) -> Vec<String> {
    let w = w.max(2);
    let mut out = vec![];
    let mut rest = text;
    while cells(rest) > w {
        let head = cut(rest, w);
        if head.is_empty() {
            break; // a character wider than the room: the line as it is, cut where it is drawn
        }
        let indent = head.len() - head.trim_start().len();
        let at = head[indent..].rfind(' ').map(|i| indent + i + 1).unwrap_or(head.len());
        out.push(rest[..at].trim_end().to_string());
        rest = &rest[at..];
    }
    out.push(rest.to_string());
    out
}

/// The preview (#120): what was said and the Ask row first, as in any view; under them the page as
/// large as the area allows, and its facts on the area's last row, muted. Returns the rows to click,
/// the picture to draw, and the pages a text takes at this size.
fn preview(app: &App, pen: &mut Pen, top: u16, bottom: u16, drawn: &mut Drawn) -> (Vec<(u16, usize)>, Preview, usize) {
    let said = app.items().len() as u16;
    let (picks, y) = if said > 0 {
        let end = (top + said).min(bottom.saturating_sub(6));
        (content(app, pen, top, end, drawn).0, end + 1)
    } else {
        (vec![], top)
    };
    let pal = pen.pal.clone();
    let Some(pv) = app.preview.as_ref() else { return (picks, None, 1) };
    let Some(pg) = pv.shown.as_ref() else {
        // a page slow to come: the wait, after a moment, so a quick one never flashes it (#122)
        if app.films && !pv.failed && pv.asked.elapsed() >= std::time::Duration::from_millis(300) && y + 4 < bottom {
            let (x, w, h) = (2, pen.w.saturating_sub(4), bottom - y);
            skip(
                pen,
                Picture {
                    x,
                    y,
                    w,
                    h,
                    file: String::new(),
                    view: Viewport::FIT,
                    spectrogram: false,
                },
            );
            // the opening from its first frame, as it shows, then the wait while the page is still on its way (#142)
            drawn.film = Some((x, y, w, h, Reel::Load, pv.asked + std::time::Duration::from_millis(300)));
        }
        return (picks, None, 1);
    };
    let (x0, w) = (2u16, pen.w.saturating_sub(4));
    let foot = bottom.saturating_sub(1);
    // a blank row between the page and its facts
    let rows = foot.saturating_sub(y + 1);
    let mut facts = vec![];
    let mut pages = 1;
    let mut picture = None;
    if let Some(png) = &pg.picture {
        picture = Some(skip(
            pen,
            Picture {
                x: x0,
                y,
                w,
                h: rows,
                file: png.clone(),
                view: pv.viewport(),
                spectrogram: false,
            },
        ));
        if pg.pages > 1 {
            facts.push(format!("page {} of {}", pg.page, pg.pages));
        }
        facts.extend(pv.percent().map(|p| format!("{}%", p)));
        if pv.turn > 0 {
            facts.push(format!("turned {}\u{b0}", pv.turn as u32 * 90));
        }
    } else if let (Some((file, _)), Some(heard)) = (&pg.sound, &pv.heard) {
        let now = std::time::Instant::now();
        let at = pv.position(now);
        facts.push(format!("{} of {}", clock_of(at), clock_of(pg.seconds)));
        picture = sound(pen, pv, pg, heard, at, (x0, y, w, rows), file, drawn);
    } else if pg.sound.is_some() {
        // a long sound's waveform, still being drawn: its length now, the picture the moment it is there (#124)
        facts.push(format!("{} of {}", clock_of(pv.position(std::time::Instant::now())), clock_of(pg.seconds)));
        for (k, l) in pg.lines.iter().take(rows.saturating_sub(3) as usize).enumerate() {
            pen.put(x0, y + k as u16, &cut_words(l, w as usize), pal.fg, pg.bold.contains(&k), false);
        }
        let t = "drawing the waveform";
        pen.put(x0 + w.saturating_sub(cells(t) as u16) / 2, y + rows / 2, t, pal.muted, false, false);
    } else if let Some(say) = &pg.say {
        // no preview: why, in the middle of the area
        let t = cut_words(say, w as usize);
        pen.put(x0 + w.saturating_sub(cells(&t) as u16) / 2, y + rows / 2, &t, pal.muted, false, false);
    } else {
        // a text: every line folded to the width, a page the area's rows; code numbered in a gutter
        let gutter = if pg.numbered { pg.lines.len().to_string().len() + 2 } else { 0 };
        let tw = (w as usize).saturating_sub(gutter);
        let mut folded = vec![];
        for (i, l) in pg.lines.iter().enumerate() {
            for (k, f) in fold(l, tw).into_iter().enumerate() {
                folded.push((i, f, k == 0));
            }
        }
        let per = (rows as usize).max(1);
        pages = folded.len().div_ceil(per).max(1);
        let page = pv.page.min(pages);
        for (r, (i, f, first)) in folded.iter().skip((page - 1) * per).take(per).enumerate() {
            let yy = y + r as u16;
            if pg.numbered && *first {
                pen.put(x0, yy, &format!("{:>1$}", i + 1, gutter - 2), pal.muted, false, false);
            }
            pen.put(x0 + gutter as u16, yy, f, pal.fg, pg.bold.contains(i), false);
        }
        if pages > 1 {
            facts.push(format!("page {} of {}", page, pages));
        }
    }
    facts.extend(pg.facts.iter().cloned());
    // the facts whole, as many as the row holds, the first ones first
    let mut row = String::new();
    for f in facts {
        let next = if row.is_empty() { f } else { format!("{}{}{}", row, SEP, f) };
        if cells(&next) > w as usize {
            break;
        }
        row = next;
    }
    pen.put(x0, foot, &row, pal.muted, false, false);
    (picks, picture, pages)
}

/// A picture's cells are sixel's: the buffer skips them (main.rs draws it).
fn skip(pen: &mut Pen, p: Picture) -> Picture {
    for yy in p.y..(p.y + p.h).min(pen.h) {
        for xx in p.x..(p.x + p.w).min(pen.w) {
            pen.buf[(xx, yy)].set_diff_option(CellDiffOption::Skip);
        }
    }
    p
}

/// Seconds as a clock: 3:45, 1:02:03.
fn clock_of(s: f64) -> String {
    let s = s.max(0.0) as u64;
    if s >= 3600 {
        format!("{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

/// The eighths of a cell, bottom up: a bar's top.
const EIGHTHS: [&str; 9] = [
    " ", "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2588}",
];
/// A sound's waveform, its spectrum and the rows between them, in cells.
const WAVE_ROWS: u16 = 4;
const BAND_ROWS: u16 = 6;

/// A sound (#120): its lines (the title bold), its waveform (the part played in the accent, the rest
/// muted), its spectrum at the time played (or the whole sound's, stopped), and its spectrogram where
/// the area has room for it.
#[allow(clippy::too_many_arguments)]
fn sound(
    pen: &mut Pen,
    pv: &crate::preview::Preview,
    pg: &crate::preview::Page,
    heard: &crate::preview::Sound,
    at: f64,
    area: (u16, u16, u16, u16),
    file: &str,
    drawn: &mut Drawn,
) -> Preview {
    let pal = pen.pal.clone();
    let (x0, mut y, w, rows) = area;
    let end = y + rows;
    for (i, l) in pg.lines.iter().enumerate() {
        let bold = pg.bold.contains(&i);
        pen.put(x0, y, &cut_words(l, w as usize), if bold || i == 0 { pal.fg } else { pal.muted }, bold, false);
        y += 1;
    }
    y += 1;
    // the waveform: each cell a column's loudest, bottom up in eighths; played in the accent
    let n = heard.wave.len().max(1);
    let played = if pg.seconds > 0.0 { (at / pg.seconds).clamp(0.0, 1.0) } else { 0.0 };
    if y + WAVE_ROWS < end {
        for c in 0..w as usize {
            let (a, b) = (c * n / w as usize, ((c + 1) * n / w as usize).max(c * n / w as usize + 1).min(n));
            let loud = heard.wave[a..b].iter().cloned().fold(0.0f32, f32::max);
            let level = (loud * (WAVE_ROWS * 8) as f32).round().max(1.0) as u16;
            let color = if (c as f64 + 0.5) / w as f64 <= played { pal.accent } else { pal.muted };
            for r in 0..WAVE_ROWS {
                let fill = level.saturating_sub(r * 8).min(8) as usize;
                pen.put(x0 + c as u16, y + WAVE_ROWS - 1 - r, EIGHTHS[fill], color, false, false);
            }
        }
        drawn.wave = Some((x0, y, w, WAVE_ROWS));
        y += WAVE_ROWS + 1;
    }
    // the spectrum: its bands at the time played while it plays, else the whole sound's, low to high
    if y + BAND_ROWS < end {
        let bands: Vec<f32> = if pv.playing.is_some() {
            // between the two columns the time played falls in, blended, so the bars move and never jump (#152)
            let last = heard.bands.len().saturating_sub(1);
            let pos = (played * n as f64).min(last as f64);
            let (col, f) = (pos as usize, (pos - pos.floor()) as f32);
            match (heard.bands.get(col), heard.bands.get((col + 1).min(last))) {
                (Some(a), Some(b)) => a.iter().zip(b.iter()).map(|(x, y)| *x as f32 * (1.0 - f) + *y as f32 * f).collect(),
                _ => vec![],
            }
        } else {
            (0..crate::preview::BANDS)
                .map(|k| heard.bands.iter().map(|b| b[k] as f32).sum::<f32>() / heard.bands.len().max(1) as f32)
                .collect()
        };
        let step = (w as usize / crate::preview::BANDS).max(1);
        let bar = step.saturating_sub(1).max(1);
        let left = x0 + (w as usize - (step * crate::preview::BANDS).min(w as usize)) as u16 / 2;
        for (k, v) in bands.iter().enumerate() {
            let level = (v / 255.0 * (BAND_ROWS * 8) as f32).round() as u16;
            for r in 0..BAND_ROWS {
                let fill = level.saturating_sub(r * 8).min(8) as usize;
                for dx in 0..bar {
                    pen.put(left + (k * step + dx) as u16, y + BAND_ROWS - 1 - r, EIGHTHS[fill], pal.accent, false, false);
                }
            }
        }
        y += BAND_ROWS + 1;
    }
    // the spectrogram, where four rows or more are left
    (y + 4 <= end).then(|| {
        skip(
            pen,
            Picture {
                x: x0,
                y,
                w,
                h: end - y,
                file: file.to_string(),
                view: Viewport::FIT,
                spectrogram: true,
            },
        )
    })
}

fn content(app: &App, pen: &mut Pen, top: u16, bottom: u16, drawn: &mut Drawn) -> (Vec<(u16, usize)>, Preview) {
    let mut at = vec![];
    let items = app.items();
    let picks: Vec<usize> = items.iter().enumerate().filter(|(_, it)| app.pickable_item(it)).map(|(i, _)| i).collect();
    let selected = if app.in_list { picks.get(app.sel).copied() } else { None };
    // the toast, the last item: its own line at the content's bottom with a blank row above it, out of the scroll (#133)
    let toast = matches!(items.last(), Some(Item::Toast)) && bottom >= top + 4;
    let n = if toast { items.len() - 1 } else { items.len() };
    let (end, bottom) = (bottom, if toast { bottom - 2 } else { bottom });
    let all = bottom.saturating_sub(top) as usize;
    // a list longer than the area keeps its last line to say how many rows sit below
    let room = if n > all { all.saturating_sub(1) } else { all };
    // the picked row in view; else where Page Up and Page Down left it
    let mut first = app.scroll.min(n.saturating_sub(room));
    if let Some(s) = selected.filter(|s| *s < n) {
        first = first.min(s);
        if s >= first + room {
            first = s + 1 - room;
        }
    }
    // a list whose rows carry pictures shows the lit row's at the top right, else the one in use; the rows beside it end before it
    let mut preview: Preview = None;
    if items.iter().any(|it| row_of(app, it).is_some_and(|r| r.preview.is_some())) && pen.w >= 2 * PREVIEW_W {
        let lit = selected.and_then(|k| row_of(app, &items[k])).and_then(|r| r.preview.clone());
        let used = items
            .iter()
            .filter_map(|it| row_of(app, it))
            .find(|r| r.sign == "check")
            .and_then(|r| r.preview.clone());
        let lit_row = selected.and_then(|k| row_of(app, &items[k])).filter(|r| r.preview.is_some());
        let used_row = items.iter().filter_map(|it| row_of(app, it)).find(|r| r.sign == "check" && r.preview.is_some());
        // under the picture, the row's columns: a drawing's palette on one line; a file's size and date, then
        // its folder on a second line, since the rows beside the picture have no room for them (#112)
        let caption: Vec<String> = lit_row
            .or(used_row)
            .map(|r| match r.columns.as_slice() {
                [] => vec![],
                [one] => vec![one.clone()],
                [a, b, rest @ ..] => {
                    let mut lines = vec![format!("{}{}{}", a, SEP, b)];
                    lines.extend(rest.iter().take(1).cloned());
                    lines
                }
            })
            .unwrap_or_default();
        // beside the list, from its first row: what was said above it keeps the whole width
        let k0 = items
            .iter()
            .position(|it| matches!(it, Item::Heading(_) | Item::Row(..) | Item::Folder(_)))
            .unwrap_or(0);
        let top = top + k0.saturating_sub(first) as u16;
        if let Some(file) = lit.or(used).filter(|_| top + PREVIEW_H + 1 < bottom) {
            let x = pen.w - 2 - PREVIEW_W;
            preview = Some(Picture {
                x,
                y: top,
                w: PREVIEW_W,
                h: PREVIEW_H,
                file,
                view: Viewport::FIT,
                spectrogram: false,
            });
            // the picture's cells are sixel's: the buffer skips them, as it does the logo's (main.rs draws it)
            for yy in top..(top + PREVIEW_H).min(pen.h) {
                for xx in x..(x + PREVIEW_W).min(pen.w) {
                    pen.buf[(xx, yy)].set_diff_option(CellDiffOption::Skip);
                }
            }
            pen.stop = Some((top, top + PREVIEW_H + 2, x - 2));
            let stop = pen.stop.take();
            for (k, c) in caption.iter().enumerate() {
                pen.put(x, top + PREVIEW_H + k as u16, &cut_words(c, PREVIEW_W as usize), pal_muted(pen), false, false);
            }
            pen.stop = stop;
        }
    }
    // a list whose rows bring an animation (#132): the lit row's plays where a wallpaper's picture is drawn, else the
    // one in use; a lit row with none (no motion) leaves the box empty, the rows beside it ending before it either way
    if preview.is_none() && pen.w >= 2 * PREVIEW_W && items.iter().any(|it| row_of(app, it).is_some_and(|r| r.film.is_some())) {
        let film = match selected.and_then(|k| row_of(app, &items[k])) {
            Some(r) => r.film.clone(),
            None => items
                .iter()
                .filter_map(|it| row_of(app, it))
                .find(|r| r.sign == "check")
                .and_then(|r| r.film.clone()),
        };
        let k0 = items
            .iter()
            .position(|it| matches!(it, Item::Heading(_) | Item::Row(..) | Item::Folder(_)))
            .unwrap_or(0);
        let top = top + k0.saturating_sub(first) as u16;
        let x = pen.w - 2 - PREVIEW_W;
        if top + PREVIEW_H + 1 < bottom {
            if let Some(f) = film {
                for yy in top..(top + PREVIEW_H).min(pen.h) {
                    for xx in x..(x + PREVIEW_W).min(pen.w) {
                        pen.buf[(xx, yy)].set_diff_option(CellDiffOption::Skip);
                    }
                }
                drawn.side_film = Some((x, top, PREVIEW_W, PREVIEW_H, f));
            }
            pen.stop = Some((top, top + PREVIEW_H + 2, x - 2));
        }
    }
    let pal = pen.pal.clone();
    let below = items[..n]
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
    let samples = items.iter().any(|it| row_of(app, it).is_some_and(|r| r.swatch.is_some()));
    // a wide list ends where its words end (#141): its band, its arrows, the toast's Undo
    if wide(pen.w) {
        pen.right = list_end(app, &items[..n], &widths, samples).clamp(WIDTH, pen.w);
    }
    // a group where any row carries a chip keeps the chip's column for every row, so their columns line up
    let chip_groups: Vec<Option<String>> = items
        .iter()
        .filter_map(|it| row_of(app, it))
        .filter(|r| !r.chip.is_empty())
        .map(|r| r.group.clone())
        .collect();
    for (k, it) in items[..n].iter().enumerate().skip(first).take(room) {
        let y = top + (k - first) as u16;
        let lit = Some(k) == selected;
        if let Some(n) = picks.iter().position(|i| *i == k) {
            at.push((y, n));
        }
        if lit {
            pen.light(y);
        }
        let chips = row_of(app, it).is_some_and(|r| chip_groups.contains(&r.group));
        item_line(app, pen, it, y, lit, (&widths, &right, samples, chips));
    }
    pen.stop = None;
    if let (true, Some(t)) = (toast, app.toast.as_ref()) {
        // the receipt's sign at 4 and its words at 6, as a row's; Undo, then the x where the rows' arrows stand
        let (y, k) = (end - 1, items.len() - 1);
        let lit = Some(k) == selected;
        if let Some(i) = picks.iter().position(|i| *i == k) {
            at.push((y, i));
        }
        if lit {
            pen.light(y);
        }
        let (sg, sc) = if t.sign == Sign::Refused { (CROSS, pal.alarm) } else { (CHECK, pal.accent) };
        let close_x = pen.end(y) - 3;
        let undo_x = close_x - 6;
        let undo = t.undo && app.undo.is_some();
        pen.put(4, y, sg, sc, false, lit);
        let room = if undo { undo_x } else { close_x }.saturating_sub(8);
        pen.put(6, y, &cut_words(&t.text, room as usize), pal.fg, false, lit);
        if undo {
            pen.put(undo_x, y, "Undo", if lit { pal.fg } else { pal.muted }, false, lit);
            drawn.toast_undo = Some((undo_x - 1, undo_x + 5, y));
        }
        pen.put(close_x, y, CLOSE, pal.muted, false, lit);
        drawn.toast_close = Some((close_x - 1, close_x + 2, y));
    }
    pen.right = pen.w;
    (at, preview)
}

/// A setting's words: its section's own state, which reads better than its purpose where it has one (on, a level, a
/// name).
fn setting_words(app: &App, label: &str, purpose: &str) -> String {
    let state = if label == "talk" {
        Some(if app.talk == Talk::Off { "Off" } else { "Click the mic" }.to_string())
    } else {
        app.providers
            .iter()
            .find(|p| p.label == label)
            .map(|p| p.title.clone())
            .filter(|t| !t.is_empty())
    };
    state.unwrap_or_else(|| purpose.to_string())
}

/// Where a wide list's words end (#141): a place's or a setting's name and state, a row's name and columns, then its
/// arrow and two cells of air.
fn list_end(app: &App, items: &[Item], widths: &[usize], samples: bool) -> u16 {
    let cols: usize = widths.iter().enumerate().skip(1).map(|(k, w)| w + if k == 1 { 2 } else { 3 }).sum();
    let row = (if samples { 9 } else { 6 }) + widths.first().copied().unwrap_or(0) + cols + 4;
    let words = items
        .iter()
        .filter_map(|it| match it {
            Item::Dest(d) => Some(PURPOSE_X as usize + cells(&app.dest_state(*d).unwrap_or_else(|| DESTS[*d].purpose.to_string())) + 5),
            Item::Setting(i) => Some(PURPOSE_X as usize + 2 + cells(&setting_words(app, SETTINGS[*i].0, SETTINGS[*i].2)) + 5),
            _ => None,
        })
        .max()
        .unwrap_or(0);
    row.max(words) as u16
}

/// A cell that starts or ends with a figure: a size, a count, a time.
fn figure(col: &str) -> bool {
    // an empty folder's count is one too: an empty trash keeps the sizes beside it on their right edge (#130)
    col == "empty" || col.chars().next().is_some_and(|c| c.is_ascii_digit()) || col.chars().last().is_some_and(|c| c.is_ascii_digit())
}

/// The widths of a list's columns: the name, then each column, so they line up (the name 26 cells at most);
/// and per column whether every cell in it is a figure, so the column lines up on its right edge.
fn widths(app: &App, items: &[Item]) -> (Vec<usize>, Vec<bool>) {
    let wide = wide(app.col_w());
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
        if row_columns(row, wide).is_empty() && row.step.is_none() && row.key.is_none() {
            continue;
        }
        let cols = std::iter::once(cells(&row.text).min(name_cap(app.col_w()))).chain(row_columns(row, wide).iter().map(|c| cells(c)));
        for (k, c) in cols.enumerate() {
            if w.len() <= k {
                w.push(0);
            }
            w[k] = w[k].max(c);
        }
        for (k, col) in row_columns(row, wide).iter().enumerate() {
            if right.len() <= k {
                right.push(true);
            }
            right[k] = right[k] && figure(col);
        }
    }
    (w, right)
}

/// A name's cells at most in a list of `w` cells: 26 in the dialog's own size, up to 48 in a wide list (#141), so a long
/// name is whole and its columns still fit.
fn name_cap(w: u16) -> usize {
    if wide(w) {
        (w.saturating_sub(70) as usize).clamp(26, 48)
    } else {
        26
    }
}

/// A row's columns: its wide ones in a wide list where it has them (a file's kind, size, and date with the time,
/// #141), else its own.
fn row_columns(row: &crate::model::Row, wide: bool) -> &[String] {
    match &row.wide {
        Some(c) if wide => c,
        _ => &row.columns,
    }
}

/// One row: its sign at 4, its text at 6, its columns lined up (the first right-aligned, a size; the rest left), its arrow when it opens more.
/// A row: its sign at 4, its text at 6, or at 9 in a list where rows carry a color's sample, the sample at 6.
#[allow(clippy::too_many_arguments)]
fn row_line(pen: &mut Pen, row: &crate::model::Row, y: u16, lit: bool, widths: &[usize], right: &[bool], samples: bool, chips: bool) {
    let pal = pen.pal.clone();
    let (g, c) = sign(&pal, &row.sign);
    pen.put(4, y, g, c, false, lit);
    let tx = if samples { 9 } else { 6 };
    if let Some([r, gr, b]) = row.swatch {
        pen.put(6, y, SAMPLE, Color::Rgb(r, gr, b), false, lit);
    }
    // a file's or a folder's name cut in its middle, its type kept (#140); other rows' at their end; a wide list's whole
    let wide = wide(pen.w);
    let columns = row_columns(row, wide);
    let name = if columns.is_empty() {
        row.text.clone()
    } else if row.id.starts_with("files:") {
        crate::scrub::cut_middle(&row.text, name_cap(pen.w))
    } else {
        cut(&row.text, name_cap(pen.w))
    };
    let mut x = pen.put(tx, y, &name, pal.fg, false, lit);
    let name_end = tx + widths.first().copied().unwrap_or(0) as u16;
    if let Some(st) = &row.step {
        // a value left and right change: the arrows muted, the value in the text color; the accent while lit
        let ac = if lit { pal.accent } else { pal.muted };
        let x0 = name_end + 2;
        let x1 = pen.put(x0, y, LESS, ac, false, lit);
        let x2 = pen.put(x1 + 1, y, &st.value, pal.fg, false, lit);
        pen.put(x2 + 1, y, MORE, ac, false, lit);
        return;
    }
    if !row.chip.is_empty() {
        chip(pen, name_end + 2, y, &row.chip);
    }
    // the key that does what the row does, as a key is drawn everywhere: a chip (#144)
    if let Some(k) = &row.key {
        pen.chip(name_end.max(x) + 2, y, k, false);
    }
    // a row's columns, unless its one column is its picture's caption (the wallpaper list); a file with a picture keeps its size and date (#112)
    if !columns.is_empty() && !widths.is_empty() && (row.preview.is_none() || columns.len() > 1) {
        x = if chips { name_end + CHIP + 2 } else { name_end };
        for (k, col) in columns.iter().enumerate() {
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
            let room = pen.end(y).saturating_sub(at) as usize;
            // a number cut is no number, and beside the picture a column is whole or not drawn at all (nor what follows it);
            // elsewhere words are cut at a word
            let beside = pen.stop.is_some_and(|(y0, y1, _)| y >= y0 && y < y1);
            if (numeric || beside) && cw as usize > room {
                break;
            }
            pen.put(at, y, &cut_words(col, room), pal.muted, false, lit);
            x = if k == 0 { x + 2 + w } else { x + 3 + w };
        }
    }
    if row.children.is_some() && row.text != ".." {
        pen.put(x, y, " \u{203a}", pal.muted, false, lit);
    }
}

/// A palette's chip, CHIP cells on its own ground: a dot in the accent and in each hue after it. A
/// chip's colors are the data's, as a sample's are, never the dialog's own slots. One color alone (the
/// ground, a color for the wallpaper) is a block of that color.
fn chip(pen: &mut Pen, x: u16, y: u16, c: &[[u8; 3]]) {
    let rgb = |v: &[u8; 3]| Color::Rgb(v[0], v[1], v[2]);
    let Some(ground) = c.first().map(rgb) else { return };
    for k in 0..CHIP {
        if x + k >= pen.end(y) || y >= pen.h {
            return;
        }
        let (sym, fg) = match k {
            0 | 8 => (" ", ground),
            _ => (DOT, c.get(k as usize + 1).map(rgb).unwrap_or(ground)),
        };
        let cell = &mut pen.buf[(x + k, y)];
        cell.set_symbol(sym);
        cell.set_fg(fg);
        cell.set_bg(ground);
    }
}

/// A month's cells across, and the air after it: the Calendar's months start at 2, 32, 62 (#141).
const MONTH_STEP: u16 = 30;

/// The time at the end of the header's clock, after the middle dot ("10:24", or "9:05 AM" on a
/// twelve-hour clock): its figures, and AM or PM.
fn time_of(clock: &str) -> Option<(&str, Option<&str>)> {
    let t = clock.rsplit('\u{b7}').next()?.trim();
    let (hm, half) = match t.split_once(' ') {
        Some((a, b)) => (a, Some(b)),
        None => (t, None),
    };
    (hm.contains(':') && hm.chars().all(|c| c.is_ascii_digit() || c == ':')).then_some((hm, half))
}

/// The Calendar: the time in large figures, from the header's clock (#41); then this month and the
/// next side by side, today a chip and a day with a reminder in the accent; left and right move both.
/// The reminders, to add, mark done or snooze, are the content's rows below. Returns the row after
/// the months.
fn calendar(app: &App, pen: &mut Pen, clock: &str, top: u16, bottom: u16) -> u16 {
    use crate::calendar::strokes;
    let pal = pen.pal.clone();
    let mut top = top;
    // the figures where they leave room for a month under them, with a row of air between
    if let Some((hm, half)) = time_of(clock).filter(|_| bottom >= top + 6 + 8) {
        let rows = strokes(hm);
        let wide = rows.first().map(|r| cells(r)).unwrap_or(0) as u16;
        for (k, l) in rows.iter().enumerate() {
            pen.put(2, top + k as u16, l, pal.accent, false, false);
        }
        if let Some(h) = half {
            pen.put(2 + wide + 2, top + rows.len() as u16 - 1, h, pal.muted, false, false);
        }
        top += rows.len() as u16 + 1;
    }
    // as many months side by side as fit: two in the dialog's own size, more in full screen (#141), else this month alone
    let across = (pen.w.saturating_sub(2) + 2) / MONTH_STEP;
    let mut low = top;
    for k in 0..across.max(1) {
        low = low.max(month(app, pen, 2 + k * MONTH_STEP, top, bottom, k as i32).unwrap_or(top));
    }
    low
}

/// One month as weeks at (x0, top), `k` months after the first the Calendar shows: today a chip, a day with a
/// reminder in the accent. Returns the row after it; None before the day is known.
fn month(app: &App, pen: &mut Pen, x0: u16, top: u16, bottom: u16, k: i32) -> Option<u16> {
    use crate::calendar::{shift, weeks_from, ymd, DAYS, MONTHS};
    let pal = pen.pal.clone();
    // the reminders provider's rows that are for a day
    let dated: Vec<(i32, u32, u32)> = app
        .providers
        .iter()
        .find(|p| p.label == "reminders")
        .map(|p| p.rows.rows.iter().filter_map(|r| ymd(r.date.as_deref()?)).collect())
        .unwrap_or_default();
    let (ty, tm, td) = app.today?;
    let (yr, mo) = shift(ty, tm, app.month_offset + k);
    let mut y = top;
    pen.put(x0, y, &format!("{} {}", MONTHS[(mo - 1) as usize], yr), pal.muted, false, false);
    y += 1;
    for i in 0..7 {
        let d = DAYS[(i + usize::from(app.monday_first)) % 7];
        pen.put(x0 + i as u16 * 4, y, d, pal.muted, false, false);
    }
    y += 1;
    for wk in weeks_from(yr, mo, app.monday_first) {
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
    Some(y)
}

/// A key's sentence up to its first comma, colon or semicolon, with no period: the part the about
/// shows on one line (#40). "moves the focus, as h, j, k, l do; Shift moves the window." is "moves
/// the focus".
fn first_part(s: &str) -> &str {
    s[..s.find([',', ':', ';']).unwrap_or(s.len())].trim_end_matches('.').trim()
}

/// The about (#40): spark-shell, its version and licence, and its address; then the keys, each a chip
/// and the first part of its sentence on one line, in their groups, a group whole or not at all; then
/// the command that shows every sentence whole, with the ones that have no key (the media keys,
/// typing exit).
fn about(app: &App, pen: &mut Pen, top: u16, bottom: u16) {
    let pal = pen.pal.clone();
    let w = pen.w;
    let Some(i) = app.about_idx else { return };
    let p = &app.providers[i];
    let x = pen.put(2, top, &format!("spark-shell {}", p.version), pal.fg, false, false);
    pen.put(x, top, &format!("{}MIT", SEP), pal.muted, false, false);
    if let Some(addr) = p.rows.rows.iter().find(|r| r.id == "about:address") {
        pen.put(2, top + 1, &addr.text, pal.accent, false, false);
    }
    let mut groups: Vec<Vec<(&str, &str)>> = vec![];
    let mut group: Option<&Option<String>> = None;
    for r in &p.rows.rows {
        let Some(key) = r.columns.first() else { continue };
        if r.tool.is_some() || r.children.is_some() {
            continue;
        }
        if group != Some(&r.group) {
            groups.push(vec![]);
            group = Some(&r.group);
        }
        if let Some(g) = groups.last_mut() {
            g.push((key, first_part(&r.text)));
        }
    }
    // the sentences line up one cell past the widest chip, and keep 20 cells at least
    let widest = groups.iter().flatten().map(|(k, _)| cells(k) as u16 + 2).max().unwrap_or(0);
    let col = (2 + widest + 1).min(w.saturating_sub(22));
    let last = bottom.saturating_sub(1); // the command's line, a blank row above it
    let mut y = top + 3;
    for g in &groups {
        if y + g.len() as u16 + 1 > last {
            break;
        }
        for (key, said) in g {
            pen.chip(2, y, key, false);
            pen.put(col, y, &cut_words(said, w.saturating_sub(col + 2) as usize), pal.fg, false, false);
            y += 1;
        }
        y += 1;
    }
    pen.put(2, y, "More on the keys: spark-shell desktop keys", pal.muted, false, false);
}

/// A rendered buffer as text and tokens: the 60 characters of each row,
/// then one line of two codes a cell -- the text's slot (f fg, m muted,
/// a accent, r alarm, s surface, l lit: the rule; upper case when bold) and the ground
/// (. the surface, l lit, a accent). A cell a picture takes is #.
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
