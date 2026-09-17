# Host-Side Patches

Anchor-verified patches to the host software — `hs_api`, `hs_bridge` and the
connectome utilities. Each matches an exact anchor, aborts unless it matches
once, and writes a backup.

RTL patches live with their design, under `single-core/*/patches/` and
`multi-core/*/patches/`.

Compiler patches for the 64-bit synapse format and synaptic delay are currently
in `multi-core/noc_exp_psc/software/` — FIX W, Y, Z and AA. See
`single-core/exp_psc/docs/FIXES.md`.
