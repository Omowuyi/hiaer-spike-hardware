#!/usr/bin/env python3
"""fix_round26.py SRC_DIR -- fix 25: a full delay slot refuses further entries instead of wrapping, and says so.
Each delay slot's 10-bit write pointer incremented without a bound: on the 1024th entry for one arrival step it wrapped
to 0, the drain took the wrapped count, and the slot's entries were lost (at exactly 1024 the slot read as empty) or
overwritten -- silently.  Now a slot holding 1023 entries refuses more (write_en requires the slot not full), so what it
holds is delivered intact, and every refused entry pulses overflow_evt, which sets error_status bit 18 (sticky, cleared
like the others).  FEATURE_WORD bit 6 (0xF10A_007F) marks the guard and bit 18 as present.  All three modules run on aclk."""
import sys, os
d = sys.argv[1]
def patch(fn, edits, marker):
    F = os.path.join(d, fn); s = open(F).read()
    if marker in s: print("%s: fix 25 already applied" % fn); return
    for a, b in edits:
        if s.count(a) != 1: sys.exit("ANCHOR %s: %d matches for: %s" % (fn, s.count(a), a.strip()[:90]))
        s = s.replace(a, b)
    if not os.path.exists(F + ".before_round26"): open(F + ".before_round26", "w").write(open(F).read())
    open(F, "w").write(s); print("%s: fix 25 applied" % fn)
patch("delay_buffer.v", [
    ("    output wire        drain_done       // all entries from current slot have been drained\n);\n",
     "    output wire        drain_done,      // all entries from current slot have been drained\n"
     "    output wire        overflow_evt     // fix 25: a delayed entry was refused because its slot already held 1023\n);\n"),
    ("    wire       write_en    = syn_valid & ~syn_is_immediate & resetn;\n",
     "    // fix 25: a slot holding 1023 entries refuses more -- the 10-bit pointer must never wrap (the drain takes its count)\n"
     "    wire       slot_full   = (slot_wr_ptr[target_slot] == 10'h3FF);\n"
     "    wire       write_en    = syn_valid & ~syn_is_immediate & resetn & ~slot_full;\n"
     "    assign     overflow_evt = syn_valid & ~syn_is_immediate & resetn & slot_full;   // fix 25\n")], "fix 25")
patch("single_core.sv", [
    ("    wire        w_dbuf_drain_done;\n", "    wire        w_dbuf_drain_done;\n    wire        w_dbuf_overflow;     // fix 25: delay-buffer slot full, entry refused\n"),
    ("        .drain_done(w_dbuf_drain_done)\n    );\n", "        .drain_done(w_dbuf_drain_done),\n        .overflow_evt(w_dbuf_overflow)   // fix 25\n    );\n"),
    ("        .iep_bypass_fired(w_iep_bypass_fired),     // fix 20\n",
     "        .iep_bypass_fired(w_iep_bypass_fired),     // fix 20\n        .dbuf_overflow(w_dbuf_overflow),           // fix 25\n")], "fix 25")
patch("command_interpreter.v", [
    ("   input        iep_bypass_fired,    // fix 20\n",
     "   input        iep_bypass_fired,    // fix 20\n   input        dbuf_overflow,       // fix 25: a delay-buffer slot was full and refused an entry\n"),
    ("        if (iep_bypass_fired)  error_status[17] <= 1'b1;   // fix 20: an exp-PSC idle bypass ended a phase\n",
     "        if (iep_bypass_fired)  error_status[17] <= 1'b1;   // fix 20: an exp-PSC idle bypass ended a phase\n"
     "        if (dbuf_overflow)     error_status[18] <= 1'b1;   // fix 25: a delay slot was full; delayed entries were refused\n"),
    ("localparam [31:0] FEATURE_WORD = 32'hF10A_003F;   // bit 4: plasticity (stdp_ctrl, opcodes 19/20); bit 5: error_status 16-17 (fix 20)\n",
     "localparam [31:0] FEATURE_WORD = 32'hF10A_007F;   // bit 4: plasticity (stdp_ctrl, opcodes 19/20); bit 5: error_status 16-17 (fix 20); bit 6: delay-slot guard, error_status 18 (fix 25)\n")], "fix 25")
