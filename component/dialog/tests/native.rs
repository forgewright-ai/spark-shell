//! The dialog painted for a window of its own: the grid's steps through cairo and pango, on a machine that has
//! both. Elsewhere (a build with no shared libraries, a container without them) the test says so and passes:
//! the steps themselves are proven in draw.rs, with neither.
#![cfg(target_os = "linux")]

mod common;

use spark_dialog::app::{App, Config};
use spark_dialog::draw::{steps, tones};
use spark_dialog::grid::{Buffer, Color, Rect};
use spark_dialog::paint::{paint, png, Font, Lib, Pixels};

fn face() -> String {
    std::env::var("DIALOG_FONT").unwrap_or_else(|_| "monospace 12".into())
}

fn pixel(data: &[u8], stride: usize, x: usize, y: usize) -> [u8; 3] {
    // cairo's ARGB32 in memory on a little-endian machine: blue, green, red, alpha
    let i = y * stride + x * 4;
    [data[i + 2], data[i + 1], data[i]]
}

#[test]
fn home_is_painted_cell_for_cell_with_cairo_and_pango() {
    let Ok(lib) = Lib::open() else {
        eprintln!("  NOTICE: cairo or pango is not here -- the painter is not exercised");
        return;
    };
    let Some(font) = Font::new(&lib, &face()) else {
        eprintln!("  NOTICE: no font {:?} here -- the painter is not exercised", face());
        return;
    };
    let pal = common::palette("tokyonight-night");
    let mut app = App::new(
        Config {
            model: true,
            talk: true,
            ..Config::default()
        },
        &[],
    );
    app.size = (60, 40);
    let mut grid = Buffer::empty(Rect::new(0, 0, 60, 40));
    spark_dialog::ui::draw(&app, &pal, "", &mut grid);
    let todo = steps(&grid, font.cell, &tones(&pal));
    let (cw, ch) = (font.cell.w as usize, font.cell.h as usize);
    assert!(cw >= 4 && ch >= 8, "a cell the text can stand in: {cw} by {ch}");
    let (w, h) = (60 * cw, 40 * ch);
    let mut data = vec![0u8; w * h * 4];
    let px = Pixels {
        data: &mut data,
        w: w as i32,
        h: h as i32,
        stride: (w * 4) as i32,
        scale: 1.0,
    };
    assert!(paint(&lib, &font, px, &todo));
    let rgb = |c: Color| match c {
        Color::Rgb(r, g, b) => [r, g, b],
        _ => panic!("a palette of colors"),
    };
    let cell = |x: usize, y: usize| -> Vec<[u8; 3]> {
        (0..ch)
            .flat_map(|py| (0..cw).map(move |px| (px, py)))
            .map(|(px, py)| pixel(&data, w * 4, x * cw + px, y * ch + py))
            .collect()
    };
    // the band: its first row is the band's color from side to side, behind the title's letters
    assert_eq!(pixel(&data, w * 4, 0, 0), rgb(pal.band), "the band's ground at the window's corner");
    assert_eq!(pixel(&data, w * 4, w - 1, ch - 1), rgb(pal.band), "to its other end");
    // a cell with nothing in it is the surface, every pixel
    assert!(cell(58, 1).iter().all(|p| *p == rgb(pal.surface)), "air under the band is the surface alone");
    // the prompt's sign stands in its cell, column 2 of the line: ink there, and none in the cell before it
    let line = spark_dialog::ui::head(&app).prompt as usize;
    assert_eq!(grid[(2, line as u16)].symbol(), "\u{276f}");
    assert!(cell(2, line).iter().any(|p| *p != rgb(pal.surface)), "the prompt's sign is drawn in its cell");
    assert!(cell(1, line).iter().all(|p| *p == rgb(pal.surface)), "and nothing in the cell before it");
    // the last row, the window's bottom edge, stays empty
    assert!(
        (0..60).all(|x| cell(x, 39).iter().all(|p| *p == rgb(pal.surface))),
        "the last row is the surface"
    );
    if let Ok(dir) = std::env::var("NATIVE_PNG") {
        assert!(png(&lib, &font, w as i32, h as i32, &todo, &format!("{dir}/home.png")), "the picture written");
    }
    font.free(&lib);
}
