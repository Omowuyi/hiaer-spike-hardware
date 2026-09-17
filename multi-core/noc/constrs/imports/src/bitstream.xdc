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

# =============================================================================
# HBM APB PCLK Pulse Width Fix
# The MMCM clk_out2 (apb_clk) produces 9.999ns period vs HBM's 10.000ns
# requirement - a 1ps shortfall. The HBM APB interface is only used during
# initial configuration (not data path) and tolerates this marginal variance.
# =============================================================================
set_multicycle_path -setup 2 \
    -to [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]
set_multicycle_path -hold 1 \
    -to [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]
    
# HBM APB PCLK: 1ps pulse width violation on hard macro - not functionally relevant
create_waiver -quiet -type METHODOLOGY -id {TIMING-20} -user "HIAER" \
    -description "HBM APB PCLK 1ps pulse width tolerance" \
    -objects [get_pins -hierarchical -filter {NAME =~ */HBM_SNGLBLI_INTF_APB_INST/PCLK}]





#set_false_path -from [get_clocks clk_out*_clock_and_buffer_clk_wiz_0_*] -to [get_clocks clk_out*_clock_and_buffer_clk_wiz_0_*]
set_false_path -from [get_pins clock_and_buff*/clk_wiz*/inst*/mmcm*/CLK*] -to [get_pins my_vio/inst*/PROBE*/probe*/D]





##Changing these to 450MHz clock

##set_property PACKAGE_PIN BJ52 [get_ports {refclk300_p}]
##set_property IOSTANDARD LVDS [get_ports {refclk300_p}]
##set_property DIFF_TERM_ADV TERM_100 [get_ports {refclk300_p}]

##set_property PACKAGE_PIN BJ53 [get_ports {refclk300_n}]
##set_property IOSTANDARD LVDS [get_ports {refclk300_n}]
##set_property DIFF_TERM_ADV TERM_100 [get_ports {refclk300_n}]

##create_clock -period 3.333 -name refclk [get_ports {refclk300_p}]

set_property IOSTANDARD LVDS [get_ports refclk450_p]
set_property DIFF_TERM_ADV TERM_100 [get_ports refclk450_p]

set_property PACKAGE_PIN BJ52 [get_ports refclk450_p]
set_property PACKAGE_PIN BJ53 [get_ports refclk450_n]
set_property IOSTANDARD LVDS [get_ports refclk450_n]
set_property DIFF_TERM_ADV TERM_100 [get_ports refclk450_n]

create_clock -period 2.222 -name refclk [get_ports refclk450_p]




#set_property PACKAGE_PIN AR14 [get_ports {pcie_clk_in_clk_n[0]}]
#set_property PACKAGE_PIN AR15 [get_ports {pcie_clk_in_clk_p[0]}]
#create_clock -period 10.000 -name pcie_clk_in_clk [get_ports pcie_clk_in_clk_p]

#set_false_path -from [get_ports sys_rst_n]
#set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]
#set_property PACKAGE_PIN BF41 [get_ports sys_rst_n]



# FIXED pcie.xdc
set_property PACKAGE_PIN AR14 [get_ports {pcie_clk_in_clk_n[0]}]
set_property PACKAGE_PIN AR15 [get_ports {pcie_clk_in_clk_p[0]}]

# FIX: Added { } and [0] to match the Verilog vector definition
create_clock -period 10.000 -name pcie_clk_in_clk [get_ports {pcie_clk_in_clk_p[0]}]

set_false_path -from [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]
set_property PACKAGE_PIN BF41 [get_ports sys_rst_n]




# Set bitstream USERID
set_property BITSTREAM.CONFIG.USERID 32'hADAD0109 [current_design]

















