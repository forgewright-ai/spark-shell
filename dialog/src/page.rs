//! One line of a section's own page, in the row shapes the dialog has: a group's heading, the page's
//! subject, a note, a fact (a label and a value, no action), or a row with a sign, a label, a value, an
//! arrow and a key chip. Apps and files build their pages from it; ui.rs draws it the one way.

#[derive(Clone, Debug, PartialEq)]
pub struct Line<A> {
    pub sign: &'static str,
    pub label: String,
    pub value: String,
    pub value_x: u16,
    pub tail: String,
    pub action: Option<A>,
    pub indent: u16,
    pub heading: bool,
    pub title: bool,
    pub muted: bool,
    pub value_muted: bool,
    /// A wrapped value's next line: one target with the line it continues.
    pub continuation: bool,
    pub disabled: bool,
    /// The key that does what the row does, drawn as a chip at the row's right (files' check: Insert).
    pub key: String,
}

impl<A> Default for Line<A> {
    fn default() -> Self {
        Self {
            sign: "",
            label: String::new(),
            value: String::new(),
            value_x: 0,
            tail: String::new(),
            action: None,
            indent: 0,
            heading: false,
            title: false,
            muted: false,
            value_muted: false,
            continuation: false,
            disabled: false,
            key: String::new(),
        }
    }
}

/// Where a page was left: the words typed, the row lit, the scroll; put back when the page comes back.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Navigation {
    pub query: String,
    pub selected: usize,
    pub in_list: bool,
    pub scroll: usize,
}
