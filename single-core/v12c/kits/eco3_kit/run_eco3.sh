#!/bin/bash
# run_eco3.sh -- crisdsc3: ECO 3 on the ECO-2 design (event counters in core 2's HBM-processor clock domain), ~1 hour.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); O=$P/core2_eco3_$(date +%m%d_%H%M)
D=$(ls -td $P/core2_eco2_* | head -1)/eco2_routed.dcp; [ -s $D ] || { echo "STOP: $D missing"; exit 1; }
mkdir -p $O && source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || exit 1
( cd $O && K=$K DCP=$D OUT=$O vivado -mode batch -source $K/eco3.tcl -log eco3.log -journal eco3.jou > /dev/null 2>&1 )
grep -E "^ECO3 " $O/eco3.log | sed 's/^ECO3 //' | grep -vE "^  probe(19|20)\["
echo "== ILA bits connected: $(grep -cE '^ECO3   probe(19|20)\[' $O/eco3.log)"
grep -E "routing errors" $O/route_status3.txt 2>/dev/null
grep -q ECO3_DONE $O/eco3.log && [ -s $O/sixteen_core_noc_v12b_eco3.bit ] && { echo "ECO3 READY: $O"; } || { echo "STOP: ECO 3 did not finish (see $O/eco3.log)"; grep -E "^ERROR" $O/eco3.log | head -6; exit 1; }
