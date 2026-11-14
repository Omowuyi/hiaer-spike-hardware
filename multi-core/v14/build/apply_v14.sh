#!/bin/bash
# apply_v14.sh [check] -- crisdsc3, multi-core folder: put the v14 sources into the Vivado project, as apply_v13 did for v13:
#   reference = noc16_v14d/src = v13's reference (simv13r40 + R2) + fix 31 + fix 32 + fix 33 + fix 34 + fix 35 = exactly what the v14 gate simulated, proven file
#   by file;  basis = the project in its v13 state (verified);  copy in;  core-1 capture taps (each tapped file = reference + taps
#   only);  top = reference top + tie-offs + R1;  verify every file;  plasticity modules present;  elaboration gate.
# 'check' = every verification, nothing changed.  v13-state imports saved once in imports_before_v14.
D=/data/omowuyi/multicore_noc_v13; I=$D/project/multi_core.srcs/sources_1/imports; K=$(cd "$(dirname "$0")" && pwd)
O=$D/v14_build; R=$O/ref; mkdir -p $O; MODE=${1:-apply}
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado"
# 0. the v14 gate must have passed in every part
if [ "${PRECHECK:-0}" = 1 ]; then
    [ "$MODE" = check ] || stop "PRECHECK=1 is only allowed with check (nothing is changed)"
    say "0/6 PRECHECK: gate verdict NOT checked (pre-check only; apply still requires it)"
else
    for c in "/tmp/gate_v14d_final.log:V14D GATE: PASS (every part)"; do
        f=${c%%:*}; m=${c#*:}; grep -q "$m" $f 2>/dev/null || stop "gate not passed: '$m' not found in $f"
    done
fi
say "0/6 v14 gate passed in every part"
# 1. the basis: the project is in its v13 state (v13's reference = simv13r40 + R2, 22 core-1 taps; top = reference top + tie-offs + R1)
B0=$O/basis; rm -rf $B0 && mkdir -p $B0 && cp $D/simv13r40/src/* $B0/ && find $B0 -name "*.before_*" -delete
python3 $K/fix_r2.py $B0/command_interpreter.v > /dev/null && find $B0 -name "*.before_*" -delete || stop "R2 on the basis"
TAPPED="hbm_processor.v internal_events_processor.v external_events_processor_simple.v pointer_fifo_controller.v command_interpreter.v single_core.sv"
X0=$O/basis_top; rm -rf $X0 && mkdir -p $X0 && cp $B0/sixteen_core_noc_top.sv $X0/ && python3 $K/fix_top.py $X0 > /dev/null && python3 $K/fix_r1b.py $X0 > /dev/null || stop "basis top"
for f in $(ls $I | grep -vE "\.before_|\.bak"); do
    [ $f = sixteen_core_noc_top.sv ] && { cmp -s $I/$f $X0/$f || stop "basis: the top is not v13's top + tie-offs + R1"; continue; }
    case " $TAPPED " in *" $f "*) python3 $K/tapcheck.py $B0/$f $I/$f > /dev/null || stop "basis: $f is not v13's file + taps";;
        *) cmp -s $I/$f $B0/$f || stop "basis: $f differs from v13's file";; esac
done
say "1/6 basis verified: the project is v13 (round 40's sources + 22 core-1 taps; top + tie-offs + R1)"
# 2. reference = noc16_v14d/src (what the v14 gate simulated), proven to be v13's reference + fix 31 + fix 32 + fix 33 + fix 34 + fix 35 and nothing else
S14=$D/noc16_v14d/src; [ -d $S14 ] || stop "$S14 missing"
rm -rf $R && mkdir -p $R && cp $S14/* $R/ && find $R -name "*.before_*" -delete
Y=$O/expect_ref; rm -rf $Y && mkdir -p $Y && cp $B0/* $Y/ && python3 $K/fix_31.py $Y > /dev/null && python3 $K/fix_32.py $Y > /dev/null && python3 $K/fix_33.py $Y > /dev/null && python3 $K/fix_34.py $Y > /dev/null && python3 $K/fix_35.py $Y > /dev/null && find $Y -name "*.before_*" -delete || stop "fixes 31-35 on the basis copy"
for f in $(ls $R); do cmp -s $R/$f $Y/$f || stop "$f in noc16_v14d/src is not v13's file + fix 31 + fix 32 + fix 33 + fix 34 + fix 35"; done
for f in $(ls $Y); do [ -f $R/$f ] || stop "$f is missing from noc16_v14d/src"; done
for f in $(ls $I | grep -vE "\.before_|\.bak"); do [ -f $R/$f ] || stop "$f is in the project but not in v14's sources"; done
say "   reference: noc16_v14d/src = v13's sources + fix 31 + fix 32 + fix 33 + fix 34 + fix 35, every file proven"
[ "$MODE" = check ] && { say "CHECK OK: nothing changed"; exit 0; }
# 3. apply
[ -d $D/imports_before_v14 ] || { cp -a $I $D/imports_before_v14 && say "   v13-state imports saved in $D/imports_before_v14"; }
cp $R/* $I/ || stop "copy"
$K/tap_v12.sh $I $R $K/fix_ila.py | tail -1 | grep -q "TAPS OK" || stop "capture taps"
python3 $K/fix_top.py $I > /dev/null || stop "tie-offs"; python3 $K/fix_r1b.py $I > /dev/null || stop "R1"
find $I -name "*.before_*" -delete
say "2/6 v14's sources copied (v13 + fix 31 + fix 32 + fix 33 + fix 34 + fix 35); 22 core-1 taps added; top tie-offs and R1 applied"
# 4. verify
X=$O/expect_top; rm -rf $X && mkdir -p $X && cp $R/sixteen_core_noc_top.sv $X/ && python3 $K/fix_top.py $X > /dev/null && python3 $K/fix_r1b.py $X > /dev/null
cmp -s $X/sixteen_core_noc_top.sv $I/sixteen_core_noc_top.sv || stop "top is not v14's top + tie-offs + R1"
for f in $(ls $I | grep -vE "\.before_|\.bak"); do
    [ $f = sixteen_core_noc_top.sv ] && continue
    case " $TAPPED " in *" $f "*) python3 $K/tapcheck.py $R/$f $I/$f > /dev/null || stop "$f is not v14's file + taps";;
        *) cmp -s $I/$f $R/$f || stop "$f is not v14's file";; esac
done
n=$(grep -h "mark_debug" $I/*.v $I/*.sv | wc -l)
c="full B $(cat $I/*.v $I/*.sv | grep -c 'full B'), fix 30 $(cat $I/*.v $I/*.sv | grep -c 'fix 30'), N5 $(cat $I/*.v $I/*.sv | grep -c 'v13 N5'), B $(cat $I/*.v $I/*.sv | grep -c 'v13 B'), R1 $(grep -c 'v13 R1' $I/sixteen_core_noc_top.sv), R2 $(grep -c 'v13 R2' $I/command_interpreter.v), fix 29 $(grep -c 'fix 29' $I/hbm_processor.v), N4 $(cat $I/noc_integration.sv $I/cores_with_noc.sv | grep -c 'v13 N4'), barrier on in top $(grep -c 'NOC_BARRIER(1)' $I/sixteen_core_noc_top.sv)"
f31=$(grep -c "fix 31" $I/command_interpreter.v); f32=$(cat $I/pointer_fifo_controller.v $I/single_core.sv | grep -c "fix 32")
f33=$(grep -c "fix 33" $I/internal_events_processor.v); f34=$(grep -c "fix 34" $I/single_core.sv); f34p=$(grep -c "fix 34" $I/pointer_fifo_controller.v); f35=$(grep -c "fix 35" $I/single_core.sv)
[ "$f31" = 2 ] && [ "$f32" = 5 ] && [ "$f33" = 5 ] && [ "$f34" = 3 ] && [ "$f34p" = 1 ] && [ "$f35" = 3 ] || stop "fix markers in the project: fix 31 $f31 (expected 2), fix 32 $f32 (expected 5), fix 33 $f33 (expected 5), fix 34 $f34/$f34p (expected 3/1), fix 35 $f35 (expected 3)"
c="$c, fix 31 $f31, fix 32 $f32, fix 33 $f33, fix 34 $f34/$f34p, fix 35 $f35"
say "3/6 every file verified: v14's file (taps only where tapped; top + tie-offs + R1). $c; capture-tap lines $n"
# 5. plasticity modules in the project
grep -c "stdp_" $D/project/multi_core.xpr > /dev/null; np=$(grep -oE "imports/stdp_[a-z_]+\.v" $D/project/multi_core.xpr | sort -u | wc -l)
[ "$np" -ge 4 ] || stop "plasticity modules: $np in the project (expected 4)"
say "4/6 plasticity modules in the project: $np"
# 6. elaboration gate
cat > $O/elab_v14.tcl << TCL
open_project $D/project/multi_core.xpr
synth_design -rtl -top sixteen_core_noc_top -name rtl_v14_check
close_project
TCL
cd $O && vivado -mode batch -source $O/elab_v14.tcl -log $O/elab_v14.log -journal $O/elab_v14.jou > /dev/null 2>&1
e=$(grep -cE "^ERROR" $O/elab_v14.log); md=$(grep -cE "Synth 8-6859|Synth 8-3352|multi-driven|multiple drivers" $O/elab_v14.log)
w=$(grep -c "Synth 8-689" $O/elab_v14.log); u=$(grep -cE "Synth 8-3848|undriven" $O/elab_v14.log)
say "5/6 elaboration: $e errors, $md multi-driven, $w width warnings, $u undriven"
[ "$e" = 0 ] && [ "$md" = 0 ] || { grep -E "^ERROR|8-6859|8-3352" $O/elab_v14.log | head; stop "elaboration gate failed"; }
date > $O/APPLIED
say "6/6 READY FOR THE TRIAL: run_v14_build.sh trial"
