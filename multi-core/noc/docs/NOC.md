# NoC Architecture

Sixteen cores as four clusters of four. Core *c* sits in cluster *c* >> 2 at
position *c* & 3. Routing is hierarchical: a spike stays on its core, crosses an
L1 bus inside the cluster, or crosses an L2 bus between clusters.

---

## Per-core router

`noc_spike_router.sv`. Each core has one. It holds the routing table for spikes
*originating* on that core and decides where each goes.

The table is indexed by the destination address:

```
wire [7:0] route_idx = spike_addr_in[16:9];
```

256 entries, one per 512-neuron block. Reset value is
`{OP_LOCAL, 4'b0000, 4'b0000}` — every spike to the host until the table is
programmed.

### Entry format, 10 bits

| bits | field |
|---|---|
| `[9:8]` | level |
| `[7:4]` | primary mask — cores within the cluster for L1, clusters for L2 |
| `[3:0]` | secondary mask — per-core mask within the destination clusters, L2 only |

| level | value | behaviour |
|---|---|---|
| `OP_NOP` | `00` | spike silently consumed and dropped |
| `OP_LOCAL` | `01` | delivered to the host path |
| `OP_L1` | `10` | onto the L1 bus, primary mask selects cores in this cluster |
| `OP_L2` | `11` | onto the L2 bus, primary selects clusters, secondary selects cores within them |

The secondary mask is what lets L2 name cores independently of their position —
a spike can reach core 2 of cluster 1 and core 3 of cluster 3 in one entry. The
original 6-bit entry could not express this.

### Routing FSM

`ROUTE_IDLE` → `ROUTE_LOOKUP` → `ROUTE_TO_NOC` or `ROUTE_TO_HOST` →
`ROUTE_DONE` → idle. Lookup results are registered on the transition out of
idle, so the table read is one cycle and the decision is made on registered
values. One spike is in flight at a time.

---

## Buses

`noc_l1_bus.sv` carries spikes between the four cores of one cluster.
`noc_l2_bus.sv` carries them between the four clusters. `noc_arbiter.sv` is the
shared arbitration primitive; `noc_input_arbiter.sv` merges NoC and local traffic
at a core's input.

`noc_spike_injector.sv` delivers an arriving NoC spike into the destination
core's external events processor — the same path an axon spike takes, so the core
does not distinguish local from remote sources.

`cores_with_noc.sv` assembles all sixteen routers, injectors and both bus levels,
and takes `route_cfg_valid` as a per-core array so each core's table is
programmed independently.

---

## OP_NOP is not free in this design

`OP_NOP` is decoded in the routing FSM and silently consumes the spike. The
Firefly design assumes NOP is unused and repurposes it as a `REMOTE` encoding.
That assumption does not hold for this router and must be rechecked against the
router in `../../noc_exp_psc/rtl/` before any Firefly work depends on it.

---

## What is not established

- Deadlock behaviour in the crossbar under sustained backpressure
- Whether the five NoC verification tests pass on hardware — they have not been
  run on this bitstream
