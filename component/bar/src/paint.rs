//! Drawing with cairo and pango: opened at run time by their sonames, so the binary needs no -devel
//! package and runs on each family's own. Only the functions used are typed, each under its name in
//! cairo.h, pango-layout.h, pango-markup.h and pangocairo.h.

use crate::bar;
use libloading::Library;
use std::ffi::{c_char, c_int, c_void, CString};

#[repr(C)]
pub struct CairoSurface {
    _opaque: [u8; 0],
}
#[repr(C)]
pub struct Cairo {
    _opaque: [u8; 0],
}
#[repr(C)]
struct FontDesc {
    _opaque: [u8; 0],
}
#[repr(C)]
struct PangoLayout {
    _opaque: [u8; 0],
}

const CAIRO_FORMAT_ARGB32: c_int = 0;
const CAIRO_OPERATOR_SOURCE: c_int = 1;
const CAIRO_OPERATOR_OVER: c_int = 2;
const CAIRO_FILTER_GOOD: c_int = 1;
const PANGO_SCALE: c_int = 1024;

/// The functions of libcairo.so.2, libpango-1.0.so.0, libpangocairo-1.0.so.0 and libgobject-2.0.so.0.
pub struct Lib {
    _libs: Vec<Library>,
    image_surface_create: unsafe extern "C" fn(c_int, c_int, c_int) -> *mut CairoSurface,
    image_surface_create_for_data: unsafe extern "C" fn(*mut u8, c_int, c_int, c_int, c_int) -> *mut CairoSurface,
    image_surface_create_from_png: unsafe extern "C" fn(*const c_char) -> *mut CairoSurface,
    image_surface_get_width: unsafe extern "C" fn(*mut CairoSurface) -> c_int,
    image_surface_get_height: unsafe extern "C" fn(*mut CairoSurface) -> c_int,
    surface_status: unsafe extern "C" fn(*mut CairoSurface) -> c_int,
    surface_destroy: unsafe extern "C" fn(*mut CairoSurface),
    surface_flush: unsafe extern "C" fn(*mut CairoSurface),
    create: unsafe extern "C" fn(*mut CairoSurface) -> *mut Cairo,
    destroy: unsafe extern "C" fn(*mut Cairo),
    scale: unsafe extern "C" fn(*mut Cairo, f64, f64),
    save: unsafe extern "C" fn(*mut Cairo),
    restore: unsafe extern "C" fn(*mut Cairo),
    translate: unsafe extern "C" fn(*mut Cairo, f64, f64),
    set_operator: unsafe extern "C" fn(*mut Cairo, c_int),
    paint: unsafe extern "C" fn(*mut Cairo),
    set_source_rgba: unsafe extern "C" fn(*mut Cairo, f64, f64, f64, f64),
    set_source_surface: unsafe extern "C" fn(*mut Cairo, *mut CairoSurface, f64, f64),
    get_source: unsafe extern "C" fn(*mut Cairo) -> *mut c_void,
    pattern_set_filter: unsafe extern "C" fn(*mut c_void, c_int),
    rectangle: unsafe extern "C" fn(*mut Cairo, f64, f64, f64, f64),
    fill: unsafe extern "C" fn(*mut Cairo),
    clip: unsafe extern "C" fn(*mut Cairo),
    move_to: unsafe extern "C" fn(*mut Cairo, f64, f64),
    font_description_from_string: unsafe extern "C" fn(*const c_char) -> *mut FontDesc,
    font_description_free: unsafe extern "C" fn(*mut FontDesc),
    font_description_get_size: unsafe extern "C" fn(*mut FontDesc) -> c_int,
    font_description_get_size_is_absolute: unsafe extern "C" fn(*mut FontDesc) -> c_int,
    layout_set_font_description: unsafe extern "C" fn(*mut PangoLayout, *mut FontDesc),
    layout_set_text: unsafe extern "C" fn(*mut PangoLayout, *const c_char, c_int),
    layout_set_markup: unsafe extern "C" fn(*mut PangoLayout, *const c_char, c_int),
    layout_get_pixel_size: unsafe extern "C" fn(*mut PangoLayout, *mut c_int, *mut c_int),
    #[allow(clippy::type_complexity)]
    parse_markup: unsafe extern "C" fn(*const c_char, c_int, u32, *mut c_void, *mut c_void, *mut c_void, *mut c_void) -> c_int,
    cairo_create_layout: unsafe extern "C" fn(*mut Cairo) -> *mut PangoLayout,
    cairo_show_layout: unsafe extern "C" fn(*mut Cairo, *mut PangoLayout),
    object_unref: unsafe extern "C" fn(*mut c_void),
}

fn open(soname: &str, what: &str) -> Result<Library, String> {
    unsafe { Library::new(soname) }.map_err(|_| format!("{soname} is missing ({what})"))
}

/// A function of an open library, by its name.
fn get<T: Copy>(lib: &Library, soname: &str, name: &str) -> Result<T, String> {
    unsafe { lib.get::<T>(name.as_bytes()) }
        .map(|s| *s)
        .map_err(|_| format!("{soname} has no {name}"))
}

macro_rules! sym {
    ($lib:expr, $soname:expr, $name:literal) => {
        get(&$lib, $soname, $name)?
    };
}

impl Lib {
    /// Opens the four; the error names the first one missing.
    pub fn open() -> Result<Lib, String> {
        let cairo = open("libcairo.so.2", "cairo, which draws the bar")?;
        let pango = open("libpango-1.0.so.0", "pango, which sets the bar's text")?;
        let pc = open("libpangocairo-1.0.so.0", "pango's cairo half")?;
        let gobject = open("libgobject-2.0.so.0", "GLib's objects")?;
        let (c, p, q, g) = ("libcairo.so.2", "libpango-1.0.so.0", "libpangocairo-1.0.so.0", "libgobject-2.0.so.0");
        let lib = Lib {
            image_surface_create: sym!(cairo, c, "cairo_image_surface_create"),
            image_surface_create_for_data: sym!(cairo, c, "cairo_image_surface_create_for_data"),
            image_surface_create_from_png: sym!(cairo, c, "cairo_image_surface_create_from_png"),
            image_surface_get_width: sym!(cairo, c, "cairo_image_surface_get_width"),
            image_surface_get_height: sym!(cairo, c, "cairo_image_surface_get_height"),
            surface_status: sym!(cairo, c, "cairo_surface_status"),
            surface_destroy: sym!(cairo, c, "cairo_surface_destroy"),
            surface_flush: sym!(cairo, c, "cairo_surface_flush"),
            create: sym!(cairo, c, "cairo_create"),
            destroy: sym!(cairo, c, "cairo_destroy"),
            scale: sym!(cairo, c, "cairo_scale"),
            save: sym!(cairo, c, "cairo_save"),
            restore: sym!(cairo, c, "cairo_restore"),
            translate: sym!(cairo, c, "cairo_translate"),
            set_operator: sym!(cairo, c, "cairo_set_operator"),
            paint: sym!(cairo, c, "cairo_paint"),
            set_source_rgba: sym!(cairo, c, "cairo_set_source_rgba"),
            set_source_surface: sym!(cairo, c, "cairo_set_source_surface"),
            get_source: sym!(cairo, c, "cairo_get_source"),
            pattern_set_filter: sym!(cairo, c, "cairo_pattern_set_filter"),
            rectangle: sym!(cairo, c, "cairo_rectangle"),
            fill: sym!(cairo, c, "cairo_fill"),
            clip: sym!(cairo, c, "cairo_clip"),
            move_to: sym!(cairo, c, "cairo_move_to"),
            font_description_from_string: sym!(pango, p, "pango_font_description_from_string"),
            font_description_free: sym!(pango, p, "pango_font_description_free"),
            font_description_get_size: sym!(pango, p, "pango_font_description_get_size"),
            font_description_get_size_is_absolute: sym!(pango, p, "pango_font_description_get_size_is_absolute"),
            layout_set_font_description: sym!(pango, p, "pango_layout_set_font_description"),
            layout_set_text: sym!(pango, p, "pango_layout_set_text"),
            layout_set_markup: sym!(pango, p, "pango_layout_set_markup"),
            layout_get_pixel_size: sym!(pango, p, "pango_layout_get_pixel_size"),
            parse_markup: sym!(pango, p, "pango_parse_markup"),
            cairo_create_layout: sym!(pc, q, "pango_cairo_create_layout"),
            cairo_show_layout: sym!(pc, q, "pango_cairo_show_layout"),
            object_unref: sym!(gobject, g, "g_object_unref"),
            _libs: vec![],
        };
        Ok(Lib {
            _libs: vec![cairo, pango, pc, gobject],
            ..lib
        })
    }

    /// A layout on `cr` in the bar's font with a text on it: pango markup when `markup` and pango takes
    /// it, the same characters as plain text when it does not. The caller unrefs it.
    unsafe fn layout(&self, cr: *mut Cairo, font: &Font, s: &str, markup: bool) -> *mut PangoLayout {
        let t = CString::new(s.replace('\0', "")).unwrap_or_default();
        let null = std::ptr::null_mut();
        let l = (self.cairo_create_layout)(cr);
        (self.layout_set_font_description)(l, font.desc);
        if markup && (self.parse_markup)(t.as_ptr(), -1, 0, null, null, null, null) != 0 {
            (self.layout_set_markup)(l, t.as_ptr(), -1);
        } else {
            (self.layout_set_text)(l, t.as_ptr(), -1);
        }
        l
    }
}

/// An RGB color, 0 to 1 a channel.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgb(pub f64, pub f64, pub f64);

impl Rgb {
    /// rrggbb (or #rrggbb); None for anything else.
    pub fn hex(s: &str) -> Option<Rgb> {
        bar::hex(s).map(Rgb::of)
    }

    /// A color of the look.
    pub fn of([r, g, b]: bar::Color) -> Rgb {
        Rgb(r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0)
    }
}

/// The bar's font, as spark-shell names it (BAR_FONT).
pub struct Font {
    desc: *mut FontDesc,
    /// The text's size in pixels.
    pub px: f64,
}

impl Font {
    pub fn new(lib: &Lib, spec: &str) -> Font {
        let spec = CString::new(spec.replace('\0', "")).unwrap_or_default();
        unsafe {
            let desc = (lib.font_description_from_string)(spec.as_ptr());
            let size = (lib.font_description_get_size)(desc) as f64 / PANGO_SCALE as f64;
            let px = if size <= 0.0 {
                16.0
            } else if (lib.font_description_get_size_is_absolute)(desc) != 0 {
                size
            } else {
                size * 96.0 / 72.0
            };
            Font { desc, px }
        }
    }

    pub fn free(&self, lib: &Lib) {
        unsafe { (lib.font_description_free)(self.desc) }
    }
}

/// A picture loaded once: spark's mark.
pub struct Picture {
    s: *mut CairoSurface,
    pub w: i32,
    pub h: i32,
}

impl Picture {
    /// A PNG file, or None when cairo cannot read it.
    pub fn png(lib: &Lib, path: &str) -> Option<Picture> {
        let p = CString::new(path).ok()?;
        unsafe {
            let s = (lib.image_surface_create_from_png)(p.as_ptr());
            if s.is_null() || (lib.surface_status)(s) != 0 {
                if !s.is_null() {
                    (lib.surface_destroy)(s);
                }
                return None;
            }
            Some(Picture {
                s,
                w: (lib.image_surface_get_width)(s),
                h: (lib.image_surface_get_height)(s),
            })
        }
    }

    pub fn free(&self, lib: &Lib) {
        unsafe { (lib.surface_destroy)(self.s) }
    }
}

/// The widths of texts in the bar's font, measured on a surface of its own that is never shown.
pub struct Ruler {
    surface: *mut CairoSurface,
    cr: *mut Cairo,
}

impl Ruler {
    pub fn new(lib: &Lib) -> Ruler {
        unsafe {
            let surface = (lib.image_surface_create)(CAIRO_FORMAT_ARGB32, 8, 8);
            Ruler {
                surface,
                cr: (lib.create)(surface),
            }
        }
    }

    /// The width a line takes in logical pixels, uncut: pango markup, or plain text.
    pub fn width(&self, lib: &Lib, font: &Font, s: &str, markup: bool) -> f64 {
        unsafe {
            let l = lib.layout(self.cr, font, s, markup);
            let (mut tw, mut th) = (0, 0);
            (lib.layout_get_pixel_size)(l, &mut tw, &mut th);
            (lib.object_unref)(l as *mut c_void);
            tw as f64
        }
    }

    pub fn free(&self, lib: &Lib) {
        unsafe {
            (lib.destroy)(self.cr);
            (lib.surface_destroy)(self.surface);
        }
    }
}

/// How a line of text sits in its box.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Align {
    Left,
    Center,
}

/// A canvas in shared memory (ARGB, as wl_shm's Argb8888), drawn in logical pixels at a scale.
pub struct Canvas<'a> {
    lib: &'a Lib,
    font: &'a Font,
    surface: *mut CairoSurface,
    cr: *mut Cairo,
}

impl<'a> Canvas<'a> {
    /// `data` is `w` by `h` device pixels, `stride` bytes a row; drawing is in logical pixels at `scale`.
    pub fn new(lib: &'a Lib, font: &'a Font, data: &'a mut [u8], w: i32, h: i32, stride: i32, scale: f64) -> Option<Canvas<'a>> {
        if data.len() < (stride * h) as usize {
            return None;
        }
        unsafe {
            let surface = (lib.image_surface_create_for_data)(data.as_mut_ptr(), CAIRO_FORMAT_ARGB32, w, h, stride);
            if surface.is_null() || (lib.surface_status)(surface) != 0 {
                return None;
            }
            let cr = (lib.create)(surface);
            (lib.scale)(cr, scale, scale);
            // nothing under the bar: the canvas starts clear
            (lib.set_operator)(cr, CAIRO_OPERATOR_SOURCE);
            (lib.set_source_rgba)(cr, 0.0, 0.0, 0.0, 0.0);
            (lib.paint)(cr);
            (lib.set_operator)(cr, CAIRO_OPERATOR_OVER);
            Some(Canvas { lib, font, surface, cr })
        }
    }

    pub fn fill(&self, x: f64, y: f64, w: f64, h: f64, c: Rgb, alpha: f64) {
        unsafe {
            (self.lib.set_source_rgba)(self.cr, c.0, c.1, c.2, alpha);
            (self.lib.rectangle)(self.cr, x, y, w, h);
            (self.lib.fill)(self.cr);
        }
    }

    /// One line in a box `w` wide and `h` tall at x, y: at its left edge or centered, in the middle of its
    /// height, and cut where the box ends. Pango markup when `markup` says so.
    #[allow(clippy::too_many_arguments)]
    pub fn text(&self, x: f64, y: f64, w: f64, h: f64, s: &str, markup: bool, c: Rgb, align: Align) {
        unsafe {
            let l = self.lib.layout(self.cr, self.font, s, markup);
            let (mut tw, mut th) = (0, 0);
            (self.lib.layout_get_pixel_size)(l, &mut tw, &mut th);
            let tx = if align == Align::Center { x + ((w - tw as f64) / 2.0).max(0.0) } else { x };
            (self.lib.save)(self.cr);
            (self.lib.rectangle)(self.cr, x, y, w, h);
            (self.lib.clip)(self.cr);
            (self.lib.set_source_rgba)(self.cr, c.0, c.1, c.2, 1.0);
            (self.lib.move_to)(self.cr, tx.round(), (y + (h - th as f64) / 2.0).round());
            (self.lib.cairo_show_layout)(self.cr, l);
            (self.lib.restore)(self.cr);
            (self.lib.object_unref)(l as *mut c_void);
        }
    }

    /// A picture in a square of `side` at x, y, scaled to fit and centered.
    pub fn picture(&self, p: &Picture, x: f64, y: f64, side: f64) {
        if p.w <= 0 || p.h <= 0 {
            return;
        }
        let k = side / p.w.max(p.h) as f64;
        unsafe {
            (self.lib.save)(self.cr);
            (self.lib.translate)(self.cr, x + (side - p.w as f64 * k) / 2.0, y + (side - p.h as f64 * k) / 2.0);
            (self.lib.scale)(self.cr, k, k);
            (self.lib.set_source_surface)(self.cr, p.s, 0.0, 0.0);
            (self.lib.pattern_set_filter)((self.lib.get_source)(self.cr), CAIRO_FILTER_GOOD);
            (self.lib.paint)(self.cr);
            (self.lib.restore)(self.cr);
        }
    }
}

impl Drop for Canvas<'_> {
    fn drop(&mut self) {
        unsafe {
            (self.lib.surface_flush)(self.surface);
            (self.lib.destroy)(self.cr);
            (self.lib.surface_destroy)(self.surface);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colors() {
        assert_eq!(Rgb::hex("ff0080"), Some(Rgb(1.0, 0.0, 128.0 / 255.0)));
        assert_eq!(Rgb::hex("#000000"), Some(Rgb(0.0, 0.0, 0.0)));
        assert_eq!(Rgb::hex("fff"), None);
        assert_eq!(Rgb::hex("gg0000"), None);
    }
}
