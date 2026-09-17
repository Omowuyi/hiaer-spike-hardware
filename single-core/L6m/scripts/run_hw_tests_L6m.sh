#!/bin/bash
# Run 42 hardware tests on L6m single-core bitstream
# Expected: 42/42 passed
set -e
cd /home/omowuyi/testing/hs_api
source .venv/bin/activate
export PYTHONPATH=/home/omowuyi/testing/hs_bridge

# Restore baseline software (no multicore patches needed for single-core)
BACKUP="/home/omowuyi/L6m_single_core_backup/software/baseline"
cp "$BACKUP/api.py" hs_api/api.py
cp "$BACKUP/neuron_models.py" hs_api/neuron_models.py
cp "$BACKUP/fpga_controller.py" /home/omowuyi/testing/hs_bridge/hs_bridge/FPGA_Execution/fpga_controller.py
cp "$BACKUP/network.py" /home/omowuyi/testing/hs_bridge/hs_bridge/network.py
cp "$BACKUP/test_bitstream_hardware_fast.py" tests/test_bitstream_hardware_fast.py
rm -f tests/conftest.py

find /home/omowuyi/testing -name "__pycache__" -exec rm -rf {} + 2>/dev/null

cd tests
pytest test_bitstream_hardware_fast.py -v
