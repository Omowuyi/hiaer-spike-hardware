#!/usr/bin/env python3
"""fix_round33.py SRC_DIR -- fix 28: in an input-only microphase the neuron processor pops, while waiting for the input
processor, only the words the input processor consumes as pairs.
Only the neuron processor pops the HBM data FIFO (hbmdataFIFO_out.rden = hbm2iep_rden); it pops in every state but
PHASE1_DONE, and the input processor consumes a pointer pair on each word available while it is in READ_INPUTS.  In an
output microphase the output pairs (consumed in PUSH) separate the input pairs from the synapse words; in an input-only
microphase (fix 27) the synapse words follow the input pairs directly, and the first one was popped in
WAIT_BRAM_PHASE1_DONE after the last pair and discarded (round 32 trace, fan-in 9,000: 52 words popped there -- 51 pairs and
one synapse word -- reads 8,999).  Now, in an input-only microphase, WAIT_BRAM_PHASE1_DONE pops only while the input
processor is in READ_INPUTS; the synapse words stay in the FIFO until POP_PTR_FIFO, as the v10 comment intends.  Output
microphases are unchanged."""
import sys, os
d = sys.argv[1]
def patch(fn, edits, marker="fix 28"):
    F = os.path.join(d, fn); s = open(F).read()
    if marker in s: print("%s: fix 28 already applied" % fn); return
    for a, b in edits:
        if s.count(a) != 1: sys.exit("ANCHOR %s: %d matches for: %s" % (fn, s.count(a), a.strip()[:90]))
        s = s.replace(a, b)
    if not os.path.exists(F + ".before_round33"): open(F + ".before_round33", "w").write(open(F).read())
    open(F, "w").write(s); print("%s: fix 28 applied" % fn)
patch("external_events_processor_simple.v", [
    ("    output        axon_row_valid,\n    output [12:0] curr_bram_waddr\n);\n",
     "    output        axon_row_valid,\n    output [12:0] curr_bram_waddr,\n"
     "    output        reading_inputs     // fix 28: consuming pointer pairs (READ_INPUTS) -- the neuron processor pops for it\n);\n"),
    ("localparam [2:0] STATE_PHASE3_NOC      = 3'd7;  // NEW: Phase 3 - Process NoC relay events\n",
     "localparam [2:0] STATE_PHASE3_NOC      = 3'd7;  // NEW: Phase 3 - Process NoC relay events\n"
     "assign reading_inputs = (curr_state == STATE_READ_INPUTS);   // fix 28\n")])
patch("internal_events_processor.v", [
    ("    input            exec_bram_phase1_done,\n",
     "    input            exec_bram_phase1_done,\n    input            eep_reading_inputs,      // fix 28: the input processor is consuming pointer pairs\n"),
    ("                         (curr_state != STATE_PHASE1_DONE);   // v10: phase-2 data stays in the FIFO until POP_PTR_FIFO\n",
     "                         (curr_state != STATE_PHASE1_DONE) &&   // v10: phase-2 data stays in the FIFO until POP_PTR_FIFO\n"
     "                         !(mp_input_only && curr_state == STATE_WAIT_BRAM_PHASE1_DONE && !eep_reading_inputs);   // fix 28\n")])
patch("single_core.sv", [
    ("    wire       exec_uram_phase1_done;\n", "    wire       exec_uram_phase1_done;\n    wire       w_eep_reading_inputs;   // fix 28\n"),
    ("        .curr_bram_waddr(w_curr_bram_waddr),\n        .axon_row_valid(w_axon_row_valid)\n",
     "        .curr_bram_waddr(w_curr_bram_waddr),\n        .axon_row_valid(w_axon_row_valid),\n        .reading_inputs(w_eep_reading_inputs)   // fix 28\n"),
    ("        .num_inputs(num_inputs),      // fix 27\n",
     "        .num_inputs(num_inputs),      // fix 27\n        .eep_reading_inputs(w_eep_reading_inputs),   // fix 28\n")])
