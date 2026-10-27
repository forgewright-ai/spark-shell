#!/usr/bin/env python3
"""Display undo keeps the native scale and refresh rate through MCP."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class Display(unittest.TestCase):
    def test_custom_scale_and_refresh_survive_tool_receipts_and_undo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bins = root / "bin"
            bins.mkdir()
            config = root / "config/spark-shell"
            config.mkdir(parents=True)
            (config / "config").write_text("DESKTOP=sway\n")
            (root / "os-release").write_text("ID=fixture\n")
            output = {"name": "DP-1", "make": "Example", "model": "Display", "serial": "1", "active": True,
                      "scale": 1.2, "current_mode": {"width": 1920, "height": 1080, "refresh": 59940},
                      "rect": {"x": 0, "y": 0, "width": 1600, "height": 900},
                      "modes": [{"width": 1920, "height": 1080, "refresh": 59940}, {"width": 1920, "height": 1080, "refresh": 60000}]}
            (root / "outputs").write_text(json.dumps([output]))
            (bins / "uname").write_text("#!/bin/sh\necho Linux\n")
            (bins / "swaymsg").write_text("#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
p=Path(os.environ["DISPLAY_TEST_ROOT"]); a=sys.argv[1:]
if a==["-t","get_outputs"]: print((p/"outputs").read_text())
elif a==["-t","get_version"]: print("{}")
elif a and a[0]=="--":
    with (p/"calls").open("a") as f: f.write(json.dumps(a)+"\\n")
    print('[{"success":true}]')
else: print("[]")
''')
            for path in bins.iterdir():
                path.chmod(0o755)
            env = {**os.environ, "PATH": str(bins) + ":" + os.environ["PATH"], "HOME": tmp,
                   "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                   "SPARK_OS_RELEASE": str(root / "os-release"), "SPARK_SHELL_ROOT": str(root / "native"),
                   "SWAYSOCK": str(root / "sway.sock"), "DISPLAY_TEST_ROOT": tmp}
            def rpc(method, params):
                request = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
                out = subprocess.run([str(REPO / "spark-shell"), "provide", "display"], env=env,
                                     input=request + "\n", text=True, capture_output=True, timeout=20)
                self.assertEqual(out.returncode, 0, out.stderr)
                return json.loads(out.stdout)
            rows = rpc("resources/read", {"uri": "spark-shell://display/rows/screen/DP-1"})
            choices = json.loads(rows["result"]["contents"][0]["text"])
            self.assertTrue(choices["short"])
            self.assertEqual({r["tool"]["arguments"]["mode"] for r in choices["rows"] if r["tool"]["name"] == "display_mode"}, {"1920x1080@59.94Hz", "1920x1080@60Hz"})
            for name, field, value, prior in (("display_scale", "scale", "1.5", "1.2"), ("display_mode", "mode", "1920x1080@60Hz", "1920x1080@59.94Hz")):
                result = rpc("tools/call", {"name": name, "arguments": {"screen": "DP-1", field: value}})
                self.assertFalse(result["result"].get("isError"), result)
                undo = result["result"]["structuredContent"]["undo"]
                self.assertEqual(undo["arguments"][field], prior)
                undone = rpc("tools/call", undo)
                self.assertFalse(undone["result"].get("isError"), undone)
                self.assertIn(field + " " + prior, (root / "calls").read_text())
            before = (root / "calls").read_text()
            for scale in ("0", "1;exec", "nan", 1.2):
                result = rpc("tools/call", {"name": "display_scale", "arguments": {"screen": "DP-1", "scale": scale}})
                self.assertIn("error", result)
            self.assertEqual((root / "calls").read_text(), before)


if __name__ == "__main__":
    unittest.main()
