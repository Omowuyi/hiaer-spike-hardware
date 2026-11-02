#!/usr/bin/env python3
"""fix_round29.py SRC_DIR -- fix 26 (corrected): the HBM processor ends Phase 2 only after this microphase's pointer
production is complete.  Replaces round 27's version, which required both producers' Phase-1-done flags high together
with the lanes empty: round 28's trace shows the input processor dropping its flag one cycle after the neuron processor
finishes (WAIT_IEP_PHASE2), 122 us before the lanes empty, in every microphase but its last -- so that condition never
held, and each such microphase ended by the 262 us fallback ([10000] slow, [16384] past the testbench limit).
  pointer controller (aclk): ptr_lanes_idle = all 16 lane FIFOs empty for 15 consecutive cycles
  single_core: lanes idle and both producers' Phase-1-done flags registered twice into aclk450; the HBM processor's
    fallback toggle registered into aclk as one pulse per toggle
  HBM processor, per microphase (cleared in TX IDLE / PHASE2_DONE): each producer armed on low and latched on high
    separately; out_mp set when TX passes SEND_OUTPUT_READ_COMMANDS (output rows read only when the neuron processor needs
    the microphase; input rows precede them in the data FIFO).  Production complete = (out_mp ? neuron processor latched
    : input processor latched) and lanes idle.  The 255-cycle Phase-2 timer runs only then.  Fallback: 65535 empty-FIFO
    cycles without it end Phase 2 as before and toggle ph2_fallback_tgl
  command interpreter: error_status bit 19 = a Phase 2 ended by the fallback; FEATURE_WORD bit 7 (0xF10A_00FF)"""
import sys, os
d = sys.argv[1]
def patch(fn, edits, marker="fix 26"):
    F = os.path.join(d, fn); s = open(F).read()
    if marker in s: print("%s: fix 26 already applied" % fn); return
    for a, b in edits:
        if s.count(a) != 1: sys.exit("ANCHOR %s: %d matches for: %s" % (fn, s.count(a), a.strip()[:90]))
        s = s.replace(a, b)
    if not os.path.exists(F + ".before_round29"): open(F + ".before_round29", "w").write(open(F).read())
    open(F, "w").write(s); print("%s: fix 26 applied" % fn)
patch("pointer_fifo_controller.v", [
    ("    output reg        ptrFIFO_wren\n);\n",
     "    output reg        ptrFIFO_wren,\n    output wire       ptr_lanes_idle   // fix 26: every lane FIFO empty for 15 cycles\n);\n"),
    ("endmodule",
     "// fix 26: all 16 lane FIFOs empty for 15 consecutive cycles (longer than any empty-flag latency): no pointer remains to\n"
     "// be moved into ptrFIFO.  Producer completion is tracked per microphase by the HBM processor, not here.\n"
     "reg [3:0] lanes_hold;\n"
     "always @(posedge clk) begin\n"
     "    if (~resetn || ~(&ptrs_empty)) lanes_hold <= 4'd0;\n"
     "    else if (lanes_hold != 4'hF)   lanes_hold <= lanes_hold + 4'd1;\n"
     "end\n"
     "assign ptr_lanes_idle = (lanes_hold == 4'hF);\n\nendmodule")])
patch("hbm_processor.v", [
    ("    input        ptrFIFO_empty,\n",
     "    input        ptrFIFO_empty,\n"
     "    input        ptr_lanes_idle,     // fix 26: pointer controller's lanes empty (synchronised)\n"
     "    input        prod_udone,         // fix 26: neuron processor's Phase-1-done flag (synchronised)\n"
     "    input        prod_bdone,         // fix 26: input processor's Phase-1-done flag (synchronised)\n"
     "    output reg   ph2_fallback_tgl,   // fix 26: toggles when a Phase 2 is ended by the fallback timer\n"),
    ("always @(posedge clk) begin\n   if ((tx_curr_state==TX_STATE_POP_POINTER_FIFO) & rx_phase1_done & ptrFIFO_empty)\n      wait_clks_cnt <= wait_clks_cnt + 1'b1;\n",
     "// fix 26: the Phase-2 idle timer may run only once this microphase's pointer production is complete.  Each producer's\n"
     "// completion is latched separately (armed on low, latched on high): the input processor drops its flag again one cycle\n"
     "// after the neuron processor finishes, so the two are never required high together.  A microphase that reads output\n"
     "// rows waits for the neuron processor (input rows precede output rows in the data FIFO); an input-only one for the\n"
     "// input processor.  Then the lanes must be idle.  Fallback: 65535 empty-FIFO cycles without it.\n"
     "reg arm_u, seen_u, arm_b, seen_b, out_mp, fb_done; reg [15:0] fb_cnt;\n"
     "wire prod_seen = out_mp ? seen_u : seen_b;\n"
     "wire prod_complete = prod_seen & ptr_lanes_idle;\n"
     "always @(posedge clk) begin\n"
     "   if (~resetn) begin\n"
     "      arm_u <= 1'b0; seen_u <= 1'b0; arm_b <= 1'b0; seen_b <= 1'b0; out_mp <= 1'b0; fb_done <= 1'b0; fb_cnt <= 16'd0;\n"
     "      ph2_fallback_tgl <= 1'b0;\n"
     "   end else if (tx_curr_state == TX_STATE_IDLE || tx_curr_state == TX_STATE_PHASE2_DONE) begin\n"
     "      arm_u <= 1'b0; seen_u <= 1'b0; arm_b <= 1'b0; seen_b <= 1'b0; out_mp <= 1'b0; fb_done <= 1'b0; fb_cnt <= 16'd0;\n"
     "   end else begin\n"
     "      if (~prod_udone) arm_u <= 1'b1;\n"
     "      if (arm_u & prod_udone) seen_u <= 1'b1;\n"
     "      if (~prod_bdone) arm_b <= 1'b1;\n"
     "      if (arm_b & prod_bdone) seen_b <= 1'b1;\n"
     "      if (tx_curr_state == TX_STATE_SEND_OUTPUT_READ_COMMANDS) out_mp <= 1'b1;\n"
     "      if ((tx_curr_state==TX_STATE_POP_POINTER_FIFO) & rx_phase1_done & ptrFIFO_empty & ~prod_complete & ~fb_done) begin\n"
     "         if (fb_cnt == 16'hFFFF) begin fb_done <= 1'b1; ph2_fallback_tgl <= ~ph2_fallback_tgl; end\n"
     "         else fb_cnt <= fb_cnt + 16'd1;\n"
     "      end else fb_cnt <= 16'd0;\n"
     "   end\n"
     "end\n"
     "wire prod_ok = prod_complete | fb_done;   // fix 26\n\n"
     "always @(posedge clk) begin\n   if ((tx_curr_state==TX_STATE_POP_POINTER_FIFO) & rx_phase1_done & ptrFIFO_empty & prod_ok)   // fix 26: & prod_ok\n      wait_clks_cnt <= wait_clks_cnt + 1'b1;\n")])
patch("single_core.sv", [
    ("    wire w_iep_push_wd_fired, w_iep_bypass_fired;   // fix 20\n",
     "    wire w_iep_push_wd_fired, w_iep_bypass_fired;   // fix 20\n"
     "    // fix 26: lanes idle (pointer controller) and both producers' Phase-1-done flags (aclk) registered twice into aclk450\n"
     "    //         for the HBM processor; its Phase-2 fallback toggle (aclk450) registered into aclk, one pulse per toggle\n"
     "    wire w_ptr_lanes_idle, w_ph2_fb_tgl;\n"
     "    (* ASYNC_REG = \"TRUE\" *) reg lanes_idle_s1, lanes_idle_450, udone_s1, udone_450, bdone_s1, bdone_450;\n"
     "    always @(posedge aclk450) begin\n"
     "        lanes_idle_s1 <= w_ptr_lanes_idle;      lanes_idle_450 <= lanes_idle_s1;\n"
     "        udone_s1      <= exec_uram_phase1_done; udone_450      <= udone_s1;\n"
     "    end\n"
     "    (* ASYNC_REG = \"TRUE\" *) reg ph2_fb_s1, ph2_fb_s2;\n"
     "    reg ph2_fb_s3;\n"
     "    always @(posedge aclk) begin\n"
     "        ph2_fb_s1 <= w_ph2_fb_tgl;\n"
     "        ph2_fb_s2 <= ph2_fb_s1;\n"
     "        ph2_fb_s3 <= ph2_fb_s2;\n"
     "    end\n"
     "    wire w_hbm_ph2_fallback = ph2_fb_s2 ^ ph2_fb_s3;   // fix 26\n"),
    ("        .ptrFIFO_empty(ptrFIFO_out.empty),\n",
     "        .ptrFIFO_empty(ptrFIFO_out.empty),\n        .ptr_lanes_idle(lanes_idle_450),     // fix 26\n"
     "        .prod_udone(udone_450),              // fix 26\n        .prod_bdone(bdone_450),              // fix 26\n"
     "        .ph2_fallback_tgl(w_ph2_fb_tgl),      // fix 26\n"),
    ("        .hbm2pfc_rden(hbm2pfc_rden),\n", "        .hbm2pfc_rden(hbm2pfc_rden),\n        .ptr_lanes_idle(w_ptr_lanes_idle),   // fix 26\n"),
    ("    assign exec_bram_phase1_done = exec_eep_phase1_done;\n",
     "    assign exec_bram_phase1_done = exec_eep_phase1_done;\n"
     "    always @(posedge aclk450) begin   // fix 26: input processor's Phase-1-done flag, registered twice into aclk450\n"
     "        bdone_s1  <= exec_bram_phase1_done;\n"
     "        bdone_450 <= bdone_s1;\n"
     "    end\n"),
    ("        .dbuf_overflow(w_dbuf_overflow),           // fix 25\n",
     "        .dbuf_overflow(w_dbuf_overflow),           // fix 25\n        .hbm_ph2_fallback(w_hbm_ph2_fallback),     // fix 26\n")])
patch("command_interpreter.v", [
    ("   input        dbuf_overflow,       // fix 25: a delay-buffer slot was full and refused an entry\n",
     "   input        dbuf_overflow,       // fix 25: a delay-buffer slot was full and refused an entry\n"
     "   input        hbm_ph2_fallback,    // fix 26: the HBM processor ended a Phase 2 by its fallback timer\n"),
    ("        if (dbuf_overflow)     error_status[18] <= 1'b1;   // fix 25: a delay slot was full; delayed entries were refused\n",
     "        if (dbuf_overflow)     error_status[18] <= 1'b1;   // fix 25: a delay slot was full; delayed entries were refused\n"
     "        if (hbm_ph2_fallback)  error_status[19] <= 1'b1;   // fix 26: a Phase 2 ended by the fallback timer (pointer production not seen)\n"),
    ("localparam [31:0] FEATURE_WORD = 32'hF10A_007F;", "localparam [31:0] FEATURE_WORD = 32'hF10A_00FF;   // bit 7: Phase-2 end waits for pointer production, error_status 19 (fix 26)\n//")])
