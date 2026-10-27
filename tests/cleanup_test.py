#!/usr/bin/env python3
"""A real dash SIGPIPE must run cleanup, even at the bar's first write."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class Cleanup(unittest.TestCase):
    @unittest.skipUnless(shutil.which("dash"), "dash is required to reproduce the signal behavior")
    def test_closed_output_pipe_removes_owned_temp_and_bar_pid(self):
        for command in (["status"], ["bar", "status"], ["--help"]):
            with self.subTest(command=command), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                mktemp = shutil.which("mktemp")
                programs = {"uname": "#!/bin/sh\necho Linux\n", "mktemp": '#!/bin/sh\nx=$("$CLEANUP_MKTEMP" -d "$CLEANUP_ROOT/owned.XXXXXX")\nprintf "%s\\n" "$x" >> "$CLEANUP_ROOT/created"\nprintf "%s\\n" "$x"\n'}
                for name, text in programs.items():
                    path = bin_dir / name
                    path.write_text(text)
                    path.chmod(0o755)
                env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                       "CLEANUP_ROOT": tmp, "CLEANUP_MKTEMP": mktemp,
                       "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                       "SPARK_SHELL_SYS": str(root / "sys"), "SPARK_SHELL_PROC": str(root / "proc")}
                reader, writer = os.pipe()
                os.close(reader)  # no reader exists before even the first write
                try:
                    process = subprocess.Popen([shutil.which("dash"), str(REPO / "spark-shell"), *command],
                                               stdout=writer, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL, env=env)
                finally:
                    os.close(writer)
                process.communicate(timeout=15)
                self.assertIn(process.returncode, (0, 1, 141))
                self.assertTrue((root / "created").exists(), "the test must observe a created folder")
                self.assertEqual(list(root.glob("owned.*")), [])
                self.assertFalse((root / "state/spark-shell/bar.pid").exists())


if __name__ == "__main__":
    unittest.main()
