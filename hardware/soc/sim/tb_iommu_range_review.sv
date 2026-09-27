`timescale 1ns/1ps
module iommu_range_checker #(parameter A=32,L=32)(output reg done=0);
    reg clk=0,rstn=0,valid=0,pw=0;
    always #2 clk=~clk;
    reg [A-1:0] addr=0;
    reg [L-1:0] len=0;
    wire ready,rv,allow;
    wire [A-1:0] pa;
    wire [2:0] fault;
    reg [A-13:0] page=0;
    integer checks=0,offset,kind;
    reg [31:0] random_q=32'h1024205;
    reg [63:0] mathematical_end;
    reg expected;
    dma_iommu_tlb #(.ADDR_WIDTH(A),.LEN_WIDTH(L),.SECURE_LOCAL_RAM(0)) dut(
        .clk_i(clk),.rst_ni(rstn),.req_valid_i(valid),.req_ready_o(ready),
        .req_vaddr_i(addr),.req_len_bytes_i(len),.req_write_i(1'b0),
        .resp_valid_o(rv),.resp_allow_o(allow),.resp_paddr_o(pa),.resp_fault_o(fault),
        .pt_write_i(pw),.pt_index_i(4'd0),.pt_vpn_i(page),.pt_ppn_i(page),
        .pt_valid_i(1'b1),.pt_read_i(1'b1),.pt_write_perm_i(1'b1),.tlb_invalidate_i(pw),
        .tlb_hit_count_o(),.tlb_miss_count_o());
    task request(input [63:0] address,input [63:0] length);
        begin
            wait(ready);@(negedge clk);addr=address;len=length;page=address>>12;pw=1;
            @(negedge clk);pw=0;valid=1;@(negedge clk);valid=0;
            mathematical_end={1'b0,addr[11:0]}+64'(len);
            expected=(len!=0 && mathematical_end<=4096);
            wait(rv);
            if(allow!==expected || fault!==(expected ? 0 : 3) || (expected && pa!==addr))
                $fatal(1,"range mismatch A=%0d L=%0d addr=%h len=%h allow=%b expected=%b",A,L,addr,len,allow,expected);
            checks++;@(negedge clk);
        end
    endtask
    initial begin
        repeat(6) @(negedge clk);rstn=1;
        // A length wider than the virtual address must not wrap into validity.
        request(0,64'h20004);
        for(offset=0;offset<4096;offset++) begin
            request(32'hfffff000+offset,0);
            request(32'hfffff000+offset,1);
            request(32'hfffff000+offset,4096-offset);
            request(32'hfffff000+offset,4097-offset);
            request(32'hfffff000+offset,4096);
            request(32'hfffff000+offset,4097);
        end
        for(kind=0;kind<1024;kind++) begin
            random_q=random_q^(random_q<<13);random_q=random_q^(random_q>>17);random_q=random_q^(random_q<<5);
            request(32'hff000000+kind,random_q);
        end
        $display("IOMMU RANGE A=%0d L=%0d PASSED: %0d requests",A,L,checks);
        done=1;
    end
endmodule
module tb_iommu_range_review;
    wire a,b;
    iommu_range_checker #(.A(16),.L(20)) small_addr(a);
    iommu_range_checker #(.A(32),.L(32)) soc_addr(b);
    initial begin wait(a && b);$display("IOMMU RANGE REVIEW TEST PASSED: 51202 requests, all page offsets, lengths and wraparound");$finish;end
    initial begin #10_000_000;$fatal(1,"range review timeout");end
endmodule
