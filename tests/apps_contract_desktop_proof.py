#!/usr/bin/env python3
"""Native regression proof for the shared home/apps interaction contract.

Usage: python3 tests/apps_contract_desktop_proof.py BINARY EVIDENCE_DIRECTORY
Real Void catalog and Sway/foot; isolated preferences; optional AI is a fixture.
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
        attach = next(line.index("Attach") for line in lines[-5:] if "Attach" in line)
        observations.append({"capture": name, "rect": s.window()["rect"], "title_column": title, "attach_column": attach})
        return title, attach

    def apps():
        s.click("apps", body=True)
        wait_for(lambda: "btop" in s.text(), "installed catalog")

    def details():
        s.key("btop", "-k", "Right")
        wait_for(lambda: "Preferences" in s.text(), "Details")

    try:
        apps()
        details()
        s.click("Visibility")
        capture("01-unsaved-preferences")
        s.key("-k", "Escape")
        assert "Save before leaving?" in s.text()
        capture("02-exit-decision")
        s.key("-k", "Escape")
        assert "Unsaved preferences" in s.text() and "Hidden from Apps" in s.text()
        # The actual close button uses the same guard.
        s.click("\u00d7")
        assert s.window() and "Save before leaving?" in s.text()
        s.click("Keep editing", body=True)
        assert "Unsaved preferences" in s.text()
        s.key("-k", "F2")
        assert "Save before leaving?" in s.text()
        s.click("Save", body=True)
        assert s.screen()[0].lstrip().startswith("conversation")
        preferences = s.root / ".config/spark-shell/apps.json"
        assert json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"]
        s.key("retain this request draft", "-k", "F2")
        s.click("Visibility")
        s.click("Save", body=True)
        s.key("-k", "Escape")
        assert "btop" in s.screen()[2]
        s.key("-k", "F2")
        assert "retain this request draft" in s.screen()[2]
        capture("03-restored-request")
        s.key("-k", "F2")
        assert "btop" in s.screen()[2]
        capture("04-restored-app-query")
        s.checks.append("Dirty Esc, close and conversation navigation require Save/Discard/Keep editing; Esc keeps edits; Save persists before navigation; request and app query restore separately")

        s.key("-k", "Escape")
        s.click("Manage categories")
        s.click("Create category")
        s.key("Writing", "-k", "Escape")
        assert "Writing" in s.screen()[2] and "Save before leaving?" in s.text()
        capture("05-category-exit-decision")
        s.key("-k", "Escape")
        assert "Writing" in s.screen()[2]
        s.click("Cancel", body=True)
        assert "Writing" not in json.loads(preferences.read_text())["categories"]
        s.key("-k", "Escape")
        details()
        s.click("Visibility")
        config = preferences.parent
        config.chmod(0o500)
        s.click("Save", body=True)
        assert "not saved" in s.text() and "Unsaved preferences" in s.text()
        assert not json.loads(preferences.read_text())["apps"]["btop.desktop"]["hidden"]
        capture("06-save-failure")
        config.chmod(0o700)
        s.key("-k", "Escape")
        s.click("Discard", body=True)
        assert "btop" in s.screen()[2]
        s.key("-k", "Escape", "-k", "Escape")
        assert "retain this request draft" in s.screen()[2]
        s.key("-k", "Escape")  # explicitly clear the restored global draft
        s.checks.append("Category Esc retains the field and Cancel discards; real permission failure retains draft and stored value; Discard completes the pending navigation")

        # A shared frame with module-specific bodies, at identical window sizes.
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
            assert capture("files-" + mode) == home_anchor
            s.key("-k", "Escape")
        assert snaps[0] == snaps[1]
        s.checks.append("Home/apps/files retain identical header and footer anchors and window geometry in compact/fullscreen/both snaps; equal snap bodies match")

        s.normal()
        fixture = s.root / "bin/spark"
        fixture.write_text('#!/bin/sh\ncase $1 in client) echo "spark client -- local";; esac\n')
        s.click("\u00d7")
        wait_for(lambda: not s.window(), "clean close")
        s.key("-M", "logo", "-k", "space", "-m", "logo")
        wait_for(s.window, "reopen")
        time.sleep(2)
        apps()
        details()
        assert "No model" in s.text() and "Preferences" in s.text()
        capture("07-details-ai-unavailable")
        s.checks.append("Persisted preferences and native Details remain available after restart with AI unavailable")
        (s.evidence / "contract.json").write_text(json.dumps({"binary_sha256": s.binary_sha256,
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
