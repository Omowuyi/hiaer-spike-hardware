#!/usr/bin/env python3
"""fix_r1b.py [--check] IMPORTS -- R1 in the build top, written for full option B's top: the active core_wrapper instance
(the j < 16 loop) gets its own CORE_ID, so every spike word is tagged with its core.  In simulation R1 is in tb_noc16
(core_wrapper #(.CORE_ID(4'(j)), .NOC_BARRIER(1))); the build top needs it explicitly."""
import sys, os
chk = sys.argv[1] == "--check"; F = os.path.join(sys.argv[-1], "sixteen_core_noc_top.sv"); s = open(F).read()
if "v13 R1" in s: sys.exit("NOT APPLIED: already patched")
a = ("core_wrapper #(.NOC_BARRIER(1)) my_core(\n                    .noc_quiet(noc_quiet),   // v13 B: barrier on in the 16-core design\n"
     "                    .noc_part(noc_part_v[j]), .noc_arrive_par(noc_arrive_par_v[j]), .noc_go0(noc_go0), .noc_go1(noc_go1),   // full B\n"
     "                    .remote_cfg_valid(core_remote_cfg_valid[j]),")
b = ("core_wrapper #(.NOC_BARRIER(1), .CORE_ID(j[3:0])) my_core(   // v13 R1: each core its own CORE_ID (spike-word tag)\n"
     "                    .noc_quiet(noc_quiet),   // v13 B: barrier on in the 16-core design\n"
     "                    .noc_part(noc_part_v[j]), .noc_arrive_par(noc_arrive_par_v[j]), .noc_go0(noc_go0), .noc_go1(noc_go1),   // full B\n"
     "                    .remote_cfg_valid(core_remote_cfg_valid[j]),")
n = s.count(a)
if n != 1: sys.exit("NOT APPLIED: the active core_wrapper instance (B's form) found %d times" % n)
if chk: print("CHECK OK"); sys.exit(0)
open(F + ".before_r1", "w").write(s); open(F, "w").write(s.replace(a, b)); print("R1 applied to", F)
