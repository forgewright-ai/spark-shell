//! The words as typed: what to erase and type so the line reads as the engine's text, and the text across
//! the pauses that end an utterance.

/// From what is typed to what the engine says now: the common start stays; the characters after it are
/// erased and the new ones typed.
pub fn delta<'a>(typed: &str, now: &'a str) -> (usize, &'a str) {
    let common = typed.chars().zip(now.chars()).take_while(|(a, b)| a == b).count();
    let erase = typed.chars().count() - common;
    let at = now.char_indices().nth(common).map_or(now.len(), |(i, _)| i);
    (erase, &now[at..])
}

/// The contract's lines for one step: `erase N` when something goes, `type TEXT` when something comes.
pub fn lines(typed: &str, now: &str) -> Vec<String> {
    let (erase, add) = delta(typed, now);
    let mut out = vec![];
    if erase > 0 {
        out.push(format!("erase {erase}"));
    }
    if !add.is_empty() {
        out.push(format!("type {add}"));
    }
    out
}

/// The utterances so far: the ones a pause ended, and the one being spoken.
#[derive(Default)]
pub struct Text {
    done: String,
}

impl Text {
    /// Everything said: the ended utterances, then the current one.
    pub fn now(&self, current: &str) -> String {
        match (self.done.is_empty(), current.is_empty()) {
            (true, _) => current.to_string(),
            (false, true) => self.done.clone(),
            (false, false) => format!("{} {}", self.done, current),
        }
    }

    /// A pause ended the current utterance: it joins the ones before.
    pub fn end(&mut self, current: &str) {
        if !current.is_empty() {
            self.done = self.now(current);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_delta_keeps_the_common_start() {
        assert_eq!(delta("", "hey"), (0, "hey"));
        assert_eq!(delta("hey", "hey can"), (0, " can"));
        assert_eq!(delta("hey can", "hey can"), (0, ""));
        assert_eq!(delta("hey cat", "hey can you"), (1, "n you"));
        assert_eq!(delta("hey can", "no"), (7, "no"));
    }

    #[test]
    fn the_delta_counts_characters_not_bytes() {
        assert_eq!(delta("caf\u{e9}s", "caf\u{e9} au lait"), (1, " au lait"));
    }

    #[test]
    fn the_lines_say_what_changes() {
        assert_eq!(lines("hey", "hey can"), vec!["type  can"]);
        assert_eq!(lines("hey cat", "hey can"), vec!["erase 1", "type n"]);
        assert!(lines("hey", "hey").is_empty());
    }

    #[test]
    fn utterances_join_with_a_space() {
        let mut t = Text::default();
        assert_eq!(t.now("hey"), "hey");
        t.end("hey there");
        assert_eq!(t.now(""), "hey there");
        assert_eq!(t.now("open"), "hey there open");
        t.end("");
        assert_eq!(t.now("x"), "hey there x");
    }
}
