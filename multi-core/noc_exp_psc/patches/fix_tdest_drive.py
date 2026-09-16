#!/usr/bin/env python3
"""
Replace the split-driver tdest assignment in the patched top.

wire_firefly_top.py produced:

    remote_spike_injector ... ff_injector (
        ...
        .m_axis_tdest  (from_firefly.tdest[3:0]),
        ...
    );
    assign from_firefly.tdest[4] = 1'b0;

That drives ONE vector from TWO places: bits [3:0] come from a module output
port, bit [4] from a continuous assign.  Verilog permits it when the bit ranges
are disjoint, but it is the only construct of its kind in the file -- every
other interface in this top is driven wholly by a module port -- and its
legality depends on how AXIStream declares tdest, which is in a file outside
the archive and cannot be checked here.

If tdest is a plain unpacked `logic [DESTW-1:0]` the split works.  If it is
declared inside a modport with a direction, or if any tool in the chain treats
a partial interface-member assignment as a full drive, the result is a
multi-driver on tdest[3:0] -- and Vivado resolves multi-driver nets by keeping
one driver and DISCARDING the other, silently, which is exactly how the
phase2_halfsel and dbuf_delayed_ready defects behaved earlier in this project.

The replacement drives the whole vector once, from a plain wire:

    wire [3:0] ff_inject_core;
    ...
        .m_axis_tdest  (ff_inject_core),
    ...
    assign from_firefly.tdest = {1'b0, ff_inject_core};

One driver, one assignment, no dependence on how the interface declares its
members.  The upper bit is zero because remote spikes address cores 0 to 15
while the switch selects among 32 destinations.

  python3 fix_tdest_drive.py --check <top.sv>
  python3 fix_tdest_drive.py         <top.sv>
"""

import sys, os

A_PORT = "        .m_axis_tdest  (from_firefly.tdest[3:0]),"
N_PORT = "        .m_axis_tdest  (ff_inject_core),"

A_ASSIGN = "    assign from_firefly.tdest[4] = 1'b0;"
N_ASSIGN = """    // One driver for the whole vector.  Remote spikes address cores 0-15,
    // while the ingress switch selects among 32 destinations, so the upper
    // bit is zero.
    assign from_firefly.tdest = {1'b0, ff_inject_core};"""

A_DECL = "    AXIStream #(512, 5) from_firefly (.aclk(aclk), .aresetn(aresetn));"
N_DECL = """    AXIStream #(512, 5) from_firefly (.aclk(aclk), .aresetn(aresetn));
    wire [3:0] ff_inject_core;"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_tdest_drive.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "ff_inject_core" in s:
    fail("already patched")

for tag, a in (("decl", A_DECL), ("port", A_PORT), ("assign", A_ASSIGN)):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-7s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

if check:
    print("""
--check: nothing written.

This removes the last construct in the patched top whose correctness could not
be established from the sources available.  After this, every interface in the
file is driven wholly by a module port or by a single continuous assignment.
""")
    sys.exit(0)

out = s.replace(A_DECL, N_DECL, 1).replace(A_PORT, N_PORT, 1).replace(A_ASSIGN, N_ASSIGN, 1)
bak = p + ".before_tdest"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
