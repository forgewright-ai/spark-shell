//! The six transitions drawn here, in the palette the dialog wears (#247, arc 2): moon, ripple, tide, embers,
//! sun and flight, as gallery/animation/make.py draws them, shape for shape. The shipped palettes play the GIFs
//! make.py drew ahead; a palette with none (a theme from a picture or from words, a palette file of yours)
//! plays these, drawn when the dialog opens or its look changes, from the colors it already has: no file, no
//! cache, no package. spark-shell names one as `draw:PIECE` where it would name a folder.
//!
//! A frame is the GIF's frame before its colors were cut to 255: each shape's coverage, one pixel of soft edge,
//! mixed onto the dialog's surface in order; a pixel inked less than 1/48 is left undrawn, so the frame lies on
//! the window's own ground. 180 by 120 cells' worth of pixels at 1x, twice that at 2x.

use crate::sixel::{show, Image, Viewport};
use crate::transition::{Film, Films, FRAME_MIN_MS};
use std::f64::consts::PI;

/// The pieces, in the order the theme's row steps through them (spark-shell's ANIMATION_NAMES).
pub const NAMES: [&str; 6] = ["moon", "ripple", "tide", "embers", "sun", "flight"];
pub const W: usize = 180;
pub const H: usize = 120;
const INK_MIN: f64 = 1.0 / 48.0;
/// foot's defaults, as spark-shell's FOOT_HEX: a palette's missing ANSI color.
const FOOT_HEX: [&str; 16] = [
    "242424", "f62b5a", "47b413", "e3c401", "24acd4", "f2affd", "13c299", "e6e6e6", "616161", "ff4d51", "35d450", "e9e836", "5dc5f8", "feabf2", "24dfc4",
    "ffffff",
];
const WHITE: Rgb = [255.0, 255.0, 255.0];
const BLACK: Rgb = [0.0, 0.0, 0.0];

type Rgb = [f64; 3];

fn rgb(h: &str) -> Option<Rgb> {
    let h = h.trim().trim_start_matches('#');
    if h.len() != 6 || !h.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let v = u32::from_str_radix(h, 16).ok()?;
    Some([(v >> 16) as f64, ((v >> 8) & 255) as f64, (v & 255) as f64])
}

fn mix(a: Rgb, b: Rgb, k: f64) -> Rgb {
    [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k]
}

/// spark-shell's hex_mix to the bit: shell arithmetic truncates toward zero.
fn hex_mix(a: Rgb, b: Rgb, pct: i64) -> Rgb {
    let m = |x: f64, y: f64| {
        let d = (y as i64 - x as i64) * pct;
        (x as i64 + d.signum() * (d.abs() / 100)) as f64
    };
    [m(a[0], b[0]), m(a[1], b[1]), m(a[2], b[2])]
}

/// spark-shell's hex_contrast: the WCAG contrast of the two, times 100.
fn hex_contrast(a: Rgb, b: Rgb) -> i64 {
    let lum = |c: Rgb| {
        let ch = c.map(|v| {
            let v = v / 255.0;
            if v <= 0.03928 {
                v / 12.92
            } else {
                ((v + 0.055) / 1.055).powf(2.4)
            }
        });
        0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
    };
    let (x, y) = (lum(a).max(lum(b)), lum(a).min(lum(b)));
    ((x + 0.05) / (y + 0.05) * 100.0) as i64
}

/// A palette as the pieces take it: the dialog's surface, its text, accent and quiet text, and the 16 colors.
#[derive(Clone, Debug, PartialEq)]
pub struct Roles {
    surface: Rgb,
    dark: bool,
    fg: Rgb,
    muted: Rgb,
    accent: Rgb,
    ansi: [Rgb; 16],
    yellow: Rgb,
}

impl Roles {
    fn with(surface: Rgb, fg: Rgb, muted: Rgb, accent: Rgb, ansi: [Rgb; 16]) -> Roles {
        let dark = (299.0 * surface[0] + 587.0 * surface[1] + 114.0 * surface[2]) / 1000.0 < 128.0;
        // a warm yellow that reads on the ground: on dark the palette's yellow lifted a little
        let yellow = if dark { mix(ansi[3], WHITE, 0.25) } else { ansi[3] };
        Roles {
            surface,
            dark,
            fg,
            muted,
            accent,
            ansi,
            yellow,
        }
    }

    /// From the dialog's own keys, as spark-shell hands them: PANEL_BG (the surface), HEX_FG, PANEL_MUTED,
    /// HEX_ACCENT and HEX_ANSI_0 to 15 (foot's own where one is missing). None without the first four.
    pub fn from(get: impl Fn(&str) -> Option<String>) -> Option<Roles> {
        let c = |k: &str| get(k).and_then(|v| rgb(&v));
        let ansi: [Rgb; 16] = std::array::from_fn(|i| c(&format!("HEX_ANSI_{}", i)).unwrap_or_else(|| rgb(FOOT_HEX[i]).unwrap()));
        Some(Roles::with(c("PANEL_BG")?, c("HEX_FG")?, c("PANEL_MUTED")?, c("HEX_ACCENT")?, ansi))
    }

    /// From a palette file's THEME_* keys, worked out as make.py and spark-shell's panel_load do: the surface the
    /// ground 9% of the way to the text, the quiet text lifted until it reads on it.
    pub fn from_theme(get: impl Fn(&str) -> Option<String>) -> Roles {
        let c = |k: &str, d: &str| {
            get(k)
                .and_then(|v| rgb(v.trim_matches(|ch| ch == '"' || ch == '\'')))
                .unwrap_or_else(|| rgb(d).unwrap())
        };
        let ansi: [Rgb; 16] = std::array::from_fn(|i| c(&format!("THEME_ANSI_{}", i), FOOT_HEX[i]));
        let (bg, fg) = (c("THEME_BG", "242424"), c("THEME_FG", "ffffff"));
        let muted = get("THEME_MUTED")
            .and_then(|v| rgb(v.trim_matches(|ch| ch == '"' || ch == '\'')))
            .unwrap_or(ansi[8]);
        let surface = hex_mix(bg, fg, 9);
        let mut pl = 35;
        let mut m = hex_mix(muted, fg, pl);
        while pl < 100 && hex_contrast(m, surface) < 450 {
            pl += 5;
            m = hex_mix(muted, fg, pl);
        }
        Roles::with(
            surface,
            fg,
            m,
            c(
                "THEME_ACCENT",
                &format!("{:02x}{:02x}{:02x}", ansi[4][0] as u8, ansi[4][1] as u8, ansi[4][2] as u8),
            ),
            ansi,
        )
    }
}

// -- drawing: coverage in the drawing's units, mixed onto the surface -------------------------------------------

struct Canvas {
    s: f64,
    w: usize,
    h: usize,
}

/// The pixels over a box: its columns and rows, the end excluded.
#[derive(Clone, Copy)]
struct Area {
    x0: usize,
    x1: usize,
    y0: usize,
    y1: usize,
}

impl Canvas {
    fn new(scale: u32) -> Canvas {
        Canvas {
            s: scale as f64,
            w: W * scale as usize,
            h: H * scale as usize,
        }
    }

    /// A shape's signed distance as coverage: one pixel of soft edge.
    fn cov(&self, d: f64) -> f64 {
        (0.5 - d * self.s).clamp(0.0, 1.0)
    }

    fn area(&self, x0: f64, y0: f64, x1: f64, y1: f64) -> Option<Area> {
        let px0 = (x0 * self.s).floor().max(0.0) as usize;
        let px1 = ((x1 * self.s).ceil().max(0.0) as usize).min(self.w);
        let py0 = (y0 * self.s).floor().max(0.0) as usize;
        let py1 = ((y1 * self.s).ceil().max(0.0) as usize).min(self.h);
        (px1 > px0 && py1 > py0).then_some(Area {
            x0: px0,
            x1: px1,
            y0: py0,
            y1: py1,
        })
    }

    /// A pixel's centre in the drawing's units.
    fn at(&self, p: usize) -> f64 {
        (p as f64 + 0.5) / self.s
    }

    /// Coverage over an area from the centre of each pixel.
    fn fill(&self, a: Area, f: impl Fn(f64, f64) -> f64) -> Shape {
        let mut cov = Vec::with_capacity((a.x1 - a.x0) * (a.y1 - a.y0));
        for py in a.y0..a.y1 {
            let y = self.at(py);
            for px in a.x0..a.x1 {
                cov.push(f(self.at(px), y));
            }
        }
        Some((a, cov))
    }
}

type Shape = Option<(Area, Vec<f64>)>;

enum Paint {
    One(Rgb),
    /// One color a row of the area, from its first.
    Rows(Vec<Rgb>),
}

struct Layer {
    shape: Shape,
    paint: Paint,
    alpha: f64,
}

fn layer(shape: Shape, color: Rgb, alpha: f64) -> Layer {
    Layer {
        shape,
        paint: Paint::One(color),
        alpha,
    }
}

fn disc(c: &Canvas, cx: f64, cy: f64, r: f64) -> Shape {
    let a = c.area(cx - r - 1.0, cy - r - 1.0, cx + r + 1.0, cy + r + 1.0)?;
    if r <= 0.0 {
        return None;
    }
    c.fill(a, |x, y| c.cov((x - cx).hypot(y - cy) - r))
}

fn ring(c: &Canvas, cx: f64, cy: f64, r: f64, w: f64) -> Shape {
    let a = c.area(cx - r - w - 1.0, cy - r - w - 1.0, cx + r + w + 1.0, cy + r + w + 1.0)?;
    c.fill(a, |x, y| c.cov(((x - cx).hypot(y - cy) - r).abs() - w / 2.0))
}

fn capsule(c: &Canvas, ax: f64, ay: f64, bx: f64, by: f64, r: f64) -> Shape {
    let a = c.area(ax.min(bx) - r - 1.0, ay.min(by) - r - 1.0, ax.max(bx) + r + 1.0, ay.max(by) + r + 1.0)?;
    let (dx, dy) = (bx - ax, by - ay);
    let len = (dx * dx + dy * dy).max(1e-9);
    c.fill(a, |x, y| {
        let t = (((x - ax) * dx + (y - ay) * dy) / len).clamp(0.0, 1.0);
        c.cov((x - ax - t * dx).hypot(y - ay - t * dy) - r)
    })
}

/// A box with hard edges: a pixel is in it or not.
fn block(c: &Canvas, x: f64, y: f64, w: f64, h: f64) -> Shape {
    let a = c.area(x, y, x + w, y + h)?;
    c.fill(a, |px, py| if px >= x && px < x + w && py >= y && py < y + h { 1.0 } else { 0.0 })
}

/// A polygon's coverage, sampled at 4 by 4 points a pixel.
fn polygon(c: &Canvas, pts: &[(f64, f64)]) -> Shape {
    let (xs, ys): (Vec<f64>, Vec<f64>) = pts.iter().copied().unzip();
    let min = |v: &[f64]| v.iter().copied().fold(f64::INFINITY, f64::min);
    let max = |v: &[f64]| v.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let a = c.area(min(&xs) - 1.0, min(&ys) - 1.0, max(&xs) + 1.0, max(&ys) + 1.0)?;
    let inside = |x: f64, y: f64| {
        let mut odd = false;
        let mut j = pts.len() - 1;
        for i in 0..pts.len() {
            let ((xi, yi), (xj, yj)) = (pts[i], pts[j]);
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                odd = !odd;
            }
            j = i;
        }
        odd
    };
    let ss = 4;
    let mut cov = Vec::with_capacity((a.x1 - a.x0) * (a.y1 - a.y0));
    for py in a.y0..a.y1 {
        for px in a.x0..a.x1 {
            let mut n = 0;
            for j in 0..ss {
                for i in 0..ss {
                    let x = (px as f64 + (i as f64 + 0.5) / ss as f64) / c.s;
                    let y = (py as f64 + (j as f64 + 0.5) / ss as f64) / c.s;
                    n += inside(x, y) as u32;
                }
            }
            cov.push(n as f64 / (ss * ss) as f64);
        }
    }
    Some((a, cov))
}

/// One frame: the layers mixed onto the surface in order; a pixel inked enough drawn opaque, the rest left
/// transparent. RGBA, w by h.
fn render(c: &Canvas, ro: &Roles, layers: &[Layer]) -> Vec<u8> {
    let mut img = vec![ro.surface; c.w * c.h];
    let mut ink = vec![0.0f64; c.w * c.h];
    for ly in layers {
        let Some((a, cov)) = &ly.shape else { continue };
        if ly.alpha <= 0.0 {
            continue;
        }
        let k = ly.alpha.min(1.0);
        let aw = a.x1 - a.x0;
        for py in a.y0..a.y1 {
            let col = match &ly.paint {
                Paint::One(c) => *c,
                Paint::Rows(rows) => rows[py - a.y0],
            };
            for px in a.x0..a.x1 {
                let v = cov[(py - a.y0) * aw + px - a.x0] * k;
                if v <= 0.0 {
                    continue;
                }
                let i = py * c.w + px;
                for ch in 0..3 {
                    img[i][ch] += (col[ch] - img[i][ch]) * v;
                }
                ink[i] += v * (1.0 - ink[i]);
            }
        }
    }
    let mut out = vec![0u8; c.w * c.h * 4];
    for i in 0..c.w * c.h {
        if ink[i] >= INK_MIN {
            for ch in 0..3 {
                out[i * 4 + ch] = img[i][ch].round_ties_even().clamp(0.0, 255.0) as u8;
            }
            out[i * 4 + 3] = 255;
        }
    }
    out
}

// -- easing ------------------------------------------------------------------------------------------------------

fn clamp(u: f64) -> f64 {
    u.clamp(0.0, 1.0)
}

fn ease_out(u: f64) -> f64 {
    1.0 - (1.0 - clamp(u)).powi(3)
}

fn ease_in(u: f64) -> f64 {
    clamp(u).powi(3)
}

fn ease_io(u: f64) -> f64 {
    let u = clamp(u);
    if u < 0.5 {
        4.0 * u.powi(3)
    } else {
        1.0 - (-2.0 * u + 2.0).powi(3) / 2.0
    }
}

fn bump(u: f64) -> f64 {
    if 0.0 < u && u < 1.0 {
        (PI * u).sin()
    } else {
        0.0
    }
}

/// Python's % on floats: the sign of the divisor.
fn pmod(a: f64, b: f64) -> f64 {
    a.rem_euclid(b)
}

// -- the pieces ----------------------------------------------------------------------------------------------------

/// Which of the three a frame is drawn for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Anim {
    Open,
    Wait,
    Close,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Piece {
    Moon,
    Ripple,
    Tide,
    Embers,
    Sun,
    Flight,
}

impl Piece {
    fn named(name: &str) -> Option<Piece> {
        Some(match name {
            "moon" => Piece::Moon,
            "ripple" => Piece::Ripple,
            "tide" => Piece::Tide,
            "embers" => Piece::Embers,
            "sun" => Piece::Sun,
            "flight" => Piece::Flight,
            _ => return None,
        })
    }

    /// A frame's length, in milliseconds: embers is a stop-motion at half the others' rate.
    fn ms(self) -> u32 {
        if self == Piece::Embers {
            80
        } else {
            40
        }
    }

    fn frames(self, anim: Anim) -> u32 {
        let (o, w, c) = match self {
            Piece::Moon => (30, 60, 20),
            Piece::Ripple => (30, 60, 24),
            Piece::Tide => (30, 72, 23),
            Piece::Embers => (15, 30, 14),
            Piece::Sun => (30, 48, 22),
            Piece::Flight => (30, 72, 24),
        };
        match anim {
            Anim::Open => o,
            Anim::Wait => w,
            Anim::Close => c,
        }
    }

    fn draw(self, c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
        match self {
            Piece::Moon => moon(c, ro, anim, f),
            Piece::Ripple => ripple(c, ro, anim, f),
            Piece::Tide => tide(c, ro, anim, f),
            Piece::Embers => embers(c, ro, anim, f),
            Piece::Sun => sun(c, ro, anim, f),
            Piece::Flight => flight(c, ro, anim, f),
        }
    }
}

/// A crescent waxes to a full moon in its halo; the halo breathes and the stars catch the light in turn.
fn moon(c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
    const HALO: [(f64, f64, f64); 2] = [(36.0, 0.08, 2.4), (26.0, 0.16, 1.2)];
    const STARS: [(f64, f64, f64); 4] = [(38.0, 28.0, 4.0), (143.0, 22.0, 18.0), (152.0, 92.0, 31.0), (27.0, 95.0, 44.0)];
    let (cx, cy, r) = (90.0, 60.0, 17.0);
    let far = 2.0 * r + 2.0;
    let mut breath = 0.0;
    let (g, sx) = match anim {
        Anim::Open => (ease_out((f - 4.0) / 24.0), Some(cx - far * ease_io(f / 26.0))),
        Anim::Wait => {
            breath = (2.0 * PI * f / 60.0).sin();
            (1.0, None)
        }
        Anim::Close => (1.0 - ease_in(f / 18.0), Some(cx + far * (1.0 - ease_io(f / 18.0)))),
    };
    let mut out = vec![];
    let (moon, soft) = if ro.dark {
        (mix(ro.fg, ro.accent, 0.15), 1.0)
    } else {
        (mix(ro.accent, ro.surface, 0.5), 0.7)
    };
    for (hr, a, amp) in HALO {
        if g > 0.0 {
            out.push(layer(
                disc(c, cx, cy, r + (hr - r) * g + amp * breath),
                ro.accent,
                soft * a * g * (1.0 + 0.15 * breath),
            ));
        }
    }
    match sx {
        None => out.push(layer(disc(c, cx, cy, r), moon, 1.0)),
        Some(sx) => {
            let shape = c
                .area(cx - r - 1.0, cy - r - 1.0, cx + r + 1.0, cy + r + 1.0)
                .and_then(|a| c.fill(a, |x, y| c.cov((x - cx).hypot(y - cy) - r) * (1.0 - c.cov((x - sx).hypot(y - cy) - (r + 1.0)))));
            out.push(layer(shape, moon, 1.0));
        }
    }
    if anim == Anim::Wait {
        for (x, y, t0) in STARS {
            let b = bump((f - t0) / 14.0);
            if b > 0.0 {
                let arm = 1.0 + 3.5 * b;
                out.push(layer(capsule(c, x - arm, y, x + arm, y, 0.3), ro.fg, 0.55 * b));
                out.push(layer(capsule(c, x, y - arm, x, y + arm, 0.3), ro.fg, 0.55 * b));
                out.push(layer(disc(c, x, y, 0.5 + 0.6 * b), ro.fg, 0.9 * b));
            }
        }
    }
    out
}

/// A drop falls into still water and rings keep spreading; at the close they gather back and it lifts away.
fn ripple(c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
    let (cx, cy, rmax, life, top) = (90.0, 66.0, 46.0, 40.0, 6.0);
    let col = ro.ansi[6];
    let mut out = vec![];
    let rings = |age: f64, k: f64, out: &mut Vec<Layer>| {
        let u = age / life;
        if !(0.0..1.0).contains(&u) {
            return;
        }
        let r = 1.5 + (rmax - 1.5) * (1.0 - (1.0 - u).powi(2));
        let a = k * (1.0 - u).powf(1.5);
        out.push(layer(ring(c, cx, cy, r, 1.6 - 0.8 * u), col, a));
        if u > 0.15 {
            let v = ease_out((u - 0.15) / 0.5);
            out.push(layer(ring(c, cx, cy, (r - 7.0 * v).max(0.5), 1.1 - 0.5 * u), col, a * 0.45 * v));
        }
    };
    match anim {
        Anim::Open => {
            if f < 10.0 {
                let u = f / 10.0;
                let y = top + (cy - top) * u * u;
                out.push(layer(capsule(c, cx, y - 1.0 - 6.0 * u, cx, y, 1.5), col, ease_out((f + 1.0) / 3.0)));
            } else {
                rings(f - 10.0, 1.0, &mut out);
                let t = (f - 10.0) / 7.0;
                if t < 1.0 {
                    for side in [-1.0, 1.0] {
                        out.push(layer(
                            disc(c, cx + side * (4.0 + 7.0 * t), cy - 36.0 * t * (1.0 - t), 0.9),
                            col,
                            0.85 * (1.0 - t * t),
                        ));
                    }
                }
            }
        }
        Anim::Wait => {
            for (b, k) in [(0.0, 0.8), (20.0, 0.65), (40.0, 1.0)] {
                rings(pmod(f - b, 60.0), k, &mut out);
            }
        }
        Anim::Close => {
            for s in [0.0, 5.0] {
                let v = (f - s) / 13.0;
                if (0.0..1.0).contains(&v) {
                    out.push(layer(
                        ring(c, cx, cy, 2.0 + 44.0 * (1.0 - v.powf(1.6)), 0.9 + 0.7 * v),
                        col,
                        0.85 * clamp(v * 2.0),
                    ));
                }
            }
            let t = (f - 17.0) / 6.0;
            if (0.0..1.0).contains(&t) {
                let y = cy - (cy - top) * (1.0 - (1.0 - t).powi(2));
                out.push(layer(capsule(c, cx, y, cx, y + 1.0 + 6.0 * (1.0 - t), 1.5), col, 1.0 - t * t));
            }
        }
    }
    out
}

/// A line opens from the centre and swells into three threads that sway against each other.
fn tide(c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
    let (cx, cy, big_e, l) = (90.0, 60.0, 76.0, 72.0);
    // amplitude, wavelength, turns a loop, phase, half width, which color
    const THREADS: [(f64, f64, f64, f64, f64, u8); 3] = [
        (6.0, 54.0, 2.0, 1.3, 0.55, 0),
        (11.0, 78.0, -1.0, 2.4, 0.75, 1),
        (15.0, 104.0, 1.0, 0.0, 1.0, 2),
    ];
    let thread = |e: f64, amp: f64, lam: f64, ph: f64, hw0: f64| -> Shape {
        let a = c.area(cx - e, cy - amp - hw0 - 2.0, cx + e, cy + amp + hw0 + 2.0)?;
        if e <= 0.0 {
            return None;
        }
        c.fill(a, |x, y| {
            let u = ((x - (cx - e)) / (2.0 * e)).clamp(0.0, 1.0);
            let win = (PI * u).sin().max(0.0);
            let dwin = PI / (2.0 * e) * (PI * u).cos();
            let th = 2.0 * PI * x / lam + ph;
            let yy = cy + amp * win * th.sin();
            let slope = amp * (dwin * th.sin() + win * th.cos() * 2.0 * PI / lam);
            let hw = hw0 * win.powf(0.6);
            let d = (y - yy).abs() / (1.0 + slope * slope).sqrt();
            (hw * c.s + 0.5 - d * c.s).clamp(0.0, 1.0) * (2.0 * hw * c.s).clamp(0.0, 1.0)
        })
    };
    let (e, amp, tau, dot) = match anim {
        Anim::Open => {
            let e = if f >= 2.0 { big_e * ease_out((f - 2.0) / 16.0) } else { 0.0 };
            let dot = if f < 4.0 { [0.5, 1.0, 1.0, 0.5][f as usize] } else { 0.0 };
            (e, ease_io((f - 8.0) / 21.0), f - 30.0, dot)
        }
        Anim::Wait => (big_e, 1.0, f, 0.0),
        Anim::Close => {
            let dot = if f >= 19.0 { [1.0, 0.66, 0.33, 0.0][(f - 19.0) as usize] } else { 0.0 };
            (big_e * (1.0 - ease_io((f - 8.0) / 12.0)), 1.0 - ease_io(f / 12.0), f, dot)
        }
    };
    let colors = [ro.muted, mix(ro.accent, ro.fg, 0.45), ro.accent];
    let mut out = vec![];
    if e > 0.0 {
        for (big_a, lam, turns, ph, hw0, role) in THREADS {
            let phase = ph - 2.0 * PI * turns * tau / l;
            out.push(layer(thread(e, big_a * amp, lam, phase, hw0), colors[role as usize], 1.0));
        }
    }
    if dot > 0.0 {
        out.push(layer(disc(c, cx, cy, 1.3), ro.accent, dot));
    }
    out
}

/// make.py's embers (random.Random(11)): birth in the loop, column, life, rise, drift, wobble.
const EMBERS: [(i32, i32, i32, f64, f64, f64); 22] = [
    (1, 33, 12, 5.213298177079218, 0.35504563590425864, 1.1925847566102958),
    (2, 31, 13, 5.827358370535915, -0.40587654377078153, 1.9053599292820202),
    (3, 41, 9, 5.471785710513206, -0.10384002354176514, 2.844807755847525),
    (5, 36, 10, 5.521631212733696, 0.33170162534997805, 0.3966756979672681),
    (5, 23, 13, 4.45414866060462, -0.03606553877671548, 2.7665354126038046),
    (8, 32, 10, 5.552525074254519, -0.00022684779320836235, 4.160183060271512),
    (9, 24, 12, 6.195781160833552, 0.49569164165619917, 5.276553650815172),
    (10, 26, 10, 5.323192354442715, -0.47024808771741766, 3.5365333969316475),
    (11, 19, 11, 5.095724357070682, 0.4580423833198135, 5.321105376341612),
    (12, 22, 9, 5.2459770968246, 0.4803589411742921, 2.4958251571378858),
    (14, 36, 10, 5.801319545617972, -0.2302244131498573, 0.5472655656516284),
    (14, 29, 9, 4.642273643936949, 0.20701602921669415, 0.06879748654462806),
    (18, 31, 10, 5.627739395251358, -0.3116145324153835, 3.1956749620847265),
    (19, 40, 10, 5.154614892294163, -0.11624821188667434, 2.479679173248598),
    (20, 16, 11, 5.955801096168699, 0.47485706063666566, 3.722411140129205),
    (22, 16, 10, 4.73715324930619, 0.49583572040779067, 3.7806761499548545),
    (23, 17, 10, 4.783838063439541, -0.24172244213837957, 4.85249125177333),
    (24, 25, 12, 4.532117396099164, -0.4098828270380698, 3.659574532492227),
    (25, 35, 11, 5.0690672838678115, -0.04679189527615102, 6.023365743220326),
    (26, 34, 10, 5.959746202044, -0.3171722842213148, 0.9679698028556619),
    (28, 42, 13, 4.84909741957265, -0.31019933403673994, 4.6435851680485705),
    (0, 22, 12, 5.987941557679543, 0.10353421478344349, 2.6467513663894073),
];
/// make.py's flicker for each cell of the line (32, from column 14): phase, turns a loop.
const FLICK: [(f64, i32); 32] = [
    (0.6521131989718737, 1),
    (3.217594590527116, 2),
    (1.4971971700051718, 3),
    (2.459316873057508, 2),
    (5.172948077636176, 3),
    (3.083476904651328, 3),
    (1.101721731689596, 3),
    (6.136679199575737, 1),
    (1.4343289984017864, 3),
    (4.104027706929082, 3),
    (3.857822938752172, 2),
    (1.333873566992744, 1),
    (4.70362650233574, 1),
    (1.6905378680211216, 2),
    (1.5641221003209131, 1),
    (1.106873709341292, 2),
    (3.3347027399631135, 1),
    (0.5789665358831851, 1),
    (5.595104644210423, 2),
    (4.125533252080112, 3),
    (3.277776725815869, 1),
    (3.7044189645372754, 1),
    (2.981699393362806, 2),
    (4.402091717706125, 1),
    (0.13350763915315675, 3),
    (0.46995536884993533, 1),
    (4.587527320336371, 2),
    (0.8578844657239757, 1),
    (0.4726510125801709, 3),
    (2.3096326532095257, 1),
    (5.6532301342461, 3),
    (4.629297578775712, 1),
];

/// A low line glows and embers lift off it, yellow to red, going dark as they climb (square pixels).
fn embers(c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
    let (g, y0, l) = (3.0, 102.0, 30.0);
    let cells: Vec<f64> = (14..46).map(|k| k as f64).collect();
    let mut out = vec![];
    let ember = |age: f64, e: (i32, i32, i32, f64, f64, f64), out: &mut Vec<Layer>| {
        let (_, col, life, rise, drift, wob) = e;
        if !(0.0..life as f64).contains(&age) {
            return;
        }
        let u = age / life as f64;
        let x = ((col as f64 * g + drift * age * g / 2.0 + 2.2 * (wob + age * 0.9).sin()) / g).floor() * g;
        let y = ((y0 - g - rise * age) / g).floor() * g;
        let warm = mix(ro.yellow, ro.ansi[1], 0.5);
        let (color, a) = if u < 0.2 {
            (ro.yellow, 1.0)
        } else if u < 0.45 {
            (warm, 1.0)
        } else {
            (ro.ansi[1], 1.0 - (u - 0.7).max(0.0) * 2.2)
        };
        out.push(layer(block(c, x, y, g, g), color, a));
    };
    let (mid, half) = ((cells.len() as f64 - 1.0) / 2.0, cells.len() as f64 / 2.0);
    let (reach, dim, tau) = match anim {
        Anim::Open => (half * (f + 1.0) / 4.0, 1.0, f - 15.0),
        Anim::Wait => (half, 1.0, f),
        Anim::Close => (half * (1.0 - f / 9.0), 1.0 - f / 12.0, f),
    };
    for (i, cell) in cells.iter().enumerate() {
        if (i as f64 - mid).abs() <= reach {
            let (ph, k) = FLICK[i];
            let a = (0.44 + 0.14 * (ph + 2.0 * PI * k as f64 * pmod(tau, l) / l).sin()) * dim;
            out.push(layer(block(c, cell * g, y0, g, g), ro.ansi[1], a));
        }
    }
    for e in EMBERS {
        let b = e.0 as f64;
        match anim {
            Anim::Open => {
                let born = b - 30.0;
                if born >= -15.0 {
                    ember(tau - born, e, &mut out);
                }
            }
            Anim::Wait => ember(pmod(f - b, 30.0), e, &mut out),
            Anim::Close => {
                let born = if e.0 == 0 { 0.0 } else { b - 30.0 };
                ember(f - born, e, &mut out);
            }
        }
    }
    out
}

/// The horizon draws out and a striped sun rises behind it, its light trembling on the water; it sets.
fn sun(c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
    let (big_cx, big_cy, r, hz, l, p) = (90.0, 78.0, 34.0, 88.0, 48.0, 7.0);
    let sunk = r + hz - big_cy + 2.0;
    let (hl, cy, light, tau) = match anim {
        Anim::Open => (
            64.0 * ease_out(f / 10.0),
            big_cy + sunk * (1.0 - ease_out((f - 5.0) / 23.0)),
            ease_io((f - 14.0) / 15.0),
            f - 30.0,
        ),
        Anim::Wait => (64.0, big_cy, 1.0, f),
        Anim::Close => (
            64.0 * (1.0 - ease_io((f - 11.0) / 10.0)),
            big_cy + sunk * ease_in(f / 15.0),
            1.0 - ease_io(f / 10.0),
            f,
        ),
    };
    let mut out = vec![];
    if cy - r < hz {
        if let Some(a) = c.area(big_cx - r - 1.0, cy - r - 1.0, big_cx + r + 1.0, hz.min(cy + r) + 1.0) {
            let shape = c.fill(a, |x, y| {
                let cov = c.cov((x - big_cx).hypot(y - cy) - r) * (0.5 - (y - hz) * c.s).clamp(0.0, 1.0);
                let v = y - cy;
                let start = -0.2 * r;
                let gap = ((v - start) / (0.75 * r)).clamp(0.0, 1.0) * 3.4; // the stripes widen downward
                let w = pmod(v - start - p * tau / l, p);
                let cut = if gap > 0.0 {
                    (0.5 - ((w - p / 2.0).abs() - gap / 2.0) * c.s).clamp(0.0, 1.0)
                } else {
                    0.0
                };
                cov * (1.0 - cut)
            });
            let rows = (a.y0..a.y1)
                .map(|py| {
                    let k = ((c.at(py) - (cy - r)) / (r + hz - big_cy)).clamp(0.0, 1.0);
                    if k < 0.55 {
                        mix(ro.yellow, ro.ansi[1], k / 0.55)
                    } else {
                        mix(ro.ansi[1], ro.ansi[5], (k - 0.55) / 0.45)
                    }
                })
                .collect();
            out.push(Layer {
                shape,
                paint: Paint::Rows(rows),
                alpha: 1.0,
            });
        }
    }
    if hl > 0.3 {
        out.push(layer(capsule(c, big_cx - hl, hz + 1.6, big_cx + hl, hz + 1.6, 0.55), ro.muted, 0.9));
    }
    let glint = mix(ro.ansi[1], ro.ansi[5], 0.5);
    for (k, (w, a)) in [(24.0, 0.5), (16.0, 0.4), (10.0, 0.3), (5.0, 0.22)].into_iter().enumerate() {
        if light > 0.0 {
            let t = 2.0 * PI * (tau / l + k as f64 / 4.0);
            let (w2, x) = (w * (1.0 + 0.2 * t.sin()), big_cx + 1.5 * (t + k as f64).sin());
            let y = hz + 6.0 + 5.0 * k as f64;
            out.push(layer(capsule(c, x - w2, y, x + w2, y, 0.75), glint, a * light));
        }
    }
    out
}

/// A paper plane glides in, draws a slow figure of eight with a dotted trail, and flies off the top left.
fn flight(c: &Canvas, ro: &Roles, anim: Anim, f: f64) -> Vec<Layer> {
    const OPEN: [(f64, f64); 4] = [(206.0, 104.0), (160.0, 116.0), (118.0, 88.0), (90.0, 60.0)];
    const CLOSE: [(f64, f64); 4] = [(90.0, 60.0), (71.4, 41.4), (40.0, 8.0), (-24.0, -26.0)];
    const WING: [(f64, f64); 3] = [(9.5, 0.0), (-8.0, -6.8), (-4.0, 0.0)];
    const FOLD: [(f64, f64); 3] = [(9.5, 0.0), (-4.0, 0.0), (-8.0, 6.8)];
    let (cx, cy, big_a, l) = (90.0, 60.0, 64.0, 72.0);
    let eight = |tau: f64| {
        let t = PI / 2.0 + 2.0 * PI * tau / l;
        let (s, co) = (t.sin(), t.cos());
        let d = 1.0 + s * s;
        (cx + big_a * co / d, cy + big_a * s * co / d)
    };
    let bezier = |p: [(f64, f64); 4], u: f64| {
        let v = 1.0 - u;
        let b = |i: usize| {
            let q = |k: usize| if i == 0 { p[k].0 } else { p[k].1 };
            v.powi(3) * q(0) + 3.0 * v * v * u * q(1) + 3.0 * v * u * u * q(2) + u.powi(3) * q(3)
        };
        (b(0), b(1))
    };
    let at = |tau: f64| -> Option<(f64, f64)> {
        match anim {
            Anim::Open => {
                if tau < 0.0 {
                    None
                } else if tau < 30.0 {
                    Some(bezier(OPEN, tau / 30.0))
                } else {
                    Some(eight(tau - 30.0))
                }
            }
            Anim::Wait => Some(eight(tau)),
            Anim::Close if tau < 0.0 => Some(eight(tau)),
            Anim::Close => (tau <= 20.0).then(|| bezier(CLOSE, tau / 20.0)),
        }
    };
    let fade = if anim == Anim::Close { 1.0 - ease_in((f - 12.0) / 11.0) } else { 1.0 };
    let mut out = vec![];
    for k in 3..27 {
        if let Some(p) = at(f - k as f64) {
            out.push(layer(disc(c, p.0, p.1, 0.8), ro.muted, 0.75 * (1.0 - k as f64 / 27.0) * fade));
        }
    }
    if let (Some(p), Some(q), Some(n)) = (at(f - 0.5), at(f + 0.5), at(f)) {
        let th = (q.1 - p.1).atan2(q.0 - p.0);
        let (cs, sn) = (th.cos(), th.sin());
        let place = |pts: &[(f64, f64)]| pts.iter().map(|&(x, y)| (n.0 + x * cs - y * sn, n.1 + x * sn + y * cs)).collect::<Vec<_>>();
        out.push(layer(polygon(c, &place(&WING)), ro.accent, 1.0));
        out.push(layer(polygon(c, &place(&FOLD)), mix(ro.accent, BLACK, 0.3), 1.0));
    }
    out
}

// -- the films -----------------------------------------------------------------------------------------------------

/// A piece's frames for one of the three, RGBA at `scale`, each with how long it stays: a frame like the one
/// before it lengthens it, as the GIF holds it. None for a name that is no piece.
pub fn frames(name: &str, ro: &Roles, scale: u32, anim: Anim) -> Option<Vec<(Vec<u8>, u32)>> {
    let piece = Piece::named(name)?;
    let c = Canvas::new(scale.clamp(1, 2));
    let drawn = in_parallel((0..piece.frames(anim)).collect(), |f| render(&c, ro, &piece.draw(&c, ro, anim, f as f64)));
    let mut out: Vec<(Vec<u8>, u32)> = vec![];
    for px in drawn {
        match out.last_mut() {
            Some((last, ms)) if *last == px => *ms += piece.ms(),
            _ => out.push((px, piece.ms())),
        }
    }
    Some(out)
}

/// `f` over `items` on up to four threads, the results in the items' order: the frames are independent of each
/// other, so a piece is drawn in about the time of its longest quarter.
fn in_parallel<T: Send, R: Send>(items: Vec<T>, f: impl Fn(T) -> R + Sync) -> Vec<R> {
    let n = std::thread::available_parallelism().map_or(1, |n| n.get()).clamp(1, 4);
    let size = items.len().div_ceil(n).max(1);
    let mut chunks: Vec<Vec<T>> = vec![];
    let mut it = items.into_iter().peekable();
    while it.peek().is_some() {
        chunks.push(it.by_ref().take(size).collect());
    }
    let f = &f;
    std::thread::scope(|s| {
        let hs: Vec<_> = chunks
            .into_iter()
            .map(|ch| s.spawn(move || ch.into_iter().map(f).collect::<Vec<R>>()))
            .collect();
        hs.into_iter().flat_map(|h| h.join().unwrap_or_default()).collect()
    })
}

fn film(name: &str, ro: &Roles, scale: u32, anim: Anim) -> Option<Film> {
    let s = scale.clamp(1, 2);
    let (w, h) = ((W as u32) * s, (H as u32) * s);
    let shown = in_parallel(frames(name, ro, s, anim)?, |(px, ms)| {
        let img = Image::from_rgba(w, h, &px)?;
        let (sx, _, _) = show(&img, w, h, &Viewport::FIT)?;
        Some((sx, ms.max(FRAME_MIN_MS)))
    });
    let out: Option<Vec<(String, u32)>> = shown.into_iter().collect();
    let out = out?;
    (!out.is_empty()).then_some(Film { w, h, frames: out })
}

/// A piece's three films in the palette: what main.rs plays for `draw:PIECE`. None for a name that is no piece.
pub fn films(name: &str, ro: &Roles, scale: u32) -> Option<Films> {
    Some(Films {
        open: film(name, ro, scale, Anim::Open)?,
        wait: film(name, ro, scale, Anim::Wait)?,
        close: film(name, ro, scale, Anim::Close)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn theme(name: &str) -> Roles {
        let path = format!("{}/../../gallery/theme/{}.env", env!("CARGO_MANIFEST_DIR"), name);
        let text = std::fs::read_to_string(path).unwrap();
        let get = |k: &str| {
            text.lines()
                .find_map(|l| l.trim().strip_prefix(k)?.strip_prefix('=').map(|v| v.trim().to_string()))
        };
        Roles::from_theme(get)
    }

    /// A GIF's frames as RGBA, each laid alone (make.py clears each after it: disposal 2), with its length.
    fn gif_frames(path: &str) -> Vec<(Vec<u8>, u32)> {
        let mut opts = gif::DecodeOptions::new();
        opts.set_color_output(gif::ColorOutput::RGBA);
        let mut dec = opts.read_info(std::fs::File::open(path).unwrap()).unwrap();
        let (w, h) = (dec.width() as usize, dec.height() as usize);
        let mut out = vec![];
        while let Some(fr) = dec.read_next_frame().unwrap() {
            let mut px = vec![0u8; w * h * 4];
            for y in 0..fr.height as usize {
                for x in 0..fr.width as usize {
                    let i = (y * fr.width as usize + x) * 4;
                    if fr.buffer[i + 3] >= 128 {
                        let o = ((fr.top as usize + y) * w + fr.left as usize + x) * 4;
                        px[o..o + 4].copy_from_slice(&fr.buffer[i..i + 4]);
                    }
                }
            }
            out.push((px, fr.delay as u32 * 10));
        }
        out
    }

    #[test]
    fn every_piece_draws_its_three_at_both_sizes() {
        let ro = theme("tokyonight-night");
        for name in NAMES {
            for scale in [1, 2] {
                for anim in [Anim::Open, Anim::Wait, Anim::Close] {
                    let fr = frames(name, &ro, scale, anim).unwrap();
                    let total: u32 = fr.iter().map(|(_, ms)| *ms).sum();
                    let p = Piece::named(name).unwrap();
                    assert_eq!(total, p.frames(anim) * p.ms(), "{} {:?}: every frame's time kept", name, anim);
                    assert!(fr.iter().all(|(px, _)| px.len() == W * H * 4 * (scale * scale) as usize));
                    assert!(
                        fr.iter().any(|(px, _)| px.chunks(4).any(|p| p[3] == 255)),
                        "{} {:?} draws something",
                        name,
                        anim
                    );
                }
            }
        }
        assert!(frames("comet", &ro, 1, Anim::Open).is_none());
    }

    /// The pieces drawn here are the GIFs make.py drew, frame for frame: the same pixels drawn, in the same colors
    /// but for the GIF's cut to 255 of them, in a dark and a light palette.
    #[test]
    fn every_piece_is_the_gif_make_py_drew() {
        for pal in ["tokyonight-night", "solarized-light"] {
            let ro = theme(pal);
            for name in NAMES {
                for (anim, reel) in [(Anim::Open, "open"), (Anim::Wait, "wait"), (Anim::Close, "close")] {
                    let gif = gif_frames(&format!("{}/../../gallery/animation/{}/{}/{}.gif", env!("CARGO_MANIFEST_DIR"), name, pal, reel));
                    let ours = frames(name, &ro, 1, anim).unwrap();
                    // the GIF's frames unrolled to the piece's own ticks, ours too
                    let unroll = |v: &[(Vec<u8>, u32)]| -> Vec<Vec<u8>> {
                        let ms = Piece::named(name).unwrap().ms();
                        v.iter()
                            .flat_map(|(px, d)| std::iter::repeat_n(px.clone(), (*d / ms).max(1) as usize))
                            .collect()
                    };
                    let (g, o) = (unroll(&gif), unroll(&ours));
                    assert_eq!(g.len(), o.len(), "{} {} {}: as many ticks", pal, name, reel);
                    let (mut both, mut either, mut off) = (0usize, 0usize, 0f64);
                    for (a, b) in g.iter().zip(&o) {
                        for (pa, pb) in a.chunks(4).zip(b.chunks(4)) {
                            match (pa[3] == 255, pb[3] == 255) {
                                (true, true) => {
                                    both += 1;
                                    off += (0..3).map(|ch| (pa[ch] as f64 - pb[ch] as f64).abs()).fold(0.0, f64::max);
                                }
                                (false, false) => {}
                                _ => either += 1,
                            }
                        }
                    }
                    let drawn = both + either;
                    assert!(drawn > 0, "{} {} {}", pal, name, reel);
                    let same = both as f64 / drawn as f64;
                    let mean_off = off / both.max(1) as f64;
                    if std::env::var_os("PIECES_PARITY").is_some() {
                        eprintln!("parity {} {} {}: same {:.4} off {:.2}", pal, name, reel, same, mean_off);
                    }
                    // the same pixels, off only by the GIF's cut to 255 colors; flight's plane, a polygon Pillow fills at
                    // 4 by 4 its own way, differs at a few edge pixels (3 in 100 drawn, about 6 in 255 off)
                    let (most, worst) = if name == "flight" { (0.965, 7.0) } else { (0.999, 3.0) };
                    assert!(same >= most, "{} {} {}: {:.4} of the drawn pixels drawn by both", pal, name, reel, same);
                    assert!(mean_off < worst, "{} {} {}: a drawn pixel off by {:.2} on average", pal, name, reel, mean_off);
                }
            }
        }
    }

    #[test]
    fn the_dialogs_keys_give_the_roles_a_palette_file_does() {
        // spark-shell's panel_load works out PANEL_BG and PANEL_MUTED as Roles::from_theme does
        let ro = theme("nord");
        let hex = |c: Rgb| format!("{:02x}{:02x}{:02x}", c[0] as u8, c[1] as u8, c[2] as u8);
        let get = |k: &str| -> Option<String> {
            Some(match k {
                "PANEL_BG" => hex(ro.surface),
                "PANEL_MUTED" => hex(ro.muted),
                "HEX_FG" => hex(ro.fg),
                "HEX_ACCENT" => hex(ro.accent),
                _ => hex(ro.ansi[k.strip_prefix("HEX_ANSI_")?.parse::<usize>().ok()?]),
            })
        };
        assert_eq!(Roles::from(get), Some(ro));
        assert_eq!(Roles::from(|_| None), None, "no palette, no roles");
    }

    /// How long a piece's three films take to draw, at 2x: `cargo test --release -- --ignored --nocapture draw_time`.
    #[test]
    #[ignore]
    fn draw_time() {
        let ro = theme("tokyonight-night");
        for name in NAMES {
            let t = std::time::Instant::now();
            films(name, &ro, 2).unwrap();
            let drawn = t.elapsed().as_millis();
            let t = std::time::Instant::now();
            for reel in ["open", "wait", "close"] {
                let p = format!(
                    "{}/../../gallery/animation/{}/tokyonight-night/{}@2x.gif",
                    env!("CARGO_MANIFEST_DIR"),
                    name,
                    reel
                );
                crate::transition::film(&std::fs::read(p).unwrap()).unwrap();
            }
            eprintln!("draw_time {}: drawn {} ms, its GIFs decoded {} ms, at 2x", name, drawn, t.elapsed().as_millis());
        }
    }

    #[test]
    fn a_film_is_sixel_frames_at_the_pieces_size() {
        let f = films("embers", &theme("dracula"), 1).unwrap();
        assert_eq!((f.open.w, f.open.h), (180, 120));
        assert!(f.wait.frames.iter().all(|(s, ms)| s.starts_with("\x1bP") && *ms >= 80));
        assert_eq!(films("embers", &theme("dracula"), 2).unwrap().close.w, 360);
    }
}
