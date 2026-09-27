`timescale 1ns/1ps
`default_nettype none

// VC707 production-oriented wrapper: PicoRV32 + SLH-DSA SHAKE accelerator +
// DMA/IOMMU + the board's 1 GiB DDR3 through the generated MIG stack.
// Firmware remains in BRAM.  DMA addresses 0x8000_0000..0xbfff_ffff are sent
// to DDR3; low addresses remain on the internal AXI fabric.
module vc707_picorv32_slh_soc_ddr #(
    parameter MEM_INIT_FILE = "soc_boot.mem"
) (
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,
    input  wire        cpu_reset,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    output wire [7:0]  led_o,

    inout  wire [63:0] ddr3_dq,
    inout  wire [7:0]  ddr3_dqs_n,
    inout  wire [7:0]  ddr3_dqs_p,
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [7:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt
);
    wire ddr_ui_clk;
    wire ddr_ui_reset;
    wire ddr_init_calib_complete;
    wire clkfb_unbuf, clkfb, soc_clk_unbuf, soc_clk, mmcm_locked;

    // The selected MIG exposes a 200 MHz UI clock.  The 600 MHz MMCM VCO and
    // 5.625 fractional divider generate 106.666667 MHz for the SoC.  This is
    // the highest implemented clock with margin after post-route timing.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(5.000),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(3.000),
        .CLKOUT0_DIVIDE_F(5.625), .STARTUP_WAIT("FALSE")
    ) soc_mmcm (
        .CLKIN1(ddr_ui_clk), .CLKFBIN(clkfb), .RST(ddr_ui_reset),
        .PWRDWN(1'b0), .CLKFBOUT(clkfb_unbuf),
        .CLKOUT0(soc_clk_unbuf), .LOCKED(mmcm_locked),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(),
        .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(),
        .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG feedback_buf (.I(clkfb_unbuf), .O(clkfb));
    BUFG soc_clk_buf (.I(soc_clk_unbuf), .O(soc_clk));

    wire reset_async = cpu_reset | ~ddr_init_calib_complete | ~mmcm_locked;
    // Async assertion is required while MIG/MMCM are not ready.  Deassertion
    // is shifted through three soc_clk edges, so downstream logic only leaves
    // reset synchronously.  ASYNC_REG keeps the synchronizer stages together.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [2:0] reset_pipe = 3'b111;
    always @(posedge soc_clk or posedge reset_async) begin
        if (reset_async)
            reset_pipe <= 3'b111;
        else
            reset_pipe <= {reset_pipe[1:0], 1'b0};
    end
    wire soc_resetn = ~reset_pipe[2];

    wire [4:0] ddr_awid, ddr_bid, ddr_arid, ddr_rid;
    wire [31:0] ddr_awaddr, ddr_wdata, ddr_araddr, ddr_rdata;
    wire [7:0] ddr_awlen, ddr_arlen;
    wire [2:0] ddr_awsize, ddr_awprot, ddr_arsize, ddr_arprot;
    wire [1:0] ddr_awburst, ddr_bresp, ddr_arburst, ddr_rresp;
    wire ddr_awlock, ddr_awvalid, ddr_awready;
    wire [3:0] ddr_awcache, ddr_awqos, ddr_wstrb;
    wire ddr_wlast, ddr_wvalid, ddr_wready, ddr_bvalid, ddr_bready;
    wire ddr_arlock, ddr_arvalid, ddr_arready;
    wire [3:0] ddr_arcache, ddr_arqos;
    wire ddr_rlast, ddr_rvalid, ddr_rready;
    wire [31:0] gpio;
    wire trap, bus_error, shake_irq, uart_irq, timer_irq, dma_irq;

    picorv32_slh_soc #(
        .CLOCK_HZ(106_666_667), .BAUD_RATE(115_200),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) soc (
        .clk(soc_clk), .resetn(soc_resetn),
        .uart_rx(uart_rx_i), .uart_tx(uart_tx_o), .gpio_out(gpio),
        .trap(trap), .bus_error(bus_error), .shake_irq(shake_irq),
        .uart_irq(uart_irq), .timer_irq(timer_irq), .dma_irq(dma_irq),
        .ddr_m_axi_awid(ddr_awid), .ddr_m_axi_awaddr(ddr_awaddr),
        .ddr_m_axi_awlen(ddr_awlen), .ddr_m_axi_awsize(ddr_awsize),
        .ddr_m_axi_awburst(ddr_awburst), .ddr_m_axi_awlock(ddr_awlock),
        .ddr_m_axi_awcache(ddr_awcache), .ddr_m_axi_awprot(ddr_awprot),
        .ddr_m_axi_awqos(ddr_awqos), .ddr_m_axi_awvalid(ddr_awvalid),
        .ddr_m_axi_awready(ddr_awready), .ddr_m_axi_wdata(ddr_wdata),
        .ddr_m_axi_wstrb(ddr_wstrb), .ddr_m_axi_wlast(ddr_wlast),
        .ddr_m_axi_wvalid(ddr_wvalid), .ddr_m_axi_wready(ddr_wready),
        .ddr_m_axi_bid(ddr_bid), .ddr_m_axi_bresp(ddr_bresp),
        .ddr_m_axi_bvalid(ddr_bvalid), .ddr_m_axi_bready(ddr_bready),
        .ddr_m_axi_arid(ddr_arid), .ddr_m_axi_araddr(ddr_araddr),
        .ddr_m_axi_arlen(ddr_arlen), .ddr_m_axi_arsize(ddr_arsize),
        .ddr_m_axi_arburst(ddr_arburst), .ddr_m_axi_arlock(ddr_arlock),
        .ddr_m_axi_arcache(ddr_arcache), .ddr_m_axi_arprot(ddr_arprot),
        .ddr_m_axi_arqos(ddr_arqos), .ddr_m_axi_arvalid(ddr_arvalid),
        .ddr_m_axi_arready(ddr_arready), .ddr_m_axi_rid(ddr_rid),
        .ddr_m_axi_rdata(ddr_rdata), .ddr_m_axi_rresp(ddr_rresp),
        .ddr_m_axi_rlast(ddr_rlast), .ddr_m_axi_rvalid(ddr_rvalid),
        .ddr_m_axi_rready(ddr_rready)
    );

    vc707_axi_ddr3_bridge ddr3_bridge (
        .sys_clk_p(sys_clk_p), .sys_clk_n(sys_clk_n),
        .sys_rst_i(cpu_reset), .soc_clk_i(soc_clk),
        .soc_aresetn_i(soc_resetn),
        .s_axi_awid(ddr_awid), .s_axi_awaddr(ddr_awaddr),
        .s_axi_awlen(ddr_awlen), .s_axi_awsize(ddr_awsize),
        .s_axi_awburst(ddr_awburst), .s_axi_awlock(ddr_awlock),
        .s_axi_awcache(ddr_awcache), .s_axi_awprot(ddr_awprot),
        .s_axi_awqos(ddr_awqos), .s_axi_awvalid(ddr_awvalid),
        .s_axi_awready(ddr_awready), .s_axi_wdata(ddr_wdata),
        .s_axi_wstrb(ddr_wstrb), .s_axi_wlast(ddr_wlast),
        .s_axi_wvalid(ddr_wvalid), .s_axi_wready(ddr_wready),
        .s_axi_bid(ddr_bid), .s_axi_bresp(ddr_bresp),
        .s_axi_bvalid(ddr_bvalid), .s_axi_bready(ddr_bready),
        .s_axi_arid(ddr_arid), .s_axi_araddr(ddr_araddr),
        .s_axi_arlen(ddr_arlen), .s_axi_arsize(ddr_arsize),
        .s_axi_arburst(ddr_arburst), .s_axi_arlock(ddr_arlock),
        .s_axi_arcache(ddr_arcache), .s_axi_arprot(ddr_arprot),
        .s_axi_arqos(ddr_arqos), .s_axi_arvalid(ddr_arvalid),
        .s_axi_arready(ddr_arready), .s_axi_rid(ddr_rid),
        .s_axi_rdata(ddr_rdata), .s_axi_rresp(ddr_rresp),
        .s_axi_rlast(ddr_rlast), .s_axi_rvalid(ddr_rvalid),
        .s_axi_rready(ddr_rready), .ui_clk_o(ddr_ui_clk),
        .ui_reset_o(ddr_ui_reset),
        .init_calib_complete_o(ddr_init_calib_complete),
        .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p), .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba), .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n), .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n), .ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n), .ddr3_cke(ddr3_cke),
        .ddr3_cs_n(ddr3_cs_n), .ddr3_dm(ddr3_dm),
        .ddr3_odt(ddr3_odt)
    );

    assign led_o = {gpio[0], timer_irq, uart_irq, shake_irq,
                    dma_irq, bus_error, trap, ddr_init_calib_complete};
endmodule

`resetall
