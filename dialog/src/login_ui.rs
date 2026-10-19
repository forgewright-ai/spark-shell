//! The login screen's drawing: a strip down the left side of the screen
//! in the panel's ground holds everything, and the rest is left to the
//! terminal's own ground, which foot draws with transparency over the
//! wallpaper. One text column, every color a slot of the palette.

use crate::login::{Field, Login, Note, Power, Session, View};
use crate::palette::Palette;
use crate::scrub::{cells, cut};
use crate::ui::{CROSS, DOT, RING};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};

/// The strip's width, in cells.
pub const STRIP: u16 = 58;
/// The text column, and the column the fields start at.
pub const COL: u16 = 5;
pub const FIELD_COL: u16 = 15;
pub const FIELD_W: u16 = STRIP - COL - FIELD_COL;
pub const BULLET: &str = "\u{2022}";
pub const CURSOR: &str = "\u{258f}";

struct Pen<'a> {
    buf: &'a mut Buffer,
    pal: &'a Palette,
    area: Rect,
}

impl Pen<'_> {
    /// Text at (x, y), cut at the strip's edge; returns the column after it.
    fn put(&mut self, x: u16, y: u16, text: &str, st: Style) -> u16 {
        let edge = self.area.width.min(STRIP.saturating_sub(2));
        if x >= edge || y >= self.area.height {
            return x;
        }
        let t = cut(text, (edge - x) as usize);
        self.buf.set_string(x, y, &t, st);
        x + cells(&t) as u16
    }
    fn fg(&self, c: Color) -> Style {
        Style::default().fg(c).bg(self.pal.surface)
    }
    fn bold(&self, c: Color) -> Style {
        self.fg(c).add_modifier(Modifier::BOLD)
    }
    fn chip(&mut self, x: u16, y: u16, key: &str) -> u16 {
        let st = Style::default().fg(self.pal.fg).bg(self.pal.lit);
        self.put(x, y, &format!(" {} ", key), st)
    }
    /// A key chip and its words: the row of keys a hint is made of.
    fn keys(&mut self, y: u16, keys: &[(&str, &str)]) {
        let mut x = COL;
        for (i, (k, w)) in keys.iter().enumerate() {
            if i > 0 {
                x = self.put(x, y, "   ", self.fg(self.pal.muted));
            }
            x = self.chip(x, y, k);
            x = self.put(x, y, &format!(" {}", w), self.fg(self.pal.muted));
        }
    }
    /// A label on the text column and its field: a run of lit cells, the text in it, the cursor when focused.
    fn field(&mut self, y: u16, label: &str, text: &str, focus: bool) {
        let lc = if focus { self.pal.accent } else { self.pal.muted };
        self.put(COL, y, label, self.fg(lc));
        let lit = Style::default().fg(self.pal.fg).bg(self.pal.lit);
        self.put(FIELD_COL, y, &" ".repeat(FIELD_W as usize), lit);
        let room = FIELD_W.saturating_sub(3) as usize;
        // a long text shows its end, where the typing is
        let n = cells(text);
        let shown: String = if n > room {
            text.chars().skip(text.chars().count() - room).collect()
        } else {
            text.into()
        };
        let x = self.put(FIELD_COL + 1, y, &shown, lit);
        if focus {
            self.put(x, y, CURSOR, Style::default().fg(self.pal.accent).bg(self.pal.lit));
        }
    }
}

/// Where the form starts and where the footer sits on a screen `h` rows tall:
/// at 49 rows the form at 18, spark at 44, the power keys at 46.
pub fn rows(h: u16) -> (u16, u16, u16) {
    let power = h.saturating_sub(3);
    let spark = h.saturating_sub(5);
    let want = h as u32 * 18 / 49;
    let most = spark.saturating_sub(15);
    let form = (want as u16).min(most).max(8);
    (form, spark, power)
}

pub fn draw(l: &Login, pal: &Palette, clock: &str, buf: &mut Buffer) {
    let area = buf.area;
    let strip = Style::default().bg(pal.surface);
    for y in 0..area.height {
        for x in 0..STRIP.min(area.width) {
            buf[(x, y)].set_symbol(" ").set_style(strip);
        }
    }
    let mut p = Pen { buf, pal, area };
    p.put(COL, 3, &l.host, p.bold(pal.fg));
    p.put(COL, 4, &l.distro, p.fg(pal.muted));
    p.put(COL, 6, clock, p.fg(pal.muted));
    let (r0, spark_row, power_row) = rows(area.height);
    match l.view {
        View::Form => {
            p.put(COL, r0, "log in", p.bold(pal.fg));
            p.field(r0 + 3, "user", &l.user, l.field == Field::User);
            let dots = BULLET.repeat(l.busy.unwrap_or(l.password.len()));
            p.field(r0 + 5, "password", &dots, l.field == Field::Password && l.busy.is_none());
            if l.desktop {
                let focus = l.field == Field::Session;
                p.put(COL, r0 + 7, "session", p.fg(if focus { pal.accent } else { pal.muted }));
                let mut x = FIELD_COL + 1;
                for (s, name) in [(Session::Desktop, "desktop"), (Session::Shell, "shell")] {
                    let on = l.session == s;
                    x = p.put(x, r0 + 7, if on { DOT } else { RING }, p.fg(if on { pal.accent } else { pal.muted }));
                    x = p.put(x, r0 + 7, &format!(" {}", name), p.fg(if on { pal.fg } else { pal.muted }));
                    x += 4;
                }
            }
            p.keys(r0 + 13, &[("Tab", "next field"), ("Enter", "log in")]);
        }
        View::Confirm(pw) => {
            let (title, says, verb) = match pw {
                Power::Restart => ("restart", " restarts. Type yes to go on.", "restart"),
                Power::Shutdown => ("shut down", " turns off. Type yes to go on.", "shut down"),
            };
            p.put(COL, r0, title, p.bold(pal.fg));
            let x = p.put(COL, r0 + 3, &l.host, p.fg(pal.fg));
            p.put(x, r0 + 3, says, p.fg(pal.muted));
            p.field(r0 + 5, "confirm", &l.confirm, true);
            p.keys(r0 + 13, &[("Enter", verb), ("Esc", "back")]);
        }
    }
    match &l.note {
        Some(Note::Wrong(t)) => {
            let x = p.put(COL, r0 + 10, CROSS, p.fg(pal.alarm));
            p.put(x, r0 + 10, &format!(" {}", t), p.fg(pal.fg));
        }
        Some(Note::Plain(t)) => {
            p.put(COL, r0 + 10, t, p.fg(pal.muted));
        }
        None => {}
    }
    if let Some(ready) = l.spark {
        let (sign, color, words) = if ready { (DOT, pal.ok, "ready") } else { (RING, pal.muted, "not running") };
        let x = p.put(COL, spark_row, sign, p.fg(color));
        let x = p.put(x, spark_row, " spark", p.fg(pal.fg));
        p.put(x, spark_row, &format!("  {}", words), p.fg(pal.muted));
    }
    let mut power: Vec<(&str, &str)> = vec![];
    let showing = match l.view {
        View::Confirm(pw) => Some(pw),
        View::Form => None,
    };
    if l.can_restart && showing != Some(Power::Restart) {
        power.push(("F11", "restart"));
    }
    if l.can_shutdown && showing != Some(Power::Shutdown) {
        power.push(("F12", "shut down"));
    }
    if !power.is_empty() {
        let mut x = COL;
        for (i, (k, w)) in power.iter().enumerate() {
            if i > 0 {
                x = p.put(x, power_row, "    ", p.fg(pal.muted));
            }
            x = p.chip(x, power_row, k);
            x = p.put(x, power_row, &format!(" {}", w), p.fg(pal.muted));
        }
    }
}

/// The screen as text and its color slots, one code pair a cell, for the
/// golden files: f fg (the terminal's own counts as fg), m muted, a
/// accent, r alarm, g ok, s surface; then the ground: l lit, s surface, .
/// the terminal's own. Upper case is bold. A color no slot names is ?.
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
        } else if c == pal.ok {
            'g'
        } else if c == pal.surface {
            's'
        } else {
            '?'
        }
    };
    let area = buf.area;
    let mut text = String::new();
    let mut codes = String::new();
    for y in 0..area.height {
        let mut skip = 0;
        for x in 0..area.width {
            let c = &buf[(x, y)];
            if skip > 0 {
                skip -= 1;
            } else {
                let sym = c.symbol();
                text.push_str(if sym.is_empty() { " " } else { sym });
                skip = cells(sym).saturating_sub(1);
            }
            let mut f = slot(c.fg);
            if c.modifier.contains(Modifier::BOLD) {
                f = f.to_ascii_uppercase();
            }
            let g = if c.bg == pal.lit {
                'l'
            } else if c.bg == pal.surface {
                's'
            } else if c.bg == Color::Reset {
                '.'
            } else {
                '?'
            };
            codes.push(f);
            codes.push(g);
        }
        text.push('\n');
        codes.push('\n');
    }
    format!("{}\n{}", text, codes)
}
