#!/usr/bin/env python3
"""Native provider contracts in isolated homes; no desktop or personal data."""
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch
from types import SimpleNamespace


REPO = Path(__file__).resolve().parents[1]
PROGRAM = REPO / "spark-shell"


def rpc(number, method, **params):
    return {"jsonrpc": "2.0", "id": number, "method": method, "params": params}


def call(number, tool_name, **arguments):
    return rpc(number, "tools/call", name=tool_name, arguments=arguments)


def title(name, key):
    """The name home says a bundled theme by (v0.172): its own family's title, its palette's own name, else its
    name's words with capitals. NAME as the curation lists it, KEY its folder."""
    family = REPO / "gallery/core" / key / "family.json"
    if family.exists() and json.loads(family.read_text()).get("id") == key:
        return json.loads(family.read_text())["title"]
    stock = REPO / "gallery/theme" / (name + ".env")
    if stock.exists():
        return stock.read_text().splitlines()[0][2:].split(" -- ")[0]
    return " ".join(word[:1].upper() + word[1:] for word in name.split("-"))


class Providers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="provider-acceptance-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = os.environ.copy()
        self.env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "config"),
                        XDG_STATE_HOME=str(self.home / "state"), XDG_DATA_HOME=str(self.home / "data"),
                        XDG_RUNTIME_DIR=str(self.home / "run"), SPARK_SHELL_NO_APPLY="1",
                        SPARK_SHELL_PTS_DIR=str(self.home / "ptys"), TZ="UTC0")
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY", "SPARK_BASE_URL", "SPARK_FORGE_TOKEN"):
            self.env.pop(key, None)
        # no way to root: on a machine whose sudo asks nothing, a theme step once wrote this home into its /etc/rc.local
        no_root = self.home / "no-root"
        no_root.mkdir()
        for name in ("sudo", "doas"):
            (no_root / name).write_text("#!/bin/sh\nexit 1\n")
            (no_root / name).chmod(0o755)
        self.env["PATH"] = str(no_root) + os.pathsep + self.env["PATH"]

    def provider(self, section, *requests, program=PROGRAM):
        packets = [rpc(0, "initialize", protocolVersion="2025-06-18", capabilities={})] + list(requests)
        result = subprocess.run(["sh", str(program), "provide", section], env=self.env,
                                input="".join(json.dumps(p) + "\n" for p in packets),
                                text=True, capture_output=True, timeout=45)
        self.assertEqual(result.returncode, 0, "provider process failed")
        replies = {p["id"]: p for p in map(json.loads, result.stdout.splitlines()) if "id" in p}
        self.assertTrue(all(p["id"] in replies for p in requests if "method" in p), "provider missed a reply")
        return replies

    def curated(self, curation):
        """The program in a tree of links to the repository, its curation the test's own."""
        tree = self.home / "tree"
        core = tree / "gallery" / "core"
        core.mkdir(parents=True)
        for entry in REPO.iterdir():
            if entry.name == "spark-shell":
                shutil.copy2(entry, tree / entry.name)   # the program resolves a link to itself
            elif entry.name not in ("gallery", ".git"):
                (tree / entry.name).symlink_to(entry)
        for entry in (REPO / "gallery").iterdir():
            if entry.name != "core":
                (tree / "gallery" / entry.name).symlink_to(entry)
        for entry in (REPO / "gallery" / "core").iterdir():
            if entry.name != "curation.json":
                (core / entry.name).symlink_to(entry)
        (core / "curation.json").write_text(json.dumps(curation))
        return tree / "spark-shell"

    def rows(self, section):
        reply = self.provider(section, rpc(1, "resources/read", uri=f"spark-shell://{section}/rows"))
        return json.loads(reply[1]["result"]["contents"][0]["text"])["rows"]

    def test_bundled_theme_gallery_opens_curated_rooms_and_applies_only_on_request(self):
        cfgdir = self.home / "config/spark-shell"
        cfgdir.mkdir(parents=True)
        config = cfgdir / "config"
        before = "THEME=nord\nDESKTOP=sway\nWALLPAPER=fjord\n"
        config.write_text(before)
        base = "spark-shell://theme/rows/gallery"
        curation = json.loads((REPO / "gallery/core/curation.json").read_text())
        sections = curation["sections"]
        dispositions = curation.get("dispositions", {})
        on_view = lambda name: dispositions.get(name, {}).get("status", "exhibited") == "exhibited"
        names = [line.split("\t") for line in (REPO / "gallery/core/themes.tsv").read_text().splitlines()]
        ids = {parts[0]: parts[-1] for parts in names}
        works = [name for section in sections for name in section["works"]]
        shows = [name for e in curation.get("exhibitions", []) if e["status"] == "open" for name in e["works"]]
        self.assertEqual(len(works), 34)
        self.assertEqual(set(works) | set(shows), set(ids), "every work hangs in a section or an open exhibition")
        self.assertEqual(len(works), len(set(works)))
        requests = [rpc(1, "resources/read", uri=base)]
        requests += [rpc(i, "resources/read", uri=base + "/collection/permanent/" + section["id"])
                     for i, section in enumerate(sections, 2)]
        requests += [rpc(i, "resources/read", uri=base + "/" + key)
                     for i, key in enumerate(ids.values(), 2 + len(sections))]
        replies = self.provider("theme", *requests)
        rendered = [json.loads(replies[q["id"]]["result"]["contents"][0]["text"]) for q in requests]
        gallery = rendered[0]
        rooms = rendered[1:1+len(sections)]
        cards = rendered[1+len(sections):]
        self.assertEqual((gallery["title"], gallery["state"]), ("The Gallery", "34 works in 6 sections, 1 exhibition"))
        kept = [r for r in gallery["rows"] if r.get("group") != "Exhibitions"]
        self.assertEqual([r["text"] for r in kept], [section["title"] for section in sections])
        self.assertTrue(all(r.get("group") == "The Permanent Collection"
                            and not r.get("tool") and not r.get("look") for r in kept))
        self.assertEqual([(r["text"], r["columns"]) for r in gallery["rows"] if r.get("group") == "Exhibitions"],
                         [("Cinematic Worlds", ["%d works" % len(shows)])])
        for section, entry, room in zip(sections, kept, rooms):
            self.assertEqual(entry["children"], base + "/collection/permanent/" + section["id"])
            self.assertEqual(entry["columns"], [str(len(section["works"])) + " works"])
            self.assertEqual(room["title"], section["title"])
            self.assertEqual(room["state"], section["description"])
            order = [w for w in section["works"] if on_view(w)] + [w for w in section["works"] if not on_view(w)]
            self.assertEqual([r["id"] for r in room["rows"]], ["theme:entry:" + ids[name] for name in order], "on view first, then supporting")
            self.assertEqual([r["text"] for r in room["rows"]], [title(name, ids[name]) for name in order], "each said by its title")
            self.assertEqual([r["children"] for r in room["rows"]], [base + "/" + ids[name] for name in order])
            split = 0 < sum(map(on_view, section["works"])) < len(section["works"])
            self.assertTrue(all(r.get("group") == (("on view" if on_view(name) else "supporting") if split else None)
                                for name, r in zip(order, room["rows"])))
            self.assertFalse([k for r in room["rows"] for k in r if k.startswith("_")], "no key of the provider's own reaches the dialog")
            self.assertTrue(all(r.get("line") for r in room["rows"]), "each work says its medium and variant")
            lead = section.get("lead") or next(w for w in section["works"] if on_view(w))
            self.assertEqual(entry["page"], "spark-shell://theme/preview/" + ids[lead])
        for parts, card in zip(names, cards):
            self.assertEqual(card["title"], title(parts[0], parts[-1]))
            self.assertEqual(card["rows"][0]["tool"],
                             {"name": "theme_palette", "arguments": {"name": parts[-1]}})
        invalid = self.provider("theme", rpc(1, "resources/read", uri=base + "/collection/permanent/missing"))
        self.assertIn("error", invalid[1])
        self.assertEqual(config.read_text(), before)
        self.assertFalse((cfgdir / "themes").exists())
        result = self.provider("theme", call(1, "theme_palette", name="ring-shadow"))[1]["result"]
        self.assertFalse(result["isError"])
        for setting in ("THEME=ring-shadow", "WALLPAPER=orbit", "GLYPH_FAMILY=banner"):
            self.assertIn(setting, config.read_text().splitlines())
        # moving or still stays the person's: a theme never turns it on (v0.174.1)
        self.assertNotIn("WALLPAPER_MOTION=on", config.read_text().splitlines())

    def test_theme_wallpapers_are_read_only_and_settings_keep_their_controls(self):
        cfg = self.home / "config/spark-shell/config"
        cfg.parent.mkdir(parents=True)
        before = "THEME=nord\nWALLPAPER=fjord\nDESKTOP=sway\nDIALOG_ANIMATION=none\n"
        cfg.write_text(before)
        base = "spark-shell://theme/"
        paths = ("rows", "rows/settings/type", "rows/gallery", "rows/gallery/nightswim",
                 "preview/nord", "preview/nightswim", "preview/nord?full=1", "current-wallpaper")
        calls = [rpc(i, "resources/read", uri=base + path) for i, path in enumerate(paths, 1)]
        replies = self.provider("theme", *calls)
        root, section, gallery, detail, nord, photo, full, current = [
            json.loads(replies[q["id"]]["result"]["contents"][0]["text"]) for q in calls]
        groups = [r["text"] for r in root["rows"] if r["id"].startswith("theme:settings:")]
        self.assertIn("Type and glyphs", groups)
        self.assertIn("Your themes", groups)
        self.assertEqual(section["title"], "Type and glyphs")
        self.assertEqual(next(r["step"]["set"]["name"] for r in section["rows"] if r["text"]=="Glyph family"), "theme_family")
        self.assertEqual(len(gallery["rows"]), 7, "six sections and Cinematic Worlds")
        self.assertTrue(all(r["page"].startswith(base + "preview/") for r in gallery["rows"]))
        self.assertEqual(detail["rows"][0]["page"], base+"preview/nightswim")
        self.assertEqual(nord["facts"], ["fjord", "Nord"])
        self.assertEqual(photo["facts"], ["nightswim.png", "Nightswim (from wallpaper)"])
        if sys.platform != "darwin":
            self.assertEqual(current["facts"], ["fjord", "Nord"])
        self.assertTrue(full["full"])
        for preview in (nord, photo, full):
            self.assertEqual(Path(preview["picture"]).read_bytes()[:8], bytes.fromhex("89504e470d0a1a0a"))
        bad = self.provider("theme", rpc(1, "resources/read", uri=base+"preview/../nord"))
        self.assertIn("error", bad[1])
        self.assertEqual(cfg.read_text(), before)

    def test_terminal_palette_copies_colors_and_exports_without_applying(self):
        cfg = self.home / "config/spark-shell/config"
        cfg.parent.mkdir(parents=True)
        before = "THEME=nord\nDESKTOP=sway\n"
        cfg.write_text(before)
        tools = self.home / "bin"
        tools.mkdir()
        for name, body in (("wl-copy", 'cat > "$HOME/clipboard"'), ("pbcopy", 'cat > "$HOME/clipboard"'),
                           ("xdg-user-dir", 'printf "%s\\n" "$HOME/files"')):
            exe = tools / name
            exe.write_text("#!/bin/sh\n" + body + "\n")
            exe.chmod(0o700)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        theme = "amber-drizzle"
        uri = "spark-shell://theme/rows/"
        req = [rpc(1, "resources/read", uri=uri+"gallery/"+theme),
               rpc(2, "resources/read", uri=uri+"palette/"+theme),
               rpc(3, "resources/read", uri=uri+"exports/"+theme),
               call(4, "theme_copy_color", name=theme, key="ANSI_15"),
               call(5, "theme_export_palette", name=theme, format="kitty")]
        reply = self.provider("theme", *req)
        detail, colors, formats = [json.loads(reply[i]["result"]["contents"][0]["text"])["rows"] for i in (1, 2, 3)]
        self.assertEqual(detail[1]["children"], req[1]["params"]["uri"])
        self.assertEqual(colors[0]["columns"], ["Amber Drizzle (handpicked)"])
        self.assertEqual(colors[1]["children"], req[2]["params"]["uri"])
        self.assertEqual(len(colors[2:]), 20)
        self.assertEqual([r["swatch"] for r in colors[2:]], [r["columns"][0] for r in colors[2:]])
        self.assertEqual((self.home/"clipboard").read_text(), colors[-1]["swatch"])
        self.assertEqual([r["tool"]["arguments"]["format"] for r in formats], ["env","foot","kitty","ghostty","alacritty"])
        self.assertFalse(reply[5]["result"]["isError"])
        destination = self.home/"files/amber-drizzle.kitty.conf"
        exported = subprocess.check_output([PROGRAM, "theme", "export", theme, "kitty"], env=self.env, text=True)
        self.assertEqual(destination.read_text(), exported)
        self.assertIn("color15 " + colors[-1]["swatch"], exported)
        destination.write_text("my file")
        self.provider("theme", req[-1])
        self.assertEqual(destination.read_text(), "my file")
        self.assertEqual((destination.parent/"amber-drizzle-2.kitty.conf").read_text(), exported)
        self.assertEqual(cfg.read_text(), before)
        self.assertNotEqual(subprocess.run([PROGRAM, "theme", "export", "../nord", "env"], env=self.env, capture_output=True).returncode, 0)
        def reference(name):
            return subprocess.check_output([PROGRAM, "theme", "export", name], env=self.env, text=True).splitlines()[0]
        self.assertEqual(reference("catppuccin-mocha"), "# Palette reference: Catppuccin Mocha")
        self.assertEqual(reference("core-dracula"), "# Palette reference: Dracula")
        personal = cfg.parent/"themes/my-dracula"
        personal.mkdir(parents=True)
        (personal/"look.env").write_text("FORMAT=2\nPALETTE=dracula\n")
        palette = (REPO/"gallery/theme/dracula.env").read_text()
        (personal/"palette.env").write_text(palette)
        self.assertEqual(reference("my-dracula"), "# Palette reference: Dracula")
        (personal/"palette.env").write_text(palette.replace("#282a36", "#282a37"))
        self.assertEqual(reference("my-dracula"), "# Palette reference: my-dracula (based on Dracula)")

    def test_exhibitions_variants_and_compositions_are_looked_at_and_change_nothing(self):
        cfgdir = self.home / "config/spark-shell"
        cfgdir.mkdir(parents=True)
        config = cfgdir / "config"
        before = "THEME=nord\nDESKTOP=sway\n"
        config.write_text(before)
        base = "spark-shell://theme/rows/gallery"
        text = lambda reply: json.loads(reply["result"]["contents"][0]["text"])
        curation = json.loads((REPO / "gallery/core/curation.json").read_text())
        pending = [e["id"] for e in curation.get("exhibitions", []) if e["status"] != "open"]
        opened = [e["title"] for e in curation.get("exhibitions", []) if e["status"] == "open"]
        replies = self.provider("theme", rpc(1, "resources/read", uri=base),
                                *[rpc(i, "resources/read", uri=base + "/collection/exhibition/" + e) for i, e in enumerate(pending, 2)])
        self.assertEqual([r["text"] for r in text(replies[1])["rows"] if r.get("group") == "Exhibitions"], opened, "no exhibition before it opens")
        self.assertTrue(all("error" in replies[i] for i in range(2, 2 + len(pending))))
        # Cinematic Worlds, open: each work's portrait drawn for a turned screen and its panels for two; Atlas Awakening has
        # loops of its own, The Sounding Gate a still and its own opening and closing, Mars Conquest and The Pilgrim's Vow both,
        # The Late Edition its opening and closing and a still first
        works = [("atlas-awakening", "Atlas Awakening", "moves with moving wallpaper on", "atlas"),
                 ("the-sounding-gate", "The Sounding Gate", "still", "own"),
                 ("mars-conquest", "Mars Conquest", "moves with moving wallpaper on", "own"),
                 ("the-pilgrims-vow", "The Pilgrim's Vow", "moves with moving wallpaper on", "own"),
                 ("the-late-edition", "The Late Edition", "still", "own")]   # its loop is the second landscape's alone
        looked = lambda i, name: [rpc(i, "resources/read", uri=base + "/" + name),
                                  rpc(i + 1, "resources/read", uri="spark-shell://theme/preview/" + name + "/portrait"),
                                  rpc(i + 2, "resources/read", uri="spark-shell://theme/preview/" + name + "/panels-2")]
        replies = self.provider("theme", rpc(1, "resources/read", uri=base + "/collection/exhibition/cinematic-worlds"),
                                *[q for i, work in enumerate(works) for q in looked(2 + 3 * i, work[0])])
        self.assertEqual([(r["id"], r["text"], r["line"]) for r in text(replies[1])["rows"]],
                         [("theme:entry:" + work[0], work[1], "cinematic illustration \u00b7 dark") for work in works], "each by its title")
        for i, (_, work_title, moves, opens) in enumerate(works):
            detail, portrait, panels = [text(replies[2 + 3 * i + n]) for n in range(3)]
            facts = {r["id"]: (r.get("columns") or [None])[0] for r in detail["rows"]}
            # the page says what it is on its poster (apply's line), and what it brings where it sets it: the wallpaper by its
            # role, moving where its picture has a loop (none on a Mac, which has no desktop), the dialog's motion its own
            wall = None if sys.platform == "darwin" else "Landscape 1" + (", moving" if moves.startswith("moves") else "")
            self.assertEqual((detail["title"], detail["rows"][0]["line"], facts.get("theme:detail:wallpaper"), facts["theme:detail:motion"]),
                             (work_title, "cinematic illustration \u00b7 dark", wall, "its own" if opens == "own" else opens))
            self.assertFalse([r for r in detail["rows"] if (r.get("columns") or [""])[0] == "keep current"], "nothing a theme leaves alone is listed")
            self.assertEqual((portrait["facts"][0], panels["facts"][0]), ("its own portrait", "2 panels, left to right"))
        # an open exhibition, a supporting work and a section's lead, from a curation of the test's own
        curation["exhibitions"] = [{"id": "study", "title": "Study", "note": "A test exhibition.", "status": "open",
                                    "works": ["nord", "absent", "dracula"]}]
        curation["dispositions"] = {"dracula": {"status": "supporting", "reason": "a test"}}
        section = next(s for s in curation["sections"] if "dracula" in s["works"])
        section["lead"] = "nord"
        program = self.curated(curation)
        replies = self.provider("theme", rpc(1, "resources/read", uri=base),
                                rpc(2, "resources/read", uri=base + "/collection/exhibition/study"),
                                rpc(3, "resources/read", uri=base + "/collection/permanent/" + section["id"]), program=program)
        home, show, room = text(replies[1]), text(replies[2]), text(replies[3])
        self.assertEqual(home["state"], "34 works in 6 sections, 1 exhibition")
        entry = next(r for r in home["rows"] if r["id"] == "theme:room:exhibition:study")
        self.assertEqual((entry["group"], entry["columns"], entry["line"], entry["children"]),
                         ("Exhibitions", ["2 works"], "A test exhibition.", base + "/collection/exhibition/study"))
        self.assertEqual(entry["page"], "spark-shell://theme/preview/nord")
        self.assertEqual([(r["text"], r["group"]) for r in show["rows"]], [("Nord", "on view"), ("Dracula", "supporting")])
        lead = next(r for r in home["rows"] if r["id"] == "theme:room:permanent:" + section["id"])
        self.assertEqual(lead["page"], "spark-shell://theme/preview/nord")
        self.assertEqual(room["rows"][-1]["text"], "Dracula")
        self.assertEqual(room["rows"][-1]["group"], "supporting")
        # a work's details: its family, its other variant as a link, its compositions; nothing applied
        replies = self.provider("theme", rpc(1, "resources/read", uri=base + "/core-tokyonight-day"),
                                rpc(2, "resources/read", uri=base + "/core-tokyonight-day/art"),
                                rpc(3, "resources/read", uri="spark-shell://theme/preview/core-tokyonight-day/portrait"),
                                rpc(4, "resources/read", uri="spark-shell://theme/preview/core-tokyonight-day/panels-3"),
                                rpc(5, "resources/read", uri=base + "/../nord/art"))
        detail, art, portrait = text(replies[1]), text(replies[2]), text(replies[3])
        self.assertEqual((detail["title"], detail["rows"][0]["line"]), ("Tokyo Night, day style", "vector \u00b7 light"))
        other = next(r for r in detail["rows"] if r["id"] == "theme:variant:dark")
        self.assertEqual((other["children"], other["columns"], other.get("tool")), (base + "/tokyonight-night", ["Tokyo Night, night style"], None))
        compositions = [r for r in detail["rows"] if r["id"] == "theme:compositions"]
        if sys.platform == "darwin":   # no desktop on a Mac: no screens to compose
            self.assertEqual(compositions, [])
        else:
            self.assertEqual(compositions[0]["children"], base + "/core-tokyonight-day/art")
        # every theme is three pictures (the owner's rule): the drawing's own portrait and its second landscape
        self.assertEqual([r["id"] for r in art["rows"]], ["theme:art:landscape", "theme:art:portrait", "theme:art:panels-2"])
        self.assertEqual([r["columns"] for r in art["rows"]], [["landscape"], ["its own composition"], ["its second landscape"]])
        self.assertTrue(all(not r.get("tool") and not r.get("look") and r["page"].startswith("spark-shell://theme/preview/core-tokyonight-day")
                            for r in art["rows"]))
        self.assertEqual(portrait["facts"][0], "the drawing drawn for a turned screen")
        self.assertIn("error", replies[4], "no panels for three screens are claimed for a work that has two landscapes")
        self.assertIn("error", replies[5])
        self.assertEqual(config.read_text(), before)
        self.assertFalse((cfgdir / "themes").exists())

    def test_preview_install_and_personal_theme_take_precedence(self):
        cfgdir = self.home / "config/spark-shell"
        themes = cfgdir / "themes"
        themes.mkdir(parents=True)
        colors = REPO / "gallery/theme/dracula.env"
        for name, anim in (("first-dracula", "sun"), ("ring-shadow", "flight")):
            folder = themes / name
            folder.mkdir()
            shutil.copyfile(colors, folder / "palette.env")
            (folder / "look.env").write_text(f"FORMAT=2\nPALETTE=dracula\nANIMATION={anim}\n")
        (cfgdir / "galleries").mkdir()
        (cfgdir / "galleries/first-gallery.list").write_text("first-dracula\nring-shadow\n")
        (cfgdir / "config").write_text("THEME=first-dracula\nDESKTOP=sway\n")
        base = "spark-shell://theme/rows/gallery"
        reads = [rpc(i, "resources/read", uri=base + tail)
                 for i, tail in enumerate(("", "/collection/permanent/chromatic-nocturnes",
                                           "/first-dracula", "/ring-shadow"), 1)]
        replies = self.provider("theme", *reads)
        gallery, room, dracula, ring = [
            json.loads(replies[i]["result"]["contents"][0]["text"]) for i in range(1, 5)]
        self.assertEqual(len(gallery["rows"]), 7, "six sections and Cinematic Worlds")
        self.assertEqual(room["title"], "Chromatic Nocturnes")
        selected = next(r for r in room["rows"] if r["sign"] == "check")
        self.assertEqual((selected["text"], selected["children"]), ("dracula", base + "/first-dracula"))
        for card, expected in ((dracula, "sun"), (ring, "flight")):
            motion = next(r for r in card["rows"] if r["id"] == "theme:detail:motion")
            self.assertEqual(motion["columns"], [expected])

    def test_duplicate_notes_keep_exact_identity_and_ambiguous_append_changes_nothing(self):
        notes = self.home / "notes"
        notes.mkdir()
        for name in ("first.md", "second.md"):
            (notes / name).write_text("# Fixture\n" + name + "\n")
        rows = [r for r in self.rows("notes") if r["text"] == "Fixture"]
        self.assertEqual(len({r["id"] for r in rows}), 2)
        self.assertEqual({r["tool"]["arguments"]["name"] for r in rows}, {"first.md", "second.md"})
        before = {p.name: p.read_bytes() for p in notes.iterdir()}
        for name in ("missing", "Fixture"):
            cli = subprocess.run(["sh", str(PROGRAM), "notes", name], env=self.env,
                                 text=True, capture_output=True, timeout=15)
            self.assertEqual(cli.returncode, 1)
            self.assertIn("no unique note", cli.stdout)
        self.assertEqual(before, {p.name: p.read_bytes() for p in notes.iterdir()})
        result = self.provider("notes", call(1, "notes_add", text="Fixture: ambiguous"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in notes.iterdir()})
        result = self.provider("notes", call(1, "notes_add", text="second.md: chosen"))
        self.assertFalse(result[1]["result"]["isError"])
        self.assertEqual(result[1]["result"]["structuredContent"]["effect"]["id"], "second.md")
        self.assertEqual((notes / "first.md").read_bytes(), before["first.md"])
        self.assertTrue((notes / "second.md").read_text().endswith("- chosen\n"))
        (notes / "second.md").unlink()
        result = self.provider("notes", call(1, "notes_add", text="second.md: stale"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(set(p.name for p in notes.iterdir()), {"first.md"})

    def test_files_rename_move_copy_trash_and_restore_on_a_fixture_home(self):
        home = self.home   # the root is the home itself: its trash is the home's (a folder under it would be a drive's)
        (home / "docs").mkdir(parents=True)
        (home / "notes.md").write_text("hello\n")
        root = home.resolve()
        self.env["SPARK_SHELL_NO_UDISKS"] = "1"
        self.env["SPARK_SHELL_NO_GIO"] = "1"
        roots = {"jsonrpc": "2.0", "id": "roots", "result": {"roots": [{"uri": "file://" + str(root)}]}}
        init = rpc(0, "initialize", protocolVersion="2025-06-18", capabilities={"roots": {}})
        initialized = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        def session(*calls):
            packets = [init, initialized, roots] + list(calls)
            result = subprocess.run(["sh", str(PROGRAM), "provide", "files"], env=self.env,
                                    input="".join(json.dumps(p) + "\n" for p in packets), text=True, capture_output=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stderr)
            return {p["id"]: p for p in map(json.loads, result.stdout.splitlines()) if "id" in p and p["id"] != "roots"}
        replies = session(call(1, "files_rename", path=str(root / "notes.md"), name="Notes 2026.md"),
                          call(2, "files_move", path=str(root / "Notes 2026.md"), to=str(root / "docs")),
                          call(3, "files_copy", path=str(root / "docs" / "Notes 2026.md"), to=str(root)),
                          call(4, "files_trash", path=str(root / "Notes 2026.md")))
        done = lambda n: replies[n]["result"]["structuredContent"]
        self.assertEqual(done(1)["undo"], {"name": "files_rename", "arguments": {"path": str(root / "Notes 2026.md"), "name": "notes.md"}})
        self.assertEqual(done(2)["undo"], {"name": "files_move", "arguments": {"path": str(root / "docs" / "Notes 2026.md"), "to": str(root)}})
        self.assertEqual(done(3)["undo"]["name"], "files_trash")
        self.assertEqual((root / "docs" / "Notes 2026.md").read_text(), "hello\n")
        self.assertEqual(done(4)["undo"], {"name": "files_restore", "arguments": {"path": str(root / "Notes 2026.md")}})
        trash = Path(self.env["XDG_DATA_HOME"]) / "Trash"
        self.assertFalse((root / "Notes 2026.md").exists(), "the copy went to the trash")
        self.assertEqual(sorted(p.name for p in (trash / "info").iterdir()), ["Notes 2026.md.trashinfo"])
        self.assertIn("Path=" + str(root).replace(" ", "%20") + "/Notes%202026.md", (trash / "info" / "Notes 2026.md.trashinfo").read_text())
        self.assertEqual((trash / "files" / "Notes 2026.md").read_text(), "hello\n")
        replies = session(call(5, "files_restore", path=str(root / "Notes 2026.md")),
                          call(6, "files_new_folder", path=str(root), name="new one"),
                          call(7, "files_trash", path=str(root)),
                          call(8, "files_rename", path=str(root / "docs"), name="../escape"))
        self.assertEqual(done(5)["receipt"], "Notes 2026.md is back")
        self.assertEqual((root / "Notes 2026.md").read_text(), "hello\n")
        self.assertFalse((trash / "files" / "Notes 2026.md").exists())
        self.assertFalse((trash / "info" / "Notes 2026.md.trashinfo").exists())
        self.assertTrue((root / "new one").is_dir())
        self.assertEqual(done(6)["undo"]["name"], "files_trash")
        self.assertTrue(replies[7]["result"]["isError"], "the home itself is never trashed")
        self.assertIn("error", replies[8], "a name with a slash never passes the schema")
        self.assertTrue((root / "docs").is_dir())

    def test_duplicate_reminders_done_undo_and_snooze_use_the_returned_uid(self):
        # Force equal second-resolution metadata, so a same-size reschedule
        # must invalidate the earlier lookup before reporting native evidence.
        bindir = self.home / "bin"
        bindir.mkdir()
        fixture = bindir / "stat"
        fixture.write_text("#!" + sys.executable + "\n" + '''import os,pathlib,sys
a=sys.argv[1:]
if len(a)>2 and a[1] in ('%n %s %Y','%N %z %m'):
 for x in a[2:]:
  p=pathlib.Path(x)
  if p.is_file(): print(str(p)+' '+str(p.stat().st_size)+' 0')
else: os.execv(''' + repr(shutil.which("stat")) + ''', ['stat']+a)
''')
        fixture.chmod(0o755)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]
        result = self.provider("reminders",
                               call(1, "reminders_add", words="2099-01-01 10:00 Fixture"),
                               call(2, "reminders_add", words="2099-01-02 10:00 Fixture"))
        identities = [result[n]["result"]["structuredContent"]["effect"]["id"] for n in (1, 2)]
        self.assertEqual(len(set(identities)), 2)
        for identity in identities:
            self.assertTrue(identity.startswith("spark-shell-"))
            opaque = uuid.UUID(identity.removeprefix("spark-shell-"))
            self.assertEqual(opaque.version, 4)
            self.assertEqual(identity, "spark-shell-" + str(opaque), "new identities must contain only a random UUID, never a hostname")
        calendar = self.home / "calendar"
        files = {uid: next(p for p in calendar.glob("*.ics") if "UID:" + uid in p.read_text()) for uid in identities}
        before = {p.name: p.read_bytes() for p in files.values()}
        choices = [c["arguments"]["name"] for r in self.rows("reminders") for c in r["more"] if c["name"] == "reminders_done"]
        self.assertEqual(set(choices), set(identities), "future reminders must have exact actions")
        result = self.provider("reminders", call(1, "reminders_done", name="Fixture"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in calendar.glob("*.ics")})
        result = self.provider("reminders", call(1, "reminders_done", name=identities[1]))
        completed = result[1]["result"]["structuredContent"]
        self.assertEqual(completed["effect"]["id"], identities[1])
        self.assertEqual(completed["effect"]["operation"], "done")
        self.assertEqual(completed["undo"]["arguments"]["name"], identities[1])
        self.assertFalse(files[identities[1]].exists())
        self.assertEqual(files[identities[0]].read_bytes(), before[files[identities[0]].name])

        result = self.provider("reminders", call(1, "reminders_restore", name=identities[1]))
        restored = result[1]["result"]["structuredContent"]["effect"]
        self.assertEqual((restored["id"], restored["operation"]), (identities[1], "restored"))
        self.assertEqual(files[identities[1]].read_bytes(), before[files[identities[1]].name])
        started = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
        result = self.provider("reminders", call(1, "reminders_snooze", name=identities[1]))
        ended = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
        moved = result[1]["result"]["structuredContent"]["effect"]
        self.assertEqual((moved["id"], moved["operation"]), (identities[1], "rescheduled"))
        due = dt.datetime.strptime(moved["localTime"], "%Y-%m-%d %H:%M")
        self.assertLessEqual((started + dt.timedelta(minutes=10)).replace(second=0, microsecond=0), due)
        self.assertLessEqual(due, (ended + dt.timedelta(minutes=10)).replace(second=0, microsecond=0))
        self.assertIn("DTSTART:" + due.strftime("%Y%m%dT%H%M00"), files[identities[1]].read_text())
        self.assertEqual(files[identities[0]].read_bytes(), before[files[identities[0]].name])

        # Two completed events with the same title never restore whichever
        # happened to sort first; the returned UID is the undo identity.
        result = self.provider("reminders", *(call(n + 1, "reminders_done", name=uid) for n, uid in enumerate(identities)))
        self.assertTrue(all(not result[n]["result"]["isError"] for n in (1, 2)))
        done = calendar / "done"
        completed_bytes = {p.name: p.read_bytes() for p in done.glob("*.ics")}
        result = self.provider("reminders", call(1, "reminders_restore", name="Fixture"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(completed_bytes, {p.name: p.read_bytes() for p in done.glob("*.ics")})
        result = self.provider("reminders", call(1, "reminders_restore", name=identities[0]))
        self.assertEqual(result[1]["result"]["structuredContent"]["effect"]["id"], identities[0])
        self.assertEqual(files[identities[0]].read_bytes(), before[files[identities[0]].name])
        self.assertTrue((done / files[identities[1]].name).exists())

    def test_typed_note_append_preserves_payload_and_only_exact_existing_file(self):
        notes = self.home / "notes"
        notes.mkdir()
        original = b"# Fixture\nExisting body.\n"
        for filename in ("first.md", "second.md"):
            (notes / filename).write_bytes(original)
        rows = self.rows("notes")
        # append is behind each note's row, no row of its own (#169)
        self.assertFalse([r for r in rows if r.get("tool") and r["tool"]["name"] == "notes_append"])
        direct = [m for r in rows for m in r.get("more", []) if m["name"] == "notes_append"]
        self.assertEqual({m["arguments"]["name"] for m in direct}, {"first.md", "second.md"})
        self.assertTrue(all(m["ask"] == ["text"] for m in direct))
        tools = self.provider("notes", rpc(1, "tools/list"))[1]["result"]["tools"]
        typed = next(t for t in tools if t["name"] == "notes_append")
        self.assertEqual(typed["inputSchema"]["required"], ["name", "text"])
        self.assertEqual(typed["inputSchema"]["properties"]["text"]["contentMediaType"], "text/plain")
        marker = self.home / "must-not-run"
        payload = '  Preserve  spaces\tand "quotes"; colon: value\\path\r\n$(touch ' + str(marker) + ')\n\n'
        result = self.provider("notes", call(1, "notes_append", name="second.md", text=payload))
        self.assertFalse(result[1]["result"]["isError"])
        self.assertEqual(result[1]["result"]["structuredContent"]["effect"],
                         {"kind":"note", "operation":"appended", "id":"second.md", "title":"Fixture"})
        self.assertNotIn("Preserve", json.dumps(result))
        self.assertEqual((notes / "second.md").read_bytes(), original + b"- " + payload.encode() + b"\n")
        self.assertEqual((notes / "first.md").read_bytes(), original)
        self.assertFalse(marker.exists())
        before = {p.name: p.read_bytes() for p in notes.iterdir()}
        for name in ("Fixture", "missing.md"):
            result = self.provider("notes", call(1, "notes_append", name=name, text="Refused body"))
            self.assertTrue(result[1]["result"]["isError"])
        for invalid in ("", "\x1bclear", "\x00", "x" * 16385):
            result = self.provider("notes", call(1, "notes_append", name="second.md", text=invalid))
            self.assertEqual(result[1]["error"]["code"], -32602)
        self.assertEqual(before, {p.name: p.read_bytes() for p in notes.iterdir()})
        (notes / "second.md").unlink()
        result = self.provider("notes", call(1, "notes_append", name="second.md", text="Stale body"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual({p.name: p.read_bytes() for p in notes.iterdir()}, {"first.md":original})

    def test_note_append_partial_payload_failure_never_reports_success(self):
        notes = self.home / "notes"
        notes.mkdir()
        original = b"# Fixture\nExisting body.\n"
        for filename in ("first.md", "second.md"):
            (notes / filename).write_bytes(original)
        bindir = self.home / "bin"
        bindir.mkdir()
        marker = self.home / "append-read-failed"
        fixture = bindir / "cat"
        fixture.write_text("#!" + sys.executable + "\n" + '''import os,pathlib,sys
a=sys.argv[1:]
if len(a)==1 and pathlib.Path(a[0]).name=='note.append':
 pathlib.Path(''' + repr(str(marker)) + ''').write_text('injected')
 os.write(1,pathlib.Path(a[0]).read_bytes()[:7])
 sys.exit(1)
os.execv(''' + repr(shutil.which("cat")) + ''', ['cat']+a)
''')
        fixture.chmod(0o755)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]
        payload = "Private full payload must never appear in the failure receipt."
        result = self.provider("notes", call(1, "notes_append", name="second.md", text=payload))[1]["result"]
        self.assertTrue(marker.exists(), "the payload copy fault must actually execute")
        self.assertTrue((notes / "second.md").read_bytes().startswith(original + b"- " + payload[:7].encode()))
        self.assertNotIn(payload.encode(), (notes / "second.md").read_bytes())
        self.assertEqual((notes / "first.md").read_bytes(), original, "a partial write must not touch another note")
        self.assertTrue(result["isError"], "a partial payload copy must never report success")
        self.assertNotIn("effect", result.get("structuredContent", {}))
        self.assertIn("check the note", json.dumps(result))
        self.assertNotIn(payload, json.dumps(result))

    def test_missing_zone_file_accepts_only_native_utc_without_dst(self):
        spec = importlib.util.spec_from_file_location("reminders", REPO / "lib/reminders.py")
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        with patch.dict(os.environ, {}, clear=True), patch.object(helper.Path, "open", side_effect=FileNotFoundError):
            for names in (("UTC", "UTC"), ("GMT", "GMT")):
                with patch.object(helper, "time", SimpleNamespace(timezone=0, altzone=0, daylight=0, tzname=names)):
                    self.assertEqual(helper.problem("209901011000"), "")
                    self.assertEqual(helper.local_zone().utcoffset(None), dt.timedelta(0))
            for settings in ({"timezone":21600, "altzone":18000, "daylight":1, "tzname":("CST","CDT")},
                             {"timezone":0, "altzone":-3600, "daylight":1, "tzname":("GMT","BST")},
                             {"timezone":0, "altzone":0, "daylight":0, "tzname":("unknown","unknown")}):
                with patch.object(helper, "time", SimpleNamespace(**settings)):
                    self.assertIn("could not be verified", helper.problem("209901011000"))
        with patch.dict(os.environ, {}, clear=True), patch.object(helper.Path, "open", side_effect=PermissionError), \
                patch.object(helper, "time", SimpleNamespace(timezone=0, altzone=0, daylight=0, tzname=("UTC","UTC"))):
            self.assertIn("could not be verified", helper.problem("209901011000"))

    def test_legacy_reminder_uid_stays_exact_through_done_restore_and_snooze(self):
        calendar = self.home / "calendar"
        calendar.mkdir()
        identity = "spark-shell-fixture@legacy-host"
        event = calendar / "legacy.ics"
        original = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:" + identity +
                    "\r\nDTSTART:20990101T100000\r\nSUMMARY:Legacy fixture\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n").encode()
        event.write_bytes(original)
        for tool, operation in (("reminders_done", "done"), ("reminders_restore", "restored"), ("reminders_snooze", "rescheduled")):
            result = self.provider("reminders", call(1, tool, name=identity))
            effect = result[1]["result"]["structuredContent"]["effect"]
            self.assertEqual((effect["id"], effect["operation"]), (identity, operation))
            if operation == "done":
                self.assertFalse(event.exists())
                self.assertEqual((calendar / "done" / event.name).read_bytes(), original)
            elif operation == "restored":
                self.assertEqual(event.read_bytes(), original)
        self.assertIn("UID:" + identity + "\n", event.read_text())
        self.assertNotIn("DTSTART:20990101T100000", event.read_text())

    def test_reminder_time_verifier_failure_never_writes(self):
        bindir = self.home / "bin"
        bindir.mkdir()
        # A broken/missing Python helper cannot be mistaken for verification.
        executable = bindir / "python3"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]
        words = "2099-01-01 10:00 Fixture"
        result = self.provider("reminders", call(2, "reminders_add", words=words))
        self.assertTrue(result[2]["result"]["isError"])
        self.assertFalse(list((self.home / "calendar").glob("*.ics")))

        executable.write_text("#!" + sys.executable + "\n" + '''import os,sys
if sys.argv[-1] == '--uid': print('fixture-host')
else: os.execv(sys.executable, [sys.executable]+sys.argv[1:])
''')
        result = self.provider("reminders", call(1, "reminders_add", words=words))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertIn("identity", result[1]["result"]["content"][0]["text"])
        self.assertFalse(list((self.home / "calendar").glob("*.ics")))

    def test_local_time_gaps_folds_and_zone_suffixes_ask_without_writing(self):
        self.env["TZ"] = "America/Chicago"
        year = max(2099, dt.datetime.now().year + 1)
        sunday = lambda month: 1 + (6 - dt.date(year, month, 1).weekday()) % 7
        words = [f"{year}-03-{sunday(3) + 7:02d} 02:30 gap fixture",
                 f"{year}-11-{sunday(11):02d} 01:30 fold fixture",
                 f"{year}-01-10 10:00 UTC zone fixture"]
        for text in words:
            result = self.provider("reminders", call(2, "reminders_add", words=text))
            self.assertTrue(result[2]["result"]["isError"], text)
            self.assertNotIn("ask-2", result, "a time that exists but cannot be kept is refused with its reason, not asked for")
            self.assertFalse(list((self.home / "calendar").glob("*.ics")))
        result = self.provider("reminders", call(1, "reminders_add", words=f"{year}-01-10 10:00 valid fixture"))
        self.assertFalse(result[1]["result"]["isError"])
        self.assertEqual(len(list((self.home / "calendar").glob("*.ics"))), 1)

    def test_spoken_reminder_timing_preserves_requested_time_and_title(self):
        tomorrow = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1)).strftime("%Y-%m-%d")
        for phrase, minute in (("tomorrow at 10:00 to review the checklist", "10:00"), ("Remind me tomorrow at 10:30 to review the checklist", "10:30")):
            result = self.provider("reminders", call(1, "reminders_add", words=phrase))
            effect = result[1]["result"]["structuredContent"]["effect"]
            self.assertEqual((effect["localTime"], effect["title"]), (f"{tomorrow} {minute}", "review the checklist"), phrase)
        saved = [p.read_text() for p in (self.home / "calendar").glob("*.ics")]
        self.assertEqual(len(saved), 2)
        for text in saved:
            self.assertIn("DTSTART:" + tomorrow.replace("-", "") + "T10", text)
            self.assertIn("SUMMARY:review the checklist\n", text)
        # the same words at the same minute again: refused with the one that exists, so a retry makes no second (#111)
        result = self.provider("reminders", call(2, "reminders_add", words="tomorrow at 10:00 to review the checklist"))
        self.assertTrue(result[2]["result"]["isError"])
        self.assertEqual(result[2]["result"]["content"][0]["text"], "tomorrow 10:00 review the checklist is a reminder already")
        self.assertEqual(len(list((self.home / "calendar").glob("*.ics"))), 2)
        # words with no time: one question over the wire (elicitation, the field when); cancelled, nothing is written
        answer = {"jsonrpc": "2.0", "id": "ask-3", "result": {"action": "cancel"}}
        result = self.provider("reminders", call(3, "reminders_add", words="Remind me to review the checklist"), answer)
        self.assertEqual(result["ask-3"]["method"], "elicitation/create")
        self.assertEqual(result["ask-3"]["params"]["message"], "When")
        self.assertEqual(result["ask-3"]["params"]["requestedSchema"]["required"], ["when"])
        self.assertTrue(result[3]["result"]["isError"])
        self.assertEqual(result[3]["result"]["content"][0]["text"], "not done: no time given")
        self.assertEqual(len(list((self.home / "calendar").glob("*.ics"))), 2)
        # answered, the time goes in front and the title is what the person asked to be reminded of
        answer = {"jsonrpc": "2.0", "id": "ask-4", "result": {"action": "accept", "content": {"when": "tomorrow 10:45"}}}
        result = self.provider("reminders", call(4, "reminders_add", words="Remind me to review the checklist"), answer)
        effect = result[4]["result"]["structuredContent"]["effect"]
        self.assertEqual((effect["localTime"], effect["title"]), (f"{tomorrow} 10:45", "review the checklist"))
        self.assertEqual(len(list((self.home / "calendar").glob("*.ics"))), 3)

    def desktop_fixture(self):
        bindir = self.home / "bin"
        bindir.mkdir()
        (bindir / "uname").write_text("#!/bin/sh\ncase $1 in -m) echo x86_64 ;; *) echo Linux ;; esac\n")
        (bindir / "uname").chmod(0o755)
        self.env.update(PATH=str(bindir) + os.pathsep + self.env["PATH"], SWAYSOCK=str(self.home / "sway.sock"))
        config = self.home / "config" / "spark-shell"
        config.mkdir(parents=True)
        (config / "config").write_text("DESKTOP=sway\nTHEME=none\n")
        return bindir

    def sound_fixture(self):
        bindir = self.desktop_fixture()
        fixture = bindir / "wpctl"
        fixture.write_text("#!" + sys.executable + "\n" + '''import json,os,pathlib,sys
p=pathlib.Path(os.environ['HOME'])/'sound.json'; s=json.loads(p.read_text()); a=sys.argv[1:]
if a[0]=='status': print('Sinks:\\n * 10. Fixture speaker [vol: 0.70]\\nSources:\\n * 20. Fixture mic [vol: 0.70]\\nStreams:')
elif a[0]=='get-volume': print('Volume: '+str(s['level']/100)+(' [MUTED]' if s['muted'] else ''))
elif a[0] in ('set-volume','set-mute'):
 if s.get('fail'): sys.exit(1)
 if s.get('noop'): sys.exit(0)
 s['lastTarget']=a[-2]
 if a[0]=='set-volume': s['level']=int(a[-1].rstrip('%'))-s.get('round',0)
 else: s['muted']=a[-1]=='1'
 p.write_text(json.dumps(s))
else: sys.exit(1)
''')
        fixture.chmod(0o755)
        state = self.home / "sound.json"
        state.write_text(json.dumps({"level":70, "muted":False}))
        return state

    def test_sound_reports_native_state_and_backend_failure(self):
        state = self.sound_fixture()
        result = self.provider("out", call(1, "out_level", level=30), call(2, "out_mute"))
        first, second = [result[n]["result"]["structuredContent"] for n in (1, 2)]
        self.assertEqual(first["effect"]["level"], 30)
        self.assertEqual(first["undo"]["arguments"]["level"], 70)
        self.assertTrue(second["effect"]["muted"])
        state.write_text(json.dumps({"level":30, "muted":True, "fail":True}))
        result = self.provider("out", call(1, "out_level", level=50))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(json.loads(state.read_text())["level"], 30)
        state.write_text(json.dumps({"level":30, "muted":False, "noop":True}))
        result = self.provider("out", call(1, "out_level", level=50))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertIn("at 30%", result[1]["result"]["content"][0]["text"])
        self.assertEqual(json.loads(state.read_text())["level"], 30)
        state.write_text(json.dumps({"level":30, "muted":False, "round":1}))
        result = self.provider("out", call(1, "out_level", level=50))
        self.assertEqual(result[1]["result"]["structuredContent"]["effect"]["level"], 49)
        self.assertIn("49%", result[1]["result"]["structuredContent"]["receipt"])

    def test_sound_relative_change_uses_native_level_and_exact_undo(self):
        state = self.sound_fixture()
        tools = self.provider("out", rpc(1, "tools/list"))[1]["result"]["tools"]
        relative = next(t for t in tools if t["name"] == "out_adjust")
        self.assertEqual(relative["inputSchema"]["properties"]["delta"], {"type":"integer", "minimum":-100, "maximum":100})
        self.assertFalse(relative["annotations"]["idempotentHint"])
        result = self.provider("out", call(1, "out_adjust", delta=-20))
        content = result[1]["result"]["structuredContent"]
        self.assertEqual(content["effect"]["level"], 50)
        self.assertEqual(json.loads(state.read_text())["level"], 50)
        self.assertEqual(content["undo"], {"name":"out_level", "arguments":{"level":70}})
        undo = content["undo"]
        self.provider("out", call(1, undo["name"], **undo["arguments"]))
        self.assertEqual(json.loads(state.read_text())["level"], 70)
        # Another client changed the volume; the next change reads it afresh.
        state.write_text(json.dumps({"level":35, "muted":False}))
        result = self.provider("out", call(1, "out_adjust", delta=10))
        self.assertEqual(result[1]["result"]["structuredContent"]["effect"]["level"], 45)
        result = self.provider("mic", call(1, "mic_adjust", delta=-20))
        self.assertEqual(result[1]["result"]["structuredContent"]["effect"]["level"], 25)
        self.assertEqual(json.loads(state.read_text())["lastTarget"], "@DEFAULT_AUDIO_SOURCE@")
        for invalid in (101, -101, 1.5, "-20"):
            result = self.provider("out", call(1, "out_adjust", delta=invalid))
            self.assertEqual(result[1]["error"]["code"], -32602)
        self.assertEqual(json.loads(state.read_text())["level"], 25)
        result = self.provider("out", call(1, "out_adjust", delta=-100), call(2, "out_adjust", delta=100))
        self.assertEqual([result[n]["result"]["structuredContent"]["effect"]["level"] for n in (1, 2)], [0, 100])
        state.write_text(json.dumps({"level":70, "muted":False, "noop":True}))
        result = self.provider("out", call(1, "out_adjust", delta=-20))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(json.loads(state.read_text())["level"], 70)
        state.write_text(json.dumps({"level":70, "muted":False}))
        cli = subprocess.run(["sh", str(PROGRAM), "panel", "out", "adjust", "-20"], env=self.env,
                             text=True, capture_output=True, timeout=15)
        self.assertEqual((cli.returncode, cli.stdout.strip()), (0, "out at 50%"))
        cli = subprocess.run(["sh", str(PROGRAM), "panel", "undo", "all"], env=self.env,
                             text=True, capture_output=True, timeout=15)
        self.assertEqual(cli.returncode, 0)
        self.assertEqual(json.loads(state.read_text())["level"], 70)

    def test_windows_use_container_ids_and_confirm_native_outcomes(self):
        bindir = self.desktop_fixture()
        fixture = bindir / "swaymsg"
        fixture.write_text("#!" + sys.executable + "\n" + '''import json,os,pathlib,re,sys
p=pathlib.Path(os.environ['HOME'])/'windows.json'; s=json.loads(p.read_text()); a=sys.argv[1:]
if a==['-t','get_tree']: print(json.dumps({'type':'root','nodes':[{'type':'output','name':'DP-1','nodes':[{'type':'workspace','name':'1','num':1,'focused':True,'nodes':s['nodes']}]}]}))
elif a==['-t','get_version']: print('{}')
elif a and a[0]=='--':
 m=re.fullmatch(r'\\[con_id=(\\d+)\\] (kill|focus)',a[1])
 if not m: print('[{"success":true}]'); sys.exit(0)
 if not s.get('decline'):
  if m[2]=='kill': s['nodes']=[n for n in s['nodes'] if n['id']!=int(m[1])]
  else:
   for n in s['nodes']: n['focused']=n['id']==int(m[1])
  p.write_text(json.dumps(s))
 print('[{"success":true}]')
else: print('[]')
''')
        fixture.chmod(0o755)
        state = self.home / "windows.json"
        state.write_text(json.dumps({"nodes":[{"id":i,"pid":i,"type":"con","app_id":"fixture","name":"Same title","focused":False} for i in (101,102)]}))
        # one row a window, close behind it by the same container ID (#144)
        rows = [r for r in self.rows("window") if r["tool"] and r["tool"]["name"] == "window_focus"]
        self.assertEqual({r["tool"]["arguments"]["name"] for r in rows}, {"101", "102"})
        self.assertEqual([[m["name"], m["arguments"]["name"]] for r in rows for m in r["more"] if m["name"] == "window_close"], [["window_close", r["tool"]["arguments"]["name"]] for r in rows])
        self.assertFalse([r for r in self.rows("window") if r["tool"] and r["tool"]["name"] == "window_close"])
        result = self.provider("window", call(1,"window_close",name="fixture"), call(2,"window_focus",name="102"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertEqual(result[2]["result"]["structuredContent"]["effect"]["id"], "102")
        self.assertTrue(next(n for n in json.loads(state.read_text())["nodes"] if n["id"]==102)["focused"])
        data=json.loads(state.read_text()); data["decline"]=True; state.write_text(json.dumps(data))
        result=self.provider("window",call(1,"window_close",name="102"))
        self.assertTrue(result[1]["result"]["isError"])
        data["decline"]=False; state.write_text(json.dumps(data))
        result=self.provider("window",call(1,"window_close",name="102"),call(2,"window_close",name="102"))
        self.assertFalse(result[1]["result"]["isError"])
        self.assertTrue(result[2]["result"]["isError"])
        self.assertEqual([n["id"] for n in json.loads(state.read_text())["nodes"]],[101])
        cli = subprocess.run(["sh", str(PROGRAM), "panel", "window", "close", "missing"], env=self.env,
                             text=True, capture_output=True, timeout=15)
        self.assertEqual(cli.returncode, 1)
        self.assertIn("no unique window", cli.stdout)

    def test_layout_without_a_window_is_not_reported_as_opened(self):
        bindir = self.desktop_fixture()
        layouts = self.home / "config" / "spark-shell" / "layouts"
        layouts.mkdir()
        (layouts / "fixture").write_text(json.dumps({"words":"fixture-app", "main":{"app":"fixture-app"}, "side":[]}))
        apps = self.home / "data" / "applications"
        apps.mkdir(parents=True)
        (apps / "fixture-app.desktop").write_text("[Desktop Entry]\nType=Application\nName=fixture-app\nExec=fixture-app\n")
        (bindir / "fixture-app").write_text("#!/bin/sh\nexit 1\n")
        (bindir / "fixture-app").chmod(0o755)
        (bindir / "pgrep").write_text("#!/bin/sh\nexit 1\n")
        (bindir / "pgrep").chmod(0o755)
        fixture = bindir / "swaymsg"
        fixture.write_text("#!/bin/sh\n" + '''case "$*" in
  '-t get_version') echo '{}' ;;
  '-t get_tree') echo '{"type":"root","nodes":[{"type":"workspace","num":1,"nodes":[]}]}' ;;
  '-t get_outputs') echo '[{"name":"HEADLESS-1","active":true,"rect":{"width":1920,"height":1080,"x":0}}]' ;;
  '-t get_workspaces') echo '[]' ;;
  *) echo '[{"success":true}]' ;;
esac
''')
        fixture.chmod(0o755)
        self.env["XDG_DATA_DIRS"] = str(self.home / "empty-data")
        result = self.provider("layout", call(1, "layout_open", name="fixture"))
        self.assertTrue(result[1]["result"]["isError"])
        self.assertNotIn("opened", result[1]["result"].get("structuredContent", {}))
        self.assertIn("no window", result[1]["result"]["content"][0]["text"])


class PlanHandling(unittest.TestCase):
    """The terminal caller holds a whole proposal before any execution."""

    def plan(self, reply, known_refused=False, use_entry=False, words="the synthetic request"):
        with tempfile.TemporaryDirectory(prefix="plan-handling-") as directory:
            home = Path(directory)
            (home / "reply.json").write_text(json.dumps(reply))
            model = home / "model"
            model.write_text('#!/bin/sh\ncase $1 in help) echo " spark steps <words>" ;; *) cat "$HOME/reply.json" ;; esac\n')
            model.chmod(0o700)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
                       XDG_STATE_HOME=str(home / "state"), XDG_DATA_HOME=str(home / "data"),
                       XDG_CACHE_HOME=str(home / "cache"), KNOWN_REFUSED=str(int(known_refused)), USE_ENTRY=str(int(use_entry)), REQUEST_WORDS=words)
            script = r'''
set -eu
. "$1/src/ask.sh"
TMP=$HOME; spark=$HOME/model; TAB=$(printf '\t'); PANEL_CROSS='!'
scrub_text() { cat; }
cut_chars() { cut -c "1-$1"; }
panel_facts() { echo 'synthetic desktop'; }
want_tools() { echo '{"tools":[]}'; }
want_name_rows() { printf 'out_use\tUSB Headset A\nout_use\tUSB Headset B\nmic_use\tUSB Mic A\nmic_use\tUSB Mic B\napps_open\tEditor A\napps_open\tEditor B\nwindow_focus\t101\tEditor\nwindow_focus\t202\tEditor\n'; }
spark_bin() { echo "$HOME/model"; }
want_names_app() { echo 'Editor A'; }
layout_words_full() { echo false; }
layout_words_ws() { :; }
SND=fixture

tool_spec() {
    _te=''; _tp=''
    case $1 in
        mic_mute) _ts=mic; _ta=mute ;;
        out_level) _ts=out; _ta=level; _tp=level ;;
        out_use) _ts=out; _ta=use; _tp=name ;;
        mic_use) _ts=mic; _ta=use; _tp=name ;;
        apps_open) _ts=apps; _ta=open; _tp=name ;;
        window_focus) _ts=window; _ta=focus; _tp=name ;;
        *) return 1 ;;
    esac
}
panel_gate() {
    if [ "$KNOWN_REFUSED" = 1 ] && [ "$1:$2" = out:use ]; then echo 'output is owned by the sound configuration'; return 1; fi
    case $1:$2 in
        mic:use) case $3 in 'USB Mic A'|'USB Mic B') printf '%s\n' "$3" ;; *) echo 'target is not in the list'; return 1 ;; esac ;;
        apps:open) case $3 in 'Editor A'|'Editor B') printf '%s\n' "$3" ;; *) echo 'target is not in the list'; return 1 ;; esac ;;
        window:focus) case $3 in 101|202) printf '%s\n' "$3" ;; *) echo 'target is not in the list'; return 1 ;; esac ;;
        out:use) case ${3:-} in 'USB Headset A'|'USB Headset B') printf '%s\n' "$3" ;; *) echo 'target is not in the list'; return 1 ;; esac ;;
        out:level) case ${3:-} in 20) echo 20 ;; *) echo 'level is outside its range'; return 1 ;; esac ;;
        mic:mute) echo '' ;;
    esac
}
: > "$TMP/plan"
if [ "$USE_ENTRY" = 1 ]; then want_plan 'open Editor A and mute the microphone'; else want_steps "$REQUEST_WORDS"; fi
cat "$TMP/plan"
'''
            result = subprocess.run(["sh", "-c", script, "plan-test", str(REPO)], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return [line.split("\x1f") for line in result.stdout.splitlines()]

    def test_target_facts_keep_active_devices_and_window_labels(self):
        with tempfile.TemporaryDirectory(prefix="target-facts-") as directory:
            script = r"""
set -eu
. "$1/src/rows.sh"
. "$1/src/ask.sh"
TMP=$2; TAB=$(printf '\t'); PANEL_DOT=dot; PANEL_RING=ring
panel_brief_sections() { printf 'out\nmic\nwindow\napps\n'; }
panel_apps_known() { echo 'Editor App'; }
panel_rows() {
    case $1 in
        out) printf 'dot\tUSB Headset A\tshow\nring\tUSB Headset B\tuse USB Headset B\n-\tmute\tmute\n' ;;
        mic) printf 'dot\tDesk Mic A\tshow\nring\tDesk Mic B\tuse Desk Mic B\n' ;;
        window) printf -- '-\tEditor One\tfocus 101\t1|Project Notes\n-\tclose Editor One\tclose 101\n' ;;
    esac
}
want_name_rows > "$TMP/want.names"
cat "$TMP/want.names"
want_names
"""
            result = subprocess.run(["sh", "-c", script, "target-facts", str(REPO), directory],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            for row in ("out_use\tUSB Headset A", "out_use\tUSB Headset B", "mic_use\tDesk Mic A", "mic_use\tDesk Mic B",
                        "window_focus\t101\tEditor One", "window_move\t101\tEditor One", "window_place\t101\tEditor One",
                        "window_close\t101\tEditor One", "apps_open\tEditor App"):
                self.assertIn(row, result.stdout)
            self.assertIn("window_focus: Editor One / Project Notes (name: 101)", result.stdout)

    def test_a_refused_part_leaves_no_terminal_action(self):
        reply = {"answer": "", "steps": [{"name": "mic_mute", "arguments": {}}],
                 "refused": ["volume change unavailable"]}
        rows = self.plan(reply)
        self.assertFalse(any(row[0] == "step" for row in rows), rows)
        self.assertTrue(any("volume change unavailable" in str(row) for row in rows), rows)

    def test_an_unresolved_target_keeps_the_whole_terminal_plan(self):
        reply = {"answer": "", "steps": [{"name": "mic_mute", "arguments": {}},
                 {"name": "out_use", "arguments": {"name": "USB Headset"}}], "refused": []}
        rows = self.plan(reply)
        self.assertFalse(any(row[0] == "step" for row in rows), rows)
        self.assertTrue(any("which output" in str(row) and "USB Headset A" in str(row)
                            and "USB Headset B" in str(row) for row in rows), rows)

    def test_a_valid_model_name_does_not_settle_an_ambiguous_request(self):
        for tool, name, words, explicit, noun in (
                ("out_use", "USB Headset A", "switch to the USB headset", "use USB Headset A", "output"),
                ("mic_use", "USB Mic A", "use the USB mic", "use USB Mic A", "microphone"),
                ("apps_open", "Editor A", "open Editor", "open Editor A", "app"),
                ("window_focus", "101", "focus Editor", "focus 101", "window")):
            with self.subTest(tool=tool):
                reply = {"answer":"", "steps":[{"name":"mic_mute", "arguments":{}},
                         {"name":tool, "arguments":{"name":name}}], "refused":[]}
                rows = self.plan(reply, words="mute the microphone and " + words)
                self.assertFalse(any(row[0] == "step" for row in rows), rows)
                self.assertTrue(any("which " + noun in str(row) for row in rows), rows)
                rows = self.plan(reply, words="mute the microphone and " + explicit)
                self.assertEqual(sum(row[0] == "step" for row in rows), 2, rows)

    def test_every_target_domain_offers_current_choices(self):
        for tool, name, noun, choices in (("mic_use", "USB Mic", "microphone", ("USB Mic A", "USB Mic B")),
                                          ("apps_open", "Editor", "app", ("Editor A", "Editor B")),
                                          ("window_focus", "Editor", "window", ("Editor (101)", "Editor (202)"))):
            with self.subTest(tool=tool):
                rows = self.plan({"answer":"", "steps":[{"name":"mic_mute", "arguments":{}},
                                  {"name":tool, "arguments":{"name":name}}], "refused":[]})
                self.assertFalse(any(row[0] == "step" for row in rows), rows)
                self.assertTrue(any("which " + noun in str(row) and all(c in str(row) for c in choices) for row in rows), rows)

    def test_known_target_keeps_the_real_failure_reason(self):
        rows = self.plan({"answer":"", "steps":[{"name":"out_use", "arguments":{"name":"USB Headset A"}}], "refused":[]}, known_refused=True)
        self.assertTrue(any("owned by the sound configuration" in str(row) for row in rows), rows)
        self.assertNotIn("which", str(rows))

    def test_an_app_in_a_compound_request_does_not_bypass_the_planner(self):
        rows = self.plan({"answer":"which Editor?", "steps":[], "refused":[]}, use_entry=True)
        self.assertEqual(rows, [["say", "which Editor?"]])

    def test_a_complete_terminal_plan_keeps_both_changes(self):
        reply = {"answer": "", "steps": [{"name": "mic_mute", "arguments": {}},
                 {"name": "out_level", "arguments": {"level": 20}}], "refused": []}
        self.assertEqual([row[:3] for row in self.plan(reply)], [["step", "mic", "mute"], ["step", "out", "level"]])

    def test_a_clarification_cannot_accompany_a_terminal_action(self):
        reply = {"answer": "which output?", "steps": [{"name": "mic_mute", "arguments": {}}], "refused": []}
        self.assertFalse(any(row[0] == "step" for row in self.plan(reply)))


if __name__ == "__main__":
    unittest.main()
