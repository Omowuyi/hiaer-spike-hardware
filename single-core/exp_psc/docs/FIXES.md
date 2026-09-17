# RTL and Compiler Fixes

Each entry gives the symptom as observed, the mechanism, the fix, and the
evidence that closed it. Letters are the labels used in session records.

Verification terms follow
[`../../../docs/04_verification_methodology.md`](../../../docs/04_verification_methodology.md).

---

## FIX F — delay buffer entry carried no URAM group

**Symptom.** A drained delayed synapse could not be written back into neuron
state.

**Mechanism.** The entry was 54 bits —
`{3'b0, dest[12:0], weight[15:0], src[17:0], stdp_tag[3:0]}`. It carried a row
index but no bank. Sixteen neurons share a row, one per group, so a row without a
group does not name a neuron.

**Fix.** Widen to 58 bits, inserting `group[3:0]`.
`patches/delay_buffer_v2.patch.py`.

---

## FIX J — delay delivered N+2 timesteps late

**Symptom.** Measured in simulation against the real `delay_buffer`, delay swept
0 to 5:

| requested | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| delivered | 1 | 3 | 4 | 5 | 6 | 7 |

N+2 for every N greater than 0.

**Mechanism.** Both `delay_buffer.v` and `axon_delay_buffer.v` advance
`current_slot` in `DRAIN_DONE`, which runs off `timestep_tick` (`exec_run`) at
the top of the timestep — ahead of the Phase-2 push.

**Fix.** `patches/fix_delay_offset.py`. Simulation-verified.

---

## FIX U — delayed entries re-delivered forever

**Symptom.** A delayed synapse arrived once and then again on every subsequent
timestep.

**Mechanism.** In `delay_buffer.v`, the slot write pointer is reset only in the
`DRAIN_DONE` branch of an if-chain whose earlier branch fires on `write_en`. A
slot written in the same timestep it drains never has its pointer cleared, so its
contents drain again.

**Fix.** `patches/fix_delay_slot_reset.py`.

---

## FIX V — spikes dropped when a per-group FIFO fills

**Symptom.** Driving all 10,000 neurons of a 10,016-neuron network to spike in a
single timestep, **8,189 were reported**. Losses by row band: 0–255 clean, then
progressively worse, ending with entire bands lost. 504 of the losses were in
microphase 0, which distinguishes this from the microphase boundary defect.

**Mechanism.** `hbm_processor.v` declared

```
wire any_spk_full;   // Backpressure: stall HBM reads if ANY spike FIFO is full
```

and never used it. Writes were gated per group —
`assign spk0_wren = !spk0_full & ...` — so when a FIFO was full the write simply
did not happen. No backpressure, no counter, no flag, and `error_status` watches
only `spk2ciFIFO`, not the eight per-group FIFOs. The loss was invisible.

**Fix.** Register `any_spk_full` and gate `hbm_rready` with it.
`patches/fix_spike_backpressure.py`.

**Evidence.** 8,189 to **9,984 of 10,000**. Hardware-verified, built and running.

---

## Compiler fixes

Host-side, no rebuild required. Scripts in
`../../../multi-core/noc_exp_psc/software/`.

**FIX W** — `_create_synapses_64` filtered on `if w[0] == 0`, dropping every
spike entry `(1, neuronIdx)` and sliding the remaining entries into the wrong
slots. `fix_syn64_spike_entries.py`.

**FIX Y** — `syn_delay` was applied to `(0,0,0)` padding, so every padding slot
became a delayed zero-weight synapse — hundreds per network, flooding the delay
buffer. This produced the alternating +1965 / −1935 signature that was attributed
to RTL three separate times. `fix_syn_delay_padding.py`.

**FIX Z** — `src = int(w[4]) if len(w) > 4 else 0`, and no tuple has five
elements, so `src` was always 0 and every synapse read neuron 0's eligibility
trace. STDP was structurally impossible until this was fixed. `fix_syn64_src.py`.

**FIX AA** — axon rows carry a source index, and `e_src[17]` flags the type.
`fix_axon_src.py`.

**Row order** — 64-bit rows were written to the wrong HBM addresses
(`_hbm_row_reversed`).

---

## Enabling patches

**Per-axon delay table, CMD 14.** `axon_delay_buffer` implemented per-axon delay
completely — an 8192x6-bit BRAM table, an immediate bypass for delay 0, a 64-slot
circular buffer and a drain FSM — and had never been usable, because
`single_core.v` hardwired its write port to zero.
`patches/enable_axon_delay.py`.

**64-bit synapses.** `internal_events_processor` v6 added `syn_64bit_en` and
`dbuf_delayed_group` with nothing driving them. `patches/wire_syn64.py` wires
both end to end.

---

## Diagnostics

**`detect_spike_drop.py`** — makes the silent per-group FIFO discard visible.
Detection only, no behaviour change. This is what led to FIX V.

**`add_microphase_diag.py`** — isolates which of four stages loses microphase-1
spikes, through `error_status` bits 12–15.

**`add_stale_write_flag.py`** — reports whether FIX T ever fires, through
`error_status` bit 12. Written instead of an ILA because marking `uram_waddr` and
`uram_wren` with `mark_debug` cost 828 ps of WNS (+43 to −785 ps): both are
high-fanout nets needing replication, and `mark_debug` freezes them. It also does
not insert an ILA — Vivado only preserves the nets, so the timing was spent for
no capture at all.

---

## Failed

In `../patches/failed/`. Kept as history, not as alternatives.

| script | why |
|---|---|
| `fix_microphase_KT.py` | failed on hardware — do not build |
| `fix_microphase_skip.py` | same family |
| `add_ila_debug.py` | 828 ps of WNS for no capture |
