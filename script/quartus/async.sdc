# (C) 2001-2024 Intel Corporation. All rights reserved.
# Your use of Intel Corporation's design tools, logic functions and other 
# software and tools, and its AMPP partner logic functions, and any output 
# files from any of the foregoing (including device programming or simulation 
# files), and any associated documentation or information are expressly subject 
# to the terms and conditions of the Intel Program License Subscription 
# Agreement, Intel FPGA IP License Agreement, or other applicable 
# license agreement, including, without limitation, that your use is for the 
# sole purpose of programming logic devices manufactured by Intel and sold by 
# Intel or its authorized distributors.  Please refer to the applicable 
# agreement for further details.


# constraints for DCFIFO sdc
#
# top-level sdc
# convention for module sdc apply_sdc_<module_name>
#
proc apply_sdc_dcfifo {hier_path} {
# gray_rdptr
apply_sdc_dcfifo_rdptr $hier_path
# gray_wrptr
apply_sdc_dcfifo_wrptr $hier_path
}
#
# common constraint setting proc
#
proc apply_sdc_dcfifo_for_ptrs {from_node_list to_node_list} {
# control skew for bits
set_max_skew -from $from_node_list -to $to_node_list -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8
# path delay (exception for net delay)
if { ![string equal "quartus_syn" $::TimeQuestInfo(nameofexecutable)] } {
set_net_delay -from $from_node_list -to $to_node_list -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8
}
#relax setup and hold calculation
set_max_delay -from $from_node_list -to $to_node_list 100
set_min_delay -from $from_node_list -to $to_node_list -100
}
#
# mstable propgation delay
#
proc apply_sdc_dcfifo_mstable_delay {from_node_list to_node_list} {
# mstable delay
if { ![string equal "quartus_syn" $::TimeQuestInfo(nameofexecutable)] } {
set_net_delay -from $from_node_list -to $to_node_list -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8
}
}
#
# rdptr constraints
#
proc apply_sdc_dcfifo_rdptr {hier_path} {
# get from and to list
set from_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|*rdptr_g*]
set to_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|ws_dgrp|dffpipe*|dffe*]
apply_sdc_dcfifo_for_ptrs $from_node_list $to_node_list
# mstable
set from_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|ws_dgrp|dffpipe*|dffe*]
set to_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|ws_dgrp|dffpipe*|dffe*]
apply_sdc_dcfifo_mstable_delay $from_node_mstable_list $to_node_mstable_list
}
#
# wrptr constraints
#
proc apply_sdc_dcfifo_wrptr {hier_path} {
# control skew for bits
set from_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|delayed_wrptr_g*]
set to_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|rs_dgwp|dffpipe*|dffe*]
apply_sdc_dcfifo_for_ptrs $from_node_list $to_node_list
# mstable
set from_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|rs_dgwp|dffpipe*|dffe*]
set to_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|rs_dgwp|dffpipe*|dffe*]
apply_sdc_dcfifo_mstable_delay $from_node_mstable_list $to_node_mstable_list
}

proc apply_sdc_pre_dcfifo {entity_name} {

set inst_list [get_entity_instances $entity_name]

foreach each_inst $inst_list {

        apply_sdc_dcfifo ${each_inst} 

    }
}
apply_sdc_pre_dcfifo yucca_async_fifo

set_false_path -to *dcfifo:dcfifo_component|dcfifo_*:auto_generated|dffpipe_*:wraclr|dffe*a[0]
set_false_path -to *dcfifo:dcfifo_component|dcfifo_*:auto_generated|dffpipe_*:rdaclr|dffe*a[0]


############################################
# sync_reg timing constraints
############################################
set     module_name "sync_reg"
set     inst_path [get_entity_instances ${module_name}]

foreach each_inst_path $inst_path {
    set cell_name "din_sync*"
    foreach each_cell $cell_name {
        set node [get_keepers ${each_inst_path}|${each_cell}]
        foreach each_node $node {
            set_max_delay -to $each_node  100
            set_min_delay -to $each_node -100
        }
    }
}

############################################
# multi_bit_ctrl_signal_cdc timing constraints
############################################
set     module_name "multi_bit_ctrl_signal_cdc"
set     inst_path [get_entity_instances ${module_name}]

foreach each_inst_path $inst_path {
    set cell_name "sync_din2dout_valid*"
    foreach each_cell $cell_name {
        set node [get_keepers ${each_inst_path}|${each_cell}]
        foreach each_node $node {
            set_max_delay -to $each_node  100
            set_min_delay -to $each_node -100
        }
    }
}

foreach each_inst_path $inst_path {
    set cell_name "sync_din2dout_ack*"
    foreach each_cell $cell_name {
        set node [get_keepers ${each_inst_path}|${each_cell}]
        foreach each_node $node {
            set_max_delay -to $each_node  100
            set_min_delay -to $each_node -100
        }
    }
}

foreach each_inst_path $inst_path {
    set cell_name "sync_ack_confirm*"
    foreach each_cell $cell_name {
        set node [get_keepers ${each_inst_path}|${each_cell}]
        foreach each_node $node {
            set_max_delay -to $each_node  100
            set_min_delay -to $each_node -100
        }
    }
}

foreach each_inst_path $inst_path {
    set cell_name "recv_data*"
    foreach each_cell $cell_name {
        set node [get_keepers ${each_inst_path}|${each_cell}]
        foreach each_node $node {
            set_max_delay -to $each_node  100
            set_min_delay -to $each_node -100
        }
    }
}