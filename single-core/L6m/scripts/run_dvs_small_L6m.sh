#!/bin/bash
# Run DVS small on L6m single-core
# Expected: 44.44%
set -e
cd /home/omowuyi/testing/hs_api
source .venv/bin/activate
export PYTHONPATH=/home/omowuyi/testing/hs_bridge

# Patch DVS test for L6d noise semantics (shift=0 -> -17, legacy_noise_en=1)
cd tests
python3 << 'PYEOF'
T = 'test_DVS_small.py'
with open(T) as f: t = f.read()
if 'neuron_obj.shift = -17' not in t:
    old = '        network = CRI_network('
    ins = '        for key in connections:\n            neuron_obj = connections[key][1]\n            if hasattr(neuron_obj, "shift") and neuron_obj.shift == 0:\n                neuron_obj.shift = -17\n            neuron_obj.legacy_noise_en = 1\n\n'
    t = t.replace(old, ins + old, 1)
    with open(T, 'w') as f: f.write(t)
    print("DVS small patched")
PYEOF

find /home/omowuyi/testing -name "__pycache__" -exec rm -rf {} + 2>/dev/null
pytest -s test_DVS_small.py -v
