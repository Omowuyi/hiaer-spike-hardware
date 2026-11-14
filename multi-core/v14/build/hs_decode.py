#!/usr/bin/env python3
"""hs_decode.py CSV -- v13 per-core HBM handshake probes (u_ila_hs): for each core, completed AW / W / B handshakes on the
HBM-processor side (s) and the HBM side (m) of its register slice (4-bit counters, mod 16), last sample.  A core is
flagged when its two sides disagree (a write accepted and not passed on, or a response lost) or when it has written
(AW) and is still waiting for responses.  Reads named columns hs_c<k>_<e>_q<b>_n, or one 384-bit column in build order."""
import sys, csv, re
EV = ["s_aw", "s_w", "s_b", "m_aw", "m_w", "m_b"]
r = list(csv.reader(open(sys.argv[1]))); h = [x.strip() for x in r[0]]; last = r[-1]
cnt = {(k, e): 0 for k in range(16) for e in EV}; found = 0
for i, name in enumerate(h):
    m = re.search(r"hs_c(\d+)_(s_aw|s_w|s_b|m_aw|m_w|m_b)_q(\d)_n", name)
    if m:
        k, e, b = int(m.group(1)), m.group(2), int(m.group(3))
        cnt[(k, e)] |= (int(last[i].strip(), 16) & 1) << b; found += 1
if found == 0:
    wide = [i for i, name in enumerate(h) if "probe0" in name or "u_ila_hs" in name]
    if not wide: sys.exit("no probe columns found")
    v = int(last[wide[0]].strip(), 16)
    for k in range(16):
        for j, e in enumerate(EV):
            cnt[(k, e)] = (v >> (4 * (6 * k + j))) & 0xF
print("core   s.aw s.w s.b | m.aw m.w m.b   reading")
bad = 0
for k in range(16):
    c = [cnt[(k, e)] for e in EV]; d = lambda a, b: (a - b) % 16
    if d(c[0], c[3]) or d(c[1], c[4]): note = "SLICE HOLDS A WRITE (s side ahead of m side)"; bad += 1
    elif d(c[3], c[5]): note = "HBM OWES %d RESPONSE(S)" % d(c[3], c[5]); bad += 1
    elif d(c[5], c[2]): note = "SLICE HOLDS A RESPONSE"; bad += 1
    else: note = "consistent" + ("" if any(c) else " (idle)")
    print("%4d   %4d %3d %3d | %4d %3d %3d   %s" % (k, *c, note))
print("ALL CORES CONSISTENT" if not bad else "%d CORE(S) FLAGGED" % bad)
