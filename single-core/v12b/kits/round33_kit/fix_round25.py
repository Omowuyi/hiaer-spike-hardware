#!/usr/bin/env python3
"""fix_round25.py SRC_DIR -- fix 24: the delay-buffer drain watchdog counts only cycles WITHOUT progress.
The drain runs in STATE_PHASE1_DONE at ~9 cycles per entry, bounded by drain_timeout (1023 cycles) so a buffer that never
raises drain_done cannot hang Phase 1.  The bound also cut off every drain longer than ~114 entries: the rest stayed in
the buffer and were delivered one or more steps late (round 24: 256 entries due at one step drained 114 + 114 + 28 over
three steps).  drain_timeout now restarts each time an entry is consumed (dbuf_delayed_ready), so it fires only after
1023 cycles with no entry -- the hang protection stays, and a drain of any length completes in its own step.  32-bit mode
never waits in this state, so it is unaffected."""
import sys, os
F = os.path.join(sys.argv[1], "internal_events_processor.v"); s = open(F).read()
if "fix 24" in s: print("fix 24 already applied"); sys.exit(0)
a = ("        if (curr_state != STATE_PHASE1_DONE) drain_timeout <= 10'd0;\n"
     "        else if (drain_timeout != 10'h3FF)   drain_timeout <= drain_timeout + 1'b1;\n")
if s.count(a) != 1: sys.exit("ANCHOR internal_events_processor.v: %d matches" % s.count(a))
s = s.replace(a, "        if (curr_state != STATE_PHASE1_DONE) drain_timeout <= 10'd0;\n"
                 "        else if (dbuf_delayed_ready)         drain_timeout <= 10'd0;   // fix 24: an entry consumed is progress\n"
                 "        else if (drain_timeout != 10'h3FF)   drain_timeout <= drain_timeout + 1'b1;\n")
if not os.path.exists(F + ".before_round25"): open(F + ".before_round25", "w").write(open(F).read())
open(F, "w").write(s); print("fix 24 applied: drain watchdog restarts on every drained entry")
