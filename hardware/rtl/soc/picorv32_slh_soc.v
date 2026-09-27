`timescale 1ns/1ps
`default_nettype none

// PicoRV32 + existing 2x4 AXI4 fabric + three 64 KiB BRAM banks +
// SLH-DSA SHAKE256 accelerator + UART + timer/GPIO.
//
// Memory map:
//   0x0000_0000..0x0000_ffff RAM0 (boot/program, initialized from MEM_INIT_FILE)
//   0x0001_0000..0x0001_ffff RAM1
//   0x0002_0000..0x0002_ffff RAM2
//   0x0003_0000..0x0003_00ff SHAKE accelerator
//   0x0003_1000..0x0003_10ff UART
//   0x0003_2000..0x0003_20ff timer/GPIO
//   0x0003_3000..0x0003_30ff DMA/IOMMU control and status
module picorv32_slh_soc #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter MEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [31:0] gpio_out,
    output wire        trap,
    output wire        bus_error,
    output wire        shake_irq,
    output wire        uart_irq,
    output wire        timer_irq,
    output wire        dma_irq,

    // Optional VC707 DDR3 aperture for the DMA master.  The five-bit ID is
    // compatible with the generated MIG bridge; bit 4 is reserved as zero.
    output wire [4:0]  ddr_m_axi_awid,
    output wire [31:0] ddr_m_axi_awaddr,
    output wire [7:0]  ddr_m_axi_awlen,
    output wire [2:0]  ddr_m_axi_awsize,
    output wire [1:0]  ddr_m_axi_awburst,
    output wire        ddr_m_axi_awlock,
    output wire [3:0]  ddr_m_axi_awcache,
    output wire [2:0]  ddr_m_axi_awprot,
    output wire [3:0]  ddr_m_axi_awqos,
    output wire        ddr_m_axi_awvalid,
    input  wire        ddr_m_axi_awready,
    output wire [31:0] ddr_m_axi_wdata,
    output wire [3:0]  ddr_m_axi_wstrb,
    output wire        ddr_m_axi_wlast,
    output wire        ddr_m_axi_wvalid,
    input  wire        ddr_m_axi_wready,
    input  wire [4:0]  ddr_m_axi_bid,
    input  wire [1:0]  ddr_m_axi_bresp,
    input  wire        ddr_m_axi_bvalid,
    output wire        ddr_m_axi_bready,
    output wire [4:0]  ddr_m_axi_arid,
    output wire [31:0] ddr_m_axi_araddr,
    output wire [7:0]  ddr_m_axi_arlen,
    output wire [2:0]  ddr_m_axi_arsize,
    output wire [1:0]  ddr_m_axi_arburst,
    output wire        ddr_m_axi_arlock,
    output wire [3:0]  ddr_m_axi_arcache,
    output wire [2:0]  ddr_m_axi_arprot,
    output wire [3:0]  ddr_m_axi_arqos,
    output wire        ddr_m_axi_arvalid,
    input  wire        ddr_m_axi_arready,
    input  wire [4:0]  ddr_m_axi_rid,
    input  wire [31:0] ddr_m_axi_rdata,
    input  wire [1:0]  ddr_m_axi_rresp,
    input  wire        ddr_m_axi_rlast,
    input  wire        ddr_m_axi_rvalid,
    output wire        ddr_m_axi_rready
);
    portable_slh_soc_core #(
        .CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(BAUD_RATE),
        .MEM_INIT_FILE(MEM_INIT_FILE), .ENABLE_EXT_MEMORY(1)
    ) core (
        .clk(clk),
        .resetn(resetn),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio_out(gpio_out),
        .trap(trap),
        .bus_error(bus_error),
        .shake_irq(shake_irq),
        .uart_irq(uart_irq),
        .timer_irq(timer_irq),
        .dma_irq(dma_irq),
        .ext_m_axi_awid(ddr_m_axi_awid),
        .ext_m_axi_awaddr(ddr_m_axi_awaddr),
        .ext_m_axi_awlen(ddr_m_axi_awlen),
        .ext_m_axi_awsize(ddr_m_axi_awsize),
        .ext_m_axi_awburst(ddr_m_axi_awburst),
        .ext_m_axi_awlock(ddr_m_axi_awlock),
        .ext_m_axi_awcache(ddr_m_axi_awcache),
        .ext_m_axi_awprot(ddr_m_axi_awprot),
        .ext_m_axi_awqos(ddr_m_axi_awqos),
        .ext_m_axi_awvalid(ddr_m_axi_awvalid),
        .ext_m_axi_awready(ddr_m_axi_awready),
        .ext_m_axi_wdata(ddr_m_axi_wdata),
        .ext_m_axi_wstrb(ddr_m_axi_wstrb),
        .ext_m_axi_wlast(ddr_m_axi_wlast),
        .ext_m_axi_wvalid(ddr_m_axi_wvalid),
        .ext_m_axi_wready(ddr_m_axi_wready),
        .ext_m_axi_bid(ddr_m_axi_bid),
        .ext_m_axi_bresp(ddr_m_axi_bresp),
        .ext_m_axi_bvalid(ddr_m_axi_bvalid),
        .ext_m_axi_bready(ddr_m_axi_bready),
        .ext_m_axi_arid(ddr_m_axi_arid),
        .ext_m_axi_araddr(ddr_m_axi_araddr),
        .ext_m_axi_arlen(ddr_m_axi_arlen),
        .ext_m_axi_arsize(ddr_m_axi_arsize),
        .ext_m_axi_arburst(ddr_m_axi_arburst),
        .ext_m_axi_arlock(ddr_m_axi_arlock),
        .ext_m_axi_arcache(ddr_m_axi_arcache),
        .ext_m_axi_arprot(ddr_m_axi_arprot),
        .ext_m_axi_arqos(ddr_m_axi_arqos),
        .ext_m_axi_arvalid(ddr_m_axi_arvalid),
        .ext_m_axi_arready(ddr_m_axi_arready),
        .ext_m_axi_rid(ddr_m_axi_rid),
        .ext_m_axi_rdata(ddr_m_axi_rdata),
        .ext_m_axi_rresp(ddr_m_axi_rresp),
        .ext_m_axi_rlast(ddr_m_axi_rlast),
        .ext_m_axi_rvalid(ddr_m_axi_rvalid),
        .ext_m_axi_rready(ddr_m_axi_rready)
    );
endmodule

`resetall
