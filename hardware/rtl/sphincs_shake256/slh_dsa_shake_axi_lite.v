`timescale 1ns/1ps
// Production-oriented AXI4-Lite accelerator for F and H in
// FIPS 205 SLH-DSA-SHAKE-256{f,s}:
//   SHAKE256(PK.seed || ADRS || input, 32 bytes)
//
// Register map (32-bit little-endian words):
//   0x00 CONTROL      bit0 START, bit1 TWO_BLOCKS, bit2 CLEAR_STATUS,
//                     bit3 ZEROIZE/ABORT
//   0x04 STATUS       bit0 READY, bit1 DONE, bit2 BUSY, bit3 ERROR,
//                     bit4 CONFIG_F_VALID, bit5 CONFIG_H_VALID,
//                     bit6 ZEROIZING
//   0x08..0x24        PK.seed words 0..7
//   0x28..0x44        ADRS words 0..7
//   0x48..0x84        input words 0..15 (write-only)
//   0x88..0xA4        digest words 0..7 (read-only)
//   0xA8 ID           0x534C4802 ("SLH", interface version 2)
//   0xAC IRQ_ENABLE   bit0 DONE, bit1 ERROR
//   0xB0 IRQ_STATUS   bit0 DONE, bit1 ERROR; write-one-to-clear
//   0xB4 CAPABILITIES version 1, F/H, zeroize, IRQ, strict errors, pipeline
module slh_dsa_shake_axi_lite #(
    parameter integer C_S_AXI_ADDR_WIDTH = 8,
    parameter integer C_S_AXI_DATA_WIDTH = 32
) (
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,
    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready,
    output wire                              irq
);
    localparam [1:0] AXI_OKAY = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;

    reg [255:0] pub_seed_q;
    reg [255:0] addr_q;
    reg [511:0] input_q;
    reg [255:0] digest_q;
    reg [31:0]  seed_byte_valid_q;
    reg [31:0]  addr_byte_valid_q;
    reg [63:0]  input_byte_valid_q;
    reg          two_blocks_q;
    reg          start_pulse;
    reg          zeroize_pulse;
    reg          done_sticky;
    reg          error_sticky;
    reg [1:0]    irq_enable_q;

`ifdef FMAX_FANOUT
    (* max_fanout = 16 *) reg hash_resetn_q = 1'b0;
`else
    reg hash_resetn_q = 1'b0;
`endif

    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_hold_q;
    reg                           aw_hold_valid_q;
    reg [C_S_AXI_DATA_WIDTH-1:0] wdata_hold_q;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_hold_q;
    reg                           w_hold_valid_q;

    wire hash_ready, hash_done, hash_error;
    wire [255:0] hash_digest;
    wire config_f_valid = &seed_byte_valid_q && &addr_byte_valid_q &&
                          &input_byte_valid_q[31:0];
    wire config_h_valid = config_f_valid && &input_byte_valid_q[63:32];

    assign s_axi_awready = !aw_hold_valid_q && !s_axi_bvalid &&
                           !zeroize_pulse;
    assign s_axi_wready = !w_hold_valid_q && !s_axi_bvalid &&
                          !zeroize_pulse;
    assign s_axi_arready = !s_axi_rvalid && !zeroize_pulse;

    wire aw_accept = s_axi_awvalid && s_axi_awready;
    wire w_accept = s_axi_wvalid && s_axi_wready;
    // Commit only from the registered AW/W pair. The extra cycle removes
    // address/data selection muxes from the register-bank critical path.
    wire write_fire = !s_axi_bvalid && aw_hold_valid_q && w_hold_valid_q;
    wire [C_S_AXI_ADDR_WIDTH-1:0] write_addr = awaddr_hold_q;
    wire [C_S_AXI_DATA_WIDTH-1:0] write_data = wdata_hold_q;
    wire [(C_S_AXI_DATA_WIDTH/8)-1:0] write_strb = wstrb_hold_q;
    wire write_aligned = (write_addr[1:0] == 2'b00);
    wire zeroize_command = write_fire && write_aligned &&
                           write_addr == 8'h00 && write_strb[0] &&
                           write_data[3];

    function [31:0] merge_wstrb;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0] strb;
        begin
            merge_wstrb = old_word;
            if (strb[0]) merge_wstrb[7:0] = new_word[7:0];
            if (strb[1]) merge_wstrb[15:8] = new_word[15:8];
            if (strb[2]) merge_wstrb[23:16] = new_word[23:16];
            if (strb[3]) merge_wstrb[31:24] = new_word[31:24];
        end
    endfunction

    spx_thash_shake256_simple_256 hash_unit (
        .clk(s_axi_aclk), .rst_n(hash_resetn_q),
        .zeroize(zeroize_pulse), .start(start_pulse),
        .two_blocks(two_blocks_q), .pub_seed(pub_seed_q),
        .addr(addr_q), .in_data(input_q), .ready(hash_ready),
        .done(hash_done), .error(hash_error), .digest(hash_digest)
    );

    assign irq = (done_sticky && irq_enable_q[0]) ||
                 (error_sticky && irq_enable_q[1]);

    initial begin
        if (C_S_AXI_DATA_WIDTH != 32 || C_S_AXI_ADDR_WIDTH < 8)
            $error("slh_dsa_shake_axi_lite requires 32-bit data and >=8-bit address");
    end

    // Local reset stage confines the high-fanout reset tree to the hash unit.
    // The parent reset is already asserted until the SoC clock is stable.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            hash_resetn_q <= 1'b0;
        else
            hash_resetn_q <= 1'b1;
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_bresp <= AXI_OKAY;
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
            s_axi_rresp <= AXI_OKAY;
            s_axi_rvalid <= 1'b0;
            awaddr_hold_q <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            aw_hold_valid_q <= 1'b0;
            wdata_hold_q <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_hold_q <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            w_hold_valid_q <= 1'b0;
            pub_seed_q <= 256'd0;
            addr_q <= 256'd0;
            input_q <= 512'd0;
            digest_q <= 256'd0;
            seed_byte_valid_q <= 32'd0;
            addr_byte_valid_q <= 32'd0;
            input_byte_valid_q <= 64'd0;
            two_blocks_q <= 1'b0;
            start_pulse <= 1'b0;
            zeroize_pulse <= 1'b0;
            done_sticky <= 1'b0;
            error_sticky <= 1'b0;
            irq_enable_q <= 2'b00;
        end else begin
            start_pulse <= 1'b0;
            zeroize_pulse <= 1'b0;

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (aw_accept) begin
                awaddr_hold_q <= s_axi_awaddr;
                aw_hold_valid_q <= 1'b1;
            end
            if (w_accept) begin
                wdata_hold_q <= s_axi_wdata;
                wstrb_hold_q <= s_axi_wstrb;
                w_hold_valid_q <= 1'b1;
            end

            // Complete writes after independently accepting AW and W.
            if (write_fire) begin
                aw_hold_valid_q <= 1'b0;
                w_hold_valid_q <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= AXI_OKAY;

                if (!write_aligned) begin
                    s_axi_bresp <= AXI_SLVERR;
                    error_sticky <= 1'b1;
                end else if (write_addr == 8'h00) begin
                    if (!write_strb[0]) begin
                        s_axi_bresp <= AXI_SLVERR;
                        error_sticky <= 1'b1;
                    end else if (write_data[3]) begin
                        // Synchronous secure erase and operation abort.
                        pub_seed_q <= 256'd0;
                        addr_q <= 256'd0;
                        input_q <= 512'd0;
                        digest_q <= 256'd0;
                        seed_byte_valid_q <= 32'd0;
                        addr_byte_valid_q <= 32'd0;
                        input_byte_valid_q <= 64'd0;
                        two_blocks_q <= 1'b0;
                        done_sticky <= 1'b0;
                        error_sticky <= 1'b0;
                        irq_enable_q <= 2'b00;
                        zeroize_pulse <= 1'b1;
                    end else begin
                        if (write_data[2]) begin
                            done_sticky <= 1'b0;
                            error_sticky <= 1'b0;
                        end
                        if (write_data[0]) begin
                            if (hash_ready &&
                                (write_data[1] ? config_h_valid :
                                                 config_f_valid)) begin
                                two_blocks_q <= write_data[1];
                                start_pulse <= 1'b1;
                                done_sticky <= 1'b0;
                                error_sticky <= 1'b0;
                            end else begin
                                s_axi_bresp <= AXI_SLVERR;
                                error_sticky <= 1'b1;
                            end
                        end
                    end
                end else begin
                    case (write_addr[7:0])
                        8'h08: begin
                            pub_seed_q[31:0] <= merge_wstrb(pub_seed_q[31:0], write_data, write_strb);
                            seed_byte_valid_q[3:0] <= seed_byte_valid_q[3:0] | write_strb;
                        end
                        8'h0c: begin
                            pub_seed_q[63:32] <= merge_wstrb(pub_seed_q[63:32], write_data, write_strb);
                            seed_byte_valid_q[7:4] <= seed_byte_valid_q[7:4] | write_strb;
                        end
                        8'h10: begin
                            pub_seed_q[95:64] <= merge_wstrb(pub_seed_q[95:64], write_data, write_strb);
                            seed_byte_valid_q[11:8] <= seed_byte_valid_q[11:8] | write_strb;
                        end
                        8'h14: begin
                            pub_seed_q[127:96] <= merge_wstrb(pub_seed_q[127:96], write_data, write_strb);
                            seed_byte_valid_q[15:12] <= seed_byte_valid_q[15:12] | write_strb;
                        end
                        8'h18: begin
                            pub_seed_q[159:128] <= merge_wstrb(pub_seed_q[159:128], write_data, write_strb);
                            seed_byte_valid_q[19:16] <= seed_byte_valid_q[19:16] | write_strb;
                        end
                        8'h1c: begin
                            pub_seed_q[191:160] <= merge_wstrb(pub_seed_q[191:160], write_data, write_strb);
                            seed_byte_valid_q[23:20] <= seed_byte_valid_q[23:20] | write_strb;
                        end
                        8'h20: begin
                            pub_seed_q[223:192] <= merge_wstrb(pub_seed_q[223:192], write_data, write_strb);
                            seed_byte_valid_q[27:24] <= seed_byte_valid_q[27:24] | write_strb;
                        end
                        8'h24: begin
                            pub_seed_q[255:224] <= merge_wstrb(pub_seed_q[255:224], write_data, write_strb);
                            seed_byte_valid_q[31:28] <= seed_byte_valid_q[31:28] | write_strb;
                        end
                        8'h28: begin
                            addr_q[31:0] <= merge_wstrb(addr_q[31:0], write_data, write_strb);
                            addr_byte_valid_q[3:0] <= addr_byte_valid_q[3:0] | write_strb;
                        end
                        8'h2c: begin
                            addr_q[63:32] <= merge_wstrb(addr_q[63:32], write_data, write_strb);
                            addr_byte_valid_q[7:4] <= addr_byte_valid_q[7:4] | write_strb;
                        end
                        8'h30: begin
                            addr_q[95:64] <= merge_wstrb(addr_q[95:64], write_data, write_strb);
                            addr_byte_valid_q[11:8] <= addr_byte_valid_q[11:8] | write_strb;
                        end
                        8'h34: begin
                            addr_q[127:96] <= merge_wstrb(addr_q[127:96], write_data, write_strb);
                            addr_byte_valid_q[15:12] <= addr_byte_valid_q[15:12] | write_strb;
                        end
                        8'h38: begin
                            addr_q[159:128] <= merge_wstrb(addr_q[159:128], write_data, write_strb);
                            addr_byte_valid_q[19:16] <= addr_byte_valid_q[19:16] | write_strb;
                        end
                        8'h3c: begin
                            addr_q[191:160] <= merge_wstrb(addr_q[191:160], write_data, write_strb);
                            addr_byte_valid_q[23:20] <= addr_byte_valid_q[23:20] | write_strb;
                        end
                        8'h40: begin
                            addr_q[223:192] <= merge_wstrb(addr_q[223:192], write_data, write_strb);
                            addr_byte_valid_q[27:24] <= addr_byte_valid_q[27:24] | write_strb;
                        end
                        8'h44: begin
                            addr_q[255:224] <= merge_wstrb(addr_q[255:224], write_data, write_strb);
                            addr_byte_valid_q[31:28] <= addr_byte_valid_q[31:28] | write_strb;
                        end
                        8'h48: begin input_q[31:0] <= merge_wstrb(input_q[31:0], write_data, write_strb); input_byte_valid_q[3:0] <= input_byte_valid_q[3:0] | write_strb; end
                        8'h4c: begin input_q[63:32] <= merge_wstrb(input_q[63:32], write_data, write_strb); input_byte_valid_q[7:4] <= input_byte_valid_q[7:4] | write_strb; end
                        8'h50: begin input_q[95:64] <= merge_wstrb(input_q[95:64], write_data, write_strb); input_byte_valid_q[11:8] <= input_byte_valid_q[11:8] | write_strb; end
                        8'h54: begin input_q[127:96] <= merge_wstrb(input_q[127:96], write_data, write_strb); input_byte_valid_q[15:12] <= input_byte_valid_q[15:12] | write_strb; end
                        8'h58: begin input_q[159:128] <= merge_wstrb(input_q[159:128], write_data, write_strb); input_byte_valid_q[19:16] <= input_byte_valid_q[19:16] | write_strb; end
                        8'h5c: begin input_q[191:160] <= merge_wstrb(input_q[191:160], write_data, write_strb); input_byte_valid_q[23:20] <= input_byte_valid_q[23:20] | write_strb; end
                        8'h60: begin input_q[223:192] <= merge_wstrb(input_q[223:192], write_data, write_strb); input_byte_valid_q[27:24] <= input_byte_valid_q[27:24] | write_strb; end
                        8'h64: begin input_q[255:224] <= merge_wstrb(input_q[255:224], write_data, write_strb); input_byte_valid_q[31:28] <= input_byte_valid_q[31:28] | write_strb; end
                        8'h68: begin input_q[287:256] <= merge_wstrb(input_q[287:256], write_data, write_strb); input_byte_valid_q[35:32] <= input_byte_valid_q[35:32] | write_strb; end
                        8'h6c: begin input_q[319:288] <= merge_wstrb(input_q[319:288], write_data, write_strb); input_byte_valid_q[39:36] <= input_byte_valid_q[39:36] | write_strb; end
                        8'h70: begin input_q[351:320] <= merge_wstrb(input_q[351:320], write_data, write_strb); input_byte_valid_q[43:40] <= input_byte_valid_q[43:40] | write_strb; end
                        8'h74: begin input_q[383:352] <= merge_wstrb(input_q[383:352], write_data, write_strb); input_byte_valid_q[47:44] <= input_byte_valid_q[47:44] | write_strb; end
                        8'h78: begin input_q[415:384] <= merge_wstrb(input_q[415:384], write_data, write_strb); input_byte_valid_q[51:48] <= input_byte_valid_q[51:48] | write_strb; end
                        8'h7c: begin input_q[447:416] <= merge_wstrb(input_q[447:416], write_data, write_strb); input_byte_valid_q[55:52] <= input_byte_valid_q[55:52] | write_strb; end
                        8'h80: begin input_q[479:448] <= merge_wstrb(input_q[479:448], write_data, write_strb); input_byte_valid_q[59:56] <= input_byte_valid_q[59:56] | write_strb; end
                        8'h84: begin input_q[511:480] <= merge_wstrb(input_q[511:480], write_data, write_strb); input_byte_valid_q[63:60] <= input_byte_valid_q[63:60] | write_strb; end
                        8'hac: begin
                            if (write_strb[0]) irq_enable_q <= write_data[1:0];
                            else begin s_axi_bresp <= AXI_SLVERR; error_sticky <= 1'b1; end
                        end
                        8'hb0: begin
                            if (write_strb[0]) begin
                                if (write_data[0]) done_sticky <= 1'b0;
                                if (write_data[1]) error_sticky <= 1'b0;
                            end else begin s_axi_bresp <= AXI_SLVERR; error_sticky <= 1'b1; end
                        end
                        default: begin
                            s_axi_bresp <= AXI_SLVERR;
                            error_sticky <= 1'b1;
                        end
                    endcase
                end
            end

            // One outstanding AXI read. Input data is deliberately
            // write-only because F/H operands may be secret-derived.
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= AXI_OKAY;
                if (s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rdata <= 32'd0;
                    s_axi_rresp <= AXI_SLVERR;
                    error_sticky <= 1'b1;
                end else begin
                    case (s_axi_araddr[7:0])
                        8'h00: s_axi_rdata <= {30'd0, two_blocks_q, 1'b0};
                        8'h04: s_axi_rdata <= {25'd0, zeroize_pulse,
                                               config_h_valid, config_f_valid,
                                               error_sticky, ~hash_ready,
                                               done_sticky, hash_ready};
                        8'h08: s_axi_rdata <= pub_seed_q[31:0];
                        8'h0c: s_axi_rdata <= pub_seed_q[63:32];
                        8'h10: s_axi_rdata <= pub_seed_q[95:64];
                        8'h14: s_axi_rdata <= pub_seed_q[127:96];
                        8'h18: s_axi_rdata <= pub_seed_q[159:128];
                        8'h1c: s_axi_rdata <= pub_seed_q[191:160];
                        8'h20: s_axi_rdata <= pub_seed_q[223:192];
                        8'h24: s_axi_rdata <= pub_seed_q[255:224];
                        8'h28: s_axi_rdata <= addr_q[31:0];
                        8'h2c: s_axi_rdata <= addr_q[63:32];
                        8'h30: s_axi_rdata <= addr_q[95:64];
                        8'h34: s_axi_rdata <= addr_q[127:96];
                        8'h38: s_axi_rdata <= addr_q[159:128];
                        8'h3c: s_axi_rdata <= addr_q[191:160];
                        8'h40: s_axi_rdata <= addr_q[223:192];
                        8'h44: s_axi_rdata <= addr_q[255:224];
                        8'h48, 8'h4c, 8'h50, 8'h54,
                        8'h58, 8'h5c, 8'h60, 8'h64,
                        8'h68, 8'h6c, 8'h70, 8'h74,
                        8'h78, 8'h7c, 8'h80, 8'h84:
                            s_axi_rdata <= 32'd0;
                        8'h88: s_axi_rdata <= digest_q[31:0];
                        8'h8c: s_axi_rdata <= digest_q[63:32];
                        8'h90: s_axi_rdata <= digest_q[95:64];
                        8'h94: s_axi_rdata <= digest_q[127:96];
                        8'h98: s_axi_rdata <= digest_q[159:128];
                        8'h9c: s_axi_rdata <= digest_q[191:160];
                        8'ha0: s_axi_rdata <= digest_q[223:192];
                        8'ha4: s_axi_rdata <= digest_q[255:224];
                        8'ha8: s_axi_rdata <= 32'h534c4802;
                        8'hac: s_axi_rdata <= {30'd0, irq_enable_q};
                        8'hb0: s_axi_rdata <= {30'd0, error_sticky, done_sticky};
                        8'hb4: s_axi_rdata <= 32'h0001003f;
                        default: begin
                            s_axi_rdata <= 32'd0;
                            s_axi_rresp <= AXI_SLVERR;
                            error_sticky <= 1'b1;
                        end
                    endcase
                end
            end

            // Keep zeroization effective for two local cycles so the pulse
            // reaches and clears all child pipeline registers. Ignore a
            // stale completion from an operation that was just aborted.
            if (zeroize_pulse || zeroize_command) begin
                pub_seed_q <= 256'd0;
                addr_q <= 256'd0;
                input_q <= 512'd0;
                digest_q <= 256'd0;
                seed_byte_valid_q <= 32'd0;
                addr_byte_valid_q <= 32'd0;
                input_byte_valid_q <= 64'd0;
                two_blocks_q <= 1'b0;
                done_sticky <= 1'b0;
                error_sticky <= 1'b0;
                irq_enable_q <= 2'b00;
            end else begin
                // The child captures these operands on this edge. Remove
                // the AXI-side copy immediately and require every later
                // request to provide fresh input bytes, preventing silent
                // reuse of stale secret-derived data.
                if (start_pulse) begin
                    input_q <= 512'd0;
                    input_byte_valid_q <= 64'd0;
                end
                if (hash_done) begin
                    if (!hash_error)
                        digest_q <= hash_digest;
                    done_sticky <= ~hash_error;
                    error_sticky <= hash_error;
                end
            end
        end
    end
endmodule
