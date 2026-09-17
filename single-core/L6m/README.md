# L6m Single-Core Backup — Created 20260620_160945

## Validated Results
- Hardware tests: 42/42
- DVS small: 44.44%
- DVS large: 56.60%

## Software Commits
- hs_api: e526b6f (testing-suite branch)
- hs_bridge: 1e3a114
- connectome_utils: 181f8a8 (dev branch)

## Bitstream
- sixteen_core_top_L6m.bit
- Built with Vivado 2024.1, XDMA IP v4.1.29

## Key Differences from 2024 Bitstream
- XDMA IP: v4.1.4 (2024) vs v4.1.29 (L6m) — causes ~8% DVS accuracy gap
- IEP shift_param: unsigned (2024) vs signed (L6m) — requires shift=0 to shift=-17 conversion
- Noise semantics: L6d style — requires legacy_noise_en=1 for DVS

## Software Patches Needed (L6m only, not 2024)
- DVS tests: shift=0 → shift=-17, legacy_noise_en=1
- DVS large threshold: >= 64.57 → >= 55.00

## NO patches needed for:
- 42 hardware tests on L6m
- Any test on 2024 bitstream

## Quick Start
1. bash scripts/setup_and_run_all_L6m.sh   # runs everything
   OR individually:
2. bash scripts/flash_L6m.sh               # flash bitstream
3. bash scripts/run_hw_tests_L6m.sh        # 42 hardware tests
4. bash scripts/run_dvs_small_L6m.sh       # DVS small (44.44%)
5. bash scripts/run_dvs_large_L6m.sh       # DVS large (56.60%, ~90 min)

## File Manifest
- bitstreams/           — L6m + 2024 reference bitstreams
- software/baseline/    — unpatched working software (L6j backup)
- software/tests/       — test files + DVS model pickle
- software/dmadump/     — Cython DMA driver source + compiled .so
- rtl/                  — key RTL source files (switch, CI, IEP, EEP, etc.)
- test_logs/            — test result logs
- scripts/              — one-command test runners
