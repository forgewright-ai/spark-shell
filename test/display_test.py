#!/usr/bin/env python3
"""The display section against a stub compositor that keeps its screens: the page's rows, a change being tried (kept, back,
left to lapse), the undo, and what a monitor's own words may never reach."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
ROWS = "spark-shell://display/rows"

# swaymsg: get_outputs is a file, an output command changes it as the compositor would, every command is logged
SWAYMSG = '''import json, os, re, sys
from pathlib import Path
p = Path(os.environ["DISPLAY_TEST_ROOT"]); a = sys.argv[1:]
if a == ["-t", "get_outputs"]: print((p / "outputs").read_text())
elif a == ["-t", "get_version"]: print("{}")
elif a and a[0] == "--":
    with (p / "calls").open("a") as f: f.write(json.dumps(a) + "\\n")
    if (p / "refuse").exists(): sys.exit(2)
    m = re.match(r'output (?:"([^"]*)"|(\\S+)) (\\S+) ?(.*)$', " ".join(a[1:]), re.S)
    if m:
        ref, (verb, words), outs = m[1] or m[2], (m[3], m[4].split()), json.loads((p / "outputs").read_text())
        for o in outs:
            if ref not in (o["name"], " ".join(o[k] or "Unknown" for k in ("make", "model", "serial"))): continue
            if verb == "mode": o["current_mode"] = next(x for x in o["modes"] if words[0] in ("%dx%d" % (x["width"], x["height"]), "%dx%d@%gHz" % (x["width"], x["height"], x["refresh"] / 1000)))
            elif verb == "scale": o["scale"] = float(words[0])
            elif verb == "transform": o["transform"] = words[0]
            elif verb == "position": o["rect"]["x"], o["rect"]["y"] = int(words[0]), int(words[1])
            elif verb == "enable": o["active"] = True; o["current_mode"] = o["current_mode"] or o["modes"][0]
            elif verb == "disable": o["active"] = False
            w, h = (o["current_mode"]["width"], o["current_mode"]["height"])
            if o["transform"] in ("90", "270"): w, h = h, w
            o["rect"]["width"], o["rect"]["height"] = round(w / o["scale"]), round(h / o["scale"])
        (p / ("outputs.%d" % os.getpid())).write_text(json.dumps(outs)); (p / ("outputs.%d" % os.getpid())).replace(p / "outputs")
    print('[{"success":true}]')
else: print("[]")
'''


def modes(*sizes):
    return [{"width": w, "height": h, "refresh": r} for w, h, r in sizes]


def screen(name, make, model, serial, x=0, y=0, size=(1920, 1080, 60000), more=(), transform="normal", scale=1, on=True):
    offered = modes(size, *more)
    w, h = (size[1], size[0]) if transform in ("90", "270") else size[:2]
    rect = {"x": x, "y": y, "width": round(w / scale), "height": round(h / scale)} if on else {"x": 0, "y": 0, "width": 0, "height": 0}
    return {"name": name, "make": make, "model": model, "serial": serial, "active": on, "scale": scale, "transform": transform,
            "current_mode": offered[0] if on else None, "rect": rect, "modes": offered}


class Provider:
    def __init__(self, test, client="spark-dialog", section="display", path=None):
        env = dict(test.env, PATH=path or test.env["PATH"])
        self.p = subprocess.Popen([str(REPO / "spark-shell"), "provide", section], env=env, text=True,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.n = 0
        if client is not None:
            self.ask("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": client, "version": "0"}})

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.p.stdin.close()
        self.p.wait(timeout=30)
        self.p.stdout.close()

    def ask(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n")
        self.p.stdin.flush()
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise AssertionError("the provider ended")
            if json.loads(line).get("id") == self.n:
                return json.loads(line)

    def rows(self, uri=ROWS):
        got = self.ask("resources/read", {"uri": uri})
        return json.loads(got["result"]["contents"][0]["text"]) if "result" in got else None

    def call(self, tool, /, **arguments):
        got = self.ask("tools/call", {"name": tool, "arguments": arguments})
        return got.get("result", got)


class Display(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="display-test."))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.bins = self.root / "bin"
        self.bins.mkdir()
        self.config = self.root / "config/spark-shell"
        self.config.mkdir(parents=True)
        (self.config / "config").write_text("DESKTOP=sway\nWALLPAPER=#204060\n")
        (self.root / "os-release").write_text("ID=fixture\n")
        self.run = self.root / "run"
        self.run.mkdir(mode=0o700)
        self.stub("uname", "#!/bin/sh\necho Linux\n")
        self.stub("swaymsg", "#!" + sys.executable + "\n" + SWAYMSG)
        for name in ("sudo", "doas", "pkill", "brightnessctl", "ddcutil", "fc-list"):   # nothing of this machine's
            self.stub(name, "#!/bin/sh\nexit 1\n")
        self.env = {**os.environ, "PATH": str(self.bins) + ":" + os.environ["PATH"], "HOME": str(self.root),
                    "XDG_CONFIG_HOME": str(self.root / "config"), "XDG_STATE_HOME": str(self.root / "state"),
                    "XDG_DATA_HOME": str(self.root / "data"), "XDG_RUNTIME_DIR": str(self.run),
                    "SPARK_OS_RELEASE": str(self.root / "os-release"), "SPARK_SHELL_ROOT": str(self.root / "native"),
                    "SPARK_SHELL_SYS": str(self.root / "sys"), "SPARK_SHELL_DEV": str(self.root / "dev"),
                    "SPARK_SHELL_PTS_DIR": str(self.root / "pts"), "SPARK_SHELL_TRIAL_SECONDS": "30",
                    "SWAYSOCK": str(self.root / "sway.sock"), "DISPLAY_TEST_ROOT": str(self.root)}
        for name in ("WAYLAND_DISPLAY", "I3SOCK", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_SHELL_NO_SVG"):
            self.env.pop(name, None)
        self.screens = self.config / "screens.conf"
        self.put(screen("DP-3", "Example", "MB16FC", "1", size=(1920, 1200, 60000), transform="90"),
                 screen("HDMI-A-1", "Example", "T24i-30", "2", x=1200, more=((1280, 720, 60000), (1920, 1080, 59940), (2560, 1440, 59951))))

    def stub(self, name, text):
        (self.bins / name).write_text(text)
        (self.bins / name).chmod(0o755)

    def put(self, *outputs):
        (self.root / "outputs").write_text(json.dumps(outputs))

    def out(self, name):
        return next(o for o in json.loads((self.root / "outputs").read_text()) if o["name"] == name)

    def live(self):
        return {o["name"]: (o["current_mode"] and o["current_mode"]["width"], o["scale"], o["transform"], o["rect"]["x"], o["rect"]["y"])
                for o in json.loads((self.root / "outputs").read_text())}

    def calls(self):
        log = self.root / "calls"
        return [" ".join(json.loads(line)[1:]) for line in log.read_text().splitlines()] if log.exists() else []

    def conf(self):
        return self.screens.read_text() if self.screens.exists() else ""

    def state(self):
        folder = self.run / "spark-shell"
        return sorted(f.name for f in folder.glob("trial.*")) if folder.exists() else []

    def token(self):
        text = next((self.run / "spark-shell").glob("trial.*")).read_text()
        return next(line.split("\x1f")[1] for line in text.splitlines() if line.startswith("token\x1f"))

    def timers(self):   # the timers of this test's trials: each by its state's token
        found = []
        for proc in Path("/proc").glob("[0-9]*"):
            try:
                words = (proc / "cmdline").read_bytes().split(b"\0")
                if b"--trial" in words and str(self.root).encode() in (proc / "environ").read_bytes():
                    found.append(proc.name)
            except OSError:
                continue
        return found

    def until(self, what, seconds=20):
        end = time.time() + seconds
        while time.time() < end:
            if what():
                return True
            time.sleep(0.05)
        return what()

    def shell(self, *words, **env):
        return subprocess.run(["sh", str(REPO / "spark-shell"), *words], env={**self.env, **env}, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=60)

    def raw(self, method, params, client=None):
        with Provider(self, client=client) as p:
            return p.ask(method, params)

    # --- the undo, through a client that names nothing (as it was before the page)
    def test_custom_scale_and_refresh_survive_tool_receipts_and_undo(self):
        self.put(screen("DP-1", "Example", "Display", "1", size=(1920, 1080, 59940), more=((1920, 1080, 60000),), scale=1.2000000476837158))
        for name, field, value, prior in (("display_scale", "scale", "1.5", "1.2"), ("display_mode", "mode", "1920x1080@60Hz", "1920x1080@59.94Hz")):
            result = self.raw("tools/call", {"name": name, "arguments": {"screen": "DP-1", field: value}})
            self.assertFalse(result["result"].get("isError"), result)
            self.assertNotIn("trial", result["result"]["structuredContent"])
            undo = result["result"]["structuredContent"]["undo"]
            self.assertEqual(undo["arguments"][field], prior, "a scale as a person writes it, not the compositor's float")
            undone = self.raw("tools/call", undo)
            self.assertFalse(undone["result"].get("isError"), undone)
            self.assertIn(field + " " + prior, "\n".join(self.calls()))
        before = self.calls()
        for scale in ("0", "1;exec", "nan", 1.2):
            result = self.raw("tools/call", {"name": "display_scale", "arguments": {"screen": "DP-1", "scale": scale}})
            self.assertIn("error", result)
        self.assertEqual(self.calls(), before)

    # --- the page
    def steps(self, rows):
        for row in rows["rows"]:
            step = row.get("step")
            if step is None:
                continue
            self.assertTrue(1 <= len(step["values"]) <= 64 and 0 <= step["at"] < len(step["values"]), row)
            self.assertTrue(all(1 <= len(v["shown"]) <= 12 and 1 <= len(v["sent"]) <= 32 for v in step["values"]), row)
            self.assertTrue(all(len(w) <= 12 for w in step["words"]) and step["key"].isalpha(), row)
        ids = [r["id"] for r in rows["rows"]]
        self.assertEqual(len(ids), len(set(ids)), "each row its own id")
        self.assertEqual(rows["short"], ids)

    def test_the_section_is_a_map_a_row_a_screen_the_brightness_and_the_idle_and_lock_steps(self):
        (self.root / "sys/class/backlight/panel").mkdir(parents=True)
        self.stub("brightnessctl", "#!/bin/sh\necho 'panel,backlight,120,47%,255'\n")
        (self.config / "config").write_text("DESKTOP=sway\nWALLPAPER=#204060\nDISPLAY_IDLE=12\nDISPLAY_LOCK=0\nDISPLAY_SAVER=art\n")
        self.screens.write_text('workspace 1 output "Example T24i-30 2"\n')
        self.put(screen("HDMI-A-1", "Example", "T24i-30", "2", x=1200), screen("DP-3", "Example", "MB16FC", "1", size=(1920, 1200, 60000), transform="90"),
                 screen("DP-1", "Example", "Off one", "3", on=False))
        with Provider(self) as p:
            rows = p.rows()
        self.steps(rows)
        self.assertEqual((rows["title"], rows["state"]), ("display", "3 screens"))
        self.assertEqual([r["id"] for r in rows["rows"]],
                         ["display:map", "display:screen:DP-3", "display:screen:HDMI-A-1", "display:screen:DP-1", "display:level", "display:idle", "display:saver", "display:lock"])
        self.assertEqual([r["group"] for r in rows["rows"]], ["screens"] * 4 + ["brightness"] + ["idle and lock"] * 3)
        first = rows["rows"][0]
        self.assertEqual(first["move"], {"name": "display_position", "arguments": {}})
        self.assertEqual(first["screens"], [
            {"name": "DP-3", "text": "MB16FC", "x": 0, "y": 0, "w": 1200, "h": 1920, "on": True, "main": False, "children": ROWS + "/screen/DP-3"},
            {"name": "HDMI-A-1", "text": "T24i-30", "x": 1200, "y": 0, "w": 1920, "h": 1080, "on": True, "main": True, "children": ROWS + "/screen/HDMI-A-1"},
            {"name": "DP-1", "text": "Off one", "x": 0, "y": 0, "w": 0, "h": 0, "on": False, "main": False, "children": ROWS + "/screen/DP-1"}],
            "from the left, the ones off last; a color wallpaper has no picture")
        self.assertEqual([(r["text"], r["columns"], r["sign"], r["children"]) for r in rows["rows"][1:4]],
                         [("MB16FC", ["1920x1200 · turned"], "opens", ROWS + "/screen/DP-3"),
                          ("T24i-30", ["1920x1080 · main"], "opens", ROWS + "/screen/HDMI-A-1"), ("Off one", ["off"], "opens", ROWS + "/screen/DP-1")])
        steps = {r["id"]: r["step"] for r in rows["rows"] if "step" in r}
        level = steps["display:level"]
        self.assertEqual([v["sent"] for v in level["values"]], [str(n) for n in sorted(list(range(5, 101, 5)) + [47])])
        self.assertEqual((level["values"][level["at"]]["shown"], level["set"], level["key"], level["words"]),
                         ("47%", {"name": "display_brightness", "arguments": {}}, "level", ["dimmer", "brighter"]))
        idle, lock, saver = steps["display:idle"], steps["display:lock"], steps["display:saver"]
        self.assertEqual([v["sent"] for v in idle["values"]], ["5", "10", "12", "15", "30", "60", "0"])
        self.assertEqual((idle["values"][idle["at"]]["shown"], idle["set"]["name"], idle["key"]), ("12 min", "display_idle", "minutes"))
        self.assertEqual((lock["values"][lock["at"]], [v["sent"] for v in lock["values"]], lock["set"]["name"]),
                         ({"shown": "never", "sent": "0"}, ["5", "10", "15", "30", "60", "0"], "display_lock"))
        self.assertEqual((saver["values"][saver["at"]]["sent"], saver["set"]["name"], saver["key"]), ("art", "display_saver", "name"))
        self.assertFalse(any(r["tool"] for r in rows["rows"]), "a step sets; no brighter or dimmer row, no tick row")

    def test_no_brightness_no_python_no_desktop_and_one_screen(self):
        self.stub("python3", "#!/bin/sh\nexit 1\n")
        self.put(screen("eDP-1", "BOE", "0x0BCA", ""))
        with Provider(self) as p:
            rows, page = p.rows(), p.rows(ROWS + "/screen/eDP-1")
            state = p.ask("initialize", {"clientInfo": {"name": "spark-dialog"}})["result"]["serverInfo"]["title"]
        self.steps(rows)
        self.assertEqual((rows["state"], state), ("1 screen", "1 screen"))
        self.assertEqual([r["id"] for r in rows["rows"]], ["display:map", "display:screen:eDP-1", "display:idle", "display:saver", "display:lock"])
        self.assertEqual(rows["rows"][1]["text"], "built-in screen")
        self.assertEqual([v["sent"] for v in rows["rows"][3]["step"]["values"]], ["clock", "art"], "without a python3 that runs them, spark-shell's own two")
        self.assertEqual([r["text"] for r in page["rows"]], ["make it the main screen", "resolution", "scale", "orientation"], "the only screen on has no switch")
        del self.env["SWAYSOCK"]
        with Provider(self) as p:
            rows = p.rows()
        self.assertEqual((rows["state"], [r["id"] for r in rows["rows"]]), ("", ["display:idle", "display:saver", "display:lock"]), "no desktop, no screens")

    def test_one_screens_page_and_its_resolutions(self):
        self.screens.write_text('workspace 1 output "HDMI-A-1"\n')
        with Provider(self) as p:
            page, other, modes_page, none = p.rows(ROWS + "/screen/HDMI-A-1"), p.rows(ROWS + "/screen/DP-3"), p.rows(ROWS + "/screen/HDMI-A-1/modes"), p.rows(ROWS + "/screen/DP-9")
            bad = [p.rows(ROWS + "/screen/" + name) for name in ("DP-9/modes", "a b", "../DP-3", "DP-3;x")]
        self.assertTrue(none is None and bad == [None] * 4, "no screen of that name, no page")
        for rows in (page, other, modes_page):
            self.steps(rows)
            self.assertTrue(all(r["group"] is None for r in rows["rows"]))
        self.assertEqual((page["title"], page["state"]), ("T24i-30", "1920x1080 60 Hz"))
        use, main, res, scale, turn, beside = page["rows"]
        self.assertEqual((use["text"], use["switch"]), ("in use", {"on": True, "turn_on": {"name": "display_on", "arguments": {"screen": "HDMI-A-1"}},
                                                                   "turn_off": {"name": "display_off", "arguments": {"screen": "HDMI-A-1"}}}))
        self.assertEqual((main["text"], main["columns"], main["muted"], main["tool"]), ("main screen", ["this one"], True, None))
        self.assertEqual((other["rows"][1]["text"], other["rows"][1]["tool"]), ("make it the main screen", {"name": "display_main", "arguments": {"screen": "DP-3"}}))
        self.assertEqual((res["text"], res["columns"], res["choice"], res["children"]), ("resolution", ["1920x1080 60 Hz"], True, ROWS + "/screen/HDMI-A-1/modes"))
        self.assertEqual((scale["step"]["values"], scale["step"]["at"], scale["step"]["set"], scale["step"]["key"]),
                         ([{"shown": s, "sent": v} for s, v in (("75%", "0.75"), ("100%", "1"), ("125%", "1.25"), ("150%", "1.5"), ("200%", "2"))], 1,
                          {"name": "display_scale", "arguments": {"screen": "HDMI-A-1"}}, "scale"))
        self.assertEqual(turn["step"]["values"], [{"shown": s, "sent": v} for s, v in (("upright", "normal"), ("right", "90"), ("upside down", "180"), ("left", "270"))],
                         "the compositor turns the picture clockwise")
        self.assertEqual((turn["step"]["at"], other["rows"][4]["step"]["at"]), (0, 1))
        self.assertEqual((beside["text"], beside["step"]["set"], [v["sent"] for v in beside["step"]["values"]], beside["step"]["at"], other["rows"][5]["step"]["at"]),
                         ("beside MB16FC", {"name": "display_place", "arguments": {"screen": "HDMI-A-1", "other": "DP-3"}}, ["left-of", "right-of", "above", "below"], 1, 0))
        self.assertEqual([(r["text"], r["sign"], r["back"]) for r in modes_page["rows"]],
                         [("2560x1440 59.95 Hz", "blank", True), ("1920x1080 60 Hz", "check", True), ("1920x1080 59.94 Hz", "blank", True), ("1280x720 60 Hz", "blank", True)])
        self.assertEqual([r["tool"] and r["tool"]["arguments"]["mode"] for r in modes_page["rows"]], ["2560x1440@59.951Hz", None, "1920x1080@59.94Hz", "1280x720@60Hz"])

    def test_a_scale_of_its_own_a_mirrored_turn_places_and_a_screen_off(self):
        for scale, shown, sent in ((1.2000000476837158, "120%", "1.2"), (1.3333333730697632, "133%", "1.3333"), (1.25, "125%", "1.25"), (3, "300%", "3")):
            self.put(screen("DP-3", "Example", "MB16FC", "1", scale=scale))
            with Provider(self) as p:
                step = next(r["step"] for r in p.rows(ROWS + "/screen/DP-3")["rows"] if r["text"] == "scale")
            self.assertEqual(step["values"][step["at"]], {"shown": shown, "sent": sent})
            self.assertLessEqual(len(step["values"]), 6)
            self.assertEqual([float(v["sent"]) for v in step["values"]], sorted(float(v["sent"]) for v in step["values"]))
        flipped = screen("DP-3", "Example", "MB16FC", "1")
        flipped["transform"] = "flipped-90"
        self.put(flipped, screen("HDMI-A-1", "Example", "T24i-30", "2", on=False))
        with Provider(self) as p:
            page, off = p.rows(ROWS + "/screen/DP-3"), p.rows(ROWS + "/screen/HDMI-A-1")
            rows = p.rows()
        self.assertEqual([(r["columns"], r["muted"], "step" in r) for r in page["rows"] if r["text"] == "orientation"], [(["mirrored"], True, False)])
        self.assertEqual([r["text"] for r in page["rows"]], ["make it the main screen", "resolution", "scale", "orientation"], "the last one on: no switch, no screen to stand beside")
        self.assertEqual((off["state"], [(r["text"], r["switch"]["on"]) for r in off["rows"]]), ("off", [("in use", False)]))
        self.assertEqual(rows["rows"][1]["columns"], ["1920x1080 · mirrored"])
        places = {(-1920, 0): "left-of", (1920, 0): "right-of", (0, -1080): "above", (0, 1080): "below", (-1920, -1080): "left-of",
                  (-100, 0): "left-of", (40, 10): "right-of", (0, -500): "above", (3, 700): "below", (0, 0): "left-of"}
        for (x, y), side in places.items():
            self.put(screen("DP-3", "Example", "MB16FC", "1", x=x, y=y), screen("HDMI-A-1", "Example", "T24i-30", "2"))
            with Provider(self) as p:
                step = p.rows(ROWS + "/screen/DP-3")["rows"][-1]["step"]
            self.assertEqual(step["values"][step["at"]]["sent"], side, (x, y))

    def test_names_of_screens_that_share_a_model_or_hold_odd_words(self):
        odd = 'A "quoted" | model'
        self.put(screen("DP-1", "Example", "Twin", "1"), screen("DP-2", "Example", "Twin", "2", x=1920), screen("DP-3", "Example", odd, "3", x=3840),
                 screen("DP-4", "", "Unknown", "", x=5760), screen("DP-5", None, None, None, x=7680))
        with Provider(self) as p:
            rows, page = p.rows(), p.rows(ROWS + "/screen/DP-3")
        self.assertEqual([r["text"] for r in rows["rows"][1:6]], ["DP-1", "DP-2", 'A "quoted" / model', "DP-4", "DP-5"], "the model, the port where two share one or it says none")
        self.assertEqual(page["title"], 'A "quoted" / model')
        self.assertEqual([r["text"] for r in page["rows"][-4:]], ["beside DP-1", "beside DP-2", "beside DP-4", "beside DP-5"])

    def test_the_maps_pictures_are_made_apart_and_kept(self):
        if not shutil.which("rsvg-convert"):
            self.skipTest("no rsvg-convert")
        (self.config / "config").write_text("DESKTOP=sway\nTHEME=nord\nWALLPAPER=fjord\n")
        with Provider(self) as p:
            first = p.rows()["rows"][0]["screens"]
            self.assertFalse(any("picture" in s for s in first), "the page opens without them")
            self.assertTrue(self.until(lambda: all("picture" in s for s in p.rows()["rows"][0]["screens"])))
            pictures = {s["name"]: Path(s["picture"]) for s in p.rows()["rows"][0]["screens"]}
        size = {}
        for name, path in pictures.items():
            data = path.read_bytes()
            self.assertEqual(data[:8], bytes.fromhex("89504e470d0a1a0a"))
            self.assertEqual(path.parent, self.root / "state/spark-shell/thumbs/screens")
            size[name] = (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big"))
        self.assertEqual(size, {"DP-3": (225, 360), "HDMI-A-1": (360, 202)}, "each in its screen's shape")
        made = {path: path.stat().st_mtime_ns for path in pictures.values()}
        with Provider(self) as p:
            p.rows()
            time.sleep(0.5)
        self.assertEqual({path: path.stat().st_mtime_ns for path in pictures.values()}, made, "once, not at each read")
        self.assertFalse((self.root / "state/spark-shell/thumbs/screens/.making").exists())

    # --- the minutes
    def test_the_minutes_take_a_number_or_its_digits_and_no_junk(self):
        with Provider(self) as p:
            for tool, key, value in (("display_idle", "DISPLAY_IDLE", "20"), ("display_idle", "DISPLAY_IDLE", 25), ("display_lock", "DISPLAY_LOCK", "0"), ("display_lock", "DISPLAY_LOCK", 999)):
                got = p.call(tool, minutes=value)
                self.assertFalse(got.get("isError", True), got)
                self.assertIn("%s=%s" % (key, value), (self.config / "config").read_text().splitlines())
            again = p.call("display_lock", minutes="999")
            self.assertEqual(again["structuredContent"]["receipt"], "lock after 999 minutes", "the one in use again is a receipt")
            before = (self.config / "config").read_text()
            for junk in ("08", "1000", "-1", "5;x", "", " 5", "5 ", "five", "1e1", 5.5, 1000, -1, True, None, ["5"]):
                got = p.call("display_idle", minutes=junk)
                self.assertEqual(got.get("error", {}).get("code"), -32602, (junk, got))
            for junk in ("0; exec bad", "1.5", 1.5, "99999", 70000, "", None):
                got = p.call("display_position", screen="DP-3", x=junk, y=0)
                self.assertEqual(got.get("error", {}).get("code"), -32602, (junk, got))
            for _ in range(2):   # the saver of the step's list; the one in use again is a receipt too
                got = self.tried(p, "display_saver", name="art")
                self.assertEqual(got["receipt"], "idle screen shows the art, the clock over it")
            before += "DISPLAY_SAVER=art\n"
            got = p.call("display_saver", name="fire")
            self.assertEqual(got.get("error", {}).get("code"), -32602)
            self.assertEqual((self.config / "config").read_text(), before)
            got = p.call("display_position", screen="DP-3", x="30", y="-0")
            self.assertEqual((got["isError"], got["structuredContent"]["undo"]["arguments"]), (False, {"screen": "DP-3", "x": 0, "y": 0}))
        self.assertIn('output "Example MB16FC 1" position 30 -0\n', self.conf())

    # --- the trial
    def tried(self, p, tool, **arguments):
        got = p.call(tool, **arguments)
        self.assertFalse(got.get("isError", True), got)
        return got["structuredContent"]

    def test_a_change_is_tried_kept_and_undone(self):
        first = '# rendered by spark-shell: the screens, as spark-shell desktop screen set them\noutput "Example T24i-30 2" position 1200 0\n'
        self.screens.write_text(first)
        with Provider(self) as p:
            got = self.tried(p, "display_mode", screen="HDMI-A-1", mode="1280x720@60Hz")
            self.assertEqual(got["trial"], {"said": "1280x720 60 Hz", "seconds": 30, "keep": {"name": "display_keep", "arguments": {"screen": "HDMI-A-1"}},
                                            "back": {"name": "display_back", "arguments": {"screen": "HDMI-A-1"}}})
            self.assertEqual((got["receipt"], "undo" in got, got["rows"]["title"]), ("HDMI-A-1 1280x720 60 Hz, back in 30 seconds unless kept", False, "display"))
            self.assertEqual((self.out("HDMI-A-1")["current_mode"]["width"], self.conf()), (1280, first), "live at once, screens.conf as it was")
            state = self.run / "spark-shell" / self.state()[0]
            self.assertEqual((len(self.state()), oct(state.stat().st_mode & 0o777), oct(state.parent.stat().st_mode & 0o777)), (1, "0o600", "0o700"))
            if Path("/proc/self/cmdline").exists():
                self.assertEqual(len(self.timers()), 1)
                timer = int(self.timers()[0])
                self.assertEqual(os.getsid(timer), timer, "a session of its own")
                held = [os.readlink(f) for f in Path("/proc/%d/fd" % timer).iterdir() if int(f.name) < 10]
                self.assertTrue(all("pipe" not in f for f in held), held)
            kept = self.tried(p, "display_keep", screen="HDMI-A-1")
            self.assertEqual((kept["receipt"], kept["undo"], "trial" in kept),
                             ("HDMI-A-1 1280x720 60 Hz kept", {"name": "display_mode", "arguments": {"screen": "HDMI-A-1", "mode": "1920x1080@60Hz"}}, False))
            self.assertEqual(self.conf(), first + 'output "Example T24i-30 2" mode 1280x720@60Hz\n')
            self.assertEqual(self.state(), [])
            self.assertTrue(self.until(lambda: not self.timers(), 5), "the timer ended with it")
            again, back = p.call("display_keep", screen="HDMI-A-1"), p.call("display_back", screen="HDMI-A-1")
            self.assertEqual([(g["isError"], g["content"][0]["text"]) for g in (again, back)], [(True, "nothing is being tried on HDMI-A-1: it was kept, or it went back")] * 2)
            self.assertEqual(self.conf().count("mode"), 1)
            undone = self.tried(p, kept["undo"]["name"], **kept["undo"]["arguments"])
            self.assertEqual(undone["trial"]["said"], "1920x1080 60 Hz", "an undo from the dialog is tried like any change")
            self.tried(p, "display_keep", screen="HDMI-A-1")
        self.assertEqual(self.conf(), first + 'output "Example T24i-30 2" mode 1920x1080@60Hz\n')

    def test_a_reload_in_between_takes_a_kept_change_again(self):
        first = 'output "Example T24i-30 2" position 1200 0\n# beside "Example T24i-30 2" right-of "Example MB16FC 1"\n'
        self.screens.write_text(first)
        before = (self.root / "outputs").read_text()
        with Provider(self) as p:
            self.tried(p, "display_transform", screen="DP-3", transform="normal")
            (self.root / "outputs").write_text(before)   # the compositor's reload reads the file, which has the old
            self.tried(p, "display_keep", screen="DP-3")
            self.assertEqual((self.live()["DP-3"][2], self.out("HDMI-A-1")["rect"]["x"]), ("normal", 1920))
            self.assertIn('output "Example T24i-30 2" position 1920 0\n', self.conf())
            self.tried(p, "display_scale", screen="HDMI-A-1", scale="1.5")
            sent = len(self.calls())
            self.tried(p, "display_keep", screen="HDMI-A-1")
            self.assertEqual(len(self.calls()), sent, "what is live already is not sent again")

    def test_back_restores_at_once_and_the_schema_names_the_trial(self):
        before = self.live()
        with Provider(self) as p:
            tools = {t["name"]: t for t in p.ask("tools/list")["result"]["tools"]}
            for name in ("display_mode", "display_scale", "display_transform"):
                self.assertEqual(tools[name]["outputSchema"]["properties"]["trial"]["required"], ["said", "seconds", "keep", "back"])
            self.assertNotIn("trial", tools["display_position"]["outputSchema"]["properties"])
            for name in ("display_keep", "display_back"):
                self.assertEqual((tools[name]["_meta"], tools[name]["annotations"]["idempotentHint"]), ({"spark-shell/person": True}, True))
            for tool, value, said in (("scale", "1.5", "scale 150%"), ("mode", "1280x720", "1280x720"), ("transform", "90", "turned right"), ("transform", "270", "turned left"), ("transform", "180", "upside down")):
                got = self.tried(p, "display_" + tool, screen="HDMI-A-1", **{tool: value})
                self.assertEqual(got["trial"]["said"], said)
                self.assertNotEqual(self.live(), before)
                got = self.tried(p, "display_back", screen="HDMI-A-1")
                self.assertEqual((got["receipt"], "undo" in got, "trial" in got), ("HDMI-A-1 is back as it was", False, False))
                self.assertEqual((self.live(), self.state()), (before, []))
            got = p.call("display_keep", screen="DP-3")
            self.assertEqual((got["isError"], got["content"][0]["text"]), (True, "nothing is being tried on DP-3: it was kept, or it went back"))
            self.tried(p, "display_scale", screen="HDMI-A-1", scale="2")
            got = p.call("display_keep", screen="DP-3")
            self.assertTrue(got["isError"], "another screen's word is no answer")
            self.assertEqual(len(self.state()), 1)
            for junk in ("", "a b", "DP-3;x", 'x"y', None, 3):
                got = p.call("display_back", screen=junk)
                self.assertTrue("error" in got or got["isError"], (junk, got))
            self.tried(p, "display_back", screen="HDMI-A-1")
        self.assertEqual(self.conf(), "", "nothing was written")

    def test_a_turn_moves_the_screens_beside_it_and_goes_back_by_itself_with_the_provider_gone(self):
        first = ('# rendered by spark-shell: the screens, as spark-shell desktop screen set them\noutput "Example MB16FC 1" transform 90\n'
                 'output "Example T24i-30 2" position 1200 0\n# beside "Example T24i-30 2" right-of "Example MB16FC 1"\n')
        self.screens.write_text(first)
        before = self.live()
        self.env["SPARK_SHELL_TRIAL_SECONDS"] = "2"
        with Provider(self) as p:
            self.tried(p, "display_transform", screen="DP-3", transform="normal")
            self.assertEqual((self.out("HDMI-A-1")["rect"]["x"], self.conf()), (1920, first), "the neighbor follows, live alone")
        (self.config / "config").write_text("NOT A CONFIG\n")   # a bad line never keeps the screen from going back
        self.assertTrue(self.until(lambda: self.live() == before), self.live())
        self.assertTrue(self.until(lambda: self.state() == []), self.state())
        self.assertEqual(self.conf(), first)
        self.assertTrue(self.until(lambda: not self.timers(), 5))
        (self.config / "config").write_text("DESKTOP=sway\nWALLPAPER=#204060\n")
        with Provider(self) as p:
            self.tried(p, "display_transform", screen="DP-3", transform="normal")
            self.tried(p, "display_keep", screen="DP-3")
        self.assertEqual(self.conf(), '# rendered by spark-shell: the screens, as spark-shell desktop screen set them\noutput "Example MB16FC 1" transform normal\n'
                                      'output "Example T24i-30 2" position 1920 0\n# beside "Example T24i-30 2" right-of "Example MB16FC 1"\n', "kept, the neighbor's place with it")
        time.sleep(2.5)
        self.assertEqual(self.live()["DP-3"][2], "normal", "a kept change stays")

    def test_a_turn_that_puts_a_screen_left_of_zero_moves_every_screen_and_back_puts_each(self):
        self.put(screen("DP-3", "Example", "MB16FC", "1", size=(1920, 1200, 60000), transform="90"), screen("HDMI-A-1", "Example", "T24i-30", "2", x=1200))
        first = 'output "Example MB16FC 1" position 0 0\n# beside "Example MB16FC 1" left-of "Example T24i-30 2"\n'
        self.screens.write_text(first)
        before = self.live()
        with Provider(self) as p:
            self.tried(p, "display_transform", screen="DP-3", transform="normal")
            self.assertEqual([self.out(n)["rect"]["x"] for n in ("DP-3", "HDMI-A-1")], [0, 1920], "all moved so none sits left of 0")
            self.assertEqual(self.conf(), first)
            self.tried(p, "display_back", screen="DP-3")
            self.assertEqual((self.live(), self.conf()), (before, first))
            self.tried(p, "display_transform", screen="DP-3", transform="normal")
            self.tried(p, "display_keep", screen="DP-3")
        for line in ('output "Example MB16FC 1" transform normal\n', 'output "Example MB16FC 1" position 0 0\n', 'output "Example T24i-30 2" position 1920 0\n',
                     '# beside "Example MB16FC 1" left-of "Example T24i-30 2"\n'):
            self.assertIn(line, self.conf())

    def test_a_second_change_keeps_the_first_and_what_is_in_use_is_no_trial(self):
        with Provider(self) as p:
            got = self.tried(p, "display_scale", screen="HDMI-A-1", scale="1")
            self.assertEqual((got["receipt"], "trial" in got, "undo" in got, self.calls(), self.conf()), ("HDMI-A-1 is scale 100% already", False, False, [], ""))
            self.tried(p, "display_scale", screen="HDMI-A-1", scale="1.25")
            token = self.token()
            got = self.tried(p, "display_scale", screen="HDMI-A-1", scale="1.250")
            self.assertEqual(("trial" in got, self.token()), (False, token), "the same again leaves the one being tried")
            got = self.tried(p, "display_transform", screen="DP-3", transform="180")
            self.assertEqual(got["trial"]["keep"]["arguments"], {"screen": "DP-3"})
            self.assertIn('output "Example T24i-30 2" scale 1.25\n', self.conf())
            self.assertNotIn("transform", self.conf())
            self.assertTrue(self.until(lambda: len(self.timers()) <= 1, 5))
            self.assertEqual((len(self.state()), self.token() != token), (1, True))
            got = p.call("display_keep", screen="HDMI-A-1")
            self.assertTrue(got["isError"], "the first is kept already")
            self.tried(p, "display_off", screen="HDMI-A-1")   # any other change of a screen keeps it first too
            self.assertIn('output "Example MB16FC 1" transform 180\n', self.conf())
            self.assertEqual(self.state(), [])
            got = self.tried(p, "display_scale", screen="HDMI-A-1", scale="2")
            self.assertEqual(("trial" in got, self.state()), (False, []), "a screen off shows nothing to judge")
            self.assertIn('output "Example T24i-30 2" scale 2\n', self.conf())
        self.env["SPARK_SHELL_TRIAL_SECONDS"] = "1"
        with Provider(self) as p:
            self.tried(p, "display_scale", screen="DP-3", scale="1.5")
            done = self.shell("desktop", "screen", "DP-3", "scale", "0.75")
            self.assertEqual((done.returncode, done.stdout), (0, "DP-3 scale 0.75\n"))
            time.sleep(2)
            self.assertEqual((self.out("DP-3")["scale"], self.state()), (0.75, []), "the command line's own change is never taken back")
        self.assertIn('output "Example MB16FC 1" scale 0.75\n', self.conf())

    def test_another_client_changes_at_once_and_never_keeps(self):
        for client in ("spark", "", None):
            self.screens.unlink(missing_ok=True)
            self.put(screen("DP-3", "Example", "MB16FC", "1"))
            with Provider(self, client=client) as p:
                got = self.tried(p, "display_scale", screen="DP-3", scale="1.5")
                self.assertEqual(("trial" in got, got["undo"]["arguments"], got["receipt"], self.state()), (False, {"screen": "DP-3", "scale": "1"}, "DP-3 scale 1.5", []))
                self.assertIn("scale 1.5\n", self.conf())
                got = p.call("display_keep", screen="DP-3")
                self.assertTrue("error" in got if client == "spark" else got["isError"], got)
                names = [t["name"] for t in p.ask("tools/list")["result"]["tools"]]
                self.assertEqual("display_keep" in names, client != "spark")
        for verb in ("keep", "back"):
            done = self.shell("bar", "panel", "display", verb, "DP-3")
            self.assertEqual(done.returncode, 1, done.stdout)
        with Provider(self) as p:
            self.tried(p, "display_scale", screen="DP-3", scale="2")
            for verb in ("keep", "back"):
                self.assertEqual(self.shell("bar", "panel", "display", verb, "DP-3").returncode, 1, "a plan from the prompt never answers for the person")
            self.assertEqual(len(self.state()), 1)
            self.tried(p, "display_back", screen="DP-3")

    def test_a_refused_change_leaves_no_trial_and_no_runtime_folder_tries_none(self):
        (self.root / "refuse").touch()
        with Provider(self) as p:
            got = p.call("display_scale", screen="DP-3", scale="1.5")
            self.assertEqual((got["isError"], self.state(), self.conf()), (True, [], ""), got)
            (self.root / "refuse").unlink()
            for tool, arguments in (("display_mode", {"mode": "800x600"}), ("display_mode", {"mode": "1x1"}), ("display_transform", {"transform": "flipped"}), ("display_scale", {"scale": "0"})):
                got = p.call(tool, screen="DP-3", **arguments)
                self.assertTrue("error" in got or got["isError"], got)
            got = p.call("display_scale", screen="DP-9", scale="2")
            self.assertTrue(got["isError"])
        self.assertEqual((self.state(), self.conf()), ([], ""))
        before = self.live()
        self.env["XDG_RUNTIME_DIR"], self.env["TMPDIR"] = "", str(self.root / "none")   # no folder to adopt either
        (self.root / "none").mkdir()
        with Provider(self) as p:
            got = p.call("display_scale", screen="DP-3", scale="1.5")
        self.assertTrue(got["isError"] and "XDG_RUNTIME_DIR" in got["content"][0]["text"], got)
        self.assertEqual((self.live(), self.conf()), (before, ""))

    def test_calls_at_once_leave_one_trial_whole(self):
        with Provider(self) as a, Provider(self) as b, Provider(self) as c:
            wants = ((a, "HDMI-A-1", "1.25"), (b, "HDMI-A-1", "1.5"), (c, "DP-3", "2"))
            threads = [threading.Thread(target=lambda w=w: w[0].call("display_scale", screen=w[1], scale=w[2])) for w in wants]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
            self.assertEqual((len(self.state()), [f for f in (self.run / "spark-shell").iterdir() if f.name.endswith(".lock")]), (1, []))
            self.assertTrue(self.until(lambda: len(self.timers()) <= 1, 5), self.timers())
            lines = self.conf().splitlines()
            self.assertTrue(all(line.startswith("# rendered") or line in {'output "Example T24i-30 2" scale 1.25', 'output "Example T24i-30 2" scale 1.5', 'output "Example MB16FC 1" scale 2'} for line in lines), lines)
            answers = [[p.call("display_keep", screen=name)["isError"] for p in (a, b)] for name in ("HDMI-A-1", "DP-3")]
            self.assertEqual(sorted(map(sorted, answers)), [[False, True], [True, True]], "one answer ends it")
        self.assertEqual(self.state(), [])
        for o in ("HDMI-A-1", "DP-3"):
            scale, ref = self.out(o)["scale"], "Example " + {"HDMI-A-1": "T24i-30 2", "DP-3": "MB16FC 1"}[o]
            self.assertIn('output "%s" scale %g\n' % (ref, scale), self.conf(), "what is live is what is written")
        self.env["SPARK_SHELL_TRIAL_SECONDS"] = "1"
        for wait in (0.75, 0.9, 1.0, 1.1):   # an answer as the time runs out: kept whole, or back whole
            with Provider(self) as p:
                scale = self.out("DP-3")["scale"]
                new = 1.5 if scale != 1.5 else 1.25
                self.tried(p, "display_scale", screen="DP-3", scale=str(new))
                time.sleep(wait)
                kept = not p.call("display_keep", screen="DP-3")["isError"]
                self.assertTrue(self.until(lambda: self.state() == []))
                self.assertEqual(self.out("DP-3")["scale"], new if kept else scale)
                self.assertIn('output "Example MB16FC 1" scale %g\n' % (new if kept else scale), self.conf())

    def test_the_timer_acts_on_its_own_trial_and_without_jq(self):
        before = self.live()
        with Provider(self) as p:
            self.tried(p, "display_transform", screen="DP-3", transform="normal")
            for words in (("0000000000000000", "0"), ("", "0"), ("zz", "0"), ("$(id)", "0")):
                self.shell("desktop", "--trial", *words)
            self.assertEqual((self.live()["DP-3"][2], len(self.state())), ("normal", 1), "another trial's timer finds nothing")
            farm = self.root / "farm"
            farm.mkdir()
            for folder in self.env["PATH"].split(os.pathsep):
                for tool in Path(folder).iterdir() if Path(folder).is_dir() else ():
                    if tool.name != "jq" and not (farm / tool.name).exists() and os.access(tool, os.X_OK):
                        (farm / tool.name).symlink_to(tool)
            self.shell("desktop", "--trial", self.token(), "0", PATH=str(farm))
        self.assertEqual((self.live(), self.state(), self.conf()), (before, [], ""))
        done = subprocess.run(["sh", str(REPO / "spark-shell"), "provide", "display"], env={**self.env, "PATH": str(farm)}, input="", capture_output=True, text=True, timeout=30)
        self.assertEqual((done.returncode, done.stdout), (1, ""), "no jq, no provider")

    # --- what a monitor says of itself
    def test_a_monitors_own_words_never_reach_the_config_or_the_shell(self):
        crafted = ['a"b', "$(touch /tmp/no)", "`id`", "a;exec x", "a\nexec x", "a\\", "a'b", "a|b", "a#b", "a&b", "a>b", "a\tb", "a[b]", "a*b", "a{b}", "écran", "x" * 121, "a\x01b"]
        for n, word in enumerate(crafted):
            first, second = screen("DP-1", "Example", "One", "1"), screen("DP-2", "Example", "Two", "2", x=1920)
            first[("make", "model", "serial")[n % 3]] = word
            self.put(first, second)
            self.screens.unlink(missing_ok=True)
            (self.root / "calls").unlink(missing_ok=True)
            for args in (("scale", "1.5"), ("left-of", "dp-2"), ("main",)):
                done = self.shell("desktop", "screen", "dp-1", *args)
                self.assertEqual(done.returncode, 0, (word, args, done.stdout))
            self.shell("desktop", "screen", "dp-2", "right-of", "dp-1")
            self.check_lines(word)
        for n, word in enumerate(crafted[:6]):   # and a trial's state, its way back and its lines
            first, second = screen("DP-1", "Example", "One", "1"), screen("DP-2", "Example", "Two", "2", x=1920)
            first[("serial", "make", "model")[n % 3]] = word
            self.put(first, second)
            self.screens.unlink(missing_ok=True)
            (self.root / "calls").unlink(missing_ok=True)
            with Provider(self) as p:
                self.tried(p, "display_transform", screen="DP-1", transform="180")
                self.assertNotIn(word, next((self.run / "spark-shell").glob("trial.*")).read_text())
                self.tried(p, "display_keep", screen="DP-1")
                self.tried(p, "display_transform", screen="DP-1", transform="normal")
                self.tried(p, "display_back", screen="DP-1")
                json.dumps(p.rows())
            self.check_lines(word)
            self.assertIn('output "DP-1" transform 180\n', self.conf())

    def check_lines(self, word):
        for line in self.conf().splitlines():
            self.assertRegex(line, r'^(# rendered by .*|# the main screen .*|output "(DP-1|Example Two 2)" [a-z0-9 .-]+|# beside "(DP-1|Example Two 2)" [a-z-]+ "(DP-1|Example Two 2)"'
                                   r'|workspace 1 output "DP-1"|exec swaymsg focus output \'"DP-1"\')$', repr(word))
        for call in self.calls():
            self.assertRegex(call, r'^(output "?(DP-1|Example Two 2)"? [a-z0-9 .-]+|workspace 1 output "DP-1")$', repr(word))

    def test_a_line_by_a_refused_id_from_before_gives_way_to_the_ports(self):
        self.put(screen("DP-1", "Example", "One", "#A&1"), screen("DP-2", "Example", "Two", "2", x=1920))
        self.screens.write_text('output "Example One #A&1" scale 1.5\noutput "Example One #A&1" transform 90\noutput "Example One #A&1" position 5 0\n'
                                '# beside "Example One #A&1" left-of "Example Two 2"\noutput "Example Two 2" scale 1.5\n')
        self.shell("desktop", "screen", "dp-1", "scale", "2")
        self.assertEqual(self.conf().splitlines()[1:], ['output "Example One #A&1" transform 90', 'output "Example One #A&1" position 5 0',
                                                        '# beside "Example One #A&1" left-of "Example Two 2"', 'output "Example Two 2" scale 1.5', 'output "DP-1" scale 2'])
        self.shell("desktop", "screen", "dp-1", "position", "0", "0")
        self.assertEqual(self.conf().splitlines()[1:], ['output "Example One #A&1" transform 90', 'output "Example Two 2" scale 1.5', 'output "DP-1" scale 2', 'output "DP-1" position 0 0'])

    def test_a_plain_id_is_written_and_two_screens_that_share_one_go_by_their_ports(self):
        good = ("Lenovo Group Limited", "T24i-30 (rev. 1.2) a/b, c+d: e_f", "V30-A1")
        self.put(screen("DP-1", *good))
        self.shell("desktop", "screen", "dp-1", "scale", "1.5")
        self.assertIn('output "%s" scale 1.5\n' % " ".join(good), self.conf())
        self.put(screen("DP-1", *good), screen("DP-2", *good, x=1920))
        self.shell("desktop", "screen", "dp-1", "scale", "2")
        self.assertIn('output "DP-1" scale 2\n', self.conf())
        self.put(screen("DP-1", "Example", "DP-2 stand-in", "1"), screen("DP-2", "Example", "Two", "2", x=1920))
        self.shell("desktop", "screen", "dp-2", "scale", "3")
        self.assertIn('output "Example Two 2" scale 3\n', self.conf(), "a port's own name before another screen's words")


if __name__ == "__main__":
    unittest.main()
