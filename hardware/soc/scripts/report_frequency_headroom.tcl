# Diagnostic only: retime the same placement at supported MMCM divides.
# Firmware CLOCK_HZ/UART constants are NOT changed; never emit a bitstream.
if {$argc != 2} {error "Usage: -tclargs input.dcp output.csv"}
open_checkpoint [file normalize [lindex $argv 0]]
set fd [open [file normalize [lindex $argv 1]] w]
puts $fd "divide,clock_mhz,setup_slack_ns,hold_slack_ns,scope"
foreach divide {3.625 3.5 3.375 3.25} {
    set_property CLKOUT0_DIVIDE_F $divide [get_cells clock_mmcm]
    update_timing
    set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    puts $fd "$divide,[expr {1000.0/$divide}],$setup,$hold,timing-only-not-a-release"
}
close $fd
