`timescale 1ns/1ps
// Revoke permission while a page-table miss is being filled. A maintenance
// write must not leave a stale writable entry in the TLB for the next request.
module tb_iommu_maintenance_review;
    reg clk=0,rstn=0,valid=0,pw=0,perm=1,inv=0;
    always #2 clk=~clk;
    wire ready,rv,allow;wire [31:0] pa;wire [2:0] fault;
    integer stage,warm,checks=0;
    dma_iommu_tlb #(.ADDR_WIDTH(32),.LEN_WIDTH(32),.SECURE_LOCAL_RAM(1)) dut(
        .clk_i(clk),.rst_ni(rstn),.req_valid_i(valid),.req_ready_o(ready),
        .req_vaddr_i(32'h1000),.req_len_bytes_i(32'd16),.req_write_i(1'b1),
        .resp_valid_o(rv),.resp_allow_o(allow),.resp_paddr_o(pa),.resp_fault_o(fault),
        .pt_write_i(pw),.pt_index_i(4'd0),.pt_vpn_i(20'h1),.pt_ppn_i(20'h10),
        .pt_valid_i(1'b1),.pt_read_i(1'b1),.pt_write_perm_i(perm),.tlb_invalidate_i(inv),
        .tlb_hit_count_o(),.tlb_miss_count_o());
    task start;
        begin wait(ready);@(negedge clk);valid=1;@(negedge clk);valid=0;end
    endtask
    task wait_response(input expected);
        begin wait(rv);
            if(allow!==expected || fault!==(expected ? 0 : 2))
                $fatal(1,"stale permission after PT maintenance: stage=%0d warm=%0d allow=%b fault=%d",stage,warm,allow,fault);
            checks++;@(negedge clk);
        end
    endtask
    initial begin
        repeat(6) @(negedge clk);rstn=1;
        for(warm=0;warm<2;warm++) for(stage=1;stage<=3;stage++) begin
            wait(ready);@(negedge clk);perm=1;pw=1;@(negedge clk);pw=0;
            if(warm) begin start();wait_response(1);end
            start();wait(dut.state_q==stage);
            #0.1;perm=0;pw=1;@(posedge clk);@(negedge clk);pw=0;
            wait_response(0); // A pending lookup must restart against the new table.
            start();wait_response(0);
            start();wait_response(0); // Also exercise the refilled read-only TLB.
        end
        // A flush without changing permissions also restarts cleanly.
        for(stage=1;stage<=3;stage++) begin
            wait(ready);@(negedge clk);perm=1;pw=1;@(negedge clk);pw=0;
            start();wait_response(1);
            start();wait(dut.state_q==stage);
            #0.1;inv=1;@(posedge clk);@(negedge clk);inv=0;
            wait_response(1);start();wait_response(1);
        end
        $display("IOMMU MAINTENANCE REVIEW TEST PASSED: %0d responses, revoke during MATCH/RESP/CHECK, cold and warm TLB",checks);$finish;
    end
    initial begin #10000;$fatal(1,"maintenance timeout");end
endmodule
