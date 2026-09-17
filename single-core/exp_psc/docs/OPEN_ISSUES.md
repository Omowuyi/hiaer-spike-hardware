# Open Issues

---

## Microphase boundary spike loss

**Symptom.** Sixteen neurons — one per group — lose their spikes at each 512-row
boundary of a sweep. 0.16% of a 10,000-neuron network.

**Instrumented.** At low spike load, with 14 probes and no FIFO overflow
possible: microphase 0 lost 0 of 7, microphase 1 lost 7 of 7. Everything from
neuron 8,192 up was silent — roughly 1,808 neurons of a 10,016-neuron network,
about 92% of the large DVS model.

**Age.** Predates L6m. Present in every design in this repository.

**Attempts.** Nine, labelled K, L, M, N, P, Q, R, S and T. Each either recovered
the spike and corrupted membrane potentials, or removed the corruption and lost
the spike. Two are kept in `../patches/failed/`.

**Do not attempt a tenth without a new hypothesis.** The nine failures share a
shape, which suggests the fault is not where they all assumed it was.

**What is eliminated.** Not the spike FIFO — FIX V addressed readout
backpressure and is independent; 504 of its losses were in microphase 0.

**What misled the search.** A boundary test reported "row 513: 0 lost" while
exercising no neuron in that row at all. Nine attempts followed that vacuous
result.

---

## Per-synapse delay delivers nothing

Four compiler faults found and fixed: FIX W (`_create_synapses_64` dropped every
spike entry), FIX Y (`syn_delay` applied to padding, flooding the delay buffer),
FIX Z (`src` always 0), and HBM row ordering. The trace moved from garbage to all
zeros. `syn_delay=0` passes as a control.

The remaining fault is isolated to push-or-drain in the delay buffer.

FIX Y is worth noting separately: it produced an alternating +1965 / −1935
signature that was attributed to RTL three times before the cause was found in
the compiler.

---

## STDP never exercised

The hardware is present — `stdp_controller.v`, the axon trace memory, and the
CMD 13 parameter fields. It has never run end to end, and was impossible before
FIX Z.

---

## CMD 10 status layout unknown

Every `error_status` read returned `0x0000`, including bits that must have been
set. Establish the layout empirically before trusting any bit of it.
