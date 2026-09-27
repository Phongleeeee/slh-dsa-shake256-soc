`timescale 1ns / 1ps
`default_nettype none

module axi_ram #(
    parameter DATA_WIDTH      = 32,
    parameter ADDR_WIDTH      = 16,
    parameter STRB_WIDTH      = (DATA_WIDTH/8),
    parameter ID_WIDTH       = 8,
    parameter INIT_FILE      = ""   // optional: load program for simulation
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awlock,
    input  wire [3:0]             s_axi_awcache,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arlock,
    input  wire [3:0]             s_axi_arcache,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready
);

    localparam ADDR_LSB = $clog2(STRB_WIDTH);
    localparam VALID_ADDR_WIDTH = ADDR_WIDTH - ADDR_LSB;

    localparam [1:0]
        WRITE_IDLE = 2'd0,
        WRITE_DATA = 2'd1,
        WRITE_RESP = 2'd2;

    localparam [1:0]
        READ_IDLE  = 2'd0,
        READ_DATA  = 2'd1;

    localparam RESP_OKAY = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    localparam integer MEM_DEPTH = (1 << VALID_ADDR_WIDTH);
    localparam integer MEM_SIZE  = DATA_WIDTH * MEM_DEPTH;
`ifdef SYNTHESIS
    localparam         INIT_FILE_INT = (INIT_FILE != "") ? INIT_FILE : "none";
`endif

    // Memory backend signals (shared by synthesis/simulation backends).
    reg                          mem_wr_en;
    reg [STRB_WIDTH-1:0]         mem_wr_strb;
    reg [VALID_ADDR_WIDTH-1:0]   mem_wr_addr;
    reg [DATA_WIDTH-1:0]         mem_wr_data;
    reg                          mem_rd_en;
    reg [VALID_ADDR_WIDTH-1:0]   mem_rd_addr;
    wire [DATA_WIDTH-1:0]        mem_rd_data;

`ifdef SYNTHESIS
    // XPM memory instance forces true block RAM mapping in Vivado.
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(VALID_ADDR_WIDTH),
        .ADDR_WIDTH_B(VALID_ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE(INIT_FILE_INT),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(MEM_SIZE),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(DATA_WIDTH),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(1),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),
        .WRITE_MODE_B("no_change")
    )
    mem_i (
        .sleep(1'b0),
        .clka(clk),
        .ena(mem_wr_en),
        .wea(mem_wr_strb),
        .addra(mem_wr_addr),
        .dina(mem_wr_data),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .clkb(clk),
        .rstb(rst),
        .enb(mem_rd_en),
        .regceb(1'b1),
        .addrb(mem_rd_addr),
        .doutb(mem_rd_data),
        .sbiterrb(),
        .dbiterrb()
    );
`else
    // Simulation backend keeps legacy visible array "mem" for existing testbenches.
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    reg [DATA_WIDTH-1:0] mem_rd_data_reg;
    integer sim_init_i;
    integer sim_byte_i;

    assign mem_rd_data = mem_rd_data_reg;

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (sim_init_i = 0; sim_init_i < MEM_DEPTH; sim_init_i = sim_init_i + 1) begin
                mem[sim_init_i] = {DATA_WIDTH{1'b0}};
            end
        end
        mem_rd_data_reg = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk) begin
        if (mem_wr_en) begin
            for (sim_byte_i = 0; sim_byte_i < STRB_WIDTH; sim_byte_i = sim_byte_i + 1) begin
                if (mem_wr_strb[sim_byte_i]) begin
                    mem[mem_wr_addr][8*sim_byte_i +: 8] <= mem_wr_data[8*sim_byte_i +: 8];
                end
            end
        end

        if (mem_rd_en) begin
            mem_rd_data_reg <= mem[mem_rd_addr];
        end
    end
`endif

//------------------------------------------------
// WRITE REGISTERS
//------------------------------------------------
    reg [1:0] write_state;

    reg [ID_WIDTH-1:0] write_id;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [7:0] write_count;
    reg [2:0] write_size;
    reg [1:0] write_burst;
    
    reg awready;
    reg wready;
    reg [ID_WIDTH-1:0] bid;
    reg [1:0] bresp;
    reg bvalid;
    
    wire [VALID_ADDR_WIDTH-1:0] write_addr_word;
    assign write_addr_word = write_addr[ADDR_WIDTH-1:ADDR_LSB];

//------------------------------------------------
// READ REGISTERS
//------------------------------------------------
    reg [1:0] read_state;
    
    reg [ID_WIDTH-1:0] read_id;
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0] read_count;
    reg [2:0] read_size;
    reg [1:0] read_burst;
    
    reg arready;
    reg [ID_WIDTH-1:0] rid;
    reg [DATA_WIDTH-1:0] rdata;
    reg [1:0] rresp;
    reg rlast;
    reg rvalid;
    reg read_last_pending;
    reg [1:0] read_wait_cnt;
    
    
//------------------------------------------------
// OUTPUTS
//------------------------------------------------
    assign s_axi_awready = awready;
    assign s_axi_wready  = wready;
    assign s_axi_bid     = bid;
    assign s_axi_bresp   = bresp;
    assign s_axi_bvalid  = bvalid;
    
    assign s_axi_arready = arready;
    assign s_axi_rid     = rid;
    assign s_axi_rdata   = rdata;
    assign s_axi_rresp   = rresp;
    assign s_axi_rlast   = rlast;
    assign s_axi_rvalid  = rvalid;

//------------------------------------------------
// MAIN SEQUENTIAL
//------------------------------------------------
    always @(posedge clk) begin

        if(rst) begin

            write_state <= WRITE_IDLE;
            read_state  <= READ_IDLE;
            
            awready <= 0;
            wready  <= 0;
            bvalid  <= 0;

            // reset thêm cho write response
            bid   <= {ID_WIDTH{1'b0}};
            bresp <= RESP_OKAY;
            
            arready <= 0;
            rvalid  <= 0;
            rlast   <= 0;

            // reset thêm cho read response
            rid   <= {ID_WIDTH{1'b0}};
            rdata <= {DATA_WIDTH{1'b0}};
            rresp <= RESP_OKAY;
            read_last_pending <= 1'b0;
            read_wait_cnt <= 2'd0;
            mem_wr_en   <= 1'b0;
            mem_wr_strb <= {STRB_WIDTH{1'b0}};
            mem_wr_addr <= {VALID_ADDR_WIDTH{1'b0}};
            mem_wr_data <= {DATA_WIDTH{1'b0}};
            mem_rd_en   <= 1'b0;
            mem_rd_addr <= {VALID_ADDR_WIDTH{1'b0}};

        end else begin 
            // defaults for one-cycle strobes to XPM ports
            mem_wr_en   <= 1'b0;
            mem_wr_strb <= {STRB_WIDTH{1'b0}};
            mem_rd_en   <= 1'b0;

//------------------------------------------------
// WRITE FSM
//------------------------------------------------
            case(write_state)

                WRITE_IDLE: begin

                    awready <= 1;
                    wready  <= 0;

                    if(awready && s_axi_awvalid) begin
                        write_id    <= s_axi_awid;
                        write_addr  <= s_axi_awaddr;
                        write_count <= s_axi_awlen;
                        write_size  <= s_axi_awsize;
                        write_burst <= s_axi_awburst;
                    
                        awready <= 0;
                        wready  <= 1;

                        write_state <= WRITE_DATA;
                    end

                end

                WRITE_DATA: begin
                    if (wready && s_axi_wvalid) begin
                        mem_wr_en   <= 1'b1;
                        mem_wr_strb <= s_axi_wstrb;
                        mem_wr_addr <= write_addr_word;
                        mem_wr_data <= s_axi_wdata;
                
                        // beat cuối theo count
                        if (write_count == 0) begin
                            bid <= write_id;
                
                            // beat cuối thì WLAST phải = 1
                            if (s_axi_wlast)
                                bresp <= RESP_OKAY;
                            else
                                bresp <= RESP_SLVERR;
                
                            bvalid <= 1'b1;
                            wready <= 1'b0;
                            write_state <= WRITE_RESP;
                        end
                        else begin
                            // chưa phải beat cuối mà WLAST lên sớm => lỗi
                            if (s_axi_wlast) begin
                                bid   <= write_id;
                                bresp <= RESP_SLVERR;
                                bvalid <= 1'b1;
                                wready <= 1'b0;
                                write_state <= WRITE_RESP;
                            end
                            else begin
                                write_count <= write_count - 1'b1;
                
                                case (write_burst)
                                    2'b01: write_addr <= write_addr + (1 << write_size);
                                    default: write_addr <= write_addr;
                                endcase
                            end
                        end
                    end
                end

                WRITE_RESP: begin

                    if(bvalid && s_axi_bready) begin
                        bvalid <= 0;
                        awready <= 1;
                        write_state <= WRITE_IDLE;
                    end

                end

            endcase

//------------------------------------------------
// READ FSM (FIXED BUG HERE)
//------------------------------------------------
            case(read_state)

                READ_IDLE: begin

                    arready <= 1;
                    rvalid  <= 0;
                    rlast   <= 0;
                    read_wait_cnt <= 2'd0;

                    if(arready && s_axi_arvalid) begin

                        read_id    <= s_axi_arid;
                        read_addr  <= s_axi_araddr;
                        read_count <= s_axi_arlen;
                        read_size  <= s_axi_arsize;
                        read_burst <= s_axi_arburst;
                        
                        arready <= 0;
                        mem_rd_en   <= 1'b1;
                        mem_rd_addr <= s_axi_araddr[ADDR_WIDTH-1:ADDR_LSB];
                        read_last_pending <= (s_axi_arlen == 0);
                        // mem_rd_en is registered; with READ_LATENCY_B=1, data is visible after 2 cycles.
                        read_wait_cnt <= 2'd2;
                        read_state <= READ_DATA;

                    end

                end

                READ_DATA: begin

                    // Wait for registered read command to reach memory and return data.
                    if (read_wait_cnt != 0) begin
                        read_wait_cnt <= read_wait_cnt - 1'b1;
                    end
                    else if (!rvalid) begin
                        rid   <= read_id;
                        rdata <= mem_rd_data;
                        rresp <= RESP_OKAY;
                        rlast <= read_last_pending;
                        rvalid <= 1'b1;
                    end
                    // beat accepted
                    else if(rvalid && s_axi_rready) begin

                        if(rlast) begin
                            rvalid <= 1'b0;
                            rlast  <= 1'b0;
                            arready <= 1'b1;
                            read_state <= READ_IDLE;
                        end
                        else begin
                            read_count <= read_count - 1'b1;
                            mem_rd_en   <= 1'b1;
                            read_last_pending <= (read_count == 1);
                            read_wait_cnt <= 2'd2;
                            rvalid <= 1'b0;

                            case(read_burst)
                                2'b01: begin
                                    read_addr   <= read_addr + (1 << read_size);
                                    mem_rd_addr <= (read_addr + (1 << read_size)) >> ADDR_LSB;
                                end
                                default: begin
                                    read_addr   <= read_addr;
                                    mem_rd_addr <= read_addr >> ADDR_LSB;
                                end
                            endcase
                        end

                    end

                end

            endcase

        end
    end

endmodule

`resetall
