#!/usr/bin/env python3
"""
Make dropped spikes VISIBLE.  Detection only -- no behaviour change.

hbm_processor.v silently discards a spike whenever its per-group FIFO is full:

    assign spk0_wren = !spk0_full & exec_hbm_rx_phase1_done
                     & exec_hbm_rvalidready_2x & hbm_rdata[031];

When spk0_full is high the write simply does not happen.  No backpressure, no
counter, no flag -- and error_status only watches spk2ciFIFO, not the eight
per-group FIFOs.  So this particular loss is invisible.

This adds a single OR-reduction of (attempt AND full) across all eight FIFOs,
routes it to the CI, and latches it as sticky error_status bit 11.  It does NOT
change spk*_wren, so no spike behaves any differently than it does today.

WHY DETECTION FIRST, NOT BACKPRESSURE
The ch10conv2 spike loss turned out to be FIX K (the microphase row skip), not
overflow.  There is currently no evidence that these FIFOs ever fill.  Adding
backpressure would change the Phase-1 read handshake on a +21.7 ps timing
margin to fix a problem we have not observed.  Turn the light on first: if
bit 11 never sets across the DVS runs, no further change is needed.

  python3 detect_spike_drop.py --check <hbm_processor.v> <single_core.sv> <command_interpreter.v>
  python3 detect_spike_drop.py         <hbm_processor.v> <single_core.sv> <command_interpreter.v>

Read it back with CMD 10 (0xFACE_FACE response), bit 11.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 3:
    fail("usage: detect_spike_drop.py [--check] <hbm_processor.v> <single_core.sv> "
         "<command_interpreter.v>")
hp_p, sc_p, ci_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

hp = open(hp_p).read()
sc = open(sc_p).read()
ci = open(ci_p).read()
for p, s in ((hp_p, hp), (sc_p, sc), (ci_p, ci)):
    if "spk_dropped" in s:
        fail("%s already mentions spk_dropped -- already patched?" % p)

edits = []

# ---------------- hbm_processor.v ----------------
o = "    output   [3:0]  hbm_curr_state    //To VIO,\n"
if hp.count(o) != 1:
    fail("hbm_curr_state port not found exactly once in %s" % hp_p)
edits.append((hp_p, o,
  "    // High for one cycle whenever a spike was discarded because its\n"
  "    // per-group FIFO was full.  Detection only; spk*_wren is unchanged.\n"
  "    output          spk_dropped,\n"
  "\n" + o, "hbm port"))

o = ("assign spk7_wren = !spk7_full & exec_hbm_rx_phase1_done & "
     "exec_hbm_rvalidready_2x & hbm_rdata[255];\n")
if hp.count(o) != 1:
    fail("spk7_wren assign not found exactly once in %s" % hp_p)
drop = "\n// A spike was produced but its FIFO was full -- it is being discarded.\n"
drop += "wire spk_attempt = exec_hbm_rx_phase1_done & exec_hbm_rvalidready_2x;\n"
drop += "assign spk_dropped =\n"
bits = [31, 63, 95, 127, 159, 191, 223, 255]
terms = ["    (spk_attempt & spk%d_full & hbm_rdata[%03d])" % (i, b)
         for i, b in enumerate(bits)]
drop += " |\n".join(terms) + ";\n"
edits.append((hp_p, o, o + drop, "hbm drop detect"))

# ---------------- single_core.sv ----------------
o = "    wire        w_dbuf_drain_done;\n"
if sc.count(o) != 1:
    fail("w_dbuf_drain_done declaration not found exactly once in %s.\n"
         "       Run wire_syn64.py first." % sc_p)
edits.append((sc_p, o, o + "    wire        w_spk_dropped;   // spike discarded, FIFO full\n",
              "SC wire"))

o = "        .hbm_curr_state(hbm_curr_state)"
if sc.count(o) != 1:
    fail("hbm_processor .hbm_curr_state hookup not found exactly once in %s (%d).\n"
         "       Paste me the hbm_processor instance port list and I'll rebase."
         % (sc_p, sc.count(o)))
edits.append((sc_p, o, "        .spk_dropped(w_spk_dropped),\n" + o, "SC hbm hookup"))

o = "        .syn_64bit_en(w_syn_64bit_en),\n        .delay_table_waddr(w_delay_table_waddr),"
if sc.count(o) != 1:
    fail("CI instance syn_64bit_en/delay_table hookup not found exactly once in %s.\n"
         "       Run wire_syn64.py and enable_axon_delay.py first." % sc_p)
edits.append((sc_p, o,
  "        .syn_64bit_en(w_syn_64bit_en),\n"
  "        .spk_dropped(w_spk_dropped),\n"
  "        .delay_table_waddr(w_delay_table_waddr),", "SC CI hookup"))

# ---------------- command_interpreter.v ----------------
o = "   input        iep_uram_out_of_range,\n"
if ci.count(o) != 1:
    fail("iep_uram_out_of_range input not found exactly once in %s" % ci_p)
edits.append((ci_p, o,
  o + "\n   // A spike was discarded because its per-group FIFO was full.\n"
      "   input        spk_dropped,\n", "CI port"))

o = "            error_status[10] <= 1'b1; // interrupt was asserted (informational)\n"
if ci.count(o) != 1:
    fail("error_status[10] assignment not found exactly once in %s" % ci_p)
edits.append((ci_p, o,
  o + "        if (spk_dropped)\n"
      "            error_status[11] <= 1'b1; // spike discarded, per-group FIFO full\n",
  "CI sticky bit 11"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {hp_p: hp, sc_p: sc, ci_p: ci}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_spkdrop"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Read it after a run with CMD 10 -- bit 11 set means at least one spike was
discarded.  If it never sets across the DVS tests, the FIFOs never fill and
backpressure is not needed.
""")
