set_property PACKAGE_PIN AR14 [get_ports {pcie_clk_in_clk_n[0]}]
set_property PACKAGE_PIN AR15 [get_ports {pcie_clk_in_clk_p[0]}]
create_clock -period 10.000 -name pcie_clk_in_clk [get_ports pcie_clk_in_clk_p]

set_false_path -from [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]
set_property PACKAGE_PIN BF41 [get_ports sys_rst_n]



