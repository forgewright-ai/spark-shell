#!/usr/bin/env python3
"""Files in native Sway/foot on an isolated desktop, against the real provider on a fixture home.

python3 tests/files_desktop_proof.py BINARY EVIDENCE_DIRECTORY
The fixture HOME holds the proof's own files alone, written before the dialog starts: documents (a Markdown
note, a text, a Python draft, a 20 by 40 PNG, a one-page PDF, a second of silence), pictures (a PNG and a
notes.md and a todo.txt a copy runs into), big (10,000 small files) and an empty folder, and on the PATH a stub
xdg-open and a stub editor that write what they are handed to a file. Every label looked for is the spec's,
dialog/DESIGN.md "Files", lowercase; the header and the status row are matched loosely around the separator
glyph. A tool the machine lacks (poppler, mpv) is said in a check, never failed.
"""
from collections import Counter
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import time
import wave
import zlib

import apps_desktop_proof
from apps_desktop_proof import Session

CHECK = "\u2713"   # the sign before a selected row's words (dialog/src/ui.rs CHECK)
LINE = "\u2502"    # the line between the panes
BIG = 10000        # the files of the large folder, ten pages of a thousand
EDITOR = "proof-editor"   # the stub EDITOR names: spark-shell's editor_pick takes it from the PATH
SIZE = r"[\d.]+ (?:B|KB|MB|GB)"
# the key bar, in its order (dialog/DESIGN.md, Keys): two lines at 60 cells, one at 120, the same in one pane and two
BAR = (r"back\s+Esc", r"nav\b", r"ren\s+F2", r"view\s+F3", r"open\s+F4",
       r"copy\s+F5", r"move\s+F6", r"new\s+F7", r"trash\s+F8", r"actions\s+F9")
# the rows of the actions, each with its key at the right (dialog/DESIGN.md, The actions)
MENU = (("open", "Enter"), ("open in app", "F4"), ("view", "F3"), ("rename", "F2"), ("copy", "F5"), ("move", "F6"),
        ("copy path", r"Ctrl\+C"), ("trash", "F8"), ("select", "Space"), ("new folder", "F7"))


def png(width, height):
    """A PNG of WIDTH by HEIGHT, 8-bit RGB, a gradient: zlib and struct alone."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)
    rows = b"".join(b"\0" + b"".join(bytes((x * 255 // max(width - 1, 1), y * 255 // max(height - 1, 1), 96)) for x in range(width))
                    for y in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def pdf(line):
    """A one-page PDF with LINE in Helvetica, written by hand with its xref table right."""
    content = ("BT /F1 18 Tf 72 720 Td (%s) Tj ET" % line).encode()
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>",
               b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
               b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
               b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offsets = bytearray(b"%PDF-1.4\n"), []
    for number, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    return bytes(out)


def silence(path, seconds=1, rate=8000):
    """A WAV of SECONDS of silence, mono, 16 bit."""
    with wave.open(str(path), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(rate)
        sound.writeframes(b"\0\0" * rate * seconds)


def build_tree(root, big=BIG):
    """The proof's own files under the fixture HOME, nothing of the host's; the time the big folder took.
    documents' names sort so notes.md and todo.txt are neighbours: Space on the one lands the bar on the other.
    pictures holds a notes.md and a todo.txt of its own, so a copy of the two stops on both names."""
    documents = root / "documents"
    documents.mkdir()
    (documents / "notes.md").write_text("# Proof notes\n\nA few lines of Markdown for the preview.\n\n- one line\n- another\n")
    (documents / "todo.txt").write_text("rename me\ntrash me\nbring me back\n")
    (documents / "draft.py").write_text("def main():\n    print('a draft')\n\n\nif __name__ == '__main__':\n    main()\n")
    (documents / "cover.png").write_bytes(png(20, 40))
    (documents / "letter.pdf").write_bytes(pdf("A one-page letter for the files proof."))
    silence(documents / "voice.wav")
    pictures = root / "pictures"
    pictures.mkdir()
    (pictures / "holiday.png").write_bytes(png(40, 20))
    (pictures / "notes.md").write_text("# Other notes\n\nThe file a copy of documents/notes.md runs into.\n")
    (pictures / "todo.txt").write_text("the file a copy of documents/todo.txt runs into\n")
    folder = root / "big"
    folder.mkdir()
    started = time.monotonic()
    for n in range(big):
        (folder / ("f%05d.txt" % n)).write_text("line %d\n" % n)
    took = time.monotonic() - started
    (root / "empty").mkdir()
    return {"big_files": big, "big_write_seconds": round(took, 3)}


def stub(path, log, stay=0):
    """A program that writes its first argument to LOG, a line each time, and exits: what it was handed, read back.
    STAY seconds before it exits keep a terminal around it long enough for its window to map."""
    path.write_text("#!/bin/sh\nprintf '%s\\n' \"$1\" >> " + shlex.quote(str(log)) + "\nsleep " + str(stay) + "\n")
    path.chmod(0o700)


def logged(path):
    return path.read_text().splitlines() if path.exists() else []


class FilesSession(Session):
    """Apps' Session with the files tree in its HOME and the stubs on its PATH before the dialog starts. The Session
    makes its HOME and starts sway in one step; the one call between the two that takes the HOME is the palette's
    read, so the tree is written on the way through it. The logs are hidden files: the home folder lists neither."""

    def __init__(self, binary, destination):
        self.timings = {}
        original = apps_desktop_proof.native_foot_config

        def with_tree(root):
            self.timings.update(build_tree(root))
            stub(root / "bin/xdg-open", root / ".xdg-open.log")
            stub(root / "bin" / EDITOR, root / ".editor.log", stay=2)
            return original(root)

        apps_desktop_proof.native_foot_config = with_tree
        try:
            super().__init__(binary, destination)
        finally:
            apps_desktop_proof.native_foot_config = original


def until(read, label, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = read()
        if value:
            return value
        time.sleep(.1)
    raise AssertionError("timed out: " + label)


RULE = "\u2500"


def bottom_rule(lines):
    """The plain rule above the key bar (dialog/DESIGN.md, the frame: h-4), the last row made of rule glyphs alone (the
    top rule carries the diamond). foot's dump drops the empty rows under the key bar, so the frame's bottom is found on
    the screen, never counted from its end."""
    for i in range(len(lines) - 1, 7, -1):
        s = lines[i].strip()
        if s and set(s) == {RULE}:
            return i
    return max(len(lines) - 3, 8)


def body(lines):
    """The content rows: from row 8 to the status row (dialog/DESIGN.md, the frame)."""
    return lines[8:bottom_rule(lines) - 1]


def status(lines):
    """The status row, the row above the plain rule."""
    return lines[bottom_rule(lines) - 1]


def keys(lines):
    """The key bar under the plain rule, its second line with it."""
    return "\n".join(lines[bottom_rule(lines) + 1:])


def column_left(lines):
    """The column's left edge: the prompt sign stands two cells into it (Session.settled)."""
    return max(len(lines[2]) - len(lines[2].lstrip()) - 2, 0)


def header_has(line, place):
    """The header names the place after `files` and the separator glyph: `files . ~`, `files . ~/documents`,
    `files . 2 selected`, `files . notes.md already exists`, `files . rename`; `~` alone is not `~/documents`."""
    return re.search(r"\bfiles\s*[^\w\s~<]\s*" + re.escape(place) + r"(?=\s|$)", line) is not None


def view_header(line, place):
    """A view's header, `view . ~/documents`."""
    return re.search(r"\bview\s*[^\w\s~<]\s*" + re.escape(place) + r"(?=\s|$)", line) is not None


def divider(lines):
    """The column of the line between the panes: the one column it fills down the content rows; None in one pane."""
    columns = Counter(i for line in body(lines) for i, cell in enumerate(line) if cell == LINE)
    column, rows = next(iter(columns.most_common(1)), (None, 0))
    return column if rows >= 3 else None


def halves(lines):
    """Each content row's number and its parts, (first column, words): the left and the right pane's cells, or the
    row whole in one pane."""
    edge = divider(lines)
    for i in range(8, bottom_rule(lines) - 1):
        yield i, [(0, lines[i])] if edge is None else [(0, lines[i][:edge]), (edge + 1, lines[i][edge + 1:])]


def pane(lines, side):
    """One pane's content rows, its own cells alone: side 0 the left, 1 the right; none in one pane."""
    edge = divider(lines)
    return [] if edge is None else [line[:edge] if side == 0 else line[edge + 1:] for line in body(lines)]


def paths(lines):
    """The two panes' paths, each on its pane's first row; None in one pane."""
    edge = divider(lines)
    return None if edge is None else (lines[8][:edge].strip(), lines[8][edge + 1:].strip())


def even_panes(s, lines, width):
    """The line stands in the middle of a column of WIDTH cells: 29 and 30, 59 and 60."""
    assert min(s.window()["rect"]["width"] // s.cell[0], 120) == width, s.window()["rect"]
    left = divider(lines) - column_left(lines)
    assert sorted((left, width - 1 - left)) == [width // 2 - 1, width // 2], "panes of %d and %d in %d cells" % (left, width - 1 - left, width)


def heading(rows, word):
    """A group's heading, the word alone on its row."""
    return any(re.match(r"\s*" + word + r"\s*$", row) for row in rows)


def short_summary(rows):
    """The folder's own row in a pane under 40 cells: `4 items . 4.5 MB`, and no `this folder`."""
    return not any("this folder" in row for row in rows) and any(re.match(r"\s*\d+ items?\s*\S\s*" + SIZE + r"\s*$", row) for row in rows)


def whole_summary(rows):
    """The folder's own row at 60 cells: `this folder . 1 folder . 3 files . 4.5 MB`."""
    return any(re.match(r"\s*this folder\s*\S\s*.*\d+ files?\s*\S\s*" + SIZE + r"\s*$", row) for row in rows)


def bar_holds(lines, rows):
    """The whole key bar, on ROWS lines; two take the row of air above them, right under the rule (v0.124.5)."""
    bar = keys(lines)
    for chip in BAR:
        assert re.search(r"\b" + chip, bar), chip + " is not on the key bar: " + bar
    assert len([line for line in bar.splitlines() if line.strip()]) == rows, bar
    assert bool(lines[bottom_rule(lines) + 1].strip()) == (rows == 2), "the key bar's first row: " + bar
    assert not re.search(r"\bpane\b", bar), "no pane key: the bar is the same in one pane and two: " + bar


def menu_holds(rows):
    """The actions, each row with its key at the right, in the rows of the page or of the pane they draw in."""
    for label, key in MENU:
        assert any(re.match(r"\s*" + re.escape(label) + r"\s{2,}" + key + r"\s*$", row) for row in rows), label + " with " + key + "\n" + "\n".join(rows)
    assert any(re.match(r"\s*new file\s*$", row) for row in rows), "new file\n" + "\n".join(rows)


def row_pattern(label):
    return re.compile(r"^(\s*(?:" + CHECK + r"\s+)?)" + re.escape(label) + r"(?=\s{2,}|\s*$)")


def find_row(lines, label, side=None):
    """The first list row whose words are LABEL (the sign allowed before them) and the column the words start at;
    in two panes in either, or in the pane SIDE. Anchored at the row's left, of the pane where there are two."""
    pattern = row_pattern(label)
    for i, parts in halves(lines):
        for n, (start, words) in enumerate(parts):
            m = pattern.match(words) if side is None or side == n else None
            if m:
                return i, start + len(m.group(1))
    return None


def row_named(lines, name):
    return find_row(lines, name) is not None


def selected(lines):
    """Any row wears the sign."""
    return any(CHECK in line for line in body(lines))


def counted(lines, n):
    """The status row counts the selection: `2 selected . 4.5 MB`."""
    return re.match(r"\s*%d selected\s*\S\s*%s\s*$" % (n, SIZE), status(lines)) is not None


def says(s, words):
    """A receipt with undo at its right."""
    row = status(s.screen())
    return words in row and re.search(r"\bundo\s*$", row) is not None


def reply_stands(lines):
    """A receipt or a refusal on the status row: its mark two cells into the column, or undo at its right; the
    lit row's line starts at the fourth cell with no mark."""
    row, left = status(lines), column_left(lines)
    return bool(row[left + 2:left + 3].strip()) or re.search(r"\bundo\s*$", row) is not None


def clear_reply(s):
    """A receipt or a refusal stands until Esc or the next action (dialog/DESIGN.md, the status row). Esc clears
    it and goes back a level in the same press (dialog/tests/host.rs), so the proof clears it by the next action
    that leaves the list where it is: the lit row's actions opened with F9 and left with Esc, which lights the
    row again and says nothing."""
    lines = s.screen()
    if not reply_stands(lines):
        return
    s.key("-k", "F9")
    after = s.screen()
    if not find_row(after, "new folder"):
        # nothing was lit: Down lights the first row, then F9 opens its actions
        s.key("-k", "Down")
        s.key("-k", "F9")
        after = s.screen()
    assert find_row(after, "new folder"), "F9 did not open the actions\n" + "\n".join(after)
    s.key("-k", "Escape")
    after = s.screen()
    assert after[0] == lines[0], "Esc from the actions did not come back: " + after[0]
    assert not reply_stands(after), "the status row still holds a receipt: " + status(after)


def deselect(s, side=0):
    """A selection a step left standing goes by `deselect all`, one click in the actions."""
    if not selected(s.screen()):
        return
    s.key("-k", "F9")
    until(lambda: find_row(s.screen(), "deselect all", side), "deselect all in the actions")
    click_row(s, "deselect all", side=side)
    until(lambda: not selected(s.screen()), "the selection gone")


def lit(lines, name):
    """The status row holds the lit row's line, its name first."""
    return re.match(r"\s*" + re.escape(name) + r"(?=\s|$)", status(lines)) is not None


def back_on(s, place, name):
    """The header names PLACE and the bar is on NAME."""
    lines = s.screen()
    return header_has(lines[0], place) and lit(lines, name)


def top(s):
    """The bar to the list's first row, a page at a time, until the status row stops moving."""
    before = None
    for _ in range(20):
        row = status(s.screen())
        if row == before:
            return
        before = row
        s.key("-k", "Prior")


def light(s, name):
    """Move the bar to the row named NAME by the keys alone, the status row the probe (the lit row's line moves
    with the bar): up a page at a time to the top, then down a row at a time."""
    clear_reply(s)
    lines = s.screen()
    assert not re.match(r"\s*\d+ selected\b", status(lines)), "the status row counts the selection, so it cannot say which row is lit"
    if lit(lines, name):
        return
    top(s)
    row = status(s.screen())
    for _ in range(80):
        if re.match(r"\s*" + re.escape(name) + r"(?=\s|$)", row):
            return
        s.key("-k", "Down")
        after = status(s.screen())
        if after == row:
            time.sleep(.3)   # a frame read before the dialog drew the press: once more
            after = status(s.screen())
        if after == row:
            break
        row = after
    raise AssertionError("no row named " + name + " from the top down\n" + s.text())


def open_folder(s, name, place):
    light(s, name)
    s.key("-k", "Return")
    until(lambda: header_has(s.screen()[0], place), "the folder " + place)


def select_two(s):
    """notes.md and todo.txt selected: Space on the one, the bar a row down, Space on the other."""
    light(s, "notes.md")
    s.key("-k", "space")
    s.key("-k", "space")
    until(lambda: counted(s.screen(), 2), "notes.md and todo.txt selected")
    lines = s.screen()
    for name in ("notes.md", "todo.txt"):
        assert any(re.match(r"\s*" + CHECK + r"\s+" + re.escape(name) + r"(?=\s)", row) for row in pane(lines, 0) or body(lines)), name + " wears the sign"


def click_at(s, row, col, double=False):
    rect = s.window()["rect"]
    # the window's first pixel is the first cell's: no air of foot's own (v0.124.5)
    s.pointer.click(rect["x"] + col * s.cell[0] + s.cell[0] // 2, rect["y"] + row * s.cell[1] + s.cell[1] // 2,
                    times=2 if double else 1)
    time.sleep(.4)


def click_row(s, label, double=False, side=None):
    """A click on the list row that reads LABEL: one click acts on a menu's row and selects an object's, a second
    within 400 ms acts on it (dialog/DESIGN.md). Scrolled into view by the keys where it is not on screen. SIDE keeps
    it to one pane: the other pane can hold the same words, and a click there would make it active."""
    lines = s.screen()
    hit = find_row(lines, label, side)
    if hit is None:
        for _ in range(20):
            before = body(lines)
            s.key("-k", "Prior")
            lines = s.screen()
            if body(lines) == before or find_row(lines, label, side):
                break
        for _ in range(80):
            lines = s.screen()
            hit = find_row(lines, label, side)
            if hit:
                break
            s.key("-k", "Down")
        else:
            raise AssertionError("no row " + label + "\n" + "\n".join(lines))
    row, col = hit
    click_at(s, row, col + len(label) // 2, double)


def shot(s, name):
    """A capture with no wait on the column's measure: the preview takes the whole window."""
    rect = s.window()["rect"]
    subprocess.run(["grim", "-o", "HEADLESS-1", str(s.evidence / (name + ".png"))], env=s.env, check=True)
    s.captures[name] = {**rect, "full_output": True}
    print("captured: " + name, flush=True)


def main(binary, destination):
    for tool in ("sway", "swaymsg", "swaybar", "foot", "grim", "wtype", "wl-copy", "wl-paste"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    os.environ["SPARK_SHELL_NO_UDISKS"] = "1"   # no drives group: the host's drives are not the proof's
    os.environ["EDITOR"] = EDITOR               # the stub on the fixture's PATH: Session takes its environment from here
    s = FilesSession(binary, destination)
    home = s.root
    both = ("~/documents", "~/pictures")
    documents, pictures = home / "documents", home / "pictures"

    def shows(*names):
        lines = s.screen()
        return all(row_named(lines, n) for n in names)

    def other_pane_shows(*names):
        lines = s.screen()
        return all(find_row(lines, n, 1) for n in names)

    def clipboard():
        return subprocess.run(["wl-paste", "--no-newline"], env=s.env, capture_output=True, text=True, timeout=5).stdout

    def stays(lines):
        """Nothing took the screen: no words in the prompt, no page, both panes where they were."""
        assert "search or ask" in lines[2], "no prompt text: " + lines[2]
        assert header_has(lines[0], "~/documents"), "no page: " + lines[0]
        assert paths(lines) == both, "both panes stay on screen\n" + "\n".join(lines)

    try:
        # 1. the home folder, in the four modes and the minimum window
        s.key("files", "-k", "Return")
        until(lambda: shows("documents", "pictures", "big"), "the home folder's rows")
        lines = s.screen()
        assert header_has(lines[0], "~"), lines[0]
        assert any(re.match(r"\s*this folder\b", l) for l in body(lines)), "the folder's own row\n" + "\n".join(body(lines))
        assert row_named(lines, "trash"), "the trash row\n" + "\n".join(body(lines))
        assert heading(body(lines), "home") and heading(body(lines), "recent"), "one pane keeps home and recent\n" + "\n".join(body(lines))
        s.four_modes("files")
        s.sway("[con_id=%d] resize set width 396 px height 416 px, move position center" % s.window()["id"])
        s.capture("files-minimum")
        s.key("-k", "Down")
        s.key("-k", "Right")
        until(lambda: "two panes need" in status(s.screen()), "the refusal below 60 cells: two panes need a window 60 cells wide")
        assert divider(s.screen()) is None, "no second pane below 60 cells"
        s.normal()
        s.checks.append("files from home draws the home folder: documents, pictures, big, the folder's own row this folder and trash, under "
                        "home and with recent; the header reads files . ~; the frame holds in compact, fullscreen, both snaps and the "
                        "minimum, where Right is refused: two panes need a window 60 cells wide")
        # 2. documents, the lit file's line on the status row, the whole key bar
        open_folder(s, "documents", "~/documents")
        until(lambda: shows("notes.md", "todo.txt", "draft.py"), "the documents rows")
        light(s, "notes.md")
        lines = s.screen()
        row = status(lines)
        assert all(w in row for w in ("notes.md", "Markdown", "~/documents")) and re.search(r"\b\d+ K?B\b", row), row
        bar_holds(lines, 2)
        words_at = next(l.index("notes.md") for l in body(lines) if row_pattern("notes.md").match(l))
        s.capture("files-status")
        s.checks.append("Down to notes.md: the status row holds its line, notes.md . Markdown . its size . the date . ~/documents; the key "
                        "bar stands on two lines at 60 cells: back Esc, nav, ren F2, view F3, open F4, copy F5, move F6, new F7, trash F8, actions F9")
        # 3. a selection: Space twice, the count, the sign, Esc clears
        s.key("-k", "space")
        s.key("-k", "space")
        until(lambda: counted(s.screen(), 2), "two rows counted on the status row")
        lines = s.screen()
        signed = [l for l in body(lines) if re.match(r"\s*" + CHECK + r"\s+(notes\.md|todo\.txt)(?=\s)", l)]
        assert len(signed) == 2, "notes.md and todo.txt wear the sign\n" + "\n".join(body(lines))
        assert all(l.index(n) > words_at for l in signed for n in ("notes.md", "todo.txt") if n in l), "the words stand right of the sign"
        s.capture("files-selected")
        s.key("-k", "Escape")
        until(lambda: re.match(r"\s*\S+\.(png|py|pdf|md|txt|wav)\b", status(s.screen())),
              "Esc clears the selection: a file's line back on the status row")
        lines = s.screen()
        assert not selected(lines), "no sign stands once no row is selected"
        assert header_has(lines[0], "~/documents"), "the first Esc goes no further than the selection: " + lines[0]
        s.checks.append("Space selects the lit row and moves the bar down: the status row reads 2 selected with the size, the rows' words "
                        "stand right of the sign; Esc with nothing typed clears the selection first and the lit file's line comes back")
        # 4. F9 in one pane: the page, each row with its key
        light(s, "notes.md")
        s.key("-k", "F9")
        until(lambda: find_row(s.screen(), "copy path"), "the actions page")
        lines = s.screen()
        assert header_has(lines[0], "notes.md"), lines[0]
        menu_holds(body(lines))
        assert not find_row(lines, "close pane"), "close pane stands only in two panes"
        assert re.search(r"\bback\s+Esc\b", keys(lines)) and "F5" not in keys(lines), "the menu's key bar: " + keys(lines)
        s.capture("files-actions")
        s.key("-k", "Escape")
        until(lambda: back_on(s, "~/documents", "notes.md"), "Esc back to the folder, notes.md lit")
        s.checks.append("F9 opens the actions named for the row, each with its key at the right: open Enter, open in app F4, view F3, rename F2, "
                        "copy F5, move F6, copy path Ctrl+C, trash F8, select Space, new folder F7, new file; no close pane in one pane; "
                        "the key bar back Esc alone")
        # 5. Right opens the second pane: the window as it was, the line, the short summary, the edges
        rect = s.window()["rect"]
        s.key("-k", "Right")
        until(lambda: paths(s.screen()) == ("~/documents", "~/documents"), "Right opens the second pane on the same folder")
        until(lambda: find_row(s.screen(), "notes.md", 1), "the second pane's rows")
        until(lambda: lit(s.screen(), ".."), "the bar lands in the second pane on its first row: the status row is ..'s line")
        assert s.window()["rect"] == rect, "the window does not resize for a pane: %r, %r" % (rect, s.window()["rect"])
        lines = s.screen()
        assert header_has(lines[0], "~/documents"), lines[0]
        even_panes(s, lines, 60)
        edge = divider(lines)
        assert all(len(l) > edge and l[edge] == LINE for l in body(lines) if l.strip()), "the line stands on every row of the panes\n" + "\n".join(body(lines))
        for side, end in ((0, edge - 2), (1, column_left(lines) + 60 - 2 - edge - 1)):
            rows = pane(lines, side)
            assert short_summary(rows), "the short summary at 30 cells\n" + "\n".join(rows)
            row = next(r for r in rows if row_pattern("notes.md").match(r))
            assert re.match(r"\s*notes\.md\s+" + SIZE + r"\s*$", row), "at 30 cells the size and no date: " + row
            assert len(row.rstrip()) == end, "the size at the pane's right edge, two cells of air: " + repr(row)
        s.capture("files-two-panes")
        opened = s.screen()
        s.key("-k", "Right")
        assert s.screen() == opened, "Right stays put at the right edge"
        s.key("-k", "Left")
        until(lambda: lit(s.screen(), "notes.md"), "Left goes to the left pane, its bar where it was")
        at_left = s.screen()
        bar_holds(at_left, 2)
        s.key("-k", "Left")
        assert s.screen() == at_left, "Left stays put at the left edge"
        s.key("-k", "F5")
        until(lambda: "the other pane shows this folder" in status(s.screen()), "F5 with both panes on one folder refuses")
        assert not (documents / "notes 2.md").exists(), "nothing copied"
        clear_reply(s)
        s.key("-k", "Right")
        until(lambda: s.screen() == opened, "Right goes back to the right pane")
        s.checks.append("Right opens the second pane on the same folder, the bar on its first row; the sway rect is unchanged; a line stands "
                        "between panes of 29 and 30, the size at each pane's right edge with two cells of air and no date, the summary "
                        "short; the key bar is the same; Right and Left stay put at the edges; F5 on one folder refuses")
        # 6. the other pane's own folder: .. from its first row, the home folder alone, the doors back, Left and Ctrl+Tab
        s.key("-k", "Return")   # the bar stood on the second pane's first row, ..: Enter opens the folder above there alone
        until(lambda: paths(s.screen()) == ("~/documents", "~"), "the bar on the second pane's first row: .. opens ~ there alone")
        until(lambda: find_row(s.screen(), "pictures", 1), "the home folder in the right pane")
        lines = s.screen()
        assert header_has(lines[0], "~"), lines[0]
        rows = pane(lines, 1)
        assert not heading(rows, "home") and not heading(rows, "recent"), "a pane shows the folder's own contents\n" + "\n".join(rows)
        assert short_summary(rows), "the short summary at 30 cells\n" + "\n".join(rows)
        assert find_row(lines, "notes.md", 0), "the left pane stays"
        s.capture("files-two-panes-home")
        open_folder(s, "pictures", "~/pictures")
        s.key("-k", "BackSpace")
        until(lambda: paths(s.screen()) == ("~/documents", "~"), "Backspace goes up in the active pane alone")
        open_folder(s, "pictures", "~/pictures")
        s.key("-k", "Escape")
        until(lambda: paths(s.screen()) == ("~/documents", "~"), "Esc goes up in the active pane alone")
        open_folder(s, "pictures", "~/pictures")
        until(lambda: paths(s.screen()) == both, "pictures in the right pane")
        s.key("-k", "Left")
        until(lambda: back_on(s, "~/documents", "notes.md"), "Left to the left pane")
        s.key("-M", "ctrl", "-k", "Tab", "-m", "ctrl")
        until(lambda: header_has(s.screen()[0], "~/pictures"), "Ctrl+Tab to the other pane")
        s.key("-M", "ctrl", "-k", "Tab", "-m", "ctrl")
        until(lambda: header_has(s.screen()[0], "~/documents"), "Ctrl+Tab back to the left pane")
        assert paths(s.screen()) == both, "each pane's path on its first row"
        s.capture("files-two-panes-folders")
        s.key("tod")
        until(lambda: find_row(s.screen(), "todo.txt", 0) and not find_row(s.screen(), "notes.md", 0), "typed words filter the active pane")
        assert find_row(s.screen(), "holiday.png", 1), "typing acts in the active pane alone"
        s.key("-k", "Escape")
        until(lambda: find_row(s.screen(), "notes.md", 0), "Esc clears the words")
        s.checks.append("Enter on the second pane's first row opens .. there alone: at home a pane has no home heading and no recent and keeps the "
                        "short summary; Backspace and Esc go up in the active pane alone; Left and Ctrl+Tab change the active pane, the header "
                        "naming its place; typed words filter the active pane alone")
        # 7. the four modes in two panes, and full screen: panes of 59 and 60, the dates, the one-line key bar
        light(s, "notes.md")
        s.four_modes("two-panes")
        s.key("-M", "logo", "-k", "f", "-m", "logo")
        time.sleep(1)
        s.settled()
        lines = s.screen()
        assert paths(lines) == both, "\n".join(lines)
        even_panes(s, lines, 120)
        bar_holds(lines, 1)
        for side, name in ((0, "notes.md"), (1, "holiday.png")):
            rows = pane(lines, side)
            assert whole_summary(rows), "at 60 cells the summary stays whole\n" + "\n".join(rows)
            row = next(r for r in rows if row_pattern(name).match(r))
            assert re.match(r"\s*" + re.escape(name) + r"\s+" + SIZE + r"\s+(today|yesterday)\s*$", row), "at 60 cells the date after the size: " + row
        s.normal()
        s.settled()
        s.checks.append("Two panes hold in compact, fullscreen and both snaps; Super+F gives panes of 59 and 60 with the date after the size, the "
                        "summary whole and the key bar on one line")
        # 8. F5 at once: no prompt text, no page, undo
        light(s, "letter.pdf")
        s.key("-k", "F5")
        until(lambda: says(s, "letter.pdf copied to ~/pictures"), "the copy's receipt with undo")
        stays(s.screen())
        assert (pictures / "letter.pdf").is_file(), "the copy on disk"
        until(lambda: other_pane_shows("letter.pdf"), "the other pane reads its folder again")
        s.capture("files-copy")
        s.click("undo")
        until(lambda: not (pictures / "letter.pdf").exists(), "the copy gone on undo")
        s.checks.append("F5 copies the lit file to the other pane's folder at once: no prompt text, no page, both panes on screen, undo on the "
                        "status row; the other pane reads again; undo takes it back")
        # 9. the name exists: inside the pane; Esc cancels, nothing said
        light(s, "notes.md")
        s.key("-k", "F5")
        until(lambda: header_has(s.screen()[0], "notes.md already exists"), "the name exists")
        lines = s.screen()
        for label in ("replace", "skip", "keep both"):
            assert find_row(lines, label, 0), "the choices lack " + label + "\n" + "\n".join(body(lines))
        assert not find_row(lines, "replace all") and not find_row(lines, "skip all"), "the all rows stand only while more remain"
        assert re.search(r"\bcancel\s+Esc\b", keys(lines)) and "save" not in keys(lines), keys(lines)
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~/documents"), "Esc cancels the operation")
        lines = s.screen()
        assert not reply_stands(lines), "Esc said it: nothing more is said: " + status(lines)
        assert not (pictures / "notes 2.md").exists() and (pictures / "notes.md").read_text().startswith("# Other notes"), "nothing copied"
        s.checks.append("F5 on a name the other folder holds stops on notes.md already exists, in the pane, replace, skip, keep both and the key "
                        "bar cancel Esc; Esc cancels and nothing is said")
        # 10. a selection's actions, deselect all
        select_two(s)
        s.key("-k", "F9")
        until(lambda: header_has(s.screen()[0], "2 selected"), "the selection's actions")
        lines = s.screen()
        for label in ("copy", "move", "copy path", "trash", "deselect all"):
            assert find_row(lines, label, 0), "the selection's page lacks " + label + "\n" + "\n".join(body(lines))
        assert paths(lines) == both, "the other pane stays"
        click_row(s, "deselect all", side=0)
        until(lambda: not selected(s.screen()) and header_has(s.screen()[0], "~/documents"), "deselect all")
        s.checks.append("F9 with 2 selected reads files . 2 selected, copy, move, copy path, trash and deselect all, in the pane; deselect all clears the selection")
        # 11. two selected, two names that exist: the five rows, the last with none of the all rows; the receipt, undo
        select_two(s)
        s.key("-k", "F5")
        until(lambda: header_has(s.screen()[0], "notes.md already exists"), "the first name that exists")
        lines = s.screen()
        order = [find_row(lines, label, 0) for label in ("replace", "replace all", "skip", "skip all", "keep both")]
        assert all(order) and [hit[0] for hit in order] == sorted(hit[0] for hit in order), "one list, in the spec's order\n" + "\n".join(body(lines))
        assert paths(lines) == both and find_row(lines, "holiday.png", 1), "the choices draw inside the active pane, the other in view\n" + "\n".join(lines)
        s.capture("files-conflict")
        click_row(s, "keep both", side=0)
        until(lambda: header_has(s.screen()[0], "todo.txt already exists"), "the second name that exists")
        lines = s.screen()
        assert find_row(lines, "keep both", 0) and not find_row(lines, "replace all") and not find_row(lines, "skip all"), "no more remain\n" + "\n".join(body(lines))
        click_row(s, "keep both", side=0)
        until(lambda: says(s, "2 files copied to ~/pictures"), "the copy's receipt with undo")
        assert (pictures / "notes 2.md").is_file() and (pictures / "todo 2.txt").is_file(), "the copies on disk"
        assert (pictures / "notes 2.md").read_text() == (documents / "notes.md").read_text()
        assert (pictures / "notes.md").read_text().startswith("# Other notes"), "the file there is kept"
        until(lambda: other_pane_shows("notes 2.md", "todo 2.txt"), "the other pane reads its folder again")
        assert not selected(s.screen()), "the selection clears once the operation ends"
        s.capture("files-receipt")
        s.click("undo")
        until(lambda: not (pictures / "notes 2.md").exists() and not (pictures / "todo 2.txt").exists(), "the copies gone on undo")
        until(lambda: "2 undone" in status(s.screen()), "the undo's receipt")
        s.capture("files-undo")
        s.checks.append("With 2 selected F5 stops on notes.md already exists inside the pane with replace, replace all, skip, skip all, keep both, the "
                        "other pane in view; keep both goes on to todo.txt already exists with no all rows; notes 2.md and todo 2.txt on disk, the "
                        "receipt 2 files copied to ~/pictures with undo, the other pane reads again; undo takes both back and says 2 undone")
        # 12. F6 and its undo
        light(s, "draft.py")
        s.key("-k", "space")
        until(lambda: counted(s.screen(), 1), "draft.py selected")
        s.key("-k", "F6")
        until(lambda: re.search(r"(1 file|draft\.py) moved to ~/pictures", status(s.screen())), "the move's receipt")
        stays(s.screen())
        assert (pictures / "draft.py").is_file() and not (documents / "draft.py").exists(), "the move on disk"
        until(lambda: other_pane_shows("draft.py"), "the other pane shows the moved file")
        s.click("undo")
        until(lambda: (documents / "draft.py").is_file() and not (pictures / "draft.py").exists(), "the move undone on disk")
        s.checks.append("F6 moves the selected file at once, the receipt says so, the panes stay, the other pane shows it, undo brings it back")
        # 13. F2, a form in the prompt with both panes on screen, and its undo
        light(s, "todo.txt")
        s.key("-k", "F2")
        until(lambda: "todo.txt" in s.screen()[2], "the prompt prefilled with the name")
        lines = s.screen()
        assert header_has(lines[0], "rename"), lines[0]
        assert paths(lines) == both, "a form keeps both panes on screen\n" + "\n".join(lines)
        bar = keys(lines)
        assert re.search(r"\bcancel\s+Esc\b", bar) and re.search(r"\bsave\s+Enter\b", bar), bar
        s.capture("files-rename")
        s.key("later.txt", "-k", "Return")   # the name stands lit: the first letter replaces it
        until(lambda: (documents / "later.txt").is_file() and find_row(s.screen(), "later.txt", 0), "the row and the file renamed")
        assert not (documents / "todo.txt").exists()
        assert "renamed" in status(s.screen()), status(s.screen())
        s.click("undo")
        until(lambda: (documents / "todo.txt").is_file() and not (documents / "later.txt").exists(), "the rename undone")
        s.checks.append("F2 opens the form in the prompt with the name as it is, files . rename in the header, both panes on screen and the key bar "
                        "cancel Esc, save Enter; Enter renames the file and the row, the receipt says renamed, undo names it back")
        # 14. F7, a new folder
        s.key("-k", "F7")
        until(lambda: "folder name" in s.screen()[2], "the form's placeholder")
        lines = s.screen()
        assert header_has(lines[0], "new folder"), lines[0]
        assert paths(lines) == both, "a form keeps both panes on screen\n" + "\n".join(lines)
        s.key("drafts", "-k", "Return")
        until(lambda: (documents / "drafts").is_dir(), "the folder on disk")
        until(lambda: any(re.match(r"\s*drafts\s{2,}.*\b(0 items|empty)\b", r) for r in pane(s.screen(), 0)), "the row drafts, empty")
        s.capture("files-new-folder")
        s.checks.append("F7 asks folder name in the prompt, files . new folder in the header; Enter makes drafts on disk and its row reads empty")
        # 15. F8 and its undo
        trash = home / "data/Trash/files"
        before = len([p for p in trash.iterdir() if p.name.startswith("todo")]) if trash.is_dir() else 0
        light(s, "todo.txt")
        s.key("-k", "F8")
        until(lambda: says(s, "todo.txt is in the trash"), "the trash receipt with undo")
        stays(s.screen())
        assert not (documents / "todo.txt").exists(), "the file left documents"
        assert len([p for p in trash.iterdir() if p.name.startswith("todo")]) == before + 1, "the file under the fixture's XDG_DATA_HOME Trash/files"
        s.click("undo")
        until(lambda: (documents / "todo.txt").is_file(), "the file back from the trash")
        s.checks.append("F8 puts the file in the fixture's own Trash/files at once and says is in the trash with undo; undo brings it back")
        # 16. F9 in two panes: inside the active pane, the other on screen, the rows still act on one click
        light(s, "letter.pdf")
        s.key("-k", "F9")
        until(lambda: find_row(s.screen(), "close pane", 0), "the actions in the left pane")
        lines = s.screen()
        assert header_has(lines[0], "letter.pdf"), lines[0]
        menu_holds(pane(lines, 0))
        assert paths(lines) == both and find_row(lines, "holiday.png", 1), "the other pane stays\n" + "\n".join(lines)
        assert re.search(r"\bback\s+Esc\b", keys(lines)) and "F5" not in keys(lines), "the menu's key bar: " + keys(lines)
        s.capture("files-actions-pane")
        click_row(s, "copy", side=0)
        until(lambda: says(s, "letter.pdf copied to ~/pictures"), "the row acts on one click")
        s.click("undo")
        until(lambda: not (pictures / "letter.pdf").exists(), "the copy gone on undo")
        clear_reply(s)
        s.key("-k", "Right")
        until(lambda: header_has(s.screen()[0], "~/pictures"), "Right to the right pane")
        light(s, "holiday.png")
        s.key("-k", "F9")
        until(lambda: find_row(s.screen(), "close pane", 1), "the actions in the right pane")
        lines = s.screen()
        menu_holds(pane(lines, 1))
        assert paths(lines) == both and find_row(lines, "notes.md", 0), "the left pane stays\n" + "\n".join(lines)
        s.key("-k", "Escape")
        until(lambda: back_on(s, "~/pictures", "holiday.png"), "back to the right pane's list")
        s.key("-k", "Left")
        until(lambda: header_has(s.screen()[0], "~/documents"), "Left to the left pane")
        s.checks.append("F9 in two panes draws the actions inside the active pane, left or right, under its path, each row with its key at the right (copy F5, "
                        "copy path Ctrl+C), close pane among them, the other pane's path and rows on screen; a row acts on one click")
        # 17. Ctrl+C: the lit row's path, then two selected paths one a line
        notes, todo = (str((documents / name).resolve()) for name in ("notes.md", "todo.txt"))
        light(s, "notes.md")
        s.key("-M", "ctrl", "-k", "c", "-m", "ctrl")
        until(lambda: "path copied" in status(s.screen()), "the receipt path copied")
        until(lambda: clipboard() == notes, "wl-paste reads the path back")
        select_two(s)
        s.key("-M", "ctrl", "-k", "c", "-m", "ctrl")
        until(lambda: "2 paths copied" in status(s.screen()), "the receipt 2 paths copied")
        until(lambda: clipboard().splitlines() == [notes, todo], "wl-paste reads two paths, one a line")
        deselect(s)
        s.checks.append("Ctrl+C copies the lit row's path, wl-paste reads it back and the receipt reads path copied; with two selected, 2 paths copied, one a line")
        # 18. the view: text, picture, PDF, sound; Esc back to the panes as they were
        light(s, "notes.md")
        s.key("-k", "F3")
        until(lambda: "Proof notes" in s.text(), "the text view")
        assert view_header(s.screen()[0], "~/documents"), s.screen()[0]
        shot(s, "view-text")
        s.key("-k", "Escape")
        until(lambda: back_on(s, "~/documents", "notes.md"), "back to the panes with notes.md lit")
        assert paths(s.screen()) == both, "the two panes stand as they were"
        light(s, "cover.png")
        s.key("-k", "F3")
        until(lambda: re.search(r"\b20\s*\S\s*40\b", s.text()), "the picture's size on the facts row")
        shot(s, "view-picture")
        s.key("-k", "Escape")
        until(lambda: back_on(s, "~/documents", "cover.png"), "back from the picture")
        light(s, "letter.pdf")
        s.key("-k", "F3")
        if shutil.which("pdftoppm"):
            # one page: the page drawn as a picture, its zoom on the facts row and the zoom keys on the bar; a count
            # of pages stands there only where there are several
            until(lambda: re.search(r"\b\d+%", s.text()) and re.search(r"\bzoom\b", keys(s.screen())), "the PDF's page")
            s.checks.append("The PDF views as its page drawn: the zoom on the facts row and zoom among the keys")
        else:
            until(lambda: "cannot view: pdftoppm (poppler) is not installed" in s.text(), "the PDF's refusal")
            s.checks.append("No poppler on this machine: the PDF says cannot view: pdftoppm (poppler) is not installed; its page is not proved here")
        s.key("-k", "Escape")
        until(lambda: back_on(s, "~/documents", "letter.pdf"), "back from the PDF")
        light(s, "voice.wav")
        s.key("-k", "F3")
        if shutil.which("mpv"):
            until(lambda: re.search(r"\bplay\b", keys(s.screen())), "the sound's keys")
            s.checks.append("The sound views with the sound's keys, play on Space; nothing is played")
        else:
            until(lambda: "cannot view: mpv is not installed" in s.text(), "the sound's refusal")
            s.checks.append("No mpv on this machine: the sound says cannot view: mpv is not installed; the play is not proved here")
        s.key("-k", "Escape")
        until(lambda: back_on(s, "~/documents", "voice.wav"), "back from the sound")
        s.checks.append("F3 views the lit file in the whole window, the header view . ~/documents: the Markdown's first line, the picture's 20 x 40 on the "
                        "facts row; Esc comes back to the two panes as they were with the file lit")
        # 19. close pane, Ctrl+Tab opening the second where there is none, and one pane again
        s.key("-k", "F9")
        until(lambda: find_row(s.screen(), "close pane", 0), "close pane in the actions")
        rect = s.window()["rect"]
        click_row(s, "close pane", side=0)
        until(lambda: divider(s.screen()) is None and header_has(s.screen()[0], "~/documents"), "one pane")
        lines = s.screen()
        assert s.window()["rect"] == rect, "the window does not resize for a pane"
        assert not any("~/pictures" in l for l in body(lines)), "the second pane is gone"
        s.key("-M", "ctrl", "-k", "Tab", "-m", "ctrl")
        until(lambda: paths(s.screen()) == ("~/documents", "~/documents"), "Ctrl+Tab opens the second pane where there is none")
        s.key("-k", "F9")
        until(lambda: find_row(s.screen(), "close pane", 1), "close pane in the second pane's actions")
        click_row(s, "close pane", side=1)
        until(lambda: divider(s.screen()) is None, "one pane again")
        s.checks.append("close pane closes the second pane with the window as it was; Ctrl+Tab opens the second where there is none")
        # 20. one pane: Left does nothing, F5 picks the folder
        light(s, "letter.pdf")
        before = s.screen()
        s.key("-k", "Left")
        assert s.screen() == before, "Left does nothing in one pane"
        s.key("-k", "F5")
        until(lambda: find_row(s.screen(), "copy letter.pdf here"), "the row that lands the copy here")
        click_row(s, "..", double=True)
        until(lambda: header_has(s.screen()[0], "~"), "the pick opens the folder above")
        click_row(s, "pictures", double=True)
        until(lambda: header_has(s.screen()[0], "~/pictures"), "the pick opens pictures")
        s.key("-k", "Down")   # a folder opened by the pointer lights nothing: an arrow does
        top(s)   # the bar on the row that lands it here, the list's first
        s.key("-k", "Return")
        until(lambda: says(s, "letter.pdf copied to ~/pictures"), "the copy landed here, the receipt with undo")
        assert (pictures / "letter.pdf").is_file(), "the copy on disk"
        s.click("undo")
        until(lambda: not (pictures / "letter.pdf").exists(), "the copy gone on undo")
        until(lambda: header_has(s.screen()[0], "~/pictures"), "the list stays where the pick landed")
        s.checks.append("In one pane Left does nothing and F5 picks the folder: open folders until the right one, Enter on copy letter.pdf here; undo takes it back")
        # 21. the large folder: a bounded wait for its first page, End to its last row; one pane keeps home and recent
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~/documents"), "Esc goes back where the pick began")
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~") and heading(body(s.screen()), "home"), "Esc to ~, the home heading back in one pane")
        assert heading(body(s.screen()), "recent"), "one pane keeps recent\n" + "\n".join(body(s.screen()))
        light(s, "big")
        started = time.monotonic()
        s.key("-k", "Return")
        s.key("-k", "Down")   # a key while the folder is read: the dialog answers it, nothing hangs
        until(lambda: row_named(s.screen(), "f00000.txt"), "the big folder's first row", 30)
        first = time.monotonic() - started
        # the Down above may have come before the rows: once they are drawn, Down lights a row of the folder, so End
        # is the list's and goes to its last row
        s.key("-k", "Down")
        until(lambda: re.search(r"~/big\s*$", status(s.screen())), "the bar on a row of the big folder", 10)
        s.key("-k", "End")
        until(lambda: any("the next page" in l for l in body(s.screen())), "the last row, the next page", 30)
        last = time.monotonic() - started
        lines = s.screen()
        assert any("the next page" in l and "more" in l for l in body(lines)), "the next page says how many more\n" + "\n".join(body(lines))
        s.timings.update({"big_first_row_seconds": round(first, 3), "big_next_page_row_seconds": round(last, 3)})
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~"), "Esc back from the big folder")
        s.checks.append("A folder of %d files lists its first page in %.1f s and End reaches the next page row, with how many more, in %.1f s; "
                        "a key pressed meanwhile is answered" % (BIG, first, last))
        # 22. the doors back, and the typed filter; with words typed Left and Right are the prompt's
        open_folder(s, "documents", "~/documents")
        s.key("-k", "BackSpace")
        until(lambda: header_has(s.screen()[0], "~"), "Backspace goes up")
        open_folder(s, "documents", "~/documents")
        lines = s.screen()
        click_at(s, 0, lines[0].index("back") + 2)
        until(lambda: header_has(s.screen()[0], "~"), "the header's back goes up")
        open_folder(s, "documents", "~/documents")
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~"), "Esc goes up")
        open_folder(s, "documents", "~/documents")
        s.key("tod")
        until(lambda: shows("todo.txt") and not shows("notes.md"), "typed words filter the folder to todo.txt")
        s.key("-k", "Left", "-k", "Left", "-k", "Right")
        s.key("x")
        until(lambda: "toxd" in s.screen()[2], "with words typed Left and Right move the cursor in the prompt")
        assert divider(s.screen()) is None, "with words typed Right opens no pane"
        s.key("-k", "Escape")
        until(lambda: shows("todo.txt", "notes.md"), "Esc clears the words and both rows are back")
        s.checks.append("With nothing typed Esc, Backspace and the header's back go up a level; typed words filter the folder, Left and Right move the "
                        "cursor in the prompt and open no pane, and Esc clears them")
        # 23. F4, last: an opener's path closes the dialog (spark-shell files_opened, #117). The proof's own assignments
        # decide which way it goes, never the machine's, through a stub xdg-mime put here so the steps before read the
        # real one: a windowed app goes through the stub xdg-open, a terminal app through its Exec in a terminal, and
        # Enter on a text file is the editor, the text application's Exec (the provider's environment holds no EDITOR)
        opener, editor = home / ".xdg-open.log", home / ".editor.log"
        apps = home / "data/applications"
        apps.mkdir(parents=True, exist_ok=True)
        for name, terminal in (("proof-window", "false"), ("proof-terminal", "true")):
            (apps / (name + ".desktop")).write_text("[Desktop Entry]\nType=Application\nName=%s\nExec=%s %%f\nTerminal=%s\n"
                                                    "MimeType=text/plain;\n" % (name, EDITOR, terminal))
        mime = home / "bin/xdg-mime"
        mime.write_text('#!/bin/sh\ncase "$1 $2" in\n"query filetype") echo text/plain ;;\n'
                        '"query default") [ "$3" != text/plain ] || cat "$HOME/.assigned" ;;\nesac\n')
        mime.chmod(0o700)

        def assign(name):
            (home / ".assigned").write_text(name + ".desktop\n")

        def documents_again():
            """Back in ~/documents on todo.txt: an opener's path closed the dialog; a stub that exits at once may not."""
            time.sleep(2)
            if s.window() is None:
                s.key("-M", "logo", "-k", "space", "-m", "logo")
                until(s.window, "the dialog again")
                time.sleep(2)
                s.key("files", "-k", "Return")
                until(lambda: shows("documents"), "the home folder again")
                open_folder(s, "documents", "~/documents")
            light(s, "todo.txt")

        assign("proof-window")
        light(s, "todo.txt")
        s.key("-k", "F4")
        until(lambda: logged(opener) == [todo], "xdg-open handed the text file's path")
        until(lambda: s.window() is None, "the dialog closes once the opener took the path")
        assert not logged(editor), "F4 is the app the system assigns, never the editor: " + repr(logged(editor))
        assign("proof-terminal")
        documents_again()
        s.key("-k", "F4")
        until(lambda: logged(editor) == [todo], "F4 gives an app that runs in a terminal a terminal")
        assert logged(opener) == [todo], "xdg-open starts a terminal app with no terminal: " + repr(logged(opener))
        documents_again()
        s.key("-k", "Return")
        until(lambda: logged(editor) == [todo, todo], "Enter opens the text file in the editor")
        assert logged(opener) == [todo], "Enter is not the system's opener: " + repr(logged(opener))
        s.checks.append("F4 hands a text file to the stub xdg-open, its path as the argument, and the editor is not run; assigned to an app that runs in "
                        "a terminal, F4 gives it a terminal, through the editor's path, not xdg-open; Enter on the same file runs the editor, not xdg-open")
        manifest = {"binary_sha256": s.binary_sha256,
                    "palette": s.palette,
                    "environment": "Void Linux; native headless Sway, foot; 1440x1000",
                    "data": "A fixture home of the proof's own: documents (Markdown, text, Python, a 20x40 PNG, a one-page PDF, a second "
                            "of silence), pictures (a PNG and a notes.md and a todo.txt a copy runs into), big (10,000 files), an empty "
                            "folder; the real files provider; a stub xdg-open and a stub editor; no drives",
                    "tools": {"pdftoppm": bool(shutil.which("pdftoppm")), "mpv": bool(shutil.which("mpv"))},
                    "usable_area": s.area, "captures": s.captures, "checks": s.checks, "timings": s.timings}
        (s.evidence / "native.json").write_text(json.dumps(manifest, indent=2) + "\n")
        for check in s.checks:
            print("ok: " + check)
    except Exception:
        try:
            (s.evidence / "failure.txt").write_text(s.text())
            print("failure window", s.window()["rect"], "foot pid", s.window()["pid"], flush=True)
            shutil.copyfile(s.log.name, s.evidence / "failure-native.log")
            subprocess.run(["grim", "-o", "HEADLESS-1", str(s.evidence / "failure.png")], env=s.env, check=True)
        except Exception:
            pass
        raise
    finally:
        s.close()


if __name__ == "__main__":
    main(*sys.argv[1:])
