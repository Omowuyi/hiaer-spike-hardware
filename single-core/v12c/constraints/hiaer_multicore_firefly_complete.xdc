#=============================================================================
# HiAER-Spike Multi-Core + FireFly Complete Constraints
# Target: ADM-PCIE-9H7 with VU37P FPGA
# 
# This is the COMPLETE constraint file containing:
# - All pin constraints (PCIe, system clock, FireFly ports 4-7)
# - Clock constraints
# - Clock domain crossing constraints
# - Core floorplanning (16 cores)
# - Debug hub constraints
# - Message suppression
#
# FPGA Topology (8-FPGA HiAER Cluster - Server 0):
#   Lower Tier (FPGA 0-3): Only Port 7 active → connects to upper tier partner
#   Upper Tier (FPGA 4-7): Ports 4,5,6,7 active → full mesh + lower tier links
#
# Connection Table:
#   FPGA 0: P7 ↔ FPGA 4 P7
#   FPGA 1: P7 ↔ FPGA 5 P7
#   FPGA 2: P7 ↔ FPGA 6 P7
#   FPGA 3: P7 ↔ FPGA 7 P7
#   FPGA 4: P4↔FPGA5 P4, P5↔FPGA6 P6(asym), P6↔FPGA7 P6, P7↔FPGA0 P7
#   FPGA 5: P4↔FPGA4 P4, P5↔FPGA6 P5, P6↔FPGA7 P5(asym), P7↔FPGA1 P7
#   FPGA 6: P4↔FPGA7 P4, P5↔FPGA5 P5, P6↔FPGA4 P5(asym), P7↔FPGA2 P7
#   FPGA 7: P4↔FPGA6 P4, P5↔FPGA5 P6(asym), P6↔FPGA4 P6, P7↔FPGA3 P7
#
# Reference: ADM-PCIE-9H7 User Manual v1.3
#=============================================================================

#=============================================================================
# SECTION 0: MESSAGE SUPPRESSION
#=============================================================================

set_msg_config -id {Synth 8-4442} -suppress
set_msg_config -id {Vivado 12-5201} -suppress
set_msg_config -id {Opt 31-67} -suppress

#=============================================================================
# SECTION 1: PCIe INTERFACE
#=============================================================================

# PCIe Reference Clock (100 MHz) - GT Reference Clock pins
set_property PACKAGE_PIN AR14 [get_ports {pcie_clk_in_clk_n[0]}]
set_property PACKAGE_PIN AR15 [get_ports {pcie_clk_in_clk_p[0]}]
create_clock -period 10.000 -name pcie_refclk [get_ports {pcie_clk_in_clk_p[0]}]

# PCIe Reset
set_property PACKAGE_PIN BF41 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

#=============================================================================
# SECTION 2: SYSTEM REFERENCE CLOCK (450 MHz)
# Now using IBUFDS (not IBUFDS_GTE4)
#=============================================================================

set_property PACKAGE_PIN BJ52 [get_ports refclk450_p]
set_property PACKAGE_PIN BJ53 [get_ports refclk450_n]
set_property IOSTANDARD LVDS [get_ports refclk450_p]
set_property IOSTANDARD LVDS [get_ports refclk450_n]
set_property DIFF_TERM_ADV TERM_100 [get_ports refclk450_p]
set_property DIFF_TERM_ADV TERM_100 [get_ports refclk450_n]
create_clock -period 2.222 -name refclk450 [get_ports refclk450_p]

#=============================================================================
# SECTION 3: FIREFLY PORT 4 - MGT Quad 234 (X1Y16-X1Y19)
# Used by: FPGA 4↔5 (P4↔P4), FPGA 6↔7 (P4↔P4)
#=============================================================================

# Reference Clock (161.1328125 MHz for 25.78125 Gbps)
set_property PACKAGE_PIN T13 [get_ports ff4_refclk_p]
set_property PACKAGE_PIN T12 [get_ports ff4_refclk_n]
create_clock -period 6.206 -name ff4_refclk [get_ports ff4_refclk_p]

# GT TX Pins
set_property PACKAGE_PIN L7  [get_ports {ff4_txp[0]}]
set_property PACKAGE_PIN L6  [get_ports {ff4_txn[0]}]
set_property PACKAGE_PIN L11 [get_ports {ff4_txp[1]}]
set_property PACKAGE_PIN L10 [get_ports {ff4_txn[1]}]
set_property PACKAGE_PIN K9  [get_ports {ff4_txp[2]}]
set_property PACKAGE_PIN K8  [get_ports {ff4_txn[2]}]
set_property PACKAGE_PIN J7  [get_ports {ff4_txp[3]}]
set_property PACKAGE_PIN J6  [get_ports {ff4_txn[3]}]

# GT RX Pins
set_property PACKAGE_PIN L2  [get_ports {ff4_rxp[0]}]
set_property PACKAGE_PIN L1  [get_ports {ff4_rxn[0]}]
set_property PACKAGE_PIN K4  [get_ports {ff4_rxp[1]}]
set_property PACKAGE_PIN K3  [get_ports {ff4_rxn[1]}]
set_property PACKAGE_PIN J2  [get_ports {ff4_rxp[2]}]
set_property PACKAGE_PIN J1  [get_ports {ff4_rxn[2]}]
set_property PACKAGE_PIN H4  [get_ports {ff4_rxp[3]}]
set_property PACKAGE_PIN H3  [get_ports {ff4_rxn[3]}]

# I2C and Module Presence
set_property PACKAGE_PIN BE11 [get_ports ff4_modprs_n]
set_property PACKAGE_PIN BM13 [get_ports ff4_scl]
set_property PACKAGE_PIN BM14 [get_ports ff4_sda]
set_property IOSTANDARD LVCMOS18 [get_ports {ff4_modprs_n ff4_scl ff4_sda}]

#=============================================================================
# SECTION 4: FIREFLY PORT 5 - MGT Quad 235 (X1Y20-X1Y23)
# Used by: FPGA 4↔6 (P5↔P6 asym), FPGA 5↔6 (P5↔P5), FPGA 5↔7 (P6↔P5 asym)
#=============================================================================

# Reference Clock
set_property PACKAGE_PIN P13 [get_ports ff5_refclk_p]
set_property PACKAGE_PIN P12 [get_ports ff5_refclk_n]
create_clock -period 6.206 -name ff5_refclk [get_ports ff5_refclk_p]

# GT TX Pins
set_property PACKAGE_PIN G7  [get_ports {ff5_txp[0]}]
set_property PACKAGE_PIN G6  [get_ports {ff5_txn[0]}]
set_property PACKAGE_PIN E7  [get_ports {ff5_txp[1]}]
set_property PACKAGE_PIN E6  [get_ports {ff5_txn[1]}]
set_property PACKAGE_PIN C7  [get_ports {ff5_txp[2]}]
set_property PACKAGE_PIN C6  [get_ports {ff5_txn[2]}]
set_property PACKAGE_PIN A6  [get_ports {ff5_txp[3]}]
set_property PACKAGE_PIN A5  [get_ports {ff5_txn[3]}]

# GT RX Pins
set_property PACKAGE_PIN G2  [get_ports {ff5_rxp[0]}]
set_property PACKAGE_PIN G1  [get_ports {ff5_rxn[0]}]
set_property PACKAGE_PIN F4  [get_ports {ff5_rxp[1]}]
set_property PACKAGE_PIN F3  [get_ports {ff5_rxn[1]}]
set_property PACKAGE_PIN E2  [get_ports {ff5_rxp[2]}]
set_property PACKAGE_PIN E1  [get_ports {ff5_rxn[2]}]
set_property PACKAGE_PIN D4  [get_ports {ff5_rxp[3]}]
set_property PACKAGE_PIN D3  [get_ports {ff5_rxn[3]}]

# I2C and Module Presence
set_property PACKAGE_PIN BF10 [get_ports ff5_modprs_n]
set_property PACKAGE_PIN BM15 [get_ports ff5_scl]
set_property PACKAGE_PIN BL15 [get_ports ff5_sda]
set_property IOSTANDARD LVCMOS18 [get_ports {ff5_modprs_n ff5_scl ff5_sda}]

#=============================================================================
# SECTION 5: FIREFLY PORT 6 - MGT Quad 135 (X0Y28-X0Y31)
# Used by: FPGA 4↔7 (P6↔P6), FPGA 4↔6 (P5↔P6 asym), FPGA 5↔7 (P6↔P5 asym)
#=============================================================================

# Reference Clock
set_property PACKAGE_PIN P42 [get_ports ff6_refclk_p]
set_property PACKAGE_PIN P43 [get_ports ff6_refclk_n]
create_clock -period 6.206 -name ff6_refclk [get_ports ff6_refclk_p]

# GT TX Pins
set_property PACKAGE_PIN G48 [get_ports {ff6_txp[0]}]
set_property PACKAGE_PIN G49 [get_ports {ff6_txn[0]}]
set_property PACKAGE_PIN E48 [get_ports {ff6_txp[1]}]
set_property PACKAGE_PIN E49 [get_ports {ff6_txn[1]}]
set_property PACKAGE_PIN C48 [get_ports {ff6_txp[2]}]
set_property PACKAGE_PIN C49 [get_ports {ff6_txn[2]}]
set_property PACKAGE_PIN A49 [get_ports {ff6_txp[3]}]
set_property PACKAGE_PIN A50 [get_ports {ff6_txn[3]}]

# GT RX Pins
set_property PACKAGE_PIN G53 [get_ports {ff6_rxp[0]}]
set_property PACKAGE_PIN G54 [get_ports {ff6_rxn[0]}]
set_property PACKAGE_PIN F51 [get_ports {ff6_rxp[1]}]
set_property PACKAGE_PIN F52 [get_ports {ff6_rxn[1]}]
set_property PACKAGE_PIN E53 [get_ports {ff6_rxp[2]}]
set_property PACKAGE_PIN E54 [get_ports {ff6_rxn[2]}]
set_property PACKAGE_PIN D51 [get_ports {ff6_rxp[3]}]
set_property PACKAGE_PIN D52 [get_ports {ff6_rxn[3]}]

# I2C and Module Presence
set_property PACKAGE_PIN BE10 [get_ports ff6_modprs_n]
set_property PACKAGE_PIN BP9  [get_ports ff6_scl]
set_property PACKAGE_PIN BN11 [get_ports ff6_sda]
set_property IOSTANDARD LVCMOS18 [get_ports {ff6_modprs_n ff6_scl ff6_sda}]

#=============================================================================
# SECTION 6: FIREFLY PORT 7 - MGT Quad 134 (X0Y24-X0Y27)
# Used by: FPGA 0↔4, 1↔5, 2↔6, 3↔7 (P7↔P7 vertical links)
#=============================================================================

# Reference Clock
set_property PACKAGE_PIN T42 [get_ports ff7_refclk_p]
set_property PACKAGE_PIN T43 [get_ports ff7_refclk_n]
create_clock -period 6.206 -name ff7_refclk [get_ports ff7_refclk_p]

# GT TX Pins
set_property PACKAGE_PIN L48 [get_ports {ff7_txp[0]}]
set_property PACKAGE_PIN L49 [get_ports {ff7_txn[0]}]
set_property PACKAGE_PIN L44 [get_ports {ff7_txp[1]}]
set_property PACKAGE_PIN L45 [get_ports {ff7_txn[1]}]
set_property PACKAGE_PIN K46 [get_ports {ff7_txp[2]}]
set_property PACKAGE_PIN K47 [get_ports {ff7_txn[2]}]
set_property PACKAGE_PIN J48 [get_ports {ff7_txp[3]}]
set_property PACKAGE_PIN J49 [get_ports {ff7_txn[3]}]

# GT RX Pins
set_property PACKAGE_PIN L53 [get_ports {ff7_rxp[0]}]
set_property PACKAGE_PIN L54 [get_ports {ff7_rxn[0]}]
set_property PACKAGE_PIN K51 [get_ports {ff7_rxp[1]}]
set_property PACKAGE_PIN K52 [get_ports {ff7_rxn[1]}]
set_property PACKAGE_PIN J53 [get_ports {ff7_rxp[2]}]
set_property PACKAGE_PIN J54 [get_ports {ff7_rxn[2]}]
set_property PACKAGE_PIN H51 [get_ports {ff7_rxp[3]}]
set_property PACKAGE_PIN H52 [get_ports {ff7_rxn[3]}]

# I2C and Module Presence
set_property PACKAGE_PIN BE9  [get_ports ff7_modprs_n]
set_property PACKAGE_PIN BM10 [get_ports ff7_scl]
set_property PACKAGE_PIN BP8  [get_ports ff7_sda]
set_property IOSTANDARD LVCMOS18 [get_ports {ff7_modprs_n ff7_scl ff7_sda}]

#=============================================================================
# SECTION 7: CLOCK DOMAIN CROSSING CONSTRAINTS
#=============================================================================

# Asynchronous clock groups - system clocks
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -include_generated_clocks clk_out1*] \
    -group [get_clocks -quiet -include_generated_clocks clk_out2*] \
    -group [get_clocks -quiet -include_generated_clocks clk_out3*] \
    -group [get_clocks -quiet -include_generated_clocks refclk450] \
    -group [get_clocks -quiet -include_generated_clocks pcie_refclk]

# FireFly reference clocks are asynchronous to system clocks
set_clock_groups -asynchronous \
    -group [get_clocks -quiet ff4_refclk] \
    -group [get_clocks -quiet ff5_refclk] \
    -group [get_clocks -quiet ff6_refclk] \
    -group [get_clocks -quiet ff7_refclk] \
    -group [get_clocks -quiet -include_generated_clocks clk_out1*]

# Reset synchronizer false paths
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/D}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *pulse_stretcher*/D}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *_synchronizer*/D}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_stretcher*/D}]

# Async FIFO false paths (gray code pointers)
set_false_path -through [get_pins -quiet -hierarchical -filter {NAME =~ *fifo*/*wr_pntr*}]
set_false_path -through [get_pins -quiet -hierarchical -filter {NAME =~ *fifo*/*rd_pntr*}]
set_false_path -through [get_pins -quiet -hierarchical -filter {NAME =~ *xpm_cdc*/*src*}]
set_false_path -through [get_pins -quiet -hierarchical -filter {NAME =~ *xpm_cdc*/*dest*}]

# Aurora CDC false paths
set_false_path -from [get_clocks -quiet -of_objects [get_pins -quiet -hierarchical -filter {NAME =~ *aurora*/inst/*/txoutclk_out*}]] -to [get_clocks -quiet clk_out1*]
set_false_path -from [get_clocks -quiet clk_out1*] -to [get_clocks -quiet -of_objects [get_pins -quiet -hierarchical -filter {NAME =~ *aurora*/inst/*/txoutclk_out*}]]
set_false_path -from [get_clocks -quiet -of_objects [get_pins -quiet -hierarchical -filter {NAME =~ *aurora*/inst/*/rxoutclk_out*}]] -to [get_clocks -quiet clk_out1*]
set_false_path -from [get_clocks -quiet clk_out1*] -to [get_clocks -quiet -of_objects [get_pins -quiet -hierarchical -filter {NAME =~ *aurora*/inst/*/rxoutclk_out*}]]

# Aurora reset synchronizers
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *aurora*/*sync*/D}]

#=============================================================================
# SECTION 8: CORE FLOORPLANNING - All 16 cores
# Cell names: gen_cores[N].my_core
#=============================================================================

# Core 0 - Bottom Left
create_pblock pblock_core_0
add_cells_to_pblock [get_pblocks pblock_core_0] [get_cells -quiet [list gen_cores[0].my_core]]
resize_pblock [get_pblocks pblock_core_0] -add {SLICE_X0Y0:SLICE_X56Y59}
resize_pblock [get_pblocks pblock_core_0] -add {DSP48E2_X0Y0:DSP48E2_X7Y17}
resize_pblock [get_pblocks pblock_core_0] -add {RAMB18_X0Y0:RAMB18_X3Y23}
resize_pblock [get_pblocks pblock_core_0] -add {RAMB36_X0Y0:RAMB36_X3Y11}
resize_pblock [get_pblocks pblock_core_0] -add {URAM288_X0Y0:URAM288_X0Y15}

# Core 1 - Bottom Right
create_pblock pblock_core_1
add_cells_to_pblock [get_pblocks pblock_core_1] [get_cells -quiet [list gen_cores[1].my_core]]
resize_pblock [get_pblocks pblock_core_1] -add {SLICE_X57Y0:SLICE_X116Y59}
resize_pblock [get_pblocks pblock_core_1] -add {DSP48E2_X8Y0:DSP48E2_X15Y17}
resize_pblock [get_pblocks pblock_core_1] -add {RAMB18_X4Y0:RAMB18_X7Y23}
resize_pblock [get_pblocks pblock_core_1] -add {RAMB36_X4Y0:RAMB36_X7Y11}
resize_pblock [get_pblocks pblock_core_1] -add {URAM288_X1Y0:URAM288_X1Y15}

# Core 2
create_pblock pblock_core_2
add_cells_to_pblock [get_pblocks pblock_core_2] [get_cells -quiet [list gen_cores[2].my_core]]
resize_pblock [get_pblocks pblock_core_2] -add {SLICE_X0Y60:SLICE_X56Y119}
resize_pblock [get_pblocks pblock_core_2] -add {DSP48E2_X0Y18:DSP48E2_X7Y41}
resize_pblock [get_pblocks pblock_core_2] -add {RAMB18_X0Y24:RAMB18_X3Y47}
resize_pblock [get_pblocks pblock_core_2] -add {RAMB36_X0Y12:RAMB36_X3Y23}
resize_pblock [get_pblocks pblock_core_2] -add {URAM288_X0Y16:URAM288_X0Y31}

# Core 3
create_pblock pblock_core_3
add_cells_to_pblock [get_pblocks pblock_core_3] [get_cells -quiet [list gen_cores[3].my_core]]
resize_pblock [get_pblocks pblock_core_3] -add {SLICE_X57Y60:SLICE_X116Y119}
resize_pblock [get_pblocks pblock_core_3] -add {DSP48E2_X8Y18:DSP48E2_X15Y41}
resize_pblock [get_pblocks pblock_core_3] -add {RAMB18_X4Y24:RAMB18_X7Y47}
resize_pblock [get_pblocks pblock_core_3] -add {RAMB36_X4Y12:RAMB36_X7Y23}
resize_pblock [get_pblocks pblock_core_3] -add {URAM288_X1Y16:URAM288_X1Y31}

# Core 4
create_pblock pblock_core_4
add_cells_to_pblock [get_pblocks pblock_core_4] [get_cells -quiet [list gen_cores[4].my_core]]
resize_pblock [get_pblocks pblock_core_4] -add {SLICE_X0Y120:SLICE_X56Y179}
resize_pblock [get_pblocks pblock_core_4] -add {DSP48E2_X0Y42:DSP48E2_X7Y65}
resize_pblock [get_pblocks pblock_core_4] -add {RAMB18_X0Y48:RAMB18_X3Y71}
resize_pblock [get_pblocks pblock_core_4] -add {RAMB36_X0Y24:RAMB36_X3Y35}
resize_pblock [get_pblocks pblock_core_4] -add {URAM288_X0Y32:URAM288_X0Y47}

# Core 5
create_pblock pblock_core_5
add_cells_to_pblock [get_pblocks pblock_core_5] [get_cells -quiet [list gen_cores[5].my_core]]
resize_pblock [get_pblocks pblock_core_5] -add {SLICE_X57Y120:SLICE_X116Y179}
resize_pblock [get_pblocks pblock_core_5] -add {DSP48E2_X8Y42:DSP48E2_X15Y65}
resize_pblock [get_pblocks pblock_core_5] -add {RAMB18_X4Y48:RAMB18_X7Y71}
resize_pblock [get_pblocks pblock_core_5] -add {RAMB36_X4Y24:RAMB36_X7Y35}
resize_pblock [get_pblocks pblock_core_5] -add {URAM288_X1Y32:URAM288_X1Y47}

# Core 6
create_pblock pblock_core_6
add_cells_to_pblock [get_pblocks pblock_core_6] [get_cells -quiet [list gen_cores[6].my_core]]
resize_pblock [get_pblocks pblock_core_6] -add {SLICE_X0Y180:SLICE_X56Y239}
resize_pblock [get_pblocks pblock_core_6] -add {DSP48E2_X0Y66:DSP48E2_X7Y89}
resize_pblock [get_pblocks pblock_core_6] -add {RAMB18_X0Y72:RAMB18_X3Y95}
resize_pblock [get_pblocks pblock_core_6] -add {RAMB36_X0Y36:RAMB36_X3Y47}
resize_pblock [get_pblocks pblock_core_6] -add {URAM288_X0Y48:URAM288_X0Y63}

# Core 7
create_pblock pblock_core_7
add_cells_to_pblock [get_pblocks pblock_core_7] [get_cells -quiet [list gen_cores[7].my_core]]
resize_pblock [get_pblocks pblock_core_7] -add {SLICE_X57Y180:SLICE_X116Y239}
resize_pblock [get_pblocks pblock_core_7] -add {DSP48E2_X8Y66:DSP48E2_X15Y89}
resize_pblock [get_pblocks pblock_core_7] -add {RAMB18_X4Y72:RAMB18_X7Y95}
resize_pblock [get_pblocks pblock_core_7] -add {RAMB36_X4Y36:RAMB36_X7Y47}
resize_pblock [get_pblocks pblock_core_7] -add {URAM288_X1Y48:URAM288_X1Y63}

# Core 8
create_pblock pblock_core_8
add_cells_to_pblock [get_pblocks pblock_core_8] [get_cells -quiet [list gen_cores[8].my_core]]
resize_pblock [get_pblocks pblock_core_8] -add {SLICE_X0Y240:SLICE_X56Y299}
resize_pblock [get_pblocks pblock_core_8] -add {DSP48E2_X0Y90:DSP48E2_X7Y113}
resize_pblock [get_pblocks pblock_core_8] -add {RAMB18_X0Y96:RAMB18_X3Y119}
resize_pblock [get_pblocks pblock_core_8] -add {RAMB36_X0Y48:RAMB36_X3Y59}
resize_pblock [get_pblocks pblock_core_8] -add {URAM288_X0Y64:URAM288_X0Y79}

# Core 9
create_pblock pblock_core_9
add_cells_to_pblock [get_pblocks pblock_core_9] [get_cells -quiet [list gen_cores[9].my_core]]
resize_pblock [get_pblocks pblock_core_9] -add {SLICE_X57Y240:SLICE_X116Y299}
resize_pblock [get_pblocks pblock_core_9] -add {DSP48E2_X8Y90:DSP48E2_X15Y113}
resize_pblock [get_pblocks pblock_core_9] -add {RAMB18_X4Y96:RAMB18_X7Y119}
resize_pblock [get_pblocks pblock_core_9] -add {RAMB36_X4Y48:RAMB36_X7Y59}
resize_pblock [get_pblocks pblock_core_9] -add {URAM288_X1Y64:URAM288_X1Y79}

# Core 10
create_pblock pblock_core_10
add_cells_to_pblock [get_pblocks pblock_core_10] [get_cells -quiet [list gen_cores[10].my_core]]
resize_pblock [get_pblocks pblock_core_10] -add {SLICE_X0Y300:SLICE_X56Y359}
resize_pblock [get_pblocks pblock_core_10] -add {DSP48E2_X0Y114:DSP48E2_X7Y137}
resize_pblock [get_pblocks pblock_core_10] -add {RAMB18_X0Y120:RAMB18_X3Y143}
resize_pblock [get_pblocks pblock_core_10] -add {RAMB36_X0Y60:RAMB36_X3Y71}
resize_pblock [get_pblocks pblock_core_10] -add {URAM288_X0Y80:URAM288_X0Y95}

# Core 11
create_pblock pblock_core_11
add_cells_to_pblock [get_pblocks pblock_core_11] [get_cells -quiet [list gen_cores[11].my_core]]
resize_pblock [get_pblocks pblock_core_11] -add {SLICE_X57Y300:SLICE_X116Y359}
resize_pblock [get_pblocks pblock_core_11] -add {DSP48E2_X8Y114:DSP48E2_X15Y137}
resize_pblock [get_pblocks pblock_core_11] -add {RAMB18_X4Y120:RAMB18_X7Y143}
resize_pblock [get_pblocks pblock_core_11] -add {RAMB36_X4Y60:RAMB36_X7Y71}
resize_pblock [get_pblocks pblock_core_11] -add {URAM288_X1Y80:URAM288_X1Y95}

# Core 12
create_pblock pblock_core_12
add_cells_to_pblock [get_pblocks pblock_core_12] [get_cells -quiet [list gen_cores[12].my_core]]
resize_pblock [get_pblocks pblock_core_12] -add {SLICE_X0Y360:SLICE_X56Y419}
resize_pblock [get_pblocks pblock_core_12] -add {DSP48E2_X0Y138:DSP48E2_X7Y161}
resize_pblock [get_pblocks pblock_core_12] -add {RAMB18_X0Y144:RAMB18_X3Y167}
resize_pblock [get_pblocks pblock_core_12] -add {RAMB36_X0Y72:RAMB36_X3Y83}
resize_pblock [get_pblocks pblock_core_12] -add {URAM288_X0Y96:URAM288_X0Y111}

# Core 13
create_pblock pblock_core_13
add_cells_to_pblock [get_pblocks pblock_core_13] [get_cells -quiet [list gen_cores[13].my_core]]
resize_pblock [get_pblocks pblock_core_13] -add {SLICE_X57Y360:SLICE_X116Y419}
resize_pblock [get_pblocks pblock_core_13] -add {DSP48E2_X8Y138:DSP48E2_X15Y161}
resize_pblock [get_pblocks pblock_core_13] -add {RAMB18_X4Y144:RAMB18_X7Y167}
resize_pblock [get_pblocks pblock_core_13] -add {RAMB36_X4Y72:RAMB36_X7Y83}
resize_pblock [get_pblocks pblock_core_13] -add {URAM288_X1Y96:URAM288_X1Y111}

# Core 14
create_pblock pblock_core_14
add_cells_to_pblock [get_pblocks pblock_core_14] [get_cells -quiet [list gen_cores[14].my_core]]
resize_pblock [get_pblocks pblock_core_14] -add {SLICE_X0Y420:SLICE_X56Y479}
resize_pblock [get_pblocks pblock_core_14] -add {DSP48E2_X0Y162:DSP48E2_X7Y185}
resize_pblock [get_pblocks pblock_core_14] -add {RAMB18_X0Y168:RAMB18_X3Y191}
resize_pblock [get_pblocks pblock_core_14] -add {RAMB36_X0Y84:RAMB36_X3Y95}
resize_pblock [get_pblocks pblock_core_14] -add {URAM288_X0Y112:URAM288_X0Y127}

# Core 15
create_pblock pblock_core_15
add_cells_to_pblock [get_pblocks pblock_core_15] [get_cells -quiet [list gen_cores[15].my_core]]
resize_pblock [get_pblocks pblock_core_15] -add {SLICE_X57Y420:SLICE_X116Y479}
resize_pblock [get_pblocks pblock_core_15] -add {DSP48E2_X8Y162:DSP48E2_X15Y185}
resize_pblock [get_pblocks pblock_core_15] -add {RAMB18_X4Y168:RAMB18_X7Y191}
resize_pblock [get_pblocks pblock_core_15] -add {RAMB36_X4Y84:RAMB36_X7Y95}
resize_pblock [get_pblocks pblock_core_15] -add {URAM288_X1Y112:URAM288_X1Y127}

#=============================================================================
# SECTION 9: DEBUG HUB
#=============================================================================

set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]

#=============================================================================
# END OF CONSTRAINTS
#=============================================================================
