//! The dialog's grid: what the dialog draws, whatever shows it. A buffer of cells, each one symbol with the
//! color it is written in, the color behind it and its weight. The frame is drawn into a buffer; a terminal
//! (terminal.rs) or a window of the dialog's own then shows the buffer. Pure: no terminal, no window, no library.

/// A place on the grid, in cells.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Rect {
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
}

impl Rect {
    pub const fn new(x: u16, y: u16, width: u16, height: u16) -> Rect {
        Rect { x, y, width, height }
    }
    pub const fn left(self) -> u16 {
        self.x
    }
    /// The first column past it.
    pub const fn right(self) -> u16 {
        self.x.saturating_add(self.width)
    }
    pub const fn top(self) -> u16 {
        self.y
    }
    /// The first row past it.
    pub const fn bottom(self) -> u16 {
        self.y.saturating_add(self.height)
    }
}

/// A color: the surface's own (Reset), one of the palette's slots by its number, or a red, green and blue.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum Color {
    #[default]
    Reset,
    Indexed(u8),
    Rgb(u8, u8, u8),
}

/// How a symbol is written: bold, underlined, both or neither.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Modifier(u8);

impl Modifier {
    pub const BOLD: Modifier = Modifier(1);
    pub const UNDERLINED: Modifier = Modifier(2);
    pub const fn empty() -> Modifier {
        Modifier(0)
    }
    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }
    pub const fn contains(self, other: Modifier) -> bool {
        self.0 & other.0 == other.0
    }
    pub fn insert(&mut self, other: Modifier) {
        self.0 |= other.0;
    }
}

impl std::ops::BitOr for Modifier {
    type Output = Modifier;
    fn bitor(self, other: Modifier) -> Modifier {
        Modifier(self.0 | other.0)
    }
}

/// What a write changes of a cell: a color where it names one, and the modifiers it adds.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Style {
    pub fg: Option<Color>,
    pub bg: Option<Color>,
    pub add_modifier: Modifier,
}

impl Style {
    pub const fn fg(mut self, color: Color) -> Style {
        self.fg = Some(color);
        self
    }
    pub const fn bg(mut self, color: Color) -> Style {
        self.bg = Some(color);
        self
    }
    pub const fn add_modifier(mut self, modifier: Modifier) -> Style {
        self.add_modifier = Modifier(self.add_modifier.0 | modifier.0);
        self
    }
}

/// Whether what shows the grid writes a cell: a cell a picture stands on is skipped, so the picture stays.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum CellDiffOption {
    #[default]
    None,
    Skip,
}

/// One cell: its symbol (a character and what joins it, or a space), its colors, its weight.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cell {
    symbol: String,
    pub fg: Color,
    pub bg: Color,
    pub modifier: Modifier,
    pub diff_option: CellDiffOption,
}

impl Default for Cell {
    fn default() -> Cell {
        Cell {
            symbol: " ".into(),
            fg: Color::Reset,
            bg: Color::Reset,
            modifier: Modifier::empty(),
            diff_option: CellDiffOption::None,
        }
    }
}

impl Cell {
    pub fn symbol(&self) -> &str {
        &self.symbol
    }
    pub fn set_symbol(&mut self, symbol: &str) -> &mut Cell {
        self.symbol.clear();
        self.symbol.push_str(symbol);
        self
    }
    pub fn set_fg(&mut self, color: Color) -> &mut Cell {
        self.fg = color;
        self
    }
    pub fn set_bg(&mut self, color: Color) -> &mut Cell {
        self.bg = color;
        self
    }
    pub fn set_style(&mut self, style: Style) -> &mut Cell {
        if let Some(c) = style.fg {
            self.fg = c;
        }
        if let Some(c) = style.bg {
            self.bg = c;
        }
        self.modifier.insert(style.add_modifier);
        self
    }
    pub fn style(&self) -> Style {
        Style {
            fg: Some(self.fg),
            bg: Some(self.bg),
            add_modifier: self.modifier,
        }
    }
    pub fn set_diff_option(&mut self, option: CellDiffOption) -> &mut Cell {
        self.diff_option = option;
        self
    }
    /// A space in the surface's own colors again.
    pub fn reset(&mut self) {
        *self = Cell::default();
    }
}

/// The cells of an area, row after row.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Buffer {
    pub area: Rect,
    pub content: Vec<Cell>,
}

impl Buffer {
    /// An area of spaces.
    pub fn empty(area: Rect) -> Buffer {
        Buffer {
            area,
            content: vec![Cell::default(); area.width as usize * area.height as usize],
        }
    }

    fn at(&self, x: u16, y: u16) -> usize {
        assert!(
            x >= self.area.x && x < self.area.right() && y >= self.area.y && y < self.area.bottom(),
            "({x}, {y}) is outside the grid's area {:?}",
            self.area
        );
        (y - self.area.y) as usize * self.area.width as usize + (x - self.area.x) as usize
    }

    /// A style laid on every cell of an area that is on the grid.
    pub fn set_style(&mut self, area: Rect, style: Style) {
        for y in area.top().max(self.area.top())..area.bottom().min(self.area.bottom()) {
            for x in area.left().max(self.area.left())..area.right().min(self.area.right()) {
                self[(x, y)].set_style(style);
            }
        }
    }

    /// Words written from a cell on, to the row's end at most: a character with all that joins it (an accent, a
    /// selector, the parts of one emoji) in one cell, as wide as the text's own measure says (scrub::cells), a wide
    /// one's second cell a space again, and no control character. Where it ended.
    pub fn set_string(&mut self, x: u16, y: u16, string: &str, style: Style) -> (u16, u16) {
        use unicode_segmentation::UnicodeSegmentation;
        use unicode_width::UnicodeWidthStr;
        let mut x = x;
        let end = self.area.right();
        let mut symbol = String::new();
        for cluster in string.graphemes(true) {
            symbol.clear();
            symbol.extend(cluster.chars().filter(|c| !c.is_control()));
            // the cluster's width, not its characters' sum: a sign with its emoji selector is two cells, a family of
            // four joined is two, and the layout counted them so
            let width = symbol.width() as u16;
            if width == 0 {
                continue;
            }
            if x >= end || end - x < width {
                break;
            }
            self[(x, y)].set_symbol(&symbol).set_style(style);
            for k in 1..width {
                self[(x + k, y)].reset();
            }
            x += width;
        }
        (x, y)
    }
}

impl std::ops::Index<(u16, u16)> for Buffer {
    type Output = Cell;
    fn index(&self, (x, y): (u16, u16)) -> &Cell {
        &self.content[self.at(x, y)]
    }
}

impl std::ops::IndexMut<(u16, u16)> for Buffer {
    fn index_mut(&mut self, (x, y): (u16, u16)) -> &mut Cell {
        let at = self.at(x, y);
        &mut self.content[at]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_take_a_cell_a_symbol_and_a_wide_one_two() {
        let mut b = Buffer::empty(Rect::new(0, 0, 8, 1));
        let st = Style::default().fg(Color::Rgb(1, 2, 3)).add_modifier(Modifier::BOLD);
        assert_eq!(b.set_string(1, 0, "a\u{754c}b", st), (5, 0));
        let row: Vec<&str> = (0..8).map(|x| b[(x, 0)].symbol()).collect();
        assert_eq!(row, [" ", "a", "\u{754c}", " ", "b", " ", " ", " "]);
        assert_eq!((b[(2, 0)].fg, b[(2, 0)].modifier), (Color::Rgb(1, 2, 3), Modifier::BOLD));
        assert_eq!(b[(3, 0)].fg, Color::Reset, "a wide symbol's second cell is a plain space");
        // what joins a character stays in its cell; a control character is not written
        let mut b = Buffer::empty(Rect::new(0, 0, 4, 1));
        b.set_string(0, 0, "e\u{301}\u{1b}x", Style::default());
        assert_eq!((b[(0, 0)].symbol(), b[(1, 0)].symbol()), ("e\u{301}", "x"));
        // the row's end stops the words, and a wide symbol with one cell left is not written
        let mut b = Buffer::empty(Rect::new(0, 0, 3, 1));
        assert_eq!(b.set_string(0, 0, "ab\u{754c}", Style::default()), (2, 0));
        assert_eq!(b[(2, 0)].symbol(), " ");
    }

    #[test]
    fn words_take_the_cells_the_layout_counted_for_them() {
        // the layout measures text with scrub::cells; the grid must end where that measure says, or every column
        // after the text sits a cell off. A sign with its emoji selector is two cells, not the sign's one
        let warn = "\u{26a0}\u{fe0f}";
        let mut b = Buffer::empty(Rect::new(0, 0, 6, 1));
        assert_eq!(b.set_string(0, 0, &format!("{warn}ok"), Style::default()), (4, 0));
        let row: Vec<&str> = (0..5).map(|x| b[(x, 0)].symbol()).collect();
        assert_eq!(row, [warn, " ", "o", "k", " "]);
        for text in [
            "plain words",
            "\u{26a0}\u{fe0f} low battery",
            "caf\u{65}\u{301}",
            "\u{754c}\u{9762}.txt",
            "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467} family",
            "\u{1f1e7}\u{1f1f7} flag",
            "tab\there",
        ] {
            let mut b = Buffer::empty(Rect::new(0, 0, 40, 1));
            let (end, _) = b.set_string(0, 0, text, Style::default());
            let shown: String = text.chars().filter(|c| !c.is_control()).collect();
            assert_eq!(end as usize, crate::scrub::cells(&shown), "{text:?}");
        }
    }

    #[test]
    fn a_style_changes_what_it_names_and_adds_its_modifiers() {
        let mut b = Buffer::empty(Rect::new(0, 0, 3, 2));
        b[(1, 1)].set_fg(Color::Indexed(4)).set_bg(Color::Rgb(9, 9, 9));
        b.set_style(
            Rect::new(1, 0, 9, 9),
            Style::default().bg(Color::Rgb(5, 5, 5)).add_modifier(Modifier::UNDERLINED),
        );
        assert_eq!(
            (b[(1, 1)].fg, b[(1, 1)].bg),
            (Color::Indexed(4), Color::Rgb(5, 5, 5)),
            "the color it names, not the other"
        );
        assert!(b[(2, 0)].modifier.contains(Modifier::UNDERLINED) && !b[(2, 0)].modifier.contains(Modifier::BOLD));
        assert_eq!(b[(0, 0)], Cell::default(), "a cell outside the area is as it was");
        assert!((Modifier::BOLD | Modifier::UNDERLINED).contains(Modifier::BOLD) && Modifier::empty().is_empty());
    }
}
