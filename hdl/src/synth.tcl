# synth
synth_design -top mkFPGATestSimpleTop
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

write_checkpoint $project_dir/${project_name}_chkpt.dcp -force

write_bitstream -file $project_dir/${project_name}_out.bit