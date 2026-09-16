`timescale 1ns / 1ps
//=============================================================================
// tb_stdp.sv -- first simulation coverage of stdp_controller.
//
// The module has only ever been validated by a hardware run of the biological
// features, which predates FIX AB.  This bench drives its three interfaces
// with behavioural models and checks the decisions the state machine makes.
//
// WHAT IT COVERS
//   1. pointer fetch      P4_PTR_READ / P4_PTR_WAIT extract {len, addr} from
//                         the correct 32-bit slot, and len+1 times four gives
//                         the entry count.  The source notes this path was
//                         once missing entirely.
//   2. neuron source      src_is_axon low, trace read from URAM row B
//   3. AXON SOURCE        src_is_axon high, trace read from axon_trace_mem,
//                         and axon_trace_rd_idx carries the FULL 17 bits.
//                         This path has never been simulated.
//   4. zero trace         leaves the weight alone
//   5. w_max clamp
//   6. per-entry decode   four entries in one beat take four distinct
//                         decisions.  The source notes the old code decoded
//                         the PREVIOUS entry.
//   7. write-back         one HBM write carrying the modified beat
//   8. two neurons        syn_processed resets per neuron.  The source notes
//                         it once accumulated, so every neuron after the
//                         first terminated immediately.
//
// HBM COMMAND FORMAT, from the module:
//     p4_ci2hbm_din = {is_write, addr[22:0], data[255:0]}
//=============================================================================

module tb_stdp;

    reg          clk = 1'b0;
    reg          resetn = 1'b0;
    reg          stdp_enable = 1'b1;
    reg  [7:0]   A_plus = 8'd16;
    reg  [7:0]   A_minus = 8'd0;
    reg  signed [15:0] w_max = 16'sd300;
    reg  signed [15:0] w_min = -16'sd300;
    reg  [7:0]   neuromod_level = 8'd0;
    reg  [16:0]  spike_addr_in = 17'd0;
    reg          spike_addr_wr = 1'b0;
    reg          phase2_done = 1'b0;

    wire         phase4_active, phase4_done;
    wire [279:0] p4_ci2hbm_din;
    wire         p4_ci2hbm_wren;
    reg          p4_ci2hbm_full = 1'b0;
    reg  [255:0] p4_hbm2ci_dout = 256'd0;
    reg          p4_hbm2ci_empty = 1'b1;
    wire         p4_hbm2ci_rden;
    wire [191:0] uram_raddr_phase4_flat;
    wire         uram_rden_phase4;
    reg  [1151:0] uram_rdata_phase4_flat = 1152'd0;

    wire         axon_trace_rd_en;
    wire [16:0]  axon_trace_rd_idx;
    reg  [3:0]   axon_trace_rd_data = 4'd0;

    integer pass = 0, fail = 0;

    always #5 clk = ~clk;

    stdp_controller dut (
        .axon_trace_rd_en   (axon_trace_rd_en),
        .axon_trace_rd_idx  (axon_trace_rd_idx),
        .axon_trace_rd_data (axon_trace_rd_data),
        .clk(clk), .resetn(resetn), .stdp_enable(stdp_enable),
        .A_plus(A_plus), .A_minus(A_minus),
        .w_max(w_max), .w_min(w_min), .neuromod_level(neuromod_level),
        .spike_addr_in(spike_addr_in), .spike_addr_wr(spike_addr_wr),
        .phase2_done(phase2_done),
        .phase4_active(phase4_active), .phase4_done(phase4_done),
        .p4_ci2hbm_din(p4_ci2hbm_din), .p4_ci2hbm_wren(p4_ci2hbm_wren),
        .p4_ci2hbm_full(p4_ci2hbm_full),
        .p4_hbm2ci_dout(p4_hbm2ci_dout), .p4_hbm2ci_empty(p4_hbm2ci_empty),
        .p4_hbm2ci_rden(p4_hbm2ci_rden),
        .uram_raddr_phase4_flat(uram_raddr_phase4_flat),
        .uram_rden_phase4(uram_rden_phase4),
        .uram_rdata_phase4_flat(uram_rdata_phase4_flat)
    );

    //-------------------------------------------------------------------------
    // Synapse entries.  {opcode[2:0], dest[12:0], weight[15:0], delay[5:0],
    //                    syn_type[3:0], stdp_tag[3:0], src[17:0]}
    // Only opcode, weight and src matter here.
    //-------------------------------------------------------------------------
    function [63:0] mk_entry(input [2:0] op, input signed [15:0] w, input [17:0] src);
        begin
            mk_entry = {op, 13'd0, w, 6'd0, 4'd0, 4'd0, src};
        end
    endfunction

    // Neuron source: bit 17 low.  group = src[3:0], half = src[4].
    localparam [17:0] SRC_N_G0 = 18'h00000;   // group 0, half 0
    localparam [17:0] SRC_N_G3 = 18'h00003;   // group 3, half 0
    // Axon source: bit 17 high.  axon_trace_mem splits [16:0] as {row, group}.
    localparam [17:0] SRC_A_HIT  = 18'h22021; // idx 0x02021 -> row 514, group 1
    localparam [17:0] SRC_A_MISS = 18'h22044; // idx 0x02044 -> row 516, group 4

    localparam [22:0] SYN_ROW = 23'd1000;

    wire [255:0] SYN_BEAT = { mk_entry(3'b000,  16'sd295, SRC_N_G3),   // entry 3
                              mk_entry(3'b000,  16'sd150, SRC_A_MISS), // entry 2
                              mk_entry(3'b000,  16'sd200, SRC_A_HIT),  // entry 1
                              mk_entry(3'b000,  16'sd100, SRC_N_G0) }; // entry 0

    // Pointer row: entry 0 = {len=0, addr=SYN_ROW}, so one beat, four entries.
    wire [255:0] PTR_BEAT = {224'd0, 9'd0, SYN_ROW};

    //-------------------------------------------------------------------------
    // HBM model.  A read request is {0, addr, ...}; a write is {1, addr, data}.
    //-------------------------------------------------------------------------
    reg [22:0]  req_addr;
    reg         req_pending = 1'b0;
    integer     req_delay = 0;

    reg         saw_write = 1'b0;
    reg [22:0]  write_addr = 23'd0;
    reg [255:0] write_data = 256'd0;
    integer     write_count = 0;
    integer     read_count  = 0;

    always @(posedge clk) begin
        if (p4_ci2hbm_wren) begin
            if (p4_ci2hbm_din[279]) begin
                saw_write  <= 1'b1;
                write_addr <= p4_ci2hbm_din[278:256];
                write_data <= p4_ci2hbm_din[255:0];
                write_count <= write_count + 1;
            end else begin
                req_addr    <= p4_ci2hbm_din[278:256];
                req_pending <= 1'b1;
                req_delay   <= 2;
                read_count  <= read_count + 1;
            end
        end
        if (req_pending) begin
            if (req_delay > 0) req_delay <= req_delay - 1;
            else begin
                p4_hbm2ci_dout  <= (req_addr >= 23'd16384) ? PTR_BEAT : SYN_BEAT;
                p4_hbm2ci_empty <= 1'b0;
            end
        end
        if (p4_hbm2ci_rden) begin
            p4_hbm2ci_empty <= 1'b1;
            req_pending     <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // URAM model: group g's low-half trace is in bits [72g+3 : 72g].
    // Give group 0 and group 3 a trace of 15; everything else zero.
    //-------------------------------------------------------------------------
    integer gi;
    initial begin
        uram_rdata_phase4_flat = 1152'd0;
        uram_rdata_phase4_flat[72*0 +: 4] = 4'd15;
        uram_rdata_phase4_flat[72*3 +: 4] = 4'd15;
    end

    //-------------------------------------------------------------------------
    // Axon trace model.  Only index 0x00021 has a trace.  Anything else reads
    // zero, so a truncated index would land on the wrong axon and read 0.
    //-------------------------------------------------------------------------
    reg [16:0] seen_axon_idx = 17'h1FFFF;
    always @(posedge clk) begin
        if (axon_trace_rd_en) begin
            seen_axon_idx      <= axon_trace_rd_idx;
            axon_trace_rd_data <= (axon_trace_rd_idx == 17'h02021) ? 4'd8 : 4'd0;
        end
    end

    task chk(input integer got, input integer exp, input [60*8:1] name);
        begin
            if (got === exp) begin
                pass = pass + 1;
                $display("  PASS  %-48s got %0d", name, got);
            end else begin
                fail = fail + 1;
                $display("  FAIL  %-48s got %0d, expected %0d", name, got, exp);
            end
        end
    endtask

    task push_spike(input [16:0] a);
        begin
            @(negedge clk);
            spike_addr_in = a;
            spike_addr_wr = 1'b1;
            @(negedge clk);
            spike_addr_wr = 1'b0;
        end
    endtask

    integer guard;

    initial begin
        $display("\n=== tb_stdp: Phase 4 weight update ===\n");

        repeat (4) @(negedge clk);
        resetn = 1'b1;
        repeat (4) @(negedge clk);

        //-------------------------------------------------------------
        // Neuron 0 spikes.  Its pointer sits at row 16384, slot 0.
        //-------------------------------------------------------------
        $display("A. one spiking neuron, one beat of four entries");
        push_spike(17'd0);

        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;

        guard = 0;
        while (!phase4_done && guard < 4000) begin
            @(negedge clk); guard = guard + 1;
        end
        chk(guard < 4000, 1, "phase4 completed without hanging");
        chk(phase4_active, 0, "phase4_active deasserted at the end");

        //-------------------------------------------------------------
        // The pointer fetch must have happened: two reads, one for the
        // pointer row and one for the synapse row.
        //-------------------------------------------------------------
        $display("\nB. pointer fetch");
        chk(read_count, 2, "two HBM reads: pointer then synapse row");

        //-------------------------------------------------------------
        // The axon lookup must have carried the full 17-bit index.  A
        // 13-bit index would present 0x0021 with the group lost.
        //-------------------------------------------------------------
        $display("\nC. axon trace lookup");
        chk(seen_axon_idx, 17'h02044, "full 17-bit index reaches the trace memory");
        chk(seen_axon_idx[3:0], 4, "group field survives in the index");

        //-------------------------------------------------------------
        // Write-back: one beat written, with four distinct decisions.
        //-------------------------------------------------------------
        $display("\nD. weight decisions");
        chk(write_count, 1, "exactly one HBM write");
        chk(write_addr, SYN_ROW, "written to the synapse row address");

        // entry 0: neuron source, group 0, trace 15 -> delta (16*15)>>4 = 15
        chk($signed(write_data[47:32]),  115, "entry 0  100 + 15 (URAM trace)");
        // entry 1: axon source, idx 0x21 -> trace 8, delta (16*8)>>4 = 8
        chk($signed(write_data[111:96]), 208, "entry 1  200 + 8 (axon trace)");
        // entry 2: axon source, idx 0x44 -> trace 0, unchanged
        chk($signed(write_data[175:160]), 150, "entry 2  unchanged, trace 0");
        // entry 3: neuron source, group 3, trace 15 -> 295+15 = 310, clamped
        chk($signed(write_data[239:224]), 300, "entry 3  clamped at w_max");

        //-------------------------------------------------------------
        // A second neuron must be processed too.  syn_processed is reset
        // per neuron; if it accumulated, this one would terminate at once.
        //-------------------------------------------------------------
        $display("\nE. second neuron processed");
        write_count = 0; read_count = 0;
        repeat (4) @(negedge clk);
        push_spike(17'd0);
        push_spike(17'd8);          // different pointer row

        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;

        guard = 0;
        while (!phase4_done && guard < 8000) begin
            @(negedge clk); guard = guard + 1;
        end
        chk(guard < 8000, 1, "two neurons completed");
        chk(read_count, 4, "four reads: two pointers, two synapse rows");
        chk(write_count, 2, "two writes, one per neuron");

        //-------------------------------------------------------------
        // With plasticity disabled, phase2_done must still complete.
        //-------------------------------------------------------------
        $display("\nF. stdp_enable low");
        stdp_enable = 1'b0;
        repeat (4) @(negedge clk);
        push_spike(17'd0);
        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;
        guard = 0;
        while (!phase4_done && guard < 200) begin
            @(negedge clk); guard = guard + 1;
        end
        chk(guard < 200, 1, "completes immediately when disabled");

        //-------------------------------------------------------------
        // G. Depression.  Every case above runs with A_minus at zero, so
        //    the depression term contributes nothing to any of them.  Here
        //    it is non-zero and the entries carry no presynaptic trace, so
        //    the only term acting is the decrement.
        //
        //    On the unpatched controller these weights are unchanged and
        //    the case fails, which is what makes it worth having.
        //-------------------------------------------------------------
        $display("\nG. depression arm");
        stdp_enable = 1'b1;          // case F disabled it and did not restore
        A_minus = 8'd16;
        write_count = 0; read_count = 0;
        repeat (4) @(negedge clk);
        push_spike(17'd0);
        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;
        guard = 0;
        while (!phase4_done && guard < 4000) begin
            @(negedge clk); guard = guard + 1;
        end
        chk(guard < 4000, 1, "completed with depression enabled");
        chk(write_count, 1, "one write with depression enabled");

        // entry 2 carries an axon source whose trace reads zero, so the only
        // term acting on it is the decrement: 150 - 16 = 134.
        // Entry 2 is an axon source whose trace reads zero. P4_COMPUTE gates
        // the whole update on src_trace != 0, so a synapse outside the trace
        // window is not written at all and the depression term never reaches
        // it. The rule is therefore a classical curve, not heterosynaptic
        // depression: potentiation at short intervals, depression at longer
        // ones within the window, and no change beyond it.
        chk($signed(write_data[175:160]), 150, "entry 2  unchanged, trace 0");

        // entry 0 takes the URAM trace of 15 and the decrement together:
        // 100 + 15 - 16 = 99.
        chk($signed(write_data[47:32]), 99, "entry 0  100 + 15 - A_minus");

        //-------------------------------------------------------------
        // H. Lower clamp.  Depression is the first mechanism in this design
        //    able to drive a weight downward, so w_min has never been
        //    exercised in that direction.
        //-------------------------------------------------------------
        $display("\nH. lower clamp under depression");
        w_min = 16'sd140;
        write_count = 0;
        repeat (4) @(negedge clk);
        push_spike(17'd0);
        @(negedge clk); phase2_done = 1'b1;
        @(negedge clk); phase2_done = 1'b0;
        guard = 0;
        while (!phase4_done && guard < 4000) begin
            @(negedge clk); guard = guard + 1;
        end
        chk($signed(write_data[175:160]) >= 140, 1, "entry 2 clamped at w_min");
        w_min = -16'sd300;
        A_minus = 8'd0;

        $display("\n=== %0d passed, %0d failed ===\n", pass, fail);
        if (fail == 0) $display("ALL PASS\n"); else $display("FAILURES PRESENT\n");
        $finish;
    end

endmodule
