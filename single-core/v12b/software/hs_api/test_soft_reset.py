#!/usr/bin/env python3
"""
ITEM A verification -- soft reset.

RTL behaviour on spike:
    soft_reset_en=0 (hard):  MP <- 0
    soft_reset_en=1 (soft):  MP <- MP_new - threshold

With leak=0 the next Phase 0 recomputes V from scratch (V - (V>>0) = 0), so the
soft-reset residual is wiped one timestep later.  It must therefore be read in
the SAME step as the spike.

  threshold 500, weight 1000, decay_ex 3900
  step 1: Phase 2 loads I_ex = 1000, V still 0
  step 2: drive = 952 > 500 -> SPIKE
             hard reset -> V = 0
             soft reset -> V = 952 - 500 = 452

  cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_soft_reset.py
"""

import sys, traceback
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

DEC, W, TH = 3900, 1000, 500
DRIVE = (W * DEC) >> 12                      # 952
EXPECT = {False: 0, True: DRIVE - TH}        # hard 0, soft 452


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


print("drive at step 2 = %d, threshold = %d" % (DRIVE, TH))
print("expect  hard reset -> V = %d      soft reset -> V = %d\n"
      % (EXPECT[False], EXPECT[True]))

ok = True
for soft in (False, True):
    try:
        model = ANN_neuron(threshold=TH, shift=-17, leak=0, soft_reset_en=soft)
    except TypeError:
        print("  ANN_neuron has no soft_reset_en argument yet.")
        print("  Run enable_soft_reset.py first, and wire the call site.")
        sys.exit(1)

    net = CRI_network(axons={'a0': [('n0', W)]},
                      connections={'n0': ([], model)},
                      outputs=['n0'], target='CRI')
    # zero Row B so the drive is exactly one weight
    cfg(decay_ex=0, decay_in=0)
    for _ in range(8):
        step(net)
    cfg()

    step(net, ['a0'])                    # step 1: accumulate I_ex
    step(net)                            # step 2: drive crosses threshold
    v = sv(net.CRI.readMP([0])[0][3])
    good = (v == EXPECT[soft])
    ok &= good
    print("  soft_reset_en=%-5s -> V = %-6d (expect %d)  %s"
          % (soft, v, EXPECT[soft], "PASS" if good else "FAIL"))

dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                       64, 1, 0, 0, 0, dmadump.DmaMethodNormal)

print("\n%s" % ("PASS - soft reset works, 8 of 8 neuron-model features complete."
                if ok else
                "FAIL - if BOTH read 0, bit 8 is still not reaching the FPGA;\n"
                "       check the write_neuron_type call site passes soft_reset_en."))
