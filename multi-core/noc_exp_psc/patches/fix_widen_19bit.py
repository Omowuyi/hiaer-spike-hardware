#!/usr/bin/env python3
"""
Widen the neuron address from seventeen bits to nineteen.

WHY
---
The neuron state memory of a core is four thousand and ninety-six ultra-RAM
rows of seventy-two bits, of which rows nought to two thousand and forty-seven
hold the first row of each neuron and the remainder hold the second. Sixteen
neurons share a row, one to each group, so a core can hold

    2,048 rows x 16 groups = 32,768 neurons

and sixteen cores hold 524,288. Naming that many neurons within one device
takes nineteen bits.

Nothing in the neuron datapath prevents it. The sweep bound is num_outputs
divided by sixteen, written by the host, and the microphase counter already
divides a sweep longer than eight thousand one hundred and ninety-two into
passes of that size. What confines the machine to 131,072 is the width of the
address that names a neuron, which is seventeen bits everywhere it travels.

WHERE THE BITS COME FROM
------------------------
Three carriers are already full, and each has a field that is written and never
read.

The thirty-two bit packet on the network on chip is opcode, source core,
destination mask, address and a five-bit timestamp. The timestamp is set by the
packing function in noc_pkg and read nowhere, so two of its bits pass to the
address and three remain.

The sixty-four bit packet on the optical link ends in sixteen bits of payload,
set to one by the classifier and read nowhere, so two pass to the address and
fourteen remain.

The thirty-two bit word that carries a spike to the host is timestamp, valid,
two reserved bits, core and address. The reserved pair passes to the address and
the core moves up by two.

The synaptic entry in the delay buffer is fifty-eight bits with three unused at
the top, two of which extend the destination row.

WHAT IS NOT CHANGED
-------------------
num_outputs and num_inputs are counts of neurons and axons within one core, not
addresses. Seventeen bits already express thirty-two thousand seven hundred and
sixty-eight, and the row limit derived from them, at thirteen bits, already
expresses two thousand and forty-eight.

The axon memory stays at eight thousand one hundred and ninety-two rows of
sixteen groups, 131,072 axons per core. That bounds how many distinct sources
may reach one core, which is a different quantity from how many neurons a core
holds, and it is generous. Growing it would change the microphase division of
the events processor and belongs to its own revision.

The noise value in the internal events processor is seventeen bits of sign and
magnitude and is not an address. The refractory parameter slice at line seven
hundred and ninety-seven is not an address either.

  python3 fix_widen_19bit.py --check <imports directory>
  python3 fix_widen_19bit.py         <imports directory>
"""

import sys, os, re

# ---------------------------------------------------------------- plain widths
# Every declaration of a signal that carries a neuron address. Each is matched
# as an exact line so that a count or a noise value cannot be caught by mistake.
WIDTHS = {
 # noc_integration sits between the top and the core group and carries the
 # same addresses. It was missed by a file list written from memory; the
 # directory-wide sweep found it.
 "noc_integration.sv": [
   ("    input  wire [16:0] core_spike_out_addr  [NUM_CORES-1:0],",
    "    input  wire [18:0] core_spike_out_addr  [NUM_CORES-1:0],"),
   ("    output wire [16:0] core_relay_din       [NUM_CORES-1:0],",
    "    output wire [18:0] core_relay_din       [NUM_CORES-1:0],"),
   ("    output wire [16:0] host_spike_addr      [NUM_CORES-1:0],",
    "    output wire [18:0] host_spike_addr      [NUM_CORES-1:0],"),
   ("    logic [16:0]           w_core_spike_addr  [NUM_CORES-1:0];",
    "    logic [18:0]           w_core_spike_addr  [NUM_CORES-1:0];"),
   ("    logic [16:0]           w_relay_addr       [NUM_CORES-1:0];",
    "    logic [18:0]           w_relay_addr       [NUM_CORES-1:0];"),
   ("    logic [16:0]           w_host_addr        [NUM_CORES-1:0];",
    "    logic [18:0]           w_host_addr        [NUM_CORES-1:0];")],
 "spike_fifo_controller.v": [
   ("    input  [16:0] spk0_dout,", "    input  [18:0] spk0_dout,"),
   ("    input  [16:0] spk1_dout,", "    input  [18:0] spk1_dout,"),
   ("    input  [16:0] spk2_dout,", "    input  [18:0] spk2_dout,"),
   ("    input  [16:0] spk3_dout,", "    input  [18:0] spk3_dout,"),
   ("    input  [16:0] spk4_dout,", "    input  [18:0] spk4_dout,"),
   ("    input  [16:0] spk5_dout,", "    input  [18:0] spk5_dout,"),
   ("    input  [16:0] spk6_dout,", "    input  [18:0] spk6_dout,"),
   ("    input  [16:0] spk7_dout,", "    input  [18:0] spk7_dout,"),
   ("    output reg [16:0] spk2ciFIFO_din,",
    "    output reg [18:0] spk2ciFIFO_din,"),
   # the two default assignments differ only by indentation, so each anchor
   # carries the line before it to be unique
   ("\n    spk2ciFIFO_din  = 17'dX;", "\n    spk2ciFIFO_din  = 19'dX;"),
   ("\n            spk2ciFIFO_din  = 17'dX;", "\n            spk2ciFIFO_din  = 19'dX;")],
 "command_interpreter.v": [
   ("   input            [16:0] spk2ciFIFO_dout,     // [16:0]=spiked neuron address",
    "   input            [18:0] spk2ciFIFO_dout,     // [18:0]=spiked neuron address")],
 "core_wrapper.sv": [
   ("    output wire [16:0] noc_spike_out_addr,",
    "    output wire [18:0] noc_spike_out_addr,"),
   ("    input  wire [16:0] noc_relay_din,",
    "    input  wire [18:0] noc_relay_din,")],
 "cores_with_noc.sv": [
   ("    input  logic [16:0] core_spike_addr [NUM_CORES-1:0],",
    "    input  logic [18:0] core_spike_addr [NUM_CORES-1:0],"),
   ("    output logic [16:0] core_noc_relay_addr [NUM_CORES-1:0],",
    "    output logic [18:0] core_noc_relay_addr [NUM_CORES-1:0],"),
   ("    output logic [16:0] host_spike_addr [NUM_CORES-1:0],",
    "    output logic [18:0] host_spike_addr [NUM_CORES-1:0],"),
   ("    logic [16:0] router_spike_addr [NUM_CORES-1:0];",
    "    logic [18:0] router_spike_addr [NUM_CORES-1:0];"),
   ("    logic [16:0] injector_spike_addr [NUM_CORES-1:0];",
    "    logic [18:0] injector_spike_addr [NUM_CORES-1:0];"),
   ("    logic [16:0] l1_spike_addr [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];",
    "    logic [18:0] l1_spike_addr [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];"),
   ("    logic [16:0] l1_rx_addr [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];",
    "    logic [18:0] l1_rx_addr [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];")],
 "external_events_processor_simple.v": [
   ("   input  wire [16:0] noc_relay_din,           // 17-bit spike address from NoC",
    "   input  wire [18:0] noc_relay_din,           // 19-bit spike address from NoC"),
   ("wire [16:0] noc_fifo_dout;", "wire [18:0] noc_fifo_dout;"),
   ("reg [16:0] noc_fifo_mem [NOC_FIFO_DEPTH-1:0];",
    "reg [18:0] noc_fifo_mem [NOC_FIFO_DEPTH-1:0];")],
 "hiaer_firefly_pkg.sv": [
   # the address grows by two and the payload gives them up, so the packet is
   # still sixty-four bits. The payload is set to one by the classifier and
   # read nowhere.
   ("        logic [16:0]    dst_neuron;     // [50:34]",
    "        logic [18:0]    dst_neuron;     // [52:34]"),
   ("        logic [15:0]    payload;        // [15:0]  Weight/flags",
    "        logic [13:0]    payload;        // [13:0]  Weight/flags, written and unread")],
 "internal_events_processor.v": [
   ("    output reg [16:0] stdp_spike_addr,   // spiked neuron full address",
    "    output reg [18:0] stdp_spike_addr,   // spiked neuron full address"),
   ("        stdp_spike_addr <= 17'd0;", "        stdp_spike_addr <= 19'd0;")],
 "noc_l1_bus.sv": [
   ("    input  logic [16:0] spike_addr_in [NUM_CORES-1:0],",
    "    input  logic [18:0] spike_addr_in [NUM_CORES-1:0],"),
   ("    output logic [16:0] spike_addr_out [NUM_CORES-1:0],",
    "    output logic [18:0] spike_addr_out [NUM_CORES-1:0],"),
   ("    logic [16:0] xbar_addr [NUM_CORES-1:0];",
    "    logic [18:0] xbar_addr [NUM_CORES-1:0];"),
   ("    logic [16:0] rx_addr_int [NUM_CORES-1:0];",
    "    logic [18:0] rx_addr_int [NUM_CORES-1:0];")],
 "noc_spike_injector.sv": [
   ("    input  logic [16:0] noc_spike_addr,",
    "    input  logic [18:0] noc_spike_addr,"),
   ("    output logic [16:0] noc_relay_addr,    // 17-bit spike address (passthrough)",
    "    output logic [18:0] noc_relay_addr,    // 19-bit spike address (passthrough)")],
 "noc_spike_router.sv": [
   ("    input  logic [16:0] spike_addr_in,",
    "    input  logic [18:0] spike_addr_in,"),
   ("    output logic [16:0] spike_addr_out,",
    "    output logic [18:0] spike_addr_out,"),
   ("    output logic [16:0] spike_addr_host,",
    "    output logic [18:0] spike_addr_host,"),
   ("    logic [16:0] addr_reg;", "    logic [18:0] addr_reg;")],
 "single_core.sv": [
   ("    output wire [16:0] noc_spike_out_addr,",
    "    output wire [18:0] noc_spike_out_addr,"),
   ("    input  wire [16:0] noc_relay_din,",
    "    input  wire [18:0] noc_relay_din,"),
   ("    wire [16:0] w_stdp_spike_addr;         // IEP \u2192 stdp_controller: spiked neuron addr",
    "    wire [18:0] w_stdp_spike_addr;         // IEP \u2192 stdp_controller: spiked neuron addr"),
   # the eight per-group spike queues and the one that reaches the command
   # interpreter carry a neuron address and are parameterised by its width
   ("    FIFO_input #(17) spk_in [7:0] (.clk(aclk450), .reset(~aresetn450));",
    "    FIFO_input #(19) spk_in [7:0] (.clk(aclk450), .reset(~aresetn450));"),
   ("    FIFO_input #(17) spk2ci_in (.clk(aclk450), .reset(~aresetn450));",
    "    FIFO_input #(19) spk2ci_in (.clk(aclk450), .reset(~aresetn450));"),
   ("    FIFO_output #(17) spk_out [7:0] (.clk(aclk450), .reset(~aresetn450));",
    "    FIFO_output #(19) spk_out [7:0] (.clk(aclk450), .reset(~aresetn450));"),
   ("    FIFO_output #(17) spk2ci_out (.clk(aclk), .reset(~aresetn));",
    "    FIFO_output #(19) spk2ci_out (.clk(aclk), .reset(~aresetn));"),
],
 "sixteen_core_noc_firefly_top.sv": [
   ("    wire [16:0] core_noc_out_addr   [15:0];",
    "    wire [18:0] core_noc_out_addr   [15:0];"),
   ("    wire [16:0] core_noc_relay_din  [15:0];",
    "    wire [18:0] core_noc_relay_din  [15:0];"),
   ("    wire [16:0] noc_host_addr  [15:0];",
    "    wire [18:0] noc_host_addr  [15:0];")],
 "spike_classifier.sv": [
   ("    logic [16:0]    spike_addr [MAX_SPIKES-1:0];",
    "    logic [18:0]    spike_addr [MAX_SPIKES-1:0];"),
   ("            spike_addr[i] <= 17'd0;", "            spike_addr[i] <= 19'd0;")],
}

# ------------------------------------------------------------ slices and depth
STRUCTURAL = {
 # the row of an address is everything above the four group bits
 "external_events_processor_simple.v": [
   ("wire [12:0] noc_neuron_addr = noc_fifo_dout[16:4];   // Row address",
    "wire [14:0] noc_neuron_addr = noc_fifo_dout[18:4];   // Row address")],
 # the routing table is indexed by the address above the block offset, and a
 # nineteen-bit address makes one thousand and twenty-four blocks of 512
 "noc_spike_router.sv": [
   ("    wire [7:0] route_idx = spike_addr_in[16:9];",
    "    wire [9:0] route_idx = spike_addr_in[18:9];"),
   ("    input  logic [7:0]  route_cfg_addr,    // Which entry to configure",
    "    input  logic [9:0]  route_cfg_addr,    // Which entry to configure")],
 "spike_classifier.sv": [
   ("    parameter int         BLOCK_BITS    = 8      // addr[16:9] -> 256 blocks",
    "    parameter int         BLOCK_BITS    = 10     // addr[18:9] -> 1024 blocks"),
   ("    logic [5:0] remote_dst [0:255];",
    "    logic [5:0] remote_dst [0:1023];"),
   ("    input  logic [7:0]      remote_cfg_addr,",
    "    input  logic [9:0]      remote_cfg_addr,"),
   ("    function automatic logic [2:0] get_dest_fpga(input logic [16:0] addr);",
    "    function automatic logic [2:0] get_dest_fpga(input logic [18:0] addr);"),
   ("        return remote_dst[addr[16:9]][2:0];",
    "        return remote_dst[addr[18:9]][2:0];"),
   ("    function automatic logic [2:0] get_dest_server(input logic [16:0] addr);",
    "    function automatic logic [2:0] get_dest_server(input logic [18:0] addr);"),
   ("        return remote_dst[addr[16:9]][5:3];",
    "        return remote_dst[addr[18:9]][5:3];"),
   ("    function automatic logic [3:0] get_dest_core(input logic [16:0] addr);",
    "    function automatic logic [3:0] get_dest_core(input logic [18:0] addr);"),
   ("    function automatic logic [16:0] get_dest_neuron(input logic [16:0] addr);",
    "    function automatic logic [18:0] get_dest_neuron(input logic [18:0] addr);"),
   # the thirty-two bit word the classifier reads: the address grows by two and
   # the source core moves up with it
   ("                        spike_addr[i] <= packet_reg[32*(i+1) +: 17];  // Neuron address",
    "                        spike_addr[i] <= packet_reg[32*(i+1) +: 19];  // Neuron address"),
   ("                        spike_dst_fpga[i] <= get_dest_fpga(packet_reg[32*(i+1) +: 17]);",
    "                        spike_dst_fpga[i] <= get_dest_fpga(packet_reg[32*(i+1) +: 19]);"),
   ("                        spike_dst_core[i] <= get_dest_core(packet_reg[32*(i+1) +: 17]);",
    "                        spike_dst_core[i] <= get_dest_core(packet_reg[32*(i+1) +: 19]);"),
   ("                            if (get_dest_fpga(packet_reg[32*(i+1) +: 17]) == LOCAL_FPGA_ID) begin",
    "                            if (get_dest_fpga(packet_reg[32*(i+1) +: 19]) == LOCAL_FPGA_ID) begin"),
   ("            m_firefly_spike.src_core    = packet_reg[32*(spike_idx+1) + 17 +: 4];",
    "            m_firefly_spike.src_core    = packet_reg[32*(spike_idx+1) + 19 +: 4];")],
 # the packet on the network on chip: two bits from the unread timestamp
 "noc_pkg.sv": [
   ("        logic [16:0] neuron_addr;  // [21:5]  Neuron address\n        logic [4:0]  timestamp;    // [4:0]   Timestamp LSBs",
    "        logic [18:0] neuron_addr;  // [21:3]  Neuron address\n        logic [2:0]  timestamp;    // [2:0]   Timestamp LSBs, written and unread"),
   ("        input logic [16:0] neuron_addr,",
    "        input logic [18:0] neuron_addr,"),
   ("        input logic [4:0]  timestamp",
    "        input logic [2:0]  timestamp")],
 "noc_l1_bus.sv": [
   ("        spike_addr_in[l2_tx_sel],\n        5'b0",
    "        spike_addr_in[l2_tx_sel],\n        3'b0"),
   ("                            rx_addr_int[d] = l2_rx_data[21:5];",
    "                            rx_addr_int[d] = l2_rx_data[21:3];")],
 # the word that carries a spike to the host: the reserved pair becomes address
 "command_interpreter.v": [
   ("      // 16-core ready: CORE_ID[3:0] in [20:17], FPGA_ID reserved in [22:21]\n      spike_sr    <= {execRun_ctr[7:0], 1'b1, 2'b00, CORE_ID[3:0], spk2ciFIFO_dout, spike_sr[447:32]};",
    "      // CORE_ID[3:0] now sits at [22:19] and the address occupies [18:0].\n      // The two bits formerly reserved at [22:21] are part of the address.\n      spike_sr    <= {execRun_ctr[7:0], 1'b1, CORE_ID[3:0], spk2ciFIFO_dout, spike_sr[447:32]};")],
 # the word the injector builds, matching the above
 "remote_spike_injector.sv": [
   ("        result[22:21] = 2'b00;\n        result[20:17] = spike.dst_core;",
    "        result[22:19] = spike.dst_core;"),
   ("        result[16:0] = spike.dst_neuron;",
    "        result[18:0] = spike.dst_neuron;")],
 # the diagnostic threshold, which counts spikes above one microphase
 "hbm_processor.v": [
   ("    (spk0_wren & (spk0_din >= 17'd8192)) | (spk1_wren & (spk1_din >= 17'd8192)) |\n    (spk2_wren & (spk2_din >= 17'd8192)) | (spk3_wren & (spk3_din >= 17'd8192)) |\n    (spk4_wren & (spk4_din >= 17'd8192)) | (spk5_wren & (spk5_din >= 17'd8192)) |\n    (spk6_wren & (spk6_din >= 17'd8192)) | (spk7_wren & (spk7_din >= 17'd8192));",
    "    (spk0_wren & (spk0_din >= 19'd8192)) | (spk1_wren & (spk1_din >= 19'd8192)) |\n    (spk2_wren & (spk2_din >= 19'd8192)) | (spk3_wren & (spk3_din >= 19'd8192)) |\n    (spk4_wren & (spk4_din >= 19'd8192)) | (spk5_wren & (spk5_din >= 19'd8192)) |\n    (spk6_wren & (spk6_din >= 19'd8192)) | (spk7_wren & (spk7_din >= 19'd8192));")],
}
for n in range(8):
    STRUCTURAL.setdefault("hbm_processor.v", []).append(
        ("    output [16:0] spk%d_din," % n, "    output [18:0] spk%d_din," % n))


def fail(m):
    sys.stderr.write("\nABORT: %s\nNothing was written to any file.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_widen_19bit.py [--check] <imports directory>")
D = args[0]
if not os.path.isdir(D):
    fail("not a directory: %s" % D)

edits = {}
for src in (WIDTHS, STRUCTURAL):
    for f, lst in src.items():
        edits.setdefault(f, []).extend(lst)

files = {}
for f in edits:
    p = os.path.join(D, f)
    if not os.path.isfile(p):
        fail("missing file: %s" % p)
    raw = open(p, errors="replace").read()
    files[f] = (p, raw, "\r\n" in raw, raw.replace("\r\n", "\n"))

total = sum(len(v) for v in edits.values())
print("Verifying %d edits across %d files.\n" % (total, len(edits)))
ok = bad = done = 0
for f in sorted(edits):
    s = files[f][3]
    for old, new in edits[f]:
        n = s.count(old)
        if n == 1:
            ok += 1
        elif n == 0 and new in s:
            done += 1          # a previous run already applied this one
        else:
            bad += 1
            print("  MISS  %-38s matched %d: %s" % (f, n, old.strip()[:60]))
    print("  %-38s %d edits" % (f, len(edits[f])))

print("\n%d verified, %d already applied, %d not found." % (ok, done, bad))
if bad:
    fail("%d anchors did not match exactly once." % bad)

if check:
    print("""
--check: nothing written. Every anchor matches exactly once.

Widths that carry an address become nineteen bits. The routing table and the
destination table grow to one thousand and twenty-four entries. Two bits are
taken from the unread timestamp of the packet on the network on chip, two from
the unread payload of the optical packet, and two from the pair reserved in the
word that reaches the host, where the core identifier moves up to sit above the
address.

Elaborate before synthesising. A width left behind truncates an address
silently; it does not fail.
""")
    sys.exit(0)

for f in files:
    p, raw, crlf, s = files[f]
    for old, new in edits[f]:
        s = s.replace(old, new, 1)
    bak = p + ".before_19bit"
    if not os.path.exists(bak):
        open(bak, "w").write(raw)
    open(p, "w").write(s.replace("\n", "\r\n") if crlf else s)
    print("  patched %s" % f)

print("\nAll files patched. Backups end .before_19bit")
print("A core may now hold 32,768 neurons and a device 524,288.")
