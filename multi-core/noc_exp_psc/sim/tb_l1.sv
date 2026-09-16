`timescale 1ns/1ps
// Does an L2-delivered spike reach the cores the mask names?
// This decides whether L2 multicast can select cores independently per
// cluster, or is stuck with the same relative position everywhere.
module tb_l1;
    import noc_pkg::*;
    localparam NC = 4;
    logic clk=0, resetn=0;
    always #4 clk = ~clk;

    logic [16:0] s_addr_in [NC-1:0];
    logic [NC-1:0] s_valid_in, s_ready_in;
    logic [3:0]  s_mask [NC-1:0];
    logic [1:0]  s_level [NC-1:0];
    logic [16:0] s_addr_out [NC-1:0];
    logic [NC-1:0] s_valid_out, s_ready_out;
    logic [31:0] l2_tx_data; logic l2_tx_valid; logic l2_tx_ready=1;
    logic [31:0] l2_rx_data=0; logic l2_rx_valid=0; logic l2_rx_ready;
    logic busy;

    noc_l1_bus #(.CLUSTER_ID(0), .NUM_CORES(NC)) dut (
        .clk(clk), .resetn(resetn),
        .spike_addr_in(s_addr_in), .spike_valid_in(s_valid_in),
        .spike_ready_in(s_ready_in), .spike_dest_mask(s_mask),
        .spike_level(s_level),
        .spike_addr_out(s_addr_out), .spike_valid_out(s_valid_out),
        .spike_ready_out(s_ready_out),
        .l2_tx_data(l2_tx_data), .l2_tx_valid(l2_tx_valid), .l2_tx_ready(l2_tx_ready),
        .l2_rx_data(l2_rx_data), .l2_rx_valid(l2_rx_valid), .l2_rx_ready(l2_rx_ready),
        .bus_busy(busy));

    integer pass=0, fail=0;

    // packet: OP[31:30] SRC[29:26] MASK[25:22] NEURON_ADDR[21:5] TS[4:0]
    function [31:0] mkpkt(input [1:0] op, input [3:0] src,
                          input [3:0] mask, input [16:0] addr, input [4:0] ts);
        mkpkt = {op, src, mask, addr, ts};
    endfunction

    task l2_send(input [3:0] mask, input [16:0] addr, input [3:0] expect_cores,
                 input string label);
        logic [NC-1:0] got; integer k;
        begin
            got = '0;
            @(posedge clk); l2_rx_data <= mkpkt(OP_L2, 4'd0, mask, addr, 5'd1);
            l2_rx_valid <= 1;
            for (k = 0; k < 30; k = k + 1) begin
                @(posedge clk);
                for (int c = 0; c < NC; c++)
                    if (s_valid_out[c] && s_ready_out[c]) got[c] = 1;
                if (l2_rx_ready) l2_rx_valid <= 0;
            end
            l2_rx_valid <= 0; repeat (4) @(posedge clk);
            if (got === expect_cores) begin
                $display("  PASS %-34s mask=%04b -> cores %04b", label, mask, got);
                pass = pass + 1;
            end else begin
                $display("  FAIL %-34s mask=%04b -> cores %04b (expected %04b)",
                         label, mask, got, expect_cores);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        for (int c = 0; c < NC; c++) begin
            s_addr_in[c]=0; s_mask[c]=0; s_level[c]=OP_LOCAL;
        end
        s_valid_in='0; s_ready_out='1;
        repeat (4) @(posedge clk); resetn <= 1; repeat (4) @(posedge clk);

        $display("L1 bus: which cores does an L2-delivered spike reach?");
        $display("");
        l2_send(4'b0001, 17'h100, 4'b0001, "mask 0001");
        l2_send(4'b0101, 17'h200, 4'b0101, "mask 0101 -- cores 0 and 2");
        l2_send(4'b1111, 17'h300, 4'b1111, "mask 1111 -- broadcast");
        l2_send(4'b1000, 17'h400, 4'b1000, "mask 1000 -- core 3 only");

        $display("");
        $display("  %0d passed, %0d failed", pass, fail);
        $display("");
        $display("  If the mask selects cores here AND clusters in noc_l2_bus,");
        $display("  the same 4 bits mean different things at the two levels --");
        $display("  so an L2 multicast reaches the SAME core positions in every");
        $display("  destination cluster.  That is a partitioner constraint.");
        $finish;
    end
    initial begin #300000; $display("TIMEOUT"); $finish; end
endmodule
