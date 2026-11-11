#!/usr/bin/env python3
"""modules_check.py [--report] -- the program's modules hold to their shape.

Reads the entry (spark-shell) and the modules it sources (src/*.sh) in that order,
comments removed, and checks:
  - every function is called somewhere (the entry, a module, a test); a function nothing
    names is dead;
  - a statement that runs at source time (outside every function) names no function and
    no global of a module sourced after it;
  - a module declares the globals it reads from other modules in a `# reads:` line and
    the globals it sets at source time in a `# sets:` line, both near its top.
--report prints the whole picture (functions, globals, their owners and readers) and the
declaration lines each module should carry, and exits 0. Without it, a finding is an
error and the exit code is 1.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENTRY = os.path.join(REPO, "spark-shell")
DEF = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*([{(])")
TRAIL = re.compile(r"^(.*\S)\s{2,}# .*$")
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
DEFAULT = re.compile(r'^:\s+"?\$\{([A-Za-z_][A-Za-z0-9_]*):=')
READ = re.compile(r"\$\{?[#!]?([A-Za-z_][A-Za-z0-9_]*)")
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
DECL = re.compile(r"^#\s*(reads|sets):\s*(.*)$")
ENV = set("HOME PATH TMPDIR USER SHELL TERM LANG LC_ALL PWD OLDPWD PPID IFS OPTARG OPTIND "
          "XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR XDG_VTNR XDG_SESSION_TYPE "
          "SWAYSOCK WAYLAND_DISPLAY DISPLAY SSH_CONNECTION SSH_TTY EDITOR VISUAL BROWSER COLUMNS LINES "
          "GITHUB_REF_NAME CARGO_HOME RUSTUP_HOME DEBIAN_FRONTEND".split())


def code_lines(path):
    """(lineno, text, in_function) per code line, comments gone; plus the declaration lines."""
    out, decls, depth, closer = [], {"reads": set(), "sets": set()}, 0, None
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            s = line.strip()
            m = DECL.match(s)
            if m and depth == 0:
                decls[m.group(1)] |= set(m.group(2).split())
                continue
            if not s or s.startswith("#"):
                continue
            m = TRAIL.match(line)
            if m and not m.group(1).count('"') % 2 and not m.group(1).count("'") % 2:
                line = m.group(1)
            d = DEF.match(line)
            if d and depth == 0:
                body = line[d.end():]
                opener = d.group(2)
                closer = "}" if opener == "{" else ")"
                if body.count(opener) + 1 == body.count(closer) and body.rstrip().endswith(closer):
                    out.append((n, line, d.group(1), True))   # a one-line function
                    continue
                depth = 1
                out.append((n, line, d.group(1), True))
                continue
            if depth and line.startswith(closer) and line.strip() == closer:
                depth = 0
                out.append((n, line, None, True))
                continue
            out.append((n, line, None, bool(depth)))
    return out, decls


def modules():
    names = []
    with open(ENTRY, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r'^\. "\$REPO/src/([a-z_]+)\.sh"$', line.strip())
            if m:
                names.append(m.group(1))
    return [("spark-shell", ENTRY)] + [(n, os.path.join(REPO, "src", n + ".sh")) for n in names]


def main():
    report = "--report" in sys.argv[1:]
    files = modules()
    order = {name: i for i, (name, _) in enumerate(files)}
    defs, owner, top_sets, reads, words, top_words, top_reads, decls = {}, {}, {}, {}, {}, {}, {}, {}
    for name, path in files:
        lines, decls[name] = code_lines(path)
        MODULE_TEXT[name] = "\n".join(text for _, text, _, _ in lines)
        top_sets[name], reads[name], words[name], top_words[name], top_reads[name] = set(), set(), set(), set(), set()
        for n, text, fn, inside in lines:
            if fn:
                defs.setdefault(fn, []).append((name, n))
                text = text[len(fn) + 2:]
            data = bool(ASSIGN.match(text) or DEFAULT.match(text))   # an assignment's right side is data, not a call...
            for w in WORD.findall(text):
                words[name].add(w)
                if not inside and not data:
                    top_words[name].add(w)
            if not inside and data:   # ...but a command substitution in it runs at source time
                for sub in re.findall(r"\$\(([^()]*)\)|`([^`]*)`", text):
                    for w in WORD.findall(sub[0] + " " + sub[1]):
                        top_words[name].add(w)
            for v in READ.findall(text):
                reads[name].add(v)
                if not inside:
                    top_reads[name].add(v)
            if not inside:
                a = ASSIGN.match(text) or DEFAULT.match(text)
                if a:
                    top_sets[name].add(a.group(1))
                    owner.setdefault(a.group(1), name)
    # names the tests use, so a function only a test names is kept and said
    test_words = set()
    for d in ("test",):
        for f in sorted(os.listdir(os.path.join(REPO, d))):
            if f.endswith((".sh", ".py")):
                with open(os.path.join(REPO, d, f), encoding="utf-8", errors="replace") as fh:
                    test_words |= set(WORD.findall(fh.read()))
    problems = []
    # 1. dead functions
    dead, test_only = [], []
    for fn, places in sorted(defs.items()):
        used = any(fn in words[m] for m in words if not (len(places) == 1 and places[0][0] == m and words_only_def(fn, m, files)))
        if not used:
            if fn in test_words:
                test_only.append((fn, places[0][0]))
            else:
                dead.append((fn, places[0][0]))
    for fn, m in dead:
        problems.append("dead: %s() in %s is called nowhere" % (fn, m))
    # 2. source-time forward references
    for name, _ in files:
        for w in sorted(top_words[name]):
            if w in defs and all(order[m] > order[name] for m, _ in defs[w]):
                problems.append("forward: %s runs %s() at source time, defined later in %s" % (name, w, defs[w][0][0]))
        for v in sorted(top_reads[name]):
            if v in owner and order[owner[v]] > order[name]:
                problems.append("forward: %s reads %s at source time, set later in %s" % (name, v, owner[v]))
    # 3. declarations
    want = {}
    for name, _ in files:
        foreign = {v for v in reads[name] if v in owner and owner[v] != name and v.isupper()}
        sets = {v for v in top_sets[name] if v.isupper()}
        want[name] = (foreign, sets)
        if name == "spark-shell":
            continue
        missing = foreign - decls[name]["reads"]
        extra = decls[name]["reads"] - foreign
        if missing:
            problems.append("reads: %s reads %s and does not say so" % (name, " ".join(sorted(missing))))
        if extra:
            problems.append("reads: %s says it reads %s and does not" % (name, " ".join(sorted(extra))))
        if sets != decls[name]["sets"]:
            problems.append("sets: %s sets %s at source time; its line says %s" % (name, " ".join(sorted(sets)) or "nothing", " ".join(sorted(decls[name]["sets"])) or "nothing"))
    if report:
        print("modules: %d (%s)" % (len(files) - 1, " ".join(n for n, _ in files[1:])))
        print("functions: %d defined, %d dead, %d named by tests alone" % (len(defs), len(dead), len(test_only)))
        for fn, m in dead:
            print("  dead  %-28s %s" % (fn, m))
        for fn, m in test_only:
            print("  tests %-28s %s" % (fn, m))
        multi = {fn: p for fn, p in defs.items() if len(p) > 1}
        if multi:
            print("functions defined twice: %s" % ", ".join("%s (%s)" % (fn, ", ".join(m for m, _ in p)) for fn, p in sorted(multi.items())))
        upper = sorted(v for v in owner if v.isupper())
        env_reads = sorted({v for m in reads for v in reads[m] if v.isupper() and v not in owner and v not in ENV and not v.startswith(("SPARK_SHELL_", "SPARK_"))})
        print("globals set at source time: %d (%d upper case); read but never set here, not the environment: %s" % (len(owner), len(upper), " ".join(env_reads) or "none"))
        for name, _ in files:
            foreign, sets = want[name]
            print("%s: sets %d, reads %d foreign" % (name, len(sets), len(foreign)))
            if sets:
                print("  # sets: " + " ".join(sorted(sets)))
            if foreign:
                print("  # reads: " + " ".join(sorted(foreign)))
        fwd = [p for p in problems if p.startswith("forward:")]
        print("forward references at source time: %d" % len(fwd))
        for p in fwd:
            print("  " + p)
        return 0
    for p in problems:
        print("modules check: " + p)
    if problems:
        print("modules check: %d problems" % len(problems))
        return 1
    print("modules check: %d modules, %d functions, every one called; the declarations hold" % (len(files) - 1, len(defs)))
    return 0


MODULE_TEXT = {}   # a module's code lines, comments gone, as one text


def words_only_def(fn, module, files):
    """True when the function's name appears in its own module only on its definition line."""
    return len(re.findall(r"\b%s\b" % re.escape(fn), MODULE_TEXT[module])) <= 1


if __name__ == "__main__":
    sys.exit(main())
