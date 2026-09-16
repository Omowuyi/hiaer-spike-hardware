#!/usr/bin/env python3
"""
FIX AB -- stdp_controller reads the AXON trace when the source is remote.

WHAT IT CHANGES
stdp_controller derives the presynaptic trace address from e_src as a neuron in
this core's URAM:

    src_group = e_src[3:0]
    src_row_b = e_src[16:5] + 12'd2048
    src_half  = e_src[4]

That is right for a presynaptic neuron on this core and useless for one
anywhere else -- its trace lives in the source core's URAM, which this core
cannot read.  So every cross-core, cross-FPGA and cross-server synapse learned
nothing.

FIX AA gave axon-driven rows a real source with a type flag:

    e_src[17] = 0  -> neuron source, e_src[16:0] = neuron index  (as today)
    e_src[17] = 1  -> axon   source, e_src[16:0] = axon index

Bit 17 was previously unused, so nothing that works today changes.

This patch adds the branch: when bit 17 is set, take the trace from
axon_trace_mem instead of URAM.  A remote spike arrives through noc_relay into
the EEP as an axon event, so axon_trace_mem has been tracking it all along --
and identically whether it came from the next core, another FPGA, or another
server.

WHY NOT CARRY THE TRACE IN THE PACKET
LTP fires when the POSTsynaptic neuron spikes, which is a later timestep than
when the presynaptic spike arrived.  A trace snapshotted at emission is stale
by then and would apply the wrong update.  Reconstructing locally is both
correct and cheaper -- the 32-bit NoC packet has no spare bits either.

  python3 fix_stdp_axon_trace.py --check <stdp_controller.v>
  python3 fix_stdp_axon_trace.py         <stdp_controller.v>

Apply after fix_axon_src.py on the compiler side.  Needs axon_trace_mem.v
instantiated and its ports connected -- see the note at the end.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_stdp_axon_trace.py [--check] <stdp_controller.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX AB" in s:
    fail("%s already patched." % p)

edits = []

# 1. ports for the axon trace lookup
o = "    wire [17:0] e_src     = current_entry_w[17:0];"
if s.count(o) != 1:
    fail("e_src declaration not found exactly once in %s" % p)
edits.append((o,
  o + """
    //=====================================================================
    // FIX AB: e_src[17] distinguishes the two kinds of presynaptic source.
    // Bit 17 was unused before, so neuron-sourced behaviour is unchanged.
    //=====================================================================
    wire        src_is_axon = e_src[17];
    wire [12:0] src_axon_idx = e_src[12:0];""", "source type decode"))

o = "    reg  [3:0]  src_trace;"
if s.count(o) != 1:
    fail("src_trace declaration not found exactly once in %s" % p)
edits.append((o,
  """    reg  [3:0]  src_trace_uram;   // from this core's URAM, neuron sources
    reg  [3:0]  src_trace;         // whichever source applies""",
  "split the trace registers"))

# 2. the URAM read must not fire for an axon source, and the mux
o = "                    if (src_half) src_trace <= uram_rdata_phase4_flat[72*src_group + 39 -: 4];\n" \
    "                    else          src_trace <= uram_rdata_phase4_flat[72*src_group + 3 -: 4];"
if s.count(o) != 1:
    fail("src_trace URAM capture not found exactly once in %s" % p)
edits.append((o,
  """                    // FIX AB: a neuron source reads this core's URAM as
                    // before; an axon source takes the value axon_trace_mem
                    // presented alongside.  The two are never both valid.
                    if (src_half) src_trace_uram <= uram_rdata_phase4_flat[72*src_group + 39 -: 4];
                    else          src_trace_uram <= uram_rdata_phase4_flat[72*src_group + 3 -: 4];
                    src_trace <= src_is_axon ? axon_trace_rd_data
                                             : (src_half ? uram_rdata_phase4_flat[72*src_group + 39 -: 4]
                                                         : uram_rdata_phase4_flat[72*src_group + 3 -: 4]);""",
  "trace source mux"))

# 3. request the axon lookup when the URAM read is issued
o = "                        uram_raddr_phase4_flat[12*src_group +: 12] <= src_row_b;"
if s.count(o) != 1:
    fail("phase-4 URAM address assignment not found exactly once in %s" % p)
edits.append((o,
  """                        // FIX AB: issue both lookups.  The URAM read is
                        // harmless for an axon source -- its result is simply
                        // not selected -- and issuing them together keeps the
                        // one-cycle latency identical on both paths, so the
                        // state machine's timing is unchanged.
                        axon_trace_rd_en  <= src_is_axon;
                        axon_trace_rd_idx <= src_axon_idx;
""" + o, "issue the axon lookup"))

# 4. module ports.  The module has a PARAMETER list before the port list, so
# anchor on the first real port rather than the first "(" -- that would land in
# the parameter list and produce a syntax error.
o = ")(\n    input  wire        clk,"
if s.count(o) != 1:
    fail("module port list opening not found exactly once in %s (%d)"
         % (p, s.count(o)))
edits.append((o,
  """)(
    //=========================================================================
    // FIX AB: axon eligibility trace lookup, for presynaptic sources that are
    // not neurons on this core.  Connect to axon_trace_mem.
    //=========================================================================
    output reg         axon_trace_rd_en,
    output reg  [12:0] axon_trace_rd_idx,
    input  wire [3:0]  axon_trace_rd_data,

    input  wire        clk,""", "module ports"))

print("edit sites verified:")
for _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

# apply in reverse position order so earlier offsets stay valid
for old, new, label in edits:
    if s.count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    s = s.replace(old, new)

bak = p + ".before_axontrace"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
Still to wire, in single_core.sv:

    axon_trace_mem #(.NUM_AXONS(8192)) axon_trace_i (
        .clk(clk), .resetn(resetn),
        .timestep(timestep_low5), .timestep_tick(exec_run),
        .axon_spike_valid(<EEP axon fired>),
        .axon_spike_idx  (<EEP axon index>),
        .trace_rd_en  (w_axon_trace_rd_en),
        .trace_rd_idx (w_axon_trace_rd_idx),
        .trace_rd_data(w_axon_trace_rd_data));

axon_spike_valid must cover BOTH host-injected axons and spikes arriving over
noc_relay -- a remote spike is an axon event, and if it is not counted here its
trace never rises and the synapse still will not learn.
""")
