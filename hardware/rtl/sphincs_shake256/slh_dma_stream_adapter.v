`timescale 1ns/1ps
`default_nettype none
// Reuses the existing F/H AXI-Lite accelerator; no duplicate Keccak core.
// Input frame: mode word (0=F,1=H), 8 seed, 8 ADRS, 8/16 operand words.
// Output frame: 8 digest words. All TKEEP must be 1111, exact TLAST required.
// CPU arms at MMIO 0x34000. DMA M2S supplies input, then S2M drains output.
module slh_dma_stream_adapter (
    input wire clk, input wire rst,
    input wire arm, input wire abort_op,
    output wire owns_hash, output wire busy, output reg done, output reg error,
    input wire [31:0] s_data, input wire [3:0] s_keep,
    input wire s_valid, output wire s_ready, input wire s_last,
    output reg [31:0] m_data, output wire [3:0] m_keep,
    output reg m_valid, input wire m_ready, output wire m_last,
    output reg [7:0] awaddr, output reg awvalid, input wire awready,
    output reg [31:0] wdata, output reg wvalid, input wire wready,
    input wire [1:0] bresp, input wire bvalid, output wire bready,
    output reg [7:0] araddr, output reg arvalid, input wire arready,
    input wire [31:0] rdata, input wire [1:0] rresp,
    input wire rvalid, output wire rready
);
    localparam IDLE=0, HEADER=1, RECEIVE=2, WRITE=3, BRESP=4,
               POLL=5, RADDR=6, RDATA=7, OUTPUT_WORD=8, CLEAN=9;
    (* max_fanout = 16 *) reg [3:0] state=IDLE;
    reg [3:0] after_write, after_read;
    reg mode;
    reg [5:0] word_index;
    reg [2:0] digest_index;
    reg [19:0] watchdog;
    wire fail_now = abort_op || (&watchdog);
    assign owns_hash = state != IDLE;
    assign busy = owns_hash;
    assign s_ready = (state==HEADER || state==RECEIVE) && !fail_now;
    assign m_keep = 4'hf;
    assign m_last = digest_index==7;
    assign bready = state==BRESP;
    assign rready = state==RDATA;
    // Commands and addresses are registered before the AXI handshake.
    task issue_write;
        input [7:0] address;
        input [31:0] value;
        input [3:0] next_state;
        begin
            awaddr<=address; wdata<=value; awvalid<=1; wvalid<=1;
            after_write<=next_state; state<=WRITE;
        end
    endtask
    task issue_read;
        input [7:0] address;
        input [3:0] next_state;
        begin araddr<=address; arvalid<=1; after_read<=next_state; state<=RADDR; end
    endtask
    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE; awaddr<=0; wdata<=0; awvalid<=0; wvalid<=0;
            araddr<=0; arvalid<=0; m_data<=0; m_valid<=0;
            done<=0; error<=0; mode<=0; word_index<=0; digest_index<=0;
            watchdog<=0; after_write<=IDLE; after_read<=IDLE;
        end else begin
            if (state==IDLE) watchdog<=0;
            else watchdog<=watchdog+1'b1;
            // Do not abandon an accepted AXI pair on abort. Drain it first.
            if (fail_now && state!=IDLE) error<=1;
            case (state)
                IDLE: if (arm) begin
                    state<=HEADER; done<=0; error<=0; word_index<=0;
                    digest_index<=0; m_data<=0; m_valid<=0;
                end
                HEADER: begin
                    if (fail_now) state<=CLEAN;
                    else if (s_valid && s_ready) begin
                        if (s_keep!=4'hf || s_last || s_data>1) begin error<=1; state<=CLEAN; end
                        else begin mode<=s_data[0]; state<=RECEIVE; end
                    end
                end
                RECEIVE: begin
                    if (fail_now || error) state<=CLEAN;
                    else if (s_valid && s_ready) begin
                        if (s_keep!=4'hf || s_last!=(word_index==(mode ? 31 : 23))) begin
                            error<=1; state<=CLEAN;
                        end else begin
                            issue_write(8'h08+{word_index,2'b00},s_data,
                                s_last ? POLL : RECEIVE);
                            word_index<=word_index+1'b1;
                        end
                    end
                end
                WRITE: begin
                    if (awvalid && awready) awvalid<=0;
                    if (wvalid && wready) wvalid<=0;
                    if ((!awvalid || awready) && (!wvalid || wready)) state<=BRESP;
                end
                BRESP: if (bvalid) begin
                    if (bresp!=0) error<=1;
                    if (after_write==IDLE) begin
                        state<=IDLE;
                        // error is updated nonblocking above. Include a fault
                        // arriving on this response edge, not just old error.
                        done<=!error && !fail_now && bresp==0;
                    end
                    else if (error || fail_now || bresp!=0) state<=CLEAN;
                    else if (after_write==POLL) begin
                        // Full operand frame committed: start F/H.
                        issue_write(0,32'd5 | (mode ? 32'd2 : 0),RADDR);
                    end else if (after_write==RADDR) state<=POLL;
                    else state<=after_write;
                end
                POLL: begin
                    if (error || fail_now) state<=CLEAN;
                    else issue_read(8'h04,POLL);
                end
                RADDR: if (arvalid && arready) begin arvalid<=0; state<=RDATA; end
                RDATA: if (rvalid) begin
                    if (rresp!=0 || error || fail_now) begin error<=1; state<=CLEAN; end
                    else if (after_read==POLL) begin
                        if (rdata[3]) begin error<=1; state<=CLEAN; end
                        else if (rdata[1]) issue_read(8'h88,OUTPUT_WORD);
                        else state<=POLL;
                    end else begin m_data<=rdata; m_valid<=1; state<=OUTPUT_WORD; end
                end
                OUTPUT_WORD: begin
                    if (error || fail_now) begin m_valid<=0; m_data<=0; state<=CLEAN; end
                    else if (m_valid && m_ready) begin
                        m_valid<=0; m_data<=0;
                        if (digest_index==7) state<=CLEAN;
                        else begin
                            digest_index<=digest_index+1'b1;
                            issue_read(8'h8c+{3'b0,digest_index,2'b00},OUTPUT_WORD);
                        end
                    end
                end
                CLEAN: begin
                    watchdog<=0;
                    // Abort/normal completion scrub the shared register bank too.
                    issue_write(0,32'd8,IDLE);
                end
                default: begin error<=1; state<=CLEAN; end
            endcase
        end
    end
endmodule
`resetall
