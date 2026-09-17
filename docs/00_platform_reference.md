# Platform Reference

Host interface of the HiAER-Spike platform: the commands the host sends, the
packets the device returns, and the memory layout both address. Read this before
any other document — every design in this repository speaks this interface.

**Target:** Xilinx Virtex UltraScale+ VU37P (`xcvu37p-fsvh2892-2-e`) on an
ADM-PCIE-9H7, 8 GB HBM2. `aclk` 125 MHz, `aclk450` 250 MHz, `apb_clk` 100 MHz.

---

## 1. Host-to-device commands

A command is a 512-bit packet written by DMA. The opcode occupies `[511:504]`.

Core selection is `tdata[503:499]` — five bits, decoded by
`pcie_tdest_generator` into AXI-Stream `tdest`. In the 64-element `uint64` array
the host builds, that is byte 62, with the core number in its top five bits.

| opcode | name | payload |
|---|---|---|
| 1 | `CMD_EEP_W` | one input sample into the axon BRAM |
| 2 | `CMD_HBM_RW` | read or write one synapse row |
| 3 | `CMD_IEP_RW` | read or write neuron state |
| 4 | `CMD_NTWK_PARAM_W` | `[33:17]` n_outputs, `[16:0]` n_inputs, threshold, neuron model |
| 6 | `CMD_EXEC_STEP` | execute one timestep |
| 7 | `CMD_EXEC_CONT` | execute continuously |
| 8 | `CMD_NTWK_PARAM_MEM_W` | per-layer neuron parameters |
| 9 | `CMD_SET_TIMEOUT` | `[21:0]` FIFO timeout in cycles; 0 disables |
| 10 | `CMD_READ_STATUS` | error status; replies `0xFACE_FACE` |
| 11 | `CMD_CLEAR_STATUS` | `[31:0]` bitmask of status bits to clear |
| 12 | `CMD_DMA_HBM_W` | `[278:256]` start row, `[31:0]` row count, then streamed data |
| 13 | `CMD_SET_PSC_PARAMS` | biological neuron model — see §2 |
| 14 | `CMD_AXON_DELAY_W` | `[18:6]` axon address, `[5:0]` delay 0–63 |
| 15 | `CMD_ROUTE_TBL_W` | `[15:6]` table address, `[5:0]` `{level[1:0], mask[3:0]}` |
| 16 | `CMD_REMOTE_DST_W` | `[15:6]` block index, `[5:3]` destination server, `[2:0]` destination FPGA |
| 17 | `CMD_FPGA_ID_W` | board identity, so one bitstream serves every chassis position |

Opcodes 0 and 5 are unused.

**A note on the CMD 15 and 16 comments.** The source comments in
`command_interpreter.v` describe `[13:6]` for the table address and index the
remote table by `spike_addr[16:9]`. Those comments predate the 19-bit widening
and were not updated. The code reads `rxFIFO_dout[15:6]` and `route_cfg_addr` is
declared `[9:0]`. Verify against the code, not the comment. See
`multi-core/noc_exp_psc/patches/fix_route_cfg_width.py`.

**CMD 15 versus CMD 16.** CMD 15 decides which *cores within this device*
receive a spike. CMD 16 decides which *device* owns a 512-neuron block. They are
independent tables with the same index.

**No core field in CMD 15.** Every core has its own command interpreter and
programs its own router, so the packet carries only address and data; the core is
selected by `tdest`. A host loader that packs a core number into the command word
is writing into bits the device does not read — and after the widening, into the
address field itself.

---

## 2. CMD 13 — biological neuron model

| bits | field |
|---|---|
| `[0]` | `delta_mode` — 1 legacy, 0 exponential PSC |
| `[12:1]` | `decay_ex`, 12-bit fixed point ×4096 |
| `[24:13]` | `decay_in`, 12-bit fixed point ×4096 |
| `[32:25]` | `decay_w`, 8-bit fixed point ×256 |
| `[40:33]` | `delta_w`, adaptation increment on spike |
| `[41]` | `coba_mode` |
| `[53:42]` | `E_ex`, 12-bit signed |
| `[65:54]` | `E_in`, 12-bit signed |
| `[73:66]` | `neuromod_level`, 8-bit unsigned |
| `[81:74]` | `neuromod_excitability_bias`, 8-bit signed |
| `[82]` | `stdp_enable` |
| `[90:83]` | `A_plus`, potentiation magnitude |
| `[98:91]` | `A_minus`, depression magnitude |
| `[114:99]` | `w_max`, 16-bit signed |
| `[130:115]` | `w_min`, 16-bit signed |
| `[131]` | `syn_64bit_en` |

---

## 3. Device-to-host packets

Identified by the two most significant bytes — `byte[63]` and `byte[62]` in the
little-endian DMA array.

| header | meaning |
|---|---|
| `0xACE0_ACE0` | command acknowledged |
| `0xEEEE_EEEE` | spike packet, up to 14 spikes |
| `0xABCD_ABCD` | execution complete, with final spikes |
| `0xBABA_BABA` | latency counter |
| `0xCABA_CABA` | HBM access counter |
| `0xBBBB____` | HBM readback data |
| `0xCCCC____` | membrane potential readback |
| `0xFFFF____` | FIFO empty, no further data |
| `0xDEAD_DEAD` | error — FIFO timeout or flush |
| `0xFACE_FACE` | status response to CMD 10 |

ACK status codes at `[439:432]`: `0x01` accepted normally, `0x02` a previous ACK
was overwritten and a sequence number was skipped.

---

## 4. The spike word

Each spike is 32 bits within a spike packet.

| bits | field | before the 19-bit widening |
|---|---|---|
| `[31:24]` | timestamp, `execRun_ctr[7:0]` | same |
| `[23]` | valid | same |
| `[22:19]` | source core, 0–15 | `[22:21]` reserved, `[20:17]` core |
| `[18:0]` | neuron address within the source core | `[16:0]` |

The host reads the packet as a 32-character MSB-first binary string, so bit *b*
sits at string position 31−*b*: the core is `spikePacket[9:13]` and the address
is `spikePacket[-19:]`.

The address is **core-relative**. The host resolves it through the connectome,
whose index is flat across all cores — correct for one core, ambiguous for
sixteen. The core field is currently decoded and then discarded.

---

## 5. Memory

**Neuron state (URAM).** 4,096 rows of 72 bits per core. Rows 0–2,047 hold each
neuron's first row, 2,048–4,095 the second. Sixteen neurons share a row index,
one to each group, so a core holds 2,048 × 16 = **32,768 neurons**, and sixteen
cores hold 524,288 — which is what a 19-bit address names.

URAM half-word `[35:0]`: `[35]` spike bit, `[34:32]` refractory counter,
`[31:0]` membrane potential in two's complement.

**Axons.** 8,192 rows × 16 groups = **131,072 axons per core**. Not widened.
Growing it would change the microphase division of the events processor and
belongs to its own revision.

`n_inputs` and `n_outputs` are 17-bit fields in CMD 4, so the encoder rejects an
axon count of exactly 131,072. The reachable maximum is 131,071.

**Synapses (HBM).** 8 GB HBM2. The 64-bit synapse format carries weight, target
row, delay and source index. `SYN_ROWS_PER_CORE_64` is 4,194,304 — 256 MB per
channel.

---

## 6. Servers

| host | role |
|---|---|
| **crisdsc0** | test — the FPGA under test, `hs_api`, `hs_bridge`, `/bitstreams/` |
| **crisdsc2** | build — multicore, NoC and Firefly projects |
| **crisdsc3** | build — biological single core, NoC + exp_psc, `/data/omowuyi/` |

crisdsc0 is not reachable by SSH from crisdsc3; files relay via crisdsc2.

After any reboot, flash the L6m bitstream first to restore the PCIe
configuration, then the target bitstream **without rebooting in between**.

The PCIe driver bind needs re-running after each programming, because the device
enumerates with ID `903f` after a rescan rather than `0902`:

```
echo "4144 903f" | sudo tee /sys/bus/pci/drivers/adxdma/new_id
```

---

## 7. What is not documented here

- **CMD 10 status bit layout.** Every `error_status` read returned `0x0000`,
  including bits that must have been set. Establish it empirically before
  trusting any bit of it.
- **CMD 2 readback byte order** was established by measurement, not by reading:
  marker `0xBBBB` in bytes 62–63, the 256-bit row in bytes 0–31, little-endian
  within each 32-bit group. Three separate derivations from RTL were wrong.
