# eco3.tcl -- on the ECO-2 design: event counters in core 2's own HBM-processor clock domain, read by the ILA.  Six 4-bit
# counters of completed handshakes (AW, W, B on both sides of core 2's register slice) and two latched flags (the HBM
# processor ever in TX_STATE_WRITE_HBM_ADDR = 1000 / TX_STATE_WRITE_HBM_DATA = 0101).  New cells constrained to core 2's
# clock region; existing placement and routing kept.  Env: K, DCP, OUT.
source $::env(K)/lutinit.tcl
open_checkpoint $::env(DCP)
set o [open $::env(OUT)/eco3.txt w]
proc say {o t} { puts $o $t; flush $o; puts "ECO3 $t" }
proc pnet {pin} { set p [get_pins -quiet $pin]; if {![llength $p]} { return "" }; return [get_nets -quiet -of_objects $p] }
set S {genblk3[2].my_core}
set ckpin [get_pins -quiet "$S/inst/hbmp/FSM_sequential_tx_curr_state_reg\[0\]/C"]
set ck [pnet "$S/inst/hbmp/FSM_sequential_tx_curr_state_reg\[0\]/C"]
if {$ck eq ""} { say $o "STOP: no clock net on core 2's HBM-processor state register"; exit 1 }
say $o "clock net $ck  clock [get_clocks -quiet -of_objects $ckpin]  period [get_property -quiet PERIOD [get_clocks -quiet -of_objects $ckpin]] ns"
set cr [get_clock_regions -quiet -of_objects [get_sites -quiet -of_objects [get_cells "$S/inst/hbmp/FSM_sequential_tx_curr_state_reg\[0\]"]]]
say $o "core 2 HBM processor clock region: $cr"
create_cell -reference VCC eco3_vcc; create_net eco3_one; connect_net -net eco3_one -objects [get_pins eco3_vcc/P]
create_cell -reference GND eco3_gnd; create_net eco3_zero; connect_net -net eco3_zero -objects [get_pins eco3_gnd/G]
proc mkff {name} {
    create_cell -reference FDRE $name; set_property INIT 1'b0 [get_cells $name]
    connect_net -net eco3_one -objects [get_pins $name/CE]; connect_net -net eco3_zero -objects [get_pins $name/R]
    connect_net -hierarchical -net $::ck -objects [get_pins $name/C]
    create_net ${name}_n; connect_net -net ${name}_n -objects [get_pins $name/Q]
}
set ev {s_aw s_axi_awvalid s_axi_awready s_w s_axi_wvalid s_axi_wready s_b s_axi_bvalid s_axi_bready
        m_aw m_axi_awvalid m_axi_awready m_w m_axi_wvalid m_axi_wready m_b m_axi_bvalid m_axi_bready}
set made {}
foreach {e vp rp} $ev {
    set v [pnet "$S/axi_slice/$vp"]; set r [pnet "$S/axi_slice/$rp"]
    if {$v eq "" || $r eq ""} { say $o "SKIP counter $e: no net on $vp or $rp"; continue }
    for {set b 0} {$b < 4} {incr b} { mkff eco3_${e}_q$b }
    for {set b 0} {$b < 4} {incr b} {
        set k [expr {3 + $b}]; set l eco3_${e}_l$b
        create_cell -reference LUT$k $l; set_property INIT [lut_init $k [cnt_body $b]] [get_cells $l]
        create_net ${l}_o; connect_net -net ${l}_o -objects [list [get_pins $l/O] [get_pins eco3_${e}_q$b/D]]
        connect_net -net eco3_${e}_q${b}_n -objects [get_pins $l/I0]
        connect_net -hierarchical -net $v -objects [get_pins $l/I1]
        connect_net -hierarchical -net $r -objects [get_pins $l/I2]
        for {set j 0} {$j < $b} {incr j} { connect_net -net eco3_${e}_q${j}_n -objects [get_pins $l/I[expr {3 + $j}]] }
    }
    lappend made $e; say $o "counter $e: valid $v, ready $r"
}
set st {}
for {set b 0} {$b < 4} {incr b} { lappend st [pnet "$S/inst/hbmp/FSM_sequential_tx_curr_state_reg\[$b\]/Q"] }
foreach {name pat} {addr 1000 data 0101} {
    if {[lsearch $st ""] >= 0} { say $o "SKIP flag $name: a state bit has no net"; continue }
    mkff eco3_${name}_f; set l eco3_${name}_fl
    create_cell -reference LUT5 $l; set_property INIT [lut_init 5 [state_body $pat]] [get_cells $l]
    create_net ${l}_o; connect_net -net ${l}_o -objects [list [get_pins $l/O] [get_pins eco3_${name}_f/D]]
    connect_net -net eco3_${name}_f_n -objects [get_pins $l/I0]
    for {set b 0} {$b < 4} {incr b} { connect_net -hierarchical -net [lindex $st $b] -objects [get_pins $l/I[expr {1 + $b}]] }
    say $o "flag $name: state == $pat"
}
# ILA: probe19[0..15] = s_aw, s_w, s_b, m_aw counters; probe20[0..7] = m_w, m_b counters; probe20[8..9] = addr, data flags
set slots {}
foreach e {s_aw s_w s_b m_aw} { for {set b 0} {$b < 4} {incr b} { lappend slots probe19 eco3_${e}_q${b}_n } }
foreach e {m_w m_b} { for {set b 0} {$b < 4} {incr b} { lappend slots probe20 eco3_${e}_q${b}_n } }
lappend slots probe20 eco3_addr_f_n probe20 eco3_data_f_n
set idx [dict create probe19 0 probe20 0]
foreach {pr net} $slots {
    set i [dict get $idx $pr]; dict incr idx $pr
    if {![llength [get_nets -quiet $net]]} { say $o "SKIP $pr\[$i\]: $net not created"; continue }
    set ipin [get_pins -quiet "u_ila_c1/$pr\[$i\]"]
    if {[llength [get_nets -quiet -of_objects $ipin]]} { disconnect_net -objects $ipin }
    if {[catch {connect_net -net $net -objects $ipin} err]} { say $o "SKIP $pr\[$i\] <- $net: [string range $err 0 100]" } else { say $o "  $pr\[$i\] <- $net" }
}
set new [get_cells -quiet -filter {NAME =~ eco3_* && (REF_NAME =~ LUT* || REF_NAME == FDRE)}]
say $o "new cells: [llength $new]"
create_pblock eco3_pb
if {[catch {resize_pblock eco3_pb -add "CLOCKREGION_${cr}:CLOCKREGION_${cr}"; add_cells_to_pblock eco3_pb $new} err]} {
    say $o "pblock not applied ([string range $err 0 120]); placing without it"; delete_pblock -quiet eco3_pb
} else { say $o "new cells constrained to CLOCKREGION_${cr}" }
if {[catch {place_design} err]} { say $o "STOP: place_design: [string range $err 0 200]"; exit 1 }
if {[catch {route_design -preserve} err]} { say $o "route_design -preserve failed ([string range $err 0 80]); plain route_design"; route_design }
report_route_status -file $::env(OUT)/route_status3.txt
set ffs [get_cells -quiet -filter {NAME =~ eco3_* && REF_NAME == FDRE}]
foreach kind {max min} {
    set p [get_timing_paths -quiet -delay_type $kind -max_paths 1 -to $ffs]
    say $o "counters: worst [expr {$kind eq "max" ? "setup" : "hold"}] slack into them [expr {[llength $p] ? [format %+.3f [get_property SLACK $p]] : "none"}] ns"
}
write_checkpoint -force $::env(OUT)/eco3_routed.dcp
write_bitstream -force $::env(OUT)/sixteen_core_noc_v12b_eco3.bit
write_debug_probes -force $::env(OUT)/sixteen_core_noc_v12b_eco3.ltx
close $o
puts "ECO3_DONE"
