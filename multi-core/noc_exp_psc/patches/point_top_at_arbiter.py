#!/usr/bin/env python3
"""
Point sixteen_core_top_firefly at axis_arbiter_2.

WHY
noc_input_arbiter.sv gave PCIe STRICT priority over FireFly: remote spikes were
served only when PCIe was idle.  Under sustained host traffic -- loading a large
network, or continuous exec_step -- they can be starved indefinitely.  Because
spikes carry a timestep tag, a starved remote spike does not merely arrive late,
it arrives in the WRONG TIMESTEP and is silently misapplied.

axis_arbiter_2 (in axis_switches.sv) keeps commands immediate -- a PCIe COMMAND
always wins -- but shares the link round-robin between PCIe spikes and FireFly
spikes, since both are spike traffic with the same deadline.  A burst of
commands does not consume FireFly's turn.  Verified: 7/7, and 10/10 on a
20-cycle contested split.

The port names are identical, so this is a module-name change only.  Keeping
both modules in the project would leave two definitions for one job.

  python3 point_top_at_arbiter.py --check <sixteen_core_top_firefly.sv>
  python3 point_top_at_arbiter.py         <sixteen_core_top_firefly.sv>
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: point_top_at_arbiter.py [--check] <sixteen_core_top_firefly.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "axis_arbiter_2" in s:
    fail("%s already points at axis_arbiter_2." % p)

o = "    noc_input_arbiter input_arbiter_i ("
if s.count(o) != 1:
    fail("noc_input_arbiter instantiation not found exactly once in %s (%d)"
         % (p, s.count(o)))

new = ("    // axis_arbiter_2 replaces noc_input_arbiter: same ports, but PCIe\n"
       "    // no longer has strict priority, so remote spikes cannot be starved\n"
       "    // into the wrong timestep.  Commands still win immediately.\n"
       "    axis_arbiter_2 #(\n"
       "        .DW(512), .DESTW(4), .BIAS_GRANTS(1)\n"
       "    ) input_arbiter_i (")

print("edit site verified:")
print("  ok  noc_input_arbiter -> axis_arbiter_2")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_arb"
if not os.path.exists(bak):
    open(bak, "w").write(s)
open(p, "w").write(s.replace(o, new))
print("patched %s (backup %s)" % (p, bak))
print("""
Do NOT add noc_input_arbiter.sv to the project -- axis_switches.sv supplies the
replacement, and two definitions for one job invites the wrong one being used.
""")
