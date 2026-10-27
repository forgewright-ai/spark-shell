#!/usr/bin/env python3
"""Prove terminal minimums with a separate headless Sway and real foot."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def wait_for(read, description):
    for _ in range(100):
        value = read()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("timed out: " + description)


def main():
    for command in ("sway", "swaymsg", "foot", "python3"):
        if not shutil.which(command):
            raise SystemExit("missing native tool: " + command)
    children = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": tmp,
               "XDG_RUNTIME_DIR": str(runtime), "WLR_BACKENDS": "headless",
               "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1"}
        for name in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY"):
            env.pop(name, None)
        config = root / "sway.conf"
        config.write_text('output HEADLESS-1 mode 1280x720\nxwayland disable\n'
                          'for_window [app_id="proof-target"] floating enable, resize set 300 200\n'
                          'for_window [app_id="proof-sibling"] floating enable, resize set 400 300\n')
        log = open(root / "sway.log", "w")
        compositor = subprocess.Popen(["sway", "-c", str(config)], env=env,
                                      stdout=log, stderr=log, start_new_session=True)
        try:
            env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "Sway socket"))
            env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "Wayland socket")

            def sway(*args):
                return json.loads(subprocess.check_output(["swaymsg", *args], env=env, timeout=5))

            def window(app):
                def find(tree):
                    if tree.get("app_id") == app:
                        return tree
                    for node in tree.get("nodes", []) + tree.get("floating_nodes", []):
                        found = find(node)
                        if found:
                            return found
                    return None
                return find(sway("-t", "get_tree"))

            for scale in (1, 1.25):
                sway("output", "HEADLESS-1", "scale", str(scale))
                sibling = subprocess.Popen(["foot", "--app-id", "proof-sibling", "sleep", "30"], env=env, stdout=log, stderr=log)
                children.append(sibling)
                before = wait_for(lambda: window("proof-sibling"), "sibling")
                lease = root / "lease"
                result = root / "cells.json"
                lease.write_text("wait\n")
                result.unlink(missing_ok=True)
                app = "import os,json,time; from pathlib import Path; Path('" + str(result) + "').write_text(json.dumps(list(os.get_terminal_size(0)))); time.sleep(5)"
                target = subprocess.Popen(["foot", "--app-id", "proof-target", "python3", str(REPO / "lib/layout_terminal.py"), str(lease), "80", "24", "python3", "-c", app], env=env, stdout=log, stderr=log)
                children.append(target)
                wait_for(lambda: window("proof-target"), "target")
                lease.write_text("ready\n")
                wait_for(lambda: result.exists(), "app launch after resize")
                columns, rows = json.loads(result.read_text())
                assert columns >= 80 and rows >= 24, (columns, rows)
                assert window("proof-sibling")["rect"] == before["rect"], "another window was resized"
                print(f"ok: real foot at scale {scale}: {columns}x{rows}, fullscreen={window('proof-target')['fullscreen_mode']}, sibling unchanged", flush=True)
                for child in (target, sibling):
                    child.terminate()
                    child.wait(timeout=5)
                wait_for(lambda: not window("proof-target") and not window("proof-sibling"), "windows closed")
        except Exception:
            log.flush()
            print((root / "sway.log").read_text()[-5000:])
            for path in root.glob("lease*"):
                print(path.name + ": " + path.read_text())
            if "SWAYSOCK" in env:
                print(subprocess.check_output(["swaymsg", "-t", "get_tree"], env=env, text=True)[-8000:])
            raise
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                    child.wait()
            compositor.terminate()
            compositor.wait(timeout=5)
            log.close()


if __name__ == "__main__":
    main()
