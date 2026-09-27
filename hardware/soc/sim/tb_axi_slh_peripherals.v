`timescale 1ns/1ps
module tb_axi_slh_peripherals;
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    reg [3:0] awid = 0;
    reg [15:0] awaddr = 0;
    reg [7:0] awlen = 0;
    reg [2:0] awsize = 3'b010;
    reg [1:0] awburst = 2'b01;
    reg awlock = 0;
    reg [3:0] awcache = 0;
    reg [2:0] awprot = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    reg wlast = 1;
    reg wvalid = 0;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;
    reg [3:0] arid = 0;
    reg [15:0] araddr = 0;
    reg [7:0] arlen = 0;
    reg [2:0] arsize = 3'b010;
    reg [1:0] arburst = 2'b01;
    reg arlock = 0;
    reg [3:0] arcache = 0;
    reg [2:0] arprot = 0;
    reg arvalid = 0;
    wire arready;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast, rvalid;
    reg rready = 0;
    wire uart_tx;
    wire [31:0] gpio_out;
    wire shake_irq, uart_irq, timer_irq;
    wire [7:0] dma_awaddr, dma_araddr;
    wire [2:0] dma_awprot, dma_arprot;
    wire dma_awvalid, dma_wvalid, dma_bready;
    wire dma_arvalid, dma_rready;
    wire [31:0] dma_wdata;
    wire [3:0] dma_wstrb;
    reg dma_bvalid = 0;
    reg [1:0] dma_bresp = 0;
    reg dma_rvalid = 0;
    reg [31:0] dma_rdata = 0;
    reg [1:0] dma_rresp = 0;
    reg [31:0] rd;
    reg [255:0] digest;
    integer i, timeout;

    axi_slh_peripherals #(.CLOCK_HZ(10_000_000), .BAUD_RATE(1_000_000)) dut (
        .clk(clk), .rst(rst),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awlock(awlock), .s_axi_awcache(awcache),
        .s_axi_awprot(awprot), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready), .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
        .s_axi_bready(bready), .s_axi_arid(arid), .s_axi_araddr(araddr),
        .s_axi_arlen(arlen), .s_axi_arsize(arsize),
        .s_axi_arburst(arburst), .s_axi_arlock(arlock),
        .s_axi_arcache(arcache), .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rlast(rlast), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .dma_axil_awaddr(dma_awaddr), .dma_axil_awprot(dma_awprot),
        .dma_axil_awvalid(dma_awvalid), .dma_axil_awready(!dma_bvalid),
        .dma_axil_wdata(dma_wdata), .dma_axil_wstrb(dma_wstrb),
        .dma_axil_wvalid(dma_wvalid), .dma_axil_wready(!dma_bvalid),
        .dma_axil_bresp(dma_bresp), .dma_axil_bvalid(dma_bvalid),
        .dma_axil_bready(dma_bready),
        .dma_axil_araddr(dma_araddr), .dma_axil_arprot(dma_arprot),
        .dma_axil_arvalid(dma_arvalid), .dma_axil_arready(!dma_rvalid),
        .dma_axil_rdata(dma_rdata), .dma_axil_rresp(dma_rresp),
        .dma_axil_rvalid(dma_rvalid), .dma_axil_rready(dma_rready),
        .uart_rx(1'b1), .uart_tx(uart_tx),
        .gpio_out(gpio_out), .shake_irq(shake_irq),
        .uart_irq(uart_irq), .timer_irq(timer_irq)
    );

    // Small AXI-Lite responder used only to verify the 0x3000 DMA bridge.
    always @(posedge clk) begin
        if (rst) begin
            dma_bvalid <= 0;
            dma_rvalid <= 0;
            dma_bresp <= 0;
            dma_rresp <= 0;
        end else begin
            if (!dma_bvalid && dma_awvalid && dma_wvalid)
                dma_bvalid <= 1;
            else if (dma_bvalid && dma_bready)
                dma_bvalid <= 0;
            if (!dma_rvalid && dma_arvalid) begin
                dma_rvalid <= 1;
                dma_rdata <= 32'hd00d0000 | dma_araddr;
            end else if (dma_rvalid && dma_rready) begin
                dma_rvalid <= 0;
            end
        end
    end

    task axi_write_expect;
        input [15:0] address;
        input [31:0] data;
        input [1:0] expected;
        begin
            @(posedge clk);
            awaddr <= address; awvalid <= 1;
            wdata <= data; wstrb <= 4'hf; wvalid <= 1;
            while (!(awready && wready)) @(posedge clk);
            @(posedge clk);
            awvalid <= 0; wvalid <= 0; wstrb <= 0; bready <= 1;
            while (!bvalid) @(posedge clk);
            if (bresp !== expected)
                $fatal(1, "write %04x response %b expected %b", address, bresp, expected);
            @(posedge clk); bready <= 0;
        end
    endtask

    task axi_write;
        input [15:0] address;
        input [31:0] data;
        begin axi_write_expect(address, data, 2'b00); end
    endtask

    task axi_read_expect;
        input [15:0] address;
        input [1:0] expected;
        output [31:0] data;
        begin
            @(posedge clk); araddr <= address; arvalid <= 1;
            while (!arready) @(posedge clk);
            @(posedge clk); arvalid <= 0; rready <= 1;
            while (!rvalid) @(posedge clk);
            data = rdata;
            if (rresp !== expected || !rlast)
                $fatal(1, "read %04x response=%b last=%b", address, rresp, rlast);
            @(posedge clk); rready <= 0;
        end
    endtask

    task axi_read;
        input [15:0] address;
        output [31:0] data;
        begin axi_read_expect(address, 2'b00, data); end
    endtask

    initial begin
        repeat (6) @(posedge clk);
        rst <= 0;
        repeat (3) @(posedge clk);

        axi_read(16'h00a8, rd);
        if (rd !== 32'h534c4802) $fatal(1, "SHAKE ID mismatch %08x", rd);
        axi_read(16'h1004, rd);
        if (!rd[0]) $fatal(1, "UART not ready %08x", rd);
        axi_write(16'h2014, 32'ha5a55a5a);
        axi_read(16'h2014, rd);
        if (rd !== 32'ha5a55a5a || gpio_out !== rd)
            $fatal(1, "GPIO mismatch read=%08x pins=%08x", rd, gpio_out);

        axi_write(16'h00ac, 32'h3);
        for (i = 0; i < 8; i = i + 1)
            axi_write(16'h0008 + i*4,
                ((i*4+3)<<24)|((i*4+2)<<16)|((i*4+1)<<8)|(i*4));
        for (i = 0; i < 8; i = i + 1)
            axi_write(16'h0028 + i*4,
                ((8'ha0+i*4+3)<<24)|((8'ha0+i*4+2)<<16)|
                ((8'ha0+i*4+1)<<8)|(8'ha0+i*4));
        for (i = 0; i < 8; i = i + 1)
            axi_write(16'h0048 + i*4,
                ((8'h40+i*4+3)<<24)|((8'h40+i*4+2)<<16)|
                ((8'h40+i*4+1)<<8)|(8'h40+i*4));
        axi_write(16'h0000, 32'h1);

        timeout = 0; rd = 0;
        while (!rd[1] && timeout < 1000) begin
            axi_read(16'h0004, rd);
            timeout = timeout + 1;
        end
        if (!rd[1] || rd[3] || !shake_irq)
            $fatal(1, "hash status=%08x irq=%b", rd, shake_irq);
        for (i = 0; i < 8; i = i + 1) begin
            axi_read(16'h0088 + i*4, rd);
            digest[i*32 +: 32] = rd;
        end
        if (digest !== 256'h29ef9ddfbe16b1469239982cee72b5bf8577df7d294905625227f38e4b6645de)
            $fatal(1, "hash mismatch %064x", digest);
        axi_write(16'h00b0, 32'h1);
        if (shake_irq) $fatal(1, "SHAKE IRQ failed to clear");

        awlen <= 1;
        axi_write_expect(16'h1008, 32'd10, 2'b10);
        awlen <= 0;
        axi_write(16'h3008, 32'h12345678);
        axi_read(16'h3004, rd);
        if (rd !== 32'hd00d0004)
            $fatal(1, "DMA AXI-Lite bridge mismatch %08x", rd);
        axi_read_expect(16'h3100, 2'b10, rd);

        $display("SOC PERIPHERAL AXI/F/H/UART/GPIO/DMA-BRIDGE TEST PASSED");
        $finish;
    end

    initial begin
        #300000;
        $fatal(1, "peripheral test timeout");
    end
endmodule
