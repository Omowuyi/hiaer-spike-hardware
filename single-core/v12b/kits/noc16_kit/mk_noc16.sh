#!/bin/bash
# mk_noc16.sh -- crisdsc3: the 16-core snapshot "noc16": simfix22's sources (fixes 1-28) + R2 in the command interpreter
# + the eight NoC sources + tb_noc16.sv (16 cores with their own CORE_ID = R1, noc_integration as the build wires it).
# SLICE=old (default: today's register slice, as round 33) or SLICE=new (slice15: mode 15 + HBM-side stage).
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); F=$P/simfix22; T=$P/noc16; SLICE=${SLICE:-old}
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
[ -d $F/src ] && [ -d $F/xsim ] && [ -f $F/tb_core_trace.sv ] || stop "simfix22 (sources, xsim, tb_core_trace.sv) missing"
NOC="noc_pkg.sv noc_arbiter.sv noc_spike_router.sv noc_spike_injector.sv noc_l1_bus.sv noc_l2_bus.sv cores_with_noc.sv noc_integration.sv"
rm -rf $T && mkdir -p $T && cp -r $F/src $T/src && find $T/src -name "*.before_*" -delete && cp $F/tb_core_trace.sv $K/tb_noc16.sv $T/ || stop "copy"
for f in $NOC; do [ -f $T/src/$f ] || stop "$f missing from simfix22/src"; done
python3 $K/fix_r2.py $T/src/command_interpreter.v > /dev/null || stop "R2 did not apply"
[ "$(grep -c 'v13 R2' $T/src/command_interpreter.v)" = 3 ] || stop "R2: expected 3 tagged headers"
cp -r $F/xsim $T/xsim && rm -rf $T/xsim/xsim.dir && ( cd $T/xsim && rm -f *.log *.jou *.pb *.wdb *.str webtalk* 2>/dev/null; rm -rf .Xil )
V=$(ls $T/xsim/*vlog.prj | head -1); [ -f "$V" ] || stop "no verilog project file"
sed -i "s|$F/src|$T/src|g; s|$F/tb_core_trace.sv|$T/tb_core_trace.sv|g" $T/xsim/*.prj
[ "$(cat $T/xsim/*.prj | grep -c "$F/")" = 0 ] || stop "project files still reference simfix22"
L1="sv xil_defaultlib $(for f in $NOC; do printf '"%s" ' $T/src/$f; done)"
sed -i "1i $L1" $V && echo "sv xil_defaultlib \"$T/tb_noc16.sv\"" >> $V
for f in $NOC tb_noc16.sv; do [ "$(grep -c "/$f\"" $V)" = 1 ] || stop "$f is not in the project file exactly once"; done
[ "$(grep -c 'xil_defaultlib\.tb_core_trace ' $T/xsim/elaborate.sh)" = 2 ] || stop "elaborate.sh: expected the top twice"
sed -i 's/xil_defaultlib\.tb_core_trace /xil_defaultlib.tb_noc16 /g' $T/xsim/elaborate.sh
if [ "$SLICE" = new ]; then
    O=$P/project/multi_core.srcs/sources_1/ip/hbm_register_slice/sim/hbm_register_slice.v; N=$P/slice15/hbm_register_slice/sim/hbm_register_slice.v
    [ -s $N ] && [ "$(cat $T/xsim/*.prj | grep -c "$O")" = 1 ] || stop "slice substitution impossible"
    sed -i "s|$O|$N|" $T/xsim/*.prj
fi
miss=$(cd $T/xsim && grep -ohE '"[^"]+\.(sv|v|svh|vh|vhd|vhdl)"' *.prj | tr -d '"' | sort -u | while read f; do [ -f "$f" ] || echo "$f"; done)
[ -z "$miss" ] || stop "missing files: $miss"
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado settings"
say "compiling and elaborating noc16 (16 cores; slice $SLICE)"
( cd $T/xsim && ./compile.sh > ../compile.log 2>&1 && ./elaborate.sh >> ../compile.log 2>&1 ) || { grep -E "ERROR|Error" $T/compile.log | head -12; stop "noc16 compile/elaborate failed (see $T/compile.log)"; }
say "NOC16 READY: $(grep -cE '^WARNING' $T/compile.log) warnings; snapshot $T/xsim (top tb_noc16)"
