#!/usr/bin/env python3
"""
Does spike loss follow the microphase row boundary?

C1.9.104 (hbmIdx 8204, row 512) loses its spike; C1.8.754 (7954, row 497) does
not.  Row 512 is the first row of microphase 1: with ~10912 neurons,
URAM_ADDR_LIMIT = 682, so microphase 0 covers rows 0-511 and microphase 1
covers 512-682.  STATE_PHASE2_DONE jumps to STATE_WAIT_BRAM_PHASE1_DONE and
skips STATE_FILL_PIPE_PHASE1, so the Phase-1 read pipeline is never re-primed
for microphase 1.

If that is the cause, EVERY neuron in row 512 loses spikes and row 513 is fine,
independent of channel.  This watches both rows and reports per row.

  hbmIdx = channel * 900 + y      (900 = 30x30 per channel)
  row    = hbmIdx // 16
  row 512 -> hbmIdx 8192..8207 -> C1.9.92  .. C1.9.107
  row 513 -> hbmIdx 8208..8223 -> C1.9.108 .. C1.9.123

Run from the tests/ directory (fixtures are loaded by relative path):
  cd /home/omowuyi/testing/hs_api/tests
  source ../.venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_microphase_boundary.py
"""

import sys, pickle
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import torch
from hs_api.api import CRI_network

PER_CHANNEL = 900
THRESHOLD   = 32676
GROUPS      = 16


def name(idx):
    return "C1.%d.%d" % (idx // PER_CHANNEL, idx % PER_CHANNEL)


ROWS = [512, 513]
watch = []
for r in ROWS:
    watch += [name(r * GROUPS + g) for g in range(GROUPS)]

print("watching %d neurons across rows %s" % (len(watch), ROWS))
for r in ROWS:
    lo, hi = r * GROUPS, r * GROUPS + GROUPS - 1
    print("  row %d : hbmIdx %d..%d  ->  %s .. %s"
          % (r, lo, hi, name(lo), name(hi)))
print()

with open('./fixtures/DVS_model_ch=10_conv=2_IFneuron.pkl', 'rb') as f:
    cfg = pickle.load(f)
with open('./fixtures/DVS_test_batch.pkl', 'rb') as f:
    batch = pickle.load(f)

net = CRI_network(axons=cfg['axons'], connections=cfg['connections'],
                  outputs=watch, target="CRI")

img = batch['images'][0]
prev = {n: None for n in watch}
# (row, timestep) -> [reported, silently_lost]
tally = {r: [0, 0] for r in ROWS}
detail = []

for t in range(img.shape[0]):
    frame = img[t, :, :, :].unsqueeze(0).flatten(start_dim=1).to(torch.int16)
    inputs = ["A%d" % i for i, e in enumerate(frame[0, :]) if e.item() > 0]

    spikes, _, _ = net.step(inputs)
    fired = set(spikes)
    got = net.read_membrane(watch)
    mp = dict(got) if isinstance(got[0], tuple) else dict(zip(watch, got))

    for n in watch:
        idx = 0
        r = (int(n.split('.')[1]) * PER_CHANNEL + int(n.split('.')[2])) // GROUPS
        p = prev[n]
        if p is not None and p > THRESHOLD:
            # crossed threshold last step -> must fire this step
            if n in fired:
                tally[r][0] += 1
            else:
                tally[r][1] += 1
                detail.append((t, n, r, p, mp[n]))
        prev[n] = mp[n]

    print("t=%d  spikes reported: %s" % (t, sorted(fired)))

print()
print("=" * 66)
print("  row   reported   SILENTLY LOST")
for r in ROWS:
    print("  %-5d %-10d %d" % (r, tally[r][0], tally[r][1]))
print("=" * 66)
if detail:
    print("\nlost spikes (neuron crossed threshold, never reported):")
    for t, n, r, p, v in detail:
        print("  t=%d  %-12s row %d   V was %-8d then %-8d (reset, no spike)"
              % (t, n, r, p, v))
print()
if tally[512][1] > 0 and tally[513][1] == 0:
    print("CONFIRMED: loss is confined to row 512, the microphase boundary.")
    print("The Phase-1 pipeline is not re-primed when microphase_ctr advances.")
elif tally[512][1] == 0 and tally[513][1] == 0:
    print("No loss observed in either row -- these neurons may not have")
    print("crossed threshold. Widen ROWS or run more timesteps.")
else:
    print("Loss is NOT confined to the boundary row. The row-512 correlation")
    print("was coincidence; send me this output.")
