//! The reply row: one line under the key row that holds the last receipt, refusal or note. A new one
//! takes the old one's place, Esc clears it, and it never stacks. A click on a row says nothing here
//! unless it is refused; the row itself shows that it worked.

use crate::scrub::scrub;

/// What the reply says: a step done, a step refused, a note, or an answer summary.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Mark {
    Done,
    Refused,
    Note,
    /// The full answer is in Conversation; its summary is only for other views.
    Answer,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Reply {
    pub mark: Mark,
    /// One line: a text of several lines reads as one, its lines parted by spaces.
    pub text: String,
    /// The undo at hand belongs to this reply: Undo stands at its end.
    pub undo: bool,
}

impl Reply {
    pub fn new(mark: Mark, text: &str) -> Reply {
        let one = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect::<Vec<_>>().join(" ");
        Reply {
            mark,
            text: scrub(&one),
            undo: false,
        }
    }

    /// A click whose step left an undo: Undo alone, no words.
    pub fn undo_only() -> Reply {
        Reply {
            mark: Mark::Done,
            text: String::new(),
            undo: true,
        }
    }
}
