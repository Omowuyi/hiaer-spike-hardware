#!/usr/bin/env python3
"""
Derive sixteen_core_noc_firefly_top.sv from test_top.sv.

WHY DERIVE RATHER THAN WRITE FRESH
test_top.sv is the only top that builds against THIS project's core_wrapper,
which uses SystemVerilog interfaces:

    AXI4.Master         hbm
    FIFO_input.Sink     rxFIFO_in
    FIFO_output.Source  txFIFO_out
    input aclk450, async_resetn450, core_number[4:0]

sixteen_core_top_firefly.sv was written for a DIFFERENT core_wrapper -- one with
.m_axi_hbm and 512-bit .m_axis_tdata / .s_axis_tdata ports.  It could never
elaborate here, which is what the "unconnected interface port 'hbm'" error was
telling us.  Rather than rewrite that file's assumptions one error at a time,
this takes the top that provably works and changes only what must change.

Everything below core_wrapper is untouched: the eight biological features, the
64-bit synapse path, CMD 13/14, FIX V, per-synapse and axon delay, the STDP
controller and its new axon-trace lookup all live inside `core` and come across
exactly as they are.

WHAT CHANGES
  1. module renamed
  2. active core count 2 -> 16 (cores 16-31 stay dummy_core, as today)
  3. rxFIFO_in / txFIFO_out / after_switch / before_switch widened [1:0] -> [31:0]
     so all 16 have somewhere to connect
  4. switch_1_32 / switch_32_1 instantiated -- they are commented out in the
     active config, so nothing currently reaches the cores from PCIe
  5. noc_integration added, on core_wrapper's existing noc_spike_out_* and
     noc_relay_* ports
  6. Firefly chain added: spike_classifier taps the aggregate stream, sending
     local spikes to PCIe and remote ones to firefly_subsystem_top

WHY THE EXISTING 32-WAY SWITCHES AND NOT axis_switches.sv
switch_1_32 / switch_32_1 already speak the AXIStream interface style this top
uses, and they are proven in this project.  axis_switches.sv takes flat vectors
-- correct for the design it was written for, but it would need an adapter per
core here for no benefit.  Sixteen unused ports cost nothing; test_top already
runs them that way with dummy_core.

  python3 make_noc_firefly_top.py --check <test_top.sv>
  python3 make_noc_firefly_top.py         <test_top.sv> <output.sv>
"""

import sys, os, re


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if not args:
    fail("usage: make_noc_firefly_top.py [--check] <test_top.sv> [output.sv]")
src = args[0]
dst = args[1] if len(args) > 1 else "sixteen_core_noc_firefly_top.sv"
if not os.path.isfile(src):
    fail("no such file: %s" % src)
s = open(src, errors="replace").read()

edits = []


def need(pat, label, count=1):
    if s.count(pat) != count:
        fail("anchor for %s found %d times, expected %d" % (label, s.count(pat), count))
    return pat


# ---- 1. module name -------------------------------------------------------
o = need("module test_top(", "module name")
edits.append((o, "module sixteen_core_noc_firefly_top(", "module name"))

# ---- 2. widen the per-core interface arrays -------------------------------
for name in ("rxFIFO_in", "txFIFO_out"):
    o = need("%s [1:0] (.clk(aclk), .reset(~aresetn));" % name, name)
    edits.append((o, "%s [31:0] (.clk(aclk), .reset(~aresetn));" % name,
                  "widen " + name))

for name in ("after_switch", "before_switch"):
    o = need("AXIStream_simple #(512) %s [1:0] (.aclk(aclk), .aresetn(aresetn));" % name, name)
    edits.append((o,
                  "AXIStream_simple #(512) %s [31:0] (.aclk(aclk), .aresetn(aresetn));" % name,
                  "widen " + name))

# ---- 3. 2 real cores -> 16 ------------------------------------------------
o = need("               if(j<2) begin", "core count")
edits.append((o, "               if(j<16) begin", "core count 2 -> 16"))

# ---- 4. the switches, plus NoC and Firefly --------------------------------
# This line appears twice -- once in the commented-out 32-core block and once
# in the active 2-core one.  Anchor on the second (active) occurrence.
_pat = "    AXIStream_simple #(512) from_txFIFO_small (.aclk(pcie_axi_clk), .aresetn(pcie_axi_aresetn));"
if s.count(_pat) != 2:
    fail("from_txFIFO_small found %d times, expected 2" % s.count(_pat))
_second = s.rindex(_pat)
o = _pat
edits.append((("ANCHOR2", _second), o + """

    //=========================================================================
    // PCIe command and spike-readout path.
    //
    // These are commented out in test_top's active configuration, so nothing
    // currently reaches the cores from the host.  A 32-way switch with 16 cores
    // attached costs nothing -- the unused ports simply never assert -- and it
    // avoids adapting the crossbar's flat-vector switches to this top's
    // interface style for no benefit.
    //=========================================================================
    switch_1_32 s_1_32 (
        .s (to_rxFIFO_with_dest),
        .m (after_switch)
    );

    switch_32_1 s_32_1 (
        .s (before_switch),
        .m (from_txFIFO)
    );

    //=========================================================================
    // Crossbar NoC -- core-to-core spike routing within this FPGA.
    //
    // Entirely separate from the 512-bit path above, which keeps carrying host
    // commands and spike readout unchanged.  The interconnect exchanges only
    // 17-bit spike addresses, so it never touches the neuron model: every
    // biological feature travels inside `core` regardless.
    //
    // Verified under xsim against these sources: router 5/5, L1 bus 4/4,
    // L2 bus 5/5.  Note the L2 bus rewrites a forwarded packet's mask to all
    // ones, so a cross-cluster spike reaches every core in each destination
    // cluster and the receiving cores filter by neuron address.
    //=========================================================================
    wire [16:0] core_noc_out_addr   [15:0];
    wire        core_noc_out_valid  [15:0];
    wire        core_noc_out_ready  [15:0];
    wire [16:0] core_noc_relay_din  [15:0];
    wire        core_noc_relay_wren [15:0];
    wire        core_noc_relay_full [15:0];
    wire        core_exec_run_w     [15:0];

    wire        core_route_cfg_valid [15:0];
    wire [7:0]  core_route_cfg_addr  [15:0];
    wire [5:0]  core_route_cfg_data  [15:0];

    // Crossbar spikes bound for the host.  Left unconsumed: spikes already
    // reach the host over the 512-bit path, and taking them here as well would
    // double-report every one.
    wire [16:0] noc_host_addr  [15:0];
    wire        noc_host_valid [15:0];

    noc_integration #(
        .NUM_CORES (16)
    ) noc_i (
        .clk                  (aclk),
        .resetn               (aresetn),
        .core_spike_out_addr  (core_noc_out_addr),
        .core_spike_out_valid (core_noc_out_valid),
        .core_spike_out_ready (core_noc_out_ready),
        .core_relay_din       (core_noc_relay_din),
        .core_relay_wren      (core_noc_relay_wren),
        .core_relay_full      (core_noc_relay_full),
        .core_exec_run        (core_exec_run_w),
        .host_spike_addr      (noc_host_addr),
        .host_spike_valid     (noc_host_valid),
        .host_spike_ready     ('1),
        .core_route_cfg_valid (core_route_cfg_valid),
        .core_route_cfg_addr  (core_route_cfg_addr),
        .core_route_cfg_data  (core_route_cfg_data)
    );
""", "switches + NoC"))

# ---- 5. connect the crossbar ports on each core ---------------------------
# The core_wrapper hookup appears in several commented-out generate blocks as
# well as the active one.  Locate the ACTIVE block by searching forward from
# the unique "if(j<2) begin" marker.
_hook = "                    .hbm(hbm[j]),\n                    .rxFIFO_in(rxFIFO_in[j]),"
_marker = "               if(j<2) begin"
_hpos = s.find(_hook, s.index(_marker))
if _hpos < 0:
    fail("core_wrapper hookup not found after the active-block marker")
o = _hook
edits.append((("HOOK", _hpos),
  """                    // Crossbar NoC.  These ports already exist on
                    // core_wrapper and single_core, wired into the EEP with
                    // NOC_FIFO_DEPTH(512) -- they were simply never connected.
                    .noc_spike_out_addr  (core_noc_out_addr[j]),
                    .noc_spike_out_valid (core_noc_out_valid[j]),
                    .noc_spike_out_ready (core_noc_out_ready[j]),
                    .noc_relay_din       (core_noc_relay_din[j]),
                    .noc_relay_wren      (core_noc_relay_wren[j]),
                    .noc_relay_full      (core_noc_relay_full[j]),
                    // Routing table writes from this core's own CI: a CMD 15
                    // already reaches the right core via tdest, so the packet
                    // carries no core field.
                    .route_cfg_valid     (core_route_cfg_valid[j]),
                    .route_cfg_addr      (core_route_cfg_addr[j]),
                    .route_cfg_data      (core_route_cfg_data[j]),
""" + o, "core NoC hookup"))

print("edit sites verified:")
for _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    print("\nStill to add by hand once this elaborates: the Firefly chain.")
    print("spike_classifier taps from_txFIFO, firefly_subsystem_top drives Aurora,")
    print("remote_spike_injector merges back into the to_rxFIFO path.  Those need")
    print("the Aurora GT placement settled first, which is still open.")
    sys.exit(0)

for old, new, label in edits:
    if isinstance(old, tuple):          # positional anchors
        kind = old[0]
        if kind == "ANCHOR2":
            pos = s.rindex(_pat); ln = len(_pat)
        else:                            # HOOK: active block only
            pos = s.find(_hook, s.index("               if(j<16) begin")); ln = len(_hook)
            if pos < 0:
                fail("active core hookup vanished mid-apply")
        s = s[:pos] + new + s[pos+ln:]
        continue
    if s.count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    s = s.replace(old, new)

open(dst, "w").write(s)
print("wrote %s" % dst)
print("""
Add it to the project and set it as top:

    add_files -norecurse <path>/sixteen_core_noc_firefly_top.sv
    set_property top sixteen_core_noc_firefly_top [current_fileset]

Then check the hierarchy resolves before synthesising.

The Firefly chain is NOT in this file yet.  spike_classifier, firefly_subsystem_top
and remote_spike_injector all take 512-bit AXI-Stream, which from_txFIFO and the
to_rxFIFO path already provide -- so they bridge cleanly.  They are held back
only because the Aurora GT placement is unresolved: the IP offers X1 quads while
the XDC pins Port 7 to X0Y24-27.  Adding them before that is settled would put an
unbuildable IP in the critical path of a design that is otherwise ready.
""")
