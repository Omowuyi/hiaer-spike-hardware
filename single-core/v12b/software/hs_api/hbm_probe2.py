#!/usr/bin/env python3
"""
hbm_probe2.py -- per-core HBM port check: read-only access, then write + read-back.

Each core has its own HBM AXI port (hbmAXI(N,N) in the top).  For each core in turn:
  phase A  status request (CMD 10)            -> is that core's command interpreter alive?
  phase B  READ-ONLY of a scratch row         -> does the port answer reads at all?
  phase C  WRITE then READ-BACK of a new row  -> does a write complete (bvalid)?
  phase D  status again
Done one core at a time, so every response is attributable to the core just addressed.
Packet layout identical to hbm_probe.py (verified against the RTL and the VIO capture).

Usage: python hbm_probe2.py <logfile> <cores, e.g. 0-15 or 0,1>
"""
import sys, time
import numpy as np
import hs_bridge.wrapped_dmadump.dmadump as d

T0 = time.time()
LOG = open(sys.argv[1], "w", buffering=1)
def log(s):
    line = "%8.3f %s" % (time.time() - T0, s)
    LOG.write(line + "\n"); LOG.flush(); print(line, flush=True)

spec = sys.argv[2] if len(sys.argv) > 2 else "0-15"
CORES = []
for part in spec.split(","):
    if "-" in part:
        a, b = part.split("-"); CORES += list(range(int(a), int(b) + 1))
    else:
        CORES.append(int(part))
ROW0 = 0x400000

def cmd(op, core):
    b = np.zeros(64, dtype=np.uint64); b[63] = op; b[62] = (core & 0x1F) << 3; return b
def hbm_w(core, row, data):
    b = cmd(2, core); a = (1 << 23) | (row & 0x7FFFFF)
    b[34], b[33], b[32] = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    b[0:32] = data; return b
def hbm_r(core, row):
    b = cmd(2, core); a = row & 0x7FFFFF
    b[34], b[33], b[32] = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    return b
def pattern(k):
    return np.array([(k * 7 + i * 13 + 1) & 0xFF for i in range(32)], dtype=np.uint64)
def send(*pk):
    arr = np.concatenate(pk).astype(np.uint64)
    return d.dma_dump_write(arr, len(arr), 1, 0, 0, 0, d.DmaMethodNormal)
def rd():
    ec, data = d.dma_dump_read(1, 0, 0, 0, d.DmaMethodNormal, 64)
    return [int(x) & 0xFF for x in list(data)[:64]]
def is_idle(b):
    v7idle = b[63:59:-1] == [0, 0, 0, 1] and all(x == 0xFF for x in b[1:60]) and b[0] == 0xFE
    ffidle = b[63] == 0xFF and b[62] == 0xFF
    return v7idle or ffidle
def poll(markers, maxreads=2000):
    other = {}
    for n in range(1, maxreads + 1):
        b = rd()
        if (b[63], b[62]) in markers:
            return n, b, other
        if not is_idle(b):
            k = "%02X %02X" % (b[63], b[62]); other[k] = other.get(k, 0) + 1
    return None, None, other

def status(c):
    send(cmd(10, c)); n, b, o = poll({(0xFA, 0xCE)})
    return ("ok(%d)" % n) if n else "NONE", o
def read_only(c):
    send(hbm_r(c, ROW0 + c)); n, b, o = poll({(0xBB, 0xBB)})
    return ("ok(%d)" % n) if n else "NONE", o
def write_rb(c):
    row = ROW0 + 0x100 + c; p = pattern(c)
    send(hbm_w(c, row, p)); send(hbm_r(c, row)); n, b, o = poll({(0xBB, 0xBB)})
    if not n:
        return "NONE", o
    return ("ok(%d)%s" % (n, "" if b[0:32] == [int(x) for x in p] else " data-differs")), o

drained = {}
for _ in range(200):
    b = rd()
    if not is_idle(b):
        k = "%02X %02X" % (b[63], b[62]); drained[k] = drained.get(k, 0) + 1
log("cores %s ; drained non-idle before start: %s" % (CORES, drained))
log("%-5s %-10s %-12s %-22s %-10s %s" % ("core", "statusA", "read-only", "write+readback", "statusD", "unexpected packets"))
summary = {}
for c in CORES:
    sA, oA = status(c)
    ro, oB = read_only(c)
    wr, oC = write_rb(c)
    sD, oD = status(c)
    other = {}
    for o in (oA, oB, oC, oD):
        for k, v in o.items(): other[k] = other.get(k, 0) + v
    summary[c] = (sA, ro, wr, sD)
    log("%-5d %-10s %-12s %-22s %-10s %s" % (c, sA, ro, wr, sD, other if other else ""))
log("SUMMARY read-only ok on cores: %s" % [c for c in CORES if summary[c][1].startswith("ok")])
log("SUMMARY write     ok on cores: %s" % [c for c in CORES if summary[c][2].startswith("ok")])
log("DONE")
