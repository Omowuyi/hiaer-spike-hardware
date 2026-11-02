#!/usr/bin/env python3
"""
Per-synapse delay, per-axon delay and STDP -- v2.

v1 hand-rolled the synapse rows with CMD 2 and got no drive even at delay=0,
which is the control case.  check_64bit.py returns perfect ascending order
through the compiler, so the emit path is proven and the hand-rolled one is
not.  This version stops hand-rolling: it builds the network normally, rewrites
the synapse tuples in place to carry a delay, and re-runs the SAME
_create_synapses_64 that check_64bit.py validated.

  (op, dest, weight)  ->  (op, dest, weight, delay, src)

_syn64_entry already accepts the 5-tuple; only the connectome lacks a delay
field, which is why the tuples are patched here rather than declared.

v1's HBM read was also wrong: entry 0 occupies row bits [255:192], so its
weight [47:32] is at DMA bytes 28-29, not 2-3.

  cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_delay_stdp2.py
"""

import sys
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

SYN_BASE = 2 ** 15
DEC, W = 3900, 1000
DRIVE = (W * DEC) >> 12          # 952
results = {}


def cfg(**kw):
    p = dict(delta_mode=0, decay_ex=DEC, decay_in=DEC, decay_w=0, delta_w=0,
             coba_mode=0, E_ex=0, E_in=0, neuromod_excitability_bias=0,
             stdp_enable=0, syn_64bit_en=1, coreID=0)
    p.update(kw)
    dmadump.dma_dump_write(build_cmd13_packet(**p), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def step(net, ax=None):
    try:
        return net.step(ax if ax else [])
    except Exception:
        return None


def mknet(threshold=50000):
    m = ANN_neuron(threshold=threshold, shift=-17, leak=0)
    return CRI_network(axons={'a0': [('n0', W)]}, connections={'n0': ([], m)},
                       outputs=['n0'], target='CRI', syn_64bit=True)


def set_delay(net, delay):
    """Rewrite every real synapse tuple to carry `delay`, then re-emit the
    synapse rows with the validated 64-bit writer."""
    comp = net.CRI.compiledNetwork
    n = 0
    for row in comp.synapses:
        for i, w in enumerate(row):
            if w[0] == 0 and int(w[2]) != 0:
                row[i] = (w[0], w[1], w[2], delay, 0)
                n += 1
    comp.create_synapses(syn_64bit=True)
    return n


def reset_rowb(net):
    cfg(decay_ex=0, decay_in=0)
    for _ in range(8):
        step(net)
    cfg()


def trace(net, nsteps):
    out = []
    for s in range(nsteps):
        step(net, ['a0'] if s == 0 else [])
        out.append(sv(net.CRI.readMP([0])[0][3]))
    return out


def hbm_read_row(row, coreID=0, tries=300):
    """CMD 2 read.  Returns the 32 payload bytes, index 31 = row bits [255:248]."""
    coreBits = np.binary_repr(coreID, 5) + '000'
    ra = '0' + np.binary_repr(row, 23)
    cmd = ([2, int(coreBits, 2)] + [0] * 27
           + [int(ra[:8], 2), int(ra[8:16], 2), int(ra[16:], 2)] + [0] * 32)
    dmadump.dma_dump_write(np.flip(np.array(cmd, dtype=np.uint64)), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)
    for _ in range(tries):
        rc, buf = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
        if rc == 0:
            b = list(buf)
            if b[63] == 0xBB and b[62] == 0xBB:
                return b[:32]
    return None


def entry0_weight(payload):
    """Entry 0 = row bits [255:192]; its weight [47:32] = bytes 28-29."""
    if payload is None:
        return None
    v = (payload[29] << 8) | payload[28]
    return v - 65536 if v >= 32768 else v


def banner(t):
    print("=" * 70); print(t); print("=" * 70)


def report(name, ok, detail=""):
    results[name] = ok
    print("  %-26s %s" % (name, "PASS" if ok else "FAIL"))
    if detail:
        print(detail)
    print()


# ------------------------------------------------------ 1 synapse delay ---
def t_synapse_delay():
    banner("1. PER-SYNAPSE DELAY  (delay field in the 64-bit entry)")
    got = {}
    for d in (0, 3):
        net = mknet()
        reset_rowb(net)
        n = set_delay(net, d)
        cfg()
        got[d] = trace(net, 9)
        print("      delay=%d (%d synapse tuples patched) -> %s" % (d, n, got[d]))
    print()
    idx = {}
    for d in (0, 3):
        idx[d] = got[d].index(DRIVE) if DRIVE in got[d] else None
    ok = (idx[0] is not None and idx[3] is not None and idx[3] - idx[0] == 3)
    report("per-synapse delay", ok,
           "      drive %d first appears at step %s (delay=0) and %s (delay=3)\n"
           "      shift expected 3, got %s"
           % (DRIVE, idx[0], idx[3],
              None if None in (idx[0], idx[3]) else idx[3] - idx[0]))


# --------------------------------------------------------- 2 axon delay ---
def write_axon_delay(axon, delay, coreID=0):
    arr = [0] * 64
    arr[63] = 14
    arr[62] = int(np.binary_repr(coreID, 5) + '000', 2)
    arr[0] = (delay & 0x3F) | ((axon & 0x3) << 6)
    arr[1] = (axon >> 2) & 0xFF
    arr[2] = (axon >> 10) & 0x07
    dmadump.dma_dump_write(np.array(arr, dtype=np.uint64), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def t_axon_delay():
    banner("2. PER-AXON DELAY  (CMD 14 delay table)")
    got = {}
    for d in (0, 3):
        net = mknet()
        reset_rowb(net)
        set_delay(net, 0)
        write_axon_delay(0, d)
        cfg()
        got[d] = trace(net, 9)
        print("      axon delay=%d -> %s" % (d, got[d]))
    write_axon_delay(0, 0)
    print()
    idx = {d: (got[d].index(DRIVE) if DRIVE in got[d] else None) for d in (0, 3)}
    ok = (idx[0] is not None and idx[3] is not None and idx[3] - idx[0] == 3)
    report("per-axon delay", ok,
           "      drive first appears at step %s (no delay) and %s (delay=3)\n"
           "      shift 0 means CMD 14 is not reaching the table" % (idx[0], idx[3]))


# --------------------------------------------------------------- 3 STDP ---
def t_stdp():
    banner("3. STDP  (Phase 4 weight write-back)")
    net = mknet(threshold=500)
    reset_rowb(net)
    set_delay(net, 0)
    cfg()

    probe = None
    for r in range(4):
        p = hbm_read_row(SYN_BASE + r)
        w = entry0_weight(p)
        print("      HBM row %d entry0 weight = %s" % (SYN_BASE + r, w))
        if w == W:
            probe = SYN_BASE + r
    if probe is None:
        report("STDP weight update", False,
               "      could not find the weight %d in any of the 4 synapse rows,\n"
               "      so the read-back is not aligned -- STDP itself is untested." % W)
        return
    print("      probing row %d\n" % probe)

    cfg(stdp_enable=1, A_plus=64, A_minus=0, w_max=32767, w_min=0)
    for _ in range(10):
        step(net, ['a0'])
    cfg()

    w_after = entry0_weight(hbm_read_row(probe))
    print("      weight after 10 spiking steps: %s (was %d)" % (w_after, W))
    print()
    report("STDP weight update", w_after is not None and w_after != W,
           "      unchanged -> Phase 4 is not writing back.  First place to look\n"
           "      is the neuron-pointer entry position inside its 256-bit row --\n"
           "      the same class of layout assumption the group order needed")


for fn in (t_synapse_delay, t_axon_delay, t_stdp):
    try:
        fn()
    except Exception:
        import traceback
        results[fn.__name__] = False
        print("  %s raised:" % fn.__name__)
        traceback.print_exc()
        print()

dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                       64, 1, 0, 0, 0, dmadump.DmaMethodNormal)

banner("SUMMARY")
for k, v in results.items():
    print("  %-26s %s" % (k, "PASS" if v else "FAIL"))
print()
print("  drive = %d   (weight %d, decay_ex %d)" % (DRIVE, W, DEC))
print("  delay=0 should read 0,952,906,...  delay=3 shifts that right by 3")
print("=" * 70)
