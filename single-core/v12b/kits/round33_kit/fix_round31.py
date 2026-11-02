#!/usr/bin/env python3
"""fix_round31.py SRC_DIR -- fix 27: the neuron processor takes part in every microphase, input-only ones included.
The HBM processor and the input processor run max(output, input) microphases (num_outputs[16:13], num_inputs[16:13]); the
neuron processor ran only the output ones (MICROPHASE_LIMIT = num_outputs[16:13]).  In an input-only microphase it was
idle, popped that microphase's Phase-2 synapse words in IDLE and discarded them (round 30 trace, fan-in 9,000: 808 words of
microphase 1 popped in IDLE; reads 8,192 -- also on the v11 card).  Now:
  MICROPHASE_LIMIT_ALL = max(MICROPHASE_LIMIT, num_inputs[16:13]); PHASE2_DONE ends the step only there
  an input-only microphase (microphase_ctr > MICROPHASE_LIMIT) skips Phase 1 here -- no refill, no PUSH: the HBM side
    reads no output rows for it -- WAIT_BRAM_PHASE1_DONE goes to PHASE1_DONE once the input processor is done (raising
    the Phase-1-done flag the input processor waits on), then Phase 2 accumulates as in any microphase
  Phase-2 accumulation addresses URAM absolutely (dest + phase2_row_offset, which depends only on the mode)
Networks whose inputs do not outnumber their outputs in microphases are unchanged (MICROPHASE_LIMIT_ALL = MICROPHASE_LIMIT)."""
import sys, os
d = sys.argv[1]
def patch(fn, edits, marker="fix 27"):
    F = os.path.join(d, fn); s = open(F).read()
    if marker in s: print("%s: fix 27 already applied" % fn); return
    for e in edits:                       # an edit is (anchor, replacement) or a list of alternatives: exactly one must match
        alts = e if isinstance(e, list) else [e]
        hits = [(a, b) for a, b in alts if s.count(a) == 1]
        if len(hits) != 1 or any(s.count(a) > 1 for a, _ in alts):
            sys.exit("ANCHOR %s: %d of %d known forms match for: %s" % (fn, len(hits), len(alts), alts[0][0].strip()[:90]))
        s = s.replace(hits[0][0], hits[0][1])
    if not os.path.exists(F + ".before_round31"): open(F + ".before_round31", "w").write(open(F).read())
    open(F, "w").write(s); print("%s: fix 27 applied" % fn)
patch("internal_events_processor.v", [
    ("    input [16:0] num_outputs,\n", "    input [16:0] num_outputs,\n    input [16:0] num_inputs,          // fix 27: input microphases (num_inputs[16:13]) the HBM side also runs\n"),
    ("assign uram_microphase_addr_limit = (microphase_ctr==MICROPHASE_LIMIT)?MICROPHASE_MOD:9'd511;\n",
     "assign uram_microphase_addr_limit = (microphase_ctr==MICROPHASE_LIMIT)?MICROPHASE_MOD:9'd511;\n"
     "// fix 27: take part in every microphase the HBM side and the input processor run -- max(output, input) microphases.\n"
     "// An input-only microphase (beyond the output ones) has no Phase 1 here, but its Phase-2 synapse data must be accumulated.\n"
     "wire [3:0] MICROPHASE_LIMIT_INPUTS = num_inputs[16:13];\n"
     "wire [3:0] MICROPHASE_LIMIT_ALL = (MICROPHASE_LIMIT_INPUTS > MICROPHASE_LIMIT) ? MICROPHASE_LIMIT_INPUTS : MICROPHASE_LIMIT;\n"
     "wire       mp_input_only = (microphase_ctr > MICROPHASE_LIMIT);   // fix 27\n"),
    ("        STATE_WAIT_BRAM_PHASE1_DONE: begin\n            if (exec_bram_phase1_done) begin\n                    next_state <= STATE_PUSH_PTR_FIFO;\n"
     "            end else if (iep_phase1_timeout == 11'd2047)\n                next_state <= STATE_PUSH_PTR_FIFO;\n        end\n",
     "        STATE_WAIT_BRAM_PHASE1_DONE: begin   // fix 27: an input-only microphase has no output rows to push\n"
     "            if (exec_bram_phase1_done) begin\n                    next_state <= mp_input_only ? STATE_PHASE1_DONE : STATE_PUSH_PTR_FIFO;\n"
     "            end else if (iep_phase1_timeout == 11'd2047)\n                next_state <= mp_input_only ? STATE_PHASE1_DONE : STATE_PUSH_PTR_FIFO;\n        end\n"),
    [("            if(microphase_ctr == MICROPHASE_LIMIT) next_state <= STATE_IDLE;\n            else begin                                     // fix 17: refill the pipeline at the next microphase's base row\n",
      "            if(microphase_ctr == MICROPHASE_LIMIT_ALL) next_state <= STATE_IDLE;                 // fix 27: every microphase\n"
      "            else if (microphase_ctr >= MICROPHASE_LIMIT) next_state <= STATE_WAIT_BRAM_PHASE1_DONE;   // fix 27: next one input-only\n"
      "            else begin                                     // fix 17: refill the pipeline at the next microphase's base row\n"),
     ("            if(microphase_ctr == MICROPHASE_LIMIT) next_state <= STATE_IDLE;\n            else next_state <= STATE_WAIT_BRAM_PHASE1_DONE;\n",
      "            if(microphase_ctr == MICROPHASE_LIMIT_ALL) next_state <= STATE_IDLE;   // fix 27: every microphase (pre-fix-17 form)\n"
      "            else next_state <= STATE_WAIT_BRAM_PHASE1_DONE;\n")],
    [("        if (microphase_ctr != MICROPHASE_LIMIT) begin\n            microphase_ctr <= microphase_ctr+1'b1;\n",
      "        if (microphase_ctr != MICROPHASE_LIMIT_ALL) begin   // fix 27\n            microphase_ctr <= microphase_ctr+1'b1;\n"),
     ("        if (microphase_ctr != MICROPHASE_LIMIT) microphase_ctr <= microphase_ctr+1'b1;\n",
      "        if (microphase_ctr != MICROPHASE_LIMIT_ALL) microphase_ctr <= microphase_ctr+1'b1;   // fix 27 (pre-fix-17 form)\n")]])
patch("single_core.sv", [
    ("    internal_events_processor iep(\n        .resetn(aresetn),\n        .clk(aclk),\n        .num_outputs(num_outputs),\n",
     "    internal_events_processor iep(\n        .resetn(aresetn),\n        .clk(aclk),\n        .num_outputs(num_outputs),\n        .num_inputs(num_inputs),      // fix 27\n")])
