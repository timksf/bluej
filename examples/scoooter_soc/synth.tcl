read_xdc [file join [file dirname $script_path] cmoda7.xdc]

synth_design -top scoooter_cmod_a7_top
puts "Finished synth_design"

source [file join [file dirname $script_path] jtag_clocking.tcl]
configure_jtag_tdo_falling_edge

report_timing_summary -file $project_dir/${project_name}_synth_timing.rpt
report_utilization -file $project_dir/${project_name}_synth_utilization.rpt
report_drc -file $project_dir/${project_name}_synth_drc.rpt
write_checkpoint -force $project_dir/${project_name}_synth.dcp

opt_design
puts "Finished opt_design"

report_timing_summary -file $project_dir/${project_name}_opt_timing.rpt
report_utilization -file $project_dir/${project_name}_opt_utilization.rpt
report_drc -file $project_dir/${project_name}_opt_drc.rpt
write_checkpoint -force $project_dir/${project_name}_opt.dcp

place_design
puts "Finished place_design"

report_timing_summary -file $project_dir/${project_name}_placed_timing.rpt
report_utilization -file $project_dir/${project_name}_placed_utilization.rpt
write_checkpoint -force $project_dir/${project_name}_placed.dcp

route_design
puts "Finished route_design"

report_timing_summary -file $project_dir/${project_name}_routed_timing.rpt
report_timing -delay_type min -max_paths 50 \
    -file $project_dir/${project_name}_routed_hold.rpt
report_utilization -file $project_dir/${project_name}_routed_utilization.rpt
report_drc -file $project_dir/${project_name}_routed_drc.rpt
write_checkpoint -force $project_dir/${project_name}_routed.dcp

phys_opt_design
puts "Finished phys_opt_design"

phys_opt_design -directive ExploreWithAggressiveHoldFix
puts "Finished phys_opt_design -directive ExploreWithAggressiveHoldFix"

report_timing_summary -file $project_dir/${project_name}_timing.rpt
report_timing -delay_type min -max_paths 50 \
    -file $project_dir/${project_name}_hold.rpt
report_utilization -file $project_dir/${project_name}_utilization.rpt
report_drc -file $project_dir/${project_name}_drc.rpt
write_checkpoint -force $project_dir/${project_name}_physopt.dcp

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
write_bitstream -force $project_dir/${project_name}.bit
puts "Finished write_bitstream"
puts "SCOOOTER_CMOD_BITSTREAM_SUCCEEDED"
