
package require ::quartus::project

set project_name [lindex $argv 0]
set project_dir [lindex $argv 1]
set top_level_entity [lindex $argv 2]
set hash [lindex $argv 3]
set for_factory [lindex $argv 4]
set pins_file [lindex $argv 5]
set family [lindex $argv 6]
set device [lindex $argv 7]
set version [lindex $argv 8]
set timestamp [lindex $argv 9]
set pmon_en [lindex $argv 10]
set board_name [lindex $argv 11]
set debug_en [lindex $argv 12]
set need_to_close_project 1
set make_assignments 1

	# Only open if not already open
if {[project_exists $project_dir/$project_name]} {
	project_open -revision $top_level_entity $project_dir/$project_name
    puts "Project $project_dir/$project_name is exist"
    set make_assignments 0
} else {
    project_new -overwrite -revision $top_level_entity $project_dir/$project_name
}

proc get_all_files {dir file_type {specific_subdirs {}}} {
    set files [list]
    foreach file [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $file]} {
            # 如果是子目录，检查是否在指定的子目录列表中
            set dirname [file tail $file]
            if {[llength $specific_subdirs] == 0 || [lsearch -exact $specific_subdirs $dirname] != -1} {
                # 如果是子目录，递归调用 get_all_files
                foreach sub_file [get_all_files $file $file_type $specific_subdirs] {
                    lappend files $sub_file
                }
            }
        } else {
            # 如果是文件，检查文件扩展名是否匹配
            set ext [file extension $file]
            if {[string match $file_type $ext]} {
                lappend files $file
            }
        }
    }
    return $files
}

if {$make_assignments} {
    set specific_subdirs [list "beq" "beq_loop_test" "emu" "mgmt" "pcie_switch" "sgdma" "tlp_adap_arbiter" "tlp_adaptor" "top" \
    "virtio2" "virtio_desc_engine" "common" "virtio_blk_desc_engine" "virtio_blk_upstream" "virtio_idx_engine" "virtio_rx_buf" "virtio_netrx" "virtio_used" \
    "virtio_avail_ring" "virtio_blk_downstream" "virtio_irq_merge_core" "virtio_nettx" "qos" "tso_csum"]
    ##sv文件
    set file_type_sv "*.sv"
    set common_files_sv [get_all_files ../common $file_type_sv]
    set src_files_sv [get_all_files ../src $file_type_sv $specific_subdirs]
    set all_files_sv [concat $common_files_sv $src_files_sv]
    foreach file $all_files_sv {
        set_global_assignment -name SYSTEMVERILOG_FILE $file
    }
    ##svh文件
    set file_type_svh "*.svh"
    set common_files_svh [get_all_files ../common $file_type_svh]
    set src_files_svh [get_all_files ../src $file_type_svh $specific_subdirs]
    set all_files_svh [concat $common_files_svh $src_files_svh]
    foreach file $all_files_svh {
        set_global_assignment -name SOURCE_FILE $file
    }
    ##ip文件
    set file_type_ip "*.ip"
    set ip_files [get_all_files ../ip $file_type_ip]
    foreach file $ip_files {
        set_global_assignment -name IP_FILE $file
    }
    ##sdc文件
    set file_type_sdc "*.sdc"
    set sdc_files [get_all_files ../script $file_type_sdc]
    foreach file $sdc_files {
        set_global_assignment -name SDC_FILE $file
    }

    #哈希值
    set_global_assignment -name VERILOG_MACRO "GIT_HASH=32'h$hash"
    set_global_assignment -name VERILOG_MACRO "VERSION=32'h$version"
    set_global_assignment -name VERILOG_MACRO "TIME_STAMP=64'h$timestamp"
    #FOR_FACTORY
    if {$for_factory} {
        set_global_assignment -name VERILOG_MACRO "FOR_FACTORY=<None>"
    }
    if {${board_name} eq "catapult"} {
        set_global_assignment -name VERILOG_MACRO "DEV_BOARD=<None>"
    }
    if {$pmon_en} {
        set_global_assignment -name VERILOG_MACRO "PMON_EN=<None>"
    }
    if {$debug_en} {
        set_global_assignment -name VERILOG_MACRO "DEBUG_EN=<None>"
    }
    #语言
    set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
    #环境
    set_global_assignment -name FAMILY "$family"
    set_global_assignment -name DEVICE $device
    set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
    set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
    set_global_assignment -name MAX_CORE_JUNCTION_TEMP 100
    set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 2
    set_global_assignment -name SEARCH_PATH ../src/pcie_switch
	set_global_assignment -name SEARCH_PATH ../src/beq
    set_global_assignment -name SEARCH_PATH ../src/virtio2
    set_global_assignment -name SEARCH_PATH ../src/virtio2/virtio_used
    set_global_assignment -name SEARCH_PATH ../src/virtio2/virtio_desc_engine
    set_global_assignment -name SEARCH_PATH ../src/virtio2/virtio_rx_buf
	set_global_assignment -name SEARCH_PATH ../common/interfaces
    set_global_assignment -name ENABLE_OCT_DONE OFF
    set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "ACTIVE SERIAL X4"
    set_global_assignment -name USE_CONFIGURATION_DEVICE ON
    set_global_assignment -name CRC_ERROR_OPEN_DRAIN ON
    set_global_assignment -name RESERVE_DATA0_AFTER_CONFIGURATION "USE AS REGULAR IO"
    set_global_assignment -name ACTIVE_SERIAL_CLOCK FREQ_100MHZ
    set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
    set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"
    set_global_assignment -name POWER_APPLY_THERMAL_MARGIN ADDITIONAL
    set_global_assignment -name INTERNAL_SCRUBBING OFF
    set_global_assignment -name ENABLE_SIGNALTAP ON
    set_global_assignment -name EDA_TIME_SCALE "1 ps" -section_id eda_simulation
    set_global_assignment -name EDA_OUTPUT_DATA_FORMAT "VERILOG HDL" -section_id eda_simulation
    set_global_assignment -name FLOW_DISABLE_ASSEMBLER ON
    set_global_assignment -name BOARD default
    set_instance_assignment -name PARTITION_COLOUR 4291659519 -to $top_level_entity -entity $top_level_entity
    set_instance_assignment -name PARTITION_COLOUR 4294967199 -to auto_fab_0 -entity $top_level_entity
    set_global_assignment -name OPTIMIZATION_MODE "High performance effort"
    set_global_assignment -name VCCP_USER_VOLTAGE 0.95V
    set_global_assignment -name NOMINAL_CORE_SUPPLY_VOLTAGE 0.95V
    set_global_assignment -name VCCBAT_USER_VOLTAGE 1.8V
    set_global_assignment -name VCCERAM_USER_VOLTAGE 0.95V
    set_global_assignment -name VERILOG_MACRO "MS_100_CLEAN_CNT_AT_USER_CLK=32'd22000000"

    #电平
	source ../script/quartus/${pins_file}.tcl
    if {${pins_file} eq "YD025G2AA_pins"} {
        source ../script/quartus/YD025G2AA_empty_region.tcl
    }

    flng::run_flow_command -flow "compile" -end "dni_ipgenerate" -resume
}
if {$need_to_close_project} {
	project_close
}
