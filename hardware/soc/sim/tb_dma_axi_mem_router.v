`timescale 1ns/1ps
`default_nettype none

module tb_dma_axi_mem_router;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg [31:0] awaddr = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 32'h12345678;
    reg wvalid = 0;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 1;
    reg [31:0] araddr = 0;
    reg arvalid = 0;
    wire arready;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast, rvalid;
    reg rready = 1;

    wire l_awvalid, d_awvalid, l_wvalid, d_wvalid;
    wire [31:0] l_awaddr, d_awaddr;
    wire l_arvalid, d_arvalid;
    wire [31:0] l_araddr, d_araddr;
    reg l_bvalid = 0, d_bvalid = 0;
    reg l_rvalid = 0, d_rvalid = 0;

    dma_axi_mem_router dut (
        .clk(clk), .rst(rst),
        .s_awid(4'ha), .s_awaddr(awaddr), .s_awlen(8'd0),
        .s_awsize(3'd2), .s_awburst(2'b01), .s_awlock(1'b0),
        .s_awcache(4'd0), .s_awprot(3'd0), .s_awqos(4'd0),
        .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(4'hf), .s_wlast(1'b1),
        .s_wvalid(wvalid), .s_wready(wready),
        .s_bid(bid), .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_arid(4'h5), .s_araddr(araddr), .s_arlen(8'd0),
        .s_arsize(3'd2), .s_arburst(2'b01), .s_arlock(1'b0),
        .s_arcache(4'd0), .s_arprot(3'd0), .s_arqos(4'd0),
        .s_arvalid(arvalid), .s_arready(arready),
        .s_rid(rid), .s_rdata(rdata), .s_rresp(rresp),
        .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready),

        .l_awaddr(l_awaddr), .l_awvalid(l_awvalid), .l_awready(1'b1),
        .l_wvalid(l_wvalid), .l_wready(1'b1),
        .l_bid(4'h1), .l_bresp(2'b00), .l_bvalid(l_bvalid),
        .l_araddr(l_araddr), .l_arvalid(l_arvalid), .l_arready(1'b1),
        .l_rid(4'h2), .l_rdata(32'h11112222), .l_rresp(2'b00),
        .l_rlast(1'b1), .l_rvalid(l_rvalid),

        .d_awaddr(d_awaddr), .d_awvalid(d_awvalid), .d_awready(1'b1),
        .d_wvalid(d_wvalid), .d_wready(1'b1),
        .d_bid(4'hb), .d_bresp(2'b00), .d_bvalid(d_bvalid),
        .d_araddr(d_araddr), .d_arvalid(d_arvalid), .d_arready(1'b1),
        .d_rid(4'hc), .d_rdata(32'ha5a55a5a), .d_rresp(2'b00),
        .d_rlast(1'b1), .d_rvalid(d_rvalid)
    );

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        // The SoC DDR aperture must become zero-based at the MIG port.
        awaddr = 32'h80001234;
        awvalid = 1;
        #1;
        if (!awready || !d_awvalid || l_awvalid || d_awaddr != 32'h00001234)
            $fatal(1, "DDR write address routing/translation failed");
        @(posedge clk);
        @(negedge clk);
        awvalid = 0;
        wvalid = 1;
        #1;
        if (!wready || !d_wvalid || l_wvalid)
            $fatal(1, "DDR write data routing failed");
        @(posedge clk);
        @(negedge clk);
        wvalid = 0;
        d_bvalid = 1;
        #1;
        if (!bvalid || bid != 4'hb || bresp != 2'b00)
            $fatal(1, "DDR write response routing failed");
        @(posedge clk);
        @(negedge clk);
        d_bvalid = 0;

        araddr = 32'h80005678;
        arvalid = 1;
        #1;
        if (!arready || !d_arvalid || l_arvalid || d_araddr != 32'h00005678)
            $fatal(1, "DDR read address routing/translation failed");
        @(posedge clk);
        @(negedge clk);
        arvalid = 0;
        d_rvalid = 1;
        #1;
        if (!rvalid || rid != 4'hc || rdata != 32'ha5a55a5a || !rlast)
            $fatal(1, "DDR read response routing failed");
        @(posedge clk);
        @(negedge clk);
        d_rvalid = 0;

        araddr = 32'h00020000;
        arvalid = 1;
        #1;
        if (!arready || !l_arvalid || d_arvalid || l_araddr != 32'h00020000)
            $fatal(1, "Local read routing failed");
        @(posedge clk);
        @(negedge clk);
        arvalid = 0;
        l_rvalid = 1;
        #1;
        if (!rvalid || rid != 4'h2 || rdata != 32'h11112222 || !rlast)
            $fatal(1, "Local read response routing failed");
        @(posedge clk);
        @(negedge clk);
        l_rvalid = 0;

        $display("DMA AXI LOCAL/DDR ROUTER TEST PASSED");
        $finish;
    end
endmodule

`resetall
