# Read-only diagnostic of the current routed SoC.  No synthesis, placement,
# constraints, source files or bitstream are changed.  Only reports are written.
# Usage: vivado -mode batch -source report_ip_scoped_timing.tcl
set script_dir [file dirname [file normalize [info script]]]
set soc_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $soc_dir build_ddr picorv32_slh_soc_ddr.runs impl_1 vc707_picorv32_slh_soc_ddr_postroute_physopt.dcp]
set report_dir [file join $soc_dir output_ddr ip_scoped_timing]
file mkdir $report_dir
open_checkpoint $checkpoint

proc csv_field {value} {
    return "\"[string map [list \" \"\"] $value]\""
}

proc report_scope {fd id label patterns clock_name} {
    global report_dir
    set regs {}
    foreach pattern $patterns {
        set cells [get_cells -hierarchical -quiet -filter "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
        set regs [lsort -unique [concat $regs $cells]]
    }
    set clocks [get_clocks -quiet $clock_name]
    if {[llength $regs] == 0 || [llength $clocks] != 1} {
        puts "SCOPE_UNAVAILABLE: $id cells=[llength $regs] clock=$clock_name"
        return
    }
    # CDC converters contain both domains.  Intersect the hierarchy with the
    # registers of this clock so neither endpoint can be a CDC MaxDelay path.
    if {[string match "clock_converter_*" $id]} {
        set domain_set {}
        foreach register [all_registers -clock $clocks] {
            dict set domain_set $register 1
        }
        set same_domain {}
        foreach register $regs {
            if {[dict exists $domain_set $register]} {
                lappend same_domain $register
            }
        }
        set regs $same_domain
        if {[llength $regs] == 0} {
            puts "SCOPE_NO_SAME_DOMAIN_REGISTERS: $id"
            return
        }
    }
    set period [get_property PERIOD $clocks]
    # Group restricts the endpoint to the named setup clock group.  Async
    # recovery/removal groups are intentionally separate from this estimate.
    set paths [get_timing_paths -quiet -from $regs -to $regs -group $clock_name -delay_type max -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        puts "SCOPE_NO_INTERNAL_PATH: $id"
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
        set status internal_single_cycle_estimate
    }
    set values [list $id $label $clock_name [format %.6f [expr {1000.0/$period}]] [format %.3f $slack] $fmax $status [llength $regs] [get_property STARTPOINT_PIN $path] [get_property ENDPOINT_PIN $path] [format %.3f $requirement] $source_clock $destination_clock]
    set escaped {}
    foreach value $values {lappend escaped [csv_field $value]}
    puts $fd [join $escaped ,]
    flush $fd
    report_timing -of_objects $paths -file [file join $report_dir "${id}.rpt"]
    puts "SCOPE_RESULT: $id clock=[format %.3f [expr {1000.0/$period}]]MHz slack=${slack}ns estimate=${fmax}MHz status=$status"
}

set fd [open [file join $report_dir summary.csv] w]
puts $fd "id,label,clock,configured_mhz,internal_slack_ns,internal_estimate_mhz,status,sequential_cells,startpoint,endpoint,requirement_ns,source_clock,destination_clock"
set scopes {
    {cpu {PicoRV32 with AXI adapter} {soc/cpu/*} soc_clk_unbuf}
    {axi_fabric {Main AXI crossbar} {soc/fabric/interconnect_ip_inst/*} soc_clk_unbuf}
    {ram0 {RAM0 AXI plus BRAM} {soc/fabric/ram0/*} soc_clk_unbuf}
    {ram1 {RAM1 AXI plus BRAM} {soc/fabric/ram1/*} soc_clk_unbuf}
    {ram2 {RAM2 AXI plus BRAM} {soc/fabric/ram2/*} soc_clk_unbuf}
    {shake_axi {SLH SHAKE AXI accelerator including nested core} {soc/peripherals/shake_accel/*} soc_clk_unbuf}
    {thash {SLH F/H controller including SHAKE} {soc/peripherals/shake_accel/hash_unit/*} soc_clk_unbuf}
    {shake_core {SHAKE256 block engine including Keccak} {soc/peripherals/shake_accel/hash_unit/core/*} soc_clk_unbuf}
    {keccak {Keccak-f1600} {soc/peripherals/shake_accel/hash_unit/core/permutation/*} soc_clk_unbuf}
    {dma_iommu {Entire DMA and IOMMU subsystem} {soc/dma_iommu/*} soc_clk_unbuf}
    {dma_only {DMA engines control FIFOs and internal crossbar excluding IOMMU} {soc/dma_iommu/access_controller_inst/* soc/dma_iommu/cdma_inst/* soc/dma_iommu/completion_fifo_inst/* soc/dma_iommu/crossbar_inst/* soc/dma_iommu/descriptor_fifo_inst/* soc/dma_iommu/dma_rd_inst/* soc/dma_iommu/dma_wr_inst/* soc/dma_iommu/regs_inst/* soc/dma_iommu/scheduler_inst/*} soc_clk_unbuf}
    {iommu {DMA IOMMU TLB and permissions} {soc/dma_iommu/iommu_inst/*} soc_clk_unbuf}
    {cdma {Memory to memory CDMA engine} {soc/dma_iommu/cdma_inst/*} soc_clk_unbuf}
    {dma_read {DMA memory to stream engine} {soc/dma_iommu/dma_rd_inst/*} soc_clk_unbuf}
    {dma_write {DMA stream to memory engine} {soc/dma_iommu/dma_wr_inst/*} soc_clk_unbuf}
    {dma_router {DMA local DDR router} {soc/dma_memory_router/*} soc_clk_unbuf}
    {uart {UART} {soc/peripherals/uart/*} soc_clk_unbuf}
    {timer_gpio {Timer and GPIO} {soc/peripherals/timer_gpio/*} soc_clk_unbuf}
    {peripherals {AXI peripheral bridge and nested devices} {soc/peripherals/*} soc_clk_unbuf}
    {clock_converter_soc {DDR AXI clock converter SoC side} {ddr3_bridge/clock_converter_inst/*} soc_clk_unbuf}
    {clock_converter_ui {DDR AXI clock converter UI side} {ddr3_bridge/clock_converter_inst/*} clk_pll_i}
    {width_converter {DDR AXI width converter} {ddr3_bridge/width_converter_inst/*} clk_pll_i}
    {mig_ui {MIG UI synchronous paths only} {ddr3_bridge/mig_inst/*} clk_pll_i}
}
foreach scope $scopes {report_scope $fd {*}$scope}
close $fd
puts "IP_SCOPED_TIMING_PASS: [file join $report_dir summary.csv]"
