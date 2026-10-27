#!/usr/bin/env python3
"""Dispatch an approved absolute path through the host's native file handler."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("Darwin", "Linux"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    if not args.path.is_absolute():
        print("opening needs an absolute path", file=sys.stderr)
        return 1
    program = "open" if args.platform == "Darwin" else "xdg-open"
    try:
        child = subprocess.Popen([program, str(args.path)], stdin=subprocess.DEVNULL,
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
    print(json.dumps({"receipt": "opening requested for " + args.path.name}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
