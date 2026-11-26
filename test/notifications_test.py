#!/usr/bin/env python3
"""The notifications' list (lib/notifications.py's Book): what pops up, what waits in the history, what was
looked at, and the state the shell reads. No bus and no drawer."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("notifications", REPO / "lib" / "notifications.py")
notifications = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notifications)
Book = notifications.Book


def note(book, summary="hello", replaces=0, urgency=None, timeout=-1, actions=(), **hints):
    if urgency is not None:
        hints["urgency"] = urgency
    return book.note("mail", replaces, summary, "a body", list(actions), hints, timeout, now=100)


class Records(unittest.TestCase):
    def test_a_record_takes_the_urgency_its_time_and_its_actions(self):
        book = Book()
        n = note(book, actions=["default", "Open", "reply", "Reply", "odd"])
        self.assertEqual((n["id"], n["urgency"], n["ms"]), (1, 1, 6000))
        self.assertEqual(n["actions"], [("default", "Open"), ("reply", "Reply")])
        self.assertEqual((note(book, urgency=0)["ms"], note(book, urgency=2)["ms"]), (4000, 0))
        self.assertEqual(note(book, urgency=7)["urgency"], 1, "an urgency that is none of the three is normal")
        self.assertEqual((note(book, urgency=b"\x02"[0])["urgency"], note(book, urgency="loud")["urgency"]), (2, 1), "a byte, as the bus sends it")
        self.assertEqual((note(book, timeout=1500)["ms"], note(book, timeout=10**9)["ms"], note(book, timeout=0)["ms"]), (1500, 60000, 0))
        self.assertEqual(note(book, category="email.arrived", transient=True)["category"], "email.arrived")

    def test_texts_are_cut_to_their_most(self):
        book = Book()
        n = book.note("a" * 500, 0, "s" * 500, "b" * 5000, ["k" * 500, "w" * 500] * 9, {"category": "c" * 500}, -1)
        self.assertEqual([len(n[k]) for k in ("app", "summary", "body", "category")], [64, 200, 1000, 64])
        self.assertEqual((len(n["actions"]), len(n["actions"][0][0]), len(n["actions"][0][1])), (4, 500, 40), "a key goes back to its app whole")
        long = book.note("a", 0, "s", "", ["k" * 1025, "too long", "app.show(('room', 'thread'))", "Open"], {}, -1)
        self.assertEqual(long["actions"], [("app.show(('room', 'thread'))", "Open")], "a key longer than any app's is no action")

    def test_a_body_with_markup_is_plain_text(self):
        book = Book()
        body = lambda text: book.note("a", 0, "s", text, [], {}, -1)["body"]   # noqa: E731
        self.assertEqual(body("<b>Ana</b> &amp; <a href=\"https://x\">Bo</a> &lt;3"), "Ana & Bo <3")
        self.assertEqual(body("if a < b and b > c"), "if a < b and b > c", "a sign that opens no tag stays")
        self.assertEqual(body("&lt;b&gt;"), "<b>", "an entity is a character, never a tag")

    def test_ids_go_up_and_one_that_replaces_a_shown_one_keeps_its_id(self):
        book = Book(last=41)
        first = note(book)
        book.add(first, True)
        again = note(book, "saved", replaces=first["id"])
        self.assertEqual((first["id"], again["id"]), (42, 42))
        book.add(again, True)
        self.assertEqual([n["summary"] for n in book.shown], ["saved"])
        self.assertEqual(note(book, replaces=7)["id"], 43, "one that names a notification not held here is a new one")
        book.close(42)
        self.assertEqual(note(book, "again", replaces=42)["id"], 42, "one in the history keeps its id too")
        self.assertEqual(note(book, urgency=float("inf"))["urgency"], 1)


class Places(unittest.TestCase):
    def test_what_pops_up_and_what_goes_straight_to_the_history(self):
        book = Book()
        self.assertTrue(book.pops(note(book), drawer=object()))
        self.assertFalse(book.pops(note(book), drawer=None), "no drawer: nothing pops up")
        book.dnd = True
        self.assertFalse(book.pops(note(book), drawer=object()))
        self.assertTrue(book.pops(note(book, urgency=2), drawer=object()), "a critical one shows under do not disturb")
        held = note(book)
        self.assertEqual(book.add(held, False), [])
        self.assertEqual((book.shown, [n["id"] for n in book.history], book.unseen()), ([], [held["id"]], 1))

    def test_one_that_changes_another_is_held_once(self):
        book = Book()
        low = note(book, "Battery low", urgency=2)
        book.add(low, True)
        book.dnd = True
        # do not disturb came on since: the card on the screen changes where it is, and no copy goes to the history
        charging = note(book, "Charging", replaces=low["id"])
        pops = book.pops(charging, drawer=object())
        book.add(charging, pops)
        self.assertEqual((pops, [n["summary"] for n in book.shown], book.history), (True, ["Charging"], []))
        # a progress said twelve times under do not disturb is one row of the history
        first = note(book, "0%")
        book.add(first, book.pops(first, drawer=object()))
        for i in range(1, 12):
            step = note(book, "%d%%" % (i * 9), replaces=first["id"])
            self.assertEqual(step["id"], first["id"])
            book.add(step, book.pops(step, drawer=object()))
        self.assertEqual(([n["summary"] for n in book.history], book.unseen()), (["99%"], 2))
        # do not disturb off: the next change of it pops up, and leaves the history
        book.dnd = False
        done = note(book, "done", replaces=first["id"])
        book.add(done, book.pops(done, drawer=object()))
        self.assertEqual(([n["summary"] for n in book.shown], book.history), (["done", "Charging"], []))

    def test_the_history_keeps_the_ten_newest_and_no_transient_one(self):
        book = Book()
        for i in range(13):
            n = note(book, "n%d" % i)
            book.add(n, True)
            self.assertTrue(book.close(n["id"]))
        self.assertEqual([n["summary"] for n in book.history], ["n%d" % i for i in range(12, 2, -1)])
        gone = note(book, transient=True)
        book.add(gone, True)
        book.close(gone["id"], looked=True)
        self.assertEqual((len(book.history), book.unseen()), (10, 10))
        self.assertFalse(book.close(999))

    def test_more_than_the_screen_holds_and_the_oldest_leave(self):
        book = Book()
        left = []
        for i in range(notifications.SHOWN_MOST + 2):
            n = note(book)
            left += book.add(n, True)
        self.assertEqual((left, len(book.shown), [n["id"] for n in book.history]), ([1, 2], notifications.SHOWN_MOST, [2, 1]))

    def test_looked_at_by_a_hand_by_its_id_and_all_at_once(self):
        book = Book()
        ids = []
        for _ in range(4):
            n = note(book)
            book.add(n, True)
            ids.append(n["id"])
        book.close(ids[0], looked=True)
        book.close(ids[1])
        self.assertEqual(book.unseen(), 3, "one a person sent away is looked at; one whose time ran out is not")
        book.look([ids[1], 77])
        self.assertEqual(book.unseen(), 2)
        book.look([0])
        self.assertEqual(book.unseen(), 0)
        again = note(book, replaces=ids[2])
        book.add(again, True)
        self.assertEqual(book.unseen(), 1, "one that changed is not looked at yet")
        book.look([])
        self.assertEqual(book.unseen(), 1, "none named is none looked at")
        book.look([0])
        self.assertEqual(book.unseen(), 0)

    def test_the_last_one_that_left_comes_back(self):
        book = Book()
        self.assertIsNone(book.restore(object()))
        for s in ("first", "second"):
            n = note(book, s)
            book.add(n, True)
            book.close(n["id"], looked=True)
        book.dnd = True
        self.assertIsNone(book.restore(object()), "it would not pop up: it stays in the history")
        self.assertEqual(([n["summary"] for n in book.history], book.unseen()), (["second", "first"], 0))
        book.dnd = False
        self.assertIsNone(book.restore(None), "no drawer: the same")
        back, gone = book.restore(object())
        self.assertEqual((back["summary"], gone, [n["summary"] for n in book.shown], [n["summary"] for n in book.history], book.unseen()),
                         ("second", [], ["second"], ["first"], 0), "looked at as it was")


class Files(unittest.TestCase):
    def test_the_state_is_what_the_shell_reads_and_the_next_server_starts_after_its_ids(self):
        book = Book()
        a, b = note(book, "on the screen"), note(book, "left")
        book.add(a, True)
        book.add(b, True)
        book.close(b["id"])
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "state")
            notifications.write_state(path, book.state(4242, drawer=object(), paused=False))
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            state = json.loads(Path(path).read_text())
            self.assertEqual((state["pid"], state["drawer"], state["dnd"], state["paused"], state["unseen"]), (4242, True, False, False, 2))
            self.assertEqual([(n["id"], n["summary"]) for n in state["shown"]], [(1, "on the screen")])
            self.assertEqual([(n["id"], n["app"]) for n in state["history"]], [(2, "mail")])
            self.assertEqual(sorted(state["shown"][0]), ["app", "id", "summary"], "what a reader reads, and no more")
            self.assertEqual((state["last"], state["born"]), (2, notifications.born(4242)))
            self.assertEqual(notifications.last_id(path), 2)
            # a server that ended: no pid, nothing held, and the newest id for the next one
            notifications.write_state(path, Book(7).state(None, None, False))
            ended = json.loads(Path(path).read_text())
            self.assertEqual((ended["pid"], ended["born"], ended["shown"], ended["history"], ended["unseen"]), (None, "", [], [], 0))
            self.assertEqual(notifications.last_id(path), 7)
            self.assertEqual(os.listdir(tmp), ["state"], "written whole, no part left beside it")
            Path(path).write_text("{ not json")
            self.assertEqual(notifications.last_id(path), 0)
        self.assertEqual(notifications.last_id("/nonexistent/state"), 0)

    def test_a_process_is_known_by_its_pid_and_its_birth(self):
        mine = notifications.born(os.getpid())
        self.assertTrue(mine.isdigit() and mine == notifications.born("self") == notifications.born(os.getpid()))
        self.assertNotEqual(mine, notifications.born(1))
        self.assertEqual(notifications.born(2 ** 22 + 7), "", "no such process")

    def test_the_desktop_is_gone_when_its_socket_is(self):
        gone = notifications.desktop_gone
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "wayland-1").write_text("")
            self.assertFalse(gone({"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": tmp}))
            self.assertFalse(gone({"WAYLAND_DISPLAY": os.path.join(tmp, "wayland-1")}))
            self.assertTrue(gone({"WAYLAND_DISPLAY": "wayland-2", "XDG_RUNTIME_DIR": tmp}))
            self.assertTrue(gone({"WAYLAND_DISPLAY": os.path.join(tmp, "wayland-2")}))
            self.assertFalse(gone({"XDG_RUNTIME_DIR": tmp}), "started under no desktop: none to end with")

    def test_the_look_is_key_value_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "look")
            Path(path).write_text("fg=aaaaaa\nFONT=Monaspace Neon 12\ndnd=yes\nno equals\n=novalue\nbad key=1\nwidth=360\n")
            self.assertEqual(notifications.read_look(path), {"fg": "aaaaaa", "font": "Monaspace Neon 12", "dnd": "yes", "width": "360"})
        self.assertEqual(notifications.read_look("/nonexistent/look"), {})


if __name__ == "__main__":
    unittest.main()
