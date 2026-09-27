# Run after opening the portable project; safe to source repeatedly.
set config_here [file dirname [file normalize [info script]]]
set config_soc [file normalize [file join $config_here ..]]
foreach tb {tb_portable_slh_firmware.v tb_portable_service_boot.v tb_portable_service_uart.v tb_iommu_secure.v tb_slh_dma_stream.v tb_slh_dma_stream_review.v tb_dma_scheduler_review.sv tb_iommu_range_review.sv tb_iommu_maintenance_review.sv tb_picorv32_slh_soc.v tb_axi_slh_peripherals.v tb_dma_axi_mem_router.v} {
    set path [file join $config_soc sim $tb]
    if {[llength [get_files -quiet $path]] == 0} {add_files -fileset sim_1 -norecurse $path}
}
set review_vectors [file join $config_soc output_portable sim_regression review_hash_vectors.mem]
if {[file exists $review_vectors] && [llength [get_files -quiet $review_vectors]] == 0} {
    add_files -fileset sim_1 -norecurse $review_vectors
    set_property file_type {Memory Initialization Files} [get_files $review_vectors]
}
set_property top tb_portable_service_boot [get_filesets sim_1]
set_property generic "MEM_INIT_FILE=[file join $config_soc firmware slh_dsa_portable.mem]" [get_filesets sim_1]
set_property verilog_define {FMAX_FANOUT} [get_filesets sim_1]
set_property xsim.simulate.runtime {600ms} [get_filesets sim_1]
update_compile_order -fileset sim_1
