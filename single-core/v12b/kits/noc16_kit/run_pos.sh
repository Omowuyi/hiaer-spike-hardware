#!/bin/bash
# run_pos.sh NAME STIM REF "POSITIONS" [plusargs...] -- crisdsc3: one recorded single-core stream re-addressed to each
# position and replayed on the 16-core snapshot, every position in its own directory, in parallel.  Each position must
# give round 33's content (cmp_content.py vs REF) and carry its own R1/R2 tags, with no packet from another core.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); T=$P/noc16; O=$P/noc16_out; mkdir -p $O
NAME=$1 STIM=$2 REF=$3 POS=$4; shift 4
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
[ -d $T/xsim/xsim.dir ] || stop "noc16 snapshot not built (mk_noc16.sh)"
[ -s $STIM ] && [ -s ${REF}_tx.txt ] || stop "stimulus or reference missing"
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado settings"
for p in $POS; do
    python3 -c "
import sys
o = open('$O/stim_${NAME}_p$p.hex', 'w')
for l in open('$STIM'):
    h = l.strip()
    if len(h) == 128 and not h.startswith('#'):
        b = bytearray.fromhex(h); b[62] = ($p << 3) | (b[62] & 7); o.write(b.hex() + '\n')
    else: o.write(l)" || stop "re-addressing for position $p"
    R=$O/run_${NAME}_p$p; rm -rf $R && mkdir -p $R && cp -a $T/xsim/xsim.dir $R/ || stop "run directory"
    ( cd $R && timeout -k 30 14400 xsim tb_core_trace_behav -R -log $O/x_${NAME}_p$p.log -testplusarg STIM=$O/stim_${NAME}_p$p.hex \
        -testplusarg OUT=$O/n_${NAME}_p$p -testplusarg CLK=0 -testplusarg RLAT=40 -testplusarg INIT_US=150 -testplusarg SEED=1 "$@" > /dev/null 2>&1 ) &
done
wait
bad=0
for p in $POS; do
    python3 $K/pos_check.py $O/n_${NAME}_p$p $p $O/c_${NAME}_p$p || bad=1
    python3 $K/cmp_content.py $O/c_${NAME}_p$p $REF "$NAME@$p" || bad=1
    grep -E "TIMEOUT" $O/n_${NAME}_p${p}_log.txt | head -2
done
[ $bad = 0 ] && say "POSITIONS $NAME: PASS on $(echo $POS | wc -w) positions" || say "POSITIONS $NAME: FAIL"
