#!/usr/bin/env python3
"""
FIX AC -- spike_classifier derives the destination FPGA from neuron-address bits.

THE BUG
    function automatic logic [2:0] get_dest_fpga(input logic [16:0] addr);
        return addr[16:14];
    endfunction

That assumes a 17-bit spike address is laid out fpga(3) + core(4) + neuron(10),
i.e. 1024 neurons per core.  A core holds 8192.  The full 17 bits are the
neuron index within one FPGA -- 16 cores x 8192 = 131072 = 2^17 exactly -- so
addr[16:14] is the TOP OF THE NEURON INDEX, not an FPGA number.

As written, every neuron above 16383 would be classified as belonging to
another FPGA and shipped over Aurora instead of delivered locally.  get_dest_core
and get_dest_neuron are wrong for the same reason.

WHY IT CANNOT BE DERIVED AT ALL
Which FPGA holds a neuron is a property of the PARTITION, not of the address.
That is exactly why the NoC has a routing table rather than decoding the
address: the same 17-bit space is mapped differently by every partition.  The
inter-FPGA layer needs the same treatment.

THE FIX
A per-FPGA table indexed by addr[16:9] -- the same 512-neuron block granularity
the NoC routing table already uses, so one partitioning decision drives both:

    remote_dst[256] = { server[2:0], fpga[2:0] }

Held in registers rather than BRAM: the classifier evaluates up to 14 spikes in
one packet, and a BRAM would need 14 sequential reads.  256 x 6 = 1536 flops
allows all of them to read combinationally, so the existing timing is unchanged.

The destination CORE is not sent.  The receiving FPGA's own routing tables
decide which cores a spike reaches, exactly as for a locally generated one.
dst_neuron already carries the full 17 bits, so nothing in the packet changes.

Loading: CMD 16, one entry per packet.
    [511:504] = 16
    [ 13: 6]  = addr   (0-255, the block)
    [  5: 0]  = data   { server[2:0], fpga[2:0] }

  python3 fix_classifier_dest.py --check <spike_classifier.sv>
  python3 fix_classifier_dest.py         <spike_classifier.sv>
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_classifier_dest.py [--check] <spike_classifier.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "remote_dst" in s:
    fail("%s already patched." % p)

edits = []

# 1. table + config ports
o = "    parameter logic [2:0] LOCAL_FPGA_ID = 3'd0"
if s.count(o) != 1:
    fail("LOCAL_FPGA_ID parameter not found exactly once in %s" % p)
edits.append((o, o + """,
    parameter int         BLOCK_BITS    = 8      // addr[16:9] -> 256 blocks""",
  "parameter"))

o = "    output logic [511:0]    m_pcie_tdata,"
if s.count(o) != 1:
    fail("m_pcie_tdata port not found exactly once in %s" % p)
edits.append((o,
  """    //=========================================================================
    // FIX AC: remote destination table.  Which FPGA holds a neuron is a
    // property of the partition, not of the address -- the same reason the NoC
    // uses a routing table instead of decoding bits.  Loaded by CMD 16.
    //=========================================================================
    input  logic            remote_cfg_valid,
    input  logic [7:0]      remote_cfg_addr,
    input  logic [5:0]      remote_cfg_data,   // {server[2:0], fpga[2:0]}

""" + o, "config ports"))

# 2. the table itself, and a corrected lookup
o = """    function automatic logic [2:0] get_dest_fpga(input logic [16:0] addr);
        return addr[16:14];
    endfunction"""
if s.count(o) != 1:
    fail("get_dest_fpga not found exactly once in %s" % p)
edits.append((o,
  """    //=========================================================================
    // FIX AC: destination lookup, one entry per 512-neuron block.
    //
    // Registers, not BRAM: up to 14 spikes in a packet are classified in the
    // same cycle, and a BRAM would force 14 sequential reads.  256 x 6 = 1536
    // flops is negligible on this part and keeps the timing as it was.
    //
    // Reset value 0 means "this FPGA", so an unprogrammed table behaves as a
    // single-FPGA system rather than scattering spikes onto Aurora.
    //=========================================================================
    logic [5:0] remote_dst [0:255];

    integer ri;
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            for (ri = 0; ri < 256; ri = ri + 1)
                remote_dst[ri] <= {3'd0, LOCAL_FPGA_ID};
        end else if (remote_cfg_valid) begin
            remote_dst[remote_cfg_addr] <= remote_cfg_data;
        end
    end

    function automatic logic [2:0] get_dest_fpga(input logic [16:0] addr);
        // addr[16:9] selects the 512-neuron block -- the same granularity the
        // NoC routing table uses, so one partition drives both.
        return remote_dst[addr[16:9]][2:0];
    endfunction

    function automatic logic [2:0] get_dest_server(input logic [16:0] addr);
        return remote_dst[addr[16:9]][5:3];
    endfunction""", "table and lookup"))

# 3. the core field is not the sender's to decide
o = """    function automatic logic [3:0] get_dest_core(input logic [16:0] addr);
        return addr[13:10];
    endfunction"""
if s.count(o) != 1:
    fail("get_dest_core not found exactly once in %s" % p)
edits.append((o,
  """    // FIX AC: the destination CORE is not the sender's to decide.  The
    // receiving FPGA's routing tables select cores from the neuron address,
    // exactly as they do for a locally generated spike, and a spike may reach
    // several cores there.  Sending a single core index would be both wrong
    // and unnecessary -- dst_neuron already carries the full 17 bits.
    function automatic logic [3:0] get_dest_core(input logic [16:0] addr);
        return 4'd0;
    endfunction""", "core field"))

o = """    function automatic logic [9:0] get_dest_neuron(input logic [16:0] addr);
        return addr[9:0];
    endfunction"""
if s.count(o) != 1:
    fail("get_dest_neuron not found exactly once in %s" % p)
edits.append((o,
  """    // FIX AC: the whole 17-bit address is the neuron index within the
    // destination FPGA.  Truncating to 10 bits assumed 1024 neurons per core;
    // a core holds 8192.
    function automatic logic [16:0] get_dest_neuron(input logic [16:0] addr);
        return addr;
    endfunction""", "neuron field"))

# 5. dst_server was hardcoded, which cannot work across servers
o = "            m_firefly_spike.dst_server  = 3'd0;  // Same server"
if s.count(o) != 1:
    fail("dst_server assignment not found exactly once in %s (%d)"
         % (p, s.count(o)))
edits.append((o,
  "            // FIX AC: was hardcoded 3'd0, which confines the system to one\n"
  "            // server.  The same table that names the FPGA names the server,\n"
  "            // so multi-server needs no extra mechanism -- only a partition\n"
  "            // that fills these entries.\n"
  "            m_firefly_spike.dst_server  = get_dest_server(spike_addr[spike_idx]);",
  "dst_server from the table"))

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

bak = p + ".before_destfix"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
Two follow-ups:

  1. sixteen_core_top_firefly must drive remote_cfg_valid/addr/data.  Add a
     CMD 16 handler alongside the CMD 15 routing-table one.

  2. Wherever the classifier assigns dst_server in the packet, it should call
     get_dest_server(addr) rather than a constant.  Check the assignment near
     m_firefly_spike.
""")
