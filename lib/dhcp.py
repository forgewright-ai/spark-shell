#!/usr/bin/env python3
"""IPv4 settings for dhcpcd's native, single-interface configuration.

The 10.3 control protocol is the one used by dhcpcd's own clients. Read the
live owner before editing its fixed config path. Root keeps private undo
records; the caller gets only a token. No service is started or replaced.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import socket
import stat
import struct
import sys
import tempfile
import time

# Also works when invoked by the permission helper with Python isolation.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from network import Refused, changes, device_name, FIELDS

CONFIG = Path('/etc/dhcpcd.conf')
STATE = Path('/var/lib/spark-shell-network')
SOCKET = '/run/dhcpcd/sock'
READ_SOCKET = '/run/dhcpcd/unpriv.sock'
NATIVE = {'ip_address', 'routers', 'domain_name_servers'}
DEFAULT = dict(zip(FIELDS, ('auto', '', '', '', 'no')))


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def connect(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(3)
    try:
        sock.connect(path)
        # Linux reports the server's credentials, not a client-supplied PID.
        peer = struct.unpack('3i', sock.getsockopt(
            socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        if peer[1] != 0:
            raise Refused('the native network socket is not root owned')
        return sock, peer[0]
    except Exception:
        sock.close()
        raise


def take(sock, count):
    data = b''
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise Refused('dhcpcd closed its native control connection')
        data += part
    return data


def size(sock, limit):
    value = struct.unpack('@N', take(sock, struct.calcsize('@N')))[0]
    if value > limit:
        raise Refused('dhcpcd returned an unsupported control response')
    return value


def block(sock):
    return take(sock, size(sock, 1048576)).decode().rstrip('\0')


def query(command):
    sock, pid = connect(READ_SOCKET)
    with sock:
        sock.sendall(command.encode() + b'\0')
        if command == '--getinterfaces':
            result = [dict(x.split('=', 1) for x in block(sock).split('\0')
                           if '=' in x) for _ in range(size(sock, 1024))]
        else:
            result = block(sock)
    return pid, result


def owner(device, expected=None):
    pid, version = query('--version')
    if not re.fullmatch(r'10\.3\.[0-9]+', version):
        raise Refused('this dhcpcd control version is not supported yet')
    config_pid, config = query('--getconfigfile')
    state_pid, rows = query('--getinterfaces')
    if (pid != config_pid or pid != state_pid or
            expected is not None and pid != expected or config != str(CONFIG)):
        raise Refused('the native network owner or config changed')
    rows = [r for r in rows if r.get('interface') == device]
    if not rows:
        raise Refused('dhcpcd does not own this interface')
    return pid, rows


def read_config():
    fd = os.open(CONFIG, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
                info.st_mode & 0o022 or info.st_nlink != 1 or
                info.st_size > 1048576):
            raise Refused('the native network config needs administrator review')
        return stream.read(), info


def section(text, device):
    """Keep native lines verbatim; refuse ambiguous scopes and special modes."""
    lines = text.splitlines(keepends=True)
    start, end, scope = len(lines), len(lines), None
    settings = DEFAULT.copy()
    found = set()
    for i, line in enumerate(lines):
        words = line.split('#', 1)[0].strip().split(None, 1)
        if not words:
            continue
        key, value = words[0], words[1].strip() if len(words) > 1 else ''
        if key in ('profile', 'ssid', 'fallback', 'include') or '\\' in line:
            raise Refused('use native dhcpcd settings for profiles or special scopes')
        if key == 'interface':
            if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}', value):
                raise Refused('use native dhcpcd settings for interface patterns')
            if scope == device:
                end = i
            scope = value
            if scope == device:
                if start != len(lines):
                    raise Refused('the native interface has more than one section')
                start = i
            continue
        if scope not in (None, device):
            continue
        if key in ('noipv4', 'nodhcp', 'inform', 'request', 'arping',
                   'noarp', 'nogateway', 'ipv4only', 'ipv6only', 'nooption'):
            raise Refused('use native dhcpcd settings for this special mode')
        if key == 'nohook' and 'resolv.conf' in value.split(','):
            raise Refused('native DNS hooks are disabled for this connection')
        if key != 'static':
            continue
        field, sep, val = value.partition('=')
        if field not in NATIVE:
            if field in ('ip6_address', 'domain_search', 'domain_name'):
                continue
            raise Refused('use native dhcpcd settings for custom static options')
        if scope is None or not sep or field in found:
            raise Refused('use native dhcpcd settings for shared or repeated IPv4 fields')
        found.add(field)
        if field == 'ip_address':
            settings.update(changes('address', [val, 'none']))
        elif field == 'routers':
            if val:
                settings['ipv4.gateway'] = val
        elif val:
            settings.update(changes('dns', [','.join(val.split())]))
        else:
            raise Refused('use native dhcpcd settings for explicitly disabled DNS')
    if 'routers' in found and settings['ipv4.method'] == 'auto':
        raise Refused('use native dhcpcd settings for custom DHCP routes')
    if settings['ipv4.gateway']:
        changes('address', [settings['ipv4.addresses'], settings['ipv4.gateway']])
    return ''.join(lines[:start]), ''.join(lines[start:end]), ''.join(lines[end:]), settings


def render(old, device, settings):
    kept = []
    for line in old.splitlines(keepends=True):
        words = line.split('#', 1)[0].strip().split(None, 1)
        if (len(words) == 2 and words[0] == 'static' and
                words[1].partition('=')[0] in NATIVE):
            continue
        kept.append(line)
    if not old:
        kept.append('interface ' + device + '\n')
    if kept and not kept[-1].endswith('\n'):
        kept[-1] += '\n'
    if settings['ipv4.method'] == 'manual':
        kept.append('static ip_address=' + settings['ipv4.addresses'] + '\n')
        kept.append('static routers=' + settings['ipv4.gateway'] + '\n')
    if settings['ipv4.ignore-auto-dns'] == 'yes':
        kept.append('static domain_name_servers=' +
                    settings['ipv4.dns'].replace(',', ' ') + '\n')
    return ''.join(kept)


def replace_config(before, after, info):
    # Never follow a replacement link or silently overwrite a later native edit.
    current, now = read_config()
    if current != before or (now.st_ino, now.st_dev) != (info.st_ino, info.st_dev):
        raise Refused('native network settings changed during apply')
    fd, name = tempfile.mkstemp(prefix='.spark-network-', dir=CONFIG.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
            os.fchown(stream.fileno(), info.st_uid, info.st_gid)
            stream.write(after)
            stream.flush()
            os.fsync(stream.fileno())
        current, now = read_config()
        if current != before or (now.st_ino, now.st_dev) != (info.st_ino, info.st_dev):
            raise Refused('native network settings changed during apply')
        os.replace(name, CONFIG)
    finally:
        Path(name).unlink(missing_ok=True)


def rebind(device, pid):
    owner(device, pid)
    listener, server = connect(READ_SOCKET)
    try:
        if server != pid:
            raise Refused('the native network owner changed')
        listener.sendall(b'--listen\n\0--version\n\0')
        if not block(listener).startswith('10.3.'):
            raise Refused('the native network owner changed')
        sock, server = connect(SOCKET)
        with sock:
            if server != pid:
                raise Refused('the native network owner changed')
            # The CLI can start a daemon. Address only the existing owner.
            sock.sendall(b'dhcpcd\0-n\0' + device.encode() + b'\n\0'
                         b'--version\n\0')
            if not block(sock).startswith('10.3.'):
                raise Refused('the native network owner changed')
        return listener
    except Exception:
        listener.close()
        raise


def live_matches(rows, settings):
    for row in rows:
        if row.get('if_up') != 'true' or not row.get('new_ip_address'):
            continue
        if settings['ipv4.method'] == 'manual':
            address = row['new_ip_address'] + '/' + row.get('new_subnet_cidr', '')
            if address != settings['ipv4.addresses'] or row.get('reason') != 'STATIC':
                continue
            if row.get('new_routers', '') != settings['ipv4.gateway']:
                continue
        elif (not row.get('new_dhcp_server_identifier') or
              row.get('reason') not in ('BOUND', 'RENEW', 'REBIND', 'REBOOT')):
            continue
        if (settings['ipv4.ignore-auto-dns'] == 'yes' and
                row.get('new_domain_name_servers', '').split() !=
                settings['ipv4.dns'].split(',')):
            continue
        return True
    return False


def await_live(device, pid, settings, text, listener):
    deadline = time.monotonic() + 15
    with listener:
        while time.monotonic() < deadline:
            owner(device, pid)
            if read_config()[0] != text:
                raise Refused('native network settings changed during apply')
            if not select.select([listener], [], [], .2)[0]:
                continue
            row = dict(x.split('=', 1) for x in block(listener).split('\0')
                       if '=' in x)
            if row.get('interface') == device and live_matches([row], settings):
                # The event belongs to this apply, including DNS -> automatic.
                if read_config()[0] != text:
                    raise Refused('native network settings changed during apply')
                return
    raise Refused('dhcpcd did not confirm the requested IPv4 settings')


def write_record(token, record):
    fd, name = tempfile.mkstemp(dir=STATE)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(record, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, STATE / (token + '.json'))
    finally:
        Path(name).unlink(missing_ok=True)


def transaction(device, before, after, old, new, settings, pid, uid):
    if before == after:
        return {'receipt': 'network settings already match'}
    token = hashlib.sha256(os.urandom(32)).hexdigest()
    record = dict(device=device, uid=uid, before=old, after=new,
                  expected=digest(after), ready=False)
    write_record(token, record)
    current, info = read_config()
    if current != before:
        raise Refused('native network settings changed during apply')
    owner(device, pid)
    replace_config(before, after, info)
    try:
        listener = rebind(device, pid)
        await_live(device, pid, settings, after, listener)
    except (OSError, Refused) as exc:
        current, info = read_config()
        if current != after:
            raise Refused('native network settings changed; inspect them before recovery') from exc
        owner(device, pid)
        replace_config(after, before, info)
        try:
            listener = rebind(device, pid)
            await_live(device, pid, section(before, device)[3], before, listener)
        except (OSError, Refused) as recovery:
            raise Refused('prior config restored; native connection recovery is not confirmed') from recovery
        raise Refused('apply failed; prior native network settings restored') from exc
    record['ready'] = True
    write_record(token, record)
    receipt = 'native network settings applied to ' + device
    if settings['ipv4.method'] == 'manual' and not settings['ipv4.dns']:
        receipt += '; set DNS explicitly for this static connection'
    return {'receipt': receipt, 'undo': token}


def run(action, device, values):
    if action == 'show':
        device_name(device)
        owner(device)
        text, _ = read_config()
        return dict(device=device, profile='dhcpcd:' + device,
                    settings=section(text, device)[3])
    if os.geteuid() != 0:
        raise Refused('native dhcpcd settings require administrator permission')
    uid = int(os.environ.get('SUDO_UID', os.getuid()))
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = STATE.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
        raise Refused('the native network undo directory needs administrator review')
    fd = os.open(STATE / 'lock', os.O_CREAT | os.O_NOFOLLOW | os.O_RDWR, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if action == 'restore':
            if values or not re.fullmatch('[0-9a-f]{64}', device):
                raise Refused('choose a network undo receipt')
            try:
                record = json.loads((STATE / (device + '.json')).read_text())
                if not record['ready'] or record['uid'] != uid:
                    raise ValueError()
            except (OSError, ValueError, KeyError) as exc:
                raise Refused('that native network undo receipt is not available') from exc
            device = device_name(record['device'])
            pid, _ = owner(device)
            before, _ = read_config()
            prefix, old, suffix, _ = section(before, device)
            if digest(before) != record['expected'] or old != record['after']:
                raise Refused('native network settings changed since this receipt; undo leaves them alone')
            new = record['before']
            after = prefix + new + suffix
            settings = section(after, device)[3]
        else:
            device_name(device)
            update = changes(action, values)
            pid, _ = owner(device)
            before, _ = read_config()
            prefix, old, suffix, previous = section(before, device)
            settings = {**previous, **update}
            if settings == previous:
                return {'receipt': 'network settings already match'}
            new = render(old, device, settings)
            # Native default files normally end in a newline. Do not make an
            # unterminated global line part of an interface declaration.
            if not old and prefix and not prefix.endswith('\n'):
                raise Refused('finish the last native config line before editing')
            after = prefix + new + suffix
        return transaction(device, before, after, old, new, settings, pid, uid)


if __name__ == '__main__':
    try:
        if len(sys.argv) < 3:
            raise Refused('network settings need an action and interface')
        print(json.dumps(run(sys.argv[1], sys.argv[2], sys.argv[3:])))
    except (Refused, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
