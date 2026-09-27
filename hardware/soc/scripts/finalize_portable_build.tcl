# Finish an already routed portable project (no synthesis/route rerun).
set script_dir [file dirname [file normalize [info script]]]
set soc_dir [file normalize [file join $script_dir ..]]
if {![info exists out_dir]} {set out_dir [file join $soc_dir output_portable]}
if {[llength [get_projects -quiet]] == 0} {
    open_project [file join $soc_dir build_portable portable_slh_soc.xpr]
}
source [file join $script_dir configure_portable_sim.tcl]
set timing_hook [file join $script_dir check_portable_timing.tcl]
if {[llength [get_files -quiet $timing_hook]] == 0} {
    add_files -fileset utils_1 -norecurse $timing_hook
}
set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $script_dir check_portable_timing.tcl] [get_runs impl_1]
set run_dir [get_property DIRECTORY [get_runs impl_1]]
set routed_checkpoint [file join $run_dir vc707_portable_wrapper_routed.dcp]
if {![file exists [file join $run_dir .route_design.end.rst]]} {error "Missing completed route"}
# A paused project with post-route phys_opt pending may refuse open_run.
# The completed routed checkpoint is the unambiguous input to finalization.
open_checkpoint $routed_checkpoint
phys_opt_design -directive AggressiveExplore
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained -file [file join $out_dir timing_summary.rpt]
report_timing -max_paths 30 -file [file join $out_dir critical_paths.rpt]
report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
report_drc -file [file join $out_dir drc.rpt]
source [file join $script_dir report_portable_ip_timing.tcl]
write_checkpoint -force [file join $out_dir portable_soc_routed.dcp]
source [file join $script_dir check_portable_timing.tcl]
set mhz [expr {1000.0/[get_property PERIOD [get_clocks -of_objects [get_pins clock_mmcm/CLKOUT0]]]}]
puts "PORTABLE_TIMING: target=$mhz MHz setup=$wns ns hold=$whs ns"
write_bitstream -force [file join $out_dir portable_slh_soc_vc707.bit]
puts "PORTABLE_SOC_BUILD_PASS: [file join $out_dir portable_slh_soc_vc707.bit]"
