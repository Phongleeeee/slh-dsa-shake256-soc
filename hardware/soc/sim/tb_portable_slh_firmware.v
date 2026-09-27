`timescale 1ns/1ps
`default_nettype none
// Run the actual RV32 C firmware through BSS initialization and the
// bidirectional internal-RAM DMA test. Full signature jobs are issued over
// UART on the board; this regression deliberately reports only startup/DMA.
module tb_portable_slh_firmware #(
    parameter MEM_INIT_FILE = "../../firmware/slh_dsa_portable.mem",
    parameter STOP_AFTER_DMA=1
);
    reg clk = 0;
    reg resetn = 0;
    wire uart_tx, trap, bus_error;
    wire [31:0] gpio;
    always #2.5 clk = ~clk;
    portable_slh_soc_core #(
        .CLOCK_HZ(10_000_000), .BAUD_RATE(1_000_000),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) dut (
        .clk(clk), .resetn(resetn), .uart_rx(1'b1), .uart_tx(uart_tx),
        .gpio_out(gpio), .trap(trap), .bus_error(bus_error),
        .ext_m_axi_awready(1'b0), .ext_m_axi_wready(1'b0),
        .ext_m_axi_bid(5'd0), .ext_m_axi_bresp(2'd0), .ext_m_axi_bvalid(1'b0),
        .ext_m_axi_arready(1'b0), .ext_m_axi_rid(5'd0),
        .ext_m_axi_rdata(32'd0), .ext_m_axi_rresp(2'd0),
        .ext_m_axi_rlast(1'b0), .ext_m_axi_rvalid(1'b0)
    );
    reg [7:0] received;
    integer bit_index;
    string line = "";
    initial begin
        repeat (20) @(posedge clk);
        resetn <= 1;
    end
    initial begin
        wait (resetn);
        forever begin
            @(negedge uart_tx);
            repeat (15) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                received[bit_index] = uart_tx;
                repeat (10) @(posedge clk);
            end
            if (!uart_tx) $fatal(1, "UART framing error");
            if (received == 10) begin
                $display("FIRMWARE UART: %s", line);
                if (STOP_AFTER_DMA && line == "DMA RAM1 -> RAM2 -> RAM1 PASS") begin
                    $display("PORTABLE C FIRMWARE STARTUP + DMA ROUNDTRIP TEST PASSED");
                    $finish;
                end
                if (!STOP_AFTER_DMA && line == "DMA F/H STREAM KAT PASS") begin
                    $display("PORTABLE C FIRMWARE DMA STREAM INTEGRATION TEST PASSED"); $finish;
                end
                line = "";
            end else if (received != 13) line = {line, received};
        end
    end
    always @(posedge clk) if (resetn) begin
        if (trap) $fatal(1, "RV32 C firmware trapped");
        if (bus_error) $fatal(1, "RV32 C firmware AXI error");
        if (gpio[3:0] == 2) $fatal(1, "RV32 C firmware failed");
    end
    initial begin
        #30_000_000;
        $fatal(1, "Timeout in full C firmware startup/DMA test");
    end
endmodule
`resetall
