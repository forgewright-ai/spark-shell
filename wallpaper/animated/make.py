#!/usr/bin/env python3
"""Animated wallpapers: small scenes, each a quiet loop with a joke in it,
drawn in a palette's own colors, in collections: a look and feel for each
persona.

    python3 wallpaper/animated/make.py [--collection NAME] [--scene NAME ...] [PALETTE.env ...]
                                       [--size WxH] [--out DIR] [--preset NAME]
    python3 wallpaper/animated/make.py --scene NAME --still T[,T...] --png DIR [PALETTE.env]

cozy: warm and playful, a picture book for grown-ups

    onsen     a capybara soaks in a hot spring in the snow, a yuzu on its
              head; the yuzu rolls off, the capybara goes under, and comes
              up with the yuzu back on its head
    duck      a rubber duck on a pond, being told about a bug: a question,
              then an idea; a frog fixes a bug of its own by eating it
    reef      under the sea the fish are prompts: a school of > fish, a ~
              eel, a * starfish, and one < swimming the wrong way
    campfire  a raccoon toasts a marshmallow; it catches fire, the raccoon
              blows it out, and eats it anyway
    ufo       over the dunes a saucer beams up a cow, has a look, and puts
              it back
    pigeons   IP over avian carriers (RFC 1149): pigeons carry envelopes
              over the roofs; one drops its packet and another sends it again

night: the night-shift builder, cinematic; weather, scale and light, a dry
joke, graded like a film (a vignette, a grain that holds still)

    garoa     Sao Paulo in the drizzle at night, the Copan and the masts of
              Paulista; a helicopter finds its roof taken and takes the next
    horizon   a black hole over the edge of an ice planet, its disc turning;
              a probe falls in and, as seen from here, never quite does
    watch     a night sail on a long swell, a lighthouse sweeping; beating
              upwind, it tacks twice a loop
    problem   a bouldering wall under one light, chalk in the beam; the
              climber comes off the crux, chalks up, starts again
    hangar    a mech in its gantry; its visor wakes, the technician jumps,
              the welder at its knee never looks up
    crossing  a level crossing at dusk; the bells, the arm, a train, and
              after it the crows on the wire in another order

Each scene is a loop of 24 seconds at 24 frames a second, 1920 by 1080 by
default, H.264 in an MP4 that ends where it begins: DIR/SCENE/NAME.mp4 for
each palette (by default every themes/*.env). The colors are the palette's,
by the roles the shipped wallpapers use (bg, fg, accent, muted, ansi_N, and
A+B:PCT, the first moved PCT of the way to the second): a dark palette's
scene is at night and a light one's by day. Most of the picture is still;
what moves is small and slow, so it can sit behind the terminals.
"""

import math
import os
import random
import subprocess
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
W, H, FPS = 1920, 1080, 24
FOOT_HEX = "242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff".split()


# -- the palette ----------------------------------------------------------------


def rgb(h):
    return tuple(float(int(h[i : i + 2], 16)) for i in (0, 2, 4))


def hex_or(v, fallback):
    v = v.strip().strip("\"'")
    if len(v) == 7 and v[0] == "#" and all(c in "0123456789abcdefABCDEF" for c in v[1:]):
        return v[1:].lower()
    return fallback


def hex_mix(a, b, pct):
    """spark-shell's hex_mix to the bit: shell arithmetic truncates toward zero."""
    out = []
    for x, y in zip(rgb(a), rgb(b)):
        d = int(y - x) * pct
        out.append(int(x) + (abs(d) // 100) * (1 if d >= 0 else -1))
    return "%02x%02x%02x" % tuple(out)


def mix(a, b, k):
    return tuple(x + (y - x) * k for x, y in zip(a, b))


def read_env(path):
    vals = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                vals[k.strip()] = v.strip()
    return vals


class Palette:
    """A palette's colors by the wallpapers' roles: p("bg+accent:7") as spark-shell's wall_role_hex."""

    def __init__(self, env):
        get = lambda k, d: hex_or(env.get(k, ""), d)
        self.hex = {"ansi_%d" % i: get("THEME_ANSI_%d" % i, FOOT_HEX[i]) for i in range(16)}
        self.hex.update(bg=get("THEME_BG", "242424"), fg=get("THEME_FG", "ffffff"), black="000000", white="ffffff")
        self.hex["accent"] = get("THEME_ACCENT", self.hex["ansi_4"])
        self.hex["muted"] = get("THEME_MUTED", self.hex["ansi_8"])
        bg = rgb(self.hex["bg"])
        self.dark = (299 * bg[0] + 587 * bg[1] + 114 * bg[2]) / 1000 < 128

    def role(self, r):
        if "+" in r:
            a, rest = r.split("+", 1)
            b, pct = rest.split(":")
            return hex_mix(self.role(a), self.role(b), int(pct))
        return self.hex[r]

    def __call__(self, r):
        return rgb(self.role(r))

    def pick(self, dark, light):
        return self(dark if self.dark else light)


# -- drawing: shapes in the drawing's units, 1920 by 1080, whatever the size -------


class Canvas:
    def __init__(self, s):
        self.s, self.w, self.h = s, round(W * s), round(H * s)

    def box(self, x0, y0, x1, y1):
        """A box in units as pixel rows and columns on the canvas, or None off it."""
        px0, px1 = max(0, math.floor(x0 * self.s) - 1), min(self.w, math.ceil(x1 * self.s) + 1)
        py0, py1 = max(0, math.floor(y0 * self.s) - 1), min(self.h, math.ceil(y1 * self.s) + 1)
        return None if px1 <= px0 or py1 <= py0 else (px0, py0, px1, py1)


def ellipse_pts(cx, cy, rx, ry, rot=0.0, n=None, a0=0.0, a1=2 * math.pi):
    n = n or max(24, min(400, int(2 * math.pi * max(rx, ry) / 3)))
    c, s = math.cos(rot), math.sin(rot)
    out = []
    for i in range(n + (0 if a1 - a0 >= 2 * math.pi - 1e-9 else 1)):
        a = a0 + (a1 - a0) * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * c - y * s, cy + x * s + y * c))
    return out


def spline(pts, closed=True, per=10):
    """A Catmull-Rom curve through the points, as a polyline."""
    n = len(pts)
    out = []
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0, p1 = pts[(i - 1) % n if closed else max(i - 1, 0)], pts[i]
        p2, p3 = pts[(i + 1) % n], pts[(i + 2) % n if closed else min(i + 2, n - 1)]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    if not closed:
        out.append(pts[-1])
    return out


def bezier(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        u = i / n
        v = 1 - u
        out.append(tuple(v**3 * p0[j] + 3 * v * v * u * p1[j] + 3 * v * u * u * p2[j] + u**3 * p3[j] for j in (0, 1)))
    return out


class Shape:
    """A union of polygons, ellipses and round strokes, in units."""

    def __init__(self):
        self.cmds = []

    def poly(self, pts):
        self.cmds.append(("poly", [tuple(p) for p in pts]))
        return self

    def ellipse(self, cx, cy, rx, ry, rot=0.0):
        return self.poly(ellipse_pts(cx, cy, rx, ry, rot))

    def circle(self, cx, cy, r):
        return self.ellipse(cx, cy, r, r)

    def line(self, pts, w):
        self.cmds.append(("line", [tuple(p) for p in pts], w))
        return self

    def rect(self, x, y, w, h):
        return self.poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)])

    def moved(self, dx=0.0, dy=0.0, k=1.0, rot=0.0, ox=0.0, oy=0.0, kx=1.0):
        """The shape scaled by kx across (-1 a mirror), turned by rot and scaled by k
        about (ox, oy), then moved."""
        c, s = math.cos(rot), math.sin(rot)
        f = lambda p: (ox + ((p[0] - ox) * kx * c - (p[1] - oy) * s) * k + dx, oy + ((p[0] - ox) * kx * s + (p[1] - oy) * c) * k + dy)
        out = Shape()
        for cmd in self.cmds:
            if cmd[0] == "poly":
                out.cmds.append(("poly", [f(p) for p in cmd[1]]))
            else:
                out.cmds.append(("line", [f(p) for p in cmd[1]], cmd[2] * k))
        return out

    def bounds(self):
        xs, ys = [], []
        for cmd in self.cmds:
            pad = cmd[2] / 2 if cmd[0] == "line" else 0
            for x, y in cmd[1]:
                xs += [x - pad, x + pad]
                ys += [y - pad, y + pad]
        return min(xs), min(ys), max(xs), max(ys)


def cover(cv, shape, ss=4, above=None, below=None, soft=0.0, clip=None):
    """A shape's coverage over its pixels: drawn ss times larger and averaged down.
    above: only what is above that height (a waterline); below: only what is under
    it; soft: blurred by that many units; clip: a coverage of the whole canvas it
    stays inside (a pool)."""
    if not shape.cmds:
        return None
    x0, y0, x1, y1 = shape.bounds()
    b = cv.box(x0 - 3 * soft, y0 - 3 * soft, x1 + 3 * soft, y1 + 3 * soft)
    if b is None:
        return None
    px0, py0, px1, py1 = b
    w, h = px1 - px0, py1 - py0
    im = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(im)
    k = cv.s * ss
    tr = lambda p: ((p[0] * cv.s - px0) * ss, (p[1] * cv.s - py0) * ss)
    for cmd in shape.cmds:
        if cmd[0] == "poly":
            if len(cmd[1]) >= 3:
                d.polygon([tr(p) for p in cmd[1]], fill=255)
        else:
            pts, lw = [tr(p) for p in cmd[1]], max(1.0, cmd[2] * k)
            if len(pts) > 1:
                d.line(pts, fill=255, width=int(round(lw)), joint="curve")
            r = lw / 2
            for x, y in (pts[0], pts[-1]):
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    cov = np.asarray(im, np.float32).reshape(h, ss, w, ss).mean(axis=(1, 3)) / 255
    if soft:
        cov = np.asarray(Image.fromarray(np.rint(cov * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(soft * cv.s)), np.float32) / 255
    if clip is not None:
        cov = cov * clip[py0:py1, px0:px1]
    rows = (np.arange(py0, py1, dtype=np.float32) + 0.5)[:, None]
    if above is not None:
        cov = cov * np.clip(above * cv.s - rows + 0.5, 0, 1)
    if below is not None:
        cov = cov * np.clip(rows - below * cv.s + 0.5, 0, 1)
    return cov, slice(py0, py1), slice(px0, px1)


def dot(cv, cx, cy, r):
    """A disc's coverage, worked out exactly: the quick way for the many small round things."""
    b = cv.box(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
    if b is None or r <= 0:
        return None
    px0, py0, px1, py1 = b
    xs = (np.arange(px0, px1, dtype=np.float32) + 0.5)[None, :] / cv.s
    ys = (np.arange(py0, py1, dtype=np.float32) + 0.5)[:, None] / cv.s
    cov = np.clip(0.5 - (np.hypot(xs - cx, ys - cy) - r) * cv.s, 0, 1)
    return cov, slice(py0, py1), slice(px0, px1)


class Layer:
    __slots__ = ("cov", "rows", "cols", "color", "alpha", "mode")

    def __init__(self, covered, color, alpha=1.0, mode="over"):
        self.cov, self.rows, self.cols = covered if covered else (None, None, None)
        self.color, self.alpha, self.mode = color, alpha, mode


def paint(img, layers):
    """Each layer over what is there; a light ("add") adds to it instead."""
    for ly in layers:
        if ly.cov is None or ly.alpha <= 0:
            continue
        a = (ly.cov * np.float32(min(1.0, ly.alpha)))[..., None]
        sub = img[ly.rows, ly.cols]
        if ly.mode == "add":
            sub += np.asarray(ly.color, np.float32) * a
        else:
            sub += (np.asarray(ly.color, np.float32) - sub) * a


def L(cv, shape, color, alpha=1.0, ss=4, above=None, below=None, soft=0.0, clip=None, mode="over"):
    return Layer(cover(cv, shape, ss, above, below, soft, clip), color, alpha, mode)


def glow(cv, x, y, r, color, alpha=1.0, soft=None):
    """A light: a soft disc added to what is under it."""
    return L(cv, Shape().circle(x, y, r), color, alpha, ss=1, soft=r * 0.8 if soft is None else soft, mode="add")


def vgrad(cv, x0, y0, x1, y1, stops):
    """A box filled top to bottom through colors: stops is [(y, color), ...]."""
    b = cv.box(x0, y0, x1, y1)
    if b is None:
        return Layer(None, (0, 0, 0))
    px0, py0, px1, py1 = b
    ys = (np.arange(py0, py1, dtype=np.float32) + 0.5) / cv.s
    sy = np.array([s[0] for s in stops], np.float32)
    col = np.stack([np.interp(ys, sy, np.array([s[1][k] for s in stops], np.float32)) for k in range(3)], -1)[:, None, :]
    return Layer((np.ones((py1 - py0, px1 - px0), np.float32), slice(py0, py1), slice(px0, px1)), col)


def full(cv, shape, ss=2):
    """A shape's coverage as an array the size of the canvas: a region to clip to."""
    out = np.zeros((cv.h, cv.w), np.float32)
    got = cover(cv, shape, ss)
    if got:
        out[got[1], got[2]] = got[0]
    return out


def D(cv, cx, cy, r, color, alpha=1.0):
    return Layer(dot(cv, cx, cy, r), color, alpha)


# -- a few letters, drawn as strokes in a box one unit high -------------------------

GLYPHS = {
    "?": [[(0.15, 0.25), (0.25, 0.08), (0.5, 0.0), (0.75, 0.08), (0.82, 0.28), (0.7, 0.45), (0.5, 0.55), (0.5, 0.7)], [(0.5, 0.95)]],
    "!": [[(0.5, 0.0), (0.5, 0.68)], [(0.5, 0.95)]],
    "z": [[(0.15, 0.35), (0.85, 0.35), (0.15, 1.0), (0.85, 1.0)]],
    "v": [[(0.1, 0.55), (0.38, 0.88), (0.95, 0.12)]],  # a tick
    "m": [[(0.05, 1.0), (0.05, 0.4), (0.12, 0.33), (0.28, 0.33), (0.36, 0.42), (0.36, 1.0)], [(0.36, 0.42), (0.44, 0.33), (0.6, 0.33), (0.67, 0.42), (0.67, 1.0)]],
    "o": [[(0.5 + 0.3 * math.cos(a * math.pi / 8), 0.67 + 0.33 * math.sin(a * math.pi / 8)) for a in range(17)]],
    "n": [[(0.6, 0.8), (0.6, 0.0)], [(0.6, 0.0), (0.95, 0.15), (0.95, 0.3), (0.6, 0.38)], [(0.6, 0.8)]],  # a quaver: stem, flag, head
}


def glyph(shape, ch, x, y, size, w):
    """Draw one letter into a shape: its top left at (x, y), size units high."""
    for stroke in GLYPHS[ch]:
        pts = [(x + px * size * 0.7, y + py * size) for px, py in stroke]
        if len(pts) == 1:
            shape.circle(pts[0][0], pts[0][1], w * 0.75)
        else:
            shape.line(pts, w)
    return shape


# -- easing ---------------------------------------------------------------------


def clamp(u, a=0.0, b=1.0):
    return a if u < a else b if u > b else u


def ease_io(u):
    u = clamp(u)
    return u * u * (3 - 2 * u)


def ease_in(u):
    return clamp(u) ** 2


def ease_out(u):
    return 1 - (1 - clamp(u)) ** 2


def bump(u):
    return math.sin(math.pi * u) if 0 < u < 1 else 0.0


def window(t, t0, t1):
    """0 to 1 as t goes from t0 to t1."""
    return clamp((t - t0) / (t1 - t0))


def wave(t, period, phase=0.0):
    return math.sin(2 * math.pi * (t / period + phase))


# -- the scenes -----------------------------------------------------------------


class Scene:
    name, seconds = "", 24

    def back(self, cv, p):  # drawn once: what is behind everything that moves
        return []

    def front(self, cv, p):  # drawn once, over what moves
        return []

    def under(self, cv, p, t):  # what moves, under the front
        return []

    def over(self, cv, p, t):  # what moves, over the front
        return []

    def ground(self, p):
        return p("bg")

    def finish(self, cv, img, p):  # the grade over the whole frame: none for these
        return img


class Cinema(Scene):
    """A scene graded like a film: its corners darker, a grain that holds still
    (it costs the video nothing, and it keeps a dark sky from banding)."""

    vignette, grain = 0.35, 1.6

    def finish(self, cv, img, p):
        store = self.__dict__.setdefault("_grade", {})
        key = (cv.w, p.dark)
        if key not in store:  # a light palette: a softer edge and less grain, as a print is
            ys = (np.arange(cv.h, dtype=np.float32) + 0.5) / cv.h - 0.5
            xs = (np.arange(cv.w, dtype=np.float32) + 0.5) / cv.w - 0.5
            r2 = (xs[None, :] * 1.15) ** 2 + (ys[:, None] * 1.35) ** 2
            k = self.vignette * (1.0 if p.dark else 0.3)
            v = (1 - k * np.clip(r2 / 0.5, 0, 1) ** 1.4)[..., None].astype(np.float32)
            g = np.random.default_rng(7).normal(0, self.grain * (1.0 if p.dark else 0.6), (cv.h, cv.w, 1)).astype(np.float32)
            store[key] = (v, g)
        v, g = store[key]
        return img * v + g


class Onsen(Scene):
    name = "onsen"
    PX, PY, PRX, PRY = 1120.0, 846.0, 430.0, 118.0  # the pool
    CX, CY = 1030.0, 836.0  # the capybara: its waterline under the neck

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            ink = p.pick("ansi_0", "fg")  # what darkens: the black slot on dark, the text on light
            capy = mix(p("ansi_3+ansi_1:26"), ink, 0.3 if dk else 0.26)
            self._c = (p, dict(
                sky=p("bg"), band=p.pick("bg+fg:4", "bg+fg:3"),
                moon=p.pick("fg+ansi_3:18", "ansi_3+bg:30"), halo1=p.pick("bg+accent:9", "bg+ansi_3:14"), halo2=p.pick("bg+accent:5", "bg+ansi_3:7"),
                far=p.pick("bg+fg:7", "bg+fg:6"), near=p.pick("bg+fg:11", "bg+fg:10"), cap=p.pick("bg+fg:26", "bg+white:70"),
                pine=p.pick("ansi_0+ansi_2:14", "bg+ansi_2:42"), pine2=p.pick("ansi_0+ansi_2:22", "bg+ansi_2:58"),
                snow=p.pick("bg+fg:17", "bg+white:55"), shade=p.pick("bg+fg:12", "bg+fg:8"),
                rock=p.pick("bg+ansi_8:60", "bg+ansi_8:42"), rock2=p.pick("bg+ansi_8:40", "bg+ansi_8:60"),
                water=p.pick("bg+ansi_6:34", "bg+ansi_6:32"), deep=p.pick("bg+ansi_6:24", "bg+ansi_6:44"), shine=p.pick("bg+ansi_6:58", "ansi_6+white:45"),
                steam=p.pick("fg", "white"), flake=p.pick("fg", "bg+fg:28"),
                capy=capy, capy2=mix(capy, ink, 0.35), capy3=mix(capy, p.pick("fg", "white"), 0.18), blush=p("ansi_1"), ink=mix(ink, capy, 0.15),
                yuzu=mix(p("ansi_3"), p("white"), 0.12 if dk else 0.0), yuzu2=mix(p("ansi_3"), p("ansi_1"), 0.25), leaf=p("ansi_2"),
                glow=p("ansi_3"), dark=dk,
            ))
        return self._c[1]

    def ground(self, p):
        return self.colors(p)["sky"]

    def back(self, cv, p):
        c = self.colors(p)
        out = []
        mx, my = 1490.0, 250.0
        out += [D(cv, mx, my, 165, c["halo2"]), D(cv, mx, my, 112, c["halo1"]), D(cv, mx, my, 62, c["moon"])]
        rnd = random.Random(4)
        for x, y in [(rnd.uniform(0, W), rnd.uniform(40, 420)) for _ in range(46)]:
            if math.hypot(x - mx, y - my) > 190:
                out.append(D(cv, x, y, rnd.choice((1.1, 1.4, 1.8)), c["flake"], 0.35 if p.dark else 0.0))
        for color, base, peaks in (
            (c["far"], 660, [(0, 600), (160, 520), (330, 470), (520, 545), (700, 500), (880, 430), (1080, 515), (1260, 470), (1420, 540), (1620, 455), (1800, 520), (1920, 490)]),
            (c["near"], 700, [(0, 640), (230, 560), (430, 625), (640, 575), (820, 640), (1000, 590), (1180, 650), (1390, 585), (1600, 640), (1760, 600), (1920, 630)]),
        ):
            out.append(L(cv, Shape().poly([(0, base + 60)] + peaks + [(W, base + 60)]), color, ss=2))
            caps = Shape()
            for i in range(1, len(peaks) - 1):
                (x0, y0), (x1, y1), (x2, y2) = peaks[i - 1], peaks[i], peaks[i + 1]
                if y1 < y0 and y1 < y2:
                    k = 0.28
                    a, b = (x1 + (x0 - x1) * k, y1 + (y0 - y1) * k), (x1 + (x2 - x1) * k, y1 + (y2 - y1) * k)
                    caps.poly([a, (x1, y1), b, (b[0] - (b[0] - x1) * 0.35, b[1] + 6), ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 4), (a[0] + (x1 - a[0]) * 0.35, a[1] + 7)])
            out.append(L(cv, caps, c["cap"], 0.8 if p.dark else 0.9, ss=2))
        out.append(L(cv, Shape().poly([(0, 720)] + [(x, 712 + 9 * math.sin(x / 210)) for x in range(0, W + 1, 40)] + [(W, H), (0, H)]), c["snow"], ss=2))
        rnd = random.Random(7)
        trees = sorted([(rnd.uniform(-20, W + 20), rnd.uniform(58, 118), rnd.random()) for _ in range(34)], key=lambda t: t[1])
        for x, h, r in trees:
            base = 724 + 9 * math.sin(x / 210) + (h - 58) * 0.12
            col = c["pine2"] if r > 0.5 else c["pine"]
            sh, sn = Shape(), Shape()
            for i in range(3):
                y1 = base - h * (0.18 + 0.29 * i)
                hw = h * (0.34 - 0.08 * i)
                sh.poly([(x - hw, y1), (x, y1 - h * 0.36), (x + hw, y1)])
                sn.poly([(x - hw * 0.35, y1 - h * 0.24), (x, y1 - h * 0.36), (x + hw * 0.35, y1 - h * 0.24), (x, y1 - h * 0.28)])
            sh.rect(x - 2.5, base - h * 0.2, 5, h * 0.2)
            out += [L(cv, sh, col, ss=2), L(cv, sn, c["cap"], 0.9, ss=2)]
        drift = Shape()
        for x0, w in ((0, 420), (380, 300), (1550, 380)):
            drift.ellipse(x0 + w / 2, 742, w / 2, 18)
        out.append(L(cv, drift, c["shade"], 0.55, ss=2))
        out += self.lantern(cv, c, 560.0, 812.0)
        # the pool: its far rocks, the water, its light
        px, py, rx, ry = self.PX, self.PY, self.PRX, self.PRY
        out.append(L(cv, Shape().ellipse(px, py + 6, rx + 30, ry + 24), c["shade"], ss=2))
        for a, s in self.rocks(range(180, 361, 18)):
            out += self.rock(cv, c, px + (rx + 8) * math.cos(a), py + (ry + 6) * math.sin(a) - 4, s)
        out.append(L(cv, Shape().ellipse(px, py, rx, ry), c["water"], ss=2))
        out.append(L(cv, Shape().ellipse(px + 30, py + 18, rx * 0.7, ry * 0.56), c["deep"], 0.8, ss=1, soft=26, clip=self.pool(cv)))
        out.append(L(cv, Shape().ellipse(1440, py - 30, 110, 16), c["moon"], 0.16, ss=1, soft=10, clip=self.pool(cv)))  # the moon on the water
        return out

    def rocks(self, angles):
        rnd = random.Random(12)
        return [(math.radians(a + rnd.uniform(-5, 5)), rnd.uniform(0.75, 1.25)) for a in angles]

    def rock(self, cv, c, x, y, s):
        body = Shape().poly(spline([(x - 44 * s, y + 8), (x - 34 * s, y - 20 * s), (x - 6 * s, y - 30 * s), (x + 30 * s, y - 22 * s), (x + 46 * s, y + 4), (x + 20 * s, y + 18 * s), (x - 24 * s, y + 18 * s)], per=6))
        cap = Shape().poly(spline([(x - 34 * s, y - 14 * s), (x - 6 * s, y - 31 * s), (x + 30 * s, y - 21 * s), (x + 22 * s, y - 13 * s), (x - 4 * s, y - 20 * s), (x - 22 * s, y - 9 * s)], per=6))
        return [L(cv, body, c["rock"], ss=2), L(cv, Shape().ellipse(x + 12 * s, y + 6, 26 * s, 10 * s), c["rock2"], 0.5, ss=2), L(cv, cap, c["cap"], 0.85, ss=2)]

    def lantern(self, cv, c, x, y):
        st = Shape()
        st.rect(x - 34, y - 14, 68, 14).rect(x - 12, y - 92, 24, 80).rect(x - 30, y - 112, 60, 20)
        st.rect(x - 26, y - 168, 52, 56)
        st.poly([(x - 62, y - 168), (x - 40, y - 186), (x + 40, y - 186), (x + 62, y - 168), (x + 50, y - 162), (x - 50, y - 162)])
        st.ellipse(x, y - 196, 10, 12)
        snow = Shape().poly(spline([(x - 60, y - 170), (x - 38, y - 192), (x + 38, y - 192), (x + 60, y - 170), (x + 30, y - 182), (x - 30, y - 182)], per=6))
        snow.ellipse(x, y - 204, 9, 6).ellipse(x - 2, y - 116, 30, 6)
        return [L(cv, Shape().ellipse(x + 12, y + 2, 64, 12), c["shade"], 0.8, ss=2), L(cv, st, c["rock"], ss=2),
                L(cv, Shape().rect(x - 14, y - 156, 28, 34), c["glow"], 0.75), L(cv, snow, c["snow"], ss=2),
                L(cv, Shape().circle(x, y - 139, 40), c["glow"], 0.22 if c["dark"] else 0.12, ss=1, soft=30)]

    def pool(self, cv):
        if getattr(self, "_pool", (None,))[0] != cv.w:
            self._pool = (cv.w, full(cv, Shape().ellipse(self.PX, self.PY, self.PRX, self.PRY)))
        return self._pool[1]

    def front(self, cv, p):
        c = self.colors(p)
        out = []
        for a, s in self.rocks(range(0, 181, 15)):
            out += self.rock(cv, c, self.PX + (self.PRX + 12) * math.cos(a), self.PY + (self.PRY + 10) * math.sin(a) + 4, s * 1.1)
        return out

    # -- the capybara, in its own units: (0, 0) the waterline under its neck, the snout to the left
    HEAD = [(-18, -122), (-80, -132), (-138, -122), (-160, -100), (-166, -66), (-152, -40), (-112, -30), (-44, -26), (8, -40)]
    TOP = (-76, -152)  # where the yuzu sits

    def capybara(self, cv, c, t, dip, look, eyes_open):
        """The capybara's layers: dip is how far down it has gone (0 up, 1 under)."""
        x0, y0 = self.CX, self.CY + 175 * ease_io(dip) + 1.5 * wave(t, 6)
        wl = self.CY  # the water's level: nothing of it shows below
        breathe = 1 + 0.035 * wave(t, 4)
        at = lambda pts: [(x0 + x, y0 + y) for x, y in pts]
        back = [(-130, 6), (-70, -26), (-6, -60 * breathe), (56, -78 * breathe), (122, -74 * breathe), (178, -50 * breathe), (216, -14), (236, 30), (40, 40)]
        body = Shape().poly(spline(at(back), per=10))
        head = Shape().poly(spline(at(self.HEAD), per=8))
        out = [L(cv, body, c["capy"], above=wl), L(cv, head, c["capy"], above=wl)]
        out.append(L(cv, body.moved(4, 8), c["deep"], 0.45, ss=1, soft=6, below=wl + 3, clip=self.pool(cv)))  # what shows through the water
        out.append(L(cv, Shape().line(spline(at([(30, -66 * breathe), (90, -70 * breathe), (150, -58 * breathe), (198, -26)]), closed=False, per=8), 7), c["capy3"], 0.4, above=wl))
        out.append(L(cv, Shape().ellipse(x0 - 148, y0 - 74, 22, 36, 0.12), c["capy2"], above=wl))  # the snout
        out.append(L(cv, Shape().ellipse(x0 - 26, y0 - 126, 14, 10, -0.4), c["capy2"], above=wl))  # the ear
        out.append(L(cv, Shape().ellipse(x0 - 158, y0 - 82, 3.5, 5.5, 0.3), c["ink"], above=wl))  # the nostril
        out.append(L(cv, Shape().line(spline(at([(-156, -46), (-146, -42), (-134, -44)]), closed=False, per=6), 2.4), c["ink"], above=wl))
        out.append(L(cv, Shape().ellipse(x0 - 108, y0 - 60, 13, 8), c["blush"], 0.25, above=wl))
        if eyes_open:
            ex, ey = x0 - 86 + 3 * look, y0 - 97
            out += [L(cv, Shape().ellipse(ex, ey, 5.5, 6.5), c["ink"], above=wl), D(cv, ex + 1.8, ey - 2.2, 1.6, c["capy3"])]
        else:
            out.append(L(cv, Shape().line(spline(at([(-96, -98), (-86, -93), (-76, -98)]), closed=False, per=6), 3.0), c["ink"], above=wl))
        return out, (x0 + self.TOP[0], y0 + self.TOP[1])

    def yuzu(self, cv, c, x, y, spin, wl=None):
        r = 21.0
        out = [L(cv, Shape().circle(x, y, r), c["yuzu"], above=wl), L(cv, Shape().ellipse(x + 6, y + 7, 14, 11, 0.6), c["yuzu2"], 0.45, above=wl)]
        lx, ly = x + r * 0.75 * math.sin(spin), y - r * 0.85 * math.cos(spin)
        out.append(L(cv, Shape().ellipse(lx + 8 * math.cos(spin), ly + 8 * math.sin(spin), 10, 4.5, spin + 0.4), c["leaf"], above=wl))
        out.append(D(cv, x - 7, y - 8, 4, c["capy3"], 0.5))
        return out

    def ring(self, cv, c, x, y, age, life=1.6, big=1.0):
        u = age / life
        if not 0 <= u < 1:
            return []
        rx = (14 + 70 * ease_out(u)) * big
        return [L(cv, Shape().line(ellipse_pts(x, y, rx, rx * 0.26, n=60) + [ellipse_pts(x, y, rx, rx * 0.26, n=60)[0]], 2.2 * (1 - u) + 0.6), c["shine"], 0.8 * (1 - u), ss=2)]

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        # the surface: slow light on the water
        for i, (x, y, w) in enumerate(((880, 812, 70), (1300, 840, 90), (1180, 900, 60), (1420, 880, 50), (960, 880, 40))):
            dx = 14 * wave(t, 6, i * 0.23)
            out.append(L(cv, Shape().line([(x + dx - w / 2, y), (x + dx + w / 2, y)], 3), c["shine"], 0.35 + 0.15 * wave(t, 4, i * 0.31), ss=2))
        # the capybara and the yuzu: rest, the roll, afloat, under, up again
        dip = window(t, 18.2, 19.3) - window(t, 19.5, 20.7)
        look = clamp((t - 15.4) / 0.6) if 15.2 <= t < 17.8 else 0.0
        eyes = 2.0 <= t < 2.3 or 15.2 <= t < 17.8 or 10.4 <= t < 10.65
        capy, top = self.capybara(cv, c, t, dip, look, eyes)
        wl = self.CY
        rest = (top[0], top[1])
        if t < 6.0:
            yx, yy, spin = rest[0], rest[1], 0.0
        elif t < 7.4:
            u = window(t, 6.0, 7.4)
            if u < 0.45:
                v = ease_in(u / 0.45)
                yx, yy = rest[0] + 62 * v, rest[1] + 8 * v * v
            else:
                v = (u - 0.45) / 0.55
                sx, sy = rest[0] + 62, rest[1] + 8
                yx, yy = sx + 60 * v, sy + (wl + 4 - sy) * v * v - 40 * v * (1 - v)
            spin = 4.2 * u
        else:
            path = [(rest[0] + 122, wl + 4), (self.CX + 170, wl + 14), (self.CX + 250, wl + 38), (self.CX + 150, wl + 58), (self.CX + 10, wl + 44), (rest[0], wl + 6)]
            u = min(1.0, (t - 7.4) / (18.6 - 7.4))
            pts = spline(path, closed=False, per=40)
            yx, yy = pts[min(len(pts) - 1, int(ease_io(u) * (len(pts) - 1)))]
            yy += 2.5 * wave(t, 2.2)
            spin = 4.2 + 0.4 * u
            if t >= 18.6:
                yy = min(wl + 6, top[1])
                yx = rest[0]
            if t >= 20.7:
                yx, yy, spin = top[0], top[1], 0.0
        if t >= 20.7 or (t >= 19.5 and top[1] <= wl + 6):
            yx, yy, spin = top[0], top[1], spin if t < 20.7 else 0.0
        afloat = 7.4 <= t < 20.7 and not (t >= 19.5 and top[1] <= wl + 6)
        out += capy
        out += self.yuzu(cv, c, yx, yy, spin, wl + 8 if afloat else None)
        # rings: the plop, the yuzu now and then, the capybara going under and coming up
        out += self.ring(cv, c, rest[0] + 122, wl + 4, t - 7.4, 1.8, 1.0)
        for t0 in (10.4, 13.6, 16.8):
            out += self.ring(cv, c, yx, wl + 10, t - t0, 1.5, 0.6)
        out += self.ring(cv, c, self.CX - 40, wl + 6, t - 18.9, 2.0, 1.6)
        out += self.ring(cv, c, self.CX - 40, wl + 6, t - 19.9, 2.0, 1.4)
        for k in range(4):
            out += self.ring(cv, c, self.CX + 60, wl + 2, (t - k * 6) % 24, 3.0, 1.2)
        rnd = random.Random(31)
        for i in range(9):  # bubbles while it is under
            t0 = 18.7 + i * 0.12 + rnd.uniform(0, 0.1)
            u = window(t, t0, t0 + 0.7)
            if 0 < u < 1:
                out.append(D(cv, self.CX - 70 + rnd.uniform(-30, 30), wl + 10 - 18 * u, 3 + 3 * rnd.random(), c["shine"], 0.8 * (1 - u)))
        # steam, rising and leaving
        rnd = random.Random(9)
        for i in range(10):
            x0 = self.PX + rnd.uniform(-340, 340)
            ph = i / 10 + rnd.uniform(0, 0.04)
            u = ((t / 8.0) + ph) % 1.0
            x, y = x0 + 60 * u + 14 * wave(t, 8, ph), self.PY - 24 - 220 * u
            a = (0.16 if p.dark else 0.5) * bump(u) ** 1.5
            out.append(L(cv, Shape().ellipse(x, y, 22 + 34 * u, 34 + 40 * u, 0.3 * wave(t, 8, ph)), c["steam"], a, ss=1, soft=16 + 12 * u))
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        out = []
        for k, t0 in enumerate((21.0, 21.7, 22.4)):  # z, z, z
            u = window(t, t0, t0 + 1.6)
            if 0 < u < 1:
                x, y = self.CX - 40 + 30 * u + 10 * k, self.CY - 180 - 60 * u - 12 * k
                out.append(L(cv, glyph(Shape(), "z", x, y, 14 + 8 * u, 2.6), c["steam"], 0.8 * bump(u), ss=4))
        rnd = random.Random(5)
        for i in range(150):  # snow, near and far: each flake falls a whole screen, or two, in a loop
            near = i % 3 == 0
            x0, y0 = rnd.uniform(0, W), rnd.uniform(0, H + 40)
            k, sway, ph = (2 if near else 1), rnd.uniform(8, 26), rnd.random()
            y = (y0 + (H + 40) * k * t / self.seconds) % (H + 40) - 20
            x = x0 + sway * wave(t, self.seconds / (1 + i % 2), ph)
            out.append(D(cv, x, y, rnd.uniform(2.2, 3.4) if near else rnd.uniform(1.1, 1.9), c["flake"], (0.75 if near else 0.5) if p.dark else (0.7 if near else 0.45)))
        return out


def bubble(cv, x, y, k, text, fill, ink, tail=-1):
    """A speech bubble at (x, y), k its size (0 gone, 1 full), its tail down to the
    left (-1) or the right (1), with a letter or a few in it."""
    if k <= 0.01:
        return []
    k *= 1.35
    size = 26 * k
    tw = size * 0.72 * len(text)
    rx, ry = max(30 * k, tw / 2 + 16 * k), 25 * k
    b = Shape().ellipse(x, y, rx, ry)
    b.poly([(x + tail * 6 * k, y + ry * 0.6), (x + tail * 24 * k, y + ry + 16 * k), (x + tail * 22 * k, y + ry * 0.4)])
    g = Shape()
    for i, ch in enumerate(text):
        glyph(g, ch, x - tw / 2 + i * size * 0.72, y - size * 0.5, size, 3.6 * k)
    return [L(cv, b, fill), L(cv, g, ink)]


def pop(t, t0, t1):
    """A bubble's size: it springs open at t0 and shuts at t1."""
    if not t0 <= t < t1:
        return 0.0
    u = window(t, t0, t0 + 0.22)
    return (1 + 0.18 * math.sin(math.pi * u)) * ease_out(u) * (1 - ease_in(window(t, t1 - 0.16, t1)))


def stars(cv, color, seed, n, top, bottom, t=None, alpha=0.5, avoid=None):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        x, y, r = rnd.uniform(0, W), rnd.uniform(top, bottom), rnd.choice((1.0, 1.3, 1.7, 2.1))
        if avoid and math.hypot(x - avoid[0], y - avoid[1]) < avoid[2]:
            continue
        a = alpha
        if t is not None and i % 4 == 0:
            a = alpha * (0.45 + 0.55 * (0.5 + 0.5 * wave(t, 24 / rnd.choice((2, 3, 4, 6)), rnd.random())))
        out.append(D(cv, x, y, r, color, a))
    return out


def ribbon(pts, w0, w1):
    """A stroke that narrows from w0 to w1 along its points, as one polygon."""
    left, right = [], []
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1.0
        w = (w0 + (w1 - w0) * i / max(n - 1, 1)) / 2
        left.append((x - dy / d * w, y + dx / d * w))
        right.append((x + dy / d * w, y - dx / d * w))
    return left + right[::-1]


class Cached:
    def cached(self, cv, key, make):
        store = self.__dict__.setdefault("_cache", {})
        if (key, cv.w) not in store:
            store[(key, cv.w)] = make()
        return store[(key, cv.w)]


class Duck(Scene, Cached):
    name = "duck"
    PX, PY, PRX, PRY = 960.0, 868.0, 900.0, 205.0  # the pond
    WL = 820.0  # the duck's waterline

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            ink = p.pick("ansi_0", "fg")
            yellow = mix(p("ansi_3"), p("white"), 0.15 if dk else 0.0)
            frog = mix(p("ansi_2"), ink, 0.12)
            self._c = (p, dict(
                dark=dk, sky=p("bg"), sun=p.pick("fg+ansi_3:15", "ansi_3+bg:30"), halo=p.pick("bg+accent:6", "bg+ansi_3:10"),
                cloud=p.pick("bg+fg:6", "bg+white:70"), cloud2=p.pick("bg+fg:4", "bg+white:45"),
                hill=p.pick("bg+ansi_2:12", "bg+ansi_2:20"), hill2=p.pick("bg+ansi_2:18", "bg+ansi_2:30"), grass=p.pick("bg+ansi_2:24", "bg+ansi_2:38"),
                water=p.pick("bg+ansi_4:26", "bg+ansi_4:24"), deep=p.pick("bg+ansi_4:18", "bg+ansi_4:34"), shine=p.pick("bg+ansi_4:55", "ansi_4+white:55"),
                reed=p.pick("ansi_0+ansi_2:34", "bg+ansi_2:62"), cattail=mix(p("ansi_3+ansi_1:30"), ink, 0.45),
                pad=p.pick("bg+ansi_2:38", "bg+ansi_2:52"), pad2=p.pick("bg+ansi_2:28", "bg+ansi_2:66"), flower=p("ansi_5"), flower2=p.pick("ansi_5+white:40", "ansi_5+white:55"),
                duck=yellow, duck2=mix(yellow, p("ansi_1"), 0.22), beak=mix(p("ansi_3"), p("ansi_1"), 0.55), ink=ink, shine2=p.pick("white", "white"),
                frog=frog, frog2=mix(frog, ink, 0.3), belly=mix(frog, p("white"), 0.45), tongue=mix(p("ansi_1"), p("ansi_5"), 0.4),
                bug=mix(ink, p("ansi_1"), 0.2), wing=p.pick("fg", "white"), bubble=p.pick("bg+fg:88", "white"), glow=p("ansi_3"), fly=p("accent"),
            ))
        return self._c[1]

    def pond(self, cv):
        return self.cached(cv, "pond", lambda: full(cv, Shape().ellipse(self.PX, self.PY, self.PRX, self.PRY)))

    def back(self, cv, p):
        c = self.colors(p)
        sx, sy = 400.0, 210.0
        out = [D(cv, sx, sy, 120, c["halo"]), D(cv, sx, sy, 58, c["sun"])]
        if c["dark"]:  # a crescent: the sky's own color over the moon
            out = [D(cv, sx, sy, 120, c["halo"]), D(cv, sx, sy, 58, c["sun"]), D(cv, sx + 26, sy - 12, 52, c["halo"])]
            out += stars(cv, c["wing"], 21, 70, 30, 520, alpha=0.4, avoid=(sx, sy, 150))
        out.append(L(cv, Shape().poly([(0, 640)] + spline([(0, 600), (300, 540), (640, 590), (980, 520), (1320, 580), (1640, 530), (1920, 590)], closed=False, per=16) + [(W, 640)]), c["hill"], ss=2))
        out.append(L(cv, Shape().poly([(0, 700)] + spline([(0, 640), (360, 600), (760, 650), (1160, 610), (1560, 655), (1920, 620)], closed=False, per=16) + [(W, 700)]), c["hill2"], ss=2))
        out.append(L(cv, Shape().rect(0, 650, W, H - 650), c["grass"], ss=1))
        out.append(L(cv, Shape().ellipse(self.PX, self.PY, self.PRX, self.PRY), c["water"], ss=2))
        out.append(L(cv, Shape().ellipse(self.PX + 60, self.PY + 40, self.PRX * 0.7, self.PRY * 0.55), c["deep"], 0.7, ss=1, soft=40, clip=self.pond(cv)))
        for x, y, r, rot, fl in ((300, 960, 46, 0.4, False), (820, 1010, 52, 2.0, False), (1480, 940, 44, 1.2, True), (1660, 870, 38, 3.4, False), (1290, 1020, 40, 5.0, False)):
            out += self.pad(cv, c, x, y, r, rot, fl)
        out += self.pad(cv, c, 520, 884, 74, 0.9, False)  # the frog's
        return out

    def pad(self, cv, c, x, y, r, rot, flower):
        pts = ellipse_pts(x, y, r, r * 0.32, 0, n=48, a0=rot + 0.35, a1=rot + 2 * math.pi - 0.35) + [(x, y)]
        out = [L(cv, Shape().ellipse(x + 3, y + 4, r, r * 0.32), c["pad2"], 0.6, ss=2), L(cv, Shape().poly(pts), c["pad"], ss=2)]
        if flower:
            f = Shape()
            for k in range(6):
                a = k * math.pi / 3
                f.ellipse(x + 10 * math.cos(a), y - 12 + 4 * math.sin(a), 9, 5, a)
            out += [L(cv, f, c["flower2"]), D(cv, x, y - 13, 5, c["flower"])]
        return out

    def reeds(self, cv, c, t):
        out = []
        rnd = random.Random(3)
        for i in range(26):
            left = i < 13
            x = rnd.uniform(40, 330) if left else rnd.uniform(1600, 1900)
            base, h = rnd.uniform(690, 760), rnd.uniform(120, 230)
            sway = 9 * (h / 200) * wave(t, 6 if i % 2 else 4, rnd.random())
            top = (x + sway + rnd.uniform(-12, 12), base - h)
            pts = bezier((x, base), (x, base - h * 0.4), (top[0] - sway * 0.3, base - h * 0.75), top, n=10)
            out.append(L(cv, Shape().poly(ribbon(pts, 6, 1.5)), c["reed"], ss=2))
            if i % 3 == 0:
                u = pts[7]
                out.append(L(cv, Shape().line([u, pts[8]], 9), c["cattail"], ss=2))
        return out

    def duck(self, cv, c, x, y, t, kx, tilt):
        sh = lambda s: s.moved(x, y, 1.22, tilt, 0, 0, kx)
        body = Shape().poly(spline([(-74, -6), (-66, -36), (-36, -50), (14, -50), (50, -50), (80, -76), (84, -40), (66, -8), (10, 6), (-50, 4)], per=8))
        head = Shape().circle(-40, -86, 31)
        beak = Shape().poly(spline([(-62, -93), (-94, -88), (-102, -79), (-93, -70), (-62, -72)], per=6))
        wing = Shape().poly(spline([(-14, -36), (20, -44), (46, -30), (30, -16), (-6, -18)], per=6))
        out = [L(cv, sh(body), c["duck"], above=self.WL), L(cv, sh(head), c["duck"]), L(cv, sh(wing), c["duck2"], above=self.WL),
               L(cv, sh(beak), c["beak"]), L(cv, sh(Shape().line([(-66, -81), (-96, -79)], 2.2)), mix(c["beak"], c["ink"], 0.35))]
        ex, ey = sh(Shape().poly([(-48, -94)])).cmds[0][1][0]
        out += [D(cv, ex, ey, 5.2, c["ink"]), D(cv, ex - 1.6 * kx, ey - 2, 1.7, c["shine2"])]
        out.append(L(cv, sh(Shape().ellipse(-54, -78, 8, 5)), c["beak"], 0.25))
        # its reflection: upside down under the waterline, faint
        flip = lambda s: s.moved(x, y, 1.22, tilt, 0, 0, kx).moved(0, 0, 1, 0, 0, 0, 1)
        refl = Shape()
        for cmd in flip(body).cmds:
            refl.cmds.append(("poly", [(px, 2 * self.WL - py + 4) for px, py in cmd[1]]))
        out.insert(0, L(cv, refl, c["duck"], 0.14, ss=1, soft=4, below=self.WL + 2, clip=self.pond(cv)))
        return out

    def ring(self, cv, c, x, y, age, life=1.8, big=1.0):
        u = age / life
        if not 0 <= u < 1:
            return []
        rx = (30 + 90 * ease_out(u)) * big
        pts = ellipse_pts(x, y, rx, rx * 0.24, n=72)
        return [L(cv, Shape().line(pts + [pts[0]], 2.4 * (1 - u) + 0.6), c["shine"], 0.75 * (1 - u), ss=2)]

    def frog(self, cv, c, t, bug):
        x, y = 520.0, 870.0
        out = []
        sh = lambda s: s.moved(x, y)
        out.append(L(cv, sh(Shape().ellipse(-26, -10, 20, 12, 0.35).ellipse(28, -10, 20, 12, -0.35)), c["frog2"]))
        out.append(L(cv, sh(Shape().ellipse(0, -28, 38, 28)), c["frog"]))
        out.append(L(cv, sh(Shape().ellipse(6, -20, 22, 15)), c["belly"]))
        g = bump(window(t, 15.95, 16.55))
        if g:
            out.append(L(cv, sh(Shape().ellipse(10, -24, 14 + 10 * g, 8 + 8 * g)), c["belly"]))
        out.append(L(cv, sh(Shape().circle(-14, -52, 12).circle(15, -54, 12)), c["frog"]))
        blink = 6.0 <= t < 6.2 or 20.5 <= t < 20.7
        lx, ly = (bug[0] - x, bug[1] - y) if bug else (40, -20)
        d = math.hypot(lx, ly) or 1
        for ex, ey in ((-14, -53), (15, -55)):
            if blink:
                out.append(L(cv, Shape().line([(x + ex - 6, y + ey), (x + ex + 6, y + ey)], 2.6), c["ink"]))
            else:
                out += [D(cv, x + ex, y + ey, 7.5, c["belly"]), D(cv, x + ex + 3 * lx / d, y + ey + 3 * ly / d, 3.6, c["ink"])]
        out.append(L(cv, sh(Shape().line(spline([(-16, -34), (4, -29), (26, -36)], closed=False, per=6), 2.4)), c["frog2"]))
        return out, (x + 26, y - 36)

    def bugpos(self, t):
        if t < 12.2 or t >= 15.65:
            return None
        if t < 13.4:
            u = ease_io(window(t, 12.2, 13.4))
            return 960 - 300 * u + 30 * wave(t, 0.7), 690 + 70 * u + 16 * wave(t, 0.45)
        return 660 + 70 * wave(t - 13.4, 1.9) + 10 * wave(t, 0.5), 760 + 28 * wave(t - 13.4, 1.1)

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        for i, (x, y, w) in enumerate(((760, 250, 1.0), (1180, 170, 0.8), (1580, 300, 0.7))):  # clouds, drifting and back
            dx = 46 * wave(t, 24, i * 0.3)
            cl = Shape().rect(x + dx - 120 * w, y, 240 * w, 34 * w).circle(x + dx - 60 * w, y + 4, 42 * w).circle(x + dx + 20 * w, y - 10 * w, 56 * w).circle(x + dx + 90 * w, y + 8, 34 * w)
            out.append(L(cv, cl, c["cloud"], 1.0, ss=2, above=y + 34 * w))
        out += self.reeds(cv, c, t)
        for i, (x, y, w) in enumerate(((420, 760, 80), (980, 1000, 120), (1400, 880, 90), (700, 920, 60), (1700, 980, 70))):
            dx = 18 * wave(t, 6, i * 0.21)
            out.append(L(cv, Shape().line([(x + dx - w / 2, y), (x + dx + w / 2, y)], 3), c["shine"], 0.3 + 0.12 * wave(t, 4, i * 0.3), ss=2))
        # the duck: it drifts, bobs, hops at its idea, turns its back for a while
        x = 1200 + 60 * wave(t, 24)
        y = self.WL + 3 * wave(t, 2.4) - 30 * bump(window(t, 8.7, 9.25))
        kx = 1 - 2 * ease_io(window(t, 19.6, 19.95)) + 2 * ease_io(window(t, 22.6, 22.95))
        tilt = 0.04 * wave(t, 2.4, 0.25)
        for k in range(10):
            out += self.ring(cv, c, x, self.WL + 6, (t - k * 2.4) % 24, 2.2, 0.8)
        out += self.ring(cv, c, x, self.WL + 6, t - 9.25, 1.8, 1.4)
        out += self.duck(cv, c, x, y, t, kx, tilt)
        # the frog and its bug
        bug = self.bugpos(t)
        frog, mouth = self.frog(cv, c, t, bug)
        out += frog
        catch = (self.bugpos(15.64) or (660, 760))
        e = ease_out(window(t, 15.5, 15.65)) - ease_in(window(t, 15.65, 15.95))
        if 15.5 <= t < 15.95:
            tip = (mouth[0] + (catch[0] - mouth[0]) * e, mouth[1] + (catch[1] - mouth[1]) * e)
            out.append(L(cv, Shape().line([mouth, tip], 5), c["tongue"]))
            out.append(D(cv, tip[0], tip[1], 5, c["tongue"]))
            if t >= 15.65:
                bug = tip
        if bug:
            bx, by = bug
            f = abs(math.sin(2 * math.pi * t / 0.1))
            out += [L(cv, Shape().ellipse(bx - 7, by - 8, 11, 6 * f + 1.5, -0.5).ellipse(bx + 7, by - 8, 11, 6 * f + 1.5, 0.5), c["wing"], 0.6),
                    L(cv, Shape().ellipse(bx, by, 10, 7).line([(bx - 8, by + 4), (bx - 13, by + 10)], 2).line([(bx + 8, by + 4), (bx + 13, by + 10)], 2), c["bug"])]
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        x = 1200 + 60 * wave(t, 24)
        y = self.WL + 3 * wave(t, 2.4) - 30 * bump(window(t, 8.7, 9.25))
        kx = 1 - 2 * ease_io(window(t, 19.6, 19.95)) + 2 * ease_io(window(t, 22.6, 22.95))
        hx, hy = x - 52 * kx, y - 170
        out = bubble(cv, hx, hy, pop(t, 2.6, 5.6), "?", c["bubble"], c["ink"], tail=1)
        out += bubble(cv, hx, hy, pop(t, 8.6, 11.2), "!", c["bubble"], c["ink"], tail=1)
        u = window(t, 8.7, 9.7)
        if 0 < u < 1:  # the idea's light
            for k in range(6):
                a = -math.pi / 2 + (k - 2.5) * 0.45
                r0, r1 = 46 + 26 * u, 58 + 34 * u
                out.append(L(cv, Shape().line([(hx + r0 * math.cos(a), hy + r0 * math.sin(a)), (hx + r1 * math.cos(a), hy + r1 * math.sin(a))], 3.2), c["glow"], 1 - u))
        out += bubble(cv, 560, 760, pop(t, 16.8, 19.0), "v", c["bubble"], c["ink"], tail=-1)
        if c["dark"]:  # fireflies by night
            rnd = random.Random(8)
            for i in range(14):
                fx = rnd.uniform(100, 1820) + 60 * wave(t, 24 / rnd.choice((1, 2, 3)), rnd.random())
                fy = rnd.uniform(560, 760) + 30 * wave(t, 24 / rnd.choice((2, 3, 4)), rnd.random())
                a = 0.5 + 0.5 * wave(t, 24 / rnd.choice((4, 6, 8)), rnd.random())
                out += [D(cv, fx, fy, 9, c["glow"], 0.16 * a), D(cv, fx, fy, 2.4, c["glow"], 0.9 * a)]
        else:  # a dragonfly by day
            fx = 960 + 640 * math.sin(2 * math.pi * t / 24)
            fy = 560 + 90 * math.sin(4 * math.pi * t / 24) + 20 * wave(t, 1.5)
            ang = math.atan2(90 * 4 * math.pi / 24 * math.cos(4 * math.pi * t / 24), 640 * 2 * math.pi / 24 * math.cos(2 * math.pi * t / 24))
            f = abs(math.sin(2 * math.pi * t / 0.08))  # 300 beats a loop
            body = Shape().line([(fx - 30 * math.cos(ang), fy - 30 * math.sin(ang)), (fx + 14 * math.cos(ang), fy + 14 * math.sin(ang))], 4)
            wings = Shape()
            for side in (-1, 1):
                for off in (0.0, 9.0):
                    wx, wy = fx - off * math.cos(ang), fy - off * math.sin(ang)
                    a = ang + side * (math.pi / 2 - 0.2)
                    wings.ellipse(wx + 16 * math.cos(a), wy + 16 * math.sin(a), 17, 4 + 2 * f, a)
            out += [L(cv, wings, c["wing"], 0.5), L(cv, body, c["fly"])]
        return out


class Reef(Scene, Cached):
    name = "reef"

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            ink = p.pick("ansi_0", "fg")
            self._c = (p, dict(
                dark=dk, top=p.pick("bg+ansi_6:24", "bg+ansi_6:14"), mid=p.pick("bg+ansi_6:16", "bg+ansi_6:24"), low=p.pick("bg+ansi_6:9", "bg+ansi_6:34"),
                ray=p.pick("ansi_6+white:50", "white"), sand=p.pick("bg+ansi_3:20", "bg+ansi_3:26"), sand2=p.pick("bg+ansi_3:28", "bg+ansi_3:36"),
                rock=p.pick("bg+ansi_8:46", "bg+ansi_8:40"), rock2=p.pick("bg+ansi_8:30", "bg+ansi_8:58"), hole=mix(ink, p("bg"), 0.2),
                kelp=p.pick("bg+ansi_2:36", "bg+ansi_2:46"), kelp2=p.pick("bg+ansi_2:24", "bg+ansi_2:34"),
                coral=p.pick("bg+ansi_5:44", "bg+ansi_5:52"), coral2=p.pick("bg+ansi_1:40", "bg+ansi_1:48"),
                fish=p("accent"), lost=max((p(k) for k in ("ansi_3", "ansi_5", "ansi_6", "ansi_2")), key=lambda q: sum((a - b) ** 2 for a, b in zip(q, p("accent")))), eel=mix(p("ansi_2"), p("ansi_4"), 0.5), star=mix(p("ansi_3"), p("ansi_1"), 0.45),
                shell=p("ansi_5"), snail=p.pick("bg+fg:40", "bg+fg:30"), ink=ink, bub=p.pick("fg", "white"), bubble=p.pick("bg+fg:88", "white"),
            ))
        return self._c[1]

    def back(self, cv, p):
        c = self.colors(p)
        out = [L(cv, Shape().poly([(0, 0), (W, 0)] + [(x, 360 + 18 * math.sin(x / 140)) for x in range(W, -1, -40)]), c["top"], ss=1)]
        out.append(L(cv, Shape().poly([(0, 360)] + [(x, 360 + 18 * math.sin(x / 140)) for x in range(0, W + 1, 40)] + [(W, 700), (0, 700)]), c["mid"], ss=1))
        out.append(L(cv, Shape().poly([(0, 700)] + [(x, 690 + 14 * math.sin(x / 170 + 1)) for x in range(0, W + 1, 40)] + [(W, H), (0, H)]), c["low"], ss=1))
        out.append(L(cv, Shape().poly([(0, H)] + spline([(0, 840), (300, 800), (700, 850), (1100, 812), (1500, 846), (1920, 806)], closed=False, per=16) + [(W, H)]), c["sand"], ss=2))
        rip = Shape()
        rnd = random.Random(2)
        for _ in range(16):
            x, y = rnd.uniform(0, W), rnd.uniform(880, 1060)
            rip.line(bezier((x - 50, y), (x - 20, y - 8), (x + 20, y - 8), (x + 50, y), n=10), 3)
        out.append(L(cv, rip, c["sand2"], 0.8, ss=2))
        # the rocks: the eel's on the left, the starfish's and the snail's on the right
        out.append(L(cv, Shape().poly(spline([(60, 900), (120, 780), (260, 730), (420, 760), (520, 860), (470, 930), (200, 950)], per=10)), c["rock"], ss=2))
        out.append(L(cv, Shape().poly(spline([(110, 900), (180, 820), (300, 800), (420, 840), (380, 900)], per=8)), c["rock2"], 0.5, ss=2))
        out.append(L(cv, Shape().ellipse(392, 836, 30, 22, -0.2), c["hole"], ss=2))
        out.append(L(cv, Shape().poly(spline([(1440, 900), (1480, 800), (1580, 760), (1720, 770), (1820, 840), (1800, 920), (1560, 940)], per=10)), c["rock"], ss=2))
        out.append(L(cv, Shape().poly(spline([(1500, 900), (1560, 830), (1680, 815), (1770, 860), (1700, 905)], per=8)), c["rock2"], 0.5, ss=2))
        # coral: branches and a fan
        br = Shape()
        def branch(x, y, a, ln, w, d):
            x2, y2 = x + ln * math.cos(a), y + ln * math.sin(a)
            br.line([(x, y), (x2, y2)], w)
            if d:
                branch(x2, y2, a - 0.42, ln * 0.72, w * 0.75, d - 1)
                branch(x2, y2, a + 0.38, ln * 0.7, w * 0.75, d - 1)
        for x, a in ((1250, -1.75), (1300, -1.45), (1350, -1.62)):
            branch(x, 880, a, 70, 14, 3)
        out.append(L(cv, br, c["coral"], ss=2))
        fan = Shape()
        for k in range(9):
            a = -math.pi / 2 + (k - 4) * 0.2
            fan.line(bezier((640, 860), (640 + 40 * math.cos(a), 860 - 50), (640 + 110 * math.cos(a), 860 + 110 * math.sin(a) + 20), (640 + 140 * math.cos(a), 860 + 140 * math.sin(a)), n=12), 5)
        out.append(L(cv, fan, c["coral2"], ss=2))
        return out

    def rays(self, cv):
        def make():
            got = []
            for x in (260, 600, 980, 1340, 1680):
                got.append(cover(cv, Shape().poly([(x - 40, -10), (x + 50, -10), (x + 260, 900), (x + 90, 900)]), 1, soft=40))
            return got
        return self.cached(cv, "rays", make)

    def kelp(self, cv, c, t):
        out = []
        rnd = random.Random(6)
        for i in range(12):
            x = rnd.choice((rnd.uniform(20, 260), rnd.uniform(520, 760), rnd.uniform(1820, 1910), rnd.uniform(1080, 1200)))
            base, h = rnd.uniform(860, 960), rnd.uniform(280, 470)
            ph, per = rnd.random(), rnd.choice((4, 6))
            pts = []
            for k in range(13):
                f = k / 12
                pts.append((x + 34 * f**1.4 * wave(t, per, ph - f * 0.6), base - h * f))
            col = c["kelp"] if i % 2 else c["kelp2"]
            sh = Shape().poly(ribbon(pts, 16, 4))
            for k in range(2, 12, 2):
                px, py = pts[k]
                side = 1 if k % 4 else -1
                sh.ellipse(px + side * 14, py - 6, 16, 6, side * 0.6)
            out.append(L(cv, sh, col, ss=2))
        return out

    def eel(self, t):
        e = ease_out(window(t, 14.0, 15.0)) * (1 - ease_in(window(t, 18.4, 19.3)))
        if e <= 0.02:
            return None
        snap = bump(window(t, 16.0, 16.4))
        out = []
        for k in range(20):
            f = k / 19 * e
            out.append((392 + 170 * f, 836 - 60 * f - 30 * math.sin(2 * math.pi * (f * 1.1 - t / 3)) * min(1.0, f * 3) - 30 * snap * f))
        return out

    def bub(self, cv, c, x, y, r):
        pts = ellipse_pts(x, y, r, r, n=24)
        return [L(cv, Shape().line(pts + [pts[0]], 2), c["bub"], 0.55, ss=2), D(cv, x - r * 0.35, y - r * 0.35, r * 0.22, c["bub"], 0.6)]

    def chevron(self, cv, x, y, color, kx, flap, size=26, w=8.0):
        a = 0.6 + 0.14 * flap
        pts = [(x - kx * size * math.cos(a), y - size * math.sin(a)), (x, y), (x - kx * size * math.cos(a), y + size * math.sin(a))]
        return L(cv, Shape().line(pts, w), color)

    def school(self, t):
        return -320 + (W + 640) * t / 24, 430 + 30 * wave(t, 12)

    SLOTS = [(120, 0), (80, -40), (80, 40), (40, -78), (40, 0), (40, 78), (0, -40), (0, 40), (-40, 0)]

    def lost(self, t):
        """The lost fish: where, which way, and whether it has its eye on the rest."""
        if t < 4:
            return None
        if t < 10.2:
            return W + 40 - 171 * (t - 4), 620 + 10 * wave(t, 1.3), -1
        sx, sy = self.school(t)
        tail = (sx - 100, sy + 50 + 6 * wave(t, 1.2, 0.5))
        kx = -1 + 2 * ease_io(window(t, 11.0, 11.4))
        if t < 11.4:
            return 900, 620 + 4 * wave(t, 0.8), kx
        u = ease_io(window(t, 11.4, 13.4))
        return 900 + (tail[0] - 900) * u, 620 + (tail[1] - 620) * u, 1

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        for i, got in enumerate(self.rays(cv)):
            out.append(Layer(got, c["ray"], (0.06 if c["dark"] else 0.22) * (0.6 + 0.4 * wave(t, 8, i * 0.27))))
        for i in range(8):  # the light on the surface
            x = (i * 260 + 80 * wave(t, 12, i * 0.13)) % (W + 200) - 100
            out.append(L(cv, Shape().line([(x - 50, 40 + 12 * (i % 3)), (x + 50, 40 + 12 * (i % 3))], 4), c["ray"], 0.18 if c["dark"] else 0.5, ss=2))
        out += self.kelp(cv, c, t)
        # the eel: out of its hole, a snap at a bubble, a burp, back in
        pts = self.eel(t)
        if pts:
            out.append(L(cv, Shape().poly(ribbon(pts, 26, 18)), c["eel"]))
            hx, hy = pts[-1]
            out.append(L(cv, Shape().circle(hx, hy, 13), c["eel"]))
            out += [D(cv, hx + 2, hy - 5, 4.6, c["bubble"]), D(cv, hx + 3, hy - 5, 2.4, c["ink"])]
        rnd = random.Random(14)
        for i in range(8):  # bubbles from the vent by the hole
            t0 = i * 3 + rnd.uniform(0, 1)
            u = ((t - t0) % 24) / 5.0
            if u < 1:
                out += self.bub(cv, c, 456 + 14 * wave(t, 1.6, i * 0.2) + 6 * (i % 3), 818 - 760 * u, 6 + 3 * (i % 3))
        if 13.6 <= t < 16.2:  # the one it eats: from the vent to where its mouth will be
            hx, hy = self.eel(16.2)[-1]
            u = ease_io(window(t, 13.6, 16.2))
            out += self.bub(cv, c, 456 + (hx + 8 - 456) * u + 6 * wave(t, 1.3), 818 + (hy - 818) * u, 8)
        u = window(t, 16.8, 18.6)
        if 0 < u < 1:  # its burp
            hx, hy = self.eel(16.8)[-1]
            out += self.bub(cv, c, hx + 6 + 10 * u, hy - 12 - 120 * u, 4 + 3 * u)
        # the starfish turns, by a fifth of a turn a loop: the same star when it ends
        sx, sy = 1600.0, 768.0
        a0 = 2 * math.pi / 5 * t / 24
        st = Shape()
        for k in range(5):
            a = a0 + k * 2 * math.pi / 5 - math.pi / 2
            st.line([(sx, sy), (sx + 30 * math.cos(a), sy + 30 * math.sin(a))], 13)
        st.circle(sx, sy, 12)
        out.append(L(cv, st, c["star"]))
        for k in range(5):
            a = a0 + k * 2 * math.pi / 5 - math.pi / 2
            out.append(D(cv, sx + 16 * math.cos(a), sy + 16 * math.sin(a), 2.2, c["bub"], 0.45))
        # the @ snail goes along its rock and back
        u = (1 - math.cos(2 * math.pi * t / 24)) / 2
        nx = 1500 + 220 * u
        kx = 1 if math.sin(2 * math.pi * t / 24) >= 0 else -1
        kx *= clamp(abs(math.sin(2 * math.pi * t / 24)) * 6)
        ny = 812 - 26 * math.sin(math.pi * u)
        body = Shape().poly(spline([(-34, 0), (-10, -8), (30, -10), (44, -2), (30, 4), (-30, 4)], per=6)).line([(30, -8), (36, -30)], 3).line([(38, -6), (48, -26)], 3)
        out.append(L(cv, body.moved(nx, ny, 1.4, 0, 0, 0, kx if abs(kx) > 0.05 else 0.05), c["snail"]))
        sh = Shape()
        spiral = [(nx + kx * 1.4 * (4 + 22 * (1 - f) * math.cos(f * 4.2 * math.pi)), ny - 36 + 1.4 * 22 * (1 - f) * math.sin(f * 4.2 * math.pi)) for f in [k / 40 for k in range(41)]]
        sh.line(spiral, 8)
        out.append(L(cv, sh, c["shell"]))
        # the school, and the one going the other way
        sx, sy = self.school(t)
        for i, (dx, dy) in enumerate(self.SLOTS):
            out.append(self.chevron(cv, sx + dx, sy + dy + 6 * wave(t, 1.2, i * 0.13), c["fish"], 1, wave(t, 0.6, i * 0.17)))
        lf = self.lost(t)
        if lf:
            lx, ly, kx = lf
            out.append(self.chevron(cv, lx, ly, c["lost"], kx if abs(kx) > 0.08 else 0.08, wave(t, 0.4)))
            out.append(D(cv, lx - kx * 9, ly - 4, 2.6, c["ink"]))
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        return bubble(cv, 930, 548, pop(t, 10.2, 11.6), "!", c["bubble"], c["ink"], tail=-1)


class Campfire(Scene, Cached):
    name = "campfire"
    FX, FY = 840.0, 880.0  # the fire
    RX, RY = 1130.0, 884.0  # the raccoon's seat

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            ink = p.pick("ansi_0", "fg")
            fur = p.pick("bg+fg:42", "bg+fg:38")
            wood = mix(p("ansi_3+ansi_1:30"), ink, 0.5)
            self._c = (p, dict(
                dark=dk, sky=p("bg"), moon=p.pick("fg+ansi_3:15", "ansi_3+bg:30"), halo=p.pick("bg+accent:6", "bg+ansi_3:10"), star=p.pick("fg", "white"),
                far=p.pick("bg+fg:5", "bg+ansi_2:16"), near=p.pick("ansi_0+ansi_2:16", "bg+ansi_2:34"), ground=p.pick("bg+fg:8", "bg+ansi_3:14"), ground2=p.pick("bg+fg:5", "bg+ansi_3:22"),
                tent=p.pick("bg+accent:40", "bg+accent:50"), tent2=p.pick("bg+accent:24", "bg+accent:72"), door=mix(ink, p("bg"), 0.25),
                rock=p.pick("bg+ansi_8:50", "bg+ansi_8:40"), wood=wood, wood2=mix(wood, p.pick("fg", "white"), 0.25),
                flame1=p("ansi_1"), flame2=mix(p("ansi_1"), p("ansi_3"), 0.5), flame3=mix(p("ansi_3"), p("white"), 0.3), glow=p("ansi_3"),
                fur=fur, fur2=mix(fur, ink, 0.45), fur3=mix(fur, p("white"), 0.55), mask=mix(ink, fur, 0.12), ink=ink, eye=p.pick("bg+fg:92", "white"),
                mallow=p.pick("fg+white:50", "white"), toast=mix(p("ansi_3"), ink, 0.25), char=mix(ink, p("ansi_1"), 0.1), smoke=p.pick("fg", "fg"),
                bubble=p.pick("bg+fg:88", "white"),
            ))
        return self._c[1]

    def back(self, cv, p):
        c = self.colors(p)
        mx, my = 1540.0, 200.0
        out = [D(cv, mx, my, 110, c["halo"]), D(cv, mx, my, 50, c["moon"])]
        if c["dark"]:
            out.append(D(cv, mx + 22, my - 14, 44, c["halo"]))
            out += stars(cv, c["star"], 17, 90, 20, 560, alpha=0.45, avoid=(mx, my, 140))
        rnd = random.Random(10)
        far = Shape()
        for i in range(60):
            x, h = i * 34 + rnd.uniform(-10, 10), rnd.uniform(70, 150)
            far.poly([(x - 30, 760), (x, 760 - h), (x + 30, 760)])
        far.rect(0, 740, W, 40)
        out.append(L(cv, far, c["far"], ss=2))
        out.append(L(cv, Shape().poly([(0, 770)] + spline([(0, 770), (480, 750), (960, 770), (1440, 752), (1920, 772)], closed=False, per=16) + [(W, H), (0, H)]), c["ground"], ss=2))
        for x, side in ((-40, 1), (1960, -1)):  # big trees at the edges, framing it
            sh = Shape()
            for k in range(6):
                y = 300 + k * 90
                hw = 90 + k * 26
                sh.poly([(x + side * 40 - hw, y + 120), (x + side * 40, y - 40), (x + side * 40 + hw, y + 120)])
            out.append(L(cv, sh, c["near"], ss=2))
        # the tent
        tx, ty = 430.0, 870.0
        out.append(L(cv, Shape().ellipse(tx, ty + 6, 170, 16), c["ground2"], ss=2))
        out.append(L(cv, Shape().poly([(tx - 150, ty), (tx - 10, ty - 200), (tx + 150, ty)]), c["tent"], ss=2))
        out.append(L(cv, Shape().poly([(tx - 10, ty - 200), (tx + 150, ty), (tx + 60, ty)]), c["tent2"], 0.6, ss=2))
        out.append(L(cv, Shape().poly([(tx - 54, ty), (tx - 10, ty - 120), (tx + 36, ty)]), c["door"], ss=2))
        out.append(L(cv, Shape().line([(tx - 10, ty - 200), (tx - 10, ty - 222)], 4).line([(tx - 150, ty), (tx - 200, ty + 10)], 2).line([(tx + 150, ty), (tx + 200, ty + 10)], 2), c["wood"], ss=2))
        if c["dark"]:
            out.append(L(cv, Shape().poly([(tx - 46, ty), (tx - 10, ty - 104), (tx + 28, ty)]), c["glow"], 0.22, ss=2))
        # the log the raccoon sits on, and the stones round the fire
        rx, ry = self.RX, self.RY
        out.append(L(cv, Shape().ellipse(rx + 10, ry + 30, 150, 14), c["ground2"], ss=2))
        out.append(L(cv, Shape().poly(spline([(rx - 120, ry - 4), (rx + 130, ry - 6), (rx + 136, ry + 26), (rx - 116, ry + 28)], per=4)), c["wood"], ss=2))
        out.append(L(cv, Shape().ellipse(rx - 118, ry + 12, 14, 17), c["wood2"], ss=2))
        out.append(L(cv, Shape().line(ellipse_pts(rx - 118, ry + 12, 7, 9, n=20), 1.6), c["wood"], ss=2))
        fx, fy = self.FX, self.FY
        out.append(L(cv, Shape().ellipse(fx, fy + 10, 130, 22), c["ground2"], ss=2))
        out += self.stones(cv, c, math.pi, 2 * math.pi)
        out.append(L(cv, Shape().line([(fx - 70, fy + 6), (fx + 64, fy - 18)], 20).line([(fx + 66, fy + 8), (fx - 60, fy - 20)], 20), c["wood"], ss=2))
        return out

    def stones(self, cv, c, a0, a1):
        out = []
        for k in range(14):
            a = 2 * math.pi * k / 14 + 0.1
            if a0 <= a < a1:
                out.append(L(cv, Shape().ellipse(self.FX + 108 * math.cos(a), self.FY + 12 + 22 * math.sin(a), 22, 14, 0.2 * math.cos(a)), c["rock"], ss=2))
        return out

    def front(self, cv, p):
        return self.stones(cv, self.colors(p), 0, math.pi)

    def flame(self, cv, c, x, y, s, t, ph):
        out = []
        for col, k, h in ((c["flame1"], 1.0, 150), (c["flame2"], 0.72, 118), (c["flame3"], 0.44, 80)):
            pts = [(x - 62 * k * s, y)]
            for i, fx in enumerate((-0.7, -0.35, 0.0, 0.35, 0.7)):
                hh = h * s * (0.55 + 0.45 * (1 - abs(fx))) * (0.85 + 0.15 * wave(t, (0.5, 0.75, 0.6, 1.2, 0.4)[i], ph + i * 0.19))
                pts.append((x + fx * 62 * k * s + 6 * wave(t, 0.6, ph + i * 0.3) * s, y - hh))
                if i < 4:
                    pts.append((x + (fx + 0.175) * 62 * k * s, y - hh * 0.55))
            pts.append((x + 62 * k * s, y))
            out.append(L(cv, Shape().poly(spline(pts, per=5)), col))
        return out

    POSES = {"toast": ((-58, -92), (-250, -118)), "blow": ((-62, -108), (-122, -150)), "eat": ((-56, -118), (-78, -142))}

    def pose(self, t):
        P = self.POSES
        def lerp(a, b, u):
            return tuple(tuple(a[i][j] + (b[i][j] - a[i][j]) * u for j in (0, 1)) for i in (0, 1))
        if t < 9.0:
            return P["toast"]
        if t < 9.6:
            return lerp(P["toast"], P["blow"], ease_io(window(t, 9.0, 9.6)))
        if t < 12.8:
            return P["blow"]
        if t < 13.6:
            return lerp(P["blow"], P["eat"], ease_io(window(t, 12.8, 13.6)))
        if t < 17.6:
            return P["eat"]
        if t < 18.4:
            return lerp(P["eat"], P["toast"], ease_io(window(t, 17.6, 18.4)))
        return P["toast"]

    def raccoon(self, cv, c, t):
        x0, y0 = self.RX, self.RY
        at = lambda pts: [(x0 + x, y0 + y) for x, y in pts]
        out = []
        sway = 6 * wave(t, 4)
        tail = spline(at([(36, -14), (80, -20), (112, -52), (110 - sway, -96), (88 - sway, -118)]), closed=False, per=6)
        for k in range(len(tail) - 1):
            out.append(L(cv, Shape().line([tail[k], tail[k + 1]], 30 - k * 0.7), c["fur2"] if (k // 4) % 2 else c["fur"]))
        breathe = 1 + 0.02 * wave(t, 3)
        out.append(L(cv, Shape().poly(spline(at([(-38, -8), (-46, -60), (-30, -106 * breathe), (8, -114 * breathe), (38, -96), (48, -50), (36, -6)]), per=8)), c["fur"]))
        out.append(L(cv, Shape().ellipse(x0 - 12, y0 - 52, 22, 34), c["fur3"], 0.8))
        out.append(L(cv, Shape().ellipse(x0 - 30, y0 - 4, 16, 8).ellipse(x0 + 4, y0 - 2, 16, 8), c["fur2"]))
        paws, tip = self.pose(t)
        sx, sy = x0 - 18, y0 - 96 * breathe
        px, py = x0 + paws[0], y0 + paws[1]
        mx, my = x0 + tip[0], y0 + tip[1]
        out.append(L(cv, Shape().line([(px + (px - mx) * 0.25, py + (py - my) * 0.25), (mx, my)], 4.5), c["wood"]))
        out.append(L(cv, Shape().line([(sx, sy), ((sx + px) / 2 + 6, (sy + py) / 2 + 8), (px, py)], 15), c["fur"]))
        out.append(D(cv, px, py, 9, c["fur2"]))
        # the marshmallow: toasting, alight, black, eaten, a new one
        ang = math.atan2(my - py, mx - px)
        have = not (13.8 <= t < 18.6)
        k = ease_out(window(t, 18.6, 18.95)) if 18.6 <= t < 19.0 else 1.0
        if have:
            col = mix(c["mallow"], c["toast"], 0.6 * window(t, 0, 7.2)) if t < 7.6 else c["char"] if t >= 10.4 else mix(mix(c["mallow"], c["toast"], 0.6), c["char"], window(t, 7.6, 10.4))
            if t >= 18.6:
                col = c["mallow"]
            m = Shape().poly([(-15, -12), (15, -12), (15, 12), (-15, 12)]).moved(mx, my, k, ang)
            out.append(L(cv, m, col))
            fl = ease_out(window(t, 7.2, 7.8)) * (1 - ease_in(window(t, 9.8, 10.5)))
            if fl > 0.02:
                out += self.flame(cv, c, mx, my - 8, 0.32 * fl * (1 + 0.1 * wave(t, 0.3)), t, 0.7)
        # the head: the mask, the eyes, the puffed cheeks, the chewing
        hx, hy = x0 - 22, y0 - 150 * breathe
        puff = bump(window(t, 9.6, 10.8)) if 9.6 <= t < 10.8 else 0.0
        chew = 4 * abs(math.sin(math.pi * (t - 14.0) / 0.35)) if 14.0 <= t < 16.0 else 0.0
        head = Shape().poly(spline([(hx - 40 - 6 * puff, hy + 10 + chew * 0.4), (hx - 32, hy - 10), (hx - 8, hy - 30), (hx + 24, hy - 28), (hx + 44, hy - 10), (hx + 42, hy + 14), (hx + 14, hy + 30 + chew), (hx - 22, hy + 26 + chew)], per=8))
        ears = Shape().poly([(hx - 14, hy - 24), (hx - 6, hy - 52), (hx + 8, hy - 26)]).poly([(hx + 14, hy - 26), (hx + 26, hy - 52), (hx + 34, hy - 22)])
        out += [L(cv, ears, c["fur2"]), L(cv, head, c["fur"])]
        out.append(L(cv, Shape().poly(spline([(hx - 38, hy + 2), (hx - 22, hy - 14), (hx + 8, hy - 16), (hx + 30, hy - 6), (hx + 14, hy + 8), (hx - 10, hy + 4), (hx - 30, hy + 10)], per=6)), c["mask"]))
        out.append(L(cv, Shape().ellipse(hx - 4, hy - 20, 26, 5).ellipse(hx - 36 - 4 * puff, hy + 14 + chew * 0.5, 14 + 4 * puff, 10 + 3 * puff), c["fur3"]))
        out.append(L(cv, Shape().ellipse(hx - 50 - 6 * puff, hy + 8 + chew * 0.3, 6, 5), c["ink"]))
        wide = 8.0 <= t < 9.6
        happy = 15.8 <= t < 17.6
        blink = 3.0 <= t < 3.18 or 11.6 <= t < 11.8 or 21.4 <= t < 21.6
        for ex, ey in ((hx - 22, hy - 4), (hx + 6, hy - 6)):
            if happy:
                out.append(L(cv, Shape().line(spline([(ex - 6, ey + 2), (ex, ey - 4), (ex + 6, ey + 2)], closed=False, per=5), 2.6), c["eye"]))
            elif blink:
                out.append(L(cv, Shape().line([(ex - 5, ey), (ex + 5, ey)], 2.4), c["eye"]))
            else:
                r = 7.5 if wide else 5.5
                look = -2 if t < 13.6 or t >= 19.0 else 0  # on the marshmallow over the fire
                out += [D(cv, ex, ey, r, c["eye"]), D(cv, ex + look, ey + 0.5, r * (0.42 if wide else 0.55), c["ink"])]
        if puff:
            for k in range(3):
                a = math.pi + (k - 1) * 0.35
                r0 = 54 + 30 * window(t, 9.6, 10.8)
                out.append(L(cv, Shape().line([(hx - 30 + r0 * math.cos(a) * 0.6, hy + 12 + r0 * math.sin(a) * 0.6), (hx - 30 + (r0 + 18) * math.cos(a) * 0.6, hy + 12 + (r0 + 18) * math.sin(a) * 0.6)], 3.4), c["eye"], puff))
        return out

    def under(self, cv, p, t):
        c = self.colors(p)
        out = [L(cv, Shape().ellipse(self.FX, self.FY + 10, 300, 70), c["glow"], (0.16 if c["dark"] else 0.08) * (0.85 + 0.15 * wave(t, 0.8)), ss=1, soft=40)]
        out += self.flame(cv, c, self.FX, self.FY, 1.0, t, 0.0)
        rnd = random.Random(19)
        for i in range(16):  # sparks
            t0 = rnd.uniform(0, 24)
            u = ((t - t0) % 24) / 2.2
            if u < 1:
                x = self.FX + rnd.uniform(-40, 40) + 30 * u * rnd.choice((-1, 1)) + 8 * wave(t, 0.75, rnd.random())
                out.append(D(cv, x, self.FY - 110 - 260 * u, 2.4, c["flame3"], 0.9 * (1 - u)))
        u = window(t, 10.5, 13.2)  # the smoke from the marshmallow blown out
        if 0 < u < 1:
            tip = self.pose(t)[1]
            sx, sy = self.RX + tip[0], self.RY + tip[1]
            out.append(L(cv, Shape().ellipse(sx + 10 * u, sy - 30 - 90 * u, 10 + 16 * u, 16 + 22 * u), c["smoke"], 0.25 * bump(u), ss=1, soft=8 + 10 * u))
        out += self.raccoon(cv, c, t)
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        hx, hy = self.RX - 22, self.RY - 150
        out = bubble(cv, hx + 40, hy - 70, pop(t, 8.0, 9.6), "!", c["bubble"], c["ink"], tail=-1)
        u = window(t, 16.0, 18.4)
        if 0 < u < 1:
            out.append(L(cv, glyph(Shape(), "n", hx + 40 + 20 * u, hy - 50 - 70 * u, 30, 3.4), c["bubble"], bump(u)))
        return out


class Ufo(Scene, Cached):
    name = "ufo"
    HZ = 720.0
    COW = (1180.0, 862.0)
    HOVER = (1180.0, 400.0)

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            ink = p.pick("ansi_0", "fg")
            self._c = (p, dict(
                dark=dk, sky=p("bg"), star=p.pick("fg", "white"), planet=p.pick("bg+ansi_5:40", "bg+ansi_5:40"), ring=p.pick("bg+ansi_5:24", "bg+ansi_5:60"),
                mesa=p.pick("bg+ansi_1:10", "bg+ansi_1:14"), dune=p.pick("bg+ansi_3:12", "bg+ansi_3:22"), dune2=p.pick("bg+ansi_3:18", "bg+ansi_3:30"), dune3=p.pick("bg+ansi_3:24", "bg+ansi_3:38"),
                cactus=p.pick("ansi_0+ansi_2:24", "bg+ansi_2:52"), shadow=mix(ink, p("bg"), 0.5),
                saucer=p.pick("bg+fg:50", "bg+fg:34"), saucer2=p.pick("bg+fg:34", "bg+fg:52"), dome=p("accent"), alien=p("ansi_2"),
                beam=p("ansi_2"), lights=[p("ansi_1"), p("ansi_3"), p("ansi_2"), p("ansi_6"), p("ansi_5")],
                cow=p.pick("fg+white:40", "white"), spot=mix(ink, p("bg"), 0.1), nose=p.pick("ansi_5+white:45", "ansi_5+white:50"), horn=p.pick("bg+ansi_3:40", "bg+ansi_3:50"),
                ink=ink, bubble=p.pick("bg+fg:88", "white"),
            ))
        return self._c[1]

    def back(self, cv, p):
        c = self.colors(p)
        out = stars(cv, c["star"], 23, 120, 20, self.HZ - 40, alpha=0.5 if c["dark"] else 0.0)
        px, py = 380.0, 230.0
        out += [D(cv, px, py, 44, c["planet"])]
        ring = ellipse_pts(px, py, 86, 18, -0.25, n=80)
        out.append(L(cv, Shape().line(ring + [ring[0]], 7), c["ring"], ss=2, above=None))
        out.append(L(cv, Shape().poly(ellipse_pts(px, py, 44, 44, n=60, a0=math.pi, a1=2 * math.pi)), c["planet"]))  # the planet over the ring's back
        out.append(L(cv, Shape().poly([(0, self.HZ), (120, self.HZ), (150, 610), (330, 600), (360, self.HZ), (1500, self.HZ), (1530, 640), (1690, 632), (1720, 676), (1820, 670), (1840, self.HZ), (W, self.HZ), (W, self.HZ + 40), (0, self.HZ + 40)]), c["mesa"], ss=2))
        for col, pts in ((c["dune"], [(0, 730), (400, 700), (900, 740), (1400, 705), (1920, 735)]), (c["dune2"], [(0, 800), (500, 770), (1100, 810), (1600, 780), (1920, 800)]), (c["dune3"], [(0, 920), (600, 890), (1200, 930), (1920, 900)])):
            out.append(L(cv, Shape().poly([(0, H)] + spline(pts, closed=False, per=16) + [(W, H)]), col, ss=2))
        for x, y, s in ((360, 830, 1.0), (1640, 790, 0.8), (230, 760, 0.5)):
            out.append(L(cv, self.cactus(x, y, s), c["cactus"], ss=2))
        return out

    def cactus(self, x, y, s):
        sh = Shape().line([(x, y), (x, y - 150 * s)], 30 * s)
        sh.line([(x, y - 70 * s), (x - 40 * s, y - 70 * s), (x - 40 * s, y - 110 * s)], 20 * s)
        sh.line([(x, y - 90 * s), (x + 36 * s, y - 90 * s), (x + 36 * s, y - 128 * s)], 20 * s)
        return sh

    def ufopos(self, t):
        hx, hy = self.HOVER
        if t < 2.0:
            return None
        if t < 4.8:
            u = ease_out(window(t, 2.0, 4.8))
            return 2160 + (hx - 2160) * u, 100 + (hy - 100) * u, -0.25 * (1 - u)
        if t < 16.8:
            return hx + 8 * wave(t, 4), hy + 7 * wave(t, 2.6), 0.03 * wave(t, 4, 0.25)
        if t < 18.4:
            u = ease_in(window(t, 16.8, 18.4))
            return hx + (-400 - hx) * u, hy + (-160 - hy) * u, 0.25 * u
        return None

    def cowpos(self, t):
        x, y = self.COW
        lift = ease_io(window(t, 6.4, 11.0)) * (1 - ease_io(window(t, 12.8, 15.8)))
        top = self.HOVER[1] + 116
        bounce = 10 * bump(window(t, 15.8, 16.3))
        return x, y - (y - top) * lift - bounce, 0.14 * wave(t, 3) * lift, lift

    def cow(self, cv, c, x, y, rot, lift, t):
        graze = 0.0 if lift > 0.01 else (1 - ease_io(window(t, 19.0, 19.6)) + ease_io(window(t, 21.6, 22.4))) if 19.0 <= t < 22.4 else 1.0
        tf = lambda s: s.moved(x, y, 1.0, rot, 0, 0)
        out = []
        dangle = 0.22 * lift * wave(t, 1.1)
        legs = Shape()
        for lx in (-52, -30, 34, 54):
            a = dangle * (1 if lx < 0 else -1)
            legs.line([(lx, -40), (lx + 34 * math.sin(a), -40 + 36 * math.cos(a))], 12)
        out.append(L(cv, tf(legs), c["cow"]))
        hooves = Shape()
        for lx in (-52, -30, 34, 54):
            a = dangle * (1 if lx < 0 else -1)
            hooves.circle(lx + 36 * math.sin(a), -40 + 38 * math.cos(a), 6.5)
        out.append(L(cv, tf(hooves), c["spot"]))
        sw = 0.25 * wave(t, 2.4)
        out.append(L(cv, tf(Shape().line(bezier((70, -84), (90, -70), (86 + 10 * sw, -50), (82 + 20 * sw, -34), n=10), 4)), c["cow"]))
        out.append(L(cv, tf(Shape().circle(82 + 20 * sw, -32, 7)), c["spot"]))
        body = Shape().poly(spline([(-72, -60), (-62, -94), (0, -100), (62, -94), (76, -64), (66, -38), (0, -34), (-62, -38)], per=8))
        out.append(L(cv, tf(body), c["cow"]))
        out.append(L(cv, tf(Shape().ellipse(-18, -76, 20, 14, 0.3).ellipse(36, -62, 16, 18, -0.2).ellipse(52, -88, 12, 8)), c["spot"]))
        # the head: down in the grass, or up at the sky
        g = graze
        hx, hy = -92 + 4 * g, -100 + 62 * g
        ha = -0.5 + 0.6 * g
        head = Shape().ellipse(hx, hy, 26, 22, ha).ellipse(hx - 18 * math.cos(ha), hy - 18 * math.sin(ha) + 6, 17, 13, ha)
        out.append(L(cv, tf(Shape().line([(-60, -80), (hx + 10, hy)], 26)), c["cow"]))
        out.append(L(cv, tf(head), c["cow"]))
        out.append(L(cv, tf(Shape().ellipse(hx - 20 * math.cos(ha), hy - 20 * math.sin(ha) + 8, 13, 9, ha)), c["nose"]))
        out.append(L(cv, tf(Shape().line([(hx + 8, hy - 18), (hx + 16, hy - 32)], 5).line([(hx - 6, hy - 20), (hx - 10, hy - 34)], 5)), c["horn"]))
        out.append(L(cv, tf(Shape().ellipse(hx + 18, hy - 8, 10, 5, 0.6)), c["spot"]))
        ex, ey = hx - 4 + 4 * g, hy - 6
        out.append(L(cv, tf(Shape().circle(ex, ey, 3.6)), c["ink"]))
        return out

    def saucer(self, cv, c, x, y, rot, t):
        tf = lambda s: s.moved(x, y, 1.0, rot, 0, 0)
        out = [L(cv, tf(Shape().poly(ellipse_pts(0, -6, 52, 46, n=60, a0=math.pi, a1=2 * math.pi))), c["dome"], 0.45)]
        tilt = 0.4 * bump(window(t, 11.0, 12.8))
        out.append(L(cv, tf(Shape().ellipse(0, -20, 16, 18, tilt).line([(0, -6), (0, 4)], 9)), c["alien"]))
        for sx in (-6, 6):
            out.append(L(cv, tf(Shape().ellipse(sx + 2 * tilt * 10, -24, 5, 7, 0.3 * (1 if sx > 0 else -1))), c["ink"]))
        out.append(L(cv, tf(Shape().ellipse(0, 0, 124, 26)), c["saucer"]))
        out.append(L(cv, tf(Shape().ellipse(0, 10, 70, 12)), c["saucer2"]))
        out.append(L(cv, tf(Shape().ellipse(-18, -30, 14, 7, -0.5)), c["bubble"], 0.35))
        for k in range(7):
            on = int(t * 6 + k) % 5
            lx = -96 + k * 32
            out.append(D(cv, *tf(Shape().poly([(lx, 4 - 6 * (1 - (abs(lx) / 110) ** 2))])).cmds[0][1][0], 6, c["lights"][on]))
        return out

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        u = self.ufopos(t)
        cx, cy, rot, lift = self.cowpos(t)
        if u:
            bx, by, br = u
            beam = clamp((t - 5.4) / 0.6) * (1 - clamp((t - 15.8) / 0.6)) if 5.4 <= t < 16.4 else 0.0
            near = clamp(1 - (by - self.HOVER[1]) / 300) if t < 16.8 else 0.0
            out.append(L(cv, Shape().ellipse(bx, self.COW[1] + 4, 150, 22), c["shadow"], 0.35 * near, ss=1, soft=14))
            if beam:
                out.append(L(cv, Shape().poly([(bx - 46, by + 14), (bx + 46, by + 14), (bx + 150, self.COW[1] + 10), (bx - 150, self.COW[1] + 10)]), c["beam"], (0.2 if c["dark"] else 0.16) * beam, ss=1, soft=6))
                for k in range(5):  # rings rising in the beam
                    v = ((t * 0.6 + k / 5) % 1.0)
                    yy = self.COW[1] - (self.COW[1] - by - 20) * v
                    hw = 150 - 104 * v
                    pts = ellipse_pts(bx, yy, hw, hw * 0.14, n=60)
                    out.append(L(cv, Shape().line(pts + [pts[0]], 2.4), c["beam"], 0.35 * beam * bump(v), ss=2))
        out.append(L(cv, Shape().ellipse(cx, self.COW[1] + 2, 90, 10), c["shadow"], 0.4 * (1 - lift), ss=1, soft=4))
        out += self.cow(cv, c, cx, cy, rot, lift, t)
        if u:
            bx, by, br = u
            if 16.8 <= t < 18.4:  # it goes in a hurry
                for k in range(3):
                    out.append(L(cv, Shape().line([(bx + 150 + k * 30, by + 10 + k * 14), (bx + 280 + k * 50, by + 40 + k * 22)], 3), c["saucer"], 0.5 * (1 - window(t, 16.8, 18.4))))
            out += self.saucer(cv, c, bx, by, br, t)
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        cx, cy, rot, lift = self.cowpos(t)
        out = bubble(cv, cx - 140, cy - 150, pop(t, 8.0, 10.4), "moo", c["bubble"], c["ink"], tail=1)
        hx, hy = self.HOVER
        out += bubble(cv, hx + 110, hy - 90, pop(t, 11.2, 12.8), "?", c["bubble"], c["ink"], tail=-1)
        out += bubble(cv, cx - 150, cy - 190, pop(t, 19.8, 21.6), "?", c["bubble"], c["ink"], tail=1)
        return out


class Pigeons(Scene, Cached):
    name = "pigeons"
    WIRE = (140.0, 1780.0, 410.0, 56.0)  # its ends, its height, its sag
    PERCH = (560.0, 720.0, 1060.0, 1220.0, 1360.0)

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            ink = p.pick("ansi_0", "fg")
            bird = mix(p("muted"), p("ansi_4"), 0.18)
            self._c = (p, dict(
                dark=dk, sky=p("bg"), sun=p.pick("fg+ansi_3:15", "ansi_3+bg:30"), halo=p.pick("bg+accent:6", "bg+ansi_3:10"), star=p.pick("fg", "white"),
                cloud=p.pick("bg+fg:5", "bg+white:70"), far=p.pick("bg+fg:6", "bg+fg:7"), near=p.pick("bg+fg:11", "bg+fg:13"), roof=p.pick("bg+fg:15", "bg+fg:18"),
                window=p.pick("ansi_3", "bg+fg:4"), pole=p.pick("bg+fg:18", "bg+fg:45"), wire=p.pick("bg+fg:30", "bg+fg:50"),
                bird=bird, bird2=mix(bird, ink, 0.3), bird3=mix(bird, p("white"), 0.35), neck=mix(p("ansi_2"), p("ansi_5"), 0.5), foot=mix(p("ansi_1"), p("white"), 0.3),
                eye=p("ansi_3"), ink=ink, letter=p.pick("fg+white:40", "white"), seal=p("ansi_1"), smoke=p.pick("fg", "fg"), bubble=p.pick("bg+fg:88", "white"),
            ))
        return self._c[1]

    def wire_y(self, x, low=0.0):
        x0, x1, y, sag = self.WIRE
        m, half = (x0 + x1) / 2, (x1 - x0) / 2
        return y + low + sag * (1 - ((x - m) / half) ** 2)

    def back(self, cv, p):
        c = self.colors(p)
        sx, sy = 1560.0, 190.0
        out = [D(cv, sx, sy, 110, c["halo"]), D(cv, sx, sy, 50, c["sun"])]
        if c["dark"]:
            out += stars(cv, c["star"], 27, 70, 20, 520, alpha=0.4, avoid=(sx, sy, 140))
        rnd = random.Random(15)
        far = Shape()
        x = -20
        while x < W:
            w, h = rnd.uniform(70, 150), rnd.uniform(120, 260)
            far.rect(x, 720 - h, w, h + 10)
            x += w + rnd.uniform(-10, 20)
        out.append(L(cv, far, c["far"], ss=1))
        near = Shape()
        roofs = []
        x = -40
        while x < W:
            w, h = rnd.uniform(160, 300), rnd.uniform(240, 360)
            near.rect(x, H - h, w, h)
            roofs.append((x, H - h, w))
            x += w + rnd.uniform(0, 30)
        out.append(L(cv, near, c["near"], ss=1))
        rf = Shape()
        for x, y, w in roofs:
            rf.rect(x - 6, y - 10, w + 12, 12)
        out.append(L(cv, rf, c["roof"], ss=1))
        win = Shape()
        lit = Shape()
        for x, y, w in roofs:
            for wx in range(int(x + 22), int(x + w - 30), 46):
                for wy in range(int(y + 34), H - 20, 62):
                    if rnd.random() < 0.3:
                        (lit if rnd.random() < 0.5 else win).rect(wx, wy, 22, 30)
        out.append(L(cv, win, c["roof"], ss=1))
        out.append(L(cv, lit, c["window"], 0.55 if c["dark"] else 1.0, ss=1))
        # the water tower and an aerial
        x0, y0 = 1440.0, roofs[-2][1] if len(roofs) > 2 else 760.0
        wt = Shape().rect(x0 - 50, y0 - 160, 100, 90).poly([(x0 - 60, y0 - 160), (x0, y0 - 200), (x0 + 60, y0 - 160)])
        wt.line([(x0 - 40, y0 - 70), (x0 - 46, y0 - 10)], 6).line([(x0 + 40, y0 - 70), (x0 + 46, y0 - 10)], 6).line([(x0 - 40, y0 - 40), (x0 + 40, y0 - 40)], 4)
        out.append(L(cv, wt, c["roof"], ss=2))
        ax, ay = 480.0, roofs[2][1] if len(roofs) > 3 else 800.0
        out.append(L(cv, Shape().line([(ax, ay - 10), (ax, ay - 150)], 5).line([(ax - 40, ay - 120), (ax + 40, ay - 120)], 4).line([(ax - 28, ay - 90), (ax + 28, ay - 90)], 4), c["roof"], ss=2))
        # the poles and the wires
        x0, x1, wy, sag = self.WIRE
        poles = Shape()
        for px in (x0, x1):
            poles.line([(px, wy - 30), (px, H)], 16).line([(px - 50, wy), (px + 50, wy)], 10)
        out.append(L(cv, poles, c["pole"], ss=2))
        for low in (0.0, 30.0):
            pts = [(x, self.wire_y(x, low)) for x in range(int(x0), int(x1) + 1, 20)]
            out.append(L(cv, Shape().line(pts, 2.4), c["wire"], ss=2))
        return out

    def perched(self, cv, c, x, t, ph, kx=1.0, nod=0.0, letter=False):
        y = self.wire_y(x) - 2
        bob = 5 * max(0.0, wave(t, 1.6, ph)) + 8 * nod
        sh = lambda s: s.moved(x, y, 1.3, 0, 0, 0, kx)
        out = [L(cv, sh(Shape().line([(-6, 0), (-8, -12)], 3).line([(6, 0), (4, -12)], 3)), c["foot"])]
        out.append(L(cv, sh(Shape().poly([(26, -26), (54, -14), (50, -6), (24, -16)])), c["bird2"]))
        out.append(L(cv, sh(Shape().poly(spline([(-30, -40), (-8, -58), (20, -50), (34, -28), (14, -12), (-18, -14)], per=8))), c["bird"]))
        out.append(L(cv, sh(Shape().poly(spline([(-4, -50), (22, -44), (32, -28), (12, -24)], per=5))), c["bird2"], 0.7))
        hx, hy = -26 - bob * 0.6, -60 + bob * 0.5
        out.append(L(cv, sh(Shape().ellipse(hx + 6, hy + 14, 15, 13)), c["neck"]))
        out.append(L(cv, sh(Shape().circle(hx, hy, 14)), c["bird"]))
        out.append(L(cv, sh(Shape().poly([(hx - 12, hy - 2), (hx - 24, hy + 3), (hx - 12, hy + 5)])), c["ink"]))
        ex, ey = sh(Shape().poly([(hx - 4, hy - 3)])).cmds[0][1][0]
        out += [D(cv, ex, ey, 3.6, c["eye"]), D(cv, ex, ey, 1.6, c["ink"])]
        return out

    def flying(self, cv, c, x, y, kx, t, letter):
        f = math.sin(2 * math.pi * t / 0.34)
        sh = lambda s: s.moved(x, y, 1.3, 0.05 * f, 0, 0, kx)
        out = []
        if letter:
            out += self.envelope(cv, c, x + kx * 4, y + 32, 0.0)
        out.append(L(cv, sh(Shape().poly([(30, -2), (60, -12), (62, 6), (30, 8)])), c["bird2"]))
        far_wing = Shape().poly([(-4, -6), (22, -8), (10 - 4 * f, -34 - 26 * f)])
        out.append(L(cv, sh(far_wing), c["bird2"]))
        out.append(L(cv, sh(Shape().ellipse(4, 0, 36, 14)), c["bird"]))
        out.append(L(cv, sh(Shape().circle(-34, -8, 13)), c["bird"]))
        out.append(L(cv, sh(Shape().ellipse(-26, -2, 10, 9)), c["neck"]))
        out.append(L(cv, sh(Shape().poly([(-46, -10), (-58, -5), (-46, -3)])), c["ink"]))
        ex, ey = sh(Shape().poly([(-38, -12)])).cmds[0][1][0]
        out += [D(cv, ex, ey, 3.2, c["eye"]), D(cv, ex, ey, 1.4, c["ink"])]
        near_wing = Shape().poly([(-10, -4), (24, -4), (14 + 6 * f, -40 * f - 4)])
        out.append(L(cv, sh(near_wing), c["bird3"]))
        return out

    def envelope(self, cv, c, x, y, rot):
        tf = lambda s: s.moved(x, y, 1.25, rot)
        return [L(cv, tf(Shape().rect(-18, -12, 36, 24)), c["letter"]), L(cv, tf(Shape().line([(-18, -12), (0, 2), (18, -12)], 2)), c["bird2"]), L(cv, tf(Shape().circle(0, 2, 4)), c["seal"])]

    def drop(self, t):
        """The packet: where it is while it falls, or None."""
        if not 11.0 <= t < 13.4:
            return None
        u = t - 11.0
        return 1240 + 30 * math.sin(u * 4.2), 300 + 72 * u + 8 * u * u, 0.6 * math.sin(u * 4.2)

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        for i, (x, y, w) in enumerate(((560, 160, 1.0), (1060, 250, 0.7), (300, 320, 0.6))):
            dx = 40 * wave(t, 24, i * 0.3)
            cl = Shape().rect(x + dx - 110 * w, y, 220 * w, 30 * w).circle(x + dx - 50 * w, y + 4, 38 * w).circle(x + dx + 24 * w, y - 8 * w, 50 * w).circle(x + dx + 86 * w, y + 8, 30 * w)
            out.append(L(cv, cl, c["cloud"], ss=2, above=y + 30 * w))
        # the birds on the wire; the one in the middle goes and comes back
        nod = bump(window(t, 21.9, 22.5))
        for i, x in enumerate(self.PERCH):
            if i == 2 and 12.2 <= t < 21.4:
                continue
            out += self.perched(cv, c, x, t, i * 0.37, 1 if i % 2 else -1, nod if i == 3 else 0.0)
        # courier A, left to right, a letter in its feet
        if 0.5 <= t < 7.5:
            u = window(t, 0.5, 7.5)
            out += self.flying(cv, c, -120 + 2160 * u, 250 - 40 * math.sin(math.pi * u) + 8 * wave(t, 0.7), -1, t, True)
        # courier B, right to left: it lets go of its letter over the roofs
        if 8.0 <= t < 16.5:
            u = window(t, 8.0, 16.5)
            out += self.flying(cv, c, 2040 - 2200 * u, 300 + 6 * wave(t, 0.7), 1, t, t < 11.0)
        d = self.drop(t)
        if d:
            out += self.envelope(cv, c, *d)
        # C: off the wire, catches it, takes it on, comes back
        if 12.2 <= t < 21.4:
            px, py = self.PERCH[2], self.wire_y(self.PERCH[2]) - 30
            catch = self.drop(13.39)
            if t < 13.4:
                u = ease_io(window(t, 12.2, 13.4))
                x, y = px + (catch[0] - px) * u, py + (catch[1] - 24 - py) * u - 40 * math.sin(math.pi * u)
                out += self.flying(cv, c, x, y, -1, t, False)
            elif t < 17.0:
                u = window(t, 13.4, 17.0)
                out += self.flying(cv, c, catch[0] - (catch[0] + 160) * u, catch[1] - 24 - 120 * math.sin(math.pi * u * 0.5), 1, t, True)
            elif t >= 19.0:
                u = ease_out(window(t, 19.0, 21.4))
                out += self.flying(cv, c, -120 + (px + 120) * u, 200 + (py - 200) * u, -1, t, False)
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        px = self.PERCH[2]
        return bubble(cv, px + 50, self.wire_y(px) - 140, pop(t, 11.3, 12.3), "!", c["bubble"], c["ink"], tail=-1)


BLACK3 = (0.0, 0.0, 0.0)


def starfield(cv, seed, n, top, bottom, color, t=None, avoid=None, big=1.0):
    """Stars of many sizes and strengths; a few of them breathing over the loop."""
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        x, y = rnd.uniform(0, W), rnd.uniform(top, bottom)
        if avoid and math.hypot(x - avoid[0], y - avoid[1]) < avoid[2]:
            continue
        m = rnd.random() ** 3
        r, a = (0.6 + 1.6 * m) * big, 0.18 + 0.75 * m
        if t is not None and i % 5 == 0:
            a *= 0.55 + 0.45 * (0.5 + 0.5 * wave(t, 24 / rnd.choice((3, 4, 6, 8)), rnd.random()))
        out.append(D(cv, x, y, r, color, a))
        if m > 0.85:
            out.append(glow(cv, x, y, 5 * big, color, 0.18 * a))
    return out


class Garoa(Cinema, Cached):
    """Sao Paulo in the drizzle at night: the Copan's wave, the masts of Paulista
    with their red lights, helicopters going from roof to roof."""

    name = "garoa"
    HZ = 900.0  # where the street begins
    PADS = ((1095.0, 618.0), (1700.0, 586.0))  # two roofs with a helipad

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            bg = p("bg")
            self._c = (p, dict(
                dark=dk,
                top=mix(bg, BLACK3, 0.55) if dk else p("bg+fg:16"), low=mix(bg, p("ansi_1"), 0.16) if dk else p("bg+white:30"),
                far=mix(mix(bg, p("ansi_1"), 0.08), BLACK3, 0.18) if dk else p("bg+fg:20"), mid=mix(bg, BLACK3, 0.42) if dk else p("bg+fg:34"),
                near=mix(bg, BLACK3, 0.66) if dk else p("bg+fg:50"), copan=mix(bg, BLACK3, 0.3) if dk else p("bg+fg:28"), copan2=mix(bg, BLACK3, 0.5) if dk else p("bg+fg:40"),
                street=mix(bg, BLACK3, 0.58) if dk else p("bg+fg:42"),
                warm=p("ansi_3"), cool=p("accent"), red=p("ansi_1"), green=p("ansi_2"), white=p.pick("fg", "white"), fog=mix(bg, p("ansi_1"), 0.12) if dk else p("bg+white:40"),
                rain=p.pick("fg", "fg"), heli=mix(bg, BLACK3, 0.75) if dk else p("bg+fg:60"),
            ))
        return self._c[1]

    def towers(self):
        """The skyline, made once: (x, y, w, kind) for the far, the middle and the near rows."""
        if hasattr(self, "_towers"):
            return self._towers
        rnd = random.Random(41)
        far, mid, near = [], [], []
        x = -20
        while x < W:
            w = rnd.uniform(40, 110)
            far.append((x, rnd.uniform(560, 700), w))
            x += w + rnd.uniform(-8, 6)
        x = 860
        while x < W + 40:
            w = rnd.uniform(90, 170)
            mid.append((x, rnd.uniform(560, 720), w))
            x += w + rnd.uniform(6, 30)
        for x0, w, y in ((-40, 230, 520), (1810, 200, 470), (190, 120, 760)):
            near.append((x0, y, w))
        self._towers = far, mid, near
        return self._towers

    def windows(self, x, y, w, rnd, lit=0.35, step=(16, 22)):
        warm, cool = Shape(), Shape()
        for wx in range(int(x + 8), int(x + w - 10), step[0]):
            for wy in range(int(y + 14), int(self.HZ - 10), step[1]):
                if rnd.random() < lit:
                    (warm if rnd.random() < 0.7 else cool).rect(wx, wy, 7, 9)
        return warm, cool

    def back(self, cv, p):
        c = self.colors(p)
        out = [vgrad(cv, 0, 0, W, self.HZ, [(0, c["top"]), (520, mix(c["top"], c["low"], 0.6)), (self.HZ, c["low"])])]
        if c["dark"]:
            out.append(L(cv, Shape().ellipse(980, 760, 1100, 260), c["red"], 0.06, ss=1, soft=120, mode="add"))  # the city's glow on the cloud
        far, mid, near = self.towers()
        sh = Shape()
        for x, y, w in far:
            sh.rect(x, y, w, self.HZ - y)
            if w > 80:
                sh.rect(x + w / 2 - 1.5, y - 40, 3, 40)
        out.append(L(cv, sh, c["far"], ss=1))
        out.append(L(cv, Shape().rect(0, 610, W, 120), c["fog"], 0.35, ss=1, soft=40))
        # the masts of Paulista: lattices with lights
        for mx, top in ((1330.0, 270.0), (1470.0, 230.0), (1590.0, 300.0)):
            m = Shape().line([(mx - 14, 640), (mx, top), (mx + 14, 640)], 3)
            for k in range(10):
                y0 = top + (640 - top) * k / 10
                y1 = top + (640 - top) * (k + 1) / 10
                hw0, hw1 = 14 * (y0 - top) / (640 - top), 14 * (y1 - top) / (640 - top)
                m.line([(mx - hw0, y0), (mx + hw1, y1)], 1.4).line([(mx + hw0, y0), (mx - hw1, y1)], 1.4)
            out.append(L(cv, m, c["mid"], ss=2))
        # the Copan: a long wave of a building, its sunshades in lines
        cp = [(300, 470), (420, 455), (560, 470), (700, 452), (860, 468), (900, 470)]
        body = Shape().poly(spline(cp, closed=False, per=10) + [(900, self.HZ), (300, self.HZ)])
        out.append(L(cv, body, c["copan"], ss=2))
        shade = Shape()
        for k in range(7):
            x0 = 300 + k * 86
            shade.poly([(x0, 460), (x0 + 40, 460), (x0 + 30, self.HZ), (x0 - 4, self.HZ)])
        out.append(L(cv, shade, c["copan2"], 0.55, ss=1, soft=14, clip=None))
        lines = Shape()
        for y in range(484, int(self.HZ), 11):
            lines.line([(300, y), (900, y)], 3.2)
        out.append(L(cv, lines, c["far"], 0.75, ss=2))
        rnd = random.Random(8)
        lit = Shape()
        for y in range(489, int(self.HZ) - 6, 11):
            for x in range(306, 896, 9):
                if rnd.random() < 0.07:
                    lit.rect(x, y, 5, 3)
        out.append(L(cv, lit, c["warm"], 0.65 if c["dark"] else 0.25, ss=2))
        # the middle row with its windows, two of them with a helipad on the roof
        rnd = random.Random(19)
        for x, y, w in mid:
            out.append(L(cv, Shape().rect(x, y, w, self.HZ - y), c["mid"], ss=1))
            wm, cl = self.windows(x, y, w, rnd)
            out += [L(cv, wm, c["warm"], 0.7 if c["dark"] else 0.3, ss=1), L(cv, cl, c["cool"], 0.6 if c["dark"] else 0.3, ss=1)]
        for px, py in self.PADS:
            out.append(L(cv, Shape().rect(px - 70, py, 140, self.HZ - py), c["mid"], ss=1))
            ring = ellipse_pts(px, py - 2, 46, 8, n=48)
            out.append(L(cv, Shape().line(ring + [ring[0]], 2.4), c["white"], 0.45, ss=2))
            out.append(L(cv, glyph_h(px, py - 2), c["white"], 0.5, ss=2))
            wm, cl = self.windows(px - 70, py, 140, rnd)
            out += [L(cv, wm, c["warm"], 0.7 if c["dark"] else 0.3, ss=1), L(cv, cl, c["cool"], 0.6 if c["dark"] else 0.3, ss=1)]
        # the near buildings, framing it, and the street
        for x, y, w in near:
            out.append(L(cv, Shape().rect(x, y, w, self.HZ - y), c["near"], ss=1))
            wm, cl = self.windows(x, y, w, rnd, lit=0.18, step=(20, 26))
            out.append(L(cv, wm, c["warm"], 0.55 if c["dark"] else 0.25, ss=1))
        out.append(L(cv, Shape().rect(0, self.HZ, W, H - self.HZ), c["street"], ss=1))
        # the wet street: every light above it drawn again below, long and soft
        refl = Shape()
        for x, y, w in mid + near:
            for k in range(3):
                refl.rect(x + w * (0.2 + 0.25 * k), self.HZ + 4, 5, 70 + 40 * k)
        out.append(L(cv, refl, c["warm"], 0.12 if c["dark"] else 0.06, ss=1, soft=6))
        return out

    def heli(self, cv, c, x, y, t, kx=1.0, tilt=0.0, parked=False):
        tf = lambda s: s.moved(x, y, 1.0, tilt, 0, 0, kx)
        out = [L(cv, tf(Shape().ellipse(0, 0, 22, 9).line([(10, -2), (52, -6)], 3.2).line([(50, -6), (56, -16)], 2.4).line([(-12, 10), (14, 10)], 2)), c["heli"])]
        blade = 0.0 if parked else (1 if int(t * 30) % 2 else 0.4)
        out.append(L(cv, tf(Shape().line([(-34 * blade - 4, -12), (34 * blade + 4, -12)], 1.8)), c["heli"], 0.85))
        on = int(t * 1.5) % 2 == 0
        strobe = (t * 1.25) % 1.0 < 0.08
        px, py = tf(Shape().poly([(56, -14)])).cmds[0][1][0]
        out.append(D(cv, px, py, 2.4, c["red"], 1.0 if on else 0.25))
        if on:
            out.append(glow(cv, px, py, 10, c["red"], 0.35))
        if strobe and not parked:
            bx, by = tf(Shape().poly([(0, 9)])).cmds[0][1][0]
            out += [D(cv, bx, by, 2.2, c["white"]), glow(cv, bx, by, 16, c["white"], 0.4)]
        return out

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        out.append(L(cv, Shape().rect(-200 + 60 * wave(t, 24), 640, W + 400, 70), c["fog"], 0.22, ss=1, soft=36))
        for k, (mx, top) in enumerate(((1330.0, 270.0), (1470.0, 230.0), (1590.0, 300.0))):  # the masts' red lights, out of step
            on = ((t + k * 0.7) % 2.0) < 1.0
            for yy in (top, top + (640 - top) * 0.45):
                out.append(D(cv, mx, yy, 2.6, c["red"], 1.0 if on else 0.2))
                if on:
                    out.append(glow(cv, mx, yy, 14, c["red"], 0.4))
        x, y = self.PADS[0]
        out += self.heli(cv, c, x - 4, y - 14, t, 1.0, 0.0, parked=True)  # the one already there
        # the late one: it comes for the first roof, finds it taken, goes round, takes the second
        if 2.0 <= t < 17.5:
            if t < 6.5:
                u = ease_io(window(t, 2.0, 6.5))
                hx, hy = -80 + (x + 30 + 80) * u, 300 + (y - 120 - 300) * u
            elif t < 9.5:
                hx, hy = x + 30 + 18 * math.sin((t - 6.5) * 2.2), y - 120 + 8 * math.sin((t - 6.5) * 3)
            else:
                px2, py2 = self.PADS[1]
                u = ease_io(window(t, 9.5, 17.0))
                hx = x + 30 + (px2 - x - 30) * u
                hy = (y - 120) + ((py2 - 16) - (y - 120)) * u - 120 * math.sin(math.pi * u)
            out += self.heli(cv, c, hx, hy, t, -1.0 if t >= 9.5 else 1.0, 0.08 if t < 6.5 or t >= 9.5 else 0.0)
        if 17.0 <= t < 20.0:  # down on the second roof, a breath, then off again
            px2, py2 = self.PADS[1]
            out += self.heli(cv, c, px2, py2 - 16, t, -1.0, 0.0, parked=18.5 <= t < 19.5)
        elif t >= 20.0:
            px2, py2 = self.PADS[1]
            u = ease_in(window(t, 20.0, 23.6))
            out += self.heli(cv, c, px2 + 400 * u, py2 - 16 - 300 * u, t, -1.0, -0.1 * u)
        # cars on the street: light going by
        for k in range(4):
            u = ((t / 6.0) + k / 4) % 1.0
            xx = -100 + (W + 200) * u if k % 2 else W + 100 - (W + 200) * u
            col = c["white"] if k % 2 else c["red"]
            out.append(L(cv, Shape().line([(xx - 30, 950 + k * 18), (xx + 30, 950 + k * 18)], 3), col, 0.5, ss=1, soft=3))
            out.append(L(cv, Shape().line([(xx - 30, 990 + k * 18), (xx + 30, 990 + k * 18)], 8), col, 0.08, ss=1, soft=10))
        # the green cross of the pharmacy that never closes, with a flicker
        fl = 0.35 if (int(t * 8) % 37) in (3, 4, 19) else 1.0
        cx, cy = 1880.0, 640.0
        cross = Shape().rect(cx - 9, cy - 26, 18, 52).rect(cx - 26, cy - 9, 52, 18)
        out += [L(cv, cross, c["green"], fl), glow(cv, cx, cy, 70, c["green"], 0.25 * fl), L(cv, Shape().rect(cx - 12, self.HZ + 6, 24, 120), c["green"], 0.12 * fl, ss=1, soft=10)]
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        out = []
        rnd = random.Random(23)
        rain = Shape()
        for i in range(260):  # drizzle: thin, slanted, quick
            x0, y0 = rnd.uniform(-100, W), rnd.uniform(0, H)
            ln = rnd.uniform(14, 34)
            y = (y0 + (H + 60) * 6 * t / self.seconds) % (H + 60) - 30
            x = x0 + 0.22 * ((y0 + (H + 60) * 6 * t / self.seconds) // (H + 60)) * 0 + 0.2 * y
            rain.line([(x, y), (x + ln * 0.22, y + ln)], 1.1)
        out.append(L(cv, rain, c["rain"], 0.16 if c["dark"] else 0.14, ss=2))
        return out


def glyph_h(x, y):
    """An H laid flat on a roof, as a pilot sees it from far off."""
    return Shape().line([(x - 14, y - 4), (x - 10, y + 4)], 2).line([(x + 10, y - 4), (x + 14, y + 4)], 2).line([(x - 12, y), (x + 12, y)], 2)


class Horizon(Cinema, Cached):
    """A black hole over the edge of an ice planet: its disc turns, its light
    bends over the top. Now and then a probe falls in, and never quite does."""

    name = "horizon"
    CX, CY, RS = 1210.0, 420.0, 118.0

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            bg = p("bg")
            hot = mix(p("ansi_3"), (255.0, 255.0, 255.0), 0.55)
            self._c = (p, dict(
                dark=dk, top=mix(bg, BLACK3, 0.62) if dk else p("bg+white:30"), low=mix(bg, BLACK3, 0.4) if dk else p("bg"),
                star=p.pick("fg", "fg"), neb1=p("accent"), neb2=p("ansi_5"),
                shadow=mix(bg, BLACK3, 0.92) if dk else mix(p("fg"), BLACK3, 0.2), hot=hot if dk else p("ansi_3"), warm=p("ansi_3") if dk else mix(p("ansi_3"), p("ansi_1"), 0.5), cool=p("ansi_1"),
                ring=mix(p("fg"), p("ansi_3"), 0.25) if dk else p("fg"), planet=mix(bg, BLACK3, 0.25) if dk else p("bg+fg:10"), planet2=mix(bg, BLACK3, 0.45) if dk else p("bg+fg:18"),
                limb=p("accent"), probe=p.pick("fg", "fg"),
            ))
        return self._c[1]

    def back(self, cv, p):
        c = self.colors(p)
        out = [vgrad(cv, 0, 0, W, H, [(0, c["top"]), (H, c["low"])])]
        if c["dark"]:
            out.append(L(cv, Shape().ellipse(520, 300, 520, 200, 0.4), c["neb1"], 0.05, ss=1, soft=140, mode="add"))
            out.append(L(cv, Shape().ellipse(1500, 820, 420, 160, -0.3), c["neb2"], 0.04, ss=1, soft=120, mode="add"))
        out += starfield(cv, 12, 520, 0, H, c["star"], avoid=(self.CX, self.CY, 300))
        # the planet's edge, lit from the disc
        out.append(L(cv, Shape().circle(260, 1820, 1060), c["planet"], ss=2))
        for k in range(5):  # its ice in bands
            out.append(L(cv, Shape().line([(x, 1820 - math.sqrt(max(0, (1060 - 60 - k * 70) ** 2 - (x - 260) ** 2))) for x in range(-200, 1300, 20)], 2.2), c["planet2"], 0.6, ss=2))
        limb = [(x, 1820 - math.sqrt(max(0, 1060 ** 2 - (x - 260) ** 2))) for x in range(-200, 1330, 10)]
        out.append(L(cv, Shape().line(limb, 3), c["limb"], 0.8, ss=2))
        out.append(L(cv, Shape().line(limb, 22), c["limb"], 0.12 if c["dark"] else 0.08, ss=1, soft=14, mode="add" if c["dark"] else "over"))
        return out

    def light(self, cv, c, t):
        """The disc and the light bent round the hole, worked out a pixel at a time:
        hot at its inner edge, turning, brighter on the side coming toward us."""
        cx, cy, rs = self.CX, self.CY, self.RS
        b = cv.box(cx - 600, cy - 230, cx + 600, cy + 230)
        px0, py0, px1, py1 = b
        X = (np.arange(px0, px1, dtype=np.float32) + 0.5)[None, :] / cv.s - cx
        Y = (np.arange(py0, py1, dtype=np.float32) + 0.5)[:, None] / cv.s - cy
        tilt = -0.08
        xr = X * math.cos(tilt) + Y * math.sin(tilt)
        yr = -X * math.sin(tilt) + Y * math.cos(tilt)
        q, rin, rout = 0.085, 132.0, 560.0
        rho = np.sqrt(xr ** 2 + (yr / q) ** 2)
        phi = np.arctan2(yr / q, xr)
        f = np.clip((rho - rin) / (rout - rin), 0, 1)
        edge = np.clip((rho - rin) / 10, 0, 1) * np.clip((rout - rho) / 120, 0, 1)
        swirl = 0.82 + 0.18 * np.sin(phi * 5 + rho * 0.025 - 2 * math.pi * 2 * t / self.seconds) * np.sin(phi * 2 - rho * 0.012 + 1.3)
        doppler = 1 - 0.42 * np.cos(phi)
        disc = 1.7 * edge * (rin / np.maximum(rho, rin)) ** 1.25 * swirl * doppler
        r = np.sqrt(X ** 2 + Y ** 2)
        behind = (yr < 0) & (r < rs)  # the far half, where the hole is in front of it
        disc = np.where(behind, 0, disc)
        theta = np.arctan2(Y, X)
        lensed = 0.75 * np.exp(-((r - rs * 1.19) / 8.5) ** 2) * (0.5 + 0.5 * np.abs(np.sin(theta))) * (1 - 0.35 * np.cos(theta))
        photon = np.exp(-((r - rs * 1.03) / 1.8) ** 2) * 0.9
        hot, warm, cool = (np.asarray(c[k], np.float32) for k in ("hot", "warm", "cool"))
        fc = f[..., None]
        col = np.where(fc < 0.35, hot + (warm - hot) * (fc / 0.35), warm + (cool - warm) * np.clip((fc - 0.35) / 0.65, 0, 1))
        ring_col = (hot * 0.5 + warm * 0.5)
        total = disc + lensed + photon
        mixed = (col * disc[..., None] + ring_col * lensed[..., None] + np.asarray(c["ring"], np.float32) * photon[..., None]) / np.maximum(total, 1e-4)[..., None]
        cov = np.clip(total, 0, 1.6).astype(np.float32)
        if c["dark"]:
            return Layer((cov, slice(py0, py1), slice(px0, px1)), mixed.astype(np.float32), 1.0, "add")
        return Layer((np.clip(cov, 0, 1), slice(py0, py1), slice(px0, px1)), mixed.astype(np.float32), 0.9)

    def under(self, cv, p, t):
        c = self.colors(p)
        cx, cy, rs = self.CX, self.CY, self.RS
        out = []
        if c["dark"]:
            out.append(glow(cv, cx, cy, 320, c["warm"], 0.09))
        out.append(D(cv, cx, cy, rs, c["shadow"]))
        out.append(self.light(cv, c, t))
        # the probe: it falls toward the edge, slows, reddens, dims, and is never seen to cross
        u = window(t, 3.0, 21.0)
        if 0 < u < 1:
            s = 1 - (1 - u) ** 3
            r = 900 - (900 - (rs + 46)) * s
            ang = -0.62 + 0.9 * s
            x, y = cx + r * math.cos(ang), cy + r * math.sin(ang) * 0.6
            redden = clamp((s - 0.7) / 0.3)
            col = mix(c["probe"], c["cool"], redden)
            blink = 0.35 + 0.65 * (1 if (t * (2.0 - 1.7 * redden)) % 1.0 < 0.5 else 0)
            fade = 1 - clamp((u - 0.82) / 0.18)
            out.append(D(cv, x, y, 2.4, col, blink * fade))
            if c["dark"]:
                out.append(glow(cv, x, y, 10, col, 0.3 * blink * fade))
        return out


SCENES_NIGHT = (Garoa(), Horizon())


def limbs(joints, w):
    """A figure from its joints: head, neck, hip, and each hand and foot through
    its elbow or knee, as round strokes."""
    j = joints
    sh = Shape().circle(j["head"][0], j["head"][1], w * 0.95)
    sh.line([j["neck"], j["hip"]], w * 1.8)
    sh.line([((j["neck"][0] + j["hip"][0]) / 2, (j["neck"][1] + j["hip"][1]) / 2 - w * 0.3), j["neck"]], w * 2.1)  # the chest, broader
    for a, b in (("elbow_l", "hand_l"), ("elbow_r", "hand_r")):
        sh.line([j["neck"], j[a], j[b]], w * 0.75)
        sh.circle(j[b][0], j[b][1], w * 0.42)
    for a, b in (("knee_l", "foot_l"), ("knee_r", "foot_r")):
        sh.line([j["hip"], j[a], j[b]], w * 0.95)
        sh.ellipse(j[b][0] + w * 0.3, j[b][1] + w * 0.1, w * 0.62, w * 0.36)
    return sh


def pose_mix(a, b, u):
    return {k: (a[k][0] + (b[k][0] - a[k][0]) * u, a[k][1] + (b[k][1] - a[k][1]) * u) for k in a}


class Watch(Cinema, Cached):
    """A night sail on a long swell, the moon low; a lighthouse sweeps the
    water. It is beating upwind: twice a loop it tacks."""

    name = "watch"
    HZ = 610.0

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            bg = p("bg")
            self._c = (p, dict(
                dark=dk, top=mix(bg, BLACK3, 0.6) if dk else p("bg+fg:10"), low=mix(bg, p("accent"), 0.14) if dk else p("bg+white:45"),
                sea=mix(bg, BLACK3, 0.42) if dk else p("bg+ansi_4:22"), deep=mix(bg, BLACK3, 0.66) if dk else p("bg+ansi_4:34"),
                moon=p.pick("fg+ansi_3:12", "ansi_3+white:40"), glint=p.pick("fg", "white"), cloud=mix(bg, BLACK3, 0.5) if dk else p("bg+fg:14"),
                land=mix(bg, BLACK3, 0.7) if dk else p("bg+fg:40"), beam=p.pick("ansi_3+white:50", "white"),
                hull=mix(bg, BLACK3, 0.8) if dk else p("bg+fg:62"), sail=mix(bg, BLACK3, 0.62) if dk else p("bg+fg:8"), rim=p.pick("fg+accent:30", "fg"),
                red=p("ansi_1"), green=p("ansi_2"), white=p.pick("fg", "white"), star=p.pick("fg", "fg"),
            ))
        return self._c[1]

    def back(self, cv, p):
        c = self.colors(p)
        out = [vgrad(cv, 0, 0, W, self.HZ, [(0, c["top"]), (self.HZ, c["low"])])]
        if c["dark"]:
            out += starfield(cv, 31, 260, 0, self.HZ - 120, c["star"], big=0.9)
        mx, my = 560.0, 470.0
        out += [glow(cv, mx, my, 160, c["moon"], 0.14 if c["dark"] else 0.25), D(cv, mx, my, 40, c["moon"])]
        for y, h, x0, w in ((420, 26, -100, 900), (452, 18, 300, 700), (500, 22, 1000, 1100)):  # long thin clouds, one over the moon
            out.append(L(cv, Shape().ellipse(x0 + w / 2, y, w / 2, h), c["cloud"], 0.8, ss=1, soft=10))
        out.append(vgrad(cv, 0, self.HZ, W, H, [(self.HZ, c["sea"]), (H, c["deep"])]))
        out.append(L(cv, Shape().poly([(0, self.HZ + 2), (0, self.HZ - 40), (90, self.HZ - 46), (170, self.HZ - 30), (260, self.HZ - 22), (330, self.HZ + 2)]), c["land"], ss=2))
        out.append(L(cv, Shape().rect(216, self.HZ - 84, 12, 62).poly([(212, self.HZ - 84), (222, self.HZ - 98), (232, self.HZ - 84)]), c["land"], ss=2))
        return out

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        # the moon's road on the water: short glints that come and go
        rnd = random.Random(5)
        for i in range(90):
            y = self.HZ + 6 + (H - self.HZ) * rnd.random() ** 1.8
            spread = 30 + (y - self.HZ) * 0.45
            x = 560 + rnd.uniform(-1, 1) * spread
            a = 0.5 + 0.5 * wave(t, 24 / rnd.choice((6, 8, 12)), rnd.random())
            out.append(L(cv, Shape().line([(x - 6 - (y - self.HZ) * 0.03, y), (x + 6 + (y - self.HZ) * 0.03, y)], 1.6 + (y - self.HZ) * 0.006), c["glint"], (0.55 if c["dark"] else 0.7) * a, ss=1))
        # the swell: long lines rolling toward us
        for k in range(9):
            u = ((t / 8.0) + k / 9) % 1.0
            y = self.HZ + 10 + (H - self.HZ) * u ** 1.6
            pts = [(x, y + 6 * math.sin(x / 140 + k)) for x in range(-20, W + 21, 40)]
            out.append(L(cv, Shape().line(pts, 1.2 + 2.5 * u), c["deep"], 0.5 * bump(u) + 0.1, ss=1))
        # the lighthouse: a beam that turns, three times a loop
        ang = 2 * math.pi * t / 8.0
        reach = 900 * abs(math.cos(ang))
        lx, ly = 222.0, self.HZ - 92
        side = 1 if math.cos(ang) > 0 else -1
        beam = Shape().poly([(lx, ly - 4), (lx + side * reach, ly - 30 - 40 * abs(math.sin(ang))), (lx + side * reach, ly + 30), (lx, ly + 4)])
        facing = max(0.0, math.sin(ang)) ** 6
        out.append(L(cv, beam, c["beam"], 0.10 + 0.08 * facing, ss=1, soft=18, mode="add" if c["dark"] else "over"))
        out.append(glow(cv, lx, ly, 10 + 40 * facing, c["beam"], 0.6 + 0.4 * facing))
        # the boat: it heels, rides the swell, and tacks at six and eighteen seconds
        k1 = ease_io(window(t, 5.0, 7.0))
        k2 = ease_io(window(t, 17.0, 19.0))
        kx = 1 - 2 * k1 + 2 * k2  # 1: bow to the right, -1: bow to the left
        bx = 1180 - 90 * math.sin(2 * math.pi * (t - 6) / 24)
        by = self.HZ + 92 + 6 * wave(t, 4)
        heel = 0.2 * kx * (1 - 0.6 * bump(window(t, 5.0, 7.0)) - 0.6 * bump(window(t, 17.0, 19.0))) + 0.03 * wave(t, 4, 0.2)
        luff = bump(window(t, 5.0, 7.0)) + bump(window(t, 17.0, 19.0))
        f = kx if abs(kx) > 0.06 else (0.06 if kx >= 0 else -0.06)
        tf = lambda s: s.moved(bx, by, 1.4, heel, 0, 0, f)
        wake = Shape().line([(bx - f * 40, by + 8), (bx - f * 260, by + 18)], 3)
        out.append(L(cv, wake, c["glint"], 0.18, ss=1, soft=4))
        hull = Shape().poly([(-70, -6), (78, -10), (60, 10), (-56, 10)])
        mast = Shape().line([(0, -8), (6, -190)], 3)
        main = Shape().poly([(8, -186), (10 + 60 * luff, -100), (12, -12), (-62 + 30 * luff, -14)])
        jib = Shape().poly([(6, -170), (74, -10), (20, -12)])
        out.append(L(cv, tf(main).moved(1.5, -1.5), c["rim"], 0.6))
        out.append(L(cv, tf(jib).moved(1.5, -1.5), c["rim"], 0.6))
        out += [L(cv, tf(main), c["sail"]), L(cv, tf(jib), c["sail"]), L(cv, tf(mast), c["hull"]), L(cv, tf(hull), c["hull"])]
        tx, ty = tf(Shape().poly([(6, -192)])).cmds[0][1][0]
        out += [D(cv, tx, ty, 2.2, c["white"]), glow(cv, tx, ty, 10, c["white"], 0.4)]
        nx, ny = tf(Shape().poly([(74, -10)])).cmds[0][1][0]
        col = c["green"] if kx > 0 else c["red"]
        out += [D(cv, nx, ny, 2.6, col), glow(cv, nx, ny, 14, col, 0.45)]
        return out


class Problem(Cinema, Cached):
    """A bouldering wall at night under one light, chalk hanging in the beam. The
    climber works the crux, comes off, chalks up, and starts again."""

    name = "problem"

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            bg = p("bg")
            self._c = (p, dict(
                dark=dk, room=mix(bg, BLACK3, 0.7) if dk else p("bg+fg:22"), wall=mix(bg, BLACK3, 0.45) if dk else p("bg+fg:8"), wall2=mix(bg, BLACK3, 0.55) if dk else p("bg+fg:14"),
                bolt=mix(bg, BLACK3, 0.75) if dk else p("bg+fg:30"), pad=mix(bg, BLACK3, 0.62) if dk else p("bg+fg:42"), seam=mix(bg, BLACK3, 0.8) if dk else p("bg+fg:55"),
                light=p.pick("ansi_3+white:60", "white"), chalk=p.pick("fg", "white"), body=mix(bg, BLACK3, 0.85) if dk else p("bg+fg:75"), rim=p.pick("ansi_3+white:50", "accent"),
                holds=[p("ansi_1"), p("ansi_2"), p("ansi_3"), p("ansi_4"), p("ansi_5"), p("ansi_6"), p("accent")],
            ))
        return self._c[1]

    WALL = [(420, 120), (1500, 120), (1640, 860), (280, 860)]  # an overhang, seen from the side and below

    def back(self, cv, p):
        c = self.colors(p)
        out = [L(cv, Shape().rect(0, 0, W, H), c["room"], ss=1)]
        out.append(L(cv, Shape().poly(self.WALL), c["wall"], ss=2))
        panels = Shape()
        for k in range(1, 6):
            u = k / 6
            panels.line([(420 + 1080 * u, 120), (280 + 1360 * u, 860)], 2)
        for k in range(1, 4):
            v = k / 4
            panels.line([(420 - 140 * v, 120 + 740 * v), (1500 + 140 * v, 120 + 740 * v)], 2)
        out.append(L(cv, panels, c["wall2"], 0.8, ss=2))
        bolts = Shape()
        for i in range(24):
            for j in range(14):
                u, v = (i + 0.5) / 24, (j + 0.5) / 14
                x = 420 - 140 * v + (1080 + 280 * v) * u
                bolts.circle(x, 120 + 740 * v, 2.2)
        out.append(L(cv, bolts, c["bolt"], ss=2))
        rnd = random.Random(17)
        for i in range(70):  # the holds: every route a color
            u, v = rnd.uniform(0.03, 0.97), rnd.uniform(0.05, 0.95)
            x, y = 420 - 140 * v + (1080 + 280 * v) * u, 120 + 740 * v
            col = c["holds"][i % len(c["holds"])]
            r = rnd.uniform(9, 22)
            sh = Shape().poly(spline([(x + r * math.cos(a) * rnd.uniform(0.7, 1.2), y + r * 0.8 * math.sin(a) * rnd.uniform(0.7, 1.2)) for a in [k * math.pi / 3 for k in range(6)]], per=4))
            out.append(L(cv, sh, mix(col, c["room"], 0.25), ss=2))
        out.append(L(cv, Shape().poly([(200, 880), (1720, 880), (1800, 1040), (120, 1040)]), c["pad"], ss=2))
        out.append(L(cv, Shape().line([(600, 880), (560, 1040)], 3).line([(1000, 880), (1000, 1040)], 3).line([(1400, 880), (1440, 1040)], 3).line([(160, 960), (1760, 960)], 2), c["seam"], ss=2))
        out.append(L(cv, Shape().poly([(560, -20), (760, -20), (1240, 1060), (300, 1060)]), c["light"], 0.10 if c["dark"] else 0.18, ss=1, soft=60, mode="add" if c["dark"] else "over"))
        return out

    # where the climber is at each moment: a few poses, and the times between them
    POSES = {
        "start": dict(head=(820, 690), neck=(830, 712), hip=(850, 790), elbow_l=(800, 690), hand_l=(790, 650), elbow_r=(870, 690), hand_r=(880, 640), knee_l=(810, 820), foot_l=(800, 860), knee_r=(895, 815), foot_r=(900, 850)),
        "mid": dict(head=(900, 520), neck=(905, 545), hip=(930, 630), elbow_l=(870, 510), hand_l=(860, 470), elbow_r=(950, 520), hand_r=(975, 480), knee_l=(880, 660), foot_l=(870, 700), knee_r=(980, 650), foot_r=(990, 690)),
        "reach": dict(head=(960, 400), neck=(962, 426), hip=(985, 510), elbow_l=(930, 400), hand_l=(925, 360), elbow_r=(1010, 360), hand_r=(1040, 300), knee_l=(950, 545), foot_l=(940, 590), knee_r=(1020, 540), foot_r=(1035, 585)),
        "air": dict(head=(990, 560), neck=(985, 585), hip=(985, 670), elbow_l=(940, 560), hand_l=(920, 520), elbow_r=(1030, 560), hand_r=(1050, 520), knee_l=(960, 720), foot_l=(950, 770), knee_r=(1020, 720), foot_r=(1030, 770)),
        "sit": dict(head=(1000, 820), neck=(1000, 845), hip=(1010, 915), elbow_l=(970, 870), hand_l=(990, 900), elbow_r=(1040, 870), hand_r=(1020, 900), knee_l=(960, 900), foot_l=(940, 940), knee_r=(1060, 900), foot_r=(1080, 940)),
        "stand": dict(head=(880, 760), neck=(882, 785), hip=(885, 865), elbow_l=(860, 815), hand_l=(875, 840), elbow_r=(905, 815), hand_r=(890, 840), knee_l=(870, 905), foot_l=(865, 945), knee_r=(900, 905), foot_r=(905, 945)),
    }
    KEYS = [(0.0, "start"), (3.0, "start"), (6.0, "mid"), (9.0, "reach"), (10.2, "reach"), (10.6, "air"), (11.0, "sit"), (15.5, "sit"), (17.5, "stand"), (21.0, "stand"), (23.4, "start")]

    def pose(self, t):
        for (t0, a), (t1, b) in zip(self.KEYS, self.KEYS[1:]):
            if t0 <= t < t1:
                u = (t - t0) / (t1 - t0)
                return pose_mix(self.POSES[a], self.POSES[b], u if a == "reach" else ease_io(u))
        return self.POSES["start"]

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        j = self.pose(t)
        fig = limbs(j, 17)
        out.append(L(cv, fig.moved(3, -2), c["rim"], 0.5 if c["dark"] else 0.6))
        out.append(L(cv, fig, c["body"]))
        for age, (x, y), big in ((t - 11.0, (1000, 930), 1.0), (t - 16.0, (1000, 880), 0.5), (t - 21.3, (885, 840), 0.4)):  # chalk: the landing, then chalking up
            u = age / 2.2
            if 0 <= u < 1:
                out.append(L(cv, Shape().ellipse(x, y - 30 * u, (40 + 120 * u) * big, (20 + 40 * u) * big), c["chalk"], 0.22 * (1 - u), ss=1, soft=16))
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        out = []
        rnd = random.Random(29)
        for i in range(70):  # chalk hanging in the beam, drifting
            x0, y0 = rnd.uniform(500, 1200), rnd.uniform(60, 1000)
            x = x0 + 30 * wave(t, 24 / rnd.choice((1, 2, 3)), rnd.random())
            y = y0 + 26 * wave(t, 24 / rnd.choice((1, 2, 3)), rnd.random())
            inside = clamp(1 - abs(x - (560 + (y / 1060) * 340 + 100)) / 380)
            out.append(D(cv, x, y, rnd.uniform(0.8, 2.0), c["chalk"], (0.5 if c["dark"] else 0.6) * inside))
        return out


class Hangar(Cinema, Cached):
    """A mech in its gantry, half done. A welder works at its knee; beacons turn.
    Its visor wakes, the technician on the catwalk jumps, and it sleeps again."""

    name = "hangar"

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            bg = p("bg")
            self._c = (p, dict(
                dark=dk, top=mix(bg, BLACK3, 0.75) if dk else p("bg+fg:30"), low=mix(bg, BLACK3, 0.5) if dk else p("bg+fg:14"),
                floor=mix(bg, BLACK3, 0.6) if dk else p("bg+fg:24"), steel=mix(bg, BLACK3, 0.35) if dk else p("bg+fg:44"), steel2=mix(bg, BLACK3, 0.5) if dk else p("bg+fg:56"),
                armor=mix(mix(bg, p("fg"), 0.22), BLACK3, 0.25) if dk else p("bg+fg:36"), armor2=mix(bg, BLACK3, 0.25) if dk else p("bg+fg:50"), stripe=p("ansi_1"),
                visor=p("accent"), amber=p("ansi_3"), spark=mix(p("ansi_3"), (255.0, 255.0, 255.0), 0.5), light=p.pick("ansi_3+white:60", "white"), steam=p.pick("fg", "white"),
                person=mix(bg, BLACK3, 0.85) if dk else p("bg+fg:75"), hazard=p("ansi_3"),
            ))
        return self._c[1]

    def back(self, cv, p):
        c = self.colors(p)
        out = [vgrad(cv, 0, 0, W, 860, [(0, c["top"]), (860, c["low"])])]
        ribs = Shape()
        for k in range(9):  # the hangar's roof ribs
            x = 60 + k * 230
            ribs.line([(x, 0), (x + 40, 260)], 10)
        ribs.line([(0, 260), (W, 260)], 8)
        out.append(L(cv, ribs, c["steel2"], ss=1))
        for x in (420, 960, 1500):  # lights in the roof, their cones
            out += [L(cv, Shape().poly([(x - 30, 260), (x + 30, 260), (x + 260, 900), (x - 260, 900)]), c["light"], 0.06 if c["dark"] else 0.12, ss=1, soft=40, mode="add" if c["dark"] else "over"), glow(cv, x, 262, 30, c["light"], 0.5)]
        out.append(L(cv, Shape().rect(0, 860, W, H - 860), c["floor"], ss=1))
        hz = Shape()
        for k in range(30):
            x = k * 70
            hz.poly([(x, 880), (x + 35, 880), (x + 5, 900), (x - 30, 900)])
        out.append(L(cv, hz, c["hazard"], 0.5, ss=2))
        # the gantry round the mech: uprights, catwalks
        g = Shape()
        for x in (640, 1280):
            g.line([(x, 160), (x, 880)], 14)
        for y in (330, 560):
            g.line([(600, y), (1320, y)], 10)
            for x in range(620, 1301, 40):
                g.line([(x, y - 30), (x, y)], 2)
            g.line([(600, y - 30), (1320, y - 30)], 3)
        out.append(L(cv, g, c["steel"], ss=2))
        out += self.mech(cv, c)
        return out

    def mech(self, cv, c):
        """A mech of no one's: broad shoulders, a slit for a visor, an arm in a clamp."""
        a, a2 = c["armor"], c["armor2"]
        out = []
        legs = Shape().poly([(840, 600), (920, 600), (930, 720), (910, 880), (820, 880), (830, 720)]).poly([(1000, 600), (1080, 600), (1090, 720), (1100, 880), (1010, 880), (990, 720)])
        out.append(L(cv, legs, a2, ss=2))
        out.append(L(cv, Shape().poly([(835, 690), (925, 690), (935, 740), (825, 740)]).poly([(995, 690), (1085, 690), (1095, 740), (985, 740)]), a, ss=2))
        out.append(L(cv, Shape().poly([(860, 600), (1060, 600), (1080, 520), (840, 520)]), a2, ss=2))
        torso = Shape().poly([(800, 300), (1120, 300), (1100, 470), (1060, 540), (860, 540), (820, 470)])
        out.append(L(cv, torso, a, ss=2))
        out.append(L(cv, Shape().poly([(900, 330), (1020, 330), (1000, 450), (920, 450)]), a2, ss=2))
        out.append(L(cv, Shape().poly([(820, 470), (1100, 470), (1094, 488), (826, 488)]), c["stripe"], 0.85, ss=2))
        out.append(L(cv, Shape().poly([(720, 270), (820, 280), (830, 360), (740, 380)]).poly([(1100, 280), (1200, 270), (1180, 380), (1090, 360)]), a2, ss=2))  # shoulders
        out.append(L(cv, Shape().poly([(735, 380), (790, 375), (800, 560), (750, 580)]).poly([(1130, 375), (1185, 380), (1170, 580), (1120, 560)]), a, ss=2))  # arms
        out.append(L(cv, Shape().rect(1110, 560, 80, 30), c["steel"], ss=2))  # the clamp
        out.append(L(cv, Shape().poly([(915, 230), (1005, 230), (1015, 290), (905, 290)]), a, ss=2))  # the head
        out.append(L(cv, Shape().poly([(918, 252), (1002, 252), (998, 264), (922, 264)]), a2, ss=2))  # its visor, asleep
        lines = Shape().line([(960, 300), (960, 540)], 2).line([(860, 420), (1060, 420)], 2).line([(845, 760), (915, 760)], 2).line([(1005, 760), (1075, 760)], 2)
        out.append(L(cv, lines, a2, 0.7, ss=2))
        return out

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        wake = bump(window(t, 12.0, 15.6)) ** 0.5 if 12.0 <= t < 15.6 else 0.0
        flick = wake * (0.6 + 0.4 * (1 if int(t * 12) % 3 else 0)) if t < 12.6 else wake
        if flick > 0.02:
            out += [L(cv, Shape().poly([(918, 252), (1002, 252), (998, 264), (922, 264)]), c["visor"], flick), glow(cv, 960, 258, 60, c["visor"], 0.45 * flick)]
        for k, (bx, by) in enumerate(((640, 150), (1280, 150))):  # beacons, turning faster while it is awake
            ang = 2 * math.pi * (t / 2.0 + (1 / 0.75 - 1 / 2.0) * clamp(t - 12.0, 0.0, 3.6) + k * 0.5)
            out.append(D(cv, bx, by, 9, c["amber"]))
            sweep = Shape().poly([(bx, by), (bx + 420 * math.cos(ang), by + 160 * math.sin(ang) - 40), (bx + 420 * math.cos(ang + 0.25), by + 160 * math.sin(ang + 0.25) + 40)])
            out += [L(cv, sweep, c["amber"], 0.10 * (0.5 + 0.5 * math.cos(ang)) if c["dark"] else 0.12, ss=1, soft=14, mode="add" if c["dark"] else "over"), glow(cv, bx, by, 24, c["amber"], 0.5)]
        # the welder at the knee: a figure, a hot point, sparks falling
        wx, wy = 790.0, 760.0
        weld = Shape().circle(wx - 30, wy - 64, 11).line([(wx - 30, wy - 50), (wx - 34, wy + 10)], 18).line([(wx - 28, wy - 40), (wx - 6, wy - 30), (wx + 6, wy - 34)], 9).line([(wx - 34, wy + 10), (wx - 46, wy + 60), (wx - 40, wy + 112)], 11).line([(wx - 34, wy + 10), (wx - 18, wy + 60), (wx - 26, wy + 112)], 11)
        out.append(L(cv, weld, c["person"]))
        arc = 0.6 + 0.4 * (1 if int(t * 20) % 4 else 0)
        out += [glow(cv, wx + 10, wy - 36, 36, c["spark"], 0.6 * arc), D(cv, wx + 10, wy - 36, 3, (255.0, 255.0, 255.0))]
        rnd = random.Random(53)
        for i in range(40):
            t0 = rnd.uniform(0, 24)
            u = ((t - t0) % 24) / 1.2
            if u < 1:
                vx, vy = rnd.uniform(-120, 160), rnd.uniform(-160, -40)
                x, y = wx + 10 + vx * u, wy - 36 + vy * u + 520 * u * u
                out.append(L(cv, Shape().line([(x, y), (x - vx * 0.03, y - (vy + 1040 * u) * 0.03)], 2), c["spark"], 1 - u, mode="add" if c["dark"] else "over"))
        # the technician on the upper catwalk, with a tablet: it jumps back when the visor wakes
        jump = bump(window(t, 12.3, 13.2))
        back_off = 60 * ease_out(window(t, 12.3, 13.0)) * (1 - ease_io(window(t, 16.0, 18.0)))
        tx, ty = 1110.0 + back_off, 330.0 - 40 * jump
        tech = Shape().circle(tx, ty - 74, 10).line([(tx, ty - 62), (tx, ty - 20)], 15).line([(tx, ty - 20), (tx - 8, ty)], 9).line([(tx, ty - 20), (tx + 8, ty)], 9).line([(tx, ty - 54), (tx - 16, ty - 40)], 7)
        out += [L(cv, tech, c["person"]), L(cv, Shape().rect(tx - 26, ty - 48, 12, 8), c["visor"], 0.9), glow(cv, tx - 20, ty - 44, 14, c["visor"], 0.3)]
        # steam from a vent at its feet, more when it wakes
        rnd = random.Random(61)
        for i in range(6):
            u = ((t / 6.0) + i / 6) % 1.0
            out.append(L(cv, Shape().ellipse(1150 + 20 * u, 860 - 160 * u, 30 + 60 * u, 20 + 40 * u), c["steam"], (0.06 + 0.12 * wake) * bump(u) * (1 if c["dark"] else 2), ss=1, soft=20 + 20 * u))
        return out

    def over(self, cv, p, t):
        c = self.colors(p)
        return bubble(cv, 1160 + 60 * ease_out(window(t, 12.3, 13.0)), 220, pop(t, 12.4, 14.2), "!", p.pick("bg+fg:88", "white"), mix(p("bg"), BLACK3, 0.6), tail=-1)


class Crossing(Cinema, Cached):
    """A level crossing at dusk, wires and a lit vending machine. The bells ring,
    the arm comes down, a train goes by; after it the crows have changed places."""

    name = "crossing"
    RAIL = 800.0

    def colors(self, p):
        if not hasattr(self, "_c") or self._c[0] is not p:
            dk = p.dark
            bg = p("bg")
            self._c = (p, dict(
                dark=dk, top=mix(bg, p("ansi_5"), 0.12) if dk else p("bg+ansi_5:12"), mid=mix(bg, p("ansi_1"), 0.2) if dk else p("bg+ansi_3:22"), low=mix(p("ansi_3"), bg, 0.55) if dk else p("ansi_3+white:55"),
                sun=mix(p("ansi_3"), (255.0, 255.0, 255.0), 0.4), cloud=mix(bg, p("ansi_5"), 0.25) if dk else p("bg+ansi_5:24"),
                ink=mix(bg, BLACK3, 0.78) if dk else p("bg+fg:70"), ink2=mix(bg, BLACK3, 0.6) if dk else p("bg+fg:52"), ground=mix(bg, BLACK3, 0.5) if dk else p("bg+fg:30"),
                red=p("ansi_1"), vend=p.pick("fg+accent:20", "white"), vend2=p("accent"), train=mix(bg, BLACK3, 0.62) if dk else p("bg+fg:46"), window=p("ansi_3"),
                haze=p.pick("ansi_3", "ansi_3"),
            ))
        return self._c[1]

    def wire(self, x, k):
        return 300 + k * 26 + 70 * ((x - 960) / 1100) ** 2

    def back(self, cv, p):
        c = self.colors(p)
        out = [vgrad(cv, 0, 0, W, self.RAIL, [(0, c["top"]), (420, c["mid"]), (self.RAIL, c["low"])])]
        out += [glow(cv, 1380, 640, 220, c["sun"], 0.28 if c["dark"] else 0.4), D(cv, 1380, 640, 60, c["sun"], 0.95)]
        for y, h, x0, w in ((180, 30, 100, 900), (240, 22, 900, 800), (520, 18, 1100, 700)):
            out.append(L(cv, Shape().ellipse(x0 + w / 2, y, w / 2, h), c["cloud"], 0.85, ss=1, soft=8))
        out.append(L(cv, Shape().poly([(0, 760), (300, 720), (520, 740), (520, 680), (700, 680), (700, 740), (1100, 760), (W, 740), (W, self.RAIL), (0, self.RAIL)]), c["ink2"], ss=2))  # roofs far off
        out.append(L(cv, Shape().rect(0, self.RAIL, W, H - self.RAIL), c["ground"], ss=1))
        rails = Shape().line([(0, self.RAIL + 40), (W, self.RAIL + 40)], 5).line([(0, self.RAIL + 70), (W, self.RAIL + 70)], 5)
        for x in range(0, W, 46):
            rails.rect(x, self.RAIL + 36, 18, 40)
        out.append(L(cv, rails, c["ink"], ss=2))
        poles = Shape()
        for x in (160, 1760):
            poles.line([(x, 120), (x, self.RAIL + 20)], 14).line([(x - 60, 260), (x + 60, 260)], 8).line([(x - 40, 300), (x + 40, 300)], 6)
        out.append(L(cv, poles, c["ink"], ss=2))
        for k in range(3):
            out.append(L(cv, Shape().line([(x, self.wire(x, k)) for x in range(160, 1761, 40)], 2.2), c["ink"], ss=2))
        return out

    def front(self, cv, p):
        """The vending machine on our side of the line, in front of the train."""
        c = self.colors(p)
        out = [L(cv, Shape().rect(300, 700, 120, 210), c["ink"], ss=2), L(cv, Shape().rect(313, 716, 94, 120), c["vend"], 0.9, ss=2)]
        cans = Shape()
        for i in range(4):
            for j in range(3):
                cans.rect(320 + i * 22, 724 + j * 36, 13, 24)
        out += [L(cv, cans, c["vend2"], 0.7, ss=2), glow(cv, 360, 780, 130, c["vend"], 0.2 if c["dark"] else 0.0)]
        return out

    CROWS = (520.0, 760.0, 1000.0, 1240.0)

    def crossing_sign(self, cv, c, t, active):
        x, y = 1520.0, self.RAIL + 20
        out = [L(cv, Shape().line([(x, y), (x, y - 330)], 10), c["ink"])]
        out.append(L(cv, Shape().line([(x - 54, y - 330), (x + 54, y - 290)], 12).line([(x - 54, y - 290), (x + 54, y - 330)], 12), c["ink"]))
        out.append(L(cv, Shape().rect(x - 70, y - 252, 140, 14), c["ink"]))
        on = int(t * 2.4) % 2 if active else -1
        for k, lx in enumerate((x - 50, x + 50)):
            lit = active and on == k
            out.append(D(cv, lx, y - 228, 16, c["red"] if lit else c["ink2"]))
            if lit:
                out.append(glow(cv, lx, y - 228, 70, c["red"], 0.55))
        # the arm: up, coming down, down, going up
        down = ease_io(window(t, 8.6, 9.8)) * (1 - ease_io(window(t, 15.0, 16.2)))
        ang = -1.45 * (1 - down)
        ax, ay = x - 30, y - 120
        tip = (ax - 560 * math.cos(ang), ay + 560 * math.sin(ang))
        out.append(L(cv, Shape().line([(ax, ay), tip], 12), c["ink"]))
        for k in range(1, 7):  # its stripes
            u0, u1 = (k - 0.5) / 7, (k - 0.1) / 7
            out.append(L(cv, Shape().line([(ax + (tip[0] - ax) * u0, ay + (tip[1] - ay) * u0), (ax + (tip[0] - ax) * u1, ay + (tip[1] - ay) * u1)], 9), c["red"], 0.9))
        return out

    def under(self, cv, p, t):
        c = self.colors(p)
        out = []
        active = 8.0 <= t < 16.0
        # the train: a long blur of windows, right to left, behind the crossing's sign and arm
        u = window(t, 10.6, 14.6)
        if 0 < u < 1:
            x0 = W + 100 - (W + 3200) * u
            train = Shape().rect(x0, self.RAIL - 220, 3000, 240)
            out.append(L(cv, train, c["train"]))
            wins = Shape()
            for k in range(60):
                wins.rect(x0 + 30 + k * 50, self.RAIL - 180, 34, 60)
            out.append(L(cv, wins, c["window"], 0.75 if c["dark"] else 0.5, ss=1))
            out.append(L(cv, Shape().rect(x0, self.RAIL - 110, 3000, 8), c["ink"], 0.8))
            out.append(L(cv, Shape().rect(x0 - 200, self.RAIL - 230, 3400, 260), c["train"], 0.3, ss=1, soft=24))
        out += self.crossing_sign(cv, c, t, active)
        # the crows: in one order before the train, another after
        after = t >= 12.6 and t < 23.0
        order = (2, 0, 3, 1) if after else (0, 1, 2, 3)
        settle = ease_io(window(t, 22.0, 23.0))
        for slot, k in enumerate(order):
            x = self.CROWS[slot]
            if 22.0 <= t < 23.0:  # they shuffle back, one by one
                x0b = self.CROWS[(2, 0, 3, 1).index(k)]
                x = x0b + (self.CROWS[k] - x0b) * settle
            y = self.wire(x, 0) - 2
            bob = 3 * max(0.0, wave(t, 2.4, k * 0.31))
            kx = 1 if k % 2 else -1
            crow = Shape().poly(spline([(-20, -10), (-6, -24), (14, -22), (22, -12), (40, -6), (14, -2), (-12, -2)], per=5)).circle(-20, -22 - bob, 9).poly([(-28, -22 - bob), (-40, -18 - bob), (-28, -16 - bob)]).line([(-2, -2), (-4, 4)], 2).line([(6, -2), (6, 4)], 2)
            out.append(L(cv, crow.moved(x, y, 1.2, 0, 0, 0, kx), c["ink"]))
        rnd = random.Random(71)
        for i in range(50):  # dust in the low sun
            x0, y0 = rnd.uniform(0, W), rnd.uniform(380, 800)
            x = x0 + 40 * wave(t, 24 / rnd.choice((1, 2, 3)), rnd.random())
            y = y0 + 20 * wave(t, 24 / rnd.choice((2, 3, 4)), rnd.random())
            out.append(D(cv, x, y, rnd.uniform(0.8, 1.8), c["haze"], 0.35 * (0.5 + 0.5 * wave(t, 24 / rnd.choice((4, 6)), rnd.random()))))
        return out


SCENES_NIGHT2 = (Watch(), Problem(), Hangar(), Crossing())


# the collections: a look and feel for each persona, the scenes in it
COLLECTIONS = {
    "cozy": ("onsen", "duck", "reef", "campfire", "ufo", "pigeons"),  # warm, playful, a picture book for grown-ups
    "night": ("garoa", "horizon", "watch", "problem", "hangar", "crossing"),  # the night-shift builder: cinematic, weather and light, a dry joke
}
SCENES = {s.name: s for s in (Onsen(), Duck(), Reef(), Campfire(), Ufo(), Pigeons()) + SCENES_NIGHT + SCENES_NIGHT2}


# -- the loop ---------------------------------------------------------------------


def stills(cv, scene, p):
    img = np.empty((cv.h, cv.w, 3), np.float32)
    img[:] = scene.ground(p)
    paint(img, scene.back(cv, p))
    return img, scene.front(cv, p)


def frame(cv, scene, p, back, front, t):
    img = back.copy()
    paint(img, scene.under(cv, p, t))
    paint(img, front)
    paint(img, scene.over(cv, p, t))
    return np.clip(np.rint(scene.finish(cv, img, p)), 0, 255).astype(np.uint8)


def encode(path, w, h, frames, preset="slow"):
    """The frames as H.264 in an MP4: tuned for flat art, BT.709 like a screen."""
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (w, h), "-r", str(FPS), "-i", "-",
           "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p", "-c:v", "libx264", "-preset", preset, "-tune", "animation",
           "-crf", "21", "-g", str(FPS * 4), "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
           "-movflags", "+faststart", path]
    pr = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in frames:
        pr.stdin.write(f.tobytes())
    pr.stdin.close()
    if pr.wait():
        raise RuntimeError("ffmpeg failed on %s" % path)


def make(job):
    scene_name, path, out_dir, s, preset = job
    scene = SCENES[scene_name]
    name = os.path.basename(path)[: -len(".env")] if path.endswith(".env") else os.path.basename(path)
    p = Palette(read_env(path))
    cv = Canvas(s)
    back, front = stills(cv, scene, p)
    d = os.path.join(out_dir, scene.name)
    os.makedirs(d, exist_ok=True)
    n = scene.seconds * FPS
    encode(os.path.join(d, name + ".mp4"), cv.w, cv.h, (frame(cv, scene, p, back, front, f / FPS) for f in range(n)), preset)
    return "%s/%s" % (scene.name, name)


def main(argv):
    out_dir, paths, scenes, size, at, png, preset = HERE, [], [], (W, H), None, None, "slow"
    collection = None
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_dir = next(it)
        elif a == "--scene":
            scenes.append(next(it))
        elif a == "--size":
            size = tuple(int(v) for v in next(it).lower().split("x"))
        elif a == "--still":
            at = [float(v) for v in next(it).split(",")]
        elif a == "--png":
            png = next(it)
        elif a == "--preset":
            preset = next(it)
        elif a == "--collection":
            collection = next(it)
            if collection not in COLLECTIONS:
                sys.exit("no collection %s: %s" % (collection, " ".join(COLLECTIONS)))
            scenes += list(COLLECTIONS[collection])
        else:
            paths.append(a)
    for s in scenes:
        if s not in SCENES:
            sys.exit("no scene %s: %s" % (s, " ".join(SCENES)))
    if size[0] * H != size[1] * W:
        sys.exit("the size must be 16 by 9, as 1920x1080 is")
    s = size[0] / W
    if not paths:
        d = os.path.join(REPO, "themes")
        paths = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".env"))
    if at is not None:  # stills, to look at
        os.makedirs(png, exist_ok=True)
        cv = Canvas(s)
        for name in scenes or list(SCENES):
            scene = SCENES[name]
            for path in paths:
                p = Palette(read_env(path))
                back, front = stills(cv, scene, p)
                for t in at:
                    out = os.path.join(png, "%s-%s-%05.2f.png" % (name, os.path.basename(path)[:-4], t))
                    Image.fromarray(frame(cv, scene, p, back, front, t)).save(out)
                    print(out)
        return
    jobs = [(n, path, out_dir, s, preset) for n in (scenes or list(SCENES)) for path in paths]
    with Pool() as pool:
        try:
            for done in pool.imap_unordered(make, jobs):
                print(done)
        except RuntimeError as e:
            sys.exit(str(e))


if __name__ == "__main__":
    main(sys.argv[1:])
