`timescale 1ns/1ps
`default_nettype none

// Small, synthesizable UART for the PicoRV32 SoC.  The MMIO wrapper presents
// one-cycle read/write pulses and this block owns all stateful UART registers.
// Register offsets:
//   0x00 DATA       W: transmit byte, R: receive byte (read clears RX_VALID)
//   0x04 STATUS     bit0 TX_READY, bit1 TX_BUSY, bit2 RX_VALID,
//                   bit3 RX_OVERRUN, bit4 RX_FRAME_ERROR
//   0x08 BAUD_DIV   clocks per bit (minimum 2)
//   0x0c IRQ_ENABLE bit0 RX_VALID, bit1 RX_ERROR
//   0x10 IRQ_STATUS same layout; write-one-to-clear error flags
module soc_uart #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire        irq,

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
    localparam integer DEFAULT_DIV = CLOCK_HZ / BAUD_RATE;

    reg [31:0] baud_div_q;
    reg [1:0]  irq_enable_q;

    reg [9:0]  tx_shift_q;
    reg [3:0]  tx_bits_q;
    reg [31:0] tx_count_q;
    wire       tx_busy = (tx_bits_q != 0);
    wire       tx_ready = !tx_busy;

    reg [1:0]  rx_sync_q;
    reg [1:0]  rx_state_q;
    reg [31:0] rx_count_q;
    reg [2:0]  rx_bit_q;
    reg [7:0]  rx_shift_q;
    reg [7:0]  rx_data_q;
    reg        rx_valid_q;
    reg        rx_overrun_q;
    reg        rx_frame_error_q;

    localparam [1:0] RX_IDLE  = 2'd0,
                     RX_START = 2'd1,
                     RX_DATA  = 2'd2,
                     RX_STOP  = 2'd3;

    assign uart_tx = tx_busy ? tx_shift_q[0] : 1'b1;
    assign irq = (irq_enable_q[0] && rx_valid_q) ||
                 (irq_enable_q[1] && (rx_overrun_q || rx_frame_error_q));

    always @* begin
        wr_error = 1'b0;
        case (wr_addr)
            8'h00: wr_error = !wr_strb[0] || tx_busy;
            8'h08: wr_error = (wr_strb != 4'hf) || (wr_data < 32'd2);
            8'h0c: wr_error = !wr_strb[0];
            8'h10: wr_error = !wr_strb[0];
            default: wr_error = 1'b1;
        endcase
    end

    always @* begin
        rd_error = 1'b0;
        case (rd_addr)
            8'h00: rd_data = {24'd0, rx_data_q};
            8'h04: rd_data = {27'd0, rx_frame_error_q, rx_overrun_q,
                               rx_valid_q, tx_busy, tx_ready};
            8'h08: rd_data = baud_div_q;
            8'h0c: rd_data = {30'd0, irq_enable_q};
            8'h10: rd_data = {29'd0, rx_frame_error_q,
                               rx_overrun_q, rx_valid_q};
            default: begin
                rd_data = 32'd0;
                rd_error = 1'b1;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div_q       <= (DEFAULT_DIV < 2) ? 32'd2 : DEFAULT_DIV;
            irq_enable_q     <= 2'b00;
            tx_shift_q       <= 10'h3ff;
            tx_bits_q        <= 4'd0;
            tx_count_q       <= 32'd0;
            rx_sync_q        <= 2'b11;
            rx_state_q       <= RX_IDLE;
            rx_count_q       <= 32'd0;
            rx_bit_q         <= 3'd0;
            rx_shift_q       <= 8'd0;
            rx_data_q        <= 8'd0;
            rx_valid_q       <= 1'b0;
            rx_overrun_q     <= 1'b0;
            rx_frame_error_q <= 1'b0;
        end else begin
            rx_sync_q <= {rx_sync_q[0], uart_rx};

            if (wr_en && !wr_error) begin
                case (wr_addr)
                    8'h00: begin
                        tx_shift_q <= {1'b1, wr_data[7:0], 1'b0};
                        tx_bits_q  <= 4'd10;
                        tx_count_q <= baud_div_q - 1'b1;
                    end
                    8'h08: baud_div_q <= wr_data;
                    8'h0c: irq_enable_q <= wr_data[1:0];
                    8'h10: begin
                        if (wr_data[1]) rx_overrun_q <= 1'b0;
                        if (wr_data[2]) rx_frame_error_q <= 1'b0;
                    end
                    default: ;
                endcase
            end

            if (rd_en && rd_addr == 8'h00)
                rx_valid_q <= 1'b0;

            if (tx_busy) begin
                if (tx_count_q == 0) begin
                    tx_shift_q <= {1'b1, tx_shift_q[9:1]};
                    tx_bits_q  <= tx_bits_q - 1'b1;
                    tx_count_q <= baud_div_q - 1'b1;
                end else begin
                    tx_count_q <= tx_count_q - 1'b1;
                end
            end

            case (rx_state_q)
                RX_IDLE: begin
                    if (!rx_sync_q[1]) begin
                        rx_count_q <= baud_div_q >> 1;
                        rx_state_q <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_count_q == 0) begin
                        if (!rx_sync_q[1]) begin
                            rx_bit_q   <= 3'd0;
                            rx_count_q <= baud_div_q - 1'b1;
                            rx_state_q <= RX_DATA;
                        end else begin
                            rx_state_q <= RX_IDLE;
                        end
                    end else begin
                        rx_count_q <= rx_count_q - 1'b1;
                    end
                end
                RX_DATA: begin
                    if (rx_count_q == 0) begin
                        rx_shift_q[rx_bit_q] <= rx_sync_q[1];
                        rx_count_q <= baud_div_q - 1'b1;
                        if (rx_bit_q == 3'd7)
                            rx_state_q <= RX_STOP;
                        else
                            rx_bit_q <= rx_bit_q + 1'b1;
                    end else begin
                        rx_count_q <= rx_count_q - 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_count_q == 0) begin
                        if (rx_sync_q[1]) begin
                            if (rx_valid_q)
                                rx_overrun_q <= 1'b1;
                            else begin
                                rx_data_q  <= rx_shift_q;
                                rx_valid_q <= 1'b1;
                            end
                        end else begin
                            rx_frame_error_q <= 1'b1;
                        end
                        rx_state_q <= RX_IDLE;
                    end else begin
                        rx_count_q <= rx_count_q - 1'b1;
                    end
                end
                default: rx_state_q <= RX_IDLE;
            endcase
        end
    end
endmodule

`resetall
