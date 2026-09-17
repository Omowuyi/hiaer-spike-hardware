# Partitioning

Assigning neurons to cores so that the routing table can express the result and
the interconnect carries as little traffic as possible.

`../../noc_exp_psc/software/noc_partition.py`.

---

## Why not METIS

METIS minimises edge cut. That is the wrong objective here.

A spike sent to four cores within one cluster is **one** L1 transaction with a
4-bit mask, not four transactions. Counting cut edges would charge it four times
and drive the partitioner to avoid a pattern that costs almost nothing.

The right metric is **λ−1 connectivity on a hypergraph**, with one hyperedge per
source block. λ−1 charges a hyperedge once for each *additional* partition it
touches, which is exactly what a multicast mask costs.

---

## Method

**Coarsen to 512-neuron blocks first.** The routing table indexes blocks, not
neurons, so a block split across cores cannot be expressed. Coarsening first
makes the granularity constraint hold by construction rather than by later
repair.

**Recurse down the hierarchy** — server, then FPGA, then cluster, then core. The
inter-FPGA cuts are decided first and therefore weighted most heavily, which is
correct: an optical hop costs far more than an L1 hop.

**KaHyPar if importable**, built-in FM refinement otherwise.

**`initial=` accepts a starting partition.** For a network with known structure —
Potjans-Diesmann, say — the population layout beats any generic starting point.

---

## Capacity

`NEURONS_PER_CORE = 32768`, giving 64 blocks per core after the 19-bit widening.
Before the widening it was 8,192, which capped a core at 16 blocks.

---

## Verification status

**Tested on synthetic networks only.** λ−1 = 1 on two populations. λ−1 = 4 on a
ring of eight, where it paired adjacent populations so that half the ring
coupling became LOCAL — the expected result.

**Never run on a real connectome.**

---

## Checking a partition

```python
from noc_partition import partition
from noc_routing import check_alignment, build_tables, describe

violations = check_alignment(neuron_to_core)
```

`check_alignment` returns every 512-neuron block whose neurons do not all live on
one core. A non-empty result means the routing table cannot express the
partition precisely; those blocks will multicast to every core holding part of
them.
