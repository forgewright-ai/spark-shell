#!/usr/bin/env python3
"""A fixed test lease, confined by dhcpcd_proof.sh to its private network."""
import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'server0\0')
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.bind(('', 67))
while True:
    data, _ = sock.recvfrom(4096)
    if len(data) < 240 or data[0] != 1:
        continue
    opts, i = {}, 240
    while i < len(data):
        code = data[i]
        i += 1
        if code == 255:
            break
        if code == 0:
            continue
        n = data[i]
        opts[code] = data[i + 1:i + 1 + n]
        i += n + 1
    kind = opts.get(53)
    if kind not in (b'\x01', b'\x03'):
        continue
    reply = bytearray(240)
    reply[:4] = b'\x02\x01\x06\x00'
    reply[4:8] = data[4:8]
    reply[10:12] = b'\x80\x00'
    reply[16:20] = socket.inet_aton('192.0.2.20')
    reply[20:24] = socket.inet_aton('192.0.2.1')
    reply[28:44] = data[28:44]
    reply[236:] = b'\x63\x82\x53\x63'
    def option(code, value):
        reply.extend(bytes((code, len(value))) + value)
    option(53, b'\x02' if kind == b'\x01' else b'\x05')
    option(54, socket.inet_aton('192.0.2.1'))
    option(51, struct.pack('!I', 3600))
    option(1, socket.inet_aton('255.255.255.0'))
    option(3, socket.inet_aton('192.0.2.1'))
    option(6, socket.inet_aton('192.0.2.53'))
    reply.append(255)
    sock.sendto(reply, ('255.255.255.255', 68))
