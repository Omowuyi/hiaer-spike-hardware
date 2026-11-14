#!/usr/bin/env python3
"""fix_32.py SRC_DIR [--check] -- fix 32: a pointer row is taken only when every column it writes has room in its pointer FIFO.
pointer_fifo_controller wrote each spiking neuron's pointer into its column's FIFO with `ptrK_wren = !ptrK_full & ...` while the
row was consumed regardless (hbm2pfc_rden = exec_hbm_rvalidready), so with the FIFO full the pointer -- and every synapse of that
neuron that step -- was silently lost (round 48/48b on the card: 408-2,768 deliveries missing when spiking neurons share few
columns; none when spread).  The controller now raises ptr_stall when a column the current row needs has a full FIFO, and
single_core holds the core-clock row handshake (exec_hbm_rvalidready, shared by the controller and the input processors) while it
is high, so the row waits and nothing is dropped.  ptr_stall uses only registered state, the row masks and the FIFO full flags."""
import sys, os
d = sys.argv[1]; chk = "--check" in sys.argv
F = {"pfc": os.path.join(d, "pointer_fifo_controller.v"), "sc": os.path.join(d, "single_core.sv")}
S = {k: open(v).read() for k, v in F.items()}
if any("fix 32" in v for v in S.values()): sys.exit("NOT APPLIED: already patched")
E = [("pfc", "    output wire       ptr_lanes_idle   // fix 26: every lane FIFO empty for 15 cycles\n",
             "    output wire       ptr_lanes_idle,  // fix 26: every lane FIFO empty for 15 cycles\n"
             "    output wire       ptr_stall        // fix 32: a column this row needs has a full pointer FIFO: hold the row\n"),
     ("pfc", "reg bram_reading, uram_reading;\n",
             "reg bram_reading, uram_reading;\n"
             "// fix 32: take a pointer row only when every column it writes has room; otherwise the row waits and no pointer is lost\n"
             "wire [15:0] ptr_full_v = {ptr15_full, ptr14_full, ptr13_full, ptr12_full, ptr11_full, ptr10_full, ptr9_full, ptr8_full,\n"
             "                          ptr7_full, ptr6_full, ptr5_full, ptr4_full, ptr3_full, ptr2_full, ptr1_full, ptr0_full};\n"
             "assign ptr_stall = |(((bram_reading ? exec_bram_spiked : 16'd0) | (uram_reading ? exec_uram_spiked : 16'd0)) & ptr_full_v);\n"),
     ("sc",  "    assign exec_hbm_rvalidready = ~hbmdataFIFO_out.empty;\n",
             "    wire w_ptr_stall;   // fix 32\n"
             "    assign exec_hbm_rvalidready = ~hbmdataFIFO_out.empty & ~w_ptr_stall;   // fix 32: hold the row while a pointer FIFO it needs is full\n"),
     ("sc",  "        .ptr_lanes_idle(w_ptr_lanes_idle),   // fix 26\n",
             "        .ptr_lanes_idle(w_ptr_lanes_idle),   // fix 26\n        .ptr_stall(w_ptr_stall),             // fix 32\n")]
for k, a, b in E:
    n = S[k].count(a)
    if n != 1: sys.exit("NOT APPLIED: anchor %r found %d times in %s" % (a.strip()[:60], n, F[k]))
    S[k] = S[k].replace(a, b)
if chk: print("CHECK OK (%s)" % ", ".join(F.values())); sys.exit(0)
for k, p in F.items(): open(p + ".before_fix32", "w").write(open(p).read()); open(p, "w").write(S[k])
print("fix 32 applied: %s" % ", ".join(F.values()))
