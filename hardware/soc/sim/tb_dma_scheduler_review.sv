`timescale 1ns/1ps
// Independent descriptor model: burst clipping, both 4 KiB boundaries,
// stream TLAST, backpressure, and changing config immediately after START.
module tb_dma_scheduler_review;
    logic clk=0,rst_n=0,start=0;
    always #2 clk=~clk;
    logic [1:0] typ=0,mode=0;
    logic [7:0] burst=0;
    logic [31:0] src=0,dst=0;
    logic [19:0] length=0;
    logic busy,done,fault;
    logic [7:0] fault_code;
    logic qvalid,qwrite,resp_valid=0;
    logic [31:0] qaddr,resp_addr=0;
    logic [19:0] qlen;
    logic [31:0] csrc,cdst,rdaddr,wraddr;
    logic [19:0] clen,rdlen,wrlen;
    logic cv,rv,wv,rdlast;
    logic cs=0,rs=0,ws=0;
    integer tick=0,descriptors=0,trials=0,negative=0;
    logic qready,engine_ready,cpu_idle;
    assign qready=(tick%5)!=0;
    assign engine_ready=(tick%7)>2;
    assign cpu_idle=(tick%6)>1;
    reg [31:0] rand_q=32'h534c4833;
    integer model_type,model_mode,model_burst,model_remaining,model_chunk;
    reg [31:0] model_src,model_dst;
    integer trial,j,waits;
    dma_axi_scheduler #(.ADDR_WIDTH(32),.LEN_WIDTH(20)) dut(
        .clk_i(clk),.rst_ni(rst_n),.cfg_start_i(start),.cfg_transfer_type_i(typ),
        .cfg_dma_mode_i(mode),.cfg_burst_words_i(burst),.cfg_src_vaddr_i(src),
        .cfg_dst_vaddr_i(dst),.cfg_length_bytes_i(length),.cpu_bus_idle_i(cpu_idle),
        .translation_invalidate_i(1'b0),.busy_o(busy),.done_o(done),.fault_o(fault),.fault_code_o(fault_code),
        .iommu_req_valid_o(qvalid),.iommu_req_ready_i(qready),.iommu_req_vaddr_o(qaddr),
        .iommu_req_len_o(qlen),.iommu_req_write_o(qwrite),.iommu_resp_valid_i(resp_valid),
        .iommu_resp_allow_i(1'b1),.iommu_resp_paddr_i(resp_addr),.iommu_resp_fault_i(3'd0),
        .cdma_desc_src_addr_o(csrc),.cdma_desc_dst_addr_o(cdst),.cdma_desc_len_o(clen),
        .cdma_desc_valid_o(cv),.cdma_desc_ready_i(engine_ready),.cdma_status_error_i(4'd0),.cdma_status_valid_i(cs),
        .axis_rd_desc_addr_o(rdaddr),.axis_rd_desc_len_o(rdlen),.axis_rd_desc_valid_o(rv),
        .axis_rd_desc_ready_i(engine_ready),.axis_rd_status_error_i(4'd0),.axis_rd_status_valid_i(rs),.axis_rd_last_chunk_o(rdlast),
        .axis_wr_desc_addr_o(wraddr),.axis_wr_desc_len_o(wrlen),.axis_wr_desc_valid_o(wv),
        .axis_wr_desc_ready_i(engine_ready),.axis_wr_status_error_i(4'd0),.axis_wr_status_valid_i(ws));
    task randomize_next;
        begin rand_q=rand_q^(rand_q<<13);rand_q=rand_q^(rand_q>>17);rand_q=rand_q^(rand_q<<5); end
    endtask
    always @(posedge clk) begin
        tick<=tick+1;
        resp_valid<=qvalid && qready;
        if(qvalid && qready) begin
            if(qlen==0 || (qaddr&4095)+qlen>4096) $fatal(1,"IOMMU request crosses a page");
            resp_addr<=qaddr^32'h40000;
        end
        cs<=cv && engine_ready;rs<=rv && engine_ready;ws<=wv && engine_ready;
        if(rst_n && engine_ready && (cv || rv || wv)) begin
            if(model_type==0 && !cv || model_type==1 && !wv || model_type==2 && !rv)
                $fatal(1,"wrong engine selected");
            model_chunk=model_mode==0 ? ((model_burst==0 || model_burst>16) ? 64 : model_burst*4) : 4;
            if(model_chunk>model_remaining) model_chunk=model_remaining;
            if(model_type!=1 && model_chunk>4096-(model_src&4095)) model_chunk=4096-(model_src&4095);
            if(model_type!=2 && model_chunk>4096-(model_dst&4095)) model_chunk=4096-(model_dst&4095);
            if((cv && (clen!==model_chunk || csrc!==(model_src^32'h40000) || cdst!==(model_dst^32'h40000))) ||
               (rv && (rdlen!==model_chunk || rdaddr!==(model_src^32'h40000) || rdlast!==(model_chunk==model_remaining))) ||
               (wv && (wrlen!==model_chunk || wraddr!==(model_dst^32'h40000))))
                $fatal(1,"descriptor differs from independent model trial=%0d",trials);
            model_src=model_src+model_chunk;model_dst=model_dst+model_chunk;
            model_remaining=model_remaining-model_chunk;descriptors++;
        end
    end
    task launch(input expect_fault);
        begin
            model_type=typ;model_mode=mode;model_burst=burst;
            model_src=src;model_dst=dst;model_remaining=length;
            @(negedge clk);start=1;@(negedge clk);start=0;
            // A new descriptor's registers may change during INIT_PAGES.
            // No calculation is allowed to depend on those uncaptured inputs.
            src=32'hdeadbeef;dst=32'hffffffff;length=0;typ=3;mode=3;burst=255;
            waits=0;
            while(!done && !fault && waits<300000) begin @(negedge clk);waits++;end
            if(waits==300000 || fault!==expect_fault || done===expect_fault)
                $fatal(1,"completion/timeout");
            if(expect_fault) begin
                if(fault_code!==1) $fatal(1,"bad-command fault encoding");
                negative++;
            end else if(model_remaining!=0) $fatal(1,"incomplete command");
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(trial=0;trial<512;trial++) begin
            randomize_next();src=32'h10000+(rand_q&32'h7ffc);
            randomize_next();dst=32'h20000+(rand_q&32'h7ffc);
            // Explicit offsets: 0, last word, last burst, and asymmetric pages.
            if(trial<16) begin src=32'h11000-4*(trial%4);dst=32'h21ffc-4*(trial/4);end
            randomize_next();length=4*(1+(rand_q%256));
            if(trial<8) length=8192;
            randomize_next();burst=rand_q[7:0];
            typ=trial%3;mode=(trial/3)%3;trials++;
            launch(0);
        end
        for(j=0;j<6;j++) begin
            src='h10000;dst='h20000;length=16;typ=0;mode=0;burst=4;
            case(j) 0:length=0;1:length=3;2:src='h10001;3:dst='h20001;4:typ=3;5:mode=3;endcase
            launch(1);
        end
        $display("DMA SCHEDULER REVIEW TEST PASSED: %0d commands, %0d descriptors, %0d invalid commands",trials,descriptors,negative);
        $finish;
    end
    initial begin #30_000_000;$fatal(1,"scheduler review timeout");end
endmodule
