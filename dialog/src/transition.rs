//! The dialog's transitions (#122): the art of assets/transitions (PR #121), played in the middle of
//! the content area. `open` plays once when the dialog opens, `wait` loops while there is nothing
//! else to show, `close` plays once when Esc closes it. A GIF is decoded once to its frames, each frame
//! encoded to sixel once, its ground left unpainted: sixel names a color in whole percents, so a ground
//! painted the surface's color would sit a shade off the window's own. main.rs clears a frame's cells
//! and draws the next in one synchronized update, at the GIF's own pace.
//! Nothing is read from a path here: main.rs hands over the bytes.

use crate::sixel::{show, Image, Viewport};

/// A frame shorter than this is held this long: GIF counts in hundredths, and a 0 means "fast".
pub const FRAME_MIN_MS: u32 = 20;
/// The wait loop gives up after this long: a provider that never answers does not hold the home back.
pub const WAIT_MAX_MS: u128 = 4000;

/// Which of the three plays.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reel {
    Open,
    Wait,
    Close,
}

/// A GIF as sixel frames, each with how long it stays, at the GIF's own size in pixels.
#[derive(Clone, Debug, PartialEq)]
pub struct Film {
    pub w: u32,
    pub h: u32,
    pub frames: Vec<(String, u32)>,
}

impl Film {
    /// How long it plays once, in milliseconds.
    pub fn length(&self) -> u128 {
        self.frames.iter().map(|(_, ms)| *ms as u128).sum()
    }

    /// The frame shown `ms` after it started, and how long until the next: played once (the last
    /// frame past its end) or looped.
    pub fn at(&self, ms: u128, looped: bool) -> (usize, u128) {
        let len = self.length().max(1);
        let mut t = if looped { ms % len } else { ms.min(len) };
        for (k, (_, d)) in self.frames.iter().enumerate() {
            if t < *d as u128 {
                return (k, *d as u128 - t);
            }
            t -= *d as u128;
        }
        (self.frames.len().saturating_sub(1), FRAME_MIN_MS as u128)
    }
}

/// The three a piece has.
#[derive(Clone, Debug, PartialEq)]
pub struct Films {
    pub open: Film,
    pub wait: Film,
    pub close: Film,
}

impl Films {
    pub fn of(&self, reel: Reel) -> &Film {
        match reel {
            Reel::Open => &self.open,
            Reel::Wait => &self.wait,
            Reel::Close => &self.close,
        }
    }
}

/// A GIF's bytes as a film: every frame laid on what the frames before it left (their disposal kept),
/// its ground transparent. None for bytes that are no GIF, a GIF over 1024 pixels a side or with no
/// frame.
pub fn film(gif_bytes: &[u8]) -> Option<Film> {
    let mut opts = gif::DecodeOptions::new();
    opts.set_color_output(gif::ColorOutput::RGBA);
    let mut dec = opts.read_info(std::io::Cursor::new(gif_bytes)).ok()?;
    let (w, h) = (dec.width() as u32, dec.height() as u32);
    if w == 0 || h == 0 || w > 1024 || h > 1024 {
        return None;
    }
    let mut canvas = vec![[0u8; 4]; (w * h) as usize];
    let mut frames = vec![];
    while let Some(f) = dec.read_next_frame().ok()? {
        let before = (f.dispose == gif::DisposalMethod::Previous).then(|| canvas.clone());
        let (fx, fy, fw, fh) = (f.left as u32, f.top as u32, f.width as u32, f.height as u32);
        for y in 0..fh {
            for x in 0..fw {
                let (cx, cy) = (fx + x, fy + y);
                let i = ((y * fw + x) * 4) as usize;
                if cx < w && cy < h && i + 3 < f.buffer.len() && f.buffer[i + 3] >= 128 {
                    canvas[(cy * w + cx) as usize] = [f.buffer[i], f.buffer[i + 1], f.buffer[i + 2], 255];
                }
            }
        }
        let laid: Vec<u8> = canvas.iter().flat_map(|p| *p).collect();
        let img = Image::from_rgba(w, h, &laid)?;
        let (s, _, _) = show(&img, w, h, &Viewport::FIT)?;
        frames.push((s, (f.delay as u32 * 10).max(FRAME_MIN_MS)));
        match f.dispose {
            gif::DisposalMethod::Background => {
                for y in fy..(fy + fh).min(h) {
                    for x in fx..(fx + fw).min(w) {
                        canvas[(y * w + x) as usize] = [0; 4];
                    }
                }
            }
            gif::DisposalMethod::Previous => {
                if let Some(b) = before {
                    canvas = b;
                }
            }
            _ => {}
        }
        if frames.len() > 1000 {
            break;
        }
    }
    (!frames.is_empty()).then_some(Film { w, h, frames })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_piece_decodes_to_frames_laid_on_the_surface_at_its_own_pace() {
        let wait = include_bytes!("../../assets/transitions/embers/tokyonight-night/wait.gif");
        let f = film(wait).expect("a film");
        assert_eq!((f.w, f.h), (180, 120));
        assert!(f.frames.len() > 10 && f.frames.iter().all(|(s, ms)| s.starts_with("\x1bP0;1;0q\"1;1;180;120") && *ms >= FRAME_MIN_MS));
        assert!(
            f.frames.iter().all(|(s, _)| !s.contains(";2;16;16;22")),
            "the ground (the surface, the GIF's transparent color) is never painted"
        );
        // looped, it comes back to its first frame; once, it stays on its last
        let len = f.length();
        assert_eq!(f.at(0, true).0, 0);
        assert_eq!(f.at(len, true).0, 0);
        assert_eq!(f.at(len * 3, false).0, f.frames.len() - 1);
        assert!(film(b"GIF89a not one").is_none());
    }

    #[test]
    fn every_piece_is_a_film_in_a_dark_and_a_light_palette() {
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../assets/transitions");
        let mut n = 0;
        for piece in std::fs::read_dir(root).unwrap().flatten().filter(|e| e.path().is_dir()) {
            for pal in ["tokyonight-night", "solarized-light"] {
                for reel in ["open", "wait", "close"] {
                    let bytes = std::fs::read(piece.path().join(pal).join(format!("{}.gif", reel))).unwrap();
                    let f = film(&bytes).unwrap_or_else(|| panic!("{:?} {} {}", piece.path(), pal, reel));
                    assert_eq!((f.w, f.h), (180, 120));
                    n += 1;
                }
            }
        }
        assert_eq!(n, 6 * 2 * 3, "six pieces");
    }
}
