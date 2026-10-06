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
---

## v3 multicore software + NoC-only bitstream — 29 Sep to 3 Oct 2026

Per-core placement made real end to end, three latent defects fixed, and a
NoC-only bitstream built that closes timing and **does not pass DMA**. The
DMA failure is unresolved and is the blocking issue for this design.

### Bitstream

| | |
|---|---|
| **File** | `sixteen_core_noc_only_v3.bit` |
| **Built** | crisdsc3, `/data/omowuyi/multicore_noc_exp_psc/`, 3 Oct 2026 04:07 |
| **MD5** | `ad5c57080b026e1aeded090bebf1bddb` |
| **Top** | `sixteen_core_noc_top` (generated; no Firefly, no GT ports) |
| **WNS / WHS** | **+0.002 ns / 0.000 ns**, zero failing endpoints of 1,468,640 |
| **Status** | **FAILS** — enumerates on PCIe, first DMA transfer hangs |

### Host software — vendored in `software/src_v3_multicore/`

Snapshots. The lab repos remain authoritative.

| repo | branch | commit |
|---|---|---|
| `connectome_utils` | `v3_multicore` | `4a99d8d3e1be535da7799fff744cb39e4971b7cd` |
| `hs_bridge` | `v3_19bit_wip` | `153a3aa9dd9a68dfd70951cc26017b4d191eb0fc` |
| `hs_api` | `exp-STDP-testing-suite` | `6b26fb464f1fe16b28cbad244748d7d53e928af9` |

| file | md5 |
|---|---|
| `api.py` | `2937c940c6db7edc36d965661c549213` |
| `compile_network.py` | `7c31ed0036d8a5e26cecb44eb61416cb` |
| `connectome.py` | `7d18798ed925f8522e6b7ccf0cd45a10` |
| `fpga_controller.py` | `b578a470cf0c5405a10eda536bbfee69` |
| `network.py` | `04ff1b6240f87a27e9c71034221f70d1` |
| `noc_routing.py` | `ef3d3861db6be9184d213f5b675e76a8` |

Verified **42/42** hardware regression on L6m after every patch.

### What the software now does

Multi-core placement did not exist before this work. `compile_network.partition()`
hardcoded `n_cores = 1`, `map_to_hbm_fpga()` looped over cores without filtering,
and both `coreTypeIdx` and `hbmIdx` were enumerated globally. Seven changes, in
dependency order:

1. **Per-core neuron and axon indexing** — `coreTypeIdx` and `hbmIdx` restart at
   0 on each core; `pad_models` computes model cutoffs per core; lookup is by
   `(core, idx)`. The lookup also became a dict instead of a linear scan run
   once per spike, which cut the regression suite from 279 s to 60 s.
2. **Real partitioning** — the hardcode removed, per-core filtering in
   `map_to_hbm_fpga`, caller-supplied `membership`.
3. **Partition applied before `pad_models`** — padding is per `(core, model)` to
   a multiple of 32, so it was computed with every neuron still on core 0.
4. **Per-core runtime** — one `fpga_compiler` per core with its own
   `num_outputs`, cutoffs, inputs and readback; all cores loaded before any is
   started, so spikes land in the right timestep.
5. **19-bit spike decode with CORE_ID** — `{ts[31:24], valid[23], core[22:19],
   neuron[18:0]}`. Core appended as a third tuple element so `spike[1]` stays
   the address.
6. **coreID field width** — see below.
7. **Routing tables loaded during construction**, from the same assignment the
   partition used.

### Three latent defects found

**`cdc_timing.xdc` was inert in every build ever made.** Every `set_max_delay`
sat inside an `if`, which XDC rejects (`Designutils 20-1307`). None had ever
applied. Rewritten without control flow, plus a PCIe↔core bound and
reset-synchroniser false paths. Took this build from WNS −2.142 ns with 1,558
failing endpoints to +0.002 ns with none. **This affects the Firefly build
equally** — it closed timing only because `ff7_pins.xdc`'s blanket clock groups
happened to cover the same crossings.

**coreID encoded as 8 bits where `tdest` reads 5.** `write_parameters_simple`
and `write_neuron_type` wrote `np.binary_repr(coreID,8)` at `[503:496]`;
`switch_1_32.sv:9` takes `tdest` from `tdata[503:499]`. The 8-bit form sent
`coreID >> 3`, so cores 1–7 all steered to core 0 and cores 8–15 to core 1.
Harmless at core 0, which is every test ever run. Eight other functions already
used the correct 5-bit form.

**This affects anyone writing host code against a multi-core bitstream.**
Without the fix, commands for cores 1-7 land on core 0 and cores 8-15 on core
1, with no error anywhere -- the network runs, and fifteen cores are left
unprogrammed on reset defaults. The fix is in `hs_bridge` branch
`v3_19bit_wip` (`153a3aa`), applied by `software/fix_coreid_width.py`.

**`noc_routing.py` was keyed on destination blocks.** `noc_spike_router.sv:87`
is `route_idx = spike_addr_in[18:9]`, and `spike_addr_in` is the core's own
spike output — so the table is **source**-indexed. Also corrected: opcode 13→15,
address `[13:6]`→`[15:6]`, 256→1024 entries, and the payload core field removed
(the core comes from `tdest`).

### THE BLOCKING ISSUE — DMA

Every bitstream from `multicore_noc_exp_psc` fails DMA. Bitstreams from two
other projects work. **The mechanism is not identified.**

| bitstream | project | XDMA `SYNTHESISFLOW` | result |
|---|---|---|---|
| `sixteen_core_top_L6m.bit` | `single_core_exp_psc` | OUT_OF_CONTEXT | works, 42/42 |
| `sixteen_core_top_multicore_noc_5.bit` | `multicore_noc` | OUT_OF_CONTEXT | works, DMA read OK |
| `sixteen_core_firefly_v3.bit` | `multicore_noc_exp_psc` | GLOBAL | fails |
| `sixteen_core_noc_only_v3.bit` ×2 | `multicore_noc_exp_psc` | GLOBAL | fails |

`multicore_noc_5` is a 16-core NoC design, so core count is not the variable.

**Signature:** PCIe enumerates, link trains x16 8.0 GT/s, BAR 0 assigned,
`/dev/adxdma0*` created — then the first host-to-card transfer hangs in
`adxdma_h2c_release` → `adxdma_cleanup_dma_requests`, state D. Module refcount
leaks and only a reboot clears it.

**Do not pursue the `start_stop_dma_engine` warning.** It appears on L6m too,
which passes 42/42 — counted 12 occurrences on a working load. `dma_core.c:673`
compares a descriptor address's high word against a descriptor count; it fires
when DMA memory is allocated above 4 GB. Noise.

**Ruled out:** GT placement (AVAL-324 4→0 under OOC, but the channels were
placed correctly); the driver warning; copied-checkpoint context mismatch
(regenerating the IP natively in this project gave the same `Opt 31-67`);
AXI-ST bypass ports (enabled in a working project too); undriven `tlast`/`tkeep`
in the ingress bypass (a real bug, fixed, did not resolve it — and
`firefly_v3` predates that code entirely).

**The OOC blocker:** setting this project's XDMA to out-of-context reaches
`opt_design`, which fails on one LUT2 in the IP's unused AXI4-MM bridge
(`Opt 31-67`, `firstdwen_ff_i_2`). `set_msg_config` does not suppress it.
`single_core_exp_psc` runs `opt_design` on an OOC checkpoint of the same IP
without hitting this.

**Two options remain:** keep diagnosing this project, or clone
`single_core_exp_psc` and bring the NoC sources into it. The second starts from
a configuration that demonstrably produces enumerating bitstreams.

### Reproducing

```bash
# 1. host software -- apply to clean checkouts, or use software/src_v3_multicore/
python3 software/patch_percore_connectome.py  <connectome_utils>/connectome_utils/connectome.py
python3 software/patch_percore_partition.py   <connectome.py> <compile_network.py>
python3 software/patch_percore_runtime.py     <network.py> <api.py>
python3 software/fix_flush_merge.py           <network.py>
python3 software/patch_spike_coreid.py        <fpga_controller.py>
python3 software/fix_coreid_width.py          <fpga_controller.py>
python3 software/patch_load_routing.py        <api.py>
# noc_routing.py must be importable by the test environment

# 2. NoC-only top -- generated, never hand-edited
python3 patches/make_noc_only_top.py <sixteen_core_noc_firefly_top.sv> <out.sv>

# 3. constraints -- rtl/cdc_timing.xdc replaces the project's inert version

# 4. build: synth_2/impl_2 on constrs_noconly, top sixteen_core_noc_top
```

Each patch runs `--check` first and aborts unless its anchor matches exactly
once. Every one was verified by a 42/42 hardware run before the next was
applied.

### Still open, unrelated to DMA

- **Microphase boundary** — 16 neurons lost at the first row of each microphase
  after the first. Nine documented fix attempts. Now **per core**, so a 16-core
  network loses 16 per core, not 16 in total.
- **Firefly pin constraints** — `ff7_pins.xdc` `PACKAGE_PIN` assignments report
  `Cannot set LOC property of ports` with an inferred OBUF, in `firefly_v3`'s
  own `impl_1` log. Predates this work.
- **`NOC_FIREFLY_DESIGN.md` §4 does not match `hiaer_firefly_pkg.sv`** —
  `dst_neuron` is 19 bits not 13, there is no `src_server` or `src_neuron`,
  `timestamp` is 8 bits not 5, and the opcode table differs entirely.
