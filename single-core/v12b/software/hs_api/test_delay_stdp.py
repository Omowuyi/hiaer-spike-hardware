#!/usr/bin/env python3
"""
The last three unvalidated features: per-synapse delay, per-axon delay, STDP.

All three are in the bitstream and all three are now unblocked by the 64-bit
synapse path working.  Each test is independent, with its own network and its
own pass/fail, so one broken feature cannot mask another.

  cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_delay_stdp.py

METHOD -- synapse rows are written directly with CMD 2 rather than through the
compiler, because the connectome has no delay field yet: a synapse tuple is
(op, dest, weight) and compiler_64bit.py only carries delay when given a
5-tuple.  Direct writes also isolate the RTL datapath from the emit path.

Row order follows the convention measured by check_64bit.py: slot quad q is
written at HBM row 3-q, so a single group-0 synapse (slot 0, quad 0) goes to
HBM row SYN_BASE+3, position 0.
"""

import sys, time
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

SYN_BASE, AXN_BASE = 2 ** 15, 0
PTR_LEN_BITS, PTR_ADDR_BITS = 9, 23
SYN_OP_BITS, SYN_ADDR_BITS, SYN_WEIGHT_BITS = 3, 13, 16
DEC, W = 3900, 1000
DRIVE = (W * DEC) >> 12          # 952
results = {}


# ---------------------------------------------------------------- helpers ---
def _core_hdr(coreID=0):
    coreBits = np.binary_repr(coreID, 5) + '000'
    return [2, int(coreBits, 2)] + [0] * 27


def hbm_write_row(row, payload, coreID=0):
    """CMD 2 write of one 256-bit HBM row.  payload = 32 bytes, MSB entry first."""
    assert len(payload) == 32
    ra = '1' + np.binary_repr(row, 23)          # leading 1 = write
    cmd = _core_hdr(coreID) + [int(ra[:8], 2), int(ra[8:16], 2), int(ra[16:], 2)] + payload
    dmadump.dma_dump_write(np.flip(np.array(cmd, dtype=np.uint64)), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def hbm_read_row(row, coreID=0, tries=200):
    """CMD 2 read; returns the 32 payload bytes of the 0xBBBB response."""
    ra = '0' + np.binary_repr(row, 23)          # leading 0 = read
    cmd = _core_hdr(coreID) + [int(ra[:8], 2), int(ra[8:16], 2), int(ra[16:], 2)] + [0] * 32
    dmadump.dma_dump_write(np.flip(np.array(cmd, dtype=np.uint64)), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)
    for _ in range(tries):
        rc, buf = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
        if rc != 0:
            continue
        b = list(buf)
        if b[63] == 0xBB and b[62] == 0xBB:
            return b[:32]
    return None


def write_axon_delay(axon, delay, coreID=0):
    """CMD 14: [18:6]=axon addr, [5:0]=delay."""
    arr = [0] * 64
    arr[63] = 14
    arr[62] = int(np.binary_repr(coreID, 5) + '000', 2)
    arr[0] = (delay & 0x3F) | ((axon & 0x3) << 6)
    arr[1] = (axon >> 2) & 0xFF
    arr[2] = (axon >> 10) & 0x07
    dmadump.dma_dump_write(np.array(arr, dtype=np.uint64), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def entry64(dest, weight, delay=0, src=0, stdp_tag=0):
    b = (np.binary_repr(0, SYN_OP_BITS) + np.binary_repr(dest, SYN_ADDR_BITS)
         + np.binary_repr(int(weight) & 0xFFFF, SYN_WEIGHT_BITS)
         + np.binary_repr(delay, 6) + np.binary_repr(0, 4)
         + np.binary_repr(stdp_tag, 4) + np.binary_repr(src, 18))
    assert len(b) == 64
    return [int(b[i:i + 8], 2) for i in range(0, 64, 8)]


def ptr_entry(length, addr):
    b = np.binary_repr(length, PTR_LEN_BITS) + np.binary_repr(addr, PTR_ADDR_BITS)
    return [int(b[i:i + 8], 2) for i in range(0, 32, 8)]


def install_one_synapse(weight=W, delay=0, src=0, stdp_tag=0):
    """One group-0 synapse -> slot 0 -> quad 0 -> HBM row SYN_BASE+3, position 0."""
    for r in range(4):
        payload = []
        for p in range(4):
            if r == 3 and p == 0:
                payload += entry64(0, weight, delay, src, stdp_tag)
            else:
                payload += [0] * 8
        hbm_write_row(SYN_BASE + r, payload)
    hbm_write_row(AXN_BASE, ptr_entry(3, SYN_BASE) * 8)


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


def mknet(threshold=50000):
    m = ANN_neuron(threshold=threshold, shift=-17, leak=0)
    return CRI_network(axons={'a0': [('n0', 1)]}, connections={'n0': ([], m)},
                       outputs=['n0'], target='CRI', syn_64bit=True)


def step(net, ax=None):
    try:
        return net.step(ax if ax else [])
    except Exception:
        return None


def reset_rowb(net):
    cfg(decay_ex=0, decay_in=0)
    for _ in range(8):
        step(net)
    cfg()


def trace(net, nsteps, first_input=True):
    out = []
    for s in range(nsteps):
        step(net, ['a0'] if (s == 0 and first_input) else [])
        out.append(sv(net.CRI.readMP([0])[0][3]))
    return out


def banner(t):
    print("=" * 70); print(t); print("=" * 70)


def report(name, ok, detail=""):
    results[name] = ok
    print("  %-26s %s" % (name, "PASS" if ok else "FAIL"))
    if detail:
        print(detail)
    print()


# ------------------------------------------------------- 1 synapse delay ---
def t_synapse_delay():
    banner("1. PER-SYNAPSE DELAY  (64-bit entry, delay field [31:26])")
    got = {}
    for d in (0, 3):
        net = mknet()
        reset_rowb(net)
        install_one_synapse(delay=d)
        cfg()
        got[d] = trace(net, 8)
        print("      delay=%d -> %s" % (d, got[d]))
    print()
    # delay=0 lands at step index 1; delay=D lands at index 1+D
    try:
        i0 = got[0].index(DRIVE)
        i3 = got[3].index(DRIVE)
        shift = i3 - i0
    except ValueError:
        i0 = i3 = shift = None
    ok = (shift == 3)
    report("per-synapse delay", ok,
           "      drive %d first appears at step %s (delay=0) and %s (delay=3)\n"
           "      shift = %s, expected 3" % (DRIVE, i0, i3, shift))


# ---------------------------------------------------------- 2 axon delay ---
def t_axon_delay():
    banner("2. PER-AXON DELAY  (CMD 14 delay table)")
    got = {}
    for d in (0, 3):
        net = mknet()
        reset_rowb(net)
        install_one_synapse(delay=0)
        write_axon_delay(0, d)
        cfg()
        got[d] = trace(net, 8)
        print("      axon delay=%d -> %s" % (d, got[d]))
    write_axon_delay(0, 0)
    print()
    try:
        i0, i3 = got[0].index(DRIVE), got[3].index(DRIVE)
        shift = i3 - i0
    except ValueError:
        i0 = i3 = shift = None
    ok = (shift == 3)
    report("per-axon delay", ok,
           "      drive first appears at step %s (no delay) and %s (delay=3)\n"
           "      shift = %s, expected 3\n"
           "      shift=0 means CMD 14 is not reaching the delay table" % (i0, i3, shift))


# ---------------------------------------------------------------- 3 STDP ---
def t_stdp():
    banner("3. STDP  (Phase 4 weight write-back)")
    net = mknet(threshold=500)          # low threshold so n0 spikes
    reset_rowb(net)
    install_one_synapse(weight=W, delay=0, src=0, stdp_tag=0)

    before = hbm_read_row(SYN_BASE + 3)
    if before is None:
        report("STDP weight update", False,
               "      HBM read-back returned no 0xBBBB packet -- cannot verify.\n"
               "      Everything else in this script is unaffected.")
        return
    w_before = (before[2] << 8) | before[3]     # entry 0, weight = bits [47:32]
    print("      weight in HBM before: %d  (wrote %d)" % (w_before, W))
    if w_before != W:
        print("      NOTE: read-back does not match what was written -- the byte")
        print("      order of hbm_read_row may not mirror hbm_write_row.")

    cfg(stdp_enable=1, A_plus=64, A_minus=0, w_max=32767, w_min=0)
    for _ in range(10):
        step(net, ['a0'])
    cfg()

    after = hbm_read_row(SYN_BASE + 3)
    w_after = (after[2] << 8) | after[3] if after else None
    print("      weight in HBM after 10 spiking steps: %s" % w_after)
    print()
    ok = (w_after is not None and w_after != w_before)
    report("STDP weight update", ok,
           "      the weight must CHANGE once stdp_enable=1 and the neuron spikes.\n"
           "      unchanged -> Phase 4 is not writing back; likely the neuron\n"
           "      pointer entry position inside its 256-bit row, which is the\n"
           "      same class of layout assumption the group order turned out to be")


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
print("  Expected drive value: %d   (weight %d, decay_ex %d)" % (DRIVE, W, DEC))
print("=" * 70)
