# HiAER-Spike Hardware Platform

**Neuromorphic computing on the Xilinx Virtex UltraScale+ VU37P (ADM-PCIE-9H7).**

Spiking neural networks in FPGA fabric: configurable synaptic weights,
refractory periods, synaptic delay, noise injection, biological neuron dynamics,
and a scaling path from one core to 640 across five servers.

This repository holds the RTL that built each bitstream, the patches that
produced it, the host software it was tested against, and a record of what has
been verified and by what means.

---

## Repository structure

```
hiaer-spike-hardware/
│
├── README.md                    this file — start here
├── docs/                        platform-wide documentation
│   ├── 00_platform_reference.md     command set, packet formats, memory, servers
│   ├── 01_bitstream_history.md      every bitstream, its RTL edits, its software
│   ├── 02_architecture.md           timestep execution, URAM banking, spike path
│   ├── 03_neuron_parameter_encoding.md
│   ├── 04_verification_methodology.md   what "verified" means here
│   ├── 05_multicore_design.md
│   ├── 06_dvs_accuracy.md
│   ├── 07_roadmap.md
│   ├── 08_lessons_learned.md
│   ├── 09_reproduction_guide.md     step by step, per bitstream
│   └── HiAER_Software_Reference.md
│
├── single-core/                 one core per FPGA — where the neuron model lives
│   ├── README.md                    feature matrix across both designs
│   │
│   ├── L6m/                     frozen baseline · built crisdsc2 · 42/42
│   │   ├── README.md
│   │   ├── rtl/                     7 sources
│   │   └── scripts/                 5 flash and test scripts
│   │
│   └── exp_psc/                 biological model · built crisdsc3 · 42/42 + 8/8
│       ├── README.md
│       ├── MANIFEST.md              source hashes, timing, results
│       ├── rtl/                     51 files — 28 live plus .before_* history
│       ├── patches/                 11 anchor-verified RTL edits
│       │   └── failed/              3 attempts that failed on hardware
│       ├── software/
│       ├── tests/
│       └── docs/
│           ├── FIXES.md             F, J, U, V and the compiler fixes
│           ├── OPEN_ISSUES.md       microphase boundary, delay, STDP
│           └── SIM_FINDINGS.md
│
├── multi-core/                  sixteen cores and beyond
│   ├── README.md                    how the designs relate
│   │
│   ├── multicore_4/             16 cores, time-multiplexed · 672/672
│   │   └── MANIFEST.md              RTL source unlocated — bitstream only
│   │
│   ├── noc/                     16 cores, parallel crossbar · WNS +0.0078 ns
│   │   ├── README.md
│   │   ├── MANIFEST.md              every source hash, verified by bitstream MD5
│   │   ├── rtl/                     35 sources — 8 NoC, 27 core
│   │   ├── constrs/                 14 constraint files
│   │   ├── software/                the L6j-validated host software
│   │   ├── clock_and_buffer.bd      125 / 100 / 250 MHz
│   │   ├── fix_iep_delay.py
│   │   ├── timing_summary.txt
│   │   └── docs/
│   │       ├── NOC.md               routers, buses, entry format, FSM
│   │       ├── ROUTING_TABLES.md    the two incompatible formats
│   │       ├── PARTITIONING.md      λ−1 hypergraph, 512-neuron granules
│   │       └── VERIFICATION.md      what passed, in simulation and on hardware
│   │
│   ├── noc_exp_psc/             crossbar + biological cores + Firefly · unverified
│   │   ├── README.md
│   │   ├── MANIFEST.md              files by destination, apply order
│   │   ├── rtl/                     122 files — 42 live plus .before_* history
│   │   ├── patches/                 42 anchor-verified patches
│   │   ├── software/                compiler and routing host code
│   │   ├── sim/                     9 testbenches and run_xsim.sh
│   │   └── docs/
│   │
│   ├── firefly/                 inter-FPGA optical, 8 per server · design only
│   │   ├── README.md
│   │   └── docs/FIREFLY.md
│   │
│   └── server-to-server/        5 servers, 100G · design only
│       ├── README.md
│       └── docs/SYSTEM.md
│
├── software/                    host software, platform-wide
│   ├── baseline_L6m/                the L6m software state, for comparison
│   └── tests/                       hardware regression and DVS tests
│
├── bitstreams/
│   └── MANIFEST.md              index — .bit files are not committed
│
└── tools/
    ├── verify_rtl_state.py      22-check content-hash build gate
    ├── init_github_repo.sh
    └── migrate_repo_v2.sh
```

---

## Where each design was built

| design | built on | tested on | source in repo |
|---|---|---|---|
| L6m | crisdsc2 | crisdsc0 | `single-core/L6m/rtl/` |
| exp_psc | crisdsc3 | crisdsc0 | `single-core/exp_psc/rtl/` |
| multicore_4 | crisdsc2 | crisdsc0 | **unlocated** |
| multicore_noc_5 | crisdsc2 | crisdsc0 | `multi-core/noc/rtl/` |
| noc + exp_psc | crisdsc3 | crisdsc0 | `multi-core/noc_exp_psc/rtl/` |

crisdsc0 is not reachable by SSH from crisdsc3; files relay via crisdsc2.

---

## Build history

| bitstream | cores | WNS | HW tests | DVS small | DVS large | status |
|---|---|---|---|---|---|---|
| 2024 reference | 1 | — | — | — | 64.24% | accuracy target, XDMA v4.1.4 |
| L6m | 1 | +0.041 ns | 42/42 | 44.44% | 56.60% | verified baseline |
| multicore_1 | 16 | — | core 0 only | — | — | tdest `[503:499]` bug |
| multicore_2 | 16 | — | core 0 only | — | — | tdest `[499:496]`, wrong byte |
| multicore_3 | 16 | — | core 0 only | — | — | registered tdest, wrong check byte |
| **multicore_4** | 16 | +0.041 ns | **672/672** | **44.44% all 16** | core 0 only | beat-7 counter — definitive |
| multicore_noc_5 | 16 | +0.0078 ns | pending | — | — | built, crossbar untested on hardware |
| exp_psc | 1 | +0.0678 ns | 42/42 | — | — | 8/8 biological features |
| noc + exp_psc v3 | 16 | +0.037 ns | — | — | — | unverified, not yet flashed |

The 64.24% to 56.60% accuracy gap was traced to the XDMA IP version — v4.1.4
against v4.1.29 — not to neuron behaviour. See `docs/06_dvs_accuracy.md`.

---

## Where to start

**Reproducing a result** → `docs/09_reproduction_guide.md`, then that design's
`MANIFEST.md` for the source hashes.

**Understanding the host interface** → `docs/00_platform_reference.md`.

**Understanding how a timestep runs** → `docs/02_architecture.md`.

**Judging what is trustworthy** → `docs/04_verification_methodology.md`. Every
feature table in this repository uses its four terms and no others.

**Building on the neuron model** → `single-core/README.md` for the feature
matrix, then `single-core/exp_psc/`.

**Building on the interconnect** → `multi-core/README.md`, then
`multi-core/noc/docs/NOC.md`.

---

## Core architecture

Each core contains an internal events processor for neuron evaluation, a command
interpreter for DMA packet parsing, an external events processor for spike I/O,
an HBM processor for synapse storage, sixteen URAMs for membrane potential, and
parameter memory in BRAM for neuron type configuration.

The host communicates over PCIe Gen3 x16 through XDMA, with an AXI-Stream switch
fabric routing commands to individual cores by `tdest`, taken from
`tdata[503:499]`.

In multicore_4 the `pcie_tdest_generator` uses a modulo-8 beat counter to extract
the coreID from `tdata[387:384]` on beat 7 of each eight-beat 512-byte transfer —
the fix that took it from core 0 only to all sixteen.

---

## Software dependencies

| component | commit | repository |
|---|---|---|
| `hs_api` | `e526b6f` (testing-suite) | Integrated-Systems-Neuroengineering/hs_api |
| `hs_bridge` | `1e3a114` | internal |
| `connectome_utils` | `181f8a8` (dev) | Integrated-Systems-Neuroengineering/connectome_utils |

Results reproduce only against the software they were measured with.

---

## Machines

| machine | role | software |
|---|---|---|
| crisdsc0 | FPGA under test, host software | Python 3.10, ADXDMA |
| crisdsc2 | Vivado builds — multicore, NoC, Firefly | Vivado 2024.1 |
| crisdsc3 | Vivado builds — biological core, merge | Vivado 2024.1 |

---

## Contact

**Omowuyi Olajide** — omowuyi@gmail.com
