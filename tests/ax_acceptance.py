#!/usr/bin/env python3
"""Complete tasks at the real dialog, with disposable native data.

Default: scripted decisions (no AI or network). --spark CHECKOUT: the installed
Spark task adapter and its configured live backend. The same goals and native
state oracles apply to both; scripts are never read by the live decision path.
Reports contain case IDs, counts and timings, never prompts, paths or credentials.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

REPO = Path(__file__).resolve().parents[1]
CASES = Path(__file__).with_name("ax_cases.json")


def append(path, value):
    raw = (json.dumps(value, separators=(",", ":")) + "\n").encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, raw)
    finally:
        os.close(fd)


def records(path):
    try:
        return [json.loads(line) for line in path.read_text().splitlines()]
    except FileNotFoundError:
        return []
    except json.JSONDecodeError:
        # A concurrent writer may still be finishing the last line.
        return [json.loads(line) for line in path.read_text().splitlines()[:-1]]


def substitute(value, known):
    if isinstance(value, str):
        for key, item in known.items():
            value = value.replace("$" + key, item)
        return value
    if isinstance(value, dict):
        return {substitute(k, known): substitute(v, known) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute(v, known) for v in value]
    return value


def known_effects(events):
    known = {}
    for e in events:
        effect = e.get("result", {}).get("structuredContent", {}).get("effect", {})
        if effect.get("id") and effect.get("kind") in ("note", "reminder"):
            known[effect["kind"] + "_id"] = effect["id"]
            if effect["kind"] == "reminder":
                known["reminder_note_file"] = re.sub("[^a-z0-9]+", "-", effect["id"].lower()).strip("-")[:40] + ".md"
    return known


def scripted(request, case, events):
    """Fixture decision process only; the actual dialog still owns every gate."""
    state = request.get("state", {"cursor": 0})
    cursor = state["cursor"]
    ident = state.get("pending", {}).get("id", 0) + 1
    if request.get("observation", {}).get("status") == "needs_input":
        question = request["observation"]["result"]["question"]
        pending = {"id": ident, "kind": "ask", "question": question}
    elif cursor >= len(case["script"]):
        return {"version": 1, "status": "done", "summary": "Task complete."}
    else:
        entry = substitute(case["script"][cursor], known_effects(events))
        cursor += 1
        if "ask" in entry:
            pending = {"id": ident, "kind": "ask", "question": entry["ask"]}
        elif "inspect" in entry:
            pending = {"id": ident, "kind": "inspect", "provider": entry["inspect"]}
        elif "answer" in entry:
            return {"version": 1, "status": "answer", "summary": entry["answer"]}
        else:
            pending = {"id": ident, "kind": "step", "step": entry}
    return dict(pending, version=1, status=pending["kind"],
                state={"cursor": cursor, "pending": pending})


def helper(folder):
    request = json.load(sys.stdin)
    case = json.loads((folder / "case.json").read_text())
    started = time.monotonic()
    inferences = []
    if os.environ.get("AX_SPARK"):
        sys.path.insert(0, str(Path(os.environ["AX_SPARK"]) / "lib"))
        from spark import tool_run
        if "AX_TEMPERATURE" in os.environ:
            native_chat = tool_run.wire.chat_grammar
            def chat(*args, **kwargs):
                kwargs["temperature"] = float(os.environ["AX_TEMPERATURE"])
                return native_chat(*args, **kwargs)
            tool_run.wire.chat_grammar = chat
        def decide(packet, tools):
            began = time.monotonic()
            try:
                return tool_run.model_decision(packet, tools)
            finally:
                inferences.append(round(time.monotonic() - began, 3))
        try:
            result = tool_run.advance(request, decide)
        except Exception:
            result = {"version": 1, "status": "blocked", "summary": "The decision backend failed."}
    else:
        result = scripted(request, case, records(folder / "providers.jsonl"))
    append(folder / "decisions.jsonl", {"request": request, "result": result,
           "seconds": round(time.monotonic() - started, 3), "inferences": inferences})
    print(json.dumps(result), flush=True)


def provider(folder, section):
    """Transparent MCP recorder. Only isolated fixture providers reach this path."""
    env = os.environ.copy()
    env["TZ"] = json.loads((folder / "case.json").read_text()).get("timezone", "UTC")
    child = subprocess.Popen([str(REPO / "spark-shell"), "provide", section],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, env=env)
    pending = {}
    def forward():
        for line in child.stdout:
            try:
                value = json.loads(line)
                request = pending.pop(value.get("id"), None)
                if request and request["method"] in ("tools/call", "spark/prepare", "tools/list", "resources/read"):
                    append(folder / "providers.jsonl", {"section": section,
                           "method": request["method"], "params": request.get("params", {}),
                           "result": value.get("result", {}), "error": "error" in value})
            except (ValueError, KeyError):
                pass
            sys.stdout.write(line)
            sys.stdout.flush()
    worker = threading.Thread(target=forward, daemon=True)
    worker.start()
    try:
        for line in sys.stdin:
            value = json.loads(line)
            if "id" in value:
                pending[value["id"]] = value
            child.stdin.write(line)
            child.stdin.flush()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        child.stdin.close()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.terminate()
            child.wait(timeout=5)
        worker.join(timeout=2)


class Screen:
    """Small VT text observer for crossterm's current screen, not a UI mock-up."""
    def __init__(self, width=60, height=44):
        self.width, self.height = width, height
        self.grid = [[" "] * width for _ in range(height)]
        self.x = self.y = 0
        self.pending = ""

    def feed(self, text):
        self.pending += text
        while self.pending:
            c = self.pending[0]
            if c == "\x1b":
                match = re.match(r"\x1b\[[0-?]*[ -/]*[@-~]", self.pending)
                if match:
                    seq = match[0]
                    self.pending = self.pending[len(seq):]
                    vals = [int(v) if v.isdigit() else 0 for v in seq[2:-1].split(";")]
                    a = vals[0] if vals else 0
                    op = seq[-1]
                    if op in "Hf":
                        self.y = min(self.height - 1, max(0, a - 1))
                        self.x = min(self.width - 1, max(0, (vals[1] if len(vals) > 1 else 1) - 1))
                    elif op == "G": self.x = min(self.width - 1, max(0, a - 1))
                    elif op == "A": self.y = max(0, self.y - (a or 1))
                    elif op == "B": self.y = min(self.height - 1, self.y + (a or 1))
                    elif op == "C": self.x = min(self.width - 1, self.x + (a or 1))
                    elif op == "D": self.x = max(0, self.x - (a or 1))
                    elif op == "J" and a in (2, 3): self.grid = [[" "] * self.width for _ in range(self.height)]
                    elif op == "K":
                        start, end = (0, self.width) if a == 2 else ((0, self.x + 1) if a == 1 else (self.x, self.width))
                        self.grid[self.y][start:end] = [" "] * (end - start)
                    continue
                if self.pending.startswith("\x1b]"):
                    end = re.search(r"\x07|\x1b\\", self.pending)
                    if not end: break
                    self.pending = self.pending[end.end():]
                    continue
                if self.pending.startswith("\x1b["):
                    break  # a CSI sequence may arrive in several reads
                if len(self.pending) < 3: break
                self.pending = self.pending[2:]
                continue
            self.pending = self.pending[1:]
            if c == "\r": self.x = 0
            elif c == "\n": self.y = min(self.height - 1, self.y + 1)
            elif c == "\b": self.x = max(0, self.x - 1)
            elif ord(c) >= 32:
                self.grid[self.y][min(self.x, self.width - 1)] = c
                self.x = min(self.width - 1, self.x + 1)

    def text(self):
        return "\n".join("".join(row).rstrip() for row in self.grid)


class Dialog:
    def __init__(self, binary, argv, env):
        import codecs
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.screen = Screen()
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(binary, [binary] + argv, env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 44, 60, 0, 0))
        os.kill(self.pid, signal.SIGWINCH)

    def wait(self, predicate, seconds=20):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if predicate(): return True
            if select.select([self.fd], [], [], .05)[0]:
                try:
                    self.screen.feed(self.decoder.decode(os.read(self.fd, 65536)))
                except OSError:
                    break
        return predicate()

    def send(self, value):
        os.write(self.fd, value.encode())

    def close(self):
        try:
            self.send("\x03")
            if not self.wait(lambda: os.waitpid(self.pid, os.WNOHANG)[0] != 0, 5):
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
        except (ProcessLookupError, ChildProcessError, OSError):
            pass
        os.close(self.fd)


def native_errors(case, home, events, now):
    errors = []
    wrong_state = False
    expected = substitute(case["expect"], known_effects(events))
    notes = {p.name: p.read_text() for p in (home / "notes").glob("*.md")}
    want_notes = expected.get("notes", {})
    # Include seeded notes when checking that no extra item was written.
    seed_notes = {Path(p).name for p in case.get("seed", {}) if p.startswith("notes/")}
    if set(notes) != set(want_notes) | seed_notes:
        errors.append("note identity or count")
        wrong_state |= bool(set(notes) - (set(want_notes) | seed_notes))
    for name, phrases in want_notes.items():
        if name in notes and any(phrase.lower() not in notes[name].lower() for phrase in phrases):
            errors.append("note content")
            wrong_state = True
    for path, original in case.get("seed", {}).items():
        if path.startswith("notes/") and not notes.get(Path(path).name, "").startswith(original):
            errors.append("original note content changed")
            wrong_state = True
        if path in case.get("unchanged", []) and (home / path).read_text() != original:
            errors.append("unrelated item changed")
            wrong_state = True
    reminders = [p.read_text() for p in (home / "calendar").glob("*.ics")]
    wants = expected.get("reminders", [])
    if len(reminders) != len(wants): errors.append("reminder count")
    wrong_state |= len(reminders) > len(wants)
    tomorrow = (now.date() + datetime.timedelta(days=1)).strftime("%Y%m%d")
    for want in wants:
        stamp = want["time"].format(tomorrow=tomorrow)
        if not any("summary:" + want["title"].lower() + "\n" in text.lower()
                   and "DTSTART:" + stamp + "\n" in text and "BEGIN:VALARM\n" in text
                   for text in reminders):
            errors.append("reminder title, time or alarm")
    for text in reminders:
        if not any("summary:" + want["title"].lower() + "\n" in text.lower()
                   and "DTSTART:" + want["time"].format(tomorrow=tomorrow) + "\n" in text
                   and "BEGIN:VALARM\n" in text for want in wants):
            wrong_state = True
    config = home / "config/spark-shell/config"
    settings = config.read_text() if config.exists() else ""
    if any(line not in settings.splitlines() for line in expected.get("config", [])):
        errors.append("saved setting")
    if "sound" in expected and json.loads((home / "sound.json").read_text()) != expected["sound"]:
        errors.append("sound state")
    read_only = {t["name"] for e in events if e["method"] == "tools/list"
                 for t in e.get("result", {}).get("tools", [])
                 if t.get("annotations", {}).get("readOnlyHint") is True}
    calls = [e["params"]["name"] for e in events if e["method"] == "tools/call"
             and e["params"]["name"] not in read_only]
    alternatives = [case["calls"]] + case.get("alternate_calls", [])
    if calls not in alternatives: errors.append("operation sequence")
    wrong_sequence = not any(calls == option[:len(calls)] for option in alternatives)
    if any(e.get("error") or e.get("result", {}).get("isError") for e in events if e["method"] == "tools/call"):
        errors.append("provider refused operation")
    if calls and any(p in errors for p in ("saved setting", "sound state")):
        wrong_state = True
    return sorted(set(errors)), int(wrong_state or wrong_sequence)


def run_case(case, binary, root, live_env, capture):
    folder = root / case["id"]
    folder.mkdir(mode=0o700)
    home = folder / "home"
    home.mkdir(mode=0o700)
    for part in ("config/spark-shell", "state", "data", "cache", "run"):
        (home / part).mkdir(parents=True, mode=0o700, exist_ok=True)
    (home / "config/spark-shell/config").write_text("THEME=none\n")
    (home / "bin").mkdir()
    hostname = home / "bin/hostname"
    hostname.write_text("#!/bin/sh\nprintf 'fixture\\n'\n")
    hostname.chmod(0o700)
    uname = home / "bin/uname"
    uname.write_text("#!/bin/sh\ncase ${1:-} in -n) echo fixture ;; *) /usr/bin/uname \"$@\" ;; esac\n")
    uname.chmod(0o700)
    if "out" in case["providers"]:
        # The provider is production code; only the hardware owner is a fixture.
        # This cannot claim a real PipeWire graph or audible sound.
        (home / "sound.json").write_text(json.dumps({"level": 70, "muted": False}))
        stub = home / "bin/wpctl"
        stub.write_text("#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
p = Path(os.environ["HOME"]) / "sound.json"
s = json.loads(p.read_text())
a = sys.argv[1:]
if a == ["status"]:
 print("Audio\\n Sinks:\\n * 42. Desk speakers [vol: %.2f]\\n Sources:\\n" % (s["level"] / 100))
elif a[:1] == ["get-volume"]:
 print("Volume: %.2f%s" % (s["level"] / 100, " [MUTED]" if s["muted"] else ""))
elif a[:1] == ["set-volume"]:
 v = a[-1]; s["level"] = round(float(v.rstrip("%")) * (1 if v.endswith("%") else 100)); p.write_text(json.dumps(s))
elif a[:1] == ["set-mute"]:
 s["muted"] = not s["muted"] if a[-1] == "toggle" else a[-1] == "1"; p.write_text(json.dumps(s))
else: sys.exit(1)
''')
        stub.chmod(0o700)
        uname = home / "bin/uname"
        uname.write_text("#!/bin/sh\ncase ${1:-} in ''|-s) echo Linux ;; -m) echo x86_64 ;; -n) echo fixture ;; *) /usr/bin/uname \"$@\" ;; esac\n")
        uname.chmod(0o700)
    for name, content in case.get("seed", {}).items():
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    (folder / "case.json").write_text(json.dumps(case))
    helper_path = folder / "decision"
    helper_path.write_text("#!" + sys.executable + "\nimport runpy, sys\nsys.argv = " +
                           repr([str(Path(__file__).resolve()), "--helper", str(folder)]) +
                           "\nrunpy.run_path(sys.argv[0], run_name='__main__')\n")
    helper_path.chmod(0o700)
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / "config"), "XDG_STATE_HOME": str(home / "state"),
           "XDG_DATA_HOME": str(home / "data"), "XDG_CACHE_HOME": str(home / "cache"),
           "XDG_RUNTIME_DIR": str(home / "run"), "SPARK_SHELL_PTS_DIR": str(home / "pts"),
           "SPARK_SHELL_NO_APPLY": "1", "SPARK_SHELL_NO_CHIME": "1", "TZ": "UTC",
           "SPARK_SHELL_PROVIDE_POLL": "1", "TERM": "xterm-256color", "LANG": "C.UTF-8",
           "HEX_FG": "c0caf5", "HEX_ACCENT": "7aa2f7", "PANEL_BG": "282a38",
           "PANEL_HI": "373a4b", "PANEL_MUTED": "7b84ae"}
    env.update(live_env)
    env["PATH"] = str(home / "bin") + os.pathsep + env["PATH"]
    argv = ["--home", case["providers"][0], "--composer", "", "--spark", str(helper_path),
            "--spark-shell", str(REPO / "spark-shell")]
    for section in case["providers"]:
        argv += ["--provider", " ".join([sys.executable, str(Path(__file__).resolve()), "--provider", str(folder), section])]
    now = datetime.datetime.now(datetime.timezone.utc)
    started = time.monotonic()
    interaction_started = finished = None
    dialog = Dialog(binary, argv, env)
    problems, handled, answers, terminal, cancelled = [], 0, 0, "", False
    wrong_proposals = 0
    try:
        def ready():
            events = records(folder / "providers.jsonl")
            available = {(e["section"], e["method"]) for e in events}
            reads = [e for e in events if e["method"] == "resources/read"
                     and e["section"] == case["providers"][0]]
            rendered = False
            if reads:
                rows = json.loads(reads[-1]["result"]["contents"][0]["text"]).get("rows", [])
                screen = " ".join(dialog.screen.text().split()).lower()
                rendered = any(" ".join(row["text"][:24].split()).lower() in screen
                               for row in rows[:4] if row.get("text"))
            return (all((p, method) in available for p in case["providers"]
                        for method in ("tools/list", "resources/read"))
                    and rendered and "Type a request" in dialog.screen.text())
        if not dialog.wait(ready, 30):
            raise RuntimeError("dialog startup")
        if case.get("select"):
            reads = [e for e in records(folder / "providers.jsonl") if e["method"] == "resources/read"
                     and e["section"] == case["providers"][0]]
            rows = json.loads(reads[-1]["result"]["contents"][0]["text"])["rows"]
            target = next(i for i, row in enumerate(rows) if row["text"] == case["select"])
            dialog.send("\x1b[B" * (target + 1))
        interaction_started = time.monotonic()
        dialog.send(case["goal"] + "\r")
        if case.get("direct"):
            if not dialog.wait(lambda: any(e["method"] == "tools/call" for e in records(folder / "providers.jsonl")), 30):
                raise RuntimeError("direct operation timeout")
            if not dialog.wait(lambda: "nord is on" in dialog.screen.text(), 10):
                raise RuntimeError("direct receipt was not visible")
            terminal = "direct"
        else:
            for _ in range(30):
                if not dialog.wait(lambda: len(records(folder / "decisions.jsonl")) > handled
                                   or "type yes" in dialog.screen.text(), 90):
                    raise RuntimeError("decision timeout")
                if "type yes" in dialog.screen.text():
                    raise RuntimeError("unexpected destructive confirmation")
                decisions = records(folder / "decisions.jsonl")
                event = decisions[handled]
                handled += 1
                result = event["result"]
                status = result.get("status")
                if status in ("done", "answer", "blocked", "stopped"):
                    terminal = status
                    summary = result.get("summary", "")
                    def settled():
                        text = dialog.screen.text()
                        return ("Stop  Esc" not in text and "Discard" not in text and "Thinking" not in text
                                and (not summary or " ".join(summary.split()) in " ".join(text.split())))
                    if not dialog.wait(settled, 10):
                        problems.append("completion was not visible")
                    break
                if status == "ask":
                    if not dialog.wait(lambda: "Answer" in dialog.screen.text()):
                        raise RuntimeError("clarification was not visible")
                    available = case.get("answers", [])
                    if answers >= len(available):
                        problems.append("unexpected question")
                        dialog.send("\x1b")
                        terminal = "unanswered"
                        break
                    dialog.send(available[answers] + "\r")
                    answers += 1
                elif status == "step":
                    events = records(folder / "providers.jsonl")
                    read_only = {t["name"] for e in events if e["method"] == "tools/list"
                                 for t in e.get("result", {}).get("tools", [])
                                 if t.get("annotations", {}).get("readOnlyHint") is True}
                    proposed = result.get("step", {}).get("name", "")
                    native = proposed.split("_", 1)[-1]
                    if native not in set(case.get("permitted", case["calls"])) | read_only:
                        wrong_proposals += 1
                        raise RuntimeError("unexpected proposed operation held before execution")
                    # Preparation may ask a native question instead of staging.
                    if not dialog.wait(lambda: "Discard" in dialog.screen.text() or
                                       len(records(folder / "decisions.jsonl")) > handled, 30):
                        raise RuntimeError("proposal was not visible")
                    if len(records(folder / "decisions.jsonl")) > handled:
                        continue
                    called = [e for e in records(folder / "providers.jsonl") if e["method"] == "tools/call"]
                    if case.get("cancel") or ("cancel_after" in case and len(called) >= case["cancel_after"]):
                        dialog.send("\x1b")
                        cancelled, terminal = True, "cancelled"
                        dialog.wait(lambda: False, .3)
                        break
                    if capture:
                        (capture / (case["id"] + "-proposal.txt")).write_text(dialog.screen.text() + "\n")
                    dialog.send("\r")
                    # Only fixed non-destructive fixture operations are accepted.
                    # A dangerous proposal remains unconfirmed and fails this case.
                elif status != "inspect":
                    raise RuntimeError("invalid decision status")
            else:
                problems.append("decision limit")
    except (RuntimeError, OSError) as error:
        problems.append(str(error) if isinstance(error, RuntimeError) else "terminal failure")
    finally:
        finished = time.monotonic()
        if capture:
            (capture / (case["id"] + "-final.txt")).write_text(dialog.screen.text() + "\n")
        dialog.close()
    events = records(folder / "providers.jsonl")
    decisions = records(folder / "decisions.jsonl")
    native_problems, wrong_native = native_errors(case, home, events, now)
    problems += native_problems
    calls = [e for e in events if e["method"] == "tools/call"]
    read_only = {t["name"] for e in events if e["method"] == "tools/list"
                 for t in e.get("result", {}).get("tools", [])
                 if t.get("annotations", {}).get("readOnlyHint") is True}
    inference_times = [t for d in decisions for t in d["inferences"]]
    if case.get("select") and (not decisions or decisions[0]["request"].get("context", {}).get("selected", {}).get("text") != case["select"]):
        problems.append("focused reference was lost")
    if answers != case["questions"]: problems.append("clarification count")
    if case.get("direct") and decisions: problems.append("direct control requested AI")
    if not case.get("direct") and not cancelled and terminal != case.get("terminal", "done"):
        problems.append("task did not complete")
    permitted = set(case.get("permitted", case["calls"]))
    wrong = sum(e["params"]["name"] not in permitted and e["params"]["name"] not in read_only for e in calls)
    wrong = max(wrong, wrong_native)
    return {"id": case["id"], "passed": not problems, "problems": sorted(set(problems)),
            "terminal": terminal, "native_calls": len(calls), "wrong_actions": wrong,
            "wrong_proposals": wrong_proposals,
            "native_reads": sum(e["params"]["name"] in read_only for e in calls),
            "questions": answers, "decision_processes": len(decisions),
            "inference_calls": len(inference_times), "inference_seconds": inference_times,
            "startup_seconds": round((interaction_started or finished) - started, 3),
            "seconds": round(finished - (interaction_started or started), 3)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    parser.add_argument("--spark", type=Path, help="opt in to the installed Spark backend")
    parser.add_argument("--temperature", type=float,
                        help="explicit evaluation override; does not change Spark configuration")
    parser.add_argument("--only", help="comma-separated fixed case IDs")
    parser.add_argument("--set", choices=("development", "held-out"), default="development",
                        help="reserve held-out live cases until implementation is frozen")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--capture", type=Path, help="save synthetic terminal text for inspection")
    args = parser.parse_args()
    if args.temperature is not None and (not args.spark or not 0 <= args.temperature <= 1):
        parser.error("--temperature needs --spark and a value from 0 to 1")
    case_path = CASES if args.set == "development" else CASES.with_name("ax_heldout.json")
    cases = json.loads(case_path.read_text())
    if args.only:
        wanted = set(args.only.split(","))
        cases = [case for case in cases if case["id"] in wanted]
        if {case["id"] for case in cases} != wanted:
            parser.error("unknown case ID")
    live_env = {}
    backend = []
    if args.spark:
        args.spark = args.spark.resolve()
        sys.path.insert(0, str(args.spark / "lib"))
        from spark import config, wire
        cfg = config.load()
        brain = wire.resolve_brain(cfg)
        try:
            backend = [stem for role, stem, _ in wire.models(cfg, brain.url, forge=brain.forge) if role == "spark"]
        except Exception:
            backend = ["unavailable"]
        live_env["AX_SPARK"] = str(args.spark)
        live_env.update(SPARK_BASE_URL=brain.url, SPARK_CTX=str(cfg.ctx))
        if brain.forge:
            live_env["SPARK_FORGE_TOKEN"] = wire.forge_token(cfg)
        else:
            live_env["SPARK_API_KEY"] = wire.api_key(cfg)
        if args.temperature is not None:
            live_env["AX_TEMPERATURE"] = str(args.temperature)
    if args.capture: args.capture.mkdir(parents=True, exist_ok=True)
    binary = str(Path(args.binary).resolve())
    if any(c.isspace() for c in str(REPO) + sys.executable):
        parser.error("the dialog's provider argv requires a path without whitespace")
    with tempfile.TemporaryDirectory(prefix="spark-ax-") as temp:
        results = []
        for case in cases:
            result = run_case(case, binary, Path(temp), live_env, args.capture)
            results.append(result)
            print(("PASS " if result["passed"] else "FAIL ") + case["id"] +
                  " " + ", ".join(result["problems"]), flush=True)
    def revision(path):
        result = subprocess.run(["git", "-C", str(path), "describe", "--always", "--dirty"],
                                capture_output=True, text=True, timeout=5)
        return result.stdout.strip() if result.returncode == 0 else "unknown"
    source = hashlib.sha256()
    for path in sorted([REPO / "spark-shell", REPO / "dialog/Cargo.toml", REPO / "dialog/Cargo.lock"]
                       + list((REPO / "dialog/src").glob("*.rs")) + list((REPO / "lib").glob("*.py"))):
        source.update(str(path.relative_to(REPO)).encode() + b"\0" + path.read_bytes())
    report = {"schema": 1, "mode": "live" if args.spark else "scripted", "set": args.set,
              "date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "shell_ref": revision(REPO), "spark_ref": revision(args.spark) if args.spark else None,
              "backend": backend, "temperature_override": args.temperature,
              "binary_sha256": hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
              "source_sha256": source.hexdigest(),
              "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "platform": platform.system(), "cases_sha256": hashlib.sha256(case_path.read_bytes()).hexdigest(),
              "scope": "real terminal and native isolated files/settings; sound uses a backend fixture; no physical-device claim",
              "cases": results, "passed": sum(r["passed"] for r in results), "total": len(results),
              "wrong_actions": sum(r["wrong_actions"] for r in results)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("mode", "passed", "total", "wrong_actions")}))
    return int(report["passed"] != report["total"])


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--helper":
        # Providers retain synthetic HOME/XDG paths and do not receive the
        # decision process's live connection or credentials.
        helper(Path(sys.argv[2]))
    elif len(sys.argv) > 3 and sys.argv[1] == "--provider":
        provider(Path(sys.argv[2]), sys.argv[3])
    else:
        sys.exit(main())
