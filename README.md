# HiAER-Spike Hardware Platform

**Neuromorphic Computing on Xilinx VU37P FPGA (ADM-PCIE-9H7)**

## Overview

HiAER-Spike implements spiking neural networks with leaky integrate-and-fire (LIF) neurons on FPGA. The system supports configurable synaptic weights, refractory periods, synaptic delays, noise injection, and multi-core scaling.

This repository documents every hardware bitstream version, every RTL edit, the corresponding software configuration for each version, and the multicore scaling path from single-core through 16-core to the full 40-FPGA cluster.

## Architecture

Each neuromorphic core contains: an Internal Events Processor (IEP) for neuron evaluation, a Command Interpreter (CI) for DMA packet parsing, an External Events Processor (EEP) for spike I/O, an HBM Processor for synapse weight storage, 16 URAMs for membrane potential storage, and Parameter Memory (BRAM) for neuron type configurations.

The host communicates via PCIe Gen3 x16 through XDMA, with an AXI-Stream switch fabric routing commands to individual cores. In the definitive multicore_4 bitstream, the `pcie_tdest_generator` uses a beat counter (mod 8) to extract coreID from `tdata[387:384]` on beat 7 of each 8-beat (512-byte) DMA transfer.

## Current Status

| Bitstream       | Cores | HW Tests         | DVS Small | DVS Full  | Status                              |
|-----------------|-------|------------------|-----------|-----------|-------------------------------------|
| 2024 reference  | 1     | N/A              | N/A       | 64.24%    | Accuracy target (XDMA v4.1.4)      |
| L6m             | 1     | 42/42            | 44.44%    | 56.60%    | Verified single-core baseline       |
| multicore_1     | 16    | 42/42 core0 only | -         | -         | tdest [503:499] bug                 |
| multicore_2     | 16    | 42/42 core0 only | -         | -         | tdest [499:496] wrong byte position |
| multicore_3     | 16    | 42/42 core0 only | -         | -         | Registered tdest, wrong check byte  |
| **multicore_4** | 16    | **42/42 ALL 16** | **44.44% all 16** | pending | **Beat-7 counter - DEFINITIVE**     |

## Quick Start

See `docs/09_reproduction_guide.md` for complete step-by-step instructions for every bitstream.

## Documentation

- `docs/01_bitstream_history.md` - Every bitstream version with RTL edits and software config
- `docs/03_neuron_parameter_encoding.md` - write_neuron_type bit field layout
- `docs/05_multicore_design.md` - 16-core architecture, routing fix, and validation
- `docs/06_dvs_accuracy.md` - DVS accuracy gap root cause analysis
- `docs/07_roadmap.md` - NoC, Firefly, 40-FPGA cluster plan
- `docs/08_lessons_learned.md` - Critical debugging lessons
- `docs/09_reproduction_guide.md` - Step-by-step test reproduction for ALL bitstreams

## Software Dependencies

| Component        | Commit/Branch               | Repository                                    |
|------------------|-----------------------------|-----------------------------------------------|
| hs_api           | `e526b6f` (testing-suite)   | Integrated-Systems-Neuroengineering/hs_api    |
| hs_bridge        | `1e3a114`                   | (internal)                                    |
| connectome_utils | `181f8a8` (dev)             | Integrated-Systems-Neuroengineering/connectome_utils |

## Machines

| Machine   | Role                                | Key Software            |
|-----------|-------------------------------------|-------------------------|
| crisdsc2  | Vivado builds, RTL development      | Vivado 2024.1           |
| crisdsc0  | FPGA testing, software development  | Python 3.10, ADXDMA     |

## Contacts

- **Omowuyi Olajide** (omowuyi@gmail.com)
