# build_v14.tcl -tclargs trial|finish [force] -- v14: the v14 sources (v13 + fix 31 + fix 32) (full B, N5, fix 30, fix 29, N1-N4, N2', R1, R2), the core-1
# capture ILA as v12b, per-core HBM handshake probes inserted in the netlist (u_ila_hs), fix-29 and probe-timing checks.
#   trial : synth_2 -> verify every tap on core 1 -> insert the ILA -> opt_design -> place_design -> per-SLR
#           utilization, post-placement timing, placed checkpoint.  Stops there.
#   finish: placed checkpoint -> phys_opt -> route -> phys_opt -> timing, utilization, DRC, routed checkpoint ->
#           bitstream + probe file, only if setup and hold are met (or 'force').
# Everything is logged to v14_build/build_report.txt.
set P   /data/omowuyi/multicore_noc_v13
set OUT $P/v14_build
file mkdir $OUT
set mode  [lindex $argv 0]
set force [expr {[lindex $argv 1] eq "force"}]
set rep [open $OUT/build_report.txt a]
proc say {msg} { global rep; puts $msg; puts $rep $msg; flush $rep }
proc stop {msg} { global rep; say "BUILD_ABORT: $msg"; close $rep; exit 1 }
say "==== build_v14 $mode [clock format [clock seconds]]"

source [file join [file dirname [info script]] lutinit.tcl]
# fix 29 checks: one resetn_l per core, released by that core's own synchroniser, feeding only that core; no synchroniser copies
proc fix29_check {where} {
    set bad 0
    set rl [get_cells -quiet -hier -filter {NAME =~ *my_core/inst/hbmp/resetn_l_reg}]
    if {[llength $rl] != 16} { say "FIX29 $where: [llength $rl] resetn_l registers (expected 16)"; incr bad }
    set rep [get_cells -quiet -hier -filter {NAME =~ *reset_sync*/*replica*}]
    if {[llength $rep]} { say "FIX29 $where: [llength $rep] replicated synchroniser registers"; incr bad }
    foreach c $rl {
        set pre [regsub {/inst/hbmp/resetn_l_reg$} $c {}]
        set drv [get_cells -quiet -of_objects [get_pins -quiet -leaf -filter {DIRECTION == OUT} -of_objects [get_nets -quiet -of_objects [get_pins $c/D]]]]
        if {$drv ne "$pre/reset_sync_450/reset_out_reg"} { say "FIX29 $where: $pre resetn_l driven by $drv"; incr bad }
        set loads [get_cells -quiet -of_objects [get_pins -quiet -leaf -filter {DIRECTION == IN} -of_objects [get_nets -quiet -of_objects [get_pins $c/Q]]]]
        set foreign 0; foreach l $loads { if {[string first "$pre/" $l] != 0} { incr foreign } }
        if {$foreign} { say "FIX29 $where: $pre resetn_l feeds $foreign cells outside its core"; incr bad }
    }
    foreach c $rl { say "FIX29 $where:   $c" }
    if {[llength [lsort -unique [lmap c $rl {regsub {/inst/hbmp/resetn_l_reg$} $c {}}]]] != [llength $rl]} { say "FIX29 $where: two resetn_l registers in one core"; incr bad }
    if {$bad} { stop "fix 29 check failed $where ($bad problems)" }
    say "FIX29 $where: PASS (16 local resetn_l, each from its own synchroniser, no loads outside its core, no synchroniser copies)"
}
# per-core HBM handshake probes: worst setup/hold into the counters must be met (otherwise their counts cannot be trusted)
proc hs_timing {where} {
    set ffs [get_cells -quiet -filter {NAME =~ hs_c* && REF_NAME == FDRE}]
    set ps [get_timing_paths -quiet -delay_type max -max_paths 1 -to $ffs]; set ph [get_timing_paths -quiet -delay_type min -max_paths 1 -to $ffs]
    set s [expr {[llength $ps] ? [get_property SLACK $ps] : 99}]; set h [expr {[llength $ph] ? [get_property SLACK $ph] : 99}]
    say [format "HS PROBES %s: %d counter flip-flops, worst setup %+.3f, worst hold %+.3f" $where [llength $ffs] $s $h]
    if {[llength $ffs] != 384} { stop "HS probes: [llength $ffs] counter flip-flops (expected 384)" }
    if {$s < 0 || $h < 0} { stop "HS probes miss timing $where: their counts could not be trusted" }
}
if {$mode eq "trial"} {
    open_project $P/project/multi_core.xpr
    reset_run synth_2
    launch_runs synth_2 -jobs 16
    wait_on_run synth_2
    set st [get_property STATUS [get_runs synth_2]]
    say "SYNTH: $st"
    if {![string match "*Complete*" $st]} { stop "synthesis did not complete" }
    open_run synth_2 -name synth_ila
    # v12b: the synthesized netlist must carry the new slice in every core (mode 15) and no mode-12 slice
    set n15 [llength [get_cells -quiet -hier -filter {NAME =~ *axi_slice/inst/r15.*}]]
    set n12 [llength [get_cells -quiet -hier -filter {NAME =~ *axi_slice/inst/r12.*}]]
    say "SLICE CELLS: mode 15 $n15, mode 12 $n12"
    if {$n15 == 0 || $n12 != 0} { stop "the synthesized slice is not the mode-15 slice in every core" }
    # v13: round 39's design in the netlist -- 16 local fix-29 reset registers, the NoC quiet counter, 16 relay-pass arming registers, the barrier's go
    set nrl [llength [get_cells -quiet -hier -filter {NAME =~ *my_core/inst/hbmp/resetn_l_reg}]]
    set nqc [llength [get_cells -quiet -hier -filter {NAME =~ *noc_quiet_cnt*}]]
    set nra [llength [get_cells -quiet -hier -filter {NAME =~ *my_core/inst/eep/relay_armed_reg}]]
    set ngo [llength [get_cells -quiet -hier -filter {NAME =~ *noc_go0_reg* || NAME =~ *noc_go1_reg*}]]
    say "V13 CELLS: resetn_l $nrl, noc_quiet counter bits $nqc, relay-pass arming registers $nra, barrier go registers $ngo"
    if {$nrl != 16 || $nqc == 0 || $nra != 16 || $ngo < 2} { stop "the synthesized netlist is not round 39's design (fix 29 / full option B missing)" }
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


    # ---------------------------------------------------------------- per-core HBM handshake probes (decision: yes)
    # Six 4-bit counters per core (AW, W, B completed handshakes on both sides of the core's register slice), each in the
    # core's own slice clock; built from the LUT INITs proven in ECO 3; DONT_TOUCH; read by u_ila_hs (384 bits).  They only
    # observe existing nets: the simulated RTL is unchanged.
    create_cell -reference VCC hs_vcc; create_net hs_one; connect_net -net hs_one -objects [get_pins hs_vcc/P]
    create_cell -reference GND hs_gnd; create_net hs_zero; connect_net -net hs_zero -objects [get_pins hs_gnd/G]
    set hsnets {}
    set order {}
    foreach p $pre l $idx { lappend order [list [string trim [lindex $l $vary] {[]}] $p] }
    foreach cp [lsort -integer -index 0 $order] {
        lassign $cp k P
        set ck [get_nets -quiet -of_objects [get_pins -quiet "$P/axi_slice/aclk"]]
        if {[llength $ck] != 1} { stop "HS probes: no slice clock net for core $k ($P/axi_slice/aclk)" }
        foreach {e vp rp} {s_aw s_axi_awvalid s_axi_awready s_w s_axi_wvalid s_axi_wready s_b s_axi_bvalid s_axi_bready
                            m_aw m_axi_awvalid m_axi_awready m_w m_axi_wvalid m_axi_wready m_b m_axi_bvalid m_axi_bready} {
            set v [get_nets -quiet -of_objects [get_pins -quiet "$P/axi_slice/$vp"]]; set r [get_nets -quiet -of_objects [get_pins -quiet "$P/axi_slice/$rp"]]
            if {[llength $v] != 1 || [llength $r] != 1} { stop "HS probes: core $k $vp/$rp not found" }
            for {set b 0} {$b < 4} {incr b} {
                set f hs_c${k}_${e}_q$b; create_cell -reference FDRE $f; set_property INIT 1'b0 [get_cells $f]; set_property DONT_TOUCH TRUE [get_cells $f]
                connect_net -net hs_one -objects [get_pins $f/CE]; connect_net -net hs_zero -objects [get_pins $f/R]
                connect_net -hierarchical -net $ck -objects [get_pins $f/C]
                create_net ${f}_n; connect_net -net ${f}_n -objects [get_pins $f/Q]
            }
            for {set b 0} {$b < 4} {incr b} {
                set n [expr {3 + $b}]; set lc hs_c${k}_${e}_l$b
                create_cell -reference LUT$n $lc; set_property INIT [lut_init $n [cnt_body $b]] [get_cells $lc]; set_property DONT_TOUCH TRUE [get_cells $lc]
                create_net ${lc}_o; connect_net -net ${lc}_o -objects [list [get_pins $lc/O] [get_pins hs_c${k}_${e}_q$b/D]]
                connect_net -net hs_c${k}_${e}_q${b}_n -objects [get_pins $lc/I0]
                connect_net -hierarchical -net $v -objects [get_pins $lc/I1]
                connect_net -hierarchical -net $r -objects [get_pins $lc/I2]
                for {set j 0} {$j < $b} {incr j} { connect_net -net hs_c${k}_${e}_q${j}_n -objects [get_pins $lc/I[expr {3 + $j}]] }
                lappend hsnets [get_nets hs_c${k}_${e}_q${b}_n]
            }
        }
    }
    say "HS PROBES: [llength $hsnets] counter bits in 16 cores (6 counters x 4 bits each)"
    if {[llength $hsnets] != 384} { stop "HS probes: [llength $hsnets] bits (expected 384)" }
    create_debug_core u_ila_hs ila
    set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_hs]
    set_property C_INPUT_PIPE_STAGES 2 [get_debug_cores u_ila_hs]
    set_property port_width 1 [get_debug_ports u_ila_hs/clk]
    connect_debug_port u_ila_hs/clk $clk
    set_property port_width 384 [get_debug_ports u_ila_hs/probe0]
    connect_debug_port u_ila_hs/probe0 $hsnets
    say "ILA u_ila_hs: 384 probe bits connected"

    opt_design -directive Explore
    set ilacells [get_cells -quiet -hierarchical -filter {NAME =~ u_ila_c1/*}]
    say "ILA cells after opt_design: [llength $ilacells]"
    if {[llength $ilacells] > 0} {
        set_false_path -from [get_clocks clk_out1_clock_and_buffer_clk_wiz_0_0] -to $ilacells
    }
    set hsila [get_cells -quiet -hierarchical -filter {NAME =~ u_ila_hs/*}]
    if {[llength $hsila]} { set_false_path -from [get_cells -quiet -filter {NAME =~ hs_c*}] -to $hsila }
    place_design -directive Explore
    report_utilization -slr -file $OUT/place_util_slr.rpt
    report_utilization -file $OUT/place_util.rpt
    report_timing_summary -file $OUT/place_timing.rpt
    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
    say "POST-PLACEMENT WNS: $wns   WHS: $whs   (estimates before routing)"
    write_checkpoint -force $OUT/placed.dcp
    # v13: design-wide CDC review on the placed design (full B adds 250 <-> 450 MHz crossings); reviewed before the finish
    if {[catch {report_cdc -summary -file $OUT/cdc_summary.rpt} e]} { say "CDC summary not written: $e" }
    if {[catch {report_cdc -details -severity {Critical} -file $OUT/cdc_critical.rpt} e]} {
        say "CDC critical-only details not written ($e); writing all details"
        catch {report_cdc -details -file $OUT/cdc_details.rpt}
    }
    say "CDC REVIEW: reports written ([join [glob -nocomplain -tails -directory $OUT cdc_*.rpt] {, }]) -- to be reviewed before the finish"
    fix29_check "after placement"
    hs_timing "after placement"
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
    fix29_check "after routing"
    hs_timing "after routing"
    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
    say "WNS: $wns   WHS: $whs"
    if {$wns < 0 || $whs < 0} {
        say "TIMING NOT MET (see $OUT/timing_summary.rpt)"
        if {!$force} { stop "no bitstream written: timing not met (run with 'force' to write it anyway)" }
    } else { say "TIMING MET" }
    write_bitstream -force $OUT/sixteen_core_noc_v14_ila.bit
    write_debug_probes -force $OUT/sixteen_core_noc_v14_ila.ltx
    say "DONE: $OUT/sixteen_core_noc_v14_ila.bit and .ltx"
} else { stop "mode must be trial or finish" }
close $rep
