#!/usr/bin/env python3
"""Use the configured CUPS service and its queues; never discover or add servers."""
import json
import os
import re
import subprocess
import sys


class Refused(Exception):
    pass


def native(program, *args):
    try:
        result = subprocess.run([program, *args], stdin=subprocess.DEVNULL,
                                text=True, capture_output=True, timeout=5,
                                env={**os.environ, "LC_ALL": "C"})
    except FileNotFoundError as exc:
        raise Refused("the native CUPS tools are not installed") from exc
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Refused("the native print service did not answer") from exc
    if result.returncode:
        if program == "lpstat" and args in (("-p",), ("-d",)) and any(
            phrase in (result.stdout + result.stderr).lower()
            for phrase in ("no destinations added", "no system default destination")
        ):
            return ""
        raise Refused("the native print service refused the request; check its service and permissions")
    return result.stdout


def queue_name(value):
    return bool(re.fullmatch(r"[^\s/#\x00-\x1f\x7f-][^\s/#\x00-\x1f\x7f]{0,126}", value))


def status():
    queues = []
    for line in native("lpstat", "-p").splitlines():
        match = re.match(r"printer (\S+) (.*)", line)
        if match and queue_name(match[1]):
            queues.append({"name": match[1], "enabled": "disabled" not in match[2], "state": match[2]})
    default = native("lpstat", "-d").strip().partition(": ")[2]
    jobs = []
    # No document names, device URIs or jobs owned by another person.
    for line in native("lpstat", "-W", "not-completed", "-u").splitlines():
        words = line.split()
        if words and re.fullmatch(r".+-[0-9]+", words[0]):
            queue, _, number = words[0].rpartition("-")
            if any(item["name"] == queue for item in queues):
                jobs.append({"id": words[0], "queue": queue, "number": number})
    return {"queues": queues, "default": default, "jobs": jobs}


def act(action, target):
    current = status()
    if action == "cancel":
        job = next((item for item in current["jobs"] if item["id"] == target), None)
        if not job:
            raise Refused("that job is no longer in your native print queue")
        native("cancel", job["number"])
        if any(item["id"] == target for item in status()["jobs"]):
            raise Refused("the print service still lists that job; cancellation is not confirmed")
        return {"receipt": "cancelled print job " + target}
    queue = next((item for item in current["queues"] if item["name"] == target), None)
    if not queue:
        raise Refused("that printer is not in the configured native queues")
    if action == "default":
        if os.environ.get("LPDEST") or os.environ.get("PRINTER"):
            raise Refused("a printer environment override is active; change it before choosing a default")
        if current["default"] == target:
            return {"receipt": target + " is already the default printer"}
        native("lpoptions", "-d", target)
        if status()["default"] != target:
            raise Refused("the native service did not report the chosen default printer")
        return {"receipt": "default printer is " + target}
    if action in ("pause", "resume"):
        enabled = action == "resume"
        if queue["enabled"] == enabled:
            return {"receipt": target + (" is already enabled" if enabled else " is already paused")}
        native("cupsenable" if enabled else "cupsdisable", target)
        after = next((item for item in status()["queues"] if item["name"] == target), None)
        if not after or after["enabled"] != enabled:
            raise Refused("the native service did not confirm the printer state")
        return {"receipt": ("enabled " if enabled else "paused ") + target}
    raise Refused("printers take default, pause, resume or cancel")


def main():
    try:
        if sys.argv[1:] == ["status"]:
            result = status()
        elif len(sys.argv) == 3:
            result = act(sys.argv[1], sys.argv[2])
        else:
            raise Refused("printers take status or an action and a native queue or job")
        print(json.dumps(result))
        return 0
    except Refused as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
