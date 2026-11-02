# hbm_probe3.py -- per core: can one HBM read complete, and can one HBM write complete?
# A read queued behind a write is only issued after the write's bvalid, so a read
# response after "write + read" proves the write completed.  Every step is drained
# completely before the next, so no response is ever attributed to the wrong step.
import sys
import numpy as np
import hs_bridge.wrapped_dmadump.dmadump as d

def cmd(op, core):
    b = np.zeros(64, dtype=np.uint64); b[63] = op; b[62] = (core & 0x1F) << 3; return b
def wr(core, row, pat):
    b = cmd(2, core); a = (1 << 23) | row
    b[34], b[33], b[32] = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF; b[0:32] = pat; return b
def rdcmd(core, row):
    b = cmd(2, core); b[34], b[33], b[32] = (row >> 16) & 0xFF, (row >> 8) & 0xFF, row & 0xFF; return b
def send(b):
    d.dma_dump_write(b, 64, 1, 0, 0, 0, d.DmaMethodNormal)
def rd():
    ec, data = d.dma_dump_read(1, 0, 0, 0, d.DmaMethodNormal, 64)
    return [int(x) & 0xFF for x in list(data)[:64]]
def collect(maxreads=3000, settle=300):
    got, quiet = [], 0
    for _ in range(maxreads):
        b = rd()
        if b[63] == 0xBB and b[62] == 0xBB:
            got.append(b); quiet = 0
        else:
            quiet += 1
            if quiet >= settle and (got or _ >= 1500):
                break
    return got

spec = sys.argv[1] if len(sys.argv) > 1 else "0-15"
cores = []
for p in spec.split(","):
    if "-" in p:
        a, b = p.split("-"); cores += list(range(int(a), int(b) + 1))
    else:
        cores.append(int(p))
left = collect(maxreads=600, settle=200)
print("leftover read responses before start: %d" % len(left), flush=True)
print("%-5s %-26s %-40s" % ("core", "read-only", "write then read"), flush=True)
rd_ok, wr_ok = [], []
for c in cores:
    send(rdcmd(c, 0x400000 + c)); r1 = collect()
    pat = [(c * 17 + i * 7 + 3) & 0xFF for i in range(32)]
    send(wr(c, 0x400100 + c, np.array(pat, dtype=np.uint64))); send(rdcmd(c, 0x400100 + c)); r2 = collect()
    match = any(b[0:32] == pat for b in r2)
    s1 = ("served (%d responses)" % len(r1)) if r1 else "NO RESPONSE"
    s2 = ("WRITE COMPLETED (%d responses, data %s)" % (len(r2), "matches" if match else "differs")) if r2 else ("WRITE NEVER COMPLETED" if r1 else "unknown (reads dead)")
    print("%-5d %-26s %-40s" % (c, s1, s2), flush=True)
    if r1: rd_ok.append(c)
    if r2: wr_ok.append(c)
print("SUMMARY reads complete on cores : %s" % rd_ok, flush=True)
print("SUMMARY writes complete on cores: %s" % wr_ok, flush=True)
