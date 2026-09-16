#!/usr/bin/env python3
"""
FIX AD -- threshold readback is truncated from 36 bits to 16.

THE BUG
core_wrapper declares

    output [35:0] threshold;          // core_wrapper.sv:24

but the top declares

    wire [15:0] threshold[0:31];      // inherited from test_top

so every core's threshold is silently truncated to its low 16 bits.  Synthesis
reports it as a warning, once per core:

    [Synth 8-689] width (16) of port connection 'threshold' does not match
                  port width (36) of module 'core_wrapper'

A warning, not an error -- so the design would build and the readback would
simply be wrong.  That is the more dangerous kind of defect: it looks like it
works.

WHY 36 BITS
The biological neuron model widened the threshold field.  test_top predates
that, and the array was never widened to match.  The VIO probe at line 273 reads
threshold[0], so this also affects debug visibility.

  python3 fix_threshold_width.py --check <sixteen_core_noc_firefly_top.sv>
  python3 fix_threshold_width.py         <sixteen_core_noc_firefly_top.sv>
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


def active_positions(text, needle):
    """Offsets of needle outside /* */ blocks.

    Everything derived from test_top keeps superseded configurations commented
    out, so a plain find lands in dead code.
    """
    hits, incmt, i, n = [], False, 0, len(text)
    while i < n:
        if not incmt and text.startswith("/*", i):
            incmt = True; i += 2; continue
        if incmt:
            if text.startswith("*/", i): incmt = False; i += 2
            else: i += 1
            continue
        if text.startswith(needle, i):
            hits.append(i)
        i += 1
    return hits


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_threshold_width.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p, errors="replace").read()

old_decl = "wire [15:0] threshold[0:31];"
new_decl = ("wire [35:0] threshold[0:31];   // FIX AD: core_wrapper drives 36 bits;\n"
            "                                  // 16 silently truncated the readback")

hits = active_positions(s, old_decl)
if not hits:
    if "wire [35:0] threshold[0:31];" in s:
        fail("%s already patched." % p)
    fail("threshold declaration not found in active code")
if len(hits) > 1:
    fail("threshold declaration found %d times in active code" % len(hits))

print("edit site verified:")
print("  ok  threshold [15:0] -> [35:0]  (line %d)"
      % (s[:hits[0]].count("\n") + 1))

# the dummy branch used a 16-bit literal; it is gone, but check anyway
lit = active_positions(s, ".threshold(16'b0)")
if lit:
    print("  note: %d active .threshold(16'b0) literal(s) remain -- these are"
          % len(lit))
    print("        tie-offs and would also truncate; widening them too")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

i = hits[0]
s = s[:i] + new_decl + s[i + len(old_decl):]

for off in sorted(active_positions(s, ".threshold(16'b0)"), reverse=True):
    s = s[:off] + ".threshold(36'b0)" + s[off + len(".threshold(16'b0)"):]

bak = p + ".before_threshold"
if not os.path.exists(bak):
    open(bak, "w").write(open(p, errors="replace").read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
The VIO probe at the top also reads threshold[0]; if it declares a 16-bit
probe input, widen that too or the debug view stays truncated.  It does not
affect the design itself.
""")
