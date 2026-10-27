#!/usr/bin/env python3
"""Answer iwctl's native terminal prompt without a password in arguments."""
import argparse
import errno
import fcntl
import os
import re
import select
import signal
import subprocess
import sys
import termios
import time


def terminal_session():
    # This helper is single threaded. iwctl needs a controlling terminal,
    # not merely file descriptors whose isatty() returns true.
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def connect(device, name, password, hidden=False):
    master, slave = os.openpty()
    child = None
    try:
        # Let readline configure echo itself so its masked display works.
        # Nothing read from this terminal is forwarded or logged.
        child = subprocess.Popen(["iwctl", "station", device,
                                  "connect-hidden" if hidden else "connect", name],
                                 stdin=slave, stdout=slave, stderr=slave,
                                 preexec_fn=terminal_session, close_fds=True,
                                 env={**{k: v for k, v in os.environ.items() if k != "PANEL_PASS"},
                                      "LC_ALL": "C", "TERM": "dumb"})
        os.close(slave)
        slave = -1
        deadline = time.monotonic() + 30
        buffered = b""
        sent = False
        entered = False
        masked = 0
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 4096)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    chunk = b""
                if not chunk:
                    break
                buffered = (buffered + chunk)[-16384:]
                plain = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", buffered)
                if not sent and b"Passphrase:" in plain:
                    # readline masks input after processing readable bytes.
                    # A newline in that same write can submit an empty buffer.
                    os.write(master, password)
                    sent = True
                    buffered = b""
                elif sent and not entered:
                    masked += chunk.count(b"*")
                    if masked >= len(password):
                        os.write(master, b"\n")
                        entered = True
            if child.poll() is not None:
                break
        try:
            return child.wait(timeout=1) == 0
        except subprocess.TimeoutExpired:
            return False
    finally:
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
        os.close(master)
        if slave >= 0:
            os.close(slave)


def interrupted(_number, _frame):
    raise KeyboardInterrupt()


def main():
    for number in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device")
    parser.add_argument("name")
    parser.add_argument("--hidden", action="store_true")
    args = parser.parse_args()
    password = sys.stdin.buffer.read(258)
    if password.endswith(b"\n"):
        password = password[:-1]
    if not password or len(password) > 63 or any(c < 32 or c == 127 for c in password):
        print("iwd needs a password of at most 63 bytes without control characters", file=sys.stderr)
        return 1
    try:
        if connect(args.device, args.name, password, args.hidden):
            return 0
    except KeyboardInterrupt:
        return 130
    except OSError:
        pass
    # Native output may contain a prompt or echoed input; never forward it.
    print("iwd did not confirm the connection", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
