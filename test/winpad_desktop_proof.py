#!/usr/bin/env python3
"""Prove the pad on a separate headless sway with a real foot, a real swaybar and spark-winpad:
python3 test/winpad_desktop_proof.py [EVIDENCE_DIRECTORY]. A throwaway HOME and a sway of its own, once in a
dark palette and once in solarized-light, as a surface change is proven (the handbook's two palettes).

Each round puts foot windows on the pad as the keys do (spark-shell desktop window: a tiled one with Down twice,
a floating one with Right then Down twice), and reads what the pad does from the compositor and the screen. By
default it is a row of icons at the bottom (#269): cells of 36 px under the handle, the 6 px line in the band's
color across its top, hide at the end, and it keeps a strip of its own height and the outer gap (the workspace's
area ends above it). The pointer on an icon lights it and a label over the pad says its words, as the dialog
names a window (the app's name, then the title, lowercase). A foot floated across the strip leaves the pad in
sight above it, and a click on an icon through it brings the tiled window back tiled. The bar's block says how
many wait, the bar's toggle hides the pad and gives the strip back. The pad dragged from an icon to the left edge
in 2 px steps changes its shape once, from a row to a column, docks there and keeps its strip there, and
spark-shell lays the windows out again once for it, never during the drag. Super+minus (desktop pad keys) shows
it with the keyboard on it and Enter brings the last one back, and the pad goes once no window waits.

Then four windows, three of them foot: the pad resized from its top left corner to two rows keeps a strip as
thick and asks spark-shell to keep its height; shrunk from its left side to one column it folds the foots into
one icon whose badge, a filled circled number in the accent at its top right, reads three (with Monaspace Neon,
by the glyph foot draws in that font; without it, by its color); made big enough again the group opens back into
its icons. A click on the group opens its list beside it, a row a window, the oldest first, and a click on a row
brings that window back; Super+minus, Enter on the group and Enter on its list bring another, and Up moves a row.
Then the band on, the bar at the bottom: the handle and the band stand where the pad is, over a strip of both and
the row, and the bar where it was. Last the titled view (desktop pad view titles): slots of 228 px, an item's
words read as the dialog's, the handle line across them. Then the dialog on the pad (v0.134.3): a foot whose app
id is spark-dialog wears spark's own mark, the block-letter S of the assets beside spark-shell, the dark one's
yellow on a dark surface and the light one's on a light one, in both views, and its words are spark, then its
title, the same pixels as a window named spark with that title, whose icon is no S. The screen is captured at each
step into the evidence directory.

Nothing here rests on a number read at the start: a bar in a fallback font grows a pixel once its line is
drawn, so every length is read from the edge the bar does not touch, or as the pad's own.

spark-winpad is SPARK_SHELL_WINPAD, else component/winpad/target's release build; spark-shell starts it through a script of
the proof's that writes what spark-winpad was handed and what it asks of spark-shell, and runs both as they
are. Needs sway, swaymsg, foot, grim, wtype and python3; swaybar where the family has it."""
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "test"))
from home_desktop_proof import Pointer  # noqa: E402  the repo's virtual pointer: motion, button, frame

W, H = 1920, 1080
GAP = 8           # sway's outer gap here, as spark-shell's GAPS_OUTER (#265); the pad's margin comes in WINPAD_GAP
BADGES = "\u2777\u2778\u2779"   # the filled circled two, three and four: what a group's badge may read here
failed = 0


def ok(cond, what, detail=""):
    global failed
    print("  %s %s%s" % ("ok  " if cond else "FAIL", what, "" if cond else "   " + str(detail)), flush=True)
    failed += 0 if cond else 1


def wait_for(read, description, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = read()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("timed out: " + description)


def nodes(node):
    yield node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key, []):
            yield from nodes(child)


def ppm(path):
    """A binary PPM (P6) as (width, height, bytes): grim writes one with -t ppm."""
    data = path.read_bytes()
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


def pixel(img, x, y):
    w, _, px = img
    o = (y * w + x) * 3
    return tuple(px[o:o + 3])


def near(a, b, tolerance=24):
    return all(abs(p - q) <= tolerance for p, q in zip(a, b))


def far(a, b):
    return max(abs(p - q) for p, q in zip(a, b))


def rgb(hexa):
    hexa = hexa.lstrip("#")
    return tuple(int(hexa[i:i + 2], 16) for i in (0, 2, 4))


def text_px(font):
    """The text size in pixels of a pango font, as spark-winpad reads WINPAD_FONT: points at 96 dpi, or px."""
    size = (font.split() or [""])[-1]
    try:
        return float(size[:-2]) if size.endswith("px") else float(size) * 96 / 72
    except ValueError:
        return 16.0


def lengths(font):
    """The pad's lengths at the text size it was handed (WINPAD_FONT, the bar's), as component/winpad/src/pad.rs's
    Metrics::for_text makes them: the mock-up's at 16 px (36 an icon's cell, 6 the handle, 228 a slot), in
    proportion at any other."""
    k = min(max(text_px(font) / 16, 0.5), 3.0)

    def s(v):
        return int(v * k + 0.5)
    return {"slot": s(228), "cell": s(40), "ctl": s(24), "band": s(24), "tool": s(36), "icon": s(24), "tip": s(24),
            "handle": max(s(6), 4)}


def pad_binary():
    named = os.environ.get("SPARK_SHELL_WINPAD")
    if named:
        return Path(named)
    for candidate in (REPO / "component/winpad/target/release/spark-winpad", REPO / "component/winpad/target/x86_64-unknown-linux-gnu/release/spark-winpad"):
        if candidate.is_file():
            return candidate
    raise SystemExit("no spark-winpad: build component/winpad/ (cargo build --release) or name it in SPARK_SHELL_WINPAD")


def shim(root, binary):
    """spark-winpad as spark-shell starts it, read on the way: a script named spark-winpad writes the environment
    spark-shell hands the pad (its colors, WINPAD_GAP, WINPAD_BAND, WINPAD_VIEW, WINPAD_HEIGHT) and points the pad's
    SPARK_SHELL at a second one, which writes each call the pad makes and runs spark-shell with it. The apps
    adapter and the assets stay beside it, for the icons and the dialog's mark."""
    folder = root / "shim"
    folder.mkdir()
    (folder / "lib").symlink_to(REPO / "lib")
    (folder / "asset").symlink_to(REPO / "asset")
    calls, handed = root / "pad-calls", root / "pad-env"
    logger = folder / "spark-shell"
    # a refit's call writes too where the focused workspace's area ends at that moment, as sway has it (#273)
    logger.write_text("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %s\n"
                      "[ \"$*\" != 'desktop window refit' ] || swaymsg -t get_workspaces | jq -c '[.[] | select(.focused) | .rect.y + .rect.height][0]' >> %s\n"
                      "exec sh %s \"$@\"\n"
                      % (shlex.quote(str(calls)), shlex.quote(str(calls) + ".areas"), shlex.quote(str(REPO / "spark-shell"))))
    pad = folder / "spark-winpad"
    pad.write_text("#!/bin/sh\nenv | grep '^WINPAD_' > %s\nSPARK_SHELL=%s exec %s \"$@\"\n"
                   % (shlex.quote(str(handed)), shlex.quote(str(logger)), shlex.quote(str(binary))))
    for script in (logger, pad):
        script.chmod(0o755)
    return pad, calls, handed


def runs(img, y, color_set, tolerance, x0=0, x1=None):
    """The runs of a row whose pixels are each near one of the colors: (start, length), left to right."""
    w, _, px = img
    x1 = w if x1 is None else x1
    out, start = [], None
    for x in range(x0, x1):
        o = (y * w + x) * 3
        r, g, b = px[o], px[o + 1], px[o + 2]
        hit = any(abs(r - c[0]) <= tolerance and abs(g - c[1]) <= tolerance and abs(b - c[2]) <= tolerance for c in color_set)
        if hit and start is None:
            start = x
        if not hit and start is not None:
            out.append((start, x - start))
            start = None
    if start is not None:
        out.append((start, x1 - start))
    return out


def runs_column(img, x, color_set, tolerance, y0=0, y1=None):
    """The runs of a column whose pixels are each near one of the colors: (start, length), top to bottom."""
    y1 = img[1] if y1 is None else y1
    out, start = [], None
    for y in range(y0, y1):
        hit = any(near(pixel(img, x, y), c, tolerance) for c in color_set)
        if hit and start is None:
            start = y
        if not hit and start is not None:
            out.append((start, y - start))
            start = None
    if start is not None:
        out.append((start, y1 - start))
    return out


def widest(img, rows, color_set, tolerance):
    """The longest run of the pad's colors over some rows: the pad's width where it stands."""
    return max((n for y in rows for _, n in runs(img, y, color_set, tolerance)), default=0)


def words_in(img, box, ground, fg, muted=None):
    """A line of words in a box (x, y, w, h) on a ground color: the columns with ink split at the widest blank
    gap, the two spaces between an app's name and its title. Each part: its ink's top and bottom rows, and its
    pixels at the text color and at the muted one. None when the box holds one word or none."""
    x0, y0, w, h = box
    step = max(24, far(fg, ground) // 3)   # ink: a third of the way from the ground to the text color, or more
    inked = []
    for x in range(x0, x0 + w):
        inked.append([y for y in range(y0, y0 + h) if far(pixel(img, x, y), ground) >= step])
    cols = [i for i, rows in enumerate(inked) if rows]
    if len(cols) < 4:
        return None
    gaps = [(b - a, a, b) for a, b in zip(cols, cols[1:]) if b - a > 1]
    if not gaps:
        return None
    _, cut_a, cut_b = max(gaps)

    def part(lo, hi):
        rows = [y for i in range(lo, hi + 1) for y in inked[i]]

        def count(color):
            return sum(1 for i in range(lo, hi + 1) for y in range(y0, y0 + h) if near(pixel(img, x0 + i, y), color, 12))
        return {"top": min(rows), "bottom": max(rows), "height": max(rows) - min(rows) + 1, "text": count(fg),
                "muted": count(muted or fg), "width": hi - lo + 1}
    return part(cols[0], cut_a), part(cut_b, cols[-1])


def lowercase(name, title):
    """A title of x-height letters (manor, ocean) drawn lowercase stands lower than an app's name with an
    ascender (foot's f) on one baseline; in capitals it would stand as tall."""
    return title["height"] <= name["height"] * 0.85 and abs(title["bottom"] - name["bottom"]) <= 2


def mask(img, box, color, tolerance=40):
    """The pixels of a box near a color, as a set of (x, y) from the top left corner of their own bounding box."""
    x0, y0, w, h = box
    got = [(x, y) for y in range(max(y0, 0), min(y0 + h, img[1])) for x in range(max(x0, 0), min(x0 + w, img[0]))
           if near(pixel(img, x, y), color, tolerance)]
    if not got:
        return set()
    lx, ly = min(x for x, _ in got), min(y for _, y in got)
    return {(x - lx, y - ly) for x, y in got}


def likeness(a, b):
    """How alike two masks are: their overlap over their union, at the best shift of a pixel or two."""
    if not a or not b:
        return 0.0
    best = 0.0
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            moved = {(x + dx, y + dy) for x, y in a}
            best = max(best, len(moved & b) / len(moved | b))
    return best


def inside(m):
    """The pixels inside a glyph's outline that are not its ink: the digit of a filled circled number."""
    rows, cols = {}, {}
    for x, y in m:
        rows.setdefault(y, []).append(x)
        cols.setdefault(x, []).append(y)
    return {(x, y) for y, xs in rows.items() for x in range(min(xs) + 1, max(xs)) if (x, y) not in m
            and x in cols and min(cols[x]) < y < max(cols[x])}


def blobs(m):
    """A mask split at its blank columns: the glyphs of a line, left to right, each from its own corner."""
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
        out.append({(x - lx, y - ly) for x, y in part})
    return out


def has_font(family):
    """Whether fontconfig gives this family itself, not a fallback."""
    try:
        got = subprocess.run(["fc-match", "-f", "%{family}", family], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return family.lower() in got.lower()


def settle(read, seconds=8):
    """What `read` says once it says yes, or at the end of the wait: for a check that reports what it saw."""
    end = time.time() + seconds
    value = read()
    while not value and time.time() < end:
        time.sleep(0.1)
        value = read()
    return value


def round_in(palette, binary, evidence):
    print("palette " + palette, flush=True)
    root = Path(tempfile.mkdtemp(prefix="pad-proof."))
    runtime = root / "run"
    runtime.mkdir(mode=0o700)
    settings = root / ".config/spark-shell"
    settings.mkdir(parents=True)
    (settings / "config").write_text("DESKTOP=sway\nTHEME=%s\nALPHA=1\n" % palette)
    spark = root / ".config/spark"   # the palette in use is spark's theme.env, as the other proofs set it
    spark.mkdir(parents=True)
    shutil.copyfile(REPO / "gallery/theme" / (palette + ".env"), spark / "theme.env")
    pad, calls, handed = shim(root, binary)
    env = {**os.environ, "HOME": str(root), "SPARK_SHELL_ROOT": str(root / "sysroot"), "XDG_CONFIG_HOME": str(root / ".config"),
           "XDG_STATE_HOME": str(root / ".local/state"), "XDG_DATA_HOME": str(root / ".local/share"),
           "XDG_RUNTIME_DIR": str(runtime), "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman",
           "WLR_LIBINPUT_NO_DEVICES": "1", "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_WINPAD": str(pad)}
    for name in ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "WINPAD_BAND", "WINPAD_GAP", "WINPAD_VIEW", "WINPAD_HEIGHT"):
        env.pop(name, None)
    # a real swaybar on top, its line spark-shell's own, so the bar's block is the one people see
    config = root / "sway.conf"
    bar = ("bar {\n position top\n status_command sh %s bar status\n}\n" % (REPO / "spark-shell")) if shutil.which("swaybar") else ""
    config.write_text("output HEADLESS-1 mode %dx%d\nxwayland disable\ndefault_border pixel 2\ngaps outer %d\n%s" % (W, H, GAP, bar))
    children = [subprocess.Popen(["sway", "-c", str(config)], env=env, cwd=root,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)]
    pointer = None
    shots = 0

    def pad_pid():
        lock = runtime / "spark-shell-winpad.pid"
        try:
            pid = int(lock.read_text().split()[0])
            os.kill(pid, 0)
            # a pad that ended and that nothing reaped (a container's first process reaps none) is gone
            if Path("/proc/%d/stat" % pid).read_text().rsplit(")", 1)[1].split()[0] == "Z":
                return None
            return pid
        except (OSError, ValueError, IndexError):
            return None

    def pad_empty():
        """The pad with no window waiting: it stays for the session, its surfaces gone (v0.140)."""
        state = runtime / "spark-shell-winpad.state"
        return pad_pid() is not None and state.exists() and "count 0" in state.read_text()

    try:
        sock = wait_for(lambda: next(iter(runtime.glob("sway-ipc.*.sock")), None), "sway's socket")
        display = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*")
                                         if not p.name.endswith(".lock")), None), "the display")
        env.update({"SWAYSOCK": str(sock), "WAYLAND_DISPLAY": display})
        pointer = Pointer(env)
        # a keyboard on the seat for the whole round, as the apps proof keeps one: a headless sway has none
        children.append(subprocess.Popen(["wtype", "-s", "600000"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))

        def stamp():
            return int(time.monotonic() * 1000) & 0xffffffff

        def move(x, y):
            pointer.send(5, 1, stamp(), int(x), int(y), W, H)   # motion_absolute, in the screen's own pixels
            pointer.send(5, 4)
            pointer.sync()

        def button(down):
            pointer.send(5, 2, stamp(), 272, 1 if down else 0)   # BTN_LEFT
            pointer.send(5, 4)
            pointer.sync()

        def click(x, y):
            move(x, y)
            time.sleep(0.1)
            button(True)
            time.sleep(0.1)
            button(False)
            time.sleep(0.1)

        def drag(start, dx, dy, step=2):
            """A press at `start`, the pointer moved dx, dy in steps of `step` px with the button held, let go."""
            move(*start)
            time.sleep(0.2)
            button(True)
            n = max(abs(dx), abs(dy)) // step or 1
            for i in range(1, n + 1):
                move(start[0] + dx * i // n, start[1] + dy * i // n)
                time.sleep(0.02)
            time.sleep(0.2)
            button(False)
            time.sleep(0.6)

        def keys(*names):
            for name in names:
                subprocess.run(["wtype", "-s", "100", "-k", name, "-s", "100"], env=env, capture_output=True)
                time.sleep(0.3)

        def tree():
            out = subprocess.run(["swaymsg", "-t", "get_tree"], env=env, capture_output=True, text=True).stdout
            return json.loads(out or "null") or {}

        def foot(pid):
            return next((n for n in nodes(tree()) if n.get("pid") == pid), None)

        def workspace_of(ident):
            return next((w for w in nodes(tree()) if w.get("type") == "workspace"
                         and any(n.get("id") == ident for n in nodes(w))), None)

        def on_pad(pid):
            return workspace_of(foot(pid)["id"])["name"] == "__i3_scratch"

        def area():
            ws = next(w for w in json.loads(subprocess.run(["swaymsg", "-t", "get_workspaces"], env=env,
                                                           capture_output=True, text=True).stdout) if w["focused"])
            r = ws["rect"]
            return r["x"], r["y"], r["width"], r["height"]

        def bottom():
            x, y, w, h = area()
            return y + h

        def shell(*words):
            done = subprocess.run(["sh", str(REPO / "spark-shell"), *words], env=env, capture_output=True, text=True)
            time.sleep(0.6)
            return (done.stdout + done.stderr).strip()

        def capture(name):
            nonlocal shots
            shots += 1
            name = "%s-%02d-%s" % (palette, shots, name)
            raw = root / (name + ".ppm")   # read here, then gone with the round's folder: the evidence keeps the PNG
            subprocess.run(["grim", "-t", "ppm", "-o", "HEADLESS-1", str(raw)], env=env, check=True)
            subprocess.run(["grim", "-o", "HEADLESS-1", str(evidence / (name + ".png"))], env=env, check=True)
            return ppm(raw)

        def grab(x, y, w, h):
            raw = root / "grab.ppm"
            subprocess.run(["grim", "-t", "ppm", "-g", "%d,%d %dx%d" % (x, y, w, h), str(raw)], env=env, check=True)
            return ppm(raw)

        def refits():
            text = calls.read_text() if calls.exists() else ""
            return text.splitlines().count("desktop window refit")

        def refit_ends():   # where the area ended at each refit's call, as sway had it then
            path = Path(str(calls) + ".areas")
            return [int(n) for n in (path.read_text().split() if path.exists() else []) if n.lstrip("-").isdigit()]

        def places():
            text = calls.read_text() if calls.exists() else ""
            return [line.split() for line in text.splitlines() if line.startswith("desktop pad place ")]

        def handed_env():
            return dict(line.split("=", 1) for line in (handed.read_text() if handed.exists() else "").splitlines() if "=" in line)

        def open_foot(title, focus=True, app=None):
            # a command of its own, so no shell renames the window: its title is the one given
            child = subprocess.Popen(["foot", *(["--app-id", app] if app else []), "--title", title, "sleep", "3600"], env=env, cwd=root,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            children.append(child)
            wait_for(lambda: foot(child.pid), "foot " + title)
            if focus:
                subprocess.run(["swaymsg", "[pid=%d] focus" % child.pid], env=env, capture_output=True)
            time.sleep(0.4)
            return child

        def minimize(child):
            subprocess.run(["swaymsg", "[pid=%d] focus" % child.pid], env=env, capture_output=True)
            time.sleep(0.2)
            said = shell("desktop", "window", "down")
            wait_for(lambda: on_pad(child.pid), "%d on the pad (%s)" % (child.pid, said))

        wait_for(lambda: area()[1] >= (20 if bar else 0) and area()[3] > 0 and area(), "the workspace's area under the bar")   # the bar drawn first
        # the bar is at the top: with nothing at the bottom, the windows' area runs down to sway's gap there
        floor = H - GAP

        def reaches(edge):
            """The windows' area runs to sway's gap at an edge: nothing keeps a strip there. Never the height read at
            the start: a bar in a fallback font grows a pixel or two once its line is drawn."""
            x, y, w, h = area()
            return y + h == floor if edge == "bottom" else x == GAP

        # 1. a tiled foot, Down twice: it goes to the pad, marked tiled, and the pad keeps its strip
        a = open_foot("MANOR").pid
        said = shell("desktop", "window", "down")
        na = foot(a)
        marks = na.get("marks", []) if na else []
        ok(workspace_of(na["id"])["name"] == "__i3_scratch", "Down twice puts the tiled window on the pad", said)
        ok(any(m.startswith("_spark-shell.min.tiled.") for m in marks), "its mark says it left the tiling", marks)
        wait_for(pad_pid, "spark-winpad started by the minimize")
        given = dict(line.split("=", 1) for line in wait_for(lambda: handed.exists() and handed.read_text(), "the pad's environment").splitlines() if "=" in line)
        gap = int(given.get("WINPAD_GAP") or 8)
        ok(given.get("WINPAD_BAND") in (None, "off") and gap == GAP, "spark-shell hands the pad the band off and the outer gap as its margin",
           {k: given.get(k) for k in ("WINPAD_BAND", "WINPAD_GAP")})
        ok(given.get("WINPAD_VIEW") in (None, "icons") and given.get("WINPAD_HEIGHT") in (None, "0"),
           "and the icons view, as many rows as needed, by default", {k: given.get(k) for k in ("WINPAD_VIEW", "WINPAD_HEIGHT")})
        m = lengths(given.get("WINPAD_FONT", ""))
        SLOT, CELL, BAND, TOOL, CTL, HANDLE = m["slot"], m["cell"], m["band"], m["tool"], m["ctl"], m["handle"]   # at 16 px: 228, 40, 24, 36, 24, 6
        ROW = HANDLE + TOOL                    # a row of icons under the handle
        inset = int(m["icon"] / 3 + 0.5)
        text_dx, text_w = inset + m["icon"] + inset, SLOT - int(inset * 3.75 + m["icon"])   # a titled item's words: past its icon
        row_floor = floor - ROW - gap
        settle(lambda: bottom() == row_floor)
        ok(bottom() == row_floor, "a row of icons at the bottom by default keeps a strip of its height: the area ends %d px over sway's gap, the row's %d and the pad's %d"
           % (floor - bottom(), ROW, gap), area())
        settle(lambda: refits() >= 1, 5)
        time.sleep(0.3)
        ok(refits() == 1, "the strip come, the pad asks spark-shell once to lay the windows out again", refits())
        ok(refit_ends()[:1] == [row_floor], "and asks once sway holds the strip: the area ends over it at the call (#273)", (refit_ends(), row_floor))

        # 2. a floating foot, Right then Down twice: a second icon, and the row read from the screen
        b = open_foot("OCEAN").pid
        shell("desktop", "window", "right")
        shell("desktop", "window", "down")
        shell("desktop", "window", "down")
        ok(on_pad(b), "Right, Down, Down puts the floating window on the pad")
        move(W // 2, 300)   # the pointer off the pad
        time.sleep(0.8)
        img = capture("two-windows")
        surface, lit, fg, muted = rgb(given["WINPAD_SURFACE"]), rgb(given["WINPAD_LIT"]), rgb(given["WINPAD_FG"]), rgb(given["WINPAD_MUTED"])
        band, accent = rgb(given["WINPAD_BAND_HEX"]), rgb(given["WINPAD_ACCENT"])
        top = H - gap - ROW            # the pad's top: the handle, a row of icons under it, over the pad's margin
        cells = top + HANDLE           # the icons' row
        row = [r for r in runs(img, cells + 2, (surface, lit), 6) if r[1] >= 2 * TOOL]
        want_w = 2 * TOOL + 1 + CTL
        ok(len(row) == 1 and abs(row[0][1] - want_w) <= 1,
           "two icons by default: two cells of %d px and hide's past a hairline, %d px wide" % (TOOL, want_w), runs(img, cells + 2, (surface, lit), 6)[:6])
        left = row[0][0] if row else (W - want_w) // 2
        handle = [r for r in runs(img, top + 2, (band,), 6) if r[0] <= left + 2 and r[0] + r[1] >= left + want_w - 2]
        ok(handle and all(near(pixel(img, left + 4, top + i), band, 6) for i in range(HANDLE))
           and near(pixel(img, left + 2, top + HANDLE), surface, 6) and not near(pixel(img, left + 4, top - 1), band, 6),
           "the handle, %d px in the band's color, runs across the pad's top" % HANDLE,
           [pixel(img, left + 4, top + i) for i in (-1, 0, HANDLE - 1, HANDLE)])
        ok(near(pixel(img, left + 4, top - 6), pixel(img, left + 4, top - 30), 6) and not near(pixel(img, left + 4, top - 6), surface, 6),
           "no band over it", pixel(img, left + 4, top - 6))
        line = shell("bar", "status", "--once")
        try:
            blocks = json.loads(line)
        except ValueError:
            blocks = []
        pad_block = next((blk for blk in blocks if blk.get("name") == "pad"), None)
        ok(pad_block is not None and "\u229f" in pad_block.get("full_text", "") and "2" in pad_block.get("full_text", ""),
           "the bar's block says two windows wait", pad_block)
        ok(blocks and blocks[0].get("name") == "pad", "it is the first block of the status line", [b_.get("name") for b_ in blocks][:3])

        # 3. the pointer on the first icon lights it, and a label over the pad says its words, 400 ms on
        first = (left + TOOL // 2, cells + TOOL // 2)
        move(*first)
        time.sleep(1.2)
        img = capture("lit")
        ok(near(pixel(img, left + 2, cells + 2), lit, 6), "the icon under the pointer is lit", pixel(img, left + 2, cells + 2))
        label_y = top - 6 - m["tip"]
        ground = pixel(img, left + 3, label_y + 2)
        label = [r for r in runs(img, label_y + 2, (ground,), 6, left, left + 400) if r[0] == left]
        ok(near(ground, surface, 16) and label, "a label stands over the pad, at the lit icon", (ground, runs(img, label_y + 2, (ground,), 6, left, left + 400)[:4]))
        parts = words_in(img, (left + 4, label_y + 1, label[0][1] - 8, m["tip"] - 2), ground, fg) if label else None
        ok(parts is not None and parts[0]["text"] >= 4 and parts[1]["text"] >= 4 and lowercase(*parts),
           "the label says the lit window's words, the name and the title, lowercase", parts)

        # 4. a foot floated across the pad's strip: the pad stays in sight, above it (#263)
        cover = open_foot("COVER")
        subprocess.run(["swaymsg", "[pid=%d] floating enable, resize set 1400 300, move position 260 %d" % (cover.pid, H - 260)],
                       env=env, capture_output=True)
        wait_for(lambda: foot(cover.pid)["rect"]["y"] + foot(cover.pid)["rect"]["height"] > top + ROW, "the foot across the strip")
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("covered")
        row = [r for r in runs(img, cells + 2, (surface, lit), 6) if r[1] >= 2 * TOOL]
        over = [x for x in range(left, left + want_w, 4) if not near(pixel(img, x, top - 40), surface, 6)]
        ok(len(row) == 1 and len(over) >= want_w // 8, "a foot floated across the strip covers the windows' area and not the pad: its row still reads there",
           (runs(img, cells + 2, (surface, lit), 6)[:6], pixel(img, left + 8, top - 40)))

        # 5. a click on the first icon, the foot still across it, brings the tiled window back, tiled
        click(*first)
        wait_for(lambda: not on_pad(a), "the first window back")
        na = foot(a)
        ok(na.get("type") == "con", "a click on an icon brings it back, tiled as it was", na.get("type"))
        capture("one-back")
        cover.terminate()
        wait_for(lambda: foot(cover.pid) is None, "the covering foot gone")

        # 6. the bar's click hides the pad: the strip is the windows' again; a second shows it
        shell("desktop", "pad", "toggle")
        wait_for(lambda: reaches("bottom"), "the strip given back")
        ok(True, "hidden, the pad gives its strip back")
        state = (runtime / "spark-shell-winpad.state").read_text() if (runtime / "spark-shell-winpad.state").exists() else ""
        ok("hidden 1" in state, "the pad says it is hidden, for the bar's block", state)
        capture("hidden")
        shell("desktop", "pad", "toggle")
        wait_for(lambda: bottom() == row_floor, "the pad back in sight")
        ok(True, "a second toggle shows it again")
        settle(lambda: refits() >= 3, 5)
        time.sleep(0.3)
        ok(refits() == 3, "spark-shell asked once as the strip went and once as it came", refits())
        ok(refit_ends()[1:3] == [floor, row_floor], "each once sway had the change: the area at sway's gap as the strip went, over the strip as it came (#273)",
           (refit_ends(), floor, row_floor))

        # 7. the pad dragged from its icon to the left edge in 2 px steps: one change of shape, from a row to a
        #    column docked there with its strip, and one refit, after the drop (#261, #266)
        img = grab(0, top - 2, W, ROW + 4)
        one_w = TOOL + 1 + CTL           # one icon in a row, hide at its end
        row = [r for r in runs(img, HANDLE + 4, (surface, lit), 6) if r[1] >= one_w - 2]
        left = row[0][0] if row else (W - one_w) // 2
        before = refits()
        move(left + TOOL // 2, cells + TOOL // 2)
        time.sleep(0.2)
        button(True)
        for i in range(1, 13):   # 6 px with the button held: a drag, not a click
            move(left + TOOL // 2, cells + TOOL // 2 - i)
            time.sleep(0.02)
        y = 500
        for i in range(1, 21):
            move(left + TOOL // 2 + (300 - left - TOOL // 2) * i // 20, cells + TOOL // 2 - 12 + (y - cells - TOOL // 2 + 12) * i // 20)
            time.sleep(0.02)
        widths = []   # the pad's width where it stands, at each step: the longest run of its colors around the pointer
        for x in list(range(300, 0, -2)) + [70]:
            move(x, y)
            time.sleep(0.05)
            widths.append((x, widest(grab(0, y - 40, 640, 80), range(0, 80, 2), (surface, lit, band), 6)))
        shapes = ["column" if n <= TOOL + 4 else "row" if n >= one_w - 4 else "?" for _, n in widths]
        steps = shapes[:-1]
        changes = sum(1 for p, q in zip(steps, steps[1:]) if p != q)
        turn = next((x for (x, _), shape in zip(widths, steps) if shape == "column"), None)
        ok(changes == 1 and "?" not in steps and steps[0] == "row",
           "dragged to the left edge in 2 px steps, the pad turns from a row to a column once, as the pointer comes %s px from the edge" % turn,
           [(x, n) for x, n in widths][::6])
        ok(shapes[-1] == "column", "back out to 70 px the column holds the edge: it lets go at 96", widths[-2:])
        move(2, y)
        time.sleep(0.1)
        during = refits()
        button(False)
        dock = GAP + TOOL + gap
        wait_for(lambda: area()[0] == dock and reaches("bottom"), "the pad docked at the left edge", seconds=8)
        ok(on_pad(b), "a drag from an icon brings no window back")
        ok(True, "dropped at the left edge, it docks there as a column and keeps its strip: the area starts %d px in" % dock)
        img = capture("left")
        column = [r for r in runs_column(img, gap + 3, (surface, lit, band), 6) if r[1] >= TOOL]
        ok(column, "the column's color stands at the left edge", runs_column(img, gap + 3, (surface, lit, band), 6)[:6])
        wait_for(lambda: refits() > during, "spark-shell asked after the drop", seconds=5)
        time.sleep(0.6)
        ok(during == before and refits() == before + 1, "spark-shell asked once, after the drop and not during the drag", (before, during, refits()))
        ok(places() and places()[-1][3:5] == ["left", "center"] and len(places()[-1]) == 8,
           "and keeps its place, its widths and its height: desktop pad place PLACE WIDTH SIDE HEIGHT", places()[-1:])

        # 8. Super+minus: the keyboard on the pad, the newest picked; Enter brings it back
        shell("desktop", "pad", "keys")
        time.sleep(0.5)
        capture("keys")
        keys("Return")
        wait_for(lambda: not on_pad(b), "Enter brings the second back")
        ok(True, "Super+minus then Enter brings the newest back")

        # 9. no window waits: the pad's surfaces go and the bar's block with them; the pad itself stays for the session
        wait_for(pad_empty, "spark-winpad with no window, still here for the glyphs", seconds=10)
        ok(wait_for(lambda: reaches("left") and reaches("bottom"), "the strip given back with the last window"), "the pad stays and gives its strip back")
        blocks = json.loads(shell("bar", "status", "--once") or "[]")
        ok(not any(blk.get("name") == "pad" for blk in blocks), "the bar's block is gone")
        refused = shell("desktop", "pad", "keys")
        ok("no window is on the pad" in refused, "Super+minus with nothing on the pad says so", refused)

        # 10. four windows at the bottom, three of them foot; resized from its top left corner to two rows
        shell("desktop", "pad", "place", "bottom center", "0", "36", "0")
        group = [open_foot("GROUP ONE"), open_foot("NOTES", app="notes"), open_foot("GROUP TWO"), open_foot("GROUP THREE")]
        g1, notes, g2, g3 = group
        for child in group:
            minimize(child)
        wait_for(pad_pid, "spark-winpad started for four")
        four_w = 4 * TOOL + 1 + CTL
        settle(lambda: bottom() == row_floor)
        move(W // 2, 300)
        time.sleep(0.8)

        def pad_box(img):
            """The pad at the bottom, as the screen shows it: its left, its top, its width and its height. Its cells'
            last row read across, then its left column up to the handle's top."""
            y = H - gap - 3
            row = next((r for r in runs(img, y, (surface, lit), 6) if r[0] <= W // 2 < r[0] + r[1]), None)
            if not row:
                return None
            col = next((r for r in runs_column(img, row[0] + 2, (surface, lit, band), 6, H - 400, H - gap) if r[0] + r[1] == H - gap), None)
            return (row[0], col[0], row[1], col[1]) if col else None

        img = capture("four")
        box = pad_box(img)
        ok(box and abs(box[2] - four_w) <= 1 and box[3] == ROW, "four icons in a row, %d px wide and %d high" % (four_w, ROW), box)
        left, top = (box[0], box[1]) if box else ((W - four_w) // 2, H - gap - ROW)
        drag((left - 3, top - 3), 0, -(TOOL + 4))
        settle(lambda: bottom() == floor - HANDLE - 2 * TOOL - gap)
        two = HANDLE + 2 * TOOL
        ok(bottom() == floor - two - gap, "resized from its top left corner to two rows, it keeps a strip as thick: %d px and the gap" % two, (floor - bottom(), area()))
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("two-rows")
        box = pad_box(img)
        two_w = 2 * TOOL + 1 + CTL
        ok(box and abs(box[2] - two_w) <= 1 and box[3] == two, "the four in two rows of two, %d by %d px" % (two_w, two), box)
        said = places()[-1] if places() else []
        ok(len(said) == 8 and said[3:5] == ["bottom", "center"] and int(said[7]) >= two,
           "the pad asks spark-shell to keep its height: desktop pad place ... %s" % (said[7] if len(said) == 8 else "?"), said)
        kept = (settings / "config").read_text()
        ok(("WINPAD_HEIGHT=%s" % said[7]) in kept if len(said) == 8 else False, "and spark-shell keeps it, WINPAD_HEIGHT", [ln for ln in kept.splitlines() if ln.startswith("WINPAD_")])

        # 11. shrunk from its left side until the foots fold into one icon, the app with the most windows first
        left, top = (box[0], box[1]) if box else ((W - two_w) // 2, H - gap - two)
        cells = top + HANDLE
        no_badge = img   # the four as they are, no group among them: a foot's cell without a badge
        plain = (left, cells)
        drag((left - 3, cells + TOOL), TOOL - 6, 0)
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("group")
        box = pad_box(img)
        one_w = TOOL + 1 + CTL
        ok(box and abs(box[2] - one_w) <= 1 and box[3] == two, "shrunk to one column of two cells, %d by %d px" % (one_w, two), box)
        ok(all(on_pad(c.pid) for c in group), "every window still waits on the pad")
        left, top = (box[0], box[1]) if box else ((W - one_w) // 2, H - gap - two)
        cells = top + HANDLE

        def badge_at(img, x, y, ground=None):
            """The accent a badge draws at a cell's top right: the pixels at the accent there (its glyph is filled
            with it; an icon's letter stroke drawn soft beside it is not), from past the cell's middle to past its
            right side and from over its top to its middle. Where a picture of the same cell
            without a badge is given, only the pixels that differ from it."""
            got = set()
            for py in range(y - 6, y + TOOL // 2 + 4):
                for px in range(x + TOOL // 2 + 1, x + TOOL + 6):
                    here = pixel(img, px, py)
                    if near(here, accent, 24) and (ground is None or far(here, pixel(ground[0], ground[1] + px - x, ground[2] + py - y)) > 24):
                        got.add((px, py))
            if not got:
                return set()
            lx, ly = min(px for px, _ in got), min(py for _, py in got)
            return {(px - lx, py - ly) for px, py in got}

        three = badge_at(img, left, cells, (no_badge, plain[0], plain[1]))
        other = badge_at(img, left, cells + TOOL, (no_badge, plain[0], plain[1]))
        # none: a few accent pixels at most, the fringes a font's smoothing puts on an icon's letter (Ubuntu's tile N)
        ok(len(three) >= 20 and len(other) < min(8, len(three) // 4), "the group of three foots wears a badge in the accent at its icon's top right, the other app none (%d px)" % len(three),
           (len(three), len(other)))
        monaspace = has_font("Monaspace Neon") and "monaspace neon" in given.get("WINPAD_FONT", "").lower()
        references = {}
        if monaspace:
            # the glyphs as foot draws them in the pad's font at the badge's size (a quarter over the text's), in the
            # accent on the pad's surface; [colors] is foot's section before 1.25 and [colors-dark] since, so both
            hexes = {"background": given["WINPAD_SURFACE"].lstrip("#"), "foreground": given["WINPAD_ACCENT"].lstrip("#")}
            colors = [arg for section in ("colors", "colors-dark") for k, v in hexes.items() for arg in ("-o", "%s.%s=%s" % (section, k, v))]
            ref = subprocess.Popen(["foot", "--app-id", "badges", "--font", "Monaspace Neon:pixelsize=%d" % round(text_px(given["WINPAD_FONT"]) * 1.25), *colors,
                                    "sh", "-c", "printf '\\033[2J\\033[H\\033[?25l%s'; exec sleep 3600" % "  ".join(BADGES)],
                                   env=env, cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            children.append(ref)
            wait_for(lambda: foot(ref.pid), "foot drawing the badges")
            subprocess.run(["swaymsg", "[pid=%d] floating enable, border none, resize set 300 80, move position 100 200" % ref.pid], env=env, capture_output=True)
            time.sleep(1.0)
            r = foot(ref.pid)["rect"]   # where sway put it: a floating window's position is the workspace's
            spot = (r["x"], r["y"], min(r["width"], 300), min(r["height"], 80))
            subprocess.run(["grim", "-g", "%d,%d %dx%d" % spot, str(evidence / ("%s-badges-by-foot.png" % palette))], env=env, check=True)
            drawn = blobs(mask(grab(*spot), (0, 0, spot[2], spot[3]), accent, 24))
            references = dict(zip(BADGES, drawn)) if len(drawn) == len(BADGES) else {}
            ok(references, "foot draws the three circled numbers for the reading", [len(d) for d in drawn])
            ref.terminate()
            wait_for(lambda: foot(ref.pid) is None, "foot's badges gone")
            time.sleep(0.4)

        def reads(m):
            """The badge's number by the glyph it is most like, its outline and its digit; none without Monaspace
            Neon's own glyphs to read it by."""
            if not references:
                return None
            score = {ch: round(likeness(m, ref) + likeness(inside(m), inside(ref)), 2) for ch, ref in references.items()}
            return max(score, key=score.get), score

        read = reads(three)
        if monaspace:
            ok(read is not None and read[0] == BADGES[1] and read[1][BADGES[1]] >= 1.2,
               "the badge reads three, the glyph foot draws for U+2778 in Monaspace Neon", read)
        else:
            print("  skip Monaspace Neon is not here: the badge is read by its color, not by its glyph", flush=True)

        # 12. made big enough again, the group opens back into its icons
        drag((left - 3, cells + TOOL), -(TOOL + 6), 0)
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("ungrouped")
        box = pad_box(img)
        ok(box and abs(box[2] - two_w) <= 1 and box[3] == two and not badge_at(img, box[0], box[1] + HANDLE, (no_badge, plain[0], plain[1])),
           "widened again to two columns, the group opens back into its four icons, no badge", box)
        left, top = (box[0], box[1]) if box else ((W - two_w) // 2, H - gap - two)
        drag((left - 3, top + HANDLE + TOOL), TOOL - 6, 0)
        move(W // 2, 300)
        time.sleep(0.8)
        box = pad_box(capture("group-again"))
        left, top = (box[0], box[1]) if box else ((W - one_w) // 2, H - gap - two)
        cells = top + HANDLE

        # 13. a click on the group opens its list over it, a row a window, the oldest first; a click on a row brings it back
        click(left + TOOL // 2, cells + TOOL // 2)
        time.sleep(0.6)
        img = capture("list")
        rows = 3
        list_top = top - 6 - rows * m["tip"]
        column = [r for r in runs_column(img, left + 3, (surface, lit), 6, top - 200, top) if r[1] >= rows * m["tip"]]
        ok(column and abs(column[-1][0] - list_top) <= 2 and column[-1][0] + column[-1][1] <= top - 4,
           "the group's list stands over it, %d rows of %d px" % (rows, m["tip"]), runs_column(img, left + 3, (surface, lit), 6, top - 200, top)[-3:])
        list_top = column[-1][0] + 1 if column else list_top
        across = [r for r in runs(img, list_top + 2, (surface, lit), 6) if r[0] <= left + 3 < r[0] + r[1]]
        list_w = across[0][1] - 2 if across else 160
        said = [words_in(img, (left + 4, list_top + i * m["tip"] + 1, list_w - 8, m["tip"] - 2), surface if i < rows - 1 else lit, fg) for i in range(rows)]
        ok(all(p is not None and p[0]["text"] >= 4 and p[1]["width"] > p[0]["width"] for p in said),
           "each row says a window's words, the app's name and its title", said)
        click(left + 60, list_top + m["tip"] // 2)
        wait_for(lambda: not on_pad(g1.pid), "the first foot back from the list")
        ok(all(on_pad(c.pid) for c in (notes, g2, g3)), "a click on the list's first row brings the oldest foot back, and that one alone")
        time.sleep(0.6)
        move(W // 2, 300)
        time.sleep(0.6)
        img = capture("group-of-two")
        box = pad_box(img)
        # notes first now: the group of the two foots left stands where the older of them does, the second cell
        two_left = badge_at(img, box[0], box[1] + HANDLE + TOOL, (no_badge, plain[0], plain[1])) if box else set()
        ok(box and len(two_left) >= 20 and len(badge_at(img, box[0], box[1] + HANDLE, (no_badge, plain[0], plain[1]))) < min(8, len(two_left) // 4),
           "the two foots left still fold, in the second cell, their badge there", (box, len(two_left)))
        if monaspace:
            read = reads(two_left)
            ok(read is not None and read[0] == BADGES[0] and read[1][BADGES[0]] >= 1.2, "and it reads two now", read)

        # 14. Super+minus picks the newest cell, the group; Enter opens its list, Up and Enter bring the older foot back
        shell("desktop", "pad", "keys")
        time.sleep(0.5)
        keys("Return")
        time.sleep(0.4)
        capture("list-keys")
        keys("Up", "Return")
        wait_for(lambda: not on_pad(g2.pid), "Enter on the list brings a foot back")
        ok(on_pad(g3.pid) and on_pad(notes.pid), "Super+minus, Enter on the group, Up and Enter bring the older foot back, and that one alone")
        # two windows in a column: Super+minus picks the newest, Up the one above it, Enter brings it back
        time.sleep(0.6)
        shell("desktop", "pad", "keys")
        time.sleep(0.5)
        keys("Up", "Return")
        wait_for(lambda: not on_pad(notes.pid), "Up then Enter brings the first cell back")
        ok(on_pad(g3.pid), "Up moves a row: Enter then brings the window above the newest back")
        shell("desktop", "pad", "keys")
        time.sleep(0.5)
        keys("Return")
        wait_for(pad_empty, "the pad with no window", seconds=10)
        ok(True, "the last one back, the pad's surfaces go")

        # 15. the band on, and the bar at the bottom (a new bar, before the pad): the pad over the bar, the handle and
        #     the band's color over the row, a strip of all three inside the bar's zone, and the bar where it was
        shell("desktop", "pad", "place", "bottom center", "0", "36", "0")
        if bar:
            config.write_text(config.read_text().replace("position top", "position bottom"))
            subprocess.run(["swaymsg", "reload"], env=env, capture_output=True)
            wait_for(lambda: area()[1] == GAP and bottom() < floor, "the bar at the bottom")
            time.sleep(1.5)   # its line drawn: the height it keeps
        edge = bottom() + GAP   # where the windows' area ends without the pad: the bar's top, or the screen's bottom
        before_bar = capture("bar-bottom")
        said = shell("desktop", "pad", "band", "on")
        for child in (a, b):
            subprocess.run(["swaymsg", "[pid=%d] focus" % child], env=env, capture_output=True)
            shell("desktop", "window", "down")
        wait_for(pad_pid, "spark-winpad started with its band")
        band_floor = edge - gap - HANDLE - BAND - TOOL - GAP
        settle(lambda: bottom() == band_floor)
        ok(bottom() == band_floor, "with the band on (%s) the strip is the handle, the band and the row, %d px, and the gap%s"
           % (said, HANDLE + BAND + TOOL, ", over the bar" if bar else ""), (edge, area()))
        move(W // 2, 200)
        time.sleep(0.6)
        img = capture("band")
        band_y = edge - gap - TOOL - BAND - HANDLE
        top_runs = [r for r in runs(img, band_y + 2, (band,), 6) if r[0] <= W // 2 < r[0] + r[1]]
        x0 = top_runs[0][0] if top_runs else W // 2 - TOOL
        ok(top_runs and all(near(pixel(img, x0 + 3, band_y + i), band, 6) for i in range(HANDLE + BAND)) and near(pixel(img, x0 + 2, band_y + HANDLE + BAND + 2), surface, 6),
           "the handle and the band's color stand where the pad is, %d px over its row" % (HANDLE + BAND), (top_runs, pixel(img, W // 2, band_y)))
        if bar:
            # had the strip taken the screen's edge, the bar would stand over the pad and the pad's colors under it
            under = [(x, y) for x in range(W // 2 - 40, W // 2 + 40, 4) for y in range(edge, H, 2)
                     if any(near(pixel(img, x, y), c, 6) for c in (band, surface, lit))]
            ok(not under and pixel(img, W // 2, edge + 1) == pixel(before_bar, W // 2, edge + 1),
               "the bar stays where it was, under the pad", (under[:4], pixel(img, W // 2, edge + 1), pixel(before_bar, W // 2, edge + 1)))
        click(x0 + TOOL // 2, edge - gap - TOOL // 2)
        wait_for(lambda: not on_pad(a), "the first window back from the banded pad")
        ok(True, "a click on its icon brings it back")

        # 16. the titled view: a slot a window, its words as the dialog's, the handle line across it
        shell("desktop", "pad", "band", "off")
        said = shell("desktop", "pad", "view", "titles")
        wait_for(lambda: handed_env().get("WINPAD_VIEW") == "titles" and pad_pid(), "the pad again in the titled view (%s)" % said)
        subprocess.run(["swaymsg", "[pid=%d] focus" % a], env=env, capture_output=True)
        shell("desktop", "window", "down")
        wait_for(lambda: on_pad(a), "the first window on the titled pad")
        titled = HANDLE + CELL
        settle(lambda: bottom() == edge - gap - titled - GAP)
        ok(bottom() == edge - gap - titled - GAP, "titles (%s): a strip of the handle and a titled row, %d px, and the gap" % (said, titled), (edge, area()))
        move(W // 2, 200)
        time.sleep(0.8)
        img = capture("titles")
        top = edge - gap - titled
        row = [r for r in runs(img, top + HANDLE + 3, (surface, lit), 6) if r[1] >= 2 * SLOT]
        ok(len(row) == 1 and abs(row[0][1] - (2 * SLOT + 1 + CTL)) <= 1, "two titled slots of %d px and hide's" % SLOT, runs(img, top + HANDLE + 3, (surface, lit), 6)[:6])
        left = row[0][0] if row else (W - 2 * SLOT) // 2
        ok(all(near(pixel(img, left + 40, top + i), band, 6) for i in range(HANDLE)) and near(pixel(img, left + 2, top + HANDLE), surface, 6),
           "the handle runs across the titled slots too", [pixel(img, left + 40, top + i) for i in (0, HANDLE - 1, HANDLE)])
        # the order on the pad: b went first, then a
        parts = words_in(img, (left + text_dx, top + HANDLE, text_w, CELL), surface, fg, muted)
        # a palette whose muted color reads at 4.5 to 1 only as the text color (solarized-light) has the two alike
        apart = far(fg, muted) > 24
        ok(parts is not None and parts[0]["text"] >= 4 and parts[1]["muted"] >= 4 and (parts[1]["text"] == 0 or not apart),
           "a slot reads its app's name in the text color, then its title, muted%s" % ("" if apart else " (the palette's muted is its text color)"), parts)
        ok(parts is not None and lowercase(*parts), "the title lowercase, as the dialog writes it (OCEAN as ocean: %s px tall to foot's %s)"
           % ((parts[1]["height"], parts[0]["height"]) if parts else ("?", "?")), parts)
        click(left + SLOT // 2, top + HANDLE + CELL // 2)
        wait_for(lambda: not on_pad(b), "the window back from the titled pad")
        move(W // 2, 200)
        time.sleep(0.8)
        row = [r for r in runs(grab(0, top + HANDLE + 3, W, 1), 0, (surface, lit), 6) if r[1] >= SLOT]
        left = row[0][0] if row else (W - SLOT) // 2
        click(left + SLOT // 2, top + HANDLE + CELL // 2)
        ok(wait_for(lambda: pad_empty() and bottom() == edge - GAP, "the pad with no window", seconds=10), "a click on its slot brings it back, and the pad's surfaces go")

        # 17. the dialog on the pad (v0.134.3): a foot whose app id is spark-dialog, as the dialog's window, wears
        #     spark's own mark, the S of the assets beside spark-shell, its three bands top to bottom: the dark one
        #     (#ffe066, #e0b400, #d24a2a) on a dark surface, the light one (#d4a400, #a87e00, #c2401f) on a light one,
        #     never recolored. An icon of 22 to 24 px smooths the thin bands, so the yellow and the red read within a
        #     few steps; the ochre, the thickest, reads as it is. The light S has nothing as bright as the dark one's
        #     yellow, and on a light ground the dark S keeps it: none there is the light S. Its words are spark, then
        #     its title: the same pixels as a window whose app is named spark with that title, whose icon, the
        #     letter tile, is no S: the mark is the dialog's alone
        dialog = open_foot("HOME", app="spark-dialog")
        twin = open_foot("HOME", app="org.example.spark")
        minimize(dialog)
        minimize(twin)
        wait_for(pad_pid, "spark-winpad started for the dialog")
        settle(lambda: bottom() == edge - gap - titled - GAP)
        move(W // 2, 200)
        time.sleep(0.8)
        img = capture("dialog-titles")
        top = edge - gap - titled
        row = [r for r in runs(img, top + HANDLE + 3, (surface, lit), 6) if r[1] >= 2 * SLOT]
        left = row[0][0] if row else (W - 2 * SLOT) // 2
        ground = pixel(img, left + SLOT // 2, top + HANDLE + 2)
        dark = (ground[0] * 299 + ground[1] * 587 + ground[2] * 114) // 1000 < 128
        yellow, ochre, red = (rgb(c) for c in (("ffe066", "e0b400", "d24a2a") if dark else ("d4a400", "a87e00", "c2401f")))
        icon = m["icon"]

        def inks(box, color, tolerance):
            x0, y0, w, h = box
            return sum(1 for y in range(y0, y0 + h) for x in range(x0, x0 + w) if near(pixel(img, x, y), color, tolerance))

        def icon_box(x, y):
            return (x - 2, y - 2, icon + 4, icon + 4)

        def the_s(box):
            """The S's three bands in a box, each a count of pixels, and the dark S's yellow where the light one stands."""
            return (inks(box, yellow, 28), inks(box, ochre, 12), inks(box, red, 28), 0 if dark else inks(box, rgb("ffe066"), 24))

        def reads_s(found):
            return found[0] >= 2 and found[1] >= 1 and found[2] >= 2 and found[3] == 0

        titled_icon = icon_box(left + inset, top + HANDLE + (CELL - icon) // 2)
        twin_icon = icon_box(left + SLOT + inset, top + HANDLE + (CELL - icon) // 2)
        found, twin_found = the_s(titled_icon), the_s(twin_icon)
        ok(reads_s(found), "the dialog's icon is spark's S for a %s ground, its bands %s: yellow, ochre and red pixels %s"
           % ("dark" if dark else "light", ", ".join("#%02x%02x%02x" % c for c in (yellow, ochre, red)), found[:3]), found)
        ok(twin_found[0] == 0 and twin_found[1] == 0, "the window named spark beside it wears no S: the mark is the dialog's", twin_found)
        words = [mask(img, (left + i * SLOT + text_dx, top + HANDLE + 2, text_w, CELL - 4), fg, 60) for i in (0, 1)]
        ink_w = [max((x for x, _ in w_), default=-1) + 1 for w_ in words]
        ok(words[0] and likeness(words[0], words[1]) >= 0.9 and abs(ink_w[0] - ink_w[1]) <= 1,
           "its words read as a window named spark with its title: spark, then home (%d px of ink, the same as %d)" % tuple(ink_w),
           (likeness(words[0], words[1]) if words[0] else None, ink_w))
        said = shell("desktop", "pad", "view", "icons")
        wait_for(lambda: handed_env().get("WINPAD_VIEW") in (None, "icons") and pad_pid(), "the pad in the icons view (%s)" % said)
        settle(lambda: bottom() == edge - gap - ROW - GAP)
        move(W // 2, 200)
        time.sleep(0.8)
        img = capture("dialog-icons")
        top = edge - gap - ROW
        row = [r for r in runs(img, top + HANDLE + 2, (surface, lit), 6) if r[1] >= 2 * TOOL]
        left = row[0][0] if row else (W - 2 * TOOL) // 2
        cell_icon = icon_box(left + (TOOL - icon) // 2, top + HANDLE + (TOOL - icon) // 2)
        found = the_s(cell_icon)
        ok(reads_s(found), "and in the icons view, the default, its cell is the same S: %s" % (found[:3],), found)
        # the keeper (v0.143): a winpad that ends by itself is started again; one stopped on purpose stays stopped
        was = pad_pid()
        os.kill(was, signal.SIGKILL)
        settle(lambda: pad_pid() not in (None, was), 8)
        now = pad_pid()
        ok(now not in (None, was), "a winpad that ends by itself is started again by its keeper", (was, now))
        if now not in (None, was):
            os.kill(now, signal.SIGTERM)
            time.sleep(3)
            ok(pad_pid() is None, "and one stopped on purpose stays stopped", pad_pid())
    except AssertionError as e:
        ok(False, str(e))
        try:
            capture("failure")
        except (subprocess.CalledProcessError, OSError):
            pass
    finally:
        if pointer:
            pointer.close()
        for child in reversed(children):
            child.terminate()
        for child in children:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
        # the pad ends with sway, and asks spark-shell once more as its strip goes: its line is written, then the folder goes
        settle(lambda: pad_pid() is None, 5)
        time.sleep(0.5)
        for _ in range(3):
            shutil.rmtree(root, ignore_errors=True)
            if not root.exists():
                break
            time.sleep(0.5)


def main():
    for tool in ("sway", "swaymsg", "foot", "grim", "wtype"):   # swaybar too where the family has it: the round takes a bar then
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    binary = pad_binary()
    evidence = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="pad-evidence."))
    evidence.mkdir(parents=True, exist_ok=True)
    for palette in ("tokyonight-night", "solarized-light"):
        round_in(palette, binary, evidence)
    print("pad proof: %s; the screens are in %s" % ("every step holds" if failed == 0 else "%d failed" % failed, evidence))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
