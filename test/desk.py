"""desk.py -- what the desktop's proofs share: the fence they start behind, and the virtual pointer.

A proof starts a sway, a bar and windows of its own, and runs spark-shell on. Outside a fence it once wrote a real
home, turned a login screen off and drew on the desktop in use. fenced() stops it there: test/prove.sh and CI's
desktop job set SPARK_SHELL_FENCE, and nothing else does.
"""
import os
from pathlib import Path
import socket
import struct
import sys
import time


def fenced():
    """Stop a proof that nothing keeps off the machine it runs on."""
    if not os.environ.get("SPARK_SHELL_FENCE"):
        sys.exit("%s: run it through test/prove.sh: its fence keeps a proof off your desktop" % Path(sys.argv[0]).name)


class Pointer:
    """Keep a virtual pointer attached to the isolated compositor for real clicks.

    Implements only registry, sync and wlr-virtual-pointer-v1 motion/button/frame.
    A persistent device matters: removing it between motion and click loses focus.
    """

    def __init__(self, env):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(5)
        self.socket.connect(str(Path(env["XDG_RUNTIME_DIR"]) / env["WAYLAND_DISPLAY"]))
        self.callback = 2
        self.globals = {}
        self.send(1, 1, 2)  # wl_display.get_registry
        self.sync()
        interface = b"zwlr_virtual_pointer_manager_v1\0"
        payload = struct.pack("II", self.globals[interface[:-1]], len(interface))
        payload += interface + b"\0" * (-len(interface) % 4)
        payload += struct.pack("II", 1, 4)
        self.packet(2, 0, payload)  # wl_registry.bind, version 1, object 4
        self.send(4, 0, 0, 5)  # create_virtual_pointer, default seat, object 5
        self.callback = 5
        self.sync()

    def packet(self, obj, opcode, payload):
        self.socket.sendall(struct.pack("II", obj, ((len(payload) + 8) << 16) | opcode) + payload)

    def send(self, obj, opcode, *args):
        self.packet(obj, opcode, struct.pack("I" * len(args), *args))

    def read(self, size):
        result = b""
        while len(result) < size:
            part = self.socket.recv(size - len(result))
            if not part:
                raise RuntimeError("virtual pointer connection closed")
            result += part
        return result

    def sync(self):
        self.callback += 1
        self.send(1, 0, self.callback)
        while True:
            obj, header = struct.unpack("II", self.read(8))
            data = self.read((header >> 16) - 8)
            opcode = header & 0xffff
            if obj == 1 and opcode == 0:
                raise RuntimeError("Wayland error: " + repr(data))
            if obj == 2 and opcode == 0:
                name, length = struct.unpack("II", data[:8])
                self.globals[data[8:8 + length - 1]] = name
            if obj == self.callback:
                return

    def click(self, x, y, times=1):
        # times 2 is a double click: the two presses 200 ms apart, within the dialog's 400 ms window
        # (the dialog design notes, app::DOUBLE_CLICK), as a desktop's double click is; two click() calls would not be,
        # since each one rests after its release
        def stamp():
            return int(time.monotonic() * 1000) & 0xffffffff
        self.send(5, 1, stamp(), x, y, 1440, 1000)  # motion_absolute
        self.send(5, 4)  # frame
        self.sync()
        time.sleep(.1)
        for _ in range(times):
            for state in (1, 0):
                self.send(5, 2, stamp(), 272, state)  # BTN_LEFT
                self.send(5, 4)
                self.sync()
                time.sleep(.1)

    def close(self):
        self.socket.close()
