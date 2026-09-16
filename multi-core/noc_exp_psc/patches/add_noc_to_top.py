#!/usr/bin/env python3
"""
Add the 4x4 crossbar NoC to sixteen_core_top_firefly -- additively.

WHY ADDITIVE AND NOT A REPLACEMENT
The existing top level already carries three things through switch_16_1 /
switch_1_16:

    1. PCIe commands from the host to every core, routed by tdest
    2. Spikes leaving the FPGA, via spike_classifier -> firefly_subsystem_top
    3. Remote spikes arriving, via remote_spike_injector -> noc_input_arbiter

Only (2) and (3) are spike traffic, and both are INTER-FPGA.  Ripping the
switches out to install the crossbar would break the command path and the whole
Firefly chain, which is already built.

The crossbar solves a different problem: core-to-core spike routing WITHIN one
FPGA, which the switches currently do only by sending everything up to the
classifier and back down.  So it is added alongside:

    core_wrapper.noc_spike_out_*  ->  noc_integration  ->  core_wrapper.noc_relay_*

Those six ports already exist on core_wrapper and on single_core, wired into
the EEP with NOC_FIFO_DEPTH(512).  Nothing on the 512-bit AXI-Stream path is
touched, so PCIe commands, the classifier, Aurora and the remote injector all
behave exactly as they do today.

BANDWIDTH NOTE
The 512-bit path carries up to 14 spikes per packet; the crossbar carries one
17-bit spike per transfer.  For core-to-core traffic that is the right trade --
a local spike no longer makes a round trip through the classifier -- but it
means the crossbar is not a drop-in for the aggregate path and should not be
made one.

host_spike_* from the crossbar is tied ready-high and left unconnected for the
first build: spikes still reach the host over the existing 512-bit path, so
consuming them twice would double-report.  Wire it only if that path is later
removed.

  python3 add_noc_to_top.py --check <sixteen_core_top_firefly.v>
  python3 add_noc_to_top.py         <sixteen_core_top_firefly.v>

Requires core_wrapper to expose route_cfg -- run add_route_cmd15.py first.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_noc_to_top.py [--check] <sixteen_core_top_firefly.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "noc_integration" in s:
    fail("%s already patched." % p)

edits = []

# 1. wires for the crossbar interface
o = """    //=========================================================================
    // PCIe/XDMA Signals
    //========================================================================="""
if s.count(o) != 1:
    fail("PCIe/XDMA signal header not found exactly once in %s" % p)
edits.append((o,
  """    //=========================================================================
    // Crossbar NoC Signals -- core-to-core spike routing within this FPGA
    //=========================================================================
    // Separate from the 512-bit AXI-Stream path above, which keeps carrying
    // PCIe commands and inter-FPGA spikes unchanged.

    wire [16:0]     core_noc_out_addr   [15:0];
    wire            core_noc_out_valid  [15:0];
    wire            core_noc_out_ready  [15:0];

    wire [16:0]     core_noc_relay_din  [15:0];
    wire            core_noc_relay_wren [15:0];
    wire            core_noc_relay_full [15:0];

    wire            core_exec_run_w     [15:0];

    // Routing table writes, one bundle per core's command interpreter
    wire            core_route_cfg_valid [15:0];
    wire [7:0]      core_route_cfg_addr  [15:0];
    wire [5:0]      core_route_cfg_data  [15:0];

    // Crossbar spikes destined for the host.  Left unconnected for the first
    // build: spikes already reach the host over the 512-bit path, and
    // consuming them here too would double-report.
    wire [16:0]     noc_host_addr  [15:0];
    wire            noc_host_valid [15:0];

""" + o, "crossbar wires"))

# 2. connect the crossbar ports on every core
o = """                // NoC RX (incoming spikes/commands)
                .s_axis_tdata   (core_rx_tdata[i]),"""
if s.count(o) != 1:
    fail("core_wrapper NoC RX hookup not found exactly once in %s" % p)
edits.append((o,
  """                // Crossbar NoC: per-spike core-to-core path.  These ports
                // already exist on core_wrapper and single_core, wired into
                // the EEP -- they were simply never connected.
                .noc_spike_out_addr  (core_noc_out_addr[i]),
                .noc_spike_out_valid (core_noc_out_valid[i]),
                .noc_spike_out_ready (core_noc_out_ready[i]),
                .noc_relay_din       (core_noc_relay_din[i]),
                .noc_relay_wren      (core_noc_relay_wren[i]),
                .noc_relay_full      (core_noc_relay_full[i]),

                // Routing table programming from this core's CI
                .route_cfg_valid     (core_route_cfg_valid[i]),
                .route_cfg_addr      (core_route_cfg_addr[i]),
                .route_cfg_data      (core_route_cfg_data[i]),

""" + o, "core_wrapper hookup"))

# 3. instantiate the interconnect
o = """    //=========================================================================
    // Spike Classifier"""
if s.count(o) != 1:
    fail("spike_classifier header not found exactly once in %s" % p)
edits.append((o,
  """    //=========================================================================
    // Crossbar NoC -- 4x4, four clusters of four cores
    //=========================================================================
    // Verified under xsim against the real sources: router 5/5, L1 bus 4/4,
    // L2 bus 5/5, and the integration layer elaborates.  Note the L2 bus
    // rewrites a forwarded packet's mask to 4'b1111, so a cross-cluster spike
    // broadcasts to all four cores in each destination cluster and the
    // receiving cores filter by neuron address.

    noc_integration #(
        .NUM_CORES (16)
    ) noc_i (
        .clk    (aclk),
        .resetn (aresetn),

        .core_spike_out_addr  (core_noc_out_addr),
        .core_spike_out_valid (core_noc_out_valid),
        .core_spike_out_ready (core_noc_out_ready),

        .core_relay_din  (core_noc_relay_din),
        .core_relay_wren (core_noc_relay_wren),
        .core_relay_full (core_noc_relay_full),

        .core_exec_run (core_exec_run_w),

        .host_spike_addr  (noc_host_addr),
        .host_spike_valid (noc_host_valid),
        .host_spike_ready ('1),

        .core_route_cfg_valid (core_route_cfg_valid),
        .core_route_cfg_addr  (core_route_cfg_addr),
        .core_route_cfg_data  (core_route_cfg_data)
    );

""" + o, "noc_integration instance"))

print("edit sites verified:")
for _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

for old, new, label in edits:
    if s.count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    s = s.replace(old, new)

bak = p + ".before_noc"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
core_exec_run_w is declared but not driven -- connect it to whatever signals a
new timestep in core_wrapper (the same source feeding the delay buffers'
timestep_tick).  The injector uses it to count spikes per timestep; leaving it
low does not break routing but disables that counter.
""")
