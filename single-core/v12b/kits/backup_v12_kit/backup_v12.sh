#!/bin/bash
# backup_v12.sh tree|vivado|rebuild -- crisdsc3: the v12 single-core design, backed up so that nothing is missing and
# anyone can open the project in Vivado and rebuild the bitstream.  Each mode refuses while a v12 build runs.
#   tree     every file of the working tree, with a checksum manifest, unpacked and verified file by file
#   vivado   the replication package: Vivado's archive_project (every referenced file brought inside), the build flow
#            made location-independent, a README, the expected results, the bitstream and probes -- then RESTORED into
#            a new directory and opened there: every file present, no IP locked, the design elaborated, warnings equal
#   rebuild  (hours) the full build run from the restored copy; bitstream payload, timing and utilization compared
# Output: /data/omowuyi/backups/
P=/data/omowuyi/multicore_noc_exp_psc; D=/data/omowuyi/backups; K=$(cd "$(dirname "$0")" && pwd)
VS=${VIVADO_SETTINGS:-/data/Xilinx-2024.1/Vivado/2024.1/settings64.sh}
mkdir -p $D; TS=$(date +%Y%m%d_%H%M)
say()  { echo "[$(date +%T)] $*"; }
stop() { say "STOP: $*"; exit 1; }
BUILD=${BUILD:-v12b}                 # which build this backup is of: v12b (default) or v12
pgrep -x 'run_v12_build\.s|run_v12b_build\.' > /dev/null && stop "a v12/v12b build is running; back up after the finish"
[ -f $P/project/multi_core.xpr ] || stop "$P/project/multi_core.xpr missing"
verify_tar() {  # archive manifest -> unpack into scratch, check every file
    local V; V=$(mktemp -d $D/.verify_XXXX); tar xzf $1 -C $V || { rm -rf $V; return 1; }
    ( cd $V && md5sum --quiet -c $2 ) > ${1%.tar.gz}.verify 2>&1; local rc=$?; rm -rf $V; return $rc; }
norm() { sed -E 's#\[[^]]*/([^/]+:[0-9]+)\]#[\1]#; s#^.*(WARNING: )#\1#'; }   # warnings without the file's directory
case $1 in
tree)
    N=${BUILD}_tree_$TS; say "every file of $P"
    ( cd $(dirname $P) && find $(basename $P) -type f -print0 | sort -z | xargs -0 md5sum ) > $D/$N.manifest || stop "manifest"
    tar czf $D/$N.tar.gz -C $(dirname $P) $(basename $P) || stop "tar"
    verify_tar $D/$N.tar.gz $D/$N.manifest || stop "VERIFY FAILED (see $D/$N.verify)"
    say "TREE BACKUP OK: $D/$N.tar.gz ($(du -h $D/$N.tar.gz | cut -f1), $(wc -l < $D/$N.manifest) files, every file verified)"
    md5sum $D/$N.tar.gz | tee $D/$N.tar.gz.md5 ;;
vivado)
    BIT=$P/sixteen_core_noc_${BUILD}_ila.bit; LTX=$P/sixteen_core_noc_${BUILD}_ila.ltx
    [ -s $BIT ] && [ -s $LTX ] || stop "no v12 bitstream/probes yet: run after the finish"
    N=${BUILD}_replication_$TS; W=$D/$N; rm -rf $W; mkdir -p $W/expected $W/bitstream || stop "mkdir"
    source $VS || stop "Vivado settings $VS"
    say "1 Vivado: every referenced file listed, IP status, archive_project"
    ( cd $W && V12_XPR=$P/project/multi_core.xpr OUTD=$W/expected ZIP=$W/multi_core_v12.xpr.zip \
        vivado -mode batch -source $K/archive_v12.tcl -log $W/expected/archive.log -journal $W/expected/archive.jou > /dev/null 2>&1 )
    grep -E "FILES_TOTAL|LOCKED_IPS|ARCHIVE_" $W/expected/archive.log | sed 's/^/   /'
    grep -q "^ARCHIVE_OK" $W/expected/archive.log && [ -s $W/multi_core_v12.xpr.zip ] || stop "archive_project failed (see $W/expected/archive.log)"
    say "2 the build flow (location-independent), README, expected results, bitstream and probes"
    python3 $K/make_replicate.py $P/build_${BUILD}_kit $BUILD $W/replicate || stop "replication flow"
    cp $K/bit_payload_md5.py $K/restore_check.tcl $W/replicate/
    cp $BIT $LTX $W/bitstream/ && md5sum $W/bitstream/* | sed "s#$W/##" > $W/expected/bitstream.md5
    python3 $K/bit_payload_md5.py $BIT > $W/expected/bitstream_payload.md5.tmp || stop "bitstream payload checksum failed (no sync word in $BIT?)"
    sed "s#$BIT#sixteen_core_noc_${BUILD}_ila.bit#" $W/expected/bitstream_payload.md5.tmp > $W/expected/bitstream_payload.md5 && rm -f $W/expected/bitstream_payload.md5.tmp
    for f in build_report.txt place_util_slr.rpt place_util.rpt place_timing.rpt route_timing.rpt route_util.rpt drc.rpt elab_width_warnings.txt elab_v12.log; do
        [ -f $P/${BUILD}_build/$f ] && cp $P/${BUILD}_build/$f $W/expected/; done
    # expected elaboration = THIS project elaborated just before archiving (archive_v12.tcl), not an older build's
    grep -q "^ORIGINAL_ELAB_DONE" $W/expected/archive.log || stop "the original project did not elaborate"
    grep -h "Synth 8-3848" $W/expected/archive.log | norm > $W/expected/undriven_normalised.txt
    grep -h "Synth 8-689" $W/expected/archive.log | norm > $W/expected/width_warnings_normalised.txt
    [ -s /tmp/sim_round33.log ] && cp /tmp/sim_round33.log $W/expected/sim_round33_gate.log
    cp -r $P/simfix22/src $W/simulated_sources_fixes1-28 2>/dev/null
    PART=$(grep -oE "Part=\"[^\"]+\"" $P/project/multi_core.xpr | head -1 | cut -d'"' -f2)
    cat > $W/README.md << README
# HiAER-Spike ${BUILD} -- single-core design (fixes 1-28; v12b adds the HBM-side register-slice stage), Vivado 2024.1

Verified scope: one network on one core, any of the 16 cores, one at a time. The bitstream physically contains the 16-core
NoC fabric; multi-core operation is NOT part of this design's verification (that is v13).
Simulation proof: expected/sim_round33_gate.log (ROUND33 GATE: PASS). Simulated sources: simulated_sources_fixes1-28/.

Part: ${PART:-see the project}.  Vivado: 2024.1 (the IP was generated with 2024.1; another version will ask to upgrade it).

## Open the project
1. Unpack multi_core_v12.xpr.zip anywhere (it is self-contained: every file the project references is inside).
2. In Vivado 2024.1: File > Project > Open, and choose the multi_core.xpr inside the unpacked directory.

## Rebuild the bitstream (synthesis, capture-ILA insertion on core 1, placement, routing)
    export V12_ROOT=<a directory for the build>        # ${BUILD}_build/ is created inside it
    export V12_XPR=<the unpacked .../multi_core.xpr>
    export VIVADO_SETTINGS=<your Vivado 2024.1 settings64.sh>   # if not /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh
    ./replicate/run_build.sh trial      # synthesis -> taps verified -> ILA -> placement -> placed.dcp, utilization, timing
    ./replicate/run_build.sh finish     # routing -> timing; bitstream and probes only if setup and hold are met

## Expected results (expected/)
- bitstream.md5: the delivered sixteen_core_noc_${BUILD}_ila.bit / .ltx (also in bitstream/)
- bitstream_payload.md5: the bitstream from its sync word onward. A rebuilt .bit differs in its header (build date and
  time); compare the payload with:  python3 replicate/bit_payload_md5.py <your .bit>
- build_report.txt: post-placement and final WNS/WHS, taps, ILA; *_util*.rpt, *_timing.rpt, drc.rpt
- width_warnings_normalised.txt / undriven_normalised.txt: the warnings of THIS project elaborated just before it was
  archived (expected/archive.log); a correct restored copy elaborates with exactly these
- project_files.txt, ip_status.txt: every file the project referenced and the IP status when archived.  Recorded as
  found: xdma_0 / xdma_0_pcie4c_ip locked by an IP revision change (built from their existing generated products;
  upgrading would change the design), and a stale utils_1 incremental-synthesis checkpoint reference (not a source)
README
    ( cd $D && find $N -type f -print0 | sort -z | xargs -0 md5sum ) > $D/$N.manifest || stop "package manifest"
    tar czf $D/$N.tar.gz -C $D $N && verify_tar $D/$N.tar.gz $D/$N.manifest || stop "package verify failed"
    say "3 RESTORE: unpacked into a new directory and opened there"
    R=$D/restore_$TS; rm -rf $R; mkdir -p $R && tar xzf $D/$N.tar.gz -C $R && cd $R/$N && mkdir -p project && \
        python3 -m zipfile -e multi_core_v12.xpr.zip project/ || stop "restore unpack"
    RX=$(find $R/$N/project -name "multi_core.xpr" | head -1); [ -n "$RX" ] || stop "no .xpr in the restored archive"
    ( cd $R/$N && R_XPR=$RX OUTD=$R/$N vivado -mode batch -source $R/$N/replicate/restore_check.tcl -log restore_check.log -journal restore_check.jou > /dev/null 2>&1 )
    L=$R/$N/restore_check.log; grep -E "RESTORE_FILES|LOCKED_IPS|RUNS" $L | sed 's/^/   /'
    m=$(grep -oE "RESTORE_FILES [0-9]+ MISSING [0-9]+" $L | awk '{print $4}')
    # the original's recorded state: locked IPs (e.g. xdma_0, IP revision change) and missing utils_1 references must be
    # reproduced EXACTLY by the restored copy -- recorded, not fixed (upgrading an IP would change the design)
    lk=$(grep -oE "^LOCKED_IPS [0-9]+ \(.*\)" $L | head -1); lk0=$(grep -oE "^LOCKED_IPS [0-9]+ \(.*\)" $W/expected/archive.log | head -1)
    mu=$(grep -oE "MISSING_UTILS [0-9]+" $L | awk '{print $2}'); mu0=$(grep -oE "MISSING_UTILS [0-9]+" $W/expected/archive.log | awk '{print $2}')
    e=$(grep -cE "^ERROR" $L); md=$(grep -cE "Synth 8-6859|Synth 8-3352|multi-driven|multiple drivers" $L)
    grep -h "Synth 8-689" $L | norm > $R/$N/width_restored.txt; grep -h "Synth 8-3848" $L | norm > $R/$N/undriven_restored.txt
    wd=$(diff $W/expected/width_warnings_normalised.txt $R/$N/width_restored.txt | grep -c '^[<>]'); ud=$(diff $W/expected/undriven_normalised.txt $R/$N/undriven_restored.txt | grep -c '^[<>]')
    up=$(grep -ciE "upgrade|locked|out-of-date|not up-to-date" $R/$N/ip_status_restored.txt 2>/dev/null)
    say "   restored: missing design files ${m:-?}; locked IPs '${lk}' (original '${lk0}'); missing utils_1 refs ${mu:-?} (original ${mu0:-?}); IP-status lines needing attention ${up:-?}, elaboration errors $e, multi-driven $md, width warnings differing $wd, undriven differing $ud"
    grep -q RESTORE_ELAB_DONE $L && [ "$m" = 0 ] && [ -n "$lk" ] && [ "$lk" = "$lk0" ] && [ "${mu:-0}" -le "${mu0:-0}" ] && [ "$e" = 0 ] && [ "$md" = 0 ] && [ "$wd" = 0 ] && [ "$ud" = 0 ] \
        || stop "RESTORE CHECK FAILED (see $L, $R/$N/ip_status_restored.txt)"
    say "REPLICATION PACKAGE OK: $D/$N.tar.gz ($(du -h $D/$N.tar.gz | cut -f1)); restored in $R/$N and opened cleanly"
    md5sum $D/$N.tar.gz | tee $D/$N.tar.gz.md5 ;;
rebuild)
    R=$(ls -td $D/restore_* 2>/dev/null | head -1); [ -n "$R" ] || stop "run 'vivado' first"
    W=$(ls -d $R/${BUILD}_replication_* | head -1); RX=$(find $W/project -name multi_core.xpr | head -1)
    export V12_ROOT=$W V12_XPR=$RX VIVADO_SETTINGS=$VS
    say "rebuilding from the restored copy $W (trial, then finish)"
    $W/replicate/run_build.sh trial > $W/rebuild_trial.log 2>&1; $W/replicate/run_build.sh finish > $W/rebuild_finish.log 2>&1
    B=$W/${BUILD}_build/sixteen_core_noc_${BUILD}_ila.bit; [ -s $B ] || stop "the rebuild produced no bitstream (see $W/rebuild_*.log)"
    a=$(cut -d' ' -f1 $W/expected/bitstream_payload.md5); b=$(python3 $W/replicate/bit_payload_md5.py $B | cut -d' ' -f1)
    say "   timing original: $(grep -E '^WNS' $W/expected/build_report.txt | tail -1); rebuilt: $(grep -E '^WNS' $W/${BUILD}_build/build_report.txt | tail -1)"
    [ "$a" = "$b" ] && say "REBUILD IDENTICAL: bitstream payload $b matches the original" || say "REBUILD DIFFERS: payload $b vs original $a (compare timing and utilization above)" ;;
*) stop "usage: backup_v12.sh tree|vivado|rebuild" ;;
esac
