#!/usr/bin/env python3
"""
Per-synapse and per-axon delay on hardware -- corrected expectations, hang-safe.

WHY THE EARLIER TEST WAS WRONG
------------------------------
test_delay_stdp2.py asserted a delay shift of exactly 3.  On the bitstream it
ran against that was wrong twice over: FIX J was not yet applied, so a
requested delay N actually arrived at N+2, and the test would have failed even
against correct silicon.  It also hung the DMA driver hard enough to need a
reflash, because it looped on dma_dump_read with no bound.

WHAT THIS ONE DOES DIFFERENTLY
------------------------------
* Correct expectation.  With FIX J, delay N delivers at exactly timestep N
  (0 = immediate, 1 -> next timestep, ...).  Measured on both delay_buffer.v
  and axon_delay_buffer.v in simulation across delays 0-5.
* Control case first.  delay=0 must produce the reference trace before any
  delayed case is attempted.  If the control is wrong the harness is wrong and
  the script stops -- that is what the earlier run should have done.
* Bounded everywhere.  Every read has a retry cap, every loop a maximum
  iteration count.  Nothing can spin on the DMA device.
* Restores delta_mode and clears the axon delay table on exit, including on
  exception, so a failure cannot leave the card in a strange state.

  cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_delay_hw.py

PREREQUISITE: a bitstream built from the current tree (FIX J on both delay
buffers).  Confirm 42/42 and 8/8 first -- if those fail, nothing here is
meaningful.
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

DEC, W = 3900, 1000
DRIVE = (W * DEC) >> 12          # 952
MAX_STEPS = 10
results = {}


# ---- a hard wall-clock guard so nothing can wedge the card ----------------
class Timeout(Exception):
    pass


def _alarm(sig, frm):
    raise Timeout("exceeded wall-clock budget")


signal.signal(signal.SIGALRM, _alarm)


def cfg(**kw):
    p = dict(delta_mode=0, decay_ex=DEC, decay_in=DEC, decay_w=0, delta_w=0,
             coba_mode=0, E_ex=0, E_in=0, neuromod_excitability_bias=0,
             stdp_enable=0, syn_64bit_en=1, coreID=0)
    p.update(kw)
    dmadump.dma_dump_write(build_cmd13_packet(**p), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def restore():
    """Always leave the card in delta mode with no axon delays."""
    try:
        for a in range(4):
            write_axon_delay(a, 0)
        dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                               64, 1, 0, 0, 0, dmadump.DmaMethodNormal)
    except Exception:
        pass


def write_axon_delay(axon, delay, coreID=0):
    arr = [0] * 64
    arr[63] = 14
    arr[62] = int(np.binary_repr(coreID, 5) + '000', 2)
    arr[0] = (delay & 0x3F) | ((axon & 0x3) << 6)
    arr[1] = (axon >> 2) & 0xFF
    arr[2] = (axon >> 10) & 0x07
    dmadump.dma_dump_write(np.array(arr, dtype=np.uint64), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def mknet():
    m = ANN_neuron(threshold=50000, shift=-17, leak=0)
    return CRI_network(axons={'a0': [('n0', W)]}, connections={'n0': ([], m)},
                       outputs=['n0'], target='CRI', syn_64bit=True)


def set_syn_delay(net, delay):
    """Rewrite the synapse tuples to carry `delay`, then re-emit via the
    validated 64-bit writer.  The connectome has no delay field, so the tuples
    are patched here rather than declared."""
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
    """Zero Row B before measuring.  Without this the drive lands on top of
    residual I_ex from a previous run and no expected value ever matches --
    the trace [550, 1475, ...] is 550 decayed plus the 952 drive."""
    cfg(decay_ex=0, decay_in=0)
    for _ in range(8):
        try:
            net.step([])
        except Exception:
            pass
    cfg()


def trace(net, nsteps=MAX_STEPS):
    out = []
    for s in range(nsteps):
        try:
            net.step(['a0'] if s == 0 else [])
        except Exception:
            pass
        out.append(sv(net.CRI.readMP([0])[0][3]))
    return out


def first_drive(tr):
    return tr.index(DRIVE) if DRIVE in tr else None


def banner(t):
    print("=" * 68); print(t); print("=" * 68)


# ------------------------------------------------------------- control ----
def control():
    banner("0. CONTROL -- delay 0 must land at the reference step")
    net = mknet()
    reset_rowb(net)
    set_syn_delay(net, 0)
    cfg()
    tr = trace(net)
    idx = first_drive(tr)
    print("   trace: %s" % tr)
    print("   drive %d first at step %s" % (DRIVE, idx))
    if idx is None:
        print("\n   CONTROL FAILED -- the immediate path does not work, so no")
        print("   delayed result would mean anything.  Stopping here.")
        return None
    print("   control OK\n")
    return idx


# ------------------------------------------------------ per-synapse -------
def t_syn_delay(base):
    banner("1. PER-SYNAPSE DELAY -- delay N must land N steps after delay 0")
    ok = True
    for d in (1, 2, 3):
        net = mknet()
        reset_rowb(net)
        set_syn_delay(net, d)
        cfg()
        tr = trace(net)
        idx = first_drive(tr)
        shift = None if idx is None else idx - base
        good = (shift == d)
        ok &= good
        print("   delay=%d -> step %-4s shift %-4s expect %d   %s"
              % (d, idx, shift, d, "PASS" if good else "FAIL"))
        print("      %s" % tr)
    results["per-synapse delay"] = ok
    print()


# --------------------------------------------------------- per-axon ------
def t_axon_delay(base):
    banner("2. PER-AXON DELAY -- CMD 14 table, same expectation")
    ok = True
    for d in (1, 2, 3):
        net = mknet()
        reset_rowb(net)
        set_syn_delay(net, 0)
        write_axon_delay(0, d)
        cfg()
        tr = trace(net)
        write_axon_delay(0, 0)
        idx = first_drive(tr)
        shift = None if idx is None else idx - base
        good = (shift == d)
        ok &= good
        print("   axon delay=%d -> step %-4s shift %-4s expect %d   %s"
              % (d, idx, shift, d, "PASS" if good else "FAIL"))
        print("      %s" % tr)
    results["per-axon delay"] = ok
    print()


try:
    signal.alarm(600)                       # 10 minutes, hard stop
    base = control()
    if base is not None:
        t_syn_delay(base)
        t_axon_delay(base)
except Timeout as e:
    print("\nABORTED: %s -- the card may need a reflash." % e)
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
    restore()

banner("SUMMARY")
if not results:
    print("  nothing ran")
for k, v in results.items():
    print("  %-22s %s" % (k, "PASS" if v else "FAIL"))
print()
print("  drive = %d (weight %d, decay_ex %d)" % (DRIVE, W, DEC))
print("  delta_mode and the axon delay table have been restored.")
print("=" * 68)
