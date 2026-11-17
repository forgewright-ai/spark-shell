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

#[test]
fn a_picture_is_painted_where_it_stands_over_the_ground_at_its_scale() {
    use spark_dialog::draw::{Pic, Step};
    use spark_dialog::sixel::Image;
    use std::sync::Arc;
    let Ok(lib) = Lib::open() else {
        eprintln!("  NOTICE: cairo or pango is not here -- the painter is not exercised");
        return;
    };
    let Some(font) = Font::new(&lib, &face()) else {
        eprintln!("  NOTICE: no font {:?} here -- the painter is not exercised", face());
        return;
    };
    // four pixels by two: the left half solid red, the right half blue at half opacity
    let mut rgba = vec![];
    for _ in 0..2 {
        rgba.extend_from_slice(&[255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 128, 0, 0, 255, 128]);
    }
    let pic = Arc::new(Pic::of(&Image::from_rgba(4, 2, &rgba).unwrap()));
    let ground = [20u8, 40, 60];
    let fill = Step::Fill {
        x: 0.0,
        y: 0.0,
        w: 16.0,
        h: 8.0,
        color: ground,
    };
    let painted = |scale: f64, pic_scale: f64| {
        let (w, h) = ((16.0 * scale) as usize, (8.0 * scale) as usize);
        let mut data = vec![0u8; w * h * 4];
        let px = Pixels {
            data: &mut data,
            w: w as i32,
            h: h as i32,
            stride: (w * 4) as i32,
            scale,
        };
        let todo = [
            fill.clone(),
            Step::Picture {
                x: 2.0,
                y: 3.0,
                scale: pic_scale,
                pic: pic.clone(),
            },
        ];
        assert!(paint(&lib, &font, px, &todo));
        (data, w * 4)
    };
    // a window pixel a screen pixel: the picture's corner at (2, 3), each of its pixels one of the window's
    let (data, stride) = painted(1.0, 1.0);
    assert_eq!(pixel(&data, stride, 1, 3), ground, "the ground before it");
    assert_eq!(pixel(&data, stride, 2, 3), [255, 0, 0], "its first pixel, solid");
    assert_eq!(pixel(&data, stride, 3, 4), [255, 0, 0]);
    let mixed = pixel(&data, stride, 4, 3);
    assert!(
        mixed[0].abs_diff(10) <= 2 && mixed[1].abs_diff(20) <= 2 && mixed[2].abs_diff(158) <= 2,
        "a half clear pixel lets half the ground through: {mixed:?}"
    );
    assert_eq!(pixel(&data, stride, 6, 3), ground, "the ground after it");
    assert_eq!(pixel(&data, stride, 2, 5), ground, "and under it");
    // a screen of twice the pixels, the picture made for it: it stands at the same place, pixel for pixel
    let (data, stride) = painted(2.0, 2.0);
    assert_eq!(pixel(&data, stride, 3, 6), ground);
    assert_eq!(pixel(&data, stride, 4, 6), [255, 0, 0], "its first pixel at twice the place");
    assert_eq!(pixel(&data, stride, 5, 7), [255, 0, 0]);
    assert_eq!(pixel(&data, stride, 8, 6), ground, "four of the screen's pixels wide, not eight");
    assert_eq!(pixel(&data, stride, 4, 8), ground, "and two high");
    font.free(&lib);
}
