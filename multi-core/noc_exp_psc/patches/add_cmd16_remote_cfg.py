#!/usr/bin/env python3
"""
Add CMD 16 -- host writes to the classifier's remote destination table.

THE GAP
-------
fix_classifier_dest.py gave spike_classifier a 256-entry remote_dst table with
config ports remote_cfg_valid / remote_cfg_addr / remote_cfg_data.  Nothing
drives them.  At reset every entry reads {3'd0, LOCAL_FPGA_ID}, so every spike
resolves to this device, classifies as local, and goes to the host path.

That is the correct and safe default for an unprogrammed device -- but it means
Firefly carries no traffic even with a working link.  The table is the thing
that decides a spike is remote.

THE COMMAND
-----------
CMD 16 follows the shape of the existing single-cycle writes.  The payload
needs eight bits of block index and six bits of {server, fpga}:

    [511:504]  8'd16          opcode
    [ 13: 6]   block index    spike_addr[16:9], one entry per 512 neurons
    [  5: 3]   dst_server
    [  2: 0]   dst_fpga

Fourteen bits total, so the whole entry fits in one 512-bit packet with room
to spare.  Programming all 256 entries of one device is 256 packets.

WHY NOT REUSE CMD 15
--------------------
CMD 15 writes the on-chip routing table, which decides WHICH CORES receive a
spike within this device.  CMD 16 writes the destination table, which decides
WHICH DEVICE owns the block.  They share the same 512-neuron block index --
one partitioning decision produces both -- but they are different structures
with different widths, and merging them would mean a mode bit inside the
payload and two meanings for one opcode.

Opcodes 1,2,3,4,6,7,8 are taken by the base design; 13, 14 and 15 by the
biological, delay and routing extensions.  16 is free.

  python3 add_cmd16_remote_cfg.py --check <command_interpreter.v>
  python3 add_cmd16_remote_cfg.py         <command_interpreter.v>
"""

import sys, os

A_PARAM = "localparam [7:0] CMD_ROUTE_TBL_W = 8'd15;  // Write to network_params_sram"
N_PARAM = """localparam [7:0] CMD_ROUTE_TBL_W = 8'd15;  // Write to network_params_sram
// CMD 16: one entry of the classifier's remote destination table.
//   [13:6] block index = spike_addr[16:9]   [5:3] dst_server   [2:0] dst_fpga
// Decides which DEVICE owns a 512-neuron block.  Distinct from CMD 15, which
// decides which CORES within this device receive a spike.
localparam [7:0] CMD_REMOTE_DST_W = 8'd16;"""

A_PORT = "   output reg        execRun_done,              // execution: finished running"
N_PORT = """   output reg        execRun_done,              // execution: finished running

   // Classifier remote destination table, written by CMD 16.  Until it is
   // loaded every block resolves to this device and nothing leaves over the
   // optical link -- the safe default for an unprogrammed device.
   output reg        remote_cfg_valid,
   output reg  [7:0] remote_cfg_addr,
   output reg  [5:0] remote_cfg_data,"""

A_CASE = "               CMD_HBM_RW: begin"
N_CASE = """               // Write one entry of the classifier's remote destination table.
               CMD_REMOTE_DST_W: begin
                  remote_cfg_valid = 1'b1;
                  rxFIFO_rden      = 1'b1;
                  rx_next_state    = RX_STATE_IDLE;
               end

               CMD_HBM_RW: begin"""

A_DEFAULT = "   network_params_mem_wren = 1'b0;"
N_DEFAULT = """   network_params_mem_wren = 1'b0;

   // Defaults for the CMD 16 write strobe.  addr and data are taken
   // combinationally from the packet, so the entry lands in the same cycle
   // the command is consumed and no holding register is needed.
   remote_cfg_valid = 1'b0;
   remote_cfg_addr  = rxFIFO_dout[13:6];
   remote_cfg_data  = rxFIFO_dout[5:0];"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_cmd16_remote_cfg.py [--check] <command_interpreter.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "CMD_REMOTE_DST_W" in s:
    fail("already patched")

# opcode 16 must be free
import re
used = sorted(int(m) for m in re.findall(r"localparam \[7:0\] CMD_\w+\s*=\s*8'd(\d+)", s))
print("  opcodes already defined here: %s" % used)
if 16 in used:
    fail("opcode 16 is already in use in this file")
print("  ok  opcode 16 is free")

plan = [("param", A_PARAM, N_PARAM), ("port", A_PORT, N_PORT),
        ("case", A_CASE, N_CASE), ("defaults", A_DEFAULT, N_DEFAULT)]
for tag, a, _ in plan:
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-8s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

if check:
    print("""
--check: nothing written.

AFTER APPLYING, three further steps -- the CI is inside core_wrapper, and the
classifier is at the top, so the signals have to be threaded out:

  1. single_core.sv   add the three ports and connect them to the ci instance
  2. core_wrapper.sv  add the three ports and connect them to single_core
  3. the top          take them from core 0 and drive the classifier:
                          .remote_cfg_valid (core_remote_cfg_valid[0]),
                          .remote_cfg_addr  (core_remote_cfg_addr[0]),
                          .remote_cfg_data  (core_remote_cfg_data[0])

Core 0 alone is enough: there is ONE classifier for the device, sitting after
switch_32_1, not one per core.  A CMD 16 steered to core 0 reaches it.

Host side, the packet is

    cmd[63] = 16
    val     = (block << 6) | (server << 3) | fpga
    cmd[0]  = val & 0xFF ;  cmd[1] = (val >> 8) & 0xFF
""")
    sys.exit(0)

out = s
for _, a, n in plan:
    out = out.replace(a, n, 1)

bak = p + ".before_cmd16"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
