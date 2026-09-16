#!/usr/bin/env python3
"""
Let the host reach every entry of the widened routing table.

THE DEFECT
----------
Widening the neuron address to nineteen bits divided the neuron space of a
device into 1,024 blocks of 512 rather than 256, and the router's table grew to
match: it is indexed by spike_addr[18:9] and holds 1,024 entries.

The path by which the host writes that table did not grow. From the command
interpreter, through the core and the core wrapper, up to the top level and back
down through the interconnect to the router, the table address is eight bits at
every step. Eight bits reach 256 entries.

The consequence is quiet. The remaining 768 entries keep their reset value,
which is the local code with an empty mask, so a spike whose address falls in
them is dropped rather than delivered. The design elaborates, builds and runs;
it simply loses every spike addressed above neuron 131,071, which is the range
the widening exists to reach.

Synthesis reports it as sixteen width mismatches, one per core, and a width
mismatch is a warning rather than an error.

WHAT THIS WRITES
----------------
Ten declarations become ten bits, and the command that programs the table takes
two more bits of its payload. The command travels in the 512-bit host packet and
used fourteen of them, eight of address and six of data; it now uses sixteen.

  python3 fix_route_cfg_width.py --check <imports directory>
  python3 fix_route_cfg_width.py         <imports directory>
"""

import sys, os

EDITS = {
 "command_interpreter.v": [
   ("output port",
    "   output reg [7:0]  route_cfg_addr,",
    "   output reg [9:0]  route_cfg_addr,"),
   ("reset value",
    "        route_cfg_addr  <= 8'd0;",
    "        route_cfg_addr  <= 10'd0;"),
   ("command payload",
    "            route_cfg_addr  <= rxFIFO_dout[13:6];",
    "            route_cfg_addr  <= rxFIFO_dout[15:6];"),
 ],
 "single_core.sv": [
   ("output port",
    "    output wire [7:0]  route_cfg_addr,",
    "    output wire [9:0]  route_cfg_addr,"),
 ],
 "core_wrapper.sv": [
   ("output port",
    "    output wire [7:0]  route_cfg_addr,",
    "    output wire [9:0]  route_cfg_addr,"),
 ],
 "sixteen_core_noc_firefly_top.sv": [
   ("per-core wire array",
    "    wire [7:0]  core_route_cfg_addr  [15:0];",
    "    wire [9:0]  core_route_cfg_addr  [15:0];"),
 ],
 "noc_integration.sv": [
   ("input array",
    "    input  wire [7:0]  core_route_cfg_addr  [NUM_CORES-1:0],",
    "    input  wire [9:0]  core_route_cfg_addr  [NUM_CORES-1:0],"),
   ("internal register",
    "    reg [7:0]  route_cfg_addr;",
    "    reg [9:0]  route_cfg_addr;"),
   ("default value",
    "        route_cfg_addr  = 8'd0;",
    "        route_cfg_addr  = 10'd0;"),
 ],
 "cores_with_noc.sv": [
   ("input port",
    "    input  logic [7:0]  route_cfg_addr,",
    "    input  logic [9:0]  route_cfg_addr,"),
 ],
}


def fail(m):
    sys.stderr.write("\nABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_route_cfg_width.py [--check] <imports directory>")
D = args[0]
if not os.path.isdir(D):
    fail("not a directory: %s" % D)

files = {}
for f in EDITS:
    p = os.path.join(D, f)
    if not os.path.isfile(p):
        fail("missing file: %s" % p)
    raw = open(p, errors="replace").read()
    files[f] = (p, raw, "\r\n" in raw, raw.replace("\r\n", "\n"))

total = sum(len(v) for v in EDITS.values())
print("Verifying %d edits across %d files.\n" % (total, len(EDITS)))
ok = done = bad = 0
for f in sorted(EDITS):
    s = files[f][3]
    for tag, old, new in EDITS[f]:
        n = s.count(old)
        if n == 1:
            ok += 1
            print("  ok    %-32s %s" % (f, tag))
        elif n == 0 and new in s:
            done += 1
            print("  done  %-32s %s (already applied)" % (f, tag))
        else:
            bad += 1
            print("  MISS  %-32s %s (matched %d)" % (f, tag, n))

print("\n%d verified, %d already applied, %d not found." % (ok, done, bad))
if bad:
    fail("%d anchors did not match exactly once." % bad)

if check:
    print("""
--check: nothing written.

After applying, elaborate and confirm that no width mismatch remains on
route_cfg_addr:

    grep "route_cfg_addr" <the elaboration log> | grep 8-689

The host must also widen the address field of the routing-table command, from
bits [13:6] to [15:6] of the 512-bit packet. Without that the hardware can
address 1,024 entries and the host can still only name 256.
""")
    sys.exit(0)

for f in files:
    p, raw, crlf, s = files[f]
    for tag, old, new in EDITS[f]:
        s = s.replace(old, new, 1)
    bak = p + ".before_routecfg"
    if not os.path.exists(bak):
        open(bak, "w").write(raw)
    open(p, "w").write(s.replace("\n", "\r\n") if crlf else s)
    print("  patched %s" % f)

print("\nAll 1,024 routing entries are now reachable from the host.")
print("The routing-table command field moves from [13:6] to [15:6].")
