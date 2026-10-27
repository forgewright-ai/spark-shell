#!/usr/bin/env python3
"""Pairing response policy and the private reply socket, without a radio."""
import importlib.util
import json
import os
import queue
import shutil
import subprocess
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
import unittest
from types import ModuleType, SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("bt_agent", REPO / "lib/bt_agent.py")
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class Pairing(unittest.TestCase):
    def test_codes_and_confirmation_require_explicit_valid_answers(self):
        answer = lambda value: {"action": "accept", "content": {"answer": value}}
        self.assertEqual(agent.response_value("pin", answer("aB12")), "aB12")
        self.assertEqual(agent.response_value("passkey", answer("000042")), 42)
        self.assertIsNone(agent.response_value("confirm", answer(True)))
        for kind, value in [("confirm", False), ("confirm", "yes"), ("passkey", "1234567"), ("pin", "bad\ncode"), ("passkey", "1;exec")]:
            with self.subTest(kind=kind, value=value), self.assertRaises(agent.Rejected):
                agent.response_value(kind, answer(value))
        for result in [{"action": "cancel"}, {"action": "decline"}, [], {"action": "accept", "content": []}]:
            with self.assertRaises(agent.Rejected):
                agent.response_value("pin", result)

    def test_only_the_matching_reply_reaches_the_pending_question(self):
        with tempfile.TemporaryDirectory() as folder:
            bridge = agent.Bridge(folder)
            result = []
            def ask():
                result.append(bridge.ask("pin", "Enter the device PIN"))
            thread = threading.Thread(target=ask)
            thread.start()
            request = Path(folder) / "bt.ask"
            deadline = time.monotonic() + 3
            while not request.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            body = json.loads(request.read_text())
            self.assertEqual(body["method"], "spark-shell/pairing")
            self.assertEqual(os.stat(Path(folder) / "bt.sock").st_mode & 0o777, 0o600)
            for request_id, value in [("bt-pair-unrelated", "bad"), (body["id"], "aB12")]:
                with socket.socket(socket.AF_UNIX) as peer:
                    peer.connect(str(Path(folder) / "bt.sock"))
                    peer.sendall((json.dumps({"id": request_id, "result": {"action": "accept", "content": {"answer": value}}}) + "\n").encode())
            thread.join(3)
            self.assertFalse(thread.is_alive())
            self.assertEqual(result, ["aB12"])
            for f in Path(folder).iterdir():
                if f.is_file():
                    self.assertNotIn("aB12", f.read_text())
            bridge.close()
            self.assertFalse(list(Path(folder).iterdir()))

    def test_cancel_stops_waiting_for_a_reply(self):
        with tempfile.TemporaryDirectory() as folder:
            bridge = agent.Bridge(folder)
            (Path(folder) / "bt.cancel").touch()
            with self.assertRaises(agent.Rejected):
                bridge.ask("confirm", "Confirm device code")
            bridge.close()


class NativeAgent(unittest.TestCase):
    def test_native_agent_is_scoped_and_unregistered_after_pairing(self):
        state = {}
        target = "/org/bluez/hci0/dev_00_11_22_33_44_55"
        dbus = ModuleType("dbus")
        service = ModuleType("dbus.service")
        mainloop = ModuleType("dbus.mainloop")
        glib = ModuleType("dbus.mainloop.glib")
        gi = ModuleType("gi")
        repository = ModuleType("gi.repository")
        class DBusError(Exception):
            pass
        class Object:
            def __init__(self, bus, path):
                state["agent"] = self
        class Interface:
            def GetManagedObjects(self):
                return {target: {"org.bluez.Device1": {"Address": "00:11:22:33:44:55"}}}
            def RegisterAgent(self, path, capability):
                state["registered"] = (path, capability)
            def UnregisterAgent(self, path):
                state["unregistered"] = path
            def RequestDefaultAgent(self, path):
                raise AssertionError("never replace another app's default agent")
            def Pair(self, reply_handler, error_handler, timeout):
                state["done"] = reply_handler
            def Get(self, interface, prop):
                return True
        test = self
        class Loop:
            def run(self):
                native = state["agent"]
                with test.assertRaises(DBusError):
                    native.RequestConfirmation("/org/bluez/another_device", 123456)
                native.RequestConfirmation(target, 123456)
                test.assertEqual(native.RequestPinCode(target), "aB12")
                test.assertEqual(native.RequestPasskey(target), 42)
                native.DisplayPasskey(target, 42, 0)
                test.assertEqual(state["display"], "Type 000042 on the chosen device")
                native.Cancel()  # BlueZ dismisses a code after entry; this is not failure.
                test.assertTrue(state["dismissed"])
                state["done"]()
            def quit(self):
                pass
        class FakeBridge:
            def __init__(self, folder):
                self.display_id = None
            def show(self, message):
                self.display_id = "display"
                state["display"] = message
            def dismiss(self):
                self.display_id = None
                state["dismissed"] = True
            def ask(self, kind, message, pump):
                state.setdefault("questions", []).append((kind, message))
                return {"pin": "aB12", "passkey": 42}.get(kind)
            def close(self):
                state["closed"] = True
        dbus.service = service
        dbus.DBusException = DBusError
        dbus.UInt32 = int
        dbus.SystemBus = lambda: SimpleNamespace(get_object=lambda *args: None)
        dbus.Interface = lambda *args: Interface()
        service.Object = Object
        service.method = lambda *args, **kwargs: (lambda fn: fn)
        glib.DBusGMainLoop = lambda **kwargs: None
        repository.GLib = SimpleNamespace(MainLoop=Loop, timeout_add_seconds=lambda *args: None, timeout_add=lambda *args: None)
        modules = {"dbus": dbus, "dbus.service": service, "dbus.mainloop": mainloop,
                   "dbus.mainloop.glib": glib, "gi": gi, "gi.repository": repository}
        with patch.dict(sys.modules, modules), patch.object(agent, "Bridge", FakeBridge), patch.object(agent.signal, "signal"):
            self.assertEqual(agent.pair("00:11:22:33:44:55"), 0)
        self.assertEqual(state["registered"][1], "KeyboardDisplay")
        self.assertEqual(state["unregistered"], state["registered"][0])
        self.assertTrue(state["closed"])
        self.assertEqual(len(state["questions"]), 3)


class ProviderPairing(unittest.TestCase):
    def test_mcp_question_reaches_the_native_tool_and_cancel_does_not_trust(self):
        for accept in (True, False, None):
            with self.subTest(accept=accept), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                repo = root / "repo"
                repo.mkdir()
                for name in ("spark-shell", "config.example"):
                    shutil.copy2(REPO / name, repo / name)
                shutil.copytree(REPO / "themes", repo / "themes")
                (repo / "dialog").mkdir()
                shutil.copy2(REPO / "dialog/dialog.env", repo / "dialog/dialog.env")
                (repo / "lib").mkdir()
                # A native-agent stand-in asks through the real socket bridge.
                (repo / "lib/bt_agent.py").write_text(
                    "import sys\nsys.path.insert(0, %r)\nimport bt_agent\n" % str(REPO / "lib") +
                    "if '--reply' in sys.argv: sys.exit(bt_agent.main())\n"
                    "b = bt_agent.Bridge(sys.argv[sys.argv.index('--bridge') + 1])\n"
                    "try: b.ask('pin', 'Enter the code from the chosen device')\n"
                    "except bt_agent.Rejected: sys.exit(1)\n"
                    "finally: b.close()\n")
                home = root / "home"
                config = home / ".config/spark-shell"
                config.mkdir(parents=True)
                (config / "config").write_text("DESKTOP=sway\nTHEME=nord\n")
                bins = home / ".local/bin"
                bins.mkdir(parents=True)
                stubs = {
                    "uname": "if [ \"$1\" = -s ]; then echo Linux; else /usr/bin/uname \"$@\"; fi",
                    "dbus-send": "echo 'boolean true'",
                    "bluetoothctl": """case "$*" in
show) printf 'Controller 00:11:22:33:44:00\nPowered: yes\n' ;;
devices) echo 'Device 00:11:22:33:44:55 Buds' ;;
'devices Paired'|'devices Connected') : ;;
*) echo "$*" >> "$HOME/native.log"; echo 'Connection successful' ;;
esac""",
                }
                for name, body in stubs.items():
                    (bins / name).write_text("#!/bin/sh\n" + body + "\n")
                    (bins / name).chmod(0o755)
                (root / "sys/class/bluetooth/hci0").mkdir(parents=True)
                (root / "os-release").write_text("ID=fixture\n")
                (root / "tmp").mkdir()
                env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                           XDG_STATE_HOME=str(home / ".local/state"), XDG_DATA_HOME=str(home / ".local/share"),
                           PATH=str(bins) + ":" + os.environ["PATH"], TMPDIR=str(root / "tmp"),
                           SPARK_SHELL_SYS=str(root / "sys"), SPARK_OS_RELEASE=str(root / "os-release"),
                           SPARK_SHELL_ROOT=str(root / "system"), SPARK_SHELL_NO_APPLY="1")
                proc = subprocess.Popen(["sh", str(repo / "spark-shell"), "provide", "bt"], env=env,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                messages = queue.Queue()
                def read():
                    for line in proc.stdout:
                        messages.put(json.loads(line))
                reader = threading.Thread(target=read, daemon=True)
                reader.start()
                def send(message):
                    proc.stdin.write(json.dumps(dict(jsonrpc="2.0", **message)) + "\n")
                    proc.stdin.flush()
                try:
                    send({"id": 1, "method": "initialize", "params": {"capabilities": {"experimental": {"spark-shell/pairing": True}}}})
                    self.assertEqual(messages.get(timeout=10)["id"], 1)
                    send({"id": 2, "method": "tools/call", "params": {"name": "bt_pair", "arguments": {"name": "Buds"}}})
                    question = messages.get(timeout=10)
                    self.assertEqual(question.get("method"), "spark-shell/pairing", question)
                    if accept is None:
                        proc.stdin.close()
                    else:
                        send({"id": question["id"], "result": {"action": "accept" if accept else "cancel", "content": {"answer": "aB12"}}})
                    result = messages.get(timeout=10)
                    self.assertEqual(result["id"], 2)
                    self.assertEqual(result["result"]["isError"], not accept)
                    log = home / "native.log"
                    if accept:
                        self.assertIn("trust 00:11:22:33:44:55", log.read_text())
                    else:
                        self.assertFalse(log.exists())
                    for file in (root / "tmp").rglob("*"):
                        if file.is_file():
                            self.assertNotIn(b"aB12", file.read_bytes())
                    if not proc.stdin.closed:
                        proc.stdin.close()
                    self.assertEqual(proc.wait(timeout=10), 0)
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
                    proc.stdout.close()
                    proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
