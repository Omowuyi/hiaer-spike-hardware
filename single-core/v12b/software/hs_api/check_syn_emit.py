#!/usr/bin/env python3
"""
What is ACTUALLY in HBM after the compiler emits a delayed synapse?

WHY
The delayed-synapse trace is byte-identical across three builds that differ by
FIX J, FIX U and FIX V:

    [-1935, 122, -1819, 233, -1713, 334, -1617, 425, -1531, 507]

Three RTL changes, zero effect.  The corruption cannot originate in RTL that
changed between those builds.  What is invariant is the software -- the
compiler's 64-bit entry packing.  And delay=0 works while delay!=0 does not,
so the emit path is fundamentally sound; only the delay field triggers it.

This reads the row back from HBM and decodes it, rather than deriving the
layout on paper.  Deriving it on paper is how the error_status offset ended up
wrong.

WHAT IT CHECKS
The IEP reads a 64-bit entry as:

    op[63:61]  dest[60:48]  weight[47:32]  delay[31:26]
    syn_type[25:22]  stdp_tag[21:18]  src[17:0]

and a 256-bit HBM row holds four of them.  Which end of the row entry 0 sits
at depends on the byte flip in _create_synapses_64, so this decodes BOTH
orientations and reports which one contains the values the compiler intended.
If neither does, the packing itself is wrong.

  cd /home/omowuyi/testing/hs_api
  source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 check_syn_emit.py
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as d

SYN_BASE = 2 ** 15
W, DELAY = 1000, 3


class Timeout(Exception):
    pass


signal.signal(signal.SIGALRM, lambda s, f: (_ for _ in ()).throw(Timeout()))


def hbm_read_row(row, coreID=0, tries=400):
    """CMD 2 read.  Response is {16'hBBBB, 240'd0, hbm2ci_dout}, so the
    256-bit row occupies bytes 0..31 and the marker bytes 62..63."""
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
                return b[:32]
    return None


def row_to_int(payload, msb_first):
    """Assemble the 256-bit row from 32 bytes, either orientation."""
    v = 0
    order = range(31, -1, -1) if msb_first else range(32)
    for i in order:
        v = (v << 8) | payload[i]
    return v


def decode(entry):
    def f(hi, lo):
        return (entry >> lo) & ((1 << (hi - lo + 1)) - 1)
    w = f(47, 32)
    return dict(op=f(63, 61), dest=f(60, 48),
                weight=w - 65536 if w >= 32768 else w,
                delay=f(31, 26), syn_type=f(25, 22),
                stdp_tag=f(21, 18), src=f(17, 0))


def show(tag, row):
    print("  %s" % tag)
    hit = False
    for e in range(4):
        ent = (row >> (64 * (3 - e))) & ((1 << 64) - 1)
        dd = decode(ent)
        mark = ""
        if dd["weight"] == W:
            mark = "  <-- weight %d found, delay reads %d" % (W, dd["delay"])
            hit = True
        print("    entry %d: op=%d dest=%-5d weight=%-7d delay=%-3d src=%-6d%s"
              % (e, dd["op"], dd["dest"], dd["weight"], dd["delay"], dd["src"], mark))
    return hit


try:
    signal.alarm(300)

    print("emitting one synapse: weight=%d, delay=%d, 64-bit format\n" % (W, DELAY))
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
    print("patched %d synapse tuple(s) to carry delay=%d" % (n, DELAY))
    comp.create_synapses(syn_64bit=True)
    print("re-emitted with syn_64bit=True\n")

    found_any = False
    for r in range(4):
        payload = hbm_read_row(SYN_BASE + r)
        if payload is None:
            print("row %d: no 0xBBBB response" % (SYN_BASE + r))
            continue
        if not any(payload):
            continue
        print("HBM row %d (SYN_BASE+%d)" % (SYN_BASE + r, r))
        a = show("as MSB-first (byte 31 highest):", row_to_int(payload, True))
        b = show("as LSB-first (byte 0 highest):", row_to_int(payload, False))
        found_any |= (a or b)
        print()

    print("=" * 66)
    if not found_any:
        print("weight %d not found in ANY row at either orientation." % W)
        print("The compiler is not writing what it intends -- the packing in")
        print("_syn64_entry or _create_synapses_64 is wrong, not the RTL.")
    else:
        print("The orientation where weight=%d appears is the real layout." % W)
        print("Check the delay field printed alongside it: if it is not %d," % DELAY)
        print("the delay bits land somewhere the IEP does not read them, and")
        print("that is the bug -- deterministic, software-side, and unchanged")
        print("by any RTL fix, which is exactly what the byte-identical traces")
        print("across three builds showed.")
    print("=" * 66)

except Timeout:
    print("\nABORTED: timed out")
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
    try:
        from hs_api.single_core_conductance_STDP import build_cmd13_packet
        d.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                         64, 1, 0, 0, 0, d.DmaMethodNormal)
    except Exception:
        pass
