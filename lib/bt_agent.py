#!/usr/bin/env python3
"""One BlueZ pairing agent for one chosen device. No default agent or daemon.

The dialog's questions cross a private socket. Submitted codes stay in memory.
The request file holds only the question and is removed after it is sent.
"""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import sys
import time
import uuid


class Rejected(Exception):
    pass


def response_value(kind, result):
    if not isinstance(result, dict) or result.get("action") != "accept":
        raise Rejected("pairing cancelled")
    content = result.get("content", {})
    if not isinstance(content, dict):
        raise Rejected("pairing response is invalid")
    value = content.get("answer")
    if kind in ("confirm", "display"):
        if value is not True:
            raise Rejected("pairing declined")
        return None
    if not isinstance(value, str):
        raise Rejected("a pairing code is required")
    if kind == "passkey":
        if not re.fullmatch(r"[0-9]{1,6}", value):
            raise Rejected("the passkey is one to six digits")
        return int(value)
    if not re.fullmatch(r"[\x20-\x7e]{1,16}", value):
        raise Rejected("the PIN is one to sixteen plain characters")
    return value


class Bridge:
    def __init__(self, folder=None):
        self.folder = Path(folder) if folder else None
        self.server = None
        self.busy = False
        self.display_id = None
        if self.folder:
            self.server = socket.socket(socket.AF_UNIX)
            self.server.bind(str(self.folder / "bt.sock"))
            os.chmod(self.folder / "bt.sock", 0o600)
            self.server.listen(1)

    def publish(self, kind, message):
        request_id = "bt-pair-" + uuid.uuid4().hex
        request = {"jsonrpc": "2.0", "id": request_id, "method": "spark-shell/pairing", "params": {"kind": kind, "message": message}}
        temp = self.folder / "bt.ask.new"
        temp.write_text(json.dumps(request) + "\n", encoding="utf-8")
        os.chmod(temp, 0o600)
        temp.replace(self.folder / "bt.ask")
        return request_id

    def show(self, message):
        # Display callbacks must return immediately so BlueZ can finish pairing.
        if self.server:
            self.display_id = self.publish("display", message)
        else:
            self.display_id = "tty"
            print(message, file=sys.stderr)

    def dismiss(self):
        if self.display_id and self.server:
            self.publish("dismiss", "")
        self.display_id = None

    def receive(self):
        if not self.server or not select.select([self.server], [], [], 0)[0]:
            return None
        conn, _ = self.server.accept()
        with conn:
            conn.settimeout(2)
            data = bytearray()
            while len(data) <= 4096 and not data.endswith(b"\n"):
                part = conn.recv(4097 - len(data))
                if not part:
                    break
                data.extend(part)
            try:
                result = json.loads(data)
                return result if isinstance(result, dict) else None
            except (ValueError, UnicodeError):
                return None

    def poll_display(self):
        if self.display_id:
            reply = self.receive()
            if reply and reply.get("id") == self.display_id:
                response_value("display", reply.get("result", {}))

    def ask(self, kind, message, pump=lambda: None):
        if self.busy:
            raise Rejected("another pairing question is pending")
        self.busy = True
        try:
            return self._ask(kind, message, pump)
        finally:
            self.busy = False

    def _ask(self, kind, message, pump):
        if not self.server:
            try:
                with open("/dev/tty", "r+") as tty:
                    if kind in ("confirm", "display"):
                        tty.write(message + " [yes/no]: "); tty.flush()
                        value = tty.readline().strip() == "yes"
                    else:
                        value = getpass.getpass(message + ": ", stream=tty)
                return response_value(kind, {"action": "accept", "content": {"answer": value}})
            except OSError as exc:
                raise Rejected("pairing needs an interactive client") from exc
        request_id = self.publish(kind, message)
        end = time.monotonic() + 120
        while time.monotonic() < end:
            pump()
            if not self.folder.exists() or (self.folder / "bt.cancel").exists():
                raise Rejected("pairing cancelled")
            if not select.select([self.server], [], [], 0.1)[0]:
                continue
            reply = self.receive()
            if reply and reply.get("id") == request_id:
                return response_value(kind, reply.get("result", {}))
        raise Rejected("pairing timed out")

    def close(self):
        if self.server:
            self.server.close()
            for name in ("bt.sock", "bt.ask", "bt.ask.new"):
                (self.folder / name).unlink(missing_ok=True)


def reply(folder):
    data = sys.stdin.buffer.read(4097)
    if len(data) > 4096:
        return 1
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(2)
        client.connect(str(Path(folder) / "bt.sock"))
        client.sendall(data.rstrip(b"\n") + b"\n")
    return 0


def pair(address, folder=None):
    # These are the distro's native D-Bus bindings, loaded only on Linux.
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    objects = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager").GetManagedObjects()
    paths = [path for path, interfaces in objects.items()
             if str(interfaces.get("org.bluez.Device1", {}).get("Address", "")).lower() == address.lower()]
    if len(paths) != 1:
        raise Rejected("the chosen device is missing or belongs to more than one adapter")
    target = paths[0]
    device = dbus.Interface(bus.get_object("org.bluez", target), "org.bluez.Device1")
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    bridge = Bridge(folder)
    loop = GLib.MainLoop()
    outcome = {"paired": False, "cancelled": False, "error": "pairing did not finish"}

    class AgentRejected(dbus.DBusException):
        _dbus_error_name = "org.bluez.Error.Rejected"

    class Agent(dbus.service.Object):
        def check(self, path):
            if path != target or outcome["cancelled"]:
                raise AgentRejected("this agent belongs to the chosen device only")

        def ask(self, path, kind, message):
            self.check(path)
            def pump():
                context = GLib.MainContext.default()
                while context.pending():
                    context.iteration(False)
                if outcome["cancelled"]:
                    raise Rejected("pairing cancelled")
            try:
                return bridge.ask(kind, message, pump)
            except Rejected as exc:
                raise AgentRejected(str(exc)) from exc

        @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
        def Release(self):
            outcome["cancelled"] = True
            loop.quit()

        @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
        def RequestPinCode(self, path):
            return self.ask(path, "pin", "Enter the PIN shown by the chosen device")

        @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
        def RequestPasskey(self, path):
            return dbus.UInt32(self.ask(path, "passkey", "Enter the passkey shown by the chosen device"))

        @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
        def RequestConfirmation(self, path, passkey):
            self.ask(path, "confirm", "Does the chosen device show %06d?" % passkey)

        @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
        def DisplayPinCode(self, path, pin):
            self.check(path)
            bridge.show("Type %s on the chosen device" % pin)

        @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
        def DisplayPasskey(self, path, passkey, entered):
            self.check(path)
            # BlueZ repeats this callback for keys already entered; show once.
            if not entered:
                bridge.show("Type %06d on the chosen device" % passkey)

        @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
        def RequestAuthorization(self, path):
            self.ask(path, "confirm", "Allow pairing with the chosen device?")

        @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
        def AuthorizeService(self, path, service):
            self.ask(path, "confirm", "Allow the chosen device to use service %s?" % service)

        @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
        def Cancel(self):
            if bridge.display_id:
                bridge.dismiss()
            else:
                outcome["cancelled"] = True
                loop.quit()

    def failed(error):
        outcome["error"] = str(error).split(":", 1)[-1].strip()
        outcome["cancelled"] = True
        loop.quit()

    def done():
        outcome["paired"] = True
        loop.quit()

    def cancel(*_):
        outcome["cancelled"] = True
        device.CancelPairing(reply_handler=lambda: None, error_handler=lambda _: None)
        loop.quit()
        return False

    def disconnected():
        if folder and (not Path(folder).exists() or (Path(folder) / "bt.cancel").exists()):
            return cancel()
        try:
            bridge.poll_display()
        except (Rejected, OSError):
            return cancel()
        return True

    agent_path = "/org/forgewright/SparkPairing"
    agent = Agent(bus, agent_path)
    registered = False
    try:
        manager.RegisterAgent(agent_path, "KeyboardDisplay")
        registered = True
        # No RequestDefaultAgent: other apps and incoming devices keep theirs.
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            signal.signal(signum, cancel)
        GLib.timeout_add_seconds(120, cancel)
        GLib.timeout_add(100, disconnected)
        device.Pair(reply_handler=done, error_handler=failed, timeout=120)
        loop.run()
        if not outcome["paired"] or outcome["cancelled"]:
            raise Rejected(outcome["error"])
        paired = dbus.Interface(bus.get_object("org.bluez", target), "org.freedesktop.DBus.Properties").Get("org.bluez.Device1", "Paired")
        if not paired:
            raise Rejected("the native device did not report a completed pairing")
        return 0
    finally:
        if registered:
            try:
                manager.UnregisterAgent(agent_path)
            except dbus.DBusException:
                pass
        bridge.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address", nargs="?")
    parser.add_argument("--bridge")
    parser.add_argument("--reply")
    args = parser.parse_args()
    try:
        if args.reply:
            return reply(args.reply)
        if not args.address or not re.fullmatch(r"[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}", args.address):
            raise Rejected("choose a Bluetooth device first")
        return pair(args.address, args.bridge)
    except ImportError:
        print("pairing needs the native Python D-Bus bindings (spark-shell on desktop)", file=sys.stderr)
    except (Rejected, OSError) as exc:
        print(str(exc), file=sys.stderr)
    except Exception:
        print("Bluetooth pairing failed; check the native service and permissions", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
