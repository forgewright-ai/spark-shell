#!/usr/bin/env python3
"""Native regression proof for the shared home/apps interaction contract.

Usage: python3 test/apps_contract_desktop_proof.py BINARY EVIDENCE_DIRECTORY
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
        title = len(lines[2]) - len(lines[2].lstrip())  # the column's edge: the prompt sign, two cells in
        attach = lines[4].index("attach")  # the prompt's tools, the fourth row
        observations.append({"capture": name, "rect": s.window()["rect"], "title_column": title, "attach_column": attach})
        return title, attach

    def apps(listed="btop"):
        s.click("apps", body=True)
        wait_for(lambda: listed in s.text(), "installed catalog")

    def details():
        s.key("btop", "-k", "F9")
        wait_for(lambda: "preferences" in s.text(), "Details")

    try:
        preferences = s.root / ".config/spark-shell/apps.json"
        # an app with no preference of its own has no entry: Undo puts the file back as it was
        hidden = lambda: json.loads(preferences.read_text())["apps"].get("btop.desktop", {}).get("hidden", False)
        apps()
        details()
        s.click("hide this app")
        assert "btop++ hidden" in s.text() and "undo" in s.text(), s.text()
        assert hidden(), "saved at once"
        capture("01-applied-at-once")
        s.click("undo")
        assert not hidden(), "undo on the status row puts the preference back"
        s.click("hide this app")
        assert hidden()
        s.key("-k", "Escape")
        # Esc clears the receipt, as it does everywhere, and goes back; nothing is asked. The list still
        # holds the words btop, which name no visible app now
        assert "Save before leaving?" not in s.text() and s.screen()[0].find("apps") >= 0, s.text()
        assert "undo" not in s.text() and "no app matches" in s.text(), s.text()
        capture("02-back-without-a-question")
        s.key("-k", "Escape")
        s.key("undo", "-k", "Return")
        assert not hidden(), "typed undo takes the last change of Apps back, after the receipt is gone"
        assert "btop" in s.text()
        details()
        s.click("hide this app")
        assert hidden()
        s.click("×")
        wait_for(lambda: not s.window(), "the x closes at once, nothing asked")
        assert hidden(), "the change stands after the close"
        s.key("-M", "logo", "-k", "space", "-m", "logo")
        wait_for(s.window, "reopen")
        time.sleep(2)
        apps("hidden apps")  # btop is hidden now: the list leaves it out, and says so in the count
        s.click("hidden apps", body=True)
        s.key("-k", "Down", "-k", "F9")
        wait_for(lambda: "preferences" in s.text(), "the hidden app's details")
        s.click("hide this app")
        assert not hidden(), "shown again from the hidden apps"
        s.key("-k", "Escape", "-k", "Escape")
        s.key("btop")
        s.key("-k", "F10")
        assert s.screen()[0].find("conversation") >= 0
        s.key("retain this request draft", "-k", "F10")
        assert "btop" in s.screen()[2], "the app query is its own"
        capture("03-restored-app-query")
        s.key("-k", "F10")
        assert "retain this request draft" in s.screen()[2], "the request draft is its own"
        capture("04-restored-request")
        s.key("-k", "F10")
        s.checks.append("A change applies at once, is said with Undo and survives Esc and the close without a question; request and app query restore separately")

        s.key("-k", "Escape")
        s.click("edit categories", body=True)
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
        assert not hidden(), "a refused change leaves the file as it was"
        capture("06-save-failure")
        config.chmod(0o700)
        s.key("-k", "Escape")
        assert "btop" in s.screen()[2], "back to the list, its words kept"
        s.key("-k", "Escape", "-k", "Escape")
        assert "retain this request draft" in s.screen()[2], "home again, with the request draft"
        s.key("-k", "Escape")  # explicitly clear the restored global draft
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
            # the title sits two cells into the frame and the prompt's tools start under the prompt's words, two
            # cells further: one frame, as component/dialog/tests/chrome.rs has it (the dialog design notes)
            assert home_anchor[1] == home_anchor[0] + 2, "the header and the tools row share the frame"
            apps()
            assert s.window()["rect"] == rect
            assert capture("apps-" + mode) == home_anchor, "apps and home share one 60 cell column"
            if mode in ("left", "right"):
                snaps.append(s.screen()[1:])
            s.key("-k", "Escape")
            s.click("files", body=True)
            wait_for(lambda: s.screen()[0].find("files") >= 0, "files")
            assert s.window()["rect"] == rect
            files_anchor = capture("files-" + mode)
            assert files_anchor[1] == files_anchor[0] + 2, "files' header and tools row share its frame, the wide one"
            assert files_anchor[0] <= home_anchor[0], "a list with columns takes up to 120 cells, never less than home's 60"
            s.key("-k", "Escape")
        assert snaps[0] == snaps[1]
        s.checks.append("Home and apps share one 60 cell column and files its 120 cell one, header and tools row in the frame, in compact, fullscreen and both snaps; equal snap bodies match")

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
