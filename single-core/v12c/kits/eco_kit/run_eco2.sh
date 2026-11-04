#!/bin/bash
# run_eco2.sh -- crisdsc3: phase 2, the ECO bitstream observing core 2 with v12b's exact placement (about an hour).
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); O=$P/core2_eco2_$(date +%m%d_%H%M)
D=$P/v12b_build/routed.dcp; [ -s $D ] || { echo "STOP: $D missing"; exit 1; }
mkdir -p $O && source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || exit 1
( cd $O && DCP=$D OUT=$O vivado -mode batch -source $K/eco2.tcl -log eco2.log -journal eco2.jou > /dev/null 2>&1 )
grep -E "^ECO " $O/eco2.log | sed 's/^ECO //' | grep -vE "^  probe(2|3|19)\[" | head -60
echo "== mapping: $(grep -cE '^ECO   probe' $O/eco2.log) bits connected"
grep -E "Fully routed|routing errors|unrouted|partially" $O/route_status.txt | head -6
grep -q ECO2_DONE $O/eco2.log && [ -s $O/sixteen_core_noc_v12b_eco2.bit ] && { md5sum $O/sixteen_core_noc_v12b_eco2.bit $O/sixteen_core_noc_v12b_eco2.ltx; echo "ECO2 READY: $O"; } || { echo "STOP: ECO did not finish (see $O/eco2.log)"; grep -E "^ERROR|CRITICAL" $O/eco2.log | head -8; exit 1; }
