#!/usr/bin/env python3
"""fix_round17.py SRC_DIR -- fix 20: PUSH_PTR_FIFO watchdog and timeout reporting (anchor-checked, all or nothing).
  * internal_events_processor.v: in PUSH_PTR_FIFO, count only while the HBM receive side has finished this microphase's
    pointer reads (exec_hbm_rx_phase1_done) or the whole step (receive side IDLE, which clears rx_phase1_done -- the
    [16384] case, round 17) and no pair is waiting -- every remaining pair is then already queued, so in normal
    operation the count never passes a few cycles.  Phase 2 then ends on the latched phase-2 done, as normally.  At 4095 the phase ends as the normal exit would, instead of
    hanging (the [16384] hang: delta mode had no timeout at all), and iep_push_wd_fired is set.
    The existing exp-PSC idle-bypass counter no longer counts while fix 14's back-pressure stall is active (it could
    otherwise end Phase 2 while synapse data was still coming); iep_bypass_fired records any bypass exit taken.
    Simulation-only messages when either fires.
  * hbm_processor.v: rx_bp_stall = fix 14's stall condition, rx_idle = receive side in IDLE, as outputs.
  * single_core.sv: rx_bp_stall and rx_idle registered twice into aclk; the new signals wired to the IEP and the interpreter.
  * command_interpreter.v: error_status bit 16 (watchdog ended a phase) and bit 17 (bypass ended a phase), sticky;
    FEATURE_WORD bit 5 says these bits exist (0xF10A_003F).  user_irq still uses bits 9:0 only."""
import sys, os
src = sys.argv[1]
F = {k: os.path.join(src, k) for k in ("internal_events_processor.v", "hbm_processor.v", "single_core.sv", "command_interpreter.v")}
S = {k: open(p).read() for k, p in F.items()}
if any("fix 20" in s for s in S.values()): print("fix 20 already applied"); sys.exit(0)
def rep(k, a, b):
    if S[k].count(a) != 1: sys.exit("ANCHOR %s: %d matches for:\n%s" % (k, S[k].count(a), a[:160]))
    S[k] = S[k].replace(a, b)
I = "internal_events_processor.v"
rep(I, "    output reg       iep_watchdog_error,\n",
       "    output reg       iep_watchdog_error,\n"
       "    input            exec_hbm_rx_phase1_done,   // fix 20: HBM receive side finished this microphase's pointer reads (aclk)\n"
       "    input            hbm_bp_stall,              // fix 20: fix 14's spike back-pressure stall is active (aclk)\n"
       "    input            hbm_rx_idle,               // fix 20: HBM receive side is IDLE (finished the step) (aclk)\n"
       "    output reg       iep_push_wd_fired,         // fix 20: sticky -- the PUSH_PTR_FIFO watchdog ended a phase\n"
       "    output reg       iep_bypass_fired,          // fix 20: sticky -- an exp-PSC idle bypass ended a phase\n")
rep(I, '(* dont_touch = "true" *) reg [10:0] iep_phase1_timeout;\n',
       '(* dont_touch = "true" *) reg [10:0] iep_phase1_timeout;\nreg [11:0] push_wd_ctr;   // fix 20\n')
rep(I, "    else if (!delta_mode && (curr_state == STATE_PUSH_PTR_FIFO || curr_state == STATE_POP_PTR_FIFO) && !exec_hbm_rvalidready)\n",
       "    else if (!delta_mode && (curr_state == STATE_PUSH_PTR_FIFO || curr_state == STATE_POP_PTR_FIFO) && !exec_hbm_rvalidready\n"
       "             && !hbm_bp_stall)   // fix 20: not while fix 14 holds the data back\n")
rep(I, "            end else if (iep_phase1_timeout == 11'd2047) begin\n                // Absolute timeout: 2048 cycles in STATE_PUSH_PTR_FIFO, skip to done\n                next_state <= STATE_PHASE1_DONE;\n            end\n",
       "            end else if (iep_phase1_timeout == 11'd2047) begin\n                // Absolute timeout: 2048 cycles in STATE_PUSH_PTR_FIFO, skip to done\n                next_state <= STATE_PHASE1_DONE;\n"
       "            end else if (push_wd_ctr == 12'hFFF) begin\n                // fix 20: the HBM side is done and 4096 cycles passed with no pair: end the phase instead of hanging\n"
       "                next_state <= STATE_PHASE1_DONE;\n            end\n")
rep(I, "\nendmodule", '''
// fix 20: PUSH_PTR_FIFO watchdog and timeout reporting (see fix_round17.py)
wire iep_bypass_take = (curr_state == STATE_WAIT_BRAM_PHASE1_DONE && !exec_bram_phase1_done && iep_phase1_timeout == 11'd2047)
                    || (curr_state == STATE_PUSH_PTR_FIFO && !exec_hbm_rvalidready && iep_phase1_timeout == 11'd2047)
                    || (curr_state == STATE_POP_PTR_FIFO && !exec_hbm_rvr_p2 && !exec_hbm_rx_phase2_done && iep_phase1_timeout == 11'd2047);
wire iep_push_wd_take = (curr_state == STATE_PUSH_PTR_FIFO) && !exec_hbm_rvalidready && (iep_phase1_timeout != 11'd2047)
                     && (push_wd_ctr == 12'hFFF);
always @(posedge clk) begin
    if (~resetn) begin
        push_wd_ctr <= 12'd0; iep_push_wd_fired <= 1'b0; iep_bypass_fired <= 1'b0;
    end else begin
        if (curr_state == STATE_PUSH_PTR_FIFO && (exec_hbm_rx_phase1_done || hbm_rx_idle) && !exec_hbm_rvalidready)
            push_wd_ctr <= (push_wd_ctr != 12'hFFF) ? push_wd_ctr + 12'd1 : push_wd_ctr;
        else
            push_wd_ctr <= 12'd0;
        if (iep_push_wd_take) iep_push_wd_fired <= 1'b1;
        if (iep_bypass_take)  iep_bypass_fired  <= 1'b1;
    end
end
// synthesis translate_off
always @(posedge clk) if (resetn) begin
    if (iep_push_wd_take) $display("%t IEP fix 20: PUSH_PTR_FIFO watchdog ended microphase %0d's phase 1 (HBM side done, 4096 idle cycles)", $time, microphase_ctr);
    if (iep_bypass_take)  $display("%t IEP fix 20: exp-PSC idle bypass ended a phase (state %0d)", $time, curr_state);
end
// synthesis translate_on
endmodule''')
H = "hbm_processor.v"
rep(H, "    input         syn_64bit_en, // fix 19: 64-bit synapse entries (spike entry: one per 64-bit lane)\n",
       "    input         syn_64bit_en, // fix 19: 64-bit synapse entries (spike entry: one per 64-bit lane)\n"
       "    output        rx_bp_stall,  // fix 20: fix 14's back-pressure stall is active\n"
       "    output        rx_idle,      // fix 20: receive side in IDLE (finished the step)\n")
rep(H, "assign hbm_rready = hbm_rready_r & ~((rx_curr_state == RX_STATE_READ_SYNAPSE_DATA) & spk_any_full);\n",
       "assign hbm_rready = hbm_rready_r & ~((rx_curr_state == RX_STATE_READ_SYNAPSE_DATA) & spk_any_full);\n"
       "assign rx_bp_stall = (rx_curr_state == RX_STATE_READ_SYNAPSE_DATA) & spk_any_full;   // fix 20\n"
       "assign rx_idle     = (rx_curr_state == RX_STATE_IDLE);   // fix 20\n")
C = "single_core.sv"
rep(C, "        .syn_64bit_en(syn_64bit_en_450),   // fix 19\n",
       "        .syn_64bit_en(syn_64bit_en_450),   // fix 19\n        .rx_bp_stall(w_hbm_bp_stall),      // fix 20\n"
       "        .rx_idle(w_hbm_rx_idle),           // fix 20\n")
rep(C, "        syn_64bit_en_450    <= syn_64bit_en_450_s1;\n    end\n",
       "        syn_64bit_en_450    <= syn_64bit_en_450_s1;\n    end\n"
       "    // fix 20: fix 14's back-pressure stall, registered twice into aclk for the neuron processor's timeout counters\n"
       "    wire w_hbm_bp_stall;\n    (* ASYNC_REG = \"TRUE\" *) reg hbm_bp_stall_s1, hbm_bp_stall_s2;\n"
       "    always @(posedge aclk) begin\n        hbm_bp_stall_s1 <= w_hbm_bp_stall;\n        hbm_bp_stall_s2 <= hbm_bp_stall_s1;\n    end\n"
       "    wire w_hbm_rx_idle;   // fix 20: HBM receive side IDLE, registered twice into aclk\n"
       "    (* ASYNC_REG = \"TRUE\" *) reg hbm_rx_idle_s1, hbm_rx_idle_s2;\n"
       "    always @(posedge aclk) begin\n        hbm_rx_idle_s1 <= w_hbm_rx_idle;\n        hbm_rx_idle_s2 <= hbm_rx_idle_s1;\n    end\n"
       "    wire w_iep_push_wd_fired, w_iep_bypass_fired;   // fix 20\n")
rep(C, "        // NEW: Feature ports\n        .iep_watchdog_error(iep_watchdog_error_w),\n",
       "        // NEW: Feature ports\n        .iep_watchdog_error(iep_watchdog_error_w),\n"
       "        .iep_push_wd_fired(w_iep_push_wd_fired),   // fix 20\n        .iep_bypass_fired(w_iep_bypass_fired),     // fix 20\n")
rep(C, "        // NEW: Watchdog outputs \u2192 wired to CI inputs\n        .iep_watchdog_error(iep_watchdog_error_w),\n",
       "        // NEW: Watchdog outputs \u2192 wired to CI inputs\n        .iep_watchdog_error(iep_watchdog_error_w),\n"
       "        .exec_hbm_rx_phase1_done(exec_hbm_rx_phase1_done_FF2_225M),   // fix 20\n        .hbm_bp_stall(hbm_bp_stall_s2),                               // fix 20\n"
       "        .hbm_rx_idle(hbm_rx_idle_s2),                                 // fix 20\n"
       "        .iep_push_wd_fired(w_iep_push_wd_fired),                      // fix 20\n        .iep_bypass_fired(w_iep_bypass_fired),                        // fix 20\n")
K = "command_interpreter.v"
rep(K, "   input        iep_watchdog_error,\n",
       "   input        iep_watchdog_error,\n   input        iep_push_wd_fired,   // fix 20\n   input        iep_bypass_fired,    // fix 20\n")
rep(K, "        if (dbg_mp1_rx)    error_status[15] <= 1'b1;\n",
       "        if (dbg_mp1_rx)    error_status[15] <= 1'b1;\n"
       "        if (iep_push_wd_fired) error_status[16] <= 1'b1;   // fix 20: the PUSH_PTR_FIFO watchdog ended a phase (recovered)\n"
       "        if (iep_bypass_fired)  error_status[17] <= 1'b1;   // fix 20: an exp-PSC idle bypass ended a phase\n")
rep(K, "localparam [31:0] FEATURE_WORD = 32'hF10A_001F;   // bit 4: plasticity (stdp_ctrl, opcodes 19/20)\n",
       "localparam [31:0] FEATURE_WORD = 32'hF10A_003F;   // bit 4: plasticity (stdp_ctrl, opcodes 19/20); bit 5: error_status 16-17 (fix 20)\n")
for k, p in F.items():
    if not os.path.exists(p + ".before_round17"): open(p + ".before_round17", "w").write(open(p).read())
    open(p, "w").write(S[k])
print("fix 20 applied: " + ", ".join(F))
