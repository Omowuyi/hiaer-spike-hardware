#!/usr/bin/env python3
"""cmp_content.py A B LABEL -- two replays carry the same content: spikes at every step and every membrane read, in order
(timing fields and the status reply's feature word are not content)."""
import sys
def content(p):
    steps, cur, mp, face = [], [], [], 0
    for l in open(p + "_tx.txt"):
        b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
        if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
            cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
            if (b[63], b[62]) == (0xAB, 0xCD): steps.append(sorted(cur)); cur = []
        elif (b[63], b[62]) == (0xCC, 0xCC): mp.append(v & 0xFFFFFFFF)
        elif b[63] == 0xFA and b[62] == 0xCE: face += 1
    return steps, mp, face
(sa, ma, fa), (sb, mb, fb) = content(sys.argv[1]), content(sys.argv[2])
d = [s for s in range(max(len(sa), len(sb))) if (sa[s] if s < len(sa) else None) != (sb[s] if s < len(sb) else None)]
ok = not d and ma == mb and fa == fb
why = [] if ok else (["spikes differ first at step %d" % d[0]] if d else []) + (["membrane reads differ (%d vs %d)" % (len(ma), len(mb))] if ma != mb else []) + (["status replies %d vs %d" % (fa, fb)] if fa != fb else [])
print("%-10s %-20s %d steps, %d membrane reads, %d status replies%s" % ("SAME" if ok else "DIFFERENT", sys.argv[3], len(sa), len(ma), fa, "" if ok else ": " + "; ".join(why)))
sys.exit(0 if ok else 1)
