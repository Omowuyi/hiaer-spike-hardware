#!/usr/bin/env python3
"""
Biological feature suite for exp_psc (delta_mode=0) -- v2.

Fixes over v1, all harness bugs rather than RTL:
  * STATE RESET between tests.  A new CRI_network does NOT clear URAM unless
    num_outputs/threshold/model/shift/leak change (uram_reinit_needed), so
    tests inherited the previous test's I_ex.  Reset by setting decay_ex=
    decay_in=decay_w=delta_w=0 and stepping: one Phase 0 then zeroes Row B.
  * neuromod_excitability_bias is 8-bit SIGNED.  v1 used 200, which is -56 --
    it made the neuron harder to fire, then asserted it would fire more.
  * I_ex is 12-bit signed (max 2047).  v1 applied the input EVERY step, driving
    I_ex to a steady state of ~20833 and overflowing it.  Input is now applied
    on step 0 only, and the spike tests watch the decaying drive cross the
    threshold.
  * AdEx: w is 8-bit and on spike becomes (w_dec + delta_w) TRUNCATED to 8
    bits.  decay_w=128, delta_w=120 keeps w at a stable 240 with no wrap.

Note: with leak=0, V_new = 0 - 0 + drive - w, so V does not accumulate --
it is the instantaneous drive.  Only Row B (I_ex, I_in, w) carries state.

  cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_bio_features2.py
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
    p = dict(delta_mode=0, decay_ex=DEC, decay_in=DEC, decay_w=0, delta_w=0,
             coba_mode=0, E_ex=0, E_in=0, neuromod_excitability_bias=0,
             stdp_enable=0, coreID=0)
    p.update(kw)
    dmadump.dma_dump_write(build_cmd13_packet(**p), 64, 1, 0, 0, 0,
                           dmadump.DmaMethodNormal)


def step(net, ax=None):
    try:
        return net.step(ax if ax else [])
    except Exception:
        return None


def readV(net):
    return sv(net.CRI.readMP([0])[0][3])


def reset_state(net):
    """Zero Row B (I_ex, I_in, w) and drain any refractory counter."""
    cfg(decay_ex=0, decay_in=0, decay_w=0, delta_w=0)
    for _ in range(8):
        step(net)
    return readV(net)


def mknet(axons, threshold, refractory_max=0):
    model = ANN_neuron(threshold=threshold, shift=-17, leak=0,
                       refractory_max=refractory_max)
    return CRI_network(axons=axons, connections={'n0': ([], model)},
                       outputs=['n0'], target='CRI')


def spikes_over(net, nsteps, first_input):
    """Apply input on step 0 only; return the spike train."""
    train = []
    for s in range(nsteps):
        sp = step(net, first_input if s == 0 else [])
        train.append(0 if sp is None else (1 if len(sp[0]) else 0))
    return train


def report(name, ok, detail=""):
    results[name] = ok
    print("  %-28s %s" % (name, "PASS" if ok else "FAIL"))
    if detail:
        print(detail)
    print()


def banner(t):
    print("=" * 70)
    print(t)
    print("=" * 70)


def trace_test(name, net, axon_keys, expect, note=""):
    base = reset_state(net)
    cfg()
    got = []
    for s in range(len(expect)):
        step(net, axon_keys if s == 0 else [])
        got.append(readV(net))
    ok = (got == expect)
    report(name, ok,
           "      after reset V = %d\n      got    %s\n      expect %s%s"
           % (base, got, expect, ("\n      " + note) if note else ""))


# --------------------------------------------------------------------------
def t_excitatory():
    banner("1. EXPONENTIAL PSC - excitatory")
    want = [0]
    i = 1000
    for _ in range(6):
        i = (i * DEC) >> 12
        want.append(i)
    trace_test("excitatory PSC decay", mknet({'a0': [('n0', 1000)]}, 50000),
               ['a0'], want)


def t_inhibitory():
    banner("2. INHIBITORY PSC - negative weight routes to I_in")
    want = [0]
    i = -500
    for _ in range(5):
        i = (i * DEC) >> 12
        want.append(i)
    trace_test("inhibitory PSC decay", mknet({'a0': [('n0', -500)]}, 50000),
               ['a0'], want, "V must go NEGATIVE")


def t_mixed():
    banner("3. MIXED exc + inh summation")
    want = [0]
    e, h = 1000, -400
    for _ in range(5):
        e = (e * DEC) >> 12
        h = (h * DEC) >> 12
        want.append(e + h)
    trace_test("mixed exc+inh summation",
               mknet({'a0': [('n0', 1000)], 'a1': [('n0', -400)]}, 50000),
               ['a0', 'a1'], want)


def t_coba():
    banner("4. COBA - drive scales with (E_ex - V)")
    E = 2000
    net = mknet({'a0': [('n0', 1000)]}, 50000)
    reset_state(net)
    cfg(coba_mode=1, E_ex=E)
    want, V, g = [0], 0, 1000
    for _ in range(5):
        g = (g * DEC) >> 12
        V = (g * (E - (V & 0xFFF))) >> 12
        want.append(V)
    got = []
    for s in range(6):
        step(net, ['a0'] if s == 0 else [])
        got.append(readV(net))
    cfg()
    report("COBA shunting drive", got == want,
           "      got    %s\n      expect %s\n"
           "      V climbs toward E_ex=%d with shrinking steps; CUBA decays"
           % (got, want, E))


def t_refractory():
    banner("5. REFRACTORY PERIOD")
    tr = {}
    for r in (0, 3):
        net = mknet({'a0': [('n0', 1000)]}, 500, refractory_max=r)
        reset_state(net)
        cfg()
        tr[r] = spikes_over(net, 16, ['a0'])
        print("      refractory_max=%d -> %s  (%d spikes)"
              % (r, tr[r], sum(tr[r])))
    print()
    report("refractory period", sum(tr[3]) < sum(tr[0]),
           "      rmax=3 must fire strictly fewer times than rmax=0")


def t_adaptation():
    banner("6. AdEx ADAPTATION")
    tr = {}
    for dw in (0, 120):
        net = mknet({'a0': [('n0', 1000)]}, 800)
        reset_state(net)
        cfg(decay_w=128, delta_w=dw)
        tr[dw] = spikes_over(net, 12, ['a0'])
        print("      delta_w=%-3d -> %s  (%d spikes)" % (dw, tr[dw], sum(tr[dw])))
    cfg()
    print()
    report("AdEx adaptation", sum(tr[120]) < sum(tr[0]),
           "      w builds on each spike and is subtracted from V,\n"
           "      so delta_w=120 must fire strictly fewer times")


def t_neuromod():
    banner("7. NEUROMODULATION - excitability bias")
    tr = {}
    for b in (0, 100):
        net = mknet({'a0': [('n0', 1000)]}, 800)
        reset_state(net)
        cfg(neuromod_excitability_bias=b)
        tr[b] = spikes_over(net, 12, ['a0'])
        print("      bias=%-4d -> %s  (%d spikes)" % (b, tr[b], sum(tr[b])))
    cfg()
    print()
    report("neuromodulation bias", sum(tr[100]) > sum(tr[0]),
           "      effective_threshold = threshold - bias, so +bias fires MORE\n"
           "      (the port comment says '+ = harder to fire'; the RTL does the\n"
           "       opposite -- the comment is wrong, not the logic)")


for fn in (t_excitatory, t_inhibitory, t_mixed, t_coba,
           t_refractory, t_adaptation, t_neuromod):
    try:
        fn()
    except Exception:
        results[fn.__name__] = False
        print("  %s raised:" % fn.__name__)
        traceback.print_exc()
        print()

dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                       64, 1, 0, 0, 0, dmadump.DmaMethodNormal)

banner("SUMMARY")
for k, v in results.items():
    print("  %-28s %s" % (k, "PASS" if v else "FAIL"))
print()
print("=" * 70)
