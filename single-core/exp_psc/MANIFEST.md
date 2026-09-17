# Build Manifest — single_core_exp_psc

---

## exp_psc, biological neuron model — July 2026

| | |
|---|---|
| **Built on** | crisdsc3, `/data/omowuyi/single_core_exp_psc/` |
| **Tested on** | crisdsc0 |
| **Vivado** | 2024.1 |
| **WNS** | +0.0678 ns |
| **Results** | 42/42 delta regression, 8/8 biological features |

IEP normalised content hash `15665e4dc212f4a376e464d7d7572bed` over 67,719
lines — v6 plus microphase diagnostics. The normalised hash strips comments and
whitespace, so it identifies behaviour rather than formatting.

### Sources

| file | MD5 |
|---|---|
| `internal_events_processor.v` | `42c23f85ae6a1fc1629a50759905b446` |
| `hbm_processor.v` | `bb47054109ee0f7bb8eef5b6cd5479ac` |
| `delay_buffer.v` | `145ca7f97f5fcd0f65a0f943a8280c9b` |
| `axon_delay_buffer.v` | `2470d9696213bb23f98f11cd493dc99c` |
| `stdp_controller.v` | `a78bee4358f8c7ea18ac2c5e2a3aa4a0` |
| `command_interpreter.v` | `174bf4ece9ea9fc979202cd784eca589` |
| `single_core.sv` | `7e372231ca529f79b7813e9b433ed770` |

These seven are the files that carry the biological model. They are what the
NoC + exp_psc merge copies forward; the interconnect never touches them.

### Software pairing

| | commit |
|---|---|
| `hs_api` | `e526b6f` (testing-suite branch) |
| `hs_bridge` | `1e3a114` |
| `connectome_utils` | `181f8a8` (dev branch) |

Plus the compiler fixes W, Y, Z, AA and the row-order correction, which are
host-side and need no rebuild. See `docs/FIXES.md`.

### Verified in this build

Hardware: 42/42 delta regression, the eight biological features, the 64-bit
synapse format, and FIX V spike backpressure at 9,984 of 10,000 spikes against
8,189 before.

Not working: per-synapse delay, STDP end to end, the microphase boundary.

### Before rebuilding

```
python3 ../../tools/verify_rtl_state.py <imports directory>
```

A build from an unhashed tree is a build whose result cannot be attributed.
