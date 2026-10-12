# synth
set script_dir [file dirname [file normalize [info script]]]
set bluej_dir  [file normalize [file join $script_dir .. script]]

# source [file join $bluej_dir jtag2axi.tcl]

# read_xdc [file join $script_dir cmoda7.xdc]
read_xdc [file join $script_dir pa200t.xdc]
synth_design -top $top_module
puts "Finished synth_design"

# implement
opt_design

report_timing_summary -file $project_dir/${project_name}_tim1.rpt
report_utilization -file $project_dir/${project_name}_util1.rpt
report_drc -file $project_dir/${project_name}_drc1.rpt
puts "Finished opt_design"

place_design

report_timing_summary -file $project_dir/${project_name}_tim2.rpt
report_utilization -file $project_dir/${project_name}_util2.rpt
puts "Finished place_design"

route_design
puts "Finished route_design"

phys_opt_design
puts "Finished phys_opt_design"

report_timing_summary -file $project_dir/${project_name}_tim3.rpt
report_utilization -file $project_dir/${project_name}_util3.rpt
report_drc -file $project_dir/${project_name}_drc3.rpt
report_methodology -file $project_dir/${project_name}_method3.rpt

write_checkpoint $project_dir/${project_name}_physopt.dcp -force

write_bitstream -file $project_dir/${project_name}_out.bit
