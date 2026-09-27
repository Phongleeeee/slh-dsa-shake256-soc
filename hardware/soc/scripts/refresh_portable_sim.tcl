# Refresh simulation-only GUI properties without touching RTL or the bitstream.
set here [file dirname [file normalize [info script]]]
set soc [file normalize [file join $here ..]]
open_project [file join $soc build_portable portable_slh_soc.xpr]
source [file join $here configure_portable_sim.tcl]
close_project
puts "PORTABLE_SIM_PROJECT_REFRESH_PASS"
