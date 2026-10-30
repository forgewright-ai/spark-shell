#!/usr/bin/env python3
"""Six small pieces for the home dialog's transitions, each drawn in a
palette's own colors on nothing, each as open, wait and close GIFs.

    python3 assets/transitions/make.py [--piece NAME ...] [PALETTE.env ...] [--out DIR]

    moon    a crescent waxes to a full moon in its halo; the halo breathes and
            the stars around it catch the light in turn; the moon wanes away
    ripple  a drop falls into still water and rings keep spreading from it; at
            the close the rings gather back and the drop lifts away
    tide    a line opens from the centre and swells into three threads that
            sway against each other; they settle into the line and it closes
    embers  a low line glows and embers lift off it, yellow to red, going dark
            as they climb; the line cools from its ends (square pixels, at half
            the others' frame rate, a stop-motion)
    sun     the horizon draws out and a striped sun rises behind it, its
            stripes drifting down, its light trembling on the water; it sets
    flight  a paper plane glides in, draws a slow figure of eight with a dotted
            trail, and at the close flies off the top left

Each palette (by default every themes/*.env) gets DIR/PIECE/NAME/ (by default
assets/transitions/PIECE/NAME/): open.gif plays once (about 1.2 s) and hands
over to wait.gif, which loops; close.gif plays once (about 1 s) and ends on
nothing; each also @2x. 180 by 120 at 1x.

A GIF pixel is drawn or not, never half. So every edge and every fade is
mixed toward the dialog's surface, PANEL_BG (spark-shell's panel_load: the
palette's ground 9% of the way to its text), the ground the GIFs are drawn
on, and what is barely there is left undrawn. The colors are the palette's:
its text, accent, muted (PANEL_MUTED, as panel_load lifts it) and ANSI
colors, a few to a piece.
"""

import math
import os
import random
import re
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
W, H = 180, 120
SCALES = (1, 2)
INK_MIN = 1 / 48  # a pixel inked less than this is left undrawn
# foot's defaults, as spark-shell's FOOT_HEX: a palette's missing ANSI color
FOOT_HEX = "242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff".split()
WHITE, BLACK = (255.0, 255.0, 255.0), (0.0, 0.0, 0.0)


# -- the palette --------------------------------------------------------------


def rgb(h):
    return tuple(float(int(h[i : i + 2], 16)) for i in (0, 2, 4))


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
        d = int(y - x) * pct
        out.append(int(x) + (abs(d) // 100) * (1 if d >= 0 else -1))
    return "%02x%02x%02x" % tuple(out)


def hex_contrast(a, b):
    """spark-shell's hex_contrast: the WCAG contrast of the two, times 100."""

    def lum(h):
        ch = [v / 255 for v in rgb(h)]
        ch = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in ch]
        return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]

    x, y = sorted((lum(a), lum(b)), reverse=True)
    return int((x + 0.05) / (y + 0.05) * 100)


def mix(a, b, k):
    """a moved k (0 to 1) of the way to b."""
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


class Roles:
    """A palette as the pieces take it: spark-shell's own keys, worked out the way it does."""

    def __init__(self, env):
        get = lambda k, d: hex_or(env.get(k, ""), d)
        ansi = [get("THEME_ANSI_%d" % i, FOOT_HEX[i]) for i in range(16)]
        bg, fg = get("THEME_BG", "242424"), get("THEME_FG", "ffffff")
        muted = get("THEME_MUTED", ansi[8])
        surface = hex_mix(bg, fg, 9)
        pl = 35
        m = hex_mix(muted, fg, pl)
        while pl < 100 and hex_contrast(m, surface) < 450:
            pl += 5
            m = hex_mix(muted, fg, pl)
        self.surface = rgb(surface)
        self.dark = (299 * self.surface[0] + 587 * self.surface[1] + 114 * self.surface[2]) / 1000 < 128
        self.fg, self.muted = rgb(fg), rgb(m)
        self.accent = rgb(get("THEME_ACCENT", ansi[4]))
        self.ansi = [rgb(a) for a in ansi]
        # a warm yellow that reads on the ground: on dark the palette's yellow lifted a little
        self.yellow = mix(self.ansi[3], WHITE, 0.25) if self.dark else self.ansi[3]


# -- drawing: coverage in the drawing's units, mixed onto the surface ------------


class Canvas:
    def __init__(self, s):
        self.s, self.w, self.h = s, W * s, H * s
        self.xs = ((np.arange(self.w) + 0.5) / s).astype(np.float32)
        self.ys = ((np.arange(self.h) + 0.5) / s).astype(np.float32)

    def cov(self, d):
        """A shape's signed distance as coverage: one pixel of soft edge."""
        return np.clip(0.5 - d * self.s, 0.0, 1.0)

    def area(self, x0, y0, x1, y1):
        """The pixels over a box in units: their rows, columns, and centres as a column and a row."""
        px0, px1 = max(0, math.floor(x0 * self.s)), min(self.w, math.ceil(x1 * self.s))
        py0, py1 = max(0, math.floor(y0 * self.s)), min(self.h, math.ceil(y1 * self.s))
        if px1 <= px0 or py1 <= py0:
            return None
        return slice(py0, py1), slice(px0, px1), self.xs[px0:px1][None, :], self.ys[py0:py1][:, None]


class Layer:
    """A shape's coverage over its pixels, its color (one, or one a row) and how strong."""

    __slots__ = ("cov", "rows", "cols", "color", "alpha")

    def __init__(self, shape, color, alpha=1.0):
        self.cov, self.rows, self.cols = shape if shape else (None, None, None)
        self.color, self.alpha = color, alpha


def disc(c, cx, cy, r):
    a = c.area(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
    if a is None or r <= 0:
        return None
    rows, cols, X, Y = a
    return c.cov(np.hypot(X - cx, Y - cy) - r), rows, cols


def ring(c, cx, cy, r, w):
    a = c.area(cx - r - w - 1, cy - r - w - 1, cx + r + w + 1, cy + r + w + 1)
    if a is None:
        return None
    rows, cols, X, Y = a
    return c.cov(np.abs(np.hypot(X - cx, Y - cy) - r) - w / 2), rows, cols


def capsule(c, ax, ay, bx, by, r):
    a = c.area(min(ax, bx) - r - 1, min(ay, by) - r - 1, max(ax, bx) + r + 1, max(ay, by) + r + 1)
    if a is None:
        return None
    rows, cols, X, Y = a
    dx, dy = bx - ax, by - ay
    t = np.clip(((X - ax) * dx + (Y - ay) * dy) / max(dx * dx + dy * dy, 1e-9), 0, 1)
    return c.cov(np.hypot(X - ax - t * dx, Y - ay - t * dy) - r), rows, cols


def block(c, x, y, w, h):
    """A box with hard edges: a pixel is in it or not."""
    a = c.area(x, y, x + w, y + h)
    if a is None:
        return None
    rows, cols, X, Y = a
    return ((X >= x) & (X < x + w) & (Y >= y) & (Y < y + h)).astype(np.float32), rows, cols


def polygon(c, pts, ss=4):
    """A polygon's coverage, drawn at ss times and averaged down."""
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    a = c.area(min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1)
    if a is None:
        return None
    rows, cols, _, _ = a
    w, h = cols.stop - cols.start, rows.stop - rows.start
    im = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(im).polygon([((x * c.s - cols.start) * ss, (y * c.s - rows.start) * ss) for x, y in pts], fill=255)
    cov = np.asarray(im, np.float32).reshape(h, ss, w, ss).mean(axis=(1, 3)) / 255
    return cov, rows, cols


def render(c, ro, layers):
    """One frame: the layers mixed onto the surface in order; the pixels inked enough to draw."""
    img = np.empty((c.h, c.w, 3), np.float32)
    img[:] = ro.surface
    ink = np.zeros((c.h, c.w), np.float32)
    for ly in layers:
        if ly.cov is None or ly.alpha <= 0:
            continue
        a = ly.cov * np.float32(min(1.0, ly.alpha))
        col = np.asarray(ly.color, np.float32)
        sub = img[ly.rows, ly.cols]
        sub += (col - sub) * a[..., None]
        ink[ly.rows, ly.cols] += a * (1 - ink[ly.rows, ly.cols])
    return np.rint(img).astype(np.uint8), ink >= INK_MIN


# -- easing ---------------------------------------------------------------------


def clamp(u):
    return 0.0 if u < 0 else 1.0 if u > 1 else u


def ease_out(u):
    return 1 - (1 - clamp(u)) ** 3


def ease_in(u):
    return clamp(u) ** 3


def ease_io(u):
    u = clamp(u)
    return 4 * u**3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


def bump(u):
    return math.sin(math.pi * u) if 0 < u < 1 else 0.0


# -- the pieces -----------------------------------------------------------------


class Moon:
    name, ms, frames = "moon", 40, {"open": 30, "wait": 60, "close": 20}
    CX, CY, R = 90.0, 60.0, 17.0
    HALO = ((36.0, 0.08, 2.4), (26.0, 0.16, 1.2))  # radius, strength, how far it breathes
    STARS = ((38, 28, 4), (143, 22, 18), (152, 92, 31), (27, 95, 44))  # x, y, the frame its light rises from

    def draw(self, c, ro, anim, f):
        cx, cy, r = self.CX, self.CY, self.R
        far, breath = 2 * r + 2, 0.0
        if anim == "open":  # the shadow slides off to the left: a crescent lit on the right
            g, sx = ease_out((f - 4) / 24), cx - far * ease_io(f / 26)
        elif anim == "wait":
            g, sx, breath = 1.0, None, math.sin(2 * math.pi * f / 60)
        else:  # it comes back from the right
            g, sx = 1 - ease_in(f / 18), cx + far * (1 - ease_io(f / 18))
        out = []
        # on dark a pale moon, the text's color; on light a pastel one, as the light wallpapers draw theirs
        moon, soft = (mix(ro.fg, ro.accent, 0.15), 1.0) if ro.dark else (mix(ro.accent, ro.surface, 0.5), 0.7)
        for hr, a, amp in self.HALO:
            if g > 0:
                out.append(Layer(disc(c, cx, cy, r + (hr - r) * g + amp * breath), ro.accent, soft * a * g * (1 + 0.15 * breath)))
        if sx is None:
            out.append(Layer(disc(c, cx, cy, r), moon))
        else:
            a = c.area(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
            rows, cols, X, Y = a
            lit = c.cov(np.hypot(X - cx, Y - cy) - r) * (1 - c.cov(np.hypot(X - sx, Y - cy) - (r + 1)))
            out.append(Layer((lit, rows, cols), moon))
        if anim == "wait":
            for x, y, t0 in self.STARS:
                b = bump((f - t0) / 14)
                if b > 0:
                    arm = 1 + 3.5 * b
                    out.append(Layer(capsule(c, x - arm, y, x + arm, y, 0.3), ro.fg, 0.55 * b))
                    out.append(Layer(capsule(c, x, y - arm, x, y + arm, 0.3), ro.fg, 0.55 * b))
                    out.append(Layer(disc(c, x, y, 0.5 + 0.6 * b), ro.fg, 0.9 * b))
        return out


class Ripple:
    name, ms, frames = "ripple", 40, {"open": 30, "wait": 60, "close": 24}
    CX, CY, RMAX, LIFE = 90.0, 66.0, 46.0, 40
    BIRTHS = ((0, 0.8), (20, 0.65), (40, 1.0))  # the frame of the loop a ring is born, how strong
    TOP = 6.0

    def rings(self, c, col, age, k, out):
        u = age / self.LIFE
        if not 0 <= u < 1:
            return
        r = 1.5 + (self.RMAX - 1.5) * (1 - (1 - u) ** 2)
        a = k * (1 - u) ** 1.5
        out.append(Layer(ring(c, self.CX, self.CY, r, 1.6 - 0.8 * u), col, a))
        if u > 0.15:  # the crest behind it
            v = ease_out((u - 0.15) / 0.5)
            out.append(Layer(ring(c, self.CX, self.CY, max(0.5, r - 7 * v), 1.1 - 0.5 * u), col, a * 0.45 * v))

    def draw(self, c, ro, anim, f):
        col, out, cx, cy = ro.ansi[6], [], self.CX, self.CY
        if anim == "open":
            if f < 10:  # it falls, faster and longer as it goes
                u = f / 10
                y = self.TOP + (cy - self.TOP) * u * u
                out.append(Layer(capsule(c, cx, y - 1 - 6 * u, cx, y, 1.5), col, ease_out((f + 1) / 3)))
            else:
                self.rings(c, col, f - 10, 1.0, out)
                t = (f - 10) / 7
                if t < 1:  # two droplets thrown up
                    for side in (-1, 1):
                        out.append(Layer(disc(c, cx + side * (4 + 7 * t), cy - 36 * t * (1 - t), 0.9), col, 0.85 * (1 - t * t)))
        elif anim == "wait":
            for b, k in self.BIRTHS:
                self.rings(c, col, (f - b) % 60, k, out)
        else:
            for s in (0, 5):  # rings come in from the edge, quicker as they near the centre
                v = (f - s) / 13
                if 0 <= v < 1:
                    out.append(Layer(ring(c, cx, cy, 2 + 44 * (1 - v**1.6), 0.9 + 0.7 * v), col, 0.85 * clamp(v * 2)))
            t = (f - 17) / 6
            if 0 <= t < 1:  # the drop lifts away, slowing, its tail below
                y = cy - (cy - self.TOP) * (1 - (1 - t) ** 2)
                out.append(Layer(capsule(c, cx, y, cx, y + 1 + 6 * (1 - t), 1.5), col, 1 - t * t))
        return out


class Tide:
    name, ms, frames = "tide", 40, {"open": 30, "wait": 72, "close": 23}
    CX, CY, E, L = 90.0, 60.0, 76.0, 72
    THREADS = (  # amplitude, wavelength, turns a loop, phase, half width, which color
        (6.0, 54.0, 2, 1.3, 0.55, "back"),
        (11.0, 78.0, -1, 2.4, 0.75, "mid"),
        (15.0, 104.0, 1, 0.0, 1.0, "front"),
    )

    def thread(self, c, e, amp, lam, ph, hw0):
        cx, cy = self.CX, self.CY
        a = c.area(cx - e, cy - amp - hw0 - 2, cx + e, cy + amp + hw0 + 2)
        if a is None or e <= 0:
            return None
        rows, cols, X, Y = a
        u = np.clip((X - (cx - e)) / (2 * e), 0, 1)
        win = np.maximum(np.sin(np.pi * u), 0)
        dwin = np.pi / (2 * e) * np.cos(np.pi * u)
        th = 2 * np.pi * X / lam + ph
        y = cy + amp * win * np.sin(th)
        slope = amp * (dwin * np.sin(th) + win * np.cos(th) * 2 * np.pi / lam)
        hw = hw0 * win**0.6
        d = np.abs(Y - y) / np.sqrt(1 + slope**2)
        return np.clip(hw * c.s + 0.5 - d * c.s, 0, 1) * np.clip(2 * hw * c.s, 0, 1), rows, cols

    def draw(self, c, ro, anim, f):
        if anim == "open":
            e, amp, tau = (self.E * ease_out((f - 2) / 16) if f >= 2 else 0.0), ease_io((f - 8) / 21), f - 30
            dot = (0.5, 1.0, 1.0, 0.5)[f] if f < 4 else 0.0
        elif anim == "wait":
            e, amp, tau, dot = self.E, 1.0, f, 0.0
        else:
            e, amp, tau = self.E * (1 - ease_io((f - 8) / 12)), 1 - ease_io(f / 12), f
            dot = (1.0, 0.66, 0.33, 0.0)[f - 19] if f >= 19 else 0.0
        colors = {"back": ro.muted, "mid": mix(ro.accent, ro.fg, 0.45), "front": ro.accent}
        out = []
        if e > 0:
            for A, lam, turns, ph, hw0, role in self.THREADS:
                phase = ph - 2 * math.pi * turns * tau / self.L
                out.append(Layer(self.thread(c, e, A * amp, lam, phase, hw0), colors[role]))
        if dot > 0:
            out.append(Layer(disc(c, self.CX, self.CY, 1.3), ro.accent, dot))
        return out


class Embers:
    name, ms, frames = "embers", 80, {"open": 15, "wait": 30, "close": 14}
    G, Y0, X0, X1, L = 3.0, 102.0, 42.0, 138.0, 30

    def __init__(self):
        rnd = random.Random(11)
        self.embers = []  # birth in the loop, column, life, rise, drift, wobble
        for i in range(22):
            b = round(i * 30 / 22 + rnd.uniform(0, 1.2)) % 30
            if 15 <= b < 18:  # none born while the line is still catching
                b = 14 if i % 2 else 18
            col = rnd.randrange(int(self.X0 / self.G) + 2, int(self.X1 / self.G) - 2)
            self.embers.append((b, col, rnd.randint(9, 13), rnd.uniform(4.4, 6.2), rnd.uniform(-0.5, 0.5), rnd.uniform(0, 6.28)))
        self.cells = list(range(int(self.X0 / self.G), int(self.X1 / self.G)))
        self.flick = [(rnd.uniform(0, 6.28), rnd.randint(1, 3)) for _ in self.cells]

    def ember(self, c, ro, age, e, out):
        b, col, life, rise, drift, wob = e
        if not 0 <= age < life:
            return
        g, u = self.G, age / life
        x = math.floor((col * g + drift * age * g / 2 + 2.2 * math.sin(wob + age * 0.9)) / g) * g
        y = math.floor((self.Y0 - g - rise * age) / g) * g
        warm = mix(ro.yellow, ro.ansi[1], 0.5)
        color, a = (ro.yellow, 1.0) if u < 0.2 else (warm, 1.0) if u < 0.45 else (ro.ansi[1], 1.0 - max(0.0, u - 0.7) * 2.2)
        out.append(Layer(block(c, x, y, g, g), color, a))

    def draw(self, c, ro, anim, f):
        g, out = self.G, []
        mid, half = (len(self.cells) - 1) / 2, len(self.cells) / 2
        if anim == "open":
            reach, dim, tau = half * (f + 1) / 4, 1.0, f - 15
        elif anim == "wait":
            reach, dim, tau = half, 1.0, f
        else:
            reach, dim, tau = half * (1 - f / 9), 1 - f / 12, f
        for i, cell in enumerate(self.cells):
            if abs(i - mid) <= reach:
                ph, k = self.flick[i]
                a = (0.44 + 0.14 * math.sin(ph + 2 * math.pi * k * (tau % self.L) / self.L)) * dim
                out.append(Layer(block(c, cell * g, self.Y0, g, g), ro.ansi[1], a))
        for e in self.embers:
            b = e[0]
            if anim == "open":
                born = b - 30
                if born >= -15:
                    self.ember(c, ro, tau - born, e, out)
            elif anim == "wait":
                self.ember(c, ro, (f - b) % 30, e, out)
            else:  # only those already in the air
                born = 0 if b == 0 else b - 30
                self.ember(c, ro, f - born, e, out)
        return out


class Sun:
    name, ms, frames = "sun", 40, {"open": 30, "wait": 48, "close": 22}
    CX, CY, R, HZ, L, P = 90.0, 78.0, 34.0, 88.0, 48, 7.0  # P: the stripes' spacing

    def sun(self, c, ro, cy, tau):
        r, cx = self.R, self.CX
        a = c.area(cx - r - 1, cy - r - 1, cx + r + 1, min(self.HZ, cy + r) + 1)
        if a is None or cy - r >= self.HZ:
            return None, None
        rows, cols, X, Y = a
        cov = c.cov(np.hypot(X - cx, Y - cy) - r) * np.clip(0.5 - (Y - self.HZ) * c.s, 0, 1)
        v = Y - cy
        start = -0.2 * r
        gap = np.clip((v - start) / (0.75 * r), 0, 1) * 3.4  # the stripes widen downward
        w = np.mod(v - start - self.P * tau / self.L, self.P)
        cut = np.clip(0.5 - (np.abs(w - self.P / 2) - gap / 2) * c.s, 0, 1) * (gap > 0)
        cov = cov * (1 - cut)
        k = np.clip((Y - (cy - r)) / (r + self.HZ - self.CY), 0, 1)[..., None]
        y, red, mag = (np.asarray(x, np.float32) for x in (ro.yellow, ro.ansi[1], ro.ansi[5]))
        color = np.where(k < 0.55, y + (red - y) * (k / 0.55), red + (mag - red) * ((k - 0.55) / 0.45))
        return (cov, rows, cols), color

    def draw(self, c, ro, anim, f):
        sunk = self.R + self.HZ - self.CY + 2  # how far below to be out of sight
        if anim == "open":
            hl, cy, light, tau = 64 * ease_out(f / 10), self.CY + sunk * (1 - ease_out((f - 5) / 23)), ease_io((f - 14) / 15), f - 30
        elif anim == "wait":
            hl, cy, light, tau = 64.0, self.CY, 1.0, f
        else:
            hl, cy, light, tau = 64 * (1 - ease_io((f - 11) / 10)), self.CY + sunk * ease_in(f / 15), 1 - ease_io(f / 10), f
        out = []
        shape, color = self.sun(c, ro, cy, tau)
        if shape:
            out.append(Layer(shape, color))
        if hl > 0.3:
            out.append(Layer(capsule(c, self.CX - hl, self.HZ + 1.6, self.CX + hl, self.HZ + 1.6, 0.55), ro.muted, 0.9))
        glint = mix(ro.ansi[1], ro.ansi[5], 0.5)
        for k, (w, a) in enumerate(((24, 0.5), (16, 0.4), (10, 0.3), (5, 0.22))):
            if light > 0:
                t = 2 * math.pi * (tau / self.L + k / 4)
                w2, x = w * (1 + 0.2 * math.sin(t)), self.CX + 1.5 * math.sin(t + k)
                y = self.HZ + 6 + 5 * k
                out.append(Layer(capsule(c, x - w2, y, x + w2, y, 0.75), glint, a * light))
        return out


class Flight:
    name, ms, frames = "flight", 40, {"open": 30, "wait": 72, "close": 24}
    CX, CY, A, L = 90.0, 60.0, 64.0, 72
    OPEN = ((206.0, 104.0), (160.0, 116.0), (118.0, 88.0), (90.0, 60.0))  # it meets the eight at its crossing, heading up left
    CLOSE = ((90.0, 60.0), (71.4, 41.4), (40.0, 8.0), (-24.0, -26.0))
    WING = ((9.5, 0.0), (-8.0, -6.8), (-4.0, 0.0))
    FOLD = ((9.5, 0.0), (-4.0, 0.0), (-8.0, 6.8))

    def eight(self, tau):
        t = math.pi / 2 + 2 * math.pi * tau / self.L
        s, co = math.sin(t), math.cos(t)
        d = 1 + s * s
        return self.CX + self.A * co / d, self.CY + self.A * s * co / d

    @staticmethod
    def bezier(p, u):
        v = 1 - u
        return tuple(v**3 * p[0][i] + 3 * v * v * u * p[1][i] + 3 * v * u * u * p[2][i] + u**3 * p[3][i] for i in (0, 1))

    def at(self, anim, tau):
        if anim == "open":
            return None if tau < 0 else self.bezier(self.OPEN, tau / 30) if tau < 30 else self.eight(tau - 30)
        if anim == "wait" or tau < 0:
            return self.eight(tau)
        return self.bezier(self.CLOSE, tau / 20) if tau <= 20 else None

    def draw(self, c, ro, anim, f):
        out = []
        fade = 1 - ease_in((f - 12) / 11) if anim == "close" else 1.0
        for k in range(3, 27):  # the trail: where it was, a frame apart
            p = self.at(anim, f - k)
            if p:
                out.append(Layer(disc(c, p[0], p[1], 0.8), ro.muted, 0.75 * (1 - k / 27) * fade))
        p, q, n = self.at(anim, f - 0.5), self.at(anim, f + 0.5), self.at(anim, f)
        if n and p and q:
            th = math.atan2(q[1] - p[1], q[0] - p[0])
            cs, sn = math.cos(th), math.sin(th)
            place = lambda pts: [(n[0] + x * cs - y * sn, n[1] + x * sn + y * cs) for x, y in pts]
            out.append(Layer(polygon(c, place(self.WING)), ro.accent))
            out.append(Layer(polygon(c, place(self.FOLD)), mix(ro.accent, BLACK, 0.3)))
        return out


PIECES = {p.name: p for p in (Moon(), Ripple(), Tide(), Embers(), Sun(), Flight())}
ANIMS = (("open", False), ("wait", True), ("close", False))


# -- GIF ------------------------------------------------------------------------


def nearest(cols, table):
    return np.concatenate([((cols[i : i + 2048, None, :] - table[None]) ** 2).sum(-1).argmin(1) for i in range(0, len(cols), 2048)])


def indexed(frames):
    """The frames' drawn pixels as indices into one table of at most 255 colors
    (from 1; 0 is nothing): their own colors when they fit; else a median cut
    of the colors, each counted once so a soft edge's few pixels get their
    share, settled by k-means, each color weighed by the root of its pixels."""
    keys = [((im[..., 0].astype(np.uint32) << 16) | (im[..., 1].astype(np.uint32) << 8) | im[..., 2]) for im, _ in frames]
    drawn = np.concatenate([k[m] for k, (_, m) in zip(keys, frames)]) if frames else np.zeros(0, np.uint32)
    uniq, count = np.unique(drawn, return_counts=True)
    cols = np.stack([(uniq >> 16) & 255, (uniq >> 8) & 255, uniq & 255], 1).astype(np.float32)
    if len(uniq) <= 255:
        table, near = cols, np.arange(len(uniq))
    else:
        q = Image.fromarray(cols.astype(np.uint8).reshape(1, -1, 3)).quantize(255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        n = len(q.getcolors(256))
        table = np.asarray(q.getpalette()[: 3 * 256], np.float32).reshape(-1, 3)[:n]
        weight = np.sqrt(count).astype(np.float32)

        def settle(rounds):
            for _ in range(rounds):
                near = nearest(cols, table)
                total = np.bincount(near, weight, len(table))
                used = total > 0
                for ch in range(3):
                    table[used, ch] = np.bincount(near, weight * cols[:, ch], len(table))[used] / total[used]

        settle(8)
        for _ in range(24):  # the color served worst takes the slot used least, while one is off by more than 12
            near = nearest(cols, table)
            off = np.abs(cols - table[near]).max(1)
            if off.max() <= 12:
                break
            table[np.bincount(near, weight, len(table)).argmin()] = cols[off.argmax()]
            settle(2)
        near = nearest(cols, table)
    out = []
    for k, (_, m) in zip(keys, frames):
        idx = np.zeros(k.shape, np.uint8)
        if len(uniq):
            idx[m] = near[np.searchsorted(uniq, k[m])] + 1
        out.append(idx)
    return out, [tuple(int(v) for v in t) for t in table]


def lzw(data, min_size):
    """GIF's LZW: codes from min_size + 1 bits wide up to 12, the table cleared
    when it is full, in sub-blocks of 255."""
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


def gate():
    """What the privacy gate refuses in the tree (ci.yml's privacy job reads
    binary files too): an e-mail address, a private IPv4 address, a home path
    naming a user, and a word of .privacy-terms or of your own list (the one
    .githooks/pre-commit reads). Compressed bytes can spell one by chance."""
    shapes = [
        rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
        rb"\b(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)\b",
        rb"(^.|[^A-Za-z0-9/._-])/(home|Users)/[A-Za-z0-9_-]+",
    ]
    own = os.environ.get("SPARK_PRIVACY_TERMS") or os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "spark", "privacy-terms")
    words = set()
    for f in (os.path.join(REPO, ".privacy-terms"), own):
        if os.path.isfile(f):
            with open(f, encoding="utf-8") as fh:
                words |= {w.split("#")[0].strip() for w in fh} - {""}
    if words:
        shapes.append(rb"(?i)\b(" + b"|".join(re.escape(w.encode()) for w in sorted(words)) + rb")\b")
    return [re.compile(x, re.M) for x in shapes]


GATE = gate()


def write_gif(path, frames, colors, surface, ms, loop):
    """A GIF89a: one color table, index 0 nothing (its color the surface), every
    frame cleared to nothing after it (disposal 2), so each holds only its drawn
    box; a frame like the one before it lengthens it. If its bytes spell what
    the privacy gate refuses, the colors are numbered again, turned round the
    table by one more each try: every byte after the header changes and not
    one pixel."""
    bits = max(1, len(colors).bit_length())  # 2**bits holds nothing and the colors
    held = []
    for idx in frames:
        if held and np.array_equal(held[-1][0], idx):
            held[-1][1] += ms // 10
        else:
            held.append([idx, ms // 10])
    h, w = frames[0].shape
    le = lambda v: v.to_bytes(2, "little")
    n = len(colors)
    for turn in range(max(1, min(n, 64))):
        order = colors[n - turn :] + colors[: n - turn]  # color i is now at (i + turn) % n
        lut = np.zeros(256, np.uint8)
        lut[1 : n + 1] = (np.arange(n) + turn) % n + 1
        table = bytes(int(v) for v in surface) + b"".join(bytes(c) for c in order)
        table += b"\0" * (3 * (1 << bits) - len(table))
        out = bytearray(b"GIF89a" + le(w) + le(h) + bytes([0xF0 | (bits - 1), 0, 0]) + table)
        if loop:
            out += b"\x21\xff\x0bNETSCAPE2.0\x03\x01" + le(0) + b"\0"
        for idx, cs in held:
            idx = lut[idx]
            ys, xs = np.nonzero(idx)
            if len(ys):
                x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
            else:  # nothing drawn: one pixel of nothing
                x0, y0, x1, y1 = 0, 0, 1, 1
            part = idx[y0:y1, x0:x1]
            out += b"\x21\xf9\x04" + bytes([(2 << 2) | 1]) + le(cs) + b"\0\0"
            out += b"\x2c" + le(int(x0)) + le(int(y0)) + le(int(x1 - x0)) + le(int(y1 - y0)) + b"\0"
            out += lzw(part.tobytes(), max(2, bits))
        out += b"\x3b"
        if not any(g.search(out) for g in GATE):
            with open(path, "wb") as fh:
                fh.write(out)
            return
    raise RuntimeError("%s: its bytes spell what the privacy gate refuses, however its colors are numbered" % path)


def make(job):
    piece_name, path, out_dir = job
    piece = PIECES[piece_name]
    name = os.path.basename(path)[: -len(".env")] if path.endswith(".env") else os.path.basename(path)
    ro = Roles(read_env(path))
    d = os.path.join(out_dir, piece.name, name)
    os.makedirs(d, exist_ok=True)
    for s in SCALES:
        c = Canvas(s)
        for anim, loop in ANIMS:
            frames = [render(c, ro, piece.draw(c, ro, anim, f)) for f in range(piece.frames[anim])]
            idx, colors = indexed(frames)
            write_gif(os.path.join(d, "%s%s.gif" % (anim, "" if s == 1 else "@%dx" % s)), idx, colors, ro.surface, piece.ms, loop)
    return "%s/%s" % (piece.name, name)


def main(argv):
    out_dir, paths, pieces = HERE, [], []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_dir = next(it)
        elif a == "--piece":
            pieces.append(next(it))
        else:
            paths.append(a)
    for p in pieces:
        if p not in PIECES:
            sys.exit("no piece %s: %s" % (p, " ".join(PIECES)))
    if not paths:
        d = os.path.join(REPO, "themes")
        paths = sorted(os.path.join(d, p) for p in os.listdir(d) if p.endswith(".env"))
    jobs = [(p, path, out_dir) for p in (pieces or list(PIECES)) for path in paths]
    with Pool() as pool:
        try:
            for done in pool.imap_unordered(make, jobs):
                print(done)
        except RuntimeError as e:
            sys.exit(str(e))


if __name__ == "__main__":
    main(sys.argv[1:])
