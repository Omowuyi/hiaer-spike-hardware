#!/bin/bash
# regen_slice.sh -- crisdsc3: the register slice regenerated OUTSIDE the project (the v12 project is only read).
# Output: /data/omowuyi/multicore_noc_exp_psc/slice15/hbm_register_slice/ (IP outputs; sim/hbm_register_slice.v is what
# sim_round34.sh compiles).  Checks the regenerated wrapper's parameters and lists every parameter line that changed.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); S=$P/slice15/hbm_register_slice
X=$P/project/multi_core.srcs/sources_1/ip/hbm_register_slice/hbm_register_slice.xci
OLD=$P/project/multi_core.srcs/sources_1/ip/hbm_register_slice/sim/hbm_register_slice.v
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
[ -f $X ] && [ -f $OLD ] || stop "project slice IP (xci or sim wrapper) missing"
PART=$(grep -oE 'Name="Part" Val="[^"]+"' $P/project/multi_core.xpr | head -1 | sed -E 's/.*Val="([^"]+)"/\1/')
[ -n "$PART" ] || stop "no part in the project file"
rm -rf $P/slice15 && mkdir -p $S && cp $X $S/ || stop "copy"
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh || stop "Vivado settings"
say "regenerating the slice (part $PART) in $S"
( cd $P/slice15 && SLICE_DIR=$S PART=$PART vivado -mode batch -source $K/regen_slice.tcl -log regen.log -journal regen.jou > /dev/null 2>&1 )
grep -E "^(BEFORE|AFTER|SLICE_)" $P/slice15/regen.log | sed 's/^/   /'
grep -q "^SLICE_REGEN_DONE" $P/slice15/regen.log || stop "regeneration failed (see $P/slice15/regen.log)"
W=$S/sim/hbm_register_slice.v; [ -s $W ] || stop "no regenerated simulation wrapper"
ok=1; chk() { grep -qE "\.$1 *\( *$2 *\)" $W || { say "   wrapper: $1 is not $2"; ok=0; }; }
for c in AW AR W R B; do chk C_REG_CONFIG_$c 15; chk C_PIPELINES_SLAVE_$c 1; chk C_PIPELINES_MASTER_$c 0; done; chk C_NUM_SLR_CROSSINGS 1
[ $ok = 1 ] || stop "regenerated wrapper does not carry the intended configuration"
say "parameter lines changed in the simulation wrapper (today < > regenerated):"
diff <(grep -E "^\s*\.C_" $OLD) <(grep -E "^\s*\.C_" $W) | grep -E "^[<>]" | sed 's/^/   /'
say "SLICE OK: mode 15, 1 crossing, 1 HBM-side stage on AW AR W R B; wrapper $W"
