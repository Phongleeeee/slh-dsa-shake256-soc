`timescale 1ns/1ps
`default_nettype none

// One-master/two-target AXI4 router used on the DMA data path.
//
// 0x0000_0000..0x7fff_ffff and 0xc000_0000..0xffff_ffff -> local fabric
// 0x8000_0000..0xbfff_ffff                              -> VC707 DDR3
//
// Read and write channels have independent state so a CDMA write address can
// never block the read request which is needed to produce its write data.
// This router deliberately permits one outstanding write and one outstanding
// read.  That matches the current DMA engines and makes the clock-domain
// boundary at the MIG deterministic.
module dma_axi_mem_router #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 4
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [ID_WIDTH-1:0]   s_awid,
    input  wire [ADDR_WIDTH-1:0] s_awaddr,
    input  wire [7:0]            s_awlen,
    input  wire [2:0]            s_awsize,
    input  wire [1:0]            s_awburst,
    input  wire                  s_awlock,
    input  wire [3:0]            s_awcache,
    input  wire [2:0]            s_awprot,
    input  wire [3:0]            s_awqos,
    input  wire                  s_awvalid,
    output wire                  s_awready,
    input  wire [DATA_WIDTH-1:0] s_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_wstrb,
    input  wire                  s_wlast,
    input  wire                  s_wvalid,
    output wire                  s_wready,
    output wire [ID_WIDTH-1:0]   s_bid,
    output wire [1:0]            s_bresp,
    output wire                  s_bvalid,
    input  wire                  s_bready,

    input  wire [ID_WIDTH-1:0]   s_arid,
    input  wire [ADDR_WIDTH-1:0] s_araddr,
    input  wire [7:0]            s_arlen,
    input  wire [2:0]            s_arsize,
    input  wire [1:0]            s_arburst,
    input  wire                  s_arlock,
    input  wire [3:0]            s_arcache,
    input  wire [2:0]            s_arprot,
    input  wire [3:0]            s_arqos,
    input  wire                  s_arvalid,
    output wire                  s_arready,
    output wire [ID_WIDTH-1:0]   s_rid,
    output wire [DATA_WIDTH-1:0] s_rdata,
    output wire [1:0]            s_rresp,
    output wire                  s_rlast,
    output wire                  s_rvalid,
    input  wire                  s_rready,

    output wire [ID_WIDTH-1:0]   l_awid,
    output wire [ADDR_WIDTH-1:0] l_awaddr,
    output wire [7:0]            l_awlen,
    output wire [2:0]            l_awsize,
    output wire [1:0]            l_awburst,
    output wire                  l_awlock,
    output wire [3:0]            l_awcache,
    output wire [2:0]            l_awprot,
    output wire                  l_awvalid,
    input  wire                  l_awready,
    output wire [DATA_WIDTH-1:0] l_wdata,
    output wire [DATA_WIDTH/8-1:0] l_wstrb,
    output wire                  l_wlast,
    output wire                  l_wvalid,
    input  wire                  l_wready,
    input  wire [ID_WIDTH-1:0]   l_bid,
    input  wire [1:0]            l_bresp,
    input  wire                  l_bvalid,
    output wire                  l_bready,
    output wire [ID_WIDTH-1:0]   l_arid,
    output wire [ADDR_WIDTH-1:0] l_araddr,
    output wire [7:0]            l_arlen,
    output wire [2:0]            l_arsize,
    output wire [1:0]            l_arburst,
    output wire                  l_arlock,
    output wire [3:0]            l_arcache,
    output wire [2:0]            l_arprot,
    output wire                  l_arvalid,
    input  wire                  l_arready,
    input  wire [ID_WIDTH-1:0]   l_rid,
    input  wire [DATA_WIDTH-1:0] l_rdata,
    input  wire [1:0]            l_rresp,
    input  wire                  l_rlast,
    input  wire                  l_rvalid,
    output wire                  l_rready,

    output wire [ID_WIDTH-1:0]   d_awid,
    output wire [ADDR_WIDTH-1:0] d_awaddr,
    output wire [7:0]            d_awlen,
    output wire [2:0]            d_awsize,
    output wire [1:0]            d_awburst,
    output wire                  d_awlock,
    output wire [3:0]            d_awcache,
    output wire [2:0]            d_awprot,
    output wire [3:0]            d_awqos,
    output wire                  d_awvalid,
    input  wire                  d_awready,
    output wire [DATA_WIDTH-1:0] d_wdata,
    output wire [DATA_WIDTH/8-1:0] d_wstrb,
    output wire                  d_wlast,
    output wire                  d_wvalid,
    input  wire                  d_wready,
    input  wire [ID_WIDTH-1:0]   d_bid,
    input  wire [1:0]            d_bresp,
    input  wire                  d_bvalid,
    output wire                  d_bready,
    output wire [ID_WIDTH-1:0]   d_arid,
    output wire [ADDR_WIDTH-1:0] d_araddr,
    output wire [7:0]            d_arlen,
    output wire [2:0]            d_arsize,
    output wire [1:0]            d_arburst,
    output wire                  d_arlock,
    output wire [3:0]            d_arcache,
    output wire [2:0]            d_arprot,
    output wire [3:0]            d_arqos,
    output wire                  d_arvalid,
    input  wire                  d_arready,
    input  wire [ID_WIDTH-1:0]   d_rid,
    input  wire [DATA_WIDTH-1:0] d_rdata,
    input  wire [1:0]            d_rresp,
    input  wire                  d_rlast,
    input  wire                  d_rvalid,
    output wire                  d_rready
);
    wire aw_to_ddr = (s_awaddr[31:30] == 2'b10);
    wire ar_to_ddr = (s_araddr[31:30] == 2'b10);
    reg write_active;
    reg write_ddr;
    reg read_active;
    reg read_ddr;

    always @(posedge clk) begin
        if (rst) begin
            write_active <= 1'b0;
            write_ddr <= 1'b0;
            read_active <= 1'b0;
            read_ddr <= 1'b0;
        end else begin
            if (!write_active && s_awvalid && s_awready) begin
                write_active <= 1'b1;
                write_ddr <= aw_to_ddr;
            end else if (write_active && s_bvalid && s_bready) begin
                write_active <= 1'b0;
            end
            if (!read_active && s_arvalid && s_arready) begin
                read_active <= 1'b1;
                read_ddr <= ar_to_ddr;
            end else if (read_active && s_rvalid && s_rready && s_rlast) begin
                read_active <= 1'b0;
            end
        end
    end

    assign s_awready = !write_active && (aw_to_ddr ? d_awready : l_awready);
    assign l_awvalid = !write_active && s_awvalid && !aw_to_ddr;
    assign d_awvalid = !write_active && s_awvalid && aw_to_ddr;
    assign s_wready  = write_active && (write_ddr ? d_wready : l_wready);
    assign l_wvalid  = write_active && s_wvalid && !write_ddr;
    assign d_wvalid  = write_active && s_wvalid && write_ddr;
    assign s_bid     = write_ddr ? d_bid : l_bid;
    assign s_bresp   = write_ddr ? d_bresp : l_bresp;
    assign s_bvalid  = write_active && (write_ddr ? d_bvalid : l_bvalid);
    assign l_bready  = write_active && !write_ddr && s_bready;
    assign d_bready  = write_active &&  write_ddr && s_bready;

    assign s_arready = !read_active && (ar_to_ddr ? d_arready : l_arready);
    assign l_arvalid = !read_active && s_arvalid && !ar_to_ddr;
    assign d_arvalid = !read_active && s_arvalid && ar_to_ddr;
    assign s_rid     = read_ddr ? d_rid : l_rid;
    assign s_rdata   = read_ddr ? d_rdata : l_rdata;
    assign s_rresp   = read_ddr ? d_rresp : l_rresp;
    assign s_rlast   = read_ddr ? d_rlast : l_rlast;
    assign s_rvalid  = read_active && (read_ddr ? d_rvalid : l_rvalid);
    assign l_rready  = read_active && !read_ddr && s_rready;
    assign d_rready  = read_active &&  read_ddr && s_rready;

    assign l_awid = s_awid;       assign d_awid = s_awid;
    // The external aperture is based at 0x8000_0000 in the SoC address map,
    // while the MIG AXI port expects a zero-based DDR byte address.
    assign l_awaddr = s_awaddr;   assign d_awaddr = {2'b00, s_awaddr[29:0]};
    assign l_awlen = s_awlen;     assign d_awlen = s_awlen;
    assign l_awsize = s_awsize;   assign d_awsize = s_awsize;
    assign l_awburst = s_awburst; assign d_awburst = s_awburst;
    assign l_awlock = s_awlock;   assign d_awlock = s_awlock;
    assign l_awcache = s_awcache; assign d_awcache = s_awcache;
    assign l_awprot = s_awprot;   assign d_awprot = s_awprot;
    assign d_awqos = s_awqos;
    assign l_wdata = s_wdata;     assign d_wdata = s_wdata;
    assign l_wstrb = s_wstrb;     assign d_wstrb = s_wstrb;
    assign l_wlast = s_wlast;     assign d_wlast = s_wlast;
    assign l_arid = s_arid;       assign d_arid = s_arid;
    assign l_araddr = s_araddr;   assign d_araddr = {2'b00, s_araddr[29:0]};
    assign l_arlen = s_arlen;     assign d_arlen = s_arlen;
    assign l_arsize = s_arsize;   assign d_arsize = s_arsize;
    assign l_arburst = s_arburst; assign d_arburst = s_arburst;
    assign l_arlock = s_arlock;   assign d_arlock = s_arlock;
    assign l_arcache = s_arcache; assign d_arcache = s_arcache;
    assign l_arprot = s_arprot;   assign d_arprot = s_arprot;
    assign d_arqos = s_arqos;
endmodule

`resetall
