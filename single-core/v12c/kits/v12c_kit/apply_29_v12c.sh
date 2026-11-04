#!/bin/bash
# apply_29_v12c.sh -- crisdsc3, single-core folder: fix 29 into the v12b project's own hbm_processor.v and
# reset_synchronizer.sv (the files project/multi_core.xpr builds from); originals kept as *.before_29.  Run once.
P=/data/omowuyi/multicore_noc_exp_psc; K=$(cd "$(dirname "$0")" && pwd); O=$P/v12c_build; X=$P/project/multi_core.xpr
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
[ -f $O/FIX29_APPLIED ] && stop "already applied ($O/FIX29_APPLIED)"
[ -f $P/v12_build/APPLIED ] && [ -f $P/v12b_build/SLICE_APPLIED ] || stop "the v12b project is not in its v12b state (APPLIED / SLICE_APPLIED missing)"
for f in hbm_processor.v reset_synchronizer.sv; do
    n=$(find $P/project/multi_core.srcs/sources_1 -name $f | wc -l); [ "$n" = 1 ] || stop "$f found $n times in the project's sources"
    grep -q "$f" $X || stop "$f is not in $X"
done
HP=$(find $P/project/multi_core.srcs/sources_1 -name hbm_processor.v); RS=$(find $P/project/multi_core.srcs/sources_1 -name reset_synchronizer.sv)
T=$(mktemp -d) && cp $HP $RS $T/ && python3 $K/fix_29.py $T || stop "fix 29"
cp $HP $HP.before_29 && cp $RS $RS.before_29 && cp $T/hbm_processor.v $HP && cp $T/reset_synchronizer.sv $RS || stop "copy back"
[ "$(grep -c resetn_l $HP)" -ge 16 ] && [ "$(grep -c ASYNC_REG $RS)" = 2 ] || stop "fix 29 not found in the project files after copying"
mkdir -p $O && { echo "fix 29 applied $(date)"; md5sum $HP $RS $HP.before_29 $RS.before_29; } > $O/FIX29_APPLIED
say "FIX 29 APPLIED to the v12b project: $HP, $RS (originals *.before_29)"
