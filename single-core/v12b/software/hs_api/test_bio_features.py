#!/usr/bin/env python3
"""
Biological feature suite for exp_psc (delta_mode=0).

Each feature gets its OWN network and its OWN pass/fail, so one broken feature
cannot poison the others.  Expected values are computed from the RTL, not
guessed:

  I_ex_dec = (I_ex * decay_ex) >> 12      arithmetic shift, signed
  I_in_dec = (I_in * decay_in) >> 12      arithmetic shift, signed
  w_dec    = (w * decay_w) >> 8           unsigned
  CUBA:  drive_ex = I_ex_dec              drive_in = I_in_dec
  COBA:  drive_ex = (g_ex_dec * (E_ex - V[11:0])) >> 12
  V_new  = V - (unsigned(V) >> leak) + drive_ex + drive_in - w_dec + noise
  spike  = V_new > (threshold - neuromod_bias)
  on spike: V = 0 (soft_reset unreachable), refrac = refractory_max,
            w += delta_w, trace = 0xF

  cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_bio_features.py
"""

import sys, traceback
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

DEC = 3900
results = {}


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def cfg(**kw):
    p = dict(delta_mode=0, decay_ex=DEC, decay_in=DEC, coba_mode=0,
             stdp_enable=0, coreID=0)
    p.update(kw)
    dmadump.dma_dump_write(build_cmd13_packet(**p), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def net_with(axons, threshold, refractory_max=0, nneurons=1):
    model = ANN_neuron(threshold=threshold, shift=-17, leak=0,
                       refractory_max=refractory_max)
    return CRI_network(axons=axons,
                       connections={'n0': ([], model)},
                       outputs=['n0'], target='CRI')


def step(net, ax=None):
    try:
        return net.step(ax if ax else [])
    except Exception:
        return None


def readV(net):
    return sv(net.CRI.readMP([0])[0][3])


def report(name, got, want, note=""):
    ok = (got == want)
    results[name] = ok
    print("  %-28s %s" % (name, "PASS" if ok else "FAIL"))
    print("      got    %s" % (got,))
    print("      expect %s" % (want,))
    if note:
        print("      %s" % note)
    print()
    return ok


def banner(t):
    print("=" * 70)
    print(t)
    print("=" * 70)


# --------------------------------------------------------------------------
def t_excitatory():
    banner("1. EXPONENTIAL PSC - excitatory (regression)")
    net = net_with({'a0': [('n0', 1000)]}, threshold=50000)
    cfg()
    want = [0]
    i = 1000
    for s in range(6):
        i = (i * DEC) >> 12
        want.append(i)
    got = []
    for s in range(7):
        step(net, ['a0'] if s == 0 else [])
        got.append(readV(net))
    report("excitatory PSC decay", got, want,
           "V should decay as floor(I_ex*3900/4096) each step")


def t_inhibitory():
    banner("2. INHIBITORY PSC - negative weight routes to I_in")
    net = net_with({'a0': [('n0', -500)]}, threshold=50000)
    cfg()
    want = [0]
    i = -500
    for s in range(5):
        i = (i * DEC) >> 12
        want.append(i)
    got = []
    for s in range(6):
        step(net, ['a0'] if s == 0 else [])
        got.append(readV(net))
    report("inhibitory PSC decay", got, want,
           "negative weight -> I_in, V must go NEGATIVE")


def t_mixed():
    banner("3. MIXED exc + inh on the same neuron")
    net = net_with({'a0': [('n0', 1000)], 'a1': [('n0', -400)]}, threshold=50000)
    cfg()
    want = [0]
    e, h = 1000, -400
    for s in range(5):
        e = (e * DEC) >> 12
        h = (h * DEC) >> 12
        want.append(e + h)
    got = []
    for s in range(6):
        step(net, ['a0', 'a1'] if s == 0 else [])
        got.append(readV(net))
    report("mixed exc+inh summation", got, want,
           "I_ex and I_in decay independently, both added to V")


def t_coba():
    banner("4. COBA - conductance mode, drive scales with (E_ex - V)")
    net = net_with({'a0': [('n0', 1000)]}, threshold=50000)
    E_EX = 2000
    cfg(coba_mode=1, E_ex=E_EX, E_in=0)
    want, V, g = [], 0, 1000
    for s in range(6):
        if s == 0:
            want.append(0)
        else:
            g = (g * DEC) >> 12
            drive = (g * (E_EX - (V & 0xFFF))) >> 12
            V = V + drive
            want.append(V)
    got = []
    for s in range(6):
        step(net, ['a0'] if s == 0 else [])
        got.append(readV(net))
    cfg()
    report("COBA shunting drive", got, want,
           "V rises toward E_ex=%d with shrinking increments (CUBA would "
           "decay instead)" % E_EX)


def t_refractory():
    banner("5. REFRACTORY PERIOD - spike train with vs without")
    trains = {}
    for rmax in (0, 3):
        net = net_with({'a0': [('n0', 1000)]}, threshold=300, refractory_max=rmax)
        cfg()
        train = []
        for s in range(8):
            sp = step(net, ['a0'])
            train.append(0 if sp is None else (1 if len(sp[0]) else 0))
        trains[rmax] = train
        print("      refractory_max=%d -> spikes %s" % (rmax, train))
    print()
    ok = trains[0] != trains[3]
    results["refractory period"] = ok
    print("  %-28s %s" % ("refractory period", "PASS" if ok else "FAIL"))
    print("      refractory_max=3 must suppress spikes that fire at rmax=0")
    if not ok:
        print("      identical trains -> refractory_max is not reaching the FPGA")
    print()


def t_adaptation():
    banner("6. AdEx ADAPTATION - w builds on spikes and suppresses firing")
    trains = {}
    for dw in (0, 255):
        net = net_with({'a0': [('n0', 1000)]}, threshold=800)
        cfg(decay_w=250, delta_w=dw)
        train = []
        for s in range(8):
            sp = step(net, ['a0'])
            train.append(0 if sp is None else (1 if len(sp[0]) else 0))
        trains[dw] = train
        print("      delta_w=%-3d -> spikes %s" % (dw, train))
    cfg()
    print()
    ok = sum(trains[255]) < sum(trains[0])
    results["AdEx adaptation"] = ok
    print("  %-28s %s" % ("AdEx adaptation", "PASS" if ok else "FAIL"))
    print("      delta_w=255 must produce FEWER spikes than delta_w=0")
    print()


def t_neuromod():
    banner("7. NEUROMODULATION - excitability bias shifts threshold")
    # effective_threshold = threshold - neuromod_excitability_bias
    # drive peaks at 952, so threshold 1000 gives no spike; bias +200 -> 800 -> spike
    trains = {}
    for bias in (0, 200):
        net = net_with({'a0': [('n0', 1000)]}, threshold=1000)
        cfg(neuromod_excitability_bias=bias)
        train = []
        for s in range(5):
            sp = step(net, ['a0'])
            train.append(0 if sp is None else (1 if len(sp[0]) else 0))
        trains[bias] = train
        print("      bias=%-4d -> spikes %s" % (bias, train))
    cfg()
    print()
    ok = sum(trains[200]) > sum(trains[0])
    results["neuromodulation bias"] = ok
    print("  %-28s %s" % ("neuromodulation bias", "PASS" if ok else "FAIL"))
    print("      effective_threshold = threshold - bias, so +bias fires MORE")
    print("      (note: the port comment says '+ = harder to fire' - the RTL")
    print("       does the opposite; the comment is wrong, not the logic)")
    print()


for fn in (t_excitatory, t_inhibitory, t_mixed, t_coba,
           t_refractory, t_adaptation, t_neuromod):
    try:
        fn()
    except Exception:
        name = fn.__name__
        results[name] = False
        print("  %s raised:" % name)
        traceback.print_exc()
        print()

dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                       64, 1, 0, 0, 0, dmadump.DmaMethodNormal)

banner("SUMMARY")
for k, v in results.items():
    print("  %-28s %s" % (k, "PASS" if v else "FAIL"))
print()
print("  NOT TESTED - soft reset: soft_reset_en_param reads")
print("  dout_neuron_param_mem[8], but nothing in the software packs bit 8.")
print("  Unreachable until write_neuron_type sets it. RTL path exists.")
print()
print("  NOT TESTED - STDP, per-synapse delay, per-axon delay: all require")
print("  the 64-bit synapse format and/or w_delay_table_wr, which is tied")
print("  to 1'b0 in single_core.v.")
print("=" * 70)
