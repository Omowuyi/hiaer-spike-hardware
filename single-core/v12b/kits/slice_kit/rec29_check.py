#!/usr/bin/env python3
"""rec29_check.py PREFIX fanin|overflow -- the two round-29 recordings replayed on the v12 design.
  fanin:    N1.0's membrane after step 0 is exactly 9000
  overflow: N1.0's membrane is 0 after steps 0-4 and exactly 1023 after step 5 (a full delay slot)
The status reply is checked separately with face_status27.py."""
import sys
steps, mp = 0, {}
for l in open(sys.argv[1] + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) == (0xAB, 0xCD): steps += 1
    elif (b[63], b[62]) == (0xCC, 0xCC):
        m = v & 0xFFFFFFFF; mp.setdefault(steps - 1, []).append(m - (1 << 32) if m >= 1 << 31 else m)
first = {s: v[0] for s, v in mp.items() if v}
if sys.argv[2] == "fanin":
    ok = first.get(0) == 9000
    print("%s fan-in 9000: %d steps; N1.0 after step 0: %s" % ("PASS" if ok else "FAIL", steps, first.get(0)))
else:
    seq = [first.get(s) for s in range(6)]
    ok = seq[:5] == [0] * 5 and seq[5] == 1023
    print("%s delay overflow: %d steps; N1.0 after steps 0-5: %s (expected 0 x5, then 1023)" % ("PASS" if ok else "FAIL", steps, seq))
sys.exit(0 if ok else 1)
