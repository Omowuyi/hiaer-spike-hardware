#!/usr/bin/env python3
"""
Declare the FireFly optical ports at the top level.

THE DEFECT
----------
The port declarations for the optical interface sit inside a comment:

    /*
        input  [3:0] ff7_rxn,
        ...
        input        ff7_refclk_p,
    */

so get_ports ff7_* returns nothing. The subsystem is still connected with
.ff7_txp (ff7_txp), which in Verilog creates an implicit one-bit wire rather
than an error, so the design elaborates and synthesises with thirty-two GT
channels whose serial pins reach no package pin at all.

Three consequences follow, and each was previously attributed to something
else:

  the PACKAGE_PIN constraints in ff7_pins.xdc matched no object
  the three set_clock_groups critical warnings had no clock to find
  no optical link could train, whatever the transceiver placement

The comment also holds GT_SERIAL_*_AUR_1_* and GT_DIFF_REFCLK1_1_*, the second
optical group of an earlier design, which suggests the whole port block was
commented out during bring-up and never restored.

WHAT THIS WRITES
----------------
Real declarations for all four ports, replacing the comment. Widths and
directions follow the constraint file:

    ff4  refclk T13/T12   lanes L7  ...   quad 234
    ff5  refclk P13/P12   lanes G7  ...   quad 235
    ff6  refclk P42/P43   lanes G48 ...   quad 135
    ff7  refclk T42/T43   lanes L48 ...   quad 134

The AUR_1 group is not restored: the four FireFly ports replace it.

  python3 declare_firefly_ports.py --check <sixteen_core_noc_firefly_top.sv>
  python3 declare_firefly_ports.py         <sixteen_core_noc_firefly_top.sv>
"""

import sys, os, re

NEW_PORTS = """    // FireFly optical ports. Four transceiver quads, one per port:
    //   ff4  refclk T13/T12  quad 234  channels X1Y40..43
    //   ff5  refclk P13/P12  quad 235  channels X1Y44..47
    //   ff6  refclk P42/P43  quad 135  channels X0Y44..47
    //   ff7  refclk T42/T43  quad 134  channels X0Y40..43
    input        ff4_refclk_p,
    input        ff4_refclk_n,
    input  [3:0] ff4_rxp,
    input  [3:0] ff4_rxn,
    output [3:0] ff4_txp,
    output [3:0] ff4_txn,
    input        ff5_refclk_p,
    input        ff5_refclk_n,
    input  [3:0] ff5_rxp,
    input  [3:0] ff5_rxn,
    output [3:0] ff5_txp,
    output [3:0] ff5_txn,
    input        ff6_refclk_p,
    input        ff6_refclk_n,
    input  [3:0] ff6_rxp,
    input  [3:0] ff6_rxn,
    output [3:0] ff6_txp,
    output [3:0] ff6_txn,
    input        ff7_refclk_p,
    input        ff7_refclk_n,
    input  [3:0] ff7_rxp,
    input  [3:0] ff7_rxn,
    output [3:0] ff7_txp,
    output [3:0] ff7_txn,
"""

OLD_TIE = """        .ff4_refclk_p  (1'b0), .ff4_refclk_n (1'b1),
        .ff5_refclk_p  (1'b0), .ff5_refclk_n (1'b1),
        .ff6_refclk_p  (1'b0), .ff6_refclk_n (1'b1),"""

NEW_TIE = """        .ff4_refclk_p  (ff4_refclk_p), .ff4_refclk_n (ff4_refclk_n),
        .ff5_refclk_p  (ff5_refclk_p), .ff5_refclk_n (ff5_refclk_n),
        .ff6_refclk_p  (ff6_refclk_p), .ff6_refclk_n (ff6_refclk_n),"""

OLD_LANES = """        .ff4_txp (), .ff4_txn (), .ff4_rxp (4'd0), .ff4_rxn (4'hF),
        .ff5_txp (), .ff5_txn (), .ff5_rxp (4'd0), .ff5_rxn (4'hF),
        .ff6_txp (), .ff6_txn (), .ff6_rxp (4'd0), .ff6_rxn (4'hF),"""

NEW_LANES = """        .ff4_txp (ff4_txp), .ff4_txn (ff4_txn), .ff4_rxp (ff4_rxp), .ff4_rxn (ff4_rxn),
        .ff5_txp (ff5_txp), .ff5_txn (ff5_txn), .ff5_rxp (ff5_rxp), .ff5_rxn (ff5_rxn),
        .ff6_txp (ff6_txp), .ff6_txn (ff6_txn), .ff6_rxp (ff6_rxp), .ff6_rxn (ff6_rxn),"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: declare_firefly_ports.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "input        ff4_refclk_p," in s:
    fail("already patched")

# Locate the commented block by its delimiters rather than by its contents:
# matching on the port text has proved fragile, while the /* that precedes
# ff7_rxn and its closing */ are unambiguous.
lines = s.split("\n")
open_i = close_i = -1
for i, ln in enumerate(lines):
    if ln.strip() == "/*" and open_i < 0:
        # the block we want is the one containing ff7_rxn
        for j in range(i + 1, min(i + 25, len(lines))):
            if lines[j].strip() == "*/":
                break
            if "ff7_rxn" in lines[j]:
                open_i, close_i = i, None
                break
    if open_i >= 0 and close_i is None and i > open_i and lines[i].strip() == "*/":
        close_i = i
        break
if open_i < 0 or not close_i:
    fail("could not find the commented optical port block")
print("  ok  commented port block found (lines %d to %d)" % (open_i + 1, close_i + 1))

class _M:
    def __init__(self, a, b): self._a, self._b = a, b
    def start(self): return self._a
    def end(self): return self._b
_pre = "\n".join(lines[:open_i])
_post = "\n".join(lines[close_i + 1:])
m = _M(len(_pre) + 1, len(s) - len(_post))

for tag, a in (("refclk tie-offs", OLD_TIE), ("lane tie-offs", OLD_LANES)):
    if s.count(a) != 1:
        fail("%s matched %d times, expected 1" % (tag, s.count(a)))
    print("  ok  %s found" % tag)

if check:
    print("""
--check: nothing written.

AFTER APPLYING, confirm the ports exist before anything else:

  puts [llength [get_ports -quiet ff*]]

Expect 24: four ports of two reference pins and four lane pairs. Until that
number is non-zero the pin constraints match nothing and no link can train.
""")
    sys.exit(0)

out = _pre + "\n" + NEW_PORTS + _post
out = out.replace(OLD_TIE, NEW_TIE, 1).replace(OLD_LANES, NEW_LANES, 1)

bak = p + ".before_ffports"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Twenty-four optical ports declared and connected.")
