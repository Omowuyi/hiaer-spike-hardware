#!/usr/bin/env python3
"""
Correct the neuron-count parameters in hiaer_firefly_pkg.sv.

    parameter int NEURONS_PER_CORE = 131072;   // ~128K

131,072 is the per-FPGA total, not the per-core one -- the comment "~128K"
gives it away, and 16 cores x 8,192 = 131,072 exactly.  The implemented design
is 8,192 neurons per core, which is not a choice but a consequence of the
synapse format: the 64-bit entry allocates dest_addr[60:48], thirteen bits, to
the postsynaptic neuron within a core.  A synapse cannot name a neuron beyond
2^13 however much memory sits behind it.

The parameter is UNUSED -- it appears nowhere but its own declaration -- so
nothing derives a wrong size from it and this is a correctness-of-record fix
rather than a functional one.  It still matters: a constant that states the
wrong figure will eventually be believed by whoever reads it next.

The URAM can physically hold more than 8,192 per core, so the headroom is real
and worth recording alongside the addressable limit rather than conflating the
two.

  python3 fix_pkg_neuron_counts.py --check <hiaer_firefly_pkg.sv>
  python3 fix_pkg_neuron_counts.py         <hiaer_firefly_pkg.sv>
"""

import sys, os

A = "    parameter int NEURONS_PER_CORE      = 131072;   // ~128K"
N = """    // 8,192 per core is set by the synapse format: the 64-bit entry gives
    // dest_addr[60:48], thirteen bits, to the postsynaptic neuron within a
    // core.  The URAM can hold more, but no synapse can address it.
    parameter int NEURONS_PER_CORE      = 8192;
    // 16 x 8,192 = 2^17 exactly, which is why the spike address is seventeen
    // bits and the routing table indexes it as addr[16:9].
    parameter int NEURONS_PER_FPGA      = 131072;"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_pkg_neuron_counts.py [--check] <hiaer_firefly_pkg.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "NEURONS_PER_FPGA" in s:
    fail("already patched")

n = s.count(A)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  anchor verified (line %d)" % (s[:s.index(A)].count("\n") + 1))

# confirm it really is unused, so the change cannot alter behaviour
uses = s.count("NEURONS_PER_CORE") - 1
print("  ok  NEURONS_PER_CORE referenced %d time(s) beyond its declaration" % uses)
if uses:
    print("  !!  it IS used -- review each site before applying, because the")
    print("      value changes by a factor of sixteen")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_counts"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
out = s.replace(A, N, 1)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
