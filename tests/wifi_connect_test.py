#!/usr/bin/env python3
"""The iwd terminal helper keeps native output private and cancels its child."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class WifiPrompt(unittest.TestCase):
    def fixture(self, program):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        command = root / "iwctl"
        command.write_text("#!" + sys.executable + "\n" + program)
        command.chmod(0o700)
        env = {**os.environ, "PATH": str(root) + ":" + os.environ["PATH"],
               "WIFI_TEST_ROOT": str(root)}
        return root, env

    def test_native_failure_never_echoes_a_secret(self):
        _, env = self.fixture("print('synthetic-password: rejected'); raise SystemExit(1)\n")
        run = subprocess.run([sys.executable, str(REPO / "lib/wifi_connect.py"), "wlan0", "cafe"],
                             input="synthetic-password\n", text=True, capture_output=True, env=env, timeout=5)
        self.assertEqual(run.returncode, 1)
        self.assertNotIn("synthetic-password", run.stdout + run.stderr)
        self.assertIn("iwd did not confirm", run.stderr)

    def test_cancel_stops_and_reaps_the_prompt_process(self):
        root, env = self.fixture("import os,time\nfrom pathlib import Path\nPath(os.environ['WIFI_TEST_ROOT'], 'pid').write_text(str(os.getpid()))\ntime.sleep(60)\n")
        child = subprocess.Popen([sys.executable, str(REPO / "lib/wifi_connect.py"), "wlan0", "cafe"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            child.stdin.write(b"synthetic-password\n")
            child.stdin.close()
            for _ in range(100):
                if (root / "pid").exists():
                    break
                time.sleep(0.01)
            native_pid = int((root / "pid").read_text())
            child.send_signal(signal.SIGTERM)
            self.assertEqual(child.wait(timeout=5), 130)
            with self.assertRaises(ProcessLookupError):
                os.kill(native_pid, 0)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            child.stdout.close()
            child.stderr.close()

    def test_unsupported_password_never_starts_iwctl(self):
        root, env = self.fixture("from pathlib import Path\nimport os\nPath(os.environ['WIFI_TEST_ROOT'], 'started').touch()\n")
        for password in (b"x" * 64, b"first\nsecond\n", b"\n", b"short", b"caf\xc3\xa9-password"):
            run = subprocess.run([sys.executable, str(REPO / "lib/wifi_connect.py"), "wlan0", "cafe"],
                                 input=password, capture_output=True, env=env, timeout=5)
            self.assertEqual(run.returncode, 1)
        self.assertFalse((root / "started").exists())


if __name__ == "__main__":
    unittest.main()
