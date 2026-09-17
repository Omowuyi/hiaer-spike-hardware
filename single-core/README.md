# Single-Core Designs

One core per FPGA. This is where the neuron model lives; everything in
[`../multi-core/`](../multi-core/) replicates a core from here and adds routing.

Verification terms are defined in
[`../docs/04_verification_methodology.md`](../docs/04_verification_methodology.md)
and are used strictly.

| design | scope | built on | tested on | status |
|---|---|---|---|---|
| [`L6m/`](L6m/) | frozen baseline | crisdsc2 | crisdsc0 | 42/42, DVS large 56.60%, WNS +0.041 ns |
| [`exp_psc/`](exp_psc/) | biological neuron model | crisdsc3 | crisdsc0 | 42/42 + 8/8 features, WNS +0.0678 ns |

---

## Feature matrix

| feature | design | mechanism | verification |
|---|---|---|---|
| Integrate and fire | L6m | membrane potential, threshold, reset | hardware |
| Refractory period | L6m | 3-bit counter in URAM `[34:32]` | hardware |
| Soft reset | L6m | subtract threshold instead of clearing | hardware |
| Axon delay | L6m | per-axon delay table, CMD 14 | hardware |
| Exponential PSC, excitatory | exp_psc | `decay_ex`, 12-bit fixed point | hardware |
| Exponential PSC, inhibitory | exp_psc | `decay_in` | hardware |
| Mixed summation | exp_psc | separate excitatory and inhibitory accumulators | hardware |
| Conductance based (COBA) | exp_psc | `coba_mode`, reversal potentials `E_ex` / `E_in` | hardware |
| AdEx adaptation | exp_psc | `decay_w`, `delta_w` on spike | hardware |
| Neuromodulation | exp_psc | `neuromod_level`, excitability bias | hardware |
| 64-bit synapse format | exp_psc | weight, target row, delay, source index | hardware |
| Spike backpressure (FIX V) | exp_psc | `any_spk_full` gates `hbm_rready` | hardware — 8,189 to 9,984 of 10,000 |
| Per-synapse delay | exp_psc | delay buffer, push-or-drain | **unverified** — delivers nothing |
| STDP | exp_psc | `stdp_controller.v`, axon trace memory | **unverified** — never run on hardware |
| Microphase boundary | both | — | **known broken** — 16 neurons lost per 512-row boundary |

---

## Which to start from

**L6m** if you want a working baseline. It is frozen, its software pairing is
recorded, and its results reproduce.

**exp_psc** if you need biological dynamics. It carries every L6m feature plus
the eight above, but per-synapse delay and STDP do not work.

Neither fixes the microphase boundary. It costs 0.16% of spikes in a
10,000-neuron network and predates both.

---

## Software pairing

Results reproduce only against the software they were measured with.

| | commit |
|---|---|
| `hs_api` | `e526b6f` (testing-suite branch) |
| `hs_bridge` | `1e3a114` |
| `connectome_utils` | `181f8a8` (dev branch) |

For L6m and multicore_4, `shift=0` must be converted to `shift=-17`, and
`legacy_noise_en=1` is required for the DVS tests. The DVS large threshold in the
test file is 64.57%, set for the 2024 bitstream; lower it to 55.00% for L6m.

The 2024 reference bitstream needs no patches and reaches DVS large 64.24%. The
gap to L6m's 56.60% is the XDMA IP version — v4.1.4 against v4.1.29.
