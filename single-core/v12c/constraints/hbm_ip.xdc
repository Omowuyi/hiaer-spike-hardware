
create_clock -period 2.22 [get_ports HBM_REF_CLK_0]
#create_clock -period 10.0 [get_ports APB_0_PCLK]
set_property LOC BLI_HBM_AXI_INTF_X17Y0 [get_cells */ONE_STACK_HBM.hbm_one_stack_intf]



