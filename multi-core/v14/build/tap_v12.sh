#!/bin/bash
# tap_v12.sh IMPORTS SIM_SRC FIX_ILA -- add the core-1 capture taps with the capture build's own fix_ila.py to the six
# tapped files (copied tap-free from the simulation), then verify: each tapped file = simulated file + taps only.
I=$1; S=$2; FX=$3; K=$(cd "$(dirname "$0")" && pwd)
TAPPED="hbm_processor.v internal_events_processor.v external_events_processor_simple.v pointer_fifo_controller.v command_interpreter.v single_core.sv"
for f in $TAPPED; do cmp -s $I/$f $S/$f || { echo "TAP STOP: $f is not the simulated file before tapping"; exit 1; }; done
python3 $FX $I || { echo "TAP STOP: fix_ila.py refused"; exit 1; }
for f in $TAPPED; do python3 $K/tapcheck.py $S/$f $I/$f || { echo "TAP STOP: $f"; exit 1; }; done
echo "TAPS OK"
