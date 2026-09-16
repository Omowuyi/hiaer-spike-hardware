`timescale 1ns / 1ps
module stdp_controller #(
    parameter SPIKE_FIFO_DEPTH = 4096,
    parameter SPIKE_ADDR_WIDTH = 17
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire        stdp_enable,
    input  wire [7:0]  A_plus,
    input  wire [7:0]  A_minus,
    input  wire signed [15:0] w_max,
    input  wire signed [15:0] w_min,
    input  wire [7:0]  neuromod_level,
    input  wire [SPIKE_ADDR_WIDTH-1:0] spike_addr_in,
    input  wire        spike_addr_wr,
    input  wire        phase2_done,
    output reg         phase4_active,
    output reg         phase4_done,
    output reg [279:0] p4_ci2hbm_din,
    output reg         p4_ci2hbm_wren,
    input  wire        p4_ci2hbm_full,
    input  wire [255:0] p4_hbm2ci_dout,
    input  wire         p4_hbm2ci_empty,
    output reg          p4_hbm2ci_rden,
    output reg  [191:0] uram_raddr_phase4_flat,
    output reg          uram_rden_phase4,
    input  wire [1151:0] uram_rdata_phase4_flat
);
    (* ram_style = "block" *)
    reg [SPIKE_ADDR_WIDTH-1:0] spike_fifo [0:SPIKE_FIFO_DEPTH-1];
    reg [11:0] spike_wr_ptr, spike_rd_ptr, spike_count;
    wire       spike_empty = (spike_count == 12'd0);
    always @(posedge clk) begin
        if (~resetn) begin spike_wr_ptr <= 12'd0; spike_count <= 12'd0; end
        else if (phase4_done) begin spike_wr_ptr <= 12'd0; spike_count <= 12'd0; end
        else if (spike_addr_wr && spike_count < SPIKE_FIFO_DEPTH) begin
            spike_fifo[spike_wr_ptr] <= spike_addr_in;
            spike_wr_ptr <= spike_wr_ptr + 12'd1;
            spike_count  <= spike_count + 12'd1;
        end
    end
    localparam P4_IDLE=4'd0, P4_CHECK_FIFO=4'd1, P4_ISSUE_READ=4'd2, P4_WAIT_READ=4'd3,
               P4_EXTRACT=4'd4, P4_URAM_READ=4'd5, P4_URAM_WAIT=4'd6, P4_COMPUTE=4'd7,
               P4_ISSUE_WRITE=4'd8, P4_NEXT_BEAT=4'd9, P4_DONE=4'd10;
    // FIX: syn_entry_count was compared against three times and NEVER
    // assigned -- P4_CHECK_FIFO used the spiked neuron's address directly as a
    // synapse row address, with no pointer fetch.  Two new states read the
    // neuron pointer first.  Codes 11 and 12 were free (0-10 used, 4-bit reg).
    localparam P4_PTR_READ = 4'd11, P4_PTR_WAIT = 4'd12;

    // Neuron pointer table: 8 x 32-bit pointers per 256-bit HBM row,
    // {len[8:0], addr[22:0]}, len = rows-1 (feeds AXI arlen directly).
    // Neuron N -> row NRN_BASE_ADDR + (N >> 3), entry (N & 7).
    localparam [22:0] NRN_BASE_ADDR = 23'd16384;   // 2^14, matches config.py
    // At 64-bit entry width there are 4 synapse entries per 256-bit row.
    localparam [3:0]  ENTRIES_PER_ROW = 4'd4;
    reg [2:0] ptr_sel;
    reg [3:0]  p4_state;
    reg [22:0] syn_base_addr;
    reg [8:0]  syn_entry_count;
    reg [8:0]  syn_processed;
    reg [22:0] syn_current_addr;
    reg [255:0] beat_data, modified_beat;
    reg [1:0]   entry_idx;
    reg         beat_modified;
    reg [22:0]  beat_addr;
    wire [63:0] current_entry_w = (entry_idx == 2'd0) ? beat_data[63:0] :
                                   (entry_idx == 2'd1) ? beat_data[127:64] :
                                   (entry_idx == 2'd2) ? beat_data[191:128] :
                                                          beat_data[255:192];
    // FIX: decode combinationally from current_entry_w.  The old code latched
    // current_entry non-blocking in P4_EXTRACT and decoded it in the same
    // cycle, so every decision used the PREVIOUS entry's fields.
    wire [2:0]  e_opcode  = current_entry_w[63:61];
    wire signed [15:0] e_weight = current_entry_w[47:32];
    wire [17:0] e_src     = current_entry_w[17:0];
    wire [3:0]  src_group = e_src[3:0];
    wire [11:0] src_row_b = e_src[16:5] + 12'd2048;
    wire        src_half  = e_src[4];
    reg  [3:0]  src_trace;
    wire [15:0] delta_w_raw = (A_plus * src_trace) >>> 4;
    wire signed [15:0] delta_w = $signed({1'b0, delta_w_raw[14:0]});
    always @(posedge clk) begin
        if (~resetn) begin
            p4_state <= P4_IDLE; phase4_active <= 1'b0; phase4_done <= 1'b0;
            p4_ci2hbm_wren <= 1'b0; p4_hbm2ci_rden <= 1'b0; uram_rden_phase4 <= 1'b0;
            uram_raddr_phase4_flat <= 192'd0; spike_rd_ptr <= 12'd0;
            beat_modified <= 1'b0; entry_idx <= 2'd0; syn_processed <= 9'd0;
            syn_entry_count <= 9'd0; syn_base_addr <= 23'd0; ptr_sel <= 3'd0;
        end else begin
            p4_ci2hbm_wren <= 1'b0; p4_hbm2ci_rden <= 1'b0;
            uram_rden_phase4 <= 1'b0; phase4_done <= 1'b0;
            case (p4_state)
                P4_IDLE: begin
                    phase4_active <= 1'b0; spike_rd_ptr <= 12'd0;
                    if (phase2_done && stdp_enable && !spike_empty) begin
                        phase4_active <= 1'b1; p4_state <= P4_CHECK_FIFO;
                    end else if (phase2_done) phase4_done <= 1'b1;
                end
                P4_CHECK_FIFO: begin
                    if (spike_rd_ptr >= spike_count) p4_state <= P4_DONE;
                    else begin
                        // FIX: syn_processed is per-neuron; it was only ever
                        // zeroed at reset, so it accumulated across neurons and
                        // every neuron after the first terminated immediately.
                        syn_processed <= 9'd0;
                        entry_idx     <= 2'd0;
                        beat_modified <= 1'b0;
                        ptr_sel <= spike_fifo[spike_rd_ptr][2:0];
                        syn_current_addr <= NRN_BASE_ADDR +
                                            {9'd0, spike_fifo[spike_rd_ptr][16:3]};
                        p4_state <= P4_PTR_READ;
                    end
                end

                // Read the 256-bit row holding this neuron's pointer.
                P4_PTR_READ: begin
                    if (!p4_ci2hbm_full) begin
                        p4_ci2hbm_din  <= {1'b0, syn_current_addr, 256'd0};
                        p4_ci2hbm_wren <= 1'b1;
                        p4_state <= P4_PTR_WAIT;
                    end
                end

                // Extract {len, addr} and turn len (rows-1) into an entry count.
                P4_PTR_WAIT: begin
                    if (!p4_hbm2ci_empty) begin
                        p4_hbm2ci_rden  <= 1'b1;
                        syn_base_addr   <= p4_hbm2ci_dout[32*ptr_sel +: 23];
                        syn_current_addr<= p4_hbm2ci_dout[32*ptr_sel +: 23];
                        syn_entry_count <= ({4'd0, p4_hbm2ci_dout[32*ptr_sel + 23 +: 9]}
                                            + 9'd1) * ENTRIES_PER_ROW;
                        p4_state <= P4_ISSUE_READ;
                    end
                end
                P4_ISSUE_READ: begin
                    if (!p4_ci2hbm_full) begin
                        p4_ci2hbm_din <= {1'b0, syn_current_addr, 256'd0};
                        p4_ci2hbm_wren <= 1'b1; p4_state <= P4_WAIT_READ;
                    end
                end
                P4_WAIT_READ: begin
                    if (!p4_hbm2ci_empty) begin
                        p4_hbm2ci_rden <= 1'b1; beat_data <= p4_hbm2ci_dout;
                        modified_beat <= p4_hbm2ci_dout; beat_addr <= syn_current_addr;
                        beat_modified <= 1'b0; entry_idx <= 2'd0; p4_state <= P4_EXTRACT;
                    end
                end
                P4_EXTRACT: begin
                    if (syn_processed < syn_entry_count && e_opcode == 3'b000) begin
                        uram_raddr_phase4_flat[12*src_group +: 12] <= src_row_b;
                        uram_rden_phase4 <= 1'b1; p4_state <= P4_URAM_READ;
                    end else if (syn_processed >= syn_entry_count) begin
                        if (beat_modified) p4_state <= P4_ISSUE_WRITE;
                        else begin spike_rd_ptr <= spike_rd_ptr + 12'd1; p4_state <= P4_CHECK_FIFO; end
                    end else begin
                        syn_processed <= syn_processed + 9'd1;
                        if (entry_idx == 2'd3) begin
                            if (beat_modified) p4_state <= P4_ISSUE_WRITE;
                            else p4_state <= P4_NEXT_BEAT;
                        end else begin entry_idx <= entry_idx + 2'd1; p4_state <= P4_EXTRACT; end
                    end
                end
                P4_URAM_READ: p4_state <= P4_URAM_WAIT;
                P4_URAM_WAIT: begin
                    if (src_half) src_trace <= uram_rdata_phase4_flat[72*src_group + 39 -: 4];
                    else          src_trace <= uram_rdata_phase4_flat[72*src_group + 3 -: 4];
                    p4_state <= P4_COMPUTE;
                end
                P4_COMPUTE: begin
                    if (src_trace != 4'd0) begin
                        if (e_weight + delta_w > w_max)
                            case (entry_idx)
                                2'd0: modified_beat[47:32] <= w_max;
                                2'd1: modified_beat[111:96] <= w_max;
                                2'd2: modified_beat[175:160] <= w_max;
                                2'd3: modified_beat[239:224] <= w_max;
                            endcase
                        else if (e_weight + delta_w < w_min)
                            case (entry_idx)
                                2'd0: modified_beat[47:32] <= w_min;
                                2'd1: modified_beat[111:96] <= w_min;
                                2'd2: modified_beat[175:160] <= w_min;
                                2'd3: modified_beat[239:224] <= w_min;
                            endcase
                        else
                            case (entry_idx)
                                2'd0: modified_beat[47:32] <= e_weight + delta_w;
                                2'd1: modified_beat[111:96] <= e_weight + delta_w;
                                2'd2: modified_beat[175:160] <= e_weight + delta_w;
                                2'd3: modified_beat[239:224] <= e_weight + delta_w;
                            endcase
                        beat_modified <= 1'b1;
                    end
                    syn_processed <= syn_processed + 9'd1;
                    if (entry_idx == 2'd3) begin
                        if (beat_modified) p4_state <= P4_ISSUE_WRITE;
                        else p4_state <= P4_NEXT_BEAT;
                    end else begin entry_idx <= entry_idx + 2'd1; p4_state <= P4_EXTRACT; end
                end
                P4_ISSUE_WRITE: begin
                    if (!p4_ci2hbm_full) begin
                        p4_ci2hbm_din <= {1'b1, beat_addr, modified_beat};
                        p4_ci2hbm_wren <= 1'b1; p4_state <= P4_NEXT_BEAT;
                    end
                end
                P4_NEXT_BEAT: begin
                    syn_current_addr <= syn_current_addr + 23'd1;
                    beat_modified <= 1'b0;
                    if (syn_processed >= syn_entry_count) begin
                        spike_rd_ptr <= spike_rd_ptr + 12'd1; p4_state <= P4_CHECK_FIFO;
                    end else p4_state <= P4_ISSUE_READ;
                end
                P4_DONE: begin phase4_active <= 1'b0; phase4_done <= 1'b1; p4_state <= P4_IDLE; end
                default: p4_state <= P4_IDLE;
            endcase
        end
    end
endmodule