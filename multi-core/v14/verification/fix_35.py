#!/usr/bin/env python3
"""fix_35.py [--check] SRC_DIR -- fix 35: the 16 pointer lanes become 1,024-word first-word-fall-through FIFOs (were FIFO_32: the
fifo_32_wide IP, 512 deep, full at 511).  One phase puts at most one pointer per row into a column (512 rows per microphase) and every
phase starts with the lanes empty, so a lane can no longer fill within a phase: no pointer is dropped (v13 reported 2,474 of 10,000
spikes per step with a whole core firing) and fix 32's stall can never trigger (on v14a-v14c the same network stops at step 1).
The FIFO is RTL in single_core.sv (block-RAM style), unit-tested: 1,025 words before full, 150,831 random words, 0 errors."""
import sys, os
chk = sys.argv[1] == "--check"; d = sys.argv[-1]; f = os.path.join(d, "single_core.sv")
s = open(f).read()
if "fix 35" in s: sys.exit("NOT APPLIED: already patched")
a = "            FIFO_32 ptr(\n"
if s.count(a) != 1: sys.exit("NOT APPLIED: lane FIFO anchor found %d times" % s.count(a))
s = s.replace(a, "            PTR_FIFO_1K ptr(   // fix 35: 1,024-word lane (was FIFO_32, 512)\n")
s = s.rstrip("\n") + "\n\n" + """// fix 35: pointer-lane FIFO, 1,024 words + output register, same ports as FIFO_32 (FIFO_input.Sink / FIFO_output.Source)
module PTR_FIFO_1K (FIFO_input.Sink i, FIFO_output.Source o);
    fwft_fifo_core #(.W(32), .AW(10)) core (.clk(i.clk), .srst(i.reset), .din(i.din), .wr_en(i.wren), .full(i.full),
                                           .dout(o.dout), .rd_en(o.rden), .empty(o.empty));
endmodule

""" + "// fix 35: first-word-fall-through FIFO, common clock, synchronous reset; DEPTH = 2**AW words of storage plus the output register.\n// Block-RAM style: synchronous read into the output register (one word per cycle).  empty = no valid output word; full = storage full.\nmodule fwft_fifo_core #(parameter W = 32, parameter AW = 10) (\n    input  wire         clk, srst,\n    input  wire [W-1:0] din,\n    input  wire         wr_en,\n    output wire         full,\n    output wire [W-1:0] dout,\n    input  wire         rd_en,\n    output wire         empty\n);\n    reg [W-1:0] mem [0:(1<<AW)-1];\n    reg [AW-1:0] wptr, rptr;\n    reg [AW:0]   cnt;                       // words in storage (not counting the output register)\n    reg [W-1:0]  q;\n    reg          v;                         // output register holds a valid word\n    wire wr  = wr_en & ~full;\n    wire pop = rd_en & v;\n    wire ld  = (cnt != 0) & (~v | pop);     // move one word from storage into the output register\n    assign full  = (cnt == (1 << AW));\n    assign empty = ~v;\n    assign dout  = q;\n    always @(posedge clk) if (wr) mem[wptr] <= din;\n    always @(posedge clk) if (ld) q <= mem[rptr];\n    always @(posedge clk) begin\n        if (srst) begin wptr <= 0; rptr <= 0; cnt <= 0; v <= 1'b0; end\n        else begin\n            if (wr) wptr <= wptr + 1'b1;\n            if (ld) rptr <= rptr + 1'b1;\n            cnt <= cnt + (wr ? 1'b1 : 1'b0) - (ld ? 1'b1 : 1'b0);\n            v   <= ld ? 1'b1 : (pop ? 1'b0 : v);\n        end\n    end\nendmodule\n"
if chk: print("CHECK OK (%s)" % f); sys.exit(0)
open(f + ".before_35", "w").write(open(f).read()); open(f, "w").write(s); print("fix 35 applied to single_core.sv (lane FIFOs 1,024 words)")
