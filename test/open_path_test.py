#!/usr/bin/env python3
"""File and folder opening uses the native host, with roots and real exit status."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class OpenPath(unittest.TestCase):
    def test_native_dispatch_and_failure_stay_within_approved_roots(self):
        for platform in ("Darwin", "Linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp).resolve()
                allowed = root / "approved"
                allowed.mkdir()
                note = allowed / "notes with spaces.md"
                note.write_text("hello\n")
                folder = allowed / "project files"
                folder.mkdir()
                hidden = allowed / ".hidden"
                hidden.mkdir()
                outside = root / "outside"
                outside.mkdir()
                link = allowed / "linked"
                link.symlink_to(outside)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                (bin_dir / "uname").write_text("#!/bin/sh\necho " + platform + "\n")
                (bin_dir / "xdg-mime").write_text("#!/bin/sh\necho files.desktop\n")
                opener = "#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
r=Path(os.environ["OPEN_TEST_ROOT"])
with (r/"calls").open("a") as f: f.write(json.dumps([Path(sys.argv[0]).name,*sys.argv[1:]])+"\\n")
sys.exit(1 if (r/"fail").exists() else 0)
'''
                for name in ("open", "xdg-open"):
                    (bin_dir / name).write_text(opener)
                for path in bin_dir.iterdir():
                    path.chmod(0o755)
                (root / "os-release").write_text("ID=fixture\n")
                env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                       "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                       "SPARK_OS_RELEASE": str(root / "os-release"), "OPEN_TEST_ROOT": str(root),
                       "WAYLAND_DISPLAY": "fixture", "SWAYSOCK": ""}
                def rpc(tool, path):
                    messages = [
                        {"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"capabilities": {"roots": {}}}},
                        {"jsonrpc": "2.0", "method": "notifications/initialized"},
                        {"jsonrpc": "2.0", "id": "roots", "result": {"roots": [{"uri": allowed.as_uri()}]}},
                        {"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": tool, "arguments": {"path": str(path)}}},
                    ]
                    out = subprocess.run([str(REPO / "spark-shell"), "provide", "files"],
                                         input="\n".join(map(json.dumps, messages)) + "\n", text=True,
                                         capture_output=True, env=env, timeout=15)
                    self.assertEqual(out.returncode, 0, out.stderr)
                    return next(json.loads(line)["result"] for line in out.stdout.splitlines() if json.loads(line).get("id") == 7)
                for tool, path in [("files_open", note), ("files_browse", folder)]:
                    result = rpc(tool, path)
                    self.assertFalse(result.get("isError"), result)
                    self.assertEqual(result["structuredContent"]["receipt"], "opening requested for " + path.name)
                calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
                self.assertEqual(calls, [["open" if platform == "Darwin" else "xdg-open", str(p)] for p in (note, folder)])
                (root / "fail").touch()
                result = rpc("files_open", note)
                self.assertTrue(result["isError"])
                self.assertIn("refused", result["content"][0]["text"])
                before = (root / "calls").read_text()
                for path in (outside, hidden, link):
                    result = rpc("files_browse", path)
                    self.assertTrue(result["isError"], result)
                self.assertEqual((root / "calls").read_text(), before)


if __name__ == "__main__":
    unittest.main()
