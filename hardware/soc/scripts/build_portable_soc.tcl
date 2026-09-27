set script_dir [file dirname [file normalize [info script]]]
set soc_dir [file normalize [file join $script_dir ..]]
set root_dir [file normalize [file join $soc_dir ../..]]
set mhz 296.296296
if {[info exists ::env(PORTABLE_SOC_MHZ)]} {set mhz $::env(PORTABLE_SOC_MHZ)}
set divide [expr {1000.0/double($mhz)}]
if {abs($divide*8-round($divide*8)) > 0.0001} {error "Clock frequency requires an MMCM fractional divide in 0.125 steps"}
set build_dir [file join $soc_dir build_portable]
set out_dir [file join $soc_dir output_portable]
if {[info exists ::env(PORTABLE_SOC_EXPERIMENT)] && $::env(PORTABLE_SOC_EXPERIMENT) ne ""} {
    set experiment $::env(PORTABLE_SOC_EXPERIMENT)
    if {![regexp {^[A-Za-z0-9_-]+$} $experiment]} {error "Invalid experiment name"}
    set experiment_dir [file join $out_dir experiments $experiment]
    set build_dir [file join $experiment_dir build]
    set out_dir [file join $experiment_dir results]
}
file mkdir $out_dir
set reuse 0
if {[info exists ::env(PORTABLE_SOC_REUSE_SYNTH)]} {set reuse $::env(PORTABLE_SOC_REUSE_SYNTH)}
if {$reuse} {
    open_project [file join $build_dir portable_slh_soc.xpr]
    set expected "MEM_INIT_FILE=slh_dsa_portable.mem CLOCK_HZ=[expr {round($mhz*1000000)}] CLKOUT_DIVIDE=$divide"
    if {[get_property generic [current_fileset]] ne $expected} {error "Reuse requires the exact same clock/generics as the synthesized project"}
    set checkpoint [file join $build_dir portable_slh_soc.runs synth_1 vc707_portable_wrapper.dcp]
    if {![file exists $checkpoint]} {error "Missing synthesis checkpoint"}
    foreach f [get_files -of_objects [get_filesets sources_1]] {
        set source_path [get_property NAME $f]
        if {[file exists $source_path] && [file mtime $source_path] > [file mtime $checkpoint]} {
            error "Source changed since synthesis: $source_path. Use a full build."
        }
    }
    reset_runs impl_1
} else {
create_project -force portable_slh_soc $build_dir -part xc7vx485tffg1761-2
source [file join $root_dir hardware scripts source_manifest.tcl]
set rtl_files [slh_read_manifest $root_dir soc_common.f]
lappend rtl_files [file join $root_dir hardware boards vc707 rtl vc707_portable_wrapper.v]
add_files -norecurse $rtl_files
set boot_mem [file join $soc_dir firmware slh_dsa_portable.mem]
add_files -norecurse $boot_mem
set_property file_type {Memory Initialization Files} [get_files $boot_mem]
add_files -fileset constrs_1 -norecurse [file join $root_dir hardware boards vc707 constraints vc707_portable.xdc]
set_property top vc707_portable_wrapper [current_fileset]
set_property generic "MEM_INIT_FILE=[file tail $boot_mem] CLOCK_HZ=[expr {round($mhz*1000000)}] CLKOUT_DIVIDE=$divide" [current_fileset]
set_property verilog_define {FMAX_FANOUT} [current_fileset]
update_compile_order -fileset sources_1
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne {synth_design Complete!}} {error "Portable synthesis failed"}
}
source [file join $script_dir configure_portable_sim.tcl]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveFanoutOpt [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
set route_status [get_property STATUS [get_runs impl_1]]
set run_dir [get_property DIRECTORY [get_runs impl_1]]
set routed_checkpoint [file join $run_dir vc707_portable_wrapper_routed.dcp]
set route_begin [file join $run_dir .route_design.begin.rst]
set route_end [file join $run_dir .route_design.end.rst]
# STATUS can legitimately read "Not started phys_opt_design (Post-Route)"
# after stopping at route_design. Check the completed route artifacts instead.
if {![file exists $routed_checkpoint] || ![file exists $route_begin] || ![file exists $route_end] ||
    [file mtime $routed_checkpoint] < [file mtime $route_begin]} {error "Portable route failed: $route_status"}
source [file join $script_dir finalize_portable_build.tcl]
