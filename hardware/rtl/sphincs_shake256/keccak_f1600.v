`timescale 1ns/1ps
// Keccak-f[1600], 24 rounds, split into two registered stages per round.
// The additional latency (48 round cycles) is intentional: it shortens the
// critical path and improves timing closure when this core is connected to
// an AXI subsystem.  zeroize synchronously aborts an operation and clears
// every data-bearing register.
module keccak_f1600 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          zeroize,
    input  wire          start,
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out,
    output reg           done
);
    reg [4:0] round;
    reg [1599:0] current_state;
    reg [1599:0] round_mid;
    reg second_half;
    reg is_running;
    wire [1599:0] first_half_out;
    wire [1599:0] next_state;

    keccak_round_theta_rho_pi first_half (
        .state_in(current_state), .state_mid(first_half_out));
    keccak_round_chi_iota second_half_logic (
        .state_mid(round_mid), .round(round), .state_out(next_state));

    always @(posedge clk) begin
        if (!rst_n) begin
            round <= 5'd0;
            current_state <= 1600'd0;
            round_mid <= 1600'd0;
            state_out <= 1600'd0;
            second_half <= 1'b0;
            is_running <= 1'b0;
            done <= 1'b0;
        end else if (zeroize) begin
            round <= 5'd0;
            current_state <= 1600'd0;
            round_mid <= 1600'd0;
            state_out <= 1600'd0;
            second_half <= 1'b0;
            is_running <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !is_running) begin
                current_state <= state_in;
                round <= 5'd0;
                second_half <= 1'b0;
                is_running <= 1'b1;
            end else if (is_running && !second_half) begin
                round_mid <= first_half_out;
                second_half <= 1'b1;
            end else if (is_running) begin
                second_half <= 1'b0;
                if (round == 5'd23) begin
                    state_out <= next_state;
                    is_running <= 1'b0;
                    done <= 1'b1;
                end else begin
                    current_state <= next_state;
                    round <= round + 1'b1;
                end
            end
        end
    end
endmodule
