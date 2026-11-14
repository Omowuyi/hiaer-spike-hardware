create_pblock pblock_inst_12
add_cells_to_pblock [get_pblocks pblock_inst_12] [get_cells -quiet [list {genblk1[12].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_12] -add {CLOCKREGION_X0Y6:CLOCKREGION_X1Y6}

create_pblock pblock_inst_13
add_cells_to_pblock [get_pblocks pblock_inst_13] [get_cells -quiet [list {genblk1[13].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_13] -add {CLOCKREGION_X2Y6:CLOCKREGION_X3Y6}

create_pblock pblock_inst_14
add_cells_to_pblock [get_pblocks pblock_inst_14] [get_cells -quiet [list {genblk1[14].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_14] -add {CLOCKREGION_X0Y7:CLOCKREGION_X1Y7}

create_pblock pblock_inst_15
add_cells_to_pblock [get_pblocks pblock_inst_15] [get_cells -quiet [list {genblk1[15].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_15] -add {CLOCKREGION_X2Y7:CLOCKREGION_X3Y7}

set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets rxFIFO_in\\.clk1328_in]
