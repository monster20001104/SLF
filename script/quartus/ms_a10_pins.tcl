set_location_assignment PIN_AN29 -to ref_clk_soc_pcie
set_location_assignment PIN_AN28 -to "ref_clk_soc_pcie(n)"
set_location_assignment PIN_AN33 -to soc_pcie_rx[0]
set_location_assignment PIN_AN32 -to "soc_pcie_rx[0](n)"
set_location_assignment PIN_AM31 -to soc_pcie_rx[1]
set_location_assignment PIN_AM30 -to "soc_pcie_rx[1](n)"
set_location_assignment PIN_AM35 -to soc_pcie_rx[2]
set_location_assignment PIN_AM34 -to "soc_pcie_rx[2](n)"
set_location_assignment PIN_AL33 -to soc_pcie_rx[3]
set_location_assignment PIN_AL32 -to "soc_pcie_rx[3](n)"
set_location_assignment PIN_AK31 -to soc_pcie_rx[4]
set_location_assignment PIN_AK30 -to "soc_pcie_rx[4](n)"
set_location_assignment PIN_AK35 -to soc_pcie_rx[5]
set_location_assignment PIN_AK34 -to "soc_pcie_rx[5](n)"
set_location_assignment PIN_AJ33 -to soc_pcie_rx[6]
set_location_assignment PIN_AJ32 -to "soc_pcie_rx[6](n)"
set_location_assignment PIN_AH31 -to soc_pcie_rx[7]
set_location_assignment PIN_AH30 -to "soc_pcie_rx[7](n)"
set_location_assignment PIN_AU37 -to soc_pcie_tx[0]
set_location_assignment PIN_AU36 -to "soc_pcie_tx[0](n)"
set_location_assignment PIN_AT35 -to soc_pcie_tx[1]
set_location_assignment PIN_AT34 -to "soc_pcie_tx[1](n)"
set_location_assignment PIN_AT39 -to soc_pcie_tx[2]
set_location_assignment PIN_AT38 -to "soc_pcie_tx[2](n)"
set_location_assignment PIN_AR37 -to soc_pcie_tx[3]
set_location_assignment PIN_AR36 -to "soc_pcie_tx[3](n)"
set_location_assignment PIN_AP35 -to soc_pcie_tx[4]
set_location_assignment PIN_AP34 -to "soc_pcie_tx[4](n)"
set_location_assignment PIN_AP39 -to soc_pcie_tx[5]
set_location_assignment PIN_AP38 -to "soc_pcie_tx[5](n)"
set_location_assignment PIN_AN37 -to soc_pcie_tx[6]
set_location_assignment PIN_AN36 -to "soc_pcie_tx[6](n)"
set_location_assignment PIN_AM39 -to soc_pcie_tx[7]
set_location_assignment PIN_AM38 -to "soc_pcie_tx[7](n)"

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

set_location_assignment PIN_AE29 -to ref_clk_host_pcie
set_location_assignment PIN_AE28 -to "ref_clk_host_pcie(n)"
set_location_assignment PIN_AE33 -to host_pcie_rx[0]
set_location_assignment PIN_AE32 -to "host_pcie_rx[0](n)"
set_location_assignment PIN_AD31 -to host_pcie_rx[1]
set_location_assignment PIN_AD30 -to "host_pcie_rx[1](n)"
set_location_assignment PIN_AD35 -to host_pcie_rx[2]
set_location_assignment PIN_AD34 -to "host_pcie_rx[2](n)"
set_location_assignment PIN_AC33 -to host_pcie_rx[3]
set_location_assignment PIN_AC32 -to "host_pcie_rx[3](n)"
set_location_assignment PIN_AB31 -to host_pcie_rx[4]
set_location_assignment PIN_AB30 -to "host_pcie_rx[4](n)"
set_location_assignment PIN_AB35 -to host_pcie_rx[5]
set_location_assignment PIN_AB34 -to "host_pcie_rx[5](n)"
set_location_assignment PIN_AA33 -to host_pcie_rx[6]
set_location_assignment PIN_AA32 -to "host_pcie_rx[6](n)"
set_location_assignment PIN_Y35 -to host_pcie_rx[7]
set_location_assignment PIN_Y34 -to "host_pcie_rx[7](n)"
set_location_assignment PIN_AG37 -to host_pcie_tx[0]
set_location_assignment PIN_AG36 -to "host_pcie_tx[0](n)"
set_location_assignment PIN_AF39 -to host_pcie_tx[1]
set_location_assignment PIN_AF38 -to "host_pcie_tx[1](n)"
set_location_assignment PIN_AE37 -to host_pcie_tx[2]
set_location_assignment PIN_AE36 -to "host_pcie_tx[2](n)"
set_location_assignment PIN_AD39 -to host_pcie_tx[3]
set_location_assignment PIN_AD38 -to "host_pcie_tx[3](n)"
set_location_assignment PIN_AC37 -to host_pcie_tx[4]
set_location_assignment PIN_AC36 -to "host_pcie_tx[4](n)"
set_location_assignment PIN_AB39 -to host_pcie_tx[5]
set_location_assignment PIN_AB38 -to "host_pcie_tx[5](n)"
set_location_assignment PIN_AA37 -to host_pcie_tx[6]
set_location_assignment PIN_AA36 -to "host_pcie_tx[6](n)"
set_location_assignment PIN_Y39 -to host_pcie_tx[7]
set_location_assignment PIN_Y38 -to "host_pcie_tx[7](n)"

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
set_location_assignment PIN_AW16 -to perstn_soc_pcie
set_instance_assignment -name IO_STANDARD LVDS -to ref_clk_host_pcie -entity $top_level_entity
set_location_assignment PIN_AV18 -to perstn_host_pcie

set_instance_assignment -name IO_STANDARD "1.8 V" -to fx2_scl -entity $top_level_entity
set_instance_assignment -name IO_STANDARD "1.8 V" -to fx2_sda -entity $top_level_entity
set_instance_assignment -name SLEW_RATE 0 -to fx2_scl -entity $top_level_entity
set_instance_assignment -name SLEW_RATE 0 -to fx2_sda -entity $top_level_entity
set_location_assignment PIN_J23 -to fx2_scl
set_location_assignment PIN_K21 -to fx2_sda