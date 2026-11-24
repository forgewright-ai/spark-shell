//! The grid as drawing steps, for a window of the dialog's own: the ground, a box behind each run of cells that
//! has a color of its own, then every symbol in its cell and a line under the ones that are underlined. Pure:
//! what a painter (paint.rs) then draws with cairo and pango, and what a test reads without either.

use crate::grid::{Buffer, CellDiffOption, Color, Modifier};
use crate::sixel::Image;
use std::sync::Arc;

/// A red, a green and a blue.
pub type Rgb = [u8; 3];

/// A cell's size in pixels, the text's own: every cell is that wide and that tall.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cell {
    pub w: f64,
    pub h: f64,
}

/// The colors the grid's own words stand for: the window's ground (Reset behind a symbol), the text's color
/// (Reset on a symbol), and the palette's slots by their number.
pub struct Tones<'a> {
    pub ground: Rgb,
    pub ink: Rgb,
    pub slot: &'a dyn Fn(u8) -> Rgb,
}

impl Tones<'_> {
    fn behind(&self, c: Color) -> Rgb {
        match c {
            Color::Reset => self.ground,
            Color::Indexed(n) => (self.slot)(n),
            Color::Rgb(r, g, b) => [r, g, b],
        }
    }
    fn on(&self, c: Color) -> Rgb {
        match c {
            Color::Reset => self.ink,
            Color::Indexed(n) => (self.slot)(n),
            Color::Rgb(r, g, b) => [r, g, b],
        }
    }
}

/// The tones of a palette whose colors are a red, a green and a blue each, as a window of the dialog's own takes
/// them: the surface behind, the text's color on. A slot's number, the terminal's way, stands for the text's.
pub fn tones(pal: &crate::palette::Palette) -> Tones<'static> {
    let rgb = |c: Color, or: Rgb| match c {
        Color::Rgb(r, g, b) => [r, g, b],
        _ => or,
    };
    let ink = rgb(pal.fg, [0xaa, 0xaa, 0xaa]);
    Tones {
        ground: rgb(pal.surface, [0x1f, 0x1f, 0x1f]),
        ink,
        slot: &|_| [0xaa, 0xaa, 0xaa],
    }
}

/// A picture's pixels as the painter takes them: `w` by `h`, four bytes a pixel, each pixel one number of alpha,
/// red, green and blue in the machine's byte order, the colors already multiplied by the alpha (cairo's ARGB32).
#[derive(Clone, Debug, PartialEq)]
pub struct Pic {
    pub w: u32,
    pub h: u32,
    pub data: Vec<u8>,
}

impl Pic {
    pub fn of(img: &Image) -> Pic {
        let mut data = Vec::with_capacity(img.pixels().len() * 4);
        for [r, g, b, a] in img.pixels() {
            let pre = |c: u8| (c as u32 * *a as u32 + 127) / 255;
            data.extend_from_slice(&(((*a as u32) << 24) | (pre(*r) << 16) | (pre(*g) << 8) | pre(*b)).to_ne_bytes());
        }
        Pic { w: img.w, h: img.h, data }
    }
}

/// A text's size: the text's own, the smaller one a row's second words are set in, or one of the large ones a
/// heading and a name are set in (v0.160): a group's heading, the line under a name, and a name at three sizes,
/// the largest for a short one.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Size {
    Main,
    Small,
    Head,
    Lead,
    Title,
    Title2,
    Title3,
}

/// The letters a typeface is shown by: the ones Monaspace's five faces draw most unlike each other.
pub const LETTERS: &str = "Agl";

impl Size {
    /// The size LETTERS are set in.
    pub const LETTERS: Size = Size::Lead;
    /// The large sizes, in the order every table of them keeps.
    pub const BIG: [Size; 5] = [Size::Head, Size::Lead, Size::Title, Size::Title2, Size::Title3];
    /// A large size's place in BIG; none for the text's own two.
    pub fn big(self) -> Option<usize> {
        Size::BIG.iter().position(|s| *s == self)
    }
    /// How many times the text's own size this one is: 28, 22, 72, 48 and 32 pixels beside its 16.
    pub fn times(self) -> f64 {
        match self {
            Size::Main => 1.0,
            Size::Small => 0.75,
            Size::Head => 1.75,
            Size::Lead => 1.375,
            Size::Title => 4.5,
            Size::Title2 => 3.0,
            Size::Title3 => 2.0,
        }
    }
}

/// One thing to draw, in pixels from the window's top left corner.
#[derive(Clone, Debug, PartialEq)]
pub enum Step {
    /// A box of one color.
    Fill {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        color: Rgb,
    },
    /// A symbol at its cell's corner; `cells` is how many cells it takes, one or two.
    Symbol {
        x: f64,
        y: f64,
        cells: u16,
        text: String,
        color: Rgb,
        bold: bool,
    },
    /// A line along the foot of a symbol's cells.
    Under {
        x: f64,
        y: f64,
        w: f64,
        color: Rgb,
    },
    /// A picture with its corner there, drawn over what is under it. `scale` is how many of its pixels stand on one
    /// of the window's: a picture made for a screen of twice the pixels is drawn at half its size, pixel for pixel.
    Picture {
        x: f64,
        y: f64,
        scale: f64,
        pic: Arc<Pic>,
    },
    /// Words as one run, their line's top left corner there, in the face's own advances: the layout in pixels
    /// (scene.rs) places a run, never a symbol a cell.
    Text {
        x: f64,
        y: f64,
        text: String,
        size: Size,
        color: Rgb,
        bold: bool,
    },
    /// Words in a family that is not the text's own, from `x`, on the baseline at `base`: a typeface's specimen. Only
    /// a family the window was asked for and resolved (Handle::face).
    Specimen {
        x: f64,
        base: f64,
        text: String,
        face: String,
        size: Size,
        color: Rgb,
    },
    /// A picture file over the whole of a box, its middle where the shapes differ: thumbs.rs puts its pixels in the
    /// step's place before it is painted.
    Cover {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        file: String,
    },
    /// A shade of one color, from clear at the box's top to nearly solid at its foot: words are read over a picture
    /// there.
    Shade {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        color: Rgb,
    },
    /// What follows is drawn inside this box alone, until Unclip: a list that scrolls under its frame.
    Clip {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
    },
    Unclip,
}

/// The steps moved by (dx, dy): a part drawn at its own corner, laid at its place in the window.
pub fn moved(steps: Vec<Step>, dx: f64, dy: f64) -> Vec<Step> {
    steps
        .into_iter()
        .map(|s| match s {
            Step::Fill { x, y, w, h, color } => Step::Fill {
                x: x + dx,
                y: y + dy,
                w,
                h,
                color,
            },
            Step::Symbol {
                x,
                y,
                cells,
                text,
                color,
                bold,
            } => Step::Symbol {
                x: x + dx,
                y: y + dy,
                cells,
                text,
                color,
                bold,
            },
            Step::Under { x, y, w, color } => Step::Under {
                x: x + dx,
                y: y + dy,
                w,
                color,
            },
            Step::Picture { x, y, scale, pic } => Step::Picture {
                x: x + dx,
                y: y + dy,
                scale,
                pic,
            },
            Step::Text { x, y, text, size, color, bold } => Step::Text {
                x: x + dx,
                y: y + dy,
                text,
                size,
                color,
                bold,
            },
            Step::Specimen {
                x,
                base,
                text,
                face,
                size,
                color,
            } => Step::Specimen {
                x: x + dx,
                base: base + dy,
                text,
                face,
                size,
                color,
            },
            Step::Cover { x, y, w, h, file } => Step::Cover {
                x: x + dx,
                y: y + dy,
                w,
                h,
                file,
            },
            Step::Shade { x, y, w, h, color } => Step::Shade {
                x: x + dx,
                y: y + dy,
                w,
                h,
                color,
            },
            Step::Clip { x, y, w, h } => Step::Clip { x: x + dx, y: y + dy, w, h },
            Step::Unclip => Step::Unclip,
        })
        .collect()
}

/// The steps that draw a grid: the ground over the whole of it first, then row by row a box behind each run of
/// cells whose color is not the ground's, then the symbols. A space draws nothing, and neither does a cell a
/// picture stands on: its ground is the window's, and the picture is drawn over it by whoever holds it.
pub fn steps(buf: &Buffer, cell: Cell, tones: &Tones) -> Vec<Step> {
    let (cols, rows) = (buf.area.width, buf.area.height);
    let mut out = vec![Step::Fill {
        x: 0.0,
        y: 0.0,
        w: cols as f64 * cell.w,
        h: rows as f64 * cell.h,
        color: tones.ground,
    }];
    out.extend(rows_steps(buf, cell, tones, 0, rows));
    out
}

/// The steps of the grid's rows `from` up to `to`, the first of them at the top: no ground under them, the boxes
/// and the symbols alone. The layout in pixels lays a place's rows inside its own frame with them.
pub fn rows_steps(buf: &Buffer, cell: Cell, tones: &Tones, from: u16, to: u16) -> Vec<Step> {
    let (cols, rows) = (buf.area.width, buf.area.height);
    let mut out = vec![];
    for y in from..to.min(rows) {
        let top = (y - from) as f64 * cell.h;
        // the boxes: a run of cells of one color behind them, where it is not the ground's
        let mut x = 0;
        while x < cols {
            let c = &buf[(x, y)];
            let color = if c.diff_option == CellDiffOption::Skip {
                tones.ground
            } else {
                tones.behind(c.bg)
            };
            let mut end = x + 1;
            while end < cols {
                let n = &buf[(end, y)];
                let same = if n.diff_option == CellDiffOption::Skip {
                    tones.ground
                } else {
                    tones.behind(n.bg)
                };
                if same != color {
                    break;
                }
                end += 1;
            }
            if color != tones.ground {
                out.push(Step::Fill {
                    x: x as f64 * cell.w,
                    y: top,
                    w: (end - x) as f64 * cell.w,
                    h: cell.h,
                    color,
                });
            }
            x = end;
        }
        // the symbols, each in its own cell: the grid holds them in place, never the text's own advance
        for x in 0..cols {
            let c = &buf[(x, y)];
            if c.diff_option == CellDiffOption::Skip || c.symbol().trim().is_empty() {
                continue;
            }
            let cells = wide(c.symbol());
            let color = tones.on(c.fg);
            out.push(Step::Symbol {
                x: x as f64 * cell.w,
                y: top,
                cells,
                text: c.symbol().to_string(),
                color,
                bold: c.modifier.contains(Modifier::BOLD),
            });
            if c.modifier.contains(Modifier::UNDERLINED) {
                out.push(Step::Under {
                    x: x as f64 * cell.w,
                    y: top + cell.h - 1.0,
                    w: cells as f64 * cell.w,
                    color,
                });
            }
        }
    }
    out
}

/// The text cursor on a cell, drawn after the grid's steps: a block of the text's color with the cell's symbol
/// over it in the ground's. While the window is not the one typed into, the block's outline alone, the symbol
/// as it was. Nothing for a cell that is not on the grid.
pub fn cursor(buf: &Buffer, cell: Cell, tones: &Tones, (x, y): (u16, u16), focused: bool) -> Vec<Step> {
    if x >= buf.area.width || y >= buf.area.height {
        return vec![];
    }
    let c = &buf[(x, y)];
    let cells = wide(c.symbol());
    let (left, top, w, h) = (x as f64 * cell.w, y as f64 * cell.h, cells as f64 * cell.w, cell.h);
    let fill = |x, y, w, h| Step::Fill { x, y, w, h, color: tones.ink };
    if !focused {
        return vec![
            fill(left, top, w, 1.0),
            fill(left, top + h - 1.0, w, 1.0),
            fill(left, top, 1.0, h),
            fill(left + w - 1.0, top, 1.0, h),
        ];
    }
    let mut out = vec![fill(left, top, w, h)];
    if !c.symbol().trim().is_empty() {
        out.push(Step::Symbol {
            x: left,
            y: top,
            cells,
            text: c.symbol().to_string(),
            color: tones.ground,
            bold: c.modifier.contains(Modifier::BOLD),
        });
    }
    out
}

/// How many cells a symbol takes: two for a wide one, else one.
fn wide(symbol: &str) -> u16 {
    use unicode_width::UnicodeWidthChar;
    match symbol.chars().next().and_then(UnicodeWidthChar::width) {
        Some(2) => 2,
        _ => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::{Rect, Style};

    const GROUND: Rgb = [10, 10, 10];
    const INK: Rgb = [200, 200, 200];
    const CELL: Cell = Cell { w: 10.0, h: 20.0 };

    fn tones() -> Tones<'static> {
        Tones {
            ground: GROUND,
            ink: INK,
            slot: &|n| [n, n, n],
        }
    }

    #[test]
    fn the_ground_then_a_box_a_run_then_each_symbol_in_its_cell() {
        let mut b = Buffer::empty(Rect::new(0, 0, 8, 2));
        b.set_string(1, 0, "ab", Style::default().bg(Color::Rgb(1, 2, 3)));
        b.set_string(
            3,
            0,
            "c",
            Style::default().bg(Color::Rgb(1, 2, 3)).fg(Color::Indexed(7)).add_modifier(Modifier::BOLD),
        );
        b.set_string(5, 0, "d", Style::default().bg(Color::Rgb(9, 9, 9)));
        b.set_string(0, 1, "\u{754c}x", Style::default().add_modifier(Modifier::UNDERLINED));
        let got = steps(&b, CELL, &tones());
        let sym = |x: f64, y: f64, cells, text: &str, color, bold| Step::Symbol {
            x,
            y,
            cells,
            text: text.into(),
            color,
            bold,
        };
        assert_eq!(
            got,
            vec![
                // the whole window's ground, once
                Step::Fill {
                    x: 0.0,
                    y: 0.0,
                    w: 80.0,
                    h: 40.0,
                    color: GROUND
                },
                // three cells of one color are one box; the next color its own; the ground's cells none
                Step::Fill {
                    x: 10.0,
                    y: 0.0,
                    w: 30.0,
                    h: 20.0,
                    color: [1, 2, 3]
                },
                Step::Fill {
                    x: 50.0,
                    y: 0.0,
                    w: 10.0,
                    h: 20.0,
                    color: [9, 9, 9]
                },
                sym(10.0, 0.0, 1, "a", INK, false),
                sym(20.0, 0.0, 1, "b", INK, false),
                sym(30.0, 0.0, 1, "c", [7, 7, 7], true),
                sym(50.0, 0.0, 1, "d", INK, false),
                // a wide symbol takes two cells, and the line under it both; the space after it draws nothing
                sym(0.0, 20.0, 2, "\u{754c}", INK, false),
                Step::Under {
                    x: 0.0,
                    y: 39.0,
                    w: 20.0,
                    color: INK
                },
                sym(20.0, 20.0, 1, "x", INK, false),
                Step::Under {
                    x: 20.0,
                    y: 39.0,
                    w: 10.0,
                    color: INK
                },
            ]
        );
    }

    #[test]
    fn a_pictures_pixels_are_multiplied_by_their_alpha() {
        let img = Image::from_rgba(2, 1, &[255, 128, 0, 255, 200, 100, 50, 128]).unwrap();
        let pic = Pic::of(&img);
        assert_eq!((pic.w, pic.h, pic.data.len()), (2, 1, 8));
        let px = |i: usize| u32::from_ne_bytes(pic.data[i * 4..i * 4 + 4].try_into().unwrap());
        assert_eq!(px(0), 0xffff8000, "a solid pixel is itself: alpha, red, green, blue");
        assert_eq!(px(1), 0x80643219, "half clear: each color about half");
    }

    #[test]
    fn the_cursor_is_a_block_under_its_symbol_and_an_outline_out_of_focus() {
        let mut b = Buffer::empty(Rect::new(0, 0, 4, 2));
        b.set_string(1, 1, "a", Style::default().add_modifier(Modifier::BOLD));
        let fill = |x: f64, y: f64, w: f64, h: f64| Step::Fill { x, y, w, h, color: INK };
        // on a symbol: the block in the text's color, the symbol again in the ground's
        assert_eq!(
            cursor(&b, CELL, &tones(), (1, 1), true),
            vec![
                fill(10.0, 20.0, 10.0, 20.0),
                Step::Symbol {
                    x: 10.0,
                    y: 20.0,
                    cells: 1,
                    text: "a".into(),
                    color: GROUND,
                    bold: true
                }
            ]
        );
        // on a space: the block alone
        assert_eq!(cursor(&b, CELL, &tones(), (2, 0), true), vec![fill(20.0, 0.0, 10.0, 20.0)]);
        // the window not typed into: four lines around the cell, nothing over its symbol
        assert_eq!(
            cursor(&b, CELL, &tones(), (1, 1), false),
            vec![
                fill(10.0, 20.0, 10.0, 1.0),
                fill(10.0, 39.0, 10.0, 1.0),
                fill(10.0, 20.0, 1.0, 20.0),
                fill(19.0, 20.0, 1.0, 20.0)
            ]
        );
        assert_eq!(cursor(&b, CELL, &tones(), (4, 0), true), vec![], "past the grid");
    }

    #[test]
    fn a_cell_a_picture_stands_on_draws_nothing_and_keeps_the_ground() {
        let mut b = Buffer::empty(Rect::new(0, 0, 3, 1));
        b.set_string(0, 0, "abc", Style::default().bg(Color::Rgb(5, 5, 5)));
        b[(1, 0)].set_diff_option(CellDiffOption::Skip);
        let got = steps(&b, CELL, &tones());
        assert_eq!(
            got[1..],
            [
                Step::Fill {
                    x: 0.0,
                    y: 0.0,
                    w: 10.0,
                    h: 20.0,
                    color: [5, 5, 5]
                },
                Step::Fill {
                    x: 20.0,
                    y: 0.0,
                    w: 10.0,
                    h: 20.0,
                    color: [5, 5, 5]
                },
                Step::Symbol {
                    x: 0.0,
                    y: 0.0,
                    cells: 1,
                    text: "a".into(),
                    color: INK,
                    bold: false
                },
                Step::Symbol {
                    x: 20.0,
                    y: 0.0,
                    cells: 1,
                    text: "c".into(),
                    color: INK,
                    bold: false
                },
            ],
            "the picture's cell has no box and no symbol"
        );
    }
}
