#!/usr/bin/env python3
"""Native Apps adapter contracts; GIO fixtures run on Linux, portable checks everywhere."""
import ctypes.util
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ADAPTER = Path(__file__).resolve().parents[1] / "lib/apps.py"
spec = importlib.util.spec_from_file_location("native_apps", ADAPTER)
apps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apps)


class Contracts(unittest.TestCase):
    def test_invalid_requests_are_data_errors(self):
        for data in ([], "text", 3, None):
            with self.assertRaises(ValueError):
                apps.request(data)

    def test_exact_window_identity_and_compositor_focus_order(self):
        one = {"id": 1, "app_id": "org.example.Editor", "name": "one"}
        two = {"id": 2, "app_id": "org.example.Editor", "name": "two"}
        wrong = {"id": 3, "app_id": "unrelated", "name": "org.example.Editor"}
        tree = {"nodes": [one, wrong], "floating_nodes": [two], "focus": [2, 3, 1]}
        record = {"id": "org.example.Editor.desktop", "wm_class": "Editor"}
        self.assertEqual([w["id"] for w in apps.matching(record, tree)], [2, 1])
        tree["focus"] = [1, 3, 2]
        self.assertEqual([w["id"] for w in apps.matching(record, tree)], [1, 2])
        tree["nodes"].append({"id": 4, "window_properties": {"class": "Editor"}})
        self.assertEqual(apps.matching(record, tree)[-1]["id"], 4)

    def test_ambiguous_cross_group_focus_is_never_guessed(self):
        record = {"id":"org.example.Editor.desktop", "wm_class":""}
        editor = {"id":1,"app_id":"org.example.Editor"}
        newer = {"id":2,"app_id":"org.example.Editor"}
        other = {"id":3,"app_id":"different"}
        tree = {"nodes":[{"id":10,"focus":[3,1],"nodes":[editor,other]}, newer],"focus":[10,2]}
        with self.assertRaisesRegex(RuntimeError, "Cannot reliably order"):
            apps.most_recent(record, tree)
        tree["nodes"][0]["focus"] = [1,3]
        self.assertEqual(apps.most_recent(record,tree)["id"],1)


requires_gio = unittest.skipUnless(sys.platform.startswith("linux") and ctypes.util.find_library("gio-2.0"), "native GIO requires Linux")


@requires_gio
class DesktopEntries(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="apps-native-test-")
        self.root = Path(self.tmp.name)
        self.user = self.root / "user/applications"
        self.system = self.root / "system/applications"
        self.user.mkdir(parents=True)
        self.system.mkdir(parents=True)
        self.env = {**os.environ, "HOME": str(self.root), "XDG_DATA_HOME": str(self.user.parent),
                    "XDG_DATA_DIRS": str(self.system.parent), "XDG_CONFIG_HOME": str(self.root / "config")}
        for key in ("SWAYSOCK", "DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS"):
            self.env.pop(key, None)

    def tearDown(self):
        self.tmp.cleanup()

    def desktop(self, name, body, user=True):
        file = (self.user if user else self.system) / name
        file.write_text("[Desktop Entry]\nType=Application\n" + body)
        return file

    def call(self, **data):
        result = subprocess.run([sys.executable, str(ADAPTER)], input=json.dumps(data), env=self.env,
                                capture_output=True, text=True, timeout=20, check=True)
        return json.loads(result.stdout)

    def test_precedence_hidden_nodisplay_tryexec_and_lowercase_names(self):
        self.desktop("org.example.Editor.desktop", "Name=System Editor\nExec=/bin/true\n", False)
        self.desktop("org.example.Editor.desktop", "Name=User EDITOR\nExec=/bin/true\nCategories=Development;Utility;\n")
        self.desktop("hidden.desktop", "Name=Hidden\nExec=/bin/true\nHidden=true\n")
        self.desktop("nodisplay.desktop", "Name=Internal\nExec=/bin/true\nNoDisplay=true\n")
        self.desktop("missing.desktop", "Name=Missing\nExec=/bin/true\nTryExec=/this-does-not-exist/apps-test\n")
        catalog = self.call(op="catalog")["apps"]
        self.assertEqual([a["name"] for a in catalog], ["user editor"])
        self.assertEqual(catalog[0]["id"], "org.example.Editor.desktop")
        self.assertEqual(catalog[0]["categories"], ["Development", "Utility"])
        self.assertFalse(catalog[0]["focus"])

    def test_metadata_is_never_executed_and_paths_keep_spelling(self):
        sentinel = self.root / "not-executed"
        launcher = self.desktop("org.example.Untrusted.desktop", "Name=Untrusted\nComment=$(touch " + str(sentinel) + ")\nExec=/bin/touch " + str(sentinel) + "\n")
        self.call(op="catalog")
        details = self.call(op="details", id=launcher.name)
        self.assertEqual(details["id"], launcher.name)
        fields = dict(details["fields"])
        self.assertEqual(fields["Launcher"], str(launcher))
        self.assertTrue(fields["Access"].startswith("Not declared"))
        self.assertEqual(details["version"], "Unavailable")
        self.assertFalse(sentinel.exists())
        self.assertIn("error", self.call(op="details", id=str(launcher)))

    def test_short_roles_are_localized_and_comments_remain_available(self):
        self.desktop("editor.desktop", "Name=Editor\nGenericName=Text Editor\nGenericName[fr]=Editeur de texte\nComment=Write documents and edit source files\nExec=/bin/true\n")
        self.desktop("missing.desktop", "Name=Missing\nComment=A verbose comment without a generic name\nExec=/bin/true\n")
        self.env.update(LANG="C.UTF-8", LC_ALL="C.UTF-8", LANGUAGE="fr")
        entries = {a["id"]: a for a in self.call(op="catalog")["apps"]}
        self.assertEqual(entries["editor.desktop"]["generic_name"], "Editeur de texte")
        self.assertEqual(entries["editor.desktop"]["description"], "Write documents and edit source files")
        self.assertEqual(entries["missing.desktop"]["generic_name"], "")

    def test_supplied_short_name_keeps_full_name_for_search_and_identity(self):
        self.desktop("firefox.desktop", "Name=Firefox\nName[fr]=Firefox court\nX-GNOME-FullName=Mozilla Firefox\nX-GNOME-FullName[fr]=Mozilla Firefox complet\nExec=/bin/true\n")
        self.desktop("mpv.desktop", "Name=mpv Media Player\nExec=/bin/true\n")
        self.env.update(LANG="C.UTF-8", LC_ALL="C.UTF-8", LANGUAGE="fr")
        entries = {a["id"]: a for a in self.call(op="catalog")["apps"]}
        self.assertEqual(entries["firefox.desktop"]["name"], "firefox court")
        self.assertEqual(entries["firefox.desktop"]["display_name"], "Mozilla Firefox complet")
        self.assertEqual(entries["mpv.desktop"]["name"], "mpv media player")

    def test_default_and_declared_new_window_use_gio_field_codes(self):
        output = self.root / "args.json"
        program = self.root / "record-arguments"
        program.write_text("#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\nPath(" + repr(str(output)) + ").write_text(json.dumps(sys.argv[1:]))\n")
        program.chmod(0o700)
        launcher = self.desktop("org.example.Launch.desktop", 'Name=Mixed CASE\nExec=' + str(program) + ' "literal argument" %c %k\nActions=new-window;\n\n[Desktop Action new-window]\nName=New window\nExec=' + str(program) + ' new-window\n')
        receipt = self.call(op="launch", id=launcher.name, mode="default")
        self.assertFalse(receipt["confirmed"])
        import time
        for _ in range(50):
            if output.exists(): break
            time.sleep(.02)
        self.assertEqual(json.loads(output.read_text()), ["literal argument", "Mixed CASE", str(launcher)])
        output.unlink()
        self.call(op="launch", id=launcher.name, mode="new")
        for _ in range(50):
            if output.exists(): break
            time.sleep(.02)
        self.assertEqual(json.loads(output.read_text()), ["new-window"])

    def test_missing_app_unsupported_mode_and_launch_failures_are_diagnostics(self):
        self.desktop("broken.desktop", "Name=Broken\nExec=/this-does-not-exist/apps-test\n")
        self.assertIn("error", self.call(op="launch", id="broken.desktop", mode="default"))
        self.assertIn("error", self.call(op="launch", id="broken.desktop", mode="new"))
        self.assertIn("error", self.call(op="launch", id="broken.desktop", mode="focus"))
        self.assertIn("error", self.call(op="details", id="gone.desktop"))
        self.assertEqual(self.call(op="catalog")["apps"], [], "GIO excludes an unavailable executable")


if __name__ == "__main__":
    unittest.main()
