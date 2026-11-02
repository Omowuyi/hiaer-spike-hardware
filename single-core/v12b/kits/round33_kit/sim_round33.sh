#!/bin/bash
# sim_round33.sh [preflight] -- crisdsc3: the final pre-build gate for v12 (fixes 1-28 + plasticity).  One run at a time.
#   simfix22  = simfix11 (fixes 1-19 + plasticity) + fixes 20-22 (round 21) + fix 23 (64-bit Phase 2 ends only when every
#               word is consumed) + fix 24 (drain watchdog counts only cycles without progress) + fix 25 (full delay slot
#               refuses entries, error_status bit 18) + fix 26 (HBM Phase 2 ends only after this microphase's pointer
#               production is complete: each producer latched separately, lanes idle; fallback timer, error_status
#               bit 19; FEATURE_WORD 0xF10A_00FF) + fix 27 (the neuron processor takes part in every microphase,
#               input-only ones included) + fix 28 (in an input-only microphase, pops while waiting only the input
#               processor's pointer pairs)
# F0  fail fast: fan-in 9,000 replayed right after the compile must read exactly 9,000
# F   recorded on the card (rec29): fan-in 9,000 (an input-only microphase) reads exactly 9,000 with no status bits;
#     1,100 delayed entries into one slot deliver exactly 1,023 at the delay step and set bit 18
#   simfix22w = simfix22 with fix 17 removed from the neuron processor           -- the watchdog must recover [16384]
# A   regression; readouts; [10000] [16000] [16384]; plasticity (strict); heavy-spike 0/30/60 %; slow host
# R19 isolated firing: 64-bit reports and captures, 32-bit reports -- neuron n exactly at step n+1
# B   nothing affected vs round 21: every replay's content (spikes per step, every membrane read) identical
# C2  watchdog: [16384] without fix 17 completes; CMD 10: feature word 0xf10a00ff, bit 16 set, bits 17-19 clear
# D   64-bit long delay recorded on the v11 card: as recorded (256 entries) and compiler-fixed (16): neurons 0-15 at step 41
# E   fan-out 4000/4096 recorded on the v11 card: N2.0's spike reported exactly at step 2
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); D=$P/sim_core
F11=$P/simfix11; F8=$P/simfix8; O=$P/round33_out; mkdir -p $O
RB=$P/round3b/rec; RB9=$P/round9/rec; R14=$P/round14/rec; R15=$P/round15/rec; R19=$P/round19/rec; R21=$P/round21_out; R22=$P/round22/rec
R2=$P/round2b_kit; K8=$P/round8_kit; K9=$P/round9_kit
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
FAILS=0; bad() { say "   FAIL: $*"; FAILS=$((FAILS+1)); }
# ---------------------------------------------------------------- inputs
[ -d $F11/src ] && [ -d $F11/xsim ] && [ -f $F8/src/internal_events_processor.v ] || stop "simfix11 / simfix8 missing"
[ "$(grep -c 'fix 19' $F11/src/hbm_processor.v)" = 10 ] && [ "$(grep -c 'fix 17' $F11/src/internal_events_processor.v)" = 7 ] || stop "simfix11 is not fixes 1-19"
[ "$(grep -c 'fix 17' $F8/src/internal_events_processor.v)" = 0 ] || stop "simfix8's neuron processor already has fix 17"
for f in $RB/stim_sr10.hex $RB/stim_sr1000.hex $RB/stim_sr4095.hex $RB9/stim_mp10000.hex $RB9/stim_mp16000.hex $RB9/stim_mp16384.hex \
         $R14/stim_plast.hex $R14/protocol.json $R15/stim_heavy.hex $R19/stim_iso64.hex $R19/stim_iso32.hex $R19/iso64.json $R19/iso32.json; do
    [ -s $f ] || stop "$f missing"; done
[ -x $R2/sim_regress.sh ] && [ -f $K8/spike_check2.py ] && [ -f $K9/mpx_check.py ] || stop "round2b/round8/round9 kits missing"
for f in $P/rec29/rec/stim_fanin_9000.hex $P/rec29/rec/stim_delay_overflow.hex $R22/stim_v11_test_syn64_long_delay.hex $R22/stim_v11_test_max_axonal_fanout_4000_.hex $R22/stim_v11_test_max_axonal_fanout_4096_.hex \
         $R21/r_sr10_tx.txt $R21/r_iso64_tx.txt $R21/r_heavy_host_tx.txt; do [ -s $f ] || stop "$f missing (rounds 21, 22)"; done
# ---------------------------------------------------------------- snapshots
mk() {  # mk NAME SRCDIR
    local T=$P/$1; rm -rf $T && mkdir -p $T && cp -r $2 $T/src && find $T/src -name "*.before_*" -delete
    cp -r $F11/xsim $T/xsim && rm -rf $T/xsim/xsim.dir && ( cd $T/xsim && rm -f *.log *.jou *.pb *.wdb *.wcfg *.str webtalk* 2>/dev/null; rm -rf .Xil )
    sed -i "s|$F11/src|$T/src|g" $T/xsim/*.prj
    [ "$(grep -c "$F11/src" $T/xsim/*.prj | awk -F: '{s+=$2} END {print s}')" = 0 ] || stop "$1 still references simfix11 sources"
    cp $D/tb_core_trace.sv $T/tb_core_trace.sv
    for pt in patch_tb_drain.py patch_tb_hostpause.py patch_tb_ptrace.py; do python3 $K/$pt $T/tb_core_trace.sv > /dev/null || stop "$1: $pt"; done
    local REFS=$(grep -lE "tb_core_trace\.sv" $T/xsim/*.prj $T/xsim/*.sh 2>/dev/null); [ -n "$REFS" ] || stop "$1: no testbench reference"
    sed -i -E "s#[^ \"'=]*tb_core_trace\.sv#$T/tb_core_trace.sv#g" $REFS
    [ -z "$(grep -hE "tb_core_trace\.sv" $REFS | grep -v "$T/tb_core_trace.sv")" ] || stop "$1: a reference to the original testbench remains"
    local miss=$(cd $T/xsim && grep -ohE '"[^"]+\.(sv|v|svh|vh|vhd|vhdl)"' *.prj | tr -d '"' | sort -u | while read f; do [ -f "$f" ] || echo "$f"; done)
    [ -z "$miss" ] || { echo "$miss" | head -3; stop "$1: files listed by the project not found"; }
}
fixes() { for f in fix_round17 fix_round20 fix_round21 fix_round24 fix_round25 fix_round26 fix_round29 fix_round31 fix_round33; do python3 $K/$f.py $1 > /dev/null || return 1; done; }
rm -rf $O/src19 $O/src19w && cp -r $F11/src $O/src19 && find $O/src19 -name "*.before_*" -delete && fixes $O/src19 || stop "fixes 20-26 did not apply"
cp -r $F11/src $O/src19w && find $O/src19w -name "*.before_*" -delete && cp $F8/src/internal_events_processor.v $O/src19w/ && fixes $O/src19w || stop "fixes 20-26 did not apply without fix 17"
mk simfix22 $O/src19
mk simfix22w $O/src19w
c() { grep -c "$1" $2; }
S=$P/simfix22/src
[ $(c 'fix 17' $S/internal_events_processor.v) = 7 ] && [ $(c 'fix 19' $S/hbm_processor.v) = 10 ] && [ $(c 'fix 20' $S/internal_events_processor.v) = 11 ] \
  && [ $(c 'fix 20' $S/hbm_processor.v) = 4 ] && [ $(c 'fix 20' $S/command_interpreter.v) = 5 ] && [ $(c 'fix 20' $S/single_core.sv) = 12 ] \
  && [ $(c 'fix 21' $S/internal_events_processor.v) = 1 ] && [ $(c 'fix 22' $S/hbm_processor.v) = 1 ] \
  && [ $(c 'fix 23' $S/internal_events_processor.v) = 1 ] && [ $(c 'fix 24' $S/internal_events_processor.v) = 1 ] \
  && [ $(c 'fix 25' $S/delay_buffer.v) = 3 ] && [ $(c 'fix 25' $S/command_interpreter.v) = 3 ] && [ $(c 'fix 25' $S/single_core.sv) = 3 ] \
  && [ $(c 'fix 26' $S/pointer_fifo_controller.v) = 2 ] && [ $(c 'fix 26' $S/hbm_processor.v) = 7 ] && [ $(c 'fix 26' $S/command_interpreter.v) = 3 ] \
  && [ $(c 'fix 26' $S/single_core.sv) = 9 ] && [ $(c 'fix 27' $S/internal_events_processor.v) = 7 ] && [ $(c 'fix 27' $S/single_core.sv) = 1 ] \
  && [ $(c 'fix 28' $S/internal_events_processor.v) = 2 ] && [ $(c 'fix 28' $S/external_events_processor_simple.v) = 2 ] && [ $(c 'fix 28' $S/single_core.sv) = 3 ] && grep -q "32'hF10A_00FF" $S/command_interpreter.v || stop "simfix22 is not fixes 1-28 + plasticity"
[ $(c 'fix 17' $P/simfix22w/src/internal_events_processor.v) = 0 ] && [ $(c 'fix 20' $P/simfix22w/src/internal_events_processor.v) = 11 ] && [ $(c 'fix 22' $P/simfix22w/src/hbm_processor.v) = 1 ] \
  && [ $(c 'fix 23' $P/simfix22w/src/internal_events_processor.v) = 1 ] && [ $(c 'fix 24' $P/simfix22w/src/internal_events_processor.v) = 1 ] \
  && [ $(c 'fix 25' $P/simfix22w/src/delay_buffer.v) = 3 ] && [ $(c 'fix 26' $P/simfix22w/src/hbm_processor.v) = 7 ] && [ $(c 'fix 27' $P/simfix22w/src/internal_events_processor.v) = 6 ] && [ $(c 'fix 28' $P/simfix22w/src/internal_events_processor.v) = 2 ] || stop "simfix22w is not fixes 20-26 without fix 17"
CORE=$(python3 -c "import json; print(json.load(open('$R14/protocol.json'))['core'])")
python3 $K/patch_stim_stdp.py $R14/stim_plast.hex $O/stim_plast_replay.hex $CORE > /dev/null || stop "plasticity replay copy"
python3 $K/patch_stim_stdp.py $R19/stim_iso64.hex $O/stim_iso64_replay.hex 1 > /dev/null || stop "isolated-64 replay copy"
cp $RB9/stim_mp16384.hex $O/stim_mp16384_cmd10.hex && printf '%s%02x0a\n' "$(printf '00%.0s' $(seq 62))" $(( (CORE & 31) << 3 )) >> $O/stim_mp16384_cmd10.hex
python3 $K/patch_stim_slots.py $R22/stim_v11_test_syn64_long_delay.hex $O/stim_ld_slots.hex 1 > /dev/null || stop "compiler-fixed long-delay copy"
say "snapshots prepared: simfix22 (fixes 1-28), simfix22w (fixes 20-28 without fix 17); stimuli ready"
if [ "$1" = "preflight" ]; then say "PREFLIGHT OK: nothing compiled or simulated"; exit 0; fi
comp() { cd $P/$1/xsim && { ./compile.sh > $O/compile_$1.log 2>&1 && ./elaborate.sh >> $O/compile_$1.log 2>&1; } || { grep -E "ERROR|Error" $O/compile_$1.log | head; stop "$1 compile failed"; }; say "$1 compiled"; }
run() { local S=$1 T=$2 ST=$3; shift 3; cd $P/$S/xsim && xsim tb_core_trace_behav -R -log $O/x_$T.log -testplusarg STIM=$ST -testplusarg OUT=$O/r_$T \
            -testplusarg CLK=0 -testplusarg RLAT=40 -testplusarg INIT_US=150 -testplusarg SEED=1 "$@" > /dev/null 2>&1; }
cnt() { python3 - "$1" << 'PY'
import sys; a = c = 0
for l in open(sys.argv[1] + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); a += (b[63], b[62]) == (0xAB, 0xCD); c += (b[63], b[62]) == (0xCC, 0xCC)
print(a, c)
PY
}
# ================================================================ simfix22
comp simfix22
say "F0 fail fast: fan-in 9,000 (an input-only microphase) must read exactly 9,000 before anything else runs"
run simfix22 fanin0 $P/rec29/rec/stim_fanin_9000.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200
python3 $K/rec29_check.py $O/r_fanin0 fanin | sed "s/^/   /"; python3 $K/rec29_check.py $O/r_fanin0 fanin > /dev/null || { say "ROUND33 GATE: FAIL (fan-in 9000 at F0; nothing else run)"; exit 1; }
say "A1 regression:"; $R2/sim_regress.sh $P/simfix22/xsim > $O/regress.txt 2>&1; grep -E "^== " $O/regress.txt | tail -1
grep -q "23 OK, 0 REGRESSION" $O/regress.txt || bad "regression"
say "A2 readouts, A3 large networks:"
for n in 10 1000 4095; do run simfix22 sr$n $RB/stim_sr$n.hex -testplusarg RGAP=0; python3 $K8/spike_check2.py $O/r_sr$n $n "[$n] p0" pass | tee -a $O/a.txt; done
for n in 10000 16000 16384; do run simfix22 mp$n $RB9/stim_mp$n.hex -testplusarg RGAP=0; done
python3 $K9/mpx_check.py $O/r_mp10000 10000 "[10000]" pass | cut -c1-120 | tee -a $O/a.txt
grep -q "^REGRESSION" $O/a.txt && bad "readouts / [10000]"
python3 - $O/r_mp16000_tx.txt << 'PY' || bad "[16000]"
import sys; vals = []; cur = []; steps = []
for l in open(sys.argv[1]):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
        cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
        if (b[63], b[62]) == (0xAB, 0xCD): steps.append(len(cur)); cur = []
    elif (b[63], b[62]) == (0xCC, 0xCC):
        m = v & 0xFFFFFFFF; vals.append(m - (1 << 32) if m >= 1 << 31 else m)
ok = len(steps) >= 2 and steps[1] == 16000 and len(vals) >= 16000 and all(x == 1 for x in vals[:16000])
print("   [16000]: spikes per step %s, %d membrane reads, first 16000 all 1: %s -> %s" % (steps, len(vals), all(x == 1 for x in vals[:16000]), "PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)
PY
read a cc <<< "$(cnt $O/r_mp16384)"; to=$(grep -c TIMEOUT $O/r_mp16384_log.txt 2>/dev/null)
echo "   [16384]: steps completed $a, membrane reads $cc, timeouts $to"; [ "$a" = 1 ] && [ "$cc" = 1 ] && [ "$to" = 0 ] || bad "[16384]"
say "R19 isolated firing (neuron n exactly at step n+1):"
run simfix22 iso64 $O/stim_iso64_replay.hex -testplusarg RGAP=0 -testplusarg PTRACE=$O/ptrace_iso64.txt
python3 $K/iso_check.py $R19/iso64.json $O/r_iso64 $O/ptrace_iso64.txt | tee $O/iso64.txt | grep -vE "^   step"; grep -q "^PASS" $O/iso64.txt || bad "64-bit isolated firing"
run simfix22 iso32 $R19/stim_iso32.hex -testplusarg RGAP=0
python3 $K/iso_check.py $R19/iso32.json $O/r_iso32 | tee $O/iso32.txt | grep -vE "^   step"; grep -q "^PASS" $O/iso32.txt || bad "32-bit isolated firing"
say "A4 plasticity (strict, 200 us response window, trace on):"
run simfix22 plast $O/stim_plast_replay.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200 -testplusarg PTRACE=$O/ptrace_plast.txt
python3 $K/plast_check.py $O/r_plast $R14/protocol.json $O/stim_plast_replay.hex | tee $O/plast.txt
if ! grep -q "^PASS plasticity-on" $O/plast.txt; then bad "plasticity"; echo "   -- plasticity trace (diagnosis):"; python3 $K/ptrace_report.py $O/ptrace_plast.txt $R14/protocol.json $O/r_plast | sed 's/^/   /'; fi
say "A5 heavy-spike, HBM read-data pauses 0 / 30 / 60 %, and C1 slow host (20 us pause in every 25 us):"
for g in 0 30 60; do run simfix22 heavy_p$g $R15/stim_heavy.hex -testplusarg RGAP=$g; done
python3 $K/heavy_check.py 30 $O/r_heavy_p0 $O/r_heavy_p30 $O/r_heavy_p60 | tail -1 | tee $O/heavy.txt; grep -q "^PASS" $O/heavy.txt || bad "heavy-spike"
run simfix22 heavy_host $R15/stim_heavy.hex -testplusarg RGAP=0 -testplusarg HOST_PAUSE_US=20 -testplusarg HOST_PERIOD_US=25
python3 $K/heavy_check.py 30 $O/r_heavy_p0 $O/r_heavy_host | tail -1 | tee $O/heavy_host.txt; grep -q "^PASS" $O/heavy_host.txt || bad "heavy-spike with a slow host"
say "B nothing affected vs round 21 (content: spikes at every step, every membrane read):"
for t in sr10 sr1000 sr4095 mp10000 mp16000 mp16384 heavy_p0 heavy_p30 heavy_p60 heavy_host iso32 iso64; do
    [ -s $R21/r_${t}_tx.txt ] && { python3 $K/cmp_content.py $O/r_$t $R21/r_$t "$t (vs 21)" || bad "$t content differs from round 21"; } || bad "round 21 has no $t to compare"; done
n20=$(cat $O/x_sr*.log $O/x_mp*.log $O/x_plast.log $O/x_heavy*.log $O/x_iso*.log 2>/dev/null | grep -c "IEP fix 20"); echo "   fix-20 messages in simfix22 logs: $n20"; [ "$n20" = 0 ] || bad "fix 20 fired in normal operation"
# ================================================================ simfix22w
comp simfix22w
say "C2 watchdog: [16384] without fix 17, then CMD 10:"
run simfix22w wd16384 $O/stim_mp16384_cmd10.hex -testplusarg RGAP=0
grep "IEP fix 20" $O/x_wd16384.log | head -3 | sed 's/^/   /'
read a cc <<< "$(cnt $O/r_wd16384)"; echo "   steps completed $a, membrane reads $cc"
grep -q "PUSH_PTR_FIFO watchdog ended microphase 2" $O/x_wd16384.log && [ "$a" -ge 1 ] || bad "the watchdog did not recover [16384]"
python3 $K/face_status27.py $O/r_wd16384 1 0 0 0 | sed 's/^/   /'; python3 $K/face_status27.py $O/r_wd16384 1 0 0 0 > /dev/null || bad "CMD 10 status after the watchdog"
# ================================================================ simfix22: delays and fan-out
say "D 64-bit long delay recorded on the v11 card (A0-A15 -> N1.0-N1.15, delay 40):"
run simfix22 ld_orig $R22/stim_v11_test_syn64_long_delay.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200
python3 $K/ld_check.py $O/r_ld_orig "as recorded (empty slots carry delay 40: 256 entries due at one step)" | sed 's/^/   /'
python3 $K/ld_check.py $O/r_ld_orig x > /dev/null || bad "long delay, as recorded"
run simfix22 ld_slots $O/stim_ld_slots.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200
python3 $K/ld_check.py $O/r_ld_slots "compiler-fixed (16 entries)" | sed 's/^/   /'
python3 $K/ld_check.py $O/r_ld_slots x > /dev/null || bad "long delay, compiler-fixed"
say "S normal operation sets none of status bits 16-19 (no watchdog, bypass, delay-slot overflow or Phase-2 fallback):"
for t in mp10000 mp16000 mp16384 heavy_p0 heavy_p30 heavy_p60 heavy_host; do
    printf '   %-12s ' $t; python3 $K/face_status27.py $O/r_$t 0 0 0 0 | tr '\n' ' '; echo
    python3 $K/face_status27.py $O/r_$t 0 0 0 0 > /dev/null || bad "status bits set in $t"; done
say "F recorded on the card: fan-in 9,000 (an input-only microphase) and 1,100 delayed entries into one slot:"
run simfix22 fanin $P/rec29/rec/stim_fanin_9000.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200
python3 $K/rec29_check.py $O/r_fanin fanin | sed 's/^/   /'; python3 $K/rec29_check.py $O/r_fanin fanin > /dev/null || bad "fan-in 9000"
python3 $K/face_status27.py $O/r_fanin 0 0 0 0 | sed 's/^/   /'; python3 $K/face_status27.py $O/r_fanin 0 0 0 0 > /dev/null || bad "fan-in 9000 status bits"
run simfix22 overflow $P/rec29/rec/stim_delay_overflow.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200
python3 $K/rec29_check.py $O/r_overflow overflow | sed 's/^/   /'; python3 $K/rec29_check.py $O/r_overflow overflow > /dev/null || bad "delay overflow"
python3 $K/face_status27.py $O/r_overflow 0 0 1 0 | sed 's/^/   /'; python3 $K/face_status27.py $O/r_overflow 0 0 1 0 > /dev/null || bad "delay overflow status bits"
say "E fan-out recorded on the v11 card: N2.0's spike reported exactly at step 2:"
for t in 4000 4096; do run simfix22 fo$t $R22/stim_v11_test_max_axonal_fanout_${t}_.hex -testplusarg RGAP=0 -testplusarg DRAIN_US=200
    python3 $K/fo_check.py $O/r_fo$t $t | sed 's/^/   /'; python3 $K/fo_check.py $O/r_fo$t $t > /dev/null || bad "fan-out $t"; done
echo
[ $FAILS = 0 ] && say "ROUND33 GATE: PASS (fixes 1-28 + plasticity; nothing affected; watchdog proven; long delay, fan-out, fan-in 9000 and full delay slot exact; no status bits in normal operation)" || say "ROUND33 GATE: FAIL ($FAILS)"
say "done; outputs in $O"
