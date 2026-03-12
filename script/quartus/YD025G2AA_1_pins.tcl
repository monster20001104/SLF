set_location_assignment PIN_AE26 -to ref_clk_soc_pcie
set_location_assignment PIN_AE25 -to "ref_clk_soc_pcie(n)"
set_location_assignment PIN_AN30 -to soc_pcie_rx[0]
set_location_assignment PIN_AN29 -to "soc_pcie_rx[0](n)"
set_location_assignment PIN_AL30 -to soc_pcie_rx[1]
set_location_assignment PIN_AL29 -to "soc_pcie_rx[1](n)"
set_location_assignment PIN_AJ30 -to soc_pcie_rx[2]
set_location_assignment PIN_AJ29 -to "soc_pcie_rx[2](n)"
set_location_assignment PIN_AH28 -to soc_pcie_rx[3]
set_location_assignment PIN_AH27 -to "soc_pcie_rx[3](n)"
set_location_assignment PIN_AG30 -to soc_pcie_rx[4]
set_location_assignment PIN_AG29 -to "soc_pcie_rx[4](n)"
set_location_assignment PIN_AF28 -to soc_pcie_rx[5]
set_location_assignment PIN_AF27 -to "soc_pcie_rx[5](n)"
set_location_assignment PIN_AE30 -to soc_pcie_rx[6]
set_location_assignment PIN_AE29 -to "soc_pcie_rx[6](n)"
set_location_assignment PIN_AD28 -to soc_pcie_rx[7]
set_location_assignment PIN_AD27 -to "soc_pcie_rx[7](n)"
set_location_assignment PIN_AL34 -to soc_pcie_tx[0]
set_location_assignment PIN_AL33 -to "soc_pcie_tx[0](n)"
set_location_assignment PIN_AK32 -to soc_pcie_tx[1]
set_location_assignment PIN_AK31 -to "soc_pcie_tx[1](n)"
set_location_assignment PIN_AJ34 -to soc_pcie_tx[2]
set_location_assignment PIN_AJ33 -to "soc_pcie_tx[2](n)"
set_location_assignment PIN_AH32 -to soc_pcie_tx[3]
set_location_assignment PIN_AH31 -to "soc_pcie_tx[3](n)"
set_location_assignment PIN_AG34 -to soc_pcie_tx[4]
set_location_assignment PIN_AG33 -to "soc_pcie_tx[4](n)"
set_location_assignment PIN_AF32 -to soc_pcie_tx[5]
set_location_assignment PIN_AF31 -to "soc_pcie_tx[5](n)"
set_location_assignment PIN_AE34 -to soc_pcie_tx[6]
set_location_assignment PIN_AE33 -to "soc_pcie_tx[6](n)"
set_location_assignment PIN_AD32 -to soc_pcie_tx[7]
set_location_assignment PIN_AD31 -to "soc_pcie_tx[7](n)"

set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[7] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[6] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[5] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[4] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[3] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[2] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[1] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_rx[0] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[7] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[6] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[5] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[4] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[3] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[2] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[1] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to soc_pcie_tx[0] -entity $top_level_entity

set_location_assignment  PIN_U26 -to ref_clk_host_pcie
set_location_assignment  PIN_U25 -to "ref_clk_host_pcie(n)"
set_location_assignment  PIN_W30 -to host_pcie_rx[0]
set_location_assignment  PIN_W29 -to "host_pcie_rx[0](n)"
set_location_assignment  PIN_V28 -to host_pcie_rx[1]
set_location_assignment  PIN_V27 -to "host_pcie_rx[1](n)"
set_location_assignment  PIN_U30 -to host_pcie_rx[2]
set_location_assignment  PIN_U29 -to "host_pcie_rx[2](n)"
set_location_assignment  PIN_T28 -to host_pcie_rx[3]
set_location_assignment  PIN_T27 -to "host_pcie_rx[3](n)"
set_location_assignment  PIN_R30 -to host_pcie_rx[4]
set_location_assignment  PIN_R29 -to "host_pcie_rx[4](n)"
set_location_assignment  PIN_P28 -to host_pcie_rx[5]
set_location_assignment  PIN_P27 -to "host_pcie_rx[5](n)"
set_location_assignment  PIN_N30 -to host_pcie_rx[6]
set_location_assignment  PIN_N29 -to "host_pcie_rx[6](n)"
set_location_assignment  PIN_M28 -to host_pcie_rx[7]
set_location_assignment  PIN_M27 -to "host_pcie_rx[7](n)"
set_location_assignment  PIN_W34 -to host_pcie_tx[0]
set_location_assignment  PIN_W33 -to "host_pcie_tx[0](n)"
set_location_assignment  PIN_V32 -to host_pcie_tx[1]
set_location_assignment  PIN_V31 -to "host_pcie_tx[1](n)"
set_location_assignment  PIN_U34 -to host_pcie_tx[2]
set_location_assignment  PIN_U33 -to "host_pcie_tx[2](n)"
set_location_assignment  PIN_T32 -to host_pcie_tx[3]
set_location_assignment  PIN_T31 -to "host_pcie_tx[3](n)"
set_location_assignment  PIN_R34 -to host_pcie_tx[4]
set_location_assignment  PIN_R33 -to "host_pcie_tx[4](n)"
set_location_assignment  PIN_P32 -to host_pcie_tx[5]
set_location_assignment  PIN_P31 -to "host_pcie_tx[5](n)"
set_location_assignment  PIN_N34 -to host_pcie_tx[6]
set_location_assignment  PIN_N33 -to "host_pcie_tx[6](n)"
set_location_assignment  PIN_M32 -to host_pcie_tx[7]
set_location_assignment  PIN_M31 -to "host_pcie_tx[7](n)"

set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[7] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[6] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[5] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[4] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[3] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[2] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[1] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_rx[0] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[7] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[6] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[5] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[4] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[3] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[2] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[1] -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to host_pcie_tx[0] -entity $top_level_entity

set_instance_assignment -name IO_STANDARD LVDS -to ref_clk_soc_pcie -entity $top_level_entity
set_location_assignment PIN_AH13 -to perstn_soc_pcie
set_location_assignment PIN_AG5  -to fpga_user_reset
set_instance_assignment -name IO_STANDARD LVDS -to ref_clk_host_pcie -entity $top_level_entity
set_location_assignment PIN_AJ10 -to perstn_host_pcie

set_instance_assignment -name IO_STANDARD "1.8 V" -to fx2_scl -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "1.8 V" -to fx2_sda -entity $top_level_entity
set_instance_assignment -name SLEW_RATE 0 -to fx2_scl -entity $top_level_entity
set_instance_assignment -name SLEW_RATE 0 -to fx2_sda -entity $top_level_entity
set_location_assignment PIN_AE8 -to fx2_scl
set_location_assignment PIN_AE7 -to fx2_sda


set_instance_assignment -name IO_STANDARD "1.8 V" -to bmc_scl -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "1.8 V" -to bmc_sda -entity $top_level_entity
set_instance_assignment -name SLEW_RATE 0 -to bmc_scl -entity $top_level_entity
set_instance_assignment -name SLEW_RATE 0 -to bmc_sda -entity $top_level_entity
set_location_assignment PIN_AA6 -to bmc_scl
set_location_assignment PIN_AA5 -to bmc_sda