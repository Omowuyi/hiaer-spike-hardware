`timescale 1ns/1ps
// Does an L2 spike actually cross clusters, and what does it do with the
// source cluster's own mask bit?
module tb_l2;
    import noc_pkg::*;
    localparam NCL = 4;
    logic clk=0, resetn=0;
    always #4 clk = ~clk;

    logic [31:0] tx_data [NCL-1:0];
    logic [NCL-1:0] tx_valid, tx_ready;
    logic [31:0] rx_data [NCL-1:0];
    logic [NCL-1:0] rx_valid, rx_ready;
    logic busy;

    noc_l2_bus #(.NUM_CLUSTERS(NCL)) dut (
        .clk(clk), .resetn(resetn),
        .l1_tx_data(tx_data), .l1_tx_valid(tx_valid), .l1_tx_ready(tx_ready),
        .l1_rx_data(rx_data), .l1_rx_valid(rx_valid), .l1_rx_ready(rx_ready),
        .bus_busy(busy));

    integer pass=0, fail=0;

    function [31:0] mkpkt(input [1:0] op, input [3:0] src,
                          input [3:0] mask, input [16:0] addr, input [4:0] ts);
        mkpkt = {op, src, mask, addr, ts};
    endfunction

    task send(input [1:0] from, input [3:0] mask, input [16:0] addr,
              input [3:0] expect_cl, input string label);
        logic [NCL-1:0] got; integer k; logic [16:0] gotaddr;
            logic [3:0] gotmask; logic [1:0] gotlevel;
        begin
            got = '0; gotaddr = '0;
            @(posedge clk);
            tx_data[from] <= mkpkt(OP_L2, {2'd0, from}, mask, addr, 5'd1);
            tx_valid[from] <= 1;
            for (k = 0; k < 25; k = k + 1) begin
                @(posedge clk);
                for (int c = 0; c < NCL; c++)
                    if (rx_valid[c]) begin
                        got[c] = 1; gotaddr = rx_data[c][21:5];
                        gotmask = rx_data[c][25:22];
                        gotlevel = rx_data[c][31:30];
                    end
                if (tx_ready[from]) tx_valid[from] <= 0;
            end
            tx_valid[from] <= 0; repeat (4) @(posedge clk);
            if (got === expect_cl && (expect_cl == 0 || gotaddr === addr)) begin
                $display("  PASS %-38s -> clusters %04b addr=%0d fwd_level=%02b fwd_mask=%04b",
                         label, got, gotaddr, gotlevel, gotmask);
                pass = pass + 1;
            end else begin
                $display("  FAIL %-38s -> clusters %04b (want %04b) addr=%0d (want %0d)",
                         label, got, expect_cl, gotaddr, addr);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        for (int c = 0; c < NCL; c++) tx_data[c] = 0;
        tx_valid = '0; rx_ready = '1;
        repeat (4) @(posedge clk); resetn <= 1; repeat (4) @(posedge clk);

        $display("L2 bus: cluster-to-cluster delivery");
        $display("");
        send(2'd0, 4'b0010, 17'd100, 4'b0010, "cluster 0 -> cluster 1");
        send(2'd0, 4'b1010, 17'd200, 4'b1010, "cluster 0 -> clusters 1 and 3");
        send(2'd0, 4'b0001, 17'd300, 4'b0000, "cluster 0 -> itself (d != src)");
        send(2'd0, 4'b1111, 17'd400, 4'b1110, "cluster 0 -> all (self excluded)");
        send(2'd2, 4'b0001, 17'd500, 4'b0001, "cluster 2 -> cluster 0");

        $display("");
        $display("  %0d passed, %0d failed", pass, fail);
        $finish;
    end
    initial begin #150000; $display("TIMEOUT"); $finish; end
endmodule
