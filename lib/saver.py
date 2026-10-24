#!/usr/bin/env python3
"""saver.py -- the idle screen's old-school animations. Python's standard library only.

  saver.py list                         the savers, one a line
  saver.py NAME                         play one in this terminal until a signal ends it
  saver.py NAME --frames N [--size WxH] [--seed N] [--time HH:MM] [--color]
                                        run N frames at once, print the last (a test, a look)
  saver.py NAME --json [--frames N] [--size WxH] [--seed N] [--time HH:MM]
                                        every frame as JSON, for a preview
  saver.py --version

A saver is a small machine: a size, a seed, and a frame each tick. The same seed
draws the same frames, so a test can hold them. Every frame is ASCII, the Linux
console draws all of it, and every color is one of three roles the palette gives:
the accent, the muted color and the bold of the text. A saver never reads a file,
never opens a socket and never starts a program.

The savers are starfield (the Windows 3.1 one), drift (the clock bounces off the
edges), fire (the demo scene's), and mystify (two ribbons of lines). All but drift
keep the time at the lower left, in the figures the idle screen draws.
"""
import json
import os
import random
import signal
import sys
import time
from collections import deque

VERSION = "1"
FPS = 10                 # frames a second; a saver is a light, not a load

# the roles a cell wears: plain text, the accent, the muted color, bold text
PLAIN, ACCENT, MUTED, BOLD = " ", "a", "m", "b"
# the desktop's foot.ini slots, as the idle clock and the dialog draw them
SGR = {PLAIN: "0", ACCENT: "38;5;16", MUTED: "38;5;20", BOLD: "1"}

# the clock's figures: five rows, every stroke two cells wide when drawn
GLYPHS = {
    "0": ("###", "# #", "# #", "# #", "###"),
    "1": ("  #", " ##", "  #", "  #", "  #"),
    "2": ("###", "  #", "###", "#  ", "###"),
    "3": ("###", "  #", "###", "  #", "###"),
    "4": ("# #", "# #", "###", "  #", "  #"),
    "5": ("###", "#  ", "###", "  #", "###"),
    "6": ("###", "#  ", "###", "# #", "###"),
    "7": ("###", "  #", "  #", "  #", "  #"),
    "8": ("###", "# #", "###", "# #", "###"),
    "9": ("###", "# #", "###", "  #", "###"),
    ":": (" ", "#", " ", "#", " "),
}


class Grid:
    """w by h cells, each a character and a role. Drawing outside is clipped."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.ch = [[" "] * w for _ in range(h)]
        self.role = [[PLAIN] * w for _ in range(h)]

    def put(self, x, y, c, role=PLAIN):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.ch[y][x] = c
            self.role[y][x] = role

    def text(self):
        return ["".join(r) for r in self.ch]

    def roles(self):
        return ["".join(r) for r in self.role]


def clock_rows(text, block="#"):
    """The time as five rows of cells; a space is air, anything else a stroke."""
    rows = [""] * 5
    for i, c in enumerate(text):
        glyph = GLYPHS.get(c)
        if glyph is None:
            continue
        for r in range(5):
            part = "".join(block * 2 if p == "#" else "  " for p in glyph[r])
            rows[r] += ("  " if i else "") + part
    return rows


def overlay_clock(g, text, where, block="#"):
    """The time in the accent, only its strokes: whatever moves behind shows between them.
    A screen under 9 rows or 38 columns has the time on one line, as the idle screen does."""
    if g.h >= 9 and g.w >= 38:
        y0 = g.h - 7 if where == "bl" else 1
        for r, row in enumerate(clock_rows(text, block)):
            for x, c in enumerate(row):
                if c != " ":
                    g.put(2 + x, y0 + r, c, ACCENT)
    else:
        for x, c in enumerate(text):
            g.put(2 + x, g.h - 2 if where == "bl" else 1, c, ACCENT)


class Saver:
    name = ""
    about = ""
    clock_at = "bl"          # "bl", "tl", or None when the saver draws the time itself

    def __init__(self, w, h, seed=0, block="#"):
        self.w, self.h = max(1, w), max(1, h)
        self.rng = random.Random(seed)
        self.block = block
        self.n = 0

    def frame(self, clock_text):
        g = Grid(self.w, self.h)
        self.draw(g, clock_text)
        self.n += 1
        if self.clock_at:
            overlay_clock(g, clock_text, self.clock_at, self.block)
        return g

    def draw(self, g, clock_text):
        raise NotImplementedError


class Starfield(Saver):
    name = "starfield"
    about = "stars flying at you from the middle of the screen"

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.stars = [self._new(True) for _ in range(max(8, self.w * self.h // 10))]

    def _new(self, anywhere):
        return [self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(0.1, 1.0) if anywhere else 1.0]

    def draw(self, g, _t):
        for i, s in enumerate(self.stars):
            s[2] -= 0.02
            if s[2] <= 0.03:
                self.stars[i] = s = self._new(False)
            sx = self.w / 2 + s[0] / s[2] * (self.w / 8)
            sy = self.h / 2 + s[1] / s[2] * (self.h / 8)
            if not (0 <= sx < self.w and 0 <= sy < self.h):
                self.stars[i] = self._new(False)
                continue
            if s[2] > 0.66:
                g.put(sx, sy, ".", MUTED)
            elif s[2] > 0.33:
                g.put(sx, sy, "+", PLAIN)
            else:
                g.put(sx, sy, "*", BOLD)


class Drift(Saver):
    name = "drift"
    about = "the clock bounces off the edges, and the figures turn bold at each bounce"
    clock_at = None

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.x, self.y = self.rng.uniform(0, 8), self.rng.uniform(0, 4)
        self.vx, self.vy = 0.6, 0.3
        self.bold = False

    def draw(self, g, clock_text):
        rows = clock_rows(clock_text, self.block)
        cw, ch = max(len(r) for r in rows), len(rows)
        if cw > self.w or ch > self.h:           # a screen too small to bounce on: the time, one line
            overlay_clock(g, clock_text, "bl", self.block)
            return
        self.x += self.vx
        self.y += self.vy
        if self.x < 0 or self.x > self.w - cw:
            self.vx = -self.vx
            self.x = min(max(self.x, 0), self.w - cw)
            self.bold = not self.bold
        if self.y < 0 or self.y > self.h - ch:
            self.vy = -self.vy
            self.y = min(max(self.y, 0), self.h - ch)
            self.bold = not self.bold
        for r, row in enumerate(rows):
            for x, c in enumerate(row):
                if c != " ":
                    g.put(self.x + x, self.y + r, c, BOLD if self.bold else ACCENT)


class Fire(Saver):
    name = "fire"
    about = "the demo scene's fire, burning up from the bottom edge"
    clock_at = "tl"
    RAMP = " .:^*sS#%@"
    TOP = 30                 # the heat of the bottom row

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.heat = [[0] * self.w for _ in range(self.h)]
        # a flame reaches about half the screen: the most a row cools follows from that
        self.cool = max(2, round(2 * self.TOP / (0.5 * self.h)))
        for _ in range(2 * self.h):                  # burn before the first frame: a screen never opens cold
            self._burn()

    def _burn(self):
        h, w, rng = self.h, self.w, self.rng
        self.heat[h - 1] = [self.TOP - rng.randint(0, 6) for _ in range(w)]   # a bed of coals, not a line
        for y in range(h - 1):
            below = self.heat[y + 1]
            row = self.heat[y]
            for x in range(w):
                src = below[min(w - 1, max(0, x + rng.randint(0, 2)))]   # the wind blows from the right
                row[x] = max(0, src - rng.randint(0, self.cool))

    def draw(self, g, _t):
        h, w = self.h, self.w
        self._burn()
        top = len(self.RAMP) - 1
        for y in range(h):
            for x in range(w):
                v = self.heat[y][x]
                if v:
                    role = BOLD if v > self.TOP * 2 // 3 else ACCENT if v > self.TOP // 3 else MUTED
                    g.put(x, y, self.RAMP[max(1, v * top // self.TOP)], role)


def _line(a, b):
    """The cells from a to b, Bresenham's."""
    (x0, y0), (x1, y1) = a, b
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        yield x0, y0
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def _stroke(a, b):
    """The character a segment is drawn with; a cell is twice as tall as it is wide."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    if dy == 0:
        return "-"
    if dx == 0:
        return "|"
    v = abs(dy * 2 / dx)
    if v < 0.5:
        return "-"
    if v > 2:
        return "|"
    return "/" if (dx > 0) != (dy > 0) else "\\"


class Mystify(Saver):
    name = "mystify"
    about = "two ribbons of lines, each point bouncing, the old trails fading"
    TRAIL = 4

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.ribbons = []
        for _ in range(2):
            pts = [[self.rng.uniform(0, self.w - 1), self.rng.uniform(0, self.h - 1)] for _ in range(4)]
            vel = [[self.rng.choice((-1, 1)) * self.rng.uniform(1.4, 2.6),
                    self.rng.choice((-1, 1)) * self.rng.uniform(0.7, 1.3)] for _ in range(4)]
            self.ribbons.append((pts, vel, deque(maxlen=self.TRAIL)))

    def draw(self, g, _t):
        for pts, vel, trail in self.ribbons:
            for p, v in zip(pts, vel):
                p[0] += v[0]
                p[1] += v[1]
                if p[0] < 0 or p[0] > self.w - 1:
                    v[0] = -v[0]
                    p[0] = min(max(p[0], 0), self.w - 1)
                if p[1] < 0 or p[1] > self.h - 1:
                    v[1] = -v[1]
                    p[1] = min(max(p[1], 0), self.h - 1)
            trail.append([(round(p[0]), round(p[1])) for p in pts])
        for k, (_p, _v, trail) in enumerate(self.ribbons):
            for age, shape in enumerate(trail):      # oldest first, so the newest ribbon is on top
                newest = age == len(trail) - 1
                role = (ACCENT if k == 0 else BOLD) if newest else MUTED
                for i in range(len(shape)):
                    a, b = shape[i], shape[(i + 1) % len(shape)]
                    c = _stroke(a, b)
                    for x, y in _line(a, b):
                        g.put(x, y, c, role)


SAVERS = {c.name: c for c in (Starfield, Drift, Fire, Mystify)}


def render(g, home=True):
    """The frame as the terminal reads it: each row placed, runs of one role under one escape."""
    out = []
    for y in range(g.h):
        out.append("\033[%d;1H" % (y + 1) if home else "")
        x = 0
        while x < g.w:
            r = g.role[y][x]
            e = x
            while e < g.w and g.role[y][e] == r:
                e += 1
            run = "".join(g.ch[y][x:e])
            out.append(run if r == PLAIN else "\033[%sm%s\033[0m" % (SGR[r], run))
            x = e
        if not home:
            out.append("\n")
    return "".join(out)


def clock_now():
    return time.strftime("%H:%M")


def parse_size(s):
    try:
        w, h = s.lower().split("x")
        w, h = int(w), int(h)
    except ValueError:
        raise SystemExit("saver: --size takes WxH, as 80x24")
    if not (1 <= w <= 500 and 1 <= h <= 200):
        raise SystemExit("saver: --size is 1x1 to 500x200")
    return w, h


def usage():
    print(__doc__.strip().split("\n\n")[0])


def play(name, seed, block):
    """In this terminal until SIGINT or SIGTERM: the window's size is read each frame."""
    out = sys.stdout
    stop = []

    def bye(*_):
        stop.append(1)
    signal.signal(signal.SIGINT, bye)
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGHUP, bye)
    out.write("\033[?25l\033[2J")
    size, saver = None, None
    try:
        while not stop:
            t0 = time.monotonic()
            try:
                sz = os.get_terminal_size(out.fileno())
                now = (sz.columns, sz.lines)
            except OSError:
                now = (80, 24)
            if now != size:
                size = now
                saver = SAVERS[name](size[0], size[1], seed, block)
                out.write("\033[2J")
            out.write(render(saver.frame(clock_now())))
            out.flush()
            time.sleep(max(0.0, 1.0 / FPS - (time.monotonic() - t0)))
    except BrokenPipeError:
        pass
    finally:
        try:
            out.write("\033[0m\033[?25h")
            out.flush()
        except OSError:
            pass


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        usage()
        return 0
    if argv[0] == "--version":
        print(VERSION)
        return 0
    if argv[0] == "list":
        for n, c in SAVERS.items():
            print("%-10s %s" % (n, c.about))
        return 0
    name, rest = argv[0], argv[1:]
    if name not in SAVERS:
        print("saver: no saver named %s; saver.py list names them" % name, file=sys.stderr)
        return 2
    opts = {"--size": None, "--frames": None, "--seed": "0", "--time": None, "--block": "#"}
    flags = {"--json": False, "--color": False}
    i = 0
    while i < len(rest):
        a = rest[i]
        if a in flags:
            flags[a] = True
        elif a in opts and i + 1 < len(rest):
            i += 1
            opts[a] = rest[i]
        else:
            print("saver: no option %s; saver.py -h lists them" % a, file=sys.stderr)
            return 2
        i += 1
    try:
        seed = int(opts["--seed"])
        frames = None if opts["--frames"] is None else int(opts["--frames"])
    except ValueError:
        print("saver: --seed and --frames take a number", file=sys.stderr)
        return 2
    block = opts["--block"]
    if len(block) != 1 or not (32 < ord(block) < 127):
        print("saver: --block takes one printable ASCII character", file=sys.stderr)
        return 2
    if frames is None and not flags["--json"]:
        if not sys.stdout.isatty():
            print("saver: not a terminal: --frames N prints the last frame of N", file=sys.stderr)
            return 2
        play(name, seed, block)
        return 0
    frames = 100 if frames is None else frames
    if not 1 <= frames <= 5000:
        print("saver: --frames is 1 to 5000", file=sys.stderr)
        return 2
    w, h = parse_size(opts["--size"] or "80x24")
    t = opts["--time"] or clock_now()
    saver = SAVERS[name](w, h, seed, block)
    grids = [saver.frame(t) for _ in range(frames)]
    if flags["--json"]:
        json.dump({"name": name, "w": w, "h": h, "fps": FPS,
                   "frames": [[g.text(), g.roles()] for g in grids]}, sys.stdout, separators=(",", ":"))
        print()
    else:
        sys.stdout.write(render(grids[-1], home=False) if flags["--color"] else "\n".join(grids[-1].text()) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(141)
