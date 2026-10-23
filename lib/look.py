#!/usr/bin/env python3
"""look.py -- a palette by color math (spark-shell issue 24). Python's standard library only.

  look.py palette PNG [--dark|--light]   the twenty palette keys from a picture's colors
  look.py words --hue HUE --accent HUE|same --warmth WARMTH --contrast CONTRAST --light dark|light
                                        the twenty keys from five words
  look.py --version

The picture is a PNG (spark-shell makes a small one with gdk-pixbuf-thumbnailer first; a PNG
of any size is read as it is). Its colors are gathered into a few clusters; the heaviest dark
one is the background of a dark palette, the heaviest light one of a light palette, the most
saturated one the accent, and each of the six terminal hues takes the cluster nearest it,
or is made at that hue in the picture's own saturation.

The rules every palette keeps, from a picture or from words: the text reads at 7 to 1 on the
background, the accent, the muted color and the six hues at 3 to 1 (WCAG); the bright hues
are a step lighter on a dark ground and a step deeper on a light one; the dark greys are the
background moved toward the text and the light greys the text moved toward the background.
The output is the palette file spark-shell reads: THEME_BG, THEME_FG, THEME_ACCENT,
THEME_MUTED and THEME_ANSI_0 to THEME_ANSI_15, one #rrggbb a line.
"""
import struct
import sys
import zlib

VERSION = "2"

HUES = {"red": 0, "orange": 30, "yellow": 55, "green": 130, "teal": 175, "blue": 220, "violet": 270, "pink": 335, "grey": None}
WARMTHS = ("warm", "neutral", "cool")
CONTRASTS = ("soft", "normal", "high")
# the six terminal hues, slot by slot: red, green, yellow, blue, magenta, cyan
SLOT_HUES = ((1, 5), (2, 125), (3, 50), (4, 225), (5, 300), (6, 185))


# --- color math

def hexs(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def hsl(rgb):
    r, g, b = (c / 255.0 for c in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return 0.0, 0.0, l
    d = mx - mn
    s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:
        h = (g - b) / d + (6 if g < b else 0)
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h * 60 % 360, s, l


def rgb(h, s, l):
    h = h % 360 / 360.0
    if s == 0:
        v = l * 255
        return (v, v, v)

    def f(p, q, t):
        t %= 1
        if t < 1 / 6:
            return p + (q - p) * 6 * t
        if t < 1 / 2:
            return q
        if t < 2 / 3:
            return p + (q - p) * (2 / 3 - t) * 6
        return p

    q = l * (1 + s) if l < 0.5 else l + s - l * s
    p = 2 * l - q
    return tuple(255 * f(p, q, h + d) for d in (1 / 3, 0, -1 / 3))


def lum(c):
    def ch(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    x, y = lum(a), lum(b)
    if x < y:
        x, y = y, x
    return (x + 0.05) / (y + 0.05)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def dist(a, b):
    return sum((a[i] - b[i]) ** 2 for i in range(3)) ** 0.5


def lift(color, ground, want, dark, max_s=None):
    """The color moved in lightness, away from the ground, until it reads at `want` to 1 on it;
    its saturation eased when lightness alone cannot get there."""
    h, s, l = hsl(color)
    if max_s is not None:
        s = min(s, max_s)
    step = 0.01 if dark else -0.01
    for _ in range(120):
        c = rgb(h, s, l)
        if contrast(c, ground) >= want:
            return c
        if 0.0 < l < 1.0:
            l = max(0.0, min(1.0, l + step))
        else:
            s = max(0.0, s - 0.05)
            if s == 0.0:
                break
    return rgb(h, s, l)


# --- a picture's colors

def read_png(path):
    """-> a list of (r, g, b) for every pixel, or every eighth on a wide picture; 8 and 16 bit,
    grey, grey with alpha, color, color with alpha and a palette; not interlaced."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, plte = 8, [], None
    w = h = depth = ctype = interlace = None
    while pos + 8 <= len(data):
        n, = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body[:13])
        elif kind == b"PLTE":
            plte = [tuple(body[i:i + 3]) for i in range(0, len(body) - 2, 3)]
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    if w is None or not idat:
        raise ValueError("not a PNG with a picture in it")
    if interlace:
        raise ValueError("an interlaced PNG is not read")
    if depth not in (8, 16) and ctype != 3:
        raise ValueError("a PNG of %d bits is not read" % depth)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if channels is None:
        raise ValueError("a PNG of color type %d is not read" % ctype)
    bps = 2 if depth == 16 else 1
    if ctype == 3:
        bps = 1
        if depth < 8:
            raise ValueError("a palette PNG under 8 bits is not read")
    bpp = channels * bps
    stride = w * bpp
    raw = zlib.decompress(b"".join(idat))
    if len(raw) < h * (stride + 1):
        raise ValueError("the PNG is cut short")
    prev = bytearray(stride)
    out = []
    step = max(1, (w * h) // 60000)   # at most about sixty thousand pixels are kept
    k = 0
    p = 0
    for _ in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                if pa <= pb and pa <= pc:
                    pr = a
                elif pb <= pc:
                    pr = b
                else:
                    pr = c
                line[i] = (line[i] + pr) & 255
        elif ft != 0:
            raise ValueError("a PNG filter %d is not read" % ft)
        for x in range(w):
            k += 1
            if k % step:
                continue
            o = x * bpp
            if ctype == 3:
                out.append(plte[line[o]] if plte and line[o] < len(plte) else (0, 0, 0))
            elif channels <= 2:
                v = line[o]
                out.append((v, v, v))
            else:
                out.append((line[o], line[o + bps], line[o + 2 * bps]))
        prev = line
    if not out:
        raise ValueError("the PNG holds no pixel")
    return out


def clusters(pixels):
    """-> [(weight, (r, g, b))] heaviest first: the pixels binned at 32 levels a channel, the
    bins near each other merged, each cluster the weighted mean of its bins."""
    bins = {}
    for c in pixels:
        key = (c[0] >> 3, c[1] >> 3, c[2] >> 3)
        if key in bins:
            e = bins[key]
            e[0] += 1
            e[1] += c[0]
            e[2] += c[1]
            e[3] += c[2]
        else:
            bins[key] = [1, c[0], c[1], c[2]]
    items = sorted(((e[0], (e[1] / e[0], e[2] / e[0], e[3] / e[0])) for e in bins.values()), reverse=True)
    out = []
    for wgt, col in items[:200]:
        for cl in out:
            if dist(cl[1], col) < 28:
                tw = cl[0] + wgt
                cl[1] = mix(cl[1], col, wgt / tw)
                cl[0] = tw
                break
        else:
            out.append([wgt, col])
    total = float(len(pixels))
    out = [(wgt / total, tuple(col)) for wgt, col in out]
    out.sort(reverse=True)
    return out


def palette_from_picture(pixels, light=None):
    cl = clusters(pixels)
    mean_l = sum(lum(c) * w for w, c in cl) / max(1e-9, sum(w for w, c in cl))
    dark = (mean_l < 0.35) if light is None else (not light)
    # the ground: the heaviest cluster on the dark side (or the light side), its saturation eased
    side = [(w, c) for w, c in cl if (hsl(c)[2] < 0.4 if dark else hsl(c)[2] > 0.6)]
    base = side[0][1] if side else cl[0][1]
    h, s, l = hsl(base)
    s = min(s, 0.35)
    l = min(max(l, 0.07), 0.19) if dark else min(max(l, 0.90), 0.97)
    bg = rgb(h, s, l)
    # the text: the lightest (darkest) near-neutral cluster, lifted to 7 to 1; else the ground's hue, pale
    cands = [c for w, c in cl if hsl(c)[1] < 0.4 and (hsl(c)[2] > 0.5 if dark else hsl(c)[2] < 0.5)]
    fg = lift(cands[0], bg, 7.0, dark, max_s=0.25) if cands else lift(rgb(h, 0.12, 0.85 if dark else 0.18), bg, 7.0, dark)
    # the accent: the most saturated cluster of some weight, at 3 to 1
    sat = sorted(((hsl(c)[1] * (0.5 + w), c) for w, c in cl if w >= 0.004 and hsl(c)[1] >= 0.25), reverse=True)
    accent = lift(sat[0][1], bg, 3.0, dark) if sat else lift(rgb((h + 180) % 360, 0.55, 0.6 if dark else 0.4), bg, 3.0, dark)
    muted = lift(rgb(h, 0.16, 0.55 if dark else 0.45), bg, 3.0, dark)
    med_s = sorted(hsl(c)[1] for w, c in cl)[len(cl) // 2] if cl else 0.5
    med_s = min(max(med_s, 0.45), 0.8)
    ansi = {}
    for slot, hue in SLOT_HUES:
        near = [(abs((hsl(c)[0] - hue + 180) % 360 - 180), c) for w, c in cl if hsl(c)[1] >= 0.25 and w >= 0.002]
        near.sort()
        if near and near[0][0] <= 28:
            c = near[0][1]
            ch, cs, clight = hsl(c)
            c = rgb(ch, max(cs, 0.45), clight)
        else:
            c = rgb(hue, med_s, 0.62 if dark else 0.40)
        ansi[slot] = lift(c, bg, 3.0, dark)
    return assemble(bg, fg, accent, muted, ansi, dark)


# --- a palette from words

def palette_from_words(hue, warmth, contrast_word, light, accent_word="same"):
    dark = light == "dark"
    base_h = HUES[hue]
    grey = base_h is None
    accent_h = HUES.get(accent_word) if accent_word != "same" else None
    accent_grey = accent_word == "grey"
    tint_h = {"warm": 38, "neutral": base_h if base_h is not None else 220, "cool": 222}[warmth]
    tint_s = {"warm": 0.14, "neutral": 0.05 if grey else 0.10, "cool": 0.12}[warmth]
    bg_l = {"soft": 0.14, "normal": 0.11, "high": 0.07}[contrast_word] if dark else {"soft": 0.92, "normal": 0.95, "high": 0.985}[contrast_word]
    fg_l = {"soft": 0.78, "normal": 0.86, "high": 0.95}[contrast_word] if dark else {"soft": 0.30, "normal": 0.22, "high": 0.10}[contrast_word]
    want = {"soft": 7.0, "normal": 9.0, "high": 13.0}[contrast_word]
    bg = rgb(tint_h, tint_s, bg_l)
    fg = lift(rgb(tint_h, tint_s * 0.8, fg_l), bg, want, dark)
    if accent_h is not None:
        accent = lift(rgb(accent_h, 0.78, 0.62 if dark else 0.40), bg, 3.0, dark)   # the second hue the words name: a flag, a brand
    elif grey or accent_grey:
        accent = lift(rgb(tint_h, 0.10, 0.70 if dark else 0.35), bg, 4.5, dark)
    else:
        accent = lift(rgb(base_h, 0.72, 0.64 if dark else 0.42), bg, 3.0, dark)
    muted = lift(rgb(tint_h, 0.16, 0.56 if dark else 0.44), bg, 3.0, dark)
    shift = {"warm": 8, "neutral": 0, "cool": -8}[warmth]
    ansi = {}
    for slot, h in SLOT_HUES:
        s = 0.22 if grey else 0.60
        ansi[slot] = lift(rgb(h + shift, s, 0.62 if dark else 0.40), bg, 3.0, dark)
    return assemble(bg, fg, accent, muted, ansi, dark)


def assemble(bg, fg, accent, muted, ansi, dark):
    pal = {"THEME_BG": bg, "THEME_FG": fg, "THEME_ACCENT": accent, "THEME_MUTED": muted}
    pal["THEME_ANSI_0"] = mix(bg, fg, 0.15) if dark else mix(fg, bg, 0.10)
    pal["THEME_ANSI_7"] = mix(fg, bg, 0.20) if dark else mix(bg, fg, 0.35)
    pal["THEME_ANSI_8"] = muted
    pal["THEME_ANSI_15"] = fg
    for slot in range(1, 7):
        c = ansi[slot]
        pal["THEME_ANSI_%d" % slot] = c
        h, s, l = hsl(c)
        bright = rgb(h, min(1.0, s + 0.05), min(0.92, l + 0.10)) if dark else rgb(h, min(1.0, s + 0.10), max(0.12, l - 0.08))
        pal["THEME_ANSI_%d" % (slot + 8)] = lift(bright, bg, 3.0, dark)
    keys = ["THEME_BG", "THEME_FG", "THEME_ACCENT", "THEME_MUTED"] + ["THEME_ANSI_%d" % i for i in range(16)]
    return "".join("%s=%s\n" % (k, hexs(pal[k])) for k in keys)


# --- the command

def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return 0
    if argv[1] == "--version":
        print(VERSION)
        return 0
    if argv[1] == "palette":
        if len(argv) < 3:
            sys.stderr.write("palette takes a PNG\n")
            return 1
        light = None
        if "--light" in argv[3:]:
            light = True
        elif "--dark" in argv[3:]:
            light = False
        try:
            sys.stdout.write(palette_from_picture(read_png(argv[2]), light))
        except (OSError, ValueError, zlib.error) as e:
            sys.stderr.write("%s\n" % e)
            return 1
        return 0
    if argv[1] == "words":
        opts = {}
        args = argv[2:]
        while args:
            if len(args) < 2 or not args[0].startswith("--"):
                sys.stderr.write("words takes --hue, --warmth, --contrast and --light, each with a word\n")
                return 1
            opts[args[0][2:]] = args[1].lower()
            args = args[2:]
        hue, warmth, con, light = opts.get("hue", ""), opts.get("warmth", "neutral"), opts.get("contrast", "normal"), opts.get("light", "dark")
        accent = opts.get("accent", "same")
        if hue not in HUES or (accent != "same" and accent not in HUES):
            sys.stderr.write("a hue is one of %s; the accent one of them or same\n" % ", ".join(HUES))
            return 1
        if warmth not in WARMTHS or con not in CONTRASTS or light not in ("dark", "light"):
            sys.stderr.write("warmth is warm, neutral or cool; contrast is soft, normal or high; light is dark or light\n")
            return 1
        sys.stdout.write(palette_from_words(hue, warmth, con, light, accent))
        return 0
    sys.stderr.write("look.py palette PNG | words --hue H --warmth W --contrast C --light dark|light\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
