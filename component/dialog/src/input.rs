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
            // with one of them held the key is a binding's, and a binding names its Shift apart from its letter:
            // the capital Caps Lock gives with no Shift held is the plain letter (Ctrl+q, never Ctrl+Shift+q)
            let c = if !plain && !mods.shift && c.is_uppercase() { lower(c) } else { c };
            return Some(KeyEvent::new_with_kind(KeyCode::Char(c), held, kind));
        }
    };
    let mut held = mods.held();
    if code == KeyCode::BackTab {
        held |= KeyModifiers::SHIFT;
    }
    Some(KeyEvent::new_with_kind(code, held, kind))
}

/// The small letter of a capital, where it is one character.
fn lower(c: char) -> char {
    let mut small = c.to_lowercase();
    match (small.next(), small.next()) {
        (Some(l), None) => l,
        _ => c,
    }
}

/// The left button as the window knows it, for telling a drag from a move.
#[derive(Clone, Copy, Debug, Default)]
pub struct Held(bool);

impl Held {
    pub fn press(&mut self, left: bool) {
        self.0 |= left;
    }
    pub fn release(&mut self, left: bool) {
        self.0 &= !left;
    }
    /// The pointer left the window. A button let go after that is let go elsewhere, and the window never hears
    /// it: home put away at the press that opened an app got no release, and every move after was a drag.
    pub fn leave(&mut self) {
        self.0 = false;
    }
    pub fn dragging(self) -> bool {
        self.0
    }
}

/// The scale the window draws at before the compositor names its own: the one every screen has, and 1 where
/// they differ. The compositor says the window's scale only when it is not the 1 a surface starts with, so a
/// guess above 1 on a screen of scale 1 would never be corrected.
pub fn first_scale(screens: impl IntoIterator<Item = i32>) -> i32 {
    let mut all = screens.into_iter().map(|s| s.max(1));
    match all.next() {
        Some(first) if all.all(|s| s == first) => first,
        _ => 1,
    }
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
    fn caps_lock_leaves_a_bound_letter_its_plain_self() {
        // Caps Lock on, Ctrl+Q: the layout names the capital, no Shift is held, and the binding is Ctrl+q
        let keys = Bindings::default();
        let k = press(0x51, Some('Q'), CTRL).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('q'), KeyModifiers::CONTROL));
        assert_eq!(keys.action(k), Some(HintKey::Quit));
        assert_eq!(keys.action(press(0x43, Some('C'), CTRL).unwrap()), Some(HintKey::CopyPath));
        // Shift held is said, with Caps Lock (the layout names the small letter) and without
        let both = Mods { shift: true, ..CTRL };
        let k = press(0x71, Some('q'), both).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('q'), KeyModifiers::CONTROL | KeyModifiers::SHIFT));
        let k = press(0x51, Some('Q'), both).unwrap();
        assert_eq!((k.code, k.modifiers), (KeyCode::Char('Q'), KeyModifiers::CONTROL | KeyModifiers::SHIFT));
        // typed with no such key held, Caps Lock's capital stays a capital
        assert_eq!(press(0x51, Some('Q'), NONE).unwrap().code, KeyCode::Char('Q'));
    }

    #[test]
    fn a_button_let_go_elsewhere_is_no_drag() {
        let mut held = Held::default();
        assert!(!held.dragging());
        held.press(true);
        assert!(held.dragging(), "the left button held: a move is a drag");
        held.release(true);
        assert!(!held.dragging());
        // the press put the window away: the pointer leaves it, and the release goes to no window
        held.press(true);
        held.leave();
        assert!(!held.dragging(), "back over the window, a move is a move");
        // another button changes nothing
        held.press(false);
        assert!(!held.dragging());
        held.press(true);
        held.release(false);
        assert!(held.dragging());
    }

    #[test]
    fn the_first_scale_is_the_one_every_screen_has() {
        assert_eq!(first_scale([2, 2]), 2, "every screen at 2: pictures made for it from the start");
        assert_eq!(first_scale([1]), 1);
        assert_eq!(first_scale([2, 1]), 1, "they differ: 1, the scale the compositor corrects from");
        assert_eq!(first_scale([1, 2]), 1);
        assert_eq!(first_scale([]), 1, "no screen known yet");
        assert_eq!(first_scale([0]), 1);
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
