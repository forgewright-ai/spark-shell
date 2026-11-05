#!/usr/bin/env python3
"""Files in native Sway/foot on an isolated desktop, against the real provider on a fixture home.

python3 tests/files_desktop_proof.py BINARY EVIDENCE_DIRECTORY
The fixture HOME holds the proof's own files alone, written before the dialog starts: documents (a Markdown
note, a text, a Python draft, a 20 by 40 PNG, a one-page PDF, a second of silence), pictures (a PNG and a
notes.md a copy runs into), big (10,000 small files) and an empty folder. Every label looked for is the
spec's, dialog/DESIGN.md "Files", lowercase; the header and the status row are matched loosely around the
separator glyph. A tool the machine lacks (poppler, mpv) is said in a check, never failed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time
import wave
import zlib

import apps_desktop_proof
from apps_desktop_proof import Session

CHECK = "\u2713"   # the check sign before a checked row's words (dialog/src/ui.rs CHECK)
BIG = 10000        # the files of the large folder, ten pages of a thousand


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
    documents' names sort so notes.md and todo.txt are neighbours: Insert on the one lands the bar on the other."""
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
    folder = root / "big"
    folder.mkdir()
    started = time.monotonic()
    for n in range(big):
        (folder / ("f%05d.txt" % n)).write_text("line %d\n" % n)
    took = time.monotonic() - started
    (root / "empty").mkdir()
    return {"big_files": big, "big_write_seconds": round(took, 3)}


class FilesSession(Session):
    """Apps' Session with the files tree in its HOME before the dialog starts. The Session makes its HOME and
    starts sway in one step; the one call between the two that takes the HOME is the palette's read, so the
    tree is written on the way through it."""

    def __init__(self, binary, destination):
        self.timings = {}
        original = apps_desktop_proof.native_foot_config

        def with_tree(root):
            self.timings.update(build_tree(root))
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
    `files . 2 checked`, `files . notes.md is in ~/pictures already`; `~` alone is not `~/documents`."""
    return re.search(r"\bfiles\s*[^\w\s~<]\s*" + re.escape(place) + r"(?=\s|$)", line) is not None


def row_pattern(label):
    return re.compile(r"^(\s*(?:" + CHECK + r"\s+)?)" + re.escape(label) + r"(?=\s{2,}|\s*$)")


def find_row(lines, label):
    """The first list row whose words are LABEL (a check sign allowed before them) and the column the words start
    at. Anchored at the row's left: in two panes it is the left pane's row, or a row that spans the column."""
    pattern = row_pattern(label)
    for i in range(8, bottom_rule(lines) - 1):
        m = pattern.match(lines[i])
        if m:
            return i, len(m.group(1))
    return None


def row_named(lines, name):
    return find_row(lines, name) is not None


def reply_stands(lines):
    """A receipt or a refusal on the status row: its mark two cells into the column, or undo at its right; the
    lit row's line starts at the fourth cell with no mark."""
    row, left = status(lines), column_left(lines)
    return bool(row[left + 2:left + 3].strip()) or re.search(r"\bundo\s*$", row) is not None


def clear_reply(s):
    """A receipt or a refusal stands until Esc or the next action (dialog/DESIGN.md, the status row). Esc clears
    it and goes back a level in the same press (dialog/tests/host.rs), so the proof clears it by the next action
    that leaves the list where it is: the lit row's actions opened with Right and left with Esc, which lights the
    row again and says nothing."""
    lines = s.screen()
    if not reply_stands(lines):
        return
    s.key("-k", "Right")
    after = s.screen()
    if after[0] == lines[0]:
        # nothing was lit: Down lights the first row, then Right opens its actions
        s.key("-k", "Down")
        s.key("-k", "Right")
        after = s.screen()
    assert after[0] != lines[0], "Right did not open the actions: " + after[0]
    s.key("-k", "Escape")
    after = s.screen()
    assert after[0] == lines[0], "Esc from the actions did not come back: " + after[0]
    assert not reply_stands(after), "the status row still holds a receipt: " + status(after)


def lit(lines, name):
    """The status row holds the lit row's line, its name first."""
    return re.match(r"\s*" + re.escape(name) + r"(?=\s|$)", status(lines)) is not None


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
    assert not re.match(r"\s*\d+ checked\b", status(lines)), "the status row counts checks, so it cannot say which row is lit"
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


def click_at(s, row, col, double=False):
    rect = s.window()["rect"]
    s.pointer.click(rect["x"] + 18 + col * s.cell[0] + s.cell[0] // 2, rect["y"] + 18 + row * s.cell[1] + s.cell[1] // 2,
                    times=2 if double else 1)
    time.sleep(.4)


def click_row(s, label, double=False):
    """A click on the list row that reads LABEL: one click acts on a menu's row and selects an object's, a second
    within 400 ms acts on it (dialog/DESIGN.md). Scrolled into view by the keys where it is not on screen."""
    lines = s.screen()
    hit = find_row(lines, label)
    if hit is None:
        for _ in range(20):
            before = body(lines)
            s.key("-k", "Prior")
            lines = s.screen()
            if body(lines) == before or find_row(lines, label):
                break
        for _ in range(80):
            lines = s.screen()
            hit = find_row(lines, label)
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
    for tool in ("sway", "swaymsg", "swaybar", "foot", "grim", "wtype"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    os.environ["SPARK_SHELL_NO_UDISKS"] = "1"   # no drives group: the host's drives are not the proof's
    s = FilesSession(binary, destination)
    home = s.root

    def shows(*names):
        lines = s.screen()
        return all(row_named(lines, n) for n in names)

    def other_pane_shows(*names):
        # the right pane's rows start at its path's column on the panes' first row
        lines = s.screen()
        right = next((l.index("~/pictures") for l in body(lines) if "~/pictures" in l), None)
        return right is not None and all(any(l.find(n, right) >= 0 for l in body(lines)) for n in names)

    try:
        # 1. the home folder, in the four modes and the minimum window
        s.key("files", "-k", "Return")
        until(lambda: shows("documents", "pictures", "big"), "the home folder's rows")
        lines = s.screen()
        assert header_has(lines[0], "~"), lines[0]
        assert any(re.match(r"\s*this folder\b", l) for l in body(lines)), "the folder's own row\n" + "\n".join(body(lines))
        assert row_named(lines, "trash"), "the trash row\n" + "\n".join(body(lines))
        s.four_modes("files")
        s.sway("[con_id=%d] resize set width 396 px height 416 px, move position center" % s.window()["id"])
        s.capture("files-minimum")
        s.normal()
        s.checks.append("files from home draws the home folder: documents, pictures, big, the folder's own row this folder and trash; "
                        "the header reads files . ~; the frame holds in compact, fullscreen, both snaps and the 36x20 minimum")
        # 2. documents, the lit file's line on the status row
        open_folder(s, "documents", "~/documents")
        until(lambda: shows("notes.md", "todo.txt", "draft.py"), "the documents rows")
        light(s, "notes.md")
        lines = s.screen()
        row = status(lines)
        assert all(w in row for w in ("notes.md", "Markdown", "~/documents")) and re.search(r"\b\d+ K?B\b", row), row
        assert re.search(r"\bactions\b", keys(lines)) and re.search(r"\bpreview\b", keys(lines)) and "Esc" in keys(lines), keys(lines)
        words_at = next(l.index("notes.md") for l in body(lines) if row_pattern("notes.md").match(l))
        s.capture("files-status")
        s.checks.append("Down to notes.md: the status row holds its line, notes.md . Markdown . its size . the date . ~/documents; "
                        "the key bar reads back  Esc   actions  ->   preview  Space")
        # 3. a check: Insert twice, the count, the sign, Esc clears
        s.key("-k", "Insert")
        s.key("-k", "Insert")
        until(lambda: re.match(r"\s*2 checked\b", status(s.screen())), "two checks counted on the status row")
        lines = s.screen()
        signed = [l for l in body(lines) if re.match(r"\s*" + CHECK + r"\s+(notes\.md|todo\.txt)(?=\s)", l)]
        assert len(signed) == 2, "notes.md and todo.txt carry the check sign\n" + "\n".join(body(lines))
        assert all(l.index(n) > words_at for l in signed for n in ("notes.md", "todo.txt") if n in l), "the words stand right of the sign"
        s.capture("files-checked")
        s.key("-k", "Escape")
        until(lambda: re.match(r"\s*\S+\.(png|py|pdf|md|txt|wav)\b", status(s.screen())),
              "Esc clears the checks: a file's line back on the status row")
        assert not any(CHECK in l for l in body(s.screen())), "no sign stands once no row is checked"
        light(s, "notes.md")
        s.key("-k", "Insert")
        until(lambda: re.match(r"\s*1 checked\b", status(s.screen())), "notes.md checked again")
        s.checks.append("Insert checks the lit row and moves the bar down: the status row reads 2 checked with the size, the rows' words "
                        "stand right of the check sign; Esc with nothing typed clears the checks first and the lit file's line comes back")
        # 4. the actions page, then two panes
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "two panes"), "the actions page")
        lines = s.screen()
        assert header_has(lines[0], "1 checked") or header_has(lines[0], "notes.md"), lines[0]
        for label in ("copy to a folder", "trash", "new folder", "two panes"):
            assert find_row(lines, label), "the actions page lacks " + label + "\n" + "\n".join(body(lines))
        assert any(re.match(r"\s*this folder\s*$", l) for l in body(lines)), "the folder's actions under their heading"
        s.capture("files-actions")
        click_row(s, "two panes")
        until(lambda: any(l.count("~/documents") >= 2 for l in body(s.screen())), "two panes on the same folder")
        bar = keys(s.screen())
        assert re.search(r"\bpane\b", bar) and "Ctrl+Tab" in bar, "the key bar adds pane  Ctrl+Tab: " + bar
        s.capture("files-two-panes")
        s.four_modes("two-panes")
        s.checks.append("Right opens the actions page named for the row: copy to a folder, trash, then this folder with new folder and two "
                        "panes; two panes shows the folder twice with each pane's path on its first row and pane  Ctrl+Tab on the key bar, "
                        "in compact, fullscreen and both snaps")
        # 5. the other pane: Ctrl+Tab, up through .., into pictures, and back
        s.key("-M", "ctrl", "-k", "Tab", "-m", "ctrl")
        time.sleep(.5)
        assert header_has(s.screen()[0], "~/documents"), "the other pane shows the same folder: " + s.screen()[0]
        top(s)   # the bar on .., the first row of a subfolder
        s.key("-k", "Return")
        until(lambda: header_has(s.screen()[0], "~"), "the right pane at ~ through ..")
        open_folder(s, "pictures", "~/pictures")
        s.key("-M", "ctrl", "-k", "Tab", "-m", "ctrl")
        until(lambda: header_has(s.screen()[0], "~/documents"), "Ctrl+Tab back to the left pane")
        assert any("~/documents" in l and "~/pictures" in l for l in body(s.screen())), "each pane's path on its first row"
        s.capture("files-two-panes-folders")
        s.checks.append("Ctrl+Tab makes the other pane active: the header names its place, .. opens the folder above there and pictures opens "
                        "in it alone, Ctrl+Tab comes back to ~/documents with both paths on the panes' first row")
        # 6. two checked files copied to the other pane: the conflict page, the receipt, undo
        assert re.match(r"\s*1 checked\b", status(s.screen())), "the left pane keeps its check through the pane switch: " + status(s.screen())
        s.key("-k", "Escape")
        until(lambda: not re.match(r"\s*\d+ checked\b", status(s.screen())), "the checks cleared")
        light(s, "notes.md")
        s.key("-k", "Insert")
        s.key("-k", "Insert")   # the bar moved to todo.txt, the next row by name
        until(lambda: re.match(r"\s*2 checked\b", status(s.screen())), "notes.md and todo.txt checked")
        lines = s.screen()
        for name in ("notes.md", "todo.txt"):
            assert any(re.match(r"\s*" + CHECK + r"\s+" + re.escape(name) + r"(?=\s)", l) for l in body(lines)), name + " carries the sign"
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "copy to ~/pictures"), "the checked set's actions")
        lines = s.screen()
        assert header_has(lines[0], "2 checked"), lines[0]
        for label in ("copy to ~/pictures", "move to ~/pictures", "trash", "uncheck all"):
            assert find_row(lines, label), "the checked set's page lacks " + label + "\n" + "\n".join(body(lines))
        click_row(s, "copy to ~/pictures")
        until(lambda: header_has(s.screen()[0], "notes.md is in ~/pictures already"), "the conflict page")
        lines = s.screen()
        for label in ("skip", "keep both", "replace"):
            assert find_row(lines, label), "the conflict page lacks " + label + "\n" + "\n".join(body(lines))
        s.capture("files-conflict")
        click_row(s, "keep both")
        until(lambda: "2 copied to ~/pictures" in status(s.screen()) and re.search(r"\bundo\s*$", status(s.screen())), "the copy's receipt with undo")
        assert (home / "pictures/notes 2.md").is_file() and (home / "pictures/todo.txt").is_file(), "the copies on disk"
        assert (home / "pictures/notes 2.md").read_text() == (home / "documents/notes.md").read_text()
        assert (home / "pictures/notes.md").read_text().startswith("# Other notes"), "the file there is kept"
        until(lambda: other_pane_shows("notes 2.md", "todo.txt"), "the other pane reads its folder again")
        s.capture("files-receipt")
        s.click("undo")
        until(lambda: not (home / "pictures/notes 2.md").exists() and not (home / "pictures/todo.txt").exists(), "the copies gone on undo")
        until(lambda: "put back" in status(s.screen()), "the undo's receipt")
        s.capture("files-undo")
        s.checks.append("With 2 checked the actions read copy to ~/pictures, move to ~/pictures, trash and uncheck all; the copy stops on the "
                        "conflict page notes.md is in ~/pictures already with skip, keep both and replace; keep both writes notes 2.md and "
                        "todo.txt, the receipt reads 2 copied to ~/pictures with undo, the other pane reads again, undo takes both back "
                        "and says put back")
        # 7. a move and its undo
        light(s, "draft.py")
        s.key("-k", "Insert")
        until(lambda: re.match(r"\s*1 checked\b", status(s.screen())), "draft.py checked")
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "move to ~/pictures"), "the actions")
        click_row(s, "move to ~/pictures")
        until(lambda: re.search(r"1 moved|draft\.py moved to ~/pictures", status(s.screen())), "the move's receipt")
        assert (home / "pictures/draft.py").is_file() and not (home / "documents/draft.py").exists(), "the move on disk"
        until(lambda: other_pane_shows("draft.py"), "the other pane shows the moved file")
        s.click("undo")
        until(lambda: (home / "documents/draft.py").is_file() and not (home / "pictures/draft.py").exists(), "the move undone on disk")
        s.checks.append("move to ~/pictures moves the checked file, the receipt says so, the other pane shows it, undo brings it back")
        # 8. rename in the prompt, and its undo
        light(s, "todo.txt")
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "rename"), "the actions")
        click_row(s, "rename")
        until(lambda: "todo.txt" in s.screen()[2], "the prompt prefilled with the name")
        bar = keys(s.screen())
        assert re.search(r"\bsave\b", bar) and "Enter" in bar and re.search(r"\blet go\b", bar) and "Esc" in bar, bar
        s.key("-k", "End")
        s.key(*[arg for _ in range(8) for arg in ("-k", "BackSpace")])
        s.key("later.txt", "-k", "Return")
        until(lambda: (home / "documents/later.txt").is_file() and row_named(s.screen(), "later.txt"), "the row and the file renamed")
        assert not (home / "documents/todo.txt").exists()
        assert "renamed" in status(s.screen()), status(s.screen())
        s.click("undo")
        until(lambda: (home / "documents/todo.txt").is_file() and not (home / "documents/later.txt").exists(), "the rename undone")
        s.checks.append("rename opens the prompt with the name as it is and the key bar let go  Esc   save  Enter; Enter renames the file "
                        "and the row, the receipt says renamed, undo names it back")
        # 9. a new folder
        clear_reply(s)
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "new folder"), "the actions")
        click_row(s, "new folder")
        until(lambda: "a name for the folder" in s.screen()[2], "the form's placeholder")
        s.key("drafts", "-k", "Return")
        until(lambda: (home / "documents/drafts").is_dir(), "the folder on disk")
        until(lambda: any(re.match(r"\s*drafts\s{2,}.*\b(0 items|empty)\b", l) for l in body(s.screen())), "the row drafts, empty")
        s.capture("files-new-folder")
        s.checks.append("new folder asks a name for the folder in the prompt; Enter makes drafts on disk and its row reads empty")
        # 10. trash and its undo
        trash = home / "data/Trash/files"
        before = len([p for p in trash.iterdir() if p.name.startswith("todo")]) if trash.is_dir() else 0
        light(s, "todo.txt")
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "trash"), "the actions")
        click_row(s, "trash")
        until(lambda: "is in the trash" in status(s.screen()) and re.search(r"\bundo\s*$", status(s.screen())), "the trash receipt with undo")
        assert not (home / "documents/todo.txt").exists(), "the file left documents"
        assert len([p for p in trash.iterdir() if p.name.startswith("todo")]) == before + 1, "the file under the fixture's XDG_DATA_HOME Trash/files"
        s.click("undo")
        until(lambda: (home / "documents/todo.txt").is_file(), "the file back from the trash")
        s.checks.append("trash puts the file in the fixture's own Trash/files and says is in the trash with undo; undo brings it back")
        # 11. the preview: text, picture, PDF, sound; Esc back to the panes as they were
        light(s, "notes.md")
        s.key("-k", "space")
        until(lambda: "Proof notes" in s.text(), "the text preview")
        shot(s, "preview-text")
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~/documents") and lit(s.screen(), "notes.md"), "back to the panes with notes.md lit")
        assert any("~/documents" in l and "~/pictures" in l for l in body(s.screen())), "the two panes stand as they were"
        light(s, "cover.png")
        s.key("-k", "space")
        until(lambda: re.search(r"\b20\s*\S\s*40\b", s.text()), "the picture's size on the facts row")
        shot(s, "preview-picture")
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~/documents") and lit(s.screen(), "cover.png"), "back from the picture")
        light(s, "letter.pdf")
        s.key("-k", "space")
        if shutil.which("pdftoppm"):
            # one page: the page drawn as a picture, its zoom on the facts row and the zoom keys on the bar; a count
            # of pages stands there only where there are several
            until(lambda: re.search(r"\b\d+%", s.text()) and re.search(r"\bzoom\b", keys(s.screen())), "the PDF's page")
            s.checks.append("The PDF previews as its page drawn: the zoom on the facts row and zoom among the keys")
        else:
            until(lambda: "no preview: pdftoppm (poppler) is not installed" in s.text(), "the PDF's refusal")
            s.checks.append("No poppler on this machine: the PDF says no preview: pdftoppm (poppler) is not installed; its page is not proved here")
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~/documents") and lit(s.screen(), "letter.pdf"), "back from the PDF")
        light(s, "voice.wav")
        s.key("-k", "space")
        if shutil.which("mpv"):
            until(lambda: re.search(r"\bplay\b", keys(s.screen())), "the sound's keys")
            s.checks.append("The sound previews with the sound's keys, play on Space; nothing is played")
        else:
            until(lambda: "no preview: mpv is not installed" in s.text(), "the sound's refusal")
            s.checks.append("No mpv on this machine: the sound says no preview: mpv is not installed; the play is not proved here")
        s.key("-k", "Escape")
        until(lambda: header_has(s.screen()[0], "~/documents") and lit(s.screen(), "voice.wav"), "back from the sound")
        s.checks.append("Space previews the lit file in the whole window: the Markdown's first line, the picture's 20 x 40 on the facts row; "
                        "Esc comes back to the two panes as they were with the file lit")
        # 14. one pane (before the large folder and the doors, so their rows are read at the column's width)
        clear_reply(s)
        s.key("-k", "Right")
        until(lambda: find_row(s.screen(), "one pane"), "the folder's actions with one pane")
        click_row(s, "one pane")
        until(lambda: header_has(s.screen()[0], "~/documents") and not any(l.count("~/documents") >= 2 for l in body(s.screen())), "one pane")
        assert not any("~/pictures" in l for l in body(s.screen())), "the second pane is gone"
        assert not re.search(r"\bpane\b", keys(s.screen())), "the key bar drops pane  Ctrl+Tab"
        s.checks.append("one pane under this folder closes the second pane: ~/documents once, no pane key")
        # 12. the large folder: a bounded wait for its first page, End to its last row
        s.key("-k", "Left")
        until(lambda: header_has(s.screen()[0], "~"), "Left with nothing typed goes up")
        light(s, "big")
        started = time.monotonic()
        s.key("-k", "Return")
        s.key("-k", "Down")   # a key while the folder is read: the dialog answers it, nothing hangs
        until(lambda: row_named(s.screen(), "f00000.txt"), "the big folder's first row", 30)
        first = time.monotonic() - started
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
        # 13. the doors back, and the typed filter
        open_folder(s, "documents", "~/documents")
        s.key("-k", "Left")
        until(lambda: header_has(s.screen()[0], "~"), "Left goes up")
        open_folder(s, "documents", "~/documents")
        s.key("-k", "BackSpace")
        until(lambda: header_has(s.screen()[0], "~"), "Backspace goes up")
        open_folder(s, "documents", "~/documents")
        lines = s.screen()
        click_at(s, 0, lines[0].index("back") + 2)
        until(lambda: header_has(s.screen()[0], "~"), "the header's back goes up")
        open_folder(s, "documents", "~/documents")
        s.key("tod")
        until(lambda: shows("todo.txt") and not shows("notes.md"), "typed words filter the folder to todo.txt")
        s.key("-k", "Escape")
        until(lambda: shows("todo.txt", "notes.md"), "Esc clears the words and both rows are back")
        s.checks.append("With nothing typed Left, Backspace and the header's back go up a level; typed words filter the folder and Esc clears them")
        manifest = {"binary_sha256": s.binary_sha256,
                    "palette": s.palette,
                    "environment": "Void Linux; native headless Sway, foot; 1440x1000",
                    "data": "A fixture home of the proof's own: documents (Markdown, text, Python, a 20x40 PNG, a one-page PDF, a second "
                            "of silence), pictures (a PNG and a notes.md a copy runs into), big (10,000 files), an empty folder; the real "
                            "files provider; no drives",
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
