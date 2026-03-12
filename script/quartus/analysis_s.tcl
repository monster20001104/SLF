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
    flng::run_flow_command -flow "compile" -end "dni_synthesis" -resume
}

if {$need_to_close_project} {
	project_close
}
