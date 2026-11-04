################################################################################

# This XDC is used only for OOC mode of synthesis, implementation
# This constraints file contains default clock frequencies to be used during
# out-of-context flows such as OOC Synthesis and Hierarchical Designs.
# This constraints file is not used in normal top-down synthesis (default flow
# of Vivado)
################################################################################
create_clock -name pcie_clk_in_clk_p -period 10 [get_ports pcie_clk_in_clk_p]
create_clock -name refclk450_clk_p -period 2.222 [get_ports refclk450_clk_p]

################################################################################