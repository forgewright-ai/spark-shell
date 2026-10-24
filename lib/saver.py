#!/usr/bin/env python3
"""saver.py -- the idle screen's old-school animations. Python's standard library only.

  saver.py list                         the savers, one a line
  saver.py NAME                         play one in this terminal until a key, a mouse move or a signal
  saver.py NAME --frames N [--size WxH] [--seed N] [--time HH:MM] [--date TEXT] [--color]
                                        run N frames at once, print the last (a test, a look)
  saver.py NAME --json [--frames N] [--size WxH] [--seed N] [--time HH:MM] [--date TEXT]
                                        every frame as JSON, for a preview
  saver.py ... --ascii                  plain ASCII only, for a console with no block glyphs
  saver.py NAME --fade N                frames to come in over (played: 15; --frames and --json: 0)
  saver.py --version

A saver is a small machine: a size, a seed, and a frame each tick. The same seed
draws the same frames, so a test can hold them; a played saver takes the time as
its seed, so each idle screen moves its own way. The clock's figures are the idle
screen's own solid blocks (U+2588), which foot draws itself; --ascii keeps every
frame to ASCII. Every color is one of three roles the palette gives: the accent,
the muted color and the bold of the text. A saver never reads a file, never opens
a socket and never starts a program. Played, it writes only the cells that changed
since the frame before: the terminal redraws what moved and nothing else.

The savers are spark (bursts that arc and fade, embers rising), starfield (the
Windows 3.1 one) and drift (the clock bounces off the edges). Each keeps the idle
screen's own clock: the time in its large figures at the lower left, a row of
air, the date under it. Drift is the clock bouncing, with its date.
"""
import json
import locale
import math
import os
import random
import select
import signal
import sys
import termios
import time

VERSION = "1"
FPS = 10                 # frames a second; a saver is a light, not a load
FADE = 15                # frames a played saver takes to come in: a second and a half
BLOCK = "\u2588"         # the idle clock's figures: U+2588 full block
BLOCK_ASCII = "#"

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


def overlay_clock(g, text, where, block="#", date=""):
    """The idle screen's own clock: the time in the accent, only its strokes, so whatever moves
    behind shows between them; a row of air; the date in the muted color. Its place is
    spark-shell's idle_clock: three columns in, the date on the second row from the bottom
    (the time five rows above the air). A screen under 9 rows or 38 columns has the time and the
    date on two lines. where "tl" is the same block at the top, for a saver whose bottom burns."""
    big = g.h >= 9 and g.w >= 38
    if big:
        y0 = g.h - 8 if where == "bl" else 1
        for r, row in enumerate(clock_rows(text, block)):
            for x, c in enumerate(row):
                if c != " ":
                    g.put(2 + x, y0 + r, c, ACCENT)
        ydate = y0 + 6
    else:
        ytime = g.h - 3 if where == "bl" else 0
        for x, c in enumerate(text):
            g.put(2 + x, ytime, c, ACCENT)
        ydate = ytime + 1
    for x, c in enumerate(date):
        g.put(2 + x, ydate, c, MUTED)


class Saver:
    name = ""
    about = ""
    clock_at = "bl"          # "bl", "tl", or None when the saver draws the time itself
    fades = True             # whether its cells come in over `fade` frames; the clock never does

    def __init__(self, w, h, seed=0, block=None, ascii=False, fade=0):
        self.w, self.h = max(1, w), max(1, h)
        self.seed = seed
        self.fade = max(0, int(fade))
        self.rng = random.Random(seed)
        self.ascii = ascii
        self.block = block or (BLOCK_ASCII if ascii else BLOCK)
        self.n = 0
        self.date = ""

    def frame(self, clock_text, date_text=""):
        g = Grid(self.w, self.h)
        self.date = date_text
        self.draw(g, clock_text)
        if self.fades and self.n < self.fade:
            self._thin(g, (self.n + 1) / (self.fade + 1))
        self.n += 1
        if self.clock_at:
            overlay_clock(g, clock_text, self.clock_at, self.block, date_text)
        return g

    def draw(self, g, clock_text):
        raise NotImplementedError

    def _thin(self, g, keep):
        """The saver's cells at the start: each one kept with the chance `keep`, so a saver comes in
        out of nothing. A generator of its own, so the saver's own frames do not move: from the first
        frame past the fade they are the frames it has without one. The clock is drawn after this."""
        r = random.Random(self.seed * 7919 + self.n)
        for y in range(g.h):
            for x in range(g.w):
                if g.ch[y][x] != " " and r.random() > keep:
                    g.ch[y][x] = " "
                    g.role[y][x] = PLAIN


class Spark(Saver):
    name = "spark"
    about = "sparks all over: bursts that arc and fade, and embers rising from below"
    BURST = 0.2              # the chance a new burst goes off each frame
    EMBER = 0.7              # the chance a new ember leaves the bottom each frame
    MAX = 900                # the most sparks alive at once

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.sparks = []     # [x, y, vx, vy, age, life, kind, hue]
        for _ in range(45):                          # a screen opens with sparks already in the air
            self._step()

    def _burst(self):
        r = self.rng
        cx, cy = r.uniform(self.w * 0.1, self.w * 0.9), r.uniform(self.h * 0.1, self.h * 0.6)
        hue = r.random() < 0.5                       # one burst is white hot, the next stays orange
        for _ in range(r.randint(28, 56)):
            a, v = r.uniform(0, 6.2832), r.uniform(0.4, 1.9)
            self.sparks.append([cx, cy, math.cos(a) * v * 2, math.sin(a) * v,    # a cell is twice as tall as wide
                                0, r.randint(14, 26), "burst", hue])

    def _ember(self):
        r = self.rng
        self.sparks.append([r.uniform(0, self.w - 1), self.h - 1, r.uniform(-0.25, 0.25), -r.uniform(0.35, 0.9),
                            0, r.randint(int(self.h * 0.6), int(self.h * 1.6)) + 4, "ember", False])

    def _step(self):
        r = self.rng
        if r.random() < self.BURST and len(self.sparks) < self.MAX:
            self._burst()
        if r.random() < self.EMBER and len(self.sparks) < self.MAX:
            self._ember()
        alive = []
        for sp in self.sparks:
            sp[4] += 1
            if sp[4] > sp[5]:
                continue
            if sp[6] == "burst":
                sp[2] *= 0.93
                sp[3] = sp[3] * 0.93 + 0.07          # drag, and gravity pulling down
            else:
                sp[2] += r.uniform(-0.12, 0.12)      # an ember sways as it rises
                sp[3] *= 0.985
            sp[0] += sp[2]
            sp[1] += sp[3]
            if -1 <= sp[0] <= self.w and -1 <= sp[1] <= self.h:
                alive.append(sp)
        self.sparks = alive

    def draw(self, g, _t):
        self._step()
        for x, y, vx, vy, age, life, kind, hue in self.sparks:
            f = age / life                           # 0 when it leaves, 1 when it dies
            if f < 0.5:
                g.put(x - vx * 0.7, y - vy * 0.7, ".", MUTED)    # a short tail: young sparks streak
            if f < 0.35:
                c, role = "*", (BOLD if hue or kind == "ember" else ACCENT)
            elif f < 0.7:
                c, role = "+", ACCENT
            else:
                c, role = ".", MUTED
            g.put(x, y, c, role)


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
    fades = False            # its cells are the clock

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.x, self.y = self.rng.uniform(0, 8), self.rng.uniform(0, 4)
        self.vx, self.vy = 0.6, 0.3
        self.bold = False

    def draw(self, g, clock_text):
        rows = clock_rows(clock_text, self.block) + ["", self.date]    # the time, a row of air, the date
        cw, ch = max(len(r) for r in rows), len(rows)
        if cw > self.w or ch > self.h:           # a screen too small to bounce on: the idle screen's small layout
            overlay_clock(g, clock_text, "bl", self.block, self.date)
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
                    g.put(self.x + x, self.y + r, c, MUTED if r == 6 else BOLD if self.bold else ACCENT)


SAVERS = {c.name: c for c in (Spark, Starfield, Drift)}


def _runs(ch, role, a, b):
    """Cells a to b of a row as the terminal reads them: runs of one role under one escape."""
    out = []
    x = a
    while x < b:
        r = role[x]
        e = x
        while e < b and role[e] == r:
            e += 1
        run = "".join(ch[x:e])
        out.append(run if r == PLAIN else "\033[%sm%s\033[0m" % (SGR[r], run))
        x = e
    return "".join(out)


def render(g, home=True):
    """The frame as the terminal reads it: each row placed, runs of one role under one escape."""
    out = []
    for y in range(g.h):
        out.append("\033[%d;1H" % (y + 1) if home else "")
        out.append(_runs(g.ch[y], g.role[y], 0, g.w))
        if not home:
            out.append("\n")
    return "".join(out)


GRACE = 0.3              # seconds at the start whose input is not a key for the saver: it came before the saver did
GAP = 8                  # unchanged cells written over rather than jumped: a cursor move costs about as much


def render_changes(g, prev):
    """What changed since the frame before, as the terminal reads it: each run of changed cells
    placed with one cursor move, the rest left as it is on the screen. No frame before (the first,
    or a new size): the whole frame."""
    if prev is None or (prev.w, prev.h) != (g.w, g.h):
        return render(g)
    out = []
    for y in range(g.h):
        ch, role, pch, prole = g.ch[y], g.role[y], prev.ch[y], prev.role[y]

        def same(i):
            return ch[i] == pch[i] and role[i] == prole[i]
        x = 0
        while x < g.w:
            if same(x):
                x += 1
                continue
            s = e = x                                # a run of changes from s to e
            x += 1
            while x < g.w:
                if not same(x):
                    e = x
                    x += 1
                    continue
                k = x                                # an unchanged stretch: a change close after it joins the run
                while k < g.w and same(k) and k - x < GAP:
                    k += 1
                if k < g.w and not same(k):
                    e = k
                    x = k + 1
                else:
                    break
            out.append("\033[%d;%dH" % (y + 1, s + 1))
            out.append(_runs(ch, role, s, e + 1))
            x = e + 1
    return "".join(out)


def clock_now():
    return time.strftime("%H:%M")


def date_now():
    """The date the idle screen shows: `date '+%A %e %B'` with its runs of spaces squeezed, so the day
    has no leading zero or space. The weekday and the month follow the machine's locale."""
    t = time.localtime()
    return "%s %d %s" % (time.strftime("%A", t), t.tm_mday, time.strftime("%B", t))


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


def play(name, seed, block, ascii, fade=FADE):
    """In this terminal until a key, a mouse move or a signal ends it (#70): the window's size is
    read each frame, the terminal a byte at a time with no echo, and every move of the mouse is
    reported to it, so whatever a person does at the screen ends the saver as Ctrl-C does."""
    out = sys.stdout
    stop = []

    def bye(*_):
        stop.append(1)
    signal.signal(signal.SIGINT, bye)
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGHUP, bye)
    fd, kept = sys.stdin.fileno(), None
    if sys.stdin.isatty():
        try:
            kept = termios.tcgetattr(fd)
            raw = termios.tcgetattr(fd)
            raw[3] &= ~(termios.ICANON | termios.ECHO)
            raw[6][termios.VMIN], raw[6][termios.VTIME] = 0, 0
            termios.tcsetattr(fd, termios.TCSANOW, raw)
            out.write("\033[?1003h")              # every move of the mouse over the window, reported
        except termios.error:
            kept = None
    out.write("\033[?25l\033[2J")
    size, saver, prev = None, None, None
    started = time.monotonic()
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
                saver = SAVERS[name](size[0], size[1], seed, block, ascii, fade)
                fade = 0                             # a saver comes in once, not again at every resize
                out.write("\033[2J")
                prev = None
            g = saver.frame(clock_now(), date_now())
            out.write(render_changes(g, prev))
            out.flush()
            prev = g
            wait = max(0.0, 1.0 / FPS - (time.monotonic() - t0))
            if kept is None:
                time.sleep(wait)
                continue
            if select.select([fd], [], [], wait)[0] and os.read(fd, 64) and time.monotonic() - started > GRACE:
                break                                # a key, or the mouse moved: the person is back
    except (BrokenPipeError, InterruptedError):
        pass
    finally:
        try:
            out.write("\033[?1003l\033[0m\033[?25h")
            out.flush()
        except OSError:
            pass
        if kept is not None:
            try:
                termios.tcsetattr(fd, termios.TCSANOW, kept)
            except termios.error:
                pass


def main(argv):
    try:
        locale.setlocale(locale.LC_TIME, "")      # the weekday and the month in the machine's language
    except locale.Error:
        pass
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
    opts = {"--size": None, "--frames": None, "--seed": None, "--time": None, "--date": None, "--block": None, "--fade": None}
    flags = {"--json": False, "--color": False, "--ascii": False}
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
        seed = None if opts["--seed"] is None else int(opts["--seed"])
        frames = None if opts["--frames"] is None else int(opts["--frames"])
        fade = None if opts["--fade"] is None else int(opts["--fade"])
    except ValueError:
        print("saver: --seed, --frames and --fade take a number", file=sys.stderr)
        return 2
    if fade is not None and not 0 <= fade <= 200:
        print("saver: --fade is 0 to 200 frames (0: none)", file=sys.stderr)
        return 2
    block = opts["--block"]
    if block is not None and (len(block) != 1 or ord(block) < 33 or (flags["--ascii"] and ord(block) > 126)):
        print("saver: --block takes one printable character, ASCII with --ascii", file=sys.stderr)
        return 2
    if frames is None and not flags["--json"]:
        if not sys.stdout.isatty():
            print("saver: not a terminal: --frames N prints the last frame of N", file=sys.stderr)
            return 2
        play(name, int(time.time()) if seed is None else seed, block, flags["--ascii"], FADE if fade is None else fade)   # each idle screen its own way
        return 0
    frames = 100 if frames is None else frames
    if not 1 <= frames <= 5000:
        print("saver: --frames is 1 to 5000", file=sys.stderr)
        return 2
    w, h = parse_size(opts["--size"] or "80x24")
    t = opts["--time"] or clock_now()
    d = date_now() if opts["--date"] is None else opts["--date"]
    saver = SAVERS[name](w, h, seed or 0, block, flags["--ascii"], fade or 0)   # a look at frames has no fade unless asked
    grids = [saver.frame(t, d) for _ in range(frames)]
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
