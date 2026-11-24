//! The small pictures the layout in pixels draws over a box (Step::Cover): each a step the painter takes, made once
//! for its file, its time and its box.

use crate::draw::{Pic, Step};
use crate::sixel::{self, Viewport};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::SystemTime;

/// The most a small picture's file may weigh.
const MOST: u64 = 4 << 20;

type Key = (String, u32, u32);

#[derive(Default)]
pub struct Thumbs {
    kept: HashMap<Key, (SystemTime, Option<Arc<Pic>>)>,
}

impl Thumbs {
    /// The steps with each cover its picture, drawn for a screen of `scale` of its pixels on one of the window's; one
    /// whose file is not there, or is no picture, draws nothing. What this frame did not draw is let go.
    pub fn put(&mut self, steps: Vec<Step>, scale: u32) -> Vec<Step> {
        let mut was = std::mem::take(&mut self.kept);
        let mut out = Vec::with_capacity(steps.len());
        for step in steps {
            let Step::Cover { x, y, w, h, file } = step else {
                out.push(step);
                continue;
            };
            let (bw, bh) = ((w * scale as f64) as u32, (h * scale as f64) as u32);
            let Some(when) = time(&file) else { continue };
            let key = (file, bw, bh);
            if !self.kept.contains_key(&key) {
                let made = was.remove(&key).filter(|(t, _)| *t == when).unwrap_or_else(|| (when, cover(&key.0, bw, bh)));
                self.kept.insert(key.clone(), made);
            }
            if let Some(pic) = self.kept.get(&key).and_then(|(_, p)| p.clone()) {
                out.push(Step::Picture {
                    x,
                    y,
                    scale: scale as f64,
                    pic,
                });
            }
        }
        out
    }
}

/// When a small picture's file was last written: a regular file of MOST at most, no link.
fn time(file: &str) -> Option<SystemTime> {
    let meta = std::fs::symlink_metadata(file).ok().filter(|m| m.is_file() && m.len() <= MOST)?;
    meta.modified().ok()
}

/// A picture over the whole of a box, its middle where the shapes differ.
fn cover(file: &str, bw: u32, bh: u32) -> Option<Arc<Pic>> {
    let img = sixel::decode(&std::fs::read(file).ok()?)?;
    let scale = (bw as f64 / img.w.max(1) as f64).max(bh as f64 / img.h.max(1) as f64);
    let view = Viewport {
        scale: Some(scale),
        ..Viewport::FIT
    };
    let made = sixel::fit(&img, bw, bh, &view)?;
    Some(Arc::new(Pic::of(&made)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(w: u32, h: u32, color: [u8; 3]) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut e = png::Encoder::new(&mut bytes, w, h);
        e.set_color(png::ColorType::Rgb);
        e.set_depth(png::BitDepth::Eight);
        let raw: Vec<u8> = (0..w * h).flat_map(|_| color).collect();
        e.write_header().unwrap().write_image_data(&raw).unwrap();
        bytes
    }

    fn at(file: &str, w: f64, h: f64) -> Step {
        Step::Cover {
            x: 3.0,
            y: 4.0,
            w,
            h,
            file: file.to_string(),
        }
    }

    #[test]
    fn a_cover_is_its_picture_over_the_whole_of_its_box() {
        let dir = std::env::temp_dir().join(format!("spark-dialog-thumbs-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("a.png");
        std::fs::write(&file, png(100, 50, [255, 0, 0])).unwrap();
        let name = file.to_str().unwrap();
        let mut thumbs = Thumbs::default();
        let fill = Step::Unclip;
        for scale in [1, 2] {
            let got = thumbs.put(vec![fill.clone(), at(name, 40.0, 60.0)], scale);
            let [Step::Unclip, Step::Picture { x, y, scale: s, pic }] = &got[..] else {
                panic!("{got:?}")
            };
            assert_eq!((*x, *y, *s, pic.w, pic.h), (3.0, 4.0, scale as f64, 40 * scale, 60 * scale));
        }
        // the same file again is the same pixels; a file rewritten is read again
        let one = thumbs.put(vec![at(name, 40.0, 60.0)], 1);
        let two = thumbs.put(vec![at(name, 40.0, 60.0)], 1);
        let (Step::Picture { pic: a, .. }, Step::Picture { pic: b, .. }) = (&one[0], &two[0]) else {
            panic!()
        };
        assert!(Arc::ptr_eq(a, b));
        assert_eq!(thumbs.kept.len(), 1, "what a frame does not draw is let go");
        // what is no picture draws nothing: not there, a link, a file that is none, one too large
        let link = dir.join("link.png");
        let _ = std::os::unix::fs::symlink(&file, &link);
        let bad = dir.join("bad.png");
        std::fs::write(&bad, b"no picture").unwrap();
        let large = dir.join("large.png");
        std::fs::File::create(&large).unwrap().set_len(MOST + 1).unwrap();
        for f in [dir.join("none.png"), link, bad, large, dir.clone()] {
            assert_eq!(thumbs.put(vec![at(f.to_str().unwrap(), 40.0, 60.0)], 1), vec![], "{f:?}");
        }
        assert_eq!(thumbs.put(vec![at(name, 4.0, 4.0)], 1), vec![], "a box too small for one");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
