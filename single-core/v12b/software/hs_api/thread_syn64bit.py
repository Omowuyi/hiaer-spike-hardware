#!/usr/bin/env python3
"""
Thread syn_64bit from CRI_network down to fpga_compiler.

compiler_64bit.py added `syn_64bit=True` to fpga_compiler.create_script(), but
CRI_network calls the compiler through hs_bridge.network, so the flag has no
way to reach it.  This wires the two intermediate layers:

    CRI_network(..., syn_64bit=True)
        -> network(..., syn_64bit=syn_64bit)
            -> self.compiledNetwork.create_script("test_config", syn_64bit=...)

Default stays False everywhere, so nothing changes until a caller opts in.

  python3 thread_syn64bit.py --check <api.py> <network.py>
  python3 thread_syn64bit.py         <api.py> <network.py>

Run compiler_64bit.py on fpga_compiler.py first -- this only moves the flag,
it does not add the 64-bit emit itself.

REMEMBER: 64-bit doubles the HBM synapse footprint.  Check headroom with
check_64bit.py before enabling it on any large network.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 2:
    fail("usage: thread_syn64bit.py [--check] <api.py> <network.py>")
api_p, net_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

api = open(api_p).read()
net = open(net_p).read()
for p, s in ((api_p, api), (net_p, net)):
    if "syn_64bit" in s:
        fail("%s already mentions syn_64bit -- already patched?" % p)

edits = []

# ---------------- api.py ----------------
o = ("            self, axons, connections, outputs, target=None, simDump=False, coreID=0\n"
     "    ):")
if api.count(o) != 1:
    fail("CRI_network.__init__ signature not found exactly once in %s" % api_p)
edits.append((api_p, o,
  "            self, axons, connections, outputs, target=None, simDump=False, coreID=0,\n"
  "            syn_64bit=False\n"
  "    ):", "CRI_network signature"))

o = ("            self.CRI = network(\n"
     "                self.connectome,\n"
     "                formatedOutputs,\n"
     "                simDump=simDump,\n"
     "                coreOveride=coreID,\n"
     "            )")
if api.count(o) != 1:
    fail("network(...) instantiation not found exactly once in %s" % api_p)
edits.append((api_p, o,
  "            self.CRI = network(\n"
  "                self.connectome,\n"
  "                formatedOutputs,\n"
  "                simDump=simDump,\n"
  "                coreOveride=coreID,\n"
  "                syn_64bit=syn_64bit,\n"
  "            )", "network() call"))

# ---------------- network.py ----------------
o = "    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0):"
if net.count(o) != 1:
    fail("network.__init__ signature not found exactly once in %s" % net_p)
edits.append((net_p, o,
  "    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0,\n"
  "                 syn_64bit = False):", "network signature"))

o = "        self.coreOveride = coreOveride #TODO:this is for debugging\n"
if net.count(o) != 1:
    fail("coreOveride assignment not found exactly once in %s" % net_p)
edits.append((net_p, o,
  o + "        # 64-bit Phase-2 synapse entries: doubles HBM footprint, needed for\n"
      "        # per-synapse delay and STDP.  Must match syn_64bit_en in CMD 13.\n"
      "        self.syn_64bit = syn_64bit\n", "store syn_64bit"))

o = ('            axon_ptrs, neuron_ptrs, synapses = '
     'self.compiledNetwork.create_script("test_config", simDump = True)')
if net.count(o) != 1:
    fail("simDump create_script call not found exactly once in %s" % net_p)
edits.append((net_p, o,
  '            axon_ptrs, neuron_ptrs, synapses = '
  'self.compiledNetwork.create_script("test_config", simDump = True, '
  'syn_64bit = self.syn_64bit)', "create_script simDump"))

o = '            self.compiledNetwork.create_script("test_config")\n'
if net.count(o) != 1:
    fail("hardware create_script call not found exactly once in %s" % net_p)
edits.append((net_p, o,
  '            self.compiledNetwork.create_script("test_config", '
  'syn_64bit = self.syn_64bit)\n', "create_script hardware"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {api_p: api, net_p: net}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_syn64bit"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Usage after this:

    net = CRI_network(axons=..., connections=..., outputs=...,
                      target='CRI', syn_64bit=True)

and set syn_64bit_en=1 in the CMD 13 packet for that core.  The two MUST
match -- 32-bit data read as 64-bit gives plausible-looking garbage weights,
not an error.
""")
