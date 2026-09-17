# exp_psc — Biological Neuron Model

A single core with exponential post-synaptic currents, conductance-based
synapses, adaptation, neuromodulation, per-axon delay and STDP hardware.

| | |
|---|---|
| **Built on** | crisdsc3, `/data/omowuyi/single_core_exp_psc/` |
| **Tested on** | crisdsc0 |
| **Timing** | WNS +0.0678 ns |
| **Results** | 42/42 delta regression, 8/8 biological features |

IEP normalised content hash `15665e4dc212f4a376e464d7d7572bed` over 67,719
lines — v6 plus microphase diagnostics.

---

## Contents

| path | what |
|---|---|
| `rtl/` | 28 sources plus the `.before_*` history of every patch applied |
| `patches/` | anchor-verified RTL edits, each with a `--check` mode |
| `patches/failed/` | attempts that failed on hardware — **do not apply** |
| `tests/` | hardware test scripts |
| `docs/` | features, fixes, open issues, simulation findings |

---

## Applying a patch

Every patch matches an exact anchor, aborts unless it matches exactly once, and
writes a `.before_*` backup.

```
python3 patches/<name>.py --check <path to imports directory>
python3 patches/<name>.py         <path to imports directory>
```

Then the build gate, before synthesis:

```
python3 ../../tools/verify_rtl_state.py <path to imports directory>
```

---

## Not working

**Per-synapse delay** delivers nothing. Four compiler faults were found and fixed
(FIX W, Y, Z and HBM row order); the trace moved from garbage to all zeros, and
the `syn_delay=0` control passes. The remaining fault is isolated to push-or-drain
in the delay buffer.

**STDP** has never run on hardware. It was structurally impossible until FIX Z —
`src` was always 0, so every synapse read neuron 0's eligibility trace.

**The microphase boundary** loses sixteen neurons per 512-row boundary. See
[`docs/OPEN_ISSUES.md`](docs/OPEN_ISSUES.md).

---

## Dead variants in `rtl/`

`internal_events_processor.v.v8_failed`, `.fixk_regression` and `.before_KT` are
kept as history. They are failed attempts, not alternatives. Do not build from
them.
