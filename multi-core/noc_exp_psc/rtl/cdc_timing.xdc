#=============================================================================
# cdc_timing.xdc -- constrain the core/memory/APB clock crossings
#
# XDC PERMITS NO CONTROL FLOW.  An earlier version of this file wrapped every
# set_max_delay in an `if`, and Vivado rejected each one:
#   CRITICAL WARNING: [Designutils 20-1307] Command 'if' is not supported
# so NONE of these constraints was ever applied, in any build.  The symptom is
# a requirement of 0.083 ns between clk_out3 and clk_out1 -- two outputs of one
# MMCM at a non-integer ratio, timed as related -- on a path that crosses an
# independent-clock FIFO and is asynchronous by construction.
#
# get_clocks -quiet returns an empty list when nothing matches, and
# set_max_delay on an empty list is a no-op, so no guard is needed.
#
# set_max_delay -datapath_only rather than set_false_path: the combinational
# delay still has to be bounded, or a path allowed to take arbitrarily long
# breaks the FIFO's own timing assumptions.  The bound is one period of the
# receiving clock, the interval the receiving side holds its input stable.
#=============================================================================

set core_clk [get_clocks -quiet clk_out1_clock_and_buffer_clk_wiz_0_0]
set mem_clk  [get_clocks -quiet clk_out3_clock_and_buffer_clk_wiz_0_0]
set apb_clk  [get_clocks -quiet clk_out2_clock_and_buffer_clk_wiz_0_0]

# Periods read from the clocks rather than written as literals, so changing
# the MMCM cannot leave a stale number here.
set_max_delay -datapath_only -from $mem_clk  -to $core_clk 15.922
set_max_delay -datapath_only -from $core_clk -to $mem_clk   4.001
set_max_delay -datapath_only -from $apb_clk  -to $core_clk 15.922
set_max_delay -datapath_only -from $core_clk -to $apb_clk  10.003

#-----------------------------------------------------------------------------
# PCIe AXI domain to core domain, and back.
#
# pcie_axi_clk comes from the PCIe hard block's own reference, unrelated to the
# MMCM that produces the core clock.  Every crossing between them goes through
# the 512-bit asynchronous FIFOs (fifo_512_wide_async).  Timed as related, all
# 1550 endpoints fail at -2.142 ns against a requirement the tool derives from
# two clocks that share no common source -- reported as "No Common Clock,
# Timed (unsafe)".
#-----------------------------------------------------------------------------
set pcie_clk [get_clocks -quiet pcie_axi_clk]

set_max_delay -datapath_only -from $pcie_clk -to $core_clk 15.922
set_max_delay -datapath_only -from $core_clk -to $pcie_clk   4.000

#-----------------------------------------------------------------------------
# Reset and pulse synchronisers are asynchronous by construction.  A reset
# synchroniser's asynchronous clear is checked for recovery/removal against the
# destination clock, which set_max_delay -datapath_only does not cover -- it
# applies to data paths, not to CLR/PRE.  Without these, user_reset from the
# PCIe block to reset_sync_450/q_reg/CLR reports -1.422 ns on a crossing the
# synchroniser exists to absorb.
#-----------------------------------------------------------------------------
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/D}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/CLR}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *reset_sync*/PRE}]
set_false_path -to [get_pins -quiet -hierarchical -filter {NAME =~ *_synchronizer*/D}]
