#!/usr/bin/env python3
"""The glyph families (#248) in an isolated native Sway/foot session. No user desktop changes.

Usage: python3 test/glyph_families_desktop_proof.py BINARY EVIDENCE_DIRECTORY

One headless sway with spark-shell's own bar (its status line, its workspaces named by the family),
foot in Monaspace Neon at 11 as the desktop draws it, a fixture battery and backlight for the gauges,
and the dialog BINARY. Three rounds, stone, star and banner: `spark-shell theme family NAME` as a
person types it, then the bar, Settings > theme, the workspace place and a thought's waiting frames,
each captured with grim. A sheet per family puts them together (rsvg-convert), and families.png sets
the three side by side. Needs sway, swaymsg, swaybar, foot, grim, wtype, rsvg-convert, and the four
faces of Monaspace Neon spark-shell installs.
"""
import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
FAMILIES = ("stone", "star", "banner")
LABELS = {  # workspace N on the bar, as the family names it
    "stone": lambda n: "\u27e8%d\u27e9" % n,
    "star": lambda n: "{%d}" % n,
    "banner": lambda n: "[%d]" % n,
}
SPACES = (1, 2, 3, 7)


def load(name):
    spec = importlib.util.spec_from_file_location(name, REPO / "test" / (name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


home = load("home_desktop_proof")
wait_for = home.wait_for


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def sheet(out, title, parts, palette):
    """parts: rows of (label, png); each row's pictures side by side, the label over each."""
    pad, gap, label_h = 24, 24, 26
    rows, width, y = [], 0, pad + 34
    for row in parts:
        x, h = pad, 0
        cells = []
        for label, png in row:
            w, ph = png_size(png)
            cells.append((x, y, w, ph, label, png))
            x += w + gap
            h = max(h, ph)
        width = max(width, x - gap + pad)
        rows.append(cells)
        y += label_h + h + gap
    height = y + pad - gap
    bg, fg, muted = "#" + palette["PANEL_BG"], "#" + palette["HEX_FG"], "#" + palette["PANEL_MUTED"]
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%d" height="%d">' % (width, height),
           '<rect width="100%%" height="100%%" fill="%s"/>' % bg,
           '<text x="%d" y="%d" fill="%s" font-family="Monaspace Neon" font-size="22">%s</text>' % (pad, pad + 18, fg, title)]
    for cells in rows:
        for x, cy, w, ph, label, png in cells:
            data = base64.b64encode(Path(png).read_bytes()).decode()
            svg.append('<text x="%d" y="%d" fill="%s" font-family="Monaspace Neon" font-size="15">%s</text>' % (x, cy + 17, muted, label))
            svg.append('<image x="%d" y="%d" width="%d" height="%d" xlink:href="data:image/png;base64,%s"/>' % (x, cy + label_h, w, ph, data))
    svg.append("</svg>")
    src = Path(str(out) + ".svg")
    src.write_text("\n".join(svg))
    subprocess.run(["rsvg-convert", "-o", str(out), str(src)], check=True)
    src.unlink()


def main(binary, destination):
    for tool in ("sway", "swaymsg", "swaybar", "foot", "grim", "wtype", "rsvg-convert"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    neon = data_home / "fonts/monaspace-neon"
    if not (neon / "MonaspaceNeon-Regular.otf").is_file():
        raise SystemExit("no Monaspace Neon in " + str(neon) + ": spark-shell on installs it")
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    binary = str(Path(binary).resolve())
    checks = []
    with tempfile.TemporaryDirectory(prefix="families-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        (root / "data/fonts").mkdir(parents=True)
        (root / "data/fonts/monaspace-neon").symlink_to(neon)
        settings = root / ".config/spark-shell"
        settings.mkdir(parents=True)
        (settings / "config").write_text("DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\nDIALOG_MODEL=yes\nDIALOG_TALK=yes\nGLYPH_FAMILY=stone\n")
        (root / ".config/spark").mkdir()
        shutil.copyfile(REPO / "gallery/theme/tokyonight-night.env", root / ".config/spark/theme.env")
        bin_ = root / "bin"
        bin_.mkdir()
        (bin_ / "spark").write_text('''#!/usr/bin/env python3
import sys, time
if sys.argv[1] == 'model': print('fixture-model\\tserving')
elif sys.argv[1] == 'client': print('spark client -- local')
elif sys.argv[1] == 'voice': sys.exit(1)
elif len(sys.argv) == 2:
    time.sleep(40)   # a thought that takes its time: the header's frames stay up to be seen
    print('A fixture answer.')
''')
        (bin_ / "brightnessctl").write_text('#!/bin/sh\ncase "$*" in "-m -c backlight info") echo "amdgpu_bl1,backlight,120,47%,255" ;; esac\n')
        for f in ("spark", "brightnessctl"):
            (bin_ / f).chmod(0o700)
        sysfs = root / "sys/class"
        (sysfs / "backlight/amdgpu_bl1").mkdir(parents=True)
        bat = sysfs / "power_supply/BAT0"
        bat.mkdir(parents=True)
        (bat / "type").write_text("Battery\n")
        (bat / "capacity").write_text("64\n")
        (bat / "status").write_text("Discharging\n")
        (root / ".config/foot").mkdir()
        colors, palette = home.native_foot_config(root)
        ini = (root / ".config/foot/foot.ini").read_text().replace("font=monospace:size=12", "font=Monaspace Neon:size=11")
        (root / ".config/foot/foot.ini").write_text(ini)
        template = (REPO / "template/.config/foot/dialog.ini").read_text()
        for old, new in {"@HOME@": tmp, "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "0x0", "@FOOT_COLORS@": colors, "@PANEL_BG@": palette["colors"]["PANEL_BG"]}.items():
            template = template.replace(old, new)
        (root / ".config/foot/dialog.ini").write_text(template)
        c = palette["colors"]
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"),
               "PATH": str(bin_) + os.pathsep + os.environ["PATH"],
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": binary, "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1",
               "SPARK_SHELL_PTS_DIR": str(root / "ptys"), "SPARK_SHELL_ROOT": str(root / "sysroot"), "SPARK_SHELL_SYS": str(root / "sys"), "SPARK_SHELL_SEMANTIC_URL": "none"}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_DIALOG_WINDOW", "GLYPH_FAMILY"):
            env.pop(key, None)
        config = root / "sway.conf"
        config.write_text("\n".join([
            "set $mod Mod4", "output HEADLESS-1 mode 1440x900", "xwayland disable", "default_border none",
            "bar {", " position top", " font pango:Monaspace Neon 11", " status_command " + str(REPO / "spark-shell") + " bar status",
            " workspace_buttons yes", " strip_workspace_numbers yes", " status_padding 2", " status_edge_padding 10",
            " colors {", "  background #%s" % c["HEX_ANSI_0"], "  statusline #%s" % c["HEX_FG"],
            "  focused_workspace #{0} #{0} #{1}".format(c["HEX_ACCENT"], c["HEX_ANSI_0"]),
            "  inactive_workspace #{0} #{0} #{1}".format(c["HEX_ANSI_0"], c["HEX_MUTED"]), " }", "}",
            "seat seat0 fallback true",
            'for_window [app_id="spark-dialog"] floating enable, border none, move position center', ""]))
        shots = {f: {} for f in FAMILIES}
        with (root / "native.log").open("w") as log:
            compositor = subprocess.Popen(["sway", "-c", str(config)], env=env, stdout=log, stderr=log)
            keyboard = None
            try:
                env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "sway"))
                env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "wayland")
                keyboard = subprocess.Popen(["wtype", "-s", "600000"], env=env, stdout=log, stderr=log)

                def sway(*args):
                    return json.loads(subprocess.check_output(["swaymsg", "-r", *args], env=env, timeout=5))

                def dialogs():
                    def walk(node):
                        return ([node] if node.get("app_id") == "spark-dialog" else []) + [w for n in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(n)]
                    return walk(sway("-t", "get_tree"))

                def names():
                    return {w["num"]: w["name"] for w in sway("-t", "get_workspaces")}

                def grab(name, geometry=None):
                    path = evidence / (name + ".png")
                    subprocess.run(["grim", *(["-g", geometry] if geometry else ["-o", "HEADLESS-1"]), str(path)], env=env, check=True)
                    print("captured: " + path.name, flush=True)
                    return path

                def open_home(view=""):
                    subprocess.run(["swaymsg", "exec", str(REPO / "spark-shell") + " desktop home " + view], env=env, check=True, capture_output=True, timeout=5)
                    w = wait_for(lambda: dialogs() and dialogs()[0], "home window")
                    time.sleep(3)
                    return w

                def close_home():
                    for w in dialogs():
                        sway("[con_id=%d] kill" % w["id"])
                    wait_for(lambda: not dialogs(), "home closed")

                def key(*args):
                    subprocess.run(["wtype", "-s", "80", *args], env=env, check=True, timeout=10)
                    time.sleep(.2)

                # four workspaces with a terminal each, then the first in front
                for n in SPACES:
                    sway("workspace number %d" % n)
                    subprocess.run(["swaymsg", "exec", "foot -e sh -c 'sleep 600'"], env=env, check=True, capture_output=True, timeout=5)
                    time.sleep(.6)
                sway("workspace number 1")
                for family in FAMILIES:
                    out = subprocess.run(["sh", str(REPO / "spark-shell"), "theme", "family", family], env=env, text=True, capture_output=True, timeout=30)
                    said = (out.stdout + out.stderr).strip()
                    if family == "stone":   # the config's already: the verb says so, and the names are stone's
                        ok = said == "the glyph family is stone already"
                    else:
                        ok = out.returncode == 0 and said == "glyph family " + family
                    checks.append({"family": family, "check": "theme family " + family, "said": said, "ok": ok})
                    want = {n: "%d:%s" % (n, LABELS[family](n)) for n in SPACES}
                    got = wait_for(lambda: names() if all(names().get(n) == want[n] for n in SPACES) else None, family + " workspace names")
                    checks.append({"family": family, "check": "the workspaces named by the family", "names": [got[n] for n in SPACES], "ok": True})
                    time.sleep(2.5)   # the bar's next line, in the family's gauge pair
                    shots[family]["bar"] = grab(family + "-bar", "0,0 1440x30")
                    w = open_home("theme")
                    r = w["rect"]
                    shots[family]["theme"] = grab(family + "-theme", "{x},{y} {width}x{height}".format(**r))
                    # its settings, under the palettes: a switch's on and off in the family's choice, the family's own row
                    key("-k", "Down")
                    for _ in range(3):
                        key("-k", "Page_Down")
                    time.sleep(.6)
                    shots[family]["settings"] = grab(family + "-settings", "{x},{y} {width}x{height}".format(**r))
                    close_home()
                    w = open_home("window")
                    shots[family]["workspace"] = grab(family + "-workspace", "{x},{y} {width}x{height}".format(**w["rect"]))
                    close_home()
                    # a thought: the words, then Ctrl+Enter asks spark (the fixture holds its answer); the header's frames
                    w = open_home()
                    r = w["rect"]
                    key("what is open")
                    key("-M", "ctrl", "-k", "Return", "-m", "ctrl")
                    time.sleep(.8)
                    frames = []
                    for i in range(4):
                        frames.append(grab("%s-thinking-%d" % (family, i), "{x},{y} {w}x{h}".format(x=r["x"], y=r["y"], w=r["width"], h=40)))
                        time.sleep(.37)
                    shots[family]["thinking"] = frames
                    close_home()
                    shots[family]["screen"] = grab(family + "-screen")
            finally:
                if keyboard:
                    keyboard.terminate()
                compositor.terminate()
                try:
                    compositor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    compositor.kill()
        shutil.copyfile(root / "native.log", evidence / "native.log")
    pal = palette["colors"]
    for family in FAMILIES:
        s = shots[family]
        sheet(evidence / ("sheet-" + family + ".png"), "glyph family: " + family,
              [[("the bar: workspaces, the brightness's gauge, the battery's cells", s["bar"])],
               [("Settings > theme", s["theme"]), ("its settings", s["settings"]), ("the workspace place", s["workspace"])],
               [("thinking, frame %d" % (i + 1), p) for i, p in enumerate(s["thinking"])]], pal)
    sheet(evidence / "families.png", "the glyph families: stone, star, banner",
          [[(f + ": the bar", shots[f]["bar"])] for f in FAMILIES] +
          [[(f + ": Settings > theme", shots[f]["settings"]) for f in FAMILIES]] +
          [[(f + ": the workspace place", shots[f]["workspace"]) for f in FAMILIES]] +
          [[(f + ": thinking", shots[f]["thinking"][0]) for f in FAMILIES]], pal)
    (evidence / "families.json").write_text(json.dumps({"checks": checks}, indent=1))
    failed = [c for c in checks if not c["ok"]]
    print(json.dumps(checks, indent=1))
    if failed:
        raise SystemExit("failed: " + json.dumps(failed))
    print("glyph families proof: three families drawn, sheets in " + str(evidence))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
