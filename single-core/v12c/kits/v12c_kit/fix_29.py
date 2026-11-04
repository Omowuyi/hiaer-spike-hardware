#!/usr/bin/env python3
"""fix_29.py [--check] SRC_DIR -- fix 29 (all cores): a state machine's bits must leave reset on the same clock edge.
In v12b, Vivado treated the 16 per-core reset synchronisers as ordinary equivalent flip-flops: 43 copies, and core 2's HBM
processor transmit state bits 1/3 were released by core 1's copy and bits 0/2 by core 14's.  Leaving RESET (0100) for IDLE
(0111) with bits 1/3 one edge ahead of 0/2 gives 0110 = WRITE_HBM_RESP, where core 2 sat from power-up.
(1) reset_synchronizer: ASYNC_REG + DONT_TOUCH on both flip-flops -- one local pair per instance, never merged or replicated;
(2) hbm_processor: the incoming reset is registered once locally (resetn_l, DONT_TOUCH) and every internal reset uses it."""
import sys, re, os
chk = sys.argv[1] == "--check"; d = sys.argv[-1]
hp, rs = os.path.join(d, "hbm_processor.v"), os.path.join(d, "reset_synchronizer.sv")
h = open(hp).read()
if "fix 29" in h: sys.exit("NOT APPLIED: already patched")
# hbm_processor: local reset register right after the port list; every use of resetn except the port declaration -> resetn_l
m = re.search(r"module\s+hbm_processor\b.*?\)\s*;", h, re.S)
if not m: sys.exit("NOT APPLIED: hbm_processor port list not found")
port = re.findall(r"^\s*input\s+resetn\s*,", h[:m.end()], re.M)
if len(port) != 1: sys.exit("NOT APPLIED: resetn port declaration found %d times" % len(port))
body = h[m.end():]
n_uses = len(re.findall(r"\bresetn\b", body))
if n_uses != 15: sys.exit("NOT APPLIED: %d uses of resetn in the body (expected 15)" % n_uses)
body = re.sub(r"\bresetn\b", "resetn_l", body)
ins = ("\n// fix 29: one local reset register for the whole HBM processor -- every state machine bit leaves reset on the same\n"
       "// edge (in v12b one core's state bits were released by two other cores' merged synchroniser copies).\n"
       "(* DONT_TOUCH = \"TRUE\" *) reg resetn_l = 1'b0;\n"
       "always @(posedge clk) resetn_l <= resetn;\n")
h = h[:m.end()] + ins + body
# reset_synchronizer: ASYNC_REG + DONT_TOUCH on both flip-flops (only where the file is part of these sources)
r = None
if os.path.exists(rs):
    r = open(rs).read()
    a1 = re.findall(r"^(\s*)output\s+reg\s+reset_out\b", r, re.M); a2 = re.findall(r"^(\s*)reg\s+q\s*;", r, re.M)
    if len(a1) != 1 or len(a2) != 1: sys.exit("NOT APPLIED: reset_synchronizer declarations found %d/%d times" % (len(a1), len(a2)))
    attr = '(* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) '
    r = re.sub(r"^(\s*)output\s+reg\s+reset_out\b", lambda x: x.group(1) + attr + "output reg reset_out", r, flags=re.M)
    r = re.sub(r"^(\s*)reg\s+q\s*;", lambda x: x.group(1) + attr + "reg q;   // fix 29", r, flags=re.M)
if chk: print("CHECK OK (hbm_processor%s)" % (" + reset_synchronizer" if r else "")); sys.exit(0)
open(hp + ".before_29", "w").write(open(hp).read()); open(hp, "w").write(h)
if r is not None: open(rs + ".before_29", "w").write(open(rs).read()); open(rs, "w").write(r)
print("fix 29 applied to hbm_processor.v%s" % (" and reset_synchronizer.sv" if r is not None else " (no reset_synchronizer.sv in these sources)"))
