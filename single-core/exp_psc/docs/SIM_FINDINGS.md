# exp_psc (delta_mode=0) — root cause, fix, and simulation evidence

## Verdict

`delta_mode=0` gives V=0 for reasons that have **nothing to do with synapse packing
format**. The weight reaches the IEP correctly and Phase 2 writes I_ex=1000 into
Row B. Phase 0 then (a) never performs the Row A write that turns I_ex into V, and
(b) corrupts Row B with legacy-mode writes.

Three bugs, all confined to `!delta_mode` paths, plus one active regression: the
"phase fix" currently in the flashed bitstream **hangs Phase 1** on any network with
more than one URAM row. All validated in simulation against the real
`internal_events_processor`.

---

## The missing measurement — taken

`exec_hbm_rdata` during POP in `delta_mode=0` **does** carry the weight at
`[495:480]`, and the exp_psc accumulate **does** write it:

```
WRITE g0 row=2048 wdata=0000000003e8000000   (state=9 POP)     <- 0x3E8 = 1000
exp_psc step 1 : V(n0) = 0   I_ex(n0) = 1000
```

For group 0 the read positions are **bit-identical** in both modes:

| field         | delta_mode=1 | exp_psc halfsel=0     |
|---------------|--------------|-----------------------|
| opcode guard  | `[511]`      | `[511]`               |
| dest_addr     | `[508:496]`  | `[508:496]` + 4096    |
| weight        | `[495:480]`  | `[495:480]`           |

`fpga_compiler.create_synapses` writes `op(3) + addr(13) + weight(16)` = 32 bits,
MSB-first — so the standard write already lands n0's weight where exp_psc reads it.
That is why the standard write, six re-packings, and the hand-built 64-bit write all
produced V=0: none of them was ever the variable.

---

## Bug 1 (FIX A) — the Row A write at psc_substate 3 never happens

`uram_wren` is assigned inside `always @(posedge clk)` (~line 1775) — it is
**registered**, so a value computed in cycle X takes effect in cycle X+1.
`psc_suppress_wren` / `psc_manual_wren` are *also* registered. The resulting
two-substate skew:

| substate | intended        | actual `uram_wren` | consequence |
|----------|-----------------|--------------------|-------------|
| sub 1    | suppressed      | **1**              | legacy delta branch writes **V = 0** |
| sub 2    | suppressed      | 0                  | ok |
| sub 3    | **Row A write** | **0**              | **I_ex never reaches V** |
| sub 4    | Row B write     | 1                  | ok |
| after 4  | none            | **1**              | `uram_waddr[0]` still = Row B addr → **Row B corrupted** |

The Row B corruption is visible in the baseline trace: `uram_rmwdata_lower[34:32]`
(bits of I_ex) is read as a refractory counter and decremented, giving
1000 → 952 → 696 → 406 → 130 instead of clean exponential decay.

**Fix:** decode the write window combinationally from the *current* substate.
`curr_state == STATE_PHASE0_READ_SPIKES` is in the gate so the legitimate Phase-1
spike-bit-clear write in `STATE_FILL_PIPE_PHASE1` (where `exec_uram_phase0_done`
is still 0) is not lost.

## Bug 2 (FIX B) — psc_saved_full_addr is one iteration stale

`psc_saved_full_addr <= uram_waddr[0];` at sub 0. `uram_waddr` last latched at
**sub 1 of the previous iteration**, i.e. `(A-1) + 4096`. Iteration 0 is correct only
because `uram_addr_rst` zeroed the register. From iteration 1 on, `psc_waddr_row_a`
points into Row B and `psc_waddr_row_b` wraps 12 bits back into Row A.

Measured (48-neuron network, Fix A applied, Fix B not):

```
psc_saved_full_addr = 0     RowA -> row 0      RowB -> row 2048
psc_saved_full_addr = 4096  RowA -> row 2048   RowB -> row 0      <- swapped
psc_saved_full_addr = 4097  RowA -> row 2048   RowB -> row 0
psc_saved_full_addr = 4098  RowA -> row 2049   RowB -> row 1
V(neuron32) = -1207959552
```

Invisible at `num_outputs=1` (a single iteration), fatal above 16 neurons.

## Bug 3 (FIX C) — phase2_halfsel mis-routes weights for groups 1-15

The 64-bit half-select scheme reads 8 entries per word at 64-bit spacing and
maps them to groups 0-7 or 8-15 depending on a toggle. Two problems:

1. **No software producer.** Every compiler path writes 32-bit entries. Reading at
   64-bit spacing gives group *g* the weight belonging to 32-bit slot *2g*.
2. **The toggle is positionally wrong even in principle.** It flips on every
   `exec_hbm_rvalidready`, so any word after the first in a Phase-2 fetch
   (multiple axon pointers, or `ptr_len` > 1) is remapped to groups 8-15
   regardless of the entries' real groups. Groups 8-15 are otherwise unreachable.

Measured, 16 neurons one per group, 32-bit slot weights 100…1600, Fix A+B only:

```
I_ex per group : 100 300 500 700 900 1100 1300 1500 0 0 0 0 0 0 0 0
expected       : 100 200 300 400 500 600 700 800 900 1000 1100 1200 1300 1400 1500 1600
```

**Fix:** one 32-bit extraction for both modes; exp_psc differs only by
`phase2_row_offset` (0 in delta, 4096 in exp_psc). `phase2_halfsel` becomes unused.

**Note on the 64-bit format.** `delay`/`stdp_tag`/`src` genuinely are needed for
synaptic delay and STDP, but they cannot be delivered until a compiler writes them
*and* the burst length doubles (16 × 64 bits = 1024 bits = 4 HBM rows per axon).
That is a separate change. Also, `dbuf_delayed_dest` / `dbuf_delayed_weight` are
declared in the IEP but **never read** — the delay buffer is currently a write-only
sink, so synaptic delay is non-functional in both modes today. The garbage entries
the scan block pushes are therefore harmless, which is why no change was made there.

---

## Validation results

Real `internal_events_processor`, 16 behavioural URAMs matching the
`xpm_memory_sdpram` config in `single_core.v` (4096 × 72, `READ_LATENCY_B=1`,
`WRITE_MODE_B="read_first"`). Icarus Verilog; no Vivado, no hardware.

Network: n0 = group 0, full_addr 0; one synapse weight +1000; `num_outputs=1`;
`ANN_neuron` (model 0), leak 0, noise off, `decay_ex=3900`. Threshold raised to
100000 so V stays observable instead of spiking.

| test | baseline | patched |
|---|---|---|
| `tb_iep` delta_mode=1 (control) | V=1000 | V=1000 (unchanged) |
| `tb_iep` exp_psc V(n0) | **0, 0, 0, 0** | **952, 906, 862** |
| `tb_iep` exp_psc I_ex(n0) | 1000 → 696 → 406 → 130 (corrupted) | 1000 → 952 → 906 |
| `tb48` Row A write rows | 0, 2048, 2048, 2049 | 0, 0, 1, 1 |
| `tb48` Row B write rows | 2048, 0, 0, 1 | 2048, 2048, 2049, 2049 |
| `tb16` I_ex per group | 100 300 500 … 1500, 0×8 | 100 200 300 … 1600 |
| `tb16d` delta_mode Phase-2 routing | 100…1600 | 100…1600 (identical) |

Re-verified on a synthetic "crisdsc3-like" file (handoff snapshot + phase fix +
debug-hook declarations): the applier detects both, and with
`--remove-phase-fix` all four testbenches pass identically to the table above.

**Delta-mode safety.** Fix A is gated by `!delta_mode`. Fix B touches
`psc_saved_full_addr`, which is read only under `!delta_mode`. Fix C reduces
to the original delta expressions when `delta_mode=1` (`phase2_row_offset = 0`,
and the unconditional weight list is verbatim the old delta list). `tb16d`
confirms this empirically: baseline and patched are identical in delta mode.

---

## Bug 4 (REMOVE) — the phase fix hangs Phase 1

The "phase fix" (`if (!delta_mode) exec_uram_phase1_done <= 1'b1;` inside the
`STATE_PUSH_PTR_FIFO` phase-signal branch) is not merely unnecessary — it is
actively harmful. Asserting `exec_uram_phase1_done` during PUSH flips the
`uram_raddr_*_full` select block (~line 919) out of its Phase-0/1 branch into the
Phase-2 branch, so during PUSH the URAM addresses come from `exec_hbm_rdata`
(pointer data) instead of the sequential `uram_raddr` counter. `uram_waddr[0]` then
never reaches `microphase_ctr*512 + uram_microphase_addr_limit`, so PUSH never
exits by its normal condition.

Measured, all three fixes applied and the phase fix left in place:

| testbench | result |
|---|---|
| `tb_iep`  (1 neuron, 1 URAM row) | passes — Phase 1 is a single trivial iteration |
| `tb48`    (48 neurons, 2 rows)   | **TIMEOUT** |
| `tb16`    (16 neurons, 2 rows)   | **TIMEOUT** |

On hardware it would escape via the 2047-cycle `iep_phase1_timeout`, having pushed
no useful pointers — consistent with "V=0 in every exp_psc configuration".

The single-neuron pass is why this was never caught: it is exactly the network
`test_exp_basic.py` builds.

`apply_exp_psc_fix.py --remove-phase-fix` removes it. With it removed, all four
testbenches pass.

---

## Before you build

1. **Remove the phase fix** (see Bug 4) and any leftover debug hook. The applier
   reports both and will remove the phase fix on request.

2. **`test_exp_basic.py` will report a false negative once this works.**
   `threshold=500` with a drive of ~952 spikes immediately, and with
   `soft_reset_en=0` that resets V to 0 — you would read V=0 from a *working*
   design. Raise the threshold (or read the spike bit) for the first
   validation run.

3. **Expected synthesis warnings.** `phase2_halfsel`, `psc_suppress_wren`, and
   `psc_manual_wren` become unused and will be optimised away. Left in place
   deliberately to keep the diff small.

## Applying it

`apply_exp_psc_fix.py` matches by anchor rather than line context, so it tolerates
the phase fix and debug hook being present. It verifies every edit site occurs
exactly once and writes nothing if any check fails. `--check` reports only.
`exp_psc_fix.patch` and the fully patched `internal_events_processor.v` are also
included, but both are relative to the handoff snapshot and will not apply cleanly
to a drifted file — prefer the applier.

## Not covered

- Multi-microphase behaviour (`num_outputs` > 8192) is untested here.
- The `dbuf` scan block still runs; it is inert but not correct. Worth removing
  when the 64-bit format is actually implemented.
- Timing closure. Fix A replaces two registered signals with combinational
  decodes of `psc_substate` / `curr_state` feeding `uram_wren`. Logic depth is
  small, but check WNS on the exp_psc paths.
