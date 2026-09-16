`timescale 1ns/1ps
// Does the router actually route?  Load a table entry, present a spike,
// check the level and mask it emits.  Nothing here is assumed from reading.
module tb_router;
    import noc_pkg::*;
    logic clk=0, resetn=0;
    always #4 clk = ~clk;

    logic [16:0] addr_in;  logic valid_in;  logic ready_in;
    logic [16:0] addr_out;  logic valid_out; logic ready_out=1;
    logic [3:0]  dest_mask; logic [1:0] level;
    logic [16:0] addr_host; logic valid_host; logic ready_host=1;
    logic cfg_valid=0; logic [7:0] cfg_addr=0; logic [5:0] cfg_data=0;

    noc_spike_router dut (
        .clk(clk), .resetn(resetn),
        .spike_addr_in(addr_in), .spike_valid_in(valid_in), .spike_ready_in(ready_in),
        .spike_addr_out(addr_out), .spike_valid_out(valid_out), .spike_ready_out(ready_out),
        .spike_dest_mask(dest_mask), .spike_level(level),
        .spike_addr_host(addr_host), .spike_valid_host(valid_host), .spike_ready_host(ready_host),
        .route_cfg_valid(cfg_valid), .route_cfg_addr(cfg_addr), .route_cfg_data(cfg_data));

    task write_entry(input [7:0] a, input [1:0] lv, input [3:0] mk);
        begin
            @(posedge clk); cfg_addr <= a; cfg_data <= {lv, mk}; cfg_valid <= 1;
            @(posedge clk); cfg_valid <= 0;
            @(posedge clk);
        end
    endtask

    integer pass = 0, fail = 0;
    task send(input [16:0] a, input [1:0] exp_lv, input [3:0] exp_mk,
              input string exp_port, input string label);
        logic saw_noc, saw_host; logic [1:0] got_lv; logic [3:0] got_mk;
        integer k;
        begin
            saw_noc = 0; saw_host = 0; got_lv = 'x; got_mk = 'x;
            @(posedge clk); addr_in <= a; valid_in <= 1;
            for (k = 0; k < 20; k = k + 1) begin
                @(posedge clk);
                if (valid_out && !saw_noc) begin saw_noc=1; got_lv=level; got_mk=dest_mask; end
                if (valid_host && !saw_host) begin saw_host=1; end
                if (ready_in) begin valid_in <= 0; end
            end
            valid_in <= 0;
            repeat (3) @(posedge clk);
            if (exp_port == "noc") begin
                if (saw_noc && got_lv===exp_lv && got_mk===exp_mk) begin
                    $display("  PASS %-28s -> NoC  level=%b mask=%b", label, got_lv, got_mk);
                    pass=pass+1;
                end else begin
                    $display("  FAIL %-28s -> noc=%b host=%b level=%b mask=%b (want level=%b mask=%b)",
                             label, saw_noc, saw_host, got_lv, got_mk, exp_lv, exp_mk);
                    fail=fail+1;
                end
            end else begin
                if (saw_host && !saw_noc) begin
                    $display("  PASS %-28s -> HOST", label);
                    pass=pass+1;
                end else begin
                    $display("  FAIL %-28s -> noc=%b host=%b (want host only)", label, saw_noc, saw_host);
                    fail=fail+1;
                end
            end
        end
    endtask

    initial begin
        addr_in=0; valid_in=0;
        repeat (4) @(posedge clk); resetn <= 1; repeat (4) @(posedge clk);

        $display("routing table index = spike_addr[16:9]");
        $display("");

        // block 1 -> L1 to cores 1 and 3 ; block 2 -> L2 to clusters 0 and 2
        write_entry(8'd1, OP_L1, 4'b1010);
        write_entry(8'd2, OP_L2, 4'b0101);
        write_entry(8'd3, OP_NOP, 4'b1111);

        send(17'd0,        OP_LOCAL, 4'b0000, "host", "block 0, reset default LOCAL");
        send(17'd1 <<9,    OP_L1,    4'b1010, "noc",  "block 1, configured L1");
        send(17'd2 <<9,    OP_L2,    4'b0101, "noc",  "block 2, configured L2");
        send(17'd3 <<9,    OP_NOP,   4'b1111, "host", "block 3, NOP");
        send((17'd1<<9)+5, OP_L1,    4'b1010, "noc",  "block 1 + offset 5");

        $display("");
        $display("  %0d passed, %0d failed", pass, fail);
        $finish;
    end
    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
