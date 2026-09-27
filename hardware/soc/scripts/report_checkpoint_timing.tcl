# Usage:
#   vivado -mode batch -source report_checkpoint_timing.tcl \
#          -tclargs <checkpoint.dcp> <report.rpt>
#
# Small reusable helper for inspecting an intermediate implementation result
# without reopening the complete project in the GUI.
if {$argc != 2} {
    error "usage: report_checkpoint_timing.tcl <checkpoint.dcp> <report.rpt>"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_file [file normalize [lindex $argv 1]]

open_checkpoint $checkpoint
report_timing_summary -delay_type max -max_paths 20 -file $report_file
report_timing -delay_type max -max_paths 20 -file "${report_file}.paths"
puts "TIMING_REPORT_PASS: $report_file"
