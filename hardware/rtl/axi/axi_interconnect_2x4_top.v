`timescale 1ns / 1ps
`default_nettype none

module axi_interconnect_2x4_top #
(
    parameter S_COUNT          = 2,
    parameter M_COUNT          = 4,
    parameter AXI_ADDR_WIDTH   = 32,
    parameter DATA_WIDTH       = 32,
    parameter STRB_WIDTH       = (DATA_WIDTH/8),
    parameter ID_WIDTH         = 4,
    parameter SLAVE_ADDR_WIDTH = 16,
    parameter RAM0_INIT_FILE   = "program_imem.mem"
)
(
    input  wire                         clk,
    input  wire                         rst,

    // AXI MASTER 0 INPUT
    input  wire [ID_WIDTH-1:0]          m0_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]    m0_axi_awaddr,
    input  wire [7:0]                   m0_axi_awlen,
    input  wire [2:0]                   m0_axi_awsize,
    input  wire [1:0]                   m0_axi_awburst,
    input  wire                         m0_axi_awlock,
    input  wire [3:0]                   m0_axi_awcache,
    input  wire [2:0]                   m0_axi_awprot,
    input  wire                         m0_axi_awvalid,
    output wire                         m0_axi_awready,

    input  wire [DATA_WIDTH-1:0]        m0_axi_wdata,
    input  wire [STRB_WIDTH-1:0]        m0_axi_wstrb,
    input  wire                         m0_axi_wlast,
    input  wire                         m0_axi_wvalid,
    output wire                         m0_axi_wready,

    output wire [ID_WIDTH-1:0]          m0_axi_bid,
    output wire [1:0]                   m0_axi_bresp,
    output wire                         m0_axi_bvalid,
    input  wire                         m0_axi_bready,

    input  wire [ID_WIDTH-1:0]          m0_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]    m0_axi_araddr,
    input  wire [7:0]                   m0_axi_arlen,
    input  wire [2:0]                   m0_axi_arsize,
    input  wire [1:0]                   m0_axi_arburst,
    input  wire                         m0_axi_arlock,
    input  wire [3:0]                   m0_axi_arcache,
    input  wire [2:0]                   m0_axi_arprot,
    input  wire                         m0_axi_arvalid,
    output wire                         m0_axi_arready,

    output wire [ID_WIDTH-1:0]          m0_axi_rid,
    output wire [DATA_WIDTH-1:0]        m0_axi_rdata,
    output wire [1:0]                   m0_axi_rresp,
    output wire                         m0_axi_rlast,
    output wire                         m0_axi_rvalid,
    input  wire                         m0_axi_rready,

    // AXI MASTER 1 INPUT
    input  wire [ID_WIDTH-1:0]          m1_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]    m1_axi_awaddr,
    input  wire [7:0]                   m1_axi_awlen,
    input  wire [2:0]                   m1_axi_awsize,
    input  wire [1:0]                   m1_axi_awburst,
    input  wire                         m1_axi_awlock,
    input  wire [3:0]                   m1_axi_awcache,
    input  wire [2:0]                   m1_axi_awprot,
    input  wire                         m1_axi_awvalid,
    output wire                         m1_axi_awready,

    input  wire [DATA_WIDTH-1:0]        m1_axi_wdata,
    input  wire [STRB_WIDTH-1:0]        m1_axi_wstrb,
    input  wire                         m1_axi_wlast,
    input  wire                         m1_axi_wvalid,
    output wire                         m1_axi_wready,

    output wire [ID_WIDTH-1:0]          m1_axi_bid,
    output wire [1:0]                   m1_axi_bresp,
    output wire                         m1_axi_bvalid,
    input  wire                         m1_axi_bready,

    input  wire [ID_WIDTH-1:0]          m1_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]    m1_axi_araddr,
    input  wire [7:0]                   m1_axi_arlen,
    input  wire [2:0]                   m1_axi_arsize,
    input  wire [1:0]                   m1_axi_arburst,
    input  wire                         m1_axi_arlock,
    input  wire [3:0]                   m1_axi_arcache,
    input  wire [2:0]                   m1_axi_arprot,
    input  wire                         m1_axi_arvalid,
    output wire                         m1_axi_arready,

    output wire [ID_WIDTH-1:0]          m1_axi_rid,
    output wire [DATA_WIDTH-1:0]        m1_axi_rdata,
    output wire [1:0]                   m1_axi_rresp,
    output wire                         m1_axi_rlast,
    output wire                         m1_axi_rvalid,
    input  wire                         m1_axi_rready,

    // Slave 3 port exposed for DMA
    output wire [ID_WIDTH-1:0]          s3_axi_awid,
    output wire [SLAVE_ADDR_WIDTH-1:0]  s3_axi_awaddr,
    output wire [7:0]                   s3_axi_awlen,
    output wire [2:0]                   s3_axi_awsize,
    output wire [1:0]                   s3_axi_awburst,
    output wire                         s3_axi_awlock,
    output wire [3:0]                   s3_axi_awcache,
    output wire [2:0]                   s3_axi_awprot,
    output wire                         s3_axi_awvalid,
    input  wire                         s3_axi_awready,

    output wire [DATA_WIDTH-1:0]        s3_axi_wdata,
    output wire [STRB_WIDTH-1:0]        s3_axi_wstrb,
    output wire                         s3_axi_wlast,
    output wire                         s3_axi_wvalid,
    input  wire                         s3_axi_wready,

    input  wire [ID_WIDTH-1:0]          s3_axi_bid,
    input  wire [1:0]                   s3_axi_bresp,
    input  wire                         s3_axi_bvalid,
    output wire                         s3_axi_bready,

    output wire [ID_WIDTH-1:0]          s3_axi_arid,
    output wire [SLAVE_ADDR_WIDTH-1:0]  s3_axi_araddr,
    output wire [7:0]                   s3_axi_arlen,
    output wire [2:0]                   s3_axi_arsize,
    output wire [1:0]                   s3_axi_arburst,
    output wire                         s3_axi_arlock,
    output wire [3:0]                   s3_axi_arcache,
    output wire [2:0]                   s3_axi_arprot,
    output wire                         s3_axi_arvalid,
    input  wire                         s3_axi_arready,

    input  wire [ID_WIDTH-1:0]          s3_axi_rid,
    input  wire [DATA_WIDTH-1:0]        s3_axi_rdata,
    input  wire [1:0]                   s3_axi_rresp,
    input  wire                         s3_axi_rlast,
    input  wire                         s3_axi_rvalid,
    output wire                         s3_axi_rready
);

    localparam integer USER_WIDTH = 1;
    localparam integer M0_SLOT = 0;
    localparam integer M1_SLOT = 1;
    localparam integer M2_SLOT = 2;
    localparam integer M3_SLOT = 3;
    localparam integer OUT_ID_WIDTH = ID_WIDTH+$clog2(S_COUNT);

    localparam [M_COUNT*32-1:0] M_ADDR_WIDTH_CFG = {
        32'd16, 32'd16, 32'd16, 32'd16
    };
    localparam [M_COUNT*AXI_ADDR_WIDTH-1:0] M_BASE_ADDR_CFG = {
        32'h0003_0000, 32'h0002_0000, 32'h0001_0000, 32'h0000_0000
    };

    // Fixed architecture of this top
    initial begin
        if (S_COUNT != 2 || M_COUNT != 4) begin
            $error("axi_interconnect_2x4_top expects S_COUNT=2 and M_COUNT=4");
        end
    end

    // S-side packed wires
    wire [S_COUNT*ID_WIDTH-1:0]       s_axi_awid_bus;
    wire [S_COUNT*AXI_ADDR_WIDTH-1:0] s_axi_awaddr_bus;
    wire [S_COUNT*8-1:0]              s_axi_awlen_bus;
    wire [S_COUNT*3-1:0]              s_axi_awsize_bus;
    wire [S_COUNT*2-1:0]              s_axi_awburst_bus;
    wire [S_COUNT-1:0]                s_axi_awlock_bus;
    wire [S_COUNT*4-1:0]              s_axi_awcache_bus;
    wire [S_COUNT*3-1:0]              s_axi_awprot_bus;
    wire [S_COUNT*4-1:0]              s_axi_awqos_bus;
    wire [S_COUNT*USER_WIDTH-1:0]     s_axi_awuser_bus;
    wire [S_COUNT-1:0]                s_axi_awvalid_bus;
    wire [S_COUNT-1:0]                s_axi_awready_bus;
    wire [S_COUNT*DATA_WIDTH-1:0]     s_axi_wdata_bus;
    wire [S_COUNT*STRB_WIDTH-1:0]     s_axi_wstrb_bus;
    wire [S_COUNT-1:0]                s_axi_wlast_bus;
    wire [S_COUNT*USER_WIDTH-1:0]     s_axi_wuser_bus;
    wire [S_COUNT-1:0]                s_axi_wvalid_bus;
    wire [S_COUNT-1:0]                s_axi_wready_bus;
    wire [S_COUNT*ID_WIDTH-1:0]       s_axi_bid_bus;
    wire [S_COUNT*2-1:0]              s_axi_bresp_bus;
    wire [S_COUNT*USER_WIDTH-1:0]     s_axi_buser_bus;
    wire [S_COUNT-1:0]                s_axi_bvalid_bus;
    wire [S_COUNT-1:0]                s_axi_bready_bus;
    wire [S_COUNT*ID_WIDTH-1:0]       s_axi_arid_bus;
    wire [S_COUNT*AXI_ADDR_WIDTH-1:0] s_axi_araddr_bus;
    wire [S_COUNT*8-1:0]              s_axi_arlen_bus;
    wire [S_COUNT*3-1:0]              s_axi_arsize_bus;
    wire [S_COUNT*2-1:0]              s_axi_arburst_bus;
    wire [S_COUNT-1:0]                s_axi_arlock_bus;
    wire [S_COUNT*4-1:0]              s_axi_arcache_bus;
    wire [S_COUNT*3-1:0]              s_axi_arprot_bus;
    wire [S_COUNT*4-1:0]              s_axi_arqos_bus;
    wire [S_COUNT*USER_WIDTH-1:0]     s_axi_aruser_bus;
    wire [S_COUNT-1:0]                s_axi_arvalid_bus;
    wire [S_COUNT-1:0]                s_axi_arready_bus;
    wire [S_COUNT*ID_WIDTH-1:0]       s_axi_rid_bus;
    wire [S_COUNT*DATA_WIDTH-1:0]     s_axi_rdata_bus;
    wire [S_COUNT*2-1:0]              s_axi_rresp_bus;
    wire [S_COUNT-1:0]                s_axi_rlast_bus;
    wire [S_COUNT*USER_WIDTH-1:0]     s_axi_ruser_bus;
    wire [S_COUNT-1:0]                s_axi_rvalid_bus;
    wire [S_COUNT-1:0]                s_axi_rready_bus;

    // M-side packed wires
    wire [M_COUNT*OUT_ID_WIDTH-1:0]   m_axi_awid_bus;
    wire [M_COUNT*AXI_ADDR_WIDTH-1:0] m_axi_awaddr_bus;
    wire [M_COUNT*8-1:0]              m_axi_awlen_bus;
    wire [M_COUNT*3-1:0]              m_axi_awsize_bus;
    wire [M_COUNT*2-1:0]              m_axi_awburst_bus;
    wire [M_COUNT-1:0]                m_axi_awlock_bus;
    wire [M_COUNT*4-1:0]              m_axi_awcache_bus;
    wire [M_COUNT*3-1:0]              m_axi_awprot_bus;
    wire [M_COUNT*4-1:0]              m_axi_awqos_bus;
    wire [M_COUNT*4-1:0]              m_axi_awregion_bus;
    wire [M_COUNT*USER_WIDTH-1:0]     m_axi_awuser_bus;
    wire [M_COUNT-1:0]                m_axi_awvalid_bus;
    wire [M_COUNT-1:0]                m_axi_awready_bus;
    wire [M_COUNT*DATA_WIDTH-1:0]     m_axi_wdata_bus;
    wire [M_COUNT*STRB_WIDTH-1:0]     m_axi_wstrb_bus;
    wire [M_COUNT-1:0]                m_axi_wlast_bus;
    wire [M_COUNT*USER_WIDTH-1:0]     m_axi_wuser_bus;
    wire [M_COUNT-1:0]                m_axi_wvalid_bus;
    wire [M_COUNT-1:0]                m_axi_wready_bus;
    wire [M_COUNT*OUT_ID_WIDTH-1:0]   m_axi_bid_bus;
    wire [M_COUNT*2-1:0]              m_axi_bresp_bus;
    wire [M_COUNT*USER_WIDTH-1:0]     m_axi_buser_bus;
    wire [M_COUNT-1:0]                m_axi_bvalid_bus;
    wire [M_COUNT-1:0]                m_axi_bready_bus;
    wire [M_COUNT*OUT_ID_WIDTH-1:0]   m_axi_arid_bus;
    wire [M_COUNT*AXI_ADDR_WIDTH-1:0] m_axi_araddr_bus;
    wire [M_COUNT*8-1:0]              m_axi_arlen_bus;
    wire [M_COUNT*3-1:0]              m_axi_arsize_bus;
    wire [M_COUNT*2-1:0]              m_axi_arburst_bus;
    wire [M_COUNT-1:0]                m_axi_arlock_bus;
    wire [M_COUNT*4-1:0]              m_axi_arcache_bus;
    wire [M_COUNT*3-1:0]              m_axi_arprot_bus;
    wire [M_COUNT*4-1:0]              m_axi_arqos_bus;
    wire [M_COUNT*4-1:0]              m_axi_arregion_bus;
    wire [M_COUNT*USER_WIDTH-1:0]     m_axi_aruser_bus;
    wire [M_COUNT-1:0]                m_axi_arvalid_bus;
    wire [M_COUNT-1:0]                m_axi_arready_bus;
    wire [M_COUNT*OUT_ID_WIDTH-1:0]   m_axi_rid_bus;
    wire [M_COUNT*DATA_WIDTH-1:0]     m_axi_rdata_bus;
    wire [M_COUNT*2-1:0]              m_axi_rresp_bus;
    wire [M_COUNT-1:0]                m_axi_rlast_bus;
    wire [M_COUNT*USER_WIDTH-1:0]     m_axi_ruser_bus;
    wire [M_COUNT-1:0]                m_axi_rvalid_bus;
    wire [M_COUNT-1:0]                m_axi_rready_bus;

    // ========= Slave input packing (m0, m1) =========
    assign s_axi_awid_bus[0*ID_WIDTH +: ID_WIDTH]         = m0_axi_awid;
    assign s_axi_awaddr_bus[0*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] = m0_axi_awaddr;
    assign s_axi_awlen_bus[0*8 +: 8]                      = m0_axi_awlen;
    assign s_axi_awsize_bus[0*3 +: 3]                     = m0_axi_awsize;
    assign s_axi_awburst_bus[0*2 +: 2]                    = m0_axi_awburst;
    assign s_axi_awlock_bus[0]                            = m0_axi_awlock;
    assign s_axi_awcache_bus[0*4 +: 4]                    = m0_axi_awcache;
    assign s_axi_awprot_bus[0*3 +: 3]                     = m0_axi_awprot;
    assign s_axi_awvalid_bus[0]                           = m0_axi_awvalid;
    assign s_axi_wdata_bus[0*DATA_WIDTH +: DATA_WIDTH]    = m0_axi_wdata;
    assign s_axi_wstrb_bus[0*STRB_WIDTH +: STRB_WIDTH]    = m0_axi_wstrb;
    assign s_axi_wlast_bus[0]                             = m0_axi_wlast;
    assign s_axi_wvalid_bus[0]                            = m0_axi_wvalid;
    assign s_axi_bready_bus[0]                            = m0_axi_bready;
    assign s_axi_arid_bus[0*ID_WIDTH +: ID_WIDTH]         = m0_axi_arid;
    assign s_axi_araddr_bus[0*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] = m0_axi_araddr;
    assign s_axi_arlen_bus[0*8 +: 8]                      = m0_axi_arlen;
    assign s_axi_arsize_bus[0*3 +: 3]                     = m0_axi_arsize;
    assign s_axi_arburst_bus[0*2 +: 2]                    = m0_axi_arburst;
    assign s_axi_arlock_bus[0]                            = m0_axi_arlock;
    assign s_axi_arcache_bus[0*4 +: 4]                    = m0_axi_arcache;
    assign s_axi_arprot_bus[0*3 +: 3]                     = m0_axi_arprot;
    assign s_axi_arvalid_bus[0]                           = m0_axi_arvalid;
    assign s_axi_rready_bus[0]                            = m0_axi_rready;

    assign s_axi_awid_bus[1*ID_WIDTH +: ID_WIDTH]         = m1_axi_awid;
    assign s_axi_awaddr_bus[1*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] = m1_axi_awaddr;
    assign s_axi_awlen_bus[1*8 +: 8]                      = m1_axi_awlen;
    assign s_axi_awsize_bus[1*3 +: 3]                     = m1_axi_awsize;
    assign s_axi_awburst_bus[1*2 +: 2]                    = m1_axi_awburst;
    assign s_axi_awlock_bus[1]                            = m1_axi_awlock;
    assign s_axi_awcache_bus[1*4 +: 4]                    = m1_axi_awcache;
    assign s_axi_awprot_bus[1*3 +: 3]                     = m1_axi_awprot;
    assign s_axi_awvalid_bus[1]                           = m1_axi_awvalid;
    assign s_axi_wdata_bus[1*DATA_WIDTH +: DATA_WIDTH]    = m1_axi_wdata;
    assign s_axi_wstrb_bus[1*STRB_WIDTH +: STRB_WIDTH]    = m1_axi_wstrb;
    assign s_axi_wlast_bus[1]                             = m1_axi_wlast;
    assign s_axi_wvalid_bus[1]                            = m1_axi_wvalid;
    assign s_axi_bready_bus[1]                            = m1_axi_bready;
    assign s_axi_arid_bus[1*ID_WIDTH +: ID_WIDTH]         = m1_axi_arid;
    assign s_axi_araddr_bus[1*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] = m1_axi_araddr;
    assign s_axi_arlen_bus[1*8 +: 8]                      = m1_axi_arlen;
    assign s_axi_arsize_bus[1*3 +: 3]                     = m1_axi_arsize;
    assign s_axi_arburst_bus[1*2 +: 2]                    = m1_axi_arburst;
    assign s_axi_arlock_bus[1]                            = m1_axi_arlock;
    assign s_axi_arcache_bus[1*4 +: 4]                    = m1_axi_arcache;
    assign s_axi_arprot_bus[1*3 +: 3]                     = m1_axi_arprot;
    assign s_axi_arvalid_bus[1]                           = m1_axi_arvalid;
    assign s_axi_rready_bus[1]                            = m1_axi_rready;

    // Unused sidebands
    assign s_axi_awqos_bus  = {S_COUNT*4{1'b0}};
    assign s_axi_awuser_bus = {S_COUNT*USER_WIDTH{1'b0}};
    assign s_axi_wuser_bus  = {S_COUNT*USER_WIDTH{1'b0}};
    assign s_axi_arqos_bus  = {S_COUNT*4{1'b0}};
    assign s_axi_aruser_bus = {S_COUNT*USER_WIDTH{1'b0}};

    // ========= Slave response unpacking (to m0, m1) =========
    assign m0_axi_awready = s_axi_awready_bus[0];
    assign m0_axi_wready  = s_axi_wready_bus[0];
    assign m0_axi_bid     = s_axi_bid_bus[0*ID_WIDTH +: ID_WIDTH];
    assign m0_axi_bresp   = s_axi_bresp_bus[0*2 +: 2];
    assign m0_axi_bvalid  = s_axi_bvalid_bus[0];
    assign m0_axi_arready = s_axi_arready_bus[0];
    assign m0_axi_rid     = s_axi_rid_bus[0*ID_WIDTH +: ID_WIDTH];
    assign m0_axi_rdata   = s_axi_rdata_bus[0*DATA_WIDTH +: DATA_WIDTH];
    assign m0_axi_rresp   = s_axi_rresp_bus[0*2 +: 2];
    assign m0_axi_rlast   = s_axi_rlast_bus[0];
    assign m0_axi_rvalid  = s_axi_rvalid_bus[0];

    assign m1_axi_awready = s_axi_awready_bus[1];
    assign m1_axi_wready  = s_axi_wready_bus[1];
    assign m1_axi_bid     = s_axi_bid_bus[1*ID_WIDTH +: ID_WIDTH];
    assign m1_axi_bresp   = s_axi_bresp_bus[1*2 +: 2];
    assign m1_axi_bvalid  = s_axi_bvalid_bus[1];
    assign m1_axi_arready = s_axi_arready_bus[1];
    assign m1_axi_rid     = s_axi_rid_bus[1*ID_WIDTH +: ID_WIDTH];
    assign m1_axi_rdata   = s_axi_rdata_bus[1*DATA_WIDTH +: DATA_WIDTH];
    assign m1_axi_rresp   = s_axi_rresp_bus[1*2 +: 2];
    assign m1_axi_rlast   = s_axi_rlast_bus[1];
    assign m1_axi_rvalid  = s_axi_rvalid_bus[1];

    // Full read/write crossbar.  Unlike the older shared interconnect, this
    // permits a DMA copy engine to issue AR and AW independently; serializing
    // those channels deadlocks a CDMA that waits for read data before W data.
    axi_crossbar #(
        .S_COUNT(S_COUNT),
        .M_COUNT(M_COUNT),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .S_ID_WIDTH(ID_WIDTH),
        .M_ID_WIDTH(OUT_ID_WIDTH),
        .AWUSER_ENABLE(0), .AWUSER_WIDTH(USER_WIDTH),
        .WUSER_ENABLE(0), .WUSER_WIDTH(USER_WIDTH),
        .BUSER_ENABLE(0), .BUSER_WIDTH(USER_WIDTH),
        .ARUSER_ENABLE(0), .ARUSER_WIDTH(USER_WIDTH),
        .RUSER_ENABLE(0), .RUSER_WIDTH(USER_WIDTH),
        .M_REGIONS(1),
        .M_BASE_ADDR(M_BASE_ADDR_CFG),
        .M_ADDR_WIDTH(M_ADDR_WIDTH_CFG),
        .M_CONNECT_READ(8'b01_11_11_11),
        .M_CONNECT_WRITE(8'b01_11_11_11)
    ) interconnect_ip_inst (
        .clk(clk),
        .rst(rst),
        .s_axi_awid(s_axi_awid_bus),
        .s_axi_awaddr(s_axi_awaddr_bus),
        .s_axi_awlen(s_axi_awlen_bus),
        .s_axi_awsize(s_axi_awsize_bus),
        .s_axi_awburst(s_axi_awburst_bus),
        .s_axi_awlock(s_axi_awlock_bus),
        .s_axi_awcache(s_axi_awcache_bus),
        .s_axi_awprot(s_axi_awprot_bus),
        .s_axi_awqos(s_axi_awqos_bus),
        .s_axi_awuser(s_axi_awuser_bus),
        .s_axi_awvalid(s_axi_awvalid_bus),
        .s_axi_awready(s_axi_awready_bus),
        .s_axi_wdata(s_axi_wdata_bus),
        .s_axi_wstrb(s_axi_wstrb_bus),
        .s_axi_wlast(s_axi_wlast_bus),
        .s_axi_wuser(s_axi_wuser_bus),
        .s_axi_wvalid(s_axi_wvalid_bus),
        .s_axi_wready(s_axi_wready_bus),
        .s_axi_bid(s_axi_bid_bus),
        .s_axi_bresp(s_axi_bresp_bus),
        .s_axi_buser(s_axi_buser_bus),
        .s_axi_bvalid(s_axi_bvalid_bus),
        .s_axi_bready(s_axi_bready_bus),
        .s_axi_arid(s_axi_arid_bus),
        .s_axi_araddr(s_axi_araddr_bus),
        .s_axi_arlen(s_axi_arlen_bus),
        .s_axi_arsize(s_axi_arsize_bus),
        .s_axi_arburst(s_axi_arburst_bus),
        .s_axi_arlock(s_axi_arlock_bus),
        .s_axi_arcache(s_axi_arcache_bus),
        .s_axi_arprot(s_axi_arprot_bus),
        .s_axi_arqos(s_axi_arqos_bus),
        .s_axi_aruser(s_axi_aruser_bus),
        .s_axi_arvalid(s_axi_arvalid_bus),
        .s_axi_arready(s_axi_arready_bus),
        .s_axi_rid(s_axi_rid_bus),
        .s_axi_rdata(s_axi_rdata_bus),
        .s_axi_rresp(s_axi_rresp_bus),
        .s_axi_rlast(s_axi_rlast_bus),
        .s_axi_ruser(s_axi_ruser_bus),
        .s_axi_rvalid(s_axi_rvalid_bus),
        .s_axi_rready(s_axi_rready_bus),
        .m_axi_awid(m_axi_awid_bus),
        .m_axi_awaddr(m_axi_awaddr_bus),
        .m_axi_awlen(m_axi_awlen_bus),
        .m_axi_awsize(m_axi_awsize_bus),
        .m_axi_awburst(m_axi_awburst_bus),
        .m_axi_awlock(m_axi_awlock_bus),
        .m_axi_awcache(m_axi_awcache_bus),
        .m_axi_awprot(m_axi_awprot_bus),
        .m_axi_awqos(m_axi_awqos_bus),
        .m_axi_awregion(m_axi_awregion_bus),
        .m_axi_awuser(m_axi_awuser_bus),
        .m_axi_awvalid(m_axi_awvalid_bus),
        .m_axi_awready(m_axi_awready_bus),
        .m_axi_wdata(m_axi_wdata_bus),
        .m_axi_wstrb(m_axi_wstrb_bus),
        .m_axi_wlast(m_axi_wlast_bus),
        .m_axi_wuser(m_axi_wuser_bus),
        .m_axi_wvalid(m_axi_wvalid_bus),
        .m_axi_wready(m_axi_wready_bus),
        .m_axi_bid(m_axi_bid_bus),
        .m_axi_bresp(m_axi_bresp_bus),
        .m_axi_buser(m_axi_buser_bus),
        .m_axi_bvalid(m_axi_bvalid_bus),
        .m_axi_bready(m_axi_bready_bus),
        .m_axi_arid(m_axi_arid_bus),
        .m_axi_araddr(m_axi_araddr_bus),
        .m_axi_arlen(m_axi_arlen_bus),
        .m_axi_arsize(m_axi_arsize_bus),
        .m_axi_arburst(m_axi_arburst_bus),
        .m_axi_arlock(m_axi_arlock_bus),
        .m_axi_arcache(m_axi_arcache_bus),
        .m_axi_arprot(m_axi_arprot_bus),
        .m_axi_arqos(m_axi_arqos_bus),
        .m_axi_arregion(m_axi_arregion_bus),
        .m_axi_aruser(m_axi_aruser_bus),
        .m_axi_arvalid(m_axi_arvalid_bus),
        .m_axi_arready(m_axi_arready_bus),
        .m_axi_rid(m_axi_rid_bus),
        .m_axi_rdata(m_axi_rdata_bus),
        .m_axi_rresp(m_axi_rresp_bus),
        .m_axi_rlast(m_axi_rlast_bus),
        .m_axi_ruser(m_axi_ruser_bus),
        .m_axi_rvalid(m_axi_rvalid_bus),
        .m_axi_rready(m_axi_rready_bus)
    );

    /*
    // =========================================================================
    // Alternative (legacy): bd_ic_2x4_wrapper
    // Use this only when needed:
    //   1) comment current "axi_interconnect interconnect_ip_inst" block above
    //   2) uncomment this block below
    //
    // IMPORTANT when switching to BD wrapper:
    //   - BD wrapper in this project uses 2-bit AXI ID.
    //   - Add localparam BD_ID_WIDTH = 2 and slice ID ports:
    //       [.. +: ID_WIDTH]  ->  [.. +: BD_ID_WIDTH]  (all awid/arid/bid/rid)
    //   - If your external ports remain ID_WIDTH=4, pad response IDs back:
    //       { {(ID_WIDTH-BD_ID_WIDTH){1'b0}}, bid_2b }
    //   - Keep only ONE active instance named interconnect_ip_inst.
    // =========================================================================
    bd_ic_2x4_wrapper interconnect_ip_inst (
        .ACLK_0(clk),
        .ARESETN_0(~rst),

        .S00_AXI_0_awid   (s_axi_awid_bus[0*ID_WIDTH +: ID_WIDTH]),
        .S00_AXI_0_awaddr (s_axi_awaddr_bus[0*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .S00_AXI_0_awlen  (s_axi_awlen_bus[0*8 +: 8]),
        .S00_AXI_0_awsize (s_axi_awsize_bus[0*3 +: 3]),
        .S00_AXI_0_awburst(s_axi_awburst_bus[0*2 +: 2]),
        .S00_AXI_0_awlock (s_axi_awlock_bus[0]),
        .S00_AXI_0_awcache(s_axi_awcache_bus[0*4 +: 4]),
        .S00_AXI_0_awprot (s_axi_awprot_bus[0*3 +: 3]),
        .S00_AXI_0_awqos  (s_axi_awqos_bus[0*4 +: 4]),
        .S00_AXI_0_awvalid(s_axi_awvalid_bus[0]),
        .S00_AXI_0_awready(s_axi_awready_bus[0]),
        .S00_AXI_0_wdata  (s_axi_wdata_bus[0*DATA_WIDTH +: DATA_WIDTH]),
        .S00_AXI_0_wstrb  (s_axi_wstrb_bus[0*STRB_WIDTH +: STRB_WIDTH]),
        .S00_AXI_0_wlast  (s_axi_wlast_bus[0]),
        .S00_AXI_0_wvalid (s_axi_wvalid_bus[0]),
        .S00_AXI_0_wready (s_axi_wready_bus[0]),
        .S00_AXI_0_bid    (s_axi_bid_bus[0*ID_WIDTH +: ID_WIDTH]),
        .S00_AXI_0_bresp  (s_axi_bresp_bus[0*2 +: 2]),
        .S00_AXI_0_bvalid (s_axi_bvalid_bus[0]),
        .S00_AXI_0_bready (s_axi_bready_bus[0]),
        .S00_AXI_0_arid   (s_axi_arid_bus[0*ID_WIDTH +: ID_WIDTH]),
        .S00_AXI_0_araddr (s_axi_araddr_bus[0*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .S00_AXI_0_arlen  (s_axi_arlen_bus[0*8 +: 8]),
        .S00_AXI_0_arsize (s_axi_arsize_bus[0*3 +: 3]),
        .S00_AXI_0_arburst(s_axi_arburst_bus[0*2 +: 2]),
        .S00_AXI_0_arlock (s_axi_arlock_bus[0]),
        .S00_AXI_0_arcache(s_axi_arcache_bus[0*4 +: 4]),
        .S00_AXI_0_arprot (s_axi_arprot_bus[0*3 +: 3]),
        .S00_AXI_0_arqos  (s_axi_arqos_bus[0*4 +: 4]),
        .S00_AXI_0_arvalid(s_axi_arvalid_bus[0]),
        .S00_AXI_0_arready(s_axi_arready_bus[0]),
        .S00_AXI_0_rid    (s_axi_rid_bus[0*ID_WIDTH +: ID_WIDTH]),
        .S00_AXI_0_rdata  (s_axi_rdata_bus[0*DATA_WIDTH +: DATA_WIDTH]),
        .S00_AXI_0_rresp  (s_axi_rresp_bus[0*2 +: 2]),
        .S00_AXI_0_rlast  (s_axi_rlast_bus[0]),
        .S00_AXI_0_rvalid (s_axi_rvalid_bus[0]),
        .S00_AXI_0_rready (s_axi_rready_bus[0]),

        .S01_AXI_0_awid   (s_axi_awid_bus[1*ID_WIDTH +: ID_WIDTH]),
        .S01_AXI_0_awaddr (s_axi_awaddr_bus[1*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .S01_AXI_0_awlen  (s_axi_awlen_bus[1*8 +: 8]),
        .S01_AXI_0_awsize (s_axi_awsize_bus[1*3 +: 3]),
        .S01_AXI_0_awburst(s_axi_awburst_bus[1*2 +: 2]),
        .S01_AXI_0_awlock (s_axi_awlock_bus[1]),
        .S01_AXI_0_awcache(s_axi_awcache_bus[1*4 +: 4]),
        .S01_AXI_0_awprot (s_axi_awprot_bus[1*3 +: 3]),
        .S01_AXI_0_awqos  (s_axi_awqos_bus[1*4 +: 4]),
        .S01_AXI_0_awvalid(s_axi_awvalid_bus[1]),
        .S01_AXI_0_awready(s_axi_awready_bus[1]),
        .S01_AXI_0_wdata  (s_axi_wdata_bus[1*DATA_WIDTH +: DATA_WIDTH]),
        .S01_AXI_0_wstrb  (s_axi_wstrb_bus[1*STRB_WIDTH +: STRB_WIDTH]),
        .S01_AXI_0_wlast  (s_axi_wlast_bus[1]),
        .S01_AXI_0_wvalid (s_axi_wvalid_bus[1]),
        .S01_AXI_0_wready (s_axi_wready_bus[1]),
        .S01_AXI_0_bid    (s_axi_bid_bus[1*ID_WIDTH +: ID_WIDTH]),
        .S01_AXI_0_bresp  (s_axi_bresp_bus[1*2 +: 2]),
        .S01_AXI_0_bvalid (s_axi_bvalid_bus[1]),
        .S01_AXI_0_bready (s_axi_bready_bus[1]),
        .S01_AXI_0_arid   (s_axi_arid_bus[1*ID_WIDTH +: ID_WIDTH]),
        .S01_AXI_0_araddr (s_axi_araddr_bus[1*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .S01_AXI_0_arlen  (s_axi_arlen_bus[1*8 +: 8]),
        .S01_AXI_0_arsize (s_axi_arsize_bus[1*3 +: 3]),
        .S01_AXI_0_arburst(s_axi_arburst_bus[1*2 +: 2]),
        .S01_AXI_0_arlock (s_axi_arlock_bus[1]),
        .S01_AXI_0_arcache(s_axi_arcache_bus[1*4 +: 4]),
        .S01_AXI_0_arprot (s_axi_arprot_bus[1*3 +: 3]),
        .S01_AXI_0_arqos  (s_axi_arqos_bus[1*4 +: 4]),
        .S01_AXI_0_arvalid(s_axi_arvalid_bus[1]),
        .S01_AXI_0_arready(s_axi_arready_bus[1]),
        .S01_AXI_0_rid    (s_axi_rid_bus[1*ID_WIDTH +: ID_WIDTH]),
        .S01_AXI_0_rdata  (s_axi_rdata_bus[1*DATA_WIDTH +: DATA_WIDTH]),
        .S01_AXI_0_rresp  (s_axi_rresp_bus[1*2 +: 2]),
        .S01_AXI_0_rlast  (s_axi_rlast_bus[1]),
        .S01_AXI_0_rvalid (s_axi_rvalid_bus[1]),
        .S01_AXI_0_rready (s_axi_rready_bus[1]),

        .M00_AXI_0_awid    (m_axi_awid_bus[M0_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M00_AXI_0_awaddr  (m_axi_awaddr_bus[M0_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M00_AXI_0_awlen   (m_axi_awlen_bus[M0_SLOT*8 +: 8]),
        .M00_AXI_0_awsize  (m_axi_awsize_bus[M0_SLOT*3 +: 3]),
        .M00_AXI_0_awburst (m_axi_awburst_bus[M0_SLOT*2 +: 2]),
        .M00_AXI_0_awlock  (m_axi_awlock_bus[M0_SLOT]),
        .M00_AXI_0_awcache (m_axi_awcache_bus[M0_SLOT*4 +: 4]),
        .M00_AXI_0_awprot  (m_axi_awprot_bus[M0_SLOT*3 +: 3]),
        .M00_AXI_0_awqos   (m_axi_awqos_bus[M0_SLOT*4 +: 4]),
        .M00_AXI_0_awregion(m_axi_awregion_bus[M0_SLOT*4 +: 4]),
        .M00_AXI_0_awvalid (m_axi_awvalid_bus[M0_SLOT]),
        .M00_AXI_0_awready (m_axi_awready_bus[M0_SLOT]),
        .M00_AXI_0_wdata   (m_axi_wdata_bus[M0_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M00_AXI_0_wstrb   (m_axi_wstrb_bus[M0_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .M00_AXI_0_wlast   (m_axi_wlast_bus[M0_SLOT]),
        .M00_AXI_0_wvalid  (m_axi_wvalid_bus[M0_SLOT]),
        .M00_AXI_0_wready  (m_axi_wready_bus[M0_SLOT]),
        .M00_AXI_0_bid     (m_axi_bid_bus[M0_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M00_AXI_0_bresp   (m_axi_bresp_bus[M0_SLOT*2 +: 2]),
        .M00_AXI_0_bvalid  (m_axi_bvalid_bus[M0_SLOT]),
        .M00_AXI_0_bready  (m_axi_bready_bus[M0_SLOT]),
        .M00_AXI_0_arid    (m_axi_arid_bus[M0_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M00_AXI_0_araddr  (m_axi_araddr_bus[M0_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M00_AXI_0_arlen   (m_axi_arlen_bus[M0_SLOT*8 +: 8]),
        .M00_AXI_0_arsize  (m_axi_arsize_bus[M0_SLOT*3 +: 3]),
        .M00_AXI_0_arburst (m_axi_arburst_bus[M0_SLOT*2 +: 2]),
        .M00_AXI_0_arlock  (m_axi_arlock_bus[M0_SLOT]),
        .M00_AXI_0_arcache (m_axi_arcache_bus[M0_SLOT*4 +: 4]),
        .M00_AXI_0_arprot  (m_axi_arprot_bus[M0_SLOT*3 +: 3]),
        .M00_AXI_0_arqos   (m_axi_arqos_bus[M0_SLOT*4 +: 4]),
        .M00_AXI_0_arregion(m_axi_arregion_bus[M0_SLOT*4 +: 4]),
        .M00_AXI_0_arvalid (m_axi_arvalid_bus[M0_SLOT]),
        .M00_AXI_0_arready (m_axi_arready_bus[M0_SLOT]),
        .M00_AXI_0_rid     (m_axi_rid_bus[M0_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M00_AXI_0_rdata   (m_axi_rdata_bus[M0_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M00_AXI_0_rresp   (m_axi_rresp_bus[M0_SLOT*2 +: 2]),
        .M00_AXI_0_rlast   (m_axi_rlast_bus[M0_SLOT]),
        .M00_AXI_0_rvalid  (m_axi_rvalid_bus[M0_SLOT]),
        .M00_AXI_0_rready  (m_axi_rready_bus[M0_SLOT]),

        .M01_AXI_0_awid    (m_axi_awid_bus[M1_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M01_AXI_0_awaddr  (m_axi_awaddr_bus[M1_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M01_AXI_0_awlen   (m_axi_awlen_bus[M1_SLOT*8 +: 8]),
        .M01_AXI_0_awsize  (m_axi_awsize_bus[M1_SLOT*3 +: 3]),
        .M01_AXI_0_awburst (m_axi_awburst_bus[M1_SLOT*2 +: 2]),
        .M01_AXI_0_awlock  (m_axi_awlock_bus[M1_SLOT]),
        .M01_AXI_0_awcache (m_axi_awcache_bus[M1_SLOT*4 +: 4]),
        .M01_AXI_0_awprot  (m_axi_awprot_bus[M1_SLOT*3 +: 3]),
        .M01_AXI_0_awqos   (m_axi_awqos_bus[M1_SLOT*4 +: 4]),
        .M01_AXI_0_awregion(m_axi_awregion_bus[M1_SLOT*4 +: 4]),
        .M01_AXI_0_awvalid (m_axi_awvalid_bus[M1_SLOT]),
        .M01_AXI_0_awready (m_axi_awready_bus[M1_SLOT]),
        .M01_AXI_0_wdata   (m_axi_wdata_bus[M1_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M01_AXI_0_wstrb   (m_axi_wstrb_bus[M1_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .M01_AXI_0_wlast   (m_axi_wlast_bus[M1_SLOT]),
        .M01_AXI_0_wvalid  (m_axi_wvalid_bus[M1_SLOT]),
        .M01_AXI_0_wready  (m_axi_wready_bus[M1_SLOT]),
        .M01_AXI_0_bid     (m_axi_bid_bus[M1_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M01_AXI_0_bresp   (m_axi_bresp_bus[M1_SLOT*2 +: 2]),
        .M01_AXI_0_bvalid  (m_axi_bvalid_bus[M1_SLOT]),
        .M01_AXI_0_bready  (m_axi_bready_bus[M1_SLOT]),
        .M01_AXI_0_arid    (m_axi_arid_bus[M1_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M01_AXI_0_araddr  (m_axi_araddr_bus[M1_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M01_AXI_0_arlen   (m_axi_arlen_bus[M1_SLOT*8 +: 8]),
        .M01_AXI_0_arsize  (m_axi_arsize_bus[M1_SLOT*3 +: 3]),
        .M01_AXI_0_arburst (m_axi_arburst_bus[M1_SLOT*2 +: 2]),
        .M01_AXI_0_arlock  (m_axi_arlock_bus[M1_SLOT]),
        .M01_AXI_0_arcache (m_axi_arcache_bus[M1_SLOT*4 +: 4]),
        .M01_AXI_0_arprot  (m_axi_arprot_bus[M1_SLOT*3 +: 3]),
        .M01_AXI_0_arqos   (m_axi_arqos_bus[M1_SLOT*4 +: 4]),
        .M01_AXI_0_arregion(m_axi_arregion_bus[M1_SLOT*4 +: 4]),
        .M01_AXI_0_arvalid (m_axi_arvalid_bus[M1_SLOT]),
        .M01_AXI_0_arready (m_axi_arready_bus[M1_SLOT]),
        .M01_AXI_0_rid     (m_axi_rid_bus[M1_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M01_AXI_0_rdata   (m_axi_rdata_bus[M1_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M01_AXI_0_rresp   (m_axi_rresp_bus[M1_SLOT*2 +: 2]),
        .M01_AXI_0_rlast   (m_axi_rlast_bus[M1_SLOT]),
        .M01_AXI_0_rvalid  (m_axi_rvalid_bus[M1_SLOT]),
        .M01_AXI_0_rready  (m_axi_rready_bus[M1_SLOT]),

        .M02_AXI_0_awid    (m_axi_awid_bus[M2_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M02_AXI_0_awaddr  (m_axi_awaddr_bus[M2_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M02_AXI_0_awlen   (m_axi_awlen_bus[M2_SLOT*8 +: 8]),
        .M02_AXI_0_awsize  (m_axi_awsize_bus[M2_SLOT*3 +: 3]),
        .M02_AXI_0_awburst (m_axi_awburst_bus[M2_SLOT*2 +: 2]),
        .M02_AXI_0_awlock  (m_axi_awlock_bus[M2_SLOT]),
        .M02_AXI_0_awcache (m_axi_awcache_bus[M2_SLOT*4 +: 4]),
        .M02_AXI_0_awprot  (m_axi_awprot_bus[M2_SLOT*3 +: 3]),
        .M02_AXI_0_awqos   (m_axi_awqos_bus[M2_SLOT*4 +: 4]),
        .M02_AXI_0_awregion(m_axi_awregion_bus[M2_SLOT*4 +: 4]),
        .M02_AXI_0_awvalid (m_axi_awvalid_bus[M2_SLOT]),
        .M02_AXI_0_awready (m_axi_awready_bus[M2_SLOT]),
        .M02_AXI_0_wdata   (m_axi_wdata_bus[M2_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M02_AXI_0_wstrb   (m_axi_wstrb_bus[M2_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .M02_AXI_0_wlast   (m_axi_wlast_bus[M2_SLOT]),
        .M02_AXI_0_wvalid  (m_axi_wvalid_bus[M2_SLOT]),
        .M02_AXI_0_wready  (m_axi_wready_bus[M2_SLOT]),
        .M02_AXI_0_bid     (m_axi_bid_bus[M2_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M02_AXI_0_bresp   (m_axi_bresp_bus[M2_SLOT*2 +: 2]),
        .M02_AXI_0_bvalid  (m_axi_bvalid_bus[M2_SLOT]),
        .M02_AXI_0_bready  (m_axi_bready_bus[M2_SLOT]),
        .M02_AXI_0_arid    (m_axi_arid_bus[M2_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M02_AXI_0_araddr  (m_axi_araddr_bus[M2_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M02_AXI_0_arlen   (m_axi_arlen_bus[M2_SLOT*8 +: 8]),
        .M02_AXI_0_arsize  (m_axi_arsize_bus[M2_SLOT*3 +: 3]),
        .M02_AXI_0_arburst (m_axi_arburst_bus[M2_SLOT*2 +: 2]),
        .M02_AXI_0_arlock  (m_axi_arlock_bus[M2_SLOT]),
        .M02_AXI_0_arcache (m_axi_arcache_bus[M2_SLOT*4 +: 4]),
        .M02_AXI_0_arprot  (m_axi_arprot_bus[M2_SLOT*3 +: 3]),
        .M02_AXI_0_arqos   (m_axi_arqos_bus[M2_SLOT*4 +: 4]),
        .M02_AXI_0_arregion(m_axi_arregion_bus[M2_SLOT*4 +: 4]),
        .M02_AXI_0_arvalid (m_axi_arvalid_bus[M2_SLOT]),
        .M02_AXI_0_arready (m_axi_arready_bus[M2_SLOT]),
        .M02_AXI_0_rid     (m_axi_rid_bus[M2_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M02_AXI_0_rdata   (m_axi_rdata_bus[M2_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M02_AXI_0_rresp   (m_axi_rresp_bus[M2_SLOT*2 +: 2]),
        .M02_AXI_0_rlast   (m_axi_rlast_bus[M2_SLOT]),
        .M02_AXI_0_rvalid  (m_axi_rvalid_bus[M2_SLOT]),
        .M02_AXI_0_rready  (m_axi_rready_bus[M2_SLOT]),

        .M03_AXI_0_awid    (m_axi_awid_bus[M3_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M03_AXI_0_awaddr  (m_axi_awaddr_bus[M3_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M03_AXI_0_awlen   (m_axi_awlen_bus[M3_SLOT*8 +: 8]),
        .M03_AXI_0_awsize  (m_axi_awsize_bus[M3_SLOT*3 +: 3]),
        .M03_AXI_0_awburst (m_axi_awburst_bus[M3_SLOT*2 +: 2]),
        .M03_AXI_0_awlock  (m_axi_awlock_bus[M3_SLOT]),
        .M03_AXI_0_awcache (m_axi_awcache_bus[M3_SLOT*4 +: 4]),
        .M03_AXI_0_awprot  (m_axi_awprot_bus[M3_SLOT*3 +: 3]),
        .M03_AXI_0_awqos   (m_axi_awqos_bus[M3_SLOT*4 +: 4]),
        .M03_AXI_0_awregion(m_axi_awregion_bus[M3_SLOT*4 +: 4]),
        .M03_AXI_0_awvalid (m_axi_awvalid_bus[M3_SLOT]),
        .M03_AXI_0_awready (m_axi_awready_bus[M3_SLOT]),
        .M03_AXI_0_wdata   (m_axi_wdata_bus[M3_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M03_AXI_0_wstrb   (m_axi_wstrb_bus[M3_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .M03_AXI_0_wlast   (m_axi_wlast_bus[M3_SLOT]),
        .M03_AXI_0_wvalid  (m_axi_wvalid_bus[M3_SLOT]),
        .M03_AXI_0_wready  (m_axi_wready_bus[M3_SLOT]),
        .M03_AXI_0_bid     (m_axi_bid_bus[M3_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M03_AXI_0_bresp   (m_axi_bresp_bus[M3_SLOT*2 +: 2]),
        .M03_AXI_0_bvalid  (m_axi_bvalid_bus[M3_SLOT]),
        .M03_AXI_0_bready  (m_axi_bready_bus[M3_SLOT]),
        .M03_AXI_0_arid    (m_axi_arid_bus[M3_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M03_AXI_0_araddr  (m_axi_araddr_bus[M3_SLOT*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
        .M03_AXI_0_arlen   (m_axi_arlen_bus[M3_SLOT*8 +: 8]),
        .M03_AXI_0_arsize  (m_axi_arsize_bus[M3_SLOT*3 +: 3]),
        .M03_AXI_0_arburst (m_axi_arburst_bus[M3_SLOT*2 +: 2]),
        .M03_AXI_0_arlock  (m_axi_arlock_bus[M3_SLOT]),
        .M03_AXI_0_arcache (m_axi_arcache_bus[M3_SLOT*4 +: 4]),
        .M03_AXI_0_arprot  (m_axi_arprot_bus[M3_SLOT*3 +: 3]),
        .M03_AXI_0_arqos   (m_axi_arqos_bus[M3_SLOT*4 +: 4]),
        .M03_AXI_0_arregion(m_axi_arregion_bus[M3_SLOT*4 +: 4]),
        .M03_AXI_0_arvalid (m_axi_arvalid_bus[M3_SLOT]),
        .M03_AXI_0_arready (m_axi_arready_bus[M3_SLOT]),
        .M03_AXI_0_rid     (m_axi_rid_bus[M3_SLOT*ID_WIDTH +: ID_WIDTH]),
        .M03_AXI_0_rdata   (m_axi_rdata_bus[M3_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .M03_AXI_0_rresp   (m_axi_rresp_bus[M3_SLOT*2 +: 2]),
        .M03_AXI_0_rlast   (m_axi_rlast_bus[M3_SLOT]),
        .M03_AXI_0_rvalid  (m_axi_rvalid_bus[M3_SLOT]),
        .M03_AXI_0_rready  (m_axi_rready_bus[M3_SLOT])
    );
    */

    assign m_axi_buser_bus = {M_COUNT*USER_WIDTH{1'b0}};
    assign m_axi_ruser_bus = {M_COUNT*USER_WIDTH{1'b0}};

    // ========= M00 -> RAM0 =========
    // NOTE: if using bd_ic_2x4_wrapper, set this ID_WIDTH to BD_ID_WIDTH (2).
    axi_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(SLAVE_ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(OUT_ID_WIDTH),
        .INIT_FILE(RAM0_INIT_FILE)
    ) ram0 (
        .clk(clk), .rst(rst),
        .s_axi_awid(m_axi_awid_bus[M0_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_awaddr(m_axi_awaddr_bus[M0_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH]),
        .s_axi_awlen(m_axi_awlen_bus[M0_SLOT*8 +: 8]),
        .s_axi_awsize(m_axi_awsize_bus[M0_SLOT*3 +: 3]),
        .s_axi_awburst(m_axi_awburst_bus[M0_SLOT*2 +: 2]),
        .s_axi_awlock(m_axi_awlock_bus[M0_SLOT]),
        .s_axi_awcache(m_axi_awcache_bus[M0_SLOT*4 +: 4]),
        .s_axi_awprot(m_axi_awprot_bus[M0_SLOT*3 +: 3]),
        .s_axi_awvalid(m_axi_awvalid_bus[M0_SLOT]),
        .s_axi_awready(m_axi_awready_bus[M0_SLOT]),
        .s_axi_wdata(m_axi_wdata_bus[M0_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_wstrb(m_axi_wstrb_bus[M0_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(m_axi_wlast_bus[M0_SLOT]),
        .s_axi_wvalid(m_axi_wvalid_bus[M0_SLOT]),
        .s_axi_wready(m_axi_wready_bus[M0_SLOT]),
        .s_axi_bid(m_axi_bid_bus[M0_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_bresp(m_axi_bresp_bus[M0_SLOT*2 +: 2]),
        .s_axi_bvalid(m_axi_bvalid_bus[M0_SLOT]),
        .s_axi_bready(m_axi_bready_bus[M0_SLOT]),
        .s_axi_arid(m_axi_arid_bus[M0_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_araddr(m_axi_araddr_bus[M0_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH]),
        .s_axi_arlen(m_axi_arlen_bus[M0_SLOT*8 +: 8]),
        .s_axi_arsize(m_axi_arsize_bus[M0_SLOT*3 +: 3]),
        .s_axi_arburst(m_axi_arburst_bus[M0_SLOT*2 +: 2]),
        .s_axi_arlock(m_axi_arlock_bus[M0_SLOT]),
        .s_axi_arcache(m_axi_arcache_bus[M0_SLOT*4 +: 4]),
        .s_axi_arprot(m_axi_arprot_bus[M0_SLOT*3 +: 3]),
        .s_axi_arvalid(m_axi_arvalid_bus[M0_SLOT]),
        .s_axi_arready(m_axi_arready_bus[M0_SLOT]),
        .s_axi_rid(m_axi_rid_bus[M0_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_rdata(m_axi_rdata_bus[M0_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(m_axi_rresp_bus[M0_SLOT*2 +: 2]),
        .s_axi_rlast(m_axi_rlast_bus[M0_SLOT]),
        .s_axi_rvalid(m_axi_rvalid_bus[M0_SLOT]),
        .s_axi_rready(m_axi_rready_bus[M0_SLOT])
    );

    // ========= M01 -> RAM1 =========
    // NOTE: if using bd_ic_2x4_wrapper, set this ID_WIDTH to BD_ID_WIDTH (2).
    axi_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(SLAVE_ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(OUT_ID_WIDTH)
    ) ram1 (
        .clk(clk), .rst(rst),
        .s_axi_awid(m_axi_awid_bus[M1_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_awaddr(m_axi_awaddr_bus[M1_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH]),
        .s_axi_awlen(m_axi_awlen_bus[M1_SLOT*8 +: 8]),
        .s_axi_awsize(m_axi_awsize_bus[M1_SLOT*3 +: 3]),
        .s_axi_awburst(m_axi_awburst_bus[M1_SLOT*2 +: 2]),
        .s_axi_awlock(m_axi_awlock_bus[M1_SLOT]),
        .s_axi_awcache(m_axi_awcache_bus[M1_SLOT*4 +: 4]),
        .s_axi_awprot(m_axi_awprot_bus[M1_SLOT*3 +: 3]),
        .s_axi_awvalid(m_axi_awvalid_bus[M1_SLOT]),
        .s_axi_awready(m_axi_awready_bus[M1_SLOT]),
        .s_axi_wdata(m_axi_wdata_bus[M1_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_wstrb(m_axi_wstrb_bus[M1_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(m_axi_wlast_bus[M1_SLOT]),
        .s_axi_wvalid(m_axi_wvalid_bus[M1_SLOT]),
        .s_axi_wready(m_axi_wready_bus[M1_SLOT]),
        .s_axi_bid(m_axi_bid_bus[M1_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_bresp(m_axi_bresp_bus[M1_SLOT*2 +: 2]),
        .s_axi_bvalid(m_axi_bvalid_bus[M1_SLOT]),
        .s_axi_bready(m_axi_bready_bus[M1_SLOT]),
        .s_axi_arid(m_axi_arid_bus[M1_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_araddr(m_axi_araddr_bus[M1_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH]),
        .s_axi_arlen(m_axi_arlen_bus[M1_SLOT*8 +: 8]),
        .s_axi_arsize(m_axi_arsize_bus[M1_SLOT*3 +: 3]),
        .s_axi_arburst(m_axi_arburst_bus[M1_SLOT*2 +: 2]),
        .s_axi_arlock(m_axi_arlock_bus[M1_SLOT]),
        .s_axi_arcache(m_axi_arcache_bus[M1_SLOT*4 +: 4]),
        .s_axi_arprot(m_axi_arprot_bus[M1_SLOT*3 +: 3]),
        .s_axi_arvalid(m_axi_arvalid_bus[M1_SLOT]),
        .s_axi_arready(m_axi_arready_bus[M1_SLOT]),
        .s_axi_rid(m_axi_rid_bus[M1_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_rdata(m_axi_rdata_bus[M1_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(m_axi_rresp_bus[M1_SLOT*2 +: 2]),
        .s_axi_rlast(m_axi_rlast_bus[M1_SLOT]),
        .s_axi_rvalid(m_axi_rvalid_bus[M1_SLOT]),
        .s_axi_rready(m_axi_rready_bus[M1_SLOT])
    );

    // ========= M02 -> RAM2 =========
    // NOTE: if using bd_ic_2x4_wrapper, set this ID_WIDTH to BD_ID_WIDTH (2).
    axi_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(SLAVE_ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(OUT_ID_WIDTH)
    ) ram2 (
        .clk(clk), .rst(rst),
        .s_axi_awid(m_axi_awid_bus[M2_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_awaddr(m_axi_awaddr_bus[M2_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH]),
        .s_axi_awlen(m_axi_awlen_bus[M2_SLOT*8 +: 8]),
        .s_axi_awsize(m_axi_awsize_bus[M2_SLOT*3 +: 3]),
        .s_axi_awburst(m_axi_awburst_bus[M2_SLOT*2 +: 2]),
        .s_axi_awlock(m_axi_awlock_bus[M2_SLOT]),
        .s_axi_awcache(m_axi_awcache_bus[M2_SLOT*4 +: 4]),
        .s_axi_awprot(m_axi_awprot_bus[M2_SLOT*3 +: 3]),
        .s_axi_awvalid(m_axi_awvalid_bus[M2_SLOT]),
        .s_axi_awready(m_axi_awready_bus[M2_SLOT]),
        .s_axi_wdata(m_axi_wdata_bus[M2_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_wstrb(m_axi_wstrb_bus[M2_SLOT*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(m_axi_wlast_bus[M2_SLOT]),
        .s_axi_wvalid(m_axi_wvalid_bus[M2_SLOT]),
        .s_axi_wready(m_axi_wready_bus[M2_SLOT]),
        .s_axi_bid(m_axi_bid_bus[M2_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_bresp(m_axi_bresp_bus[M2_SLOT*2 +: 2]),
        .s_axi_bvalid(m_axi_bvalid_bus[M2_SLOT]),
        .s_axi_bready(m_axi_bready_bus[M2_SLOT]),
        .s_axi_arid(m_axi_arid_bus[M2_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_araddr(m_axi_araddr_bus[M2_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH]),
        .s_axi_arlen(m_axi_arlen_bus[M2_SLOT*8 +: 8]),
        .s_axi_arsize(m_axi_arsize_bus[M2_SLOT*3 +: 3]),
        .s_axi_arburst(m_axi_arburst_bus[M2_SLOT*2 +: 2]),
        .s_axi_arlock(m_axi_arlock_bus[M2_SLOT]),
        .s_axi_arcache(m_axi_arcache_bus[M2_SLOT*4 +: 4]),
        .s_axi_arprot(m_axi_arprot_bus[M2_SLOT*3 +: 3]),
        .s_axi_arvalid(m_axi_arvalid_bus[M2_SLOT]),
        .s_axi_arready(m_axi_arready_bus[M2_SLOT]),
        .s_axi_rid(m_axi_rid_bus[M2_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH]),
        .s_axi_rdata(m_axi_rdata_bus[M2_SLOT*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(m_axi_rresp_bus[M2_SLOT*2 +: 2]),
        .s_axi_rlast(m_axi_rlast_bus[M2_SLOT]),
        .s_axi_rvalid(m_axi_rvalid_bus[M2_SLOT]),
        .s_axi_rready(m_axi_rready_bus[M2_SLOT])
    );

    // ========= M03 -> external DMA slave (s3) =========
    assign s3_axi_awid    = m_axi_awid_bus[M3_SLOT*OUT_ID_WIDTH +: ID_WIDTH];
    assign s3_axi_awaddr  = m_axi_awaddr_bus[M3_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH];
    assign s3_axi_awlen   = m_axi_awlen_bus[M3_SLOT*8 +: 8];
    assign s3_axi_awsize  = m_axi_awsize_bus[M3_SLOT*3 +: 3];
    assign s3_axi_awburst = m_axi_awburst_bus[M3_SLOT*2 +: 2];
    assign s3_axi_awlock  = m_axi_awlock_bus[M3_SLOT];
    assign s3_axi_awcache = m_axi_awcache_bus[M3_SLOT*4 +: 4];
    assign s3_axi_awprot  = m_axi_awprot_bus[M3_SLOT*3 +: 3];
    assign s3_axi_awvalid = m_axi_awvalid_bus[M3_SLOT];
    assign m_axi_awready_bus[M3_SLOT] = s3_axi_awready;

    assign s3_axi_wdata   = m_axi_wdata_bus[M3_SLOT*DATA_WIDTH +: DATA_WIDTH];
    assign s3_axi_wstrb   = m_axi_wstrb_bus[M3_SLOT*STRB_WIDTH +: STRB_WIDTH];
    assign s3_axi_wlast   = m_axi_wlast_bus[M3_SLOT];
    assign s3_axi_wvalid  = m_axi_wvalid_bus[M3_SLOT];
    assign m_axi_wready_bus[M3_SLOT] = s3_axi_wready;

    assign m_axi_bid_bus[M3_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH] =
        {{(OUT_ID_WIDTH-ID_WIDTH){1'b0}}, s3_axi_bid};
    assign m_axi_bresp_bus[M3_SLOT*2 +: 2]             = s3_axi_bresp;
    assign m_axi_bvalid_bus[M3_SLOT]                   = s3_axi_bvalid;
    assign s3_axi_bready                               = m_axi_bready_bus[M3_SLOT];

    assign s3_axi_arid    = m_axi_arid_bus[M3_SLOT*OUT_ID_WIDTH +: ID_WIDTH];
    assign s3_axi_araddr  = m_axi_araddr_bus[M3_SLOT*AXI_ADDR_WIDTH +: SLAVE_ADDR_WIDTH];
    assign s3_axi_arlen   = m_axi_arlen_bus[M3_SLOT*8 +: 8];
    assign s3_axi_arsize  = m_axi_arsize_bus[M3_SLOT*3 +: 3];
    assign s3_axi_arburst = m_axi_arburst_bus[M3_SLOT*2 +: 2];
    assign s3_axi_arlock  = m_axi_arlock_bus[M3_SLOT];
    assign s3_axi_arcache = m_axi_arcache_bus[M3_SLOT*4 +: 4];
    assign s3_axi_arprot  = m_axi_arprot_bus[M3_SLOT*3 +: 3];
    assign s3_axi_arvalid = m_axi_arvalid_bus[M3_SLOT];
    assign m_axi_arready_bus[M3_SLOT] = s3_axi_arready;

    assign m_axi_rid_bus[M3_SLOT*OUT_ID_WIDTH +: OUT_ID_WIDTH] =
        {{(OUT_ID_WIDTH-ID_WIDTH){1'b0}}, s3_axi_rid};
    assign m_axi_rdata_bus[M3_SLOT*DATA_WIDTH +: DATA_WIDTH] = s3_axi_rdata;
    assign m_axi_rresp_bus[M3_SLOT*2 +: 2]                  = s3_axi_rresp;
    assign m_axi_rlast_bus[M3_SLOT]                         = s3_axi_rlast;
    assign m_axi_rvalid_bus[M3_SLOT]                        = s3_axi_rvalid;
    assign s3_axi_rready                                    = m_axi_rready_bus[M3_SLOT];

endmodule

`resetall
