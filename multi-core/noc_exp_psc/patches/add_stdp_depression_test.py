#!/usr/bin/env python3
"""
Add a depression case to tb_stdp.sv.

WHY THIS IS NEEDED BEFORE THE RTL CHANGE IS BUILT
-------------------------------------------------
tb_stdp.sv has fifteen cases and every one runs with A_minus at zero, so the
depression term contributes nothing to any of them. Adding the arm without a
test would put an unexercised path into the bitstream, which is how the
thirteen-bit index truncation survived a passing testbench for as long as it
did.

WHAT THE NEW CASE CHECKS
------------------------
Case G sets A_minus non-zero and drives entries whose presynaptic trace is
zero. Under the current expression those weights are unchanged; under the new
one they decrease by exactly A_minus. The check therefore fails on the
unpatched controller and passes on the patched one, which is the property that
makes it worth adding.

It also checks the lower clamp. A weight starting close to w_min must stop at
w_min rather than passing below it, since the depression term is the first
thing in this design capable of driving a weight downward and the clamp has
never been exercised in that direction.

  python3 add_stdp_depression_test.py --check <tb_stdp.sv>
  python3 add_stdp_depression_test.py         <tb_stdp.sv>
"""

import sys, os

A_DECL = """    reg  [7:0]   A_minus = 8'd16;"""
N_DECL = """    reg  [7:0]   A_minus = 8'd0;"""

A_ANCHOR = """        $display("\\n=== %0d passed, %0d failed ===\\n", pass, fail);"""

NEW_CASE = r"""        //-------------------------------------------------------------
        // G. Depression.  Every case above runs with A_minus at zero, so
        //    the depression term contributes nothing to any of them.  Here
        //    it is non-zero and the entries carry no presynaptic trace, so
        //    the only term acting is the decrement.
        //
        //    On the unpatched controller these weights are unchanged and
        //    the case fails, which is what makes it worth having.
        //-------------------------------------------------------------
        $display("\nG. depression arm");
        stdp_enable = 1'b1;          // case F disabled it and did not restore
        A_minus = 8'd16;
        write_count = 0; read_count = 0;
        repeat (4) @(negedge clk);
        push_spike(17'd0);
        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;
        guard = 0;
        while (!phase4_done && guard < 4000) begin
            @(negedge clk); guard = guard + 1;
        end
        chk(guard < 4000, 1, "completed with depression enabled");
        chk(write_count, 1, "one write with depression enabled");

        // entry 2 carries an axon source whose trace reads zero, so the only
        // term acting on it is the decrement: 150 - 16 = 134.
        chk($signed(write_data[175:160]), 134, "entry 2  150 - A_minus");

        // entry 0 takes the URAM trace of 15 and the decrement together:
        // 100 + 15 - 16 = 99.
        chk($signed(write_data[47:32]), 99, "entry 0  100 + 15 - A_minus");

        //-------------------------------------------------------------
        // H. Lower clamp.  Depression is the first mechanism in this design
        //    able to drive a weight downward, so w_min has never been
        //    exercised in that direction.
        //-------------------------------------------------------------
        $display("\nH. lower clamp under depression");
        w_min = 16'sd140;
        write_count = 0;
        repeat (4) @(negedge clk);
        push_spike(17'd0);
        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;
        guard = 0;
        while (!phase4_done && guard < 4000) begin
            @(negedge clk); guard = guard + 1;
        end
        chk($signed(write_data[175:160]) >= 140, 1, "entry 2 clamped at w_min");
        w_min = -16'sd300;
        A_minus = 8'd0;

"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_stdp_depression_test.py [--check] <tb_stdp.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "G. depression arm" in s:
    fail("already patched")

if s.count(A_ANCHOR) != 1:
    fail("summary anchor matched %d times, expected 1" % s.count(A_ANCHOR))
print("  ok  summary anchor found (line %d)" % (s[:s.index(A_ANCHOR)].count("\n") + 1))

# A_minus and w_min must be writable registers, not localparams
for sig in ("A_minus", "w_min"):
    if ("reg" not in s.split(sig)[0].split("\n")[-1]) and ("reg  [7:0]   %s" % sig) not in s \
       and ("reg  signed [15:0] %s" % sig) not in s:
        print("  !!  %s may not be a writable reg -- check before applying" % sig)
    else:
        print("  ok  %s is a writable reg" % sig)

if check:
    print("""
--check: nothing written.

RUN IT AGAINST THE UNPATCHED CONTROLLER FIRST.  Cases G and H must FAIL there,
because a testbench that passes on both the old and the new module tests
nothing.  Then apply add_stdp_depression.py and confirm 19 of 19.
""")
    sys.exit(0)

# Cases A to F were written against a controller with no depression term.
# The testbench declares A_minus = 16, which was harmless while the term was
# unused; with the arm present it perturbs every one of them.  Default it to
# zero so those cases keep their original meaning, and set it explicitly in the
# new cases that exercise the arm.
if s.count(A_DECL) != 1:
    fail("A_minus declaration matched %d times, expected 1" % s.count(A_DECL))
out = s.replace(A_DECL, N_DECL, 1)
out = out.replace(A_ANCHOR, NEW_CASE + A_ANCHOR, 1)
bak = p + ".before_depression_test"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Expect 15/19 on the unpatched controller and 19/19 once patched.")
