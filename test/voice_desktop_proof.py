#!/usr/bin/env python3
"""Voice on a real sway, headless: a stand-in engine that speaks the ear's contract, its words typed into
the window that has the focus, and the mic on every title band, in its own color, with the bars while it
listens. The voice is a window's capability, like its buttons: what the words mean is the window's own affair.

python3 test/voice_desktop_proof.py [EVIDENCE_DIRECTORY]. A throwaway HOME and a sway of its own.
SPARK_SHELL_WINPAD names the pad's build, which draws the mic. Needs sway, swaymsg, foot, grim, wtype, python3."""

import collections
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent
failed = 0


def ok(cond, what, detail=""):
    global failed
    print("  %s   %s" % ("ok" if cond else "FAIL", what) + ("" if cond else "   %s" % (detail,)))
    if not cond:
        failed += 1


def wait_for(read, what, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        value = read()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("waited %ds for %s" % (seconds, what))


def glyphs(env, box):
    """The ink of a box of the screen, in clusters a blank column apart: (x, width, pixels, average) each.

    The ink is every pixel away from the box's own background, so it reads the same on any palette, over a
    focused band or an unfocused one."""
    x, y, w, h = box
    raw = subprocess.run(["grim", "-t", "ppm", "-g", "%d,%d %dx%d" % box, "-"], env=env, capture_output=True, check=True).stdout
    data = raw.split(b"\n", 3)[3]
    pixel = lambda cx, cy: tuple(data[3 * (cy * w + cx):3 * (cy * w + cx) + 3])   # noqa: E731
    ground = collections.Counter(pixel(cx, cy) for cy in range(h) for cx in range(w)).most_common(1)[0][0]
    far = lambda p: sum(abs(a - b) for a, b in zip(p, ground)) > 90   # noqa: E731
    columns = [[pixel(cx, cy) for cy in range(h) if far(pixel(cx, cy))] for cx in range(w)]
    out, run, blanks, at = [], [], 0, 0
    for cx, ink in enumerate(columns + [[]] * 4):
        if ink:
            if not run:
                at = cx
            run.append(ink)
            blanks = 0
        else:
            blanks += 1
            if run and blanks >= 4:
                flat = [p for col in run for p in col]
                out.append((at, len(run), len(flat), tuple(sum(c[i] for c in flat) // len(flat) for i in range(3))))
                run = []
    return out


def band_glyphs(all_ink):
    """A band's parts: the single characters (the buttons and the mic) and what follows them (the bars, the title)."""
    marks = [c for c in all_ink if c[1] <= 14]
    rest = [c for c in all_ink if c[1] > 14]
    return marks, rest


STUB = """#!/bin/sh
# the ear's contract, by a stand-in: a level ten times a second, the words in pieces, then the leash's end
say() { echo "$1"; sleep 0.1; }
exec 9<&0   # the leash kept on a fd of its own: a backgrounded subshell is handed /dev/null for stdin
( cat <&9 > /dev/null; kill -TERM $$ ) &   # its end ends the engine, as the ear's contract says
say 'level 3'; say 'type echo'; say 'level 5'; say 'type  voice'; say 'level 6'; say 'type  work'; say 'erase 4'; say 'type works > %s'
while :; do say 'level 6'; say 'level 2'; done
"""


def main():
    pad = os.environ.get("SPARK_SHELL_WINPAD", "")
    if not (pad and os.access(pad, os.X_OK)):
        raise SystemExit("SPARK_SHELL_WINPAD names no pad build")
    for tool in ("sway", "swaymsg", "foot", "grim", "wtype"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    evidence = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="voice-evidence."))
    evidence.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="voice-proof."))
    runtime = root / "run"
    runtime.mkdir(mode=0o700)
    said = root / "said.txt"
    stub = root / "ear-stub"
    stub.write_text(STUB % said)
    stub.chmod(0o755)
    env = {**os.environ, "HOME": str(root), "XDG_CONFIG_HOME": str(root / ".config"), "XDG_STATE_HOME": str(root / ".local/state"),
           "XDG_DATA_HOME": str(root / ".local/share"), "XDG_RUNTIME_DIR": str(runtime), "WLR_BACKENDS": "headless",
           "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1", "SPARK_SHELL_DIALOG_URL": "none", "SPARK_SHELL_FONT_URL": "none",
           "SPARK_SHELL_SEMANTIC_URL": "none", "SPARK_SHELL_WINPAD": pad}
    for name in ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS"):
        env.pop(name, None)
    settings = root / ".config/spark-shell"
    settings.mkdir(parents=True)
    (settings / "config").write_text("DESKTOP=sway\nDISPLAY_IDLE=0\nDISPLAY_LOCK=0\nVOICE_ENGINE=%s\n" % stub)
    fonts = Path.home() / ".local/share/fonts"
    if fonts.is_dir():
        (root / ".local/share").mkdir(parents=True, exist_ok=True)
        os.symlink(fonts, root / ".local/share/fonts")

    def spark(*args):
        done = subprocess.run(["sh", str(REPO / "spark-shell"), *args], env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        return (done.stdout + done.stderr).strip()

    spark("on", "--yes")
    render = (root / ".config/sway/config").read_text()
    titles = [line for line in render.splitlines() if "title_format" in line]
    ok(len(titles) == 2 and all("&#x25A1; " in line and "&#x25CB;</span>" in line for line in titles),
       "the render: every title starts with the three buttons and the mic, a ring in its own color", titles)
    ok("bindsym --no-repeat Mod4+space exec %s/spark-shell desktop voice press" % REPO in render
       and "bindsym --release Mod4+space exec %s/spark-shell desktop voice release" % REPO in render,
       "the render: Super+Space pressed and released are the voice's", [line for line in render.splitlines() if "voice" in line])
    children = [subprocess.Popen(["sway", "-c", str(root / ".config/sway/config")], env=env, cwd=root, stdout=subprocess.DEVNULL, stderr=open(root / "sway.log", "w"))]
    try:
        sock = wait_for(lambda: next(iter(runtime.glob("sway-ipc.*.sock")), None), "sway's socket")
        display = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")), None), "the display")
        env["SWAYSOCK"], env["WAYLAND_DISPLAY"] = str(sock), display

        def sway(*words):
            return subprocess.run(["swaymsg", *words], env=env, capture_output=True, text=True, timeout=10).stdout

        def windows(node, out):
            if node.get("app_id") == "foot":
                out.append(node)
            for k in node.get("nodes", []) + node.get("floating_nodes", []):
                windows(k, out)
            return out

        def terminal(name):
            return next(w for w in windows(json.loads(sway("-t", "get_tree")), []) if w["name"] == name)

        def band(name):   # the start of a title band, where the buttons and the mic are drawn
            w = terminal(name)
            r, d = w["rect"], w["deco_rect"]
            return r["x"] + 10, r["y"] - d["height"] + 2, min(260, r["width"] - 20), d["height"] - 4

        def state():
            path = runtime / "spark-shell-voice.state"
            return path.read_text() if path.exists() else ""

        def shot(name):
            subprocess.run(["grim", str(evidence / (name + ".png"))], env=env, check=False)

        def why():
            log = runtime / "spark-shell-voice/log"
            return (log.read_text().replace("\n", " | ")[-300:] if log.exists() else "(no log)")

        sway("output", "*", "resolution", "1920x1080")
        time.sleep(1.5)
        sway("exec", "foot --app-id foot --title busy -e sleep 1000")
        time.sleep(1)
        sway("[app_id=spark-dialog]", "kill")
        sway("exec", "foot --app-id foot --title shell bash --norc --noprofile")
        wait_for(lambda: len(windows(json.loads(sway("-t", "get_tree")), [])) >= 2, "two terminals")
        time.sleep(2)
        wait_for(lambda: (runtime / "spark-shell-winpad.pid").exists(), "the pad")
        time.sleep(1.5)
        shot("1-at-rest")
        marks, after = band_glyphs(glyphs(env, band("shell")))
        ok(len(marks) == 4, "the focused terminal's band: the three buttons and the mic, four single glyphs", [(c[0], c[1]) for c in marks])
        if len(marks) == 4:
            mic_end = marks[3][0] + marks[3][1]
            gap = min((c[0] - mic_end for c in after), default=999)
            ok(gap >= 40, "at rest the room after the mic is blank: the title stands where it will stand while listening", (mic_end, gap))
            buttons = [c[3] for c in marks[:3]]
            mic = marks[3][3]
            apart = min(sum(abs(a - b) for a, b in zip(mic, c)) for c in buttons)
            ok(apart > 40, "the mic is drawn in its own color, not the title's, as the buttons are with the focus", (buttons, mic, apart))
        # the busy terminal's band carries the mic too: the voice is every window's
        busy, busy_after = band_glyphs(glyphs(env, band("busy")))
        ok(len(busy) == 4, "a window running something of its own carries the mic as well: the capability is the window's",
           [(c[0], c[1]) for c in busy])
        # the shell: the words come as they are said, and Enter runs the line
        sway("[title=shell]", "focus")
        time.sleep(0.5)
        answer = spark("desktop", "voice", "toggle")
        ok(answer == "voice: listening", "the mic clicked on the shell: listening", answer)
        try:
            wait_for(lambda: "listening 1" in state(), "the state says listening")
        except AssertionError:
            log = runtime / "spark-shell-voice/log"
            raise AssertionError("the session never listened: state %r, log %r, windows %r"
                                 % (state(), log.read_text()[-400:] if log.exists() else "(none)",
                                    [(w["name"], w.get("pid"), w.get("focused")) for w in windows(json.loads(sway("-t", "get_tree")), [])]))
        time.sleep(1.2)
        shot("2-listening")
        lit, lit_after = band_glyphs(glyphs(env, band("shell")))
        bars = [c for c in lit_after if len(lit) == 4 and 0 <= c[0] - (lit[3][0] + lit[3][1]) < 25]
        ok(len(lit) == 4 and bars, "while it listens the bars stand right after the mic, in the room kept for them",
           ([(c[0], c[1]) for c in lit], [(c[0], c[1]) for c in lit_after], state().replace("\n", " "), why()))
        answer = spark("desktop", "voice", "toggle")
        ok(answer == "voice: off", "clicked again: off", (answer, why()))
        wait_for(lambda: "listening 0" in state(), "the state at rest")
        time.sleep(0.7)
        quiet, quiet_after = band_glyphs(glyphs(env, band("shell")))
        ok(len(quiet) == 4 and [c[0] for c in quiet_after] == [c[0] for c in after],
           "off again: the bars are gone and the title stands where it stood", ([(c[0], c[1]) for c in quiet], [c[0] for c in quiet_after]))
        shot("3-typed")
        subprocess.run(["wtype", "-s", "20", "-k", "Return"], env=env, check=False)
        wait_for(said.exists, "the line run by Enter", 5)
        ok(said.read_text().strip() == "voice works",
           "the words were typed into the shell's line as they came, an erase and all; Enter ran them", said.read_text() if said.exists() else "")
        shot("3-after")
    except AssertionError as e:
        ok(False, str(e))
    finally:
        for c in children:
            c.terminate()
        time.sleep(1)
        for c in children:
            c.kill()
        shutil.rmtree(root, ignore_errors=True)
    print("voice proof: %s; the screens are in %s" % ("every step holds" if failed == 0 else "%d failed" % failed, evidence))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
