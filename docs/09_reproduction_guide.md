# Test Reproduction Guide — Step-by-Step for Every Bitstream

This guide answers: "How do I run test X on bitstream Y?" for every combination.

---

## Software Dependencies (All Bitstreams)

| Component        | Commit Hash                              | Branch         |
|------------------|------------------------------------------|----------------|
| hs_api           | `e526b6fdcfea4cd0c0d2e7b16cb0134839dcd830` | testing-suite |
| hs_bridge        | `1e3a114`                                | (default)      |
| connectome_utils | `181f8a8`                                | dev            |

**Working software backup** (crisdsc0): `/home/omowuyi/L6j_working_software/`

---

## 1. Original 2024 Reference Bitstream

**Bitstream**: `/bitstreams/multi_neuron_type_param_mem_fix_08132024.bit`
**Vivado**: 2019.2 | **XDMA IP**: v4.1.4
**No software patches needed.**

### Flash
```bash
sudo /bitstreams/scripts/flash.sh /bitstreams/multi_neuron_type_param_mem_fix_08132024.bit
sleep 3; echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null
sleep 3; sudo modprobe adxdma
echo "4144 0902" | sudo tee /sys/bus/pci/drivers/adxdma/new_id > /dev/null 2>&1 || true
sudo chmod 666 /dev/adxdma0*
```

### Run 42 Hardware Tests
```bash
cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
export PYTHONPATH=/home/omowuyi/testing/hs_bridge
pytest tests/test_bitstream_hardware_fast.py -v
```

### Run DVS Large (Expected: 64.24%)
```bash
pytest -s tests/test_DVS_large_fulldataset_2024.py -v
# Uses DVS_model_config_shift=0.pkl (109,615 neurons)
# NO shift conversion needed — 2024 IEP uses unsigned shift natively
```

### FAQ: "Why doesn't the 2024 bitstream work for me?"
1. Wrong driver: Need `adxdma`, NOT `xdma`. Check: `lsmod | grep adxdma`
2. PCIe not enumerated: Must rescan after flash
3. Wrong branch: Must use testing-suite, not marchChange
4. Missing pickle: `DVS_model_config_shift=0.pkl` must be in tests/

---

## 2. L6m Single-Core Bitstream

**Bitstream**: `/bitstreams/sixteen_core_top_L6m.bit`
**Vivado**: 2024.1

### Run 42 Hardware Tests (Expected: 42/42)
```bash
# Flash (same procedure as above but with L6m bitstream)
# Restore software:
cp /home/omowuyi/L6j_working_software/{api.py,neuron_models.py} hs_api/
cp /home/omowuyi/L6j_working_software/fpga_controller.py /home/omowuyi/testing/hs_bridge/hs_bridge/FPGA_Execution/
cp /home/omowuyi/L6j_working_software/{network.py} /home/omowuyi/testing/hs_bridge/hs_bridge/
cp /home/omowuyi/L6j_working_software/test_bitstream_hardware_fast.py tests/
pytest tests/test_bitstream_hardware_fast.py -v
```

### Run DVS Large (Expected: 56.60%)
```bash
# Must patch DVS test for L6d noise semantics:
# shift=0 -> shift=-17, legacy_noise_en=1
# See software/patches/ for patch scripts
pytest -s tests/test_DVS_large_fulldataset_2024.py -v
```

**Why DVS patch needed**: L6m uses signed shift_param. shift=0 in pickle enables noise (wrong). Must convert to shift=-17 (disables noise) and set legacy_noise_en=1 (restores 35-bit MP mode).

---

## 3. Multicore_4 — 16-Core (Definitive)

**Bitstream**: `/bitstreams/sixteen_core_top_multicore_4.bit`
**Vivado**: 2024.1

### Run 42 HW Tests on ALL 16 Cores (Expected: 42/42 each)
```bash
# Flash multicore_4, then:
# 1. Restore from backup
cp /home/omowuyi/L6j_working_software/api.py hs_api/api.py
cp /home/omowuyi/L6j_working_software/neuron_models.py hs_api/neuron_models.py
cp /home/omowuyi/L6j_working_software/fpga_controller.py /home/omowuyi/testing/hs_bridge/hs_bridge/FPGA_Execution/
cp /home/omowuyi/L6j_working_software/network.py /home/omowuyi/testing/hs_bridge/hs_bridge/
cp /home/omowuyi/L6j_working_software/test_bitstream_hardware_fast.py tests/

# 2. Apply coreBits fix
python3 /home/omowuyi/fix_coreid_crisdsc0.py

# 3. Apply multicore fixes
python3 /home/omowuyi/fix_multicore_final_crisdsc0.py

# 4. Test all 16 cores
for CORE in $(seq 0 15); do
    echo "=== Core $CORE ==="
    find /home/omowuyi/testing -name "__pycache__" -exec rm -rf {} + 2>/dev/null
    HIAER_CORE_ID=$CORE pytest tests/test_bitstream_hardware_fast.py -v 2>&1 | tail -1
done
```

### Run DVS Small on ALL 16 Cores (Expected: 44.44% each)
```bash
# After applying multicore fixes, patch DVS files for HIAER_CORE_ID + shift fix
for CORE in $(seq 0 15); do
    HIAER_CORE_ID=$CORE pytest -s tests/test_DVS_small.py -v 2>&1 | tail -3
done
```

### Run DVS Large (Expected: ~56.60%, core 0 only)
```bash
# Must disable DMA padding wrapper (causes errant packets for multi-group commands)
# See docs/05_multicore_design.md for details
HIAER_CORE_ID=0 pytest -s tests/test_DVS_large_fulldataset_2024.py -v
```

---

## Patches Summary

| Bitstream | coreBits fix | Spike mask | DMA padding | HIAER_CORE_ID | DVS shift patch |
|-----------|:---:|:---:|:---:|:---:|:---:|
| 2024 ref  | - | - | - | - | - |
| L6m       | - | - | - | - | Yes |
| multicore_4 | Yes | Yes | Yes | Yes | Yes |
