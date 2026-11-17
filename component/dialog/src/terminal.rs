//! The grid shown in a terminal: the one place the terminal library's own cells are named. A window of the
//! dialog's own needs none of this.

use crate::grid;
use ratatui::buffer::{Buffer, CellDiffOption};
use ratatui::style::{Color, Modifier};

/// A grid's color as the terminal library names it.
pub fn color(c: grid::Color) -> Color {
    match c {
        grid::Color::Reset => Color::Reset,
        grid::Color::Indexed(n) => Color::Indexed(n),
        grid::Color::Rgb(r, g, b) => Color::Rgb(r, g, b),
    }
}

/// A grid laid on the terminal's frame, cell for cell, as far as both reach: the symbol, its colors, its weight,
/// and whether the terminal leaves the cell alone (a picture stands there).
pub fn blit(from: &grid::Buffer, to: &mut Buffer) {
    for y in 0..from.area.height.min(to.area.height) {
        for x in 0..from.area.width.min(to.area.width) {
            let c = &from[(x, y)];
            let t = &mut to[(x, y)];
            t.set_symbol(c.symbol());
            t.fg = color(c.fg);
            t.bg = color(c.bg);
            let mut modifier = Modifier::empty();
            if c.modifier.contains(grid::Modifier::BOLD) {
                modifier |= Modifier::BOLD;
            }
            if c.modifier.contains(grid::Modifier::UNDERLINED) {
                modifier |= Modifier::UNDERLINED;
            }
            t.modifier = modifier;
            t.set_diff_option(if c.diff_option == grid::CellDiffOption::Skip {
                CellDiffOption::Skip
            } else {
                CellDiffOption::None
            });
        }
    }
}
