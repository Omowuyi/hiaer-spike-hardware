#!/usr/bin/env python3
"""face_status.py PREFIX [expect_bit16 expect_bit17] -- decode the last CMD 10 reply: {FACE FACE, error_status,
feature word, ...}; bytes 56-59 = error_status, 52-55 = feature word."""
import sys
last = None
for l in open(sys.argv[1] + "_tx.txt"):
    b = bytes.fromhex(l.split()[1])
    if b[63] == 0xFA and b[62] == 0xCE and b[61] == 0xFA and b[60] == 0xCE: last = b
if last is None: print("FAIL no CMD 10 reply"); sys.exit(1)
fw = int.from_bytes(last[52:56], "little"); es = int.from_bytes(last[56:60], "little")
b16, b17 = (es >> 16) & 1, (es >> 17) & 1
print("CMD 10 reply: feature word 0x%08x, error_status 0x%08x (bit 16 watchdog %d, bit 17 bypass %d)" % (fw, es, b16, b17))
if len(sys.argv) > 3:
    ok = fw == 0xF10A003F and b16 == int(sys.argv[2]) and b17 == int(sys.argv[3])
    print("PASS" if ok else "FAIL (expected feature word 0xf10a003f, bit 16 = %s, bit 17 = %s)" % (sys.argv[2], sys.argv[3])); sys.exit(0 if ok else 1)
