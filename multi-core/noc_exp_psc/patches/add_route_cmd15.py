#!/usr/bin/env python3
"""
NoC routing-table write command -- opcode 15 -- for the biological core.

WHY OPCODE 15
The biological command_interpreter already uses CMD 13 for PSC parameters
(syn_64bit_en at bit 131) and CMD 14 for the axon delay table.  The NoC design
notes drafted routing at 13, which would collide.  Opcode 15 is free in both.

WHY NO CORE FIELD
Every core has its own command_interpreter, and commands already reach the
right one via tdest / coreID.  So a CMD 15 addressed to core c is decoded by
core c's CI, which programs core c's own router.  The packet needs only the
table address and the entry:

    [511:504] = 15
    [ 13:  6] = addr   (0-255, indexed by spike_addr[16:9])
    [  5:  0] = data   {level[1:0], mask[3:0]}

cores_with_noc still expects a single route_cfg bundle with a core selector,
so noc_integration.v combines the sixteen per-core bundles -- only one core
receives a given CMD 15, so only one asserts at a time.

TABLE FORMAT, verified from noc_spike_router.sv by simulation
    256 entries per core, indexed by spike_addr[16:9] -- one entry per
    512-neuron block.  Six bits: [5:4] level, [3:0] mask.
    OP_NOP=00, OP_LOCAL=01, OP_L1=10, OP_L2=11.  Reset {OP_LOCAL, 4'b0000}.

  python3 add_route_cmd15.py --check <command_interpreter.v> <single_core.sv> <core_wrapper.sv>
  python3 add_route_cmd15.py         <command_interpreter.v> <single_core.sv> <core_wrapper.sv>

Apply to the BIOLOGICAL files -- the ones carrying FIX A-J, CMD 13 and CMD 14.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 3:
    fail("usage: add_route_cmd15.py [--check] <command_interpreter.v> "
         "<single_core.sv> <core_wrapper.sv>")
ci_p, sc_p, cw_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

ci = open(ci_p).read()
sc = open(sc_p).read()
cw = open(cw_p).read()
for p, s in ((ci_p, ci), (sc_p, sc), (cw_p, cw)):
    if "route_cfg" in s:
        fail("%s already mentions route_cfg -- already patched?" % p)

edits = []

# ---------------- command_interpreter ----------------
o = "localparam [7:0] CMD_NTWK_PARAM_MEM_W  = 8'd8;"
if ci.count(o) != 1:
    fail("CMD_NTWK_PARAM_MEM_W localparam not found exactly once in %s" % ci_p)
edits.append((ci_p, o,
  o + "\n// NoC routing table write, one entry per packet.  13 and 14 are taken\n"
      "// by the PSC parameters and the axon delay table.\n"
      "//   [13:6]=addr, [5:0]={level[1:0], mask[3:0]}\n"
      "localparam [7:0] CMD_ROUTE_TBL_W = 8'd15;", "CI opcode 15"))

# Anchor on a base-CI port so this applies whether or not the spike-drop
# detector has been added.
o = "   input        iep_uram_out_of_range,\n"
if ci.count(o) != 1:
    fail("iep_uram_out_of_range input not found exactly once in %s (%d)"
         % (ci_p, ci.count(o)))
edits.append((ci_p, o,
  o + "\n   // NoC routing table programming for THIS core's router\n"
      "   output reg        route_cfg_valid,\n"
      "   output reg [7:0]  route_cfg_addr,\n"
      "   output reg [5:0]  route_cfg_data,\n", "CI ports"))

o = "wire [7:0] rx_command = rxFIFO_dout[511:504];"
if ci.count(o) != 1:
    fail("rx_command wire not found exactly once in %s" % ci_p)
edits.append((ci_p, o,
  o + "\n\n"
      "//=========================================================================\n"
      "// NoC routing table write.  Single-cycle pulse with the fields held\n"
      "// alongside it; noc_spike_router latches on route_cfg_valid.\n"
      "//=========================================================================\n"
      "always @(posedge clk) begin\n"
      "    if (~aresetn) begin\n"
      "        route_cfg_valid <= 1'b0;\n"
      "        route_cfg_addr  <= 8'd0;\n"
      "        route_cfg_data  <= 6'd0;\n"
      "    end else begin\n"
      "        route_cfg_valid <= 1'b0;\n"
      "        if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty &&\n"
      "            rx_command == CMD_ROUTE_TBL_W) begin\n"
      "            route_cfg_addr  <= rxFIFO_dout[13:6];\n"
      "            route_cfg_data  <= rxFIFO_dout[5:0];\n"
      "            route_cfg_valid <= 1'b1;\n"
      "        end\n"
      "    end\n"
      "end", "CI capture"))

# ---------------- single_core ----------------
o = "    output wire [16:0] noc_spike_out_addr,"
if sc.count(o) != 1:
    fail("noc_spike_out_addr port not found exactly once in %s -- is this the "
         "biological single_core with the NoC interface?" % sc_p)
edits.append((sc_p, o,
  "    // NoC routing table programming, from this core's CI\n"
  "    output wire        route_cfg_valid,\n"
  "    output wire [7:0]  route_cfg_addr,\n"
  "    output wire [5:0]  route_cfg_data,\n\n" + o, "SC ports"))

# The IEP instance also carries iep_uram_out_of_range, so anchor on the CI
# instance's neighbouring ports to stay unique.
o = ("        .iep_uram_out_of_range(iep_uram_out_of_range_w),\n"
     "        .user_irq(user_irq),")
if sc.count(o) != 1:
    fail("CI instance anchor not found exactly once in %s (%d)"
         % (sc_p, sc.count(o)))
edits.append((sc_p, o,
  "        .iep_uram_out_of_range(iep_uram_out_of_range_w),\n"
  "        .route_cfg_valid(route_cfg_valid),\n"
  "        .route_cfg_addr(route_cfg_addr),\n"
  "        .route_cfg_data(route_cfg_data),\n"
  "        .user_irq(user_irq),", "SC CI hookup"))

# ---------------- core_wrapper ----------------
o = "    output wire [16:0] noc_spike_out_addr,"
if cw.count(o) != 1:
    fail("noc_spike_out_addr port not found exactly once in %s" % cw_p)
edits.append((cw_p, o,
  "    // NoC routing table programming, passed up from this core's CI\n"
  "    output wire        route_cfg_valid,\n"
  "    output wire [7:0]  route_cfg_addr,\n"
  "    output wire [5:0]  route_cfg_data,\n\n" + o, "CW ports"))

o = "        .noc_spike_out_addr(noc_spike_out_addr),"
if cw.count(o) != 1:
    fail("noc_spike_out_addr hookup not found exactly once in %s" % cw_p)
edits.append((cw_p, o,
  "        .route_cfg_valid(route_cfg_valid),\n"
  "        .route_cfg_addr(route_cfg_addr),\n"
  "        .route_cfg_data(route_cfg_data),\n" + o, "CW hookup"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {ci_p: ci, sc_p: sc, cw_p: cw}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_route15"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Host side: send CMD 15 to core c with [13:6]=addr and [5:0]={level,mask}.
noc_routing.py generates the tables; its packet builder needs the core field
dropped and the opcode changed from 13 to 15.
""")
