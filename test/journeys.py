#!/usr/bin/env python3
"""journeys.py NAME TREE OUT [dialog=FILE] [bar=FILE] [winpad=FILE] [wallpaper=FILE] -- one journey through the
desktop TREE makes (test/desk.py's Desktop), with the invariants held after each step.

The last line is the verdict: GREEN, RED and what broke, or NOT-RUN and what could not be arranged. A journey stays
when it is red on a release that had a bug and green on the fix (test/replay.py), and green run after run under load.
It says nothing of words, glyphs, colors, times or order: what stands, what is seen, what runs.
"""
from pathlib import Path
import os
import shutil
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from desk import Broken, Desktop, NotRun, fenced  # noqa: E402


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


def loops(d):
    """A theme with loops of its own: they move, after the theme and after a reload. A player started anew over a
    still takes some seconds: it must come to move, and move on."""
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
    if d.sway("reload").returncode:   # no ground here: the loops stand on the background
        raise Broken("sway refused its reload")
    time.sleep(2)
    moves("after a reload")


SCREENS = {"home": ((1280, 720, "normal"),), "loops": ((1080, 1920, "90"), (1280, 720, "normal"))}   # two screens: one alone keeps no loop through a reload yet
KEYS = {"matrix": {"BAR_TRAY": "yes"}}
JOURNEYS = {f.__name__: f for f in (home, live, matrix, loops)}


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
