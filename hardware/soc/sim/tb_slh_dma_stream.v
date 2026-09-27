`timescale 1ns/1ps
module tb_slh_dma_stream;
    reg clk=0,rst=1,arm=0,abort_op=0;
    always #2 clk=~clk;
    reg [31:0] sd=0; reg [3:0] sk=15; reg sv=0,sl=0,mr=0;
    wire sr,mv,ml,owns,busy,done,error;
    wire [31:0] md,wd,rd; wire [3:0] mk;
    wire [7:0] aa,ra; wire av,ar,wv,wr,bv,br,rv,rr,rav,rar;
    wire [1:0] bp,rp;
    slh_dma_stream_adapter a(.clk(clk),.rst(rst),.arm(arm),.abort_op(abort_op),
        .owns_hash(owns),.busy(busy),.done(done),.error(error),
        .s_data(sd),.s_keep(sk),.s_valid(sv),.s_ready(sr),.s_last(sl),
        .m_data(md),.m_keep(mk),.m_valid(mv),.m_ready(mr),.m_last(ml),
        .awaddr(aa),.awvalid(av),.awready(ar),.wdata(wd),.wvalid(wv),.wready(wr),
        .bresp(bp),.bvalid(bv),.bready(br),.araddr(ra),.arvalid(rav),.arready(rar),
        .rdata(rd),.rresp(rp),.rvalid(rv),.rready(rr));
    slh_dsa_shake_axi_lite hash(.s_axi_aclk(clk),.s_axi_aresetn(!rst),
        .s_axi_awaddr(aa),.s_axi_awvalid(av),.s_axi_awready(ar),
        .s_axi_wdata(wd),.s_axi_wstrb(4'hf),.s_axi_wvalid(wv),.s_axi_wready(wr),
        .s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
        .s_axi_araddr(ra),.s_axi_arvalid(rav),.s_axi_arready(rar),
        .s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rv),.s_axi_rready(rr),.irq());
    task start; begin @(negedge clk); arm=1; @(negedge clk); arm=0; end endtask
    task beat(input [31:0] data,input last,input [3:0] keep);
        begin @(negedge clk); sd=data; sl=last; sk=keep; sv=1;
            do @(posedge clk); while(!sr);
            @(negedge clk); sv=0; repeat(2) @(negedge clk);
        end
    endtask
    task frame(input mode);
        integer j,k,base; reg [31:0] data;
        begin start(); beat(mode,0,15);
            for(j=0;j<(mode ? 32 : 24);j=j+1) begin
                base=j<8 ? j*4 : (j<16 ? 160+(j-8)*4 : 64+(j-16)*4);
                for(k=0;k<4;k=k+1) data[k*8+:8]=base+k;
                beat(data,j==(mode ? 31 : 23),15);
            end
        end
    endtask
    task drain(input [255:0] expected);
        integer j; reg [255:0] digest; reg [31:0] held;
        begin for(j=0;j<8;j=j+1) begin
                wait(mv); held=md; repeat(5) begin @(posedge clk); if(!mv || md!==held) $fatal(1,"output changed under backpressure"); end
                if(mk!==15 || ml!==(j==7)) $fatal(1,"output framing");
                digest[j*32+:32]=md;
                @(negedge clk); mr=1; @(negedge clk); mr=0;
            end
            wait(!owns); if(error || !done || digest!==expected) $fatal(1,"digest %h expected %h",digest,expected);
            if(hash.input_q!==0 || hash.pub_seed_q!==0 || hash.digest_q!==0) $fatal(1,"stream bank not scrubbed");
        end
    endtask
    initial begin
        repeat(8) @(negedge clk); rst=0;
        frame(0); drain(256'h29ef9ddfbe16b1469239982cee72b5bf8577df7d294905625227f38e4b6645de);
        frame(1); drain(256'h5a0c081366ef0287f98f0fab56c9f14371fa20967e46842c532d9d282de78f78);
        start(); beat(0,0,15); beat(32'hdeadbeef,1,15); wait(!owns); if(!error) $fatal(1,"early TLAST not rejected");
        start(); beat(0,0,3); wait(!owns); if(!error) $fatal(1,"bad TKEEP not rejected");
        start(); @(negedge clk); abort_op=1; @(negedge clk); abort_op=0;
        wait(!owns); if(!error) $fatal(1,"abort not rejected");
        frame(0); @(negedge clk); rst=1; repeat(4) @(negedge clk); rst=0;
        repeat(4) @(negedge clk); if(owns || mv) $fatal(1,"stale state after reset");
        frame(0); drain(256'h29ef9ddfbe16b1469239982cee72b5bf8577df7d294905625227f38e4b6645de);
        $display("DMA F/H STREAM BACKPRESSURE/FRAMING/ABORT/RESET TEST PASSED"); $finish;
    end
    initial begin #100000; $fatal(1,"stream timeout"); end
endmodule
