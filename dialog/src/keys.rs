//! Named home actions. One validated map drives terminal input and visible hints.
use crate::app::HintKey;
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use std::path::Path;

const DEFAULTS: &[(&str, HintKey, &str)] = &[
    ("accept", HintKey::Enter, "Enter"),
    ("ask", HintKey::Ask, "Ctrl+Enter"),
    ("newline", HintKey::Newline, "Shift+Enter"),
    ("back", HintKey::Escape, "Esc"),
    ("conversation", HintKey::Conversation, "F2"),
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
    ("quit", HintKey::Quit, "Ctrl+c"),
    ("preview", HintKey::Char(' '), "Space"),
    ("zoom-in", HintKey::Char('+'), "Plus"),
    ("zoom-out", HintKey::Char('-'), "-"),
    ("zoom-fit", HintKey::Char('0'), "0"),
    ("previous-page", HintKey::Char('<'), "<"),
    ("next-page", HintKey::Char('>'), ">"),
];

#[derive(Clone, Debug)]
pub struct Bindings(Vec<(String, HintKey, String, KeyEvent)>);

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
        "space" => KeyCode::Char(' '),
        "plus" => KeyCode::Char('+'),
        f if f.starts_with('f') && f.len() > 1 => {
            let n = f[1..].parse::<u8>().map_err(|_| format!("invalid key: {}", key))?;
            if !(1..=12).contains(&n) {
                return Err("function keys are F1 through F12".into());
            }
            KeyCode::F(n)
        }
        _ if key.chars().count() == 1 && !key.chars().any(char::is_control) => KeyCode::Char(key.chars().next().unwrap()),
        _ => return Err(format!("unknown key: {}", key)),
    };
    Ok(normalize(KeyEvent::new(code, modifiers)))
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
                .map(|(name, action, key)| (name.to_string(), *action, key.to_string(), parse(key).unwrap()))
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
        for (name, value) in object {
            let entry = bindings
                .0
                .iter_mut()
                .find(|(n, ..)| n == name)
                .ok_or_else(|| format!("unknown home action: {}", name))?;
            let label = value.as_str().ok_or_else(|| format!("{} needs a key string", name))?;
            entry.3 = parse(label)?;
            entry.2 = label.to_string();
        }
        for (i, (name, _, _, key)) in bindings.0.iter().enumerate() {
            if let Some((other, ..)) = bindings.0[..i].iter().find(|(_, _, _, k)| k.code == key.code && k.modifiers == key.modifiers) {
                return Err(format!("key conflict: {} and {}", name, other));
            }
        }
        Ok(bindings)
    }

    pub fn action(&self, key: KeyEvent) -> Option<HintKey> {
        let key = normalize(key);
        self.0
            .iter()
            .find(|(_, _, _, k)| k.code == key.code && k.modifiers == key.modifiers)
            .map(|(_, a, ..)| *a)
    }

    pub fn label(&self, action: HintKey) -> &str {
        match self
            .0
            .iter()
            .find(|(_, a, ..)| *a == action)
            .map(|(_, _, label, _)| label.as_str())
            .unwrap_or("")
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
    fn remapping_and_conflicts_are_resolved_before_input() {
        let keys = Bindings::from_json(r#"{"ask":"F4"}"#).unwrap();
        assert_eq!(keys.action(KeyEvent::new(KeyCode::F(4), KeyModifiers::NONE)), Some(HintKey::Ask));
        assert_eq!(keys.action(parse("Ctrl+Enter").unwrap()), None);
        assert_eq!(keys.label(HintKey::Ask), "F4");
        assert!(Bindings::from_json(r#"{"ask":"Enter"}"#).unwrap_err().contains("conflict"));
        assert!(Bindings::from_json(r#"{"ask":"Control+Enter"}"#).is_err());
        assert!(Bindings::from_json(r#"{"typo":"F4"}"#).is_err());
        assert_eq!(
            keys.action(KeyEvent::new(KeyCode::BackTab, KeyModifiers::SHIFT)),
            Some(HintKey::PreviousControl)
        );
    }
}
