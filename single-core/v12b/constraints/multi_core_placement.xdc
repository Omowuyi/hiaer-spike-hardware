# create_pblock pblock_inst
# add_cells_to_pblock [get_pblocks pblock_inst] [get_cells -quiet [list {genblk1[0].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst] -add {SLICE_X0Y0:SLICE_X56Y59}
# resize_pblock [get_pblocks pblock_inst] -add {DSP48E2_X0Y0:DSP48E2_X7Y17}
# resize_pblock [get_pblocks pblock_inst] -add {RAMB18_X0Y0:RAMB18_X3Y23}
# resize_pblock [get_pblocks pblock_inst] -add {RAMB36_X0Y0:RAMB36_X3Y11}
# resize_pblock [get_pblocks pblock_inst] -add {URAM288_X0Y0:URAM288_X0Y15}
# create_pblock pblock_inst_1
# add_cells_to_pblock [get_pblocks pblock_inst_1] [get_cells -quiet [list {genblk1[1].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_1] -add {SLICE_X57Y0:SLICE_X116Y59}
# resize_pblock [get_pblocks pblock_inst_1] -add {DSP48E2_X8Y0:DSP48E2_X15Y17}
# resize_pblock [get_pblocks pblock_inst_1] -add {RAMB18_X4Y0:RAMB18_X7Y23}
# resize_pblock [get_pblocks pblock_inst_1] -add {RAMB36_X4Y0:RAMB36_X7Y11}
# resize_pblock [get_pblocks pblock_inst_1] -add {URAM288_X1Y0:URAM288_X1Y15}
# create_pblock pblock_inst_2
# add_cells_to_pblock [get_pblocks pblock_inst_2] [get_cells -quiet [list {genblk1[2].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_2] -add {SLICE_X0Y60:SLICE_X56Y119}
# resize_pblock [get_pblocks pblock_inst_2] -add {DSP48E2_X0Y18:DSP48E2_X7Y41}
# resize_pblock [get_pblocks pblock_inst_2] -add {RAMB18_X0Y24:RAMB18_X3Y47}
# resize_pblock [get_pblocks pblock_inst_2] -add {RAMB36_X0Y12:RAMB36_X3Y23}
# resize_pblock [get_pblocks pblock_inst_2] -add {URAM288_X0Y16:URAM288_X0Y31}
# create_pblock pblock_inst_3
# add_cells_to_pblock [get_pblocks pblock_inst_3] [get_cells -quiet [list {genblk1[3].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_3] -add {SLICE_X57Y60:SLICE_X116Y119}
# resize_pblock [get_pblocks pblock_inst_3] -add {DSP48E2_X8Y18:DSP48E2_X15Y41}
# resize_pblock [get_pblocks pblock_inst_3] -add {RAMB18_X4Y24:RAMB18_X7Y47}
# resize_pblock [get_pblocks pblock_inst_3] -add {RAMB36_X4Y12:RAMB36_X7Y23}
# resize_pblock [get_pblocks pblock_inst_3] -add {URAM288_X1Y16:URAM288_X1Y31}
# create_pblock pblock_inst_4
# add_cells_to_pblock [get_pblocks pblock_inst_4] [get_cells -quiet [list {genblk1[4].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_4] -add {SLICE_X0Y120:SLICE_X56Y179}
# resize_pblock [get_pblocks pblock_inst_4] -add {DSP48E2_X0Y42:DSP48E2_X7Y65}
# resize_pblock [get_pblocks pblock_inst_4] -add {RAMB18_X0Y48:RAMB18_X3Y71}
# resize_pblock [get_pblocks pblock_inst_4] -add {RAMB36_X0Y24:RAMB36_X3Y35}
# resize_pblock [get_pblocks pblock_inst_4] -add {URAM288_X0Y32:URAM288_X0Y47}
# create_pblock pblock_inst_5
# add_cells_to_pblock [get_pblocks pblock_inst_5] [get_cells -quiet [list {genblk1[5].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_5] -add {SLICE_X57Y120:SLICE_X116Y179}
# resize_pblock [get_pblocks pblock_inst_5] -add {DSP48E2_X8Y42:DSP48E2_X15Y65}
# resize_pblock [get_pblocks pblock_inst_5] -add {RAMB18_X4Y48:RAMB18_X7Y71}
# resize_pblock [get_pblocks pblock_inst_5] -add {RAMB36_X4Y24:RAMB36_X7Y35}
# resize_pblock [get_pblocks pblock_inst_5] -add {URAM288_X1Y32:URAM288_X1Y47}
# create_pblock pblock_inst_6
# add_cells_to_pblock [get_pblocks pblock_inst_6] [get_cells -quiet [list {genblk1[6].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_6] -add {SLICE_X0Y180:SLICE_X56Y239}
# resize_pblock [get_pblocks pblock_inst_6] -add {DSP48E2_X0Y66:DSP48E2_X7Y89}
# resize_pblock [get_pblocks pblock_inst_6] -add {RAMB18_X0Y72:RAMB18_X3Y95}
# resize_pblock [get_pblocks pblock_inst_6] -add {RAMB36_X0Y36:RAMB36_X3Y47}
# resize_pblock [get_pblocks pblock_inst_6] -add {URAM288_X0Y48:URAM288_X0Y63}
# create_pblock pblock_inst_7
# add_cells_to_pblock [get_pblocks pblock_inst_7] [get_cells -quiet [list {genblk1[7].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_7] -add {SLICE_X57Y180:SLICE_X116Y239}
# resize_pblock [get_pblocks pblock_inst_7] -add {DSP48E2_X8Y66:DSP48E2_X15Y89}
# resize_pblock [get_pblocks pblock_inst_7] -add {RAMB18_X4Y72:RAMB18_X7Y95}
# resize_pblock [get_pblocks pblock_inst_7] -add {RAMB36_X4Y36:RAMB36_X7Y47}
# resize_pblock [get_pblocks pblock_inst_7] -add {URAM288_X1Y48:URAM288_X1Y63}
# create_pblock pblock_inst_8
# add_cells_to_pblock [get_pblocks pblock_inst_8] [get_cells -quiet [list {genblk1[8].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_8] -add {SLICE_X0Y240:SLICE_X56Y299}
# resize_pblock [get_pblocks pblock_inst_8] -add {DSP48E2_X0Y90:DSP48E2_X7Y113}
# resize_pblock [get_pblocks pblock_inst_8] -add {RAMB18_X0Y96:RAMB18_X3Y119}
# resize_pblock [get_pblocks pblock_inst_8] -add {RAMB36_X0Y48:RAMB36_X3Y59}
# resize_pblock [get_pblocks pblock_inst_8] -add {URAM288_X0Y64:URAM288_X0Y79}
# create_pblock pblock_inst_9
# add_cells_to_pblock [get_pblocks pblock_inst_9] [get_cells -quiet [list {genblk1[9].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_9] -add {SLICE_X57Y240:SLICE_X116Y299}
# resize_pblock [get_pblocks pblock_inst_9] -add {DSP48E2_X8Y90:DSP48E2_X15Y113}
# resize_pblock [get_pblocks pblock_inst_9] -add {RAMB18_X4Y96:RAMB18_X7Y119}
# resize_pblock [get_pblocks pblock_inst_9] -add {RAMB36_X4Y48:RAMB36_X7Y59}
# resize_pblock [get_pblocks pblock_inst_9] -add {URAM288_X1Y64:URAM288_X1Y79}
# create_pblock pblock_inst_10
# add_cells_to_pblock [get_pblocks pblock_inst_10] [get_cells -quiet [list {genblk1[10].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_10] -add {SLICE_X0Y300:SLICE_X56Y359}
# resize_pblock [get_pblocks pblock_inst_10] -add {DSP48E2_X0Y114:DSP48E2_X7Y137}
# resize_pblock [get_pblocks pblock_inst_10] -add {RAMB18_X0Y120:RAMB18_X3Y143}
# resize_pblock [get_pblocks pblock_inst_10] -add {RAMB36_X0Y60:RAMB36_X3Y71}
# resize_pblock [get_pblocks pblock_inst_10] -add {URAM288_X0Y80:URAM288_X0Y95}
# create_pblock pblock_inst_11
# add_cells_to_pblock [get_pblocks pblock_inst_11] [get_cells -quiet [list {genblk1[11].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_11] -add {SLICE_X57Y300:SLICE_X116Y359}
# resize_pblock [get_pblocks pblock_inst_11] -add {DSP48E2_X8Y114:DSP48E2_X15Y137}
# resize_pblock [get_pblocks pblock_inst_11] -add {RAMB18_X4Y120:RAMB18_X7Y143}
# resize_pblock [get_pblocks pblock_inst_11] -add {RAMB36_X4Y60:RAMB36_X7Y71}
# resize_pblock [get_pblocks pblock_inst_11] -add {URAM288_X1Y80:URAM288_X1Y95}
# create_pblock pblock_inst_12
# add_cells_to_pblock [get_pblocks pblock_inst_12] [get_cells -quiet [list {genblk1[12].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_12] -add {SLICE_X0Y360:SLICE_X56Y419}
# resize_pblock [get_pblocks pblock_inst_12] -add {DSP48E2_X0Y138:DSP48E2_X7Y161}
# resize_pblock [get_pblocks pblock_inst_12] -add {RAMB18_X0Y144:RAMB18_X3Y167}
# resize_pblock [get_pblocks pblock_inst_12] -add {RAMB36_X0Y72:RAMB36_X3Y83}
# resize_pblock [get_pblocks pblock_inst_12] -add {URAM288_X0Y96:URAM288_X0Y111}
# create_pblock pblock_inst_13
# add_cells_to_pblock [get_pblocks pblock_inst_13] [get_cells -quiet [list {genblk1[13].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_13] -add {SLICE_X57Y360:SLICE_X116Y419}
# resize_pblock [get_pblocks pblock_inst_13] -add {DSP48E2_X8Y138:DSP48E2_X15Y161}
# resize_pblock [get_pblocks pblock_inst_13] -add {RAMB18_X4Y144:RAMB18_X7Y167}
# resize_pblock [get_pblocks pblock_inst_13] -add {RAMB36_X4Y72:RAMB36_X7Y83}
# resize_pblock [get_pblocks pblock_inst_13] -add {URAM288_X1Y96:URAM288_X1Y111}
# create_pblock pblock_inst_14
# add_cells_to_pblock [get_pblocks pblock_inst_14] [get_cells -quiet [list {genblk1[14].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_14] -add {SLICE_X0Y420:SLICE_X56Y479}
# resize_pblock [get_pblocks pblock_inst_14] -add {DSP48E2_X0Y162:DSP48E2_X7Y185}
# resize_pblock [get_pblocks pblock_inst_14] -add {RAMB18_X0Y168:RAMB18_X3Y191}
# resize_pblock [get_pblocks pblock_inst_14] -add {RAMB36_X0Y84:RAMB36_X3Y95}
# resize_pblock [get_pblocks pblock_inst_14] -add {URAM288_X0Y112:URAM288_X0Y127}
# create_pblock pblock_inst_15
# add_cells_to_pblock [get_pblocks pblock_inst_15] [get_cells -quiet [list {genblk1[15].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_15] -add {SLICE_X57Y420:SLICE_X116Y479}
# resize_pblock [get_pblocks pblock_inst_15] -add {DSP48E2_X8Y162:DSP48E2_X15Y185}
# resize_pblock [get_pblocks pblock_inst_15] -add {RAMB18_X4Y168:RAMB18_X7Y191}
# resize_pblock [get_pblocks pblock_inst_15] -add {RAMB36_X4Y84:RAMB36_X7Y95}
# resize_pblock [get_pblocks pblock_inst_15] -add {URAM288_X1Y112:URAM288_X1Y127}

# set_clock_groups -asynchronous -group clk_out1* -group clk_out2* -group clk_out3* -group refclk* -group pcie_clk*
# connect_debug_port dbg_hub/clk [get_nets rxFIFO_in\\.clk1328_in]

# create_pblock pblock_inst_23
# add_cells_to_pblock [get_pblocks pblock_inst_23] [get_cells -quiet [list {genblk1[23].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_23] -add {CLOCKREGION_X6Y5:CLOCKREGION_X7Y5}
# ##create_pblock pblock_inst_24
# ##add_cells_to_pblock [get_pblocks pblock_inst_24] [get_cells -quiet [list {genblk1[24].my_core/inst}]]
# ##resize_pblock [get_pblocks pblock_inst_24] -add {CLOCKREGION_X4Y6:CLOCKREGION_X5Y6}
# ##create_pblock pblock_inst_25
# ##add_cells_to_pblock [get_pblocks pblock_inst_25] [get_cells -quiet [list {genblk1[25].my_core/inst}]]
# ##resize_pblock [get_pblocks pblock_inst_25] -add {CLOCKREGION_X6Y6:CLOCKREGION_X7Y6}
# ##create_pblock pblock_inst_26
# ##add_cells_to_pblock [get_pblocks pblock_inst_26] [get_cells -quiet [list {genblk1[26].my_core/inst}]]
# ##resize_pblock [get_pblocks pblock_inst_26] -add {CLOCKREGION_X4Y7:CLOCKREGION_X5Y7}
# ##create_pblock pblock_inst_27
# ##add_cells_to_pblock [get_pblocks pblock_inst_27] [get_cells -quiet [list {genblk1[27].my_core/inst}]]
# ##resize_pblock [get_pblocks pblock_inst_27] -add {CLOCKREGION_X6Y7:CLOCKREGION_X7Y7}
# ## create_pblock pblock_inst_28
# ## add_cells_to_pblock [get_pblocks pblock_inst_28] [get_cells -quiet [list {genblk1[28].my_core/inst}]]
# ## resize_pblock [get_pblocks pblock_inst_28] -add {CLOCKREGION_X4Y8:CLOCKREGION_X5Y8}
# ## create_pblock pblock_inst_30
# ## add_cells_to_pblock [get_pblocks pblock_inst_30] [get_cells -quiet [list {genblk1[30].my_core/inst}]]
# ## resize_pblock [get_pblocks pblock_inst_30] -add {CLOCKREGION_X4Y9:CLOCKREGION_X5Y9}
# ## create_pblock pblock_inst_31
# ## add_cells_to_pblock [get_pblocks pblock_inst_31] [get_cells -quiet [list {genblk1[31].my_core/inst}]]
# ## resize_pblock [get_pblocks pblock_inst_31] -add {CLOCKREGION_X6Y9:CLOCKREGION_X7Y9}
# create_pblock pblock_inst_16
# add_cells_to_pblock [get_pblocks pblock_inst_16] [get_cells -quiet [list {genblk1[16].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_16] -add {CLOCKREGION_X4Y0:CLOCKREGION_X7Y1}
# create_pblock pblock_inst_17
# add_cells_to_pblock [get_pblocks pblock_inst_17] [get_cells -quiet [list {genblk1[17].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_17] -add {CLOCKREGION_X4Y2:CLOCKREGION_X7Y3}
# create_pblock pblock_inst_18
# add_cells_to_pblock [get_pblocks pblock_inst_18] [get_cells -quiet [list {genblk1[18].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_18] -add {CLOCKREGION_X4Y4:CLOCKREGION_X7Y4}
# create_pblock pblock_inst_19
# add_cells_to_pblock [get_pblocks pblock_inst_19] [get_cells -quiet [list {genblk1[19].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_19] -add {CLOCKREGION_X4Y5:CLOCKREGION_X5Y5}
# create_pblock pblock_inst_20
# add_cells_to_pblock [get_pblocks pblock_inst_20] [get_cells -quiet [list {genblk1[20].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_20] -add {CLOCKREGION_X4Y6:CLOCKREGION_X5Y6}
# create_pblock pblock_inst_21
# add_cells_to_pblock [get_pblocks pblock_inst_21] [get_cells -quiet [list {genblk1[21].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_21] -add {CLOCKREGION_X6Y6:CLOCKREGION_X7Y6}
# create_pblock pblock_inst_22
# add_cells_to_pblock [get_pblocks pblock_inst_22] [get_cells -quiet [list {genblk1[22].my_core/inst}]]
# resize_pblock [get_pblocks pblock_inst_22] -add {CLOCKREGION_X4Y7:CLOCKREGION_X5Y7}
# ## create_pblock pblock_inst_29
# ## add_cells_to_pblock [get_pblocks pblock_inst_29] [get_cells -quiet [list {genblk1[29].my_core/inst}]]
# ## resize_pblock [get_pblocks pblock_inst_29] -add {CLOCKREGION_X6Y8:CLOCKREGION_X7Y8}
# set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
# set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
# connect_debug_port dbg_hub/clk [get_nets after_switch\\.aclk1760_in]
