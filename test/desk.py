"""desk.py -- what the desktop's proofs share: the fence they start behind, the virtual pointer, and the whole
desktop (Desktop) as a login makes it, with the invariants its journeys hold it to (test/journeys.py).

A proof starts a sway, a bar and windows of its own, and runs spark-shell on. Outside a fence it once wrote a real
home, turned a login screen off and drew on the desktop in use. fenced() stops it there: test/prove.sh and CI's
desktop job set SPARK_SHELL_FENCE, and nothing else does.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time


def fenced(whole=False):
    """Stop a proof that nothing keeps off the machine it runs on. WHOLE: a journey, which starts every program of the
    desktop, runs in a bwrap of its own (test/replay.py) or in a CI container, where no login's init runs."""
    fence = os.environ.get("SPARK_SHELL_FENCE")
    first = Path("/proc/1/comm").read_text().strip() if whole and Path("/proc/1/comm").exists() else ""
    if not fence or (whole and not (fence == "desk" and first == "bwrap" or fence == "ci" and first not in ("", "runit", "systemd", "init", "openrc-init", "launchd"))):
        sys.exit("%s: run it through test/prove.sh: its fence keeps a proof off your desktop" % Path(sys.argv[0]).name)


class Pointer:
    """Keep a virtual pointer attached to the isolated compositor for real clicks.

    Implements only registry, sync and wlr-virtual-pointer-v1 motion/button/frame.
    A persistent device matters: removing it between motion and click loses focus.
    """

    def __init__(self, env):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(5)
        self.socket.connect(str(Path(env["XDG_RUNTIME_DIR"]) / env["WAYLAND_DISPLAY"]))
        self.callback = 2
        self.globals = {}
        self.send(1, 1, 2)  # wl_display.get_registry
        self.sync()
        interface = b"zwlr_virtual_pointer_manager_v1\0"
        payload = struct.pack("II", self.globals[interface[:-1]], len(interface))
        payload += interface + b"\0" * (-len(interface) % 4)
        payload += struct.pack("II", 1, 4)
        self.packet(2, 0, payload)  # wl_registry.bind, version 1, object 4
        self.send(4, 0, 0, 5)  # create_virtual_pointer, default seat, object 5
        self.callback = 5
        self.sync()

    def packet(self, obj, opcode, payload):
        self.socket.sendall(struct.pack("II", obj, ((len(payload) + 8) << 16) | opcode) + payload)

    def send(self, obj, opcode, *args):
        self.packet(obj, opcode, struct.pack("I" * len(args), *args))

    def read(self, size):
        result = b""
        while len(result) < size:
            part = self.socket.recv(size - len(result))
            if not part:
                raise RuntimeError("virtual pointer connection closed")
            result += part
        return result

    def sync(self):
        self.callback += 1
        self.send(1, 0, self.callback)
        while True:
            obj, header = struct.unpack("II", self.read(8))
            data = self.read((header >> 16) - 8)
            opcode = header & 0xffff
            if obj == 1 and opcode == 0:
                raise RuntimeError("Wayland error: " + repr(data))
            if obj == 2 and opcode == 0:
                name, length = struct.unpack("II", data[:8])
                self.globals[data[8:8 + length - 1]] = name
            if obj == self.callback:
                return

    def click(self, x, y, times=1):
        # times 2 is a double click: the two presses 200 ms apart, within the dialog's 400 ms window
        # (the dialog design notes, app::DOUBLE_CLICK), as a desktop's double click is; two click() calls would not be,
        # since each one rests after its release
        def stamp():
            return int(time.monotonic() * 1000) & 0xffffffff
        self.send(5, 1, stamp(), x, y, 1440, 1000)  # motion_absolute
        self.send(5, 4)  # frame
        self.sync()
        time.sleep(.1)
        for _ in range(times):
            for state in (1, 0):
                self.send(5, 2, stamp(), 272, state)  # BTN_LEFT
                self.send(5, 4)
                self.sync()
                time.sleep(.1)

    def close(self):
        self.socket.close()


class NotRun(Exception):
    """The desk could not be brought to where a check looks: no word on the program under test."""


class Broken(Exception):
    """An invariant did not hold."""


GROUND = (0, 255, 0)
PARTS = ("swaybg", "swaybar", "spark-bar", "spark-winpad", "spark-dialog", "spark-wallpaper")


class Desktop:
    """The desktop as a login makes it: spark-shell on renders the config, a headless sway runs it, with the
    dialog, the bar and the pad built from the tree. No stand-in for any of them, and no copy of the config."""

    def __init__(self, tree, builds, out, screens=((1200, 1920, "90"), (1920, 1080, "normal")), config=()):
        self.tree, self.builds, self.out, self.screens, self.said = Path(tree), dict(builds), Path(out), screens, []
        self.home, self.run = self.out / "home", self.out / "run"
        for d in (self.home / ".config/spark-shell", self.home / ".config/spark", self.home / ".config/sway/config.d",
                  self.home / "root/etc", self.home / "bin", self.run, self.out / "pts"):
            d.mkdir(parents=True, exist_ok=True)
        self.run.chmod(0o700)
        for f in ("/etc/os-release", "/etc/group", "/etc/passwd"):
            shutil.copy(f, self.home / "root" / f.lstrip("/"))
        for tool in ("sudo", "doas", "tmux", "usermod", "gpasswd"):
            stub = self.home / "bin" / tool
            stub.write_text("#!/bin/sh\nexit %d\n" % (tool in ("sudo", "doas", "tmux")))
            stub.chmod(0o755)
        keys = {"DESKTOP": "sway", "THEME": "nord", "WALLPAPER": "skyline", "DISPLAY_IDLE": "0", "DISPLAY_LOCK": "0",
                "DIALOG_ANIMATION": "none", "BAR_TEXT": "12"}
        keys.update(dict(config))
        seen = self.home / ".local/state/spark-shell/desktop.seen"   # a desktop logged into before: home is opened by a check, never by a login
        seen.parent.mkdir(parents=True, exist_ok=True)
        seen.write_text("")
        (self.home / ".config/spark-shell/config").write_text("".join("%s=%s\n" % k for k in keys.items()))
        lines, x = [], 0
        for i, (w, h, turn) in enumerate(screens):
            mode = (h, w) if turn in ("90", "270") else (w, h)
            lines.append("output HEADLESS-%d mode %dx%d position %d 0 transform %s" % (i + 1, mode[0], mode[1], x, turn))
            x += w
        (self.home / ".config/sway/config.d/desk.conf").write_text("\n".join(lines) + "\n")
        self.env = {"HOME": str(self.home), "PATH": "%s:%s/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" % (self.home / "bin", "/opt/nocap:" if os.path.exists("/opt/nocap/sway") else ""),
                    "LANG": "C.UTF-8", "TERM": "xterm-256color", "USER": "ada", "SPARK_SHELL_FENCE": "desk",
                    "XDG_RUNTIME_DIR": str(self.run), "TMUX_TMPDIR": str(self.out), "SPARK_SHELL_ROOT": str(self.home / "root"),
                    "SPARK_SHELL_PTS_DIR": str(self.out / "pts"), "SPARK_SHELL_DIALOG_URL": "none", "SPARK_SHELL_FONT_URL": "none",
                    "SPARK_SHELL_SEMANTIC_URL": "none", "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman",
                    "WLR_LIBINPUT_NO_DEVICES": "1", "WLR_HEADLESS_OUTPUTS": str(len(screens)), "LIBGL_ALWAYS_SOFTWARE": "1"}
        for name, path in self.builds.items():
            self.env["SPARK_SHELL_" + name.upper()] = str(path)
        self.procs = []

    # --- the desk brought up, and down
    def start(self):
        got = self.sh("sh", str(self.tree / "spark-shell"), "on", "--yes", seconds=240)
        (self.out / "on.log").write_text(got.stdout + got.stderr)
        conf = self.home / ".config/sway/config"
        if not conf.exists():
            raise NotRun("spark-shell on rendered no sway config")
        bus = self.sh("dbus-daemon", "--session", "--fork", "--print-address=1").stdout.splitlines()
        self.env["DBUS_SESSION_BUS_ADDRESS"] = bus[0] if bus else ""
        with open(str(self.out / "sway.log"), "w") as log:
            self.procs.append(subprocess.Popen(["sway", "-c", str(conf)], env=self.env, cwd=str(self.home), stdout=log, stderr=log))
        self.env["SWAYSOCK"] = str(self.until(lambda: next(self.run.glob("sway-ipc.*.sock"), None), "sway's socket"))
        self.env["WAYLAND_DISPLAY"] = self.until(lambda: next((p.name for p in self.run.glob("wayland-*") if p.is_socket()), None), "a Wayland socket")
        self.procs.append(subprocess.Popen(["wtype", "-s", "900000"], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        self.until(lambda: len(self.msg("-t", "get_outputs")) == len(self.screens), "%d screens" % len(self.screens))
        if "bar" in self.builds:
            self.until(lambda: self.census()["spark-bar"], "spark-bar", 40)
        self.quiet()
        for w in self.windows():   # the terminal a login opens: the checks start on empty workspaces
            self.sway("[con_id=%d] move to workspace 8" % w["id"])
        self.sway("workspace 1")
        self.ground()
        return self

    def stop(self):
        self.sh("swaymsg", "exit", seconds=5)
        for sig in (signal.SIGTERM, signal.SIGKILL):
            for pid in self.ours():
                try:
                    os.kill(pid, sig)
                except OSError:
                    pass
            time.sleep(0.5)

    # --- asking and telling
    def sh(self, *argv, seconds=60):
        """A command's answer. Its words go to files: what it starts (home) may keep them open, and a pipe would wait."""
        with tempfile.TemporaryFile("w+") as said, tempfile.TemporaryFile("w+") as moaned:
            try:
                code = subprocess.run(argv, env=self.env, cwd=str(self.home), stdin=subprocess.DEVNULL, stdout=said, stderr=moaned, timeout=seconds).returncode
            except subprocess.TimeoutExpired:
                code = 124
            said.seek(0)
            moaned.seek(0)
            return subprocess.CompletedProcess(argv, code, said.read(), moaned.read() + (" (timed out in %d s)" % seconds if code == 124 else ""))

    def shell(self, *verb, seconds=90):
        """A verb of spark-shell's. One that refuses changed nothing, so what follows would judge nothing."""
        got = self.sh("sh", str(self.tree / "spark-shell"), *verb, seconds=seconds)
        said = " ".join((got.stdout + got.stderr).strip().splitlines()[-1:])
        self.said.append("%s -> %d %s" % (" ".join(verb), got.returncode, said))
        if got.returncode:
            raise NotRun("spark-shell %s said %d: %s" % (" ".join(verb), got.returncode, said))
        return got

    def msg(self, *args):
        got = self.sh("swaymsg", "-r", *args, seconds=15)
        if got.returncode:
            raise NotRun("swaymsg %s: %s" % (" ".join(args), got.stderr.strip()[:80]))
        return json.loads(got.stdout or "null")

    def key(self, *words):
        self.sh("wtype", "-s", "100", *words, "-s", "100", seconds=10)

    def sway(self, command):
        return self.sh("swaymsg", command, seconds=15)

    def until(self, read, what, seconds=25, kind=NotRun):
        """The first true answer. A look that could not be taken (NotRun) to the end is no word on the program."""
        end, blind = time.monotonic() + seconds, None
        while time.monotonic() < end:
            try:
                value, blind = read(), None
            except NotRun as why:
                value, blind = None, why
            if value:
                return value
            time.sleep(0.2)
        if blind:
            raise NotRun("%s: %s" % (what, blind))
        raise kind("waited %d s for %s" % (seconds, what))

    def holds(self, read, what, seconds=20):
        """An invariant: true within SECONDS, and true again after a rest. What comes and goes between is not it."""
        self.until(read, what, seconds, Broken)
        time.sleep(1.5)
        self.until(read, what + ", and again", 10, Broken)

    def reload(self):
        got = self.sway("reload")
        if got.returncode:
            raise Broken("sway refused its reload: %s" % (got.stdout + got.stderr).strip()[:120])
        time.sleep(2)
        self.ground()

    def quiet(self, seconds=20):
        """Wait until the desk is at rest: two snapshots a second apart are the same."""
        last, end = None, time.monotonic() + seconds
        while time.monotonic() < end:
            now = self.snapshot()
            if now == last:
                return now
            last = now
            time.sleep(1)
        raise NotRun("the desk did not come to rest in %d s" % seconds)

    def alone(self):
        """Home's workspace to itself: what shows through an unseen home is the plain ground."""
        d = self.dialog()
        for w in self.windows():
            if d and w["id"] != d["id"] and w["workspace"] == d["workspace"]:
                self.sway("[con_id=%d] move to workspace 9" % w["id"])
        time.sleep(0.5)

    def ground(self):
        self.sway("output * bg #%02x%02x%02x solid_color" % GROUND)
        time.sleep(1)

    # --- what stands
    def windows(self):
        found = []

        def walk(n, ws):
            ws = n["name"] if n.get("type") == "workspace" else ws
            if n.get("pid") and n.get("type") in ("con", "floating_con"):
                found.append(dict(n, workspace=ws))
            for k in n.get("nodes", []) + n.get("floating_nodes", []):
                walk(k, ws)
        walk(self.msg("-t", "get_tree"), None)
        return found

    def dialog(self):
        return next((w for w in self.windows() if w.get("app_id") == "spark-dialog"), None)

    def ours(self):
        """Every process of this run, by the runtime folder in its environment."""
        mark, found = b"XDG_RUNTIME_DIR=" + str(self.run).encode(), []
        for p in Path("/proc").iterdir():
            if p.name.isdigit() and int(p.name) != os.getpid():
                try:
                    if mark in (p / "environ").read_bytes().split(b"\0"):
                        found.append(int(p.name))
                except OSError:
                    continue
        return found

    def census(self):
        """The desktop's own programs that run: name -> [(pid, file, whether that file is gone)]."""
        got = {name: [] for name in PARTS}
        for pid in self.ours():
            try:
                name, exe = Path("/proc/%d/comm" % pid).read_text().strip(), os.readlink("/proc/%d/exe" % pid)
            except OSError:
                continue
            if name in got:
                got[name].append((pid, exe.replace(" (deleted)", ""), exe.endswith(" (deleted)")))
        return got

    def snapshot(self):
        """What a reload at rest must leave as it was: the windows, their bands, the areas, the programs."""
        areas = {w["name"]: tuple(w["rect"].values()) for w in self.msg("-t", "get_workspaces") if w.get("visible")}
        return {"windows": sorted((w.get("app_id") or "", w["workspace"] or "", tuple(w["rect"].values()), w["deco_rect"]["height"]) for w in self.windows()),
                "areas": areas, "programs": {n: len(p) for n, p in self.census().items()}}

    def grab(self, x, y, w, h):
        got = subprocess.run(["grim", "-t", "ppm", "-g", "%d,%d %dx%d" % (x, y, w, h), "-"], env=self.env, capture_output=True, timeout=30)
        if got.returncode:
            raise NotRun("grim: " + got.stderr.decode(errors="replace")[:80])
        return got.stdout.split(b"\n", 3)[3]

    def seen(self):
        """How much of the dialog's window is drawn over the plain ground: near 0 it is unseen, near 1 it is seen."""
        d = self.dialog()
        if not d:
            return None
        for w in self.windows():
            if w["id"] != d["id"] and w.get("visible") and w["workspace"] == d["workspace"]:
                raise NotRun("%s stands on home's workspace" % w.get("app_id"))
        r = d["rect"]
        area = next(w["rect"] for w in self.msg("-t", "get_workspaces") if w["name"] == d["workspace"])
        strip = self.grab(area["x"] + 4, area["y"] + area["height"] - 12, 40, 8)   # under every window's edge: the ground alone
        if any(tuple(strip[i:i + 3]) != GROUND for i in range(0, len(strip) - 2, 3)):
            self.ground()
            raise NotRun("the ground is not plain beside home")
        px = self.grab(r["x"] + 8, r["y"] + 8, r["width"] - 16, r["height"] - 16)
        points = range(0, len(px) - 2, 3 * 97)
        return 1 - sum(1 for i in points if tuple(px[i:i + 3]) == GROUND) / max(1, len(points))

    # --- the invariants
    def whole(self):
        """The bar, the pad and the background drawer run, one of each, the rest one at most, none an older build's."""
        need = ("swaybg",) + tuple("spark-" + part for part in ("bar", "winpad") if part in self.builds)

        def as_made():
            got = self.census()
            return all(len(got[n]) == 1 for n in need) and all(len(f) <= 1 for f in got.values()) and not any(f[2] for found in got.values() for f in found)
        try:
            self.holds(as_made, "one of each program")
        except Broken:
            raise Broken("the programs are not one of each, or are an older build's: %s"
                         % ", ".join("%d %s%s" % (len(f), n, " from a file that is gone" if any(x[2] for x in f) else "") for n, f in self.census().items() if f or n in need))

    def home_seen(self):
        if not self.dialog():
            raise Broken("home is gone")
        self.until(lambda: (self.dialog() or {}).get("visible") and (self.dialog() or {}).get("focused"), "home to have the keys", 15)
        self.holds(lambda: (self.seen() or 0) > 0.8, "home seen while it has the keys")

    def reload_is_nothing(self):
        before = self.quiet()
        self.reload()
        after = self.quiet()
        if after != before:
            keys = [k for k in before if before[k] != after[k]]
            raise Broken("a reload at rest changed %s: %s -> %s" % (", ".join(keys), [before[k] for k in keys], [after[k] for k in keys]))
