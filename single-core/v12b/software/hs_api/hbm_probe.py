#!/usr/bin/env python3
"""
hbm_probe.py -- measure core 0's HBM write path directly, at the packet level.

Packet layout (verified against command_interpreter.v / hbm_processor.v / fpga_compiler.py):
  byte 63 = opcode, byte 62 = core << 3
  CMD 2  bytes 34..32 = tdata[279:256] = {rw, row[22:0]}  (rw=1 write, 0 read)
         bytes 31..0  = tdata[255:0]   = the 256-bit HBM row (write data)
  CMD 10 status request  -> response {FACE_FACE, error_status, ..., execRun_ctr}: bytes 63,62 = FA CE
  CMD 2 read response    -> {BBBB, 240'd0, row[255:0]}: bytes 63,62 = BB BB, bytes 31..0 = row
  Idle packet (C2H always valid, missed_inputs undeclared): bytes 63..60 = 00 00 00 01, 59..1 = FF, 0 = FE

The HBM TX FSM serves ci2hbm in order: a read queued behind a write is not issued until that
write's bvalid arrives.  So a read-back that returns its row proves the preceding write completed.

Usage: python hbm_probe.py <logfile>
"""
import sys, time
import numpy as np
import hs_bridge.wrapped_dmadump.dmadump as d

T0 = time.time()
LOG = open(sys.argv[1], "w", buffering=1)
def log(s):
    line = "%8.3f %s" % (time.time() - T0, s)
    LOG.write(line + "\n"); LOG.flush(); print(line, flush=True)

CORE = 0
ROW0 = 0x400000           # scratch rows, far from network rows (axon 0.., nrn 16384.., syn 32768..)

def cmd(op, core=CORE):
    b = np.zeros(64, dtype=np.uint64); b[63] = op; b[62] = (core & 0x1F) << 3; return b

def hbm_w(row, data):
    b = cmd(2); a = (1 << 23) | (row & 0x7FFFFF)
    b[34], b[33], b[32] = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    b[0:32] = data; return b

def hbm_r(row):
    b = cmd(2); a = row & 0x7FFFFF
    b[34], b[33], b[32] = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    return b

def pattern(k):
    return np.array([(k * 7 + i * 13 + 1) & 0xFF for i in range(32)], dtype=np.uint64)

def send(*pk):
    arr = np.concatenate(pk).astype(np.uint64)
    return d.dma_dump_write(arr, len(arr), 1, 0, 0, 0, d.DmaMethodNormal)

def rd():
    ec, data = d.dma_dump_read(1, 0, 0, 0, d.DmaMethodNormal, 64)
    return ec, [int(x) & 0xFF for x in list(data)[:64]]

def is_idle(b):
    return b[63:59:-1] == [0, 0, 0, 1] and all(x == 0xFF for x in b[1:60]) and b[0] == 0xFE

def poll(markers, maxreads=4000):
    other = {}
    for n in range(1, maxreads + 1):
        ec, b = rd()
        if (b[63], b[62]) in markers:
            return n, b, other
        if not is_idle(b):
            k = "%02X %02X" % (b[63], b[62]); other[k] = other.get(k, 0) + 1
    return None, None, other

def status(tag):
    send(cmd(10))
    n, b, other = poll({(0xFA, 0xCE)})
    if n:
        es = b[56] | b[57] << 8 | b[58] << 16 | b[59] << 24
        log("STATUS %-10s FACE after %d reads, bytes59..56=%08X execRun_ctr=%d other=%s"
            % (tag, n, es, b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24, other))
    else:
        log("STATUS %-10s NO RESPONSE in 4000 reads (CI RX/TX not serving), other=%s" % (tag, other))
    return bool(n)

def readback(row, exp, tag):
    send(hbm_r(row))
    n, b, other = poll({(0xBB, 0xBB)})
    if not n:
        log("READBACK %-12s row=%d NO 0xBBBB in 4000 reads -> preceding write never completed (other=%s)" % (tag, row, other))
        return False
    got = b[0:32]; ok = got == [int(x) for x in exp]
    log("READBACK %-12s row=%d after %d reads data %s%s" % (tag, row, n, "MATCH" if ok else "MISMATCH",
        "" if ok else "  got=%s exp=%s" % (" ".join("%02X" % x for x in got), " ".join("%02X" % int(x) for x in exp))))
    return True

# 0. drain anything already queued
other = {}
for _ in range(200):
    ec, b = rd()
    if not is_idle(b):
        k = "%02X %02X" % (b[63], b[62]); other[k] = other.get(k, 0) + 1
log("DRAIN before start: non-idle packets=%s" % other)

# 1. CI alive?
status("start")

# 2. one write + read-back
send(hbm_w(ROW0, pattern(0)))
first_ok = readback(ROW0, pattern(0), "single")

# 3. 120 write/read-back pairs, stop at first failure
fail_at = None
if first_ok:
    for k in range(1, 121):
        send(hbm_w(ROW0 + k, pattern(k)))
        if not readback(ROW0 + k, pattern(k), "pair#%d" % k):
            fail_at = k; break
    log("PAIRS: %s" % ("all 120 completed" if fail_at is None else "first failure at pair #%d" % fail_at))

# 4. burst of 102 writes, 10 per DMA call like the compiler, then read back the last row
if first_ok and fail_at is None:
    base = ROW0 + 200
    pk = [hbm_w(base + k, pattern(1000 + k)) for k in range(102)]
    for i in range(0, 102, 10):
        send(*pk[i:i + 10])
    log("BURST: 102 writes sent")
    readback(base + 101, pattern(1000 + 101), "burst-last")
    readback(base + 0, pattern(1000 + 0), "burst-first")

# 5. CI still alive?
status("end")
log("DONE")
