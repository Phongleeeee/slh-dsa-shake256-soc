# Read-only timing diagnostic for the SHAKE accelerator in the routed SoC.
# Unlike the broad hierarchy report, this report accepts only Q -> D/CE paths,
# so synchronous reset/set pins do not become the reported critical endpoint.
set script_dir [file dirname [file normalize [info script]]]
set soc_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $soc_dir build_ddr picorv32_slh_soc_ddr.runs impl_1 vc707_picorv32_slh_soc_ddr_postroute_physopt.dcp]
set report_dir [file join $soc_dir output_ddr shake_datapath_fmax]
file mkdir $report_dir
open_checkpoint $checkpoint

proc csv_field {value} {
    return "\"[string map [list \" \"\"] $value]\""
}

proc report_datapath_scope {fd id label pattern clock_name} {
    global report_dir
    set regs [get_cells -hierarchical -quiet -filter "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
    set clocks [get_clocks -quiet $clock_name]
    if {[llength $regs] == 0 || [llength $clocks] != 1} {
        puts "SCOPE_UNAVAILABLE: $id cells=[llength $regs] clock=$clock_name"
        return
    }

    set q_pins [get_pins -quiet -of_objects $regs -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
    set data_pins [get_pins -quiet -of_objects $regs -filter {DIRECTION == IN && (REF_PIN_NAME == D || REF_PIN_NAME == CE)}]
    if {[llength $q_pins] == 0 || [llength $data_pins] == 0} {
        puts "SCOPE_NO_Q_TO_DATA_PINS: $id q=[llength $q_pins] data=[llength $data_pins]"
        return
    }

    set period [get_property PERIOD $clocks]
    set paths [get_timing_paths -quiet -from $q_pins -to $data_pins -group $clock_name -delay_type max -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        puts "SCOPE_NO_Q_TO_DATA_PATH: $id"
        return
    }

    set path [lindex $paths 0]
    set slack [get_property SLACK $path]
    set requirement [get_property REQUIREMENT $path]
    set source_clock [get_property STARTPOINT_CLOCK $path]
    set destination_clock [get_property ENDPOINT_CLOCK $path]
    set fmax ""
    set status non_single_cycle_or_cross_clock
    if {$source_clock eq $clock_name && $destination_clock eq $clock_name && abs($requirement-$period) < 0.002 && ($period-$slack) > 0.0} {
        set fmax [format %.3f [expr {1000.0/($period-$slack)}]]
        set status q_to_data_single_cycle_estimate
    }

    set values [list $id $label $clock_name [format %.6f [expr {1000.0/$period}]] [format %.3f $slack] $fmax $status [llength $regs] [llength $q_pins] [llength $data_pins] [get_property STARTPOINT_PIN $path] [get_property ENDPOINT_PIN $path] [format %.3f $requirement] $source_clock $destination_clock]
    set escaped {}
    foreach value $values {lappend escaped [csv_field $value]}
    puts $fd [join $escaped ,]
    flush $fd
    report_timing -of_objects $paths -file [file join $report_dir "${id}.rpt"]
    puts "SHAKE_DATAPATH_RESULT: $id slack=${slack}ns estimate=${fmax}MHz start=[get_property STARTPOINT_PIN $path] end=[get_property ENDPOINT_PIN $path]"
}

set fd [open [file join $report_dir summary.csv] w]
puts $fd "id,label,clock,configured_mhz,q_to_data_slack_ns,q_to_data_estimate_mhz,status,sequential_cells,q_pins,data_pins,startpoint,endpoint,requirement_ns,source_clock,destination_clock"
set scopes {
    {shake_axi {SLH SHAKE AXI accelerator including nested core} {soc/peripherals/shake_accel/*} soc_clk_unbuf}
    {thash {SLH F/H controller including SHAKE} {soc/peripherals/shake_accel/hash_unit/*} soc_clk_unbuf}
    {shake_core {SHAKE256 block engine including Keccak} {soc/peripherals/shake_accel/hash_unit/core/*} soc_clk_unbuf}
    {keccak {Keccak-f1600} {soc/peripherals/shake_accel/hash_unit/core/permutation/*} soc_clk_unbuf}
}
foreach scope $scopes {report_datapath_scope $fd {*}$scope}
close $fd
puts "SHAKE_DATAPATH_TIMING_PASS: [file join $report_dir summary.csv]"
