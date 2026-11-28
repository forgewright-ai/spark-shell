#!/usr/bin/env python3
"""triptych_check.py [REPO] -- every bundled theme is three pictures, all different: one for a turned screen and two
landscapes (the owner's rule, 2026-11-27). A theme brings them by what its wallpaper is:
  a picture   its family (family.json in its folder): a portrait and the panels for two screens, three files
  a scene     the scene's portrait composition and its second landscape (lib/wallpaper.py --info: views 1 and 2)
  a drawing   gallery/wallpaper/NAME.svg beside NAME-portrait.svg and NAME-2.svg
Prints one line a theme that breaks it and exits 1; a scene is judged only where numpy is here (the engine needs it).
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))


def look(path):
    out = {}
    try:
        for line in open(path, encoding="utf-8"):
            k, sep, v = line.strip().partition("=")
            if sep:
                out[k] = v
    except OSError:
        pass
    return out


def shell_words(name):
    text = open(os.path.join(REPO, "src", "look.sh"), encoding="utf-8").read()
    return re.search(r'^%s="([^"]*)"' % name, text, re.M).group(1).split()


SHIPPED = {e.split(":")[0]: e.split(":")[1] for e in shell_words("WALL_SHIPPED")}
SCENES = set(shell_words("WALL_SCENES"))


def scene_views(name):
    try:
        got = subprocess.run([sys.executable, "-I", os.path.join(REPO, "lib", "wallpaper.py"), "--info", "--scene", name],
                             capture_output=True, text=True, timeout=60)
        return json.loads(got.stdout) if got.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def main():
    try:
        import numpy  # noqa: F401 -- the engine's own need
        scenes_here = True
    except ImportError:
        scenes_here = False
    bad, n = [], 0
    for line in open(os.path.join(REPO, "gallery", "core", "themes.tsv"), encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if not parts[0]:
            continue
        name, folder = parts[0], (parts[1] if len(parts) > 1 else parts[0])
        n += 1
        d = os.path.join(REPO, "gallery", "core", folder)
        lk = look(os.path.join(d, "look.env")) if os.path.isdir(d) else {}
        wall = lk.get("WALLPAPER") or next((w for w, p in SHIPPED.items() if p == name), "")
        if wall == "picture":
            try:
                fam = json.load(open(os.path.join(d, "family.json"), encoding="utf-8"))
            except (OSError, ValueError):
                bad.append("%s: a picture with no family.json to name its portrait and second landscape" % name)
                continue
            me = next((v for v in fam.get("variants", {}).values() if v.get("theme") == folder), {})
            two = [p.get("landscape") for p in (me.get("panels") or {}).get("2", [])]
            files = [me.get("portrait")] + two
            if len(two) != 2 or None in files or len(set(files)) != 3:
                bad.append("%s: its family names %s, not a portrait and two landscapes all different" % (name, files))
            elif not all(os.path.isfile(os.path.join(d, f)) for f in files):
                bad.append("%s: a picture its family names is not in its folder" % name)
        elif wall in SCENES:
            if not scenes_here:
                continue
            info = scene_views(wall)
            if not info or "portrait" not in info.get("orientations", []) or 2 not in info.get("views", []):
                bad.append("%s: the scene %s has no %s" % (name, wall, "portrait" if info and "portrait" not in info.get("orientations", []) else "second landscape"))
        elif wall in SHIPPED:
            for v in ("portrait", "2"):
                if not os.path.isfile(os.path.join(REPO, "gallery", "wallpaper", "%s-%s.svg" % (wall, v))):
                    bad.append("%s: the drawing %s has no %s-%s.svg" % (name, wall, wall, v))
        else:
            bad.append("%s: its wallpaper %r brings no pictures of its own" % (name, wall))
    for b in bad:
        print(b)
    print("triptych_check: %d themes, %d without three pictures%s" % (n, len(bad), "" if scenes_here else " (scenes not judged: no numpy)"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
