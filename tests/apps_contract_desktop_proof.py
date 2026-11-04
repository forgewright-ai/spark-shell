#!/usr/bin/env python3
"""Native regression proof for the shared home/apps interaction contract.

Usage: python3 tests/apps_contract_desktop_proof.py BINARY EVIDENCE_DIRECTORY
Real Void catalog and Sway/foot; isolated preferences; optional AI is a fixture.
A change of Apps applies at once and Undo takes it back; nothing asks before
you leave; the request draft and the app query are kept apart; home, apps and
files share one frame in every window mode.
"""
import json
from pathlib import Path
import subprocess
import sys
import time

from apps_desktop_proof import Session, wait_for


def main(binary, destination):
    s = Session(binary, destination)
    observations = []

    def capture(name):
        s.capture(name)
        lines = s.screen()
        (s.evidence / (name + ".txt")).write_text("\n".join(lines) + "\n")
        title = len(lines[0]) - len(lines[0].lstrip())
        attach = next(line.index("attach") for line in lines[-5:] if "attach" in line)
        observations.append({"capture": name, "rect": s.window()["rect"], "title_column": title, "attach_column": attach})
        return title, attach

    def apps():
        s.click("apps", body=True)
        wait_for(lambda: "btop" in s.text(), "installed catalog")

    def details():
        s.key("btop", "-k", "Right")
        wait_for(lambda: "preferences" in s.text(), "Details")

    try:
        preferences = s.root / ".config/spark-shell/apps.json"
        apps()
        details()
        s.click("hide this app")
        assert "btop++ hidden" in s.text() and "Undo" in s.text(), s.text()
        assert json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"], "saved at once"
        capture("01-applied-at-once")
        s.key("-k", "Escape")
        assert "Save before leaving?" not in s.text() and s.screen()[0].lstrip().startswith("apps"), "Esc goes back, nothing asked"
        capture("02-back-without-a-question")
        s.click("Undo")
        assert not json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"], "Undo puts the preference back"
        details()
        s.click("hide this app")
        s.click("×")
        wait_for(lambda: not s.window(), "the x closes at once, nothing asked")
        assert json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"], "the change stands after the close"
        s.key("-M", "logo", "-k", "space", "-m", "logo")
        wait_for(s.window, "reopen")
        time.sleep(2)
        apps()
        s.key("btop")
        s.key("-k", "F2")
        assert s.screen()[0].lstrip().startswith("conversation")
        s.key("retain this request draft", "-k", "F2")
        assert "btop" in s.screen()[2], "the app query is its own"
        capture("03-restored-app-query")
        s.key("-k", "F2")
        assert "retain this request draft" in s.screen()[2], "the request draft is its own"
        capture("04-restored-request")
        s.key("-k", "F2")
        s.checks.append("A change applies at once, is said with Undo and survives Esc and the close without a question; request and app query restore separately")

        s.key("-k", "Escape")
        s.click("categories", body=True)
        s.click("new category")
        s.key("Writing", "-k", "Escape")
        assert "Writing" not in json.loads(preferences.read_text())["categories"], "Esc lets a form go"
        assert "Save before leaving?" not in s.text() and "categories" in s.text()
        capture("05-form-let-go")
        s.key("-k", "Escape")
        details()
        config = preferences.parent
        config.chmod(0o500)
        s.click("hide this app")
        assert "not saved" in s.text(), s.text()
        assert json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"], "a refused change leaves the file as it was"
        capture("06-save-failure")
        config.chmod(0o700)
        s.key("-k", "Escape", "-k", "Escape")
        assert "btop" in s.screen()[2]
        s.key("-k", "Escape", "-k", "Escape", "-k", "F2")
        assert "retain this request draft" in s.screen()[2]
        s.key("-k", "Escape")  # explicitly clear the restored global draft
        s.key("-k", "F2")
        s.checks.append("A form's Esc keeps nothing and asks nothing; a real permission failure is refused on the status row and the stored value stands")

        # One frame for every view, at identical window sizes.
        snaps = []
        for mode in ("compact", "fullscreen", "left", "right"):
            if mode == "fullscreen":
                s.key("-M", "logo", "-k", "f", "-m", "logo")
            elif mode == "left":
                s.key("-M", "logo", "-k", "f", "-m", "logo")
                s.key("-M", "logo", "-k", "Left", "-m", "logo")
            elif mode == "right":
                s.key("-M", "logo", "-k", "Right", "-m", "logo")
            time.sleep(1)
            rect = s.window()["rect"]
            home_anchor = capture("home-" + mode)
            apps()
            assert s.window()["rect"] == rect
            assert capture("apps-" + mode) == home_anchor
            if mode in ("left", "right"):
                snaps.append(s.screen()[1:])
            s.key("-k", "Escape")
            s.click("files", body=True)
            wait_for(lambda: s.screen()[0].lstrip().startswith("files"), "files")
            assert s.window()["rect"] == rect
            assert capture("files-" + mode)[1] == home_anchor[1], "the footer shares the frame"
            s.key("-k", "Escape")
        assert snaps[0] == snaps[1]
        s.checks.append("Home and apps share one 60 cell column, files its 120 cell one, with the same footer anchor, in compact, fullscreen and both snaps; equal snap bodies match")

        s.normal()
        fixture = s.root / "bin/spark"
        fixture.write_text('#!/bin/sh\ncase $1 in client) echo "spark client -- local";; esac\n')
        s.click("×")
        wait_for(lambda: not s.window(), "clean close")
        s.key("-M", "logo", "-k", "space", "-m", "logo")
        wait_for(s.window, "reopen")
        time.sleep(2)
        apps()
        details()
        assert "no model" in s.text() and "preferences" in s.text()
        capture("07-details-ai-unavailable")
        s.checks.append("Persisted preferences and native Details remain available after restart with AI unavailable")
        (s.evidence / "contract.json").write_text(json.dumps({"binary_sha256": s.binary_sha256,
            "palette": s.palette,
            "environment": "Void Linux; native headless Sway/foot; real installed catalog; isolated preferences; model/voice fixtures",
            "checks": s.checks, "observations": observations}, indent=2) + "\n")
        print(json.dumps(s.checks, indent=2), flush=True)
    except Exception:
        print(s.text(), flush=True)
        s.capture("failure")
        raise
    finally:
        (s.root / ".config/spark-shell").chmod(0o700)
        s.close()


if __name__ == "__main__":
    main(*sys.argv[1:])
