#!/usr/bin/env python3
"""Native Apps adapter contracts; GIO fixtures run on Linux, portable checks everywhere."""
import ctypes.util
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import struct
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

    def test_home_on_top_of_the_workspace_orders_nothing(self):
        # Home is focused whenever it asks: with the app on two workspaces its
        # own window must not read as a third group's newest window.
        record = {"id":"org.example.Editor.desktop", "wm_class":""}
        here = {"id":2,"app_id":"org.example.Editor"}
        home = {"id":3,"app_id":"spark-dialog"}
        there = {"id":4,"app_id":"org.example.Editor"}
        tree = {"id":0,"focus":[10,11],"nodes":[
            {"id":10,"focus":[3,2],"nodes":[here],"floating_nodes":[home]},
            {"id":11,"focus":[4],"nodes":[there],"floating_nodes":[]}]}
        self.assertEqual(apps.most_recent(record, tree)["id"], 2)

    def test_a_large_compositor_tree_is_parsed_whole(self):
        tree = {"nodes": [{"id": n, "app_id": "x", "name": "w" * 400} for n in range(1000)]}
        text = json.dumps(tree)
        self.assertGreater(len(text), 131072)
        real_run, real_which = apps.subprocess.run, apps.shutil.which
        apps.subprocess.run = lambda *a, **k: subprocess.CompletedProcess(a, 0, text, "")
        apps.shutil.which = lambda name: "/bin/" + name
        os.environ["SWAYSOCK"] = "fixture"
        try:
            self.assertEqual(len(apps.sway_tree()["nodes"]), 1000)
        finally:
            apps.subprocess.run, apps.shutil.which = real_run, real_which
            del os.environ["SWAYSOCK"]

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
                    "XDG_DATA_DIRS": str(self.system.parent), "XDG_CONFIG_HOME": str(self.root / "config"),
                    "XDG_STATE_HOME": str(self.root / ".local/state")}
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

    @unittest.skipUnless(shutil.which("rsvg-convert"), "rsvg-convert draws the icons")
    def test_icons_are_drawn_at_the_size_asked_into_the_state_cache_and_nothing_else_is_read(self):
        # #230: a theme's drawing, a theme's PNG, a path; a name that climbs out of the themes, or names a file
        # that is no icon, gives none; nothing is drawn without a size asked
        hicolor = self.system.parent / "icons/hicolor"
        (hicolor / "scalable/apps").mkdir(parents=True)
        (hicolor / "48x48/apps").mkdir(parents=True)
        (hicolor / "16x16/apps").mkdir(parents=True)
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#3366cc"/></svg>'
        (hicolor / "scalable/apps/drawn-app.svg").write_text(svg)
        source = self.root / "source.svg"
        source.write_text(svg)
        subprocess.run(["rsvg-convert", "-w", "48", "-h", "48", "-o", str(hicolor / "48x48/apps/png-app.png"), str(source)], check=True)
        subprocess.run(["rsvg-convert", "-w", "16", "-h", "16", "-o", str(hicolor / "16x16/apps/png-app.png"), str(source)], check=True)
        (self.root / "secret.txt").write_text("not an icon")
        for name, icon in [("drawn", "drawn-app"), ("png", "png-app"), ("path", str(hicolor / "48x48/apps/png-app.png")),
                           ("climb", "../../../secret"), ("text", str(self.root / "secret.txt")), ("missing", "no-such-icon"), ("none", "")]:
            self.desktop("org.example.%s.desktop" % name, "Name=%s\nExec=/bin/true\nIcon=%s\n" % (name, icon))
        plain = {a["name"]: a for a in self.call(op="catalog")["apps"]}
        self.assertTrue(all("icon" not in a for a in plain.values()), "no size asked, nothing drawn")
        apps = {a["name"]: a for a in self.call(op="catalog", icon_px=18)["apps"]}
        cache = self.root / ".local/state/spark-shell/icons/18"
        for name in ("drawn", "png", "path"):
            icon = Path(apps[name]["icon"])
            self.assertEqual(icon.parent, cache, name)
            data = icon.read_bytes()
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"), name)
            self.assertEqual(struct.unpack(">II", data[16:24]), (18, 18), name)
        for name in ("climb", "text", "missing", "none"):
            self.assertNotIn("icon", apps[name], name)
        self.assertEqual(stat.S_IMODE(cache.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(cache.parent.stat().st_mode), 0o700)
        # drawn once: the same file at the next read, untouched
        before = {n: Path(apps[n]["icon"]).stat().st_mtime_ns for n in ("drawn", "png")}
        again = {a["name"]: a for a in self.call(op="catalog", icon_px=18)["apps"]}
        self.assertEqual({n: Path(again[n]["icon"]).stat().st_mtime_ns for n in before}, before)
        self.assertEqual(sorted(p.name for p in cache.iterdir() if p.name.startswith(".")), [], "no temporary file left")
        for bad in (0, 7, 257, "18", True, 18.5):
            self.assertIn("error", self.call(op="catalog", icon_px=bad), bad)

    def test_precedence_hidden_nodisplay_tryexec_and_supplied_names(self):
        self.desktop("org.example.Editor.desktop", "Name=System Editor\nExec=/bin/true\n", False)
        self.desktop("org.example.Editor.desktop", "Name=User EDITOR\nExec=/bin/true\nCategories=Development;Utility;\n")
        self.desktop("hidden.desktop", "Name=Hidden\nExec=/bin/true\nHidden=true\n")
        self.desktop("nodisplay.desktop", "Name=Internal\nExec=/bin/true\nNoDisplay=true\n")
        self.desktop("missing.desktop", "Name=Missing\nExec=/bin/true\nTryExec=/this-does-not-exist/apps-test\n")
        catalog = self.call(op="catalog")["apps"]
        self.assertEqual([a["name"] for a in catalog], ["User EDITOR"], "the name as the entry writes it")
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
        self.assertEqual(entries["firefox.desktop"]["name"], "Firefox court")
        self.assertEqual(entries["firefox.desktop"]["display_name"], "Mozilla Firefox complet")
        self.assertEqual(entries["mpv.desktop"]["name"], "mpv Media Player")

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
