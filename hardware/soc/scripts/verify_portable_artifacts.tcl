# Read-only acceptance recheck of the exact published checkpoint.
set script_dir [file dirname [file normalize [info script]]]
set soc_dir [file normalize [file join $script_dir ..]]
set out_dir [file join $soc_dir output_portable]
open_checkpoint [file join $out_dir portable_soc_routed.dcp]
report_methodology -file [file join $out_dir methodology.rpt]
if {[llength [get_drc_ruledecks -quiet bitstream_checks]]} {
    report_drc -ruledeck bitstream_checks -file [file join $out_dir bitstream_drc.rpt]
}
source [file join $script_dir check_portable_timing.tcl]
puts "PORTABLE_ARTIFACT_RECHECK_PASS"
