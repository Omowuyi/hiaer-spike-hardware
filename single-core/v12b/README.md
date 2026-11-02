# HiAER-Spike v12b: single-core design (fixes 1-28, plasticity, HBM-side register-slice stage)

**Verified scope:** one network on one core, on any of the 16 cores, one core at a time. The bitstream physically contains
the 16-core NoC fabric; multi-core operation is not part of this design's verification (that is v13).

| | |
|---|---|
| Part | xcvu37p-fsvh2892-2-e, Vivado 2024.1 |
| Timing | WNS: 0.015   WHS: 0.000 (setup and hold met) |
| Bitstream | sixteen_core_noc_v12b_ila.bit (md5 in bitstream/md5.txt); probes sixteen_core_noc_v12b_ila.ltx (here) |
| Feature word | 0xF10A_00FF (status bits 16-19: watchdog, exp-PSC bypass, delay-slot overflow, Phase-2 fallback) |

## What is here
- rtl_simulated/: the sources the simulation gates proved (fixes 1-28 and plasticity).
- rtl_built/: the sources Vivado synthesized: rtl_simulated plus the 22 capture taps on core 1 and the top-level tie-offs.
- ip/: every IP configuration. hbm_register_slice is mode 15 (Multi_SLR_Crossing), one SLR crossing, one pipeline stage on
  the HBM side of every channel (v12 failed timing on the HBM-to-slice wires without it; round 34 proved it changes no result).
- constraints/, project/multi_core.xpr: the project as built.
- kits/: the build (build_v12_kit, build_v12b_kit, ila_kit), the slice regeneration (slice_kit), the simulation gates
  (round33_kit; slice_kit/sim_round34.sh), the backup and restore proof (backup_v12_kit), the 16-core testbench (noc16_kit).
- verification/: round 33 and round 34 gate logs (both PASS), the 16-core position gate.
- build_reports/: placement and routing utilization and timing.
- software/: where the software used with this bitstream lives (branch v12b_tested in hs_bridge, hs_api and
  connectome_utils), and software/state/: each repository's branch, commit and uncommitted changes at test time.

## Reproduce
The self-contained Vivado archive (with the restore proof) and the full working tree are kept in /data/omowuyi/backups on
crisdsc3 (v12b_replication_*, v12b_tree_*). To rebuild from it, follow that package's README. From this repository: create
the project from project/multi_core.xpr with rtl_built/, ip/ and constraints/, then run kits/build_v12b_kit (trial, then finish).
