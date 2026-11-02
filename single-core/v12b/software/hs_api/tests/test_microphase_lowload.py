#!/usr/bin/env python3
"""
Does microphase 1 lose spikes, with the readout NOT overloaded?

WHY A SECOND TEST
test_microphase_scope.py drove all 10000 neurons to spike in one timestep and
lost 1811 of them -- 504 in microphase 0, which cannot be a microphase bug.
8189 reported is suspiciously close to 8192 = 2^13, and the loss pattern
(rows 0-255 clean, then progressively worse) is a FIFO filling up.  That is
hbm_processor's `!spk*_full` silent discard, a real defect but a different
one, and it masks whatever the microphase path is doing.

This drives only 14 neurons, spread across both microphases.  Fourteen spikes
in a timestep cannot overflow anything, so any loss is the microphase effect
alone.

The network is still 10000 neurons so the microphase structure is identical:

    10016 neurons -> URAM_ADDR_LIMIT 626
    microphase 0 : rows 0-511    neurons 0-8191
    microphase 1 : rows 512-626  neurons 8192-9999

Probes include 8720 -- C1.9.620, row 545 -- which is the neuron Christopher's
in-depth test finds missing on hardware but present in the simulator.

  cd /home/omowuyi/testing/hs_api/tests
  source ../.venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_microphase_lowload.py
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron

N = 10000
GROUPS = 16
BOUNDARY = 512 * GROUPS          # 8192

PROBES = [
    (100,  "microphase 0, early"),
    (1000, "microphase 0"),
    (3000, "microphase 0"),
    (5120, "microphase 0, group 0 -- passes in the in-depth test"),
    (7000, "microphase 0"),
    (8000, "microphase 0"),
    (8191, "microphase 0, LAST neuron before the boundary"),
    (8192, "microphase 1, FIRST neuron -- the boundary row"),
    (8204, "microphase 1 -- C1.9.104, fails in the spikes test"),
    (8300, "microphase 1"),
    (8720, "microphase 1 -- C1.9.620, fails in the in-depth test"),
    (9000, "microphase 1"),
    (9500, "microphase 1"),
    (9999, "microphase 1, last"),
]


class Timeout(Exception):
    pass


def _alarm(sig, frm):
    raise Timeout("exceeded wall-clock budget")


signal.signal(signal.SIGALRM, _alarm)

try:
    signal.alarm(900)

    idxs = [i for i, _ in PROBES]
    print("network: %d neurons, all wired; only %d axons FIRED\n" % (N, len(idxs)))

    # The network must be built exactly as the full-load test builds it.  A
    # neuron only gets a spike entry allocated in its HBM rows if it is a
    # synapse target and appears in outputs; wiring only the probes left them
    # with no rows, so none could report and the first run showed zero spikes
    # even in microphase 0.  Build everything, then fire only the probes.
    axons = {"A%d" % i: [("N%d" % i, 1)] for i in range(N)}
    model = ANN_neuron(0, shift=-17)
    conns = {"N%d" % i: ([], model) for i in range(N)}
    net = CRI_network(axons=axons, connections=conns,
                      outputs=["N%d" % i for i in range(N)], target="CRI")

    net.step(["A%d" % i for i in idxs])      # t=0: only the probes reach MP=1
    spikes = net.step([])                     # t=1: all probes must spike
    if isinstance(spikes, tuple):
        spikes = spikes[0]
    fired = set(spikes)

    print("  neuron   row   grp  mp   spiked   note")
    print("  " + "-" * 70)
    mp0_lost = mp1_lost = mp0_tot = mp1_tot = 0
    for i, note in PROBES:
        row, grp = i // GROUPS, i % GROUPS
        mp = 0 if i < BOUNDARY else 1
        ok = ("N%d" % i) in fired
        if mp:
            mp1_tot += 1; mp1_lost += (not ok)
        else:
            mp0_tot += 1; mp0_lost += (not ok)
        print("  %-8d %-5d %-4d %-3d %-8s %s"
              % (i, row, grp, mp, "yes" if ok else "NO", note))

    print()
    print("  microphase 0 : %d of %d lost" % (mp0_lost, mp0_tot))
    print("  microphase 1 : %d of %d lost" % (mp1_lost, mp1_tot))
    print()
    print("=" * 70)
    if mp1_lost == mp1_tot and mp0_lost == 0:
        print("CONFIRMED: microphase 1 reports NO spikes at all, microphase 0 is")
        print("clean.  The defect is microphase-1 spike reporting as a whole --")
        print("roughly %d neurons in this network, not 16.  Every fix aimed at" % (N - BOUNDARY))
        print("row 512 alone was far too narrow.")
    elif mp1_lost and mp0_lost == 0:
        print("PARTIAL: %d of %d microphase-1 probes lost, microphase 0 clean."
              % (mp1_lost, mp1_tot))
        print("The pattern of which ones survive is the next clue.")
    elif mp0_lost == 0 and mp1_lost == 0:
        print("NO LOSS at low spike load.  So the microphase path is fine and the")
        print("earlier losses were ALL readout overflow -- which makes the spike")
        print("FIFO the real target, not the microphase logic.")
    else:
        print("Loss in BOTH microphases (%d and %d) even at low load."
              % (mp0_lost, mp1_lost))
    print("=" * 70)

except Timeout as e:
    print("\nABORTED: %s" % e)
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
    try:
        import hs_bridge.wrapped_dmadump.dmadump as d
        from hs_api.single_core_conductance_STDP import build_cmd13_packet
        d.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                         64, 1, 0, 0, 0, d.DmaMethodNormal)
    except Exception:
        pass
