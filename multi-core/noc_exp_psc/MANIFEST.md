# File Manifest and Build Plan

Everything produced, what each file does, where it goes, and in what order to
build.

---

## BUILD SEQUENCE — NoC first, Firefly second

**Build the NoC bitstream alone, then Firefly.** Three reasons:

**A NoC failure and a Firefly failure look the same from the host.** Both show
as spikes not arriving. Building them together means a failure could be the
crossbar, the routing tables, the Aurora link, the classifier or the injector —
five suspects instead of one.

**The NoC is testable on ONE FPGA.** Flash one card, load routing tables, send a
spike from core 0 to core 5, confirm it arrives. Firefly cannot be tested at all
without a second FPGA, and the topology is not exercised until all eight are up.

**FPGA_ID is a compile-time parameter.**

```systemverilog
module sixteen_core_top_firefly #(parameter logic [2:0] FPGA_ID = 3'd0)
```

Eight FPGAs therefore need **eight different bitstreams**, at ~50 minutes each —
about seven hours per iteration. Before starting Firefly bring-up, make FPGA_ID
runtime-settable: a CMD that writes an ID register, or three board pins read at
reset. One build then serves all eight cards, and a topology change stops
costing a day. That is a small change now and a large saving later.

**Order:**

1. NoC bitstream, one FPGA — crossbar, routing tables, biological cores
2. Verify: L1 hop, L2 hop, then 672/672 across all 16 cores
3. Make FPGA_ID runtime-settable
4. Firefly bitstream — add the Aurora chain, two FPGAs first, then eight
5. Server-to-server

---

## FILES BY DESTINATION

### `rtl/noc/` — the interconnect

| file | what it does | status |
|---|---|---|
| `noc_pkg.sv` | opcodes, packet struct, topology table | yours |
| `noc_spike_router.sv` | per-core 256-entry routing table, decides LOCAL/L1/L2 | **5/5 xsim** |
| `noc_spike_injector.sv` | delivers a NoC spike into a core's EEP | yours |
| `noc_l1_bus.sv` | intra-cluster crossbar, 4 cores | **4/4 xsim** |
| `noc_l2_bus.sv` | inter-cluster crossbar, 4 clusters | **5/5 xsim** |
| `noc_arbiter.sv` | shared arbitration primitive | yours |
| `cores_with_noc.sv` | assembles routers, injectors, buses | elaborates |
| **`noc_integration.v`** | wires 16 cores to the crossbar; combines the 16 per-core routing-table writes into the single bundle the interconnect expects | **elaborates** |
| **`axis_switches.sv`** | `switch_16_1`, `switch_1_16` and `axis_arbiter_2` — SystemVerilog replacements for two Xilinx IP blocks and `noc_input_arbiter.sv` | **30/30** |
| **`axon_trace_mem.v`** | eligibility traces for axon sources, so STDP works across cores | **11/11** |

### `rtl/core/` — the biological core

Seven files copied from `single_core_exp_psc`: `internal_events_processor.v`,
`hbm_processor.v`, `delay_buffer.v`, `axon_delay_buffer.v`, `stdp_controller.v`,
`command_interpreter.v`, `single_core.sv`. Plus `core_wrapper.sv` and the top
level.

Every biological feature travels with these — the NoC never touches them.

### `patches/` — anchor-verified RTL edits

| file | what it does |
|---|---|
| `add_route_cmd15.py` | CMD 15 routing-table write; threads `route_cfg` CI → single_core → core_wrapper. Opcode 15 because 13 is PSC params and 14 is the axon delay table |
| `add_noc_to_top.py` | adds `noc_integration` to the top level **additively** — the AXI-Stream switches, classifier, Aurora chain and injector are untouched |
| `add_remote_egress.py` | adds a remote egress port to the router for Firefly. Orthogonal `remote_en`, not an overloaded level code |
| `fix_stdp_axon_trace.py` | STDP controller reads the axon trace when `e_src[17]` is set |
| `fix_spike_backpressure.py` | **FIX V** — the one fix measured on hardware: 8189 → 9984 of 10000 spikes |
| `add_microphase_diag.py` | diagnostic bits for the microphase bug |
| `verify_rtl_state.py` | 22-check content-hash gate. Run before every build |

### `software/` — compiler and host

| file | what it does |
|---|---|
| `noc_routing.py` | builds routing tables from a partition, sends them |
| `noc_partition.py` | hierarchical hypergraph partitioner, λ-1 objective, cost model matching the measured L2 broadcast |
| `patch_syn_delay.py` | `CRI_network(..., syn_delay=N)` — delay at compile time |
| `fix_syn64_spike_entries.py` | **FIX W** — the 64-bit emit was dropping every spike entry |
| `fix_syn_delay_padding.py` | **FIX Y** — `syn_delay` was applied to padding, flooding the delay buffer |
| `fix_syn64_src.py` | **FIX Z** — `src` was always 0, making STDP impossible |
| `fix_axon_src.py` | **FIX AA** — axon rows carry a source index; `e_src[17]` flags the type |

### `sim/` — verification

`run_xsim.sh` plus `tb_router.sv`, `tb_l1.sv`, `tb_l2.sv`, `tb_switches.sv`,
`tb_arb.sv`. The runner gates on elaboration first, then runs every testbench.

### `tests/` — hardware

`test_bio_features2.py` (8 features), `test_delay_construct.py`,
`test_microphase_lowload.py`, `hbm_calibrate.py`.

### `docs/`

`NOC_FIREFLY_DESIGN.md`, `SESSION_HANDOVER.md`, `FIXES.md`,
`single-core-README.md`.

---

## APPLY ORDER

```
# compiler, no rebuild
fix_syn64_spike_entries.py   fpga_compiler.py
fix_syn_delay_padding.py     fpga_compiler.py
fix_syn64_src.py             fpga_compiler.py
fix_axon_src.py              fpga_compiler.py
patch_syn_delay.py           fpga_compiler.py network.py api.py

# RTL, needs a build
fix_spike_backpressure.py    hbm_processor.v
add_route_cmd15.py           command_interpreter.v single_core.sv core_wrapper.sv
fix_stdp_axon_trace.py       stdp_controller.v
add_noc_to_top.py            sixteen_core_top_firefly.sv
# add_remote_egress.py       -- Firefly only, hold for the second build
```

Then `verify_rtl_state.py`, then build.

---

## WHAT IS VERIFIED AND WHAT IS NOT

**Measured on hardware:** 42/42 delta regression, 8/8 biological features,
64-bit synapse format, FIX V spike backpressure (8189 → 9984), WNS +67.8 ps.

**Verified in simulation:** router, L1 bus, L2 bus, both AXI-Stream switches,
the arbiter, the axon trace memory, and the full interconnect elaboration.

**Verified computationally:** Firefly topology — 20 symmetric links, all 56
pairs reachable, worst case 3 hops.

**Not verified:** the merged bitstream, routing tables on hardware, any Aurora
link, per-synapse delay, STDP end to end. The microphase boundary still loses
16 neurons per boundary.
