# Source after opening the routed portable design. Include incoming boundary
# paths in each scope so fast internal datapaths do not hide a slow AXI path.
set report_dir [file join $out_dir ip_timing]
file mkdir $report_dir
set fd [open [file join $report_dir summary.csv] w]
puts $fd "ip,clock_mhz,setup_slack_ns,estimated_limit_mhz,startpoint,endpoint"
foreach {name pattern} {
    CPU soc/cpu/*
    AXI soc/fabric/interconnect_ip_inst/*
    RAM0 soc/fabric/ram0/*
    RAM1 soc/fabric/ram1/*
    RAM2 soc/fabric/ram2/*
    SHAKE_AXI soc/peripherals/shake_accel/*
    SHAKE_core soc/peripherals/shake_accel/hash_unit/core/*
    Keccak soc/peripherals/shake_accel/hash_unit/core/permutation/*
    DMA_IOMMU soc/dma_iommu/*
    IOMMU soc/dma_iommu/iommu_inst/*
    UART soc/peripherals/uart/*
    Timer_GPIO soc/peripherals/timer_gpio/*
    Peripheral_bridge soc/peripherals/*
} {
    set cells [get_cells -hier -quiet -filter "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
    if {[llength $cells] == 0} {continue}
    set paths [get_timing_paths -quiet -to $cells -delay_type max -max_paths 1]
    if {[llength $paths] == 0} {continue}
    set path [lindex $paths 0]
    set clock_name [get_property ENDPOINT_CLOCK $path]
    set period [get_property PERIOD [get_clocks $clock_name]]
    set slack [get_property SLACK $path]
    set estimate "NA"
    if {[get_property STARTPOINT_CLOCK $path] eq $clock_name && abs([get_property REQUIREMENT $path]-$period) < 0.002} {
        set estimate [format %.3f [expr {1000.0/($period-$slack)}]]
    }
    puts $fd "$name,[format %.3f [expr {1000.0/$period}]],[format %.3f $slack],$estimate,\"[get_property STARTPOINT_PIN $path]\",\"[get_property ENDPOINT_PIN $path]\""
    report_timing -of_objects $paths -file [file join $report_dir "$name.rpt"]
}
close $fd
