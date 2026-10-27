#!/usr/bin/env python3
# tests for lib/saver.py -- plain asserts, standard library only. A saver is
# held to what the idle screen needs: every frame ASCII, inside its size, the
# same frames from the same seed, no crash on a small screen, the clock drawn
# where it says, and the escapes only the three roles' own.

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SAVER = os.path.join(REPO, "lib", "saver.py")
sys.path.insert(0, os.path.join(REPO, "lib"))
import saver  # noqa: E402

passed = 0


def ok(cond, what):
    global passed
    if not cond:
        sys.stderr.write("FAIL %s\n" % what)
        sys.exit(1)
    passed += 1


def run(*args):
    return subprocess.run([sys.executable, "-I", SAVER] + list(args), capture_output=True, text=True)


ok(sorted(saver.SAVERS) == ["drift", "spark", "starfield"], "the three savers")
ok(run("list").stdout.count("\n") == 3, "list names one a line")

BLOCKS = set("\u2588")   # the idle clock's block
for name, cls in saver.SAVERS.items():
    for plain in (False, True):
        for w, h in ((80, 24), (40, 12), (20, 6), (1, 1), (200, 60)):
            s = cls(w, h, seed=5, ascii=plain)
            seen = set()
            for n in range(150):
                g = s.frame("14:32")
                for row, rl in zip(g.text(), g.roles()):
                    if len(row) != w or len(rl) != w:
                        ok(False, "%s %dx%d frame %d: a row is not %d cells" % (name, w, h, n, w))
                    seen |= set(row)
                ok(len(g.text()) == h, "%s %dx%d: %d rows" % (name, w, h, h))
            what = "ascii" if plain else "blocks"
            ok(all(32 <= ord(c) < 127 for c in seen) if plain else all(32 <= ord(c) < 127 or c in BLOCKS for c in seen),
               "%s %dx%d %s: only the glyphs the mode allows" % (name, w, h, what))
            ok(set("".join(g.roles())) <= set(" amb"), "%s %dx%d: only the three roles" % (name, w, h))
    # the clock is solid blocks by default and # with --ascii
    big = cls(80, 24, seed=5)
    txt = "".join("".join(big.frame("14:32").text()) for _ in range(3))
    ok("\u2588" in txt, "%s: the clock is drawn in full blocks" % name)

    a = cls(80, 24, seed=9).frame("09:05").text()
    b = cls(80, 24, seed=9).frame("09:05").text()
    c = cls(80, 24, seed=10)
    d = cls(80, 24, seed=9)
    fa = [d.frame("09:05").text() for _ in range(30)]
    fc = [c.frame("09:05").text() for _ in range(30)]
    ok(a == b, "%s: the same seed, the same first frame" % name)
    if name != "drift":                       # drift's start differs by seed too, but only in where it begins
        ok(fa != fc, "%s: another seed, other frames" % name)
    ok(len(set("".join(f) for f in fa)) > 5, "%s: it moves" % name)

# the clock is the idle screen's own: the same figures, 34 cells wide, and the same place
rows = saver.clock_rows("14:32")
ok(len(rows) == 5 and all(len(r) == 34 for r in rows), "the time is five rows and 34 cells wide")
ok(rows[0].startswith("  ") and "##" in rows[0], "a figure has strokes two cells wide")
src = open(os.path.join(REPO, "spark-shell")).read()
digits = {m.group(1): tuple(re.findall(r"'([ #]*)'", m.group(2)))
          for m in re.finditer(r"^\s+([0-9:])\) printf '%s\\n' ((?:'[ #]*' ?)+) ;;", src, re.M)}
ok(digits == saver.GLYPHS, "the figures are the ones spark-shell's idle clock draws (clock_digit)")
names = re.search(r"^SAVER_NAMES='([a-z ]*)'", src, re.M)
ok(names is not None and names.group(1).split() == list(saver.SAVERS), "the names DISPLAY_SAVER takes are the savers, in lib/saver.py's order")
ok(re.search(r"^VERSION = \"%s\"" % re.escape(saver.VERSION), open(os.path.join(REPO, "lib", "saver.py")).read(), re.M) is not None, "saver_version reads the version out of the file")
for name in ("spark", "starfield"):
    g = saver.SAVERS[name](80, 24, seed=1, ascii=True).frame("14:32", "Saturday 24 October")
    ok(g.role[16].count("a") > 4 and g.role[20].count("a") > 4, "%s: the time sits at the lower left in the accent, rows 17 to 21" % name)
    d = "Saturday 24 October"      # the letters are drawn; whatever moves may pass between the words
    ok(all(g.text()[22][2 + i] == c and g.role[22][2 + i] == "m" for i, c in enumerate(d) if c != " "),
       "%s: the date is on the second row from the bottom, muted" % name)
    ok(set(g.text()[21][2:30]) <= set(" ") or "#" not in g.text()[21][2:30], "%s: a row of air between the time and the date" % name)
# a screen under 9 rows or 38 columns has the time and the date on two lines
g = saver.SAVERS["starfield"](30, 8, seed=1).frame("14:32", "Saturday 24 October")
ok("14:32" in "".join(g.text()[5]) and "Saturday 24" in "".join(g.text()[6]), "a small screen has the time and the date on two lines")
g = saver.SAVERS["starfield"](37, 20, seed=1).frame("14:32", "Saturday 24")
ok("14:32" in "".join(g.text()[17]), "37 columns is small: the two lines")

# the fade: a played saver comes in over its first frames. The clock is solid from the first, and
# the saver's own frames do not move: past the fade they are the frames it has without one
def lit(g):
    return sum(1 for row in g.text() for c in row if c != " ")


for name in ("spark", "starfield"):
    cls = saver.SAVERS[name]
    a = cls(80, 24, seed=3, fade=15)
    b = cls(80, 24, seed=3)
    fa = [a.frame("14:32", "Saturday 24 October") for _ in range(20)]
    fb = [b.frame("14:32", "Saturday 24 October") for _ in range(20)]
    ok(all(fa[n].text() == fb[n].text() and fa[n].roles() == fb[n].roles() for n in range(15, 20)),
       "%s: past its fade the frames are the ones it has without a fade" % name)
    clock = saver.Grid(80, 24)
    saver.overlay_clock(clock, "14:32", cls.clock_at, saver.BLOCK, "Saturday 24 October")
    solid = all(fa[0].ch[y][x] == clock.ch[y][x] and fa[0].role[y][x] == clock.role[y][x]
                for y in range(24) for x in range(80) if clock.ch[y][x] != " ")
    ok(solid, "%s: the clock is whole from the first frame" % name)
    same = all(fa[0].ch[y][x] in (" ", fb[0].ch[y][x]) or clock.ch[y][x] != " " for y in range(24) for x in range(80))
    ok(same, "%s: a faded cell is the saver's own cell, never another" % name)
    counts = [lit(g) for g in fa[:15]]
    ok(counts[0] < lit(fb[0]) and counts[-1] > counts[0], "%s: it fills as it comes in (%d to %d cells)" % (name, counts[0], counts[-1]))
d = saver.SAVERS["drift"](80, 24, seed=3, fade=15)
e = saver.SAVERS["drift"](80, 24, seed=3)
ok(all(d.frame("14:32", "x").text() == e.frame("14:32", "x").text() for _ in range(20)), "drift does not fade: its cells are the clock")
# fade 0 is no fade, and the fade has no effect on the random stream a saver draws from
ok(saver.SAVERS["spark"](80, 24, seed=3, fade=0).frame("14:32").text() == saver.SAVERS["spark"](80, 24, seed=3).frame("14:32").text(), "fade 0 is none")

# played, a saver writes only what changed: on a screen that takes the writes, the last frame
# stands exactly as a whole redraw would draw it, for fewer bytes (drift, mostly still, far fewer)
def apply(screen, text):
    """A terminal's grid taking cursor moves, the three roles' escapes and plain cells."""
    y = x = 0
    role = " "
    back = {v: k for k, v in saver.SGR.items()}
    for m in re.finditer(r"\x1b\[(\d+);(\d+)H|\x1b\[([0-9;]+)m|(.)", text, re.S):
        if m.group(1):
            y, x = int(m.group(1)) - 1, int(m.group(2)) - 1
        elif m.group(3):
            role = back.get(m.group(3), " ")
        else:
            screen[y][x] = (m.group(4), role)
            x += 1


for name in saver.SAVERS:
    for w, h in ((80, 24), (200, 56)):
        s = saver.SAVERS[name](w, h, seed=4, fade=15)
        screen = [[(" ", " ")] * w for _ in range(h)]
        prev, sent, whole = None, 0, 0
        for n in range(120):
            g = s.frame("14:3%d" % (n // 60), "Saturday 24 October")
            out = saver.render_changes(g, prev)
            apply(screen, out)
            sent += len(out)
            whole += len(saver.render(g))
            prev = g
        ok(all(screen[y][x] == (g.ch[y][x], g.role[y][x]) for y in range(h) for x in range(w)),
           "%s %dx%d: the changes alone leave the screen as the last frame draws it" % (name, w, h))
        ok(sent < whole * (0.25 if name == "drift" else 1), "%s %dx%d: the changes are fewer bytes than a whole redraw, drift's a quarter at most (%d of %d)" % (name, w, h, sent, whole))
ok(saver.render_changes(g, None) == saver.render(g), "with no frame before, the whole frame")

# drift bounces: it stays on the screen and turns at an edge
d = saver.SAVERS["drift"](80, 24, seed=3)
xs = []
for _ in range(400):
    g = d.frame("14:32")
    cells = [x for row in g.text() for x, ch in enumerate(row) if ch != " "]
    ok(bool(cells), "drift: the clock is on the screen")
    xs.append(min(cells))
# the clock is 34 cells wide on 80, and its leading 1 is four cells of air: its left stroke runs 4 to 50
ok(min(xs) <= 5 and max(xs) >= 48, "drift reaches both edges (%d to %d)" % (min(xs), max(xs)))

# the command line
r = run("starfield", "--frames", "5", "--size", "40x10", "--seed", "1", "--time", "12:00", "--date", "Monday 2 March")
ok(r.returncode == 0 and r.stdout.count("\n") == 10 and all(len(x) == 40 for x in r.stdout.split("\n")[:-1]), "--frames prints the last frame, plain")
r = run("spark", "--frames", "3", "--size", "30x8", "--color")
ok(r.returncode == 0 and re.search(r"\x1b\[(38;5;16|38;5;20|1|0)m", r.stdout) is not None, "--color draws the roles")
ok(not re.search(r"\x1b\[(?!(38;5;16|38;5;20|1|0)m)", r.stdout), "--color has no escape but the roles'")
r = run("starfield", "--json", "--frames", "4", "--size", "20x6")
j = json.loads(r.stdout)
ok(j["w"] == 20 and j["h"] == 6 and len(j["frames"]) == 4 and len(j["frames"][0][0]) == 6, "--json gives the frames")
ok(run("nope").returncode == 2, "an unknown saver is exit 2")
ok(run("spark", "--size", "9").returncode == 2, "a bad size is exit 2")
ok(run("spark", "--frames", "0").returncode == 2, "a frame count under 1 is exit 2")
ok(run("spark", "--frames", "1", "--fade", "201").returncode == 2 and run("spark", "--frames", "1", "--fade", "-1").returncode == 2 and run("spark", "--frames", "1", "--fade", "x").returncode == 2, "a fade outside 0 to 200, or not a number, is exit 2")
r0 = run("starfield", "--frames", "1", "--size", "80x24", "--seed", "2", "--fade", "0")
r1 = run("starfield", "--frames", "1", "--size", "80x24", "--seed", "2", "--fade", "30")
ok(r0.returncode == 0 and r1.returncode == 0 and sum(c != " " and c != "\n" for c in r1.stdout) < sum(c != " " and c != "\n" for c in r0.stdout), "--fade 30 makes the first frame thinner than none")
ok(run("spark", "--block", "xy", "--frames", "1").returncode == 2, "a block is one character")
r = run("drift", "--ascii", "--frames", "3", "--size", "60x12")
ok(r.returncode == 0 and all(ord(c) < 127 for c in r.stdout) and "#" in r.stdout, "--ascii prints ASCII, the clock in #")
r = run("drift", "--frames", "3", "--size", "60x12")
ok("\u2588" in r.stdout, "by default the clock is full blocks")
r = run("spark", "--ascii", "--block", "\u2588", "--frames", "1")
ok(r.returncode == 2, "--ascii refuses a block that is not ASCII")
ok(run("spark").returncode == 2, "play with no terminal is exit 2, nothing drawn")
ok(run("spark", "--frames", "4", "--size", "40x10").stdout == run("spark", "--frames", "4", "--size", "40x10").stdout, "with no --seed, a look at frames is the same each time (seed 0); a played saver takes the time")
ok(run("--version").stdout.strip() == saver.VERSION, "--version")

# played in a terminal, a key or a mouse move ends it as a signal does (#70), after a moment's
# grace; the mouse is reported only while it plays, and the cursor comes back
import fcntl
import pty
import struct
import termios as tio


def played(events, until=6.0):
    """drift at a pty of 80x24; events: (seconds, bytes) to type. -> the output, the seconds from
    the last bytes typed to its end (None when it never ended), its exit status."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(sys.executable, [sys.executable, "-I", SAVER, "drift"])
    fcntl.ioctl(fd, tio.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    out, t0, last, todo = b"", time.time(), None, list(events)
    while time.time() - t0 < until:
        if select.select([fd], [], [], 0.02)[0]:
            try:
                out += os.read(fd, 65536)
            except OSError:
                pass
        while todo and time.time() - t0 >= todo[0][0]:
            os.write(fd, todo.pop(0)[1])
            last = time.time()
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            played.left = len(todo)                  # keys never typed: it ended before them
            return out, (time.time() - last) if last else None, st
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    played.left = len(todo)
    return out, None, None


import select  # noqa: E402
import time  # noqa: E402
out, took, st = played([(1.0, b"x")])
ok(took is not None and took < 1.0 and st == 0, "a key ends a played saver within a second, a clean end (#70)")
ok(b"\x1b[?1003h" in out and out.endswith(b"\x1b[?1003l\x1b[0m\x1b[?25h"), "the mouse is reported while it plays and not after; the cursor comes back")
out, took, st = played([(1.0, b"\x1b[M#!!")])
ok(took is not None and took < 1.0, "a mouse move, as the terminal reports it, ends it too")
out, took, st = played([(0.05, b"x"), (1.5, b"y")])
ok(played.left == 0 and took is not None and took < 1.0, "a key in its first moment is not the person coming back: it plays on, and the next one ends it")

print("saver_test: %d checks passed" % passed)

# The time preference is read live, including the half-day on large figures.
import tempfile
from unittest.mock import patch
with tempfile.TemporaryDirectory() as folder:
    os.makedirs(os.path.join(folder, "spark-shell"))
    config = os.path.join(folder, "spark-shell", "config")
    with patch.dict(os.environ, {"XDG_CONFIG_HOME": folder}):
        with open(config, "w") as f:
            f.write("CLOCK_FORMAT=12\n")
        with patch.object(saver.time, "strftime", return_value="01:05 PM"):
            assert saver.clock_now() == "1:05 PM"
        assert saver.clock_rows("1:05 PM")[-1].endswith(" PM")
        with open(config, "w") as f:
            f.write("CLOCK_FORMAT=24\n")
        with patch.object(saver.time, "strftime", return_value="13:05") as fmt:
            assert saver.clock_now() == "13:05"
            fmt.assert_called_once_with("%H:%M")
print("saver time preferences: live clock format and half-day passed")
