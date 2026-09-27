`timescale 1ns/1ps
`default_nettype none

// Board adapter only. The core uses one synchronous clock and internal RAM.
module vc707_portable_wrapper #(
    parameter integer CLOCK_HZ = 296_296_296,
    parameter real CLKOUT_DIVIDE = 3.375,
    parameter MEM_INIT_FILE = "slh_dsa_portable.mem"
) (
    input wire sysclk_p,
    input wire sysclk_n,
    input wire reset_btn,
    input wire uart_rx,
    output wire uart_tx,
    output wire [7:0] led
);
    wire clk200, clkfb_raw, clkfb, soc_clk_raw, soc_clk, locked;
    IBUFDS #(.DIFF_TERM("TRUE"), .IOSTANDARD("LVDS")) input_clock (
        .I(sysclk_p), .IB(sysclk_n), .O(clk200)
    );
    // 1 GHz VCO; divide 3.375 -> 296.296296 MHz (release build).
    MMCME2_BASE #(
        .CLKIN1_PERIOD(5.0), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.0), .CLKOUT0_DIVIDE_F(CLKOUT_DIVIDE),
        .BANDWIDTH("OPTIMIZED"), .STARTUP_WAIT("FALSE")
    ) clock_mmcm (
        .CLKIN1(clk200), .CLKFBIN(clkfb), .CLKFBOUT(clkfb_raw),
        .CLKOUT0(soc_clk_raw), .LOCKED(locked),
        .RST(reset_btn), .PWRDWN(1'b0)
    );
    BUFG feedback_buffer (.I(clkfb_raw), .O(clkfb));
    BUFG soc_clock_buffer (.I(soc_clk_raw), .O(soc_clk));
    wire reset_async = reset_btn | ~locked;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [2:0] reset_pipe = 3'b111;
    always @(posedge soc_clk or posedge reset_async) begin
        if (reset_async) reset_pipe <= 3'b111;
        else reset_pipe <= {reset_pipe[1:0], 1'b0};
    end
    wire resetn = ~reset_pipe[2];
    wire [31:0] gpio;
    wire trap, bus_error, shake_irq, uart_irq, timer_irq, dma_irq;
    portable_slh_soc_core #(
        .CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(115_200),
        .MEM_INIT_FILE(MEM_INIT_FILE), .ENABLE_EXT_MEMORY(0)
    ) soc (
        .clk(soc_clk), .resetn(resetn),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .gpio_out(gpio),
        .trap(trap), .bus_error(bus_error), .shake_irq(shake_irq),
        .uart_irq(uart_irq), .timer_irq(timer_irq), .dma_irq(dma_irq),
        .ext_m_axi_awready(1'b0), .ext_m_axi_wready(1'b0),
        .ext_m_axi_bid(5'd0), .ext_m_axi_bresp(2'd0), .ext_m_axi_bvalid(1'b0),
        .ext_m_axi_arready(1'b0), .ext_m_axi_rid(5'd0),
        .ext_m_axi_rdata(32'd0), .ext_m_axi_rresp(2'd0),
        .ext_m_axi_rlast(1'b0), .ext_m_axi_rvalid(1'b0)
    );
    assign led = {dma_irq, shake_irq, bus_error, trap, gpio[3:0]};
endmodule
`resetall
