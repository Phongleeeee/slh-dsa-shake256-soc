`timescale 1ns/1ps
// Software-style ring model, independent of DUT pointer encoding.
module dma_fifo_review_case #(parameter integer DEPTH=8, SEED=1)(output reg done=0);
    reg clk=0,rstn=0,push=0,pop=0,flush=0;
    always #2 clk=~clk;
    reg [31:0] serial=0,rng;
    wire accept,reject,dvalid,dempty,dfull,cvalid,cempty,cfull;
    wire [$clog2(DEPTH+1)-1:0] dc,cc;
    wire [31:0] src,dst,len,next_addr,clen;
    wire [1:0] typ,mode;
    wire [7:0] burst,id,cid,code;
    wire irq,cdone,cfault;
    reg [31:0] model[0:DEPTH-1];
    integer count=0,head=0,tail=0,checks=0,full_hits=0,empty_hits=0,overflows=0,simultaneous=0;
    integer trial;
    reg pa,qa;
    reg [31:0] front;
    dma_descriptor_fifo #(.ADDR_WIDTH(32),.LEN_WIDTH(32),.DEPTH(DEPTH)) d(
        .clk_i(clk),.rst_ni(rstn),.flush_i(flush),.push_i(push),
        .push_src_addr_i(serial),.push_dst_addr_i(serial^32'habcdef01),.push_length_i(serial+4),
        .push_transfer_type_i(serial[1:0]),.push_dma_mode_i(serial[3:2]),
        .push_burst_words_i(serial[7:0]),.push_irq_i(serial[8]),.push_id_i(serial[15:8]),
        .push_next_desc_i(~serial),.push_accepted_o(accept),.push_rejected_o(reject),
        .pop_i(pop),.valid_o(dvalid),.src_addr_o(src),.dst_addr_o(dst),.length_o(len),
        .transfer_type_o(typ),.dma_mode_o(mode),.burst_words_o(burst),.irq_o(irq),.id_o(id),
        .next_desc_o(next_addr),.empty_o(dempty),.full_o(dfull),.count_o(dc));
    dma_completion_fifo #(.LEN_WIDTH(32),.DEPTH(DEPTH)) c(
        .clk_i(clk),.rst_ni(rstn),.flush_i(flush),.push_i(push),.pop_i(pop),
        .push_id_i(serial[15:8]),.push_done_i(serial[0]),.push_fault_i(serial[1]),
        .push_fault_code_i(serial[7:0]),.push_bytes_i(serial+4),.valid_o(cvalid),
        .id_o(cid),.done_o(cdone),.fault_o(cfault),.fault_code_o(code),.bytes_o(clen),
        .empty_o(cempty),.full_o(cfull),.count_o(cc));
    task check_model;
        begin
            if(dc!==count || cc!==count || dvalid!==(count!=0) || cvalid!==(count!=0) ||
               dempty!==(count==0) || cempty!==(count==0) || dfull!==(count==DEPTH) || cfull!==(count==DEPTH))
                $fatal(1,"FIFO state depth=%0d trial=%0d model=%0d actual=%0d/%0d",DEPTH,trial,count,dc,cc);
            if(count) begin
                front=model[head];
                if(src!==front || dst!==(front^32'habcdef01) || len!==front+4 ||
                   typ!==front[1:0] || mode!==front[3:2] || burst!==front[7:0] ||
                   irq!==front[8] || id!==front[15:8] || next_addr!==~front ||
                   cid!==front[15:8] || cdone!==front[0] || cfault!==front[1] ||
                   code!==front[7:0] || clen!==front+4)
                    $fatal(1,"FIFO metadata/order depth=%0d trial=%0d",DEPTH,trial);
            end
            checks++;
        end
    endtask
    initial begin
        rng=SEED;
        repeat(5) @(negedge clk);rstn=1;
        for(trial=0;trial<20000;trial++) begin
            @(negedge clk);
            rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            serial=rng;push=rng[0];pop=rng[1];flush=(trial%251==250);
            if(trial%100<20) begin push=1;pop=0;end
            if(trial%100>=20 && trial%100<40) begin push=0;pop=1;end
            if(trial%100>=40 && trial%100<60) begin push=1;pop=1;end
            #0.1;check_model();
            qa=pop && count!=0;pa=push && (count<DEPTH || qa);
            if(accept!==pa || reject!==(push && !pa)) $fatal(1,"FIFO accept/reject mismatch");
            if(count==DEPTH) full_hits++;
            if(count==0) empty_hits++;
            if(push && !pa) overflows++;
            if(pa && qa) simultaneous++;
            @(posedge clk);
            if(flush) begin count=0;head=0;tail=0;end
            else begin
                if(pa) begin model[tail]=serial;tail=(tail+1)%DEPTH;end
                if(qa) head=(head+1)%DEPTH;
                count=count+int'(pa)-int'(qa);
            end
            #0.1;check_model();
        end
        if(!full_hits || !empty_hits || !overflows || !simultaneous) $fatal(1,"FIFO coverage hole");
        $display("DMA FIFO MODEL PASS depth=%0d checks=%0d full=%0d empty=%0d rejected=%0d simultaneous=%0d",
            DEPTH,checks,full_hits,empty_hits,overflows,simultaneous);
        done=1;
    end
endmodule
module tb_dma_fifo_review;
    wire a,b;
    dma_fifo_review_case #(.DEPTH(4),.SEED(32'h534c4804)) c4(a);
    dma_fifo_review_case #(.DEPTH(8),.SEED(32'h534c4808)) c8(b);
    initial begin wait(a && b);$display("DMA FIFO REVIEW TEST PASSED: 80000 model checks, descriptor and completion FIFO");$finish;end
    initial begin #1ms;$fatal(1,"FIFO test timeout");end
endmodule
