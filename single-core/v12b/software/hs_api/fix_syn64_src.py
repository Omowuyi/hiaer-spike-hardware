#!/usr/bin/env python3
"""
FIX Z -- the 64-bit synapse entry never carries a source address, so STDP
cannot work.

THE BUG
_syn64_entry reads the source from the synapse tuple:

    src = int(w[4]) if len(w) > 4 else 0

but no tuple the compiler builds has five elements.  They are:

    (0, dest, weight)   a synapse
    (0, 0, 0)           padding
    (1, neuronIdx)      a spike entry

so src is ALWAYS 0 in every entry ever emitted.

stdp_controller reads the presynaptic neuron from that field:

    wire [17:0] e_src     = current_entry[17:0];
    wire [3:0]  src_group = e_src[3:0];
    wire [11:0] src_row_b = e_src[16:5] + 12'd2048;

With src=0 it looks up neuron 0's eligibility trace for every synapse in the
network and updates every weight from it.  STDP is structurally unable to work
-- no RTL change can fix that, because the information is absent from the data.

THE FIX
The source is known at compile time.  self.neuron_ptrs maps each neuron to the
range of synapse rows it owns, so every row's owning neuron is derivable.  Build
that map once and pass the owner as src for entries in that row.

Rows reached from AXON pointers have no presynaptic neuron -- the input comes
from outside the core -- so they keep src=0, which is correct: STDP has nothing
to correlate against for an external input.

  python3 fix_syn64_src.py --check <fpga_compiler.py>
  python3 fix_syn64_src.py         <fpga_compiler.py>

Apply after compiler_64bit.py, patch_syn_delay.py, fix_syn64_spike_entries.py
and fix_syn_delay_padding.py.  Compiler only -- no rebuild.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_syn64_src.py [--check] <fpga_compiler.py>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX Z" in s:
    fail("%s already patched." % p)
if "_syn64_entry" not in s:
    fail("%s has no _syn64_entry -- run compiler_64bit.py first." % p)

edits = []

# 1. _syn64_entry takes an explicit source
o = "    def _syn64_entry(self, w):"
if s.count(o) != 1:
    fail("_syn64_entry signature not found exactly once in %s" % p)
edits.append((o, "    def _syn64_entry(self, w, src_neuron=0):",
              "_syn64_entry signature"))

o = "        src   = int(w[4]) if len(w) > 4 else 0\n"
if s.count(o) != 1:
    fail("_syn64_entry src line not found exactly once in %s" % p)
edits.append((o,
  "        # FIX Z: a 5-tuple carries its own source, but none of the tuples\n"
  "        # the compiler builds does, so this was always 0 and STDP had no\n"
  "        # presynaptic neuron to correlate against.  Fall back to the neuron\n"
  "        # that owns this synapse row.\n"
  "        src   = int(w[4]) if len(w) > 4 else int(src_neuron)\n",
  "_syn64_entry source fallback"))

# 2. build the row -> owning neuron map and use it
o = "            entries = [self._syn64_entry(w) for w in d]\n"
if s.count(o) != 1:
    fail("_create_synapses_64 entry list not found exactly once in %s -- run "
         "fix_syn64_spike_entries.py first." % p)
edits.append((o,
  "            entries = [self._syn64_entry(w, _row_owner.get(r, 0)) for w in d]\n",
  "pass the row owner"))

o = "        bigCmdList = []\n        for r, d in enumerate(self.synapses):"
if s.count(o) != 1:
    fail("_create_synapses_64 main loop not found exactly once in %s" % p)
edits.append((o,
  "        bigCmdList = []\n"
  "\n"
  "        # FIX Z: map each synapse row to the neuron that owns it, so entries\n"
  "        # can carry a real presynaptic address.  neuron_ptrs[row][col] gives\n"
  "        # the (start, end) synapse-row range for neuron row*rowLength+col.\n"
  "        # Rows reached only from AXON pointers stay 0 -- an external input\n"
  "        # has no presynaptic neuron, and STDP has nothing to correlate there.\n"
  "        _row_owner = {}\n"
  "        try:\n"
  "            _rl = len(self.neuron_ptrs[0])\n"
  "            for _ri, _row in enumerate(self.neuron_ptrs):\n"
  "                for _ci, _p in enumerate(_row):\n"
  "                    _start, _end = int(_p[0]), int(_p[1])\n"
  "                    if _end >= _start:\n"
  "                        _n = _ri * _rl + _ci\n"
  "                        for _sr in range(_start, _end + 1):\n"
  "                            _row_owner[_sr] = _n\n"
  "        except Exception:\n"
  "            _row_owner = {}\n"
  "\n"
  "        for r, d in enumerate(self.synapses):", "row owner map"))

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

bak = p + ".before_fixz"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
STDP now has a presynaptic address to work with.  Note this is necessary, not
sufficient: stdp_controller's neuron-pointer entry position within its 256-bit
row is still an assumption, and no STDP test has ever run on hardware.
""")
