#!/usr/bin/env python3
"""
Add the depression arm to stdp_controller.v.

WHAT IS MISSING
---------------
A_minus is declared as an input at line 10 and never appears in the compute
path.  The rule as built is

    e_weight + delta_w        with  delta_w = (A_plus * src_trace) >> 4

which is potentiation only.  Every weight of an active population reaches
w_max, and the distinction the rule was meant to learn is destroyed -- measured
as 100 of 100 synapses at the ceiling with no separation between correlated and
uncorrelated input.

WHY THIS FORM, AND NOT TRUE LTD
-------------------------------
The textbook depression arm is post-before-pre: triggered when a presynaptic
spike arrives at a recently-fired postsynaptic neuron.  That is the opposite
traversal to Phase 4, which is triggered BY a postsynaptic spike and walks that
neuron's synapses.  Implementing it properly means folding weight update into
Phase 2, which already walks a firing axon's synapses -- but Phase 2 currently
only READS, and adding write-back there roughly doubles synaptic traffic in the
bandwidth-dominant phase.

Heterosynaptic depression avoids that entirely.  Every synapse of a firing
postsynaptic neuron is decremented by a constant, and those with recent
presynaptic activity are potentiated by more than the decrement.  The result is
competition: synapses that predict the postsynaptic spike win, the rest decay.

It costs one subtractor.  Phase 4 already performs a read-modify-write of the
weight, already clamps against BOTH w_max and w_min, and A_minus is already a
port -- so no new traversal, no new memory traffic, no new configuration
command.

MEASURED EFFECT
---------------
On a task where two input groups have matched mean rates and differ only in
spike timing, separation between the groups in units of their spread:

    A_minus =  0      no separation, 100 of 100 synapses saturated
    A_minus =  2      7.9
    A_minus =  4     54.9
    A_minus =  8    140.4
    A_minus = 16     52.2

against 10.3 for host-side weight renormalisation, which also only acts between
runs rather than continuously.  A_minus around 8 is the operating point; too
large and the correlated group is depressed faster than it potentiates.

  python3 add_stdp_depression.py --check <stdp_controller.v>
  python3 add_stdp_depression.py         <stdp_controller.v>
"""

import sys, os

OLD = "    wire signed [15:0] delta_w = $signed({1'b0, delta_w_raw[14:0]});"
NEW = """    //=========================================================================
    // Heterosynaptic depression.  Every synapse of a firing postsynaptic
    // neuron is decremented by A_minus; those with a recent presynaptic spike
    // are potentiated by more than that, so they win and the rest decay.
    //
    // Costs one subtractor: Phase 4 already reads, modifies and writes the
    // weight, and already clamps against both w_max and w_min, so the negative
    // case needs no new logic.  A_minus was already a port and previously
    // unused.
    //
    // Without this the rule is potentiation-only and every weight reaches
    // w_max, which destroys the distinction it exists to learn.
    //=========================================================================
    wire signed [15:0] delta_w = $signed({1'b0, delta_w_raw[14:0]})
                               - $signed({8'd0, A_minus});"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_stdp_depression.py [--check] <stdp_controller.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "A_minus})" in s:
    fail("already patched")

n = s.count(OLD)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  delta_w declaration found (line %d)" % (s[:s.index(OLD)].count("\n") + 1))

if "input  wire [7:0]  A_minus," not in s:
    fail("A_minus is not a port on this module")
print("  ok  A_minus is already a port")

# both clamps must exist, or a negative delta has nowhere to land
for tag, a in (("w_max clamp", "> w_max"), ("w_min clamp", "< w_min")):
    if a not in s:
        fail("%s not found -- a negative delta would underflow" % tag)
print("  ok  both clamps present, so a negative delta is already handled")

if check:
    print("""
--check: nothing written.

AFTER APPLYING:

  1. Re-run tb_stdp.sv.  Its clamp case sets w_max just above the starting
     weight and expects the weight to stop there; with A_minus at its default
     of zero every existing case behaves exactly as before, so the suite should
     still pass 15 of 15.  That is the regression check.

  2. Add a case that sets A_minus non-zero and checks the weight DECREASES for
     a synapse whose presynaptic trace is zero.  Without it the new arm has no
     coverage, and an untested arm is how the trace truncation survived.

  3. A_minus is written by the same CMD 13 that already carries A_plus, so no
     host change is needed beyond setting the field.

DEFAULT BEHAVIOUR IS UNCHANGED: at A_minus = 0 this reduces exactly to the
current expression.
""")
    sys.exit(0)

bak = p + ".before_depression"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
out = s.replace(OLD, NEW, 1)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("A_minus = 0 reproduces the current behaviour exactly.")
