#!/usr/bin/env python3
"""
FIX Y -- syn_delay was being applied to padding entries.

THE BUG
Synapse rows are padded with (0, 0, 0) entries, and the compiler later
overwrites some of them with spike entries:

    if r[i] == (0, 0, 0) and n <= len(outputs):
        r[i] = (1, neuronIdx)

_syn64_entry falls back to the network-wide syn_delay for any entry that does
not carry its own:

    delay = int(w[3]) if len(w) > 3 else getattr(self, 'syn_delay', 0)

So with syn_delay=N, EVERY (0, 0, 0) padding slot is emitted as a synapse with
weight 0 and delay N.  The IEP treats any entry with delay != 0 as delayed and
pushes it into the delay buffer, so a single row of padding injects up to eight
bogus zero-weight delayed entries -- and a real network has hundreds of rows.
The delay buffer fills with rubbish that drains over subsequent timesteps,
which is exactly the "a drive arrives every timestep" signature that was
blamed on the delay buffer itself.

THE FIX
Apply the default delay only to entries that actually carry a weight.  A
padding entry stays delay 0 and is never pushed.

    delay = int(w[3]) if len(w) > 3 else (
                getattr(self, 'syn_delay', 0) if int(w[2]) != 0 else 0)

  python3 fix_syn_delay_padding.py --check <fpga_compiler.py>
  python3 fix_syn_delay_padding.py         <fpga_compiler.py>

Apply after patch_syn_delay.py and fix_syn64_spike_entries.py.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_syn_delay_padding.py [--check] <fpga_compiler.py>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX Y" in s:
    fail("%s already patched." % p)

old = "        delay = int(w[3]) if len(w) > 3 else getattr(self, 'syn_delay', 0)\n"
if s.count(old) != 1:
    fail("_syn64_entry delay line not found exactly once in %s -- run "
         "patch_syn_delay.py first." % p)

new = ("        # FIX Y: rows are padded with (0, 0, 0) entries.  Applying the\n"
       "        # network-wide delay to those turned every padding slot into a\n"
       "        # zero-weight DELAYED synapse, and the IEP pushes anything with\n"
       "        # delay != 0 into the delay buffer -- up to eight bogus entries\n"
       "        # per row, across hundreds of rows.  Only real synapses get it.\n"
       "        delay = int(w[3]) if len(w) > 3 else (\n"
       "            getattr(self, 'syn_delay', 0) if int(w[2]) != 0 else 0)\n")

print("edit site verified:")
print("  ok  _syn64_entry: default delay only for weighted entries")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_fixy"
if not os.path.exists(bak):
    open(bak, "w").write(s)
open(p, "w").write(s.replace(old, new))
print("patched %s (backup %s)" % (p, bak))
print("""
Verify offline before any hardware run:

    python3 -c "
    import sys; sys.path.insert(0,'/home/omowuyi/testing/hs_bridge')
    import hs_bridge.FPGA_Execution.fpga_compiler as fc
    class T: pass
    t = T(); t.syn_delay = 3
    f = fc.fpga_compiler._syn64_entry
    print('padding (0,0,0) delay =', int(f(t,(0,0,0))[32:38],2))
    print('real    (0,5,1000) delay =', int(f(t,(0,5,1000))[32:38],2))
    "

Expect 0 for the padding entry and 3 for the real one.
""")
