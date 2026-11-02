#!/usr/bin/env python3
"""pos_check.py NOC16_PREFIX POSITION OUT_PREFIX -- from a tb_noc16 run: core POSITION's packets as a single-core log
(OUT_PREFIX_tx.txt, "time hex"), and the R1/R2 checks: every spike word tagged POSITION, every step-done / latency /
HBM-access header tagged 0xC0 + POSITION, no packet from any other core.  Prints one line; exit 0 if all hold."""
import sys
pre, p, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
mine = other = bad_spike = bad_hdr = spikes = hdrs = 0
with open(out + "_tx.txt", "w") as o:
    for l in open(pre + "_tx.txt"):
        t, c, h = l.split(); c = int(c)
        if c != p: other += 1; continue
        mine += 1; o.write("%s %s\n" % (t, h)); b = bytes.fromhex(h); v = int.from_bytes(b, "little")
        if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
            for k in range(14):
                w = (v >> (32 + 32 * k)) & 0xFFFFFFFF
                if (w >> 23) & 1:
                    spikes += 1; bad_spike += ((w >> 19) & 0xF) != (p & 0xF)
        if (b[63], b[62]) in ((0xAB, 0xCD), (0xBA, 0xBA), (0xCA, 0xBA)):
            hdrs += 1; bad_hdr += not (b[61] == 0xC0 and b[60] == p)
ok = mine > 0 and other == 0 and bad_spike == 0 and bad_hdr == 0
print("%-4s position %2d: %d packets (%d from other cores); %d spike words, %d mis-tagged; %d step/count headers, %d mis-tagged"
      % ("OK" if ok else "BAD", p, mine, other, spikes, bad_spike, hdrs, bad_hdr))
sys.exit(0 if ok else 1)
