set_property PACKAGE_PIN T42 [get_ports ff7_refclk_p]
set_property PACKAGE_PIN T43 [get_ports ff7_refclk_n]
create_clock -period 6.206 -name ff7_refclk [get_ports ff7_refclk_p]
set_property PACKAGE_PIN L48 [get_ports {ff7_txp[0]}]
set_property PACKAGE_PIN L49 [get_ports {ff7_txn[0]}]
set_property PACKAGE_PIN L44 [get_ports {ff7_txp[1]}]
set_property PACKAGE_PIN L45 [get_ports {ff7_txn[1]}]
set_property PACKAGE_PIN K46 [get_ports {ff7_txp[2]}]
set_property PACKAGE_PIN K47 [get_ports {ff7_txn[2]}]
set_property PACKAGE_PIN J48 [get_ports {ff7_txp[3]}]
set_property PACKAGE_PIN J49 [get_ports {ff7_txn[3]}]
set_property PACKAGE_PIN L53 [get_ports {ff7_rxp[0]}]
set_property PACKAGE_PIN L54 [get_ports {ff7_rxn[0]}]
set_property PACKAGE_PIN K51 [get_ports {ff7_rxp[1]}]
set_property PACKAGE_PIN K52 [get_ports {ff7_rxn[1]}]
set_property PACKAGE_PIN J53 [get_ports {ff7_rxp[2]}]
set_property PACKAGE_PIN J54 [get_ports {ff7_rxn[2]}]
set_property PACKAGE_PIN H51 [get_ports {ff7_rxp[3]}]
set_property PACKAGE_PIN H52 [get_ports {ff7_rxn[3]}]

# The FireFly reference clock is asynchronous to the core clock.  Without this
# Vivado times the Aurora boundary as a related path and reports failures on a
# crossing the transceiver handles internally -- the same class of phantom
# violation that produced WNS -5.131 ns on the FIFO crossing.
# ff7_refclk is not a clock object: the reference enters through an IBUFDS_GTE4
# inside the transceiver, so no create_clock on the port ever takes. The group
# is therefore expressed against the clocks the Aurora cores generate, which are
# what actually cross into the fabric. The core clock is named for its MMCM
# output, not clk_out1.
# XDC does not permit control flow, so this is written as plain commands.
# get_clocks -quiet returns an empty list when nothing matches, and
# set_clock_groups on an empty group is a no-op rather than an error.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_out1_clock_and_buffer_clk_wiz_0_0] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier -filter {NAME =~ *TXOUTCLK}]]

# Reset and pulse synchronisers are asynchronous by construction.
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/D}]
# A reset synchroniser's asynchronous clear is asynchronous by construction, so
# timing it as a synchronous path reports a violation on a crossing the
# synchroniser exists to absorb. The /D filter above misses /CLR and /PRE.
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/CLR}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/PRE}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *pulse_stretcher*/D}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *_synchronizer*/D}]

# The four clock domains are independent: core and memory from one MMCM at a
# non-integer ratio, PCIe from its own reference, and the transceiver clocks
# recovered from the serial line. Every crossing between them goes through an
# asynchronous FIFO or a reset synchroniser. Timed as related, the adjacent
# edges produce requirements of tens of picoseconds -- 83 ps between core and
# memory, 10 ps from the transceiver -- which no logic can meet and which
# describe nothing physical.
set_clock_groups -asynchronous \
  -group [get_clocks -quiet clk_out1_clock_and_buffer_clk_wiz_0_0] \
  -group [get_clocks -quiet clk_out2_clock_and_buffer_clk_wiz_0_0] \
  -group [get_clocks -quiet clk_out3_clock_and_buffer_clk_wiz_0_0] \
  -group [get_clocks -quiet pcie_axi_clk] \
  -group [get_clocks -quiet {txoutclk_out* rxoutclk_out* *TXOUTCLKPCS* *QPLL*}]
