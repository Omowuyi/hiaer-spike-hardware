# eco2.tcl -- ECO on v12b's routed design: re-point 55 bits of core 1's ILA (u_ila_c1) to core 2's AXI handshake (both
# sides of its register slice), its HBM-processor and command-interpreter states and its FIFO flags; route only the
# changed nets; every other cell and route stays as placed in v12b.  Env: DCP, OUT.
open_checkpoint $::env(DCP)
set o [open $::env(OUT)/eco2.txt w]
proc say {o t} { puts $o $t; flush $o; puts "ECO $t" }
say $o "== s_axi_rready of every core's slice (net present?)"
for {set c 0} {$c < 16} {incr c} {
    set p [get_pins -quiet "genblk3\[$c\].my_core/axi_slice/s_axi_rready"]
    say $o "  core $c: [expr {[llength $p] ? ([llength [get_nets -quiet -of_objects $p]] ? "net [get_nets -quiet -of_objects $p]" : "NO NET") : "no pin"}]"
}
set S {genblk3[2].my_core}
proc pnet {pin} { set p [get_pins -quiet $pin]; if {![llength $p]} { return "" }; return [get_nets -quiet -of_objects $p] }
proc qnet {cell} { return [pnet "$cell/Q"] }
# a FIFO flag at the FIFO's own output port (outside its locked IP netlist): <fifo>/empty or <fifo>/full,
# else the IP wrapper's port (<fifo>/IP/empty ...), else any boundary pin of the FIFO ending in the flag name
proc fflag {fifo which} {
    foreach cand [list "$fifo/$which" "$fifo/IP/$which"] { set n [pnet $cand]; if {$n ne ""} { return [list $cand $n] } }
    foreach p [get_pins -quiet -filter "NAME =~ ${fifo}/*${which} && NAME !~ *prog_*" "$fifo/*"] { set n [get_nets -quiet -of_objects $p]; if {[llength $n]} { return [list [get_property NAME $p] $n] } }
    return [list "$fifo/$which" ""]
}
set map {}
# probe2: slice handshake, HBM-processor side then HBM side, then FIFO flags
set i 0
foreach sig {awvalid awready wvalid wready bvalid bready arvalid arready rvalid rready} { lappend map [list probe2 $i "$S/axi_slice/s_axi_$sig" [pnet "$S/axi_slice/s_axi_$sig"]]; incr i }
foreach sig {awvalid awready wvalid wready bvalid bready arvalid arready rvalid rready} { lappend map [list probe2 $i "$S/axi_slice/m_axi_$sig" [pnet "$S/axi_slice/m_axi_$sig"]]; incr i }
set ff "IP/U0/inst_fifo_gen/gconvfifo.rf/grf.rf/gntv_or_sync_fifo.gl0"
lappend map [list probe2 20 "rxFIFO empty" [lindex [fflag "$S/inst/rxFIFO" empty] 1]]
lappend map [list probe2 21 "rxFIFO full" [lindex [fflag "$S/inst/rxFIFO" full] 1]]
lappend map [list probe2 22 "hbmdataFIFO full" [lindex [fflag "$S/inst/hbmdataFIFO" full] 1]]
# probe3: HBM processor states, command-interpreter transmit state, FIFO flags
for {set b 0} {$b < 11} {incr b} { lappend map [list probe3 $b "hbmp rx onehot $b" [qnet "$S/inst/hbmp/FSM_onehot_rx_curr_state_reg\[$b\]"]] }
for {set b 0} {$b < 4} {incr b} { lappend map [list probe3 [expr {11 + $b}] "hbmp tx $b" [qnet "$S/inst/hbmp/FSM_sequential_tx_curr_state_reg\[$b\]"]] }
for {set b 0} {$b < 3} {incr b} { lappend map [list probe3 [expr {15 + $b}] "ci tx $b" [qnet "$S/inst/ci/FSM_sequential_tx_curr_state_reg\[$b\]"]] }
lappend map [list probe3 18 "hbmdataFIFO empty" [lindex [fflag "$S/inst/hbmdataFIFO" empty] 1]]
lappend map [list probe3 19 "txFIFO empty" [lindex [fflag "$S/inst/txFIFO" empty] 1]]
lappend map [list probe3 20 "txFIFO full" [lindex [fflag "$S/inst/txFIFO" full] 1]]
# probe19: command-interpreter receive state
for {set b 0} {$b < 12} {incr b} { lappend map [list probe19 $b "ci rx onehot $b" [qnet "$S/inst/ci/FSM_onehot_rx_curr_state_reg\[$b\]"]] }
say $o "== mapping (ILA bit <- core 2 signal: net)"
set changed {}; set n 0; set skipped 0
foreach m $map {
    lassign $m pr bit what net
    set ipin [get_pins -quiet "u_ila_c1/$pr\[$bit\]"]
    if {![llength $ipin]} { say $o "  SKIP $pr\[$bit\] ($what): ILA pin not found"; incr skipped; continue }
    if {$net eq ""} { say $o "  SKIP $pr\[$bit\] ($what): no net"; incr skipped; continue }
    set old [get_nets -quiet -of_objects $ipin]
    if {[llength $old]} { disconnect_net -objects $ipin }
    if {[catch {connect_net -hierarchical -net $net -objects $ipin} err]} {
        say $o "  SKIP $pr\[$bit\] ($what): connection refused ([string range $err 0 120]); original net restored"
        if {[llength $old]} { catch {connect_net -hierarchical -net $old -objects $ipin} }
        incr skipped; continue
    }
    if {[llength $old]} { lappend changed $old }
    lappend changed $net; incr n
    say $o "  $pr\[$bit\] <- $what: $net   (was [expr {[llength $old] ? $old : {none}}])"
}
say $o "== connected $n bits, skipped $skipped"
set changed [lsort -unique $changed]
route_design -nets [get_nets -quiet $changed]
report_route_status -file $::env(OUT)/route_status.txt
report_timing_summary -max_paths 10 -file $::env(OUT)/timing_eco2.txt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]; set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
say $o "== after ECO: WNS $wns  WHS $whs"
write_checkpoint -force $::env(OUT)/eco2_routed.dcp
write_bitstream -force $::env(OUT)/sixteen_core_noc_v12b_eco2.bit
write_debug_probes -force $::env(OUT)/sixteen_core_noc_v12b_eco2.ltx
close $o
puts "ECO2_DONE"
