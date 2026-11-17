//! What a window of the dialog's own hears, in the events the dialog's loop already reads: a key as the
//! keyboard's layout names it (its keysym, the character it types, the modifiers held) becomes the key event a
//! terminal sends for it, and the pointer's place in pixels becomes a cell. Pure: the window (window.rs) feeds
//! it, and a test reads it without one.

use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

/// The modifiers held, as the keyboard's state has them.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Mods {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub logo: bool,
}

impl Mods {
    pub fn held(self) -> KeyModifiers {
        let mut m = KeyModifiers::NONE;
        for (on, bit) in [
            (self.shift, KeyModifiers::SHIFT),
            (self.ctrl, KeyModifiers::CONTROL),
            (self.alt, KeyModifiers::ALT),
            (self.logo, KeyModifiers::SUPER),
        ] {
            if on {
                m |= bit;
            }
        }
        m
    }
}

// the keysyms of the keys that type nothing (xkbcommon-keysyms.h)
const XK_ISO_LEFT_TAB: u32 = 0xfe20;
const XK_BACKSPACE: u32 = 0xff08;
const XK_TAB: u32 = 0xff09;
const XK_RETURN: u32 = 0xff0d;
const XK_ESCAPE: u32 = 0xff1b;
const XK_HOME: u32 = 0xff50;
const XK_LEFT: u32 = 0xff51;
const XK_UP: u32 = 0xff52;
const XK_RIGHT: u32 = 0xff53;
const XK_DOWN: u32 = 0xff54;
const XK_PAGE_UP: u32 = 0xff55;
const XK_PAGE_DOWN: u32 = 0xff56;
const XK_END: u32 = 0xff57;
const XK_INSERT: u32 = 0xff63;
const XK_KP_ENTER: u32 = 0xff8d;
const XK_KP_HOME: u32 = 0xff95;
const XK_KP_LEFT: u32 = 0xff96;
const XK_KP_UP: u32 = 0xff97;
const XK_KP_RIGHT: u32 = 0xff98;
const XK_KP_DOWN: u32 = 0xff99;
const XK_KP_PAGE_UP: u32 = 0xff9a;
const XK_KP_PAGE_DOWN: u32 = 0xff9b;
const XK_KP_END: u32 = 0xff9c;
const XK_KP_INSERT: u32 = 0xff9e;
const XK_KP_DELETE: u32 = 0xff9f;
const XK_F1: u32 = 0xffbe;
const XK_F12: u32 = 0xffc9;
const XK_DELETE: u32 = 0xffff;

/// A key as a terminal's event: `sym` is the layout's keysym for it, `text` the character that keysym types
/// (none for a key that types nothing). None for a key that is no event of its own: a modifier, a key the
/// dialog has no word for.
///
/// A character typed with neither Ctrl, Alt nor Super held comes as a terminal sends it: the character alone,
/// with Shift said only for a capital, since the character already carries its shift. With one of them held,
/// every modifier held is said.
pub fn key(sym: u32, text: Option<char>, mods: Mods, kind: KeyEventKind) -> Option<KeyEvent> {
    let code = match sym {
        XK_RETURN | XK_KP_ENTER => KeyCode::Enter,
        XK_ESCAPE => KeyCode::Esc,
        XK_BACKSPACE => KeyCode::Backspace,
        XK_TAB => KeyCode::Tab,
        XK_ISO_LEFT_TAB => KeyCode::BackTab,
        XK_DELETE | XK_KP_DELETE => KeyCode::Delete,
        XK_INSERT | XK_KP_INSERT => KeyCode::Insert,
        XK_HOME | XK_KP_HOME => KeyCode::Home,
        XK_END | XK_KP_END => KeyCode::End,
        XK_PAGE_UP | XK_KP_PAGE_UP => KeyCode::PageUp,
        XK_PAGE_DOWN | XK_KP_PAGE_DOWN => KeyCode::PageDown,
        XK_LEFT | XK_KP_LEFT => KeyCode::Left,
        XK_RIGHT | XK_KP_RIGHT => KeyCode::Right,
        XK_UP | XK_KP_UP => KeyCode::Up,
        XK_DOWN | XK_KP_DOWN => KeyCode::Down,
        XK_F1..=XK_F12 => KeyCode::F((sym - XK_F1 + 1) as u8),
        _ => {
            let c = text.filter(|c| !c.is_control())?;
            let plain = !(mods.ctrl || mods.alt || mods.logo);
            let held = if plain {
                if c.is_uppercase() {
                    KeyModifiers::SHIFT
                } else {
                    KeyModifiers::NONE
                }
            } else {
                mods.held()
            };
            return Some(KeyEvent::new_with_kind(KeyCode::Char(c), held, kind));
        }
    };
    let mut held = mods.held();
    if code == KeyCode::BackTab {
        held |= KeyModifiers::SHIFT;
    }
    Some(KeyEvent::new_with_kind(code, held, kind))
}

/// The cell under a place in pixels, on a grid of `cols` by `rows` cells of `cw` by `ch` pixels: a place past
/// the grid's edge (the window's last pixels, where no whole cell fits) is the edge's cell.
pub fn cell(x: f64, y: f64, (cw, ch): (f64, f64), (cols, rows): (u16, u16)) -> (u16, u16) {
    let at = |v: f64, size: f64, count: u16| {
        if size <= 0.0 || count == 0 || v <= 0.0 {
            return 0;
        }
        ((v / size) as u32).min(count as u32 - 1) as u16
    };
    (at(x, cw, cols), at(y, ch, rows))
}

/// The wheel's scroll gathered into steps: one step each 15 pixels, a wheel's notch, so a touchpad's small
/// scrolls add up to steps of the same size.
#[derive(Clone, Copy, Debug, Default)]
pub struct Wheel(f64);

const WHEEL_STEP: f64 = 15.0;

impl Wheel {
    /// The whole steps a scroll of `px` pixels brings, with what was left before: under zero is up.
    pub fn steps(&mut self, px: f64) -> i32 {
        self.0 += px;
        let steps = (self.0 / WHEEL_STEP).trunc();
        self.0 -= steps * WHEEL_STEP;
        steps as i32
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::HintKey;
    use crate::keys::Bindings;

    const NONE: Mods = Mods {
        shift: false,
        ctrl: false,
        alt: false,
        logo: false,
    };
    const SHIFT: Mods = Mods { shift: true, ..NONE };
    const CTRL: Mods = Mods { ctrl: true, ..NONE };

    fn press(sym: u32, text: Option<char>, mods: Mods) -> Option<KeyEvent> {
        key(sym, text, mods, KeyEventKind::Press)
    }

    #[test]
    fn a_typed_character_comes_as_a_terminal_sends_it() {
        let k = press(0x61, Some('a'), NONE).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('a'), KeyModifiers::NONE));
        // a capital says its shift; a symbol typed with Shift does not: it already is the shifted one
        let k = press(0x41, Some('A'), SHIFT).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('A'), KeyModifiers::SHIFT));
        let k = press(0x2b, Some('+'), SHIFT).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('+'), KeyModifiers::NONE));
        // a digit that needs Shift on its layout is the digit alone, so the key bound to 0 is still found
        let k = press(0x30, Some('0'), SHIFT).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('0'), KeyModifiers::NONE));
        // Caps Lock: a capital with no Shift held is still a capital
        let k = press(0x41, Some('A'), NONE).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('A'), KeyModifiers::SHIFT));
        let k = press(0xe9, Some('\u{e9}'), NONE).unwrap();
        assert_eq!(k.code, KeyCode::Char('\u{e9}'), "a letter outside ASCII");
    }

    #[test]
    fn the_keys_that_type_nothing_keep_their_modifiers() {
        let k = press(XK_RETURN, Some('\r'), SHIFT).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Enter, KeyModifiers::SHIFT));
        let k = press(XK_KP_ENTER, None, CTRL).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Enter, KeyModifiers::CONTROL));
        let k = press(XK_ISO_LEFT_TAB, None, SHIFT).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::BackTab, KeyModifiers::SHIFT));
        assert_eq!(press(XK_F1, None, NONE).unwrap().code, KeyCode::F(1));
        assert_eq!(press(XK_F12, None, NONE).unwrap().code, KeyCode::F(12));
        assert_eq!(press(XK_KP_PAGE_DOWN, None, NONE).unwrap().code, KeyCode::PageDown);
        assert_eq!(press(XK_ESCAPE, Some('\u{1b}'), NONE).unwrap().code, KeyCode::Esc);
        // a modifier alone, or a key with no word here, is no event
        assert_eq!(press(0xffe1, None, SHIFT), None, "Shift itself");
        assert_eq!(press(0xff13, None, NONE), None, "Pause");
        // a held key says so, and a release says so
        assert_eq!(key(XK_DOWN, None, NONE, KeyEventKind::Repeat).unwrap().kind, KeyEventKind::Repeat);
        assert_eq!(key(XK_DOWN, None, NONE, KeyEventKind::Release).unwrap().kind, KeyEventKind::Release);
    }

    #[test]
    fn the_dialogs_own_bindings_find_their_keys() {
        // each default as the window's keyboard sends it
        let keys = Bindings::default();
        let act = |sym, text, mods| keys.action(press(sym, text, mods).unwrap());
        assert_eq!(act(XK_RETURN, None, NONE), Some(HintKey::Enter));
        assert_eq!(act(XK_RETURN, None, CTRL), Some(HintKey::Ask));
        assert_eq!(act(XK_RETURN, None, SHIFT), Some(HintKey::Newline));
        assert_eq!(act(XK_ISO_LEFT_TAB, None, SHIFT), Some(HintKey::PreviousControl));
        assert_eq!(act(XK_TAB, None, CTRL), Some(HintKey::Pane));
        assert_eq!(act(0x71, Some('q'), CTRL), Some(HintKey::Quit));
        assert_eq!(act(0x63, Some('c'), CTRL), Some(HintKey::CopyPath));
        assert_eq!(act(0x2b, Some('+'), SHIFT), Some(HintKey::Char('+')));
        assert_eq!(act(0x3c, Some('<'), SHIFT), Some(HintKey::Char('<')));
        assert_eq!(act(0x20, Some(' '), NONE), Some(HintKey::Select));
        assert_eq!(act(0x61, Some('a'), NONE), None, "a letter is typed, no action");
    }

    #[test]
    fn a_place_in_pixels_is_a_cell_and_the_edge_holds() {
        let grid = (60, 40);
        assert_eq!(cell(0.0, 0.0, (10.0, 20.0), grid), (0, 0));
        assert_eq!(cell(9.9, 19.9, (10.0, 20.0), grid), (0, 0));
        assert_eq!(cell(10.0, 20.0, (10.0, 20.0), grid), (1, 1));
        assert_eq!(cell(599.0, 799.0, (10.0, 20.0), grid), (59, 39));
        assert_eq!(cell(604.0, 812.0, (10.0, 20.0), grid), (59, 39), "past the last whole cell");
        assert_eq!(cell(-3.0, -1.0, (10.0, 20.0), grid), (0, 0));
        assert_eq!(cell(5.0, 5.0, (0.0, 0.0), grid), (0, 0), "no cell size yet");
    }

    #[test]
    fn the_wheel_gathers_small_scrolls_into_steps() {
        let mut w = Wheel::default();
        assert_eq!(w.steps(15.0), 1, "a notch down");
        assert_eq!(w.steps(-30.0), -2, "two up");
        assert_eq!([w.steps(6.0), w.steps(6.0), w.steps(6.0)], [0, 0, 1], "a touchpad's scrolls add up");
        assert_eq!(w.steps(-3.0), 0);
    }
}
