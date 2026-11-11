#!/usr/bin/env python3
"""Monaspace's five faces (#247, arc 3) in an isolated native Sway/foot session. No user desktop changes.

Usage: python3 test/faces_desktop_proof.py BINARY FACES_DIRECTORY EVIDENCE_DIRECTORY

FACES_DIRECTORY holds the twenty files of the five faces (MonaspaceNeon-Regular.otf ... MonaspaceKrypton-
BoldItalic.otf), out of the zip spark-shell pins. One headless sway; for each face `spark-shell theme face
NAME` as a person types it, foot.ini as spark-shell renders it, then home opened in it and captured. The
window is the same size in every face: the five share Neon's cell. A sheet puts them side by side.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
FACES = ("neon", "argon", "xenon", "radon", "krypton")
STYLES = ("Regular", "Bold", "Italic", "BoldItalic")


def load(name):
    spec = importlib.util.spec_from_file_location(name, REPO / "test" / (name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


home = load("home_desktop_proof")
families = load("glyph_families_desktop_proof")
wait_for = home.wait_for


def main(binary, faces_dir, destination):
    for tool in ("sway", "swaymsg", "foot", "grim", "rsvg-convert"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    faces_dir = Path(faces_dir).resolve()
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    checks, shots = [], []
    with tempfile.TemporaryDirectory(prefix="faces-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        for face in FACES:   # where spark-shell's on puts them: fonts/monaspace-NAME, four styles each
            d = root / "data/fonts" / ("monaspace-" + face)
            d.mkdir(parents=True)
            for s in STYLES:
                f = "Monaspace%s-%s.otf" % (face.capitalize(), s)
                shutil.copyfile(faces_dir / f, d / f)
        settings = root / ".config/spark-shell"
        settings.mkdir(parents=True)
        (settings / "config").write_text("DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\nDIALOG_MODEL=yes\nFONT=Monaspace Neon:size=11\n")
        (root / ".config/spark").mkdir()
        shutil.copyfile(REPO / "gallery/theme/tokyonight-night.env", root / ".config/spark/theme.env")
        bin_ = root / "bin"
        bin_.mkdir()
        (bin_ / "spark").write_text("#!/usr/bin/env python3\nimport sys\nif sys.argv[1] == 'model': print('fixture-model\\tserving')\n")
        (bin_ / "spark").chmod(0o700)
        (root / ".config/foot").mkdir()
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"), "XDG_CACHE_HOME": str(root / "cache"),
               "PATH": str(bin_) + os.pathsep + os.environ["PATH"],
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": str(Path(binary).resolve()), "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1",
               "SPARK_SHELL_PTS_DIR": str(root / "ptys"), "SPARK_SHELL_ROOT": str(root / "sysroot"), "SPARK_SHELL_SEMANTIC_URL": "none"}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_DIALOG_WINDOW", "FONT", "THEME"):
            env.pop(key, None)
        subprocess.run(["fc-cache", "-f"], env=env, capture_output=True)
        colors, palette = home.native_foot_config(root)
        template = (REPO / "template/.config/foot/dialog.ini").read_text()
        for old, new in {"@HOME@": tmp, "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "0x0", "@FOOT_COLORS@": colors, "@PANEL_BG@": palette["colors"]["PANEL_BG"]}.items():
            template = template.replace(old, new)
        (root / ".config/foot/dialog.ini").write_text(template)
        base_ini = (root / ".config/foot/foot.ini").read_text()
        config = root / "sway.conf"
        config.write_text("output HEADLESS-1 mode 1200x900\nxwayland disable\ndefault_border none\nseat seat0 fallback true\n"
                          'for_window [app_id="spark-dialog"] floating enable, border none, move position center\n')

        def shell(*args):
            r = subprocess.run(["sh", str(REPO / "spark-shell"), *args], env=env, text=True, capture_output=True, timeout=120)
            return r.returncode, (r.stdout + r.stderr).strip()

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

                sizes = set()
                for face in FACES[1:] + FACES[:1]:   # neon last: back to it from krypton, so spark-shell renders it too
                    st, said = shell("theme", "face", face)
                    ok = st == 0
                    # foot's font line as spark-shell renders it; this proof's colors around it
                    rendered = (root / ".config/foot/foot.ini").read_text() if (root / ".config/foot/foot.ini").is_file() else ""
                    font = next((l for l in rendered.splitlines() if l.startswith("font=")), "")
                    want = "font=Monaspace %s:size=11,DejaVu Sans Mono:size=11" % face.capitalize()
                    checks.append({"face": face, "said": said, "font": font, "ok": ok and font == want})
                    (root / ".config/foot/foot.ini").write_text(base_ini.replace("font=monospace:size=12", font or "font=monospace:size=11"))
                    subprocess.run(["swaymsg", "exec", str(REPO / "spark-shell") + " desktop home theme"], env=env, check=True, capture_output=True, timeout=5)
                    w = wait_for(lambda: dialogs() and dialogs()[0], face + " home")
                    time.sleep(3)
                    r = dialogs()[0]["rect"]
                    sizes.add((r["width"], r["height"]))
                    p = evidence / ("face-%s.png" % face)
                    subprocess.run(["grim", "-g", "%d,%d %dx%d" % (r["x"], r["y"], r["width"], r["height"]), str(p)], env=env, check=True)
                    shots.append((face, p))
                    for d in dialogs():
                        subprocess.run(["swaymsg", "[con_id=%d] kill" % d["id"]], env=env, capture_output=True, timeout=5)
                    wait_for(lambda: not dialogs(), face + " closed")
                checks.append({"check": "one window size in every face: one cell", "sizes": sorted(sizes), "ok": len(sizes) == 1})
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    compositor.kill()
    shots.sort(key=lambda s: FACES.index(s[0]))
    families.sheet(evidence / "faces.png", "Monaspace's five faces, home's Settings > theme in each, at size 11",
                   [[("theme face " + f, p) for f, p in shots[:3]], [("theme face " + f, p) for f, p in shots[3:]]], palette["colors"])
    (evidence / "faces.json").write_text(json.dumps({"checks": checks}, indent=1))
    print(json.dumps(checks, indent=1))
    if any(not c["ok"] for c in checks):
        raise SystemExit("failed")
    print("faces proof: the five faces drawn by foot, sheets in " + str(evidence))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
