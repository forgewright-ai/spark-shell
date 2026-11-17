//! The grid's drawing steps (draw.rs) painted with cairo and pango, the libraries spark-bar and spark-winpad
//! draw with: opened at run time by their sonames, so the binary needs no -devel package and runs on each
//! family's own. Only the functions used are typed, each under its name in cairo.h, pango-layout.h and
//! pangocairo.h.

use crate::draw::{Cell, Rgb, Step};
use libloading::Library;
use std::ffi::{c_char, c_int, c_void, CString};

#[repr(C)]
struct CairoSurface {
    _opaque: [u8; 0],
}
#[repr(C)]
struct Cairo {
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
const PANGO_WEIGHT_BOLD: c_int = 700;

/// The functions of libcairo.so.2, libpango-1.0.so.0, libpangocairo-1.0.so.0 and libgobject-2.0.so.0. The four
/// stay open for the life of the process: GLib registers its types once and cannot be closed under them.
pub struct Lib {
    image_surface_create: unsafe extern "C" fn(c_int, c_int, c_int) -> *mut CairoSurface,
    image_surface_create_for_data: unsafe extern "C" fn(*mut u8, c_int, c_int, c_int, c_int) -> *mut CairoSurface,
    surface_status: unsafe extern "C" fn(*mut CairoSurface) -> c_int,
    surface_destroy: unsafe extern "C" fn(*mut CairoSurface),
    surface_flush: unsafe extern "C" fn(*mut CairoSurface),
    surface_write_to_png: unsafe extern "C" fn(*mut CairoSurface, *const c_char) -> c_int,
    create: unsafe extern "C" fn(*mut CairoSurface) -> *mut Cairo,
    destroy: unsafe extern "C" fn(*mut Cairo),
    scale: unsafe extern "C" fn(*mut Cairo, f64, f64),
    set_source_rgba: unsafe extern "C" fn(*mut Cairo, f64, f64, f64, f64),
    rectangle: unsafe extern "C" fn(*mut Cairo, f64, f64, f64, f64),
    fill: unsafe extern "C" fn(*mut Cairo),
    move_to: unsafe extern "C" fn(*mut Cairo, f64, f64),
    save: unsafe extern "C" fn(*mut Cairo),
    restore: unsafe extern "C" fn(*mut Cairo),
    translate: unsafe extern "C" fn(*mut Cairo, f64, f64),
    set_source_surface: unsafe extern "C" fn(*mut Cairo, *mut CairoSurface, f64, f64),
    paint: unsafe extern "C" fn(*mut Cairo),
    font_description_from_string: unsafe extern "C" fn(*const c_char) -> *mut FontDesc,
    font_description_free: unsafe extern "C" fn(*mut FontDesc),
    font_description_set_weight: unsafe extern "C" fn(*mut FontDesc, c_int),
    layout_set_font_description: unsafe extern "C" fn(*mut PangoLayout, *mut FontDesc),
    layout_set_text: unsafe extern "C" fn(*mut PangoLayout, *const c_char, c_int),
    layout_get_pixel_size: unsafe extern "C" fn(*mut PangoLayout, *mut c_int, *mut c_int),
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
        let cairo = open("libcairo.so.2", "cairo, which draws the bar too")?;
        let pango = open("libpango-1.0.so.0", "pango, which sets the bar's text")?;
        let pc = open("libpangocairo-1.0.so.0", "pango's cairo half")?;
        let gobject = open("libgobject-2.0.so.0", "GLib's objects")?;
        let (c, p, q, g) = ("libcairo.so.2", "libpango-1.0.so.0", "libpangocairo-1.0.so.0", "libgobject-2.0.so.0");
        let lib = Lib {
            image_surface_create: sym!(cairo, c, "cairo_image_surface_create"),
            image_surface_create_for_data: sym!(cairo, c, "cairo_image_surface_create_for_data"),
            surface_status: sym!(cairo, c, "cairo_surface_status"),
            surface_destroy: sym!(cairo, c, "cairo_surface_destroy"),
            surface_flush: sym!(cairo, c, "cairo_surface_flush"),
            surface_write_to_png: sym!(cairo, c, "cairo_surface_write_to_png"),
            create: sym!(cairo, c, "cairo_create"),
            destroy: sym!(cairo, c, "cairo_destroy"),
            scale: sym!(cairo, c, "cairo_scale"),
            set_source_rgba: sym!(cairo, c, "cairo_set_source_rgba"),
            rectangle: sym!(cairo, c, "cairo_rectangle"),
            fill: sym!(cairo, c, "cairo_fill"),
            move_to: sym!(cairo, c, "cairo_move_to"),
            save: sym!(cairo, c, "cairo_save"),
            restore: sym!(cairo, c, "cairo_restore"),
            translate: sym!(cairo, c, "cairo_translate"),
            set_source_surface: sym!(cairo, c, "cairo_set_source_surface"),
            paint: sym!(cairo, c, "cairo_paint"),
            font_description_from_string: sym!(pango, p, "pango_font_description_from_string"),
            font_description_free: sym!(pango, p, "pango_font_description_free"),
            font_description_set_weight: sym!(pango, p, "pango_font_description_set_weight"),
            layout_set_font_description: sym!(pango, p, "pango_layout_set_font_description"),
            layout_set_text: sym!(pango, p, "pango_layout_set_text"),
            layout_get_pixel_size: sym!(pango, p, "pango_layout_get_pixel_size"),
            cairo_create_layout: sym!(pc, q, "pango_cairo_create_layout"),
            cairo_show_layout: sym!(pc, q, "pango_cairo_show_layout"),
            object_unref: sym!(gobject, g, "g_object_unref"),
        };
        // never closed: a closed GLib takes the process down when its own cleanup runs at the end
        for open in [cairo, pango, pc, gobject] {
            std::mem::forget(open);
        }
        Ok(lib)
    }
}

/// The text's face, regular and bold, and the cell it makes: every symbol stands in a cell as wide as one of
/// its letters and as tall as one of its lines.
pub struct Font {
    regular: *mut FontDesc,
    bold: *mut FontDesc,
    pub cell: Cell,
}

impl Font {
    /// A face by pango's own words for one ("Monaspace Neon 12"); its cell measured once. None when no cell comes
    /// of it.
    pub fn new(lib: &Lib, spec: &str) -> Option<Font> {
        let spec = CString::new(spec.replace('\0', "")).ok()?;
        unsafe {
            let regular = (lib.font_description_from_string)(spec.as_ptr());
            let bold = (lib.font_description_from_string)(spec.as_ptr());
            (lib.font_description_set_weight)(bold, PANGO_WEIGHT_BOLD);
            let font = Font {
                regular,
                bold,
                cell: Cell { w: 0.0, h: 0.0 },
            };
            let surface = (lib.image_surface_create)(CAIRO_FORMAT_ARGB32, 1, 1);
            let cr = (lib.create)(surface);
            let l = (lib.cairo_create_layout)(cr);
            (lib.layout_set_font_description)(l, regular);
            (lib.layout_set_text)(l, c"M".as_ptr(), -1);
            let (mut w, mut h) = (0, 0);
            (lib.layout_get_pixel_size)(l, &mut w, &mut h);
            (lib.object_unref)(l as *mut c_void);
            (lib.destroy)(cr);
            (lib.surface_destroy)(surface);
            if w <= 0 || h <= 0 {
                font.free(lib);
                return None;
            }
            Some(Font {
                cell: Cell { w: w as f64, h: h as f64 },
                ..font
            })
        }
    }

    pub fn free(&self, lib: &Lib) {
        unsafe {
            (lib.font_description_free)(self.regular);
            (lib.font_description_free)(self.bold);
        }
    }
}

fn channel(v: u8) -> f64 {
    v as f64 / 255.0
}

/// The steps drawn on a cairo surface, in logical pixels at a scale.
unsafe fn run(lib: &Lib, font: &Font, surface: *mut CairoSurface, scale: f64, steps: &[Step]) {
    let cr = (lib.create)(surface);
    (lib.scale)(cr, scale, scale);
    let layout = (lib.cairo_create_layout)(cr);
    let ink = |c: Rgb| (lib.set_source_rgba)(cr, channel(c[0]), channel(c[1]), channel(c[2]), 1.0);
    for step in steps {
        match step {
            Step::Fill { x, y, w, h, color } => {
                ink(*color);
                (lib.rectangle)(cr, *x, *y, *w, *h);
                (lib.fill)(cr);
            }
            Step::Under { x, y, w, color } => {
                ink(*color);
                (lib.rectangle)(cr, *x, *y, *w, 1.0);
                (lib.fill)(cr);
            }
            Step::Symbol { x, y, text, color, bold, .. } => {
                let Ok(t) = CString::new(text.replace('\0', "")) else { continue };
                (lib.layout_set_font_description)(layout, if *bold { font.bold } else { font.regular });
                (lib.layout_set_text)(layout, t.as_ptr(), -1);
                ink(*color);
                (lib.move_to)(cr, *x, *y);
                (lib.cairo_show_layout)(cr, layout);
            }
            Step::Picture { x, y, scale, pic } => {
                let (w, h) = (pic.w as c_int, pic.h as c_int);
                if w <= 0 || h <= 0 || pic.data.len() < (w as usize) * (h as usize) * 4 || *scale <= 0.0 {
                    continue;
                }
                // cairo reads the pixels and writes none: the picture is the source, never the target
                let source = (lib.image_surface_create_for_data)(pic.data.as_ptr() as *mut u8, CAIRO_FORMAT_ARGB32, w, h, w * 4);
                if !source.is_null() && (lib.surface_status)(source) == 0 {
                    (lib.save)(cr);
                    (lib.translate)(cr, *x, *y);
                    (lib.scale)(cr, 1.0 / *scale, 1.0 / *scale);
                    (lib.set_source_surface)(cr, source, 0.0, 0.0);
                    (lib.paint)(cr);
                    // the source let go before its pixels are
                    (lib.restore)(cr);
                }
                if !source.is_null() {
                    (lib.surface_destroy)(source);
                }
            }
        }
    }
    (lib.object_unref)(layout as *mut c_void);
    (lib.surface_flush)(surface);
    (lib.destroy)(cr);
}

/// Pixels to paint into, in shared memory (ARGB, as wl_shm's Argb8888): `w` by `h` device pixels, `stride` bytes
/// a row, drawn in logical pixels at `scale`.
pub struct Pixels<'a> {
    pub data: &'a mut [u8],
    pub w: i32,
    pub h: i32,
    pub stride: i32,
    pub scale: f64,
}

/// The steps painted into pixels. False when cairo takes no such surface.
pub fn paint(lib: &Lib, font: &Font, px: Pixels, steps: &[Step]) -> bool {
    if px.w <= 0 || px.h <= 0 || px.data.len() < (px.stride * px.h) as usize {
        return false;
    }
    unsafe {
        let surface = (lib.image_surface_create_for_data)(px.data.as_mut_ptr(), CAIRO_FORMAT_ARGB32, px.w, px.h, px.stride);
        if surface.is_null() || (lib.surface_status)(surface) != 0 {
            return false;
        }
        run(lib, font, surface, px.scale, steps);
        (lib.surface_destroy)(surface);
    }
    true
}

/// The steps painted into a picture file, `w` by `h` pixels: what a test or a review looks at.
pub fn png(lib: &Lib, font: &Font, w: i32, h: i32, steps: &[Step], path: &str) -> bool {
    let Ok(p) = CString::new(path) else { return false };
    unsafe {
        let surface = (lib.image_surface_create)(CAIRO_FORMAT_ARGB32, w, h);
        if surface.is_null() || (lib.surface_status)(surface) != 0 {
            return false;
        }
        run(lib, font, surface, 1.0, steps);
        let ok = (lib.surface_write_to_png)(surface, p.as_ptr()) == 0;
        (lib.surface_destroy)(surface);
        ok
    }
}
