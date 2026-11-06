#!/usr/bin/env python3
"""The dialog at a real terminal, against spark-shell's own providers:
python3 tests/dialog_pty.py PATH-TO-spark-dialog. A throwaway HOME, a
60 by 40 pty; the home draws its places, words find a palette, Down
moves into the list and Enter sets it, words that name no row light
the ask row and Enter on it asks, Esc closes, and no provider outlives
the window. CI runs it with no
network (unshare -n). Linux and macOS, python3 stdlib only."""
import re
import fcntl, json, os, pty, select, signal, struct, subprocess, sys, tempfile, termios, time

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
           "SPARK_SHELL_PROVIDE_POLL": "1", "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_PTS_DIR": home + "/pts"}
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
    ok(read_until(lambda: "home" in text() and "settings" in text() and "search or ask" in text() and "\u00d7" in text(), 15), "the home draws: its title, Settings, the prompt, close as x", text()[-400:])
    ok("\x1b]52" not in text(), "the dialog writes no clipboard sequence")
    os.write(fd, b"nord")
    ok(read_until(lambda: "nord" in text(), 5), "typing finds the palette among every row")
    os.write(fd, b"\x1b[B")
    time.sleep(0.3)
    os.write(fd, b"\r")
    def themed():
        with open(cfg) as f:
            return "THEME=nord" in f.read()
    ok(read_until(themed, 15), "Enter on the palette the words found keeps it (#196: C)", text()[-400:])
    # the step is audited when its answer comes, and the answer carries the section's rows (#196,
    # phase 4): wait for the audit line, the state the checks below need, never a fixed time
    audit = os.path.join(home, ".local/state/spark-shell/audit")
    def audited():
        return os.path.exists(audit) and open(audit).read().count("\n") >= 1
    read_until(audited, 15)
    read_until(lambda: False, 0.5)
    ok("nord is on" not in text() and "\u276f theme nord" not in text(), "a pick says nothing: no command above the list, no receipt (#196)", text()[-400:])
    rec = open(audit).read() if os.path.exists(audit) else ""
    ok(rec.count("\n") == 1 and "\ttheme\ttheme_palette\t" in rec and "nord" not in rec and (os.stat(audit).st_mode & 0o777) == 0o600,
       "one audit line, 0600, numbers and names: the tool, never the argument", rec)
    # the workspace place with no sway: it says so in its header, and Esc comes back
    os.write(fd, b"workspace")
    time.sleep(0.5)
    os.write(fd, b"\r")
    ok(read_until(lambda: "desktop" in text()[-3000:], 10), "workspace with no sway says no desktop in its header", text()[-400:])
    os.write(fd, b"\x1b")
    time.sleep(0.5)
    def processes():
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,command="], capture_output=True, text=True, errors="replace").stdout
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
    resize(binary, env)
    tasks(binary, env, home)
    files(binary, env, home)
    clicks(binary, env, home)
    print("dialog_pty: %d failed" % failed)
    return 1 if failed else 0


def resize(binary, env):
    """Resize redraws even when a launcher leaves SIGWINCH blocked."""
    pid, fd = pty.fork()
    if pid == 0:
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGWINCH})
        os.execve(binary, [binary, "--composer", ""], env)
    screen = Screen()
    cursor_queries = []

    def wait_for(words, seconds=8):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            if all(word in screen.text() for word in words):
                return True
            if select.select([fd], [], [], .1)[0]:
                try:
                    data = os.read(fd, 65536)
                    if b"\x1b[6n" in data:
                        cursor_queries.append(True)
                    screen.feed(data)
                except OSError:
                    return False
        return False

    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
        assert wait_for(["search or ask"]), "resize fixture did not open"
        os.write(fd, b"resize draft")
        assert wait_for(["resize draft"]), "draft did not appear"
        cursor_queries.clear()
        for _ in range(6):
            screen = Screen(12, 32)
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 32, 0, 0))
            assert wait_for(["Make this window larger"], 2), "shrink did not redraw without a key"
            screen = Screen()
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
            assert wait_for(["resize draft", "Esc", "\u2500"], 2), "restore lost the draft or the frame"
        assert not cursor_queries, "resize queried the cursor while another thread owns terminal input"
        ok(True, "resize redraws without SIGWINCH or keyboard input and retains the draft")
    except AssertionError as error:
        ok(False, "resize redraw", str(error))
    finally:
        os.kill(pid, signal.SIGTERM)
        # Drain the terminal while it restores its modes. A full PTY output
        # buffer can otherwise hold macOS's exit path inside waitpid forever.
        deadline = time.monotonic() + 5
        while os.waitpid(pid, os.WNOHANG)[0] == 0:
            if time.monotonic() >= deadline:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                break
            if select.select([fd], [], [], .1)[0]:
                try:
                    os.read(fd, 65536)
                except OSError:
                    pass
        os.close(fd)


def tasks(binary, base_env, home):
    """Real terminal keys, paste and pointer events cross the task boundary.
    The model and provider are fixtures; a tools/call records an effect."""
    provider = os.path.join(home, "task-provider")
    helper = os.path.join(home, "task-helper")
    with open(provider, "w") as f:
        f.write("#!" + sys.executable + "\n" + r'''
import json, re, os, sys
tool = {"name":"notes_pick","title":"notes pick NAME","inputSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}
rows = {"title":"Notes","rows":[{"id":"target","text":"Fixture target","tool":{"name":"notes_pick","arguments":{"name":"Fixture target"}}}]}
for line in sys.stdin:
    v = json.loads(line)
    if "id" not in v: continue
    method = v["method"]
    result = {}
    if method == "initialize": result = {"protocolVersion":"2025-06-18","capabilities":{"tools":{},"resources":{}},"serverInfo":{"name":"notes","version":"1"}}
    elif method == "tools/list": result = {"tools":[tool]}
    elif method == "resources/read": result = {"contents":[{"uri":"spark-shell://notes/rows","mimeType":"application/json","text":json.dumps(rows)}]}
    elif method == "tools/call":
        with open(sys.argv[1], "a") as f: f.write(json.dumps(v["params"])+"\n")
        result = {"isError":False,"structuredContent":{"receipt":"fixture completed"},"content":[{"type":"text","text":"fixture completed"}]}
    print(json.dumps({"jsonrpc":"2.0","id":v["id"],"result":result}), flush=True)
''')
    with open(helper, "w") as f:
        f.write("#!" + sys.executable + "\n" + r'''
import json, os, sys
if sys.argv[1:4] == ["model", "list", "--porcelain"]:
    print("fixture-model\tserving")
    sys.exit(0)
if sys.argv[1:2] != ["steps"]: sys.exit(0)
tools = json.load(sys.stdin)
with open(os.environ["TASK_REQUESTS"], "a") as f: f.write(json.dumps({"argv": sys.argv[1:], "tools": tools})+"\n")
print(json.dumps({"answer": "", "steps": [{"name": "notes_pick", "arguments": {"name": "Fixture target"}}], "refused": []}))
''')
    os.chmod(provider, 0o700)
    os.chmod(helper, 0o700)
    requests, calls = (os.path.join(home, name) for name in ("task-requests", "task-calls"))
    env = dict(base_env, TASK_REQUESTS=requests)
    argv = [binary, "--provider", provider + " " + calls + " notes", "--home", "notes", "--composer", "model", "--spark", helper]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, argv, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
    seen = bytearray()
    def wait_for(test, secs=10):
        end = time.monotonic() + secs
        while time.monotonic() < end:
            if test(): return True
            if select.select([fd], [], [], .1)[0]:
                try: seen.extend(os.read(fd, 65536))
                except OSError: break
        return test()
    def records(path):
        if not os.path.exists(path): return []
        with open(path) as f: return [json.loads(line) for line in f if line.endswith("\n")]
    try:
        assert wait_for(lambda: b"Fixture" in seen and b"target" in seen), "the provider did not draw"
        # Provider discovery and model discovery are independent. Wait for the visible connection state before
        # typing, so the ask row stands for words that name no row (dialog/DESIGN.md): asking is a row, and Enter
        # on it asks; typing alone asks nothing
        assert wait_for(lambda: b"fixture-model" in seen), "the fixture model did not become available"
        os.write(fd, b"\x1b[B")
        time.sleep(.1)
        os.write(fd, b"use this")
        assert wait_for(lambda: b"ask spark" in seen), "the ask row did not draw for words that name no row"
        ok(not records(requests), "typing asks nothing by itself: the ask row waits for Enter")
        os.write(fd, b"\r")
        assert wait_for(lambda: b"notes pick Fixture" in seen and b"discard" in seen), "the proposal did not draw"   # the line wraps across a cursor move
        req = records(requests)
        ok(len(req) == 1 and req[0]["argv"][:3] == ["steps", "--about", req[0]["argv"][2]] and "Fixture target" not in req[0]["argv"][2]
           and [t["name"] for t in req[0]["tools"]["tools"]] == ["notes_pick"],
           "the words go to spark steps once, with explicit context only and the providers' tools on stdin")
        ok(not records(calls), "nothing runs before Enter")
        os.write(fd, b"\r")
        assert wait_for(lambda: b"keep" in seen and b"working" in seen), "the question's page did not draw"   # the words may part across a cursor move
        ok(not records(calls), "Enter on a step that is not read-only waits for the question's yes")
        os.write(fd, b"\x1b[A")   # keep working is lit first: Up to the verb
        time.sleep(0.3)
        os.write(fd, b"\r")   # Enter on the verb is the yes
        assert wait_for(lambda: len(records(calls)) == 1 and b"completed" in seen), "the step did not run"   # the receipt wraps across a cursor move
        ok(records(calls)[0]["arguments"]["name"] == "Fixture target" and len(records(requests)) == 1,
           "Enter runs the proposal as proposed, and spark is not asked again")
    except (AssertionError, KeyError, IndexError) as e:
        ok(False, "task terminal interaction", str(e) + " " + repr(re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", bytes(seen[-2500:]))))
    finally:
        os.write(fd, b"\x11")
        if not wait_for(lambda: os.waitpid(pid, os.WNOHANG)[0] != 0, 5):
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(fd)


class Screen:
    """The cells a 60 by 40 terminal would hold from the bytes a program wrote: the cursor moves applied, the
    colors dropped. A capture of the bytes alone misses a cell the terminal's diff left as it was ("rename"
    drawn over "hello.txt" keeps its e unsent), and this does not."""
    def __init__(self, rows=40, cols=60):
        self.rows, self.cols = rows, cols
        self.cells = [[" "] * cols for _ in range(rows)]
        self.r = self.c = 0
        self.rest = b""
    def feed(self, data):
        data = self.rest + data
        try:
            s = data.decode("utf-8")
            self.rest = b""
        except UnicodeDecodeError as e:
            s = data[:e.start].decode("utf-8", "replace")
            self.rest = data[e.start:] if len(data) - e.start < 4 else b""
        i = 0
        while i < len(s):
            ch = s[i]
            if ch == "\x1b" and i + 1 < len(s) and s[i + 1] == "[":
                j = i + 2
                while j < len(s) and not ("@" <= s[j] <= "~"):
                    j += 1
                if j >= len(s):
                    self.rest = s[i:].encode("utf-8") + self.rest
                    return
                params, final = s[i + 2:j].lstrip("?>"), s[j]
                nums = [int(x) if x.isdigit() else 0 for x in params.split(";")] if params else []
                n = nums[0] if nums and nums[0] else 1
                if final in "Hf":
                    self.r = min(self.rows - 1, max(0, n - 1))
                    self.c = min(self.cols - 1, max(0, (nums[1] if len(nums) > 1 and nums[1] else 1) - 1))
                elif final == "A": self.r = max(0, self.r - n)
                elif final == "B": self.r = min(self.rows - 1, self.r + n)
                elif final == "C": self.c = min(self.cols - 1, self.c + n)
                elif final == "D": self.c = max(0, self.c - n)
                elif final == "G": self.c = min(self.cols - 1, max(0, n - 1))
                elif final == "d": self.r = min(self.rows - 1, max(0, n - 1))
                elif final == "J" and nums and nums[0] == 2: self.cells = [[" "] * self.cols for _ in range(self.rows)]
                elif final == "K":
                    row = self.cells[self.r]
                    for k in range(self.c, self.cols): row[k] = " "
                i = j + 1
                continue
            if ch == "\x1b":
                if i + 1 >= len(s):   # a read that ends on the ESC: the sequence comes whole with the next
                    self.rest = b"\x1b" + self.rest
                    return
                i += 2
                continue
            if ch == "\r": self.c = 0
            elif ch == "\n": self.r = min(self.rows - 1, self.r + 1)
            elif ch == "\x08": self.c = max(0, self.c - 1)
            elif ch >= " ":
                if self.c < self.cols:
                    self.cells[self.r][self.c] = ch
                self.c += 1
            i += 1
    def text(self):
        return "\n".join("".join(row).rstrip() for row in self.cells)


def files(binary, env, home):
    """The files as a file manager (#112), against the real provider on a fixture home: Files opens
    the home folder with its rows, F9 on a file opens its steps, Esc comes back, Right opens the second
    pane, close pane closes it. F keys as a legacy terminal sends them: F2 \\x1bOQ, F3 \\x1bOR, F5
    \\x1b[15~, F7 \\x1b[18~, F9 \\x1b[20~, F10 \\x1b[21~."""
    with open(os.path.join(home, "hello.txt"), "w") as f:
        f.write("hello\n")
    os.makedirs(os.path.join(home, "docs"), exist_ok=True)
    argv = [binary, "--provider", SS + " provide files", "--provider", SS + " provide about", "--composer", "", "--spark-shell", SS]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, argv, dict(env, SPARK_SHELL_NO_UDISKS="1"))
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
    seen = bytearray()
    screen = Screen()
    def wait_for(test, secs=15):
        end = time.monotonic() + secs
        while time.monotonic() < end:
            if test(): return True
            if select.select([fd], [], [], .1)[0]:
                try:
                    chunk = os.read(fd, 65536)
                except OSError: break
                seen.extend(chunk)
                screen.feed(chunk)
        return test()
    plain = lambda: re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", bytes(seen)).decode("utf-8", "replace")
    tight = lambda: re.sub(r"\s+", "", plain())   # the terminal's cursor moves split words: compared with no spaces
    shown = lambda: re.sub(r"\s+", "", screen.text())   # the screen as the terminal holds it, with no spaces
    try:
        assert wait_for(lambda: "search or ask" in plain() and "browse your home" in plain()), "the home did not draw with the files ready"
        os.write(fd, b"\x1bOQ")        # F2 where no row can be renamed
        assert wait_for(lambda: "nothingtorenamehere" in shown()), "F2 at the home did not refuse: " + screen.text()[-900:]
        os.write(fd, b"\x03")          # Ctrl+C is copy path: at the home it refuses, and the dialog stays
        assert wait_for(lambda: "nothingtocopyhere" in shown()), "Ctrl+C at the home did not refuse: " + screen.text()[-900:]
        assert os.waitpid(pid, os.WNOHANG)[0] == 0, "Ctrl+C closed the dialog"
        ok(True, "F2 and Ctrl+C refuse where they have nothing to act on, and Ctrl+C no longer closes the dialog")
        os.write(fd, b"files")
        time.sleep(0.3)
        os.write(fd, b"\r")
        assert wait_for(lambda: "hello.txt" in shown() and "thisfolder" in shown() and "trash" in shown()), "the home folder did not draw: " + screen.text()[-900:]
        ok(True, "Files opens the home folder: home first, the folder, the fixture file with its size and the trash, then the folder's own row (#127, #130)")
        os.write(fd, b"\x1b[B")       # Down: the first row, the folder
        time.sleep(0.3)
        os.write(fd, b"\x1b[B")       # Down: the file, lit
        assert wait_for(lambda: all(w in shown() for w in ("renF2", "viewF3", "openF4", "copyF5", "moveF6", "newF7", "trashF8", "actionsF9"))), "the key bar did not show the file's keys: " + screen.text()[-600:]
        seen.clear()
        os.write(fd, b"\x1b[20~")     # F9: its actions
        # read from the screen, not the bytes: a cell the row before held too is not sent again ("rename" over "hello.txt" keeps its e)
        assert wait_for(lambda: all(w in shown() for w in ("openinappF4", "renameF2", "copypathCtrl+C", "selectSpace", "newfolderF7", "newfile", "back"))), "the actions did not draw: " + screen.text()[-900:]
        assert "closepane" not in shown() and "twopanes" not in shown(), "one pane has no pane row: " + screen.text()[-900:]
        ok(True, "Down lights the file with its keys on the bar; F9 opens the actions, each row with its key at the right, and no pane row in one pane")
        seen.clear()
        os.write(fd, b"\x1b")          # back to the folder
        assert wait_for(lambda: "hello.txt" in shown() and "thisfolder" in shown() and "renameF2" not in shown()), "Esc did not come back: " + screen.text()[-900:]
        ok(True, "Esc comes back to the folder")
        os.write(fd, b"\x1bOR")        # F3, the bytes foot sends: the lit file's view
        assert wait_for(lambda: "view\u00b7" in shown()), "F3 did not view the lit file: " + screen.text()[-900:]
        os.write(fd, b"\x1b")
        assert wait_for(lambda: "thisfolder" in shown() and "view\u00b7" not in shown()), "Esc did not leave the view: " + screen.text()[-900:]
        ok(True, "F3 through the terminal views the lit file, and Esc comes back")
        os.write(fd, b"v")             # v on a lit row is a letter: a search starts and no view comes up
        assert wait_for(lambda: "searchorask" not in shown()), "v did not reach the prompt: " + screen.text()[-900:]
        time.sleep(0.5)
        wait_for(lambda: False, 0.3)
        assert "view\u00b7" not in shown(), "v opened a view: " + screen.text()[-900:]
        os.write(fd, b"\x7f")
        assert wait_for(lambda: "searchorask" in shown() and "hello.txt" in shown()), "Backspace did not clear the v: " + screen.text()[-900:]
        ok(True, "v on a lit row types a letter and opens nothing")
        os.write(fd, b"\x1b[B")       # typing took the keys to the prompt: Down, Down lights the file again
        time.sleep(0.3)
        os.write(fd, b"\x1b[B")
        assert wait_for(lambda: "hello.txt" in re.sub(r"\s+", "", "".join(screen.cells[35]))), "the file was not lit again: " + screen.text()[-900:]
        # the rework of 2026-11-05 (dialog/DESIGN.md, Files): a selection, the second pane by Right and the actions'
        # close pane. The status row is h-5, row 35 of 40; read with no spaces, as the rest. Ctrl+Tab is the kitty
        # protocol's and a legacy pty cannot send it, so the desktop proof alone presses it
        status = lambda: re.sub(r"\s+", "", "".join(screen.cells[35]))
        prompt = lambda: re.sub(r"\s+", "", "".join(screen.cells[2]))
        twice = lambda word: any("".join(row).count(word) >= 2 for row in screen.cells)
        line = lambda: any("\u2502" in "".join(row) for row in screen.cells[8:35])
        os.write(fd, b" ")             # Space: the lit file selected, the bar a row down
        assert wait_for(lambda: "1selected" in status()), "Space did not count the selection on the status row: " + screen.text()[-900:]
        ok(True, "Space selects the lit file: the status row reads 1 selected")
        os.write(fd, b"\x1b")          # Esc with nothing typed: the selection goes first, the lit row's line comes back
        assert wait_for(lambda: status() and "selected" not in status()), "Esc did not clear the selection: " + screen.text()[-900:]
        if "hello.txt" not in status():
            os.write(fd, b"\x1b[A")    # Up: Space moved the bar a row down, so the file's line is a row up
        assert wait_for(lambda: "hello.txt" in status()), "the file's line is not back on the status row: " + screen.text()[-900:]
        ok(True, "Esc clears the selection first: hello.txt's line is back on the status row")
        os.write(fd, b"\x1b[C")        # Right: the second pane, the same folder, the bar on its first row
        assert wait_for(lambda: line() and twice("hello.txt") and "".join(screen.cells[8]).count("~") >= 2 and "docs" in status()), "Right did not open the second pane: " + screen.text()[-900:]
        assert wait_for(lambda: not re.search(r"\b(home|recent)\b", screen.text())), "two panes at home keep a heading: " + screen.text()[-900:]
        ok(True, "Right opens the second pane: the line between them, each pane's path on its first row, the bar on the second's first row, no home heading and no recent")
        wait_for(lambda: False, 0.3)
        drawn = screen.text()
        os.write(fd, b"\x1b[C")        # Right again: the edge
        wait_for(lambda: False, 0.4)
        assert screen.text() == drawn, "Right at the edge moved: " + screen.text()[-900:]
        os.write(fd, b"\x1b[D")        # Left: the left pane, its bar where it was
        assert wait_for(lambda: "hello.txt" in status()), "Left did not go to the left pane: " + screen.text()[-900:]
        wait_for(lambda: False, 0.3)
        drawn = screen.text()
        os.write(fd, b"\x1b[D")        # Left again: the edge
        wait_for(lambda: False, 0.4)
        assert screen.text() == drawn, "Left at the edge moved: " + screen.text()[-900:]
        ok(True, "Left and Right move between the panes and stay put at the edge")
        os.write(fd, b"\x1bOQ")        # F2: the form in the prompt, the name as it is, both panes on screen
        assert wait_for(lambda: "hello.txt" in prompt() and "cancelEsc" in shown() and "saveEnter" in shown() and line()), "F2 did not open the form: " + screen.text()[-900:]
        os.write(fd, b"\x1b")
        assert wait_for(lambda: "searchorask" in prompt()), "Esc did not cancel the form: " + screen.text()[-900:]
        os.write(fd, b"\x1b[18~")      # F7: the same form, its placeholder
        assert wait_for(lambda: "foldername" in prompt() and "cancelEsc" in shown() and line()), "F7 did not open the form: " + screen.text()[-900:]
        os.write(fd, b"\x1b")
        assert wait_for(lambda: "searchorask" in prompt()), "Esc did not cancel the form: " + screen.text()[-900:]
        ok(os.path.exists(os.path.join(home, "hello.txt")), "F2 opens the form with the name, F7 asks folder name, both panes stay, and Esc cancels")
        os.write(fd, b"\x1b[15~")      # F5 with both panes on one folder
        assert wait_for(lambda: "theotherpaneshowsthisfolder" in status()), "F5 did not refuse: " + screen.text()[-900:]
        os.write(fd, b"\x1b[20~")      # the refusal stands until the next action, and Esc alone would also go back a level
        assert wait_for(lambda: "closepane" in shown()), "F9 did not open the actions: " + screen.text()[-900:]
        os.write(fd, b"\x1b")
        assert wait_for(lambda: "closepane" not in shown() and "hello.txt" in status()), "Esc did not come back to the file: " + screen.text()[-900:]
        os.write(fd, b"\x1b[C")        # the right pane, on docs, its first row
        assert wait_for(lambda: "docs" in status()), "Right did not go to the right pane: " + screen.text()[-900:]
        os.write(fd, b"\r")
        assert wait_for(lambda: "~/docs" in "".join(screen.cells[8])), "Enter did not open docs in the right pane: " + screen.text()[-900:]
        os.write(fd, b"\x1b[D")
        assert wait_for(lambda: "hello.txt" in status()), "Left did not come back: " + screen.text()[-900:]
        os.write(fd, b"\x1b[15~")      # F5: at once, to the other pane's folder
        assert wait_for(lambda: "hello.txtcopiedto~/docs" in status() and "undo" in status()), "F5 did not copy: " + screen.text()[-900:]
        ok(os.path.exists(os.path.join(home, "docs", "hello.txt")) and "searchorask" in prompt() and line(),
           "F5 refuses on one folder and copies to the other pane's at once, no words in the prompt, both panes on screen", screen.text()[-900:])
        os.write(fd, b"\x1b[21~")      # F10: the conversation, and back
        assert wait_for(lambda: "conversation" in "".join(screen.cells[0])), "F10 did not open the conversation: " + screen.text()[-900:]
        os.write(fd, b"\x1b[21~")
        assert wait_for(lambda: "conversation" not in "".join(screen.cells[0]) and line()), "F10 did not come back: " + screen.text()[-900:]
        ok(True, "F10 opens the conversation and comes back to the panes")
        os.write(fd, b"\x1b[20~")      # F9: the actions, inside the pane, close pane among them
        assert wait_for(lambda: "closepane" in shown() and "~/docs" in "".join(screen.cells[8])), "the actions lack close pane or the other pane: " + screen.text()[-900:]
        os.write(fd, b"close pane")    # typing narrows the menu, the best match lit
        assert wait_for(lambda: "newfolderF7" not in shown()), "typing did not narrow the actions: " + screen.text()[-900:]
        os.write(fd, b"\r")
        assert wait_for(lambda: "hello.txt" in shown() and not line() and not twice("hello.txt") and "".join(screen.cells[8]).count("~") < 2), "close pane did not close the second pane: " + screen.text()[-900:]
        ok(True, "F9 draws the actions in the pane with the other on screen; close pane, typed, closes the second pane: the folder once again")
    except AssertionError as e:
        ok(False, "files terminal interaction", str(e))
    finally:
        os.write(fd, b"\x11")
        if not wait_for(lambda: os.waitpid(pid, os.WNOHANG)[0] != 0, 5):
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(fd)


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
    while time.time() < end and b"search or ask" not in seen:
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
    ps = lambda: subprocess.run(["ps", "-A", "-o", "command="], capture_output=True, text=True, errors="replace").stdout
    still = any(slow in l for l in ps().splitlines())
    ok(status is not None and took < 0.5 and still, "Esc closes the dialog at once while a provider is still busy, nothing waits for it (#60)",
       "took %s s, the busy one still there: %s" % (took, still))
    time.sleep(3)
    ok(not any(slow in l for l in ps().splitlines()), "the busy provider ends by itself once its work is done")


CLICK_PROVIDER = r"""import json, sys
step = {"values": [{"shown": n, "sent": n} for n in ("10", "11", "12")], "at": 1, "set": {"name": "theme_text", "arguments": {}}, "key": "size", "words": ["smaller", "bigger"]}
rows = {"title": "theme", "short": [], "rows": [{"id": "theme:show:Text size", "sign": "blank", "text": "Text size", "tool": None, "more": [], "columns": [], "children": None, "group": None, "step": step}]}
tool = {"name": "theme_text", "title": "theme text SIZE", "inputSchema": {"type": "object", "properties": {"size": {"type": "string", "enum": ["10", "11", "12"]}}, "required": ["size"], "additionalProperties": False},
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False, "openWorldHint": False}}
for line in sys.stdin:
    v = json.loads(line)
    m, i = v.get("method"), v.get("id")
    if i is None:
        continue
    if m == "initialize":
        r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}, "resources": {"subscribe": True}}, "serverInfo": {"name": "theme", "title": "theme", "version": "1"}}
    elif m == "tools/list":
        r = {"tools": [tool]}
    elif m == "resources/read":
        r = {"contents": [{"uri": "spark-shell://theme/rows", "mimeType": "application/json", "text": json.dumps(rows)}]}
    elif m == "tools/call":
        with open(sys.argv[1], "a") as f:
            f.write(json.dumps(v["params"]) + "\n")
        r = {"content": [{"type": "text", "text": "text at " + v["params"]["arguments"]["size"]}], "isError": False}
    else:
        r = {}
    print(json.dumps({"jsonrpc": "2.0", "id": i, "result": r}), flush=True)
"""


def clicks(binary, env, home):
    """A click on a value row's arrows (#175): the right one steps the value up and the left one down, as the
    arrow keys do. The clicks are the bytes a terminal sends for a mouse press and release (SGR, 1006)."""
    prov, log = os.path.join(home, "click-provider.py"), os.path.join(home, "click-calls")
    with open(prov, "w") as f:
        f.write(CLICK_PROVIDER)
    argv = [binary, "--provider", "%s %s %s theme" % (sys.executable, prov, log), "--home", "theme", "--composer", "", "--spark-shell", SS]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, argv, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 60, 0, 0))
    screen = Screen()

    def wait_for(test, secs=10):
        end = time.time() + secs
        while time.time() < end and not test():
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try:
                    screen.feed(os.read(fd, 65536))
                except OSError:
                    break
        return test()

    def calls():
        try:
            with open(log) as f:
                return [json.loads(l)["arguments"]["size"] for l in f if l.strip()]
        except OSError:
            return []

    def click(r, c):
        os.write(fd, ("\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (c + 1, r + 1, c + 1, r + 1)).encode())

    def arrows():
        # the value row where it stands now, and its two arrows: the list moves down as a receipt comes in above it
        for k, l in enumerate(screen.cells):
            if "Text size" in "".join(l) and "\u2039" in l and "\u203a" in l:
                return k, l.index("\u2039"), l.index("\u203a")
        return None

    try:
        drawn = wait_for(lambda: arrows() is not None)
        ok(drawn, "the value row draws with its arrows", screen.text()[-600:])
        if not drawn:
            return
        r, _, more = arrows()
        click(r, more)
        ok(wait_for(lambda: calls() == ["12"], 5), "a click on the right arrow sets the next value up", repr(calls()))
        ok(wait_for(lambda: "12" in "".join(screen.cells[r]) and "text at" not in screen.text(), 2), "the value changes in place, and nothing is said", screen.text()[-400:])
        wait_for(lambda: False, 0.5)
        r, less, _ = arrows()
        click(r, less)
        ok(wait_for(lambda: calls() == ["12", "11"], 5), "a click on the left arrow sets the next value down", repr(calls()))
        wait_for(lambda: False, 0.5)
        r, _, _ = arrows()
        click(r, 6)
        time.sleep(0.5)
        ok(calls() == ["12", "11"], "a click on the row's name lights it and runs nothing", repr(calls()))
    finally:
        os.write(fd, b"\x11")
        gone = []
        if not wait_for(lambda: bool(gone) or (os.waitpid(pid, os.WNOHANG)[0] != 0 and not gone.append(1)), 5):
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(fd)


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
    while time.time() < end and b"search or ask" not in seen:
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
    # three lines in the draft (one, twothree, four): the prompt stays two rows, the last two shown, the arrow
    # saying a line sits above (#196)
    ok("twothree" in text and "four" in text and "\u2191" in text and "No such file" not in text and "not found" not in text,
       "Shift+Enter starts a new line and a pasted newline stays in the draft: nothing was sent", text[-400:])
    os.write(fd, b"\x11")
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
    ok(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 130 and b"\x1b[<1u" in seen,
       "Ctrl+Q closes it with a signal's 130, and the protocol is turned off again on the way out", repr(status))


if __name__ == "__main__":
    sys.exit(main(os.path.abspath(sys.argv[1])))
