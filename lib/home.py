#!/usr/bin/env python3
"""Home's compositor adapter: named bindings and serialized open-or-focus.

No shell evaluation. The compositor owns windows; the existing process owns
its draft, conversation, providers and navigation state.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

import compositor


def config_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "spark-shell"


def chord(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_+]+", value):
        raise ValueError("desktop keys use modifiers and a keysym, separated by +")
    parts = value.split("+")
    aliases = {"super": "Mod4", "alt": "Mod1", "ctrl": "Ctrl", "shift": "Shift", "mod4": "Mod4", "mod1": "Mod1"}
    mods = [aliases.get(p.lower()) for p in parts[:-1]]
    if None in mods or len(mods) != len(set(mods)) or not parts[-1]:
        raise ValueError("unknown or repeated desktop modifier")
    key = {"enter": "Return", "esc": "Escape", "space": "space"}.get(parts[-1].lower(), parts[-1])
    return "+".join(sorted(mods, key=["Mod4", "Ctrl", "Mod1", "Shift"].index) + [key])


def bindings(source, overrides):
    if not isinstance(overrides, dict):
        raise ValueError("desktop-keys.json must be an object of action: key")
    lines = source.splitlines()
    known, seen, result = set(), {}, []
    action, scope, last = None, "default", None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("mode ") and stripped.endswith("{"):
            scope = stripped
        elif stripped == "}":
            scope = "default"
        elif stripped.startswith("# action: "):
            action = stripped[len("# action: "):]
        elif stripped.startswith("bindsym "):
            rest = stripped[len("bindsym "):].split(None, 1)
            flags = ""
            while rest[0].startswith("--"):   # a --release binding belongs to the press binding before it
                flags += rest[0] + " "
                rest = rest[1].split(None, 1)
            default, command = rest
            if flags:
                if last is None:
                    raise ValueError("a release binding with no binding before it: " + stripped)
                action = last
            else:
                if action is None:
                    raise ValueError("binding has no named action: " + stripped)
                if action in known:
                    raise ValueError("duplicate desktop action: " + action)
                known.add(action)
            key = chord(overrides.get(action, default.replace("$mod", "Super")))
            identity = (scope, flags, key.lower())
            if identity in seen:
                raise ValueError("desktop key conflict: " + seen[identity] + " and " + action)
            seen[identity] = action
            lines[i] = line[:len(line) - len(line.lstrip())] + "bindsym " + flags + key + " " + command
            if not flags:
                result.append((action, key.replace("Mod4", "Super").replace("Mod1", "Alt")))
                last = action
            action = None
    unknown = set(overrides) - known
    if unknown:
        raise ValueError("unknown desktop action: " + ", ".join(sorted(unknown)))
    return "\n".join(lines) + "\n", result


def read_overrides():
    file = config_dir() / "desktop-keys.json"
    return json.loads(file.read_text()) if file.exists() else {}


def wm(*args):
    return compositor.msg(*args)


def home_id(tree):
    if tree.get("app_id") == "spark-dialog" and isinstance(tree.get("id"), int):
        return tree["id"]
    for child in tree.get("nodes", []) + tree.get("floating_nodes", []):
        found = home_id(child)
        if found is not None:
            return found
    return None


def placed(tree, ident, workspace=None):
    """The window with this id and the workspace it stands on, or (None, None)."""
    if tree.get("type") == "workspace":
        workspace = tree
    if tree.get("id") == ident:
        return tree, workspace
    for child in tree.get("nodes", []) + tree.get("floating_nodes", []):
        found = placed(child, ident, workspace)
        if found[0] is not None:
            return found
    return None, None


def fit(tree, ident):
    """The window inside the space the bar leaves (#234). Sway holds a floating window to the screen, not to the
    workspace's area, so on a short screen home would run under the bar and past the bottom edge. The command
    that brings it inside, or None when it fits."""
    window, workspace = placed(tree, ident)
    if window is None or workspace is None:
        return None
    rect, area = window.get("rect") or {}, workspace.get("rect") or {}
    try:
        width, height = int(rect["width"]), int(rect["height"])
        room_w, room_h = int(area["width"]), int(area["height"])
        x, y, ax, ay = int(rect["x"]), int(rect["y"]), int(area["x"]), int(area["y"])
    except (KeyError, TypeError, ValueError):
        return None
    if min(room_w, room_h) <= 0:
        return None
    w, h = min(width, room_w), min(height, room_h)
    if (w, h) == (width, height) and ax <= x and ay <= y and x + w <= ax + room_w and y + h <= ay + room_h:
        return None
    return "[con_id=%d] resize set width %d px height %d px, move position center" % (ident, w, h)


def focus_existing():
    tree = wm("-t", "get_tree")
    ident = home_id(tree)
    if ident is None:
        return False
    window, _ = placed(tree, ident)
    # home back from the pad: its mark goes, or the pad would list it the next time home is put away
    leave = "".join("unmark %s, " % mark for mark in (window or {}).get("marks", []) if mark.startswith("_spark-shell.min."))
    result = wm("[con_id=%d] %sfocus" % (ident, leave))
    if not result or not all(item.get("success") for item in result):
        raise ValueError("the compositor could not focus home")
    command = fit(tree, ident)
    if command:
        wm(command)   # best effort: home works the same at the size sway gave it
    return True


def ask_section(runtime, section):
    """A section for the open home to go to (a bar block's click): one word, written whole, then taken
    by the dialog on its tick (component/dialog/src/goto.rs); an older request is replaced."""
    temp = runtime / ("spark-home.goto.%d" % os.getpid())
    fd = os.open(temp, os.O_CREAT | os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(section + "\n")
    os.replace(temp, runtime / "spark-home.goto")


def open_home(shell, section=None):
    section = section or None   # an empty word is no section: Super+Space and the bar's sign ask for none
    if section is not None and not re.fullmatch(r"[a-z]{1,32}", section):
        raise ValueError("a section is one word in lowercase letters")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", str(config_dir())))
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = os.open(runtime / "spark-home.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock, "w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        if section and home_id(wm("-t", "get_tree")) is not None:
            ask_section(runtime, section)   # home is open: it goes there, its draft and its way back kept
        if focus_existing():
            return
        argv = compositor.terminal_argv(compositor.terminal_config("dialog"), "spark-dialog", shell, "dialog")
        if section:
            argv.append(section)
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, start_new_session=True)
        # Hold the launch lock until the compositor owns the window. Concurrent
        # invocations then focus it instead of racing a second terminal into view.
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if focus_existing():
                return
            if child.poll() is not None:
                raise ValueError("home did not open (terminal exit %s)" % child.returncode)
            time.sleep(0.05)
        child.terminate()
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=3)
        raise ValueError("home did not map; the incomplete launch was stopped")


def main(argv):
    command, source, *rest = argv
    if command == "open":
        open_home(source, rest[0] if rest else None)
    elif command in ("render", "keys", "map"):
        file = Path(source)
        rendered, keys = bindings(file.read_text(), read_overrides())
        if command == "render":
            file.write_text(rendered)
        elif command == "map":
            print(json.dumps(dict(keys)))
        else:
            for action, key in keys:
                print(key + " " + action + ".")
    else:
        raise ValueError("expected open, render or keys")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print("home: " + str(error), file=sys.stderr)
        sys.exit(1)
