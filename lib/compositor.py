"""The compositor and the terminal, the one helper that names them (sway, foot)."""
import json
import os
import shutil
import subprocess
from pathlib import Path

NAME = "sway"
TERMINAL = "foot"
COPY_MISSING = "copying needs wl-copy in a Wayland session"


def session():
    return bool(os.environ.get("SWAYSOCK"))


def here():
    return bool(shutil.which("swaymsg"))


def argv(*args):
    """The argv of a command whose reply is raw JSON."""
    return ["swaymsg", "-r", *args]


def call(*args, timeout=5):
    """A command's CompletedProcess, the reply unparsed."""
    return subprocess.run(["swaymsg", *args], text=True, capture_output=True, stdin=subprocess.DEVNULL, timeout=timeout)


def msg(*args, timeout=5):
    """A command, its reply parsed; raises on a refused one."""
    result = subprocess.run(argv(*args), check=True, capture_output=True, text=True, timeout=timeout)
    return json.loads(result.stdout)


def copy_here():
    return bool(shutil.which("wl-copy") and os.environ.get("WAYLAND_DISPLAY"))


def copy(text, timeout=4):
    """text on the clipboard; False when the clipboard did not take it."""
    done = subprocess.run(["wl-copy", "--"], input=text, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True, timeout=timeout)
    return done.returncode == 0


def terminal_here():
    return bool(shutil.which("foot"))


def terminal_config(kind="dialog"):
    return Path.home() / ".config/foot" / ("dialog.ini" if kind == "dialog" else "foot.ini")


def terminal_argv(config, app_id, *command):
    """The argv that opens a window of the terminal running command."""
    return ["foot", "--config", str(config), "--app-id", app_id, "-e", *command]
