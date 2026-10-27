#!/usr/bin/env python3
"""The Mac battery provider reads pmset, including absent and unknown estimates."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class Battery(unittest.TestCase):
    def test_native_status_and_estimates_without_linux_battery_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name, text in {"uname": "#!/bin/sh\necho Darwin\n", "pmset": '#!/bin/sh\ncat "$BATTERY_TEST_DATA"\n'}.items():
                path = bin_dir / name
                path.write_text(text)
                path.chmod(0o755)
            fixture = root / "battery"
            env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                   "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                   "SPARK_SHELL_SYS": str(root / "sys"), "BATTERY_TEST_DATA": str(fixture)}
            request = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "resources/read", "params": {"uri": "spark-shell://bat/rows"}})
            for status, expected, absent in [
                ("76%; discharging; 4:15 remaining present: true", ["76%", "discharging", "4:15 left"], ["no battery"]),
                ("60%; charging; 1:20 remaining present: true", ["60%", "charging", "1:20 to full"], ["no battery"]),
                ("100%; charged; 0:00 remaining present: true", ["100%", "charged"], ["0:00 left", "0:00 to full"]),
                ("40%; charging; (no estimate) present: true", ["40%", "charging"], ["no estimate", "to full"]),
                ("", ["no battery reported by macOS"], ["charge "]),
            ]:
                with self.subTest(status=status):
                    fixture.write_text("Now drawing from 'AC Power'\n" + (" -InternalBattery-0 (id=1) " + status + "\n" if status else ""))
                    out = subprocess.run([str(REPO / "spark-shell"), "provide", "bat"], input=request + "\n", text=True, capture_output=True, env=env, timeout=10)
                    self.assertEqual(out.returncode, 0, out.stderr)
                    rows = json.loads(json.loads(out.stdout)["result"]["contents"][0]["text"])
                    words = " ".join(row["text"] for row in rows["rows"])
                    for phrase in expected:
                        self.assertIn(phrase, words)
                    for phrase in absent:
                        self.assertNotIn(phrase, words)


if __name__ == "__main__":
    unittest.main()
