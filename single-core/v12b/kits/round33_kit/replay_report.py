#!/usr/bin/env python3
"""replay_report.py PREFIX [LABEL] -- what a replay produced, per step: spikes (addresses when few), and the membrane
reads that followed that step (count and values).  Plus steps completed and testbench timeouts."""
import sys, collections
pre = sys.argv[1]; lab = sys.argv[2] if len(sys.argv) > 2 else pre
steps, cur, mps, mp_after = [], [], [], collections.OrderedDict()
for l in open(pre + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
        cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
        if (b[63], b[62]) == (0xAB, 0xCD): steps.append(cur); cur = []
    elif (b[63], b[62]) == (0xCC, 0xCC):
        m = v & 0xFFFFFFFF; m = m - (1 << 32) if m >= 1 << 31 else m
        mp_after.setdefault(len(steps) - 1, []).append(m)
try: to = open(pre + "_log.txt").read().count("TIMEOUT")
except FileNotFoundError: to = "no log"
print("== %s: %d steps completed, testbench timeouts %s" % (lab, len(steps), to))
for s, sp in enumerate(steps):
    if sp or s in mp_after:
        c = collections.Counter(sp); dup = sum(v - 1 for v in c.values() if v > 1)
        line = "   step %2d: %d spikes%s" % (s, len(sp), (" " + str(sorted(c)[:16]) + (" ..." if len(c) > 16 else "")) if sp else "")
        if dup: line += " (%d duplicates)" % dup
        if s in mp_after:
            vals = mp_after[s]; h = collections.Counter(vals)
            line += " | after: %d membrane reads, values %s" % (len(vals), dict(sorted(h.items())[:6]) if len(h) <= 6 else "%d distinct, first %s" % (len(h), vals[:6]))
        print(line)
