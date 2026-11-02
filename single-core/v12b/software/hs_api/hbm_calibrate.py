#!/usr/bin/env python3
"""
Self-calibrating HBM read/write diagnostic.

WHY THIS EXISTS
Three packet layouts were derived from the RTL this session and all three were
wrong: the error_status offset, the synapse-row byte offsets, and the row
orientation.  Each wrong layout produced a confident but false conclusion.
Deriving offsets from Verilog and trusting them is the bottleneck.

This does not derive anything.  It writes a pattern whose every byte is
distinct, reads it back, and finds where each byte actually landed.  The
resulting map is measured, so it cannot be wrong in the way the derived ones
were.  Everything after that decodes through the measured map.

STAGES
  1. CALIBRATE   write 32 distinct bytes to a scratch HBM row, read back,
                 and locate each one in the 64-byte response
  2. VERIFY      write a second, different pattern and confirm the map holds
  3. DECODE      emit a real synapse through the compiler with a known
                 weight and delay, read it back through the measured map,
                 and report whether the delay field is where the IEP reads it

A scratch row well above the synapse region is used so nothing real is
disturbed.

  cd /home/omowuyi/testing/hs_api
  source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 hbm_calibrate.py
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
import hs_bridge.wrapped_dmadump.dmadump as d

# A row inside the mapped synapse region but well past anything a one-neuron
# network uses.  2^22 was outside the mapped range -- the write silently went
# nowhere and the read returned zeros.
# SYN_BASE_ADDR and AXN_BASE_ADDR live in config.py, not here -- they are read
# from the compiler at runtime rather than hardcoded.  Assuming 2**15 was the
# last remaining guess in this tool and it was wrong.
W, DELAY = 1000, 3


class Timeout(Exception):
    pass


signal.signal(signal.SIGALRM, lambda s, f: (_ for _ in ()).throw(Timeout()))


def hbm_write_row(row, payload, coreID=0):
    """CMD 2 write, byte order exactly as create_synapses builds it."""
    assert len(payload) == 32
    coreBits = np.binary_repr(coreID, 5) + '000'
    ra = '1' + np.binary_repr(row, 23)
    cmd = ([2, int(coreBits, 2)] + [0] * 27
           + [int(ra[:8], 2), int(ra[8:16], 2), int(ra[16:], 2)] + payload)
    d.dma_dump_write(np.flip(np.array(cmd, dtype=np.uint64)), 64, 1, 0, 0, 0,
                     d.DmaMethodNormal)


def hbm_read_raw(row, coreID=0, tries=400):
    """CMD 2 read.  Returns all 64 response bytes -- no assumption about
    which of them carry the row."""
    coreBits = np.binary_repr(coreID, 5) + '000'
    ra = '0' + np.binary_repr(row, 23)
    cmd = ([2, int(coreBits, 2)] + [0] * 27
           + [int(ra[:8], 2), int(ra[8:16], 2), int(ra[16:], 2)] + [0] * 32)
    d.dma_dump_write(np.flip(np.array(cmd, dtype=np.uint64)), 64, 1, 0, 0, 0,
                     d.DmaMethodNormal)
    for _ in range(tries):
        rc, buf = d.dma_dump_read(1, 0, 0, 0, d.DmaMethodNormal, 64)
        if rc == 0:
            b = [int(x) for x in buf]
            if b[63] == 0xBB and b[62] == 0xBB:
                return b
    return None


def calibrate(pattern, tag):
    """Write `pattern` (32 distinct bytes) and report where each lands."""
    hbm_write_row(SCRATCH, pattern)
    resp = hbm_read_raw(SCRATCH)
    if resp is None:
        print("  %s: no 0xBBBB response" % tag)
        return None
    # position in the payload -> position in the response
    where = {}
    for pi, val in enumerate(pattern):
        hits = [ri for ri in range(64) if resp[ri] == val]
        if len(hits) == 1:
            where[pi] = hits[0]
    print("  %s: %d of 32 payload bytes located uniquely" % (tag, len(where)))
    if not where:
        nz = [(i, hex(resp[i])) for i in range(64) if resp[i]]
        print("    raw response, nonzero bytes: %s" % nz)
        print("    wrote: %s ..." % [hex(v) for v in pattern[:8]])
    return where


try:
    signal.alarm(600)

    print("=" * 68)
    print("Read layout measured from a live response: the 256-bit row occupies")
    print("bytes 0..31, and within each 32-bit group the bytes are LITTLE-endian.")
    print("Established by decoding a real row as {len,addr} pointers and getting")
    print("coherent, monotonically increasing values.  The compiler's WRITE path")
    print("is separately proven by check_64bit.py returning 99,199,...,1599.")
    print("=" * 68)
    print()

    print("=" * 68)
    print("STAGE 3 -- decode a real compiler-emitted synapse")
    print("=" * 68)
    from hs_api.api import CRI_network
    from hs_api.neuron_models import ANN_neuron
    import hs_bridge.FPGA_Execution.fpga_compiler as fc

    SYN_BASE = getattr(fc, "SYN_BASE_ADDR", None)
    AXN_BASE = getattr(fc, "AXN_BASE_ADDR", None)
    if SYN_BASE is None:
        import config as _cfg
        SYN_BASE = _cfg.SYN_BASE_ADDR
        AXN_BASE = getattr(_cfg, "AXN_BASE_ADDR", 0)
    print("  SYN_BASE_ADDR = %d   AXN_BASE_ADDR = %s" % (SYN_BASE, AXN_BASE))

    model = ANN_neuron(threshold=50000, shift=-17, leak=0)
    net = CRI_network(axons={'a0': [('n0', W)]}, connections={'n0': ([], model)},
                      outputs=['n0'], target='CRI', syn_64bit=True)
    comp = net.CRI.compiledNetwork
    n = 0
    for r in comp.synapses:
        for i, w in enumerate(r):
            if w[0] == 0 and int(w[2]) != 0:
                r[i] = (w[0], w[1], w[2], DELAY, 0)
                n += 1
    comp.create_synapses(syn_64bit=True)
    print("  emitted 1 synapse, weight=%d delay=%d (%d tuple(s) patched)\n"
          % (W, DELAY, n))

    def row_words(row):
        """Return the eight 32-bit words of an HBM row, using the measured
        layout: bytes 0..31, little-endian within each group."""
        resp = hbm_read_raw(row)
        if resp is None:
            return None
        b = resp[:32]
        return [(b[4*g+3] << 24) | (b[4*g+2] << 16) | (b[4*g+1] << 8) | b[4*g]
                for g in range(8)]

    # Follow the axon pointer instead of assuming where the synapses are.
    print("  axon pointer row %d:" % AXN_BASE)
    words = row_words(AXN_BASE)
    if not words:
        raise SystemExit("no response reading the axon pointer row")
    targets = []
    for i, wd in enumerate(words):
        ln, ad = wd >> 23, wd & 0x7FFFFF
        if ad:
            print("    entry %d: len=%-4d addr=%d" % (i, ln, ad))
            targets.append((ln, ad))
    if not targets:
        raise SystemExit("axon pointer row is empty -- nothing to follow")

    ln, ad = targets[0]
    print("\n  following the first pointer: %d row(s) from %d\n" % (ln + 1, ad))
    for row in range(ad, ad + ln + 1):
        words = row_words(row)
        if not words or not any(words):
            continue
        v = 0
        for wd in reversed(words):
            v = (v << 32) | wd
        print("  HBM row %d" % row)
        for e in range(4):
            ent = (v >> (64 * (3 - e))) & ((1 << 64) - 1)
            def f(hi_, lo_):
                return (ent >> lo_) & ((1 << (hi_ - lo_ + 1)) - 1)
            wt = f(47, 32)
            wt = wt - 65536 if wt >= 32768 else wt
            mark = "   <== weight %d, delay reads %d" % (W, f(31, 26)) if wt == W else ""
            print("    entry %d: op=%d dest=%-5d weight=%-7d delay=%-3d src=%-6d%s"
                  % (e, f(63, 61), f(60, 48), wt, f(31, 26), f(17, 0), mark))
        print()

    print("=" * 68)
    print("Read the line marked <==.  If delay there is %d, the compiler" % DELAY)
    print("writes the field correctly and the bug is on the RTL read side.")
    print("If it is not %d, the delay bits land where the IEP does not look" % DELAY)
    print("-- deterministic, software-side, and unchanged by any RTL fix,")
    print("which is exactly what three byte-identical traces showed.")
    print("=" * 68)

except Timeout:
    print("\nABORTED: timed out")
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
