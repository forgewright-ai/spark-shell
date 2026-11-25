#!/usr/bin/env python3
"""replay.py JOURNEY TAG... [--runs N] [--beside N] -- a journey on releases that are out: which are red, which green.
replay.py JOURNEY here -- on this tree and the programs built in it (test/prove.sh): exit 1 unless every run is green.

A journey earns its place here: red on the release that had the bug, green on the one that fixed it and on those
after. Each tag is cloned from this repository and its programs are built offline from the crates on disk, once, under
REPLAY_DIR (/var/tmp/spark-shell-replay); each run is a process tree of its own in bwrap, with no network, no /run, no
device and no home of yours. The tiny loop in place of a theme's 4K ones keeps a software renderer to a few processors.
"""
import argparse
import concurrent.futures
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
BASE = Path(os.environ.get("REPLAY_DIR", "/var/tmp/spark-shell-replay"))
PARTS = ("dialog", "bar", "winpad", "wallpaper")


def run(*argv, **more):
    return subprocess.run([str(a) for a in argv], capture_output=True, text=True, **more)


def tree(tag):
    """The tag's tree, with a tiny loop in place of each of its own."""
    if tag == "here":
        return REPO
    where = BASE / "trees" / tag
    if not where.exists():
        where.parent.mkdir(parents=True, exist_ok=True)
        got = run("git", "-c", "advice.detachedHead=false", "clone", "-q", "--no-hardlinks", "--branch", tag, "file://%s" % REPO, where)
        if got.returncode:
            sys.exit("replay: %s: %s" % (tag, got.stderr.strip()[-200:]))
        tiny = BASE / "tiny.mp4"
        if shutil.which("ffmpeg") and not tiny.exists():
            run("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=12", "-t", "4", "-pix_fmt", "yuv420p", tiny)
        for loop in where.glob("gallery/**/*.mp4"):
            if tiny.exists():
                shutil.copy(str(tiny), str(loop))
    return where


def builds(tag):
    """The tag's programs, built offline: part -> file."""
    if tag == "here":
        made = {part: [REPO / "component" / d / "release" / ("spark-" + part) for d in ("target", part + "/target")] for part in PARTS}
        return {part: f for part, files in made.items() for f in files if f.exists()}
    out, got = BASE / "bin" / tag, {}
    out.mkdir(parents=True, exist_ok=True)
    for part in PARTS:
        crate, file = tree(tag) / "component" / part, out / ("spark-" + part)
        if not crate.exists():
            continue
        if not file.exists():
            env = dict(os.environ, CARGO_TARGET_DIR=str(BASE / ("target-" + part)))
            made = run("nice", "-n", "12", "cargo", "build", "--release", "--locked", "--offline", cwd=str(crate), env=env)
            if made.returncode:
                print("replay: %s %s was not built: %s" % (tag, part, made.stderr.strip().splitlines()[-1:]))
                continue
            shutil.copy(str(BASE / ("target-" + part) / "release" / file.name), str(file))
        got[part] = file
    return got


def once(journey, tag, n):
    """One run in a bwrap of its own -> its verdict."""
    out = BASE / "runs" / ("%s-%s-%d" % (journey, tag, n))
    shutil.rmtree(str(out), ignore_errors=True)
    out.mkdir(parents=True)
    root, made, test = tree(tag), builds(tag), REPO / "test"
    argv = ["bwrap", "--die-with-parent", "--unshare-pid", "--unshare-net", "--unshare-ipc", "--unshare-uts", "--ro-bind", "/", "/",
            "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/run", "--tmpfs", "/tmp", "--tmpfs", "/var/tmp", "--tmpfs", "/home",
            "--ro-bind", root, root, *(("--ro-bind", BASE / "bin" / tag, BASE / "bin" / tag) if tag != "here" else ()), "--ro-bind", test, test, "--bind", out, out,
            "--chdir", out, "--clearenv", "--setenv", "PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin", "--setenv", "LANG", "C.UTF-8",
            "--setenv", "SPARK_SHELL_FENCE", "desk", "--setenv", "PYTHONDONTWRITEBYTECODE", "1",
            "nice", "-n", "12", "timeout", "420", "python3", "-I", test / "journeys.py", journey, root, out / "desk"]
    got = run(*argv, *["%s=%s" % kv for kv in made.items()])
    (out / "err").write_text(got.stderr)
    said = got.stdout.strip().splitlines()
    return said[-1] if said else "NOT-RUN no verdict: %s" % got.stderr.strip()[-120:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("journey")
    ap.add_argument("tags", nargs="+")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--beside", type=int, default=1, help="how many run side by side")
    a = ap.parse_args()
    if not shutil.which("bwrap"):
        sys.exit("replay: bwrap is not installed: a release's desktop runs nowhere else")
    bad = 0
    for tag in a.tags:
        if a.journey == "loops" and "wallpaper" not in builds(tag):
            print("%-7s %-9s not run: no spark-wallpaper was built" % (a.journey, tag))
            continue
        with concurrent.futures.ThreadPoolExecutor(a.beside) as pool:
            verdicts = list(pool.map(lambda n: once(a.journey, tag, n), range(1, a.runs + 1)))
        count = {w: sum(v.startswith(w) for v in verdicts) for w in ("RED", "GREEN", "NOT-RUN")}
        print("%-7s %-9s %s" % (a.journey, tag, ", ".join("%s %d" % (w.lower(), n) for w, n in count.items() if n)))
        for why in sorted({v for v in verdicts if not v.startswith("GREEN")}):
            print("        %s" % why[:300])
        bad += tag == "here" and count["GREEN"] != len(verdicts)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
