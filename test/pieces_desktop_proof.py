#!/usr/bin/env python3
"""Animations for any palette (#247, arc 2) in an isolated native Sway/foot session. No user desktop changes.

Usage: python3 test/pieces_desktop_proof.py BINARY EVIDENCE_DIRECTORY [BASELINE_BINARY]

One headless sway, foot in Monaspace Neon as the desktop draws it. A theme is made from a picture with
`spark-shell theme picture` as a person types it; home then opens and plays its piece, which the dialog
draws in the picture's palette (no GIF exists for it), captured as it opens; the same for each piece by
`theme animation NAME`. Then home is opened 8 times with the animation off, from `desktop home` to its
window in sway's tree, with BINARY and, when given, with BASELINE_BINARY: the time an open takes must
not grow. Needs sway, swaymsg, foot, grim, rsvg-convert, and Monaspace Neon as spark-shell installs it.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
PIECES = ("moon", "ripple", "tide", "embers", "sun", "flight")


def load(name):
    spec = importlib.util.spec_from_file_location(name, REPO / "test" / (name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


home = load("home_desktop_proof")
families = load("glyph_families_desktop_proof")
wait_for = home.wait_for


def main(binary, destination, baseline=None):
    for tool in ("sway", "swaymsg", "foot", "grim", "rsvg-convert"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    neon = data_home / "fonts/monaspace-neon"
    if not (neon / "MonaspaceNeon-Regular.otf").is_file():
        raise SystemExit("no Monaspace Neon in " + str(neon))
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    binaries = [("this build", str(Path(binary).resolve()))] + ([("baseline", str(Path(baseline).resolve()))] if baseline else [])
    checks, opens = [], {}
    with tempfile.TemporaryDirectory(prefix="pieces-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        (root / "data/fonts").mkdir(parents=True)
        (root / "data/fonts/monaspace-neon").symlink_to(neon)
        settings = root / ".config/spark-shell"
        settings.mkdir(parents=True)
        (settings / "config").write_text("DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_MODEL=yes\n")
        (root / ".config/spark").mkdir()
        shutil.copyfile(REPO / "gallery/theme/tokyonight-night.env", root / ".config/spark/theme.env")
        bin_ = root / "bin"
        bin_.mkdir()
        (bin_ / "spark").write_text("#!/usr/bin/env python3\nimport sys\nif sys.argv[1] == 'model': print('fixture-model\\tserving')\n")
        (bin_ / "spark").chmod(0o700)
        (root / ".config/foot").mkdir()
        drawing = REPO / "gallery/wallpaper" / "dunes.png"
        if not drawing.is_file():
            drawing = next(p for p in sorted((REPO / "gallery/wallpaper").glob("*.png")))
        (root / "pictures").mkdir()
        picture = root / "pictures" / drawing.name   # a picture comes from under the home
        shutil.copyfile(drawing, picture)
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"),
               "PATH": str(bin_) + os.pathsep + os.environ["PATH"],
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": binaries[0][1], "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1",
               "SPARK_SHELL_PTS_DIR": str(root / "ptys"), "SPARK_SHELL_ROOT": str(root / "sysroot"), "SPARK_SHELL_SEMANTIC_URL": "none"}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_DIALOG_WINDOW", "GLYPH_FAMILY", "DIALOG_ANIMATION", "THEME"):
            env.pop(key, None)

        def shell(*args):
            r = subprocess.run(["sh", str(REPO / "spark-shell"), *args], env=env, text=True, capture_output=True, timeout=120)
            return r.returncode, (r.stdout + r.stderr).strip()

        # the theme from a picture, before sway: the palette made, the look applied; its foot.ini then this proof's
        st, said = shell("theme", "picture", str(picture))
        checks.append({"check": "theme picture " + picture.name, "said": said.splitlines()[0] if said else "", "ok": st == 0})
        cfg = (settings / "config").read_text()
        look = next((l.split("=", 1)[1] for l in cfg.splitlines() if l.startswith("THEME=")), "")
        st, trn = shell("theme", "animation")
        checks.append({"check": "the look plays a piece", "theme": look, "said": trn, "ok": st == 0 and not trn.startswith("animation none")})
        colors, palette = home.native_foot_config(root)
        ini = (root / ".config/foot/foot.ini").read_text().replace("font=monospace:size=12", "font=Monaspace Neon:size=11")
        (root / ".config/foot/foot.ini").write_text(ini)
        template = (REPO / "template/.config/foot/dialog.ini").read_text()
        for old, new in {"@HOME@": tmp, "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "0x0", "@FOOT_COLORS@": colors, "@PANEL_BG@": palette["colors"]["PANEL_BG"]}.items():
            template = template.replace(old, new)
        (root / ".config/foot/dialog.ini").write_text(template)
        config = root / "sway.conf"
        config.write_text("set $mod Mod4\noutput HEADLESS-1 mode 1200x900\nxwayland disable\ndefault_border none\nseat seat0 fallback true\n"
                          'for_window [app_id="spark-dialog"] floating enable, border none, move position center\n')
        shots = []
        with (root / "native.log").open("w") as log:
            compositor = subprocess.Popen(["sway", "-c", str(config)], env=env, stdout=log, stderr=log)
            try:
                env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "sway"))
                env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "wayland")

                def dialogs():
                    tree = json.loads(subprocess.check_output(["swaymsg", "-r", "-t", "get_tree"], env=env, timeout=5))
                    def walk(node):
                        return ([node] if node.get("app_id") == "spark-dialog" else []) + [w for n in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(n)]
                    return walk(tree)

                def close_home():
                    for w in dialogs():
                        subprocess.run(["swaymsg", "[con_id=%d] kill" % w["id"]], env=env, capture_output=True, timeout=5)
                    wait_for(lambda: not dialogs(), "home closed")

                def open_home():
                    t0 = time.monotonic()
                    subprocess.run(["swaymsg", "exec", str(REPO / "spark-shell") + " desktop home"], env=env, check=True, capture_output=True, timeout=5)
                    w = None
                    while time.monotonic() - t0 < 20:
                        d = dialogs()
                        if d:
                            w = d[0]
                            break
                        time.sleep(0.005)
                    if w is None:
                        raise AssertionError("no home window")
                    return w, (time.monotonic() - t0) * 1000

                # each piece in the picture's palette, as it opens: the first frames, a third of a second apart
                for piece in PIECES:
                    st, said = shell("theme", "animation", piece)
                    w, _ = open_home()
                    r = w["rect"]
                    frames = []
                    for k in range(3):
                        time.sleep(0.33)
                        p = evidence / ("%s-%d.png" % (piece, k))
                        subprocess.run(["grim", "-g", "%d,%d %dx%d" % (r["x"], r["y"], r["width"], r["height"]), str(p)], env=env, check=True)
                        frames.append(p)
                    shots.append((piece, frames))
                    checks.append({"check": "theme animation " + piece, "said": said, "ok": st == 0})
                    close_home()
                # the opening's time with the animation off, 8 opens each binary
                shell("theme", "animation", "none")
                for label, b in binaries:
                    env["SPARK_SHELL_DIALOG"] = b
                    times = []
                    for _ in range(9):
                        _, ms = open_home()
                        times.append(ms)
                        time.sleep(0.6)
                        close_home()
                    opens[label] = [round(t) for t in times[1:]]   # the first warms the caches
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    compositor.kill()
    pal = palette["colors"]
    families.sheet(evidence / "pieces.png", "every piece in a palette made from a picture (%s)" % picture.name,
                   [[("%s, %.1f s in" % (piece, 0.33 * (k + 1)), p) for k, p in enumerate(frames)] for piece, frames in shots], pal)
    summary = {label: {"median_ms": statistics.median(t), "each_ms": t} for label, t in opens.items()}
    if baseline:
        grew = summary["this build"]["median_ms"] - summary["baseline"]["median_ms"]
        checks.append({"check": "home opens no slower with the animation off", "grew_ms": grew, "ok": grew <= 20})
    (evidence / "pieces.json").write_text(json.dumps({"checks": checks, "opens": summary}, indent=1))
    print(json.dumps({"checks": checks, "opens": summary}, indent=1))
    if any(not c["ok"] for c in checks):
        raise SystemExit("failed")
    print("pieces proof: every piece drawn in a picture's palette, sheets in " + str(evidence))


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
