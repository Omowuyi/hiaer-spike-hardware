#!/usr/bin/env python3
"""cmp_streams.py PREFIX_A PREFIX_B LABEL -- 'nothing affected': two replays of the same recording must produce the same
response packets in the same order (timestamps ignored).  CMD 10 replies (FACE FACE) carry the feature word, which
fix 20 changes, so they are counted, not compared."""
import sys
def load(pre):
    pk, face = [], 0
    for l in open(pre + "_tx.txt"):
        h = l.split()[1]; b = bytes.fromhex(h)
        if b[63] == 0xFA and b[62] == 0xCE and b[61] == 0xFA and b[60] == 0xCE: face += 1; continue
        pk.append(h)
    return pk, face
a, fa = load(sys.argv[1]); b, fb = load(sys.argv[2]); lab = sys.argv[3]
if a == b and fa == fb: print("IDENTICAL %-22s %d packets (+%d CMD 10 replies)" % (lab, len(a), fa)); sys.exit(0)
i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
print("DIFFERENT %-22s %d vs %d packets, CMD 10 replies %d vs %d; first difference at packet %d" % (lab, len(a), len(b), fa, fb, i)); sys.exit(1)
