#!/usr/bin/env python3
"""fo_check.py PREFIX N -- max_axonal_fanout[N] (A0 -> N1.0..N1.N-1 -> N2.0, threshold 0, only N2.0 an output): step 0 no
spikes; step 1 no reported spikes (N1 are not outputs) and N2.0's membrane reads N; step 2 exactly N2.0 (address N)."""
import sys
N = int(sys.argv[2]); steps, cur, mp = [], [], {}
for l in open(sys.argv[1] + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
        cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
        if (b[63], b[62]) == (0xAB, 0xCD): steps.append(sorted(cur)); cur = []
    elif (b[63], b[62]) == (0xCC, 0xCC):
        m = v & 0xFFFFFFFF; mp.setdefault(len(steps) - 1, []).append(m - (1 << 32) if m >= 1 << 31 else m)
ok = len(steps) >= 3 and steps[0] == [] and steps[1] == [] and steps[2] == [N] and mp.get(1, []).count(N) == 1
print("%s fan-out %d: steps %d; spikes per step %s; N2.0's membrane after step 1: %s" % ("PASS" if ok else "FAIL", N, len(steps),
      [s if len(s) <= 3 else "%d spikes" % len(s) for s in steps[:3]], "N present" if mp.get(1, []).count(N) == 1 else "missing"))
sys.exit(0 if ok else 1)
