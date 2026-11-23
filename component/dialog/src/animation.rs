//! The dialog's transitions (#122): the art of gallery/animation (PR #121), played in the middle of
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

/// A GIF as frames, each with how long it stays, at the GIF's own size in pixels: as sixel for a terminal, or,
/// for a window that paints them itself, as pixels in `pics` beside frames whose sixel is empty. A painted
/// piece's WebP is read a frame at a time as it plays (`stream`): its frames hold their times alone.
#[derive(Clone, Debug, PartialEq)]
pub struct Film {
    pub w: u32,
    pub h: u32,
    pub frames: Vec<(String, u32)>,
    pub pics: Vec<std::sync::Arc<crate::draw::Pic>>,
    pub stream: Option<std::sync::Arc<Stream>>,
}

impl Film {
    /// Frame `k` as pixels, for a window.
    pub fn pic(&self, k: usize) -> Option<std::sync::Arc<crate::draw::Pic>> {
        match &self.stream {
            Some(s) => s.at(k).map(|(p, _)| p),
            None => self.pics.get(k).cloned(),
        }
    }

    /// Frame `k` as sixel, for a terminal.
    pub fn sixel(&self, k: usize) -> Option<String> {
        match &self.stream {
            Some(s) => s.at(k).map(|(_, s)| s),
            None => self.frames.get(k).map(|(s, _)| s.clone()),
        }
    }

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
    film_as(gif_bytes, false)
}

/// As `film`, its frames as pixels: what a window paints.
pub fn film_pixels(gif_bytes: &[u8]) -> Option<Film> {
    film_as(gif_bytes, true)
}

fn film_as(gif_bytes: &[u8], pixels: bool) -> Option<Film> {
    let mut opts = gif::DecodeOptions::new();
    opts.set_color_output(gif::ColorOutput::RGBA);
    let mut dec = opts.read_info(std::io::Cursor::new(gif_bytes)).ok()?;
    let (w, h) = (dec.width() as u32, dec.height() as u32);
    if w == 0 || h == 0 || w > 1024 || h > 1024 {
        return None;
    }
    let mut canvas = vec![[0u8; 4]; (w * h) as usize];
    let (mut frames, mut pics) = (vec![], vec![]);
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
        let s = if pixels {
            pics.push(std::sync::Arc::new(crate::draw::Pic::of(&img)));
            String::new()
        } else {
            show(&img, w, h, &Viewport::FIT)?.0
        };
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
    (!frames.is_empty()).then_some(Film {
        w,
        h,
        frames,
        pics,
        stream: None,
    })
}

/// A painted piece's reel, an animated WebP read a frame at a time as it plays: hundreds of full-color frames held
/// as pixels would be hundreds of megabytes. The frame shown is kept; a frame before it reads again from the first.
pub struct Stream {
    pixels: bool,
    state: std::sync::Mutex<StreamState>,
}

struct StreamState {
    dec: image_webp::WebPDecoder<std::io::Cursor<Vec<u8>>>,
    next: usize, // the frame the decoder gives next; the canvas holds the one before it
    canvas: Vec<u8>,
    shown: Option<(usize, std::sync::Arc<crate::draw::Pic>, String)>,
}

impl std::fmt::Debug for Stream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Stream")
    }
}

impl PartialEq for Stream {
    fn eq(&self, other: &Stream) -> bool {
        std::ptr::eq(self, other)
    }
}

impl Stream {
    /// Frame `k`: its pixels (for a window) or its sixel (for a terminal), the other empty.
    fn at(&self, k: usize) -> Option<(std::sync::Arc<crate::draw::Pic>, String)> {
        let mut st = self.state.lock().ok()?;
        if let Some((j, p, s)) = &st.shown {
            if *j == k {
                return Some((p.clone(), s.clone()));
            }
        }
        if k + 1 < st.next {
            st.dec.reset_animation();
            st.next = 0;
        }
        while st.next <= k {
            let StreamState { dec, canvas, .. } = &mut *st;
            dec.read_frame(canvas).ok()?;
            st.next += 1;
        }
        let (w, h) = st.dec.dimensions();
        let img = Image::from_rgba(w, h, &st.canvas)?;
        let (pic, six) = if self.pixels {
            (std::sync::Arc::new(crate::draw::Pic::of(&img)), String::new())
        } else {
            (
                std::sync::Arc::new(crate::draw::Pic { w: 0, h: 0, data: vec![] }),
                show(&img, w, h, &Viewport::FIT)?.0,
            )
        };
        st.shown = Some((k, pic.clone(), six.clone()));
        Some((pic, six))
    }
}

/// An animated WebP's bytes as a film read as it plays, as pixels or as sixel. None for bytes that are no
/// animated WebP with alpha (its ground is the window's), one over 1024 pixels a side, or one whose first frame
/// does not decode.
pub fn film_webp(bytes: Vec<u8>, pixels: bool) -> Option<Film> {
    let times = webp_times(&bytes)?;
    let mut dec = image_webp::WebPDecoder::new(std::io::Cursor::new(bytes)).ok()?;
    let (w, h) = dec.dimensions();
    if !dec.is_animated() || !dec.has_alpha() || w == 0 || h == 0 || w > 1024 || h > 1024 || times.len() != dec.num_frames() as usize {
        return None;
    }
    dec.set_background_color([0, 0, 0, 0]).ok()?; // the ground is the window's own
    let canvas = vec![0; dec.output_buffer_size()?];
    let stream = Stream {
        pixels,
        state: std::sync::Mutex::new(StreamState {
            dec,
            next: 0,
            canvas,
            shown: None,
        }),
    };
    stream.at(0)?;
    Some(Film {
        w,
        h,
        frames: times.into_iter().map(|ms| (String::new(), ms.max(FRAME_MIN_MS))).collect(),
        pics: vec![],
        stream: Some(std::sync::Arc::new(stream)),
    })
}

/// How long each frame of an animated WebP stays, read from its frames' headers (ANMF: offsets and size, then
/// the time in three bytes) before any frame decodes.
fn webp_times(b: &[u8]) -> Option<Vec<u32>> {
    if b.len() < 12 || &b[0..4] != b"RIFF" || &b[8..12] != b"WEBP" {
        return None;
    }
    let (mut i, mut times) = (12usize, vec![]);
    while i + 8 <= b.len() {
        let size = u32::from_le_bytes(b[i + 4..i + 8].try_into().ok()?) as usize;
        if &b[i..i + 4] == b"ANMF" {
            let p = b.get(i + 8..i + 8 + 16)?;
            times.push(u32::from_le_bytes([p[12], p[13], p[14], 0]));
        }
        i = i.checked_add(8 + size + (size & 1))?;
    }
    (!times.is_empty()).then_some(times)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_piece_decodes_to_frames_laid_on_the_surface_at_its_own_pace() {
        let wait = include_bytes!("../../../gallery/animation/embers/tokyonight-night/wait.gif");
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
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../../gallery/animation");
        let mut n = 0;
        // a piece is a folder; one a tool left (__pycache__ beside lib/animation.py) is not, and a painted one (its own
        // open.webp) has its own test
        for piece in std::fs::read_dir(root)
            .unwrap()
            .flatten()
            .filter(|e| e.path().is_dir() && !e.file_name().to_string_lossy().starts_with(['_', '.']) && !e.path().join("open.webp").is_file())
        {
            for pal in ["tokyonight-night", "solarized-light"] {
                for reel in ["open", "wait", "close"] {
                    let bytes = std::fs::read(piece.path().join(pal).join(format!("{}.gif", reel))).unwrap();
                    let f = film(&bytes).unwrap_or_else(|| panic!("{:?} {} {}", piece.path(), pal, reel));
                    assert_eq!((f.w, f.h), (180, 120));
                    n += 1;
                }
            }
        }
        assert_eq!(n, 6 * 2 * 3, "six drawn pieces");
    }

    #[test]
    fn a_painted_piece_plays_as_it_reads_in_its_own_colors() {
        let at = |reel: &str| std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/../../gallery/animation/atlas/").to_string() + reel + ".webp").unwrap();
        // twice the drawn pieces' size; its frames and their times read from the headers: open and close 3.6 seconds
        // each, a turn of the wait 9.6
        for (reel, frames, ms) in [("open", 106, 3599), ("wait", 288, 9599), ("close", 106, 3599)] {
            let f = film_webp(at(reel), true).unwrap();
            assert_eq!((f.w, f.h, f.frames.len(), f.length()), (360, 240, frames, ms), "{}", reel);
            assert!(f.pics.is_empty(), "{}: no frame is held but the one shown", reel);
        }
        // the open ends where the close starts, the control raised: no pass through the wait's pose between them
        let (o, c) = (film_webp(at("open"), true).unwrap(), film_webp(at("close"), true).unwrap());
        assert_eq!(o.pic(o.frames.len() - 1).unwrap(), c.pic(0).unwrap());
        let f = film_webp(at("open"), true).unwrap();
        // a frame, then one before it: read again from the first, the same pixels
        let (late, early) = (f.pic(60).unwrap(), f.pic(20).unwrap());
        assert_eq!(f.pic(20).unwrap(), early);
        assert_eq!(f.pic(60).unwrap(), late);
        assert_ne!(early, late);
        // its own colors, its edges soft: a pixel partly clear, and a warm one (the painted bronze, no palette's)
        let px: Vec<[u8; 4]> = late.data.chunks(4).map(|p| u32::from_ne_bytes(p.try_into().unwrap()).to_be_bytes()).collect();
        assert!(px.iter().any(|p| p[0] > 0 && p[0] < 255), "a soft edge");
        assert!(px.iter().any(|p| p[0] == 255 && p[1] > p[3] + 40), "a warm color, red over blue");
        assert!(px[0][0] == 0, "the corner is clear: the window's ground shows");
        // as sixel for a terminal, the ground unpainted
        let s = film_webp(at("wait"), false).unwrap();
        assert!(s.sixel(10).unwrap().starts_with("\x1bP0;1;0q\"1;1;360;240"));
        assert!(film_webp(b"RIFF\0\0\0\0WEBPnot one".to_vec(), true).is_none());
        assert!(film_webp(
            std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/../../gallery/animation/embers/tokyonight-night/wait.gif")).unwrap(),
            true
        )
        .is_none());
    }
}
