# NoC + Biological Core — the merge

Sixteen biological cores on the parallel crossbar, with the neuron address
widened from 17 to 19 bits and the Firefly optical subsystem added.

| | |
|---|---|
| **Built on** | crisdsc3, `/data/omowuyi/multicore_noc_exp_psc/` |
| **Tested on** | crisdsc0 |
| **WNS** | +0.037 ns |
| **Status** | **unverified** — built, never flashed |

---

## Contents

| path | what |
|---|---|
| `rtl/` | 42 live sources plus 80 `.before_*` files recording every patch in sequence |
| `patches/` | 43 anchor-verified RTL patches, each documenting symptom, mechanism and evidence |
| `software/` | host-side compiler and routing code |
| `sim/` | nine testbenches and `run_xsim.sh` |
| `docs/` | the merge notes and the August session handover |

The `.before_*` suffixes are the build history: `before_19bit`, `before_route15`,
`before_routecfg`, `before_runtimeid`, `before_cmd16`, `before_firefly` and the
rest, in the order they were applied.

---

## What the merge carries

From [`../../single-core/exp_psc/`](../../single-core/exp_psc/): the seven files
that hold the biological model — internal events processor, HBM processor, both
delay buffers, the STDP controller, the command interpreter and the core. Every
biological feature travels with them; the interconnect never touches them.

From [`../noc/`](../noc/): the crossbar, routers, injectors and buses.

New in this design: the 19-bit widening, the routing-table width increase, the
Firefly Aurora subsystem, the spike classifier, the remote destination table
(CMD 16) and runtime FPGA identity (CMD 17).

---

## The 19-bit widening

A core holds 2,048 URAM rows × 16 groups = 32,768 neurons, so sixteen cores hold
524,288 — which needs 19 bits to name. What confined the design to 131,072 was
the width of the address wherever it travelled, not any limit in the datapath.

The extra two bits came from fields that were written and never read: two bits of
the NoC packet's 5-bit timestamp, two of the optical packet's 16-bit payload, the
two reserved bits of the host spike word, and two of the three unused bits at the
top of the delay-buffer synaptic entry.

`patches/fix_widen_19bit.py` documents the whole derivation and is the reference
for what did and did not change. `num_outputs` and `num_inputs` are counts within
one core and were not widened.

---

## Not verified

Nothing in this design has run on hardware. Specifically unverified: the merged
bitstream, routing tables on a device, any Aurora link, per-synapse delay, STDP.

The microphase boundary defect is inherited from the biological core.
