#!/usr/bin/env python3
"""
Mark the microphase boundary signals for ILA capture.

The current bitstream has no debug core at all -- refresh_hw_device reports
"no supported debug core(s) in it".  So the boundary cannot be observed on
hardware without a rebuild, and if FIX T fails there is nothing to look at.

This adds (* mark_debug = "true" *) to the six signals that determine what
happens at a microphase transition:

    curr_state            which phase, and when PUSH begins
    microphase_ctr        which microphase
    uram_raddr            the Phase-1 read address
    uram_rden             when a read is issued
    uram_waddr[0]         the LATCHED write address -- the stale one
    uram_wren[0]          the REGISTERED write enable

Group 0 is enough: in Phase 1 all 16 groups share the same address and enable.

Ten cycles around the transition with these six signals settles the question
that eight blind attempts have not.

COST
Debug insertion adds an ILA core and routing.  The last build closed at
WNS +43 ps, so there should be room, but CHECK WNS BEFORE FLASHING.  If it
goes negative, revert with the backup and rebuild without instrumentation --
a marginal bitstream is worth less than a diagnosable one.

  python3 add_ila_debug.py --check <internal_events_processor.v>
  python3 add_ila_debug.py         <internal_events_processor.v>
  python3 add_ila_debug.py --remove <internal_events_processor.v>

After synthesis, in Vivado:
    set_property MARK_DEBUG true [get_nets ...]   # already set by attribute
    open_synthesized_design
    -> Set Up Debug wizard picks up the marked nets automatically

Capture with the ILA trigger on:
    curr_state == 7 (PUSH) && microphase_ctr != 0
and read the ten cycles either side.
"""

import sys, os, re

ATTR = '(* mark_debug = "true" *) '

TARGETS = [
    (r"^reg\s*\[3:0\]\s+curr_state\s*,\s*next_state\s*;", "curr_state"),
    (r"^reg\s*\[3:0\]\s+microphase_ctr\s*;",            "microphase_ctr"),
    (r"^reg\s*\[12:0\]\s+uram_raddr\s*;",               "uram_raddr"),
    (r"^reg\s+uram_rden\s*;",                           "uram_rden"),
    (r"^reg\s*\[12:0\]\s+uram_waddr\s*\[15:0\]\s*;",   "uram_waddr"),
    (r"^reg\s*\[15:0\]\s+uram_wren\s*;",                "uram_wren"),
]


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
remove = "--remove" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_ila_debug.py [--check|--remove] <internal_events_processor.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
lines = open(p).read().split("\n")

if remove:
    n = 0
    for i, l in enumerate(lines):
        if ATTR in l:
            lines[i] = l.replace(ATTR, ""); n += 1
    if not n:
        fail("no mark_debug attributes found in %s" % p)
    open(p, "w").write("\n".join(lines))
    print("removed %d mark_debug attributes from %s" % (n, p))
    sys.exit(0)

if any(ATTR in l for l in lines):
    fail("%s already has mark_debug attributes -- use --remove first." % p)

hits = []
for pat, name in TARGETS:
    rx = re.compile(pat)
    idx = [i for i, l in enumerate(lines) if rx.match(l.strip())]
    if len(idx) != 1:
        fail("declaration for %s matched %d times in %s (expected 1).\n"
             "       Send me the declaration line and I'll rebase." % (name, len(idx), p))
    hits.append((idx[0], name))

print("declarations found:")
for i, name in hits:
    print("  ok  %-16s line %d" % (name, i + 1))

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

for i, name in hits:
    lines[i] = ATTR + lines[i].lstrip()

bak = p + ".before_ila"
if not os.path.exists(bak):
    open(bak, "w").write("\n".join(open(p).read().split("\n")))
open(p, "w").write("\n".join(lines))
print("\nmarked %d signals in %s (backup %s)" % (len(hits), p, bak))
print("""
CHECK WNS AFTER SYNTHESIS, BEFORE FLASHING.  If timing does not close,
run with --remove and rebuild.
""")
