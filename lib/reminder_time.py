#!/usr/bin/env python3
"""Validate local reminder times and mint opaque event identities."""
import datetime as dt
import os
from pathlib import Path
import re
import sys
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def local_zone():
    name = os.environ.get("TZ", "").lstrip(":")
    if name in ("UTC0", "GMT0"):
        return dt.timezone.utc
    if name:
        if name.startswith("/"):
            with open(name, "rb") as stream:
                return ZoneInfo.from_file(stream)
        return ZoneInfo(name)
    with Path("/etc/localtime").open("rb") as stream:
        return ZoneInfo.from_file(stream)


def problem(value, title=""):
    # A zone immediately after the time could otherwise become the title.
    token = title.split(maxsplit=1)[0] if title else ""
    zones = {"UTC", "GMT", "EST", "EDT", "CST", "CDT", "MST", "MDT",
             "PST", "PDT", "BST", "CET", "CEST", "IST", "JST", "Z"}
    named_zone = False
    if "/" in token:
        try:
            ZoneInfo(token)
            named_zone = True
        except (ValueError, ZoneInfoNotFoundError):
            pass
    if token.upper() in zones or re.fullmatch(r"[+-]\d{2}:?\d{2}", token) or named_zone:
        return "Reminders use this computer's local time. What local day and time should I use, without a time-zone suffix?"
    try:
        when = dt.datetime.strptime(value, "%Y%m%d%H%M")
        zone = local_zone()
        instants = set()
        for fold in (0, 1):
            instant = when.replace(tzinfo=zone, fold=fold).astimezone(dt.timezone.utc)
            if instant.astimezone(zone).replace(tzinfo=None) == when:
                instants.add(instant)
        if not instants:
            return "That local time does not exist because the clock moves forward. What other local time should I use?"
        if len(instants) != 1:
            return "That local time occurs twice because the clock moves back. Choose a local time outside the repeated hour."
    except (ValueError, OSError, ZoneInfoNotFoundError):
        return "The local date or time zone could not be verified. Check the computer's time settings before creating the reminder."
    return ""


if __name__ == "__main__":
    if sys.argv[1:] == ["--uid"]:
        print("spark-shell-" + str(uuid.uuid4()))
        sys.exit(0)
    message = problem(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
    if message:
        print(message)
        sys.exit(1)
    print("ok")
