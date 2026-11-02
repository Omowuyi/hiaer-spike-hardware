#!/usr/bin/env python3
"""patch_tb_ptrace.py TB -- plasticity trace monitor in a COPY of the testbench (design untouched), active only with
+PTRACE=<file>.  Logs on the core clock: step ticks; every axon and neuron capture the plasticity controller receives
(row, mask; same valid conditions as its inputs); Phase-4 start (with the controller's stored capture counts) and end;
rewards; every HBM request the controller issues and every response it takes."""
import sys
p = sys.argv[1]; s = open(p).read()
if "round 18 plasticity trace" in s: print("already patched"); sys.exit(0)
i = s.index("module tb_core_trace"); j = s.index("\nendmodule", i)
mon = r'''
    // ---- round 18 plasticity trace monitor (testbench only) ----
    integer ptf = 0; string ptname;
    initial if ($value$plusargs("PTRACE=%s", ptname)) ptf = $fopen(ptname, "w");
    always @(posedge aclk) if (ptf != 0) begin
        if (dut.inst.exec_run) $fdisplay(ptf, "%0t STEP", $time);
        if (dut.inst.w_stdp_enable && dut.inst.w_stdp_cap_valid)
            $fdisplay(ptf, "%0t NCAP row=%0d mask=%h", $time, dut.inst.w_stdp_cap_row, dut.inst.w_stdp_cap_mask);
        if (dut.inst.w_stdp_enable && dut.inst.w_axon_row_valid && (|dut.inst.exec_eep_spiked))
            $fdisplay(ptf, "%0t ACAP row=%0d mask=%h", $time, dut.inst.w_curr_bram_waddr, dut.inst.exec_eep_spiked);
        if (dut.inst.w_plast_p4_start) $fdisplay(ptf, "%0t P4START ncount=%0d acount=%0d", $time, dut.inst.u_plast.ncount, dut.inst.u_plast.acount);
        if (dut.inst.w_plast_p4_done)  $fdisplay(ptf, "%0t P4DONE", $time);
        if (dut.inst.w_plast_reward_req) $fdisplay(ptf, "%0t REWARD R=%0d", $time, $signed(dut.inst.w_plast_reward_R));
        if (dut.inst.u_plast.hreq_valid && dut.inst.u_plast.hreq_ready)
            $fdisplay(ptf, "%0t HREQ we=%0d addr=%0d data=%h", $time, dut.inst.u_plast.hreq_we, dut.inst.u_plast.hreq_addr, dut.inst.u_plast.hreq_wdata);
        if (dut.inst.u_plast.hrsp_valid && dut.inst.u_plast.hrsp_ready)
            $fdisplay(ptf, "%0t HRSP data=%h", $time, dut.inst.u_plast.hrsp_rdata);
    end
'''
open(p, "w").write(s[:j] + "\n" + mon + s[j:]); print("plasticity trace monitor added to %s" % p)
