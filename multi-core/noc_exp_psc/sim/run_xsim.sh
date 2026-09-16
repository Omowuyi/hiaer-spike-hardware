#!/usr/bin/env bash
# Verify the NoC modules under xsim.
#
# WHY XSIM AND NOT IVERILOG
# iverilog reports, for noc_l1_bus.sv:161, noc_l2_bus.sv:104 and
# noc_arbiter.sv:65:
#
#   sorry: constant selects in always_* processes are not currently supported
#          (all bits will be included)
#
# That is the simulator saying it cannot handle a variable index inside an
# always block -- exactly what these buses do (xbar_data[rx_sel[dst]]).  Under
# iverilog noc_l2_bus hangs with time not advancing and the received address
# reads x.  Only noc_spike_router compiled clean there, so only its result was
# trustworthy.  xsim handles this correctly.
#
# Point NOC_SRC at the directory holding the ORIGINAL sources -- no
# iverilog workarounds are needed here:
#
#   noc_pkg.sv  noc_spike_router.sv  noc_l1_bus.sv  noc_l2_bus.sv
#
#   NOC_SRC=/home/omowuyi/multi_16_parallel/multicore_16 bash run_xsim.sh
#
# Each testbench prints PASS/FAIL per case and a count.  Nothing is written and
# no hardware is touched.

set -e
: "${NOC_SRC:?set NOC_SRC to the directory holding noc_pkg.sv etc}"
command -v xvlog >/dev/null || { echo "source the Vivado settings first"; exit 1; }

for f in noc_pkg.sv noc_spike_router.sv noc_l1_bus.sv noc_l2_bus.sv; do
    [ -f "$NOC_SRC/$f" ] || { echo "missing $NOC_SRC/$f"; exit 1; }
done

run () {   # $1 = testbench, $2 = top module, $3.. = sources
    tb=$1; top=$2; shift 2
    echo "============================================================"
    echo "  $tb"
    echo "============================================================"
    rm -rf work_$top && mkdir work_$top && cd work_$top
    xvlog -sv "$@" ../$tb > compile.log 2>&1 || {
        echo "  COMPILE FAILED"; tail -20 compile.log; cd ..; return 1; }
    xelab -debug typical $top -s sim > elab.log 2>&1 || {
        echo "  ELABORATION FAILED"; tail -20 elab.log; cd ..; return 1; }
    xsim sim -R 2>&1 | grep -vE "^(INFO|WARNING|\*\*\*|Vivado|xsim|Time reso|Copyright|Tool Ver)" | sed '/^$/d'
    cd ..
    echo
}

# Elaboration gate: does the whole interconnect plus the integration layer
# build?  iverilog cannot do this -- it rejects the unpacked-array port
# connections cores_with_noc uses -- so xsim is the only check that counts.
echo "============================================================"
echo "  ELABORATION: cores_with_noc + noc_integration"
echo "============================================================"
rm -rf work_elab && mkdir work_elab && cd work_elab
if xvlog -sv $NOC_SRC/noc_pkg.sv $NOC_SRC/noc_spike_router.sv \
         $NOC_SRC/noc_spike_injector.sv $NOC_SRC/noc_l1_bus.sv \
         $NOC_SRC/noc_l2_bus.sv $NOC_SRC/noc_arbiter.sv \
         $NOC_SRC/cores_with_noc.sv $NOC_SRC/noc_integration.v \
         > compile.log 2>&1 && \
   xelab noc_integration -s elab > elab.log 2>&1; then
    echo "  PASS -- the integration layer elaborates"
else
    echo "  FAIL -- see work_elab/compile.log and work_elab/elab.log"
    tail -25 compile.log elab.log 2>/dev/null
fi
cd ..
echo

# The AXI-Stream switches replace Xilinx IP.  The IP is a black box, so
# nothing between the cores and PCIe/Firefly could be simulated before.
if [ -f "$NOC_SRC/axis_switches.sv" ]; then
    run tb_switches.sv tb_switches $NOC_SRC/axis_switches.sv
    run tb_arb.sv     tb_arb     $NOC_SRC/axis_switches.sv
fi

if [ -f "$NOC_SRC/axon_trace_mem.v" ]; then
    run tb_at2.sv     tb_at2     $NOC_SRC/axon_trace_mem.v
fi

run tb_router.sv tb_router $NOC_SRC/noc_pkg.sv $NOC_SRC/noc_spike_router.sv
run tb_l1.sv     tb_l1     $NOC_SRC/noc_pkg.sv $NOC_SRC/noc_l1_bus.sv
run tb_l2.sv     tb_l2     $NOC_SRC/noc_pkg.sv $NOC_SRC/noc_l2_bus.sv

cat <<'NOTE'
============================================================
  WHAT TO READ
============================================================
tb_router   Already 5/5 under iverilog with no warnings.  Re-running here
            only confirms xsim agrees.

tb_l1       Which cores an L2-delivered spike reaches.  The iverilog run said
            "the mask in bits [25:22] selects cores" -- but that run carried
            the unsupported-construct warning, so it needs confirming.

tb_l2       Cluster-to-cluster delivery, and the important one: the test now
            prints fwd_level and fwd_mask of the FORWARDED packet.

            noc_l2_bus.sv lines 82-87 appear to rewrite the packet:

                xbar_data[src] <= { OP_L1,
                                    l1_tx_data[src][29:26],
                                    4'b1111,              <-- mask overwritten
                                    l1_tx_data[src][21:0] };

            If fwd_mask reads 1111 regardless of the mask sent, then an L2
            spike BROADCASTS to all four cores in every destination cluster
            rather than selecting positions.  Receiving cores would have to
            filter by neuron address, and a single-core target costs four
            deliveries.

            That is a partitioner constraint and a bandwidth cost, and it is
            currently a claim from READING the source -- this run is what
            settles it.

Also note tb_l2's "cluster 0 -> itself" case: line 107 has (d != src), so a
spike should NOT loop back to its own cluster.
NOTE
