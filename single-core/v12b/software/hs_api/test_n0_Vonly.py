# V-only confirmation (no unreliable HBM/Row-B readback). Uses read_membrane (Row A, trustworthy).
# n0 packed at entry 7 (bytes 60-61 = IEP exp_psc read position, derived from the working 32-bit path).
# Clears stale membrane first, then runs exp_psc steps and watches V evolve.
import sys, numpy as np
sys.path.insert(0,'/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.FPGA_Execution.fpga_controller import SYN_BASE_ADDR
from hs_api.single_core_conductance_STDP import build_cmd13_packet
def sv(v): v=int(v)&0xFFFFFFFF; return v-0x100000000 if v>=0x80000000 else v
def entry64(op,dest,weight): return ((op&7)<<61)|((dest&0x1FFF)<<48)|((weight&0xFFFF)<<32)
def pack(ebg):
    ent=[0]*8
    for g,v in ebg.items(): ent[7-g]=v         # group g -> entry (7-g). n0->entry7->bytes60-61
    b=[]
    for e in ent: b+=[(int(e)>>(8*(7-k)))&0xFF for k in range(8)]
    return b
def wr(r,ebg,c=0):
    a='1'+np.binary_repr(SYN_BASE_ADDR+r,23)
    cmd=[2,c]+[0]*27+[int(a[:8],2),int(a[8:16],2),int(a[16:],2)]+pack(ebg)
    return dmadump.dma_dump_write(np.flip(np.array(cmd,dtype=np.uint64)),len(cmd),1,0,0,0,dmadump.DmaMethodNormal)

model=ANN_neuron(threshold=1000000,shift=-17,leak=0)
net=CRI_network(axons={'a0':[('n0',1000)]},connections={'n0':([],model)},outputs=['n0'],target='CRI')
# control (delta): confirms path + establishes we can read V
net.step(['a0']); cv=sv(net.read_membrane(['n0'])[0][1]); print("CONTROL (delta) V =",cv); assert cv==1000,"reflash"

# write n0 synapse in 64-bit format at entry7; clear the pair row
wr(1,{0:entry64(0,0,1000)}); wr(0,{})

# switch to exp_psc, then run several steps WITH NO delta interference, watching V
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=0,decay_ex=3900,decay_in=3900,coba_mode=0,stdp_enable=0,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
for i in range(1,6):
    net.step(['a0'] if i==1 else [])
    print(f"exp_psc step{i}: V =", sv(net.read_membrane(['n0'])[0][1]))
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
print("restored delta")
