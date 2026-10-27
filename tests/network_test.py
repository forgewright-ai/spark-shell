#!/usr/bin/env python3
"""Network profile transactions: only native IPv4 fields, exact undo and failure."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("network", REPO / "lib/network.py")
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)
UUID = "00000000-1111-2222-3333-444444444444"


class Network(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name) / "network"
        self.original = dict(zip(network.FIELDS, ("auto", "", "", "", "no")))
        self.settings = self.original.copy()
        self.calls = []
        self.fail_reapply = False
        self.active = UUID
        self.mock = patch.object(network, "native", self.native)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def native(self, *args):
        self.calls.append(args)
        if args[:2] == ("-g", "GENERAL.CON-UUID"):
            return self.active
        if args[:3] == ("--escape", "no", "-g"):
            return self.settings[args[3]]
        if args[:3] == ("connection", "modify", "uuid"):
            self.assertEqual(args[3], UUID)
            self.settings = dict(zip(args[4::2], args[5::2]))
            self.assertEqual(set(self.settings), set(network.FIELDS))
            return ""
        if args[:2] == ("device", "reapply"):
            if self.fail_reapply:
                self.fail_reapply = False
                raise network.Refused("reapply failed")
            return ""
        raise AssertionError(args)

    def test_static_dns_auto_and_exact_undo(self):
        result = network.run(self.folder, "address", "eth0", ["192.0.2.8/24", "192.0.2.1"])
        self.assertEqual(self.settings["ipv4.addresses"], "192.0.2.8/24")
        self.assertEqual(self.settings["ipv4.method"], "manual")
        self.assertEqual((self.folder / (result["undo"] + ".json")).stat().st_mode & 0o777, 0o600)
        dns = network.run(self.folder, "dns", "eth0", ["192.0.2.53,198.51.100.53"])
        self.assertEqual(self.settings["ipv4.ignore-auto-dns"], "yes")
        self.assertEqual(self.settings["ipv4.addresses"], "192.0.2.8/24")
        network.run(self.folder, "restore", dns["undo"], [])
        network.run(self.folder, "restore", result["undo"], [])
        self.assertEqual(self.settings, self.original)
        network.run(self.folder, "address", "eth0", ["192.0.2.8/24", "none"])
        network.run(self.folder, "auto", "eth0", [])
        self.assertEqual(self.settings, self.original)

    def test_reapply_failure_restores_profile_and_live_settings(self):
        self.fail_reapply = True
        with self.assertRaisesRegex(network.Refused, "previous settings restored"):
            network.run(self.folder, "address", "eth0", ["192.0.2.8/24", "192.0.2.1"])
        self.assertEqual(self.settings, self.original)
        self.assertEqual(sum(call[:2] == ("device", "reapply") for call in self.calls), 2)
        self.assertFalse(any(json.loads(p.read_text())["ready"] for p in self.folder.glob("*.json")))

    def test_undo_preserves_later_native_edits_and_refuses_another_profile(self):
        result = network.run(self.folder, "dns", "eth0", ["192.0.2.53"])
        saved = self.settings.copy()
        self.settings["ipv4.dns"] = "198.51.100.53"
        with self.assertRaisesRegex(network.Refused, "changed since"):
            network.run(self.folder, "restore", result["undo"], [])
        self.assertEqual(self.settings["ipv4.dns"], "198.51.100.53")
        self.settings = saved
        self.active = "00000000-1111-2222-3333-555555555555"
        with self.assertRaisesRegex(network.Refused, "changed since"):
            network.run(self.folder, "restore", result["undo"], [])

    def test_invalid_values_and_unmanaged_interfaces_never_write(self):
        for action, values in [("address", ["192.0.2.8", "192.0.2.1"]), ("address", ["192.0.2.8/24", "198.51.100.1"]), ("dns", ["192.0.2.53;exec"]), ("dns", ["224.0.0.1"]), ("auto", ["extra"])]:
            with self.subTest(action=action, values=values), self.assertRaises(network.Refused):
                network.run(self.folder, action, "eth0", values)
        self.active = "--"
        with self.assertRaisesRegex(network.Refused, "native manager keeps control"):
            network.run(self.folder, "dns", "eth0", ["192.0.2.53"])
        self.assertEqual(self.settings, self.original)
        self.assertFalse(self.folder.exists())


class Provider(unittest.TestCase):
    def test_setup_uses_native_services_and_never_replaces_an_owner(self):
        for family, package, manager in (("debian", "network-manager", "apt-get"),
                                         ("arch", "networkmanager", "pacman"),
                                         ("void", "NetworkManager", "xbps-install"),
                                         ("fedora", "NetworkManager", "dnf"),
                                         ("opensuse", "NetworkManager", "zypper")):
            with self.subTest(family=family), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                bins = root / "bin"
                bins.mkdir()
                # Only these programs exist in this isolated native fixture.
                for name in ("sh", "id", "dirname", "sed", "tr", "grep", "sort", "paste", "cut", "awk", "mktemp", "rm", "mkdir", "cat", "date", "readlink", "jq", "ln", "chmod", "env", "head", "tail", "wc", "basename"):
                    if path := shutil.which(name):
                        (bins / name).symlink_to(path)
                (bins / "uname").write_text("#!/bin/sh\necho Linux\n")
                (bins / "sudo").write_text('#!/bin/sh\nexec "$@"\n')
                for name in (manager, "systemctl", "sv"):
                    (bins / name).write_text('#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$NETWORK_TEST_ROOT/native.log"\n')
                for path in bins.iterdir():
                    if not path.is_symlink():
                        path.chmod(0o755)
                (root / "os-release").write_text("ID=" + family + "\n")
                native = root / "native"
                if family == "void":
                    for name in ("etc/runit", "etc/sv/dbus", "etc/sv/NetworkManager"):
                        (native / name).mkdir(parents=True)
                else:
                    (native / "run/systemd/system").mkdir(parents=True)
                env = {**os.environ, "HOME": tmp, "PATH": str(bins),
                       "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                       "SPARK_SHELL_ROOT": str(native), "SPARK_OS_RELEASE": str(root / "os-release"),
                       "NETWORK_TEST_ROOT": tmp}
                def run(*flags):
                    return subprocess.run(["/bin/sh", str(REPO / "spark-shell"), "desktop", "network", "setup", *flags],
                                          env=env, text=True, capture_output=True, timeout=20)
                dry = run("--dry-run")
                self.assertEqual(dry.returncode, 0, dry.stderr + dry.stdout)
                self.assertIn(package, dry.stdout)
                self.assertFalse((root / "native.log").exists())
                applied = run("--yes")
                self.assertEqual(applied.returncode, 0, applied.stderr + applied.stdout)
                log = (root / "native.log").read_text()
                self.assertIn(package, log)
                self.assertIn("sv up" if family == "void" else "systemctl enable --now NetworkManager", log)
                if family == "void":
                    self.assertTrue((native / "var/service/dbus").is_symlink())
                    self.assertTrue((native / "var/service/NetworkManager").is_symlink())
                (bins / "dhcpcd").write_text("#!/bin/sh\nexit 1\n")
                (bins / "dhcpcd").chmod(0o755)
                refused = run("--yes")
                self.assertNotEqual(refused.returncode, 0)
                self.assertIn("keeps control", refused.stdout)
                self.assertEqual((root / "native.log").read_text(), log)

    def test_hidden_network_uses_each_native_backend_without_password_arguments(self):
        for backend in ("nmcli", "iwctl", "wpa_cli"):
            with self.subTest(backend=backend), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                (root / "config/spark-shell").mkdir(parents=True)
                (root / "config/spark-shell/config").write_text("DESKTOP=sway\n")
                (root / "sys/class/net/wlan0/wireless").mkdir(parents=True)
                (root / "os-release").write_text("ID=fixture\n")
                (bin_dir / "uname").write_text("#!/bin/sh\necho Linux\n")
                stub = "#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
r=Path(os.environ["NETWORK_TEST_ROOT"]); name=Path(sys.argv[0]).name; a=sys.argv[1:]
with (r/"argv").open("a") as f: f.write(json.dumps([name,*a])+"\\n")
if name=="wpa_passphrase":
    pw=sys.stdin.read(); print("#psk="+pw); print("psk="+"a"*64); sys.exit()
if name != os.environ["NETWORK_TEST_BACKEND"]: sys.exit(1)
if name=="nmcli":
    if a==["-t","-f","RUNNING","general"]: print("running")
    elif a[:5]==["--ask","dev","wifi","connect","hidden cafe"]:
        (r/"received").write_text(sys.stdin.read()); print("connected")
elif name=="iwctl":
    if a==["station","wlan0","show"]: print("Station wlan0")
    elif a==["station","wlan0","connect-hidden","hidden cafe"]: (r/"received").write_text(sys.stdin.read())
elif name=="wpa_cli":
    if a[:2]==["-i","wlan0"]: a=a[2:]
    if not a: (r/"wire").write_text(sys.stdin.read()); print("OK")
    elif a==["status"]:
        if (r/"selected").exists(): print("ssid=hidden cafe\\nwpa_state=COMPLETED")
    elif a==["add_network"]: print(2)
    elif a[:1]==["select_network"]: (r/"selected").touch(); print("OK")
    else: print("OK")
'''
                for name in ("nmcli", "iwctl", "wpa_cli", "wpa_passphrase"):
                    (bin_dir / name).write_text(stub)
                for path in bin_dir.iterdir():
                    path.chmod(0o755)
                env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                       "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                       "SPARK_SHELL_SYS": str(root / "sys"), "SPARK_OS_RELEASE": str(root / "os-release"),
                       "NETWORK_TEST_ROOT": tmp, "NETWORK_TEST_BACKEND": backend}
                password = 'quoted "password" with spaces'
                request = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "wifi_hidden", "arguments": {"name": "hidden cafe", "password": password}}})
                out = subprocess.run([str(REPO / "spark-shell"), "provide", "wifi"], input=request + "\n", text=True, capture_output=True, env=env, timeout=20)
                self.assertEqual(out.returncode, 0, out.stderr)
                result = json.loads(out.stdout)
                self.assertFalse(result["result"].get("isError"), result)
                self.assertIn("connected to hidden cafe", result["result"]["structuredContent"]["receipt"])
                argv = (root / "argv").read_text()
                self.assertNotIn(password, argv + out.stdout + out.stderr)
                self.assertNotIn("a" * 64, argv + out.stdout + out.stderr)
                if backend == "wpa_cli":
                    self.assertEqual((root / "wire").read_text(), "set_network 2 psk " + "a" * 64 + "\n")
                    self.assertIn('"scan_ssid", "1"', argv)
                else:
                    self.assertEqual((root / "received").read_text().rstrip("\n"), password)
                    self.assertIn('"hidden", "yes"' if backend == "nmcli" else '"connect-hidden"', argv)

    def test_native_profile_rows_mutation_receipt_and_guarded_undo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            config = root / "config/spark-shell"
            config.mkdir(parents=True)
            (config / "config").write_text("DESKTOP=sway\n")
            (root / "os-release").write_text("ID=fixture\n")
            iface = root / "sys/class/net/eth0"
            iface.mkdir(parents=True)
            for name, value in {"device": "", "type": "1", "carrier": "1", "operstate": "up"}.items():
                (iface / name).write_text(value)
            original = dict(zip(network.FIELDS, ("auto", "", "", "", "no")))
            (root / "profile.json").write_text(json.dumps(original))
            programs = {"uname": "#!/bin/sh\necho Linux\n", "ip": "#!/bin/sh\nexit 0\n",
                        "nmcli": "#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
p=Path(os.environ["NETWORK_TEST_ROOT"])/"profile.json"
a=sys.argv[1:]
if a[:4] == ["--wait","15","--colors","no"]: a=a[4:]
if a[:2] == ["-g","GENERAL.CON-UUID"]: print("00000000-1111-2222-3333-444444444444")
elif a[:3] == ["--escape","no","-g"]: print(json.loads(p.read_text())[a[3]])
elif a[:3] == ["connection","modify","uuid"]: p.write_text(json.dumps(dict(zip(a[4::2],a[5::2]))))
elif a[:2] == ["device","reapply"]: pass
else: sys.exit(1)
'''}
            for name, content in programs.items():
                path = bin_dir / name
                path.write_text(content)
                path.chmod(0o755)
            env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                   "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
                   "SPARK_SHELL_SYS": str(root / "sys"), "SPARK_SHELL_ROOT": str(root / "native"),
                   "SPARK_OS_RELEASE": str(root / "os-release"), "NETWORK_TEST_ROOT": tmp}
            def rpc(method, params):
                payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
                out = subprocess.run([str(REPO / "spark-shell"), "provide", "lan"], input=payload + "\n", text=True,
                                     capture_output=True, env=env, timeout=20)
                self.assertEqual(out.returncode, 0, out.stderr)
                return next(json.loads(line) for line in out.stdout.splitlines() if json.loads(line).get("id") == 1)
            rows = rpc("resources/read", {"uri": "spark-shell://lan/rows"})
            listed = json.loads(rows["result"]["contents"][0]["text"])["rows"]
            self.assertTrue(any(r.get("children") == "spark-shell://lan/rows/network/eth0" for r in listed), listed)
            settings = rpc("resources/read", {"uri": "spark-shell://lan/rows/network/eth0"})
            controls = json.loads(settings["result"]["contents"][0]["text"])["rows"]
            self.assertTrue(any(r.get("tool", {}).get("ask") == ["address", "gateway"] for r in controls))
            result = rpc("tools/call", {"name": "lan_address", "arguments": {"device": "eth0", "address": "192.0.2.8/24", "gateway": "192.0.2.1"}})
            self.assertFalse(result["result"].get("isError"), result)
            undo = result["result"]["structuredContent"]["undo"]
            self.assertEqual(undo["name"], "lan_restore")
            self.assertEqual(json.loads((root / "profile.json").read_text())["ipv4.addresses"], "192.0.2.8/24")
            result = rpc("tools/call", undo)
            self.assertFalse(result["result"].get("isError"), result)
            self.assertEqual(json.loads((root / "profile.json").read_text()), original)
            bad = rpc("tools/call", {"name": "lan_dns", "arguments": {"device": "eth0", "servers": "192.0.2.53;exec"}})
            self.assertIn("error", bad)
            self.assertEqual(json.loads((root / "profile.json").read_text()), original)


if __name__ == "__main__":
    unittest.main()
