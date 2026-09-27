`timescale 1ns/1ps
`default_nettype none

// VC707 board top.  The 200 MHz differential clock is converted to a
// conservative 100 MHz SoC clock.  reset_btn is active high.
module vc707_picorv32_slh_soc #(
    parameter MEM_INIT_FILE = "soc_boot.mem"
) (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       reset_btn,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [7:0] led
);
    wire clk200;
    wire clkfb_raw, clkfb;
    wire soc_clk_raw, soc_clk;
    wire locked;

    IBUFDS #(.DIFF_TERM("TRUE"), .IOSTANDARD("LVDS")) input_clock (
        .I(sysclk_p), .IB(sysclk_n), .O(clk200)
    );

    // VCO 1000 MHz; output 100 MHz.
    MMCME2_BASE #(
        .CLKIN1_PERIOD(5.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.0),
        .CLKOUT0_DIVIDE_F(10.0)
    ) clock_mmcm (
        .CLKIN1(clk200), .CLKFBIN(clkfb), .CLKFBOUT(clkfb_raw),
        .CLKOUT0(soc_clk_raw), .LOCKED(locked),
        .PWRDWN(1'b0), .RST(reset_btn)
    );
    BUFG feedback_buffer (.I(clkfb_raw), .O(clkfb));
    BUFG soc_clock_buffer (.I(soc_clk_raw), .O(soc_clk));

    // Synchronize both assertion and release into the SoC clock domain.  A
    // synchronous reset here avoids feeding asynchronous control into BRAM.
    (* ASYNC_REG = "TRUE" *) reg [3:0] reset_pipe_q = 4'b0000;
    always @(posedge soc_clk) begin
        if (!locked)
            reset_pipe_q <= 4'b0000;
        else
            reset_pipe_q <= {reset_pipe_q[2:0], 1'b1};
    end
    wire resetn = reset_pipe_q[3];

    wire [31:0] gpio_out;
    wire trap, bus_error, shake_irq, uart_irq, timer_irq, dma_irq;
    picorv32_slh_soc #(
        .CLOCK_HZ(100_000_000),
        .BAUD_RATE(115_200),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) soc (
        .clk(soc_clk), .resetn(resetn),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .gpio_out(gpio_out),
        .trap(trap), .bus_error(bus_error), .shake_irq(shake_irq),
        .uart_irq(uart_irq), .timer_irq(timer_irq), .dma_irq(dma_irq)
    );

    // LED[3:0] are firmware-controlled.  The upper LEDs expose essential
    // hardware status even if firmware or UART are not yet working.
    assign led = {dma_irq, shake_irq, bus_error, trap, gpio_out[3:0]};
endmodule

`resetall
