#!/usr/bin/env python3
# Minimal single-feature validation for the exec_uram_phase1_done=1@PUSH bitstream.
# Basic excitatory PSC from a CLEAN baseline. If V evolves, the phase fix works end-to-end.
#
# Run AFTER flashing the phase-fix bitstream:
#   cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
#   export PYTHONPATH=/home/omowuyi/testing/hs_bridge
#   python3 test_exp_basic.py

import sys, numpy as np
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v

def readV(net):
    return sv(net.CRI.readMP([net.connectome.get_neuron_by_key('n0').get_hbmIdx()])[0][3])


model = ANN_neuron(threshold=500, shift=-17, leak=0)
net = CRI_network(axons={'a0': [('n0', 1000)]},
                  connections={'n0': ([], model)},
                  outputs=['n0'], target='CRI')

# clean baseline: spike then reset -> V returns to 0
net.step(['a0']); print("delta spike:      V =", readV(net))
net.step([]);     print("cleared baseline: V =", readV(net))

# switch to exp_psc (delta_mode=0). The network's own 32-bit synapse write already places
# n0's weight at the exp_psc group-0 read position [495:480].
dmadump.dma_dump_write(
    build_cmd13_packet(delta_mode=0, decay_ex=3900, decay_in=3900,
                       coba_mode=0, stdp_enable=0, coreID=0),
    64, 1, 0, 0, 0, dmadump.DmaMethodNormal)
print("baseline before exp:", readV(net))

for i in range(1, 8):
    try:
        net.step(['a0'] if i == 1 else [])
    except Exception as e:
        print(f"  step{i}: spiked (crash {type(e).__name__})")
    print(f"exp_psc step{i}: V = {readV(net)}")

# restore delta mode
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                       64, 1, 0, 0, 0, dmadump.DmaMethodNormal)
