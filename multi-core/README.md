# Multi-Core Designs

Sixteen cores on one FPGA, then eight FPGAs in a server, then five servers. Each
directory is a distinct design with its own bitstream, manifest and results.

Verification terms are defined in
[`../docs/04_verification_methodology.md`](../docs/04_verification_methodology.md).

| design | scope | built on | WNS | status |
|---|---|---|---|---|
| [`multicore_4/`](multicore_4/) | 16 cores, time-multiplexed | crisdsc2 | +0.041 ns | **672/672** — RTL source unlocated |
| [`noc/`](noc/) | 16 cores, parallel crossbar | crisdsc2 | +0.0078 ns | built; NoC tests pending |
| [`noc_exp_psc/`](noc_exp_psc/) | crossbar + biological cores + Firefly | crisdsc3 | +0.037 ns | unverified — not yet flashed |
| [`firefly/`](firefly/) | inter-FPGA optical, 8 per server | — | — | design only; no link has trained |
| [`server-to-server/`](server-to-server/) | 5 servers, 100G | — | — | design only |

All tested on crisdsc0.

---

## How they relate

`multicore_4` replicates a core sixteen times over a time-multiplexed path. It is
the only design with a complete 672/672 result, and its RTL source has not been
located.

`noc/` adds a parallel crossbar — per-core routers, L1 buses within a cluster of
four, L2 across four clusters — so spikes move between cores without the host.
Built on the L6m core lineage, 17-bit addressing.

`noc_exp_psc/` merges the biological core from
[`../single-core/exp_psc/`](../single-core/exp_psc/) onto that crossbar and
widens the neuron address from 17 to 19 bits. It also carries the Firefly
optical subsystem. Nothing in it has run on hardware.

`firefly/` and `server-to-server/` are design documents. The RTL for Firefly
lives inside `noc_exp_psc/rtl/`.

---

## The two routing table formats

The NoC design and the merge do not share a routing table format. See
[`noc/docs/ROUTING_TABLES.md`](noc/docs/ROUTING_TABLES.md). Host code written for
one will silently misprogram the other.
