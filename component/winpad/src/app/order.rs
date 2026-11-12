//! Super+Tab on the screen: the focus goes to the window the walk names.

use super::App;
use std::time::Instant;

impl App {
    /// Super+Tab: the window before, along the walk.
    pub fn back(&mut self) {
        if let Some(id) = self.history.back(Instant::now()) {
            let _ = self.ipc.run(&format!("[con_id={id}] focus"));
        }
    }

    pub fn settle(&mut self) {
        self.history.settle(Instant::now());
    }
}
