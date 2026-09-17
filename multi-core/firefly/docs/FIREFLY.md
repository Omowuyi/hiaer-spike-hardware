# Unified NoC + Firefly Design

Three routing levels, designed together because the interface between them is
where the real constraints sit.

| level | scope | mechanism |
|---|---|---|
| **NoC** | 16 cores, 1 FPGA | 4×4 crossbar, L1 within cluster, L2 across clusters |
| **Firefly** | 8 FPGAs, 1 server | Aurora 64B/66B, 4 ports/FPGA, ≤3 hops |
| **100G** | 5 servers | Tofino P4, EtherType 0x88B5 |

---

## 1. The address space

Every neuron in the system has one global address:

```
 server[2:0] | fpga[2:0] | core[3:0] | neuron[12:0]      = 23 bits
             |<--------- spike_addr[16:0] ------------>|
```

`core|neuron` is exactly the 17-bit `spike_addr` the NoC already uses, so the
on-chip format is unchanged and the higher levels prepend to it. Nothing about
the existing NoC packet has to move.

**Consequence for the partitioner:** a neuron's global address is fixed by its
placement. The partition therefore determines addressing, not the reverse —
which means the routing tables, the remote table (§3) and the relay tables all
fall out of one assignment step.

---

## 2. Getting a spike off the FPGA — an orthogonal flag, not a level code

An earlier draft of this document proposed repurposing `OP_NOP` as `REMOTE`,
since the level field is full but NOP is dead. **That was wrong**, and the
reason matters: it forces every block to be either local or remote.

```
entry says LOCAL   ->  remote targets silently never receive the spike
entry says REMOTE  ->  local  targets silently never receive the spike
```

Both are silent spike loss — the same failure class that cost days on the
microphase bug. A design that forces the choice is a bug.

**Instead, leave level and mask alone and add one independent bit:**

```
level[1:0] + mask[3:0]    unchanged -- LOCAL / L1 / L2, already verified
remote_en                 one bit per 512-neuron block, consulted in parallel
```

A spike can be both. The router emits on-chip per the level *and* to the
egress port when `remote_en` is set. `OP_NOP` stays available as a genuine
drop code, and `noc_l1_bus` / `noc_l2_bus` are untouched — so everything the
xsim runs verified keeps behaving identically.

`add_remote_egress.py` implements the router side: three new ports and a
parallel tap on the accepted spike. Verified — with `remote_en` tied low the
router still passes 5/5, bit-identical to before.

---

## 3. Remote tables — per FPGA, not per core

Whether a destination block lives off-chip depends on the **block**, not on
which core emitted the spike. So both tables are per FPGA, indexed by the same
`spike_addr[16:9]`:

```
remote_en [256]   1 bit    is this block off-chip at all?
remote_dst[256]   6 bits   { server[2:0], fpga[2:0] }
```

256 × 7 bits — one distributed RAM for the whole FPGA, against 4096 entries if
it were per core.

**Server-to-server falls out of the same structure.** If `server != my_server`
the egress goes to the 100G plane; otherwise to Aurora. Same table, same
lookup, one comparison to choose the port. No third mechanism, and no change
when the system grows from one server to five.

---

## 4. Packet formats

**NoC, 32-bit — unchanged:**
```
OP[31:30] SRC[29:26] MASK[25:22] NEURON_ADDR[21:5] TS[4:0]
```

**Firefly, 64-bit:**
```
[63:61] opcode        001 = spike, 010 = barrier, 011 = relay
[60:58] dst_server
[57:55] dst_fpga
[54:51] dst_core
[50:38] dst_neuron
[37:33] TS            timestep tag, mod 32
[32:30] src_server
[29:27] src_fpga
[26:23] src_core
[22:10] src_neuron
[ 9: 6] ttl           hop budget, decrement per hop, drop at 0
[ 5: 0] reserved
```

`ttl` bounds the topology at 3 hops and makes a routing-table error drop a
packet rather than circulate it forever. Cheap insurance in a 40-FPGA system.

---

## 5. Timestep synchronisation — the part that decides correctness

A spike emitted in timestep *T* must land in timestep *T+d* on the receiving
FPGA. If FPGAs run free, the receiver may already be past *T+d* when it
arrives, and the spike is silently misordered or lost.

**Timing budget.** Aurora is 200–300 ns one-way, ≤3 hops ≈ 900 ns worst case.
A timestep with 8192 neurons is Phase 0 alone at ~2560 cycles ≈ 20 µs at
125 MHz. So a remote spike arrives in roughly 4% of a timestep — comfortable,
*provided* FPGAs stay near lockstep.

**Design: bounded skew with a periodic barrier.**

- Every Firefly spike carries `TS[4:0]`, already in the packet.
- The receiving FPGA buffers arrivals **by TS** and releases them when its own
  local timestep matches. This is structurally identical to
  `axon_delay_buffer` — 64 slots, `timestep_tick` drain, entries deposited at
  `slot = TS`. **Reuse that module rather than writing a new one.**
- `TS` is 5 bits, so 32 timesteps of slack before aliasing. Issue a barrier
  every **16** timesteps: each FPGA sends `opcode=010` when it completes the
  barrier timestep and waits for all peers before advancing.

Cost: one round trip per 16 timesteps ≈ 900 ns / 320 µs ≈ **0.3% overhead**,
with a hard guarantee that skew never exceeds 16 < 32.

Barrier only at intervals, not every timestep, is what keeps the overhead
negligible while still bounding drift.

---

## 6. Constraints the partitioner must respect

**512-neuron granularity.** The routing table is indexed by `addr[16:9]`, so one
entry governs 512 neurons. A block split across cores cannot be expressed
precisely. METIS will not respect this unless constrained — assign in
512-aligned granules, or accept multicast to every core holding part of a
block. `noc_routing.check_alignment()` reports violations.

**Locality is worth more across FPGAs than across cores.** An L1 hop is a few
cycles; a Firefly hop is ~250 ns plus a timestep-buffer wait. Weight the
partitioner's edge cut accordingly — cutting an on-chip edge is roughly two
orders of magnitude cheaper than cutting an inter-FPGA one.

**Fan-out to many FPGAs multiplies traffic.** One spike to four FPGAs is four
Aurora packets. Populations with high divergence belong on one FPGA, or behind
a relay (§7).

---

## 7. Relay, for the ≤3-hop bound

The server topology gives lower-tier FPGAs 0–3 only Port 7, while upper-tier
4–7 have all four ports. Not every pair is directly connected, so some spikes
transit an intermediate FPGA.

A relayed packet arrives, matches no local `dst_fpga`, and is re-emitted on the
next-hop port with `ttl` decremented. This needs a small relay table — the same
`remote_dst` structure, consulted when `dst_fpga != my_fpga`.

Relayed spikes must **not** enter the local timestep buffer; they pass straight
through. Keeping that path separate avoids a relay stalling on the local
timestep boundary.

---

## 8. What has to be built

| item | where | size |
|---|---|---|
| REMOTE decode (level 00) | `noc_spike_router.sv` | one case arm |
| `remote_dst` table + CMD | new, plus CI opcode | ~1536 bits + decode |
| egress: NoC 32-bit → Firefly 64-bit | new module | small |
| ingress: Firefly → timestep buffer | reuse `axon_delay_buffer` | wiring |
| relay path | new, shares `remote_dst` | small |
| barrier generate/wait | CI or a small FSM | small |
| routing-table CMD | `add_route_cmd.py` — **written** | done |
| table generation | `noc_routing.py` — **written** | done |

**Opcode conflict to settle first:** the single-core CI uses CMD 13 for PSC
parameters (`syn_64bit_en` at bit 131). The NoC routing command as drafted also
uses 13. In the merged design routing moves to **opcode 15**, which is free in
both.

---

## 9. Order of work

1. Merge the biological single core into the NoC project — seven RTL files,
   verified by content hash before building
2. Routing command on opcode 15 + four `route_cfg` signals threaded at top level
3. Build, load tables, verify L1 then L2
4. REMOTE decode + `remote_dst` + egress/ingress — Firefly spike path
5. Barrier
6. Relay

Steps 1–3 give a working 16-core biological NoC. Steps 4–6 extend it across the
server without revisiting anything from 1–3, because the NoC packet format and
the routing table width are unchanged by the Firefly work.

That is the point of designing them together: **the Firefly layer costs one
dead opcode, one small table and one reused module** — provided the REMOTE
encoding and the `TS` buffering are decided now rather than retrofitted.
