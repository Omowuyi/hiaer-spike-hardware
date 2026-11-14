# v14: the 16-core NoC with fixes 31 to 35

Sixteen cores on a crossbar NoC, each with the full single-core feature set (fixes 1 to 30, plasticity, the HBM-side register slice), and five fixes found while verifying v13 against Christopher Deng's DVS spike tests and larger networks.

- bitstream: `/bitstreams/sixteen_core_noc_v14_ila.bit` on crisdsc0 (the `.bit` is not in this repository; `bitstream/` holds its md5 and the `.ltx`)
- md5: `f1014cec1e5e98434ef2a5959866113d`
- software: `hs_bridge` and `hs_api` branch `v14-multicore`, `connectome_utils` branch `v12b_tested`

## The five fixes

| fix | file | what went wrong | now |
|---|---|---|---|
| 31 | `command_interpreter.v` | the latency and HBM-count packets were written to the transmit FIFO without checking that it had room, so under a slow host a core's count packets for a step could be lost | both writes wait for room |
| 32 | `pointer_fifo_controller.v`, `single_core.sv` | a pointer row was consumed even when a column's pointer FIFO was full, so its pointers were dropped (more than about 256 spiking neurons in one column of one core in one step) | the row is held until there is room |
| 33 | `internal_events_processor.v` | in a core with more than 8,192 neurons, microphase 0's Phase 2 wrote a neuron's spike flag as 0, erasing a spike the neuron had just fired in microphase 1 before it was read; this is the loss in Christopher's tests | Phase 2 keeps the spike flag |
| 34 | `single_core.sv`, `pointer_fifo_controller.v` | when a core's input count was a multiple of 16, the input processors read one row past the core's input range, and relays landing there were followed through unwritten pointers into HBM row 0 | inputs at or beyond the range push no pointer, and a pointer of length 0 is never written |
| 35 | `single_core.sv` | the pointer lanes held 512 words, one short of a full phase; with every neuron of a core firing, v13 reported about a quarter of the spikes, and fix 32's hold could deadlock | each lane holds 1,024 words, so it cannot fill within a phase: nothing is dropped and the hold is never needed |

## Verification

RTL simulation of this exact design (v14d): all 13 required parts passed (`verification/gate_v14d_verdict.txt`):

- Christopher's two DVS spike tests: 8 of 8 assertions, 167 of 167 listed conv1 neurons
- one-core CNN, 15,371 neurons, against the exact model: 0 membranes differ
- 10,000 neurons on one core all firing in every step: 30,000 of 30,000 spikes
- round 46's original recording, with relays beyond a core's input range: exact at all 7 steps
- count packets under a slow host: v13 loses them, v14 does not
- the NoC, multi-core equivalence, the single-core regression (fixes 1 to 28, plasticity, watchdog, fan-in 9,000, delays), core positions, and the REACH2 gate

Fix 35's FIFO was unit-tested on its own first (`verification/fwft_fifo_core.v`, `tb_fifo.v`): 1,025 words before full, 150,831 random words, 0 errors.

On the board: V14 CARD ACCEPTANCE: PASS on 2026-11-13: Christopher Deng's two DVS spike tests, equivalence across 1, 4 and 16 cores, bio and plasticity, concentrated spikes (R48b, R48c), count packets (R57), the single-core suite on all 16 cores, and 12 large networks up to 122,891 neurons including 10,000 neurons on one core all firing, every spike and membrane exact

## Build

Vivado 2024.1, project `multi_core.xpr`. Timing met: WNS +0.001 ns, WHS +0.001 ns. Reports are in `build_reports/`; block RAM is at most 71.7 % of any SLR.

To rebuild: `build/apply_v14.sh` (puts `rtl/` into the project after checking it, then elaborates), then `build/run_v14_build.sh trial` and `build/run_v14_build.sh finish`.

## Layout

`rtl/` sources · `constraints/` · `ip/` IP configurations · `bitstream/` md5 and `.ltx` · `build_reports/` · `build/` build scripts · `verification/` the simulation gate and fix 35's unit test
