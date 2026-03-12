package require ::quartus::project

set project_name [lindex $argv 0]
set project_dir [lindex $argv 1]
set top_level_entity [lindex $argv 2]


set need_to_close_project 1
set make_anne 1

	# Only open if not already open
if {[project_exists $project_dir/$project_name]} {
	project_open -revision $top_level_entity $project_dir/$project_name
} else {
    puts "Project $project_dir/$project_name is not exist"
    set make_anne 0
    set need_to_close_project 0
}

if {$make_anne} {
    flng::run_flow_command -flow "compile" -end "sta_signoff" -resume
    flng::run_flow_command -flow "compile" -start "assembler" -end "assembler"

    set summary_file "../build/output_files/dpu_top.sta.summary"
    if {[file exists $summary_file]} {
        set fp [open $summary_file r]
        set lines [split [read $fp] "\n"]
        close $fp

        set entries {}

        for {set i 0} {$i < [expr {[llength $lines] - 3}]} {incr i} {
            set line [string trim [lindex $lines $i]]
            if {$line eq "" || [string match "---*" $line]} {
                continue
            }
            if {[string first "Type" $line] == 0} {
                set type_field [string trim [lindex [split $line ":"] 1]]
                set parts [split $type_field "'"]
                set type [string trim [lindex $parts 0]]
                set clock [string trim [lindex $parts 1]]

                set slack_line [string trim [lindex $lines [expr {$i + 1}]]]
                set slack [string trim [lindex [split $slack_line ":"] 1]]

                set tns_line [string trim [lindex $lines [expr {$i + 2}]]]
                set tns [string trim [lindex [split $tns_line ":"] 1]]

                set corner_line [string trim [lindex $lines [expr {$i + 3}]]]
                set corner [string trim [lindex [split $corner_line ":"] 1]]

                if {[catch {set slack_num [expr {double($slack)}]}]} {
                    puts "worring: slack '$slack'"
                    continue
                }

                lappend entries [list $type $clock $slack $tns $corner $slack_num]
                incr i 3
            }
        }

        if {[llength $entries] == 0} {
            puts "empty"
            exit 0
        }

        set sorted_entries [lsort -real -increasing -index 5 $entries]
        set num_to_show [expr {min(4, [llength $sorted_entries])}]

        puts "================================================"
        for {set i 0} {$i < $num_to_show} {incr i} {
            set entry [lindex $sorted_entries $i]
            puts "[expr {$i + 1}]. Type: [lindex $entry 0] '[lindex $entry 1]'"
            puts "   Slack  : [lindex $entry 2] ns"
            puts "   TNS    : [lindex $entry 3] ns"
            puts "   Corner : [lindex $entry 4]"
            puts ""
        }
    } else {
        puts "Error: File $summary_file does not exist."
    }    
}

if {$need_to_close_project} {
	project_close
}
