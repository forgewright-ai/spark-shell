#!/usr/bin/env python3
"""Prove spark's bar on a headless sway of its own, through spark-shell: python3 test/bar_desktop_proof.py [DIRECTORY].

DIRECTORY takes the screens, and while the proof runs a folder of its work: a throwaway HOME, a runtime folder, a
temporary one, the stand-ins. Nothing of the machine is touched: the sway is a headless one the proof starts and
ends by its pid, the sound tool is a stand-in that keeps its state in files (wpctl's answers; pactl, amixer and
pw-dump are stand-ins too, and so are tmux and spark, which a verb could reach), the dialog's terminal is recorded
and never opened, the machine's wire, wifi and battery are a fixture, and the palette is the proof's own, never a
theme of the machine's.

Three things the home sets so that every family's sway and fonts give the same answers. The pointer is a theme of
the proof's with no image: it hovers and clicks, and no capture has a cursor in it. The home's fontconfig asks for
subpixel rendering, as Ubuntu's does for every home: the bar draws its text gray all the same, so a color read off
the screen is the color it was handed. And the proof reaps what its session orphans, as an init does: a
container's first process reaps none, and a dead process nobody reaped still answers kill -0.

sway's own lines for the bar are read from the template: exec spark-shell bar start, the key bound to spark-shell
bar keys, and the resize mode. So the bar under proof is the one spark-shell starts, under its keeper, reading the
real spark-shell bar status. The five gates of the bar's review, each check named by its gate:

1 identity       the mark is the asset's own pixels at 24 px, the dark one or the light one by the ground; the
                 line's glyphs are a font's; a workspace's number stands in the family's key frame, stone's
                 angle brackets, star's braces, banner's square brackets, read from the screen
2 behavior       by the pointer and by the keys: out's sign mutes, its gauge sets the level at the click, takes
                 the wheel and Home, End, Left and Right, its percent opens its section; the mic's gauge and
                 sign; a workspace shown; a module's section opened; the mark opens home
3 states         no sound device, a change that fails, the status shell killed while its jobs hold its pipe and
                 back with none of them left, the bar ended with ABRT and started again by its keeper, stopped
                 on purpose, loading before the first line, and a binding mode
4 accessibility  every text role at 4.5 to 1 on its surface, by the palette and by the screen; the keys go
                 through every target once, left to right; every control has a name; nothing moves by itself
5 geometry       36 px, 16 px text, a 24 px mark, by the state file and by the screen; no cell moves with its
                 value; pins; a narrow screen and what goes first; the bottom edge; two screens

Then the look, which travels in the status line: a light palette written while the bar runs, a palette looked at
and a theme applied through spark-shell, each worn by the same process; the mark and the contrast again on the
light ground. spark-bar is SPARK_SHELL_BAR, else component/bar/target's release build. Needs sway, swaymsg, foot,
grim, wtype, jq and python3; fc-list where there is one."""
import atexit
import collections
import ctypes
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import traceback
import zlib

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "test"))
from home_desktop_proof import Pointer  # noqa: E402  the repo's virtual pointer: motion, button, axis, frame

W, H = 1920, 1080
OUT = "HEADLESS-1"
BAR, TEXT, MARK = 36, 16, 24                 # the sketch's sizes at 12 points: the bar, its text, the mark
OVERFLOW = "wifi bat mic out clock"          # the config's order here, not the default one; lan is not named
LOOK = ("fg", "accent", "muted", "ground", "lit", "attention", "alpha")   # the look block's fields, as BAR_FG and the rest
FAMILIES = (("stone", "\u27e8", "\u27e9"), ("star", "{", "}"), ("banner", "[", "]"))
# the proof's own palettes, a dark ground and a light one: BG, FG, ACCENT, MUTED and the sixteen slots
PALETTES = {
    "dark": ("1f2430", "e6e9ef", "5fb3ff", "bcc4d0",
             "171b24 ff6b6b 7ee081 ffcc66 5fb3ff c79bff 5fd7d7 c8ccd4 6b7480 ff8a8a 9bea9d ffd98a 8cc8ff d8b8ff 8ae6e6 ffffff"),
    "light": ("f4f1ea", "2b2f38", "1a5fb4", "4a505c",
              "2b2f38 b3261e 2f6f2f 7a4f00 1a5fb4 7b3fa0 0e6b6b d9d5cc 5c6370 c0392b 3c8a3c 8f6200 2f76d0 8d50b5 168080 f4f1ea"),
}
WPCTL = r"""#!/bin/sh
# the proof's sound tool: wpctl's answers from files, every change written to one
d=${PROOF_SND:?}
i=0; while [ -e "$d/slow" ] && [ "$i" -lt 900 ]; do sleep 0.1; i=$((i + 1)); done   # slow: no answer until the proof lets go
[ ! -e "$d/down" ] || { echo 'Could not connect to PipeWire' >&2; exit 1; }
side() { case $1 in *SINK*) echo out ;; *) echo mic ;; esac; }
case ${1:-} in
    status) printf 'Audio\n |- Sinks:\n |  *   50. Proof Speakers [vol: 0.40]\n |\n |- Sources:\n |  *   52. Proof Microphone [vol: 0.50]\n |\n' ;;
    get-volume) k=$(side "$2"); l=$(cat "$d/$k.level" 2>/dev/null || echo 40); m=''; [ ! -e "$d/$k.muted" ] || m=' [MUTED]'
        printf 'Volume: %d.%02d%s\n' "$((l / 100))" "$((l % 100))" "$m" ;;
    set-mute|set-volume) echo "$*" >> "$d/log"
        [ ! -e "$d/fail" ] || exit 1
        k=$(side "$*")
        if [ "$1" = set-mute ]; then
            case $3 in 1) : > "$d/$k.muted" ;; 0) rm -f "$d/$k.muted" ;; toggle) if [ -e "$d/$k.muted" ]; then rm -f "$d/$k.muted"; else : > "$d/$k.muted"; fi ;; esac
        else
            l=$(cat "$d/$k.level" 2>/dev/null || echo 40); for v in "$@"; do :; done
            case $v in *%+) l=$((l + ${v%\%+})) ;; *%-) l=$((l - ${v%\%-})) ;; *%) l=${v%\%} ;; esac
            [ "$l" -le 100 ] || l=100; [ "$l" -ge 0 ] || l=0
            echo "$l" > "$d/$k.level.new" && mv "$d/$k.level.new" "$d/$k.level"
        fi ;;
    *) echo "$*" >> "$d/log" ;;
esac
"""
FOOT = """#!/bin/sh
# the proof's opener: the dialog's terminal is recorded and never opened; any other foot is the real one
case " $* " in *" --app-id spark-dialog "*) printf '%%s\\n' "$*" >> "${PROOF_OPENED:?}"; exit 0 ;; esac
exec %s "$@"
"""
# ends the proof's sway, by its pid, should the proof itself be killed before it can
GUARD = """import os, signal, sys, time
proof, sway, born, mark = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4].encode()
while True:
    try:
        os.kill(proof, 0)
    except OSError:
        break
    time.sleep(1)
try:
    if open("/proc/%d/stat" % sway).read().rsplit(")", 1)[1].split()[19] == born:   # the same process, not its pid again
        os.kill(sway, signal.SIGTERM)
except (OSError, IndexError):
    pass
time.sleep(2)
for pid in [int(n) for n in os.listdir("/proc") if n.isdigit() and int(n) != os.getpid()]:   # what did not end with it: the keyboard
    try:
        if mark in open("/proc/%d/environ" % pid, "rb").read().split(b"\\0"):
            os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
"""
# an Xcursor file of one transparent pixel: the proof's pointer has no image, so no capture has one in it
NO_IMAGE = (b"Xcur" + struct.pack("<3I", 16, 0x10000, 1) + struct.pack("<3I", 0xfffd0002, 24, 28)
            + struct.pack("<9I", 36, 0xfffd0002, 24, 1, 1, 1, 0, 0, 0) + struct.pack("<I", 0))
failed = 0
gate = "lifecycle"
tally = collections.OrderedDict()
on_failure = []


def ok(cond, what, detail=""):
    global failed
    counts = tally.setdefault(gate, [0, 0])
    counts[0 if cond else 1] += 1
    line = "  %s %s: %s%s" % ("ok  " if cond else "FAIL", gate, what, "" if cond else "   " + str(detail))
    print(line.encode("ascii", "backslashreplace").decode(), flush=True)   # a workspace's name in a detail is no ASCII
    if not cond:
        failed += 1
        for hook in on_failure:
            hook()
    return bool(cond)


def enter(name, words):
    global gate
    gate = name
    print("%s -- %s" % (name, words), flush=True)


def wait_for(read, description, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = read()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("timed out: " + description)


def settle(read, seconds=8):
    """What `read` says once it says yes, or at the end of the wait: for a check that reports what it saw."""
    end = time.time() + seconds
    value = read()
    while not value and time.time() < end:
        time.sleep(0.05)
        value = read()
    return value


def ppm(data):
    """A binary PPM (P6) as (width, height, bytes): grim writes one with -t ppm."""
    parts, i = [], 0
    while len(parts) < 4:
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        parts.append(data[i:j])
        i = j
    return int(parts[1]), int(parts[2]), data[i + 1:]


def far(a, b):
    return max(abs(p - q) for p, q in zip(a, b))


def near(a, b, tolerance=6):
    return far(a, b) <= tolerance


def rgb(hexa):
    hexa = hexa.lstrip("#")
    return tuple(int(hexa[i:i + 2], 16) for i in (0, 2, 4))


def contrast(a, b):
    """WCAG's contrast of two colors, 1 to 21."""
    def luminance(color):
        linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in (c / 255.0 for c in color)]
        return sum(p * q for p, q in zip(linear, (.2126, .7152, .0722)))
    low, high = sorted((luminance(a), luminance(b)))
    return (high + .05) / (low + .05)


def dark(color):
    """Whether a ground is dark, as spark-shell and the bar say it (theme_is_dark)."""
    return (color[0] * 299 + color[1] * 587 + color[2] * 114) // 1000 < 128


class Img:
    """A piece of the screen."""

    def __init__(self, w, h, data):
        self.w, self.h, self.data = w, h, data

    def px(self, x, y):
        o = (y * self.w + x) * 3
        return tuple(self.data[o:o + 3])

    def all(self):
        return [self.px(x, y) for y in range(self.h) for x in range(self.w)]

    def ground(self):
        """The color most of it is."""
        return collections.Counter(self.all()).most_common(1)[0][0]

    def cut(self, x0, x1):
        """Its columns from x0 up to x1, a piece of its own."""
        return Img(x1 - x0, self.h, b"".join(self.data[(y * self.w + x0) * 3:(y * self.w + x1) * 3] for y in range(self.h)))

    def top(self, ground=None):
        """How far its strongest pixel is from the ground."""
        ground = ground or self.ground()
        return max(far(c, ground) for c in set(self.all()))

    def ink(self, ground=None, of=None):
        """Its ink, as (x, y): the pixels a third of the way or more from the ground to its strongest pixel, or
        to a wider piece's (`of`, its top)."""
        ground = ground or self.ground()
        top = self.top(ground) if of is None else of
        if top < 24:
            return set()
        return {(x, y) for y in range(self.h) for x in range(self.w) if far(self.px(x, y), ground) * 3 >= top}

    def strongest(self, ground=None):
        ground = ground or self.ground()
        return max(set(self.all()), key=lambda c: far(c, ground))

    def inked(self, ground, color):
        """Its ink against a color it should be drawn in: (whether every pixel is that color thinned by the
        ground, one measure for the three channels, as a gray face draws it: no colored edge of a subpixel
        face, no other color; how far its strongest pixel goes, 1 the color itself)."""
        span = [color[i] - ground[i] for i in range(3)]
        wide = max(range(3), key=lambda i: abs(span[i]))
        if abs(span[wide]) < 24:
            return False, 0.0
        gray, most = True, 0.0
        for c in set(self.all()):
            t = (c[wide] - ground[wide]) / float(span[wide])
            gray = gray and -0.03 <= t <= 1.03 and all(abs(ground[i] + t * span[i] - c[i]) <= 3 for i in range(3))
            most = max(most, t)
        return gray, most


def glyphs(m):
    """A mask split at its blank columns, the glyphs of a line left to right: (the column a glyph starts at, the
    glyph from its own corner)."""
    cols = sorted({x for x, _ in m})
    groups, run = [], []
    for x in cols:
        if run and x - run[-1] > 1:
            groups.append(run)
            run = []
        run.append(x)
    if run:
        groups.append(run)
    out = []
    for g in groups:
        part = {(x, y) for x, y in m if g[0] <= x <= g[-1]}
        lx, ly = min(x for x, _ in part), min(y for _, y in part)
        out.append((lx, {(x - lx, y - ly) for x, y in part}))
    return out


def blobs(m):
    """The glyphs of a mask alone."""
    return [part for _, part in glyphs(m)]


def flip(m):
    wide = max(x for x, _ in m)
    return {(wide - x, y) for x, y in m}


def likeness(a, b):
    """How alike two masks are: their overlap over their union, at the best shift of a pixel."""
    if not a or not b:
        return 0.0
    best = 0.0
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            moved = {(x + dx, y + dy) for x, y in a}
            best = max(best, len(moved & b) / float(len(moved | b)))
    return best


def read_png(path):
    """An 8-bit RGBA PNG as (width, height, rows): the mark's files."""
    data = Path(path).read_bytes()
    i, idat, head = 8, b"", None
    while i < len(data):
        n, kind = struct.unpack(">I4s", data[i:i + 8])
        body = data[i + 8:i + 8 + n]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        i += 12 + n
    w, h, depth, color, _, _, lace = head
    if (depth, color, lace) != (8, 6, 0):
        raise ValueError("%s is not an 8-bit RGBA PNG" % path)
    raw, stride, rows, prev = zlib.decompress(idat), w * 4, [], bytearray(w * 4)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, rows


def drawn(asset, size, box, center, ground):
    """A picture scaled to size by size, centered at `center` in a box (w, h), over a ground: rows of colors."""
    aw, ah, rows = asset
    out = [[ground] * box[0] for _ in range(box[1])]
    x0, y0, k = center[0] - size / 2.0, center[1] - size / 2.0, aw / float(size)
    for yy in range(box[1]):
        for xx in range(box[0]):
            u, v = (xx + 0.5 - x0) * k - 0.5, (yy + 0.5 - y0) * k - 0.5
            if u <= -1 or v <= -1 or u >= aw or v >= ah:
                continue
            ui, vi = int(u // 1), int(v // 1)
            fu, fv = u - ui, v - vi
            acc = [0.0, 0.0, 0.0, 0.0]
            for dy, wy in ((0, 1 - fv), (1, fv)):
                for dx, wx in ((0, 1 - fu), (1, fu)):
                    sx, sy = ui + dx, vi + dy
                    if 0 <= sx < aw and 0 <= sy < ah:
                        r, g, b, a = rows[sy][sx * 4:sx * 4 + 4]
                        part = wx * wy * a / 255.0
                        acc = [acc[0] + r * part, acc[1] + g * part, acc[2] + b * part, acc[3] + part]
            cover = min(acc[3], 1.0)
            out[yy][xx] = tuple(int(acc[i] + ground[i] * (1 - cover) + 0.5) for i in range(3))
    return out


def apart(img, picture):
    """The mean difference of a piece of the screen and a picture, a channel, 0 to 255."""
    total = sum(abs(p - q) for y in range(img.h) for x in range(img.w) for p, q in zip(img.px(x, y), picture[y][x]))
    return total / float(img.w * img.h * 3)


def level_at(inside, width):
    """The level a click `inside` pixels into a gauge of that width sets, as src/bar.sh's bar_click has it: to 5."""
    return max(0, min(100, (inside * 100 // width + 2) // 5 * 5))


def left_out(width, cell, spaces, blocks, overflow):
    """What a bar of that width leaves out, by the rule spark-bar --help states: the optional blocks first, then
    whole modules, the ones BAR_OVERFLOW does not name before the named ones, from the left, then in its order.
    blocks: (module, id, width, optional) in the line's order; spaces: the workspaces' width.
    -> (the ids left out in the order they go, the ids kept, whether the cell for the rest stands)."""
    left, right, kept, more, out = cell + MARK + cell, width - cell, list(blocks), False, []

    def need():
        w = sum(b[2] for b in kept) + sum(cell if a[0] == b[0] else 2 * cell for a, b in zip(kept, kept[1:]))
        if more:
            w += cell + (2 * cell if kept else 0)
        return left + spaces + (2 * cell if w and spaces else 0) + w
    modules = list(collections.OrderedDict.fromkeys(b[0] for b in blocks))
    order = [m for m in modules if m not in overflow] + sorted((m for m in modules if m in overflow), key=overflow.index)
    for m in order:
        while need() > right:
            b = next((b for b in kept if b[0] == m and b[3]), None)
            if b is None:
                break
            kept.remove(b)
            out.append(b[1])
        if need() <= right:
            break
    for m in order:
        if need() <= right:
            break
        if any(b[0] == m for b in kept):
            kept = [b for b in kept if b[0] != m]
            out.append(m)
            more = True
    return out, [b[1] for b in kept], more


class Target:
    def __init__(self, f):
        self.id, self.kind, self.state, self.name = f[2], f[7], f[8], f[10]
        self.x, self.y, self.w, self.h = (int(n) for n in f[3:7])
        self.flags = set() if f[9] == "-" else set(f[9].split(","))

    @property
    def rect(self):
        return self.x, self.y, self.w, self.h

    @property
    def mid(self):
        return self.x + self.w // 2

    @property
    def module(self):
        return self.id.split(".")[0]


class Strip:
    """One output's bar in the state file."""

    def __init__(self, f):
        self.name, self.width, self.height, self.edge, self.scale = f[1], int(f[2]), int(f[3]), f[4], int(f[5])
        self.targets, self.dropped = [], []


class State:
    """The bar's state file, read: the status, then each output's bar, its targets and what it left out."""

    def __init__(self, text):
        self.text, self.status, self.mode, self.outputs, self.odd = text, "", "", collections.OrderedDict(), []
        for line in text.splitlines():
            f = line.split("\t")
            try:
                if f == ["bar", "1"]:
                    continue
                if f[0] == "status" and len(f) == 2:
                    self.status = f[1]
                elif f[0] == "mode" and len(f) == 2:
                    self.mode = f[1]
                elif f[0] == "output" and len(f) == 6:
                    self.outputs[f[1]] = Strip(f)
                elif f[0] == "target" and len(f) == 11:
                    self.outputs[f[1]].targets.append(Target(f))
                elif f[0] == "dropped" and len(f) == 3:
                    self.outputs[f[1]].dropped.append(f[2])
                else:
                    self.odd.append(line)
            except (KeyError, ValueError):
                self.odd.append(line)

    def bar(self, output=OUT):
        return self.outputs.get(output)

    def targets(self, output=OUT):
        strip = self.outputs.get(output)
        return strip.targets if strip else []

    def find(self, ident, output=OUT):
        return next((t for t in self.targets(output) if t.id == ident), None)

    def named(self, ident, output=OUT):
        t = self.find(ident, output)
        return t.name if t else None

    def ids(self, output=OUT):
        return [t.id for t in self.targets(output)]

    def rects(self, output=OUT):
        return collections.OrderedDict((t.id, t.rect) for t in self.targets(output))

    def focused(self, output=OUT):
        return next((t.id for t in self.targets(output) if "focused" in t.flags), None)

    def brief(self):
        bars = ["%s %dx%d %s: %s%s" % (b.name, b.width, b.height, b.edge,
                                         " ".join(t.id + ("[%s %s]" % (t.state, ",".join(sorted(t.flags))) if t.flags or t.state != "ok" else "") for t in b.targets),
                                         (" left out: " + " ".join(b.dropped)) if b.dropped else "") for b in self.outputs.values()]
        return "status %s%s; %s" % (self.status, (", mode " + self.mode) if self.mode else "", "; ".join(bars))


def moved(a, b):
    """Where two sets of rectangles differ, for a check's words."""
    return {k: (a.get(k), b.get(k)) for k in list(a) + [k for k in b if k not in a] if a.get(k) != b.get(k)}


def proc(pid, name):
    return Path("/proc/%d/%s" % (pid, name)).read_bytes()


def cmdline(pid):
    try:
        return [w.decode("utf-8", "replace") for w in proc(pid, "cmdline").split(b"\0")[:-1]]
    except OSError:
        return []


def environ_of(pid):
    try:
        return dict(e.decode("utf-8", "replace").split("=", 1) for e in proc(pid, "environ").split(b"\0") if b"=" in e)
    except OSError:
        return {}


def stat_of(pid, fields=(0, 1)):
    """A process's state letter and its parent's pid, or other fields of its stat after its name: 2 its process
    group, 19 its start time; None each when it is gone."""
    try:
        after = proc(pid, "stat").decode("utf-8", "replace").rsplit(")", 1)[1].split()
        return tuple(after[i] if i in (0, 19) else int(after[i]) for i in fields)
    except (OSError, IndexError, ValueError):
        return (None,) * len(fields)


def alive(pid):
    return bool(pid) and stat_of(pid)[0] not in (None, "Z")


def group_of(pid):
    return stat_of(pid, (2,))[0]


def members(group):
    """The processes of a process group that still run."""
    return [int(e.name) for e in Path("/proc").iterdir() if e.name.isdigit() and group_of(int(e.name)) == group and alive(int(e.name))]


def bar_binary():
    named = os.environ.get("SPARK_SHELL_BAR")
    if named:
        if not os.access(named, os.X_OK):
            raise SystemExit("SPARK_SHELL_BAR names no spark-bar build: " + named)
        return Path(named).resolve()
    for candidate in (REPO / "component/bar/target/release/spark-bar", REPO / "component/bar/target/x86_64-unknown-linux-gnu/release/spark-bar"):
        if candidate.is_file():
            return candidate
    raise SystemExit("no spark-bar: build component/bar/ (cargo build --release) or name it in SPARK_SHELL_BAR")


class Desk:
    """The proof's desktop: its folders, its stand-ins, its sway, and what it reads and sends there."""

    def __init__(self, evidence, binary):
        self.evidence, self.binary = evidence, binary
        self.work = Path(tempfile.mkdtemp(prefix="work.", dir=str(evidence)))
        self.home, self.run, self.snd = self.work / "home", self.work / "run", self.work / "snd"
        if len(str(self.run)) > 70:   # a socket's path holds 107 bytes: sway's and the display's are under it
            shutil.rmtree(str(self.work), ignore_errors=True)
            raise SystemExit("%s is too long a path for the sockets of a sway under it: name a shorter directory" % evidence)
        self.settings, self.theme = self.home / ".config/spark-shell/config", self.home / ".config/spark/theme.env"
        self.state_file, self.lock, self.log_file = (self.run / ("spark-shell-bar." + kind) for kind in ("state", "pid", "log"))
        self.loop_file = self.home / ".local/state/spark-shell/bar.pid"
        self.opened_file = self.work / "opened"
        self.shell_path = str(REPO / "spark-shell")
        self.children, self.pointer, self.guard, self.stopped, self.left, self.reaps = [], None, None, False, None, False
        self.seen, self.shots, self.kept, self.space = set(), 0, 0, (W, H)
        self.stage()

    def stage(self):
        fake, sys_, proc_ = self.work / "bin", self.work / "sys", self.work / "proc"
        for folder in (self.settings.parent, self.theme.parent, self.work / "tmp", fake, self.snd, self.work / "pts", self.work / "dev",
                       self.work / "root", sys_ / "class/net/eth0", sys_ / "class/net/wlan0/wireless", sys_ / "class/power_supply/BAT0", proc_ / "net"):
            folder.mkdir(parents=True)
        self.run.mkdir(mode=0o700)
        self.real_foot = shutil.which("foot")
        tools = {"wpctl": WPCTL, "foot": FOOT % self.real_foot, "pw-dump": "#!/bin/sh\necho '[]'\n", "ip": "#!/bin/sh\nexit 0\n"}
        # no other sound system, the kernel's own link quality, and nothing of the machine's that a verb could reach: its tmux, its spark
        tools.update((name, "#!/bin/sh\nexit 1\n") for name in ("pactl", "amixer", "iw", "tmux", "spark"))
        for name, text in tools.items():
            (fake / name).write_text(text)
            (fake / name).chmod(0o755)
        # the machine: a wire up, wifi at 70, a battery at 64, so the line has modules enough to leave some out
        for name, text in (("class/net/eth0/device", ""), ("class/net/eth0/type", "1\n"), ("class/net/eth0/carrier", "1\n"), ("class/net/eth0/operstate", "up\n"),
                           ("class/net/wlan0/device", ""), ("class/net/wlan0/type", "1\n"), ("class/net/wlan0/operstate", "up\n"),
                           ("class/power_supply/BAT0/type", "Battery\n"), ("class/power_supply/BAT0/capacity", "64\n"), ("class/power_supply/BAT0/status", "Discharging\n")):
            (sys_ / name).write_text(text)
        (proc_ / "net/wireless").write_text("Inter-| sta-|   Quality        |\n face | tus | link level noise |\n"
                                            " wlan0: 0000   49.  -61.  -256        0      0      0      0      0        0\n")
        # the pointer: a theme of the proof's with no image (the pointer stays where it is put, and a target under it
        # is still lit), named in the config so a look applied by spark-shell keeps it
        cursors = self.home / ".local/share/icons/proof-blank/cursors"
        cursors.mkdir(parents=True)
        (cursors.parent / "index.theme").write_text("[Icon Theme]\nName=proof-blank\n")
        for name in ("default", "left_ptr", "text", "xterm"):
            (cursors / name).write_bytes(NO_IMAGE)
        # 12 points is the sketch's size; ALPHA 1 so the bar's ground is the palette's own color on the screen
        self.config_text = "DESKTOP=sway\nALPHA=1\nBAR_TEXT=12\nWALLPAPER=none\nPOINTER=proof-blank 24\nBAR_OVERFLOW=%s\n" % OVERFLOW
        self.settings.write_text(self.config_text)
        # the home asks fontconfig for subpixel rendering, with Ubuntu's three settings (slight hinting, rgb, the default
        # lcd filter), as that system asks it for every home: the bar's text stays gray
        (self.home / ".config/fontconfig").mkdir()
        (self.home / ".config/fontconfig/fonts.conf").write_text(
            '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n<fontconfig>\n <match target="font">\n'
            + "".join('  <edit name="%s" mode="assign"><%s>%s</%s></edit>\n' % (name, kind, value, kind) for name, kind, value in
                      (("antialias", "bool", "true"), ("hinting", "bool", "true"), ("hintstyle", "const", "hintslight"), ("rgba", "const", "rgb"), ("lcdfilter", "const", "lcddefault")))
            + ' </match>\n</fontconfig>\n')
        self.palette("dark")
        self.sound(40, False, 50, False)
        env = {k: v for k, v in os.environ.items() if k in ("PATH", "USER", "LOGNAME", "SHELL", "LANG", "TZ") or k.startswith("LC_")}
        env.update({"PATH": str(fake) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(self.home),
                    "XDG_CONFIG_HOME": str(self.home / ".config"), "XDG_STATE_HOME": str(self.home / ".local/state"),
                    "XDG_DATA_HOME": str(self.home / ".local/share"), "XDG_CACHE_HOME": str(self.home / ".cache"),
                    "XDG_RUNTIME_DIR": str(self.run), "TMPDIR": str(self.work / "tmp"), "TMUX_TMPDIR": str(self.work / "tmp"),
                    "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
                    "XCURSOR_PATH": str(self.home / ".local/share/icons"), "XCURSOR_THEME": "proof-blank", "XCURSOR_SIZE": "24",
                    "SPARK_SHELL_BAR": str(self.binary), "SPARK_SHELL_PTS_DIR": str(self.work / "pts"), "SPARK_SHELL_ROOT": str(self.work / "root"),
                    "SPARK_SHELL_SYS": str(sys_), "SPARK_SHELL_PROC": str(proc_), "SPARK_SHELL_DEV": str(self.work / "dev"),
                    "SPARK_SHELL_SEMANTIC_URL": "none", "SPARK_SHELL_DIALOG_URL": "none", "SPARK_SHELL_FONT_URL": "none", "SPARK_SHELL_NO_APPLY": "1",
                    "PROOF_SND": str(self.snd), "PROOF_OPENED": str(self.opened_file)})
        self.env = env
        # sway's lines for the bar, as the template has them: its start, its key, and the resize mode
        template = (REPO / "template/.config/sway/config").read_text().splitlines()
        self.own = [line[len("@BAR_OWN@"):].replace("@REPO@", str(REPO)) for line in template if line.startswith("@BAR_OWN@")]
        self.keys_line = [line.replace("@REPO@", str(REPO)) for line in template if line.startswith("bindsym") and line.endswith("spark-shell bar keys")]
        self.keys_key = (re.findall(r"^bindsym \$mod\+(\w+) exec ", " ".join(self.keys_line)) or [""])[0]
        at = template.index('mode "resize" {') if 'mode "resize" {' in template else None
        self.mode_lines = [] if at is None else template[at:template.index("}", at) + 1] + [line for line in template if line == 'bindsym $mod+r mode "resize"']
        self.config = self.work / "sway.conf"
        self.config.write_text("set $mod Mod4\noutput %s mode %dx%d\nxwayland disable\ndefault_border pixel 2\nfocus_follows_mouse no\nmouse_warping none\n"
                               "seat * xcursor_theme proof-blank 24\n%s\n" % (OUT, W, H, "\n".join(self.keys_line + self.mode_lines + self.own)))

    def palette(self, name):
        bg, fg, accent, muted, slots = PALETTES[name]
        self.pal = {"name": name, "BG": bg, "FG": fg, "ACCENT": accent, "MUTED": muted, "ANSI": slots.split()}
        self.theme.write_text("".join("THEME_%s=#%s\n" % (k, self.pal[k]) for k in ("BG", "FG", "ACCENT", "MUTED"))
                              + "".join("THEME_ANSI_%d=#%s\n" % (i, c) for i, c in enumerate(self.pal["ANSI"])))

    def start(self):
        # what the session orphans comes to the proof, which reaps it as an init does: a container's first process
        # reaps none, and a dead process nobody reaped still answers kill -0 (the status' watcher asks that)
        try:
            self.reaps = ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0   # PR_SET_CHILD_SUBREAPER
        except (OSError, AttributeError):
            self.reaps = False
        log = open(str(self.work / "sway.log"), "w")
        sway = subprocess.Popen(["sway", "-c", str(self.config)], env=self.env, cwd=str(self.work), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=log)
        self.children.append(sway)
        self.guard = subprocess.Popen([sys.executable, "-I", "-c", GUARD, str(os.getpid()), str(sway.pid), str(stat_of(sway.pid, (19,))[0]),
                                       "XDG_RUNTIME_DIR=" + str(self.run)], env=self.env,
                                      start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sock = wait_for(lambda: next(iter(self.run.glob("sway-ipc.*.sock")), None), "sway's socket")
        display = wait_for(lambda: next((p.name for p in self.run.glob("wayland-*") if not p.name.endswith(".lock")), None), "the display")
        self.env.update({"SWAYSOCK": str(sock), "WAYLAND_DISPLAY": display})
        self.pointer = Pointer(self.env)
        # a keyboard on the seat for the whole proof, as the pad's proof keeps one: a headless sway has none
        self.children.append(subprocess.Popen(["wtype", "-s", "600000"], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))

    def reap(self):
        """The dead the session left to the proof, reaped; never a child the proof started itself."""
        own = {child.pid for child in self.children + ([self.guard] if self.guard else [])}
        for entry in Path("/proc").iterdir():
            if entry.name.isdigit() and int(entry.name) not in own and stat_of(int(entry.name)) == ("Z", os.getpid()):
                try:
                    os.waitpid(int(entry.name), os.WNOHANG)
                except OSError:
                    pass

    def ours(self):
        """The processes that carry this proof's runtime folder: its sway's, and what they started."""
        mark, found = ("XDG_RUNTIME_DIR=" + str(self.run)).encode(), []
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit() or int(entry.name) == os.getpid():
                continue
            try:
                if mark in (entry / "environ").read_bytes().split(b"\0") and stat_of(int(entry.name))[0] not in (None, "Z"):
                    found.append(int(entry.name))
            except OSError:
                continue
        return found

    def stop(self):
        """The end, on every way out: the proof's sway ended by its pid, what it started gone with it, the work removed."""
        if self.stopped:
            return
        self.stopped = True
        if self.pointer:
            self.pointer.close()
        if self.guard:
            self.guard.terminate()
        for child in reversed(self.children):
            child.terminate()
        for child in self.children + ([self.guard] if self.guard else []):
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
        settle(lambda: self.reap() or not self.ours(), 6)
        self.left = [(pid, " ".join(cmdline(pid))[:120]) for pid in self.ours()]   # what did not end with the sway by itself
        for sig in (signal.SIGTERM, signal.SIGKILL):
            pids = self.ours()
            for pid in pids:
                try:
                    os.kill(pid, sig)
                except OSError:
                    pass
            if pids:
                settle(lambda: not self.ours(), 2)
        if failed:
            self.keep_log()
        for _ in range(3):
            shutil.rmtree(str(self.work), ignore_errors=True)
            if not self.work.exists():
                break
            time.sleep(0.5)

    def keep_log(self):
        try:
            shutil.copyfile(str(self.log_file), str(self.evidence / "failure-bar.log"))
        except OSError:
            pass

    def keep_failure(self):
        """A failed check leaves the state file, the bar's log and the screen in the directory; the first few."""
        if self.stopped or self.kept >= 6:
            return
        self.kept += 1
        self.keep_log()
        try:
            shutil.copyfile(str(self.state_file), str(self.evidence / ("failure-%02d-bar.state" % self.kept)))
        except OSError:
            pass
        try:
            subprocess.run(["grim", str(self.evidence / ("failure-%02d.png" % self.kept))], env=self.env, capture_output=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            pass

    # --- what it reads
    def state(self):
        try:
            text = self.state_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
        if not text:
            return None
        self.seen.add(text)
        return State(text)

    def until(self, test, what, seconds=20):
        """The state file once it says `test`; a timeout says what was waited for and what the file said."""
        end, s = time.time() + seconds, None
        while time.time() < end:
            s = self.state()
            try:
                if s is not None and test(s):
                    return s
            except (AttributeError, TypeError):   # a target the test names is not there yet
                pass
            time.sleep(0.04)
        raise AssertionError("waited %ds for %s; the state file says: %s" % (seconds, what, s.brief() if s else "nothing, there is none"))

    def bar_pid(self):
        try:
            pid = int(self.lock.read_text().split()[0])
        except (OSError, ValueError, IndexError):
            return None
        return pid if alive(pid) else None

    def loop_pid(self):
        """The status loop the bar runs: spark-shell bar status writes its pid here, for a redraw."""
        try:
            pid = int(self.loop_file.read_text().split()[0])
        except (OSError, ValueError, IndexError):
            return None
        return pid if alive(pid) else None

    def bar_env(self):
        pid = self.bar_pid()
        return environ_of(pid) if pid else {}

    def sway(self, *words):
        return subprocess.run(["swaymsg", *words], env=self.env, capture_output=True, encoding="utf-8", errors="replace", timeout=10).stdout

    def ask(self, kind):
        return json.loads(self.sway("-r", "-t", kind) or "null") or []

    def names(self):
        return {w["num"]: w["name"] for w in self.ask("get_workspaces")}

    def focused_space(self):
        return next((w["num"] for w in self.ask("get_workspaces") if w.get("focused")), None)

    def node(self, pid):
        def walk(n):
            yield n
            for key in ("nodes", "floating_nodes"):
                for child in n.get(key, []):
                    yield from walk(child)
        return next((n for n in walk(self.ask("get_tree") or {}) if n.get("pid") == pid), None)

    def shell(self, *words, **more):
        env = dict(self.env)
        env.update(more)
        done = subprocess.run(["sh", self.shell_path, *words], env=env, stdin=subprocess.DEVNULL, capture_output=True, encoding="utf-8", errors="replace", timeout=90)
        done.said = (done.stdout + done.stderr).strip()
        return done

    def line(self):
        """The status line as spark's bar is handed it: the blocks of spark-shell bar status --once."""
        try:
            return json.loads(self.shell("bar", "status", "--once", SPARK_BAR="1").stdout or "[]")
        except ValueError:
            return []

    def look(self):
        """The look the line carries for spark's bar: its block named look, the six colors and the alpha."""
        return next((b for b in self.line() if b.get("name") == "look"), {})

    def roles(self):
        """The colors the bar draws in, by role, as the line's look says them now: the palette's own text, accent,
        ground and attention, the shade the shell makes for the hover chip, and the muted it lifts until it reads."""
        look, env = self.look(), self.bar_env()
        return {k: rgb(look.get(k) or env.get("BAR_" + k.upper()) or "000000") for k in LOOK[:-1]}

    def grab(self, x, y, w, h):
        # grim ended by a signal is the capture's fall, not the bar's (a container's small shared memory can run
        # out for a moment while a wallpaper is drawn): it is asked again, three times at most
        for left in (2, 1, 0):
            got = subprocess.run(["grim", "-t", "ppm", "-g", "%d,%d %dx%d" % (x, y, w, h), "-"], env=self.env, capture_output=True, timeout=20)
            if got.returncode == 0:
                return Img(*ppm(got.stdout))
            if got.returncode > 0 or not left:
                got.check_returncode()
            time.sleep(0.5)

    def shot(self, name, output=OUT):
        self.shots += 1
        subprocess.run(["grim", "-o", output, str(self.evidence / ("%02d-%s.png" % (self.shots, name)))], env=self.env, capture_output=True, timeout=20)

    def opened(self):
        try:
            return self.opened_file.read_text().splitlines()
        except OSError:
            return []

    def log(self):
        try:
            return (self.snd / "log").read_text().splitlines()
        except OSError:
            return []

    def level(self, side):
        try:
            return int((self.snd / (side + ".level")).read_text())
        except (OSError, ValueError):
            return None

    def muted(self, side):
        return (self.snd / (side + ".muted")).exists()

    def pins(self):
        return ([line[len("BAR_PINS="):] for line in self.settings.read_text().splitlines() if line.startswith("BAR_PINS=")] or [None])[-1]

    # --- what it sends
    def sound(self, out, muted, mic, mic_muted):
        """The sound tool's state, set from outside the bar, as another program's change is."""
        for side, level, off in (("out", out, muted), ("mic", mic, mic_muted)):
            (self.snd / (side + ".level")).write_text("%d\n" % level)
            if off:
                (self.snd / (side + ".muted")).write_text("")
            elif (self.snd / (side + ".muted")).exists():
                (self.snd / (side + ".muted")).unlink()

    def flag(self, name, on):
        if on:
            (self.snd / name).write_text("")
        elif (self.snd / name).exists():
            (self.snd / name).unlink()

    def nudge(self):
        """A line now, as spark-shell asks its loop for one after any change (bar_redraw): SIGUSR1 to the loop."""
        pid = self.loop_pid()
        if pid:
            try:
                os.kill(pid, signal.SIGUSR1)
            except OSError:
                pass

    def says(self, out, muted=False, mic=50, mic_muted=False, seconds=10):
        """The sound set from outside, a line asked for, and the state file once the bar shows it."""
        self.sound(out, muted, mic, mic_muted)
        self.nudge()
        want = ("output muted" if muted else "output %d%%" % out, "microphone muted" if mic_muted else "microphone %d%%" % mic)
        return self.until(lambda s: s.status == "ok" and (s.named("out.name"), s.named("mic.name")) == want, "the bar to show %s and %s" % want, seconds)

    def layout(self):
        outs = [o for o in self.ask("get_outputs") if o.get("active")]
        self.space = (max(o["rect"]["x"] + o["rect"]["width"] for o in outs), max(o["rect"]["y"] + o["rect"]["height"] for o in outs))
        return outs

    def stamp(self):
        return int(time.monotonic() * 1000) & 0xffffffff

    def move(self, x, y):
        self.pointer.send(5, 1, self.stamp(), int(x), int(y), self.space[0], self.space[1])   # motion_absolute, over every screen
        self.pointer.send(5, 4)
        self.pointer.sync()

    def button(self, down):
        self.pointer.send(5, 2, self.stamp(), 272, 1 if down else 0)   # BTN_LEFT
        self.pointer.send(5, 4)
        self.pointer.sync()

    def click(self, x, y):
        self.move(x, y)
        time.sleep(0.08)
        self.button(True)
        time.sleep(0.04)
        self.button(False)

    def wheel(self, notches):
        """The wheel turned: 15 px of scroll a notch, down when positive, as a mouse's wheel says it."""
        self.pointer.send(5, 3, self.stamp(), 0, (notches * 15 * 256) & 0xffffffff)   # axis, vertical, a fixed-point value
        self.pointer.send(5, 4)
        self.pointer.sync()

    def key(self, name, shift=False):
        words = ["-M", "shift", "-k", name, "-m", "shift"] if shift else ["-k", name]
        subprocess.run(["wtype", "-s", "80", *words, "-s", "40"], env=self.env, capture_output=True, timeout=10)

    def chord(self, modifier, name):
        subprocess.run(["wtype", "-s", "80", "-M", modifier, "-k", name, "-m", modifier, "-s", "40"], env=self.env, capture_output=True, timeout=10)

    def keys_on(self):
        """Super and the key sway's template binds to spark-shell bar keys."""
        self.chord("logo", self.keys_key)

    def focus(self, ident):
        """Tab until the keys are on a target."""
        s = self.until(lambda s: s.focused(), "the keys on the bar", 5)
        for _ in range(len(s.targets()) + 1):
            if s.focused() == ident:
                return s
            was = s.focused()
            self.key("Tab")
            s = self.until(lambda s: s.focused() not in (None, was), "Tab to move the keys on from %s" % was, 5)
        raise AssertionError("Tab never reached %s; the state file says: %s" % (ident, s.brief()))

    def terminal(self, title):
        child = subprocess.Popen([self.real_foot, "--title", title, "sleep", "900"], env=self.env, cwd=str(self.work), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.children.append(child)
        wait_for(lambda: self.node(child.pid), "the terminal " + title)
        return child

    def end_bar(self):
        """The bar stopped on purpose: SIGTERM, which it leaves on with 0, so its keeper lets it."""
        pid = self.bar_pid()
        if pid:
            os.kill(pid, signal.SIGTERM)
            settle(lambda: not alive(pid), 5)
        if self.state_file.exists():   # the next bar writes its own: a reader waits for that one
            self.state_file.unlink()
        return pid

    def rest(self, seconds=15):
        """The bar as a gate finds it: running as the config first had it, 1920 wide, at the top, the first
        workspace shown, the sound at 40 and 50, the pointer and the keys off it."""
        for name in ("down", "fail", "slow"):
            self.flag(name, False)
        self.sway("output", OUT, "mode", "%dx%d" % (W, H))
        self.layout()
        self.move(W // 2, H // 2)
        s = self.state()
        if s and s.mode:
            self.sway("mode", "default")
        if s and any(s.focused(o) for o in s.outputs):
            self.key("Escape")
        if self.focused_space() != 1:
            self.sway("workspace", "number", "1")
        self.sound(40, False, 50, False)
        if self.settings.read_text() != self.config_text:   # a gate left the config changed: as it was, and the bar again
            self.settings.write_text(self.config_text)
            self.end_bar()
        if self.bar_pid() and not settle(self.loop_pid, 3):   # a bar whose status never came back: started again
            self.end_bar()
        if not self.bar_pid():
            self.shell("bar", "start")
        self.nudge()
        return self.until(lambda s: s.status == "ok" and not s.mode and s.bar().width == W and s.bar().edge == "top" and not s.bar().dropped
                          and (s.named("out.name"), s.named("mic.name")) == ("output 40%", "microphone 50%")
                          and "selected" in s.find("workspace:1").flags and not any(t.flags & {"focused", "hover"} for b in s.outputs.values() for t in b.targets),
                          "the bar at rest: the whole line, out at 40 and the mic at 50, workspace 1 shown, no key and no pointer on it", seconds)


def seen(read, seconds=5):
    """A reading of the screen that holds: read() gives (whether it holds, what it saw), and is asked again
    while it does not, for the bar's frame follows the state file's word by a moment."""
    end = time.time() + seconds
    while True:
        good, saw = read()
        if good or time.time() >= end:
            return bool(good), saw
        time.sleep(0.05)


def mark_reads(d, x, y, side):
    """How the screen reads at a mark's square (its left, its top, its side), against spark's mark drawn there
    at five sizes, against the other ground's mark, and against no mark at all; and its three bands' pixels."""
    ground = rgb(d.pal["BG"])
    own, other = ("favicon", "favicon-light") if dark(ground) else ("favicon-light", "favicon")
    asset = read_png(REPO / "asset" / (own + "-26.png"))   # the PNG at or above 24 px: bar::mark_file
    img = d.grab(x - 2, y - 2, side + 4, side + 4)
    box, center = (side + 4, side + 4), ((side + 4) / 2.0, (side + 4) / 2.0)
    fits = {size: round(apart(img, drawn(asset, size, box, center, ground)), 2) for size in (side - 4, side - 2, side, side + 2, side + 4)}
    bands = [c for c, _ in collections.Counter(tuple(row[i:i + 3]) for row in asset[2] for i in range(0, len(row), 4) if row[i + 3] == 255).most_common(3)]
    return {"file": own + "-26.png", "fits": fits, "best": min(fits, key=fits.get),
            "other": round(apart(img, drawn(read_png(REPO / "asset" / (other + "-26.png")), side, box, center, ground)), 2),
            "blank": round(apart(img, [[ground] * box[0] for _ in range(box[1])]), 2),
            "bands": [sum(1 for p in img.all() if near(p, c, 30)) for c in bands]}


def mark_is(r, side):
    return r["best"] == side and r["fits"][side] <= 2.5 and r["fits"][side] * 3 <= min(r["other"], r["blank"]) and all(n >= 2 for n in r["bands"])


def mark_seen(d, x, y, there=True):
    """Whether the mark stands in the square at x, y (or, with there False, does not), and how it read."""
    def read():
        r = mark_reads(d, x, y, MARK)
        return mark_is(r, MARK) == there, r
    return seen(read)


def worn(img, ground, color, least=0.97):
    """Whether a piece is drawn in a color, gray: every pixel is the color thinned by the ground, and the
    strongest is the color itself (a thin glyph, with no pixel it covers whole: `least` of the way)."""
    gray, most = img.inked(ground, color)
    return gray and most >= least


def reads(d, t, ink, surface, top=0):
    """A cell's text as the screen has it, against the colors it should be in: whether its strongest ink is
    that ink itself on that surface, drawn gray, at 4.5 to 1 or more, and (the contrast, the ink, the surface)."""
    def read():
        img = d.grab(t.x, top + t.y, t.w, t.h)
        ground = img.ground()
        strong = img.strongest(ground)
        ratio = contrast(strong, ground)
        return ratio >= 4.5 and near(ground, surface, 3) and worn(img, ground, ink), (round(ratio, 1), strong, ground)
    return seen(read)


def lifecycle(d):
    enter("lifecycle", "spark-shell starts the bar, as sway's config does at login")
    ok(d.own == ["exec %s bar start" % d.shell_path] and len(d.keys_line) == 1 and d.keys_key and d.mode_lines[-1:] == ['bindsym $mod+r mode "resize"'],
       "sway's template has one line that starts the bar, exec spark-shell bar start, binds Super+%s to spark-shell bar keys, and has the resize mode on Super+r: the proof's sway reads them from it" % d.keys_key,
       (d.own, d.keys_line, d.mode_lines[-1:]))
    s = d.until(lambda s: s.status == "ok" and s.find("out.gauge") and s.find("clock.time"), "the bar's first line", 20)
    pid = d.bar_pid()
    ok(pid and cmdline(pid)[:1] == [str(d.binary)] and s.text.startswith("bar\t1\nstatus\tok\noutput\t%s\t%d\t" % (OUT, W)) and not s.odd,
       "sway's exec line started spark-bar, the build SPARK_SHELL_BAR names; it holds its lock and writes its state file", (pid, cmdline(pid or 0), s.text[:80], s.odd))
    loop = wait_for(d.loop_pid, "the status loop's pid")
    ok(stat_of(loop)[1] == pid and environ_of(loop).get("SPARK_BAR") == "1" and cmdline(loop)[-3:] == [d.shell_path, "bar", "status"],
       "the bar runs spark-shell bar status itself, with SPARK_BAR=1: every value it shows is the real loop's", (stat_of(loop), cmdline(loop)))
    env, pal = d.bar_env(), d.pal
    want = {"SPARK_SHELL": d.shell_path, "BAR_POSITION": "top", "BAR_FG": pal["FG"], "BAR_ACCENT": pal["ACCENT"], "BAR_GROUND": pal["BG"],
            "BAR_ATTENTION": pal["ANSI"][3], "BAR_ALPHA": "1", "BAR_PINS": "", "BAR_OVERFLOW": OVERFLOW, "BAR_TRAY_WIDTH": "0",
            "BAR_LOCK": str(d.lock), "BAR_STATE": str(d.state_file)}
    ok(all(env.get(k) == v for k, v in want.items()) and env.get("BAR_FONT", "").endswith(" 12") and all(re.fullmatch("[0-9a-f]{6}", env.get(k, "")) for k in ("BAR_LIT", "BAR_MUTED")),
       "spark-shell starts it with the proof's own palette (its hover shade and its muted are the shell's, made from it), 12 point text, the config's overflow order and its two files",
       {k: env.get(k) for k in list(want) + ["BAR_FONT", "BAR_LIT", "BAR_MUTED"] if env.get(k) != want.get(k)})
    line = d.line()
    look = line[0] if line and line[0].get("name") == "look" else {}
    ok(look and all(look.get(k) == env.get("BAR_" + k.upper()) for k in LOOK) and set(look) == set(LOOK) | {"name"} and not any(t.module == "look" for t in s.targets()),
       "the line carries the look for spark's bar: its first block, named look, the six colors and the alpha as the bar was started with; it is no module and no target", (look, line[:1]))
    again = d.shell("bar", "start")
    bars = lambda: [p for p in d.ours() if cmdline(p)[:1] == [str(d.binary)]]   # noqa: E731
    more = settle(lambda: bars() != [pid] and bars(), 1.5)   # a second one would come at once
    ok(again.returncode == 0 and not more and d.bar_pid() == pid, "spark-shell bar start again starts no second bar", (again.returncode, again.said, pid, more))
    # the pointer on the bar, where nothing is: no image of it, in a capture that asks for the pointer too
    at = (max(t.x + t.w for t in s.targets() if t.kind == "workspace") + min(t.x for t in s.targets() if t.kind not in ("mark", "workspace"))) // 2
    d.move(at, s.bar().height // 2)

    def bare():
        raw = subprocess.run(["grim", "-c", "-t", "ppm", "-g", "%d,0 48x%d" % (at - 24, s.bar().height), "-"], env=d.env, capture_output=True, timeout=20).stdout
        img = Img(*ppm(raw)) if raw else None
        return bool(img) and set(img.all()) == {rgb(pal["BG"])}, img and sorted(set(img.all()))[:4]
    good, saw = seen(bare)
    ok(good, "the proof's pointer has no image: with it on the bar, a capture that takes the pointer too shows the ground alone, so no capture measures a cursor", saw)
    d.move(W // 2, H // 2)
    # two terminals, a workspace each: the workspaces stay, and the first one's is the tiled window the bar keeps off
    d.windows = [d.terminal("ONE")]
    d.sway("workspace", "number", "2")
    d.windows.append(d.terminal("TWO"))
    d.sway("workspace", "number", "1")
    d.until(lambda s: s.find("workspace:2") and "selected" in s.find("workspace:1").flags, "two workspaces on the bar, the first shown")


def identity(d):
    enter("identity", "the mark, the font's glyphs, the family's frame")
    s = d.rest()
    mark, high, ground = s.find("mark"), s.bar().height, rgb(d.pal["BG"])
    good, r = mark_seen(d, mark.x, (high - mark.w) // 2)
    ok(mark.w == MARK and good,
       "the mark is the asset's own pixels (%s, the %s ground's) drawn at %d px: of five sizes that one fits, %.2f a channel off; the other ground's mark is %.2f off, no mark %.2f"
       % (r["file"], d.pal["name"], MARK, r["fits"].get(MARK, -1), r["other"], r["blank"]), r)
    ok(all(n >= 2 for n in r["bands"]) and len(r["bands"]) == 3, "it is a picture, not a glyph in one color: its three bands' own colors are on the screen (%s pixels)" % (r["bands"],), r)
    d.shot("identity-mark")

    def cells():
        strip = d.grab(0, 0, W, high)
        stray = [x for x in range(mark.x + mark.w, W) if not any(t.x <= x < t.x + t.w for t in s.targets()) and any(not near(strip.px(x, y), ground, 3) for y in range(high))]
        blank = [t.id for t in s.targets() if len(strip.cut(t.x, t.x + t.w).ink()) < 3]
        return not stray and not blank, (stray[:8], blank)
    good, saw = seen(cells)
    ok(good, "every target draws in its own cells, and not a pixel is drawn between them", saw)
    # the proof's home asks fontconfig for subpixel rendering, as Ubuntu's does: the bar draws gray all the same, a
    # block of one color in that color thinned by the ground and nothing else
    asks = subprocess.run(["fc-match", "-f", "%{rgba} %{lcdfilter}", "monospace"], env=d.env, capture_output=True, timeout=20).stdout.decode("ascii", "replace").split() if shutil.which("fc-match") else []
    plain, roles = {}, d.roles()
    for block in d.line():
        text = block.get("full_text", "")
        colors = set(re.findall("foreground='#([0-9a-f]{6})'", text))
        ident = block.get("name", "") + ("." + block["instance"] if block.get("instance") else "")
        if s.find(ident) and ((len(colors) == 1 and not re.sub("<span[^>]*>.*?</span>", "", text).strip()) or (not colors and "<" not in text)):
            plain[ident] = rgb(colors.pop()) if colors else roles["fg"]

    def gray():
        strip = d.grab(0, 0, W, high)
        off = {i: strip.cut(s.find(i).x, s.find(i).x + s.find(i).w).inked(ground, c) for i, c in plain.items()}
        return all(g and most >= 0.5 for g, most in off.values()), {i: v for i, v in off.items() if not (v[0] and v[1] >= 0.5)}
    good, saw = seen(gray)
    ok(good and len(plain) >= 6,
       "the bar's text is gray whatever fontconfig asks (here: %s): each of the %d blocks of one color is that color thinned by the ground, with no colored edge and no other color"
       % ("subpixel rendering, by the home's own file" if asks == ["1", "1"] else "rgba and lcdfilter " + " ".join(asks) if asks else "not known, no fc-match", len(plain)), (asks, saw, sorted(plain)))
    digits, pairs, signs, family, last = [], [], set("\u2026\u26a0"), "stone", None
    for name, left, right in FAMILIES:
        if name != family:
            said = d.shell("theme", "family", name)
            family = name
            ok(said.returncode == 0 and said.said == "glyph family " + name, "spark-shell theme family %s" % name, (said.returncode, said.said))
        want = {n: "%d:%s%d%s" % (n, left, n, right) for n in (1, 2)}
        got = settle(lambda: d.names() == want and d.names(), 8) or d.names()
        ok(got == want, "%s: sway's workspaces are named by the family, the number in its key frame (U+%04X N U+%04X)" % (name, ord(left), ord(right)), got)
        for block in d.line():
            signs |= {c for c in re.sub("<[^>]*>", "", block.get("full_text", "")) if ord(c) > 126 and block.get("name") != "logo"}
        signs |= {left, right}
        found, drawn_ = {}, {}

        def framed():
            for ident in ("workspace:2", "workspace:1"):
                t = s.find(ident)
                img = d.grab(t.x, 0, t.w, high)
                found[ident] = b = blobs(img.ink())
                # three glyphs, the outer two a pair that mirror each other; and the frame is this family's, drawn since the last one's
                if not (len(b) == 3 and likeness(flip(b[0]), b[2]) >= 0.55 and (ident != "workspace:2" or img.data != last)):
                    return False, {i: (len(f), round(likeness(flip(f[0]), f[-1]), 2) if f else 0) for i, f in found.items()}
                if ident == "workspace:2":
                    drawn_[0] = img.data
            return True, None
        good, saw = seen(framed, 8)
        ok(good and all(s.find(i).w == 4 * (mark.x) for i in ("workspace:2", "workspace:1")),
           "%s: on the screen a workspace is three glyphs in a cell of four, its number between a pair that mirror each other; the one shown, on its chip, the same" % name, saw)
        last = drawn_.get(0)
        if len(found.get("workspace:2", [])) == 3:
            pairs.append(found["workspace:2"][0])
            digits.append(found["workspace:2"][1])
        d.shot("identity-" + name)
    ok(len(digits) == 3 and digits[0] == digits[1] == digits[2] and all(likeness(a, b) < 0.8 for a, b in ((pairs[0], pairs[1]), (pairs[0], pairs[2]), (pairs[1], pairs[2]))),
       "the number is the same pixels under all three families and the pair around it another in each: the frame alone changes",
       ([len(x) for x in digits], [round(likeness(a, b), 2) for a in pairs for b in pairs if a is not b]))
    if shutil.which("fc-list"):
        lacking = ["U+%04X" % ord(c) for c in sorted(signs) if not subprocess.run(["fc-list", ":charset=%x" % ord(c), "family"], env=d.env, capture_output=True, timeout=20).stdout.strip()]
        ok(not lacking, "real glyphs: a font here holds every sign the bar draws under the three families (%d of them), so none is a missing-glyph box" % len(signs), lacking)
    else:
        print("  skip identity: no fc-list here: which font holds each sign is not asked", flush=True)
    back = d.shell("theme", "family", "stone")
    settle(lambda: d.names().get(2) == "2:\u27e82\u27e9", 8)
    ok(back.returncode == 0 and d.names().get(2) == "2:\u27e82\u27e9", "back to stone, the default family", (back.said, d.names()))


def behavior(d):
    enter("behavior", "the pointer and the keys, through the real status loop and the stand-in sound tool")
    s = d.rest()
    high, ground = s.bar().height, rgb(d.pal["BG"])
    mid, sign, gauge = high // 2, s.find("out.name"), s.find("out.gauge")
    kinds = [s.find(i).kind for i in ("out.name", "out.gauge", "out.pct", "mic.name", "mic.gauge", "clock.time")]
    ok(kinds == ["toggle", "level", "open", "open", "level", "open"],
       "the state file: out's sign is a toggle, its gauge a level, its percent an opener; the mic's sign an opener, its gauge a level; the clock an opener", kinds)
    # the pointer
    d.move(s.find("clock.time").mid, mid)
    lit, hover = d.until(lambda s: "hover" in s.find("clock.time").flags, "the pointer on the clock").find("clock.time"), d.roles()["lit"]

    def chip():
        img = d.grab(lit.x - 2, 0, lit.w + 4, high)
        return (all(near(img.px(x, y), hover, 3) for x in (2, lit.w + 1) for y in (0, high - 1)) and all(near(img.px(x, 1), ground, 3) for x in (0, lit.w + 3)),
                [img.px(x, 1) for x in (0, 2, lit.w + 1, lit.w + 3)])
    good, saw = seen(chip)
    ok(good, "pointer: the target under it is lit, a chip in the hover color the bar's whole height and its own width", saw)
    d.shot("behavior-hover")
    d.click(sign.mid, mid)
    d.until(lambda s: s.named("out.name") == "output muted", "out muted by a click on its sign")
    ok(d.muted("out") and d.log()[-1:] == ["set-mute @DEFAULT_AUDIO_SINK@ toggle"] and not d.opened(),
       "pointer: a click on out's sign mutes: the sound tool's switch is thrown, and nothing is opened", (d.muted("out"), d.log()[-2:], d.opened()))
    d.click(sign.mid, mid)
    d.until(lambda s: s.named("out.name") == "output 40%", "out unmuted by a second click")
    ok(not d.muted("out"), "pointer: a second click unmutes")
    inside = gauge.w * 3 // 10
    want = level_at(inside, gauge.w)
    d.click(gauge.x + inside, mid)
    d.until(lambda s: s.named("out.gauge") == "output %d%%" % want, "the level set by a click on the gauge")
    ok(d.level("out") == want and abs(want - 100 * inside // gauge.w) <= 5,
       "pointer: a click on out's gauge sets the level where the click is: %d px into its %d makes it %d%%" % (inside, gauge.w, want), (d.level("out"), d.log()[-1:]))
    d.move(gauge.mid, mid)
    d.until(lambda s: "hover" in s.find("out.gauge").flags, "the pointer on the gauge")
    d.wheel(-1)
    d.until(lambda s: s.named("out.gauge") == "output %d%%" % (want + 5), "the wheel up to add 5")
    up = d.level("out")
    d.wheel(1)
    d.wheel(1)
    d.until(lambda s: s.named("out.gauge") == "output %d%%" % (want - 5), "the wheel down twice to take 10")
    ok(up == want + 5 and d.level("out") == want - 5 and d.log()[-3:] == ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%" + way for way in "+--"],
       "pointer: the wheel on the gauge takes 5 a notch, up and down (%d, %d, %d)" % (want, up, want - 5), (up, d.level("out"), d.log()[-3:]))
    mic = s.find("mic.gauge")
    inside = mic.w * 8 // 10
    d.click(mic.x + inside, mid)
    d.until(lambda s: s.named("mic.gauge") == "microphone %d%%" % level_at(inside, mic.w), "the mic's level set by a click on its gauge")
    ok(d.level("mic") == level_at(inside, mic.w) and d.level("out") == want - 5, "pointer: a click on the mic's gauge sets the mic's level, %d%%, and out's stays" % level_at(inside, mic.w),
       (d.level("mic"), d.level("out")))
    d.click(s.find("workspace:2").mid, mid)
    two = d.until(lambda s: "selected" in s.find("workspace:2").flags, "workspace 2 shown by a click on it")
    ok(d.focused_space() == 2 and not two.find("workspace:1").flags and two.find("workspace:2").flags == {"hover", "selected", "visible"},
       "pointer: a click on workspace 2 shows it: sway has the focus there and the state file says so", (d.focused_space(), two.brief()))
    d.click(s.find("workspace:1").mid, mid)
    d.until(lambda s: "selected" in s.find("workspace:1").flags, "workspace 1 shown again")
    ok(d.focused_space() == 1, "pointer: and a click on workspace 1 brings it back", d.focused_space())
    line = "--config %s/.config/foot/dialog.ini --app-id spark-dialog -e %s dialog" % (d.home, d.shell_path)
    changes, got = len(d.log()), []
    for ident, section in (("out.pct", "out"), ("mic.name", "mic"), ("clock.time", "clock"), ("bat", "bat"), ("mark", "")):
        n = len(d.opened())
        d.click(s.find(ident).mid, mid)
        got.append((ident, (settle(lambda: d.opened()[n:], 8) or ["nothing opened"])[-1], line + (" " + section if section else "")))
    ok(all(found == wanted for _, found, wanted in got) and len(d.opened()) == 5 and len(d.log()) == changes,
       "pointer: out's percent opens the dialog's out section, the mic's sign mic, the clock clock, the battery bat, and the mark home with no section; no sound is changed",
       [g for g in got if g[1] != g[2]] or (d.opened(), d.log()[changes:]))
    # the keys
    d.move(W // 2, H // 2)
    d.until(lambda s: not any("hover" in t.flags for t in s.targets()), "the pointer off the bar")
    d.keys_on()
    s = d.until(lambda s: s.focused() == "mark", "Super+%s to put the keys on the bar" % d.keys_key)
    mark, accent = s.find("mark"), rgb(d.pal["ACCENT"])

    def under():
        img = d.grab(mark.x, high - 3, mark.w, 3)
        return all(near(img.px(x, y), accent, 3) for x in (0, mark.w - 1) for y in (1, 2)) and not near(img.px(0, 0), accent, 40), [img.px(0, y) for y in range(3)]
    good, saw = seen(under)
    ok(good, "keys: Super+%s, sway's binding of spark-shell bar keys, picks the mark: a 2 px line in the accent under it" % d.keys_key, saw)
    d.shot("behavior-keys")
    d.key("Right")
    d.until(lambda s: s.focused() == "workspace:1", "Right to move the keys to workspace 1")
    d.key("Left")
    d.until(lambda s: s.focused() == "mark", "Left to move them back to the mark")
    ok(True, "keys: Right and Left move along the bar")
    # the keyboards configured again while the bar has the keys, as a layout changed or a keyboard plugged in does: an
    # older sway takes the keyboard off the surface and gives it back, and each key here is a keyboard of its own
    d.sway("input", "type:keyboard", "repeat_delay", "450")
    d.key("Right")
    d.until(lambda s: s.focused() == "workspace:1", "Right to move the keys after the keyboards were configured again")
    d.key("Left")
    s = d.until(lambda s: s.focused() == "mark", "Left to move them back")
    ok(True, "keys: the keyboards configured again while the bar has them: the bar keeps the keys")
    d.focus("out.name")
    d.key("Return")
    s = d.until(lambda s: s.named("out.name") == "output muted", "Enter on out's sign to mute")
    ok(d.muted("out") and s.focused() == "out.name", "keys: Enter on out's sign mutes, and the keys stay on it", (d.muted("out"), s.focused()))
    d.key("space")
    s = d.until(lambda s: s.named("out.name") == "output %d%%" % (want - 5), "Space to unmute")
    ok(not d.muted("out") and s.focused() == "out.name", "keys: Space unmutes", (d.muted("out"), s.focused()))
    d.key("Tab")
    d.until(lambda s: s.focused() == "out.gauge", "Tab to the gauge")
    levels = []
    for name, level in (("End", 100), ("Home", 0), ("Right", 5), ("Right", 10), ("Left", 5)):
        d.key(name)
        s = d.until(lambda s: s.named("out.gauge") == "output %d%%" % level, "%s on the gauge to make it %d%%" % (name, level))
        levels.append(d.level("out"))
    tail = ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ " + v for v in ("100%", "0%", "5%+", "5%+", "5%-")]
    ok(levels == [100, 0, 5, 10, 5] and d.log()[-5:] == tail and s.focused() == "out.gauge",
       "keys: on the gauge End sets 100 and Home 0, Right and Left take 5, and the keys stay on it", (levels, d.log()[-5:], s.focused()))
    d.key("Tab")
    d.until(lambda s: s.focused() == "out.pct", "Tab to the percent")
    n = len(d.opened())
    d.key("Return")
    s = d.until(lambda s: not s.focused(), "Enter on the percent to give the keyboard back")
    ok((settle(lambda: d.opened()[n:], 8) or [""])[-1] == line + " out", "keys: Enter on the percent opens the out section and gives the keyboard back", d.opened()[n:])
    said = d.shell("bar", "keys")
    d.until(lambda s: s.focused() == "mark", "spark-shell bar keys to put the keys on the bar")
    n = len(d.opened())
    d.key("Return")
    d.until(lambda s: not s.focused(), "Enter on the mark to give the keyboard back")
    ok(said.said == "the bar has the keys: the arrows move, Enter acts, Esc leaves" and (settle(lambda: d.opened()[n:], 8) or [""])[-1] == line,
       "keys: spark-shell bar keys says so, and Enter on the mark opens home", (said.said, d.opened()[n:]))
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s again" % d.keys_key)
    d.key("Right")
    d.key("Right")
    d.until(lambda s: s.focused() == "workspace:2", "Right twice to workspace 2")
    d.key("Return")
    s = d.until(lambda s: "selected" in s.find("workspace:2").flags and not s.focused(), "Enter on workspace 2 to show it")
    ok(d.focused_space() == 2, "keys: Enter on a workspace shows it and gives the keyboard back", d.focused_space())
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s once more" % d.keys_key)
    d.key("Escape")
    s = d.until(lambda s: not s.focused(), "Escape to give the keyboard back")
    ok(d.focused_space() == 2 and len(d.opened()) == 7, "keys: Escape gives the keyboard back and does nothing else", (d.focused_space(), d.opened()))


def states(d):
    enter("states", "no device, a failed change, the status gone, a crash, a stop, loading, a binding mode")
    s = d.rest()
    base, high, mid, cell = s.rects(), s.bar().height, s.bar().height // 2, s.find("mark").x
    frame = collections.OrderedDict((k, v) for k, v in base.items() if k == "mark" or k.startswith("workspace:"))
    sound = ("out.name", "out.gauge", "out.pct", "mic.name", "mic.gauge")
    ground, sign, gauge, pct = rgb(d.pal["BG"]), s.find("out.name"), s.find("out.gauge"), s.find("out.pct")
    muted, alarm = d.roles()["muted"], rgb(d.pal["ANSI"][1])
    # no sound device
    d.flag("down", True)
    d.nudge()
    s = d.until(lambda s: all(s.find(i).state == "unavailable" for i in sound), "out and mic to say unavailable")
    ok(s.status == "ok" and s.rects() == base and s.named("out.name") == "output not available: no audio system found"
       and s.named("mic.gauge") == "microphone not available: no audio system found" and all(t.state == "ok" for t in s.targets() if t.id not in sound),
       "no sound device: out and the mic say unavailable and why, in the same cells; the rest of the line is as it was", (moved(base, s.rects()), s.named("out.name"), s.brief()))

    def hollow():
        cells, img = d.grab(gauge.x, 0, pct.x + pct.w - gauge.x, high), d.grab(sign.x, 0, sign.w, high)
        return not cells.ink(ground) and worn(img, ground, muted, 0.5), (len(cells.ink(ground)), img.strongest(ground), img.inked(ground, muted))
    good, saw = seen(hollow)
    ok(good, "on the screen its gauge and its percent are empty cells and its sign is drawn muted", saw)
    d.shot("states-unavailable")
    d.flag("down", False)
    d.nudge()
    d.until(lambda s: all(s.find(i).state == "ok" for i in sound), "out and mic back")
    # a change that fails
    d.flag("fail", True)
    d.click(sign.mid, mid)
    d.move(W // 2, H // 2)
    s = d.until(lambda s: s.find("out.name").state == "error" and not any("hover" in t.flags for t in s.targets()), "out to say its change failed")
    ok(all(s.find(i).state == "error" for i in sound[:3]) and all(s.find(i).state == "ok" for i in sound[3:]) and s.named("out.name") == "output could not be changed"
       and s.rects() == base and not d.muted("out") and d.log()[-1:] == ["set-mute @DEFAULT_AUDIO_SINK@ toggle"],
       "a change that fails: out says error, could not be changed, in the same cells; the device is as it was, and the mic is not touched",
       (moved(base, s.rects()), s.brief(), d.muted("out"), d.log()[-1:]))

    def warning():
        img = d.grab(gauge.x, 0, gauge.w, high)
        return worn(img, ground, alarm, 0.5) and all(x < gauge.w // 2 for x, _ in img.ink(ground)), (img.strongest(ground), img.inked(ground, alarm), sorted({x for x, _ in img.ink(ground)})[-3:])
    good, saw = seen(warning)
    ok(good, "on the screen a warning stands in the gauge's first cells, in the alarm color", saw)
    d.shot("states-error")
    d.flag("fail", False)
    d.click(sign.mid, mid)
    s = d.until(lambda s: s.find("out.name").state == "ok" and s.named("out.name") == "output muted", "the next change, one that works, to clear the error")
    ok(d.muted("out") and s.rects() == base, "the next change that works clears it: out is muted now, and says so")
    d.click(sign.mid, mid)
    d.until(lambda s: s.named("out.name") == "output 40%", "out unmuted")
    # the status child ends, its background jobs (the clicks' reader, the workspaces' watcher) still holding its pipe
    bar, loop = d.bar_pid(), d.loop_pid()
    crew = members(group_of(loop))
    ok(group_of(loop) == loop and group_of(bar) != loop and len(crew) >= 3 and loop in crew,
       "the status runs in a process group of its own: the loop and its background jobs, %d processes" % len(crew), (loop, group_of(loop), group_of(bar), crew))
    os.kill(loop, signal.SIGKILL)
    s = d.until(lambda s: s.status == "error", "the status marked broken", 6)
    ok(s.rects() == frame and d.bar_pid() == bar,
       "the status shell killed while its jobs hold the pipe: the bar hears its end, the state file says error, and the frame stays, the mark and the workspaces where they were",
       (s.brief(), d.bar_pid(), bar))
    d.shot("states-status-ended")
    s = d.until(lambda s: s.status == "ok" and s.find("clock.time"), "the status started again", 15)
    ok(d.loop_pid() not in (None, loop) and d.bar_pid() == bar and s.rects() == base and not [p for p in crew if alive(p)],
       "it is started again within seconds: another spark-shell bar status, the same bar, every cell where it was; of the old one no process is left",
       (loop, d.loop_pid(), bar, d.bar_pid(), moved(base, s.rects()), [(p, " ".join(cmdline(p))[:60]) for p in crew if alive(p)]))
    # the bar itself ends: ABRT, a crash
    old = d.loop_pid()
    crew = members(group_of(old))
    d.state_file.unlink()
    os.kill(bar, signal.SIGABRT)
    now = settle(lambda: d.bar_pid() not in (None, bar) and d.bar_pid(), 12)
    s = d.until(lambda s: s.status == "ok" and s.find("clock.time"), "the bar started again by its keeper", 15)
    said = d.log_file.read_text(encoding="utf-8", errors="replace") if d.log_file.exists() else ""
    ok(now and now != bar and "spark-bar ended (134): started again" in said and s.rects() == base,
       "the bar killed with SIGABRT: its keeper says so and starts it again, another pid (%s, then %s), the whole line back" % (bar, now), (bar, now, said[-200:], moved(base, s.rects())))
    # the crashed bar ended no group: its status finds its pipe closed at its next line, asked for now; the workspaces'
    # watcher sees that at a workspace event and its subscriber at the one after, so the workspace is changed a few times
    try:
        os.kill(old, signal.SIGUSR1)
    except OSError:
        pass
    settle(lambda: d.reap() or not alive(old), 20)
    until, turn = time.time() + 20, 0
    while [p for p in crew if alive(p)] and time.time() < until:
        d.reap()   # the dead loop reaped, as an init does: its watcher asks whether it still answers
        turn += 1
        d.sway("workspace", "number", "2" if turn % 2 else "1")
        time.sleep(0.4)
    d.sway("workspace", "number", "1")
    ok(len(crew) >= 3 and not [p for p in crew if alive(p)], "after the crash nothing of the old status is left either: its loop and its jobs end by themselves",
       ([(p, " ".join(cmdline(p))[-60:]) for p in crew if alive(p)], "the proof reaps its session's orphans" if d.reaps else "the proof could not take its session's orphans to reap"))
    # stopped on purpose
    crew = members(group_of(wait_for(d.loop_pid, "the new bar's status loop")))
    keepers = lambda: [p for p in d.ours() if "spark-bar ended" in " ".join(cmdline(p))]   # noqa: E731  the keeper's own words are its command
    kept = keepers()
    d.end_bar()
    settle(lambda: not keepers() and not [p for p in crew if alive(p)], 20)   # a keeper that is gone starts no bar again
    ok(len(kept) == 1 and not keepers() and d.bar_pid() is None and not any(cmdline(p)[:1] == [str(d.binary)] for p in d.ours()) and crew and not [p for p in crew if alive(p)],
       "stopped on purpose (SIGTERM): it left with 0, so its keeper ended too and starts none again, and its status went with it, the whole group",
       (kept, keepers(), d.bar_pid(), [(p, " ".join(cmdline(p))[:60]) for p in crew if alive(p)]))
    # loading: the bar up before its first line; the sound tool gives no answer until the proof has looked
    d.move(W // 2, H // 2)
    d.flag("slow", True)
    started = d.shell("bar", "start")
    s = d.until(lambda s: s.status == "loading" and s.find("mark"), "the bar up before its first line", 10)
    ok(started.returncode == 0 and s.rects() == frame, "loading: spark-shell bar start, and before the first line the frame is there, the mark and the workspaces where they stay",
       (started.said, s.brief()))
    after = base["workspace:2"][0] + base["workspace:2"][2]

    def waiting():
        note, rest_ = d.grab(W - 3 * cell, 0, 2 * cell, high), d.grab(after, 0, W - 3 * cell - after, high)
        return worn(note, ground, muted, 0.5) and not rest_.ink(ground), (len(note.ink(ground)), note.strongest(ground), note.inked(ground, muted), len(rest_.ink(ground)))
    good, saw = seen(waiting)
    ok(good, "on the screen a muted sign stands at the right end where the status will be, and nothing else", saw)
    d.shot("states-loading")
    d.flag("slow", False)
    s = d.until(lambda s: s.status == "ok" and s.find("clock.time"), "the first line", 40)
    ok(s.rects() == base, "the first line fills the cells kept for it", moved(base, s.rects()))
    # a binding mode other than default: the template's resize, on Super+r
    s = d.rest()
    before = min(r[0] for k, r in base.items() if k != "mark" and not k.startswith("workspace:")) - 2 * cell
    d.chord("logo", "r")
    s = d.until(lambda s: s.mode == "resize", "the binding mode in the state file")

    def mode(there):
        def read():
            img = d.grab(after, 0, before - after, high)
            first = min([x for x, _ in img.ink(ground)] or [None])
            return (first == cell and near(img.px(cell, 1), rgb(d.pal["ACCENT"]), 3)) if there else first is None, (first, img.px(cell, 1))
        return seen(read)
    good, saw = mode(True)
    ok(good and s.rects() == base and not any(t.module == "mode" for t in s.targets()),
       "a binding mode (Super+r, the template's resize): the state file says mode resize and its name stands one cell after the workspaces, on the accent; it is no target, and every target is where it was",
       (s.brief(), saw))
    d.shot("states-mode")
    d.key("Escape")
    s = d.until(lambda s: not s.mode, "the default mode again")
    good, saw = mode(False)
    ok(good and s.rects() == base, "back in the default mode the cell is gone", (s.brief(), saw))


def contrasts(d, s):
    """Every text role on the surface it is drawn on: by the palette, then as the screen has it."""
    pal, roles = d.pal, d.roles()
    fg, muted, accent, ground, lit, alert = (roles[k] for k in ("fg", "muted", "accent", "ground", "lit", "attention"))
    pairs = collections.OrderedDict((("text on the ground", (fg, ground)), ("muted text on the ground", (muted, ground)), ("the shown workspace's label on the accent", (ground, accent)),
                                     ("text on the hover chip", (fg, lit)), ("muted text on the hover chip", (muted, lit)), ("an urgent workspace's label on the ground", (alert, ground)),
                                     ("a failed change's sign on the ground", (rgb(pal["ANSI"][1]), ground))))
    ratios = collections.OrderedDict((k, round(contrast(*v), 2)) for k, v in pairs.items())
    ok(all(r >= 4.5 for r in ratios.values()) and contrast(accent, ground) >= 3 and (fg, accent, ground, alert) == tuple(rgb(c) for c in (pal["FG"], pal["ACCENT"], pal["BG"], pal["ANSI"][3])),
       "the %s palette is the proof's own, never a theme of the machine's: as the bar is handed it, each text role reads at 4.5 to 1 or more on its surface (%s), the accent's lines at 3 or more (%.2f)"
       % (pal["name"], ", ".join("%.1f" % r for r in ratios.values()), contrast(accent, ground)), (ratios, roles))
    mid, got = s.bar().height // 2, collections.OrderedDict()
    for label, ident, pair in (("text on the ground", "clock.time", (fg, ground)), ("muted text on the ground", "clock.date", (muted, ground)),
                               ("a workspace not shown, muted on the ground", "workspace:2", (muted, ground)), ("the shown workspace's label on the accent", "workspace:1", (ground, accent))):
        got[label] = reads(d, s.find(ident), *pair)
    for label, ident, pair in (("text on the hover chip", "clock.time", (fg, lit)), ("muted text on the hover chip", "clock.date", (muted, lit))):
        d.move(s.find(ident).mid, mid)
        d.until(lambda s: "hover" in s.find(ident).flags, "the pointer on " + ident)
        got[label] = reads(d, s.find(ident), *pair)
    d.move(W // 2, H // 2)
    d.until(lambda s: not any("hover" in t.flags for t in s.targets()), "the pointer off the bar")
    for label, (good, (ratio, ink, surface)) in got.items():
        ok(good, "on the screen, %s reads at %.1f to 1: its strongest ink #%02x%02x%02x on #%02x%02x%02x" % ((label, ratio) + ink + surface), pairs.get(label))
    return alert, ground


def shipped(d):
    """Every palette spark-shell ships, as its bar is handed it: the look of the status line under each, and on its
    ground the contrast of its text, of the muted the shell lifts, of its accent and of its attention slot."""
    runs, rows = [], collections.OrderedDict()
    for path in sorted((REPO / "gallery/theme").glob("*.env")):
        conf = d.work / "shipped" / path.stem
        (conf / "spark").mkdir(parents=True)
        (conf / "spark-shell").mkdir()
        shutil.copyfile(str(path), str(conf / "spark/theme.env"))
        (conf / "spark-shell/config").write_text("DESKTOP=sway\nTHEME=%s\n" % path.stem)
        runs.append((path.stem, subprocess.Popen(["sh", d.shell_path, "bar", "status", "--once"], env=dict(d.env, SPARK_BAR="1", XDG_CONFIG_HOME=str(conf)),
                                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)))
    for name, run in runs:
        try:
            look = next(b for b in json.loads(run.communicate(timeout=60)[0].decode("utf-8", "replace") or "[]") if b.get("name") == "look")
            rows[name] = tuple(contrast(rgb(look[k]), rgb(look["ground"])) for k in ("fg", "muted", "accent", "attention"))
        except (ValueError, KeyError, StopIteration, subprocess.TimeoutExpired):
            rows[name] = None
    return rows


def accessibility(d):
    enter("accessibility", "contrast, the keys' order, names, no motion")
    s = d.rest()
    alert, ground = contrasts(d, s)
    # the shipped palettes are their authors' colors: the bar answers for the muted it is handed, lifted to 4.5 to 1,
    # or as far as the palette's own text where that reads under it; the rest is said, for whoever picks a palette
    rows = shipped(d)
    read = collections.OrderedDict((n, r) for n, r in rows.items() if r)
    short = {n: (round(r[1], 2), round(r[0], 2)) for n, r in read.items() if not (r[1] >= 4.5 or r[1] >= r[0])}
    ok(len(rows) >= 2 and len(read) == len(rows) and not short,
       "every palette spark-shell ships (%d of them): the muted the bar is handed reads at 4.5 to 1 or more on the ground, or as its text does where the palette's own text reads under that"
       % len(rows), short or [n for n, r in rows.items() if not r])
    for words, i, least in (("text on the ground", 0, 4.5), ("the accent on the ground, the focus line and the gauges", 2, 3),
                            ("the shown workspace's label, the ground on the accent", 2, 4.5), ("an urgent workspace's label, the attention slot on the ground", 3, 4.5)):
        under = ", ".join("%s %.2f" % (n, r[i]) for n, r in sorted(read.items(), key=lambda item: item[1][i]) if r[i] < least)
        print("  note accessibility: shipped palettes, %s: %s" % (words, ("under %s to 1 in %s" % (least, under)) if under else "%s to 1 or more in each" % least), flush=True)
    two, high = s.find("workspace:2"), s.bar().height
    d.sway("[pid=%d]" % d.windows[1].pid, "urgent", "enable")
    s = d.until(lambda s: "urgent" in s.find("workspace:2").flags, "workspace 2 to ask for attention")
    good, (ratio, ink, surface) = reads(d, two, alert, ground)

    def edge():
        img = d.grab(two.x, high - 3, two.w, 3)
        return all(near(img.px(x, y), alert, 3) for x in (0, two.w - 1) for y in (1, 2)) and near(img.px(0, 0), ground, 3), [img.px(0, y) for y in range(3)]
    lined, saw = seen(edge)
    ok(good and lined, "a workspace that asks for attention says it twice, never by color alone: its label in the attention color (%.1f to 1) and a 2 px line at the bar's inner edge" % ratio,
       (ink, surface, saw))
    d.shot("accessibility-urgent")
    d.sway("[pid=%d]" % d.windows[1].pid, "urgent", "disable")
    d.until(lambda s: "urgent" not in s.find("workspace:2").flags, "workspace 2 at rest again")
    # the keys' order
    d.shell("bar", "keys")
    s = d.until(lambda s: s.focused() == "mark", "the keys on the bar")
    order, visual, went = s.ids(), [t.id for t in sorted(s.targets(), key=lambda t: t.x)], []
    for _ in order:
        was = s.focused()
        d.key("Tab")
        s = d.until(lambda s: s.focused() not in (None, was), "Tab to move the keys on from %s" % was, 5)
        went.append(s.focused())
    ok(order == visual and went == visual[1:] + visual[:1] and len(set(went)) == len(visual),
       "the keys: Tab goes through all %d targets, each once, left to right as they stand, and comes round to the mark" % len(visual), (went, visual))
    d.key("Tab", shift=True)
    s = d.until(lambda s: s.focused() == visual[-1], "Shift+Tab to go back, from the mark round to the last target", 5)
    d.key("Escape")
    d.until(lambda s: not s.focused(), "Escape to give the keyboard back")
    ok(True, "the keys: Shift+Tab goes back, round to the last one")
    # no motion
    d.move(W // 2, H // 2)
    d.until(lambda s: not any("hover" in t.flags for t in s.targets()), "the pointer off the bar")

    def still():
        if time.localtime().tm_sec > 54:   # the clock's own change of minute is not motion
            time.sleep(61 - time.localtime().tm_sec)
        one = d.grab(0, 0, W, high).data
        time.sleep(1.3)
        return one == d.grab(0, 0, W, high).data, None
    good, _ = seen(still, 4)
    ok(good, "no motion: two frames of the bar 1.3 s apart, with nothing touched, are the same pixels")


def names(d):
    """Every control in every state the proof saw: a name, an id, a kind and a state of the bar's own."""
    global gate
    gate = "accessibility"
    lines = bad = 0
    for text in d.seen:
        s = State(text)
        bad += len(s.odd)
        for strip in s.outputs.values():
            for t in strip.targets:
                lines += 1
                if not (t.name.strip() and t.id and t.kind in ("mark", "workspace", "toggle", "level", "open") and t.state in ("ok", "unavailable", "error")
                        and t.flags <= {"focused", "hover", "selected", "urgent", "visible"}):
                    bad += 1
    ok(lines and not bad, "names: in the %d states the bar wrote here, each of its %d target lines has a name that is not empty, a kind and a state of the bar's own" % (len(d.seen), lines), bad)


def geometry(d):
    enter("geometry", "the sizes, no shift, pins, a narrow screen, the bottom, two screens")
    s = d.rest()
    base, strip, env = s.rects(), s.bar(), d.bar_env()
    mark, high, ground = s.find("mark"), strip.height, rgb(d.pal["BG"])
    cell = mark.x
    spaces = [t for t in s.targets() if t.kind == "workspace"]
    status = [t for t in s.targets() if t.kind not in ("mark", "workspace")]
    ok(strip.height == BAR and strip.scale == 1 and strip.edge == "top" and all((t.y, t.h) == (0, BAR) for t in s.targets()) and mark.w == MARK
       and env.get("BAR_FONT", "").endswith(" 12") and round(TEXT * 2.25) == BAR and round(TEXT * 1.5) == MARK and 9 <= cell <= 11,
       "the state file: the bar is %d px high and its mark %d wide, the sizes of %d px text (12 points); a cell, the font's 0, is %d px" % (BAR, MARK, TEXT, cell),
       (strip.height, mark.rect, env.get("BAR_FONT"), cell))
    gap = (spaces[-1].x + spaces[-1].w + status[0].x) // 2
    win, area = d.node(d.windows[0].pid)["rect"], next(w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1)

    def rows():
        column = d.grab(gap, 0, 1, BAR + 12)
        n = next((y for y in range(column.h) if not near(column.px(0, y), ground, 3)), column.h)
        return n == BAR, n
    good, saw = seen(rows)
    ok(good and (area["x"], area["y"], area["width"], area["height"]) == (0, BAR, W, H - BAR) and win["y"] == BAR,
       "the screen: the bar's ground is %d rows at the top, and the windows' area begins under it: a tiled window's rect starts at y %d, clear of the bar" % (BAR, BAR), (saw, area, win))

    def digits():
        inked = sorted({y for _, y in d.grab(*s.find("clock.time").rect).ink(ground)})
        tall = inked[-1] - inked[0] + 1 if inked else 0
        return TEXT * 0.5 <= tall <= TEXT * 0.9 and abs((inked[0] + inked[-1] + 1) / 2.0 - BAR / 2.0) <= 3, (tall, inked[:1], inked[-1:])
    good, saw = seen(digits)
    ok(good, "the screen: the clock's digits stand in the middle of the bar's height, %d px tall, a face of %d px" % (saw[0], TEXT), saw)
    picture = d.grab(mark.x, 0, mark.w, high).ink(ground)
    box = (min(x for x, _ in picture), min(y for _, y in picture), max(x for x, _ in picture), max(y for _, y in picture)) if picture else None
    ok(box and box[1] >= (BAR - MARK) // 2 and box[3] < (BAR + MARK) // 2 and box[0] >= 0 and box[2] < MARK,
       "the screen: the mark's ink stands inside its %d px square, in the middle of the bar's height" % MARK, box)
    blocks = [(b["name"], b["name"] + ("." + b["instance"] if b.get("instance") else ""), b.get("cells", 0) * cell, bool(b.get("optional")))
              for b in d.line() if b.get("name") not in ("logo", "look")]
    gaps = [(b.x - a.x - a.w, cell if a.module == b.module else 2 * cell) for a, b in zip(status, status[1:])]
    ok(mark.x == cell and spaces[0].x == cell + MARK + cell and all(a.x + a.w == b.x for a, b in zip(spaces, spaces[1:])) and all(g == want for g, want in gaps)
       and [(i, w) for _, i, w, _ in blocks] == [(t.id, t.w) for t in status] and status[-1].x + status[-1].w == W - cell,
       "the cells: each block stands in the cells its line keeps for it, one cell apart inside a module and two between modules, the status ends a cell from the edge",
       (gaps, [(i, w) for _, i, w, _ in blocks], [(t.id, t.w) for t in status]))
    # no shift
    pct, kept, signs, right = s.find("out.pct"), collections.OrderedDict(), {}, True
    for label, level, off, inked in (("5%", 5, False, (0, 0, 1, 1)), ("100%", 100, False, (1, 1, 1, 1)), ("muted", 100, True, (0, 0, 0, 0))):
        kept[label] = d.says(level, off).rects()

        def percent():
            img = d.grab(pct.x, 0, pct.w, high)
            top = img.top(ground)   # a cell has a glyph when it has ink as strong as the block's
            return tuple(int(len(img.cut(i * cell, (i + 1) * cell).ink(ground, top)) >= 3) for i in range(4)) == inked, img
        good, signs[label] = seen(percent)
        right = right and good
    d.flag("down", True)
    d.nudge()
    kept["no device"] = d.until(lambda s: s.find("out.name").state == "unavailable", "out to say unavailable").rects()
    d.flag("down", False)
    s = d.rest()
    ok(all(r == base for r in kept.values()), "no shift: every target's rectangle is the same at 5%, at 100%, muted and with no sound device", {k: moved(base, r) for k, r in kept.items() if r != base})
    ok(right and signs["5%"].cut(3 * cell, 4 * cell).data == signs["100%"].cut(3 * cell, 4 * cell).data,
       "no shift on the screen: the percent sign stands in the same pixels at 5% and at 100%, the digits right-aligned before it in the cells kept for them; muted, the cells are empty")
    zeros = [(b[0] - a[0], len(a[1])) for a, b in zip(glyphs(signs["100%"].ink(ground)), glyphs(signs["100%"].ink(ground))[1:]) if a[1] == b[1]]
    ok([pitch for pitch, _ in zeros] == [cell], "the screen: the text's size by its pitch: the two 0 of 100%% are the same pixels one cell apart, the %d px the state file says a cell is" % cell,
       (zeros, [x for x, _ in glyphs(signs["100%"].ink(ground))]))
    # pins
    changes, pid, crew = len(d.log()), d.bar_pid(), members(group_of(d.loop_pid() or 0))
    said = d.shell("bar", "unpin", "out", PROOF_VERB="unpin")   # a word in the verb's own environment: a bar the verb started itself would carry it
    s = d.until(lambda s: s.status == "ok" and s.find("mic.gauge") and s.find("clock.time") and not s.find("out.gauge") and d.bar_pid() not in (None, pid), "the bar again without out", 20)
    took = base["mic.name"][0] - base["out.name"][0]   # out's three slots and the gap after them
    want = collections.OrderedDict((k, ((r[0] + took,) + r[1:]) if k in ("lan", "wifi.name", "wifi.gauge") else r) for k, r in base.items() if not k.startswith("out."))
    listed = "workspaces pad lan bt wifi mic due notifications light kb bat clock"
    ok(said.returncode == 0 and said.said.startswith("unpinned out") and s.rects() == want and d.pins() == listed and d.bar_env().get("BAR_PINS") == listed and len(d.log()) == changes,
       "spark-shell bar unpin out: its three targets are gone, the modules after it stand where they stood and the ones before it close up to them; the device is not touched",
       (said.said, moved(want, s.rects()), d.pins(), d.log()[changes:]))
    ok(crew and not [p for p in crew if alive(p)] and "PROOF_VERB" not in d.bar_env() and d.bar_env().get("SWAYSOCK") == d.env["SWAYSOCK"],
       "the bar is started again for it through sway, as at login: it has sway's environment, not the verb's, and of the bar before and its status no process is left",
       ([(p, " ".join(cmdline(p))[:60]) for p in crew if alive(p)], d.bar_env().get("PROOF_VERB")))
    pid = d.bar_pid()
    said = d.shell("bar", "pin", "out")
    s = d.until(lambda s: s.status == "ok" and s.find("out.gauge") and s.find("clock.time") and d.bar_pid() not in (None, pid), "the bar again with out", 20)
    ok(said.returncode == 0 and said.said.startswith("pinned out") and s.rects() == base and d.pins() == "" and d.bar_env().get("BAR_PINS") == "",
       "spark-shell bar pin out: it is back, and every target is where it first was", (said.said, moved(base, s.rects()), d.pins()))
    # a narrow screen
    overflow, room = env.get("BAR_OVERFLOW", "").split(), sum(t.w for t in spaces)
    plans = {w: left_out(w, cell, room, blocks, overflow) for w in range(W, 200, -cell)}
    some = next((w for w in sorted(plans, reverse=True) if plans[w][0] and not plans[w][2]), None)      # the widest that loses a block, and no module
    most = next((w for w in sorted(plans, reverse=True) if len(plans[w][0]) - 2 == 3), None)            # the widest that loses three modules
    for width, words in ((some, "a screen %d px wide: an optional block goes first, and no module"),
                         (most, "a screen %d px wide: the optional blocks, then whole modules, the one the config does not name first, then in the config's order; a cell stands for them")):
        gone, kept_, more = plans.get(width, ([], [], False))
        d.sway("output", OUT, "mode", "%dx%d" % (width or W, H))
        d.layout()
        s = d.until(lambda s: s.bar().width == width and s.status == "ok", "the bar %s px wide" % width)
        s = settle(lambda: d.state().bar().dropped == gone and d.state(), 4) or d.state()
        there = [t for t in s.targets() if t.kind not in ("mark", "workspace")]
        ok(width and s.bar().dropped == gone and [t.id for t in there] == (["more"] if more else []) + kept_ and s.find("mark").rect == base["mark"]
           and all(t.x + t.w <= width - cell for t in s.targets()) and all(t.w == base[t.id][2] for t in there if t.id != "more"),
           (words % (width or 0)) + " (" + " ".join(gone) + ")", (gone, s.brief()))
    ok(some and most and plans[some][0][:1] == ["out.pct"] and plans[most][0] == ["out.pct", "clock.date", "lan", "wifi", "bat"],
       "the order is the config's own (BAR_OVERFLOW=%s): out's percent before the date, then lan, which it does not name, wifi and bat" % OVERFLOW, (plans.get(some), plans.get(most)))
    rest_ = s.find("more")
    n = len(d.opened())

    def dots():
        return bool(rest_ and d.grab(*rest_.rect).ink(ground)), None
    good, _ = seen(dots)
    if rest_:
        d.click(rest_.mid, high // 2)
        d.move(W // 2, H // 2)
    ok(rest_ and (rest_.kind, rest_.name, rest_.w) == ("open", "more", cell) and good and (settle(lambda: d.opened()[n:], 8) or [""])[-1].endswith(" dialog"),
       "the cell for the modules left out: an ellipsis, named more, and a click on it opens home, where they are", (rest_ and rest_.rect, d.opened()[n:]))
    d.shot("geometry-narrow")
    d.sway("output", OUT, "mode", "%dx%d" % (W, H))
    d.layout()
    s = d.until(lambda s: s.bar().width == W and not s.bar().dropped and s.find("clock.date"), "the bar %d px wide again" % W)
    ok(s.rects() == base, "the screen wide again: the whole line is back, every target where it was", moved(base, s.rects()))
    # the bottom edge, by the verb
    said = d.shell("bar", "bottom")
    s = d.until(lambda s: s.bar().edge == "bottom" and s.status == "ok" and s.find("clock.time"), "the bar at the bottom", 30)
    area = settle(lambda: next((w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1 and H - (w["rect"]["y"] + w["rect"]["height"]) - w["rect"]["x"] == BAR), None), 5) \
        or next(w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1)
    win = d.node(d.windows[0].pid)["rect"]
    ok(said.returncode == 0 and s.rects() == base and H - (area["y"] + area["height"]) - area["x"] == BAR and area["y"] == area["x"] and win["y"] + win["height"] <= H - BAR
       and d.look().get("ground") == d.pal["BG"],
       "spark-shell bar bottom: the state file says bottom, every target at the same place along it; the windows' area ends %d px over the screen's edge and a tiled window's rect with it, clear of the bar" % BAR,
       (said.said[-200:], s.bar().edge, moved(base, s.rects()), area, win))
    low, saw = mark_seen(d, mark.x, H - BAR + (BAR - MARK) // 2)
    up, _ = mark_seen(d, mark.x, (BAR - MARK) // 2, False)
    ok(low and up, "on the screen the mark stands in the bottom %d rows, and no longer at the top" % BAR, saw)
    d.shot("geometry-bottom")
    said = d.shell("bar", "top")
    s = d.until(lambda s: s.bar().edge == "top" and s.status == "ok" and s.find("clock.time"), "the bar at the top again", 30)
    area = settle(lambda: next((w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1 and w["rect"]["y"] - w["rect"]["x"] == BAR), None), 5) \
        or next(w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1)
    ok(said.returncode == 0 and s.rects() == base and area["y"] - area["x"] == BAR and H - (area["y"] + area["height"]) == area["x"],
       "spark-shell bar top: back at the top, the windows' area %d px under the screen's edge again" % BAR, (said.said[-200:], moved(base, s.rects()), area))
    # two screens
    d.sway("create_output")
    s = d.until(lambda s: len(s.outputs) == 2 and all(b.targets and b.targets[-1].id == "clock.time" for b in s.outputs.values()), "a bar on each of two screens", 15)
    outs = {o["name"]: o for o in d.layout()}
    other = next(name for name in s.outputs if name != OUT)
    theirs = {name: ["workspace:%d" % w["num"] for w in sorted(d.ask("get_workspaces"), key=lambda w: w["num"]) if w["output"] == name] for name in s.outputs}
    ok(set(outs) == set(s.outputs) and all(s.bar(n).width == outs[n]["rect"]["width"] and s.bar(n).height == BAR and s.bar(n).edge == "top" for n in outs)
       and all([t.id for t in s.targets(n) if t.kind == "workspace"] == theirs[n] and [t.id for t in s.targets(n) if t.kind != "workspace"] == [k for k in base if not k.startswith("workspace:")] for n in outs)
       and s.rects(OUT) == base and any(t.flags == {"selected", "visible"} for t in s.targets(OUT)) and [t.flags for t in s.targets(other) if t.kind == "workspace"] == [{"visible"}],
       "two screens (swaymsg create_output): a bar on each, %d px, the mark and the same status on both, each with its own workspaces; the first screen's bar has not moved" % BAR,
       (s.brief(), theirs))
    at = outs[other]["rect"]
    good, saw = mark_seen(d, at["x"] + mark.x, at["y"] + (BAR - MARK) // 2)
    ok(good, "on the second screen the mark is drawn too, the same pixels", saw)
    d.sway("mode", "resize")
    s = d.until(lambda s: s.mode == "resize", "the binding mode in the state file")

    def both():
        inks = [d.grab(outs[n]["rect"]["x"] + max(t.x + t.w for t in s.targets(n) if t.kind == "workspace"), outs[n]["rect"]["y"], 12 * cell, high).ink(ground) for n in (OUT, other)]
        return all(inks), [len(i) for i in inks]
    good, saw = seen(both)
    ok(good, "a binding mode stands after the workspaces on both screens' bars", saw)
    d.shot("geometry-second-screen", other)
    d.sway("mode", "default")
    d.until(lambda s: not s.mode, "the default mode again")
    d.sway("focus", "output", other)
    d.shell("bar", "keys")
    s = d.until(lambda s: s.focused(other) == "mark", "the keys on the second screen's bar")
    sign = s.find("out.name", other)
    d.key("Escape")
    d.until(lambda s: not s.focused(other), "Escape to give the keyboard back")
    d.click(at["x"] + sign.mid, at["y"] + high // 2)
    both_say = d.until(lambda s: s.named("out.name", other) == "output muted" and s.named("out.name") == "output muted", "out muted by a click on the second screen's bar")
    ok(not s.focused(OUT) and d.muted("out"), "the keys go to the bar of the screen that has the focus, and a click on the second screen's bar acts: out is muted, and both bars say so", both_say.brief())
    d.click(at["x"] + sign.mid, at["y"] + high // 2)
    d.until(lambda s: s.named("out.name") == "output 40%", "out unmuted")
    d.sway("focus", "output", OUT)


def relook(d):
    """The look travels in the line: another palette while the bar runs, written as a theme's change writes it,
    then previewed and applied through spark-shell; the mark and the contrast again on the light ground."""
    enter("identity", "the look travels in the line: another palette, the bar running")
    s = d.rest()
    bar, high, clock = d.bar_pid(), s.bar().height, s.find("clock.time")
    gap = (max(t.x + t.w for t in s.targets() if t.kind == "workspace") + min(t.x for t in s.targets() if t.kind not in ("mark", "workspace"))) // 2

    def wears(bg, fg):
        """Whether the bar's ground and its text are those colors on the screen, and what they are."""
        def read():
            ground, text = d.grab(gap, high // 2, 1, 1).px(0, 0), d.grab(*clock.rect)
            return near(ground, bg, 3) and near(text.ground(), bg, 3) and worn(text, bg, fg), (ground, text.strongest(bg), text.inked(bg, fg))
        return read

    def gallery(name):
        text = (REPO / "gallery/theme" / (name + ".env")).read_text()
        return [rgb(re.search(r"^THEME_%s=#([0-9a-fA-F]{6})$" % key, text, re.M).group(1)) for key in ("BG", "FG")]
    d.palette("light")
    d.nudge()
    pal = d.pal
    mine = rgb(pal["BG"]), rgb(pal["FG"])
    good, saw = seen(wears(*mine), 20)
    look = d.look()
    ok(good and d.bar_pid() == bar and (look.get("ground"), look.get("fg")) == (pal["BG"], pal["FG"]),
       "another palette written while the bar runs: the next line carries its look, and the bar's ground and text are its colors on the screen, the same process (pid %s)" % bar,
       (saw, look, bar, d.bar_pid()))
    s = d.rest()
    mark = s.find("mark")
    good, r = mark_seen(d, mark.x, (high - mark.w) // 2)
    ok(good, "on the light ground the mark is the light asset's own pixels (%s) at %d px, %.2f a channel off; the dark ground's mark is %.2f off"
       % (r["file"], MARK, r["fits"].get(MARK, -1), r["other"]), r)
    d.shot("look-light")
    enter("accessibility", "the light palette")
    contrasts(d, s)
    enter("identity", "a theme previewed and applied through spark-shell, the bar running")
    said = d.shell("bar", "panel", "theme", "preview", "tokyonight-night")   # the dialog's own step, by its verb
    good, saw = seen(wears(*gallery("tokyonight-night")), 20)
    ok(said.returncode == 0 and good and d.bar_pid() == bar, "a palette looked at (spark-shell bar panel theme preview tokyonight-night): the bar wears it at once, the same process",
       (said.said[-160:], saw, bar, d.bar_pid()))
    said = d.shell("bar", "panel", "theme", "preview", "off")
    good, saw = seen(wears(*mine), 20)
    ok(said.returncode == 0 and good and d.bar_pid() == bar, "the preview off: the bar wears the palette in use again", (said.said[-160:], saw, bar, d.bar_pid()))
    said = d.shell("theme", "nord")
    good, saw = seen(wears(*gallery("nord")), 30)
    ok(said.returncode == 0 and good and d.bar_pid() == bar, "spark-shell theme nord: the theme applied, the bar wears it with no restart, the same process", (said.said[-160:], saw, bar, d.bar_pid()))
    d.shot("look-applied")


def main():
    for tool in ("sway", "swaymsg", "foot", "grim", "wtype", "jq"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    binary = bar_binary()
    evidence = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="bar-proof.", dir="/var/tmp"))
    evidence.mkdir(parents=True, exist_ok=True)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))   # the bar is ended with ABRT here: no core file of it
    began = time.time()
    d = Desk(evidence.resolve(), binary)
    atexit.register(d.stop)
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, lambda number, _: sys.exit(128 + number))
    on_failure.append(d.keep_failure)
    try:
        d.start()
        for part in (lifecycle, identity, behavior, states, accessibility, geometry, relook, names):
            try:
                part(d)
            except AssertionError as e:
                ok(False, str(e))
            except Exception as e:   # a part that could not go on fails, and the next one starts from rest
                traceback.print_exc()
                ok(False, "the checks could not go on: %s: %s" % (type(e).__name__, e))
    except AssertionError as e:
        ok(False, str(e))
    finally:
        d.stop()
    global gate
    gate = "lifecycle"
    ok(d.left == [], "the session over: the bar, its keeper and its status ended with their sway, by themselves", d.left)
    took = time.time() - began
    counted = ", ".join("%s %d" % (name, good + bad) for name, (good, bad) in tally.items())
    print("bar proof: %s (%s) in %d s; the screens are in %s" % ("every gate holds" if failed == 0 else "%d failed" % failed, counted, took, evidence))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
