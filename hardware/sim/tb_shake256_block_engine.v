`timescale 1ns/1ps
module tb_shake256_block_engine;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, zeroize = 0, init = 0, absorb = 0;
    reg squeeze = 0, last = 0;
    reg [1087:0] din = 0;
    reg [7:0] valid_bytes = 0;
    wire [1087:0] dout;
    wire ready, done, output_valid, error;
    reg [7:0] expected [0:1399];
    integer c, j, length, offset, count, out_index, failures = 0;

    shake256_block_engine dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize),
        .init(init), .absorb(absorb), .squeeze(squeeze),
        .pre_padded(1'b0), .din(din), .valid_bytes(valid_bytes),
        .last(last), .dout(dout), .ready(ready), .done(done),
        .output_valid(output_valid), .error(error)
    );

    task wait_done;
        begin
            @(posedge done);
            #1;
            if (error) begin
                $display("FAIL unexpected command error at %0t", $time);
                failures = failures + 1;
            end
            @(negedge clk);
        end
    endtask

    task check_chunk;
        input integer case_number;
        input integer base;
        input integer size;
        integer k;
        begin
            if (!output_valid) begin
                $display("FAIL output_valid case %0d", case_number);
                failures = failures + 1;
            end
            for (k = 0; k < size; k = k + 1)
                if (dout[k*8 +: 8] !== expected[case_number*200+base+k]) begin
                    $display("FAIL case=%0d byte=%0d got=%02h want=%02h",
                             case_number, base+k, dout[k*8 +: 8],
                             expected[case_number*200+base+k]);
                    failures = failures + 1;
                end
        end
    endtask

    initial begin
        $readmemh("vectors.mem", expected);
        #21 rst_n = 1;
        for (c = 0; c < 7; c = c + 1) begin
            @(negedge clk);
            init = 1;
            @(negedge clk);
            init = 0;
            if (!done || !ready || output_valid) begin
                $display("FAIL init case %0d", c);
                failures = failures + 1;
            end

            case (c)
                0: length = 0;
                1: length = 3;
                2: length = 135;
                3: length = 136;
                4: length = 137;
                5: length = 272;
                // SPHINCS+-SHAKE-256f thash of a WOTS+ public key:
                // 32-byte public seed + 32-byte ADRS + 67*32 bytes.
                6: length = 2208;
            endcase
            offset = 0;
            begin : absorb_message
                while (1) begin
                    count = length - offset;
                    if (count > 136) count = 136;
                    din = 0;
                    for (j = 0; j < count; j = j + 1)
                        if (c == 1) begin
                            case (j)
                                0: din[j*8 +: 8] = "a";
                                1: din[j*8 +: 8] = "b";
                                2: din[j*8 +: 8] = "c";
                            endcase
                        end else din[j*8 +: 8] = (offset+j) % 256;
                    valid_bytes = count;
                    last = (offset + count == length);
                    @(negedge clk);
                    absorb = 1;
                    @(negedge clk);
                    absorb = 0;
                    wait_done();
                    offset = offset + count;
                    if (last) disable absorb_message;
                end
            end
            check_chunk(c, 0, 136);
            @(negedge clk);
            squeeze = 1;
            @(negedge clk);
            squeeze = 0;
            wait_done();
            check_chunk(c, 136, 64);
            $display("PASS case %0d, length=%0d, output=200 bytes", c, length);
        end
        if (failures == 0) $display("ALL SHAKE256 REGRESSIONS PASSED");
        else $fatal(1, "%0d SHAKE256 failures", failures);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Simulation timeout");
    end
endmodule
