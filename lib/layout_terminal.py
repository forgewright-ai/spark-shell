#!/usr/bin/env python3
"""Start a terminal app after its layout is sized, using actual terminal cells."""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time


class Refused(Exception):
    pass


def sway(*args):
    try:
        result = subprocess.run(["swaymsg", *args], text=True, capture_output=True,
                                stdin=subprocess.DEVNULL, timeout=3)
        data = json.loads(result.stdout)
        if result.returncode or (isinstance(data, list) and any(not x.get("success", True) for x in data)):
            raise ValueError()
        return data
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        raise Refused("the native window manager did not accept the size") from exc


def nodes(tree):
    yield tree
    for child in tree.get("nodes", []) + tree.get("floating_nodes", []):
        yield from nodes(child)


def ancestors():
    result = set()
    pid = os.getppid()
    while pid > 1 and pid not in result:
        result.add(pid)
        try:
            # The command in parentheses may contain spaces or parentheses.
            pid = int(Path(f"/proc/{pid}/stat").read_text().rpartition(")")[2].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return result


def fit(columns, rows):
    size = os.get_terminal_size(0)
    if size.columns >= columns and size.lines >= rows:
        return
    parents = ancestors()
    matches = [n for n in nodes(sway("-t", "get_tree")) if n.get("pid") in parents]
    if len(matches) != 1:
        raise Refused("cannot identify this terminal window to size it")
    window = matches[0]
    con = window["id"]
    if not isinstance(con, int) or min(size.columns, size.lines) < 1:
        raise Refused("the terminal has no usable size")
    # rect and cell counts share the current scale; no guessed font metrics.
    width = math.ceil(window["rect"]["width"] * max(1, columns / size.columns))
    height = math.ceil(window["rect"]["height"] * max(1, rows / size.lines))
    sway("--", f"[con_id={con}] resize set width {width} px height {height} px")
    for _ in range(10):
        time.sleep(0.05)
        size = os.get_terminal_size(0)
        if size.columns >= columns and size.lines >= rows:
            return
    # A split may have no room. Only this app floats; other windows stay put.
    sway("--", f"[con_id={con}] floating enable")
    sway("--", f"[con_id={con}] resize set width {width} px height {height} px")
    for _ in range(20):
        time.sleep(0.05)
        size = os.get_terminal_size(0)
        if size.columns >= columns and size.lines >= rows:
            return
    raise Refused(f"this screen cannot provide {columns} columns and {rows} rows")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lease", type=Path)
    parser.add_argument("columns", type=int)
    parser.add_argument("rows", type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    result = Path(str(args.lease) + ".result")
    try:
        if not (20 <= args.columns <= 240 and 5 <= args.rows <= 100) or not args.command:
            raise Refused("invalid terminal minimum or command")
        deadline = time.monotonic() + 120
        while args.lease.read_text() != "ready\n":
            if time.monotonic() >= deadline:
                raise Refused("the layout did not finish opening")
            time.sleep(0.05)
        fit(args.columns, args.rows)
        result.write_text("ready\n")
        os.execvp(args.command[0], args.command)
    except (OSError, Refused) as exc:
        message = "terminal app not started: " + str(exc)
        if args.lease.exists():
            result.write_text(message + "\n")
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
