`timescale 1ns/1ps
module tb_iommu_secure;
    reg clk=0,rstn=0,valid=0,write_req=0,pw=0,inv=0,pr=1,ppw=1;
    reg [31:0] addr=0,len=16; reg [19:0] vpn=1,ppn=16;
    wire ready,rv,allow; wire [31:0] pa; wire [2:0] fault;
    always #2 clk=~clk;
    dma_iommu_tlb #(.ADDR_WIDTH(32),.LEN_WIDTH(32),.SECURE_LOCAL_RAM(1)) dut(
        .clk_i(clk),.rst_ni(rstn),.req_valid_i(valid),.req_ready_o(ready),
        .req_vaddr_i(addr),.req_len_bytes_i(len),.req_write_i(write_req),
        .resp_valid_o(rv),.resp_allow_o(allow),.resp_paddr_o(pa),.resp_fault_o(fault),
        .pt_write_i(pw),.pt_index_i(4'd0),.pt_vpn_i(vpn),.pt_ppn_i(ppn),
        .pt_valid_i(1'b1),.pt_read_i(pr),.pt_write_perm_i(ppw),.tlb_invalidate_i(inv),
        .tlb_hit_count_o(),.tlb_miss_count_o());
    task map(input [19:0] v,input [19:0] p,input writable);
        begin @(negedge clk); vpn=v; ppn=p; ppw=writable; pw=1; inv=1;
            @(negedge clk); pw=0; inv=0; repeat(2) @(negedge clk); end
    endtask
    task request(input [31:0] a,input [31:0] n,input w,input expected,input [2:0] f);
        begin wait(ready); @(negedge clk); addr=a; len=n; write_req=w; valid=1;
            @(negedge clk); valid=0; wait(rv);
            if(allow!==expected || fault!==f) $fatal(1,"firewall %h allow %b fault %d ptv=%h ppn=%h valid=%b req=%h match=%b",a,allow,fault,dut.pt_vpn_q[0],dut.pt_ppn_q[0],dut.pt_valid_q[0],dut.req_vaddr_q,dut.match_pt_hit_q);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(6) @(negedge clk); rstn=1;
        map(1,'h10,1); request('h1000,16,0,1,0); request('h1000,16,1,1,0);
        map(1,'h2d,1); request('h1000,16,0,0,2); request('h1000,16,1,0,2);
        map(1,'h2b,1); request('h1000,16,0,0,2);
        map(1,'h2f,1); request('h1000,16,0,0,2);
        map(1,0,1); request('h1000,16,1,0,2);
        map(1,'h30,1); request('h1000,16,0,0,2);
        map(1,'h10,0); request('h1000,16,0,1,0); request('h1000,16,1,0,2);
        map('h2d,'h10,1); request('h2d000,16,0,1,0);
        request('h2dff0,32,0,0,3); request('h2d000,0,0,0,3);
        map('hfffff,'h10,1); request('hfffffff0,32,0,0,3);
        $display("IOMMU PHYSICAL VAULT/STACK/BOOT/MMIO FIREWALL + ALIAS TEST PASSED"); $finish;
    end
    initial begin #10000; $fatal(1,"secure IOMMU timeout"); end
endmodule
