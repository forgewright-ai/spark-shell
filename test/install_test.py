#!/usr/bin/env python3
"""Installer transactions in an isolated HOME, with no native package manager."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class Install(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bins = self.root / "bin"
        self.bins.mkdir()
        # An allowlist keeps host services, downloads and package managers unreachable.
        for name in ("sh", "dirname", "sed", "tr", "grep", "sort", "paste", "cut", "awk",
                     "mktemp", "rm", "mkdir", "cat", "date", "readlink", "jq", "ln", "chmod",
                     "env", "head", "tail", "wc", "basename", "cp", "mv", "find", "cmp",
                     "touch", "rmdir", "python3", "cksum", "printf", "ls"):
            if path := shutil.which(name):
                (self.bins / name).symlink_to(path)
        self.stub("uname", "echo Linux")
        self.stub("id", 'case "$1" in -u) echo 0 ;; -un) echo fixture ;; *) echo fixture ;; esac')
        self.stub("sudo", '[ "${1:-}" != -n ] || shift; exec "$@"')
        self.stub("tty", "exit 1")
        self.stub("pacman", '''case "$1" in
    -Qq) [ "$2" != pulseaudio ] && [ -e "$HOME/installed" ]; exit $? ;;
esac
printf '%s\\n' "$*" >> "$HOME/transactions"
if [ -e "$HOME/fail" ] || { [ "$1" != -Syu ] && [ ! -e "$HOME/allow-stale" ]; }; then
    echo 'error: failed retrieving file: The requested URL returned error: 404' >&2
    exit 1
fi
: > "$HOME/installed"
''')
        self.stub("systemctl", 'printf "%s\\n" "$*" >> "$HOME/services"')
        self.os_release = self.root / "os-release"
        self.os_release.write_text("ID=arch\n")
        self.native = self.root / "native"
        (self.native / "run/systemd/system").mkdir(parents=True)
        self.config = self.root / ".config/spark-shell/config"
        self.env = {
            "HOME": str(self.root), "PATH": str(self.bins), "LC_ALL": "C", "TERM": "dumb",
            "XDG_CONFIG_HOME": str(self.root / ".config"),
            "XDG_STATE_HOME": str(self.root / ".local/state"),
            "XDG_DATA_HOME": str(self.root / ".local/share"),
            "SPARK_SHELL_ROOT": str(self.native), "SPARK_OS_RELEASE": str(self.os_release),
            "SPARK_SHELL_DEV": str(self.root / "dev"),
            "SPARK_SHELL_PTS_DIR": str(self.root / "pts"),
            "SPARK_SHELL_FONT_URL": "none", "SPARK_SHELL_DIALOG_URL": "none",
            "FONT": "DejaVu Sans Mono:size=12", "THEME": "none",
            "SPARK_SHELL_TEST_TTY": "1",   # a person at the terminal; the no-terminal tests clear it
        }

    def stub(self, name, body):
        path = self.bins / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def run_shell(self, *args, answer="", **env):
        return subprocess.run(["/bin/sh", str(REPO / "spark-shell"), *args],
                              env={**self.env, **env}, input=answer, text=True,
                              capture_output=True, timeout=30)

    def transactions(self):
        path = self.root / "transactions"
        return path.read_text().splitlines() if path.exists() else []

    def test_stale_database_is_refreshed_with_full_upgrade(self):
        result = self.run_shell("on", "--yes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.transactions()), 1)
        args = self.transactions()[0].split()
        self.assertEqual(args[:2], ["-Syu", "--needed"])
        self.assertNotIn("--noconfirm", args)
        self.assertTrue((self.root / ".bash_profile").exists())

    def test_package_failure_preserves_files_and_startup_choices(self):
        original = "DESKTOP=none\nLOGIN=no\nFONT=DejaVu Sans Mono:size=12\n"
        self.config.parent.mkdir(parents=True)
        self.config.write_text(original)
        profile = self.root / ".bash_profile"
        profile.write_text("# existing login shell\n")
        (self.root / "fail").touch()
        for args in (("on", "desktop"), ("desktop", "on"), ("on", "login"),
                     ("login", "on"), ("apply",)):
            with self.subTest(args=args):
                result = self.run_shell(*args, "--yes")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("404", result.stderr)
                self.assertEqual(self.config.read_text(), original)
                self.assertEqual(profile.read_text(), "# existing login shell\n")
                self.assertFalse((self.root / ".config/sway/config").exists())
                self.assertFalse((self.root / "services").exists())
                self.assertNotIn("open a new shell", result.stdout)
                self.assertNotIn("render look", result.stdout)

    def test_failed_first_install_does_not_save_desktop_choice(self):
        (self.root / "fail").touch()
        result = self.run_shell("on", "desktop", "--yes")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.config.exists())
        self.assertFalse((self.root / ".bash_profile").exists())

    def test_successful_retry_commits_desktop_choice(self):
        (self.root / "fail").touch()
        self.assertNotEqual(self.run_shell("on", "desktop", "--yes").returncode, 0)
        (self.root / "fail").unlink()
        result = self.run_shell("on", "desktop", "--yes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("DESKTOP=sway\n", self.config.read_text())
        self.assertTrue((self.root / ".config/sway/config").exists())

    def test_dry_run_does_not_install_or_save_configuration(self):
        result = self.run_shell("on", "desktop", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.transactions())
        self.assertFalse(self.config.exists())
        self.assertFalse((self.root / ".bash_profile").exists())
        self.assertIn("full system upgrade", result.stdout.lower())

    def test_installed_dependencies_do_not_trigger_upgrade(self):
        (self.root / "installed").touch()
        result = self.run_shell("on", "--yes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.transactions())

    def test_rejected_consent_mentions_upgrade_and_changes_nothing(self):
        for args in (("on",), ("on", "desktop"), ("on", "login")):
            with self.subTest(args=args):
                result = self.run_shell(*args, answer="n\n", SPARK_SHELL_TEST_TTY="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("full system upgrade", result.stdout.lower())
                self.assertFalse(self.transactions())
                self.assertFalse(self.config.exists())
                self.assertFalse((self.root / ".bash_profile").exists())

    def test_retry_hint_has_one_space_and_never_the_upgrade_that_failed(self):
        (self.root / "fail").touch()
        for args, hint in ((("on",), "run spark-shell on again"),
                           (("on", "desktop"), "run spark-shell on desktop again"),
                           (("apply",), "run spark-shell on again")):
            with self.subTest(args=args):
                result = self.run_shell(*args, "--yes")
                self.assertIn(hint, result.stdout)
                self.assertNotIn("on  ", result.stdout)
                self.assertNotIn("sudo pacman -Syu", result.stdout)

    def test_no_terminal_never_reaches_pacmans_question(self):
        result = self.run_shell("on", "--yes", SPARK_SHELL_TEST_TTY="")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.transactions(), "pacman asks, and nobody is here")
        self.assertIn("pacman asks before it upgrades", result.stdout)
        self.assertIn("so they go on", result.stdout)
        self.assertTrue((self.root / ".bash_profile").exists(), "update must still render")

    def test_no_terminal_desktop_or_login_waits_for_its_packages(self):
        for args in (("on", "desktop"), ("on", "login")):
            with self.subTest(args=args):
                result = self.run_shell(*args, "--yes", SPARK_SHELL_TEST_TTY="")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.transactions())
                self.assertFalse(self.config.exists())
                self.assertFalse((self.root / ".bash_profile").exists())
                self.assertFalse((self.root / ".config/sway/config").exists())

    def test_no_terminal_dry_run_says_and_stops_nothing(self):
        result = self.run_shell("on", "desktop", "--dry-run", SPARK_SHELL_TEST_TTY="")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("still to install", result.stdout)

    def test_network_setup_keeps_its_package_transaction(self):
        (self.root / "allow-stale").touch()
        result = self.run_shell("desktop", "network", "setup", "--yes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.transactions(), ["-S --needed --noconfirm networkmanager"])


class Families(Install):
    """The stop on a failed install holds off Arch too: it is on the shared path (#217)."""
    STUBS = {
        "debian": {"apt-get": 'case "$1" in update) exit 0 ;; esac\n%(act)s',
                   "dpkg-query": '[ -e "$HOME/installed" ] && echo "install ok installed"'},
        "void": {"xbps-install": "%(act)s",
                 "xbps-query": '[ -e "$HOME/installed" ]'},
        "fedora": {"dnf": "%(act)s", "rpm": '[ -e "$HOME/installed" ]'},
        "opensuse": {"zypper": "%(act)s", "rpm": '[ -e "$HOME/installed" ]'},
    }
    SAID = {"debian": "failed (see above) -- run spark-shell on desktop again",
            "void": "sudo xbps-install -Su, then spark-shell on desktop",
            "fedora": "sudo dnf upgrade --refresh, then spark-shell on desktop",
            "opensuse": "sudo zypper dup, then spark-shell on desktop"}
    ACT = '''printf '%s\\n' "$*" >> "$HOME/transactions"
[ ! -e "$HOME/fail" ] || { echo 'error: no such package' >&2; exit 1; }
: > "$HOME/installed"'''

    def family(self, name):
        (self.bins / "pacman").unlink()
        self.os_release.write_text("ID=%s\n" % name)
        for tool, body in self.STUBS[name].items():
            self.stub(tool, body % {"act": self.ACT} if "%(act)s" in body else body)

    def test_a_failed_install_stops_each_family_and_the_retry_runs_to_the_end(self):
        for name in self.STUBS:
            with self.subTest(family=name):
                self.setUp()
                self.family(name)
                (self.root / "fail").touch()
                result = self.run_shell("on", "desktop", "--yes")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(self.transactions(), "the manager was asked")
                self.assertIn(self.SAID[name], result.stdout)
                self.assertNotIn("on  ", result.stdout)
                self.assertFalse(self.config.exists())
                self.assertFalse((self.root / ".bash_profile").exists())
                self.assertFalse((self.root / ".config/sway/config").exists())
                (self.root / "fail").unlink()
                result = self.run_shell("on", "desktop", "--yes")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("DESKTOP=sway\n", self.config.read_text())
                self.assertTrue((self.root / ".config/sway/config").exists())


for _name in [n for n in vars(Install) if n.startswith("test_")]:
    setattr(Families, _name, None)   # the Arch tests run once, in Install


if __name__ == "__main__":
    unittest.main()
