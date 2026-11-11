#!/usr/bin/env python3
"""Semantic search in an isolated native Sway/foot session (v0.130). No user desktop changes.

Usage: python3 test/semantic_desktop_proof.py BINARY EVIDENCE_DIRECTORY [MODEL.gguf]
The real launcher, providers and EmbeddingGemma 2 on spark's own llama.cpp server, in a scratch home; spark itself is
a deterministic fixture. Needs sway, foot, wtype and spark's engine. The helpers are home_desktop_proof.py's.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("home_proof", REPO / "test/home_desktop_proof.py")
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)

# spark, as the dialog calls it: the model in use, and for steps the one tool offered filled from fixed values
FIXTURE = '''#!/usr/bin/env python3
import json, sys
from pathlib import Path
here = Path(__file__)
if sys.argv[1:2] == ['model']: print('fixture-model\\tserving')
elif sys.argv[1:2] == ['client']: print('spark client -- local')
elif sys.argv[1:2] == ['voice']: sys.exit(1)
elif sys.argv[1:2] == ['steps']:
    tools = json.load(sys.stdin)['tools']
    here.with_suffix('.steps').write_text(json.dumps({'argv': sys.argv[1:], 'tools': [t['name'] for t in tools]}))
    t = tools[0]
    props = t['inputSchema'].get('properties', {})
    def value(p):
        if p.get('enum'): return p['enum'][0]
        return {'integer': 5, 'number': 5, 'boolean': True}.get(p.get('type'), 'tomorrow 9:00 call the dentist')
    args = {k: value(props[k]) for k in t['inputSchema'].get('required', [])}
    print(json.dumps({'answer': '', 'steps': [{'name': t['name'], 'arguments': args}], 'refused': []}))
elif len(sys.argv) == 2 and ' ' in sys.argv[1]:
    here.with_suffix('.asked').write_text(sys.argv[1])
    print('Fixture answer to: ' + sys.argv[1])
'''


def main(binary, destination, model=None):
    for tool in ("sway", "swaymsg", "foot", "wtype"):
        if not shutil.which(tool):
            raise SystemExit("missing native tool: " + tool)
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    model = Path(model or data / "spark-shell/models/embeddinggemma-2-Q8_0.gguf").resolve()
    engine = data / "spark/engine"
    if not model.is_file() or not engine.is_dir():
        raise SystemExit("needs the model (%s) and spark's engine (%s)" % (model, engine))
    evidence = Path(destination).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    binary = str(Path(binary).resolve())
    checks = []
    with tempfile.TemporaryDirectory(prefix="semantic-proof-") as tmp:
        root = Path(tmp)
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        (root / ".config/spark-shell").mkdir(parents=True)
        (root / ".config/spark-shell/config").write_text(
            "DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\nDIALOG_ATTACH=no\nDIALOG_TALK=no\nDIALOG_MODEL=yes\nDIALOG_SEMANTIC=yes\n")
        (root / ".config/spark").mkdir()
        shutil.copyfile(REPO / "gallery/theme/tokyonight-night.env", root / ".config/spark/theme.env")
        fixtures = root / "bin"
        fixtures.mkdir()
        spark = fixtures / "spark"
        spark.write_text(FIXTURE)
        spark.chmod(0o700)
        foot = root / ".config/foot"
        foot.mkdir()
        colors, palette = home.native_foot_config(root)
        template = (REPO / "template/.config/foot/dialog.ini").read_text()
        for old, new in {"@HOME@": tmp, "@PANEL_SIZE@": "60x40", "@PANEL_PAD@": "0x0", "@FOOT_COLORS@": colors,
                         "@PANEL_BG@": palette["colors"]["PANEL_BG"]}.items():
            template = template.replace(old, new)
        dump = fixtures / "screen-dump"
        dump.write_text("from pathlib import Path\nimport sys\n(Path.home() / 'screen.txt').write_text(sys.stdin.read())\n")
        template += "\n[key-bindings]\npipe-visible=[python3 " + str(dump) + "] Control+Shift+F12\n"
        (foot / "dialog.ini").write_text(template)
        # the model and spark's engine, linked in only now: the palette's probe above must start no server
        (root / "data/spark-shell").mkdir(parents=True)
        (root / "data/spark-shell/models").symlink_to(model.parent)
        (root / "data/spark").mkdir()
        (root / "data/spark/engine").symlink_to(engine)
        env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": str(root / ".config"), "XDG_RUNTIME_DIR": str(runtime),
               "XDG_STATE_HOME": str(root / "state"), "XDG_DATA_HOME": str(root / "data"), "XDG_CACHE_HOME": str(root / "cache"),
               "PATH": str(fixtures) + os.pathsep + os.environ["PATH"],
               "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1",
               "SPARK_SHELL_DIALOG": binary, "SPARK_DIALOG_SLOTS": "1", "SPARK_SHELL_NO_APPLY": "1",
               "SPARK_SHELL_PTS_DIR": str(root / "ptys"), "SPARK_SHELL_ROOT": str(root / "sysroot")}
        for key in ("SWAYSOCK", "WAYLAND_DISPLAY", "DISPLAY"):
            env.pop(key, None)
        config = root / "sway.conf"
        source = (REPO / "template/.config/sway/config").read_text().replace("@REPO@", str(REPO))
        keys = [line for line in source.splitlines() if line.startswith("bindsym ") and "desktop home" in line]
        config.write_text('set $mod Mod4\noutput HEADLESS-1 mode 1440x1000\nxwayland disable\nseat seat0 fallback true\n'
                          'for_window [app_id="spark-dialog"] floating enable, border none, move position center\n'
                          + "\n".join(keys) + "\n")
        with (root / "native.log").open("w") as log:
            compositor = subprocess.Popen(["sway", "-c", str(config)], env=env, stdout=log, stderr=log)
            keyboard = None
            try:
                env["SWAYSOCK"] = str(home.wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "sway"))
                env["WAYLAND_DISPLAY"] = home.wait_for(
                    lambda: next((p.name for p in runtime.glob("wayland-*") if p.is_socket()), None), "wayland")
                keyboard = subprocess.Popen(["wtype", "-s", "600000"], env=env, stdout=log, stderr=log)

                def key(*args):
                    subprocess.run(["wtype", "-s", "100", *args, "-s", "100"], env=env, check=True, timeout=5)
                    time.sleep(.2)

                def windows():
                    def walk(node):
                        return ([node] if node.get("app_id") == "spark-dialog" else []) + [
                            w for n in node.get("nodes", []) + node.get("floating_nodes", []) for w in walk(n)]
                    return walk(json.loads(subprocess.check_output(["swaymsg", "-r", "-t", "get_tree"], env=env, timeout=5)))

                def screen(name):
                    file = root / "screen.txt"
                    file.unlink(missing_ok=True)
                    key("-M", "ctrl", "-M", "shift", "-k", "F12", "-m", "shift", "-m", "ctrl")
                    home.wait_for(file.exists, "terminal screen dump")
                    text = file.read_text()
                    (evidence / (name + ".txt")).write_text(text)
                    return text

                def running():
                    out = subprocess.run(["sh", str(REPO / "spark-shell"), "semantic", "status"], env=env,
                                         capture_output=True, text=True, timeout=10).stdout
                    return "running at" in out

                def ask(words, wait=1.5):
                    # typed at home's empty prompt: the search rests, the semantic search answers, the list settles
                    key(words)
                    time.sleep(wait)

                key("-M", "logo", "-k", "space", "-m", "logo")
                home.wait_for(lambda: windows(), "home window")
                home.wait_for(running, "the semantic search server")
                checks.append("The launcher started the semantic search server on the session's socket; spark-shell semantic status says it runs")
                time.sleep(8)   # the providers' rows, then their vectors (the warm-up)

                # 1. a page found by what the words mean, opened by Enter with no model call
                ask("show me all running process", wait=3)
                listed = screen("1-running-found")
                assert "running" in listed, "running is among the matches"
                key("-k", "Return")
                time.sleep(2)
                page = screen("1-running-opened")
                assert not spark.with_suffix(".steps").exists() and not spark.with_suffix(".asked").exists(), "no model call"
                assert "running" in page.splitlines()[0] or "running" in "".join(page.splitlines()[:3]), "the running page is open"
                checks.append("'show me all running process' finds running by meaning; Enter opens the page, no model call")

                # 2. a step found by meaning: spark reads its values with that one tool offered, and it waits for Enter
                key("-k", "Escape")
                ask("remind me tomorrow at 9 to call the dentist", wait=3)
                screen("2-remind-found")
                key("-k", "Return")
                request = json.loads(home.wait_for(lambda: spark.with_suffix(".steps").exists()
                                                   and spark.with_suffix(".steps").read_text(), "the fill request"))
                assert request["tools"] == ["reminders_add"], request
                time.sleep(1)
                staged = screen("2-remind-staged")
                assert "reminders" in staged and "run:" in staged, "the step waits in the prompt for Enter"
                checks.append("'remind me tomorrow at 9 to call the dentist' finds reminders_add; Enter asks spark with that one tool, and the step waits for Enter")
                key("-k", "Escape")

                # 3. words that name nothing on the desktop: the ask row, spark answers in words
                ask("what is the capital of France", wait=3)
                key("-k", "Return")
                asked = home.wait_for(lambda: spark.with_suffix(".asked").exists()
                                      and spark.with_suffix(".asked").read_text(), "the question")
                assert asked == "what is the capital of France", asked
                time.sleep(1)
                answer = screen("3-answer")
                assert "Fixture answer to: what is the capital of France" in answer.replace("\n", " ") or "Fixture answer" in answer
                checks.append("'what is the capital of France' lights the ask row; spark answers it in words, as spark WORDS")

                # 4. in the list of apps, words that name no app (#250): the theme's setting stands under the apps,
                # found by meaning, and Enter opens it; spark is not asked (it once answered `spark look on`)
                spark.with_suffix(".asked").unlink()
                key("-k", "Escape")
                time.sleep(1)
                ask("apps", wait=1)
                key("-k", "Return")
                time.sleep(2)
                assert "apps" in "".join(screen("4-apps").splitlines()[:3]), "the list of apps is open"
                ask("change theme", wait=3)
                found = screen("4-change-theme-found")
                # a setting shows what it holds now (`theme  tokyonight-night`), under the kind's heading
                assert "no app matches" in found and "settings" in found and re.search(r"^ +theme +\S", found, re.M), \
                    "the theme's setting is found by meaning"
                key("-k", "Return")
                time.sleep(2)
                opened = screen("4-change-theme-opened")
                assert "theme" in "".join(opened.splitlines()[:3]) and "run:" not in opened, \
                    "Enter opened the theme; no step of it waits in the prompt"
                assert not spark.with_suffix(".asked").exists(), "spark was not asked"
                checks.append("'change theme' typed in the list of apps names no app; the theme's setting stands under them, "
                              "found by meaning, and Enter opens the theme, no model call (#250)")
            finally:
                if keyboard:
                    keyboard.terminate()
                    keyboard.wait(timeout=5)
                compositor.terminate()
                try:
                    compositor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                home.stop_round(env)
    (evidence / "semantic.json").write_text(json.dumps({"binary": binary, "model": str(model), "checks": checks}, indent=2) + "\n")
    for check in checks:
        print("ok: " + check)


if __name__ == "__main__":
    main(*sys.argv[1:])
