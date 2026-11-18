#!/usr/bin/env python3
import os, struct, zlib, sys

password = sys.argv[1].encode()
first = open(sys.argv[2], 'rb').read()
second = open(sys.argv[3], 'rb').read()
out = sys.argv[4]

CRC_TABLE = []
for n in range(256):
    c = n
    for _ in range(8):
        c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
    CRC_TABLE.append(c)

def crc32_update(crc, b):
    return CRC_TABLE[(crc ^ b) & 0xFF] ^ (crc >> 8)

def init_keys(password):
    keys = [0x12345678, 0x23456789, 0x34567890]
    for ch in password:
        keys[0] = crc32_update(keys[0], ch)
        keys[1] = (keys[1] + (keys[0] & 0xFF)) & 0xFFFFFFFF
        keys[1] = (keys[1] * 134775813 + 1) & 0xFFFFFFFF
        keys[2] = crc32_update(keys[2], (keys[1] >> 24) & 0xFF)
    return keys

def decode_byte(keys):
    temp = (keys[2] | 2) & 0xFFFF
    return ((temp * (temp ^ 1)) >> 8) & 0xFF

def update_keys(keys, c):
    keys[0] = crc32_update(keys[0], c)
    keys[1] = (keys[1] + (keys[0] & 0xFF)) & 0xFFFFFFFF
    keys[1] = (keys[1] * 134775813 + 1) & 0xFFFFFFFF
    keys[2] = crc32_update(keys[2], (keys[1] >> 24) & 0xFF)

def encrypt(password, payload):
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    v1 = (crc >> 16) & 0xFF
    v2 = (crc >> 24) & 0xFF
    keys = init_keys(password)
    hdr = bytearray(os.urandom(10)) + bytes([v1, v2])
    enc = bytearray()
    for b in hdr:
        t = decode_byte(keys)
        enc.append(b ^ t)
        update_keys(keys, b)
    for b in payload:
        t = decode_byte(keys)
        enc.append(b ^ t)
        update_keys(keys, b)
    return crc, bytes(enc)

body = bytearray()
cd = bytearray()
offset = 0
name = b'dup.txt'
for payload in (first, second):
    crc, enc = encrypt(password, payload)
    lf = bytearray()
    lf += b'PK\x03\x04'
    lf += struct.pack('<H', 20)
    lf += struct.pack('<H', 0x1)
    lf += struct.pack('<H', 0)
    lf += struct.pack('<HH', 0, 0)
    lf += struct.pack('<I', crc)
    lf += struct.pack('<I', len(enc))
    lf += struct.pack('<I', len(payload))
    lf += struct.pack('<HH', len(name), 0)
    lf += name
    lf += enc
    body += lf
    cd += b'PK\x01\x02'
    cd += struct.pack('<HH', 20, 20)
    cd += struct.pack('<H', 0x1)
    cd += struct.pack('<H', 0)
    cd += struct.pack('<HH', 0, 0)
    cd += struct.pack('<I', crc)
    cd += struct.pack('<I', len(enc))
    cd += struct.pack('<I', len(payload))
    cd += struct.pack('<HHHHH', len(name), 0, 0, 0, 0)
    cd += struct.pack('<II', 0, offset)
    cd += name
    offset = len(body)

eocd = bytearray()
eocd += b'PK\x05\x06'
eocd += struct.pack('<HHHH', 0, 0, 2, 2)
eocd += struct.pack('<I', len(cd))
eocd += struct.pack('<I', len(body))
eocd += struct.pack('<H', 0)
open(out, 'wb').write(bytes(body + cd + eocd))
