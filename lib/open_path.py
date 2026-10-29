#!/usr/bin/env python3
"""Dispatch an approved absolute path through the host's native file handler;
--reveal shows it in the file manager instead (the folder opened, the item
selected where the file manager takes org.freedesktop.FileManager1)."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("Darwin", "Linux"))
    parser.add_argument("path", type=Path)
    parser.add_argument("--reveal", action="store_true", help="show the path in the file manager")
    args = parser.parse_args()
    if not args.path.is_absolute():
        print("opening needs an absolute path", file=sys.stderr)
        return 1
    program = "open" if args.platform == "Darwin" else "xdg-open"
    argv = [program, str(args.path)]
    if args.reveal:
        if args.platform == "Darwin":
            argv = ["open", "-R", str(args.path)]
        elif shown(args.path):
            print(json.dumps({"receipt": "revealed " + args.path.name}))
            return 0
        else:
            argv = ["xdg-open", str(args.path.parent)]
    try:
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True, close_fds=True)
        try:
            code = child.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            code = None  # some native handlers remain alive with the opened app
        if code not in (None, 0):
            print("the native application refused to open that path", file=sys.stderr)
            return 1
    except OSError:
        print("the native file handler could not start", file=sys.stderr)
        return 1
    print(json.dumps({"receipt": ("revealed " if args.reveal else "opening requested for ") + args.path.name}))
    return 0


def shown(path):
    """The file manager asked to show the item, over the session bus; False when none answers."""
    url = "file://" + str(path).replace("%", "%25").replace(" ", "%20").replace("\"", "%22").replace(",", "%2C")
    try:
        done = subprocess.run(["dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.FileManager1",
                               "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems",
                               "array:string:" + url, "string:"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=3)
        return done.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


if __name__ == "__main__":
    sys.exit(main())
