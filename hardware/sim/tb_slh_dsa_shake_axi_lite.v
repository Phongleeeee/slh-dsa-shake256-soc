`timescale 1ns/1ps
module tb_slh_dsa_shake_axi_lite;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] awaddr = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    reg wvalid = 0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;
    reg [7:0] araddr = 0;
    reg arvalid = 0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 0;
    wire irq;
    reg [31:0] rd;
    reg [255:0] digest;
    integer i;
    integer timeout;

    always #5 clk = ~clk;

    slh_dsa_shake_axi_lite dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready), .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata),
        .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready), .irq(irq)
    );

    task axi_write_expect;
        input [7:0] address;
        input [31:0] data;
        input [3:0] strobe;
        input [1:0] expected_resp;
        begin
            @(posedge clk);
            awaddr <= address;
            awvalid <= 1'b1;
            wdata <= data;
            wstrb <= strobe;
            wvalid <= 1'b1;
            while (!(awready && wready)) @(posedge clk);
            @(posedge clk);
            awvalid <= 1'b0;
            wvalid <= 1'b0;
            wstrb <= 4'h0;
            bready <= 1'b1;
            while (!bvalid) @(posedge clk);
            if (bresp !== expected_resp)
                $fatal(1, "AXI write %02x response %b expected %b",
                       address, bresp, expected_resp);
            @(posedge clk);
            bready <= 1'b0;
        end
    endtask

    task axi_write;
        input [7:0] address;
        input [31:0] data;
        begin
            axi_write_expect(address, data, 4'hf, 2'b00);
        end
    endtask

    // Address and data arrive in different cycles to verify independent
    // AXI write channel buffering.
    task axi_write_split;
        input [7:0] address;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr <= address;
            awvalid <= 1'b1;
            while (!awready) @(posedge clk);
            @(posedge clk);
            awvalid <= 1'b0;
            repeat (3) @(posedge clk);
            wdata <= data;
            wstrb <= 4'hf;
            wvalid <= 1'b1;
            while (!wready) @(posedge clk);
            @(posedge clk);
            wvalid <= 1'b0;
            wstrb <= 4'h0;
            bready <= 1'b1;
            while (!bvalid) @(posedge clk);
            if (bresp !== 2'b00)
                $fatal(1, "AXI split write response error");
            @(posedge clk);
            bready <= 1'b0;
        end
    endtask

    task axi_read_expect;
        input [7:0] address;
        input [1:0] expected_resp;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr <= address;
            arvalid <= 1'b1;
            while (!arready) @(posedge clk);
            @(posedge clk);
            arvalid <= 1'b0;
            rready <= 1'b1;
            while (!rvalid) @(posedge clk);
            data = rdata;
            if (rresp !== expected_resp)
                $fatal(1, "AXI read %02x response %b expected %b",
                       address, rresp, expected_resp);
            @(posedge clk);
            rready <= 1'b0;
        end
    endtask

    task axi_read;
        input [7:0] address;
        output [31:0] data;
        begin
            axi_read_expect(address, 2'b00, data);
        end
    endtask

    task load_common_registers;
        begin
            // pub_seed bytes 00..1f, ADRS bytes a0..bf, input bytes 40..7f.
            for (i = 0; i < 8; i = i + 1)
                axi_write(8'h08 + i*4,
                          ((i*4+3) << 24) | ((i*4+2) << 16) |
                          ((i*4+1) << 8) | (i*4));
            for (i = 0; i < 8; i = i + 1)
                axi_write(8'h28 + i*4,
                          ((8'ha0+i*4+3) << 24) | ((8'ha0+i*4+2) << 16) |
                          ((8'ha0+i*4+1) << 8) | (8'ha0+i*4));
            for (i = 0; i < 16; i = i + 1)
                axi_write(8'h48 + i*4,
                          ((8'h40+i*4+3) << 24) | ((8'h40+i*4+2) << 16) |
                          ((8'h40+i*4+1) << 8) | (8'h40+i*4));
        end
    endtask

    task wait_and_check_hash;
        input [255:0] expected;
        begin
            timeout = 0;
            rd = 0;
            while (!rd[1] && timeout < 4000) begin
                axi_read(8'h04, rd);
                timeout = timeout + 1;
            end
            if (!rd[1] || rd[3] || !irq)
                $fatal(1, "AXI hash status error status=%08x timeout=%0d",
                       rd, timeout);
            for (i = 0; i < 8; i = i + 1) begin
                axi_read(8'h88 + i*4, rd);
                digest[i*32 +: 32] = rd;
            end
            if (digest !== expected)
                $fatal(1, "AXI hash mismatch got=%064x expected=%064x",
                       digest, expected);
            axi_write(8'hB0, 32'h00000001); // W1C DONE
            if (irq) $fatal(1, "IRQ did not clear after DONE W1C");
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (3) @(posedge clk);

        axi_read(8'hA8, rd);
        if (rd !== 32'h534c4802) $fatal(1, "AXI ID error: %08x", rd);
        axi_read(8'hB4, rd);
        if (rd !== 32'h0001003f) $fatal(1, "Capabilities error: %08x", rd);

        // Enable DONE and ERROR interrupts using split AW/W channels.
        axi_write_split(8'hAC, 32'h00000003);

        // START before complete configuration must fail and raise ERROR IRQ.
        axi_write_expect(8'h00, 32'h00000001, 4'hf, 2'b10);
        if (!irq) $fatal(1, "Configuration error did not raise IRQ");
        axi_write(8'hB0, 32'h00000002);
        if (irq) $fatal(1, "ERROR IRQ did not clear");

        load_common_registers();
        axi_read(8'h04, rd);
        if (rd[5:4] !== 2'b11) $fatal(1, "Configuration-valid flags missing");

        // Input window is intentionally write-only.
        axi_read(8'h48, rd);
        if (rd !== 32'd0) $fatal(1, "Write-only input leaked data");

        // F operation. A second START while busy must return SLVERR.
        axi_write(8'h00, 32'h00000001);
        axi_write_expect(8'h00, 32'h00000001, 4'hf, 2'b10);
        axi_write(8'hB0, 32'h00000002); // clear expected BUSY error
        wait_and_check_hash(
            256'h29ef9ddfbe16b1469239982cee72b5bf8577df7d294905625227f38e4b6645de);

        // Consumed input is invalidated: stale operands cannot be reused.
        axi_write_expect(8'h00, 32'h00000003, 4'hf, 2'b10);
        axi_write(8'hB0, 32'h00000002);

        // H operation with a freshly written input.
        load_common_registers();
        axi_write(8'h00, 32'h00000003);
        wait_and_check_hash(
            256'h5a0c081366ef0287f98f0fab56c9f14371fa20967e46842c532d9d282de78f78);

        // Invalid and misaligned accesses return SLVERR.
        axi_read_expect(8'hB8, 2'b10, rd);
        axi_write(8'hB0, 32'h00000002);
        axi_write_expect(8'h09, 32'h12345678, 4'hf, 2'b10);
        axi_write(8'hB0, 32'h00000002);

        // ZEROIZE clears data, validity, status, digest and IRQ enables.
        axi_write(8'h00, 32'h00000008);
        repeat (4) @(posedge clk);
        axi_read(8'h04, rd);
        if (!rd[0] || rd[5:1] !== 5'd0)
            $fatal(1, "Zeroize status incorrect: %08x", rd);
        axi_read(8'h88, rd);
        if (rd !== 32'd0) $fatal(1, "Zeroize did not clear digest");
        axi_read(8'hAC, rd);
        if (rd[1:0] !== 2'b00) $fatal(1, "Zeroize did not clear IRQ enables");

        // Verify abort/zeroize during a live operation and absence of a
        // delayed stale completion.
        load_common_registers();
        axi_write(8'hAC, 32'h00000003);
        axi_write(8'h00, 32'h00000003);
        repeat (8) @(posedge clk);
        axi_write(8'h00, 32'h00000008);
        repeat (120) @(posedge clk);
        axi_read(8'h04, rd);
        if (!rd[0] || rd[3:1] !== 3'b000 || irq)
            $fatal(1, "Abort/zeroize failed: status=%08x irq=%b", rd, irq);

        $display("AXI SLH-DSA SHAKE IP SECURITY/PROTOCOL TESTS PASSED");
        $finish;
    end

    initial begin
        #250000;
        $fatal(1, "AXI test timeout");
    end
endmodule
