set script_dir [file dirname [file normalize [info script]]]
set hw_dir [file normalize [file join $script_dir ..]]
set work_dir [file join $hw_dir build ip_packager]
set ip_dir [file join $hw_dir output ip_repo slh_dsa_shake_accel_2.0]

create_project -force slh_dsa_shake_ip $work_dir -part xc7vx485tffg1761-2
set root_dir [file normalize [file join $hw_dir ..]]
source [file join $hw_dir scripts source_manifest.tcl]
add_files -norecurse [slh_read_manifest $root_dir shake_core.f]
set_property top slh_dsa_shake_axi_lite [get_filesets sources_1]
set_property target_language Verilog [current_project]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_dir -vendor student.local \
    -library security -taxonomy /UserIP -import_files -force
set core [ipx::current_core]
set_property name slh_dsa_shake_accel $core
set_property version 2.0 $core
set_property display_name {SLH-DSA SHAKE256 F/H Accelerator v2} $core
set_property description \
    {Hardened 300 MHz AXI4-Lite accelerator for F and H in SLH-DSA-SHAKE-256f} $core
set_property company_url {https://csrc.nist.gov/pubs/fips/205/final} $core
set_property supported_families {virtex7 Production} $core
set_property core_revision 2 $core

ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

set axi_if [ipx::get_bus_interfaces s_axi -of_objects $core]
if {[llength $axi_if] == 1} {
    set_property interface_mode slave $axi_if
    set_property abstraction_type_vlnv \
        xilinx.com:interface:aximm_rtl:1.0 $axi_if
}
set clk_if [ipx::get_bus_interfaces s_axi_aclk -of_objects $core]
if {[llength $clk_if] == 1} {
    set clk_param [ipx::add_bus_parameter ASSOCIATED_BUSIF $clk_if]
    set_property value s_axi $clk_param
    set rst_param [ipx::add_bus_parameter ASSOCIATED_RESET $clk_if]
    set_property value s_axi_aresetn $rst_param
    set freq_param [ipx::add_bus_parameter FREQ_HZ $clk_if]
    set_property value 300000000 $freq_param
}

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity -quiet $core
ipx::save_core $core
puts "PACKAGED_IP=[file join $ip_dir component.xml]"
close_project
