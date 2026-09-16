#!/usr/bin/env python3
"""
Complete the cross-core STDP wiring in single_core.sv.

Run wire_cross_core_stdp.py FIRST -- this depends on the EEP already exposing
axon_row_valid and on stdp_controller carrying a 17-bit axon_trace_rd_idx.

FOUR EDITS
  1. Declare the internal wires and the 5-bit timestep counter.
     curr_bram_waddr is an output PORT of single_core, so the EEP drives both
     the port and a new internal wire.  exec_run is already the timestep tick
     used by both delay buffers; nothing counts it, so this adds the counter
     axon_trace_mem needs for its lazy decay.

  2. Extend the EEP instantiation with .axon_row_valid and redirect
     .curr_bram_waddr onto the internal wire, then drive the port from it.

  3. Instantiate axon_trace_mem after the stdp_controller.

  4. Connect the three stdp_controller ports currently left open, which
     synthesis reports as
        port 'axon_trace_rd_en'   ... is unconnected
        port 'axon_trace_rd_idx'  ... is unconnected
        port 'axon_trace_rd_data' ... is unconnected

WHY THE ROW/MASK PAIR IS CORRECT
  The EEP comment states raddr LEADS and waddr LAGS.  waddr trails raddr by
  PIPE_DEPTH, the BRAM read latency, so on the cycle bramPresent_wren asserts,
  bramPresent_waddr is the row whose mask is on bramPresent_rdata.  Those are
  exposed as curr_bram_waddr and exec_eep_spiked, so the triple
  {axon_row_valid, curr_bram_waddr, exec_eep_spiked} names a fired axon row
  with no extra alignment logic.

  This is the PRESENT bank, which is the bank being applied this timestep.  A
  spike arriving over noc_relay was written to the FUTURE bank and is scanned
  next timestep, so it is counted then -- which is when its synapses fire.

  python3 wire_stdp_single_core.py --check <path-to-single_core.sv>
  python3 wire_stdp_single_core.py         <path-to-single_core.sv>
"""

import sys, os

A_DECL = "    wire     [15:0] exec_eep_spiked;"
N_DECL = """    wire     [15:0] exec_eep_spiked;

    //=========================================================================
    // Cross-core STDP support signals.
    //
    // curr_bram_waddr is an output port; the EEP now drives an internal wire
    // and the port is driven from it, so axon_trace_mem can see it too.
    //=========================================================================
    wire            w_axon_row_valid;
    wire     [12:0] w_curr_bram_waddr;
    assign curr_bram_waddr = w_curr_bram_waddr;

    wire            w_axon_trace_rd_en;
    wire     [16:0] w_axon_trace_rd_idx;
    wire     [3:0]  w_axon_trace_rd_data;

    // exec_run is the timestep tick already used by both delay buffers.
    // axon_trace_mem needs a counter of it for decay-on-read.
    reg      [4:0]  axon_trace_timestep;
    always @(posedge aclk) begin
        if (~aresetn)      axon_trace_timestep <= 5'd0;
        else if (exec_run) axon_trace_timestep <= axon_trace_timestep + 5'd1;
    end"""

A_EEP = "        .curr_bram_waddr(curr_bram_waddr)\n    );"
N_EEP = "        .curr_bram_waddr(w_curr_bram_waddr),\n        .axon_row_valid(w_axon_row_valid)\n    );"

A_INST = """                                  iep_uram[3].rdata,  iep_uram[2].rdata,  iep_uram[1].rdata,  iep_uram[0].rdata})
    );"""
N_INST = """                                  iep_uram[3].rdata,  iep_uram[2].rdata,  iep_uram[1].rdata,  iep_uram[0].rdata}),
        .axon_trace_rd_en(w_axon_trace_rd_en),
        .axon_trace_rd_idx(w_axon_trace_rd_idx),
        .axon_trace_rd_data(w_axon_trace_rd_data)
    );

    //=========================================================================
    // Eligibility traces for incoming axons.
    //
    // A presynaptic neuron on another core keeps its trace in that core's
    // memory, which this core cannot read.  Sending the trace inside the spike
    // packet does not help either: potentiation is evaluated when the
    // POSTsynaptic neuron fires, generally a later timestep, so a value
    // sampled at emission is already stale.
    //
    // This core receives every such spike -- that is how the synapse fires at
    // all -- so it rebuilds the trace itself.  Spikes from the NoC enter as
    // axon events exactly like host-injected ones, so one write port serves
    // both, and the mechanism extends unchanged to spikes from other devices.
    //=========================================================================
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
    );"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: wire_stdp_single_core.py [--check] <single_core.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)

raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "axon_trace_mem u_axon_trace" in s:
    fail("already patched: axon_trace_mem instance present")

for tag, a in (("decl", A_DECL), ("eep", A_EEP), ("stdp", A_INST)):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-6s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

print("\nline endings: %s" % ("CRLF, preserved" if crlf else "LF"))

if check:
    print("""
--check: nothing written.

After applying, still to do:
  * add axon_trace_mem.v to the Vivado project
      add_files -norecurse <path>/axon_trace_mem.v
  * re-run the STDP tests.  src_axon_idx changed from 13 to 17 bits, so a
    synapse now reads its own axon's trace instead of group 0's.  Any earlier
    single-core STDP measurement is superseded.
""")
    sys.exit(0)

s = s.replace(A_DECL, N_DECL, 1)
s = s.replace(A_EEP, N_EEP, 1)
s = s.replace(A_INST, N_INST, 1)

bak = p + ".before_xstdp"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(s.replace("\n", "\r\n") if crlf else s)
print("\npatched %s (backup %s)" % (p, bak))
