#!/usr/bin/env python3
"""The home dialog's transitions as first drawn, kept aside (nothing uses them;
the set chosen is in assets/transitions/): the logo (assets/logo.svg)
catching fire, waiting and going out, as GIFs in a palette's own colors,
nothing behind them.

    python3 assets/brand-transitions/make.py [PALETTE.env ...] [--out DIR]

Each palette (by default every themes/*.env) gets DIR/NAME/ (by default
assets/brand-transitions/NAME/):

    open.gif   once, 1.2 s: the cursor sparks, the S catches from its foot
               up, the chevron comes in; it ends on the whole mark
    wait.gif   loops, 1.6 s: the whole mark, the cursor blinking, a glow
               climbing the S, sparks off the cursor; it starts and ends
               on the whole mark, so it follows open.gif with no jump
    close.gif  once, 0.96 s: the S burns down toward the cursor, its
               sparks fly into it, the cursor goes out; it ends on nothing

and each again @2x. The colors are the palette's: the bands its yellow and
red (ANSI 3 and 1), the chevron its text, the cursor and the sparks its
accent. A GIF pixel is drawn or not, never half, so the mark is drawn with
hard edges (it is blocks already) and a color fading out is mixed toward
the dialog's surface, PANEL_BG (spark-shell's panel_load: the palette's
ground 9% of the way to its text), the ground it is drawn on. The
transparent index is that surface too, for a reader that ignores it.
"""

import math
import os
import random
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
FRAME_MS = 40  # 25 a second: GIF counts in hundredths, and browsers slow anything under 20
SCALES = (1, 2)
# foot's defaults, as spark-shell's FOOT_HEX: a palette's missing ANSI color
FOOT_HEX = "242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff".split()


# -- colors -------------------------------------------------------------------


def rgb(h):
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def hex_or(v, fallback):
    """#rrggbb as rrggbb in lowercase, else the fallback: spark-shell's hex_or."""
    v = v.strip().strip("\"'")
    if len(v) == 7 and v[0] == "#" and all(c in "0123456789abcdefABCDEF" for c in v[1:]):
        return v[1:].lower()
    return fallback


def hex_mix(a, b, pct):
    """spark-shell's hex_mix to the bit: shell arithmetic truncates toward zero."""
    out = []
    for x, y in zip(rgb(a), rgb(b)):
        d = (y - x) * pct
        out.append(x + (abs(d) // 100) * (1 if d >= 0 else -1))
    return "%02x%02x%02x" % tuple(out)


def mix(a, b, k):
    """a moved k (0 to 1) of the way to b, as an RGB tuple."""
    return tuple(round(x + (y - x) * k) for x, y in zip(a, b))


def step(k, n=8):
    """k held to n steps, so a GIF's colors stay few."""
    return round(max(0.0, min(1.0, k)) * n) / n


def luma(c):
    return (299 * c[0] + 587 * c[1] + 114 * c[2]) // 1000


def read_env(path):
    vals = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                vals[k.strip()] = v.strip()
    return vals


class Roles:
    """A palette's colors as the mark takes them."""

    def __init__(self, env):
        get = lambda k, d: hex_or(env.get(k, ""), d)
        ansi = [get("THEME_ANSI_%d" % i, FOOT_HEX[i]) for i in range(16)]
        bg, fg = get("THEME_BG", "242424"), get("THEME_FG", "ffffff")
        self.surface = rgb(hex_mix(bg, fg, 9))
        self.dark = luma(self.surface) < 128
        self.fg = rgb(fg)
        self.accent = rgb(get("THEME_ACCENT", ansi[4]))
        yellow, self.red = rgb(ansi[3]), rgb(ansi[1])
        # as the logo's two drawings are: on dark a yellow lifted, the yellow, the red;
        # on light the yellow, the yellow deepened, the red
        if self.dark:
            self.bands = [mix(yellow, (255, 255, 255), 0.3), yellow, self.red]
            self.hot = [mix(b, (255, 255, 255), 0.6) for b in self.bands]
        else:
            self.bands = [yellow, mix(yellow, (0, 0, 0), 0.25), self.red]
            self.hot = [mix(b, self.fg, 0.45) for b in self.bands]
        self.flare = mix(self.accent, self.fg, 0.5)

    def fade(self, c, k):
        """c gone k of the way into the surface: a fade on the ground it is drawn on."""
        return mix(c, self.surface, step(k))


# -- the mark -------------------------------------------------------------------


def mark():
    """The logo's shapes: the S's blocks (each with its band, 0 the top), the
    chevron's outline, the cursor; and the drawing's size."""
    root = ET.parse(os.path.join(REPO, "assets", "logo.svg")).getroot()
    tag = lambda e: e.tag.rsplit("}", 1)[-1]
    fills, cells, chevron, cursor = [], [], None, None
    for e in root:
        if tag(e) == "rect":
            r = tuple(float(e.get(k)) for k in ("x", "y", "width", "height"))
            if chevron is not None:  # the rect after the chevron is the cursor
                cursor = r
                continue
            f = e.get("fill")
            if f not in fills:
                fills.append(f)
            cells.append(Cell(r, fills.index(f)))
        elif tag(e) == "polyline":
            pts = [tuple(map(float, p.split(","))) for p in e.get("points").split()]
            chevron = stroke(pts, float(e.get("stroke-width")))
    _, _, w, h = map(float, root.get("viewBox").split())
    return cells, chevron, cursor, (w, h)


class Cell:
    def __init__(self, r, band):
        self.r, self.band = r, band
        self.cx, self.cy = r[0] + r[2] / 2, r[1] + r[3] / 2


def stroke(pts, width):
    """A polyline of two segments as the outline SVG draws: mitred, butt ends."""
    (a, b, c), h = pts, width / 2

    def normal(p, q):
        dx, dy = q[0] - p[0], q[1] - p[1]
        n = math.hypot(dx, dy)
        return (-dy / n * h, dx / n * h)

    def meet(p, d, q, e):  # the line p + t d meets q + s e
        den = d[0] * e[1] - d[1] * e[0]
        t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
        return (p[0] + t * d[0], p[1] + t * d[1])

    na, nb = normal(a, b), normal(b, c)
    da, db = (b[0] - a[0], b[1] - a[1]), (c[0] - b[0], c[1] - b[1])
    side = []
    for s in (1, -1):
        pa = (a[0] + s * na[0], a[1] + s * na[1])
        pc = (c[0] + s * nb[0], c[1] + s * nb[1])
        pb = (b[0] + s * nb[0], b[1] + s * nb[1])
        side.append((pa, meet(pa, da, pb, db), pc))
    (l0, l1, l2), (r0, r1, r2) = side
    return [l0, l1, l2, r2, r1, r0]


# -- drawing --------------------------------------------------------------------


def px(v, s):
    return math.floor(v * s + 0.5)


class Frame:
    """One frame's shapes in the drawing's units, each with its color, drawn in order."""

    def __init__(self):
        self.ops = []

    def rect(self, r, color, dx=0.0, dy=0.0):
        if color is not None:
            self.ops.append(("rect", (r[0] + dx, r[1] + dy, r[2], r[3]), color))

    def poly(self, pts, color, dx=0.0, dy=0.0):
        if color is not None:
            self.ops.append(("poly", [(x + dx, y + dy) for x, y in pts], color))

    def spark(self, x, y, size, color):
        self.rect((x - size / 2, y - size / 2, size, size), color)


def raster(frames, size, scale):
    """The frames as rows of color indices at scale, 0 nothing; and the colors, from 1."""
    w, h = px(size[0], scale), px(size[1], scale)
    index, images = {}, []
    for fr in frames:
        im = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(im)
        for kind, shape, color in fr.ops:
            if color not in index:
                index[color] = len(index) + 1
            i = index[color]
            if kind == "rect":
                x, y, rw, rh = shape
                x0, y0, x1, y1 = px(x, scale), px(y, scale), px(x + rw, scale), px(y + rh, scale)
                x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w), min(y1, h)
                if x1 > x0 and y1 > y0:
                    d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=i)
            else:
                d.polygon([(x * scale, y * scale) for x, y in shape], fill=i)
        images.append(im)
    return images, sorted(index, key=index.get)


def lzw(data, min_size):
    """GIF's LZW, code by code as omggif writes it, in sub-blocks of 255."""
    clear, eoi = 1 << min_size, (1 << min_size) + 1
    out, acc, nbits = bytearray(), 0, 0

    def emit(code, size):
        nonlocal acc, nbits
        acc |= code << nbits
        nbits += size
        while nbits >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            nbits -= 8

    size, nxt, table = min_size + 1, eoi + 1, {}
    emit(clear, size)
    prefix = data[0]
    for k in data[1:]:
        key = (prefix << 8) | k
        code = table.get(key)
        if code is not None:
            prefix = code
            continue
        emit(prefix, size)
        if nxt == 4096:
            emit(clear, size)
            size, nxt, table = min_size + 1, eoi + 1, {}
        else:
            if nxt >= 1 << size:
                size += 1
            table[key] = nxt
            nxt += 1
        prefix = k
    emit(prefix, size)
    emit(eoi, size)
    if nbits:
        out.append(acc & 0xFF)
    blocks = bytearray([min_size])
    for i in range(0, len(out), 255):
        blocks += bytes([len(out[i : i + 255])]) + out[i : i + 255]
    return bytes(blocks + b"\0")


def gif(frames, size, scale, surface, path, loop):
    """The frames as a GIF89a at scale: one color table, index 0 nothing (its
    color the surface), every frame cleared to nothing after it (disposal 2), so
    each holds only its drawn box; a frame like the one before it lengthens it."""
    images, colors = raster(frames, size, scale)
    if len(colors) > 255:
        sys.exit("%s: %d colors, a GIF holds 255 and nothing" % (path, len(colors)))
    bits = max(1, (len(colors)).bit_length())  # a table of 2**bits holds nothing and the colors
    table = bytes(surface) + b"".join(bytes(c) for c in colors)
    table += b"\0" * (3 * (1 << bits) - len(table))
    held = []  # (image, hundredths)
    for im in images:
        if held and held[-1][0].tobytes() == im.tobytes():
            held[-1][1] += FRAME_MS // 10
        else:
            held.append([im, FRAME_MS // 10])
    w, h = images[0].size
    le = lambda v: v.to_bytes(2, "little")
    out = bytearray(b"GIF89a" + le(w) + le(h) + bytes([0xF0 | (bits - 1), 0, 0]) + table)
    if loop:
        out += b"\x21\xff\x0bNETSCAPE2.0\x03\x01" + le(0) + b"\0"
    for im, cs in held:
        box = im.getbbox() or (0, 0, 1, 1)  # nothing drawn: one pixel of nothing
        part = im.crop(box)
        out += b"\x21\xf9\x04" + bytes([(2 << 2) | 1]) + le(cs) + b"\0\0"
        out += b"\x2c" + le(box[0]) + le(box[1]) + le(part.width) + le(part.height) + b"\0"
        out += lzw(part.tobytes(), max(2, bits))
    out += b"\x3b"
    with open(path, "wb") as f:
        f.write(out)


def whole(fr, cells, chevron, cursor, ro, band=None):
    for c in cells:
        fr.rect(c.r, band(c) if band else ro.bands[c.band])
    fr.poly(chevron, ro.fg)
    fr.rect(cursor, ro.accent)


def centre(r):
    return (r[0] + r[2] / 2, r[1] + r[3] / 2)


# -- the three ------------------------------------------------------------------


def open_frames(ro, cells, chevron, cursor):
    """The cursor sparks; the spark leaps to the S's foot; the S catches from
    there to its head, each block an ember, white hot, then its band; the
    chevron comes in from the left; it ends on the whole mark."""
    n, frames = 30, []
    cx, cy = centre(cursor)
    start, foot = (cx, cursor[1] - 2), (75.0, 96.0)
    dist = lambda c: math.hypot(c.cx - foot[0], c.cy - foot[1])
    far = max(dist(c) for c in cells)
    lit = {id(c): 6 + round(dist(c) / far * 14) for c in cells}  # frames 6 to 20
    rnd = random.Random(3)
    # a spark off the S's right side as each block there catches
    sparks = [(lit[id(c)], c.r[0] + c.r[2], c.cy, rnd.uniform(1.0, 2.2), rnd.uniform(2.2, 3.4)) for c in cells if c.cx >= 60]

    def leap(u):  # the leap from the cursor to the foot, an arc
        x = start[0] + (foot[0] - start[0]) * u
        y = start[1] + (foot[1] - start[1]) * u - 28 * 4 * u * (1 - u)
        return x, y

    for f in range(n):
        fr = Frame()
        for c in cells:
            a = f - lit[id(c)]
            b = c.band
            col = None if a < 0 else ro.fade(ro.bands[b], 0.6) if a == 0 else ro.hot[b] if a == 1 else mix(ro.hot[b], ro.bands[b], 0.5) if a == 2 else ro.bands[b]
            fr.rect(c.r, col)
        if f >= 12:
            k = max(0.0, 1 - (f - 12) / 5)
            fr.poly(chevron, ro.fade(ro.fg, k), dx=-6 * k)
        fr.rect(cursor, ro.fade(ro.accent, 0.5) if f == 0 else ro.flare if f == 1 else ro.accent)
        if 1 <= f <= 6:
            for back, size, k in ((2, 2, 0.75), (1, 2.5, 0.4), (0, 3.5, 0.0)):
                u = (f - 1 - back * 0.5) / 5
                if u >= 0:
                    x, y = leap(u)
                    fr.spark(x, y, size, ro.fade(ro.flare if back == 0 else ro.accent, k))
        for t0, x0, y0, vx, vy in sparks:
            a = f - t0
            if 0 <= a < 8:
                fr.spark(x0 + 2 + vx * a, y0 - vy * a, 2, ro.fade(ro.accent if a < 3 else ro.bands[0], a / 8))
        frames.append(fr)
    return frames


def wait_frames(ro, cells, chevron, cursor):
    """The whole mark: the cursor blinks twice, a glow climbs the S from its foot
    to its head, three sparks rise off the cursor; frame 0 is the whole mark."""
    n, frames = 40, []
    cx, cy = centre(cursor)
    births = (2, 14, 24)  # each lives 14 frames: none crosses the loop's seam
    for f in range(n):
        fr = Frame()
        yc = 125 - (f / (n * 0.75)) * 150  # the glow's middle, under the foot to over the head
        glow = lambda c: mix(ro.bands[c.band], ro.hot[c.band], step(max(0.0, 1 - abs(c.cy - yc) / 18) * 0.45))
        for c in cells:
            fr.rect(c.r, glow(c))
        fr.poly(chevron, ro.fg)
        fr.rect(cursor, ro.accent if (f // 10) % 2 == 0 else None)
        for i, t0 in enumerate(births):
            a = f - t0
            if 0 <= a < 14:
                x = cx + math.sin(a * 0.55 + i * 2.1) * 3.5 + (i - 1) * a * 0.4
                fr.spark(x, cursor[1] - 3 - a * 4.2, 2.5 if a < 4 else 2, ro.fade(ro.flare if a < 2 else ro.accent, a / 14))
        frames.append(fr)
    return frames


def close_frames(ro, cells, chevron, cursor):
    """The S burns down from its head toward the cursor, each block flaring,
    an ember, gone; every third one's spark flies into the cursor; the chevron
    goes right and out; the cursor flares and goes out; it ends on nothing."""
    n, frames = 24, []
    cx, cy = centre(cursor)
    dist = lambda c: math.hypot(c.cx - cx, c.cy - cy)
    near, far = min(dist(c) for c in cells), max(dist(c) for c in cells)
    out = {id(c): 1 + round((far - dist(c)) / (far - near) * 11) for c in cells}  # frames 1 to 12
    flyers = [c for i, c in enumerate(sorted(cells, key=lambda c: out[id(c)])) if i % 3 == 1]
    for f in range(n):
        fr = Frame()
        for c in cells:
            a = f - out[id(c)]
            col = ro.bands[c.band] if a < 0 else ro.hot[c.band] if a == 0 else ro.fade(ro.red, (0.2, 0.5, 0.8)[a - 1]) if a < 4 else None
            fr.rect(c.r, col)
        if f < 15:
            k = max(0.0, (f - 9) / 5)
            fr.poly(chevron, ro.fade(ro.fg, k) if k < 1 else None, dx=4 * k)
        cur = ro.accent if f < 18 else ro.flare if f == 18 else ro.accent if f == 19 else ro.fade(ro.accent, 0.5) if f == 20 else ro.fade(ro.accent, 0.8) if f == 21 else None
        fr.rect(cursor, cur)
        for c in flyers:
            a = f - out[id(c)] - 1
            if 0 <= a < 6:
                u = ((a + 1) / 6) ** 2  # slow off the block, fast into the cursor
                x, y = c.cx + (cx - c.cx) * u, c.cy + (cy - c.cy) * u - 10 * math.sin(u * math.pi)
                fr.spark(x, y, 2.5, ro.flare if a < 2 else ro.accent)
        frames.append(fr)
    return frames


ANIMS = (("open", open_frames, False), ("wait", wait_frames, True), ("close", close_frames, False))


def main(argv):
    out_dir, paths = HERE, []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_dir = next(it)
        else:
            paths.append(a)
    if not paths:
        d = os.path.join(REPO, "themes")
        paths = sorted(os.path.join(d, p) for p in os.listdir(d) if p.endswith(".env"))
    cells, chevron, cursor, size = mark()
    for p in paths:
        name = os.path.basename(p)[: -len(".env")] if p.endswith(".env") else os.path.basename(p)
        ro = Roles(read_env(p))
        d = os.path.join(out_dir, name)
        os.makedirs(d, exist_ok=True)
        for anim, make, loop in ANIMS:
            frames = make(ro, cells, chevron, cursor)
            for s in SCALES:
                gif(frames, size, s, ro.surface, os.path.join(d, "%s%s.gif" % (anim, "" if s == 1 else "@%dx" % s)), loop)
        print("%s: %s, on %02x%02x%02x" % (name, "dark" if ro.dark else "light", *ro.surface))


if __name__ == "__main__":
    main(sys.argv[1:])
