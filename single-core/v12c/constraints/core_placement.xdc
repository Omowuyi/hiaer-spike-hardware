create_pblock {pblock_genblk1[0].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[0].my_core}] [get_cells -quiet [list {genblk1[0].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[0].my_core}] -add {SLICE_X0Y0:SLICE_X56Y59}
resize_pblock [get_pblocks {pblock_genblk1[0].my_core}] -add {DSP48E2_X0Y0:DSP48E2_X7Y17}
resize_pblock [get_pblocks {pblock_genblk1[0].my_core}] -add {RAMB18_X0Y0:RAMB18_X3Y23}
resize_pblock [get_pblocks {pblock_genblk1[0].my_core}] -add {RAMB36_X0Y0:RAMB36_X3Y11}
resize_pblock [get_pblocks {pblock_genblk1[0].my_core}] -add {URAM288_X0Y0:URAM288_X0Y15}
create_pblock {pblock_genblk1[1].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[1].my_core}] [get_cells -quiet [list {genblk1[1].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[1].my_core}] -add {SLICE_X57Y0:SLICE_X116Y59}
resize_pblock [get_pblocks {pblock_genblk1[1].my_core}] -add {DSP48E2_X8Y0:DSP48E2_X15Y17}
resize_pblock [get_pblocks {pblock_genblk1[1].my_core}] -add {RAMB18_X4Y0:RAMB18_X7Y23}
resize_pblock [get_pblocks {pblock_genblk1[1].my_core}] -add {RAMB36_X4Y0:RAMB36_X7Y11}
resize_pblock [get_pblocks {pblock_genblk1[1].my_core}] -add {URAM288_X1Y0:URAM288_X1Y15}
create_pblock {pblock_genblk1[2].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[2].my_core}] [get_cells -quiet [list {genblk1[2].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[2].my_core}] -add {SLICE_X0Y60:SLICE_X56Y119}
resize_pblock [get_pblocks {pblock_genblk1[2].my_core}] -add {DSP48E2_X0Y18:DSP48E2_X7Y41}
resize_pblock [get_pblocks {pblock_genblk1[2].my_core}] -add {RAMB18_X0Y24:RAMB18_X3Y47}
resize_pblock [get_pblocks {pblock_genblk1[2].my_core}] -add {RAMB36_X0Y12:RAMB36_X3Y23}
resize_pblock [get_pblocks {pblock_genblk1[2].my_core}] -add {URAM288_X0Y16:URAM288_X0Y31}
create_pblock {pblock_genblk1[3].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[3].my_core}] [get_cells -quiet [list {genblk1[3].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[3].my_core}] -add {SLICE_X57Y60:SLICE_X116Y119}
resize_pblock [get_pblocks {pblock_genblk1[3].my_core}] -add {DSP48E2_X8Y18:DSP48E2_X15Y41}
resize_pblock [get_pblocks {pblock_genblk1[3].my_core}] -add {RAMB18_X4Y24:RAMB18_X7Y47}
resize_pblock [get_pblocks {pblock_genblk1[3].my_core}] -add {RAMB36_X4Y12:RAMB36_X7Y23}
resize_pblock [get_pblocks {pblock_genblk1[3].my_core}] -add {URAM288_X1Y16:URAM288_X1Y31}
create_pblock {pblock_genblk1[4].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[4].my_core}] [get_cells -quiet [list {genblk1[4].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[4].my_core}] -add {SLICE_X0Y119:SLICE_X56Y179}
resize_pblock [get_pblocks {pblock_genblk1[4].my_core}] -add {DSP48E2_X0Y42:DSP48E2_X7Y65}
resize_pblock [get_pblocks {pblock_genblk1[4].my_core}] -add {RAMB18_X0Y48:RAMB18_X3Y71}
resize_pblock [get_pblocks {pblock_genblk1[4].my_core}] -add {RAMB36_X0Y24:RAMB36_X3Y35}
resize_pblock [get_pblocks {pblock_genblk1[4].my_core}] -add {URAM288_X0Y32:URAM288_X0Y47}
create_pblock {pblock_genblk1[5].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[5].my_core}] [get_cells -quiet [list {genblk1[5].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[5].my_core}] -add {CLOCKREGION_X2Y2:CLOCKREGION_X3Y2}
create_pblock {pblock_genblk1[6].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[6].my_core}] [get_cells -quiet [list {genblk1[6].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[6].my_core}] -add {SLICE_X0Y180:SLICE_X56Y239}
resize_pblock [get_pblocks {pblock_genblk1[6].my_core}] -add {DSP48E2_X0Y66:DSP48E2_X7Y89}
resize_pblock [get_pblocks {pblock_genblk1[6].my_core}] -add {RAMB18_X0Y72:RAMB18_X3Y95}
resize_pblock [get_pblocks {pblock_genblk1[6].my_core}] -add {RAMB36_X0Y36:RAMB36_X3Y47}
resize_pblock [get_pblocks {pblock_genblk1[6].my_core}] -add {URAM288_X0Y48:URAM288_X0Y63}
create_pblock {pblock_genblk1[7].my_core}
add_cells_to_pblock [get_pblocks {pblock_genblk1[7].my_core}] [get_cells -quiet [list {genblk1[7].my_core}]]
resize_pblock [get_pblocks {pblock_genblk1[7].my_core}] -add {SLICE_X57Y180:SLICE_X116Y239}
resize_pblock [get_pblocks {pblock_genblk1[7].my_core}] -add {DSP48E2_X8Y66:DSP48E2_X15Y89}
resize_pblock [get_pblocks {pblock_genblk1[7].my_core}] -add {RAMB18_X4Y72:RAMB18_X7Y95}
resize_pblock [get_pblocks {pblock_genblk1[7].my_core}] -add {RAMB36_X4Y36:RAMB36_X7Y47}
resize_pblock [get_pblocks {pblock_genblk1[7].my_core}] -add {URAM288_X1Y48:URAM288_X1Y63}

create_pblock pblock_inst
add_cells_to_pblock [get_pblocks pblock_inst] [get_cells -quiet [list {genblk1[8].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst] -add {SLICE_X0Y240:SLICE_X56Y299}
resize_pblock [get_pblocks pblock_inst] -add {DSP48E2_X0Y90:DSP48E2_X7Y113}
resize_pblock [get_pblocks pblock_inst] -add {RAMB18_X0Y96:RAMB18_X3Y119}
resize_pblock [get_pblocks pblock_inst] -add {RAMB36_X0Y48:RAMB36_X3Y59}
resize_pblock [get_pblocks pblock_inst] -add {URAM288_X0Y64:URAM288_X0Y79}
create_pblock pblock_inst_1
add_cells_to_pblock [get_pblocks pblock_inst_1] [get_cells -quiet [list {genblk1[9].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_1] -add {SLICE_X57Y240:SLICE_X116Y299}
resize_pblock [get_pblocks pblock_inst_1] -add {DSP48E2_X8Y90:DSP48E2_X15Y113}
resize_pblock [get_pblocks pblock_inst_1] -add {RAMB18_X4Y96:RAMB18_X7Y119}
resize_pblock [get_pblocks pblock_inst_1] -add {RAMB36_X4Y48:RAMB36_X7Y59}
resize_pblock [get_pblocks pblock_inst_1] -add {URAM288_X1Y64:URAM288_X1Y79}
create_pblock pblock_inst_2
add_cells_to_pblock [get_pblocks pblock_inst_2] [get_cells -quiet [list {genblk1[10].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_2] -add {SLICE_X0Y300:SLICE_X56Y359}
resize_pblock [get_pblocks pblock_inst_2] -add {DSP48E2_X0Y114:DSP48E2_X7Y137}
resize_pblock [get_pblocks pblock_inst_2] -add {RAMB18_X0Y120:RAMB18_X3Y143}
resize_pblock [get_pblocks pblock_inst_2] -add {RAMB36_X0Y60:RAMB36_X3Y71}
resize_pblock [get_pblocks pblock_inst_2] -add {URAM288_X0Y80:URAM288_X0Y95}
create_pblock pblock_inst_3
add_cells_to_pblock [get_pblocks pblock_inst_3] [get_cells -quiet [list {genblk1[11].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_3] -add {SLICE_X57Y300:SLICE_X116Y359}
resize_pblock [get_pblocks pblock_inst_3] -add {DSP48E2_X8Y114:DSP48E2_X15Y137}
resize_pblock [get_pblocks pblock_inst_3] -add {RAMB18_X4Y120:RAMB18_X7Y143}
resize_pblock [get_pblocks pblock_inst_3] -add {RAMB36_X4Y60:RAMB36_X7Y71}
resize_pblock [get_pblocks pblock_inst_3] -add {URAM288_X1Y80:URAM288_X1Y95}
create_pblock pblock_inst_4
add_cells_to_pblock [get_pblocks pblock_inst_4] [get_cells -quiet [list {genblk1[12].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_4] -add {SLICE_X0Y360:SLICE_X56Y419}
resize_pblock [get_pblocks pblock_inst_4] -add {DSP48E2_X0Y138:DSP48E2_X7Y161}
resize_pblock [get_pblocks pblock_inst_4] -add {RAMB18_X0Y144:RAMB18_X3Y167}
resize_pblock [get_pblocks pblock_inst_4] -add {RAMB36_X0Y72:RAMB36_X3Y83}
resize_pblock [get_pblocks pblock_inst_4] -add {URAM288_X0Y96:URAM288_X0Y111}
create_pblock pblock_inst_5
add_cells_to_pblock [get_pblocks pblock_inst_5] [get_cells -quiet [list {genblk1[13].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_5] -add {SLICE_X57Y360:SLICE_X116Y419}
resize_pblock [get_pblocks pblock_inst_5] -add {DSP48E2_X8Y138:DSP48E2_X15Y161}
resize_pblock [get_pblocks pblock_inst_5] -add {RAMB18_X4Y144:RAMB18_X7Y167}
resize_pblock [get_pblocks pblock_inst_5] -add {RAMB36_X4Y72:RAMB36_X7Y83}
resize_pblock [get_pblocks pblock_inst_5] -add {URAM288_X1Y96:URAM288_X1Y111}
create_pblock pblock_inst_6
add_cells_to_pblock [get_pblocks pblock_inst_6] [get_cells -quiet [list {genblk1[14].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_6] -add {SLICE_X0Y420:SLICE_X56Y479}
resize_pblock [get_pblocks pblock_inst_6] -add {DSP48E2_X0Y162:DSP48E2_X7Y185}
resize_pblock [get_pblocks pblock_inst_6] -add {RAMB18_X0Y168:RAMB18_X3Y191}
resize_pblock [get_pblocks pblock_inst_6] -add {RAMB36_X0Y84:RAMB36_X3Y95}
resize_pblock [get_pblocks pblock_inst_6] -add {URAM288_X0Y112:URAM288_X0Y127}
create_pblock pblock_inst_7
add_cells_to_pblock [get_pblocks pblock_inst_7] [get_cells -quiet [list {genblk1[15].my_core/inst}]]
resize_pblock [get_pblocks pblock_inst_7] -add {SLICE_X57Y420:SLICE_X116Y479}
resize_pblock [get_pblocks pblock_inst_7] -add {DSP48E2_X8Y162:DSP48E2_X15Y185}
resize_pblock [get_pblocks pblock_inst_7] -add {RAMB18_X4Y168:RAMB18_X7Y191}
resize_pblock [get_pblocks pblock_inst_7] -add {RAMB36_X4Y84:RAMB36_X7Y95}
resize_pblock [get_pblocks pblock_inst_7] -add {URAM288_X1Y112:URAM288_X1Y127}
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets rxFIFO_in\\.clk1148_in]
