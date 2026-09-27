module tb_portable_service_boot #(parameter MEM_INIT_FILE="../../firmware/slh_dsa_portable.mem");
    tb_portable_slh_firmware #(.MEM_INIT_FILE(MEM_INIT_FILE),.STOP_AFTER_DMA(0)) firmware();
endmodule
