#!/usr/bin/env python3
"""fix_r2.py [--check] command_interpreter.v -- v13 R2 (as in v13_dev_kit/rtl/fix_r1r2.py, command-interpreter part):
step-done (ABCD), latency (BABA) and HBM-access (CABA) headers carry the core: byte 61 = 0xC0, byte 60 = core."""
import sys
chk = sys.argv[1] == "--check"; ci = sys.argv[-1]
E = [("txFIFO_din  = {32'hABCD_ABCD, spike_sr, execRun_ctr};",
      "txFIFO_din  = {16'hABCD, 8'hC0, 4'h0, CORE_ID[3:0], spike_sr, execRun_ctr};   // v13 R2: byte 61 0xC0, byte 60 core"),
     ("txFIFO_din  = {32'hBABA_BABA, 448'b0, latency_ctr};",
      "txFIFO_din  = {16'hBABA, 8'hC0, 4'h0, CORE_ID[3:0], 448'b0, latency_ctr};   // v13 R2"),
     ("txFIFO_din  = {32'hCABA_CABA, 448'b0, hbm_access_ctr};",
      "txFIFO_din  = {16'hCABA, 8'hC0, 4'h0, CORE_ID[3:0], 448'b0, hbm_access_ctr};   // v13 R2")]
s = open(ci).read(); bad = [a for a, _ in E if s.count(a) != 1]
if bad: print("ANCHOR missing or repeated:", *bad, sep="\n  "); sys.exit("NOT APPLIED")
if chk: print("CHECK OK"); sys.exit(0)
for a, b in E: s = s.replace(a, b)
open(ci, "w").write(s); print("R2 applied to", ci)
