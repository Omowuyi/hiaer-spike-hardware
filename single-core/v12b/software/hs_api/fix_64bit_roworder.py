#!/usr/bin/env python3
"""
Fix the 64-bit HBM row order in fpga_compiler._create_synapses_64.

MEASURED ON HARDWARE (check_64bit.py order):

    group -> slot : [12,13,14,15, 8,9,10,11, 4,5,6,7, 0,1,2,3]

The within-quad offset is preserved exactly (group g always reads position
g%4), and the four quads are reversed:

    group quad gq  reads  HBM row 3 - gq

_create_synapses_64 currently writes slot quad q to HBM row q, so every quad
lands in the wrong one.  Writing slot quad q at HBM row 3-q makes group g read
slot g.

A 16-group unit spans 2 logical rows of 8 entries = 4 HBM rows at 64-bit, so
the reversal is applied within each 4-row unit:

    unit   = r // 2
    within = 2 * (r % 2) + half        # 0..3, the slot quad
    hbm    = 4 * unit + (3 - within)   # reversed

RTL is unchanged -- this is purely which HBM row the compiler writes each
group of four entries into.

  python3 fix_64bit_roworder.py --check <fpga_compiler.py>
  python3 fix_64bit_roworder.py         <fpga_compiler.py>

Requires compiler_64bit.py to have been applied first.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_64bit_roworder.py [--check] <fpga_compiler.py>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "_create_synapses_64" not in s:
    fail("%s has no _create_synapses_64 -- run compiler_64bit.py first." % p)
if "_hbm_row_reversed" in s:
    fail("%s already has the row-order fix -- already patched?" % p)

old = ("                rowAddress = '1' + np.binary_repr("
       "SYN_BASE_ADDR + 2 * r + half, 23)")
if s.count(old) != 1:
    fail("row-address line not found exactly once in %s (%d).\n"
         "       Send me _create_synapses_64 and I'll rebase." % (p, s.count(old)))

new = ("                # Measured: group quad gq reads HBM row 3-gq, so slot\n"
       "                # quad q must be written at row 3-q.  Reversal applies\n"
       "                # within each 16-group unit (2 logical rows = 4 HBM rows).\n"
       "                _unit = r // 2\n"
       "                _within = 2 * (r % 2) + half\n"
       "                _hbm_row_reversed = 4 * _unit + (3 - _within)\n"
       "                rowAddress = '1' + np.binary_repr("
       "SYN_BASE_ADDR + _hbm_row_reversed, 23)")

print("edit site verified:")
print("  ok  _create_synapses_64 row address")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_roworder"
if not os.path.exists(bak):
    open(bak, "w").write(s)
open(p, "w").write(s.replace(old, new))
print("patched %s (backup %s)" % (p, bak))
print("""
Re-run:  python3 check_64bit.py order
Expect:  99 199 299 399 499 599 699 799 899 999 1099 1199 1299 1399 1499 1599
""")
