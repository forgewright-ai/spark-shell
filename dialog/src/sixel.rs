//! The mark: the repo's favicon, its drawing cropped from the square, one
//! row tall, drawn through sixel. The PNGs (assets/mark-H.png, H the row's
//! pixels) are embedded at build time, never read from a path at run time;
//! a terminal without sixel draws nothing.

const DARK: [(u32, &[u8]); 4] = [
    (16, include_bytes!("../assets/mark-16.png")),
    (19, include_bytes!("../assets/mark-19.png")),
    (22, include_bytes!("../assets/mark-22.png")),
    (26, include_bytes!("../assets/mark-26.png")),
];
const LIGHT: [(u32, &[u8]); 4] = [
    (16, include_bytes!("../assets/mark-light-16.png")),
    (19, include_bytes!("../assets/mark-light-19.png")),
    (22, include_bytes!("../assets/mark-light-22.png")),
    (26, include_bytes!("../assets/mark-light-26.png")),
];

/// The terminals that draw sixel, by TERM: foot (1.28 on the box), and
/// the ones that say so in their name. Anything else draws no mark.
pub fn terminal_draws_it(term: &str) -> bool {
    term.starts_with("foot") || term.contains("sixel")
}

/// The size for a row of `cell_h` pixels: the largest that fits, or none.
pub fn pick(cell_h: u32) -> Option<u32> {
    DARK.iter().map(|(n, _)| *n).filter(|n| *n <= cell_h).max()
}

/// RGBA pixels of the mark `n` pixels tall, dark or light.
pub fn pixels(n: u32, dark: bool) -> Option<(u32, u32, Vec<u8>)> {
    let set = if dark { &DARK } else { &LIGHT };
    let bytes = set.iter().find(|(s, _)| *s == n)?.1;
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

/// A sixel image of RGBA pixels: colours rounded to 4 bits a channel, a
/// pixel under half opacity left unpainted (the background shows).
pub fn encode(w: u32, h: u32, rgba: &[u8]) -> String {
    let mut colours: Vec<(u8, u8, u8)> = Vec::new();
    let mut index = vec![usize::MAX; (w * h) as usize];
    for i in 0..(w * h) as usize {
        let p = &rgba[i * 4..i * 4 + 4];
        if p[3] < 128 {
            continue;
        }
        let c = (p[0] >> 4, p[1] >> 4, p[2] >> 4);
        let k = match colours.iter().position(|x| *x == c) {
            Some(k) => k,
            None => {
                colours.push(c);
                colours.len() - 1
            }
        };
        index[i] = k;
    }
    // DCS P1=0 P2=1 (unpainted pixels stay transparent), raster 1:1 at w x h
    let mut out = format!("\x1bP0;1;0q\"1;1;{};{}", w, h);
    for (k, (r, g, b)) in colours.iter().enumerate() {
        let pct = |v: u8| (v as u32 * 17 * 100 + 127) / 255;
        out.push_str(&format!("#{};2;{};{};{}", k, pct(*r), pct(*g), pct(*b)));
    }
    let mut band = 0;
    while band < h {
        let mut first = true;
        for k in 0..colours.len() {
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
    fn every_size_decodes_a_row_tall_three_cells_at_most_and_transparent_at_the_corner() {
        for dark in [true, false] {
            for n in [16, 19, 22, 26] {
                let (w, h, px) = pixels(n, dark).expect("decodes");
                assert_eq!(h, n);
                assert!(w <= n * 3 * 6 / 10 * 2, "{} wide at {} tall", w, h);
                assert!(px[((w - 1) * 4 + 3) as usize] < 128, "the top right corner has no ground of its own");
                assert!(px.chunks(4).any(|p| p[3] > 200), "and the mark is there");
            }
        }
    }

    #[test]
    fn the_size_is_the_largest_that_fits_the_row() {
        assert_eq!(pick(21), Some(19));
        assert_eq!(pick(30), Some(26));
        assert_eq!(pick(12), None);
    }

    #[test]
    fn sixel_shape() {
        let s = mark(22, true).unwrap();
        assert!(s.starts_with("\x1bP0;1;0q\"1;1;31;22") && s.ends_with("\x1b\\"));
        assert_eq!(s.matches('-').count(), 4, "22 rows are four bands of six");
        assert!(terminal_draws_it("foot") && terminal_draws_it("foot-extra") && !terminal_draws_it("xterm-256color"));
    }
}
