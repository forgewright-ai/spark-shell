#!/usr/bin/env python3
"""Native CUPS ownership, queue state, scoped cancellation and provider receipts."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("printers", REPO / "lib/printers.py")
printers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(printers)


class Printers(unittest.TestCase):
    def setUp(self):
        self.enabled = True
        self.default = "Desk"
        self.jobs = ["Office-42"]
        self.calls = []
        patcher = patch.object(printers, "native", self.native)
        patcher.start()
        self.addCleanup(patcher.stop)
        env = patch.dict(os.environ, {"LPDEST": "", "PRINTER": ""})
        env.start()
        self.addCleanup(env.stop)

    def native(self, program, *args):
        self.calls.append((program, *args))
        if program == "lpstat":
            if args == ("-p",):
                return "printer Desk is idle.\nprinter Office " + ("is idle." if self.enabled else "disabled since yesterday") + "\n"
            if args == ("-d",):
                return "system default destination: " + self.default
            self.assertEqual(args, ("-W", "not-completed", "-u"))
            return "\n".join(job + " person 1024 today" for job in self.jobs)
        if program == "lpoptions":
            self.default = args[1]
        elif program in ("cupsenable", "cupsdisable"):
            self.enabled = program == "cupsenable"
        elif program == "cancel":
            self.assertEqual(args, ("42",))
            self.jobs.remove("Office-42")
        else:
            raise AssertionError((program, args))
        return ""

    def test_default_pause_resume_and_one_owned_job(self):
        printers.act("default", "Office")
        self.assertEqual(self.default, "Office")
        printers.act("pause", "Office")
        self.assertFalse(self.enabled)
        printers.act("resume", "Office")
        self.assertTrue(self.enabled)
        printers.act("cancel", "Office-42")
        self.assertEqual(self.jobs, [])
        self.assertIn(("cancel", "42"), self.calls)
        self.assertFalse(any("-a" in call for call in self.calls))

    def test_missing_targets_and_environment_override_never_mutate(self):
        for action, target in [("default", "Missing"), ("pause", "-a"), ("cancel", "Office-99")]:
            with self.subTest(action=action), self.assertRaises(printers.Refused):
                printers.act(action, target)
        with patch.dict(os.environ, {"LPDEST": "Desk"}), self.assertRaisesRegex(printers.Refused, "override"):
            printers.act("default", "Office")
        self.assertTrue(all(call[0] == "lpstat" for call in self.calls))


class Provider(unittest.TestCase):
    def test_rows_and_confirmed_native_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (root / "config/spark-shell").mkdir(parents=True)
            (root / "config/spark-shell/config").write_text("DESKTOP=sway\n")
            (root / "os-release").write_text("ID=fixture\n")
            (root / "state.json").write_text(json.dumps({"enabled": True, "default": "Desk", "jobs": ["Office-42"]}))
            (bin_dir / "uname").write_text("#!/bin/sh\necho Linux\n")
            stub = "#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
r=Path(os.environ["PRINTER_TEST_ROOT"]); p=r/"state.json"; s=json.loads(p.read_text()); n=Path(sys.argv[0]).name; a=sys.argv[1:]
with (r/"calls").open("a") as f: f.write(json.dumps([n,*a])+"\\n")
if n=="lpstat":
    if a==["-p"]: print("printer Desk is idle.\\nprinter Office " + ("is idle." if s["enabled"] else "disabled since yesterday"))
    elif a==["-d"]: print("system default destination: "+s["default"])
    elif a==["-W","not-completed","-u"]: print("\\n".join(j+" person 1024 today" for j in s["jobs"]))
    else: sys.exit(1)
elif n=="lpoptions": s["default"]=a[1]
elif n in ["cupsenable","cupsdisable"]: s["enabled"]=n=="cupsenable"
elif n=="cancel" and a==["42"]: s["jobs"]=[]
else: sys.exit(1)
p.write_text(json.dumps(s))
'''
            for name in ("lpstat", "lpoptions", "cupsenable", "cupsdisable", "cancel"):
                (bin_dir / name).write_text(stub)
            for path in bin_dir.iterdir():
                path.chmod(0o755)
            env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                   "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                   "SPARK_OS_RELEASE": str(root / "os-release"), "PRINTER_TEST_ROOT": tmp,
                   "LPDEST": "", "PRINTER": ""}
            def rpc(method, params):
                payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
                out = subprocess.run([str(REPO / "spark-shell"), "provide", "printers"], input=payload + "\n", text=True,
                                     capture_output=True, env=env, timeout=20)
                self.assertEqual(out.returncode, 0, out.stderr)
                return json.loads(out.stdout)["result"]
            listing = rpc("tools/list", {})
            self.assertTrue(next(t for t in listing["tools"] if t["name"] == "printers_cancel")["annotations"]["destructiveHint"])
            rows = json.loads(rpc("resources/read", {"uri": "spark-shell://printers/rows"})["contents"][0]["text"])
            self.assertTrue(any(r.get("tool", {}).get("name") == "printers_pause" for r in rows["rows"] if r.get("tool")))
            result = rpc("tools/call", {"name": "printers_pause", "arguments": {"name": "Office"}})
            self.assertFalse(result.get("isError"), result)
            self.assertFalse(json.loads((root / "state.json").read_text())["enabled"])
            self.assertEqual(result["structuredContent"]["undo"]["name"], "printers_resume")
            result = rpc("tools/call", result["structuredContent"]["undo"])
            self.assertFalse(result.get("isError"), result)
            self.assertTrue(json.loads((root / "state.json").read_text())["enabled"])
            result = rpc("tools/call", {"name": "printers_cancel", "arguments": {"job": "Office-42"}})
            self.assertFalse(result.get("isError"), result)
            self.assertNotIn("undo", result["structuredContent"])
            self.assertEqual(json.loads((root / "state.json").read_text())["jobs"], [])


if __name__ == "__main__":
    unittest.main()
