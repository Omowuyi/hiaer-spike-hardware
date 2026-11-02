# apply_slice.tcl -- the project's own hbm_register_slice set exactly as slice_kit/regen_slice.tcl set its copy (proven
# SLICE OK), regenerated, and its out-of-context synthesis re-run explicitly.
open_project $::env(XPR)
set ip [get_ips hbm_register_slice]
if {[get_property IS_LOCKED $ip]} { puts "APPLY_ABORT: IP locked: [get_property LOCK_DETAILS $ip]"; exit 1 }
set_property -dict [list CONFIG.REG_AW {15} CONFIG.REG_AR {15} CONFIG.REG_W {15} CONFIG.REG_R {15} CONFIG.REG_B {15} CONFIG.NUM_SLR_CROSSINGS {1}] $ip
set_property -dict [list CONFIG.PIPELINES_SLAVE_AW {1} CONFIG.PIPELINES_SLAVE_AR {1} CONFIG.PIPELINES_SLAVE_W {1} CONFIG.PIPELINES_SLAVE_R {1} CONFIG.PIPELINES_SLAVE_B {1}] $ip
foreach p {REG_AW REG_AR REG_W REG_R REG_B NUM_SLR_CROSSINGS PIPELINES_SLAVE_R PIPELINES_MASTER_R} { puts "PROJECT $p=[get_property CONFIG.$p $ip]" }
generate_target all $ip
set r [get_runs -quiet hbm_register_slice_synth_1]
if {$r ne ""} {
    reset_run $r; launch_runs $r -jobs 8; wait_on_run $r
    set st [get_property STATUS $r]; puts "OOC_RUN: $st"
    if {![string match "*Complete*" $st]} { puts "APPLY_ABORT: out-of-context synthesis of the slice did not complete"; exit 1 }
} else { puts "OOC_RUN: none (the slice is synthesized with the top level)" }
close_project
puts "APPLY_DONE"
