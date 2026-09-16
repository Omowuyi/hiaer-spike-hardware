#!/usr/bin/env python3
"""
FIX W -- the 64-bit synapse emit drops spike entries.

THE BUG
The proven 32-bit path in create_synapses() handles TWO opcodes:

    if w[0] == 0:      normal synapse   {op=0, dest=w[1], weight=w[2]}
    elif w[0] == 1:    SPIKE ENTRY      {op=4, 12 zeros, addr=w[1][16:0]}

The spike entry is what makes a neuron report a spike: op=4 is binary 100, so
the top bit of the opcode field is the spike flag the hardware looks for.

_create_synapses_64 does:

    entries = [self._syn64_entry(w) for w in d if w[0] == 0]

which DISCARDS every spike entry and slides the remaining synapses into their
positions.  A neuron whose spike entry is dropped can never report a spike in
64-bit mode, and every entry after the dropped one lands at the wrong index.

THE FIX
Encode the spike entry in the 64-bit layout the same way the 32-bit path does
-- op=4 with the address in the low 17 bits -- and keep every entry in its
original position instead of filtering.

    64-bit spike entry:  op[63:61]=4, bits[60:17]=0, addr[16:0]
    64-bit synapse:      op[63:61]=0, dest[60:48], weight[47:32],
                         delay[31:26], syn_type[25:22], stdp_tag[21:18],
                         src[17:0]

Entry 0's address field sits at bits [16:0] in BOTH formats, which is why the
32-bit spike readout happens to line up for entry 0 and not for the rest.

NOTE
This is necessary but not sufficient.  hbm_processor reads spike flags at
32-bit spacing (hbm_rdata[31], [63], [95] ...), so in 64-bit mode it looks at
the wrong bits for entries 1-3.  That needs the companion RTL change; see
fix_spike_detect_64bit.py.

  python3 fix_syn64_spike_entries.py --check <fpga_compiler.py>
  python3 fix_syn64_spike_entries.py         <fpga_compiler.py>
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_syn64_spike_entries.py [--check] <fpga_compiler.py>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX W" in s:
    fail("%s already patched." % p)
if "_create_synapses_64" not in s:
    fail("%s has no _create_synapses_64 -- run compiler_64bit.py first." % p)

edits = []

# ---- teach _syn64_entry the spike-entry opcode ----
o = "        delay = int(w[3]) if len(w) > 3 else getattr(self, 'syn_delay', 0)\n"
if s.count(o) != 1:
    fail("_syn64_entry delay line not found exactly once in %s -- run "
         "patch_syn_delay.py first." % p)
edits.append((o,
  "        # FIX W: a spike entry is op=4 with the address in the low 17 bits,\n"
  "        # exactly as the 32-bit path encodes it.  Dropping these was making\n"
  "        # affected neurons unable to report spikes at all in 64-bit mode.\n"
  "        if w[0] == 1:\n"
  "            return (np.binary_repr(4, SYN_OP_BITS)\n"
  "                    + 44 * '0'\n"
  "                    + np.binary_repr(int(w[1]) & 0x1FFFF, 17))\n"
  "        if w[0] != 0:\n"
  "            raise ValueError(\"unhandled synapse opcode %r\" % (w[0],))\n"
  + o, "spike-entry encoding"))

# ---- stop filtering; keep every entry in place ----
o = "            entries = [self._syn64_entry(w) for w in d if w[0] == 0]\n"
if s.count(o) != 1:
    fail("_create_synapses_64 entry list not found exactly once in %s" % p)
edits.append((o,
  "            # FIX W: was `if w[0] == 0`, which dropped spike entries and slid\n"
  "            # everything after them into the wrong slot.  Encode every entry\n"
  "            # and keep its position.\n"
  "            entries = [self._syn64_entry(w) for w in d]\n",
  "keep all entries"))

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

bak = p + ".before_fixw"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
Spike entries now survive the 64-bit emit.  The companion RTL change is still
required for entries 1-3 -- see fix_spike_detect_64bit.py.
""")
