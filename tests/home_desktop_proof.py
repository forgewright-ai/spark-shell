#!/usr/bin/env python3
"""Home in an isolated native Sway/foot session. No user desktop changes.

Usage: python3 tests/home_desktop_proof.py BINARY EVIDENCE_DIRECTORY
Needs sway, swaybar, foot, grim and wtype. Model and voice are deterministic fixtures;
all native screenshots use the same font, palette and configured footer.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def contrast_ratio(foreground, background):
    def luminance(color):
        channels = [int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
        return sum(a * b for a, b in zip(linear, (.2126, .7152, .0722)))
    a, b = sorted((luminance(foreground), luminance(background)))
    return (b + .05) / (a + .05)


def native_foot_config(root):
    """Read the palette from the real launcher in the isolated fixture HOME.

    A probe replaces only the dialog executable, before Sway starts. This uses
    production theme loading and contrast adjustment without painting a desktop.
    """
    keys = ["HEX_FG", "HEX_ACCENT", "HEX_MUTED", "PANEL_BG", "PANEL_HI", "PANEL_MUTED", "PANEL_BAND"]
    keys += ["HEX_ANSI_" + str(i) for i in range(16)]
    probe = root / "palette-probe"
    probe.write_text("#!" + sys.executable + "\nimport json, os\nprint(json.dumps({k: os.environ[k] for k in " + repr(keys) + "}))\n")
    probe.chmod(0o700)
    env = {k: v for k, v in os.environ.items() if k not in keys and k not in
           ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_DIALOG_WINDOW")}
    env.update(HOME=str(root), XDG_CONFIG_HOME=str(root / ".config"),
               XDG_STATE_HOME=str(root / "state"), XDG_DATA_HOME=str(root / "data"),
               XDG_RUNTIME_DIR=str(root / "run"), SPARK_SHELL_DIALOG=str(probe),
               SPARK_SHELL_PTS_DIR=str(root / "ptys"), SPARK_SHELL_NO_APPLY="1")
    try:
        result = subprocess.run(["sh", str(REPO / "spark-shell"), "dialog"], env=env,
                                stdin=subprocess.DEVNULL, text=True, capture_output=True,
                                check=True, timeout=30)
        palette = json.loads(result.stdout)
    finally:
        probe.unlink()
    assert all(re.fullmatch(r"[0-9a-fA-F]{6}", value) for value in palette.values())
    ratios = {role: round(contrast_ratio(palette[key], palette["PANEL_BG"]), 3)
              for role, key in (("muted", "PANEL_MUTED"), ("foreground", "HEX_FG"), ("accent", "HEX_ACCENT"))}
    assert all(ratio >= 4.5 for ratio in ratios.values()), ratios
    version = subprocess.check_output(["foot", "--version"], text=True)
    major, minor = map(int, re.search(r"version: (\d+)\.(\d+)", version).groups())
    colors = "colors-dark" if (major, minor) >= (1, 26) else "colors"
    lines = ["[main]", "font=monospace:size=12", "[" + colors + "]",
             "background=" + palette["PANEL_BG"], "foreground=" + palette["HEX_FG"]]
    lines += [("regular" if i < 8 else "bright") + str(i % 8) + "=" + palette["HEX_ANSI_" + str(i)] for i in range(16)]
    lines += [str(slot) + "=" + palette[key] for slot, key in
              ((16, "HEX_ACCENT"), (17, "HEX_MUTED"), (18, "PANEL_BG"), (19, "PANEL_HI"), (20, "PANEL_MUTED"), (21, "PANEL_BAND"))]
    (root / ".config/foot/foot.ini").write_text("\n".join(lines) + "\n")
    return colors, {"colors": palette, "contrast": ratios, "source": "spark-shell dialog launcher environment"}


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
        # (dialog/DESIGN.md, app::DOUBLE_CLICK), as a desktop's double click is; two click() calls would not be,
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


def wait_for(read, label):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        value = read()
        if value:
            return value
        time.sleep(.1)
    raise AssertionError("timed out: " + label)


def stop_round(env):
    """Stop what the round started and the compositor's end leaves: spark-shell desktop home starts its foot in
    a session of its own (lib/home.py), so the terminal, the dialog and its providers outlive sway, reparented to
    init; a failed round left a set alive on the box for 17 hours. Every process with this round's runtime dir in
    its environment goes, a term first and a kill for what stays a second later."""
    mark = ("XDG_RUNTIME_DIR=" + env["XDG_RUNTIME_DIR"]).encode()

    def alive():
        found = []
        for p in Path("/proc").iterdir():
            if not p.name.isdigit() or int(p.name) == os.getpid():
                continue
            try:
                if mark in p.joinpath("environ").read_bytes().split(b"\0"):
                    found.append(int(p.name))
            except OSError:
                continue
        return found

    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = alive()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(1)


def main(binary, destination):
    for tool in ("sway", "swaymsg", "swaybar", "foot", "grim", "wtype"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    binary = str(Path(binary).resolve())
    checks, captures = [], {}
    with tempfile.TemporaryDirectory(prefix="home-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        settings = root / ".config/spark-shell"
        settings.mkdir(parents=True)
        (settings / "config").write_text("DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\nDIALOG_ATTACH=yes\nDIALOG_TALK=yes\nDIALOG_MODEL=yes\n")
        spark_settings = root / ".config/spark"
        spark_settings.mkdir()
        shutil.copyfile(REPO / "themes/tokyonight-night.env", spark_settings / "theme.env")
        fixtures = root / "bin"
        fixtures.mkdir()
        fixture = fixtures / "spark"
        fixture.write_text('''#!/usr/bin/env python3
import json, sys, time
from pathlib import Path
here = Path(__file__)
if sys.argv[1] == 'model':
    if not here.with_suffix('.unavailable').exists(): print('fixture-model\\tserving')
elif sys.argv[1] == 'client': print('spark client -- local')
elif sys.argv[1] == 'voice':
    if here.with_suffix('.unavailable').exists(): sys.exit(1)
    if 'listen' in sys.argv:
        here.with_suffix('.listening').touch()
        time.sleep(30)
        print('fixture dictated draft')
    else: print('voice ready')
elif sys.argv[1] == 'steps':
    here.with_suffix('.request').write_text(json.dumps({'argv': sys.argv[1:], 'input': json.load(sys.stdin)}))
    answer = 'This is a deterministic model fixture.\\n\\n' + '\\n'.join('Line %02d: full answers stay inside home.' % n for n in range(1, 36)) + '\\nEND OF ANSWER'
    print(json.dumps({'answer': answer, 'steps': [], 'refused': []}))
''')
        fixture.chmod(0o700)
        foot = root / ".config/foot"
        foot.mkdir()
        colors, palette = native_foot_config(root)
        template = (REPO / "templates/.config/foot/dialog.ini").read_text()
        for old, new in {"@HOME@": tmp, "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "0x0", "@FOOT_COLORS@": colors, "@PANEL_BG@": palette["colors"]["PANEL_BG"]}.items():
            template = template.replace(old, new)
        dump = fixtures / "screen-dump"
        dump.write_text("from pathlib import Path\nimport sys\n(Path.home() / 'screen.txt').write_text(sys.stdin.read())\n")
        template += "\n[key-bindings]\npipe-visible=[python3 " + str(dump) + "] Control+Shift+F12\n"
        (foot / "dialog.ini").write_text(template)
        attachment = root / "long-attachment-for-narrow-footer-review.md"
        attachment.write_text("Native footer fixture.\n")
        subprocess.run(["foot", "--check-config", "--config", str(foot / "dialog.ini")], check=True, capture_output=True)
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"),
               "PATH": str(fixtures) + os.pathsep + os.environ["PATH"],
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": binary, "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_PTS_DIR": str(root / "ptys")}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY"):
            env.pop(key, None)
        config = root / "sway.conf"
        source = (REPO / "templates/.config/sway/config").read_text().replace("@REPO@", str(REPO))
        keys = [line for line in source.splitlines() if line.startswith("bindsym ") and
                ("desktop home" in line or "focus mode_toggle" in line or "desktop window" in line or line.endswith(" fullscreen"))]
        config.write_text('set $mod Mod4\noutput HEADLESS-1 mode 1440x1000\nxwayland disable\n'
                          'bar {\n position top\n height 28\n font pango:monospace 10\n}\nseat seat0 fallback true\nfor_window [app_id="spark-dialog"] floating enable, border none, move position center\n' + "\n".join(keys) + "\n")
        with (root / "native.log").open("w") as log:
            compositor = subprocess.Popen(["sway", "-c", str(config)], env=env, stdout=log, stderr=log)
            pointer = None
            keyboard = None
            try:
                env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "sway"))
                env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "wayland")
                pointer = Pointer(env)
                # Keep keyboard capability between wtype invocations. Removing
                # the seat's last keyboard produces FocusLost and cancels voice.
                keyboard = subprocess.Popen(["wtype", "-s", "600000"], env=env, stdout=log, stderr=log)

                def sway(*args):
                    return json.loads(subprocess.check_output(["swaymsg", "-r", *args], env=env, timeout=5))

                def windows():
                    def walk(node):
                        return ([node] if node.get("app_id") == "spark-dialog" else []) + [w for n in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(n)]
                    return walk(sway("-t", "get_tree"))

                def key(*args):
                    subprocess.run(["wtype", "-s", "100", *args, "-s", "100"], env=env, check=True, timeout=5)
                    time.sleep(.2)

                def open_home():
                    key("-M", "logo", "-k", "space", "-m", "logo")
                    window = wait_for(lambda: windows() and windows()[0], "home window")
                    time.sleep(3)
                    return window

                def close_home():
                    sway("[con_id=%d] kill" % windows()[0]["id"])
                    wait_for(lambda: not windows(), "fixture closed")

                def capture(name, whole=False):
                    rect = windows()[0]["rect"]
                    geometry = "{x},{y} {width}x{height}".format(**rect)
                    subprocess.run(["grim", *( ["-o", "HEADLESS-1"] if whole else ["-g", geometry]), str(evidence / (name + ".png"))], env=env, check=True)
                    captures[name] = {**{k: rect[k] for k in ("x", "y", "width", "height")}, "full_output": whole}
                    print("captured: " + name, flush=True)

                first = open_home()
                area = next(w["rect"] for w in sway("-t", "get_workspaces") if w["focused"])
                assert area["y"] >= 28, "the bar must reserve the top of the usable area"
                cell = (first["rect"]["width"] // 60, first["rect"]["height"] // 40)   # no air of foot's own (v0.124.5)

                def screen():
                    file = root / "screen.txt"
                    file.unlink(missing_ok=True)
                    key("-M", "ctrl", "-M", "shift", "-k", "F12", "-m", "shift", "-m", "ctrl")
                    wait_for(file.exists, "terminal screen dump")
                    # Foot can export cleared cells either as spaces or as empty
                    # lines after a redraw. Retain leading columns for alignment.
                    return [line.rstrip() for line in file.read_text().splitlines()]

                def control(label):
                    lines = screen()
                    row = next(i for i in range(len(lines) - 1, -1, -1) if label in lines[i])
                    col = lines[row].index(label) + len(label) // 2
                    rect = windows()[0]["rect"]
                    # the window's first pixel is the first cell's: no air of foot's own (v0.124.5)
                    x, y = rect["x"] + col * cell[0] + cell[0] // 2, rect["y"] + row * cell[1] + cell[1] // 2
                    pointer.click(x, y)
                    time.sleep(.5)

                def footer_gap():
                    # the frame's two strips (dialog/DESIGN.md): the prompt's tools on the fourth row, the diamond's rule
                    # under them and a row of air; the plain rule, a row of air and the key bar at the bottom
                    lines = screen()
                    assert "fixture-model" in lines[4] or "model" in lines[4], "the prompt's tools on the fourth row"
                    assert not lines[5].strip(), "a row of air between the tools and the rule (v0.124.3)"
                    assert "\u2500" in lines[6] and ("\u25c6" in lines[6] or "\u25c7" in lines[6]), "the diamond's rule under the air"
                    assert not lines[7].strip(), "a row of air under the rule"
                    bottom = max(i for i, line in enumerate(lines) if "\u2500" in line)
                    assert not lines[bottom + 1].strip(), "a full blank row separates the plain rule and the keys"
                    assert "Esc" in lines[bottom + 2], "the key bar is the last thing in the frame"

                def model_click():
                    footer_gap()
                    control("fixture-model")
                    assert "model" in screen()[0].lower(), "model click missed after resize: " + repr(screen())
                    key("-k", "Escape")
                    assert "home" in screen()[0].lower()

                capture("root-void", whole=True)
                model_click()
                key("-M", "logo", "-k", "f", "-m", "logo")
                time.sleep(2)
                assert windows()[0]["fullscreen_mode"] == 1
                capture("root-fullscreen-void", whole=True)
                model_click()
                key("-M", "logo", "-k", "f", "-m", "logo")
                time.sleep(2)
                assert windows()[0]["rect"] == first["rect"], "fullscreen restores the original normal rectangle"
                key("-M", "logo", "-k", "Left", "-m", "logo")
                time.sleep(2)
                left = windows()[0]["rect"]
                assert left == {"x": area["x"], "y": area["y"], "width": area["width"] // 2, "height": area["height"]}, (left, area)
                capture("root-snapped-left-void", whole=True)
                left_screen = screen()
                model_click()
                key("-M", "logo", "-k", "Right", "-m", "logo")
                time.sleep(2)
                right = windows()[0]["rect"]
                assert right == {**left, "x": area["x"] + area["width"] // 2, "width": area["width"] - area["width"] // 2}, (left, right)
                right_screen = screen()
                assert left_screen[1:] == right_screen[1:], "snap sides must compose the same layout at the same size: " + repr([(i, a, b) for i, (a, b) in enumerate(zip(left_screen, right_screen)) if i and a != b])
                capture("root-snapped-right-void", whole=True)
                model_click()
                key("-M", "logo", "-k", "f", "-m", "logo")
                key("-M", "logo", "-k", "f", "-m", "logo")
                time.sleep(2)
                assert windows()[0]["rect"] == right, "fullscreen restores the snapped rectangle"
                checks.append("Root is bounded and centered; both snaps fill equivalent halves of the usable area below the bar")
                checks.append("Native model clicks and the frame's two strips are correct after normal, fullscreen and both snaps")
                # Restore the fixture's normal dimensions for the conversation comparison.
                sway("[con_id=%d] resize set width %d px height %d px, move position center" % (first["id"], first["rect"]["width"], first["rect"]["height"]))
                time.sleep(2)
                key(*[arg for _ in range(10) for arg in ("-k", "Down")])
                for placement in ("f", "f", "Left", "Right", "f", "f"):
                    key("-M", "logo", "-k", placement, "-m", "logo")
                    assert "home" in screen()[0].lower(), "resize changed the current root view"
                key("-k", "Return")
                assert "power" in screen()[0].lower(), "resize lost the selected last destination"
                key("-k", "Escape")
                sway("[con_id=%d] resize set width %d px height %d px, move position center" % (first["id"], first["rect"]["width"], first["rect"]["height"]))
                time.sleep(2)
                checks.append("The selected Power destination and root view survive fullscreen, both snaps and restore")
                checks.append("Super+Space opens the quiet root with Attach, model/source and Talk configured")
                key("draft persists")
                key("-M", "shift", "-k", "Return", "-m", "shift")
                key("second line")
                for _ in range(3):
                    key("-M", "logo", "-k", "space", "-m", "logo")
                current = windows()
                assert len(current) == 1 and current[0]["id"] == first["id"] and current[0]["pid"] == first["pid"]
                capture("draft-refocus-void")
                checks.append("Repeated Super+Space retains one process and the two-line draft")
                key("-M", "ctrl", "-k", "Return", "-m", "ctrl")
                request_file = fixture.with_suffix(".request")
                wait_for(request_file.exists, "explicit Ask")
                assert json.loads(request_file.read_text())["argv"][-1] == "draft persists\nsecond line"
                time.sleep(.5)
                capture("conversation-void", whole=True)
                assert all(captures["root-void"][k] == captures["conversation-void"][k] for k in ("width", "height"))
                checks.append("Root and conversation share one normal size, font, key row and configured footer")
                key("unfinished follow-up")
                key("-k", "Next")
                key("-k", "F2")
                key("-k", "F2")
                capture("conversation-scroll-void")
                checks.append("The full fixture answer scrolls; F2 preserves the follow-up draft")
                key("-M", "logo", "-k", "f", "-m", "logo")
                assert windows()[0]["fullscreen_mode"] == 1
                capture("fullscreen-void")
                key("-M", "logo", "-k", "f", "-m", "logo")
                assert windows()[0]["fullscreen_mode"] == 0
                checks.append("Native fullscreen and restore retain the same home process")
                key("-M", "logo", "-k", "Left", "-m", "logo")
                left = windows()[0]
                assert left["id"] == first["id"] and left["rect"]["width"] == area["width"] // 2
                capture("snapped-left-void")
                key("-M", "logo", "-k", "Right", "-m", "logo")
                right = windows()[0]
                assert right["id"] == first["id"] and right["rect"]["x"] > left["rect"]["x"]
                capture("snapped-right-void")
                checks.append("Native left and right placement retains the home process and draft")
                sway("[con_id=%d] resize set width 400 px height 500 px" % first["id"])
                time.sleep(3)
                capture("narrow-void")
                footer_gap()
                assert "unfinished follow-up" in "\n".join(screen()), "draft survives snap, fullscreen and resize"
                assert "conversati" in screen()[0].lower(), "resize changed the conversation view"
                key("-k", "Escape")
                key("-k", "F2")
                key("help", "-k", "Return")
                time.sleep(1)
                assert "in home" in "\n".join(screen()), "help opens on the dialog's own keys at the narrow size"
                capture("help-void")
                checks.append("Narrow keys wrap whole groups on the key bar; help opens at the narrow size")
                close_home()

                # help at the window's own size: the desktop's subjects are on the first page there
                open_home()
                key("help", "-k", "Return")
                time.sleep(1)
                text = "\n".join(screen())
                assert "in home" in text and "windows" in text and "Super+Return" in text, "help is a list by subject with the desktop's keys: " + text
                capture("help-full-void")
                checks.append("Help lists the dialog's and the desktop's keys by subject, with their chips")
                close_home()

                open_home()
                key("about", "-k", "Return")
                time.sleep(1)
                text = "\n".join(screen())
                assert "spark-shell" in text and "project" in text and "license" in text and "credits" in text and "installed at" in text, "about is the facts and the four rows: " + text
                capture("about-void")
                key("license", "-k", "Return")
                time.sleep(1)
                assert "MIT License" in "\n".join(screen()), "the license opens as a page"
                key("-k", "Escape")
                time.sleep(1)
                assert "credits" in "\n".join(screen()), "Esc comes back to about"
                checks.append("About shows the release, the dialog's version, project, license, credits and help; the license is a page and Esc comes back")
                close_home()

                open_home()
                key("power", "-k", "Return")
                time.sleep(1)
                text = "\n".join(screen())
                assert "lock" in text and "logout" in text, "power's rows are one word each: " + text
                key("logout", "-k", "Return")
                time.sleep(1)
                text = "\n".join(screen())
                assert "keep working" in text and "every window closes" in text, "logout asks on the question page: " + text
                capture("question-void")
                key("-k", "Return")   # keep working is lit first: Enter keeps
                time.sleep(1)
                assert "keep working" not in "\n".join(screen()) and windows(), "keep working keeps the session and comes back"
                checks.append("Power is five verbs; logout asks on a question page and keep working comes back")
                close_home()

                first = open_home()
                control("attach")
                key("long-attachment", "-k", "Down", "-k", "Return")
                time.sleep(1)
                assert "remove" in "\n".join(screen()), "attachment picker did not return its file"
                sway("[con_id=%d] resize set width 396 px height 492 px" % first["id"])
                time.sleep(2)
                footer_gap()
                control("talk")
                wait_for(fixture.with_suffix(".listening").exists, "native Talk click")
                assert "cancel" in "\n".join(screen())
                capture("narrow-attachment-void")
                control("cancel")
                assert "talk" in "\n".join(screen())
                control("remove")
                assert "remove" not in "\n".join(screen())
                control("model")
                assert "model" in screen()[0].lower()
                key("-k", "Escape")
                control("attach")
                assert "pick a file" in "\n".join(screen())
                checks.append("At 36 columns with a long attachment, Talk, Cancel, Remove, Model and Attach clicks reach their displayed controls")
                close_home()

                (settings / "home-keys.json").write_text('{"ask": "F4"}\n')
                open_home()
                key("configured request", "-k", "F4")
                wait_for(lambda: json.loads(request_file.read_text())["argv"][-1] == "configured request", "configured F4 Ask")
                checks.append("Configured F4 reaches the same explicit Ask action")
                close_home()

                (settings / "home-keys.json").unlink()
                fixture.with_suffix(".unavailable").touch()
                previous_request = request_file.read_text()
                open_home()
                capture("root-unavailable-void", whole=True)
                key("unavailable draft")
                key("-M", "ctrl", "-k", "Return", "-m", "ctrl")
                assert request_file.read_text() == previous_request
                capture("unavailable-ask-void")
                checks.append("Unavailable model and voice keep the configured footer visible; Ask retains the draft and makes no model request")
            finally:
                if keyboard:
                    keyboard.terminate()
                    keyboard.wait(timeout=5)
                if pointer:
                    pointer.close()
                compositor.terminate()
                try:
                    compositor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                stop_round(env)
    (evidence / "native.json").write_text(json.dumps({"platform": "Void Linux", "tools": ["sway", "swaybar", "foot", "wtype", "grim", "persistent virtual pointer"],
                                                     "binary_sha256": hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
                                                     "palette": palette,
                                                     "display": {"width": 1440, "height": 1000, "usable_area": area},
                                                     "fixtures": ["model response", "voice availability"],
                                                     "tools": ["attach", "model/source", "talk"],
                                                     "captures": captures, "checks": checks}, indent=2) + "\n")
    for check in checks:
        print("ok: " + check)


if __name__ == "__main__":
    main(*sys.argv[1:])
