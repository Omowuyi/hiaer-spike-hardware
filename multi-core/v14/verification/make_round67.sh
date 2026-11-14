#!/bin/bash
# make_round67.sh FIX_SCRIPT ... -- crisdsc3, multi-core folder: round 67 = round 40's single-core half (slice_kit/sim_round40.sh)
# with the given fix scripts added to its shared fix chain after fix 30 (both single-core snapshots).  Snapshots simfix67/simfix67w,
# output round67_out, verdict ROUND67 GATE.  A fix whose anchors do not match stops the chain with NOT APPLIED.
D=/data/omowuyi/multicore_noc_v13; R40=$D/slice_kit/sim_round40.sh
[ $# -ge 1 ] && [ -s $R40 ] || { echo "STOP: usage make_round67.sh FIX ... (and $R40 must exist)"; exit 1; }
for f in "$@"; do cp "$f" $D/slice_kit/ || exit 1; done
python3 - $R40 $D/slice_kit/sim_round67.sh "$@" << 'PY'
import sys, re, os
s = open(sys.argv[1]).read(); fixes = [os.path.basename(f) for f in sys.argv[3:]]
a = "python3 $K/fix_30.py $1 > /dev/null || return 1; }"
assert s.count(a) == 1, "shared fix chain"
s = s.replace(a, "python3 $K/fix_30.py $1 > /dev/null || return 1; " + " ".join("python3 $K/%s $1 > /dev/null || return 1;" % f for f in fixes) + " }")
s = re.sub(r"\bsimfix40(w?)\b", lambda m: "simfix67" + m.group(1), s)
for x, y in (("round40_out", "round67_out"), ("ROUND40 GATE", "ROUND67 GATE"), ("sim_round40", "sim_round67")): s = s.replace(x, y)
assert not re.search(r"simfix40|round40_out|ROUND40 GATE", s)
open(sys.argv[2], "w").write(s); print("sim_round67.sh written: round 40 + %s in the shared chain" % ", ".join(fixes))
PY
chmod +x $D/slice_kit/sim_round67.sh && bash -n $D/slice_kit/sim_round67.sh && echo "ROUND67 SINGLE-CORE SCRIPT READY"
