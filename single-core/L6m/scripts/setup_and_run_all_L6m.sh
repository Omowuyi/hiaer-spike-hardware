#!/bin/bash
# Complete L6m single-core: flash + restore + run all 3 tests
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Step 1: Flash L6m ==="
bash "$DIR/flash_L6m.sh"

echo "=== Step 2: Run 42 hardware tests ==="
bash "$DIR/run_hw_tests_L6m.sh"

echo "=== Step 3: Run DVS small ==="
bash "$DIR/run_dvs_small_L6m.sh"

echo "=== Step 4: Run DVS large (~90 min) ==="
bash "$DIR/run_dvs_large_L6m.sh"

echo ""
echo "=== ALL L6m TESTS COMPLETE ==="
