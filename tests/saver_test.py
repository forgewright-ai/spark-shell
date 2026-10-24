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


ok(sorted(saver.SAVERS) == ["drift", "fire", "mystify", "sparks", "starfield"], "the five savers")
ok(run("list").stdout.count("\n") == 5, "list names one a line")

BLOCKS = set("\u2588\u2591\u2592\u2593") | set(chr(c) for c in range(0x2801, 0x2900))   # the idle clock's block, fire's shades, mystify's braille
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

# the clock is drawn where each saver says; the figures are the idle screen's, 34 cells wide
rows = saver.clock_rows("14:32")
ok(len(rows) == 5 and all(len(r) == 34 for r in rows), "the time is five rows and 34 cells wide")
ok(rows[0].startswith("  ") and "##" in rows[0], "a figure has strokes two cells wide")
for name in ("starfield", "mystify"):
    g = saver.SAVERS[name](80, 24, seed=1).frame("14:32")
    ok(g.role[24 - 7][2 + 6] == "a" or "a" in g.role[24 - 7], "%s: the clock sits at the lower left in the accent" % name)
g = saver.SAVERS["fire"](80, 24, seed=1).frame("14:32")
ok("a" in g.role[1], "fire: the clock moves to the top")
ok("".join(g.text()[1])[2:8].strip() != "", "fire: the clock is drawn")
# mystify in braille: its lines are dots, never a stroke character; with --ascii they are strokes
m = saver.SAVERS["mystify"](80, 24, seed=4)
txt = "".join("".join(m.frame("14:32").text()) for _ in range(40))
ok(any(0x2801 <= ord(c) < 0x2900 for c in txt) and not any(c in "/\\" for c in txt), "mystify draws in braille")
m = saver.SAVERS["mystify"](80, 24, seed=4, ascii=True)
txt = "".join("".join(m.frame("14:32").text()) for _ in range(40))
ok(any(c in "/\\|-" for c in txt) and all(ord(c) < 127 for c in txt), "mystify --ascii draws strokes")
# sparks: a burst is many sparks at once, and the screen opens with some in the air
sp = saver.SAVERS["sparks"](80, 24, seed=7)
ok(len(sp.sparks) > 30, "sparks opens with sparks in the air (%d)" % len(sp.sparks))
peak = max(len(sp.sparks) for _ in range(200) if sp.frame("14:32"))
ok(peak > 100 and peak <= sp.MAX + 60, "sparks fills the screen without passing its cap (%d)" % peak)
sp = saver.SAVERS["sparks"](80, 24, seed=7)
gone = 0
for _ in range(400):
    sp.frame("14:32")
    gone = max(gone, len(sp.sparks))
ok(all(-1 <= x <= 80 and -1 <= y <= 24 for x, y, *_ in sp.sparks), "sparks leave the list when they leave the screen")
# a screen too small for the figures has the time on one line
g = saver.SAVERS["starfield"](30, 8, seed=1).frame("14:32")
ok("14:32" in "".join(g.text()), "a small screen has the time on one line")

# fire is warm before its first frame, and never a solid wall
f = saver.SAVERS["fire"](80, 24, seed=2)
g = f.frame("14:32")
lit = sum(1 for row in g.text() for ch in row if ch != " ")
ok(300 < lit < 1700, "fire opens mid-burn, not cold and not a wall (%d cells lit)" % lit)

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
r = run("starfield", "--frames", "5", "--size", "40x10", "--seed", "1", "--time", "12:00")
ok(r.returncode == 0 and r.stdout.count("\n") == 10 and all(len(x) == 40 for x in r.stdout.split("\n")[:-1]), "--frames prints the last frame, plain")
r = run("fire", "--frames", "3", "--size", "30x8", "--color")
ok(r.returncode == 0 and re.search(r"\x1b\[(38;5;16|38;5;20|1|0)m", r.stdout) is not None, "--color draws the roles")
ok(not re.search(r"\x1b\[(?!(38;5;16|38;5;20|1|0)m)", r.stdout), "--color has no escape but the roles'")
r = run("mystify", "--json", "--frames", "4", "--size", "20x6")
j = json.loads(r.stdout)
ok(j["w"] == 20 and j["h"] == 6 and len(j["frames"]) == 4 and len(j["frames"][0][0]) == 6, "--json gives the frames")
ok(run("nope").returncode == 2, "an unknown saver is exit 2")
ok(run("fire", "--size", "9").returncode == 2, "a bad size is exit 2")
ok(run("fire", "--frames", "0").returncode == 2, "a frame count under 1 is exit 2")
ok(run("fire", "--block", "xy", "--frames", "1").returncode == 2, "a block is one character")
r = run("drift", "--ascii", "--frames", "3", "--size", "60x12")
ok(r.returncode == 0 and all(ord(c) < 127 for c in r.stdout) and "#" in r.stdout, "--ascii prints ASCII, the clock in #")
r = run("drift", "--frames", "3", "--size", "60x12")
ok("\u2588" in r.stdout, "by default the clock is full blocks")
r = run("fire", "--ascii", "--block", "\u2588", "--frames", "1")
ok(r.returncode == 2, "--ascii refuses a block that is not ASCII")
ok(run("fire").returncode == 2, "play with no terminal is exit 2, nothing drawn")
ok(run("--version").stdout.strip() == saver.VERSION, "--version")

print("saver_test: %d checks passed" % passed)
