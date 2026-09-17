# Verification Methodology

What it takes for a statement in this repository to be called verified, and what
each level does and does not license. Every feature table uses these four terms
and no others.

---

## The four levels

**Hardware-verified.** Run on a flashed FPGA, with a test that would have failed
had the feature been absent. The strongest level, and the only one that licenses
"this works".

**Simulation-verified.** Passes a testbench under `xsim`. Establishes that the
logic does what the RTL says. Does not establish timing closure, integration
with the rest of the design, or that the host programs it correctly.

**Computationally verified.** A property established by calculation over the
design — a topology being fully connected, a table being large enough, an
address fitting a field. Establishes arithmetic, nothing physical.

**Unverified.** Written, elaborated, possibly built, never exercised. A design
that synthesises and closes timing is unverified until something runs through it.

A level attaches to a *specific statement*, never to a file or a feature in
general. `noc_spike_router.sv` is simulation-verified for its routing decisions
and unverified for deadlock under backpressure; both are true at once.

---

## Rules that produced these levels

Each was learned by being wrong.

**Never conclude from reading RTL.** Three packet layouts and one routing-table
format were derived by careful reading and all four were wrong. The router became
trustworthy only after simulation; the HBM readback byte order only after
measurement.

**A vacuous result is worse than a failure.** A boundary test reported
"row 513: 0 lost" while exercising no neuron in that row. That result sent nine
fix attempts after the wrong target. A test must be able to fail before its
passing means anything.

**Anchor-verified patches, never hand edits.** Every RTL change is a script that
matches an exact anchor, aborts unless it matches exactly once, writes a
`.before_*` backup, and offers `--check`. Three hand-pastes silently failed in a
single session; no anchored patch did.

**Content-hash the sources before every build.** `tools/verify_rtl_state.py` is a
22-check gate. A build from a tree you have not hashed is a build whose result
cannot be attributed to anything.

**Bound every hardware test.** `SIGALRM` plus a retry cap. Two unbounded scripts
hung the card and cost recovery cycles.

**Silence is not success.** A width mismatch is a synthesis warning, not an
error. The routing-table write path was eight bits wide against a ten-bit table
across sixteen cores and built cleanly; the only symptom would have been spikes
quietly dropped above neuron 131,071.

---

## Current status

**Hardware-verified.** L6m: 42/42 regression, DVS small 44.44%, DVS large
56.60%. multicore_4: 672/672 across all sixteen cores. exp_psc: 42/42 delta
regression, 8/8 biological features, the 64-bit synapse format, and FIX V spike
backpressure measured as 8,189 → 9,984 of 10,000 spikes.

**Simulation-verified.** The NoC router (5/5), the L1 bus (4/4), the L2 bus
(5/5), both AXI-Stream switches and the arbiter (30/30), the axon trace memory
(11/11), and elaboration of the full interconnect.

**Computationally verified.** The Firefly topology — 20 symmetric links, all 56
pairs reachable, worst case three hops. The 19-bit address space against the URAM
row count. The 1,024-entry routing table against 524,288 neurons per device.

**Unverified.** The merged NoC + exp_psc bitstream. Routing tables on hardware.
Any Aurora optical link. Per-synapse delay end to end. STDP end to end.

**Known broken.** The microphase boundary loses spikes from sixteen neurons at
each 512-row boundary — 0.16% of a 10,000-neuron network. It predates L6m. Nine
fix attempts (K, L, M, N, P, Q, R, S, T) each either recovered the spike and
corrupted membrane potentials, or removed the corruption and lost the spike. Do
not attempt a tenth without a new hypothesis; the failed attempts are kept in
`single-core/exp_psc/patches/failed/`.
