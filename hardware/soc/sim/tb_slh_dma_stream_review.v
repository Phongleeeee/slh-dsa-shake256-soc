`timescale 1ns/1ps
// Independent Python hashlib oracle, varying stream stalls, framing and aborts.
module tb_slh_dma_stream_review;
    reg clk=0,rst=1,arm=0,abort_op=0;
    always #2 clk=~clk;
    reg [31:0] sd=0; reg [3:0] sk=15; reg sv=0,sl=0,mr=0;
    wire sr,mv,ml,owns,busy,done,error;
    wire [31:0] md,wd,rd; wire [3:0] mk;
    wire [7:0] aa,ra; wire av,ar,wv,wr,bv,br,rv,rr,rav,rar;
    wire [1:0] bp,rp;
    reg [31:0] vectors[0:10495]; // 256 * (mode + 32 operands + 8 digest)
    reg [31:0] prng=32'h205256;
    integer case_no,word_no,k,stalls,negative_cases=0;
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
    task random_delay;
        begin
            prng=prng^(prng<<13);prng=prng^(prng>>17);prng=prng^(prng<<5);
            repeat(prng[2:0]) @(negedge clk);
        end
    endtask
    task start;
        begin @(negedge clk);arm=1;@(negedge clk);arm=0; end
    endtask
    task beat(input [31:0] data,input last,input [3:0] keep);
        begin
            random_delay();@(negedge clk);sd=data;sl=last;sk=keep;sv=1;
            do @(posedge clk);while(!sr);
            @(negedge clk);sv=0;
        end
    endtask
    task frame(input integer c,input missing_last);
        integer j,limit;
        begin
            start();beat(vectors[41*c],0,15);
            limit=vectors[41*c] ? 32 : 24;
            for(j=0;j<limit;j=j+1) beat(vectors[41*c+1+j],!missing_last && j==limit-1,15);
        end
    endtask
    task drain(input integer c);
        integer j;reg [31:0] held;reg held_last;
        begin
            for(j=0;j<8;j=j+1) begin
                wait(mv);held=md;held_last=ml;
                // Longer than a normal data beat, with data/framing stability.
                for(k=0;k<3+(c+j)%23;k=k+1) begin
                    @(posedge clk);
                    if(!mv || md!==held || ml!==held_last || mk!==15)
                        $fatal(1,"AXIS unstable under backpressure case=%0d",c);
                end
                if(md!==vectors[41*c+33+j] || ml!==(j==7))
                    $fatal(1,"independent SHAKE256 mismatch case=%0d word=%0d got=%h expected=%h",c,j,md,vectors[41*c+33+j]);
                @(negedge clk);mr=1;@(negedge clk);mr=0;
            end
        end
    endtask
    task finish_check(input expected_error);
        begin
            wait(!owns);@(negedge clk);
            if(error!==expected_error || done===expected_error || mv)
                $fatal(1,"completion flags done=%b error=%b expected_error=%b",done,error,expected_error);
            if(hash.input_q!==0 || hash.pub_seed_q!==0 || hash.digest_q!==0)
                $fatal(1,"secret/digest register bank not zeroized");
        end
    endtask
    initial begin
        $readmemh("review_hash_vectors.mem",vectors);
        if(vectors[10495]===32'hxxxxxxxx) $fatal(1,"missing review vectors");
        repeat(8) @(negedge clk);rst=0;
        for(case_no=0;case_no<256;case_no=case_no+1) begin
            frame(case_no,0);drain(case_no);finish_check(0);
        end
        for(stalls=0;stalls<15;stalls=stalls+1) begin
            start();beat(0,0,15);beat(32'h01234567,0,stalls[3:0]);finish_check(1);negative_cases++;
        end
        start();beat(2,0,15);finish_check(1);negative_cases++;
        start();beat(0,1,15);finish_check(1);negative_cases++;
        frame(0,1);finish_check(1);negative_cases++;
        frame(1,1);finish_check(1);negative_cases++;
        // Error on the final cleanup response must never assert DONE as well.
        frame(0,0);drain(0);
        wait(a.state==4 && a.after_write==0 && bv);
        @(negedge clk);abort_op=1;@(negedge clk);abort_op=0;
        finish_check(1);negative_cases++;
        // Recover and prove that a following independent operation succeeds.
        frame(255,0);drain(255);finish_check(0);
        $display("INDEPENDENT SHAKE256 STREAM REVIEW TEST PASSED: 256 vectors, %0d negative cases, recovery",negative_cases);
        $finish;
    end
    initial begin #20_000_000;$fatal(1,"review stream timeout state=%0d case=%0d",a.state,case_no);end
endmodule
