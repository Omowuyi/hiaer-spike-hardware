# Build Manifest — multicore_noc_5

One entry per build. Each records the exact sources by content hash, the
machine, the tooling, the timing and the results, so a build can be reproduced
and a result attributed.

---

## multicore_noc_5 — 23 June 2026

| | |
|---|---|
| **Bitstream** | `sixteen_core_top_multicore_noc_5.bit` |
| **Bitstream MD5** | `dfb89313ea1d6a69cabfab70f807e0ae` |
| **Also stored as** | `sixteen_core_top_noc_delay_fix.bit` (identical) |
| **Location** | `/data/omowuyi/multicore_noc/bitstreams/` and `/data/omowuyi/bitstreams/` on crisdsc3 |
| **Built on** | crisdsc2, `/home/omowuyi/single_core_a/single_core/` |
| **Tested on** | crisdsc0 |
| **Vivado** | 2024.1 |
| **WNS** | +0.007763 ns |
| **Clocks** | `aclk` 125 MHz, `aclk450` 250 MHz, `apb_clk` 100 MHz |
| **Results** | pending — the five NoC verification tests have not been run |

### NoC sources

| file | MD5 |
|---|---|
| `cores_with_noc.sv` | `3ed49ec8ad6257ee00b100bedebc005f` |
| `noc_pkg.sv` | `591566030ae011a70f9e6dcca865f0f1` |
| `noc_spike_router.sv` | `ddb8e37b870553a4f3673cec9f6d59e9` |
| `noc_l1_bus.sv` | `87d372d4443cf92b85955d7d99c9ce30` |
| `noc_l2_bus.sv` | `95e315f8af57f7957c52beec02c4c4b5` |
| `noc_spike_injector.sv` | `32ba49e7a6b9913c476a5a51178b279a` |
| `noc_arbiter.sv` | `cde482cbec73523359f05485ffac1e8a` |
| `noc_input_arbiter.sv` | `9a11cee3d5e76a6c8fc78df749c166ad` |

### Core sources

| file | MD5 |
|---|---|
| `command_interpreter.v` | `b989ff7f19bfa1a914a8bb7313f911b1` |
| `single_core.sv` | `49f1fc3ce10111631ef49884c24e3614` |
| `core_wrapper.sv` | `c6236158ec6b59d3070bfe4cf33e120b` |
| `internal_events_processor.v` | `9e84631700ff304f3a6405d171413067` |
| `hbm_processor.v` | `aaff17e6f07a3b79b5428464b71f1c90` |
| `external_events_processor_simple.v` | `ba242f3bdd693976883095a62be53385` |

### Software pairing

| | commit |
|---|---|
| `hs_api` | `e526b6f` (testing-suite branch) |
| `hs_bridge` | `1e3a114` |
| `connectome_utils` | `181f8a8` (dev branch) |

### Fixes in this build

As recorded in `timing_summary.txt`:

1. NoC integration — routers, injectors, L1 and L2 crossbars, sixteen CDC FIFOs
2. INTER_CORE synapse routing — HBM processor opcode `001`
3. HBM processor pipeline register — `exec_hbm_rdata` and `exec_hbm_rvalidready`
4. HBM APB false-path constraint — `apb_clk` against `aclk`
5. IEP multi-driven net fix — `delay_add` defaults moved to the correct always block
6. IEP delay match pipeline — `dm_match_pipe`, `dm_is_upper_pipe`
7. Routing table, CMD 0x0D

### Provenance note

`/data/omowuyi/multicore_noc/rtl_backup/` on crisdsc3 is labelled as the
reproduction source for this bitstream. It is not: its `cores_with_noc.v` is
zero bytes and it contains no NoC sources at all. The sources in this directory
came from the crisdsc2 build tree named above, which produced the bitstream
whose MD5 matches both copies stored on crisdsc3.

The `rtl_backup` core sources and constraints are genuine and are included here;
only its NoC half is missing.
