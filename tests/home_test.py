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
SPEC = importlib.util.spec_from_file_location("home", REPO / "lib/home.py")
home = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(home)


class HomeTest(unittest.TestCase):
    def test_default_and_configured_bindings_and_conflicts(self):
        template = (REPO / "templates/.config/sway/config").read_text()
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
                "foot": '''import json, os, sys
from pathlib import Path
p = Path(os.environ["HOME"])
with (p / "launches").open("a") as f: f.write(" ".join(sys.argv[1:]) + "\\n")
(p / "tree").write_text(json.dumps({"nodes":[{"app_id":"spark-dialog","id":42}]}))
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
            done = subprocess.run(argv, env=env, capture_output=True, timeout=10)
            self.assertEqual(done.returncode, 0, done.stderr.decode())
            self.assertEqual(goto.read_text(), "bt\n", "no section asked: no request written")
            for bad in ["../x", "Bt", "a b"]:
                done = subprocess.run(argv + [bad], env=env, capture_output=True, timeout=10)
                self.assertNotEqual(done.returncode, 0, bad)


if __name__ == "__main__":
    unittest.main()
