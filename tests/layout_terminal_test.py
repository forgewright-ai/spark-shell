#!/usr/bin/env python3
"""Terminal geometry, native targeting and launch ordering without a desktop."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("layout_terminal", REPO / "lib/layout_terminal.py")
terminal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(terminal)


class Terminal(unittest.TestCase):
    def test_fits_in_cells_with_native_scaling_and_only_its_container(self):
        sizes = [os.terminal_size((40, 24)), os.terminal_size((80, 24))]
        tree = {"nodes": [{"id": 31, "pid": 23, "rect": {"width": 400, "height": 500}},
                          {"id": 32, "pid": 24, "rect": {"width": 900, "height": 500}}]}
        with patch.object(terminal, "ancestors", return_value={23}), patch.object(terminal, "sway", return_value=tree) as sway, patch.object(terminal.os, "get_terminal_size", side_effect=sizes), patch.object(terminal.time, "sleep"):
            terminal.fit(80, 24)
        self.assertEqual(sway.call_args_list[1].args, ("--", "[con_id=31] resize set width 800 px height 500 px"))
        self.assertEqual(sway.call_count, 2)

    def test_no_room_floats_only_this_window_then_checks_real_cells(self):
        tree = {"nodes": [{"id": 31, "pid": 23, "rect": {"width": 400, "height": 500}}]}
        with patch.object(terminal, "ancestors", return_value={23}), patch.object(terminal, "sway", return_value=tree) as sway, patch.object(terminal.os, "get_terminal_size", return_value=os.terminal_size((40, 24))), patch.object(terminal.time, "sleep"), self.assertRaisesRegex(terminal.Refused, "cannot provide 80"):
            terminal.fit(80, 24)
        self.assertIn(("--", "[con_id=31] floating enable"), [call.args for call in sway.call_args_list])

    def test_ambiguous_parent_never_resizes_another_window(self):
        tree = {"nodes": [{"id": 31, "pid": 23}, {"id": 32, "pid": 23}]}
        with patch.object(terminal, "ancestors", return_value={23}), patch.object(terminal, "sway", return_value=tree) as sway, patch.object(terminal.os, "get_terminal_size", return_value=os.terminal_size((40, 24))), self.assertRaises(terminal.Refused):
            terminal.fit(80, 24)
        self.assertEqual(sway.call_count, 1)

    def test_real_pty_child_waits_for_layout_then_executes_app(self):
        import fcntl
        import pty
        import struct
        import termios
        import time
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lease = root / "lease"
            lease.write_text("wait\n")
            output = root / "opened"
            master, slave = pty.openpty()
            self.addCleanup(os.close, master)
            self.addCleanup(os.close, slave)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
            app = root / "app.py"
            app.write_text("from pathlib import Path\nimport sys\nPath(sys.argv[1]).write_text('started')\n")
            child = subprocess.Popen([sys.executable, str(REPO / "lib/layout_terminal.py"), str(lease), "80", "24", sys.executable, str(app), str(output)], stdin=slave, stdout=slave, stderr=slave)
            try:
                time.sleep(0.2)
                self.assertIsNone(child.poll())
                self.assertFalse(output.exists())
                lease.write_text("ready\n")
                self.assertEqual(child.wait(timeout=5), 0)
                self.assertEqual(output.read_text(), "started")
                self.assertEqual(Path(str(lease) + ".result").read_text(), "ready\n")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()


if __name__ == "__main__":
    unittest.main()
