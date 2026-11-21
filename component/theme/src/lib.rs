//! The theme values shared by spark-shell's native components. The shell selects and applies looks.
//! The renderers consume these colors and glyphs in their own units.

pub mod animation;
pub mod glyphs;
pub mod palette;

/// A red, green and blue channel in display order.
pub type Rgb = [u8; 3];

/// Exactly six ASCII hex digits, as used in provider messages.
pub fn hex_digits(s: &str) -> Option<Rgb> {
    if s.len() != 6 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let [_, r, g, b] = u32::from_str_radix(s, 16).ok()?.to_be_bytes();
    Some([r, g, b])
}

/// The launcher's color spelling. Older native readers accept surrounding space and leading hash signs.
pub fn hex(s: &str) -> Option<Rgb> {
    hex_digits(s.trim().trim_start_matches('#'))
}

/// Whether the ground is below half brightness, as spark-shell's theme_is_dark computes it.
pub fn dark_ground(r: u8, g: u8, b: u8) -> bool {
    u32::from(r) * 299 + u32::from(g) * 587 + u32::from(b) * 114 < 128_000
}

/// spark-shell's hex_mix uses signed integer division, truncating the change toward zero.
fn mix(a: Rgb, b: Rgb, percent: i32) -> Rgb {
    std::array::from_fn(|i| {
        let x = i32::from(a[i]);
        (x + (i32::from(b[i]) - x) * percent / 100) as u8
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_digits_and_launcher_colors_keep_their_own_input_rules() {
        let color = Some([0xab, 0xcd, 0xef]);
        assert_eq!(hex_digits("AbCdEf"), color);
        for launcher in ["#AbCdEf", "  AbCdEf  ", " ##AbCdEf\n"] {
            assert_eq!(hex(launcher), color);
            assert_eq!(hex_digits(launcher), None);
        }
        for invalid in ["", "abc", "+12345", "fffffg", "12345678", "12345\u{e9}"] {
            assert_eq!(hex(invalid), None);
        }
    }
}
