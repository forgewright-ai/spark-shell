//! Sixel: a picture beside a list (a wallpaper's, #36), drawn only where
//! the terminal draws sixel. Nothing is read from a path here: main.rs
//! hands over the PNG's bytes.

/// The terminals that draw sixel, by TERM: foot (1.28 on the box), and
/// the ones that say so in their name. Anything else draws no picture.
pub fn terminal_draws_it(term: &str) -> bool {
    term.starts_with("foot") || term.contains("sixel")
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

#[cfg(test)]
mod tests {
    use super::*;

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
        // 2 by 12 pixels, one color and a transparent half: a raster of 2 by 12, two bands of six
        let mut px = vec![];
        for y in 0..12 {
            for _x in 0..2 {
                px.extend(if y < 6 { [255u8, 224, 102, 255] } else { [0, 0, 0, 0] });
            }
        }
        let s = encode(2, 12, &px);
        assert!(s.starts_with("\x1bP0;1;0q\"1;1;2;12") && s.ends_with("\x1b\\"), "{}", s);
        assert_eq!(s.matches('-').count(), 2, "12 rows are two bands of six, each ended by -");
        assert!(s.contains("#0;2;100;88;40"), "the color, exact");
        assert!(terminal_draws_it("foot") && terminal_draws_it("foot-extra") && !terminal_draws_it("xterm-256color"));
    }
}
