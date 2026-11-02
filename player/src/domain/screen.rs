//! A screen as the player sees it: sway's name for it, its size in
//! pixels and its scale.

/// A width and a height, in pixels or in the compositor's logical units.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Size {
    pub width: u32,
    pub height: u32,
}

impl Size {
    pub fn new(width: u32, height: u32) -> Size {
        Size { width, height }
    }

    /// True when there is nothing to draw on.
    pub fn is_empty(self) -> bool {
        self.width == 0 || self.height == 0
    }
}

/// A screen with a background surface: its name (DP-3, HDMI-A-1), its size
/// in pixels and the scale that size was reached by.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Screen {
    pub name: String,
    pub size: Size,
    pub scale: u32,
}

impl Screen {
    /// The screen from the compositor's logical size and the output's
    /// scale; a scale below 1 counts as 1.
    pub fn new(name: impl Into<String>, logical: Size, scale: u32) -> Screen {
        let scale = scale.max(1);
        let size = Size::new(logical.width.saturating_mul(scale), logical.height.saturating_mul(scale));
        Screen {
            name: name.into(),
            size,
            scale,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_size_in_pixels_is_the_logical_size_times_the_scale() {
        let screen = Screen::new("DP-3", Size::new(1280, 720), 2);
        assert_eq!(screen.size, Size::new(2560, 1440));
        assert_eq!(screen.scale, 2);
        assert_eq!(screen.name, "DP-3");
    }

    #[test]
    fn a_scale_below_one_counts_as_one() {
        let screen = Screen::new("HDMI-A-1", Size::new(1920, 1080), 0);
        assert_eq!(screen.size, Size::new(1920, 1080));
        assert_eq!(screen.scale, 1);
    }

    #[test]
    fn a_huge_size_saturates_instead_of_wrapping() {
        let screen = Screen::new("X", Size::new(u32::MAX, 1), 3);
        assert_eq!(screen.size, Size::new(u32::MAX, 3));
    }

    #[test]
    fn a_size_with_a_zero_side_is_empty() {
        assert!(Size::new(0, 1080).is_empty());
        assert!(Size::new(1920, 0).is_empty());
        assert!(!Size::new(1, 1).is_empty());
    }
}
