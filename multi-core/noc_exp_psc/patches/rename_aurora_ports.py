#!/usr/bin/env python3
"""
Rename the AUR_0 ports to ff7_* and correct their bit order.

TWO PROBLEMS
------------
1. NAMES.  The board pinout in hiaer_multicore_firefly_complete.xdc constrains
   ports called ff7_refclk_p/n, ff7_txp[3:0], ff7_txn[3:0], ff7_rxp[3:0] and
   ff7_rxn[3:0].  The top declares the same signals as GT_SERIAL_TX_AUR_0_txp
   and so on, so the constraints match nothing.

2. BIT ORDER, which is the dangerous one.  The top declares

       input  [0:3] GT_SERIAL_RX_AUR_0_rxp

   ascending, so bit 0 is the MSB.  firefly_subsystem_top expects [3:0] and the
   XDC assigns ff7_txp[0] to L48, [1] to L44, [2] to K46, [3] to J48.  Connect a
   [0:3] port to a [3:0] expression and the lanes REVERSE: logical lane 0 drives
   the pin the board wires to lane 3.

   Aurora would still train and bond -- lane alignment is part of the protocol --
   and then carry data with the lanes permuted.  That presents as a link which
   comes up and delivers corrupted payloads, which is far harder to diagnose
   than a link that never comes up at all.

RENAMING RATHER THAN TRANSLATING
--------------------------------
The alternative is to rewrite the vendor constraints into GT_SERIAL_* names.
That leaves a translated copy of a board pinout in the tree, which the next
person has to know about.  Renaming the ports makes the supplied constraints
apply unmodified, matches the ff4-ff7 naming the Firefly design uses
throughout, and lets an upper-tier build take ff4 to ff6 from the same file
without further work.

AUR_1 IS LEFT ALONE
-------------------
It is unused on a lower-tier device.  When an upper-tier build needs a second
channel it should be renamed to whichever of ff4, ff5 or ff6 the connector
carries, decided against the board documentation rather than assumed here.

  python3 rename_aurora_ports.py --check <sixteen_core_noc_firefly_top.sv>
  python3 rename_aurora_ports.py         <sixteen_core_noc_firefly_top.sv>
"""

import sys, os

EDITS = [
    # port declarations -- note the [0:3] to [3:0] correction
    ("decl_rxn", "    input [0:3]GT_SERIAL_RX_AUR_0_rxn,",
                 "    input  [3:0] ff7_rxn,"),
    ("decl_rxp", "    input [0:3]GT_SERIAL_RX_AUR_0_rxp,",
                 "    input  [3:0] ff7_rxp,"),
    ("decl_txn", "    output [0:3]GT_SERIAL_TX_AUR_0_txn,",
                 "    output [3:0] ff7_txn,"),
    ("decl_txp", "    output [0:3]GT_SERIAL_TX_AUR_0_txp,",
                 "    output [3:0] ff7_txp,"),
    ("decl_clkn", "    input GT_DIFF_REFCLK1_0_clk_n,",
                  "    input        ff7_refclk_n,"),
    ("decl_clkp", "    input GT_DIFF_REFCLK1_0_clk_p,",
                  "    input        ff7_refclk_p,"),
    # instantiation -- the port and the signal now share a name
    ("inst_clkp", "        .ff7_refclk_p  (GT_DIFF_REFCLK1_0_clk_p),",
                  "        .ff7_refclk_p  (ff7_refclk_p),"),
    ("inst_clkn", "        .ff7_refclk_n  (GT_DIFF_REFCLK1_0_clk_n),",
                  "        .ff7_refclk_n  (ff7_refclk_n),"),
    ("inst_txp", "        .ff7_txp (GT_SERIAL_TX_AUR_0_txp),",
                 "        .ff7_txp (ff7_txp),"),
    ("inst_txn", "        .ff7_txn (GT_SERIAL_TX_AUR_0_txn),",
                 "        .ff7_txn (ff7_txn),"),
    ("inst_rxp", "        .ff7_rxp (GT_SERIAL_RX_AUR_0_rxp),",
                 "        .ff7_rxp (ff7_rxp),"),
    ("inst_rxn", "        .ff7_rxn (GT_SERIAL_RX_AUR_0_rxn),",
                 "        .ff7_rxn (ff7_rxn),"),
]


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: rename_aurora_ports.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "input  [3:0] ff7_rxn," in s:
    fail("already patched")

for tag, old, _ in EDITS:
    n = s.count(old)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
print("  ok  %d anchors verified" % len(EDITS))

# AUR_0 must not survive anywhere else, or a stray reference will dangle
leftovers = [l for l in s.split("\n")
             if ("AUR_0" in l or "GT_DIFF_REFCLK1_0" in l)
             and not l.lstrip().startswith("//")]
known = {old.strip() for _, old, _ in EDITS}
stray = [l for l in leftovers if l.strip() not in known]
if stray:
    print("  !!  %d further CODE reference(s) to AUR_0 that this patch does not touch:" % len(stray))
    for l in stray[:6]:
        print("        %s" % l.strip()[:70])
    fail("resolve these before renaming, or they will dangle")
print("  ok  no other AUR_0 references")

if check:
    print("""
--check: nothing written.

AFTER APPLYING, extract the ff7 lines from the board pinout into their own
constraint file.  Do NOT add the whole file: it also constrains
pcie_clk_in_clk, sys_rst_n and refclk450, which constrs_3 already covers, and
duplicate PACKAGE_PIN assignments are an error.

    F=/data/omowuyi/multicore_noc_exp_psc/project/firefly_integration/hiaer_multicore_firefly_complete.xdc
    O=/data/omowuyi/multicore_noc_exp_psc/project/ff7_pins.xdc
    grep -E "ff7_(refclk|txp|txn|rxp|rxn)" $F | grep -v "modprs\\|scl\\|sda" > $O

The sideband pins ff7_modprs_n, ff7_scl and ff7_sda are excluded because
nothing in the design drives them -- constraining a port that does not exist
is an error.  They are module-present detect and the optical module's I2C
management interface; a link comes up without them.

Then:

    add_files -fileset constrs_3 $O
""")
    sys.exit(0)

out = s
for _, old, new in EDITS:
    out = out.replace(old, new, 1)

bak = p + ".before_ffnames"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Ports are now ff7_* with [3:0] ordering, matching the board pinout.")
