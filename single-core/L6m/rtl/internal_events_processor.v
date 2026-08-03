`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////////////
// INTERNAL EVENTS PROCESSOR - NOISE BUG FIX
////////////////////////////////////////////////////////////////////////////////////////
// 
// NOISE SHIFT FIX:
//   Old behavior: shift=0 meant no noise, shift>17 meant left-shifted noise
//   New behavior: shift=0 means unshifted noise, shift<0 (i.e., shift[5]=1) disables noise
//                 shift=+15 means large noise (left shift by 15)
//                 shift=-17 (6'b101111) means no noise
//
// shift_param is 6-bit signed:
//   Positive values (0 to 31): left shift PRBS (larger noise)
//   Negative values (-1 to -32): right shift PRBS (smaller noise)
//   Values <= -17: effectively zero noise
//
////////////////////////////////////////////////////////////////////////////////////////

module internal_events_processor(
    input resetn,
    input clk,
    
    // for debugging
    input [16:0] num_outputs,
    input signed [35:0] threshold,
    
    input            exec_run,
    input            exec_bram_phase1_done,
    output reg       exec_uram_phase1_ready,
    input    [511:0] exec_hbm_rdata,
    input            exec_hbm_rvalidready,
    
    output wire                 hbm2iep_rden,
    
    output reg [15:0] exec_uram_spiked,
    output reg       exec_uram_phase0_done,
    output reg       exec_uram_phase1_done,
    output reg       exec_uram_phase2_done,
    input            exec_hbm_rx_phase2_done,
    input      [1:0] exec_neuron_model,
    input      [5:0] leak,
    input      [5:0] shift,
    
    input                      ci2iep_empty,
    input          [1+17+35:0] ci2iep_dout,
    output reg                 ci2iep_rden,
    input                      iep2ci_full,
    output reg       [17+35:0] iep2ci_din,
    output reg                 iep2ci_wren,
    
    output reg [11:0]   uram_raddr_0,
    output reg [11:0]   uram_raddr_1,
    output reg [11:0]   uram_raddr_2,
    output reg [11:0]   uram_raddr_3,
    output reg [11:0]   uram_raddr_4,
    output reg [11:0]   uram_raddr_5,
    output reg [11:0]   uram_raddr_6,
    output reg [11:0]   uram_raddr_7,
    output reg [11:0]   uram_raddr_8,
    output reg [11:0]   uram_raddr_9,
    output reg [11:0]   uram_raddr_10,
    output reg [11:0]   uram_raddr_11,
    output reg [11:0]   uram_raddr_12,
    output reg [11:0]   uram_raddr_13,
    output reg [11:0]   uram_raddr_14,
    output reg [11:0]   uram_raddr_15,
    output reg          uram_rden_0,
    output reg          uram_rden_1,
    output reg          uram_rden_2,
    output reg          uram_rden_3,
    output reg          uram_rden_4,
    output reg          uram_rden_5,
    output reg          uram_rden_6,
    output reg          uram_rden_7,
    output reg          uram_rden_8,
    output reg          uram_rden_9,
    output reg          uram_rden_10,
    output reg          uram_rden_11,
    output reg          uram_rden_12,
    output reg          uram_rden_13,
    output reg          uram_rden_14,
    output reg          uram_rden_15,
    input [71:0] uram_rdata_0,
    input [71:0] uram_rdata_1,
    input [71:0] uram_rdata_2,
    input [71:0] uram_rdata_3,
    input [71:0] uram_rdata_4,
    input [71:0] uram_rdata_5,
    input [71:0] uram_rdata_6,
    input [71:0] uram_rdata_7,
    input [71:0] uram_rdata_8,
    input [71:0] uram_rdata_9,
    input [71:0] uram_rdata_10,
    input [71:0] uram_rdata_11,
    input [71:0] uram_rdata_12,
    input [71:0] uram_rdata_13,
    input [71:0] uram_rdata_14,
    input [71:0] uram_rdata_15,
    output [11:0]   uram_waddr_0,
    output [11:0]   uram_waddr_1,
    output [11:0]   uram_waddr_2,
    output [11:0]   uram_waddr_3,
    output [11:0]   uram_waddr_4,
    output [11:0]   uram_waddr_5,
    output [11:0]   uram_waddr_6,
    output [11:0]   uram_waddr_7,
    output [11:0]   uram_waddr_8,
    output [11:0]   uram_waddr_9,
    output [11:0]   uram_waddr_10,
    output [11:0]   uram_waddr_11,
    output [11:0]   uram_waddr_12,
    output [11:0]   uram_waddr_13,
    output [11:0]   uram_waddr_14,
    output [11:0]   uram_waddr_15,
    output [71:0]   uram_wdata_0,
    output [71:0]   uram_wdata_1,
    output [71:0]   uram_wdata_2,
    output [71:0]   uram_wdata_3,
    output [71:0]   uram_wdata_4,
    output [71:0]   uram_wdata_5,
    output [71:0]   uram_wdata_6,
    output [71:0]   uram_wdata_7,
    output [71:0]   uram_wdata_8,
    output [71:0]   uram_wdata_9,
    output [71:0]   uram_wdata_10,
    output [71:0]   uram_wdata_11,
    output [71:0]   uram_wdata_12,
    output [71:0]   uram_wdata_13,
    output [71:0]   uram_wdata_14,
    output [71:0]   uram_wdata_15,
    output          uram_wren_0,
    output          uram_wren_1,
    output          uram_wren_2,
    output          uram_wren_3,
    output          uram_wren_4,
    output          uram_wren_5,
    output          uram_wren_6,
    output          uram_wren_7,
    output          uram_wren_8,
    output          uram_wren_9,
    output          uram_wren_10,
    output          uram_wren_11,
    output          uram_wren_12,
    output          uram_wren_13,
    output          uram_wren_14,
    output          uram_wren_15,
    
    output   [3:0]  iep_curr_state,
    output   [12:0] curr_uram_waddr,
    
    output reg [3:0] rd_addr_neuron_param_mem,
    input [83:0] dout_neuron_param_mem,
    
    // Watchdog and error outputs
    output reg       iep_watchdog_error,
    output reg       iep_uram_out_of_range
);

//////////////////
// DECLARATIONS //
//////////////////

wire [12:0] URAM_ADDR_LIMIT;
reg [3:0] microphase_ctr;
wire [3:0] MICROPHASE_LIMIT;
wire [8:0] MICROPHASE_MOD;
wire [8:0] uram_microphase_addr_limit;
wire  [3:0] SET_GROUP;
wire [12:0] SET_ROW;

reg [3:0] SET_GROUP_reg;
reg [12:0] SET_ROW_reg;

reg [12:0]  uram_raddr;
reg         uram_rden;

reg [12:0] uram_waddr [15:0];
reg [11:0] uram_waddr_reg [15:0];  
reg signed [71:0] uram_wdata_reg [15:0];
reg  [15:0] uram_wren;

reg uram_addr_rst, uram_addr_inc;

reg [511:0] exec_hbm_rdata_reg;

reg [11:0] uram_init_addr;
reg        uram_init_done;
reg        uram_init_wren;

// URAM reinit: detect when a new network is loaded by monitoring num_outputs changes
reg        uram_reinit_needed;
reg        uram_reinit_active;  // distinguishes power-on init from reinit
reg [16:0] num_outputs_prev;
reg signed [35:0] threshold_prev;
reg [1:0]  model_prev;
reg [5:0]  shift_prev;
reg [5:0]  leak_prev;

reg signed [15:0] exec_hbm_rdata_reg_arr[15:0];
wire signed [34:0] exec_hbm_rdata_reg_signext[15:0];

reg [71:0] uram_wdata[15:0];

assign uram_wdata_0 = uram_wdata[0];
assign uram_wdata_1 = uram_wdata[1];
assign uram_wdata_2 = uram_wdata[2];
assign uram_wdata_3 = uram_wdata[3];
assign uram_wdata_4 = uram_wdata[4];
assign uram_wdata_5 = uram_wdata[5];
assign uram_wdata_6 = uram_wdata[6];
assign uram_wdata_7 = uram_wdata[7];
assign uram_wdata_8 = uram_wdata[8];
assign uram_wdata_9 = uram_wdata[9];
assign uram_wdata_10 = uram_wdata[10];
assign uram_wdata_11 = uram_wdata[11];
assign uram_wdata_12 = uram_wdata[12];
assign uram_wdata_13 = uram_wdata[13];
assign uram_wdata_14 = uram_wdata[14];
assign uram_wdata_15 = uram_wdata[15];

// State machine
reg [3:0] curr_state, next_state;
localparam [3:0] STATE_RESET                 = 4'd0;
localparam [3:0] STATE_IDLE                  = 4'd1;
localparam [3:0] STATE_PHASE0_READ_SPIKES    = 4'd2;
localparam [3:0] STATE_PHASE0_DONE           = 4'd3;
localparam [3:0] STATE_PHASE0_DONE_WAIT      = 4'd4;
localparam [3:0] STATE_FILL_PIPE_PHASE1      = 4'd5;
localparam [3:0] STATE_WAIT_BRAM_PHASE1_DONE = 4'd6;
localparam [3:0] STATE_PUSH_PTR_FIFO         = 4'd7;
localparam [3:0] STATE_PHASE1_DONE           = 4'd8;
localparam [3:0] STATE_POP_PTR_FIFO          = 4'd9;
localparam [3:0] STATE_PHASE2_DONE           = 4'd10;
localparam [3:0] STATE_READ_URAM_0           = 4'd11;
localparam [3:0] STATE_READ_URAM_1           = 4'd12;
localparam [3:0] STATE_WRITE_URAM            = 4'd13;
localparam [3:0] STATE_WRITE_URAM_0          = 4'd14;
localparam [3:0] STATE_INIT_URAM             = 4'd15;

assign iep_curr_state = curr_state;

always @(posedge clk) begin
    if (~resetn) curr_state <= STATE_RESET;
    else         curr_state <= next_state;
end

//=========================================================================
// IEP Watchdog Timer - detects hangs in any state
// Resets on every state transition. Fires at 50M cycles (~111ms at 450MHz).
// Also detects URAM address out of range.
// These are internal regs - no new output ports required.
//=========================================================================
reg [25:0] watchdog_ctr;  // 26-bit: max 67M cycles
localparam [25:0] WATCHDOG_LIMIT = 26'd50_000_000;
reg [3:0] prev_state;

always @(posedge clk) begin
    if (~resetn) begin
        watchdog_ctr <= 26'd0;
        prev_state <= STATE_RESET;
        iep_watchdog_error <= 1'b0;
        iep_uram_out_of_range <= 1'b0;
    end else begin
        prev_state <= curr_state;
        // Reset counter on any state transition or when idle
        if (curr_state != prev_state || curr_state == STATE_IDLE) begin
            watchdog_ctr <= 26'd0;
        end else if (watchdog_ctr < WATCHDOG_LIMIT) begin
            watchdog_ctr <= watchdog_ctr + 1'b1;
        end else begin
            iep_watchdog_error <= 1'b1;  // Sticky: latched until reset
        end
        // URAM address range check during phase0
        if (!exec_uram_phase0_done && (uram_raddr > URAM_ADDR_LIMIT + 13'd2))
            iep_uram_out_of_range <= 1'b1;
    end
end

always @(posedge clk) begin
    if (~resetn) begin
        uram_init_addr <= 12'd0;
        uram_init_done <= 1'b0;
        uram_reinit_needed <= 1'b0;
        uram_reinit_active <= 1'b0;
        num_outputs_prev <= 17'd0;
        threshold_prev <= 36'd0;
        model_prev <= 2'd0;
        shift_prev <= 6'd0;
        leak_prev <= 6'd0;
    end else begin
        // Detect ANY network parameter change → request URAM reinit
        if (num_outputs != num_outputs_prev || threshold != threshold_prev ||
            exec_neuron_model != model_prev || shift != shift_prev || leak != leak_prev) begin
            num_outputs_prev <= num_outputs;
            threshold_prev <= threshold;
            model_prev <= exec_neuron_model;
            shift_prev <= shift;
            leak_prev <= leak;
            uram_reinit_needed <= 1'b1;
        end
        
        if (curr_state == STATE_RESET) begin
            uram_init_addr <= 12'd0;
            uram_init_done <= 1'b0;
            uram_reinit_active <= 1'b0;
        end else if (curr_state == STATE_IDLE && next_state == STATE_INIT_URAM) begin
            // Entering INIT_URAM from IDLE (reinit path): reset init counter
            uram_init_addr <= 12'd0;
            uram_init_done <= 1'b0;
            uram_reinit_active <= 1'b1;
            uram_reinit_needed <= 1'b0;
        end else if (curr_state == STATE_INIT_URAM) begin
            if (uram_init_addr == 12'hFFF) begin
                uram_init_done <= 1'b1;
            end else begin
                uram_init_addr <= uram_init_addr + 1'b1;
            end
        end else if (curr_state != STATE_INIT_URAM) begin
            uram_reinit_active <= 1'b0;
        end
    end
end

genvar j;
generate 
    for (j=0; j<16;j=j+1) begin
        assign exec_hbm_rdata_reg_signext[j] = (exec_hbm_rdata_reg_arr[j][15]) ? {19'h7FFFF, exec_hbm_rdata_reg_arr[j]} : {19'h00000, exec_hbm_rdata_reg_arr[j]};
    end
endgenerate

reg exec_hbm_rvalidready_reg, exec_hbm_rvalidready_reg2;

reg [12:0]   uram_raddr_0_full;
reg [12:0]   uram_raddr_1_full;
reg [12:0]   uram_raddr_2_full;
reg [12:0]   uram_raddr_3_full;
reg [12:0]   uram_raddr_4_full;
reg [12:0]   uram_raddr_5_full;
reg [12:0]   uram_raddr_6_full;
reg [12:0]   uram_raddr_7_full;
reg [12:0]   uram_raddr_8_full;
reg [12:0]   uram_raddr_9_full;
reg [12:0]   uram_raddr_10_full;
reg [12:0]   uram_raddr_11_full;
reg [12:0]   uram_raddr_12_full;
reg [12:0]   uram_raddr_13_full;
reg [12:0]   uram_raddr_14_full;
reg [12:0]   uram_raddr_15_full;

reg [12:0]   uram_raddr_0_full_reg;
reg [12:0]   uram_raddr_1_full_reg;
reg [12:0]   uram_raddr_2_full_reg;
reg [12:0]   uram_raddr_3_full_reg;
reg [12:0]   uram_raddr_4_full_reg;
reg [12:0]   uram_raddr_5_full_reg;
reg [12:0]   uram_raddr_6_full_reg;
reg [12:0]   uram_raddr_7_full_reg;
reg [12:0]   uram_raddr_8_full_reg;
reg [12:0]   uram_raddr_9_full_reg;
reg [12:0]   uram_raddr_10_full_reg;
reg [12:0]   uram_raddr_11_full_reg;
reg [12:0]   uram_raddr_12_full_reg;
reg [12:0]   uram_raddr_13_full_reg;
reg [12:0]   uram_raddr_14_full_reg;
reg [12:0]   uram_raddr_15_full_reg;

reg signed [35:0] threshold_param;
reg      [1:0] exec_neuron_model_param;
reg      [5:0] leak_param;
reg signed [5:0] shift_param;  // CHANGED: Now signed for proper negative handling
// Feature 6: Refractory period - per-layer max loaded into per-neuron URAM counter on spike
reg      [2:0] refractory_max_param;
// Feature 1e: Synaptic delay - per-layer delay value for group B (delayed) synapses
reg      [3:0] delay_value_param;
// Feature 1e: Dual synapse enable - per-layer flag
reg            dual_synapse_en_param;
// Soft reset mode - per-layer: 0=hard reset (MP=0), 1=soft reset (MP=MP-threshold)
reg            soft_reset_en_param;

always @(posedge clk) begin
    if (~resetn) begin
        threshold_param <= threshold;
        exec_neuron_model_param <= exec_neuron_model;
        leak_param <= leak;
        shift_param <= shift;
        refractory_max_param <= 3'd0;
        delay_value_param <= 4'd0;
        dual_synapse_en_param <= 1'b0;
        soft_reset_en_param <= 1'b0;
    end else begin
        threshold_param <= dout_neuron_param_mem[69:34];
        exec_neuron_model_param <= dout_neuron_param_mem[71:70];
        shift_param <= dout_neuron_param_mem[77:72];
        leak_param <= dout_neuron_param_mem[83:78];
        // New fields from neuron_param_mem [20:0]
        delay_value_param <= dout_neuron_param_mem[20:17];
        refractory_max_param <= dout_neuron_param_mem[16:14];
        dual_synapse_en_param <= dout_neuron_param_mem[13];
        soft_reset_en_param <= dout_neuron_param_mem[8];
    end
end

parameter NEURON_GROUPS=16;

reg [71:0] uram_rmwdata[NEURON_GROUPS-1:0]; 
reg [35:0] uram_rmwdata_upper[NEURON_GROUPS-1:0]; 
reg [35:0] uram_rmwdata_lower[NEURON_GROUPS-1:0]; 

reg signed [34:0] uram_rmwmem_upper[NEURON_GROUPS-1:0]; 
reg signed [34:0] uram_rmwmem_lower[NEURON_GROUPS-1:0];
// Feature 6: Per-neuron refractory counters extracted from URAM half-word [34:32]
reg [2:0] refrac_ctr_upper[NEURON_GROUPS-1:0];
reg [2:0] refrac_ctr_lower[NEURON_GROUPS-1:0];

reg uram_wren_0_reg;
reg uram_wren_1_reg;
reg uram_wren_2_reg;
reg uram_wren_3_reg;
reg uram_wren_4_reg;
reg uram_wren_5_reg;
reg uram_wren_6_reg;
reg uram_wren_7_reg;
reg uram_wren_8_reg;
reg uram_wren_9_reg;
reg uram_wren_10_reg;
reg uram_wren_11_reg;
reg uram_wren_12_reg;
reg uram_wren_13_reg;
reg uram_wren_14_reg;
reg uram_wren_15_reg;

integer i;
always @(*) begin
    for (i = 0; i < NEURON_GROUPS; i=i+1) begin
        uram_rmwdata_upper[i] = uram_rmwdata[i][71:36];
        uram_rmwdata_lower[i] = uram_rmwdata[i][35:0];
        // URAM half-word layout: [35]=spike, [34:32]=refractory_counter, [31:0]=MP
        // uram_rmwmem extracts the full [34:0] for backward-compatible use in phase1/phase2
        // where only the spike bit [35] and accumulated MP matter.
        uram_rmwmem_upper[i] = uram_rmwdata_upper[i][34:0];
        uram_rmwmem_lower[i] = uram_rmwdata_lower[i][34:0];
        // Feature 6: Extract per-neuron refractory counters
        refrac_ctr_upper[i] = uram_rmwdata_upper[i][34:32];
        refrac_ctr_lower[i] = uram_rmwdata_lower[i][34:32];
    end
end

always @(*) begin
    if ((curr_state==STATE_WRITE_URAM) || (curr_state==STATE_WRITE_URAM_0) || (curr_state==STATE_READ_URAM_0) || (curr_state==STATE_READ_URAM_1)) begin
        uram_rmwdata[0] = ((uram_waddr_0==uram_waddr_reg[0]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_0 && uram_wren_0_reg)?uram_wdata_reg[0]:uram_rdata_0;
        uram_rmwdata[1] = ((uram_waddr_1==uram_waddr_reg[1]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_1 && uram_wren_1_reg)?uram_wdata_reg[1]:uram_rdata_1;
        uram_rmwdata[2] = ((uram_waddr_2==uram_waddr_reg[2]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_2 && uram_wren_2_reg)?uram_wdata_reg[2]:uram_rdata_2;
        uram_rmwdata[3] = ((uram_waddr_3==uram_waddr_reg[3]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_3 && uram_wren_3_reg)?uram_wdata_reg[3]:uram_rdata_3;
        uram_rmwdata[4] = ((uram_waddr_4==uram_waddr_reg[4]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_4 && uram_wren_4_reg)?uram_wdata_reg[4]:uram_rdata_4;
        uram_rmwdata[5] = ((uram_waddr_5==uram_waddr_reg[5]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_5 && uram_wren_5_reg)?uram_wdata_reg[5]:uram_rdata_5;
        uram_rmwdata[6] = ((uram_waddr_6==uram_waddr_reg[6]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_6 && uram_wren_6_reg)?uram_wdata_reg[6]:uram_rdata_6;
        uram_rmwdata[7] = ((uram_waddr_7==uram_waddr_reg[7]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_7 && uram_wren_7_reg)?uram_wdata_reg[7]:uram_rdata_7;
        uram_rmwdata[8] = ((uram_waddr_8==uram_waddr_reg[8]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_8 && uram_wren_8_reg)?uram_wdata_reg[8]:uram_rdata_8;
        uram_rmwdata[9] = ((uram_waddr_9==uram_waddr_reg[9]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_9 && uram_wren_9_reg)?uram_wdata_reg[9]:uram_rdata_9;
        uram_rmwdata[10] = ((uram_waddr_10==uram_waddr_reg[10]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_10 && uram_wren_10_reg)?uram_wdata_reg[10]:uram_rdata_10;
        uram_rmwdata[11] = ((uram_waddr_11==uram_waddr_reg[11]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_11 && uram_wren_11_reg)?uram_wdata_reg[11]:uram_rdata_11;
        uram_rmwdata[12] = ((uram_waddr_12==uram_waddr_reg[12]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_12 && uram_wren_12_reg)?uram_wdata_reg[12]:uram_rdata_12;
        uram_rmwdata[13] = ((uram_waddr_13==uram_waddr_reg[13]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_13 && uram_wren_13_reg)?uram_wdata_reg[13]:uram_rdata_13;
        uram_rmwdata[14] = ((uram_waddr_14==uram_waddr_reg[14]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_14 && uram_wren_14_reg)?uram_wdata_reg[14]:uram_rdata_14;
        uram_rmwdata[15] = ((uram_waddr_15==uram_waddr_reg[15]) && (SET_GROUP == SET_GROUP_reg) && uram_wren_15 && uram_wren_15_reg)?uram_wdata_reg[15]:uram_rdata_15;
    end
    else begin
        uram_rmwdata[0] = ((uram_waddr_0==uram_waddr_reg[0]) && uram_wren_0 && uram_wren_0_reg)?uram_wdata_reg[0]:uram_rdata_0;
        uram_rmwdata[1] = ((uram_waddr_1==uram_waddr_reg[1]) && uram_wren_1 && uram_wren_1_reg)?uram_wdata_reg[1]:uram_rdata_1;
        uram_rmwdata[2] = ((uram_waddr_2==uram_waddr_reg[2]) && uram_wren_2 && uram_wren_2_reg)?uram_wdata_reg[2]:uram_rdata_2;
        uram_rmwdata[3] = ((uram_waddr_3==uram_waddr_reg[3]) && uram_wren_3 && uram_wren_3_reg)?uram_wdata_reg[3]:uram_rdata_3;
        uram_rmwdata[4] = ((uram_waddr_4==uram_waddr_reg[4]) && uram_wren_4 && uram_wren_4_reg)?uram_wdata_reg[4]:uram_rdata_4;
        uram_rmwdata[5] = ((uram_waddr_5==uram_waddr_reg[5]) && uram_wren_5 && uram_wren_5_reg)?uram_wdata_reg[5]:uram_rdata_5;
        uram_rmwdata[6] = ((uram_waddr_6==uram_waddr_reg[6]) && uram_wren_6 && uram_wren_6_reg)?uram_wdata_reg[6]:uram_rdata_6;
        uram_rmwdata[7] = ((uram_waddr_7==uram_waddr_reg[7]) && uram_wren_7 && uram_wren_7_reg)?uram_wdata_reg[7]:uram_rdata_7;
        uram_rmwdata[8] = ((uram_waddr_8==uram_waddr_reg[8]) && uram_wren_8 && uram_wren_8_reg)?uram_wdata_reg[8]:uram_rdata_8;
        uram_rmwdata[9] = ((uram_waddr_9==uram_waddr_reg[9]) && uram_wren_9 && uram_wren_9_reg)?uram_wdata_reg[9]:uram_rdata_9;
        uram_rmwdata[10] = ((uram_waddr_10==uram_waddr_reg[10]) && uram_wren_10 && uram_wren_10_reg)?uram_wdata_reg[10]:uram_rdata_10;
        uram_rmwdata[11] = ((uram_waddr_11==uram_waddr_reg[11]) && uram_wren_11 && uram_wren_11_reg)?uram_wdata_reg[11]:uram_rdata_11;
        uram_rmwdata[12] = ((uram_waddr_12==uram_waddr_reg[12]) && uram_wren_12 && uram_wren_12_reg)?uram_wdata_reg[12]:uram_rdata_12;
        uram_rmwdata[13] = ((uram_waddr_13==uram_waddr_reg[13]) && uram_wren_13 && uram_wren_13_reg)?uram_wdata_reg[13]:uram_rdata_13;
        uram_rmwdata[14] = ((uram_waddr_14==uram_waddr_reg[14]) && uram_wren_14 && uram_wren_14_reg)?uram_wdata_reg[14]:uram_rdata_14;
        uram_rmwdata[15] = ((uram_waddr_15==uram_waddr_reg[15]) && uram_wren_15 && uram_wren_15_reg)?uram_wdata_reg[15]:uram_rdata_15;
    end
end

/////////////////
// ASSIGNMENTS //
/////////////////

assign URAM_ADDR_LIMIT = num_outputs[16:4];
assign MICROPHASE_LIMIT = URAM_ADDR_LIMIT[12:9];
assign MICROPHASE_MOD = URAM_ADDR_LIMIT[8:0];

assign uram_microphase_addr_limit = (microphase_ctr==MICROPHASE_LIMIT)?MICROPHASE_MOD:9'd511;

assign SET_GROUP = ci2iep_dout[52:49];
assign SET_ROW   = ci2iep_dout[48:36];

//////////////
// BEHAVIOR //
//////////////

always @(posedge clk) begin
    if (~resetn | uram_addr_rst)
        uram_raddr <= 13'd0;
    else if (uram_addr_inc)
        uram_raddr <= uram_raddr + 1'b1;
end

always @(*) begin
    if (~exec_uram_phase0_done || ~exec_uram_phase1_done) begin
        uram_raddr_0_full <= uram_raddr[12:0];
        uram_raddr_1_full <= uram_raddr[12:0];
        uram_raddr_2_full <= uram_raddr[12:0];
        uram_raddr_3_full <= uram_raddr[12:0];
        uram_raddr_4_full <= uram_raddr[12:0];
        uram_raddr_5_full <= uram_raddr[12:0];
        uram_raddr_6_full <= uram_raddr[12:0];
        uram_raddr_7_full <= uram_raddr[12:0];
        uram_raddr_8_full <= uram_raddr[12:0];
        uram_raddr_9_full <= uram_raddr[12:0];
        uram_raddr_10_full <= uram_raddr[12:0];
        uram_raddr_11_full <= uram_raddr[12:0];
        uram_raddr_12_full <= uram_raddr[12:0];
        uram_raddr_13_full <= uram_raddr[12:0];
        uram_raddr_14_full <= uram_raddr[12:0];
        uram_raddr_15_full <= uram_raddr[12:0];
    end else if (~exec_uram_phase2_done) begin
        uram_raddr_0_full <= exec_hbm_rdata[508:496];
        uram_raddr_1_full <= exec_hbm_rdata[476:464];
        uram_raddr_2_full <= exec_hbm_rdata[444:432];
        uram_raddr_3_full <= exec_hbm_rdata[412:400];
        uram_raddr_4_full <= exec_hbm_rdata[380:368];
        uram_raddr_5_full <= exec_hbm_rdata[348:336];
        uram_raddr_6_full <= exec_hbm_rdata[316:304];
        uram_raddr_7_full <= exec_hbm_rdata[284:272];
        uram_raddr_8_full <= exec_hbm_rdata[252:240];
        uram_raddr_9_full <= exec_hbm_rdata[220:208];
        uram_raddr_10_full <= exec_hbm_rdata[188:176];
        uram_raddr_11_full <= exec_hbm_rdata[156:144];
        uram_raddr_12_full <= exec_hbm_rdata[124:112];
        uram_raddr_13_full <= exec_hbm_rdata[092:080];
        uram_raddr_14_full <= exec_hbm_rdata[060:048];
        uram_raddr_15_full <= exec_hbm_rdata[028:016];
    end else begin
        uram_raddr_0_full <= SET_ROW;
        uram_raddr_1_full <= SET_ROW;
        uram_raddr_2_full <= SET_ROW;
        uram_raddr_3_full <= SET_ROW;
        uram_raddr_4_full <= SET_ROW;
        uram_raddr_5_full <= SET_ROW;
        uram_raddr_6_full <= SET_ROW;
        uram_raddr_7_full <= SET_ROW;
        uram_raddr_8_full <= SET_ROW;
        uram_raddr_9_full <= SET_ROW;
        uram_raddr_10_full <= SET_ROW;
        uram_raddr_11_full <= SET_ROW;
        uram_raddr_12_full <= SET_ROW;
        uram_raddr_13_full <= SET_ROW;
        uram_raddr_14_full <= SET_ROW;
        uram_raddr_15_full <= SET_ROW;
    end
end

always @(posedge clk) begin
     if (~resetn) begin
            uram_raddr_0_full_reg <= 13'd0;
            uram_raddr_1_full_reg <= 13'd0;
            uram_raddr_2_full_reg <= 13'd0;
            uram_raddr_3_full_reg <= 13'd0;
            uram_raddr_4_full_reg <= 13'd0;
            uram_raddr_5_full_reg <= 13'd0;
            uram_raddr_6_full_reg <= 13'd0;
            uram_raddr_7_full_reg <= 13'd0;
            uram_raddr_8_full_reg <= 13'd0;
            uram_raddr_9_full_reg <= 13'd0;
            uram_raddr_10_full_reg <= 13'd0;
            uram_raddr_11_full_reg <= 13'd0;
            uram_raddr_12_full_reg <= 13'd0;
            uram_raddr_13_full_reg <= 13'd0;
            uram_raddr_14_full_reg <= 13'd0;
            uram_raddr_15_full_reg <= 13'd0;   
            exec_hbm_rdata_reg <= 512'b0;   
     end else begin
            uram_raddr_0_full_reg <= uram_raddr_0_full;
            uram_raddr_1_full_reg <= uram_raddr_1_full;
            uram_raddr_2_full_reg <= uram_raddr_2_full;
            uram_raddr_3_full_reg <= uram_raddr_3_full;
            uram_raddr_4_full_reg <= uram_raddr_4_full;
            uram_raddr_5_full_reg <= uram_raddr_5_full;
            uram_raddr_6_full_reg <= uram_raddr_6_full;
            uram_raddr_7_full_reg <= uram_raddr_7_full;     
            uram_raddr_8_full_reg <= uram_raddr_8_full;
            uram_raddr_9_full_reg <= uram_raddr_9_full;
            uram_raddr_10_full_reg <= uram_raddr_10_full;
            uram_raddr_11_full_reg <= uram_raddr_11_full;
            uram_raddr_12_full_reg <= uram_raddr_12_full;
            uram_raddr_13_full_reg <= uram_raddr_13_full;
            uram_raddr_14_full_reg <= uram_raddr_14_full;
            uram_raddr_15_full_reg <= uram_raddr_15_full;  
            exec_hbm_rdata_reg <= exec_hbm_rdata;  
     end
end

always @(*) begin
    uram_rden_0 = uram_rden;
    uram_rden_1 = uram_rden;
    uram_rden_2 = uram_rden;
    uram_rden_3 = uram_rden;
    uram_rden_4 = uram_rden;
    uram_rden_5 = uram_rden;
    uram_rden_6 = uram_rden;
    uram_rden_7 = uram_rden; 
    uram_rden_8 = uram_rden;
    uram_rden_9 = uram_rden;
    uram_rden_10 = uram_rden;
    uram_rden_11 = uram_rden;
    uram_rden_12 = uram_rden;
    uram_rden_13 = uram_rden;
    uram_rden_14 = uram_rden;
    uram_rden_15 = uram_rden; 
    
    uram_raddr_0 = uram_raddr_0_full[12:1];
    uram_raddr_1 = uram_raddr_1_full[12:1];
    uram_raddr_2 = uram_raddr_2_full[12:1];
    uram_raddr_3 = uram_raddr_3_full[12:1];
    uram_raddr_4 = uram_raddr_4_full[12:1];
    uram_raddr_5 = uram_raddr_5_full[12:1];
    uram_raddr_6 = uram_raddr_6_full[12:1];
    uram_raddr_7 = uram_raddr_7_full[12:1];
    uram_raddr_8 = uram_raddr_8_full[12:1];
    uram_raddr_9 = uram_raddr_9_full[12:1];
    uram_raddr_10 = uram_raddr_10_full[12:1];
    uram_raddr_11 = uram_raddr_11_full[12:1];
    uram_raddr_12 = uram_raddr_12_full[12:1];
    uram_raddr_13 = uram_raddr_13_full[12:1];
    uram_raddr_14 = uram_raddr_14_full[12:1];
    uram_raddr_15 = uram_raddr_15_full[12:1];
end

always @(posedge clk) begin
    if (~resetn | uram_addr_rst) begin
        uram_waddr[0] <= 13'd0;
        uram_waddr[1] <= 13'd0;
        uram_waddr[2] <= 13'd0;
        uram_waddr[3] <= 13'd0;
        uram_waddr[4] <= 13'd0;
        uram_waddr[5] <= 13'd0;
        uram_waddr[6] <= 13'd0;
        uram_waddr[7] <= 13'd0;
        uram_waddr[8] <= 13'd0;
        uram_waddr[9] <= 13'd0;
        uram_waddr[10] <= 13'd0;
        uram_waddr[11] <= 13'd0;
        uram_waddr[12] <= 13'd0;
        uram_waddr[13] <= 13'd0;
        uram_waddr[14] <= 13'd0;
        uram_waddr[15] <= 13'd0;
    end else if (uram_rden) begin
        uram_waddr[0] <= uram_raddr_0_full;
        uram_waddr[1] <= uram_raddr_1_full;
        uram_waddr[2] <= uram_raddr_2_full;
        uram_waddr[3] <= uram_raddr_3_full;
        uram_waddr[4] <= uram_raddr_4_full;
        uram_waddr[5] <= uram_raddr_5_full;
        uram_waddr[6] <= uram_raddr_6_full;
        uram_waddr[7] <= uram_raddr_7_full;
        uram_waddr[8] <= uram_raddr_8_full;
        uram_waddr[9] <= uram_raddr_9_full;
        uram_waddr[10] <= uram_raddr_10_full;
        uram_waddr[11] <= uram_raddr_11_full;
        uram_waddr[12] <= uram_raddr_12_full;
        uram_waddr[13] <= uram_raddr_13_full;
        uram_waddr[14] <= uram_raddr_14_full;
        uram_waddr[15] <= uram_raddr_15_full;
    end
end

assign uram_waddr_0  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[0][12:1];
assign uram_waddr_1  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[1][12:1];
assign uram_waddr_2  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[2][12:1];
assign uram_waddr_3  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[3][12:1];
assign uram_waddr_4  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[4][12:1];
assign uram_waddr_5  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[5][12:1];
assign uram_waddr_6  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[6][12:1];
assign uram_waddr_7  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[7][12:1];
assign uram_waddr_8  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[8][12:1];
assign uram_waddr_9  = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[9][12:1];
assign uram_waddr_10 = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[10][12:1];
assign uram_waddr_11 = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[11][12:1];
assign uram_waddr_12 = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[12][12:1];
assign uram_waddr_13 = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[13][12:1];
assign uram_waddr_14 = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[14][12:1];
assign uram_waddr_15 = (curr_state==STATE_INIT_URAM) ? uram_init_addr : (curr_state==STATE_WRITE_URAM) ? SET_ROW_reg[12:1] : uram_waddr[15][12:1];

always @(posedge clk) begin
   if (exec_hbm_rvalidready) begin
      for(i=0; i< NEURON_GROUPS; i=i+1) begin
             if (exec_hbm_rdata[32*(16-i)-1]) exec_hbm_rdata_reg_arr[i] <= 16'd0;
             else                             exec_hbm_rdata_reg_arr[i] <= exec_hbm_rdata[32*(15-i)+15-:16];
      end
    end
end

always @(posedge clk) begin
    exec_hbm_rvalidready_reg <= exec_hbm_rvalidready;
    exec_hbm_rvalidready_reg2 <= exec_hbm_rvalidready_reg;
    uram_wdata_reg[0] <= uram_wdata_0;
    uram_wdata_reg[1] <= uram_wdata_1;
    uram_wdata_reg[2] <= uram_wdata_2;
    uram_wdata_reg[3] <= uram_wdata_3;
    uram_wdata_reg[4] <= uram_wdata_4;
    uram_wdata_reg[5] <= uram_wdata_5;
    uram_wdata_reg[6] <= uram_wdata_6;
    uram_wdata_reg[7] <= uram_wdata_7;
    uram_wdata_reg[8] <= uram_wdata_8;
    uram_wdata_reg[9] <= uram_wdata_9;
    uram_wdata_reg[10] <= uram_wdata_10;
    uram_wdata_reg[11] <= uram_wdata_11;
    uram_wdata_reg[12] <= uram_wdata_12;
    uram_wdata_reg[13] <= uram_wdata_13;
    uram_wdata_reg[14] <= uram_wdata_14;
    uram_wdata_reg[15] <= uram_wdata_15;
    uram_waddr_reg[0] <= uram_waddr_0;
    uram_waddr_reg[1] <= uram_waddr_1;
    uram_waddr_reg[2] <= uram_waddr_2;
    uram_waddr_reg[3] <= uram_waddr_3;
    uram_waddr_reg[4] <= uram_waddr_4;
    uram_waddr_reg[5] <= uram_waddr_5;
    uram_waddr_reg[6] <= uram_waddr_6;
    uram_waddr_reg[7] <= uram_waddr_7;
    uram_waddr_reg[8] <= uram_waddr_8;
    uram_waddr_reg[9] <= uram_waddr_9;
    uram_waddr_reg[10] <= uram_waddr_10;
    uram_waddr_reg[11] <= uram_waddr_11;
    uram_waddr_reg[12] <= uram_waddr_12;
    uram_waddr_reg[13] <= uram_waddr_13;
    uram_waddr_reg[14] <= uram_waddr_14;
    uram_waddr_reg[15] <= uram_waddr_15;
    SET_GROUP_reg <= SET_GROUP;
    SET_ROW_reg <= SET_ROW;
    uram_wren_0_reg <= uram_wren_0;
    uram_wren_1_reg <= uram_wren_1;
    uram_wren_2_reg <= uram_wren_2;
    uram_wren_3_reg <= uram_wren_3;
    uram_wren_4_reg <= uram_wren_4;
    uram_wren_5_reg <= uram_wren_5;
    uram_wren_6_reg <= uram_wren_6;
    uram_wren_7_reg <= uram_wren_7;
    uram_wren_8_reg <= uram_wren_8;
    uram_wren_9_reg <= uram_wren_9;
    uram_wren_10_reg <= uram_wren_10;
    uram_wren_11_reg <= uram_wren_11;
    uram_wren_12_reg <= uram_wren_12;
    uram_wren_13_reg <= uram_wren_13;
    uram_wren_14_reg <= uram_wren_14;
    uram_wren_15_reg <= uram_wren_15;
end

//=============================================================================
// PRBS NOISE GENERATION - FIXED VERSION
//=============================================================================
// New behavior:
//   shift_param = 0:   Unshifted noise (full 16-bit PRBS contribution)
//   shift_param > 0:   Left shift (larger noise, up to +15)
//   shift_param < 0:   Right shift (smaller noise)
//   shift_param <= -17: No noise (shifted to zero)
//
// shift_param is treated as 6-bit signed: range -32 to +31
//=============================================================================

wire [255:0] prbs;
reg [15:0] prbs_ng[NEURON_GROUPS-1:0];
reg [16:0] prbs_regularized[NEURON_GROUPS-1:0];
reg [34:0] prbs_shift[NEURON_GROUPS-1:0];
reg signed [35:0] prbs_shift_signext[NEURON_GROUPS-1:0];

// Compute absolute value of shift for shifting operations
wire [5:0] shift_abs;
wire shift_is_negative;
wire noise_disabled;

assign shift_is_negative = shift_param[5];  // MSB indicates negative (signed)
assign shift_abs = shift_is_negative ? (~shift_param + 1'b1) : shift_param;  // Absolute value
assign noise_disabled = shift_is_negative && (shift_abs >= 6'd17);  // shift <= -17 disables noise

prbs_512b prbs_inst (
    .clk(clk),
    .resetn(resetn),     
    .prbs (prbs)
);

always @(*) begin
    for (i = 0; i < NEURON_GROUPS; i=i+1) begin
        prbs_ng[i] = prbs[i*NEURON_GROUPS+:16];
        prbs_regularized[i] = 2*prbs_ng[i]+1;  // 17-bit value, MSB is sign
        
        // FIXED NOISE SHIFT LOGIC
        if (noise_disabled) begin
            // shift <= -17: No noise
            prbs_shift[i] = 35'd0;
        end else if (shift_is_negative) begin
            // Negative shift (but > -17): Right shift (smaller noise)
            // Use full 17-bit prbs_regularized so shift=-16 still yields nonzero
            prbs_shift[i] = {18'd0, prbs_regularized[i]} >> shift_abs;
        end else begin
            // Zero or positive shift: Left shift (larger noise)
            // shift=0: unshifted, shift=+15: large noise
            prbs_shift[i] = prbs_regularized[i][15:0] << shift_abs;
        end
        
        // Sign extension based on prbs_regularized MSB (sign bit)
        if (prbs_regularized[i][16]) begin
            // Negative PRBS value
            if (prbs_shift[i] == 0) begin
                prbs_shift_signext[i] = 36'sd0;  // Corner case: shifted to zero
            end else begin
                prbs_shift_signext[i][35] = 1'b1;  // Sign bit
                prbs_shift_signext[i][34:0] = 36'h800000000 - prbs_shift[i];
            end
        end else begin
            // Positive PRBS value
            prbs_shift_signext[i] = {1'b0, prbs_shift[i]};
        end
    end
end

//=============================================================================
// URAM WRITE DATA LOGIC (unchanged except uses fixed prbs_shift_signext)
//=============================================================================

always @(*) begin
    if (curr_state==STATE_INIT_URAM) begin
        for (i = 0; i < NEURON_GROUPS; i=i+1) begin
            uram_wdata[i] = 72'd0;
        end
    end else if (curr_state==STATE_WRITE_URAM) begin
        for (i = 0; i < NEURON_GROUPS; i=i+1) begin
            uram_wdata[i] = (uram_waddr[i][0])? {ci2iep_dout[35:0], uram_rmwdata_lower[i]}:{uram_rmwdata_upper[i],ci2iep_dout[35:0]};
        end
    end else if (!exec_uram_phase0_done && !exec_uram_phase1_done) begin
        for (i = 0; i < NEURON_GROUPS; i=i+1) begin
            if (uram_waddr[i][0]) begin
                // ODD address → upper half-word contains this neuron's data
                // URAM layout: [35]=spike, [34:32]=refrac_ctr, [31:0]=MP
                if (refrac_ctr_upper[i] > 3'd0) begin
                    // In refractory period - decrement counter, suppress spike
                    // Preserve current MP (which holds reset value: 0 for hard, MP-Vth for soft)
                    uram_wdata[i] = {1'b0, refrac_ctr_upper[i] - 3'd1, uram_rmwmem_upper[i][31:0], uram_rmwdata_lower[i]};
                end else if ((uram_rmwmem_upper[i][31:0] > threshold_param[31:0]) && ({uram_waddr[i], i[3:0]} < num_outputs)) begin
                    // Spike! Set spike bit, load refractory counter
                    // Soft reset: MP = MP - threshold. Hard reset: MP = 0.
                    if (soft_reset_en_param)
                        uram_wdata[i] = {1'b1, refractory_max_param, uram_rmwmem_upper[i][31:0] - threshold_param[31:0], uram_rmwdata_lower[i]};
                    else
                        uram_wdata[i] = {1'b1, refractory_max_param, 32'd0, uram_rmwdata_lower[i]};
                end else begin
                    // No spike, no refractory - apply neuron model as before
                    if (exec_neuron_model_param==2'd0) begin
                        uram_wdata[i] = {1'b0, 3'd0, 32'd0, uram_rmwdata_lower[i]};
                    end else if (exec_neuron_model_param==2'd1) begin
                        uram_wdata[i] = {1'b0, 3'd0, uram_rmwmem_upper[i][31:0] + 32'd1, uram_rmwdata_lower[i]};
                    end else if (exec_neuron_model_param==2'd2) begin
                        uram_wdata[i][71] = 1'b0;
                        uram_wdata[i][70:68] = 3'd0;
                        uram_wdata[i][67:36] = prbs_shift_signext[i][31:0] + uram_rmwmem_upper[i][31:0] - ($unsigned(uram_rmwmem_upper[i][31:0]) >> leak_param); 
                        uram_wdata[i][35:0] = uram_rmwdata_lower[i]; 
                    end else if (exec_neuron_model_param==2'd3) begin
                        uram_wdata[i] = {1'b0, 3'd0, uram_rmwmem_upper[i][31:0], uram_rmwdata_lower[i]};
                    end
                end
            end else begin
                // EVEN address → lower half-word contains this neuron's data
                if (refrac_ctr_lower[i] > 3'd0) begin
                    // In refractory period - decrement counter, suppress spike
                    // Preserve current MP (which holds reset value: 0 for hard, MP-Vth for soft)
                    uram_wdata[i] = {uram_rmwdata_upper[i], 1'b0, refrac_ctr_lower[i] - 3'd1, uram_rmwmem_lower[i][31:0]};
                end else if ((uram_rmwmem_lower[i][31:0] > threshold_param[31:0]) && ({uram_waddr[i], i[3:0]} < num_outputs)) begin
                    // Spike! Set spike bit, load refractory counter
                    // Soft reset: MP = MP - threshold. Hard reset: MP = 0.
                    if (soft_reset_en_param)
                        uram_wdata[i] = {uram_rmwdata_upper[i], 1'b1, refractory_max_param, uram_rmwmem_lower[i][31:0] - threshold_param[31:0]};
                    else
                        uram_wdata[i] = {uram_rmwdata_upper[i], 1'b1, refractory_max_param, 32'd0};
                end else begin
                    // No spike, no refractory
                    if (exec_neuron_model_param==2'd0) begin
                        uram_wdata[i] = {uram_rmwdata_upper[i], 1'b0, 3'd0, 32'd0};
                    end else if (exec_neuron_model_param==2'd1) begin
                        uram_wdata[i] = {uram_rmwdata_upper[i], 1'b0, 3'd0, uram_rmwmem_lower[i][31:0] + 32'd1};
                    end else if (exec_neuron_model_param==2'd2) begin
                        uram_wdata[i][71:36] = uram_rmwdata_upper[i]; 
                        uram_wdata[i][35] = 1'b0; 
                        uram_wdata[i][34:32] = 3'd0;
                        uram_wdata[i][31:0] = prbs_shift_signext[i][31:0] + uram_rmwmem_lower[i][31:0] - ($unsigned(uram_rmwmem_lower[i][31:0]) >> leak_param); 
                    end else if (exec_neuron_model_param==2'd3) begin
                        uram_wdata[i] = {uram_rmwdata_upper[i], 1'b0, 3'd0, uram_rmwmem_lower[i][31:0]};
                    end
                end
            end
        end 
    end else if (exec_uram_phase0_done && !exec_uram_phase1_done) begin
        for (i = 0; i < NEURON_GROUPS; i=i+1) begin
            if (uram_waddr[i][0]) begin
                if (uram_rmwdata_upper[i][35]==1'b1) 
                    // Clear spike bit [35], preserve refrac[34:32] and MP[31:0] via uram_rmwmem_upper[34:0]
                    uram_wdata[i] = {1'b0,uram_rmwmem_upper[i], uram_rmwdata_lower[i]};
                else 
                    uram_wdata[i] = {uram_rmwdata_upper[i], uram_rmwdata_lower[i]};
            end else begin
                if (uram_rmwdata_lower[i][35]==1'b1) 
                    uram_wdata[i] = {uram_rmwdata_upper[i], 1'b0, uram_rmwmem_lower[i]};
                else 
                    uram_wdata[i] = {uram_rmwdata_upper[i], uram_rmwdata_lower[i]};
            end
        end    
    end else if (exec_uram_phase1_done) begin
        for(i=0;i < NEURON_GROUPS; i=i+1) begin
            // Phase2: accumulate HBM weights into MP [31:0], preserve spike[35] and refrac_ctr[34:32]
            // During refractory: preserve current MP (holds reset value) - skip weight accumulation
            if (uram_waddr[i][0]) begin
                if (uram_rmwmem_upper[i][34:32] > 3'd0)
                    // Refractory: preserve MP at reset value, preserve refrac_ctr
                    uram_wdata[i] = {{1'b0, uram_rmwmem_upper[i][34:32], uram_rmwmem_upper[i][31:0]}, uram_rmwdata_lower[i]};
                else
                    uram_wdata[i] = {{1'b0, uram_rmwmem_upper[i][34:32], uram_rmwmem_upper[i][31:0] + exec_hbm_rdata_reg_signext[i][31:0]}, uram_rmwdata_lower[i]};
            end else begin
                if (uram_rmwmem_lower[i][34:32] > 3'd0)
                    uram_wdata[i] = {uram_rmwdata_upper[i], {1'b0, uram_rmwmem_lower[i][34:32], uram_rmwmem_lower[i][31:0]}};
                else
                    uram_wdata[i] = {uram_rmwdata_upper[i], {1'b0, uram_rmwmem_lower[i][34:32], uram_rmwmem_lower[i][31:0] + exec_hbm_rdata_reg_signext[i][31:0]}};
            end
        end
    end
end

always @(posedge clk) begin
    if ((curr_state==STATE_READ_URAM_0) | (curr_state==STATE_READ_URAM_1) | (curr_state==STATE_WRITE_URAM_0)) begin
        uram_wren[0] <= 1'b0;
        uram_wren[1] <= 1'b0;
        uram_wren[2] <= 1'b0;
        uram_wren[3] <= 1'b0;
        uram_wren[4] <= 1'b0;
        uram_wren[5] <= 1'b0;
        uram_wren[6] <= 1'b0;
        uram_wren[7] <= 1'b0;
        uram_wren[8] <= 1'b0;
        uram_wren[9] <= 1'b0;
        uram_wren[10] <= 1'b0;
        uram_wren[11] <= 1'b0;
        uram_wren[12] <= 1'b0;
        uram_wren[13] <= 1'b0;
        uram_wren[14] <= 1'b0;
        uram_wren[15] <= 1'b0;
    end else begin
        uram_wren[0] = uram_rden_0;
        uram_wren[1] = uram_rden_1;
        uram_wren[2] = uram_rden_2;
        uram_wren[3] = uram_rden_3;
        uram_wren[4] = uram_rden_4;
        uram_wren[5] = uram_rden_5;
        uram_wren[6] = uram_rden_6;
        uram_wren[7] = uram_rden_7;
        uram_wren[8] = uram_rden_8;
        uram_wren[9] = uram_rden_9;
        uram_wren[10] = uram_rden_10;
        uram_wren[11] = uram_rden_11;
        uram_wren[12] = uram_rden_12;
        uram_wren[13] = uram_rden_13;
        uram_wren[14] = uram_rden_14;
        uram_wren[15] = uram_rden_15;
    end
end

assign uram_wren_0  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd0)  : uram_wren[0];
assign uram_wren_1  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd1)  : uram_wren[1];
assign uram_wren_2  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd2)  : uram_wren[2];
assign uram_wren_3  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd3)  : uram_wren[3];
assign uram_wren_4  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd4)  : uram_wren[4];
assign uram_wren_5  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd5)  : uram_wren[5];
assign uram_wren_6  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd6)  : uram_wren[6];
assign uram_wren_7  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd7)  : uram_wren[7];
assign uram_wren_8  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd8)  : uram_wren[8];
assign uram_wren_9  = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd9)  : uram_wren[9];
assign uram_wren_10 = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd10) : uram_wren[10];
assign uram_wren_11 = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd11) : uram_wren[11];
assign uram_wren_12 = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd12) : uram_wren[12];
assign uram_wren_13 = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd13) : uram_wren[13];
assign uram_wren_14 = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd14) : uram_wren[14];
assign uram_wren_15 = (curr_state==STATE_INIT_URAM) ? 1'b1 : (curr_state==STATE_WRITE_URAM) ? (SET_GROUP_reg==4'd15) : uram_wren[15];

reg [3:0] wait_cycle_neuron_param_mem; 
reg wait_cycle_neuron_param_rst;
reg wait_cycle_neuron_param_inc;
reg rd_addr_neuron_param_rst;
reg rd_addr_neuron_param_inc;

always @(posedge clk) begin
    if (~resetn) begin
        wait_cycle_neuron_param_mem <= 4'd0;
        rd_addr_neuron_param_mem <= 4'b0;
    end else begin
        if(wait_cycle_neuron_param_rst) wait_cycle_neuron_param_mem <= 4'd0;
        if(rd_addr_neuron_param_rst) rd_addr_neuron_param_mem <= 4'b0;
        if (wait_cycle_neuron_param_inc) wait_cycle_neuron_param_mem <= wait_cycle_neuron_param_mem + 1'b1;  
        if(rd_addr_neuron_param_inc) rd_addr_neuron_param_mem <= rd_addr_neuron_param_mem + 1'b1;
    end
end

always @(*) begin
    uram_rden     <= 1'b0;
    uram_addr_rst <= 1'b0;
    uram_addr_inc <= 1'b0;
    uram_init_wren <= 1'b0;
    
    ci2iep_rden <= 1'b0;
    iep2ci_wren <= 1'b0;
    
    next_state <= curr_state;
    
    wait_cycle_neuron_param_rst <= 1'b0;
    wait_cycle_neuron_param_inc <= 1'b0;
    rd_addr_neuron_param_rst <= 1'b0;
    rd_addr_neuron_param_inc <= 1'b0;
    
    case (curr_state)
        STATE_RESET: begin
            uram_addr_rst <= 1'b1;
            wait_cycle_neuron_param_rst <= 1'b1;
            rd_addr_neuron_param_rst <= 1'b1;
            next_state <= STATE_INIT_URAM;
        end
        
        STATE_INIT_URAM: begin
            uram_init_wren <= 1'b1;
            if (uram_init_done) begin
                uram_init_wren <= 1'b0;
                if (uram_reinit_active) begin
                    // Reinit complete: proceed to process the timestep
                    uram_addr_rst <= 1'b1;
                    wait_cycle_neuron_param_rst <= 1'b1;
                    rd_addr_neuron_param_rst <= 1'b1;
                    next_state <= STATE_PHASE0_READ_SPIKES;
                end else begin
                    // Power-on init: go to idle
                    next_state <= STATE_IDLE;
                end
            end
        end
        
        STATE_IDLE: begin
            if (exec_run && uram_reinit_needed) begin
                // New network detected: clear all URAMs before processing first timestep
                uram_addr_rst <= 1'b1;
                next_state <= STATE_INIT_URAM;
            end else if (exec_run) begin
                uram_addr_rst <= 1'b1;
                wait_cycle_neuron_param_rst <= 1'b1;
                rd_addr_neuron_param_rst <= 1'b1;
                next_state <= STATE_PHASE0_READ_SPIKES;
            end else if (exec_uram_phase2_done & ~ci2iep_empty) begin
                if (ci2iep_dout[53] == 1'b0)
                    next_state <= STATE_READ_URAM_0;
                else
                    next_state <= STATE_WRITE_URAM_0;
            end
        end
        STATE_READ_URAM_0: begin
            uram_rden <= 1'b1;
            next_state <= STATE_READ_URAM_1;
        end
        STATE_READ_URAM_1: begin
            if (~iep2ci_full) begin
                iep2ci_wren <= 1'b1;
                ci2iep_rden <= 1'b1;
                next_state <= STATE_IDLE;
            end
        end
        STATE_WRITE_URAM_0: begin
            uram_rden <= 1'b1;
            next_state <= STATE_WRITE_URAM;
        end
        STATE_WRITE_URAM: begin
            ci2iep_rden <= 1'b1;
            next_state <= STATE_IDLE;
        end
        STATE_PHASE0_READ_SPIKES: begin
            if((((uram_raddr_0_full != 0) && uram_raddr_0_full == dout_neuron_param_mem[33:21]) && (wait_cycle_neuron_param_mem == 0))) begin
                if (uram_raddr_0_full == URAM_ADDR_LIMIT) begin
                      uram_addr_inc <= 1'b1;
                      uram_rden <= 1'b1;
                      next_state <= STATE_PHASE0_DONE;
                end else begin
                    rd_addr_neuron_param_inc <= 1'b1;
                    wait_cycle_neuron_param_inc <= 1'b1;
                end
            end else if ((wait_cycle_neuron_param_mem != 0) && (wait_cycle_neuron_param_mem < 4)) begin
                wait_cycle_neuron_param_inc <= 1'b1;
            end else begin
                wait_cycle_neuron_param_rst <= 1'b1;
                uram_addr_inc <= 1'b1;
                uram_rden <= 1'b1;
                if (uram_waddr[0] == URAM_ADDR_LIMIT)
                      next_state <= STATE_PHASE0_DONE;
            end
        end
        STATE_PHASE0_DONE: begin
            next_state <= STATE_PHASE0_DONE_WAIT;
            rd_addr_neuron_param_rst <= 1'b1;
            uram_addr_rst <= 1'b1;
        end
        STATE_PHASE0_DONE_WAIT: begin
            next_state <= STATE_FILL_PIPE_PHASE1;
        end
        STATE_FILL_PIPE_PHASE1: begin
            if (uram_raddr < 14'd1) begin
                uram_rden <= 1'b1;
                uram_addr_inc <= 1'b1;
            end else begin
                next_state <= STATE_WAIT_BRAM_PHASE1_DONE;
            end
        end
        
        STATE_WAIT_BRAM_PHASE1_DONE: begin
            if (exec_bram_phase1_done)
                next_state <= STATE_PUSH_PTR_FIFO;
        end
        STATE_PUSH_PTR_FIFO: begin
            if (exec_hbm_rvalidready) begin
                uram_addr_inc <= 1'b1;
                if (uram_waddr[0] == microphase_ctr * 512 + uram_microphase_addr_limit) begin
                    next_state <= STATE_PHASE1_DONE;
                end else
                    uram_rden <= 1'b1;
            end 
        end
        STATE_PHASE1_DONE: begin
            next_state <= STATE_POP_PTR_FIFO;
        end
        STATE_POP_PTR_FIFO: begin
            if (exec_hbm_rvalidready) begin
                uram_rden <= 1'b1;
            end
            else if (exec_hbm_rx_phase2_done)
                next_state <= STATE_PHASE2_DONE;
        end
        STATE_PHASE2_DONE: begin
            if(microphase_ctr == MICROPHASE_LIMIT) next_state <= STATE_IDLE;
            else next_state <= STATE_WAIT_BRAM_PHASE1_DONE;
        end
        default: begin
            next_state <= STATE_RESET;
        end
    endcase
end

always @(*) begin
    case (SET_GROUP_reg)
        4'd0: iep2ci_din <= (uram_raddr_0_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[0]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[0]};
        4'd1: iep2ci_din <= (uram_raddr_1_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[1]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[1]};
        4'd2: iep2ci_din <= (uram_raddr_2_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[2]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[2]};
        4'd3: iep2ci_din <= (uram_raddr_3_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[3]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[3]};
        4'd4: iep2ci_din <= (uram_raddr_4_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[4]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[4]};
        4'd5: iep2ci_din <= (uram_raddr_5_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[5]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[5]};
        4'd6: iep2ci_din <= (uram_raddr_6_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[6]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[6]};
        4'd7: iep2ci_din <= (uram_raddr_7_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[7]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[7]};
        4'd8: iep2ci_din <= (uram_raddr_8_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[8]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[8]};
        4'd9: iep2ci_din <= (uram_raddr_9_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[9]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[9]};
        4'd10: iep2ci_din <= (uram_raddr_10_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[10]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[10]};
        4'd11: iep2ci_din <= (uram_raddr_11_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[11]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[11]};
        4'd12: iep2ci_din <= (uram_raddr_12_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[12]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[12]};
        4'd13: iep2ci_din <= (uram_raddr_13_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[13]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[13]};
        4'd14: iep2ci_din <= (uram_raddr_14_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[14]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[14]};
        4'd15: iep2ci_din <= (uram_raddr_15_full_reg[0])? {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_upper[15]}:{SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[15]};
        default: iep2ci_din <= {SET_GROUP_reg,SET_ROW_reg,uram_rmwdata_lower[0]};
    endcase
end

always @(posedge clk) begin
    if (~resetn) begin
        exec_uram_phase1_ready <= 1'b0;
        exec_uram_phase0_done  <= 1'b1;
        exec_uram_phase1_done  <= 1'b1;
        exec_uram_phase2_done  <= 1'b1;
    end else if (exec_run) begin
        exec_uram_phase1_ready <= 1'b0;
        exec_uram_phase0_done  <= 1'b0;
        exec_uram_phase1_done  <= 1'b0;
        exec_uram_phase2_done  <= 1'b0;
    end else if (curr_state == STATE_IDLE) begin
        microphase_ctr <= 4'b0;
        exec_uram_phase1_ready <= 1'b0;
        exec_uram_phase0_done  <= 1'b1;
        exec_uram_phase1_done  <= 1'b1;
        exec_uram_phase2_done  <= 1'b1;
    end else if (curr_state == STATE_WAIT_BRAM_PHASE1_DONE) begin
        exec_uram_phase1_ready <= 1'b0;
        exec_uram_phase1_done  <= 1'b0;
        exec_uram_phase2_done  <= 1'b0;
    end else if (curr_state == STATE_FILL_PIPE_PHASE1) 
        exec_uram_phase0_done  <= 1'b1;
    else if (curr_state == STATE_PUSH_PTR_FIFO)
        exec_uram_phase1_ready <= 1'b1;
    else if (curr_state == STATE_PHASE1_DONE) begin
        exec_uram_phase1_done  <= 1'b1;
        exec_uram_phase1_ready <= 1'b0;
    end else if (curr_state == STATE_PHASE2_DONE) begin
        exec_uram_phase2_done  <= 1'b1;
        if (microphase_ctr != MICROPHASE_LIMIT) microphase_ctr <= microphase_ctr+1'b1;
    end
end

always @(*) begin
    if (exec_uram_phase1_ready & !exec_uram_phase1_done) begin
        exec_uram_spiked[0] = (~uram_raddr_0_full[0])? (uram_rmwdata_upper[0][35]):(uram_rmwdata_lower[0][35]);
        exec_uram_spiked[1] = (~uram_raddr_1_full[0])? (uram_rmwdata_upper[1][35]):(uram_rmwdata_lower[1][35]);
        exec_uram_spiked[2] = (~uram_raddr_2_full[0])? (uram_rmwdata_upper[2][35]):(uram_rmwdata_lower[2][35]);
        exec_uram_spiked[3] = (~uram_raddr_3_full[0])? (uram_rmwdata_upper[3][35]):(uram_rmwdata_lower[3][35]);
        exec_uram_spiked[4] = (~uram_raddr_4_full[0])? (uram_rmwdata_upper[4][35]):(uram_rmwdata_lower[4][35]);
        exec_uram_spiked[5] = (~uram_raddr_5_full[0])? (uram_rmwdata_upper[5][35]):(uram_rmwdata_lower[5][35]);
        exec_uram_spiked[6] = (~uram_raddr_6_full[0])? (uram_rmwdata_upper[6][35]):(uram_rmwdata_lower[6][35]);
        exec_uram_spiked[7] = (~uram_raddr_7_full[0])? (uram_rmwdata_upper[7][35]):(uram_rmwdata_lower[7][35]);
        exec_uram_spiked[8] = (~uram_raddr_8_full[0])? (uram_rmwdata_upper[8][35]):(uram_rmwdata_lower[8][35]);
        exec_uram_spiked[9] = (~uram_raddr_9_full[0])? (uram_rmwdata_upper[9][35]):(uram_rmwdata_lower[9][35]);
        exec_uram_spiked[10] = (~uram_raddr_10_full[0])? (uram_rmwdata_upper[10][35]):(uram_rmwdata_lower[10][35]);
        exec_uram_spiked[11] = (~uram_raddr_11_full[0])? (uram_rmwdata_upper[11][35]):(uram_rmwdata_lower[11][35]);
        exec_uram_spiked[12] = (~uram_raddr_12_full[0])? (uram_rmwdata_upper[12][35]):(uram_rmwdata_lower[12][35]);
        exec_uram_spiked[13] = (~uram_raddr_13_full[0])? (uram_rmwdata_upper[13][35]):(uram_rmwdata_lower[13][35]);
        exec_uram_spiked[14] = (~uram_raddr_14_full[0])? (uram_rmwdata_upper[14][35]):(uram_rmwdata_lower[14][35]);
        exec_uram_spiked[15] = (~uram_raddr_15_full[0])? (uram_rmwdata_upper[15][35]):(uram_rmwdata_lower[15][35]);
        // Ghost neuron masking: suppress spikes from neuron addresses >= num_outputs
        // Use uram_waddr (matches the data in uram_rmwdata) not uram_raddr_i_full (which is 1 ahead)
        if ({uram_waddr[0], 4'd0} >= num_outputs) exec_uram_spiked[0] = 1'b0;
        if ({uram_waddr[1], 4'd1} >= num_outputs) exec_uram_spiked[1] = 1'b0;
        if ({uram_waddr[2], 4'd2} >= num_outputs) exec_uram_spiked[2] = 1'b0;
        if ({uram_waddr[3], 4'd3} >= num_outputs) exec_uram_spiked[3] = 1'b0;
        if ({uram_waddr[4], 4'd4} >= num_outputs) exec_uram_spiked[4] = 1'b0;
        if ({uram_waddr[5], 4'd5} >= num_outputs) exec_uram_spiked[5] = 1'b0;
        if ({uram_waddr[6], 4'd6} >= num_outputs) exec_uram_spiked[6] = 1'b0;
        if ({uram_waddr[7], 4'd7} >= num_outputs) exec_uram_spiked[7] = 1'b0;
        if ({uram_waddr[8], 4'd8} >= num_outputs) exec_uram_spiked[8] = 1'b0;
        if ({uram_waddr[9], 4'd9} >= num_outputs) exec_uram_spiked[9] = 1'b0;
        if ({uram_waddr[10], 4'd10} >= num_outputs) exec_uram_spiked[10] = 1'b0;
        if ({uram_waddr[11], 4'd11} >= num_outputs) exec_uram_spiked[11] = 1'b0;
        if ({uram_waddr[12], 4'd12} >= num_outputs) exec_uram_spiked[12] = 1'b0;
        if ({uram_waddr[13], 4'd13} >= num_outputs) exec_uram_spiked[13] = 1'b0;
        if ({uram_waddr[14], 4'd14} >= num_outputs) exec_uram_spiked[14] = 1'b0;
        if ({uram_waddr[15], 4'd15} >= num_outputs) exec_uram_spiked[15] = 1'b0;
    end else
        exec_uram_spiked = 16'd0;
end

assign hbm2iep_rden = exec_hbm_rvalidready;
assign curr_uram_waddr = uram_waddr[0];

endmodule