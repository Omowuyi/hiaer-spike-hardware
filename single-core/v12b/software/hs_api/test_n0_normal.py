# n0 = group0. exp_psc group0 weight extraction [495:480]+guard[511] is BIT-IDENTICAL to
# delta entry0 (proven to work). So the NORMAL 32-bit synapse write should place n0's weight
# exactly where exp_psc reads it. NO repacking. Just switch delta->exp_psc and check V.
import sys, numpy as np
sys.path.insert(0,'/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet
def sv(v): v=int(v)&0xFFFFFFFF; return v-0x100000000 if v>=0x80000000 else v
def readV(net):
    r=net.CRI.readMP([net.connectome.get_neuron_by_key('n0').get_hbmIdx()]); return sv(int(r[0][3]))

# threshold 500 so we can clear baseline via spike/reset
model=ANN_neuron(threshold=500,shift=-17,leak=0)
net=CRI_network(axons={'a0':[('n0',1000)]},connections={'n0':([],model)},outputs=['n0'],target='CRI')
# The network's normal compile already wrote n0's synapse (weight 1000) in 32-bit format.
net.step(['a0']); print("delta spike: V=",readV(net))
net.step([]);     print("cleared baseline: V=",readV(net))

# Switch to exp_psc. DO NOT rewrite synapses - use what create_synapses already wrote.
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=0,decay_ex=3900,decay_in=3900,coba_mode=0,stdp_enable=0,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
print("baseline before exp:",readV(net))
for i in range(1,7):
    try: net.step(['a0'] if i==1 else [])
    except Exception as e: print(f"  step{i}: spiked (crash {type(e).__name__})")
    print(f"exp_psc step{i}: V =", readV(net))
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
