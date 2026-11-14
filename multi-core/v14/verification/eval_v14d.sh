#!/bin/bash
# eval_v14d.sh -- crisdsc3: the v14d gate's verdict from every part's own log (no simulation), with exactly the gate's list.
say()  { echo "[$(date +%T)] $*"; }
pgrep -f "gate_v14d.sh|sim_round67.sh" > /dev/null && { say "STOP: the gate or the single-core half is still running"; exit 1; }
ok=1
for c in "/tmp/r55d.log:PASS ROUND55D noc16_v14d" "/tmp/noc67.log:ROUND40 NOC: PASS" "/tmp/equiv67.log:ROUND40 EQUIVALENCE: PASS" "/tmp/sim_round67.log:ROUND67 GATE: PASS" \
         "/tmp/r59d.log:PASS R59 dvs_basic noc16_v14d" "/tmp/r59d.log:PASS R59 dvs_indepth noc16_v14d" \
         "/tmp/r62d.log:PASS ROUND62 noc16_v14d" "/tmp/r63d.log:PASS ROUND63 noc16_v14d" "/tmp/r64d.log:COMPLETE r64_noc16_v14d" "/tmp/r64d.log:MISSING r64_noc16_v13slow" \
         "/tmp/pos67_mp.log:POSITIONS mp10000: PASS" "/tmp/pos67_sr.log:POSITIONS sr1000: PASS" "/tmp/g14r2d.log:G14R2 GATE: PASS on noc16_v14d"; do
    f=${c%%:*}; m=${c#*:}; if grep -q "$m" $f; then echo "  PASS  $m"; else echo "  FAIL  $m  (see $f)"; ok=0; fi
done
[ $ok = 1 ] && say "V14D GATE: PASS (every part)" || say "V14D GATE: FAIL"
