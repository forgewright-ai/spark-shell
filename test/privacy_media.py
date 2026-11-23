#!/usr/bin/env python3
"""privacy_media.py -- the privacy gate's second look at the files its word list hit.

  printf '%s\\n' FILE... | PRIVACY_TERMS=REGEX python3 -I test/privacy_media.py
        the files that still hold a listed word, one a line; 1 when any
  python3 -I test/privacy_media.py
        no word list: checks itself (as ci.yml's python3 tests run)

A picture, a loop or a reel (PNG, JPEG, MP4, WebP) is read by its parts, and only the parts a person
writes in are searched: its metadata, comments and names. Its coded pixels and frames are not, as any
short word turns up in megabytes of them by chance. A file of another kind is searched whole, and one
whose parts do not read is searched whole too. The words match as git grep -i -w matches them. Only a
file's name is printed, never what it holds: CI's log is public.
"""
import os
import re
import struct
import sys

WORD = rb"[A-Za-z0-9_]"


def parts(data):
    """-> the byte strings a person may have written, or None for a file of no known kind."""
    if data[4:8] == b"ftyp":   # MP4: every box but the coded media's payload
        out, pos = [], 0
        while pos + 8 <= len(data):
            size, kind = struct.unpack(">I4s", data[pos:pos + 8])
            head = 8
            if size == 1:
                size, head = struct.unpack(">Q", data[pos + 8:pos + 16])[0], 16
            elif size == 0:
                size = len(data) - pos
            if size < head or pos + size > len(data):
                return None
            out.append(data[pos:pos + head] if kind == b"mdat" else data[pos:pos + size])
            pos += size
        return out if pos == len(data) else None
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":   # WebP: every chunk but the coded frames
        out, pos = [data[:12]], 12
        while pos + 8 <= len(data):
            kind = data[pos:pos + 4]
            n, = struct.unpack("<I", data[pos + 4:pos + 8])
            end = pos + 8 + n + (n & 1)
            if end > len(data):
                return None
            out.append(data[pos:pos + 8] if kind in (b"VP8 ", b"VP8L", b"ALPH", b"ANMF") else data[pos:end])
            pos = end
        return out if pos == len(data) else None
    if data[:8] == b"\x89PNG\r\n\x1a\n":   # PNG: every chunk but the coded pixels
        out, pos = [], 8
        while pos + 12 <= len(data):
            n, = struct.unpack(">I", data[pos:pos + 4])
            kind, end = data[pos + 4:pos + 8], pos + 12 + n
            if end > len(data):
                return None
            out.append(data[pos:pos + 8] if kind in (b"IDAT", b"fdAT") else data[pos:end])
            pos = end
        return out if pos == len(data) else None
    if data[:3] == b"\xff\xd8\xff":   # JPEG: every segment, not a scan's coded bytes; what follows its end
        out, pos = [], 2
        while pos + 2 <= len(data):
            if data[pos] != 0xFF:
                return None
            m = data[pos + 1]
            if m == 0xFF:
                pos += 1
                continue
            if m == 0xD9:
                out.append(data[pos + 2:])
                return out
            if m == 0xD8 or 0xD0 <= m <= 0xD7:
                pos += 2
                continue
            if pos + 4 > len(data):
                return None
            n, = struct.unpack(">H", data[pos + 2:pos + 4])
            end = pos + 2 + n
            if end > len(data):
                return None
            out.append(data[pos:end])
            if m == 0xDA:
                while True:
                    end = data.find(b"\xff", end)
                    if end < 0 or end + 1 >= len(data):
                        return None
                    nx = data[end + 1]
                    if nx == 0x00 or nx == 0xFF or 0xD0 <= nx <= 0xD7:
                        end += 1
                        continue
                    break
            pos = end
        return None
    return None


def holds(rx, data):
    p = parts(data)
    return any(rx.search(x) for x in (p if p is not None else [data]))


def words(terms):
    return re.compile(b"(?<!" + WORD + b")(?:" + terms.encode("utf-8", "surrogateescape") + b")(?!" + WORD + b")", re.I)


def self_check():
    rx = words(r"ember|tide\-pool")
    box = lambda kind, body: struct.pack(">I4s", 8 + len(body), kind) + body
    chunk = lambda kind, body: kind + struct.pack("<I", len(body)) + body + b"\0" * (len(body) & 1)
    png = lambda kind, body: struct.pack(">I", len(body)) + kind + body + b"\0\0\0\0"
    jpeg = lambda m, body: bytes([0xFF, m]) + struct.pack(">H", len(body) + 2) + body
    sof = jpeg(0xC0, b"\x08\x00\x10\x00\x20\x03\x01\x11\x00\x02\x11\x00\x03\x11\x00")
    sos = jpeg(0xDA, b"\x03\x01\x00\x02\x11\x03\x11\x00\x3f\x00") + b"\x01 ember \x02\xff\x00\x03"
    cases = [
        ("an MP4's coded frames", box(b"ftyp", b"isom") + box(b"moov", b"mvhd") + box(b"mdat", b"\x00 Ember \x01"), False),
        ("an MP4's title", box(b"ftyp", b"isom") + box(b"moov", box(b"udta", b"\xa9nam tide-pool")) + box(b"mdat", b"\x00"), True),
        ("a WebP's frames", b"RIFF\0\0\0\0WEBP" + chunk(b"VP8X", b"\0" * 10) + chunk(b"ANMF", b"\0 ember \0"), False),
        ("a WebP's XMP", b"RIFF\0\0\0\0WEBP" + chunk(b"VP8 ", b"x ember x") + chunk(b"XMP ", b"<dc:creator>ember</dc:creator>"), True),
        ("a PNG's pixels", b"\x89PNG\r\n\x1a\n" + png(b"IHDR", b"\0" * 13) + png(b"IDAT", b"\x01 ember \x02") + png(b"IEND", b""), False),
        ("a PNG's text", b"\x89PNG\r\n\x1a\n" + png(b"IHDR", b"\0" * 13) + png(b"tEXt", b"Author\0Ember") + png(b"IEND", b""), True),
        ("a JPEG's scan", b"\xff\xd8" + sof + sos + b"\xff\xd9", False),
        ("a JPEG's EXIF", b"\xff\xd8" + jpeg(0xE1, b"Exif\0\0Artist ember") + sof + sos + b"\xff\xd9", True),
        ("what follows a JPEG's end", b"\xff\xd8" + sof + sos + b"\xff\xd9 ember", True),
        ("a JPEG that does not read", b"\xff\xd8\xff\xe1\x00", None),
        ("a text file", b"notes: the ember glows", True),
        ("a word inside another", b"remember the tide-pools", False),
    ]
    bad = []
    for what, data, want in cases:
        got = holds(rx, data)
        if want is None:
            want = rx.search(data) is not None
        if got != want:
            bad.append("%s: %s" % (what, "found" if got else "not found"))
    for b in bad:
        print("privacy_media: " + b)
    if not bad:
        print("privacy_media: a listed word in a picture's, a loop's or a reel's metadata is found; in its coded data, not")
    return 1 if bad else 0


def main(argv):
    if len(argv) > 1:
        sys.stderr.write(__doc__)
        return 2
    terms = os.environ.get("PRIVACY_TERMS", "")
    if not terms:
        return self_check()
    rx, hit = words(terms), False
    for line in sys.stdin:
        name = line.rstrip("\n")
        if not name:
            continue
        with open(name, "rb") as fh:
            if holds(rx, fh.read()):
                print(name)
                hit = True
    return 1 if hit else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
