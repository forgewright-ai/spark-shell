#!/usr/bin/env python3
"""Apps in native Sway/foot on an isolated desktop; real system discovery.

python3 tests/apps_desktop_proof.py BINARY EVIDENCE_DIRECTORY
Uses the host's desktop entries read-only and a temporary preference directory.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

from home_desktop_proof import Pointer, native_foot_config, wait_for

REPO = Path(__file__).resolve().parents[1]


class Session:
    def __init__(self, binary, destination):
        self.binary = str(Path(binary).resolve())
        self.binary_sha256 = hashlib.sha256(Path(self.binary).read_bytes()).hexdigest()
        self.evidence = Path(destination).resolve()
        self.evidence.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix="apps-proof-")
        self.root = Path(self.tmp.name)
        (self.root / ".bashrc").write_text("PS1='preview$ '\n")
        (self.root / ".zshrc").write_text("PROMPT='preview% '\n")
        runtime = self.root / "run"
        runtime.mkdir(mode=0o700)
        config = self.root / ".config/spark-shell"
        config.mkdir(parents=True)
        (config / "config").write_text("DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\nDIALOG_ATTACH=yes\nDIALOG_TALK=yes\nDIALOG_MODEL=yes\n")
        theme = self.root / ".config/spark"
        theme.mkdir()
        shutil.copyfile(REPO / "themes/tokyonight-night.env", theme / "theme.env")
        fixtures = self.root / "bin"
        fixtures.mkdir()
        spark = fixtures / "spark"
        spark.write_text("#!/bin/sh\ncase $1 in model) printf 'fixture-model\\tserving\\n';; client) echo 'spark client -- local';; voice) echo 'voice ready';; esac\n")
        spark.chmod(0o700)
        foot = self.root / ".config/foot"
        foot.mkdir()
        colors, self.palette = native_foot_config(self.root)
        dump = fixtures / "screen-dump"
        dump.write_text("from pathlib import Path\nimport sys\n(Path.home() / 'screen.txt').write_text(sys.stdin.read())\n")
        template = (REPO / "templates/.config/foot/dialog.ini").read_text()
        for old, new in {"@HOME@": str(self.root), "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "18x18", "@FOOT_COLORS@": colors, "@PANEL_BG@": self.palette["colors"]["PANEL_BG"]}.items():
            template = template.replace(old, new)
        template += "\n[key-bindings]\npipe-visible=[python3 " + str(dump) + "] Control+Shift+F12\n"
        (foot / "dialog.ini").write_text(template)
        (self.root / "long-attachment-for-apps-review.md").write_text("Native attachment fixture.\n")
        adapter_mode = self.root / "adapter-mode"
        # Only failure-state checks replace a native adapter response. Discovery,
        # normal launches and all primary screenshots use the real adapter.
        python = fixtures / "python3"
        python.write_text("#!" + sys.executable + "\n" +
            "import json,os,sys\nfrom pathlib import Path\n" +
            "mode = Path(" + repr(str(adapter_mode)) + ")\n" +
            "if len(sys.argv)>1 and sys.argv[1].endswith('/lib/apps.py') and mode.exists():\n" +
            "    request=json.load(sys.stdin); state=mode.read_text()\n" +
            "    if request['op']=='catalog' and state=='empty': print(json.dumps({'apps':[]})); sys.exit()\n" +
            "    if request['op']=='catalog' and state=='discovery': print(json.dumps({'error':'Fixture: native discovery unavailable'})); sys.exit()\n" +
            "    if request['op']=='launch' and state=='launch': print(json.dumps({'error':'Fixture: native launch refused'})); sys.exit()\n" +
            "os.execv(" + repr(sys.executable) + ", [" + repr(sys.executable) + "]+sys.argv[1:])\n")
        python.chmod(0o700)
        self.env = {**os.environ, "HOME": str(self.root), "XDG_CONFIG_HOME": str(self.root / ".config"),
                    "XDG_RUNTIME_DIR": str(runtime), "XDG_STATE_HOME": str(self.root / "state"), "XDG_DATA_HOME": str(self.root / "data"),
                    "PATH": str(fixtures) + os.pathsep + os.environ["PATH"],
                    "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
                    "SPARK_SHELL_DIALOG": self.binary, "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_PTS_DIR": str(self.root / "ptys")}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY"):
            self.env.pop(key, None)
        sway = self.root / "sway.conf"
        source = (REPO / "templates/.config/sway/config").read_text().replace("@REPO@", str(REPO))
        keys = [line for line in source.splitlines() if line.startswith("bindsym ") and
                ("desktop home" in line or "focus mode_toggle" in line or "desktop window" in line or line.endswith(" fullscreen"))]
        sway.write_text('set $mod Mod4\noutput HEADLESS-1 mode 1440x1000\nxwayland disable\n'
                        'bar {\n position top\n height 28\n font pango:monospace 10\n}\nseat seat0 fallback true\n'
                        'for_window [app_id="spark-dialog"] floating enable, border none, move position center\n' + "\n".join(keys) + "\n")
        self.log = (self.root / "native.log").open("w")
        self.compositor = subprocess.Popen(["sway", "-c", str(sway)], env=self.env, cwd=self.root, stdout=self.log, stderr=self.log)
        self.env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "Sway"))
        self.env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "Wayland")
        self.pointer = Pointer(self.env)
        self.keyboard = subprocess.Popen(["wtype", "-s", "600000"], env=self.env, stdout=self.log, stderr=self.log)
        self.captures, self.checks = {}, []
        self.key("-M", "logo", "-k", "space", "-m", "logo")
        self.first = wait_for(lambda: self.window(), "home")
        time.sleep(3)
        rect = self.first["rect"]
        self.cell = ((rect["width"] - 36) // 60, (rect["height"] - 36) // 40)
        self.area = next(w["rect"] for w in self.sway("-t", "get_workspaces") if w["focused"])

    def sway(self, *args):
        return json.loads(subprocess.check_output(["swaymsg", "-r", *args], env=self.env, timeout=5))

    def window(self):
        def walk(node):
            if node.get("app_id") == "spark-dialog":
                return node
            for child in node.get("nodes", []) + node.get("floating_nodes", []):
                found = walk(child)
                if found:
                    return found
        return walk(self.sway("-t", "get_tree"))

    def key(self, *args):
        subprocess.run(["wtype", "-s", "100", *args, "-s", "100"], env=self.env, check=True, timeout=5)
        time.sleep(.2)

    def screen(self):
        file = self.root / "screen.txt"
        file.unlink(missing_ok=True)
        self.key("-M", "ctrl", "-M", "shift", "-k", "F12", "-m", "shift", "-m", "ctrl")
        wait_for(file.exists, "terminal text")
        return [line.rstrip() for line in file.read_text().splitlines()]

    def text(self):
        return "\n".join(self.screen())

    def focus(self):
        ident = self.window()["id"]
        self.key("-M", "logo", "-k", "space", "-m", "logo")
        assert self.window()["id"] == ident, "Super+Space replaced home instead of returning to it"
        time.sleep(.3)

    def click(self, label, body=False):
        # Scroll through the real keyboard path, then derive coordinates from
        # the current terminal text, never from a pre-resize capture.
        match = re.compile(r"(?<!\w)" + re.escape(label) + r"(?!\w)")
        if label in ("Save", "Cancel", "Discard", "Keep editing"):
            match = re.compile(r"^\s*(?:\u203a\s*)?" + re.escape(label) + r"\s*$")
        for _ in range(80):
            lines = self.screen()
            if any(match.search(line) for line in (lines[7:] if body else lines)):
                break
            self.key("-k", "Down")
        else:
            raise AssertionError("control not found: " + label + "\n" + self.text())
        row = next(i for i, line in enumerate(lines) if match.search(line) and (not body or i >= 7))
        col = lines[row].index(label) + len(label) // 2
        rect = self.window()["rect"]
        self.pointer.click(rect["x"] + 18 + col * self.cell[0] + self.cell[0] // 2,
                           rect["y"] + 18 + row * self.cell[1] + self.cell[1] // 2)
        time.sleep(.4)

    def settled(self):
        def current():
            rect = self.window()["rect"]
            cols = (rect["width"] - 36) // self.cell[0]
            rows = (rect["height"] - 36) // self.cell[1]
            lines = self.screen()
            title = 2 + (cols - min(cols, 120)) // 2
            good = re.search(r"\b(home|apps|files|conversation)\b", lines[0]) is not None and len(lines[0]) - len(lines[0].lstrip()) == title and any("Attach" in line or "Remove" in line for line in lines[max(0, rows-3):])
            return good
        wait_for(current, "terminal redraw after resize")
        time.sleep(.3)

    def capture(self, name, whole=True):
        self.settled()
        if name.startswith(("apps-", "details-")):
            lines = self.screen()
            inset = lambda line: len(line) - len(line.lstrip())
            assert inset(lines[7]) == inset(lines[0]), "Apps body must share the header's left anchor"
        rect = self.window()["rect"]
        geometry = "{x},{y} {width}x{height}".format(**rect)
        subprocess.run(["grim", *(["-o", "HEADLESS-1"] if whole else ["-g", geometry]), str(self.evidence / (name + ".png"))], env=self.env, check=True)
        self.captures[name] = {**rect, "full_output": whole}
        print("captured: " + name, flush=True)

    def normal(self):
        if self.window()["fullscreen_mode"]:
            self.key("-M", "logo", "-k", "f", "-m", "logo")
        self.sway("[con_id=%d] resize set width %d px height %d px, move position center" %
                  (self.window()["id"], self.first["rect"]["width"], self.first["rect"]["height"]))
        time.sleep(1)

    def four_modes(self, name, capture=True):
        self.normal()
        if capture: self.capture(name + "-compact")
        self.key("-M", "logo", "-k", "f", "-m", "logo")
        time.sleep(1)
        self.settled()
        if capture: self.capture(name + "-fullscreen")
        self.key("-M", "logo", "-k", "f", "-m", "logo")
        screens = []
        for key, side in [("Left", "left"), ("Right", "right")]:
            self.key("-M", "logo", "-k", key, "-m", "logo")
            time.sleep(1)
            rect = self.window()["rect"]
            assert rect == {"x": 0 if side == "left" else 720, "y": 28, "width": 720, "height": 972}, rect
            self.settled()
            if capture: self.capture(name + "-snap-" + side)
            screens.append(self.screen()[1:])
        assert screens[0] == screens[1], "equal snap regions must compose equally"
        self.normal()
        self.settled()

    def close(self):
        self.keyboard.terminate()
        self.keyboard.wait(timeout=5)
        self.pointer.close()
        self.compositor.terminate()
        self.compositor.wait(timeout=10)
        self.log.close()
        self.tmp.cleanup()


def main(binary, destination):
    s = Session(binary, destination)
    try:
        s.key("apps", "-k", "Return")
        wait_for(lambda: "btop" in "\n".join(s.screen()), "Apps catalog")
        text = s.text()
        assert "System Monitor" in text and "Web Browser" in text
        assert "Resource monitor that" not in text and "A wayland native" not in text
        s.key("usage")
        assert "btop" in s.text(), "full desktop comments remain searchable"
        s.key("-k", "Escape")
        s.key("system monitor")
        assert "btop" in s.text(), "displayed roles remain searchable"
        s.key("-k", "Escape")
        s.checks.append("Browse uses concise desktop-entry roles; role and full-comment searches both find the installed app")
        s.four_modes("apps")
        s.sway("[con_id=%d] resize set width 396 px height 416 px, move position center" % s.window()["id"])
        s.capture("apps-minimum")
        s.normal()
        s.key("btop")
        s.four_modes("query", capture=False)
        assert "btop" in s.screen()[2], "resize lost the search"
        s.click("\u2192")  # the physical keycap opens Details through the same action
        wait_for(lambda: "Preferences" in "\n".join(s.screen()), "application Details")
        time.sleep(1)
        s.four_modes("details")
        s.checks.append("Real system Apps and on-demand btop Details render in compact, fullscreen and equal work-area snaps")
        s.key("-k", "Escape")
        assert "btop" in "\n".join(s.screen()), "Details returns to its query"
        s.checks.append("Returning from Details restores the app search; active query and selected app survive all four modes; clicked Right keycap opens Details")
        s.key("-k", "Right")
        s.click("Visibility")
        assert "Unsaved preferences" in s.text()
        s.click("Technical details")
        s.four_modes("expanded-unsaved", capture=False)
        assert "Identity" in s.text(), "resize collapsed Technical details"
        s.click("Save")
        preferences = s.root / ".config/spark-shell/apps.json"
        saved = json.loads(preferences.read_text())
        assert saved["apps"]["btop.desktop"]["hidden"]
        s.key("-k", "Escape")
        assert "No apps match" in s.text()
        s.capture("hidden-search")
        s.click("Show hidden apps")
        assert "hidden: btop" in s.text()
        s.key("-k", "Down", "-k", "Down", "-k", "Right")
        wait_for(lambda: "Technical details" in s.text(), "hidden app Details")
        s.click("Technical details")  # collapse to the compact preferences group
        s.click("Visibility")
        s.click("Save")
        assert not json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"]
        s.checks.append("Hide saves to local preferences, removes search results, labels hidden entries, and restores without editing launchers")
        s.key("-k", "Escape", "-k", "Escape")
        s.click("Manage categories")
        s.click("Create category")
        s.key("Writing", "-k", "Return")
        s.click("Writing")
        s.click("Rename category")
        s.key("Review", "-k", "Return")
        s.click("Default mappings")
        s.click("Development")
        s.click("Review")
        s.click("Save", body=True)
        assert json.loads(preferences.read_text())["mappings"]["Development"] == "Review"
        s.key("-k", "Escape")
        s.click("Delete category")
        s.click("Delete category")
        saved = json.loads(preferences.read_text())
        assert "Review" not in saved["categories"] and "Development" not in saved["mappings"]
        s.checks.append("Native category creation, rename, mapping edit and confirmed deletion persist and reclassify")
        s.key("-k", "Escape")
        s.key("btop", "-k", "Right")
        s.click("Category")
        s.click("Utilities")
        s.click("Save")
        assert json.loads(preferences.read_text())["apps"]["btop.desktop"]["category"] == "Utilities"
        s.click("Attach")
        s.key("long-attachment", "-k", "Down", "-k", "Return")
        wait_for(lambda: "Remove" in s.text(), "attachment")
        assert "apps / btop" in s.text(), "attachment did not return to Details"
        s.click("Technical details")
        s.sway("[con_id=%d] resize set width 396 px height 416 px, move position center" % s.window()["id"])
        time.sleep(2)
        s.settled()
        for _ in range(12):
            if "/usr/share/applications/" in s.text(): break
            s.key("-k", "Next")
        assert "/usr/share/applications/" in s.text(), "technical metadata cannot be scrolled into view"
        s.capture("minimum-long-metadata")
        s.click("Copy launcher path")
        copied = subprocess.check_output(["wl-paste", "--no-newline"], env=s.env, text=True, timeout=5)
        assert copied == "/usr/share/applications/btop.desktop", copied
        wait_for(lambda: "Copied" in s.text(), "clipboard completion receipt")
        s.capture("minimum-technical-attachment")
        s.click("Visibility")
        s.capture("minimum-preferences-attachment")
        s.click("Cancel")
        s.click("Remove")
        assert "Remove" not in s.text()
        s.checks.append("At 36x20, long technical values reflow, original launcher path copies, preferences scroll above the reserved populated footer, and Remove has a current hit target")
        s.normal()
        s.key("-k", "Escape", "-k", "Escape")
        s.key("zz-no-application")
        assert "No apps match" in s.text()
        s.capture("no-matches")
        s.key("-k", "Escape")
        s.key("foot")
        s.key("-k", "Return")
        def app_windows(identity="foot"):
            def walk(node):
                return ([node] if node.get("app_id") == identity else []) + [w for child in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(child)]
            return walk(s.sway("-t", "get_tree"))
        wait_for(app_windows, "real installed foot launch via Enter")
        time.sleep(2)
        assert app_windows(), "application was killed when the helper exited"
        subprocess.run(["grim", "-o", "HEADLESS-1", str(s.evidence / "application-opened.png")], env=s.env, check=True)
        s.focus()
        assert "Opened foot" in s.text(), s.text()
        s.click("foot", body=True)
        wait_for(lambda: len(app_windows()) == 2, "real installed foot launch via click")
        s.focus()
        s.checks.append("Enter and click both launch the installed foot desktop entry; windows outlive the helper; confirmed receipts stay in Apps")
        s.key("-k", "Escape")
        s.key("btop", "-k", "Return")
        time.sleep(2)
        s.focus()
        assert "Opened btop" in s.text(), s.text()
        s.checks.append("The real installed Terminal=true btop entry launches through GIO into foot and its window is confirmed")
        first_btop = app_windows("btop")[0]["id"]
        s.click("btop", body=True)
        wait_for(lambda: len(app_windows("btop")) == 2, "second btop window")
        s.focus()
        s.key("-k", "Right")
        s.click("Launch")
        s.click("Focus existing")
        s.click("Save")
        s.sway("[con_id=%d] focus" % first_btop)
        s.focus()
        s.click("Open application")
        wait_for(lambda: any(w["id"] == first_btop and w["focused"] for w in app_windows("btop")), "most recent matching btop window")
        s.focus()
        assert "Focused btop" in s.text(), s.text()
        s.key("-k", "Escape")
        s.key("-k", "Return")
        wait_for(lambda: any(w["id"] == first_btop and w["focused"] for w in app_windows("btop")), "focus via Enter")
        s.focus()
        s.click("btop", body=True)
        wait_for(lambda: any(w["id"] == first_btop and w["focused"] for w in app_windows("btop")), "focus via click")
        s.focus()
        assert len(app_windows("btop")) == 2
        s.checks.append("With two real btop windows, saved Focus existing selects the most recently focused match; Enter and click share it without opening a third")
        s.sway('[app_id="btop"] kill')
        s.focus()
        s.key("-k", "Return")
        wait_for(lambda: len(app_windows("btop")) == 1, "Focus existing launches when no matching window remains")
        s.focus()
        assert "Opened btop" in s.text()
        s.checks.append("Focus existing starts the installed btop application when no matching window remains")
        # Reopen the same isolated home process with the saved preference file.
        s.sway("[con_id=%d] kill" % s.window()["id"])
        wait_for(lambda: s.window() is None, "home closed")
        s.key("-M", "logo", "-k", "space", "-m", "logo")
        wait_for(s.window, "home restart")
        time.sleep(2)
        s.key("apps", "-k", "Return")
        wait_for(lambda: "btop" in s.text(), "catalog after restart")
        s.key("btop", "-k", "Right")
        wait_for(lambda: "Focus existing" in s.text(), "preferences after restart")
        assert "Utilities" in s.text()
        s.checks.append("After restarting home, btop retains its category override, restored visibility and Focus existing preference")
        s.key("-k", "Escape", "-k", "Escape")
        # A local entry with no package ownership exercises absent metadata.
        entries = s.root / "data/applications"
        entries.mkdir(parents=True, exist_ok=True)
        fixture = entries / "org.example.AppsProof.desktop"
        fixture.write_text("[Desktop Entry]\nType=Application\nName=Inspection Fixture\nComment=Local fixture for missing package metadata and declared desktop actions\nExec=foot --app-id=org.example.AppsProof --title=Apps-proof\nActions=new-window;\n\n[Desktop Action new-window]\nName=New window\nExec=foot --app-id=org.example.AppsProof --title=Apps-proof-new\n")
        s.click("Refresh apps")
        time.sleep(1)
        s.key("inspection", "-k", "Right")
        wait_for(lambda: "Unavailable" in s.text(), "missing package metadata")
        if app_windows() or app_windows("btop"):
            s.sway('[app_id="^(foot|btop)$"] move container to workspace 2')
        s.focus()
        s.capture("missing-metadata")
        s.click("Launch")
        s.click("New window")
        s.click("Save")
        s.click("Open application")
        wait_for(lambda: app_windows("org.example.AppsProof"), "declared New window action")
        s.focus()
        s.key("-k", "Escape")
        s.click("inspection fixture", body=True)
        wait_for(lambda: len(app_windows("org.example.AppsProof")) == 2, "second declared New window action")
        s.focus()
        s.checks.append("A labelled local desktop-entry fixture shows unavailable package metadata; its declared New window action opens two real foot windows through the saved preference")
        s.sway('[app_id="org.example.AppsProof"] move container to workspace 2')
        s.focus()
        mode = s.root / "adapter-mode"
        mode.write_text("launch")
        s.key("-k", "Return")
        wait_for(lambda: "native launch refused" in s.text(), "launch failure receipt")
        assert "inspection" in s.screen()[2]
        s.capture("launch-failure")
        mode.unlink()
        s.key("-k", "Escape")
        mode.write_text("empty")
        s.click("Refresh apps")
        wait_for(lambda: "No launchable" in s.text(), "empty catalog")
        s.capture("empty-catalog")
        mode.write_text("discovery")
        s.click("Refresh apps")
        wait_for(lambda: "Apps unavailable" in s.text(), "discovery failure")
        s.capture("discovery-failure")
        mode.unlink()
        s.click("Refresh apps")
        wait_for(lambda: "btop" in s.text(), "discovery retry")
        s.checks.append("Explicit adapter failure fixtures verify empty catalog versus unavailable discovery, retry recovery, and launch failure retaining the search")
        manifest = {"binary_sha256": s.binary_sha256,
                    "palette": s.palette,
                    "environment": "Void Linux; native headless Sway, foot, GIO; 1440x1000; monospace 12; scale 1",
                    "data": "System desktop entries; temporary Apps preferences; model and voice availability fixtures",
                    "usable_area": s.area, "captures": s.captures, "checks": s.checks}
        (s.evidence / "native.json").write_text(json.dumps(manifest, indent=2) + "\n")
        for check in s.checks:
            print("ok: " + check)
    except Exception:
        try:
            (s.evidence / "failure.txt").write_text(s.text())
            print("failure window", s.window()["rect"], "foot pid", s.window()["pid"], flush=True)
            children = subprocess.check_output(["pgrep", "-P", str(s.window()["pid"])], text=True).split()
            for child in children:
                print("tty size", subprocess.run(["stty", "-F", "/proc/" + child + "/fd/1", "size"], text=True, capture_output=True), flush=True)
            shutil.copyfile(s.log.name, s.evidence / "failure-native.log")
            subprocess.run(["grim", "-o", "HEADLESS-1", str(s.evidence / "failure.png")], env=s.env, check=True)
        except Exception:
            pass
        raise
    finally:
        s.close()


if __name__ == "__main__":
    main(*sys.argv[1:])
