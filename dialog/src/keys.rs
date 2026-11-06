//! Named home actions. One validated map drives terminal input and visible hints.
use crate::app::HintKey;
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use std::path::Path;

const DEFAULTS: &[(&str, HintKey, &str)] = &[
    ("accept", HintKey::Enter, "Enter"),
    ("ask", HintKey::Ask, "Ctrl+Enter"),
    ("newline", HintKey::Newline, "Shift+Enter"),
    ("back", HintKey::Escape, "Esc"),
    ("conversation", HintKey::Conversation, "F10"),
    ("next-control", HintKey::Tab, "Tab"),
    ("previous-control", HintKey::PreviousControl, "Shift+Tab"),
    ("up", HintKey::Up, "Up"),
    ("down", HintKey::Down, "Down"),
    ("left", HintKey::Left, "Left"),
    ("right", HintKey::Right, "Right"),
    ("start", HintKey::Start, "Home"),
    ("end", HintKey::End, "End"),
    ("page-up", HintKey::PageUp, "PageUp"),
    ("page-down", HintKey::PageDown, "PageDown"),
    ("backspace", HintKey::Backspace, "Backspace"),
    ("delete", HintKey::Delete, "Delete"),
    ("quit", HintKey::Quit, "Ctrl+Q"),
    ("rename", HintKey::Rename, "F2"),
    ("view", HintKey::View, "F3"),
    ("open", HintKey::Open, "F4"),
    ("copy", HintKey::Copy, "F5"),
    ("move", HintKey::Move, "F6"),
    ("new", HintKey::New, "F7"),
    ("trash", HintKey::Trash, "F8"),
    ("actions", HintKey::Actions, "F9"),
    ("copy-path", HintKey::CopyPath, "Ctrl+C"),
    ("select", HintKey::Select, "Space"),
    ("pane", HintKey::Pane, "Ctrl+Tab"),
    ("zoom-in", HintKey::Char('+'), "Plus"),
    ("zoom-out", HintKey::Char('-'), "-"),
    ("zoom-fit", HintKey::Char('0'), "0"),
    ("previous-page", HintKey::Char('<'), "<"),
    ("next-page", HintKey::Char('>'), ">"),
];

/// The names an older home-keys.json may hold: the file keeps working when an action takes the word people see.
const ALIASES: &[(&str, &str)] = &[("preview", "view"), ("check", "select")];

/// Each action: its name, what it does, the key as a person reads it, the key itself. An action a person's own key
/// took the default from has neither: it stays unbound, and no key does it.
#[derive(Clone, Debug)]
pub struct Bindings(Vec<(String, HintKey, String, Option<KeyEvent>)>);

fn parse(text: &str) -> Result<KeyEvent, String> {
    let mut parts: Vec<_> = text.split('+').collect();
    let key = parts.pop().ok_or("empty key")?;
    let mut modifiers = KeyModifiers::NONE;
    for part in parts {
        let m = match part.to_ascii_lowercase().as_str() {
            "ctrl" => KeyModifiers::CONTROL,
            "alt" => KeyModifiers::ALT,
            "shift" => KeyModifiers::SHIFT,
            _ => return Err(format!("unknown modifier: {}", part)),
        };
        if modifiers.contains(m) {
            return Err(format!("repeated modifier: {}", part));
        }
        modifiers |= m;
    }
    let code = match key.to_ascii_lowercase().as_str() {
        "enter" => KeyCode::Enter,
        "esc" => KeyCode::Esc,
        "tab" => KeyCode::Tab,
        "up" => KeyCode::Up,
        "down" => KeyCode::Down,
        "left" => KeyCode::Left,
        "right" => KeyCode::Right,
        "home" => KeyCode::Home,
        "end" => KeyCode::End,
        "pageup" => KeyCode::PageUp,
        "pagedown" => KeyCode::PageDown,
        "backspace" => KeyCode::Backspace,
        "delete" => KeyCode::Delete,
        "insert" => KeyCode::Insert,
        "space" => KeyCode::Char(' '),
        "plus" => KeyCode::Char('+'),
        f if f.starts_with('f') && f.len() > 1 => {
            let n = f[1..].parse::<u8>().map_err(|_| format!("invalid key: {}", key))?;
            if !(1..=12).contains(&n) {
                return Err("function keys are F1 through F12".into());
            }
            KeyCode::F(n)
        }
        // a letter binds its key whatever its case (P is the p key); a shifted one is written Shift+p
        l if l.len() == 1 && l.as_bytes()[0].is_ascii_alphabetic() => KeyCode::Char(l.as_bytes()[0].to_ascii_lowercase() as char),
        _ if key.chars().count() == 1 && !key.chars().any(char::is_control) => KeyCode::Char(key.chars().next().unwrap()),
        _ => return Err(format!("unknown key: {}", key)),
    };
    Ok(normalize(KeyEvent::new(code, modifiers)))
}

fn same(a: &KeyEvent, b: &KeyEvent) -> bool {
    a.code == b.code && a.modifiers == b.modifiers
}

fn normalize(mut key: KeyEvent) -> KeyEvent {
    if key.code == KeyCode::BackTab {
        key.code = KeyCode::Tab;
        key.modifiers |= KeyModifiers::SHIFT;
    }
    // Shifted printable symbols already carry their shift in the character.
    if let KeyCode::Char(c) = key.code {
        if c.is_ascii_uppercase() {
            key.code = KeyCode::Char(c.to_ascii_lowercase());
            key.modifiers |= KeyModifiers::SHIFT;
        } else if !c.is_alphanumeric() && c != ' ' {
            key.modifiers.remove(KeyModifiers::SHIFT);
        }
    }
    key
}

impl Default for Bindings {
    fn default() -> Self {
        Self(
            DEFAULTS
                .iter()
                .map(|(name, action, key)| (name.to_string(), *action, key.to_string(), Some(parse(key).unwrap())))
                .collect(),
        )
    }
}

impl Bindings {
    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read_to_string(path) {
            Ok(text) => Self::from_json(&text),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(format!("cannot read home keys: {}", e)),
        }
    }

    pub fn from_json(text: &str) -> Result<Self, String> {
        let value: serde_json::Value = serde_json::from_str(text).map_err(|e| format!("home keys: {}", e))?;
        let object = value.as_object().ok_or("home keys must be an object of action: key")?;
        let mut bindings = Self::default();
        let mut set: Vec<(String, KeyEvent)> = vec![];
        for (name, value) in object {
            let name = ALIASES.iter().find(|(old, _)| old == name).map_or(name.as_str(), |(_, new)| new);
            let entry = bindings
                .0
                .iter_mut()
                .find(|(n, ..)| n.as_str() == name)
                .ok_or_else(|| format!("unknown home action: {}", name))?;
            let label = value.as_str().ok_or_else(|| format!("{} needs a key string", name))?;
            let key = parse(label)?;
            entry.3 = Some(key);
            entry.2 = label.to_string();
            set.retain(|(n, _)| n != name); // a name and its old name: the later stands
            set.push((name.to_string(), key));
        }
        // two keys the person set on one key: refused before home starts
        for (i, (name, key)) in set.iter().enumerate() {
            if let Some((other, _)) = set[..i].iter().find(|(_, k)| same(k, key)) {
                return Err(format!("key conflict: {} and {}", name, other));
            }
        }
        // a key the person set wins over a default: an upgrade that gives a default to their key never stops home from
        // starting, and the action that held it by default alone stays unbound
        for (name, _, label, key) in bindings.0.iter_mut() {
            if !set.iter().any(|(n, _)| n == name) && key.is_some_and(|k| set.iter().any(|(_, s)| same(s, &k))) {
                *key = None;
                label.clear();
            }
        }
        Ok(bindings)
    }

    pub fn action(&self, key: KeyEvent) -> Option<HintKey> {
        let key = normalize(key);
        self.0.iter().find(|(_, _, _, k)| k.is_some_and(|k| same(&k, &key))).map(|(_, a, ..)| *a)
    }

    pub fn label(&self, action: HintKey) -> &str {
        match self
            .0
            .iter()
            .find(|(_, a, ..)| *a == action)
            .map(|(_, _, label, _)| label.as_str())
            // the player's Space (play, pause) is no binding's: its chip keeps its word
            .unwrap_or(if action == HintKey::Char(' ') { "Space" } else { "" })
        {
            "Up" => "\u{2191}",
            "Down" => "\u{2193}",
            "Left" => "\u{2190}",
            "Right" => "\u{2192}",
            "Plus" => "+",
            label => label,
        }
    }

    pub fn help(&self) -> Vec<(&str, &str)> {
        self.0.iter().map(|(name, _, key, _)| (name.as_str(), key.as_str())).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn view_is_f3_so_no_typed_letter_opens_it() {
        let keys = Bindings::default();
        assert_eq!(keys.action(KeyEvent::new(KeyCode::F(3), KeyModifiers::NONE)), Some(HintKey::View));
        assert_eq!(keys.action(KeyEvent::new(KeyCode::Char('p'), KeyModifiers::NONE)), None);
        assert_eq!(keys.label(HintKey::View), "F3");
    }

    #[test]
    fn the_keys_are_the_function_row_and_each_is_a_name_in_help() {
        let keys = Bindings::default();
        for (n, action, name) in [
            (2, HintKey::Rename, "rename"),
            (3, HintKey::View, "view"),
            (4, HintKey::Open, "open"),
            (5, HintKey::Copy, "copy"),
            (6, HintKey::Move, "move"),
            (7, HintKey::New, "new"),
            (8, HintKey::Trash, "trash"),
            (9, HintKey::Actions, "actions"),
            (10, HintKey::Conversation, "conversation"),
        ] {
            assert_eq!(keys.action(KeyEvent::new(KeyCode::F(n), KeyModifiers::NONE)), Some(action), "F{}", n);
            let f = format!("F{}", n);
            assert!(keys.help().contains(&(name, f.as_str())), "{} in help", name);
        }
        let ctrl = |c: char| KeyEvent::new(KeyCode::Char(c), KeyModifiers::CONTROL);
        assert_eq!(keys.action(ctrl('c')), Some(HintKey::CopyPath), "Ctrl+C copies, it no longer quits");
        assert_eq!(keys.action(ctrl('q')), Some(HintKey::Quit));
        assert_eq!(keys.label(HintKey::CopyPath), "Ctrl+C");
        assert_eq!(keys.action(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE)), Some(HintKey::Select));
        assert_eq!(keys.action(KeyEvent::new(KeyCode::Right, KeyModifiers::NONE)), Some(HintKey::Right));
    }

    #[test]
    fn a_key_the_person_set_wins_over_a_default_and_two_of_theirs_are_refused() {
        // the README's own example once: F2 is rename's default now, and the person's F2 stands
        let keys = Bindings::from_json(r#"{"conversation": "F2"}"#).unwrap();
        assert_eq!(keys.action(KeyEvent::new(KeyCode::F(2), KeyModifiers::NONE)), Some(HintKey::Conversation));
        assert_eq!(keys.label(HintKey::Rename), "", "rename stays unbound");
        assert!(keys.help().contains(&("rename", "")), "and help shows no key for it");
        assert_eq!(
            keys.action(KeyEvent::new(KeyCode::F(10), KeyModifiers::NONE)),
            None,
            "F10 lets go with its action"
        );
        // v0.125 pointed people here: check is select's old name, and nothing else moves
        let keys = Bindings::from_json(r#"{"check": "Insert"}"#).unwrap();
        assert_eq!(keys.action(KeyEvent::new(KeyCode::Insert, KeyModifiers::NONE)), Some(HintKey::Select));
        assert_eq!(keys.label(HintKey::Select), "Insert");
        assert_eq!(keys.action(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE)), None);
        // two keys the person set on one key: refused before home starts
        let e = Bindings::from_json(r#"{"ask": "F4", "conversation": "F4"}"#).unwrap_err();
        assert!(e.contains("conflict") && e.contains("ask") && e.contains("conversation"), "{}", e);
        // over any default: the person's key is theirs, the default's action unbound
        let keys = Bindings::from_json(r#"{"ask":"Enter"}"#).unwrap();
        assert_eq!(keys.action(parse("Enter").unwrap()), Some(HintKey::Ask));
        assert_eq!(keys.label(HintKey::Enter), "");
    }

    #[test]
    fn an_older_home_keys_file_keeps_working() {
        let keys = Bindings::from_json(r#"{"preview":"F11","check":"Insert"}"#).unwrap();
        assert_eq!(keys.label(HintKey::View), "F11", "preview is still a name for view");
        assert_eq!(keys.action(KeyEvent::new(KeyCode::Insert, KeyModifiers::NONE)), Some(HintKey::Select));
        assert_eq!(keys.action(KeyEvent::new(KeyCode::F(3), KeyModifiers::NONE)), None, "the old key lets go");
        let keys = Bindings::from_json(r#"{"view":"F12"}"#).unwrap();
        assert_eq!(keys.label(HintKey::View), "F12");
    }

    #[test]
    fn remapping_and_conflicts_are_resolved_before_input() {
        let keys = Bindings::from_json(r#"{"ask":"F11"}"#).unwrap();
        assert_eq!(keys.action(KeyEvent::new(KeyCode::F(11), KeyModifiers::NONE)), Some(HintKey::Ask));
        assert_eq!(keys.action(parse("Ctrl+Enter").unwrap()), None);
        assert_eq!(keys.label(HintKey::Ask), "F11");
        assert!(Bindings::from_json(r#"{"ask":"Control+Enter"}"#).is_err());
        assert!(Bindings::from_json(r#"{"typo":"F11"}"#).is_err());
        assert_eq!(
            keys.action(KeyEvent::new(KeyCode::BackTab, KeyModifiers::SHIFT)),
            Some(HintKey::PreviousControl)
        );
    }
}
