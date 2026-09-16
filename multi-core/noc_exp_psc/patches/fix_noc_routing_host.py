#!/usr/bin/env python3
"""
Bring the host routing-table loader in line with the widened RTL.

FOUR DEFECTS
------------
1. Opcode 13. The RTL decodes CMD_ROUTE_TBL_W as 15; 13 is PSC parameters and
   14 is the axon delay table in the biological core. Every routing write has
   been arriving as a PSC parameter write.
2. No core selector. tdest is tdata[503:499] -- the top five bits of byte 62 --
   and _packet never writes that byte, so all sixteen tables go to core 0.
3. Address masked to eight bits. The RTL now reads rxFIFO_dout[15:6], ten bits.
4. ENTRIES 256. The table holds 1,024 entries, indexed by spike_addr[18:9].

  python3 fix_noc_routing_host.py --check <noc_routing.py>
  python3 fix_noc_routing_host.py         <noc_routing.py>
"""
import sys, os, shutil

args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    sys.exit("ABORT: usage: fix_noc_routing_host.py [--check] <noc_routing.py>")
p = args[0]
if not os.path.isfile(p):
    sys.exit("ABORT: no such file: %s" % p)
s = open(p).read()

EDITS = [
 ("opcode",
  "CMD_ROUTE_TBL_W = 13",
  "CMD_ROUTE_TBL_W = 15"),
 ("entry count",
  "ENTRIES = 256",
  "ENTRIES = 1024"),
 ("block comment",
  "BLOCK = 512                      # neurons per routing entry, from addr[16:9]",
  "BLOCK = 512                      # neurons per routing entry, from addr[18:9]"),
 ("packet body",
  "    val = ((core & 0xF) << 14) | ((addr & 0xFF) << 6) | \\\n"
  "          ((level & 0x3) << 4) | (mask & 0xF)\n"
  "    cmd[0] = val & 0xFF\n"
  "    cmd[1] = (val >> 8) & 0xFF\n"
  "    cmd[2] = (val >> 16) & 0xFF",
  "    # tdest = tdata[503:499]: five bits of core in the top of byte 62.\n"
  "    cmd[62] = (core & 0x1F) << 3\n"
  "    # The RTL reads [15:6] address, [5:0] data. No core field in the word.\n"
  "    val = ((addr & 0x3FF) << 6) | ((level & 0x3) << 4) | (mask & 0xF)\n"
  "    cmd[0] = val & 0xFF\n"
  "    cmd[1] = (val >> 8) & 0xFF"),
 ("docstring table size",
  "256 entries per core, indexed by spike_addr[16:9] -- so one entry governs a",
  "1024 entries per core, indexed by spike_addr[18:9] -- so one entry governs a"),
 ("docstring wire format",
  "WIRE FORMAT (CMD 13, one entry per packet)\n"
  "    [511:504] = 13\n"
  "    [ 17: 14] = core\n"
  "    [ 13:  6] = addr\n"
  "    [  5:  0] = {level, mask}",
  "WIRE FORMAT (CMD 15, one entry per packet)\n"
  "    [511:504] = 15\n"
  "    [503:499] = core (tdest)\n"
  "    [ 15:  6] = addr\n"
  "    [  5:  0] = {level, mask}"),
 ("docstring granularity",
  "Because the index is addr[16:9], routing is decided per 512-neuron block.  A",
  "Because the index is addr[18:9], routing is decided per 512-neuron block.  A"),
]

for name, old, new in EDITS:
    n = s.count(old)
    if n != 1:
        sys.exit("ABORT: %s -- anchor found %d times, expected 1.\nNothing written." % (name, n))
if check:
    print("all 7 anchors matched exactly once; --check only, nothing written")
    sys.exit(0)
for name, old, new in EDITS:
    s = s.replace(old, new)
shutil.copy(p, p + ".before_widen")
open(p, "w").write(s)
print("OK: patched, backup at %s.before_widen" % p)
