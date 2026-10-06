#!/usr/bin/env python3
"""
NoC routing table generation and loading -- v3.

WHAT CHANGED FROM THE PRE-v3 VERSION, AND WHY

Every one of these was read out of the RTL rather than inferred; the previous
version of this file had all four wrong, and a wrong entry here programs
plausible-looking garbage rather than failing visibly.

  opcode            13 -> 15.  13 and 14 are taken by the PSC parameters and
                    the axon delay table (command_interpreter.v:237)
  address field     [13:6] -> [15:6].  10 bits, from
                    `route_cfg_addr <= rxFIFO_dout[15:6]`
  entries per core  256 -> 1024, matching the 10-bit address
  core selection    there is NO core field in the payload.
                    command_interpreter.v never decodes one -- its CORE_ID is a
                    compile-time parameter used only to tag outgoing spikes.
                    The core comes from tdest, which switch_1_32.sv:9 takes as
                    `s.tdata[503:499]` -- FIVE bits, so byte 62 = coreID << 3
  table index       SOURCE block, not destination.  noc_spike_router.sv:87 is
                    `route_idx = spike_addr_in[18:9]`, and spike_addr_in is the
                    core's own spike output ("Spike Input from Core (from
                    spk2ciFIFO)").  The entry answers "where do spikes FROM
                    this block go", so it is indexed by the SPIKING neuron's
                    block.  The previous version keyed on dst // BLOCK, which
                    is a different table entirely.

TOPOLOGY (noc_spike_router.sv / noc_l1_bus.sv / noc_l2_bus.sv)
16 cores as 4 clusters of 4.  Core c sits in cluster c >> 2 at position c & 3.
L1 moves a spike between cores inside one cluster; L2 moves it across clusters.

TABLE
1024 entries per core, indexed by spike_addr[18:9] -- one entry per 512-neuron
block of the SOURCE core's address space.  Each entry is 6 bits:

    [5:4] level   NOP=0, LOCAL=1, L1=2, L2=3
    [3:0] mask    L1: destination cores within the cluster
                  L2: destination clusters

Reset value is {OP_LOCAL, 4'b0000} (noc_spike_router.sv:75), so an unwritten
entry keeps the spike on its own core.

NOTE ON L2.  noc_l2_bus rewrites a forwarded packet's mask to all ones, so a
cross-cluster spike reaches every core in each destination cluster and the
receiving cores filter by neuron address.  An L2 entry therefore costs more
NoC traffic than its mask suggests -- worth weighting in the partitioner.

GRANULARITY CONSTRAINT
Routing is decided per 512-neuron block of per-core address space.  A block
whose neurons are split across cores cannot be expressed: one entry covers all
512.  Assign in 512-aligned granules, or accept a multicast to every core
holding part of it.  check_alignment() reports violations.

  from noc_routing import build_tables, load_tables, check_alignment
  tables = build_tables(neuron_to_core, edges)
  load_tables(tables)
"""

import numpy as np

NUM_CORES = 16
CLUSTER_SIZE = 4
NUM_CLUSTERS = NUM_CORES // CLUSTER_SIZE
BLOCK = 512                      # neurons per routing entry, from addr[18:9]
ENTRIES = 1024                   # 10-bit route_cfg_addr
CMD_ROUTE_TBL_W = 15             # command_interpreter.v:237

OP_NOP, OP_LOCAL, OP_L1, OP_L2 = 0, 1, 2, 3
LEVEL_NAME = {0: "NOP", 1: "LOCAL", 2: "L1", 3: "L2"}


def cluster_of(core):
    return core >> 2


def position_in_cluster(core):
    return core & 3


def _core_index(neuron_to_core, core_index=None):
    """Per-core neuron index, which is what the router sees.

    spike_addr is a neuron's index WITHIN its core, so the block a routing
    entry covers is (per-core index) // 512 -- not the global neuron id.  Pass
    core_index={neuron: per-core index} when you have it (connectome
    get_coreTypeIdx); without it, indices are derived by numbering each core's
    neurons in ascending global id, which matches how the connectome orders a
    core's neurons only if the network was built that way.
    """
    if core_index is not None:
        return core_index
    per_core = {}
    derived = {}
    for n in sorted(neuron_to_core):
        c = neuron_to_core[n]
        idx = per_core.get(c, 0)
        derived[n] = idx
        per_core[c] = idx + 1
    return derived


def check_alignment(neuron_to_core, core_index=None):
    """Report 512-neuron blocks whose neurons do not all live on one core.

    Returns a list of (core, block_index, {cores}) for every violation.
    """
    idx = _core_index(neuron_to_core, core_index)
    blocks = {}
    for n, c in neuron_to_core.items():
        if n not in idx:
            continue
        blocks.setdefault((c, idx[n] // BLOCK), set()).add(c)
    return sorted((c, b, cs) for (c, b), cs in blocks.items() if len(cs) > 1)


def build_tables(neuron_to_core, edges, core_index=None):
    """Build a routing table for every core.

    neuron_to_core : {neuron_id: core_id}
    edges          : iterable of (src_neuron, dst_neuron)
    core_index     : optional {neuron_id: per-core index}; without it, indices
                     are derived by numbering each core's neurons in order

    Returns {core: [ (level, mask) ] * ENTRIES}.
    """
    idx = _core_index(neuron_to_core, core_index)

    # Indexed by the SOURCE block, because that is what the router looks up:
    # route_idx = spike_addr_in[18:9] and spike_addr_in is the spiking neuron.
    need = {c: {} for c in range(NUM_CORES)}
    for src, dst in edges:
        sc = neuron_to_core.get(src)
        dc = neuron_to_core.get(dst)
        if sc is None or dc is None or src not in idx:
            continue
        need[sc].setdefault(idx[src] // BLOCK, set()).add(dc)

    tables = {}
    for core in range(NUM_CORES):
        tbl = [(OP_NOP, 0)] * ENTRIES
        for blk, dests in need[core].items():
            if blk >= ENTRIES:
                raise ValueError("block %d exceeds the %d-entry table -- core "
                                 "%d holds more than %d neurons"
                                 % (blk, ENTRIES, core, ENTRIES * BLOCK))
            if dests == {core}:
                tbl[blk] = (OP_LOCAL, 0)
            elif all(cluster_of(d) == cluster_of(core) for d in dests):
                mask = 0
                for d in dests:
                    mask |= 1 << position_in_cluster(d)
                tbl[blk] = (OP_L1, mask)
            else:
                # Mixed local+remote or cross-cluster: L2 carries it.  The L2
                # bus broadcasts within each destination cluster, so the source
                # core's own cluster is included when it is a destination.
                mask = 0
                for d in dests:
                    mask |= 1 << cluster_of(d)
                tbl[blk] = (OP_L2, mask)
        tables[core] = tbl
    return tables


def _packet(core, addr, level, mask):
    """One CMD 15 packet, 64 bytes.

        byte 63       = 15                      opcode, tdata[511:504]
        byte 62       = core << 3               tdest, tdata[503:499]
        bytes 0..1    = {addr[9:0], level, mask} at tdata[15:0]

    The core is NOT a payload field -- switch_1_32 steers on tdest.
    """
    cmd = np.zeros(64, dtype=np.uint64)
    cmd[63] = CMD_ROUTE_TBL_W
    cmd[62] = (core & 0x1F) << 3
    val = ((addr & 0x3FF) << 6) | ((level & 0x3) << 4) | (mask & 0xF)
    cmd[0] = val & 0xFF
    cmd[1] = (val >> 8) & 0xFF
    return cmd


def load_tables(tables, skip_nop=True, verbose=True):
    """Send every entry.  NOP is not the reset value -- reset is
    {OP_LOCAL, 0000} -- so skipping NOP leaves an unwritten entry as LOCAL,
    which keeps the spike on its own core.  That is the safe default and it
    saves sending 16384 packets for a network that needs a handful."""
    import hs_bridge.wrapped_dmadump.dmadump as d
    sent = 0
    for core in sorted(tables):
        for addr, (level, mask) in enumerate(tables[core]):
            if skip_nop and level == OP_NOP:
                continue
            d.dma_dump_write(_packet(core, addr, level, mask),
                             64, 1, 0, 0, 0, d.DmaMethodNormal)
            sent += 1
    if verbose:
        print("routing: %d entries sent across %d cores" % (sent, len(tables)))
    return sent


def describe(tables, limit=12):
    """Print the non-NOP entries -- small enough to eyeball for a test network."""
    for core in sorted(tables):
        rows = [(a, l, m) for a, (l, m) in enumerate(tables[core]) if l != OP_NOP]
        if not rows:
            continue
        print("core %-2d : %d entries" % (core, len(rows)))
        for a, l, m in rows[:limit]:
            print("    block %-3d (core-local neurons %5d-%5d)  %-5s mask=%s"
                  % (a, a * BLOCK, a * BLOCK + BLOCK - 1, LEVEL_NAME[l],
                     format(m, "04b")))
        if len(rows) > limit:
            print("    ... %d more" % (len(rows) - limit))


def from_connectome(connectome, edges):
    """Build tables straight from a partitioned connectome.

    Takes the per-core index from the connectome itself rather than deriving
    it, so placement and routing come from one assignment.  Call after
    apply_partition and pad_models.
    """
    neuron_to_core = {}
    core_index = {}
    for key, n in connectome.get_neurons().items():
        neuron_to_core[key] = n.get_core()
        core_index[key] = n.get_coreTypeIdx()
    return build_tables(neuron_to_core, edges, core_index=core_index)


# ---------------------------------------------------------------- self-test
if __name__ == "__main__":
    # core 0 -> core 1 (same cluster) should be L1
    # core 0 -> core 5 (cluster 1)    should be L2
    # core 0 -> core 0                should be LOCAL
    n2c = {}
    cidx = {}
    for c in range(NUM_CORES):
        for i in range(BLOCK):
            n = c * BLOCK + i
            n2c[n] = c
            cidx[n] = i          # per-core index restarts on every core
    edges = [(0, BLOCK * 1 + 5),        # core 0 block 0 -> core 1, same cluster
             (1, BLOCK * 5 + 7),        # core 0 block 0 -> core 5, cluster 1
             (2, 3)]                    # core 0 block 0 -> core 0
    t = build_tables(n2c, edges, core_index=cidx)
    describe(t)

    e0 = t[0][0]
    print()
    print("core 0 block 0 ->", LEVEL_NAME[e0[0]], format(e0[1], "04b"))
    assert e0[0] == OP_L2, "mixed local + cross-cluster must escalate to L2"
    assert e0[1] == 0b0011, "clusters 0 and 1 expected"

    p = _packet(core=5, addr=777, level=OP_L1, mask=0b1010)
    assert p[63] == 15, "opcode"
    assert p[62] == 5 << 3, "tdest is tdata[503:499], five bits"
    val = int(p[0]) | (int(p[1]) << 8)
    assert (val >> 6) == 777, "addr at [15:6]"
    assert ((val >> 4) & 3) == OP_L1 and (val & 0xF) == 0b1010, "data at [5:0]"
    print("packet: opcode=%d byte62=0x%02X addr=%d level=%s mask=%s  OK"
          % (p[63], p[62], val >> 6, LEVEL_NAME[(val >> 4) & 3],
             format(val & 0xF, "04b")))

    bad = check_alignment(n2c, core_index=cidx)
    print("alignment violations:", len(bad))
