#!/bin/bash
# ============================================================
# HiAER-Spike Complete Test Script
# ============================================================
# Usage:
#   bash run_all_tests.sh L6j    # Test L6j bitstream
#   bash run_all_tests.sh L6m    # Test L6m bitstream
# ============================================================
set -e

BITSTREAM_NAME="${1:-L6j}"

if [ "$BITSTREAM_NAME" == "L6j" ]; then
    BITSTREAM="/bitstreams/sixteen_core_top_L6j.bit"
elif [ "$BITSTREAM_NAME" == "L6m" ]; then
    BITSTREAM="/bitstreams/sixteen_core_top_L6m.bit"
else
    echo "Usage: bash run_all_tests.sh [L6j|L6m]"
    exit 1
fi

echo "============================================"
echo "  HiAER-Spike Test Suite: $BITSTREAM_NAME"
echo "============================================"

# Step 1: Flash bitstream
echo ""
echo "[Step 1/6] Flashing $BITSTREAM_NAME bitstream..."
sudo /bitstreams/scripts/flash.sh "$BITSTREAM"
sleep 3
echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null
sleep 3
sudo modprobe adxdma
echo "4144 0902" | sudo tee /sys/bus/pci/drivers/adxdma/new_id > /dev/null 2>&1 || true
sudo chmod 666 /dev/adxdma0*
echo "  Bitstream flashed and PCIe configured."

# Step 2: Setup environment
echo ""
echo "[Step 2/6] Setting up software environment..."
cd /home/omowuyi/testing/hs_api
source .venv/bin/activate
export PYTHONPATH=/home/omowuyi/testing/hs_bridge

# Step 3: Restore working software from backup
echo ""
echo "[Step 3/6] Restoring working software from L6j_working_software backup..."
cp /home/omowuyi/L6j_working_software/api.py hs_api/api.py
cp /home/omowuyi/L6j_working_software/neuron_models.py hs_api/neuron_models.py
cp /home/omowuyi/L6j_working_software/fpga_controller.py /home/omowuyi/testing/hs_bridge/hs_bridge/FPGA_Execution/fpga_controller.py
cp /home/omowuyi/L6j_working_software/network.py /home/omowuyi/testing/hs_bridge/hs_bridge/network.py
cp /home/omowuyi/L6j_working_software/test_bitstream_hardware_fast.py tests/test_bitstream_hardware_fast.py
echo "  Software restored."

# Step 4: Patch DVS test if needed
echo ""
echo "[Step 4/6] Patching DVS test (shift=0→-17, legacy_noise_en=1)..."
python3 << 'PYEOF'
T = '/home/omowuyi/testing/hs_api/tests/test_DVS_large_fulldataset_2024.py'
with open(T) as f: t = f.read()
if 'neuron_obj.shift = -17' not in t:
    old = '        network = CRI_network('
    ins = """        # Convert shift=0 to shift=-17 (L6d noise semantics) and enable legacy noise
        for key in connections:
            neuron_obj = connections[key][1]  # modelIdx=1
            if hasattr(neuron_obj, 'shift') and neuron_obj.shift == 0:
                neuron_obj.shift = -17
            neuron_obj.legacy_noise_en = 1

"""
    t = t.replace(old, ins + old, 1)
    with open(T, 'w') as f: f.write(t)
    print('  DVS test patched.')
else:
    print('  DVS test already patched.')
PYEOF

# Step 5: Run 42 hardware tests
echo ""
echo "[Step 5/6] Running 42 hardware tests (~5 min)..."
find /home/omowuyi/testing -name "__pycache__" -exec rm -rf {} + 2>/dev/null
cd /home/omowuyi/testing/hs_api/tests
pytest test_bitstream_hardware_fast.py -v 2>&1 | tee pytest_${BITSTREAM_NAME}_hw.log
echo ""
HW_RESULT=$(tail -1 pytest_${BITSTREAM_NAME}_hw.log)
echo "Hardware test result: $HW_RESULT"

if echo "$HW_RESULT" | grep -q "42 passed"; then
    echo "  ✓ All 42 hardware tests PASSED"
else
    echo "  ✗ Hardware tests FAILED - stopping here"
    exit 1
fi

# Step 6: Run DVS full dataset test
echo ""
echo "[Step 6/6] Running DVS full dataset test (~90 min)..."
echo "  Expected accuracy: ~56.60% (Vivado 2024.1 XDMA v4.1.29 ceiling)"
find /home/omowuyi/testing -name "__pycache__" -exec rm -rf {} + 2>/dev/null
cd /home/omowuyi/testing/hs_api/tests
nohup pytest -s test_DVS_large_fulldataset_2024.py > pytest_${BITSTREAM_NAME}_dvs.log 2>&1 &
DVS_PID=$!
echo "  DVS test running (PID: $DVS_PID)"
echo ""
echo "  Monitor progress:"
echo "    grep 'Running accuracy' tests/pytest_${BITSTREAM_NAME}_dvs.log | tail -1"
echo ""
echo "  Check final result:"
echo "    tail -10 tests/pytest_${BITSTREAM_NAME}_dvs.log"
echo ""
echo "============================================"
echo "  Hardware: 42/42 PASSED on $BITSTREAM_NAME"
echo "  DVS: running in background (PID: $DVS_PID)"
echo "============================================"
