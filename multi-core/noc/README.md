# Network-on-Chip — multicore_noc_5

Sixteen cores connected by a parallel crossbar: four clusters of four, with an L1
bus inside each cluster and an L2 bus across clusters. A spike moves between
cores without passing through the host.

| | |
|---|---|
| **Bitstream** | `sixteen_core_top_multicore_noc_5.bit`, MD5 `dfb89313ea1d6a69cabfab70f807e0ae` |
| **Built on** | crisdsc2, `/home/omowuyi/single_core_a/single_core/` |
| **Tested on** | crisdsc0 |
| **WNS** | +0.007763 ns |
| **Core lineage** | L6m, 17-bit neuron addressing |
| **Results** | **pending** — the design builds and closes timing; the five NoC verification tests have not been run |

---

## Contents

| path | what |
|---|---|
| `rtl/` | 8 NoC sources plus 27 core sources — the exact set that built the bitstream |
| `constrs/` | 14 constraint files, including `false_paths.xdc` and `multi_core_placement.xdc` |
| `software/` | the L6j-validated host software this bitstream was tested against |
| `clock_and_buffer.bd` | clock wizard — 125 / 100 / 250 MHz |
| `fix_iep_delay.py` | the IEP delay match pipeline fix |
| `timing_summary.txt` | WNS and the seven fixes in this build |
| `docs/` | architecture, routing tables, partitioning, verification |

See [`MANIFEST.md`](MANIFEST.md) for every source hash.

---

## Provenance

`/data/omowuyi/multicore_noc/rtl_backup/` on crisdsc3 is labelled as the
reproduction source for this bitstream and is not: its `cores_with_noc.v` is zero
bytes and it holds no NoC sources. The NoC half here came from the crisdsc2 build
tree, identified by matching the built bitstream's MD5 against both archived
copies. The core half and the constraints came from `rtl_backup`, which is
genuine.

---

## Against the merge

`noc_exp_psc/` is a different design, not a later version of this one. It has
19-bit addressing, a 1,024-entry routing table, biological cores, and a different
routing command. The two are not interchangeable and neither is a drop-in
replacement for the other.
