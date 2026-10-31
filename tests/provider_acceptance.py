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

    def provider(self, section, *requests):
        packets = [rpc(0, "initialize", protocolVersion="2025-06-18", capabilities={})] + list(requests)
        result = subprocess.run(["sh", str(PROGRAM), "provide", section], env=self.env,
                                input="".join(json.dumps(p) + "\n" for p in packets),
                                text=True, capture_output=True, timeout=45)
        self.assertEqual(result.returncode, 0, "provider process failed")
        replies = {p["id"]: p for p in map(json.loads, result.stdout.splitlines()) if "id" in p}
        self.assertTrue(all(p["id"] in replies for p in requests if "method" in p), "provider missed a reply")
        return replies

    def rows(self, section):
        reply = self.provider(section, rpc(1, "resources/read", uri=f"spark-shell://{section}/rows"))
        return json.loads(reply[1]["result"]["contents"][0]["text"])["rows"]

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
        direct = [r for r in rows if r.get("tool") and r["tool"]["name"] == "notes_append"]
        self.assertEqual({r["tool"]["arguments"]["name"] for r in direct}, {"first.md", "second.md"})
        self.assertTrue(all(r["tool"]["ask"] == ["text"] for r in direct))
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
        spec = importlib.util.spec_from_file_location("reminder_time", REPO / "lib/reminder_time.py")
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
if a==['-t','get_tree']: print(json.dumps({'type':'root','nodes':s['nodes']}))
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
        self.assertEqual([[m["name"], m["arguments"]["name"]] for r in rows for m in r["more"]], [["window_close", r["tool"]["arguments"]["name"]] for r in rows])
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


if __name__ == "__main__":
    unittest.main()
