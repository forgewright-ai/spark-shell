//! The buttons' side on the screen: a clear surface a screen that takes the pointer on the buttons sway draws,
//! and the word to sway on how each window's are drawn.

use super::{spawn, App, Deco, BTN_LEFT, NAMESPACE};
use crate::buttons::{self, Glyph};
use smithay_client_toolkit::compositor::Region;
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::Shape as Cursor;
use smithay_client_toolkit::seat::pointer::PointerEventKind;
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer};
use smithay_client_toolkit::shell::WaylandSurface;
use wayland_client::protocol::wl_shm;
use wayland_client::protocol::wl_surface::WlSurface;

impl App {
    /// Every band carries the mic where something can hear: the voice is a window's, like its buttons, and
    /// the window makes of the words what it will.
    fn with_mic(&self, _b: &crate::buttons::Band) -> bool {
        self.cfg.titles.voice
    }

    pub(super) fn is_term(&self, app: &str) -> bool {
        let t = &self.cfg.titles;
        (!t.term.is_empty() && app == t.term) || (!t.term_also.is_empty() && app.starts_with(&t.term_also))
    }

    pub(super) fn apply_deco(&mut self, oi: usize) {
        if self.outs[oi].deco.is_some() {
            return;
        }
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self
            .layer_shell
            .create_layer_surface(&self.qh, surface, Layer::Top, Some(NAMESPACE), Some(&self.outs[oi].output));
        layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
        layer.set_size(0, 0);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        if let Ok(region) = Region::new(&self.compositor) {
            layer.wl_surface().set_input_region(Some(region.wl_region()));
        }
        layer.commit();
        self.outs[oi].deco = Some(Deco {
            layer,
            size: (0, 0),
            configured: false,
        });
    }

    pub fn draw_decos(&mut self) {
        self.deco_dirty = false;
        for oi in 0..self.outs.len() {
            self.draw_deco(oi);
        }
    }

    /// The pointer's cells over the glyphs sway draws at the start of each title. Nothing is drawn here: the
    /// surface is clear, so the glyphs are sway's own pixels and move with their window.
    fn draw_deco(&mut self, oi: usize) {
        let Some(d) = self.outs[oi].deco.as_ref() else { return };
        if !d.configured || d.size.0 <= 0 || d.size.1 <= 0 {
            return;
        }
        let (size, scale) = (d.size, self.outs[oi].scale.max(1));
        let name = self.outs[oi].name.clone();
        let (bw, bh) = (size.0 * scale, size.1 * scale);
        let Ok((buffer, data)) = self.pool.create_buffer(bw, bh, bw * 4, wl_shm::Format::Argb8888) else {
            eprintln!("spark-winpad: no shared memory for a frame");
            return;
        };
        let Ok(region) = Region::new(&self.compositor) else { return };
        data.fill(0);
        for b in self.bands.iter().filter(|b| b.output == name) {
            let cells = buttons::glyph_cells(b.rect, self.cell);
            let last = if self.with_mic(b) { 3 } else { 2 };
            region.add(cells[0].x, cells[0].y, cells[last].x + cells[last].w - cells[0].x, cells[0].h);
        }
        let d = self.outs[oi].deco.as_ref().unwrap();
        let surface = d.layer.wl_surface().clone();
        surface.set_input_region(Some(region.wl_region()));
        surface.set_buffer_scale(scale);
        if buffer.attach_to(&surface).is_ok() {
            surface.damage_buffer(0, 0, bw, bh);
            d.layer.commit();
        }
    }

    pub(super) fn deco_of(&self, surface: &WlSurface) -> Option<usize> {
        self.outs.iter().position(|o| o.deco.as_ref().is_some_and(|d| d.layer.wl_surface() == surface))
    }

    /// The glyph under a point on a screen's glyph surface, and its window.
    fn glyph_at(&self, oi: usize, pos: (f64, f64)) -> Option<(i64, Glyph)> {
        let name = &self.outs[oi].name;
        self.bands
            .iter()
            .filter(|b| &b.output == name)
            .find_map(|b| buttons::glyph_at(b.rect, self.cell, pos.0, pos.1, self.with_mic(b)).map(|g| (b.id, g)))
    }

    /// The pointer on a glyph surface: the hand over a glyph; a press and a release on the same glyph act.
    pub(super) fn deco_pointer(&mut self, oi: usize, kind: &PointerEventKind, pos: (f64, f64)) {
        match kind {
            PointerEventKind::Enter { serial } => {
                if let Some(p) = self.pointer.as_mut() {
                    p.serial = *serial;
                    p.cursor = None;
                }
                self.deco_over(oi, pos);
            }
            PointerEventKind::Motion { .. } => self.deco_over(oi, pos),
            PointerEventKind::Press { button: BTN_LEFT, .. } => self.deco_press = self.glyph_at(oi, pos),
            PointerEventKind::Release { button: BTN_LEFT, .. } => {
                let pressed = self.deco_press.take();
                if let Some((id, glyph)) = self.glyph_at(oi, pos).filter(|h| Some(*h) == pressed) {
                    match glyph {
                        Glyph::Close => {
                            let _ = self.ipc.run(&format!("[con_id={id}] kill"));
                        }
                        Glyph::Min => spawn(&self.cfg.spark_shell, &["desktop", "window", "min", &id.to_string()]),
                        Glyph::Fill => spawn(&self.cfg.spark_shell, &["desktop", "window", "toggle", &id.to_string()]),
                        Glyph::Mic => spawn(&self.cfg.spark_shell, &["desktop", "voice", "toggle"]),
                    }
                }
            }
            PointerEventKind::Leave { .. } => {
                self.deco_press = None;
                if self.deco_hover.take().is_some() {
                    self.title_sync();
                }
            }
            _ => {}
        }
    }

    /// The pointer over a button: the hand, and the button lit.
    fn deco_over(&mut self, oi: usize, pos: (f64, f64)) {
        let over = self.glyph_at(oi, pos);
        self.set_cursor(if over.is_some() { Cursor::Pointer } else { Cursor::Default });
        if over != self.deco_hover {
            self.deco_hover = over;
            self.title_sync();
        }
    }

    /// Each band in sight wears the title its state asks for, drawn by sway: the buttons, the window's name
    /// cut to its room, and the meter's cells at the right end. sway is told only when that title changed.
    pub(super) fn title_sync(&mut self) {
        let t = &self.cfg.titles;
        let mut todo = vec![];
        for b in &self.bands {
            let hover = self.deco_hover.filter(|h| h.0 == b.id).map(|h| h.1);
            let mic = self.with_mic(b).then_some(&self.voice);
            let around = if self.is_term(&b.app) { &t.term_title } else { &t.title };
            let line = buttons::title(
                buttons::room(b.rect, self.cell),
                &buttons::buttons(b.focused, hover, &t.colors, &t.ground, mic),
                around,
                &b.name,
                &buttons::meter(mic),
            );
            if self.sent.get(&b.id) != Some(&line) {
                todo.push((b.id, format!("[con_id={}] title_format \"{line}\"", b.id), line));
            }
        }
        for (id, command, line) in todo {
            if self.ipc.run(&command).is_ok() {
                self.sent.insert(id, line);
            }
        }
    }
}
