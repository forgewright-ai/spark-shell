#!/usr/bin/env python3
"""Basic IPv4 settings through the active native network manager.

No passwords are read. Undo holds only the five IPv4 fields changed here.
Other managers retain ownership; an unsupported owner is a refusal.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

FIELDS = ("ipv4.method", "ipv4.addresses", "ipv4.gateway", "ipv4.dns", "ipv4.ignore-auto-dns")


class Refused(Exception):
    pass


def native(*args):
    try:
        result = subprocess.run(["nmcli", "--wait", "15", "--colors", "no", *args],
                                text=True, capture_output=True, stdin=subprocess.DEVNULL,
                                timeout=20, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Refused("NetworkManager did not answer; check the native connection") from exc
    if result.returncode:
        raise Refused("NetworkManager refused the change; check native permissions and connection settings")
    return result.stdout.strip()


def device_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,15}", value):
        raise Refused("choose a native network interface")
    return value


def profile(device):
    value = native("-g", "GENERAL.CON-UUID", "device", "show", device_name(device))
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value):
        raise Refused("this interface has no active NetworkManager profile; its native manager keeps control")
    return value


def read(uuid):
    return {key: native("--escape", "no", "-g", key, "connection", "show", "uuid", uuid) for key in FIELDS}


def write(uuid, values):
    args = ["connection", "modify", "uuid", uuid]
    for key in FIELDS:
        args.extend((key, values[key]))
    native(*args)


def changes(action, values):
    if action == "auto" and not values:
        return {"ipv4.method": "auto", "ipv4.addresses": "", "ipv4.gateway": ""}
    if action == "address" and len(values) == 2:
        address, gateway = values
        try:
            if "/" not in address:
                raise ValueError()
            net = ipaddress.IPv4Interface(address)
            if net.ip.is_unspecified or net.ip.is_multicast or net.ip.is_loopback:
                raise ValueError()
            if gateway != "none":
                route = ipaddress.IPv4Address(gateway)
                if route not in net.network or route.is_unspecified or route.is_multicast or route == net.ip:
                    raise ValueError()
        except ValueError as exc:
            raise Refused("use an IPv4 address with prefix and a gateway on that network, or none") from exc
        return {"ipv4.method": "manual", "ipv4.addresses": str(net), "ipv4.gateway": "" if gateway == "none" else gateway}
    if action == "dns" and len(values) == 1:
        if values[0] == "auto":
            return {"ipv4.dns": "", "ipv4.ignore-auto-dns": "no"}
        try:
            servers = [ipaddress.IPv4Address(x) for x in values[0].split(",")]
            if not 1 <= len(servers) <= 3 or any(x.is_unspecified or x.is_multicast for x in servers):
                raise ValueError()
        except ValueError as exc:
            raise Refused("DNS is auto or one to three IPv4 addresses separated by commas") from exc
        return {"ipv4.dns": ",".join(map(str, servers)), "ipv4.ignore-auto-dns": "yes"}
    raise Refused("network settings take address, auto or dns with their values")


def save(folder, token, record):
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(folder, 0o700)
    fd, tmp = tempfile.mkstemp(dir=folder)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(record, stream)
        os.replace(tmp, folder / (token + ".json"))
    finally:
        Path(tmp).unlink(missing_ok=True)


def apply(folder, device, uuid, before, after):
    if before == after:
        return {"receipt": "network settings already match"}
    token = hashlib.sha256(os.urandom(32)).hexdigest()
    record = {"device": device, "uuid": uuid, "before": before, "after": after, "ready": False}
    save(folder, token, record)  # a crash leaves recovery evidence before any native write
    attempted = after
    try:
        if profile(device) != uuid or read(uuid) != before:
            raise Refused("the native connection changed; read its settings again")
        write(uuid, after)
        attempted = read(uuid)  # native serialization may normalize address lists
        native("device", "reapply", device)
        if profile(device) != uuid or read(uuid) != attempted:
            raise Refused("the native connection changed during apply")
    except Refused as exc:
        # Restore only fields still equal to our attempted write. External edits win.
        try:
            current = read(uuid)
            if current == before:
                raise Refused(str(exc) + "; previous profile settings remain") from exc
            if current != attempted or profile(device) != uuid:
                raise Refused(str(exc) + "; the connection changed again, so inspect it in the native manager") from exc
            write(uuid, before)
            native("device", "reapply", device)
        except Refused as recovery:
            raise Refused(str(recovery)) from exc
        raise Refused(str(exc) + "; previous settings restored") from exc
    record["after"] = attempted
    record["ready"] = True
    save(folder, token, record)
    return {"receipt": "native network settings applied to " + device, "undo": token}


def dhcpcd(folder, action, device, values):
    helper = Path(__file__).with_name("network_dhcpcd.py")
    command = [sys.executable, "-I", str(helper), action, device, *values]
    if action != "show" and os.geteuid() != 0:
        command = ["sudo", "-n", *command]
    try:
        result = subprocess.run(command, text=True, capture_output=True,
                                stdin=subprocess.DEVNULL, timeout=50)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Refused("the native dhcpcd helper did not answer") from exc
    if result.returncode:
        raise Refused(result.stderr.strip() or "native dhcpcd permission is required")
    try:
        output = json.loads(result.stdout)
        if "undo" in output:
            save(folder, output["undo"], {"backend": "dhcpcd"})
        return output
    except (ValueError, TypeError, KeyError) as exc:
        raise Refused("the native dhcpcd helper returned an invalid receipt") from exc


def run(folder, action, device, values):
    if action == "restore":
        if values or not re.fullmatch(r"[0-9a-f]{64}", device):
            raise Refused("choose an undo receipt from a network change")
        try:
            record = json.loads((folder / (device + ".json")).read_text())
            if record.get("backend") == "dhcpcd":
                return dhcpcd(folder, action, device, values)
            if not record["ready"] or set(record["before"]) != set(FIELDS) or set(record["after"]) != set(FIELDS):
                raise ValueError()
            old = record["before"]
            now = record["after"]
            device = device_name(record["device"])
            uuid = profile(device)
            if uuid != record["uuid"] or read(uuid) != now:
                raise Refused("network settings changed since this receipt; undo leaves those changes alone")
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise Refused("that network undo receipt is not available") from exc
        return apply(folder, device, uuid, now, old)
    device_name(device)
    update = None if action == "show" else changes(action, values)
    try:
        uuid = profile(device)
    except Refused:
        if sys.platform == "linux" and Path("/run/dhcpcd/unpriv.sock").is_socket():
            return dhcpcd(folder, action, device, values)
        raise
    before = read(uuid)
    if action == "show":
        return {"device": device, "profile": uuid, "settings": before}
    if before["ipv4.method"] not in ("auto", "manual"):
        raise Refused("this connection uses a special native mode; change it in the native manager")
    return apply(folder, device, uuid, before, {**before, **update})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("action", choices=("show", "address", "auto", "dns", "restore"))
    parser.add_argument("device")
    parser.add_argument("values", nargs="*")
    args = parser.parse_args()
    try:
        if args.check:
            if args.action == "restore":
                if args.values or not re.fullmatch(r"[0-9a-f]{64}", args.device):
                    raise Refused("choose a network undo receipt")
            else:
                device_name(args.device)
                changes(args.action, args.values)
            return 0
        print(json.dumps(run(args.state, args.action, args.device, args.values)))
        return 0
    except (Refused, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
