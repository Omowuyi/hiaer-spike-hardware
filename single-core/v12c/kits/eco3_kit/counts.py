#!/usr/bin/env python3
"""counts.py CSV -- core 2's handshake counters and state flags from an ILA capture of the ECO-3 bitstream (last sample;
4-bit counters wrap at 16), with the reading of where the write was lost."""
import sys, csv
r = list(csv.reader(open(sys.argv[1]))); h = [x.strip() for x in r[0]]; last = r[-1]; first = r[2]
def bit(name, row):
    for i, x in enumerate(h):
        if x == name or x.startswith(name + "[") or x.split("[")[0] == name: return int(row[i].strip(), 16) & 1
    return None
def cnt(e, row):
    b = [bit("eco3_%s_q%d_n" % (e, k), row) for k in range(4)]
    return None if None in b else sum(v << k for k, v in enumerate(b))
c = {e: cnt(e, last) for e in ("s_aw", "s_w", "s_b", "m_aw", "m_w", "m_b")}
f = {n: bit("eco3_%s_f_n" % n, last) for n in ("addr", "data")}
print("handshakes completed (mod 16): HBM-processor side  aw %s  w %s  b %s   |   HBM side  aw %s  w %s  b %s" %
      (c["s_aw"], c["s_w"], c["s_b"], c["m_aw"], c["m_w"], c["m_b"]))
print("HBM processor ever in WRITE_HBM_ADDR: %s   ever in WRITE_HBM_DATA: %s" % (f["addr"], f["data"]))
print("counters changing during the capture: %s" % ("none" if all(cnt(e, first) == c[e] for e in c) else "YES (activity during capture)"))
if None in c.values() or None in f.values(): print("some counters/flags are missing from the capture"); sys.exit(0)
d = lambda a, b: (a - b) % 16
if c["s_aw"] == 0 and c["s_w"] == 0 and not f["addr"]:
    print("READING: no write handshake ever on the HBM-processor side and the state never passed WRITE_HBM_ADDR, yet it waits in WRITE_HBM_RESP: the HBM processor's state machine jumped (HBM processor fault)")
elif d(c["s_aw"], c["m_aw"]) or d(c["s_w"], c["m_w"]):
    print("READING: the slice accepted %d write address(es) / %d data beat(s) more than it passed to the HBM: core 2's register slice lost the write" % (d(c["s_aw"], c["m_aw"]), d(c["s_w"], c["m_w"])))
elif d(c["m_aw"], c["m_b"]):
    print("READING: the HBM accepted %d write(s) more than it answered: core 2's HBM port never returned the write response" % d(c["m_aw"], c["m_b"]))
elif d(c["m_b"], c["s_b"]):
    print("READING: the HBM returned %d response(s) the slice never passed back: core 2's register slice lost the write response" % d(c["m_b"], c["s_b"]))
else:
    print("READING: every write was answered on both sides; the HBM processor received the response and still waits: HBM processor fault")
