//! The mark: the repo's favicon, one row tall, drawn through sixel. The
//! favicon is pixel art (the block letters, their one-pixel shadow lines,
//! the prompt sign), so the mark is a pixel grid snapped from
//! assets/favicon.svg: a block 2 by 3 pixels, a shadow line 1, the exact
//! colors, drawn at a whole multiple of its rows. A row shorter than the
//! grid keeps the 16 px PNG. Nothing is read from a path at run time; a
//! terminal without sixel draws nothing.

/// The mark's pixels, 29 by 18: a, b, c the letter's three bands, p the
/// prompt sign, k the cursor, . the surface showing through. The top row
/// is air, so the mark sits in the middle of a 19 px row.
const GRID: [&str; 18] = [
    ".............................",
    "aaaaaaaaaaaaaa...............",
    "aaaaaaaaaaaaaaaa.............",
    "aaaaaaaaaaaaaa.a.............",
    "aaaa...........a.............",
    "aaaa.aaaaaaaaaaa.............",
    "aaaa.a.......................",
    "bbbbbbbbbbbbbb...............",
    "bbbbbbbbbbbbbbbb..pp.........",
    "bbbbbbbbbbbbbb.b...ppp.......",
    ".b........bbbb.b....ppp......",
    ".bbbbbbbbbbbbb.b.....ppp.....",
    "..........bbbb.b......ppp....",
    "cccccccccccccc.c.....ppp.....",
    "cccccccccccccc.c....ppp......",
    "cccccccccccccc.c...ppp.......",
    ".c.............c..pp.........",
    ".ccccccccccccccc..........kkk",
];
/// The favicon's colors on a dark palette (assets/favicon.svg) and a light one (favicon-light.svg).
const DARK_INK: [(char, [u8; 3]); 5] = [
    ('a', [0xff, 0xe0, 0x66]),
    ('b', [0xe0, 0xb4, 0x00]),
    ('c', [0xd2, 0x4a, 0x2a]),
    ('p', [0xe6, 0xdf, 0xd2]),
    ('k', [0xe0, 0xb4, 0x00]),
];
const LIGHT_INK: [(char, [u8; 3]); 5] = [
    ('a', [0xd4, 0xa4, 0x00]),
    ('b', [0xa8, 0x7e, 0x00]),
    ('c', [0xc2, 0x40, 0x1f]),
    ('p', [0x24, 0x1f, 0x18]),
    ('k', [0x7d, 0x60, 0x00]),
];
const SMALL_DARK: &[u8] = include_bytes!("../assets/mark-16.png");
const SMALL_LIGHT: &[u8] = include_bytes!("../assets/mark-light-16.png");

/// The terminals that draw sixel, by TERM: foot (1.28 on the box), and
/// the ones that say so in their name. Anything else draws no mark.
pub fn terminal_draws_it(term: &str) -> bool {
    term.starts_with("foot") || term.contains("sixel")
}

/// The mark's height for a row of `cell_h` pixels: the grid at the largest
/// whole multiple that fits, else the 16 px PNG, else none.
pub fn pick(cell_h: u32) -> Option<u32> {
    let rows = GRID.len() as u32;
    if cell_h >= rows {
        Some(cell_h / rows * rows)
    } else if cell_h >= 16 {
        Some(16)
    } else {
        None
    }
}

/// RGBA pixels of the mark `n` pixels tall (a value `pick` gave), dark or light.
pub fn pixels(n: u32, dark: bool) -> Option<(u32, u32, Vec<u8>)> {
    let rows = GRID.len() as u32;
    if n >= rows && n / rows * rows == n {
        let s = n / rows;
        let ink = if dark { &DARK_INK } else { &LIGHT_INK };
        let w = GRID[0].len() as u32 * s;
        let mut px = Vec::with_capacity((w * n * 4) as usize);
        for y in 0..n {
            let line = GRID[(y / s) as usize].as_bytes();
            for x in 0..w {
                let c = line[(x / s) as usize] as char;
                match ink.iter().find(|(k, _)| *k == c) {
                    Some((_, [r, g, b])) => px.extend([*r, *g, *b, 255]),
                    None => px.extend([0, 0, 0, 0]),
                }
            }
        }
        return Some((w, n, px));
    }
    if n != 16 {
        return None;
    }
    let bytes = if dark { SMALL_DARK } else { SMALL_LIGHT };
    let mut dec = png::Decoder::new(std::io::Cursor::new(bytes));
    dec.set_transformations(png::Transformations::normalize_to_color8());
    let mut r = dec.read_info().ok()?;
    let mut buf = vec![0; r.output_buffer_size()?];
    let info = r.next_frame(&mut buf).ok()?;
    let (w, h) = (info.width, info.height);
    let rgba: Vec<u8> = match info.color_type {
        png::ColorType::Rgba => buf[..(w * h * 4) as usize].to_vec(),
        png::ColorType::Rgb => buf[..(w * h * 3) as usize].chunks(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect(),
        _ => return None,
    };
    Some((w, h, rgba))
}

/// A sixel image of RGBA pixels: each color exact (sixel takes it in
/// percent), a pixel under half opacity left unpainted (the background shows).
pub fn encode(w: u32, h: u32, rgba: &[u8]) -> String {
    let mut colors: Vec<(u8, u8, u8)> = Vec::new();
    let mut index = vec![usize::MAX; (w * h) as usize];
    for i in 0..(w * h) as usize {
        let p = &rgba[i * 4..i * 4 + 4];
        if p[3] < 128 {
            continue;
        }
        let c = (p[0], p[1], p[2]);
        let k = match colors.iter().position(|x| *x == c) {
            Some(k) => k,
            None => {
                colors.push(c);
                colors.len() - 1
            }
        };
        index[i] = k;
    }
    // DCS P1=0 P2=1 (unpainted pixels stay transparent), raster 1:1 at w x h
    let mut out = format!("\x1bP0;1;0q\"1;1;{};{}", w, h);
    for (k, (r, g, b)) in colors.iter().enumerate() {
        let pct = |v: u8| (v as u32 * 100 + 127) / 255;
        out.push_str(&format!("#{};2;{};{};{}", k, pct(*r), pct(*g), pct(*b)));
    }
    let mut band = 0;
    while band < h {
        let mut first = true;
        for k in 0..colors.len() {
            let mut line = String::new();
            let mut any = false;
            let mut run: Option<(char, u32)> = None;
            for x in 0..w {
                let mut bits = 0u8;
                for dy in 0..6 {
                    let y = band + dy;
                    if y < h && index[(y * w + x) as usize] == k {
                        bits |= 1 << dy;
                    }
                }
                if bits != 0 {
                    any = true;
                }
                let ch = (63 + bits) as char;
                run = match run {
                    Some((c, n)) if c == ch => Some((c, n + 1)),
                    Some((c, n)) => {
                        push_run(&mut line, c, n);
                        Some((ch, 1))
                    }
                    None => Some((ch, 1)),
                };
            }
            if let Some((c, n)) = run {
                if c != '?' {
                    push_run(&mut line, c, n);
                }
            }
            if any {
                if !first {
                    out.push('$');
                }
                out.push_str(&format!("#{}", k));
                out.push_str(&line);
                first = false;
            }
        }
        out.push('-');
        band += 6;
    }
    out.push_str("\x1b\\");
    out
}

fn push_run(line: &mut String, c: char, n: u32) {
    if n > 3 {
        line.push_str(&format!("!{}{}", n, c));
    } else {
        for _ in 0..n {
            line.push(c);
        }
    }
}

/// A picture for a box of `bw` by `bh` pixels, as sixel (#36: a wallpaper beside its list): a PNG's
/// bytes made 8-bit color, scaled down to fit with its shape kept (each pixel the mean of the ones it
/// covers), its colors cut to at most 255 (the most used of a 4096-color grid, every other pixel the
/// nearest of them). None for bytes that are no PNG, a picture over 4096 pixels a side, or a box
/// under 8 pixels.
pub fn picture(png: &[u8], bw: u32, bh: u32) -> Option<String> {
    if bw < 8 || bh < 8 {
        return None;
    }
    let mut dec = png::Decoder::new(std::io::Cursor::new(png));
    dec.set_transformations(png::Transformations::normalize_to_color8());
    let mut r = dec.read_info().ok()?;
    let (w0, h0) = (r.info().width, r.info().height);
    if w0 == 0 || h0 == 0 || w0 > 4096 || h0 > 4096 {
        return None;
    }
    let mut buf = vec![0; r.output_buffer_size()?];
    let info = r.next_frame(&mut buf).ok()?;
    let ch: usize = match info.color_type {
        png::ColorType::Rgba => 4,
        png::ColorType::Rgb => 3,
        png::ColorType::GrayscaleAlpha => 2,
        png::ColorType::Grayscale => 1,
        _ => return None,
    };
    let line = info.line_size;
    let at = |x: u32, y: u32| -> [u32; 3] {
        let i = y as usize * line + x as usize * ch;
        if ch >= 3 {
            [buf[i] as u32, buf[i + 1] as u32, buf[i + 2] as u32]
        } else {
            [buf[i] as u32; 3]
        }
    };
    let k = (bw as f64 / w0 as f64).min(bh as f64 / h0 as f64).min(1.0);
    let (w, h) = (((w0 as f64 * k) as u32).max(1), ((h0 as f64 * k) as u32).max(1));
    let mut small: Vec<[u8; 3]> = Vec::with_capacity((w * h) as usize);
    for y in 0..h {
        let (y0, y1) = (y * h0 / h, ((y + 1) * h0 / h).max(y * h0 / h + 1).min(h0));
        for x in 0..w {
            let (x0, x1) = (x * w0 / w, ((x + 1) * w0 / w).max(x * w0 / w + 1).min(w0));
            let (mut sum, mut n) = ([0u32; 3], 0u32);
            for sy in y0..y1 {
                for sx in x0..x1 {
                    let c = at(sx, sy);
                    sum = [sum[0] + c[0], sum[1] + c[1], sum[2] + c[2]];
                    n += 1;
                }
            }
            small.push([(sum[0] / n) as u8, (sum[1] / n) as u8, (sum[2] / n) as u8]);
        }
    }
    // the colors: the 255 most used cells of a 16-step grid, each the mean of its pixels
    let key = |c: &[u8; 3]| ((c[0] as usize >> 4) << 8) | ((c[1] as usize >> 4) << 4) | (c[2] as usize >> 4);
    let mut bins = vec![(0u32, [0u32; 3]); 4096];
    for c in &small {
        let b = &mut bins[key(c)];
        b.0 += 1;
        b.1 = [b.1[0] + c[0] as u32, b.1[1] + c[1] as u32, b.1[2] + c[2] as u32];
    }
    let mut used: Vec<usize> = (0..4096).filter(|i| bins[*i].0 > 0).collect();
    used.sort_by(|a, b| bins[*b].0.cmp(&bins[*a].0).then(a.cmp(b)));
    used.truncate(255);
    let mean = |i: usize| {
        let (n, s) = bins[i];
        [(s[0] / n) as u8, (s[1] / n) as u8, (s[2] / n) as u8]
    };
    let mut to = vec![usize::MAX; 4096];
    for (j, i) in used.iter().enumerate() {
        to[*i] = j;
    }
    let inks: Vec<[u8; 3]> = used.iter().map(|i| mean(*i)).collect();
    let mut rgba = Vec::with_capacity(small.len() * 4);
    for c in &small {
        let j = match to[key(c)] {
            usize::MAX => {
                let d = |e: &[u8; 3]| (0..3).map(|q| (c[q] as i32 - e[q] as i32).pow(2)).sum::<i32>();
                (0..inks.len()).min_by_key(|j| d(&inks[*j])).unwrap_or(0)
            }
            j => j,
        };
        let e = inks.get(j).copied().unwrap_or(*c);
        rgba.extend([e[0], e[1], e[2], 255]);
    }
    Some(encode(w, h, &rgba))
}

/// The mark for a row `cell_h` pixels tall, ready to write at the cursor.
pub fn mark(cell_h: u32, dark: bool) -> Option<String> {
    let n = pick(cell_h)?;
    let (w, h, px) = pixels(n, dark)?;
    Some(encode(w, h, &px))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_grid_is_one_shape_and_every_letter_has_an_ink() {
        assert!(GRID.iter().all(|l| l.len() == GRID[0].len()), "every row as wide");
        for l in GRID {
            for c in l.chars() {
                assert!(c == '.' || DARK_INK.iter().any(|(k, _)| *k == c), "{} has no ink", c);
            }
        }
        assert_eq!(DARK_INK.map(|(k, _)| k), LIGHT_INK.map(|(k, _)| k));
        assert!(GRID[0].chars().all(|c| c == '.'), "the top row is air");
    }

    #[test]
    fn the_prompt_sign_is_symmetric_about_its_tip() {
        let at = |y: usize| GRID[y].char_indices().filter(|(_, c)| *c == 'p').map(|(i, _)| i).collect::<Vec<_>>();
        let rows: Vec<usize> = (0..GRID.len()).filter(|y| !at(*y).is_empty()).collect();
        let (top, bottom) = (rows[0], rows[rows.len() - 1]);
        for d in 0..=(bottom - top) / 2 {
            assert_eq!(at(top + d), at(bottom - d), "rows {} and {}", top + d, bottom - d);
        }
    }

    #[test]
    fn the_size_is_the_largest_whole_multiple_that_fits_the_row() {
        assert_eq!(pick(19), Some(18));
        assert_eq!(pick(38), Some(36));
        assert_eq!(pick(17), Some(16), "a short row keeps the small logo");
        assert_eq!(pick(12), None);
    }

    #[test]
    fn every_size_fits_three_cells_and_is_transparent_at_the_corner() {
        for dark in [true, false] {
            for (n, cell_w) in [(16, 9), (18, 10), (36, 20), (54, 30)] {
                let (w, h, px) = pixels(n, dark).expect("draws");
                assert_eq!(h, n);
                assert!(w <= cell_w * 3, "{} wide at {} tall", w, h);
                assert!(px[((w - 1) * 4 + 3) as usize] < 128, "the top right corner has no ground of its own");
                assert!(px.chunks(4).any(|p| p[3] > 200), "and the mark is there");
            }
        }
        let (_, _, px) = pixels(18, true).unwrap();
        assert_eq!(&px[(29 * 4)..(29 * 4 + 4)], &[0xff, 0xe0, 0x66, 255], "the exact color, row 1");
    }

    #[test]
    fn a_picture_fits_its_box_with_its_shape_and_few_colors() {
        // a 64 by 32 PNG, left half red, right half a gradient: 16 by 8 fits a box of 20 by 8
        let (w, h) = (64u32, 32u32);
        let mut raw = Vec::new();
        for _y in 0..h {
            for x in 0..w {
                if x < 32 {
                    raw.extend([200u8, 20, 20]);
                } else {
                    raw.extend([0u8, (x * 4) as u8, 255]);
                }
            }
        }
        let mut bytes = Vec::new();
        {
            let mut e = png::Encoder::new(&mut bytes, w, h);
            e.set_color(png::ColorType::Rgb);
            e.set_depth(png::BitDepth::Eight);
            e.write_header().unwrap().write_image_data(&raw).unwrap();
        }
        let s = picture(&bytes, 20, 8).expect("a picture");
        assert!(s.starts_with("\x1bP0;1;0q\"1;1;16;8") && s.ends_with("\x1b\\"), "{}", &s[..30]);
        assert!(s.contains(";2;78;8;8"), "the red, exact enough");
        assert!(picture(b"not a png", 20, 8).is_none());
        assert!(picture(&bytes, 4, 4).is_none(), "a box too small draws nothing");
    }

    #[test]
    fn sixel_shape() {
        let s = mark(19, true).unwrap();
        assert!(s.starts_with("\x1bP0;1;0q\"1;1;29;18") && s.ends_with("\x1b\\"));
        assert_eq!(s.matches('-').count(), 3, "18 rows are three bands of six");
        assert!(s.contains("#0;2;100;88;40"), "the top band's yellow, exact");
        assert!(terminal_draws_it("foot") && terminal_draws_it("foot-extra") && !terminal_draws_it("xterm-256color"));
    }
}
