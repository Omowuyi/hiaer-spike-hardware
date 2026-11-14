#!/usr/bin/env python3
"""patch_hostgap.py TB_NOC16_SV -- slow-host mode (testbench only): with +HOST_GAP_NS=<ns>, every <ns> the host is granted ONE read,
to ONE core, in round-robin order (a polling host that reads one packet at a time, as the card's software does); the packet logger
uses the same grant.  Without the plusarg (host_gap_ns = 0) the read enable and the logger are exactly as before."""
import sys
p = sys.argv[1]; s = open(p).read()
if "slow-host mode" in s: sys.exit("NOT APPLIED: already patched")
E = [("    always @(posedge aclk) host_pause_q <= host_pause;\n",
      "    always @(posedge aclk) host_pause_q <= host_pause;\n"
      "    // slow-host mode (+HOST_GAP_NS): one read grant per gap, to one core, round-robin; off (0) unless given\n"
      "    int host_gap_ns; reg host_strobe = 1'b0, host_strobe_q = 1'b0; reg [3:0] host_rr = 4'd0; reg [15:0] host_grant_q = 16'h0;\n"
      "    initial begin\n"
      "        if (!$value$plusargs(\"HOST_GAP_NS=%d\", host_gap_ns)) host_gap_ns = 0;\n"
      "        if (host_gap_ns > 0) forever begin #(host_gap_ns * 1000); host_strobe = 1'b1; #(host_gap_ns * 500); host_strobe = 1'b0; end\n"
      "    end\n"
      "    always @(posedge aclk) begin\n"
      "        host_strobe_q <= host_strobe;\n"
      "        host_grant_q  <= (host_strobe & ~host_strobe_q) ? (16'h0001 << host_rr) : 16'h0000;\n"
      "        if (host_strobe & ~host_strobe_q) host_rr <= host_rr + 4'd1;\n"
      "    end\n"),
     ("        assign tx.rden = ~tx.empty & ~host_pause_q;\n",
      "        assign tx.rden = ~tx.empty & ~host_pause_q & (host_gap_ns == 0 || host_grant_q[j]);   // slow-host mode\n"),
     ("        always @(negedge aclk) if (rstn && !tx.empty && !host_pause_q) begin\n",
      "        always @(negedge aclk) if (rstn && !tx.empty && !host_pause_q && (host_gap_ns == 0 || host_grant_q[j])) begin   // slow-host mode\n")]
for a, b in E:
    if s.count(a) != 1: sys.exit("NOT APPLIED: anchor found %d times: %s" % (s.count(a), a.strip()[:70]))
    s = s.replace(a, b)
open(p + ".before_hostgap", "w").write(open(p).read()); open(p, "w").write(s); print("slow-host mode inserted into %s" % p)
