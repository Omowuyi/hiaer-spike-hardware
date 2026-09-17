# Routing Tables

Two designs in this repository have routing tables. **They are not compatible.**
Host code written for one will silently misprogram the other, and the failure is
invisible: entries land in the wrong place or not at all, and spikes are dropped
rather than misdelivered.

---

## The two formats

| | `noc/` (multicore_noc_5) | `noc_exp_psc/` (the merge) |
|---|---|---|
| opcode | CMD 13 (`0x0D`) | CMD 15 |
| address field in packet | `rxFIFO_dout[17:10]`, 8 bits | `rxFIFO_dout[15:6]`, 10 bits |
| entry field in packet | `rxFIFO_dout[9:0]`, 10 bits | `rxFIFO_dout[5:0]`, 6 bits |
| table index | `spike_addr[16:9]` | `spike_addr[18:9]` |
| entries per core | 256 | 1,024 |
| block size | 512 neurons | 512 neurons |
| entry layout | `[9:8]` level, `[7:4]` primary, `[3:0]` secondary | `[5:4]` level, `[3:0]` mask |
| L2 per-core selection | yes, via secondary mask | no |
| core selection | `tdest` | `tdest` |

Neither packet carries a core field. Each core has its own command interpreter
and programs its own router; the core is selected by `tdest`, which is
`tdata[503:499]`.

---

## Why they differ

The merge widened the neuron address from 17 to 19 bits, which quadrupled the
table to 1,024 entries and pushed the address field in the command packet from 8
bits to 10. Those two extra bits came out of the entry field, which fell from 10
bits to 6 — and the four bits lost were the secondary mask.

So the merge gained address range and lost the ability to name cores
independently within destination clusters on an L2 route. Whether that was
intended or was a consequence of the widening is not recorded anywhere, and it is
worth deciding deliberately.

---

## Levels

| level | value | behaviour |
|---|---|---|
| NOP | `00` | no target |
| LOCAL | `01` | stays on the source core |
| L1 | `10` | within the cluster; mask selects core positions |
| L2 | `11` | across clusters; mask selects clusters |

In `noc/` the reset value is `{OP_LOCAL, 4'b0000, 4'b0000}` and NOP is decoded as
a silent drop.

---

## Granularity

One entry governs 512 neurons. A block whose neurons live on more than one core
cannot be expressed — the entry picks one destination set for all 512.

The partitioner therefore coarsens to 512-neuron granules, so the constraint is
satisfied by construction rather than checked afterwards.
`noc_routing.check_alignment()` reports any violation.

---

## Host loader

`../software/noc_routing.py` in `noc_exp_psc/` builds and sends tables for the
**merge** format. It was corrected in September 2026 for four defects, all of
which predate that correction: the opcode was 13 rather than 15, no `tdest` byte
was emitted so every table went to core 0, the address was masked to 8 bits
against a 10-bit field, and `ENTRIES` was 256 against a 1,024-entry table.

There is no host loader for the `noc/` format in this repository.
