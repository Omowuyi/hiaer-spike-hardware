# diag_axons.py -- the test_max_number_axons network, with the full result pattern printed.
# Usage: HIAER_CORE_ID=<core> python diag_axons.py <number of axons>
import os, sys
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
core = int(os.environ.get("HIAER_CORE_ID", 0)); n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
axons = {f"A{i}": [(f"N1.{i}", 1)] for i in range(n)}
model = ANN_neuron(0, shift=-17); conns = {f"N1.{i}": ([], model) for i in range(n)}
outs = [f"N1.{i}" for i in range(n)]
net = CRI_network(axons=axons, connections=conns, outputs=outs, target="CRI", coreID=core)
def s32(v):
    v = int(v) & 0xFFFFFFFF; return v - (1 << 32) if v >= (1 << 31) else v
def runs(idx):
    idx = sorted(idx); out = []; i = 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and idx[j + 1] == idx[j] + 1: j += 1
        out.append(str(idx[i]) if i == j else "%d-%d" % (idx[i], idx[j])); i = j + 1
    return ", ".join(out[:24]) + (" ... (%d ranges)" % len(out) if len(out) > 24 else "")
sp1 = net.step([f"A{i}" for i in range(n)]); mp1 = {k: s32(v) for k, v in net.read_membrane(outs)}
sp2 = net.step([]); mp2 = {k: s32(v) for k, v in net.read_membrane(outs)}
v1 = [mp1[f"N1.{i}"] for i in range(n)]; v2 = [mp2[f"N1.{i}"] for i in range(n)]
s1 = sp1[0] if isinstance(sp1, tuple) else sp1; s2 = sp2[0] if isinstance(sp2, tuple) else sp2
ok = [i for i in range(n) if v1[i] == 1]
print("core %d, %d axons" % (core, n))
print("step 0: spikes=%d   MP==1: %d   MP==0: %d   other: %d" % (len(s1), len(ok), v1.count(0), n - len(ok) - v1.count(0)))
print("  first 48 MP values after step 0:", v1[:48])
print("  neurons with MP==1:", runs(ok))
for m in (2, 4, 8, 16, 32):
    res = sorted(set(i % m for i in ok))
    if len(res) < m: print("  MP==1 only at index %% %d in %s" % (m, res))
others = sorted(set(v for v in v1 if v not in (0, 1)))
if others: print("  values other than 0/1 after step 0:", others[:20])
spk = sorted(int(k.split(".")[1]) for k in s2 if k.startswith("N1."))
print("step 1: spikes=%d   spiking neurons: %s" % (len(s2), runs(spk)))
print("  spiked == had MP 1 after step 0:", set(spk) == set(ok))
print("  MP after step 1: zeros=%d  first 16: %s" % (v2.count(0), v2[:16]))
