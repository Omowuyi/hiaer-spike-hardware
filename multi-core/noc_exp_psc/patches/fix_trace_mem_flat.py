#!/usr/bin/env python3
"""
Flatten axon_trace_mem's two-dimensional array into one memory per bank.

WHY THE FIRST FIX WAS NOT ENOUGH
--------------------------------
fix_trace_mem_bram.py corrected the access pattern so that every read and write
uses a constant bank index and a single variable row. That is necessary but not
sufficient. Synthesis still reports

    WARNING: [Synth 8-11357] Potential Runtime issue for 3D-RAM or RAM from
    Record/Structs for RAM last_ts_reg with 786432 registers

786,432 registers is the whole array for one core, so it is still in flip-flops.
Vivado classifies

    reg [VW-1:0] last_ts [0:NUM_GROUPS-1][0:NUM_ROWS-1];

as a three-dimensional RAM, counting the packed dimension, and will not infer
block RAM from it whatever ram_style requests and however it is addressed.

THE FIX
-------
Declare one flat memory per bank inside the generate block. Each is then a
one-dimensional unpacked array with a single variable address, which is exactly
what a block RAM port provides. Sixteen such arrays replace one two-dimensional
array; the storage, the addressing and the behaviour are identical.

The per-bank initial loop moves inside the generate with its memory.

Apply after fix_trace_mem_bram.py.

  python3 fix_trace_mem_flat.py --check <axon_trace_mem.v>
  python3 fix_trace_mem_flat.py         <axon_trace_mem.v>
"""

import sys, os

OLD_ARR = """    (* ram_style = "block" *)
    reg [VW-1:0] last_ts [0:NUM_GROUPS-1][0:NUM_ROWS-1];

    integer g, r;
    initial
        for (g = 0; g < NUM_GROUPS; g = g + 1)
            for (r = 0; r < NUM_ROWS; r = r + 1)
                last_ts[g][r] = {VW{1'b0}};      // valid bit clear
"""

OLD_GEN = """        for (gi = 0; gi < NUM_GROUPS; gi = gi + 1) begin : gen_bank
            reg [VW-1:0] bank_dout;
            always @(posedge clk) begin
                if (row_fired && row_mask[gi])
                    last_ts[gi][row_addr] <= {1'b1, timestep};
                if (trace_rd_en)
                    bank_dout <= last_ts[gi][rd_row];
            end
            assign bank_rd[gi] = bank_dout;
        end"""

NEW_GEN = """        for (gi = 0; gi < NUM_GROUPS; gi = gi + 1) begin : gen_bank
            // One flat memory per bank. A two-dimensional array is classified
            // by Vivado as a three-dimensional RAM and built in registers
            // whatever ram_style asks for, which cost 786,432 registers per
            // core. A one-dimensional array with a single variable address is
            // what a block RAM port provides and infers correctly.
            (* ram_style = "block" *)
            reg [VW-1:0] last_ts [0:NUM_ROWS-1];
            reg [VW-1:0] bank_dout;

            integer r;
            initial
                for (r = 0; r < NUM_ROWS; r = r + 1)
                    last_ts[r] = {VW{1'b0}};     // valid bit clear

            always @(posedge clk) begin
                if (row_fired && row_mask[gi])
                    last_ts[row_addr] <= {1'b1, timestep};
                if (trace_rd_en)
                    bank_dout <= last_ts[rd_row];
            end
            assign bank_rd[gi] = bank_dout;
        end"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_trace_mem_flat.py [--check] <axon_trace_mem.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "reg [VW-1:0] last_ts [0:NUM_ROWS-1]" in s:
    fail("already patched")
if "bank_rd" not in s:
    fail("fix_trace_mem_bram.py has not been applied; apply it first")

for tag, a in (("array", OLD_ARR), ("generate", OLD_GEN)):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-8s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

if check:
    print("""
--check: nothing written.

AFTER APPLYING, re-run tb_at3 under xsim. The storage, the addressing and the
decay arithmetic are unchanged, so it must still pass 51 of 51, and synthesis
must no longer report Synth 8-11357 for last_ts_reg.
""")
    sys.exit(0)

out = s.replace(OLD_ARR, "", 1).replace(OLD_GEN, NEW_GEN, 1)
bak = p + ".before_flat"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Expect Synth 8-11357 to disappear and RAMB18 to rise by about 43 per core.")
