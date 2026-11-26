#!/usr/bin/env python3
"""The notifications' server: org.freedesktop.Notifications on the session bus.

  python3 lib/notifications.py STATE LOOK [DRAWER]

It keeps the list, the last ten that left and what was looked at (Book), writes them to STATE, its one writer,
and hands what shows to DRAWER (spark-bar notifications) as a JSON line each; the drawer says back what the
person did. LOOK is spark-shell's file of KEY=value lines: the drawer's colors, face and place, and do not
disturb. With no DRAWER, or one that ended five times in a minute, nothing pops up: the list is kept all the same.
It ends with the desktop it was started under: when its drawer ends and the compositor's socket is gone.

Beside the standard interface it answers seven methods of its own (OWN), for spark-shell alone: Seen(au) and
Dismiss(au), an id of 0 for every one; Restore(), the last one that left on the screen again; Reload(), LOOK read
again; Open(), the stack takes the keys; Pause() and Resume(), around the idle screen: what would pop up waits,
and shows after.
"""
import fcntl
import html
import json
import os
import re
import signal
import subprocess
import sys
import time

NAME = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
OWN = "ai.forgewright.SparkShell.Notifications"
VERSION = "1"
KEPT = 10            # the history's length
SHOWN_MOST = 50      # more than these on the screen at once: the oldest leaves
TEXT_MOST = {"app": 64, "summary": 200, "body": 1000, "category": 64, "label": 40}
KEY_MOST = 1024      # an action's key goes back to its app whole (GTK's holds the action's name and its target): a longer one is no action
ACTIONS_MOST = 4
PIPE_ROOM = 1 << 20  # the drawer's pipe: one that reads is never this far behind
TAG = re.compile(r"</?[A-Za-z][^<>]{0,200}>")
EXPIRED, DISMISSED, CLOSED = 1, 2, 3   # the reasons of NotificationClosed
TIMES = {0: 4000, 1: 6000, 2: 0}       # milliseconds on the screen by urgency; 0 stays until dismissed
TIME_MOST = 60000


def cut(value, kind):
    """A text an app sent, as a string of the most characters its kind may have. No character is judged here: what
    draws a text scrubs it (the drawer, the shell's rows)."""
    return str(value)[:TEXT_MOST[kind]]


def plain(body):
    """A body's markup read: its tags gone, its entities the characters they name. The server says it takes markup,
    as the others do, so an app sends "&amp;" for an ampersand."""
    return html.unescape(TAG.sub("", str(body)))


def born(pid="self"):
    """The clock tick a process started at, as /proc says it: with its pid, that process and no later one."""
    try:
        with open("/proc/%s/stat" % pid, encoding="utf-8", errors="replace") as f:
            return f.read().rsplit(") ", 1)[1].split()[19]
    except (OSError, IndexError):
        return ""


def desktop_socket(env):
    """The socket of the compositor a server was started under; None for a server started under none."""
    name = env.get("WAYLAND_DISPLAY")
    if not name:
        return None
    return name if os.path.isabs(name) else os.path.join(env.get("XDG_RUNTIME_DIR", ""), name)


def desktop_gone(env):
    """Whether that compositor is gone: its socket is no more. A server started under none is no desktop's."""
    path = desktop_socket(env)
    return path is not None and not os.path.exists(path)


class Book:
    """The notifications: the ones on the screen, the last that left, which were looked at. No bus and no drawer."""

    def __init__(self, last=0):
        self.last = last        # the newest id handed out
        self.shown = []         # newest first
        self.history = []       # newest first, KEPT at most
        self.seen = set()
        self.dnd = False

    def note(self, app, replaces, summary, body, actions, hints, timeout, now=None):
        """A notification as an app sent it -> its record. One that replaces one held here, on the screen or in the
        history, keeps its id."""
        try:
            urgency = int(hints.get("urgency", 1))   # a byte on the bus
        except (TypeError, ValueError, OverflowError):
            urgency = 1
        if urgency not in (0, 1, 2):
            urgency = 1
        if timeout is None or timeout < 0:
            ms = TIMES[urgency]
        else:
            ms = min(int(timeout), TIME_MOST)
        pairs = [(str(actions[i]), cut(actions[i + 1], "label")) for i in range(0, len(actions) - 1, 2)]
        pairs = [(key, label) for key, label in pairs if len(key) <= KEY_MOST][:ACTIONS_MOST]
        nid = int(replaces) if replaces and any(n["id"] == replaces for n in self.shown + self.history) else 0
        if not nid:
            self.last = self.last + 1 if self.last < 0xFFFFFFFE else 1
            nid = self.last
        return {"id": nid, "app": cut(app, "app"), "summary": cut(summary, "summary"), "body": cut(plain(body), "body"),
                "urgency": urgency, "category": cut(hints.get("category", ""), "category"), "actions": pairs, "ms": ms,
                "transient": bool(hints.get("transient", False)), "time": int(now if now is not None else time.time())}

    def pops(self, note, drawer):
        """Whether it pops up: a drawer draws it, and do not disturb lets a critical one through alone. One that
        changes a card on the screen changes it there, whatever was set since."""
        if any(n["id"] == note["id"] for n in self.shown):
            return True
        return bool(drawer) and (not self.dnd or note["urgency"] == 2)

    def add(self, note, pops):
        """The record takes its place: on the screen, or straight to the history when nothing pops it up. It is
        held once: the one it replaces goes. -> the ids that left the screen for it (more than SHOWN_MOST)."""
        self.seen.discard(note["id"])
        if not pops:
            self.keep(note)
            return []
        self.history = [n for n in self.history if n["id"] != note["id"]]
        for i, old in enumerate(self.shown):
            if old["id"] == note["id"]:
                self.shown[i] = note
                return []
        return self.place(note)

    def place(self, note):
        """In front on the screen. -> the ids that left it for the history: more than SHOWN_MOST, the oldest."""
        self.shown.insert(0, note)
        gone = self.shown[SHOWN_MOST:]
        del self.shown[SHOWN_MOST:]
        for old in gone:
            self.keep(old)
        return [old["id"] for old in gone]

    def keep(self, note):
        if note["transient"]:
            self.seen.discard(note["id"])
            return
        self.history = [n for n in self.history if n["id"] != note["id"]]
        self.history.insert(0, note)
        for old in self.history[KEPT:]:
            self.seen.discard(old["id"])
        del self.history[KEPT:]

    def close(self, nid, looked=False):
        """One on the screen leaves it for the history; LOOKED when a person's own hand sent it. -> whether it was there."""
        for i, note in enumerate(self.shown):
            if note["id"] == nid:
                del self.shown[i]
                self.keep(note)
                if looked and not note["transient"]:
                    self.seen.add(nid)
                return True
        return False

    def look(self, ids):
        """These were looked at; the id 0 among them, every one there is."""
        held = {n["id"] for n in self.shown + self.history}
        ids = {int(i) for i in ids}
        self.seen |= held if 0 in ids else held & ids

    def restore(self, drawer):
        """The last one that left is on the screen again, where it would pop up now; looked at or not, as it was.
        -> it and the ids that left the screen for it; None when none left, or it would not pop up."""
        if not self.history or not self.pops(self.history[0], drawer):
            return None
        note = self.history.pop(0)
        return note, self.place(note)

    def unseen(self):
        return len({n["id"] for n in self.shown + self.history} - self.seen)

    def state(self, pid, drawer, paused):
        """What the shell reads: the server that wrote it (its pid and when it was born; none once it ended), the
        newest id handed out, and the two lists by id, app and summary."""
        said = lambda n: {k: n[k] for k in ("id", "app", "summary")}   # noqa: E731
        return {"pid": pid, "born": born(pid) if pid else "", "last": self.last, "drawer": bool(drawer), "dnd": self.dnd,
                "paused": paused, "unseen": self.unseen(), "shown": [said(n) for n in self.shown], "history": [said(n) for n in self.history]}


def read_look(path):
    """spark-shell's KEY=value lines -> a dict; a file that is not there is an empty one."""
    look = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                key, eq, value = line.rstrip("\n").partition("=")
                if eq and key.replace("_", "").isalnum():
                    look[key.lower()] = value[:200]
    except OSError:
        pass
    return look


def write_state(path, state):
    tmp = "%s.%d" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    os.replace(tmp, path)


def last_id(path):
    """The newest id a server before this one handed out, as its state file says: no id is handed out twice while
    the file lasts (a server that ends leaves it, with nothing held)."""
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
        return max([0, int(state.get("last") or 0)] + [int(n["id"]) for n in state.get("shown", []) + state.get("history", [])])
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return 0


def serve(state_path, look_path, drawer_cmd):
    # the distro's native D-Bus bindings, as lib/bluetooth.py loads them
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        name = dbus.service.BusName(NAME, bus, do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        print("notifications: another program holds %s and shows them" % NAME, file=sys.stderr)
        return 0
    loop = GLib.MainLoop()

    class Server(dbus.service.Object):
        def __init__(self):
            super().__init__(name, PATH)
            self.book = Book(last_id(state_path))
            self.cmd = list(drawer_cmd)
            self.drawer = None
            self.buf = b""
            self.deaths = []
            self.paused = False
            self.look = {}
            self.reload()
            self.start()
            self.write()

        # --- the drawer: a child that draws what it is told and says what the person did
        def draws(self):
            """A drawer runs, or is on its way: what comes pops up."""
            return bool(self.drawer or self.cmd)

        def start(self):
            if not self.cmd or self.drawer:
                return False
            try:
                self.drawer = subprocess.Popen(self.cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
            except OSError as e:
                self.give_up("%s: %s" % (self.cmd[0], e))
                return False
            for end in (self.drawer.stdin, self.drawer.stdout):
                os.set_blocking(end.fileno(), False)   # never waited for: a drawer that hangs holds nothing up
            try:
                fcntl.fcntl(self.drawer.stdin.fileno(), getattr(fcntl, "F_SETPIPE_SZ", 1031), PIPE_ROOM)
            except OSError:
                pass
            GLib.io_add_watch(self.drawer.stdout.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.heard)
            self.tell({"look": self.look})
            for note in reversed(self.book.shown):
                self.draw(note)
            self.write()
            return False   # as a timer's callback: once

        def draw(self, note):
            """A notification handed to the drawer, unless it waits: while paused a critical one alone is drawn."""
            if not self.paused or note["urgency"] == 2:
                self.tell({"show": note})

        def tell(self, said):
            if not self.drawer:
                return
            line = (json.dumps(said, ensure_ascii=False) + "\n").encode()
            try:
                sent = os.write(self.drawer.stdin.fileno(), line)
            except BlockingIOError:
                sent = 0
            except OSError:
                return   # it is gone: its end comes over its stdout
            if sent != len(line):
                # it does not read, and a line cut short is no line: it ends, and the next one is told what shows
                self.drawer.kill()

        def heard(self, fd, condition):
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                return True
            except OSError:
                chunk = b""
            if not chunk:
                self.ended()
                return False
            self.buf += chunk
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                try:
                    said = json.loads(line)
                except ValueError:
                    continue
                if isinstance(said, dict):
                    self.did(said)
            if len(self.buf) > 65536:
                self.buf = b""
            return True

        def did(self, said):
            """What the person did, as the drawer says it: a notification's time ran out, they sent it away, they
            chose an action, or they looked at the ones on the screen."""
            nid = said.get("id")
            if said.get("event") == "expired" and isinstance(nid, int):
                if self.book.close(nid):
                    self.NotificationClosed(nid, EXPIRED)
            elif said.get("event") == "dismissed" and isinstance(nid, int):
                if self.book.close(nid, looked=True):
                    self.NotificationClosed(nid, DISMISSED)
            elif said.get("event") == "action" and isinstance(nid, int) and isinstance(said.get("key"), str):
                if any(n["id"] == nid and any(k == said["key"] for k, _ in n["actions"]) for n in self.book.shown):
                    self.ActionInvoked(nid, said["key"])
                    self.book.close(nid, looked=True)
                    self.NotificationClosed(nid, DISMISSED)
            elif said.get("event") == "seen":
                self.book.look([n["id"] for n in self.book.shown])
            else:
                return
            self.write()

        def ended(self):
            """The drawer is gone. With its compositor gone too the desktop is over, and this ends. Else it is started
            again, and after five ends within a minute nothing pops up any more."""
            gone, self.drawer = self.drawer, None
            self.buf = b""
            if gone:
                try:
                    gone.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    gone.kill()
                for end in (gone.stdin, gone.stdout):
                    try:
                        end.close()
                    except OSError:
                        pass
            if desktop_gone(os.environ):
                loop.quit()
                return
            now = time.monotonic()
            self.deaths = [t for t in self.deaths if now - t < 60] + [now]
            if len(self.deaths) >= 5:
                self.give_up("the drawer ended five times in a minute")
            elif self.cmd:
                GLib.timeout_add(500, self.start)
                self.write()

        def give_up(self, why):
            """Nothing pops up any more: what was on the screen goes to the list, not looked at, and its apps hear so."""
            self.cmd = []
            for note in list(self.book.shown):
                self.book.close(note["id"])
                self.NotificationClosed(note["id"], EXPIRED)
            print("notifications: %s: nothing pops up until the next login" % why, file=sys.stderr)
            self.write()

        def left(self, ids, reason):
            """These left the screen: the drawer and their apps are told."""
            for nid in ids:
                self.tell({"close": nid})
                self.NotificationClosed(nid, reason)

        def write(self):
            try:
                write_state(state_path, self.book.state(os.getpid(), self.draws(), self.paused))
            except OSError as e:
                print("notifications: %s: %s" % (state_path, e), file=sys.stderr)

        def reload(self):
            self.look = read_look(look_path)
            self.book.dnd = self.look.get("dnd") == "yes"

        # --- org.freedesktop.Notifications
        @dbus.service.method(NAME, in_signature="", out_signature="as")
        def GetCapabilities(self):
            return ["actions", "body", "body-markup"]   # markup is read and dropped (plain): the card is plain text

        # byte_arrays: a picture among the hints comes as one string of bytes, never an object a byte
        @dbus.service.method(NAME, in_signature="susssasa{sv}i", out_signature="u", byte_arrays=True)
        def Notify(self, app, replaces, icon, summary, body, actions, hints, timeout):
            note = self.book.note(app, int(replaces), summary, body, [str(a) for a in actions], dict(hints), int(timeout))
            pops = self.book.pops(note, self.draws())
            self.left(self.book.add(note, pops), EXPIRED)
            if pops:
                self.draw(note)
            else:
                GLib.idle_add(self.held, note["id"])   # after the answer: the app knows its id before it hears the end
            self.write()
            return dbus.UInt32(note["id"])

        def held(self, nid):
            self.NotificationClosed(nid, EXPIRED)
            return False

        @dbus.service.method(NAME, in_signature="u", out_signature="")
        def CloseNotification(self, nid):
            if self.book.close(int(nid)):
                self.left([int(nid)], CLOSED)
                self.write()

        @dbus.service.method(NAME, in_signature="", out_signature="ssss")
        def GetServerInformation(self):
            return ("spark-shell", "forgewright", VERSION, "1.2")

        @dbus.service.signal(NAME, signature="uu")
        def NotificationClosed(self, nid, reason):
            pass

        @dbus.service.signal(NAME, signature="us")
        def ActionInvoked(self, nid, key):
            pass

        # --- spark-shell's own
        @dbus.service.method(OWN, in_signature="au", out_signature="")
        def Seen(self, ids):
            self.book.look([int(i) for i in ids])
            self.write()

        @dbus.service.method(OWN, in_signature="au", out_signature="")
        def Dismiss(self, ids):
            """The person sent these away from the screen by a step of spark-shell's: looked at, and their apps hear
            a person dismissed them."""
            ids = {int(i) for i in ids}
            gone = [n["id"] for n in self.book.shown if 0 in ids or n["id"] in ids]
            for nid in gone:
                self.book.close(nid, looked=True)
            self.left(gone, DISMISSED)
            self.write()

        @dbus.service.method(OWN, in_signature="", out_signature="b")
        def Restore(self):
            back = self.book.restore(self.draws())
            if back is None:
                return False
            note, gone = back
            self.left(gone, EXPIRED)
            self.draw(note)
            self.write()
            return True

        @dbus.service.method(OWN, in_signature="", out_signature="")
        def Reload(self):
            self.reload()
            self.tell({"look": self.look})
            self.write()

        @dbus.service.method(OWN, in_signature="", out_signature="")
        def Open(self):
            self.tell({"open": True})

        @dbus.service.method(OWN, in_signature="", out_signature="")
        def Pause(self):
            """The idle screen is up: what is on the screen leaves it and waits here, with what comes meanwhile. A
            critical one stays in sight."""
            if not self.paused:
                self.paused = True
                for note in self.book.shown:
                    if note["urgency"] != 2:
                        self.tell({"close": note["id"]})
                self.write()

        @dbus.service.method(OWN, in_signature="", out_signature="")
        def Resume(self):
            """The person is back: what waited shows, each with its whole time."""
            if self.paused:
                self.paused = False
                for note in reversed(self.book.shown):
                    if note["urgency"] != 2:
                        self.tell({"show": note})
                self.write()

    server = Server()

    def end(*_):
        loop.quit()
        return False

    try:   # GLib 2.80 moved it to a namespace of its own
        import gi
        gi.require_version("GLibUnix", "2.0")
        from gi.repository import GLibUnix
        take = GLibUnix.signal_add
    except (ImportError, ValueError, AttributeError):
        take = GLib.unix_signal_add
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        take(GLib.PRIORITY_DEFAULT, sig, end)
    # the server is its desktop's, with a drawer or with none: it ends when the compositor's socket goes
    watch = None
    if desktop_socket(os.environ):
        try:
            from gi.repository import Gio
            watch = Gio.File.new_for_path(desktop_socket(os.environ)).monitor_file(Gio.FileMonitorFlags.NONE, None)
            watch.connect("changed", lambda _m, _f, _o, event: event == Gio.FileMonitorEvent.DELETED and end())
        except (ImportError, GLib.Error) as e:   # no watch: the drawer's end says so, where there is one
            print("notifications: the compositor's socket is not watched: %s" % e, file=sys.stderr)
    bus.add_signal_receiver(end, signal_name="Disconnected", dbus_interface="org.freedesktop.DBus.Local")
    bus.set_exit_on_disconnect(False)
    try:
        loop.run()
    finally:
        if watch:
            watch.cancel()
        if server.drawer:
            server.cmd = []
            try:
                server.drawer.terminate()
                server.drawer.wait(timeout=2)
            except (OSError, subprocess.TimeoutExpired):
                pass
        try:   # no server and nothing held: the file stays for the newest id, which the next server goes on from
            write_state(state_path, Book(server.book.last).state(None, None, False))
        except OSError:
            pass
    return 0


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    return serve(argv[1], argv[2], argv[3:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
