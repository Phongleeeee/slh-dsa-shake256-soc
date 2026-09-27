`timescale 1ns/1ps
`default_nettype none
// Executes the published RV32 firmware, not a host/native crypto substitute.
// Functional UART RPC coverage; full signature jobs still require board testing.
module tb_portable_service_uart #(
    parameter MEM_INIT_FILE="../../firmware/slh_dsa_portable.mem"
);
    reg clk=0, resetn=0, uart_rx=1;
    wire uart_tx,trap,bus_error;
    wire [31:0] gpio;
    always #5 clk=~clk;
    portable_slh_soc_core #(.CLOCK_HZ(100_000_000),.BAUD_RATE(100_000),
        .MEM_INIT_FILE(MEM_INIT_FILE)) dut (
        .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .gpio_out(gpio),.trap(trap),.bus_error(bus_error),
        .ext_m_axi_awready(1'b0),.ext_m_axi_wready(1'b0),
        .ext_m_axi_bid(5'd0),.ext_m_axi_bresp(2'd0),.ext_m_axi_bvalid(1'b0),
        .ext_m_axi_arready(1'b0),.ext_m_axi_rid(5'd0),
        .ext_m_axi_rdata(32'd0),.ext_m_axi_rresp(2'd0),
        .ext_m_axi_rlast(1'b0),.ext_m_axi_rvalid(1'b0)
    );
    reg ready=0;
    reg [7:0] tx_byte;
    reg [7:0] rx_queue[0:4095],frame[0:1043],reply[0:1043];
    integer written=0,read_index=0,bit_index,payload_index,checks=0;
    string line="";
    function [31:0] crc_byte(input [31:0] crc,input [7:0] data);
        reg [31:0] c; integer j;
        begin
            c=crc^data;
            for(j=0;j<8;j=j+1) c=(c>>1)^(c[0]?32'hedb88320:0);
            crc_byte=c;
        end
    endfunction
    task put32(input integer p,input [31:0] value);
        integer j; begin for(j=0;j<4;j=j+1) frame[p+j]=value>>(8*j); end
    endtask
    task send_byte(input [7:0] value);
        integer j;
        begin
            @(negedge clk); uart_rx=0; repeat(1000) @(negedge clk);
            for(j=0;j<8;j=j+1) begin uart_rx=value[j]; repeat(1000) @(negedge clk); end
            uart_rx=1; repeat(1000) @(negedge clk);
        end
    endtask
    task request(input [7:0] op,input [31:0] seq,input integer n,input integer corrupt);
        reg [31:0] crc; integer j;
        begin
            frame[0]="S";frame[1]="L";frame[2]="H";frame[3]="3";
            frame[4]=1;frame[5]=op;frame[6]=0;frame[7]=0;
            put32(8,seq);put32(12,n);
            crc=32'hffffffff;
            for(j=0;j<16;j=j+1) crc=crc_byte(crc,frame[j]);
            for(j=0;j<n;j=j+1) crc=crc_byte(crc,frame[20+j]);
            put32(16,(crc^32'hffffffff)^corrupt);
            for(j=0;j<20+n;j=j+1) send_byte(frame[j]);
        end
    endtask
    task response(input [7:0] op,input [31:0] seq,input integer n,input integer status);
        integer j; reg [31:0] crc,received_crc,received_seq,received_len;
        begin
            wait(written>=read_index+20+n);
            for(j=0;j<20+n;j=j+1) reply[j]=rx_queue[read_index+j];
            read_index=read_index+20+n;
            received_seq={reply[11],reply[10],reply[9],reply[8]};
            received_len={reply[15],reply[14],reply[13],reply[12]};
            if({reply[0],reply[1],reply[2],reply[3]}!==32'h534c4833 ||
               reply[4]!==1 || reply[5]!==(op|8'h80) ||
               {reply[7],reply[6]}!==status || received_seq!==seq || received_len!==n)
                $fatal(1,"UART RPC response header/op/sequence/length/status mismatch");
            crc=32'hffffffff;
            for(j=0;j<16;j=j+1) crc=crc_byte(crc,reply[j]);
            for(j=0;j<n;j=j+1) crc=crc_byte(crc,reply[20+j]);
            received_crc={reply[19],reply[18],reply[17],reply[16]};
            if((crc^32'hffffffff)!==received_crc) $fatal(1,"UART response CRC mismatch");
            checks=checks+1;
            $display("UART RPC response op=%0d seq=%0d accepted at %0t",op,seq,$time);
        end
    endtask
    initial begin
        repeat(20) @(posedge clk);resetn<=1;
        wait(ready);repeat(300) @(posedge clk);
        request(1,1,0,0);response(1,1,28,0);
        if({reply[27],reply[26],reply[25],reply[24]}!==100_000_000 ||
           {reply[43],reply[42],reply[41],reply[40]}!==0) $fatal(1,"INFO clock/key state wrong");
        request(1,1,0,0);response(1,1,28,0); // duplicate cached reply
        frame[20]=2;frame[21]=0;frame[22]=0;frame[23]=0;
        request(12,2,4,0);response(12,2,0,0);
        request(1,3,0,0);response(1,3,28,0);
        if(reply[36]!==2) $fatal(1,"Mode change failed");
        request(14,4,0,0);response(14,4,0,0);
        request(11,5,0,0);response(11,5,0,0);
        // Request opcodes must have bit7 clear; 100 is unknown but well-formed.
        request(100,6,0,0);response(100,6,0,1);
        // Real RV32 parser bounds/state checks; no host substitute.
        frame[20]=3;frame[21]=0;frame[22]=0;frame[23]=0;
        request(12,20,4,0);response(12,20,0,1); // invalid mode
        request(12,21,3,0);response(12,21,0,1); // truncated mode
        request(10,22,0,0);response(10,22,0,2); // no private key
        for(payload_index=0;payload_index<32;payload_index=payload_index+1) frame[20+payload_index]=1;
        request(5,23,32,0);response(5,23,0,2); // no key/message
        put32(20,16385);frame[24]=0;
        request(3,24,5,0);response(3,24,0,5); // message too large
        put32(20,1);frame[24]=255;
        request(3,25,5,0);response(3,25,0,1); // missing context
        // Longest context and a fragmented/incomplete one-byte message.
        for(payload_index=0;payload_index<255;payload_index=payload_index+1) frame[25+payload_index]=payload_index;
        request(3,26,260,0);response(3,26,0,0);
        put32(20,1);frame[24]="X";
        request(4,27,5,0);response(4,27,0,5); // out-of-order
        put32(20,0);
        request(4,28,5,0);response(4,28,0,0);
        request(4,28,5,0);response(4,28,0,0); // retry must be cached
        request(4,29,5,0);response(4,29,0,5); // same offset, new request
        put32(20,49856);
        request(8,30,4,0);response(8,30,0,0);
        put32(20,0);frame[24]=1;
        request(9,31,5,0);response(9,31,0,0);
        for(payload_index=0;payload_index<64;payload_index=payload_index+1) frame[20+payload_index]=0;
        request(7,32,64,0);response(7,32,0,2); // incomplete signature
        request(13,33,0,0);response(13,33,40,0);
        for(payload_index=20;payload_index<60;payload_index=payload_index+1)
            if(reply[payload_index]!==0) $fatal(1,"ZEROIZE left historical metrics behind");
        request(1,7,0,1);
        // Fail-closed cleanup wipes ~77 KiB on RV32. Wait for its final
        // private-stack store instead of sending into the one-byte RX register
        // while the firmware is intentionally not accepting new commands.
        wait(dut.m0_axi_awvalid && dut.m0_axi_awready && dut.m0_axi_awaddr==32'h2fffc);
        repeat(2000) @(posedge clk);
        if(written!=read_index) $fatal(1,"Corrupt CRC received a success response");
        request(1,8,0,0);response(1,8,28,0);
        $display("PORTABLE RV32 UART RPC BOUNDS/STATE/CONTEXT/CHUNK/RETRY/CRC RECOVERY TEST PASSED (%0d responses)",checks);
        $finish;
    end
    initial begin
        wait(resetn);
        forever begin
            @(negedge uart_tx);repeat(1500) @(posedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                tx_byte[bit_index]=uart_tx;repeat(1000) @(posedge clk);
            end
            if(!uart_tx) $fatal(1,"UART TX framing failure");
            if(ready) begin
                if(written>=4096) $fatal(1,"Receive queue overflow");
                rx_queue[written]=tx_byte;written=written+1;
            end else if(tx_byte==10) begin
                $display("FIRMWARE UART: %s",line);
                if(line=="SLH3 READY: volatile key; trusted UART; no board TRNG") ready=1;
                line="";
            end else if(tx_byte!=13) line={line,tx_byte};
        end
    end
    always @(posedge clk) if(resetn && (trap || bus_error || gpio[3:0]==2))
        $fatal(1,"Firmware CPU/AXI/boot failure");
    always @(posedge clk) if(ready && dut.peripherals.uart.rx_overrun_q)
        $fatal(1,"UART test speed caused RX overrun");
    initial begin #600_000_000;$fatal(1,"UART RPC timeout checks=%0d written=%0d read=%0d cpu_pc=%h",checks,written,read_index,dut.cpu.picorv32_core.reg_pc);end
endmodule
`resetall
