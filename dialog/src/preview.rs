//! The preview (#120): one file of a list, as large as the content area allows. Up and down go
//! through the list's files, left and right through the file's pages; Esc, or Space with nothing
//! typed, goes back to the list, and Enter opens the file. A picture zooms, moves and turns; a sound
//! plays with its waveform and its spectrum. The provider reads the file and answers a page; the
//! dialog draws three shapes, lines, a picture or a sound, and never looks at a file's type.

use crate::model::{self, Call, Row};
use crate::scrub::scrub;
use crate::sixel::{Image, Viewport};
use serde_json::Value;

/// The lines one page brings, at most: a longer text says where its preview stops.
pub const LINES_MAX: usize = 20_000;
/// The facts a page shows at its foot, at most.
pub const FACTS_MAX: usize = 8;
/// The zoom's stops, in percent: 100 is a picture's own pixels, a PDF page at 96 pixels an inch.
pub const STOPS: [u32; 10] = [25, 33, 50, 67, 100, 150, 200, 300, 400, 800];
/// An arrow moves a zoomed picture by this share of the part shown.
pub const PAN: f64 = 0.25;
/// A sound's spectrum: this many bands, low to high.
pub const BANDS: usize = 28;

/// What a provider answers for a file: its name, its facts, and lines or a picture.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Page {
    /// The uri this page answers: an answer for a file left meanwhile lands nowhere.
    pub uri: String,
    pub title: String,
    /// The file's facts, each a few words ("412 kB", "4032 by 3024", "3:45").
    pub facts: Vec<String>,
    pub lines: Vec<String>,
    /// The lines drawn bold, by index: a heading.
    pub bold: Vec<usize>,
    /// Lines numbered at the left, muted: source code.
    pub numbered: bool,
    /// A PNG of the page: absolute, a .png, no parent step (as a row's preview).
    pub picture: Option<String>,
    /// A picture's page and how many the file has (a PDF); text is paged here, by the area.
    pub page: usize,
    pub pages: usize,
    /// One line where there is no preview, and why.
    pub say: Option<String>,
    /// A text of the page spark can read, as a file the provider wrote: the attach path takes it.
    pub attach: Option<String>,
    /// Right plays the file: here (a sound), or in its app (a video, through the open tool).
    pub play: Option<Call>,
    /// What stops a sound playing here; leaving the file calls it.
    pub stop: Option<Call>,
    /// A sound's length in seconds: the key row says Play again once it has ended, and the waveform
    /// knows where it is.
    pub seconds: f64,
    /// A picture's size at 100 %: its own pixels, a PDF page's at 96 pixels an inch.
    pub size: Option<(u32, u32)>,
    /// The picture is the largest the provider draws: a zoom past it asks for nothing more.
    pub full: bool,
    /// A sound: a PNG of its waveform over its spectrogram, and the waveform's height in it.
    pub sound: Option<(String, u32)>,
}

/// A sound as the dialog draws it, read once from its picture: the waveform's loudness at each of
/// its columns (0 to 1), the spectrum's bands at each column (0 to 255), and the spectrogram itself.
#[derive(Clone, Debug, PartialEq)]
pub struct Sound {
    pub wave: Vec<f32>,
    pub bands: Vec<[u8; BANDS]>,
    pub spectrogram: Image,
}

/// The preview's place: the provider, the list it came from (its files, in its order), the file
/// shown, its page, and the page as it came.
#[derive(Clone, Debug, PartialEq)]
pub struct Preview {
    pub prov: usize,
    /// The words of the list's place, for the header ("~/docs").
    pub place: String,
    pub files: Vec<Row>,
    pub at: usize,
    /// The page shown, from 1.
    pub page: usize,
    pub shown: Option<Page>,
    /// When the sound started, while it plays here, and where it was in it then, in seconds.
    pub playing: Option<std::time::Instant>,
    pub played: f64,
    /// A picture's quarter turns, its zoom in percent (None fits it) and the point at the middle of
    /// the box, as a share of the picture turned.
    pub turn: u8,
    pub zoom: Option<u32>,
    pub center: (f64, f64),
    /// The page drawn larger was asked for (a zoom past the picture's pixels).
    pub full: bool,
    /// The picture's box in pixels and the picture's own pixels, as main.rs last drew it.
    pub px: (u32, u32),
    pub src: (u32, u32),
    /// The sound read from its picture (main.rs reads it once).
    pub heard: Option<Sound>,
    /// When the page on screen was asked for: one slow to come shows the wait (#122).
    pub asked: std::time::Instant,
    /// The page asked for did not come (refused, or not in time): the wait ends (#124).
    pub failed: bool,
    /// Where the picture was drawn, in the terminal's pixels from the grid's corner: a video plays over it (#125).
    pub frame: Option<(u32, u32, u32, u32)>,
}

impl Preview {
    /// The preview of `files[at]`, None when no row of the list has a page.
    pub fn new(prov: usize, place: &str, rows: &[Row], lit: &str) -> Option<Preview> {
        let files: Vec<Row> = rows.iter().filter(|r| r.page.is_some()).cloned().collect();
        let at = files.iter().position(|r| r.id == lit)?;
        Some(Preview {
            prov,
            place: place.to_string(),
            files,
            at,
            page: 1,
            shown: None,
            playing: None,
            played: 0.0,
            turn: 0,
            zoom: None,
            center: (0.5, 0.5),
            full: false,
            px: (0, 0),
            src: (0, 0),
            heard: None,
            asked: std::time::Instant::now(),
            failed: false,
            frame: None,
        })
    }

    pub fn row(&self) -> &Row {
        &self.files[self.at]
    }

    /// The uri of the page to read now: the row's own, with the page asked for past the first and
    /// the picture drawn larger once a zoom asked for it.
    pub fn uri(&self) -> String {
        let base = self.row().page.clone().unwrap_or_default();
        let mut q = vec![];
        if self.page > 1 && self.shown.as_ref().is_some_and(|p| p.picture.is_some()) {
            q.push(format!("page={}", self.page));
        }
        if self.full {
            q.push("full=1".to_string());
        }
        if q.is_empty() {
            base
        } else {
            format!("{}?{}", base, q.join("&"))
        }
    }

    /// Another file of the list, d away; false at either end.
    pub fn step_file(&mut self, d: i32) -> bool {
        let to = self.at as i64 + d as i64;
        if to < 0 || to >= self.files.len() as i64 {
            return false;
        }
        self.at = to as usize;
        self.page = 1;
        self.shown = None;
        self.playing = None;
        self.played = 0.0;
        self.heard = None;
        self.fit();
        self.turn = 0;
        self.full = false;
        true
    }

    /// Another page, d away, of `pages`; false at either end.
    pub fn step_page(&mut self, d: i32, pages: usize) -> bool {
        let to = self.page as i64 + d as i64;
        if to < 1 || to > pages as i64 {
            return false;
        }
        self.page = to as usize;
        self.fit();
        true
    }

    /// Where the sound is now, in seconds: where it started plus the time since, while it plays.
    pub fn position(&self, now: std::time::Instant) -> f64 {
        let len = self.shown.as_ref().map(|p| p.seconds).unwrap_or(0.0);
        let at = self.played + self.playing.map(|t| now.duration_since(t).as_secs_f64()).unwrap_or(0.0);
        if len > 0.0 {
            at.min(len)
        } else {
            at
        }
    }

    /// Whether the sound plays still: its length has not run out since it started.
    pub fn plays(&self, now: std::time::Instant) -> bool {
        match (self.playing, &self.shown) {
            (Some(_), Some(p)) => p.seconds <= 0.0 || self.position(now) < p.seconds,
            _ => false,
        }
    }

    /// The picture's size at 100 %, turned; its own pixels where the provider gave none.
    fn size(&self) -> Option<(f64, f64)> {
        let (w, h) = self.shown.as_ref()?.size.or((self.src.0 > 0).then_some(self.src))?;
        let (w, h) = if self.turn % 2 == 1 { (h, w) } else { (w, h) };
        Some((w as f64, h as f64))
    }

    /// Box pixels a pixel of the picture drawn, at the zoom asked for, or fitted.
    fn scale(&self) -> Option<f64> {
        let (w, _) = self.size()?;
        let (sw, sh) = if self.turn % 2 == 1 { (self.src.1, self.src.0) } else { self.src };
        if sw == 0 || self.px.0 == 0 {
            return None;
        }
        Some(match self.zoom {
            Some(z) => z as f64 / 100.0 * w / sw as f64,
            None => (self.px.0 as f64 / sw as f64).min(self.px.1 as f64 / sh as f64).min(1.0),
        })
    }

    /// The zoom as drawn now, in percent: the one asked for, else the fit's.
    pub fn percent(&self) -> Option<u32> {
        if let Some(z) = self.zoom {
            return Some(z);
        }
        let (w, _) = self.size()?;
        let sw = if self.turn % 2 == 1 { self.src.1 } else { self.src.0 };
        Some((self.scale()? * sw as f64 / w * 100.0).round().max(1.0) as u32)
    }

    /// How the picture is drawn now, for sixel::show.
    pub fn viewport(&self) -> Viewport {
        Viewport {
            turn: self.turn,
            scale: self.zoom.and_then(|_| self.scale()),
            at: self.center,
        }
    }

    /// The picture fitted again, at its middle.
    pub fn fit(&mut self) {
        self.zoom = None;
        self.center = (0.5, 0.5);
    }

    /// A zoom stop in (+1) or out (-1); out past the fit fits it. False where it stays as it is.
    pub fn zoom_step(&mut self, d: i32) -> bool {
        let Some(now) = self.percent() else { return false };
        let fit = self.zoom.map_or(now, |_| {
            let z = self.zoom.take();
            let f = self.percent().unwrap_or(now);
            self.zoom = z;
            f
        });
        let to = if d > 0 {
            STOPS.iter().copied().find(|s| *s > now)
        } else {
            STOPS.iter().rev().copied().find(|s| *s < now).filter(|s| *s > fit)
        };
        match to {
            Some(z) => self.zoom = Some(z),
            None if d < 0 && self.zoom.is_some() => self.fit(),
            None => return false,
        }
        self.hold();
        true
    }

    /// A quarter turn, clockwise (+1) or back (-1), fitted again.
    pub fn rotate(&mut self, d: i32) {
        self.turn = ((self.turn as i32 + d).rem_euclid(4)) as u8;
        self.fit();
    }

    /// The part shown moved, in shares of what is shown (an arrow moves PAN of it).
    pub fn pan(&mut self, dx: f64, dy: f64) {
        let Some(k) = self.scale() else { return };
        let (sw, sh) = if self.turn % 2 == 1 { (self.src.1, self.src.0) } else { self.src };
        let (vw, vh) = (
            (self.px.0 as f64 / k / sw.max(1) as f64).min(1.0),
            (self.px.1 as f64 / k / sh.max(1) as f64).min(1.0),
        );
        self.center = (self.center.0 + dx * vw, self.center.1 + dy * vh);
        self.hold();
    }

    /// The middle held where the picture still covers the box.
    fn hold(&mut self) {
        let Some(k) = self.scale() else { return };
        let (sw, sh) = if self.turn % 2 == 1 { (self.src.1, self.src.0) } else { self.src };
        let half = |box_px: u32, n: u32| (box_px as f64 / k / n.max(1) as f64 / 2.0).min(0.5);
        let (hx, hy) = (half(self.px.0, sw), half(self.px.1, sh));
        self.center = (self.center.0.clamp(hx, 1.0 - hx), self.center.1.clamp(hy, 1.0 - hy));
    }

    /// The zoom asks for more than the picture holds, and the larger one was not asked for yet.
    pub fn needs_full(&self) -> bool {
        !self.full && self.shown.as_ref().is_some_and(|p| p.picture.is_some() && !p.full) && self.zoom.is_some() && self.scale().is_some_and(|k| k > 1.0)
    }
}

/// A sound read from its picture (the provider's waveform over its spectrogram, `wave` rows of it the
/// waveform): the loudness of each column, the spectrum's bands at each column (low first), and the
/// spectrogram for its picture.
pub fn sound(img: &Image, wave: u32) -> Option<Sound> {
    if wave == 0 || wave >= img.h || img.w == 0 {
        return None;
    }
    let lit = |x: u32, y: u32| {
        let p = img.pixel(x, y);
        (p[0] as u32 + p[1] as u32 + p[2] as u32) / 3
    };
    // the waveform is drawn about its middle: a column's loudness is how far its ink reaches
    let wave_at: Vec<f32> = (0..img.w)
        .map(|x| {
            let ink: Vec<u32> = (0..wave).filter(|y| lit(x, *y) > 64).collect();
            match (ink.first(), ink.last()) {
                (Some(a), Some(b)) => (b - a + 1) as f32 / wave as f32,
                _ => 0.0,
            }
        })
        .collect();
    // the spectrogram, high at its top: its rows cut into BANDS, the low band last
    let rows = img.h - wave;
    let bands: Vec<[u8; BANDS]> = (0..img.w)
        .map(|x| {
            let mut b = [0u8; BANDS];
            for (k, slot) in b.iter_mut().enumerate() {
                let (y0, y1) = (rows * (BANDS - 1 - k) as u32 / BANDS as u32, rows * (BANDS - k) as u32 / BANDS as u32);
                let n = (y1 - y0).max(1);
                *slot = ((y0..y1).map(|y| lit(x, wave + y)).sum::<u32>() / n) as u8;
            }
            b
        })
        .collect();
    Some(Sound {
        wave: wave_at,
        bands,
        spectrogram: img.rows(wave, img.h),
    })
}

/// A picture's path is held to a preview's shape: absolute, a PNG, no parent step, no control.
fn png_path(v: Option<&Value>) -> Option<String> {
    let p = v?.as_str()?;
    (p.starts_with('/') && p.ends_with(".png") && !p.split('/').any(|c| c == "..") && !p.chars().any(char::is_control)).then(|| p.to_string())
}

/// A text for spark is a file the provider wrote, held to the same shape, a .txt.
fn attach(v: Option<&Value>) -> Option<String> {
    let p = v?.as_str()?;
    (p.starts_with('/') && p.ends_with(".txt") && !p.split('/').any(|c| c == "..") && !p.chars().any(char::is_control)).then(|| p.to_string())
}

/// A page from a resource read's text; None when it is not one. Every string scrubbed as it is read.
pub fn page(uri: &str, text: &str) -> Option<Page> {
    let v: Value = serde_json::from_str(text).ok()?;
    let str_of = |k: &str| v.get(k).and_then(Value::as_str).map(scrub).filter(|t| !t.is_empty());
    let lines: Vec<String> = v
        .get("lines")
        .and_then(Value::as_array)
        .map(|a| a.iter().take(LINES_MAX).map(|l| scrub(l.as_str().unwrap_or(""))).collect())
        .unwrap_or_default();
    let n = lines.len();
    let picture = png_path(v.get("picture"));
    let pages = v.get("pages").and_then(Value::as_u64).unwrap_or(1).clamp(1, 100_000) as usize;
    Some(Page {
        uri: uri.to_string(),
        title: str_of("title").unwrap_or_default(),
        facts: v
            .get("facts")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .map(scrub)
                    .filter(|f| !f.is_empty() && f.chars().count() <= 40)
                    .take(FACTS_MAX)
                    .collect()
            })
            .unwrap_or_default(),
        bold: v
            .get("bold")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(Value::as_u64).map(|i| i as usize).filter(|i| *i < n).collect())
            .unwrap_or_default(),
        numbered: v.get("numbered").and_then(Value::as_bool).unwrap_or(false),
        page: v.get("page").and_then(Value::as_u64).unwrap_or(1).clamp(1, pages as u64) as usize,
        pages: if picture.is_some() { pages } else { 1 },
        picture,
        lines,
        say: str_of("say"),
        attach: attach(v.get("attach")),
        play: v.get("play").and_then(model::call),
        stop: v.get("stop").and_then(model::call),
        size: v
            .get("size")
            .and_then(Value::as_array)
            .and_then(|a| Some((a.first()?.as_u64()? as u32, a.get(1)?.as_u64()? as u32)))
            .filter(|(w, h)| *w > 0 && *h > 0 && *w <= 1 << 20 && *h <= 1 << 20),
        full: v.get("full").and_then(Value::as_bool).unwrap_or(false),
        sound: v
            .get("sound")
            .and_then(|s| Some((png_path(s.get("picture"))?, s.get("wave")?.as_u64()? as u32))),
        seconds: v
            .get("seconds")
            .and_then(Value::as_f64)
            .filter(|s| s.is_finite())
            .unwrap_or(0.0)
            .clamp(0.0, 86_400.0),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, page: Option<&str>) -> Row {
        let mut r = model::rows(&format!(r#"{{"title":"t","rows":[{{"id":"{}","text":"{}"}}]}}"#, id, id))
            .unwrap()
            .rows
            .remove(0);
        r.page = page.map(str::to_string);
        r
    }

    #[test]
    fn a_page_is_read_and_held_to_its_shapes() {
        let p = page(
            "spark-shell://files/preview/x",
            r##"{"title":"notes\u001b[2J.md","facts":["2 kB","a fact far too long to be one, past forty cells","today"],
               "lines":["# one","two\u0007"],"bold":[0,9],"numbered":true,"picture":"/data/me/../etc/x.png",
               "attach":"/data/me/.cache/p.txt","play":{"name":"files_play","arguments":{"path":"/data/me/a.mp3"}},"seconds":225}"##,
        )
        .unwrap();
        assert_eq!(p.title, "notes[2J.md");
        assert_eq!(p.facts, vec!["2 kB", "today"]);
        assert_eq!(p.lines, vec!["# one", "two"]);
        assert_eq!(p.bold, vec![0]);
        assert!(p.numbered && p.picture.is_none() && p.pages == 1);
        assert_eq!(p.attach.as_deref(), Some("/data/me/.cache/p.txt"));
        assert_eq!(p.play.map(|c| c.name), Some("files_play".to_string()));
        assert_eq!(p.seconds, 225.0);
        let q = page("u", r#"{"title":"r.pdf","picture":"/c/r-3.png","page":3,"pages":14,"attach":"/c/r.pdf"}"#).unwrap();
        assert_eq!((q.picture.as_deref(), q.page, q.pages, q.attach), (Some("/c/r-3.png"), 3, 14, None));
        assert!(page("u", "not json").is_none());
    }

    #[test]
    fn the_arrows_move_through_files_and_pages() {
        let rows = vec![row("a", Some("p://a")), row("dir", None), row("b", Some("p://b")), row("c", Some("p://c"))];
        let mut v = Preview::new(0, "~/docs", &rows, "b").unwrap();
        assert_eq!((v.files.len(), v.at), (3, 1));
        assert!(Preview::new(0, "~", &rows, "dir").is_none());
        assert!(v.step_file(1) && v.row().id == "c" && !v.step_file(1));
        assert!(v.step_file(-2) && v.row().id == "a" && !v.step_file(-1));
        assert_eq!(v.uri(), "p://a");
        v.shown = page("p://a", r#"{"picture":"/c/a.png","pages":3}"#);
        assert!(v.step_page(1, 3) && v.step_page(1, 3) && !v.step_page(1, 3));
        assert_eq!(v.uri(), "p://a?page=3");
        assert!(v.step_file(1) && v.page == 1 && v.shown.is_none());
    }

    #[test]
    fn a_picture_zooms_along_the_stops_moves_inside_itself_and_turns() {
        let mut v = Preview::new(0, "~", &[row("a", Some("p://a"))], "a").unwrap();
        v.shown = page("p://a", r#"{"picture":"/c/a.png","size":[4000,3000]}"#);
        (v.src, v.px) = ((1600, 1200), (500, 500));
        // fitted: 500 box pixels for the 1600 drawn, 4000 the picture's own: 12.5 %
        assert_eq!((v.percent(), v.viewport().scale), (Some(13), None));
        assert!(v.zoom_step(1) && v.zoom == Some(25) && !v.needs_full());
        assert!(v.zoom_step(1) && v.zoom_step(1) && v.zoom_step(1) && v.zoom_step(1) && v.zoom == Some(100));
        assert!(v.needs_full(), "100 % is 2.5 box pixels a pixel drawn: the larger picture is asked for");
        assert_eq!(v.viewport().scale, Some(2.5));
        // moved past its edge, the middle stays where the picture covers the box
        v.pan(-10.0, 0.0);
        assert!((v.center.0 - 500.0 / 2.5 / 1600.0 / 2.0).abs() < 1e-9 && v.center.1 == 0.5);
        // out past the fit fits it; a turn fits it again and swaps the sides
        assert!(v.zoom_step(-1) && v.zoom == Some(67));
        for _ in 0..4 {
            v.zoom_step(-1);
        }
        assert_eq!((v.zoom, v.center), (None, (0.5, 0.5)));
        assert!(!v.zoom_step(-1), "fitted, out does nothing");
        v.rotate(-1);
        assert_eq!((v.turn, v.viewport().turn), (3, 3));
        // turned, the long side stands: 500 box pixels for its 1600 drawn, 4000 its own, 12.5 % again
        assert_eq!(v.percent(), Some(13));
        assert_eq!(v.size(), Some((3000.0, 4000.0)));
    }

    #[test]
    fn a_sound_is_read_from_its_waveform_and_its_spectrogram() {
        // 2 columns: a waveform 4 rows tall (the first column's ink 2 of them, the second none),
        // then a spectrogram of 28 rows, bright at its bottom (the low band) in the first column
        let mut px = vec![];
        for y in 0..32u32 {
            for x in 0..2u32 {
                let on = (y < 4 && x == 0 && (1..3).contains(&y)) || (y >= 31 && x == 0);
                px.extend(if on { [255u8, 255, 255, 255] } else { [0, 0, 0, 255] });
            }
        }
        let mut raw = Vec::new();
        {
            let mut e = png::Encoder::new(&mut raw, 2, 32);
            e.set_color(png::ColorType::Rgba);
            e.set_depth(png::BitDepth::Eight);
            e.write_header().unwrap().write_image_data(&px).unwrap();
        }
        let s = sound(&crate::sixel::decode(&raw).unwrap(), 4).unwrap();
        assert_eq!(s.wave, vec![0.5, 0.0]);
        assert_eq!((s.bands[0][0], s.bands[0][BANDS - 1], s.bands[1][0]), (255, 0, 0));
        assert_eq!((s.spectrogram.w, s.spectrogram.h), (2, 28));
    }

    #[test]
    fn a_sound_knows_where_it_is() {
        let mut v = Preview::new(0, "~", &[row("a", Some("p://a"))], "a").unwrap();
        v.shown = page("p://a", r#"{"seconds":10.5,"lines":["a"]}"#);
        let t = std::time::Instant::now();
        v.played = 4.0;
        assert_eq!(v.position(t), 4.0);
        v.playing = Some(t);
        assert!(v.plays(t + std::time::Duration::from_secs(6)) && !v.plays(t + std::time::Duration::from_secs(7)));
        assert_eq!(v.position(t + std::time::Duration::from_secs(60)), 10.5);
    }
}
