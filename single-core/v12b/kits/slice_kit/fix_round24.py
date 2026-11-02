#!/usr/bin/env python3
"""fix_round24.py SRC_DIR -- fix 23: Phase 2 ends only when it has actually consumed every word.
STATE_POP_PTR_FIFO left for PHASE2_DONE when no word was accepted this cycle and the HBM side had finished reading.  In
64-bit mode word acceptance is stalled for 8 cycles while each word's lanes are scanned for delayed entries, so the HBM
side finishes long before the neuron processor has consumed the FIFO, and the first stall cycle after that ended Phase 2:
the remaining words were abandoned (round 23 trace: 9 of 32 words scanned; 64-bit long-delay test, card and simulation),
and later popped as if they belonged to the next phase.  The exit now also requires the HBM data FIFO empty and no lane
scan in flight.  In 32-bit mode (no stall) a cycle without an accepted word already means the FIFO is empty, so the
condition is unchanged there."""
import sys, os
F = os.path.join(sys.argv[1], "internal_events_processor.v"); s = open(F).read()
if "fix 23" in s: print("fix 23 already applied"); sys.exit(0)
a = ("        STATE_POP_PTR_FIFO: begin\n            if (exec_hbm_rvr_p2) begin   // FIX G\n                uram_rden <= 1'b1;\n            end\n"
     "            else if (exec_hbm_rx_phase2_done)\n                next_state <= STATE_PHASE2_DONE;\n")
if s.count(a) != 1: sys.exit("ANCHOR internal_events_processor.v: %d matches" % s.count(a))
b = a.replace("            else if (exec_hbm_rx_phase2_done)\n",
              "            else if (exec_hbm_rx_phase2_done && !exec_hbm_rvalidready && !(syn_64bit_en && dbuf_phase2_active))   // fix 23\n")
s = s.replace(a, b)
if not os.path.exists(F + ".before_round24"): open(F + ".before_round24", "w").write(open(F).read())
open(F, "w").write(s); print("fix 23 applied: Phase 2 ends only with the HBM side done, the FIFO empty and no scan in flight")
