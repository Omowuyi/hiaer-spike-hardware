# CORRECT 64-bit packing, derived from the actual _cmd_to_uint64_array byte convention
# (dout bit B = finalCmd[B//8] bit B%8). Entry = 8 bytes MSB-first at group position.
# Verified: weight/dest/delay/stdp_tag/src ALL land at exp_psc RTL read positions.
import sys, numpy as np
sys.path.insert(0,'/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.FPGA_Execution.fpga_controller import SYN_BASE_ADDR
from hs_api.single_core_conductance_STDP import build_cmd13_packet
def sv(v): v=int(v)&0xFFFFFFFF; return v-0x100000000 if v>=0x80000000 else v
def entry64(op,dest,weight,delay=0,syn_type=0,stdp_tag=0,src=0):
    return (((op&7)<<61)|((dest&0x1FFF)<<48)|((weight&0xFFFF)<<32)|((delay&0x3F)<<26)|((syn_type&0xF)<<22)|((stdp_tag&0xF)<<18)|(src&0x3FFFF))
def pack_group(group_in_row, entry_val):
    data=[0]*32
    eb=[(entry_val>>(8*(7-b)))&0xFF for b in range(8)]  # MSB-first
    for k in range(8): data[group_in_row*8+k]=eb[k]
    return data
def wr(r, group, entry_val):
    data=pack_group(group, entry_val)
    a='1'+np.binary_repr(SYN_BASE_ADDR+r,23)
    cmd=[2,0]+[0]*27+[int(a[:8],2),int(a[8:16],2),int(a[16:],2)]+data
    return dmadump.dma_dump_write(np.flip(np.array(cmd,dtype=np.uint64)),len(cmd),1,0,0,0,dmadump.DmaMethodNormal)
def readV(net):
    r=net.CRI.readMP([net.connectome.get_neuron_by_key('n0').get_hbmIdx()]); return sv(int(r[0][3]))

model=ANN_neuron(threshold=500,shift=-17,leak=0)
net=CRI_network(axons={'a0':[('n0',1000)]},connections={'n0':([],model)},outputs=['n0'],target='CRI')
net.step(['a0']); print("delta spike: V=",readV(net))
net.step([]);     print("cleared baseline: V=",readV(net))

# n0 = group0. Write 64-bit entry to row1 group0, clear row0.
wr(1, 0, entry64(0, dest=0, weight=1000))
wr(0, 0, 0)
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=0,decay_ex=3900,decay_in=3900,coba_mode=0,stdp_enable=0,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
print("baseline before exp:",readV(net))
for i in range(1,7):
    try: net.step(['a0'] if i==1 else [])
    except Exception as e: print(f"  step{i}: spiked (crash {type(e).__name__})")
    print(f"exp_psc step{i}: V =", readV(net))
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
