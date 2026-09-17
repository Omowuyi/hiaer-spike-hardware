# =============================================================================
# false_paths.xdc
# Minimal clock domain exception
# =============================================================================

set_clock_groups -quiet -asynchronous  -group [get_clocks -quiet pcie_clk_in_clk]  -group [get_clocks -quiet refclk450]

