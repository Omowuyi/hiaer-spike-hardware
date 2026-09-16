#!/usr/bin/env python3
"""
Raise the partitioner's per-core capacity to the widened neuron space.

THE DEFECT
----------
NEURONS_PER_CORE is 8192, the value before the address widening. The neuron
state memory holds 2,048 URAM rows of 16 groups, so a core holds 32,768.
max_blocks and cap both derive from this constant, so the partitioner allows
16 blocks per core where the hardware accepts 64, and rejects any network
above 131,072 neurons per device -- the range the widening exists to reach.

The comments naming addr[16:9] are also stale; the index is addr[18:9].

  python3 fix_partition_capacity.py --check <noc_partition.py>
  python3 fix_partition_capacity.py         <noc_partition.py>
"""
import sys, os, shutil

args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    sys.exit("ABORT: usage: fix_partition_capacity.py [--check] <noc_partition.py>")
p = args[0]
if not os.path.isfile(p):
    sys.exit("ABORT: no such file: %s" % p)
s = open(p).read()

EDITS = [
 ("capacity constant",
  "NEURONS_PER_CORE = 8192",
  "NEURONS_PER_CORE = 32768       # 2,048 URAM rows x 16 groups, after the 19-bit widening"),
 ("block constant comment",
  "BLOCK = 512                    # neurons per routing-table entry, addr[16:9]",
  "BLOCK = 512                    # neurons per routing-table entry, addr[18:9]"),
 ("granularity note",
  "3. Granularity.  The routing table is indexed by addr[16:9], so one entry",
  "3. Granularity.  The routing table is indexed by addr[18:9], so one entry"),
]

for name, old, new in EDITS:
    n = s.count(old)
    if n != 1:
        sys.exit("ABORT: %s -- anchor found %d times, expected 1.\nNothing written." % (name, n))
if check:
    print("all 3 anchors matched exactly once; --check only, nothing written")
    sys.exit(0)
for name, old, new in EDITS:
    s = s.replace(old, new)
shutil.copy(p, p + ".before_widen")
open(p, "w").write(s)
print("OK: patched, backup at %s.before_widen" % p)
