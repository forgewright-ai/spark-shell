#!/usr/bin/env python3
# spark-shell's Terminal.app helper: the one place the palette cannot be
# written as a text file. A Terminal.app profile is archived NSColor and
# NSFont objects inside a plist, so it is built here from theme.env and
# the font, and handed to Terminal.app through its preferences.
#
#   terminal_profile.py apply THEME_ENV FACE SIZE
#       build the spark-shell profile, import it, make it the default
#       and set it on every open window
#   terminal_profile.py remove
#       remove the spark-shell profile (and any spark* profile an older
#       spark left), the default back to Basic
#   terminal_profile.py fonts
#       the monospace faces installed here, one PostScript name per line
#   terminal_profile.py has-font FACE
#       exit 0 when the face is installed, 1 when it is not
#
# SPARK_SHELL_NO_APPLY=1 builds and prints, and never touches Terminal.app
# (tests and CI Macs). SPARK_SHELL_MAC_FONTS=A:B:C names the installed
# faces instead of asking Spotlight (tests).
#
# Python 3 standard library only: Apple's /usr/bin/python3 (3.9) runs it.
# Ported from spark 1.61 (lib/spark/theme.py, lib/spark/site.py).

import os
import plistlib
import subprocess
import sys
import time

NAME = "spark-shell"
IS_MAC = sys.platform == "darwin"

THEME_KEYS = (["THEME_BG", "THEME_FG", "THEME_ACCENT", "THEME_MUTED"]
              + ["THEME_ANSI_%d" % i for i in range(16)])

ANSI_NAMES = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
              "BrightBlack", "BrightRed", "BrightGreen", "BrightYellow", "BrightBlue",
              "BrightMagenta", "BrightCyan", "BrightWhite"]

# the monospace faces a Mac may have, by PostScript name; the first five
# are the ones named when Spotlight cannot say
MAC_MONO = ("Menlo-Regular", "Monaco", "SFMono-Regular", "JetBrainsMono-Regular", "Courier",
            "CourierNewPSMT", "AndaleMono", "PTMono-Regular", "FiraCode-Regular", "Hack-Regular",
            "SourceCodePro-Regular", "CascadiaCode-Regular", "UbuntuMono-Regular", "DejaVuSansMono",
            "Inconsolata-Regular", "RobotoMono-Regular", "IBMPlexMono", "VictorMono-Regular")

# the monospace faces every Mac ships (/System/Library/Fonts, outside
# Spotlight's index)
MAC_SYSTEM = {"Menlo-Regular", "Menlo-Bold", "Monaco", "SFMono-Regular", "SFMono-Bold", "Courier",
              "Courier-Bold", "CourierNewPSMT", "AndaleMono"}


def no_apply():
    return bool(os.environ.get("SPARK_SHELL_NO_APPLY"))


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "spark-shell")


def run(argv, timeout=10):
    """(exit code, stdout); 127 when the program is missing or hangs."""
    try:
        p = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=timeout, universal_newlines=True)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


# --- the palette ------------------------------------------------------------

def read_theme(path):
    """The 20 THEME_* keys of a theme.env as a dict, or None when the file
    is unreadable or a key is missing or not #rrggbb."""
    pal = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                pal[k.strip()] = v.strip().strip("'\"")
    except (OSError, UnicodeDecodeError):
        return None
    for k in THEME_KEYS:
        if not _is_hex(pal.get(k, "")):
            return None
    return pal


def _is_hex(v):
    h = v[1:] if v.startswith("#") else ""
    return len(h) == 6 and all(c in "0123456789abcdefABCDEF" for c in h)


def _hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# --- the archive Terminal.app reads ---------------------------------------

def _archive(objects, top_index=1):
    """A minimal NSKeyedArchiver binary plist: $objects[0] is $null."""
    return plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver",
                           "$top": {"root": plistlib.UID(top_index)},
                           "$objects": ["$null"] + objects}, fmt=plistlib.FMT_BINARY)


def ns_color(hexstr):
    r, g, b = _hex_rgb(hexstr)
    return _archive([
        {"$class": plistlib.UID(2), "NSColorSpace": 1,
         "NSRGB": ("%.6f %.6f %.6f" % (r, g, b)).encode() + b"\x00"},
        {"$classname": "NSColor", "$classes": ["NSColor", "NSObject"]},
    ])


def ns_font(name, size):
    return _archive([
        {"$class": plistlib.UID(3), "NSName": plistlib.UID(2), "NSSize": size, "NSfFlags": 16},
        name,
        {"$classname": "NSFont", "$classes": ["NSFont", "NSObject"]},
    ])


def profile_dict(name, pal, font_name="Menlo-Regular", font_size=13.0):
    d = {"name": name, "type": "Window Settings", "ProfileCurrentVersion": 2.07,
         "BackgroundColor": ns_color(pal["THEME_BG"]),
         "TextColor": ns_color(pal["THEME_FG"]),
         "TextBoldColor": ns_color(pal["THEME_FG"]),
         "CursorColor": ns_color(pal["THEME_ACCENT"]),
         "SelectionColor": ns_color(pal["THEME_ANSI_0"]),
         "Font": ns_font(font_name, float(font_size)),
         "columnCount": 120, "rowCount": 36, "useOptionAsMetaKey": True}
    for i, k in enumerate(ANSI_NAMES):
        d["ANSI%sColor" % k] = ns_color(pal["THEME_ANSI_%d" % i])
    return d


def read_back(data):
    """Decode a profile's archived values: the colours as "r g b" and the
    font as "FACE SIZE". Proof the archive is readable."""
    d = plistlib.loads(data) if isinstance(data, bytes) else data
    out = {}
    for k, v in d.items():
        if isinstance(v, bytes):
            a = plistlib.loads(v)
            obj = a["$objects"][1]
            if "NSRGB" in obj:
                out[k] = obj["NSRGB"].rstrip(b"\x00").decode()
            elif "NSName" in obj:
                out[k] = "%s %s" % (a["$objects"][obj["NSName"].data], obj["NSSize"])
    return out


# --- the fonts --------------------------------------------------------------

def mac_font_installed(face):
    """True for a face every Mac ships or one Spotlight finds (kMDItemFonts
    holds PostScript names); False when Spotlight indexes and has no such
    face; None when indexing is off or this is not a Mac, so a caller never
    refuses on no evidence."""
    seam = os.environ.get("SPARK_SHELL_MAC_FONTS")
    if seam is not None:
        return face in seam.split(":")
    if not IS_MAC:
        return None
    if face in MAC_SYSTEM:
        return True
    rc, out = run(["mdfind", "kMDItemFonts == '%s'" % face.replace("'", "")], timeout=5)
    if rc == 0 and out.strip():
        return True
    rc, out = run(["mdutil", "-s", "/"], timeout=5)
    return False if rc == 0 and "Indexing enabled" in out else None


def installed_fonts():
    """MAC_MONO's faces this Mac has. When Spotlight cannot say, the first
    five, the ones a Mac is likely to have."""
    out = []
    for face in MAC_MONO:
        here = mac_font_installed(face)
        if here or (here is None and IS_MAC and face in MAC_MONO[:5]):
            out.append(face)
    return out


def has_font(face):
    """True when the face is here, or on a Mac where Spotlight cannot say."""
    here = mac_font_installed(face)
    return bool(here) or (here is None and IS_MAC)


# --- Terminal.app -----------------------------------------------------------

def _live_sets():
    """The settings sets the RUNNING Terminal.app knows: its own list, not
    the preferences file, which it reads only at launch. [] when it is not
    running or refuses the script."""
    rc, out = run(["osascript", "-e", 'tell application "Terminal" to get name of every settings set'], timeout=8)
    return [n.strip() for n in out.split(",")] if rc == 0 else []


def _switch_windows(name, path, face, size):
    """The running Terminal.app takes the profile now: imported live by
    opening the .terminal file when its list lacks the name (the one live
    import there is; it opens a window with the profile), then made the
    default and set on every tab of every window by script. Returns the
    note: switched, or what remains by hand."""
    live = _live_sets()
    if not live:
        return ", and new windows use it"
    if name not in live:
        run(["open", "-g", path], timeout=8)
        time.sleep(1.5)
        if name not in _live_sets():
            return ", and new windows use it (quit and reopen Terminal.app for the open ones)"
    # the live copy may predate a font change: the face and size go in by script too
    script = ('tell application "Terminal"\nset s to settings set "%s"\n'
              'set font name of s to "%s"\nset font size of s to %s\n'
              'set default settings to s\n'
              'repeat with w in windows\nrepeat with t in tabs of w\nset current settings of t to s\n'
              'end repeat\nend repeat\nend tell') % (name, face.replace('"', ""), int(float(size)))
    rc, _ = run(["osascript", "-e", script], timeout=8)
    return ", and the open windows took it" if rc == 0 else \
        ", and new windows use it (open ones: Terminal, Shell, Show Inspector)"


def _terminal_prefs(path):
    """Terminal.app's preferences as a dict, {} when there are none.
    `defaults export` writes XML that may carry a raw ESC byte (an older
    spark's key map), which no XML parser accepts, so plutil (lenient)
    turns it into a binary plist first."""
    xml, bin_ = path + ".export", path + ".bin"
    try:
        rc, _ = run(["defaults", "export", "com.apple.Terminal", xml], timeout=10)
        if rc != 0 or not os.path.exists(xml):
            return {}
        rc, _ = run(["plutil", "-convert", "binary1", "-o", bin_, xml], timeout=10)
        if rc != 0:
            return {}
        with open(bin_, "rb") as f:
            prefs = plistlib.load(f)
        return prefs if isinstance(prefs, dict) else {}
    except Exception:
        return {}
    finally:
        for f in (xml, bin_):
            try:
                os.remove(f)
            except OSError:
                pass


def _import_prefs(prefs, path):
    tmp = path + ".prefs"
    with open(tmp, "wb") as f:
        plistlib.dump(prefs, f, fmt=plistlib.FMT_BINARY)
    rc, _ = run(["defaults", "import", "com.apple.Terminal", tmp], timeout=10)
    try:
        os.remove(tmp)
    except OSError:
        pass
    return rc == 0


def _install_profile(name, d, path):
    """Put the profile into Terminal.app's preferences under its name,
    replacing an older one of that name, and make it the default. Through
    `defaults export` and `defaults import`, never `open`: handing
    Terminal.app the .terminal file imports a duplicate ("NAME 1") when the
    name exists. Earlier duplicates of that shape are removed on the way."""
    prefs = _terminal_prefs(path)
    ws = prefs.get("Window Settings")
    if not isinstance(ws, dict):
        ws = prefs["Window Settings"] = {}
    ws[name] = d
    for k in list(ws):
        rest = k[len(name):]
        if k.startswith(name) and rest.startswith(" ") and rest.strip().isdigit():
            del ws[k]
    prefs["Default Window Settings"] = name
    prefs["Startup Window Settings"] = name
    return _import_prefs(prefs, path)


def _ours(k):
    """spark-shell's profile, its duplicates, and any spark* an older spark left."""
    return k.startswith("spark")


def spark_profiles():
    """The spark* profile names Terminal.app's preferences hold."""
    prefs = _terminal_prefs(os.path.join(config_dir(), "terminal"))
    ws = prefs.get("Window Settings")
    return sorted(k for k in ws if _ours(k)) if isinstance(ws, dict) else []


def remove_profiles():
    """Every spark* profile leaves Terminal.app's preferences; a default or
    startup setting that named one falls back to Basic. Returns the names
    removed. Open windows keep their look."""
    path = os.path.join(config_dir(), "terminal")
    os.makedirs(config_dir(), exist_ok=True)
    prefs = _terminal_prefs(path)
    ws = prefs.get("Window Settings")
    if not isinstance(ws, dict):
        return []
    gone = sorted(k for k in ws if _ours(k))
    if not gone:
        return []
    for k in gone:
        del ws[k]
    for key in ("Default Window Settings", "Startup Window Settings"):
        if _ours(str(prefs.get(key, ""))):
            prefs[key] = "Basic"
    return gone if _import_prefs(prefs, path) else []


# --- the verbs --------------------------------------------------------------

def err(msg):
    sys.stderr.write("spark-shell: %s\n" % msg)
    return 1


def cmd_apply(theme_env, face, size):
    pal = read_theme(theme_env)
    if pal is None:
        return err("cannot read the palette in %s (20 THEME_* keys, each #rrggbb)" % theme_env)
    try:
        points = float(size)
    except ValueError:
        points = 0.0
    if not 6 <= points <= 72:
        return err("the font size is points, from 6 to 72, not %s" % size)
    if not IS_MAC and not no_apply():
        return err("Terminal.app profiles are for macOS; this machine is not a Mac")
    if not has_font(face):
        return err("the font %s is not installed on this Mac (spark-shell font list shows the ones that are)" % face)
    d = profile_dict(NAME, pal, face, points)
    want = plistlib.dumps(d, fmt=plistlib.FMT_BINARY)
    back = read_back(want)
    if back.get("BackgroundColor") is None or back.get("Font") is None:
        return err("the profile did not read back, so Terminal.app was not touched")
    size_word = "%g" % points
    if no_apply():
        print("Terminal.app would take the %s profile: %s at %s points, background %s."
              % (NAME, face, size_word, pal["THEME_BG"]))
        return 0
    cdir = config_dir()
    os.makedirs(cdir, exist_ok=True)
    path = os.path.join(cdir, NAME + ".terminal")
    have = b""
    try:
        with open(path, "rb") as f:
            have = f.read()
    except OSError:
        pass
    rc, out = run(["defaults", "read", "com.apple.Terminal", "Default Window Settings"])
    is_default = rc == 0 and out.strip() == NAME
    rc, out = run(["defaults", "read", "com.apple.Terminal", "Window Settings"], timeout=10)
    imported = rc == 0 and ('"%s"' % NAME in out or "%s =" % NAME in out)
    stale_dup = rc == 0 and ('"%s 1"' % NAME in out)
    if have == want and imported and is_default and not stale_dup:
        print("The %s profile is Terminal.app's default already%s."
              % (NAME, _switch_windows(NAME, path, face, points)))
        return 0
    with open(path, "wb") as f:
        f.write(want)
    if not _install_profile(NAME, d, path):
        return err("could not write Terminal.app's preferences, so the profile is not the default")
    print("The %s profile is Terminal.app's default now, %s at %s points%s."
          % (NAME, face, size_word, _switch_windows(NAME, path, face, points)))
    return 0


def cmd_remove():
    if no_apply():
        print("Terminal.app would lose the %s profile and any spark* profile, and Basic would be the default."
              % NAME)
        return 0
    if not IS_MAC:
        print("This machine is not a Mac, so there is no Terminal.app profile to remove.")
        return 0
    gone = remove_profiles()
    if gone:
        print("Terminal.app lost %d profile%s (%s), and Basic is the default again."
              % (len(gone), "" if len(gone) == 1 else "s", ", ".join(gone)))
    else:
        print("Terminal.app holds no %s profile." % NAME)
    return 0


USAGE = """usage: terminal_profile.py apply THEME_ENV FACE SIZE
       terminal_profile.py remove
       terminal_profile.py fonts
       terminal_profile.py has-font FACE"""


def main(argv):
    verb = argv[0] if argv else ""
    if verb == "apply" and len(argv) == 4:
        return cmd_apply(argv[1], argv[2], argv[3])
    if verb == "remove" and len(argv) == 1:
        return cmd_remove()
    if verb == "fonts" and len(argv) == 1:
        for face in installed_fonts():
            print(face)
        return 0
    if verb == "has-font" and len(argv) == 2:
        return 0 if has_font(argv[1]) else 1
    sys.stderr.write(USAGE + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
