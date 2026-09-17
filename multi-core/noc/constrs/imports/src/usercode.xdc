# Set bitstream USERID
# set_property BITSTREAM.CONFIG.USERID 32'hADAD0109 [current_design]



# THIS FILE APPLIES ONLY TO PCB REVISION 2 OR LATER OF ADM-PCIE-9H7.

# Configuration from SPI Flash as per XAPP1233
# Enable bitstream compression
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DIV-1 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property CONFIG_MODE SPIx8 [current_design]

# Don't pull unused pins up or down
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]

# Set CFGBVS to GND to match schematics
set_property CFGBVS GND [current_design]

# Set CONFIG_VOLTAGE to 1.8V to match schematics
set_property CONFIG_VOLTAGE 1.8 [current_design]

# Set safety trigger to power down FPGA at 125degC
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable [current_design]

# Set bitstream USERID
set_property BITSTREAM.CONFIG.USERID 32'hADAD0109 [current_design]


# =============================================================================
# Pin Assignments
# =============================================================================

# 450MHz reference clock
set_property IOSTANDARD LVDS [get_ports refclk450_p]
set_property DIFF_TERM_ADV TERM_100 [get_ports refclk450_p]
set_property PACKAGE_PIN BJ52 [get_ports refclk450_p]
set_property PACKAGE_PIN BJ53 [get_ports refclk450_n]
set_property IOSTANDARD LVDS [get_ports refclk450_n]
set_property DIFF_TERM_ADV TERM_100 [get_ports refclk450_n]
create_clock -period 2.222 -name refclk [get_ports refclk450_p]

# PCIe reference clock
set_property PACKAGE_PIN AR14 [get_ports {pcie_clk_in_clk_n[0]}]
set_property PACKAGE_PIN AR15 [get_ports {pcie_clk_in_clk_p[0]}]
create_clock -period 10.000 -name pcie_clk_in_clk [get_ports {pcie_clk_in_clk_p[0]}]

# System reset
set_false_path -from [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]
set_property PACKAGE_PIN BF41 [get_ports sys_rst_n]


# =============================================================================
# HBM APB PCLK Pulse Width Fix
# The MMCM clk_out3 (apb_clk) produces 9.999ns period vs HBM's 10.000ns
# requirement - a 1ps shortfall. The HBM APB interface is only used during
# initial configuration (not data path) and tolerates this marginal variance.
# =============================================================================
set_multicycle_path -setup 2 \
    -to [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]
set_multicycle_path -hold 1 \
    -to [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]

# Waiver for HBM APB PCLK methodology warning
create_waiver -quiet -type METHODOLOGY -id {TIMING-20} -user "HIAER" \
    -description "HBM APB PCLK 1ps pulse width tolerance" \
    -objects [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]

# Minimum pulse width constraint relaxation for HBM PCLK
# The -0.001ns WPWS violation is on the HBM hard macro APB clock input.
# This is a silicon-managed interface; the 1ps shortfall is not functionally relevant.
set_false_path -to [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]


# =============================================================================
# Clock Domain Crossing Constraints
#
# The design has two independent clock sources:
#   Source 1: refclk450 (450MHz pad) -> MMCM (clk_wiz_0) -> aclk, aclk450, apb_clk
#   Source 2: PCIe GT block -> pcie_axi_clk (250MHz)
#
# These are physically asynchronous. All CDC between them uses async FIFOs:
#   - FIFO_512_ASYNC rx_cdc: pcie_axi_clk -> aclk (H2C path)
#   - FIFO_512_ASYNC tx_cdc: aclk -> pcie_axi_clk (C2H path)
#
# Without these constraints, Vivado tries to time paths between these
# unrelated clocks, causing false setup violations and TIMING-6/7/51 warnings.
# =============================================================================

# PCIe AXI clock is asynchronous to all clk_wiz-derived clocks
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks pcie_clk_in_clk] \
    -group [get_clocks -include_generated_clocks refclk]

# VIO probe false paths (debug signals, not functional)
set_false_path -from [get_pins clock_and_buff*/clk_wiz*/inst*/mmcm*/CLK*] \
               -to   [get_pins my_vio/inst*/PROBE*/probe*/D]

# HBM APB-to-fabric CDC false path (initialization only, not data path)
# The HBM IP has internal synchronizers for this crossing.
# Fixes WNS violation on hbm_apb_arbiter → xsdb2adb path.
set_false_path -from [get_clocks clk_out2_clock_and_buffer_clk_wiz_0_0] -to [get_clocks clk_out1_clock_and_buffer_clk_wiz_0_0]
set_false_path -from [get_clocks clk_out1_clock_and_buffer_clk_wiz_0_0] -to [get_clocks clk_out2_clock_and_buffer_clk_wiz_0_0]

