#!/usr/bin/env python3
"""fix_34.py [--check] SRC_DIR -- fix 34: no pointer is pushed for an input at or beyond num_inputs, and none for a zero-length pointer.
Both input-side processors bound a pass at row floor(num_inputs/16) INCLUSIVE, so when num_inputs is a multiple of 16 they read one
row past the input range (in lockstep: the input processor reads that relay/axon row, the HBM processor its pointer row).  Relays
landing there were turned into pointers read from past the written pointer table (zeros), and the zero pointers were followed as
1-beat reads of HBM address 0, whose pointer data Phase 2 applied as synapses (round 49: cores 10/11, 13/15 such reads at steps 5/6).
Both sides keep reading exactly the rows they read today (their lockstep pairing is untouched); now
  A) single_core: exec_bram_spiked also masks every input bit >= num_inputs (row compared with floor(num_inputs/16));
  B) pointer_fifo_controller: a pointer whose length field (bits 31:23) is 0 is not written (nothing to read)."""
import sys, os, re
chk = sys.argv[1] == "--check"; d = sys.argv[-1]
F = {"sc": os.path.join(d, "single_core.sv"), "pfc": os.path.join(d, "pointer_fifo_controller.v")}
S = {k: open(v).read() for k, v in F.items()}
if any("fix 34" in v for v in S.values()): sys.exit("NOT APPLIED: already patched")
a = "    assign exec_bram_spiked = exec_eep_spiked & {16{w_eep_reading_inputs}};"
if S["sc"].count(a) != 1: sys.exit("NOT APPLIED: single_core anchor found %d times" % S["sc"].count(a))
b = ("    // fix 34: an input bit at or beyond num_inputs pushes no pointer (rows are read up to floor(num_inputs/16) inclusive)\n"
     "    wire [12:0] w_nin_row  = num_inputs[16:4];\n"
     "    wire [15:0] w_nin_mask = (w_curr_bram_waddr <  w_nin_row) ? 16'hFFFF :\n"
     "                             (w_curr_bram_waddr == w_nin_row) ? ((16'h0001 << num_inputs[3:0]) - 16'h0001) : 16'h0000;   // fix 34\n"
     "    assign exec_bram_spiked = exec_eep_spiked & {16{w_eep_reading_inputs}} & w_nin_mask;   // fix 34 (and fix 30)")
S["sc"] = S["sc"].replace(a, b, 1)
n = 0
for k in range(16):
    old = "assign ptr%d_wren = !ptr%d_full & exec_hbm_rvalidready & (" % (k, k)
    c = S["pfc"].count(old)
    if c != 1: sys.exit("NOT APPLIED: pointer controller anchor for ptr%d found %d times" % (k, c))
    S["pfc"] = S["pfc"].replace(old, "assign ptr%d_wren = !ptr%d_full & exec_hbm_rvalidready & (|exec_hbm_rdata[%d:%d]) & (" % (k, k, 32 * k + 31, 32 * k + 23)); n += 1
S["pfc"] = S["pfc"].replace("\nassign ptr0_wren =", "\n// fix 34: a zero-length pointer (length field, bits 31:23 of each pointer) is not written: there is nothing to read\nassign ptr0_wren =", 1)
if chk: print("CHECK OK (%s)" % ", ".join(F.values())); sys.exit(0)
for k, p in F.items(): open(p + ".before_34", "w").write(open(p).read()); open(p, "w").write(S[k])
print("fix 34 applied: single_core.sv (input-range mask), pointer_fifo_controller.v (%d zero-length guards)" % n)
