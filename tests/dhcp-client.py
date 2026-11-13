#!/usr/bin/env python3
"""Obtain a real lease from OpenWrt for the isolated static Docker client."""
import fcntl
import json
import os
import socket
import struct
import time

control = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
request = struct.pack('256s', b'eth0')
mac = fcntl.ioctl(control.fileno(), 0x8927, request)[18:24]
try:
    old = fcntl.ioctl(control.fileno(), 0x8915, request)[20:24]
except OSError:
    old = None
xid = os.urandom(4)
header = struct.pack('BBBB', 1, 1, 6, 0) + xid + struct.pack('HH', 0, 0x0080)
header += b'\0' * 16 + mac + b'\0' * 10 + b'\0' * 192 + b'\x63\x82\x53\x63'
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'eth0\0')
sock.bind(('', 68)); sock.settimeout(10)

def receive(kind):
    while True:
        data, _ = sock.recvfrom(4096)
        if len(data) < 240 or data[4:8] != xid:
            continue
        options = {}; offset = 240
        while offset < len(data):
            code = data[offset]; offset += 1
            if code == 255: break
            if code == 0: continue
            length = data[offset]; offset += 1
            options[code] = data[offset:offset + length]; offset += length
        if options.get(53) == bytes([kind]):
            return data, options

sock.sendto(header + b'\x35\x01\x01\x37\x03\x01\x03\x06\xff', ('255.255.255.255', 67))
offer, options = receive(2)
address = offer[16:20]
sock.sendto(header + b'\x35\x01\x03\x32\x04' + address + b'\x36\x04' + options[54] + b'\x37\x03\x01\x03\x06\xff', ('255.255.255.255', 67))
receive(5)
sock.close()

def attr(kind, value):
    length = 4 + len(value)
    return struct.pack('HH', length, kind) + value + b'\0' * (-length % 4)
netlink = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
netlink.bind((0, 0))
index = socket.if_nametoindex('eth0')
def address_message(kind, value):
    payload = struct.pack('BBBBI', socket.AF_INET, 24, 0, 0, index)
    payload += attr(1, value) + attr(2, value)
    netlink.send(struct.pack('IHHII', 16 + len(payload), kind, 1 | 4 | (0x400 if kind == 20 else 0), 5, 0) + payload)
    reply = netlink.recv(4096)
    error = struct.unpack('i', reply[16:20])[0]
    if error not in [0, -17]:
        raise OSError(-error, 'DHCP address configuration failed')
if old != address:
    if old is not None:
        address_message(21, old)
    address_message(20, address)
with open('/etc/resolv.conf', 'w') as file:
    file.write('nameserver 172.30.77.1\n')
print(json.dumps({'dhcp_address': socket.inet_ntoa(address), 'dns': '172.30.77.1'}))
