# HiAER-Spike v12c: single-core design (v12b + fix 29)

**Verified scope:** one network on one core, on any of the 16 cores, one core at a time. The bitstream physically contains
the 16-core NoC fabric; multi-core operation is not part of this design's verification (that is v13).

| | |
|---|---|
| Part | xcvu37p-fsvh2892-2-e, Vivado 2024.1 |
| Timing | WNS: 0.001   WHS: 0.000 (setup and hold met) |
| Bitstream | sixteen_core_noc_v12c_ila.bit (md5 in bitstream/md5.txt); probes sixteen_core_noc_v12c_ila.ltx (here) |
| Feature word | 0xF10A_00FF (status bits 16-19: watchdog, exp-PSC bypass, delay-slot overflow, Phase-2 fallback) |
| On the card | the complete hardware suite passes on all 16 cores (verification/card_sweep_16_cores/matrix.txt) |

## What changed from v12b
On v12b, core 2 stalled at its first HBM write. Vivado had merged the 16 per-core 450 MHz reset synchronisers, so two bits
of core 2's HBM transmit state were released by core 1's copy and two by core 14's; a one-cycle skew put the machine in its
response state from power-up. Fix 29: ASYNC_REG and DONT_TOUCH on both reset-synchroniser flip-flops of every core, and one
local DONT_TOUCH reset register in each HBM processor, so every state bit leaves reset on the same edge. The build checks
after placement and after routing that each core has its own local reset register, driven by its own synchroniser.
Everything else is v12b.

## What is here
- rtl_simulated/: the sources the simulation gate proved (v12b's fixes 1-28 and plasticity, plus fix 29; round 34c).
- rtl_built/: the sources Vivado synthesized: rtl_simulated plus the 22 capture taps on core 1 and the top-level tie-offs.
- ip/: every IP configuration (as v12b: hbm_register_slice mode 15 with one HBM-side pipeline stage).
- constraints/, project/multi_core.xpr: the project as built.
- kits/: the v12c gate and build (v12c_kit), and the diagnosis of the core 2 stall where present (eco kits, fix29_kit).
- verification/: the round 34c gate log (PASS); the card results: the 16-core sweep matrix and every core's summary, and the
  core 2 run; the bitstream md5 on the card and the hardware suite commit used.
- build_reports/: placement and routing utilization and timing.
- software/: where the software used with this bitstream lives (branch v12b_tested in hs_bridge, hs_api and connectome_utils).

## Reproduce
From this repository: create the project from project/multi_core.xpr with rtl_built/, ip/ and constraints/, then run
kits/v12c_kit (run_v12c_build.sh trial, then finish).
