# HiAER-Spike Software Reference
## Packet Formats, Bit Fields, HBM Organization, and Test Design Guide

**For:** Software Team (Gwen, Christopher, connectome_utils/hs_api/hs_bridge)  
**From:** Omowuyi Olajide (Hardware)  
**Date:** June 2026  
**Hardware Version:** NoC-integrated 16-core (builds on multicore_4 baseline)  
**Software Baseline:** hs_api e526b6f (testing-suite) · hs_bridge 1e3a114 · connectome_utils 181f8a8 (dev)

---

## 1. System Parameters

| Parameter | Value |
|-----------|-------|
| Cores per FPGA | 16 (Core 0–15) |
| Neurons per core | 131,072 (17-bit address, 0x00000–0x1FFFF) |
| HBM per core | 512 MB (dedicated pseudo-channel, per-core relative addressing) |
| HBM row address | 23 bits (relative to core's partition) |
| HBM data width | 256 bits per row (8 × 32-bit entries) |
| URAM per core | 16 banks × 4,096 × 72 bits (16 neuron groups × 8,192 neurons/group) |
| Membrane potential | 32 bits [31:0] (signed) |
| Refractory counter | 3 bits [34:32] in URAM (decrements each timestep, suppresses spike when >0) |
| Axon BRAM | 8,192 × 16 bits (one-hot encoded, double-buffered present/future) |
| Spike FIFO depth | 512 entries per neuron group (8 FIFOs) |
| Pointer FIFO depth | 512 entries (16 banks) |
| Clock: aclk | 125 MHz (CI, IEP, EEP, NoC) |
| Clock: aclk450 | 250 MHz (HBM processor, spike FIFOs) |
| PCIe | Gen3 ×16 via XDMA, 512-bit AXI-Stream |

---

## 2. PCIe DMA Routing (Host → FPGA)

Each DMA write is a 512-byte transfer = 64 × uint64 elements = 8 AXI beats of 64 bytes.

The `pcie_tdest_generator` module uses a beat counter (mod 8). On **beat 7**, it latches the core ID from `tdata[387:384]`, which corresponds to element 62 of the uint64 array (raw byte offset 496).

**Software requirement:** When constructing the 64-element uint64 array for dma_dump_write, place the target core ID in the lower 4 bits of element 62:

```python
data = np.zeros(64, dtype=np.uint64)
data[62] = core_id & 0xF  # bits 3:0 = core ID (0-15)
# ... fill other elements with command data ...
dma_dump_write(data)
```

The AXI-Stream switch routes the 512-bit packet to the specified core_wrapper instance based on tdest.

**coreBits encoding for hs_api:** `coreBits = '000' + np.binary_repr(coreID, 5)`

---

## 3. PCIe Command Formats (Host → FPGA, 512 bits)

All commands are 512 bits wide. Bits [511:504] = opcode byte. Core routing via element 62 of DMA array (see Section 2).

### 3.1 Command 0x01: Execute Time Step

| Bits | Field | Value |
|------|-------|-------|
| 511:504 | Command | 0x01 |
| 503:0 | Reserved | All zeros |

Triggers single timestep execution. Broadcast to all cores (no core-specific routing needed for execution).

### 3.2 Command 0x02: HBM Read/Write

| Bits | Field | Description |
|------|-------|-------------|
| 511:504 | Command | 0x02 |
| 503:280 | Reserved | zeros |
| 279 | R/W | 0 = Read, 1 = Write |
| 278:256 | Row Address | 23-bit address, **per-core relative** (row 0 on core 0 ≠ row 0 on core 5) |
| 255:0 | Data | 256-bit write data (for write only) |

**Critical:** Row addressing is per-core relative. Each core has its own isolated HBM pseudo-channel. The core is selected by the DMA routing (element 62), not by the row address.

CI extracts: `ci2hbm_din = rxFIFO_dout[279:0]` → bit 279 = R/W, bits 278:256 = row, bits 255:0 = data.

### 3.3 Command 0x03: URAM Read/Write

| Bits | Field | Description |
|------|-------|-------------|
| 511:504 | Command | 0x03 |
| 53 | R/W | 0 = Read, 1 = Write |
| 52:36 | Neuron Address | 17-bit neuron address (0–131071) |
| 35:0 | Data | 36-bit membrane potential (for write) |

CI extracts: `ci2iep_din = rxFIFO_dout[53:0]`

### 3.4 Command 0x04: Write Network Parameters

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 511:504 | Command | 8 | 0x04 |
| 503:84 | Reserved | 420 | zeros |
| 83:78 | Leak | 6 | Leak rate parameter |
| 77:72 | Shift | 6 | Noise shift (shift=-17 disables PRBS noise, does NOT scale weights) |
| 71:70 | Neuron Model | 2 | 0=LIF, 1=ALIF |
| 69:34 | Threshold | 36 | Signed firing threshold |
| 33:17 | Num Outputs | 17 | Number of output neurons (spike FIFO scan range) |
| 16:0 | Num Inputs | 17 | Number of input axons (axon BRAM scan range) |

### 3.5 Command 0x06: Execute Step

| Bits | Field | Value |
|------|-------|-------|
| 511:504 | Command | 0x06 |
| 503:0 | Reserved | zeros |

### 3.6 Command 0x07: Execute Continuous

| Bits | Field | Description |
|------|-------|-------------|
| 511:504 | Command | 0x07 |
| 503:32 | Reserved | zeros |
| 31:0 | execRun_limit | Number of timesteps to execute continuously |

### 3.7 Command 0x08: Write Neuron Parameter Memory

| Bits | Field | Description |
|------|-------|-------------|
| 511:504 | Command | 0x08 |
| 503:84 | Reserved | zeros |
| 83:0 | Data | Neuron parameter data (auto-incrementing address) |

Neuron parameter memory fields (per neuron):

| Bits | Field | Description |
|------|-------|-------------|
| 20:17 | delay_value | 4-bit synaptic delay (0 = no delay) |
| 16:14 | refractory_max | 3-bit max refractory period (0 = disabled) |
| 8 | soft_reset_en | 1 = subtract threshold on spike (instead of reset to 0) |

### 3.8 Command 0x09: Set FIFO Timeout

| Bits | Field | Description |
|------|-------|-------------|
| 511:504 | Command | 0x09 |
| 27:0 | Timeout | Timeout value in clock cycles (at 125 MHz) |

### 3.9 Command 0x0A: Read Error Status

| Bits | Field | Value |
|------|-------|-------|
| 511:504 | Command | 0x0A |

Returns 32-bit sticky error register via C2H.

### 3.10 Command 0x0B: Clear Error Status

| Bits | Field | Value |
|------|-------|-------|
| 511:504 | Command | 0x0B |

Clears all sticky error bits.

### 3.11 Command 0x0D: Write Routing Table Entry (NEW)

| Bits | Field | Description |
|------|-------|-------------|
| 511:504 | Command | 0x0D |
| 503:18 | Reserved | zeros |
| 17:10 | Entry Address | Routing table index (0–255), corresponds to spike_addr[16:9] |
| 9:8 | Level | 00=NOP (drop), 01=LOCAL (host only), 10=L1 (intra-cluster), 11=L2 (inter-cluster) |
| 7:4 | Primary Mask | L1: target core bitmask within cluster. L2: target cluster bitmask |
| 3:0 | Secondary Mask | L2 only: per-core bitmask within destination clusters. L1: unused |

**Default:** All 256 entries = 10'b01_0000_0000 (LOCAL, no masks). NoC is invisible until routing tables are explicitly loaded.

**Routing table granularity:** 256 entries indexed by addr[16:9] means each entry covers 512 neurons (2^9). Neurons 0–511 share entry 0, neurons 512–1023 share entry 1, etc.

**Example — Route neuron group 0 (neurons 0–511) from core 0 to core 3 via L1:**
```python
entry_addr = 0  # neurons 0-511
level = 0b10    # L1 (intra-cluster)
primary_mask = 0b1000  # core 3 (bit 3)
secondary_mask = 0b0000  # unused for L1
entry_data = (level << 8) | (primary_mask << 4) | secondary_mask
# entry_data = 0x280

# Build 512-bit command
data = np.zeros(64, dtype=np.uint64)
data[62] = 0  # target core 0 (the core whose routing table we're writing)
data[63] = 0x0D  # opcode
data[0] = (entry_addr << 10) | entry_data  # bits [17:10]=addr, [9:0]=entry
dma_dump_write(data)
```

---

## 4. FPGA → Host Response Formats (512 bits)

### 4.1 Spike Output Packet (Header: 0xEEEEEEEE)

| Bits | Field | Description |
|------|-------|-------------|
| 511:480 | Header | 0xEEEE_EEEE (identifies spike packet) |
| 479:32 | Spike Data | 14 × 32-bit individual spike packets |
| 31:0 | execRun_ctr | Full 32-bit execution run counter (timestamp) |

**Individual Spike Packet (32 bits) — 14 per PCIe packet:**

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:24 | Timestamp | 8 | execRun_ctr[7:0] |
| 23 | Valid | 1 | 1 = valid spike, 0 = padding (ignore this entry) |
| 22:21 | FPGA_ID | 2 | Reserved (currently 00) |
| 20:17 | CORE_ID | 4 | Source core (0–15) — identifies which core fired |
| 16:0 | Neuron Address | 17 | Spiked neuron address within that core (0–131071) |

**Software spike decoding:**
```python
def decode_spike(spike_32bit):
    valid    = (spike_32bit >> 23) & 0x1
    core_id  = (spike_32bit >> 17) & 0xF      # CORE_ID from bits [20:17]
    neuron   = spike_32bit & 0x1FFFF           # mask lower 17 bits
    # CRITICAL: always mask with 0x1FFFF — CI embeds CORE_ID at [20:17]
    global_neuron = core_id * 131072 + neuron
    return valid, core_id, neuron, global_neuron
```

### 4.2 Execution Done Packet (Header: 0xABCDABCD)

| Bits | Field | Description |
|------|-------|-------------|
| 511:480 | Header | 0xABCD_ABCD |
| 479:32 | Spike Data | Final spike packets (may be partially filled) |
| 31:0 | execRun_ctr | Final timestamp |

### 4.3 HBM Read Response (Header: 0xBBBB)

| Bits | Field | Description |
|------|-------|-------------|
| 511:496 | Header | 0xBBBB |
| 495:256 | Reserved | zeros |
| 255:0 | Data | 256-bit HBM data (8 × 32-bit entries) |

### 4.4 URAM Read Response (Header: 0xCCCC)

| Bits | Field | Description |
|------|-------|-------------|
| 511:496 | Header | 0xCCCC |
| 495:53 | Reserved | zeros |
| 52:36 | Neuron Address | 17-bit neuron address that was read |
| 35:0 | Membrane Potential | 36-bit value (32-bit MP at [31:0], refractory at [34:32]) |

### 4.5 Latency Counter (Header: 0xBABABABA)

| Bits | Field | Description |
|------|-------|-------------|
| 511:480 | Header | 0xBABA_BABA |
| 31:0 | Latency | Clock cycles during execution |

### 4.6 HBM Access Counter (Header: 0xCABACABA)

| Bits | Field | Description |
|------|-------|-------------|
| 511:480 | Header | 0xCABA_CABA |
| 31:0 | Count | Number of HBM accesses during execution |

---

## 5. HBM Memory Organization

### 5.1 Per-Core HBM Structure

Each core has independent, isolated access to its HBM pseudo-channel via a 33-bit AXI address bus and 256-bit data bus. Row addresses are per-core relative (row 0 on core 0 is physically different from row 0 on core 5).

**HBM data layout per core:**

| HBM Row Range | Content | Loaded by |
|---------------|---------|-----------|
| 0 to N_axons-1 | Axon pointer table | Command 0x02 (write) |
| N_axons to N_axons+N_neurons-1 | Neuron pointer table | Command 0x02 (write) |
| After pointer tables | Synapse data rows | Command 0x02 (write) |

### 5.2 Axon Pointer (32 bits, within 256-bit HBM row)

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:23 | Length | 9 | Number of synapse rows for this axon (0–511) |
| 22:0 | Address | 23 | Starting HBM row address for this axon's synapses |

Each 256-bit HBM row contains 8 pointers (8 × 32b = 256b).

### 5.3 Neuron Pointer (32 bits, same format as axon pointer)

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:23 | Length | 9 | Number of synapse rows targeting this neuron |
| 22:0 | Address | 23 | Starting HBM row address for synapses |

### 5.4 Synapse Entry (32 bits, 8 per 256-bit HBM row)

**Opcode [31:29] determines synapse type:**

**LOCAL (opcode = 000):** Standard intra-core synapse.

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:29 | Opcode | 3 | 000 |
| 28:16 | Target Neuron | 13 | Target neuron address within this core (0–8191) |
| 15:0 | Weight | 16 | Signed 16-bit synaptic weight |

**INTER_CORE (opcode = 001):** Inter-core synapse via NoC. **NEW — now implemented in hardware.**

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:29 | Opcode | 3 | 001 |
| 28:25 | Dst Core | 4 | Target core ID (0–15) |
| 24:8 | Relay Address | 17 | Relay axon address on the destination core |
| 7:0 | Reserved | 8 | 0x00 |

**How INTER_CORE works:** When the HBM processor encounters opcode 001 during Phase 2, it writes the 17-bit relay address to the spike FIFO (same path as SPIKE_OUT). The NoC routing table then routes this spike to the destination core. On the destination core, the relay address maps to a relay axon in the axon BRAM, which has its own pointer table and synapse entries. The weight is stored in the DESTINATION core's synapse table, not carried in the spike.

**Software requirement for INTER_CORE:** The network partitioner must: (1) assign relay axon indices on the destination core, (2) create pointer/synapse entries for relay axons on the destination core's HBM, (3) write INTER_CORE synapse entries on the source core's HBM with the correct dst_core and relay_address, (4) configure the routing table on the source core so the relay address range routes to the target core.

**INTER_FPGA (opcode = 010):** Inter-FPGA synapse via Firefly. Defined but NOT yet implemented in HBM processor.

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:29 | Opcode | 3 | 010 |
| 28:0 | Routing Info | 29 | TBD (will contain dst_fpga, dst_core, relay_addr) |

**SPIKE_OUT (opcode = 100):** Spike output marker. Triggers spike detection in HBM processor.

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 31:29 | Opcode | 3 | 100 |
| 28:17 | Reserved | 12 | zeros |
| 16:0 | Spike Address | 17 | Source neuron address that fired |

**IEP behavior:** The IEP receives 512 bits (16 synapse entries) via exec_hbm_rdata. It processes each entry by adding the 16-bit weight to the URAM at the 13-bit target address. INTER_CORE entries are zeroed out by the HBM processor before reaching the IEP, so the IEP sees weight=0 and address=0, which has no effect. SPIKE_OUT entries have opcode bit 31=1; the IEP ignores these for weight accumulation.

### 5.5 Synapse Storage Layout

Each 256-bit HBM row = 8 × 32-bit synapse entries.

| Byte Position in 256-bit row | Entry | Bits |
|------------------------------|-------|------|
| [31:0] | Entry 0 | [31:29]=opcode, [28:16]=addr, [15:0]=weight |
| [63:32] | Entry 1 | Same format |
| [95:64] | Entry 2 | Same format |
| [127:96] | Entry 3 | Same format |
| [159:128] | Entry 4 | Same format |
| [191:160] | Entry 5 | Same format |
| [223:192] | Entry 6 | Same format |
| [255:224] | Entry 7 | Same format |

The HBM processor reads two 256-bit rows per cycle (512 bits = 16 entries) and sends them to the IEP as exec_hbm_rdata[511:0].

---

## 6. Execution Flow (What the Software Must Do)

### 6.1 Network Initialization Sequence

For each core (core_id = 0 to 15):

1. **Write network parameters** (0x04): Set leak, shift, threshold, neuron model, num_inputs, num_outputs
2. **Write neuron parameter memory** (0x08): Set refractory_max, delay_value, soft_reset_en per neuron
3. **Write axon pointer table** (0x02): Rows starting at address 0, each row = 8 pointers
4. **Write neuron pointer table** (0x02): Rows following axon pointers
5. **Write synapse data** (0x02): Rows at addresses specified by pointers
6. **Write routing table** (0x0D, NEW): 256 entries specifying how outgoing spikes are routed

### 6.2 Execution Sequence

1. **Send input** (bit 504=1 initial, then 0x00 data): One-hot encoded active axons per core
2. **Execute** (0x01 or 0x06 or 0x07): Triggers micro-pipelined processing
3. **Read spikes**: Parse C2H stream for 0xEEEEEEEE packets, extract CORE_ID and neuron address
4. **Read membrane** (0x03, optional): Verify neuron states

### 6.3 Multi-Core Considerations

- Each core is independently addressable via element 62 of the DMA array
- DMA padding wrapper: pad all dma_dump_write calls to 64-element multiples (DISABLED for DVS large due to errant packets on multi-group commands >64 elements)
- HIAER_CORE_ID environment variable must be set for each test file
- For DVS models: shift=0 must be converted to shift=-17 (L6d noise semantics), legacy_noise_en=1 (35-bit mode)

---

## 7. NoC Routing (for Inter-Core Test Design)

### 7.1 Two Routing Modes

**Source-side routing (routing table):** When a neuron fires, the routing table (indexed by addr[16:9]) determines if/where to send the spike on the NoC. Configured via CMD 0x0D.

**Synapse-level routing (HBM INTER_CORE):** When the HBM processor reads a synapse with opcode 001, it generates a spike to the target core with the relay address. The routing table must be configured to route the relay address range to the target core.

Both modes can be used simultaneously. Both modes use the same spike FIFO → CDC FIFO → router → L1/L2 crossbar → injector → EEP relay FIFO path.

### 7.2 Cluster and Core Mapping

| Core ID | Cluster | Local Index | Cluster ID |
|---------|---------|-------------|------------|
| 0 | 0 | 0 | 0 |
| 1 | 0 | 1 | 0 |
| 2 | 0 | 2 | 0 |
| 3 | 0 | 3 | 0 |
| 4 | 1 | 0 | 1 |
| 5 | 1 | 1 | 1 |
| 6 | 1 | 2 | 1 |
| 7 | 1 | 3 | 1 |
| 8 | 2 | 0 | 2 |
| 9 | 2 | 1 | 2 |
| 10 | 2 | 2 | 2 |
| 11 | 2 | 3 | 2 |
| 12 | 3 | 0 | 3 |
| 13 | 3 | 1 | 3 |
| 14 | 3 | 2 | 3 |
| 15 | 3 | 3 | 3 |

**L1 routing (level=10):** Routes within a cluster. Primary mask bits [3:0] select which local cores receive the spike. Cores 0–3 are in cluster 0, cores 4–7 in cluster 1, etc.

**L2 routing (level=11):** Routes across clusters. Primary mask bits [3:0] select which clusters. Secondary mask bits [3:0] select which cores within each destination cluster.

### 7.3 Example: Simple 2-Core NoC Test

Test core 0 → core 1 spike delivery:

```python
# 1. Load a small network on core 0
#    - 10 neurons, some configured to spike
#    - Routing table: neurons 0-511 → L1, target core 1
write_route_table_entry(core_id=0, entry_addr=0,
    level=0b10, primary_mask=0b0010, secondary_mask=0b0000)
# entry = (0b10 << 8) | (0b0010 << 4) | 0b0000 = 0x220

# 2. Load relay axons on core 1
#    - Relay axon at address matching the spike address from core 0
#    - Relay axon has pointer → synapses → target local neurons

# 3. Execute both cores simultaneously

# 4. Read core 1's membrane potentials
#    - Should show accumulated weights from core 0's spikes
```

---

## 8. Inter-FPGA Spike Packet (64 bits, Aurora)

For future Firefly integration. Software must generate routing tables that account for inter-FPGA destinations.

| Bits | Field | Width | Description |
|------|-------|-------|-------------|
| 63:61 | Opcode | 3 | 000=SPIKE, 001=SYNC, 010=CONFIG, 011=STATUS, 100=CREDIT, 111=NOP |
| 60:58 | Dst Server | 3 | Destination server ID (0–7) |
| 57:55 | Dst FPGA | 3 | Destination FPGA within server (0–7) |
| 54:51 | Dst Core | 4 | Destination core within FPGA (0–15) |
| 50:34 | Dst Neuron | 17 | Destination neuron address (0–131071) |
| 33:31 | Src FPGA | 3 | Source FPGA ID |
| 30:27 | Src Core | 4 | Source core ID |
| 26:19 | Timestamp | 8 | Timestep counter (modulo 256) |
| 18:16 | TTL | 3 | Time-to-live (decremented per hop, drop at 0) |
| 15:0 | Payload | 16 | Weight or additional flags |

**Addressing capacity:** 8 servers × 8 FPGAs × 16 cores × 131,072 neurons = 134,217,728 neurons.

---

## 9. Inter-Server Ethernet Frame

For future 100G CMAC integration via s64 switch (Arista 7170, P4 Tofino).

| Field | Size | Description |
|-------|------|-------------|
| Dst MAC | 6 bytes | Encodes target FPGA or multicast group |
| Src MAC | 6 bytes | Encodes source FPGA + server ID |
| EtherType | 2 bytes | 0x88B5 (local experimental use) |
| Version + Flags | 2 bytes | Protocol version, multicast flag, partition ID |
| Src Core ID | 2 bytes | Source core (0–15) |
| Dst Core ID | 2 bytes | Target core(s) |
| Timestamp | 4 bytes | Sub-ms resolution within 1ms timestep |
| Spike Count | 4 bytes | Number of 64-bit spike events in payload |
| Spike Payload | N × 8 bytes | Array of 64-bit spike events (same as Aurora format) |
| FCS | 4 bytes | Auto-generated by CMAC |

**s64 switch processing:** The P4 Tofino ASIC parses the custom Ethernet frame, extracts destination FPGA ID, and forwards to the correct output port. It supports unicast, multicast (one spike → multiple FPGAs), mirroring (debug copy), and partition isolation (different research jobs on different FPGA subsets).

---

## 10. Known Issues and Compatibility

### 10.1 Software API Mismatches (9 of 42 test failures)

Tests `test_refractory_period` and `test_synaptic_delay` fail because hs_bridge 1e3a114 lacks `refractory_max` and `dual_synapse_en` parameters that the testing-suite branch tests expect. These are software API gaps, not hardware failures. The hardware correctly implements both features.

### 10.2 DMA Padding

All dma_dump_write calls must be padded to 64-element multiples (512 bytes). This is handled by the universal DMA padding wrapper in fpga_controller.py. **Exception:** DVS large model tests must DISABLE padding because multi-group commands with >64 elements generate errant packets.

### 10.3 DVS Model Configuration

For L6j/L6m hardware, the DVS model config must use:
- `shift=-17` (not shift=0; this disables PRBS noise)
- `legacy_noise_en=1` (35-bit noise mode)
- Model file: `DVS_model_config_shift=0.pkl` (109,615 neurons, full model)

### 10.4 FPGA Power Cycle

For PCIe enumeration failures after programming: `sudo shutdown -h now`, wait 30 seconds, power on (not just reboot). Then re-bind PCIe driver with `echo "4144 903f" > /sys/bus/pci/drivers/xdma/new_id`.

---

## 11. Global Neuron Addressing

```
Global Neuron ID = (CORE_ID × 131,072) + neuron_address

Example: Core 5, Neuron 1000 → Global ID = 5 × 131,072 + 1,000 = 656,360
```

Total per FPGA: 16 cores × 131,072 = 2,097,152 neurons
Total system: 41 FPGAs × 2,097,152 = 85,983,232 neurons (at 16 cores/FPGA)

---

## 12. Git Repositories

| Repository | URL | Branch | Hash |
|-----------|-----|--------|------|
| hs_api | (testing-suite) | testing-suite | e526b6f |
| hs_bridge | (main) | main | 1e3a114 |
| connectome_utils | (dev) | dev | 181f8a8 |
| Hardware (Omowuyi) | github.com/Omowuyi/hiaer-spike-hardware | main | — |
| Hardware (Lab) | github.com/Integrated-Systems-Neuroengineering/HiAER-Spike-Hardware | main | — |

---

## 13. Contact

- **Hardware (NoC, FPGA, bitstream):** Omowuyi Olajide
- **Software (hs_api, testing-suite):** Christopher Deng
- **Software (connectome_utils, partitioning):** Gwen
- **Multicore/NoC collaboration:** Paresh Kurdekar Vasanth
- **Advisor:** Leif Gibb
- **SDSC/NSG:** Kenneth Yoshimoto
