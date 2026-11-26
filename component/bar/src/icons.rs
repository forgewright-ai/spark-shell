//! The bar's icons, each drawn in a box of 16: written by component/bar/icons.py from its drawings, never by
//! hand. A shape is a path, filled or stroked with flat ends and sharp corners; its ink is the part's tone,
//! the tone faint (a wifi band the signal does not reach), or none: a hole cut in what is under it.

/// The side of the box the icons are drawn in.
pub const BOX: f64 = 16.0;
/// How far a stroke's corner may reach before it is cut flat, in widths.
pub const MITER: f64 = 6.0;

/// A step of a path: move, line, curve, close.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Seg {
    M(f64, f64),
    L(f64, f64),
    C(f64, f64, f64, f64, f64, f64),
    Z,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ink {
    On,
    Faint,
    Off,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shape {
    pub ink: Ink,
    /// How wide the path is stroked; 0 for a filled one.
    pub stroke: f64,
    pub path: &'static [Seg],
}

/// Every drawing's name: an icon, or an icon and its form.
pub const NAMES: [&str; 43] = [
    "lan",
    "bt",
    "bt-idle",
    "bt-off",
    "wifi",
    "wifi-fair",
    "wifi-weak",
    "wifi-off",
    "out",
    "out-muted",
    "mic",
    "mic-muted",
    "media",
    "media-paused",
    "light",
    "kb",
    "battery-full",
    "battery-half",
    "battery-low",
    "battery-charging",
    "plane",
    "flag",
    "flag-none",
    "quiet",
    "due",
    "calendar",
    "stopwatch",
    "check",
    "pulse",
    "key",
    "vpn",
    "vpn-off",
    "lock",
    "drive",
    "update",
    "pad",
    "more",
    "power",
    "display",
    "printer",
    "phones",
    "caps",
    "night",
];

/// A drawing by its name; none for a name the bar does not know.
pub fn shapes(name: &str) -> Option<&'static [Shape]> {
    Some(match name {
        "lan" => LAN,
        "bt" => BT,
        "bt-idle" => BT_IDLE,
        "bt-off" => BT_OFF,
        "wifi" => WIFI,
        "wifi-fair" => WIFI_FAIR,
        "wifi-weak" => WIFI_WEAK,
        "wifi-off" => WIFI_OFF,
        "out" => OUT,
        "out-muted" => OUT_MUTED,
        "mic" => MIC,
        "mic-muted" => MIC_MUTED,
        "media" => MEDIA,
        "media-paused" => MEDIA_PAUSED,
        "light" => LIGHT,
        "kb" => KB,
        "battery-full" => BATTERY_FULL,
        "battery-half" => BATTERY_HALF,
        "battery-low" => BATTERY_LOW,
        "battery-charging" => BATTERY_CHARGING,
        "plane" => PLANE,
        "flag" => FLAG,
        "flag-none" => FLAG_NONE,
        "quiet" => QUIET,
        "due" => DUE,
        "calendar" => CALENDAR,
        "stopwatch" => STOPWATCH,
        "check" => CHECK,
        "pulse" => PULSE,
        "key" => KEY,
        "vpn" => VPN,
        "vpn-off" => VPN_OFF,
        "lock" => LOCK,
        "drive" => DRIVE,
        "update" => UPDATE,
        "pad" => PAD,
        "more" => MORE,
        "power" => POWER,
        "display" => DISPLAY,
        "printer" => PRINTER,
        "phones" => PHONES,
        "caps" => CAPS,
        "night" => NIGHT,
        _ => return None,
    })
}

#[rustfmt::skip]
const LAN: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(1.9, 5.6), Seg::L(4.5, 3.0), Seg::L(7.1, 5.6)] },
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(4.5, 3.6), Seg::L(4.5, 13.8)] },
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(8.9, 10.4), Seg::L(11.5, 13.0), Seg::L(14.1, 10.4)] },
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(11.5, 2.2), Seg::L(11.5, 12.4)] },
];

#[rustfmt::skip]
const BT: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.9, path: &[Seg::M(4.6, 4.8), Seg::L(11.4, 11.2), Seg::L(8.0, 14.6), Seg::L(8.0, 1.4), Seg::L(11.4, 4.8), Seg::L(4.6, 11.2)] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(1.7, 6.5), Seg::L(3.2, 8.0), Seg::L(1.7, 9.5), Seg::L(0.2, 8.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(14.3, 6.5), Seg::L(15.8, 8.0), Seg::L(14.3, 9.5), Seg::L(12.8, 8.0), Seg::Z] },
];

#[rustfmt::skip]
const BT_IDLE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.9, path: &[Seg::M(4.6, 4.8), Seg::L(11.4, 11.2), Seg::L(8.0, 14.6), Seg::L(8.0, 1.4), Seg::L(11.4, 4.8), Seg::L(4.6, 11.2)] },
];

#[rustfmt::skip]
const BT_OFF: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.1, path: &[Seg::M(4.6, 4.8), Seg::L(11.4, 11.2), Seg::L(8.0, 14.6), Seg::L(8.0, 1.4), Seg::L(11.4, 4.8), Seg::L(4.6, 11.2)] },
];

#[rustfmt::skip]
const WIFI: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(-0.627, 5.973), Seg::C(1.661, 3.685, 4.764, 2.399, 8.0, 2.399), Seg::C(11.236, 2.399, 14.339, 3.685, 16.627, 5.973), Seg::L(14.505, 8.095), Seg::C(10.912, 4.503, 5.088, 4.503, 1.495, 8.095), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.626, 9.226), Seg::C(5.594, 6.258, 10.406, 6.258, 13.374, 9.226), Seg::L(11.253, 11.347), Seg::C(10.39, 10.484, 9.22, 9.999, 8.0, 9.999), Seg::C(6.78, 9.999, 5.61, 10.484, 4.747, 11.347), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 14.6), Seg::L(5.737, 12.337), Seg::C(6.337, 11.737, 7.151, 11.399, 8.0, 11.399), Seg::C(8.849, 11.399, 9.663, 11.737, 10.263, 12.337), Seg::Z] },
];

#[rustfmt::skip]
const WIFI_FAIR: &[Shape] = &[
    Shape { ink: Ink::Faint, stroke: 0.0, path: &[Seg::M(-0.627, 5.973), Seg::C(1.661, 3.685, 4.764, 2.399, 8.0, 2.399), Seg::C(11.236, 2.399, 14.339, 3.685, 16.627, 5.973), Seg::L(14.505, 8.095), Seg::C(10.912, 4.503, 5.088, 4.503, 1.495, 8.095), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.626, 9.226), Seg::C(5.594, 6.258, 10.406, 6.258, 13.374, 9.226), Seg::L(11.253, 11.347), Seg::C(10.39, 10.484, 9.22, 9.999, 8.0, 9.999), Seg::C(6.78, 9.999, 5.61, 10.484, 4.747, 11.347), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 14.6), Seg::L(5.737, 12.337), Seg::C(6.337, 11.737, 7.151, 11.399, 8.0, 11.399), Seg::C(8.849, 11.399, 9.663, 11.737, 10.263, 12.337), Seg::Z] },
];

#[rustfmt::skip]
const WIFI_WEAK: &[Shape] = &[
    Shape { ink: Ink::Faint, stroke: 0.0, path: &[Seg::M(-0.627, 5.973), Seg::C(1.661, 3.685, 4.764, 2.399, 8.0, 2.399), Seg::C(11.236, 2.399, 14.339, 3.685, 16.627, 5.973), Seg::L(14.505, 8.095), Seg::C(10.912, 4.503, 5.088, 4.503, 1.495, 8.095), Seg::Z] },
    Shape { ink: Ink::Faint, stroke: 0.0, path: &[Seg::M(2.626, 9.226), Seg::C(5.594, 6.258, 10.406, 6.258, 13.374, 9.226), Seg::L(11.253, 11.347), Seg::C(10.39, 10.484, 9.22, 9.999, 8.0, 9.999), Seg::C(6.78, 9.999, 5.61, 10.484, 4.747, 11.347), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 14.6), Seg::L(5.737, 12.337), Seg::C(6.337, 11.737, 7.151, 11.399, 8.0, 11.399), Seg::C(8.849, 11.399, 9.663, 11.737, 10.263, 12.337), Seg::Z] },
];

#[rustfmt::skip]
const WIFI_OFF: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(-0.627, 5.973), Seg::C(1.661, 3.685, 4.764, 2.399, 8.0, 2.399), Seg::C(11.236, 2.399, 14.339, 3.685, 16.627, 5.973), Seg::L(14.505, 8.095), Seg::C(10.912, 4.503, 5.088, 4.503, 1.495, 8.095), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.626, 9.226), Seg::C(5.594, 6.258, 10.406, 6.258, 13.374, 9.226), Seg::L(11.253, 11.347), Seg::C(10.39, 10.484, 9.22, 9.999, 8.0, 9.999), Seg::C(6.78, 9.999, 5.61, 10.484, 4.747, 11.347), Seg::Z] },
    Shape { ink: Ink::On, stroke: 1.1, path: &[Seg::M(8.0, 14.0), Seg::L(6.162, 12.162), Seg::C(7.177, 11.147, 8.823, 11.147, 9.838, 12.162), Seg::Z] },
];

#[rustfmt::skip]
const OUT: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(1.6, 5.6), Seg::L(4.8, 5.6), Seg::L(9.2, 2.0), Seg::L(9.2, 14.0), Seg::L(4.8, 10.4), Seg::L(1.6, 10.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(11.0, 3.4), Seg::L(15.6, 8.0), Seg::L(11.0, 12.6), Seg::L(11.0, 10.0), Seg::L(13.0, 8.0), Seg::L(11.0, 6.0), Seg::Z] },
];

#[rustfmt::skip]
const OUT_MUTED: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(2.4, 6.2), Seg::L(5.0, 6.2), Seg::L(8.6, 3.2), Seg::L(8.6, 12.8), Seg::L(5.0, 9.8), Seg::L(2.4, 9.8), Seg::Z] },
];

#[rustfmt::skip]
const MIC: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 0.8), Seg::L(8.0, 0.8), Seg::C(9.712, 0.8, 11.1, 2.188, 11.1, 3.9), Seg::L(11.1, 7.5), Seg::C(11.1, 9.212, 9.712, 10.6, 8.0, 10.6), Seg::L(8.0, 10.6), Seg::C(6.288, 10.6, 4.9, 9.212, 4.9, 7.5), Seg::L(4.9, 3.9), Seg::C(4.9, 2.188, 6.288, 0.8, 8.0, 0.8), Seg::Z] },
    Shape { ink: Ink::On, stroke: 1.8, path: &[Seg::M(2.4, 7.6), Seg::L(2.4, 8.6), Seg::C(2.4, 11.693, 4.907, 14.2, 8.0, 14.2), Seg::C(11.093, 14.2, 13.6, 11.693, 13.6, 8.6), Seg::L(13.6, 7.6)] },
    Shape { ink: Ink::On, stroke: 1.8, path: &[Seg::M(8.0, 14.2), Seg::L(8.0, 16.0)] },
];

#[rustfmt::skip]
const MIC_MUTED: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(8.0, 1.55), Seg::L(8.0, 1.55), Seg::C(9.298, 1.55, 10.35, 2.602, 10.35, 3.9), Seg::L(10.35, 7.5), Seg::C(10.35, 8.798, 9.298, 9.85, 8.0, 9.85), Seg::L(8.0, 9.85), Seg::C(6.702, 9.85, 5.65, 8.798, 5.65, 7.5), Seg::L(5.65, 3.9), Seg::C(5.65, 2.602, 6.702, 1.55, 8.0, 1.55), Seg::Z] },
    Shape { ink: Ink::On, stroke: 1.8, path: &[Seg::M(2.4, 7.6), Seg::L(2.4, 8.6), Seg::C(2.4, 11.693, 4.907, 14.2, 8.0, 14.2), Seg::C(11.093, 14.2, 13.6, 11.693, 13.6, 8.6), Seg::L(13.6, 7.6)] },
    Shape { ink: Ink::On, stroke: 1.8, path: &[Seg::M(8.0, 14.2), Seg::L(8.0, 16.0)] },
];

#[rustfmt::skip]
const MEDIA: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(3.4, 1.8), Seg::L(14.2, 8.0), Seg::L(3.4, 14.2), Seg::Z] },
];

#[rustfmt::skip]
const MEDIA_PAUSED: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(4.4, 3.4), Seg::L(12.4, 8.0), Seg::L(4.4, 12.6), Seg::Z] },
];

#[rustfmt::skip]
const LIGHT: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(5.1, 8.0), Seg::C(5.1, 6.398, 6.398, 5.1, 8.0, 5.1), Seg::C(9.602, 5.1, 10.9, 6.398, 10.9, 8.0), Seg::C(10.9, 9.602, 9.602, 10.9, 8.0, 10.9), Seg::C(6.398, 10.9, 5.1, 9.602, 5.1, 8.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(12.7, 8.0), Seg::L(15.2, 8.0)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(11.182, 11.182), Seg::L(12.667, 12.667)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(8.0, 12.7), Seg::L(8.0, 15.2)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(4.818, 11.182), Seg::L(3.333, 12.667)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(3.3, 8.0), Seg::L(0.8, 8.0)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(4.818, 4.818), Seg::L(3.333, 3.333)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(8.0, 3.3), Seg::L(8.0, 0.8)] },
    Shape { ink: Ink::On, stroke: 1.7, path: &[Seg::M(11.182, 4.818), Seg::L(12.667, 3.333)] },
];

#[rustfmt::skip]
const KB: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.8, 3.6), Seg::L(13.2, 3.6), Seg::C(14.194, 3.6, 15.0, 4.406, 15.0, 5.4), Seg::L(15.0, 10.6), Seg::C(15.0, 11.594, 14.194, 12.4, 13.2, 12.4), Seg::L(2.8, 12.4), Seg::C(1.806, 12.4, 1.0, 11.594, 1.0, 10.6), Seg::L(1.0, 5.4), Seg::C(1.0, 4.406, 1.806, 3.6, 2.8, 3.6), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(2.9, 5.4), Seg::L(4.5, 5.4), Seg::L(4.5, 7.0), Seg::L(2.9, 7.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(5.77, 5.4), Seg::L(7.37, 5.4), Seg::L(7.37, 7.0), Seg::L(5.77, 7.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(8.63, 5.4), Seg::L(10.23, 5.4), Seg::L(10.23, 7.0), Seg::L(8.63, 7.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(11.5, 5.4), Seg::L(13.1, 5.4), Seg::L(13.1, 7.0), Seg::L(11.5, 7.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(4.6, 8.8), Seg::L(11.4, 8.8), Seg::L(11.4, 10.4), Seg::L(4.6, 10.4), Seg::Z] },
];

#[rustfmt::skip]
const BATTERY_FULL: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(2.6, 4.6), Seg::L(11.8, 4.6), Seg::C(12.684, 4.6, 13.4, 5.316, 13.4, 6.2), Seg::L(13.4, 9.8), Seg::C(13.4, 10.684, 12.684, 11.4, 11.8, 11.4), Seg::L(2.6, 11.4), Seg::C(1.716, 11.4, 1.0, 10.684, 1.0, 9.8), Seg::L(1.0, 6.2), Seg::C(1.0, 5.316, 1.716, 4.6, 2.6, 4.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(14.0, 6.6), Seg::L(15.4, 6.6), Seg::L(15.4, 9.4), Seg::L(14.0, 9.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.7, 6.3), Seg::L(11.7, 6.3), Seg::L(11.7, 9.7), Seg::L(2.7, 9.7), Seg::Z] },
];

#[rustfmt::skip]
const BATTERY_HALF: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(2.6, 4.6), Seg::L(11.8, 4.6), Seg::C(12.684, 4.6, 13.4, 5.316, 13.4, 6.2), Seg::L(13.4, 9.8), Seg::C(13.4, 10.684, 12.684, 11.4, 11.8, 11.4), Seg::L(2.6, 11.4), Seg::C(1.716, 11.4, 1.0, 10.684, 1.0, 9.8), Seg::L(1.0, 6.2), Seg::C(1.0, 5.316, 1.716, 4.6, 2.6, 4.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(14.0, 6.6), Seg::L(15.4, 6.6), Seg::L(15.4, 9.4), Seg::L(14.0, 9.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.7, 6.3), Seg::L(7.2, 6.3), Seg::L(7.2, 9.7), Seg::L(2.7, 9.7), Seg::Z] },
];

#[rustfmt::skip]
const BATTERY_LOW: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(2.6, 4.6), Seg::L(11.8, 4.6), Seg::C(12.684, 4.6, 13.4, 5.316, 13.4, 6.2), Seg::L(13.4, 9.8), Seg::C(13.4, 10.684, 12.684, 11.4, 11.8, 11.4), Seg::L(2.6, 11.4), Seg::C(1.716, 11.4, 1.0, 10.684, 1.0, 9.8), Seg::L(1.0, 6.2), Seg::C(1.0, 5.316, 1.716, 4.6, 2.6, 4.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(14.0, 6.6), Seg::L(15.4, 6.6), Seg::L(15.4, 9.4), Seg::L(14.0, 9.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.7, 6.3), Seg::L(4.14, 6.3), Seg::L(4.14, 9.7), Seg::L(2.7, 9.7), Seg::Z] },
];

#[rustfmt::skip]
const BATTERY_CHARGING: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(2.6, 4.6), Seg::L(11.8, 4.6), Seg::C(12.684, 4.6, 13.4, 5.316, 13.4, 6.2), Seg::L(13.4, 9.8), Seg::C(13.4, 10.684, 12.684, 11.4, 11.8, 11.4), Seg::L(2.6, 11.4), Seg::C(1.716, 11.4, 1.0, 10.684, 1.0, 9.8), Seg::L(1.0, 6.2), Seg::C(1.0, 5.316, 1.716, 4.6, 2.6, 4.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(14.0, 6.6), Seg::L(15.4, 6.6), Seg::L(15.4, 9.4), Seg::L(14.0, 9.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.4, 5.6), Seg::L(5.2, 8.5), Seg::L(7.0, 8.5), Seg::L(6.0, 10.4), Seg::L(9.2, 7.5), Seg::L(7.4, 7.5), Seg::Z] },
];

#[rustfmt::skip]
const PLANE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 0.8), Seg::L(9.2, 2.6), Seg::L(9.2, 5.4), Seg::L(15.2, 9.6), Seg::L(15.2, 11.6), Seg::L(9.2, 9.2), Seg::L(9.2, 12.2), Seg::L(11.4, 14.0), Seg::L(11.4, 15.4), Seg::L(8.0, 14.4), Seg::L(4.6, 15.4), Seg::L(4.6, 14.0), Seg::L(6.8, 12.2), Seg::L(6.8, 9.2), Seg::L(0.8, 11.6), Seg::L(0.8, 9.6), Seg::L(6.8, 5.4), Seg::L(6.8, 2.6), Seg::Z] },
];

#[rustfmt::skip]
const FLAG: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.8, 1.4), Seg::L(4.6, 1.4), Seg::L(4.6, 14.6), Seg::L(2.8, 14.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(5.6, 2.4), Seg::L(14.2, 2.4), Seg::L(11.4, 5.8), Seg::L(14.2, 9.2), Seg::L(5.6, 9.2), Seg::Z] },
];

#[rustfmt::skip]
const FLAG_NONE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.8, 1.4), Seg::L(4.6, 1.4), Seg::L(4.6, 14.6), Seg::L(2.8, 14.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(5.6, 2.4), Seg::L(14.2, 2.4), Seg::L(11.4, 5.8), Seg::L(14.2, 9.2), Seg::L(5.6, 9.2), Seg::Z] },
];

#[rustfmt::skip]
const QUIET: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 1.4), Seg::L(14.6, 8.0), Seg::L(8.0, 14.6), Seg::L(1.4, 8.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(4.7, 7.0), Seg::L(11.3, 7.0), Seg::L(11.3, 9.0), Seg::L(4.7, 9.0), Seg::Z] },
];

#[rustfmt::skip]
const DUE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.6, 1.4), Seg::L(13.4, 1.4), Seg::L(13.4, 3.2), Seg::L(2.6, 3.2), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.6, 12.8), Seg::L(13.4, 12.8), Seg::L(13.4, 14.6), Seg::L(2.6, 14.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(3.8, 4.0), Seg::L(12.2, 4.0), Seg::L(8.0, 7.7), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 8.3), Seg::L(12.2, 12.0), Seg::L(3.8, 12.0), Seg::Z] },
];

#[rustfmt::skip]
const CALENDAR: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(4.0, 0.8), Seg::L(5.8, 0.8), Seg::L(5.8, 3.4), Seg::L(4.0, 3.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(10.2, 0.8), Seg::L(12.0, 0.8), Seg::L(12.0, 3.4), Seg::L(10.2, 3.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(3.0, 2.6), Seg::L(13.0, 2.6), Seg::C(13.994, 2.6, 14.8, 3.406, 14.8, 4.4), Seg::L(14.8, 13.2), Seg::C(14.8, 14.194, 13.994, 15.0, 13.0, 15.0), Seg::L(3.0, 15.0), Seg::C(2.006, 15.0, 1.2, 14.194, 1.2, 13.2), Seg::L(1.2, 4.4), Seg::C(1.2, 3.406, 2.006, 2.6, 3.0, 2.6), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(1.2, 6.0), Seg::L(14.8, 6.0), Seg::L(14.8, 7.2), Seg::L(1.2, 7.2), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(8.0, 9.2), Seg::L(9.9, 11.1), Seg::L(8.0, 13.0), Seg::L(6.1, 11.1), Seg::Z] },
];

#[rustfmt::skip]
const STOPWATCH: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(6.4, 0.6), Seg::L(9.6, 0.6), Seg::L(9.6, 2.2), Seg::L(6.4, 2.2), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(7.3, 2.0), Seg::L(8.7, 2.0), Seg::L(8.7, 3.4), Seg::L(7.3, 3.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(11.4, 3.2), Seg::L(12.5, 2.1), Seg::L(14.1, 3.7), Seg::L(13.0, 4.8), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.2, 9.7), Seg::C(2.2, 6.497, 4.797, 3.9, 8.0, 3.9), Seg::C(11.203, 3.9, 13.8, 6.497, 13.8, 9.7), Seg::C(13.8, 12.903, 11.203, 15.5, 8.0, 15.5), Seg::C(4.797, 15.5, 2.2, 12.903, 2.2, 9.7), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 1.5, path: &[Seg::M(8.0, 10.4), Seg::L(8.0, 5.8)] },
    Shape { ink: Ink::Off, stroke: 1.5, path: &[Seg::M(7.3, 9.7), Seg::L(10.6, 9.7)] },
];

#[rustfmt::skip]
const CHECK: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 2.6, path: &[Seg::M(2.2, 8.4), Seg::L(6.2, 12.4), Seg::L(13.8, 3.8)] },
];

#[rustfmt::skip]
const PULSE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.9, path: &[Seg::M(0.8, 8.6), Seg::L(4.0, 8.6), Seg::L(5.9, 3.4), Seg::L(8.6, 13.2), Seg::L(10.6, 6.4), Seg::L(11.8, 8.6), Seg::L(15.2, 8.6)] },
];

#[rustfmt::skip]
const KEY: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(4.8, 3.8), Seg::L(9.0, 8.0), Seg::L(4.8, 12.2), Seg::L(0.6, 8.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(4.8, 6.5), Seg::L(6.3, 8.0), Seg::L(4.8, 9.5), Seg::L(3.3, 8.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 7.1), Seg::L(15.2, 7.1), Seg::L(15.2, 8.9), Seg::L(8.0, 8.9), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(11.0, 8.9), Seg::L(12.6, 8.9), Seg::L(12.6, 11.5), Seg::L(11.0, 11.5), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(13.6, 8.9), Seg::L(15.2, 8.9), Seg::L(15.2, 10.7), Seg::L(13.6, 10.7), Seg::Z] },
];

#[rustfmt::skip]
const VPN: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 0.9), Seg::L(14.0, 3.1), Seg::L(14.0, 7.8), Seg::C(14.0, 11.5, 11.2, 14.2, 8.0, 15.4), Seg::C(4.8, 14.2, 2.0, 11.5, 2.0, 7.8), Seg::L(2.0, 3.1), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(8.0, 5.6), Seg::L(10.0, 7.6), Seg::L(8.0, 9.6), Seg::L(6.0, 7.6), Seg::Z] },
];

#[rustfmt::skip]
const VPN_OFF: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.5, path: &[Seg::M(8.0, 1.9), Seg::L(13.2, 3.8), Seg::L(13.2, 7.8), Seg::C(13.2, 10.9, 10.8, 13.2, 8.0, 14.4), Seg::C(5.2, 13.2, 2.8, 10.9, 2.8, 7.8), Seg::L(2.8, 3.8), Seg::Z] },
];

#[rustfmt::skip]
const LOCK: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.8, path: &[Seg::M(5.0, 7.4), Seg::L(5.0, 5.0), Seg::C(5.0, 3.343, 6.343, 2.0, 8.0, 2.0), Seg::C(9.657, 2.0, 11.0, 3.343, 11.0, 5.0), Seg::L(11.0, 7.4)] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(4.6, 7.0), Seg::L(11.4, 7.0), Seg::C(12.284, 7.0, 13.0, 7.716, 13.0, 8.6), Seg::L(13.0, 12.8), Seg::C(13.0, 13.684, 12.284, 14.4, 11.4, 14.4), Seg::L(4.6, 14.4), Seg::C(3.716, 14.4, 3.0, 13.684, 3.0, 12.8), Seg::L(3.0, 8.6), Seg::C(3.0, 7.716, 3.716, 7.0, 4.6, 7.0), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(8.0, 9.3), Seg::L(9.4, 10.7), Seg::L(8.0, 12.1), Seg::L(6.6, 10.7), Seg::Z] },
];

#[rustfmt::skip]
const DRIVE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 2.6), Seg::L(14.2, 9.0), Seg::L(1.8, 9.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(1.8, 11.0), Seg::L(14.2, 11.0), Seg::L(14.2, 13.4), Seg::L(1.8, 13.4), Seg::Z] },
];

#[rustfmt::skip]
const UPDATE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(8.0, 1.6), Seg::L(8.0, 9.0)] },
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(4.2, 5.8), Seg::L(8.0, 9.6), Seg::L(11.8, 5.8)] },
    Shape { ink: Ink::On, stroke: 1.8, path: &[Seg::M(2.0, 10.6), Seg::L(2.0, 13.8), Seg::L(14.0, 13.8), Seg::L(14.0, 10.6)] },
];

#[rustfmt::skip]
const PAD: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(3.2, 2.4), Seg::L(12.8, 2.4), Seg::C(13.794, 2.4, 14.6, 3.206, 14.6, 4.2), Seg::L(14.6, 11.8), Seg::C(14.6, 12.794, 13.794, 13.6, 12.8, 13.6), Seg::L(3.2, 13.6), Seg::C(2.206, 13.6, 1.4, 12.794, 1.4, 11.8), Seg::L(1.4, 4.2), Seg::C(1.4, 3.206, 2.206, 2.4, 3.2, 2.4), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(4.2, 9.4), Seg::L(11.8, 9.4), Seg::L(11.8, 11.2), Seg::L(4.2, 11.2), Seg::Z] },
];

#[rustfmt::skip]
const MORE: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.8, 6.3), Seg::L(4.5, 8.0), Seg::L(2.8, 9.7), Seg::L(1.1, 8.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 6.3), Seg::L(9.7, 8.0), Seg::L(8.0, 9.7), Seg::L(6.3, 8.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(13.2, 6.3), Seg::L(14.9, 8.0), Seg::L(13.2, 9.7), Seg::L(11.5, 8.0), Seg::Z] },
];

#[rustfmt::skip]
const POWER: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(11.571, 4.43), Seg::C(13.522, 5.954, 14.29, 8.548, 13.484, 10.889), Seg::C(12.678, 13.229, 10.475, 14.8, 8.0, 14.8), Seg::C(5.525, 14.8, 3.322, 13.229, 2.516, 10.889), Seg::C(1.71, 8.548, 2.478, 5.954, 4.429, 4.43)] },
    Shape { ink: Ink::On, stroke: 2.0, path: &[Seg::M(8.0, 1.0), Seg::L(8.0, 8.2)] },
];

#[rustfmt::skip]
const DISPLAY: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.6, 2.0), Seg::L(13.4, 2.0), Seg::C(14.284, 2.0, 15.0, 2.716, 15.0, 3.6), Seg::L(15.0, 10.0), Seg::C(15.0, 10.884, 14.284, 11.6, 13.4, 11.6), Seg::L(2.6, 11.6), Seg::C(1.716, 11.6, 1.0, 10.884, 1.0, 10.0), Seg::L(1.0, 3.6), Seg::C(1.0, 2.716, 1.716, 2.0, 2.6, 2.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(7.0, 11.6), Seg::L(9.0, 11.6), Seg::L(9.0, 13.4), Seg::L(7.0, 13.4), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(4.4, 13.2), Seg::L(11.6, 13.2), Seg::L(11.6, 14.8), Seg::L(4.4, 14.8), Seg::Z] },
];

#[rustfmt::skip]
const PRINTER: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(4.2, 1.4), Seg::L(11.8, 1.4), Seg::L(11.8, 4.8), Seg::L(4.2, 4.8), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.6, 5.8), Seg::L(13.4, 5.8), Seg::C(14.173, 5.8, 14.8, 6.427, 14.8, 7.2), Seg::L(14.8, 10.8), Seg::C(14.8, 11.573, 14.173, 12.2, 13.4, 12.2), Seg::L(2.6, 12.2), Seg::C(1.827, 12.2, 1.2, 11.573, 1.2, 10.8), Seg::L(1.2, 7.2), Seg::C(1.2, 6.427, 1.827, 5.8, 2.6, 5.8), Seg::Z] },
    Shape { ink: Ink::Off, stroke: 0.0, path: &[Seg::M(4.2, 9.8), Seg::L(11.8, 9.8), Seg::L(11.8, 12.2), Seg::L(4.2, 12.2), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(5.2, 10.8), Seg::L(10.8, 10.8), Seg::L(10.8, 14.8), Seg::L(5.2, 14.8), Seg::Z] },
];

#[rustfmt::skip]
const PHONES: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 1.9, path: &[Seg::M(2.6, 10.4), Seg::L(2.6, 8.4), Seg::C(2.6, 5.418, 5.018, 3.0, 8.0, 3.0), Seg::C(10.982, 3.0, 13.4, 5.418, 13.4, 8.4), Seg::L(13.4, 10.4)] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(2.8, 9.0), Seg::L(3.4, 9.0), Seg::C(4.173, 9.0, 4.8, 9.627, 4.8, 10.4), Seg::L(4.8, 13.4), Seg::C(4.8, 14.173, 4.173, 14.8, 3.4, 14.8), Seg::L(2.8, 14.8), Seg::C(2.027, 14.8, 1.4, 14.173, 1.4, 13.4), Seg::L(1.4, 10.4), Seg::C(1.4, 9.627, 2.027, 9.0, 2.8, 9.0), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(12.6, 9.0), Seg::L(13.2, 9.0), Seg::C(13.973, 9.0, 14.6, 9.627, 14.6, 10.4), Seg::L(14.6, 13.4), Seg::C(14.6, 14.173, 13.973, 14.8, 13.2, 14.8), Seg::L(12.6, 14.8), Seg::C(11.827, 14.8, 11.2, 14.173, 11.2, 13.4), Seg::L(11.2, 10.4), Seg::C(11.2, 9.627, 11.827, 9.0, 12.6, 9.0), Seg::Z] },
];

#[rustfmt::skip]
const CAPS: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(8.0, 1.2), Seg::L(14.2, 7.6), Seg::L(10.7, 7.6), Seg::L(10.7, 11.0), Seg::L(5.3, 11.0), Seg::L(5.3, 7.6), Seg::L(1.8, 7.6), Seg::Z] },
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(5.3, 12.6), Seg::L(10.7, 12.6), Seg::L(10.7, 14.8), Seg::L(5.3, 14.8), Seg::Z] },
];

#[rustfmt::skip]
const NIGHT: &[Shape] = &[
    Shape { ink: Ink::On, stroke: 0.0, path: &[Seg::M(9.6, 1.7), Seg::C(6.2, 0.828, 2.722, 2.812, 1.743, 6.183), Seg::C(0.764, 9.554, 2.638, 13.093, 5.976, 14.178), Seg::C(9.313, 15.263, 12.91, 13.502, 14.1, 10.2), Seg::C(12.072, 10.23, 10.198, 9.12, 9.249, 7.327), Seg::C(8.3, 5.534, 8.435, 3.361, 9.6, 1.7), Seg::Z] },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_name_has_its_drawing() {
        for name in NAMES {
            let drawn = shapes(name).unwrap_or_else(|| panic!("{name} has no drawing"));
            assert!(!drawn.is_empty(), "{name} is empty");
            for s in drawn {
                assert!(matches!(s.path.first(), Some(Seg::M(..))), "{name}: a path begins with a move");
                assert!(s.stroke >= 0.0 && s.stroke < 4.0, "{name}: a stroke of {}", s.stroke);
                for seg in s.path {
                    let at = match *seg {
                        Seg::M(x, y) | Seg::L(x, y) | Seg::C(.., x, y) => (x, y),
                        Seg::Z => (0.0, 0.0),
                    };
                    let near = |v: f64| v > -1.0 && v < BOX + 1.0;
                    assert!(near(at.0) && near(at.1), "{name}: {at:?} is off the box");
                }
            }
        }
        assert_eq!(shapes("no such icon"), None);
        assert_eq!(shapes(""), None);
    }
}
