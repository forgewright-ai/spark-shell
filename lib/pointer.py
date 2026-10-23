#!/usr/bin/env python3
"""The spark pointer: two cursor themes, spark-white and spark-black, written as
Xcursor files from geometry (spark-shell issue #22, the owner's sketches).

    python3 lib/pointer.py ICONS_DIR        # ICONS_DIR/spark-white/cursors/..., spark-black
    python3 lib/pointer.py --version        # the geometry's version, stamped in each theme

Every shape is a signed distance over a 24-pixel grid: the fill, a one-pixel line
around it, and inner lines in the line's color. Every straight edge sits on a whole
pixel, so a line is one crisp pixel. The other sizes (32, 48, 64, 96) are the same
geometry scaled, as sway picks them for a scaled screen. Standard library only.
"""
import math
import os
import struct
import sys

VERSION = "2"          # bump when a shape or an alias changes: on desktop writes the themes again
SIZES = (24, 32, 48, 64, 96)
WHITE = ((255, 255, 255), (14, 14, 16))
BLACK = ((0, 0, 0), (255, 255, 255))
LINE = 1.0             # the line around a shape, in pixels of the 24 grid


# ---- signed distances, all in the 24 grid ----------------------------------
def sd_circle(c, r):
    return lambda x, y: math.hypot(x - c[0], y - c[1]) - r


def sd_box(c, h, r=0.0):
    """A box with center c and half extents h, its corners rounded by r."""
    def f(x, y):
        qx = abs(x - c[0]) - h[0] + r
        qy = abs(y - c[1]) - h[1] + r
        return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r
    return f


def sd_rbox(c, h, r, deg):
    """A rounded box turned by deg degrees."""
    ca, sa = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    f = sd_box((0.0, 0.0), h, r)
    return lambda x, y: f((x - c[0]) * ca + (y - c[1]) * sa, -(x - c[0]) * sa + (y - c[1]) * ca)


def sd_capsule(a, b, r):
    def f(x, y):
        pax, pay = x - a[0], y - a[1]
        bax, bay = b[0] - a[0], b[1] - a[1]
        t = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
        return math.hypot(pax - bax * t, pay - bay * t) - r
    return f


def sd_poly(pts):
    n = len(pts)

    def f(x, y):
        d = float("inf")
        s = 1.0
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[i - 1]
            ex, ey = bx - ax, by - ay
            wx, wy = x - ax, y - ay
            t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
            d = min(d, (wx - ex * t) ** 2 + (wy - ey * t) ** 2)
            c1 = y >= ay
            c2 = y < by
            c3 = ex * wy > ey * wx
            if (c1 and c2 and c3) or ((not c1) and (not c2) and (not c3)):
                s = -s
        return s * math.sqrt(d)
    return f


def union(*fs):
    return lambda x, y: min(f(x, y) for f in fs)


def cut(f, *gs):
    return lambda x, y: max(f(x, y), *(-g(x, y) for g in gs))


def flip_x(f):
    return lambda x, y: f(24.0 - x, y)


def flip_y(f):
    return lambda x, y: f(x, 24.0 - y)


def swap_xy(f):
    return lambda x, y: f(y, x)


# ---- the shapes: (sdf, hot spot, inner lines or None) -----------------------
def shapes():
    S = {}
    L = 19.0
    tip = (2.0, 2.0)
    bottom = (tip[0] + L * math.sin(math.radians(20)), tip[1] + L * math.cos(math.radians(20)))
    right = (tip[0] + L * math.cos(math.radians(30)), tip[1] + L * math.sin(math.radians(30)))
    notch = (tip[0] + 0.72 * L * math.sin(math.radians(35)), tip[1] + 0.72 * L * math.cos(math.radians(35)))
    S["default"] = (sd_poly([tip, right, notch, bottom]), (1, 1), None)   # a notched delta, no stem

    index = sd_box((10.0, 7.5), (2.0, 5.5), 0.7)                            # x 8..12, y 2..13
    k1 = sd_box((13.5, 10.5), (1.5, 2.5), 0.7)
    k2 = sd_box((16.5, 10.5), (1.5, 2.5), 0.7)
    k3 = sd_box((19.5, 11.0), (1.5, 2.0), 0.7)
    palm = sd_box((14.5, 15.0), (6.5, 3.0), 0.7)                            # x 8..21, y 12..18
    thumb = sd_rbox((6.3, 14.3), (3.0, 1.85), 0.7, 125)
    cuff = sd_box((14.5, 20.0), (5.5, 1.0), 0.3)                            # x 9..20, y 19..21
    hand_lines = union(sd_capsule((11.5, 8.5), (11.5, 12.5), 0.5),           # the line that marks the click finger
                       sd_capsule((15.5, 9.5), (15.5, 12.5), 0.5), sd_capsule((18.5, 10.0), (18.5, 12.5), 0.5))
    S["pointer"] = (union(index, k1, k2, k3, palm, thumb, cuff), (10, 1), hand_lines)

    k0 = sd_box((9.5, 10.5), (1.5, 2.5), 0.7)                                # a fist: four knuckles, no finger up
    fist_lines = union(sd_capsule((11.5, 8.5), (11.5, 12.5), 0.5), sd_capsule((14.5, 8.5), (14.5, 12.5), 0.5),
                       sd_capsule((17.5, 9.0), (17.5, 12.5), 0.5))
    k1b = sd_box((12.5, 10.5), (1.5, 2.5), 0.7)
    k2b = sd_box((15.5, 10.5), (1.5, 2.5), 0.7)
    k3b = sd_box((18.5, 11.0), (1.5, 2.0), 0.7)
    S["grabbing"] = (union(k0, k1b, k2b, k3b, palm, thumb, cuff), (12, 12), fist_lines)

    stem = sd_box((12.0, 12.0), (1.0, 7.0))                                  # x 11..13, y 5..19
    serifs = union(sd_box((9.5, 4.0), (1.5, 1.0)), sd_box((14.5, 4.0), (1.5, 1.0)),
                   sd_box((9.5, 20.0), (1.5, 1.0)), sd_box((14.5, 20.0), (1.5, 1.0)))
    S["text"] = (union(stem, serifs), (12, 12), None)

    bar = sd_box((12.0, 12.0), (1.0, 6.0))                                   # x 11..13, y 6..18
    tri_l = sd_poly([(2.5, 12.0), (8.0, 6.0), (8.0, 18.0)])
    tri_r = sd_poly([(21.5, 12.0), (16.0, 6.0), (16.0, 18.0)])
    col = union(bar, tri_l, tri_r)
    S["col-resize"] = (col, (12, 12), None)
    S["row-resize"] = (swap_xy(col), (12, 12), None)

    head_w = sd_poly([(2.5, 12.0), (8.0, 7.0), (8.0, 17.0)])                 # one head and a shaft: the four sides
    shaft_w = sd_box((14.5, 12.0), (6.5, 1.0))                               # x 8..21, y 11..13
    w = union(head_w, shaft_w)
    S["w-resize"] = (w, (12, 12), None)
    S["e-resize"] = (flip_x(w), (12, 12), None)
    S["n-resize"] = (swap_xy(w), (12, 12), None)
    S["s-resize"] = (flip_y(swap_xy(w)), (12, 12), None)

    bracket = union(sd_box((10.5, 3.0), (8.5, 1.0)), sd_box((3.0, 10.5), (1.0, 8.5)))   # arms x 2..19 and y 2..19
    wedge = sd_poly([(7.0, 7.0), (18.0, 7.0), (7.0, 18.0)])
    nw = union(bracket, wedge)
    S["nw-resize"] = (nw, (7, 7), None)                                      # the hot spot in the wedge's corner pixel
    S["ne-resize"] = (flip_x(nw), (16, 7), None)
    S["sw-resize"] = (flip_y(nw), (7, 16), None)
    S["se-resize"] = (flip_x(flip_y(nw)), (16, 16), None)

    diag_shaft = sd_capsule((8.0, 8.0), (16.0, 16.0), 1.0)
    h1 = sd_poly([(3.0, 3.0), (10.0, 5.0), (5.0, 10.0)])
    h2 = sd_poly([(21.0, 21.0), (14.0, 19.0), (19.0, 14.0)])
    nwse = union(diag_shaft, h1, h2)
    S["nwse-resize"] = (nwse, (12, 12), None)
    S["nesw-resize"] = (flip_x(nwse), (12, 12), None)

    plus_v = sd_box((12.0, 12.0), (1.0, 6.0))
    plus_h = sd_box((12.0, 12.0), (6.0, 1.0))
    up = sd_poly([(12.0, 1.5), (8.5, 6.0), (15.5, 6.0)])                   # narrow heads: no pocket between a head and the bars
    left = sd_poly([(1.5, 12.0), (6.0, 8.5), (6.0, 15.5)])
    S["move"] = (union(plus_v, plus_h, up, flip_y(up), left, flip_x(left)), (12, 12), None)

    ring = lambda x, y: abs(math.hypot(x - 12.0, y - 12.0) - 8.0) - 1.0      # noqa: E731
    slash = sd_rbox((12.0, 12.0), (7.0, 1.0), 0.0, 45)
    S["not-allowed"] = (union(ring, slash), (12, 12), None)

    S["crosshair"] = (union(sd_box((12.0, 12.0), (1.0, 10.0)), sd_box((12.0, 12.0), (10.0, 1.0))), (12, 12), None)

    glass = sd_poly([(7.0, 6.0), (17.0, 6.0), (17.0, 9.5), (12.75, 11.5), (12.75, 12.5), (17.0, 14.5), (17.0, 18.0),
                     (7.0, 18.0), (7.0, 14.5), (11.25, 12.5), (11.25, 11.5), (7.0, 9.5)])
    S["wait"] = (union(glass, sd_box((12.0, 2.0), (5.0, 1.0)), sd_box((12.0, 22.0), (5.0, 1.0))), (12, 12), None)
    return S


# the same image under the names the cursor-shape protocol and X apps ask for
ALIASES = {
    "default": ["left_ptr", "arrow", "top_left_arrow"],
    "pointer": ["hand1", "hand2", "pointing_hand", "openhand", "alias", "copy", "context-menu", "help", "cell", "dnd-copy", "dnd-link", "dnd-ask", "dnd-none"],
    "grabbing": ["grab", "closedhand", "fleur_grab", "dnd-move"],   # grab: what sway asks for while a window moves (#46)
    "text": ["xterm", "ibeam", "vertical-text"],
    "wait": ["watch", "progress", "left_ptr_watch", "half-busy"],
    "col-resize": ["sb_h_double_arrow", "split_h", "ew-resize", "h_double_arrow", "size_hor"],
    "row-resize": ["sb_v_double_arrow", "split_v", "ns-resize", "v_double_arrow", "size_ver"],
    "w-resize": ["left_side"],
    "e-resize": ["right_side"],
    "n-resize": ["top_side"],
    "s-resize": ["bottom_side"],
    "nw-resize": ["top_left_corner", "ul_angle"],
    "ne-resize": ["top_right_corner", "ur_angle"],
    "sw-resize": ["bottom_left_corner", "ll_angle"],
    "se-resize": ["bottom_right_corner", "lr_angle"],
    "nwse-resize": ["bd_double_arrow", "size_fdiag"],
    "nesw-resize": ["fd_double_arrow", "size_bdiag"],
    "move": ["fleur", "all-scroll", "size_all"],
    "not-allowed": ["crossed_circle", "forbidden", "no-drop", "dnd-no-drop", "circle"],
    "crosshair": ["cross", "tcross", "plus"],
}


# ---- rendering ---------------------------------------------------------------
def coverage(sdf, inner, size):
    """Per pixel: the fill's coverage, the line's, and the inner lines' (0..1 each)."""
    k = size / 24.0
    t = LINE * k
    out = []
    for y in range(size):
        for x in range(size):
            d = sdf((x + 0.5) / k, (y + 0.5) / k) * k
            a_in = max(0.0, min(1.0, 0.5 - d))
            a_out = max(0.0, min(1.0, 0.5 - (d - t)))
            a_l = max(0.0, min(1.0, 0.5 - inner((x + 0.5) / k, (y + 0.5) / k) * k)) if inner and a_out > 0 else 0.0
            out.append((a_in, a_out, a_l))
    return out


def argb(cov, fill, line):
    """Premultiplied ARGB words, as the Xcursor format wants them."""
    words = []
    for a_in, a_out, a_l in cov:
        if a_out <= 0.0:
            words.append(0)
            continue
        f_cov = a_in * (1.0 - a_l)
        l_cov = a_out - f_cov
        r = fill[0] * f_cov + line[0] * l_cov
        g = fill[1] * f_cov + line[1] * l_cov
        b = fill[2] * f_cov + line[2] * l_cov
        a = int(round(a_out * 255))
        words.append((a << 24) | (int(round(r)) << 16) | (int(round(g)) << 8) | int(round(b)))
    return words


def xcursor(images):
    """One Xcursor file from [(nominal, w, h, xhot, yhot, words)], one image per size."""
    IMG = 0xFFFD0002
    n = len(images)
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, n)
    toc = b""
    body = b""
    pos = 16 + 12 * n
    for nominal, w, h, xh, yh, words in images:
        chunk = struct.pack("<9I", 36, IMG, nominal, 1, w, h, xh, yh, 0) + struct.pack("<%dI" % len(words), *words)
        toc += struct.pack("<III", IMG, nominal, pos)
        body += chunk
        pos += len(chunk)
    return header + toc + body


def write_themes(icons):
    """The two themes under ICONS (spark-white, spark-black); the files that changed."""
    todo = shapes()
    cov = {}
    for name, (sdf, hot, inner) in todo.items():
        cov[name] = [(size, coverage(sdf, inner, size), hot) for size in SIZES]
    for theme, (fill, line) in (("spark-white", WHITE), ("spark-black", BLACK)):
        d = os.path.join(icons, theme, "cursors")
        os.makedirs(d, exist_ok=True)
        for name, per_size in cov.items():
            images = []
            for size, c, hot in per_size:
                k = size / 24.0
                images.append((size, size, size, int(hot[0] * k), int(hot[1] * k), argb(c, fill, line)))
            path = os.path.join(d, name)
            with open(path, "wb") as f:
                f.write(xcursor(images))
            for alias in ALIASES.get(name, ()):
                ap = os.path.join(d, alias)
                if os.path.islink(ap) or os.path.exists(ap):
                    os.remove(ap)
                os.symlink(name, ap)
        with open(os.path.join(icons, theme, "index.theme"), "w") as f:
            f.write("[Icon Theme]\nName=%s\nComment=the spark pointer, %s, drawn by spark-shell\n" % (theme, theme.split("-")[1]))
        with open(os.path.join(icons, theme, "version"), "w") as f:
            f.write(VERSION + "\n")


def main(argv):
    if len(argv) == 2 and argv[1] == "--version":
        print(VERSION)
        return 0
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    write_themes(argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
