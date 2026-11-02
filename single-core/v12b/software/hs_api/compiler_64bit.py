#!/usr/bin/env python3
"""
64-bit synapse emit for fpga_compiler.py.

WHAT CHANGES
------------
32-bit entry {op[2:0], dest[12:0], weight[15:0]} -> 8 entries per 256-bit HBM
row.  self.synapses is a list of such rows, and a pointer is
    len  = p[1] - p[0]        (rows - 1, feeds AXI arlen directly)
    addr = p[0] + SYN_BASE_ADDR

64-bit entry {op[2:0], dest[12:0], weight[15:0], delay[5:0], syn_type[3:0],
stdp_tag[3:0], src[17:0]} -> only 4 fit per 256-bit row, so each logical row
becomes TWO HBM rows and every pointer offset doubles:

    new_start = 2*p[0]
    new_end   = 2*p[1] + 1
    new_len   = 2*(p[1] - p[0]) + 1

hbm_processor needs no change: ptr_burst is derived from ptr_len, which comes
straight from ptrFIFO_dout[31:23], so the burst follows the pointer.

Synapse tuples stay backward compatible.  A 3-tuple (op, dest, weight) emits
delay=0/src=0; a 5-tuple (op, dest, weight, delay, src) carries them through,
so connectome_utils can start emitting delay without breaking anything.

COST -- read this before enabling
---------------------------------
HBM footprint DOUBLES.  The large DVS model is ~7,003,192 rows ~ 214 MB
against a 256 MB per-channel limit; at 64-bit that is ~428 MB and WILL NOT
FIT.  Load time doubles.  Phase 2 does twice the HBM reads.  Only enable it
for networks that actually need per-synapse delay or STDP -- syn_64bit_en is
a per-core runtime bit, so other cores and other networks are unaffected.

  usage:
    python3 compiler_64bit.py --check <fpga_compiler.py>
    python3 compiler_64bit.py         <fpga_compiler.py>

  then:
    f.create_script('cfg', syn_64bit=True)
  and set syn_64bit_en=1 in CMD 13 for that core.

UNVERIFIED -- the group ordering
--------------------------------
The IEP reads 2 consecutive HBM rows as one 512-bit word and takes group 0
from the MSB end.  Which half of a row-pair carries groups 0-7 is set by the
upstream partitioner, not by this file, and I have not been able to verify it
against hardware.  Run verify_64bit_order.py FIRST: it writes a known
per-group pattern and reads I_ex back.  Groups in order means the convention
holds; a permutation tells you exactly what to swap.
"""

import sys, os, re

def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: compiler_64bit.py [--check] <fpga_compiler.py>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()
if "syn_64bit" in s:
    fail("%s already mentions syn_64bit -- already patched?" % p)

edits = []

# ---- signatures ----
for old, new, label in [
    ("    def create_axon_ptrs(self, simDump = False):",
     "    def create_axon_ptrs(self, simDump = False, syn_64bit = False):", "axon_ptrs sig"),
    ("    def create_neuron_ptrs(self, simDump = False):",
     "    def create_neuron_ptrs(self, simDump = False, syn_64bit = False):", "neuron_ptrs sig"),
    ("    def create_synapses(self, simDump = False):",
     "    def create_synapses(self, simDump = False, syn_64bit = False):", "synapses sig"),
    ("    def create_script(self, fname, simDump = False):",
     "    def create_script(self, fname, simDump = False, syn_64bit = False):", "script sig"),
]:
    if s.count(old) != 1:
        fail("%s not found exactly once in %s" % (label, p))
    edits.append((old, new, label))

# ---- pointer scaling ----
old = ("                binAddr = np.binary_repr(p[1] - p[0], PTR_LEN_BITS) + "
       "np.binary_repr(p[0] + SYN_BASE_ADDR,\n"
       "                                                                                    PTR_ADDR_BITS)")
if s.count(old) != 1:
    fail("axon pointer packing not found exactly once in %s" % p)
edits.append((old,
 "                # 64-bit entries halve the entries per HBM row, so each logical\n"
 "                # synapse row becomes two HBM rows and offsets double.\n"
 "                _s = (p[0] * 2) if syn_64bit else p[0]\n"
 "                _l = (2 * (p[1] - p[0]) + 1) if syn_64bit else (p[1] - p[0])\n"
 "                binAddr = np.binary_repr(_l, PTR_LEN_BITS) + "
 "np.binary_repr(_s + SYN_BASE_ADDR, PTR_ADDR_BITS)", "axon ptr scaling"))

old = ("                binCmd = np.binary_repr(p[1] - p[0], PTR_LEN_BITS) + "
       "np.binary_repr(p[0] + SYN_BASE_ADDR, PTR_ADDR_BITS)")
if s.count(old) != 1:
    fail("neuron pointer packing not found exactly once in %s" % p)
edits.append((old,
 "                _s = (p[0] * 2) if syn_64bit else p[0]\n"
 "                _l = (2 * (p[1] - p[0]) + 1) if syn_64bit else (p[1] - p[0])\n"
 "                binCmd = np.binary_repr(_l, PTR_LEN_BITS) + "
 "np.binary_repr(_s + SYN_BASE_ADDR, PTR_ADDR_BITS)", "neuron ptr scaling"))

# ---- 64-bit entry encoder + row split ----
old = "        weights = self.synapses\n"
if s.count(old) != 1:
    fail("create_synapses body start not found exactly once in %s" % p)
edits.append((old, old + """
        if syn_64bit:
            return self._create_synapses_64(simDump)
""", "dispatch to 64-bit"))

old = "    def create_script(self, fname, simDump = False, syn_64bit = False):"
edits.append((old, '''    def _syn64_entry(self, w):
        """One 64-bit synapse entry as a 64-character bit string.

        {op[2:0], dest[12:0], weight[15:0], delay[5:0], syn_type[3:0],
         stdp_tag[3:0], src[17:0]}   -- matches internal_events_processor.v

        Accepts (op, dest, weight) or (op, dest, weight, delay, src).
        """
        delay = int(w[3]) if len(w) > 3 else 0
        src   = int(w[4]) if len(w) > 4 else 0
        if not 0 <= delay <= 63:
            raise ValueError("synapse delay %d outside 0-63" % delay)
        return (np.binary_repr(0, SYN_OP_BITS)
                + np.binary_repr(int(w[1]), SYN_ADDR_BITS)
                + np.binary_repr(int(w[2]), SYN_WEIGHT_BITS)
                + np.binary_repr(delay, 6)
                + np.binary_repr(0, 4)          # syn_type, reserved
                + np.binary_repr(0, 4)          # stdp_tag, single global rule
                + np.binary_repr(src, 18))

    def _create_synapses_64(self, simDump = False):
        """64-bit emit.  Each logical row of 8 entries becomes TWO HBM rows of
        4 entries, written at SYN_BASE_ADDR + 2r and + 2r + 1, preserving
        entry order.  Pointer offsets are doubled to match."""
        dump = [] if simDump else None
        bigCmdList = []
        for r, d in enumerate(self.synapses):
            entries = [self._syn64_entry(w) for w in d if w[0] == 0]
            while len(entries) < 8:
                entries.append(np.binary_repr(0, 64))
            for half in (0, 1):
                cmd = []
                for b in entries[half * 4:(half + 1) * 4]:
                    cmd += [int(b[i:i + 8], 2) for i in range(0, 64, 8)]
                rowAddress = '1' + np.binary_repr(SYN_BASE_ADDR + 2 * r + half, 23)
                cmd = (self.HBM_OP_RW_LIST
                       + [int(rowAddress[:8], 2), int(rowAddress[8:16], 2),
                          int(rowAddress[16:], 2)] + cmd)
                cmd = np.flip(np.array(cmd, dtype=np.uint64))
                if simDump:
                    h = ['{:0{width}x}'.format(i, width=2) for i in cmd]
                    h.reverse()
                    dump.append(''.join(h))
                else:
                    bigCmdList.append(cmd)
        if simDump:
            return dump
        split = np.concatenate(bigCmdList)
        while split.size:
            element = split[:640]
            split = split[640:]
            dmadump.dma_dump_write(element, len(element), 1, 0, 0, 0,
                                   dmadump.DmaMethodNormal)

''' + old, "64-bit encoder"))

# ---- thread the flag through create_script ----
for old, new, label in [
    ("        axon_ptrs = self.create_axon_ptrs(simDump)",
     "        axon_ptrs = self.create_axon_ptrs(simDump, syn_64bit)", "script axon"),
    ("        neuron_ptrs = self.create_neuron_ptrs(simDump)",
     "        neuron_ptrs = self.create_neuron_ptrs(simDump, syn_64bit)", "script neuron"),
    ("        synapses = self.create_synapses(simDump)",
     "        synapses = self.create_synapses(simDump, syn_64bit)", "script synapses"),
]:
    if s.count(old) != 1:
        fail("%s not found exactly once in %s" % (label, p))
    edits.append((old, new, label))

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
bak = p + ".before_64bit"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("\nDefault is unchanged: syn_64bit=False emits exactly the 32-bit layout")
print("you have today.  Nothing changes until you pass syn_64bit=True.")
