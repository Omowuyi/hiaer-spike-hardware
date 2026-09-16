#!/usr/bin/env python3
"""
Add a remote egress port to noc_spike_router -- Firefly readiness.

THE PROBLEM WITH OVERLOADING THE LEVEL FIELD
An earlier design note proposed repurposing OP_NOP as REMOTE.  That forces a
block to be either local or remote:

    entry says LOCAL   -> remote targets silently never receive the spike
    entry says REMOTE  -> local  targets silently never receive the spike

Both are silent spike loss, which is the exact failure class that cost days on
the microphase bug.  A design that forces the choice is wrong.

THE FIX -- ORTHOGONAL FLAG
Leave level and mask alone; they decide ON-CHIP delivery and are already
verified by simulation (tb_router 5/5, tb_l1 and tb_l2 under xsim).  Add one
independent bit consulted in parallel:

    level[1:0] + mask[3:0]   unchanged -- LOCAL / L1 / L2 as today
    remote_en                one bit per 512-neuron block

A spike can now be both.  The router emits on-chip per the level AND to the
egress port when remote_en is set.  OP_NOP stays available as a genuine drop
code, and noc_l1_bus / noc_l2_bus are untouched -- so everything the three
xsim runs verified keeps behaving identically.

WHY THE TABLE IS PER FPGA, NOT PER CORE
Whether a destination block lives off-chip depends on the BLOCK, not on which
core emitted the spike.  One 256-bit RAM per FPGA, indexed by the same
spike_addr[16:9].  It pairs with a remote_dst table giving {server, fpga} for
the same index.

SERVER-TO-SERVER FALLS OUT OF THE SAME STRUCTURE
remote_dst is {server[2:0], fpga[2:0]}.  If server != my_server the egress
goes to the 100G plane; otherwise to Aurora.  Same table, same lookup, one
comparison to pick the port.  No third mechanism.

WHAT THIS PATCH DOES
Adds to noc_spike_router:
    input  logic        remote_en_in      lookup result for this spike's block
    output logic [16:0] spike_addr_remote
    output logic        spike_valid_remote
    input  logic        spike_ready_remote

The remote path is a parallel tap on the accepted spike -- it does not steal
from the NoC or host paths, so on-chip routing is bit-identical to today.

  python3 add_remote_egress.py --check <noc_spike_router.sv>
  python3 add_remote_egress.py         <noc_spike_router.sv>

The remote_en / remote_dst tables and the egress packet builder are separate
modules, not part of this patch.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_remote_egress.py [--check] <noc_spike_router.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "remote_en_in" in s:
    fail("%s already patched." % p)

edits = []

o = """    // =========================================================================
    // Routing Table Configuration Interface
    // ========================================================================="""
if s.count(o) != 1:
    fail("routing-table config header not found exactly once in %s" % p)
edits.append((o,
  """    // =========================================================================
    // Remote Egress -- Firefly / inter-server
    // =========================================================================
    // remote_en_in is the per-block lookup from the FPGA-wide remote table,
    // presented alongside spike_addr_in.  It is ORTHOGONAL to level/mask: a
    // block may be delivered on-chip AND off-chip.  Forcing a choice between
    // them would silently drop one set of targets.
    input  logic        remote_en_in,
    output logic [16:0] spike_addr_remote,
    output logic        spike_valid_remote,
    input  logic        spike_ready_remote,

""" + o, "remote ports"))

o = """    logic [5:0] route_table [ROUTE_TABLE_SIZE-1:0];"""
if s.count(o) != 1:
    fail("route_table declaration not found exactly once in %s" % p)
edits.append((o,
  o + """

    // -------------------------------------------------------------------------
    // Remote egress tap.  A parallel copy of any accepted spike whose block is
    // marked remote.  It does not consume from the NoC or host paths, so
    // on-chip routing behaviour is unchanged -- which is what keeps the
    // verified tb_router / tb_l1 / tb_l2 results valid.
    // -------------------------------------------------------------------------
    logic [16:0] remote_addr_hold;
    logic        remote_valid_hold;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            remote_addr_hold  <= 17'd0;
            remote_valid_hold <= 1'b0;
        end else begin
            if (remote_valid_hold && spike_ready_remote)
                remote_valid_hold <= 1'b0;
            if (spike_valid_in && spike_ready_in && remote_en_in) begin
                remote_addr_hold  <= spike_addr_in;
                remote_valid_hold <= 1'b1;
            end
        end
    end

    assign spike_addr_remote  = remote_addr_hold;
    assign spike_valid_remote = remote_valid_hold;""", "remote tap"))

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

bak = p + ".before_remote"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
cores_with_noc must now pass remote_en_in per core and expose the three
spike_*_remote signals.  Re-run the xsim testbenches afterwards: with
remote_en_in tied low the on-chip results must be bit-identical to the
current 5/5, 4/4 and 5/5.
""")
