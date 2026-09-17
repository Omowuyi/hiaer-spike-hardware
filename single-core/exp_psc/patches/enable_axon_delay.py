#!/usr/bin/env python3
"""
Enable the per-axon delay table.  CMD 14 (0x0E).

axon_delay_buffer already implements per-axon delay completely: an 8192x6-bit
BRAM table, an immediate bypass for delay==0, a 64-slot circular buffer and a
drain FSM.  It has never been usable because single_core.v hardwires

    wire [12:0] w_delay_table_waddr = 13'd0;
    wire [5:0]  w_delay_table_wdata = 6'd0;
    wire        w_delay_table_wr    = 1'b0;

so the table can never be written.  Block RAM initialises to zero, every axon
delay reads 0, and every event takes the immediate bypass -- 96 BRAM36 doing
nothing.

This adds CMD 14 to write one table entry and wires it through.  Needs NO
synapse-format change and NO recompilation: it is orthogonal to syn_64bit_en.

  packet:  [511:504] = 8'd14
           [503:496] = coreID
           [ 18:  6] = axon address (13 bits)
           [  5:  0] = delay in timesteps (6 bits, 0-63)

  usage:
    python3 enable_axon_delay.py --check <command_interpreter.v> <single_core.v>
    python3 enable_axon_delay.py         <command_interpreter.v> <single_core.v>

Opcode 14 is free: 1,2,3,4,6,7,8,9,10,11,12,13 are taken, and 0x0D is the NoC
routing-table command in the multicore build.
"""

import sys, os

def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 2:
    fail("usage: enable_axon_delay.py [--check] <command_interpreter.v> <single_core.v>")
ci_p, sc_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

edits = []
ci = open(ci_p).read()
sc = open(sc_p).read()

if "CMD_AXON_DELAY_W" in ci:
    fail("%s already defines CMD_AXON_DELAY_W -- already patched?" % ci_p)

# --- opcode ---
o = "localparam [7:0] CMD_SET_PSC_PARAMS = 8'd13;\n"
if ci.count(o) != 1:
    fail("CMD_SET_PSC_PARAMS localparam not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o +
  "// Per-axon delay table write.  [18:6]=axon addr, [5:0]=delay (0-63).\n"
  "localparam [7:0] CMD_AXON_DELAY_W   = 8'd14;\n", "opcode 14"))

# --- outputs ---
o = "   output reg        syn_64bit_en\n"
if ci.count(o) != 1:
    fail("syn_64bit_en output not found exactly once in %s.\n"
         "       Run wire_syn64.py first." % ci_p)
edits.append((ci_p, o,
  "   output reg        syn_64bit_en,\n\n"
  "   // Per-axon delay table programming (CMD 14) -> axon_delay_buffer\n"
  "   output reg [12:0] delay_table_waddr,\n"
  "   output reg [5:0]  delay_table_wdata,\n"
  "   output reg        delay_table_wr\n", "CI outputs"))

# --- capture + default ---
o = "        syn_64bit_en <= 1'b0;  // default: 32-bit entries\n"
if ci.count(o) != 1:
    fail("syn_64bit_en reset line not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o +
  "        delay_table_waddr <= 13'd0;\n"
  "        delay_table_wdata <= 6'd0;\n"
  "        delay_table_wr    <= 1'b0;\n", "CI reset"))

o = "    if(rx_curr_state == RX_STATE_WAIT_RUN) begin\n"
if ci.count(o) != 1:
    fail("RX_STATE_WAIT_RUN counter block not found exactly once in %s" % ci_p)
edits.append((ci_p, o,
  "    // CMD 14: one axon delay table entry per packet.  Single-cycle pulse.\n"
  "    delay_table_wr <= 1'b0;\n"
  "    if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty &&\n"
  "        rx_command == CMD_AXON_DELAY_W) begin\n"
  "        delay_table_waddr <= rxFIFO_dout[18:6];\n"
  "        delay_table_wdata <= rxFIFO_dout[5:0];\n"
  "        delay_table_wr    <= 1'b1;\n"
  "    end\n" + o, "CI capture"))

# --- RX state machine case arm ---
o = ("               CMD_SET_PSC_PARAMS: begin\n"
     "                  rxFIFO_rden = 1'b1;\n"
     "                  rx_next_state = RX_STATE_IDLE;\n"
     "               end\n")
if ci.count(o) != 1:
    fail("CMD_SET_PSC_PARAMS case arm not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o +
  "               // Per-axon delay table write; registers captured above.\n"
  "               CMD_AXON_DELAY_W: begin\n"
  "                  rxFIFO_rden = 1'b1;\n"
  "                  rx_next_state = RX_STATE_IDLE;\n"
  "               end\n", "CI case arm"))

# --- single_core: untie ---
o = ("    wire [12:0] w_delay_table_waddr = 13'd0;\n"
     "    wire [5:0]  w_delay_table_wdata = 6'd0;\n"
     "    wire        w_delay_table_wr    = 1'b0;\n")
if sc.count(o) != 1:
    fail("delay table tie-offs not found exactly once in %s" % sc_p)
edits.append((sc_p, o,
  "    // Driven by the CI from CMD 14 (was hardwired to 0, so the table could\n"
  "    // never be written and every axon delay stayed at 0).\n"
  "    wire [12:0] w_delay_table_waddr;\n"
  "    wire [5:0]  w_delay_table_wdata;\n"
  "    wire        w_delay_table_wr;\n", "SC untie"))

o = "        .syn_64bit_en(w_syn_64bit_en)\n    );\n"
if sc.count(o) != 1:
    fail("CI instance end not found exactly once in %s.\n"
         "       Run wire_syn64.py first." % sc_p)
edits.append((sc_p, o,
  "        .syn_64bit_en(w_syn_64bit_en),\n"
  "        .delay_table_waddr(w_delay_table_waddr),\n"
  "        .delay_table_wdata(w_delay_table_wdata),\n"
  "        .delay_table_wr(w_delay_table_wr)\n    );\n", "SC CI hookup"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {ci_p: ci, sc_p: sc}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_axondelay"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Host side -- one packet per axon:

    def write_axon_delay(axon_addr, delay, coreID=0):
        cmd = np.zeros(512, dtype=int)
        cmd[:8]    = list(np.binary_repr(14, 8))
        cmd[8:16]  = list(np.binary_repr(coreID, 8))
        cmd[-19:-6] = list(np.binary_repr(axon_addr, 13))
        cmd[-6:]    = list(np.binary_repr(delay, 6))
        dma_dump_write(_cmd_to_uint64_array(cmd), 64, 1, 0, 0, 0, DmaMethodNormal)
""")
