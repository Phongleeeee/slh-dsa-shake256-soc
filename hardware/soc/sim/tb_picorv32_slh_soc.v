`timescale 1ns/1ps
`default_nettype none

// End-to-end regression: PicoRV32 fetches the boot image from AXI RAM,
// accesses UART/GPIO and runs the SHAKE F known-answer test through AXI.
module tb_picorv32_slh_soc;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg uart_rx = 1'b1;

    wire uart_tx;
    wire [31:0] gpio_out;
    wire trap;
    wire bus_error;
    wire shake_irq;
    wire uart_irq;
    wire timer_irq;
    wire dma_irq;

    always #5 clk = ~clk;
    integer boot_run;

    portable_slh_soc_core #(
        .CLOCK_HZ(10_000_000),
        .BAUD_RATE(1_000_000),
        .MEM_INIT_FILE("../../firmware/soc_boot.mem")
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio_out(gpio_out),
        .trap(trap),
        .bus_error(bus_error),
        .shake_irq(shake_irq),
        .uart_irq(uart_irq),
        .timer_irq(timer_irq),
        .dma_irq(dma_irq),
        .ext_m_axi_awready(1'b0), .ext_m_axi_wready(1'b0),
        .ext_m_axi_bid(5'd0), .ext_m_axi_bresp(2'd0), .ext_m_axi_bvalid(1'b0),
        .ext_m_axi_arready(1'b0), .ext_m_axi_rid(5'd0),
        .ext_m_axi_rdata(32'd0), .ext_m_axi_rresp(2'd0),
        .ext_m_axi_rlast(1'b0), .ext_m_axi_rvalid(1'b0)
    );

    initial begin
        repeat (20) @(posedge clk);
        resetn <= 1'b1;
        // Interrupt an actual AXI DMA write between clock edges, then boot
        // twice. This checks reset cancellation and retained boot RAM data.
        fork : reset_probe
            begin
                wait (dut.dma_axi_wvalid && dut.dma_axi_wready);
                @(posedge clk);
                @(negedge clk);
            end
            begin
                #2_000_000;
                $fatal(1, "No DMA write observed for mid-transfer reset test");
            end
        join_any
        disable reset_probe;
        resetn <= 1'b0;
        $display("PORTABLE SOC RESET ASSERTED DURING DMA WRITE");
        repeat (20) @(posedge clk);
      for (boot_run = 0; boot_run < 2; boot_run = boot_run + 1) begin
        resetn <= 1'b1;
        // Allow the registered reset distribution to clear old GPIO/status.
        repeat (3) @(posedge clk);

        fork : outcome
            begin
                wait (gpio_out[3:0] == 4'h1);
                if (!dut.dma_iommu.perf_valid || dut.dma_iommu.perf_seq !== 2 ||
                    dut.dma_iommu.perf_src_bytes !== 16 ||
                    dut.dma_iommu.perf_dst_bytes !== 16 ||
                    dut.dma_iommu.perf_axi_r_bytes !== 16 ||
                    dut.dma_iommu.perf_axi_w_bytes !== 16)
                    $fatal(1, "DMA snapshot omitted final beat or roundtrip command");
                $display("PICORV32 AXI SOC BOOT %0d DMA + SHAKE KAT TEST PASSED", boot_run + 1);
            end
            begin
                wait (gpio_out[3:0] == 4'h2);
                $fatal(1, "Firmware reported SHAKE KAT failure");
            end
            begin
                wait (trap);
                $fatal(1, "PicoRV32 trapped");
            end
            begin
                wait (bus_error);
                $fatal(1, "AXI bus error detected");
            end
            begin
                #2_000_000;
                $fatal(1, "Timeout waiting for firmware result; gpio=%08x", gpio_out);
            end
        join_any
        disable outcome;
        if (boot_run == 0) begin
            resetn <= 1'b0;
            repeat (20) @(posedge clk);
        end
      end
      $display("PORTABLE SOC RESET/REBOOT TEST PASSED");
      $finish;
    end
endmodule

`resetall
