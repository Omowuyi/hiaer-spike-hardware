#!/bin/bash
# run_discover.sh -- crisdsc3: phase 1 of the core-2 observation (read-only).  Writes discover.txt.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); O=$P/core2_eco_$(date +%m%d_%H%M)
D=$P/v12b_build/routed.dcp; [ -s $D ] || { echo "STOP: $D missing"; exit 1; }
mkdir -p $O && source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || exit 1
( cd $O && DCP=$D OUT=$O vivado -mode batch -source $K/discover.tcl -log discover.log -journal discover.jou > /dev/null 2>&1 )
grep -q DISCOVER_DONE $O/discover.log || { echo "STOP: discovery did not finish (see $O/discover.log)"; tail -5 $O/discover.log; exit 1; }
echo "results in $O"; wc -l < $O/discover.txt | sed 's/^/lines: /'; cat $O/discover.txt
