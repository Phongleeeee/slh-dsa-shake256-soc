`timescale 1ns/1ps
module tb_portable_dma_regression;
    wire done, pass;
    integer snapshots_checked = 0;
    tb_dma_mmu_axi_top #(
        .AUTO_FINISH(0), .LOG_PATH("dma_function.log"),
        .PERF_LOG_PATH("dma_throughput.log"), .EDGE_LOG_PATH("dma_edges.log")
    ) regression (.test_done_o(done), .test_pass_o(pass));
    // Independently check publication against the counters frozen on the
    // preceding edge, including final beats, queued starts and fault cases.
    task automatic check_snapshot(
        input logic [31:0] seq, length, total_cycles,
        input logic [1:0] transfer_type, dma_mode,
        input logic fault,
        input logic [31:0] src_bytes, src_span, dst_bytes, dst_span,
        input logic [31:0] r_bytes, r_cycles, w_bytes, w_cycles
    );
        #0.01;
        if (!regression.dut.perf_valid ||
            regression.dut.perf_seq !== seq ||
            regression.dut.perf_length !== length ||
            regression.dut.perf_total_cycles !== total_cycles ||
            regression.dut.perf_transfer_type !== transfer_type ||
            regression.dut.perf_dma_mode !== dma_mode ||
            regression.dut.perf_fault !== fault ||
            regression.dut.perf_src_bytes !== src_bytes ||
            regression.dut.perf_src_span !== src_span ||
            regression.dut.perf_dst_bytes !== dst_bytes ||
            regression.dut.perf_dst_span !== dst_span ||
            regression.dut.perf_axi_r_bytes !== r_bytes ||
            regression.dut.perf_axi_r_cycles !== r_cycles ||
            regression.dut.perf_axi_w_bytes !== w_bytes ||
            regression.dut.perf_axi_w_cycles !== w_cycles)
            $fatal(1, "Pipelined DMA performance snapshot mismatch");
        snapshots_checked++;
    endtask
    always @(posedge regression.clk) begin
        if (regression.rst_n && regression.dut.perf_active_q &&
            regression.dut.perf_dst_remaining_q !==
                (regression.dut.perf_dst_bytes_q < regression.dut.perf_length_q ?
                    regression.dut.perf_length_q - regression.dut.perf_dst_bytes_q : 0))
            $fatal(1, "DMA remaining-byte counter differs from length minus accepted bytes");
        if (regression.rst_n && regression.dut.perf_snapshot_q)
            check_snapshot(
                regression.dut.perf_seq + 1,
                regression.dut.perf_length_q,
                regression.dut.perf_cycle_q,
                regression.dut.perf_type_q,
                regression.dut.perf_mode_q,
                regression.dut.perf_snapshot_fault_q,
                regression.dut.perf_src_bytes_q,
                regression.dut.perf_src_seen_q ?
                    regression.dut.perf_src_last_q - regression.dut.perf_src_first_q + 1 : 0,
                regression.dut.perf_dst_bytes_q,
                regression.dut.perf_dst_seen_q ?
                    regression.dut.perf_dst_last_q - regression.dut.perf_dst_first_q + 1 : 0,
                regression.dut.perf_axi_r_bytes_q,
                regression.dut.perf_ar_seen_q && regression.dut.perf_r_done_seen_q ?
                    regression.dut.perf_r_done_q - regression.dut.perf_ar_first_q + 1 : 0,
                regression.dut.perf_axi_w_bytes_q,
                regression.dut.perf_aw_seen_q && regression.dut.perf_b_done_seen_q ?
                    regression.dut.perf_b_done_q - regression.dut.perf_aw_first_q + 1 : 0
            );
    end
    initial begin
        wait (done);
        if (!pass) $fatal(1, "DMA/IOMMU robustness regression failed");
        if (snapshots_checked < 9) $fatal(1, "Missing DMA snapshot coverage");
        $display("DMA SNAPSHOT CHECKS PASSED: %0d", snapshots_checked);
        $display("PORTABLE DMA/IOMMU ROBUSTNESS TEST PASSED");
        $finish;
    end
endmodule
