# build_v12.tcl -tclargs trial|finish [force] -- the v12 capture build (core-1 ILA), from build_ila.tcl's proven flow.
#   trial : synth_2 -> verify every tap on core 1 -> insert the ILA -> opt_design -> place_design -> per-SLR
#           utilization, post-placement timing, placed checkpoint.  Stops there.
#   finish: placed checkpoint -> phys_opt -> route -> phys_opt -> timing, utilization, DRC, routed checkpoint ->
#           bitstream + probe file, only if setup and hold are met (or 'force').
# Everything is logged to v12_build/build_report.txt.
set P   /data/omowuyi/multicore_noc_exp_psc
set OUT $P/v12_build
file mkdir $OUT
set mode  [lindex $argv 0]
set force [expr {[lindex $argv 1] eq "force"}]
set rep [open $OUT/build_report.txt a]
proc say {msg} { global rep; puts $msg; puts $rep $msg; flush $rep }
proc stop {msg} { global rep; say "BUILD_ABORT: $msg"; close $rep; exit 1 }
say "==== build_v12 $mode [clock format [clock seconds]]"
if {$mode eq "trial"} {
    open_project $P/project/multi_core.xpr
    reset_run synth_2
    launch_runs synth_2 -jobs 16
    wait_on_run synth_2
    set st [get_property STATUS [get_runs synth_2]]
    say "SYNTH: $st"
    if {![string match "*Complete*" $st]} { stop "synthesis did not complete" }
    open_run synth_2 -name synth_ila
    report_utilization -file $OUT/synth_util.rpt
    set expect {
      inst/hbmp/dbg_tx_state 4            inst/hbmp/dbg_rx_state 4
      inst/hbmp/dbg_tx_ptr_ctr 23         inst/hbmp/dbg_rx_ptr_ctr 23
      inst/hbmp/dbg_wait_clks_cnt 8       inst/hbmp/dbg_wait_clks_done_cnt 5
      inst/hbmp/dbg_phase 6               inst/hbmp/dbg_in 3
      inst/hbmp/dbg_fifo 4                inst/hbmp/dbg_axi 5
      inst/iep/dbg_iep_state 4            inst/iep/dbg_iep_timeout 11       inst/iep/dbg_iep_flags 4
      inst/eep/dbg_eep_state 3            inst/eep/dbg_eep_flags 2
      inst/ptf_fifo_controller/dbg_pfc_wren 1
      inst/ci/dbg_ci_rx_state 4           inst/ci/dbg_ci_tx_state 4         inst/ci/dbg_ci_flags 2
      inst/dbg_bram_spiked 16             inst/dbg_uram_spiked 16           inst/dbg_p2done 2
    }

    # every net carrying MARK_DEBUG, by name
    set NET [dict create]
    foreach n [get_nets -hierarchical -filter {MARK_DEBUG == 1}] { dict set NET [get_property NAME $n] $n }
    say "nets with MARK_DEBUG: [dict size $NET]"

    # ---------------------------------------------------------------- find core 1
    # the 16 copies of inst/hbmp/dbg_tx_state[0]; the generate index that differs between them
    # identifies the core
    set pre {}
    dict for {name obj} $NET {
        if {[regexp {^(.*)/inst/hbmp/dbg_tx_state\[0\]$} $name -> p]} { lappend pre $p }
    }
    say "core_wrapper instances with taps: [llength $pre]"
    foreach p [lsort $pre] { say "  $p" }
    if {[llength $pre] != 16} { stop "expected 16 core_wrapper instances, found [llength $pre]" }
    set idx {}
    foreach p $pre { lappend idx [regexp -all -inline {\[[0-9]+\]} $p] }
    set npos [llength [lindex $idx 0]]
    set vary -1
    for {set k 0} {$k < $npos} {incr k} {
        set vals {}
        foreach l $idx { lappend vals [lindex $l $k] }
        if {[llength [lsort -unique $vals]] == 16} { set vary $k }
    }
    if {$vary < 0} { stop "could not find the generate index that distinguishes the 16 cores" }
    set core1 {}
    foreach p $pre l $idx { if {[lindex $l $vary] eq {[1]}} { lappend core1 $p } }
    if {[llength $core1] != 1} { stop "core 1 not identified uniquely: $core1" }
    set C [lindex $core1 0]
    say "core 1 = $C"

    # ---------------------------------------------------------------- verify every tap
    set probes {}
    set missing {}
    foreach {base w} $expect {
        set nets {}
        if {$w == 1} {
            if {[dict exists $NET "$C/$base"]} { lappend nets [dict get $NET "$C/$base"] } else { lappend missing "$base" }
        } else {
            for {set i 0} {$i < $w} {incr i} {
                if {[dict exists $NET "$C/$base\[$i\]"]} { lappend nets [dict get $NET "$C/$base\[$i\]"] } else { lappend missing "$base\[$i\]" }
            }
        }
        lappend probes $base $w $nets
    }
    if {[llength $missing] > 0} { stop "taps missing on core 1: $missing" }
    set total 0
    foreach {base w nets} $probes { incr total $w; say [format "  probe %-40s %3d bits" $base $w] }
    say "all [expr {[llength $probes] / 3}] taps found on core 1, $total bits"

    # ---------------------------------------------------------------- ILA clock: aclk450
    set clk [get_nets -quiet aclk450]
    if {[llength $clk] != 1} { set clk [get_nets -quiet -hierarchical -filter [format {NAME == "%s/aclk450"} $C]] }
    if {[llength $clk] != 1} { stop "aclk450 net not found" }
    say "ILA clock net: [get_property NAME $clk]"

    create_debug_core u_ila_c1 ila
    set_property C_DATA_DEPTH 32768        [get_debug_cores u_ila_c1]
    set_property C_TRIGIN_EN false         [get_debug_cores u_ila_c1]
    set_property C_TRIGOUT_EN false        [get_debug_cores u_ila_c1]
    set_property C_ADV_TRIGGER false       [get_debug_cores u_ila_c1]
    set_property C_INPUT_PIPE_STAGES 2     [get_debug_cores u_ila_c1]
    set_property C_EN_STRG_QUAL false      [get_debug_cores u_ila_c1]
    set_property ALL_PROBE_SAME_MU true    [get_debug_cores u_ila_c1]
    set_property ALL_PROBE_SAME_MU_CNT 1   [get_debug_cores u_ila_c1]
    set_property port_width 1 [get_debug_ports u_ila_c1/clk]
    connect_debug_port u_ila_c1/clk $clk
    set k 0
    foreach {base w nets} $probes {
        if {$k > 0} { create_debug_port u_ila_c1 probe }
        set_property port_width $w [get_debug_ports u_ila_c1/probe$k]
        set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_c1/probe$k]
        connect_debug_port u_ila_c1/probe$k $nets
        incr k
    }
    say "ILA u_ila_c1: $k probes connected"

    opt_design -directive Explore
    set ilacells [get_cells -quiet -hierarchical -filter {NAME =~ u_ila_c1/*}]
    say "ILA cells after opt_design: [llength $ilacells]"
    if {[llength $ilacells] > 0} {
        set_false_path -from [get_clocks clk_out1_clock_and_buffer_clk_wiz_0_0] -to $ilacells
    }
    place_design -directive Explore
    report_utilization -slr -file $OUT/place_util_slr.rpt
    report_utilization -file $OUT/place_util.rpt
    report_timing_summary -file $OUT/place_timing.rpt
    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
    say "POST-PLACEMENT WNS: $wns   WHS: $whs   (estimates before routing)"
    write_checkpoint -force $OUT/placed.dcp
    say "TRIAL_DONE: placed checkpoint $OUT/placed.dcp; reports place_util_slr.rpt, place_util.rpt, place_timing.rpt"
} elseif {$mode eq "finish"} {
    if {![file exists $OUT/placed.dcp]} { stop "no placed checkpoint: run the trial first" }
    open_checkpoint $OUT/placed.dcp
    phys_opt_design -directive Explore
    route_design -directive Explore -tns_cleanup
    phys_opt_design -directive Explore
    report_timing_summary -file $OUT/timing_summary.rpt
    report_utilization -slr -file $OUT/route_util_slr.rpt
    report_utilization -hierarchical -file $OUT/route_util_hier.rpt
    report_drc -file $OUT/drc.rpt
    write_checkpoint -force $OUT/routed.dcp
    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
    say "WNS: $wns   WHS: $whs"
    if {$wns < 0 || $whs < 0} {
        say "TIMING NOT MET (see $OUT/timing_summary.rpt)"
        if {!$force} { stop "no bitstream written: timing not met (run with 'force' to write it anyway)" }
    } else { say "TIMING MET" }
    write_bitstream -force $OUT/sixteen_core_noc_v12_ila.bit
    write_debug_probes -force $OUT/sixteen_core_noc_v12_ila.ltx
    say "DONE: $OUT/sixteen_core_noc_v12_ila.bit and .ltx"
} else { stop "mode must be trial or finish" }
close $rep
