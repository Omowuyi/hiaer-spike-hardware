#!/bin/bash
# undo_v12.sh -- crisdsc3: restore the project's imports as they were before apply_v12.sh and remove the plasticity
# modules from the Vivado project.
P=/data/omowuyi/multicore_noc_exp_psc; I=$P/project/multi_core.srcs/sources_1/imports; B=$P/imports_before_v11; O=$P/v12_build
source /data/Xilinx-2024.1/Vivado/2024.1/settings64.sh
[ -d $B ] || { echo "nothing to undo: $B missing"; exit 1; }
cat > /tmp/undo_v12.tcl << TCL
open_project $P/project/multi_core.xpr
foreach f {stdp_ctrl.v stdp_update_unit.v stdp_elig_unit.v stdp_nstamps.v} { set p [get_files -quiet $I/\$f]; if {[llength \$p]} { remove_files \$p } }
update_compile_order -fileset sources_1
close_project
TCL
vivado -mode batch -source /tmp/undo_v12.tcl -log /tmp/undo_v12.log -journal /tmp/undo_v12.jou > /dev/null 2>&1
rm -rf $I && cp -a $B $I && echo "restored $I from $B"
