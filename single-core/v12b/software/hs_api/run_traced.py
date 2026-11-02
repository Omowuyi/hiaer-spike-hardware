#!/usr/bin/env python3
"""
run_traced.py v2 -- run a hardware pytest with every host<->FPGA DMA transfer logged.

WRITES: split into 64-byte commands (wordSize=1: element i = tdata[8i+7:8i]) and decoded.
READS:  every returned 64-byte packet summarised (marker bytes 63/62, head and tail
        bytes, exitCode).  First 100 reads logged in full; after that only when the
        packet CHANGES, plus a heartbeat every 5000 reads.  flush_spikes exits only on
        FF FF (empty, x50), CC CC, EE EE (spikes) or CD AB (exec done) -- anything
        else makes it loop, so the marker column is what matters.
Usage:  python run_traced.py <logfile> <pytest args...>
"""
import sys, time, os

LOG = sys.argv[1]
PYARGS = sys.argv[2:]
_f = open(LOG, "w", buffering=1)
_t0 = time.time()
_seq = [0]
_rd = {"n": 0, "last": None, "same": 0}

def log(s, sync=False):
    _f.write("%9.3f %s\n" % (time.time() - _t0, s))
    _f.flush()
    if sync:
        os.fsync(_f.fileno())

OPS = {0: "AXON_DATA", 1: "EEP_W(input)", 2: "HBM_RW", 3: "IEP_RW", 4: "NTWK_PARAM",
       6: "EXEC_STEP", 7: "EXEC_CONT", 8: "NTWK_PARAM_MEM", 9: "SET_TIMEOUT",
       10: "READ_STATUS", 11: "CLEAR_STATUS", 12: "DMA_HBM_W", 13: "PSC_PARAMS",
       14: "AXON_DELAY", 15: "ROUTE_TBL", 16: "REMOTE_DST", 17: "FPGA_ID"}
MARK = {(0xFF, 0xFF): "EMPTY", (0xCC, 0xCC): "MP", (0xEE, 0xEE): "SPIKES",
        (0xAB, 0xCD): "EXEC_DONE", (0xBA, 0xBA): "LATENCY", (0xCA, 0xBA): "HBM_ACC",
        (0xDE, 0xAD): "ERROR(DEAD)", (0xFA, 0xCE): "STATUS(FACE)", (0xBB, 0xBB): "HBM_READ",
        (0x00, 0x00): "ZERO"}

def decode(cmd):
    b = [int(x) & 0xFF for x in cmd]
    op, core = b[63], b[62] >> 3
    s = "op=%2d %-15s core=%2d" % (op, OPS.get(op, "UNKNOWN"), core)
    if op == 2:
        a = (b[34] << 16) | (b[33] << 8) | b[32]
        nz = sum(1 for x in b[0:32] if x)
        s += " %s row=%d data_nonzero_bytes=%d" % ("WRITE" if a >> 23 else "READ ", a & 0x7FFFFF, nz)
    elif op == 7:
        s += " limit=%d" % (b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24)
    elif op == 0:
        s += " nonzero_bytes=%d" % sum(1 for x in b[0:62] if x)
    return s

def pkt(b):
    m = MARK.get((b[63], b[62]), "OTHER")
    return "[63,62]=%02X %02X %-12s hi=%s lo=%s" % (
        b[63], b[62], m, " ".join("%02X" % x for x in b[63:47:-1]),
        " ".join("%02X" % x for x in b[0:16]))

import hs_bridge.wrapped_dmadump.dmadump as dmadump
_orig_w, _orig_r = dmadump.dma_dump_write, dmadump.dma_dump_read

def traced_write(data, nWriteData, *a, **k):
    n = int(nWriteData)
    log("WRITE call: %d bytes = %d commands%s" % (n, n // 64, "" if n % 64 == 0 else "  ** NOT A MULTIPLE OF 64 **"))
    for i in range(0, n - n % 64, 64):
        _seq[0] += 1
        log("  #%-6d %s" % (_seq[0], decode(data[i:i + 64])))
    r = _orig_w(data, nWriteData, *a, **k)
    log("WRITE returned %s" % (r,), sync=True)
    return r

def traced_read(*a, **k):
    r = _orig_r(*a, **k)
    _rd["n"] += 1
    n = _rd["n"]
    try:
        ec, data = r
        b = [int(x) & 0xFF for x in list(data)[:64]]
        key = tuple(b)
    except Exception as e:
        log("READ  #%d unparsable return: %r (%s)" % (n, type(r), e), sync=True)
        return r
    if n <= 100:
        log("READ  #%-7d ec=%s %s" % (n, ec, pkt(b)), sync=(n == 100))
    elif key != _rd["last"]:
        log("READ  #%-7d ec=%s CHANGED after %d identical: %s" % (n, ec, _rd["same"], pkt(b)), sync=True)
        _rd["same"] = 0
    else:
        _rd["same"] += 1
        if n % 5000 == 0:
            log("READ  #%-7d heartbeat: %d identical so far, current %s" % (n, _rd["same"], pkt(b)), sync=True)
    _rd["last"] = key
    return r

dmadump.dma_dump_write = traced_write
dmadump.dma_dump_read = traced_read

class _Plugin:
    def pytest_runtest_logstart(self, nodeid, location):
        log("===== TEST START %s" % nodeid, sync=True)
    def pytest_runtest_logfinish(self, nodeid, location):
        log("===== TEST END   %s" % nodeid, sync=True)

import pytest
log("pytest %s" % " ".join(PYARGS), sync=True)
rc = pytest.main(PYARGS, plugins=[_Plugin()])
log("pytest exit %s" % rc, sync=True)
sys.exit(rc)
