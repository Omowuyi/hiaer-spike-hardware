#!/bin/bash
# make_round34c.sh -- crisdsc3, single-core folder: the v12c gate = round 34's own script (the gate v12b passed) with
# fix 29 added at the end of its fix chain.  No R2.  Written to $P/slice_kit/sim_round34c.sh.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); R34=$P/slice_kit/sim_round34.sh
[ -s $R34 ] || { echo "STOP: $R34 missing"; exit 1; }
cp $K/fix_29.py $P/slice_kit/ || exit 1
python3 - $R34 $P/slice_kit/sim_round34c.sh << 'PY'
import sys
s = open(sys.argv[1]).read()
a = "fix_round31 fix_round33; do python3 $K/$f.py $1 > /dev/null || return 1; done; }"
b = "fix_round31 fix_round33; do python3 $K/$f.py $1 > /dev/null || return 1; done; python3 $K/fix_29.py $1 > /dev/null || return 1; }"
assert s.count(a) == 1, "round 34 fix-chain anchor"
s = s.replace(a, b)
for x, y in (("simfix23w", "simfix34cw"), ("simfix23", "simfix34c"), ("round34_out", "round34c_out"), ("ROUND34 GATE", "ROUND34C GATE"), ("sim_round34", "sim_round34c")):
    s = s.replace(x, y)
assert "fix_r2" not in s, "R2 must not be in the v12c gate"
open(sys.argv[2], "w").write(s); print("sim_round34c.sh written: round 34 + fix 29 (no R2)")
PY
chmod +x $P/slice_kit/sim_round34c.sh && bash -n $P/slice_kit/sim_round34c.sh && echo "ROUND34C SCRIPT READY: $P/slice_kit/sim_round34c.sh"
