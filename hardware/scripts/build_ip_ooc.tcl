set script_dir [file dirname [file normalize [info script]]]
set hw_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $hw_dir build ip_ooc]
set report_dir [file join $hw_dir output ip_reports]
set target_period 3.333333
if {[info exists ::env(SLH_IP_PERIOD_NS)]} {
    set target_period $::env(SLH_IP_PERIOD_NS)
}
set target_mhz [expr {1000.0 / $target_period}]
file mkdir $build_dir
file mkdir $report_dir

create_project -force slh_dsa_shake_ip_ooc $build_dir \
    -part xc7vx485tffg1761-2
set root_dir [file normalize [file join $hw_dir ..]]
source [file join $hw_dir scripts source_manifest.tcl]
add_files -norecurse [slh_read_manifest $root_dir shake_core.f]
set_property top slh_dsa_shake_axi_lite [get_filesets sources_1]
set_property verilog_define {FMAX_FANOUT} [get_filesets sources_1]
update_compile_order -fileset sources_1

synth_design -top slh_dsa_shake_axi_lite -mode out_of_context \
    -part xc7vx485tffg1761-2 -flatten_hierarchy rebuilt
create_clock -name s_axi_aclk -period $target_period [get_ports s_axi_aclk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports s_axi_aclk]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_utilization -hierarchical \
    -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
write_checkpoint -force [file join $report_dir slh_dsa_shake_axi_lite_routed.dcp]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] == 0} {
    error "No timing path found for packaged IP"
}
set slack [get_property SLACK $worst_path]
puts "IP_WNS=$slack"
if {$slack < 0.0} {
    error "AXI IP failed $target_mhz MHz timing with WNS $slack ns"
}
puts "IP_TARGET_MHZ=$target_mhz"
puts "IP_OOC_TIMING_PASS"
close_project
