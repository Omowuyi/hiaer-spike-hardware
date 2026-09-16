#!/usr/bin/env python3
"""
Make axon_trace_mem infer block RAM.

THE DEFECT
----------
Synthesis of the sixteen-core design reports

    CLB LUTs        6,382,964 of 1,303,680   489.61 per cent
    CLB Registers  12,983,304 of 2,607,360   497.95 per cent

against block RAM at 29.7 per cent and ultra-RAM at 83.3 per cent. The design
is five times too large to place, and the excess is entirely registers.

The cause is this array:

    (* ram_style = "block" *)
    reg [VW-1:0] last_ts [0:NUM_GROUPS-1][0:NUM_ROWS-1];

read as

    rd_ts <= last_ts[rd_group][rd_row];

with rd_group taken from trace_rd_idx[3:0] and rd_row from [16:4]. Both indices
vary, so the read is an arbitrary access into a two-dimensional array. A block
RAM has one address port; it cannot serve a read whose bank index is also
variable. Vivado therefore ignores the ram_style attribute and builds the array
in flip-flops, and the arithmetic accounts for the whole overflow:

    16 groups x 8192 rows x 6 bits =    786,432 bits per core
    x 16 cores                     = 12,582,912
    registers reported             = 12,983,304

The remainder is the rest of the design.

THE FIX
-------
Read every bank at the same row address and select afterwards. Each bank then
has a single variable address, which is exactly what a block RAM provides, and
the bank selection becomes a sixteen-to-one multiplexer on the registered read
data rather than an index into the array.

The write path is unchanged: it already uses a constant bank index per generate
instance and a variable row, which infers correctly.

The stored value is unchanged, the latency is unchanged at one cycle, and the
decay arithmetic is untouched, so tb_at3 must still pass 51 of 51.

  python3 fix_trace_mem_bram.py --check <axon_trace_mem.v>
  python3 fix_trace_mem_bram.py         <axon_trace_mem.v>
"""

import sys, os

OLD_DECL = """    genvar gi;
    generate
        for (gi = 0; gi < NUM_GROUPS; gi = gi + 1) begin : gen_bank
            always @(posedge clk) begin
                if (row_fired && row_mask[gi])
                    last_ts[gi][row_addr] <= {1'b1, timestep};
            end
        end
    endgenerate"""

NEW_DECL = """    // Each bank is read at the same row address every cycle and the bank is
    // selected afterwards. That gives every bank one variable address, which is
    // what a block RAM port provides, so the array infers as sixteen block RAMs
    // rather than as flip-flops. Indexing the array with a variable bank as well
    // as a variable row would require an arbitrary two-dimensional access, which
    // no block RAM can serve, and Vivado would build the whole array in
    // registers -- 786,432 bits per core, twelve and a half million across the
    // device.
    wire [VW-1:0] bank_rd [0:NUM_GROUPS-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_GROUPS; gi = gi + 1) begin : gen_bank
            reg [VW-1:0] bank_dout;
            always @(posedge clk) begin
                if (row_fired && row_mask[gi])
                    last_ts[gi][row_addr] <= {1'b1, timestep};
                if (trace_rd_en)
                    bank_dout <= last_ts[gi][rd_row];
            end
            assign bank_rd[gi] = bank_dout;
        end
    endgenerate"""

OLD_RD = """            rd_pending <= trace_rd_en;
            if (trace_rd_en) begin
                rd_ts  <= last_ts[rd_group][rd_row];
                rd_now <= timestep;
            end"""

NEW_RD = """            rd_pending <= trace_rd_en;
            if (trace_rd_en) begin
                rd_group_q <= rd_group;      // select the bank next cycle
                rd_now     <= timestep;
            end"""

OLD_USE = """            if (rd_pending) begin
                if (!rd_ts[VW-1])"""

NEW_USE = """            if (rd_pending) begin
                if (!rd_ts[VW-1])"""

OLD_REGS = """    reg [VW-1:0]       rd_ts;
    reg [TS_BITS-1:0]  rd_now;
    reg                rd_pending;"""

NEW_REGS = """    reg [3:0]          rd_group_q;
    reg [TS_BITS-1:0]  rd_now;
    reg                rd_pending;

    // the bank selected by the registered group index, available in the same
    // cycle rd_pending is asserted
    wire [VW-1:0] rd_ts = bank_rd[rd_group_q];"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_trace_mem_bram.py [--check] <axon_trace_mem.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "bank_rd" in s:
    fail("already patched")

# the read must be moved before rd_row is used inside the generate, so rd_row
# has to be declared above it
i_rdrow = s.find("wire [ROW_BITS-1:0] rd_row")
i_gen = s.find("genvar gi;")
if i_rdrow < 0 or i_gen < 0:
    fail("could not locate rd_row or the generate block")
if i_rdrow > i_gen:
    print("  !!  rd_row is declared after the generate block; the patch moves "
          "the read into it, so rd_row must be hoisted first")

for tag, a in (("decl", OLD_DECL), ("regs", OLD_REGS), ("read", OLD_RD)):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-5s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

if check:
    print("""
--check: nothing written.

AFTER APPLYING, re-run tb_at3. The stored value, the one-cycle latency and the
decay arithmetic are unchanged, so it must still pass 51 of 51. A change here
that altered behaviour would be worse than the area it saves.
""")
    sys.exit(0)

out = s
# hoist rd_group / rd_row above the generate block
RD_DECLS = """    wire [3:0]          rd_group = trace_rd_idx[3:0];
    wire [ROW_BITS-1:0] rd_row   = trace_rd_idx[16:4];
"""
if RD_DECLS in out:
    out = out.replace(RD_DECLS, "", 1)
    out = out.replace("    genvar gi;", RD_DECLS + "\n    genvar gi;", 1)
else:
    fail("could not hoist the read index declarations; check them by hand")

out = out.replace(OLD_DECL, NEW_DECL, 1)
out = out.replace(OLD_REGS, NEW_REGS, 1)
out = out.replace(OLD_RD, NEW_RD, 1)

bak = p + ".before_bram"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Expect roughly 43 RAMB18 per core in place of 786,432 registers.")
