# NoC Verification

Terms as defined in
[`../../../docs/04_verification_methodology.md`](../../../docs/04_verification_methodology.md).

---

## Simulation-verified

Run under `xsim` via `../../noc_exp_psc/sim/run_xsim.sh`, which gates on
elaboration first and then runs each testbench.

| module | testbench | result |
|---|---|---|
| `noc_spike_router.sv` | `tb_router.sv` | 5/5 |
| `noc_l1_bus.sv` | `tb_l1.sv` | 4/4 |
| `noc_l2_bus.sv` | `tb_l2.sv` | 5/5 |
| `axis_switches.sv` | both switches and the arbiter | 30/30 |
| `axon_trace_mem.v` | — | 11/11 |
| full interconnect | — | elaborates |

### What the router tests established

```
block 0, reset default LOCAL   -> HOST
block 1, configured L1         -> NoC  level=10 mask=1010
block 2, configured L2         -> NoC  level=11 mask=0101
block 3, NOP                   -> HOST
block 1 + offset 5             -> NoC  level=10 mask=1010
```

Table writes land via `route_cfg`, the index is the block rather than the
neuron, and an offset within a block routes with its block.

**Note on the NOP result.** That test was run against an earlier router in which
NOP fell through to the host path. The router in this design decodes NOP and
silently drops the spike. The Firefly `REMOTE` encoding rests on NOP being
unused; that premise needs rechecking against the router it will actually run on.

---

## Not verified

- **On hardware, anything.** `multicore_noc_5` builds and closes timing at
  +0.0078 ns. The five NoC verification tests have not been run on it.
- **Deadlock** in the crossbar under sustained backpressure.
- **The routing tables on hardware** — no table has been loaded onto a flashed
  device.
- **The partitioner on a real connectome.** It has been run on synthetic networks
  only.

---

## Running the testbenches

```
cd ../../noc_exp_psc/sim && bash run_xsim.sh
```

The runner elaborates first and stops if elaboration fails, because a testbench
that runs against a design which did not elaborate reports nothing useful.
