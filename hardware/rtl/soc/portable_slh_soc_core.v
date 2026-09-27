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
module portable_slh_soc_core #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter MEM_INIT_FILE = "",
    parameter integer ENABLE_EXT_MEMORY = 0
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

    // Optional board-independent AXI memory extension for the DMA master.
    // Disabled by default; no external memory or calibration is needed.
    output wire [4:0]  ext_m_axi_awid,
    output wire [31:0] ext_m_axi_awaddr,
    output wire [7:0]  ext_m_axi_awlen,
    output wire [2:0]  ext_m_axi_awsize,
    output wire [1:0]  ext_m_axi_awburst,
    output wire        ext_m_axi_awlock,
    output wire [3:0]  ext_m_axi_awcache,
    output wire [2:0]  ext_m_axi_awprot,
    output wire [3:0]  ext_m_axi_awqos,
    output wire        ext_m_axi_awvalid,
    input  wire        ext_m_axi_awready,
    output wire [31:0] ext_m_axi_wdata,
    output wire [3:0]  ext_m_axi_wstrb,
    output wire        ext_m_axi_wlast,
    output wire        ext_m_axi_wvalid,
    input  wire        ext_m_axi_wready,
    input  wire [4:0]  ext_m_axi_bid,
    input  wire [1:0]  ext_m_axi_bresp,
    input  wire        ext_m_axi_bvalid,
    output wire        ext_m_axi_bready,
    output wire [4:0]  ext_m_axi_arid,
    output wire [31:0] ext_m_axi_araddr,
    output wire [7:0]  ext_m_axi_arlen,
    output wire [2:0]  ext_m_axi_arsize,
    output wire [1:0]  ext_m_axi_arburst,
    output wire        ext_m_axi_arlock,
    output wire [3:0]  ext_m_axi_arcache,
    output wire [2:0]  ext_m_axi_arprot,
    output wire [3:0]  ext_m_axi_arqos,
    output wire        ext_m_axi_arvalid,
    input  wire        ext_m_axi_arready,
    input  wire [4:0]  ext_m_axi_rid,
    input  wire [31:0] ext_m_axi_rdata,
    input  wire [1:0]  ext_m_axi_rresp,
    input  wire        ext_m_axi_rlast,
    input  wire        ext_m_axi_rvalid,
    output wire        ext_m_axi_rready
);
    localparam integer AXI_ADDR_WIDTH = 32;
    localparam integer DATA_WIDTH = 32;
    localparam integer STRB_WIDTH = 4;
    localparam integer ID_WIDTH = 4;
    localparam integer SLAVE_ADDR_WIDTH = 16;

    // The kit wrapper supplies a synchronized reset. Register identical
    // copies near the four domains to avoid one global high-fanout reset
    // route and asynchronous control of BRAM enable/reset pins. All copies
    // assert/deassert on the SAME clock edge (one cycle after resetn).
    // Keep distinct registers: merging them defeats physical distribution.
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg [3:0] local_resetn_q = 4'b0;
    always @(posedge clk) local_resetn_q <= {4{resetn}};
    wire cpu_resetn = local_resetn_q[0];
    wire dma_resetn = local_resetn_q[1];
    // The optional memory router shares the fabric's reset domain.
    wire fabric_rst = ~local_resetn_q[2];
    wire router_rst = fabric_rst;
    wire peripherals_rst = ~local_resetn_q[3];

    // PicoRV32 AXI4-Lite master.
    wire        p_awvalid, p_awready;
    wire [31:0] p_awaddr;
    wire [2:0]  p_awprot;
    wire        p_wvalid, p_wready;
    wire [31:0] p_wdata;
    wire [3:0]  p_wstrb;
    wire        p_bvalid, p_bready;
    wire        p_arvalid, p_arready;
    wire [31:0] p_araddr;
    wire [2:0]  p_arprot;
    wire        p_rvalid, p_rready;
    wire [31:0] p_rdata;
    wire [31:0] cpu_irq;
    wire [31:0] cpu_eoi;
    wire        trace_valid;
    wire [35:0] trace_data;
    wire        pcpi_valid;
    wire [31:0] pcpi_insn, pcpi_rs1, pcpi_rs2;

    assign cpu_irq = {23'd0, dma_irq, timer_irq, uart_irq, shake_irq, 5'd0};

    picorv32_axi #(
        .ENABLE_COUNTERS(1),
        .ENABLE_COUNTERS64(1),
        .BARREL_SHIFTER(1),
        .TWO_CYCLE_COMPARE(1),
        .TWO_CYCLE_ALU(1),
        .CATCH_MISALIGN(1),
        .CATCH_ILLINSN(1),
        .ENABLE_IRQ(1),
        .ENABLE_IRQ_QREGS(1),
        .ENABLE_IRQ_TIMER(1),
        .REGS_INIT_ZERO(1),
        .PROGADDR_RESET(32'h0000_0000),
        .PROGADDR_IRQ(32'h0000_0010),
        .STACKADDR(32'h0002_fff0)
    ) cpu (
        .clk(clk), .resetn(cpu_resetn), .trap(trap),
        .mem_axi_awvalid(p_awvalid), .mem_axi_awready(p_awready),
        .mem_axi_awaddr(p_awaddr), .mem_axi_awprot(p_awprot),
        .mem_axi_wvalid(p_wvalid), .mem_axi_wready(p_wready),
        .mem_axi_wdata(p_wdata), .mem_axi_wstrb(p_wstrb),
        .mem_axi_bvalid(p_bvalid), .mem_axi_bready(p_bready),
        .mem_axi_arvalid(p_arvalid), .mem_axi_arready(p_arready),
        .mem_axi_araddr(p_araddr), .mem_axi_arprot(p_arprot),
        .mem_axi_rvalid(p_rvalid), .mem_axi_rready(p_rready),
        .mem_axi_rdata(p_rdata),
        .pcpi_valid(pcpi_valid), .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1), .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0),
        .pcpi_ready(1'b0), .irq(cpu_irq), .eoi(cpu_eoi),
        .trace_valid(trace_valid), .trace_data(trace_data)
    );

    // Promote the AXI4-Lite transaction to a legal single-beat AXI4
    // transaction for the existing full AXI fabric.
    wire [ID_WIDTH-1:0]       m0_axi_awid = {ID_WIDTH{1'b0}};
    wire [AXI_ADDR_WIDTH-1:0] m0_axi_awaddr = p_awaddr;
    wire [7:0]                m0_axi_awlen = 8'd0;
    wire [2:0]                m0_axi_awsize = 3'b010;
    wire [1:0]                m0_axi_awburst = 2'b01;
    wire                      m0_axi_awlock = 1'b0;
    wire [3:0]                m0_axi_awcache = 4'b0000;
    wire [2:0]                m0_axi_awprot = p_awprot;
    wire                      m0_axi_awvalid = p_awvalid;
    wire                      m0_axi_awready;
    wire [DATA_WIDTH-1:0]     m0_axi_wdata = p_wdata;
    wire [STRB_WIDTH-1:0]     m0_axi_wstrb = p_wstrb;
    wire                      m0_axi_wlast = 1'b1;
    wire                      m0_axi_wvalid = p_wvalid;
    wire                      m0_axi_wready;
    wire [ID_WIDTH-1:0]       m0_axi_bid;
    wire [1:0]                m0_axi_bresp;
    wire                      m0_axi_bvalid;
    wire                      m0_axi_bready = p_bready;
    wire [ID_WIDTH-1:0]       m0_axi_arid = {ID_WIDTH{1'b0}};
    wire [AXI_ADDR_WIDTH-1:0] m0_axi_araddr = p_araddr;
    wire [7:0]                m0_axi_arlen = 8'd0;
    wire [2:0]                m0_axi_arsize = 3'b010;
    wire [1:0]                m0_axi_arburst = 2'b01;
    wire                      m0_axi_arlock = 1'b0;
    wire [3:0]                m0_axi_arcache = 4'b0000;
    wire [2:0]                m0_axi_arprot = p_arprot;
    wire                      m0_axi_arvalid = p_arvalid;
    wire                      m0_axi_arready;
    wire [ID_WIDTH-1:0]       m0_axi_rid;
    wire [DATA_WIDTH-1:0]     m0_axi_rdata;
    wire [1:0]                m0_axi_rresp;
    wire                      m0_axi_rlast;
    wire                      m0_axi_rvalid;
    wire                      m0_axi_rready = p_rready;

    assign p_awready = m0_axi_awready;
    assign p_wready  = m0_axi_wready;
    assign p_bvalid  = m0_axi_bvalid;
    assign p_arready = m0_axi_arready;
    assign p_rvalid  = m0_axi_rvalid;
    assign p_rdata   = m0_axi_rdata;

    reg bus_error_q;
    always @(posedge clk or negedge cpu_resetn) begin
        if (!cpu_resetn)
            bus_error_q <= 1'b0;
        else if ((m0_axi_bvalid && m0_axi_bready && m0_axi_bresp != 2'b00) ||
                 (m0_axi_rvalid && m0_axi_rready && m0_axi_rresp != 2'b00))
            bus_error_q <= 1'b1;
    end
    assign bus_error = bus_error_q;

    // DMA/IOMMU owns the second full AXI master and can therefore move data
    // without making PicoRV32 execute load/store copy loops.
    wire [ID_WIDTH-1:0]       m1_axi_awid;
    wire [AXI_ADDR_WIDTH-1:0] m1_axi_awaddr;
    wire [7:0]                m1_axi_awlen;
    wire [2:0]                m1_axi_awsize;
    wire [1:0]                m1_axi_awburst;
    wire                      m1_axi_awlock;
    wire [3:0]                m1_axi_awcache;
    wire [2:0]                m1_axi_awprot;
    wire                      m1_axi_awvalid;
    wire                      m1_axi_awready;
    wire [DATA_WIDTH-1:0]     m1_axi_wdata;
    wire [STRB_WIDTH-1:0]     m1_axi_wstrb;
    wire                      m1_axi_wlast;
    wire                      m1_axi_wvalid;
    wire                      m1_axi_wready;
    wire [ID_WIDTH-1:0]       m1_axi_bid;
    wire [1:0]                m1_axi_bresp;
    wire                      m1_axi_bvalid;
    wire                      m1_axi_bready;
    wire [ID_WIDTH-1:0]       m1_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0] m1_axi_araddr;
    wire [7:0]                m1_axi_arlen;
    wire [2:0]                m1_axi_arsize;
    wire [1:0]                m1_axi_arburst;
    wire                      m1_axi_arlock;
    wire [3:0]                m1_axi_arcache;
    wire [2:0]                m1_axi_arprot;
    wire                      m1_axi_arvalid;
    wire                      m1_axi_arready;
    wire [ID_WIDTH-1:0]       m1_axi_rid;
    wire [DATA_WIDTH-1:0]     m1_axi_rdata;
    wire [1:0]                m1_axi_rresp;
    wire                      m1_axi_rlast;
    wire                      m1_axi_rvalid;
    wire                      m1_axi_rready;

    // Raw DMA master. The optional extension is selected at elaboration.
    // In the portable build all DMA traffic uses the local AXI fabric.
    wire [ID_WIDTH-1:0]       dma_axi_awid;
    wire [AXI_ADDR_WIDTH-1:0] dma_axi_awaddr;
    wire [7:0]                dma_axi_awlen;
    wire [2:0]                dma_axi_awsize;
    wire [1:0]                dma_axi_awburst;
    wire                      dma_axi_awlock;
    wire [3:0]                dma_axi_awcache;
    wire [2:0]                dma_axi_awprot;
    wire [3:0]                dma_axi_awqos;
    wire [3:0]                dma_axi_awregion;
    wire                      dma_axi_awvalid;
    wire                      dma_axi_awready;
    wire [DATA_WIDTH-1:0]     dma_axi_wdata;
    wire [STRB_WIDTH-1:0]     dma_axi_wstrb;
    wire                      dma_axi_wlast;
    wire                      dma_axi_wvalid;
    wire                      dma_axi_wready;
    wire [ID_WIDTH-1:0]       dma_axi_bid;
    wire [1:0]                dma_axi_bresp;
    wire                      dma_axi_bvalid;
    wire                      dma_axi_bready;
    wire [ID_WIDTH-1:0]       dma_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0] dma_axi_araddr;
    wire [7:0]                dma_axi_arlen;
    wire [2:0]                dma_axi_arsize;
    wire [1:0]                dma_axi_arburst;
    wire                      dma_axi_arlock;
    wire [3:0]                dma_axi_arcache;
    wire [2:0]                dma_axi_arprot;
    wire [3:0]                dma_axi_arqos;
    wire [3:0]                dma_axi_arregion;
    wire                      dma_axi_arvalid;
    wire                      dma_axi_arready;
    wire [ID_WIDTH-1:0]       dma_axi_rid;
    wire [DATA_WIDTH-1:0]     dma_axi_rdata;
    wire [1:0]                dma_axi_rresp;
    wire                      dma_axi_rlast;
    wire                      dma_axi_rvalid;
    wire                      dma_axi_rready;

    wire [ID_WIDTH-1:0]       ext_awid_int;
    wire [ID_WIDTH-1:0]       ext_bid_int = ext_m_axi_bid[ID_WIDTH-1:0];
    wire [ID_WIDTH-1:0]       ext_arid_int;
    wire [ID_WIDTH-1:0]       ext_rid_int = ext_m_axi_rid[ID_WIDTH-1:0];
    assign ext_m_axi_awid = {1'b0, ext_awid_int};
    assign ext_m_axi_arid = {1'b0, ext_arid_int};

    wire [7:0]  dma_axil_awaddr;
    wire [2:0]  dma_axil_awprot;
    wire        dma_axil_awvalid;
    wire        dma_axil_awready;
    wire [31:0] dma_axil_wdata;
    wire [3:0]  dma_axil_wstrb;
    wire        dma_axil_wvalid;
    wire        dma_axil_wready;
    wire [1:0]  dma_axil_bresp;
    wire        dma_axil_bvalid;
    wire        dma_axil_bready;
    wire [7:0]  dma_axil_araddr;
    wire [2:0]  dma_axil_arprot;
    wire        dma_axil_arvalid;
    wire        dma_axil_arready;
    wire [31:0] dma_axil_rdata;
    wire [31:0] dma_hash_s_data, dma_hash_m_data;
    wire [3:0] dma_hash_s_keep, dma_hash_m_keep;
    wire dma_hash_s_valid, dma_hash_s_ready, dma_hash_s_last;
    wire dma_hash_m_valid, dma_hash_m_ready, dma_hash_m_last;
    wire [1:0]  dma_axil_rresp;
    wire        dma_axil_rvalid;
    wire        dma_axil_rready;

    wire cpu_bus_idle = !(m0_axi_awvalid || m0_axi_wvalid ||
                          m0_axi_arvalid || m0_axi_bvalid || m0_axi_rvalid);

    dma_mmu_axi_top #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(DATA_WIDTH),
        // dma_mmu_axi_top appends one engine-selection bit to this value.
        .AXI_ID_WIDTH(ID_WIDTH-1),
        .AXIL_ADDR_WIDTH(8),
        .LEN_WIDTH(32),
        .PAGE_SHIFT(12),
        .PT_ENTRIES(16),
        .TLB_ENTRIES(4), .SECURE_LOCAL_RAM(!ENABLE_EXT_MEMORY),
        .AXI_MAX_BURST_LEN(16),
        .DESC_QUEUE_DEPTH(8)
    ) dma_iommu (
        .aclk(clk), .aresetn(dma_resetn), .cpu_bus_idle_i(cpu_bus_idle),
        .irq_o(dma_irq),
        .s_axil_awaddr(dma_axil_awaddr), .s_axil_awprot(dma_axil_awprot),
        .s_axil_awvalid(dma_axil_awvalid), .s_axil_awready(dma_axil_awready),
        .s_axil_wdata(dma_axil_wdata), .s_axil_wstrb(dma_axil_wstrb),
        .s_axil_wvalid(dma_axil_wvalid), .s_axil_wready(dma_axil_wready),
        .s_axil_bresp(dma_axil_bresp), .s_axil_bvalid(dma_axil_bvalid),
        .s_axil_bready(dma_axil_bready), .s_axil_araddr(dma_axil_araddr),
        .s_axil_arprot(dma_axil_arprot), .s_axil_arvalid(dma_axil_arvalid),
        .s_axil_arready(dma_axil_arready), .s_axil_rdata(dma_axil_rdata),
        .s_axil_rresp(dma_axil_rresp), .s_axil_rvalid(dma_axil_rvalid),
        .s_axil_rready(dma_axil_rready),
        .m_axi_awid(dma_axi_awid), .m_axi_awaddr(dma_axi_awaddr),
        .m_axi_awlen(dma_axi_awlen), .m_axi_awsize(dma_axi_awsize),
        .m_axi_awburst(dma_axi_awburst), .m_axi_awlock(dma_axi_awlock),
        .m_axi_awcache(dma_axi_awcache), .m_axi_awprot(dma_axi_awprot),
        .m_axi_awqos(dma_axi_awqos), .m_axi_awregion(dma_axi_awregion),
        .m_axi_awvalid(dma_axi_awvalid), .m_axi_awready(dma_axi_awready),
        .m_axi_wdata(dma_axi_wdata), .m_axi_wstrb(dma_axi_wstrb),
        .m_axi_wlast(dma_axi_wlast), .m_axi_wvalid(dma_axi_wvalid),
        .m_axi_wready(dma_axi_wready), .m_axi_bid(dma_axi_bid),
        .m_axi_bresp(dma_axi_bresp), .m_axi_bvalid(dma_axi_bvalid),
        .m_axi_bready(dma_axi_bready), .m_axi_arid(dma_axi_arid),
        .m_axi_araddr(dma_axi_araddr), .m_axi_arlen(dma_axi_arlen),
        .m_axi_arsize(dma_axi_arsize), .m_axi_arburst(dma_axi_arburst),
        .m_axi_arlock(dma_axi_arlock), .m_axi_arcache(dma_axi_arcache),
        .m_axi_arprot(dma_axi_arprot), .m_axi_arqos(dma_axi_arqos),
        .m_axi_arregion(dma_axi_arregion), .m_axi_arvalid(dma_axi_arvalid),
        .m_axi_arready(dma_axi_arready), .m_axi_rid(dma_axi_rid),
        .m_axi_rdata(dma_axi_rdata), .m_axi_rresp(dma_axi_rresp),
        .m_axi_rlast(dma_axi_rlast), .m_axi_rvalid(dma_axi_rvalid),
        .m_axi_rready(dma_axi_rready),
        .s_axis_periph_tdata(dma_hash_m_data), .s_axis_periph_tkeep(dma_hash_m_keep),
        .s_axis_periph_tvalid(dma_hash_m_valid), .s_axis_periph_tready(dma_hash_m_ready),
        .s_axis_periph_tlast(dma_hash_m_last), .m_axis_periph_tdata(dma_hash_s_data),
        .m_axis_periph_tkeep(dma_hash_s_keep), .m_axis_periph_tvalid(dma_hash_s_valid),
        .m_axis_periph_tready(dma_hash_s_ready), .m_axis_periph_tlast(dma_hash_s_last)
    );

    generate if (ENABLE_EXT_MEMORY) begin : external_memory
    dma_axi_mem_router #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dma_memory_router (
        .clk(clk), .rst(router_rst),
        .s_awid(dma_axi_awid), .s_awaddr(dma_axi_awaddr),
        .s_awlen(dma_axi_awlen), .s_awsize(dma_axi_awsize),
        .s_awburst(dma_axi_awburst), .s_awlock(dma_axi_awlock),
        .s_awcache(dma_axi_awcache), .s_awprot(dma_axi_awprot),
        .s_awqos(dma_axi_awqos), .s_awvalid(dma_axi_awvalid),
        .s_awready(dma_axi_awready), .s_wdata(dma_axi_wdata),
        .s_wstrb(dma_axi_wstrb), .s_wlast(dma_axi_wlast),
        .s_wvalid(dma_axi_wvalid), .s_wready(dma_axi_wready),
        .s_bid(dma_axi_bid), .s_bresp(dma_axi_bresp),
        .s_bvalid(dma_axi_bvalid), .s_bready(dma_axi_bready),
        .s_arid(dma_axi_arid), .s_araddr(dma_axi_araddr),
        .s_arlen(dma_axi_arlen), .s_arsize(dma_axi_arsize),
        .s_arburst(dma_axi_arburst), .s_arlock(dma_axi_arlock),
        .s_arcache(dma_axi_arcache), .s_arprot(dma_axi_arprot),
        .s_arqos(dma_axi_arqos), .s_arvalid(dma_axi_arvalid),
        .s_arready(dma_axi_arready), .s_rid(dma_axi_rid),
        .s_rdata(dma_axi_rdata), .s_rresp(dma_axi_rresp),
        .s_rlast(dma_axi_rlast), .s_rvalid(dma_axi_rvalid),
        .s_rready(dma_axi_rready),

        .l_awid(m1_axi_awid), .l_awaddr(m1_axi_awaddr),
        .l_awlen(m1_axi_awlen), .l_awsize(m1_axi_awsize),
        .l_awburst(m1_axi_awburst), .l_awlock(m1_axi_awlock),
        .l_awcache(m1_axi_awcache), .l_awprot(m1_axi_awprot),
        .l_awvalid(m1_axi_awvalid), .l_awready(m1_axi_awready),
        .l_wdata(m1_axi_wdata), .l_wstrb(m1_axi_wstrb),
        .l_wlast(m1_axi_wlast), .l_wvalid(m1_axi_wvalid),
        .l_wready(m1_axi_wready), .l_bid(m1_axi_bid),
        .l_bresp(m1_axi_bresp), .l_bvalid(m1_axi_bvalid),
        .l_bready(m1_axi_bready), .l_arid(m1_axi_arid),
        .l_araddr(m1_axi_araddr), .l_arlen(m1_axi_arlen),
        .l_arsize(m1_axi_arsize), .l_arburst(m1_axi_arburst),
        .l_arlock(m1_axi_arlock), .l_arcache(m1_axi_arcache),
        .l_arprot(m1_axi_arprot), .l_arvalid(m1_axi_arvalid),
        .l_arready(m1_axi_arready), .l_rid(m1_axi_rid),
        .l_rdata(m1_axi_rdata), .l_rresp(m1_axi_rresp),
        .l_rlast(m1_axi_rlast), .l_rvalid(m1_axi_rvalid),
        .l_rready(m1_axi_rready),

        .d_awid(ext_awid_int), .d_awaddr(ext_m_axi_awaddr),
        .d_awlen(ext_m_axi_awlen), .d_awsize(ext_m_axi_awsize),
        .d_awburst(ext_m_axi_awburst), .d_awlock(ext_m_axi_awlock),
        .d_awcache(ext_m_axi_awcache), .d_awprot(ext_m_axi_awprot),
        .d_awqos(ext_m_axi_awqos), .d_awvalid(ext_m_axi_awvalid),
        .d_awready(ext_m_axi_awready), .d_wdata(ext_m_axi_wdata),
        .d_wstrb(ext_m_axi_wstrb), .d_wlast(ext_m_axi_wlast),
        .d_wvalid(ext_m_axi_wvalid), .d_wready(ext_m_axi_wready),
        .d_bid(ext_bid_int), .d_bresp(ext_m_axi_bresp),
        .d_bvalid(ext_m_axi_bvalid), .d_bready(ext_m_axi_bready),
        .d_arid(ext_arid_int), .d_araddr(ext_m_axi_araddr),
        .d_arlen(ext_m_axi_arlen), .d_arsize(ext_m_axi_arsize),
        .d_arburst(ext_m_axi_arburst), .d_arlock(ext_m_axi_arlock),
        .d_arcache(ext_m_axi_arcache), .d_arprot(ext_m_axi_arprot),
        .d_arqos(ext_m_axi_arqos), .d_arvalid(ext_m_axi_arvalid),
        .d_arready(ext_m_axi_arready), .d_rid(ext_rid_int),
        .d_rdata(ext_m_axi_rdata), .d_rresp(ext_m_axi_rresp),
        .d_rlast(ext_m_axi_rlast), .d_rvalid(ext_m_axi_rvalid),
        .d_rready(ext_m_axi_rready)
    );
    end else begin : internal_memory_only
        assign m1_axi_awid = dma_axi_awid;
        assign m1_axi_awaddr = dma_axi_awaddr;
        assign m1_axi_awlen = dma_axi_awlen;
        assign m1_axi_awsize = dma_axi_awsize;
        assign m1_axi_awburst = dma_axi_awburst;
        assign m1_axi_awlock = dma_axi_awlock;
        assign m1_axi_awcache = dma_axi_awcache;
        assign m1_axi_awprot = dma_axi_awprot;
        assign m1_axi_awvalid = dma_axi_awvalid;
        assign m1_axi_wdata = dma_axi_wdata;
        assign m1_axi_wstrb = dma_axi_wstrb;
        assign m1_axi_wlast = dma_axi_wlast;
        assign m1_axi_wvalid = dma_axi_wvalid;
        assign m1_axi_bready = dma_axi_bready;
        assign m1_axi_arid = dma_axi_arid;
        assign m1_axi_araddr = dma_axi_araddr;
        assign m1_axi_arlen = dma_axi_arlen;
        assign m1_axi_arsize = dma_axi_arsize;
        assign m1_axi_arburst = dma_axi_arburst;
        assign m1_axi_arlock = dma_axi_arlock;
        assign m1_axi_arcache = dma_axi_arcache;
        assign m1_axi_arprot = dma_axi_arprot;
        assign m1_axi_arvalid = dma_axi_arvalid;
        assign m1_axi_rready = dma_axi_rready;
        assign dma_axi_awready = m1_axi_awready;
        assign dma_axi_wready = m1_axi_wready;
        assign dma_axi_bid = m1_axi_bid;
        assign dma_axi_bresp = m1_axi_bresp;
        assign dma_axi_bvalid = m1_axi_bvalid;
        assign dma_axi_arready = m1_axi_arready;
        assign dma_axi_rid = m1_axi_rid;
        assign dma_axi_rdata = m1_axi_rdata;
        assign dma_axi_rresp = m1_axi_rresp;
        assign dma_axi_rlast = m1_axi_rlast;
        assign dma_axi_rvalid = m1_axi_rvalid;
        assign ext_awid_int = 0;
        assign ext_arid_int = 0;
        assign ext_m_axi_awaddr = 0;
        assign ext_m_axi_awlen = 0;
        assign ext_m_axi_awsize = 0;
        assign ext_m_axi_awburst = 0;
        assign ext_m_axi_awlock = 0;
        assign ext_m_axi_awcache = 0;
        assign ext_m_axi_awprot = 0;
        assign ext_m_axi_awqos = 0;
        assign ext_m_axi_awvalid = 0;
        assign ext_m_axi_wdata = 0;
        assign ext_m_axi_wstrb = 0;
        assign ext_m_axi_wlast = 0;
        assign ext_m_axi_wvalid = 0;
        assign ext_m_axi_bready = 0;
        assign ext_m_axi_araddr = 0;
        assign ext_m_axi_arlen = 0;
        assign ext_m_axi_arsize = 0;
        assign ext_m_axi_arburst = 0;
        assign ext_m_axi_arlock = 0;
        assign ext_m_axi_arcache = 0;
        assign ext_m_axi_arprot = 0;
        assign ext_m_axi_arqos = 0;
        assign ext_m_axi_arvalid = 0;
        assign ext_m_axi_rready = 0;
    end endgenerate

    // Exposed fourth slave from the existing interconnect.
    wire [ID_WIDTH-1:0]       s3_axi_awid;
    wire [SLAVE_ADDR_WIDTH-1:0] s3_axi_awaddr;
    wire [7:0]                s3_axi_awlen;
    wire [2:0]                s3_axi_awsize;
    wire [1:0]                s3_axi_awburst;
    wire                      s3_axi_awlock;
    wire [3:0]                s3_axi_awcache;
    wire [2:0]                s3_axi_awprot;
    wire                      s3_axi_awvalid;
    wire                      s3_axi_awready;
    wire [DATA_WIDTH-1:0]     s3_axi_wdata;
    wire [STRB_WIDTH-1:0]     s3_axi_wstrb;
    wire                      s3_axi_wlast;
    wire                      s3_axi_wvalid;
    wire                      s3_axi_wready;
    wire [ID_WIDTH-1:0]       s3_axi_bid;
    wire [1:0]                s3_axi_bresp;
    wire                      s3_axi_bvalid;
    wire                      s3_axi_bready;
    wire [ID_WIDTH-1:0]       s3_axi_arid;
    wire [SLAVE_ADDR_WIDTH-1:0] s3_axi_araddr;
    wire [7:0]                s3_axi_arlen;
    wire [2:0]                s3_axi_arsize;
    wire [1:0]                s3_axi_arburst;
    wire                      s3_axi_arlock;
    wire [3:0]                s3_axi_arcache;
    wire [2:0]                s3_axi_arprot;
    wire                      s3_axi_arvalid;
    wire                      s3_axi_arready;
    wire [ID_WIDTH-1:0]       s3_axi_rid;
    wire [DATA_WIDTH-1:0]     s3_axi_rdata;
    wire [1:0]                s3_axi_rresp;
    wire                      s3_axi_rlast;
    wire                      s3_axi_rvalid;
    wire                      s3_axi_rready;

    axi_interconnect_2x4_top #(
        .S_COUNT(2), .M_COUNT(4), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH), .SLAVE_ADDR_WIDTH(SLAVE_ADDR_WIDTH),
        .RAM0_INIT_FILE(MEM_INIT_FILE)
    ) fabric (
        .clk(clk), .rst(fabric_rst),
        .m0_axi_awid(m0_axi_awid), .m0_axi_awaddr(m0_axi_awaddr),
        .m0_axi_awlen(m0_axi_awlen), .m0_axi_awsize(m0_axi_awsize),
        .m0_axi_awburst(m0_axi_awburst), .m0_axi_awlock(m0_axi_awlock),
        .m0_axi_awcache(m0_axi_awcache), .m0_axi_awprot(m0_axi_awprot),
        .m0_axi_awvalid(m0_axi_awvalid), .m0_axi_awready(m0_axi_awready),
        .m0_axi_wdata(m0_axi_wdata), .m0_axi_wstrb(m0_axi_wstrb),
        .m0_axi_wlast(m0_axi_wlast), .m0_axi_wvalid(m0_axi_wvalid),
        .m0_axi_wready(m0_axi_wready), .m0_axi_bid(m0_axi_bid),
        .m0_axi_bresp(m0_axi_bresp), .m0_axi_bvalid(m0_axi_bvalid),
        .m0_axi_bready(m0_axi_bready), .m0_axi_arid(m0_axi_arid),
        .m0_axi_araddr(m0_axi_araddr), .m0_axi_arlen(m0_axi_arlen),
        .m0_axi_arsize(m0_axi_arsize), .m0_axi_arburst(m0_axi_arburst),
        .m0_axi_arlock(m0_axi_arlock), .m0_axi_arcache(m0_axi_arcache),
        .m0_axi_arprot(m0_axi_arprot), .m0_axi_arvalid(m0_axi_arvalid),
        .m0_axi_arready(m0_axi_arready), .m0_axi_rid(m0_axi_rid),
        .m0_axi_rdata(m0_axi_rdata), .m0_axi_rresp(m0_axi_rresp),
        .m0_axi_rlast(m0_axi_rlast), .m0_axi_rvalid(m0_axi_rvalid),
        .m0_axi_rready(m0_axi_rready),
        .m1_axi_awid(m1_axi_awid), .m1_axi_awaddr(m1_axi_awaddr),
        .m1_axi_awlen(m1_axi_awlen), .m1_axi_awsize(m1_axi_awsize),
        .m1_axi_awburst(m1_axi_awburst), .m1_axi_awlock(m1_axi_awlock),
        .m1_axi_awcache(m1_axi_awcache), .m1_axi_awprot(m1_axi_awprot),
        .m1_axi_awvalid(m1_axi_awvalid), .m1_axi_awready(m1_axi_awready),
        .m1_axi_wdata(m1_axi_wdata), .m1_axi_wstrb(m1_axi_wstrb),
        .m1_axi_wlast(m1_axi_wlast), .m1_axi_wvalid(m1_axi_wvalid),
        .m1_axi_wready(m1_axi_wready), .m1_axi_bid(m1_axi_bid),
        .m1_axi_bresp(m1_axi_bresp), .m1_axi_bvalid(m1_axi_bvalid),
        .m1_axi_bready(m1_axi_bready), .m1_axi_arid(m1_axi_arid),
        .m1_axi_araddr(m1_axi_araddr), .m1_axi_arlen(m1_axi_arlen),
        .m1_axi_arsize(m1_axi_arsize), .m1_axi_arburst(m1_axi_arburst),
        .m1_axi_arlock(m1_axi_arlock), .m1_axi_arcache(m1_axi_arcache),
        .m1_axi_arprot(m1_axi_arprot), .m1_axi_arvalid(m1_axi_arvalid),
        .m1_axi_arready(m1_axi_arready), .m1_axi_rid(m1_axi_rid),
        .m1_axi_rdata(m1_axi_rdata), .m1_axi_rresp(m1_axi_rresp),
        .m1_axi_rlast(m1_axi_rlast), .m1_axi_rvalid(m1_axi_rvalid),
        .m1_axi_rready(m1_axi_rready),
        .s3_axi_awid(s3_axi_awid), .s3_axi_awaddr(s3_axi_awaddr),
        .s3_axi_awlen(s3_axi_awlen), .s3_axi_awsize(s3_axi_awsize),
        .s3_axi_awburst(s3_axi_awburst), .s3_axi_awlock(s3_axi_awlock),
        .s3_axi_awcache(s3_axi_awcache), .s3_axi_awprot(s3_axi_awprot),
        .s3_axi_awvalid(s3_axi_awvalid), .s3_axi_awready(s3_axi_awready),
        .s3_axi_wdata(s3_axi_wdata), .s3_axi_wstrb(s3_axi_wstrb),
        .s3_axi_wlast(s3_axi_wlast), .s3_axi_wvalid(s3_axi_wvalid),
        .s3_axi_wready(s3_axi_wready), .s3_axi_bid(s3_axi_bid),
        .s3_axi_bresp(s3_axi_bresp), .s3_axi_bvalid(s3_axi_bvalid),
        .s3_axi_bready(s3_axi_bready), .s3_axi_arid(s3_axi_arid),
        .s3_axi_araddr(s3_axi_araddr), .s3_axi_arlen(s3_axi_arlen),
        .s3_axi_arsize(s3_axi_arsize), .s3_axi_arburst(s3_axi_arburst),
        .s3_axi_arlock(s3_axi_arlock), .s3_axi_arcache(s3_axi_arcache),
        .s3_axi_arprot(s3_axi_arprot), .s3_axi_arvalid(s3_axi_arvalid),
        .s3_axi_arready(s3_axi_arready), .s3_axi_rid(s3_axi_rid),
        .s3_axi_rdata(s3_axi_rdata), .s3_axi_rresp(s3_axi_rresp),
        .s3_axi_rlast(s3_axi_rlast), .s3_axi_rvalid(s3_axi_rvalid),
        .s3_axi_rready(s3_axi_rready)
    );

    axi_slh_peripherals #(
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(SLAVE_ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH), .CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(BAUD_RATE)
    ) peripherals (
        .clk(clk), .rst(peripherals_rst),
        .s_axi_awid(s3_axi_awid), .s_axi_awaddr(s3_axi_awaddr),
        .s_axi_awlen(s3_axi_awlen), .s_axi_awsize(s3_axi_awsize),
        .s_axi_awburst(s3_axi_awburst), .s_axi_awlock(s3_axi_awlock),
        .s_axi_awcache(s3_axi_awcache), .s_axi_awprot(s3_axi_awprot),
        .s_axi_awvalid(s3_axi_awvalid), .s_axi_awready(s3_axi_awready),
        .s_axi_wdata(s3_axi_wdata), .s_axi_wstrb(s3_axi_wstrb),
        .s_axi_wlast(s3_axi_wlast), .s_axi_wvalid(s3_axi_wvalid),
        .s_axi_wready(s3_axi_wready), .s_axi_bid(s3_axi_bid),
        .s_axi_bresp(s3_axi_bresp), .s_axi_bvalid(s3_axi_bvalid),
        .s_axi_bready(s3_axi_bready), .s_axi_arid(s3_axi_arid),
        .s_axi_araddr(s3_axi_araddr), .s_axi_arlen(s3_axi_arlen),
        .s_axi_arsize(s3_axi_arsize), .s_axi_arburst(s3_axi_arburst),
        .s_axi_arlock(s3_axi_arlock), .s_axi_arcache(s3_axi_arcache),
        .s_axi_arprot(s3_axi_arprot), .s_axi_arvalid(s3_axi_arvalid),
        .s_axi_arready(s3_axi_arready), .s_axi_rid(s3_axi_rid),
        .s_axi_rdata(s3_axi_rdata), .s_axi_rresp(s3_axi_rresp),
        .s_axi_rlast(s3_axi_rlast), .s_axi_rvalid(s3_axi_rvalid),
        .s_axi_rready(s3_axi_rready),
        .dma_axil_awaddr(dma_axil_awaddr),
        .dma_axil_awprot(dma_axil_awprot),
        .dma_axil_awvalid(dma_axil_awvalid),
        .dma_axil_awready(dma_axil_awready),
        .dma_axil_wdata(dma_axil_wdata), .dma_axil_wstrb(dma_axil_wstrb),
        .dma_axil_wvalid(dma_axil_wvalid), .dma_axil_wready(dma_axil_wready),
        .dma_axil_bresp(dma_axil_bresp), .dma_axil_bvalid(dma_axil_bvalid),
        .dma_axil_bready(dma_axil_bready),
        .dma_axil_araddr(dma_axil_araddr),
        .dma_axil_arprot(dma_axil_arprot),
        .dma_axil_arvalid(dma_axil_arvalid),
        .dma_axil_arready(dma_axil_arready),
        .dma_axil_rdata(dma_axil_rdata), .dma_axil_rresp(dma_axil_rresp),
        .dma_axil_rvalid(dma_axil_rvalid), .dma_axil_rready(dma_axil_rready),
        .dma_hash_s_data(dma_hash_s_data), .dma_hash_s_keep(dma_hash_s_keep),
        .dma_hash_s_valid(dma_hash_s_valid), .dma_hash_s_ready(dma_hash_s_ready),
        .dma_hash_s_last(dma_hash_s_last), .dma_hash_m_data(dma_hash_m_data),
        .dma_hash_m_keep(dma_hash_m_keep), .dma_hash_m_valid(dma_hash_m_valid),
        .dma_hash_m_ready(dma_hash_m_ready), .dma_hash_m_last(dma_hash_m_last),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx), .gpio_out(gpio_out), .shake_irq(shake_irq),
        .uart_irq(uart_irq), .timer_irq(timer_irq)
    );

    wire _unused = &{1'b0, m0_axi_bid, m0_axi_rid, m0_axi_rlast,
                     dma_axi_awregion, dma_axi_arregion, ext_m_axi_bid[4],
                     ext_m_axi_rid[4], cpu_eoi, trace_valid,
                     trace_data, pcpi_valid, pcpi_insn, pcpi_rs1, pcpi_rs2};
endmodule

`resetall
