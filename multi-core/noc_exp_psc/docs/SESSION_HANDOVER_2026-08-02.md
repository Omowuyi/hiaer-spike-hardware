# HiAER-Spike — Session Handover (2 Aug 2026)

Everything needed to continue exactly from where this session stopped. Read
this first; the memory files `/areas/hiaer-spike-rtl.md`,
`/areas/microphase-boundary-bug.md` and `/areas/noc-integration.md` hold the
same facts in more detail.

---

## WHERE THE SESSION STOPPED

Verifying — by simulation, not by reading — that `noc_spike_router.sv` works.
It does: **5/5 tests pass** in `/home/claude/work/nocsim/tb_router.sv`.

```
block 0, reset default LOCAL  -> HOST
block 1, configured L1        -> NoC  level=10 mask=1010
block 2, configured L2        -> NoC  level=11 mask=0101
block 3, NOP                  -> HOST
block 1 + offset 5            -> NoC  level=10 mask=1010
```

That confirms: table writes land via `route_cfg`, the index really is
`spike_addr[16:9]`, and `OP_NOP` falls through to the host path — so it is free
for the Firefly `REMOTE` encoding.

**Next step:** decide the merge target project, then merge the biological
single core into it.

---

## MACHINES

| host | role | holds |
|---|---|---|
| **crisdsc0** | test | `hs_api`, `hs_bridge`, the FPGA under test, `/bitstreams/` |
| **crisdsc2** | build + multicore | all multicore/NoC/Firefly projects |
| **crisdsc3** | build | `single_core_exp_psc` (biological single core), `/data/omowuyi/patches/` |

crisdsc0 SSH from crisdsc3 is blocked; files relay via crisdsc2.

Flash procedure after any reboot: L6m bitstream first to restore PCIe config,
then the target bitstream **without rebooting in between**.

---

## SINGLE CORE — current state

Bitstream on the card: **WNS +0.0678 ns**, **42/42** pytest, **8/8** biological
features. IEP normalized hash `15665e4dc212f4a376e464d7d7572bed` / 67719 =
v6 + microphase diagnostics.

### Working and hardware-verified

- 8 biological features: exp PSC exc/inh, mixed summation, COBA, refractory,
  AdEx adaptation, neuromodulation, soft reset
- 64-bit synapse format — weight delivery, group order `99…1599`
- **FIX V** — spike-readout backpressure. **8189 → 9984 of 10000** spikes.
  `hbm_processor.v` had `wire any_spk_full` declared with the comment
  "Backpressure: stall HBM reads if ANY spike FIFO is full" and never used it.
  FIX V registers it and gates `hbm_rready`

### Not working

**Microphase boundary** — 16 neurons per 512-row boundary lose spikes. 0.16% of
a 10k network. Predates L6m. Nine fix attempts (K, L, M, N, P, Q, R, S, T) all
failed; each either recovers the spike and corrupts membrane potentials, or
removes the corruption and loses the spike. **Do not attempt a tenth blind.**

**Per-synapse delay** — delivers nothing. Four compiler bugs found and fixed
this session (below); the trace went from garbage to all-zeros, and the control
(`syn_delay=0`) passes. Remaining bug is isolated to push-or-drain.

**STDP** — never run on hardware. Was structurally impossible until FIX Z.

### Compiler fixes made this session (all offline-verified, no rebuild needed)

| | bug |
|---|---|
| **FIX W** | `_create_synapses_64` filtered `if w[0] == 0`, dropping every spike entry `(1, neuronIdx)` and sliding the rest into wrong slots |
| **FIX Y** | `syn_delay` applied to `(0,0,0)` padding, so every padding slot became a delayed zero-weight synapse — hundreds per network flooding the delay buffer. **This was the alternating +1965/−1935 "drive every timestep" signature blamed on RTL three times** |
| **FIX Z** | `src = int(w[4]) if len(w) > 4 else 0`, and no tuple has 5 elements — so `src` was always 0 and STDP read neuron 0's trace for every synapse |
| row order | 64-bit rows written to wrong HBM addresses (`_hbm_row_reversed`) |

Plus `patch_syn_delay.py`: delay is now specifiable at construction —
`CRI_network(..., syn_64bit=True, syn_delay=N)`.

### Key RTL facts, hard-won

- `uram_wren` is **registered** (`always @(posedge clk)`, ~line 1972 of the
  IEP), so it lags `uram_rden` by one cycle and pairs with `uram_waddr`
- The IEP has **178 module-level declarations before their use**. Vivado
  synthesis accepts it; `xvlog` rejects the file. `xsim_prep.py` hoists them
- `mark_debug` costs **828 ps** of WNS on this design — `uram_waddr` (16×13)
  and `uram_wren` (16) are high-fanout nets needing replication. And it does
  **not** insert an ILA; Vivado only preserves the nets. Any future capture
  must use registered copies with fanout 1

### Verified readback layouts — do NOT re-derive these

Three separate derivations from RTL were wrong this session.

**CMD 2 (HBM read):** marker `0xBBBB` in bytes 62–63, the 256-bit row in bytes
0–31, **little-endian within each 32-bit group**.

**CMD 10 (error status):** layout **unknown and never working**. Every
`error_status` read this session returned 0x0000 including bits that must have
been set. Establish it empirically before trusting any bit.

---

## NoC — verified findings

### The router works

Tested, not assumed. `tb_router.sv`, 5/5.

### Table format, settled from RTL

- **Per-core.** `cores_with_noc.sv:124`:
  `route_cfg_valid_per_core[c] = route_cfg_valid && (route_cfg_core == c)`
- 256 entries per core, indexed by `spike_addr[16:9]` — one entry per
  **512-neuron block**
- `route_cfg_data[5:0]` = `[5:4]` level, `[3:0]` mask
- `OP_NOP=00, OP_LOCAL=01, OP_L1=10, OP_L2=11`; reset value
  `{OP_LOCAL, 4'b0000}`
- `OP_NOP` is never tested in the routing decision — **free for Firefly
  REMOTE**

### Two incompatible variants exist

**Working variant** — `cores_with_noc.sv` with `route_cfg` as **input**, plus
`noc_spike_router.sv`, `noc_pkg.sv`, `noc_l1_bus.sv`, `noc_l2_bus.sv`,
`noc_arbiter.sv`, `noc_spike_injector.sv`. On crisdsc2 at
`/home/omowuyi/multi_16_parallel/multicore_16/` and `/home/omowuyi/multicore_dev/`.

**Broken variant** — `backup_noc_wns0_20260623`: `cores_with_noc.v` is **0
bytes**, its CI uses CMD 13 with `[17:10]` addr and **10-bit** `[9:0]` data and
**no core field**, and `route_cfg` is `output` in CI, `single_core.sv` and
`core_wrapper.sv` with **no consumer**. CMD 13 pulses into nothing there.

**Therefore:** `add_route_cmd.py` and `noc_routing.py` match the *working*
variant. Check which variant a project's CI implements before applying either.

### Still unverified

- What `noc_l2_bus.sv` does with the 4-bit mask — whether L2 can select cores
  independently per cluster, or is stuck with the same relative position
- Whether any project builds the working variant end to end
- Deadlock behaviour in the crossbar under backpressure

---

## ARTIFACTS

All in `/mnt/user-data/outputs/`. Patch scripts are anchor-verified: they
`--check` first, abort on ambiguity, and write `.before_*` backups.

**Single core, RTL:** `fix_spike_backpressure.py` (FIX V, **built and
working**), `add_microphase_diag.py`, `fix_delay_slot_reset.py`,
`fix_microphase_KT.py` (**failed on hardware — do not build**),
`fix_spike_detect_64bit.py` (**FIX X — on hold, rests on an unverified byte
order**), `verify_rtl_state.py` (22-check build gate), `xsim_prep.py`

**Single core, compiler:** `fix_syn64_spike_entries.py` (W),
`fix_syn_delay_padding.py` (Y), `fix_syn64_src.py` (Z), `patch_syn_delay.py`

**Tests:** `test_delay_construct.py`, `test_microphase_lowload.py`,
`test_microphase_scope.py`, `hbm_calibrate.py`, `prove_spike_entry.py`

**NoC:** `noc_routing.py` (table generation + loader), `noc_partition.py`
(hierarchical hypergraph partitioner), `add_route_cmd.py` (CMD 13 for the CI),
`NOC_FIREFLY_DESIGN.md`

**Repo:** `migrate_repo.sh`, `single-core-README.md`, `FIXES.md`

**Simulation:** `/home/claude/work/sim` (single core — `iep_small*`,
`tbspk3.v`, `tbwave2.v`, `tb1e.v`), `/home/claude/work/nocsim` (`tb_router.sv`)

---

## PARTITIONER

`noc_partition.py` — hierarchical hypergraph partitioning, **not METIS**.

METIS minimises edge cut, which is wrong here: one spike to four cores in a
cluster is *one* L1 transaction with a 4-bit mask, not four. The right metric
is **λ−1 connectivity on a hypergraph**, one hyperedge per source block.

- Coarsens to 512-neuron blocks, so the routing granularity is satisfied by
  construction rather than checked afterwards
- Recursive down server → FPGA → cluster → core, so inter-FPGA cuts are decided
  first and therefore weighted most
- Uses KaHyPar if importable, built-in FM refinement otherwise
- `initial=` accepts a starting partition — for Potjans-Diesmann the population
  layout beats any generic start

Tested on synthetic networks only: λ−1 = 1 on two populations, λ−1 = 4 on a
ring of 8 (it paired adjacent populations so half the ring coupling became
LOCAL). **Never run on a real connectome.**

---

## FIREFLY DESIGN

`NOC_FIREFLY_DESIGN.md`. Four decisions, all resting on the NoC facts above:

1. **`OP_NOP` → `REMOTE`** — the level field is full, but NOP is dead. Mask
   becomes an Aurora port bitmask; 4 bits, 4 ports per FPGA. One decode arm,
   no wider table, no packet change. **NOP confirmed unused by simulation.**
2. **Remote destination table per FPGA, not per core** — 256 × 6 bits giving
   `{server, fpga}`. The destination depends on the neuron block, not the
   source core
3. **Reuse `axon_delay_buffer` as the TS receive buffer** — incoming spikes
   carry `TS[4:0]`; hold until the local timestep matches. Structurally
   identical to what that module already does
4. **Barrier every 16 timesteps, not every timestep** — Aurora ~900 ns worst
   case over 3 hops against a ~20 µs timestep; `TS` gives 32 timesteps of
   slack. ~0.3% overhead versus 4% for a per-timestep barrier

Unverified premises: the ~20 µs timestep is arithmetic, not measured; the
`axon_delay_buffer` fit is structural, not tested.

---

## IMMEDIATE NEXT STEPS

1. **Identify the merge target** on crisdsc2 — which project builds the working
   NoC variant. Check `route_cfg` direction on its `cores_with_noc.sv`: input
   means wired, output means dangling
2. **Merge the biological single core** — seven files from
   `single_core_exp_psc/.../imports/`: `internal_events_processor.v`,
   `hbm_processor.v` (with FIX V), `delay_buffer.v`, `axon_delay_buffer.v`,
   `stdp_controller.v`, `command_interpreter.v`, `single_core.sv`. Verify by
   content hash before building
3. **Opcode conflict** — the single-core CI uses CMD 13 for PSC parameters
   (`syn_64bit_en` at bit 131). NoC routing also drafted at 13. In the merged
   design routing moves to **opcode 15**, free in both. One-line change to
   `add_route_cmd.py` and `noc_routing.py`
4. **Build, load tables, verify L1 then L2**
5. Then Firefly: REMOTE decode, remote table, egress/ingress, barrier, relay

---

## WORKING PRACTICES THAT MATTERED

- **Never claim something works from reading it.** Three packet layouts and one
  routing-table format were derived from RTL and all were wrong. The router was
  only trustworthy after simulation
- **Anchor-verified patches over pasting.** Three hand-pastes silently failed
  this session; no anchored patch did. Always `--check` first
- **Verify content hashes before every build.** `verify_rtl_state.py`
- **Bound every hardware test** — `SIGALRM` plus retry caps. Two unbounded
  scripts hung the card and cost recovery cycles
- **A vacuous test result is worse than a failure.** The boundary test reported
  "row 513: 0 lost" when zero neurons in that row had been tested at all, and
  that sent nine fix attempts after the wrong target
