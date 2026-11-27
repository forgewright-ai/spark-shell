#!/usr/bin/env python3
"""journeys.py NAME TREE OUT [dialog=FILE] [bar=FILE] [winpad=FILE] [wallpaper=FILE] -- one journey through the
desktop TREE makes (test/desk.py's Desktop), with the invariants held after each step.

The last line is the verdict: GREEN, RED and what broke, or NOT-RUN and what could not be arranged. A journey stays
when it is red on a release that had a bug and green on the fix (test/replay.py), and green run after run under load.
It says nothing of words, glyphs, colors, times or order: what stands, what is seen, what runs.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from desk import GROUND, Broken, Desktop, NotRun, Pointer, fenced  # noqa: E402


def open_home(d, workspace):
    d.sway("workspace %s" % workspace)
    time.sleep(0.5)
    d.shell("desktop", "home")
    w = d.until(d.dialog, "home's window")
    exe = os.path.basename(os.readlink("/proc/%d/exe" % w["pid"]))
    if exe != "spark-dialog":
        raise NotRun("home's window is %s's" % exe)
    d.alone()
    d.home_seen()


def go(d, *sections):
    """Home to another place: its window's title changes, as it does under a person's hand."""
    was = (d.dialog() or {}).get("name")
    for section in sections:
        d.shell("desktop", "home", section)
        end = time.monotonic() + 6
        while time.monotonic() < end:
            if (d.dialog() or {}).get("name") not in (None, was):
                return
            time.sleep(0.2)
    raise NotRun("home went to none of %s (its title stayed %r)" % (", ".join(sections), was))


def home(d):
    """Home opened, moved through, reloaded under and re-themed: it is seen while it has the keys."""
    open_home(d, "5")
    go(d, "files", "notes")
    d.home_seen()
    d.reload()
    go(d, "theme", "sound")
    d.home_seen()
    d.shell("theme", "tokyonight-night")
    d.ground()
    d.home_seen()
    d.whole()


def live(d):
    """The desktop changed while it runs: each change leaves it as a login would make it, so a reload is nothing."""
    d.whole()
    d.reload_is_nothing()
    d.sway("workspace 1")
    for _ in range(2):
        d.sway("exec foot --app-id desk-window")
    d.until(lambda: sum(w.get("app_id") == "desk-window" for w in d.windows()) == 2, "two windows")
    for verb in (("bar", "text", "20"), ("bar", "text", "12"), ("theme", "gruvbox-dark"), ("theme", "nord"),
                 ("bar", "bottom"), ("bar", "top")):
        d.shell(*verb)
        d.ground()
        d.whole()
        d.reload_is_nothing()
        d.whole()
    if len(d.msg("-t", "get_outputs")) > 1:   # the move keys are judged on two screens: a desk of one ends here
        moves(d)


def moves(d):
    """The move keys on two screens: a window moved one way again and again stays in sight, one sent to the other
    screen is whole on it, its title too, and has the keyboard, so the next key is its own."""
    screens = sorted((o["rect"] for o in d.msg("-t", "get_outputs")), key=lambda r: r["x"])
    if len(screens) < 2:
        raise NotRun("the move keys are judged on two screens")

    def one():
        return next((w for w in d.windows() if w.get("app_id") == "desk-move"), None)

    def box():
        r, band = one()["rect"], one().get("deco_rect", {}).get("height", 0)
        return r["x"], r["y"] - band, r["x"] + r["width"], r["y"] + r["height"]

    def on(screen):
        x, y, right, bottom = box()
        return screen["x"] <= x and screen["y"] <= y and right <= screen["x"] + screen["width"] and bottom <= screen["y"] + screen["height"]

    def move(way, what):
        d.shell("desktop", "window", "move", way)
        time.sleep(0.4)
        if not one():
            raise Broken("%s is gone" % what)

    d.sway("focus output %s" % next(o["name"] for o in d.msg("-t", "get_outputs") if o["rect"] == screens[0]))
    d.sway("workspace 7")
    d.sway("exec foot --app-id desk-move")
    d.until(one, "a window")
    time.sleep(0.8)
    d.shell("desktop", "window", "float")   # free, on the screen at the left: no screen is left of it
    d.until(lambda: one()["type"] == "floating_con" and on(screens[0]), "a free window on the left screen")
    for _ in range(12):
        move("left", "a free window moved left")
    if not on(screens[0]):
        raise Broken("a free window moved left again and again left its screen: its box is %s" % (box(),))
    move("right", "a free window sent to the next screen")
    d.until(lambda: box()[0] >= screens[1]["x"], "the free window on the right screen", 10, Broken)
    time.sleep(0.6)
    if not on(screens[1]):
        raise Broken("a free window sent to a smaller screen is not whole on it: its box is %s" % (box(),))
    if not one().get("focused"):
        raise Broken("a free window sent to the next screen left the keyboard behind")
    d.shell("desktop", "window", "left")    # at a place now: the left half of the right screen
    time.sleep(0.4)
    move("left", "a placed window sent to the next screen")
    d.until(lambda: box()[2] <= screens[0]["x"] + screens[0]["width"], "the placed window on the left screen", 10, Broken)
    time.sleep(0.6)
    if not one().get("focused"):
        raise Broken("a placed window sent to the next screen left the keyboard behind")
    was = box()
    d.shell("desktop", "window", "down")    # the next key is its own: it is the window that takes it
    time.sleep(0.6)
    if box() == was or not on(screens[0]):
        raise Broken("the key after a move to the next screen did not reach the window moved")
    d.sway('[app_id="desk-move"] kill')


def matrix(d):
    """A narrow turned screen, the tray on, the text grown step by step: a window put on the pad takes no room there
    and is not lost, and the desk is as a login would make it."""
    narrow = "HEADLESS-1"
    d.sway("workspace 3 output %s" % narrow)
    d.sway("focus output %s" % narrow)
    d.sway("workspace 3")
    for _ in range(2):
        d.sway("exec foot --app-id desk-window")
    d.until(lambda: sum(w.get("app_id") == "desk-window" for w in d.windows()) == 2, "two windows")
    here = [w for w in d.windows() if w.get("app_id") == "desk-window"]
    rect = next(o["rect"] for o in d.msg("-t", "get_outputs") if o["name"] == narrow)
    if not all(rect["x"] <= w["rect"]["x"] < rect["x"] + rect["width"] for w in here):
        raise NotRun("the windows did not open on the narrow screen")
    for size in ("12", "14", "16", "20", "24"):
        d.shell("bar", "text", size)
        d.ground()
        ids, areas = {w["id"] for w in d.windows()}, d.quiet()["areas"]
        d.sway("[con_id=%d] focus" % here[0]["id"])
        d.shell("desktop", "window", "min")
        one = lambda: next((w for w in d.windows() if w["id"] == here[0]["id"]), None)   # noqa: E731
        d.until(lambda: one() and not one().get("visible"), "the window on the pad")
        if len(d.census()["spark-winpad"]) != 1:
            raise Broken("%d spark-winpad run with a window on the pad" % len(d.census()["spark-winpad"]))
        time.sleep(1.5)
        try:
            d.holds(lambda: d.snapshot()["areas"] == areas, "the windows' area as it was")
        except Broken:
            raise Broken("a window put on the pad changed the windows' area at text %s: %s -> %s" % (size, areas, d.snapshot()["areas"]))
        if {w["id"] for w in d.windows()} != ids:
            raise Broken("a window put on the pad is lost")
        for _ in range(3):   # Super+minus and Enter, a person's way back; a pad not ready yet is asked again
            d.shell("desktop", "pad", "keys")
            time.sleep(1)
            d.key("-k", "Return")
            end = time.monotonic() + 8
            while time.monotonic() < end and not (one() or {}).get("visible"):
                time.sleep(0.3)
            if (one() or {}).get("visible"):
                break
        else:
            raise NotRun("the window did not come back from the pad")
    d.whole()
    tabs(d)


def tabs(d):
    """A window in a tab and two side by side in the next: a click on a close button closes the window it is drawn on,
    and one in a window's own text closes none, whatever stands behind it."""
    outs = [o["rect"] for o in d.msg("-t", "get_outputs")]
    wide, high = max(r["x"] + r["width"] for r in outs), max(r["y"] + r["height"] for r in outs)
    pointer = Pointer(d.env)

    def click(x, y):
        pointer.click(round(x * 1440 / wide), round(y * 1000 / high))   # its own space over every screen

    def here():
        return {w["app_id"]: w for w in d.windows() if (w.get("app_id") or "").startswith("desk-tab")}

    def foot(name):
        d.sway("exec foot --app-id desk-tab%s" % name)
        d.until(lambda: "desk-tab" + name in here(), "window %s" % name)
        time.sleep(0.8)   # the keys on it, before the next word to sway
    d.sway("workspace 6")
    foot("a")
    d.sway("splith")
    d.sway("layout tabbed")
    foot("b")
    d.sway("splith")
    foot("c")
    w = here()
    if w["desk-tabb"]["rect"]["y"] != w["desk-tabc"]["rect"]["y"] or w["desk-tabb"].get("visible") is not True or w["desk-taba"].get("visible") is not False:
        raise NotRun("sway did not lay the windows in a tab and a group")
    for _ in range(3):   # the pad's buttons follow the tree: one not there yet is asked again
        rect = w["desk-tabb"]["rect"]
        click(rect["x"] + 26, rect["y"] - w["desk-tabb"]["deco_rect"]["height"] / 2)   # a title stands right over its window
        end = time.monotonic() + 5
        while time.monotonic() < end and "desk-tabb" in here():
            time.sleep(0.2)
        if "desk-tabb" not in here():
            break
    else:
        raise Broken("a click on the close button of a window in a tab's group does nothing")
    foot("b")
    d.sway('[app_id="desk-taba"] focus')
    d.until(lambda: here()["desk-taba"].get("visible") and not here()["desk-tabb"].get("visible"), "the group behind its tab")
    time.sleep(1.5)
    rect, left = here()["desk-taba"]["rect"], set(here())
    for down in (14, 42, 70):
        click(rect["x"] + 26, rect["y"] + down)
        time.sleep(1.5)
        if set(here()) != left:
            raise Broken("a click in a window's text closed %s behind it" % ", ".join(left - set(here())))
    pointer.close()


def loops(d):
    """A theme with loops of its own: they move, after the theme and after a reload, on two screens and on one. A player
    started anew over a still takes some seconds: it must come to move, and move on."""
    def moving():
        players = d.census()["spark-wallpaper"]
        if len(players) != 1:
            return False

        def ticks():
            f = Path("/proc/%d/stat" % players[0][0]).read_text().rsplit(")", 1)[1].split()
            return int(f[11]) + int(f[12])
        try:
            a = ticks()
            time.sleep(2)
            return ticks() - a > 4
        except OSError:   # ended between the looks
            return False

    def moves(when):
        d.until(moving, "the loops move %s" % when, 40, Broken)
        time.sleep(5)
        d.until(moving, "the loops move on %s" % when, 15, Broken)
    d.shell("theme", "atlas-awakening", seconds=180)
    d.shell("theme", "motion", "on")
    d.until(lambda: d.census()["spark-wallpaper"], "a player", 40)
    moves("after the theme")
    turned, wide = (o["name"] for o in sorted(d.msg("-t", "get_outputs"), key=lambda o: o["transform"] == "normal"))
    for where in ("two screens", "one screen"):
        if where == "one screen":   # the wide one alone: no screen's own still starts the drawer then
            d.sway("output %s unplug" % turned)   # for good: a reload turns a disabled one on again
            d.until(lambda: [o["name"] for o in d.msg("-t", "get_outputs") if o["active"]] == [wide], "one screen")
            time.sleep(2)
            moves("on one screen")
        if d.sway("reload").returncode:   # no ground here: the loops stand on the background
            raise Broken("sway refused its reload")
        time.sleep(2)
        moves("after a reload, %s" % where)
    d.shell("theme", "none", seconds=60)   # another look, and this one back: its loops are in the cache, so they start before the drawer does
    d.shell("theme", "atlas-awakening", seconds=60)
    d.until(lambda: d.census()["spark-wallpaper"], "a player again", 40)
    moves("after the theme again, one screen")


def notifications(d):
    """A program's notification is kept and shown by the bar; a click reaches the program that sent it and the keys
    dismiss; do not disturb keeps one out of sight and lets a critical one through; the server gone, the session bus
    starts spark-shell's own again, whatever other notification program this machine has; one of each program all along."""
    file = d.run / "spark-shell-notifications.state"
    width, height = d.screens[0][0], d.screens[0][1]

    def state():
        try:
            return json.loads(file.read_text())
        except (OSError, ValueError):
            return {}

    def shown():
        return [n["summary"] for n in state().get("shown", [])]

    def send(*words):
        got = d.sh("notify-send", *words, seconds=20)
        if got.returncode:
            raise NotRun("notify-send said %d: %s" % (got.returncode, got.stderr.strip()[:80]))

    def stack():
        """The box something is drawn in on the right of the screen, under the bar; None when the ground is plain there."""
        side = 420
        px = d.grab(width - side, 0, side, height)
        rows = [y for y in range(0, height, 2) if any(tuple(px[(y * side + x) * 3:(y * side + x) * 3 + 3]) != GROUND for x in range(0, side, 6))]
        while rows and rows[0] == 0:   # the bar, at the top
            last = rows.pop(0)
            while rows and rows[0] == last + 2:
                last = rows.pop(0)
        while rows and rows[-1] >= height - 2:   # or at the bottom
            last = rows.pop()
            while rows and rows[-1] == last - 2:
                last = rows.pop()
        if not rows:
            return None
        cols = [x for x in range(0, side, 2) if tuple(px[(rows[0] * side + x) * 3:(rows[0] * side + x) * 3 + 3]) != GROUND]
        return (width - side + cols[0], rows[0], width - side + cols[-1], rows[-1]) if cols else None

    d.until(lambda: state().get("drawer"), "the notifications' server and its drawer, started at login", 40)
    d.whole()
    send("-a", "mail", "one", "kept")
    send("-u", "critical", "-a", "power", "two", "stays")
    said = d.out / "action.txt"
    with open(str(said), "w") as out:
        d.procs.append(subprocess.Popen(["notify-send", "-a", "chat", "-A", "default=Open", "three", "asks"], env=d.env, cwd=str(d.home), stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.DEVNULL))
    d.until(lambda: shown() == ["three", "two", "one"], "three on the screen, the newest first", 20, Broken)
    box = d.until(stack, "the notifications drawn by the bar", 15, Broken)
    time.sleep(0.6)
    d.sh("grim", str(d.out / "stack.png"), seconds=20)   # for a look: the stack closed
    if state().get("unseen") != 3:
        raise Broken("three came and nobody looked: the count says %s" % state().get("unseen"))
    # a click on the newest: what its program offered reaches that program, and the card leaves
    pointer = Pointer(d.env)
    pointer.click(round((box[0] + 60) * 1440 / width), round((box[1] + 16) * 1000 / height))
    d.until(lambda: said.read_text().strip() == "default", "the click to reach the program that sent it", 15, Broken)
    d.until(lambda: shown() == ["two", "one"], "the clicked one to leave the screen", 10, Broken)
    pointer.close()
    # the keys: Super+n's verb opens the stack, Delete sends the chosen one away
    d.shell("desktop", "notifications", "open")
    time.sleep(1)
    d.sh("grim", str(d.out / "open.png"), seconds=20)   # and open, under the keys
    d.sh("wtype", "-k", "Delete")
    d.until(lambda: shown() == ["one"], "Delete to dismiss the one the keys are on", 10, Broken)
    d.sh("wtype", "-k", "Escape")
    d.shell("desktop", "notifications", "dismiss")
    d.until(lambda: shown() == [] and stack() is None, "the screen clear after dismiss", 15, Broken)
    if state().get("unseen") != 0:
        raise Broken("each was sent away by hand, and the count still says %s" % state().get("unseen"))
    # do not disturb: one waits in the list, unseen and undrawn; a critical one shows
    d.shell("desktop", "notifications", "do-not-disturb", "on")
    send("-a", "mail", "quiet", "waits")
    d.until(lambda: [n["summary"] for n in state().get("history", [])][:1] == ["quiet"] and state().get("unseen") == 1, "the quiet one in the list", 10, Broken)
    time.sleep(1)
    if shown() or stack():
        raise Broken("do not disturb is on and a notification shows")
    send("-u", "critical", "-a", "power", "loud", "shows")
    d.until(lambda: shown() == ["loud"] and stack(), "a critical one through do not disturb", 15, Broken)
    d.shell("desktop", "notifications", "do-not-disturb", "off")
    d.shell("desktop", "notifications", "dismiss")
    d.whole()
    # the server ended: the bus starts spark-shell's own at the next notification, by the service file on desktop rendered
    pid = state().get("pid")
    os.kill(pid, 15)
    d.until(lambda: state().get("pid") is None and state().get("last"), "the ended server's state file to name no server, and keep its newest id", 10)
    send("-a", "mail", "again", "after the server's end")
    d.until(lambda: state().get("pid") not in (None, pid) and shown() == ["again"], "the bus to start the server again", 40, Broken)
    d.until(lambda: state().get("drawer") and stack(), "its drawer, in the session's own environment", 20, Broken)
    d.shell("desktop", "notifications", "dismiss")
    d.whole()


def arrange(d):
    """The bar's status arranged while the desktop runs (v0.171): a module moved in its group, a gauge taken off, a
    module hidden and the shipped order back are each kept in the config, drawn by the bar and leave the desktop as a
    login would make it, so a reload is nothing; home's bar section, a row for each module, is seen; and an undo puts
    the four lines of the config back as they were, and the bar with them."""
    config = d.home / ".config" / "spark-shell" / "config"
    state = d.run / "spark-shell-bar.state"

    def kept():
        return sorted(line for line in config.read_text().splitlines() if line.startswith(("BAR_ORDER=", "BAR_HIDE=", "BAR_PINS=", "BAR_GAUGES=")))

    def parts():
        """The parts of the status's modules as spark's bar has drawn them, left to right: MODULE.PART, from its state file."""
        at = {}
        try:
            lines = state.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return []
        for f in (line.split("\t") for line in lines):
            if f[0] == "target" and len(f) == 11 and "." in f[2] and f[3].isdigit():
                at.setdefault(f[2], int(f[3]))
        return sorted(at, key=at.get)

    def drawn(test, what):
        """The bar once it shows `what`: a change is in its next line, so a bar that never shows it reads no arrangement."""
        end = time.monotonic() + 30
        while time.monotonic() < end:
            try:
                if test(parts()):
                    return
            except ValueError:   # a part the test names is not drawn yet
                pass
            time.sleep(0.2)
        raise Broken("the bar did not come to show %s; it shows %s" % (what, " ".join(parts())))

    d.whole()
    drawn(lambda p: p.index("out.name") < p.index("mic.name"), "the volume before the microphone, the shipped order")
    for verb, test, what in (
            (("bar", "move", "mic", "before", "out"), lambda p: p.index("mic.name") < p.index("out.name"), "the microphone before the volume"),
            (("bar", "gauge", "out", "off"), lambda p: "out.name" in p and "out.gauge" not in p, "the volume with no gauge"),
            (("bar", "hide", "mic"), lambda p: "out.name" in p and "mic.name" not in p, "no microphone"),
            (("bar", "move", "default"), lambda p: "out.name" in p and "mic.name" not in p, "the shipped order, the microphone still hidden")):
        was = kept()
        d.shell(*verb)
        if kept() == was:
            raise Broken("spark-shell %s was done and the config says what it said before" % " ".join(verb))
        drawn(test, what)
        d.whole()
        d.reload_is_nothing()
    if "BAR_ORDER=pad due media lan bt wifi out mic light kb bat" not in kept():
        raise Broken("the shipped order was asked for and the config has %s" % kept())
    open_home(d, "5")
    go(d, "bar", "bar")
    d.home_seen()
    was = kept()
    d.shell("bar", "show", "mic")
    if kept() == was:
        raise Broken("the hidden module was shown and the config says what it said before")
    drawn(lambda p: p.index("out.name") < p.index("mic.name"), "the microphone again, after the volume")
    d.shell("bar", "panel", "undo", "all")
    if kept() != was:
        raise Broken("the undo left the config with %s, and before the step it had %s" % (kept(), was))
    drawn(lambda p: "out.name" in p and "mic.name" not in p, "no microphone again, after the undo")
    d.home_seen()
    d.whole()
    d.reload_is_nothing()


SCREENS = {"home": ((1280, 720, "normal"),), "loops": ((1080, 1920, "90"), (1280, 720, "normal")), "notifications": ((1280, 720, "normal"),),
           "arrange": ((1280, 720, "normal"),)}
KEYS = {"matrix": {"BAR_TRAY": "yes"}}
JOURNEYS = {f.__name__: f for f in (home, live, moves, matrix, tabs, loops, notifications, arrange)}


MARK = ".spark-shell-journey"


def main():
    fenced(whole=True)
    name, tree, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    builds = dict(a.split("=", 1) for a in sys.argv[4:])
    if out.exists() and any(out.iterdir()):
        if not (out / MARK).exists():
            sys.exit("journeys.py: %s is there and is no folder of a journey: not touched" % out)
        shutil.rmtree(str(out))
    out.mkdir(parents=True, exist_ok=True)
    (out / MARK).write_text("")
    lacks = [part for part in ("dialog", "bar", "winpad") + (("wallpaper",) if name == "loops" else ()) if not os.access(builds.get(part, ""), os.X_OK)]
    word, d = "NOT-RUN no build of %s" % ", ".join(lacks), None
    try:
        if not lacks:
            more = {"screens": SCREENS[name]} if name in SCREENS else {}
            d = Desktop(tree, builds, out, config=KEYS.get(name, {}), **more)
            d.start()
            JOURNEYS[name](d)
            word = "GREEN"
    except Broken as why:
        word = "RED %s" % why
    except NotRun as why:
        word = "NOT-RUN %s" % why
    except Exception as why:   # the harness itself: no word on the program
        word = "NOT-RUN %s: %s" % (type(why).__name__, why)
    finally:
        if d:
            (out / "said.txt").write_text("\n".join(d.said + [word]) + "\n")
            if shutil.which("grim"):
                d.sh("grim", str(out / "last.png"), seconds=20)
            d.stop()
    print(word)
    return {"G": 0, "R": 1, "N": 3}[word[0]]


if __name__ == "__main__":
    sys.exit(main())
