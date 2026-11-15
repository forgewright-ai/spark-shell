#!/usr/bin/env python3
"""Prove spark's bar on a headless sway of its own, through spark-shell: python3 test/bar_desktop_proof.py [DIRECTORY].

DIRECTORY takes the screens, and while the proof runs a folder of its work: a throwaway HOME, a runtime folder, a
temporary one, the stand-ins. Nothing of the machine is touched: the sway is a headless one the proof starts and
ends by its pid, the sound tool is a stand-in that keeps its state in files (wpctl's answers; pactl, amixer and
pw-dump are stand-ins too, and so are the tools of the notifications and of bluetooth, the players, tmux and spark,
which a verb could reach), the dialog's terminal is recorded and never opened, the machine's wire, wifi, bluetooth
and battery are a fixture, and the palettes are the proof's own, never a theme of the machine's: their tones are
of hues apart, so a pixel read off the screen says which tone drew it.

Three things the home sets so that every family's sway and fonts give the same answers. The pointer is a theme of
the proof's with no image: it hovers and clicks, and no capture has a cursor in it. The home's fontconfig asks for
subpixel rendering, as Ubuntu's does for every home: the bar draws its text gray all the same, so a color read off
the screen is the color it was handed. And the proof reaps what its session orphans, as an init does: a
container's first process reaps none, and a dead process nobody reaped still answers kill -0.

sway's own lines for the bar are read from the template: exec spark-shell bar start, the key bound to spark-shell
bar keys, and the resize mode. So the bar under proof is the one spark-shell starts, under its keeper, reading the
real spark-shell bar status. What is measured is what the bar promises: its cells, the colors it was handed, its
own geometry, by its state file and a few pixels a claim; never a font's outline, and never a time: how long a
thing takes, what is drawn while a number flows or before the shell answers, how often the bar wakes are the
unit tests', which hand the clock in (component/bar/src/bar.rs). The five gates of the bar's review, each check
named by its gate:

1 identity       the logo is the asset's own pixels at 24 px, one ink, the dark ground's or the light one's; the
                 workspaces are ten places of three cells in the glyph family's pair, stone, star and banner,
                 star's one unbroken line; the plate, in its place, says where you are in two digits; a gauge
                 is the same pair; the signs are icons, the bar's own drawings; a family, a palette, a preview and a theme are drawn
                 by the same process
2 behavior       by the pointer and by the keys, through the real status loop and the stand-in sound tool: the
                 sign mutes, a click on the gauge sets the level where it was, the wheel and Up and Down step
                 it, Home and End set its ends, Left and Right move past it; a change that fails comes back; a
                 place shows its workspace; the number and the other modules open their section, the logo
                 home; pin, unpin, hide and show; a button on a window, or the pointer's travel, gives the keys back
3 states         muted, off, the wire down, a microphone that records, a reminder and a window that ask, no
                 sound device, the status shell killed while its jobs hold its pipe and back with none of them
                 left, the bar ended with ABRT and started again by its keeper, stopped on purpose, loading
                 before the first line, a binding mode, and a screen at rest: no bar and no room kept while it
                 shows the rest workspace
4 accessibility  the tones on the screen are the look's, the accent on the plate and the keys' line alone; the
                 text reads at 4.5 to 1 on the ground and on a chip, and the plate's digits are the look's ink;
                 under the pointer each part alone stands on a chip of the lit tone, in its own color, a dim one
                 raised, every sign's chip the same size; the keys go through every target once, left to right,
                 a line at the plate's foot under the one they are on; every control has a name; nothing moves
                 at rest
5 geometry       the spec's numbers at 16 px, by the state file and by the screen: the run of 300 px, the plate
                 of 30 by 28 in its place, gaps of one, three and five cells, the hairline before the time; no
                 cell moves with a value, a state or the workspace shown; what a bar short of width gives up, in
                 order; the bottom edge; two screens, each with its own plate, one at rest alone

BAR_PROOF_FONT names a face for the proof's config and hides the Monaspace faces from the proof's home: this
machine as one of the rows that have DejaVu Sans Mono alone. BAR_PROOF_TIMES says how long each gate took.
spark-bar is SPARK_SHELL_BAR, else component/bar/target's release build. Needs sway, swaymsg, foot, grim, wtype,
jq and python3; fc-list where there is one."""
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
BAR, TEXT, MARK, CELL = 36, 16, 24, 10       # the spec's sizes at 12 points: the bar, its text, the logo, a cell
OVERFLOW = "kb wifi mic out bat"             # the config's order here, not the default one; lan and bt are not named
MODULES = "pad lan bt wifi out mic due light kb bat clock notifications".split()   # the line's order
GROUPS = dict(pad="windows", lan="connections", bt="connections", wifi="connections", out="sound", mic="sound", due="tasks",
              light="seat", kb="seat", bat="seat", clock="time", notifications="time")
LOOK = ("fg", "accent", "muted", "ground", "lit", "attention", "alert", "alpha", "full", "light", "motion", "ink")   # the look's slots, as BAR_FG and the rest
SLOTS = ("BAR_FG", "BAR_ACCENT", "BAR_MUTED", "BAR_GROUND", "BAR_LIT", "BAR_ATTENTION", "BAR_ALERT", "BAR_ALPHA", "BAR_GAUGE_FULL", "BAR_GAUGE_LIGHT", "BAR_MOTION", "BAR_INK")
RESTS = "idle"                               # the rest name spark-shell hands the bar (BAR_REST): the idle screen's workspaces
FACT = {"name", "group", "sign", "icon", "text", "cells", "bold", "state", "set", "pinned", "label", "toggle"}   # a module's fields; level where it has one
ICONS = set(re.findall(r'^    "([a-z-]+)",$', (REPO / "component" / "bar" / "src" / "icons.rs").read_text(), re.M))   # the drawings the bar has, by name
KINDS = ("mark", "workspace", "level", "open", "toggle")
STATES = ("ok", "muted", "off", "missing", "wrong", "asks", "records")
FLAGS = {"focused", "hover", "selected", "visible", "urgent", "empty"}
FAMILIES = (("stone", "\u25b0", "\u25b1"), ("star", "\u2501", "\u2500"), ("banner", "\u25ae", "\u25af"))   # each family's gauge pair, full and light
REST = (["mark"] + ["workspace:%d" % n for n in range(1, 11)]
        + ["lan.name", "bt.name", "wifi.name", "out.name", "out.gauge", "out.pct", "mic.name", "kb.name", "kb.text", "bat.name", "bat.text", "clock.text", "notifications.name"])
# the proof's own palettes, a dark ground and a light one: BG, FG, ACCENT, MUTED and the sixteen slots. The tones the
# bar draws in (the text, the muted, the accent, slot 1 the red, slot 3 the attention) are hues apart on each
PALETTES = {
    "dark": ("1f2430", "e6e9ef", "5fb3ff", "5a9a8a",
             "171b24 ff6b6b 7ee081 ffcc66 5fb3ff c79bff 5fd7d7 c8ccd4 6b7480 ff8a8a 9bea9d ffd98a 8cc8ff d8b8ff 8ae6e6 ffffff"),
    "light": ("f4f1ea", "2b2f38", "1a5fb4", "8f74a6",
              "2b2f38 b3261e 2f6f2f 7a4f00 1a5fb4 7b3fa0 0e6b6b d9d5cc 5c6370 c0392b 3c8a3c 8f6200 2f76d0 8d50b5 168080 f4f1ea"),
}
# the light one with an accent its ground does not read on, 2 to 1: what is written on that accent is another ink
PALETTES["pale"] = PALETTES["light"][:2] + ("5fb3ff",) + PALETTES["light"][3:]
MACHINE = (("class/net/eth0/carrier", "1\n"), ("class/net/wlan0/operstate", "up\n"), ("class/power_supply/BAT0/capacity", "64\n"))   # what a check changes, as it is at rest
WPCTL = r"""#!/bin/sh
# the proof's sound tool: wpctl's answers from files, every change written to one
d=${PROOF_SND:?}
i=0; while [ -e "$d/slow" ] && [ "$i" -lt 1800 ]; do sleep 0.05; i=$((i + 1)); done   # slow: no answer until the proof lets go
[ ! -e "$d/down" ] || { echo 'Could not connect to PipeWire' >&2; exit 1; }
side() { case $1 in *SINK*) echo out ;; *) echo mic ;; esac; }
case ${1:-} in
    status) printf 'Audio\n |- Sinks:\n |  *   50. Proof Speakers [vol: 0.40]\n |\n |- Sources:\n |  *   52. Proof Microphone [vol: 0.50]\n |\n' ;;
    get-volume) k=$(side "$2"); l=$(cat "$d/$k.level" 2>/dev/null || echo 40); m=''; [ ! -e "$d/$k.muted" ] || m=' [MUTED]'
        printf 'Volume: %d.%02d%s\n' "$((l / 100))" "$((l % 100))" "$m" ;;
    set-mute|set-volume) : > "$d/busy.$$"; trap 'rm -f "$d/busy.$$"' EXIT   # busy: a change on its way, until it is made
        echo "$*" >> "$d/log"
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
# what records, as pw-dump says it; the notifications nobody looked at, as makoctl lists them; bluetooth's switch
PWDUMP = "#!/bin/sh\ncat \"${PROOF_SND:?}/pw-dump\" 2>/dev/null || echo '[]'\n"
RECORDING = '[{"info":{"props":{"media.class":"Stream/Input/Audio"},"state":"running"}}]\n'
MAKOCTL = """#!/bin/sh
d=${PROOF_SND:?}
case ${1:-} in
    mode) echo default; [ ! -e "$d/dnd" ] || echo do-not-disturb ;;
    list) cat "$d/notes" 2>/dev/null || : ;;
esac
"""
BLUETOOTHCTL = """#!/bin/sh
d=${PROOF_SND:?}
case "$*" in
    show) if [ -e "$d/bt-off" ]; then echo 'Powered: no'; else echo 'Powered: yes'; fi ;;
    'devices Connected') [ -e "$d/bt-alone" ] || echo 'Device AA:BB:CC:DD:EE:FF Proof Buds' ;;
esac
"""
FOOT = """#!/bin/sh
# the proof's opener: the dialog's terminal is recorded and never opened; any other foot is the real one
case " $* " in *" --app-id spark-dialog "*) printf '%%s\\n' "$*" >> "${PROOF_OPENED:?}"; exit 0 ;; esac
exec %s "$@"
"""
SWAYMSG = """#!/bin/sh
# sway's own tool, but for a layout asked for, which is recorded and not passed on: the proof's lasting keyboard has no
# keymap yet, and a sway asked to switch such a keyboard's layout ends on an assertion of its own (seen on 1.12)
case " $* " in *" xkb_switch_layout "*) printf '%%s\\n' "$*" >> "${PROOF_ASKED:?}"; exit 0 ;; esac
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
    print(line.encode("ascii", "backslashreplace").decode(), flush=True)   # a sign in a detail is no ASCII
    if not cond:
        failed += 1
        for hook in on_failure:
            hook()
    return bool(cond)


def note(words):
    print(("  note %s: %s" % (gate, words)).encode("ascii", "backslashreplace").decode(), flush=True)


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


def seen(read, seconds=5):
    """A reading of the screen that holds: read() gives (whether it holds, what it saw), and is asked again
    while it does not, for the bar's frame follows the state file's word by a moment."""
    end = time.time() + seconds
    while True:
        good, saw = read()
        if good or time.time() >= end:
            return bool(good), saw
        time.sleep(0.05)


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


def near(a, b, tolerance=3):
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


def along(c, base, color, slack=4):
    """How far a pixel stands from a base color toward another, 0 to 1, when it lies between the two, as a glyph
    drawn gray in that color over that base does: one measure for the three channels, no colored edge of a
    subpixel face, no other color. None when it lies elsewhere."""
    span = [color[i] - base[i] for i in range(3)]
    wide = max(range(3), key=lambda i: abs(span[i]))
    if abs(span[wide]) < 24:
        return None
    t = (c[wide] - base[wide]) / float(span[wide])
    if -0.04 <= t <= 1.04 and all(abs(base[i] + t * span[i] - c[i]) <= slack for i in range(3)):
        return t
    return None


class Img:
    """A piece of the screen."""

    def __init__(self, w, h, data):
        self.w, self.h, self.data = w, h, data

    def px(self, x, y):
        o = (y * self.w + x) * 3
        return tuple(self.data[o:o + 3])

    def pixels(self):
        d = self.data
        return zip(d[0::3], d[1::3], d[2::3])

    def colors(self):
        return set(self.pixels())

    def part(self, x, y, w, h):
        """A piece of its own: w by h from x, y."""
        return Img(w, h, b"".join(self.data[((y + r) * self.w + x) * 3:((y + r) * self.w + x + w) * 3] for r in range(h)))

    def ink(self, base, least=48):
        """The pixels that far or farther from a base color, as (x, y): what is drawn there."""
        strong = {c for c in self.colors() if far(c, base) >= least}
        return {(i % self.w, i // self.w) for i, c in enumerate(self.pixels()) if c in strong} if strong else set()

    def reach(self, base, color):
        """Against a color it should be drawn in over a base: (whether every pixel lies between the two, how far
        the strongest goes, 1 the color itself)."""
        most = 0.0
        for c in self.colors():
            t = along(c, base, color)
            if t is None:
                return False, most
            most = max(most, t)
        return True, most

    def tone(self, base, tones, least=0.35):
        """The tones it can be drawn in over a base, by name: each one whose color every pixel lies toward, the
        strongest a good part of the way. One name for a piece in one tone; none for an empty or a mixed one."""
        found = []
        for name, color in tones.items():
            lies, most = self.reach(base, color)
            if lies and most >= least:
                found.append(name)
        return sorted(found)

    def cover(self, base, color):
        """How much of the color each pixel has over the base, 0 to 1: a glyph's shape, whatever it is drawn in."""
        return [along(c, base, color) or 0.0 for c in self.pixels()]

    def run(self, x, y, color):
        """The run of a color along row y through x: (its first column, its width)."""
        if not near(self.px(x, y), color):
            return x, 0
        x0, x1 = x, x + 1
        while x0 > 0 and near(self.px(x0 - 1, y), color):
            x0 -= 1
        while x1 < self.w and near(self.px(x1, y), color):
            x1 += 1
        return x0, x1 - x0

    def fall(self, x, y, color):
        """The run of a color down column x through y: (its first row, its height)."""
        if not near(self.px(x, y), color):
            return y, 0
        y0, y1 = y, y + 1
        while y0 > 0 and near(self.px(x, y0 - 1), color):
            y0 -= 1
        while y1 < self.h and near(self.px(x, y1), color):
            y1 += 1
        return y0, y1 - y0

    def box(self, x, y, color):
        """A box filled with a color, measured from a point on its first row: its run along that row, and down its
        first column the first row and the last one in the color, whatever is drawn on it between. -> (x, y, w, h)"""
        x0, w = self.run(x, y, color)
        rows = [r for r in range(self.h) if near(self.px(x0, r), color)] if w else []
        return (x0, rows[0], w, rows[-1] - rows[0] + 1) if rows else (x0, y, w, 0)

    def runs(self, y, ground):
        """What stands on row y: (first column, width, color) for each run of one color that is not the ground."""
        out, x = [], 0
        while x < self.w:
            c = self.px(x, y)
            if near(c, ground):
                x += 1
                continue
            x0 = x
            while x < self.w and near(self.px(x, y), c):
                x += 1
            out.append((x0, x - x0, c))
        return out


def alike(a, b, slack=0.08):
    """Whether two shapes (Img.cover) are the same glyph: every pixel as much covered."""
    return len(a) == len(b) and all(abs(p - q) <= slack for p, q in zip(a, b))


def census(img, ground, tones):
    """A piece of the screen by tone: for each tone the pixels that can be drawn in it alone, strong enough to
    tell (a faint edge lies toward every tone), and the pixels that lie toward none. -> ({tone: [(x, y)]}, [(x, y)])"""
    kinds = {}
    for c in img.colors():
        if far(c, ground) < 40:
            continue
        on = [name for name, color in tones.items() if along(c, ground, color) is not None]
        kinds[c] = on[0] if len(on) == 1 else "" if not on else None
    only, stray = collections.defaultdict(list), []
    if kinds:
        for i, c in enumerate(img.pixels()):
            k = kinds.get(c)
            if k:
                only[k].append((i % img.w, i // img.w))
            elif k == "":
                stray.append((i % img.w, i // img.w))
    return only, stray


def inside(points, rects):
    """The points that are in none of the rectangles (x, y, w, h)."""
    return [(x, y) for x, y in points if not any(r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3] for r in rects)]


def read_png(path):
    """An 8-bit RGBA PNG as (width, height, rows): the logo's files."""
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


def glyphs(text):
    """A text's glyphs, a cell each, as the bar counts them: a character with the marks that join it."""
    out = []
    for c in text:
        n = ord(c)
        if out and (0x300 <= n <= 0x36f or n == 0x200d or 0x20d0 <= n <= 0x20ff or 0xfe00 <= n <= 0xfe0f):
            out[-1] += c
        else:
            out.append(c)
    return out


def full_cells(level):
    """The cells a gauge of five draws full: level x 5 / 100 rounded, at least one above zero (the spec)."""
    return 0 if level <= 0 else max(1, (min(level, 100) * 5 + 50) // 100)


def level_at(into, width):
    """The level a click `into` pixels into a gauge of that width sets: the place clicked, rounded to 5 (the spec;
    src/bar.sh's bar_click and the bar agree on it)."""
    return max(0, min(100, (into * 100 // width + 2) // 5 * 5))


def plan(line, levels, width, run_end, overflow, cell):
    """The status as the spec lays it on a bar of that width, from the facts of a line and the levels drawn: from
    the right edge leftward with two cells of room, one cell between a module's parts, three between the modules of
    a group, five between groups; a sign a cell a glyph, or two where it is an icon the bar draws; a pinned level's
    gauge of five cells and its number in four, the digits at the
    right; a text as wide as it is drawn in the cells kept for it. Short of width, with five cells kept after the
    workspaces: every number goes, then every gauge, then whole modules, the ones the overflow order does not
    name first, from the left, then in its order, never the time's group; three dots stand for them at the left
    end. -> (the targets as (id, x, w), what was left out in the order it went, the hairline's x or None)"""
    pieces = []

    def size(p):
        parts = [p["sign"], 5 if p["gauge"] else 0, 4 if p["number"] else 0, p["m"].get("cells", 0)]
        return sum(parts) + max(sum(1 for n in parts if n > 0) - 1, 0)

    def gap(a, b):
        return 3 if a["m"]["group"] == b["m"]["group"] else 5

    def cells():
        n = sum(size(p) for p in pieces) + sum(gap(a, b) for a, b in zip(pieces, pieces[1:]))
        return n + ((1 + (5 if pieces else 0)) if more else 0)

    def fits():
        return cells() == 0 or run_end + (5 + cells()) * cell <= width - 2 * cell
    for m in line:
        if m.get("name") in ("look", "logo"):
            continue
        level = levels.get(m["name"], m.get("level"))
        p = {"m": m, "sign": 2 if m.get("icon") in ICONS else len(glyphs(m.get("sign", ""))), "level": level or 0}
        p["gauge"] = p["number"] = bool(m.get("pinned")) and level is not None
        if size(p) > 0:
            pieces.append(p)
    gone, more = [], False
    for part in ("number", "gauge"):
        if not fits():
            for p in pieces:
                if p[part]:
                    p[part] = False
                    gone.append(p["m"]["name"] + (".pct" if part == "number" else ".gauge"))
    may = [p["m"]["name"] for p in pieces if p["m"]["group"] != "time"]
    for name in [n for n in may if n not in overflow] + sorted((n for n in may if n in overflow), key=overflow.index):
        if fits():
            break
        pieces = [p for p in pieces if p["m"]["name"] != name]
        gone.append(name)
        more = True
    if not fits():
        pieces, more = [], False
    x, out, hair, before = width - 2 * cell - cells() * cell, [], None, None
    if more:
        out.append(("more", x, cell))
        x += 6 * cell
    for p in pieces:
        m = p["m"]
        if before:
            x += gap(before, p) * cell
        if m["group"] == "time" and (before["m"]["group"] != "time" if before else more):
            hair = x - 5 * cell + 5 * cell // 2
        before, end, state = p, x + size(p) * cell, m.get("state", "ok")
        if p["sign"]:
            out.append((m["name"] + ".name", x, p["sign"] * cell))
            x += (p["sign"] + 1) * cell
        if p["gauge"]:
            if state != "missing":
                out.append((m["name"] + ".gauge", x, 5 * cell))
            x += 6 * cell
        if p["number"]:
            if state not in ("muted", "missing"):
                blank = 3 - len(str(p["level"]))
                out.append((m["name"] + ".pct", x + blank * cell, (4 - blank) * cell))
            x += 5 * cell
        text = glyphs(m.get("text", ""))[:max(m.get("cells", 0), 0)]
        if text and m.get("text", "").strip():
            out.append((m["name"] + ".text", x, len(text) * cell))
        x = end
    return out, gone, hair


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
    """The bar's state file, read: the status, the binding mode, the levels as they are drawn, then each output's
    bar, its targets and what it left out."""

    def __init__(self, text):
        self.text, self.status, self.mode, self.levels, self.outputs, self.odd = text, "", "", collections.OrderedDict(), collections.OrderedDict(), []
        self.resting = []   # the outputs at rest: no bar on them
        for line in text.splitlines():
            f = line.split("\t")
            try:
                if f == ["bar", "1"]:
                    continue
                if f[0] == "status" and len(f) == 2:
                    self.status = f[1]
                elif f[0] == "mode" and len(f) == 2:
                    self.mode = f[1]
                elif f[0] == "level" and len(f) == 3:
                    self.levels[f[1]] = int(f[2])
                elif f[0] == "rest" and len(f) == 2:
                    self.resting.append(f[1])
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

    def spaces(self, output=OUT):
        return [t for t in self.targets(output) if t.kind == "workspace"]

    def parts(self, output=OUT):
        """The status's targets: all but the logo and the workspaces."""
        return [t for t in self.targets(output) if t.kind not in ("mark", "workspace")]

    def plate(self, output=OUT):
        return next((t for t in self.targets(output) if "visible" in t.flags), None)

    def rects(self, output=OUT):
        return collections.OrderedDict((t.id, t.rect) for t in self.targets(output))

    def focused(self, output=OUT):
        return next((t.id for t in self.targets(output) if "focused" in t.flags), None)

    def hovered(self, output=OUT):
        return next((t.id for t in self.targets(output) if "hover" in t.flags), None)

    def brief(self):
        bars = ["%s %dx%d %s: %s%s" % (b.name, b.width, b.height, b.edge,
                                         " ".join(t.id + ("[%s %s]" % (t.state, ",".join(sorted(t.flags))) if t.flags - {"empty"} or t.state != "ok" else "") for t in b.targets),
                                         (" left out: " + " ".join(b.dropped)) if b.dropped else "") for b in self.outputs.values()]
        return "status %s%s%s, levels %s; %s" % (self.status, (", mode " + self.mode) if self.mode else "", (", at rest " + " ".join(self.resting)) if self.resting else "",
                                                 " ".join("%s %d" % kv for kv in self.levels.items()), "; ".join(bars))


def moved(a, b):
    """Where two sets of rectangles differ, for a check's words."""
    return {k: (a.get(k), b.get(k)) for k in list(a) + [k for k in b if k not in a] if a.get(k) != b.get(k)}


def stays(base, now, but=()):
    """What moved of the targets that two states both have: nothing, when no cell moves with a value or a state.
    A number is as wide as its digits, so its right edge is what stays; a text as wide as it says, so its left one."""
    out = {}
    for k, r in now.items():
        if k in base and k not in but:
            was = base[k]
            same = ((was[0] + was[2], was[1], was[3]) == (r[0] + r[2], r[1], r[3]) if k.endswith(".pct")
                    else (was[0], was[1], was[3]) == (r[0], r[1], r[3]) if k.endswith(".text") else was == r)
            if not same:
                out[k] = (was, r)
    return out


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
        self.opened_file, self.asked_file = self.work / "opened", self.work / "asked"
        self.shell_path = str(REPO / "spark-shell")
        self.children, self.pointer, self.guard, self.stopped, self.left, self.reaps = [], None, None, False, None, False
        self.seen, self.signs, self.shots, self.kept, self.space, self.windows = set(), set("\u2026\u26a0"), 0, 0, (W, H), []
        self.cell, self.high = CELL, BAR
        self.stage()

    def stage(self):
        fake, sys_, proc_ = self.work / "bin", self.work / "sys", self.work / "proc"
        for folder in (self.settings.parent, self.theme.parent, self.work / "tmp", fake, self.snd, self.work / "pts", self.work / "dev", self.work / "root",
                       sys_ / "class/net/eth0", sys_ / "class/net/wlan0/wireless", sys_ / "class/power_supply/BAT0", sys_ / "class/bluetooth/hci0", proc_ / "net"):
            folder.mkdir(parents=True)
        self.run.mkdir(mode=0o700)
        self.real_foot = shutil.which("foot")
        tools = {"wpctl": WPCTL, "foot": FOOT % self.real_foot, "swaymsg": SWAYMSG % shutil.which("swaymsg"), "pw-dump": PWDUMP, "makoctl": MAKOCTL,
                 "bluetoothctl": BLUETOOTHCTL, "ip": "#!/bin/sh\nexit 0\n"}
        # no other sound system, the kernel's own link quality, no light to set, and nothing of the machine's that a verb
        # could reach: its tmux, its spark; and no sound and no notification of the proof's reach the machine's
        tools.update((name, "#!/bin/sh\nexit 1\n") for name in ("pactl", "amixer", "iw", "tmux", "spark", "brightnessctl", "ddcutil"))
        tools.update((name, "#!/bin/sh\nexit 0\n") for name in ("notify-send", "pw-play", "aplay"))
        for name, text in tools.items():
            (fake / name).write_text(text)
            (fake / name).chmod(0o755)
        # the machine: a wire up, bluetooth on, wifi at 70, a battery at 64, so the line has modules enough to leave some out
        for name, text in (("class/net/eth0/device", ""), ("class/net/eth0/type", "1\n"), ("class/net/eth0/operstate", "up\n"),
                           ("class/net/wlan0/device", ""), ("class/net/wlan0/type", "1\n"),
                           ("class/power_supply/BAT0/type", "Battery\n"), ("class/power_supply/BAT0/status", "Discharging\n")) + MACHINE:
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
        # 12 points is the spec's size; ALPHA 1 so the bar's ground is the palette's own color on the screen; two layouts,
        # so the keyboard's module is on the line
        face = self.face = os.environ.get("BAR_PROOF_FONT", "").strip()
        self.config_text = ("DESKTOP=sway\nALPHA=1\nBAR_TEXT=12\nWALLPAPER=none\nPOINTER=proof-blank 24\nBAR_OVERFLOW=%s\nKEYBOARD=us de\n" % OVERFLOW
                            + ("FONT=%s:size=12\n" % face if face else ""))
        self.configure()
        # the home asks fontconfig for subpixel rendering, with Ubuntu's three settings (slight hinting, rgb, the default
        # lcd filter), as that system asks it for every home: the bar's text stays gray
        (self.home / ".config/fontconfig").mkdir()
        (self.home / ".config/fontconfig/fonts.conf").write_text(
            '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n<fontconfig>\n <match target="font">\n'
            + "".join('  <edit name="%s" mode="assign"><%s>%s</%s></edit>\n' % (name, kind, value, kind) for name, kind, value in
                      (("antialias", "bool", "true"), ("hinting", "bool", "true"), ("hintstyle", "const", "hintslight"), ("rgba", "const", "rgb"), ("lcdfilter", "const", "lcddefault")))
            + ' </match>\n'
            # a face named for the proof: the curated faces are hidden from this home too, as on a machine that has none of them
            + (' <selectfont><rejectfont><glob>*onaspace*</glob></rejectfont></selectfont>\n' if face else "")
            + '</fontconfig>\n')
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
                    "SPARK_SHELL_NO_CHIME": "1", "PROOF_SND": str(self.snd), "PROOF_OPENED": str(self.opened_file), "PROOF_ASKED": str(self.asked_file)})
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

    def put(self, path, text):
        """A file written whole beside itself and moved into place: a line of the status that reads it meanwhile
        reads the old one or the new one, never half of one."""
        new = path.with_name(path.name + ".new")
        new.write_text(text)
        os.replace(str(new), str(path))

    def configure(self, more=""):
        """The proof's config as it first was, and what a check adds to it."""
        self.put(self.settings, self.config_text + more)

    def palette(self, name):
        """One of the proof's palettes written as the theme in use, and the tones the bar draws in under it."""
        bg, fg, accent, muted, slots = PALETTES[name]
        self.pal = {"name": name, "BG": bg, "FG": fg, "ACCENT": accent, "MUTED": muted, "ANSI": slots.split()}
        self.put(self.theme, "".join("THEME_%s=#%s\n" % (k, self.pal[k]) for k in ("BG", "FG", "ACCENT", "MUTED"))
                 + "".join("THEME_ANSI_%d=#%s\n" % (i, c) for i, c in enumerate(self.pal["ANSI"])))
        self.ground = rgb(bg)
        self.tones = collections.OrderedDict((("text", rgb(fg)), ("dim", rgb(muted)), ("accent", rgb(accent)),
                                              ("alert", rgb(self.pal["ANSI"][1])), ("attention", rgb(self.pal["ANSI"][3]))))

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
        self.keyboard = self.lasting()

    def lasting(self, *types):
        """A keyboard on the seat until it is ended: a wtype that sleeps. With nothing to type after its sleep it has
        no keymap; with a key to type it has one, of one layout."""
        child = subprocess.Popen(["wtype", "-s", "600000", *types], env=self.env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.children.append(child)
        return child

    def keyboards(self):
        """The seat's keyboards as sway lists them: (identifier, how many layouts) each."""
        return [(i.get("identifier"), len(i.get("xkb_layout_names") or [])) for i in self.ask("get_inputs") if i.get("type") == "keyboard"]

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
        """A failed check leaves the state file, the bar's log, what the sound tool heard, the processes and the
        screen in the directory; the first few."""
        if self.stopped or self.kept >= 6:
            return
        self.kept += 1
        self.keep_log()
        for kept, name in ((self.state_file, "bar.state"), (self.snd / "log", "sound.log")):
            try:
                shutil.copyfile(str(kept), str(self.evidence / ("failure-%02d-%s" % (self.kept, name))))
            except OSError:
                pass
        try:   # a click that never lands: is the status loop there, is its reader, is one of its jobs still at work
            listed = subprocess.run(["ps", "-eo", "pid,ppid,pgid,stat,etimes,args"], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10).stdout
            (self.evidence / ("failure-%02d-processes.txt" % self.kept)).write_text(listed)
        except (OSError, subprocess.SubprocessError):
            pass
        try:
            subprocess.run(["grim", str(self.evidence / ("failure-%02d.png" % self.kept))], env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
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

    def until(self, test, what, seconds=20, said=None):
        """The state file once it says `test`; a timeout says what was waited for and what the file said."""
        end, s = time.time() + seconds, None
        while True:
            s = self.state()
            try:
                if s is not None and test(s):
                    return s
            except (AttributeError, TypeError, KeyError):   # a target the test names is not there yet
                pass
            if time.time() >= end:
                break
            time.sleep(0.02)
        raise AssertionError("waited %ds for %s; the state file says: %s" % (said or seconds, what, s.brief() if s else "nothing, there is none"))

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
        return subprocess.run(["swaymsg", *words], env=self.env, stdin=subprocess.DEVNULL, capture_output=True, encoding="utf-8", errors="replace", timeout=10).stdout

    def ask(self, kind):
        return json.loads(self.sway("-r", "-t", kind) or "null") or []

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

    def line(self, **more):
        """The status line as spark's bar is handed it now: the objects of spark-shell bar status --once, the look
        first. The glyphs the bar draws from a font are kept, for the fonts to be asked for each: the look's pair, and a
        sign that has no icon."""
        try:
            line = json.loads(self.shell("bar", "status", "--once", SPARK_BAR="1", **more).stdout or "[]")
        except ValueError:
            return []
        for block in line:
            keys = ("full", "light") if block.get("icon") in ICONS else ("sign", "full", "light")
            self.signs |= {c for k in keys for c in block.get(k, "") if ord(c) > 126}
        return line

    def grab(self, x, y, w, h):
        # grim ended by a signal is the capture's fall, not the bar's (a container's small shared memory can run
        # out for a moment while a wallpaper is drawn): it is asked again, three times at most
        for left in (2, 1, 0):
            got = subprocess.run(["grim", "-t", "ppm", "-g", "%d,%d %dx%d" % (x, y, w, h), "-"], env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
            if got.returncode == 0:
                return Img(*ppm(got.stdout))
            if got.returncode > 0 or not left:
                got.check_returncode()
            time.sleep(0.5)

    def strip(self, at=(0, 0), width=None):
        """A bar as the screen has it, whole: the one at the top of the screen at `at`."""
        return self.grab(at[0], at[1], width or self.space[0], self.high)

    def shot(self, name, output=OUT):
        self.shots += 1
        subprocess.run(["grim", "-o", output, str(self.evidence / ("%02d-%s.png" % (self.shots, name)))], env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=20)

    def lines_of(self, path):
        try:
            return path.read_text().splitlines()
        except OSError:
            return []

    def opened(self):
        return self.lines_of(self.opened_file)

    def asked(self):
        return self.lines_of(self.asked_file)

    def log(self):
        return self.lines_of(self.snd / "log")

    def level(self, side):
        try:
            return int((self.snd / (side + ".level")).read_text())
        except (OSError, ValueError):
            return None

    def muted(self, side):
        return (self.snd / (side + ".muted")).exists()

    def conf(self, key):
        """A key of the proof's config as spark-shell last wrote it, or None."""
        return ([line[len(key) + 1:] for line in self.settings.read_text().splitlines() if line.startswith(key + "=")] or [None])[-1]

    # --- what it sends
    def sound(self, out, muted, mic, mic_muted):
        """The sound tool's state, set from outside the bar, as another program's change is: once no change of the
        bar's own is on its way, for one that lands after this would undo it."""
        settle(lambda: not list(self.snd.glob("busy.*")), 10)
        for side, level, off in (("out", out, muted), ("mic", mic, mic_muted)):
            (self.snd / (side + ".level")).write_text("%d\n" % level)
            if off:
                (self.snd / (side + ".muted")).write_text("")
            elif (self.snd / (side + ".muted")).exists():
                (self.snd / (side + ".muted")).unlink()

    def flag(self, name, on, text=""):
        if on:
            (self.snd / name).write_text(text)
        elif (self.snd / name).exists():
            (self.snd / name).unlink()

    def machine(self, name, text):
        """A file of the fixture machine: its wire, its wifi, its battery."""
        (self.work / "sys" / name).write_text(text)

    def remind(self, on):
        """A reminder due five minutes ago in the home's calendar, or none."""
        ics = self.home / "calendar/proof.ics"
        if on:
            ics.parent.mkdir(exist_ok=True)
            ics.write_text("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:proof-1\nDTSTART:%s\nSUMMARY:the proof's reminder\nEND:VEVENT\nEND:VCALENDAR\n"
                           % time.strftime("%Y%m%dT%H%M00", time.localtime(time.time() - 300)))
        elif ics.exists():
            ics.unlink()

    def notes(self, n):
        """So many notifications nobody looked at, as mako lists them."""
        self.flag("notes", n, "".join("Notification %d: note %d\n  App name: proof\n" % (i, i) for i in range(1, n + 1)))

    def nudge(self):
        """A line now, as spark-shell asks its loop for one after any change (bar_redraw): SIGUSR1 to the loop."""
        pid = self.loop_pid()
        if pid:
            try:
                os.kill(pid, signal.SIGUSR1)
            except OSError:
                pass

    def told(self, test, what, seconds=20):
        """The state file once a line of the status says `test`: a line is asked for, and asked for again each
        second and a half, for a line that comes while the hand's steps are not all answered may be taken for an
        answer to one of them."""
        end = time.time() + seconds
        while True:
            self.nudge()
            left = end - time.time()
            try:
                return self.until(test, what, max(0.1, min(1.5, left)), seconds)
            except AssertionError:
                if left <= 1.5:
                    raise

    def says(self, out, muted=False, mic=50, mic_muted=False, seconds=20):
        """The sound set from outside, a line asked for, and the state file once the bar shows it."""
        self.sound(out, muted, mic, mic_muted)
        want = ("output muted" if muted else "output %d%%" % out, "microphone muted" if mic_muted else "microphone %d%%" % mic)
        return self.told(lambda s: s.status == "ok" and (s.named("out.name"), s.named("mic.name")) == want and (s.levels.get("out"), s.levels.get("mic")) == (out, mic),
                         "the bar to show %s and %s" % want, seconds)

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

    def away(self):
        """The pointer off every bar, and the state file saying so."""
        self.move(self.space[0] // 4, H // 2)
        return self.until(lambda s: not any(s.hovered(o) for o in s.outputs), "the pointer off the bar", 5)

    def over(self, t, at=(0, 0)):
        """The pointer on a target, and the state file saying so."""
        self.move(at[0] + t.mid, at[1] + self.high // 2)
        return self.until(lambda s: any(s.hovered(o) == t.id for o in s.outputs), "the pointer on " + t.id, 5)

    def button(self, down):
        self.pointer.send(5, 2, self.stamp(), 272, 1 if down else 0)   # BTN_LEFT
        self.pointer.send(5, 4)
        self.pointer.sync()

    def click(self, x, y=None):
        self.move(x, self.high // 2 if y is None else y)
        time.sleep(0.08)
        self.button(True)
        time.sleep(0.04)
        self.button(False)

    def wheel(self, notches):
        """The wheel turned: 15 px of scroll a notch, down when positive, as a mouse's wheel says it."""
        self.pointer.send(5, 3, self.stamp(), 0, (notches * 15 * 256) & 0xffffffff)   # axis, vertical, a fixed-point value
        self.pointer.send(5, 4)
        self.pointer.sync()

    def key(self, name, shift=False, times=1):
        words = (["-M", "shift"] if shift else []) + ["-k", name] + ["-s", "25", "-k", name] * (times - 1) + (["-m", "shift"] if shift else [])
        subprocess.run(["wtype", "-s", "80", *words, "-s", "40"], env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=20)

    def chord(self, modifier, name):
        subprocess.run(["wtype", "-s", "80", "-M", modifier, "-k", name, "-m", modifier, "-s", "40"], env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=10)

    def keys_on(self):
        """Super and the key sway's template binds to spark-shell bar keys."""
        self.chord("logo", self.keys_key)

    def focus(self, ident):
        """The keys moved to a target: Tab or Shift+Tab, whichever is the shorter way round."""
        s = self.until(lambda s: s.focused(), "the keys on the bar", 5)
        ids = s.ids()
        ahead = (ids.index(ident) - ids.index(s.focused())) % len(ids)
        if ahead:
            back = len(ids) - ahead
            self.key("Tab", shift=back < ahead, times=min(ahead, back))
        try:
            return self.until(lambda s: s.focused() == ident, "the keys on " + ident, 4)
        except AssertionError:   # a key that was lost on the way: one at a time from where they are
            for _ in range(len(ids) + 1):
                s = self.state()
                if s.focused() == ident:
                    return s
                was = s.focused()
                self.key("Tab")
                self.until(lambda s: s.focused() not in (None, was), "Tab to move the keys on from %s" % was, 5)
            raise AssertionError("Tab never reached %s; the state file says: %s" % (ident, self.state().brief()))

    def terminal(self, title):
        child = subprocess.Popen([self.real_foot, "--title", title, "sleep", "900"], env=self.env, cwd=str(self.work), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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

    def at_rest(self, s):
        b = s.bar()
        return bool(s.status == "ok" and not s.mode and not s.resting and len(s.outputs) == 1 and b and b.width == W and b.edge == "top" and not b.dropped
                    and s.ids() == REST and all(t.state == "ok" for t in b.targets) and dict(s.levels) == {"wifi": 70, "out": 40, "mic": 50}
                    and (s.named("out.name"), s.named("mic.name")) == ("output 40%", "microphone 50%")
                    and s.find("workspace:1").flags == {"selected", "visible"} and ("empty" in s.find("workspace:2").flags) == (not self.windows)
                    and not any(t.flags & {"focused", "hover", "urgent"} for t in b.targets))

    def rest(self, seconds=30):
        """The bar as a gate finds it: running as the config first had it, in the dark palette, one screen 1920
        wide, at the top, the first workspace shown, the machine as it first was, the sound at 40 and 50, the
        pointer and the keys off it."""
        for name in ("down", "fail", "slow", "bt-off", "bt-alone", "dnd", "notes", "pw-dump"):
            self.flag(name, False)
        for name, text in MACHINE:
            if (self.work / "sys" / name).read_text() != text:
                self.machine(name, text)
        self.remind(False)
        s = self.state()
        for name in list(s.outputs if s else []):
            if name != OUT:
                self.sway("output", name, "unplug")
        if not s or not s.bar() or s.bar().width != W or len(s.outputs) != 1:
            self.sway("output", OUT, "mode", "%dx%d" % (W, H))
        self.layout()
        self.move(W // 4, H // 2)
        if s and s.mode:
            self.sway("mode", "default")
        if s and any(s.focused(o) for o in s.outputs):
            self.key("Escape")
        if self.focused_space() != 1:
            self.sway("workspace", "number", "1")
        self.sound(40, False, 50, False)
        if self.settings.read_text() != self.config_text:   # a gate left the config changed: as it was, said by the next line
            self.configure()
        if self.pal["name"] != "dark":
            self.palette("dark")
        if s and s.bar() and s.bar().edge != "top":
            self.shell("bar", "top")
        if self.bar_pid() and not settle(self.loop_pid, 3):   # a bar whose status never came back: started again
            self.end_bar()
        if not self.bar_pid():
            self.shell("bar", "start")
        return self.told(self.at_rest, "the bar at rest: the whole line, out at 40 and the mic at 50, workspace 1 shown, no key and no pointer on it", seconds)


def mark_reads(d, x, y, side):
    """How the screen reads at the logo's square (its left, its top, its side), against the asset drawn there at
    five sizes, against the other ground's asset, and against no logo at all; and whether it is one ink."""
    ground = d.ground
    own, other = ("favicon", "favicon-light") if dark(ground) else ("favicon-light", "favicon")
    asset = read_png(REPO / "asset" / (own + "-26.png"))   # the PNG at or above 24 px: bar::mark_file
    img = d.grab(x - 2, y - 2, side + 4, side + 4)
    box, center = (side + 4, side + 4), ((side + 4) / 2.0, (side + 4) / 2.0)
    fits = {size: round(apart(img, drawn(asset, size, box, center, ground)), 2) for size in (side - 4, side - 2, side, side + 2, side + 4)}
    ink = collections.Counter(tuple(row[i:i + 3]) for row in asset[2] for i in range(0, len(row), 4) if row[i + 3] == 255).most_common(1)[0][0]
    return {"file": own + "-26.png", "fits": fits, "best": min(fits, key=fits.get), "ink": "%02x%02x%02x" % ink, "one": img.reach(ground, ink),
            "other": round(apart(img, drawn(read_png(REPO / "asset" / (other + "-26.png")), side, box, center, ground)), 2),
            "blank": round(apart(img, [[ground] * box[0] for _ in range(box[1])]), 2)}


def mark_is(r, side):
    return r["best"] == side and r["fits"][side] <= 2.5 and r["fits"][side] * 3 <= min(r["other"], r["blank"]) and r["one"][0] and r["one"][1] >= 0.9


def mark_seen(d, x, y, there=True):
    """Whether the logo stands in the square at x, y (or, with there False, does not), and how it read."""
    def read():
        r = mark_reads(d, x, y, MARK)
        return mark_is(r, MARK) == there, r
    return seen(read)


def place(strip, t):
    """A target's own cells on a bar's capture, the bar's whole height."""
    return strip.part(t.x, 0, t.w, strip.h)


def first_cell(d, strip, t):
    """The first of a target's cells on a bar's capture, the bar's whole height."""
    return strip.part(t.x, 0, d.cell, strip.h)


def pair_of(d, strip, s):
    """The family's pair as the workspaces wear it now: a cell of a place with a workspace, a cell of a place with none."""
    full = next(t for t in s.spaces() if not t.flags & {"visible", "empty", "urgent", "hover"})
    light = next(t for t in s.spaces() if t.flags == {"empty"})
    return first_cell(d, strip, full), first_cell(d, strip, light)


def run_reads(d, strip, s, output=OUT):
    """The workspaces' run on a capture against the state file: a place with a workspace in the text's tone, one
    with none in the dim one, one that asks in the attention's, its three cells the same pixels; the full ones the
    same pixels, the light ones the same pixels, and the two apart. -> (whether it is so, what was off)"""
    off, fulls, lights = [], set(), set()
    for t in s.spaces(output):
        if t.flags & {"visible", "hover"}:
            continue
        img = place(strip, t)
        want = "attention" if "urgent" in t.flags else "dim" if "empty" in t.flags else "text"
        if img.tone(d.ground, d.tones) != [want]:
            off.append((t.id, want, img.tone(d.ground, d.tones)))
        elif t.w != 3 * d.cell or len({img.part(i * d.cell, 0, d.cell, img.h).data for i in range(3)}) != 1:
            off.append((t.id, "three cells, the same pixels each", t.w))
        elif want != "attention":
            (lights if want == "dim" else fulls).add(img.data)
    if len(lights) > 1 or len(fulls) > 1 or fulls & lights:
        off.append("%d kinds of full place, %d of light, %d shared" % (len(fulls), len(lights), len(fulls & lights)))
    return not off, off


def plate_reads(d, strip, t, ink=None):
    """The plate on a capture: its box as the accent fills it, measured (x, y, w, h); whether all in it lies
    between the accent and the ink its label is written in, the ground's color unless another is named; and the
    columns of its label's ink, counted from its left."""
    accent, ink = d.tones["accent"], d.ground if ink is None else ink
    inset = round(strip.h / 9.0)
    box = strip.box(t.x + 1, inset, accent)
    inner = strip.part(t.x, inset, t.w, strip.h - 2 * inset)
    lies, most = inner.reach(accent, ink)
    cols = sorted({i % inner.w for i, c in enumerate(inner.pixels()) if (along(c, accent, ink) or 0) >= 0.5})
    return box, lies and most >= 0.9, cols


def no_bar(d, at=(0, 0), width=W):
    """Whether no bar is drawn at the top of the screen at `at`, with no window there: the rows a bar would have and
    twelve under them are one flat color, so nothing stands in them and nothing ends where a bar would."""
    def read():
        colors = d.grab(at[0], at[1], width, d.high + 12).colors()
        return len(colors) == 1, sorted(colors)[:4]
    return seen(read)


def label_stands(cols, cell):
    """Whether a plate's label is two characters in its two cells: ink in each, none in the half cells of padding's
    outer part."""
    half = cell // 2
    return bool(cols) and any(half <= c < half + cell for c in cols) and any(half + cell <= c < half + 2 * cell for c in cols) and cols[0] >= 2 and cols[-1] < 3 * cell - 2


def gauge_reads(strip, t, full, light):
    """A gauge's five cells on a capture: F where a cell is the same pixels as a place with a workspace (the pair's
    full glyph in the text's tone), L where it is those of a place with none (the light glyph, dim), ? otherwise."""
    cell = t.w // 5
    return "".join("F" if c == full.data else "L" if c == light.data else "?" for c in (strip.part(t.x + i * cell, 0, cell, strip.h).data for i in range(5)))


def gauge_of(level):
    return "F" * full_cells(level) + "L" * (5 - full_cells(level))


def chip_reads(d, strip, t, lit, color):
    """A part under the pointer on a capture: its chip measured (x, y, w, h), in the lit tone, and whether all
    that stands on it in the part's cells is drawn in a color: the part's own."""
    inset = round(strip.h / 9.0)
    box = strip.box(t.x + 1, inset, lit)
    lies, most = strip.part(t.x, inset, t.w, strip.h - 2 * inset).reach(lit, color)
    return box, lies and most >= 0.5


def raised(d):
    """The dim tone on a chip: halfway to the text's color, a channel at a time."""
    return tuple((a + b) / 2.0 for a, b in zip(d.tones["dim"], d.tones["text"]))


def line_reads(d, strip, t, plate):
    """The keys' line on a capture, a fifth of a cell thick. Under a part: whether the accent fills the last rows of
    the plate's box, the part's width and half a cell at each side (a place's own three cells), and nothing of it
    stands above those rows, under them or past its ends (the plate itself aside). On the plate, where the accent
    could not be seen: whether the ground's color fills the plate's width one thickness above its foot, a strip of
    the accent left under it."""
    accent, ground, inset, half, thick = d.tones["accent"], d.ground, round(strip.h / 9.0), d.cell // 2, max((d.cell + 2) // 5, 1)
    foot = strip.h - inset
    if plate is not None and t.id == plate.id:
        across = range(t.x, t.x + t.w)
        line = all(near(strip.px(x, y), ground) for x in across for y in range(foot - 2 * thick, foot - thick))
        strip_ = all(near(strip.px(x, y), accent) for x in across for y in range(foot - thick, foot))
        above = all(near(strip.px(x, foot - 2 * thick - 1), accent) for x in (t.x, t.x + 1, t.x + t.w - 2, t.x + t.w - 1))
        beside = all(near(strip.px(x, y), ground) for x in (t.x - 1, t.x + t.w) for y in range(foot - 2 * thick, foot + 1))
        return line and strip_ and above and beside, ("on the plate", line, strip_, above, beside)
    pad = 0 if t.kind == "workspace" else half
    x0, x1 = t.x - pad, t.x + t.w + pad
    on_plate = lambda x: plate is not None and plate.x <= x < plate.x + plate.w   # noqa: E731
    filled = all(near(strip.px(x, y), accent) for x in range(x0, x1) for y in range(foot - thick, foot))
    above = [x for x in range(x0, x1) if not on_plate(x) and near(strip.px(x, foot - thick - 1), accent)]
    under = [x for x in range(x0, x1) if near(strip.px(x, foot), accent)]
    past = [x for x in (x0 - 1, x1) if 0 <= x < strip.w and not on_plate(x) and near(strip.px(x, foot - 1), accent)]
    return filled and not above and not under and not past, (filled, above[:3], under[:3], past)


def lifecycle(d):
    enter("lifecycle", "spark-shell starts the bar, as sway's config does at login")
    ok(d.own == ["exec %s bar start" % d.shell_path] and len(d.keys_line) == 1 and d.keys_key and d.mode_lines[-1:] == ['bindsym $mod+r mode "resize"'],
       "sway's template has one line that starts the bar, exec spark-shell bar start, binds Super+%s to spark-shell bar keys, and has the resize mode on Super+r: the proof's sway reads them from it" % d.keys_key,
       (d.own, d.keys_line, d.mode_lines[-1:]))
    s = d.until(lambda s: s.status == "ok" and s.find("out.gauge") and s.find("clock.text"), "the bar's first line", 30)
    d.cell, d.high = s.find("mark").x, s.bar().height
    pid = d.bar_pid()
    ok(pid and cmdline(pid)[:1] == [str(d.binary)] and s.text.startswith("bar\t1\nstatus\tok\n") and "\noutput\t%s\t%d\t" % (OUT, W) in s.text and not s.odd,
       "sway's exec line started spark-bar, the build SPARK_SHELL_BAR names; it holds its lock and writes its state file", (pid, cmdline(pid or 0), s.text[:80], s.odd))
    loop = wait_for(d.loop_pid, "the status loop's pid")
    ok(stat_of(loop)[1] == pid and environ_of(loop).get("SPARK_BAR") == "1" and cmdline(loop)[-3:] == [d.shell_path, "bar", "status"],
       "the bar runs spark-shell bar status itself, with SPARK_BAR=1: every value it shows is the real loop's", (stat_of(loop), cmdline(loop)))
    env, pal = d.bar_env(), d.pal
    want = {"SPARK_SHELL": d.shell_path, "BAR_POSITION": "top", "BAR_FG": pal["FG"], "BAR_ACCENT": pal["ACCENT"], "BAR_MUTED": pal["MUTED"], "BAR_GROUND": pal["BG"],
            "BAR_ATTENTION": pal["ANSI"][3], "BAR_ALERT": pal["ANSI"][1], "BAR_INK": pal["BG"], "BAR_ALPHA": "1", "BAR_GAUGE_FULL": FAMILIES[0][1], "BAR_GAUGE_LIGHT": FAMILIES[0][2],
            "BAR_MOTION": "yes", "BAR_OVERFLOW": OVERFLOW, "BAR_REST": RESTS, "BAR_TRAY_WIDTH": "0", "BAR_LOCK": str(d.lock), "BAR_STATE": str(d.state_file)}
    ok(all(env.get(k) == v for k, v in want.items()) and env.get("BAR_FONT", "").endswith(" 12") and (not d.face or env.get("BAR_FONT") == d.face + " 12")
       and re.fullmatch("[0-9a-f]{6}", env.get("BAR_LIT", "")) and "BAR_PINS" not in env and "BAR_HIDE" not in env,
       "spark-shell starts it with the look of its first line: the proof's own palette, its muted and its red as they are, the ground as the ink, for it reads on this accent, stone's gauge pair, motion, 12 point text; the config's overflow order, the rest name %s, its two files, and no pins: those are each line's to say" % RESTS,
       {k: env.get(k) for k in list(want) + ["BAR_FONT", "BAR_LIT", "BAR_PINS", "BAR_HIDE"] if env.get(k) != want.get(k)})
    line = d.line()
    look, mods = (line[0] if line and line[0].get("name") == "look" else {}), line[1:]
    ok(look and set(look) == set(LOOK) | {"name"} and all(look[k] == env.get(v) for k, v in zip(LOOK, SLOTS)) and all(isinstance(v, str) for v in look.values())
       and not any(t.module == "look" for t in s.targets()),
       "the line carries the look for spark's bar: its first object, named look, the seven colors, the alpha, the gauge pair, the motion and the ink, each a string, as the bar was started with; it is no module and no target", (look, line[:1]))
    order = [m.get("name") for m in mods]
    ok(order == [n for n in MODULES if n in order] and len(order) >= 9
       and all(set(m) - {"level"} == FACT and m["state"] in STATES and m["group"] == GROUPS.get(m["name"]) and "<" not in m["sign"] + m["text"] and m["icon"] in ICONS | {""} and isinstance(m["cells"], int) for m in mods)
       and [m["name"] for m in mods if m["bold"]] == ["clock"] and [m["name"] for m in mods if m["pinned"]] == ["out"] and [m["name"] for m in mods if m["toggle"]] == ["out", "kb"]
       and {m["name"]: (m["level"], m["set"]) for m in mods if "level" in m} == {"wifi": (70, False), "out": (40, True), "mic": (50, True)},
       "then the modules in the bar's order, each a fact and no markup: its group, its sign, its text and the cells kept for it, its state, its label; the time alone bold, out alone pinned, out and the keyboard switched in place, three levels of which the wifi's cannot be set",
       [m for m in mods if set(m) - {"level"} != FACT] or mods)
    sways = d.shell("bar", "status", "--once")
    ok('"full_text"' in sways.stdout and '"markup":"pango"' in sways.stdout and '"look"' not in sways.stdout,
       "without SPARK_BAR the line is the one sway's own bar draws: blocks of marked-up text, and no look", sways.stdout[:160])
    again = d.shell("bar", "start")
    bars = lambda: [p for p in d.ours() if cmdline(p)[:1] == [str(d.binary)]]   # noqa: E731
    more = settle(lambda: bars() != [pid] and bars(), 1.5)   # a second one would come at once
    ok(again.returncode == 0 and not more and d.bar_pid() == pid, "spark-shell bar start again starts no second bar", (again.returncode, again.said, pid, more))
    # the pointer on the bar, where nothing is: no image of it, in a capture that asks for the pointer too
    at = (max(t.x + t.w for t in s.spaces()) + min(t.x for t in s.parts())) // 2
    d.move(at, d.high // 2)

    def bare():
        raw = subprocess.run(["grim", "-c", "-t", "ppm", "-g", "%d,0 48x%d" % (at - 24, d.high), "-"], env=d.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=20).stdout
        img = Img(*ppm(raw)) if raw else None
        return bool(img) and img.colors() == {d.ground}, img and sorted(img.colors())[:4]
    good, saw = seen(bare)
    ok(good, "the proof's pointer has no image: with it on the bar, a capture that takes the pointer too shows the ground alone, so no capture measures a cursor", saw)
    d.away()
    # two terminals, a workspace each: the second workspace stays, and the first one's is the tiled window the bar keeps off
    d.windows = [d.terminal("ONE")]
    d.sway("workspace", "number", "2")
    d.windows.append(d.terminal("TWO"))
    d.sway("workspace", "number", "1")
    d.until(lambda s: "empty" not in s.find("workspace:2").flags and "selected" in s.find("workspace:1").flags, "a window on the second workspace, the first shown")


def identity(d):
    enter("identity", "the logo, the workspaces in the three families, the plate, the gauge, real glyphs")
    s = d.rest()
    pid, cell, high, ground, tones = d.bar_pid(), d.cell, d.high, d.ground, d.tones
    mark, gauge, one = s.find("mark"), s.find("out.gauge"), s.find("workspace:1")
    good, r = mark_seen(d, mark.x, (high - mark.w) // 2)
    ok(mark.w == MARK and good,
       "the logo is the asset's own pixels (%s, the %s ground's) drawn at %d px: of five sizes that one fits, %.2f a channel off; the other ground's logo is %.2f off, no logo %.2f"
       % (r["file"], d.pal["name"], MARK, r["fits"].get(MARK, -1), r["other"], r["blank"]), r)
    ok(r["one"][0] and r["one"][1] >= 0.9 and rgb(r["ink"]) not in tones.values(),
       "it is drawn as the file is, in the file's one ink (#%s) thinned by the ground and in no tone of the look" % r["ink"], r)
    d.shot("identity-logo")
    spaces = s.spaces()
    ok([t.id for t in spaces] == ["workspace:%d" % n for n in range(1, 11)] and [t.w for t in spaces] == [3 * cell] * 10
       and [t.id for t in spaces if "empty" not in t.flags] == ["workspace:1", "workspace:2"],
       "the workspaces are ten places, always: the two that exist and eight with none, three cells each, the one this screen shows too", s.brief())
    refs, last = {}, None
    for name, full_glyph, light_glyph in FAMILIES:
        if name != "stone":
            said = d.shell("theme", "family", name)
            ok(said.returncode == 0 and said.said == "glyph family " + name, "spark-shell theme family %s" % name, (said.returncode, said.said))
        got = {}

        def family():
            strip = d.strip()
            full, light = pair_of(d, strip, s)
            good, off = run_reads(d, strip, s)
            got.update(full=full, light=light, gauge=gauge_reads(strip, gauge, full, light),
                       line=len({x for x, _ in strip.part(spaces[1].x, 0, 27 * cell, high).ink(ground, 40)}),
                       level=len({x for x, _ in place(strip, gauge).ink(ground, 40)}))
            return good and light.data != last, off
        good, saw = seen(family, 10)
        look = d.line()[0]
        ok(good and d.bar_pid() == pid and (look.get("full"), look.get("light")) == (full_glyph, light_glyph),
           "%s: the line's look says its pair (U+%04X, U+%04X), and the run is drawn in it: three cells of the full glyph in the text's color where a workspace is, of the light one in the dim color where none is, each kind the same pixels in every cell; by the same process"
           % (name, ord(full_glyph), ord(light_glyph)), (saw, look, pid, d.bar_pid()))
        ok(got.get("gauge") == gauge_of(40),
           "%s: out's gauge at 40 is the same pair, two cells the pixels of a cell of a place with a workspace and three those of one with none" % name, got.get("gauge"))
        if name == "star":
            ok(got.get("line") == 27 * cell and got.get("level") == 5 * cell,
               "star: the nine places after the plate are one unbroken line, ink in each of their %d columns, and the gauge's five cells another" % (27 * cell), (got.get("line"), got.get("level")))
        refs[name], last = (got["full"].data, got["light"].data), got["light"].data
        d.shot("identity-" + name)
    ok(len({pair for pair in refs.values()}) == 3 and len({p[0] for p in refs.values()}) == 3 and len({p[1] for p in refs.values()}) == 3,
       "the three families draw three pairs: no full glyph and no light one is the pixels of another family's")
    back = d.shell("theme", "family", "stone")
    good, saw = seen(lambda: (pair_of(d, d.strip(), s)[1].data == refs["stone"][1], None), 10)
    ok(back.returncode == 0 and good and d.bar_pid() == pid, "back to stone, the default family, the same pixels as before", (back.said, pid, d.bar_pid()))
    # the signs are icons: each drawn the text's size, in the middle of its two cells
    signs = [t for t in s.targets() if t.id.endswith(".name")]

    def icons():
        strip, off, left, top = d.strip(), [], (2 * cell - TEXT) // 2, (high - TEXT) // 2
        for t in signs:
            ink = place(strip, t).ink(ground, 40)
            xs, ys = sorted(x for x, _ in ink), sorted(y for _, y in ink)
            if t.w != 2 * cell or not ink or xs[0] < left - 1 or xs[-1] > left + TEXT or ys[0] < top - 1 or ys[-1] > top + TEXT or xs[-1] - xs[0] < cell:
                off.append((t.id, t.w, (xs[0], xs[-1], ys[0], ys[-1]) if ink else None))
        return not off, off
    good, saw = seen(icons)
    ok(good and len(signs) >= 7 and all(m["icon"] in ICONS for m in d.line()[1:] if m["name"] + ".name" in s.ids()),
       "the signs are icons, the bar's own drawings: each of the %d is drawn in a square of the text's %d px in the middle of its two cells, wider than a cell, and the line names a drawing the bar has for each" % (len(signs), TEXT), saw)
    # the plate
    first = {}

    def plate(t, into):
        def read():
            strip = d.strip()
            box, lies, cols = plate_reads(d, strip, t)
            into.update(box=box, cols=cols, data=strip.part(t.x, 0, t.w, high).data)
            return box == (t.x, d.high // 9, 3 * cell, high - 2 * (high // 9)) and lies and label_stands(cols, cell), (box, lies, cols[:1], cols[-1:])
        return seen(read)
    good, saw = plate(one, first)
    ok(good and one.name == "workspace 1" and one.flags == {"selected", "visible"},
       "the plate: the workspace this screen shows is a box of the accent over its place, three cells by the bar less a ninth at each end, its label of two characters in the ground's color, in the middle two cells", saw)
    d.sway("workspace", "number", "10")
    s10 = d.until(lambda s: "visible" in s.find("workspace:10").flags, "workspace 10 shown")
    ten, tenth = s10.find("workspace:10"), {}
    good, saw = plate(ten, tenth)
    ok(good and ten.name == "workspace 10" and tenth.get("data") != first.get("data") and [t.rect for t in s10.spaces()] == [t.rect for t in spaces]
       and "empty" not in s10.find("workspace:1").flags,
       "the plate on workspace 10: the same box over the run's last place, two digits again and other ones; no place has moved", (saw, s10.brief()))
    d.shot("identity-plate-10")
    d.sway("workspace", "number", "1")
    d.until(lambda s: "visible" in s.find("workspace:1").flags and "empty" in s.find("workspace:10").flags, "workspace 1 shown again, and no workspace 10")


def behavior(d):
    enter("behavior", "the pointer and the keys, through the real status loop and the stand-in sound tool")
    s = d.rest()
    pid, cell, ground = d.bar_pid(), d.cell, d.ground
    sign, gauge, mic = s.find("out.name"), s.find("out.gauge"), s.find("mic.name")
    base = s.rects()
    want = {"mark": "mark", "workspace:1": "workspace", "workspace:7": "workspace", "lan.name": "open", "bt.name": "open", "wifi.name": "open", "out.name": "toggle", "out.gauge": "level",
            "out.pct": "open", "mic.name": "open", "kb.name": "toggle", "kb.text": "toggle", "bat.text": "open", "clock.text": "open", "notifications.name": "open"}
    kinds = {t.id: t.kind for t in s.targets()}
    ok(all(kinds.get(k) == v for k, v in want.items()),
       "the state file: out's sign is a toggle, its gauge a level, its number an opener; the keyboard's sign and layout toggles; a place a workspace; every other part an opener",
       {k: kinds.get(k) for k, v in want.items() if kinds.get(k) != v})
    strip = d.strip()
    full, light = pair_of(d, strip, s)
    # the pointer: the sign mutes
    d.click(sign.mid)
    quiet = d.until(lambda s: s.find("out.name").state == "muted" and s.named("out.name") == "output muted", "out muted by a click on its sign")
    ok(d.muted("out") and d.log()[-1:] == ["set-mute @DEFAULT_AUDIO_SINK@ toggle"] and not d.opened() and quiet.levels.get("out") == 40,
       "pointer: a click on out's sign mutes: the sound tool's switch is thrown, the level stays, and nothing is opened", (d.muted("out"), d.log()[-2:], d.opened(), quiet.brief()))
    d.click(sign.mid)
    d.until(lambda s: s.find("out.name").state == "ok" and s.named("out.name") == "output 40%", "out unmuted by a second click")
    ok(not d.muted("out"), "pointer: a second click unmutes")
    # the gauge sets the level where the click was
    into = gauge.w * 8 // 10
    want = level_at(into, gauge.w)
    n = len(d.log())
    d.click(gauge.x + into)
    d.away()
    d.told(lambda s: s.named("out.name") == "output %d%%" % want and s.levels.get("out") == want, "the click on the gauge to set %d" % want)
    good, saw = seen(lambda: (lambda g: (g == gauge_of(want), g))(gauge_reads(d.strip(), gauge, full, light)))
    ok(good and d.level("out") == want == 80 and d.log()[n:] == ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ %d%%" % want],
       "pointer: a click %d px into the gauge's %d sets the level where the click was, to 5: the sound tool was told %d%%, and on the screen the gauge has four full cells" % (into, gauge.w, want),
       (saw, d.level("out"), d.log()[n:]))
    d.shot("behavior-gauge")
    # the wheel, on each of out's parts: a notch at a time, each one answered before the next
    n, level, went = len(d.log()), want, []
    for ident, notch in (("out.name", -1), ("out.gauge", -1), ("out.pct", -1), ("out.gauge", 1)):
        d.over(s.find(ident))
        d.wheel(notch)
        level -= 5 * notch
        try:
            d.told(lambda s, level=level: s.named("out.name") == "output %d%%" % level and s.levels.get("out") == level, "the wheel on %s to make it %d" % (ident, level))
        except AssertionError as late:   # what the sound tool heard says whether the notch was lost before the shell or after it
            raise AssertionError("%s; the sound tool heard %s and is at %s" % (late, d.log()[n:], d.level("out"))) from None
        went.append(d.level("out"))
    ok(went == [want + 5, want + 10, want + 15, want + 10] and d.log()[n:] == ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%" + way for way in "+++-"],
       "pointer: the wheel on the sign, on the gauge and on the number takes 5 a notch, up and down: the sound tool was told each notch in turn, and is where the bar is, at %d" % level,
       (went, d.log()[n:]))
    # a change that fails comes back: the sound tool refuses it, and the next line says a level the hand did not set
    d.flag("fail", True)
    d.wheel(-1)
    d.away()
    wrong = d.told(lambda s: s.find("out.name").state == "wrong" and s.levels.get("out") == level and not s.hovered(), "out to say wrong, its level back at %d" % level)
    seen_red = seen(lambda: (lambda t: (t == ["alert"], t))(place(d.strip(), sign).tone(ground, d.tones)))
    ok(wrong.named("out.name") == "output could not be changed" and d.level("out") == level
       and d.log()[-1:] == ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"] and not stays(base, wrong.rects()) and seen_red[0] and all(t.state == "ok" for t in wrong.targets() if t.module != "out"),
       "a change that fails: the sound tool refused the notch, and the line is the truth: the level is back at %d, out says wrong, could not be changed, its sign red on the screen, in the same cells; nothing else is touched" % level,
       (wrong.brief(), d.level("out"), d.log()[-1:], stays(base, wrong.rects()), seen_red))
    d.shot("behavior-failed")
    d.flag("fail", False)
    d.over(gauge)
    d.wheel(-1)
    level += 5
    d.told(lambda s: s.find("out.name").state == "ok" and s.named("out.name") == "output %d%%" % level and s.levels.get("out") == level, "the next change, one that works, to clear it")
    ok(d.level("out") == level, "the next change that works clears it: out is at %d, and says so" % level, d.level("out"))
    # motion is the look's to say: the config's BAR_MOTION=no travels in the next line, to the same process
    d.configure("BAR_MOTION=no\nBAR_HIDE=lan\n")   # the wire off the bar too: the line that hides it is the config's new one, and moves nothing else
    d.told(lambda s: not s.find("lan.name"), "the line of the config with no motion")
    look = d.line()[0]
    d.over(gauge)
    d.wheel(1)
    level -= 5
    d.told(lambda s: s.named("out.name") == "output %d%%" % level and s.levels.get("out") == level, "a notch with no motion")
    ok(look.get("motion") == "no" and d.level("out") == level and d.bar_pid() == pid,
       "with BAR_MOTION=no in the config the next line's look says motion no, to the same process, and a notch still sets the level", (look, d.level("out"), pid, d.bar_pid()))
    d.configure()
    d.told(lambda s: s.find("lan.name"), "the line of the config as it was")
    d.says(40)
    # the microphone, not pinned: its sign takes the wheel
    n = len(d.log())
    d.over(mic)
    d.wheel(-1)
    shown = d.told(lambda s: s.named("mic.name") == "microphone 55%" and s.levels.get("mic") == 55, "the wheel on the mic's sign to make it 55")
    ok(d.level("mic") == 55 and d.level("out") == 40 and d.log()[n:] == ["set-volume -l 1.0 @DEFAULT_AUDIO_SOURCE@ 5%+"] and not shown.find("mic.gauge"),
       "pointer: the wheel on the mic's sign, which has no gauge on the bar, sets the mic's level, 55, and out's stays", (d.level("mic"), d.level("out"), d.log()[n:]))
    d.says(40)
    # a place shows its workspace, an empty one too
    d.click(s.find("workspace:2").mid)
    two = d.until(lambda s: "selected" in s.find("workspace:2").flags, "workspace 2 shown by a click on its place")
    ok(d.focused_space() == 2 and two.find("workspace:1").flags <= {"hover"} and {"selected", "visible"} <= two.find("workspace:2").flags
       and [t.rect for t in two.spaces()] == [t.rect for t in s.spaces()],
       "pointer: a click on a place shows its workspace: sway has the focus on 2, the plate is there, and no place has moved", (d.focused_space(), two.brief()))
    d.click(two.find("workspace:5").mid)
    five = d.until(lambda s: "selected" in s.find("workspace:5").flags, "workspace 5 shown by a click on its empty place")
    ok(d.focused_space() == 5 and "empty" in two.find("workspace:5").flags and "empty" not in five.find("workspace:5").flags and five.find("workspace:5").name == "workspace 5",
       "pointer: a click on a place with no workspace goes there all the same, as Super+5 does: the plate is on 5", (d.focused_space(), five.brief()))
    d.click(five.find("workspace:1").mid)
    one = d.until(lambda s: "selected" in s.find("workspace:1").flags and "empty" in s.find("workspace:5").flags, "workspace 1 shown again, and 5 gone")
    ok(d.focused_space() == 1 and "empty" not in one.find("workspace:2").flags, "pointer: and a click on the first place brings it back; the place left behind has no workspace again", (d.focused_space(), one.brief()))
    d.away()
    # what opens
    dialog = "--config %s/.config/foot/dialog.ini --app-id spark-dialog -e %s dialog" % (d.home, d.shell_path)
    changes, got = len(d.log()), []
    doors = (("out.pct", "out"), ("mic.name", "mic"), ("lan.name", "lan"), ("bt.name", "bt"), ("wifi.name", "wifi"), ("bat.text", "bat"), ("clock.text", "clock"),
             ("notifications.name", "notifications"), ("mark", ""))
    for ident, section in doors:
        n = len(d.opened())
        d.click(s.find(ident).mid)
        got.append((ident, (settle(lambda: d.opened()[n:], 8) or ["nothing opened"])[-1], dialog + (" " + section if section else "")))
    d.away()
    ok(all(found == wanted for _, found, wanted in got) and len(d.opened()) == len(doors) and len(d.log()) == changes,
       "pointer: out's number opens the dialog's out section, the mic's sign mic, and the wire, bluetooth, wifi, the battery, the time and the notifications each their own; the logo opens home, with no section; no sound is changed",
       [g for g in got if g[1] != g[2]] or (d.opened(), d.log()[changes:]))
    # the keyboard's layout, switched in place. The shell switches a layout only where every keyboard under an identifier has
    # one, for a sway asked to switch a keyboard with no keymap ends; the proof's lasting keyboard has none, and all
    # virtual keyboards share one identifier. So for this click a keyboard with a layout takes its place
    typing = d.lasting("-k", "Shift_L")
    wait_for(lambda: any(n for _, n in d.keyboards()), "a keyboard with a layout on the seat")
    d.keyboard.terminate()
    d.keyboard.wait(timeout=5)
    seat = wait_for(lambda: (lambda k: k and all(n for _, n in k) and k)(d.keyboards()), "no keyboard without a layout on the seat")
    n, asked = len(d.opened()), len(d.asked())
    d.click(s.find("kb.text").mid)
    next_ = settle(lambda: d.asked()[asked:], 8) or []
    named = re.fullmatch(r'-- input "([^"]+)" xkb_switch_layout next', next_[0]) if len(next_) == 1 else None
    ok(named and named.group(1) in [i for i, _ in seat] and "type:" not in next_[0] and len(d.opened()) == n and len(d.log()) == changes,
       "pointer: a click on the keyboard's layout asks sway for the next one, on the keyboard that has layouts, by its identifier, never on every keyboard; nothing is opened", (next_, seat, d.opened()[n:]))
    d.keyboard = d.lasting()
    wait_for(lambda: any(not n for _, n in d.keyboards()), "the proof's own keyboard on the seat again")
    typing.terminate()
    typing.wait(timeout=5)
    d.away()
    # pins and what is hidden: the config's, said by the next line to the same bar
    shown = "workspaces, pad, lan, bt, wifi, out, mic, due, light, kb, bat, clock, notifications"   # what the config does not hide
    left = ("lan.name", "bt.name", "wifi.name", "out.name", "out.gauge", "out.pct", "mic.name")
    said = d.shell("bar", "pin", "mic")
    both = d.until(lambda s: s.find("mic.gauge") and s.find("mic.pct"), "the mic's gauge and number on the bar")
    ok(said.returncode == 0 and said.said.startswith("pinned mic") and d.conf("BAR_PINS") == "out mic" and d.bar_pid() == pid
       and all(both.rects()[k][0] == base[k][0] - 11 * cell for k in left) and not stays(base, both.rects(), left)
       and (both.find("mic.gauge").x, both.find("mic.gauge").w, both.find("mic.pct").x + both.find("mic.pct").w) == (base["mic.name"][0] - 8 * cell, 5 * cell, base["mic.name"][0] + 2 * cell),
       "spark-shell bar pin mic: its gauge and its number come beside its sign, eleven cells; its sign and what stands left of it move that far, and what stands right stays; the same process",
       (said.said, d.conf("BAR_PINS"), pid, d.bar_pid(), both.brief()))
    said = d.shell("bar", "unpin", "out")
    bare = d.until(lambda s: not s.find("out.gauge") and not s.find("out.pct") and s.find("mic.gauge"), "out's gauge and number off the bar")
    ok(said.returncode == 0 and said.said.startswith("unpinned out") and d.conf("BAR_PINS") == "mic" and d.bar_pid() == pid and bare.find("out.name").x == sign.x and bare.levels.get("out") == 40,
       "spark-shell bar unpin out: its gauge and its number go, its sign and its level stay; the device is not touched; the same process", (said.said, d.conf("BAR_PINS"), bare.brief()))
    said = d.shell("bar", "unpin", "mic")
    none = d.until(lambda s: not s.find("mic.gauge") and not s.find("out.gauge"), "no gauge on the bar")
    ok(said.returncode == 0 and "no gauge now" in said.said and d.conf("BAR_PINS") == "none" and not [t for t in none.targets() if t.kind == "level"] and d.bar_pid() == pid,
       "spark-shell bar unpin mic: no level is pinned, the config says none, and the bar has no gauge", (said.said, d.conf("BAR_PINS"), none.brief()))
    said = d.shell("bar", "pin", "out")
    again = d.until(lambda s: s.rects() == base, "out's gauge and number back, every target where it was")
    ok(said.returncode == 0 and said.said.startswith("pinned out") and d.conf("BAR_PINS") == "out" and d.bar_pid() == pid, "spark-shell bar pin out: it is back, and every target is where it first was", (said.said, again.brief()))
    said = d.shell("bar", "hide", "bat")
    gone = d.until(lambda s: not s.find("bat.text"), "the battery off the bar")
    ok(said.returncode == 0 and said.said.startswith("hidden bat") and shown.replace(" bat,", "") in said.said and d.conf("BAR_HIDE") == "bat" and d.bar_pid() == pid
       and gone.find("kb.text").x - base["kb.text"][0] == 10 * cell and not stays(base, gone.rects(), [k for k in base if base[k][0] < base["bat.text"][0]]),
       "spark-shell bar hide bat: the battery is off the bar and what stood left of it closes up to the time, ten cells; the same process", (said.said, d.conf("BAR_HIDE"), gone.brief()))
    said = d.shell("bar", "show", "bat")
    again = d.until(lambda s: s.rects() == base, "the battery back, every target where it was")
    ok(said.returncode == 0 and said.said.startswith("shown bat") and shown in said.said and d.conf("BAR_HIDE") == "" and d.bar_pid() == pid and len(d.log()) == changes,
       "spark-shell bar show bat: it is back where it was; through the four verbs the bar was never started again (pid %s) and no sound was changed" % pid, (said.said, again.brief(), pid, d.bar_pid()))
    # the keys
    d.keys_on()
    s = d.until(lambda s: s.focused() == "mark", "Super+%s to put the keys on the bar" % d.keys_key)
    good, saw = seen(lambda: line_reads(d, d.strip(), s.find("mark"), s.plate()))
    ok(good, "keys: Super+%s, sway's binding of spark-shell bar keys, picks the logo: a 2 px line in the accent at the plate's foot under it" % d.keys_key, saw)
    d.shot("behavior-keys")
    d.key("Right")
    d.until(lambda s: s.focused() == "workspace:1", "Right to move the keys to the first place")
    d.key("Left")
    d.until(lambda s: s.focused() == "mark", "Left to move them back to the logo")
    ok(True, "keys: Right and Left move along the bar")
    # the keyboards configured again while the bar has the keys, as a layout changed or a keyboard plugged in does: an
    # older sway takes the keyboard off the surface and gives it back, and each key here is a keyboard of its own
    d.sway("input", "type:keyboard", "repeat_delay", "450")
    d.key("Right")
    d.until(lambda s: s.focused() == "workspace:1", "Right to move the keys after the keyboards were configured again")
    d.key("Left")
    d.until(lambda s: s.focused() == "mark", "Left to move them back")
    ok(True, "keys: the keyboards configured again while the bar has them: the bar keeps the keys")
    d.focus("out.name")
    d.key("Return")
    s = d.until(lambda s: s.named("out.name") == "output muted", "Enter on out's sign to mute")
    ok(d.muted("out") and s.focused() == "out.name", "keys: Enter on out's sign mutes, and the keys stay on it: a toggle", (d.muted("out"), s.focused()))
    d.key("space")
    s = d.until(lambda s: s.named("out.name") == "output 40%", "Space to unmute")
    ok(not d.muted("out") and s.focused() == "out.name", "keys: Space unmutes, the keys still there", (d.muted("out"), s.focused()))
    d.key("Tab")
    d.until(lambda s: s.focused() == "out.gauge", "Tab to the gauge")
    n, levels = len(d.log()), []
    for name, level in (("End", 100), ("Home", 0), ("Up", 5), ("Up", 10), ("Down", 5)):
        d.key(name)
        s = d.told(lambda s, level=level: s.named("out.name") == "output %d%%" % level and s.levels.get("out") == level, "%s on the gauge to make it %d%%" % (name, level))
        levels.append(d.level("out"))
    tail = ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ " + v for v in ("100%", "0%", "5%+", "5%+", "5%-")]
    ok(levels == [100, 0, 5, 10, 5] and d.log()[n:] == tail and s.focused() == "out.gauge",
       "keys: on the gauge End sets 100 and Home 0, Up and Down take 5, and the keys stay on it", (levels, d.log()[n:], s.focused()))
    # Left and Right move past the gauge as past any part; Up on the sign is the wheel there too, and nothing where no level is
    n, way = len(d.log()), []
    for name, ident in (("Right", "out.pct"), ("Left", "out.gauge"), ("Left", "out.name")):
        d.key(name)
        way.append(d.until(lambda s, ident=ident: s.focused() == ident, "%s to move the keys to %s" % (name, ident), 5).levels.get("out"))
    moved_none = d.log()[n:]
    d.key("Up")
    s = d.told(lambda s: s.named("out.name") == "output 10%" and s.levels.get("out") == 10, "Up on out's sign to make it 10%")
    on_sign = (d.level("out"), s.focused(), d.log()[n:])
    d.focus("lan.name")
    d.key("Up")
    d.key("Down")
    d.key("Right")
    s = d.until(lambda s: s.focused() == "bt.name", "Right to move the keys on from the wire's sign, after Up and Down there", 5)
    ok(way == [5, 5, 5] and not moved_none and on_sign == (10, "out.name", ["set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"]) and d.log()[n:] == on_sign[2] and d.level("out") == 10,
       "keys: Left and Right move past the gauge as past any part, and set no level; Up on out's sign is the wheel there too, and the keys stay; on the wire's sign, which has no level, Up and Down do nothing",
       (way, moved_none, on_sign, d.log()[n:], s.focused()))
    d.focus("out.gauge")
    d.key("Tab")
    d.until(lambda s: s.focused() == "out.pct", "Tab to the number")
    n = len(d.opened())
    d.key("Return")
    s = d.until(lambda s: not s.focused(), "Enter on the number to give the keyboard back")
    ok((settle(lambda: d.opened()[n:], 8) or [""])[-1] == dialog + " out", "keys: Enter on the number opens the out section and gives the keyboard back: an opener", d.opened()[n:])
    said = d.shell("bar", "keys")
    d.until(lambda s: s.focused() == "mark", "spark-shell bar keys to put the keys on the bar")
    d.focus("kb.text")
    n, asked = len(d.opened()), len(d.asked())
    # what the shell may ask of sway here: a switch for each identifier under which every keyboard has a layout,
    # as sway lists them now. The proof's own keyboard has none on sway 1.12, so nothing; sway 1.9 gives it one
    seat = d.keyboards()
    switch = ['-- input "%s" xkb_switch_layout next' % i for i in sorted({i for i, _ in seat if all(k for j, k in seat if j == i)})]
    d.key("Return")
    d.key("Tab", shift=True)
    kept = d.until(lambda s: s.focused() == "kb.name", "the keys still on the bar after Enter on the keyboard's layout: Shift+Tab moves them to its sign", 5)
    d.focus("mark")
    d.key("Return")
    d.until(lambda s: not s.focused(), "Enter on the logo to give the keyboard back")
    home = settle(lambda: d.opened()[n:], 8) or []
    ok(kept and home == [dialog] and d.asked()[asked:] == switch and not [a for a in d.asked() if "type:" in a],
       "keys: Enter on the keyboard's layout, a toggle, keeps the keys on the bar and opens nothing; the shell asks sway to switch only where every keyboard under an identifier has a layout (%d here), never every keyboard at once" % len(switch),
       (home, d.asked(), seat))
    ok(said.said == "the bar has the keys: the arrows move, Enter acts, Esc leaves" and home[-1:] == [dialog],
       "keys: spark-shell bar keys says so, and Enter on the logo opens home", (said.said, home))
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s again" % d.keys_key)
    d.key("Right", times=2)
    d.until(lambda s: s.focused() == "workspace:2", "Right twice to the second place")
    d.key("Return")
    s = d.until(lambda s: "selected" in s.find("workspace:2").flags and not s.focused(), "Enter on the second place to show its workspace")
    ok(d.focused_space() == 2, "keys: Enter on a place shows its workspace and gives the keyboard back", d.focused_space())
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s once more" % d.keys_key)
    n = len(d.opened())
    d.key("Escape")
    s = d.until(lambda s: not s.focused(), "Escape to give the keyboard back")
    ok(d.focused_space() == 2 and len(d.opened()) == n, "keys: Escape gives the keyboard back and does nothing else", (d.focused_space(), d.opened()[n:]))
    # the pointer gives the keys back too: a button on a window
    d.away()
    x, y = d.space[0] // 4, H // 2
    win = d.node(d.windows[1].pid)["rect"]
    on_window = win["x"] <= x < win["x"] + win["width"] - 8 * cell and win["y"] <= y < win["y"] + win["height"]
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s, the pointer on a window" % d.keys_key)
    n, changes = len(d.opened()), len(d.log())
    d.button(True)
    d.button(False)
    if not settle(lambda: not d.state().focused(), 3):
        # a sway that hands the pointer to a surface only once it moves: one cell, travel that keeps the keys
        note("this sway gave a button pressed with no move before it to the window: the bar is handed the pointer off itself at its first move")
        x += cell
        d.move(x, y)
        d.button(True)
        d.button(False)
    s = d.until(lambda s: not s.focused(), "a button on a window to give the keyboard back", 5)
    ok(on_window and d.focused_space() == 2 and len(d.opened()) == n and len(d.log()) == changes,
       "pointer: while the bar has the keys a button pressed on a window gives the keyboard back, as Escape does, and does nothing else", (on_window, win, d.focused_space(), d.opened()[n:]))
    # and its travel: a cell keeps the keys, more than three cells gives them back
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s again, the pointer on a window" % d.keys_key)
    d.move(x + cell, y)
    d.key("Right")
    kept = d.until(lambda s: s.focused() == "workspace:1", "Right to move the keys, after the pointer moved a cell", 5)
    d.move(x + 7 * cell, y)
    s = d.until(lambda s: not s.focused(), "the pointer's travel to give the keyboard back", 5)
    ok(kept and d.focused_space() == 2, "pointer: the pointer moved a cell off the bar, the keys stay, and Right still moves them; moved %d px more, past three cells, it gives the keyboard back" % (6 * cell), s.brief())
    # a click on the bar itself still reaches the bar, and a toggle keeps the keys
    d.keys_on()
    d.until(lambda s: s.focused() == "mark", "Super+%s once again" % d.keys_key)
    d.click(sign.mid)
    s = d.until(lambda s: s.named("out.name") == "output muted", "a click on out's sign, the bar having the keys")
    ok(d.muted("out") and s.focused() == "mark", "pointer: while the bar has the keys a click on the bar still reaches it: out's sign mutes, and the keys stay where they were", (d.muted("out"), s.focused()))
    d.click(sign.mid)
    d.until(lambda s: s.named("out.name") == "output 10%", "out unmuted")
    d.key("Escape")
    d.until(lambda s: not s.focused(), "Escape to give the keyboard back")
    d.away()


def states(d):
    enter("states", "muted, off, down, recording, asking, no device, the status gone, a crash, a stop, loading, a binding mode")
    s = d.rest()
    base, high, cell, ground, tones = s.rects(), d.high, d.cell, d.ground, d.tones
    frame = collections.OrderedDict((k, v) for k, v in base.items() if k == "mark" or k.startswith("workspace:"))
    run_end = frame["workspace:10"][0] + frame["workspace:10"][2]
    gauge, pct, plate = s.find("out.gauge"), s.find("out.pct"), s.plate()
    box = (plate.x, high // 9, plate.w, high - 2 * (high // 9))
    strip = d.strip()
    full, light = pair_of(d, strip, s)
    calm = {i: place(strip, s.find(i)) for i in ("out.name", "bt.name", "mic.name", "notifications.name")}
    # what is not well, all at once: out muted, the wire down, bluetooth and wifi off, the battery low, the mic
    # recording, two notifications nobody looked at, and a window waiting on a pad that is hidden
    waits = d.terminal("PAD")
    d.sway("[pid=%d] mark --add _spark-shell.min.proof, move scratchpad" % waits.pid)
    d.sound(40, True, 50, False)
    d.machine("class/net/eth0/carrier", "0\n")
    d.machine("class/net/wlan0/operstate", "down\n")
    d.machine("class/power_supply/BAT0/capacity", "9\n")
    d.flag("bt-off", True)
    d.flag("pw-dump", True, RECORDING)
    d.notes(2)
    want = {"pad.name": "off", "pad.text": "off", "lan.name": "wrong", "bt.name": "off", "wifi.name": "off", "out.name": "muted", "out.gauge": "muted", "mic.name": "records",
            "kb.name": "ok", "kb.text": "ok", "bat.name": "wrong", "bat.text": "wrong", "clock.text": "ok", "notifications.name": "ok", "notifications.text": "ok"}
    hard = d.told(lambda s: {t.id: t.state for t in s.parts()} == want, "the bar to say what is not well")
    words = {i: hard.named(i) for i in ("pad.name", "lan.name", "bt.name", "wifi.name", "out.name", "mic.name", "bat.text", "notifications.name")}
    ok(words == {"pad.name": "pad hidden, 1 windows", "lan.name": "lan not connected", "bt.name": "bluetooth off", "wifi.name": "wifi not connected", "out.name": "output muted",
                 "mic.name": "microphone 50%, recording", "bat.text": "battery 9% low", "notifications.name": "notifications, 2 not seen"}
       and dict(hard.levels) == {"out": 40, "mic": 50} and not stays(base, hard.rects()) and hard.find("pad.name").kind == "toggle",
       "the state file: out muted with its level and no number, the wire and the low battery wrong, bluetooth, wifi and the pad off, the mic records, the notifications counted; each says so in words, and no target that was there has moved",
       (words, hard.brief(), stays(base, hard.rects())))
    d.line()   # its signs, the hollow ones too, for the fonts to be asked for
    x0 = 2 * cell + MARK   # past the logo, whose ink is the file's own

    def hard_look():
        strip = d.strip()
        got = {i: place(strip, hard.find(i)).tone(ground, tones) for i in want if i != "out.gauge"}
        cells = [strip.part(gauge.x + i * cell, 0, cell, high) for i in range(5)]
        dims = [c.tone(ground, tones) for c in cells[:2]]
        shape = [alike(c.cover(ground, tones["dim"]), full.cover(ground, tones["text"])) for c in cells[:2]]
        rest_ = [c.data == light.data for c in cells[2:]]
        blank = strip.part(gauge.x + gauge.w + cell, 0, 4 * cell, high).colors() == {ground}
        solid = [i for i in ("out.name", "bt.name", "mic.name") if place(strip, hard.find(i)).data == calm[i].data]
        only, stray = census(strip.part(x0, 0, strip.w - x0, high), ground, tones)
        red = inside(only["alert"], [(hard.find(i).x - cell // 2 - x0, 0, hard.find(i).w + cell, high) for i in ("lan.name", "mic.name", "bat.name")])
        blue = inside(only["accent"], [(box[0] - x0, box[1], box[2], box[3])])
        saw = {"tones": got, "gauge": (dims, shape, rest_), "number": blank, "not hollow": solid, "red": red[:4], "accent": blue[:4], "attention": only["attention"][:4], "stray": stray[:4]}
        tones_ok = got == dict({i: ["text"] for i in got}, **{"pad.name": ["dim"], "pad.text": ["dim"], "bt.name": ["dim"], "wifi.name": ["dim"], "out.name": ["dim"],
                                                               "lan.name": ["alert"], "mic.name": ["alert"], "bat.name": ["alert"]})
        return tones_ok and dims == [["dim"]] * 2 and all(shape) and all(rest_) and blank and not solid and not red and not blue and not only["attention"] and not stray, saw
    _, saw = seen(hard_look)
    ok(saw["tones"]["out.name"] == ["dim"] and "out.name" not in saw["not hollow"] and saw["gauge"] == ([["dim"]] * 2, [True] * 2, [True] * 3) and saw["number"],
       "muted, on the screen: the icon is the hollow one, dim as its gauge is; the gauge keeps its level with every cell dim, two the full glyph's shape and three the light one, and the number's cells are empty", saw)
    ok(all(saw["tones"][i] == ["dim"] for i in ("bt.name", "wifi.name", "pad.name", "pad.text")) and "bt.name" not in saw["not hollow"],
       "off, on the screen: bluetooth's icon, another than with a device, wifi's, and the hidden pad's and its count are dim", saw)
    ok(all(saw["tones"][i] == ["alert"] for i in ("lan.name", "mic.name", "bat.name")) and "mic.name" not in saw["not hollow"] and not saw["red"] and not saw["attention"] and not saw["accent"]
       and not saw["stray"] and all(saw["tones"][i] == ["text"] for i in ("kb.name", "kb.text", "bat.text", "clock.text", "notifications.name", "notifications.text")),
       "wrong and recording, on the screen: the wire's icon, the mic's and the low battery's are red, and the battery's number stays the text's color beside it; red is nowhere else on the bar; no attention color; the accent on the plate alone; the count and the rest in the text's color",
       saw)
    d.shot("states-not-well")
    waits.terminate()
    # what asks: a reminder that is due, and a window that wants attention; and bluetooth on with nothing connected, and
    # the notifications held back
    d.rest()
    d.remind(True)
    d.flag("bt-alone", True)
    d.flag("dnd", True)
    d.sway("[pid=%d]" % d.windows[1].pid, "urgent", "enable")
    asks = d.told(lambda s: s.find("due.name").state == "asks" and "urgent" in s.find("workspace:2").flags and s.find("bt.name").state == "missing" and s.named("notifications.name") == "do not disturb",
                  "a reminder due, workspace 2 asking, bluetooth alone, do not disturb")
    due, two, alone, quiet = asks.find("due.name"), asks.find("workspace:2"), asks.find("bt.name"), asks.find("notifications.name")
    d.line()

    def asking():
        strip = d.strip()
        got = place(strip, due).tone(ground, tones), place(strip, two).tone(ground, tones), place(strip, alone).tone(ground, tones), place(strip, quiet).tone(ground, tones)
        shape = (alike(first_cell(d, strip, two).cover(ground, tones["attention"]), full.cover(ground, tones["text"])),
                 place(strip, alone).data != calm["bt.name"].data,
                 place(strip, quiet).data != calm["notifications.name"].data)
        only, stray = census(strip.part(x0, 0, strip.w - x0, high), ground, tones)
        there = inside(only["attention"], [(due.x - cell // 2 - x0, 0, due.w + cell, high), (two.x - x0, 0, two.w, high)])   # a face with no such sign draws its number, wider than a cell
        return got == (["attention"], ["attention"], ["dim"], ["text"]) and all(shape) and not there and not only["alert"] and not stray, (got, shape, there[:4], only["alert"][:4], stray[:4])
    _, saw = seen(asking)
    ok(saw[0][:2] == (["attention"], ["attention"]) and saw[1][0] and not saw[2] and not saw[3] and not saw[4] and due.name.startswith("reminder due: the proof") and due.kind == "open"
       and asks.named("workspace:2") == "workspace 2",
       "what asks: a reminder due is its sign alone in the attention color, and a workspace with a window that asks is its three cells of the full glyph in that color; the attention color is nowhere else, and no red", (saw, asks.brief()))
    ok(alone.name == "bluetooth on" and saw[0][2] == ["dim"] and saw[1][1],
       "bluetooth on with nothing connected says missing: its icon is not the one with a device, and dim", (saw, asks.brief()))
    ok(quiet.state == "ok" and quiet.rect == (base["notifications.name"][0], 0, 2 * cell, high) and saw[0][3] == ["text"] and saw[1][2],
       "do not disturb: the notifications' icon is another one, in the text's color, in the flag's cells", (saw, asks.brief()))
    ok(due.x == asks.find("mic.name").x + 2 * cell + 5 * cell and asks.find("kb.name").x == due.x + 2 * cell + 5 * cell and asks.find("mic.name").x == base["mic.name"][0] - 7 * cell
       and not stays(base, asks.rects(), [k for k in base if "." in k and base[k][0] <= base["mic.name"][0]]),
       "the reminder is a group of its own, five cells from the sound and five from the seat: what stands left of it made room, seven cells, and what stands right stays", asks.brief())
    d.shot("states-asking")
    d.sway("[pid=%d]" % d.windows[1].pid, "urgent", "disable")
    # no sound device
    d.rest()
    d.flag("down", True)
    lost = d.told(lambda s: s.find("out.name").state == "missing" and s.find("mic.name").state == "missing", "out and the mic to say missing")
    d.line()
    ok(lost.status == "ok" and not lost.find("out.gauge") and not lost.find("out.pct") and not stays(base, lost.rects())
       and lost.named("out.name") == "output not available: no audio system found" and lost.named("mic.name") == "microphone not available: no audio system found"
       and lost.find("out.name").kind == "toggle" and all(t.state == "ok" for t in lost.targets() if t.module not in ("out", "mic")),
       "no sound device: out and the mic say missing and why; out's gauge and number are no targets, and every other target is where it was and as it was", (stays(base, lost.rects()), lost.brief()))

    def hollow():
        strip = d.strip()
        got = [place(strip, lost.find(i)).tone(ground, tones) for i in ("out.name", "mic.name")]
        blank = strip.part(gauge.x, 0, pct.x + pct.w - gauge.x, high).colors() == {ground}
        same = [i for i in ("out.name", "mic.name") if place(strip, lost.find(i)).data == calm[i].data]
        return got == [["dim"], ["dim"]] and blank and not same, (got, blank, same)
    good, saw = seen(hollow)
    ok(good, "on the screen the two icons are the hollow ones, dim, and the cells of out's gauge and number are empty", saw)
    d.shot("states-missing")
    d.flag("down", False)
    d.told(lambda s: s.rects() == base and all(t.state == "ok" for t in s.targets()), "out and the mic back")
    # the status child ends, its background jobs (the clicks' reader, the workspaces' watcher) still holding its pipe
    bar, loop = d.bar_pid(), d.loop_pid()
    crew = members(group_of(loop))
    ok(group_of(loop) == loop and group_of(bar) != loop and len(crew) >= 3 and loop in crew,
       "the status runs in a process group of its own: the loop and its background jobs, %d processes" % len(crew), (loop, group_of(loop), group_of(bar), crew))
    os.kill(loop, signal.SIGKILL)
    s = d.until(lambda s: s.status == "error", "the status marked broken", 6)

    def notice(tone="dim"):
        def read():
            strip = d.strip()
            at = strip.part(W - 4 * cell, 0, 2 * cell, high).tone(ground, tones)
            rest_ = strip.part(run_end, 0, W - 4 * cell - run_end, high).colors() == {ground}
            return at == [tone] and rest_ and strip.part(W - 2 * cell, 0, 2 * cell, high).colors() == {ground}, (at, rest_)
        return seen(read)
    good, saw = notice()
    ok(s.rects() == frame and d.bar_pid() == bar and good,
       "the status shell killed while its jobs hold the pipe: the bar hears its end, the state file says error, the frame stays, the logo and the ten places where they were, and a dim sign stands where the status ended, two cells from the edge",
       (s.brief(), d.bar_pid(), bar, saw))
    d.shot("states-status-ended")
    s = d.until(lambda s: s.status == "ok" and s.find("clock.text"), "the status started again", 15)
    ok(d.loop_pid() not in (None, loop) and d.bar_pid() == bar and s.rects() == base and not [p for p in crew if alive(p)],
       "it is started again: another spark-shell bar status, the same bar, every cell where it was; of the old one no process is left",
       (loop, d.loop_pid(), bar, d.bar_pid(), moved(base, s.rects()), [(p, " ".join(cmdline(p))[:60]) for p in crew if alive(p)]))
    # the bar itself ends: ABRT, a crash
    old = wait_for(d.loop_pid, "the status loop's pid")
    crew = members(group_of(old))
    d.state_file.unlink()
    os.kill(bar, signal.SIGABRT)
    now = settle(lambda: d.bar_pid() not in (None, bar) and d.bar_pid(), 12)
    s = d.until(lambda s: s.status == "ok" and s.find("clock.text"), "the bar started again by its keeper", 15)
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
    d.move(W // 4, H // 2)
    d.flag("slow", True)
    started = d.shell("bar", "start")
    s = d.until(lambda s: s.status == "loading" and s.find("mark") and s.find("workspace:10"), "the bar up before its first line", 10)
    good, saw = notice()
    ok(started.returncode == 0 and s.rects() == frame and not s.levels and good,
       "loading: spark-shell bar start, and before the first line the frame is there, the logo and the ten places where they stay, and three dim dots where the status will end; nothing else", (started.said, s.brief(), saw))
    d.shot("states-loading")
    d.flag("slow", False)
    s = d.until(lambda s: s.status == "ok" and s.find("clock.text"), "the first line", 40)
    ok(s.rects() == base, "the first line fills the cells kept for it", moved(base, s.rects()))
    # a binding mode other than default: the template's resize, on Super+r
    s = d.rest()
    after = run_end
    d.chord("logo", "r")
    s = d.until(lambda s: s.mode == "resize", "the binding mode in the state file")

    def mode(there):
        def read():
            strip = d.strip()
            name = strip.part(after + cell, 0, 6 * cell, high)
            cols = sorted({x // cell for x, _ in name.ink(ground, 40)})
            room = strip.part(after, 0, cell, high).colors() == {ground} and strip.part(after + 7 * cell, 0, base["lan.name"][0] - 5 * cell - after - 7 * cell, high).colors() == {ground}
            return (name.tone(ground, tones) == ["attention"] and cols == list(range(6)) and room) if there else (name.colors() == {ground} and room), (name.tone(ground, tones), cols, room)
        return seen(read)
    good, saw = mode(True)
    ok(good and s.rects() == base and not any(t.module == "mode" for t in s.targets()),
       "a binding mode (Super+r, the template's resize): the state file says mode resize and its name stands one cell after the workspaces, a glyph a cell, in the attention color, as plain text; it is no target, and every target is where it was",
       (s.brief(), saw))
    d.shot("states-mode")
    d.key("Escape")
    s = d.until(lambda s: not s.mode, "the default mode again")
    good, saw = mode(False)
    ok(good and s.rects() == base, "back in the default mode the name is gone", (s.brief(), saw))
    # a screen at rest: the workspace it shows has the rest name, as the idle screen's has; a name that only begins
    # with it is a workspace as any other
    pid, inset, near_ = d.bar_pid(), high // 9, RESTS + "r"
    area = lambda key: next(((w["rect"]["x"], w["rect"]["y"], w["rect"]["width"], w["rect"]["height"]) for w in d.ask("get_workspaces") if key in (w["name"], w["num"])), None)   # noqa: E731  a workspace's rectangle, by its name or its number
    drawn_at = lambda t: seen(lambda: (lambda b: (b == (t.x, inset, t.w, high - 2 * inset), b))(plate_reads(d, d.strip(), t)[0]))   # noqa: E731  the plate, on the screen
    d.sway("workspace", near_)
    on_it = d.until(lambda s: not s.resting and "visible" in s.find("workspace:" + near_).flags, "the workspace named %s shown, the bar there" % near_)
    good, saw = drawn_at(on_it.find("workspace:" + near_))
    under = settle(lambda: area(near_) == (0, high, W, H - high), 5)
    ok(good and under and not stays(base, on_it.rects()) and d.bar_pid() == pid,
       "a workspace named %s is not the rest one: the bar stays, its plate on that workspace's place, and the windows' area begins under it" % near_, (saw, area(near_), on_it.brief()))
    d.shell("bar", "keys")
    d.until(lambda s: s.focused() == "mark", "the keys on the bar")
    d.sway("workspace", RESTS)
    gone = d.until(lambda s: s.resting == [OUT] and not s.outputs, "the screen at rest in the state file")
    whole = settle(lambda: area(RESTS) == (0, 0, W, H), 5)
    good, saw = no_bar(d)
    ok(whole and good and gone.status == "ok" and d.bar_pid() == pid,
       "a screen at rest (the workspace named %s, the bar's BAR_REST): the state file names the screen at rest and no bar on it, the workspace's rectangle is the whole screen, no room kept, and nothing is drawn where the bar was; the same process" % RESTS,
       (area(RESTS), saw, gone.brief(), pid, d.bar_pid()))
    d.shot("states-rest")
    d.sway("workspace", "number", "1")
    back = d.until(d.at_rest, "the bar back on workspace 1 as it was, no key on it")
    good, saw = drawn_at(back.plate())
    under = settle(lambda: area(1) == (0, high, W, H - high), 5)
    ok(back.rects() == base and good and under and d.bar_pid() == pid,
       "workspace 1 shown again: the bar is back as it was, every target in its rectangle, the plate drawn in its place, the windows' area under it; the keys it had went back when it left, and no target has them",
       (moved(base, back.rects()), saw, area(1), back.brief()))
    # a bar started while its screen rests, as its keeper starts one: none there either, until another workspace is shown
    d.sway("workspace", RESTS)
    d.until(lambda s: s.resting == [OUT] and not s.outputs, "the screen at rest again")
    d.end_bar()
    started = d.shell("bar", "start")
    again = d.until(lambda s: s.status == "ok" and s.resting == [OUT] and not s.outputs, "a bar started on the screen at rest, its first line read", 30)
    good, saw = no_bar(d)
    now = d.bar_pid()
    ok(started.returncode == 0 and now not in (None, pid) and good and area(RESTS) == (0, 0, W, H),
       "a bar started while its screen rests draws none there: another process, its status read, and the state file names the screen at rest, no room is kept, nothing is drawn",
       (started.said, pid, now, saw, area(RESTS), again.brief()))
    d.sway("workspace", "number", "1")
    back = d.until(d.at_rest, "the new bar on workspace 1")
    good, saw = drawn_at(back.plate())
    ok(back.rects() == base and good and d.bar_pid() == now, "and its bar comes with workspace 1: every target in its rectangle, the plate drawn; the same process", (moved(base, back.rects()), saw, now, d.bar_pid()))


def tones_at_rest(d, s):
    """The bar at rest, as the screen has it: every pixel past the logo lies between the ground and the text's
    color or the dim one, or, in the plate's box, the accent; and the text itself reads as the palette has it."""
    cell, high, ground, tones = d.cell, d.high, d.ground, d.tones
    plate, x0 = s.plate(), 2 * cell + MARK
    box = (plate.x - x0, high // 9, plate.w, high - 2 * (high // 9))

    def read():
        strip = d.strip()
        only, stray = census(strip.part(x0, 0, strip.w - x0, high), ground, tones)
        accent = inside(only["accent"], [box])
        clock = place(strip, s.find("clock.text")).reach(ground, tones["text"])
        dim = place(strip, s.find("workspace:3")).reach(ground, tones["dim"])
        saw = {"accent off the plate": accent[:4], "red": only["alert"][:4], "attention": only["attention"][:4], "of no tone": stray[:4],
               "text": len(only["text"]), "dim": len(only["dim"]), "accent": len(only["accent"]), "the time": clock, "an empty place": dim}
        return (not accent and not only["alert"] and not only["attention"] and not stray and only["text"] and only["dim"] and only["accent"]
                and clock[0] and clock[1] >= 0.97 and dim[0] and dim[1] >= 0.5), saw
    good, saw = seen(read)
    ok(good, "the %s palette on the screen, the bar at rest: every pixel past the logo is the text's color, the dim one or, on the plate alone, the accent, each thinned by the ground; no red, no attention color, no other color"
       % d.pal["name"], saw)
    ratio = contrast(tones["text"], ground)
    ok(saw["the time"][0] and saw["the time"][1] >= 0.97 and ratio >= 4.5, "on the screen the time's strongest ink is the text's color itself, #%02x%02x%02x on #%02x%02x%02x: %.1f to 1" % (tones["text"] + ground + (ratio,)), saw)


def contrasts(d):
    """The proof's palette in use: the text on the ground and on a chip, the label on the plate, the tones that
    are signs and lines, and a dim part on a chip, raised."""
    pal, ground, tones = d.pal, d.ground, d.tones
    lit = rgb(d.line()[0].get("lit", "000000"))
    text = collections.OrderedDict((("the text on the ground", (tones["text"], ground)), ("the text on a chip, the lit tone", (tones["text"], lit)),
                                    ("the plate's label, the ground's color on the accent", (ground, tones["accent"]))))
    marks = collections.OrderedDict((("the dim tone", (tones["dim"], ground)), ("the accent's line", (tones["accent"], ground)),
                                     ("the red", (tones["alert"], ground)), ("the attention color", (tones["attention"], ground))))
    ratios = collections.OrderedDict((k, round(contrast(*v), 2)) for k, v in list(text.items()) + list(marks.items()))
    ok(all(ratios[k] >= 4.5 for k in text) and all(ratios[k] >= 3 for k in marks),
       "the %s palette is the proof's own, never a theme of the machine's: its text reads at 4.5 to 1 or more on the ground, on a chip and on the plate (%s), and its signs' and lines' tones at 3 or more on the ground (%s)"
       % (pal["name"], ", ".join("%.1f" % ratios[k] for k in text), ", ".join("%.1f" % ratios[k] for k in marks)), ratios)
    at_rest, on_chip = contrast(tones["dim"], ground), contrast(raised(d), lit)
    ok(on_chip >= at_rest, "a dim part on a chip is raised halfway to the text's color: it reads at %.1f to 1 on the lit tone, no worse than the dim tone on the ground, %.1f" % (on_chip, at_rest),
       (on_chip, at_rest, lit))


def accessibility(d):
    enter("accessibility", "the tones, contrast, the pointer's chip, the keys' line and order, names, no motion")
    s = d.rest()
    cell, high, ground, tones = d.cell, d.high, d.ground, d.tones
    inset, half, plate, mark = high // 9, cell // 2, s.plate(), s.find("mark")
    contrasts(d)
    tones_at_rest(d, s)
    rest_strip = d.strip()
    plate_run = (plate.x, plate.w, tones["accent"])
    ok(rest_strip.runs(inset, ground) == [plate_run] and rest_strip.runs(high - inset - 1, ground) == [plate_run],
       "at rest nothing is lit: on the first and the last row of the plate's box the plate alone stands", (rest_strip.runs(inset, ground), rest_strip.runs(high - inset - 1, ground)))
    # under the pointer
    lit = rgb(d.line()[0].get("lit", "000000"))
    signs = [t for t in s.targets() if t.id.endswith(".name")]
    others = [s.find(i) for i in ("out.gauge", "out.pct", "kb.text", "bat.text", "clock.text", "workspace:2", "workspace:3")]
    sizes, off = {}, []
    for t in signs + others:
        own = raised(d) if "empty" in t.flags else tones["text"]   # at rest every part is well; a place with no workspace is dim
        pad = 0 if t.kind == "workspace" else half
        d.over(t)

        def chip(t=t, own=own, pad=pad):
            strip = d.strip()
            box, inked = chip_reads(d, strip, t, lit, own)
            alone = sorted(strip.runs(inset, ground)) == sorted([plate_run, (t.x - pad, t.w + 2 * pad, lit)])
            if t.id == "out.gauge":   # its cells keep their tones on the chip: the full ones the text's, the light ones dim
                full_, dim = strip.part(t.x, inset, 2 * cell, high - 2 * inset).reach(lit, tones["text"]), strip.part(t.x + 2 * cell, inset, 3 * cell, high - 2 * inset).reach(lit, tones["dim"])
                inked = full_[0] and full_[1] >= 0.5 and dim[0] and dim[1] >= 0.5
            return box == (t.x - pad, inset, t.w + 2 * pad, high - 2 * inset) and inked and alone, (box, inked, alone)
        good, saw = seen(chip)
        sizes[t.id] = saw[0][2:]
        if not good:
            off.append((t.id, saw))
    ok(not [o for o in off if o[0].endswith(".name")] and {sizes[t.id] for t in signs} == {(3 * cell, high - 2 * inset)} and len(signs) >= 7,
       "under the pointer every sign stands on a chip of the same size, %d by %d: its icon's two cells and half a cell at each side, the plate's height, filled with the look's lit tone, the icon on it still in its own color"
       % (3 * cell, high - 2 * inset), (off, {t.id: sizes[t.id] for t in signs}))
    ok(not [o for o in off if not o[0].endswith(".name")] and sizes["out.gauge"] == (6 * cell, high - 2 * inset) and sizes["out.pct"] == (4 * cell, high - 2 * inset) and sizes["clock.text"] == (6 * cell, high - 2 * inset)
       and sizes["workspace:2"] == sizes["workspace:3"] == (3 * cell, high - 2 * inset),
       "a gauge, a number and a text too, each as wide as it is drawn and half a cell at each side, in its own color, a gauge's light cells still dim; a place's chip is its own three cells and no wider, an empty place's glyphs raised halfway to the text's color; and each part lights alone: with the pointer on one, only its chip and the plate stand on the box's first row",
       (off, sizes))
    d.shot("accessibility-chip")
    d.over(plate)
    left = s.parts()[0].x   # the logo and the run: the status has the time, which changes by itself
    good, saw = seen(lambda: (lambda strip: (strip.part(0, 0, left, high).data == rest_strip.part(0, 0, left, high).data and strip.runs(inset, ground) == [plate_run], strip.runs(inset, ground)))(d.strip()))
    ok(good, "the plate does not change under the pointer: the logo and the run are the pixels they are at rest, and nothing is lit", saw)
    d.over(mark)
    good, saw = seen(lambda: (lambda strip: (strip.box(mark.x - 1, inset, lit) == (mark.x - half, inset, mark.w + 2 * half, high - 2 * inset), strip.box(mark.x - 1, inset, lit)))(d.strip()))
    ok(good, "the logo, a picture, stands on a chip of the lit tone too, its square and half a cell at each side", saw)
    d.away()
    # the keys' order, and their line
    d.shell("bar", "keys")
    s = d.until(lambda s: s.focused() == "mark", "the keys on the bar")
    order, visual, went, lines = s.ids(), [t.id for t in sorted(s.targets(), key=lambda t: t.x)], [], {}
    for _ in order:
        was = s.focused()
        d.key("Tab")
        s = d.until(lambda s: s.focused() not in (None, was), "Tab to move the keys on from %s" % was, 5)
        went.append(s.focused())
        if s.focused() in ("workspace:1", "workspace:2", "out.name", "out.gauge", "clock.text", "mark"):
            lines[s.focused()] = seen(lambda t=s.find(s.focused()): line_reads(d, d.strip(), t, plate), 3)
        if s.focused() == "out.gauge":
            d.shot("accessibility-keys")
    ok(order == visual and went == visual[1:] + visual[:1] and len(set(went)) == len(visual),
       "the keys: Tab goes through all %d targets, each once, left to right as they stand, and comes round to the logo" % len(visual), (went, visual))
    ok(len(lines) == 6 and all(good for good, _ in lines.values()),
       "the keys' line: under the part that has the keys, 2 px of the accent in the last rows of the plate's box, the part's width and half a cell at each side, a place's own three cells; on the plate, 2 px of the ground's color across it, 2 px above its foot; read under the logo, a place, a sign, a gauge and the time, and on the plate",
       {k: v for k, v in lines.items() if not v[0]} or lines)
    only, _ = census(d.strip(), ground, tones)
    thick = max((cell + 2) // 5, 1)
    foot = inside(only["accent"], [(plate.x, inset, plate.w, high - 2 * inset), (mark.x - half, high - inset - thick, mark.w + 2 * half, thick)])
    ok(not foot, "with the keys on the bar the accent is the plate and the keys' line, and nowhere else", foot[:6])
    d.key("Tab", shift=True)
    s = d.until(lambda s: s.focused() == visual[-1], "Shift+Tab to go back, from the logo round to the last target", 5)
    d.key("Escape")
    d.until(lambda s: not s.focused(), "Escape to give the keyboard back")
    ok(True, "the keys: Shift+Tab goes back, round to the last one")
    # no motion
    d.away()

    def still():
        if time.localtime().tm_sec > 55:   # the clock's own change of minute is not motion
            time.sleep(61 - time.localtime().tm_sec)
        one = d.strip().data
        time.sleep(1)
        return one == d.strip().data, None
    good, _ = seen(still, 8)
    ok(good, "no motion at rest: two captures of the bar a second apart, with nothing touched, are the same pixels")


def names(d):
    """Every control in every state the proof saw: a name, an id, a kind and a state of the bar's own; a sign its icon's two cells."""
    global gate
    gate = "accessibility"
    lines, bad, wide, signs = 0, [], [], 0
    for text in d.seen:
        s = State(text)
        bad += s.odd[:1]
        for strip in s.outputs.values():
            for t in strip.targets:
                lines += 1
                if not (t.name.strip() and t.id and t.kind in KINDS and t.state in STATES and t.flags <= FLAGS and (t.y, t.h) == (0, strip.height)
                        and re.fullmatch(r"mark|more|workspace:.+|(%s)\.(name|gauge|pct|text)" % "|".join(MODULES), t.id)):
                    bad.append((t.id, t.kind, t.state, sorted(t.flags), t.name))
                if t.id.endswith(".name"):
                    signs += 1
                    if t.w != 2 * d.cell:
                        wide.append((t.id, t.state, t.w))
    ok(lines and not bad, "names: in the %d states the bar wrote here, each of its %d target lines has an id, a name that is not empty, a kind, a state and flags of the bar's own, and the bar's whole height"
       % (len(d.seen), lines), bad[:6])
    gate = "geometry"
    ok(signs and not wide, "in each of those states a sign is an icon in two cells, whatever its module's state: %d sign lines" % signs, wide[:6])
    gate = "identity"
    if shutil.which("fc-list"):
        fonts = lambda *ask: subprocess.run(["fc-list", *ask, "family"], env=d.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=20).stdout.strip()   # noqa: E731
        lacking = ["U+%04X" % ord(c) for c in sorted(d.signs) if not fonts(":charset=%x" % ord(c))]
        ok(not lacking and len(d.signs) >= 8,
           "real glyphs: a font here holds every glyph the bar drew, the three families' pairs, the dots and the warning (%d of them), so none is a missing-glyph box; the signs are icons, and need no font" % len(d.signs), lacking)
    else:
        print("  skip identity: no fc-list here: which font holds each sign is not asked", flush=True)


def geometry(d):
    enter("geometry", "the spec's numbers, no shift, a bar short of width, the bottom, two screens")
    s = d.rest()
    base, strip_, env = s.rects(), s.bar(), d.bar_env()
    cell, high, ground, tones = d.cell, d.high, d.ground, d.tones
    inset = high // 9
    mark, plate, spaces, parts = s.find("mark"), s.plate(), s.spaces(), s.parts()
    run_end = spaces[-1].x + spaces[-1].w
    ok((strip_.height, strip_.scale, strip_.edge, mark.rect, cell, inset) == (BAR, 1, "top", (CELL, 0, MARK, BAR), CELL, 4) and env.get("BAR_FONT", "").endswith(" 12")
       and round(TEXT * 2.25) == BAR and round(TEXT * 1.5) == MARK,
       "the state file, at 16 px text (12 points): the bar is %d px high, a cell, the font's 0, is %d px, the logo %d px one cell from the edge" % (BAR, CELL, MARK),
       (strip_.height, mark.rect, env.get("BAR_FONT"), cell))
    ok(spaces[0].x == mark.x + mark.w + cell == 44 and [t.rect for t in spaces] == [(44 + 30 * i, 0, 30, BAR) for i in range(10)] and plate.rect == (44, 0, 30, BAR) and run_end == 344
       and run_end - (mark.x + mark.w + cell) == 300,
       "the run: from 44 px, ten places of 30 px with none between, the plate one of them, 300 px in all", [t.rect for t in spaces])
    area = next(w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1)
    win = d.node(d.windows[0].pid)["rect"]

    def rows():
        shot = d.grab(0, 0, W, BAR + 12)
        column = shot.fall((run_end + parts[0].x) // 2, 0, ground)
        box, _, cols = plate_reads(d, shot.part(0, 0, W, BAR), plate)
        room = shot.part(plate.x - cell, 0, cell, BAR).colors() == {ground}
        return column == (0, BAR) and box == (44, 4, 30, 28) and room, (column, box, room)
    good, saw = seen(rows)
    ok(good and (area["x"], area["y"], area["width"], area["height"]) == (0, BAR, W, H - BAR) and win["y"] == BAR,
       "the screen: the bar's ground is %d rows at the top, and the windows' area begins under it; the plate is 30 by 28 px, 4 px from the bar's top and bottom, over its place's three cells, a cell of bare ground before the run" % BAR, (saw, area, win))
    line = d.line()
    want, gone, hair = plan(line, s.levels, W, run_end, OVERFLOW.split(), cell)
    ok([(t.id, t.x, t.w) for t in parts] == want and not gone and not strip_.dropped,
       "the status stands as the spec lays it from the line's facts: every part in its cells, counted from the right edge", (moved(dict((i, (x, w)) for i, x, w in want), dict((t.id, (t.x, t.w)) for t in parts)), gone))
    at = {t.id: t for t in parts}
    icon = 2 * cell   # a sign is an icon, in two cells
    gaps = {"out's sign to its gauge": at["out.gauge"].x - at["out.name"].x - icon, "its gauge to its number's cells": at["out.pct"].x + at["out.pct"].w - 4 * cell - at["out.gauge"].x - 5 * cell,
            "the keyboard's sign to its layout": at["kb.text"].x - at["kb.name"].x - icon, "the battery's sign to its number": at["bat.text"].x - at["bat.name"].x - icon,
            "the wire to bluetooth": at["bt.name"].x - at["lan.name"].x - icon,
            "bluetooth to wifi": at["wifi.name"].x - at["bt.name"].x - icon, "out to the mic": at["mic.name"].x - at["out.pct"].x - at["out.pct"].w,
            "the keyboard to the battery": at["bat.name"].x - at["kb.text"].x - 2 * cell, "wifi to out": at["out.name"].x - at["wifi.name"].x - icon,
            "the mic to the keyboard": at["kb.name"].x - at["mic.name"].x - icon, "the battery to the time": at["clock.text"].x - at["bat.text"].x - 4 * cell,
            "the time to the flag": at["notifications.name"].x - at["clock.text"].x - 5 * cell, "the flag's cells to the edge": W - at["notifications.name"].x - icon - cell - 2 * cell}
    ok(gaps == {"out's sign to its gauge": cell, "its gauge to its number's cells": cell, "the keyboard's sign to its layout": cell, "the battery's sign to its number": cell,
                "the wire to bluetooth": 3 * cell, "bluetooth to wifi": 3 * cell,
                "out to the mic": 3 * cell, "the keyboard to the battery": 3 * cell, "wifi to out": 5 * cell, "the mic to the keyboard": 5 * cell, "the battery to the time": 5 * cell,
                "the time to the flag": 3 * cell, "the flag's cells to the edge": 2 * cell}
       and at["out.gauge"].w == 5 * cell and at["out.pct"].w == 3 * cell and at["clock.text"].w == 5 * cell and {at[i].w for i in at if i.endswith(".name")} == {icon},
       "the gaps: one cell between a module's parts, three between the modules of a group, five between groups; the time and the flag three cells apart; two cells of room at the edge; a sign's icon two cells, a gauge five, a number its digits and the percent sign",
       gaps)
    x = at["clock.text"].x - 5 * cell + 5 * cell // 2

    def hairline():
        shot = d.strip()
        line_ = shot.fall(x, high // 2, tones["dim"])
        sides = [shot.part(x + dx, 0, 1, high).colors() == {ground} for dx in (-1, 1)]
        return line_ == (high // 4, high * 3 // 4 - high // 4) and all(sides) and shot.run(x, high // 2, tones["dim"]) == (x, 1), (line_, sides)
    good, saw = seen(hairline)
    ok(good and hair == x and x == at["bat.text"].x + 4 * cell + 5 * cell // 2,
       "the hairline before the time: 1 px wide, the dim color, from a quarter to three quarters of the bar's height, in the middle of the five cells before it", (saw, hair, x))
    # no shift
    kept, shots = collections.OrderedDict(), {}
    slot = (at["out.gauge"].x + 6 * cell, 0, 4 * cell, high)
    for label, level, off, cells in (("5%", 5, False, 2), ("100%", 100, False, 4), ("muted", 100, True, 0)):
        now = d.says(level, off)
        kept[label] = now.rects()
        got = {}

        def number():
            got["img"] = d.grab(*slot)
            inked = [bool(got["img"].part(i * cell, 0, cell, high).ink(ground, 40)) for i in range(4)]
            return inked == [False] * (4 - cells) + [True] * cells and (now.find("out.pct").w if cells else 0) == cells * cell, inked
        good, saw = seen(number)
        shots[label] = got["img"] if good else None
    d.flag("down", True)
    kept["no device"] = d.told(lambda s: s.find("out.name").state == "missing", "out to say missing").rects()
    d.flag("down", False)
    d.machine("class/net/eth0/carrier", "0\n")
    kept["the wire down"] = d.told(lambda s: s.find("lan.name").state == "wrong" and s.find("out.name").state == "muted", "the wire to say wrong").rects()
    s = d.rest()
    ok(all(not stays(base, r) for r in kept.values()) and len(kept) == 5,
       "no shift: every target that stays is in the same rectangle at 5%, at 100%, muted, with no sound device and with the wire down; a number's right edge stays", {k: stays(base, r) for k, r in kept.items() if stays(base, r)})
    ok(all(shots.values()) and shots["5%"].part(3 * cell, 0, cell, high).data == shots["100%"].part(3 * cell, 0, cell, high).data
       and shots["5%"].part(2 * cell, 0, cell, high).data != shots["100%"].part(2 * cell, 0, cell, high).data,
       "no shift on the screen: the percent sign stands in the same pixels at 5% and at 100%, the digits at the right of the three cells kept for them, a cell each; muted, the four cells are empty", {k: bool(v) for k, v in shots.items()})
    # a workspace outside 1 to 10
    d.sway("workspace", "number", "23")
    far_ = d.until(lambda s: s.find("workspace:23") and "visible" in s.find("workspace:23").flags, "workspace 23 shown")
    extra = far_.find("workspace:23")
    good, saw = seen(lambda: (lambda r: (r[0] == (extra.x, inset, 3 * cell, high - 2 * inset) and r[1] and label_stands(r[2], cell), r[:2]))(plate_reads(d, d.strip(), extra)))
    ok(good and [t.id for t in far_.spaces()] == [t.id for t in spaces] + ["workspace:23"] and extra.rect == (run_end, 0, 3 * cell, high) and extra.name == "workspace 23"
       and not stays(base, far_.rects()),
       "a workspace outside 1 to 10 gets a place after the tenth: 23 is the eleventh, three cells, the plate while it is shown; no place has moved, and the status has not", (saw, far_.brief()))
    d.sway("workspace", "number", "1")
    d.until(lambda s: not s.find("workspace:23") and "visible" in s.find("workspace:1").flags, "workspace 1 shown again, and no place for 23")
    # a bar short of width: the config pins three levels, so there are numbers and gauges to give up
    pid = d.bar_pid()
    d.configure("BAR_PINS=out mic wifi\n")
    pinned = d.told(lambda s: s.find("mic.gauge") and s.find("wifi.pct") and s.find("out.pct"), "three levels pinned by the config")
    line = d.line()
    want, gone, _ = plan(line, pinned.levels, W, run_end, OVERFLOW.split(), cell)
    ok([(t.id, t.x, t.w) for t in pinned.parts()] == want and not gone and pinned.find("wifi.gauge").kind == "open" and pinned.find("mic.gauge").kind == "level" and d.bar_pid() == pid,
       "pins honoured: BAR_PINS=out mic wifi in the config, and the next line puts a gauge and a number beside each of the three; the wifi's, a reading, opens its section; the same process", pinned.brief())
    plans = collections.OrderedDict((w, plan(line, pinned.levels, w, run_end, OVERFLOW.split(), cell)) for w in range(W, 20 * cell, -cell))
    def first(test):
        return next((w for w, p in plans.items() if test(p[1])), None)
    steps = (("the numbers go first, all of them, and nothing else", first(lambda g: g and all(i.endswith(".pct") for i in g))),
             ("then the gauges, all of them, and still no module", first(lambda g: any(i.endswith(".gauge") for i in g) and all("." in i for i in g))),
             ("then whole modules, the ones the config's order does not name first, from the left, and three dots stand for them", first(lambda g: len([i for i in g if "." not in i]) == 3)),
             ("at the narrowest every module that may leave has left: the workspaces and the time's group stay, with the dots", first(lambda g: len([i for i in g if "." not in i]) == 7)))
    orders = []
    for words, width in steps:
        want, gone, hair = plans.get(width, ([], [], None))
        d.sway("output", OUT, "mode", "%dx%d" % (width or W, H))
        d.layout()
        now = settle(lambda: (lambda s: s and s.bar() and s.bar().width == width and s.bar().dropped == gone and s)(d.state()), 8) or d.state()
        orders.append(gone)
        ok(width and now.bar().width == width and now.bar().dropped == gone and [(t.id, t.x, t.w) for t in now.parts()] == want and now.rects().get("mark") == base["mark"]
           and [t.rect for t in now.spaces()] == [t.rect for t in spaces] and (not want or min(x for _, x, _ in want) >= run_end + 5 * cell),
           "a bar %s px wide: %s (%s)" % (width, words, " ".join(gone)), (gone, now.brief()))
    ok(all(steps[i][1] and steps[i][1] > steps[i + 1][1] for i in range(3)) and orders[0] == ["wifi.pct", "out.pct", "mic.pct"] and orders[1] == orders[0] + ["wifi.gauge", "out.gauge", "mic.gauge"]
       and orders[2] == orders[1] + ["lan", "bt", "kb"] and orders[3] == orders[1] + ["lan", "bt", "kb", "wifi", "mic", "out", "bat"],
       "the order is the spec's and the config's (BAR_OVERFLOW=%s): numbers, gauges, then lan and bt, which it does not name, then kb, wifi, mic, out and bat" % OVERFLOW, (steps, orders))
    more, clock = now.find("more"), now.find("clock.text")
    n = len(d.opened())

    def dots():
        shot = d.strip(width=now.bar().width)
        return bool(more) and place(shot, more).tone(ground, tones) == ["dim"] and shot.fall(clock.x - 5 * cell + 5 * cell // 2, high // 2, tones["dim"])[1] == high * 3 // 4 - high // 4, None
    good, _ = seen(dots)
    if more:
        d.click(more.mid)
        d.away()
    ok(more and (more.kind, more.name, more.w, more.state) == ("open", "more", cell, "ok") and clock.x - more.x == 6 * cell and good and (settle(lambda: d.opened()[n:], 8) or [""])[-1].endswith(" dialog"),
       "the three dots: one dim cell at the status's left end, five cells before the time with the hairline between, named more; a click on it opens home, where the modules are", (more and more.rect, d.opened()[n:]))
    d.shot("geometry-narrow")
    d.sway("output", OUT, "mode", "%dx%d" % (W, H))
    d.layout()
    d.configure()
    s = d.told(lambda s: s.bar().width == W and not s.bar().dropped and s.rects() == base, "the bar %d px wide again, out alone pinned" % W)
    ok(d.bar_pid() == pid, "the screen wide again and the pins as they were: the whole line is back, every target where it was; the same process through it all", (pid, d.bar_pid()))
    # the bottom edge, by the verb
    said = d.shell("bar", "bottom")
    s = d.until(lambda s: s.bar().edge == "bottom" and s.status == "ok" and s.find("clock.text"), "the bar at the bottom", 30)
    area = settle(lambda: next((w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1 and H - (w["rect"]["y"] + w["rect"]["height"]) - w["rect"]["x"] == BAR), None), 5) \
        or next(w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1)
    win = d.node(d.windows[0].pid)["rect"]
    ok(said.returncode == 0 and s.rects() == base and H - (area["y"] + area["height"]) - area["x"] == BAR and area["y"] == area["x"] and win["y"] + win["height"] <= H - BAR
       and d.bar_pid() != pid,
       "spark-shell bar bottom: the bar is started again there, through sway; the state file says bottom, every target at the same place along it; the windows' area ends %d px over the screen's edge and a tiled window's rect with it, clear of the bar" % BAR,
       (said.said[-200:], s.bar().edge, moved(base, s.rects()), area, win))
    low, saw = mark_seen(d, mark.x, H - BAR + (BAR - MARK) // 2)
    up, _ = mark_seen(d, mark.x, (BAR - MARK) // 2, False)
    good, box = seen(lambda: (lambda b: (b == (plate.x, inset, plate.w, high - 2 * inset), b))(plate_reads(d, d.strip((0, H - BAR)), plate)[0]))
    ok(low and up and good, "on the screen the logo stands in the bottom %d rows, and no longer at the top; the plate is in its box there too" % BAR, (saw, box))
    d.shot("geometry-bottom")
    said = d.shell("bar", "top")
    s = d.until(lambda s: s.bar().edge == "top" and s.status == "ok" and s.find("clock.text"), "the bar at the top again", 30)
    area = settle(lambda: next((w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1 and w["rect"]["y"] - w["rect"]["x"] == BAR), None), 5) \
        or next(w["rect"] for w in d.ask("get_workspaces") if w["num"] == 1)
    ok(said.returncode == 0 and s.rects() == base and area["y"] - area["x"] == BAR and H - (area["y"] + area["height"]) == area["x"],
       "spark-shell bar top: back at the top, the windows' area %d px under the screen's edge again" % BAR, (said.said[-200:], moved(base, s.rects()), area))
    # two screens
    d.sway("create_output")
    s = d.until(lambda s: len(s.outputs) == 2 and all(b.targets and b.targets[-1].id == "notifications.name" for b in s.outputs.values()), "a bar on each of two screens", 15)
    outs = {o["name"]: o for o in d.layout()}
    other = next(name for name in s.outputs if name != OUT)
    theirs = next(w["num"] for w in d.ask("get_workspaces") if w["output"] == other)
    there, here, at_ = s.plate(other), s.plate(), outs[other]["rect"]
    ok(set(outs) == set(s.outputs) and all(s.bar(n).width == outs[n]["rect"]["width"] and s.bar(n).height == BAR and s.bar(n).edge == "top" for n in outs)
       and [t.id for t in s.spaces(other)] == [t.id for t in s.spaces()] == REST[1:11] and [t.id for t in s.parts(other)] == [t.id for t in s.parts()] == REST[11:]
       and s.rects() == base and here.id == "workspace:1" and here.flags == {"selected", "visible"} and there.id == "workspace:%d" % theirs and there.flags == {"visible"}
       and "empty" not in s.find(there.id).flags and [t.rect for t in s.spaces(other)] == [t.rect for t in s.spaces()] and [t.id for t in s.spaces(other) if "empty" not in t.flags] == [t.id for t in s.spaces() if "empty" not in t.flags],
       "two screens (swaymsg create_output): a bar on each, %d px, the logo, the ten places in the same cells and the same status on both; each has its own plate, on the workspace it shows, and the other screen's workspace is a full place; the first screen's bar has not moved" % BAR,
       s.brief())

    def second():
        shot = d.strip((at_["x"], at_["y"]), at_["width"])
        box, lies, cols = plate_reads(d, shot, there)
        good, off = run_reads(d, shot, s, other)
        mine = plate_reads(d, d.strip(width=W), here)[0]
        return box == (there.x, inset, 3 * cell, high - 2 * inset) and lies and label_stands(cols, cell) and good and mine == (here.x, inset, 3 * cell, high - 2 * inset), (box, lies, off, mine)
    good, saw = seen(second)
    logo, r = mark_seen(d, at_["x"] + mark.x, at_["y"] + (BAR - MARK) // 2)
    ok(good and logo, "on the second screen the logo is drawn too, the same pixels, its plate stands on its own workspace, %d, and the run around it is the pair; the first screen's plate is where it was" % theirs, (saw, r))
    d.sway("mode", "resize")
    s = d.until(lambda s: s.mode == "resize", "the binding mode in the state file")
    good, saw = seen(lambda: (lambda found: (found == [["attention"]] * 2, found))(
        [d.grab(outs[n]["rect"]["x"] + max(t.x + t.w for t in s.spaces(n)) + cell, outs[n]["rect"]["y"], 6 * cell, high).tone(ground, tones) for n in (OUT, other)]))
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
    d.click(at_["x"] + sign.mid, at_["y"] + high // 2)
    both_say = d.until(lambda s: s.named("out.name", other) == "output muted" and s.named("out.name") == "output muted", "out muted by a click on the second screen's bar")
    ok(not s.focused(OUT) and d.muted("out"), "the keys go to the bar of the screen that has the focus, and a click on the second screen's bar acts: out is muted, and both bars say so", both_say.brief())
    d.click(at_["x"] + sign.mid, at_["y"] + high // 2)
    s = d.until(lambda s: s.named("out.name") == "output 40%", "out unmuted")
    # the second screen at rest, by its own rest workspace, as the idle screen names it; the first is not
    idle, second = "%s %s" % (RESTS, other), s.rects(other)
    area = lambda key: next((w["rect"] for w in d.ask("get_workspaces") if key in (w["name"], w["num"])), None)   # noqa: E731  a workspace's rectangle, by its name or its number
    mine = lambda: seen(lambda: (lambda b: (b == (here.x, inset, 3 * cell, high - 2 * inset), b))(plate_reads(d, d.strip(width=W), here)[0]))   # noqa: E731  the first screen's plate, on the screen
    d.sway("workspace", idle)
    alone = d.until(lambda s: s.resting == [other] and list(s.outputs) == [OUT], "the second screen at rest, the first not")
    whole = settle(lambda: area(idle) == at_, 5)
    bare, saw = no_bar(d, (at_["x"], at_["y"]), at_["width"])
    good, box = mine()
    ok(whole and bare and good and alone.rects() == base and alone.plate().id == here.id,
       "two screens, the second at rest (its workspace named %s): it alone has no bar, its workspace's rectangle the whole screen and nothing drawn where its bar was; the first screen's bar stands as it stood, its plate drawn" % idle,
       (area(idle), saw, box, alone.brief()))
    ok(not alone.find("workspace:" + idle) and [t.id for t in alone.spaces()] == REST[1:11],
       "the rest workspace has no place on the first screen's bar: its run is the ten places, as with one screen", alone.brief())
    # no surface of the bar's is left on the screen at rest, to take the pointer for the keys: the first bar has
    # the keys, the pointer travels on the second screen, and the keys stay
    d.sway("focus", "output", OUT)
    d.shell("bar", "keys")
    d.until(lambda s: s.focused() == "mark", "the keys on the first screen's bar")
    for step in (0, 7 * cell):
        d.move(at_["x"] + at_["width"] // 4 + step, at_["y"] + at_["height"] // 2)
    d.key("Right")
    held = d.until(lambda s: s.focused() == "workspace:1", "Right to move the keys, after the pointer travelled on the screen at rest", 5)
    d.key("Escape")
    d.until(lambda s: not s.focused(), "Escape to give the keyboard back")
    ok(held.resting == [other], "while the first screen's bar has the keys the pointer moved %d px on the screen at rest gives no key back: nothing of the bar is there to hear it, and Right still moves the keys" % (7 * cell), held.brief())
    d.sway("focus", "output", other)
    d.sway("workspace", "number", str(theirs))
    both = d.until(lambda s: not s.resting and s.rects(other) == second and s.plate(other).id == there.id, "the second screen's bar back")
    under = settle(lambda: area(theirs) == dict(at_, y=at_["y"] + high, height=at_["height"] - high), 5)
    back, saw = seen(lambda: (lambda b: (b == (there.x, inset, 3 * cell, high - 2 * inset), b))(plate_reads(d, d.strip((at_["x"], at_["y"]), at_["width"]), there)[0]))
    ok(under and back and both.rects() == base, "its own workspace shown again, the second screen's bar is back as it was: every target in its rectangle, its plate drawn, the windows' area under it", (area(theirs), saw, both.brief()))
    d.sway("focus", "output", OUT)
    d.sway("output", other, "unplug")
    s = settle(lambda: (lambda s: s and len(s.outputs) == 1 and s)(d.state()), 8)
    if s:
        d.layout()
        ok(s.rects() == base, "the second screen unplugged: its bar is gone with it, and the first screen's stands as it stood", s.brief())
    else:
        note("this sway unplugs no screen: the second one stays for the rest of the proof")


def relook(d):
    """The look travels in the line: another palette while the bar runs, written as a theme's change writes it,
    then previewed and applied through spark-shell; the logo and the tones again on the light ground."""
    enter("identity", "the look travels in the line: another palette, the bar running")
    s = d.rest()
    bar, high, clock = d.bar_pid(), d.high, s.find("clock.text")
    gap = (max(t.x + t.w for t in s.spaces()) + min(t.x for t in s.parts())) // 2

    def wears(bg, fg):
        """Whether the bar's ground and its text are those colors on the screen, and what they are."""
        def read():
            ground, text = d.grab(gap, high // 2, 1, 1).px(0, 0), d.grab(*clock.rect)
            lies, most = text.reach(bg, fg)
            return near(ground, bg) and lies and most >= 0.97, (ground, lies, round(most, 2))
        return read

    def gallery(name):
        text = (REPO / "gallery/theme" / (name + ".env")).read_text()
        return [rgb(re.search(r"^THEME_%s=#([0-9a-fA-F]{6})$" % key, text, re.M).group(1)) for key in ("BG", "FG")]
    d.palette("light")
    d.nudge()
    pal = d.pal
    mine = rgb(pal["BG"]), rgb(pal["FG"])
    good, saw = seen(wears(*mine), 20)
    look = d.line()[0]
    ok(good and d.bar_pid() == bar and [look.get(k) for k in ("ground", "fg", "accent", "muted", "alert", "attention")] == [pal["BG"], pal["FG"], pal["ACCENT"], pal["MUTED"], pal["ANSI"][1], pal["ANSI"][3]],
       "another palette written while the bar runs: the next line carries its look, and the bar's ground and text are its colors on the screen, the same process (pid %s)" % bar,
       (saw, look, bar, d.bar_pid()))
    mark = s.find("mark")
    good, r = mark_seen(d, mark.x, (high - mark.w) // 2)
    ok(good, "on the light ground the logo is the light ground's asset (%s, ink #%s) at %d px, %.2f a channel off; the dark ground's logo is %.2f off"
       % (r["file"], r["ink"], MARK, r["fits"].get(MARK, -1), r["other"]), r)
    d.shot("look-light")
    enter("accessibility", "the light palette")
    contrasts(d)
    tones_at_rest(d, s)
    # what is written on the accent: a palette whose ground does not read on its accent, so the look says another ink
    d.palette("pale")
    d.nudge()
    plate, inset, accent, look = s.plate(), high // 9, d.tones["accent"], d.line()[0]
    ink = rgb(look.get("ink") or d.pal["BG"])

    def written():
        strip = d.strip()
        box, lies, cols = plate_reads(d, strip, plate, ink)
        grounded = plate_reads(d, strip, plate)[1]
        return box == (plate.x, inset, plate.w, high - 2 * inset) and lies and label_stands(cols, d.cell) and not grounded, (box, lies, grounded, cols[:1], cols[-1:])
    good, saw = seen(written, 20)
    ok(look.get("accent") == d.pal["ACCENT"] and far(ink, d.ground) >= 48 and contrast(d.ground, accent) < 4.5 <= contrast(ink, accent) and good and d.bar_pid() == bar,
       "the ink: on this palette's accent its ground reads at %.1f to 1, and the line's look says another ink, #%s, %.1f to 1; on the screen the plate's digits are that ink, and not the ground's color; the same process"
       % (contrast(d.ground, accent), look.get("ink"), contrast(ink, accent)), (look, saw, bar, d.bar_pid()))
    d.shot("look-ink")
    # and before the first line: a bar started under this palette is handed the ink with the rest of its look
    d.end_bar()
    d.flag("slow", True)
    started = d.shell("bar", "start")
    d.until(lambda s: s.status == "loading" and s.plate().rect == plate.rect, "the bar up before its first line", 10)
    env = d.bar_env()
    good, saw = seen(written)
    d.flag("slow", False)
    d.until(lambda s: s.status == "ok" and s.find("clock.text"), "the first line", 40)
    ok(started.returncode == 0 and env.get("BAR_INK") == look.get("ink") and good,
       "a bar started under this palette has the ink in its environment (BAR_INK), and before its first line the plate's digits are that ink too", (started.said, env.get("BAR_INK"), saw))
    bar = d.bar_pid()
    enter("identity", "a theme previewed and applied through spark-shell, the bar running")
    said = d.shell("bar", "panel", "theme", "preview", "tokyonight-night")   # the dialog's own step, by its verb
    good, saw = seen(wears(*gallery("tokyonight-night")), 20)
    ok(said.returncode == 0 and good and d.bar_pid() == bar, "a palette looked at (spark-shell bar panel theme preview tokyonight-night): the bar wears it, the same process",
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
            at = time.time()
            try:
                part(d)
            except AssertionError as e:
                ok(False, str(e))
            except Exception as e:   # a part that could not go on fails, and the next one starts from rest
                traceback.print_exc()
                ok(False, "the checks could not go on: %s: %s" % (type(e).__name__, e))
            if os.environ.get("BAR_PROOF_TIMES"):
                print("  time %s: %.1f s" % (part.__name__, time.time() - at), flush=True)
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
