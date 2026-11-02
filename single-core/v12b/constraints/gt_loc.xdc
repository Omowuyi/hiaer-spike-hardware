#==============================================================================
# FireFly transceiver placement, all four ports.
#
# The Aurora IP offers only Quad_X1Y0 through Quad_X1Y11 because no board file
# is installed, so every core defaults to Quad_X1Y0 and none of them lands on
# the quad its pins belong to. Placement is an implementation property, so this
# is corrected by constraint rather than by reconfiguring the IP.
#
# The map below was read from the part with get_sites on the package pins named
# in hiaer_multicore_firefly_complete.xdc, and it matches the transceiver table
# on page 63 of the CRI hardware manual:
#
#   port  refclk pin  lane 0 pin   quad  common      channels
#   ff4   T13         L7           234   X1Y10       X1Y40..43
#   ff5   P13         G7           235   X1Y11       X1Y44..47
#   ff6   P42         G48          135   X0Y11       X0Y44..47
#   ff7   T42         L48          134   X0Y10       X0Y40..43
#
# GT serial pins are dedicated silicon: a channel placed anywhere else cannot
# reach them. PCIe occupies X1Y4 to X1Y15, so none of these four quads
# collides with it.
#==============================================================================

# instance path -> {first channel index, common}
dict set ff_map ff_subsys/gen_all_ports.u_aurora_port4/gen_aurora_port4.u_aurora {X1Y 40 GTYE4_COMMON_X1Y10}
dict set ff_map ff_subsys/gen_all_ports.u_aurora_port5/gen_aurora_port5.u_aurora {X1Y 44 GTYE4_COMMON_X1Y11}
dict set ff_map ff_subsys/gen_all_ports.u_aurora_port6/gen_aurora_port6.u_aurora {X0Y 44 GTYE4_COMMON_X0Y11}
dict set ff_map ff_subsys/u_aurora_port7/gen_aurora_port7.u_aurora               {X0Y 40 GTYE4_COMMON_X0Y10}

dict for {inst spec} $ff_map {
    lassign $spec col base common

    set chans [get_cells -quiet -hier -filter \
                  "REF_NAME =~ GTYE4_CHANNEL* && NAME =~ $inst/*"]
    if {[llength $chans] != 4} {
        puts "WARNING: $inst has [llength $chans] channels, expected 4; skipped"
        continue
    }
    # lane i must land on base+i so that lane 0 owns the txp\[0\] pin
    for {set i 0} {$i < 4} {incr i} {
        set hit 0
        foreach c $chans {
            if {[string match "*gen_gtye4_channel_inst\[$i\]*" $c]} {
                set site "GTYE4_CHANNEL_${col}[expr {$base + $i}]"
                set_property LOC $site [get_cells $c]
                puts "  [file tail $inst] lane $i -> $site"
                set hit 1
            }
        }
        if {!$hit} { puts "WARNING: $inst lane $i not found" }
    }

    set cm [get_cells -quiet -hier -filter \
               "REF_NAME =~ GTYE4_COMMON* && NAME =~ $inst/*"]
    if {[llength $cm] == 1} {
        set_property LOC $common [get_cells $cm]
        puts "  [file tail $inst] common -> $common"
    } else {
        puts "WARNING: $inst has [llength $cm] commons, expected 1"
    }
}
