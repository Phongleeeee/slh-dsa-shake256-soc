# Validate moved source paths and elaborate RTL. Does not synthesize/route/emit a bitstream.
set here [file dirname [file normalize [info script]]]
set soc [file normalize [file join $here ..]]
set root [file normalize [file join $soc ../..]]
open_project [file join $soc build_portable portable_slh_soc.xpr]
source [file join $root hardware scripts source_manifest.tcl]
set expected [slh_read_manifest $root soc_common.f]
lappend expected [file join $root hardware boards vc707 rtl vc707_portable_wrapper.v]
lappend expected [file join $soc firmware slh_dsa_portable.mem]
set actual {}
foreach f [get_files -of_objects [get_filesets sources_1]] {
    lappend actual [file normalize [get_property NAME $f]]
}
if {[lsort $actual] ne [lsort $expected]} {error "Project sources differ from the canonical manifest"}
foreach set_name {sources_1 constrs_1 sim_1 utils_1} {
    foreach f [get_files -of_objects [get_filesets $set_name]] {
        set name [get_property NAME $f]
        if {![file isfile $name]} {error "Missing project file: $name"}
    }
}
source [file join $here configure_portable_sim.tcl]
update_compile_order -fileset sources_1
report_compile_order -used_in synthesis -file [file join $soc output_portable reorganization_compile_order.rpt]
synth_design -rtl -name relocated_rtl -top vc707_portable_wrapper
puts "REORGANIZED_PROJECT_ELABORATION_PASS"
close_design
close_project
