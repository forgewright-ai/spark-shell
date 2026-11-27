//! The color picker's model: a color as three things a person can change one at a time (its hue, its shade, its
//! strength), each a strip of swatches, with the value typed in the prompt as the fourth way. The strips are cut in
//! OKLCH, so a step of shade keeps the hue and two hues of one shade look as light as each other; every swatch is a
//! color the screen can show.

use spark_theme::Rgb;

/// The hues of a strip, evenly around the wheel.
pub const HUES: usize = 18;
/// The shades of a strip, from light to dark.
pub const SHADES: [f32; 12] = [0.97, 0.91, 0.84, 0.77, 0.70, 0.63, 0.56, 0.49, 0.42, 0.34, 0.26, 0.17];
/// The strengths of a strip: gray first, then toward the most the screen shows at that hue and shade.
pub const STRENGTHS: [f32; 6] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];

/// One of the picker's strips, top to bottom.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Strip {
    Hue,
    Shade,
    Strength,
    /// The other colors of what is being changed (a theme's 20), to take one as it is.
    Theirs,
}

/// A color while it is picked.
#[derive(Clone, Debug, PartialEq)]
pub struct Picker {
    /// The color when the picker opened: Esc keeps it.
    pub was: Rgb,
    /// The color it must read against (text on the ground, the ground under text), when there is one.
    pub against: Option<Rgb>,
    /// The colors to take as they are, with their names.
    pub theirs: Vec<(String, Rgb)>,
    /// Lightness 0 to 1, strength 0 to 1 (of the most the screen shows there), hue in degrees.
    light: f32,
    strength: f32,
    hue: f32,
    /// The value as it is, where no strip made it: the color it opened with, one typed, one taken.
    exact: Option<Rgb>,
    pub strip: Strip,
    /// The swatch lit on the strip of the theme's colors.
    pub theirs_at: usize,
}

impl Picker {
    pub fn new(was: Rgb, against: Option<Rgb>, theirs: Vec<(String, Rgb)>) -> Picker {
        let mut p = Picker {
            was,
            against,
            theirs,
            light: 0.0,
            strength: 0.0,
            hue: 0.0,
            exact: None,
            strip: Strip::Hue,
            theirs_at: 0,
        };
        p.set(was);
        p.theirs_at = p.theirs.iter().position(|(_, c)| *c == was).unwrap_or(0);
        p
    }

    /// The color now.
    pub fn value(&self) -> Rgb {
        self.exact.unwrap_or_else(|| shown(self.light, self.strength, self.hue))
    }

    /// A color given whole (typed, or one of the theme's): the strips follow it.
    pub fn set(&mut self, c: Rgb) {
        let (l, ch, h) = oklch(c);
        let most = most(l, h);
        self.light = l;
        self.strength = if most > 0.0005 { (ch / most).clamp(0.0, 1.0) } else { 0.0 };
        // a gray has no hue of its own: the one before stays, so strength brings the same color back
        if ch > 0.004 {
            self.hue = h;
        }
        self.exact = Some(c);
    }

    /// The strip's swatches, as they would be with the other two as they are.
    pub fn swatches(&self, strip: Strip) -> Vec<Rgb> {
        match strip {
            Strip::Hue => (0..HUES).map(|i| shown(self.light, self.strength.max(0.35), hue_of(i))).collect(),
            Strip::Shade => SHADES.iter().map(|l| shown(*l, self.strength, self.hue)).collect(),
            Strip::Strength => STRENGTHS.iter().map(|s| shown(self.light, *s, self.hue)).collect(),
            Strip::Theirs => self.theirs.iter().map(|(_, c)| *c).collect(),
        }
    }

    /// The swatch nearest the color now, on a strip.
    pub fn at(&self, strip: Strip) -> usize {
        let near = |values: &mut dyn Iterator<Item = f32>, v: f32| {
            values
                .enumerate()
                .min_by(|a, b| (a.1 - v).abs().total_cmp(&(b.1 - v).abs()))
                .map_or(0, |(i, _)| i)
        };
        match strip {
            Strip::Hue => {
                let turn = |a: f32, b: f32| ((a - b + 540.0).rem_euclid(360.0) - 180.0).abs();
                (0..HUES)
                    .min_by(|a, b| turn(hue_of(*a), self.hue).total_cmp(&turn(hue_of(*b), self.hue)))
                    .unwrap_or(0)
            }
            Strip::Shade => near(&mut SHADES.iter().copied(), self.light),
            Strip::Strength => near(&mut STRENGTHS.iter().copied(), self.strength),
            Strip::Theirs => self.theirs_at.min(self.theirs.len().saturating_sub(1)),
        }
    }

    /// How many swatches a strip has.
    pub fn len(&self, strip: Strip) -> usize {
        match strip {
            Strip::Hue => HUES,
            Strip::Shade => SHADES.len(),
            Strip::Strength => STRENGTHS.len(),
            Strip::Theirs => self.theirs.len(),
        }
    }

    /// The strips there are, top to bottom: the theme's own colors only where it has some.
    pub fn strips(&self) -> Vec<Strip> {
        let mut v = vec![Strip::Hue, Strip::Shade, Strip::Strength];
        if !self.theirs.is_empty() {
            v.push(Strip::Theirs);
        }
        v
    }

    /// The swatch I of a strip taken: the color follows.
    pub fn pick(&mut self, strip: Strip, i: usize) {
        if i >= self.len(strip) {
            return;
        }
        self.strip = strip;
        match strip {
            Strip::Hue => {
                self.hue = hue_of(i);
                // a gray given a hue would stay gray: it takes the least strength that shows it
                if self.strength < STRENGTHS[1] {
                    self.strength = STRENGTHS[2];
                }
                self.exact = None;
            }
            Strip::Shade => {
                self.light = SHADES[i];
                self.exact = None;
            }
            Strip::Strength => {
                self.strength = STRENGTHS[i];
                self.exact = None;
            }
            Strip::Theirs => {
                self.theirs_at = i;
                let c = self.theirs[i].1;
                self.set(c);
            }
        }
    }

    /// Left or right along the strip lit; it stops at its ends, and the hues go around.
    pub fn step(&mut self, right: bool) {
        let (strip, n) = (self.strip, self.len(self.strip));
        if n == 0 {
            return;
        }
        let at = self.at(strip);
        let to = match (strip, right) {
            (Strip::Hue, true) => (at + 1) % n,
            (Strip::Hue, false) => (at + n - 1) % n,
            (_, true) => (at + 1).min(n - 1),
            (_, false) => at.saturating_sub(1),
        };
        // the color as typed may stand between two swatches: the first step lands on the nearest one; on the
        // list's own colors, with none of them the color now, on the one the strip stands at
        let off = self.swatches(strip).get(at) != Some(&self.value());
        let to = if off && (strip == Strip::Theirs || (self.exact.is_some() && strip != Strip::Hue)) {
            at
        } else {
            to
        };
        self.pick(strip, to);
    }

    /// Up or down to the strip beside; false at the first and the last, which the page takes.
    pub fn row(&mut self, down: bool) -> bool {
        let strips = self.strips();
        let at = strips.iter().position(|s| *s == self.strip).unwrap_or(0);
        let to = if down { at + 1 } else { at.wrapping_sub(1) };
        match strips.get(to) {
            Some(s) => {
                self.strip = *s;
                true
            }
            None => false,
        }
    }

    /// The contrast with the color it must read against, in hundredths (450 is 4.5 to 1); none where it has none.
    pub fn contrast(&self) -> Option<u32> {
        self.against.map(|o| contrast(self.value(), o))
    }

    /// Whether the color now is the one it opened with.
    pub fn unchanged(&self) -> bool {
        self.value() == self.was
    }
}

/// `#rrggbb` as the shell takes it.
pub fn hex_of(c: Rgb) -> String {
    format!("#{:02x}{:02x}{:02x}", c[0], c[1], c[2])
}

/// A color typed in the prompt, whole: `#rrggbb`, `rrggbb`, and the short `#rgb`.
pub fn typed(s: &str) -> Option<Rgb> {
    let t = s.trim().trim_start_matches('#');
    if t.len() == 3 && t.bytes().all(|b| b.is_ascii_hexdigit()) {
        let wide: String = t.chars().flat_map(|c| [c, c]).collect();
        return spark_theme::hex_digits(&wide);
    }
    spark_theme::hex_digits(t)
}

/// WCAG contrast of two colors, in hundredths, as spark-shell's hex_contrast gives it.
pub fn contrast(a: Rgb, b: Rgb) -> u32 {
    let lum = |c: Rgb| {
        let f = |v: u8| {
            let x = f64::from(v) / 255.0;
            if x <= 0.03928 {
                x / 12.92
            } else {
                ((x + 0.055) / 1.055).powf(2.4)
            }
        };
        0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
    };
    let (x, y) = (lum(a), lum(b));
    let (hi, lo) = if x > y { (x, y) } else { (y, x) };
    ((hi + 0.05) / (lo + 0.05) * 100.0) as u32
}

fn hue_of(i: usize) -> f32 {
    // the first swatch a red, as a color wheel starts
    (25.0 + i as f32 * 360.0 / HUES as f32).rem_euclid(360.0)
}

/// The color the screen shows for a lightness, a strength of the most it has there, and a hue.
fn shown(light: f32, strength: f32, hue: f32) -> Rgb {
    let c = most(light, hue) * strength.clamp(0.0, 1.0);
    srgb(light, c, hue).map_or([0, 0, 0], |v| v.map(|x| (x.clamp(0.0, 1.0) * 255.0).round() as u8))
}

/// The most chroma the screen shows at a lightness and a hue.
fn most(light: f32, hue: f32) -> f32 {
    let (mut lo, mut hi) = (0.0_f32, 0.4_f32);
    for _ in 0..16 {
        let mid = (lo + hi) / 2.0;
        if srgb(light, mid, hue).is_some() {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    lo
}

/// OKLCH to sRGB, each channel 0 to 1; none when the screen cannot show it.
fn srgb(l: f32, c: f32, h: f32) -> Option<[f32; 3]> {
    let (a, b) = (c * h.to_radians().cos(), c * h.to_radians().sin());
    let l_ = l + 0.396_337_78 * a + 0.215_803_76 * b;
    let m_ = l - 0.105_561_346 * a - 0.063_854_17 * b;
    let s_ = l - 0.089_484_18 * a - 1.291_485_5 * b;
    let (l3, m3, s3) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_);
    let lin = [
        4.076_741_7 * l3 - 3.307_711_6 * m3 + 0.230_969_94 * s3,
        -1.268_438 * l3 + 2.609_757_4 * m3 - 0.341_319_38 * s3,
        -0.004_196_086_3 * l3 - 0.703_418_6 * m3 + 1.707_614_7 * s3,
    ];
    let eps = 0.000_5;
    if lin.iter().any(|v| *v < -eps || *v > 1.0 + eps) {
        return None;
    }
    Some(lin.map(|v| {
        let v = v.clamp(0.0, 1.0);
        if v <= 0.003_130_8 {
            12.92 * v
        } else {
            1.055 * v.powf(1.0 / 2.4) - 0.055
        }
    }))
}

/// sRGB to OKLCH: lightness 0 to 1, chroma, hue in degrees.
fn oklch(c: Rgb) -> (f32, f32, f32) {
    let lin = c.map(|v| {
        let x = f32::from(v) / 255.0;
        if x <= 0.040_45 {
            x / 12.92
        } else {
            ((x + 0.055) / 1.055).powf(2.4)
        }
    });
    let l = (0.412_221_46 * lin[0] + 0.536_332_55 * lin[1] + 0.051_445_995 * lin[2]).cbrt();
    let m = (0.211_903_5 * lin[0] + 0.680_699_5 * lin[1] + 0.107_396_96 * lin[2]).cbrt();
    let s = (0.088_302_46 * lin[0] + 0.281_718_85 * lin[1] + 0.629_978_7 * lin[2]).cbrt();
    let ll = 0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s;
    let a = 1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s;
    let b = 0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s;
    (ll, (a * a + b * b).sqrt(), b.atan2(a).to_degrees().rem_euclid(360.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn far(a: Rgb, b: Rgb) -> i32 {
        (0..3).map(|i| (i32::from(a[i]) - i32::from(b[i])).abs()).max().unwrap()
    }

    #[test]
    fn a_color_goes_to_oklch_and_back_as_it_was() {
        for c in [
            [0x1e, 0x1e, 0x2e],
            [0xcd, 0xd6, 0xf4],
            [0xcb, 0xa6, 0xf7],
            [255, 0, 0],
            [0, 255, 0],
            [0, 0, 255],
            [0, 0, 0],
            [255, 255, 255],
            [0x80, 0x80, 0x80],
        ] {
            let (l, ch, h) = oklch(c);
            let back = srgb(l, ch, h).map(|v| v.map(|x| (x * 255.0).round() as u8));
            assert!(back.is_some_and(|b| far(b, c) <= 1), "{:?} came back as {:?}", c, back);
        }
    }

    #[test]
    fn it_opens_on_the_color_it_was_given_and_says_it_until_a_strip_moves() {
        let was = [0xcd, 0xd6, 0xf4];
        let mut p = Picker::new(was, Some([0x1e, 0x1e, 0x2e]), vec![]);
        assert_eq!(p.value(), was, "the value as it is, not the swatch nearest");
        assert!(p.unchanged());
        assert_eq!(
            p.strips(),
            vec![Strip::Hue, Strip::Shade, Strip::Strength],
            "no strip of colors there are none of"
        );
        // the first step along the shades lands on the swatch nearest, then each step is one swatch
        p.strip = Strip::Shade;
        let near = p.at(Strip::Shade);
        p.step(true);
        assert_eq!(p.at(Strip::Shade), near, "the first step takes the nearest shade");
        assert_eq!(p.value(), p.swatches(Strip::Shade)[near]);
        p.step(true);
        assert_eq!(p.at(Strip::Shade), near + 1);
        assert!(!p.unchanged());
    }

    #[test]
    fn every_swatch_is_a_color_and_the_lit_one_is_the_value() {
        let mut p = Picker::new([0x89, 0xb4, 0xfa], None, vec![("red".into(), [0xf3, 0x8b, 0xa8])]);
        for strip in [Strip::Hue, Strip::Shade, Strip::Strength] {
            for i in 0..p.len(strip) {
                p.pick(strip, i);
                assert_eq!(p.at(strip), i, "{:?} {}", strip, i);
                // the hue strip shows its hues at a strength that tells them apart; the others show the value itself
                if strip != Strip::Hue {
                    assert!(
                        far(p.swatches(strip)[i], p.value()) <= 1,
                        "{:?} {}: {:?} is not {:?}",
                        strip,
                        i,
                        p.swatches(strip)[i],
                        p.value()
                    );
                }
            }
        }
        p.pick(Strip::Theirs, 0);
        assert_eq!(p.value(), [0xf3, 0x8b, 0xa8], "one of the theme's own, as it is");
        p.pick(Strip::Theirs, 7);
        assert_eq!(p.value(), [0xf3, 0x8b, 0xa8], "no swatch there: nothing changes");
    }

    #[test]
    fn the_shades_go_from_light_to_dark_and_the_strengths_from_gray() {
        let p = Picker::new([0xf3, 0x8b, 0xa8], None, vec![]);
        let light = |c: Rgb| u32::from(c[0]) * 299 + u32::from(c[1]) * 587 + u32::from(c[2]) * 114;
        let shades = p.swatches(Strip::Shade);
        assert!(shades.windows(2).all(|w| light(w[0]) > light(w[1])), "{:?}", shades);
        let strengths = p.swatches(Strip::Strength);
        assert!(far(strengths[0], [strengths[0][1]; 3]) <= 2, "the first strength is a gray: {:?}", strengths[0]);
        let spread = |c: Rgb| i32::from(*c.iter().max().unwrap()) - i32::from(*c.iter().min().unwrap());
        assert!(strengths.windows(2).all(|w| spread(w[0]) < spread(w[1])), "{:?}", strengths);
    }

    #[test]
    fn a_gray_takes_a_hue_and_the_hues_go_around() {
        let mut p = Picker::new([0x80, 0x80, 0x80], None, vec![]);
        p.pick(Strip::Hue, 0);
        let c = p.value();
        assert!(c[0] > c[2] + 20, "the first hue is a red: {:?}", c);
        p.strip = Strip::Hue;
        p.step(false);
        assert_eq!(p.at(Strip::Hue), HUES - 1, "left of the first hue is the last");
        p.step(true);
        assert_eq!(p.at(Strip::Hue), 0);
    }

    #[test]
    fn the_first_step_along_the_lists_own_colors_takes_the_first() {
        let mut p = Picker::new([1, 2, 3], None, vec![("a".into(), [10, 10, 10]), ("b".into(), [20, 20, 20])]);
        p.strip = Strip::Theirs;
        p.step(true);
        assert_eq!(p.value(), [10, 10, 10], "none of them was the color: the first, not the second");
        p.step(true);
        assert_eq!(p.value(), [20, 20, 20]);
        p.step(true);
        assert_eq!(p.value(), [20, 20, 20], "it stops at the last");
        p.step(false);
        assert_eq!(p.value(), [10, 10, 10]);
    }

    #[test]
    fn up_and_down_move_between_the_strips_and_stop_at_the_ends() {
        let mut p = Picker::new([1, 2, 3], None, vec![("x".into(), [9, 9, 9])]);
        assert!(!p.row(false), "above the first strip is the page's");
        assert!(p.row(true) && p.row(true) && p.row(true));
        assert_eq!(p.strip, Strip::Theirs);
        assert!(!p.row(true));
    }

    #[test]
    fn a_typed_color_and_its_contrast() {
        assert_eq!(typed("#ff8800"), Some([0xff, 0x88, 0x00]));
        assert_eq!(typed(" FF8800 "), Some([0xff, 0x88, 0x00]));
        assert_eq!(typed("#f80"), Some([0xff, 0x88, 0x00]));
        assert_eq!(typed("banana"), None);
        assert_eq!(typed("#ff88"), None);
        assert_eq!(hex_of([0xff, 0x88, 0x00]), "#ff8800");
        assert_eq!(contrast([255, 255, 255], [0, 0, 0]), 2100);
        assert_eq!(contrast([0, 0, 0], [0, 0, 0]), 100);
        let p = Picker::new([0xcd, 0xd6, 0xf4], Some([0x1e, 0x1e, 0x2e]), vec![]);
        assert!(p.contrast().is_some_and(|c| c > 1000), "{:?}", p.contrast());
    }
}
