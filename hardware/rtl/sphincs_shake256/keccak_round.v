`timescale 1ns/1ps

// First half of a Keccak-f[1600] round: theta, rho and pi.  Splitting the
// round at this natural boundary shortens the combinational path and makes
// the core easier to close at high clock rates on Virtex-7.
module keccak_round_theta_rho_pi (
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_mid
);
    reg [63:0] a [0:4][0:4];
    reg [63:0] b [0:4][0:4];
    reg [63:0] c [0:4];
    reg [63:0] d [0:4];
    integer x, y;
    integer rotate [0:4][0:4];

    initial begin
        rotate[0][0]=0;  rotate[0][1]=36; rotate[0][2]=3;
        rotate[0][3]=41; rotate[0][4]=18;
        rotate[1][0]=1;  rotate[1][1]=44; rotate[1][2]=10;
        rotate[1][3]=45; rotate[1][4]=2;
        rotate[2][0]=62; rotate[2][1]=6;  rotate[2][2]=43;
        rotate[2][3]=15; rotate[2][4]=61;
        rotate[3][0]=28; rotate[3][1]=55; rotate[3][2]=25;
        rotate[3][3]=21; rotate[3][4]=56;
        rotate[4][0]=27; rotate[4][1]=20; rotate[4][2]=39;
        rotate[4][3]=8;  rotate[4][4]=14;
    end

    always @* begin
        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                a[x][y] = state_in[64*(5*y+x) +: 64];

        for (x = 0; x < 5; x = x + 1)
            c[x] = a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4];
        for (x = 0; x < 5; x = x + 1)
            d[x] = c[(x+4)%5] ^ {c[(x+1)%5][62:0], c[(x+1)%5][63]};
        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                a[x][y] = a[x][y] ^ d[x];

        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                a[x][y] = (a[x][y] << rotate[x][y]) |
                          (a[x][y] >> (64-rotate[x][y]));

        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                b[y][(2*x+3*y)%5] = a[x][y];

        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                state_mid[64*(5*y+x) +: 64] = b[x][y];
    end
endmodule

// Second half of a Keccak-f[1600] round: chi and iota.
module keccak_round_chi_iota (
    input  wire [1599:0] state_mid,
    input  wire [4:0]    round,
    output reg  [1599:0] state_out
);
    reg [63:0] b [0:4][0:4];
    reg [63:0] a [0:4][0:4];
    reg [63:0] rc [0:23];
    integer x, y;

    initial begin
        rc[0]  = 64'h0000000000000001; rc[1]  = 64'h0000000000008082;
        rc[2]  = 64'h800000000000808a; rc[3]  = 64'h8000000080008000;
        rc[4]  = 64'h000000000000808b; rc[5]  = 64'h0000000080000001;
        rc[6]  = 64'h8000000080008081; rc[7]  = 64'h8000000000008009;
        rc[8]  = 64'h000000000000008a; rc[9]  = 64'h0000000000000088;
        rc[10] = 64'h0000000080008009; rc[11] = 64'h000000008000000a;
        rc[12] = 64'h000000008000808b; rc[13] = 64'h800000000000008b;
        rc[14] = 64'h8000000000008089; rc[15] = 64'h8000000000008003;
        rc[16] = 64'h8000000000008002; rc[17] = 64'h8000000000000080;
        rc[18] = 64'h000000000000800a; rc[19] = 64'h800000008000000a;
        rc[20] = 64'h8000000080008081; rc[21] = 64'h8000000000008080;
        rc[22] = 64'h0000000080000001; rc[23] = 64'h8000000080008008;
    end

    always @* begin
        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                b[x][y] = state_mid[64*(5*y+x) +: 64];

        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                a[x][y] = b[x][y] ^
                          ((~b[(x+1)%5][y]) & b[(x+2)%5][y]);
        a[0][0] = a[0][0] ^ rc[round];

        for (x = 0; x < 5; x = x + 1)
            for (y = 0; y < 5; y = y + 1)
                state_out[64*(5*y+x) +: 64] = a[x][y];
    end
endmodule

// Compatibility wrapper for users that need a combinational complete round.
module keccak_round (
    input  wire [1599:0] state_in,
    input  wire [4:0]    round,
    output wire [1599:0] state_out
);
    wire [1599:0] state_mid;
    keccak_round_theta_rho_pi u_first (
        .state_in(state_in), .state_mid(state_mid));
    keccak_round_chi_iota u_second (
        .state_mid(state_mid), .round(round), .state_out(state_out));
endmodule
