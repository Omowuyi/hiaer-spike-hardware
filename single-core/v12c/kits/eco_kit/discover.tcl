# discover.tcl -- v12b routed design, read-only: everything the ECO needs to observe core 2 with v12b's exact placement.
# 1 the existing ILA(s): probe ports, widths, current nets, clock; 2 core 2's AXI handshake nets on both sides of its
# register slice; 3 core 2's HBM-processor and command-interpreter state registers; 4 core 2's command-FIFO flags.
open_checkpoint $::env(DCP)
set o [open $::env(OUT)/discover.txt w]
puts $o "== ILA cores"
foreach ila [get_cells -hier -quiet -filter {REF_NAME =~ *ila* && IS_PRIMITIVE == 0}] {
    if {[regexp {/} $ila] && ![regexp {^u_ila} $ila]} { continue }
    puts $o "ILA $ila  (REF [get_property REF_NAME $ila])"
    set ck [get_nets -quiet -of_objects [get_pins -quiet $ila/clk]]
    puts $o "  clk net: $ck  clock: [get_clocks -quiet -of_objects [get_pins -quiet $ila/clk]]"
    set buses [dict create]
    foreach p [get_pins -quiet $ila/probe*] { regexp {^(.*?)(\[\d+\])?$} [get_property NAME $p] -> b; dict incr buses $b }
    foreach b [lsort -dictionary [dict keys $buses]] {
        set p0 [lindex [get_pins -quiet "$b*"] 0]
        puts $o "  [file tail $b]  width [dict get $buses $b]  first bit net: [get_nets -quiet -of_objects $p0]"
    }
}
puts $o "== core 2 register slice: handshake pins and nets"
set sl {genblk3[2].my_core/axi_slice}
foreach p [lsort -dictionary [get_pins -quiet -filter {NAME =~ *valid* || NAME =~ *ready*} "$sl/*"]] {
    puts $o "  [get_property NAME $p]  net [get_nets -quiet -of_objects $p]  clock [get_clocks -quiet -of_objects $p]"
}
puts $o "== core 2 state registers (HBM processor, command interpreter)"
foreach c [lsort -dictionary [get_cells -hier -quiet -filter {NAME =~ "genblk3[2].my_core/*" && IS_SEQUENTIAL && (NAME =~ *curr_state* || NAME =~ *FSM_onehot*state* || NAME =~ *rx_state* || NAME =~ *tx_state*)}]] {
    puts $o "  $c"
}
puts $o "== core 2 FIFO flags (empty/full)"
foreach c [lsort -dictionary [get_cells -hier -quiet -filter {NAME =~ "genblk3[2].my_core/*" && IS_SEQUENTIAL && (NAME =~ *ram_empty_i_reg || NAME =~ *ram_full_i_reg || NAME =~ *empty_reg || NAME =~ *full_reg)}]] {
    puts $o "  $c"
}
close $o
puts "DISCOVER_DONE"
