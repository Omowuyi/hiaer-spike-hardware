#!/usr/bin/env python3
"""
Which neurons fail to accumulate their axon weight around row 512?

test_max_number_axons[10000] now fails at N1.8196 (row 512, group 4) with
MP=0 instead of 1.  Neurons 8192-8195 (groups 0-3) passed, so it is a PARTIAL
row failure -- not the whole row.  That is a different signature from the FIX K
spike loss and needs mapping before it can be diagnosed.

Reproduces the test's setup exactly (one axon per neuron, weight 1,
ANN_neuron threshold 0 shift -17) but reports EVERY mismatch across the
boundary instead of stopping at the first.

  cd /home/omowuyi/testing/hs_api/tests
  source ../.venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 diag_boundary_accum.py
"""

import sys
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron

N = 10000            # same as the failing parametrisation
LO, HI = 8176, 8240  # rows 511..514, a little either side
GROUPS = 16

axons = {"A%d" % i: [("N1.%d" % i, 1)] for i in range(N)}
model = ANN_neuron(0, shift=-17)
connections = {"N1.%d" % i: ([], model) for i in range(N)}
watch = ["N1.%d" % i for i in range(LO, HI)]

print("building network: %d axons, %d neurons" % (N, N))
net = CRI_network(axons=axons, connections=connections,
                  outputs=watch, target="CRI")

net.step(["A%d" % i for i in range(N)])          # timestep 0: all axons fire
mp = net.read_membrane(watch)
mp = dict(mp) if isinstance(mp[0], tuple) else dict(zip(watch, mp))

print()
print("  neuron   row  grp   MP   expected 1")
print("  " + "-" * 40)
bad_by_row = {}
for i in range(LO, HI):
    n = "N1.%d" % i
    row, grp = i // GROUPS, i % GROUPS
    v = mp[n]
    flag = "" if v == 1 else "   <-- MISMATCH"
    if v != 1:
        bad_by_row.setdefault(row, []).append(grp)
    print("  %-8d %-4d %-4d %-4d%s" % (i, row, grp, v, flag))

print()
print("=" * 52)
if not bad_by_row:
    print("no mismatches in this range")
else:
    for row in sorted(bad_by_row):
        g = bad_by_row[row]
        print("  row %d : groups %s  (%d of 16)" % (row, g, len(g)))
    print()
    rows = sorted(bad_by_row)
    if rows == [512] and len(bad_by_row[512]) == GROUPS:
        print("ENTIRE row 512 fails -> the row is not being written at all")
    elif rows == [512]:
        print("PARTIAL row 512 -> only some groups. The failing group list")
        print("is the diagnostic: contiguous from 4 suggests a pipeline")
        print("depth, scattered suggests something else.")
    else:
        print("Failure spans rows %s -- not confined to the boundary." % rows)
print("=" * 52)
