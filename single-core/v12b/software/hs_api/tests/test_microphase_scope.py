#!/usr/bin/env python3
"""
Is the spike loss confined to the boundary row, or does it span all of
microphase 1?

WHY THIS TEST
The earlier boundary test reported row 512: 7 lost, row 513: 0 lost -- and the
row-513 result was VACUOUS.  Zero reported AND zero lost means no row-513
neuron ever crossed threshold, so that row was never actually tested.  Reading
it as "row 513 is fine" sent nine fix attempts after a one-row skip.

Christopher's in-depth test fails at C1.9.620 = hbmIdx 8720 = row 545, which
is in microphase 1 but is NOT the boundary row.  Every neuron that fired
correctly in that test is in rows 38-488, all microphase 0.  That points at
the whole of microphase 1 rather than its first row.

METHOD -- non-vacuous by construction
10000 axons, axon i -> neuron i, weight 1, ANN neuron with threshold 0.
Fire every axon at t=0.  Every neuron reaches MP=1, and at t=1 EVERY neuron
must spike.  No neuron can be silently untested.

    10016 neurons -> URAM_ADDR_LIMIT 626
    microphase 0 : rows 0-511    neurons 0-8191
    microphase 1 : rows 512-626  neurons 8192-9999

If the loss is a one-row skip, only neurons 8192-8207 go missing.
If it spans microphase 1, everything from 8192 up goes missing.

SAFETY
Bounded: a SIGALRM hard stop, and only network.step() is used -- no
read_membrane, which is where previous runs spun.  Restores delta_mode on
exit, including on exception.

  cd /home/omowuyi/testing/hs_api/tests
  source ../.venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_microphase_scope.py
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron

N = 10000
GROUPS = 16
BOUNDARY_ROW = 512
BOUNDARY_NEURON = BOUNDARY_ROW * GROUPS          # 8192


class Timeout(Exception):
    pass


def _alarm(sig, frm):
    raise Timeout("exceeded wall-clock budget")


signal.signal(signal.SIGALRM, _alarm)


def build():
    axons = {"A%d" % i: [("N%d" % i, 1)] for i in range(N)}
    model = ANN_neuron(0, shift=-17)
    conns = {"N%d" % i: ([], model) for i in range(N)}
    outs = ["N%d" % i for i in range(N)]
    return CRI_network(axons=axons, connections=conns, outputs=outs, target="CRI")


results = {}
try:
    signal.alarm(900)

    print("building: %d axons -> %d neurons, weight 1, threshold 0" % (N, N))
    print("microphase 0 = neurons 0..%d, microphase 1 = neurons %d..%d\n"
          % (BOUNDARY_NEURON - 1, BOUNDARY_NEURON, N - 1))
    net = build()

    net.step(["A%d" % i for i in range(N)])       # t=0: every neuron reaches MP=1
    spikes = net.step([])                          # t=1: every neuron must spike
    if isinstance(spikes, tuple):
        spikes = spikes[0]
    fired = set(spikes)
    print("spikes reported at t=1: %d of %d expected\n" % (len(fired), N))

    missing = [i for i in range(N) if ("N%d" % i) not in fired]
    results["missing"] = missing

    # per-row tally, only for rows that have neurons
    print("  row range        neurons   missing   verdict")
    print("  " + "-" * 52)
    bands = [(0, 255), (256, 500), (501, 511), (512, 512),
             (513, 520), (521, 560), (561, 600), (601, 624)]
    for lo, hi in bands:
        n0, n1 = lo * GROUPS, min(hi * GROUPS + GROUPS - 1, N - 1)
        if n0 >= N:
            continue
        tot = n1 - n0 + 1
        miss = sum(1 for i in missing if n0 <= i <= n1)
        mp = 0 if hi < BOUNDARY_ROW else 1
        verdict = "all lost" if miss == tot else ("clean" if miss == 0 else "partial")
        print("  %4d-%-4d (mp%d)   %6d   %7d   %s" % (lo, hi, mp, tot, miss, verdict))

    print()
    mp0_miss = sum(1 for i in missing if i < BOUNDARY_NEURON)
    mp1_miss = sum(1 for i in missing if i >= BOUNDARY_NEURON)
    mp1_tot = N - BOUNDARY_NEURON
    print("  microphase 0 : %d of %d missing" % (mp0_miss, BOUNDARY_NEURON))
    print("  microphase 1 : %d of %d missing" % (mp1_miss, mp1_tot))
    print()
    print("=" * 60)
    if mp1_miss == mp1_tot and mp0_miss == 0:
        print("CONFIRMED: the ENTIRE microphase 1 loses spikes -- %d neurons," % mp1_tot)
        print("not 16.  The defect is microphase-1 spike reporting as a whole,")
        print("not a one-row skip.  Every fix aimed at row 512 was too narrow.")
    elif mp1_miss and mp0_miss == 0:
        print("PARTIAL: %d of %d microphase-1 neurons lose spikes, microphase 0" % (mp1_miss, mp1_tot))
        print("is clean.  Send me the per-row table -- the pattern within")
        print("microphase 1 is the diagnostic.")
    elif mp0_miss == 0 and mp1_miss == 0:
        print("NO LOSS -- every neuron reported.  If this build has FIX K, it")
        print("worked; if not, the loss needs a different trigger than this")
        print("uniform-drive pattern.")
    else:
        print("Loss is NOT confined to microphase 1 (%d missing in microphase 0)." % mp0_miss)
        print("Send me the per-row table.")
    print("=" * 60)

except Timeout as e:
    print("\nABORTED: %s -- kill any leftover pytest/python processes." % e)
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
    try:
        import numpy as np, hs_bridge.wrapped_dmadump.dmadump as d
        from hs_api.single_core_conductance_STDP import build_cmd13_packet
        d.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                         64, 1, 0, 0, 0, d.DmaMethodNormal)
    except Exception:
        pass
