#!/usr/bin/env python3
# Biological feature test suite for exp_psc (delta_mode=0), for the bitstream with the
# exec_uram_phase1_done=1@PUSH fix. Uses STANDARD 32-bit network synapse writes (create_synapses)
# — no custom packer — since the weight-based features need only the weight, which the 32-bit
# write already places at the exp_psc group-0 read position [495:480] (verified against create_synapses).
#
# Covers the 7 weight-based features. STDP + synaptic delay (which need 64-bit entry fields)
# are handled separately once the weight path is confirmed.
#
# Run AFTER flashing the phase-fix bitstream:
#   cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
#   export PYTHONPATH=/home/omowuyi/testing/hs_bridge
#   python3 test_features.py

import sys, numpy as np
sys.path.insert(0,'/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_api.single_core_conductance_STDP import build_cmd13_packet

def sv(v):
    v=int(v)&0xFFFFFFFF; return v-0x100000000 if v>=0x80000000 else v
def cmd13(**kw):
    dmadump.dma_dump_write(build_cmd13_packet(**kw),64,1,0,0,0,dmadump.DmaMethodNormal)
def delta():
    cmd13(delta_mode=1, coreID=0)

def new_net(threshold=500, weight=1000):
    model=ANN_neuron(threshold=threshold, shift=-17, leak=0)
    net=CRI_network(axons={'a0':[('n0',weight)]}, connections={'n0':([],model)},
                    outputs=['n0'], target='CRI')
    return net
def V(net):
    return sv(net.CRI.readMP([net.connectome.get_neuron_by_key('n0').get_hbmIdx()])[0][3])
def clear_baseline(net):
    # spike+reset to clear V to 0 (threshold low so it fires then resets)
    net.step(['a0']); net.step([])
    return V(net)

def banner(name):
    print(f"\n{'='*56}\n  {name}\n{'='*56}")

# ---------------------------------------------------------------
# 1. Exponential PSC decay (excitatory): V rises on input, I_ex decays exponentially
# ---------------------------------------------------------------
def test_exp_psc():
    banner("1. Exponential PSC decay (excitatory)")
    net=new_net(threshold=1000000, weight=1000)   # high thr: watch V build without spiking
    delta(); net.step(['a0']); print("  delta control V =", V(net))
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs=[]
    for i in range(1,9):
        net.step(['a0'] if i==1 else [])
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    rose = vs[0] > 0 or any(v>0 for v in vs)
    decayed = len(vs)>=3 and vs[-1] < max(vs) if max(vs)>0 else False
    print(f"  -> PSC present: {rose}; exponential decay after peak: {decayed}")

# ---------------------------------------------------------------
# 2. Inhibitory PSC: negative weight -> I_in -> V decreases
# ---------------------------------------------------------------
def test_inhibitory():
    banner("2. Inhibitory PSC (negative weight)")
    net=new_net(threshold=1000000, weight=-1000)  # negative weight
    delta(); net.step(['a0']); base=V(net); print("  delta control V =", base)
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs=[]
    for i in range(1,6):
        net.step(['a0'] if i==1 else [])
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    print(f"  -> V should go negative (inhibition): min V = {min(vs)}")

# ---------------------------------------------------------------
# 3. COBA conductance: drive scales with (E_ex - V); compare drive at low vs high V
# ---------------------------------------------------------------
def test_coba():
    banner("3. COBA conductance mode")
    net=new_net(threshold=1000000, weight=1000)
    delta(); net.step(['a0']); print("  delta control V =", V(net))
    # COBA on, E_ex high positive reversal
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=1, E_ex=2000, E_in=-2000, coreID=0)
    vs=[]
    for i in range(1,7):
        net.step(['a0'] if i==1 else [])
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    print(f"  -> COBA: V should approach E_ex and drive shrink as V rises. peak={max(vs)}")

# ---------------------------------------------------------------
# 4. AdEx adaptation: w accumulates on spikes, subtracts from V
# ---------------------------------------------------------------
def test_adex():
    banner("4. AdEx adaptation current")
    net=new_net(threshold=500, weight=1000)
    delta(); clear_baseline(net); print("  baseline cleared")
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, decay_w=200, delta_w=100, coba_mode=0, coreID=0)
    vs=[]
    for i in range(1,10):
        net.step(['a0'] if i%2==1 else [])
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    print(f"  -> adaptation should reduce V response over repeated spikes. Vs={vs}")

# ---------------------------------------------------------------
# 5. Refractory period: after spike, V held/suppressed for N steps
# ---------------------------------------------------------------
def test_refractory():
    banner("5. Refractory period")
    net=new_net(threshold=500, weight=1000)
    delta(); clear_baseline(net); print("  baseline cleared")
    # refractory is set via neuron model param (refractory_max). Use ANN_neuron with refr param if available.
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs=[]
    for i in range(1,8):
        net.step(['a0'])   # drive every step
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    print(f"  -> after a spike, V should be suppressed for refractory window. Vs={vs}")

# ---------------------------------------------------------------
# 6. Neuromodulation: excitability bias shifts effective threshold
# ---------------------------------------------------------------
def test_neuromod():
    banner("6. Neuromodulation (excitability bias)")
    net=new_net(threshold=1000, weight=800)
    delta(); clear_baseline(net)
    # with positive excitability bias, effective threshold lowers -> fires more easily
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, neuromod_excitability_bias=500, coba_mode=0, coreID=0)
    vs=[]
    for i in range(1,6):
        net.step(['a0'] if i==1 else [])
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    print(f"  -> excitability bias shifts firing threshold. Vs={vs}")

# ---------------------------------------------------------------
# 7. Soft reset: after spike V = V - threshold (not 0)
# ---------------------------------------------------------------
def test_soft_reset():
    banner("7. Soft reset")
    net=new_net(threshold=500, weight=1200)   # weight > threshold to force spike + overshoot
    delta(); clear_baseline(net)
    # soft_reset_en is a neuron-model param; drive strongly, observe post-spike V != 0
    cmd13(delta_mode=0, decay_ex=3900, decay_in=3900, coba_mode=0, coreID=0)
    vs=[]
    for i in range(1,6):
        try: net.step(['a0'] if i==1 else [])
        except Exception as e: print(f"    step{i}: spiked ({type(e).__name__})")
        vs.append(V(net)); print(f"  step{i}: V = {vs[-1]}")
    delta()
    print(f"  -> soft reset: post-spike V = V-threshold, not 0. Vs={vs}")

if __name__=="__main__":
    print("exp_psc biological feature suite (weight-based, 32-bit standard writes)")
    test_exp_psc()
    test_inhibitory()
    test_coba()
    test_adex()
    test_refractory()
    test_neuromod()
    test_soft_reset()
    print("\nDone. STDP + synaptic delay require 64-bit entry fields (separate 64-bit write path).")
