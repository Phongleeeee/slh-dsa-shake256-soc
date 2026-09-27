set script_dir [file dirname [file normalize [info script]]]
set hw_dir [file normalize [file join $script_dir ..]]
set project_name sphincs_shake256_vc707
set project_file [file join $hw_dir build vivado $project_name.xpr]
if {![file exists $project_file]} { error "Run create_project.tcl first" }
open_project $project_file
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set status [get_property STATUS [get_runs impl_1]]
if {![string match "write_bitstream Complete*" $status]} {
    error "Implementation failed: $status"
}
open_run impl_1
set output_dir [file join $hw_dir output]
set report_dir [file join $output_dir reports]
file mkdir $report_dir
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
set source_bit [file join $hw_dir build vivado "$project_name.runs" impl_1 vc707_sphincs_shake256_selftest.bit]
set critical_path [get_timing_paths -max_paths 1]
set slack [get_property SLACK [lindex $critical_path 0]]
puts "WORST_SETUP_SLACK_NS=$slack"
if {$slack < 0.0} {
    error "Timing failed with WNS=$slack ns; firmware was not published"
}
set output_bit [file join $output_dir sphincs_shake256_vc707_250mhz.bit]
file copy -force $source_bit $output_bit
puts "FIRMWARE=$output_bit"
