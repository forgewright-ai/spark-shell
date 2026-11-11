//! The login screen's drawing: a strip down the left side of the screen
//! in the panel's ground holds everything, and the rest is left to the
//! terminal's own ground, which foot draws with transparency over the
//! wallpaper. One text column, every color a slot of the palette.

use crate::login::{Field, Key, Login, Note, Power, Session, Spot, View};
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
    /// Key chips and their words on one row, `gap` cells apart: a hint, or the power keys.
    fn keys(&mut self, y: u16, keys: &[(&str, &str, Key)], gap: u16) {
        let mut x = COL;
        for (i, (k, w, _)) in keys.iter().enumerate() {
            if i > 0 {
                x = self.put(x, y, &" ".repeat(gap as usize), self.fg(self.pal.muted));
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

/// The hint under the form: its chips, their words, the key each stands for.
fn hint(l: &Login) -> Vec<(&'static str, &'static str, Key)> {
    match l.view {
        View::Form => vec![("Tab", "next field", Key::Tab), ("Enter", "log in", Key::Enter)],
        View::Confirm(Power::Restart) => vec![("Enter", "restart", Key::Enter), ("Esc", "back", Key::Esc)],
        View::Confirm(Power::Shutdown) => vec![("Enter", "shut down", Key::Enter), ("Esc", "back", Key::Esc)],
    }
}

/// The power keys at the foot: the ones this machine has, less the one being confirmed.
fn power(l: &Login) -> Vec<(&'static str, &'static str, Key)> {
    let showing = match l.view {
        View::Confirm(pw) => Some(pw),
        View::Form => None,
    };
    let mut v = vec![];
    if l.can_restart && showing != Some(Power::Restart) {
        v.push(("F11", "restart", Key::F(11)));
    }
    if l.can_shutdown && showing != Some(Power::Shutdown) {
        v.push(("F12", "shut down", Key::F(12)));
    }
    v
}

/// The gaps between the hint's keys and between the power keys.
const HINT_GAP: u16 = 3;
const POWER_GAP: u16 = 4;

/// The cells each key of a row takes, its chip and its words: (from, to, key).
fn key_spans(keys: &[(&str, &str, Key)], gap: u16) -> Vec<(u16, u16, Key)> {
    let mut x = COL;
    keys.iter()
        .map(|(k, w, key)| {
            let from = x;
            x += cells(k) as u16 + 2 + 1 + cells(w) as u16;
            let span = (from, x, *key);
            x += gap;
            span
        })
        .collect()
}

/// The session row's choices: each one's sign and name, and the column it starts at.
fn choices() -> [(Session, &'static str, u16); 2] {
    let desktop = FIELD_COL + 1;
    let shell = desktop + 2 + cells("desktop") as u16 + 4;
    [(Session::Desktop, "desktop", desktop), (Session::Shell, "shell", shell)]
}

/// What a click at (x, y) lands on, on a screen `w` by `h` cells: a
/// field with its label, a session with its sign, a key chip with its
/// words, the cells `draw` puts them on.
pub fn spot(l: &Login, w: u16, h: u16, x: u16, y: u16) -> Option<Spot> {
    if x >= w.min(STRIP) || y >= h {
        return None;
    }
    let (r0, _, power_row) = rows(h);
    let in_keys = |keys: &[(&str, &str, Key)], gap| {
        key_spans(keys, gap)
            .into_iter()
            .find(|(a, b, _)| (*a..*b).contains(&x))
            .map(|(_, _, k)| Spot::Press(k))
    };
    if y == r0 + 13 {
        return in_keys(&hint(l), HINT_GAP);
    }
    if y == power_row {
        return in_keys(&power(l), POWER_GAP);
    }
    if l.view != View::Form || !(COL..FIELD_COL + FIELD_W).contains(&x) {
        return None;
    }
    if y == r0 + 3 {
        return Some(Spot::Focus(Field::User));
    }
    if y == r0 + 5 {
        return Some(Spot::Focus(Field::Password));
    }
    if y == r0 + 7 && l.desktop {
        if x < FIELD_COL {
            return Some(Spot::Focus(Field::Session));
        }
        return choices()
            .into_iter()
            .find(|(_, name, at)| (*at..*at + 2 + cells(name) as u16).contains(&x))
            .map(|(s, _, _)| Spot::Pick(s));
    }
    None
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
                for (s, name, x) in choices() {
                    let on = l.session == s;
                    let x = p.put(x, r0 + 7, if on { DOT } else { RING }, p.fg(if on { pal.accent } else { pal.muted }));
                    p.put(x, r0 + 7, &format!(" {}", name), p.fg(if on { pal.fg } else { pal.muted }));
                }
            }
        }
        View::Confirm(pw) => {
            let (title, says) = match pw {
                Power::Restart => ("restart", " restarts. Type yes to go on."),
                Power::Shutdown => ("shut down", " turns off. Type yes to go on."),
            };
            p.put(COL, r0, title, p.bold(pal.fg));
            let x = p.put(COL, r0 + 3, &l.host, p.fg(pal.fg));
            p.put(x, r0 + 3, says, p.fg(pal.muted));
            p.field(r0 + 5, "confirm", &l.confirm, true);
        }
    }
    p.keys(r0 + 13, &hint(l), HINT_GAP);
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
    p.keys(power_row, &power(l), POWER_GAP);
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
