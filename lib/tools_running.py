#!/usr/bin/env python3
"""tools_running.py -- the programs running, for the tools place's running page (v0.129).

  tools_running.py list PROC STATE [WINDOWS]   a TSV line a program, the busiest first:
      NAME CPU PRIVATE RESIDENT COUNT UIDS STARTED PIDS COMMAND WINDOW
  tools_running.py tree PROC PID                PID and every process under it, a pid a line

A program is the name of its command's first word (an interpreter's script by the script's
name), so a program's processes are one line; a kernel thread, which has no command, is not
listed, nor is this reader. CPU is the program's share of the whole processor, in percent, since the sample kept
in STATE; with no sample younger than 30 seconds, two are taken half a second apart. PRIVATE
is what its processes hold alone, resident less shared, in bytes, summed: a floor, never a
double count. STARTED is when its oldest process started, in seconds since the epoch.
WINDOWS is a file of PID<tab>CON lines, sway's windows: a program's WINDOW is its newest
window's con id, or empty.
"""
import json
import os
import sys
import time

INTERPRETERS = {"sh", "bash", "dash", "zsh", "ksh", "python", "python3", "perl", "node", "ruby", "lua", "env"}


def read(path, mode="r"):
    try:
        with open(path, mode) as f:
            return f.read()
    except OSError:
        return None


def name_of(argv):
    words = [w.decode("utf-8", "replace") for w in argv if w]
    if not words:
        return ""
    first = os.path.basename(words[0].split(" ")[0].split(":")[0])
    if first in INTERPRETERS:
        for w in words[1:]:
            if w in ("-c", "-m", "-e"):
                break
            if not w.startswith("-"):
                return os.path.basename(w)
    return first


def sample(proc):
    """-> (total jiffies, {pid: fields}) of every process with a command."""
    head = (read(os.path.join(proc, "stat")) or "").split("\n", 1)[0].split()
    total = sum(int(x) for x in head[1:]) if head[:1] == ["cpu"] else 0
    procs = {}
    try:
        pids = [d for d in os.listdir(proc) if d.isdigit()]
    except OSError:
        pids = []
    me = str(os.getpid())
    for pid in pids:
        if pid == me:
            continue
        base = os.path.join(proc, pid)
        stat = read(os.path.join(base, "stat"))
        cmd = read(os.path.join(base, "cmdline"), "rb")
        if not stat or not cmd:
            continue
        fields = stat[stat.rfind(")") + 2:].split()
        if len(fields) < 20:
            continue
        statm = (read(os.path.join(base, "statm")) or "0 0 0").split()
        uid = ""
        for line in (read(os.path.join(base, "status")) or "").splitlines():
            if line.startswith("Uid:"):
                uid = line.split()[1]
                break
        argv = cmd.split(b"\0")
        procs[pid] = {
            "ppid": fields[1],
            "jiffies": int(fields[11]) + int(fields[12]),
            "start": int(fields[19]),
            "resident": int(statm[1]) if len(statm) > 1 else 0,
            "shared": int(statm[2]) if len(statm) > 2 else 0,
            "uid": uid,
            "name": name_of(argv),
            "command": argv[0].decode("utf-8", "replace") if argv else "",
        }
    return total, procs


def boot_time(proc):
    for line in (read(os.path.join(proc, "stat")) or "").splitlines():
        if line.startswith("btime "):
            return int(line.split()[1])
    return 0


def windows_of(path):
    pids = {}
    for line in (read(path) or "").splitlines() if path else []:
        parts = line.split("\t")
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            pids[parts[0]] = max(pids.get(parts[0], 0), int(parts[1]))
    return pids


def listing(proc, state, windows):
    before = None
    kept = read(state)
    if kept:
        try:
            before = json.loads(kept)
            if time.time() - before.get("at", 0) > 30:
                before = None
        except ValueError:
            before = None
    if before is None:
        total0, procs0 = sample(proc)
        time.sleep(0.5)
        before = {"total": total0, "procs": {p: v["jiffies"] for p, v in procs0.items()}}
    total, procs = sample(proc)
    try:
        with open(state + ".new", "w") as f:
            json.dump({"at": time.time(), "total": total, "procs": {p: v["jiffies"] for p, v in procs.items()}}, f)
        os.replace(state + ".new", state)
    except OSError:
        pass
    span = max(total - before.get("total", 0), 1)
    page = os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096
    tick = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
    btime = boot_time(proc)
    win = windows_of(windows)
    groups = {}
    for pid, p in procs.items():
        if not p["name"]:
            continue
        g = groups.setdefault(p["name"], {"cpu": 0, "private": 0, "resident": 0, "pids": [], "uids": set(), "start": None, "command": "", "window": 0})
        g["cpu"] += max(p["jiffies"] - before.get("procs", {}).get(pid, p["jiffies"]), 0)
        g["private"] += max(p["resident"] - p["shared"], 0) * page
        g["resident"] += p["resident"] * page
        g["pids"].append(int(pid))
        g["uids"].add(p["uid"])
        if g["start"] is None or p["start"] < g["start"]:
            g["start"] = p["start"]
            g["command"] = p["command"]
        g["window"] = max(g["window"], win.get(pid, 0))
    rows = sorted(groups.items(), key=lambda kv: (-kv[1]["cpu"], -kv[1]["private"], kv[0]))
    for name, g in rows:
        cpu = round(100.0 * g["cpu"] / span)
        started = btime + (g["start"] or 0) // tick
        fields = [name, str(cpu), str(g["private"]), str(g["resident"]), str(len(g["pids"])), ",".join(sorted(g["uids"])), str(started),
                  " ".join(str(p) for p in sorted(g["pids"])), g["command"], str(g["window"] or "")]
        print("\t".join(f.replace("\t", " ").replace("\n", " ") for f in fields))


def tree(proc, root):
    _, procs = sample(proc)
    kids = {}
    for pid, p in procs.items():
        kids.setdefault(p["ppid"], []).append(pid)
    out, todo = [], [root]
    while todo:
        pid = todo.pop()
        out.append(pid)
        todo.extend(kids.get(pid, []))
    print("\n".join(out))


def main(argv):
    if argv[:1] == ["list"] and len(argv) >= 3:
        listing(argv[1], argv[2], argv[3] if len(argv) > 3 else "")
    elif argv[:1] == ["tree"] and len(argv) == 3:
        tree(argv[1], argv[2])
    else:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
