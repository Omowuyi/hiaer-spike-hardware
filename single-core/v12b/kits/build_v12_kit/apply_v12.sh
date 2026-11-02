#!/bin/bash
# apply_v12.sh [check] -- crisdsc3: put the proven simulation sources (simfix22 = fixes 1-28 + plasticity) into the
# Vivado project, verify every file, add the plasticity modules to the project, and run the elaboration gate.
# Sources: simfix22 = fixes 1-28 + plasticity, gated by round 33.
# 'check' = every verification, nothing changed.  Undo: undo_v12.sh.
P=/data/omowuyi/multicore_noc_exp_psc; I=$P/project/multi_core.srcs/sources_1/imports; K=$(cd "$(dirname "$0")" && pwd)
# S11 = the final sources: simfix22 = fixes 1-28 + plasticity (round 33)
S0=$P/simfix/src; S11=$P/simfix22/src; B=$P/imports_before_v11; O=$P/v12_build; mkdir -p $O
COPY="axon_delay_buffer.v command_interpreter.v delay_buffer.v external_events_processor_simple.v hbm_processor.v internal_events_processor.v noc_spike_router.sv single_core.sv pointer_fifo_controller.v"
TAPPED="hbm_processor.v internal_events_processor.v external_events_processor_simple.v pointer_fifo_controller.v command_interpreter.v single_core.sv"
NEW="stdp_ctrl.v stdp_update_unit.v stdp_elig_unit.v stdp_nstamps.v"
TAPS="dbg_tx_state dbg_rx_state dbg_tx_ptr_ctr dbg_rx_ptr_ctr dbg_wait_clks_cnt dbg_wait_clks_done_cnt dbg_phase dbg_in dbg_fifo dbg_axi dbg_iep_state dbg_iep_timeout dbg_iep_flags dbg_eep_state dbg_eep_flags dbg_pfc_wren dbg_ci_rx_state dbg_ci_tx_state dbg_ci_flags dbg_bram_spiked dbg_uram_spiked dbg_p2done"
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh
export XILINXD_LICENSE_FILE=2100@cadenza.ucsd.edu LM_LICENSE_FILE=2100@cadenza.ucsd.edu
# 0. round 33 must have passed: its gate covers the whole pre-build simulation on simfix22 (fixes 1-28 + plasticity)
L21=/tmp/sim_round33.log
[ -s $L21 ] || stop "$L21 missing: round 33 has not run"
grep -q "ROUND33 GATE: PASS" $L21 || stop "round 33 did not pass (no 'ROUND33 GATE: PASS' in $L21)"
[ "$(grep -c 'fix 21' $S11/internal_events_processor.v)" = 1 ] && [ "$(grep -c 'fix 20' $S11/internal_events_processor.v)" = 11 ] \
    && [ "$(grep -c 'fix 20' $S11/command_interpreter.v)" = 5 ] && [ "$(grep -c 'fix 22' $S11/hbm_processor.v)" = 1 ] \
    && [ "$(grep -c 'fix 23' $S11/internal_events_processor.v)" = 1 ] && [ "$(grep -c 'fix 24' $S11/internal_events_processor.v)" = 1 ] \
    && [ "$(grep -c 'fix 25' $S11/delay_buffer.v)" = 3 ] && [ "$(grep -c 'fix 26' $S11/hbm_processor.v)" = 7 ] \
    && [ "$(grep -c 'fix 26' $S11/pointer_fifo_controller.v)" = 2 ] && [ "$(grep -c 'fix 26' $S11/single_core.sv)" = 9 ] && [ "$(grep -c 'fix 27' $S11/internal_events_processor.v)" = 7 ] \
    && [ "$(grep -c 'fix 27' $S11/single_core.sv)" = 1 ] && [ "$(grep -c 'fix 28' $S11/internal_events_processor.v)" = 2 ] \
    && [ "$(grep -c 'fix 28' $S11/external_events_processor_simple.v)" = 2 ] && [ "$(grep -c 'fix 28' $S11/single_core.sv)" = 3 ] \
    && grep -q "32'hF10A_00FF" $S11/command_interpreter.v || stop "simfix22 is not the round-33 design"
say "0/6 round 33 passed; simfix22 is fixes 1-28 + plasticity"
# 1. the basis (the project as it is now)
SRC=$I; [ -d $B ] && SRC=$B      # after an apply, verify against the saved original
for f in $COPY; do
    if [ $f = hbm_processor.v ]; then
        n=$(diff $SRC/$f $S0/$f | grep -cE '^[<>]'); m=$(diff $SRC/$f $S0/$f | grep '^>' | grep -c 'v10: a CMD 2 read')
        [ "$n" = 6 ] && [ "$m" = 3 ] || stop "$f: project vs simulation base is not exactly fixes 8-9 ($n lines, $m markers)"
    else cmp -s $SRC/$f $S0/$f || stop "$f: project differs from the simulation base"; fi
done
cmp -s $SRC/pointer_fifo_controller.v $S0/pointer_fifo_controller.v || stop "pointer_fifo_controller.v: project differs from the simulation base"
[ "$(grep -c 'fix 26' $S11/pointer_fifo_controller.v)" = 2 ] && [ "$(grep -c 'mark_debug' $S11/pointer_fifo_controller.v)" = 0 ] \
    || stop "pointer_fifo_controller.v: simfix22's is not the fix-26 version without capture taps"
for f in $(ls $S11); do
    case " $COPY $NEW pointer_fifo_controller.v " in *" $f "*) continue;; esac
    [ -f $SRC/$f ] || continue
    cmp -s $SRC/$f $S11/$f || stop "$f: differs between the project and simfix22 but is not one of the files to copy"
done
say "1/6 basis verified: project = simulation base (+ fixes 8-9 for the HBM processor); every other shared file identical"
if [ "$1" = "check" ]; then say "CHECK OK: nothing changed"; exit 0; fi
# 2. apply
[ -d $B ] || { cp -a $I $B && say "   original imports saved in $B"; }
for f in $COPY $NEW; do cp $S11/$f $I/$f || stop "copy $f"; done
cp $B/sixteen_core_noc_top.sv $I/sixteen_core_noc_top.sv || stop "top not restored from $B"   # tie-offs always applied to the original
python3 $K/fix_top.py $I || stop "fix_top.py"
[ -f $P/ila_kit/fix_ila.py ] || stop "$P/ila_kit/fix_ila.py missing"
$K/tap_v12.sh $I $S11 $P/ila_kit/fix_ila.py || stop "capture taps could not be added as simulated file + taps only"
say "2/6 copied $(echo $COPY $NEW | wc -w) files from simfix22 (simulated sources carry no capture taps); taps added by ila_kit/fix_ila.py; top-level tie-offs applied"
# 3. verify the result
for f in $COPY $NEW; do case " $TAPPED " in *" $f "*) continue;; esac; cmp -s $I/$f $S11/$f || stop "$f not identical to simfix22 after the copy"; done
grep -q "unused_switch_slot" $I/sixteen_core_noc_top.sv && grep -q "core_exec_run_tieoff" $I/sixteen_core_noc_top.sv && grep -qE "^    wire        core_exec_run_w     \[15:0\];" $I/sixteen_core_noc_top.sv || stop "top-level tie-offs missing"
for t in $TAPS; do grep -qE "mark_debug.*\b$t\b" $I/*.v $I/*.sv || stop "ILA tap $t missing"; done
for f in $TAPPED; do python3 $K/tapcheck.py $S11/$f $I/$f > /dev/null || stop "$f is not simfix22 plus taps only"; done
say "3/6 project sources = simfix22 (6 files + capture taps only, verified; 7 identical) + top tie-offs; all 22 ILA taps present"
# 4. the four plasticity modules into the Vivado project
cat > $O/add_files.tcl << TCL
open_project $P/project/multi_core.xpr
foreach f {$NEW} {
    set p $I/\$f
    if {[llength [get_files -quiet \$p]] == 0} { add_files -fileset sources_1 -norecurse \$p; puts "added \$f" } else { puts "already in the project: \$f" }
}
update_compile_order -fileset sources_1
foreach f {$NEW} { if {[llength [get_files -quiet $I/\$f]] != 1} { puts "ADD_FAILED \$f"; exit 1 } }
puts "ADD_OK"
close_project
TCL
cd $O && vivado -mode batch -source $O/add_files.tcl -log $O/add_files.log -journal $O/add_files.jou > /dev/null 2>&1
grep -q ADD_OK $O/add_files.log || { grep -E "ERROR|ADD_FAILED" $O/add_files.log | head; stop "adding the plasticity modules failed"; }
grep -E "^(added|already in the project:) stdp_" $O/add_files.log | sed 's/^/   /'
[ "$(grep -cE "^(added|already in the project:) stdp_" $O/add_files.log)" = 4 ] || stop "plasticity modules: expected 4 add/present lines"
say "4/6 plasticity modules in the project: 4 of 4"
# 5. elaboration gate
cat > $O/elab_v12.tcl << TCL
open_project $P/project/multi_core.xpr
synth_design -rtl -top sixteen_core_noc_top -name rtl_v12_check
close_project
TCL
cd $O && vivado -mode batch -source $O/elab_v12.tcl -log $O/elab_v12.log -journal $O/elab_v12.jou > /dev/null 2>&1
e=$(grep -cE "^ERROR" $O/elab_v12.log); md=$(grep -cE "Synth 8-6859|Synth 8-3352|multi-driven|multiple drivers" $O/elab_v12.log)
w=$(grep -c "Synth 8-689" $O/elab_v12.log); u=$(grep -cE "Synth 8-3848|undriven" $O/elab_v12.log)
grep -E "Synth 8-689" $O/elab_v12.log > $O/elab_width_warnings.txt
say "5/6 elaboration: $e errors, $md multi-driven, $w width warnings (v9 baseline 25; list in $O/elab_width_warnings.txt), $u undriven"
[ "$e" = 0 ] && [ "$md" = 0 ] || { grep -E "^ERROR|8-6859|8-3352" $O/elab_v12.log | head; stop "elaboration gate failed"; }
date > $O/APPLIED
say "6/6 READY FOR THE TRIAL: run_v12_build.sh trial"
