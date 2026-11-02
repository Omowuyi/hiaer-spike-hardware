#!/usr/bin/env python3
# ============================================================================
# exp_psc biological feature test — 64-BIT synapse packing
#
# The exp_psc RTL (delta_mode=0) reads 64-bit synapse entries:
#   reg_arr_64[N] = exec_hbm_rdata[64N+63 : 64N]   (8 entries/512-bit word)
#   entry fields: [63:61]op [60:48]dest [47:32]weight [31:26]delay
#                 [25:22]syn_type [21:18]stdp_tag [17:0]src
#   group 0 = entry 7 = [511:448]; weight at [495:480].
#
# The standard compiler writes 32-bit entries — exp_psc can't read those. This script
# writes 64-bit entries directly (verified: every field lands at the RTL read position).
#
# Runs on the CURRENT flashed bitstream (phase fix + original 64-bit extraction) — NO rebuild.
#
#   cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
#   export PYTHONPATH=/home/omowuyi/testing/hs_bridge
#   python3 test_exp_psc_64bit.py
# ============================================================================

import sys, numpy as np
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.FPGA_Execution.fpga_controller import SYN_BASE_ADDR
from hs_api.single_core_conductance_STDP import build_cmd13_packet


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v

# ---- 64-bit synapse entry (RTL-verified field layout) ----
def entry64(op=0, dest=0, weight=0, delay=0, syn_type=0, stdp_tag=0, src=0):
    return (((op & 7) << 61) | ((dest & 0x1FFF) << 48) | ((int(weight) & 0xFFFF) << 32)
            | ((delay & 0x3F) << 26) | ((syn_type & 0xF) << 22)
            | ((stdp_tag & 0xF) << 18) | (src & 0x3FFFF))

# ---- pack 4 x 64-bit entries into a 256-bit HBM row ----
# group g in this row -> data bytes [g*8 : g*8+8], MSB-first.
# n0 = group 0 = entry position 0 (row1 = 2nd beat).
def pack_row_64(entries4):
    data = [0] * 32
    for g, e in enumerate(entries4):
        eb = [(int(e) >> (8 * (7 - b))) & 0xFF for b in range(8)]
        for k in range(8):
            data[g * 8 + k] = eb[k]
    return data

def wr(r, entries4, c=0):
    data = pack_row_64(entries4)
    a = '1' + np.binary_repr(SYN_BASE_ADDR + r, 23)
    cmd = [2, c] + [0] * 27 + [int(a[:8], 2), int(a[8:16], 2), int(a[16:], 2)] + data
    dmadump.dma_dump_write(np.flip(np.array(cmd, dtype=np.uint64)),
                           len(cmd), 1, 0, 0, 0, dmadump.DmaMethodNormal)

def cmd13(**kw):
    dmadump.dma_dump_write(build_cmd13_packet(**kw), 64, 1, 0, 0, 0, dmadump.DmaMethodNormal)
def delta():
    cmd13(delta_mode=1, coreID=0)

def new_net(threshold=500, weight=1000):
    model = ANN_neuron(threshold=threshold, shift=-17, leak=0)
    return CRI_network(axons={'a0': [('n0', weight)]},
                       connections={'n0': ([], model)}, outputs=['n0'], target='CRI')
def V(net):
    return sv(net.CRI.readMP([net.connectome.get_neuron_by_key('n0').get_hbmIdx()])[0][3])
def clear_baseline(net):
    net.step(['a0']); net.step([]); return V(net)
def banner(n):
    print(f"\n{'='*60}\n  {n}\n{'='*60}")

# write n0's synapse as a 64-bit entry (group 0 = row1 position 0), clear row0.
def write_n0_64(weight=1000, delay=0, stdp_tag=0, src=0, syn_type=0):
    wr(1, [entry64(op=0, dest=0, weight=weight, delay=delay,
                   syn_type=syn_type, stdp_tag=stdp_tag, src=src), 0, 0, 0])
    wr(0, [0, 0, 0, 0])


# ------------------------------------------------------------
# STAGE 0 — gating: basic excitatory PSC with 64-bit write
# ------------------------------------------------------------
def stage0():
    banner("STAGE 0  Basic excitatory PSC (64-bit write, gating check)")
    net = new_net(threshold=500, weight=1000)
    net.step(['a0']); print("  delta spike:      V =", V(net))
    net.step([]);     print("  cleared baseline: V =", V(net))
    write_n0_64(weight=1000)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    print("  baseline before exp:", V(net))
    vs = []
    for i in range(1, 8):
        try: net.step(['a0'] if i == 1 else [])
        except Exception as e: print(f"    step{i}: spiked ({type(e).__name__})")
        vs.append(V(net)); print(f"  exp_psc step{i}: V = {vs[-1]}")
    delta()
    ok = any(v != 0 for v in vs)
    print(f"\n  RESULT: 64-bit weight path {'WORKS' if ok else 'FAILS (V=0)'}")
    return ok


def test_exp_psc():
    banner("1. Exponential PSC decay")
    net = new_net(threshold=1000000, weight=1000)
    net.step(['a0']); print("  delta control V =", V(net))
    write_n0_64(weight=1000)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 9):
        net.step(['a0'] if i == 1 else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> peak={max(vs)}, decays after peak: {vs[-1] < max(vs) if max(vs)>0 else False}")

def test_inhibitory():
    banner("2. Inhibitory PSC (negative weight)")
    net = new_net(threshold=1000000, weight=1000)
    net.step(['a0']); print("  delta control V =", V(net))
    write_n0_64(weight=-1000)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 6):
        net.step(['a0'] if i == 1 else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> min V = {min(vs)} (should go negative)")

def test_coba():
    banner("3. COBA conductance")
    net = new_net(threshold=1000000, weight=1000)
    net.step(['a0']); print("  delta control V =", V(net))
    write_n0_64(weight=1000)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=1, E_ex=2000, E_in=-2000, coreID=0)
    vs = []
    for i in range(1, 7):
        net.step(['a0'] if i == 1 else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> peak={max(vs)} (V approaches E_ex, drive shrinks as V rises)")

def test_adex():
    banner("4. AdEx adaptation")
    net = new_net(threshold=500, weight=1000)
    clear_baseline(net); print("  baseline cleared")
    write_n0_64(weight=1000)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, decay_w=200, delta_w=100, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 10):
        net.step(['a0'] if i % 2 == 1 else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> Vs={vs} (response reduces over repeated spikes)")

def test_refractory():
    banner("5. Refractory period")
    net = new_net(threshold=500, weight=1000)
    clear_baseline(net); print("  baseline cleared")
    write_n0_64(weight=1000)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 8):
        net.step(['a0']); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> Vs={vs} (post-spike suppression)")

def test_stdp():
    banner("6. STDP (needs 64-bit stdp_tag + src)")
    net = new_net(threshold=500, weight=1000)
    clear_baseline(net); print("  baseline cleared")
    # stdp_tag nonzero + src address in the 64-bit entry enable STDP eligibility
    write_n0_64(weight=1000, stdp_tag=1, src=0)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, stdp_enable=1,
          A_plus=50, A_minus=50, w_max=2000, w_min=0, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 8):
        net.step(['a0'] if i in (1, 3) else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> Vs={vs} (STDP modifies weight on pre/post pairing)")

def test_neuromod():
    banner("7. Neuromodulation")
    net = new_net(threshold=1000, weight=800)
    clear_baseline(net)
    write_n0_64(weight=800)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, neuromod_excitability_bias=500, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 6):
        net.step(['a0'] if i == 1 else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> Vs={vs} (excitability bias shifts threshold)")

def test_delay():
    banner("8. Synaptic delay (needs 64-bit delay field)")
    net = new_net(threshold=1000000, weight=1000)
    clear_baseline(net)
    # delay=3: the spike effect should appear ~3 steps later via delay_buffer
    write_n0_64(weight=1000, delay=3)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 9):
        net.step(['a0'] if i == 1 else []); vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> Vs={vs} (effect delayed ~3 steps vs immediate)")

def test_soft_reset():
    banner("9. Soft reset")
    net = new_net(threshold=500, weight=1200)
    clear_baseline(net)
    write_n0_64(weight=1200)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs = []
    for i in range(1, 6):
        try: net.step(['a0'] if i == 1 else [])
        except Exception as e: print(f"    step{i}: spiked ({type(e).__name__})")
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta(); print(f"  -> Vs={vs} (post-spike V = V-threshold, not 0)")


if __name__ == "__main__":
    print("exp_psc 9-feature suite — 64-bit synapse packing (current bitstream, no rebuild)")
    if not stage0():
        print("\nSTAGE 0 failed (V=0). The 64-bit write isn't reaching I_ex.")
        print("Paste STAGE 0 output — next step depends on whether it's the packing byte-order")
        print("or the phase timing. Stopping before the feature tests.")
        sys.exit(0)
    test_exp_psc()
    test_inhibitory()
    test_coba()
    test_adex()
    test_refractory()
    test_stdp()
    test_neuromod()
    test_delay()
    test_soft_reset()
    print("\n" + "="*60 + "\n  All 9 features tested with 64-bit synapse packing.\n" + "="*60)
