# Full System

640 cores: five servers × eight FPGAs × sixteen cores. At 32,768 neurons per
core that is a ceiling of roughly 21 million neurons.

**Nothing in this document is built or verified.**

---

## Three network planes

**On-chip.** The NoC crossbar — L1 within a cluster of four cores, L2 across four
clusters. Latency is a few cycles. See
[`../../noc/docs/NOC.md`](../../noc/docs/NOC.md).

**Intra-server.** Aurora 64B/66B optical links between the eight FPGAs of one
chassis — twenty symmetric links, worst case three hops, roughly 900 ns. See
[`../../firefly/`](../../firefly/).

**Inter-server.** 100G Ethernet through a P4-programmed Tofino switch, carrying
spikes between the five servers.

Each plane is an order of magnitude slower than the one above it, which is why
the partitioner decides the inter-server cuts first and weights them most.

---

## Addressing

A neuron is named by `{server, fpga, core, neuron}`. Within a device the 19-bit
address covers all sixteen cores. Beyond it, the remote destination table (CMD
16) maps a 512-neuron block to `{server[2:0], fpga[2:0]}`.

Three bits of server allows eight; five servers are planned.

---

## Timestep coherence

The system advances in lockstep. A spike emitted in timestep *t* must be
integrated in timestep *t* everywhere, so either every device waits for every
other, or spikes carry a timestep field and are buffered until the receiver
catches up.

The Firefly design takes the second route, with a barrier every sixteen timesteps
rather than every one. Extending that across servers is unaddressed: the 100G
latency budget has not been measured and the barrier interval that suits Aurora
may not suit Ethernet.

---

## What has to happen first

The NoC on hardware. Then a trained optical link. Then two FPGAs exchanging a
spike. Then eight. Only then does this document describe anything buildable.
