`timescale 1ns/1ps
`default_nettype none

// AXI4 slave for the 64 KiB peripheral window at 0x0003_0000.
// Only single-beat 32-bit transactions are accepted.  Sub-regions:
//   0x0000..0x00ff  SLH-DSA SHAKE256 F/H accelerator
//   0x1000..0x10ff  UART
//   0x2000..0x20ff  timer/GPIO
//   0x3000..0x30ff  DMA/IOMMU AXI4-Lite control bridge
// The wrapper adds AXI IDs/RLAST around the AXI4-Lite SHAKE IP and returns
// SLVERR for bursts, unaligned accesses and unmapped registers.
module axi_slh_peripherals #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 16,
    parameter integer ID_WIDTH   = 4,
    parameter integer CLOCK_HZ   = 100_000_000,
    parameter integer BAUD_RATE  = 115_200
) (
    input  wire                      clk,
    input  wire                      rst,

    input  wire [ID_WIDTH-1:0]       s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [7:0]                s_axi_awlen,
    input  wire [2:0]                s_axi_awsize,
    input  wire [1:0]                s_axi_awburst,
    input  wire                      s_axi_awlock,
    input  wire [3:0]                s_axi_awcache,
    input  wire [2:0]                s_axi_awprot,
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,
    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                      s_axi_wlast,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,
    output reg  [ID_WIDTH-1:0]       s_axi_bid,
    output reg  [1:0]                s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,

    input  wire [ID_WIDTH-1:0]       s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [7:0]                s_axi_arlen,
    input  wire [2:0]                s_axi_arsize,
    input  wire [1:0]                s_axi_arburst,
    input  wire                      s_axi_arlock,
    input  wire [3:0]                s_axi_arcache,
    input  wire [2:0]                s_axi_arprot,
    input  wire                      s_axi_arvalid,
    output wire                      s_axi_arready,
    output reg  [ID_WIDTH-1:0]       s_axi_rid,
    output reg  [DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                s_axi_rresp,
    output reg                       s_axi_rlast,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready,

    output wire [7:0]                dma_axil_awaddr,
    output wire [2:0]                dma_axil_awprot,
    output wire                      dma_axil_awvalid,
    input  wire                      dma_axil_awready,
    output wire [31:0]               dma_axil_wdata,
    output wire [3:0]                dma_axil_wstrb,
    output wire                      dma_axil_wvalid,
    input  wire                      dma_axil_wready,
    input  wire [1:0]                dma_axil_bresp,
    input  wire                      dma_axil_bvalid,
    output wire                      dma_axil_bready,
    output wire [7:0]                dma_axil_araddr,
    output wire [2:0]                dma_axil_arprot,
    output wire                      dma_axil_arvalid,
    input  wire                      dma_axil_arready,
    input  wire [31:0]               dma_axil_rdata,
    input  wire [1:0]                dma_axil_rresp,
    input  wire                      dma_axil_rvalid,
    output wire                      dma_axil_rready,

    input  wire [31:0]               dma_hash_s_data,
    input  wire [3:0]                dma_hash_s_keep,
    input  wire                      dma_hash_s_valid,
    output wire                      dma_hash_s_ready,
    input  wire                      dma_hash_s_last,
    output wire [31:0]               dma_hash_m_data,
    output wire [3:0]                dma_hash_m_keep,
    output wire                      dma_hash_m_valid,
    input  wire                      dma_hash_m_ready,
    output wire                      dma_hash_m_last,
    input  wire                      uart_rx,
    output wire                      uart_tx,
    output wire [31:0]               gpio_out,
    output wire                      shake_irq,
    output wire                      uart_irq,
    output wire                      timer_irq
);
    localparam [1:0] AXI_OKAY   = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;

    localparam [2:0] WR_CAPTURE   = 3'd0,
                     WR_SHA_SEND  = 3'd1,
                     WR_SHA_RESP  = 3'd2,
                     WR_DMA_SEND  = 3'd3,
                     WR_DMA_RESP  = 3'd4,
                     WR_RESPONSE  = 3'd5;
    localparam [2:0] RD_CAPTURE   = 3'd0,
                     RD_SHA_ADDR  = 3'd1,
                     RD_SHA_DATA  = 3'd2,
                     RD_DMA_ADDR  = 3'd3,
                     RD_DMA_DATA  = 3'd4,
                     RD_RESPONSE  = 3'd5;

    reg [2:0] wr_state_q, rd_state_q;

    reg                    aw_hold_valid_q;
    reg [ID_WIDTH-1:0]     awid_hold_q;
    reg [ADDR_WIDTH-1:0]   awaddr_hold_q;
    reg [7:0]              awlen_hold_q;
    reg [2:0]              awsize_hold_q;
    reg [1:0]              awburst_hold_q;
    reg                    awlock_hold_q;
    reg                    w_hold_valid_q;
    reg [DATA_WIDTH-1:0]   wdata_hold_q;
    reg [(DATA_WIDTH/8)-1:0] wstrb_hold_q;
    reg                    wlast_hold_q;

    reg                    ar_hold_valid_q;
    reg [ID_WIDTH-1:0]     arid_hold_q;
    reg [ADDR_WIDTH-1:0]   araddr_hold_q;
    reg [7:0]              arlen_hold_q;
    reg [2:0]              arsize_hold_q;
    reg [1:0]              arburst_hold_q;
    reg                    arlock_hold_q;

    assign s_axi_awready = (wr_state_q == WR_CAPTURE) && !aw_hold_valid_q;
    assign s_axi_wready  = (wr_state_q == WR_CAPTURE) && !w_hold_valid_q;
    assign s_axi_arready = (rd_state_q == RD_CAPTURE) && !ar_hold_valid_q;

    // AXI4-Lite connection to the existing accelerator.
    reg         sha_awvalid_q;
    reg         sha_wvalid_q;
    reg         sha_arvalid_q;
    reg         dma_awvalid_q;
    reg         dma_wvalid_q;
    reg         dma_arvalid_q;
    wire        sha_awready;
    wire        sha_wready;
    wire [1:0]  sha_bresp;
    wire        sha_bvalid;
    wire        sha_arready;
    wire [31:0] sha_rdata;
    wire [1:0]  sha_rresp;
    wire        sha_rvalid;

    reg stream_arm_q, stream_abort_q;
    wire stream_owns, stream_busy, stream_done, stream_error;
    wire [7:0] stream_awaddr, stream_araddr;
    wire [31:0] stream_wdata;
    wire stream_awvalid, stream_wvalid, stream_bready;
    wire stream_arvalid, stream_rready;
    slh_dma_stream_adapter dma_hash_stream (
        .clk(clk), .rst(rst), .arm(stream_arm_q), .abort_op(stream_abort_q),
        .owns_hash(stream_owns), .busy(stream_busy), .done(stream_done), .error(stream_error),
        .s_data(dma_hash_s_data), .s_keep(dma_hash_s_keep),
        .s_valid(dma_hash_s_valid), .s_ready(dma_hash_s_ready), .s_last(dma_hash_s_last),
        .m_data(dma_hash_m_data), .m_keep(dma_hash_m_keep),
        .m_valid(dma_hash_m_valid), .m_ready(dma_hash_m_ready), .m_last(dma_hash_m_last),
        .awaddr(stream_awaddr), .awvalid(stream_awvalid), .awready(sha_awready),
        .wdata(stream_wdata), .wvalid(stream_wvalid), .wready(sha_wready),
        .bresp(sha_bresp), .bvalid(sha_bvalid), .bready(stream_bready),
        .araddr(stream_araddr), .arvalid(stream_arvalid), .arready(sha_arready),
        .rdata(sha_rdata), .rresp(sha_rresp), .rvalid(sha_rvalid), .rready(stream_rready)
    );

    slh_dsa_shake_axi_lite #(
        .C_S_AXI_ADDR_WIDTH(8),
        .C_S_AXI_DATA_WIDTH(32)
    ) shake_accel (
        .s_axi_aclk(clk),
        .s_axi_aresetn(!rst),
        .s_axi_awaddr(stream_owns ? stream_awaddr : awaddr_hold_q[7:0]),
        .s_axi_awvalid(stream_owns ? stream_awvalid : sha_awvalid_q),
        .s_axi_awready(sha_awready),
        .s_axi_wdata(stream_owns ? stream_wdata : wdata_hold_q),
        .s_axi_wstrb(stream_owns ? 4'hf : wstrb_hold_q),
        .s_axi_wvalid(stream_owns ? stream_wvalid : sha_wvalid_q),
        .s_axi_wready(sha_wready),
        .s_axi_bresp(sha_bresp),
        .s_axi_bvalid(sha_bvalid),
        .s_axi_bready(stream_owns ? stream_bready : (wr_state_q == WR_SHA_RESP)),
        .s_axi_araddr(stream_owns ? stream_araddr : araddr_hold_q[7:0]),
        .s_axi_arvalid(stream_owns ? stream_arvalid : sha_arvalid_q),
        .s_axi_arready(sha_arready),
        .s_axi_rdata(sha_rdata),
        .s_axi_rresp(sha_rresp),
        .s_axi_rvalid(sha_rvalid),
        .s_axi_rready(stream_owns ? stream_rready : (rd_state_q == RD_SHA_DATA)),
        .irq(shake_irq)
    );

    // The DMA register block is instantiated at SoC level because its AXI4
    // memory master must connect directly to fabric master port M1.  This
    // wrapper translates the fourth MMIO page to that AXI4-Lite slave.
    assign dma_axil_awaddr  = awaddr_hold_q[7:0];
    assign dma_axil_awprot  = 3'b000;
    assign dma_axil_awvalid = dma_awvalid_q;
    assign dma_axil_wdata   = wdata_hold_q;
    assign dma_axil_wstrb   = wstrb_hold_q;
    assign dma_axil_wvalid  = dma_wvalid_q;
    assign dma_axil_bready  = (wr_state_q == WR_DMA_RESP);
    assign dma_axil_araddr  = araddr_hold_q[7:0];
    assign dma_axil_arprot  = 3'b000;
    assign dma_axil_arvalid = dma_arvalid_q;
    assign dma_axil_rready  = (rd_state_q == RD_DMA_DATA);

    reg         uart_wr_en_q, uart_rd_en_q;
    reg  [7:0]  uart_wr_addr_q, uart_rd_addr_q;
    reg  [31:0] uart_wr_data_q;
    reg  [3:0]  uart_wr_strb_q;
    wire        uart_wr_error;
    wire [31:0] uart_rd_data;
    wire        uart_rd_error;

    soc_uart #(.CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(BAUD_RATE)) uart (
        .clk(clk), .rst_n(!rst), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .irq(uart_irq),
        .wr_en(uart_wr_en_q), .wr_addr(awaddr_hold_q[7:0]),
        .wr_data(wdata_hold_q), .wr_strb(wstrb_hold_q),
        .wr_error(uart_wr_error),
        .rd_en(uart_rd_en_q), .rd_addr(araddr_hold_q[7:0]),
        .rd_data(uart_rd_data), .rd_error(uart_rd_error)
    );

    reg         timer_wr_en_q, timer_rd_en_q;
    reg  [7:0]  timer_wr_addr_q, timer_rd_addr_q;
    reg  [31:0] timer_wr_data_q;
    reg  [3:0]  timer_wr_strb_q;
    wire        timer_wr_error;
    wire [31:0] timer_rd_data;
    wire        timer_rd_error;

    soc_timer_gpio #(.CLOCK_HZ(CLOCK_HZ)) timer_gpio (
        .clk(clk), .rst_n(!rst), .irq(timer_irq), .gpio_out(gpio_out),
        .wr_en(timer_wr_en_q), .wr_addr(awaddr_hold_q[7:0]),
        .wr_data(wdata_hold_q), .wr_strb(wstrb_hold_q),
        .wr_error(timer_wr_error),
        .rd_en(timer_rd_en_q), .rd_addr(araddr_hold_q[7:0]),
        .rd_data(timer_rd_data), .rd_error(timer_rd_error)
    );

    wire write_protocol_error =
        (awlen_hold_q != 0) || (awsize_hold_q != 3'b010) ||
        (awburst_hold_q == 2'b11) || awlock_hold_q ||
        (awaddr_hold_q[1:0] != 2'b00) || !wlast_hold_q;
    wire read_protocol_error =
        (arlen_hold_q != 0) || (arsize_hold_q != 3'b010) ||
        (arburst_hold_q == 2'b11) || arlock_hold_q ||
        (araddr_hold_q[1:0] != 2'b00);

    always @(posedge clk) begin
        if (rst) begin
            wr_state_q       <= WR_CAPTURE;
            aw_hold_valid_q  <= 1'b0;
            awid_hold_q      <= {ID_WIDTH{1'b0}};
            awaddr_hold_q    <= {ADDR_WIDTH{1'b0}};
            awlen_hold_q     <= 8'd0;
            awsize_hold_q    <= 3'd0;
            awburst_hold_q   <= 2'd0;
            awlock_hold_q    <= 1'b0;
            w_hold_valid_q   <= 1'b0;
            wdata_hold_q     <= {DATA_WIDTH{1'b0}};
            wstrb_hold_q     <= {(DATA_WIDTH/8){1'b0}};
            wlast_hold_q     <= 1'b0;
            s_axi_bid        <= {ID_WIDTH{1'b0}};
            s_axi_bresp      <= AXI_OKAY;
            s_axi_bvalid     <= 1'b0;
            sha_awvalid_q    <= 1'b0;
            sha_wvalid_q     <= 1'b0;
            dma_awvalid_q    <= 1'b0;
            dma_wvalid_q     <= 1'b0;
            stream_arm_q     <= 1'b0;
            stream_abort_q   <= 1'b0;
            uart_wr_en_q     <= 1'b0;
            uart_wr_addr_q   <= 8'd0;
            uart_wr_data_q   <= 32'd0;
            uart_wr_strb_q   <= 4'd0;
            timer_wr_en_q    <= 1'b0;
            timer_wr_addr_q  <= 8'd0;
            timer_wr_data_q  <= 32'd0;
            timer_wr_strb_q  <= 4'd0;
        end else begin
            uart_wr_en_q  <= 1'b0;
            timer_wr_en_q <= 1'b0;
            stream_arm_q <= 1'b0;
            stream_abort_q <= 1'b0;

            case (wr_state_q)
                WR_CAPTURE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        aw_hold_valid_q <= 1'b1;
                        awid_hold_q     <= s_axi_awid;
                        awaddr_hold_q   <= s_axi_awaddr;
                        awlen_hold_q    <= s_axi_awlen;
                        awsize_hold_q   <= s_axi_awsize;
                        awburst_hold_q  <= s_axi_awburst;
                        awlock_hold_q   <= s_axi_awlock;
                    end
                    if (s_axi_wvalid && s_axi_wready) begin
                        w_hold_valid_q <= 1'b1;
                        wdata_hold_q   <= s_axi_wdata;
                        wstrb_hold_q   <= s_axi_wstrb;
                        wlast_hold_q   <= s_axi_wlast;
                    end

                    if (aw_hold_valid_q && w_hold_valid_q) begin
                        s_axi_bid       <= awid_hold_q;
                        aw_hold_valid_q <= 1'b0;
                        w_hold_valid_q  <= 1'b0;

                        if (write_protocol_error) begin
                            s_axi_bresp  <= AXI_SLVERR;
                            s_axi_bvalid <= 1'b1;
                            wr_state_q   <= WR_RESPONSE;
                        end else begin
                            case (awaddr_hold_q[15:12])
                                4'h0: begin
                                    if (awaddr_hold_q[11:8] != 0 || stream_owns) begin
                                        s_axi_bresp  <= AXI_SLVERR;
                                        s_axi_bvalid <= 1'b1;
                                        wr_state_q   <= WR_RESPONSE;
                                    end else begin
                                        sha_awvalid_q <= 1'b1;
                                        sha_wvalid_q  <= 1'b1;
                                        wr_state_q    <= WR_SHA_SEND;
                                    end
                                end
                                4'h1: begin
                                    uart_wr_addr_q <= awaddr_hold_q[7:0];
                                    uart_wr_data_q <= wdata_hold_q;
                                    uart_wr_strb_q <= wstrb_hold_q;
                                    if (!uart_wr_error) uart_wr_en_q <= 1'b1;
                                    s_axi_bresp  <= uart_wr_error ? AXI_SLVERR : AXI_OKAY;
                                    s_axi_bvalid <= 1'b1;
                                    wr_state_q   <= WR_RESPONSE;
                                end
                                4'h2: begin
                                    timer_wr_addr_q <= awaddr_hold_q[7:0];
                                    timer_wr_data_q <= wdata_hold_q;
                                    timer_wr_strb_q <= wstrb_hold_q;
                                    if (!timer_wr_error) timer_wr_en_q <= 1'b1;
                                    s_axi_bresp  <= timer_wr_error ? AXI_SLVERR : AXI_OKAY;
                                    s_axi_bvalid <= 1'b1;
                                    wr_state_q   <= WR_RESPONSE;
                                end
                                4'h3: begin
                                    if (awaddr_hold_q[11:8] != 0) begin
                                        s_axi_bresp  <= AXI_SLVERR;
                                        s_axi_bvalid <= 1'b1;
                                        wr_state_q   <= WR_RESPONSE;
                                    end else begin
                                        dma_awvalid_q <= 1'b1;
                                        dma_wvalid_q  <= 1'b1;
                                        wr_state_q    <= WR_DMA_SEND;
                                    end
                                end
                                4'h4: begin
                                    s_axi_bvalid<=1'b1; wr_state_q<=WR_RESPONSE;
                                    if (awaddr_hold_q[11:0]!=0 || !wstrb_hold_q[0] ||
                                        (wdata_hold_q[0] && stream_busy)) s_axi_bresp<=AXI_SLVERR;
                                    else begin
                                        s_axi_bresp<=AXI_OKAY;
                                        stream_arm_q<=wdata_hold_q[0];
                                        stream_abort_q<=wdata_hold_q[1];
                                    end
                                end
                                default: begin
                                    s_axi_bresp  <= AXI_SLVERR;
                                    s_axi_bvalid <= 1'b1;
                                    wr_state_q   <= WR_RESPONSE;
                                end
                            endcase
                        end
                    end
                end
                WR_SHA_SEND: begin
                    if (sha_awvalid_q && sha_awready) sha_awvalid_q <= 1'b0;
                    if (sha_wvalid_q && sha_wready) sha_wvalid_q <= 1'b0;
                    if ((!sha_awvalid_q || sha_awready) &&
                        (!sha_wvalid_q || sha_wready))
                        wr_state_q <= WR_SHA_RESP;
                end
                WR_SHA_RESP: begin
                    if (sha_bvalid) begin
                        s_axi_bresp  <= sha_bresp;
                        s_axi_bvalid <= 1'b1;
                        wr_state_q   <= WR_RESPONSE;
                    end
                end
                WR_DMA_SEND: begin
                    if (dma_awvalid_q && dma_axil_awready)
                        dma_awvalid_q <= 1'b0;
                    if (dma_wvalid_q && dma_axil_wready)
                        dma_wvalid_q <= 1'b0;
                    if ((!dma_awvalid_q || dma_axil_awready) &&
                        (!dma_wvalid_q || dma_axil_wready))
                        wr_state_q <= WR_DMA_RESP;
                end
                WR_DMA_RESP: begin
                    if (dma_axil_bvalid) begin
                        s_axi_bresp  <= dma_axil_bresp;
                        s_axi_bvalid <= 1'b1;
                        wr_state_q   <= WR_RESPONSE;
                    end
                end
                WR_RESPONSE: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state_q   <= WR_CAPTURE;
                    end
                end
                default: wr_state_q <= WR_CAPTURE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_state_q       <= RD_CAPTURE;
            ar_hold_valid_q  <= 1'b0;
            arid_hold_q      <= {ID_WIDTH{1'b0}};
            araddr_hold_q    <= {ADDR_WIDTH{1'b0}};
            arlen_hold_q     <= 8'd0;
            arsize_hold_q    <= 3'd0;
            arburst_hold_q   <= 2'd0;
            arlock_hold_q    <= 1'b0;
            s_axi_rid        <= {ID_WIDTH{1'b0}};
            s_axi_rdata      <= {DATA_WIDTH{1'b0}};
            s_axi_rresp      <= AXI_OKAY;
            s_axi_rlast      <= 1'b0;
            s_axi_rvalid     <= 1'b0;
            sha_arvalid_q    <= 1'b0;
            dma_arvalid_q    <= 1'b0;
            uart_rd_en_q     <= 1'b0;
            uart_rd_addr_q   <= 8'd0;
            timer_rd_en_q    <= 1'b0;
            timer_rd_addr_q  <= 8'd0;
        end else begin
            uart_rd_en_q  <= 1'b0;
            timer_rd_en_q <= 1'b0;

            case (rd_state_q)
                RD_CAPTURE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        ar_hold_valid_q <= 1'b1;
                        arid_hold_q     <= s_axi_arid;
                        araddr_hold_q   <= s_axi_araddr;
                        arlen_hold_q    <= s_axi_arlen;
                        arsize_hold_q   <= s_axi_arsize;
                        arburst_hold_q  <= s_axi_arburst;
                        arlock_hold_q   <= s_axi_arlock;
                    end

                    if (ar_hold_valid_q) begin
                        ar_hold_valid_q <= 1'b0;
                        s_axi_rid       <= arid_hold_q;
                        s_axi_rlast     <= 1'b1;

                        if (read_protocol_error) begin
                            s_axi_rdata  <= 32'd0;
                            s_axi_rresp  <= AXI_SLVERR;
                            s_axi_rvalid <= 1'b1;
                            rd_state_q   <= RD_RESPONSE;
                        end else begin
                            case (araddr_hold_q[15:12])
                                4'h0: begin
                                    if (araddr_hold_q[11:8] != 0 || stream_owns) begin
                                        s_axi_rdata  <= 32'd0;
                                        s_axi_rresp  <= AXI_SLVERR;
                                        s_axi_rvalid <= 1'b1;
                                        rd_state_q   <= RD_RESPONSE;
                                    end else begin
                                        sha_arvalid_q <= 1'b1;
                                        rd_state_q    <= RD_SHA_ADDR;
                                    end
                                end
                                4'h1: begin
                                    uart_rd_addr_q <= araddr_hold_q[7:0];
                                    if (!uart_rd_error) uart_rd_en_q <= 1'b1;
                                    s_axi_rdata  <= uart_rd_data;
                                    s_axi_rresp  <= uart_rd_error ? AXI_SLVERR : AXI_OKAY;
                                    s_axi_rvalid <= 1'b1;
                                    rd_state_q   <= RD_RESPONSE;
                                end
                                4'h2: begin
                                    timer_rd_addr_q <= araddr_hold_q[7:0];
                                    if (!timer_rd_error) timer_rd_en_q <= 1'b1;
                                    s_axi_rdata  <= timer_rd_data;
                                    s_axi_rresp  <= timer_rd_error ? AXI_SLVERR : AXI_OKAY;
                                    s_axi_rvalid <= 1'b1;
                                    rd_state_q   <= RD_RESPONSE;
                                end
                                4'h3: begin
                                    if (araddr_hold_q[11:8] != 0) begin
                                        s_axi_rdata  <= 32'd0;
                                        s_axi_rresp  <= AXI_SLVERR;
                                        s_axi_rvalid <= 1'b1;
                                        rd_state_q   <= RD_RESPONSE;
                                    end else begin
                                        dma_arvalid_q <= 1'b1;
                                        rd_state_q    <= RD_DMA_ADDR;
                                    end
                                end
                                4'h4: begin
                                    s_axi_rvalid<=1'b1; rd_state_q<=RD_RESPONSE;
                                    s_axi_rresp<=AXI_OKAY;
                                    case (araddr_hold_q[11:0])
                                        12'h004: s_axi_rdata<={29'd0,stream_error,stream_done,stream_busy};
                                        12'h008: s_axi_rdata<=32'h53445301;
                                        default: begin s_axi_rdata<=0; s_axi_rresp<=AXI_SLVERR; end
                                    endcase
                                end
                                default: begin
                                    s_axi_rdata  <= 32'd0;
                                    s_axi_rresp  <= AXI_SLVERR;
                                    s_axi_rvalid <= 1'b1;
                                    rd_state_q   <= RD_RESPONSE;
                                end
                            endcase
                        end
                    end
                end
                RD_SHA_ADDR: begin
                    if (sha_arvalid_q && sha_arready) begin
                        sha_arvalid_q <= 1'b0;
                        rd_state_q    <= RD_SHA_DATA;
                    end
                end
                RD_SHA_DATA: begin
                    if (sha_rvalid) begin
                        s_axi_rdata  <= sha_rdata;
                        s_axi_rresp  <= sha_rresp;
                        s_axi_rvalid <= 1'b1;
                        rd_state_q   <= RD_RESPONSE;
                    end
                end
                RD_DMA_ADDR: begin
                    if (dma_arvalid_q && dma_axil_arready) begin
                        dma_arvalid_q <= 1'b0;
                        rd_state_q    <= RD_DMA_DATA;
                    end
                end
                RD_DMA_DATA: begin
                    if (dma_axil_rvalid) begin
                        s_axi_rdata  <= dma_axil_rdata;
                        s_axi_rresp  <= dma_axil_rresp;
                        s_axi_rvalid <= 1'b1;
                        rd_state_q   <= RD_RESPONSE;
                    end
                end
                RD_RESPONSE: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rd_state_q   <= RD_CAPTURE;
                    end
                end
                default: rd_state_q <= RD_CAPTURE;
            endcase
        end
    end

    // Sideband inputs are intentionally accepted but not used by these
    // non-cacheable, non-privileged MMIO devices.
    wire _unused = &{1'b0, s_axi_awcache, s_axi_awprot,
                     s_axi_arcache, s_axi_arprot};
endmodule

`resetall
