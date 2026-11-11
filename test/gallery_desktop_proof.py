#!/usr/bin/env python3
"""The gallery (#247, arc 5): its themes installed and worn in an isolated native Sway/foot session. No user desktop changes.

Usage: python3 test/gallery_desktop_proof.py BINARY FACES_DIRECTORY GALLERY_DIRECTORY EVIDENCE_DIRECTORY

GALLERY_DIRECTORY is a copy of forgewright-ai/spark-shell-gallery. Its tree is committed and tagged gallery-v1 here,
signed with a throwaway key that a copy of this tree's allowed-signers names; the live allowed-signers and the
live home are never read. One headless sway; for each theme in the gallery's index `spark-shell theme install
NAME` as a person types it, then home opened in it and captured: its palette, its face, its glyph family. The
wallpaper is installed too, and checked in the config. FACES_DIRECTORY holds Monaspace's twenty files, as
test/faces_desktop_proof.py takes them.
"""
import hashlib
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


def look(path):
    return dict(l.split("=", 1) for l in Path(path).read_text().splitlines() if "=" in l and not l.startswith("#"))


def main(binary, faces_dir, gallery_dir, destination):
    for tool in ("sway", "swaymsg", "foot", "grim", "rsvg-convert", "git", "ssh-keygen"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    faces_dir, gallery_dir = Path(faces_dir).resolve(), Path(gallery_dir).resolve()
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    checks, shots = [], []
    with tempfile.TemporaryDirectory(prefix="gallery-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        for face in FACES:   # where spark-shell's on puts them: fonts/monaspace-NAME, four styles each
            d = root / "data/fonts" / ("monaspace-" + face)
            d.mkdir(parents=True)
            for s in STYLES:
                f = "Monaspace%s-%s.otf" % (face.capitalize(), s)
                shutil.copyfile(faces_dir / f, d / f)
        # a copy of this tree that trusts a throwaway key, and the gallery tagged gallery-v1 with it, its message the gallery's line
        tree = root / "tree"
        shutil.copytree(REPO, tree, ignore=shutil.ignore_patterns(".git", "target", "target2", ".claude"))
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "", "-f", str(root / "key")], check=True)
        (tree / "allowed-signers").write_text('spark-shell-release namespaces="git" %s\n' % " ".join((root / "key.pub").read_text().split()[:2]))
        gallery = root / "gallery"
        shutil.copytree(gallery_dir, gallery, ignore=shutil.ignore_patterns(".git"))
        git = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_NOSYSTEM": "1"}
        for argv in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-q", "-m", "gallery-v1"],
                     ["-c", "gpg.format=ssh", "-c", "user.signingkey=" + str(root / "key"), "tag", "-s", "-m", "spark-shell-gallery gallery-v1", "gallery-v1"]):
            subprocess.run(["git", "-C", str(gallery), *argv], env=git, check=True)
        index = [l.split("\t") for l in (gallery / "index.tsv").read_text().splitlines()[1:]]
        themes = sorted({n for k, n, *_ in index if k == "theme"})
        walls = [(n, p) for k, n, p, *_ in index if k == "wallpaper"]
        settings = root / ".config/spark-shell"
        settings.mkdir(parents=True)
        (settings / "config").write_text("DESKTOP=sway\nTHEME=nord\nDIALOG_MODEL=yes\nFONT=Monaspace Neon:size=11\n")
        (root / ".config/spark").mkdir()
        shutil.copyfile(REPO / "gallery/theme/nord.env", root / ".config/spark/theme.env")
        bin_ = root / "bin"
        bin_.mkdir()
        (bin_ / "spark").write_text("#!/usr/bin/env python3\nimport sys\nif sys.argv[1] == 'model': print('fixture-model\\tserving')\n")
        (bin_ / "spark").chmod(0o700)
        (bin_ / "sudo").write_text('#!/bin/sh\nexec "$@"\n')   # theme install's root paths (the boot palette) as the person, under SPARK_SHELL_ROOT
        (bin_ / "sudo").chmod(0o700)
        (root / ".config/foot").mkdir()
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"), "XDG_CACHE_HOME": str(root / "cache"),
               "PATH": str(bin_) + os.pathsep + os.environ["PATH"],
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": str(Path(binary).resolve()), "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1",
               "SPARK_SHELL_PTS_DIR": str(root / "ptys"), "SPARK_SHELL_ROOT": str(root / "sysroot"), "SPARK_SHELL_SEMANTIC_URL": "none", "SPARK_SHELL_GALLERY_URL": str(gallery)}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SPARK_DIALOG_WINDOW", "FONT", "THEME"):
            env.pop(key, None)
        subprocess.run(["fc-cache", "-f"], env=env, capture_output=True)
        config = root / "sway.conf"
        config.write_text("output HEADLESS-1 mode 1200x900\nxwayland disable\ndefault_border none\nseat seat0 fallback true\n"
                          'for_window [app_id="spark-dialog"] floating enable, border none, move position center\n')

        def shell(*args):
            r = subprocess.run(["sh", str(tree / "spark-shell"), *args], env=env, text=True, capture_output=True, timeout=180)
            return r.returncode, (r.stdout + r.stderr).strip()

        def dress():   # foot for the theme in use: the font line spark-shell renders from FONT (faces_desktop_proof holds that line), the palette's colors
            fnt = look(settings / "config").get("FONT", "Monaspace Neon:size=11")
            font = "font=%s,DejaVu Sans Mono:size=%s" % (fnt, fnt.split("size=")[-1].split(":")[0])
            colors, palette = home.native_foot_config(root, accent_min=2.5)   # a made palette's accent is 3 to 1 on its ground, a shade less on home's lighter surface
            base = (root / ".config/foot/foot.ini").read_text()
            (root / ".config/foot/foot.ini").write_text(base.replace("font=monospace:size=12", font))
            template = (REPO / "template/.config/foot/dialog.ini").read_text()
            for old, new in {"@HOME@": tmp, "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "0x0", "@FOOT_COLORS@": colors, "@PANEL_BG@": palette["colors"]["PANEL_BG"]}.items():
                template = template.replace(old, new)
            (root / ".config/foot/dialog.ini").write_text(template.replace("font=monospace:size=12", font))
            return font, palette

        st, said = shell("theme", "gallery")
        (evidence / "gallery.txt").write_text(said.replace(str(gallery), "a local copy of forgewright-ai/spark-shell-gallery") + "\n")
        checks.append({"check": "theme gallery lists every theme and wallpaper of the index", "ok": st == 0 and all(("  " + n + " ") in said for n in themes + [w for w, _ in walls])})
        with (root / "native.log").open("w") as log:
            compositor = subprocess.Popen(["sway", "-c", str(config)], env=env, stdout=log, stderr=log)
            palette = None
            try:
                env["SWAYSOCK"] = str(wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "sway"))
                env["WAYLAND_DISPLAY"] = wait_for(lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "wayland")

                def dialogs():
                    tree_ = json.loads(subprocess.check_output(["swaymsg", "-r", "-t", "get_tree"], env=env, timeout=5))
                    def walk(node):
                        return ([node] if node.get("app_id") == "spark-dialog" else []) + [w for n in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(n)]
                    return walk(tree_)

                for name in themes:
                    st, said = shell("theme", "install", name)
                    want = look(gallery / "themes" / name / "look.env")
                    cfg = look(settings / "config")
                    font, palette = dress()
                    worn = {"THEME": cfg.get("THEME") == name,
                            "face": "FACE" not in want or cfg.get("FONT", "").startswith("Monaspace %s:" % want["FACE"].capitalize()),
                            "family": "GLYPH_FAMILY" not in want or cfg.get("GLYPH_FAMILY") == want["GLYPH_FAMILY"],
                            "animation": "ANIMATION" not in want or cfg.get("DIALOG_ANIMATION") == want["ANIMATION"],
                            "kept": (settings / "themes" / name / "palette.env").read_bytes() == (gallery / "themes" / name / "palette.env").read_bytes()}
                    checks.append({"theme": name, "said": said.splitlines()[0] if said else "", "font": font, "worn": worn, "ok": st == 0 and all(worn.values())})
                    subprocess.run(["swaymsg", "exec", str(tree / "spark-shell") + " desktop home theme"], env=env, check=True, capture_output=True, timeout=5)
                    wait_for(lambda: dialogs() and dialogs()[0], name + " home")
                    time.sleep(3)
                    r = dialogs()[0]["rect"]
                    p = evidence / ("theme-%s.png" % name)
                    subprocess.run(["grim", "-g", "%d,%d %dx%d" % (r["x"], r["y"], r["width"], r["height"]), str(p)], env=env, check=True)
                    shots.append(("theme install %s: %s, %s, %s" % (name, want.get("FACE", "-"), want.get("GLYPH_FAMILY", "-"), want.get("ANIMATION", "-")), p))
                    for d in dialogs():
                        subprocess.run(["swaymsg", "[con_id=%d] kill" % d["id"]], env=env, capture_output=True, timeout=5)
                    wait_for(lambda: not dialogs(), name + " closed")
                for name, rel in walls:
                    st, said = shell("theme", "install", name)
                    path = root / "data/spark-shell/gallery" / Path(rel).name
                    same = path.is_file() and hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256((gallery / rel).read_bytes()).digest()
                    checks.append({"wallpaper": name, "said": said.splitlines()[0] if said else "", "ok": st == 0 and same and look(settings / "config").get("WALLPAPER") == str(path)})
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    compositor.kill()
    families.sheet(evidence / "gallery.png", "The gallery's themes, installed by spark-shell theme install and worn: home's Settings > theme in each",
                   [shots], palette["colors"] if palette else {})
    (evidence / "gallery.json").write_text(json.dumps({"checks": checks}, indent=1))
    print(json.dumps(checks, indent=1))
    if any(not c["ok"] for c in checks):
        raise SystemExit("failed")
    print("gallery proof: every theme installed and worn, the wallpaper in place, sheets in " + str(evidence))


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
