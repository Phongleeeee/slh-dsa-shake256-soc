# Timing-only experiment; never publishes a deployable bitstream.
# Explicit inputs prevent accidental overwrite of a previous frequency result.
set here [file dirname [file normalize [info script]]]
set soc_dir [file normalize [file join $here ..]]
set root_dir [file normalize [file join $soc_dir ../..]]
if {![info exists ::env(PORTABLE_PROBE_DCP)] || ![info exists ::env(PORTABLE_PROBE_NAME)]} {
    error "Set PORTABLE_PROBE_DCP and PORTABLE_PROBE_NAME for an explicit diagnostic checkpoint/output"
}
if {![regexp {^[A-Za-z0-9_-]+$} $::env(PORTABLE_PROBE_NAME)]} {error "Invalid experiment name"}
set out [file join $soc_dir output_portable probes $::env(PORTABLE_PROBE_NAME)]
file mkdir $out
open_checkpoint $::env(PORTABLE_PROBE_DCP)
read_xdc [file join $root_dir hardware boards vc707 constraints vc707_portable.xdc]
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive AggressiveFanoutOpt
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $out timing_summary.rpt]
report_timing -max_paths 30 -file [file join $out critical_paths.rpt]
write_checkpoint -force [file join $out routed.dcp]
puts "PORTABLE_PROBE_WNS: [get_property SLACK [get_timing_paths -max_paths 1]]"
