`timescale 1ns / 1ps

// VC707 external-memory bridge.
//
// The project SoC uses a 32-bit AXI4 interface at 150 MHz.  The VC707 MIG
// exposes a 512-bit AXI4 interface in its own UI clock domain.  The two AMD
// infrastructure IP blocks below preserve AXI transaction IDs while crossing
// the clock boundary and convert the data width before the request reaches
// the DDR3 controller.
module vc707_axi_ddr3_bridge (
    input  wire         sys_clk_p,
    input  wire         sys_clk_n,
    input  wire         sys_rst_i,

    input  wire         soc_clk_i,
    input  wire         soc_aresetn_i,

    input  wire [4:0]   s_axi_awid,
    input  wire [31:0]  s_axi_awaddr,
    input  wire [7:0]   s_axi_awlen,
    input  wire [2:0]   s_axi_awsize,
    input  wire [1:0]   s_axi_awburst,
    input  wire         s_axi_awlock,
    input  wire [3:0]   s_axi_awcache,
    input  wire [2:0]   s_axi_awprot,
    input  wire [3:0]   s_axi_awqos,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wlast,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [4:0]   s_axi_bid,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [4:0]   s_axi_arid,
    input  wire [31:0]  s_axi_araddr,
    input  wire [7:0]   s_axi_arlen,
    input  wire [2:0]   s_axi_arsize,
    input  wire [1:0]   s_axi_arburst,
    input  wire         s_axi_arlock,
    input  wire [3:0]   s_axi_arcache,
    input  wire [2:0]   s_axi_arprot,
    input  wire [3:0]   s_axi_arqos,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [4:0]   s_axi_rid,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rlast,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    output wire         ui_clk_o,
    output wire         ui_reset_o,
    output wire         init_calib_complete_o,

    inout  wire [63:0]  ddr3_dq,
    inout  wire [7:0]   ddr3_dqs_n,
    inout  wire [7:0]   ddr3_dqs_p,
    output wire [13:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,
    output wire         ddr3_ras_n,
    output wire         ddr3_cas_n,
    output wire         ddr3_we_n,
    output wire         ddr3_reset_n,
    output wire [0:0]   ddr3_ck_p,
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_cs_n,
    output wire [7:0]   ddr3_dm,
    output wire [0:0]   ddr3_odt
);

    wire ui_clk;
    wire ui_clk_sync_rst;
    wire ui_aresetn = ~ui_clk_sync_rst;
    assign ui_clk_o = ui_clk;
    assign ui_reset_o = ui_clk_sync_rst;

    // 32-bit AXI after the asynchronous clock-domain crossing.
    wire [4:0]  c_awid;
    wire [31:0] c_awaddr;
    wire [7:0]  c_awlen;
    wire [2:0]  c_awsize;
    wire [1:0]  c_awburst;
    wire        c_awlock;
    wire [3:0]  c_awcache;
    wire [2:0]  c_awprot;
    wire [3:0]  c_awregion;
    wire [3:0]  c_awqos;
    wire        c_awvalid, c_awready;
    wire [31:0] c_wdata;
    wire [3:0]  c_wstrb;
    wire        c_wlast, c_wvalid, c_wready;
    wire [4:0]  c_bid;
    wire [1:0]  c_bresp;
    wire        c_bvalid, c_bready;
    wire [4:0]  c_arid;
    wire [31:0] c_araddr;
    wire [7:0]  c_arlen;
    wire [2:0]  c_arsize;
    wire [1:0]  c_arburst;
    wire        c_arlock;
    wire [3:0]  c_arcache;
    wire [2:0]  c_arprot;
    wire [3:0]  c_arregion;
    wire [3:0]  c_arqos;
    wire        c_arvalid, c_arready;
    wire [4:0]  c_rid;
    wire [31:0] c_rdata;
    wire [1:0]  c_rresp;
    wire        c_rlast, c_rvalid, c_rready;

    vc707_axi_clock_converter clock_converter_inst (
        .s_axi_aclk(soc_clk_i), .s_axi_aresetn(soc_aresetn_i),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen), .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst), .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache), .s_axi_awprot(s_axi_awprot),
        .s_axi_awregion(4'b0000), .s_axi_awqos(s_axi_awqos),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr), .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize), .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock), .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot), .s_axi_arregion(4'b0000),
        .s_axi_arqos(s_axi_arqos), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .m_axi_aclk(ui_clk), .m_axi_aresetn(ui_aresetn),
        .m_axi_awid(c_awid), .m_axi_awaddr(c_awaddr),
        .m_axi_awlen(c_awlen), .m_axi_awsize(c_awsize),
        .m_axi_awburst(c_awburst), .m_axi_awlock(c_awlock),
        .m_axi_awcache(c_awcache), .m_axi_awprot(c_awprot),
        .m_axi_awregion(c_awregion), .m_axi_awqos(c_awqos),
        .m_axi_awvalid(c_awvalid), .m_axi_awready(c_awready),
        .m_axi_wdata(c_wdata), .m_axi_wstrb(c_wstrb),
        .m_axi_wlast(c_wlast), .m_axi_wvalid(c_wvalid),
        .m_axi_wready(c_wready), .m_axi_bid(c_bid),
        .m_axi_bresp(c_bresp), .m_axi_bvalid(c_bvalid),
        .m_axi_bready(c_bready), .m_axi_arid(c_arid),
        .m_axi_araddr(c_araddr), .m_axi_arlen(c_arlen),
        .m_axi_arsize(c_arsize), .m_axi_arburst(c_arburst),
        .m_axi_arlock(c_arlock), .m_axi_arcache(c_arcache),
        .m_axi_arprot(c_arprot), .m_axi_arregion(c_arregion),
        .m_axi_arqos(c_arqos), .m_axi_arvalid(c_arvalid),
        .m_axi_arready(c_arready), .m_axi_rid(c_rid),
        .m_axi_rdata(c_rdata), .m_axi_rresp(c_rresp),
        .m_axi_rlast(c_rlast), .m_axi_rvalid(c_rvalid),
        .m_axi_rready(c_rready)
    );

    // 512-bit AXI feeding the native-width MIG slave interface.
    wire [31:0]  w_awaddr;
    wire [7:0]   w_awlen;
    wire [2:0]   w_awsize;
    wire [1:0]   w_awburst;
    wire         w_awlock;
    wire [3:0]   w_awcache;
    wire [2:0]   w_awprot;
    wire [3:0]   w_awregion;
    wire [3:0]   w_awqos;
    wire         w_awvalid, w_awready;
    wire [511:0] w_wdata;
    wire [63:0]  w_wstrb;
    wire         w_wlast, w_wvalid, w_wready;
    wire [1:0]   w_bresp;
    wire         w_bvalid, w_bready;
    wire [31:0]  w_araddr;
    wire [7:0]   w_arlen;
    wire [2:0]   w_arsize;
    wire [1:0]   w_arburst;
    wire         w_arlock;
    wire [3:0]   w_arcache;
    wire [2:0]   w_arprot;
    wire [3:0]   w_arregion;
    wire [3:0]   w_arqos;
    wire         w_arvalid, w_arready;
    wire [511:0] w_rdata;
    wire [1:0]   w_rresp;
    wire         w_rlast, w_rvalid, w_rready;

    vc707_axi_dwidth_converter width_converter_inst (
        .s_axi_aclk(ui_clk), .s_axi_aresetn(ui_aresetn),
        .s_axi_awid(c_awid), .s_axi_awaddr(c_awaddr),
        .s_axi_awlen(c_awlen), .s_axi_awsize(c_awsize),
        .s_axi_awburst(c_awburst), .s_axi_awlock(c_awlock),
        .s_axi_awcache(c_awcache), .s_axi_awprot(c_awprot),
        .s_axi_awregion(c_awregion), .s_axi_awqos(c_awqos),
        .s_axi_awvalid(c_awvalid), .s_axi_awready(c_awready),
        .s_axi_wdata(c_wdata), .s_axi_wstrb(c_wstrb),
        .s_axi_wlast(c_wlast), .s_axi_wvalid(c_wvalid),
        .s_axi_wready(c_wready), .s_axi_bid(c_bid),
        .s_axi_bresp(c_bresp), .s_axi_bvalid(c_bvalid),
        .s_axi_bready(c_bready), .s_axi_arid(c_arid),
        .s_axi_araddr(c_araddr), .s_axi_arlen(c_arlen),
        .s_axi_arsize(c_arsize), .s_axi_arburst(c_arburst),
        .s_axi_arlock(c_arlock), .s_axi_arcache(c_arcache),
        .s_axi_arprot(c_arprot), .s_axi_arregion(c_arregion),
        .s_axi_arqos(c_arqos), .s_axi_arvalid(c_arvalid),
        .s_axi_arready(c_arready), .s_axi_rid(c_rid),
        .s_axi_rdata(c_rdata), .s_axi_rresp(c_rresp),
        .s_axi_rlast(c_rlast), .s_axi_rvalid(c_rvalid),
        .s_axi_rready(c_rready),
        .m_axi_awaddr(w_awaddr), .m_axi_awlen(w_awlen),
        .m_axi_awsize(w_awsize), .m_axi_awburst(w_awburst),
        .m_axi_awlock(w_awlock), .m_axi_awcache(w_awcache),
        .m_axi_awprot(w_awprot), .m_axi_awregion(w_awregion),
        .m_axi_awqos(w_awqos), .m_axi_awvalid(w_awvalid),
        .m_axi_awready(w_awready), .m_axi_wdata(w_wdata),
        .m_axi_wstrb(w_wstrb), .m_axi_wlast(w_wlast),
        .m_axi_wvalid(w_wvalid), .m_axi_wready(w_wready),
        .m_axi_bresp(w_bresp), .m_axi_bvalid(w_bvalid),
        .m_axi_bready(w_bready), .m_axi_araddr(w_araddr),
        .m_axi_arlen(w_arlen), .m_axi_arsize(w_arsize),
        .m_axi_arburst(w_arburst), .m_axi_arlock(w_arlock),
        .m_axi_arcache(w_arcache), .m_axi_arprot(w_arprot),
        .m_axi_arregion(w_arregion), .m_axi_arqos(w_arqos),
        .m_axi_arvalid(w_arvalid), .m_axi_arready(w_arready),
        .m_axi_rdata(w_rdata), .m_axi_rresp(w_rresp),
        .m_axi_rlast(w_rlast), .m_axi_rvalid(w_rvalid),
        .m_axi_rready(w_rready)
    );

    wire [4:0] mig_bid_unused;
    wire [4:0] mig_rid_unused;
    wire [11:0] device_temp_unused;

    vc707_ddr3_mig mig_inst (
        .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p), .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba), .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n), .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n), .ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n), .ddr3_cke(ddr3_cke),
        .ddr3_cs_n(ddr3_cs_n), .ddr3_dm(ddr3_dm),
        .ddr3_odt(ddr3_odt), .sys_clk_p(sys_clk_p),
        .sys_clk_n(sys_clk_n), .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst), .ui_addn_clk_0(),
        .ui_addn_clk_1(), .ui_addn_clk_2(), .ui_addn_clk_3(),
        .ui_addn_clk_4(), .mmcm_locked(), .aresetn(~sys_rst_i),
        .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
        .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
        .s_axi_awid(5'b0), .s_axi_awaddr(w_awaddr),
        .s_axi_awlen(w_awlen), .s_axi_awsize(w_awsize),
        .s_axi_awburst(w_awburst), .s_axi_awlock(w_awlock),
        .s_axi_awcache(w_awcache), .s_axi_awprot(w_awprot),
        .s_axi_awqos(w_awqos), .s_axi_awvalid(w_awvalid),
        .s_axi_awready(w_awready), .s_axi_wdata(w_wdata),
        .s_axi_wstrb(w_wstrb), .s_axi_wlast(w_wlast),
        .s_axi_wvalid(w_wvalid), .s_axi_wready(w_wready),
        .s_axi_bready(w_bready), .s_axi_bid(mig_bid_unused),
        .s_axi_bresp(w_bresp), .s_axi_bvalid(w_bvalid),
        .s_axi_arid(5'b0), .s_axi_araddr(w_araddr),
        .s_axi_arlen(w_arlen), .s_axi_arsize(w_arsize),
        .s_axi_arburst(w_arburst), .s_axi_arlock(w_arlock),
        .s_axi_arcache(w_arcache), .s_axi_arprot(w_arprot),
        .s_axi_arqos(w_arqos), .s_axi_arvalid(w_arvalid),
        .s_axi_arready(w_arready), .s_axi_rready(w_rready),
        .s_axi_rid(mig_rid_unused), .s_axi_rdata(w_rdata),
        .s_axi_rresp(w_rresp), .s_axi_rlast(w_rlast),
        .s_axi_rvalid(w_rvalid), .init_calib_complete(init_calib_complete_o),
        .device_temp(device_temp_unused), .sys_rst(sys_rst_i)
    );

endmodule
