# Also installed as the project's write-bitstream PRE hook.
# No bitstream may be generated through the GUI with failing setup/hold.
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "PORTABLE_TIMING_GATE: setup=$wns ns hold=$whs ns"
if {$wns eq "" || $whs eq "" || $wns < 0 || $whs < 0} {
    error "Timing failed or unavailable; bitstream generation blocked"
}
