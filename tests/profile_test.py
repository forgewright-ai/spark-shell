#!/usr/bin/env python3
# tests for lib/terminal_profile.py -- plain asserts, standard library only,
# runnable with Apple's /usr/bin/python3. SPARK_SHELL_NO_APPLY=1 on every
# run of the helper: Terminal.app is never touched, and HOME is a throwaway.

import os
import plistlib
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
HELPER = os.path.join(REPO, "lib", "terminal_profile.py")
sys.path.insert(0, os.path.join(REPO, "lib"))
import terminal_profile as tp  # noqa: E402

TMP = tempfile.mkdtemp(prefix="spark-shell-profile-")
passed = 0


def ok(cond, what):
    global passed
    if not cond:
        sys.stderr.write("FAIL %s\n" % what)
        sys.exit(1)
    passed += 1


def helper(*args, **env_extra):
    env = {"PATH": "/usr/bin:/bin", "HOME": TMP, "XDG_CONFIG_HOME": os.path.join(TMP, "config"),
           "SPARK_SHELL_NO_APPLY": "1"}
    env.update(env_extra)
    p = subprocess.run([sys.executable, HELPER] + list(args), stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, universal_newlines=True, env=env, timeout=60)
    return p.returncode, p.stdout, p.stderr


def rgb(h):
    h = h.lstrip("#")
    return "%.6f %.6f %.6f" % tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# --- every palette in themes/ reads whole ---------------------------------
themes = sorted(f for f in os.listdir(os.path.join(REPO, "themes")) if f.endswith(".env"))
ok(len(themes) == 9, "9 palettes in themes/, found %d" % len(themes))
for t in themes:
    path = os.path.join(REPO, "themes", t)
    with open(path, encoding="utf-8") as f:
        first = f.readline()
    ok(first.startswith("# ") and "http" in first and "(" in first, "%s: the upstream and licence header" % t)
    ok(tp.read_theme(path) is not None, "%s: 20 THEME_* keys, each #rrggbb" % t)

# --- a profile from a sample theme.env ----------------------------------
sample = os.path.join(TMP, "theme.env")
keys = {"THEME_BG": "#282828", "THEME_FG": "#ebdbb2", "THEME_ACCENT": "#fe8019", "THEME_MUTED": "#928374"}
for i in range(16):
    keys["THEME_ANSI_%d" % i] = "#%02x%02x%02x" % (i * 10, 255 - i * 10, i * 5)
with open(sample, "w", encoding="utf-8") as f:
    f.write("# a sample palette\n")
    f.write("".join("%s=%s\n" % kv for kv in keys.items()))

pal = tp.read_theme(sample)
ok(pal == keys, "read_theme returns the 20 keys")
d = tp.profile_dict("spark-shell", pal, "Monaco", 15)
ok(d["name"] == "spark-shell", "the profile is named spark-shell")
ok("keyMapBoundKeys" not in d, "no key map: key bindings are an app's business")
back = tp.read_back(plistlib.dumps(d, fmt=plistlib.FMT_BINARY))
ok(back["BackgroundColor"] == rgb(keys["THEME_BG"]), "background is THEME_BG")
ok(back["TextColor"] == rgb(keys["THEME_FG"]), "text is THEME_FG")
ok(back["CursorColor"] == rgb(keys["THEME_ACCENT"]), "cursor is THEME_ACCENT")
ok(back["SelectionColor"] == rgb(keys["THEME_ANSI_0"]), "selection is ANSI 0")
for i, name in enumerate(tp.ANSI_NAMES):
    ok(back["ANSI%sColor" % name] == rgb(keys["THEME_ANSI_%d" % i]), "ANSI%sColor is slot %d" % (name, i))
ok(back["Font"] == "Monaco 15.0", "the font is Monaco at 15 points, got %s" % back.get("Font"))

# a palette with a key missing, or a word where hex belongs, is refused
bad = os.path.join(TMP, "bad.env")
with open(bad, "w", encoding="utf-8") as f:
    f.write("THEME_BG=#282828\nTHEME_FG=white\n")
ok(tp.read_theme(bad) is None, "an incomplete palette is None")
ok(tp.read_theme(os.path.join(TMP, "missing.env")) is None, "a missing file is None")

# --- apply under SPARK_SHELL_NO_APPLY=1: builds and prints, Terminal untouched
rc, out, err = helper("apply", sample, "Monaco", "15", SPARK_SHELL_MAC_FONTS="Monaco:Menlo-Regular")
ok(rc == 0, "apply exits 0 (stderr: %s)" % err.strip())
ok(len(out.splitlines()) == 1 and "would" in out and "Monaco" in out and "#282828" in out,
   "apply prints one would line: %r" % out)
ok(err == "", "apply is quiet on stderr")
ok(not os.path.exists(os.path.join(TMP, "config", "spark-shell")), "apply wrote nothing under the config dir")

rc, out, err = helper("apply", sample, "NoSuchFace-Regular", "13", SPARK_SHELL_MAC_FONTS="Monaco")
ok(rc == 1 and out == "" and len(err.splitlines()) == 1 and "NoSuchFace-Regular" in err,
   "a face not installed: exit 1, one line on stderr (%d %r %r)" % (rc, out, err))

rc, out, err = helper("apply", os.path.join(TMP, "missing.env"), "Monaco", "13", SPARK_SHELL_MAC_FONTS="Monaco")
ok(rc == 1 and out == "" and len(err.splitlines()) == 1, "an unreadable theme.env: exit 1, one line on stderr")

rc, out, err = helper("apply", sample, "Monaco", "big", SPARK_SHELL_MAC_FONTS="Monaco")
ok(rc == 1 and len(err.splitlines()) == 1, "a size that is not points: exit 1, one line")

rc, out, err = helper("apply", sample)
ok(rc == 2 and "usage" in err, "apply without FACE SIZE: the usage, exit 2")

# --- remove under SPARK_SHELL_NO_APPLY=1 --------------------------------
rc, out, err = helper("remove")
ok(rc == 0 and len(out.splitlines()) == 1 and "would" in out and "Basic" in out,
   "remove prints one would line: %r" % out)
ok(not os.path.exists(os.path.join(TMP, "config", "spark-shell")), "remove wrote nothing under the config dir")

# --- fonts and has-font -------------------------------------------------
rc, out, err = helper("fonts", SPARK_SHELL_MAC_FONTS="Monaco:FiraCode-Regular:NotMono")
ok(rc == 0 and out.split() == ["Monaco", "FiraCode-Regular"], "fonts lists the installed MAC_MONO faces in order: %r" % out)
rc, out, err = helper("has-font", "Monaco", SPARK_SHELL_MAC_FONTS="Monaco")
ok(rc == 0, "has-font Monaco: exit 0")
rc, out, err = helper("has-font", "Hack-Regular", SPARK_SHELL_MAC_FONTS="Monaco")
ok(rc == 1, "has-font Hack-Regular, not installed: exit 1")

# the real lookups run (Spotlight on a Mac), whatever they find
rc, out, err = helper("fonts")
ok(rc == 0, "fonts runs without the seam")
if sys.platform == "darwin":
    ok("Menlo-Regular" in out.split(), "every Mac ships Menlo-Regular")
    rc, out, err = helper("has-font", "Menlo-Regular")
    ok(rc == 0, "has-font Menlo-Regular: exit 0 on a Mac")
rc, out, err = helper("has-font", "NoSuchFace-Regular")
ok(rc in (0, 1), "has-font runs without the seam")

rc, out, err = helper("nonsense")
ok(rc == 2 and "usage" in err, "an unknown verb: the usage, exit 2")

print("profile_test: %d passed" % passed)
