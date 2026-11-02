#!/usr/bin/env python3
# exp_psc (delta_mode=0) validation for the FIXED bitstream.
#
# Changes from the old test_exp_basic.py:
#   * threshold 500 -> 5000.  With leak=0 the RTL computes V = I_ex_decayed each
#     timestep, peaking near 952.  At threshold=500 the neuron fires immediately
#     and V resets to 0, so a WORKING design reads V=0.  5000 keeps V observable.
#   * also reads Row B so a failure can be localised: if I_ex is nonzero but V is
#     0, Phase 2 works and Phase 0 is not converting I_ex into V.  If both are 0,
#     Phase 2 is not accumulating.
#   * self-checks against the expected decay sequence.
#
#   cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
#   export PYTHONPATH=/home/omowuyi/testing/hs_bridge
#   python3 test_exp_fixed.py

import sys
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

WEIGHT   = 1000
DECAY_EX = 3900          # I_ex_next = (I_ex * 3900) >> 12
NSTEPS   = 7
ROW_B    = 4096          # Row B full-address offset (see ROW_B_FULL_OFFSET)
NG       = 16            # ng_num


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def set_mode(delta, decay=DECAY_EX):
    dmadump.dma_dump_write(
        build_cmd13_packet(delta_mode=delta, decay_ex=decay, decay_in=decay,
                           coba_mode=0, stdp_enable=0, coreID=0),
        64, 1, 0, 0, 0, dmadump.DmaMethodNormal)


def step(net, axons=None):
    try:
        net.step(axons if axons else [])
        return ""
    except Exception as e:
        return "  (step raised %s)" % type(e).__name__


# threshold raised so the drive never crosses it
model = ANN_neuron(threshold=5000, shift=-17, leak=0)
net = CRI_network(axons={'a0': [('n0', WEIGHT)]},
                 connections={'n0': ([], model)},
                 outputs=['n0'], target='CRI')

n0 = net.connectome.get_neuron_by_key('n0').get_hbmIdx()
row_a_idx = n0                          # Row A: membrane potential
row_b_idx = (n0 // NG + ROW_B) * NG + (n0 % NG)   # Row B: I_ex / I_in / w / trace


def read_V():
    return sv(net.CRI.readMP([row_a_idx])[0][3])


def read_rowb():
    """Row B half-word [31:0] = {I_ex[7:0], I_in[11:0], w[7:0], trace[3:0]}.
    read_membranes drops bits [35:32], so only the low 8 bits of I_ex survive."""
    v = int(net.CRI.readMP([row_b_idx])[0][3]) & 0xFFFFFFFF
    return {'i_ex_low8': (v >> 24) & 0xFF,
            'i_in': (v >> 12) & 0xFFF,
            'w': (v >> 4) & 0xFF,
            'trace': v & 0xF,
            'raw': v}


# expected V, mirroring the RTL: floor(I_ex * decay / 4096), applied in Phase 0
# of the timestep AFTER the one where Phase 2 accumulated the weight
expected = [0]
i_ex = WEIGHT
for s in range(2, NSTEPS + 1):
    i_ex = (i_ex * DECAY_EX) >> 12
    expected.append(i_ex)

print("n0 hbmIdx = %d   Row A idx = %d   Row B idx = %d"
      % (n0, row_a_idx, row_b_idx))
print()

print("=" * 66)
print("delta_mode = 1   (control - must still work)")
print("=" * 66)
set_mode(1)
print(step(net, ['a0']) or "", end="")
v = read_V()
print("  spike step : V = %-8d (expect %d)  %s" % (v, WEIGHT, "ok" if v == WEIGHT else "<-- FAIL"))
print(step(net) or "", end="")
v = read_V()
print("  cleared    : V = %-8d (expect 0)     %s" % (v, "ok" if v == 0 else "<-- FAIL"))
print()

print("=" * 66)
print("delta_mode = 0   (exp_psc)")
print("=" * 66)
set_mode(0)
print("  baseline before input: V = %d" % read_V())
print()

fails = 0
for s in range(1, NSTEPS + 1):
    msg = step(net, ['a0'] if s == 1 else [])
    v = read_V()
    b = read_rowb()
    want = expected[s - 1]
    ok = (v == want)
    fails += 0 if ok else 1
    print("  step %d : V = %-8d (expect %-6d) %-9s | RowB i_ex&0xFF=%-4d i_in=%-5d w=%-4d trace=%d%s"
          % (s, v, want, "ok" if ok else "<-- MISMATCH",
             b['i_ex_low8'], b['i_in'], b['w'], b['trace'], msg))

set_mode(1)   # restore delta mode

print()
print("=" * 66)
if fails == 0:
    print("PASS - exp_psc membrane potential tracks the expected exponential decay.")
else:
    print("%d/%d timesteps mismatched." % (fails, NSTEPS))
    print()
    print("How to read it:")
    print("  V=0 but RowB i_ex nonzero  -> Phase 2 accumulates, Phase 0 is not")
    print("                                converting I_ex into V (Fix A region).")
    print("  V=0 and RowB i_ex==0       -> Phase 2 is not accumulating at all")
    print("                                (Fix C region), or decay_ex arrived 0.")
    print("  V nonzero but wrong scale  -> decay_ex mismatch; expected sequence")
    print("                                assumes decay_ex=%d." % DECAY_EX)
    print("  All neurons read the same  -> readMP addressing; run test_holdmp.py.")
print("=" * 66)
