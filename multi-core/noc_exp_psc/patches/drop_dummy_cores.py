#!/usr/bin/env python3
"""
Drop the 16 dummy cores and the second HBM stack from the NoC top.

WHY THEY WERE THERE
sixteen_core_noc_firefly_top.sv is derived from test_top.sv, which was built for
32 cores across both HBM stacks.  With 16 real cores the upper 16 channels had
nothing driving them, so test_top filled them with dummy_core -- a tie-off that
holds each unused AXI channel at benign constants.

That is correct for a 32-channel design.  It is wrong here: the NoC is 16 cores,
so 16 channels is all the design needs, and hbm_right serves none of them.

WHAT CHANGES
  hbm [31:0]        -> hbm [15:0]
  hbm_right hbm2    -> removed entirely (it maps channels 16-31)
  dummy_core branch -> removed; the generate loop instantiates 16 real cores

The AXI-Stream arrays (after_switch, before_switch, rxFIFO_in, txFIFO_out) stay
at [31:0] because switch_1_32 and switch_32_1 expect 32 elements.  Their upper
16 ports simply never assert and synthesis optimises them away -- narrowing them
would mean swapping in 16-way switches, which is a separate change and not
needed to remove the dummies.

WHAT THIS FREES
An entire HBM stack, 16 dummy instances, and the dummy_core dependency -- the
module that had to be hunted down as disabled in the project.

  python3 drop_dummy_cores.py --check <sixteen_core_noc_firefly_top.sv>
  python3 drop_dummy_cores.py         <sixteen_core_noc_firefly_top.sv>

Run this AFTER a successful build with the dummies in place, so there is a
known-good baseline to compare against.  If the design has not built yet, build
first: this is a cleanup, not a fix for anything that is broken.
"""

import sys, os, re



def _active_find(text, needle, start=0):
    """Index of the first occurrence of needle that is NOT inside a /* */ block.

    test_top.sv -- and everything derived from it -- keeps several superseded
    configurations commented out, so a plain str.find lands in dead code.  That
    is exactly how an earlier version of this patch removed the commented
    hbm_right and left the live one in place.
    """
    incmt, i, n = False, 0, len(text)
    while i < n:
        if not incmt and text.startswith("/*", i):
            incmt = True; i += 2; continue
        if incmt:
            if text.startswith("*/", i): incmt = False; i += 2
            else: i += 1
            continue
        if i >= start and text.startswith(needle, i):
            return i
        i += 1
    return -1


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: drop_dummy_cores.py [--check] <sixteen_core_noc_firefly_top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p, errors="replace").read()

if "hbm_right" not in s:
    fail("%s has no hbm_right -- already patched?" % p)

report = []

# ---- 1. narrow the HBM array (active declaration only) --------------------
pat_hbm = "AXI4 #(33, 256) hbm [31:0] (.aclk(aclk450), .aresetn(aresetn450));"
n_hbm = s.count(pat_hbm)
if n_hbm < 1:
    fail("HBM array declaration not found")
# the active one is the LAST occurrence; earlier ones sit in commented blocks
report.append("hbm array [31:0] -> [15:0]  (%d occurrence(s), patching the active one)" % n_hbm)

# ---- 2. locate hbm_right and its closing paren ----------------------------
i_hr = _active_find(s, "hbm_right hbm2 (")
if i_hr < 0:
    fail("hbm_right instantiation not found")
# scan forward for the matching ");" at depth 0
depth, j = 0, s.index("(", i_hr)
end = -1
while j < len(s):
    if s[j] == "(":
        depth += 1
    elif s[j] == ")":
        depth -= 1
        if depth == 0:
            k = s.find(";", j)
            end = k + 1 if k >= 0 else j + 1
            break
    j += 1
if end < 0:
    fail("could not find the end of the hbm_right instantiation")
report.append("hbm_right instantiation: %d chars, lines %d-%d"
              % (end - i_hr, s[:i_hr].count("\n") + 1, s[:end].count("\n") + 1))

# ---- 3. locate the dummy_core else-branch --------------------------------
i_else = _active_find(s, "               end else begin")
if i_else < 0:
    fail("dummy_core else-branch not found")
i_dummy = _active_find(s, "dummy_core my_core(", i_else)
if i_dummy < 0:
    fail("dummy_core instantiation not found after the else")
# the branch ends at the "end" that closes it, just before the loop's "end"
i_close = s.find("               end\n", i_dummy)
if i_close < 0:
    fail("could not find the end of the dummy_core branch")
i_close += len("               end\n")
report.append("dummy_core branch: lines %d-%d"
              % (s[:i_else].count("\n") + 1, s[:i_close].count("\n") + 1))

print("edits located:")
for r in report:
    print("  ok  %s" % r)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

# Apply from the END of the file backwards, so offsets computed earlier stay
# valid.  hbm_right sits AFTER the dummy branch, so it must be removed first --
# doing the dummy branch first shortens the string and leaves i_hr pointing at
# the wrong place, which silently skips the hbm_right removal.
if i_hr < i_else:
    fail("unexpected layout: hbm_right precedes the dummy branch")
s = s[:i_hr] + s[end:]
s = s[:i_else] + "               end\n" + s[i_close:]
i_last = s.rindex(pat_hbm)
s = (s[:i_last]
     + "AXI4 #(33, 256) hbm [15:0] (.aclk(aclk450), .aresetn(aresetn450));"
       "  // 16 cores, 16 channels -- hbm_right removed"
     + s[i_last + len(pat_hbm):])

bak = p + ".before_dropdummy"
if not os.path.exists(bak):
    open(bak, "w").write(open(p, errors="replace").read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
In Vivado:

    update_compile_order -fileset sources_1
    report_compile_order -used_in synthesis > /tmp/co.txt

then check the missing-instances section is empty and rebuild.

dummy_core is now unreferenced.  Leave the file in the project -- removing it
gains nothing and test_top still uses it.
""")
