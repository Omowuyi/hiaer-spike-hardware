`timescale 1ns/1ps
module tb;
    reg clk = 0, srst = 1; always #2 clk = ~clk;
    reg [31:0] din = 0; reg wr_en = 0, rd_en = 0; wire full, empty; wire [31:0] dout;
    fwft_fifo_core #(32, 10) dut(.clk(clk), .srst(srst), .din(din), .wr_en(wr_en), .full(full), .dout(dout), .rd_en(rd_en), .empty(empty));
    reg [31:0] q [0:4095]; integer qh = 0, qt = 0, n = 0, errors = 0, i, maxocc = 0, wrote = 0, read = 0;
    // one clock cycle: inputs set at the falling edge; the model takes exactly what the FIFO samples at the next rising edge
    task cyc(input w, input r); begin
        @(negedge clk); wr_en = w; rd_en = r; din = n;
        if (r && !empty) begin if (dout !== q[qh % 4096]) begin errors = errors + 1; if (errors < 5) $display("ORDER/LOSS error: got %0d expected %0d", dout, q[qh % 4096]); end qh = qh + 1; read = read + 1; end
        if (w && !full) begin q[qt % 4096] = n; qt = qt + 1; wrote = wrote + 1; n = n + 1; end
        if (full && (qt - qh) < 1024) begin errors = errors + 1; if (errors < 5) $display("FULL early at occupancy %0d", qt - qh); end
        if ((qt - qh) > maxocc) maxocc = qt - qh;
        @(posedge clk);
    end endtask
    initial begin
        repeat (4) @(posedge clk); srst = 0;
        for (i = 0; i < 1100; i = i + 1) cyc(1, 0);                       // fill with no reads
        $display("fill: %0d words accepted before full (full=%0d)", qt - qh, full);
        for (i = 0; i < 200000; i = i + 1) cyc(($random & 3) != 0, ($random & 3) != 0);   // random simultaneous traffic
        for (i = 0; i < 1300; i = i + 1) cyc(0, 1);                       // drain
        $display("random: written %0d, read %0d, left %0d, max occupancy %0d, errors %0d, empty at end %0d", wrote, read, qt - qh, maxocc, errors, empty);
        $display("%s", (errors == 0 && qt == qh && empty) ? "FIFO UNIT TEST: PASS" : "FIFO UNIT TEST: FAIL");
        $finish;
    end
endmodule
