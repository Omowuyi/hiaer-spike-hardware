# Execution Architecture

How a timestep executes, how neuron state is banked, and the path a spike takes
from the neuron that emits it to the host or to another core. Command and packet
formats are in [`00_platform_reference.md`](00_platform_reference.md).

---

## 1. A core

One core holds up to 32,768 neurons and 131,072 axons. Sixteen cores occupy one
FPGA. A core is `single_core.sv` wrapping four processors:

- **external events processor** — delivers arriving spikes to axons
- **HBM processor** — fetches synapse rows for a firing source
- **internal events processor** — integrates, applies the neuron model, decides
  which neurons fire
- **command interpreter** — decodes host packets, emits spike words

Only the internal events processor knows the neuron model. The NoC, the delay
buffers and the Firefly path carry addresses and never interpret dynamics. That
is why the biological core merged into the NoC design without the interconnect
changing.

---

## 2. URAM banking, sixteen groups

Neuron state lives in ultra-RAM: 4,096 rows of 72 bits per core. Rows 0–2,047
hold each neuron's first row; rows 2,048–4,095 hold the second. Sixteen neurons
share a row index, one to each **group**, so a neuron is addressed as
`{row[10:0], group[3:0]}`.

The sixteen groups are processed in parallel, so a sweep across the population is
`num_outputs / 16` row iterations rather than `num_outputs`.

`uram_wren` is registered — `always @(posedge clk)` — so it lags `uram_rden` by
one cycle and pairs with `uram_waddr`, not with the read address. Several failed
fixes came from assuming otherwise.

---

## 3. Microphases

A sweep longer than 8,192 rows is divided into passes of at most that size by a
microphase counter. This is what lets a population larger than one pass be
evaluated without widening the datapath.

The division is also where the platform's oldest defect lives: at each 512-row
boundary, sixteen neurons — one per group — lose their spikes. Instrumentation at
low spike load found microphase 0 losing 0 of 7 probes and microphase 1 losing
7 of 7, with everything above neuron 8,192 silent. See
`single-core/exp_psc/docs/OPEN_ISSUES.md`.

---

## 4. The spike path

A spike emitted by a neuron travels:

1. the internal events processor sets the spike bit in URAM row A and pushes the
   neuron index into the spike FIFO
2. the command interpreter packs it into a 32-bit word — timestamp, valid, core,
   address, with the core at `[22:19]` and the address at `[18:0]` after the
   widening
3. fourteen spike words fill a 512-bit packet headed `0xEEEE_EEEE`, which the
   host reads by DMA
4. in a multi-core design the same spike also enters the NoC path: the spike
   classifier decides whether it stays local, crosses the on-chip network, or
   leaves the device by optical link

Spike readout can backpressure. `hbm_processor.v` declared `any_spk_full` with
the comment "stall HBM reads if ANY spike FIFO is full" and never used it; FIX V
registers it and gates `hbm_rready`, taking delivery from 8,189 to 9,984 of
10,000 spikes.

---

## 5. On-chip network

Sixteen cores as four clusters of four. Core *c* sits in cluster *c* >> 2 at
position *c* & 3.

Each core has a router holding a table indexed by the destination address —
`spike_addr[18:9]` after the widening, 1,024 entries, one per 512-neuron block.
Each entry is six bits: `[5:4]` level, `[3:0]` mask.

| level | meaning | mask |
|---|---|---|
| `00` | NOP — no target | — |
| `01` | LOCAL — stays on this core | — |
| `10` | L1 — within the cluster | core positions |
| `11` | L2 — across clusters | cluster bits |

Reset value is `{OP_LOCAL, 4'b0000}`. `OP_NOP` is never tested in the routing
decision, which is what makes it available as the Firefly `REMOTE` encoding.

Routing granularity is therefore 512 neurons. A block split across two cores
cannot be expressed — one entry chooses one destination set for all 512. The
partitioner coarsens to 512-neuron blocks so the constraint is satisfied by
construction; `noc_routing.check_alignment()` reports violations.

---

## 6. Inter-device

The spike classifier decides device ownership from a second table, written by
CMD 16 and indexed by the same block index. Spikes leaving the device travel
Aurora 64B/66B.

`remote_spike_injector.sv` reassembles the destination on arrival. It previously
packed 3 bits of device, 4 of core and 10 of neuron against cores of 8,192, so a
spike addressed to neuron 5,000 arrived at neuron 904. It now takes the full
`[18:0]`.

No optical link has yet carried a spike.

---

## 7. To be completed

The phase 0–4 decomposition of a timestep is not written here yet. It should be
extracted from the state machine in `internal_events_processor.v` rather than
recalled, and stated with the cycle cost of each phase.
