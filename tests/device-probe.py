#!/usr/bin/env python3
"""Run in each isolated Docker LAN client; route only via the OpenWrt guest."""
import json
import socket
import struct
import sys
import urllib.request

def route():
    def attr(kind, data):
        length = len(data) + 4
        return struct.pack('HH', length, kind) + data + b'\0' * (-length % 4)
    payload = struct.pack('BBBBBBBBI', socket.AF_INET, 0, 0, 0, 254, 3, 0, 1, 0)
    payload += attr(5, socket.inet_aton('172.30.77.1'))
    payload += attr(4, struct.pack('I', socket.if_nametoindex('eth0')))
    message = struct.pack('IHHII', 16 + len(payload), 24, 1 | 4 | 0x100 | 0x400, 1, 0) + payload
    sock = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
    sock.bind((0, 0)); sock.send(message)
    reply = sock.recv(4096)
    error = struct.unpack('i', reply[16:20])[0]
    if error:
        raise OSError(-error, 'Cannot set lab route')
    # Images can be switched between release tests; discard the previous guest MAC.
    payload = struct.pack('BBHiHBB', socket.AF_INET, 0, 0, socket.if_nametoindex('eth0'), 0, 0, 0)
    payload += attr(1, socket.inet_aton('172.30.77.1'))
    sock.send(struct.pack('IHHII', 16 + len(payload), 29, 1 | 4, 2, 0) + payload)
    sock.recv(4096)

route()
if len(sys.argv) > 1 and sys.argv[1] == 'route':
    print('LAN gateway configured'); sys.exit(0)
result = {}
try:
    response = urllib.request.urlopen('http://198.18.77.1:18000/probe', timeout=6)
    result['tcp'] = response.status == 200 and response.read() == b'overwall-lab-origin'
except Exception:
    result['tcp'] = False
try:
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); udp.settimeout(6)
    udp.sendto(b'overwall-udp-probe', ('198.18.77.1', 18001))
    result['udp'] = udp.recv(100) == b'overwall-udp-probe'
except Exception:
    result['udp'] = False
print(json.dumps(result))
