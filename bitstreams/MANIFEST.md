# Bitstream Index

`.bit` files are **not committed** — roughly 68 MB each, and they change with
every build. This index records what exists, where, and what it was measured to
do. Each design's own `MANIFEST.md` carries the source hashes needed to rebuild
it.

All bitstreams live on crisdsc0 at `/bitstreams/` for flashing, and are archived
on crisdsc3 under `/data/omowuyi/bitstreams/`.

---

| bitstream | design | built on | WNS | results |
|---|---|---|---|---|
| `multi_neuron_type_param_mem_fix_08132024.bit` | 2024 reference | — | — | DVS large 64.24% |
| `sixteen_core_top_L6m.bit` | L6m single core | crisdsc2 | +0.041 ns | 42/42, DVS small 44.44%, DVS large 56.60% |
| `sixteen_core_top_multicore_4.bit` | multicore_4 | crisdsc2 | +0.041 ns | 672/672 across sixteen cores |
| `sixteen_core_top_multicore_noc_5.bit` | multicore_noc_5 | crisdsc2 | +0.0078 ns | NoC tests pending |
| exp_psc build | single_core_exp_psc | crisdsc3 | +0.0678 ns | 42/42, 8/8 features |
| `sixteen_core_firefly_v3` | noc + exp_psc + Firefly | crisdsc3 | +0.037 ns | unverified — not yet flashed |

---

## Known hashes

| bitstream | MD5 |
|---|---|
| `sixteen_core_top_multicore_noc_5.bit` | `dfb89313ea1d6a69cabfab70f807e0ae` |
| `sixteen_core_top_noc_delay_fix.bit` | `dfb89313ea1d6a69cabfab70f807e0ae` (identical file) |

---

## Flashing

After any reboot, flash L6m first to restore the PCIe configuration, then the
target bitstream **without rebooting in between**.

```
cd /bitstreams && sudo ./flash_2024.sh
```

Then rebind the driver, since the device enumerates as `903f` after a rescan:

```
echo "4144 903f" | sudo tee /sys/bus/pci/drivers/adxdma/new_id
```

---

## The accuracy gap

The 2024 reference reaches DVS large 64.24%; L6m reaches 56.60%. The difference
was traced to the XDMA IP version — v4.1.4 against v4.1.29 — not to any
difference in neuron behaviour.
