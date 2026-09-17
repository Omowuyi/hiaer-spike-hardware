# =============================================================================
# false_paths.xdc
# Clock exceptions only
# =============================================================================

set_clock_groups -quiet -asynchronous  -group [get_clocks -quiet pcie_clk_in_clk]  -group [get_clocks -quiet refclk450]

