#!/usr/bin/env python3
"""The dialog at a real terminal, against spark-shell's own providers:
python3 tests/dialog_pty.py PATH-TO-spark-dialog. A throwaway HOME, a
60 by 40 pty; the home draws its places, words find a palette, Down
moves into the list and Enter sets it (Enter in the prompt alone would
send the words as a request), Esc closes, and no provider outlives the
window. CI runs it with no
network (unshare -n). Linux and macOS, python3 stdlib only."""
import fcntl, os, pty, select, signal, struct, subprocess, sys, tempfile, termios, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = os.path.join(REPO, "spark-shell")
failed = 0


def ok(cond, what, detail=""):
    global failed
    print("  %s %s%s" % ("ok  " if cond else "FAIL", what, "" if cond else "   " + detail))
    failed += 0 if cond else 1


def main(binary):
    home = tempfile.mkdtemp()
    os.makedirs(os.path.join(home, ".config", "spark-shell"))
    cfg = os.path.join(home, ".config", "spark-shell", "config")
    with open(cfg, "w") as f:
        f.write("THEME=none\n")
    env = {"HOME": home, "XDG_CONFIG_HOME": home + "/.config", "XDG_STATE_HOME": home + "/.local/state", "XDG_DATA_HOME": home + "/.local/share",
           "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TERM": "xterm-256color", "LANG": "C.UTF-8",
           "HEX_FG": "c0caf5", "HEX_ACCENT": "7aa2f7", "PANEL_BG": "282a38", "PANEL_HI": "373a4b", "PANEL_MUTED": "7b84ae",
           "SPARK_SHELL_PROVIDE_POLL": "1"}
    argv = [binary, "--provider", SS + " provide theme", "--provider", SS + " provide about", "--composer", "", "--spark-shell", SS]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, argv, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
    os.kill(pid, signal.SIGWINCH)
    seen = bytearray()

    def read_until(test, secs):
        end = time.time() + secs
        while time.time() < end:
            if test():
                return True
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try:
                    seen.extend(os.read(fd, 65536))
                except OSError:
                    break
        return test()

    text = lambda: seen.decode("utf-8", "replace")
    ok(read_until(lambda: "home" in text() and "Settings" in text() and "Type a request." in text() and "\u00d7" in text(), 15), "the home draws: its title, Settings, the prompt, close as x", text()[-400:])
    ok("\x1b]52" not in text(), "the dialog writes no clipboard sequence")
    os.write(fd, b"nord")
    ok(read_until(lambda: "nord" in text(), 5), "typing finds the palette among every row")
    os.write(fd, b"\x1b[B")
    time.sleep(0.3)
    os.write(fd, b"\r")
    def themed():
        with open(cfg) as f:
            return "THEME=nord" in f.read()
    ok(read_until(lambda: themed() and "theme nord" in text() and "nord is on" in text(), 15), "Enter sets the palette: the turn is the command, then the reply (#53)", text()[-400:])
    audit = os.path.join(home, ".local/state/spark-shell/audit")
    rec = open(audit).read() if os.path.exists(audit) else ""
    ok(rec.count("\n") == 1 and "\ttheme\ttheme_palette\t" in rec and "nord" not in rec and (os.stat(audit).st_mode & 0o777) == 0o600,
       "one audit line, 0600, numbers and names: the tool, never the argument", rec)
    def processes():
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,command="], capture_output=True, text=True).stdout
        return {int(parts[0]): (int(parts[1]), parts[2]) for line in out.splitlines()
                if len(parts := line.split(None, 2)) == 3}
    before = processes()
    descendants = {pid}
    while True:
        added = {p for p, (parent, _) in before.items() if parent in descendants}
        if added <= descendants:
            break
        descendants |= added
    providers = {p for p in descendants if p in before and (SS + " provide") in before[p][1]}
    ok(len(providers) >= 2, "the cleanup check observes this dialog's providers")
    time.sleep(0.3)
    os.write(fd, b"\x1b")   # the receipt is up at the home: the first Esc clears it (#25)
    time.sleep(0.5)
    os.write(fd, b"\x1b")   # the next closes
    status = None
    end = time.time() + 10
    while time.time() < end:
        read_until(lambda: False, 0.2)
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            status = st
            break
    ok(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, "Esc clears the receipt, the next Esc closes the dialog, exit 0", repr(status))
    # The window closes without waiting for native providers. Observe their
    # cleanup with a bound, not a fixed scheduling delay or unrelated dialogs.
    deadline = time.monotonic() + 5
    while providers & processes().keys() and time.monotonic() < deadline:
        time.sleep(0.1)
    ok(not providers & processes().keys(), "this dialog's providers exit after the window closes")
    busy(binary, env, home)
    keys(binary, env)
    print("dialog_pty: %d failed" % failed)
    return 1 if failed else 0


def busy(binary, env, home):
    """A provider that stays busy 2 s after its input ends: Esc closes the dialog at once, nothing
    waits for it (the wait held the window open as a bare terminal, #60), and it ends by itself."""
    slow = os.path.join(home, "slow-provider")
    with open(slow, "w") as f:
        f.write("#!/bin/sh\ncat > /dev/null\nsleep 2\n")
    os.chmod(slow, 0o755)
    argv = [binary, "--provider", SS + " provide theme", "--provider", slow, "--composer", "", "--spark-shell", SS]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, argv, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
    seen = bytearray()
    end = time.time() + 15
    while time.time() < end and b"Type a request." not in seen:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            seen.extend(os.read(fd, 65536))
    os.write(fd, b"\x1b")
    t_esc = time.time()
    status, t_exit = None, None
    while time.time() < t_esc + 10:
        r, _, _ = select.select([fd], [], [], 0.01)
        if r:
            try:
                seen.extend(os.read(fd, 65536))
            except OSError:
                pass
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            status, t_exit = st, time.time()
            break
    took = (t_exit - t_esc) if t_exit else None
    ps = lambda: subprocess.run(["ps", "-A", "-o", "command="], capture_output=True, text=True).stdout
    still = any(slow in l for l in ps().splitlines())
    ok(status is not None and took < 0.5 and still, "Esc closes the dialog at once while a provider is still busy, nothing waits for it (#60)",
       "took %s s, the busy one still there: %s" % (took, still))
    time.sleep(3)
    ok(not any(slow in l for l in ps().splitlines()), "the busy provider ends by itself once its work is done")


def keys(binary, env):
    """A terminal that speaks the kitty keyboard protocol, as foot does: it
    answers the dialog's question, and Shift+Enter comes as CSI 13;2u. A
    new line and a pasted one go into the draft; nothing is sent."""
    argv = [binary, "--provider", SS + " provide theme", "--composer", "", "--spark-shell", "/nonexistent/spark-shell"]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, argv, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
    seen = bytearray()
    answered = False
    end = time.time() + 15
    while time.time() < end and b"Type a request." not in seen:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            seen.extend(os.read(fd, 65536))
        if not answered and b"\x1b[?u" in seen:
            os.write(fd, b"\x1b[?0u\x1b[?62;22c")   # the flags now, then the device attributes: foot's answer
            answered = True
    ok(answered and b"\x1b[>1u" in seen, "the dialog asks for the kitty keyboard protocol and turns it on where it is answered", repr(bytes(seen[-200:])))
    os.write(fd, b"one")
    os.write(fd, b"\x1b[13;2u")                     # Shift+Enter, as foot sends it
    os.write(fd, b"two")
    os.write(fd, b"\x1b[200~three\nfour\x1b[201~")  # a bracketed paste with a newline in it
    end = time.time() + 5
    while time.time() < end and not (b"twothree" in seen and b"four" in seen):
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            seen.extend(os.read(fd, 65536))
    text = seen.decode("utf-8", "replace")
    # three lines in the draft (one, twothree, four): the prompt grows to show all three, no arrow (#53)
    ok("twothree" in text and "four" in text and "\u2191" not in text and "No such file" not in text and "not found" not in text,
       "Shift+Enter starts a new line and a pasted newline stays in the draft: nothing was sent", text[-400:])
    os.write(fd, b"\x03")
    status = None
    end = time.time() + 10
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                seen.extend(os.read(fd, 65536))
            except OSError:
                pass
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            status = st
            break
    ok(status is not None and b"\x1b[<1u" in seen, "Ctrl-C closes it, and the protocol is turned off again on the way out", repr(status))


if __name__ == "__main__":
    sys.exit(main(os.path.abspath(sys.argv[1])))
