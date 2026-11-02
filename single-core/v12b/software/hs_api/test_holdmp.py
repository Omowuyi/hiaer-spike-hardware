#!/usr/bin/env python3
# Does TX_STATE_HOLD_MP make readMP return stale data in exp_psc mode?
#
# The MP packet echoes back the neuron address that produced it
# (iep2ci_din = {SET_GROUP_reg, SET_ROW_reg, data}), and read_membranes
# decodes it as tuple[0]. So we can check whether the response we get back
# is the one we asked for -- this works even though V is 0 everywhere,
# because the address does not come from the neuron data.
#
# Run on the CURRENT bitstream. No rebuild needed.
#   cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
#   export PYTHONPATH=/home/omowuyi/testing/hs_bridge
#   python3 test_holdmp.py

import sys
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

N = 64                      # 64 neurons -> URAM rows 0..3 (16 neurons per row)
PROBE = [0, 16, 32, 48]     # one neuron in each of 4 different rows


def set_mode(delta):
    dmadump.dma_dump_write(
        build_cmd13_packet(delta_mode=delta, decay_ex=3900, decay_in=3900,
                           coba_mode=0, stdp_enable=0, coreID=0),
        64, 1, 0, 0, 0, dmadump.DmaMethodNormal)


def step(net, axons=None):
    try:
        net.step(axons if axons else [])
    except Exception as e:
        print("    (step raised %s -- ignored)" % type(e).__name__)


def check(label, requested, returned):
    """returned = list of readMP tuples (index, row, col, mp)"""
    ok = True
    print("  %s" % label)
    for want, got in zip(requested, returned):
        got_idx, got_row, got_col = got[0], got[1], got[2]
        match = (got_idx == want)
        ok &= match
        print("      asked n%-3d (row %d col %2d)  ->  got n%-3d (row %d col %2d)  %s"
              % (want, want // 16, want % 16, got_idx, got_row, got_col,
                 "ok" if match else "<-- MISMATCH"))
    return ok


print("building %d-neuron network..." % N)
model = ANN_neuron(threshold=500, shift=-17, leak=0)
net = CRI_network(axons={'a0': [('n0', 1000)]},
                 connections={('n%d' % i): ([], model) for i in range(N)},
                 outputs=['n%d' % i for i in range(N)], target='CRI')

idx = {i: net.connectome.get_neuron_by_key('n%d' % i).get_hbmIdx() for i in range(N)}
probe = [idx[i] for i in PROBE]
print("hbmIdx for n%s = %s" % (PROBE, probe))
print()

results = {}
for mode_name, delta in (("delta_mode=1  (CONTROL)", 1), ("delta_mode=0  (exp_psc)", 0)):
    print("=" * 68)
    print(mode_name)
    print("=" * 68)
    set_mode(delta)
    step(net, ['a0'])          # exec_run_done -> sets execution_started
    step(net)

    a = check("A) one readMP call, 4 neurons:", probe, net.CRI.readMP(probe))
    b = check("B) same call again:", probe, net.CRI.readMP(probe))

    print("  C) four separate readMP calls:")
    c = True
    for p in probe:
        got = net.CRI.readMP([p])[0]
        match = (got[0] == p)
        c &= match
        print("      asked n%-3d  ->  got n%-3d (row %d col %2d)  %s"
              % (p, got[0], got[1], got[2], "ok" if match else "<-- MISMATCH"))
    results[delta] = (a, b, c)
    print()

set_mode(1)   # restore delta mode

print("=" * 68)
print("VERDICT")
print("=" * 68)
d1, d0 = results[1], results[0]
print("  delta_mode=1 : A=%s B=%s C=%s" % d1)
print("  delta_mode=0 : A=%s B=%s C=%s" % d0)
print()
if all(d0):
    print("  All exp_psc responses matched the request.")
    print("  -> TX_STATE_HOLD_MP is HARMLESS. Do NOT edit command_interpreter.v.")
    print("     Rebuild with the fixed internal_events_processor.v only.")
elif all(d1) and not all(d0):
    print("  exp_psc returned the wrong neuron; delta_mode did not.")
    print("  -> TX_STATE_HOLD_MP IS causing stale reads. Delete this line in")
    print("     command_interpreter.v (TX_STATE_IDLE, ~line 980):")
    print("       if (execution_started && !delta_mode) tx_next_state = TX_STATE_HOLD_MP;")
    print("     and rebuild both files.")
else:
    print("  Mismatches in BOTH modes -- readMP addressing is unreliable")
    print("  independently of HOLD_MP. Send me this output before rebuilding.")
