#!/usr/bin/env python3
"""fix_b.py [--check] SRC_DIR -- v13 option B: a spike crossing cores acts at step t+1 exactly as one inside a core,
whatever the partition.  Today a relay of step t reaches its destination's future bank before or after that core's next
exec_run depending on timing (t+1 or t+2).  B: no core reports step-done (AB CD) while any spike is in flight in the NoC,
so every relay of step t is in its destination's relay FIFO before any exec_run(t+1); the input processor's existing v10
swap (banks swap at exec_run only after the queued relays are written) then applies it at t+1.
  cores_with_noc   noc_quiet: nothing in any core's NoC output FIFO, router NoC output, L1 delivery, L2 delivery or L2
                   crossbar, for 4 consecutive cycles (registered, same clock as the cores)
  noc_integration  noc_quiet output port;  sixteen_core_noc_top: wired to every core_wrapper
  core_wrapper     NOC_BARRIER parameter (default 0; the 16-core top sets 1 on both instances) and noc_quiet input
  single_core      NOC_BARRIER (default 0: single-core use unchanged) and noc_quiet, passed to the command interpreter
  command_interp.  the final AB CD is sent only when (NOC_BARRIER == 0) or noc_quiet
Files absent from SRC_DIR are skipped (single-core source sets); command_interpreter.v and single_core.sv are required."""
import sys, os, re
chk = sys.argv[1] == "--check"; d = sys.argv[-1]
def rd(f): return open(os.path.join(d, f)).read()
def one(s, a, b, what):
    n = s.count(a)
    if n != 1: raise SystemExit("NOT APPLIED: %s found %d times" % (what, n))
    return s.replace(a, b)
out = {}
# ---------------- command interpreter (required)
s = rd("command_interpreter.v")
if "v13 B" in s: sys.exit("NOT APPLIED: already patched")
s = one(s, "   parameter CORE_ID        = 0\n   )(", "   parameter CORE_ID        = 0,\n   parameter NOC_BARRIER    = 0    // v13 B: 1 = hold the step-done (AB CD) until noc_quiet\n   )(", "CI parameter list")
s = one(s, "   input  wire        noc_spk_afull\n);",
        "   input  wire        noc_spk_afull,\n   input  wire        noc_quiet          // v13 B: no spike in flight anywhere in the NoC\n);\n"
        "// v13 B: with the barrier on, the step-done waits until no spike is in flight in the NoC, so the host cannot start\n"
        "// step t+1 before every relay of step t is in its destination's relay FIFO (applied there at t+1 by the v10 swap).\n"
        "wire noc_ok = (NOC_BARRIER == 0) || (noc_quiet == 1'b1);", "CI port list end")
s = one(s, "if (execRun_done && spk2ciFIFO_empty && !spike_rd_pending) begin",
        "if (execRun_done && spk2ciFIFO_empty && !spike_rd_pending && noc_ok) begin   // v13 B", "WAIT_FOR_SPIKES final transition")
s = one(s, "            if (execRun_done && spk2ciFIFO_empty) begin\n",
        "            if (execRun_done && spk2ciFIFO_empty && noc_ok) begin   // v13 B: AB CD only with the NoC idle\n", "SEND_SPIKES step-done condition")
out["command_interpreter.v"] = s
# ---------------- single_core (module core) (required)
s = rd("single_core.sv")
s = one(s, "    parameter [3:0] CORE_ID  = 4'd0\n    )(", "    parameter [3:0] CORE_ID  = 4'd0,\n    parameter NOC_BARRIER    = 0      // v13 B: 1 in the 16-core design (core_wrapper)\n    )(", "core parameter list")
s = one(s, "    output wire        exec_eep_phase3_done,\n", "    output wire        exec_eep_phase3_done,\n    input  wire        noc_quiet,             // v13 B (ignored when NOC_BARRIER = 0)\n", "core port exec_eep_phase3_done")
s = one(s, "        .CORE_ID(CORE_ID)    // NEW: Pass CORE_ID for spike packet tagging\n    ) ci (\n",
        "        .NOC_BARRIER(NOC_BARRIER),   // v13 B\n        .CORE_ID(CORE_ID)    // NEW: Pass CORE_ID for spike packet tagging\n    ) ci (\n        .noc_quiet(noc_quiet),       // v13 B\n", "CI instance")
out["single_core.sv"] = s
# ---------------- core_wrapper
if os.path.exists(os.path.join(d, "core_wrapper.sv")):
    s = rd("core_wrapper.sv")
    s = one(s, "    parameter [2:0] FPGA_ID = 3'd0\n)(", "    parameter [2:0] FPGA_ID = 3'd0,\n    parameter NOC_BARRIER = 0         // v13 B: 0 by default (anything not connecting noc_quiet behaves as before); the 16-core top and tb_noc16 set 1\n)(", "core_wrapper parameter list")
    s = one(s, "    output wire [2:0]  fpga_id_data\n);", "    output wire [2:0]  fpga_id_data,\n    input  wire        noc_quiet          // v13 B\n);", "core_wrapper port list end")
    m = re.findall(r"    core #\(\n        \.CORE_ID\(CORE_ID\)\n    \)\s*(\w+)\s*\(\n", s)
    if len(m) != 1: raise SystemExit("NOT APPLIED: core instance in core_wrapper found %d times" % len(m))
    s = re.sub(r"    core #\(\n        \.CORE_ID\(CORE_ID\)\n    \)\s*(\w+)\s*\(\n",
               lambda x: "    core #(\n        .NOC_BARRIER(NOC_BARRIER),   // v13 B\n        .CORE_ID(CORE_ID)\n    ) %s (\n        .noc_quiet(noc_quiet),       // v13 B\n" % x.group(1), s)
    out["core_wrapper.sv"] = s
# ---------------- cores_with_noc
if os.path.exists(os.path.join(d, "cores_with_noc.sv")):
    s = rd("cores_with_noc.sv")
    s = one(s, "    output logic [NUM_CORES-1:0]    injector_overflow\n);",
            "    output logic [NUM_CORES-1:0]    injector_overflow,\n    output logic                    noc_quiet          // v13 B: no spike anywhere in the NoC (see below)\n);", "cores_with_noc port list end")
    blk = ("    // =========================================================================\n"
           "    // v13 B: noc_quiet -- every place a spike can wait between a core's NoC output and a destination's relay FIFO\n"
           "    // is empty: the cores' NoC output FIFOs (core_spike_valid = !empty), the routers' NoC output stages, the L1 buses'\n"
           "    // registered deliveries to cores (injectors are pass-through into the relay FIFOs), the L2 bus's held deliveries\n"
           "    // to clusters, and the L2 crossbar and its senders (l2_bus_busy).  Each hand-off moves a spike between these on\n"
           "    // one clock edge, so no cycle hides one; 4 consecutive idle cycles are required anyway.  The routers' host\n"
           "    // path (local spikes, ready tied 1) carries no relay and is not included.\n"
           "    // =========================================================================\n"
           "    wire noc_busy = (|core_spike_valid) | (|router_spike_valid) | (|injector_spike_valid) | (|l2_to_l1_valid) | l2_bus_busy;\n"
           "    logic [2:0] noc_quiet_cnt;\n"
           "    always_ff @(posedge clk or negedge resetn) begin\n"
           "        if (!resetn)                   noc_quiet_cnt <= 3'd0;\n"
           "        else if (noc_busy)             noc_quiet_cnt <= 3'd0;\n"
           "        else if (noc_quiet_cnt != 3'd4) noc_quiet_cnt <= noc_quiet_cnt + 3'd1;\n"
           "    end\n"
           "    assign noc_quiet = (noc_quiet_cnt == 3'd4) && !noc_busy;\n\n")
    a = "    // =========================================================================\n    // Router Overflow Status\n"
    s = one(s, a, blk + a, "cores_with_noc router-overflow section")
    out["cores_with_noc.sv"] = s
# ---------------- noc_integration
if os.path.exists(os.path.join(d, "noc_integration.sv")):
    s = rd("noc_integration.sv")
    s = one(s, "    input  wire [5:0]  core_route_cfg_data  [NUM_CORES-1:0]\n);",
            "    input  wire [5:0]  core_route_cfg_data  [NUM_CORES-1:0],\n    output wire        noc_quiet               // v13 B: no spike in flight anywhere in the NoC\n);", "noc_integration port list end")
    s = one(s, "        .core_exec_run (w_exec_run)\n    );", "        .noc_quiet     (noc_quiet),            // v13 B\n        .core_exec_run (w_exec_run)\n    );", "cores_with_noc instance end")
    out["noc_integration.sv"] = s
# ---------------- 16-core top
if os.path.exists(os.path.join(d, "sixteen_core_noc_top.sv")):
    s = rd("sixteen_core_noc_top.sv")
    s = one(s, "    noc_integration #(\n        .NUM_CORES (16)\n    ) noc_i (\n        .clk                  (aclk),\n",
            "    wire noc_quiet;   // v13 B: NoC idle, from noc_integration to every core's command interpreter\n"
            "    noc_integration #(\n        .NUM_CORES (16)\n    ) noc_i (\n        .clk                  (aclk),\n        .noc_quiet            (noc_quiet),            // v13 B\n", "top noc_integration instance")
    n = len(re.findall(r"core_wrapper my_core\(\n", s))
    if n != 2: raise SystemExit("NOT APPLIED: core_wrapper instances in the top found %d times (expected 2)" % n)
    s = re.sub(r"core_wrapper my_core\(\n", "core_wrapper #(.NOC_BARRIER(1)) my_core(\n                    .noc_quiet(noc_quiet),   // v13 B: barrier on in the 16-core design\n", s)
    out["sixteen_core_noc_top.sv"] = s
if chk: print("CHECK OK (%s)" % ", ".join(sorted(out))); sys.exit(0)
for f, s in out.items():
    p = os.path.join(d, f); open(p + ".before_b", "w").write(open(p).read()); open(p, "w").write(s)
print("B applied to %d files: %s" % (len(out), ", ".join(sorted(out))))
