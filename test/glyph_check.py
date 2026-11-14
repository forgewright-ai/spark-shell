#!/usr/bin/env python3
"""The glyph families' font check (#248): every glyph of every family is in each curated font and is
one cell wide, or this fails, and with it the build.

The families are read where they live: the dialog's share in component/dialog/src/glyphs.rs (the model's sign,
a choice's on and off, the branch, the bullet, thinking's sign, the gauge pair, the dots) and the
shell's in spark-shell's family_set (the gauge pair, thinking's sign, the dots and the key frame, the
pair around a workspace's number and a key). The two must agree where they share a
slot. A glyph passes when fc-query lists it in the font's charset and Unicode gives it one cell: not
East Asian Wide or Fullwidth, and not a mark or a format character, which take none.

The fonts: the files named on the command line; else every curated face spark-shell installs, four styles
each (FONT_FACES, Monaspace's five, #247 arc 3, in ~/.local/share/fonts/monaspace-NAME); else the release
zip spark-shell pins, fetched and held to its sha256 (NEON_URL, NEON_SHA256).

    python3 -I test/glyph_check.py [FONT...]
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def octal(s):
    """'\\342\\226\\260' -> the text those bytes are."""
    return re.sub(rb"\\([0-7]{3})", lambda m: bytes([int(m.group(1), 8)]), s.encode()).decode()


def rust_text(s):
    """'\\u{25b0}' -> the character."""
    return re.sub(r"\\u\{([0-9a-fA-F]+)\}", lambda m: chr(int(m.group(1), 16)), s)


def dialog_families():
    src = open(os.path.join(REPO, "component/dialog/src/glyphs.rs"), encoding="utf-8").read()
    track = re.search(r'pub const TRACK: &str = "((?:\\u\{[0-9a-f]+\}|[^"\\])*)";', src)
    out = {}
    for name, body in re.findall(r"pub const (STONE|STAR|BANNER): Glyphs = Glyphs \{(.*?)\};", src, re.S):
        fields = dict((k, rust_text(v)) for k, v in re.findall(r'(\w+): "((?:\\u\{[0-9a-f]+\}|[^"\\])*)"', body))
        out[fields.pop("name")] = fields
    if set(out) != {"stone", "star", "banner"} or not track:
        sys.exit("glyph check: component/dialog/src/glyphs.rs does not hold STONE, STAR, BANNER and TRACK as this check reads them")
    return out, rust_text(track.group(1))


def shell_families(sh):
    body = re.search(r"^family_set\(\) \{.*?^\}", sh, re.S | re.M)
    if not body:
        sys.exit("glyph check: spark-shell has no family_set")
    body = body.group(0)
    out = {}
    for name, fe in re.findall(r"^\s+(star|banner|\*)\) _fe='([^']*)'", body, re.M):
        on, off, think, kl, kr = fe.split(" ")
        out["stone" if name == "*" else name] = {
            "gauge_on": octal(on),
            "gauge_off": octal(off),
            "think": octal(think),
            "key": octal(kl) + octal(kr),
        }
    dot = re.search(r'_fb=\$\(printf "\$_fe ((?:\\[0-7]{3})+)"\)', body)
    if set(out) != {"stone", "star", "banner"} or not dot:
        sys.exit("glyph check: spark-shell's family_set does not hold stone, star, banner and the dots as this check reads them")
    return out, octal(dot.group(1))


def pinned(sh, key):
    m = re.search(r"^%s=(.*?)\s*(#.*)?$" % key, sh, re.M)
    if not m:
        sys.exit("glyph check: spark-shell has no %s" % key)
    v = m.group(1).strip("'\"")
    m = re.match(r"\$\{[A-Z_]+:-(.*)\}$", v)
    return m.group(1) if m else v


def fonts_from(sh, tmp):
    """Every style of every curated face (spark-shell's FONT_FACES, #247 arc 3): the installed files where all of them
    are there, else the pinned zip's."""
    styles = pinned(sh, "NEON_STYLES").split()
    faces = [f.capitalize() for f in pinned(sh, "FONT_FACES").split()]
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
    have = [os.path.join(data, "fonts/monaspace-%s" % f.lower(), "Monaspace%s-%s.otf" % (f, s)) for f in faces for s in styles]
    if all(os.path.isfile(f) for f in have):
        return have, "the faces installed in %s" % os.path.join(data, "fonts")
    url, sha = pinned(sh, "NEON_URL"), pinned(sh, "NEON_SHA256")
    z = os.path.join(tmp, "monaspace.zip")
    subprocess.run(["curl", "-fsSL", "--proto", "=https", "--proto-redir", "=https", "--retry", "3", "-o", z, url], check=True)
    got = hashlib.sha256(open(z, "rb").read()).hexdigest()
    if got != sha:
        sys.exit("glyph check: the zip fetched is not the one spark-shell pins (sha256 %s, pinned %s)" % (got, sha))
    out = []
    with zipfile.ZipFile(z) as zf:
        for face in faces:
            for s in styles:
                f = os.path.join(tmp, "Monaspace%s-%s.otf" % (face, s))
                with zf.open("Static Fonts/Monaspace %s/Monaspace%s-%s.otf" % (face, face, s)) as src, open(f, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                out.append(f)
    return out, "the release zip spark-shell pins (sha256 checked)"


def charset(font):
    r = subprocess.run(["fc-query", "--format", "%{charset}", font], capture_output=True, text=True, check=True)
    have = set()
    for tok in r.stdout.split():
        lo, _, hi = tok.partition("-")
        have.update(range(int(lo, 16), int(hi or lo, 16) + 1))
    if not have:
        sys.exit("glyph check: fc-query read no charset from %s" % font)
    return have


def one_cell(c):
    """None when c takes one cell in a terminal, else why not."""
    if len(c) != 1:
        return "is %d characters, not one" % len(c)
    if unicodedata.east_asian_width(c) in ("W", "F"):
        return "is East Asian wide: two cells"
    if unicodedata.category(c) in ("Mn", "Me", "Cf", "Cc"):
        return "takes no cell of its own"
    return None


def main():
    sh = open(os.path.join(REPO, "spark-shell"), encoding="utf-8").read()
    for f in sorted(os.listdir(os.path.join(REPO, "src"))):   # the entry and its modules, one text
        if f.endswith(".sh"):
            sh += open(os.path.join(REPO, "src", f), encoding="utf-8").read()
    dialog, track = dialog_families()
    shell, dot = shell_families(sh)
    bad = []
    if track != dot:
        bad.append("the dots: the dialog draws %r, the shell %r" % (track, dot))
    for name in ("stone", "star", "banner"):
        for slot in ("gauge_on", "gauge_off", "think"):
            if dialog[name][slot] != shell[name][slot]:
                bad.append("%s's %s: the dialog draws %r, the shell %r" % (name, slot, dialog[name][slot], shell[name][slot]))
    tmp = tempfile.mkdtemp(prefix="glyph-check.")
    try:
        if len(sys.argv) > 1:
            fonts, said = sys.argv[1:], "the fonts named"
        else:
            fonts, said = fonts_from(sh, tmp)
        sets = [(os.path.basename(f), charset(f)) for f in fonts]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for name in ("stone", "star", "banner"):
        glyphs = list(dict.fromkeys(list(dialog[name].values()) + list(shell[name]["key"]) + [track]))
        for g in glyphs:
            why = one_cell(g)
            if why:
                bad.append("%s: %r (%s) %s" % (name, g, " ".join("U+%04X" % ord(c) for c in g), why))
                continue
            for fn, have in sets:
                if ord(g) not in have:
                    bad.append("%s: %s U+%04X %s is not in %s" % (name, g, ord(g), unicodedata.name(g, "?"), fn))
        if not any(b.startswith(name + ":") for b in bad):
            print("glyph check: %s, %d glyphs, each one cell wide and in %s" % (name, len(glyphs), ", ".join(fn for fn, _ in sets)))
    if bad:
        print("glyph check: failed, against %s:" % said)
        for b in bad:
            print("  " + b)
        sys.exit(1)
    print("glyph check: the three families agree in the dialog and the shell, against %s" % said)


if __name__ == "__main__":
    main()
