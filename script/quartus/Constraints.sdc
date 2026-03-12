derive_pll_clocks -create_base_clocks

#100MHz PCIe#1 Ref clock from U56
create_clock -period 10 [get_ports ref_clk_soc_pcie]

#100MHz PCIe#2 Ref clock from U56
create_clock -period 10 [get_ports ref_clk_host_pcie]

create_clock -name {altera_reserved_tck} -period 30.000  [get_ports {altera_reserved_tck}]
set_clock_groups -asynchronous -group {altera_reserved_tck}
#set_max_delay -to [get_ports { altera_reserved_tdo } ] 0

set_false_path -to [get_ports {leds[*]}]

set_false_path -from [get_ports fpga_user_reset]

#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_11m}]
#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_11m}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}]

#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}] -to [get_clocks {u_soc_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}]
#set_false_path -from [get_clocks {u_soc_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}]

#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}] -to [get_clocks {u_soc_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}]
#set_false_path -from [get_clocks {u_soc_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}]

#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_11m}] -to [get_clocks {u_soc_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}]
#set_false_path -from [get_clocks {u_soc_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_11m}]

#set_false_path -from [get_clocks {altera_ts_clk}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}]
#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}] -to [get_clocks {altera_ts_clk}]


#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}] -to [get_clocks {u_host_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}]
#set_false_path -from [get_clocks {u_host_pcie_hip|pcie_a10_hip_0|wys~CORE_CLK_OUT}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}]

#set_false_path -from [get_clocks {u_host_pcie_hip|pcie_a10_hip_0|pld_clk}] -to [get_clocks {ref_clk_host_pcie}]
#set_false_path -from [get_clocks {ref_clk_host_pcie}] -to [get_clocks {u_host_pcie_hip|pcie_a10_hip_0|pld_clk}]

#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}] -to [get_clocks {ref_clk_host_pcie}]
#set_false_path -from [get_clocks {ref_clk_host_pcie}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}]


#source ../script/quartus/jtag_sdc.tcl

#set_false_path -from [get_clocks {altera_reserved_tck}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_11m}]
#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_11m}] -to [get_clocks {altera_reserved_tck}]
#set_false_path -from [get_clocks {altera_reserved_tck}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}]
#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_50m}] -to [get_clocks {altera_reserved_tck}]
#set_false_path -from [get_clocks {altera_reserved_tck}] -to [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}]
#set_false_path -from [get_clocks {u_clock_gen|u_pll|iopll_0|outclk_200m}] -to [get_clocks {altera_reserved_tck}]

set_false_path -from "perstn_host_pcie"
set_false_path -from "perstn_soc_pcie"

############################################
# I2C timing constraints
############################################

