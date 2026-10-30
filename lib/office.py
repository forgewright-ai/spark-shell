#!/usr/bin/env python3
"""office.py -- the text of an Office document, for a preview (#120). Python's standard library only.

  office.py FILE      {"lines": [...], "bold": [...]} as JSON on stdout; exit 1 when FILE is not
                      a document this reads

Reads docx, pptx and xlsx (Office Open XML) and odt, odp and ods (OpenDocument): a document's
paragraphs, a heading bold, a list's items marked, a table's cells a row a line; a presentation's
slides, each under its number in bold; a sheet's cells a row a line, each sheet under its name.
A document is untrusted: it is read for its text alone, never run. No macro, no linked file, no
external entity (expat resolves none here); a part of it over PART_MAX unpacked is not read, and
the text stops at LINES_MAX lines.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

PART_MAX = 8 << 20
LINES_MAX = 20000
CELLS_MAX = 64          # a row's cells at most: a sheet's repeated empty columns are no text
SEP = " \u00b7 "        # between a table's cells and a sheet's, as the dialog parts its facts

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
S = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
TEXT = "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}"
TABLE = "{urn:oasis:names:tc:opendocument:xmlns:table:1.0}"
DRAW = "{urn:oasis:names:tc:opendocument:xmlns:drawing:1.0}"
OFFICE = "{urn:oasis:names:tc:opendocument:xmlns:office:1.0}"


class Doc:
    def __init__(self):
        self.lines, self.bold = [], []

    def add(self, text, bold=False):
        text = " ".join(text.split())
        if len(self.lines) >= LINES_MAX:
            return
        if not text and (not self.lines or not self.lines[-1]):
            return  # one blank line between blocks, never two
        if bold:
            self.bold.append(len(self.lines))
        self.lines.append(text)

    def result(self):
        while self.lines and not self.lines[-1]:
            self.lines.pop()
        return {"lines": self.lines, "bold": [b for b in self.bold if b < len(self.lines)]}


def part(z, name):
    info = z.getinfo(name)
    if info.file_size > PART_MAX:
        raise ValueError("a part over PART_MAX")
    return ET.fromstring(z.read(info))


def texts(el, t_tag):
    return "".join(t.text or "" for t in el.iter(t_tag))


def docx(z, doc):
    body = part(z, "word/document.xml").find(W + "body")
    for block in list(body if body is not None else []):
        if block.tag == W + "p":
            style = block.find(f"{W}pPr/{W}pStyle")
            name = style.get(W + "val", "") if style is not None else ""
            listed = block.find(f"{W}pPr/{W}numPr") is not None
            words = paragraph(block)
            heading = bool(re.match(r"(?i)(heading|title)", name))
            if heading:
                doc.add("")
            doc.add(("\u2022 " + words) if listed and words else words, bold=(heading or all_bold(block)) and bool(words))
        elif block.tag == W + "tbl":
            for tr in block.iter(W + "tr"):
                cells = [" ".join(paragraph(p) for p in tc.iter(W + "p")).strip() for tc in tr.findall(W + "tc")]
                doc.add(SEP.join(cells[:CELLS_MAX]))
            doc.add("")


def all_bold(p):
    """Every run with words in it is bold: the paragraph is drawn bold, as it is written."""
    runs = [r for r in p.iter(W + "r") if texts(r, W + "t").strip()]

    def bold(r):
        b = r.find(f"{W}rPr/{W}b")
        return b is not None and b.get(W + "val", "true") not in ("0", "false")

    return bool(runs) and all(bold(r) for r in runs)


def paragraph(p):
    out = []
    for el in p.iter():
        if el.tag == W + "t":
            out.append(el.text or "")
        elif el.tag in (W + "tab", W + "br"):
            out.append(" ")
    return "".join(out)


def pptx(z, doc):
    slides = sorted((n for n in z.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)), key=lambda n: int(re.findall(r"\d+", n)[-1]))
    for k, name in enumerate(slides, 1):
        doc.add("")
        doc.add(f"Slide {k}", bold=True)
        for p in part(z, name).iter(A + "p"):
            doc.add(texts(p, A + "t"))


def xlsx(z, doc):
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        shared = [texts(si, S + "t") for si in part(z, "xl/sharedStrings.xml").iter(S + "si")]
    names = [s.get("name", "") for s in part(z, "xl/workbook.xml").iter(S + "sheet")]
    sheets = sorted((n for n in z.namelist() if re.fullmatch(r"xl/worksheets/sheet\d+\.xml", n)), key=lambda n: int(re.findall(r"\d+", n)[-1]))
    for k, name in enumerate(sheets):
        doc.add("")
        doc.add(names[k] if k < len(names) and names[k] else f"Sheet {k + 1}", bold=True)
        for row in part(z, name).iter(S + "row"):
            cells = []
            for c in row.findall(S + "c")[:CELLS_MAX]:
                kind, v = c.get("t", ""), c.find(S + "v")
                if kind == "s" and v is not None and (v.text or "").isdigit() and int(v.text) < len(shared):
                    cells.append(shared[int(v.text)])
                elif kind == "inlineStr":
                    cells.append(texts(c, S + "t"))
                else:
                    cells.append(v.text or "" if v is not None else "")
            while cells and not cells[-1]:
                cells.pop()
            if cells:
                doc.add(SEP.join(cells))


def odf(z, doc, sheets=False):
    body = part(z, "content.xml").find(OFFICE + "body")
    if body is None:
        return
    up = {c: p for p in body.iter() for c in p}

    def under(el, tag):
        while el in up:
            el = up[el]
            if el.tag == tag:
                return True
        return False

    slide = 0
    for el in body.iter():
        if el.tag == DRAW + "page":
            slide += 1
            doc.add("")
            doc.add(f"Slide {slide}", bold=True)
        elif el.tag == TABLE + "table":
            doc.add("")
            if sheets:
                doc.add(el.get(TABLE + "name", "Sheet"), bold=True)
            for row in el.iter(TABLE + "table-row"):
                cells = []
                for c in row.findall(TABLE + "table-cell"):
                    words = " ".join(odf_text(p) for p in c.iter(TEXT + "p")).strip()
                    n = int(c.get(TABLE + "number-columns-repeated", "1") or 1) if words else 1
                    cells.extend([words] * min(n, CELLS_MAX))
                    if len(cells) >= CELLS_MAX:
                        break
                while cells and not cells[-1]:
                    cells.pop()
                if cells:
                    doc.add(SEP.join(cells[:CELLS_MAX]))
        elif el.tag in (TEXT + "h", TEXT + "p") and not under(el, TABLE + "table"):
            words = odf_text(el)
            if el.tag == TEXT + "h":
                doc.add("")
                doc.add(words, bold=True)
            else:
                doc.add(("\u2022 " + words) if under(el, TEXT + "list-item") and words else words)


def odf_text(el):
    """A paragraph's words, its spaces, tabs and line breaks (elements of their own) as spaces."""
    out = []

    def walk(e):
        if e.tag in (TEXT + "s", TEXT + "tab", TEXT + "line-break"):
            out.append(" ")
        out.append(e.text or "")
        for c in e:
            walk(c)
            out.append(c.tail or "")

    walk(el)
    return "".join(out)


READERS = {"docx": docx, "pptx": pptx, "xlsx": xlsx, "odt": odf, "odp": odf, "ods": lambda z, doc: odf(z, doc, sheets=True)}


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    kind = argv[1].rsplit(".", 1)[-1].lower()
    if kind not in READERS:
        return 1
    doc = Doc()
    try:
        with zipfile.ZipFile(argv[1]) as z:
            READERS[kind](z, doc)
    except (OSError, KeyError, ValueError, RecursionError, zipfile.BadZipFile, ET.ParseError):
        return 1
    out = doc.result()
    if not out["lines"]:
        return 1
    json.dump(out, sys.stdout, ensure_ascii=False)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
