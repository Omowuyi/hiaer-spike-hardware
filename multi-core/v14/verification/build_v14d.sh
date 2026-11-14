#!/bin/bash
# build_v14d.sh -- crisdsc3: (1) snapshot noc16_v14d = noc16_v14a + fix 33 + fix 34 + fix 35 (applied to its own copy of the sources; every
# project path moved to the copy and checked) + the slow-host testbench mode; (2) snapshot noc16_v13slow = noc16_v13r40 (the v13 design)
# is not rebuilt: noc16_v13slow (v13 + slow-host mode only, built for the previous gate) is reused.  Refuses if noc16_v14d exists.
D=/data/omowuyi/multicore_noc_v13; K=$(cd "$(dirname "$0")" && pwd); A=$D/noc16_v14a; N=$D/noc16_v14d; T=$D/noc16_v13r40; H=$D/noc16_v13slow
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
[ -d $A/xsim/xsim.dir/tb_core_trace_behav ] && grep -q "fix 32" $A/src/pointer_fifo_controller.v || stop "$A is not the v14a snapshot"
[ -d $T/xsim/xsim.dir/tb_core_trace_behav ] && grep -q "fix 30" $T/src/single_core.sv || stop "$T is not round 40's snapshot"
[ -e $N ] && stop "$N already exists (nothing done)"; [ -d $H/xsim/xsim.dir/tb_core_trace_behav ] || stop "$H (the v13 slow-host snapshot built for the previous gate) is missing"
python3 $K/fix_33.py --check $A/src > /dev/null && python3 $K/fix_34.py --check $A/src > /dev/null && python3 $K/fix_35.py --check $A/src > /dev/null || stop "fix 33 / fix 34 do not apply to the v14a sources"
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado"
build() { cd $1/xsim && bash compile.sh > $1/compile_$2.log 2>&1 && bash elaborate.sh > $1/elaborate_$2.log 2>&1 || stop "$2: compile/elaborate failed (see $1)"
          grep -qiE "^ERROR" $1/compile_$2.log $1/elaborate_$2.log && stop "$2: errors (see $1)"; [ -d $1/xsim/xsim.dir/tb_core_trace_behav ] || stop "$2: snapshot missing"; }
cp -a $A $N || stop "copy v14a"
python3 $K/fix_33.py $N/src && python3 $K/fix_34.py $N/src && python3 $K/fix_35.py $N/src || stop "fixes 33/34"; find $N/src -name "*.before_*" -delete
python3 $K/patch_hostgap.py $N/tb_noc16.sv || stop "slow-host mode (v14d)"
[ "$(grep -c 'fix 33' $N/src/internal_events_processor.v)" = 5 ] && [ "$(grep -c 'fix 34' $N/src/single_core.sv)" = 3 ] && [ "$(grep -c 'fix 34' $N/src/pointer_fifo_controller.v)" = 1 ] && [ "$(grep -c 'fix 35' $N/src/single_core.sv)" = 3 ] || stop "fix markers"
for P in $N/xsim/tb_core_trace_vlog.prj $N/xsim/tb_core_trace_vhdl.prj; do n=$(grep -c "$A/" $P); sed -i "s#$A/#$N/#g" $P
    [ "$(grep -c "$A/" $P)" = 0 ] && [ "$(grep -c "$N/" $P)" = "$n" ] || stop "project file $P: paths not moved cleanly"; done
build $N v14d; say "SNAPSHOT noc16_v14d READY: v14a + fix 33 + fix 34 + fix 35 (+ slow-host testbench mode)"
