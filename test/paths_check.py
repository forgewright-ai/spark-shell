#!/usr/bin/env python3
"""paths_check.py [--report] -- every path written in the tree points at something in the tree.

Scans the tracked text files for references into the top-level folders (asset, component,
distro, gallery, lib, src, template, test) and the root files, in these forms:
  template/login/config.toml   "$REPO/src/core.sh"   $REPO/lib/apps.py   ./test/gate.sh
A reference with a shell variable or a glob after the folder (src/$name.sh, lib/motion_*.py)
is checked up to the first such part. A reference that names nothing in the tree is an error.
Markers written into installed files keep their text on purpose and are listed in KEEP.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = "asset component distro gallery lib src template test".split()
ROOT_FILES = "spark-shell config.example allowed-signers LICENSE README.md CHANGELOG.md CREDITS.md".split()
REF = re.compile(r"(?<![A-Za-z0-9_.\-/])(?:\./|\$REPO/|\$\{REPO\}/|\"\$REPO\"/)?((?:%s)/[A-Za-z0-9_.\-/$*{}]+)" % "|".join(TOP))
KEEP = (
    "rendered by spark-shell from template",   # the marker an installed file carries; readers accept it
    "[ ! -e ",                                 # a test that a path is absent
)
TEXT = (".sh", ".py", ".rs", ".toml", ".yml", ".yaml", ".md", ".env", ".ini", ".conf", ".json", ".txt", ".svg", ".desktop", ".rules", ".service", "")


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=REPO, capture_output=True, check=True).stdout
    return [p for p in out.decode().split("\0") if p]


def exists(ref, base):
    """The reference as a path in the tree, or under the file's own crate for a crate's manifest.

    A part that is a variable, a glob or an all-capitals placeholder (NAME, N, PIECE) ends the
    check: the folder before it must exist. A build output (a `target/` part) is never in the
    tree and passes."""
    parts = ref.split("/")
    fixed = []
    for p in parts:
        if "$" in p or "*" in p or "{" in p or re.search(r"(^|[-_.])[A-Z][A-Z0-9]*([-_.]|$)", p) or p == "target":
            break
        fixed.append(p)
    cut = "/".join(fixed).rstrip("/.")
    partial = len(fixed) < len(parts)
    for root in (REPO, base):
        path = os.path.join(root, cut) if cut else root
        if partial and os.path.isdir(os.path.dirname(path) if not os.path.isdir(path) else path):
            return True
        if not partial and os.path.exists(path):
            return True
    return False


def main():
    report = "--report" in sys.argv[1:]
    bad = []
    for path in tracked():
        if not path.endswith(TEXT) or "/golden/" in path or path.startswith(("asset/transitions", "gallery/animation/")):
            continue
        full = os.path.join(REPO, path)
        crate = re.match(r"^(component/[a-z_]+)/", path)
        base = os.path.join(REPO, crate.group(1)) if crate else REPO
        try:
            with open(full, encoding="utf-8") as fh:
                for n, line in enumerate(fh, 1):
                    if any(k in line for k in KEEP):
                        continue
                    for ref in REF.findall(line):
                        if not exists(ref, base):
                            bad.append((path, n, ref))
        except (UnicodeDecodeError, OSError):
            continue
    for path, n, ref in bad:
        print("paths check: %s:%d names %s, which the tree does not have" % (path, n, ref))
    if bad:
        print("paths check: %d stale references" % len(bad))
        return 1
    print("paths check: every path written in the tree exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())
