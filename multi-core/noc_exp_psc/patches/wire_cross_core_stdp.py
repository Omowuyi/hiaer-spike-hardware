#!/usr/bin/env python3
"""
Wire cross-core STDP: axon_trace_mem into single_core, fed by the EEP scan.

WHAT IS ALREADY THERE
  EEP  line 213  assign curr_bram_waddr = bramPresent_waddr;
  EEP  line 274  assign exec_eep_spiked = bramPresent_rdata;

  The EEP's own comment says raddr LEADS and waddr LAGS.  waddr trails raddr by
  PIPE_DEPTH, which is the BRAM read latency, so waddr is the row address of the
  currently-valid rdata.  The alignment is already computed by the design.

WHAT IS MISSING
  1. a valid strobe.  bramPresent_wren asserts exactly when a row is consumed,
     but it is internal to the EEP.
  2. a timestep counter.  exec_run is used as a tick but nothing counts it, and
     axon_trace_mem needs timestep[4:0] for its lazy decay.
  3. the axon_trace_mem instance itself.

WHAT IS WRONG
  stdp_controller line 90 reads

      wire [12:0] src_axon_idx = e_src[12:0];

  e_src is 18 bits: bit 17 is the axon flag and [16:0] is the index.  Taking
  [12:0] discards the top four bits, collapsing sixteen distinct axons onto
  every trace address.  axon_trace_mem splits a 17-bit index as
  {row[12:0], group[3:0]}, so the top four bits ARE the group.  Dropping them
  means every lookup returns group 0 of the right row -- wrong for fifteen
  axons out of sixteen, and silently so.

  This patch widens the port and the slice to 17 bits.

Run --check first.  Every edit is anchored and the script refuses to write
unless every anchor matches exactly once.

  python3 wire_cross_core_stdp.py --check <dir>
  python3 wire_cross_core_stdp.py         <dir>

where <dir> is the imports directory holding the three files.
"""

import sys, os

EDITS = [
# ---------------------------------------------------------------- EEP -------
("external_events_processor_simple.v", [
 ("port",
  "    output [2:0]  eep_curr_state,",
  "    output [2:0]  eep_curr_state,\n"
  "    // Asserts on the cycle bramPresent_rdata is valid for bramPresent_waddr,\n"
  "    // so {curr_bram_waddr, exec_eep_spiked} name a fired axon row.\n"
  "    output        axon_row_valid,"),
 ("drive",
  "assign curr_bram_waddr = bramPresent_waddr;",
  "assign curr_bram_waddr = bramPresent_waddr;\n"
  "assign axon_row_valid  = bramPresent_wren;"),
]),

# ------------------------------------------------------- stdp_controller ----
("stdp_controller.v", [
 ("port_width",
  "    output reg  [12:0] axon_trace_rd_idx,",
  "    output reg  [16:0] axon_trace_rd_idx,"),
 ("slice",
  "    wire [12:0] src_axon_idx = e_src[12:0];",
  "    // e_src[16:0] is the full axon index; axon_trace_mem splits it as\n"
  "    // {row[12:0], group[3:0]}.  Taking only [12:0] dropped the group.\n"
  "    wire [16:0] src_axon_idx = e_src[16:0];"),
]),
]

INSTANCE = """
    //=========================================================================
    // Cross-core STDP: eligibility traces for incoming axons.
    //
    // A presynaptic neuron on another core holds its trace in that core's
    // memory, which this core cannot read.  Carrying the trace in the spike
    // packet does not work either: potentiation is evaluated when the
    // POSTsynaptic neuron fires, generally a later timestep, so a trace
    // sampled at emission is stale by the time it is used.
    //
    // This core does receive every such spike -- that is how the synapse
    // fires at all -- so it reconstructs the trace locally.  Spikes arriving
    // over noc_relay enter as axon events, exactly like host-injected ones,
    // so one write port covers both.
    //=========================================================================
    reg [4:0] axon_trace_timestep;
    always @(posedge aclk) begin
        if (~aresetn)      axon_trace_timestep <= 5'd0;
        else if (exec_run) axon_trace_timestep <= axon_trace_timestep + 5'd1;
    end

    wire        w_axon_trace_rd_en;
    wire [16:0] w_axon_trace_rd_idx;
    wire [3:0]  w_axon_trace_rd_data;

    axon_trace_mem u_axon_trace (
        .clk           (aclk),
        .resetn        (aresetn),
        .timestep      (axon_trace_timestep),
        .timestep_tick (exec_run),
        .row_fired     (w_axon_row_valid),
        .row_addr      (w_curr_bram_waddr),
        .row_mask      (exec_eep_spiked),
        .trace_rd_en   (w_axon_trace_rd_en),
        .trace_rd_idx  (w_axon_trace_rd_idx),
        .trace_rd_data (w_axon_trace_rd_data)
    );

"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv[1:]
    if len(args) != 1:
        fail("usage: wire_cross_core_stdp.py [--check] <imports-dir>")
    d = args[0]
    if not os.path.isdir(d):
        fail("no such directory: %s" % d)

    plan = []
    for fname, edits in EDITS:
        p = os.path.join(d, fname)
        if not os.path.isfile(p):
            fail("missing file: %s" % p)
        s = open(p, errors="replace").read()
        for tag, old, new in edits:
            n = s.count(old)
            if n == 0 and new.split("\n")[0].strip() in s:
                fail("%s: edit '%s' looks already applied" % (fname, tag))
            if n != 1:
                fail("%s: anchor '%s' matched %d times, expected 1" % (fname, tag, n))
            plan.append((p, fname, tag, old, new))
        print("  ok  %-38s %d anchor(s) verified" % (fname, len(edits)))

    # single_core: the instance, plus the three stdp connections
    sc = os.path.join(d, "single_core.sv")
    if not os.path.isfile(sc):
        fail("missing file: %s" % sc)
    s = open(sc, errors="replace").read()
    for name, need in (("curr_bram_waddr", 1), ("exec_eep_spiked", 1),
                       ("stdp_controller stdp_ctrl (", 1)):
        if s.count(name) < need:
            fail("single_core.sv: expected '%s' and did not find it" % name)
    if "axon_trace_mem u_axon_trace" in s:
        fail("single_core.sv: instance already present")
    print("  ok  %-38s references verified" % "single_core.sv")

    print("\nEdits planned:")
    for _, fname, tag, old, _ in plan:
        print("  %-38s %-12s %s" % (fname, tag, old.strip()[:56]))
    print("  %-38s %-12s %s" % ("single_core.sv", "instance", "axon_trace_mem u_axon_trace"))

    if check:
        print("\n--check: nothing written.")
        print("""
STILL TO DO BY HAND, because these depend on names this script cannot verify:

  1. single_core.sv must expose the EEP's new axon_row_valid.  Add to the EEP
     instantiation:   .axon_row_valid(w_axon_row_valid),
     and declare:     wire w_axon_row_valid;
     curr_bram_waddr is already an output PORT of single_core; you need it as
     an internal wire too, so add:  wire [12:0] w_curr_bram_waddr;
     and change the EEP connection to drive both.

  2. Connect the three stdp_controller ports, which are currently left open:
        .axon_trace_rd_en   (w_axon_trace_rd_en),
        .axon_trace_rd_idx  (w_axon_trace_rd_idx),
        .axon_trace_rd_data (w_axon_trace_rd_data)

  3. Add axon_trace_mem.v to the Vivado project.

  4. Re-run the STDP testbench: widening src_axon_idx changes which trace a
     synapse reads, so any prior single-core STDP result must be re-taken.
""")
        return

    for p, fname, tag, old, new in plan:
        s = open(p, errors="replace").read()
        bak = p + ".before_xstdp"
        if not os.path.exists(bak):
            open(bak, "w").write(s)
        open(p, "w").write(s.replace(old, new, 1))
    print("\npatched %d file(s); backups written with .before_xstdp" % len({p for p, *_ in plan}))
    print("single_core.sv NOT modified -- see the --check notes for the manual steps")


main()
