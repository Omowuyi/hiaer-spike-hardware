`timescale 1ns / 1ps
//=============================================================================
// tb_at3.sv -- axon_trace_mem, the cases tb_at2 did not reach.
//
// tb_at2 passed 11 of 11 while two real defects were live, because it drove
// one microphase and one group.  Both defects hid exactly outside that:
//
//   * NUM_ROWS defaulted to 512 while the EEP row address is 13 bits spanning
//     microphases (waddr = microphase_ctr*512 + offset).  Rows 512 and above
//     aliased onto rows 0 and above.
//
//   * stdp_controller took src_axon_idx = e_src[12:0], discarding the group
//     field, so all sixteen axons in a row read group 0's trace.
//
// This bench instantiates with NUM_ROWS = 8192, the value single_core now
// overrides, and drives rows and groups across their full range.
//=============================================================================

module tb_at3;

    localparam NUM_ROWS   = 8192;
    localparam ROW_BITS   = 13;
    localparam NUM_GROUPS = 16;
    localparam TS_BITS    = 5;
    localparam TRACE_BITS = 4;

    reg                    clk = 1'b0;
    reg                    resetn = 1'b0;
    reg  [TS_BITS-1:0]     timestep = 5'd0;
    reg                    timestep_tick = 1'b0;

    reg                    row_fired = 1'b0;
    reg  [ROW_BITS-1:0]    row_addr = 13'd0;
    reg  [NUM_GROUPS-1:0]  row_mask = 16'd0;

    reg                    trace_rd_en = 1'b0;
    reg  [16:0]            trace_rd_idx = 17'd0;
    wire [TRACE_BITS-1:0]  trace_rd_data;

    integer pass = 0;
    integer fail = 0;

    always #5 clk = ~clk;

    axon_trace_mem #(
        .NUM_ROWS   (NUM_ROWS),
        .ROW_BITS   (ROW_BITS),
        .NUM_GROUPS (NUM_GROUPS),
        .TS_BITS    (TS_BITS),
        .TRACE_BITS (TRACE_BITS)
    ) dut (
        .clk           (clk),
        .resetn        (resetn),
        .timestep      (timestep),
        .timestep_tick (timestep_tick),
        .row_fired     (row_fired),
        .row_addr      (row_addr),
        .row_mask      (row_mask),
        .trace_rd_en   (trace_rd_en),
        .trace_rd_idx  (trace_rd_idx),
        .trace_rd_data (trace_rd_data)
    );

    // Fire one row with the given mask, at the current timestep.
    task fire(input [ROW_BITS-1:0] r, input [NUM_GROUPS-1:0] m);
        begin
            @(negedge clk);
            row_addr  = r;
            row_mask  = m;
            row_fired = 1'b1;
            @(negedge clk);
            row_fired = 1'b0;
            row_mask  = 16'd0;
        end
    endtask

    // Advance the timestep counter by n.
    task step(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                timestep_tick = 1'b1;
                timestep = timestep + 5'd1;
                @(negedge clk);
                timestep_tick = 1'b0;
            end
        end
    endtask

    // Read axon {row, group} and compare against expected.
    task chk(input [ROW_BITS-1:0] r, input [3:0] g,
                input [TRACE_BITS-1:0] exp, input [55*8:1] name);
        begin
            @(negedge clk);
            trace_rd_idx = {r, g};
            trace_rd_en  = 1'b1;
            @(negedge clk);
            trace_rd_en  = 1'b0;
            @(negedge clk);
            @(negedge clk);
            if (trace_rd_data === exp) begin
                pass = pass + 1;
                $display("  PASS  %-52s row=%0d grp=%0d -> %0d", name, r, g, trace_rd_data);
            end else begin
                fail = fail + 1;
                $display("  FAIL  %-52s row=%0d grp=%0d -> %0d, expected %0d",
                         name, r, g, trace_rd_data, exp);
            end
        end
    endtask

    integer k;

    initial begin
        $display("\n=== tb_at3: rows beyond 511, and all sixteen groups ===\n");

        repeat (4) @(negedge clk);
        resetn = 1'b1;
        repeat (4) @(negedge clk);

        //---------------------------------------------------------------
        // A. Rows spanning microphases must not alias.
        //    With NUM_ROWS=512 these all collapse onto rows 0..3.
        //---------------------------------------------------------------
        $display("A. microphase spread");
        fire(13'd0,    16'h0001);      // microphase 0
        fire(13'd512,  16'h0001);      // microphase 1
        fire(13'd1024, 16'h0001);      // microphase 2
        fire(13'd8191, 16'h0001);      // last row

        chk(13'd0,    4'd0, 4'd15, "row 0 fired");
        chk(13'd512,  4'd0, 4'd15, "row 512 fired");
        chk(13'd1024, 4'd0, 4'd15, "row 1024 fired");
        chk(13'd8191, 4'd0, 4'd15, "row 8191 fired");

        // Rows that were never fired must read zero, not a neighbour's value.
        chk(13'd1,    4'd0, 4'd0,  "row 1 never fired");
        chk(13'd513,  4'd0, 4'd0,  "row 513 never fired");
        chk(13'd4096, 4'd0, 4'd0,  "row 4096 never fired");

        //---------------------------------------------------------------
        // B. Every group must be independently addressable.
        //    With a 13-bit index the group field is lost and all sixteen
        //    read group 0.
        //---------------------------------------------------------------
        $display("\nB. group independence, one row");
        fire(13'd2000, 16'h0100);      // group 8 only

        chk(13'd2000, 4'd8,  4'd15, "group 8 fired");
        for (k = 0; k < 16; k = k + 1)
            if (k != 8)
                chk(13'd2000, k[3:0], 4'd0, "other group untouched");

        //---------------------------------------------------------------
        // C. A full mask must set every group in that row.
        //---------------------------------------------------------------
        $display("\nC. full mask");
        fire(13'd3000, 16'hFFFF);
        for (k = 0; k < 16; k = k + 1)
            chk(13'd3000, k[3:0], 4'd15, "all groups fired");

        //---------------------------------------------------------------
        // D. Decay, on a row well above 511.
        //---------------------------------------------------------------
        $display("\nD. decay on a high row");
        fire(13'd5000, 16'h0004);      // group 2
        chk(13'd5000, 4'd2, 4'd15, "age 0");
        step(1); chk(13'd5000, 4'd2, 4'd7, "age 1");
        step(1); chk(13'd5000, 4'd2, 4'd3, "age 2");
        step(1); chk(13'd5000, 4'd2, 4'd1, "age 3");
        step(1); chk(13'd5000, 4'd2, 4'd0, "age 4, decayed out");

        //---------------------------------------------------------------
        // E. Re-firing a decayed entry restores it.
        //---------------------------------------------------------------
        $display("\nE. re-fire after decay");
        fire(13'd5000, 16'h0004);
        chk(13'd5000, 4'd2, 4'd15, "refreshed");

        //---------------------------------------------------------------
        // F. Timestep counter wraparound.  timestep is 5 bits, so firing
        //    near 31 and reading after the wrap exercises the modulo
        //    subtraction in the decay.
        //---------------------------------------------------------------
        $display("\nF. counter wraparound");
        while (timestep != 5'd30) step(1);
        fire(13'd6000, 16'h8000);      // group 15
        chk(13'd6000, 4'd15, 4'd15, "fired at ts 30");
        step(1);  chk(13'd6000, 4'd15, 4'd7, "ts 31, age 1");
        step(1);  chk(13'd6000, 4'd15, 4'd3, "ts 0 after wrap, age 2");
        step(1);  chk(13'd6000, 4'd15, 4'd1, "ts 1, age 3");

        //---------------------------------------------------------------
        // G. Two rows in different microphases, same group, different
        //    timesteps -- the case that would silently merge under aliasing.
        //---------------------------------------------------------------
        $display("\nG. independent ageing across microphases");
        fire(13'd100, 16'h0002);       // group 1, now
        step(2);
        fire(13'd612, 16'h0002);       // group 1, two steps later
        chk(13'd612, 4'd1, 4'd15, "recent row full");
        chk(13'd100, 4'd1, 4'd3,  "older row aged by 2");

        $display("\n=== %0d passed, %0d failed ===\n", pass, fail);
        if (fail == 0) $display("ALL PASS\n");
        else           $display("FAILURES PRESENT\n");
        $finish;
    end

endmodule
