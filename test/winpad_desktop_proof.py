#!/usr/bin/env python3
"""Prove the pad on a separate headless sway with a real foot, a real swaybar and spark-winpad:
python3 test/winpad_desktop_proof.py [EVIDENCE_DIRECTORY]. A throwaway HOME and a sway of its own, once in a
dark palette and once in solarized-light, as a surface change is proven (the handbook's two palettes). Sway's
own bar draws here, never spark's (SPARK_SHELL_BAR is dropped): the pad on spark's bar is proven with that bar.

Each round puts foot windows on the pad as the keys do (spark-shell desktop window: a tiled one with Down twice,
a floating one with Right then Down twice), and reads what the pad does from the compositor and the screen. By
default, with no bar of spark's to stand on, it is a row of icons at the bottom's middle (#269): the grip's room
of 20 px at its left, cells of 36 px, hide a pixel past them, as high as one cell. It is a piece of the bar: the
bar's ground, an edge of 1 px in the lit tone inside it all around, and the grip, a line in the palette's dim
tone in the middle of its room, half as long as the room is across. It keeps a strip of its own height and the
outer gap (the workspace's area ends above it). The pointer on an icon lights its whole cell and a label over
the pad says its words, as the dialog names a window (the app's name, then the title, lowercase). A foot floated
across the strip leaves the pad in sight above it, and a click on an icon through it brings the tiled window back
tiled. The bar's block says how many wait, the bar's toggle hides the pad and gives the strip back. A screen on
the idle screen's workspace (idle, or idle and a screen's name) has no pad, keeps no strip and gives the pad no
keys, and the pad is back with the workspace before; a workspace named idler keeps it. The pad dragged from an
icon to the left edge in 2 px steps changes its shape once, from a row to a column with the middle of its grip's
room under the pointer, docks there, the grip's room across its top and hide under its cells, and keeps its
strip there, and spark-shell lays the windows out again once for it, never during the drag. Super+minus (desktop
pad keys) shows it with the keyboard on it, its edge the accent while it has the keys, and Enter brings the last
one back, and the pad goes once no window waits.

Then four windows, three of them foot: the pad resized from its top left corner to two rows keeps a strip as
thick and asks spark-shell to keep its height; shrunk from its left side to one column it folds the foots into
one icon whose badge, a filled circled number in the accent at its top right, reads three (with Monaspace Neon,
by the glyph foot draws in that font; without it, by its color); made big enough again the group opens back into
its icons. A click on the group opens its list beside it, a row a window, the oldest first, and a click on a row
brings that window back; Super+minus, Enter on the group and Enter on its list bring another, and Up moves a row.
Then the band on, the bar at the bottom: the band stands across the pad's top, the grip's room under it at the
row's left, over a strip of the band and the row, and the bar where it was. Last the titled view (desktop pad
view titles): slots of 228 px past the grip's room, an item's words read as the dialog's, the edge and the grip
as on the icons. Then the dialog on the pad (v0.134.3): a foot whose app id is spark-dialog wears spark's own
mark, the diamond in the chevron of the assets beside spark-shell, in its light ink on a dark ground and its
dark ink on a light one, in both views, and its words are spark, then its title, the same pixels as a window
named spark with that title, whose icon holds none of that ink. The screen is captured at each step into the
evidence directory.

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
    Metrics::for_text makes them: the mock-up's at 16 px (36 an icon's cell, 20 the grip's room, 228 a slot), in
    proportion at any other."""
    k = min(max(text_px(font) / 16, 0.5), 3.0)

    def s(v):
        return int(v * k + 0.5)
    return {"slot": s(228), "cell": s(40), "ctl": s(24), "band": s(24), "tool": s(36), "icon": s(24), "tip": s(24),
            "lead": s(20)}


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


def edge_off(img, box, tone):
    """The pixels of a pad's edge that are not a tone: the edge is the 1 px inside its rectangle (x, y, w, h), all
    around. None where the edge runs whole in that tone."""
    x, y, w, h = box
    line = [(px, py) for py in (y, y + h - 1) for px in range(x, x + w)]
    line += [(px, py) for px in (x, x + w - 1) for py in range(y + 1, y + h - 1)]
    return [p for p in line if not near(pixel(img, *p), tone, 6)]


def grip_line(img, room, tone, column=False):
    """The grip's line in its room (x, y, w, h), as the screen shows it: whether it is the line the pad draws, and
    the runs of its tone through the room's middle, down a row's room and along a column's. The line is one, 1 px
    wide, in the middle of the room and half as long as the room is across: its height in a row, its width in a
    column. A line that begins on half a pixel shows a pixel short."""
    x, y, w, h = room
    if column:
        got, lo, across = runs(img, y + h // 2, (tone,), 6, x, x + w), x, w
        beside = [pixel(img, x + w // 2, y + h // 2 + d) for d in (-1, 1)]
    else:
        got, lo, across = runs_column(img, x + w // 2, (tone,), 6, y, y + h), y, h
        beside = [pixel(img, x + w // 2 + d, y + h // 2) for d in (-1, 1)]
    long = across // 2
    held = (len(got) == 1 and long - 1 <= got[0][1] <= long and abs(2 * got[0][0] + got[0][1] - 2 * lo - across) <= 1
            and not any(near(p, tone, 6) for p in beside))
    return held, got


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
    # SPARK_SHELL_BAR too: this is the pad with sway's own bar, where a pad whose place is the bar (the default)
    # stands at the bottom's middle; a spark-bar named here would have spark-shell take the bar for spark's
    for name in ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "WINPAD_BAND", "WINPAD_GAP", "WINPAD_VIEW", "WINPAD_HEIGHT",
                 "SPARK_SHELL_BAR"):
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
        SLOT, CELL, BAND, TOOL, CTL, LEAD = m["slot"], m["cell"], m["band"], m["tool"], m["ctl"], m["lead"]   # at 16 px: 228, 40, 24, 36, 24, 20
        ROW = TOOL                             # a row of icons is as high as one cell: the grip's room is at its left
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
        # the pad is a piece of the bar: the bar's ground, its edge and a lit cell in the lit tone, the grip's line
        # in the palette's own dim tone (none handed: the muted one); a label and a group's list keep the surface
        ok(given.get("WINPAD_GROUND") and given.get("WINPAD_DIM"), "spark-shell hands the pad the bar's ground and the palette's dim tone, the grip's",
           {k: given.get(k) for k in ("WINPAD_GROUND", "WINPAD_DIM")})
        ground, surface, lit, fg, muted = (rgb(given[k]) for k in ("WINPAD_GROUND", "WINPAD_SURFACE", "WINPAD_LIT", "WINPAD_FG", "WINPAD_MUTED"))
        band, accent = rgb(given["WINPAD_BAND_HEX"]), rgb(given["WINPAD_ACCENT"])
        dim = rgb(given.get("WINPAD_DIM") or given["WINPAD_MUTED"])
        body = (ground, lit)           # what a row or a column of the pad reads as, off its icons
        top = H - gap - ROW            # the pad's top: a row of icons over the pad's margin, the cells as high as it
        row = [r for r in runs(img, top + 2, body, 6) if r[1] >= 2 * TOOL]
        want_w = LEAD + 2 * TOOL + 1 + CTL
        ok(len(row) == 1 and abs(row[0][1] - want_w) <= 1,
           "two icons by default: the grip's room of %d px, two cells of %d and hide's a pixel past them, %d px wide" % (LEAD, TOOL, want_w),
           runs(img, top + 2, body, 6)[:6])
        left = row[0][0] if row else (W - want_w) // 2
        ok(abs(left - (W - want_w) // 2) <= 1, "with no bar of spark's to stand on, it stands at the bottom's middle", (left, (W - want_w) // 2))
        off = edge_off(img, (left, top, want_w, ROW), lit)
        ok(not off and near(pixel(img, left + 1, top + 1), ground, 6)
           and not any(near(pixel(img, *p), lit, 6) for p in ((left + 4, top - 1), (left - 1, top + 4), (left + 4, top + ROW))),
           "the pad's edge, 1 px in the lit tone, runs inside it all around, on the bar's ground",
           (off[:4], [pixel(img, *p) for p in ((left, top), (left + 1, top + 1), (left + 4, top - 1), (left - 1, top + 4))]))
        held, line = grip_line(img, (left, top, LEAD, ROW), dim)
        ok(held, "the grip, a line of %d px in the dim tone, stands in the middle of its room at the row's left" % (ROW // 2),
           (line, pixel(img, left + LEAD // 2, top + ROW // 2)))
        past = left + LEAD + 2 * TOOL   # the pixel between the cells and hide: the pad's body, no hairline
        ok(all(near(pixel(img, past, y), ground, 6) for y in range(top + 1, top + ROW - 1)),
           "no hairline stands before hide: the pixel past the cells is the pad's ground", [pixel(img, past, top + i) for i in (1, ROW // 2, ROW - 2)])
        ok(near(pixel(img, left + 4, top - 6), pixel(img, left + 4, top - 30), 6)
           and not any(near(pixel(img, left + 4, top - 6), c, 6) for c in (ground, band)),
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
        cell_x = left + LEAD           # the first cell: past the grip's room
        first = (cell_x + TOOL // 2, top + TOOL // 2)
        move(*first)
        time.sleep(1.2)
        img = capture("lit")
        lit_row = runs(img, top + 2, (lit,), 6, left + 1, left + want_w - 1)
        lit_col = runs_column(img, cell_x + 2, (lit,), 6, top, top + ROW)
        ok(lit_row == [(cell_x, TOOL)] and lit_col == [(top, ROW)],
           "the icon under the pointer is lit: its whole cell, %d px past the pad's left, in the lit tone" % LEAD, (lit_row, lit_col))
        label_y = top - 6 - m["tip"]
        paper = pixel(img, cell_x + 3, label_y + 2)   # the label's ground, as the screen shows it
        label = [r for r in runs(img, label_y + 2, (paper,), 6, left, left + 400) if r[0] == cell_x]
        ok(near(paper, surface, 16) and label, "a label stands over the pad, at the lit icon", (paper, runs(img, label_y + 2, (paper,), 6, left, left + 400)[:4]))
        parts = words_in(img, (cell_x + 4, label_y + 1, label[0][1] - 8, m["tip"] - 2), paper, fg) if label else None
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
        row = [r for r in runs(img, top + 2, body, 6) if r[1] >= 2 * TOOL]
        over = [x for x in range(left, left + want_w, 4) if not near(pixel(img, x, top - 40), ground, 6)]
        ok(len(row) == 1 and len(over) >= want_w // 8, "a foot floated across the strip covers the windows' area and not the pad: its row still reads there",
           (runs(img, top + 2, body, 6)[:6], pixel(img, left + 8, top - 40)))

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

        # 6b. the rest: a screen that shows the idle screen's workspace has no pad and keeps no room for it, and
        #     nothing is stored, so the pad is back with the workspace before. The idle screen's workspace on
        #     another screen, the name and a space, is a rest too; a name that only starts alike is none
        ok(given.get("WINPAD_REST") == "idle", "spark-shell names the idle screen's workspace as the pad's rest", given.get("WINPAD_REST"))
        state_file = runtime / "spark-shell-winpad.state"
        one_w = LEAD + TOOL + 1 + CTL   # one icon in a row: the grip's room, its cell, hide at its end

        def pad_row():   # the pad's row at the bottom, as the screen shows it now
            return [r for r in runs(grab(0, top + 2, W, 1), 0, body, 6) if r[1] >= TOOL]

        def workspace(name, rests):
            """The screen on a workspace: the pad gone and the area at sway's gap when it rests, the pad and its
            strip there when not, and spark-shell asked once to lay the windows out again when that changed."""
            was, asked = bool(pad_row()), refits()
            subprocess.run(["swaymsg", "workspace", name], env=env, capture_output=True)
            if rests:
                held = settle(lambda: reaches("bottom") and not pad_row())
            else:
                held = settle(lambda: bottom() == row_floor and [r for r in pad_row() if abs(r[1] - one_w) <= 1])
            settle(lambda: refits() > asked or was != rests, 5)
            return held and refits() == asked + (1 if was == rests else 0)

        home = next(w["name"] for w in json.loads(subprocess.run(["swaymsg", "-t", "get_workspaces"], env=env, capture_output=True, text=True).stdout) if w["focused"])
        move(W // 2, 300)   # the pointer off the pad
        said = state_file.read_text()
        ok(workspace("idle", True), "on the idle screen's workspace the pad is gone and keeps no room: the area runs to sway's gap", (area(), pad_row(), refits()))
        capture("rest")
        ok(state_file.read_text() == said and said.split() == ["hidden", "0", "count", "1"],
           "nothing is stored for it: the pad's state says what it said, not hidden, one window waiting", (said, state_file.read_text()))
        ok(workspace("idler", False), "a workspace whose name only starts alike is no rest: the pad and its strip are there", (area(), pad_row(), refits()))
        ok(workspace("idle HEADLESS-1", True), "the idle screen's workspace of another screen, the name and a space, is a rest too", (area(), pad_row(), refits()))
        shell("desktop", "pad", "keys")   # Super+minus on a screen at rest: no keys there, and none kept for later
        ok(workspace(home, False), "back on its own workspace the pad is back as it was, over its strip", (area(), pad_row(), refits()))
        img = capture("rest-over")
        at = (pad_row() or [((W - one_w) // 2, 0)])[0][0]
        off = edge_off(img, (at, top, one_w, ROW), lit)
        ok(not off and not near(pixel(img, at, top), accent, 6),
           "Super+minus on the screen at rest gave the pad no keys, there or later: its edge is the lit tone, not the accent",
           (off[:4], pixel(img, at, top)))

        # 7. the pad dragged from its icon to the left edge in 2 px steps: one change of shape, from a row to a
        #    column docked there with its strip, and one refit, after the drop (#261, #266)
        img = grab(0, top - 2, W, ROW + 4)
        one_w = LEAD + TOOL + 1 + CTL    # one icon in a row: the grip's room, its cell, hide at its end
        row = [r for r in runs(img, 4, body, 6) if r[1] >= one_w - 2]
        left = row[0][0] if row else (W - one_w) // 2
        cell_x = left + LEAD
        before = refits()
        move(cell_x + TOOL // 2, top + TOOL // 2)
        time.sleep(0.2)
        button(True)
        for i in range(1, 13):   # 6 px with the button held: a drag, not a click
            move(cell_x + TOOL // 2, top + TOOL // 2 - i)
            time.sleep(0.02)
        y = 500
        for i in range(1, 21):
            move(cell_x + TOOL // 2 + (300 - cell_x - TOOL // 2) * i // 20, top + TOOL // 2 - 12 + (y - top - TOOL // 2 + 12) * i // 20)
            time.sleep(0.02)
        widths = []   # the pad's width where it stands, at each step: the longest run of its colors around the pointer
        for x in list(range(300, 0, -2)) + [70]:
            move(x, y)
            time.sleep(0.05)
            widths.append((x, widest(grab(0, y - 40, 640, 80), range(0, 80, 2), body, 6)))
        shapes = ["column" if n <= TOOL + 4 else "row" if n >= one_w - 4 else "?" for _, n in widths]
        steps = shapes[:-1]
        changes = sum(1 for p, q in zip(steps, steps[1:]) if p != q)
        turn = next((x for (x, _), shape in zip(widths, steps) if shape == "column"), None)
        ok(changes == 1 and "?" not in steps and steps[0] == "row",
           "dragged to the left edge in 2 px steps, the pad turns from a row to a column once, as the pointer comes %s px from the edge" % turn,
           [(x, n) for x, n in widths][::6])
        ok(shapes[-1] == "column", "back out to 70 px the column holds the edge: it lets go at 96", widths[-2:])

        def column_top():
            """The dragged column's top edge around the pointer at 70, y, as the screen shows it: the run of the lit
            tone on the row the middle of the grip's room puts it at, and no pad on the row over it."""
            g = grab(0, y - LEAD // 2 - 1, 640, 2)
            return [r for r in runs(g, 1, (lit,), 6) if r[0] <= 70 < r[0] + r[1]], [r for r in runs(g, 0, body, 6) if r[0] <= 70 < r[0] + r[1]]

        settle(lambda: column_top() == ([(70 - TOOL // 2, TOOL)], []), 3)
        ok(column_top() == ([(70 - TOOL // 2, TOOL)], []),
           "the pad that turned a column holds the middle of its grip's room under the pointer: %d px in and %d down" % (TOOL // 2, LEAD // 2),
           (column_top(), (70 - TOOL // 2, y - LEAD // 2)))
        move(2, y)
        time.sleep(0.1)
        during = refits()
        button(False)
        dock = GAP + TOOL + gap
        wait_for(lambda: area()[0] == dock and reaches("bottom"), "the pad docked at the left edge", seconds=8)
        ok(on_pad(b), "a drag from an icon brings no window back")
        ok(True, "dropped at the left edge, it docks there as a column and keeps its strip: the area starts %d px in" % dock)
        img = capture("left")
        column = [r for r in runs_column(img, gap + 3, body, 6) if r[1] >= TOOL]
        col_h = LEAD + TOOL + 1 + CTL    # one icon in a column: the grip's room over its cell, hide under it
        ok(len(column) == 1 and column[0][1] == col_h, "the column's color stands at the left edge: the grip's room, its cell and hide under it, %d px high" % col_h,
           runs_column(img, gap + 3, body, 6)[:6])
        col_top = column[0][0] if column else 0
        held, line = grip_line(img, (gap, col_top, TOOL, LEAD), dim, column=True)
        ok(held, "the grip's line lies across the column's top, %d px in the dim tone in the middle of its room" % (TOOL // 2), line)
        wait_for(lambda: refits() > during, "spark-shell asked after the drop", seconds=5)
        time.sleep(0.6)
        ok(during == before and refits() == before + 1, "spark-shell asked once, after the drop and not during the drag", (before, during, refits()))
        ok(places() and places()[-1][3:5] == ["left", "center"] and len(places()[-1]) == 8,
           "and keeps its place, its widths and its height: desktop pad place PLACE WIDTH SIDE HEIGHT", places()[-1:])

        # 8. Super+minus: the keyboard on the pad, the newest picked; its edge is the accent while it has the keys,
        #    but where the picked cell, lit whole, reaches the pad's sides; Enter brings the window back
        shell("desktop", "pad", "keys")
        settle(lambda: near(pixel(grab(gap, col_top, 1, 1), 0, 0), accent, 6), 5)
        time.sleep(0.5)
        img = capture("keys")
        off = edge_off(img, (gap, col_top, TOOL, col_h), accent)
        picked = [p for p in off if col_top + LEAD <= p[1] < col_top + LEAD + TOOL and near(pixel(img, *p), lit, 6)]
        ok(off == picked and len(off) <= 2 * TOOL and near(pixel(img, gap + 1, col_top + 1), ground, 6),
           "with the keys the pad's edge is the accent, all around but beside the picked cell, lit whole",
           ([p for p in off if p not in picked][:4], len(off), pixel(img, gap, col_top), pixel(img, gap + 1, col_top + 1)))
        held, line = grip_line(img, (gap, col_top, TOOL, LEAD), dim, column=True)
        ok(held, "and its grip keeps the dim tone", line)
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
        four_w = LEAD + 4 * TOOL + 1 + CTL
        settle(lambda: bottom() == row_floor)
        move(W // 2, 300)
        time.sleep(0.8)

        def pad_box(img):
            """The pad at the bottom, as the screen shows it: its left, its top, its width and its height. Its last
            rows read across, under its icons, then the grip's room up to the pad's top."""
            y = H - gap - 3
            row = next((r for r in runs(img, y, body, 6) if r[0] <= W // 2 < r[0] + r[1]), None)
            if not row:
                return None
            col = next((r for r in runs_column(img, row[0] + 2, body, 6, H - 400, H - gap) if r[0] + r[1] == H - gap), None)
            return (row[0], col[0], row[1], col[1]) if col else None

        img = capture("four")
        box = pad_box(img)
        ok(box and abs(box[2] - four_w) <= 1 and box[3] == ROW, "four icons in a row, %d px wide and %d high" % (four_w, ROW), box)
        left, top = (box[0], box[1]) if box else ((W - four_w) // 2, H - gap - ROW)
        drag((left - 3, top - 3), 0, -(TOOL + 4))
        two = 2 * TOOL                   # two rows of icons, the grip's room at their left
        settle(lambda: bottom() == floor - two - gap)
        ok(bottom() == floor - two - gap, "resized from its top left corner to two rows, it keeps a strip as thick: %d px and the gap" % two, (floor - bottom(), area()))
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("two-rows")
        box = pad_box(img)
        two_w = LEAD + 2 * TOOL + 1 + CTL
        ok(box and abs(box[2] - two_w) <= 1 and box[3] == two, "the four in two rows of two, %d by %d px" % (two_w, two), box)
        said = places()[-1] if places() else []
        ok(len(said) == 8 and said[3:5] == ["bottom", "center"] and int(said[7]) >= two,
           "the pad asks spark-shell to keep its height: desktop pad place ... %s" % (said[7] if len(said) == 8 else "?"), said)
        kept = (settings / "config").read_text()
        ok(("WINPAD_HEIGHT=%s" % said[7]) in kept if len(said) == 8 else False, "and spark-shell keeps it, WINPAD_HEIGHT", [ln for ln in kept.splitlines() if ln.startswith("WINPAD_")])

        # 11. shrunk from its left side until the foots fold into one icon, the app with the most windows first
        left, top = (box[0], box[1]) if box else ((W - two_w) // 2, H - gap - two)
        cell_x = left + LEAD             # the cells: past the grip's room, from the pad's top
        no_badge = img   # the four as they are, no group among them: a foot's cell without a badge
        plain = (cell_x, top)
        drag((left - 3, top + TOOL), TOOL - 6, 0)
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("group")
        box = pad_box(img)
        one_w = LEAD + TOOL + 1 + CTL
        ok(box and abs(box[2] - one_w) <= 1 and box[3] == two, "shrunk to one column of two cells, %d by %d px" % (one_w, two), box)
        ok(all(on_pad(c.pid) for c in group), "every window still waits on the pad")
        left, top = (box[0], box[1]) if box else ((W - one_w) // 2, H - gap - two)
        cell_x = left + LEAD

        def badge_at(img, x, y, bare=None):
            """The accent a badge draws at a cell's top right: the pixels at the accent there (its glyph is filled
            with it; an icon's letter stroke drawn soft beside it is not), from past the cell's middle to past its
            right side and from over its top to its middle. Where a picture of the same cell
            without a badge is given, only the pixels that differ from it."""
            got = set()
            for py in range(y - 6, y + TOOL // 2 + 4):
                for px in range(x + TOOL // 2 + 1, x + TOOL + 6):
                    here = pixel(img, px, py)
                    if near(here, accent, 24) and (bare is None or far(here, pixel(bare[0], bare[1] + px - x, bare[2] + py - y)) > 24):
                        got.add((px, py))
            if not got:
                return set()
            lx, ly = min(px for px, _ in got), min(py for _, py in got)
            return {(px - lx, py - ly) for px, py in got}

        three = badge_at(img, cell_x, top, (no_badge, plain[0], plain[1]))
        other = badge_at(img, cell_x, top + TOOL, (no_badge, plain[0], plain[1]))
        # none: a few accent pixels at most, the fringes a font's smoothing puts on an icon's letter (Ubuntu's tile N)
        ok(len(three) >= 20 and len(other) < min(8, len(three) // 4), "the group of three foots wears a badge in the accent at its icon's top right, the other app none (%d px)" % len(three),
           (len(three), len(other)))
        monaspace = has_font("Monaspace Neon") and "monaspace neon" in given.get("WINPAD_FONT", "").lower()
        references = {}
        if monaspace:
            # the glyphs as foot draws them in the pad's font at the badge's size (a quarter over the text's), in the
            # accent on the pad's ground; [colors] is foot's section before 1.25 and [colors-dark] since, so both
            hexes = {"background": given["WINPAD_GROUND"].lstrip("#"), "foreground": given["WINPAD_ACCENT"].lstrip("#")}
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
        drag((left - 3, top + TOOL), -(TOOL + 6), 0)
        move(W // 2, 300)
        time.sleep(0.8)
        img = capture("ungrouped")
        box = pad_box(img)
        ok(box and abs(box[2] - two_w) <= 1 and box[3] == two and not badge_at(img, box[0] + LEAD, box[1], (no_badge, plain[0], plain[1])),
           "widened again to two columns, the group opens back into its four icons, no badge", box)
        left, top = (box[0], box[1]) if box else ((W - two_w) // 2, H - gap - two)
        drag((left - 3, top + TOOL), TOOL - 6, 0)
        move(W // 2, 300)
        time.sleep(0.8)
        box = pad_box(capture("group-again"))
        left, top = (box[0], box[1]) if box else ((W - one_w) // 2, H - gap - two)
        cell_x = left + LEAD

        # 13. a click on the group opens its list over it, at its cell, a row a window, the oldest first; a click on a
        #     row brings it back
        click(cell_x + TOOL // 2, top + TOOL // 2)
        time.sleep(0.6)
        img = capture("list")
        rows = 3
        list_top = top - 6 - rows * m["tip"]
        column = [r for r in runs_column(img, cell_x + 3, (surface, lit), 6, top - 200, top) if r[1] >= rows * m["tip"]]
        ok(column and abs(column[-1][0] - list_top) <= 2 and column[-1][0] + column[-1][1] <= top - 4,
           "the group's list stands over it, %d rows of %d px" % (rows, m["tip"]), runs_column(img, cell_x + 3, (surface, lit), 6, top - 200, top)[-3:])
        list_top = column[-1][0] + 1 if column else list_top
        across = [r for r in runs(img, list_top + 2, (surface, lit), 6) if r[0] <= cell_x + 3 < r[0] + r[1]]
        list_w = across[0][1] - 2 if across else 160
        said = [words_in(img, (cell_x + 4, list_top + i * m["tip"] + 1, list_w - 8, m["tip"] - 2), surface if i < rows - 1 else lit, fg) for i in range(rows)]
        ok(all(p is not None and p[0]["text"] >= 4 and p[1]["width"] > p[0]["width"] for p in said),
           "each row says a window's words, the app's name and its title", said)
        click(cell_x + 60, list_top + m["tip"] // 2)
        wait_for(lambda: not on_pad(g1.pid), "the first foot back from the list")
        ok(all(on_pad(c.pid) for c in (notes, g2, g3)), "a click on the list's first row brings the oldest foot back, and that one alone")
        time.sleep(0.6)
        move(W // 2, 300)
        time.sleep(0.6)
        img = capture("group-of-two")
        box = pad_box(img)
        # notes first now: the group of the two foots left stands where the older of them does, the second cell
        two_left = badge_at(img, box[0] + LEAD, box[1] + TOOL, (no_badge, plain[0], plain[1])) if box else set()
        ok(box and len(two_left) >= 20 and len(badge_at(img, box[0] + LEAD, box[1], (no_badge, plain[0], plain[1]))) < min(8, len(two_left) // 4),
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

        # 15. the band on, and the bar at the bottom (a new bar, before the pad): the pad over the bar, the band's
        #     color across the row's top and the grip's room under it, a strip of both inside the bar's zone, and
        #     the bar where it was
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
        band_floor = edge - gap - BAND - TOOL - GAP
        settle(lambda: bottom() == band_floor)
        ok(bottom() == band_floor, "with the band on (%s) the strip is the band and the row, %d px, and the gap%s"
           % (said, BAND + TOOL, ", over the bar" if bar else ""), (edge, area()))
        move(W // 2, 200)
        time.sleep(0.6)
        img = capture("band")
        band_y = edge - gap - TOOL - BAND   # the pad's top: the band, the row under it
        # the band's own color on its first row inside the edge, over its word: from the pad's left to its right
        top_runs = [r for r in runs(img, band_y + 1, (band,), 6) if r[0] <= W // 2 < r[0] + r[1]]
        left = top_runs[0][0] - 1 if top_runs else (W - want_w) // 2
        down = runs_column(img, left + 3, (band,), 6, band_y, band_y + BAND + TOOL)
        off = edge_off(img, (left, band_y, want_w, BAND + TOOL), lit)
        ok(top_runs and abs(top_runs[0][1] + 2 - want_w) <= 1 and down == [(band_y + 1, BAND - 1)] and not off
           and near(pixel(img, left + 3, band_y + BAND + 2), ground, 6),
           "the band's color stands across the pad's top inside its edge, %d px over its row" % BAND, (top_runs, down, off[:4], pixel(img, W // 2, band_y)))
        held, line = grip_line(img, (left, band_y + BAND, LEAD, TOOL), dim)
        ok(held, "the grip's room is under the band, at the row's left: its line stands in the middle of it", line)
        if bar:
            # had the strip taken the screen's edge, the bar would stand over the pad and the pad's colors under it
            under = [(x, y) for x in range(W // 2 - 40, W // 2 + 40, 4) for y in range(edge, H, 2)
                     if any(near(pixel(img, x, y), c, 6) for c in (band, ground, lit))]
            ok(not under and pixel(img, W // 2, edge + 1) == pixel(before_bar, W // 2, edge + 1),
               "the bar stays where it was, under the pad", (under[:4], pixel(img, W // 2, edge + 1), pixel(before_bar, W // 2, edge + 1)))
        click(left + LEAD + TOOL // 2, edge - gap - TOOL // 2)
        wait_for(lambda: not on_pad(a), "the first window back from the banded pad")
        ok(True, "a click on its icon brings it back")

        # 16. the titled view: a slot a window, its words as the dialog's, the edge and the grip as on the icons
        shell("desktop", "pad", "band", "off")
        said = shell("desktop", "pad", "view", "titles")
        wait_for(lambda: handed_env().get("WINPAD_VIEW") == "titles" and pad_pid(), "the pad again in the titled view (%s)" % said)
        subprocess.run(["swaymsg", "[pid=%d] focus" % a], env=env, capture_output=True)
        shell("desktop", "window", "down")
        wait_for(lambda: on_pad(a), "the first window on the titled pad")
        titled = CELL                    # a titled row: as high as a slot, the grip's room at its left
        settle(lambda: bottom() == edge - gap - titled - GAP)
        ok(bottom() == edge - gap - titled - GAP, "titles (%s): a strip of a titled row, %d px, and the gap" % (said, titled), (edge, area()))
        move(W // 2, 200)
        time.sleep(0.8)
        img = capture("titles")
        top = edge - gap - titled
        titled_w = LEAD + 2 * SLOT + 1 + CTL
        row = [r for r in runs(img, top + 3, body, 6) if r[1] >= 2 * SLOT]
        ok(len(row) == 1 and abs(row[0][1] - titled_w) <= 1, "the grip's room, two titled slots of %d px and hide's, %d px wide" % (SLOT, titled_w),
           runs(img, top + 3, body, 6)[:6])
        left = row[0][0] if row else (W - titled_w) // 2
        cell_x = left + LEAD
        off = edge_off(img, (left, top, titled_w, titled), lit)
        held, line = grip_line(img, (left, top, LEAD, titled), dim)
        ok(not off and held and near(pixel(img, left + 1, top + 1), ground, 6),
           "the titled pad has the edge all around and the grip in its room too", (off[:4], line, pixel(img, left + 1, top + 1)))
        # the order on the pad: b went first, then a; the slot's words between the pad's edges
        parts = words_in(img, (cell_x + text_dx, top + 1, text_w, CELL - 2), ground, fg, muted)
        # a palette whose muted color reads at 4.5 to 1 only as the text color (solarized-light) has the two alike
        apart = far(fg, muted) > 24
        ok(parts is not None and parts[0]["text"] >= 4 and parts[1]["muted"] >= 4 and (parts[1]["text"] == 0 or not apart),
           "a slot reads its app's name in the text color, then its title, muted%s" % ("" if apart else " (the palette's muted is its text color)"), parts)
        ok(parts is not None and lowercase(*parts), "the title lowercase, as the dialog writes it (OCEAN as ocean: %s px tall to foot's %s)"
           % ((parts[1]["height"], parts[0]["height"]) if parts else ("?", "?")), parts)
        click(cell_x + SLOT // 2, top + CELL // 2)
        wait_for(lambda: not on_pad(b), "the window back from the titled pad")
        move(W // 2, 200)
        time.sleep(0.8)
        row = [r for r in runs(grab(0, top + 3, W, 1), 0, body, 6) if r[1] >= SLOT]
        left = row[0][0] if row else (W - LEAD - SLOT - 1 - CTL) // 2
        click(left + LEAD + SLOT // 2, top + CELL // 2)
        ok(wait_for(lambda: pad_empty() and bottom() == edge - GAP, "the pad with no window", seconds=10), "a click on its slot brings it back, and the pad's surfaces go")

        # 17. the dialog on the pad (v0.134.3): a foot whose app id is spark-dialog, as the dialog's window, wears
        #     spark's own mark, the diamond in the chevron of the assets beside spark-shell (v0.148), in one ink:
        #     the light one (#e9e7dc) on a dark ground, the dark one (#080a0f) on a light one, never recolored.
        #     Its words are spark, then its title: the same pixels as a window whose app is named spark with that
        #     title, whose icon, the letter tile, holds none of that ink: the mark is the dialog's alone
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
        row = [r for r in runs(img, top + 3, body, 6) if r[1] >= 2 * SLOT]
        left = row[0][0] if row else (W - titled_w) // 2
        cell_x = left + LEAD
        stands_on = pixel(img, cell_x + SLOT // 2, top + 2)   # the ground the mark stands on, as the screen shows it
        dark = (stands_on[0] * 299 + stands_on[1] * 587 + stands_on[2] * 114) // 1000 < 128
        ink = rgb("e9e7dc" if dark else "080a0f")
        icon = m["icon"]

        def inks(box, color, tolerance):
            x0, y0, w, h = box
            return sum(1 for y in range(y0, y0 + h) for x in range(x0, x0 + w) if near(pixel(img, x, y), color, tolerance))

        def icon_box(x, y):
            return (x - 2, y - 2, icon + 4, icon + 4)

        def the_mark(box):
            """The mark's ink in a box, a count of pixels: its two solid shapes fill a good part of an icon."""
            return inks(box, ink, 24)

        def reads_mark(found):
            return found >= 24

        titled_icon = icon_box(cell_x + inset, top + (CELL - icon) // 2)
        twin_icon = icon_box(cell_x + SLOT + inset, top + (CELL - icon) // 2)
        found, twin_found = the_mark(titled_icon), the_mark(twin_icon)
        ok(reads_mark(found), "the dialog's icon is spark's mark for a %s ground, in its own ink #%02x%02x%02x: %d pixels of it"
           % (("dark" if dark else "light",) + ink + (found,)), found)
        ok(twin_found == 0, "the window named spark beside it holds none of that ink: the mark is the dialog's", twin_found)
        words = [mask(img, (cell_x + i * SLOT + text_dx, top + 2, text_w, CELL - 4), fg, 60) for i in (0, 1)]
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
        row = [r for r in runs(img, top + 2, body, 6) if r[1] >= 2 * TOOL]
        left = row[0][0] if row else (W - want_w) // 2
        cell_icon = icon_box(left + LEAD + (TOOL - icon) // 2, top + (TOOL - icon) // 2)
        found = the_mark(cell_icon)
        ok(reads_mark(found), "and in the icons view, the default, its cell is the same mark: %d pixels of its ink" % found, found)
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
