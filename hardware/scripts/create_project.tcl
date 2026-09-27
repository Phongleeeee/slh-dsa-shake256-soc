set script_dir [file dirname [file normalize [info script]]]
set hw_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $hw_dir build vivado]
set project_name sphincs_shake256_vc707

create_project -force $project_name $project_dir -part xc7vx485tffg1761-2
set root_dir [file normalize [file join $hw_dir ..]]
source [file join $hw_dir scripts source_manifest.tcl]
add_files -norecurse [slh_read_manifest $root_dir shake_core.f]
add_files -norecurse [file join $hw_dir boards vc707 rtl vc707_sphincs_shake256_selftest.v]
add_files -fileset constrs_1 [file join $hw_dir boards vc707 constraints vc707_shake_selftest.xdc]
add_files -fileset sim_1 [list \
    [file join $hw_dir sim tb_shake256_block_engine.v] \
    [file join $hw_dir sim tb_spx_thash_shake256_simple_256.v] \
    [file join $hw_dir sim tb_slh_dsa_shake_axi_lite.v] \
    [file join $hw_dir sim tb_vc707_sphincs_shake256_selftest.v]]
set_property top vc707_sphincs_shake256_selftest [get_filesets sources_1]
set_property top tb_vc707_sphincs_shake256_selftest [get_filesets sim_1]
set_property verilog_define {FMAX_FANOUT} [get_filesets sources_1]
set_property target_language Verilog [current_project]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "MAIN_PROJECT=[file join $project_dir $project_name.xpr]"
