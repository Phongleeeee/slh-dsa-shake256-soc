set script_dir [file dirname [file normalize [info script]]]
set soc_dir    [file normalize [file join $script_dir ..]]
set root_dir   [file normalize [file join $soc_dir ../..]]
set build_dir  [file join $soc_dir build_ddr]
set out_dir    [file join $soc_dir output_ddr]
file mkdir $out_dir

create_project -force picorv32_slh_soc_ddr $build_dir -part xc7vx485tffg1761-2

# Match the board metadata used when the reused VC707 MIG was generated.  Keep
# the part-only fallback so the project still builds on Vivado installations
# that do not have the VC707 board files installed.
set vc707_board [get_board_parts -quiet xilinx.com:vc707:part0:1.5]
if {[llength $vc707_board] != 0} {
    set_property board_part xilinx.com:vc707:part0:1.5 [current_project]
}

source [file join $root_dir hardware scripts source_manifest.tcl]
set rtl_files [slh_read_manifest $root_dir soc_common.f]
lappend rtl_files [file join $root_dir hardware boards vc707 rtl vc707_picorv32_slh_soc_ddr.v]
lappend rtl_files [file join $root_dir hardware boards vc707 rtl vc707_axi_ddr3_bridge.sv]
add_files -norecurse $rtl_files

set ddr_ip_files [list \
    [file join $root_dir hardware boards vc707 optional_ddr3 vc707_ddr3_mig vc707_ddr3_mig.xci] \
    [file join $root_dir hardware boards vc707 optional_ddr3 vc707_axi_clock_converter vc707_axi_clock_converter.xci] \
    [file join $root_dir hardware boards vc707 optional_ddr3 vc707_axi_dwidth_converter vc707_axi_dwidth_converter.xci]]
add_files -norecurse $ddr_ip_files

if {[info exists ::env(SOC_BOOT_MEM)] && $::env(SOC_BOOT_MEM) ne ""} {
    set boot_mem [file normalize $::env(SOC_BOOT_MEM)]
} else {
    set boot_mem [file join $soc_dir firmware soc_boot.mem]
}
add_files -norecurse $boot_mem
set_property file_type {Memory Initialization Files} [get_files $boot_mem]
add_files -fileset constrs_1 -norecurse [file join $root_dir hardware boards vc707 constraints vc707_soc_ddr.xdc]

set_property top vc707_picorv32_slh_soc_ddr [current_fileset]
set_property top_auto_set 0 [current_fileset]
set_property generic "MEM_INIT_FILE=[file tail $boot_mem]" [current_fileset]
set_property verilog_define {FMAX_FANOUT} [current_fileset]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne {synth_design Complete!}} {
    error "DDR synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne {write_bitstream Complete!}} {
    error "DDR implementation failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_timing_summary -delay_type max -max_paths 20 -file [file join $out_dir timing_summary.rpt]
report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
report_drc -file [file join $out_dir drc.rpt]
if {[info exists ::env(SOC_BITSTREAM_NAME)] && $::env(SOC_BITSTREAM_NAME) ne ""} {
    set bitstream_name $::env(SOC_BITSTREAM_NAME)
} else {
    set bitstream_name picorv32_slh_dma_ddr_vc707.bit
}
file copy -force \
    [file join $build_dir picorv32_slh_soc_ddr.runs impl_1 vc707_picorv32_slh_soc_ddr.bit] \
    [file join $out_dir $bitstream_name]
puts "SOC_DDR_BUILD_PASS: [file join $out_dir $bitstream_name]"
