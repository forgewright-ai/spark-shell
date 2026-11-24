#!/usr/bin/env python3
"""look.py -- a palette by color math (spark-shell issue 24). Python's standard library only.

  look.py palette PNG [--dark|--light]   the twenty palette keys from a picture's colors
  look.py words --hue HUE --accent HUE|same --warmth WARMTH --contrast CONTRAST --light dark|light
                                        the twenty keys from five words
  look.py edges PNG                     "#TOP #BOTTOM": the colors along a small picture's top and bottom,
                                        to extend it on a screen of another shape
  look.py picture FILE                  "png W H" or "jpeg W H": the kind and the size its header
                                        says, read before anything decodes it (the gallery's check)
  look.py shown FILE                    "KIND W H" for a whole PNG, JPEG, WebP or GIF a screen can show,
                                        metadata and all (a wallpaper of the person's own)
  look.py loop FILE                     "W H" for an MP4 of one H.264 video, every byte of it in the file
  look.py reel FILE                     "W H FRAMES" for an animated WebP, each frame the size it says
  look.py bare FILE OUT [KIND]          a picture, a loop or a reel (KIND, when it must be that one) with no
                                        metadata (EXIF, XMP, a camera's place and time): the parts its check
                                        takes, its pixels untouched
  look.py pack FOLDER OUT               a theme file: a plain tar of the theme's folder, FOLDER/FILE each,
                                        a picture under a name a theme file takes
  look.py unpack FILE DIR               a theme file's folder in DIR, each file plain, of a kind a theme
                                        holds and within its size; the theme's name on stdout
  look.py --version

The picture is a PNG (spark-shell makes a small one first, through gdk-pixbuf-thumbnailer or
rsvg-convert; a PNG of any size is read as it is, and a clear pixel is skipped). Its colors are gathered into a few clusters; the heaviest dark
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
import io
import os
import re
import stat
import struct
import sys
import tarfile
import zlib

VERSION = "3"

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
    if w > PIXELS_READ[0] or h > PIXELS_READ[1]:
        raise ValueError("a PNG of %dx%d is past %dx%d" % (w, h, PIXELS_READ[0], PIXELS_READ[1]))
    need = h * (stride + 1)   # inflated no further than its header says it holds: a small file never becomes gigabytes
    z = zlib.decompressobj()
    raw = z.decompress(b"".join(idat), need)
    if len(raw) < need:
        raise ValueError("the PNG is cut short")
    if z.unconsumed_tail:
        raise ValueError("the PNG holds more than its header says")
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
            if channels in (2, 4) and line[o + (channels - 1) * bps] < 128:
                continue   # a clear pixel (the margins of a picture drawn small inside a square) is no color of the picture
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


# --- a picture's kind and size, from its structure alone

PIXELS_READ = (16384, 16384)   # read_png's limit: a picture past it is made small first (gdk-pixbuf, rsvg)
FILE_MOST = 128 << 20   # the most bytes read of any one file
SCANS_MOST = 64   # of a JPEG: each is drawn over the whole picture, so a small file could take hours; the shipped art has 10
JPEG_SOF = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
# a still picture's own parts, and nothing else: no metadata (EXIF, XMP, text, C2PA), no animation (APNG),
# no private chunk, nothing after its end. So a picture shows what was reviewed, and carries nothing more
PNG_CHUNKS = {b"IHDR", b"PLTE", b"tRNS", b"gAMA", b"cHRM", b"sRGB", b"pHYs", b"bKGD", b"IDAT", b"IEND"}
JPEG_MARKERS = JPEG_SOF | {0xD8, 0xE0, 0xDB, 0xC4, 0xDD, 0xDA, 0xD9} | set(range(0xD0, 0xD8))
JPEG_NEXT = re.compile(rb"\xff[^\x00\xff\xd0-\xd7]")   # the marker past a scan's bytes: FF 00 is a byte, FF D0 to D7 a restart


def read_file(path, most=FILE_MOST):
    """-> a plain file's bytes, never a pipe's or a device's: reading one could wait for ever."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as fh:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise ValueError("not a plain file")
        if st.st_size > most:
            raise ValueError("over %d MiB" % (most >> 20))
        return fh.read(most)


def is_png(data):
    return data[:8] == b"\x89PNG\r\n\x1a\n"


def is_jpeg(data):
    return data[:3] == b"\xff\xd8\xff"


def is_webp(data):
    return data[:4] == b"RIFF" and data[8:12] == b"WEBP"


def is_mp4(data):
    return data[4:8] == b"ftyp"


def png_parts(data):
    """-> (kind, start, end) of each of a PNG's chunks, to its IEND, its header first."""
    pos = 8
    while pos + 12 <= len(data):
        n, = struct.unpack(">I", data[pos:pos + 4])
        kind, end = data[pos + 4:pos + 8], pos + 12 + n
        if pos == 8 and (kind != b"IHDR" or n != 13):
            raise ValueError("a PNG whose first chunk is not its header")
        if end > len(data):
            break
        yield kind, pos, end
        if kind == b"IEND":
            return
        pos = end
    raise ValueError("a PNG with no end")


def jpeg_parts(data):
    """-> (marker, start, end) of each of a JPEG's parts past its first two bytes, a scan with its coded
    bytes, to its EOI."""
    pos, scans = 2, 0
    while pos + 2 <= len(data):
        if data[pos] != 0xFF:
            raise ValueError("a JPEG with a broken marker")
        m = data[pos + 1]
        if m == 0xFF:
            pos += 1
            continue
        if m == 0xD9:
            yield m, pos, pos + 2
            return
        if m == 0xD8 or 0xD0 <= m <= 0xD7:
            yield m, pos, pos + 2
            pos += 2
            continue
        if pos + 4 > len(data):
            break
        n, = struct.unpack(">H", data[pos + 2:pos + 4])
        end = pos + 2 + n
        if n < 2 or end > len(data):
            break
        if m == 0xDA:
            scans += 1
            if scans > SCANS_MOST:
                raise ValueError("a JPEG of over %d scans, which takes too long to show" % SCANS_MOST)
            past = JPEG_NEXT.search(data, end)
            if past is None:
                break
            end = past.start()
        yield m, pos, end
        pos = end
    raise ValueError("a JPEG with no end")


def jpeg_frame(data, start, end):
    """-> (width, height, colors) a JPEG's frame header says."""
    if end - start < 10:
        raise ValueError("a JPEG with a broken frame header")
    h, w, n = struct.unpack(">HHB", data[start + 5:start + 10])
    return w, h, n


def jpeg_jfif(data, start, end):
    """-> an APP0 as a plain JFIF header; nothing for one that is another (JFXX holds a small picture)."""
    if data[start + 4:start + 9] != b"JFIF\0" or end - start < 18:
        return b""
    return b"\xff\xe0\x00\x10" + data[start + 4:start + 16] + b"\0\0"   # no small picture in it either


def picture_size(path):
    """-> ("png" | "jpeg", width, height): a PNG of a still picture's chunks alone, IHDR first and IEND
    last; a JPEG of a still picture's markers alone, read through its scans to EOI at its end. Nothing is
    decompressed."""
    data = read_file(path)
    if is_png(data):
        for kind, start, end in png_parts(data):
            if kind not in PNG_CHUNKS:
                raise ValueError("a PNG with a %r chunk, which a still picture has not" % kind.decode("latin-1"))
        if end != len(data):
            raise ValueError("a PNG with data after its end")
        return ("png",) + struct.unpack(">II", data[16:24])
    if is_jpeg(data):
        size = None
        for m, start, end in jpeg_parts(data):
            if m not in JPEG_MARKERS:
                raise ValueError("a JPEG with a 0x%02X marker, which a still picture has not" % m)
            if m == 0xE0 and jpeg_jfif(data, start, end) != data[start:end]:
                raise ValueError("a JPEG with a small picture in it, which a still picture has not")
            if m in JPEG_SOF and size is None:
                size = jpeg_frame(data, start, end)
        if end != len(data):
            raise ValueError("a JPEG with data after its end")
        if size is None:
            raise ValueError("a JPEG with no frame header")
        return "jpeg", size[0], size[1]
    raise ValueError("not a PNG or a JPEG")


def picture_shown(path):
    """-> (kind, width, height) of a whole picture a screen can show, metadata and all: one of the person's
    own. Cut short, of no size, larger than a screen can be or of too many scans is refused."""
    data, size = read_file(path), None
    if is_png(data):
        kind = "png"
        for part in png_parts(data):
            pass
        size = struct.unpack(">II", data[16:24])
    elif is_jpeg(data):
        kind = "jpeg"
        for m, start, end in jpeg_parts(data):
            if m in JPEG_SOF and size is None:
                size = jpeg_frame(data, start, end)[:2]
    elif is_webp(data):
        kind, size = "webp", webp_size(data)
    elif data[:6] in (b"GIF87a", b"GIF89a") and len(data) > 13:
        kind, size = "gif", struct.unpack("<HH", data[6:10])
    else:
        raise ValueError("not a PNG, a JPEG, a WebP or a GIF")
    if not size or not size[0] or not size[1]:
        raise ValueError("a picture of no size")
    if max(size) > 32767 or size[0] * size[1] > PIXELS_READ[0] * PIXELS_READ[1]:
        raise ValueError("a picture of %dx%d, more than a screen can show" % size)
    return kind, size[0], size[1]


def exif_turn(tiff):
    """-> how a photo's EXIF says it lies: 1 as it is, 2 to 8 turned or mirrored."""
    order = {b"II*\0": "<", b"MM\0*": ">"}.get(tiff[:4])
    if order is None or len(tiff) < 8:
        return 1
    at, = struct.unpack(order + "I", tiff[4:8])
    for i in range(struct.unpack(order + "H", tiff[at:at + 2])[0] if at + 2 <= len(tiff) else 0):
        row = tiff[at + 2 + 12 * i:at + 14 + 12 * i]
        if len(row) == 12 and struct.unpack(order + "HH", row[:4]) == (0x0112, 3):
            return struct.unpack(order + "H", row[8:10])[0]
    return 1


def picture_bare(data):
    """-> the picture with its own parts alone: a PNG of PNG_CHUNKS, a JPEG of JPEG_MARKERS, nothing after
    its end. Metadata goes (a camera's place and time among it); the pixels are the same bytes. Refused
    where what goes says how they show: a photo turned by its EXIF, a color model of Adobe's."""
    if is_png(data):
        return data[:8] + b"".join(data[a:b] for kind, a, b in png_parts(data) if kind in PNG_CHUNKS)
    if is_jpeg(data):
        out, turn, adobe, colors, jfif = [b"\xff\xd8"], 1, None, 0, b""
        for m, a, b in jpeg_parts(data):
            if m == 0xE0:
                if not jfif:
                    jfif = jpeg_jfif(data, a, b)
                    out.append(jfif)
            elif m == 0xE1 and data[a + 4:a + 10] == b"Exif\0\0":
                turn = exif_turn(data[a + 10:b])
            elif m == 0xEE and data[a + 4:a + 9] == b"Adobe" and b - a >= 16:
                adobe = data[a + 15]
            elif m in JPEG_MARKERS and m != 0xD8 and not 0xD0 <= m <= 0xD7:
                if m in JPEG_SOF:
                    colors = jpeg_frame(data, a, b)[2]
                out.append(data[a:b])
        if 2 <= turn <= 8:
            raise ValueError("a photo turned by its EXIF alone, which a theme drops: save it upright")
        if adobe is not None and (colors == 4 or colors == 3 and adobe != 1):
            raise ValueError("a JPEG in CMYK or RGB, which a plain one is not: save it in sRGB")
        return b"".join(out)
    raise ValueError("not a PNG or a JPEG")


# --- a loop: an MP4 of one H.264 video, every byte of it in the file. Its boxes are read here, before
# ffprobe or a player opens it: a file named .mp4 that is a playlist or an SDP, which would open the
# network, has none of them, and an MP4 that names another file or holds anything beside its video is refused

LOOP_MOST = (7680, 4320)   # either way round
MP4_HOLDS = {   # the boxes a loop is made of, by the one that holds them
    "file": {b"ftyp", b"moov", b"mdat"}, "moov": {b"mvhd", b"trak"}, "trak": {b"tkhd", b"edts", b"mdia"}, "edts": {b"elst"},
    "mdia": {b"mdhd", b"hdlr", b"minf"}, "minf": {b"vmhd", b"hdlr", b"dinf", b"stbl"}, "dinf": {b"dref"}, "stsd": {b"avc1"},
    "stbl": {b"stsd", b"stts", b"stss", b"ctts", b"stsc", b"stsz", b"stco", b"co64", b"sdtp", b"sgpd", b"sbgp", b"cslg"},
    "avc1": {b"avcC", b"pasp", b"colr", b"btrt", b"clap", b"fiel"},
}
MP4_PAST = {b"free", b"skip", b"wide", b"udta", b"meta", b"uuid", b"iods"}   # padding and metadata: read past, and no part of a bare one
MP4_DREF = struct.pack(">III4sI", 0, 1, 12, b"url ", 1)   # one data reference, to the file itself
MP4_ROWS = 500000   # the most rows of a table: over two hours of frames


def mp4_boxes(data, a, b):
    """-> (kind, start, inside, end) for each box from a to b, which they fill."""
    out = []
    while a < b:
        if b - a < 8 or len(out) >= 1000:
            raise ValueError("a broken MP4")
        n, kind = struct.unpack(">I4s", data[a:a + 8])
        inside = a + 8
        if n == 1 and b - a >= 16:
            n, = struct.unpack(">Q", data[a + 8:a + 16])
            inside = a + 16
        elif n == 0:   # to the end
            n = b - a
        if n < inside - a or n > b - a:
            raise ValueError("a broken MP4")
        out.append((kind, a, inside, a + n))
        a += n
    return out


def mp4_in(data, holder, a, b, bare):
    """-> {kind: [(start, inside, end)]}: HOLDER's own boxes from a to b. Another is metadata or padding and is
    read past, or is refused; in BARE, a copy being made bare, each becomes a free box of zeros where it lies."""
    own = {}
    for kind, start, inside, end in mp4_boxes(data, a, b):
        if kind in MP4_HOLDS[holder]:
            own.setdefault(kind, []).append((start, inside, end))
        elif bare is not None:
            mp4_free(bare, start, inside, end)
        elif kind not in MP4_PAST:
            raise ValueError("an MP4 with a %r box, which a loop has not" % kind.decode("latin-1"))
    return own


def mp4_free(bare, start, inside, end):
    bare[start + 4:start + 8] = b"free"
    bare[inside:end] = bytes(end - inside)


def mp4_one(own, kind):
    """-> (inside, end) of the one box of its kind."""
    if len(own.get(kind, ())) != 1:
        raise ValueError("an MP4 of not one %s" % kind.decode())
    return own[kind][0][1:]


def mp4_rows(data, at, end, form):
    """-> the rows of a table whose count is at AT."""
    n = struct.unpack(">I", data[at:at + 4])[0] if at + 4 <= end else MP4_ROWS + 1
    size = struct.calcsize(form) * n
    if n > MP4_ROWS or at + 4 + size > end:
        raise ValueError("a broken MP4")
    return list(struct.iter_unpack(form, data[at + 4:at + 4 + size]))


def mp4_sized(w, h):
    if not (w and h) or max(w, h) > max(LOOP_MOST) or w * h > LOOP_MOST[0] * LOOP_MOST[1]:
        raise ValueError("%dx%d, past %dx%d" % ((w, h) + LOOP_MOST))


def sps_size(nal):
    """-> (width, height) an H.264 sequence header says its frames have, in whole blocks of 16."""
    bits, at = "".join("{:08b}".format(x) for x in nal[1:2048].replace(b"\0\0\3", b"\0\0")), 0

    def u(n):
        nonlocal at
        at += n
        if at > len(bits):
            raise ValueError("an MP4 with a broken H.264 header")
        return int(bits[at - n:at] or "0", 2)

    def ue():
        zeros = 0
        while not u(1):
            zeros += 1
        return (1 << zeros) - 1 + u(zeros) if zeros < 32 else u(1 << 20)   # no such number: past the end

    profile, _ = u(8), u(16)
    ue()
    if profile in (100, 110, 122, 244, 44, 83, 86, 118, 128, 134, 135, 138, 139):
        chroma = ue()
        if chroma == 3:
            u(1)
        ue(), ue(), u(1)
        if u(1):
            for i in range(12 if chroma == 3 else 8):
                if u(1):
                    last = scale = 8
                    for _ in range(16 if i < 6 else 64):
                        if scale:
                            step = ue()
                            scale = (last + ((step + 1) // 2 if step & 1 else -(step // 2))) % 256
                        last = scale or last
    ue()
    order = ue()
    if order == 0:
        ue()
    elif order == 1:
        u(1), ue(), ue()
        for _ in range(min(ue(), 255)):
            ue()
    ue(), u(1)
    w, h = ue() + 1, ue() + 1
    return 16 * w, 16 * h * (1 if u(1) else 2)


def loop_read(data, bare=None):
    """-> (width, height) of a loop. BARE, a bytearray of its bytes, is made bare: the one video stays where
    it lies, so every offset holds, and all else is zeros: other tracks and their bytes, names, times."""
    if not is_mp4(data):
        raise ValueError("no MP4")
    own = mp4_in(data, "file", 0, len(data), bare)
    moov = mp4_in(data, "moov", *mp4_one(own, b"moov"), bare)
    tracks = moov.get(b"trak", [])
    if bare is not None:
        for t in [t for t in tracks if not mp4_video(data, t)]:
            mp4_free(bare, *t)
            tracks = [x for x in tracks if x != t]
    if len(tracks) != 1:
        raise ValueError("an MP4 with a track beside its video" if tracks else "no H.264 video")
    trak = mp4_in(data, "trak", *tracks[0][1:], bare)
    mdia = mp4_in(data, "mdia", *mp4_one(trak, b"mdia"), bare)
    hdlr = mp4_one(mdia, b"hdlr")
    if data[hdlr[0] + 8:hdlr[0] + 12] != b"vide":
        raise ValueError("no H.264 video")
    minf = mp4_in(data, "minf", *mp4_one(mdia, b"minf"), bare)
    dref = mp4_one(mp4_in(data, "dinf", *mp4_one(minf, b"dinf"), bare), b"dref")
    if data[dref[0]:dref[1]] != MP4_DREF:
        raise ValueError("an MP4 that names another file")
    stbl = mp4_in(data, "stbl", *mp4_one(minf, b"stbl"), bare)
    a, b = mp4_one(stbl, b"stsd")
    kinds = [k for k, _, _, _ in mp4_boxes(data, a + 8, b)]
    if kinds != [b"avc1"]:
        raise ValueError("no H.264 video")
    a, b = mp4_one(mp4_in(data, "stsd", a + 8, b, bare), b"avc1")
    if b - a < 78:
        raise ValueError("a broken MP4")
    w, h = struct.unpack(">HH", data[a + 24:a + 28])
    mp4_sized(w, h)
    entry = a
    a, b = mp4_one(mp4_in(data, "avc1", a + 78, b, bare), b"avcC")
    at = a + 6
    for _ in range(data[a + 5] & 31 if b - a > 6 else 0):
        n, = struct.unpack(">H", data[at:at + 2]) if at + 2 <= b else (0,)
        mp4_sized(*sps_size(data[at + 2:min(at + 2 + n, b)]))
        at += 2 + n
    if at == a + 6:
        raise ValueError("an MP4 with a broken H.264 header")
    kept = mp4_samples(data, stbl, [(x, y) for _, x, y in own.get(b"mdat", [])])
    if bare is not None:
        gone = [t[1:] for t in own[b"mdat"]]
        gone += [(x + 24, y) for x, y in [hdlr] + [t[1:] for t in minf.get(b"hdlr", [])]] + [(entry + 42, entry + 74)]   # the track's name, the encoder's
        for x, y in (mp4_one(moov, b"mvhd"), mp4_one(trak, b"tkhd"), mp4_one(mdia, b"mdhd")):   # made and changed, by the camera's clock
            gone.append((x + 4, min(y, x + (20 if data[x:x + 1] == b"\1" else 12))))
        for x, y in gone:
            bare[x:y] = bytes(max(0, y - x))
        for x, y in kept:
            bare[x:y] = data[x:y]
    return w, h


def mp4_video(data, track):
    """-> whether a track is a video, whatever else it holds."""
    for kind, _, a, b in mp4_boxes(data, track[1], track[2]):
        if kind == b"mdia":
            return any(k == b"hdlr" and data[x + 8:x + 12] == b"vide" for k, _, x, _ in mp4_boxes(data, a, b))
    return False


def mp4_samples(data, stbl, mdats):
    """-> (start, end) of each run of the video's bytes, every one in an mdat and none twice."""
    a, b = mp4_one(stbl, b"stsz")
    if b - a < 12:
        raise ValueError("a broken MP4")
    each, count = struct.unpack(">II", data[a + 4:a + 12])
    sizes = [each] * min(count, MP4_ROWS) if each else [n for n, in mp4_rows(data, a + 8, b, ">I")]
    a, b = mp4_one(stbl, b"stsc")
    runs = mp4_rows(data, a + 4, b, ">III")
    wide = b"co64" in stbl
    a, b = mp4_one(stbl, b"co64" if wide else b"stco")
    out, taken, run = [], 0, -1
    for i, (at,) in enumerate(mp4_rows(data, a + 4, b, ">Q" if wide else ">I"), 1):
        while run + 1 < len(runs) and runs[run + 1][0] <= i:
            run += 1
        if run < 0 or runs[run][1] > len(sizes) - taken:
            raise ValueError("an MP4 whose video is not all in it")
        end = at + sum(sizes[taken:taken + runs[run][1]])
        taken += runs[run][1]
        if not any(x <= at and end <= y for x, y in mdats[:16]):
            raise ValueError("an MP4 whose video is not all in it")
        out.append((at, end))
    if not out or taken != len(sizes) or sum(y - x for x, y in out) > sum(y - x for x, y in mdats):
        raise ValueError("an MP4 whose video is not all in it")
    return out


# --- a reel: an animated WebP the dialog plays. Its decoder ends the dialog on a frame that is not the size
# its header says, so each frame's own header is read here and, before it decodes, there (animation.rs)

REEL_MOST = (1024, 1024)
REEL_FRAMES = 1000
WEBP_PAST = {b"ICCP", b"EXIF", b"XMP "}   # metadata: read past, and no part of a bare one


def webp_chunks(data, a, b):
    """-> (kind, inside, end) for each chunk from a to b, which they fill, a last odd byte left unpadded or not."""
    out = []
    while a < b:
        if b - a < 8 or len(out) > 2 * REEL_FRAMES:
            raise ValueError("a broken WebP")
        kind, n = struct.unpack("<4sI", data[a:a + 8])
        if n > b - a - 8:
            raise ValueError("a WebP cut short")
        out.append((kind, a + 8, a + 8 + n))
        a += 8 + n + (n & 1)
    return out


def u24(data, at):
    return data[at] | data[at + 1] << 8 | data[at + 2] << 16


def webp_frame(data, kind, a, b):
    """-> (width, height) a VP8 or VP8L bitstream says of itself."""
    if kind == b"VP8 " and b - a >= 10 and not data[a] & 1 and data[a + 3:a + 6] == b"\x9d\x01\x2a":
        w, h = struct.unpack("<HH", data[a + 6:a + 10])
        return w & 0x3FFF, h & 0x3FFF
    if kind == b"VP8L" and b - a >= 5 and data[a] == 0x2F:
        n, = struct.unpack("<I", data[a + 1:a + 5])
        if not n >> 29:
            return (n & 0x3FFF) + 1, (n >> 14 & 0x3FFF) + 1
    raise ValueError("a WebP with a broken frame")


def webp_size(data):
    """-> (width, height) of any WebP, whole."""
    end = 8 + struct.unpack("<I", data[4:8])[0]
    if end > len(data):
        raise ValueError("a WebP cut short")
    if data[12:16] == b"VP8X" and end >= 30:
        return u24(data, 24) + 1, u24(data, 27) + 1
    return webp_frame(data, data[12:16], 20, end)


def reel_read(data, strict=True):
    """-> (width, height, frames, the reel bare). Not STRICT, what is no part of it may be in it or after it."""
    if not is_webp(data):
        raise ValueError("no WebP")
    end = 8 + struct.unpack("<I", data[4:8])[0]
    if end > len(data):
        raise ValueError("a WebP cut short")
    if strict and len(data) > end + (end & 1):
        raise ValueError("a WebP with data after its end")
    chunks = webp_chunks(data, 12, end)
    if not chunks or chunks[0][0] != b"VP8X" or chunks[0][2] - chunks[0][1] != 10 or not data[chunks[0][1]] & 2:
        raise ValueError("a still WebP, no animation")
    at = chunks[0][1]
    if not data[at] & 16:
        raise ValueError("a WebP with no clear ground (no alpha)")
    w, h = u24(data, at + 4) + 1, u24(data, at + 7) + 1
    if w > REEL_MOST[0] or h > REEL_MOST[1]:
        raise ValueError("%dx%d, past %dx%d" % ((w, h) + REEL_MOST))
    out, frames, anim = [webp_chunk(b"VP8X", b"\x12\0\0\0" + data[at + 4:at + 10])], 0, False
    for kind, a, b in chunks[1:]:
        if kind == b"ANIM" and b - a == 6 and not anim:
            anim = True
            out.append(webp_chunk(kind, data[a:b]))
        elif kind == b"ANMF" and anim:
            frames += 1
            if frames > REEL_FRAMES:
                raise ValueError("a WebP of over %d frames" % REEL_FRAMES)
            out.append(webp_chunk(kind, reel_frame(data, a, b, w, h, strict)))
        elif strict and kind not in WEBP_PAST:
            raise ValueError("a WebP with a %r chunk, which a reel has not" % kind.decode("latin-1"))
    if not frames:
        raise ValueError("a still WebP, no animation")
    body = b"WEBP" + b"".join(out)
    return w, h, frames, struct.pack("<4sI", b"RIFF", len(body)) + body


def reel_frame(data, a, b, width, height, strict):
    """-> a frame with its own chunks alone, on the canvas and the size its header says."""
    if b - a < 32:
        raise ValueError("a WebP with a broken frame")
    x, y, w, h = 2 * u24(data, a), 2 * u24(data, a + 3), u24(data, a + 6) + 1, u24(data, a + 9) + 1
    if x + w > width or y + h > height:
        raise ValueError("a WebP with a frame outside its picture")
    parts = webp_chunks(data, a + 16, b)
    own = parts[:2] if parts[0][0] == b"ALPH" else parts[:1]
    if own[-1][0] != (b"VP8 " if len(own) == 2 else own[0][0]) or strict and len(parts) != len(own):
        raise ValueError("a WebP with a broken frame")
    if webp_frame(data, *own[-1]) != (w, h):
        raise ValueError("a WebP whose frame is not the size its header says")
    if own[0][0] == b"ALPH":
        s, e = own[0][1:]
        if e == s or data[s] & 2 or data[s] >> 4 & 2 or not data[s] & 1 and e - s - 1 < w * h:
            raise ValueError("a WebP with a broken frame")
    return data[a:a + 16] + b"".join(webp_chunk(k, data[s:e]) for k, s, e in own)


def webp_chunk(kind, body):
    return struct.pack("<4sI", kind, len(body)) + body + b"\0" * (len(body) & 1)


def file_bare(data, kind=""):
    """-> a picture, a loop or a reel with its own parts alone: KIND, else whichever it is."""
    if kind == "loop" or not kind and is_mp4(data):
        bare = bytearray(data)
        loop_read(data, bare)
        return bytes(bare)
    if kind == "reel" or not kind and is_webp(data):
        return reel_read(data, False)[3]
    return picture_bare(data)


# --- a theme file: one theme's folder in a plain tar (spark-shell theme export and theme install FILE)

THEME_FILE_KINDS = {"env": 8192, "json": 65536, "jpg": 16 << 20, "jpeg": 16 << 20, "png": 16 << 20,
                    "mp4": 64 << 20, "webp": 16 << 20}   # the most bytes of each
THEME_FILE_MAX = 256 << 20   # all its files together
THEME_FILE_COUNT = 32
THEME_NAME = re.compile(r"[a-z][a-z0-9-]{0,39}\Z")
THEME_PART = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}\Z")


THEME_TEXT = bytes(range(32, 127)) + b"\t\n"   # what its look, its colors and its family are written in


def said(s):
    return "".join(c for c in s if c.isprintable())[:60]


def theme_kind(part, size):
    """-> the kind of a file a theme may hold, named plainly and within its size."""
    if not THEME_PART.match(part):
        raise ValueError("it holds a file named %s" % said(part))
    kind = part.rsplit(".", 1)[1].lower() if "." in part else ""
    if kind not in THEME_FILE_KINDS:
        raise ValueError("it holds %s, a kind of file a theme has not" % part)
    cap = THEME_FILE_KINDS[kind]
    if size > cap:
        raise ValueError("its %s is over %s" % (part, "%d MiB" % (cap >> 20) if cap >= 1 << 20 else "%d KiB" % (cap >> 10)))
    return kind


def theme_plain(part, kind, data):
    """DATA, refused when PART is text and holds a byte that is not (grep reads past a NUL, jq past some)."""
    if kind in ("env", "json") and data.translate(None, THEME_TEXT):
        raise ValueError("its %s holds a byte that is not plain text" % part)
    return data


def theme_pack(folder, out):
    """OUT: a plain tar of FOLDER's files as NAME/FILE, in name order, no owner and no time. What a reader of
    it refuses is refused here; a picture whose name is one (My Photo.jpg) goes as NAME-picture.jpg."""
    name = os.path.basename(os.path.normpath(folder))
    if not THEME_NAME.match(name):
        raise ValueError("%s is not a theme's name (a to z, 0 to 9 and -, 40 at most)" % said(name))
    parts, total = {}, 0
    for part in sorted(os.listdir(folder)):
        p = os.path.join(folder, part)
        if not stat.S_ISREG(os.lstat(p).st_mode):
            raise ValueError("%s is not a plain file" % said(part))
        parts[part] = read_file(p)
    look = parts.get("look.env", b"")
    picture = os.fsdecode(next((x[8:] for x in look.split(b"\n") if x.startswith(b"PICTURE=")), b""))
    if picture in parts and not THEME_PART.match(picture):
        plain = "%s-picture.%s" % (name, picture.rsplit(".", 1)[-1].lower())
        parts[plain] = parts.pop(picture)
        parts["look.env"] = look.replace(b"PICTURE=" + os.fsencode(picture) + b"\n", b"PICTURE=" + os.fsencode(plain) + b"\n")
    if len(parts) > THEME_FILE_COUNT:
        raise ValueError("it holds over %d files" % THEME_FILE_COUNT)
    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as t:
        for part in sorted(parts):
            data = theme_plain(part, theme_kind(part, len(parts[part])), parts[part])
            total += len(data)
            if total > THEME_FILE_MAX:
                raise ValueError("its files are over %d MiB" % (THEME_FILE_MAX >> 20))
            info = tarfile.TarInfo(name + "/" + part)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            t.addfile(info, io.BytesIO(data))


def theme_unpack(path, out):
    """-> the theme's name, its files in OUT/NAME. Read member by member, never extracted as the file
    says: a plain file alone, in the one folder, named plainly, of a kind a theme holds, within its size."""
    if os.path.getsize(path) > THEME_FILE_MAX + (1 << 20):
        raise ValueError("it is over %d MiB" % (THEME_FILE_MAX >> 20))
    try:
        t = tarfile.open(path, "r:")
    except tarfile.TarError:
        raise ValueError("it is not a theme file") from None
    name, seen, total, members = None, set(), 0, 0
    with t:
        for m in t:
            members += 1
            if members > 2 * THEME_FILE_COUNT:
                raise ValueError("it holds over %d files" % THEME_FILE_COUNT)
            head, _, part = m.name.partition("/")
            if m.isdir() and part == "" and (name is None or head == name):
                continue
            if not m.isreg():
                raise ValueError("it holds a link, a device or a folder: %s" % said(m.name))
            if not part or "/" in part:
                raise ValueError("its files are not in one folder")
            if not THEME_NAME.match(head):
                raise ValueError("its folder is not a theme's name (a to z, 0 to 9 and -, 40 at most)")
            if name is None:
                name = head
                os.mkdir(os.path.join(out, name), 0o700)
            elif head != name:
                raise ValueError("it holds more than one theme")
            kind = theme_kind(part, m.size)
            if part in seen:
                raise ValueError("it holds %s twice" % part)
            if len(seen) >= THEME_FILE_COUNT:
                raise ValueError("it holds over %d files" % THEME_FILE_COUNT)
            total += m.size
            if total > THEME_FILE_MAX:
                raise ValueError("its files are over %d MiB" % (THEME_FILE_MAX >> 20))
            seen.add(part)
            src = t.extractfile(m)
            fd = os.open(os.path.join(out, name, part), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "wb") as dst:
                left = m.size
                while left:
                    b = src.read(min(left, 1 << 20))
                    if not b:
                        raise ValueError("it is cut short")
                    dst.write(theme_plain(part, kind, b))
                    left -= len(b)
    if name is None:
        raise ValueError("it holds no theme")
    return name


# --- the command

def edge_colors(path):
    """-> (top, bottom) as #rrggbb: the mean of the picture's top and bottom twentieth. Only a small,
    opaque PNG is read, every pixel kept in its row (read_png keeps them all under sixty thousand)."""
    head = open(path, "rb").read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    w, h = struct.unpack(">II", head[16:24])
    if w * h > 60000:
        raise ValueError("a picture of %dx%d is too large to read its edges; give a small one" % (w, h))
    px = read_png(path)
    if len(px) != w * h:
        raise ValueError("the picture has clear pixels, so its rows are not whole")
    band = max(1, h // 20)
    mean = lambda ps: tuple(sum(c[i] for c in ps) / len(ps) for i in range(3))
    return hexs(mean(px[:w * band])), hexs(mean(px[w * (h - band):]))


def why(e, broken="a broken file"):
    """-> an exception as one line: this file's own words, the system's, or BROKEN."""
    if isinstance(e, OSError) and e.strerror:
        return e.strerror
    return str(e) if type(e) is ValueError else broken


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
    if argv[1] == "edges":
        if len(argv) != 3:
            sys.stderr.write("edges takes a PNG\n")
            return 1
        try:
            print("%s %s" % edge_colors(argv[2]))
        except (OSError, ValueError, zlib.error, struct.error) as e:
            sys.stderr.write("%s\n" % e)
            return 1
        return 0
    if argv[1] in ("picture", "shown", "loop", "reel"):
        if len(argv) != 3:
            sys.stderr.write("%s takes a file\n" % argv[1])
            return 1
        try:
            if argv[1] == "picture":
                print("%s %d %d" % picture_size(argv[2]))
            elif argv[1] == "shown":
                print("%s %d %d" % picture_shown(argv[2]))
            elif argv[1] == "loop":
                print("%d %d" % loop_read(read_file(argv[2])))
            else:
                print("%d %d %d" % reel_read(read_file(argv[2]))[:3])
        except Exception as e:
            sys.stderr.write("%s\n" % why(e))
            return 1
        return 0
    if argv[1] in ("bare", "pack", "unpack"):
        if len(argv) != 4 and not (argv[1] == "bare" and len(argv) == 5 and argv[4] in ("picture", "loop", "reel")):
            sys.stderr.write("%s takes two paths\n" % argv[1])
            return 1
        try:
            if argv[1] == "bare":
                data = file_bare(read_file(argv[2]), *argv[4:])
                with open(argv[3], "xb") as fh:
                    fh.write(data)
            elif argv[1] == "pack":
                theme_pack(argv[2], argv[3])
            else:
                print(theme_unpack(argv[2], argv[3]))
        except Exception as e:
            sys.stderr.write("%s\n" % why(e, "a broken file" if argv[1] == "bare" else "it is broken"))
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
