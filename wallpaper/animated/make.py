#!/usr/bin/env python3
"""Animated wallpapers: small scenes, each a quiet loop with a joke in it,
drawn in a palette's own colors, in collections: a look and feel for each
persona.

    python3 wallpaper/animated/make.py --raw --scene NAME --size WxH [--fps N] [--jobs N] PALETTE.env
    python3 wallpaper/animated/make.py --info [--scene NAME [--size WxH] [--fps N]]
    python3 wallpaper/animated/make.py --scene NAME --still T|poster --size WxH --png FILE.png PALETTE.env
    python3 wallpaper/animated/make.py --scene NAME --still T[,T...] --png DIR [PALETTE.env ...]
    python3 wallpaper/animated/make.py [--collection NAME] [--scene NAME ...] [PALETTE.env ...]
                                       [--size WxH] [--out DIR] [--preset NAME]

--raw is what the desktop reads: the loop once, rgb24 frames of W*H*3 bytes on
stdout, seamless, at the scene's own rate unless --fps says another (a pixel
scene steps 12 times a second on its grid; asked for at its grid's size, as
--info names it, it comes unscaled, for the player to scale with square
pixels). --jobs draws frames in that many processes, in order all the same.
It exits 0 once the whole loop is written; anything it cannot do (a scene it
does not know, a palette it cannot read, a size it cannot draw, a reader that
goes away) is one line on stderr and a nonzero exit, and nothing else is ever
written there. --info is one line of JSON: a scene's rate, length, frames,
still time and grid, or with no --scene every scene and its collection. A
still (poster: the scene's own moment) is a PNG, the picture to show before
its loop is made. Only numpy is needed for these; the MP4s of the last form,
for a gallery, are encoded by ffmpeg. A landscape size that is not 16 by 9
gets the scene's picture covering it, centered; a portrait one gets the
scene's own portrait composition (a pixel scene's on a 270 by 480 grid), and
is refused for a scene that does not have one yet.

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

night: the night shift, by another hand: pixel art, 480 by 270 shown as
squares, twelve frames a second, the palette's colors and a dither between
them; the references and not the story, no one in them, a dry joke

    garoa     Sao Paulo in the drizzle at night, the Copan and the masts of
              Paulista; a helicopter finds its roof taken and takes the next
    horizon   a black hole over the edge of an ice planet, its disc turning;
              a probe falls in and, as seen from here, never quite does
    watch     the sea at night, the moon's road on it, a lighthouse sweeping
              the water; once a loop it stops and looks up at the moon
    problem   a training board, a grid of holds in every color, a light by
              each; it shows a problem, then another, then runs Life, and a
              glider walks down it
    continue  an arcade after closing, six machines playing to no one; one
              asks the empty room to continue, counts down, and gives up
    crossing  a level crossing at dusk, far off: the bells, the arm, a small
              train; after it the crows on the wire are in another order

Each scene is a loop of 24 seconds at 24 frames a second, 1920 by 1080 by
default (a pixel scene's 480 by 270 four times over), H.264 in an MP4 that
ends where it begins: DIR/SCENE/NAME.mp4 for each palette (by default every
themes/*.env). The colors are the palette's, by the roles the shipped
wallpapers use (bg, fg, accent, muted, ansi_N, and A+B:PCT, the first moved
PCT of the way to the second): a dark palette's scene is at night and a
light one's by day. Most of the picture is still; what moves is small and
slow, so it can sit behind the terminals.
"""

import json
import math
import os
import random
import struct
import subprocess
import sys
import warnings
import zlib
from multiprocessing import Pool

import numpy as np

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
    """The pixels a scene is drawn on: uw by uh of its units at s pixels a unit,
    the drawing moved by (ox, oy) units. A landscape canvas is the drawing as it
    is; a portrait one is the scene's own view of it, with things placed for it."""

    def __init__(self, s, uw=W, uh=H, ox=0.0, oy=0.0):
        self.s, self.uw, self.uh, self.ox, self.oy = s, uw, uh, ox, oy
        self.w, self.h = round(uw * s), round(uh * s)
        self.portrait = uh > uw
        self.key = (self.w, self.h, ox, oy)

    def box(self, x0, y0, x1, y1):
        """A box in units as pixel rows and columns on the canvas, or None off it."""
        px0, px1 = max(0, math.floor((x0 + self.ox) * self.s) - 1), min(self.w, math.ceil((x1 + self.ox) * self.s) + 1)
        py0, py1 = max(0, math.floor((y0 + self.oy) * self.s) - 1), min(self.h, math.ceil((y1 + self.oy) * self.s) + 1)
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


def scan(polys, w, h):
    """Polygons filled into a mask h by w: a sample is in when its center is.
    Each polygon is turned the same way first, so overlapping ones make a union."""
    D = np.zeros((h, w + 2), np.int32)
    for pts in polys:
        P = np.asarray(pts, np.float64)
        if len(P) < 3:
            continue
        x, y = P[:, 0], P[:, 1]
        if np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y) < 0:
            x, y = x[::-1], y[::-1]
        x1, y1 = np.roll(x, -1), np.roll(y, -1)
        r0 = np.clip(np.ceil(np.minimum(y, y1) - 0.5), 0, h).astype(np.int64)  # the rows whose centers each edge crosses
        r1 = np.clip(np.ceil(np.maximum(y, y1) - 0.5), 0, h).astype(np.int64)
        n = np.maximum(r1 - r0, 0)
        tot = int(n.sum())
        if not tot:
            continue
        e = np.repeat(np.arange(len(x)), n)
        r = r0[e] + np.arange(tot) - np.repeat(np.cumsum(n) - n, n)
        xi = x[e] + (r + 0.5 - y[e]) * (x1[e] - x[e]) / (y1[e] - y[e])
        col = np.clip(np.floor(xi - 0.5).astype(np.int64) + 1, 0, w + 1)
        np.add.at(D, (r, col), np.where(y1[e] > y[e], 1, -1))
    return np.cumsum(D, axis=1)[:, :w] != 0


def strokes(m, pts, r, strict=False):
    """A round stroke of radius r along points into the mask m: round ends and joins."""
    h, w = m.shape
    segs = list(zip(pts, pts[1:])) or [(pts[0], pts[0])]
    for (ax, ay), (bx, by) in segs:
        x0, x1 = max(0, int(math.floor(min(ax, bx) - r))), min(w, int(math.ceil(max(ax, bx) + r)) + 1)
        y0, y1 = max(0, int(math.floor(min(ay, by) - r))), min(h, int(math.ceil(max(ay, by) + r)) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        X = np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5 - ax
        Y = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5 - ay
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy
        t = np.clip((X * dx + Y * dy) / ll, 0, 1) if ll > 0 else 0.0
        d2 = (X - t * dx) ** 2 + (Y - t * dy) ** 2
        m[y0:y1, x0:x1] |= (d2 < r * r) if strict else (d2 <= r * r)


def box_blur(a, r, axis):
    """A running mean 2r+1 wide along an axis, the edges taken as empty."""
    if r <= 0:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad), axis=axis, dtype=np.float64)
    hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
    lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, sigma):
    """A Gaussian blur of sigma pixels, as three running means (close enough to the eye)."""
    if sigma < 0.3:
        return a
    wl = int(math.sqrt(4 * sigma * sigma + 1))
    wl -= 1 - wl % 2
    m = round((12 * sigma * sigma - 3 * wl * wl - 12 * wl - 9) / (-4 * wl - 4))
    for i in range(3):
        r = ((wl if i < m else wl + 2) - 1) // 2
        a = box_blur(box_blur(a, r, 0), r, 1)
    return a


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
    k = cv.s * ss
    tr = lambda p: (((p[0] + cv.ox) * cv.s - px0) * ss, ((p[1] + cv.oy) * cv.s - py0) * ss)
    m = scan([[tr(p) for p in cmd[1]] for cmd in shape.cmds if cmd[0] == "poly" and len(cmd[1]) >= 3], w * ss, h * ss)
    for cmd in shape.cmds:
        if cmd[0] == "line" and cmd[1]:
            strokes(m, [tr(p) for p in cmd[1]], round(max(1.0, cmd[2] * k)) / 2, strict=True)  # a whole number of samples wide
    cov = m.reshape(h, ss, w, ss).mean(axis=(1, 3), dtype=np.float32)
    if soft:
        cov = blur(cov, soft * cv.s)
    if clip is not None:
        cov = cov * clip[py0:py1, px0:px1]
    rows = (np.arange(py0, py1, dtype=np.float32) + 0.5)[:, None]
    if above is not None:
        cov = cov * np.clip((above + cv.oy) * cv.s - rows + 0.5, 0, 1)
    if below is not None:
        cov = cov * np.clip(rows - (below + cv.oy) * cv.s + 0.5, 0, 1)
    return cov, slice(py0, py1), slice(px0, px1)


def dot(cv, cx, cy, r):
    """A disc's coverage, worked out exactly: the quick way for the many small round things."""
    b = cv.box(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
    if b is None or r <= 0:
        return None
    px0, py0, px1, py1 = b
    xs = (np.arange(px0, px1, dtype=np.float32) + 0.5)[None, :] / cv.s - cv.ox
    ys = (np.arange(py0, py1, dtype=np.float32) + 0.5)[:, None] / cv.s - cv.oy
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
    ys = (np.arange(py0, py1, dtype=np.float32) + 0.5) / cv.s - cv.oy
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
    name, seconds, poster = "", 24, 6.0
    portrait = None  # its view for a portrait screen: (width, height, x, y) in units, or None for none yet

    def view(self, portrait):
        """The units a canvas shows: the drawing as it is, or the portrait view."""
        return self.portrait if portrait else (W, H, 0.0, 0.0)

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


class Onsen(Scene):
    name = "onsen"
    poster = 4.0  # the still: the list's picture, and what shows before the loop is made
    portrait = (1080.0, 1920.0, -580.0, 840.0)  # the pool at the foot, a tall sky over it
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
        mx, my = (1360.0, -330.0) if cv.portrait else (1490.0, 250.0)
        out += [D(cv, mx, my, 165, c["halo2"]), D(cv, mx, my, 112, c["halo1"]), D(cv, mx, my, 62, c["moon"])]
        rnd = random.Random(4)
        flakes = [(rnd.uniform(0, W), rnd.uniform(40, 420)) for _ in range(46)]
        if cv.portrait:  # the tall sky has its own
            flakes = [(rnd.uniform(560, 1680), rnd.uniform(-820, 420)) for _ in range(80)]
        for x, y in flakes:
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
        out += self.lantern(cv, c, *((1500.0, 712.0) if cv.portrait else (560.0, 812.0)))  # in a portrait, behind the pool
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
        if getattr(self, "_pool", (None,))[0] != cv.key:
            self._pool = (cv.key, full(cv, Shape().ellipse(self.PX, self.PY, self.PRX, self.PRY)))
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
        if (key, cv.key) not in store:
            store[(key, cv.key)] = make()
        return store[(key, cv.key)]


class Duck(Scene, Cached):
    name = "duck"
    poster = 9.0
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
    poster = 4.5

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
    poster = 3.0
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
    poster = 8.0
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
    poster = 1.5
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


# -- night: a pixel artist's ------------------------------------------------------
#
# The night collection is drawn by another hand: a canvas of 480 by 270, twelve
# frames a second, colors from the palette and nothing else, the steps between
# them an ordered dither, each pixel shown as a square.

PW, PH, PFPS = 480, 270, 12
GRID = [PW, PH]  # the grid being drawn on: 480 by 270, or 270 by 480 for a portrait
WHITE3 = (255.0, 255.0, 255.0)
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16
DITHERS = {}


def dither(h, w):
    """The ordered dither's thresholds over a canvas h by w, fixed to its pixels."""
    if (h, w) not in DITHERS:
        DITHERS[(h, w)] = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    return DITHERS[(h, w)]


def C(col):
    return np.asarray(col, np.float32)


class Mask:
    """Shapes with hard edges, as a pixel artist draws them: a pixel is in or out.
    Whole numbers name pixels, as on a grid of them; a polygon keeps its edge."""

    def __init__(self, w=None, h=None):
        self.mm = np.zeros((h or GRID[1], w or GRID[0]), bool)

    def poly(self, pts):
        q = [(round(x) + 0.5, round(y) + 0.5) for x, y in pts]
        self.mm |= scan([q], self.mm.shape[1], self.mm.shape[0])
        strokes(self.mm, q + q[:1], 0.5)
        return self

    def rect(self, x, y, w, h):
        x0, y0, x1, y1 = round(x), round(y), round(x + w) - 1, round(y + h) - 1
        if x1 >= x0 and y1 >= y0:
            self.mm[max(0, y0) : max(0, y1 + 1), max(0, x0) : max(0, x1 + 1)] = True
        return self

    def _in(self, x0, y0, x1, y1, shrink=0.0):
        """The pixels inside the ellipse that fits pixels x0..x1 by y0..y1."""
        cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
        rx, ry = (x1 - x0 + 1) / 2 - shrink, (y1 - y0 + 1) / 2 - shrink
        if rx <= 0 or ry <= 0:
            return np.zeros_like(self.mm)
        X = (np.arange(self.mm.shape[1], dtype=np.float32)[None, :] + 0.5 - cx) / rx
        Y = (np.arange(self.mm.shape[0], dtype=np.float32)[:, None] + 0.5 - cy) / ry
        return X * X + Y * Y <= 1.0

    def ell(self, cx, cy, rx, ry):
        self.mm |= self._in(round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry))
        return self

    def ring(self, cx, cy, rx, ry, w=1):
        box_ = (round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry))
        self.mm |= self._in(*box_) & ~self._in(*box_, shrink=w)
        return self

    def line(self, pts, w=1):
        strokes(self.mm, [(round(x) + 0.5, round(y) + 0.5) for x, y in pts], w / 2)
        return self

    def px(self, x, y):
        x, y = round(x), round(y)
        if 0 <= y < self.mm.shape[0] and 0 <= x < self.mm.shape[1]:
            self.mm[y, x] = True
        return self

    def m(self):
        return self.mm


def fill(a, mask, col, alpha=1.0):
    m = mask.m() if isinstance(mask, Mask) else mask
    if alpha >= 1.0:
        a[m] = C(col)
    else:
        a[m] += (C(col) - a[m]) * alpha


def put(a, x, y, col, alpha=1.0):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < a.shape[1] and 0 <= y < a.shape[0]:
        a[y, x] += (C(col) - a[y, x]) * alpha


def hline(a, x0, x1, y, col, alpha=1.0):
    y = int(round(y))
    x0, x1 = max(0, int(round(x0))), min(a.shape[1], int(round(x1)))
    if 0 <= y < a.shape[0] and x1 > x0:
        a[y, x0:x1] += (C(col) - a[y, x0:x1]) * alpha


def vline(a, x, y0, y1, col, alpha=1.0):
    x = int(round(x))
    y0, y1 = max(0, int(round(y0))), min(a.shape[0], int(round(y1)))
    if 0 <= x < a.shape[1] and y1 > y0:
        a[y0:y1, x] += (C(col) - a[y0:y1, x]) * alpha


def box(a, x, y, w, h, col, alpha=1.0):
    x0, y0 = max(0, int(round(x))), max(0, int(round(y)))
    x1, y1 = min(a.shape[1], int(round(x + w))), min(a.shape[0], int(round(y + h)))
    if x1 > x0 and y1 > y0:
        a[y0:y1, x0:x1] += (C(col) - a[y0:y1, x0:x1]) * alpha


def pglow(a, x, y, r, col, k, add=True):
    """Light round a point; the dither turns it into the rings a pixel artist draws."""
    x0, x1 = max(0, int(x - r - 1)), min(a.shape[1], int(x + r + 2))
    y0, y1 = max(0, int(y - r - 1)), min(a.shape[0], int(y + r + 2))
    if x1 <= x0 or y1 <= y0:
        return
    xs = np.arange(x0, x1, dtype=np.float32)[None, :] - x
    ys = np.arange(y0, y1, dtype=np.float32)[:, None] - y
    f = (np.clip(1 - np.sqrt(xs * xs + ys * ys) / r, 0, 1) ** 2 * k)[..., None]
    sub = a[y0:y1, x0:x1]
    if add:
        sub += C(col) * f
    else:
        sub += (C(col) - sub) * f


def pgrad(a, y0, y1, stops, x0=0, x1=None):
    """A sky: colors at heights, in between them a straight blend for the dither to step."""
    h = a.shape[0]
    ys = np.arange(h, dtype=np.float32)
    col = np.zeros((h, 3), np.float32)
    hs = [s[0] for s in stops]
    for ch in range(3):
        col[:, ch] = np.interp(ys, hs, [s[1][ch] for s in stops])
    y0, y1 = max(0, int(y0)), min(h, int(y1))
    a[y0:y1, x0:x1] = col[y0:y1, None, :]


def sprite(a, x, y, rows, cmap, kx=1, alpha=1.0):
    """Pixel art by hand: one character a pixel, '.' for none; kx=-1 mirrors it."""
    w = max(len(r) for r in rows)
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == "." or ch == " " or ch not in cmap:
                continue
            xi = x + (i if kx > 0 else w - 1 - i)
            put(a, xi, y + j, cmap[ch], alpha)


FONT = {  # three by five, for the few words a picture needs
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110", "E": "111100110100111",
    "F": "111100110100100", "G": "011100101101011", "H": "101101111101101", "I": "111010010010111", "K": "101101110101101",
    "L": "100100100100111", "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "R": "110101110101101", "S": "011100010001110", "T": "111010010010010", "U": "101101101101111", "V": "101101101101010",
    "W": "101101111111101", "Y": "101101010010010", "Z": "111001010100111", "X": "101101010101101", "Q": "010101101110011", "J": "001001001101010", "?": "110001010000010", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110", "6": "011100111101111",
    "7": "111001010010010", "8": "111101111101111", "9": "111101111001110", " ": "000000000000000", ".": "000000000000010",
    "-": "000000111000000", ":": "000010000010000", "/": "001001010100100", "!": "010010010000010",
}


def text(a, x, y, s, col, alpha=1.0, scale=1):
    for k, ch in enumerate(s.upper()):
        bits = FONT.get(ch, FONT[" "])
        for i, b in enumerate(bits):
            if b == "1":
                bx, by = x + k * 4 * scale + (i % 3) * scale, y + (i // 3) * scale
                if scale == 1:
                    put(a, bx, by, col, alpha)
                else:
                    box(a, bx, by, scale, scale, col, alpha)


def quant_px(a, P, th):
    """Pixels (n by 3) to the nearest of the palette's colors, or, between two, an
    ordered dither of them by their thresholds th: flat color stays flat, a blend
    becomes a pattern."""
    a64, P64 = a.astype(np.float64), P.astype(np.float64)
    d = (a64 * a64).sum(1)[:, None] - 2.0 * (a64 @ P64.T) + (P64 * P64).sum(1)[None, :]  # the squared distances, as a product
    i1 = d.argmin(-1)
    np.put_along_axis(d, i1[:, None], np.inf, -1)
    i2 = d.argmin(-1)
    c1, c2 = P[i1], P[i2]
    v = c2 - c1
    t = ((a - c1) * v).sum(-1) / np.maximum((v * v).sum(-1), 1e-6)
    return np.where((t > th)[:, None], c2, c1)


def quant(a, pal):
    h, w = a.shape[:2]
    return quant_px(a.reshape(-1, 3), pal, dither(h, w).reshape(-1)).reshape(h, w, 3)


def hull(pts):
    """The convex hull of points, to fill: a cone of light from a lamp to a patch."""
    pts = sorted(set((round(x, 2), round(y, 2)) for x, y in pts))
    if len(pts) < 3:
        return pts

    def half(seq):
        out = []
        for q in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (q[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (q[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(q)
        return out[:-1]

    return half(pts) + half(pts[::-1])


def ramp(a, b, n):
    return [mix(a, b, k / (n - 1)) for k in range(n)]


class Pixel:
    name, seconds, pixel, poster = "", 24, True, 6.0
    portrait = False  # True once it has a portrait composition on a 270 by 480 grid
    gw, gh = PW, PH

    def orient(self, portrait):
        """Draw on the landscape grid or the portrait one; a scene places its things in layout."""
        self.gw, self.gh = (PH, PW) if portrait else (PW, PH)
        GRID[:] = [self.gw, self.gh]
        self.layout(portrait)

    def layout(self, portrait):
        pass

    def key(self, p):
        return (self.gw > self.gh,) + tuple(sorted(p.hex.items()))

    def colors(self, p):
        raise NotImplementedError

    def extra(self, p, c):  # the steps in between that the dither may use
        return []

    def palette(self, p):
        st = self.__dict__.setdefault("_pal", {})
        k = self.key(p)
        if k not in st:
            c = self.colors(p)
            cols = [v for v in c.values() if isinstance(v, tuple)] + self.extra(p, c)
            seen, out = set(), []
            for col in cols:
                q = tuple(round(v, 3) for v in col)
                if q not in seen:
                    seen.add(q)
                    out.append(col)
            st[k] = np.asarray(out, np.float32)
        return st[k]

    def base(self, p):
        st = self.__dict__.setdefault("_base", {})
        k = self.key(p)
        if k not in st:
            a = np.zeros((self.gh, self.gw, 3), np.float32)
            self.back(a, p, self.colors(p))
            st[k] = a
        return st[k]

    def back(self, a, p, c):
        pass

    def draw(self, a, p, c, t):
        pass

    def render(self, p, t, portrait=False):
        """A frame: the still part's dither is worked out once, and each frame's
        only where it differs from it; the same pixels as dithering it all."""
        self.orient(portrait)
        t = t % self.seconds
        base = self.base(p)
        a = base.copy()
        self.draw(a, p, self.colors(p), t)
        st = self.__dict__.setdefault("_qbase", {})
        k = self.key(p)
        if k not in st:
            st[k] = quant(base, self.palette(p))
        out = st[k].copy()
        ys, xs = np.nonzero(np.any(a != base, axis=-1))
        if len(ys):
            out[ys, xs] = quant_px(a[ys, xs], self.palette(p), dither(*a.shape[:2])[ys, xs])
        return out


def clouds(a, seed, n, band, body, lit, alpha, lit_below=True, wmin=50, wmax=130, big=False, tail=False):
    """Long clouds of a few puffs each; their edge toward the light picked out."""
    rnd = random.Random(seed)
    for k in range(n):
        cx, cy, w = rnd.randint(-20, a.shape[1] + 20), rnd.randint(*band), rnd.randint(wmin, wmax)
        m = Mask()
        for j in range(rnd.randint(4, 7)):
            px_ = cx - w / 2 + w * rnd.random()
            ry = rnd.randint(5, 11) if big else rnd.randint(3, 7)
            m.ell(px_, cy - ry * 0.4 * rnd.random(), rnd.randint(14, 32) if big else rnd.randint(10, 24), ry)
        if tail:
            m.rect(cx - w / 2 - 6, cy, w + 12, 3)
        mm = m.m()
        fill(a, mm, body, alpha)
        sh = np.zeros_like(mm)
        d = 3 if big else 2
        if lit_below:
            sh[:-d] = mm[d:]
        else:
            sh[d:] = mm[:-d]
        fill(a, mm & ~sh, lit, min(1.0, alpha * 1.1))


def roof(a, x, y, w, rnd, col, edge):
    """What is on a Sao Paulo roof: a water tank, an antenna, a box of a machine."""
    k = rnd.random()
    if k < 0.45 and w > 14:
        tx = x + 3 + rnd.randrange(max(1, w - 10))
        box(a, tx, y - 4, 6, 3, col)
        hline(a, tx, tx + 6, y - 4, edge)
        put(a, tx + 1, y - 1, col)
        put(a, tx + 4, y - 1, col)
    if rnd.random() < 0.5:
        ax = x + 2 + rnd.randrange(max(1, w - 4))
        vline(a, ax, y - rnd.randint(4, 9), y, col)
    if rnd.random() < 0.4:
        bx = x + 2 + rnd.randrange(max(1, w - 6))
        box(a, bx, y - 2, 4, 2, edge)


# -- garoa ------------------------------------------------------------------------

HELI = (
    "..........k......",
    "k......kkkkkk....",
    "kk....kkkkkkkgg..",
    "kkkkkkkkkkkkkkggk",
    ".......kkkkkkkkk.",
    "........s....s...",
    ".......sssssssss.",
)


class Garoa(Pixel):
    """Sao Paulo in the drizzle at night: the Copan's wave, the masts of Paulista
    with their red lights, helicopters going from roof to roof."""

    name = "garoa"
    poster = 8.0
    HZ = 225
    PADS = ((274, 154), (425, 146))
    MASTS = ((332, 67), (367, 57), (397, 75))

    def colors(self, p):
        st = self.__dict__.setdefault("_c", {})
        k = self.key(p)
        if k in st:
            return st[k]
        bg, dk = p("bg"), p.dark
        glow_c = mix(p("ansi_1"), p("ansi_3"), 0.45)
        if dk:
            c = dict(top=mix(bg, BLACK3, 0.5), low=mix(bg, glow_c, 0.26), cloud=mix(mix(bg, BLACK3, 0.3), glow_c, 0.1), cloudlit=mix(bg, glow_c, 0.3),
                     far=mix(mix(bg, glow_c, 0.12), BLACK3, 0.3), fog=mix(bg, glow_c, 0.2), mast=mix(bg, BLACK3, 0.5),
                     copan=mix(bg, BLACK3, 0.32), copanline=mix(bg, BLACK3, 0.58), mid=mix(bg, BLACK3, 0.46), midedge=mix(bg, BLACK3, 0.36),
                     near=mix(bg, BLACK3, 0.7), street=mix(bg, BLACK3, 0.62), wet=mix(bg, BLACK3, 0.5),
                     glass=mix(mix(bg, BLACK3, 0.46), p("fg"), 0.08), warm=p("ansi_3"), warmdim=mix(p("ansi_3"), mix(bg, BLACK3, 0.46), 0.45),
                     cool=p("accent"), red=p("ansi_1"), white=p("fg"), rain=mix(bg, p("fg"), 0.42), heli=mix(bg, BLACK3, 0.78),
                     heliglass=mix(p("accent"), BLACK3, 0.35), pad=mix(mix(bg, BLACK3, 0.46), p("fg"), 0.3))
        else:
            c = dict(top=p("bg+fg:22"), low=p("bg+white:35"), cloud=p("bg+fg:30"), cloudlit=p("bg+white:55"),
                     far=p("bg+fg:24"), fog=p("bg+white:50"), mast=p("bg+fg:48"),
                     copan=p("bg+fg:30"), copanline=p("bg+fg:46"), mid=p("bg+fg:40"), midedge=p("bg+fg:32"),
                     near=p("bg+fg:58"), street=p("bg+fg:50"), wet=p("bg+fg:36"),
                     glass=p("bg+fg:26"), warm=p("ansi_3"), warmdim=mix(p("ansi_3"), p("bg+fg:40"), 0.5),
                     cool=p("bg+white:60"), red=p("ansi_1"), white=p("white"), rain=p("bg+fg:52"), heli=p("bg+fg:72"),
                     heliglass=p("bg+fg:40"), pad=p("bg+fg:20"))
        st[k] = c
        return c

    def extra(self, p, c):
        return (ramp(c["top"], c["low"], 6) + ramp(c["red"], c["top"], 4)[1:3] + ramp(c["warm"], c["street"], 4)[1:3]
                + [mix(c["fog"], c["far"], 0.5), mix(c["white"], c["street"], 0.5), mix(c["red"], c["street"], 0.5)])

    def towers(self):
        if hasattr(self, "_towers"):
            return self._towers
        rnd = random.Random(41)
        far, mid = [], []
        x = -5
        while x < PW:
            w = rnd.randint(10, 27)
            far.append((x, rnd.randint(140, 175), w))
            x += w + rnd.randint(-2, 1)
        x = 215
        while x < PW + 10:
            w = rnd.randint(22, 42)
            mid.append((x, rnd.randint(140, 180), w))
            x += w + rnd.randint(2, 7)
        near = [(-10, 130, 58), (452, 117, 50), (47, 190, 30)]
        self._towers = far, mid, near
        return self._towers

    def facade(self, a, c, x, y, w, rnd, lit=0.34, step=(4, 5), size=(2, 2), dk=True):
        for wx in range(int(x) + 3, int(x + w) - 3, step[0]):
            for wy in range(int(y) + 4, self.HZ - 3, step[1]):
                r = rnd.random()
                if r < lit:
                    col = c["warm"] if rnd.random() < 0.72 else c["cool"]
                    if rnd.random() < 0.3:
                        col = c["warmdim"]
                    box(a, wx, wy, size[0], size[1], col if dk or rnd.random() < 0.3 else c["glass"])
                elif r < lit + 0.3:
                    box(a, wx, wy, size[0], size[1], c["glass"])

    def back(self, a, p, c):
        dk = p.dark
        pgrad(a, 0, self.HZ, [(0, c["top"]), (120, mix(c["top"], c["low"], 0.55)), (self.HZ, c["low"])])
        # low cloud, lit from below by the city
        clouds(a, 3, 7, (4, 80), c["cloud"], c["cloudlit"], 0.75, lit_below=True, wmin=70, wmax=170, big=True, tail=True)
        far, mid, near = self.towers()
        m = Mask()
        for x, y, w in far:
            m.rect(x, y, w, self.HZ - y)
            if w > 20:
                m.rect(x + w // 2, y - 10, 1, 10)
        fill(a, m, c["far"])
        frnd = random.Random(12)
        for x, y, w in far:
            for k in range(w // 6):
                if frnd.random() < 0.35:
                    put(a, x + 2 + frnd.randrange(max(1, w - 4)), y + 3 + frnd.randrange(max(1, 150 - y)), c["warmdim"] if dk else c["glass"], 0.6)
        box(a, 0, 152, PW, 30, c["fog"], 0.3)
        # the masts of Paulista: lattices
        for mx, top in self.MASTS:
            m = Mask().line([(mx - 3, 160), (mx, top)]).line([(mx + 3, 160), (mx, top)])
            for k in range(1, 12):
                y0 = top + (160 - top) * (k - 1) / 11
                y1 = top + (160 - top) * k / 11
                h0, h1 = 3 * (y0 - top) / (160 - top), 3 * (y1 - top) / (160 - top)
                m.line([(mx - h0, y0), (mx + h1, y1)])
            m.rect(mx - 2, top + 18, 5, 1).rect(mx - 3, top + 52, 7, 1)
            fill(a, m, c["mast"])
        # the Copan: a long wave of a building in lines of sunshade
        cp = spline([(75, 118), (105, 114), (140, 118), (175, 113), (215, 117), (225, 118)], closed=False, per=12)
        fill(a, Mask().poly(cp + [(225, self.HZ), (75, self.HZ)]), c["copan"])
        rnd = random.Random(8)
        for y in range(122, self.HZ, 3):
            hline(a, 75, 226, y, c["copanline"])
            for x in range(76, 225):
                if rnd.random() < 0.035:
                    put(a, x, y + 1, c["warm"] if dk else c["glass"], 1.0 if dk else 0.8)
        for x in (75, 225):
            vline(a, x, 113, self.HZ, c["copanline"])
        # the middle row, two roofs with a helipad
        rnd = random.Random(19)
        for x, y, w in mid:
            box(a, x, y, w, self.HZ - y, c["mid"])
            vline(a, x, y, self.HZ, c["midedge"])
            hline(a, x, x + w, y, c["midedge"])
            self.facade(a, c, x, y, w, rnd, dk=dk)
            roof(a, x, y, w, rnd, c["mid"], c["midedge"])
        for px_, py in self.PADS:
            box(a, px_ - 17, py, 35, self.HZ - py, c["mid"])
            hline(a, px_ - 17, px_ + 18, py, c["midedge"])
            self.facade(a, c, px_ - 17, py + 3, 35, rnd, dk=dk)
            fill(a, Mask().ring(px_, py - 2, 9, 2), c["pad"])
            for dx, dy in ((-2, -3), (-2, -2), (-2, -1), (2, -3), (2, -2), (2, -1), (-1, -2), (0, -2), (1, -2)):
                put(a, px_ + dx, py + dy, c["pad"])
        # the near buildings, and the wet street with every light again in it
        for x, y, w in near:
            box(a, x, y, w, self.HZ - y, c["near"])
            self.facade(a, c, x, y, w, rnd, lit=0.16, step=(5, 7), size=(3, 3), dk=dk)
        box(a, 0, self.HZ, PW, PH - self.HZ, c["street"])
        hline(a, 0, PW, self.HZ, c["wet"])
        rnd = random.Random(4)
        src = a[150 : self.HZ - 2].copy()
        for y in range(self.HZ + 1, PH):
            d = y - self.HZ
            sy = self.HZ - 3 - int(d * 1.6)
            if sy < 150 or rnd.random() < 0.25:
                continue
            row = src[sy - 150]
            bright = row.sum(-1) > C(c["street"]).sum() + 160
            if bright.any():
                xs = np.nonzero(bright)[0]
                k = 0.5 * (1 - d / (PH - self.HZ)) ** 1.2
                a[y, xs] += (row[xs] - a[y, xs]) * k
        for y in range(self.HZ + 6, PH, 9):  # lanes
            for x in range(0, PW, 16):
                hline(a, x, x + 6, y + 8, c["wet"]) if y == self.HZ + 15 else None

    def heli(self, a, c, x, y, t, kx=1, parked=False):
        cmap = {"k": c["heli"], "s": c["heli"], "g": c["heliglass"]}
        x, y = int(round(x)), int(round(y))
        sprite(a, x - 8, y - 3, HELI, cmap, kx)
        cx = x - 8 + (10 if kx > 0 else 6)
        if parked:
            hline(a, cx - 7, cx + 8, y - 4, c["heli"])
        else:
            n = int(t * PFPS) % 3
            half = (9, 3, 6)[n]
            hline(a, cx - half, cx + half + 1, y - 4, c["heli"])
        on = int(t * 1.5) % 2 == 0
        tx = x - 8 + (0 if kx > 0 else 16)
        put(a, tx, y - 2, c["red"], 1.0 if on else 0.3)
        if on:
            pglow(a, tx, y - 2, 5, c["red"], 0.35)
        if not parked and (t * 1.25) % 1.0 < 0.1:
            put(a, x, y + 2, c["white"])
            pglow(a, x, y + 2, 7, c["white"], 0.4)

    def draw(self, a, p, c, t):
        dk = p.dark
        box(a, 0, 158 + 2 * wave(t, 24), PW, 18, c["fog"], 0.18)
        for k, (mx, top) in enumerate(self.MASTS):
            on = ((t + k * 0.7) % 2.0) < 1.0
            for yy in (top, top + int((160 - top) * 0.45)):
                put(a, mx, yy, c["red"], 1.0 if on else 0.35)
                if on:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        put(a, mx + dx, yy + dy, c["red"], 0.5)
                    pglow(a, mx, yy, 7, c["red"], 0.3)
        x, y = self.PADS[0]
        self.heli(a, c, x - 1, y - 5, t, 1, parked=True)
        if 2.0 <= t < 17.5:  # the late one: its roof is taken, it goes round and takes the next
            if t < 6.5:
                u = ease_io(window(t, 2.0, 6.5))
                hx, hy = -20 + (x + 8 + 20) * u, 75 + (y - 30 - 75) * u
            elif t < 9.5:
                hx, hy = x + 8 + 4 * math.sin((t - 6.5) * 2.2), y - 30 + 2 * math.sin((t - 6.5) * 3)
            else:
                px2, py2 = self.PADS[1]
                u = ease_io(window(t, 9.5, 17.0))
                hx = x + 8 + (px2 - x - 8) * u
                hy = (y - 30) + ((py2 - 5) - (y - 30)) * u - 30 * math.sin(math.pi * u)
            if t < 17.0:
                self.heli(a, c, hx, hy, t, -1 if t >= 9.5 else 1)
        px2, py2 = self.PADS[1]
        if 17.0 <= t < 20.0:
            self.heli(a, c, px2, py2 - 5, t, -1, parked=18.5 <= t < 19.5)
        elif t >= 20.0:
            u = ease_in(window(t, 20.0, 23.6))
            if u < 1:
                self.heli(a, c, px2 + 100 * u, py2 - 5 - 75 * u, t, -1)
        # cars: lights going by, and their light in the wet street
        for k in range(4):
            u = ((t / 6.0) + k / 4) % 1.0
            right = k % 2 == 0
            xx = -12 + (PW + 24) * u if right else PW + 12 - (PW + 24) * u
            yy = self.HZ + 9 + k * 5
            col = c["white"] if right else c["red"]
            box(a, xx - 4, yy - 2, 9, 3, c["near"])
            fx = xx + 4 if right else xx - 4
            put(a, fx, yy - 1, col)
            put(a, fx, yy, col)
            pglow(a, fx, yy, 6, col, 0.25)
            for d in range(2, 14, 2):
                put(a, fx, yy + d, col, 0.45 * (1 - d / 14))
        # the drizzle: thin, slanted, quick, and its splashes
        rnd = random.Random(23)
        speed = 12 * (PH + 20) / self.seconds
        for i in range(150):
            x0, y0, ln = rnd.uniform(-60, PW), rnd.uniform(0, PH + 20), rnd.choice((3, 3, 4, 5))
            yy = (y0 + speed * t) % (PH + 20) - 10
            xx = x0 + 0.3 * yy
            for j in range(ln):
                put(a, xx + 0.3 * j, yy + j, c["rain"], 0.9 if i % 4 else 1.0)
        frnd = random.Random(int(round(t * PFPS)) % (self.seconds * PFPS) * 7 + 1)
        for i in range(14):
            put(a, frnd.randint(0, PW - 1), frnd.randint(self.HZ + 2, PH - 1), c["rain"])



# -- horizon ------------------------------------------------------------------------


class Horizon(Pixel):
    """A black hole over the edge of an ice planet: its disc turns, its light
    bends over the top. A probe falls in, and as seen from here never quite does."""

    name = "horizon"
    poster = 12.0
    CX, CY, RS = 302.0, 105.0, 30.0
    PLANET = (65.0, 455.0, 265.0)

    def colors(self, p):
        st = self.__dict__.setdefault("_c", {})
        k = self.key(p)
        if k in st:
            return st[k]
        bg, dk = p("bg"), p.dark
        if dk:
            top, low = mix(bg, BLACK3, 0.62), mix(bg, BLACK3, 0.38)
            c = dict(top=top, low=low, star=p("fg"), stardim=mix(low, p("fg"), 0.45), shadow=mix(bg, BLACK3, 0.94),
                     hot=mix(p("ansi_3"), WHITE3, 0.55), warm=p("ansi_3"), cool=p("ansi_1"), ring=mix(p("fg"), p("ansi_3"), 0.25),
                     planet=mix(bg, BLACK3, 0.22), planet2=mix(bg, BLACK3, 0.42), planetlit=mix(mix(bg, BLACK3, 0.22), p("accent"), 0.32),
                     limb=p("accent"), probe=p("fg"), neb1=mix(low, p("accent"), 0.16), neb2=mix(low, p("ansi_5"), 0.14))
        else:
            top, low = p("bg+white:30"), p("bg")
            c = dict(top=top, low=low, star=p("fg"), stardim=p("bg+fg:40"), shadow=mix(p("fg"), BLACK3, 0.2),
                     hot=p("ansi_3"), warm=mix(p("ansi_3"), p("ansi_1"), 0.5), cool=p("ansi_1"), ring=p("fg"),
                     planet=p("bg+fg:10"), planet2=p("bg+fg:20"), planetlit=p("bg+accent:30"),
                     limb=p("accent"), probe=p("fg"), neb1=p("bg+accent:10"), neb2=p("bg+ansi_5:8"))
        st[k] = c
        return c

    def extra(self, p, c):
        mid = mix(c["top"], c["low"], 0.5)
        out = ramp(c["top"], c["low"], 4)
        for col in ("warm", "cool", "hot", "ring", "limb"):
            out += ramp(mid, c[col], 5)[1:-1]
        out += ramp(c["warm"], c["hot"], 3)[1:2] + ramp(c["cool"], c["warm"], 3)[1:2] + ramp(c["planet"], c["planetlit"], 3)[1:2]
        out += [mix(c["shadow"], c["warm"], 0.3), mix(c["shadow"], c["hot"], 0.5)]
        return out

    def back(self, a, p, c):
        dk = p.dark
        pgrad(a, 0, PH, [(0, c["top"]), (PH, c["low"])])
        pglow(a, 130, 75, 170, c["neb1"], 0.55, add=False)
        pglow(a, 375, 205, 140, c["neb2"], 0.5, add=False)
        rnd = random.Random(12)
        self.twinkle = []
        for i in range(260):
            x, y = rnd.randrange(PW), rnd.randrange(PH)
            if math.hypot(x - self.CX, y - self.CY) < 70:
                continue
            m = rnd.random() ** 3
            if m > 0.9:
                put(a, x, y, c["star"])
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    put(a, x + dx, y + dy, c["stardim"])
            elif m > 0.4:
                put(a, x, y, c["star"])
                if i % 4 == 0:
                    self.twinkle.append((x, y, rnd.choice((3, 4, 6, 8)), rnd.random()))
            else:
                put(a, x, y, c["stardim"], 0.8 if dk else 0.6)
        # the planet's edge, lit from the disc, its ice in bands
        px_, py_, pr = self.PLANET
        ys, xs = np.mgrid[0:PH, 0:PW].astype(np.float32)
        d = np.sqrt((xs - px_) ** 2 + (ys - py_) ** 2)
        inside = d <= pr
        a[inside] = C(c["planet"])
        rim = np.clip(1 - (pr - d) / 26, 0, 1) ** 2 * np.clip(0.4 + 0.6 * (xs - px_) / pr + 0.3 * (py_ - ys) / pr, 0, 1)
        a[inside] += (C(c["planetlit"]) - a[inside]) * rim[inside][:, None]
        for k in range(5):
            r = pr - 14 - k * 17
            band = inside & (np.abs(d - r) < 0.6)
            a[band] = C(c["planet2"])
        limb = np.abs(d - pr) < 0.7
        a[limb] = C(c["limb"])
        halo = (d > pr) & (d < pr + 7)
        a[halo] += (C(c["limb"]) - a[halo]) * (0.25 * (1 - (d[halo] - pr) / 7) ** 2 * np.clip(0.3 + (xs[halo] - px_) / pr, 0, 1))[:, None]
        fill(a, Mask().ell(self.CX, self.CY, self.RS, self.RS), c["shadow"])

    def light(self, a, c, t, dk):
        cx, cy, rs = self.CX, self.CY, self.RS
        x0, x1, y0, y1 = int(cx - 150), int(cx + 151), int(cy - 60), int(cy + 61)
        X = np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5 - cx
        Y = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5 - cy
        tilt = -0.08
        xr = X * math.cos(tilt) + Y * math.sin(tilt)
        yr = -X * math.sin(tilt) + Y * math.cos(tilt)
        q, rin, rout = 0.085, 33.0, 140.0
        rho = np.sqrt(xr ** 2 + (yr / q) ** 2)
        phi = np.arctan2(yr / q, xr)
        f = np.clip((rho - rin) / (rout - rin), 0, 1)
        edge = np.clip((rho - rin) / 2.5, 0, 1) * np.clip((rout - rho) / 30, 0, 1)
        swirl = 0.8 + 0.2 * np.sin(phi * 5 + rho * 0.1 - 2 * math.pi * 2 * t / self.seconds) * np.sin(phi * 2 - rho * 0.048 + 1.3)
        doppler = 1 - 0.42 * np.cos(phi)
        disc = 1.6 * edge * (rin / np.maximum(rho, rin)) ** 1.25 * swirl * doppler
        r = np.sqrt(X ** 2 + Y ** 2)
        disc = np.where((yr < 0) & (r < rs), 0, disc)
        theta = np.arctan2(Y, X)
        lensed = 0.8 * np.exp(-((r - rs * 1.19) / 2.2) ** 2) * (0.5 + 0.5 * np.abs(np.sin(theta))) * (1 - 0.35 * np.cos(theta))
        photon = np.exp(-((r - rs * 1.04) / 0.7) ** 2) * 0.9
        hot, warm, cool = C(c["hot"]), C(c["warm"]), C(c["cool"])
        fc = f[..., None]
        col = np.where(fc < 0.35, hot + (warm - hot) * (fc / 0.35), warm + (cool - warm) * np.clip((fc - 0.35) / 0.65, 0, 1))
        ring = hot * 0.5 + warm * 0.5
        total = disc + lensed + photon
        mixed = (col * disc[..., None] + ring * lensed[..., None] + C(c["ring"]) * photon[..., None]) / np.maximum(total, 1e-4)[..., None]
        sub = a[y0:y1, x0:x1]
        k = np.clip(total, 0, 1)[..., None]
        sub += (mixed - sub) * k

    def draw(self, a, p, c, t):
        dk = p.dark
        for x, y, per, ph in self.twinkle:
            if wave(t, 24 / per, ph) < -0.2:
                put(a, x, y, c["stardim"])
        pglow(a, self.CX, self.CY, 80, c["warm"], 0.08 if dk else 0.05, add=dk)
        self.light(a, c, t, dk)
        u = window(t, 3.0, 21.0)
        if 0 < u < 1:
            s_ = 1 - (1 - u) ** 3
            r = 225 - (225 - (self.RS + 11)) * s_
            ang = -0.62 + 0.9 * s_
            x, y = self.CX + r * math.cos(ang), self.CY + r * math.sin(ang) * 0.6
            redden = clamp((s_ - 0.7) / 0.3)
            col = mix(c["probe"], c["cool"], redden)
            blink = 1.0 if (t * (2.0 - 1.7 * redden)) % 1.0 < 0.5 else 0.35
            fade = 1 - clamp((u - 0.82) / 0.18)
            put(a, x, y, col, blink * fade)
            if blink > 0.5 and fade > 0.3:
                pglow(a, x, y, 4, col, 0.3 * fade, add=dk)


# -- watch ------------------------------------------------------------------------


class Watch(Pixel):
    """The sea at night, the moon low and its road on the water, a lighthouse
    sweeping. Once a loop the lighthouse stops and looks up at the moon."""

    name = "watch"
    poster = 0.5
    portrait = True
    F, EYE = 236.0, 1.0  # the eye: one unit over the water, the horizon at HZ
    REACH = 50.0  # how far out its beam comes down on the water

    def layout(self, portrait):
        """Where things are: landscape, or a portrait's tall sky and long road of moonlight."""
        if portrait:
            self.HZ, self.MOON, self.LX, self.BUOY, self.CLOUDS, self.SHIFT = 274, (168.0, 150.0), 40, (204, 283), (96, 236), -12
        else:
            self.HZ, self.MOON, self.LX, self.BUOY, self.CLOUDS, self.SHIFT = 152, (140.0, 110.0), 52, (330, 161), (78, 135), 0
        z = 60.0  # the lamp in the world: across, up, away; on screen at LX, 29 over the horizon
        self.LAMP = ((self.LX - self.gw / 2) * z / self.F, self.EYE + 29 * z / self.F, z)

    def scr(self, x, y, z):
        """A point of the world on the screen, in perspective."""
        return self.gw / 2 + self.F * x / z, self.HZ + self.F * (self.EYE - y) / z

    def colors(self, p):
        st = self.__dict__.setdefault("_c", {})
        k = self.key(p)
        if k in st:
            return st[k]
        bg, dk = p("bg"), p.dark
        if dk:
            moon = p("fg+ansi_3:12")
            c = dict(top=mix(bg, BLACK3, 0.6), low=mix(bg, p("accent"), 0.16), sea=mix(mix(bg, BLACK3, 0.18), p("accent"), 0.06), deep=mix(bg, BLACK3, 0.55),
                     seahi=mix(mix(bg, BLACK3, 0.18), p("accent"), 0.3), moon=moon, mare=mix(moon, mix(bg, p("accent"), 0.16), 0.3),
                     glint=p("fg"), glintdim=mix(p("fg"), mix(bg, BLACK3, 0.3), 0.55), cloud=mix(mix(bg, p("accent"), 0.1), BLACK3, 0.25), cloudlit=mix(mix(bg, p("accent"), 0.16), moon, 0.38),
                     land=mix(bg, BLACK3, 0.74), landedge=mix(mix(bg, BLACK3, 0.74), moon, 0.14), tower=mix(p("fg"), bg, 0.3), towerred=mix(p("ansi_1"), bg, 0.3),
                     beam=p("ansi_3+white:50"), star=p("fg"), stardim=mix(mix(bg, BLACK3, 0.6), p("fg"), 0.45), buoy=p("ansi_2"))
        else:
            moon = p("ansi_3+white:40")
            c = dict(top=p("bg+fg:10"), low=p("bg+white:45"), sea=p("bg+ansi_4:22"), deep=p("bg+ansi_4:36"), seahi=p("bg+white:50"),
                     moon=moon, mare=mix(moon, p("bg+fg:20"), 0.35), glint=p("white"), glintdim=p("bg+white:30"), cloud=p("bg+fg:14"), cloudlit=p("bg+white:60"),
                     land=p("bg+fg:44"), landedge=p("bg+fg:30"), tower=p("white"), towerred=p("ansi_1"), beam=p("white"), star=p("fg"), stardim=p("bg+fg:20"), buoy=p("ansi_2"))
        st[k] = c
        return c

    def extra(self, p, c):
        return (ramp(c["top"], c["low"], 6) + ramp(c["sea"], c["deep"], 4) + ramp(c["low"], c["moon"], 4)[1:-1] + ramp(c["sea"], c["beam"], 4)[1:-1]
                + ramp(c["top"], c["beam"], 4)[1:-1] + [mix(c["land"], c["beam"], 0.4), mix(c["sea"], c["buoy"], 0.5)])

    def back(self, a, p, c):
        dk = p.dark
        pgrad(a, 0, self.HZ, [(0, c["top"]), (self.HZ, c["low"])])
        if dk:
            rnd = random.Random(31)
            for i in range(170 if self.gw > self.gh else 230):
                x, y = rnd.randrange(self.gw), rnd.randrange(self.HZ - 30)
                put(a, x, y, c["star"] if rnd.random() < 0.3 else c["stardim"])
        mx, my = self.MOON
        pglow(a, mx, my, 44, c["moon"], 0.22 if dk else 0.35, add=False)
        fill(a, Mask().ell(mx, my, 9, 9), c["moon"])
        for dx, dy in ((-3, -2), (-2, -2), (-3, -1), (2, 1), (3, 1), (2, 2), (0, 4), (-1, 3)):
            put(a, mx + dx, my + dy, c["mare"])
        clouds(a, 5, 5, self.CLOUDS, c["cloud"], c["cloudlit"], 0.9, lit_below=False, wmin=60, wmax=170)
        pgrad(a, self.HZ, self.gh, [(self.HZ, c["sea"]), (self.gh, c["deep"])])
        hline(a, 0, self.gw, self.HZ, c["seahi"])
        rnd = random.Random(9)
        for i in range(260):  # the sea's texture: short strokes, longer as they come near
            y = self.HZ + 2 + int((self.gh - self.HZ) * rnd.random() ** 1.5)
            ln = 1 + int((y - self.HZ) / 12)
            x = rnd.randrange(self.gw)
            hline(a, x, x + ln, y, c["seahi"] if rnd.random() < 0.5 else c["deep"], 0.7)
        land = [(0, self.HZ + 1), (0, self.HZ - 13)] + [(x + self.SHIFT, self.HZ + y) for x, y in ((14, -15), (30, -12), (46, -10), (64, -6), (80, -2), (92, 1))]
        fill(a, Mask().poly(land), c["land"])
        for (x0, y0), (x1_, y1_) in zip(land[1:-2], land[2:-1]):
            fill(a, Mask().line([(x0, y0), (x1_, y1_)]), c["landedge"])
        lx = self.LX
        for y in range(self.HZ - 26, self.HZ - 9):
            w = 3 if y < self.HZ - 17 else 4
            band = ((y - (self.HZ - 26)) // 3) % 2
            box(a, lx - w // 2, y, w, 1, c["towerred"] if band else c["tower"])
        box(a, lx - 3, self.HZ - 27, 7, 1, c["land"])
        box(a, lx - 1, self.HZ - 30, 3, 3, c["land"])
        put(a, lx, self.HZ - 29, c["beam"])
        box(a, lx - 2, self.HZ - 31, 5, 1, c["land"])
        put(a, lx, self.HZ - 32, c["land"])
        self.lamp = (lx, self.HZ - 29)

    def draw(self, a, p, c, t):
        dk = p.dark
        mx, my = self.MOON
        rnd = random.Random(5)
        for i in range(80):  # the moon's road: strokes that come and go
            y = self.HZ + 2 + int((self.gh - self.HZ - 2) * rnd.random() ** 1.7)
            spread = 5 + (y - self.HZ) * 0.42
            x = mx + rnd.uniform(-1, 1) * spread
            ln = 1 + int((y - self.HZ) * 0.07)
            v = wave(t, 24 / rnd.choice((6, 8, 12)), rnd.random())
            if v > 0.1:
                hline(a, x - ln, x + ln + 1, y, c["glint"] if v > 0.6 else c["glintdim"])
        for k in range(8):  # the swell, rolling in
            u = ((t / 8.0) + k / 8) % 1.0
            y = self.HZ + 3 + (self.gh - self.HZ - 3) * u ** 1.6
            al = 0.25 + 0.5 * bump(u)
            for x in range(-(k * 7) % 9, self.gw, 9):
                yy = y + 1.5 * math.sin(x / 35 + k)
                hline(a, x, x + 3 + int(4 * u), yy, c["deep"], al)
        # the buoy far out: green, every three seconds
        if (t % 3.0) < 0.35:
            bx, by = self.BUOY
            put(a, bx, by, c["buoy"])
            pglow(a, bx, by, 5, c["buoy"], 0.35, add=dk)
            put(a, bx, by + 3, c["buoy"], 0.4)
        # the beam: it sweeps the water, three times a loop; once it looks up at the moon
        lx, ly = self.lamp
        ang = 2 * math.pi * t / 8.0
        w = ease_io(window(t, 12.3, 13.3)) * (1 - ease_io(window(t, 14.9, 15.9)))
        X0, Y0, Z0 = self.LAMP
        dx, dz = math.cos(ang), -math.sin(ang)  # where it points, on the water; -z is toward us
        gx, gz = X0 + self.REACH * dx, Z0 + self.REACH * dz
        cx_, cz_ = -X0, -Z0  # toward the eye
        n_ = math.hypot(cx_, cz_)
        facing = max(0.0, (dx * cx_ + dz * cz_) / n_) ** 6
        away = max(0.0, -math.sin(ang))
        spot = []
        for k in range(20):  # the patch it lights: a round of light on the water, seen in perspective
            f = 2 * math.pi * k / 20
            px_ = gx + 13 * math.cos(f) * dx + 7 * math.sin(f) * (-dz)
            pz_ = gz + 13 * math.cos(f) * dz + 7 * math.sin(f) * dx
            spot.append(self.scr(px_, 0.0, max(pz_, 3.0)))
        gs = self.scr(gx, 0.0, gz)
        if w > 0:  # it lifts off the water toward the moon
            tip = (gs[0] + (mx - gs[0]) * w, gs[1] + (my - gs[1]) * w)
            spot = [(tip[0] + (x - gs[0]) * (1 - 0.6 * w), tip[1] + (y - gs[1]) * (1 - 0.8 * w)) for x, y in spot]
        k = (1 - 0.6 * away ** 2) * (1 - w) + w
        water = (1 - w) * (1 - 0.6 * away ** 2)
        fill(a, Mask().poly(hull(spot + [(lx, ly - 1), (lx, ly + 1)])), c["beam"], (0.18 if dk else 0.26) * k)
        if water > 0.05:
            # the beam again in the water, from the lamp's mirror image down there to the patch
            rx, ry = self.scr(X0, -Y0, Z0)
            m = Mask().poly(hull(spot + [(rx, ry)])).m()
            m[: self.HZ + 1] = False
            rows = (np.arange(self.gh) + int(t * PFPS)) % 3 == 0  # broken by the swell
            m[rows] = False
            fill(a, m, c["beam"], (0.1 if dk else 0.16) * water)
            fill(a, Mask().poly(spot), c["beam"], (0.3 if dk else 0.35) * water)
            rnd = random.Random(17)
            for i in range(14):  # glints in the patch, short far off and longer near
                f, r = rnd.uniform(0, 2 * math.pi), rnd.random() ** 0.5
                px_ = gx + 12 * r * math.cos(f) * dx + 6 * r * math.sin(f) * (-dz)
                pz_ = max(3.0, gz + 12 * r * math.cos(f) * dz + 6 * r * math.sin(f) * dx)
                if wave(t, 24 / rnd.choice((8, 12, 24)), rnd.random()) > 0:
                    sx, sy = self.scr(px_, 0.0, pz_)
                    half = max(0.5, 0.25 * self.F / pz_)
                    hline(a, sx - half, sx + half + 1, sy, c["glint"], 0.7 * water)
        put(a, lx, ly, c["beam"])
        pglow(a, lx, ly, 3 + 12 * facing * (1 - w), c["beam"], 0.5 + 0.4 * facing * (1 - w), add=dk)
        for d in range(3, 24, 2):  # the lamp in the water below it, brighter when it faces us
            put(a, lx + (d % 3) - 1, self.HZ + d, c["glint"], (0.25 + 0.6 * facing) * (1 - d / 24))


# -- problem ----------------------------------------------------------------------


def hold_mask(kind, rnd):
    """A climbing hold as a pixel artist would cut it: a jug, a crimp, a sloper..."""
    m = Mask(34, 34)
    cx, cy = 17, 17
    rot = rnd.uniform(-0.6, 0.6)
    e = lambda rx, ry, r=rot, x=cx, y=cy: [(round(px_), round(py_)) for px_, py_ in ellipse_pts(x, y, rx, ry, r, 28)]
    groove = None
    if kind == "jug":
        m.poly(e(10.5, 7))
        groove = e(6.5, 1.6, rot, cx, cy - 3)
    elif kind == "crimp":
        m.poly(e(10, 3.2, rot * 0.4))
    elif kind == "sloper":
        m.poly(e(11, 8.5))
    elif kind == "pinch":
        m.poly(e(4.5, 10, rot * 0.6))
    elif kind == "pocket":
        m.poly(e(8.5, 7))
        groove = e(2.6, 2, 0, cx, cy - 1)
    elif kind == "edge":
        m.poly([(cx - 9, cy - 3), (cx + 9, cy - 4), (cx + 8, cy + 4), (cx - 8, cy + 4)])
    elif kind == "blob":
        for k in range(3):
            m.poly(e(rnd.uniform(4, 7), rnd.uniform(3, 6), rnd.uniform(0, 3), cx + rnd.randint(-5, 5), cy + rnd.randint(-3, 3)))
    else:  # a foot chip
        m.ell(cx, cy, 3, 2)
    g = Mask(34, 34).poly(groove).m() if groove else None
    return m.m(), g


def dome(m):
    """How far each pixel of a mask is from its edge: a hold's height."""
    h = np.zeros(m.shape, np.int32)
    cur = m.copy()
    while cur.any():
        h += cur
        p_ = np.pad(cur, 1)
        cur = cur & p_[:-2, 1:-1] & p_[2:, 1:-1] & p_[1:-1, :-2] & p_[1:-1, 2:]
    return h


class Problem(Pixel):
    """A training board at night, a grid of holds, each with its light. The
    board shows a problem, then another; then it runs Life, and a glider climbs
    down across it."""

    name = "problem"
    poster = 4.0
    CELL, COLS, ROWS = 30, 16, 9
    KINDS = ("jug", "crimp", "sloper", "pinch", "pocket", "edge", "jug", "blob", "blob", "crimp", "sloper")
    HUES = ("ansi_1", "ansi_2", "ansi_3", "ansi_4", "ansi_5", "ansi_6", "w", "k", "ansi_3", "w")
    A = ([(5, 1), (6, 1)], [(4, 3), (7, 4), (5, 5), (8, 6), (6, 7)], [(7, 8)])
    B = ([(10, 0)], [(12, 2), (9, 3), (11, 5), (13, 6), (10, 7)], [(12, 8)])

    def colors(self, p):
        st = self.__dict__.setdefault("_c", {})
        k = self.key(p)
        if k in st:
            return st[k]
        bg, dk = p("bg"), p.dark
        if dk:
            wall = mix(mix(bg, p("ansi_3"), 0.14), BLACK3, 0.3)
            c = dict(wall=wall, walllit=mix(wall, p("fg"), 0.07), walldark=mix(wall, BLACK3, 0.45), seam=mix(wall, BLACK3, 0.28), tnut=mix(wall, BLACK3, 0.6),
                     ledoff=mix(wall, BLACK3, 0.7), ledrim=mix(wall, p("fg"), 0.16),
                     start=p("ansi_10"), hand=p("ansi_12"), top=p("ansi_9"), life=p("ansi_13"))
            for h in self.HUES:
                col = p("fg") if h == "w" else mix(bg, BLACK3, 0.45) if h == "k" else p(h)
                if h == "k":
                    c[h], c[h + "l"], c[h + "d"], c[h + "s"] = col, mix(col, p("fg"), 0.3), mix(col, BLACK3, 0.6), mix(col, p("fg"), 0.5)
                else:
                    c[h], c[h + "l"], c[h + "d"], c[h + "s"] = mix(col, wall, 0.22), mix(col, WHITE3, 0.2), mix(col, wall, 0.6), mix(col, WHITE3, 0.6)
        else:
            wall = p("bg+ansi_3:16")
            c = dict(wall=wall, walllit=p("bg+white:40"), walldark=mix(wall, BLACK3, 0.2), seam=mix(wall, BLACK3, 0.1), tnut=mix(wall, BLACK3, 0.4),
                     ledoff=p("bg+fg:40"), ledrim=p("bg+fg:20"),
                     start=p("ansi_2"), hand=p("ansi_4"), top=p("ansi_1"), life=p("ansi_5"))
            for h in self.HUES:
                col = p("white") if h == "w" else p("bg+fg:75") if h == "k" else p(h)
                c[h], c[h + "l"], c[h + "d"], c[h + "s"] = col, mix(col, WHITE3, 0.35), mix(col, BLACK3, 0.35), mix(col, WHITE3, 0.7)
        st[k] = c
        return c

    def extra(self, p, c):
        out = ramp(c["walllit"], c["wall"], 3)[1:2] + ramp(c["wall"], c["walldark"], 3)[1:2]
        for led in ("start", "hand", "top", "life"):
            out += ramp(c["wall"], c[led], 5)[1:-1] + [mix(c[h], c[led], 0.4) for h in ("w", "k", "ansi_3")]
        return out

    def cell(self, col, row):  # row 0 at the bottom
        return col * self.CELL, (self.ROWS - 1 - row) * self.CELL

    def back(self, a, p, c):
        a[:] = C(c["wall"])
        pgrad(a, 0, PH, [(0, c["walllit"]), (110, c["wall"]), (PH, mix(c["wall"], c["walldark"], 0.6))])
        for y in range(5, PH, 10):  # the T-nuts, a hole every ten
            for x in range(5, PW, 10):
                put(a, x, y, c["tnut"])
        for x in range(0, PW, 120):
            vline(a, x, 0, PH, c["seam"])
        for y in range(0, PH, 90):
            hline(a, 0, PW, y, c["seam"])
        rnd = random.Random(77)
        for col in range(self.COLS):
            for row in range(self.ROWS):
                x, y = self.cell(col, row)
                picks = [rnd.choice(self.KINDS)]
                if rnd.random() < 0.3:
                    picks.append("chip")
                for n, kind in enumerate(picks):
                    h = rnd.choice(self.HUES)
                    base, light, dark, spec = c[h], c[h + "l"], c[h + "d"], c[h + "s"]
                    m, g = hold_mask(kind, rnd)
                    if n == 0:
                        ox, oy = x - 2 + rnd.randint(-3, 3), y - 1 + rnd.randint(-2, 4)
                    else:
                        ox, oy = x - 17 + rnd.choice((6, 24)), y - 17 + 24
                    self.hold(a, c, m, g, ox, oy, base, light, dark, spec, kind != "chip")
                lx, ly = x + 2, y + 2
                box(a, lx, ly, 2, 2, c["ledoff"])

    def hold(self, a, c, m, g, ox, oy, base, light, dark, spec, bolt):
        ys_, xs_ = np.nonzero(m)
        if not len(ys_):
            return
        hh = dome(m)
        sh = np.zeros((m.shape[0] + 3, m.shape[1] + 3), bool)
        sh[ys_ + 1, xs_ + 2] = True
        sh[ys_ + 2, xs_ + 2] = True
        sh[ys_ + 2, xs_ + 3] = True
        sh[ys_, xs_] = False
        for yy, xx in zip(*np.nonzero(sh)):
            put(a, ox + xx, oy + yy, c["walldark"])
        pad = np.pad(hh, 2)
        top_ = max(1, hh.max())
        for yy, xx in zip(ys_, xs_):
            here = hh[yy, xx]
            ul = pad[yy + 1, xx + 1]  # toward the light, up and left
            dr = pad[yy + 3, xx + 3]
            if ul < here and here <= 1:
                col_ = light
            elif dr < here and here <= 2:
                col_ = dark
            elif ul < here and here <= 3 and top_ > 4:
                col_ = mix(base, light, 0.5)
            else:
                col_ = base
            put(a, ox + xx, oy + yy, col_)
        if g is not None:
            for yy, xx in zip(*np.nonzero(g & m)):
                put(a, ox + xx, oy + yy, dark)
        cy_, cx_ = np.argwhere(hh == top_)[0]
        if top_ >= 3:
            put(a, ox + cx_ - 2, oy + cy_ - 2, spec)
        if bolt:
            put(a, ox + cx_, oy + cy_, c["tnut"])
            put(a, ox + cx_ - 1, oy + cy_ - 1, light)

    def led(self, a, c, col, row, colr, k, dk):
        x, y = self.cell(col, row)
        lx, ly = x + 2, y + 2
        box(a, lx, ly, 2, 2, colr, k)
        if k > 0.5:
            pglow(a, lx + 12, ly + 13, 24, colr, 0.5 * k if dk else 0.3 * k, add=dk)
            box(a, lx, ly, 2, 2, colr)
            for dx, dy in ((-1, 0), (2, 0), (0, -1), (0, 2), (-1, 1), (2, 1), (1, -1), (1, 2)):
                put(a, lx + dx, ly + dy, colr, 0.5)

    def life(self):
        if hasattr(self, "_life"):
            return self._life
        cells = {(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)}
        cells = {(x + 2, y + 0) for x, y in cells}
        gens = [cells]
        for _ in range(30):
            n = {}
            for x, y in cells:
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if dx or dy:
                            n[(x + dx, y + dy)] = n.get((x + dx, y + dy), 0) + 1
            cells = {q for q, v in n.items() if v == 3 or (v == 2 and q in cells)}
            gens.append(cells)
        self._life = gens
        return gens

    def draw(self, a, p, c, t):
        dk = p.dark
        for prob, t0, t1 in ((self.A, 0.5, 7.2), (self.B, 7.8, 14.6)):
            if t0 <= t < t1:
                seq = [(q, c["start"]) for q in prob[0]] + [(q, c["hand"]) for q in prob[1]] + [(q, c["top"]) for q in prob[2]]
                for i, ((col, row), colr) in enumerate(seq):
                    if t >= t0 + 0.09 * i:
                        self.led(a, c, col, row, colr, 1.0, dk)
        if 15.2 <= t < 22.8:  # the board runs Life: a glider walks down it
            g = int((t - 15.2) / 0.3)
            for x, y in self.life()[g]:
                if 0 <= x < self.COLS and 0 <= y < self.ROWS:
                    self.led(a, c, x, self.ROWS - 1 - y, c["life"], 1.0, dk)


# -- continue ---------------------------------------------------------------------


class Continue(Pixel):
    """An arcade after closing: the machines play to no one. One of them asks
    an empty room to continue, counts down, and gives up."""

    name = "continue"
    poster = 6.0
    FLOOR = 214
    CABS = (88, 168, 248, 328, 408)

    def colors(self, p):
        st = self.__dict__.setdefault("_c", {})
        k = self.key(p)
        if k in st:
            return st[k]
        bg, dk = p("bg"), p.dark
        hues = (p("ansi_4"), p("ansi_5"), p("ansi_2"), p("ansi_1"), p("ansi_3"))
        if dk:
            wallc = mix(bg, BLACK3, 0.62)
            c = dict(wall=wallc, wall2=mix(bg, BLACK3, 0.7), floor=mix(bg, BLACK3, 0.72), carpet1=mix(mix(bg, BLACK3, 0.72), p("ansi_5"), 0.28),
                     carpet2=mix(mix(bg, BLACK3, 0.72), p("ansi_6"), 0.25), carpet3=mix(mix(bg, BLACK3, 0.72), p("ansi_3"), 0.25),
                     screen=mix(bg, BLACK3, 0.85), ink=mix(bg, BLACK3, 0.88), text=p("fg"), textdim=mix(p("fg"), BLACK3, 0.45),
                     neon=p("ansi_5"), neondim=mix(p("ansi_5"), wallc, 0.7),
                     red=p("ansi_1"), yellow=p("ansi_3"), green=p("ansi_2"), cyan=p("ansi_6"), blue=p("ansi_4"), white=p("fg"))
            for i, h in enumerate(hues):
                c["body%d" % i] = mix(h, BLACK3, 0.7)
                c["edge%d" % i] = mix(h, BLACK3, 0.84)
                c["side%d" % i] = mix(h, BLACK3, 0.55)
                c["marq%d" % i] = mix(h, WHITE3, 0.3)
        else:
            c = dict(wall=p("bg+fg:12"), wall2=p("bg+fg:18"), floor=p("bg+fg:24"), carpet1=p("bg+ansi_5:30"), carpet2=p("bg+ansi_6:30"), carpet3=p("bg+ansi_3:30"),
                     screen=mix(p("fg"), BLACK3, 0.55), ink=p("bg+fg:80"), text=p("white"), textdim=p("bg+fg:40"),
                     neon=p("ansi_5"), neondim=p("bg+ansi_5:30"),
                     red=p("ansi_1"), yellow=p("ansi_3"), green=p("ansi_2"), cyan=p("ansi_6"), blue=p("ansi_4"), white=p("white"))
            for i, h in enumerate(hues):
                c["body%d" % i] = mix(h, BLACK3, 0.35)
                c["edge%d" % i] = mix(h, BLACK3, 0.6)
                c["side%d" % i] = mix(h, BLACK3, 0.15)
                c["marq%d" % i] = mix(h, WHITE3, 0.5)
        st[k] = c
        return c

    def extra(self, p, c):
        out = []
        for col in ("blue", "neon", "green", "red", "yellow", "cyan"):
            out += ramp(c["wall"], c[col], 5)[1:-1] + ramp(c["floor"], c[col], 4)[1:-1] + ramp(c["screen"], c[col], 3)[1:2]
        for i in range(5):
            out += [mix(c["body%d" % i], c["white"], 0.18)]
        out += ramp(c["screen"], c["white"], 4)[1:-1]
        return out

    def back(self, a, p, c):
        dk = p.dark
        a[:] = C(c["wall"])
        for x in range(0, PW, 24):
            vline(a, x, 0, self.FLOOR, c["wall2"])
        box(a, 0, self.FLOOR, PW, PH - self.FLOOR, c["floor"])
        rnd = random.Random(15)
        for i in range(260):  # the carpet: little cosmic shapes, as arcade carpets have
            x, y = rnd.randrange(PW), rnd.randrange(self.FLOOR + 2, PH)
            col = c[rnd.choice(("carpet1", "carpet2", "carpet3"))]
            kind = rnd.random()
            if kind < 0.4:
                put(a, x, y, col)
                put(a, x + 1, y, col)
            elif kind < 0.7:
                put(a, x, y, col)
                put(a, x + 1, y + 1, col)
                put(a, x + 2, y, col)
            else:
                for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                    put(a, x + dx, y + dy, col)
        hline(a, 0, PW, self.FLOOR, c["ink"])
        # the claw machine
        box(a, 16, 70, 58, self.FLOOR - 70, c["edge1"])
        box(a, 20, 74, 50, 70, c["body1"])
        box(a, 22, 82, 46, 56, mix(c["body1"], c["white"], 0.18))
        rnd = random.Random(4)
        for i in range(9):
            px_, py_ = 25 + rnd.randrange(38), 126 + rnd.randrange(8)
            col = c[rnd.choice(("red", "yellow", "green", "cyan", "neon"))]
            fill(a, Mask().ell(px_, py_, 3, 2), col)
            put(a, px_ - 2, py_ - 3, col)
            put(a, px_ + 2, py_ - 3, col)
        box(a, 20, 146, 50, 10, c["side1"])
        box(a, 40, 160, 10, 14, c["ink"])
        box(a, 43, 164, 4, 6, c["red"], 0.9)
        box(a, 18, 66, 54, 8, c["marq1"])
        text(a, 27, 68, "PRIZE", c["edge1"])
        # the cabinets
        for i, x in enumerate(self.CABS):
            body, edge, side, marq = (c[n % i] for n in ("body%d", "edge%d", "side%d", "marq%d"))
            box(a, x, 56, 64, self.FLOOR - 56, edge)
            box(a, x + 3, 60, 58, self.FLOOR - 62, body)
            box(a, x + 3, 60, 2, self.FLOOR - 62, side)
            box(a, x + 59, 60, 2, self.FLOOR - 62, side)
            box(a, x + 4, 62, 56, 16, marq)
            box(a, x + 6, 82, 52, 44, c["ink"])
            box(a, x + 5, 130, 54, 4, side)
            box(a, x + 4, 134, 56, 14, mix(body, c["white"], 0.18))
            box(a, x + 14, 136, 1, 6, c["ink"])
            box(a, x + 13, 135, 3, 2, c["red"])
            for b, colr in enumerate((c["red"], c["yellow"], c["cyan"])):
                box(a, x + 28 + b * 7, 140, 3, 2, colr)
            for s_ in (0, 1):
                box(a, x + 22 + s_ * 14, 164, 6, 10, c["ink"])
                box(a, x + 24 + s_ * 14, 166, 2, 6, c["red"])
                pglow(a, x + 25 + s_ * 14, 169, 6, c["red"], 0.3 if dk else 0.1, add=dk)
            box(a, x + 4, 196, 56, 16, edge)
            title = ("ZAP", "RACE", "BRIX", "QUEST", "CLIMB")[i]
            text(a, x + 32 - len(title) * 2, 66, title, edge)
            hline(a, x + 6, x + 58, 75, edge)

    def screen(self, a, c, i, t):
        x0, y0, w, h = self.CABS[i] + 8, 84, 48, 40
        box(a, x0, y0, w, h, c["screen"])
        rnd = random.Random(i * 11 + 3)
        if i == 0:  # a shooter: stars going by, a ship that dodges, a row that marches
            for k in range(30):
                sx, sy0 = rnd.randrange(w), rnd.randrange(h)
                sy = (sy0 + t * h / 2) % h
                put(a, x0 + sx, y0 + sy, c["textdim"] if k % 3 else c["text"])
            shx = x0 + 22 + 14 * math.sin(2 * math.pi * t / 6)
            for dx, dy in ((0, 0), (-1, 1), (0, 1), (1, 1), (-2, 2), (-1, 2), (0, 2), (1, 2), (2, 2)):
                put(a, shx + dx, y0 + h - 5 + dy, c["cyan"])
            ex = x0 + 8 + 6 * math.sin(2 * math.pi * t / 4)
            for k in range(5):
                for dx, dy in ((0, 0), (2, 0), (1, 1), (0, 2), (2, 2)):
                    put(a, ex + k * 7 + dx, y0 + 6 + dy + (1 if int(t * 4) % 2 else 0), c["neon"])
            for k in range(3):
                u = ((t * 1.5) + k / 3) % 1.0
                put(a, shx, y0 + h - 7 - (h - 14) * u, c["yellow"])
                put(a, shx, y0 + h - 8 - (h - 14) * u, c["yellow"])
        elif i == 1:  # a racer: the road coming at us
            hz = y0 + 12
            box(a, x0, y0, w, 12, mix(c["screen"], c["blue"], 0.5))
            box(a, x0, hz, w, h - 12, mix(c["screen"], c["green"], 0.35))
            for yy in range(hz, y0 + h):
                d = (yy - hz) / (h - 12)
                half = 2 + d * 26
                cx = x0 + w / 2 + 3 * math.sin(2 * math.pi * t / 8) * (1 - d)
                hline(a, cx - half, cx + half, yy, c["ink"])
                z = 1 / (d + 0.08)
                if (z * 0.5 + t * 6) % 2 < 1:
                    put(a, cx - half - 1, yy, c["red"])
                    put(a, cx + half, yy, c["red"])
                    put(a, cx, yy, c["text"])
                else:
                    put(a, cx - half - 1, yy, c["text"])
                    put(a, cx + half, yy, c["text"])
            cx = x0 + w / 2 + 4 * math.sin(2 * math.pi * t / 4)
            box(a, cx - 4, y0 + h - 6, 9, 3, c["red"])
            box(a, cx - 2, y0 + h - 8, 5, 2, c["red"])
            put(a, cx - 4, y0 + h - 3, c["ink"])
            put(a, cx + 4, y0 + h - 3, c["ink"])
        elif i == 2:  # bricks and a ball that never misses
            cols = (c["red"], c["yellow"], c["green"], c["cyan"])
            for r in range(4):
                for k in range(8):
                    box(a, x0 + 1 + k * 6, y0 + 4 + r * 3, 5, 2, cols[r])
            u = (t / 3.0) % 1.0
            v = (t / 2.0) % 1.0
            bx = x0 + 2 + (w - 4) * (1 - abs(1 - 2 * u))
            by = y0 + 17 + (h - 21) * (1 - abs(1 - 2 * v))
            put(a, bx, by, c["text"])
            px_ = min(max(bx, x0 + 5), x0 + w - 5)
            hline(a, px_ - 4, px_ + 5, y0 + h - 2, c["text"])
        elif i == 4:  # girders, ladders, barrels rolling down, and someone going up
            self.climb(a, c, x0, y0, w, t)
        else:  # the one that asks
            if t < 3.0:
                text(a, x0 + 8, y0 + 4, "HI SCORE", c["yellow"])
                for r, sc in enumerate(("99990", "87650", "76540", "65430")):
                    text(a, x0 + 2, y0 + 13 + r * 6, "%d AAA %s" % (r + 1, sc), c["text"] if r == 0 else c["textdim"])
            elif t < 13.0:
                text(a, x0 + 6, y0 + 5, "CONTINUE?", c["text"])
                n = 9 - int(t - 3.0)
                if (t - 3.0) % 1.0 < 0.8:
                    text(a, x0 + 19, y0 + 15, str(n), c["yellow"], scale=3)
            elif t < 16.5:
                text(a, x0 + 6, y0 + 17, "GAME OVER", c["red"])
            else:
                if (t * 2) % 2 < 1.2:
                    text(a, x0 + 2, y0 + 15, "INSERT COIN", c["text"])
                text(a, x0 + 8, y0 + h - 7, "CREDIT 0", c["textdim"])
        for yy in range(y0 + 1, y0 + h, 2):  # the tube's lines
            hline(a, x0, x0 + w, yy, c["screen"], 0.3)
        for dx, dy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            put(a, x0 + dx, y0 + dy, c["ink"])

    def climb(self, a, c, x0, y0, w, t):
        red, rail = c["red"], mix(c["red"], c["screen"], 0.5)

        def gy(j, x):  # each girder slopes the other way: the barrels zigzag down
            u = (x - x0) / w
            return y0 + 10 + 9 * j + (2 * u if j % 2 == 0 else 2 * (1 - u))

        spans = ((x0, x0 + w - 6), (x0 + 6, x0 + w), (x0, x0 + w - 6), (x0, x0 + w))
        for lx, j in ((x0 + 30, 0), (x0 + 14, 1), (x0 + 34, 2)):
            ya, yb = gy(j, lx) + 2, gy(j + 1, lx)
            vline(a, lx, ya, yb, c["cyan"])
            vline(a, lx + 2, ya, yb, c["cyan"])
            for yy in range(int(ya) + 1, int(yb), 2):
                put(a, lx + 1, yy, c["cyan"])
        for j, (xa, xb) in enumerate(spans):
            for x in range(xa, xb):
                put(a, x, gy(j, x), red)
                put(a, x, gy(j, x) + 1, red if x % 3 == 0 else rail)
        for k, (bx, by) in enumerate(((x0 + 1, y0 + 6), (x0 + 4, y0 + 6), (x0 + 2, y0 + 3))):
            box(a, bx, by, 3, 3, c["yellow"])
            put(a, bx + 1, by + 1, rail)
        text(a, x0 + w - 12, y0 + 1, "1UP", red)
        barrels = []
        for k in range(3):  # three barrels, two seconds apart, six seconds from top to bottom
            sp = ((t - 2 * k) % 6.0) / 6.0 * 4
            j, f = int(sp), sp - int(sp)
            xa, xb = (x0 + 7, x0 + w - 4) if j % 2 == 0 else (x0 + w - 4, x0 - 3)
            if j == 3:
                xa, xb = x0 + w - 4, x0 - 4
            bx = xa + (xb - xa) * f
            barrels.append((j, bx))
            by = gy(j, bx) - 3
            box(a, bx - 1, by, 3, 3, c["yellow"])
            put(a, bx - 1 + (int(t * 6) % 2) * 2, by + 1, rail)
        u = t % 12.0  # the climber's demo: across, up, back, up, and again
        if u < 4:
            j, hx, hy = 3, x0 + 4 + 30 * u / 4, None
        elif u < 6:
            j, hx = 2, x0 + 34
            hy = gy(3, hx) - 4 + (gy(2, hx) - gy(3, hx)) * (u - 4) / 2
        elif u < 9:
            j, hx, hy = 2, x0 + 34 - 20 * (u - 6) / 3, None
        elif u < 11:
            j, hx = 1, x0 + 14
            hy = gy(2, hx) - 4 + (gy(1, hx) - gy(2, hx)) * (u - 9) / 2
        else:
            j, hx, hy = 1, x0 + 14, None
        if hy is None:
            hy = gy(j, hx) - 4
            if any(bj == j and abs(bx - hx) < 4 for bj, bx in barrels):
                hy -= 3
        if u < 11.5 or int(t * 8) % 2:
            put(a, hx + 1, hy, c["text"])
            hline(a, hx, hx + 3, hy + 1, c["blue"])
            put(a, hx + 1, hy + 2, c["blue"])
            step = int(t * 6) % 2
            put(a, hx + step * 2, hy + 3, c["text"])
            put(a, hx + 2 - step * 2, hy + 3, c["text"])

    def draw(self, a, p, c, t):
        dk = p.dark
        tints = (c["cyan"], c["green"], c["yellow"], c["text"], c["red"])
        for i, x in enumerate(self.CABS):
            k = 0.1
            if i == 3 and 3.0 <= t < 13.0:
                k = 0.14 if (t - 3.0) % 1.0 < 0.8 else 0.08
            pglow(a, x + 32, 104, 46, tints[i], k if dk else k * 0.5, add=dk)
            fill(a, Mask().ell(x + 32, self.FLOOR + 10, 30, 6), tints[i], 0.12 if dk else 0.06)
            self.screen(a, c, i, t)
        # the neon on the back wall; its last letter is not well
        fl = (int(round(t * PFPS)) % (self.seconds * PFPS) % 61) in (7, 8, 30, 33, 34)
        pglow(a, 240, 30, 60, c["neon"], 0.12 if dk else 0.05, add=dk)
        for k, ch in enumerate("GAMES"):
            on = not (k == 4 and fl)
            text(a, 196 + k * 18, 20, ch, c["neon"] if on else c["neondim"], scale=4)
        # the claw, idling
        cx = 30 + 30 * (0.5 + 0.5 * math.sin(2 * math.pi * t / 12))
        vline(a, cx, 82, 92, c["textdim"])
        for dx, dy in ((-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0), (-2, 1), (2, 1), (-2, 2), (2, 2)):
            put(a, cx + dx, 93 + dy, c["text"])
        pglow(a, 45, 110, 34, c["neon"], 0.1 if dk else 0.04, add=dk)


# -- crossing ---------------------------------------------------------------------

CROW = (
    "..kk.....",
    "kkkkk....",
    "..kkkkkk.",
    "...kkkkkk",
    "...k.k...",
)


class Crossing(Pixel):
    """A level crossing at dusk, far off, and a lit vending machine. The bells
    ring, the arm comes down, a small train goes by; after it the crows on the
    wire are in another order."""

    name = "crossing"
    poster = 12.0
    RAIL = 200
    CROWS = (130, 190, 250, 310)
    SX = 334

    def colors(self, p):
        st = self.__dict__.setdefault("_c", {})
        k = self.key(p)
        if k in st:
            return st[k]
        bg, dk = p("bg"), p.dark
        if dk:
            c = dict(top=mix(bg, p("ansi_5"), 0.12), mid=mix(bg, p("ansi_1"), 0.22), low=mix(p("ansi_3"), bg, 0.5),
                     sun=mix(p("ansi_3"), WHITE3, 0.4), cloud=mix(bg, p("ansi_5"), 0.25), cloudlit=mix(p("ansi_3"), mix(bg, p("ansi_5"), 0.25), 0.45),
                     ink=mix(bg, BLACK3, 0.8), ink2=mix(bg, BLACK3, 0.58), ground=mix(bg, BLACK3, 0.55), field=mix(mix(bg, BLACK3, 0.55), p("ansi_2"), 0.12),
                     road=mix(bg, BLACK3, 0.45), red=p("ansi_1"), vend=p.pick("fg+accent:20", "white"), vend2=p("accent"), vend3=p("ansi_1"),
                     train=mix(bg, BLACK3, 0.66), trainroof=mix(bg, BLACK3, 0.5), window=p("ansi_3"), haze=p("ansi_3"), lamp=p("fg"))
        else:
            c = dict(top=p("bg+ansi_5:12"), mid=p("bg+ansi_3:22"), low=p("ansi_3+white:55"),
                     sun=mix(p("ansi_3"), WHITE3, 0.5), cloud=p("bg+ansi_5:22"), cloudlit=p("bg+white:60"),
                     ink=p("bg+fg:72"), ink2=p("bg+fg:52"), ground=p("bg+fg:30"), field=p("bg+ansi_2:30"), road=p("bg+fg:22"),
                     red=p("ansi_1"), vend=p("white"), vend2=p("accent"), vend3=p("ansi_1"),
                     train=p("bg+fg:50"), trainroof=p("bg+fg:36"), window=p("ansi_3+white:30"), haze=p("ansi_3"), lamp=p("white"))
        st[k] = c
        return c

    def extra(self, p, c):
        return (ramp(c["top"], c["mid"], 4) + ramp(c["mid"], c["low"], 4) + ramp(c["low"], c["sun"], 4)[1:-1] + ramp(c["ground"], c["red"], 4)[1:-1]
                + ramp(c["ground"], c["vend"], 4)[1:-1] + [mix(c["mid"], c["red"], 0.5), mix(c["low"], c["red"], 0.5), mix(c["train"], c["window"], 0.5)])

    WIRES = ((33, 22), (33, 31), (43, 26))  # where each wire leaves the crossarm, and how far it sags

    def wire(self, x, k):
        """A wire from pole to pole: it hangs, lowest halfway between them."""
        top, sag = self.WIRES[k]
        u = (x - 240) / 204
        return top + sag * (1 - u * u)

    def back(self, a, p, c):
        dk = p.dark
        pgrad(a, 0, self.RAIL, [(0, c["top"]), (105, c["mid"]), (self.RAIL, c["low"])])
        pglow(a, 345, 168, 60, c["sun"], 0.35 if dk else 0.45, add=False)
        fill(a, Mask().ell(345, 168, 11, 11), c["sun"])
        clouds(a, 21, 6, (30, 140), c["cloud"], c["cloudlit"], 0.95, lit_below=True, wmin=60, wmax=180)
        rnd = random.Random(33)  # the roofs of the town beyond the line
        x = -6
        m, lit = Mask(), []
        while x < PW:
            w, h = rnd.randint(14, 28), rnd.randint(5, 10)
            top = 186 - rnd.randint(0, 8)
            m.poly([(x, top + h // 2), (x + w // 2, top), (x + w, top + h // 2), (x + w, self.RAIL), (x, self.RAIL)])
            if rnd.random() < 0.5:
                lit.append((x + rnd.randint(3, max(4, w - 4)), top + h // 2 + 3))
            x += w + rnd.randint(0, 3)
        m.rect(150, 168, 3, 20).rect(146, 166, 11, 3)
        fill(a, m, c["ink2"])
        for lx, ly in lit:
            box(a, lx, ly, 2, 2, c["window"], 0.9 if dk else 0.5)
        box(a, 0, self.RAIL, PW, PH - self.RAIL, c["field"])
        rnd = random.Random(2)
        for i in range(300):
            x, y = rnd.randrange(PW), rnd.randrange(self.RAIL + 8, PH)
            put(a, x, y, c["ground"])
        box(a, 0, self.RAIL, PW, 7, c["ground"])
        for x in range(0, PW, 4):
            box(a, x, self.RAIL + 2, 2, 4, c["ink2"])
        hline(a, 0, PW, self.RAIL + 2, c["ink"])
        hline(a, 0, PW, self.RAIL + 5, c["ink"])
        fill(a, Mask().poly([(self.SX - 10, self.RAIL + 7), (self.SX + 6, self.RAIL + 7), (self.SX + 70, PH), (self.SX - 92, PH)]), c["road"])
        fill(a, Mask().rect(self.SX - 12, self.RAIL, 20, 7), c["road"])
        hline(a, self.SX - 12, self.SX + 8, self.RAIL + 2, c["ink"])
        hline(a, self.SX - 12, self.SX + 8, self.RAIL + 5, c["ink"])
        # the poles and wires, near, framing it
        for x in (36, 444):
            box(a, x - 2, 14, 5, PH - 14, c["ink"])
            box(a, x - 14, 32, 29, 3, c["ink"])
            box(a, x - 9, 42, 19, 2, c["ink"])
        for k in range(3):
            for x in range(36, 445):
                put(a, x, self.wire(x, k), c["ink"])

    def front(self, a, c, dk):
        x, y = 70, 196  # the vending machine, on our side of the line
        box(a, x, y, 18, 34, c["ink"])
        box(a, x + 2, y + 2, 14, 18, c["vend"], 0.95)
        for i in range(3):
            for j in range(3):
                box(a, x + 3 + i * 4, y + 3 + j * 6, 3, 4, (c["vend2"], c["vend3"], c["vend2"])[(i + j) % 3])
        box(a, x + 3, y + 23, 12, 3, c["ink2"])
        box(a, x + 13, y + 22, 2, 2, c["red"])
        pglow(a, x + 9, y + 12, 30, c["vend"], 0.22 if dk else 0.05, add=dk)
        fill(a, Mask().ell(x + 9, y + 36, 18, 4), c["vend"], 0.15 if dk else 0.05)

    def sign(self, a, c, t, active, dk):
        x, y = self.SX, self.RAIL + 6
        vline(a, x, y - 30, y, c["ink"])
        for k in range(-3, 4):
            put(a, x + k, y - 31 + k, c["ink"])
            put(a, x + k, y - 31 - k, c["ink"])
        hline(a, x - 5, x + 6, y - 23, c["ink"])
        on = int(t * 2.4) % 2 if active else -1
        for k, lx in enumerate((x - 4, x + 3)):
            lit = active and on == k
            box(a, lx, y - 22, 2, 2, c["red"] if lit else c["ink2"])
            if lit:
                pglow(a, lx + 1, y - 21, 10, c["red"], 0.45, add=dk)
        down = ease_io(window(t, 8.6, 9.8)) * (1 - ease_io(window(t, 15.0, 16.2)))
        ang = -1.45 * (1 - down)
        ax, ay = x - 3, y - 10
        L = 44
        for d in range(L):
            px_ = ax - d * math.cos(ang)
            py_ = ay + d * math.sin(ang)
            put(a, px_, py_, c["red"] if (d // 3) % 2 and d > 3 else c["lamp"] if dk else c["ink"])

    def draw(self, a, p, c, t):
        dk = p.dark
        active = 8.0 <= t < 16.0
        u = window(t, 10.6, 14.6)
        if 0 < u < 1:  # the train, small and far, right to left
            x0 = PW + 10 - (PW + 380) * u
            for car in range(5):
                cx = x0 + car * 70
                box(a, cx, self.RAIL - 14, 68, 15, c["train"])
                hline(a, cx + 1, cx + 67, self.RAIL - 15, c["trainroof"])
                for k in range(11):
                    box(a, cx + 4 + k * 6, self.RAIL - 11, 3, 4, c["window"], 0.9 if dk else 0.6)
                hline(a, cx, cx + 68, self.RAIL - 5, c["ink"])
            put(a, x0 + 1, self.RAIL - 4, c["lamp"])
            pglow(a, x0 + 1, self.RAIL - 4, 8, c["lamp"], 0.4, add=dk)
        self.sign(a, c, t, active, dk)
        self.front(a, c, dk)
        after = 12.6 <= t < 23.0
        order = (2, 0, 3, 1) if after else (0, 1, 2, 3)
        settle = ease_io(window(t, 22.0, 23.0))
        for slot, k in enumerate(order):
            x = self.CROWS[slot]
            if 22.0 <= t < 23.0:
                x0b = self.CROWS[(2, 0, 3, 1).index(k)]
                x = x0b + (self.CROWS[k] - x0b) * settle
            y = self.wire(x, 0)
            bob = 1 if wave(t, 2.4, k * 0.31) > 0.6 else 0
            kx = 1 if k % 2 else -1
            sprite(a, int(x) - 4, int(y) - 5 - bob, CROW, {"k": c["ink"]}, kx)
        rnd = random.Random(71)
        for i in range(36):  # dust in the low sun
            x0, y0 = rnd.uniform(200, 470), rnd.uniform(95, 200)
            x = x0 + 10 * wave(t, 24 / rnd.choice((1, 2, 3)), rnd.random())
            y = y0 + 5 * wave(t, 24 / rnd.choice((2, 3, 4)), rnd.random())
            if wave(t, 24 / rnd.choice((4, 6)), rnd.random()) > 0:
                put(a, x, y, c["haze"], 0.7)


SCENES_NIGHT = (Garoa(), Horizon(), Watch(), Problem(), Continue(), Crossing())


# the collections: a look and feel for each persona, the scenes in it
COLLECTIONS = {
    "cozy": ("onsen", "duck", "reef", "campfire", "ufo", "pigeons"),  # warm, playful, a picture book for grown-ups
    "night": ("garoa", "horizon", "watch", "problem", "continue", "crossing"),  # the night shift: pixel art, the references and not the story
}
SCENES = {s.name: s for s in (Onsen(), Duck(), Reef(), Campfire(), Ufo(), Pigeons()) + SCENES_NIGHT}


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


def upscale(q, w, h):
    """A pixel scene's grid at a size: every pixel a square of them, the whole
    grid covering the size and centered (so a 16 by 9 size shows all of it)."""
    img = np.clip(np.rint(q), 0, 255).astype(np.uint8)
    gh, gw = img.shape[:2]
    if (w, h) == (gw, gh):
        return img
    k = max(w / gw, h / gh)
    if k == int(k) and gw * k == w and gh * k == h:
        k = int(k)
        return np.repeat(np.repeat(img, k, 0), k, 1)
    cols = np.clip(((np.arange(w) + 0.5 + (gw * k - w) / 2) / k).astype(np.int64), 0, gw - 1)
    rows = np.clip(((np.arange(h) + 0.5 + (gh * k - h) / 2) / k).astype(np.int64), 0, gh - 1)
    return img[rows][:, cols]


def drawable(scene, w, h):
    """Why a scene cannot be drawn at w by h, or None when it can."""
    if not (16 <= w <= 8192 and 16 <= h <= 8192):
        return "%dx%d is not a size to draw at (16 to 8192 a side)" % (w, h)
    if h > w and not scene.portrait:
        return "%s has no portrait composition yet" % scene.name
    return None


def canvas_for(scene, w, h):
    """A flat scene's canvas for a screen w by h, its view for that shape covering
    it; and where the screen's corner falls on it."""
    uw, uh, ox, oy = scene.view(h > w)
    s = max(w / uw, h / uh)
    while round(uw * s) < w or round(uh * s) < h:
        s += 0.5 / uw
    cv = Canvas(s, uw, uh, ox, oy)
    return cv, (cv.w - w) // 2, (cv.h - h) // 2


def frames_at(scene, p, w, h, fps):
    """The loop once, w by h, fps frames a second: a pixel scene steps on its own
    grid's beat and is scaled up with square pixels; a flat one is drawn at the
    size, its 16 by 9 picture covering a wider or taller landscape, centered."""
    n = round(scene.seconds * fps)
    if getattr(scene, "pixel", False):
        last = (None, None)
        for f in range(n):
            k = f * PFPS // fps
            if last[0] != k:
                last = (k, upscale(scene.render(p, k / PFPS, h > w), w, h))
            yield last[1]
        return
    cv, x0, y0 = canvas_for(scene, w, h)
    back, front = stills(cv, scene, p)
    for f in range(n):
        yield frame(cv, scene, p, back, front, f / fps)[y0 : y0 + h, x0 : x0 + w]


def still_at(scene, p, w, h, t):
    """One frame of a scene at a time of its loop, w by h."""
    if getattr(scene, "pixel", False):
        return upscale(scene.render(p, t, h > w), w, h)
    cv, x0, y0 = canvas_for(scene, w, h)
    back, front = stills(cv, scene, p)
    return frame(cv, scene, p, back, front, t)[y0 : y0 + h, x0 : x0 + w]


_JOB = {}


def _job_init(name, path, w, h, fps):
    """A worker of --jobs: the scene, its palette and its still part, once."""
    warnings.simplefilter("ignore")
    np.seterr(all="ignore")
    sc = SCENES[name]
    p = Palette(read_env(path))
    _JOB.update(sc=sc, p=p, w=w, h=h, fps=fps)
    if not getattr(sc, "pixel", False):
        cv, x0, y0 = canvas_for(sc, w, h)
        back, front = stills(cv, sc, p)
        _JOB.update(cv=cv, back=back, front=front, x0=x0, y0=y0)


def _job_frame(i):
    """Frame i of the loop as bytes (for a pixel scene, step i of its grid)."""
    j = _JOB
    if getattr(j["sc"], "pixel", False):
        return upscale(j["sc"].render(j["p"], i / PFPS, j["h"] > j["w"]), j["w"], j["h"]).tobytes()
    img = frame(j["cv"], j["sc"], j["p"], j["back"], j["front"], i / j["fps"])
    return img[j["y0"] : j["y0"] + j["h"], j["x0"] : j["x0"] + j["w"]].tobytes()


def frame_bytes(name, path, p, w, h, fps, jobs):
    """The loop's frames as bytes, in order, drawn by jobs processes."""
    sc = SCENES[name]
    n = sc.seconds * fps
    if jobs <= 1:
        for img in frames_at(sc, p, w, h, fps):
            yield img.tobytes()
        return
    with Pool(jobs, initializer=_job_init, initargs=(name, path, w, h, fps)) as pool:
        if getattr(sc, "pixel", False):
            steps = [f * PFPS // fps for f in range(n)]
            uniq = sorted(set(steps))
            it = pool.imap(_job_frame, uniq, chunksize=4)
            reps = {}  # each grid step, as many times as the frame rate repeats it
            for k in steps:
                reps[k] = reps.get(k, 0) + 1
            for k, data in zip(uniq, it):
                for _ in range(reps[k]):
                    yield data
        else:
            for data in pool.imap(_job_frame, range(n), chunksize=4):
                yield data


def write_png(path, img):
    """An RGB picture as a PNG, with zlib alone."""
    h, w = img.shape[:2]
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def info(scene, portrait=False):
    out = {"scene": scene.name, "collection": next(c for c, ns in COLLECTIONS.items() if scene.name in ns),
           "fps": native_fps(scene), "seconds": scene.seconds, "frames": scene.seconds * native_fps(scene), "still": scene.poster,
           "kind": "pixel" if getattr(scene, "pixel", False) else "flat", "orientations": ["landscape"] + (["portrait"] if scene.portrait else [])}
    if getattr(scene, "pixel", False):
        out["grid"] = "%dx%d" % ((PH, PW) if portrait else (PW, PH))
        if scene.portrait and not portrait:
            out["portrait_grid"] = "%dx%d" % (PH, PW)
    return out


def native_fps(scene):
    return PFPS if getattr(scene, "pixel", False) else FPS


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
    scene_name, path, out_dir, size, preset = job
    scene = SCENES[scene_name]
    name = os.path.basename(path)[: -len(".env")] if path.endswith(".env") else os.path.basename(path)
    p = Palette(read_env(path))
    d = os.path.join(out_dir, scene.name)
    os.makedirs(d, exist_ok=True)
    encode(os.path.join(d, name + ".mp4"), size[0], size[1], frames_at(scene, p, size[0], size[1], FPS), preset)
    return "%s/%s" % (scene.name, name)


def refuse(msg, code=1):
    """One line on stderr and out: what the frames' reader is told when it cannot have them."""
    sys.stderr.write("make.py: %s\n" % msg)
    sys.exit(code)


def palette_of(path):
    try:
        env = read_env(path)
    except (OSError, UnicodeDecodeError, ValueError) as e:
        refuse("cannot read the palette %s (%s)" % (path, e.__class__.__name__))
    if not any(k.startswith("THEME_") for k in env):
        refuse("%s is not a palette: it has no THEME_ lines" % path)
    return Palette(env)


def main(argv):
    out_dir, paths, scenes, size, at, png, preset = HERE, [], [], None, None, None, "slow"
    raw, want_info, fps, jobs = False, False, None, 1
    it = iter(argv)
    try:
        for a in it:
            if a == "--out":
                out_dir = next(it)
            elif a == "--scene":
                scenes.append(next(it))
            elif a == "--size":
                v = next(it).lower().split("x")
                if len(v) != 2 or not all(x.isdigit() for x in v):
                    refuse("the size is WxH, as 1920x1080 is", 2)
                size = (int(v[0]), int(v[1]))
            elif a == "--still":
                at = next(it)
            elif a == "--png":
                png = next(it)
            elif a == "--preset":
                preset = next(it)
            elif a == "--raw":
                raw = True
            elif a == "--info":
                want_info = True
            elif a == "--jobs":
                v = next(it)
                if not v.isdigit() or not 1 <= int(v) <= 64:
                    refuse("the jobs are a whole number, 1 to 64", 2)
                jobs = int(v)
            elif a == "--fps":
                v = next(it)
                if not v.isdigit() or not 1 <= int(v) <= 120:
                    refuse("the fps is a whole number, 1 to 120", 2)
                fps = int(v)
            elif a == "--collection":
                c = next(it)
                if c not in COLLECTIONS:
                    refuse("no collection %s: %s" % (c, " ".join(COLLECTIONS)), 2)
                scenes += list(COLLECTIONS[c])
            elif a.startswith("--"):
                refuse("no option %s" % a, 2)
            else:
                paths.append(a)
    except StopIteration:
        refuse("%s wants a value" % a, 2)
    for n in scenes:
        if n not in SCENES:
            refuse("no scene %s: %s" % (n, " ".join(SCENES)), 2)
    if raw or want_info or at is not None:  # what spark-shell reads: nothing else on stderr
        warnings.simplefilter("ignore")
        np.seterr(all="ignore")
    if want_info:
        if not scenes:
            print(json.dumps({"collections": {c: list(ns) for c, ns in COLLECTIONS.items()}, "scenes": [info(SCENES[n]) for ns in COLLECTIONS.values() for n in ns]}))
            return 0
        if len(scenes) != 1:
            refuse("--info takes one --scene, or none for all of them", 2)
        sc = SCENES[scenes[0]]
        out = info(sc, bool(size and size[1] > size[0]))
        if size:
            why = drawable(sc, *size)
            if why:
                refuse(why)
            out["size"] = "%dx%d" % size
        if fps:
            if (sc.seconds * fps) != int(sc.seconds * fps):
                refuse("%d frames a second do not make a whole loop of %s" % (fps, sc.name))
            out["fps"], out["frames"] = fps, sc.seconds * fps
        print(json.dumps(out))
        return 0
    if raw:
        if len(scenes) != 1 or len(paths) != 1 or not size:
            refuse("--raw takes one --scene, one --size WxH and one palette file", 2)
        sc = SCENES[scenes[0]]
        why = drawable(sc, *size)
        if why:
            refuse(why)
        p = palette_of(paths[0])
        fps = fps or native_fps(sc)
        n, out = sc.seconds * fps, sys.stdout.buffer
        done = 0
        try:
            for data in frame_bytes(sc.name, paths[0], p, size[0], size[1], fps, jobs):
                out.write(data)
                done += 1
            out.flush()
        except BrokenPipeError:
            sys.stderr.write("make.py: the reader went away after %d of %d frames\n" % (done, n))
            os._exit(1)
        except Exception as e:  # noqa: BLE001 -- one line, whatever it was
            refuse("%s stopped after %d of %d frames: %s" % (sc.name, done, n, e))
        return 0
    size = size or (W, H)
    if not paths:
        d = os.path.join(REPO, "themes")
        paths = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".env"))
    if at is not None:  # stills: the list's picture, and the layer under the loop
        names = scenes or list(SCENES)
        one = png and png.endswith(".png")
        if not png or (one and (len(names) != 1 or len(paths) != 1 or "," in at)):
            refuse("--still takes --png DIR, or --png FILE.png for one scene, one palette and one time", 2)
        for name in names:
            sc = SCENES[name]
            why = drawable(sc, *size)
            if why:
                refuse(why)
            for path in paths:
                p = palette_of(path)
                for v in at.split(","):
                    try:
                        t = sc.poster if v == "poster" else float(v)
                    except ValueError:
                        refuse("--still takes times in seconds, or poster", 2)
                    if one:
                        out = png
                    else:
                        os.makedirs(png, exist_ok=True)
                        out = os.path.join(png, "%s-%s-%05.2f.png" % (name, os.path.basename(path)[:-4], t))
                    write_png(out, still_at(sc, p, size[0], size[1], t))
                    if not one:
                        print(out)
        return 0
    for n in scenes or list(SCENES):
        why = drawable(SCENES[n], *size)
        if why:
            refuse(why)
    jobs = [(n, path, out_dir, size, preset) for n in (scenes or list(SCENES)) for path in paths]
    with Pool() as pool:
        try:
            for done in pool.imap_unordered(make, jobs):
                print(done)
        except RuntimeError as e:
            sys.exit(str(e))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
