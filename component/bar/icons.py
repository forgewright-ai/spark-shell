#!/usr/bin/env python3
"""The bar's icons, each drawn in a box of 16: bold and solid, the shapes people know, ends cut flat, a
diamond only where it helps; solid is live, hollow is silent. These are the drawings; src/icons.rs is
written from them, and test/icons_check.py holds the two together.

  python3 -I component/bar/icons.py                  write src/icons.rs
  python3 -I component/bar/icons.py --check          1 unless src/icons.rs is what the drawings give
  python3 -I component/bar/icons.py --sheet OUT.svg  every drawing three times its size, to look at
"""
import math
import os
import re
import sys

ON, FAINT, OFF = "On", "Faint", "Off"   # a shape's ink: the part's tone, the tone faint, or a hole cut in what is under it
K = math.sqrt(0.5)


def points(s):
    return [tuple(float(v) for v in p.split(",")) for p in s.split()]


def arc(x1, y1, rx, ry, large, sweep, x2, y2):
    """An SVG arc from one point to another, as cubic curves of a quarter turn at most."""
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    wide = math.sqrt(max(dx * dx / (rx * rx) + dy * dy / (ry * ry), 1.0))
    rx, ry = rx * wide, ry * wide
    below = rx * rx * dy * dy + ry * ry * dx * dx
    k = math.sqrt(max((rx * rx * ry * ry - below) / below, 0.0)) * (1 if large != sweep else -1)
    mx, my = k * rx * dy / ry, -k * ry * dx / rx
    cx, cy = mx + (x1 + x2) / 2, my + (y1 + y2) / 2
    a1 = math.atan2((dy - my) / ry, (dx - mx) / rx)
    turn = math.atan2((-dy - my) / ry, (-dx - mx) / rx) - a1
    if sweep and turn < 0:
        turn += 2 * math.pi
    if not sweep and turn > 0:
        turn -= 2 * math.pi
    n = max(1, math.ceil(abs(turn) / (math.pi / 2) - 1e-9))
    out = []
    for i in range(n):
        t1, t2 = a1 + turn * i / n, a1 + turn * (i + 1) / n
        h = 4 / 3 * math.tan((t2 - t1) / 4)
        p1 = (cx + rx * math.cos(t1), cy + ry * math.sin(t1))
        p2 = (cx + rx * math.cos(t2), cy + ry * math.sin(t2))
        out.append(("C", p1[0] - h * rx * math.sin(t1), p1[1] + h * ry * math.cos(t1), p2[0] + h * rx * math.sin(t2), p2[1] - h * ry * math.cos(t2), p2[0], p2[1]))
    return out


def path(d, ink=ON, w=0.0):
    """A path in SVG's words (M L H V A C Z, absolute): filled, or stroked `w` wide."""
    words = re.findall(r"[MLHVACZ]|-?\d+\.?\d*", d)
    segs, at, i = [], (0.0, 0.0), 0
    while i < len(words):
        word, take = words[i], {"M": 2, "L": 2, "H": 1, "V": 1, "A": 7, "C": 6, "Z": 0}[words[i]]
        v = [float(n) for n in words[i + 1:i + 1 + take]]
        i += 1 + take
        if word in "ML":
            at = (v[0], v[1])
            segs.append((word,) + at)
        elif word == "H":
            at = (v[0], at[1])
            segs.append(("L",) + at)
        elif word == "V":
            at = (at[0], v[0])
            segs.append(("L",) + at)
        elif word == "A":
            segs += arc(at[0], at[1], v[0], v[1], v[3] != 0, v[4] != 0, v[5], v[6])
            at = (v[5], v[6])
        elif word == "C":
            segs.append(("C",) + tuple(v))
            at = (v[4], v[5])
        else:
            segs.append(("Z",))
    return [(ink, w, segs)]


def poly(pts, ink=ON, w=0.0):
    p = points(pts)
    return [(ink, w, [("M",) + p[0]] + [("L",) + q for q in p[1:]] + [("Z",)])]


def line(pts, w=1.8, ink=ON):
    p = points(pts)
    return [(ink, w, [("M",) + p[0]] + [("L",) + q for q in p[1:]])]


def rect(x, y, w, h, r=0.0, ink=ON, sw=0.0):
    rx, ry = min(r, w / 2), min(r, h / 2)
    if rx <= 0:
        return poly("%g,%g %g,%g %g,%g %g,%g" % (x, y, x + w, y, x + w, y + h, x, y + h), ink, sw)
    return path("M%g,%g H%g A%g,%g 0 0 1 %g,%g V%g A%g,%g 0 0 1 %g,%g H%g A%g,%g 0 0 1 %g,%g V%g A%g,%g 0 0 1 %g,%g Z"
                % (x + rx, y, x + w - rx, rx, ry, x + w, y + ry, y + h - ry, rx, ry, x + w - rx, y + h, x + rx, rx, ry, x, y + h - ry, y + ry, rx, ry, x + rx, y), ink, sw)


def disc(cx, cy, r, ink=ON, w=0.0):
    return path("M%g,%g A%g,%g 0 1 1 %g,%g A%g,%g 0 1 1 %g,%g Z" % (cx - r, cy, r, r, cx + r, cy, r, r, cx - r, cy), ink, w)


def diamond(cx, cy, r, ink=ON, w=0.0):
    return poly("%g,%g %g,%g %g,%g %g,%g" % (cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy), ink, w)


def band(cx, cy, r1, r2, ink=ON):
    """A ring's quarter, opening upward; from the center when r1 is 0."""
    if r1 <= 0:
        return path("M%g,%g L%.3f,%.3f A%g,%g 0 0 1 %.3f,%.3f Z" % (cx, cy, cx - r2 * K, cy - r2 * K, r2, r2, cx + r2 * K, cy - r2 * K), ink)
    return path("M%.3f,%.3f A%g,%g 0 0 1 %.3f,%.3f L%.3f,%.3f A%g,%g 0 0 0 %.3f,%.3f Z"
                % (cx - r2 * K, cy - r2 * K, r2, r2, cx + r2 * K, cy - r2 * K, cx + r1 * K, cy - r1 * K, r1, r1, cx - r1 * K, cy - r1 * K), ink)


# the drawings: a name, or a name and its form, each a list of shapes
def lan():
    return line("1.9,5.6 4.5,3 7.1,5.6", 2) + line("4.5,3.6 4.5,13.8", 2) + line("8.9,10.4 11.5,13 14.1,10.4", 2) + line("11.5,2.2 11.5,12.4", 2)


def bt(form):
    """linked: a dot at each side; idle: the rune alone; off: the rune drawn thin."""
    rune = path("M4.6,4.8 L11.4,11.2 L8,14.6 L8,1.4 L11.4,4.8 L4.6,11.2", w=1.1 if form == "off" else 1.9)
    return rune + (diamond(1.7, 8, 1.5) + diamond(14.3, 8, 1.5) if form == "linked" else [])


def wifi(form):
    """on: three bands; fair and weak: the outer bands faint, by the signal; off: the tip hollow."""
    tip = path("M8,14 L%.3f,%.3f A2.6,2.6 0 0 1 %.3f,%.3f Z" % (8 - 2.6 * K, 14 - 2.6 * K, 8 + 2.6 * K, 14 - 2.6 * K), w=1.1) if form == "off" else band(8, 14.6, 0, 3.2)
    return band(8, 14.6, 9.2, 12.2, FAINT if form in ("fair", "weak") else ON) + band(8, 14.6, 4.6, 7.6, FAINT if form == "weak" else ON) + tip


def out(muted):
    if muted:
        return poly("2.4,6.2 5,6.2 8.6,3.2 8.6,12.8 5,9.8 2.4,9.8", w=1.5)
    return poly("1.6,5.6 4.8,5.6 9.2,2 9.2,14 4.8,10.4 1.6,10.4") + poly("11,3.4 15.6,8 11,12.6 11,10 13,8 11,6")


def mic(muted):
    pill = rect(5.65, 1.55, 4.7, 8.3, 2.35, sw=1.5) if muted else rect(4.9, 0.8, 6.2, 9.8, 3.1)
    return pill + path("M2.4,7.6 V8.6 A5.6,5.6 0 0 0 13.6,8.6 V7.6", w=1.8) + line("8,14.2 8,16")


def due():
    return rect(2.6, 1.4, 10.8, 1.8) + rect(2.6, 12.8, 10.8, 1.8) + poly("3.8,4 12.2,4 8,7.7") + poly("8,8.3 12.2,12 3.8,12")


def light():
    o = disc(8, 8, 2.9)
    for i in range(8):
        a = math.radians(45 * i)
        r1, r2 = (4.7, 7.2) if i % 2 == 0 else (4.5, 6.6)
        o += line("%.3f,%.3f %.3f,%.3f" % (8 + r1 * math.cos(a), 8 + r1 * math.sin(a), 8 + r2 * math.cos(a), 8 + r2 * math.sin(a)), 1.7)
    return o


def kb():
    keys = [s for x in (2.9, 5.77, 8.63, 11.5) for s in rect(x, 5.4, 1.6, 1.6, ink=OFF)]
    return rect(1, 3.6, 14, 8.8, 1.8) + keys + rect(4.6, 8.8, 6.8, 1.6, ink=OFF)


def flag(some):
    return rect(2.8, 1.4, 1.8, 13.2) + poly("5.6,2.4 14.2,2.4 11.4,5.8 14.2,9.2 5.6,9.2", w=0.0 if some else 1.5)


def quiet():
    return diamond(8, 8, 6.6) + rect(4.7, 7, 6.6, 2, ink=OFF)


def pad():
    return rect(1.4, 2.4, 13.2, 11.2, 1.8) + rect(4.2, 9.4, 7.6, 1.8, ink=OFF)


def battery(form):
    case = rect(1, 4.6, 12.4, 6.8, 1.6, sw=1.5) + rect(14, 6.6, 1.4, 2.8)
    if form == "charging":
        return case + poly("8.4,5.6 5.2,8.5 7,8.5 6,10.4 9.2,7.5 7.4,7.5")
    return case + rect(2.7, 6.3, 9.0 * {"full": 1.0, "half": 0.5, "low": 0.16}[form], 3.4)


def plane():
    return poly("8,0.8 9.2,2.6 9.2,5.4 15.2,9.6 15.2,11.6 9.2,9.2 9.2,12.2 11.4,14 11.4,15.4 8,14.4 4.6,15.4 4.6,14 6.8,12.2 6.8,9.2 0.8,11.6 0.8,9.6 6.8,5.4 6.8,2.6")


def vpn(on):
    if not on:
        return path("M8,1.9 L13.2,3.8 V7.8 C13.2,10.9 10.8,13.2 8,14.4 C5.2,13.2 2.8,10.9 2.8,7.8 V3.8 Z", w=1.5)
    return path("M8,0.9 L14,3.1 V7.8 C14,11.5 11.2,14.2 8,15.4 C4.8,14.2 2,11.5 2,7.8 V3.1 Z") + diamond(8, 7.6, 2, OFF)


def lock():
    return path("M5,7.4 V5 A3,3 0 0 1 11,5 V7.4", w=1.8) + rect(3, 7, 10, 7.4, 1.6) + diamond(8, 10.7, 1.4, OFF)


def power():
    k, h = 5.8 * math.sin(math.radians(38)), 5.8 * math.cos(math.radians(38))
    return path("M%.3f,%.3f A5.8,5.8 0 1 1 %.3f,%.3f" % (8 + k, 9 - h, 8 - k, 9 - h), w=2) + line("8,1 8,8.2", 2)


def phones():
    return path("M2.6,10.4 V8.4 A5.4,5.4 0 0 1 13.4,8.4 V10.4", w=1.9) + rect(1.4, 9, 3.4, 5.8, 1.4) + rect(11.2, 9, 3.4, 5.8, 1.4)


def display():
    return rect(1, 2, 14, 9.6, 1.6) + rect(7, 11.6, 2, 1.8) + rect(4.4, 13.2, 7.2, 1.6)


def printer():
    return rect(4.2, 1.4, 7.6, 3.4) + rect(1.2, 5.8, 13.6, 6.4, 1.4) + rect(4.2, 9.8, 7.6, 2.4, ink=OFF) + rect(5.2, 10.8, 5.6, 4)


def caps():
    return poly("8,1.2 14.2,7.6 10.7,7.6 10.7,11 5.3,11 5.3,7.6 1.8,7.6") + rect(5.3, 12.6, 5.4, 2.2)


def night():
    return path("M9.6,1.7 A6.5,6.5 0 1 0 14.1,10.2 A5.4,5.4 0 0 1 9.6,1.7 Z")


def drive():
    return poly("8,2.6 14.2,9 1.8,9") + rect(1.8, 11, 12.4, 2.4)


def update():
    return line("8,1.6 8,9", 2) + line("4.2,5.8 8,9.6 11.8,5.8", 2) + line("2,10.6 2,13.8 14,13.8 14,10.6", 1.8)


def more():
    return diamond(2.8, 8, 1.7) + diamond(8, 8, 1.7) + diamond(13.2, 8, 1.7)


def key():
    return diamond(4.8, 8, 4.2) + diamond(4.8, 8, 1.5, OFF) + rect(8, 7.1, 7.2, 1.8) + rect(11, 8.9, 1.6, 2.6) + rect(13.6, 8.9, 1.6, 1.8)


def calendar():
    return rect(4, 0.8, 1.8, 2.6) + rect(10.2, 0.8, 1.8, 2.6) + rect(1.2, 2.6, 13.6, 12.4, 1.8) + rect(1.2, 6, 13.6, 1.2, ink=OFF) + diamond(8, 11.1, 1.9, OFF)


def stopwatch():
    return (rect(6.4, 0.6, 3.2, 1.6) + rect(7.3, 2, 1.4, 1.4) + poly("11.4,3.2 12.5,2.1 14.1,3.7 13,4.8") + disc(8, 9.7, 5.8)
            + line("8,10.4 8,5.8", 1.5, OFF) + line("7.3,9.7 10.6,9.7", 1.5, OFF))


def check():
    return line("2.2,8.4 6.2,12.4 13.8,3.8", 2.6)


def pulse():
    return line("0.8,8.6 4,8.6 5.9,3.4 8.6,13.2 10.6,6.4 11.8,8.6 15.2,8.6", 1.9)


ICONS = {
    "lan": lan(), "bt": bt("linked"), "bt-idle": bt("idle"), "bt-off": bt("off"),
    "wifi": wifi("on"), "wifi-fair": wifi("fair"), "wifi-weak": wifi("weak"), "wifi-off": wifi("off"),
    "out": out(False), "out-muted": out(True), "mic": mic(False), "mic-muted": mic(True),
    "light": light(), "kb": kb(),
    "battery-full": battery("full"), "battery-half": battery("half"), "battery-low": battery("low"), "battery-charging": battery("charging"),
    "plane": plane(), "flag": flag(True), "flag-none": flag(False), "quiet": quiet(),
    "due": due(), "calendar": calendar(), "stopwatch": stopwatch(), "check": check(), "pulse": pulse(),
    "key": key(), "vpn": vpn(True), "vpn-off": vpn(False), "lock": lock(), "drive": drive(), "update": update(),
    "pad": pad(), "more": more(), "power": power(), "display": display(), "printer": printer(), "phones": phones(),
    "caps": caps(), "night": night(),
}

HEAD = """//! The bar's icons, each drawn in a box of 16: written by component/bar/icons.py from its drawings, never by
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
"""

TESTS = """
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
"""


def num(v):
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    s = "0" if s in ("-0", "") else s
    return s + ".0" if "." not in s else s


def seg(s):
    return "Seg::Z" if s[0] == "Z" else "Seg::%s(%s)" % (s[0], ", ".join(num(v) for v in s[1:]))


def const(name):
    return name.upper().replace("-", "_")


def rust():
    out = [HEAD]
    out.append("/// Every drawing's name: an icon, or an icon and its form.\npub const NAMES: [&str; %d] = [\n%s];\n" % (len(ICONS), "".join('    "%s",\n' % n for n in ICONS)))
    out.append("/// A drawing by its name; none for a name the bar does not know.\npub fn shapes(name: &str) -> Option<&'static [Shape]> {\n    Some(match name {\n%s        _ => return None,\n    })\n}\n"
               % "".join('        "%s" => %s,\n' % (n, const(n)) for n in ICONS))
    for name, shapes in ICONS.items():
        rows = "".join("    Shape { ink: Ink::%s, stroke: %s, path: &[%s] },\n" % (ink, num(w), ", ".join(seg(s) for s in segs)) for ink, w, segs in shapes)
        out.append("#[rustfmt::skip]\nconst %s: &[Shape] = &[\n%s];\n" % (const(name), rows))
    return "\n".join(out) + TESTS


def sheet():
    """Every drawing on a dark ground, three times its size: a hole shows the ground."""
    ground, ink, faint, o = "#191724", "#e0def4", "#6e6a86", []
    for i, (name, shapes) in enumerate(ICONS.items()):
        x, y, parts = 24 + (i % 10) * 120, 24 + (i // 10) * 100, []
        for kind, w, segs in shapes:
            d = " ".join("Z" if s[0] == "Z" else s[0] + ",".join("%.3f" % v for v in s[1:]) for s in segs)
            color = {ON: ink, FAINT: faint, OFF: ground}[kind]
            paint = 'fill="none" stroke="%s" stroke-width="%g" stroke-miterlimit="6"' % (color, w) if w else 'fill="%s"' % color
            parts.append('<path d="%s" %s/>' % (d, paint))
        o.append('<g transform="translate(%d %d) scale(3)">%s</g><text x="%d" y="%d" font-size="11" fill="#8a8f98" text-anchor="middle">%s</text>' % (x, y, "".join(parts), x + 24, y + 68, name))
    rows = (len(ICONS) + 9) // 10
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1230" height="%d" font-family="monospace"><rect width="100%%" height="100%%" fill="%s"/>%s</svg>\n' % (rows * 100 + 24, ground, "".join(o))


def main(args):
    target = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", "icons.rs")
    if args[:1] == ["--sheet"] and len(args) == 2:
        open(args[1], "w").write(sheet())
    elif args == ["--check"]:
        if not os.path.exists(target) or open(target).read() != rust():
            print("component/bar/src/icons.rs is not what component/bar/icons.py draws: run python3 -I component/bar/icons.py")
            return 1
    elif not args:
        open(target, "w").write(rust())
    else:
        print(__doc__.strip())
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
