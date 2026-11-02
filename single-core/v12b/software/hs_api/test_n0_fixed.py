# Hardware test of the fix: n0 synapse placed at entry7 (correct slot), full 64-byte row.
# Expect: I_ex ~1000 after step1, V nonzero after step2.  Reflash first for clean control.
import sys, numpy as np
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.FPGA_Execution.fpga_controller import SYN_BASE_ADDR, read_address_packet
from hs_api.single_core_conductance_STDP import build_cmd13_packet

def entry64(op,dest,weight,delay=0,syn_type=0,stdp_tag=0,src=0):
    return (((op&0x7)<<61)|((dest&0x1FFF)<<48)|((weight&0xFFFF)<<32)
            |((delay&0x3F)<<26)|((syn_type&0xF)<<22)|((stdp_tag&0xF)<<18)|(src&0x3FFFF))
def pack_row_64bit(entries_by_group):
    ent=[0]*8
    for g,val in entries_by_group.items(): ent[7-g]=val
    b=[]
    for e in ent: b+=[(int(e)>>(8*(7-k)))&0xFF for k in range(8)]
    return b
def write_row_64bit(r, entries_by_group, coreID=0):
    data=pack_row_64bit(entries_by_group)
    a='1'+np.binary_repr(SYN_BASE_ADDR+r,23)
    cmd=[2,coreID]+[0]*27+[int(a[:8],2),int(a[8:16],2),int(a[16:],2)]+data
    return dmadump.dma_dump_write(np.flip(np.array(cmd,dtype=np.uint64)),len(cmd),1,0,0,0,dmadump.DmaMethodNormal)
def sv(v): v=int(v)&0xFFFFFFFF; return v-0x100000000 if v>=0x80000000 else v
def ruram(row,col,c=0,t=4000):
    cb=np.binary_repr(c,5)+'000'; tl=np.array([0]*55+[int(cb,2),3],dtype=np.uint64)
    dmadump.dma_dump_write(np.concatenate([read_address_packet(row=row,col=col),tl]),62,1,0,0,0,dmadump.DmaMethodNormal)
    for _ in range(t):
        ec,d=dmadump.dma_dump_read(1,0,0,0,dmadump.DmaMethodNormal,64)
        if int(d[62])==204 and int(d[63])==204: return [int(x) for x in d]
    return None
def iex(p):
    if p is None: return None
    d=np.flip(np.array(p,dtype=np.uint64)); b=''.join(np.binary_repr(int(i),8) for i in d)
    v=int(b[-72:],2); x=(v>>24)&0xFFF; return x-4096 if x>=2048 else x

model=ANN_neuron(threshold=1000000,shift=-17,leak=0)
net=CRI_network(axons={'a0':[('n0',1000)]},connections={'n0':([],model)},outputs=['n0'],target='CRI')
net.step(['a0']); cv=sv(net.read_membrane(['n0'])[0][1]); print("CONTROL V =",cv)
assert cv==1000,"reflash and rerun"
r=net.CRI.readMP([net.connectome.get_neuron_by_key('n0').get_hbmIdx()]); nr,nc=int(r[0][1]),int(r[0][2])

# n0 = group 0 -> entry7. Full 64-byte row. Write to the row a0's pointer fetches (row 1) and clear its pair (row 0).
write_row_64bit(1, {0: entry64(0, dest=0, weight=1000)})
write_row_64bit(0, {})   # full zero row

dmadump.dma_dump_write(build_cmd13_packet(delta_mode=0,decay_ex=3900,decay_in=3900,coba_mode=0,stdp_enable=0,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
net.step(['a0']); print("I_ex after step1 =", iex(ruram(nr+4096,nc)))
print("V after step1 =", sv(net.read_membrane(['n0'])[0][1]))
net.step([]); print("V after step2 =", sv(net.read_membrane(['n0'])[0][1]))
dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1,coreID=0),64,1,0,0,0,dmadump.DmaMethodNormal)
print("restored")
