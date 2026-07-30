read_xdc [file join [file dirname $script_path] cmoda7.xdc]

synth_design -top scoooter_cmod_a7_top
puts "Finished synth_design"

source [file join [file dirname $script_path] jtag_clocking.tcl]
configure_jtag_tdo_falling_edge

report_timing_summary -file $project_dir/${project_name}_synth_timing.rpt
report_utilization -file $project_dir/${project_name}_synth_utilization.rpt
report_drc -file $project_dir/${project_name}_synth_drc.rpt
write_checkpoint -force $project_dir/${project_name}_synth.dcp

puts "SCOOOTER_CMOD_SYNTHESIS_SUCCEEDED"
