#!/usr/bin/env python3
"""office_test.py -- lib/office.py on documents made here, one of each kind (#120). Standard library only."""
import json
import os
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OFFICE = os.path.join(HERE, "..", "lib", "office.py")
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
S = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
ODF = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
       'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"')
fails = 0


def check(name, ok, got):
    global fails
    print("  ok   %s" % name if ok else "  FAIL %s   %s" % (name, got))
    fails += 0 if ok else 1


def make(path, parts):
    with zipfile.ZipFile(path, "w") as z:
        for name, text in parts.items():
            z.writestr(name, text)


def read(path):
    r = subprocess.run([sys.executable, "-I", OFFICE, path], capture_output=True, text=True)
    return r.returncode, (json.loads(r.stdout) if r.returncode == 0 else None)


with tempfile.TemporaryDirectory() as d:
    p = lambda n: os.path.join(d, n)
    make(p("a.docx"), {"word/document.xml": '<w:document %s><w:body>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Plan</w:t></w:r></w:p>'
        '<w:p><w:r><w:t xml:space="preserve">Some </w:t></w:r><w:r><w:t>words.</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>first</w:t></w:r></w:p>'
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>All bold</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Region</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Sales</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
        '</w:body></w:document>' % W})
    st, out = read(p("a.docx"))
    check("docx: a heading and a bold paragraph bold, a list's item marked, a table's row a line",
          st == 0 and out["lines"] == ["Plan", "Some words.", "\u2022 first", "All bold", "Region \u00b7 Sales"] and out["bold"] == [0, 3], out)
    make(p("a.pptx"), {"ppt/slides/slide2.xml": '<p:sld xmlns:p="x" %s><a:p><a:r><a:t>Second</a:t></a:r></a:p></p:sld>' % A,
                       "ppt/slides/slide1.xml": '<p:sld xmlns:p="x" %s><a:p><a:r><a:t>First</a:t></a:r></a:p></p:sld>' % A})
    st, out = read(p("a.pptx"))
    check("pptx: the slides in their order, each under its number in bold", st == 0 and out["lines"] == ["Slide 1", "First", "", "Slide 2", "Second"] and out["bold"] == [0, 3], out)
    make(p("a.xlsx"), {"xl/sharedStrings.xml": '<sst %s><si><t>Region</t></si><si><t>North</t></si></sst>' % S,
                       "xl/workbook.xml": '<workbook %s><sheets><sheet name="Sales"/></sheets></workbook>' % S,
                       "xl/worksheets/sheet1.xml": '<worksheet %s><sheetData><row><c t="s"><v>0</v></c><c><v>12</v></c></row><row><c t="s"><v>1</v></c><c><v>120</v></c></row></sheetData></worksheet>' % S})
    st, out = read(p("a.xlsx"))
    check("xlsx: a sheet under its name, a row a line", st == 0 and out["lines"] == ["Sales", "Region \u00b7 12", "North \u00b7 120"] and out["bold"] == [0], out)
    make(p("a.odt"), {"content.xml": '<office:document-content %s><office:body><office:text>'
        '<text:h>Plan</text:h><text:p>Some<text:s/>words.</text:p><text:list><text:list-item><text:p>first</text:p></text:list-item></text:list>'
        '<table:table table:name="T1"><table:table-row><table:table-cell><text:p>a</text:p></table:table-cell></table:table-row></table:table>'
        '</office:text></office:body></office:document-content>' % ODF})
    st, out = read(p("a.odt"))
    check("odt: a heading bold, its spaces kept, a list's item marked, a table's row with no name over it",
          st == 0 and out["lines"] == ["Plan", "Some words.", "\u2022 first", "", "a"] and out["bold"] == [0], out)
    make(p("a.ods"), {"content.xml": '<office:document-content %s><office:body><office:spreadsheet>'
        '<table:table table:name="Sheet1"><table:table-row><table:table-cell><text:p>x</text:p></table:table-cell>'
        '<table:table-cell table:number-columns-repeated="16000"/></table:table-row></table:table></office:spreadsheet></office:body></office:document-content>' % ODF})
    st, out = read(p("a.ods"))
    check("ods: a sheet under its name; a run of empty cells is no text", st == 0 and out["lines"] == ["Sheet1", "x"], out)
    rows = "".join('<row><c t="inlineStr"><is><t>r%d</t></is></c><c><v>%d</v></c></row>' % (i, i) for i in range(150000))
    make(p("big.xlsx"), {"xl/workbook.xml": '<workbook %s><sheets><sheet name="Sales"/></sheets></workbook>' % S,
                         "xl/worksheets/sheet1.xml": '<worksheet %s><sheetData>%s</sheetData></worksheet>' % (S, rows)})
    st, out = read(p("big.xlsx"))
    check("xlsx: a sheet's part over 8 MB is read row by row, its first rows shown up to the lines' limit",
          st == 0 and out["lines"][:3] == ["Sales", "r0 \u00b7 0", "r1 \u00b7 1"] and len(out["lines"]) == 20000, (st, out and out["lines"][:3], out and len(out["lines"])))
    with open(p("bad.docx"), "w") as f:
        f.write("not a zip")
    make(p("big.docx"), {"word/document.xml": "<w:document %s><w:body>%s</w:body></w:document>" % (W, "<w:p/>" * 2000000)})
    make(p("entity.docx"), {"word/document.xml": '<!DOCTYPE d [<!ENTITY x SYSTEM "file:///etc/passwd">]><w:document %s><w:body><w:p><w:r><w:t>&x;</w:t></w:r></w:p></w:body></w:document>' % W})
    st1, _ = read(p("bad.docx"))
    st2, _ = read(p("big.docx"))
    st3, out3 = read(p("entity.docx"))
    st4, _ = read(p("a.rtf"))
    check("a file that is no document, a part over 8 MB, an external entity, another type: not read",
          st1 == 1 and st2 == 1 and (st3 == 1 or "root:" not in json.dumps(out3)) and st4 == 1, (st1, st2, st3, out3, st4))

print("office_test: %s" % ("ok" if fails == 0 else "%d failed" % fails))
sys.exit(1 if fails else 0)
