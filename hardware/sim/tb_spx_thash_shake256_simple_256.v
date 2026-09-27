`timescale 1ns/1ps
module tb_spx_thash_shake256_simple_256;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, zeroize = 0, start = 0, two_blocks = 0;
    reg [255:0] pub_seed = 0, addr = 0;
    reg [511:0] in_data = 0;
    wire ready, done, error;
    wire [255:0] digest;
    integer i;
    integer cycle_count = 0;
    integer launched_at;

    always @(posedge clk) cycle_count = cycle_count + 1;

    spx_thash_shake256_simple_256 dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .two_blocks(two_blocks), .pub_seed(pub_seed),
        .addr(addr), .in_data(in_data), .ready(ready),
        .done(done), .error(error), .digest(digest)
    );

    task run_case;
        input select_two;
        input [255:0] expected;
        begin
            @(negedge clk);
            if (!ready) $fatal(1, "thash not ready");
            two_blocks = select_two;
            launched_at = cycle_count;
            start = 1;
            @(negedge clk);
            start = 0;
            wait(done);
            #1;
            if (error || digest !== expected)
                $fatal(1, "thash case %0d got %h expected %h error=%b",
                       select_two, digest, expected, error);
            $display("PASS SPHINCS+ thash inblocks=%0d latency=%0d cycles",
                     select_two ? 2 : 1, cycle_count - launched_at);
        end
    endtask

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            pub_seed[i*8 +: 8] = i;
            addr[i*8 +: 8] = 'ha0 + i;
        end
        for (i = 0; i < 64; i = i + 1)
            in_data[i*8 +: 8] = 'h40 + i;
        #21 rst_n = 1;
        run_case(1'b0,
            256'h29ef9ddfbe16b1469239982cee72b5bf8577df7d294905625227f38e4b6645de);
        run_case(1'b1,
            256'h5a0c081366ef0287f98f0fab56c9f14371fa20967e46842c532d9d282de78f78);
        $display("ALL SPHINCS+ THASH TESTS PASSED");
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "thash timeout");
    end
endmodule
