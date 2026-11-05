#!/usr/bin/env python3
"""Prove the workspace place's steps on a separate headless sway with real
foot: python3 tests/workspace_desktop_proof.py. A throwaway HOME and a sway
of its own; a foot stands in for the dialog. Reads the rows, then moves,
places and arranges real windows through spark-shell's provider, undoes each,
takes a picture with the dialog stepped aside, saves a tabbed workspace and
opens it again. Needs sway, swaymsg, foot, grim, jq and python3."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
failed = 0


def ok(cond, what, detail=""):
    global failed
    print("  %s %s%s" % ("ok  " if cond else "FAIL", what, "" if cond else "   " + str(detail)))
    failed += 0 if cond else 1


def wait_for(read, description, seconds=10):
    end = time.time() + seconds
    while time.time() < end:
        value = read()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("timed out: " + description)


class Desktop:
    def __init__(self, root):
        self.root = root
        self.children = []
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        self.env = {**os.environ, "HOME": str(root), "XDG_CONFIG_HOME": str(root / ".config"),
                    "XDG_STATE_HOME": str(root / ".local/state"), "XDG_DATA_HOME": str(root / ".local/share"),
                    "XDG_RUNTIME_DIR": str(runtime), "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman",
                    "WLR_LIBINPUT_NO_DEVICES": "1", "SPARK_SHELL_NO_APPLY": "1"}
        for name in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY"):
            self.env.pop(name, None)
        config = root / "sway.conf"
        config.write_text('output HEADLESS-1 mode 1280x720\nxwayland disable\n'
                          'for_window [app_id="spark-dialog"] floating enable\n')
        self.children.append(subprocess.Popen(["sway", "-c", str(config)], env=self.env, cwd=root,
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        sock = wait_for(lambda: next(iter(runtime.glob("sway-ipc.*.sock")), None), "sway's socket")
        display = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")), None), "the display")
        self.env.update({"SWAYSOCK": str(sock), "WAYLAND_DISPLAY": display})
        wait_for(lambda: self.tree(), "sway answering")

    def sway(self, *args):
        return subprocess.run(["swaymsg", *args], env=self.env, capture_output=True, text=True)

    def tree(self):
        out = self.sway("-t", "get_tree").stdout
        return json.loads(out) if out.strip() else None

    def nodes(self, node=None):
        node = node or self.tree()
        yield node
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            yield from self.nodes(child)

    def window(self, app):
        return next((n for n in self.nodes() if n.get("app_id") == app), None)

    def workspace_of(self, app):
        for ws in self.nodes():
            if ws.get("type") == "workspace" and any(n.get("app_id") == app for n in self.nodes(ws)):
                return ws
        return None

    def arranged(self, app):
        """How the windows of app's workspace stand: sway wraps them in one container for tabs."""
        node = self.workspace_of(app)
        while len(node.get("nodes", [])) == 1 and node["nodes"][0].get("pid") is None:
            node = node["nodes"][0]
        return node["layout"]

    def open(self, app):
        self.children.append(subprocess.Popen(["foot", "--app-id", app, "sleep", "600"], env=self.env, cwd=self.root,
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        return wait_for(lambda: self.window(app), "the window " + app)["id"]

    def close(self):
        for child in reversed(self.children):
            child.terminate()
        for child in self.children:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()


def provider(desk, section, *messages):
    """The answers of a real provider to these requests, by id."""
    lines = [{"jsonrpc": "2.0", "id": 0, "method": "initialize",
              "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "proof", "version": "0"}}},
             {"jsonrpc": "2.0", "method": "notifications/initialized"}]
    for i, (method, params) in enumerate(messages, 1):
        lines.append({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
    out = subprocess.run(["sh", str(REPO / "spark-shell"), "provide", section], env=desk.env, cwd=desk.root,
                         input="\n".join(json.dumps(m) for m in lines) + "\n", capture_output=True, text=True, timeout=120).stdout
    answers = {}
    for line in out.splitlines():
        message = json.loads(line)
        if isinstance(message.get("id"), int):
            answers[message["id"]] = message
    return answers


def call(desk, section, tool, **arguments):
    answer = provider(desk, section, ("tools/call", {"name": tool, "arguments": arguments}))[1]["result"]
    return answer.get("structuredContent") or {"refused": answer["content"][0]["text"]}


def rows(desk, section, uri=None):
    uri = uri or "spark-shell://%s/rows" % section
    return json.loads(provider(desk, section, ("resources/read", {"uri": uri}))[1]["result"]["contents"][0]["text"])


def undo(desk, section, result):
    return call(desk, section, result["undo"]["name"], **result["undo"]["arguments"])


def main():
    for command in ("sway", "swaymsg", "foot", "grim", "jq"):
        if not shutil.which(command):
            raise SystemExit("missing native tool: " + command)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / ".config/spark-shell").mkdir(parents=True)
        (root / ".config/spark-shell/config").write_text("DESKTOP=sway\nTHEME=none\n")
        desk = Desktop(root)
        try:
            one = desk.open("proof-one")
            two = desk.open("proof-two")
            desk.open("spark-dialog")
            view = rows(desk, "window")
            windows = [r for r in view["rows"] if (r.get("tool") or {}).get("name") == "window_focus"]
            ok(view["state"] == "2 windows" and len(windows) == 2, "the rows: two windows, the dialog left out", view["state"])
            ok(all(r["group"].startswith("workspace 1") and "this one" in r["group"] for r in windows), "under the workspace you are on", windows[0]["group"])
            ok(sum(1 for r in windows if r.get("front")) == 1, "one window is the one in front")

            moved = call(desk, "window", "window_move", name=str(two), to="3")
            ok(moved.get("receipt") == "proof-two moved to workspace 3" and desk.workspace_of("proof-two")["num"] == 3, "move: the window is on workspace 3", moved)
            ok(desk.workspace_of("spark-dialog")["num"] == 1, "move: you stay where you are")
            undo(desk, "window", moved)
            ok(desk.workspace_of("proof-two")["num"] == 1, "move: undo puts it back")

            placed = call(desk, "window", "window_place", name=str(one), how="floating")
            ok(desk.window("proof-one")["type"] == "floating_con", "place: floating", placed)
            undo(desk, "window", placed)
            ok(desk.window("proof-one")["type"] == "con", "place: undo tiles it again")
            half = call(desk, "window", "window_place", name=str(one), how="left")
            rect = desk.window("proof-one")["rect"]
            ok(half.get("receipt") == "proof-one on the left half" and rect["x"] == 0 and rect["width"] <= 640, "place: the left half, by its ID, not in focus", rect)
            undo(desk, "window", half)
            full = call(desk, "window", "window_place", name=str(one), how="full")
            ok(desk.window("proof-one")["fullscreen_mode"] == 1, "place: full screen", full)
            call(desk, "window", "window_place", name=str(one), how="tiled")
            ok(desk.window("proof-one")["fullscreen_mode"] == 0, "place: tiled leaves full screen")
            aside = root / "aside"
            aside.write_text(f"{one}\n")
            desk.env["SPARK_SHELL_ASIDE"] = str(aside)   # what the panel hands the dialog when a full screen window steps aside
            line = next(r for r in rows(desk, "window")["rows"] if r.get("tool", {}).get("arguments", {}).get("name") == str(one))["line"]
            ok("full screen" in line, "aside: a window that stepped aside reads full screen", line)
            call(desk, "window", "window_place", name=str(one), how="floating")
            ok(desk.window("proof-one")["type"] == "floating_con" and not aside.read_text().strip(), "aside: placing it clears it, so it stays as placed")
            call(desk, "window", "window_place", name=str(one), how="tiled")
            del desk.env["SPARK_SHELL_ASIDE"]
            desk.sway("[app_id=spark-dialog] focus")   # full screen took the focus, as the dialog closing would give it

            arranged = call(desk, "window", "window_tabs")
            ok(arranged.get("receipt") == "windows in tabs" and desk.arranged("proof-one") == "tabbed", "arrange: tabs on this workspace", arranged)
            ok("WINDOWS=tabs" in (root / ".config/spark-shell/config").read_text(), "arrange: and the default for new ones")
            shown = next(r for r in rows(desk, "window")["rows"] if r["id"] == "window:arrange")
            ok(shown["columns"] == ["tabs"], "arrange: the row reads this workspace", shown)
            saved = call(desk, "layout", "layout_save", name="tabbed")
            ok("arrange" in (root / ".config/spark-shell/layouts/tabbed").read_text(), "save: the arrangement is kept", saved)
            undo(desk, "window", arranged)
            ok(desk.arranged("proof-one") == "splith", "arrange: undo puts this workspace back")
            ok("WINDOWS=split" in (root / ".config/spark-shell/config").read_text(), "arrange: and the default")

            shot = call(desk, "window", "window_capture", what="screen")
            pictures = list(root.glob("**/screenshots/*.png"))
            ok(".png" in shot.get("receipt", "") and len(pictures) == 1, "capture: the file's name on the status row, and the file", shot)
            ok(desk.workspace_of("spark-dialog")["num"] == 1, "capture: the dialog is back on its workspace, out of the scratchpad")
            call(desk, "window", "window_move", name=str(two), to="4")
            shot = call(desk, "window", "window_capture", what="window", name=str(two))
            ok(".png" in shot.get("receipt", "") and len(list(root.glob("**/screenshots/*.png"))) == 2, "capture: a window on another workspace", shot)
            ok(desk.workspace_of("spark-dialog")["num"] == 1, "capture: you end where you began")

            # a saved tabbed layout opens in tabs, on a workspace of its own
            (root / ".config/spark-shell/layouts/reopen").write_text('{"words":"reopen","why":"a proof","arrange":"tabs","main":{"app":"shell"},"side":[{"app":"shell"}]}\n')
            call(desk, "layout", "layout_open", name="reopen")
            wait_for(lambda: sum(1 for n in desk.nodes() if n.get("app_id") == "foot") == 2, "the layout's two windows", 20)
            ok(desk.arranged("foot") == "tabbed", "open: a saved layout comes back in tabs", desk.arranged("foot"))

            desk.sway(f"[con_id={one}] move container to workspace notes")
            listed = rows(desk, "window")["rows"]
            named = next(r for r in listed if r.get("tool", {}).get("arguments", {}).get("name") == str(one))
            ok(named["group"].startswith("workspace notes") and "workspace notes" in named["line"] and "-1" not in named["group"], "named: a workspace with no number reads by its name", named)
            desk.sway("workspace notes")
            call(desk, "window", "window_capture", what="window", name=str(two))
            focused = [w["name"] for w in json.loads(desk.sway("-t", "get_workspaces").stdout) if w["focused"]]
            ok(focused == ["notes"], "named: a capture comes back to it", focused)
            back = call(desk, "window", "window_move", name=str(one), to="1")
            ok(desk.workspace_of("proof-one")["num"] == 1 and not back.get("undo"), "named: a move from it works, with no undo to refuse", back)

            gone = call(desk, "window", "window_move", name="999999", to="2")
            ok(gone.get("refused") == "that window is no longer open", "a window gone is said", gone)
        finally:
            desk.close()
    print("workspace proof: %s" % ("FAILED" if failed else "ok"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
