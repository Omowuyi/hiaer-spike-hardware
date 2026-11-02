#!/bin/bash
# run_v12_build.sh trial|finish [force] -- crisdsc3: the v12 capture build in two parts (see build_v12.tcl).
# trial (hours): synthesis, ILA, placement, per-SLR utilization and post-placement timing; stops with a placed checkpoint.
# finish (hours): routing from that checkpoint, timing, bitstream + probe file (only if timing is met, unless 'force').
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); O=$P/v12_build
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh
export XILINXD_LICENSE_FILE=2100@cadenza.ucsd.edu LM_LICENSE_FILE=2100@cadenza.ucsd.edu
case "$1" in trial|finish) ;; *) stop "usage: run_v12_build.sh trial|finish [force]";; esac
[ -f $O/APPLIED ] || stop "apply_v12.sh has not completed"
[ "$1" = finish ] && { [ -f $O/placed.dcp ] || stop "no placed checkpoint: run the trial first"; }
say "$1 started (log $O/build_$1.log)"
cd $O && vivado -mode batch -log $O/build_$1.log -journal $O/build_$1.jou -source $K/build_v12.tcl -tclargs $1 $2 > /dev/null 2>&1
grep -E "SYNTH:|taps found|core 1 =|ILA u_ila_c1|POST-PLACEMENT|TRIAL_DONE|WNS:|TIMING|DONE:|BUILD_ABORT" $O/build_report.txt | tail -10
if [ "$1" = trial ] && [ -f $O/place_util_slr.rpt ]; then
    echo "--- per-SLR utilization after placement:"; grep -E "^\| *(SLR|Site Type)|CLB LUTs|Block RAM Tile|URAM|DSPs" $O/place_util_slr.rpt | head -24
fi
if [ "$1" = finish ] && [ -f $O/sixteen_core_noc_v12_ila.bit ]; then
    cp $O/sixteen_core_noc_v12_ila.bit $O/sixteen_core_noc_v12_ila.ltx $P/ && md5sum $P/sixteen_core_noc_v12_ila.bit $P/sixteen_core_noc_v12_ila.ltx
fi
grep -q BUILD_ABORT $O/build_report.txt && tail -1 $O/build_report.txt | grep -q BUILD_ABORT && exit 1
say "$1 finished"
