#!/usr/bin/env python3
"""The display section against a stub compositor that keeps its screens: the undo, and what a monitor's own words may never
reach."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]

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
                    "SPARK_SHELL_PTS_DIR": str(self.root / "pts"),
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

    def calls(self):
        log = self.root / "calls"
        return [" ".join(json.loads(line)[1:]) for line in log.read_text().splitlines()] if log.exists() else []

    def conf(self):
        return self.screens.read_text() if self.screens.exists() else ""

    def shell(self, *words, **env):
        return subprocess.run(["sh", str(REPO / "spark-shell"), *words], env={**self.env, **env}, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=60)

    def raw(self, method, params, client=None):
        with Provider(self, client=client) as p:
            return p.ask(method, params)

    # --- the undo, through a client that names nothing (as it was before the page)
    def test_custom_scale_and_refresh_survive_tool_receipts_and_undo(self):
        self.put(screen("DP-1", "Example", "Display", "1", size=(1920, 1080, 59940), more=((1920, 1080, 60000),), scale=1.2))
        for name, field, value, prior in (("display_scale", "scale", "1.5", "1.2"), ("display_mode", "mode", "1920x1080@60Hz", "1920x1080@59.94Hz")):
            result = self.raw("tools/call", {"name": name, "arguments": {"screen": "DP-1", field: value}})
            self.assertFalse(result["result"].get("isError"), result)
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
