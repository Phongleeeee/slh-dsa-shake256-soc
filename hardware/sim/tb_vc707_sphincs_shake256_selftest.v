`timescale 1ns/1ps
module tb_vc707_sphincs_shake256_selftest;
    reg sysclk_p = 1'b0;
    wire sysclk_n = ~sysclk_p;
    wire [7:0] led;
    always #2.5 sysclk_p = ~sysclk_p;

    vc707_sphincs_shake256_selftest dut (
        .sysclk_p(sysclk_p), .sysclk_n(sysclk_n), .led(led)
    );

    initial begin
        wait (led[0] || led[1]);
        #1;
        if (led[0] && !led[1] && !led[2])
            $display("VC707 SPHINCS+-SHAKE256 FIRMWARE SELFTEST PASSED");
        else
            $fatal(1, "VC707 firmware self-test failed: LEDs=%b", led);
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "VC707 firmware self-test timeout: LEDs=%b", led);
    end
endmodule
