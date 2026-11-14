#!/usr/bin/env python3
"""fix_33.py [--check] SRC_DIR -- fix 33: Phase 2 keeps each neuron's spike flag (bit 35 of its 36-bit half-word) as read.
In delta mode the Phase-2 accumulation wrote the target neuron's flag as a constant 0.  With one microphase that is harmless (Phase 1
has already consumed every flag), but with two, microphase 0's Phase 2 runs BEFORE microphase 1's Phase 1: an accumulation into a
microphase-1 neuron that fired in this step's Phase 0 erased its flag, so the spike was never seen, reported or delivered.  Observed
directly in round 58b (p1_0_2_4: Phase 0 sets the flag, microphase 0's Phase-2 write 000000004 clears it, microphase 1's Phase 1
finds 0) and on the card in test_DVS_ch=10_conv=2_spikes (C1.9.104, row 512) and _spikes_indepth (C1.9.620, row 545).
The flag now comes from uram_rmwdata_upper/lower[i][35] -- the same read data the accumulation already uses for V."""
import sys, os
chk = sys.argv[1] == "--check"; d = sys.argv[-1]; f = os.path.join(d, "internal_events_processor.v")
s = open(f).read()
if "fix 33" in s: sys.exit("NOT APPLIED: already patched")
E = [
 ("            // DELTA MODE: MP += weight (original, unchanged)\n",
  "            // DELTA MODE: MP += weight (original, unchanged)\n"
  "            // fix 33: the target neuron's spike flag (bit 35) is written back as read, not as 0 (a later microphase's Phase 1 must still see it)\n"),
 ("uram_wdata[i] = {{1'b0, uram_rmwmem_upper[i][34:32], uram_rmwmem_upper[i][31:0]}, uram_rmwdata_lower[i]};",
  "uram_wdata[i] = {{uram_rmwdata_upper[i][35], uram_rmwmem_upper[i][34:32], uram_rmwmem_upper[i][31:0]}, uram_rmwdata_lower[i]};   // fix 33"),
 ("uram_wdata[i] = {{1'b0, uram_rmwmem_upper[i][34:32], uram_rmwmem_upper[i][31:0] + exec_hbm_rdata_reg_signext[i][31:0]}, uram_rmwdata_lower[i]};",
  "uram_wdata[i] = {{uram_rmwdata_upper[i][35], uram_rmwmem_upper[i][34:32], uram_rmwmem_upper[i][31:0] + exec_hbm_rdata_reg_signext[i][31:0]}, uram_rmwdata_lower[i]};   // fix 33"),
 ("uram_wdata[i] = {uram_rmwdata_upper[i], {1'b0, uram_rmwmem_lower[i][34:32], uram_rmwmem_lower[i][31:0]}};",
  "uram_wdata[i] = {uram_rmwdata_upper[i], {uram_rmwdata_lower[i][35], uram_rmwmem_lower[i][34:32], uram_rmwmem_lower[i][31:0]}};   // fix 33"),
 ("uram_wdata[i] = {uram_rmwdata_upper[i], {1'b0, uram_rmwmem_lower[i][34:32], uram_rmwmem_lower[i][31:0] + exec_hbm_rdata_reg_signext[i][31:0]}};",
  "uram_wdata[i] = {uram_rmwdata_upper[i], {uram_rmwdata_lower[i][35], uram_rmwmem_lower[i][34:32], uram_rmwmem_lower[i][31:0] + exec_hbm_rdata_reg_signext[i][31:0]}};   // fix 33")]
for a, b in E:
    n = s.count(a)
    if n != 1: sys.exit("NOT APPLIED: anchor found %d times: %s" % (n, a.strip()[:90]))
    s = s.replace(a, b)
if chk: print("CHECK OK (%s)" % f); sys.exit(0)
open(f + ".before_33", "w").write(open(f).read()); open(f, "w").write(s); print("fix 33 applied to internal_events_processor.v (5 markers)")
