`timescale 1ns/1ps
// F/H primitive for FIPS 205 SLH-DSA-SHAKE-256{f,s}:
//   SHAKE256(PK.seed || ADRS || input, 32 bytes)
// Byte zero of each vector is in bits [7:0]. Input is one 32-byte block for
// F or two 32-byte blocks for H. The complete padded SHAKE rate block is
// registered at request acceptance; this removes a high-fanout mode signal
// from the sponge datapath and improves Fmax.
module spx_thash_shake256_simple_256 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          zeroize,
    input  wire          start,
    input  wire          two_blocks,
    input  wire [255:0]  pub_seed,
    input  wire [255:0]  addr,
    input  wire [511:0]  in_data,
    output wire          ready,
    output reg           done,
    output reg           error,
    output reg  [255:0]  digest
);
    localparam IDLE = 3'd0, INIT = 3'd1, ABSORB = 3'd2,
               WAIT_HASH = 3'd3, CLEANUP = 3'd4;
`ifdef FMAX_FANOUT
    // IDLE directly qualifies loading all 1088 padded-block bits.  Replicate
    // the FSM decode close to those registers instead of routing one control
    // net across the whole Keccak datapath.
    (* max_fanout = 16 *) reg [2:0] state;
`else
    reg [2:0] state;
`endif
    reg [1087:0] padded_block_q;
    reg pending_error_q;
    wire [1087:0] core_dout;
    wire core_ready, core_done, core_output_valid, core_error;
    wire core_zeroize = zeroize || (state == CLEANUP);

    shake256_block_engine core (
        .clk(clk), .rst_n(rst_n), .zeroize(core_zeroize),
        .init(state == INIT), .absorb(state == ABSORB), .squeeze(1'b0),
        .pre_padded(1'b1), .din(padded_block_q), .valid_bytes(8'd136),
        .last(1'b1), .dout(core_dout), .ready(core_ready),
        .done(core_done), .output_valid(core_output_valid),
        .error(core_error)
    );

    assign ready = (state == IDLE) && !zeroize;

    // The SoC supplies a clock-synchronous local reset.  A synchronous reset
    // avoids routing one asynchronous CLR net to all 1088 padded-block bits.
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            error <= 1'b0;
            digest <= 256'd0;
            padded_block_q <= 1088'd0;
            pending_error_q <= 1'b0;
        end else if (zeroize) begin
            state <= IDLE;
            done <= 1'b0;
            error <= 1'b0;
            digest <= 256'd0;
            padded_block_q <= 1088'd0;
            pending_error_q <= 1'b0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    // SHAKE domain byte 0x1f and final rate bit 0x80.
                    if (two_blocks)
                        padded_block_q <= {8'h80, 48'd0, 8'h1f,
                                           in_data, addr, pub_seed};
                    else
                        padded_block_q <= {8'h80, 304'd0, 8'h1f,
                                           in_data[255:0], addr, pub_seed};
                    state <= INIT;
                end
                INIT: state <= ABSORB;
                ABSORB: if (core_ready) state <= WAIT_HASH;
                WAIT_HASH: if (core_done) begin
                    pending_error_q <= core_error | ~core_output_valid;
                    if (core_output_valid)
                        digest <= core_dout[255:0];
                    // Remove the padded operand immediately. CLEANUP then
                    // clears the sponge and both Keccak pipeline stages
                    // before completion becomes visible to the caller.
                    padded_block_q <= 1088'd0;
                    state <= CLEANUP;
                end
                CLEANUP: begin
                    error <= pending_error_q;
                    done <= 1'b1;
                    state <= IDLE;
                    pending_error_q <= 1'b0;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
