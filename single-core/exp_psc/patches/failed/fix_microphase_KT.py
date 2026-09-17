#!/usr/bin/env python3
"""
FIX K + FIX T -- microphase boundary spike loss.

TWO DEFECTS, BOTH REQUIRED
--------------------------
FIX K.  STATE_PUSH_PTR_FIFO set uram_addr_inc unconditionally, so the exit
cycle advanced uram_raddr without issuing a read.  At a microphase boundary
that skipped the first row of the next microphase entirely: its spike bits
were never examined and all 16 neurons in it lost every spike they produced.

    measured (8-row microphase):  broken  reads 0..7 then 9,10  -- row 8 absent
                                  fixed   reads 0..7, 8, 9, 10
    measured (hardware):          7 silent spike losses, all row 512, none 513

FIX T.  uram_wren is REGISTERED, so the write at cycle T carries the enable
latched from the read at T-1 -- and pairs with uram_waddr, latched the same
edge.  At a microphase transition the first PUSH cycle therefore inherits
Phase 2's enable AND Phase 2's address, while curr_state is already PUSH so
uram_wdata is computed with Phase-1 semantics.  Result: Phase-1 data written
to a Phase-2 address, clobbering an accumulation.  Non-deterministic on
hardware because which address is stale depends on Phase 2's last write.

    measured (hardware, FIX K alone):  test_max_number_axons[10000] fails,
                                       failing group moves between runs

FIX T gates the write on whether the latched address belongs to the current
microphase.  Testing the address is self-correcting -- no cycle counting, no
flag to clear at the right moment, and microphase 0 needs no special case
because its range starts at 0.

VERIFICATION STATUS
-------------------
FIX K: mechanism confirmed in simulation and matched by the hardware failure
pattern.  FIX T: recovers the spike in simulation (3 spike-cycles vs 0), but
the corruption side is NOT verified -- the simulation monitors disagreed with
each other.  test_max_number_axons[10000] on hardware is the verdict.

  python3 fix_microphase_KT.py --check <internal_events_processor.v>
  python3 fix_microphase_KT.py         <internal_events_processor.v>

Apply to the known-good IEP (normalized 2cc062c7a7807f202fb2f3e859f630a3).
"""

import sys, os, re


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_microphase_KT.py [--check] <internal_events_processor.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

for marker in ("FIX K", "FIX T"):
    if marker in s:
        fail("%s already contains %s -- already patched?" % (p, marker))

edits = []

# ---------------- FIX K ----------------
oldK = """            if (exec_hbm_rvalidready) begin
                uram_addr_inc <= 1'b1;
                if (uram_waddr[0] == microphase_ctr * 512 + uram_microphase_addr_limit) begin
                    next_state <= STATE_PHASE1_DONE;
                end else
                    uram_rden <= 1'b1;
            end"""
newK = """            if (exec_hbm_rvalidready) begin
                // FIX K: uram_addr_inc was unconditional, so the exit cycle
                // advanced uram_raddr without issuing a read, skipping the
                // first row of the next microphase.  Only advance when a read
                // is actually issued.
                if (uram_waddr[0] == microphase_ctr * 512 + uram_microphase_addr_limit) begin
                    next_state <= STATE_PHASE1_DONE;
                end else begin
                    uram_addr_inc <= 1'b1;
                    uram_rden <= 1'b1;
                end
            end"""
if s.count(oldK) != 1:
    fail("STATE_PUSH_PTR_FIFO block not found exactly once in %s (%d)"
         % (p, s.count(oldK)))
edits.append((oldK, newK, "FIX K: conditional address advance"))

# ---------------- FIX T ----------------
for i in range(16):
    m = re.search(
        r"assign uram_wren_%d\s+= \(curr_state==STATE_INIT_URAM\) \? 1'b1 : "
        r"\(curr_state==STATE_WRITE_URAM\) \? \(SET_GROUP_reg==4'd%d\)\s+: "
        r"uram_wren\[%d\];" % (i, i, i), s)
    if not m:
        fail("uram_wren_%d assign not found in %s" % (i, p))
    hdr = ("\n//=========================================================================\n"
           "// FIX T: during PUSH the write address must belong to the CURRENT\n"
           "// microphase.  uram_wren and uram_waddr are both registered from the\n"
           "// previous read, so the first PUSH cycle of a microphase inherits\n"
           "// Phase 2's enable and Phase 2's address while curr_state is already\n"
           "// PUSH -- Phase-1 data written to a Phase-2 address, clobbering the\n"
           "// accumulation there.  Testing the address itself is self-correcting:\n"
           "// no cycle counting, and microphase 0 needs no special case because\n"
           "// its range starts at 0.\n"
           "//=========================================================================\n"
           if i == 0 else "")
    new = hdr + (
        "wire push_waddr_ok_%d = (uram_waddr[%d] >= (microphase_ctr * 512)) &&\n"
        "                       (uram_waddr[%d] <= (microphase_ctr * 512 + uram_microphase_addr_limit));\n"
        "assign uram_wren_%d = (curr_state==STATE_INIT_URAM) ? 1'b1 :\n"
        "                     (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd%d) :\n"
        "                     (curr_state==STATE_PUSH_PTR_FIFO) ? (uram_wren[%d] && push_waddr_ok_%d) :\n"
        "                     uram_wren[%d];" % (i, i, i, i, i, i, i, i))
    edits.append((m.group(0), new, "FIX T: group %d write gate" % i))

print("edit sites verified:")
for _, _, label in edits[:2]:
    print("  ok  %s" % label)
print("  ok  FIX T: write gate on all 16 groups")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

for old, new, label in edits:
    if s.count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    s = s.replace(old, new)

bak = p + ".before_KT"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
Verdict on hardware:
  pytest tests/test_bitstream_hardware_fast.py     42/42 -> FIX T works
  python3 tests/test_microphase_boundary.py        0 losses -> FIX K works

If test_max_number_axons[10000] fails again, revert with the backup and use
the ILA capture rather than another blind attempt.
""")
