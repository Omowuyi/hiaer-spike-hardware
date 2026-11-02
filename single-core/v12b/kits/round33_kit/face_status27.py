#!/usr/bin/env python3
"""face_status27.py PREFIX [b16 b17 b18 b19] -- the last CMD 10 reply {FACE FACE, error_status, feature word}; bytes 56-59 =
error_status, 52-55 = feature word.  With expectations: feature word 0xF10A00FF (fixes 1-26) and bits 16-19 as given."""
import sys
last = None
for l in open(sys.argv[1] + "_tx.txt"):
    b = bytes.fromhex(l.split()[1])
    if b[63] == 0xFA and b[62] == 0xCE and b[61] == 0xFA and b[60] == 0xCE: last = b
if last is None: print("FAIL no CMD 10 reply"); sys.exit(1)
fw = int.from_bytes(last[52:56], "little"); es = int.from_bytes(last[56:60], "little"); bits = [(es >> k) & 1 for k in (16, 17, 18, 19)]
print("CMD 10 reply: feature word 0x%08x, error_status 0x%08x (bit 16 watchdog %d, 17 bypass %d, 18 delay-slot overflow %d, 19 Phase-2 fallback %d)" % ((fw, es) + tuple(bits)))
if len(sys.argv) > 5:
    want = [int(x) for x in sys.argv[2:6]]; ok = fw == 0xF10A00FF and bits == want
    print("PASS" if ok else "FAIL (expected feature word 0xf10a00ff, bits 16-19 = %s)" % want); sys.exit(0 if ok else 1)
