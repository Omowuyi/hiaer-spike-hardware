# Server-to-Server

Five servers, eight FPGAs each, sixteen cores per FPGA — 640 cores. Connected by
100G Ethernet with a P4 program on an Arista 7170-64C.

**Design only. No RTL in this repository, nothing built, nothing verified.**

See [`docs/SYSTEM.md`](docs/SYSTEM.md).

---

## Position in the sequence

| phase | scope | status |
|---|---|---|
| 1 | 16 cores on one FPGA over the NoC | built, hardware tests pending |
| 2 | 8 FPGAs in a server over Firefly | designed, no link trained |
| 3 | 5 servers over 100G | designed only |

Phase 3 depends on Phase 2, which depends on Phase 1 being verified on hardware.
None of those dependencies is currently satisfied.

---

## Intended structure

100G CMAC on QSFP port D. Spikes carried in a custom header parsed by a P4
program on the Tofino switch, with match-action tables doing the forwarding and
partition management handled through EOS.

The partitioner already recurses server → FPGA → cluster → core, so the
assignment side of this is in place; see
[`../noc/docs/PARTITIONING.md`](../noc/docs/PARTITIONING.md).
