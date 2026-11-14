#!/bin/bash
# gate_v14d.sh FIX_SCRIPT ... -- crisdsc3: the whole simulation gate on snapshot noc16_v14d (v14a + the given fixes; build it first
# with build_v14d.sh).  Runs in parallel: R55b (round 44's one-core CNN vs the exact model), round 40's NoC and equivalence halves,
# round 40's single-core half with fixes 31, 32 and the given fixes (round 60), both position runs, and G14R2 (REACH2 gate, 8 at a
# time).  Logs in /tmp/{r55d,noc67,equiv67,sim_round67,pos67_mp,pos67_sr,r59d,g14r2d,r62d,r63d,r64d}.log; one summary at the end.  Refuses to start if
# any of its outputs exists.
D=/data/omowuyi/multicore_noc_v13; K=$(cd "$(dirname "$0")" && pwd); N=$D/noc16_v14d
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
[ $# -ge 1 ] || stop "usage: gate_v14d.sh FIX_SCRIPT ... (the fixes beyond 31 and 32)"
[ -d $N/xsim/xsim.dir/tb_core_trace_behav ] || stop "build noc16_v14d first (build_v14d.sh)"
for x in round55d_ round67_ round59d_ round62d_ round63d_ round64d_ g14r2_noc16_v14d_; do ls -d $D/${x}*/ > /dev/null 2>&1 && stop "an output already exists: $(ls -d $D/${x}*/ | head -1)"; done
[ -d $D/g14r2_kit ] && [ -d $D/r55_kit ] && [ -d $D/r59_kit ] && [ -s $D/r44_kit/stim_c32_1.hex ] && [ -s $D/r46_kit/stim_c32c_16.hex ] && [ -s $D/r56_kit/stim_r56.hex ] && [ -d $D/noc16_v13slow/xsim/xsim.dir/tb_core_trace_behav ] || stop "a kit, a recording or the noc16_v13slow snapshot is missing"
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado"
# R55b
( O=$D/round55d_$(date +%m%d_%H%M); mkdir -p $O/run && cp -a $N/xsim/xsim.dir $O/run/ && cd $O/run && timeout -k 30 43200 xsim tb_core_trace_behav -R -log $O/x.log \
    -testplusarg STIM=$D/r44_kit/stim_c32_1.hex -testplusarg OUT=$O/n_c32_1 -testplusarg CLK=0 -testplusarg RLAT=40 -testplusarg INIT_US=150 -testplusarg SEED=1 \
    -testplusarg RGAP=0 -testplusarg DRAIN_US=50 > /dev/null 2>&1; python3 $D/r55_kit/vs_model.py $D/r55_kit/plan_c32_1.json $O/n_c32_1 $D/r55_kit/model_c32_1_4steps.json | sed 's/ROUND46/ROUND55D noc16_v14d/' ) > /tmp/r55d.log 2>&1 &
# round 40's NoC and equivalence halves on v14d
for f in run_noc40 run_equiv40; do sed -e 's#T=$D/noc16_v13r40#T=$D/noc16_v14d#' -e 's#round40_#round67_#' $D/r40_kit/$f.sh > $D/r40_kit/${f}_v14d.sh && chmod +x $D/r40_kit/${f}_v14d.sh; done
[ "$(grep -cE 'noc16_v14d|round67_' $D/r40_kit/run_noc40_v14d.sh)" = 2 ] && [ "$(grep -cE 'noc16_v14d|round67_' $D/r40_kit/run_equiv40_v14d.sh)" = 2 ] || stop "r40 script copies"
( cd $D && ./r40_kit/run_noc40_v14d.sh ) > /tmp/noc67.log 2>&1 &
( cd $D && ./r40_kit/run_equiv40_v14d.sh ) > /tmp/equiv67.log 2>&1 &
# round 40's single-core half with fixes 31, 32 and the given fixes
( cd $D && $K/make_round67.sh $K/fix_31.py $K/fix_32.py "$@" && ./slice_kit/sim_round67.sh ) > /tmp/sim_round67.log 2>&1 &
# positions (round 40's commands, snapshot noc16_v14d)
( cd $D && NOC16=$N NOC_OUT=$D/round67_pos_mp ./mc_tests_kit/noc16_kit/run_pos.sh mp10000 $D/round9/rec/stim_mp10000.hex $D/round33_out/r_mp10000 "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15" -testplusarg RGAP=0 ) > /tmp/pos67_mp.log 2>&1 &
( cd $D && NOC16=$N NOC_OUT=$D/round67_pos_sr ./mc_tests_kit/noc16_kit/run_pos.sh sr1000 $D/round3b/rec/stim_sr1000.hex $D/round33_out/r_sr1000 "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15" -testplusarg RGAP=0 ) > /tmp/pos67_sr.log 2>&1 &
# R59 on v14d: Christopher's DVS ch10/conv2 tests (basic and in-depth), his own checks
( O=$D/round59d_$(date +%m%d_%H%M); mkdir -p $O; for n in dvs_basic dvs_indepth; do R=$O/run_$n; mkdir -p $R && cp -a $N/xsim/xsim.dir $R/ && \
    ( cd $R && timeout -k 30 86400 xsim tb_core_trace_behav -R -log $O/x_$n.log -testplusarg STIM=$D/r59_kit/stim_$n.hex -testplusarg OUT=$O/n_$n -testplusarg CLK=0 \
      -testplusarg RLAT=40 -testplusarg INIT_US=150 -testplusarg SEED=1 -testplusarg RGAP=0 -testplusarg DRAIN_US=50 > /dev/null 2>&1; rm -rf $R ) & done; wait
  python3 $D/r59_kit/r59_eval.py basic $D/r59_kit/plan_dvs_basic.json $O/n_dvs_basic $D/r59_kit/outputs_r59.json noc16_v14d
  python3 $D/r59_kit/r59_eval.py indepth $D/r59_kit/plan_dvs_indepth.json $O/n_dvs_indepth $D/r59_kit/outputs_r59.json noc16_v14d ) > /tmp/r59d.log 2>&1 &
xr() { R=$1/run_$2; mkdir -p $R && cp -a $3/xsim/xsim.dir $R/ && ( cd $R && timeout -k 30 86400 xsim tb_core_trace_behav -R -log $1/x_$2.log -testplusarg STIM=$4 -testplusarg OUT=$1/n_$2 \
    -testplusarg CLK=0 -testplusarg RLAT=40 -testplusarg INIT_US=150 -testplusarg SEED=1 -testplusarg RGAP=0 ${5:--testplusarg DRAIN_US=50} > /dev/null 2>&1; rm -rf $R ); }
# R62: round 46's ORIGINAL recording (old compiler: relays land past cores 10-11's input range) must match the exact model (fix 34)
( O=$D/round62d_$(date +%m%d_%H%M); mkdir -p $O; xr $O c32c_16 $N $D/r46_kit/stim_c32c_16.hex; python3 $D/r46_kit/vs_model.py $D/r46_kit/plan_c32c_16.json $O/n_c32c_16 $D/r46_kit/model_c32c_7steps.json | sed "s/ROUND46/ROUND62 noc16_v14d/" ) > /tmp/r62d.log 2>&1 &
# R63: full-load readout: 10,000 neurons (two microphases) all spiking every step, every spike against the exact model
( O=$D/round63d_$(date +%m%d_%H%M); mkdir -p $O; xr $O r63 $N $K/stim_r63.hex; python3 $K/vs_model.py $K/plan_r63.json $O/n_r63 $K/model_r63.json | sed "s/ROUND46/ROUND63 noc16_v14d/" ) > /tmp/r63d.log 2>&1 &
# R64: count packets under a slow polling host (one read per 200 ns, round-robin): v13 must lose some (trigger), v14d none (fix 31)
( O=$D/round64d_$(date +%m%d_%H%M); mkdir -p $O; for s in noc16_v13slow noc16_v14d; do xr $O $s $D/$s $D/r56_kit/stim_r56.hex "-testplusarg HOST_GAP_NS=200 -testplusarg DRAIN_US=2000" & done; wait
  for s in noc16_v13slow noc16_v14d; do echo "  $s steps $(grep -c 'step-done from every executed core' $O/n_${s}_log.txt)"; python3 $D/r56_kit/count_pkts.py $O/n_${s}_tx.txt r64_$s | grep -E "core +[0-7]:|COMPLETE|MISSING"; done ) > /tmp/r64d.log 2>&1 &
# G14R2 on v14d
( cd $D && SNAP=noc16_v14d J=8 ./g14r2_kit/run_g14.sh ) > /tmp/g14r2d.log 2>&1 &
say "started: R55b, round 40 NoC + equivalence + single core, positions mp/sr, R59 (Christopher's tests), R62 (fix 34 without REACH), R63 (full-load readout), R64 (slow host, v13 vs v14d), G14R2 -- all on noc16_v14d"
wait
ok=1
for c in "/tmp/r55d.log:PASS ROUND55D noc16_v14d" "/tmp/noc67.log:ROUND40 NOC: PASS" "/tmp/equiv67.log:ROUND40 EQUIVALENCE: PASS" "/tmp/sim_round67.log:ROUND67 GATE: PASS" \
         "/tmp/r59d.log:PASS R59 dvs_basic noc16_v14d" "/tmp/r59d.log:PASS R59 dvs_indepth noc16_v14d" \
         "/tmp/r62d.log:PASS ROUND62 noc16_v14d" "/tmp/r63d.log:PASS ROUND63 noc16_v14d" "/tmp/r64d.log:COMPLETE r64_noc16_v14d" "/tmp/r64d.log:MISSING r64_noc16_v13slow" \
         "/tmp/pos67_mp.log:POSITIONS mp10000: PASS" "/tmp/pos67_sr.log:POSITIONS sr1000: PASS" "/tmp/g14r2d.log:G14R2 GATE: PASS on noc16_v14d"; do
    f=${c%%:*}; m=${c#*:}; if grep -q "$m" $f; then echo "  PASS  $m"; else echo "  FAIL  $m  (see $f)"; ok=0; fi
done
[ $ok = 1 ] && say "V14D GATE: PASS (every part)" || say "V14D GATE: FAIL"
