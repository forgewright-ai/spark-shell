#!/usr/bin/env python3
"""Assert actual dhcpcd state and kernel addressing in the isolated proof."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import network_dhcpcd as native
import network

assert os.geteuid() == 0
assert os.environ.get('SPARK_DHCPCD_PROOF_HOST_NET')
assert os.readlink('/proc/self/ns/net') != os.environ['SPARK_DHCPCD_PROOF_HOST_NET']
state = Path('/run/proof-receipts')
original = native.CONFIG.read_text()
for _ in range(100):
    try:
        pid, rows = native.owner('proof0')
        if native.live_matches(rows, native.DEFAULT):
            break
    except (OSError, native.Refused):
        pass
    time.sleep(.1)
else:
    raise AssertionError('the native DHCP client did not acquire the test lease')


def check(address, dns):
    data = json.loads(subprocess.check_output(
        ['ip', '-j', '-4', 'addr', 'show', 'dev', 'proof0']))
    assert [a['local'] for a in data[0]['addr_info']] == [address], data
    if dns is not None:
        assert 'nameserver ' + dns in Path('/etc/resolv.conf').read_text()


def action(name, value, *args):
    return network.run(state, name, value, list(args))

check('192.0.2.20', '192.0.2.53')
assert action('show', 'proof0')['profile'] == 'dhcpcd:proof0'
fixed = action('address', 'proof0', '192.0.2.8/24', '192.0.2.1')
check('192.0.2.8', None)
routes = json.loads(subprocess.check_output(
    ['ip', '-j', '-4', 'route', 'show', 'default', 'dev', 'proof0']))
assert routes[0]['gateway'] == '192.0.2.1', routes
print('PASS: native static IPv4 and gateway', flush=True)
dns = action('dns', 'proof0', '198.51.100.53')
check('192.0.2.8', '198.51.100.53')
print('PASS: native DNS and private root receipt', flush=True)
assert (native.STATE / (dns['undo'] + '.json')).stat().st_mode & 0o777 == 0o600
assert json.loads((state / (dns['undo'] + '.json')).read_text()) == {'backend': 'dhcpcd'}
action('restore', dns['undo'])
action('restore', fixed['undo'])
assert native.CONFIG.read_text() == original
check('192.0.2.20', '192.0.2.53')
print('PASS: exact undo and native DHCP recovery', flush=True)
action('address', 'proof0', '192.0.2.9/24', 'none')
action('auto', 'proof0')
check('192.0.2.20', '192.0.2.53')
print('PASS: automatic IPv4', flush=True)
dns = action('dns', 'proof0', '198.51.100.53')
auto = action('dns', 'proof0', 'auto')
check('192.0.2.20', '192.0.2.53')
print('PASS: automatic DNS from the native lease', flush=True)
before_failure = native.CONFIG.read_text()
try:
    # The test server already owns this address: real native DAD must fail.
    action('address', 'proof0', '192.0.2.1/24', 'none')
except network.Refused as exc:
    assert 'prior native network settings restored' in str(exc), exc
else:
    raise AssertionError('a duplicate address received a success receipt')
assert native.CONFIG.read_text() == before_failure
check('192.0.2.20', '192.0.2.53')
print('PASS: native duplicate-address failure and verified recovery', flush=True)

caller = int(os.environ.get('SUDO_UID', '0'))
if caller:
    client_state = Path('/run/proof-client')
    client_state.mkdir(mode=0o700)
    os.chown(client_state, caller, -1)
    command = ['sudo', '-n', '-u', '#' + str(caller), sys.executable, '-I',
               str(Path(network.__file__)), '--state', str(client_state)]
    before_permission = native.CONFIG.read_text()
    result = subprocess.run(command + ['dns', 'proof0', '198.51.100.53'],
                            capture_output=True, text=True, timeout=50)
    if result.returncode:
        assert ('password is required' in result.stderr or
                'not allowed to execute' in result.stderr), result.stderr
        assert native.CONFIG.read_text() == before_permission
        print('PASS: native permission refusal leaves config intact', flush=True)
    else:
        receipt = json.loads(result.stdout)
        check('192.0.2.20', '198.51.100.53')
        result = subprocess.run(command + ['restore', receipt['undo']],
                                capture_output=True, text=True, timeout=50)
        assert result.returncode == 0, result.stderr
        assert native.CONFIG.read_text() == before_permission
        check('192.0.2.20', '192.0.2.53')
        print('PASS: ordinary user, native sudo permission and undo', flush=True)

native.CONFIG.write_text(native.CONFIG.read_text() + '# later native edit\n')
try:
    action('restore', auto['undo'])
except network.Refused as exc:
    assert 'changed since' in str(exc), exc
else:
    raise AssertionError('stale undo overwrote a later native edit')
print('PASS: later native edit preserved', flush=True)
