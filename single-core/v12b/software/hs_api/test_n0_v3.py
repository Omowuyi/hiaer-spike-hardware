# exp_psc packing v3: weight placed at row bytes 2-3 (= IEP group0 read position [495:480]),
# solved directly against the RTL read bits + the proven DMA flip framing. V-only (trustworthy).
import sys, numpy as np
sys.path.insert(0,'/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.FPGA_Execution.fpga_controller import SYN_BASE_ADDR
from hs_api.single_core_conductance_STDP import build_cmd13_packet
def sv(v): v=int(v)&0xFFFFFFFF; return v-0x100000000 if v>=0x80000000 else v

# exp_psc weight read positions (group -> row byte where weight MSB lands, pre-flip data index = 31-rowbyte)
_WT_HI={0:495,1:431,2:367,3:303}
def _wt_row_bytes(hi):
    r=hi-256; b=(255-r)//8; return b,b+1
def pack_exp_row(entries_by_group):
    data=[0]*32
    for g,(dest,weight) in entries_by_group.items():
        b2,b3=_wt_row_bytes(_WT_HI[g]); w=int(weight)&0xFFFF
        data[31-b2]=(w>>8)&0xFF; data[31-b3]=w&0xFF
    return data
def wr(r,ebg,c=0):
    a='1'+np.binary_repr(SYN_BASE_ADDR+r,23)
    cmd=[2,c]+[0]*27+[int(a[:8],2),int(a[8:16],2),int(a[16:],2)]+pack_exp_row(ebg)
    return dmadump.dma_dump_write(np.flip(np.array(cmd,dtype=np.uint64)),len(cmd),1,0,0,0,dmadump.DmaMethodNormal)

# n0 fetched via a0 pointer (rows 0,1). n0 = row1 col0 = group0. Write row1 group0, clear row0.
model=ANN_neuron(threshold=500,shift=-17,leak=0)
net=CRI_network(axons={'a0':[('n0',1000)]},connections={'n0':([],model)},outputs=['n0'],target='CRI')
net.step(['a0']); print("delta spike step V=",sv(net.read_membrane(['n0'])[0][1]))
net.step([]); base=sv(net.read_membrane(['n0'])[0][1]); print("cleared baseline V=",base)

wr(1,{0:(0,1000)}); wr(0,{})
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=0,decay_ex=3900,decay_in=3900,coba_mode=0,stdp_enable=0,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
for i in range(1,6):
    net.step(['a0'] if i==1 else [])
    print(f"exp_psc step{i}: V =", sv(net.read_membrane(['n0'])[0][1]))
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
