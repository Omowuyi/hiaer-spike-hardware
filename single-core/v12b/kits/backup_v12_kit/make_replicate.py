#!/usr/bin/env python3
"""make_replicate.py BUILD_KIT_DIR BUILD OUT_DIR -- the build's own runner and Tcl, made location-independent for a
restored copy: the tree, the project file and the Vivado settings come from V12_ROOT, V12_XPR and VIVADO_SETTINGS; the
apply-marker checks (meaningful only in the original tree) are removed.  Every edit must land exactly once."""
import sys, os, re
kit, b, out = sys.argv[1:4]
run = open(os.path.join(kit, "run_%s_build.sh" % b)).read(); tcl = open(os.path.join(kit, "build_%s.tcl" % b)).read()
a1 = 'P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); O=$P/%s_build\n' % b
assert run.count(a1) == 1, "runner: location line"
run = run.replace(a1, 'P=${V12_ROOT:?set V12_ROOT to the restored tree}; [ -n "$V12_XPR" ] || { echo "set V12_XPR to the restored .xpr"; exit 1; }\n'
                      'K=$(cd "$(dirname "$0")" && pwd); O=$P/%s_build; mkdir -p $O\n' % b)
a2 = "source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh\n"
assert run.count(a2) == 1, "runner: settings line"
run = run.replace(a2, "source ${VIVADO_SETTINGS:-/data/Xilinx-2024.1/Vivado/2024.1/settings64.sh}   # Vivado 2024.1\n")
n0 = len(run.splitlines()); run = "\n".join(l for l in run.splitlines() if "APPLIED" not in l) + "\n"
removed = n0 - len(run.splitlines())
run = run.replace("build_%s.tcl" % b, "build.tcl")
a3 = "set P   /data/omowuyi/multicore_noc_exp_psc\n"; a4 = "    open_project $P/project/multi_core.xpr\n"
assert tcl.count(a3) == 1 and tcl.count(a4) == 1, "Tcl: location lines"
tcl = tcl.replace(a3, "set P   $::env(V12_ROOT)      ;# replication: the restored tree\n").replace(a4, "    open_project $::env(V12_XPR)   ;# replication: the restored project\n")
assert "/data/omowuyi" not in run + tcl, "a hard-coded path remains"
os.makedirs(out, exist_ok=True)
open(os.path.join(out, "run_build.sh"), "w").write(run); open(os.path.join(out, "build.tcl"), "w").write(tcl)
os.chmod(os.path.join(out, "run_build.sh"), 0o755)
print("replication flow for %s: runner + Tcl location-independent; %d apply-marker check(s) removed" % (b, removed))
