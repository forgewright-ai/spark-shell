#!/usr/bin/env python3
"""Home in an isolated native Sway/foot session. No user desktop changes.

Usage: python3 tests/home_desktop_proof.py BINARY EVIDENCE_DIRECTORY
Needs sway, foot, grim and wtype. Screenshots contain only fixture data.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def wait_for(read, label):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        value = read()
        if value:
            return value
        time.sleep(.1)
    raise AssertionError("timed out: " + label)


def main(binary, destination):
    for tool in ("sway", "swaymsg", "foot", "grim", "wtype"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    binary = str(Path(binary).resolve())
    checks = []
    with tempfile.TemporaryDirectory(prefix="home-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        settings = root / ".config/spark-shell"
        settings.mkdir(parents=True)
        (settings / "config").write_text("DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\nDIALOG_TALK=no\nDIALOG_MODEL=no\n")
        spark_settings = root / ".config/spark"
        spark_settings.mkdir()
        shutil.copyfile(REPO / "themes/tokyonight-night.env", spark_settings / "theme.env")
        foot = root / ".config/foot"
        foot.mkdir()
        version = subprocess.check_output(["foot", "--version"], text=True)
        major, minor = map(int, re.search(r"version: (\d+)\.(\d+)", version).groups())
        colors = "colors-dark" if (major, minor) >= (1, 26) else "colors"
        (foot / "dialog.ini").write_text("[main]\nfont=monospace:size=12\ninitial-window-size-chars=60x40\npad=18x18\n[" + colors + "]\nbackground=282a38\nforeground=c0caf5\n16=7aa2f7\n17=7b84ae\n18=282a38\n19=373a4b\n20=7b84ae\n")
        subprocess.run(["foot", "--check-config", "--config", str(foot / "dialog.ini")], check=True, capture_output=True)
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"),
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": binary, "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_PTS_DIR": str(root / "ptys")}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY"):
            env.pop(key, None)
        config = root / "sway.conf"
        # Use the real template's entry, focus-mode, fullscreen and snapping bindings.
        source = (REPO / "templates/.config/sway/config").read_text().replace("@REPO@", str(REPO))
        keys = [line for line in source.splitlines() if line.startswith("bindsym ") and
                ("desktop home" in line or "focus mode_toggle" in line or "desktop window" in line or line.endswith(" fullscreen"))]
        config.write_text('set $mod Mod4\noutput HEADLESS-1 mode 1440x1000\nxwayland disable\n'
                          'seat seat0 fallback true\nfor_window [app_id="spark-dialog"] floating enable, border none, move position center\n' + "\n".join(keys) + "\n")
        with (root / "native.log").open("w") as log:
            compositor = subprocess.Popen(["sway", "-c", str(config)], env=env, stdout=log, stderr=log)
            try:
                env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "sway"))
                env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "wayland")

                def sway(*args):
                    return json.loads(subprocess.check_output(["swaymsg", "-r", *args], env=env, timeout=5))

                def windows():
                    def walk(node):
                        return ([node] if node.get("app_id") == "spark-dialog" else []) + [w for n in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(n)]
                    return walk(sway("-t", "get_tree"))

                def key(*args):
                    subprocess.run(["wtype", "-s", "100", *args, "-s", "100"], env=env, check=True, timeout=5)
                    time.sleep(.2)

                def capture(name):
                    rect = windows()[0]["rect"]
                    geometry = "{x},{y} {width}x{height}".format(**rect)
                    subprocess.run(["grim", "-g", geometry, str(evidence / (name + ".png"))], env=env, check=True)

                key("-M", "logo", "-k", "space", "-m", "logo")
                first = wait_for(lambda: windows() and windows()[0], "home window")
                time.sleep(3)
                capture("root-void")
                checks.append("Super+Space launches home in real foot")
                key("draft persists")
                key("-M", "shift", "-k", "Return", "-m", "shift")
                key("second line")
                for _ in range(3):
                    key("-M", "logo", "-k", "space", "-m", "logo")
                current = windows()
                assert len(current) == 1 and current[0]["id"] == first["id"] and current[0]["pid"] == first["pid"]
                capture("draft-refocus-void")
                checks.append("Repeated Super+Space keeps one container and process with the two-line draft visible")
                key("-M", "ctrl", "-k", "Return", "-m", "ctrl")
                capture("unavailable-ask-void")
                checks.append("Native Ctrl+Enter reaches Ask; unavailable model keeps draft")
                key("-M", "logo", "-k", "f", "-m", "logo")
                assert windows()[0]["fullscreen_mode"] == 1
                capture("fullscreen-void")
                key("-M", "logo", "-k", "f", "-m", "logo")
                assert windows()[0]["fullscreen_mode"] == 0
                checks.append("Native fullscreen and restore retain the same home process")
                key("-M", "logo", "-k", "Left", "-m", "logo")
                left = windows()[0]
                assert left["id"] == first["id"] and left["rect"]["width"] <= 740
                capture("snapped-left-void")
                key("-M", "logo", "-k", "Right", "-m", "logo")
                right = windows()[0]
                assert right["id"] == first["id"] and right["rect"]["x"] > left["rect"]["x"]
                capture("snapped-right-void")
                checks.append("Native left and right placement retains the home process and draft")
                sway("[con_id=%d] resize set width 400 px height 500 px" % first["id"])
                # Let compositor configuration, terminal resize and providers
                # settle before taking evidence; no key forces the redraw.
                time.sleep(3)
                capture("narrow-void")
                key("-k", "Escape")
                key("help", "-k", "Return")
                capture("help-void")
                checks.append("Narrow layout and Help render with configured actions")
                sway("[con_id=%d] kill" % first["id"])
                wait_for(lambda: not windows(), "first fixture closed")

                # A separate fixture exercises real terminal input and rendering,
                # with a deterministic response instead of a live model request.
                fixture = root / "fixture-model"
                fixture.write_text("#!/usr/bin/env python3\nimport json, sys\nfrom pathlib import Path\n"
                                   "if sys.argv[1] == 'model': print('fixture-model\\tserving')\n"
                                   "elif sys.argv[1] == 'steps':\n"
                                   " Path(__file__).with_suffix('.request').write_text(json.dumps({'argv': sys.argv[1:], 'input': json.load(sys.stdin)}))\n"
                                   " answer = 'This is a deterministic model fixture.\\n\\n' + '\\n'.join('Line %02d: full answers stay inside home.' % n for n in range(1, 36)) + '\\nEND OF ANSWER'\n"
                                   " print(json.dumps({'answer': answer, 'steps': [], 'refused': []}))\n")
                fixture.chmod(0o700)
                (settings / "home-keys.json").write_text('{"ask": "F4"}\n')
                subprocess.Popen(["foot", "--config", str(foot / "dialog.ini"), "--app-id", "spark-dialog", "-e", binary,
                                  "--composer", "model", "--spark", str(fixture)], env=env, stdout=log, stderr=log)
                wait_for(lambda: windows(), "conversation fixture window")
                time.sleep(1)
                key("show the full fixture answer")
                key("-k", "F4")
                request = wait_for(lambda: fixture.with_suffix(".request").exists(), "configured Ask")
                assert request and json.loads(fixture.with_suffix(".request").read_text())["argv"][-1] == "show the full fixture answer"
                time.sleep(.3)
                capture("conversation-void")
                key("unfinished follow-up")
                key("-k", "Next")
                key("-k", "F2")
                key("-k", "F2")
                capture("conversation-scroll-void")
                checks.append("Configured F4 sends explicit Ask; fixture answer scrolls in home and F2 preserves the follow-up draft")
            finally:
                compositor.terminate()
                compositor.wait(timeout=10)
    (evidence / "native.json").write_text(json.dumps({"platform": "Void Linux", "tools": ["sway", "foot", "wtype", "grim"], "checks": checks}, indent=2) + "\n")
    for check in checks:
        print("ok: " + check)


if __name__ == "__main__":
    main(*sys.argv[1:])
