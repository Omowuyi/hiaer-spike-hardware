#!/bin/bash
# apply_slice.sh -- crisdsc3, ONLY if the v12 finish did not close timing and round 34 passed: the new register slice
# (mode 15, 1 crossing, 1 HBM-side stage per channel) into the v12 project, for the v12b build.  Backs up the project's
# slice IP directory and project file first; afterwards the project's simulation wrapper must equal slice15's exactly.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); TS=$(date +%Y%m%d_%H%M)
IPD=$P/project/multi_core.srcs/sources_1/ip/hbm_register_slice; NEW=$P/slice15/hbm_register_slice/sim/hbm_register_slice.v
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
grep -q "ROUND34 GATE: PASS" /tmp/sim_round34.log 2>/dev/null || stop "round 34 has not passed (/tmp/sim_round34.log)"
pgrep -x run_v12_build.s > /dev/null && stop "the v12 build is still running"
[ -s $P/sixteen_core_noc_v12_ila.bit ] && [ "$1" != force ] && stop "v12 closed timing and has its bitstream: the new slice goes into v13, not this project"
[ -s $NEW ] && [ -d $IPD ] || stop "slice15 wrapper or the project's slice IP missing"
B=$P/ip_backup_before_slice15_$TS; mkdir -p $B && cp -a $IPD $B/ && cp -a $P/project/multi_core.xpr $B/ || stop "backup"
say "backed up the project's slice IP and project file to $B"
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado settings"
( cd $B && XPR=$P/project/multi_core.xpr vivado -mode batch -source $K/apply_slice.tcl -log apply.log -journal apply.jou > /dev/null 2>&1 )
grep -E "^(PROJECT|OOC_RUN|APPLY_)" $B/apply.log | sed 's/^/   /'
grep -q "^APPLY_DONE" $B/apply.log || stop "applying the slice failed (see $B/apply.log); restore from $B"
d=$(diff <(grep -E "^\s*\.C_" $IPD/sim/hbm_register_slice.v) <(grep -E "^\s*\.C_" $NEW) | grep -cE "^[<>]")
[ "$d" = 0 ] || stop "the project's regenerated wrapper differs from slice15's in $d parameter lines"
mkdir -p $P/v12b_build && echo "slice15 applied $(date); backup $B" > $P/v12b_build/SLICE_APPLIED
say "APPLIED: the project's slice equals slice15 (mode 15, 1 crossing, 1 HBM-side stage per channel); next: run_v12b_build.sh trial"
