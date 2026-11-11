#!/usr/bin/env python3
"""Prove the window keys on a separate headless sway with a real foot:
python3 test/window_desktop_proof.py. A throwaway HOME and a sway of its
own. Drives spark-shell desktop window as Super+arrow and Super+minus do and
reads where foot lands: Up twice maximizes, Down twice minimizes, Right then
Down is the bottom right quarter, and the window minimized last comes back
at its place. foot rounds a floating window down to whole cells, so a place
holds when the corner is the place's and the size is the place's or up to
an eighth less.

The sway it starts takes from spark-shell's own render the gaps, the edge,
the bar's font and the rule for a new window (#262, #265), with a bar at the
top. Then: the area stands 8 pixels in from the screen's edges and a window
has an edge of 2 (#265); two windows the keys placed in the top quarters,
and a third foot opens floating in the bottom half; all four places taken, a
fifth opens at two thirds, centered, on top; a workspace with a tiled window
tiles a new one (#262). Two foot windows on the halves, no tiled window: the
space for windows changes and both move to the halves of the space as it is
now, then back; a window dragged by hand stays where it was dragged (#264).
The space changes by spark-pad docked at the left as a toolbar when
SPARK_SHELL_PAD names a build (the pad runs spark-shell desktop window refit
when its strip changes), else by spark-shell bar text, the bar at the top
taller, then thin again (bar text runs the refit after the bar's new
height). Then the space changes and comes back between two refits (#273):
a strip like the pad's, from a client of the proof's own, shown and gone
with nothing between, and the refit after puts the halves back, their
places kept; with a pad build, its strip shown and gone as fast as the keys
go, ten times, the halves at their places each time. Needs sway, swaymsg,
foot and python3."""
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
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


def settle(read, seconds=6):
    """read() until it holds; False when it never does in that time."""
    end = time.time() + seconds
    while time.time() < end:
        if read():
            return True
        time.sleep(0.1)
    return False


def nodes(node):
    yield node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key, []):
            yield from nodes(child)


def fills(got, want):
    gx, gy, gw, gh = got
    wx, wy, ww, wh = want
    return (abs(gx - wx) <= 2 and abs(gy - wy) <= 2 and ww - ww // 8 <= gw <= ww + 2
            and wh - wh // 8 <= gh <= wh + 2)


def places(area):
    x, y, w, h = area["x"], area["y"], area["width"], area["height"]
    return {"top half": (x, y, w, h // 2), "maximized": (x, y, w, h),
            "bottom half": (x, y + h // 2, w, h - h // 2), "left half": (x, y, w // 2, h),
            "right half": (x + w // 2, y, w - w // 2, h),
            "top left quarter": (x, y, w // 2, h // 2), "top right quarter": (x + w // 2, y, w - w // 2, h // 2),
            "bottom left quarter": (x, y + h // 2, w // 2, h - h // 2),
            "bottom right quarter": (x + w // 2, y + h // 2, w - w // 2, h - h // 2)}


def rect(node):
    r = node["rect"]
    return (r["x"], r["y"], r["width"], r["height"])


class Strip:
    """A strip like the pad's, kept at the left edge by a client of its own: a layer surface on the
    background with an exclusive zone, one transparent pixel so sway maps it and holds its zone. It runs
    no refit, so the area changes and comes back with nothing between. Speaks the Wayland wire protocol
    itself (registry, sync, wl_compositor, wl_shm, zwlr_layer_shell_v1)."""

    def __init__(self, env):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(str(Path(env["XDG_RUNTIME_DIR"]) / env["WAYLAND_DISPLAY"]))
        self.next, self.buf, self.globals, self.serial = 2, b"", {}, None
        self.req(1, 1, struct.pack("I", self.new()))   # wl_display.get_registry: object 2
        self.sync()
        self.compositor, self.shm, self.shell = (self.bind(name, version) for name, version in
                                                 (("wl_compositor", 4), ("wl_shm", 1), ("zwlr_layer_shell_v1", 1)))
        fd = os.memfd_create("strip")
        os.ftruncate(fd, 4)
        self.pool = self.new()
        message = struct.pack("II", self.shm, (16 << 16) | 0) + struct.pack("Ii", self.pool, 4)   # wl_shm.create_pool, the fd beside
        self.sock.sendmsg([message], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, struct.pack("i", fd))])
        os.close(fd)
        self.buffer = self.new()
        self.req(self.pool, 0, struct.pack("IiiiiI", self.buffer, 0, 1, 1, 4, 0))   # create_buffer: 1x1, argb8888
        self.sync()

    def new(self):
        self.next += 1
        return self.next - 1

    def req(self, obj, op, args=b""):
        self.sock.sendall(struct.pack("II", obj, ((8 + len(args)) << 16) | op) + args)

    def bind(self, name, version):
        nid = self.new()
        text = name.encode() + b"\0"
        self.req(2, 0, struct.pack("II", self.globals[name], len(text)) + text + b"\0" * (-len(text) % 4)
                 + struct.pack("II", version, nid))
        return nid

    def sync(self):
        done = self.new()
        self.req(1, 0, struct.pack("I", done))
        while True:
            while len(self.buf) < 8 or len(self.buf) < struct.unpack("II", self.buf[:8])[1] >> 16:
                part = self.sock.recv(65536)
                if not part:
                    raise RuntimeError("the compositor closed the strip's connection")
                self.buf += part
            obj, head = struct.unpack("II", self.buf[:8])
            size, op = head >> 16, head & 0xffff
            data, self.buf = self.buf[8:size], self.buf[size:]
            if obj == 1 and op == 0:
                raise RuntimeError("Wayland error: %r" % data)
            if obj == 2 and op == 0:   # wl_registry.global
                n = struct.unpack("I", data[4:8])[0]
                self.globals[data[8:8 + n - 1].decode()] = struct.unpack("I", data[:4])[0]
            if obj == getattr(self, "layer", None) and op == 0:   # zwlr_layer_surface_v1.configure
                self.serial = struct.unpack("I", data[:4])[0]
            if obj == done:
                return

    def show(self, thick):
        self.surface, self.layer = self.new(), None
        self.req(self.compositor, 0, struct.pack("I", self.surface))   # create_surface
        self.layer = self.new()
        name = b"strip\0\0\0"
        self.req(self.shell, 0, struct.pack("IIII", self.layer, self.surface, 0, 0) + struct.pack("I", 6) + name)   # background, sway's output
        self.req(self.layer, 1, struct.pack("I", 1 | 2 | 4))   # anchor: top, bottom, left
        self.req(self.layer, 0, struct.pack("II", thick, 0))
        self.req(self.layer, 2, struct.pack("i", thick))   # the exclusive zone
        self.req(self.surface, 6)   # commit: sway configures it
        self.sync()
        self.req(self.layer, 6, struct.pack("I", self.serial))   # ack_configure
        self.req(self.surface, 1, struct.pack("Iii", self.buffer, 0, 0))   # attach the pixel
        self.req(self.surface, 6)   # mapped: its zone is the area's
        self.sync()

    def hide(self):
        self.req(self.layer, 2, struct.pack("i", 0))   # the zone given back, as the pad's strip goes
        self.req(self.surface, 6)
        self.req(self.layer, 7)   # destroy
        self.req(self.surface, 0)
        self.sync()


def main():
    root = Path(tempfile.mkdtemp(prefix="window-proof."))
    runtime = root / "run"
    runtime.mkdir(mode=0o700)
    env = {**os.environ, "HOME": str(root), "SPARK_SHELL_ROOT": str(root / "sysroot"), "XDG_CONFIG_HOME": str(root / ".config"),
           "XDG_STATE_HOME": str(root / ".local/state"), "XDG_DATA_HOME": str(root / ".local/share"),
           "XDG_RUNTIME_DIR": str(runtime), "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman",
           "WLR_LIBINPUT_NO_DEVICES": "1", "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_PTS_DIR": str(root / "pts"),
           "SPARK_SHELL_DIALOG_URL": "none", "SPARK_SHELL_FONT_URL": "none", "SPARK_SHELL_SEMANTIC_URL": "none"}
    for name in ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_SHELL_PAD"):
        env.pop(name, None)   # never the desktop this runs on, nor its session bus
    pad = os.environ.get("SPARK_SHELL_PAD", "")
    # a bar where the family has swaybar (openSUSE has none on PATH); PROOF_NO_BAR proves that case here
    bar_here = shutil.which("swaybar") is not None and not os.environ.get("PROOF_NO_BAR")
    pad = pad if pad and os.access(pad, os.X_OK) else ""
    settings = root / ".config/spark-shell"
    settings.mkdir(parents=True)
    (settings / "config").write_text("DESKTOP=sway\nDISPLAY_IDLE=0\nDISPLAY_LOCK=0\nBAR_TEXT=10\n"
                                     + ("PAD_PLACE=left center\n" if pad else ""))

    def spark(*args):
        done = subprocess.run(["sh", str(REPO / "spark-shell"), *args], env=env, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=60)
        return (done.stdout + done.stderr).strip()

    # spark-shell's own render, no sway running yet: its gaps, its edge, the bar's font and the rule for a new window
    spark("bar", "text", "10")
    render = (root / ".config/sway/config").read_text()
    picked = [line for line in render.splitlines()
              if re.match(r"(gaps (inner|outer) |default_border |default_floating_border |for_window \[tiling\] )", line)]
    font = next((line.strip() for line in render.splitlines() if line.strip().startswith("font pango:")), "font pango:monospace 10")
    ok(len(picked) == 5 and "gaps outer 8" in picked and "default_border pixel 2" in picked
       and any(line.endswith("spark-shell desktop window new") for line in picked),
       "spark-shell's render: an outer gap of 8, an edge of 2, the rule for a new window (#262, #265)", picked)
    config = root / "sway.conf"
    bar = ("bar {\n    position top\n    %s\n    status_command while :; do echo proof; sleep 60; done\n}\n" % font) if bar_here else ""
    config.write_text("output HEADLESS-1 mode 1920x1080\nxwayland disable\n%s\n%s" % ("\n".join(picked), bar))
    children = [subprocess.Popen(["sway", "-c", str(config)], env=env, cwd=root,
                                 stdout=subprocess.DEVNULL, stderr=open(root / "sway.log", "w"))]
    try:
        sock = wait_for(lambda: next(iter(runtime.glob("sway-ipc.*.sock")), None), "sway's socket")
        display = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*")
                                         if not p.name.endswith(".lock")), None), "the display")
        env.update({"SWAYSOCK": str(sock), "WAYLAND_DISPLAY": display})
        if pad:
            env["SPARK_SHELL_PAD"] = pad

        def tree():
            out = subprocess.run(["swaymsg", "-t", "get_tree"], env=env, capture_output=True, text=True).stdout
            return json.loads(out or "null") or {}

        def msg(command):
            subprocess.run(["swaymsg", "--", command], env=env, capture_output=True, text=True)

        def node(ident):
            return next((n for n in nodes(tree()) if n.get("id") == ident), None)

        def foot():
            return next((n for n in nodes(tree()) if n.get("app_id") == "foot"), None)

        def workspace_of(ident):
            return next(w for w in nodes(tree()) if w.get("type") == "workspace"
                        and any(n.get("id") == ident for n in nodes(w)))

        def workspace(name):
            return next(w for w in nodes(tree()) if w.get("type") == "workspace" and w.get("name") == name)

        def footed():
            return {n["id"] for n in nodes(tree()) if n.get("app_id") == "foot"}

        def open_foot():
            before = footed()
            children.append(subprocess.Popen(["foot"], env=env, cwd=root,
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            ident = wait_for(lambda: next(iter(footed() - before), None), "a new foot window")
            time.sleep(1.2)   # the rule's spark-shell decides, and foot answers the size it is given
            return ident

        children.append(subprocess.Popen(["foot"], env=env, cwd=root,
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        wait_for(foot, "foot's window")
        time.sleep(0.5)   # the bar's height is in the area before it is read
        area = workspace_of(foot()["id"])["rect"]
        place = places(area)

        def key(word, ident=None):
            done = subprocess.run(["sh", str(REPO / "spark-shell"), "desktop", "window", word] + ([str(ident)] if ident else []),
                                  env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
            time.sleep(0.6)   # foot answers the new size with its own, a frame later
            return (done.stdout + done.stderr).strip()

        steps = [("up", "top half"), ("up", "maximized"), ("down", "bottom half"), ("down", "minimized"),
                 ("restore", "bottom half"), ("right", "bottom right quarter"), ("up", "right half"),
                 ("down", "bottom right quarter"), ("down", "minimized"), ("restore", "bottom right quarter"),
                 ("left", "bottom left quarter")]
        for word, where in steps:
            said = key(word)
            n = foot()
            ws = workspace_of(n["id"])["name"]
            got = rect(n)
            if where == "minimized":
                ok(ws == "__i3_scratch" and "on the pad" in said, "%s: foot is minimized, on the pad" % word, (ws, said))
            else:
                ok(ws != "__i3_scratch" and fills(got, place[where]) and where in said,
                   "%s: foot is %s, %s" % (word, "maximized" if where == "maximized" else "on the " + where, got),
                   "want %s, said %r" % (place[where], said))

        # half the air (#265): the area 8 pixels in from the screen where no bar is, a window's edge 2 pixels
        n = foot()
        ok(area["x"] == 8 and area["x"] + area["width"] == 1920 - 8 and area["y"] + area["height"] == 1080 - 8
           and (area["y"] > 8 if bar_here else area["y"] == 8),
           "the area stands 8 pixels in from the screen's edges%s (#265)" % (", below the bar" if bar_here else ", no bar here"), area)
        ok(n["current_border_width"] == 2 and n["window_rect"]["x"] == 2 and n["rect"]["x"] + n["window_rect"]["x"] == 10,
           "a window at the left edge: an edge of 2, its text 10 pixels from the screen's edge; two windows side by side 4 apart (#265)",
           (n["current_border_width"], n["rect"], n["window_rect"]))

        # a new window (#262): on workspace 2, two windows the keys placed in the top quarters, then a third, a fourth, a fifth
        msg("workspace 2")
        a = open_foot()
        key("up")
        key("left")
        b = open_foot()   # the left half is under a, the right half free: b floats there by itself
        ok(node(b)["type"] == "floating_con" and fills(rect(node(b)), place["right half"]),
           "a foot opened beside a window the keys placed floats in the right half, the first place free (#262)", rect(node(b)))
        key("up")
        ok(fills(rect(node(a)), place["top left quarter"]) and fills(rect(node(b)), place["top right quarter"]),
           "two windows the keys placed in the top quarters", (rect(node(a)), rect(node(b))))
        c = open_foot()
        ok(node(c)["type"] == "floating_con" and fills(rect(node(c)), place["bottom half"]),
           "a third foot opens floating in the free bottom half, not under the two (#262)", rect(node(c)))
        key("left")
        d = open_foot()
        ok(node(d)["type"] == "floating_con" and fills(rect(node(d)), place["bottom right quarter"]),
           "no half free: a fourth opens in the bottom right quarter, the one place left (#262)", rect(node(d)))
        e = open_foot()
        er = rect(node(e))
        cw, ch = area["width"] * 2 // 3, area["height"] * 2 // 3
        centered = (abs(er[0] - (area["x"] + (area["width"] - cw) // 2)) <= 2
                    and abs(er[1] - (area["y"] + (area["height"] - ch) // 2)) <= 2)   # sway centers the size it gave; foot rounds it down from the corner
        ok(node(e)["type"] == "floating_con" and cw - cw // 8 <= er[2] <= cw + 2 and ch - ch // 8 <= er[3] <= ch + 2 and centered
           and workspace("2")["floating_nodes"][-1]["id"] == e,
           "every place taken: a fifth opens at two thirds, centered, on top (#262)", (er, area))
        msg("workspace 3")
        f = open_foot()
        g = open_foot()
        ok(node(f)["type"] == "con" and node(g)["type"] == "con",
           "a workspace with a tiled window tiles the new one (#262)", (node(f)["type"], node(g)["type"]))

        # the space for windows changes (#264): on workspace 4, two halves the keys placed and no tiled window
        if pad or bar_here:   # the space changes by the pad, else by the bar's text size; with neither, nothing here changes it
            msg("workspace 4")
            h = open_foot()
            key("left")
            i = open_foot()
            ok(fills(rect(node(h)), place["left half"]) and fills(rect(node(i)), place["right half"]),
               "two foot windows on the left and right halves, no tiled window", (rect(node(h)), rect(node(i))))
            first = workspace("4")["rect"]
            j = None
            if pad:   # a third window on the pad shows it, docked at the left as a toolbar, and it keeps its strip
                j = open_foot()
                key("min", j)
                how = "spark-pad docked at the left as a toolbar"
            else:
                spark("bar", "text", "30")
                how = "the bar at the top taller (spark-shell bar text 30)"
            changed = settle(lambda: workspace("4")["rect"] != first, 8)
            now = places(workspace("4")["rect"])
            moved = settle(lambda: fills(rect(node(h)), now["left half"]) and fills(rect(node(i)), now["right half"]), 8)
            ok(changed and moved, "%s: both windows move to the halves of the space as it is now (#264)" % how,
               (first, workspace("4")["rect"], rect(node(h)), rect(node(i))))
            # one of them dragged by hand, as Super+left-drag does; then the space comes back
            time.sleep(1.5)   # the second refit, a second after the first
            msg("[con_id=%d] move absolute position 700 400" % i)
            time.sleep(0.6)
            dragged = rect(node(i))
            second = workspace("4")["rect"]
            if pad:
                key("restore", j)   # the pad's last window back: the pad goes, and its strip with it
                how = "the pad gone"
            else:
                spark("bar", "text", "10")
                how = "the bar thin again (spark-shell bar text 10)"
            back = settle(lambda: workspace("4")["rect"] != second, 10)
            again = places(workspace("4")["rect"])
            home = settle(lambda: fills(rect(node(h)), again["left half"]), 8)
            time.sleep(2)   # the second refit, a second after the first
            ok(back and home and workspace("4")["rect"] == first,
               "%s: the window at its place takes the space back (#264)" % how, (workspace("4")["rect"], rect(node(h))))
            stays = rect(node(i))
            # sway itself moves a floating window a little when the corner of the space moves; the refit never moves it to its place
            ok(abs(stays[0] - dragged[0]) <= 48 and abs(stays[1] - dragged[1]) <= 48 and stays[2:] == dragged[2:]
               and not fills(stays, again["right half"])
               and not any(m.startswith("_spark-shell.place.") for m in node(i).get("marks", [])),
               "a window dragged by hand stays where it was dragged, and no longer holds a place (#264)",
               (dragged, stays, node(i).get("marks")))
            said = spark("desktop", "window", "refit")
            ok(said == "the windows the keys placed are at their places",
               "desktop window refit by hand: every placed window is at its place, nothing moves", said)
        else:
            print("  skip no pad and no swaybar here: the refit is proven on the families that have one", flush=True)

        # the space changes and comes back between two refits (#273): sway moves each floating window a little by
        # itself every time the area changes, so a strip shown and gone with no refit between leaves the placed
        # windows a few pixels off on the very area they were placed on; the refit after puts them at their places
        msg("workspace 5")
        west = open_foot()
        key("left")
        east = open_foot()
        full = workspace("5")["rect"]
        halves = places(full)

        def at_halves():
            return fills(rect(node(west)), halves["left half"]) and fills(rect(node(east)), halves["right half"])

        def placed(ident):
            return any(m.startswith("_spark-shell.place.") for m in node(ident).get("marks", []))

        ok(at_halves(), "two foot windows on the halves of workspace 5", (rect(node(west)), rect(node(east))))
        strip = Strip(env)
        strip.show(40)
        shown = settle(lambda: workspace("5")["rect"] != full, 4)
        strip.hide()
        gone = settle(lambda: workspace("5")["rect"] == full, 4)
        nudged = (rect(node(west)), rect(node(east)))
        said = spark("desktop", "window", "refit")
        settle(at_halves, 2)
        ok(shown and gone and at_halves() and placed(west) and placed(east),
           "a strip shown and gone with no refit between: the refit puts both halves back, and neither loses its place (#273)",
           (shown, gone, nudged, said, rect(node(west)), rect(node(east))))

        # the pad's own strip as fast as the keys go (#273): a third window on the pad and back, ten times, the second
        # key as soon as the strip holds the area, while the pad's refit for it runs; the halves at their places
        if pad:
            def bare(word, ident):   # the key alone, no wait for foot after it
                subprocess.run(["sh", str(REPO / "spark-shell"), "desktop", "window", word, str(ident)], env=env,
                               stdin=subprocess.DEVNULL, capture_output=True, text=True)

            def area_now():   # workspace 5's area, read as fast as swaymsg answers
                out = subprocess.run(["swaymsg", "-t", "get_workspaces"], env=env, capture_output=True, text=True).stdout
                return next((w["rect"] for w in json.loads(out or "[]") if w.get("name") == "5"), full)

            key("left", west)   # placed anew, whatever the step before left
            key("right", east)
            third = open_foot()
            off = []
            for round_ in range(10):
                bare("min", third)
                end = time.time() + 2
                while time.time() < end and area_now() == full:   # no pause: back the moment the strip holds the area
                    pass
                bare("restore", third)
                if not settle(lambda: workspace("5")["rect"] == full and at_halves() and placed(west) and placed(east), 4):
                    off.append((round_, rect(node(west)), rect(node(east)), placed(west), placed(east)))
                    key("left", west)   # placed again for the next round
                    key("right", east)
            time.sleep(1)   # a refit that ran late moves nothing after the last round
            ok(not off and at_halves() and placed(west) and placed(east),
               "the pad's strip shown and gone as fast as the keys go, ten times: both halves at their places each time (#273)",
               (off, rect(node(west)), rect(node(east))))
    finally:
        for child in reversed(children):
            child.terminate()
    print("window proof: %s" % ("every key holds" if failed == 0 else "%d failed" % failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
