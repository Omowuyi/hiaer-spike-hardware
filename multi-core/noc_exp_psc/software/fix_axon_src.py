#!/usr/bin/env python3
"""
FIX AA -- axon-driven synapse rows carry a source index, for cross-core STDP.

THE PROBLEM
STDP needs the presynaptic neuron's eligibility trace.  That trace lives in the
SOURCE core's URAM, and a destination core cannot read another core's URAM --
so a synapse whose presynaptic neuron sits on a different core can never learn.
FIX Z gave neuron-driven rows a real src, but axon-driven rows keep src=0.

Carrying the trace in the NoC packet does not fix this.  LTP fires when the
POSTsynaptic neuron spikes, which is some later timestep than when the
presynaptic spike arrived, so a trace snapshotted at emission time is already
stale by the time it is needed.  It would produce wrong weight updates, and the
32-bit NoC packet has no spare bits anyway.

THE APPROACH
Reconstruct the trace locally instead.  An eligibility trace is an exponentially
decaying value incremented on each presynaptic spike, and the destination core
already receives every presynaptic spike -- that is how the synapse fires at
all.  So the core can maintain the trace itself.

Remote spikes arrive through noc_relay into the EEP as AXON events.  So the
change is: give axon events eligibility traces the same way neurons have them,
and let the synapse name which axon it came from.

This patch is the compiler half -- the src field.  The RTL half is the axon
trace storage plus the stdp_controller lookup.

WHY IT SCALES UNCHANGED
A remote spike is an axon event whether it came from the next core, another
FPGA over Aurora, or another server.  Nothing here is distance-specific, and
the NoC packet, routers and buses are untouched -- so everything verified stays
verified.

Transport delay offsets the reconstructed trace from the source's own copy:
sub-microsecond on-chip, up to ~900 ns across three Aurora hops, against a
timestep of tens of microseconds.  Well under one timestep, so the two agree.

  python3 fix_axon_src.py --check <fpga_compiler.py>
  python3 fix_axon_src.py         <fpga_compiler.py>

Apply after fix_syn64_src.py.  Compiler only -- no rebuild.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_axon_src.py [--check] <fpga_compiler.py>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX AA" in s:
    fail("%s already patched." % p)
if "_row_owner" not in s:
    fail("%s has no _row_owner map -- run fix_syn64_src.py first." % p)

edits = []

o = """        _row_owner = {}
        try:
            _rl = len(self.neuron_ptrs[0])"""
if s.count(o) != 1:
    fail("_row_owner map not found exactly once in %s" % p)
edits.append((o,
  """        # FIX AA: rows reached from an AXON pointer get the axon index as
        # their source, so stdp_controller can look up that axon's eligibility
        # trace.  Previously they were left at 0, which made every axon-driven
        # synapse -- including every spike arriving over the NoC from another
        # core, FPGA or server -- read neuron 0's trace and learn nothing
        # meaningful.
        #
        # The encoding: bit 17 set marks an AXON source, bits [16:0] the axon
        # index.  Neuron sources keep bit 17 clear, so the RTL can tell them
        # apart without a separate field.  src is 18 bits, so both fit.
        _axon_owner = {}
        try:
            _al = len(self.axon_ptrs[0])
            for _ri, _row in enumerate(self.axon_ptrs):
                for _ci, _p in enumerate(_row):
                    _start, _end = int(_p[0]), int(_p[1])
                    if _end >= _start:
                        _a = _ri * _al + _ci
                        for _sr in range(_start, _end + 1):
                            _axon_owner[_sr] = (1 << 17) | (_a & 0x1FFFF)
        except Exception:
            _axon_owner = {}

        _row_owner = {}
        try:
            _rl = len(self.neuron_ptrs[0])""", "axon owner map"))

o = "            entries = [self._syn64_entry(w, _row_owner.get(r, 0)) for w in d]\n"
if s.count(o) != 1:
    fail("_create_synapses_64 entry list not found exactly once in %s -- run "
         "fix_syn64_src.py first." % p)
edits.append((o,
  "            # A row is reached from a neuron pointer or an axon pointer, not\n"
  "            # both.  Neuron ownership wins if a row somehow appears in both,\n"
  "            # since an intra-core presynaptic neuron has a real trace while\n"
  "            # the axon index is only a stand-in for a remote one.\n"
  "            _src = _row_owner.get(r, _axon_owner.get(r, 0))\n"
  "            entries = [self._syn64_entry(w, _src) for w in d]\n",
  "use the axon owner"))

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

bak = p + ".before_axonsrc"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
src encoding now:
    bit 17 = 0  -> neuron source, bits [16:0] = neuron index
    bit 17 = 1  -> axon   source, bits [16:0] = axon index

The RTL half still has to be added: axon eligibility traces, and the
stdp_controller lookup that reads them when bit 17 is set.
""")
