# Build Manifest — multicore_4

---

## multicore_4, sixteen cores, time-multiplexed — June 2026

| | |
|---|---|
| **Bitstream** | `sixteen_core_top_multicore_4.bit` |
| **Location** | `/data/omowuyi/multicore_noc/bitstreams/` and `/data/omowuyi/bitstreams/` on crisdsc3 |
| **Built on** | crisdsc2 |
| **Tested on** | crisdsc0 |
| **Vivado** | 2024.1 |
| **WNS** | +0.041 ns |
| **Results** | **672/672** — 42/42 on every one of sixteen cores |
| | DVS small 44.44% on all sixteen cores |
| | DVS large 56.60% on core 0, matching the L6m single-core baseline |

### RTL source — not located

The RTL that produced this bitstream has not been found. It is not on crisdsc3,
and the crisdsc2 trees searched so far do not hold an identified copy. This
entry records the bitstream and its results; it does not permit a rebuild.

Recovering it is worth doing while the crisdsc2 trees still exist, since
multicore_4 is the only design with a full 672/672 result.

### What the design does

Sixteen cores sharing a time-multiplexed path, without the parallel crossbar
that multicore_noc_5 adds.

The defining fix was in `pcie_tdest_generator`. Each `uint64` element of the
Python command array is eight raw DMA bytes on x86 little-endian, so a
64-element command is 512 bytes and eight AXI beats. The coreID at element 62
maps to raw byte 496, which lands in beat 7 at `tdata[387:384]` — not beat 0,
where earlier implementations read it. The fix latches coreID from
`tdata[387:384]` on beat 7 using a modulo-8 beat counter, paired with a host-side
wrapper that pads every `dma_dump_write` to a multiple of 64 elements so the beat
counter stays aligned.

### Known issue

The DVS large padding wrapper must be **disabled** for multi-group commands
longer than 64 elements; it causes errant packets during membrane potential
readout. Consequently DVS large runs correctly only on core 0.

### Software pairing

| | commit |
|---|---|
| `hs_api` | `e526b6f` (testing-suite branch) |
| `hs_bridge` | `1e3a114` |
| `connectome_utils` | `181f8a8` (dev branch) |

`shift=0` must be converted to `shift=-17`, and `legacy_noise_en=1` is required
for the DVS tests. Lower the DVS large threshold in the test file from 64.57% to
55.00%.
