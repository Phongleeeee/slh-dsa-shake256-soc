`timescale 1ns/1ps
// End-to-end DMA: production movers/IOMMU, behavioral AXI fabric/RAM.
// Production SoC fabric/XPM integration is tested separately by test_soc.ps1.
// Reuse the original fixture and its 9-mode/queue/fault regression first.
module tb_dma_matrix_review;
    wire baseline_done, baseline_pass;
    tb_dma_mmu_axi_top #(.AUTO_FINISH(0), .STREAM_CAPTURE_WORDS(4096), .DMA_POLL_LIMIT(250000),
        .LOG_PATH("baseline.log"), .PERF_LOG_PATH("baseline_perf.log"),
        .EDGE_LOG_PATH("baseline_edges.log")) f(
        .test_done_o(baseline_done), .test_pass_o(baseline_pass));
    integer covered[0:2][0:2];
    integer successes=0, negatives=0, words_checked=0, trial=0;
    integer tick=0, expected_words=0, received=0, sent=0, active_type=0;
    integer stall_cycles=0;
    logic checking=0, random_ready=0, enforce_completion=0;
    logic [31:0] pattern=0, rng=32'h28d0a123;
    logic stalled=0;
    logic [36:0] held_stream;
    integer csv;
    integer active_mode=0, control_checks=0, pt_commits=0;
    logic queue_check=0;
    integer queue_done=0;
    logic [1:0] injected_response;
    integer bus_fault_checks=0, reset_checks=0;

    function automatic [15:0] physical(input integer va);
        // Deliberately non-contiguous physical pages.
        physical=va[15:0]^16'h5000;
    endfunction
    function automatic [31:0] payload(input integer n);
        payload=pattern ^ (32'h9e3779b9*n) ^ (n<<11);
    endfunction
    task next_random;
        rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
    endtask

    always @(negedge f.clk) begin
        tick=tick+1;
        if(random_ready) f.m_axis_tready=(tick%17>=5 && tick%31!=0);
    end
    always @(posedge f.clk) begin
        if(f.rst_n && f.dut.pt_write) pt_commits++;
        if(checking && $test$plusargs("trace")) begin
            if(f.m_axi_arvalid && f.m_axi_arready) $display("TRACE AR=%h len=%d mem4000=%h",f.m_axi_araddr,f.m_axi_arlen,f.mem_inst.mem['h1000]);
            if(f.m_axi_rvalid && f.m_axi_rready) $display("TRACE R=%h last=%b",f.m_axi_rdata,f.m_axi_rlast);
        end
        if(checking && f.rst_n) begin
            if(stalled && {f.m_axis_tvalid,f.m_axis_tlast,f.m_axis_tkeep,f.m_axis_tdata}
                    !== {1'b1,held_stream})
                $fatal(1,"AXIS changed under backpressure trial=%0d",trial);
            stalled=f.m_axis_tvalid && !f.m_axis_tready;
            held_stream={f.m_axis_tlast,f.m_axis_tkeep,f.m_axis_tdata};
            if(stalled) stall_cycles++;
            if(f.m_axis_tvalid && f.m_axis_tready) begin
                if(active_type!=2 || (!queue_check && received>=expected_words) ||
                   f.m_axis_tdata!==payload(received%expected_words) || f.m_axis_tkeep!==4'hf ||
                   f.m_axis_tlast!==(received%expected_words==expected_words-1))
                    $fatal(1,"M2S data/keep/last mismatch trial=%0d word=%0d data=%h expected=%h last=%b",
                        trial,received,f.m_axis_tdata,payload(received),f.m_axis_tlast);
                received++; words_checked++;
            end
            if(f.s_axis_tvalid && f.s_axis_tready) sent++;
            if(enforce_completion && active_type==2 && f.dut.dma_done && received!=expected_words)
                $fatal(1,"M2S DONE before destination accepted data: received=%0d expected=%0d",received,expected_words);
            if(queue_check && f.dut.completion_push) begin
                queue_done++;
                if(f.dut.dma_fault || received < queue_done*expected_words)
                    $fatal(1,"Queued completion overtook packet drain");
            end
            if(f.m_axi_arvalid && f.m_axi_arready &&
                ((f.m_axi_araddr&4095)+4*(f.m_axi_arlen+1)>4096 || f.m_axi_arlen>15))
                $fatal(1,"AXI read burst exceeds page/burst bound");
            if(f.m_axi_awvalid && f.m_axi_awready &&
                ((f.m_axi_awaddr&4095)+4*(f.m_axi_awlen+1)>4096 || f.m_axi_awlen>15))
                $fatal(1,"AXI write burst exceeds page/burst bound");
            if(!queue_check && active_mode!=0 &&
               ((f.m_axi_arvalid && f.m_axi_arready && f.m_axi_arlen!=0) ||
                (f.m_axi_awvalid && f.m_axi_awready && f.m_axi_awlen!=0)))
                $fatal(1,"Non-burst mode issued multi-beat transaction");
        end else stalled=0;
    end

    task initialize_pages;
        for(integer p=0;p<16;p++) f.program_page(p,p,p^5,1,1);
    endtask
    task send_words(input integer count);
        for(integer n=0;n<count;n++) begin
            repeat((n+trial)%4) @(negedge f.clk);
            @(negedge f.clk);
            f.s_axis_tdata=payload(n); f.s_axis_tkeep=15;
            f.s_axis_tlast=(n==count-1); f.s_axis_tvalid=1;
            do @(posedge f.clk); while(!f.s_axis_tready);
            @(negedge f.clk); f.s_axis_tvalid=0;
        end
        f.s_axis_tlast=0;
    endtask

    task good_transfer(input integer typ,mode,bytes,burst,src,dst);
        reg [31:0] result,seq_before;
        integer waits;
        begin
            trial++;
            @(negedge f.clk);
            pattern=32'hd28a0000^trial; active_type=typ;active_mode=mode;
            expected_words=bytes/4;received=0;sent=0;stall_cycles=0;
            f.stream_out_count=0;f.stream_out_last_count=0;
            f.transparent_pattern_enable=(mode==2);
            f.m_axis_tready=1;
            for(integer n=-1;n<=expected_words;n++) begin
                if(typ!=2) f.mem_inst.mem[physical(dst+4*n)>>2]=32'hc0decafe;
                if(typ!=1) f.mem_inst.mem[physical(src+4*n)>>2]=payload(n);
            end
            seq_before=f.dut.perf_seq;
            checking=1;random_ready=1;enforce_completion=1;
            fork
                begin f.run_dma(src,dst,bytes,typ,mode,burst,result); end
                begin if(typ==1) send_words(expected_words); end
            join
            waits=0;
            while((typ==2 && received!=expected_words || f.dut.perf_seq==seq_before) && waits<50000) begin
                @(negedge f.clk); waits++;
            end
            repeat(8) @(negedge f.clk);
            checking=0;random_ready=0;enforce_completion=0;f.m_axis_tready=1;
            if(waits==50000 || result[2:0]!==3'b010)
                $fatal(1,"DMA completion error trial=%0d type=%0d mode=%0d bytes=%0d status=%h",trial,typ,mode,bytes,result);
            if(typ==1 && sent!=expected_words) $fatal(1,"S2M byte count mismatch");
            if(typ!=2) begin
                for(integer n=0;n<expected_words;n++) begin
                    if(f.mem_inst.mem[physical(dst+4*n)>>2]!==payload(n))
                        $fatal(1,"RAM data mismatch trial=%0d word=%0d",trial,n);
                    words_checked++;
                end
                if(f.mem_inst.mem[physical(dst-4)>>2]!==32'hc0decafe ||
                   f.mem_inst.mem[physical(dst+bytes)>>2]!==32'hc0decafe)
                    $fatal(1,"DMA modified guard bytes");
            end
            if(f.dut.perf_fault || f.dut.perf_length!==bytes ||
               f.dut.perf_src_bytes!==bytes || f.dut.perf_dst_bytes!==bytes ||
               f.dut.perf_transfer_type!==typ || f.dut.perf_dma_mode!==mode)
                $fatal(1,"Performance byte/type/mode mismatch trial=%0d",trial);
            covered[typ][mode]++;successes++;
            $fdisplay(csv,"%0d,%0d,%0d,%0d,%0d,%h,%h,%0d,PASS",trial,typ,mode,bytes,burst,src,dst,stall_cycles);
        end
    endtask

    task reject_transfer(input integer typ,mode,src,dst,bytes,code);
        reg [31:0] result;
        integer ar_before,aw_before;
        begin
            ar_before=f.ar_count;aw_before=f.aw_count;
            f.run_dma(src,dst,bytes,typ,mode,16,result);
            repeat(8) @(negedge f.clk);
            if(!result[2] || result[1] || result[15:8]!==code ||
               f.ar_count!=ar_before || f.aw_count!=aw_before)
                $fatal(1,"Negative command leaked AXI or wrong fault: type=%0d mode=%0d status=%h expected=%h",typ,mode,result,code);
            negatives++;
        end
    endtask

    task completion_backpressure(input integer mode);
        reg [31:0] result;
        integer word_index;
        reg [31:0] init_word;
        begin
            trial++;
            @(negedge f.clk);pattern=32'hfeedabcd;received=0;active_type=2;active_mode=mode;expected_words=8;
            f.stream_out_count=0;f.stream_out_last_count=0;
            for(integer n=0;n<8;n++) begin
                word_index=physical('h1000+4*n)>>2;
                init_word=payload(n);
                f.mem_inst.mem[word_index]=init_word;
                if($test$plusargs("trace")) $display("INIT n=%0d index=%h word=%h read=%h",n,word_index,init_word,f.mem_inst.mem[word_index]);
            end
            f.m_axis_tready=0;checking=1;enforce_completion=1;
            fork
                f.run_dma('h1000,0,32,2,mode,16,result);
                begin
                    wait(f.m_axis_tvalid);
                    repeat(150) @(negedge f.clk);
                    f.m_axis_tready=1;
                end
            join
            repeat(12) @(negedge f.clk);
            checking=0;enforce_completion=0;
            if(result[2:0]!==3'b010 || received!=8) $fatal(1,"Backpressure completion test failed");
            $display("M2S COMPLETION BACKPRESSURE PASS mode=%0d",mode);
        end
    endtask

    // Independent AW and W arrival; B held for an arbitrary number of cycles.
    task write_split(input [7:0] addr,input [31:0] data,input [3:0] mask,
                     input integer aw_delay,w_delay,b_delay);
        begin
            @(negedge f.clk); f.axil_bready=0;
            fork
                begin
                    repeat(aw_delay) @(negedge f.clk);
                    f.axil_awaddr=addr;f.axil_awvalid=1;
                    do @(posedge f.clk); while(!f.axil_awready);
                    @(negedge f.clk);f.axil_awvalid=0;
                end
                begin
                    repeat(w_delay) @(negedge f.clk);
                    f.axil_wdata=data;f.axil_wstrb=mask;f.axil_wvalid=1;
                    do @(posedge f.clk); while(!f.axil_wready);
                    @(negedge f.clk);f.axil_wvalid=0;
                end
            join
            while(!f.axil_bvalid) @(negedge f.clk);
            repeat(b_delay) begin
                @(negedge f.clk);
                if(!f.axil_bvalid || f.axil_bresp!==0) $fatal(1,"B response changed under stall");
            end
            f.axil_bready=1;@(posedge f.clk);@(negedge f.clk);f.axil_bready=0;
        end
    endtask

    task control_plane;
        reg [31:0] expected,value,data;
        integer before_commit;
        begin
            expected=0;
            f.axil_write(8'h08,expected);
            for(integer k=0;k<64;k++) begin
                next_random();data=rng;
                write_split(8'h08,data,k%16,k%5,(k+2)%7,k%9);
                for(integer b=0;b<4;b++) if((k%16)&(1<<b)) expected[b*8+:8]=data[b*8+:8];
                f.axil_read(8'h08,value);
                if(value!==expected) $fatal(1,"AXI-Lite WSTRB/AW-W ordering mismatch k=%0d",k);
                control_checks++;
            end
            before_commit=pt_commits;
            write_split(8'h2c,7,0,3,0,5);
            repeat(4) @(negedge f.clk);
            if(pt_commits!=before_commit) $fatal(1,"WSTRB=0 unexpectedly commits IOMMU page table");
            control_checks++;
            write_split(8'h2c,32'habcdef00,14,0,4,3);
            repeat(4) @(negedge f.clk);
            if(pt_commits!=before_commit) $fatal(1,"Upper-byte-only write unexpectedly commits page table");
            control_checks++;
            $display("DMA AXIL CONTROL PASS: %0d checks",control_checks);
        end
    endtask

    task queued_backpressure;
        reg [31:0] value,bytes;
        integer waits,word_index;
        reg [31:0] init_word;
        begin
            @(negedge f.clk);pattern=32'h98abc123;active_type=2;expected_words=8;
            received=0;queue_done=0;f.stream_out_count=0;f.stream_out_last_count=0;
            for(integer n=0;n<8;n++) begin
                word_index=physical('h1000+4*n)>>2;init_word=payload(n);
                f.mem_inst.mem[word_index]=init_word;
            end
            f.axil_write(8'h58,8); // pause queue before filling it
            for(integer n=0;n<8;n++) f.enqueue_descriptor('h1000,0,32,2,n%3,16,n%2,n,0);
            f.enqueue_descriptor('h1000,0,32,2,0,16,1,99,0); // must reject, not overwrite
            f.axil_read(8'h5c,value);
            if(!value[12] || !value[9] || value[3:0]!=8) $fatal(1,"Descriptor full/overflow not reported");
            f.m_axis_tready=0;checking=1;queue_check=1;
            f.axil_write(8'h58,4); // resume
            wait(f.m_axis_tvalid);
            repeat(150) @(negedge f.clk);
            if(f.dut.completion_count!=0 || queue_done!=0) $fatal(1,"Stalled queue completed early");
            random_ready=1;
            waits=0;
            while(f.dut.completion_count!=8 && waits<30000) begin @(negedge f.clk);waits++;end
            if(waits==30000) $fatal(1,"Completion queue did not fill");
            f.enqueue_descriptor('h1000,0,32,2,0,16,1,8,0);
            repeat(100) @(negedge f.clk);
            if(queue_done!=8 || received!=64 || f.dut.desc_queue_count!=1)
                $fatal(1,"Full completion FIFO failed to backpressure queue");
            for(integer n=0;n<9;n++) begin
                waits=0;
                while(!f.dut.completion_valid && waits<10000) begin @(negedge f.clk);waits++;end
                if(waits==10000) $fatal(1,"Missing queued completion");
                f.pop_completion(value,bytes);
                if(value[31:24]!==n || value[2:0]!==3'b011 || bytes!==32)
                    $fatal(1,"Completion ID/order/bytes mismatch n=%0d status=%h bytes=%d",n,value,bytes);
            end
            repeat(25) @(negedge f.clk);
            if(queue_done!=9 || received!=72 || f.dut.completion_valid || f.dut.control_busy)
                $fatal(1,"Queued transfer leaked/dropped a packet");
            checking=0;queue_check=0;random_ready=0;f.m_axis_tready=1;
            $display("DMA QUEUE BACKPRESSURE/OVERFLOW/ORDER PASS: 9 packets, 9 ordered completions");
        end
    endtask

    task bus_error(input integer typ,mode,write_error,response,bytes);
        reg [31:0] result;
        integer expected_code;
        begin
            @(negedge f.clk);pattern=32'hbad0cafe;f.m_axis_tready=(typ!=2);
            f.stream_out_count=0;f.stream_out_last_count=0;
            f.mem_inst.mem['h1000]=pattern;
            injected_response=response;
            if(write_error) force f.m_axi_bresp=injected_response;
            else force f.m_axi_rresp=injected_response;
            fork
                f.run_dma('h1000,'h9000,bytes,typ,mode,16,result);
                // An AXI fault terminates after the first descriptor: do not
                // feed a second chunk and hide an abort by resetting the DUT.
                begin if(typ==1) send_words(mode==0 ? bytes/4 : 1);end
                begin
                    if(typ==2) begin
                        wait(f.m_axis_tvalid);
                        repeat(50) begin
                            @(negedge f.clk);
                            if(f.dut.dma_done || f.dut.dma_fault)
                                $fatal(1,"Read error retired before its stalled output drained");
                        end
                        f.m_axis_tready=1;
                    end
                end
            join
            release f.m_axi_bresp;release f.m_axi_rresp;
            expected_code=(typ==0 ? 'h40 : (typ==1 ? 'h60 : 'h50)) |
                (write_error ? (response==2 ? 6 : 7) : (response==2 ? 4 : 5));
            if(!result[2] || result[1] || result[15:8]!==expected_code)
                $fatal(1,"AXI error propagation type=%0d mode=%0d write=%0d resp=%0d status=%h",typ,mode,write_error,response,result);
            if(typ==2 && f.stream_out_count!=(mode==0 ? bytes/4 : 1))
                $fatal(1,"Read error left stale/dropped stream beats");
            bus_fault_checks++;
            // No resetting the DMA to hide stale error/FIFO state.
            good_transfer(typ,mode,32,8,'h1000,'h9000);
        end
    endtask

    task reset_stalled_m2s(input integer mode);
        begin
            checking=0;random_ready=0;enforce_completion=0;
            @(negedge f.clk);f.m_axis_tready=0;
            f.configure_dma('h1000,0,64,2,mode,16);f.start_dma();
            wait(f.m_axis_tvalid);
            repeat(15) @(negedge f.clk);
            f.rst_n=0;repeat(8) @(negedge f.clk);
            f.rst_n=1;f.m_axis_tready=1;repeat(8) @(negedge f.clk);
            if(f.m_axis_tvalid || f.dut.control_busy || f.dut.rd_status_pending_q ||
               f.dut.rd_output_drained_q || f.dut.completion_valid)
                $fatal(1,"Reset left stale M2S data/status");
            initialize_pages();
            good_transfer(2,mode,64,16,'h1000,'h9000);
            reset_checks++;
        end
    endtask

    integer lengths[0:19]='{4,8,12,28,32,60,64,68,124,128,132,252,256,260,1024,4092,4096,4100,8188,8192};
    integer bursts[0:6]='{0,1,2,3,15,16,255};
    integer src,dst,len,burst;
    initial begin
        for(integer t=0;t<3;t++) for(integer m=0;m<3;m++) covered[t][m]=0;
        wait(baseline_done);
        if(!baseline_pass) $fatal(1,"Original regression failed");
        repeat(10) @(negedge f.clk);
        initialize_pages();
        control_plane();
        queued_backpressure();
        for(integer m=0;m<3;m++) completion_backpressure(m);
        csv=$fopen("matrix_cases.csv","w");
        if(!csv) $fatal(1,"Cannot open coverage CSV");
        $fdisplay(csv,"trial,type,mode,bytes,burst_words,src_va,dst_va,axis_stalls,result");
        for(integer t=0;t<3;t++) for(integer m=0;m<3;m++) begin
            for(integer k=0;k<44;k++) begin
                if(k<20) begin
                    len=lengths[k];burst=bursts[k%7];
                    src='h1000+((k%3==0)?4092:((k%3==1)?4032:0));
                    dst='h9000+((k%3==0)?4080:((k%3==1)?4092:64));
                end else begin
                    next_random();src='h1000+(rng&4092);
                    next_random();dst='h9000+(rng&4092);
                    next_random();len=4*(1+rng%512);
                    next_random();burst=rng[7:0];
                end
                good_transfer(t,m,len,burst,src,dst);
            end
            $display("DMA MATRIX CELL PASS: type=%0d mode=%0d cases=%0d",t,m,covered[t][m]);
        end
        for(integer t=0;t<3;t++) for(integer m=0;m<3;m++) begin
            reject_transfer(t,m,'h1000,'h9000,0,1);
            reject_transfer(t,m,'h1000,'h9000,3,1);
            if(t!=1) reject_transfer(t,m,'h1001,'h9000,16,1);
            if(t!=2) reject_transfer(t,m,'h1000,'h9001,16,1);
            reject_transfer(t,3,'h1000,'h9000,16,1);
            if(t!=1) begin
                f.program_page(1,1,4,0,1);
                reject_transfer(t,m,'h1000,'h9000,16,'h22);
                f.program_page(1,1,4,1,1);
            end
            if(t!=2) begin
                f.program_page(9,9,12,1,0);
                reject_transfer(t,m,'h1000,'h9000,16,'h32);
                f.program_page(9,9,12,1,1);
            end
            good_transfer(t,m,16,4,'h1000,'h9000);
        end
        for(integer t=0;t<3;t++) for(integer m=0;m<3;m++) for(integer r=2;r<=3;r++) for(integer b=0;b<2;b++) begin
            if(t!=1) bus_error(t,m,0,r,b==0 ? 4 : 64);
            if(t!=2) bus_error(t,m,1,r,b==0 ? 4 : 64);
        end
        for(integer m=0;m<3;m++) reset_stalled_m2s(m);
        if(f.errors) $fatal(1,"Fixture accumulated errors=%0d",f.errors);
        $fclose(csv);
        $display("DMA MATRIX REVIEW TEST PASSED: %0d valid commands, %0d negative commands, %0d checked words; 9/9 cells",successes,negatives,words_checked);
        $display("DMA ADDITIONAL COVERAGE: %0d AXI faults with immediate recovery; %0d stalled M2S resets; %0d AXIL checks",bus_fault_checks,reset_checks,control_checks);
        $finish;
    end
    initial begin #100ms; $fatal(1,"DMA matrix global timeout"); end
endmodule
