#!/usr/bin/env python3
"""
Prove or disprove FIX W and FIX X -- without a build.

TWO CLAIMS
  W. _create_synapses_64 drops spike entries (w[0]==1), because it filters
     `if w[0] == 0`.  A dropped spike entry means the neuron can never report
     a spike in 64-bit mode.
  X. hbm_processor tests spike flags at 32-bit spacing -- hbm_rdata[31], [63],
     [95] ... -- so in 64-bit mode, where a row holds four 64-bit entries, it
     looks at the wrong bits.

Both are checkable by reading HBM back.  Nothing here changes RTL or requires
a bitstream.

METHOD
  1. Compile the SAME network twice, once 32-bit and once 64-bit.
  2. Read the synapse rows back through the axon pointer.
  3. Count entries whose opcode is 4 -- the spike entry.
     32-bit should have them.  If 64-bit has none, claim W is proven.
  4. For each spike entry found in the 64-bit rows, report whether the bit
     hbm_processor actually tests is set.  If the flag sits at bit 63 while
     the hardware tests bit 31, claim X is proven.

READBACK LAYOUT (measured, not derived)
  CMD 2 response: marker 0xBBBB in bytes 62-63, the 256-bit row in bytes
  0..31, little-endian within each 32-bit group.

  cd /home/omowuyi/testing/hs_api
  source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 prove_spike_entry.py
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as d

W = 1000
RTL_FLAG_BITS_32 = [31, 63, 95, 127, 159, 191, 223, 255]   # what the RTL tests


class Timeout(Exception):
    pass


signal.signal(signal.SIGALRM, lambda s, f: (_ for _ in ()).throw(Timeout()))


def read_row(row, coreID=0, tries=400):
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
                p = b[:32]
                words = [(p[4*g+3] << 24) | (p[4*g+2] << 16) | (p[4*g+1] << 8) | p[4*g]
                         for g in range(8)]
                v = 0
                for wd in reversed(words):
                    v = (v << 32) | wd
                return v, words
    return None, None


def axon_target():
    """Follow the axon pointer to the synapse rows.

    AXN_BASE_ADDR lives in config.py, not in fpga_compiler, so it is read at
    runtime.  Hardcoding row 0 was wrong -- that is what made the first run
    report 'could not follow the axon pointer'."""
    base = None
    try:
        import hs_bridge.FPGA_Execution.fpga_compiler as fc
        base = getattr(fc, "AXN_BASE_ADDR", None)
    except Exception:
        pass
    if base is None:
        try:
            import config as _cfg
            base = getattr(_cfg, "AXN_BASE_ADDR", 0)
        except Exception:
            base = 0
    for row in (base, base + 1, 0, 1):
        v, words = read_row(row)
        if words is None:
            continue
        for wd in words:
            ln, ad = wd >> 23, wd & 0x7FFFFF
            if ad:
                print("  axon pointer found in row %d" % row)
                return ln, ad
    return None


def build(bits64):
    m = ANN_neuron(threshold=50000, shift=-17, leak=0)
    kw = dict(axons={'a0': [('n0', W)]}, connections={'n0': ([], m)},
              outputs=['n0'], target='CRI')
    if bits64:
        kw['syn_64bit'] = True
    return CRI_network(**kw)


def survey(bits64, label):
    print("=" * 70)
    print("%s" % label)
    print("=" * 70)
    build(bits64)
    t = axon_target()
    if not t:
        print("  could not follow the axon pointer\n")
        return None
    ln, ad = t
    print("  axon pointer: %d row(s) from %d" % (ln + 1, ad))

    spikes, synapses = [], []
    for row in range(ad, ad + ln + 1):
        v, words = read_row(row)
        if v is None or not v:
            continue
        if bits64:
            for e in range(4):
                ent = (v >> (64 * (3 - e))) & ((1 << 64) - 1)
                op = (ent >> 61) & 7
                if op == 4:
                    spikes.append((row, e, ent, 63 + 64 * (3 - e)))
                elif op == 0 and ((ent >> 32) & 0xFFFF) == W:
                    synapses.append((row, e))
        else:
            for e in range(8):
                ent = (v >> (32 * (7 - e))) & 0xFFFFFFFF
                op = (ent >> 29) & 7
                if op == 4:
                    spikes.append((row, e, ent, 31 + 32 * (7 - e)))
                elif op == 0 and (ent & 0xFFFF) == W:
                    synapses.append((row, e))

    print("  synapses carrying weight %d : %d" % (W, len(synapses)))
    print("  spike entries (opcode 4)    : %d" % len(spikes))
    for row, e, ent, bitpos in spikes:
        addr = ent & 0x1FFFF
        print("     row %d entry %d: addr=%d, flag bit is %d in the row"
              % (row, e, addr, bitpos))
    print()
    return spikes, synapses


try:
    signal.alarm(900)

    r32 = survey(False, "A. 32-bit format (the proven path)")
    r64 = survey(True, "B. 64-bit format")

    print("=" * 70)
    print("VERDICT")
    print("=" * 70)
    if r32 is None or r64 is None:
        print("  incomplete -- could not read one of the two")
        raise SystemExit(1)

    s32, y32 = r32
    s64, y64 = r64

    print("  32-bit: %d spike entries, %d weighted synapses" % (len(s32), len(y32)))
    print("  64-bit: %d spike entries, %d weighted synapses" % (len(s64), len(y64)))
    print()

    if s32 and not s64:
        print("  CLAIM W PROVEN: the 32-bit emit writes spike entries and the")
        print("  64-bit emit writes none.  _create_synapses_64 is dropping them,")
        print("  so a neuron cannot report a spike in 64-bit mode.")
    elif s64:
        print("  CLAIM W DISPROVEN for this build: the 64-bit emit DOES contain")
        print("  spike entries, so they are not being dropped.")
    else:
        print("  Neither format shows a spike entry -- this network may not have")
        print("  one at all, which would make the comparison meaningless.  Try a")
        print("  network whose output neuron has outgoing synapses.")
    print()

    if s64:
        print("  Now claim X -- does the hardware look where the flag actually is?")
        for row, e, ent, bitpos in s64:
            tested = RTL_FLAG_BITS_32[e] if e < 8 else None
            print("     entry %d: flag at bit %d, hbm_processor tests bit %s  -> %s"
                  % (e, bitpos, tested,
                     "MATCH" if tested == bitpos else "MISALIGNED"))
        if any(RTL_FLAG_BITS_32[e] != bp for _, e, _, bp in s64 if e < 8):
            print("\n  CLAIM X PROVEN: the flag and the tested bit differ.")
        else:
            print("\n  CLAIM X DISPROVEN: they line up.")
    else:
        print("  Claim X cannot be tested until spike entries survive the")
        print("  64-bit emit -- apply FIX W first, then re-run this.")
    print("=" * 70)

except Timeout:
    print("\nABORTED: timed out")
except SystemExit:
    pass
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
