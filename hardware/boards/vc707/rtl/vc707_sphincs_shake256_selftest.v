`timescale 1ns/1ps
// Main VC707 firmware for the organized project.
// It validates the SPHINCS+-SHAKE-256f-simple thash primitive with one and
// two 32-byte input blocks. LED0=PASS, LED1=FAIL, LED2=RUN, LED7=heartbeat.
module vc707_sphincs_shake256_selftest #(
    parameter real CLK_MULT = 5.0,
    parameter integer CLKOUT_DIVIDE = 4
) (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    output wire [7:0] led
);
    wire clk200, feedback, feedback_buf, core_clk_raw, core_clk, locked;
    IBUFDS #(.DIFF_TERM("TRUE"), .IOSTANDARD("LVDS")) input_clock (
        .I(sysclk_p), .IB(sysclk_n), .O(clk200)
    );
    // Default: 200 MHz * 5 / 4 = 250 MHz, VCO = 1000 MHz.
    MMCME2_BASE #(
        .CLKIN1_PERIOD(5.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(CLK_MULT), .CLKOUT0_DIVIDE_F(CLKOUT_DIVIDE)
    ) clock_mmcm (
        .CLKIN1(clk200), .CLKFBIN(feedback_buf),
        .CLKFBOUT(feedback), .CLKOUT0(core_clk_raw),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG feedback_buffer (.I(feedback), .O(feedback_buf));
    BUFG core_clock_buffer (.I(core_clk_raw), .O(core_clk));

    reg [3:0] reset_pipe = 4'b0000;
    always @(posedge core_clk or negedge locked) begin
        if (!locked) reset_pipe <= 4'b0000;
        else reset_pipe <= {reset_pipe[2:0], 1'b1};
    end
    wire rst_n = reset_pipe[3];

    // Byte zero is in bits [7:0]. These vectors are shared with the C/RTL
    // cross-check in software/sphincs_signer/spx_cli.c and hardware/sim/.
    localparam [255:0] PUB_SEED =
        256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;
    localparam [255:0] ADRS =
        256'hbfbebdbcbbbab9b8b7b6b5b4b3b2b1b0afaeadacabaaa9a8a7a6a5a4a3a2a1a0;
    localparam [511:0] INPUT_DATA = {
        256'h7f7e7d7c7b7a797877767574737271706f6e6d6c6b6a69686766656463626160,
        256'h5f5e5d5c5b5a595857565554535251504f4e4d4c4b4a49484746454443424140
    };
    localparam [255:0] EXPECT_ONE =
        256'h29ef9ddfbe16b1469239982cee72b5bf8577df7d294905625227f38e4b6645de;
    localparam [255:0] EXPECT_TWO =
        256'h5a0c081366ef0287f98f0fab56c9f14371fa20967e46842c532d9d282de78f78;

    reg start = 1'b0;
    reg two_blocks = 1'b0;
    wire ready, done, error;
    wire [255:0] digest;
    spx_thash_shake256_simple_256 thash (
        .clk(core_clk), .rst_n(rst_n), .zeroize(1'b0), .start(start),
        .two_blocks(two_blocks), .pub_seed(PUB_SEED), .addr(ADRS),
        .in_data(INPUT_DATA), .ready(ready), .done(done),
        .error(error), .digest(digest)
    );

    localparam [2:0] TEST_ONE = 3'd0, WAIT_ONE = 3'd1,
                     TEST_TWO = 3'd2, WAIT_TWO = 3'd3,
                     FINISHED = 3'd4;
    reg [2:0] state = TEST_ONE;
    reg pass = 1'b0, fail = 1'b0;
    reg [27:0] heartbeat = 28'd0;

    always @(posedge core_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= TEST_ONE;
            start <= 1'b0;
            two_blocks <= 1'b0;
            pass <= 1'b0;
            fail <= 1'b0;
            heartbeat <= 28'd0;
        end else begin
            heartbeat <= heartbeat + 1'b1;
            start <= 1'b0;
            case (state)
                TEST_ONE: if (ready) begin
                    two_blocks <= 1'b0;
                    start <= 1'b1;
                    state <= WAIT_ONE;
                end
                WAIT_ONE: if (done) begin
                    if (error || digest != EXPECT_ONE) fail <= 1'b1;
                    state <= TEST_TWO;
                end
                TEST_TWO: if (ready) begin
                    two_blocks <= 1'b1;
                    start <= 1'b1;
                    state <= WAIT_TWO;
                end
                WAIT_TWO: if (done) begin
                    if (error || digest != EXPECT_TWO) fail <= 1'b1;
                    else if (!fail) pass <= 1'b1;
                    state <= FINISHED;
                end
                default: state <= FINISHED;
            endcase
        end
    end

    assign led = {heartbeat[27], 4'b0000, state != FINISHED, fail, pass};
endmodule
