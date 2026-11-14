#!/usr/bin/env python3
"""fix_top.py IMPORTS_DIR -- NoC loose ends in the build top (sixteen_core_noc_top.sv), anchor-checked:
  * core_exec_run_w was declared and never driven; through noc_integration (unpacked port) and cores_with_noc it only
    resets the NoC injectors' statistics counters (noc_spike_injector.sv: count_reg / overflow_reg) -> each element tied
    to 0 in a generate loop; the declaration stays unpacked (round 21 apply: a packed vector failed elaboration)
  * switch slots 16-31 had no core: after_switch[16..31].tready and before_switch[16..31].tvalid/tdata were
    undriven -> no producer is ever valid, and a packet routed to a slot >= 16 (never sent) is drained"""
import sys, os
F = os.path.join(sys.argv[1], "sixteen_core_noc_top.sv"); s = open(F).read()
if "unused_switch_slot" in s: print("already applied"); sys.exit(0)
E = [("    wire        core_exec_run_w     [15:0];\n",
      "    wire        core_exec_run_w     [15:0];\n"
      "    // NoC injector statistics only (noc_integration -> cores_with_noc -> noc_spike_injector.exec_run resets its\n"
      "    // count/overflow registers); was undriven -> tied to 0 element by element (the port is an unpacked array)\n"
      "    genvar cer;\n    generate for (cer = 0; cer < 16; cer = cer + 1) begin : core_exec_run_tieoff\n"
      "        assign core_exec_run_w[cer] = 1'b0;\n    end endgenerate\n"),
     ("/*\n    FIFO_512_ASYNC rx_cdc(",
      ""
      "    // Switch slots 16-31 have no core: no producer is ever valid there, and a packet routed to them (tdest >= 16,\n"
      "    // which the host never sends) is drained rather than stalling switch_1_32.  These nets were undriven.\n"
      "    genvar us;\n    generate\n        for (us = 16; us < 32; us = us + 1) begin : unused_switch_slot\n"
      "            assign after_switch[us].tready  = 1'b1;\n            assign before_switch[us].tvalid = 1'b0;\n"
      "            assign before_switch[us].tdata  = 512'd0;\n        end\n    endgenerate\n/*\n    FIFO_512_ASYNC rx_cdc(")]
for a, b in E:
    if s.count(a) != 1: sys.exit("ANCHOR sixteen_core_noc_top.sv: %d matches for:\n%s" % (s.count(a), a[:120]))
    s = s.replace(a, b)
if not os.path.exists(F + ".before_v11top"): open(F + ".before_v11top", "w").write(open(F).read())
open(F, "w").write(s); print("sixteen_core_noc_top.sv: core_exec_run_w tied off; switch slots 16-31 tied off")
