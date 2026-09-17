#!/usr/bin/env python3
"""
Report whether FIX T ever fires -- error_status bit 12.

WHY NOT AN ILA
The previous attempt marked uram_waddr and uram_wren with mark_debug and cost
828 ps of WNS (+43 -> -785).  Those are high-fanout nets that need replication
to meet timing, and mark_debug freezes them.  Worse, mark_debug alone does not
insert an ILA -- Vivado only preserves the nets, so the timing was spent for
no capture at all.

WHAT THIS DOES INSTEAD
FIX T already computes push_waddr_ok_0 for its write gate.  This ORs the
suppressed condition into one sticky bit and routes it to the CI, readable
with CMD 10 alongside the existing error flags.  Cost: one AND and one
register on a signal that already exists.  Same pattern as the spk_dropped
detector, which built at +43 ps.

WHAT IT TELLS YOU
    bit 12 SET    FIX T suppressed at least one stale PUSH write -- the
                  mechanism is real and the gate is active
    bit 12 CLEAR  FIX T never fired.  If test_max_number_axons still fails,
                  the corruption is NOT the stale-address write and every
                  fix aimed at it has been aimed at the wrong thing

That second outcome is the valuable one: it would eliminate in a single run
the hypothesis that eight attempts have been built on.

  python3 add_stale_write_flag.py --check <internal_events_processor.v> <single_core.sv> <command_interpreter.v>
  python3 add_stale_write_flag.py         <internal_events_processor.v> <single_core.sv> <command_interpreter.v>

Apply AFTER fix_microphase_KT.py -- it depends on push_waddr_ok_0.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 3:
    fail("usage: add_stale_write_flag.py [--check] <internal_events_processor.v> "
         "<single_core.sv> <command_interpreter.v>")
iep_p, sc_p, ci_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

iep = open(iep_p).read()
sc = open(sc_p).read()
ci = open(ci_p).read()

if "push_waddr_ok_0" not in iep:
    fail("%s has no push_waddr_ok_0 -- run fix_microphase_KT.py first." % iep_p)
for p, s in ((iep_p, iep), (sc_p, sc), (ci_p, ci)):
    if "dbg_stale_write" in s:
        fail("%s already patched." % p)

edits = []

# ---------------- IEP: the sticky flag ----------------
o = "    input  wire [3:0]  dbuf_delayed_group,   // FIX I: bank for the drained entry\n"
if iep.count(o) != 1:
    fail("dbuf_delayed_group port not found exactly once in %s" % iep_p)
edits.append((iep_p, o,
  "    // Sticky: FIX T suppressed a PUSH write whose latched address belonged\n"
  "    // to a previous microphase.  Cleared only by reset.\n"
  "    output reg         dbg_stale_write,\n" + o, "IEP port"))

o = "assign uram_wren_0 = (curr_state==STATE_INIT_URAM) ? 1'b1 :"
if iep.count(o) != 1:
    fail("uram_wren_0 assign not found exactly once in %s -- is FIX T applied?" % iep_p)
edits.append((iep_p, o,
  "// Sticky record of FIX T firing.  push_waddr_ok_0 is already computed for\n"
  "// the gate, so this is one AND and one register.\n"
  "always @(posedge clk) begin\n"
  "    if (~resetn)\n"
  "        dbg_stale_write <= 1'b0;\n"
  "    else if (curr_state == STATE_PUSH_PTR_FIFO && uram_wren[0] && !push_waddr_ok_0)\n"
  "        dbg_stale_write <= 1'b1;\n"
  "end\n\n" + o, "IEP sticky flag"))

# ---------------- single_core: wire it through ----------------
o = "    wire        w_spk_dropped;   // spike discarded, FIFO full\n"
if sc.count(o) != 1:
    fail("w_spk_dropped declaration not found exactly once in %s -- run "
         "detect_spike_drop.py first." % sc_p)
edits.append((sc_p, o, o + "    wire        w_dbg_stale_write;  // FIX T suppressed a stale PUSH write\n",
              "SC wire"))

o = "        .dbuf_delayed_group(w_dbuf_delayed_group),\n"
if sc.count(o) != 1:
    fail("IEP dbuf_delayed_group hookup not found exactly once in %s" % sc_p)
edits.append((sc_p, o, "        .dbg_stale_write(w_dbg_stale_write),\n" + o, "SC IEP hookup"))

# .spk_dropped appears on BOTH the hbm_processor and CI instances -- anchor on
# the following line to pick the CI one.
o = ("        .spk_dropped(w_spk_dropped),\n"
     "        .delay_table_waddr(w_delay_table_waddr),")
if sc.count(o) != 1:
    fail("CI spk_dropped/delay_table hookup not found exactly once in %s (%d)"
         % (sc_p, sc.count(o)))
edits.append((sc_p, o,
  "        .spk_dropped(w_spk_dropped),\n"
  "        .dbg_stale_write(w_dbg_stale_write),\n"
  "        .delay_table_waddr(w_delay_table_waddr),", "SC CI hookup"))

# ---------------- CI: error_status bit 12 ----------------
o = "   input        spk_dropped,\n"
if ci.count(o) != 1:
    fail("spk_dropped input not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o + "\n   // FIX T suppressed a stale PUSH write at a microphase boundary.\n"
                           "   input        dbg_stale_write,\n", "CI port"))

o = "            error_status[11] <= 1'b1; // spike discarded, per-group FIFO full\n"
if ci.count(o) != 1:
    fail("error_status[11] assignment not found exactly once in %s -- run "
         "detect_spike_drop.py first." % ci_p)
edits.append((ci_p, o,
  o + "        if (dbg_stale_write)\n"
      "            error_status[12] <= 1'b1; // FIX T fired at a microphase boundary\n",
  "CI sticky bit 12"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {iep_p: iep, sc_p: sc, ci_p: ci}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_staleflag"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Read after a run that exercises a microphase boundary (any network above 8192
neurons -- test_max_number_axons[10000] does) with CMD 10, bit 12.
""")
