#!/usr/bin/env python3
"""Named desktop bindings and concurrent open-or-focus, without a desktop."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "lib"))   # the helpers import each other by name
SPEC = importlib.util.spec_from_file_location("home", REPO / "lib/home.py")
home = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(home)


class HomeTest(unittest.TestCase):
    def test_default_and_configured_bindings_and_conflicts(self):
        template = (REPO / "template/.config/sway/config").read_text()
        rendered, pairs = home.bindings(template, {})
        keys = dict(pairs)
        self.assertEqual(keys["home.open"], "Super+space")
        self.assertEqual(keys["window.focus-mode"], "Super+Alt+space")
        self.assertNotIn("dialog chat", rendered)
        self.assertIn("desktop home", rendered)
        rendered, pairs = home.bindings(template, {"home.open": "Super+F3"})
        self.assertEqual(dict(pairs)["home.open"], "Super+F3")
        self.assertIn("bindsym Mod4+F3 exec", rendered)
        for config in ({"home.open": "Super+Return"}, {"missing": "F1"}, {"home.open": "F1;exec bad"}):
            with self.assertRaises(ValueError):
                home.bindings(template, config)
        self.assertEqual(home.chord("Super+Alt+Space"), home.chord("Alt+Mod4+space"))

    def test_home_stays_inside_the_space_under_the_bar(self):
        # #234: sway holds a floating window to the screen, not to the area the bar leaves; home is brought inside
        def tree(win, area):
            return {"type": "root", "nodes": [{"type": "output", "nodes": [{"type": "workspace", "rect": area,
                    "floating_nodes": [{"id": 42, "app_id": "spark-dialog", "rect": win}]}]}]}
        rect = lambda x, y, w, h: {"x": x, "y": y, "width": w, "height": h}
        # 1280x720 with a 28 px bar: 720 rows asked, 692 there; centred, it covered the bar by 14 and ran 14 past
        self.assertEqual(home.fit(tree(rect(340, 14, 600, 720), rect(0, 28, 1280, 692)), 42),
                         "[con_id=42] resize set width 600 px height 692 px, move position center")
        # a narrow screen too
        self.assertEqual(home.fit(tree(rect(0, 28, 600, 600), rect(0, 28, 500, 900)), 42),
                         "[con_id=42] resize set width 500 px height 600 px, move position center")
        # it fits, inside: nothing; it fits but sits over the bar: moved, not resized
        self.assertIsNone(home.fit(tree(rect(660, 174, 600, 760), rect(0, 28, 1920, 1052)), 42))
        self.assertEqual(home.fit(tree(rect(660, 0, 600, 760), rect(0, 28, 1920, 1052)), 42),
                         "[con_id=42] resize set width 600 px height 760 px, move position center")
        # nothing known, nothing done: no workspace, no rect, another window
        self.assertIsNone(home.fit({"nodes": [{"id": 42, "app_id": "spark-dialog"}]}, 42))
        self.assertIsNone(home.fit(tree(rect(0, 0, 600, 720), {}), 42))
        self.assertIsNone(home.fit(tree(rect(0, 0, 600, 720), rect(0, 28, 1280, 692)), 7))

    def test_parallel_launches_focus_one_existing_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = {**os.environ, "HOME": tmp, "XDG_RUNTIME_DIR": tmp, "PATH": tmp + os.pathsep + os.environ["PATH"]}
            for name, body in {
                "swaymsg": '''import json, os, sys
from pathlib import Path
p = Path(os.environ["HOME"])
if "get_tree" in sys.argv:
    print((p / "tree").read_text() if (p / "tree").exists() else '{"nodes":[]}')
else:
    with (p / "focus").open("a") as f: f.write("focused\\n")
    print('[{"success":true}]')
''',
                "foot": '''import json, os, time
from pathlib import Path
p = Path(os.environ["HOME"])
with (p / "launches").open("a") as f: f.write("started\\n")
time.sleep(.15)
(p / "draft").write_text("preserve this draft")
(p / "next-tree").write_text(json.dumps({"nodes":[{"app_id":"spark-dialog","id":42}]}))
(p / "next-tree").replace(p / "tree")
time.sleep(.2)
''',
            }.items():
                file = root / name
                file.write_text("#!" + sys.executable + "\n" + body)
                file.chmod(0o700)
            argv = [sys.executable, str(REPO / "lib/home.py"), "open", str(REPO / "spark-shell")]
            children = [subprocess.Popen(argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(4)]
            for child in children:
                _, error = child.communicate(timeout=10)
                self.assertEqual(child.returncode, 0, error.decode())
            self.assertEqual((root / "launches").read_text().splitlines(), ["started"])
            self.assertEqual((root / "draft").read_text(), "preserve this draft")
            self.assertGreaterEqual(len((root / "focus").read_text().splitlines()), 4)

    def test_home_back_from_the_pad_leaves_the_pad(self):
        tree = {"type": "root", "nodes": [{"type": "output", "nodes": [{"type": "workspace", "name": "__i3_scratch", "nodes": [], "floating_nodes": [
            {"type": "floating_con", "app_id": "spark-dialog", "id": 42, "marks": ["_spark-shell.min.float.42", "keep"],
             "rect": {"x": 0, "y": 0, "width": 10, "height": 10}}]}]}]}
        said = []

        def sway(*args):
            if args == ("-t", "get_tree"):
                return tree
            said.append(args[0])
            return [{"success": True}]

        kept = home.wm
        home.wm = sway
        try:
            self.assertTrue(home.focus_existing())
        finally:
            home.wm = kept
        self.assertEqual(said[0], "[con_id=42] unmark _spark-shell.min.float.42, focus")

    def test_a_section_asked_of_an_open_home_is_a_request_it_takes(self):
        # a bar block clicked while home is open: the section written for home to go to, the window focused,
        # no second launch; with no home open, the launch names the section and no request is left behind
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = {**os.environ, "HOME": tmp, "XDG_RUNTIME_DIR": tmp, "PATH": tmp + os.pathsep + os.environ["PATH"]}
            for name, body in {
                "swaymsg": '''import os, sys
from pathlib import Path
p = Path(os.environ["HOME"])
if "get_tree" in sys.argv:
    print((p / "tree").read_text() if (p / "tree").exists() else '{"nodes":[]}')
else:
    with (p / "focus").open("a") as f: f.write("focused\\n")
    print('[{"success":true}]')
''',
                "foot": '''import json, os, sys, time
from pathlib import Path
p = Path(os.environ["HOME"])
with (p / "launches").open("a") as f: f.write(" ".join(sys.argv[1:]) + "\\n")
(p / "tree").write_text(json.dumps({"nodes":[{"app_id":"spark-dialog","id":42}]}))
time.sleep(.5)   # a terminal runs while its window is up: home.py reads the window before the exit
''',
            }.items():
                file = root / name
                file.write_text("#!" + sys.executable + "\n" + body)
                file.chmod(0o700)
            argv = [sys.executable, str(REPO / "lib/home.py"), "open", str(REPO / "spark-shell")]
            goto = root / "spark-home.goto"
            done = subprocess.run(argv + ["notifications"], env=env, capture_output=True, timeout=10)
            self.assertEqual(done.returncode, 0, done.stderr.decode())
            self.assertTrue((root / "launches").read_text().rstrip().endswith("dialog notifications"))
            self.assertFalse(goto.exists(), "a new home takes its section from its argument")
            done = subprocess.run(argv + ["bt"], env=env, capture_output=True, timeout=10)
            self.assertEqual(done.returncode, 0, done.stderr.decode())
            self.assertEqual(len((root / "launches").read_text().splitlines()), 1, "home open: no second launch")
            self.assertEqual(goto.read_text(), "bt\n")
            self.assertEqual(goto.stat().st_mode & 0o777, 0o600)
            for none in ([], [""]):   # Super+Space and the bar's sign ask for no section, an empty word among them
                done = subprocess.run(argv + none, env=env, capture_output=True, timeout=10)
                self.assertEqual(done.returncode, 0, done.stderr.decode())
                self.assertEqual(goto.read_text(), "bt\n", "no section asked: no request written")
            for bad in ["../x", "Bt", "a b"]:
                done = subprocess.run(argv + [bad], env=env, capture_output=True, timeout=10)
                self.assertNotEqual(done.returncode, 0, bad)


if __name__ == "__main__":
    unittest.main()
