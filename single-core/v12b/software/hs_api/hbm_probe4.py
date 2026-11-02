# hbm_probe4.py -- does every HBM write put a packet in the core's output stream?
# Rounds of 50 writes (10 per DMA call), one read after each round, then drain and
# count ALL responses.  ~51 per round = writes generate responses; ~1 = they don't;
# 0 = the core has stopped.  1,200 writes total, below the input buffering, so the
# card cannot wedge.
import sys
import numpy as np
import hs_bridge.wrapped_dmadump.dmadump as d

CORE = int(sys.argv[1]) if len(sys.argv) > 1 else 1
ROUNDS, PER = 24, 50
BASE = 0x400200

def cmd(op, core):
    b = np.zeros(64, dtype=np.uint64); b[63] = op; b[62] = (core & 0x1F) << 3; return b
def wr(core, row, k):
    b = cmd(2, core); a = (1 << 23) | row
    b[34], b[33], b[32] = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    b[0:32] = [(k * 11 + i * 5 + 1) & 0xFF for i in range(32)]; return b
def rdcmd(core, row):
    b = cmd(2, core); b[34], b[33], b[32] = (row >> 16) & 0xFF, (row >> 8) & 0xFF, row & 0xFF; return b
def send(*pk):
    arr = np.concatenate(pk).astype(np.uint64)
    d.dma_dump_write(arr, len(arr), 1, 0, 0, 0, d.DmaMethodNormal)
def rd():
    ec, data = d.dma_dump_read(1, 0, 0, 0, d.DmaMethodNormal, 64)
    return [int(x) & 0xFF for x in list(data)[:64]]
def collect(maxreads=6000, settle=300):
    n, other, quiet = 0, {}, 0
    for i in range(maxreads):
        b = rd()
        if b[63] == 0xBB and b[62] == 0xBB:
            n += 1; quiet = 0
        else:
            k = "%02X %02X" % (b[63], b[62])
            if k not in ("FF FF", "00 00"):
                other[k] = other.get(k, 0) + 1
            quiet += 1
            if quiet >= settle and (n or i >= 2000):
                break
    return n, other

print("core %d: leftover responses before start: %d" % (CORE, collect(maxreads=800, settle=300)[0]), flush=True)
print("%-6s %-14s %-22s %s" % ("round", "writes so far", "responses this round", "other packets"), flush=True)
total = 0
for r in range(ROUNDS):
    pk = [wr(CORE, BASE + r * PER + i, r * PER + i) for i in range(PER)]
    for i in range(0, PER, 10):
        send(*pk[i:i + 10])
    send(rdcmd(CORE, BASE + r * PER + PER - 1))
    n, other = collect()
    total += n
    print("%-6d %-14d %-22d %s" % (r, (r + 1) * PER, n, other if other else ""), flush=True)
    if n == 0:
        print("no response at all after %d writes: the core stopped" % ((r + 1) * PER), flush=True)
        break
print("TOTAL responses %d for %d writes + %d reads" % (total, (r + 1) * PER, r + 1), flush=True)
