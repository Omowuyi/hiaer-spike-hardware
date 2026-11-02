#!/usr/bin/env python3
"""ld_check.py PREFIX LABEL -- 64-bit long-delay test (A0-A15 -> N1.0-N1.15, delay 40): exactly neurons 0-15 spike, all
at step 41, and nothing else in the run."""
import sys
out, cur = [], []
for l in open(sys.argv[1] + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
        cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
        if (b[63], b[62]) == (0xAB, 0xCD): out.append(sorted(cur)); cur = []
nz = {s: sp for s, sp in enumerate(out) if sp}
ok = len(out) >= 42 and list(nz) == [41] and nz[41] == list(range(16))
print("%s long delay, %s: %d steps; spikes %s" % ("PASS" if ok else "FAIL", sys.argv[2], len(out), "; ".join("step %d: %s" % (s, sp) for s, sp in nz.items()) or "none"))
sys.exit(0 if ok else 1)
