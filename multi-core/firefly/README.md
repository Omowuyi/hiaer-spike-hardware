# Firefly — Inter-FPGA

Aurora 64B/66B optical links connecting eight FPGAs within a server. The RTL
lives in [`../noc_exp_psc/rtl/`](../noc_exp_psc/rtl/); this directory holds the
design.

**No optical link has yet trained. Nothing here is verified on hardware.**

See [`docs/FIREFLY.md`](docs/FIREFLY.md) for the full design.

---

## Four decisions

**`OP_NOP` becomes `REMOTE`.** The level field is full, but NOP appeared unused,
so a remote route reuses it with the mask becoming an Aurora port bitmask — four
bits, four ports per FPGA. One decode arm, no wider table, no packet change.

**Verified against the router this will run on.** In
`../noc_exp_psc/rtl/noc_spike_router.sv` the routing FSM tests only `OP_LOCAL`,
`OP_L1` and `OP_L2`; `OP_NOP` falls to the default and takes the host path. The
value carries no behaviour of its own, so adding a `REMOTE` arm removes nothing.

Note that this is **not** true of the router in [`../noc/`](../noc/), which
decodes `OP_NOP` explicitly and silently drops the spike. The two designs differ
here as they do in address width and entry format.

**A remote destination table per FPGA, not per core** — 256 × 6 bits giving
`{server, fpga}`, written by CMD 16. The destination depends on the neuron block,
not on which core emitted the spike.

**Reuse `axon_delay_buffer` as the receive buffer.** Incoming spikes carry a
timestep field; hold each until the local timestep matches. Structurally
identical to what that module already does. The fit is structural, not tested.

**Barrier every sixteen timesteps, not every timestep.** Aurora is roughly 900 ns
worst case over three hops against a timestep of about 20 µs, and the timestep
field gives 32 timesteps of slack. That is about 0.3% overhead against roughly 4%
for a per-timestep barrier. The 20 µs figure is arithmetic, not measured.

---

## Topology

Twenty symmetric links across eight FPGAs; all 56 ordered pairs reachable; worst
case three hops. Computationally verified.

---

## Runtime FPGA identity

`FPGA_ID` was a compile-time parameter, which meant eight different bitstreams at
roughly 50 minutes each — about seven hours per topology iteration. CMD 17 makes
it runtime-settable, so one build serves every chassis position.
`../noc_exp_psc/patches/fix_runtime_fpga_id.py`.

---

## Bring-up, not yet done

1. Flash the v3 bitstream
2. Loop port 7 back on itself and confirm `channel_up` on `user_led_g0`
3. VIO probes 30–33 carry `channel_up[3:0]` and `hard_err[3:0]`
4. Only then two FPGAs, then eight
