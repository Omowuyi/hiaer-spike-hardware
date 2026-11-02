#!/usr/bin/env python3
"""heavy_check.py STEPS PREFIX... -- the same recording replayed at several host read speeds must give the same result:
every step completed, no timeouts, identical spikes at every step and identical membrane replies."""
import sys
steps_expected = int(sys.argv[1]); runs = {}
for pre in sys.argv[2:]:
    try: log = open(pre + "_log.txt").read()
    except FileNotFoundError: print("FAIL %s: no simulation output" % pre); sys.exit(1)
    steps, cur, mps = [], [], []
    for l in open(pre + "_tx.txt"):
        b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
        if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
            for k in range(14):
                s = (v >> (32 + 32 * k)) & 0xFFFFFFFF
                if (s >> 23) & 1: cur.append(s & 0x7FFFF)
            if (b[63], b[62]) == (0xAB, 0xCD): steps.append(sorted(cur)); cur = []
        elif (b[63], b[62]) == (0xCC, 0xCC):
            mps.append(v & 0xFFFFFFFF)
    runs[pre] = (steps, mps, log.count("TIMEOUT"))
names = list(runs); ref = runs[names[0]]; bad = []
for n in names:
    st, mp, to = runs[n]
    dup = sum(len(s) - len(set(s)) for s in st)
    print("   %-40s steps %d, spikes %d (per step %d-%d), duplicates %d, membrane replies %d, timeouts %d" % (
        n.split("/")[-1], len(st), sum(len(s) for s in st), min(map(len, st)) if st else 0, max(map(len, st)) if st else 0, dup, len(mp), to))
    if len(st) != steps_expected: bad.append("%s: %d steps completed, expected %d" % (n, len(st), steps_expected))
    if to: bad.append("%s: %d timeouts" % (n, to))
    if dup: bad.append("%s: %d spikes reported twice in a step" % (n, dup))
    if st != ref[0]:
        d = next((i for i in range(min(len(st), len(ref[0]))) if st[i] != ref[0][i]), None)
        bad.append("%s: spikes differ from %s (first at step %s)" % (n, names[0].split("/")[-1], d))
    if mp != ref[1]: bad.append("%s: membrane replies differ from %s" % (n, names[0].split("/")[-1]))
heavy = sum(len(s) for s in ref[0]) // max(len(ref[0]), 1)
print("%s heavy-spike exp-PSC: %d runs, ~%d spikes per step; %d problems" % ("PASS" if not bad else "FAIL", len(names), heavy, len(bad)))
for x in bad: print("   " + x)
sys.exit(0 if not bad else 1)
