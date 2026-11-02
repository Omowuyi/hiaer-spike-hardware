# regen_slice.tcl -- the hbm_register_slice IP, copied out of the project, reconfigured and regenerated in memory.
# Mode 15 (Multi_SLR_Crossing) on all five channels, one SLR crossing (as today), then one pipeline stage on the HBM
# ("slave") side of every channel.  Env: SLICE_DIR, PART.
create_project -in_memory -part $::env(PART)
set_property target_language Verilog [current_project]
read_ip $::env(SLICE_DIR)/hbm_register_slice.xci
set ip [get_ips hbm_register_slice]
if {[get_property IS_LOCKED $ip]} { puts "SLICE_ABORT: IP locked: [get_property LOCK_DETAILS $ip]"; exit 1 }
foreach p {REG_AW REG_AR REG_W REG_R REG_B NUM_SLR_CROSSINGS} { puts "BEFORE $p=[get_property CONFIG.$p $ip]" }
set_property -dict [list CONFIG.REG_AW {15} CONFIG.REG_AR {15} CONFIG.REG_W {15} CONFIG.REG_R {15} CONFIG.REG_B {15} CONFIG.NUM_SLR_CROSSINGS {1}] $ip
set_property -dict [list CONFIG.PIPELINES_SLAVE_AW {1} CONFIG.PIPELINES_SLAVE_AR {1} CONFIG.PIPELINES_SLAVE_W {1} CONFIG.PIPELINES_SLAVE_R {1} CONFIG.PIPELINES_SLAVE_B {1}] $ip
foreach p {REG_AW REG_AR REG_W REG_R REG_B NUM_SLR_CROSSINGS PIPELINES_SLAVE_AW PIPELINES_SLAVE_AR PIPELINES_SLAVE_W PIPELINES_SLAVE_R PIPELINES_SLAVE_B PIPELINES_MASTER_AW PIPELINES_MASTER_AR PIPELINES_MASTER_W PIPELINES_MASTER_R PIPELINES_MASTER_B PROTOCOL ADDR_WIDTH DATA_WIDTH ID_WIDTH} {
    puts "AFTER $p=[get_property CONFIG.$p $ip]"
}
generate_target {instantiation_template simulation synthesis} $ip
puts "SLICE_REGEN_DONE"
