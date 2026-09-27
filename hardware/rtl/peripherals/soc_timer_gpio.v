`timescale 1ns/1ps
`default_nettype none

// 64-bit free-running timer and 32-bit GPIO output.
// 0x00 MTIME_LO, 0x04 MTIME_HI, 0x08 MTIMECMP_LO, 0x0c MTIMECMP_HI
// 0x10 CONTROL (bit0 timer IRQ enable, bit1 reset MTIME)
// 0x14 GPIO_OUT
// 0x18 STATUS (bit0 timer pending)
module soc_timer_gpio #(parameter integer CLOCK_HZ=100_000_000) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        irq,
    output reg  [31:0] gpio_out,
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_strb,
    output reg         wr_error,
    input  wire        rd_en,
    input  wire [7:0]  rd_addr,
    output reg  [31:0] rd_data,
    output reg         rd_error
);
    reg [63:0] mtime_q;
    reg [63:0] mtimecmp_q;
    reg        irq_enable_q;
    wire       timer_pending = (mtime_q >= mtimecmp_q);
    assign irq = irq_enable_q && timer_pending;

    always @* begin
        wr_error = (wr_strb != 4'hf);
        case (wr_addr)
            8'h00, 8'h04, 8'h08, 8'h0c, 8'h10, 8'h14: ;
            default: wr_error = 1'b1;
        endcase
    end

    always @* begin
        rd_error = 1'b0;
        case (rd_addr)
            8'h00: rd_data = mtime_q[31:0];
            8'h04: rd_data = mtime_q[63:32];
            8'h08: rd_data = mtimecmp_q[31:0];
            8'h0c: rd_data = mtimecmp_q[63:32];
            8'h10: rd_data = {31'd0, irq_enable_q};
            8'h14: rd_data = gpio_out;
            8'h18: rd_data = {31'd0, timer_pending};
            8'h1c: rd_data = CLOCK_HZ;
            default: begin rd_data = 32'd0; rd_error = 1'b1; end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime_q      <= 64'd0;
            mtimecmp_q   <= 64'hffff_ffff_ffff_ffff;
            irq_enable_q <= 1'b0;
            gpio_out     <= 32'd0;
        end else begin
            mtime_q <= mtime_q + 1'b1;
            if (wr_en && !wr_error) begin
                case (wr_addr)
                    8'h00: mtime_q[31:0] <= wr_data;
                    8'h04: mtime_q[63:32] <= wr_data;
                    8'h08: mtimecmp_q[31:0] <= wr_data;
                    8'h0c: mtimecmp_q[63:32] <= wr_data;
                    8'h10: begin
                        irq_enable_q <= wr_data[0];
                        if (wr_data[1]) mtime_q <= 64'd0;
                    end
                    8'h14: gpio_out <= wr_data;
                    default: ;
                endcase
            end
        end
    end
endmodule

`resetall
