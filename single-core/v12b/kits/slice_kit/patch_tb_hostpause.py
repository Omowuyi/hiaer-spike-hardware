#!/usr/bin/env python3
"""patch_tb_hostpause.py TB -- testbench options HOST_PAUSE_US / HOST_PERIOD_US: the host stops reading responses for
HOST_PAUSE_US in every HOST_PERIOD_US (default off: behaviour unchanged).  RGAP pauses the HBM read-data channel only;
this is the slow host that drives fix 14's back-pressure.  The pop (tx.rden) and the recording use the same pause
signal, registered on the rising edge, so a paused head packet is neither popped nor recorded."""
import sys
p = sys.argv[1]; s = open(p).read()
if "HOST_PAUSE_US" in s: print("already patched"); sys.exit(0)
E = [("    assign tx.rden = ~tx.empty;          // drain every response as it appears (FWFT)\n",
      "    // host-pause option: the host stops reading for HOST_PAUSE_US in every HOST_PERIOD_US (default: off)\n"
      "    int host_pause_us, host_period_us; reg host_pause = 1'b0, host_pause_q = 1'b0;\n"
      "    initial begin\n"
      "        if (!$value$plusargs(\"HOST_PAUSE_US=%d\", host_pause_us)) host_pause_us = 0;\n"
      "        if (!$value$plusargs(\"HOST_PERIOD_US=%d\", host_period_us)) host_period_us = 0;\n"
      "        if (host_pause_us > 0 && host_period_us > host_pause_us)\n"
      "            forever begin #((host_period_us - host_pause_us) * 1_000_000); host_pause = 1'b1; #(host_pause_us * 1_000_000); host_pause = 1'b0; end\n"
      "    end\n"
      "    always @(posedge aclk) host_pause_q <= host_pause;\n"
      "    assign tx.rden = ~tx.empty & ~host_pause_q;   // drain every response as it appears (FWFT), except while the host pauses\n"),
     ("    always @(negedge aclk) if (rstn && !tx.empty) begin\n",
      "    always @(negedge aclk) if (rstn && !tx.empty && !host_pause_q) begin   // recorded exactly when popped\n")]
for a, b in E:
    if s.count(a) != 1: sys.exit("ANCHOR %s: %d matches for:\n%s" % (p, s.count(a), a[:100]))
    s = s.replace(a, b)
open(p, "w").write(s); print("testbench: HOST_PAUSE_US / HOST_PERIOD_US (default off)")
