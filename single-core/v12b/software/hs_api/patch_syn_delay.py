#!/usr/bin/env python3
"""
Make per-synapse delay reachable through the API.

THE GAP
The connectome has no delay field, so synapse tuples are (op, dest, weight).
The only way to get a delay in was to patch the tuples AFTER the network was
built and call create_synapses() again -- and that re-emit does not reach HBM.
Reading the rows back through the axon pointer shows the original delay=0 data
still sitting there, which is why every delayed test this session produced a
byte-identical trace across three different bitstreams: the synapse data never
actually changed.

THE FIX
Let the delay be supplied when the network is COMPILED, so it is present the
first time the synapse rows are written -- the same path that already works
for delay=0 and that check_64bit.py proved correct.

    net = CRI_network(axons=..., connections=..., outputs=...,
                      target='CRI', syn_64bit=True, syn_delay=3)

Every synapse in the network then carries delay=3.  That is a network-wide
default rather than true per-synapse delay -- carrying a distinct delay per
synapse needs a field in connectome_utils, which is a larger change -- but it
is enough to exercise and verify the hardware delay path, which has never
actually been tested.

  python3 patch_syn_delay.py --check <fpga_compiler.py> <network.py> <api.py>
  python3 patch_syn_delay.py         <fpga_compiler.py> <network.py> <api.py>

Apply AFTER compiler_64bit.py, fix_64bit_roworder.py and thread_syn64bit.py.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 3:
    fail("usage: patch_syn_delay.py [--check] <fpga_compiler.py> <network.py> <api.py>")
fc_p, net_p, api_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

fc = open(fc_p).read()
net = open(net_p).read()
api = open(api_p).read()
for p, s in ((fc_p, fc), (net_p, net), (api_p, api)):
    if "syn_delay" in s:
        fail("%s already mentions syn_delay -- already patched?" % p)
if "_syn64_entry" not in fc:
    fail("%s has no _syn64_entry -- run compiler_64bit.py first." % fc_p)

edits = []

# ---------------- fpga_compiler: use the default when the tuple has none ----
o = "        delay = int(w[3]) if len(w) > 3 else 0\n"
if fc.count(o) != 1:
    fail("_syn64_entry delay line not found exactly once in %s" % fc_p)
edits.append((fc_p, o,
  "        # A 5-tuple carries its own delay; a 3-tuple falls back to the\n"
  "        # network-wide default, which is how delay is specified until the\n"
  "        # connectome grows a per-synapse field.\n"
  "        delay = int(w[3]) if len(w) > 3 else getattr(self, 'syn_delay', 0)\n",
  "compiler: default delay"))

o = "    def create_script(self, fname, simDump = False, syn_64bit = False):"
if fc.count(o) != 1:
    fail("create_script signature not found exactly once in %s -- run "
         "compiler_64bit.py first." % fc_p)
edits.append((fc_p, o,
  "    def create_script(self, fname, simDump = False, syn_64bit = False,\n"
  "                      syn_delay = 0):\n"
  "        # Recorded before any emit so _syn64_entry can see it.  Delay only\n"
  "        # has meaning in the 64-bit format; the 32-bit entry has no field\n"
  "        # for it, so a nonzero delay there is a caller error.\n"
  "        if syn_delay and not syn_64bit:\n"
  "            raise ValueError(\"syn_delay requires syn_64bit=True -- the \"\n"
  "                             \"32-bit synapse entry has no delay field\")\n"
  "        if not 0 <= syn_delay <= 63:\n"
  "            raise ValueError(\"syn_delay %d outside 0-63\" % syn_delay)\n"
  "        self.syn_delay = syn_delay",
  "compiler: create_script signature"))

# ---------------- network.py ----------------
o = ("    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0,\n"
     "                 syn_64bit = False):")
if net.count(o) != 1:
    fail("network.__init__ signature not found exactly once in %s -- run "
         "thread_syn64bit.py first." % net_p)
edits.append((net_p, o,
  "    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0,\n"
  "                 syn_64bit = False, syn_delay = 0):", "network: signature"))

o = "        self.syn_64bit = syn_64bit\n"
if net.count(o) != 1:
    fail("self.syn_64bit assignment not found exactly once in %s" % net_p)
edits.append((net_p, o,
  o + "        # Network-wide synapse delay in timesteps, applied at compile time\n"
      "        # so it is present the first time the rows are written.\n"
      "        self.syn_delay = syn_delay\n", "network: store"))

n = net.count("syn_64bit = self.syn_64bit")
if n != 2:
    fail("expected 2 'syn_64bit = self.syn_64bit' call sites in %s, found %d"
         % (net_p, n))
edits.append((net_p, "syn_64bit = self.syn_64bit",
              "syn_64bit = self.syn_64bit, syn_delay = self.syn_delay",
              "network: both create_script calls"))

# ---------------- api.py ----------------
o = ("            self, axons, connections, outputs, target=None, simDump=False, coreID=0,\n"
     "            syn_64bit=False\n    ):")
if api.count(o) != 1:
    fail("CRI_network.__init__ signature not found exactly once in %s -- run "
         "thread_syn64bit.py first." % api_p)
edits.append((api_p, o,
  "            self, axons, connections, outputs, target=None, simDump=False, coreID=0,\n"
  "            syn_64bit=False, syn_delay=0\n    ):", "api: signature"))

o = "                syn_64bit=syn_64bit,\n"
if api.count(o) != 1:
    fail("network(syn_64bit=...) call not found exactly once in %s" % api_p)
edits.append((api_p, o, o + "                syn_delay=syn_delay,\n", "api: pass through"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {fc_p: fc, net_p: net, api_p: api}
for path, old, new, label in edits:
    c = bufs[path].count(old)
    if label.endswith("both create_script calls"):
        if c != 2:
            fail("anchor for %s changed count mid-apply (%d)" % (label, c))
    elif c != 1:
        fail("anchor for %s stopped being unique mid-apply (%d)" % (label, c))
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_syndelay"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Usage:
    net = CRI_network(axons=..., connections=..., outputs=...,
                      target='CRI', syn_64bit=True, syn_delay=3)

and set syn_64bit_en=1 in CMD 13 for that core.  Verify with
test_delay_construct.py -- the drive should arrive N timesteps later than it
does with syn_delay=0.
""")
